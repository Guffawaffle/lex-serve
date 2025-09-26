#!/bin/sh
# Smoke test: compose validity, config files, profiles vs ports, .gitignore secrets
set -eu

fail() { printf "FAIL: %s\n" "$1" >&2; exit 2; }
pass() { printf "PASS: %s\n" "$1\n"; }

# 1) docker compose config
if ! docker compose config >/dev/null 2>&1; then
  fail "docker compose config failed. Run 'docker compose config' to see syntax errors."
fi
pass "compose config valid"

# 2) required non-secret config files/dirs
[ -f cloudflared/config.yml ] || fail "missing required config: cloudflared/config.yml"
[ -d nginx/conf.d ] || fail "missing required directory: nginx/conf.d"
pass "required config files present"

# 3) services that declare ports must be guarded by profiles: - dev
bad=$(awk '
  /^[[:space:]]{2}[A-Za-z0-9_-]+:/ { svc=$1; sub(":$","",svc); next }
  /^[[:space:]]{4}ports:/ { has_ports[svc]=1; next }
  /^[[:space:]]{4}profiles:/ {
    getline
    if ($0 ~ /- dev/) profiles[svc]=1
  }
  END {
    for (s in has_ports) if (!profiles[s]) print s
  }' docker-compose.yml || true)

if [ -n "$bad" ]; then
  fail "found services publishing host ports without 'profiles: - dev':\n$bad"
fi
pass "ports guarded by dev profile (no host ports by default)"

# 4) .gitignore coverage for secrets (non-exhaustive)
missing_patterns=""
check_pat() {
  pattern="$1"
  if ! grep -Fxq "$pattern" .gitignore 2>/dev/null; then
    missing_patterns="$missing_patterns\n  $pattern"
  fi
}
check_pat "cloudflared/tunnel.json"
check_pat "ssl/cloudflare-origin/*"
check_pat "*.pem"
check_pat "*.key"
check_pat "letsencrypt/"
if [ -n "$missing_patterns" ]; then
  printf "WARN: .gitignore missing common secret patterns:%s\n" "$missing_patterns" >&2
  # Not failing hard; operator may intentionally manage secrets differently.
else
  pass ".gitignore contains common secret patterns"
fi

printf "\nALL CHECKS PASS\n"
exit 0
