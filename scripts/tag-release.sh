#!/bin/sh
# Create an annotated release tag after a successful dry-run.
# Usage: TAG=v1.0.0 ./scripts/tag-release.sh
set -eu

TAG="${TAG:-}"
[ -n "$TAG" ] || { echo "ERROR: TAG env var required, e.g. TAG=v1.0.0"; exit 2; }

# ensure clean tree
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: working tree not clean. Commit or stash changes before tagging."
  exit 2
fi

# best-effort dry-run freshness check (optional warn)
DRY_RUN_MARKER=".git/.last-release-dry-run"
MAX_AGE_MIN="${DRY_RUN_MAX_AGE_MIN:-60}" # minutes
if [ -f "$DRY_RUN_MARKER" ]; then
  now=$(date +%s)
  then=$(date -u -d "$(cat "$DRY_RUN_MARKER")" +%s 2>/dev/null || echo 0)
  age_min=$(( (now - then) / 60 ))
  if [ "$age_min" -gt "$MAX_AGE_MIN" ]; then
    echo "WARNING: last dry-run timestamp is ${age_min} minutes old (max ${MAX_AGE_MIN})."
    echo "  Consider re-running: DOMAIN=\$DOMAIN N=3 ./scripts/release-dry-run.sh"
  fi
else
  echo "WARNING: no dry-run timestamp found. Consider running:"
  echo "  DOMAIN=\$DOMAIN N=3 ./scripts/release-dry-run.sh"
fi

# create annotated tag (local only)
git tag -a "$TAG" -m "Release $TAG"
echo "Tag created locally: $TAG"
echo "Push with:"
echo "  git push origin $TAG"
echo ""
echo "Note: pushing the tag will trigger packaging CI (package.yml)."
