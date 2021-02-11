#!/bin/bash
set -e
set -x

export MIX_ENV=offline
cd trader/

mix trader.backtest 2008-01-01T00:00:00Z 2008-01-31T00:00:00Z ../data/strategies/
