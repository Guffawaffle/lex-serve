<<<<<<< HEAD
## ...existing code...
## Merged README (kept detailed operator notes)

# lex-serve

Nginx + Cloudflared (Docker/Compose). Env-driven, RO site mount, simple configs.

## Validations & Drills

This repository includes lightweight validation scripts and runbook drills to ex
ercise resilience:
- Smoke tests (idempotent, POSIX sh):
  - scripts/smoke-compose.sh — validate compose and local config guardrails
  - scripts/smoke-internal.sh — internal connectivity & TLS checks (requires sta
ck up)
  - scripts/smoke-external.sh — edge / DNS routed checks (requires DNS/tunnel)
- Guardrails:
  - scripts/guard-validate.sh — pre-push/CI checks (compose, .env.example, .giti
gnore, noTLSVerify guard)
- Helpers:
  - scripts/check-no-host-ports.sh — quick fail if any running container exposes
 host ports
Run the RUNBOOK drills and review docs/RUNBOOK.md and docs/GUARDRAILS.md for pro
cedures and test matrix.
Drift cleanup (Gate 8)
- Removed all references/mounts to Let's Encrypt and unrelated host artifacts fr
om docker-compose.
- The origin certificate/key for Cloudflare Origin CA must be placed at:
  ./nginx/certs/
- Do NOT commit certs or tunnel credentials. These files are operator-managed an
d must remain out of VCS.

Security posture
- No host ports are published by default (dev profile only exposes ports when ex
plicitly used).
- CI workflows validate configuration and scripts on PRs and tag pushes; they do
 not run containers or include secrets.

## Remediation (2025-09-26)

Recent regression fixes applied to restore end-to-end delivery for https://smart
ergpt.dev via Cloudflare Tunnel:
1. Nginx container failed to start due to insufficient capabilities for privileg
e drop (setgid). Added CAP_SETGID and CAP_SETUID and ensured service not gated behind inactive profile.
2. Duplicate/conflicting server blocks (`site.conf` with `server_name localhost`
 and `smartergpt.dev.conf`) caused ambiguity and prior startup errors. Neutralized `site.conf`; consolidated config into `smartergpt.dev.conf`.
3. Mounted web root (`./www -> /var/www/html`) so static index is actually serve
d under TLS vhost.
4. Resolved origin TLS routing issues by adjusting Cloudflare Tunnel ingress rul
es to explicit hostnames (`smartergpt.dev` and `www.smartergpt.dev`).
5. Temporarily disabled origin TLS verification (`noTLSVerify: true`) to validat
e flow; site now returns 200 through Cloudflare. This MUST be reverted (or replaced with `caPool`) for production.
6. Added debug logging to cloudflared during investigation (consider downgrading
 to `info`).

### Outstanding Hardening Tasks
* Re-enable TLS verification: remove `noTLSVerify: true` and (optionally) supply
 Cloudflare Origin CA bundle via `caPool`.
* Remove deprecated `protocol: h2mux` (let it default to auto/http2).
* Consider rate limiting / additional caching headers for static assets.
* Add monitoring for 4xx/5xx spikes (metrics endpoint already present internally).
* Document operational reload procedure (`docker exec nginx nginx -s reload`).

### Quick Verification Commands
```
curl -Ik https://smartergpt.dev | grep 'HTTP/2 200'
docker compose logs --tail=20 cloudflared | grep -i registered
docker exec nginx nginx -T | grep smartergpt.dev -n
```

## Cloudflared Healthcheck Strategy (2025-09-26)

The `cloudflare/cloudflared` image is distroless: no `/bin/sh`, `curl`, `wget`,
or `grep`.
Earlier we used a process-grep style healthcheck that depended on a shell. This
was brittle and showed as `(health: starting)` longer than needed. We replaced it with:

```
healthcheck:
  test: ["CMD", "cloudflared", "--version"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s
```

Why this works:
1. Executes the binary directly (verifies container FS & executable integrity).
2. Fails fast if primary process crashed (container becomes unhealthy -> restart
 policy).
