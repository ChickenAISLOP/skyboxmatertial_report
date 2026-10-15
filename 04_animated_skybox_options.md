# 04 — Animated Skybox: Options

## Verdict

**An animated PAYDAY 2 skybox is achievable, and the game already ships the
machinery.** The current mod fails because it patches the only sky layer that
cannot move, and leaves four layers that can completely untouched.

| Layer | Animatable | Coverage | Effort |
|---|---|---|---|
| Dome cubemap (`dome_sky`) | **No** | 34 skies | — |
| Cloud layers (`DIFFUSE0_UVANIM` + `uv0_speed`) | **Yes** | 1 sky vanilla, extensible to any | Medium |
| Dome rotation (`sky_orientation.rotation`) | **Yes** | **225 / 225 environments** | **Low** |
| Sun animation (`sun_anim`, `sun_anim_x`) | **Yes** | **49 / 225 (Tier 3 only)** | Low |
| Lens flares (`flare_anim_x/y`, 8 flares) | **Yes** | **49 / 225 (Tier 3 only)** | Low |

### Important context: Tier 3 is not "the animated environments"

The 225 environments split three ways (see `03_environment_schema.md`):

| Tier | Count | What it is |
|---|---|---|
| 1 | **174** | Legacy flat environments. No sun model at all |
| 2 | **2** | `pd2_env_hox_02`, `pd2_ff_2` — full HDR, static sun |
| 3 | **49** | Full HDR + tone mapping + DOF + SSAO + bloom + motion blur + animated sun |

Sun/flare animation ships as part of the **modern rendering pipeline**, not as a
separate animation feature. It is therefore absent from ~78% of environments — there is
no sun model there to animate.

**Dome rotation is the only animation channel that works in 100% of environments.**

---

## Why the current mod cannot work

Three independent confirmations that `dome_sky` has no animation:

1. **All 33 named sky configs** use `render_template="dome_sky"`, and `dome_sky`
   exposes only `params_a` (range/offset/curve), `params_b` (sky intensity/sun
   intensity), and legacy `color0`/`color2`. No scroll parameter exists.
2. **`mods/environment editor/env.lua`** reads the live material and enumerates the
   variables: `color0`, `color0_scale`, `color2`, `color2_scale`. That is the whole
   set.
3. **`02_sky_material_configs.md`** — `uv0_speed` appears in exactly 4 configs
   game-wide, none of them `dome_sky`.

The mod's own header comment states this correctly. The diagnosis was right; the
conclusion drawn from it ("so remove animation entirely") was too pessimistic,
because it only looked at the dome.

---

## Option A — Dome rotation (cheapest, works everywhere)

`sky_orientation.rotation` exists in **all 225 environments**.

Skybox rotation is a display concern, not an art concern. A slowly rotating dome
reads as a moving sky even with zero texture animation. This is what most "animated
skybox" mods actually do.

**Pros**
- Available in every environment, no exceptions
- One value, trivial to drive
- No new assets, no new textures, no disk cost
- Cannot seam or tile — it is a matrix, not a UV offset
- Zero framerate cost

**Cons**
- Clouds baked into the cubemap rotate with it. For a single-composite sky that is
  often unnoticeable; for `sky_1945_sunset_clouds` (layered) the clouds would
  counter-rotate and look wrong.

**Effort:** low. **Recommendation: do this first.**

---

## Option B — Scrolling cloud layers (the real animated skybox)

Copy the `sky_1945_sunset_clouds` structure. That sky is the reference
implementation and it is vanilla.

Add to any sky's material config:

```xml
<material name="clouds_a" render_template="effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR" version="2">
    <diffuse_texture file="units/mods/skybox_animated/textures/clouds_a_df"/>
    <variable value="sun" type="scalar" name="intensity"/>
    <variable value="0.005 0 0" type="vector3" name="uv0_speed"/>
</material>
<material name="clouds_b" render_template="effect:DIFFUSE0_TEXTURE:DIFFUSE0_UVANIM:VERTEX_COLOR" version="2">
    <diffuse_texture file="units/mods/skybox_animated/textures/clouds_b_df"/>
    <variable value="sun" type="scalar" name="intensity"/>
    <variable value="0 -0.006 0" type="vector3" name="uv0_speed"/>
</material>
```

