# 02 — Sky Material Configs

84 `sky*.material_config` files exist, of which 77 declare `render_template="dome_sky"` and resolve to 40 distinct skies.
All are plain XML and read directly.

---

## The standard sky config

36 of 39 sky configs are byte-for-byte the same shape. Canonical example
(`sky_1345_clear_sky.material_config`):

```xml
<?xml version="1.0" encoding="ISO-8859-1" ?>
<materials>
	<material name="sky" render_template="dome_sky">
		<diffuse_texture file="core/environments/skies/sky_1345_clear_sky/sky_1345_clear_sky_df"/>
		<variable name="params_a" type="vector3" value="1 0.0 1.0"/> <!-- Range, offset, curve -->
		<variable name="params_b" type="vector3" value="0.25 0.5 0"/> <!-- Sky intensity, Sun intensity, Not used -->

		<!-- OLD shit -->
		<variable name="color0" type="vector3" value="1.0 1.0 1.0"/>
		<variable name="color2" type="vector3" value="1.0 1.0 1.0"/>
	</material>
</materials>
```

### Variable reference

| Variable | Type | Meaning | Animatable |
|---|---|---|---|
| `params_a.x` | scalar | **Range** — horizontal gradient spread | No |
| `params_a.y` | scalar | **Offset** — vertical gradient shift | No |
| `params_a.z` | scalar | **Curve** — gradient falloff shape | No |
| `params_b.x` | scalar | **Sky intensity** (brightness) | No |
| `params_b.y` | scalar | **Sun intensity** | No |
| `params_b.z` | scalar | Not used (always `0`) | No |
| `color0` | vector3 | Legacy sky-top colour | No |
| `color2` | vector3 | Legacy sky-bottom colour | No |

The comments are Valve's own, straight from the shipped files.

**There is no `uv_speed`, no `uv_offset`, no scroll parameter on `dome_sky`.**
The gradient is baked per-sky via `params_a`. This is a hard ceiling, not a mod bug.

### What the `Environment Editor` mod exposes

> **Provenance:** the mod itself is **not** in this asset export — there is no `mods/`
> folder in `aireportpd2/`. The snippet below is from community description of that
> mod, not verified against a file here. Treat it as a lead, not a finding. Everything
> else in this document was read directly from the export.

`mods/environment editor/env.lua` reads this exact material and finds only:

```lua
local underlay_mat = Underlay:material(Idstring("sky"))
underlay_mat:get_variable(Idstring("color0"))        -- sky top
underlay_mat:get_variable(Idstring("color0_scale"))
underlay_mat:get_variable(Idstring("color2"))        -- sky bottom
underlay_mat:get_variable(Idstring("color2_scale"))
```

That is the complete live variable set for the sky material. Independent
confirmation from a third source.

---

## Full `params_a` / `params_b` table

| Sky | params_a (range, offset, curve) | params_b (sky int, sun int, -) |
|---|---|---|
| `default` | `0.9 0.5 2.0` | `0.15 1 0` |
| `sky_0200_night_moon_stars` | `1 0.05 1.2` | `0.5 0.5 0` |
| `sky_0902_overcast` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_0902_overcast_dark` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_0927_whispy_clouds` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_1008_cloudy` | `1.0 0.0 0.95` | `0.25 1 0` |
| `sky_1044_overcast_sun` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_1224_clear_sky` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_1313_cloudy` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_1313_cloudy_dark` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_1345_clear_sky` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_1345_clear_sky_mountain_01` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_1530_low_sun_clouds` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_1830_low_sun_clouds` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_1846_low_sun_nice_clouds` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_1930_sunset_heavy_clouds` | `1 0.1 0.9` | `0.25 0.5 0` |
| `sky_1930_twillight` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_1931_low_sun` | `1.0 0.0 1.0` | `0.25 1 0` |
| `sky_1945_sunset` | `1 0.0 1.0` | `0.25 0.5 0` |
| **`sky_1945_sunset_clouds`** | **`0.2 0.0 0.1`** | **`0.25 0.5 0`** |
| `sky_2000_twilight_mad` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_2003_dusk_blue` | `1.0 -0.09 1.5` | `0.25 1 0` |
| `sky_2003_dusk_blue_high_color_scale` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_2003_sunrise` | `1.0 -0.09 1.5` | `0.25 1 0` |
| `sky_2100_moon` | `1 -0.09 1.5` | `0.25 0.5 0` |
| `sky_2335_night_moon` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_277_dusk` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_279_dusk` | `1 0.0 1.0` | `0.1 0.5 0` |
| `sky_city_clear` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_city_clear_high` | `1 0.0 1.0` | `0.25 0.5 0` |
| **`sky_cloudy_blue`** | **`0.9 0.5 2.0`** | **`0.15 1 0`** |
| `sky_corp_deep_blue` | `1 0.0 1.0` | `0.1 0.5 0` |
| `sky_csgo_de_bank_cs15_daylight02` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_dah_night` | `1 -0.09 1.5` | `0.25 0.5 0` |
| `sky_pent_dusk_0065` | `1 0.0 1.0` | `0.1 0.5 0` |
| `sky_rvd_la_afternoon` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_v2_030_sun_low` | `1 0.0 1.0` | `0.25 0.5 0` |
| `sky_vit_thunderstorm` | `1 0.0 1.0` | `0.25 0.5 0` |

