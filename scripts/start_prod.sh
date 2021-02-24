#!/bin/bash


nohup ./run_analyst.sh &> analyst_logs.out &
nohup ./run_trader.sh &> trader_logs.out &
