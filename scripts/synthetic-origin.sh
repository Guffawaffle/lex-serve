#!/bin/sh
# Synthetic probe for origin connectivity from inside the tunnel/container network.
# Intended to be executed from within cloudflared container or a container on the same Docker network.
# Usage: DOMAIN=example.com THRESH_MS=1500 ./scripts/synthetic-origin.sh
set -eu

DOMAIN=${DOMAIN:-}
if [ -z "$DOMAIN" ]; then
	echo "DOMAIN environment variable required" >&2
	exit 2
fi

THRESH_MS=${THRESH_MS:-1500}

# Resolve the 'nginx' hostname on the container network to an IP
NGINX_IP=$(getent hosts nginx 2>/dev/null | awk '{print $1}' || true)
if [ -z "$NGINX_IP" ]; then
	echo "Unable to resolve 'nginx' container address. Run this from cloudflared or a container on the same Docker network." >&2
	exit 2
fi

# Use --resolve to ensure SNI matches DOMAIN while connecting directly to NGINX_IP.
# Do not disable TLS verification (no --insecure).
OUT=$(curl -sS -D - -o /dev/null --resolve "${DOMAIN}:443:${NGINX_IP}" -L --connect-timeout 10 --max-time 30 "https://${DOMAIN}/" 2>/dev/null || true)
if [ -z "$OUT" ]; then
	echo "FAIL origin curl failed" >&2
	exit 1
fi

read HTTP_CODE TIME_S <<EOF
$(curl -sS -o /dev/null -w "%{http_code} %{time_total}" --resolve "${DOMAIN}:443:${NGINX_IP}" -L --connect-timeout 10 --max-time 30 "https://${DOMAIN}/")
EOF

TIME_MS=$(awk "BEGIN{printf \"%d\", $TIME_S * 1000}")

if [ "${HTTP_CODE%% *}" -ge 200 ] && [ "${HTTP_CODE%% *}" -lt 300 ] && [ "$TIME_MS" -le "$THRESH_MS" ]; then
	printf "PASS origin %s %dms\n" "$HTTP_CODE" "$TIME_MS"
	exit 0
else
	printf "FAIL origin status=%s time=%dms\n" "$HTTP_CODE" "$TIME_MS" >&2
	exit 1
fi
