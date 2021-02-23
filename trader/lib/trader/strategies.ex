defmodule Trader.Strategies do
  alias Trader.Alpaca.AlpacaApi
  require Logger

  def all_strategies_by_allocation do
    active_strategies
    |> Enum.map(fn %TradingStrategy{name: name, capital_allocation: capital_allocation} ->
      {name, capital_allocation}
    end)
    |> Enum.into(%{})
  end

  def active_strategies do
    strategies =
      Application.app_dir(:trader, "priv")
      |> Path.join("active_strategies")
      |> Path.join("*.pb.txt")
      |> Path.wildcard()
      |> Enum.map(fn p ->
        Trader.ProtoUtil.parse_text_format(p, TradingStrategy, "trading_strategy.proto")
      end)

    check_strategies(strategies)
    strategies
  end

  defp check_strategies(strategies) do
    total_allocation =
      strategies
      |> Enum.map(fn %TradingStrategy{capital_allocation: c} -> c end)
      |> Enum.sum()

    if total_allocation > 1.0 do
      raise "Total capital allocation of all strategies must be at most 1"
    end
  end

  def is_schedulable?(%TradingStrategy{schedule: :ALL}, _) do
    true
  end

  def is_schedulable?(%TradingStrategy{schedule: :MARKET_HOURS}, timestamp) do
    ny_datetime = timestamp |> DateTime.shift_zone!("America/New_York")
    ny_date = DateTime.to_date(ny_datetime) |> Date.to_iso8601()

    calendar =
      Trader.DataCache.cached("market-calendar", 86400, &Trader.Alpaca.Alpaca.get_calendar/0)

    case Map.get(calendar, ny_date) do
      nil ->
        false

      %{
        "o" => open_str,
        "c" => close_str
      } ->
        open = Time.from_iso8601!(open_str <> ":00")
        close = Time.from_iso8601!(close_str <> ":00")
        current = DateTime.to_time(ny_datetime)

        case {Time.compare(open, current), Time.compare(current, close)} do
          {:lt, :lt} -> true
          _ -> false
        end
    end
  end
end
