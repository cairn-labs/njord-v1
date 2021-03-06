#!/bin/bash
set -e

export STRATEGY=`realpath $1`
export MIX_ENV=offline
cd trader/

mix trader.backtest 2021-03-01T16:00:00Z 2021-03-06T00:00:00Z $STRATEGY
