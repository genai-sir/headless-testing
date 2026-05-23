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

REMOTE="ghcr.io/${IMAGE_OWNER}/${IMAGE_NAME}:${TAG}"

echo "==> verify local image exists"
docker image inspect "$LOCAL_IMAGE" >/dev/null \
  || { echo "  $LOCAL_IMAGE not found locally. bake first: scripts/build-redroid-image.sh" >&2; exit 1; }

echo "==> verify docker login"
docker info 2>/dev/null | grep -q "Username:" \
  || { echo "  not logged in to docker hub or ghcr." >&2
       echo "  echo \"\$GHCR_PAT\" | docker login ghcr.io -u <user> --password-stdin" >&2
       exit 1; }

echo "==> tagging $LOCAL_IMAGE -> $REMOTE"
docker tag "$LOCAL_IMAGE" "$REMOTE"

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
