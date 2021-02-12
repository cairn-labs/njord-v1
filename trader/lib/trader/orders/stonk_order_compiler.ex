defmodule Trader.Orders.StonkOrderCompiler do
  @moduledoc """
  Takes current positions, current prices, and a set of predictions and
  generates orders. This will be more complex in the future, but currently
  does the following:

  1. Sort predicted prices by % difference from current.
  2. Issue market sell orders for all shares for all holdings with
     predictions < -X% of current price (unless PDT banned)
  3. Check to see if there is at least one prediction for > +X% of market
     price. If not, exit.
  2. Issue market sell orders for all shares for all holdings with no
     predictions (unless PDT banned)
  3. After fill of the above sell orders, select all predictions for > +X% of
     market price (not PDT banned) and allocate capital weighted by % difference
     from market price. Issue market buy orders.
  """

  def get_orders(
    %ExchangePositions{} = current_positions,
    prices,
    %Prediction{labels: labels} = prediction
  ) do
    "do the thing above"
  end
end