Then the sky's `.scene` / `.model` must reference those materials on geometry.
That last part is the blocker — see Risks.

**Key mechanic:** the geometry must carry the layer material. `sky_1945_sunset_clouds`
has a `.scene` and `.model` that place `clouds_top`, `clouds_02`, `clouds_02_slow`.
A stock sky's scene has no such meshes, so **you cannot add cloud layers to a stock
sky by editing the material config alone.** You would need to author or repurpose
scene geometry.

**The workaround that avoids all of this:** ship your *own* sky pair modelled on
`sky_1945_sunset_clouds` — dome mesh + 2–3 cloud shells — instead of overriding an
existing sky.

**Speeds from vanilla, for reference:**

| Speed | Effect |
|---|---|
| `0.001` | barely perceptible |
| `0.003` | slow drift |
| `0.005` | good cloud drift |
| `0.01 – 0.02` | obvious scroll |
| `0.5` | conveyor belt, not weather |
| `-1.5` | hazard scanline (shipped in `cas_skylight_barrier_hack`) |

Values are **not normalised**. Combine two layers at different speeds on different
axes for parallax — that is what makes `clouds_02` / `clouds_02_slow` work: identical
texture, 0.005 vs 0.003, same image but visibly separating.

**Important:** the cloud texture must have **wrap = repeat** on U and V, or it will
seam visibly once it scrolls. Vanilla cloud textures do. An imported DDS may not.

**Pros**
- Genuine texture motion, the thing you actually wanted
- Parallax from 2+ layers sells depth
- Precedent exists in vanilla, so nothing is being reverse-engineered

**Cons**
- Needs scene geometry, not just a config edit
- Repeating texture becomes obvious over long sessions
- More VRAM and draw calls per sky
- Extrapolating UV animation onto the `dome_sky` dome itself is unlikely to work —
  the template has no `UVANIM` token

**Effort:** medium to high. **This is the "hoping for animated skybox" answer, but it
is a sky-authoring project, not a config patch.**

---

## Option C — Sun and flare animation (cheap, additive)

**Tier 3 environments only (49 of 225)** carry `sun_anim`, `sun_anim_x`, `flare_anim_x`,
`flare_anim_y`, plus 8 flares with independent `flare_index_N`, `flare_alpha_N`,
`flare_offset_N`, `flare_scale_N`.

Moving the sun and its flares sells a lot of sky motion for very little work — and it
composes with Option A for free, since both are environment-level.

The Tier 3 sun model is not a tint. It includes:

```
color_sun / color_opposite_sun / alpha_scale_sun / alpha_scale_opposite_sun
sun_color / sun_color_scale / sun_range
sky_intensity / sky_top / sky_bottom
```

`color_opposite_sun` means the environment models light from **both** the sun and its
opposite — a full atmospheric model.

`core/lib/managers/coresky.lua` exposes `interpolate`, which is the primitive for
time-varying params.

**Pros**
- Pairs with rotation — they reinforce
- 8 flares is a lot of visual movement for one system
- Backed by `interpolate` in the manager

**Cons**
- **Tier 3 only.** The 174 legacy environments have no sun model
- Does not move clouds or the dome
- Tier 3 also runs motion blur (`uv_velocity_rg_mask` / `uv_velocity_b_mask`) — animated
  elements get blurred, which may smear rather than read as motion
- Numeric values are in the undecoded binary payload of `.environment` (see
  `05_environment_binary_format.md`)

**Effort:** low. **Best value if combined with Option A, and you only need it for
outdoor levels.**

---

## Recommendation