3. Zero extra tooling, preserving minimal attack surface.

If you need to assert active tunnel connections, build a tiny wrapper image (mul
ti-stage) with busybox and query the internal metrics endpoint (`http://127.0.0.1:8080/metrics`) for `cloudflared_tunnel_connections > 0`. Example future healthcheck (if busybox present):

```
test: ["CMD-SHELL", "wget -q -O - http://127.0.0.1:8080/metrics | grep -q cloudf
lared_tunnel_connections"]
```

We intentionally did not add this complexity now; the current lightweight check
is sufficient for basic liveness. Add an external synthetic (scripts/synthetic-edge.sh) to cover end-to-end availability.

## Recent Enhancements (Token Mode & Ops Tooling)

The stack now supports Cloudflare Tunnel token mode with health-gated startup an
d developer shortcuts.

Key changes:

* Cloudflared runs with `--token $TUNNEL_TOKEN` (no `credentials-file` on disk).
* Added `depends_on` with `condition: service_healthy` so tunnel only starts aft
er `nginx` passes healthcheck.
* `Makefile` introduced for quick operator workflows (`make up`, `make status`,
`make reload-nginx`).
* GitHub Actions workflow `.github/workflows/compose-preflight.yml` validates co
mpose syntax, nginx config, and health endpoint per PR.
* README updated with env var guidance.

### .env Requirements

```
TUNNEL_TOKEN=REDACTED_LONG_CLOUDFLARE_TOKEN
DOMAIN=smartergpt.dev
CLOUDFLARED_TUNNEL_ID=70e73974-c4bd-4590-95b7-d6f1d722937b
```

### Quick Start

```
make up
make status   # shows compose ps + health probe
```

### Validate Compose

```
make config
```

### Reload Nginx After Config Change

```
make reload-nginx
```

### Next Optional Enhancement

Add a development `app` service (e.g., FastAPI) behind an internal route and map
 via an additional ingress rule in a dev override file—request this if you'd like it scaffolded.
>>>>>>> a603f09 (chore: initial public commit (sanitized, no secrets))

## Validations & Drills

This repository includes lightweight validation scripts and runbook drills to exercise resilience:

- Smoke tests (idempotent, POSIX sh):
  - scripts/smoke-compose.sh — validate compose and local config guardrails
  - scripts/smoke-internal.sh — internal connectivity & TLS checks (requires stack up)
  - scripts/smoke-external.sh — edge / DNS routed checks (requires DNS/tunnel)
- Guardrails:
  - scripts/guard-validate.sh — pre-push/CI checks (compose, .env.example, .gitignore, noTLSVerify guard)
- Helpers:
  - scripts/check-no-host-ports.sh — quick fail if any running container exposes host ports

Run the RUNBOOK drills and review docs/RUNBOOK.md and docs/GUARDRAILS.md for procedures and test matrix.

Drift cleanup (Gate 8)
- Removed all references/mounts to Let's Encrypt and unrelated host artifacts from docker-compose.
- The origin certificate/key for Cloudflare Origin CA must be placed at:
  ./nginx/certs/
- Do NOT commit certs or tunnel credentials. These files are operator-managed and must remain out of VCS.

Security posture
- No host ports are published by default (dev profile only exposes ports when explicitly used).
- CI workflows validate configuration and scripts on PRs and tag pushes; they do not run containers or include secrets.

## Remediation (2025-09-26)

Recent regression fixes applied to restore end-to-end delivery for https://smartergpt.dev via Cloudflare Tunnel:

1. Nginx container failed to start due to insufficient capabilities for privilege drop (setgid). Added CAP_SETGID and CAP_SETUID and ensured service not gated behind inactive profile.
2. Duplicate/conflicting server blocks (`site.conf` with `server_name localhost` and `smartergpt.dev.conf`) caused ambiguity and prior startup errors. Neutralized `site.conf`; consolidated config into `smartergpt.dev.conf`.
3. Mounted web root (`./www -> /var/www/html`) so static index is actually served under TLS vhost.
4. Resolved origin TLS routing issues by adjusting Cloudflare Tunnel ingress rules to explicit hostnames (`smartergpt.dev` and `www.smartergpt.dev`).
5. Temporarily disabled origin TLS verification (`noTLSVerify: true`) to validate flow; site now returns 200 through Cloudflare. This MUST be reverted (or replaced with `caPool`) for production.
6. Added debug logging to cloudflared during investigation (consider downgrading to `info`).

