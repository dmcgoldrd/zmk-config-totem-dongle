#!/usr/bin/env bash
# Run ZMK snapshot tests for totem behaviors.
#
# Usage:
#   ./scripts/test.sh                       # run every test under tests/
#   ./scripts/test.sh hrm-tap-only          # one test by directory name
#   ./scripts/test.sh --accept              # regenerate snapshots from current behavior
#   ./scripts/test.sh --accept hrm-tap-only # regenerate one snapshot
#
# Snapshots live in tests/<name>/keycode_events.snapshot — diff them after
# changes to confirm the keymap behaves the same way.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
IMAGE="zmkfirmware/zmk-build-arm:3.5-branch"
VOLUME="totem-dongle-west"
TESTS_DIR="${REPO_ROOT}/tests"

ACCEPT_ENV=""
if [[ "${1:-}" == "--accept" ]]; then
  ACCEPT_ENV="ZMK_TESTS_AUTO_ACCEPT=1"
  shift
fi

if [[ -n "${1:-}" ]]; then
  TARGET="tests/totem/${1}"
else
  TARGET="tests/totem"
fi

# West cache from build.sh holds the populated /west tree. We bind-mount the
# host tests/ over /west/zmk/app/tests/totem so snapshot updates (--accept)
# write back into the host repo.
exec docker run --rm \
  -v "${VOLUME}:/west" \
  -v "${TESTS_DIR}:/west/zmk/app/tests/totem" \
  -e ZMK_TESTS_VERBOSE=1 \
  "${IMAGE}" \
  bash -c "
    set -euo pipefail
    if [ ! -f /west/.initialized ]; then
      echo 'west workspace not initialized — run ./scripts/build.sh first' >&2
      exit 1
    fi
    cd /west
    west zephyr-export
    cd /west/zmk/app
    ${ACCEPT_ENV} ./run-test.sh ${TARGET}
  "
