#!/bin/bash

set -o nounset
set -o errexit

readonly IMAGE="vm2gol-v2-zig:4"

build() {
  docker build \
    --build-arg USER=$USER \
    --build-arg GROUP=$(id -gn) \
    -t $IMAGE .
}

run() {
  docker run --rm -it \
    -v"$(pwd):/home/${USER}/work" \
    $IMAGE "$@"
}

# --------------------------------

cmd="$1"; shift

case $cmd in
  build | b* )
    build "$@"
;; run | r* )
     run "$@"
;; * )
     echo "invalid command (${cmd})" >&2
     ;;
esac
