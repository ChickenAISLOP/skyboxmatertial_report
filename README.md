# PAYDAY 2 Skybox / Material Config — Investigation Report

**Date:** 2026-10-15
**Subject:** Can a PAYDAY 2 skybox be animated, and what drives it?
**Short answer:** Yes. Vanilla already does it — but through the **environment** and
**material config** layers, not the layer the existing mod was patching.

---

## Read in this order

| File | Contents |
|---|---|
| `01_sky_inventory.md` | All 34 sky assets, exact paths, which are actually used |
| `02_sky_material_configs.md` | `dome_sky` schema, `params_a`/`params_b`, the `DIFFUSE0_UVANIM` + `uv0_speed` mechanism |
| `03_environment_schema.md` | `.environment` schema, the three tiers, full key list, sky→environment map |
| `04_animated_skybox_options.md` | The three animation routes, effort vs payoff, why the current mod stalls |
| `05_environment_binary_format.md` | Reverse engineering of the binary container + decoder |

### Artifacts

| Path | Contents | Published |
|---|---|---|
| `tools/decode_environment.ps1` | Working `.environment` decoder | yes |
| `decoded/environments.json` | Full dump of all 225 (7.2 MB) | no — regenerate |
| `decoded/environment_summary.csv` | `underlay`, `global_texture`, literal pool floats (79 KB) | no — regenerate |
| `aireportpd2/` | Raw asset export, 2,536 files / 217 MB | no — game assets |

The raw export is ripped Overkill content and is **not** committed — it is gitignored.
The two decoded outputs are large and fully reproducible:

```powershell
.\tools\decode_environment.ps1 -Path <your>\environments -Recurse -JsonOut decoded\environments.json
```

---

## The four headline findings

### 1. `core/material_configs/` is NOT where the sky lives

It holds only 3 files, none sky-related:

```
effect_gizmo.material_config
hub_elements.material_config
widgets_materials.material_config
```

Each sky's config sits next to its texture:
`core/environments/skies/<sky_name>/<sky_name>.material_config`

### 2. The existing mod targets the right material but the wrong capability

`Underlay:material(Idstring("sky"))` **is** correct — every sky config declares
`name="sky"`. But the render template is `dome_sky`, which exposes only `params_a`
(range / offset / curve), `params_b` (sky intensity / sun intensity) and legacy
`color0`/`color2`. No `uv_speed`, no UV animation. Confirmed three independent ways —
see `02_sky_material_configs.md`. The mod's own header comment already reached this
conclusion correctly.

### 3. Animation lives in two other places, both vanilla

- **Cloud scroll** — `effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR` +
  `uv0_speed`. Shipped in `sky_1945_sunset_clouds`, `vit_stormclouds`,
  `lxy_bdrop_skyline`, `cas_skylight_barrier_hack`.
- **Environment-level** — `sky_orientation.rotation` in **all 225** environments;
  `sun_anim` + `flare_anim_x`/`flare_anim_y` in **49**.

The dome itself never moves. Clouds, sun and flares do.

### 4. The 49 are not "animated environments" — they are the modern render pipeline

Diffing two environments on the same sky showed those 49 carry an entire HDR stack the
other 174 do not:

```
tone_mapping  middle_grey  white_luminance
bright_to_dark_adaption_speed  dark_to_bright_adaptation_speed
ssao  depth_blur  near_focus_distance_min/max  far_focus_distance_min/max
bloom_apply  bloom_brightpass
uv_velocity_rg_mask  uv_velocity_b_mask
```

Auto-exposure tone mapping, depth of field, SSAO, bloom and motion blur. Sun/flare
animation ships **as part of that pipeline**, which is why it is absent from the 174
legacy environments — they have no sun model at all.

| Tier | Count | Node block | What |
|---|---|---|---|
| 1 — Legacy flat | **174** | 1.8–2.5 KB | No sun model |
| 2 — Post stack, static sun | **2** | 5.3 KB | `pd2_env_hox_02`, `pd2_ff_2` |
| 3 — Post stack + animation | **49** | 6.6–7.3 KB | Full HDR |

**`env_menu` is Tier 3.** The main menu runs the full stack with an animated sun. That
is exactly where the mod was costing framerate.

**Dome rotation is the only animation channel available in all 225 environments.**

---

## Bottom line

Rotation is available everywhere and costs nothing — try it first. Visible cloud
motion requires scene geometry, not just a config edit, so it is a sky-authoring
project rather than a patch. Full reasoning in `04_animated_skybox_options.md`.

---

## Exported assets

Diesel Crate Browser export of
`D:\SteamLibrary\steamapps\common\PAYDAY 2\assets`, dumped into `aireportpd2/`.
**Not committed to this repository** — gitignored, see *Artifacts* above.

| Folder | Files | Size |
|---|---|---|
| `aireportpd2/core/` | 724 | 132.7 MB |
| `aireportpd2/environments/` | 311 | 58.2 MB |
| `aireportpd2/lib/` | 1256 | 20.7 MB |
| `aireportpd2/gamedata/` | 147 | 2.4 MB |
| `aireportpd2/skydomes/` | 7 | 2.7 MB |
| `aireportpd2/settings/` | 10 | 0.2 MB |
| `aireportpd2/` (root) | 77 | ~0.1 MB |
| **total** | **2,536** | **217.1 MB** |

### Notes on the export

- The **root-level** `*.material_config` files are a flat duplicate set, verified
  byte-identical to the canonical nested copies by SHA-256. The nested path is
  canonical.
- `.material_config` exports as clean XML.
- `.lua` and `.environment` are stored in Overkill's serialized-chunk container.
  **All 1,646 exported `.lua` files are binary** — none are plain text. The
  `.environment` container was reverse engineered; see `05_environment_binary_format.md`.
- **`.crate` contents cannot be grepped.** A full scan of all 98 `.crate` files
  (~30 GB, 431 s) found zero plaintext occurrences of `material_configs` or
  `sky_1345_clear_sky`. Paths are hashed and `crates.shipping_manifest` stores 16-byte
  GUIDs. The GUI export or the in-game `DB:open(type, idstring)` API are the only
  decode routes.

---

## Data recovered

| Item | Coverage |
|---|---|
| Sky assets located | 34 / 34 folders, every file enumerated |
| `.material_config` schema | Fully read, plain XML |
| Environment key sets | 225 / 225 |
| `underlay` sky binding | 223 / 225 (the 2 exceptions are the 2 Tier-2 files) |
| Literal float constants | 2,210 slots, 575 distinct |
| Environment node/value block | **Partially decoded** — 40-byte descriptor table mapped, field semantics unknown, see `05` |

Everything except the node/value block's field semantics is verified directly from the
export. The remaining gap is per-key numeric attribution inside that block, which is
cheaper to get in-game via the Environment Editor mod than by further binary work.