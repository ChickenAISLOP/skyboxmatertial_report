# 03 — Environment Schema

225 `.environment` files were exported from `environments/`.

The container was reverse engineered: header, float pool, string table, tag stream and
key→value bindings are all decoded. Full format write-up in
`05_environment_binary_format.md`; the decoder is `tools/decode_environment.ps1`.

**Not** the same container as `.lua`. `.lua` files use Overkill's `1B 4C 4A` serialized
chunk; `.environment` uses a distinct layout documented in `05`.

---

## Key finding

| Property | Count | Share |
|---|---|---|
| Files with an `underlay` (sky texture bound) | **225** | **100%** |
| Files with `sky_orientation` | **225** | **100%** |
| Files with the HDR post stack (`tone_mapping`) | 51 | 23% |
| Files with `sun_anim` + `flare_anim_x/y` | **49** | 22% |

**Every single environment can rotate its sky.** Rotation is not a special case —
`sky_orientation` is always present.

---

## The three tiers

The 225 environments split cleanly by which keys they carry, by file size, and by the
size of their decoded node/value block.

| Tier | Count | File size | Node block | Strings | What it is |
|---|---|---|---|---|---|
| **1 — Legacy** | **174** | 4,452 – 6,004 B | 1.8 – 2.5 KB | 47 | Flat. Sky + ambient + fog only |
| **2 — Post stack, no animation** | **2** | ~11,600 B | 5.3 KB | 94–132 | Full HDR pipeline, static sun |
| **3 — Post stack + sun/flare animation** | **49** | 11,620 – 16,588 B | 6.6 – 7.3 KB | 132–163 | Full HDR pipeline, animated |

Tier is determined by string presence, **not** by the header complexity counter — see
`05_environment_binary_format.md` for the counterexamples that prove this.

### Tier 1 — Legacy (174 environments)

Only the keys in the "Full key list" below. No tone mapping, no bloom, no SSAO, no
sun animation, no flares. All 174 carry **exactly 28** real keys.

### Tier 2 — Post stack, static sun (2 environments)

```
pd2_env_hox_02
pd2_ff_2
```

The only two files where the `key → name → value → value` token pattern does not
resolve, which indicates a different node shape. Treat their structure as unverified.

### Tier 3 — Full HDR pipeline + animation (49 environments)

```
env                      env_cafe                env_nightclub
env_0200_night_moon_stars env_office             env_street
env_1830_low_sun_clouds  env_test_dark           env_trailer_bank
env_1930_sunset_heavy_clouds env_watchdogs_2_3  pd2_env_afternoon
env_1945_sunset          env_asset_texturing     pd2_env_arm_fac
env_2003_dusk_blue       env_bridge2             pd2_env_arm_hcm_02
env_assault_forest       env_csgo_de_bank        pd2_env_bigbank
env_diamond2             env_forest_fog          pd2_env_docks
env_gunrange             env_forest_fog2         pd2_env_ed1
env_menu                 testing                 pd2_env_ed2
                                                 pd2_env_foggy_bright
pd2_env_framing_frame_stage_2                      pd2_env_jew_street
pd2_env_framing_frame_stage_3                      pd2_env_midday
pd2_env_morning          pd2_env_morning_02       pd2_env_motel
pd2_env_mountain         pd2_env_n2               pd2_env_rat_stage_2
pd2_env_sunset           pd2_env_villa_vivaldi    pd2_env_wd2_evening
pd2_hlm1                 pd2_hox_1                pd2_kosugi
pd2_res
```

---

## What Tier 3 actually carries

Diffing two environments on the **same sky** (`pd2_hox_1` = Tier 3, `pd2_env_night` =
Tier 1, both `sky_2100_moon`) isolates exactly what the animation tier adds. 159
strings vs 49.

### The 8-flare system (Tier 3 only)

```
flare_name        flare_color
flare_index_1 .. flare_index_8
flare_alpha_1 .. flare_alpha_8
flare_offset_1 .. flare_offset_8
flare_scale_1 .. flare_scale_8
flare_anim_x      flare_anim_y
```

### Sun model (Tier 3 only)

