defmodule Mix.Tasks.Trader.RegenerateMetadata do
  require Logger

  def run(_argv) do
    {:ok, _} = Application.ensure_all_started(:trader)

    Trader.Db.SqlStream.stream(
      "SELECT id, contents FROM data ORDER BY time ASC LIMIT $1 OFFSET $2",
      []
    )
    |> Flow.from_enumerable()
    |> Flow.map(&decode_contents/1)
    |> Flow.map(&update_selector/1)
    |> Flow.map(&update_price/1)
    |> Flow.run()
  end

  defp decode_contents([id, datapoint_str]) do
    [id, DataPoint.decode(datapoint_str)]
  end

  defp update_selector([id, datapoint]) do
    selector = Trader.Selectors.from_data_point(datapoint)
    Trader.Db.DataPoints.update_selector(id, selector)

    [id, datapoint]
  end

  defp update_price([id, datapoint]) do
    price =
      datapoint
      |> Trader.PriceUtil.price_from_data_point()
      |> Trader.PriceUtil.as_float()

    Trader.Db.DataPoints.update_price(id, price)

    [id, datapoint]
  end
end
