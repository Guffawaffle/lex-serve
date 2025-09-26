#!/bin/sh
# Simple synthetic probe for the public edge.
# Usage: DOMAIN=example.com THRESH_MS=1500 ./scripts/synthetic-edge.sh

set -eu

DOMAIN=${DOMAIN:-}
if [ -z "$DOMAIN" ]; then
	echo "DOMAIN environment variable required" >&2
	exit 2
fi

THRESH_MS=${THRESH_MS:-1500}
# Perform request, follow redirects, capture status and total time
OUT=$(curl -sS -D - -o /dev/null -L --connect-timeout 10 --max-time 30 "https://${DOMAIN}/" 2>/dev/null || true)
# If curl itself failed, OUT may be empty
if [ -z "$OUT" ]; then
	echo "FAIL curl failed to reach https://${DOMAIN}/" >&2
	exit 1
fi

# Get numeric status and time_total using a second curl write-out to avoid parsing headers
read HTTP_CODE TIME_S <<EOF
$(curl -sS -o /dev/null -w "%{http_code} %{time_total}" -L --connect-timeout 10 --max-time 30 "https://${DOMAIN}/")
EOF

TIME_MS=$(awk "BEGIN{printf \"%d\", $TIME_S * 1000}")

# Check for Cloudflare headers (CF-Cache-Status, CF-RAY, or Server: cloudflare)
HEADERS=$(curl -sS -I -L --connect-timeout 10 --max-time 10 "https://${DOMAIN}/" 2>/dev/null || true)
echo "$HEADERS" | grep -i -E 'CF-Cache-Status:|CF-RAY:|Server: cloudflare' >/dev/null 2>&1
HAS_CF=$?

if [ "${HTTP_CODE%% *}" -ge 200 ] && [ "${HTTP_CODE%% *}" -lt 300 ] && [ "$TIME_MS" -le "$THRESH_MS" ] && [ "$HAS_CF" -eq 0 ]; then
	printf "PASS edge %s %dms\n" "$HTTP_CODE" "$TIME_MS"
	exit 0
else
	printf "FAIL edge status=%s time=%dms cf-header=%d\n" "$HTTP_CODE" "$TIME_MS" "$HAS_CF" >&2
	exit 1
fi
