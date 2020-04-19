defmodule Trader.Db.DataPoints do
  alias Trader.Repo
  alias Trader.TimeUtil
  alias Ecto.Adapters.SQL

  def insert_datapoint(%DataPoint{} = datapoint) do
    ts = TimeUtil.int_to_datetime(datapoint.event_timestamp)
    type = DataPointType.mapping[datapoint.data_point_type]
    data = DataPoint.encode(datapoint)
    {:ok, _} = SQL.query(
      Repo,
      "INSERT INTO data (time, data_type, contents) VALUES ($1, $2, $3);",
      [ts, type, data]
    )    
  end
end
