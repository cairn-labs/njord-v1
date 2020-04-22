defmodule Trader.Db.DataPoints do
  alias Trader.Repo
  alias Trader.TimeUtil
  alias Ecto.Adapters.SQL
  require Logger

  @origin ~U[2020-04-20 00:00:00Z]

  def insert_datapoint(%DataPoint{} = datapoint) do
    ts = TimeUtil.int_to_datetime(datapoint.event_timestamp)
    type = DataPointType.mapping()[datapoint.data_point_type]
    selector = Trader.Selectors.from_data_point(datapoint)
    data = DataPoint.encode(datapoint)

    {:ok, _} =
      SQL.query(
        Repo,
        "INSERT INTO data (time, data_type, selector, contents) VALUES ($1, $2, $3, $4);",
        [ts, type, selector, data]
      )
  end

  def get_available_windows(data_point_type, max_time_diff_ms, frame_width_ms, selector) do
    type = DataPointType.mapping()[data_point_type]

    {selector_expr, selector_value} =
      case selector do
        nil -> {"", []}
        s -> {"AND selector = $4 ", [selector]}
      end

    {:ok, %{rows: rows}} =
      SQL.query(
        Repo,
        "SELECT time_bucket('#{frame_width_ms} milliseconds', bucket, $1::timestamptz) AS frame FROM " <>
          "(SELECT time_bucket('#{max_time_diff_ms} milliseconds', time, $1::timestamptz) AS bucket FROM data " <>
          "WHERE data_type = $2 #{selector_expr} GROUP BY bucket) as sub " <>
          "GROUP BY frame HAVING count(*) >= $3 - 1 ORDER BY frame asc",
        [
          @origin,
          type,
          floor(frame_width_ms / max_time_diff_ms)
        ] ++ selector_value
      )

    Enum.map(rows, &hd/1)
  end

  def get_frame_component(
        %FeatureConfig{
          data_point_type: data_point_type,
          bucketing_strategy: bucketing_strategy,
          bucket_width_ms: bucket_width_ms
        },
        start_timestamp,
        frame_width_ms,
        selector
      ) do
    type = DataPointType.mapping()[data_point_type]

    {selector_expr, selector_value} =
      case selector do
        nil -> {"", []}
        s -> {"AND selector = $3", [selector]}
      end

    aggregation =
      case bucketing_strategy do
        :EARLIEST -> "first(contents, time)"
        :LATEST -> "last(contents, time)"
      end

    query = """
    SELECT
    time_bucket_gapfill('#{bucket_width_ms} milliseconds', time) as bucket,
    locf(#{aggregation}, (
      SELECT contents FROM data d2 WHERE d2.time::timestamp AT TIME ZONE 'Utc' < $2
      AND d2.data_type = $1 #{selector_expr} ORDER BY d2.time DESC LIMIT 1
    )) AS value
    FROM data
    WHERE data_type = $1 #{selector_expr} AND time >= $2
    AND TIME < $2 + interval '#{frame_width_ms}  milliseconds'
    GROUP BY bucket ORDER BY bucket ASC;
    """

    {:ok, %{rows: rows}} = SQL.query(Repo, query, [type, start_timestamp] ++ selector_value)

    rows
    |> Enum.map(fn [_ts, value] -> value end)
  end
end
