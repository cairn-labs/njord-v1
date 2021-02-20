#!/bin/bash
set -e
set -x

export MIX_ENV=offline
cd trader/

mix trader.backtest 2021-02-17T16:00:00Z 2021-02-20T00:00:00Z ../data/strategies/
