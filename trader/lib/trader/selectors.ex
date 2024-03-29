defmodule Trader.Selectors do
  require Logger

  def from_data_point(%DataPoint{
        data_point_type: :L2_ORDER_BOOK,
        l2_order_book: %L2OrderBook{
          product: %CurrencyPair{
            base: base,
            counter: counter
          }
        }
      }) do
    "#{Atom.to_string(base)}-#{Atom.to_string(counter)}"
  end

  def from_data_point(%DataPoint{
        data_point_type: :NEWS_API_ITEM,
        news_api_item: %NewsApiItem{url: url}
      }) do
    url
  end

  def from_data_point(%DataPoint{
        data_point_type: :SUBREDDIT_TOP_LISTING,
        subreddit_top_listing: %SubredditTopListing{subreddit_name: name}
      }) do
    name
  end

  def from_data_point(%DataPoint{
        data_point_type: :STONK_AGGREGATE,
        stonk_aggregate: %StonkAggregate{ticker: ticker, width_minutes: width}
      }) do
    "#{ticker}-#{width}"
  end

  def from_data_point(d) do
    nil
  end

  def from_feature_config(%FeatureConfig{
        data_point_type: :L2_ORDER_BOOK,
        l2_order_book_config: %L2OrderBookConfig{
          product: %CurrencyPair{
            base: base,
            counter: counter
          }
        }
      }) do
    "#{Atom.to_string(base)}-#{Atom.to_string(counter)}"
  end

  def from_feature_config(%FeatureConfig{
        data_point_type: :STONK_AGGREGATE,
        stonk_aggregate_config: %StonkAggregateConfig{
          ticker: ticker,
          width_minutes: width_minutes
        }
      }) do
    "#{ticker}-#{width_minutes}"
  end

  def from_feature_config(%FeatureConfig{
        data_point_type: :SUBREDDIT_TOP_LISTING,
        subreddit_top_listing_config: %SubredditTopListingConfig{
          subreddit_name: name
        }
      }) do
    name
  end

  def from_feature_config(_), do: nil

  def from_label_config(%LabelConfig{
        label_type: :FX_RATE,
        fx_rate_config: %FxRateLabelConfig{
          product: %CurrencyPair{
            base: base,
            counter: counter
          }
        }
      }) do
    "#{Atom.to_string(base)}-#{Atom.to_string(counter)}"
  end

  def from_label_config(%LabelConfig{
        label_type: :STONK_PRICE,
        stonk_price_config: %StonkPriceLabelConfig{
          ticker: ticker,
          width_minutes: width_minutes
        }
      }) do
    "#{ticker}-#{width_minutes}"
  end
end
