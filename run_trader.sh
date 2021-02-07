#!/bin/bash
set -e

cd trader/
mix ecto.migrate
mix phx.server
