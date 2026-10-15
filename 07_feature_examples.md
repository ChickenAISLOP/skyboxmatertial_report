# 07 — Feature Examples

One worked example per feature from `06_skybox_features.md`. Every value below was
read from the exported assets.

Legend: **decoded** = value recovered · **key only** = key recovered, value lives in
the undecoded node/value block (see `05`)

Scope: **38 skies**, **225 environments**. Both re-derived by content filter, not path
filter — see *Corrections* at the end.

---

# The four animatable features

## 1. Dome rotation — key only

```
sky_orientation
└─ param
   ├─ key   = rotation
   └─ value = <vector3>
```

- **Where:** inside every one of the 225 `.environment` files
- **Coverage:** 225 / 225
- **Runtime:** `Global.level_data` → environment → `sky_orientation`
- **Status:** key decoded, value in the node/value block

The only animation channel that works in every environment. `rotation` also appears in
the 225/225 key set alongside `sky_orientation`, `param`, `key`, `value`.

---

## 2. Cloud scroll — fully decoded

The only sky in the game with animated clouds. Full config:

```xml
<!-- sky_1945_sunset_clouds.material_config -->
<materials>
    <material name="sky" render_template="dome_sky">
        <diffuse_texture file=".../sky_1945_sunset_clouds_df"/>
        <variable name="params_a" type="vector3" value="0.2 0.0 0.1"/>
        <variable name="params_b" type="vector3" value="0.25 0.5 0"/>
    </material>

    <material name="clouds_top" render_template="effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR" version="2">
        <diffuse_texture file=".../top_clouds_df"/>
        <variable value="sun"       type="scalar"  name="intensity"/>
        <variable value="0 -0.0060000000521541 0" type="vector3" name="uv0_speed"/>
    </material>

    <material name="clouds_02" render_template="effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR" version="2">
        <diffuse_texture file=".../stormy_clouds_df"/>
        <variable value="reddot"    type="scalar"  name="intensity"/>
        <variable value="0.0049999998882413 0 0" type="vector3" name="uv0_speed"/>
    </material>

    <material name="clouds_02_slow" render_template="effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR" version="2">
        <diffuse_texture file=".../stormy_clouds_df"/>
        <variable value="reddot"    type="scalar"  name="intensity"/>
        <variable value="0.0029999988619238 0 0" type="vector3" name="uv0_speed"/>
    </material>
</materials>
```

Values are stored at full float precision; rounded in the tables below.

**How it works:**

| Part | Role |
|---|---|
| `DIFFUSE0_UVANIM` in `render_template` | Enables UV animation. **Without this token `uv0_speed` is inert** |
| `uv0_speed` | Scroll rate. `.x` = U, `.y` = V, `.z` unused |
| `intensity` | Named lighting reference — `sun` / `reddot` observed |
| `clouds_02` vs `clouds_02_slow` | **Same texture, different speed.** That parallax is the trick |

**Every `uv0_speed` that ships in the game** — 8 values across 4 configs:

| Config | Material | Value (u, v, —) | Reads as |
|---|---|---|---|
| `sky_1945_sunset_clouds` | `clouds_top` | `0 -0.006 0` | vertical drift down |
| `sky_1945_sunset_clouds` | `clouds_02` | `0.005 0 0` | horizontal, medium |
| `sky_1945_sunset_clouds` | `clouds_02_slow` | `0.003 0 0` | horizontal parallax |
| `vit_stormclouds` | — | `0.001 0 0` | barely perceptible |
| `vit_stormclouds` | — | `0 0.01 0` | 10× faster vertical |
| `lxy_bdrop_skyline` | — | `0.02 0 0` | fast |
| `lxy_bdrop_skyline` | — | `0 0.5 0` | conveyor belt |
| `cas_skylight_barrier_hack` | — | `-1.5 ~0 0` | hazard scanline |

Values are **not normalised**. `-1.5` is legal and ships.

Note the attribute order is inconsistent in the source files — `sky_1945_sunset_clouds`
writes `value` before `name`, `lxy_bdrop_skyline` writes `type` first. Any parser must
match attribute order independently.

