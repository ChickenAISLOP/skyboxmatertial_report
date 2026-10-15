# 06 — Skybox Feature Reference

Spec sheet for every skybox feature in PAYDAY 2, written in the same style as a
`material_config`. Everything below is read directly from the exported assets.

---

## The sky material spec

This is the complete feature surface of the stock sky, expressed as a material:

```xml
<material name="sky" render_template="dome_sky" version="2">
  <diffuse_texture file="core/environments/skies/<sky_name>/<sky_name>_df"/>

  <!-- Gradient shaping. Non-animatable. -->
  <variable name="params_a" type="vector3" value="1 0.0 1.0"/>
  <!--   x = Range    horizontal gradient spread -->
  <!--   y = Offset   vertical gradient shift -->
  <!--   z = Curve    gradient falloff shape -->

  <variable name="params_b" type="vector3" value="0.25 0.5 0"/>
  <!--   x = Sky intensity   0.1 .. 0.5 -->
  <!--   y = Sun intensity   0.5 (none) or 1 (visible sun disc) -->
  <!--   z = unused, always 0 -->

  <!-- Legacy. Marked "OLD shit" by Valve. -->
  <variable name="color0" type="vector3" value="1.0 1.0 1.0"/>   <!-- sky top -->
  <variable name="color2" type="vector3" value="1.0 1.0 1.0"/>   <!-- sky bottom -->
</material>
```

**Six variables. None of them animate.** `dome_sky` has no `uv_speed`, no scroll
parameter, no rotation handle. This is the hard ceiling.

---

## Feature matrix

| # | Feature | Key / mechanism | Animatable | Coverage |
|---|---|---|---|---|
| 1 | **Dome rotation** | `sky_orientation.rotation` | **Yes** | **225 / 225 envs** |
| 2 | **Cloud scroll** | `DIFFUSE0_UVANIM` + `uv0_speed` | **Yes** | 1 sky vanilla, extensible |
| 3 | **Sun animation** | `sun_anim`, `sun_anim_x` | **Yes** | 49 / 225 envs |
| 4 | **Lens flare animation** | `flare_anim_x`, `flare_anim_y` | **Yes** | 49 / 225 envs |
| 5 | Sky brightness | `params_b.x` | No | 34 skies |
| 6 | Sun disc on/off | `params_b.y` = 0.5 / 1 | No | 34 skies |
| 7 | Gradient spread | `params_a.x` | No | 34 skies |
| 8 | Gradient offset | `params_a.y` | No | 34 skies |
| 9 | Gradient curve | `params_a.z` | No | 34 skies |
| 10 | Sky top colour | `color0` | No | 34 skies |
| 11 | Sky bottom colour | `color2` | No | 34 skies |
| 12 | Sky cubemap swap | `underlay` | n/a | 223 / 225 recovered |
| 13 | Sun colour (both sides) | `color_sun`, `color_opposite_sun` | Tier 3 | 49 envs |
| 14 | Volumetric sun rays | `sun_ray_color`, `sun_ray_color_scale` | Tier 3 | 49 envs |
| 15 | Auto-exposure | `tone_mapping`, `middle_grey`, `white_luminance` | Tier 3 | 49 envs |
| 16 | Depth of field | `near/far_focus_distance_min/max` | Tier 3 | 49 envs |
| 17 | Bloom | `bloom_apply`, `bloom_brightpass` | Tier 3 | 49 envs |
| 18 | SSAO | `ssao`, `global_ssao`, `local_ssao` | Tier 3 | 49 envs |
| 19 | Motion blur | `uv_velocity_rg_mask`, `uv_velocity_b_mask` | Tier 3 | 49 envs |
| 20 | God rays | `fog_sun_scatter_color`, `fog_curve` | Tier 3 | 49 envs |
| 21 | Cloud overlay | `cloud_overlay` | Tier 3 | 49 envs |
| 22 | Sky reflection | `sky_reflection_top/bottom_color(_scale)` | Tier 3 | 49 envs |

Features 1–4 are the only animatable ones. 1 works everywhere; 2 needs geometry;
3–4 need a Tier 3 environment.

---

## Per-sky feature table

All 35 sky material configs. `Mats` = material count, `UV` = scrolling layers,
`Envs` = environments binding it.