### Observations

- **`params_b.y` = 1** on the "low sun" skies (`sky_1008_cloudy`, `sky_1931_low_sun`,
  `sky_2003_dusk_blue`, `sky_2003_sunrise`, `sky_cloudy_blue`) — these are the ones with
  a visible sun disc. Sun intensity `1` vs `0.5`.
- **`params_a.z` (curve) > 1** on twilight/night skies (`1.2`, `1.5`) — steepens the
  gradient so the horizon band compresses. These read as dusk.
- **`params_a.y` (offset)** goes negative (`-0.09`) on the same twilight set —
  pushes the gradient band up the dome.
- `sky_1945_sunset_clouds` has a radical `params_a = 0.2 0.0 0.1` because its dome is
  mostly covered by cloud layers. The dome is a backdrop, not the subject.
- `sky_cloudy_blue` is the outlier: `params_a = 0.9 0.5 2.0`, `params_b.x = 0.15`.

### Non-`dome_sky` configs

Three recovered sky-named configs are **not** skies:

| File | render_template |
|---|---|
| `skydome_quick_diamond.material_config` | `generic:DIFFUSE_TEXTURE:RL_BACKDROP:SELF_ILLUMINATION` |
| `skylight_broken_large.material_config` | `generic:DIFFUSE_TEXTURE:*` (prop) |
| `skyscraper_construction.material_config` | `generic:DIFFUSE_TEXTURE:*` (prop) |

---

## The animated sky: `sky_1945_sunset_clouds`

**This is the only sky in PAYDAY 2 with a layered, scrolling cloud setup.** It is
also the reference implementation for an animated skybox.

```xml
<?xml version="1.0" encoding="ISO-8859-1" ?>
<materials>
	<material name="sky" render_template="dome_sky">
		<diffuse_texture file="core/environments/skies/sky_1945_sunset_clouds/sky_1945_sunset_clouds_df"/>
		<variable name="params_a" type="vector3" value="0.2 0.0 0.1"/>
		<variable name="params_b" type="vector3" value="0.25 0.5 0"/>
		<variable name="color0" type="vector3" value="1.0 1.0 1.0"/>
		<variable name="color2" type="vector3" value="1.0 1.0 1.0"/>
	</material>
    <material name="clouds_top" render_template="effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR" version="2">
        <diffuse_texture file="core/environments/skies/sky_1945_sunset_clouds/top_clouds_df"/>
        <variable value="sun" type="scalar" name="intensity"/>
        <variable value="0 -0.0060000000521541 0" type="vector3" name="uv0_speed"/>
    </material>
    <material name="clouds_02" render_template="effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR" version="2">
        <diffuse_texture file="core/environments/skies/sky_1945_sunset_clouds/stormy_clouds_df"/>
        <variable value="reddot" type="scalar" name="intensity"/>
        <variable value="0.0049999998882413 0 0" type="vector3" name="uv0_speed"/>
    </material>
    <material name="clouds_02_slow" render_template="effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR" version="2">
        <diffuse_texture file="core/environments/skies/sky_1945_sunset_clouds/stormy_clouds_df"/>
        <variable value="reddot" type="scalar" name="intensity"/>
        <variable value="0.0029999988619238 0 0" type="vector3" name="uv0_speed"/>
    </material>
</materials>
```

### The mechanism

| Part | Role |
|---|---|
| `DIFFUSE0_UVANIM` in `render_template` | Enables UV animation on the diffuse slot. **Without this token, `uv0_speed` is inert.** |
| `<variable name="uv0_speed" type="vector3">` | Scroll rate. `.x` = U, `.y` = V, `.z` unused |
| `<variable name="intensity" type="scalar">` | Named **lighting-parameter reference** — `sun` / `reddot` / `monitor` / `none` |
| `name="clouds_02_slow"` | A *separate material*, same texture, different speed. Parallax by differential scroll |
| `VERTEX_COLOR` | Tints the layer by mesh vertex colour |

The three layers scroll at `-0.006` V, `+0.005` U, `+0.003` U — different axes, different
rates. `clouds_02` and `clouds_02_slow` share one texture and separate purely by speed.
That parallax is what sells it as motion.

`intensity="sun"` / `"reddot"` / `"monitor"` are not arbitrary strings — they are
references into a light-intensity database. `core/lib/managers/coresky.lua` exposes
`LightIntensityDB`, `database_lookup`, `interpolate`, `scale` / `invscale`. Clouds are
lit by whatever the environment's sun is doing.

---

## Every `uv0_speed` in the export

Only 4 configs in the entire game use UV animation. Full list:

| Config | Material | `uv0_speed` (u, v, —) | Motion |
|---|---|---|---|
| `sky_1945_sunset_clouds` | `clouds_top` | `0  -0.006  0` | vertical drift down |
| `sky_1945_sunset_clouds` | `clouds_02` | `0.005  0  0` | horizontal right, medium |
| `sky_1945_sunset_clouds` | `clouds_02_slow` | `0.003  0  0` | horizontal right, slow (parallax) |
| `vit_stormclouds` | — | `0.001  0  0` | very slow horizontal |
| `vit_stormclouds` | — | `0  0.01  0` | vertical, 10× faster than clouds_top |
| `lxy_bdrop_skyline` | — | `0.02  0  0` | fast horizontal |
| `lxy_bdrop_skyline` | — | `0  0.5  0` | very fast vertical |
| `cas_skylight_barrier_hack` | — | `-1.5  ~0  0` | **very fast** left (hazard scanline) |

Reference speeds for a believable sky:

- `0.001` — barely perceptible drift
- `0.003 – 0.005` — good cloud drift
- `0.01 – 0.02` — obvious scroll
- `0.5` and above — not weather, this is a UV conveyor belt

Note `cas_skylight_barrier_hack` uses `-1.5`. Values in this game are **not**
normalised. Nothing stops you using large values; the shader just adds them to the
UV each frame and the texture must have `wrap = repeat` or it will seam.

---

## Render templates across the whole export

| Count | Template | UV anim |
|---|---|---|
| 70 | `dome_sky` | no |
| 24 | `generic:DIFFUSE_TEXTURE` | no |
| 12 | `effect:BLEND_ADD:DIFFUSE0_TEXTURE` | no |
| 11 | `generic:DIFFUSE_TEXTURE:SELF_ILLUMINATION:SELF_ILLUMINATION_BLOOM` | no |
| 10 | `shadow_caster_only` | no |
| **7** | **`effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR`** | **yes** |
| 3 | `effect:BLEND_ADD:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM` | **yes** |
| 1 | `effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM` | **yes** |
| 1 | `generic:DIFFUSE_TEXTURE:SELF_ILLUMINATION:SELF_ILLUMINATION_BLOOM:SELF_ILLUMINATION_UVANIM` | **yes** (il slot) |

**11 of 113 render templates support UV animation. `dome_sky` is not one of them.**

Note the two families: `DIFFUSE0_UVANIM` animates slot 0, `SELF_ILLUMINATION_UVANIM`
animates the emissive slot. For sky work you want `DIFFUSE0_UVANIM`.

---

## Cross-reference: the weapon scrolling mod

`mods/Scrolling Textures` already solves this problem for weapons, and its approach
transfers directly to the sky.

Its generated configs (`assets/units/mods/scrolling_textures/materials/*.material_config`):

```xml
<materials version="3" group="weapon_scout">
	<material name="mat_rail_adapter" render_template="generic:DEPTH_SCALING:DIFFUSE_TEXTURE:DIFFUSE_UVANIM:SELF_ILLUMINATION:SELF_ILLUMINATION_BLOOM:SELF_ILLUMINATION_UVANIM" version="2" unique="true">
		<diffuse_texture file="units/mods/scrolling_textures/textures/default_df" />
		<self_illumination_texture file="units/mods/scrolling_textures/textures/default_il" />
		<variable name="uv_speed" value="0.1 0 0" type="vector3" />
		<variable name="il_bloom" value="1.0" type="scalar" />
		<variable name="il_multiplier" value="5" type="scalar" />
	</material>
</materials>
```

Differences worth noting:

| | Sky (`dome_sky`) | Scrolling Textures |
|---|---|---|
| Template flag | none | `DIFFUSE_UVANIM` |
| Variable name | — | `uv_speed` |
| Slot naming | `diffuse_texture` | `diffuse_texture` |
| `unique` attr | absent | `unique="true"` |
| `<materials>` attrs | none | `version="3" group="..."` |
| Speed range | n/a | `0.1` |

**`uv_speed` vs `uv0_speed`.** Both spellings appear in the codebase. The Scrolling
Textures mod writes `uv_speed`; the shipped sky/cloud configs use `uv0_speed`. The
`UVANIM` token in the render template is what the shader actually binds to — the
variable name is the slot index. Use `uv0_speed` for slot 0 to match the shipped sky
configs, or `uv_speed` to match the mod's convention. Worth testing both in-game.

`unique="true"` is significant: it tells the engine this config defines its own unique
material instance rather than referencing a shared one. The shipped sky configs omit
it because they are the originals. If you override a sky config you likely want it.

### How that mod loads and reads configs

Runtime read of a vanilla config, straight from
`mods/Scrolling Textures/lua/generator/configs.lua`:

```lua
local t = Idstring("material_config")
local n = Idstring(path)
if not DB:has(t, n) then return nil end
local f = DB:open(t, n)
local data = f:read()
f:close()
```

So configs are addressed as `DB:open("material_config", "<path>")`. The sky config path
would be `core/environments/skies/<sky_name>/<sky_name>`.

Configs are discovered by walking `tweak_data.weapon.factory.parts[].material_config`.
There is no equivalent tweak table for skies — the sky config path is reached from the
environment's `underlay` texture path by convention (`<dir>/<basename>`). This is why
finding these configs took crate spelunking.
