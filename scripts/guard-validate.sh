#!/bin/sh
# Guardrails: validate compose, .env.example keys, .gitignore, and cloudflared noTLSVerify
set -eu

fail() { printf "FAIL: %s\n" "$1" >&2; exit 2; }
warn() { printf "WARN: %s\n" "$1" >&2; }
pass() { printf "PASS: %s\n" "$1\n"; }

# 1) docker compose config
if ! docker compose config >/dev/null 2>&1; then
  fail "docker compose config failed. Fix compose YAML."
fi
pass "compose config OK"

# 2) collect ${VAR} occurrences from docker-compose.yml
vars=$(sed -n 's/.*${\([^}]\+\)}.*/\1/p' docker-compose.yml | sort -u || true)
if [ -z "${vars}" ]; then
  pass "no interpolated variables found in docker-compose.yml"
else
  if [ ! -f .env.example ]; then
    fail ".env.example missing; it should document required environment variables: $vars"
  fi
  missing=""
  for v in $vars; do
    if ! grep -E "^${v}=" .env.example >/dev/null 2>&1; then
      missing="$missing $v"
    fi
  done
  if [ -n "$missing" ]; then
    fail ".env.example missing entries for variables referenced in compose:$missing"
  fi
  pass ".env.example covers compose interpolated variables"
fi

# 3) .gitignore contains common secret patterns
need="cloudflared/tunnel.json ssl/cloudflare-origin/* *.pem *.key letsencrypt/"
miss=""
for p in $need; do
  if ! grep -Fxq "$p" .gitignore 2>/dev/null; then
    miss="$miss $p"
  fi
done
if [ -n "$miss" ]; then
  warn ".gitignore missing patterns:$miss"
else
  pass ".gitignore contains expected secret patterns"
fi

# 4) cloudflared config must not have active noTLSVerify: true/false (allowed only commented for debug)
if [ -f cloudflared/config.yml ]; then
  if grep -n '^[[:space:]]*noTLSVerify:' cloudflared/config.yml >/dev/null 2>&1; then
    fail "cloudflared/config.yml contains an active 'noTLSVerify:' entry. This is disallowed; use commented entries only for temporary debug."
  fi
  pass "cloudflared/config.yml OK (no active noTLSVerify)"
else
  warn "cloudflared/config.yml not present; ensure operator provides it at runtime"
fi

printf "\nALL GUARDRAIL CHECKS PASS (or warned). Fix failures before promoting.\n"
exit 0
