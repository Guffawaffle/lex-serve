# ...existing RUNBOOK content...

## Drift cleanup (Gate 8)
- Removed references and mounts to Let's Encrypt and unrelated host paths from docker-compose. The stack no longer mounts:
  - ./letsencrypt:/etc/letsencrypt:ro
  - ./ssl/cloudflare-origin:/etc/ssl/cloudflare-origin:ro
  - /home/guff/LoquiLex/loquilex/ui/web/dist:/var/www/html:ro
- Canonical operator-managed origin cert/key location: ./nginx/certs/
  - Do NOT commit certificates or keys. Ensure ./nginx/certs is listed in .gitignore and populated by operators at deploy time.
- Rationale: Let's Encrypt and unrelated app artifacts are out-of-scope for this hardened Cloudflare + Origin CA deployment.

## Resilience Drills (Gate 6)

Run the following copy-paste command blocks to exercise failure/recovery scenarios. These are intended for operators and can be run on staging or controlled environments.

### Crash / Restart drill
Crash nginx and observe recovery:
```
# Kill nginx, wait for restart and check health
docker compose kill nginx
sleep 3
docker compose ps nginx
# Wait for health to recover
for i in 1 2 3 4 5; do
  docker compose exec -T nginx sh -c "curl -fsS -m 2 http://localhost/healthz" >/dev/null 2>&1 && break || sleep 2
done
docker compose ps --services --filter "status=running"
```

Repeat the same for cloudflared (replace nginx -> cloudflared). Confirm `docker compose ps` shows the service as restarted and `docker compose logs --tail=50 <svc>` shows healthy startup.

### Tunnel credential rotation
Replace the operator-supplied tunnel credential bundle and bring cloudflared back up:
```
# Stop cloudflared
docker compose stop cloudflared || true

# Operator: replace the file ./cloudflared/tunnel.json with new credentials (do NOT commit)
# cp /secure/location/new-tunnel.json ./cloudflared/tunnel.json

# Start and verify
docker compose up -d cloudflared
# Check active tunnel via Cloudflare dashboard or via container logs:
docker compose logs --tail=100 cloudflared | sed -n '1,200p'
```
Confirm Cloudflare dashboard shows the tunnel "Active". If it does not, check the credentials file and ensure the tunnel ID used in .env is correct.

### CA trust flip (debug-only)
Temporarily enable noTLSVerify to validate routing without CA trust. Do this only in a controlled environment, and revert immediately.

```
# Edit cloudflared/config.yml and temporarily uncomment or add:
# noTLSVerify: true

# Restart cloudflared and test internal path:
docker compose restart cloudflared
# From cloudflared container:
docker compose exec -T cloudflared sh -c "openssl s_client -connect nginx:443 -servername '${DOMAIN}' </dev/null | sed -n '1,20p'"

# REVERT: remove/comment noTLSVerify and restart cloudflared
# (Immediate revert required)
```

Do not enable noTLSVerify in production; use it only for short-lived debugging.

### Network isolation check
Prove there are no host-published ports by default:
```
docker compose config --services
# Show docker ps ports for this project
docker ps --format '{{.Names}} :: {{.Ports}}' | sed -n '1,200p'
# Or use the helper:
./scripts/check-no-host-ports.sh
```

## Test Matrix

Scenario -> Command(s) -> Expected signal -> Likely fix on failure

- Fresh bring-up -> docker compose up -d && ./scripts/smoke-compose.sh -> PASS compose/config checks -> fix YAML, ensure required config files present
- Internal TLS fail -> ./scripts/smoke-internal.sh -> OpenSSL shows Verify return code != 0 -> add CA to cloudflared trust or install correct certs in nginx
- External edge 4xx/5xx -> ./scripts/smoke-external.sh -> 2xx / Cloudflare headers present -> check origin application logs, firewall, or route rules
- Tunnel down -> docker compose ps / docker compose logs cloudflared -> cloudflared not running / errors -> check tunnel.json credentials, cloudflared logs, and Cloudflare dashboard
- SNI mismatch -> openssl output shows certificate for different name -> ensure nginx cert matches DOMAIN or update SNI configuration
- CA not trusted -> openssl Verify return code non-zero -> import CA into cloudflared/trusted CA store or use operator CA bundle
- Wrong profile exposing ports -> ./scripts/smoke-compose.sh -> warns about ports without dev profile -> move ports: to service under profiles: - dev or remove host publishing

# End of appended RUNBOOK changes

## Cloudflare Edge Settings (Gate 7)

