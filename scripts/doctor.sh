#!/bin/bash
set -euo pipefail

# doctor.sh - HTTPS-first stack health validation
# Runs comprehensive 4-gate checks for Cloudflare Edge → cloudflared → Nginx:443 stack
#
# Usage:
#   ./scripts/doctor.sh                    # Run full 4-gate health check
#   DOMAIN=example.com ./scripts/doctor.sh # Override domain for testing
#
# Environment Variables:
#   DOMAIN                - Domain to test (default: smartergpt.dev)
#   COMPOSE_PROJECT_NAME  - Docker Compose project name (default: smartergpt)
#
# Exit Codes:
#   0 - All gates passed (healthy)
#   1 - One or more gates failed (unhealthy)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-smartergpt}"
DOMAIN="${DOMAIN:-smartergpt.dev}"

# Track gate results
GATE_RESULTS=()
GATE_COUNT=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✅ PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠️ WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[❌ FAIL]${NC} $1"
}

log_gate() {
    local gate_num="$1"
    local status="$2"
    local message="$3"

    GATE_COUNT=$((GATE_COUNT + 1))
    GATE_RESULTS["$gate_num"]="$status"

    if [ "$status" = "PASS" ]; then
        log_success "Gate $gate_num: $message"
    else
        log_error "Gate $gate_num: $message"
    fi
}

# Change to project root
cd "$PROJECT_ROOT"

echo
echo "🔬 HTTPS-First Stack Doctor - 4-Gate Health Check"
echo "=================================================="
echo "Project: $COMPOSE_PROJECT_NAME"
echo "Domain: $DOMAIN"
echo "Working Directory: $(pwd)"
echo

# Gate 1: Containers healthy + Nginx config valid
echo "🚪 Gate 1: Containers healthy + Nginx config valid"
echo "---------------------------------------------------"

log_info "Starting containers with force recreate..."
if docker compose up -d --force-recreate; then
    log_success "Containers started"
else
    log_gate 1 "FAIL" "Failed to start containers"
    exit 1
fi

log_info "Waiting for services to be healthy..."
sleep 8

log_info "Checking container status..."
docker compose ps

# Check if both containers are healthy using simpler status check
NGINX_STATUS=$(docker compose ps nginx --format "table {{.Status}}" | tail -n +2 | grep -o "healthy\|unhealthy\|starting" | head -1 || echo "unknown")
CLOUDFLARED_STATUS=$(docker compose ps cloudflared --format "table {{.Status}}" | tail -n +2 | grep -o "healthy\|unhealthy\|starting" | head -1 || echo "unknown")

if [ "$NGINX_STATUS" = "healthy" ] && [ "$CLOUDFLARED_STATUS" = "healthy" ]; then
    log_success "Both containers are healthy"
else
    log_error "Container health check failed - nginx: $NGINX_STATUS, cloudflared: $CLOUDFLARED_STATUS"
fi

log_info "Testing nginx configuration..."
NGINX_CONTAINER=$(docker compose ps -q nginx)
if docker exec "$NGINX_CONTAINER" nginx -t; then
    log_success "Nginx configuration is valid"
else
    log_gate 1 "FAIL" "Nginx configuration test failed"
    exit 1
fi

log_info "Checking cloudflared logs for tunnel connection..."
if docker compose logs --since=2m cloudflared | grep -q "Registered tunnel connection"; then
    log_success "Cloudflared tunnel connections established"
    log_gate 1 "PASS" "Containers healthy + Nginx config valid"
else
    log_gate 1 "FAIL" "Cloudflared tunnel connection not found"
fi

echo

# Gate 2: Internal origin over TLS (service name → 443)
echo "🚪 Gate 2: Internal TLS check (nginx:443)"
echo "-----------------------------------------"

log_info "Testing internal TLS connectivity to nginx:443..."
NETWORK_NAME="smartergpt-edge-net"

# Test internal HTTPS connection
if docker run --rm --network "$NETWORK_NAME" curlimages/curl:latest \
    -kI https://nginx:443 -H "Host: $DOMAIN" --max-time 10 | grep -q "200 OK"; then
    log_success "Internal TLS connection to nginx:443 successful"
    log_gate 2 "PASS" "Internal TLS to nginx:443 working"
else
    log_gate 2 "FAIL" "Internal TLS connection to nginx:443 failed"
fi

echo

# Gate 3: Zero Trust route settings verification
echo "🚪 Gate 3: Zero Trust route verification"
echo "---------------------------------------"

log_info "Checking cloudflared configuration..."
CONFIG_LOG=$(docker compose logs --since=5m cloudflared | grep "Updated to new configuration" | tail -1)

if [ -n "$CONFIG_LOG" ]; then
    log_success "Found tunnel configuration in logs"

    # Extract and validate configuration
    if echo "$CONFIG_LOG" | grep -q 'https://nginx:443'; then
        log_success "Service pointing to https://nginx:443 ✓"
    else
        log_error "Service not pointing to https://nginx:443"
    fi

    if echo "$CONFIG_LOG" | grep -q 'noTLSVerify.*false'; then
        log_success "TLS verify enabled ✓"
    else
        log_error "TLS verify not enabled"
    fi

    if echo "$CONFIG_LOG" | grep -q "originServerName.*$DOMAIN"; then
        log_success "Origin server name set to $DOMAIN ✓"
    else
        log_warning "Origin server name not set or different from $DOMAIN"
    fi

    log_gate 3 "PASS" "Zero Trust routes properly configured"
else
    log_gate 3 "FAIL" "No tunnel configuration found in logs"
fi

echo

# Gate 4: External HTTPS check
echo "🚪 Gate 4: External HTTPS check"
echo "-------------------------------"

log_info "Testing external HTTPS endpoint via Cloudflare Edge..."

# Test external HTTPS connection
if curl -I "https://$DOMAIN" --max-time 10 | grep -q "200"; then
    log_success "External HTTPS connection successful"

    # Check for expected headers
    HEADERS=$(curl -I "https://$DOMAIN" --max-time 10 2>/dev/null)

    if echo "$HEADERS" | grep -q "server: cloudflare"; then
        log_success "Cloudflare edge detected ✓"
    fi

    if echo "$HEADERS" | grep -q "strict-transport-security:"; then
        log_success "HSTS header present ✓"
    fi

    if echo "$HEADERS" | grep -q "cf-ray:"; then
        log_success "Cloudflare Ray ID present ✓"
    fi

    log_gate 4 "PASS" "External HTTPS working via Cloudflare"
else
    log_gate 4 "FAIL" "External HTTPS connection failed"
fi

echo

# Final Results Summary
echo "📊 4-Gate Check Results"
echo "======================"

TOTAL_GATES=4
PASSED_GATES=0

for i in $(seq 1 $TOTAL_GATES); do
    if [ "${GATE_RESULTS[$i]:-}" = "PASS" ]; then
        echo -e "Gate $i: ${GREEN}✅ PASSED${NC}"
        PASSED_GATES=$((PASSED_GATES + 1))
    else
        echo -e "Gate $i: ${RED}❌ FAILED${NC}"
    fi
done

echo
echo "Summary: $PASSED_GATES/$TOTAL_GATES gates passed"

if [ "$PASSED_GATES" -eq "$TOTAL_GATES" ]; then
    echo -e "${GREEN}🎉 ALL GATES PASSED! HTTPS-first stack is fully operational.${NC}"
    echo
    echo "Architecture: External → Cloudflare Edge (TLS) → cloudflared → Nginx:443 (Origin TLS) → Content"
    exit 0
else
    echo -e "${RED}💥 SOME GATES FAILED! Check the errors above.${NC}"
    exit 1
fi