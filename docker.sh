#!/bin/bash

set -o nounset
set -o errexit

readonly IMAGE="mini-ruccola-zig:10"

build() {
  docker build \
    --build-arg USER=$USER \
    --build-arg GROUP=$(id -gn) \
    --progress plain \
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
