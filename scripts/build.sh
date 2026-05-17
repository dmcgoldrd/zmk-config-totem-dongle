#!/usr/bin/env bash
# Build totem-dongle firmware locally via Docker.
#
# Usage:
#   ./scripts/build.sh                # build every target in build.yaml
#   ./scripts/build.sh totem_dongle   # build a single artifact-name (or shield-name)
#   ./scripts/build.sh --reset        # wipe the west cache volume and start fresh
#
# Output: firmware/<artifact>.uf2

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
IMAGE="zmkfirmware/zmk-build-arm:3.5-branch"
VOLUME="totem-dongle-west"
FIRMWARE_DIR="${REPO_ROOT}/firmware"

if [[ "${1:-}" == "--reset" ]]; then
  docker volume rm "${VOLUME}" 2>/dev/null || true
  echo "wiped west cache volume"
  shift
fi

mkdir -p "${FIRMWARE_DIR}"

# Pull image if missing
if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo ">>> pulling ${IMAGE} (~675MB, one-time)"
  docker pull "${IMAGE}"
fi

exec docker run --rm \
  -v "${VOLUME}:/west" \
  -v "${REPO_ROOT}:/zmk-config:ro" \
  -v "${FIRMWARE_DIR}:/firmware" \
  "${IMAGE}" \
  bash /zmk-config/scripts/docker-build.sh "${1:-}"
