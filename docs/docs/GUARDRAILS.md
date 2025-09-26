# Guardrails & Pre-flight Checks

This document explains the lightweight guard scripts in scripts/ intended to be run before commits, during CI, and before production promotion.

- scripts/guard-validate.sh
  - Runs docker compose config (syntax/structure).
  - Ensures variables interpolated in docker-compose.yml are documented in .env.example.
  - Ensures .gitignore contains common secret patterns.
  - Fails if cloudflared/config.yml contains an active `noTLSVerify:` entry.

- scripts/smoke-compose.sh
  - Quick local smoke test of compose validity and presence of required non-secret config files.
  - Ensures services that publish host ports are gated under `profiles: - dev` (so production does not publish host ports).

- scripts/smoke-internal.sh and scripts/smoke-external.sh
  - More invasive tests that expect the stack to be up.
  - Use these in staging to validate internal TLS chains and external edge routing.

When to run
- Locally: run guard-validate.sh and smoke-compose.sh before committing major infra changes.
- CI: include guard-validate.sh as a blocking check for pushes to protected branches.
- Staging/Pre-prod: run smoke-internal.sh and smoke-external.sh after deployment to verify behavior.

Notes
- These scripts intentionally avoid creating or committing secrets.
- They do not publish any host ports by default.
- The noTLSVerify setting is only allowed commented for debugging and will make guard-validate fail if active.