### Outstanding Hardening Tasks
* Re-enable TLS verification: remove `noTLSVerify: true` and (optionally) supply Cloudflare Origin CA bundle via `caPool`.
* Remove deprecated `protocol: h2mux` (let it default to auto/http2).
* Consider rate limiting / additional caching headers for static assets.
* Add monitoring for 4xx/5xx spikes (metrics endpoint already present internally).
* Document operational reload procedure (`docker exec nginx nginx -s reload`).

### Quick Verification Commands
```
curl -Ik https://smartergpt.dev | grep 'HTTP/2 200'
docker compose logs --tail=20 cloudflared | grep -i registered
docker exec nginx nginx -T | grep smartergpt.dev -n
```

## Cloudflared Healthcheck Strategy (2025-09-26)

The `cloudflare/cloudflared` image is distroless: no `/bin/sh`, `curl`, `wget`, or `grep`.
Earlier we used a process-grep style healthcheck that depended on a shell. This was brittle
and showed as `(health: starting)` longer than needed. We replaced it with:

```
healthcheck:
  test: ["CMD", "cloudflared", "--version"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s
```

Why this works:
1. Executes the binary directly (verifies container FS & executable integrity).
2. Fails fast if primary process crashed (container becomes unhealthy -> restart policy).
3. Zero extra tooling, preserving minimal attack surface.

If you need to assert active tunnel connections, build a tiny wrapper image (multi-stage) with busybox
and query the internal metrics endpoint (`http://127.0.0.1:8080/metrics`) for
`cloudflared_tunnel_connections > 0`. Example future healthcheck (if busybox present):

```
test: ["CMD-SHELL", "wget -q -O - http://127.0.0.1:8080/metrics | grep -q cloudflared_tunnel_connections"]
```

We intentionally did not add this complexity now; the current lightweight check is sufficient for
basic liveness. Add an external synthetic (scripts/synthetic-edge.sh) to cover end-to-end availability.

## Recent Enhancements (Token Mode & Ops Tooling)

The stack now supports Cloudflare Tunnel token mode with health-gated startup and developer shortcuts.

Key changes:

* Cloudflared runs with `--token $TUNNEL_TOKEN` (no `credentials-file` on disk).
* Added `depends_on` with `condition: service_healthy` so tunnel only starts after `nginx` passes healthcheck.
* `Makefile` introduced for quick operator workflows (`make up`, `make status`, `make reload-nginx`).
* GitHub Actions workflow `.github/workflows/compose-preflight.yml` validates compose syntax, nginx config, and health endpoint per PR.
* README updated with env var guidance.

### .env Requirements

```
TUNNEL_TOKEN=REDACTED_LONG_CLOUDFLARE_TOKEN
DOMAIN=smartergpt.dev
CLOUDFLARED_TUNNEL_ID=70e73974-c4bd-4590-95b7-d6f1d722937b
```

### Quick Start

```
make up
make status   # shows compose ps + health probe
```

IMPORTANT: A valid Cloudflare Tunnel token must exist in your local `.env`:

```
TUNNEL_TOKEN=__REDACTED_TUNNEL_TOKEN__
```

If `TUNNEL_TOKEN` is missing, `docker compose config` (and `up`) will fail fast with a clear error.
To run only nginx locally (no tunnel):

```
docker compose up -d nginx
```


### Validate Compose

```
make config
```

### Reload Nginx After Config Change

```
make reload-nginx
```

### Next Optional Enhancement

Add a development `app` service (e.g., FastAPI) behind an internal route and map via an additional ingress rule
in a dev override file—request this if you'd like it scaffolded.
>>>>>>> a603f09 (chore: initial public commit (sanitized, no secrets))
