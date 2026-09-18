<#
.SYNOPSIS
    Builds the TRS-80 Color Computer 1/2 version of Matrix Rain.

.DESCRIPTION
    Assembles matrix_rain_coco.asm with LWTOOLS into matrix_rain_coco.bin,
    then writes the cassette and disk images matrix_rain_coco.cas and
    matrix_rain_coco.dsk from it. The program is MATRIX on tape and
    MATRIX.BIN on disk.

    -Run    opens the .bin in XRoar.
    -Test   checks the program in XRoar, with no window:
              1. After 400 frames, screen RAM matches what
                 matrix_rain_coco.c leaves after 400 frames under cc65's
                 6502 simulator.
              2. Nothing outside the screen and the program's own memory
                 changes while it runs.
            These use test builds, assembled with TESTFRAMES=n so that
            the main loop parks after n frames. XRoar writes a snapshot
            some time after the trap that asks for it, so the program
            has to be holding still by then.

.EXAMPLE
    .\build-coco.ps1
    .\build-coco.ps1 -Run
    .\build-coco.ps1 -Test
#>

[CmdletBinding()]
param(
    [switch] $Run,
    [switch] $Test,
    [string] $Lwtools = 'C:\Development\_VintageDevelopment\lwtools\bin',
    [string] $XRoar   = 'C:\Program Files\6809.org.uk\XRoar 1.9\xroar.exe',
    [string] $Cc65    = 'C:\Development\_VintageDevelopment\cc65_snapshot',
    [string] $Roms    = (Join-Path $env:USERPROFILE 'Documents\XRoar\ROMS'),
    [string] $Machine = 'coco2bus'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools\xroar.ps1')
. (Join-Path $PSScriptRoot 'tools\coco_images.ps1')

$lwasm  = Join-Path $Lwtools 'lwasm.exe'
$source = Join-Path $PSScriptRoot 'matrix_rain_coco.asm'
$bin    = Join-Path $PSScriptRoot 'matrix_rain_coco.bin'
$cas    = Join-Path $PSScriptRoot 'matrix_rain_coco.cas'
$dsk    = Join-Path $PSScriptRoot 'matrix_rain_coco.dsk'
$work   = Join-Path $env:TEMP 'matrix_rain_coco'
New-Item -ItemType Directory -Force $work | Out-Null

if (-not (Test-Path $lwasm))  { throw "lwasm not found at $lwasm. Pass -Lwtools <folder holding lwasm.exe>." }
if (-not (Test-Path $source)) { throw "$source not found." }

# Assembles the program and returns the .bin path and its label
# addresses. With $Frames of 0 or more it is a test build that parks
# at testdone after that many frames.
function Build-Coco([string] $Out, [int] $Frames = -1) {
    $symbols = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($Out) + '.sym')
    $defines = if ($Frames -ge 0) { @('-D', "TESTFRAMES=$Frames") } else { @() }
    & $lwasm --decb @defines -o $Out "--symbol-dump=$symbols" $source
    if ($LASTEXITCODE -ne 0) { throw "lwasm failed on $source" }
    [pscustomobject] @{ Bin = $Out; Labels = (Read-LwasmSymbols $symbols) }
}

$release = Build-Coco $bin
New-CocoCas -Bin $bin -Name 'MATRIX' -Path $cas
New-CocoDsk -Bin $bin -Name 'MATRIX' -Path $dsk
Write-Host ('Built matrix_rain_coco.bin ({0:n0} bytes), matrix_rain_coco.cas and matrix_rain_coco.dsk' -f (Get-Item $bin).Length)

if ($Run) {
    if (-not (Test-Path $XRoar)) { throw "XRoar not found at $XRoar. Pass -XRoar <path to xroar.exe>." }
    # Start-Process, so XRoar runs in its own window until closed and
    # never reads this console.
    $proc = Start-Process $XRoar -ArgumentList '-machine', $Machine, '-run', (ConvertTo-XRoarPath $bin) -PassThru
    Write-Host ('Launched in XRoar (PID {0}). Close the window to stop it.' -f $proc.Id)
}

