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
        _ -> {"AND selector = $4 ", [selector]}
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
    limit = floor(frame_width_ms / bucket_width_ms)

    {selector_expr, selector_value} =
      case selector do
        nil -> {"", []}
        _ -> {"AND selector = $4", [selector]}
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
    GROUP BY bucket ORDER BY bucket ASC
    LIMIT $3;
    """

    {:ok, %{rows: rows}} =
      SQL.query(Repo, query, [type, start_timestamp, limit] ++ selector_value)

    rows
    |> Enum.map(fn [_ts, value] -> value end)
  end

  def get_data_at_time(timestamp, data_point_type, selector) do
    type = DataPointType.mapping()[data_point_type]

    {selector_expr, selector_value} =
      case selector do
        nil -> {"", []}
        _ -> {"AND selector = $3", [selector]}
      end

    query =
      "select contents from data where time > $1 AND data_type = $2 #{selector_expr} ORDER BY time asc LIMIT 1;"

    case SQL.query(Repo, query, [timestamp, type] ++ selector_value) do
      {:ok, %{rows: []}} -> nil
      {:ok, %{rows: [[contents]]}} -> DataPoint.decode(contents)
    end
  end

  def update_selector(datapoint_id, selector) do
    {:ok, _} =
      SQL.query(Repo, "UPDATE data SET selector = $1 WHERE id = $2", [selector, datapoint_id])

    :ok
  end

  def update_price(datapoint_id, price) do
    {:ok, _} = SQL.query(Repo, "UPDATE data SET price = $1 WHERE id = $2", [price, datapoint_id])

    :ok
  end

  def get_windows_by_price_change(direction, amount, frame_width_ms, prediction_delay_ms) do
    prediction_upper_bound_ms = 2 * prediction_delay_ms

    price_clause =
      case direction do
        :up ->
          "and prediction_end_price > (1.0 + $1) * window_end_price"

        :down ->
          "and prediction_end_price < (1.0 - $1) * window_end_price"

        :flat ->
          "and prediction_end_price > (1.0 - $1) * window_end_price and prediction_end_price < (1.0 + $1) * window_end_price"
      end

    query = """
    SELECT window_begin_time, window_end_price, prediction_end_price
    FROM (SELECT time - INTERVAL '#{frame_width_ms} milliseconds' AS window_begin_time,
                 price                                            AS window_end_price,
                 (SELECT price
                  FROM data AS data_inner
                  WHERE time > data_outer.time + INTERVAL '#{prediction_delay_ms} milliseconds'
                    AND time < data_outer.time + INTERVAL '#{prediction_upper_bound_ms} milliseconds'
                  ORDER BY time
                  LIMIT 1)                                        AS prediction_end_price
          FROM data AS data_outer) AS subquery
    WHERE window_end_price is not null
      and prediction_end_price is not null
      #{price_clause}
    ORDER BY random()
    """

    {:ok, %{rows: rows}} = SQL.query(Repo, query, [amount])

    rows
    |> Enum.map(fn [ts, _, _] -> ts end)
  end
end
