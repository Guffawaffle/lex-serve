# RUNBOOK (outline)

Sections:
- Setup
  - High-level steps to prepare environment (placeholders)
- Bring-up
  - High-level steps to start services (placeholders)
- Verification
  - High-level checks to confirm system is healthy (placeholders)
- Troubleshooting
  - Common failure modes and where to look (placeholders)

Security notes:
- nginx/certs/ will hold origin certs/keys. Private key files MUST be mode 600 and must not be committed to git.
- cloudflared/tunnel.json is intentionally NOT created here. Place it manually under cloudflared/ when ready.

RUNBOOK — Operator Steps (Gate 3)

Operator prerequisites
- Ensure Docker and docker-compose (or Docker Compose v2) are installed.
- Prepare a `.env` at the repo root containing at least:
  - DOMAIN=your.domain.example
  - CLOUDFLARED_TUNNEL_ID=<tunnel-uuid>
  - (optional) ORIGIN_CERT_PATH, ORIGIN_KEY_PATH, LOG_LEVEL, TZ

Secrets and where to place them (do NOT commit)
- Place Cloudflare tunnel credentials (the tunnel JSON) at:
  - ./cloudflared/tunnel.json
- Place Origin CA certificate and key under:
  - ./nginx/certs/origin_cert.pem
  - ./nginx/certs/origin_key.pem
- File permissions:
  - origin_key.pem must be mode 600 (chmod 600 ./nginx/certs/origin_key.pem).
  - tunnel.json should be readable only by the operator (600).

Trusting the Cloudflare Origin CA for cloudflared
- Option A (recommended): Mount a CA bundle and reference it if supported:
  - Place Origin CA PEM in ./cloudflared/ca/origin_ca.pem and ensure cloudflared config uses caPool to point at it.
- Option B: Bake the CA into a custom cloudflared image's trust store (advanced).
- Option C: If the Origin CA is already trusted by the image base CA store, no extra step is needed.
- IMPORTANT: TLS verification remains enabled by default. Do not disable it in production.

Bring-up sequence
1. Verify `.env` is populated (DOMAIN, CLOUDFLARED_TUNNEL_ID).
2. Ensure secrets are placed (nginx certs and cloudflared/tunnel.json) and have correct modes (origin key 600).
3. Start services:
   - docker compose up -d
4. Check service health:
   - docker compose ps
   - docker compose logs -f nginx
   - docker compose logs -f cloudflared

Verification steps
- From inside the cloudflared container:
  - docker compose exec cloudflared sh
  - curl -vk --resolve ${DOMAIN}:443:nginx https://${DOMAIN}:443
    - Ensure TLS handshake succeeds and certificate presented is the Origin CA cert.
- Cloudflare dashboard:
  - Confirm the tunnel is active and that a route exists for ${DOMAIN}.
- External check:
  - curl -I https://${DOMAIN}
    - Expect HTTP 200 and Cloudflare response headers when proxied.
- Quick healthcheck queries:
  - docker compose exec nginx curl -fsS http://localhost/healthz

Troubleshooting
- SNI mismatch: ensure originServerName in cloudflared/config.yml equals the certificate CN/SAN.
- Cert trust failures: ensure cloudflared trusts the Origin CA (see CA options above).
- Missing tunnel.json: cloudflared will fail to start — ensure you mounted the credentials file.
- Permission errors: ensure origin key is 600 and owned by operator where appropriate.

{
## Initial Bring-up (Gate 4)

1) Preflight
- Complete docs/PREFLIGHT.md checklist and ensure .env and secrets are in place.

2) Start the stack
```sh
# from repo root
docker compose up -d
```

3) Monitor health & logs
```sh
docker compose ps
docker compose logs -f nginx --tail 200
docker compose logs -f cloudflared --tail 200
```

4) Cloudflare Dashboard
- Confirm the tunnel shows as "Active" and the DNS/ingress route for `${DOMAIN}` is present.

## Verification commands (copy-pasteable)

A) Internal TLS & SNI (from within cloudflared container)
```sh
# Exec into cloudflared and run openssl to test SNI and certificate chain
docker compose exec cloudflared sh -c 'apk add --no-cache openssl >/dev/null 2>&1 || true; \
  openssl s_client -connect nginx:443 -servername ${DOMAIN} -showcerts'
# If you mounted a CA bundle:
docker compose exec cloudflared sh -c 'openssl s_client -connect nginx:443 -servername ${DOMAIN} -CAfile /etc/cloudflared/ca/origin_ca.pem'
```

B) Check cloudflared logs for origin TLS verification issues
```sh
docker compose logs cloudflared | tail -n 200
# Look for "certificate verify failed" or "x509" errors → CA trust/SNI problem.
```

C) External check (public)
```sh
# From your workstation (public internet)
curl -I https://${DOMAIN}
# Expect HTTP/2 or HTTP/1.1 200 OK and Cloudflare headers (e.g., server: cloudflare, cf-ray)
```

