defmodule Trader.Alpaca.Alpaca do
  require Logger
  use GenServer
  alias Trader.Db
  alias Trader.PriceUtil
  alias Trader.Alpaca.AlpacaApi, as: Api

  @initial_delay_ms 1_000

  def start_link([]) do
    if Application.get_env(:trader, __MODULE__)[:enable] do
      {:ok, pid} = GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
      Process.send_after(pid, :tick, @initial_delay_ms)
      {:ok, pid}
    else
      :ignore
    end
  end

  def execute_order_tree(%OrderTree{} = order_tree, strategy_name) do
    GenServer.call(__MODULE__, {:execute_order_tree, order_tree, strategy_name})
  end

  def current_price(ticker) do
    Api.call(:data, :GET, "v1/last/stocks/#{ticker}")
    |> Api.parse_response()
    |> Map.get("last", %{})
    |> Map.get("price", nil)
  end

  def current_positions() do
    stonks =
      Api.call(:trading, :GET, "v2/positions")
      |> Api.parse_response()
      |> Enum.filter(fn
        %{"side" => "long", "asset_class" => "us_equity"} -> true
        _ -> false
      end)
      |> Enum.map(fn %{"symbol" => ticker, "qty" => qty} ->
        ProductHolding.new(
          product:
            Product.new(
              product_type: :STONK,
              product_name: ticker
            ),
          amount: qty
        )
      end)

    cash_amount =
      Api.call(:trading, :GET, "v2/account")
      |> Api.parse_response()
      |> Map.get("cash")

    holdings = [
      ProductHolding.new(
        product:
          Product.new(
            product_type: :CURRENCY,
            product_name: "USD"
          ),
        amount: cash_amount
      )
      | stonks
    ]

    orders =
      Api.call(:trading, :GET, "v2/orders?status=open", retry: true)
      |> Api.parse_response()
      |> Enum.flat_map(&parse_order_from_exchange/1)

    ExchangePositions.new(holdings: holdings, orders: orders)
  end

  def current_positions(strategy_name) do
    GenServer.call(__MODULE__, {:get_strategy_positions, strategy_name})
  end

  def order_request_object(
        %Order{
          id: order_id,
          order_type: :MARKET_SELL,
          sell_product:
            %Product{
              product_name: ticker
            } = product,
          amount: amount_str
        } = order
      ) do
    %{
      symbol: ticker,
      qty: amount_str,
      side: "sell",
      type: "market",
      time_in_force: "gtc",
      client_order_id: order_id
    }
  end

  def order_request_object(
        %Order{
          id: order_id,
          order_type: :MARKET_BUY,
          buy_product:
            %Product{
              product_name: ticker
            } = product,
          amount: amount_str
        } = order
      ) do
    %{
      symbol: ticker,
      qty: amount_str,
      side: "buy",
      type: "market",
      time_in_force: "gtc",
      client_order_id: order_id
    }
  end

  def order_request_object(%Order{
        order_type: :CANCEL_ORDER,
        target_order_id: target,
        id: id
      }) do
    %{
      type: "cancel_order",
      target: target,
      client_order_id: id
    }
  end

  defp submit_order_request(%{type: "cancel_order", target: target_order_id, client_order_id: id}) do
    Logger.info("Order #{id}: Cancelling existing order #{target_order_id}")

    case Api.call(
           :trading,
           :GET,
           "v2/orders:by_client_order_id?client_order_id=#{target_order_id}"
         )
         |> Api.parse_response() do
      %{"id" => id} ->
        case Api.call(:trading, :DELETE, "v2/orders/#{id}") do
          %HTTPoison.Response{status_code: 204} ->
            :ok

          other ->
            Logger.warn("Order rejected: #{inspect(other)}")
            :error
        end

      _ ->
        Logger.warn("Attempted to cancel order #{target_order_id} that could not be found")
    end
  end

  defp submit_order_request(object) do
    Logger.info(
      "Placing #{object[:type]} #{object[:side]} order for #{object[:qty]} #{object[:symbol]}"
    )

    case Api.call(:trading, :POST, "v2/orders", object, retry: false) do
      %HTTPoison.Response{status_code: 200} ->
        :ok

      other ->
        Logger.warn("Order rejected: #{inspect(other)}")
        :error
    end
  end

  ####################
  # Server Callbacks #
  ####################

  @impl true
  def init(_state) do
    Logger.info("Cancelling all existing orders on Alpaca. Allocating initial positions:")
    %HTTPoison.Response{status_code: 207} = Api.call(:trading, :DELETE, "v2/orders", retry: true)
    exchange_positions = %ExchangePositions{holdings: holdings} = current_positions()
    strategy_positions = allocate_holdings_to_active_strategies(holdings)

    Trader.ExchangeUtil.print_positions("Exchange positions:", exchange_positions)

    for {name, positions} <- strategy_positions do
      Trader.ExchangeUtil.print_positions("Strategy #{name}:", positions)
    end

    {:ok,
     %{
       pending_orders: [],
       placed_orders: [],
       filled_orders: [],
       strategy_positions: strategy_positions
     }}
  end

  def handle_info(
        :tick,
        %{
          pending_orders: pending_orders,
          placed_orders: placed_orders,
          filled_orders: filled_orders,
          strategy_positions: strategy_positions
        } = state
      ) do
    exchange_filled =
      Api.call(:trading, :GET, "v2/orders?status=all", retry: true)
      |> Api.parse_response()
      |> Enum.filter(fn
        %{"status" => "filled"} -> true
        _ -> false
      end)
      |> Enum.map(fn %{"client_order_id" => id} -> id end)
      |> Enum.into(MapSet.new())

    # The exchange doesn't keep track of CANCEL_ORDER orders,
    # so add them here if their target order has indeed been cancelled
    filled =
      placed_orders
      |> Enum.filter(fn
        %Order{order_type: :CANCEL_ORDER} -> true
        _ -> false
      end)
      |> Enum.filter(fn %Order{target_order_id: target} -> order_cancelled?(target) end)
      |> Enum.map(fn %Order{id: id} -> id end)
      |> Enum.into(exchange_filled)

    {can_run, still_pending} =
      pending_orders
      |> Enum.split_with(fn %Order{parent_order_ids: parents} ->
        MapSet.size(MapSet.difference(MapSet.new(parents), filled)) == 0
      end)

    [accepted, rejected] =
      can_run
      |> Enum.map(fn o -> {o, submit_order_request(order_request_object(o))} end)
      |> Enum.split_with(fn
        {_, :ok} -> true
        {_, :error} -> false
      end)
      |> Tuple.to_list()
      |> Enum.map(fn os -> Enum.map(os, fn {o, _} -> o end) end)

    new_strategy_positions = update_strategy_positions(strategy_positions, accepted, filled)

    {now_filled, still_placed} =
      placed_orders
      |> Enum.split_with(fn %Order{id: id} -> id in filled end)

    pid = self()
    delay = Application.get_env(:trader, __MODULE__)[:milliseconds_per_tick]
    spawn(fn -> Process.send_after(pid, :tick, delay) end)

    {:noreply,
     %{
       state
       | pending_orders: remove_pending_with_rejected_parents(still_pending, rejected),
         placed_orders: still_placed ++ accepted,
         filled_orders: filled_orders ++ now_filled,
         strategy_positions: new_strategy_positions
     }}
  end

  def handle_call(
        {:execute_order_tree, %OrderTree{orders: orders}, strategy_name},
        _from,
        %{pending_orders: pending_orders} = state
      ) do
    tagged_orders =
      Enum.map(orders, fn order -> %Order{order | source_strategy: strategy_name} end)

    {:reply, :ok, %{state | pending_orders: pending_orders ++ tagged_orders}}
  end

  # def handle_call(
  #       {:execute_order_tree, %OrderTree{orders: orders}},
  #       _from,
  #       %{pending_orders: pending_orders} = state
  #     ) do
  #   # Actually, let's simplify this by just serializing all orders first
  #   # First, execute orders with no dependencies
  #   {base_orders, dependent_orders} =
  #     Enum.split_with(orders, fn %Order{parent_order_ids: parents} -> parents == [] end)

  #   [_accepted_ids, rejected_ids] =
  #     base_orders
  #     |> Enum.map(&order_request_object/1)
  #     |> Enum.map(fn o -> {Map.get(o, :client_order_id), submit_order_request(o)} end)
  #     |> Enum.split_with(fn
  #       {_, :ok} -> true
  #       {_, :error} -> false
  #     end)
  #     |> Tuple.to_list()
  #     |> Enum.map(fn os -> Enum.map(os, fn {id, _} -> id end) end)

  #   # TODO make this recursive to reject more deeply nested dependent orders
  #   accepted_dependent_orders =
  #     dependent_orders
  #     |> Enum.flat_map(fn %Order{id: id, parent_order_ids: parents} = order ->
  #       if MapSet.size(MapSet.intersection(MapSet.new(parents), MapSet.new(rejected_ids))) > 0 do
  #         Logger.warn("Order #{id} depends on a rejected order; discarding.")
  #         []
  #       else
  #         [order]
  #       end
  #     end)

  #   {:reply, :ok,
  #    %{
  #      state
  #      | pending_orders: pending_orders ++ accepted_dependent_orders
  #    }}
  # end

  def handle_call(
        {:get_strategy_positions, strategy_name},
        _from,
        %{strategy_positions: strategy_positions} = state
      ) do
    {:reply, Map.get(strategy_positions, strategy_name), state}
  end

  defp order_cancelled?(order_id) do
    # Call API by client order id and see if it is in state cancelled
  end

  def update_strategy_positions(strategy_positions, placed_orders, filled_order_ids) do
    strategy_positions
    |> Enum.map(fn {strategy_name, positions} ->
      {strategy_name,
       update_strategy_position(strategy_name, positions, placed_orders, filled_order_ids)}
    end)
    |> Enum.into(%{})
  end

  def update_strategy_position(
        strategy_name,
        %ExchangePositions{holdings: holdings, orders: orders},
        placed_orders,
        filled_order_ids
      ) do
    new_orders =
      placed_orders
      |> Enum.filter(fn %Order{source_strategy: s} -> s == strategy_name end)

    new_positions = %ExchangePositions{holdings: holdings, orders: orders ++ new_orders}

    Trader.ExchangeUtil.print_positions(
      "New positions for strategy #{strategy_name}:",
      new_positions
    )

    new_positions
  end

  def allocate_holdings_to_active_strategies(holdings) do
    for %TradingStrategy{name: strategy_name, capital_allocation: allocation} <-
          Trader.Strategies.active_strategies() do
      strategy_holdings =
        Enum.map(holdings, fn %ProductHolding{amount: qty} = holding ->
          %ProductHolding{holding | amount: "#{floor(PriceUtil.as_float(qty) * allocation)}"}
        end)

      {strategy_name, ExchangePositions.new(holdings: strategy_holdings)}
    end
    |> Enum.into(%{})
  end

  defp parse_order_from_exchange(%{
         "client_order_id" => id,
         "type" => "market",
         "symbol" => ticker,
         "side" => "sell",
         "qty" => amount_str
       }) do
    [
      Order.new(
        id: id,
        status: :PLACED,
        order_type: :MARKET_SELL,
        sell_product: Product.new(product_name: ticker, product_type: :STONK),
        amount: amount_str
      )
    ]
  end

  defp parse_order_from_exchange(%{
         "client_order_id" => id,
         "type" => "market",
         "symbol" => ticker,
         "side" => "buy",
         "qty" => amount_str
       }) do
    [
      Order.new(
        id: id,
        order_type: :MARKET_BUY,
        status: :PLACED,
        buy_product: Product.new(product_name: ticker, product_type: :STONK),
        amount: amount_str
      )
    ]
  end

  defp parse_order_from_exchange(order_object) do
    Logger.warn("Received unknown order type from Alpaca; skipping: #{inspect(order_object)}")
    []
  end

  def remove_pending_with_rejected_parents(pending_orders, rejected_orders) do
    rejected_ids =
      rejected_orders
      |> Enum.map(fn %Order{id: id} -> id end)
      |> Enum.into(MapSet.new())

    pending_orders
    |> Enum.filter(fn %Order{parent_order_ids: parents} ->
      MapSet.size(MapSet.intersection(MapSet.new(parents), rejected_ids)) == 0
    end)
  end
end
