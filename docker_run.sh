#!/bin/bash

docker run --rm -it \
  -v"$(pwd):/home/${USER}/work" \
  vm2gol-v2-zig:1 "$@"