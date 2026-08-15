#!/usr/bin/env bash
# Shared shell utilities for neutrino run scripts.

# Join arguments with ':'
join_colon() {
  local result=""
  for p in "$@"; do
    result="${result:+${result}:}${p}"
  done
  printf '%s' "${result}"
}
