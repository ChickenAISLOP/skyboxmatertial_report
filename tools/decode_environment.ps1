<#
  decode_environment.ps1  --  PAYDAY 2 .environment (Overkill "Oxml") decoder

  Usage:
    .\decode_environment.ps1 -Path "<file.environment>"            # human-readable dump
    .\decode_environment.ps1 -Path "<folder>" -Recurse -JsonOut x   # batch JSON

  Container layout (verified against all 225 exported .environment files):

    0x000  u64  version / flags (0)
    0x008  u64  floatPoolCount
    0x010  u64  floatPoolCount (repeat)
    0x018  u64  floatPoolOffset
    0x020  u64  0
    0x028  u64  stringCount
    0x030  u64  stringCount (repeat)
    0x038  u64  stringRecordTableOffset   (records actually begin at +8)
    0x040  u64  0
    0x048  u64  nodeBlockDepth / complexity tier (10..29)
    0x050  u64  same (repeat)
    0x058  u64  end of string region == start of node/value block
    floatPoolOffset          floatPoolCount * float32
    stringRecordTable+8      stringCount * { u32 offset; u32 pad[3] }
    strings                  NUL-separated ASCII
    node/value block         variable-length records (SEE LIMITATION BELOW)
    tag stream               [u8 tag][u8 value][u8 0][u8 0] * N

  Tag stream semantics (verified):
    tag 0x00  (no data)
    tag 0x03  string reference  (leaf / value slot)
    tag 0x04  string reference
    tag 0x05  float, indexed into the float pool
    tag 0x08  string reference  (element / container name)

  LIMITATION: the node/value block is NOT decoded. It is variable-length per
  record (mixes float32 and integer fields) and the numeric values that belong
  to each key live there. Key names, string values and pool floats ARE decoded.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Path,
  [switch]$Recurse,
  [string]$JsonOut
)

function Read-Environment([string]$file){
  $b = [System.IO.File]::ReadAllBytes($file)

  $fpc = [int][BitConverter]::ToInt64($b,0x008)
  $fpo = [int][BitConverter]::ToInt64($b,0x018)
  $sc  = [int][BitConverter]::ToInt64($b,0x028)
  $srt = [int][BitConverter]::ToInt64($b,0x038)
  $sre = [int][BitConverter]::ToInt64($b,0x058)
  $aux = [int][BitConverter]::ToInt64($b,0x048)

  # string table: record i lives at srt+8+i*16, first u32 is the byte offset
  $strs = New-Object System.Collections.Generic.List[string]
  for($i=0; $i -lt $sc; $i++){
    $off = [BitConverter]::ToInt32($b, $srt + 8 + $i*16)
    if($off -le 0 -or $off -ge $b.Length){ $strs.Add(""); continue }
    $e = $off
    while($e -lt $b.Length -and $b[$e] -ne 0){ $e++ }
    $strs.Add([System.Text.Encoding]::ASCII.GetString($b,$off,$e-$off))
  }

  # float pool: mixed string-index and literal constants, first-use order
  $pool = New-Object System.Collections.Generic.List[double]
  for($i=0; $i -lt $fpc; $i++){ $pool.Add([double][BitConverter]::ToSingle($b,$fpo+$i*4)) }

  # locate tag stream: longest run of [tag][val][0][0] words with tag < 0x40
  $stream=0; $words=0
  for($s=$sre; $s -lt $b.Length-16; $s++){
    $n=0
    while($s+$n*4+3 -lt $b.Length){
      $w=$s+$n*4
      if($b[$w+2] -eq 0 -and $b[$w+3] -eq 0 -and $b[$w] -lt 0x40 -and $b[$w+1] -lt 0x40){ $n++ } else { break }
    }
    if($n -gt $words){ $words=$n; $stream=$s }
  }

  # decode tag stream
  $tags = New-Object System.Collections.Generic.List[string]
  for($i=0; $i -lt $words; $i++){
    $w=$stream+$i*4; $t=$b[$w]; $v=$b[$w+1]
    switch($t){
      5 { if($v -lt $pool.Count){ $tags.Add("FLOAT $($pool[$v])") } else { $tags.Add("FLOAT ?$v") } }
      0 { $tags.Add("-") }
      default { if($v -lt $strs.Count){ $tags.Add($strs[$v]) } else { $tags.Add("?$v") } }
    }
  }

  # node/value block: emit float32 candidates only (structure not decoded)
  $blockLen = $stream - $sre
  $floats = New-Object System.Collections.Generic.List[double]
  for($i=$sre; $i+3 -lt $stream; $i+=4){
    $v=[BitConverter]::ToSingle($b,$i)
    if(-not [double]::IsNaN($v) -and [Math]::Abs($v) -lt 1e6 -and $v -ne 0){ $floats.Add([double]$v) }
  }

  # Tier classification is by string presence, NOT by the aux counter.
  # aux (0x048) is a complexity/depth counter that does not map cleanly to tiers:
  # env_asset_texturing has aux=15 but is Tier 3; pd2_ff_2 has aux=18 but is Tier 2.
  $hasSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$strs)
  $tier = if($hasSet.Contains('tone_mapping')){ if($hasSet.Contains('sun_anim')){ 3 } else { 2 } } else { 1 }

  [PSCustomObject]@{
    file      = [System.IO.Path]::GetFileNameWithoutExtension($file)
    bytes     = $b.Length
    tier      = $tier
    aux       = $aux
    strings   = $strs.ToArray()
    pool      = $pool.ToArray()
    tagStream = $tags.ToArray()
    blockLen  = $blockLen
    blockFloats = $floats.ToArray()
  }
}

$STRUCT = @('environment','metadata','data','sky_orientation','param','key','value','others',
            'post_effect','deferred','deferred_lighting','apply_ambient','shadow_processor',
            'shadow_rendering','shadow_modifier','underlay_effect','sky')

if($Recurse){
  $files = Get-ChildItem -Path $Path -Recurse -File -Filter *.environment
} elseif(Test-Path $Path -PathType Container){
  $files = Get-ChildItem -Path $Path -Recurse -File -Filter *.environment
} else {
  $files = @(Get-Item $Path)
}

$all = New-Object System.Collections.Generic.List[object]
foreach($f in $files){ $all.Add((Read-Environment $f.FullName)) }

if($JsonOut){
  $all | ConvertTo-Json -Depth 6 | Set-Content -Path $JsonOut -Encoding UTF8
  "wrote $JsonOut  ($($all.Count) environments)"
  return
}

foreach($e in $all){
  "########## $($e.file)  [tier $($e.tier)]  $($e.bytes) bytes ##########"
  ""
  "-- keys --"
  $i=0
  foreach($s in $e.strings){
    $kind = if($STRUCT -contains $s){ 'struct' } elseif($s -match '/'){ 'path' } else { 'KEY' }
    if($kind -eq 'KEY'){ "  [$i] $s" }
    $i++
  }
  ""
  "-- decoded tag stream ($($e.tagStream.Count)) --"
  $e.tagStream -join ' | '
  ""
  "-- node/value block: $($e.blockLen) bytes, $($e.blockFloats.Count) float32 candidates --"
  ($e.blockFloats | Select-Object -First 40) -join ', '
  ""
}