Checklist (operator must confirm each):
- [ ] SSL/TLS: set to "Full (strict)" (Dashboard: Domain > SSL/TLS).
  - TLS versions: allow TLS 1.2 and TLS 1.3 only.
  - HTTP/2: enabled (SSL/TLS -> Edge Certificates).
  - HSTS: optional. Impact: enabling HSTS will cause browsers to remember HTTPS-only access; enable only after validating all hosts and subdomains.
- [ ] WAF: Managed Rules ON (Dashboard: Security -> WAF -> Managed Rules).
  - Bot Fight Mode: optional. Note: tune to avoid false positives.
  - If you need to exclude health probes, create a bypass rule for path /healthz (Firewall Rules -> Create a rule: expression uri.path eq "/healthz" -> action: Allow).
- [ ] Caching: Standard caching ON. Bypass cache for /healthz and POST (Page Rules or Cache Rules).
  - Example Page Rule: If URL matches *example.com/healthz* -> Cache Level: Bypass.
  - For POST requests, ensure caching rules don't cache POST.
- [ ] Rate Limiting: create rules to protect origins.
  - Example: if requests from single IP > 300 requests per 1 minute -> block/return 429.
  - Add an exception clause "if Cloudflare Client is a verified bot" or skip known good sources.
  - Dashboard path: Security -> Tools -> Rate Limiting (UI may vary; search "Rate Limiting" in the domain dashboard).
- [ ] Zero exposure: ensure proxy (orange cloud) is enabled and origin IPs are not published publicly. Verify no A/AAAA record points directly to origin (DNS tab).
- [ ] Transform Rules / Edge headers: while Cloudflare can inject headers via Transform Rules, prefer setting security headers at origin (Nginx) for portability. If using Cloudflare Transform Rules, add them under Rules -> Transform Rules.

Verification cues:
- SSL/TLS: Dashboard shows "Full (strict)" and TLS analytics show accepted TLSv1.2/1.3 connections.
- WAF: Security -> Events shows blocked requests and matched rule IDs.
- Rate limiting: Security -> Events / Analytics shows triggered rate-limiting events; you will see 429s in Access logs.
- Cloudflare presence in responses: look for CF-Cache-Status or CF-RAY headers in response headers.
- Check "Edge is active" by curling the public domain and verifying CF-* headers:
  curl -I https://$DOMAIN | egrep 'CF-(Cache-Status|RAY)|Server: cloudflare'

Notes on false positives and bypasses:
- If legitimate traffic (health checks, CI IPs) are blocked, create Firewall Rules to bypass for those specific URIs / IPs.

## Synthetics & SLOs

Default thresholds (tunable):
- Edge median latency: 1500 ms (EDGE_THRESH_MS)
- Origin median latency: 1500 ms (ORIGIN_THRESH_MS)
- Runs to compute median: N=3 (default)

Scripts (in repo):
- scripts/synthetic-edge.sh
  - Validates external edge: 2xx response, Cloudflare headers present, latency <= threshold.
  - Usage: DOMAIN=example.com THRESH_MS=1500 ./scripts/synthetic-edge.sh
- scripts/synthetic-origin.sh
  - Run from inside cloudflared (or container on same Docker network). Validates direct origin reachability and TLS.
  - Usage: DOMAIN=example.com THRESH_MS=1500 ./scripts/synthetic-origin.sh
- scripts/slo-gate.sh
  - Runs both checks N times and computes medians.
  - Usage: N=3 DOMAIN=example.com ./scripts/slo-gate.sh

- Interpretation:
  - Scripts return 0 on PASS, non-zero on FAIL. Use these in CI/CD gates or operator checks before cutover.
  - If origin synthetic fails because of TLS (e.g., Cloudflare Origin CA is not trusted inside container), ensure the container has the origin CA installed before trusting.

## GATE 10 — Observability, Alerting & Incident Workflow

Purpose: provide concise operator guidance to turn healthchecks, cloudflared metrics, and Nginx logs into actionable monitoring and incident response. No secrets, no host port changes, docs-only instrumentation guidance.

### 1) Metrics & Logs (docs-first)

- cloudflared metrics:
  - Remain internal-only: exposed on 127.0.0.1:8080 inside the cloudflared container by default.
  - Docs-only Prometheus scrape stub (operator-run sidecar or host agent approach — do not add containers here):
    - Idea: have a small agent run on the Docker host that runs: docker exec cloudflared curl -s http://127.0.0.1:8080/metrics and exposes those metrics to Prometheus.
    - Example scrape job (concept, implement in your Prometheus config):
      - job_name: 'cloudflared'
        metrics_path: /metrics
        static_configs:
          - targets: ['localhost:XXXX']  # agent exposes metrics on localhost:XXXX