**Ship Option A first.** It works in every environment, costs nothing, and immediately
answers whether rotation alone satisfies "animated skybox". If it does, the project is
done.

If you want visible cloud motion, that is Option B, and it means building a
`sky_1945_sunset_clouds`-style layered sky rather than overriding a stock one. Scope
that as sky authoring.

Option C is a cheap add-on to A for outdoor levels.

---

## Risks and unknowns

| Risk | Detail |
|---|---|
| **Scene geometry is the blocker** | Cloud layers need meshes. Stock skies have none. Verified from `sky_1945_sunset_clouds` having 13 files vs the usual 4. |
| **`uv_speed` vs `uv0_speed`** | Both spellings exist. The mod writes `uv_speed`; shipped sky configs use `uv0_speed`. The `UVANIM` render-template token is the real binding; the name is the slot index. Test both. |
| **`unique="true"`** | Shipped sky configs omit it; the Scrolling Textures mod sets it. Probably required for a clean override. |
| **Text wrapping** | Scrolling textures need `wrap = repeat`. Imported DDS may not carry it. |
| **No tweak_data for skies** | Weapon configs are discoverable via `tweak_data.weapon.factory.parts[].material_config`. Sky configs are reached by convention from the environment's `underlay` path. There is no lookup table to hook. |
| **Config path is not always `core/`** | `sky_2335_night_moon` resolves under `units/pd2_dlc_sah/`. Corp under `units/pd2_dlc_corp/cubemaps/`. Pent under `units/pd2_dlc_pent/architecture/cubemaps/`. Derive from `underlay`, don't hardcode. |
| **`.environment` numerics undecoded** | Container layout is mapped (see `05_environment_binary_format.md`) but the node record layout is not. Numeric values need in-game extraction or further RE. |
| **Motion blur on animated elements** | Tier 3 has `uv_velocity_rg_mask` / `uv_velocity_b_mask` in exactly the 49 animated environments. Scrolling clouds will be motion-blurred — verify it reads as motion, not smear. |
| **Tier 3 is expensive** | Tier 3 runs HDR tone mapping with auto-exposure, DOF, SSAO, bloom and motion blur. `env_menu` is Tier 3. Per-frame environment work in the menu is the worst case. Gate on heist load. |
| **4 dead skies are safe** | `sky_1345_clear_sky`, `sky_1846_low_sun_nice_clouds`, `sky_cloudy_blue`, `sky_1044_overcast_sun` are bound by zero environments. Repurpose freely. |

---

## Practical next steps

1. **Prove rotation.** Drive `sky_orientation.rotation` per-frame in-game. If that
   looks acceptable, ship it. Everything else is optional.
2. **Confirm the template token.** Apply a config with `DIFFUSE0_UVANIM` + `uv0_speed`
   to `mat_rail_adapter` (the weapon from Scrolling Textures) to confirm the shader
   path, then try the same on a sky material. Isolates config syntax from scene
   geometry.
3. **Derive, don't hardcode.** Build the sky→config path map from the `underlay`
   values in `03_environment_schema.md`.
4. **Scope Option B as authoring.** Budget for dome mesh + 2–3 cloud shells, not a
   config edit.

---

## Reference files

| Path | Purpose |
|---|---|
| `core/environments/skies/<sky>/<sky>.material_config` | Per-sky material definition |
| `core/environments/skies/<sky>/<sky>.scene` | Scene graph — where cloud meshes would live |
| `environments/<name>/<name>.environment` | Environment: `underlay`, `sky_orientation`, sun, flares |
| `core/lib/managers/coresky.lua` | `CoreSky` param tree, `interpolate`, `LightIntensityDB` |
| `core/lib/managers/viewport/interfaces/coreenvironmentskyorientationinterface` | Orientation interface |
| `mods/Scrolling Textures/lua/generator/configs.lua` | Working UV-scroll implementation, `DB:open` pattern |
| `mods/environment editor/env.lua` | Live variable enumeration of the sky material |