#!/bin/bash
set -x

pkill -f phx.server
fuser -k -n tcp 8001
