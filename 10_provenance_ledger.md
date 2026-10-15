# Provenance ledger

**Added 2026-10-15, after the rotation retraction.** This file exists because the
single largest error in this investigation was an *inference* presented with the same
confidence as a measurement. Recording which claims rest on what, makes that visible.

## Environment swap cannot be tested in this mod configuration

A separate, non-crash finding, and the reason swap is still unverified.

Both swap routes access-violated **inside `PackageManager:_script_data`**, reached via
BeardLib's `FileManager:Process:46`:

| Route | Result |
|---|---|
| `managers.viewport:set_override_environment(path, blend)` | access violation (crash 5 — my argument-count guess) |
| `worlddefinition:_set_environment(path)` | access violation (crash 6) |

The second is the important one. `_set_environment` had already been called in rev1
without crashing, so it looked safe. It was only safe because the argument was
`core/environments/default` — **already loaded, so nothing actually loaded**. Point it at
a real environment and it loads one, and the load faults.

The load path with BeardLib installed:

```
worlddefinition:_set_environment(path)
  preload_environment        coreviewportmanager.lua:148
    preload_environment      coreenvironmentmanager.lua:107
      _load                  coreenvironmentmanager.lua:258
        BeardLib FileManager:Process:46
          PackageManager:_script_data   ← access violation
```

`BeardLib/Classes/Managers/FileManager.lua:23` does `FileManager = self`, so BeardLib
handles every script-data load once installed, and line 40 auto-registers environment
assets before line 46 reads them.

**Ruled out:** a string where an `Idstring` was required. That was the obvious
explanation — it caused crash 1 — but the `Day & Night Full` mod passes plain strings to
`_set_environment` (`override_all[k] = v.value`), so a string is the accepted type.

**Not ruled out:** whether this is a BeardLib bug, a conflict with the `environment
editor` mod also in `mods/`, or a genuine engine limitation. No further attempt was
made; two crashes is enough.

The swap TEST button has been **removed from the menu**, not hidden. The read-only
inspect remains, since it only reads.

## Every crash in this investigation was mine

Five, all self-inflicted, all from the same family of mistake — calling something whose
argument convention had not been established.

| # | Cause | `pcall` catchable? |
|---|---|---|
| 1 | `get_variable("string")` where an `Idstring` was required | **no** — access violation |
| 2 | Invented a `SizeCode` symbol that does not exist | **no** — access violation |
| 3 | `local a = 1, b = 2` (invalid declaration) | yes |
| 4 | `DelayManager` — a global that does not exist in this build | yes |
| 5 | `set_override_environment(path, blend)` — guessed argument count | **no** — access violation |
| 6 | `_set_environment` with a real (not already-loaded) environment | **no** — access violation |

**Crash 5 in detail.** `coreviewportmanager.lua` lists
`set_override_environment(environment_path, blend_duration, ...)` — with more arguments
after `blend_duration`. Rev3 tried `(path, blend)` first. That faulted inside
`PackageManager:_script_data`, reached through BeardLib's `FileManager:Process:46`.

Two contributing factors:

1. **The argument count was guessed.** No installed mod calls
   `set_override_environment` — zero hits across 1,419 mod Lua files. Passing fewer
   arguments than the native function reads leaves it reading memory never supplied.
2. **BeardLib is in the load path.** `FileManager.lua:23` assigns `FileManager = self`,
   so every environment load goes through BeardLib's `Process`.

This is the same error as crash 2. The rule "only call functions another installed mod
already calls successfully" exists precisely to prevent it — it is written above in this
same file — and it was bypassed anyway because the decompiled signature *looked* safe.

`set_override_environment` was removed. It is the better API on paper (it takes a blend
duration, which `_set_environment` does not) but is not safely callable without precedent.
`worlddefinition:_set_environment(path)` is used instead: it was called in rev1 without
raising and without crashing, and it is what the Day & Night mod calls.

## Is anything else already animating the rotation?

Asked because two inspections five minutes apart read `162` and `338`.

**No. Measured, not inferred.** A 12-second watch sampled the rotation 24 times on
`branchbank`:

| Viewport | First | Last | Min | Max | Spread |
|---|---|---|---|---|---|
| `active_viewports[1]` | 222.0000 | 222.0000 | 222.0000 | 222.0000 | **0.0000** |
| `first_active_viewport()` | 222.0000 | 222.0000 | 222.0000 | 222.0000 | **0.0000** |

One level for the whole window, both viewport accessors in exact agreement, zero drift.

The file evidence agrees and predicted it: `sky_rot` appears in exactly four files in
the entire export, all editor or lobby Lua. Zero `.environment` files, zero `.level`
files, zero occurrences in `playerstandard.lua`. `coreworlddefinition` reads
`self._environment.sky_rot` once at load and calls `create_global_environment_modifier`;
the only later writers are an editor slider and the lobby's `_set_sky_rotation_angle`.