**To roll your own:** the texture needs `wrap = repeat` or it seams. And in Tier 3
environments, `uv_velocity_*_mask` applies motion blur to it.

---

## 3. Sun animation — key only

```
sun_anim          sun animation master
sun_anim_x        sun animation, X axis
```

- **Coverage:** 49 / 225 environments
- **Absent from:** all 174 Tier 1 environments
- Backed by `interpolate` in `core/lib/managers/coresky.lua`

---

## 4. Lens flare animation — key only

```
flare_anim_x      flare animation, X
flare_anim_y      flare animation, Y
```

Eight flares, each independently animated:

```
flare_index_1 .. flare_index_8
flare_alpha_1 .. flare_alpha_8
flare_offset_1 .. flare_offset_8
flare_scale_1 .. flare_scale_8
flare_color        flare_name
```

- **Coverage:** all 33 flare keys appear in exactly **49 / 225**
- `flare_name` resolves through `LightIntensityDB` / `database_lookup` in `coresky.lua`

---

# The non-animatable sky variables — all decoded

Real values, straight from the configs. Counts are over **38 skies**.

## 5. Sky brightness — `params_b.x`

```xml
<variable name="params_b" type="vector3" value="0.25 0.5 0"/>
```

| Value | Skies |
|---|---|
| `0.1` | `sky_279_dusk`, `sky_corp_deep_blue`, `sky_pent_dusk_0065` — dimmest |
| `0.15` | `default`, `sky_cloudy_blue` |
| `0.25` | 32 skies — the default |
| `0.5` | `sky_0200_night_moon_stars` — brightest |

Range observed: `0.1` to `0.5`. Bimodal — nothing between `0.15` and `0.25`, or
between `0.25` and `0.5`.

## 6. Sun disc — `params_b.y`

`1` = visible sun disc, `0.5` = no sun.

```xml
<variable name="params_b" type="vector3" value="0.25 1 0"/>   <!-- sun visible -->
<variable name="params_b" type="vector3" value="0.25 0.5 0"/> <!-- no sun -->
```

**6 of 38** skies have a sun disc; the other 32 use `0.5`:

```
default        sky_cloudy_blue   sky_1931_low_sun
sky_1008_cloudy    sky_2003_dusk_blue    sky_2003_sunrise
```

All six are daylight or low-sun skies. Every twilight and night sky uses `0.5`.

## 7. Gradient spread — `params_a.x`

`1` for **35 of 38** skies (31 write `1`, 4 write `1.0` — same value). Outliers:

| Value | Sky |
|---|---|
| `0.9` | `default`, `sky_cloudy_blue` |
| `0.2` | `sky_1945_sunset_clouds` — dome is a backdrop |

## 8. Gradient offset — `params_a.y`

Goes **negative** on twilight skies, pushing the gradient band up the dome:

| Value | Skies |
|---|---|
| `-0.09` | `sky_2003_dusk_blue`, `sky_2003_sunrise`, `sky_2100_moon`, `sky_dah_night` |
| `0.0` | 30 skies |
| `0.05` | `sky_0200_night_moon_stars` |
| `0.1` | `sky_1930_sunset_heavy_clouds` |
| `0.5` | `default`, `sky_cloudy_blue` |

## 9. Gradient curve — `params_a.z`

`> 1` steepens the gradient so the horizon band compresses:

| Value | Skies |
|---|---|
| `0.1` | `sky_1945_sunset_clouds` |
| `0.9` | `sky_1930_sunset_heavy_clouds` |
| `0.95` | `sky_1008_cloudy` |
| `1.0` | 28 skies |
| `1.2` | `sky_0200_night_moon_stars` |
| `1.5` | `sky_2003_dusk_blue`, `sky_2003_sunrise`, `sky_2100_moon`, `sky_dah_night` |
| `2.0` | `default`, `sky_cloudy_blue` |

## 10 & 11. Legacy colours — `color0` / `color2`

```xml
<!-- OLD shit -->
<variable name="color0" type="vector3" value="1.0 1.0 1.0"/>   <!-- sky top -->
<variable name="color2" type="vector3" value="1.0 1.0 1.0"/>   <!-- sky bottom -->
```

