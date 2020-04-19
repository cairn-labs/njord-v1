defmodule Trader.TimeUtil do
  def int_to_datetime(microseconds_since_epoch) do
    {:ok, dt} = DateTime.from_unix(microseconds_since_epoch, :microsecond)
    dt
  end
end