| Sky | Mats | `params_a` range,offset,curve | `params_b` sky,sun | UV | Envs |
|---|---|---|---|---|---|
| `default` | 1 | `0.9 0.5 2.0` | `0.15 1` | 0 | 16 |
| `sky_0200_night_moon_stars` | 1 | `1 0.05 1.2` | `0.5 0.5` | 0 | 18 |
| `sky_0902_overcast` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 9 |
| `sky_0902_overcast_dark` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 1 |
| `sky_0927_whispy_clouds` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 2 |
| `sky_1008_cloudy` | 1 | `1.0 0.0 0.95` | `0.25 1` | 0 | 4 |
| `sky_1044_overcast_sun` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | **0** |
| `sky_1224_clear_sky` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 20 |
| `sky_1313_cloudy` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 4 |
| `sky_1313_cloudy_dark` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 10 |
| `sky_1345_clear_sky` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | **0** |
| `sky_1345_clear_sky_mountain_01` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 1 |
| `sky_1530_low_sun_clouds` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 6 |
| `sky_1830_low_sun_clouds` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 2 |
| `sky_1846_low_sun_nice_clouds` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | **0** |
| `sky_1930_sunset_heavy_clouds` | 1 | `1 0.1 0.9` | `0.25 0.5` | 0 | 2 |
| `sky_1930_twillight` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 2 |
| `sky_1931_low_sun` | 1 | `1.0 0.0 1.0` | `0.25 1` | 0 | 2 |
| `sky_1945_sunset` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 3 |
| **`sky_1945_sunset_clouds`** | **4** | `0.2 0.0 0.1` | `0.25 0.5` | **3** | 3 |
| `sky_2000_twilight_mad` | 2 | `1 0.0 1.0` | `0.25 0.5` | 0 | 3 |
| `sky_2003_dusk_blue` | 1 | `1.0 -0.09 1.5` | `0.25 1` | 0 | 28 |
| `sky_2003_dusk_blue_high_color_scale` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | **0** |
| `sky_2003_sunrise` | 1 | `1.0 -0.09 1.5` | `0.25 1` | 0 | 2 |
| `sky_2100_moon` | 1 | `1 -0.09 1.5` | `0.25 0.5` | 0 | 16 |
| `sky_2335_night_moon` | 2 | `1 0.0 1.0` | `0.25 0.5` | 0 | **45** |
| `sky_277_dusk` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 2 |
| `sky_279_dusk` | 1 | `1 0.0 1.0` | `0.1 0.5` | 0 | 2 |
| `sky_city_clear` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 1 |
| `sky_city_clear_high` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 2 |
| `sky_cloudy_blue` | 1 | `0.9 0.5 2.0` | `0.15 1` | 0 | **0** |
| `sky_csgo_de_bank_cs15_daylight02` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 1 |
| `sky_dah_night` | 1 | `1 -0.09 1.5` | `0.25 0.5` | 0 | 2 |
| `sky_pent_dusk_0065` | 1 | `1 0.0 1.0` | `0.1 0.5` | 0 | 10 |
| `sky_rvd_la_afternoon` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | **0** |
| `sky_v2_030_sun_low` | 1 | `1 0.0 1.0` | `0.25 0.5` | 0 | 1 |
| `skydome_quick_diamond` | 1 | — | — | 0 | n/a |

---

## Reading the parameter patterns

### `params_b.y` — sun disc

`1` = visible sun disc, `0.5` = no sun:

```
sky_1008_cloudy   sky_1931_low_sun   sky_2003_dusk_blue
sky_2003_sunrise   sky_cloudy_blue    default
```

### `params_a.z` — gradient curve

`> 1` steepens the gradient so the horizon band compresses. These are the twilight
and night skies:

```
1.2   sky_0200_night_moon_stars
1.5   sky_2003_dusk_blue   sky_2003_sunrise   sky_2100_moon   sky_dah_night
2.0   default   sky_cloudy_blue
```

`params_a.y` goes negative (`-0.09`) on the same twilight set — it pushes the
gradient band up the dome.

### Outliers

