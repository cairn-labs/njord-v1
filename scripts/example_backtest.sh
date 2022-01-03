#!/bin/bash
set -e

export STRATEGY=`realpath $1`
export MIX_ENV=offline
cd trader/

mix trader.backtest 2021-12-31T20:00:00Z 2021-12-31T21:00:00Z $STRATEGY
