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

### 2. `color1` is a real input that no config ever sets

The dome shader wants **three** colour inputs: `color0`, `color1`, `color2`.

Every sky config declares only `color0` and `color2`:

```xml
<variable name="color0" type="vector3" value="1.0 1.0 1.0"/>
<variable name="color2" type="vector3" value="1.0 1.0 1.0"/>
```

**0 of 38** sky configs declare `color1`. It is an unused middle band, permanently at
its default. That is consistent with `params_a` shaping the gradient across the dome:
a three-stop gradient would want a mid colour, and the engine reserves one but the art
never fills it.

This is the most actionable finding in this document: `color1` is a free parameter
nothing is using.

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

## Still not resolved

`params_a` and `params_b` are confirmed as the dome shader's two vector3 inputs, but
their **per-component meaning** stays inferred from observed values, not read from
source. The compiled bytecode would need disassembly to settle it. What is now
verified is that they are exactly two vectors and nothing else — the earlier "six
variables, none animate" claim holds, with `color1` added as a seventh slot the art
never fills.

| Slot | Shader input | Set by configs | Value |
|---|---|---|---|
| 1 | `ref_params_a` | 38 / 38 | range, offset, curve (inferred) |
| 2 | `ref_params_b` | 38 / 38 | sky intensity, sun intensity (inferred) |
| 3 | `ref_color0` | 38 / 38 | always `1.0 1.0 1.0` |
| 4 | `ref_color1` | **0 / 38** | never set |
| 5 | `ref_color2` | 38 / 38 | always `1.0 1.0 1.0` |

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