#!/bin/bash
set -euo pipefail

# doctor.sh — HTTPS-first stack health validation
# Cloudflare Edge → cloudflared (token) → Nginx:443 (TLS)

# ===== Colors =====
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'

# ===== Config (overridable via flags/env) =====
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-smartergpt}"
DOMAIN="${DOMAIN:-smartergpt.dev}"
SERVICE="${SERVICE:-nginx}"
PORT="${PORT:-443}"
CA_PATH_DEFAULT="ssl/cloudflare-origin/origin-ca.pem"
CA_PATH="${CA_PATH:-$CA_PATH_DEFAULT}"
EXPECT_CODES="${EXPECT_CODES:-200,301,302,404}"
NO_RECREATE="false"

# ===== CLI flags =====
while [[ $# -gt 0 ]]; do
	case "$1" in
		--no-recreate) NO_RECREATE="true"; shift ;;
		--domain) DOMAIN="$2"; shift 2 ;;
		--service) SERVICE="$2"; shift 2 ;;
		--port) PORT="$2"; shift 2 ;;
		--ca) CA_PATH="$2"; shift 2 ;;
		--expect) EXPECT_CODES="$2"; shift 2 ;;
		-h|--help)
			cat <<EOF
Usage: $0 [--no-recreate] [--domain smartergpt.dev] [--service nginx] [--port 443] [--ca path] [--expect "200,301,302,404"]
EOF
			exit 0 ;;
		*) echo "Unknown flag: $1" >&2; exit 2 ;;
	esac
done

cd "$PROJECT_ROOT"

