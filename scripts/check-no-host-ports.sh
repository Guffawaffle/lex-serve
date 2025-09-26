#!/bin/sh
# Fail if any running container has host published ports
set -eu

fail() { printf "FAIL: %s\n" "$1" >&2; exit 2; }
pass() { printf "PASS: %s\n" "$1\n"; }

# List containers with non-empty Ports field
bad=$(docker ps --format '{{.Names}}::{{.Ports}}' | awk -F '::' '$2!="" {print $0; exit 0}')
if [ -n "$bad" ]; then
  printf "FAIL: found containers exposing host ports:\n%s\n" "$bad" >&2
  exit 2
fi
pass "no host ports exposed on running containers"
exit 0
