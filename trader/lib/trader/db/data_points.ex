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

    price =
      datapoint
      |> Trader.PriceUtil.price_from_data_point()
      |> Trader.PriceUtil.as_float()

    data = DataPoint.encode(datapoint)

    {:ok, _} =
      SQL.query(
        Repo,
        "INSERT INTO data (time, data_type, selector, price, contents) VALUES ($1, $2, $3, $4, $5);",
        [ts, type, selector, price, data]
      )
  end

  def insert_datapoint_if_not_exists(%DataPoint{} = datapoint) do
    type = DataPointType.mapping()[datapoint.data_point_type]
    selector = Trader.Selectors.from_data_point(datapoint)

    case SQL.query(
           Repo,
           "SELECT id FROM data WHERE data_type = $1 AND selector = $2;",
           [type, selector]
         ) do
      {:ok, %{rows: []}} ->
        insert_datapoint(datapoint)

      _ ->
        :ok
    end
  end

  def get_price_at_time(data_point_type, selector, timestamp) do
    type = DataPointType.mapping()[data_point_type]

    case SQL.query(
           Repo,
           "select price from data where data_type = $1 and selector = $2 and time < $3 ORDER BY time DESC LIMIT 1;",
           [type, selector, timestamp]
         ) do
      {:ok, %{rows: []}} -> nil
      {:ok, %{rows: [[price]]}} -> price
    end
  end

  def get_available_windows(
        data_point_type,
        max_time_diff_ms,
        frame_width_ms,
        selector,
        start_date,
        end_date
      ) do
    type = DataPointType.mapping()[data_point_type]

    {current_param, selector_expr, selector_value} =
      case selector do
        nil -> {4, "", []}
        _ -> {5, "AND selector = $4 ", [selector]}
      end

    {current_param, start_expr, start_value} =
      case start_date do
        nil ->
          {current_param, "", []}

        _ ->
          {current_param + 1, "AND time > $#{current_param}",
           [
             TimeUtil.date_string_to_datetime(start_date, :begin)
           ]}
      end

    {_current_param, end_expr, end_value} =
      case end_date do
        nil ->
          {current_param, "", []}

        _ ->
          {current_param + 1, "AND time < $#{current_param}",
           [
             TimeUtil.date_string_to_datetime(end_date, :end)
           ]}
      end

    {:ok, %{rows: rows}} =
      SQL.query(
        Repo,
        "SELECT time_bucket('#{frame_width_ms} milliseconds', bucket, $1::timestamptz) AS frame FROM " <>
          "(SELECT time_bucket('#{max_time_diff_ms} milliseconds', time, $1::timestamptz) AS bucket FROM data " <>
          "WHERE data_type = $2 #{selector_expr} #{start_expr} #{end_expr} " <>
          "GROUP BY bucket) as sub " <>
          "GROUP BY frame HAVING count(*) >= $3 - 1 ORDER BY frame asc",
        [
          @origin,
          type,
          floor(frame_width_ms / max_time_diff_ms)
        ] ++ selector_value ++ start_value ++ end_value
      )

    Enum.map(rows, &hd/1)
  end

  def get_frame_component(
        %FeatureConfig{
          data_point_type: :OPTION_QUOTE_CHAIN,
          bucketing_strategy: bucketing_strategy,
          bucket_width_ms: bucket_width_ms
        },
        start_timestamp,
        frame_width_ms,
        selector
      ) do
    query = """
    SELECT DISTINCT selector
    FROM data
    WHERE time >= $1
    AND TIME < $1 + interval '#{frame_width_ms}  milliseconds'
    AND data_type = 5
    """

    {:ok, %{rows: rows}} = SQL.query(Repo, query, [start_timestamp])

    quotes =
      for [symbol] <- rows do
        # investigate parallelizing this
        get_frame_component(
          %FeatureConfig{
            data_point_type: :OPTION_QUOTE,
            bucketing_strategy: bucketing_strategy,
            bucket_width_ms: bucket_width_ms
          },
          start_timestamp,
          frame_width_ms,
          symbol
        )
      end
    Logger.info("ROWS #{inspect(rows)}")
    Logger.info(inspect(Enum.map(quotes, &length/1)))
    # Just need to figure out how to combine these properly into
    # an Option Quote Chain object. Probably want to unzip  -- see terminal
    []
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
    |> Enum.flat_map(fn
      [_ts, value] when value != nil -> [value]
      _ -> []
    end)
  end

  def get_data_at_time(timestamp, data_point_type, selector, before_or_after) do
    type = DataPointType.mapping()[data_point_type]

    {selector_expr, selector_value} =
      case selector do
        nil -> {"", []}
        _ -> {"AND selector = $3", [selector]}
      end

    query =
      case before_or_after do
        :after ->
          "select contents from data where time > $1 AND data_type = $2 #{selector_expr} ORDER BY time asc LIMIT 1;"

        :before ->
          "select contents from data where time < $1 AND data_type = $2 #{selector_expr} ORDER BY time desc LIMIT 1;"
      end

    case SQL.query(Repo, query, [timestamp, type] ++ selector_value) do
      {:ok, %{rows: []}} -> nil
      {:ok, %{rows: [[contents]]}} -> DataPoint.decode(contents)
    end
  end

  def get_data_before_time(timestamp, data_point_type, selector) do
    get_data_at_time(timestamp, data_point_type, selector, :before)
  end

  def get_data_after_time(timestamp, data_point_type, selector) do
    get_data_at_time(timestamp, data_point_type, selector, :after)
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

  def counts_by_type_in_window(start_datetime, end_datetime) do
    query =
      "select data_type, count(*) from data where time > $1 and time <= $2 group by data_type"

    {:ok, %{rows: rows}} = SQL.query(Repo, query, [start_datetime, end_datetime])

    rows
    |> Enum.map(fn [data_type, count] -> {DataPointType.key(data_type), count} end)
    |> Enum.into(%{})
  end

  def price_crossing_timestamp(:STONK_PRICE, selector, price, above_or_below, start_ts, end_ts) do
    type = DataPointType.mapping()[:STONK_AGGREGATE]

    operator =
      case above_or_below do
        :above -> ">="
        :below -> "<="
      end

    query = """
    SELECT time FROM data WHERE data_type = $1 AND time >= $2 AND time < $3
    AND price #{operator} $4 AND selector = $5 ORDER BY time ASC LIMIT 1
    """

    case SQL.query(Repo, query, [type, start_ts, end_ts, price, selector]) do
      {:ok, %{rows: []}} -> nil
      {:ok, %{rows: [[p]]}} -> p
    end
  end
end