So the `162` vs `338` difference was **two different levels**. `162` was read on `big`;
the rotation probe's TEST did not log the level, so which level produced `338` was never
recorded. That was a gap in the probe, not behaviour in the engine.

**Consequence:** a mod can own `sky_orientation/rotation` outright. No arbitration with
the game is needed, and a driver does not have to fight anything.

## The "Writable: yes" column was inference

Found while wiring a brightness control, and it is the same mistake as the rotation
retraction in a smaller costume.

The sky probe called `variable_exists` and `get_variable`. Both are read-only. The
report's table had three columns — `Variable`, `Live value`, `Writable` — and the first
two were measured while the third was `variable_exists` returning true, restated as
"yes".

At the time the claim was made, **no `set_variable` call existed anywhere in the mod**.
The only occurrence of the string was inside a comment showing the intended syntax. A
reader had no way to tell a measured column from an inferred one, because they were in
the same table with the same formatting.

Two columns now separate `Variable exists` (measured) from `Write tested` (honestly
empty). The `params_b.x` brightness control is the feature that will fill it in.

The generalisable lesson is the rotation one again: **existence is not writability, and
an inferred value placed beside measured ones inherits their credibility.**

## The driver works

`lua/sky_rotation.lua` in the mod, Options → skybox → Sky Rotation. Per-frame continuous
rotation, user-confirmed working.

```lua
local key = Idstring("sky_orientation/rotation"):key()
local h = managers.viewport:first_active_viewport()._env_handler
R.angle = (R.angle + speed * dt) % 360
h:editor_set_value(key, R.angle)
```

Time-based, not frame-based, so the rate is identical at any framerate. Verified in
LuaJIT before shipping — end angle matches exactly at 30 / 60 / 90 / 144 / 240 fps:

| fps | writes over 60s | end angle |
|---|---|---|
| 30 | 1,800 | 218.000 |
| 60 | 3,600 | 218.000 |
| 144 | 8,640 | 218.000 |
| 240 | 14,400 | 218.000 |

This works because nothing else competes for the value — see the 12-second watch above,
spread 0.0000. A mod can own the rotation outright.

## Brightness is not drivable — both routes measured dead

Built, tested, and removed. The negative result is worth more than the control was.

**Route 1 — the sky material. `set_variable` is a silent no-op.**

| Time | Event |
|---|---|
| 14:09:29 | captured original sky intensity `0.1500` |
| 14:09:29 | wrote `params_b.x` → `0.0697`, reported as success |
| 14:09:30 | `params_b` reads back `0.1500` — **unchanged** |

No error raised, `errors 0`, `writes 1`. The material returned by
`Underlay:material()` is evidently not the live one the renderer reads. A call that
reports success and does nothing is worse than one that raises, because it looks like
it worked.

This is the second confirmation that the retracted `Writable: yes` column was wrong.

**Route 2 — the environment. The key only exists in 23% of environments.**

The write route itself works. Verified:

```
14:12:21  others/sun_ray_color_scale 1.0000 -> 0.4028 (x0.40)  CONFIRMED
```

But the key that actually means sky intensity is `underlay_effect/sky_top/sky_intensity`,
and our decode of all 225 environments shows where it lives:

| Key | Coverage |
|---|---|
| `sky_intensity` | **51 / 225** — Tier 2 and 3 only |
| | the other **174** are Tier 1 legacy: no sun model, no intensity key at all |

`modders_devmap`, where this was tested, is Tier 1. All ten candidate paths correctly
returned `no (false)`. That is not a naming problem and no path string fixes it.

An intermediate revision made it look broken for the wrong reason: it fell through to
`others/sun_ray_color_scale`, the only supported key on that level, which scales the
**sun rays**. The write stuck, nothing looked different, and it read like a failure of
the whole approach rather than a bad fallback.

**Removed.** A control that works on 23% of levels is worse than none, because it looks
functional.

## Provenance tiers

| Tier | Meaning |
|---|---|
| **1** | Measured in-game this session. Someone ran it and watched the result. |
| **2** | Re-derived from files in the export. Reproducible from the data on disk. |
| **3** | Third-party source or documentation. Someone else's claim, unverified by us. |
| **4** | **Inference.** Reasoned, not measured. Treat as a hypothesis. |

Tier 4 is where every retraction in this project originated. Not one claim that had to
be withdrawn came from a measurement.

## The rotation retraction

**Wrong claim, originally Tier 4 stated as Tier 1:** "There is no Lua-facing setter for
`scy_orientation/rotation`; the dome cannot be rotated from a Lua mod."

It looked like Tier 1 because it came from a live probe. It was not. The probe measured
the sky **material** and found no rotation variable — a correct observation — then the
conclusion "therefore no Lua-facing setter exists" was added. That last step is Tier 4.

Two concrete faults:

