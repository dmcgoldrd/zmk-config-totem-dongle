# Project context for AI agents

> Read this first. It compresses everything a fresh session needs about this repo into one file.

## What this is

A personal **ZMK firmware config for a Totem keyboard with a dongle**. Three-piece split: left half, right half, and a dongle that bridges USB ↔ BLE. Boards are `seeeduino_xiao_ble` (nRF52840). Built locally via Docker — no GitHub Actions dependency in the day-to-day workflow.

ZMK and `urob/zmk-helpers` are pinned to **`v0.3`** in `config/west.yml`. v0.3 is the last stable tag on the Zephyr 3.5 line. ZMK's `main` branch moved to Zephyr 4.1 + Hardware Model V2 on Dec 9 2025; we deferred that migration until ZMK ships v0.4 with stable HWMv2 board names (probably Q2/Q3 2026). Don't unpin `west.yml` without doing the HWMv2 work explicitly.

## Day-to-day commands

Run from the repo root.

```bash
./scripts/build.sh                  # build all 4 firmware targets via Docker → firmware/*.uf2
./scripts/build.sh totem_dongle     # build one target
./scripts/build.sh --reset          # wipe the named-volume west cache (rare)

./scripts/draw.sh                   # parse config/totem.keymap → totem_keymap.yaml → totem.ortho.svg
./scripts/test.sh                   # run all snapshot tests (~17s warm cache)
./scripts/test.sh hrm-tap-only      # run one test
./scripts/test.sh --accept          # regenerate snapshots after intentional behavior change
```

First build is ~2 min (downloads zmkfirmware/zmk-build-arm:3.5-branch and runs west update). Subsequent builds reuse the `totem-dongle-west` Docker named volume — about 17 seconds for all four targets.

## Build targets (from `build.yaml`)

| Artifact | What it is |
|----------|------------|
| `totem_left.uf2` | Left half — peripheral, BLE-connects to dongle |
| `totem_right.uf2` | Right half — peripheral, BLE-connects to dongle |
| `totem_dongle.uf2` | Dongle — central, USB to host, BLE to halves. ZMK Studio enabled (`CONFIG_ZMK_STUDIO=y`), USB logging snippet attached |
| `settings_reset.uf2` | Clears BLE pairing state. Flash before re-pairing halves or after big firmware changes |

## Flash topology — important

**The keymap lives only on the dongle (the central).** Halves are dumb peripherals that report position events over BLE.

- **Pure keymap edits** → flash dongle only
- **west.yml / shield / Kconfig changes** → flash all three (dongle + both halves) to keep firmware in sync
- **If BLE pairing acts up** → flash `settings_reset.uf2` to all three, then re-flash and let them re-pair (5–10s on first power-on)

## Layer system (six layers)

Defined in `config/totem.keymap` lines 12-17.

| # | Name | Role | Activation |
|---|------|------|------------|
| 0 | BASE | QWERTY alphas with homerow mods | default |
| 1 | GAME | Same QWERTY, **HRMs disabled on left hand A-F** | combo TAB+A (`gaming_toggle_combo`) toggles in/out |
| 2 | NAV | Arrow cluster + browser back/forward (`Gui+[`, `Gui+]`) | hold-tap on left thumb SPACE |
| 3 | NUM | Numpad + symbols | hold-tap on right thumb BSPC |
| 4 | FUN | F1-F12 | hold-tap on right thumb DEL |
| 5 | UTIL | Bluetooth profile + volume + media | hold-tap on left thumb ESC |

## Homerow mods (HRMs)

Macro definition at `config/totem.keymap:63-72`:

```c
#define MAKE_HRM(NAME, HOLD, TAP, TRIGGER_POS) \
    ZMK_BEHAVIOR(NAME, hold_tap, \
        flavor = "balanced"; \
        tapping-term-ms = <280>; \
        quick-tap-ms = <175>; \
        require-prior-idle-ms = <150>; \
        bindings = <HOLD>, <TAP>; \
        hold-trigger-key-positions = <TRIGGER_POS>; \
        hold-trigger-on-release; \
    )
```

