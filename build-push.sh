#!/usr/bin/env bash
# build-push.sh — Build and push DeerFlow Docker images to a container registry
#
# Usage:
#   ./build-push.sh                          # build + push both images with defaults
#   ./build-push.sh --registry ghcr.io/myorg --tag sha-abc1234
#   REGISTRY=ghcr.io/myorg TAG=v1.2.3 ./build-push.sh
#
# Environment variables (can also be passed as flags):
#   REGISTRY   — image registry prefix  (default: ghcr.io/trustsoftvn)
#   TAG        — image tag              (default: latest)
#   PLATFORM   — docker buildx platform (default: linux/amd64)
#   PUSH       — set to "false" to build only, skip push (default: true)

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
REGISTRY="${REGISTRY:-ghcr.io/trustsoftvn}"
TAG="${TAG:-latest}"
PLATFORM="${PLATFORM:-linux/amd64}"
PUSH="${PUSH:-true}"

# ── Parse flags ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --tag)      TAG="$2";      shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --no-push)  PUSH="false";  shift   ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

BACKEND_IMAGE="${REGISTRY}/deer-flow-backend:${TAG}"
FRONTEND_IMAGE="${REGISTRY}/deer-flow-frontend:${TAG}"

# Repo root is the directory containing this script
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== DeerFlow Image Build ==="
echo "  Registry : ${REGISTRY}"
echo "  Tag      : ${TAG}"
echo "  Platform : ${PLATFORM}"
echo "  Push     : ${PUSH}"
echo "  Backend  : ${BACKEND_IMAGE}"
echo "  Frontend : ${FRONTEND_IMAGE}"
echo ""

# ── Ensure buildx builder ─────────────────────────────────────────────────────
if ! docker buildx inspect deer-flow-builder &>/dev/null; then
  echo ">> Creating buildx builder 'deer-flow-builder'..."
  docker buildx create --name deer-flow-builder --use
else
  docker buildx use deer-flow-builder
fi

PUSH_FLAG=""
[[ "$PUSH" == "true" ]] && PUSH_FLAG="--push"

# ── Build backend image ───────────────────────────────────────────────────────
echo ""
echo ">> Building backend image: ${BACKEND_IMAGE}"
docker buildx build \
  --platform "${PLATFORM}" \
  --file "${REPO_ROOT}/backend/Dockerfile" \
  --tag "${BACKEND_IMAGE}" \
  --label "org.opencontainers.image.source=https://github.com/bytedance/deer-flow" \
  --label "org.opencontainers.image.revision=$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)" \
  --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --cache-from "type=registry,ref=${REGISTRY}/deer-flow-backend:cache" \
  --cache-to   "type=registry,ref=${REGISTRY}/deer-flow-backend:cache,mode=max" \
  ${PUSH_FLAG} \
  "${REPO_ROOT}"

# ── Build frontend image ──────────────────────────────────────────────────────
echo ""
echo ">> Building frontend image (prod target): ${FRONTEND_IMAGE}"
docker buildx build \
  --platform "${PLATFORM}" \
  --file "${REPO_ROOT}/frontend/Dockerfile" \
  --target prod \
  --tag "${FRONTEND_IMAGE}" \
  --label "org.opencontainers.image.source=https://github.com/bytedance/deer-flow" \
  --label "org.opencontainers.image.revision=$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)" \
  --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --cache-from "type=registry,ref=${REGISTRY}/deer-flow-frontend:cache" \
  --cache-to   "type=registry,ref=${REGISTRY}/deer-flow-frontend:cache,mode=max" \
  ${PUSH_FLAG} \
  "${REPO_ROOT}"

echo ""
echo "=== Done ==="
echo "  Backend  : ${BACKEND_IMAGE}"
echo "  Frontend : ${FRONTEND_IMAGE}"
[[ "$PUSH" == "true" ]] && echo "  Images pushed to registry."