1. `viewport._env_handler` is metatable-backed. `pairs()` returns nothing because the
   methods live on `__index`. The probe read an empty table as "no methods". The same
   mistake had already been made and fixed once earlier in the session on
   `managers.worlddefinition`; it was reintroduced.
2. The material is the wrong object. Rotation is an environment value, not a material
   variable.

**Corrected, now Tier 1:**

| Step | Value |
|---|---|
| `h:get_value(key)` | `338` |
| `h:editor_set_value(key, 68)` | returned without raising |
| `h:get_value(key)` 0.5 s later | `68` |
| `h:editor_set_value(key, 338)` | returned without raising |
| `h:get_value(key)` | `338` |

Dome visibly rotated and returned (user-confirmed video).

## Current claim status

| Claim | Tier | How verified |
|---|---|---|
| 38 skies, 223 bindings | 1 | inventory regenerated byte-identically from the export |
| Rotation drivable from Lua | **1** | in-game write / read-back / restore, plus video |
| Rotation present in 225/225 environments | 2 | key decoded from every `.environment` |
| `has_data_path_key(sky_orientation/rotation)` = YES | 1 | live probe |
| `_environment_modifier_id` == rotation key hash | 1 | live probe, value `3c084f67b1da34be` |
| **Nothing animates the rotation in a heist** | **1** | 24 samples over 12s on `branchbank`, spread **0.0000**, both viewports agreeing |
| Rotation survives a level change without a fight | 1 | implied by the above — no competing writer exists |
| 4 sky-material variables **exist and are readable** | 1 | live probe; values match static decode |
| Those 4 variables are **writable** | **1 — refuted** | **`set_variable` measured as a silent no-op: wrote 0.0697, read back 0.1500, no error.** See below |
| `_set_environment` callable | 1 | live call returned without raising |
| Environment DB path form `environments/<dir>/<name>` | 1 | 5/5 candidates returned `YES` |
| Environment swap changes the rendered sky | **4** | **not demonstrated, and not safely testable** — both routes access-violate through BeardLib's `FileManager:Process` |
| Day & Night 17-variant cycle works | 3 | third-party mod source; mod never loaded |
| 3 dome templates, 1 used | 2 | DXBC reflection from `environment.d3d11.shaders` |
| `uv_velocity_*` live under `cloud_overlay/` | 3 | BLE key-path list; our decoder flattened it |

## Process rules adopted

1. **Never generalise a measurement of object A into a claim about object B.** "Four
   variables on the material" was restated as "no setter in the engine".
2. **An empty `pairs()` is not an empty object.** Check `getmetatable(o).__index`.
   This mistake was made twice on two different objects.
3. **Only call functions another installed mod already calls successfully.** `pcall`
   cannot catch access violations. Precedent: `DisableFog` for `get_value`,
   BeardLib-Editor for `editor_set_value`. **This rule was bypassed on
   `set_override_environment` and caused crash 5.** Zero hits across 1,419 mod Lua files
   is the signal to leave it alone.
4. **Do not trust a Lua global because it sounds right.** `DelayManager` does not exist
   in this build; `DelayedCalls` does.
5. **A decompiled signature is not a calling convention.** The constant pool shows
   `set_override_environment(environment_path, blend_duration, ...)` — it does not show
   how many arguments the native function reads. Reading one as the other caused crash 5,
   the same failure mode as the invented `SizeCode` symbol in crash 2.
7. **A crash should close the door, not invite a retry with different arguments.**
   Crashes 1, 2 and 5 were all followed by a narrower attempt at the same thing.
8. **Check that the thing exists, not that a string matching its name exists.**
   While wiring the rotation menu I grepped for `sa_rot_enabled` and reported "wiring
   present" — but that was the *callback*, which existed, while the menu *item* that
   references it had never been added. The tab was registered, built and linked, and
   empty. A search that can only succeed is not a verification.
9. **Appending to a structured file needs the structure.** `loc/english.txt` is a JSON
   object; an `Add-Content` of an INI-style block landed outside the closing brace and
   silently killed every key added since. The first repair attempt was also wrong —
   commas dropped between entries — and was only caught by validating the parse.

## Corrections issued this session

| # | Was | Now |
|---|---|---|
| 1 | 34 skies | **38** — four root-level `.material_config` files were missed |
| 2 | `color1` free to author | not set on `modders_devmap`; authorable at `underlay_effect/sky/color1` |
| 3 | `color0` inert | environment-driven |
| 4 | rotation "available" | authorable in file — **and now also drivable from Lua** |
| 5 | "sky cannot be animated" | it can, two independent ways |
| 6 | `uv_velocity_*` flat key | full path `underlay_effect/cloud_overlay/uv_velocity_*` |
| 7 | rotation unreachable from Lua | **reachable — see above** |
| 8 | "the dome never rotates" | it rotates via `sky_orientation/rotation` |