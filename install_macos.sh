#!/bin/bash

brew tap timescale/tap
brew install --upgrade postgresql
brew install timescaledb
/usr/local/bin/timescaledb_move.sh
timescaledb-tune --yes
sleep 5
brew services restart postgresql
sleep 5
psql -c "CREATE USER trader_dev WITH PASSWORD 'password';"
createdb trader_dev -O trader_dev
