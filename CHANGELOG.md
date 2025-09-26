# 2025-09-26
## Fixed
- Corrected nginx healthcheck syntax (previously used invalid single-string with `CMD-SHELL` literal causing exit 127 and unhealthy container).
## Added
- Enforced mandatory `TUNNEL_TOKEN` via parameter expansion in `docker-compose.yml` (fail-fast if unset).
## Notes
- If you intentionally want to run stack without cloudflared, start only nginx: `docker compose up -d nginx`.
- Provide a valid token in `.env` to run full stack.

# Changelog
All notable changes to this project will be documented in this file.

## [Unreleased]
- TBD: hardening and docs improvements.

## [1.0.0] — Initial production-ready stack
- Gate 2–3: Scaffold + functional configs (nginx + cloudflared via HTTPS with Origin CA).
- Gate 4: Secrets placement guidance, CA trust wiring, first bring-up steps.
- Gate 5: Hardening, portable bundle, migration plan.
- Gate 6: Smoke tests, guardrails, resilience drills.
- Gate 7: Edge posture docs, Nginx policy headers, synthetics.
- Gate 8: Drift cleanup; CI validate/package; PR hygiene.
- Gate 9: Image pinning by digest; security scans + SBOM; digest refresher.
- Gate 10: Observability, SLOs, alerts, incident workflow.

[Unreleased]: (add compare link)
[1.0.0]: (add tag link)
