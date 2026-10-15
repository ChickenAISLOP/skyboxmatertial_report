# 09 — Environment Authoring with BeardLib

How the sky is actually animated in PAYDAY 2. This supersedes the conclusion in
`08` that the sky cannot be animated, which was too strong.

Everything here is from the modding toolchain, not from the binary export.

---

## The correction

`08` concluded:

> **There is no Lua-facing setter for `sky_orientation/rotation`.** ... The dome
> cannot be rotated or scrolled from a Lua mod.

The first half is correct and was verified by probe. The second half does not follow.
Rotation is **authorable in the environment file**, and two further runtime animation
surfaces exist that the binary export never exposed.

| Route | Verified how |
|---|---|
| `sky_orientation/rotation` as a file parameter | present in all 25 Day & Night XML files and in the BeardLib template |
| Whole-environment swap at runtime | `managers.worlddefinition:_set_environment()` |
| Colour grading elements | `EditorEnvironment` in BeardLib-Editor |

---

## BeardLib-Editor

[diesel-modding/BeardLib-Editor](https://github.com/diesel-modding/BeardLib-Editor)

> "a tool that allows you to edit and create things like maps & environments"

Install: SuperBLT + BeardLib, unzip into `mods/`, launch, accept the prompt. Runs
in-game, no separate executable. There are no releases — it is source that the game
loads.

Relevant files:

```
Classes/Map/Layers/EnvironmentLayerEditor.lua
Classes/Map/Elements/environmentelement.lua
Classes/Map/Elements/environmentoperatorelement.lua
Classes/Map/Tools/EnvironmentToolEditor.lua
Hooks/EnvironmentManager.lua
Templates/Instance/environments/default.environment
Tools/cubemap_light.bat
Tools/cubemap_light_adv.bat
```

---

## Where `CoreEnvironmentManager` actually lives

The runtime probe reported `CoreSky`, `EnvironmentHandler` and `EnvironmentManager`
as absent. They are not globals — they are modules:

```lua
core:module("CoreEnvironmentManager")
core:import("CoreClass")
core:import("CoreEnvironmentHandler")
core:import("CoreEnvironmentFeeder")
```

That import block is the whole missing link. The classes are reachable through the
`core:import` system, not through `_G`.

---

## Full key paths

`Hooks/EnvironmentManager.lua` carries a complete list. Several paths were flattened
by the binary recovery in `03`, which recovered only the leaf name:

```xml
<underlay_effect>
  <sky><param key="color0" .../><param key="color2" .../></sky>
  <sky_top><param key="sky_intensity" .../></sky_top>
  <sky_bottom><param key="sky_intensity" .../></sky_bottom>
  <sun><param key="sun_color" .../><param key="sun_color_scale" .../></sun>
  <cloud_overlay>
    <param key="color_sun" .../>
    <param key="color_sun_scale" .../>
    <param key="color_opposite_sun" .../>
    <param key="color_opposite_sun_scale" .../>
    <param key="alpha_scale_sun" .../>
    <param key="alpha_scale_opposite_sun" .../>
    <param key="uv_velocity_rg_mask" .../>
    <param key="uv_velocity_b_mask" .../>
    <param key="uv_scale_b_mask" .../>
  </cloud_overlay>
</underlay_effect>
```

**`underlay_effect/cloud_overlay/*` is the node the scrolling-cloud shader reads.**
The shader uniforms recovered in `08` (`ref_uv_velocity_rg_mask`, `ref_color_sun`,
`ref_alpha_scale_sun`, `ref_time`) map onto these exactly. The binary scan reported
them as bare `uv_velocity_rg_mask` because it read leaf names only.

Also present, never seen in the export:

```
underlay_effect/sky/color1        underlay_effect/sky/color1_scale
others/global_world_overlay_texture
others/global_world_overlay_mask_texture
others/sky_texture
post_effect/bloom_combine_post_processor/bloom_combine/bloom_lense/bloom_blur_size
```

`color1` exists as a real key path. `variable_exists` returned false for it on
`modders_devmap` because that environment does not set it — the shader input is
authorable after all, just not present by default.

---

## Colour grading: a runtime surface the export never showed

`Classes/Map/Elements/environmentelement.lua` defines `ElementEnvironment` with:

| Control | Range | Effect |
|---|---|---|
| `color_grading` | `none`, `color_off`, `color_payday`, `color_heat`, `color_nice`, `color_sin`, `color_bhd`, `color_xgen`, `color_xxxgen`, `color_matrix` | grade preset |
| `chromatic_amount` | float, `-1` = off | chromatic aberration |
| `brightness` | float, `-1` = off | exposure |
| `contrast` | float, `-1` = off | contrast |
| `min_amount` / `max_amount` | `1` to `5` | random range |
| `random` | bool | randomise per use |

`min_amount`, `max_amount` and `random` together mean a level can get a randomised
grade on load. That is animation-adjacent and entirely absent from the 225 decoded
environments.

---

## The environment XML schema

Custom XML, the same format BeardLib compiles at load. Vanilla `.environment` files
are the compiled binary form; mods can ship either.

```xml
<environment>
  <metadata/>
  <data>
    <sky_orientation>
      <param key="rotation" value="0"/>
    </sky_orientation>
    <others>
      <param key="underlay"      value="core/environments/skies/sky_2003_dusk_blue/sky_2003_dusk_blue"/>
      <param key="global_texture" value="environments/cubemaps/cubemap_bank_01"/>
      <param key="sun_ray_color"  value="0.8509804 0.21176471 0"/>
    </others>
    <post_effect>
      <deferred><deferred_lighting><apply_ambient>
        <param key="sky_top_color"  value="0.19607843 0.34509805 0.6509804"/>
        <param key="sky_bottom_color" value="0 0 0"/>
        <param key="fog_min_range"  value="0"/>
        <!-- ... -->
      </apply_ambient></deferred_lighting></deferred>
      <shadow_processor><shadow_rendering><shadow_modifier>
        <param key="shadow_slice_depths" value="1301 3034 10000"/>
      </shadow_modifier></shadow_rendering></shadow_processor>
    </post_effect>
    <underlay_effect><sky>
      <param key="color0"       value="0.8588236 0.80392164 1"/>
      <param key="color0_scale" value="0.2"/>
      <param key="color2"       value="0.6 0.30588236 0.18039216"/>
      <param key="color2_scale" value="1.667"/>
    </sky></underlay_effect>
  </data>
</environment>
```

Note `underlay_effect/sky/color0` — the same key path the Environment Editor mod
reads and writes at runtime. That is why `color0`/`color2` read `0, 0, 0` live on a
sky whose config says `1.0 1.0 1.0`: **the environment overrides the material.**

---

## A working day/night cycle

The `Day & Night Full` mod ships 26 `.environment` files and registers 17 as
replacements for vanilla ones. The whole animation mechanism is in `Loader.lua`:

```lua
BeardLib:ReplaceScriptData(mod_path .. "assets/environments/morning.environment",
                          "custom_xml", "environments/morning", "environment", true)
...
managers.worlddefinition:_set_environment("environments/morning")
```

Per-level:

```lua
tweak_data.levels[level_id].env_params = { environment = <name> }
```

Its registered set replaces these vanilla environments:

```
early_morning  morning  mid_day  afternoon  sunset  evening  night
forest_night   docks    mountain sunny       foggy_day
foggy_evening  foggy_bright_evening
```

**None of those 14 exist in the 225-environment export.** The export covers heist
environments only. The generic named environments are in a part of the DB that was
never extracted.

### What actually differs between two times of day

| Environment | underlay | color0 (top) | color2 (bottom) | sun_ray_color |
|---|---|---|---|---|
| `midday` | `default` | `0 0 0` | `0 0 0` | `1 0.945 0.812` |
| `morning` | `sky_1830_low_sun_clouds` | `0 0 0` | `0 0 0` | `1 0.561 0.357` |
| `sunny` | `sky_1530_low_sun_clouds` | `0.197 0.174 0.118` | `0.732 0.658 0.548` | `0.717 0.402 0.256` |
| `sunset` | `sky_2003_dusk_blue` | `0.859 0.804 1.0` | `0.6 0.306 0.180` | `0.851 0.212 0` |
| `night` | `sky_2335_night_moon` | `0 0 0` | `0 0 0` | `0.431 0.647 1` |

Four parameters do it: **`underlay`, `color0`, `color2`, `sun_ray_color`**. The
`color0_scale` / `color2_scale` pair controls how strongly each is applied.

That is the complete recipe. It also explains why the dome itself never needs to
move — the sky is re-graded, not rotated.

### All 25 set `rotation` to `0`

Not one Day & Night environment uses a non-zero rotation. The author found the same
thing the probe did: rotation exists in the schema but is not a useful lever.

---

## Corrected picture

| Claim | Was | Now |
|---|---|---|
| Rotation authorable | not addressed | **yes**, `<param key="rotation">` in the file |
| Rotation drivable from Lua | no | **no** — probe confirmed |
| `color1` settable | "unused, not exposed" | **authorable**, `underlay_effect/sky/color1` |
| `uv_velocity_*` key path | flat leaf name | `underlay_effect/cloud_overlay/uv_velocity_*` |
| Animation mechanism | four variables on a material | environment swap, plus colour grading elements |
| Export completeness | 225 environments | heist-level only; 14 generic ones missing |

## Still open

- `units/` export never landed. `sky_1945_sunset_clouds_mex` still missing.
- `params_a` / `params_b` component semantics. **Now confirmed** — the Day & Night
  config annotates them: `params_a` is "Range, offset, curve" and `params_b` is
  "Sky intensity, Sun intensity, Not used". Third-party corroboration of the
  inference in `06`.
- The 40 dome `.model` files the mod ships were not analysed. That is the geometry
  route to real cloud motion.

## References

- BeardLib-Editor — https://github.com/diesel-modding/BeardLib-Editor
- BeardLib wiki — https://luffyyy.gitbook.io/beardlib
- ScriptData / custom XML — https://luffyyy.gitbook.io/beardlib/things-to-know/scriptdata
- BeardLib Templates — https://github.com/diesel-modding/BeardLib-Templates
- SuperBLT — https://superblt.znix.xyz