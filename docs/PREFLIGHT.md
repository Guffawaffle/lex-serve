# PREFLIGHT — Pre-flight checklist (Gate 4)

Copy-paste checklist

1) Verify .env contains required keys
```sh
# from repo root
grep -E '^(DOMAIN|CLOUDFLARED_TUNNEL_ID|ORIGIN_CERT_PATH|ORIGIN_KEY_PATH|LOG_LEVEL|TZ)=' .env || echo ".env missing required keys"
```

2) Verify required secret files (must NOT be committed)
```sh
# expected locations (operator-populated)
test -f ./nginx/certs/origin_cert.pem || echo "MISSING: ./nginx/certs/origin_cert.pem"
test -f ./nginx/certs/origin_key.pem  || echo "MISSING: ./nginx/certs/origin_key.pem"
test -f ./cloudflared/tunnel.json      || echo "MISSING: ./cloudflared/tunnel.json"
```

3) Set and verify file modes (recommended)
```sh
# ensure origin key is owner-readable only
chmod 600 ./nginx/certs/origin_key.pem
ls -l ./nginx/certs/origin_cert.pem ./nginx/certs/origin_key.pem ./cloudflared/tunnel.json
# expected mode for origin_key.pem: -rw-------
```

4) Repo hygiene: ensure sensitive files are ignored
```sh
# quick grep for common patterns in .gitignore
grep -E 'cloudflared/tunnel.json|nginx/certs/origin_key.pem|ssl/cloudflare-origin|^\.env$' .gitignore || echo "Consider adding secrets to .gitignore"
```

Trust the Origin CA — Options (do NOT disable TLS verification in production)

Option A — Preferred (mount a CA bundle)
- Place your Cloudflare Origin CA PEM at:
  - ./cloudflared/ca/origin_ca.pem
- If your cloudflared supports it, add a reference in cloudflared/config.yml (example):
  - originRequest:
      caPool: /etc/cloudflared/ca/origin_ca.pem
- Version check (one-liner):
```sh
# locally (host): check image version
docker run --rm --entrypoint "" cloudflare/cloudflared:2025.1.0 sh -c 'cloudflared --version || true'
# in-container (after up): docker compose exec cloudflared cloudflared --version
```
- How to confirm: start cloudflared and inspect logs for successful TLS handshakes to origin and no CA verification errors:
```sh
docker compose logs -f cloudflared | sed -n '1,200p'
# look for messages indicating connection/handshake success or CA verification errors
```

Option B — Advanced (image trust store)
- Build/use a cloudflared image that has the Origin CA in the system trust store (Debian/Alpine update-ca-certificates).
- Deferred to Gate 5 hardening; recommended only for managed build pipelines.

Temporary debug toggle (ONLY for short-lived debugging)
- To bypass verification temporarily (NOT recommended), you may set:
  - originRequest:
      noTLSVerify: true
- DO NOT leave this enabled. Revert immediately after debugging.

End of PREFLIGHT
