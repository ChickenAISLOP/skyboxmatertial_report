# PAYDAY 2 Skybox / Material Config — Investigation Report

**Date:** 2026-10-15
**Subject:** Can a PAYDAY 2 skybox be animated, and what drives it?
**Short answer:** Yes, two independent ways. **Dome rotation is directly drivable from
Lua** (`_env_handler:editor_set_value`), and whole-environment swap re-grades the sky.
Both act on the **environment** and **material config** layers, not the layer the
existing mod was patching.

> **Read `10_provenance_ledger.md` if you only read one other file.** An earlier version
> of this report stated that rotation was unreachable from Lua. That was wrong, it was
> retracted across five documents, and the ledger records why — it was an inference
> dressed up as a measurement.

---

## Read in this order

| File | Contents |
|---|---|
| `01_sky_inventory.md` | All 38 skies, exact paths, which are actually used |
| `02_sky_material_configs.md` | `dome_sky` schema, `params_a`/`params_b`, the `DIFFUSE0_UVANIM` + `uv0_speed` mechanism |
| `03_environment_schema.md` | `.environment` schema, the three tiers, full key list, sky→environment map |
| `04_animated_skybox_options.md` | The three animation routes, effort vs payoff, why the current mod stalls |
| `05_environment_binary_format.md` | Reverse engineering of the binary container + decoder |
| `06_skybox_features.md` | **Feature spec sheet** — every feature, per-sky matrix, speed reference |
| `07_feature_examples.md` | **One worked example per feature**, with real values |
| `08_render_templates_shaders.md` | `dome_sky`/`dome_clouds`/`dome_sun`, shader inputs, runtime probe |
| `09_environment_authoring.md` | **How the sky is actually animated** — BeardLib, environment XML, the day/night recipe |
| `10_provenance_ledger.md` | **Which claims rest on what** — the rotation retraction, current tier for every claim, process rules |

### Artifacts

| Path | Contents | Published |
|---|---|---|
| `tools/decode_environment.ps1` | Working `.environment` decoder | yes |
| `decoded/sky_inventory.csv` | All 38 skies: params, materials, UV layers, env bindings | yes |
| `decoded/environment_keys.csv` | Every environment key with per-tier coverage (178 keys) | yes |
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

**Dome rotation is the only animation channel present in all 225 environments — and it
IS reachable from a Lua mod.** Corrected finding; see finding 5 and `09`.

---

### 5. Runtime probe: only four sky variables are moddable

An in-game read-only probe enumerated every Lua-reachable environment object.

`CoreSky`, `EnvironmentHandler`, `EnvironmentManager` are **not globals**. The live
route is `managers.viewport:first_active_viewport():vp():get_post_processor_effect(...)`.

A filter for `rot` / `sky` / `orient` / `underlay` / `sun` across all reachable methods
and fields returned **zero hits** — on the **sky material**. That was the wrong layer,
and an earlier draft of this report wrongly generalised it to the whole engine.

The rotation setter exists. It lives on the viewport's environment handler, one level
up from the material:

```lua
local key = Idstring("sky_orientation/rotation"):key()   -- "3c084f67b1da34be"
local h = managers.viewport:first_active_viewport()._env_handler
h:editor_set_value(key, degrees)      -- write
h:get_value(key)                      -- read
```

Verified in-game on `big`, read → write → read-back → restore:

| Step | Value |
|---|---|
| original | `338` |
| wrote `338 + 90` | `68` |
| read back 0.5 s later | `68` |
| restored | `338` |

`managers.viewport:has_data_path_key(key)` returns `YES`, and
`managers.worlddefinition._environment_modifier_id` is literally `"3c084f67b1da34be"` —
the same hash — so the level's own environment modifier is keyed on this value.

Exactly four variables are writable on the sky **material**, via the same path the
Environment Editor uses:

```lua
local mat = Underlay:material(Idstring("sky"))
if mat:variable_exists(Idstring("color0")) then
    mat:set_variable(Idstring("color0"), v)
end
```

| Variable | Live value | Writable |
|---|---|---|
| `params_a` | `0.9, 0.5, 2.0` | yes |
| `params_b` | `0.15, 1, 0` | yes |
| `color0` | `0, 0, 0` | yes |
| `color2` | `0, 0, 0` | yes |
| `color1` | absent | **no** |