if ($Test) {
    if (-not (Test-Path $XRoar)) { throw "XRoar not found at $XRoar. Pass -XRoar <path to xroar.exe>." }
    $cl65   = Join-Path $Cc65 'bin\cl65.exe'
    $sim65  = Join-Path $Cc65 'bin\sim65.exe'
    $frames = 400
    $screen = 0x0400
    $size   = 512

    # Runs a test build until it parks, and returns its RAM and build.
    function Get-ParkedRam([int] $Frames) {
        $build = Build-Coco (Join-Path $work "test$Frames.bin") $Frames
        $snap  = Join-Path $work "test$Frames.sna"
        if (Test-Path $snap) { Remove-Item $snap }
        $null = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Machine $Machine -Log "test$Frames.log" -Arguments @(
            '-run', (ConvertTo-XRoarPath $build.Bin),
            '-trap', ('pc=0x{0:X4}' -f $build.Labels['testdone']),
            '-trap-snap', (ConvertTo-XRoarPath $snap), '-trap-timeout', '1')
        if (-not (Test-Path $snap)) { throw "The $Frames-frame test build never reached testdone. XRoar's log: $work\test$Frames.log" }
        [pscustomobject] @{ Ram = (Read-XRoarRam $snap); Build = $build }
    }

    # 1. Screen RAM after 400 frames matches the reference model's.
    $reference = Join-Path $work 'reference.bin'
    & $cl65 -t sim6502 -Oi -Cl -DSIM_RAW "-DSIM_FRAMES=$frames" -o $reference (Join-Path $PSScriptRoot 'matrix_rain_coco.c')
    if ($LASTEXITCODE -ne 0) { throw 'The reference model did not build.' }
    $expected = @(& $sim65 $reference | ForEach-Object { [Convert]::ToByte($_, 16) })
    if ($expected.Count -ne $size) { throw "The reference model printed $($expected.Count) bytes, not $size." }

    $after = Get-ParkedRam $frames
    $ram   = $after.Ram

    # The code and tables must be intact in memory. This also shows the
    # snapshot was read from the right place.
    $image = (Read-DecbBin $after.Build.Bin).Segments[0]
    for ($addr = $after.Build.Labels['start']; $addr -lt $image.Address + $image.Bytes.Length; $addr++) {
        if ($ram[$addr] -ne $image.Bytes[$addr - $image.Address]) {
            throw ('The program in memory differs from its .bin at ${0:X4}: the snapshot was misread, or the program wrote over itself.' -f $addr)
        }
    }

    Write-Host "`nScreen after $frames frames ('.' empty, '*' letter, '#' highlighted letter, 'o' block, '@' highlighted block):`n"
    for ($row = 0; $row -lt 16; $row++) {
        $line = foreach ($c in 0..31) {
            $v = $ram[$screen + $row * 32 + $c]
            if ($v -eq 0x80)       { '.' }
            elseif ($v -band 0x80) { if ($v -band 0x40) { '@' } else { 'o' } }
            elseif ($v -band 0x40) { '#' }
            else                   { '*' }
        }
        Write-Host (-join $line)
    }

    $diff = @(0..($size - 1) | Where-Object { $ram[$screen + $_] -ne $expected[$_] })
    if ($diff.Count) {
        $at = $diff[0]
        throw ('Screen RAM differs from the reference model''s in {0} of {1} bytes after {2} frames. The first is at ${3:X4}: the CoCo has ${4:X2}, the reference ${5:X2}.' -f `
            $diff.Count, $size, $frames, ($screen + $at), $ram[$screen + $at], $expected[$at])
    }
    Write-Host ("`nScreen RAM: all {0} bytes match the reference model after {1} frames" -f $size, $frames)

    # 2. From the moment setup finishes to 400 frames later, nothing
    #    outside the screen and the program's own memory changes.
    $before  = (Get-ParkedRam 0).Ram
    $ownEnd  = $after.Build.Labels['progend']
    $changed = @(for ($addr = 0; $addr -lt $ram.Length; $addr++) {
        if ($addr -ge $screen -and $addr -lt $screen + $size) { continue }
        if ($addr -ge 0x0E00 -and $addr -lt $ownEnd) { continue }
        if ($ram[$addr] -ne $before[$addr]) { $addr }
    })
    if ($changed.Count) {
        throw ('{0} bytes outside the screen and the program changed while it ran. The first is at ${1:X4}.' -f $changed.Count, $changed[0])
    }
    Write-Host 'Other RAM:  unchanged while it ran'
    return
}
