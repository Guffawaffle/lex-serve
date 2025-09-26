#!/bin/sh
# Final E2E dry-run: guards + smoke + synthetics. Requires stack up & DNS.
# Usage: DOMAIN=example.com N=3 ./scripts/release-dry-run.sh
set -eu

DOMAIN="${DOMAIN:-}"
[ -n "$DOMAIN" ] || { echo "ERROR: DOMAIN is required"; exit 2; }
N="${N:-3}"
# Where to record successful dry-run timestamp (best-effort)
DRY_RUN_MARKER=".git/.last-release-dry-run"

run() {
  echo "== $1 =="
  shift
  cmd="$*"
  # Do not leak env secrets; run command
  if ! sh -c "$cmd"; then
    echo "DRY-RUN FAIL: step failed: $1"
    exit 3
  fi
}

# Ensure helper scripts are executable if present
chmod +x ./scripts/guard-validate.sh 2>/dev/null || true
chmod +x ./scripts/guard-images.sh 2>/dev/null || true
chmod +x ./scripts/smoke-compose.sh 2>/dev/null || true
chmod +x ./scripts/slo-gate.sh 2>/dev/null || true

run "Guard: validate" ./scripts/guard-validate.sh
run "Guard: image pinning" ./scripts/guard-images.sh
run "Smoke: compose (static checks)" ./scripts/smoke-compose.sh

echo "== Synthetics: SLO gate (N=${N}) =="
# slo-gate.sh expects DOMAIN and N in env
if ! DOMAIN="$DOMAIN" N="$N" ./scripts/slo-gate.sh; then
  echo "DRY-RUN FAIL: synthetics failed"
  exit 4
fi

# record timestamp for tag helper best-effort check
if [ -d .git ]; then
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$DRY_RUN_MARKER" || true
fi

echo "DRY-RUN PASS: all guards and synthetics succeeded."
exit 0
