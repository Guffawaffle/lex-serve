#!/bin/sh
set -eu

HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
ROOT="$HERE/.."
DIST_DIR="$ROOT/dist"
TS="$(date +%Y%m%d-%H%M%S)"
OUT_FILE="$DIST_DIR/nginx-cloudflared-PORTABLE-$TS.tar.gz"

# Files/dirs to include (relative to repo root)
INCLUDE="
docker-compose.yml
cloudflared/config.yml
nginx/conf.d
docs
.env.example
cloudflared/Dockerfile
"

# Exclude patterns (explicit)
EXCLUDE_PATTERNS="
--exclude=./nginx/certs/*
--exclude=./cloudflared/tunnel.json
--exclude=./.env
--exclude=./cloudflared/ca/*
"

mkdir -p "$DIST_DIR"

# Build tar command
cd "$ROOT"

# Ensure required files exist (non-fatal if optional files missing; warn)
for f in docker-compose.yml; do
  if [ ! -f "$f" ]; then
    echo "ERROR: required file '$f' missing" >&2
    exit 2
  fi
done

# Prepare include list for tar - use --files-from via a temp file for safety
TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

# Add only existing include entries
for p in $INCLUDE; do
  if [ -e "$p" ]; then
    echo "./$p" >> "$TMPFILE"
  fi
done

echo "Creating portable bundle at: $OUT_FILE"
tar czf "$OUT_FILE" $(echo $EXCLUDE_PATTERNS) --files-from="$TMPFILE"

echo "Bundle created: $OUT_FILE"
echo "Included:"
tar tzf "$OUT_FILE" | sed -n '1,50p' | sed 's/^/  /'
echo ""
echo "Excluded (patterns):"
echo "  - nginx/certs/*"
echo "  - cloudflared/tunnel.json"
echo "  - .env"
echo "  - cloudflared/ca/*"
echo ""
echo "Notes:"
echo "  - The bundle intentionally excludes secrets (certs, tunnel credentials, .env)."
echo "  - On target host, operator must place secrets per PREFLIGHT before starting the stack."
exit 0
