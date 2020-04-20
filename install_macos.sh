#!/bin/bash

brew tap timescale/tap
brew install --upgrade postgresql
brew install timescaledb
/usr/local/bin/timescaledb_move.sh
timescaledb-tune --yes
sleep 5
brew services restart postgresql
sleep 5
psql -c "CREATE USER trader_dev WITH PASSWORD 'password' SUPERUSER;"
createdb trader_dev -O trader_dev
psql -U trader_dev -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"

brew install python3
pip install virtualenv
virtualenv -p python3 venv
source venv/bin/activate
pip install -r requirements.txt
