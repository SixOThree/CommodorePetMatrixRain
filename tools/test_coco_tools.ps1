<#
.SYNOPSIS
    Tests for the CoCo helpers in tools\coco_images.ps1 and tools\xroar.ps1.

.DESCRIPTION
    Assembles tools\fixtures\fill.asm and checks the .bin reader and the
    cassette and disk image writers. Prints PASS, FAIL or SKIP for each
    check and exits 1 if any failed.
#>

[CmdletBinding()]
param(
    [string] $Lwtools = 'C:\Development\_VintageDevelopment\lwtools\bin',
    [string] $XRoar   = 'C:\Program Files\6809.org.uk\XRoar 1.9\xroar.exe',
    [string] $Roms    = (Join-Path $env:USERPROFILE 'Documents\XRoar\ROMS')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'coco_images.ps1')

$work = Join-Path $env:TEMP 'coco_tools_test'
New-Item -ItemType Directory -Force $work | Out-Null
$script:failures = 0

function Check([string] $What, [bool] $Ok, [string] $Detail = '') {
    if ($Ok) { Write-Host "PASS  $What" }
    else     { Write-Host "FAIL  $What  $Detail"; $script:failures++ }
}

function Hex([byte[]] $Bytes) { [Convert]::ToHexString($Bytes) }

# A DECB .bin written by hand: one segment per entry of $Segments, each
# @(address, length), filled with the low byte of each byte's address.
function New-TestBin([string] $Path, [object[]] $Segments, [int] $Exec) {
    $out = [Collections.Generic.List[byte]]::new()
    foreach ($s in $Segments) {
        $address, $length = $s
        $out.AddRange([byte[]] (0x00, ($length -shr 8), ($length -band 0xFF), ($address -shr 8), ($address -band 0xFF)))
        for ($i = 0; $i -lt $length; $i++) { $out.Add([byte] (($address + $i) -band 0xFF)) }
    }
    $out.AddRange([byte[]] (0xFF, 0x00, 0x00, ($Exec -shr 8), ($Exec -band 0xFF)))
    [IO.File]::WriteAllBytes($Path, $out.ToArray())
}

# The fixture: see tools\fixtures\fill.asm.
$bin = Join-Path $work 'fill.bin'
$sym = Join-Path $work 'fill.sym'
& (Join-Path $Lwtools 'lwasm.exe') --decb -o $bin "--symbol-dump=$sym" (Join-Path $PSScriptRoot 'fixtures\fill.asm')
if ($LASTEXITCODE -ne 0) { throw 'tools\fixtures\fill.asm did not assemble' }
$binBytes = [IO.File]::ReadAllBytes($bin)

# --- Read-DecbBin ---
$fixture = Read-DecbBin $bin
Check 'Read-DecbBin: one segment, loading at $0E00' ($fixture.Segments.Count -eq 1 -and $fixture.Segments[0].Address -eq 0x0E00)
Check 'Read-DecbBin: the segment is the whole file less its 10 bytes of framing' ($fixture.Segments[0].Bytes.Length -eq $binBytes.Length - 10)
Check 'Read-DecbBin: exec address $0E00' ($fixture.Exec -eq 0x0E00)

# --- New-CocoCas ---
$cas = Join-Path $work 'fill.cas'
New-CocoCas -Bin $bin -Name 'FILL' -Path $cas
$c = [IO.File]::ReadAllBytes($cas)
Check 'cassette: starts with 128 leader bytes' (@($c[0..127] | Where-Object { $_ -ne 0x55 }).Count -eq 0)
Check 'cassette: then a 15-byte name block' ($c[128] -eq 0x55 -and $c[129] -eq 0x3C -and $c[130] -eq 0x00 -and $c[131] -eq 15)
$name = [Text.Encoding]::ASCII.GetString($c, 132, 8)
Check 'cassette: the name is FILL' ($name -eq 'FILL    ') "got '$name'"
Check 'cassette: machine code, binary, no gaps' ($c[140] -eq 2 -and $c[141] -eq 0 -and $c[142] -eq 0)
Check 'cassette: exec and load addresses $0E00' ($c[143] -eq 0x0E -and $c[144] -eq 0 -and $c[145] -eq 0x0E -and $c[146] -eq 0)
$sum = 0; for ($i = 130; $i -lt 147; $i++) { $sum += $c[$i] }
Check 'cassette: name block checksum' ($c[147] -eq ($sum % 256) -and $c[148] -eq 0x55)
Check 'cassette: second leader' (@($c[149..276] | Where-Object { $_ -ne 0x55 }).Count -eq 0)

