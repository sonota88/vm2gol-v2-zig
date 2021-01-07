#!/bin/bash

print_project_dir() {
  local real_path="$(readlink --canonicalize "$0")"
  (
    cd "$(dirname "$real_path")"
    pwd
  )
}

export PROJECT_DIR="$(print_project_dir)"
export TEST_DIR="${PROJECT_DIR}/test"
export TEMP_DIR="${PROJECT_DIR}/z_tmp"
ZIG=zig-0.6.0
EXE_FILE=${PROJECT_DIR}/bin/app

MAX_ID_JSON=6
MAX_ID_TOKENIZE=2
MAX_ID_PARSE=2
MAX_ID_STEP=29

ERRS=""

run_test_json() {
  local infile="$1"; shift

  cat $infile | $ZIG run test_json.zig
}

run_tokenize() {
  local infile="$1"; shift

  cat $infile | $ZIG run vgtokenizer.zig
}

run_parse() {
  local infile="$1"; shift

  cat $infile | $ZIG run vgparser.zig
}

run_cg() {
  local infile="$1"; shift

  cat $infile | $ZIG run vgcg.zig
}

# --------------------------------

setup() {
  mkdir -p ./z_tmp
  mkdir -p ./bin
}

build() {
  :
}

postproc() {
  local stage="$1"; shift

  if [ "$ERRS" = "" ]; then
    echo "${stage}: ok"
  else
    echo "----"
    echo "FAILED: ${ERRS}"
    exit 1
  fi
}