`params_a`/`params_b` match the static decoding exactly, validating the binary analysis.

**Correction.** The material probe was sound; the inference drawn from it was not. Four
variables on the material is a statement about the *material*, not about the engine.
`SkyRotationFeeder` is indeed C++-internal, but it is fed from an environment value that
Lua can address directly.

---

## Bottom line

**Yes — and there are two independent ways to do it, not one.**

### 1. Dome rotation — directly drivable (verified in-game)

`sky_orientation/rotation` is a live, writable environment value. Read it, write it,
read it back, restore it. The dome visibly rotated and returned. This is the cheapest
possible animated skybox and it works from Lua in a heist.

```lua
local key = Idstring("sky_orientation/rotation"):key()
local h = managers.viewport:first_active_viewport()._env_handler
h:editor_set_value(key, current_angle + degrees_per_second * dt)
```

It is present in **225 / 225** environments, so it is not a per-level special case.

**Nothing else writes to it during a heist.** A 12-second watch sampled it 24 times and
measured a spread of **0.0000** — completely static, with both viewports agreeing. The
file evidence agrees: `sky_rot` appears in only four files in the whole export, all
editor or lobby Lua, and the modifier is created once at level load. A mod can
therefore own the rotation outright, with nothing to arbitrate against.

### 2. Environment swap — re-grades the whole sky

Four parameters do it: `underlay`, `color0`, `color2`, `sun_ray_color`. A working
17-variant day/night cycle ships in the `Day & Night Full` mod, driven by
`managers.worlddefinition:_set_environment()`.

```lua
BeardLib:ReplaceScriptData(path, "custom_xml", "environments/morning", "environment", true)
managers.worlddefinition:_set_environment("environments/morning")
```

`_set_environment` is confirmed present and callable. Its candidates are real DB paths
of the form `environments/<dir>/<name>` — all verified `YES` — but an in-heist swap has
not yet been confirmed to change the rendered sky; the level's own environment name is
not readable from Lua, so the revert path could not be captured. Treat swap as
**authoring-proven, runtime-unproven**. `BeardLib-Editor` gives it a GUI.

Runtime Lua on the sky *material* remains limited to four variables (`params_a`,
`params_b`, `color0`, `color2`), and that surface alone only produces a slow colour
wash. Rotation is a separate surface on the environment handler and is fully open.

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

`units/` is **absent** from this export. See the known-gap note in *Data recovered*.

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
| Sky assets located | **38 skies** — 34 folders under `core/environments/skies` + 4 root-level configs |
| `.material_config` schema | Fully read, plain XML |
| Render templates | 3 dome templates declared, 1 used — see `08` |
| Shader inputs | Recovered from DXBC reflection in `core/shaders/` |
| Environment key sets | 225 / 225 |
| `underlay` sky binding | 223 / 225 (the 2 exceptions are the 2 Tier-2 files) |
| Literal float constants | 2,210 slots, 575 distinct |
| Live sky values | Probed in-game: `params_a`/`params_b` match static decoding exactly |
| Lua-reachable sky controls | **4 variables** — `params_a`, `params_b`, `color0`, `color2` |
| Environment XML schema | Full schema recovered from BeardLib - see `09` |
| `sky_orientation/rotation` | **Drivable from Lua** via `_env_handler:editor_set_value` — corrected |
| Environment node/value block | **Partially decoded** — 40-byte descriptor table mapped, field semantics unknown, see `05` |

### Known gap: `units/` was never exported

The install is 31.66 GB across 98 `.crate` files; the export used here is 217 MB /
2,536 files and has **no `units/` directory**. 14 `underlay` bindings point into
`units/`, and three of those sky configs were never extracted — including
`sky_1945_sunset_clouds_mex`. Details and how to close it in `08`.

Everything except the node/value block's field semantics is verified directly from the
export. The remaining gap is per-key numeric attribution inside that block. `coresky.lua`
exports as LuaJIT bytecode, but its string table exposes `class.CoreSky` with
`database_lookup`, `interpolate`, `set_value` and `LightIntensityDB` — enough to read
any key's live value in-game, which is cheaper than further binary work.