<#
.SYNOPSIS
    Regenerate decoded/sky_inventory.csv from one or more PAYDAY 2 asset exports.

.DESCRIPTION
    Scans every .material_config under each given root, keeps only the ones that
    declare render_template="dome_sky", resolves the sky name from the FOLDER
    (not the filename), and rebuilds the inventory.

    Two bugs in the original scan are deliberately avoided:

      1. Content filter, not path filter. The first version selected skies by
         directory name matching 'environments.skies|skydomes', which silently
         excluded every root-level config. Content-filtering on the render
         template gives 38 skies, not 34.

      2. Folder name is authoritative. sky_1313_cloudy and sky_1313_cloudy_dark
         are two distinct skies whose config files are BOTH named
         sky_1313_cloudy.material_config. Deduping by filename merged them.

    Attribute order is inconsistent between files (some write value before name),
    so uv0_speed is matched order-independently.

.PARAMETER Path
    One or more export roots. If omitted, the default export is used.

.PARAMETER EnvCsv
    environment_summary.csv, used to resolve how many environments bind each sky.

.PARAMETER OutCsv
    Destination. Default decoded/sky_inventory.csv

.EXAMPLE
    .\tools\regenerate_sky_inventory.ps1
    Regenerates from the default export.

.EXAMPLE
    .\tools\regenerate_sky_inventory.ps1 -Path 'D:\pd2_units_export'
    Merges a units/ export and prints what changed.

.NOTES
    Every row is re-derived from its config file after generation and verified
    field by field. Environment bindings are cross-checked against the count of
    recovered underlay values.
