#!/usr/bin/env bash
# Push the locally-baked redroid image to GHCR and print the digest line
# to paste into docker/.env.
#
# Prerequisites (one-time):
#   1. PAT with `write:packages,read:packages` scopes:
#        gh auth refresh -h github.com -s write:packages,read:packages
#      or generate at https://github.com/settings/tokens (classic).
#   2. Docker login:
#        echo "$GHCR_PAT" | docker login ghcr.io -u <your-gh-user> --password-stdin
#   3. The org/user that owns the package (`genai-sir` by default) must allow
#      package publishing from the source repo.
#
# Usage:
#   sudo scripts/push-redroid-image.sh
#   sudo IMAGE_OWNER=your-user TAG=v2 scripts/push-redroid-image.sh
set -euo pipefail

LOCAL_IMAGE="${LOCAL_IMAGE:-redroid/redroid:14.0.0_64only_mindthegapps_magisk}"
IMAGE_OWNER="${IMAGE_OWNER:-genai-sir}"
IMAGE_NAME="${IMAGE_NAME:-headless-redroid}"
TAG="${TAG:-14.0.0_64only-mtg-magisk-$(date +%Y%m%d)}"
SOURCE_URL="${SOURCE_URL:-https://github.com/genai-sir/headless-testing}"

REMOTE="ghcr.io/${IMAGE_OWNER}/${IMAGE_NAME}:${TAG}"

echo "==> verify local image exists"
docker image inspect "$LOCAL_IMAGE" >/dev/null \
  || { echo "  $LOCAL_IMAGE not found locally. bake first: scripts/build-redroid-image.sh" >&2; exit 1; }

echo "==> verify docker login"
docker info 2>/dev/null | grep -q "Username:" \
  || { echo "  not logged in to docker hub or ghcr." >&2
       echo "  echo \"\$GHCR_PAT\" | docker login ghcr.io -u <user> --password-stdin" >&2
       exit 1; }

# Stamp the OCI source label so GHCR auto-links the package to this repo
# under https://github.com/orgs/<owner>/packages. One thin metadata layer, ~0 KB.
echo "==> stamping OCI labels onto $REMOTE"
docker build \
  --label "org.opencontainers.image.source=$SOURCE_URL" \
  --label "org.opencontainers.image.description=Rooted Android 14 (redroid) with Magisk Delta + MindTheGApps + LSPosed-ready" \
  --label "org.opencontainers.image.revision=$(git -C "$(dirname "$0")/.." rev-parse --short=12 HEAD 2>/dev/null || echo unknown)" \
  -t "$REMOTE" \
  - <<EOF
FROM $LOCAL_IMAGE
EOF

echo "==> pushing $REMOTE"
docker push "$REMOTE"

echo "==> resolving content digest"
DIGEST="$(docker inspect --format '{{index .RepoDigests 0}}' "$REMOTE" 2>/dev/null | sed 's/^.*@//')"
[ -n "$DIGEST" ] || { echo "  could not resolve digest after push" >&2; exit 1; }

PINNED="ghcr.io/${IMAGE_OWNER}/${IMAGE_NAME}@${DIGEST}"
echo
echo "==> pinned reference (paste into docker/.env):"
echo
echo "    REDROID_IMAGE=$PINNED"
echo
echo "tag was also pushed for human use: $REMOTE"
