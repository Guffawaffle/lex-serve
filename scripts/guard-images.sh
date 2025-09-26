#!/bin/sh
# Fail on :latest or missing @sha256: in docker-compose.yml image entries
set -eu

FILE="docker-compose.yml"
if [ ! -f "$FILE" ]; then
  echo "WARN: $FILE not found, skipping image guard"
  exit 0
fi

errors=0
# extract image values (simple YAML-aware grep)
grep -E '^[[:space:]]*image:' "$FILE" | while IFS= read -r line; do
  img=$(printf "%s" "$line" | sed -n 's/^[[:space:]]*image:[[:space:]]*//p' | tr -d '"' | tr -d "'")
  [ -z "$img" ] && continue
  case "$img" in
    *:latest* )
      printf 'ERROR: image uses :latest -> %s\n' "$img"
      errors=1
      ;;
    *@sha256:* )
      # ok
      ;;
    * )
      printf 'ERROR: image missing @sha256 digest -> %s\n' "$img"
      errors=1
      ;;
  esac
done

if [ "$errors" -ne 0 ]; then
  echo "Guard failed: fix image pinning (no :latest; add @sha256 digest)"
  exit 2
fi

echo "Guard ok: all images are pinned by digest (no :latest)"
exit 0
