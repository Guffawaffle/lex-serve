# Tarpit & Honeypot Architecture

## Overview

lex-serve implements a multi-layer tarpit and honeypot system to trap and waste attacker resources while protecting real services.

## Layers

### Layer 1: SSH Tarpit (endlessh-go)
- **Service**: `endlessh` container
- **Port**: 2222 (internal), exposed via Cloudflare Tunnel
- **Behavior**: Slowly sends infinite random SSH banners (10 second delay between lines)
- **Purpose**: Trap SSH scanners indefinitely, waste their time
- **Metrics**: Prometheus metrics on port 2112

**Cloudflare Zero Trust Setup Required**:
```
Subdomain: ssh
Domain: smartergpt.dev
Type: TCP
URL: endlessh:2222
```

### Layer 2: HTTP Tarpit (nginx)
Honeypot endpoints that return slow-drip responses:

| Endpoint | Rate Limit | Bandwidth | Purpose |
|----------|-----------|-----------|---------|
| `/admin.php` | 1 req/min | 128 B/s | Fake admin panel |
| `/login.php` | 1 req/min | 128 B/s | Fake login page |
| `/wp-login.php` | 1 req/min | 128 B/s | Fake WordPress |
| `/administrator/index.php` | 1 req/min | 128 B/s | Fake Joomla |

### Layer 3: Attack Pattern Detection
Attack patterns get slow 403 responses or silent drops:

| Pattern | Response | Bandwidth |
|---------|----------|-----------|
| VCS probes (`.git`) | 403 | 64 B/s |
| Config files (`.env`, `.sql`) | 403 | 64 B/s |
| CMS probes (wp-admin, etc) | 403 | 64 B/s |
| Admin panels (phpmyadmin) | 403 | 64 B/s |
| Script files (.php, .asp) | 403 | 64 B/s |
| Exploits (shell, exec) | 444 (drop) | N/A |

### Layer 4: Connection & Bandwidth Limits

| Limit | Value | Purpose |
|-------|-------|---------|
| Max connections per IP | 50 | Prevent resource exhaustion |
| Max total connections | 1000 | Server protection |
| Global bandwidth cap | 1 Mbps | Prevent saturation |
| Tarpit bandwidth | 128 B/s | Waste attacker time |
| Attack pattern bandwidth | 64 B/s | Extra slow for probes |

## Service Routing Priority

1. **Real endpoints (FAST PATH)**
   - `smartergpt.dev` - Main website
   - `cloud.smartergpt.dev` - Nextcloud (when profile enabled)
   - `/healthz` - Container health checks

2. **Honeypot endpoints (TARPIT)**
   - Fake login pages, admin panels
   - Slow drip responses, rate limited

3. **Attack patterns (SLOW 403 or DROP)**
   - VCS metadata, config files, CMS probes
   - Bandwidth throttled or silent drop

4. **Unknown hosts (DROP)**
   - Any request to unknown `server_name` → 444

## Logging

All honeypot hits are logged to `/var/log/nginx/honeytrap.log` in JSON format:

```json
{
  "timestamp": "2025-11-28T10:00:00+00:00",
  "remote_addr": "1.2.3.4",
  "cf_connecting_ip": "5.6.7.8",
  "cf_ipcountry": "CN",
  "request_uri": "/.git/config",
  "attack_type": "vcs_probe",
  "http_user_agent": "curl/7.68.0"
}
```

Analyze with:
```bash
./analyze-honeytrap.sh
```

## Cloudflare Zero Trust Configuration

### Required Routes

| Subdomain | Type | Target | Purpose |
|-----------|------|--------|---------|
| smartergpt.dev | HTTPS | nginx:443 | Main website |
| www.smartergpt.dev | HTTPS | nginx:443 | Main website |
| ssh.smartergpt.dev | TCP | endlessh:2222 | SSH tarpit |
| cloud.smartergpt.dev | HTTPS | nginx:443 | Nextcloud (optional) |

### Update Tunnel Config

1. Go to Cloudflare Dashboard → Zero Trust → Access → Tunnels
2. Find your tunnel (token in `.env`)
3. Add each hostname above

## Container Management

```bash
# Start all (without Nextcloud)
docker compose up -d

# Start with Nextcloud
docker compose --profile nextcloud up -d
# Note: Enable cloud.smartergpt.dev.conf.nextcloud first:
# mv nginx/conf.d/cloud.smartergpt.dev.conf.nextcloud nginx/conf.d/cloud.smartergpt.dev.conf

# Reload nginx after config changes
docker compose exec nginx nginx -s reload

# View tarpit logs
docker compose logs endlessh -f

# View honeytrap hits
tail -f nginx/logs/honeytrap.log | jq .
```

## Metrics

Endlessh exports Prometheus metrics:
- `endlessh_client_open_count_total` - Total connection attempts
- `endlessh_trapped_time_seconds_total` - Total seconds attackers wasted
- `endlessh_sent_bytes_total` - Total bytes sent to trappers

Access at: `http://endlessh:2112/metrics` (internal network only)

