defmodule Trader.TimeUtil do
  def int_to_datetime(microseconds_since_epoch) do
    {:ok, dt} = DateTime.from_unix(microseconds_since_epoch, :microsecond)
    dt
  end

  @doc """
  Given a start and end date in format YYYY-MM-DD, generate a list of
  all dates in between these two dates (inclusive)
  """
  def date_range(start_date_str, end_date_str) do
    start_date = Date.from_iso8601!(start_date_str)
    end_date = Date.from_iso8601!(end_date_str)
    Date.range(start_date, end_date) |> Stream.map(&Date.to_string/1)
  end

  def date_string_to_datetime(date_string, :begin) do
    {:ok, datetime, 0} = DateTime.from_iso8601("#{date_string}T00:00:00Z")
    datetime
  end

  def date_string_to_datetime(date_string, :end) do
    {:ok, datetime, 0} = DateTime.from_iso8601("#{date_string}T23:59:59Z")
    datetime
  end
end