Instances:
- `hml` — left HRMs, only trigger on right-hand keys + thumbs (opposite-hand chord)
- `hmr` — right HRMs, only trigger on left-hand keys + thumbs
- `hmr_meh` — special right-side HRM where the tap binding is `&comma_morph` instead of `&kp` (used at the right-side comma position to chain the mod-morph through the HRM)

**Do not retune timing constants casually.** Changes to `tapping-term-ms`, `quick-tap-ms`, or `require-prior-idle-ms` will flag through the snapshot tests; the values above are tested baselines.

## Mod-morphs

Defined `config/totem.keymap:83-98`. Three of them, all triggered by `MOD_LSFT|MOD_RSFT`:

| Behavior | Tap | Shift+tap |
|----------|-----|-----------|
| `qexcl` | `?` | `!` |
| `comma_morph` | `,` | `;` |
| `dot_morph` | `.` | `:` |

## Combos

In `config/combos.dtsi`. Tuning:
- `COMBO_TERM_FAST = 18ms` for tight finger pairs
- `COMBO_TERM_SLOW = 30ms` for looser combos
- `require-prior-idle-ms = 150` to prevent misfires during fast typing

Currently 30 combos across vertical pairs, horizontal pairs, and a few editing macros. The standout one:

```c
ZMK_COMBO(gaming_toggle_combo, &tog GAME, LT4 LM4, BASE GAME NAV NUM FUN UTIL, COMBO_TERM_FAST)
```

Left-TAB + left-A → toggle GAME layer, active on every layer (so you can always escape).

## Repo layout

```
config/
  totem.keymap                    main keymap (all six layers)
  combos.dtsi                     all 30 combos
  totem.conf                      BLE config — central battery proxy, experimental conn
  zmk-helpers-repo/               git submodule → urob/zmk-helpers v2 branch
  boards/shields/totem/           shield definition
    totem.dtsi                    physical-layout + matrix transform + kscan
    totem.zmk.yml                 Studio discovery metadata
    Kconfig.shield, Kconfig.defconfig
    totem_left.{conf,overlay}     peripheral config
    totem_right.{conf,overlay}    peripheral config
    totem_dongle.{conf,overlay}   central config (USB, no sleep, 2 peripherals)
  west.yml                        zmk + zmk-helpers pinned to v0.3

tests/
  behavior_keymap.dtsi            shared 4x4 test keymap mirroring production tuning 1:1
  hrm-*/                          HRM behavior tests (tap-only, hold-opposite, same-hand, quick-tap)
  mod-morph-*/                    qexcl, comma_morph variants
  layer-tap-*/                    lt behavior tap + hold paths
  num-layer-emits-7/              NUM layer activation + key press
  fun-layer-emits-f7/             FUN layer
  util-layer-vol-up/              UTIL layer (consumer-page volume up)
  gaming-layer-disables-hrm/      GAME layer no-HRM property
  combo-activates-gaming/         combo engine + gaming toggle

scripts/
  build.sh                        host wrapper around zmkfirmware/zmk-build-arm:3.5-branch
  docker-build.sh                 runs inside container; parses build.yaml; emits firmware/<artifact>.uf2
  draw.sh                         uv run keymap parse + draw
  test.sh                         shells run-test.sh inside the same docker image

firmware/                         (gitignored) built .uf2 artifacts
keymap-drawer/                    rendered SVGs (committed; useful as reference)
totem.ortho.svg                   primary keymap SVG (committed; matches current keymap)
drawer_config.yaml                keymap-drawer config (preamble + zmk_additional_includes)
totem_keymap.yaml                 intermediate YAML from keymap-drawer parse
pyproject.toml + uv.lock          Python deps (keymap-drawer 0.21.0); managed by uv
```

## Test conventions

Tests live in `tests/<name>/` with three files each:
- `native_posix_64.keymap` — `&kscan { events = <ZMK_MOCK_PRESS(row,col,delay_ms) ...>; };`
- `events.patterns` — sed substitutions turning verbose Zephyr logs into stable one-line-per-event format
- `keycode_events.snapshot` — committed expected output, diffed against fresh runs

The shared `tests/behavior_keymap.dtsi` overrides `&kscan` to `rows=4 columns=4` so `ZMK_MOCK_PRESS(row, col, ms)` resolves to position `row*4 + col` across 16 keys. native_posix_64 ships with `rows=2 columns=2` by default — without the override, `(row=1, col=0)` silently collapses onto position 2 instead of 4. Keep the override.