# Walks the data blocks from $At and returns the bytes they carry, or
# $null if any block is malformed or anything follows the end block.
function Read-CasData([byte[]] $C, [int] $At) {
    $data = [Collections.Generic.List[byte]]::new()
    while ($true) {
        if ($C[$At] -ne 0x55 -or $C[$At + 1] -ne 0x3C) { return $null }
        $type = $C[$At + 2]; $len = $C[$At + 3]
        $sum = $type + $len
        for ($i = 0; $i -lt $len; $i++) {
            $sum += $C[$At + 4 + $i]
            if ($type -eq 1) { $data.Add($C[$At + 4 + $i]) }
        }
        if ($C[$At + 4 + $len] -ne ($sum % 256) -or $C[$At + 5 + $len] -ne 0x55) { return $null }
        $At += 6 + $len
        if ($type -eq 0xFF) { break }
        if ($type -ne 1) { return $null }
    }
    if ($At -ne $C.Length) { return $null }
    ,$data.ToArray()
}
$data = Read-CasData $c 277
Check 'cassette: well-formed data blocks and end block' ($null -ne $data)
Check 'cassette: the data blocks hold the program' ($null -ne $data -and (Hex $data) -eq (Hex $fixture.Segments[0].Bytes))

$big = Join-Path $work 'big.bin'
New-TestBin $big @(, @(0x2000, 600)) 0x2000
$bigCas = Join-Path $work 'big.cas'
New-CocoCas -Bin $big -Name 'BIG' -Path $bigCas
$bc = [IO.File]::ReadAllBytes($bigCas)
Check 'cassette: 600 bytes split 255 + 255 + 90' ($bc[280] -eq 255 -and $bc[280 + 261] -eq 255 -and $bc[280 + 522] -eq 90)
$bigData = Read-CasData $bc 277
Check 'cassette: split blocks reassemble' ($null -ne $bigData -and (Hex $bigData) -eq (Hex (Read-DecbBin $big).Segments[0].Bytes))

$two = Join-Path $work 'two.bin'
New-TestBin $two @(@(0x2000, 10), @(0x3000, 10)) 0x2000
$refused = $false
try { New-CocoCas -Bin $two -Name 'TWO' -Path (Join-Path $work 'two.cas') } catch { $refused = $true }
Check 'cassette: refuses a .bin with two segments' $refused

# --- New-CocoDsk ---
$dsk = Join-Path $work 'fill.dsk'
New-CocoDsk -Bin $bin -Name 'FILL' -Path $dsk
$k = [IO.File]::ReadAllBytes($dsk)
$fat = (17 * 18 + 1) * 256          # track 17, sector 2
$dir = (17 * 18 + 2) * 256          # track 17, sector 3
Check 'disk: 35 tracks of 18 sectors of 256 bytes' ($k.Length -eq 161280)
Check 'disk: directory entry FILL.BIN' ([Text.Encoding]::ASCII.GetString($k, $dir, 11) -eq 'FILL    BIN')
Check 'disk: machine code, binary, starting in granule 0' ($k[$dir + 11] -eq 2 -and $k[$dir + 12] -eq 0 -and $k[$dir + 13] -eq 0)
Check 'disk: bytes in the last sector' (($k[$dir + 14] * 256 + $k[$dir + 15]) -eq $binBytes.Length) 'fill.bin fits in one sector'
Check 'disk: the next directory entry is unused' ($k[$dir + 32] -eq 0xFF)
Check 'disk: granule 0 is the last, using 1 sector' ($k[$fat] -eq 0xC1)
Check 'disk: the other 67 granules are free' (@(1..67 | Where-Object { $k[$fat + $_] -ne 0xFF }).Count -eq 0)
Check 'disk: granule 0 holds the .bin as is' ((Hex $k[0..($binBytes.Length - 1)]) -eq (Hex $binBytes))

$long = Join-Path $work 'long.bin'
New-TestBin $long @(, @(0x2000, 3000)) 0x2000
$longDsk = Join-Path $work 'long.dsk'
New-CocoDsk -Bin $long -Name 'LONG' -Path $longDsk
$lk = [IO.File]::ReadAllBytes($longDsk)
$longBytes = [IO.File]::ReadAllBytes($long)
Check 'disk: a 3,010-byte file chains granule 0 to granule 1' ($lk[$fat] -eq 1 -and $lk[$fat + 1] -eq 0xC3)
Check 'disk: and fills them in order' ((Hex $lk[0..3009]) -eq (Hex $longBytes))
Check 'disk: 194 bytes in its last sector' (($lk[$dir + 14] * 256 + $lk[$dir + 15]) -eq 194)

