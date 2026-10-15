# Raw probe output

Verbatim output from the in-game probes, archived so the report's claims can be
checked against the actual runs rather than taken on trust.

These files are **evidence, not documentation**. Several of them record failures.
That is the point — the negative results are what took the work to establish.

## What each file is

| File | Probe | What it establishes |
|---|---|---|
| `sky_rot_watch.txt` | rotation watch | Spread **0.0000** over 24 samples on `branchbank`. Nothing animates the sky rotation in a heist. |
| `sky_rotation.log` | rotation driver | Driver lifecycle: start, write confirmation, stop. |
| `sky_rotation_settings.json` | rotation driver | The persisted `enabled` / `speed` values. |
| `brightness_report.txt` | brightness detect | All 10 candidate environment data paths return `no (false)` on a Tier 1 environment. |
| `sky_brightness.log` | brightness driver | **The silent no-op.** Writes `params_b.x → 0.0697`, reads back `0.1500`, no error raised. |
| `sky_probe_report.txt` | sky internals | The four readable material variables and their live values. |
| `env_swap_report.txt` | environment API | `game_default_environment()` returns `core/environments/default`; the five candidate DB paths all return `YES`. |
| `cloud_report.txt` | cloud layers | `Underlay:material()` returns `nil` for `clouds_top` / `clouds_02` / `clouds_02_slow` on a level not using `sky_1945_sunset_clouds`. |

## The two that matter most

**`sky_brightness.log`** is why brightness was removed. `mat:set_variable()` reported
success on every call — no error, `errors 0`, `writes 1` — and changed nothing:

```
14:09:29  captured original sky intensity 0.1500
14:09:29  sky intensity 0.1500 -> 0.0697   (x0.46)   <- reported as written
14:09:30  params_b reads back 0.1500                 <- unchanged
```

That is the measurement that refuted the report's `Writable: yes` column, which had
been inferred from `variable_exists` — a read-only call.

**`sky_rot_watch.txt`** is why the driver can own the rotation outright. Twelve seconds,
24 samples, one level, spread 0.0000, both viewport accessors agreeing exactly. No
competing writer exists, so no arbitration is needed.

## A note on the brightness log

It contains 112 identical lines timestamped `14:09:47` — the result of dragging the
brightness slider, each tick writing a log line and appending to the file. The throttle
added afterwards fixed it, but the spam was already recorded before that. Kept as-is
rather than cleaned, because the volume is itself the evidence for why the throttle
exists.

## Provenance

All produced 2026-10-15 on the user's install, written to `mods/saves/` by the probe
modules. The probe modules themselves have since been deleted from the mod; these files
are the remaining record of what they measured.