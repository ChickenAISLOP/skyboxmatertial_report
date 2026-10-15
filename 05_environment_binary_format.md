# 05 — `.environment` Binary Format

The `.environment` payloads use Overkill's proprietary **Oxml** serialization
(`coresky.lua`'s identifier table references `Oxml_node`, `child`, `key`, `value`,
`children`).

A working decoder ships with this report:

```
tools/decode_environment.ps1
```

Run it against one file for a human-readable dump, or against the whole tree:

```powershell
.\tools\decode_environment.ps1 -Path ..\aireportpd2\environments\env_menu\env_menu.environment
.\tools\decode_environment.ps1 -Path ..\aireportpd2\environments -Recurse -JsonOut decoded\environments.json
```

Outputs already generated: `decoded/environments.json` (all 225) and
`decoded/environment_summary.csv`.

---

## Container layout

Verified against all 225 exported files.

| Offset | Size | Contents |
|---|---|---|
| `0x000` | 8 | 0 |
| `0x008` | 8 | **float pool count** |
| `0x010` | 8 | same, repeated |
| `0x018` | 8 | **float pool offset** (208 in every file) |
| `0x020` | 8 | 0 |
| `0x028` | 8 | **string count** |
| `0x030` | 8 | same, repeated |
| `0x038` | 8 | **string record table offset** (records begin at `+8`) |
| `0x040` | 8 | 0 |
| `0x048` | 8 | complexity counter — **not** a tier (see below) |
| `0x050` | 8 | same, repeated |
| `0x058` | 8 | **end of string region** = start of node/value block |

Then, in order:

```
float pool          floatPoolCount × float32
string records      stringCount × { u32 offset; u32 pad[3] }     at recordTable + 8
string bytes        NUL-separated ASCII
node/value block    variable length, contains a 40-byte descriptor table
record grid         [u8 tag][u8 value][0x00][0x00] × N
```

The 8-byte gap at `recordTable + 8` is real: the first 8 bytes after the header
pointer are always zero. Reading record `i` at `recordTable + 8 + i*16` works for all
225 files.

### The `0x048` field is not a tier

It looks like one but is not. Counter-examples found:

| Environment | `0x048` | String-derived tier |
|---|---|---|
| `env_asset_texturing` | 15 | 3 |
| `pd2_ff_2` | 18 | 2 |
| `pd2_env_hox_02` | 22 | 2 |

Ranges per actual tier: Tier 1 = 10–14, Tier 2 = 18–22, Tier 3 = 15–29. Overlapping.
Classify by string presence, never by this field.

---

## Float pool — literal values, recovered

At `floatPoolOffset`, `floatPoolCount` float32s in **first-use order**. The pool holds
two kinds of entry and they are interleaved:

- **String indices** — small integers that happen to be valid string slots
- **Literal floats** — real environment values

How to tell them apart: an entry whose value is a whole number equal to a valid string
index is an index; anything else is a literal.

Worked example, `pd2_indiana_basement` (18 entries):

```
pool[0]=1    pool[1]=2    pool[2]=0    pool[3]=3    pool[4]=4
pool[5]=0.25 ← literal
pool[6]=9259 ← literal
pool[7]=5    pool[8]=6    pool[9]=7    pool[10]=8   pool[11]=9  pool[12]=10
pool[13]=0.3 ← literal
pool[14]=11
pool[15]=0.17 ← literal
pool[16]=12   pool[17]=13
```

Resolving the indices against that file's string table:

```
1=metadata  2=data  0=environment  3=sky_orientation  4=param
5=key  6=rotation  7=value  8=others  9=underlay  10=core/environments/skies/default/default
11=global_texture  12=environments/cubemaps/cubemap_midday_hcm  13=sun_ray_color
```

That is exactly document order. Confirmed.

### Literal float statistics

| | Total |
|---|---|
| Literal float slots across all 225 files | **2,210** |
| Distinct values | **575** |

Per tier:

| Tier | Literal floats per file |
|---|---|
| 1 | 2 – 13 (avg 7.8) |
| 2 | 8 – 12 (avg 10.0) |
| 3 | 11 – 24 (avg 17.1) |

Most frequent values:

| Count | Value | Likely role |
|---|---|---|
| 105 | `0.5` | default scale |
| 60 | `0.32` | intensity |
| 47 | `0.20` | intensity |
| 45 | `0.55` | intensity |
| 44 | `0.108` | flare offset / scale |
| 41 | `0.15` | intensity |
| 38 | `0.717` | intensity |
| 37 | `0.80` | scale |
| 35 | `0.896` | intensity |
| 34 | `0.454` | intensity |

Values cluster hard in `0.0 – 1.0` — these are intensities, scales and colour
multipliers, not distances. Distances live in the node/value block instead.

### `env_menu` literal pool (Tier 3)

```
[44] 0.320   [47] 0.609   [48] 0.932   [49] 0.143
[51] 0.573   [52] 0.440   [53] 0.034   [54] 0.570
[55] 0.092   [56] 0.433   [57] 0.038   [58] 0.154
[59] 0.896   [60] 0.800   [61] 1.505   [62] 9.609
[63] 4.086   [64] 0.484   [65] 0.147   [66] 1.047
[67] 0.454   [68] 9.391
```

Note the gap: indices 44–68 with 45, 46, 50 missing. Those are consumed by
non-float entries. The two values above 1.0 (`9.609`, `9.391`, `4.086`) are almost
certainly flare scale or sun-range parameters.

> Attribution is by elimination, not proof. Which literal belongs to which key is the
> one thing the tag stream does not make explicit — see *Limitations*.

---

## Record grid — fully decoded

4-byte words, `[u8 tag][u8 value][0x00][0x00]`. Only five tag values occur.

| Tag | Meaning |
|---|---|
| `0x00` | no-op / padding |
| `0x03` | string reference, leaf or value slot |
| `0x04` | string reference |
| `0x05` | **float, indexed into the float pool** |
| `0x08` | string reference, element or container name |

Locating it: scan for the longest run of words where bytes 2 and 3 are both zero and
bytes 0 and 1 are both `< 0x40`. Reliable on every file. **Derive this offset — do not
hard-code it**, see the caveat under *The descriptor table*.

### Document structure

The stream encodes a tree of the form:

```
environment
├─ metadata
└─ data
   ├─ sky_orientation
   │  └─ param
   │     ├─ key   = rotation
   │     └─ value = <float>
   ├─ param  key = underlay        value = core/environments/skies/default/default
   ├─ param  key = global_texture  value = environments/cubemaps/cubemap_midday_hcm
   ├─ param  key = sun_ray_color   value = 0.25
   └─ …
   ├─ post_effect
   ├─ deferred
   ├─ shadow_processor
   └─ underlay_effect
```

That is why `sky_orientation.rotation` reads as a dotted path in the report — it
literally is one in the tree.

### Key/value recovery

The recurring token run is `key → <KEYNAME> → value → <VALUE>`. Matching that pattern
recovers string-valued params directly:

```
[45] 8/5   'key'
[46] 4/9   'underlay'
[47] 4/7   'value'
[48] 4/10  'core/environments/skies/default/default'
```

`underlay` — the sky cubemap binding — recovered this way for **223 of 225**
environments.

The 2 that fail are `pd2_env_hox_02` and `pd2_ff_2` — precisely the two Tier-2
environments, which use a different node shape. That is a clean correlation, not a
coincidence.

`decoded/environment_summary.csv` contains the recovered `underlay` and
`global_texture` for all 225.

---

## Node/value block — partially decoded

Runs from `0x058` to the start of the record grid.

| Tier | Block size |
|---|---|
| 1 | 1,791 – 2,451 bytes |
| 2 | 5,311 – 5,359 bytes |
| 3 | 6,595 – 7,259 bytes |

### What is known

- It is **variable length per record**, not a flat array. Two files with identical key
  sets have non-identical block layouts.
- It mixes **float32 and integer** fields at the same alignment. Reading it as pure
  float32 produces denormal garbage from roughly the midpoint onward
  (`5.6E-45` is the integer `4` at float32 scale).
- Colour values appear as clean **RGB float triples**. A Tier-1 file opens with them:
  ```
  0.2745 0.5294 0.6000
  0.2941 0.3098 0.3490
  0.3137 0.4314 0.4510
  ```
  and closes with two more. Five in total, matching the five colour params an
  environment carries — `fog_start_color`, `fog_far_low_color`, `ambient_color`,
  `sky_top_color`, `sky_bottom_color`.
