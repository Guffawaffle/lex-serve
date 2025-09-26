#!/bin/sh
set -eu
f="nginx/conf.d/health.conf"
grep -Eq '^[[:space:]]*server[[:space:]]*\{' "$f" && { echo "FAIL: health.conf must not contain 'server{'"; exit 2; }
grep -Eq '^[[:space:]]*http[[:space:]]*\{' "$f"   && { echo "FAIL: health.conf must not contain 'http{'"; exit 2; }
echo "PASS: health.conf context looks sane (location-only)"
