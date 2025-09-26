# Cloudflare Origin Certificate Setup for smartergpt.dev

This repository is prepared to let you switch from a local Let's Encrypt cert to a Cloudflare Origin Certificate for the private (cloudflared -> Nginx) leg. Public users still see Cloudflare's edge cert; the origin cert only needs to be trusted by Cloudflare.

## 1. Generate / Download Cloudflare Origin Certificate

From the Cloudflare Dashboard:
1. Select your zone: `smartergpt.dev`.
2. SSL/TLS -> Origin Server -> Create Certificate.
3. Key type: ECDSA preferred (or RSA if you need legacy). Leave default hostnames (`smartergpt.dev` + `*.smartergpt.dev`).
4. Cloudflare will present two PEM blocks:
   - Certificate (PEM)  (may include intermediate)  -> save as `origin.crt`
   - Private key (PEM) -> save as `origin.key`
5. Place both files into: `ssl/cloudflare-origin/`

Resulting paths (host):
```
nginx-docker/ssl/cloudflare-origin/origin.crt
nginx-docker/ssl/cloudflare-origin/origin.key
```
They will be mounted into the container at:
```
/etc/ssl/cloudflare-origin/origin.crt
/etc/ssl/cloudflare-origin/origin.key
```

## 2. (Optional) Remove or Archive Existing Let's Encrypt Certs
You can keep `/etc/letsencrypt` mounted; Nginx just won't reference those files in origin mode. To fully retire LE renewal, disable the cron/systemd timers you previously used.

## 3. Deploy the Origin Certificate Config

Run the helper script (includes validation & backup):
```bash
chmod +x scripts/switch_to_origin_cert.sh
./scripts/switch_to_origin_cert.sh
```
This will:
- Verify the `origin.crt` and `origin.key` look valid.
- Backup the current `nginx/conf.d/smartergpt.dev.conf`.
- Copy the template `smartergpt.dev.origin.conf.template` to `smartergpt.dev.conf`.
- Recreate the `nginx` container.
- Perform a simple HTTPS origin check on `https://localhost:8443/`.

## 4. Update cloudflared Configuration

Edit `/etc/cloudflared/config.yml` (or replace with provided example `cloudflared-config-origin.yml.example`):

```yaml
tunnel: 70e73974-c4bd-4590-95b7-d6f1d722937b
credentials-file: /etc/cloudflared/70e73974-c4bd-4590-95b7-d6f1d722937b.json
originRequest:
  connectTimeout: 10s
  tcpKeepAlive: 2m
  noTLSVerify: false
  httpHostHeader: smartergpt.dev
ingress:
  - hostname: smartergpt.dev
    service: https://localhost:8443
  - hostname: www.smartergpt.dev
    service: https://localhost:8443
  - service: http_status:404
```
Validate & restart:
```bash
sudo cloudflared tunnel ingress validate
sudo systemctl restart cloudflared
journalctl -u cloudflared -f
```

## 5. Validation Checklist

| Step | Command | Expectation |
|------|---------|-------------|
| DNS | `dig +noall +answer smartergpt.dev @1.1.1.1` | CNAME (flattened) to tunnel domain |
| Tunnel | `cloudflared tunnel list | grep 70e7` | Status HEALTHY |
| Origin TLS cert | `openssl s_client -connect localhost:8443 -servername smartergpt.dev </dev/null | openssl x509 -noout -subject -issuer` | Subject CN=*.smartergpt.dev or smartergpt.dev, Issuer=Cloudflare Inc ECC CA-* |
| Public curl | `curl -I https://smartergpt.dev/` | 200 or 301->200, headers include `cf-ray` |
| Health endpoint | `curl -I https://smartergpt.dev/healthz` | 200 |

## 6. Rollback
If anything breaks:
1. Restore previous config: `cp nginx/conf.d/smartergpt.dev.conf.bak.<timestamp> nginx/conf.d/smartergpt.dev.conf`
2. Recreate container: `docker compose up -d --force-recreate nginx`
3. Point cloudflared back to `http://localhost:8080` if needed.

## 7. Security Notes
- The Origin Certificate is only trusted by Cloudflare; it’s fine that browsers would not trust it directly if accessed bypassing Cloudflare (which they can't if you keep ports private / only tunnel exposed).
- Keep `ssl/cloudflare-origin/` permissions restrictive (`chmod 600 origin.key`). If running git, add entries to `.gitignore` (already recommended below).

Add to `.gitignore` (if not present):
```
ssl/cloudflare-origin/origin.crt
ssl/cloudflare-origin/origin.key
```

## 8. Optional Hardening
- Enable HSTS preload ONLY after confirming consistent HTTPS via Cloudflare for several weeks.
- Add rate limiting / WAF rules in Cloudflare.
- Consider turning on `brotli` compression at Cloudflare edge to reduce origin CPU usage.

## 9. Troubleshooting Quick Map
| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| 502 from Cloudflare | Origin unreachable / wrong port | Check `journalctl -u cloudflared -f`, curl localhost:8443 |
| TLS mismatch error | Old cert served | Confirm `openssl s_client` output, ensure script replaced config |
| Health failing | Permissions / wrong path to cert/key | Check container logs `docker logs smartergpt-nginx` |

---
You are now ready to use a Cloudflare Origin Certificate end-to-end.
