#!/usr/bin/env bash
# Render totem keymap SVG locally via keymap-drawer.
#
# Two-step pipeline:
#   1. parse config/totem.keymap → totem_keymap.yaml
#   2. draw totem_keymap.yaml     → totem.ortho.svg
#
# Re-renders both files. Diff against committed versions for regression check.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

# Ensure deps are installed in the project's uv-managed .venv
uv sync >/dev/null

CONFIG=drawer_config.yaml
KEYMAP_SRC=config/totem.keymap
YAML_OUT=totem_keymap.yaml
SVG_OUT=totem.ortho.svg

echo ">>> parsing ${KEYMAP_SRC}"
uv run keymap -c "${CONFIG}" parse -z "${KEYMAP_SRC}" > "${YAML_OUT}"

echo ">>> drawing ${YAML_OUT}"
uv run keymap -c "${CONFIG}" draw "${YAML_OUT}" > "${SVG_OUT}"

echo ""
echo "rendered:"
echo "  ${YAML_OUT}  ($(wc -c < ${YAML_OUT}) bytes)"
echo "  ${SVG_OUT}   ($(wc -c < ${SVG_OUT}) bytes)"
