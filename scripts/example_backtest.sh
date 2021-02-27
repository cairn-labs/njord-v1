#!/bin/bash
set -e

export STRATEGY=`realpath $1`
export MIX_ENV=offline
cd trader/

mix trader.backtest 2021-02-17T16:00:00Z 2021-02-27T00:00:00Z $STRATEGY