```
sun_anim          sun_anim_x
sun_color         sun_color_scale
color_sun         color_sun_scale
color_opposite_sun          color_opposite_sun_scale
alpha_scale_sun             alpha_scale_opposite_sun
sun_range
sun_ray_color               sun_ray_color_scale
sun_specular_color          sun_specular_color_scale
```

Note the **opposite-sun** terms — the environment models light from both the sun and
its opposite. That is a full atmospheric model, not a tint.

### HDR tone mapping with auto-exposure (Tier 3 only)

```
tone_mapping                    middle_grey
white_luminance                 luminance_clamp
bright_to_dark_adaption_speed   dark_to_bright_adaption_speed
disable_tone_mapping            exposure_sepia_levels
```

`middle_grey` + `white_luminance` + bidirectional adaptation speed is a **full
auto-exposure pipeline**. The sky drives exposure.

### Post-processing (Tier 3 only)

```
ssao          global_ssao     local_ssao
depth_blur    near_focus_distance_min / _max
              far_focus_distance_min  / _max
bloom_apply   bloom_brightpass
```

`near_focus_*` / `far_focus_*` is a **depth-of-field** setup — these are the cinematic
environments.

### Motion blur (49 environments)

```
uv_velocity_rg_mask
uv_velocity_b_mask
```

These are per-channel UV velocity masks. Their presence in exactly the 49 animated
environments implies **motion blur is driven from animated UV motion**. Anything you
scroll will be motion-blurred. Relevant if you build Option B — verify it looks right
and does not smear.

### Other Tier 3 additions

```
cloud_overlay        sky_intensity       sky_top        sky_bottom
fog_curve           fog_sun_range       fog_height_range
fog_sun_scatter_color
sky_reflection_top_color / _scale
sky_reflection_bottom_color / _scale
environment_map_intensity / _shadow
height_fade         height_fade_intesity_clamp
shadow_fadeout      fadeout_blend
start  end0  end1  end2  start_color  start_color_scale
min_range  max_range  clamp  threshold  intensity  opacity  soften
color0  color1  alpha0  alpha1
$template_mix
```

`$template_mix` is the only string beginning with `$` — likely a shader template
variable rather than a plain key.

---

## Why this reframes the animation question

Tier 3 is not "the animated environments". Tier 3 is **the modern rendering pipeline**,
and sun/flare animation ships as part of it.

Two consequences:

1. **`env_menu` is Tier 3.** The main menu runs the full HDR + DOF + SSAO + bloom +
   motion-blur stack with an animated sun. That is why per-frame sky work is expensive
   there — it is the most expensive environment in the game, and the mod was touching
   it. Gating on heist load, as the mod already attempts, is correct.

2. **Animation coverage is really 49/225 = 22%, and those are outdoor showcase levels.**
   The 174 legacy environments have no sun model at all, so Option C is unavailable in
   ~78% of environments. Dome rotation (Option A) is the only channel that works
   everywhere.

---

## How this was extracted

A decoder for the proprietary binary container ships with this report:

```
tools/decode_environment.ps1
decoded/environments.json        full dump, all 225
decoded/environment_summary.csv  underlay + global_texture + literal pool floats
```

`underlay` — the sky binding — was recovered from the decoded tag stream for
**223 of 225** environments. The two exceptions are exactly the two Tier-2 files,
which use a different node shape.

**2,210 literal float values** were recovered from the constant pools across all 225
files (575 distinct). These are genuine per-environment tuning values — intensities,
scales and colour multipliers, clustering in `0.0 – 1.0`. Format detail and the
remainder of the decode are in `05_environment_binary_format.md`.

---

## Full key list

Recovered from the string tables. Grouped by subsystem.

### Sky binding and orientation

| Key | Type | Meaning |
|---|---|---|
| `underlay` | texture path | **The sky cubemap.** e.g. `core/environments/skies/sky_1945_sunset/sky_1945_sunset` |
| `sky_orientation` | group | Orientation control |
| `sky_orientation.rotation` | vector3 | **Dome rotation.** Present in all 225 |

`underlay` is the field the game uses to pick the sky. It points at the **texture**,
not the material config. The material config is found by convention in the same folder.

### Sun

| Key | Meaning |
|---|---|
| `sun_ray_color` | Volumetric sun shaft colour |
| `sun_ray_color_scale` | Sun shaft intensity |
| `sun_specular_color` | Specular highlight tint |
| `sun_specular_color_scale` | Specular intensity |
| `sun_anim` | **Sun animation master** |
| `sun_anim_x` | **Sun animation, X axis** |