D) Quick health endpoint
```sh
docker compose exec nginx curl -fsS http://localhost/healthz || echo "nginx healthcheck failed"
```

## Troubleshooting signals & likely fixes

- "certificate verify failed" or "x509: certificate signed by unknown authority"
  - Cause: cloudflared cannot trust the Origin CA.
  - Fix: mount ./cloudflared/ca/origin_ca.pem and enable caPool (Option A), or install CA in image trust store (Option B). Re-run PREFLIGHT checks.

- "SNI mismatch" (server returned certificate for different name)
  - Cause: originServerName != certificate SAN/CN
  - Fix: ensure ${DOMAIN} matches the Origin CA certificate SANs and originRequest.originServerName is set to ${DOMAIN}.

- "host not found: nginx" or DNS resolution errors
  - Cause: service not on same Docker network
  - Fix: ensure both services are attached to `nginx-tunnel-net` in docker-compose.yml and containers restarted.

- "tunnel not found" or cloudflared failing to start
  - Cause: missing/invalid ./cloudflared/tunnel.json or wrong CLOUDFLARED_TUNNEL_ID
  - Fix: verify the credentials file path and permissions, validate CLOUDFLARED_TUNNEL_ID in .env.

## Migration Test (Gate 5)

This section describes a repeatable migration test for moving the nginx + cloudflared stack to a new host using the portable bundle.

### Source host (create the portable bundle)
1. Ensure your local repo has no secrets committed (no tunnel.json, no certs in repo).
2. Run the packager:
   - ./scripts/package-portable.sh
3. Confirm created tarball under ./dist. Verify contents:
   - Should include: docker-compose.yml, cloudflared/config.yml, nginx/conf.d, docs/, .env.example, cloudflared/Dockerfile (if present)
   - Should NOT include: nginx/certs/*, cloudflared/tunnel.json, .env, cloudflared/ca/*
4. Transfer the tarball securely to the target host (scp, rsync, etc).

### Target host (unpack and bring up)
Prereqs:
- Docker Engine and Docker Compose v2+ installed.
- Operator will provide Cloudflare tunnel credentials (tunnel.json), and TLS origin cert/key as required.
- Ensure user on target has permissions to run docker compose.

Steps:
1. Create target dir and unpack:
   - mkdir -p /home/<user>/nginx-docker && tar xzf nginx-cloudflared-PORTABLE-*.tar.gz -C /home/<user>/nginx-docker
2. Place secrets (operator-only):
   - Copy tunnel.json -> /home/<user>/nginx-docker/cloudflared/tunnel.json
   - Place origin cert/key if used -> /home/<user>/nginx-docker/nginx/certs/ (or follow PREFLIGHT)
   - Create a .env file from .env.example with DOMAIN and CLOUDFLARED_TUNNEL_ID set.
3. Run preflight checks (PREFLIGHT):
   - Verify file ownerships and readability for docker (config and credential files accessible by container user).
   - If using cloudflared-trusted image with a CA built-in, ensure that was built on the target (see notes below).
4. Start the stack:
   - docker compose up -d
   - If using the trusted CA build, use: docker compose --profile trusted-ca --profile default up -d --build cloudflared-trusted
5. Verify:
   - docker compose ps -> services are healthy
   - docker compose logs cloudflared (or cloudflared-trusted) to ensure tunnel connects
   - Query cloudflared internal metrics:
     - docker exec -it cloudflared sh -c "curl -sS http://127.0.0.1:8080/metrics | head -n 20"
   - Verify Nginx health endpoint:
     - docker exec -it nginx sh -c "curl -fsS http://localhost/healthz || exit 1"

### Success Criteria
- cloudflared service shows "Active" in the Cloudflare dashboard for the tunnel ID.
- Internal TLS handshake validates with SNI = ${DOMAIN} (use internal debugging tools or curl with --resolve if needed).
- External check: curl -I -sS "https://${DOMAIN}" returns HTTP 200 and Cloudflare response headers (CF-Cache-Status, server details).

### Rollback (target host)
- docker compose down
- Securely delete the unpacked directory and any secrets placed for the migration:
  - shred -u /path/to/secret (or follow your secure deletion policies)
- If abandoning migration, remove any built images (docker image rm ...) and container artifacts.

Notes:
- The portable bundle does NOT contain secrets. Operator must inject credentials on the target host.
- When using the cloudflared trusted build: do not bake secrets into the image. Use build-time ARG only when operator provides the origin CA locally (and ensure build context contains it on the operator host).

## Rollback & Safety

- Quick stop:
```sh
docker compose down
```
- Revert last repo config change:
```sh
# if using git and last commit introduced a bad change:
git revert HEAD
# or reset to previous known-good commit (use with care):
git reset --hard <commit>
```
- Safety reminders:
  - Do NOT publish nginx host ports in production. If you temporarily enabled ports for debugging, remove them before returning to production.
  - Keep origin_key.pem and tunnel.json out of git and verify permissions (600).

}
