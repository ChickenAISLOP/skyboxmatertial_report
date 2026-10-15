# 08 — Render Templates and Shader Inputs

The layer below `material_config`. Discovered via the modworkshop wiki, which
documents that template variables live in `shaders/base.render_template_database` —
a file that was present in the export the whole time and never opened.

---

## The wiki lead

[Material Config XML](https://wiki.modworkshop.net/books/payday-2-mod-creation/page/material-config-xml)
states:

> A full list of template variables can be found in `shaders/base.render_template_database`
>
> TEMPLATES ARE **NOT** MODULAR!

That is the pointer. `core/shaders/` in the export contains:

| File | Size |
|---|---|
| `base.d3d11.shaders` | 14.8 MB |
| `default_render_templates.render_template_database` | 6.5 KB |
| `default_shaders.d3d11.shaders` | 118 KB |
| `deferred_geometry_deprecated.render_template_database` | 12.9 KB |
| `deferred_lighting.render_template_database` | 14.1 KB |
| `environment.render_template_database` | **769 B** |
| `filters.render_template_database` | 14.8 KB |
| `post.render_template_database` | 15.7 KB |

Plus 7 `.post_processor` files describing the full post stack.

---

## There are three dome templates, not one

`environment.render_template_database` in full:

```xml
<diesel_render_system>
    <render_templates>
        <template name="dome_clouds" sort_value="">
            <shader_input_declaration/>
            <technique name="default">
                <method name="dome_clouds:default"/>
            </technique>
        </template>
        <template name="dome_sky" sort_value="">
            <shader_input_declaration/>
            <technique name="default">
                <method name="dome_sky:default"/>
            </technique>
        </template>
        <template name="dome_sun" sort_value="">
            <shader_input_declaration/>
            <technique name="default">
                <method name="dome_sun:default"/>
            </technique>
        </template>
    </render_templates>
</diesel_render_system>
```

**Usage across the whole export:**

| Template | Used by |
|---|---|
| `dome_sky` | **70** configs (38 distinct skies) |
| `dome_clouds` | **0** |
| `dome_sun` | **0** |

Zero in `mod_overrides` too. Both are declared, compiled and bound to a shader, but
nothing in the game uses them. They are supported and unused — worth knowing if you
want a second dome layer or a separate sun sprite.

---

## What each shader actually reads

`environment.d3d11.shaders` embeds 6 compiled HLSL shaders. Their DXBC reflection
data survived extraction, so the input names are readable. Splitting on the
`Microsoft (R) HLSL Shader Compiler 10.1` marker gives the per-template input sets
exactly:

### Shader 1 — the cloud/sun pass (18 inputs)

```
ref_alpha_scale_sun               ref_color_sun
ref_alpha_scale_opposite_sun      ref_color_opposite_sun
ref_cloud_mask_clamp              ref_global_color_sun
ref_cloud_sun_contour             ref_global_sun_dir
ref_cloud_sun_contour_pow         ref_global_color_sky_a
ref_cloud_sun_contour_mask_pow    ref_global_color_sky_b
ref_cloud_sun_contour_mask_slide  ref_global_color_sky_c
ref_time
ref_uv_velocity_rg_mask           ref_uv_velocity_b_mask
ref_uv_scale_b_mask
```

### Shaders 2 and 3 — the dome (5 inputs each)

```
ref_params_a
ref_params_b
ref_color0
ref_color1
ref_color2
```

### Shader 4 — the sun disc (1 input)

```
ref_sun_color
```

Shaders 5 and 6 declare no material inputs — vertex-only transforms.

### Engine-provided uniforms

```
camera_near_range      camera_pos          camera_world_matrix
GLOBAL_fov_ratio       GLOBAL_use_parallax view_proj_matrix
world_matrix           ref_time
```

---

## What this proves, and what it changes

### 1. The environment key names are confirmed against the shader

Every `ref_*` name maps to a key recovered from the `.environment` binaries:

| Shader uniform | Environment key | Coverage |
|---|---|---|
| `ref_uv_velocity_rg_mask` | `uv_velocity_rg_mask` | 49 |
| `ref_uv_velocity_b_mask` | `uv_velocity_b_mask` | 49 |
| `ref_uv_scale_b_mask` | `uv_scale_b_mask` | 49 |
| `ref_color_sun` | `color_sun` | 49 |
| `ref_alpha_scale_sun` | `alpha_scale_sun` | 49 |
| `ref_color_opposite_sun` | `color_opposite_sun` | 49 |
| `ref_alpha_scale_opposite_sun` | `alpha_scale_opposite_sun` | 49 |

This is independent confirmation that the 49-environment Tier-3 block is the cloud and
sun pass, read by a shader that takes a time uniform.

### 2. `color1` is a real input that no config ever sets — and it is not writable

The dome shader wants **three** colour inputs: `color0`, `color1`, `color2`.

Every sky config declares only `color0` and `color2`:

```xml
<variable name="color0" type="vector3" value="1.0 1.0 1.0"/>
<variable name="color2" type="vector3" value="1.0 1.0 1.0"/>
```

**0 of 38** sky configs declare `color1`. That is consistent with `params_a` shaping
the gradient across the dome: a three-stop gradient would want a mid colour, and the
engine reserves one but the art never fills it.

**Correction.** An earlier revision of this document called `color1` "a free parameter
nothing is using". That was wrong. A live probe shows `variable_exists("color1")`
returns **false**, and the only known write path gates on that same check:

```lua
if mat:variable_exists(Idstring("color0")) then
    mat:set_variable(Idstring("color0"), v)
end
```

So `color1` is an unused shader input, not an exposed one. It cannot be set.

### 2b. `color0` / `color2` are live, not inert

Also a correction. The static configs say `1.0 1.0 1.0`. At runtime they read
`Vector3(0, 0, 0)`. Both exist, both are writable, and both are currently black.
They are not the inert defaults this document originally described.

### 3. `ref_time` is the animation clock

The cloud/sun shader takes `ref_time`. Combined with `uv_velocity_*_mask` and
`cloud_sun_contour_mask_slide`, that is the mechanism behind Tier 3 motion — the
engine advances it, the shader scrolls UVs and slides the sun contour mask. It is
shader-driven, not Lua-driven.

### 4. `dome_sun` has its own input, separate from the dome colours

`ref_sun_color` is its own uniform, and `ref_global_color_sun` / `ref_global_sun_dir`
come from the environment. So the sun disc is not drawn by the dome shader. A sky
authored on `dome_sun` would take a colour directly rather than through `params_b.y`.

---

## Runtime probe: what is actually reachable from Lua

A read-only BLT probe was run in-game against `modders_devmap` to enumerate every
Lua-reachable object on the environment. Method lists recovered via
`getmetatable(obj).__index` (the `vp`, `post_processor` and `modifier` objects are
userdata, so `pairs()` returns nothing on them).

**Proven write path** — copied from `mods/environment editor/env.lua`, which calls it
every frame:

```lua
local mat = Underlay:material(Idstring("sky"))
if mat:variable_exists(Idstring("color0")) then
    local v = mat:get_variable(Idstring("color0"))
    mat:set_variable(Idstring("color0"), v)
end
```

**Environment object chain** — also from `env.lua`:

```
managers.viewport:first_active_viewport()          -> table
  :vp()                                            -> userdata
    :get_post_processor_effect("World", Idstring("deferred"))
      :modifier(Idstring("apply_ambient"))         -> userdata
        :material()                                -> userdata
```

Complete method inventory:

| Object | Methods |
|---|---|
| `vp` | `camera`, `director`, `update`, `extension`, `key`, `alive`, `get_rect`, `set_dimensions`, `get_post_processor_effect`, `set_post_processor_effect`, `get_post_processor_effect_name`, `set_LOD_active`, `override_submit_eye`, `set_override_submit_eye` |
| `post_processor` | `modifier`, `modifiers`, `set_visibility`, `visibility`, `extension`, `key`, `alive` |
| `modifier` | `material`, `set_visibility`, `visibility`, `extension`, `key`, `alive` |

Viewport fields: `__manager`, `__name`, `__active_requested`, `__really_activated`,
`_env_handler`, `_vp`, `_vpm`, `_replaced_vp`, `_render_params`, `_init_trace`,
`_ref_fov_stack`, `_enable_adaptive_quality`, `_width_mul_enabled`.

### `sky_orientation/rotation` is not reachable — closed

`CoreSky`, `EnvironmentHandler` and `EnvironmentManager` are **not globals** at
runtime. `viewport._env_handler` exists but is an empty table.

A filter for any name containing `rot`, `sky`, `orient`, `underlay` or `sun`, run
across every reachable method and field, returned **zero hits**.

**There is no Lua-facing setter for `sky_orientation/rotation`.** `SkyRotationFeeder`
is C++-internal and consumes the key directly from the environment data. The rotation
is real and present in all 225 environments, but not drivable at runtime.

This resolves what `03`, `04` and `07` previously left open.

### Correction

Those documents described rotation as "the cheapest possible win" and "the only
animation channel available in all 225 environments". Both are true of the **engine**
and false for **runtime Lua**. A sky dome cannot be rotated from a Lua mod.

**Further correction, see `09`.** "Not drivable at runtime" is not the same as "not
moddable". `sky_orientation/rotation` is authorable in the environment file, and the
primary sky-animation mechanism is swapping whole environments, not moving the dome.
This section was too strong. `09` documents the real routes.

### What is actually animatable

| Variable | Live value | Writable | Reads as |
|---|---|---|---|
| `params_a` | `0.9, 0.5, 2.0` | yes | gradient spread / offset / curve |
| `params_b` | `0.15, 1, 0` | yes | sky intensity / sun intensity |
| `color0` | `0, 0, 0` | yes | sky tint |
| `color2` | `0, 0, 0` | yes | sky tint |
| `color1` | absent on this sky | **yes**, as `underlay_effect/sky/color1` - see `09` |

`params_a` and `params_b` at runtime match the static config decoding exactly, which
validates the binary analysis throughout this report. `09` adds third-party
corroboration of the component meanings.

Sweeping these over time produces a slow colour wash - that is all the runtime Lua
surface offers. It is **not** the way the sky is animated in practice. For that, see
`09`: the engine re-grades the dome through the environment's
`underlay_effect/sky/*` keys, and whole environments are swapped at runtime.

---

## Export is incomplete: `units/` was never extracted

`assets/` in the game install is **31.66 GB across 98 `.crate` files**. The Diesel
Crate Browser export used for this report is **217 MB / 2,536 files** covering:

```
core/         724 files   132.7 MB
environments/ 311 files    58.2 MB
lib/         1256 files    20.7 MB
gamedata/     147 files     2.4 MB
skydomes/       7 files     2.7 MB
settings/      10 files     0.2 MB
```

There is **no `units/` directory in the export.** It was never extracted.

This matters concretely. 14 of the 223 `underlay` bindings point into `units/`:

| Environments | Sky |
|---|---|
| 10 | `units/pd2_dlc_pent/architecture/cubemaps/sky_pent_dusk_0065` |
| 3 | `units/pd2_dlc_corp/cubemaps/sky_corp_deep_blue` |
| 1 | `units/pd2_dlc_mex/environments/sky_1945_sunset_clouds_mex` |

All three are referenced by vanilla environments. **None were extracted.** Two of them
(`sky_pent_dusk_0065`, `sky_corp_deep_blue`) were counted in the 38-sky inventory only
because flat duplicate copies exist at the export root.

`sky_1945_sunset_clouds_mex` — a **Minecraft-themed variant of the one animated sky** —
is not in the export at all.

### To close this gap

`DieselCrateBrowser.exe` is a Qt GUI app with no CLI flags (`--help` produces nothing).
Automated extraction is not possible from the command line. Either:

1. Run the GUI, search for `units`, export it — then re-run
   `decoded/sky_inventory.csv` generation; or
2. Use the in-game Lua API, `DB:open(type, idstring)`, which resolves hashed paths.

A raw byte scan of all 98 crates found **zero** plaintext occurrences of the three sky
names. Paths are hashed and `crates.shipping_manifest` stores 16-byte GUIDs, so
name-based discovery inside the crates is not possible.