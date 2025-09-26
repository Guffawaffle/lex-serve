#!/usr/bin/env bash
# Simple guard to block committing obvious secrets.
set -euo pipefail

files=$(git diff --cached --name-only)
[ -z "$files" ] && exit 0

if echo "$files" | grep -E '^cloudflared/ca/|\.pem$|\.key$|\.pfx$|\.crt$' >/dev/null; then
  echo "✖ Blocked: attempting to commit potential secret/cert files."
  echo "  Fix: add to .gitignore or remove from index, and use env/volume mounts."
  exit 1
fi

# Scan staged contents for key markers
if git diff --cached -U0 | grep -E 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' >/dev/null; then
  echo "✖ Blocked: staged diff contains PRIVATE KEY block."
  exit 1
fi

# Detect accidental inclusion of a real-looking tunnel secret (heuristic: long base64 token assigned to TUNNEL_TOKEN= not placeholder)
if git diff --cached -U0 | grep -E 'TUNNEL_TOKEN=([A-Za-z0-9+/=]{24,})' | grep -vi '__REDACTED_TUNNEL_TOKEN__' >/dev/null; then
  echo "✖ Blocked: staged diff appears to contain a real TUNNEL_TOKEN value."
  exit 1
fi

exit 0