**All 38 of 38 skies ship `1.0 1.0 1.0` for both** in the config file. That is the
*static* value.

At runtime it is a different number. Live probe of `modders_devmap`:

```
params_a  Vector3(0.9000, 0.5000, 2.0000)
params_b  Vector3(0.1500, 1.0000, 0.0000)
color0    Vector3(0.0000, 0.0000, 0.0000)
color1    <absent>
color2    Vector3(0.0000, 0.0000, 0.0000)
```

`params_a` and `params_b` match the static config exactly — the binary decoding in
this document is confirmed against live values. `color0` and `color2` do **not**: the
config says `1.0 1.0 1.0`, the running material reads `0, 0, 0`. Both are present,
both are writable.

`color1` is declared by the dome shader but `variable_exists` returns **false** at
runtime, and the write path is gated on the same check, so it is **not settable**. An
unused shader input, not a free parameter.

This is the variable set the existing mod's author probed and concluded the sky was
static from. The conclusion was right; `color0`/`color2` just aren't where the live
values live.

Note the environment binary uses the same key names (`color0`, `color2`, plus
`color0_scale`, `color2_scale`, `sky_top_color`, `sky_bottom_color`) — those are
environment-level lighting, separate from the material variables above.

---

## 12. Sky cubemap swap — decoded

`underlay` is what the game reads to pick the sky:

```
underlay = core/environments/skies/sky_1945_sunset/sky_1945_sunset
```

- **Coverage:** 223 / 225 recovered. The 2 exceptions are `pd2_env_hox_02` and
  `pd2_ff_2` — both Tier 2, which uses a different node shape
- **Most-used:** `sky_2335_night_moon` → 45 environments
- **Not always `core/`:** 209 under `core/`, **14 under `units/`** (Corp, Pent, Sah)
- **32 distinct skies** are bound by at least one environment; the other 6 are unbound
- `underlay` and `underlay_effect` both appear in **225 / 225**

Full map in `decoded/environment_summary.csv`.

---

# Tier 3 features — key only

Coverage figures are exact. Three tiers of coverage exist:

| Coverage | Meaning | Keys |
|---|---|---|
| **225** | every environment | `sun_ray_color`, `sun_ray_color_scale`, `underlay`, `rotation`, … |
| **51** | 49 Tier 3 + both Tier 2 | the post stack: tone mapping, DOF, bloom, SSAO, reflections |
| **49** | Tier 3 only | sun + flare animation, motion blur |
| **35** | 33 Tier 3 + both Tier 2 | fog / god rays |
| **34** | 32 Tier 3 + both Tier 2 | `sun_range`, `min_range`, `max_range` |

## 13. Sun colour, both directions

```
color_sun              color_sun_scale              49
color_opposite_sun     color_opposite_sun_scale     49
alpha_scale_sun        alpha_scale_opposite_sun     49
sun_range              sun_color    sun_color_scale
sky_intensity          sky_top      sky_bottom       51
```

- `color_opposite_sun` means the environment models light from **both** the sun and its
  opposite — a full atmospheric model, not a colour swap
- **`sun_range` is 34, not 49.** 17 Tier 3 environments have the full sun model but no
  `sun_range`
- **`sky_intensity` is 51, not 49** — both Tier 2 environments carry it

## 14. Volumetric sun rays

```
sun_ray_color          sun_ray_color_scale
```

Present in **all 225**. One of only 42 keys in the 225/225 set. The scale value
differs between tiers; the key never disappears.

## 15. Auto-exposure

```
tone_mapping           middle_grey            white_luminance
dark_to_bright_adaption_speed   bright_to_dark_adaption_speed
luminance_clamp        disable_tone_mapping   exposure_sepia_levels
```

All **51**. Bidirectional adaptation speed = real auto-exposure. **The sky drives
exposure**, so a changing sky re-grades the whole scene.

## 16. Depth of field

```
depth_blur    near_focus_distance_min    near_focus_distance_max
              far_focus_distance_min     far_focus_distance_max
```

All **51**.

## 17. Bloom

```
bloom_apply   bloom_brightpass
```

Both **51**.

## 18. Ambient occlusion

