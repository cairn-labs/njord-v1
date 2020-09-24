defmodule Trader.CurrencyUtil do
  def currency_pair_from_string(pair_str) do
    [base_str, counter_str] = String.split(pair_str, "-")

    CurrencyPair.new(
      base: currency_from_string(base_str),
      counter: currency_from_string(counter_str)
    )
  end

  def currency_from_string("BTC"), do: :BTC
  def currency_from_string("USD"), do: :USD
  def currency_from_string("ETH"), do: :ETH
  def currency_from_string("LTC"), do: :LTC
  def currency_from_string("XRP"), do: :XRP
end