get_ids() {
  local max_id="$1"; shift

  if [ $# -eq 1 ]; then
    echo "$1"
  else
    seq 1 $max_id
  fi
}

# --------------------------------

test_json_nn() {
  local nn="$1"; shift

  echo "case ${nn}"

  local input_file="${TEST_DIR}/json/${nn}.json"
  local temp_json_file="${TEMP_DIR}/test.json"
  local exp_tokens_file="${TEST_DIR}/json/${nn}.json"

  run_test_json $input_file > $temp_json_file
  if [ $? -ne 0 ]; then
    ERRS="${ERRS},${nn}_json"
    return
  fi

  ruby test/diff.rb json $exp_tokens_file $temp_json_file
  if [ $? -ne 0 ]; then
    # meld $exp_tokens_file $temp_json_file &

    ERRS="${ERRS},json_${nn}_diff"
    return
  fi
}

test_json() {
  local ids="$(get_ids $MAX_ID_JSON "$@")"

  for id in $ids; do
    test_json_nn $(printf "%02d" $id)
  done
}

# --------------------------------

test_tokenize_nn() {
  local nn="$1"; shift

  echo "case ${nn}"

  local input_file="${TEST_DIR}/tokenize/${nn}.vg.txt"
  local temp_tokens_file="${TEMP_DIR}/test.tokens.txt"
  local exp_tokens_file="${TEST_DIR}/tokenize/exp_${nn}.txt"

  run_tokenize $input_file > $temp_tokens_file
  if [ $? -ne 0 ]; then
    ERRS="${ERRS},${nn}_tokenize"
    return
  fi

  ruby test/diff.rb text $exp_tokens_file $temp_tokens_file
  if [ $? -ne 0 ]; then
    # meld $exp_tokens_file $temp_tokens_file &

    ERRS="${ERRS},tokenize_${nn}_diff"
    return
  fi
}

test_tokenize() {
  local ids="$(get_ids $MAX_ID_TOKENIZE "$@")"

  for id in $ids; do
    test_tokenize_nn $(printf "%02d" $id)
  done
}

# --------------------------------

test_parse_nn() {
  local nn="$1"; shift

  echo "case ${nn}"

  local input_file="${TEST_DIR}/parse/${nn}.vg.txt"
  local temp_tokens_file="${TEMP_DIR}/test.tokens.txt"
  local temp_vgt_file="${TEMP_DIR}/test.vgt.json"
  local exp_vgt_file="${TEST_DIR}/parse/exp_${nn}.vgt.json"

  echo "  tokenize" >&2
  run_tokenize $input_file > $temp_tokens_file
  if [ $? -ne 0 ]; then
    ERRS="${ERRS},${nn}_tokenize"
    return
  fi

  echo "  parse" >&2
  run_parse $temp_tokens_file \
    > $temp_vgt_file
  if [ $? -ne 0 ]; then
    ERRS="${ERRS},${nn}_parse"
    return
  fi

  ruby test/diff.rb json $exp_vgt_file $temp_vgt_file
  if [ $? -ne 0 ]; then
    # meld $exp_vgt_file $temp_vga_file &

    ERRS="${ERRS},parse_${nn}_diff"
    return
  fi
}

# --------------------------------

test_parse() {
  local ids="$(get_ids $MAX_ID_PARSE "$@")"

  for id in $ids; do
    test_parse_nn $(printf "%02d" $id)
  done
}

# --------------------------------

test_compile_nn() {
  local nn="$1"; shift

  echo "case ${nn}"

  local temp_tokens_file="${TEMP_DIR}/test.tokens.txt"
  local temp_vgt_file="${TEMP_DIR}/test.vgt.json"
  local temp_vga_file="${TEMP_DIR}/test.vga.txt"
  local local_errs=""
  local exp_vga_file="${TEST_DIR}/compile/exp_${nn}.vga.txt"

  echo "  tokenize" >&2
  run_tokenize ${TEST_DIR}/compile/${nn}.vg.txt \
    > $temp_tokens_file
  if [ $? -ne 0 ]; then
    ERRS="${ERRS},${nn}_tokenize"
    local_errs="${local_errs},${nn}_tokenize"
    return
  fi

  echo "  parse" >&2
  run_parse $temp_tokens_file \
    > $temp_vgt_file
  if [ $? -ne 0 ]; then
    ERRS="${ERRS},${nn}_parse"
    local_errs="${local_errs},${nn}_parse"
    return
  fi

  echo "  codegen" >&2
  run_cg $temp_vgt_file \
    > $temp_vga_file
  if [ $? -ne 0 ]; then
    ERRS="${ERRS},${nn}_cg"
    local_errs="${local_errs},${nn}_cg"
    return
  fi

  if [ "$local_errs" = "" ]; then
    ruby test/diff.rb asm $exp_vga_file $temp_vga_file
    if [ $? -ne 0 ]; then
      # meld $exp_vga_file $temp_vga_file &

      ERRS="${ERRS},compile_${nn}_diff"
      return
    fi
  fi
}

# --------------------------------

test_compile() {
  local ids="$(get_ids $MAX_ID_STEP "$@")"

  for id in $ids; do
    test_compile_nn $(printf "%02d" $id)
  done
}

# --------------------------------

test_all() {
  echo "==== json ===="
  test_json
  if [ $? -ne 0 ]; then
    ERRS="${ERRS},${nn}_json"
    return
  fi

  echo "==== tokenize ===="
  test_tokenize
  if [ $? -ne 0 ]; then
    ERRS="${ERRS},${nn}_tokenize"
    return
  fi

  echo "==== parse ===="
  test_parse
  if [ $? -ne 0 ]; then
    ERRS="${ERRS},${nn}_parser"
    return
  fi

  echo "==== compile ===="
  test_compile
  if [ $? -ne 0 ]; then
    ERRS="${ERRS},${nn}_compile"
    return
  fi
}

# --------------------------------

setup

# build

cmd="$1"; shift
case $cmd in
  json | j*)     #task: Run json tests
    test_json "$@"
    postproc "json"
    ;;

  tokenize | t*) #task: Run tokenize tests
    test_tokenize "$@"
    postproc "tokenize"
    ;;

  parse | p*)    #task: Run parse tests
    test_parse "$@"
    postproc "parse"
    ;;

  compile | c*)  #task: Run compile tests
    test_compile "$@"
    postproc "compile"
    ;;

  all | a*)      #task: Run all tests
    test_all
    postproc "all"
    ;;

  *)
    echo "Tasks:"
    grep '#task: ' $0 | grep -v grep
    ;;
esac
