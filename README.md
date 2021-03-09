Njord
=====

Njord is an algorithmic trading system designed to actively trade a variety of
assets (currently, equities and cryptocurrencies) based on streams of various
data types (currently stock aggregates, crypto order books, subreddit top pages
+ comments, and news headlines + articles). It is not designed for high
frequency trading (it is a soft-realtime system and trading based on
second-level data is probably ill-advised) but should be capable of trading
strategies at cadences of one minute to weeks.


Overview
--------
Njord is composed of two major components that communicate with each other using
a [shared set of protocol buffers](proto/):

  1. [Analyst](analyst/) is a Python application whose role is to accept slices
     of data (in the form of [DataFrame](proto/data_frame.proto) objects) and
     strategy configuration (in the form of a
     [TradingStrategy](proto/trading_strategy.proto#L9) object), and to return
     asset [price predictions](proto/prediction.proto).

  2. [Trader](trader/) is an Elixir application that does basically everything
     else:
        * Handles all communication with the outside world (data sources,
          exchanges, etc)
        * Pulls frames of data from the database so that they can be sent to the
          analyst either in realtime (live) or at a timestamp (for backtesting
          or model training)
        * Manages capital and asset allocation between strategies
        * Turns price predictions into orders