# ===== Logging =====
log() { printf '%s\n' "$*"; }
info(){ printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()  { printf "${GREEN}[✅ PASS]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[⚠️ WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[❌ FAIL]${NC} %s\n" "$*"; }

declare -A GATE
gate_pass(){ GATE["$1"]="PASS"; ok "Gate $1: $2"; }
gate_fail(){ GATE["$1"]="FAIL"; err "Gate $1: $2"; }

# ===== Helpers =====
require_cmd() {
	for c in "$@"; do command -v "$c" >/dev/null || { err "Missing command: $c"; exit 2; }; done
}
json_mounts() {
	local cid="$1"
	docker inspect "$cid" --format '{{json .Mounts}}'
}
first_network_of() {
	local cid="$1"
	docker inspect "$cid" --format '{{range $k,$v:=.NetworkSettings.Networks}}{{printf "%s\n" $k}}{{end}}' | head -n1
}
container_id() { docker compose ps -q "$1"; }

status_is_healthy() {
	local svc="$1"
	docker compose ps "$svc" --format '{{.Status}}' | grep -q 'healthy'
}

openssl_has_san() {
	local crt="$1" host="$2"
	openssl x509 -in "$crt" -noout -ext subjectAltName 2>/dev/null | grep -Eq "(DNS:|IP:).*${host}"
}

curl_internal_tls() {
	local net="$1" host_header="$2" service="$3" port="$4" expect_codes_csv="$5" ca_file="$6"
	local code exp_ok="false"
	local curl_img="curlimages/curl:8.10.1"
	local args=( -sS -o /dev/null -w '%{http_code}' "https://${host_header}:${port}" --connect-to "${host_header}:${port}:${service}:${port}" -H "Host: ${host_header}" --connect-timeout 8 --max-time 12 )
	if [[ -f "$ca_file" ]]; then
		args+=( --cacert "/ca/$(basename "$ca_file")" )
	else
		args+=( -k )
	fi
	code=$(docker run --rm --network "$net" -v "$PWD/$(dirname "$ca_file"):/ca:ro" "$curl_img" "${args[@]}")
	IFS=',' read -ra want <<<"$expect_codes_csv"
	for w in "${want[@]}"; do [[ "$code" == "$w" ]] && exp_ok="true"; done
	if [[ "$exp_ok" == "true" ]]; then
		ok "Internal HTTPS ${service}:${port} returned ${code} (Host: ${host_header})"
		return 0
	else
		err "Internal HTTPS ${service}:${port} returned ${code} (wanted ${expect_codes_csv})"
		return 1
	fi
}

# ===== Banner =====
echo
echo "🔬 HTTPS-First Stack Doctor — Cloudflare → cloudflared → ${SERVICE}:${PORT}"
echo "Project: ${COMPOSE_PROJECT_NAME} | Domain: ${DOMAIN} | Root: ${PROJECT_ROOT}"
echo "Expect: ${EXPECT_CODES} | CA: ${CA_PATH}"
echo "=============================================================="
echo

# 🚪 Gate 0: Host sanity (single tunnel, perms, mounts)
echo "🚪 Gate 0: Host sanity"
CLOUD_INIT_ACTIVE="$(systemctl is-active cloudflared 2>/dev/null || true)"
if [[ "$CLOUD_INIT_ACTIVE" == "active" ]] || pgrep -fa cloudflared >/dev/null; then
	err "Host-level cloudflared detected (service=${CLOUD_INIT_ACTIVE}). This causes tunnel conflicts."
	err "Run: sudo systemctl stop cloudflared && sudo systemctl disable cloudflared"
	GATE[0]="FAIL"
else
	ok "No host-level cloudflared running"
	GATE[0]="PASS"
fi

# key/cert perms (fail hard if bad)
KEY="ssl/cloudflare-origin/origin.key"
CRT="ssl/cloudflare-origin/origin.crt"
if [[ ! -f "$KEY" || ! -f "$CRT" ]]; then
	gate_fail 0 "Missing origin cert/key at ssl/cloudflare-origin/"
	exit 1
fi
# 600 root:root for key; 644 for crt
KEY_MODE=$(stat -c '%a' "$KEY"); KEY_OWNER=$(stat -c '%U:%G' "$KEY")
CRT_MODE=$(stat -c '%a' "$CRT"); CRT_OWNER=$(stat -c '%U:%G' "$CRT")
[[ "$KEY_MODE" == "600" && "$KEY_OWNER" == "root:root" ]] || warn "origin.key should be 600 root:root (is ${KEY_MODE} ${KEY_OWNER})"
[[ "$CRT_MODE" =~ ^64[04]$ ]] || warn "origin.crt should be 644 (is ${CRT_MODE})"

# cloudflared CA mount present?
CF_CID="$(docker compose ps -q cloudflared || true)"
if [[ -n "$CF_CID" ]] && docker inspect "$CF_CID" --format '{{json .Mounts}}' | grep -q '/etc/ssl/cloudflare-origin'; then
	ok "CA directory mounted into cloudflared (ro)"
else
	warn "CA directory NOT mounted into cloudflared; strict verify may fail"
fi
echo


require_cmd docker openssl

# ===== Gate 1 — Containers healthy + Nginx config valid =====
echo "🚪 Gate 1: Containers healthy + Nginx config valid"
[[ "$NO_RECREATE" == "true" ]] || info "Starting containers (force recreate)…"
[[ "$NO_RECREATE" == "true" ]] || docker compose up -d --force-recreate

info "Waiting a few seconds for healthchecks…"
sleep 8
docker compose ps

if ! status_is_healthy "$SERVICE"; then
	warn "Service '$SERVICE' not yet healthy"; fi
if ! status_is_healthy cloudflared; then
	warn "Service 'cloudflared' not yet healthy"; fi

NGINX_CID="$(container_id "$SERVICE")"
if docker exec "$NGINX_CID" nginx -t >/dev/null 2>&1; then
	ok "Nginx configuration is valid"
else
	gate_fail 1 "Nginx configuration test failed"
	exit 1
fi

if docker compose logs --since=3m cloudflared | egrep -qi 'Registered tunnel connection|Connection established|Updated to new configuration'; then
	gate_pass 1 "Containers healthy + Nginx config valid"
else
	gate_fail 1 "Cloudflared tunnel connection not confirmed in logs"
fi
echo

# ===== Gate 1.5 — Origin cert SAN check (extra) =====
echo "🔎 Extra: Verify origin cert SAN contains ${DOMAIN}"
if openssl_has_san "ssl/cloudflare-origin/origin.crt" "$DOMAIN"; then
	ok "Origin certificate SAN includes ${DOMAIN}"
else
	warn "Origin certificate SAN does not list ${DOMAIN} (SNI may fail strict verify)"
fi
echo

# ===== Gate 2 — Internal origin over TLS =====
echo "🚪 Gate 2: Internal TLS (service-name → ${PORT})"
NET_NAME="$(first_network_of "$NGINX_CID")"
if [[ -z "$NET_NAME" ]]; then
	gate_fail 2 "Could not determine Docker network for ${SERVICE}"
else
	info "Detected network: ${NET_NAME}"
	if curl_internal_tls "$NET_NAME" "$DOMAIN" "$SERVICE" "$PORT" "$EXPECT_CODES" "$CA_PATH"; then
		gate_pass 2 "Internal TLS to ${SERVICE}:${PORT} working"
	else
		gate_fail 2 "Internal TLS to ${SERVICE}:${PORT} failed"
	fi
fi
echo

# ===== Gate 3 — Zero Trust route sanity via logs =====
echo "🚪 Gate 3: Zero Trust route verification (from logs)"
LOGS="$(docker compose logs --since=5m cloudflared || true)"
SVC_OK=$(grep -c "service.*https://${SERVICE}:${PORT}" <<<"$LOGS" || true)
TLSV_OK=$(grep -c 'noTLSVerify.*false' <<<"$LOGS" || true)
SNI_OK=$(grep -c "originServerName.*${DOMAIN}" <<<"$LOGS" || true)

[[ "$SVC_OK" -gt 0 ]] || warn "Route not seen pointing to https://${SERVICE}:${PORT}"
[[ "$TLSV_OK" -gt 0 ]] || warn "TLS verify not confirmed as ON in recent logs"
[[ "$SNI_OK" -gt 0 ]] || warn "Origin server name not confirmed as ${DOMAIN} in recent logs"

if [[ "$SVC_OK" -gt 0 && "$TLSV_OK" -gt 0 ]]; then
	gate_pass 3 "Routes appear correct (service + verify); SNI=${DOMAIN} ${SNI_OK:+(seen)}"
else
	gate_fail 3 "Route config not fully confirmed from logs; check dashboard"
fi
echo

# ===== Gate 3.5 — CA pool mount exists (distroless-safe) =====
echo "🔎 Extra: Verify CA pool mount into cloudflared"
CF_CID="$(container_id cloudflared)"
if json_mounts "$CF_CID" | grep -q '/etc/ssl/cloudflare-origin'; then
	ok "CA directory mounted into cloudflared (ro)"
else
	warn "CA directory not mounted into cloudflared; strict verify may fail"
fi
echo

# ===== Gate 4 — External HTTPS through Edge =====
echo "🚪 Gate 4: External HTTPS (Edge → tunnel → origin)"
EXT_CODE="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 12 "https://${DOMAIN}")" || true
if grep -q "\b${EXT_CODE}\b" <<<"${EXPECT_CODES//,/ }"; then
	ok "External HTTPS returned ${EXT_CODE}"
	HEADERS="$(curl -sSI --max-time 12 "https://${DOMAIN}" || true)"
	grep -qi '^server: cloudflare' <<<"$HEADERS" && ok "Cloudflare edge detected"
	grep -qi '^strict-transport-security:' <<<"$HEADERS" && ok "HSTS present"
	gate_pass 4 "External HTTPS working via Cloudflare"
else
	gate_fail 4 "External HTTPS returned ${EXT_CODE} (wanted one of ${EXPECT_CODES})"
fi
echo

# ===== Summary =====
echo "📊 Gate Results"
PASS=0
for i in 1 2 3 4; do
	if [[ "${GATE[$i]:-FAIL}" == "PASS" ]]; then
		echo "Gate $i: ✅ PASSED"
		PASS=$((PASS + 1))
	else
		echo "Gate $i: ❌ FAILED"
	fi
done
echo
printf "Summary: %s/4 gates passed\n" "$PASS"
if [[ "$PASS" -eq 4 ]]; then
	echo -e "${GREEN}🎉 ALL GATES PASSED! HTTPS-first stack is fully operational.${NC}"
	exit 0
else
	echo -e "${RED}💥 SOME GATES FAILED! See notes above.${NC}"
	exit 1
fi
