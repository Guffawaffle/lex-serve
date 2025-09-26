#!/bin/sh
# Smoke test: internal connectivity & TLS (requires stack up)
set -eu

fail() { printf "FAIL: %s\n" "$1" >&2; exit 2; }
pass() { printf "PASS: %s\n" "$1\n"; }

# Load DOMAIN if present (do not print)
if [ -f .env ]; then
  # shellcheck disable=SC1090
  . .env
fi
[ -n "${DOMAIN:-}" ] || fail "DOMAIN not set. Export DOMAIN or add it to .env"

# 1) required services running: nginx and exactly one cloudflared service
nginx_id=$(docker compose ps -q nginx || true)
cf1=$(docker compose ps -q cloudflared || true)
cf2=$(docker compose ps -q cloudflared-trusted || true)

if [ -z "$nginx_id" ]; then
  fail "nginx service is not running. Start the stack and re-run."
fi

cf_count=0
[ -n "$cf1" ] && cf_count=$((cf_count+1))
[ -n "$cf2" ] && cf_count=$((cf_count+1))
if [ "$cf_count" -ne 1 ]; then
  fail "expect exactly one cloudflared service running (cloudflared XOR cloudflared-trusted). Found: $cf_count"
fi
pass "required services running (nginx + one cloudflared)"

# 2) nginx health endpoint
if ! docker compose exec -T nginx sh -c "if command -v curl >/dev/null 2>&1; then curl -fsS -m 5 http://localhost/healthz; else wget -qO- -T 5 http://localhost/healthz; fi" >/dev/null 2>&1; then
  fail "nginx /healthz failed. Check nginx logs: docker compose logs nginx"
fi
pass "nginx /healthz OK"

# 3) TLS handshake from cloudflared -> nginx (uses openssl inside cloudflared)
cloudflared_svc=""
[ -n "$cf1" ] && cloudflared_svc="cloudflared"
[ -n "$cf2" ] && cloudflared_svc="cloudflared-trusted"

# Ensure openssl exists inside cloudflared container
if ! docker compose exec -T "$cloudflared_svc" sh -c 'command -v openssl >/dev/null 2>&1' >/dev/null 2>&1; then
  fail "openssl not present inside $cloudflared_svc. Install or run the TLS check from a host with CA trust configured."
fi

# Run openssl and look for verification success
openssl_out=$(docker compose exec -T "$cloudflared_svc" sh -c "openssl s_client -connect nginx:443 -servername '${DOMAIN}' -CAfile /etc/ssl/certs/ca-certificates.crt </dev/null 2>/dev/null || true")
if printf '%s' "$openssl_out" | grep -q "Verify return code: 0 (ok)"; then
  pass "TLS handshake from $cloudflared_svc -> nginx: VERIFY OK"
else
  printf "WARN: TLS handshake did not verify as OK. OpenSSL output (sanitized):\n" >&2
  printf '%s\n' "$(printf '%s' "$openssl_out" | sed -n '1,60p')" >&2
  fail "TLS verification failed. Check nginx certificates, CA trust inside cloudflared, or RUNBOOK CA flip drill."
fi

printf "\nALL INTERNAL CHECKS PASS\n"
exit 0