- Metrics Map (what to collect)
  - cloudflared:
    - tunnel_status (up/down), connection_count, RTT, reconnect_count
  - Nginx:
    - 2xx/4xx/5xx rate, request_latency (log-derived p50/p95), 429 rate
  - Synthetics:
    - edge_latency_ms, origin_latency_ms, synthetics_pass_rate (N runs)
- Log parsing guidance (one-liners)
  - 5xx rate (sample): grep access.log | awk '{print $9}' | grep -E '^5' | wc -l
  - 429 rate (sample): grep access.log | awk '{print $9}' | grep '^429$' | wc -l
  - Use these counts divided by total requests in the same interval for percent calculations.

### 2) SLOs & Alerts

- SLO Targets (concrete)
  - Availability SLO: 99.9% monthly (allowed downtime ≈ 43 minutes/month).
  - Latency SLOs:
    - Edge: p50 ≤ 800ms, p95 ≤ 1500ms
    - Origin: p50 ≤ 500ms, p95 ≤ 1200ms

- Alert rules (doc definitions with thresholds, actionable first actions and where to look)
  - P1: Tunnel disconnected > 3m OR reconnects > 5 in 10m
    - First action: check cloudflared logs (docker compose logs cloudflared), verify tunnel.json and env TUNNEL ID, check egress/network/firewall.
    - Where to look: cloudflared logs, host firewall, Cloudflare dashboard (Tunnel status).
  - P1: 5xx rate > 3% for 5m OR edge synthetic failing 3/3 runs
    - First action: capture Nginx 5xx samples (tail logs), roll back recent nginx changes if any, enable debug log if needed.
    - Where to look: nginx access/error logs, container healthchecks, app upstream logs.
  - P2: Edge p95 > 1500ms for 15m OR Origin p95 > 1200ms for 15m
    - First action: run slo-gate.sh with N=5 to confirm, check Cloudflare analytics for region-specific spikes.
    - Where to look: synthetics output, Cloudflare analytics, nginx request latency (log-derived).
  - P2: 429 rate-limit > 5% sustained for 10m
    - First action: inspect client IPs (are they legitimate CI/health checks?), temporarily relax or disable rate-limit rule.
    - Where to look: nginx access logs, Cloudflare Firewall/Rate Limiting events.

- Suggested alert playbook pointers (short)
  - Include a link or command in the alert to run: DOMAIN=$DOMAIN N=3 ./scripts/slo-gate.sh and collect logs: docker compose logs --tail=200 nginx cloudflared

### 3) Incident Workflow (Gate 10)

- Triage
  1. Identify scope: Edge (Cloudflare) vs Tunnel vs Origin (nginx) vs application.
  2. Gather artifacts:
     - cloudflared logs: docker compose logs --tail=500 cloudflared
     - nginx logs: docker compose logs --tail=500 nginx && docker compose exec -T nginx tail -n 200 /var/log/nginx/access.log
     - Synthetics: run ./scripts/synthetic-edge.sh and ./scripts/synthetic-origin.sh
  3. Determine impact (users affected, regions, percent errors).

- Mitigation playbooks (concise)
  - Tunnel flapping
    - Check tunnel.json and .env tunnel ID, verify egress connectivity.
    - Rotate credentials (see Gate 4) if credentials appear compromised.
    - Temporary scale: run a second cloudflared instance under a named profile (operator note; do not publish host ports).
  - 5xx spike
    - Rollback last nginx/application deploy if correlated with deploy time.
    - Temporarily disable rate-limit rules (commented config stanza at origin or Cloudflare bypass).
    - Increase debugging and capture request traces for upstream services.
  - Latency spike
    - Check Cloudflare analytics for geo/regional anomalies.
    - Run slo-gate.sh with N>5 to determine if transient or sustained.
    - Investigate upstream app performance and connection saturation.

- Communications (stakeholder update template)
  - Subject: [INCIDENT] <Short impact> — <service> — <start time>
  - Body (short):
    - Impact: who/how many affected and symptom (e.g., 5xx/errors/high latency).
    - Start time: <timestamp>
    - Current status: <what you have done (triage/mitigation)>
    - Next action and ETA: <planned mitigation, ETA>
    - Link to logs/dashboards: <links>
    - Sender & follow-up cadence: e.g., every 15m until resolved.

- Postmortem template (short)
  - Summary: one-line summary and impact metrics (duration, users affected).
  - Timeline: key events with timestamps.
  - Root Cause: brief technical cause.
  - Corrective Actions: immediate and long-term fixes.
  - Follow-ups & Owners: who is responsible and by when.

