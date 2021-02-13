defmodule Trader.Orders.OrderCreation do
  require Logger
  alias Trader.Orders.StonkOrderCompiler

  def submit_orders(prediction, :backtest) do
    submit_orders(prediction, Trader.Alpaca.MockAlpaca, Trader.Coinbase.MockCoinbaseExchange)
  end

  def submit_orders(prediction, :live) do
    submit_orders(prediction, Trader.Alpaca.Alpaca, Trader.Coinbase.CoinbaseExchange)
  end

  def submit_orders(
        %Prediction{strategy_name: strategy_name, labels: labels} = prediction,
        stonk_exchange_module,
        fx_exchange_module
      ) do
    labels_by_type = Enum.group_by(labels, fn %Label{label_config: %{label_type: t}} -> t end)
    stonk_labels = Map.get(labels_by_type, :STONK_PRICE, [])
    fx_rate_labels = Map.get(labels_by_type, :FX_RATE, [])

    Logger.info(
      "Received prediction from #{strategy_name} with " <>
        "#{length(stonk_labels)} stonk price predictions and " <>
        "#{length(fx_rate_labels)} FX rate predictions."
    )

    submit_stonk_orders(%Prediction{prediction | labels: stonk_labels}, stonk_exchange_module)
    submit_fx_orders(%Prediction{prediction | labels: fx_rate_labels}, fx_exchange_module)
  end

  defp submit_stonk_orders(%Prediction{labels: []}, exchange) do
    :ok
  end

  defp submit_stonk_orders(%Prediction{labels: labels} = prediction, exchange) do
    current_positions = exchange.current_positions()

    current_label_prices =
      labels
      |> Enum.map(fn label -> label.label_config.stonk_price_config.ticker end)
      |> Enum.map(fn ticker -> {ticker, exchange.current_price(ticker)} end)
      |> Enum.into(%{})

    all_current_prices =
      current_positions.holdings
      |> Enum.filter(fn
        %ProductHolding{product: %Product{product_type: :STONK}} -> true
        _ -> false
      end)
      |> Enum.map(fn %ProductHolding{product: %Product{product_name: ticker}} ->
        {ticker, exchange.current_price(ticker)}
      end)
      |> Enum.into(current_label_prices)

    StonkOrderCompiler.get_orders(current_positions, all_current_prices, prediction)
    |> exchange.execute_order_tree
  end

  defp submit_fx_orders(%Prediction{labels: []}, exchange) do
    :ok
  end

  defp submit_fx_orders(%Prediction{labels: _}, exchange) do
    raise "Not implemented yet"
  end
end
