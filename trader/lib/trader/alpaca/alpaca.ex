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

  def execute_order_tree(%OrderTree{} = order_tree) do
    GenServer.call(__MODULE__, {:execute_order_tree, order_tree})
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

    ExchangePositions.new(holdings: holdings)
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

  defp submit_order_request(object) do
    Logger.info(
      "Executing #{object[:type]} #{object[:side]} order for #{object[:qty]} #{object[:symbol]}"
    )

    case Api.call(:trading, :POST, "v2/orders", object) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
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
    {:ok, %{pending_orders: []}}
  end

  def handle_info(:tick, %{pending_orders: pending_orders} = state) do
    filled =
      Api.call(:trading, :GET, "v2/orders?status=all")
      |> Api.parse_response()
      |> Enum.filter(fn
        %{"status" => "filled"} -> true
        _ -> false
      end)
      |> Enum.map(fn %{"client_order_id" => id} -> id end)
      |> Enum.into(MapSet.new())

    {can_run, still_pending} =
      pending_orders
      |> Enum.split_with(fn %Order{parent_order_ids: parents} ->
        MapSet.size(MapSet.difference(MapSet.new(parents), filled)) == 0
      end)

    can_run
    |> Enum.map(&order_request_object/1)
    |> Enum.each(&submit_order_request/1)

    pid = self()
    delay = Application.get_env(:trader, __MODULE__)[:milliseconds_per_tick]
    spawn(fn -> Process.send_after(pid, :tick, delay) end)
    {:noreply, %{state | pending_orders: still_pending}}
  end

  def handle_call(
        {:execute_order_tree, %OrderTree{orders: orders}},
        _from,
        %{pending_orders: pending_orders} = state
      ) do
    # First, execute orders with no dependencies
    {base_orders, dependent_orders} =
      Enum.split_with(orders, fn %Order{parent_order_ids: parents} -> parents == [] end)

    [_accepted_ids, rejected_ids] =
      base_orders
      |> Enum.map(&order_request_object/1)
      |> Enum.map(fn o -> {Map.get(o, :client_order_id), submit_order_request(o)} end)
      |> Enum.split_with(fn
        {_, :ok} -> true
        {_, :error} -> false
      end)
      |> Tuple.to_list()
      |> Enum.map(fn os -> Enum.map(os, fn {id, _} -> id end) end)

    # TODO make this recursive to reject more deeply nested dependent orders
    accepted_dependent_orders =
      dependent_orders
      |> Enum.flat_map(fn %Order{id: id, parent_order_ids: parents} = order ->
        if MapSet.size(MapSet.intersection(MapSet.new(parents), MapSet.new(rejected_ids))) > 0 do
          Logger.warn("Order #{id} depends on a rejected order; discarding.")
          []
        else
          [order]
        end
      end)

    {:reply, :ok,
     %{
       state
       | pending_orders: pending_orders ++ accepted_dependent_orders
     }}
  end
end