### 4) Runbook polish: Quick Commands & Golden Path

- Quick Commands (top operator copy-paste)
  1. Check services: docker compose ps
  2. Tail logs: docker compose logs --tail=200 nginx cloudflared
  3. Health probe nginx: docker compose exec -T nginx sh -c "curl -fsS -m 2 http://localhost/healthz"
  4. Kill & verify restart: docker compose kill nginx && sleep 3 && docker compose ps nginx
  5. Cloudflared logs: docker compose logs --tail=200 cloudflared
  6. Replace tunnel creds (operator): cp /secure/location/new-tunnel.json ./cloudflared/tunnel.json && docker compose up -d cloudflared
  7. Run edge synthetic: DOMAIN=$DOMAIN THRESH_MS=1500 ./scripts/synthetic-edge.sh
  8. Run origin synthetic: DOMAIN=$DOMAIN THRESH_MS=1500 ./scripts/synthetic-origin.sh
  9. Generate image digests: ./scripts/refresh-image-digests.sh nginx:1.26-alpine
  10. Check no host ports: docker ps --format '{{.Names}} :: {{.Ports}}'

- Golden Path (6-step checklist to go zero → green prod)
  1. Configure Cloudflare: SSL Full (strict), TLS 1.2+, HTTP/2, WAF ON.
  2. Ensure cloudflared tunnel active and credentials in ./cloudflared/tunnel.json (do not commit).
  3. docker compose up -d cloudflared nginx && docker compose ps (containers healthy).
  4. Run synthetics: N=3 DOMAIN=$DOMAIN ./scripts/slo-gate.sh → expect PASS.
  5. Monitor edge: curl -I https://$DOMAIN and look for CF-* headers and acceptable latency.
  6. Cut DNS over or flip route and monitor Cloudflare analytics + nginx logs for 30–60m.

## Release Flow (Gate 11)

1) Dry-Run:
   - `DOMAIN=$DOMAIN N=3 ./scripts/release-dry-run.sh` → expect PASS.
2) Manual spot-checks:
   - CF Analytics (Traffic/WAF/Rate Limit), edge headers, Nginx 5xx/429.
3) Tag:
   - `TAG=v1.0.0; TAG=$TAG ./scripts/tag-release.sh`
   - Push tag when ready: `git push origin $TAG` (triggers packaging CI).
4) Verify CI artifacts:
   - Package tarball under Actions → “Package on tag”.
   - Security scan & SBOM (Gate 9) available under Actions → “Security - Trivy + Syft SBOM”.
5) Announce:
   - Share tag + artifact links + CHANGELOG highlights.
6) Rollback (if needed):
   - Delete tag (local/remote), revert last changes, confirm health, re-run dry-run.

### Notes & Constraints
- No secrets are added to the repo. Do not commit tunnel.json or certificates.
- No host ports are exposed or recommended. Any agent that scrapes cloudflared metrics should run with local network access and not publish origin ports publicly.

# End of appended Gate 10 content

## Image Pinning & Scanning (Gate 9)

Why pin images
- Pinning images by digest (image@sha256:...) ensures immutable, reproducible deploys and prevents surprises from floating tags.
- Human-readable tags are kept in comments for operator clarity (e.g. "# nginx:1.26-alpine") but the runtime reference is the digest.

How to refresh digests (operator-run)
- Locally run:
  ./scripts/refresh-image-digests.sh
  or specify images:
  ./scripts/refresh-image-digests.sh nginx:1.26-alpine cloudflare/cloudflared:2025.1.0
- The script:
  - pulls the tagged image,
  - resolves the first RepoDigest,
  - updates docker-compose.yml in place replacing the tagged image with the digest while preserving the tag in a trailing comment,
  - prints a diff between the original and updated compose file.
- The script does NOT commit changes; review diffs and commit intentionally.

CI scanning & SBOMs
- A GitHub Actions workflow (.github/workflows/security.yml) runs on PRs and pushes to main.
- It runs Trivy:
  - filesystem scan (trivy fs) and
  - config audit (trivy config)
  - Fails the job on HIGH and CRITICAL findings (lower severities are warn-only because they are not included in the failing severity set).
- It runs Syft to produce an SBOM (spdx-json) named sbom-repo.spdx.json and uploads it as a workflow artifact.
- Find scan logs and the SBOM under the Actions tab for the run and download the artifact.

Policy
- PRs must not introduce unpinned images or use :latest. The guard (scripts/guard-images.sh) is run in the validate workflow and will fail CI if images are not pinned by digest.
