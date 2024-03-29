#!/bin/bash
set -e
set -x

# Elixir
rm -rf trader/lib/proto/*.pb.ex
protoc -I proto --elixir_out=trader/lib/proto/ proto/*.proto
cp -R proto/*.proto trader/priv/proto_definitions/

# Python
source venv/bin/activate
rm -rf analyst/proto/*_pb2.py
protoc --proto_path=proto/ --python_out=analyst/proto/ proto/*.proto
# this is so ridiculous, see https://github.com/protocolbuffers/protobuf/issues/1491
touch analyst/proto/__init__.py
2to3 analyst/proto/ -w -n > /dev/null 2>&1
