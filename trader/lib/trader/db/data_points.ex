defmodule Trader.Db.DataPoints do
  alias Trader.Repo
  alias Trader.TimeUtil
  alias Ecto.Adapters.SQL

  @origin ~U[2020-04-20 00:00:00Z]

  def insert_datapoint(%DataPoint{} = datapoint) do
    ts = TimeUtil.int_to_datetime(datapoint.event_timestamp)
    type = DataPointType.mapping()[datapoint.data_point_type]
    data = DataPoint.encode(datapoint)

    {:ok, _} =
      SQL.query(
        Repo,
        "INSERT INTO data (time, data_type, contents) VALUES ($1, $2, $3);",
        [ts, type, data]
      )
  end

  def get_available_windows(data_point_type, max_time_diff_ms, frame_width_ms) do
    type = DataPointType.mapping()[data_point_type]

    {:ok, %{rows: rows}} =
      SQL.query(
        Repo,
        "SELECT time_bucket('#{frame_width_ms} milliseconds', bucket, $1::timestamptz) AS frame FROM " <>
          "(SELECT time_bucket('#{max_time_diff_ms} milliseconds', time, $1::timestamptz) AS bucket FROM data WHERE data_type = $2 GROUP BY bucket) as sub " <>
          "GROUP BY frame HAVING count(*) >= $3 - 1 ORDER BY frame asc",
        [
          @origin,
          type,
          floor(frame_width_ms / max_time_diff_ms)
        ]
      )

    Enum.map(rows, &hd/1)
  end
end
