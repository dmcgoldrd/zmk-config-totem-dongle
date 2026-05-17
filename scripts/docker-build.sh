#!/usr/bin/env bash
# Runs INSIDE the zmkfirmware/zmk-build-arm container.
# Driven by scripts/build.sh on the host.

set -euo pipefail

if [ ! -f /.dockerenv ]; then
  echo "This script runs inside the docker container only." >&2
  echo "Use ./scripts/build.sh from the host." >&2
  exit 1
fi

REPO=/zmk-config
WEST_DIR=/west
CONFIG_DIR="${WEST_DIR}/config"
OUT=/firmware
ONLY="${1:-}"

# Copy a writable mirror of config/ into the west workspace (host mount is :ro).
rm -rf "${CONFIG_DIR}"
mkdir -p "${CONFIG_DIR}"
cp -R "${REPO}/config/." "${CONFIG_DIR}/"

# One-time west init/update; subsequent runs reuse the named volume.
if [ ! -f "${WEST_DIR}/.initialized" ]; then
  cd "${WEST_DIR}"
  west init -l "${CONFIG_DIR}"
  west update --fetch-opt=--filter=tree:0
  west zephyr-export
  touch "${WEST_DIR}/.initialized"
else
  cd "${WEST_DIR}"
  # Refresh the zephyr-export each run (cmake user registry is per-container, not persisted)
  west zephyr-export
fi

REPO="${REPO}" CONFIG_DIR="${CONFIG_DIR}" OUT="${OUT}" ONLY="${ONLY}" python3 - <<'PYEOF'
import os, sys, shutil, subprocess, yaml

repo, config_dir, out_dir, only = (os.environ[k] for k in ("REPO","CONFIG_DIR","OUT","ONLY"))

with open(os.path.join(repo, "build.yaml")) as f:
    data = yaml.safe_load(f)

failed, built, skipped = [], [], []
for entry in data.get("include", []):
    board = entry["board"]
    shield = entry.get("shield", "")
    snippet = entry.get("snippet", "")
    cmake_args = entry.get("cmake-args", "")
    artifact = entry.get("artifact-name") or (shield.replace(" ", "_") if shield else board)

    if only and artifact != only and shield != only:
        skipped.append(artifact)
        continue

    build_dir = f"/tmp/zmk-build/{artifact}"
    cmd = [
        "west", "build",
        "-s", "/west/zmk/app",
        "-b", board,
        "-d", build_dir,
        "--",
        f"-DZMK_CONFIG={config_dir}",
        f"-DBOARD_ROOT={repo}",
    ]
    if shield:
        cmd.append(f"-DSHIELD={shield}")
    if snippet:
        cmd.append(f"-DSNIPPET={snippet}")
    if cmake_args:
        cmd.extend(cmake_args.split())

    print(f">>> building {artifact}  (board={board} shield={shield})", flush=True)
    r = subprocess.run(cmd, cwd="/west")
    if r.returncode != 0:
        failed.append(artifact)
        continue

    uf2 = f"{build_dir}/zephyr/zmk.uf2"
    if os.path.exists(uf2):
        dest = f"{out_dir}/{artifact}.uf2"
        shutil.copy2(uf2, dest)
        built.append(artifact)
        print(f"    -> firmware/{artifact}.uf2", flush=True)
    else:
        failed.append(f"{artifact} (no .uf2 produced)")

print("")
print(f"built:   {built}")
if skipped:
    print(f"skipped: {skipped}")
if failed:
    print(f"failed:  {failed}", file=sys.stderr)
    sys.exit(1)
PYEOF