# --- XRoar ---
if (-not (Test-Path $XRoar)) { throw "XRoar not found at $XRoar" }
. (Join-Path $PSScriptRoot 'xroar.ps1')

$labels = Read-LwasmSymbols $sym
Check 'Read-LwasmSymbols: finds start, mainloop, waitsync and done' (
    $labels['start'] -eq 0x0E00 -and $labels.ContainsKey('mainloop') -and $labels.ContainsKey('waitsync') -and $labels.ContainsKey('done'))

# Runs the fixture until it parks at DONE and returns its RAM, or $null.
function Get-FixtureRam([string] $What, [string[]] $Load) {
    $snap = Join-Path $work "$What.sna"
    if (Test-Path $snap) { Remove-Item $snap }
    $null = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Log "$What.log" -Arguments ($Load + @(
        '-trap', ('pc=0x{0:X4}' -f $labels['done']),
        '-trap-snap', (ConvertTo-XRoarPath $snap), '-trap-timeout', '1'))
    if (-not (Test-Path $snap)) { return $null }
    Read-XRoarRam $snap
}

function Test-FixtureRam([string] $What, $Ram) {
    if ($null -eq $Ram) { Check "$What`: reaches DONE" $false "no snapshot, see $work\$What.log"; return }
    Check "$What`: reaches DONE" $true
    Check "$What`: the snapshot holds 64K of RAM" ($Ram.Length -eq 65536) "got $($Ram.Length)"
    $bad = @(0..511 | Where-Object { $Ram[0x400 + $_] -ne ($_ % 256) })
    Check "$What`: the screen holds the fixture's pattern" ($bad.Count -eq 0) "$($bad.Count) bytes wrong"
    $seg  = $fixture.Segments[0]
    $code = [byte[]]::new($seg.Bytes.Length)
    [Array]::Copy($Ram, $seg.Address, $code, 0, $code.Length)
    Check "$What`: the program sits where it was loaded" ((Hex $code) -eq (Hex $seg.Bytes))
}

Test-FixtureRam 'bin' (Get-FixtureRam 'bin' @('-run', (ConvertTo-XRoarPath $bin)))
Test-FixtureRam 'cassette' (Get-FixtureRam 'cassette' @('-load-tape', (ConvertTo-XRoarPath $cas), '-type', 'CLOADM:EXEC\r'))
if ((Test-Path (Join-Path $Roms 'disk11.rom')) -or (Test-Path (Join-Path $Roms 'disk10.rom'))) {
    Test-FixtureRam 'disk' (Get-FixtureRam 'disk' @('-machine-cart', 'rsdos', '-load-fd0', (ConvertTo-XRoarPath $dsk), '-type', 'LOADM\"FILL\":EXEC\r'))
} else {
    Write-Host "SKIP  disk: no disk11.rom or disk10.rom in $Roms"
}

$trace = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Log 'fill.trace' -Arguments @(
    '-trace-timing', '-run', (ConvertTo-XRoarPath $bin),
    '-trap', ('pc=0x{0:X4}' -f $labels['mainloop']), '-trap-range', '2', '-trap-trace',
    '-trap', ('pc=0x{0:X4}' -f $labels['done']), '-trap-timeout', '1')
$wait = $labels['waitsync']
$frames = @(Measure-XRoarTrace -Trace $trace -FrameStart $labels['mainloop'] -Stop $labels['done'] -Idle @($wait, ($wait + 3)))
Remove-Item $trace
Check 'trace: 10 whole frames between the 2nd pass and DONE' ($frames.Count -eq 10) "got $($frames.Count)"
Check 'trace: every frame does exactly 523 cycles of work' (@($frames | Where-Object { $_.Busy -ne 523 }).Count -eq 0) (($frames | ForEach-Object Busy) -join ', ')
$field = ($frames | Measure-Object Total -Average).Average
Check 'trace: a frame lasts one NTSC field, 14,934 cycles' ($field -gt 14900 -and $field -lt 14970) "average $field"

# --- summary ---
Write-Host ''
if ($script:failures) { Write-Host "$($script:failures) check(s) failed"; exit 1 }
Write-Host 'All checks passed'
