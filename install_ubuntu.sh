#!/bin/bash


sudo add-apt-repository ppa:timescale/timescaledb-ppa
sudo apt-get update
sudo apt install -y timescaledb-postgresql-12
sudo sh -c $'echo "shared_preload_libraries = \'timescaledb\'" >> /etc/postgresql/12/main/postgresql.conf'

sleep 5
sudo service postgresql restart
sleep 5

sudo -u postgres bash -c "psql -c \"CREATE USER trader_dev WITH PASSWORD 'password' SUPERUSER;\""
sudo -u postgres bash -c "createdb trader_dev -O trader_dev"
PGPASSWORD=password psql -h localhost -U trader_dev -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"
