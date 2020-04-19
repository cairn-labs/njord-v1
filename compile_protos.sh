#!/bin/bash

# Elixir
protoc -I proto --elixir_out=trader/lib/proto/ proto/*.proto

# C++
rm -rf analyst/proto/*.pb.h analyst/proto/*.pb.cc
protoc --proto_path=proto/ --cpp_out=analyst/proto/ proto/*.proto