```
ssao   global_ssao   local_ssao
```

All **51**.

## 19. Motion blur

```
uv_velocity_rg_mask    uv_velocity_b_mask    uv_scale_b_mask
```

All **49** — Tier 3 only, matching sun and flare animation exactly. Implies motion blur
is driven from animated UV motion. Anything you scroll gets blurred.

## 20. God rays / scatter

```
fog_curve              fog_sun_range          fog_sun_scatter_color
fog_height_range       fog_far_high_color
```

All **35**, not 51 — these are not universal even within Tier 3. 16 Tier 3
environments lack the fog model entirely.

## 21. Cloud overlay

```
cloud_overlay
```

**51**.

## 22. Sky reflection

```
sky_reflection_top_color        sky_reflection_top_color_scale
sky_reflection_bottom_color     sky_reflection_bottom_color_scale
height_fade      height_fade_intesity_clamp      environment_map_intensity
```

All **51**. What the sky contributes to shiny surfaces.

---

## Coverage summary

| Tier | Envs | Features available |
|---|---|---|
| 1 — Legacy | **174** | 1 (rotation), 5–12, 14 |
| 2 — Post stack, static sun | **2** | 1, 5–12, 14–22 except 3, 4 |
| 3 — Post stack + anim | **49** | all 22 |

Only feature **1** works in 100% of environments.

---

## Cross-check against the community wikis

The **Payday Wiki** (2,036 pages) has **no skybox or environment article at all** — a
`Skybox` page is offered as a red link ("Create the page"). Its `Materials` article
covers mask cosmetics, not engine materials. `PAYDAY 2 mods and tools` documents the
Bundle Tool (extractor), Mod Tool, and mod overrides, and nothing about
`material_config` or `.environment` formats.

The **modworkshop wiki** was more useful. Its
[Material Config XML](https://wiki.modworkshop.net/books/payday-2-mod-creation/page/material-config-xml)
page points to `shaders/base.render_template_database` for the authoritative variable
list. Following that pointer into `core/shaders/` produced the render template and
shader findings in `08_render_templates_shaders.md`, including confirmation that the
`uv_velocity_*`, `color_sun` and `alpha_scale_*` keys are real shader uniforms.

Most values in this document come from the binary export. Where the community wikis
cover the format at all, they cover `material_config` structure only.

---

## Corrections applied in this revision

The previous version of this document was wrong in ten places. All traced to two
methodology bugs:

1. **Path filter instead of content filter.** Skies were selected by directory name
   matching `environments.skies|skydomes`, which silently excluded every root-level
   config. Content-filtering on `render_template="dome_sky"` gives **38** skies, not 34.
2. **Name collisions.** `sky_1313_cloudy` and `sky_1313_cloudy_dark` are two distinct
   skies whose config files are **both** named `sky_1313_cloudy.material_config` —
   the dark one's sits in its own folder with the wrong filename. Deduping by filename
   merged them into one.

| Claim | Was | Now |
|---|---|---|
| Sky count | 34 | **38** |
| `params_b.x = 0.25` | 25 skies | **32** |
| `params_b.x = 0.1` | 2 skies | **3** (`sky_corp_deep_blue` missing) |
| `params_a.x = 1` | 32 of 34 | **35 of 38** |
| `params_a.y = 0.0` | 26 skies | **30** |
| `params_a.z = 1.0` | 23 skies | **28** |
| `sun_range` coverage | 49 | **34** |
| `sky_intensity` coverage | 49 | **51** |
| Skies with a sun disc | 6 | 6 (unchanged) |
| Skies with `color0`/`color2` | "every sky" | **38 / 38**, verified |

Every row of `decoded/sky_inventory.csv` was re-derived from its config file after
generation and verified field by field: **0 mismatches**, env bindings sum to 223,
matching the 223 recovered `underlay` values.

## Getting the remaining values

Every "key only" feature's numeric value sits in the node/value block, which is
partially decoded — see `05`. The 40-byte descriptor table is mapped but its field
semantics aren't.

The cheap route is live extraction: `coresky.lua` exposes `interpolate` and
`database_lookup` against `Global.level_data`, which is enough to read any key's live
value without further binary work.