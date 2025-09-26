#!/bin/sh
# Refresh image digests for docker-compose.yml
# Usage: ./refresh-image-digests.sh [image1[:tag] ...]
# Defaults to nginx:1.26-alpine and cloudflare/cloudflared:2025.1.0

set -eu

FILE="docker-compose.yml"
if [ ! -f "$FILE" ]; then
  echo "ERROR: $FILE not found"
  exit 1
fi

DEFAULTS="nginx:1.26-alpine cloudflare/cloudflared:2025.1.0"
if [ "$#" -eq 0 ]; then
  IMAGES="$DEFAULTS"
else
  IMAGES="$*"
fi

cp "$FILE" "${FILE}.bak"
changed=0

for ref in $IMAGES; do
  echo "Pulling $ref ..."
  if ! docker pull "$ref"; then
    echo "WARN: docker pull failed for $ref, skipping"
    continue
  fi

  # get first RepoDigest from inspect (e.g. nginx@sha256:...)
  repo_digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$ref" 2>/dev/null || true)
  if [ -z "$repo_digest" ]; then
    echo "WARN: could not resolve digest for $ref"
    continue
  fi

  # ensure repo_digest includes @sha256:
  case "$repo_digest" in
    *@sha256:* ) ;;
    * )
      echo "WARN: digest for $ref does not contain @sha256:, skipping: $repo_digest"
      continue
      ;;
  esac

  # Replace occurrences in compose where image equals the tagged ref
  # Preserve human-readable tag as trailing comment
  # Use perl for a robust in-place replacement
  esc_ref=$ref
  new_line="${repo_digest} # ${ref}"

  perl -0777 -pe '
    my $ref = $ENV{"REF"};
    my $new = $ENV{"NEW"};
    s/^([[:space:]]*image:[[:space:]]*)\Q$ref\E([[:space:]]*(#.*)?)?$/${1} . $new/egm
  ' -- -e 0 1 REF="$esc_ref" NEW="$new_line" "$FILE" > "${FILE}.tmp" && mv "${FILE}.tmp" "$FILE"

  echo "Updated $ref -> $repo_digest"
  changed=1
done

if [ "$changed" -eq 0 ]; then
  echo "No updates applied."
else
  echo "Digest update summary (diff against ${FILE}.bak):"
  if command -v git >/dev/null 2>&1; then
    git --no-pager diff --no-index -- "${FILE}.bak" "${FILE}" || true
  else
    diff -u "${FILE}.bak" "${FILE}" || true
  fi
fi

echo "Done. Changes are not committed."
exit 0