### Lens flares (8 per environment)

| Key pattern | Range |
|---|---|
| `flare_name` | flare definition name, default `default` |
| `flare_index_N` | N = 1..8 |
| `flare_color` | flare tint |
| `flare_alpha_N` | N = 1..8 |
| `flare_offset_N` | N = 1..8 |
| `flare_scale_N` | N = 1..8 |
| `flare_anim_x` | **flare animation, X** |
| `flare_anim_y` | **flare animation, Y** |

Eight independently positioned, scaled, tinted and animated flares. This is the
sun/lens-flare system of a Source-engine sky at sunset.

### Sky colour and reflection

```
sky_top_color                  sky_bottom_color
sky_reflection_top_color       sky_reflection_bottom_color
sky_reflection_top_color_scale sky_reflection_bottom_color_scale
sky_bottom_color_scale
```

The reflection colours are what the sky contributes to shiny surfaces.

### Ambient and lighting

```
ambient_color                  ambient_color_scale
ambient_scale                  ambient_falloff_scale
environment_map_intensity      environment_map_intensity_shadow
effect_light_scale             height_fade
height_fade_intesity_clamp     apply_ambient
```

### Render pipeline

```
post_effect
deferred                       deferred_lighting
shadow                         shadow_rendering
shadow_processor               shadow_modifier
shadow_fadeout_blend           fadeout_blend
slice0 slice1 slice2 slice3
shadow_slice_overlap           shadow_slice_depths
global_texture                 e.g. core/textures/cubemap_default
```

`shadow_processor` with 4 slices (`slice0..3`) — CSM. `global_texture` is the default
reflection cubemap when a level has no custom one.

---

## The `underlay` → sky map

Grouped by sky, environment count descending.

| Sky | envs |
|---|---|
| `sky_2335_night_moon` | 46 |
| `sky_2003_dusk_blue` | 28 |
| `sky_1224_clear_sky` | 20 |
| `sky_0200_night_moon_stars` | 18 |
| `sky_2100_moon` | 16 |
| `default` | 16 |
| `sky_0902_overcast` | 9 |
| `sky_pent_dusk_0065` | 9 |
| `sky_1313_cloudy_dark` | 10 |
| `sky_1530_low_sun_clouds` | 6 |
| `sky_1008_cloudy` | 4 |
| `sky_1313_cloudy` | 4 |
| `sky_1945_sunset` | 3 |
| `sky_corp_deep_blue` | 3 |
| `sky_2000_twilight_mad` | 3 |
| `sky_1945_sunset_clouds` | 3 |
| `sky_277_dusk` | 2 |
| `sky_279_dusk` | 2 |
| `sky_0927_whispy_clouds` | 2 |
| `sky_1830_low_sun_clouds` | 2 |
| `sky_1930_sunset_heavy_clouds` | 2 |
| `sky_1930_twillight` | 2 |
| `sky_1931_low_sun` | 2 |
| `sky_2003_sunrise` | 2 |
| `sky_city_clear_high` | 2 |
| `sky_dah_night` | 2 |
| `sky_city_clear` | 1 |
| `sky_0902_overcast_dark` | 1 |
| `sky_1345_clear_sky_mountain_01` | 1 |
| `sky_csgo_de_bank_cs15_daylight02` | 1 |
| `sky_v2_030_sun_low` | 1 |
| `sky_1945_sunset_clouds_mex` | 1 |

### Skies with zero vanilla environments

```
sky_1345_clear_sky
sky_1846_low_sun_nice_clouds
sky_cloudy_blue
sky_1044_overcast_sun
sky_2003_dusk_blue_high_color_scale
sky_rvd_la_afternoon
```

Present in the game, referenced by nothing. Safe to repurpose without breaking a
level — useful if you want a sky that vanilla never binds and therefore never loads.

### Not `core/environments/skies/`

Four skies live in DLC folders instead:

| Environment group | Path |
|---|---|
| Corp | `units/pd2_dlc_corp/cubemaps/sky_corp_deep_blue/…` |
| Pent / Trains | `units/pd2_dlc_pent/architecture/cubemaps/sky_pent_dusk_0065/…` |
| Mex | `units/pd2_dlc_mex/environments/sky_1945_sunset_clouds_mex/…` |
| SAH | `units/pd2_dlc_sah/environments/skies/sky_2335_night_moon/…` |

`sky_2335_night_moon` is the notable one — its own config lives under `pd2_dlc_sah`, not
`core`. A mod that hardcodes `core/environments/skies/` will miss it.

---

## The 49 animated environments

See **Tier 3** above for the full list and for what those environments actually carry.

Roughly: **all outdoor levels with a visible sun.** Interior levels bind a sky for
ambient/reflection purposes but carry no sun or flare params — nothing to animate.

Note `env_menu` (main menu) is Tier 3. That is why the mod's skybox was visibly
costing framerate in the menu — the menu environment is one of the most complex in the
game, running the full HDR + DOF + SSAO + bloom + motion-blur stack.

---

## `coresky.lua` — the manager

Payload not decoded (serialized chunk). Identifier table recovered:

```
CoreSky
_name  _params  param  parameter  children
name  value  type  from
Vector3  number  string
interpolate  parse  copy
set_value  set_name  init  class
database_lookup  LightIntensityDB  assert  find
scale  invscale
pairs  tostring  tonumber  math  string
string_to_vector  string_is_good_vector
db_key  value_key
```

Reading that:

- `CoreSky` is a class with a `_params` tree. Each param has `name`, `value`, `type`
  (`Vector3` / `number` / `string`), and optional `children`.
- **`interpolate`** — params can be interpolated. This is the animated-sky primitive.
  A param that interpolates between values over time is a moving value.
- `database_lookup` / `LightIntensityDB` / `db_key` / `value_key` — resolves named
  lighting references. This backs the `intensity="sun"` style strings.
- `scale` / `invscale` — the `params_b` intensity maths.
- `string_to_vector` / `string_is_good_vector` — env values are parsed from strings.

`coresky.lua` is 1,898 bytes of serialized data — small, it is a schema interpreter
rather than logic. `CoreSky` likely takes the same param tree the `.environment` file
carries and exposes it to Lua, which is how `Environment Editor` reads `color0`/`color2`.

---

## How this connects to the existing mod

`mods/skybox_animated/lua/environment_hook.lua` hooks `GameSetupUpdate` and patches
one thing:

```lua
local material = Underlay:material(Idstring("sky"))
Application.set_material_texture(material, Idstring("diffuse_texture"), texture_ids, Idstring("normal"))
```

That swaps the cubemap on the `dome_sky` material. It does **not** touch:

- `underlay` — the environment's own sky binding
- `sky_orientation.rotation` — available in 100% of environments
- `sun_anim` / `flare_anim_x` / `flare_anim_y` — available in 49
- any cloud layer material — `clouds_top`, `clouds_02`, `clouds_02_slow`

So the mod reaches the one layer that cannot animate, and leaves all four layers that
can untouched. That is the whole diagnosis.

---

## Decoding note

`.environment` payloads begin with a plain header, not a magic:

```
00 00 00 00 00 00 00 00 | 12 00 00 00 00 00 00 00 | 12 00 00 00 00 00 00 00
d0 00 00 00 00 00 00 00 | 00 00 00 00 00 00 00 00 | 2f 00 00 00 00 00 00 00
2f 00 00 00 00 00 00 00 | 18 01 00 00 00 00 00 00 | ...
```

Decoded: `0x008` = float pool count (18), `0x018` = float pool offset (208),
`0x028` = string count (47), `0x038` = string record table (280), `0x058` = end of the
string region.

**Recovered from all 225 files:** every key name, every string-valued binding
(`underlay`, `global_texture`, …), the full tag stream, and 2,210 literal float
constants.

**Not recovered:** per-key attribution of the numeric values inside the node/value
block. That block is variable-length per record and mixes float32 with integer fields.
A 40-byte descriptor table inside it has been mapped, but its field semantics are not
resolved. The block also carries the distance-type parameters (fog ranges, cascaded
shadow slice depths), which are not in the float pool.

For exact numbers on those, read them live in-game — the Environment Editor mod
already surfaces several, and `coresky` exposes `interpolate` and `database_lookup`.