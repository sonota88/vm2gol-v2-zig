#!/bin/bash

docker build \
  --build-arg USER=$USER \
  --build-arg GROUP=$(id -gn) \
  -t vm2gol-v2-zig:2 .