- Distance and range parameters live here too. The same file yields `533`, `2367`,
  `10000`, `9999`, `50000`, `101`, `801`, `634`, `1566` — fog ranges and cascaded
  shadow slice depths.

### The descriptor table

Buried in the middle of the block is a table of **40-byte descriptors**, each holding
three small integers and one u32 pointer into the record region.

Stride is **40 bytes**, and that is consistent across every file measured:

| File | Tier | Pointers | Spacing |
|---|---|---|---|
| `pd2_indiana_basement` | 1 | 41 | 40 × 39, 80 × 1 |
| `pd2_are_stage` | 1 | 41 | 40 × 39, 80 × 1 |
| `pd2_env_night` | 1 | 43 | 40 × 39, 80 × 3 |
| `pd2_hox_1` | 3 | 165 | 40 × 163, 160 × 1 |
| `env_menu` | 3 | 161 | 40 × 158, 80 × 1, 120 × 1 |

Pointer targets, relative to the record grid, for `pd2_indiana_basement`:

```
13, 45, 109, 125, 141, 181, 197, 213, 229, 245, 277, 293, ...
```

Deltas: `32, 64, 16, 16, 40, 16, 16, 16, 16, 32, 16` — every one a multiple of 8. All
targets are `≡ 1 (mod 4)` relative to the grid, so they land 13 bytes into the record
stream rather than on a record boundary.

> **Caveat that cost an hour:** pointer detection depends on where you declare the
> record region to begin. Hard-coding `0xdc8` instead of deriving it from the longest
> `[tag][val][0][0]` run makes descriptor spacing look like 32 bytes and shifts which
> u32 values qualify as pointers. Derive the grid first; do not hard-code it.

### What is still unknown

The meaning of each descriptor field, and therefore which value belongs to which key.
The 40-byte stride and the 16-byte pointer granularity are solid; the semantics are
not.

### Why this was not pushed further

All 174 Tier-1 files carry exactly **28** real keys. There is no smaller specimen
anywhere in the export, so the record layout cannot be inferred from a trivial case —
it has to be solved on a full 28-key file, which is what was attempted.

Every value-bearing record has to be distinguished from integer fields whose type is
only knowable from context. Without a known-good plaintext sample to validate against,
any attribution would be guesswork dressed as data.

---

## Practical guidance

### Get the numbers in-game instead

Far cheaper and exact. `coresky.lua` exports as LuaJIT bytecode, but its string table
exposes `set_value`, `interpolate` and `database_lookup` against `Global.level_data` —
enough to read or write any environment key at runtime. Dumping a key is then a few
lines of Lua rather than more binary work. Roughly an hour of work versus days of
binary RE for the same numbers.

Note there is **no `mods/` folder in the asset export**, so community tooling like the
Environment Editor mod could not be checked here.

### If you continue the RE

1. Validate against a file whose values are known — read the live value in-game and
   diff against the corresponding `.environment`.
2. Start from a Tier-1 file (28 keys, 1.8 KB block).
3. Use the colour triples as anchors: they are unambiguously float32 and their count
   equals the number of colour params.
4. Only then attempt Tier 3, where the block is 3–4× larger.

### Invariants to assert in any decoder

```
floatPoolOffset   = 208                      (constant across all 225)
stringRecord[i]   = u32( recordTable + 8 + i*16 )
stringsEnd        = u64 @ 0x058
tagStreamStart    = longest run from stringsEnd of [tag][val][0][0], tag < 0x40
```

If a candidate parse violates the first or second, it is wrong.

---

## Side finding: crate contents cannot be grepped

Recorded because it cost 431 seconds to establish.

A full scan of all 98 `.crate` files in
`D:\SteamLibrary\steamapps\common\PAYDAY 2\assets` (~30 GB) for the plaintext strings
`material_configs` and `sky_1345_clear_sky` returned **zero hits**.
`crates.shipping_manifest` stores 16-byte GUIDs, not names, and asset paths inside
crates are hashed.

Any future asset lookup must go through Diesel Crate Browser or the in-game
`DB:open(type, idstring)` API. Raw crate scanning will not work.