Layer-tap (`&lt`) tuning is overridden in the test dtsi to match the production override (`balanced`, `tapping-term-ms=250`, `quick-tap-ms=175`). If you ever retune these globally, update both places.

USB HID keycodes in snapshots:
- `usage_page 0x07` = keyboard page (most keys)
- `usage_page 0x0C` = consumer page (media keys like VOL_UP `0xE9`)
- `implicit_mods 0x02` = left-shift implicit (from a shifted-character behavior)
- `keycode 0xE0` = LCTRL, `0xE1` = LSHFT, `0x04` = A, `0x0D` = J, `0x24` = 7, `0x38` = `/` (shifted=`?`), `0x52` = UP arrow

## Common tasks → where to look

| I want to... | Look at |
|--------------|---------|
| Change a key on BASE | `config/totem.keymap` line ~100 onward (default_layer bindings) |
| Add/edit a combo | `config/combos.dtsi`. Bump combo count comment if you care |
| Add a new mod-morph | `config/totem.keymap` near line 83 (existing mod-morphs) |
| Retune HRM timing | `config/totem.keymap:63-72` (MAKE_HRM macro). Run `./scripts/test.sh` after — HRM snapshots will flag the change |
| Add a layer | bump `#define` count at top of `totem.keymap`, add a `*_layer { bindings = < ... >; };` block, add a hold-tap or combo to activate it |
| Edit the shield (GPIO, transform) | `config/boards/shields/totem/totem.dtsi`. Requires re-flashing halves |
| Edit dongle behavior | `config/boards/shields/totem/totem_dongle.{conf,overlay}` |
| Re-render SVG | `./scripts/draw.sh` |
| Run tests | `./scripts/test.sh` |
| After intentional behavior change | `./scripts/test.sh --accept` to regenerate snapshots, eyeball the diff, commit |

## Operational rules

- **Don't unpin `west.yml`** without doing the HWMv2 migration explicitly. Pin to a specific tag, not `main`.
- **Submodule init required on fresh clone:** `git submodule update --init --recursive`. Without it, `./scripts/draw.sh` fails because `zmk-helpers/key-labels/totem.h` isn't on disk.
- **Don't `git push` without confirming.** This is `dmcgoldrd/zmk-config-totem-dongle` on GitHub. Public repo, but pushes still need an explicit go.
- **GPG signing via 1Password sometimes fails** — use `git commit --no-gpg-sign` as fallback (authorized).
- **Test before/after on any keymap edit.** The snapshot tests are the regression net; let them catch the unintended change rather than discovering it on the keyboard.

## Future work (parked)

- **Migrate to Zephyr 4.1 / HWMv2** when ZMK v0.4 ships. Migration guide: <https://zmk.dev/blog/2025/12/09/zephyr-4-1>. The shield itself needs no changes (HWMv2 only restructures boards, not shields); the work is updating `build.yaml` board names (`seeeduino_xiao_ble` → likely `xiao_ble//zmk`) and bumping the Docker image tag from `:3.5-branch` to a `:4.1-branch` variant.
- **Add tests for `hmr_meh`** (the HRM that wraps the comma mod-morph) — niche but a useful regression test if you ever touch that binding.
- **Sticky-key behavior tests** — your `&sk` has `release-after-ms=2000` and `quick-release`; could verify both don't drift.
- **Pin Docker image to SHA** instead of `:3.5-branch` floating tag, once a known-good run is logged.

## References

- ZMK docs: <https://zmk.dev/docs>
- ZMK keymaps & behaviors: <https://zmk.dev/docs/keymaps>
- ZMK Studio: <https://zmk.dev/docs/features/studio>
- zmk-helpers (v2): <https://github.com/urob/zmk-helpers>
- keymap-drawer: <https://github.com/caksoylar/keymap-drawer>
- Pin your ZMK version (June 2025): <https://zmk.dev/blog/2025/06/20/pinned-zmk>
- Zephyr 4.1 upgrade (Dec 2025): <https://zmk.dev/blog/2025/12/09/zephyr-4-1>
- Totem hardware: <https://github.com/GEIGEIGEIST/zmk-config-totem>
