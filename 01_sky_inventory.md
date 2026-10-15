# 01 — Sky Inventory

All sky assets live under `core/environments/skies/<sky_name>/`.

Each folder contains **4 files minimum**:

| File | Role |
|---|---|
| `<name>.model` | Dome mesh |
| `<name>.scene` | Scene description |
| `<name>.material_config` | Material definition (the `sky` material) |
| `<name>_df.dds` or `<name>.dds` | Diffuse cubemap |

Some folders carry extra cloud/moon textures (see `sky_1945_sunset_clouds`).

---

## The 25 requested skies

All 25 exist. "envs" = number of `.environment` files in vanilla that bind this sky.

| # | Sky | envs | Notes |
|---|---|---|---|
| 1 | `sky_1345_clear_sky` | **0** | Not used by any vanilla environment |
| 2 | `sky_city_clear` | 1 | |
| 3 | `sky_1930_sunset_heavy_clouds` | 2 | |
| 4 | `sky_1830_low_sun_clouds` | 2 | |
| 5 | `sky_1846_low_sun_nice_clouds` | **0** | Not used by vanilla |
| 6 | `sky_1930_twillight` | 2 | Valve typo: "twillight", not "twilight" |
| 7 | `sky_0200_night_moon_stars` | 18 | |
| 8 | `sky_2335_night_moon` | **46** | Most-used sky in the game |
| 9 | `sky_2100_moon` | 16 | |
| 10 | `sky_1008_cloudy` | 4 | |
| 11 | `sky_1313_cloudy` | 4 | |
| 12 | `sky_cloudy_blue` | **0** | Not used by vanilla |
| 13 | `sky_0927_whispy_clouds` | 2 | |
| 14 | `sky_0902_overcast` | 9 | |
| 15 | `sky_0902_overcast_dark` | 1 | |
| 16 | `sky_1044_overcast_sun` | **0** | Not used by vanilla |
| 17 | `sky_2003_sunrise` | 2 | |
| 18 | `sky_2003_dusk_blue` | 28 | |
| 19 | `sky_1945_sunset` | 3 | |
| 20 | `sky_1530_low_sun_clouds` | 6 | |
| 21 | `sky_1931_low_sun` | 2 | |
| 22 | `sky_1224_clear_sky` | 20 | |
| 23 | `sky_1345_clear_sky_mountain_01` | 1 | |
| 24 | `sky_city_clear_high` | 2 | |
| 25 | `sky_csgo_de_bank_cs15_daylight02` | 1 | From CS:GO, `de_bank` CS15 content |

**4 of the 25 are dead assets** — they ship in the game but no environment references
them: `sky_1345_clear_sky`, `sky_1846_low_sun_nice_clouds`, `sky_cloudy_blue`,
`sky_1044_overcast_sun`. They are safe to override; nothing vanilla depends on them.

---

## Additional skies present but not requested

| Sky | envs | Notes |
|---|---|---|
| `default` | 16 | Fallback sky |
| `sky_1313_cloudy_dark` | 10 | |
| `sky_1945_sunset_clouds` | 3 | **The animated one** — see `02_sky_material_configs.md` |
| `sky_2000_twilight_mad` | 3 | |
| `sky_2003_dusk_blue_high_color_scale` | 0 | Not used by vanilla |
| `sky_277_dusk` | 2 | |
| `sky_279_dusk` | 2 | |
| `sky_corp_deep_blue` | 3 | `units/pd2_dlc_corp/cubemaps/` |
| `sky_dah_night` | 2 | |
| `sky_pent_dusk_0065` | 9 | `units/pd2_dlc_pent/architecture/cubemaps/` |
| `sky_rvd_la_afternoon` | 0 | Not used by vanilla |
| `sky_v2_030_sun_low` | 1 | |
| `sky_1945_sunset_clouds_mex` | 1 | `units/pd2_dlc_mex/environments/` |

**33 named skies + `default` = 34 folders total.**

---

## Full asset paths

Canonical form:

```
core/environments/skies/<sky_name>/<sky_name>.material_config
core/environments/skies/<sky_name>/<sky_name>.model
core/environments/skies/<sky_name>/<sky_name>.scene
core/environments/skies/<sky_name>/<sky_name>_df.dds
```

### Naming is inconsistent — check before you override

Three different naming conventions exist in the same folder tree:

| Pattern | Example | Folders |
|---|---|---|
| `<name>.dds` | `sky_0200_night_moon_stars.dds` | most skies |
| `<name>_df.dds` | `sky_1345_clear_sky_df.dds` | newer skies |
| unrelated name | `dah_sky_night_df.dds` in `sky_dah_night/` | `sky_dah_night` |

The **material config** is always `<name>.material_config` and always points at the
`_df` variant:

```xml
<diffuse_texture file="core/environments/skies/sky_1345_clear_sky/sky_1345_clear_sky_df"/>
```

So `_df.dds` is the file that matters even when a plain `.dds` also exists.

### Known content quirks

- `sky_1313_cloudy_dark/` contains `sky_1313_cloudy.material_config` — **wrong name,
  copies the non-dark config.** Its actual textures are `sky_1313_cloudy_dark_df.dds`
  and `sky_1313_cloudy_darker_df.dds`. This is a Valve bug; do not use it as a
  reference for how dark variants are wired.
- `sky_2335_night_moon/` and `sky_2000_twilight_mad/` carry an extra `moon_df.dds`
  used by a second `mat_moon` material.
- `sky_1945_sunset_clouds/` has **13 files** — 5 cloud layers plus lit variants. It is
  the only sky in the game with a layered cloud setup.
- `sky_1345_clear_sky_mountain_01` reads as "mountain_01" but is a flat cubemap; the
  mountain is painted into the texture.

---

## Texture sizes (from `Desktop/skies` working copy)

The user already has these extracted to `C:\Users\meow\Desktop\skies\` as
SuperComposedTexture (`.texture`) files:

| Size | Count | Meaning |
|---|---|---|
| 1,048,704 B | 10 | small cube (likely 256px, no `_df`) |
| 2,097,280 B | 4 | medium |
| 2,796,344 B | 7 | large cube (likely 512px) |
| 5,592,560 B | 2 | 2× large — `sky_1945_sunset`, `sky_2003_dusk_blue` |

Note `sky_city_clear_high` is **1,329 bytes** in that working copy — a stub or failed
extract. The in-game asset is fine; re-extract it if it renders blank.

---

## Related non-sky assets worth knowing

```
core/textures/skydome_cube_test
units/payday2/architecture/skydomes/skydome_quick_diamond   (+ _df, sky_il_df)
units/payday2/cubemaps/cubemap_sky
environments/cubemaps/cubemap_sky
core/lib/managers/coresky.lua                                ← sky manager
core/lib/managers/viewport/interfaces/coreenvironmentskyorientationinterface
units/pd2_dlc2/csgo_models/props/de_vertigo/de_vertigo_skybox01_part_02
units/pd2_dlc2/csgo_models/props_buildings/watertower_001a_skybox
```

`skydome_quick_diamond.material_config` is the **only** sky-ish config that does *not*
use `dome_sky` — it is an interior backdrop:

```xml
<material name="sky" render_template="generic:DIFFUSE_TEXTURE:RL_BACKDROP:SELF_ILLUMINATION" version="2">
  <diffuse_texture file="units/payday2/architecture/skydomes/skydome_quick_diamond_df"/>
  <self_illumination_texture file="units/payday2/architecture/skydomes/sky_il_df"/>
  <variable value="none" type="scalar" name="il_multiplier"/>
</material>
```

Still named `sky`, still no UV animation.