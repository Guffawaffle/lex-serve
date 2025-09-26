# Release Checklist — E2E Dry-Run & Tag (Gate 11)

## Preconditions
- Stack is up and healthy (`docker compose ps` shows healthy).
- Cloudflare DNS/route points the hostname to the tunnel.
- `.env` includes DOMAIN and CLOUDFLARED_TUNNEL_ID; secrets present (not in git).

## One-command dry-run (guards + smoke + synthetics)
```bash
DOMAIN=$DOMAIN N=3 ./scripts/release-dry-run.sh
```

Expect: **DRY-RUN PASS**.

Manual spot-checks (5–10 min):

* Edge headers: `curl -I https://$DOMAIN | egrep 'CF-(Cache-Status|RAY)|Server: cloudflare'`
* Cloudflare Analytics: Traffic + WAF + Rate Limiting show sane baselines.
* Nginx logs: no rising 5xx; rate-limit 429 stable/low.

## Tag & package

```bash
TAG=v1.0.0
TAG=$TAG ./scripts/tag-release.sh
# If satisfied:
git push origin $TAG
```

Artifacts: **Actions → “Package on tag”** run and Security scans on main/PR.

## Announce

* Share tag, Actions artifact link, and CHANGELOG highlights.

## Rollback (if needed)

* Unpublish tag:

  ```bash
  git tag -d $TAG
  git push origin :refs/tags/$TAG
  ```
* Revert latest changes (if release had repo edits):

  ```bash
  git revert <commit_sha>   # or restore previous bundle
  ```
* Confirm Cloudflare route & stack are healthy; rerun dry-run.
