#!/bin/sh
# Smoke test: external edge response via DNS/tunnel (requires DNS/tunnel to be configured)
set -eu

fail() { printf "FAIL: %s\n" "$1" >&2; exit 2; }
pass() { printf "PASS: %s\n" "$1\n"; }

if [ -f .env ]; then
  # shellcheck disable=SC1090
  . .env
fi
[ -n "${DOMAIN:-}" ] || fail "DOMAIN not set. Export DOMAIN or add it to .env"

# perform a head request
resp_headers=$(curl -sSI --max-time 10 "https://${DOMAIN}" || true)
if [ -z "$resp_headers" ]; then
  fail "No HTTP response from https://${DOMAIN}. Check DNS/tunnel routing and cloudflared."
fi

# extract status line
status_line=$(printf '%s\n' "$resp_headers" | sed -n '1p' | tr -d '\r')
case "$status_line" in
  *200*|*201*|*202*|*203*|*204*|*2??*)
    pass "Edge returned 2xx status: $status_line"
    ;;
  *)
    fail "Unexpected status: $status_line. Check application or origin routing."
    ;;
esac

# check for Cloudflare headers
if printf '%s\n' "$resp_headers" | grep -qi '^cf-ray:' || printf '%s\n' "$resp_headers" | grep -qi '^server:.*cloudflare'; then
  pass "Response appears to be proxied by Cloudflare (cf-ray / server: cloudflare present)"
else
  printf "WARN: response lacks Cloudflare headers. It may not be routed through Cloudflare.\n" >&2
  printf "Headers received:\n%s\n" "$resp_headers" >&2
  fail "Edge response not proxied by Cloudflare"
fi

printf "\nALL EXTERNAL CHECKS PASS\n"
exit 0