| Sky | Why it's odd |
|---|---|
| `sky_1945_sunset_clouds` | `params_a = 0.2 0.0 0.1` — the dome is a backdrop; the clouds are the subject |
| `sky_cloudy_blue` | `params_a = 0.9 0.5 2.0`, `params_b.x = 0.15` — dimmest and steepest |
| `default` | Same shape as `sky_cloudy_blue` — it is the fallback sky |
| `skydome_quick_diamond` | No `dome_sky`. Interior backdrop: `generic:DIFFUSE_TEXTURE:RL_BACKDROP:SELF_ILLUMINATION` |

---

## The one animated sky

`sky_1945_sunset_clouds` is the only sky in the game with layered, scrolling clouds.
Four materials:

```xml
<material name="sky" render_template="dome_sky">
  <diffuse_texture file="core/environments/skies/sky_1945_sunset_clouds/sky_1945_sunset_clouds_df"/>
  <variable name="params_a" type="vector3" value="0.2 0.0 0.1"/>
  <variable name="params_b" type="vector3" value="0.25 0.5 0"/>
</material>

<material name="clouds_top" render_template="effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR" version="2">
  <diffuse_texture file=".../top_clouds_df"/>
  <variable value="sun"     type="scalar"  name="intensity"/>
  <variable value="0 -0.006 0" type="vector3" name="uv0_speed"/>   <!-- vertical, down -->
</material>

<material name="clouds_02" render_template="effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR" version="2">
  <diffuse_texture file=".../stormy_clouds_df"/>
  <variable value="reddot"  type="scalar"  name="intensity"/>
  <variable value="0.005 0 0" type="vector3" name="uv0_speed"/>    <!-- horizontal, medium -->
</material>

<material name="clouds_02_slow" render_template="effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR" version="2">
  <diffuse_texture file=".../stormy_clouds_df"/>                    <!-- same texture -->
  <variable value="reddot"  type="scalar"  name="intensity"/>
  <variable value="0.003 0 0" type="vector3" name="uv0_speed"/>    <!-- horizontal, slow -->
</material>
```

`clouds_02` and `clouds_02_slow` use the **same texture at different speeds**. That
parallax is the whole trick — identical imagery that visibly separates over time.

---

## Every `uv0_speed` in the game

Only four configs use UV animation anywhere.

| Config | Material | Value (u, v, —) | Reads as |
|---|---|---|---|
| `sky_1945_sunset_clouds` | `clouds_top` | `0 -0.006 0` | vertical drift |
| `sky_1945_sunset_clouds` | `clouds_02` | `0.005 0 0` | horizontal drift |
| `sky_1945_sunset_clouds` | `clouds_02_slow` | `0.003 0 0` | horizontal parallax |
| `vit_stormclouds` | — | `0.001 0 0` | very slow |
| `vit_stormclouds` | — | `0 0.01 0` | 10× faster vertical |
| `lxy_bdrop_skyline` | — | `0.02 0 0` | fast |
| `lxy_bdrop_skyline` | — | `0 0.5 0` | conveyor belt |
| `cas_skylight_barrier_hack` | — | `-1.5 ~0 0` | hazard scanline |

**Speed reference:**

| Value | Effect |
|---|---|
| `0.001` | barely perceptible |
| `0.003 – 0.005` | good cloud drift |
| `0.01 – 0.02` | obvious scroll |
| `0.5` and up | not weather |
| `-1.5` | a hazard scanline, shipped in the game |

Values are **not normalised** — `-1.5` is legal and ships. Two rules if you roll
your own: keep the texture `wrap = repeat`, and in Tier 3 environments expect motion
blur from `uv_velocity_*_mask`.

---

## Environment tiers

| Tier | Count | Sun model | Animatable |
|---|---|---|---|
| 1 — Legacy | **174** | none | rotation only |
| 2 — Post stack, static | **2** | yes | rotation only |
| 3 — Post stack + anim | **49** | yes | rotation + sun + 8 flares |

Full detail in `03_environment_schema.md`. Short version: Tier 3 is the modern render
pipeline (tone mapping, DOF, SSAO, bloom, motion blur), and sun animation ships inside
it. `env_menu` is Tier 3 — which is why per-frame sky work in the menu is the worst
case for framerate.

---

## Skies bound by zero environments

Safe to override without breaking any level:

```
sky_1044_overcast_sun
sky_1345_clear_sky
sky_1846_low_sun_nice_clouds
sky_2003_dusk_blue_high_color_scale
sky_cloudy_blue
sky_rvd_la_afternoon
```