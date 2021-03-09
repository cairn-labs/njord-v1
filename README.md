Njord
=====

Njord is an algorithmic trading system designed to actively trade a variety of
assets (currently, equities and cryptocurrencies) based on streams of various
data types (currently stock aggregates, crypto order books, subreddit top pages
and comments, and news headlines + articles). It is not designed for high
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

Entry Points
------------

When diving into this codebase, the following entry points might be useful.

1. **Data Ingest.**  Take a look at [Trader.Coinbase.L2DataCollector](trader/lib/trader/coinbase/l2_data_collector.ex) 
   or [Trader.Alpaca.AlpacaDataCollector](trader/lib/trader/alpaca/alpaca_data_collector.ex). 
   There are several others and all work in slightly different ways, but what they 
   have in common is creating a [DataPoint](proto/data_point.proto) object and then 
   adding it to the DB with `Trader.Db.DataPoints.insert_datapoint/1`.
   
2. **Frame Retrieval.** [This](trader/lib/trader/frames/frame_generation.ex#L31) is 
   the mechanism for retrieving data that was ingested. Data is requested with a 
   [FrameConfig](proto/frame_config.proto) (for example, see 
   [this one](data/frame_configs/stonks_and_wsb.pb.txt) that pulls both WSB data and
   GME price and volume aggregates. It takes care of normalizing and interpolating
   time buckets, doing a lot of the heavy lifting with [TimescaleDB](https://www.timescale.com/) 
   which is currently our primary datastore: see [this crazy query](trader/lib/trader/db/data_points.ex#L142)
   for example.
   
3. **Live Trading.** The core live trading event loop is in [Trader.Runners.LiveRunner](trader/lib/trader/runners/live_runner.ex).
   See in particular the `:tick` event handler. This checks which strategies are due to be run
   based on their cadence, extracts their input dataframes and sends them to the Analyst, and
   finally sends any resulting predictions to the order creation module. Note that when run
   in live mode, this server will load all strategies present in [trader/priv/active_strategies/](trader/priv/active_strategies/).
   
4. **Backtesting.** [Trader.Runners.BacktestRunner](trader/lib/trader/runners/backtest_runner.ex)
   provides an alternative runner that loads a single strategy and runs it against mock exchanges.
   The prediction infrastructure and order compiler is exactly the same as when running in live mode,
   but time prgression and order fills are simulated instead of happening in realtime. Note that 
   my backtesting logic is not very sophisticated and does not model market order slippage.
   
5. **API.** There is a very minimal API that currently serves http://trader.tendies.ai/status. You 
   will definitely want to install a JSON Formatter Chrome Extension if you plan on monitoring the 
   live strategies using that endpoint. This is a [Phoenix](https://www.phoenixframework.org/) API
   and the relevant controller code is located at 
   [TraderWeb.StatusController](trader/lib/trader_web/controllers/status_controller.ex).

   The API also offers a route for [retrieving training data given a frame config](trader/lib/trader_web/controllers/training_data_controller.ex).
   This is used by the [get_training_data.py](scripts/get_training_data.py) script to create large
   training data dumps for building and testing new models.
    