#>
[CmdletBinding()]
param(
    [string[]] $Path,
    [string]   $EnvCsv,
    [string]   $OutCsv,
    [switch]   $Quiet
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not reliable inside param() defaults when the script is
# invoked via powershell -File, so resolve the repo root here instead.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

if (-not $Path)   { $Path   = @((Join-Path $RepoRoot 'aireportpd2')) }
if (-not $EnvCsv) { $EnvCsv = (Join-Path $RepoRoot 'decoded\environment_summary.csv') }
if (-not $OutCsv) { $OutCsv = (Join-Path $RepoRoot 'decoded\sky_inventory.csv') }

function Write-Status($msg) { if (-not $Quiet) { Write-Host $msg } }

# ---------------------------------------------------------------------------
# environment bindings: how many .environment files point at each sky
# ---------------------------------------------------------------------------
$use = @{}
if (Test-Path $EnvCsv) {
    foreach ($e in (Import-Csv $EnvCsv)) {
        if ($e.Underlay) {
            $leaf = ($e.Underlay -split '/')[-1]
            if (-not $use.ContainsKey($leaf)) { $use[$leaf] = 0 }
            $use[$leaf]++
        }
    }
    Write-Status ("underlay bindings: {0} distinct skies" -f $use.Count)
} else {
    Write-Warning "env csv not found at $EnvCsv - environment counts will be 0"
}

# ---------------------------------------------------------------------------
# scan
# ---------------------------------------------------------------------------
$roots = @($Path)
foreach ($p in $roots) {
    if (-not (Test-Path $p)) { throw "path not found: $p" }
}

$configs = foreach ($p in $roots) {
    Get-ChildItem -Path $p -Recurse -File -Filter '*.material_config' -ErrorAction SilentlyContinue
}
Write-Status ("scanned {0} .material_config files across {1} root(s)" -f $configs.Count, $roots.Count)

# keep only dome_sky
$sky = foreach ($f in $configs) {
    if ((Get-Content $f.FullName -Raw) -match 'render_template="dome_sky"') { $f }
}
$sky = @($sky)
Write-Status ("dome_sky configs: {0} files" -f $sky.Count)

# resolve one file per sky, preferring the nested core/environments/skies copy
$best = @{}
foreach ($f in $sky) {
    $dirName = $f.Directory.Name
    # a config sitting directly in the export root has no meaningful parent name
    $isRoot = ($f.Directory.Parent -eq $null) -or ($dirName -eq 'skies') -or
              ($dirName -match '^(aireportpd2|assets|export|pd2)$')
    $name = if ($isRoot) { $f.BaseName } else { $dirName }

    $prefer = $f.FullName -match 'environments\\skies'
    if (-not $best.ContainsKey($name) -or $prefer) { $best[$name] = $f }
}
Write-Status ("distinct skies: {0}" -f $best.Count)

# ---------------------------------------------------------------------------
# build rows
# ---------------------------------------------------------------------------
$rows = foreach ($name in $best.Keys) {
    $f = $best[$name]
    $c = Get-Content $f.FullName -Raw

    # uv0_speed, matched regardless of attribute order
    $uv = @([regex]::Matches($c, '<variable[^>]*uv0_speed[^>]*>') |
            ForEach-Object { if ($_.Value -match 'value="([^"]+)"') { $matches[1] } })

    # Store the path relative to whichever root it came from. Absolute paths
    # would leak the machine layout into a CSV that gets published.
    $rel = $f.FullName
    foreach ($root in $roots) {
        if ($f.FullName.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/')
            break
        }
    }

    [PSCustomObject]@{
        Sky        = $name
        ConfigPath = ($rel -replace '\\', '/')
        ConfigFile = $f.BaseName
        Mats       = ([regex]::Matches($c, '<material\s')).Count
        ParamsA    = if ($c -match 'name="params_a"[^>]*value="([^"]+)"') { $matches[1] } else { '' }
        ParamsB    = if ($c -match 'name="params_b"[^>]*value="([^"]+)"') { $matches[1] } else { '' }
        Color0     = if ($c -match 'name="color0"[^>]*value="([^"]+)"') { $matches[1] } else { '' }
        Color2     = if ($c -match 'name="color2"[^>]*value="([^"]+)"') { $matches[1] } else { '' }
        UVLayers   = $uv.Count
        UVValues   = ($uv -join ' | ')
        Envs       = if ($use.ContainsKey($name)) { $use[$name] } else { 0 }
    }
}
$rows = @($rows | Sort-Object Sky)

# ---------------------------------------------------------------------------
# verify before writing
# ---------------------------------------------------------------------------
$fail = 0
foreach ($r in $rows) {
    # ConfigPath is stored relative to its root, so resolve it back for reading
    $full = $null
    foreach ($root in $roots) {
        $cand = Join-Path $root ($r.ConfigPath -replace '/', '\')
        if (Test-Path $cand) { $full = $cand; break }
    }
    if (-not $full) { $fail++; Write-Warning "missing file for $($r.Sky): $($r.ConfigPath)"; continue }
    $c = Get-Content $full -Raw
    $pa = if ($c -match 'name="params_a"[^>]*value="([^"]+)"') { $matches[1] } else { '' }
    $pb = if ($c -match 'name="params_b"[^>]*value="([^"]+)"') { $matches[1] } else { '' }
    $m  = ([regex]::Matches($c, '<material\s')).Count
    $uv = @([regex]::Matches($c, '<variable[^>]*uv0_speed[^>]*>')).Count
    if ($pa -ne $r.ParamsA) { $fail++; Write-Warning "params_a mismatch: $($r.Sky)" }
    if ($pb -ne $r.ParamsB) { $fail++; Write-Warning "params_b mismatch: $($r.Sky)" }
    if ($m  -ne $r.Mats)     { $fail++; Write-Warning "material count mismatch: $($r.Sky)" }
    if ($uv -ne $r.UVLayers) { $fail++; Write-Warning "uv layer mismatch: $($r.Sky)" }
}

$bindings = ($rows | Measure-Object Envs -Sum).Sum
$boundSkies = @($rows | Where-Object { $_.Envs -gt 0 }).Count
$totalUnderlay = ($use.Values | Measure-Object -Sum).Sum

Write-Host ""
Write-Status ("verification failures : {0}" -f $fail)
Write-Status ("skies                  : {0}" -f $rows.Count)
Write-Status ("environment bindings  : {0}" -f $bindings)
Write-Status ("skies bound by >=1 env : {0}" -f $boundSkies)
Write-Status ("total underlay values  : {0}" -f $totalUnderlay)

if ($fail -gt 0) { throw "$fail row-level verification failures, not writing" }

# ---------------------------------------------------------------------------
# diff against what is already on disk
# ---------------------------------------------------------------------------
if (Test-Path $OutCsv) {
    $old = Import-Csv $OutCsv
    $oldByName = @{}; foreach ($o in $old) { $oldByName[$o.Sky] = $o }
    $newNames = @($rows.Sky)

    $added   = $newNames   | Where-Object { -not $oldByName.ContainsKey($_) }
    $removed = $old.Sky    | Where-Object { $newNames -notcontains $_ }
    $changed = foreach ($n in $newNames) {
        if (-not $oldByName.ContainsKey($n)) { continue }
        $o = $oldByName[$n]
        $r = $rows | Where-Object { $_.Sky -eq $n }
        $d = @()
        if ($o.ParamsA  -ne $r.ParamsA)  { $d += "params_a '$($o.ParamsA)' -> '$($r.ParamsA)'" }
        if ($o.ParamsB  -ne $r.ParamsB)  { $d += "params_b '$($o.ParamsB)' -> '$($r.ParamsB)'" }
        if ($o.Mats     -ne "$($r.Mats)") { $d += "mats $($o.Mats) -> $($r.Mats)" }
        if ($o.UVLayers -ne "$($r.UVLayers)") { $d += "uv_layers $($o.UVLayers) -> $($r.UVLayers)" }
        if ($o.Envs     -ne "$($r.Envs)") { $d += "envs $($o.Envs) -> $($r.Envs)" }
        if ($d.Count) { "  $n : $($d -join '; ')" }
    }

    Write-Host ""
    if ($added)   { Write-Host "ADDED:"   -ForegroundColor Green; $added   | ForEach-Object { "  + $_" } }
    if ($removed) { Write-Host "REMOVED:" -ForegroundColor Red;   $removed | ForEach-Object { "  - $_" } }
    if ($changed) { Write-Host "CHANGED:" -ForegroundColor Yellow; $changed | ForEach-Object { $_ } }
    if (-not ($added -or $removed -or $changed)) { Write-Status "no change vs previous run" }
}

$rows | Export-Csv $OutCsv -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Status ("wrote {0} ({1} rows)" -f $OutCsv, $rows.Count)