#!/usr/bin/env bash
set -euo pipefail

echo "== git status (untracked only) =="
git status --porcelain=v1 -uno || true
echo

echo "--- tracked cloudflared/ca files ---"
git ls-files cloudflared/ca || true
echo

echo "== grep for private keys in tracked files =="
git grep -n --break --heading -I -E "BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|PRIVATE KEY-----" || true
echo

echo "== grep for likely secret tokens =="
git grep -n --break --heading -I -E "TUNNEL_SECRET|TunnelSecret|api[_-]?key|secret|password|token" || true
echo

echo "== show .gitignore lines relevant to secrets =="
grep -nE 'cloudflared/ca/|\.env|\.pem|\.key|\.crt|nginx/certs/' .gitignore || echo "(no matching lines)"
echo

echo "== recent history mentions (ids or filenames) =="
git rev-list --objects --all | grep -E 'cloudflared/ca|origin\.(key|crt)|\.pem' || true
echo

echo "Completed. If something was committed, rotate and purge history."
