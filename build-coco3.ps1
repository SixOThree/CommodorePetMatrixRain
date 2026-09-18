<#
.SYNOPSIS
    Builds the TRS-80 Color Computer 3 version of Matrix Rain.

.DESCRIPTION
    Assembles matrix_rain_coco3.asm twice with LWTOOLS:

      matrix_rain_coco3.bin       80x24 for an RGB monitor
      matrix_rain_coco3_cmp.bin   40x24 for a TV or composite monitor

    then writes a cassette image of each, matrix_rain_coco3.cas and
    matrix_rain_coco3_cmp.cas, and one disk image holding both,
    matrix_rain_coco3.dsk. The programs are MATRIX3 and MATRIX3C on tape
    and disk.

    -Run              opens the RGB build in XRoar, set to an RGB monitor.
    -Run -Composite   opens the composite build, XRoar set to composite.
    -Test             checks both builds in XRoar, with no window:
              1. After 400 frames, screen RAM, characters and attributes,
                 matches what matrix_rain_coco3.c leaves after 400 frames
                 under cc65's 6502 simulator.
              2. Nothing in the 512K outside the screen and the program's
                 own memory changes while it runs.
              3. The cassette images load with CLOADM and run, and the
                 disk image with LOADM when Disk BASIC's ROM is in the
                 ROM folder; otherwise the disk check is skipped.
              4. It reports the cycles a frame takes, from a trace.
            Checks 1, 2 and 4 use test builds, assembled with TESTFRAMES=n
            so that the main loop parks after n frames. XRoar writes a
            snapshot some time after the trap that asks for it, so the
            program has to be holding still by then.

.EXAMPLE
    .\build-coco3.ps1
    .\build-coco3.ps1 -Run
    .\build-coco3.ps1 -Run -Composite
    .\build-coco3.ps1 -Test
#>

[CmdletBinding()]
param(
    [switch] $Run,
    [switch] $Composite,
    [switch] $Test,
    [string] $Lwtools = 'C:\Development\_VintageDevelopment\lwtools\bin',
    [string] $XRoar   = 'C:\Program Files\6809.org.uk\XRoar 1.9\xroar.exe',
    [string] $Cc65    = 'C:\Development\_VintageDevelopment\cc65_snapshot',
    [string] $Roms    = (Join-Path $env:USERPROFILE 'Documents\XRoar\ROMS')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools\xroar.ps1')
. (Join-Path $PSScriptRoot 'tools\coco_images.ps1')

$lwasm     = Join-Path $Lwtools 'lwasm.exe'
$source    = Join-Path $PSScriptRoot 'matrix_rain_coco3.asm'
$reference = Join-Path $PSScriptRoot 'matrix_rain_coco3.c'
$dsk       = Join-Path $PSScriptRoot 'matrix_rain_coco3.dsk'
$work      = Join-Path $env:TEMP 'matrix_rain_coco3'
New-Item -ItemType Directory -Force $work | Out-Null

if (-not (Test-Path $lwasm))  { throw "lwasm not found at $lwasm. Pass -Lwtools <folder holding lwasm.exe>." }
if (-not (Test-Path $source)) { throw "$source not found." }

$screen = 0x2000         # the screen, as the program sees it
$rows   = 24

# BASIC's memory map puts logical $0000 at physical $70000, and a 512K
# snapshot holds RAM in physical order.
$physical = 0x70000

$builds = @(
    [pscustomobject] @{
        Name = 'rgb'; Defines = @(); Cols = 80; Tv = 'rgb'; Tape = 'MATRIX3'
        Bin = (Join-Path $PSScriptRoot 'matrix_rain_coco3.bin')
        Cas = (Join-Path $PSScriptRoot 'matrix_rain_coco3.cas')
    }
    [pscustomobject] @{
        Name = 'composite'; Defines = @('COMPOSITE'); Cols = 40; Tv = 'cmp-br'; Tape = 'MATRIX3C'
        Bin = (Join-Path $PSScriptRoot 'matrix_rain_coco3_cmp.bin')
        Cas = (Join-Path $PSScriptRoot 'matrix_rain_coco3_cmp.cas')
    }
)

# Assembles one build and returns the .bin path and its label addresses.
# With $Frames of 0 or more it is a test build that parks at testdone
# after that many frames.
function Build-Coco3($Build, [string] $Out, [int] $Frames = -1) {
    $symbols = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($Out) + '.sym')
    $defines = @(foreach ($name in $Build.Defines) { '-D', $name })
    if ($Frames -ge 0) { $defines += @('-D', "TESTFRAMES=$Frames") }
    & $lwasm --decb @defines -o $Out "--symbol-dump=$symbols" $source
    if ($LASTEXITCODE -ne 0) { throw "lwasm failed on $source ($($Build.Name) build)" }
    [pscustomobject] @{ Bin = $Out; Labels = (Read-LwasmSymbols $symbols) }
}

$release = @{}
foreach ($b in $builds) {
    $release[$b.Name] = Build-Coco3 $b $b.Bin
    New-CocoCas -Bin $b.Bin -Name $b.Tape -Path $b.Cas
}
New-CocoDsk -Bin @($builds | ForEach-Object Bin) -Name @($builds | ForEach-Object Tape) -Path $dsk
foreach ($b in $builds) {
    Write-Host ('Built {0} ({1:n0} bytes) and {2}' -f (Split-Path $b.Bin -Leaf), (Get-Item $b.Bin).Length, (Split-Path $b.Cas -Leaf))
}
Write-Host ('Built {0} holding both' -f (Split-Path $dsk -Leaf))

if ($Run) {
    if (-not (Test-Path $XRoar)) { throw "XRoar not found at $XRoar. Pass -XRoar <path to xroar.exe>." }
    $b = if ($Composite) { $builds[1] } else { $builds[0] }
    # Start-Process, so XRoar runs in its own window until closed and
    # never reads this console.
    $proc = Start-Process $XRoar -ArgumentList '-machine', 'coco3', '-ram', '512', '-tv-input', $b.Tv, '-run', (ConvertTo-XRoarPath $b.Bin) -PassThru
    Write-Host ('Launched the {0} build in XRoar (PID {1}). Close the window to stop it.' -f $b.Name, $proc.Id)
}

if ($Test) {
    if (-not (Test-Path $XRoar)) { throw "XRoar not found at $XRoar. Pass -XRoar <path to xroar.exe>." }
    $cl65       = Join-Path $Cc65 'bin\cl65.exe'
    $sim65      = Join-Path $Cc65 'bin\sim65.exe'
    $testFrames = 400

    # Runs a test build until it parks, and returns its RAM and build.
    function Get-ParkedRam($Build, [int] $Frames) {
        $tb   = Build-Coco3 $Build (Join-Path $work "$($Build.Name)_test$Frames.bin") $Frames
        $snap = Join-Path $work "$($Build.Name)_test$Frames.sna"
        if (Test-Path $snap) { Remove-Item $snap }
        $null = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Machine 'coco3' -Log "$($Build.Name)_test$Frames.log" -Arguments @(
            '-ram', '512', '-run', (ConvertTo-XRoarPath $tb.Bin),
            '-trap', ('pc=0x{0:X4}' -f $tb.Labels['testdone']),
            '-trap-snap', (ConvertTo-XRoarPath $snap), '-trap-timeout', '1')
        if (-not (Test-Path $snap)) {
            throw "The $($Build.Name) $Frames-frame test build never reached testdone. XRoar's log: $work\$($Build.Name)_test$Frames.log"
        }
        [pscustomobject] @{ Ram = (Read-XRoarRam $snap); Build = $tb }
    }

    # The first offset from $Start up to $End where two byte arrays
    # differ, or -1.
    function Find-Difference([byte[]] $A, [byte[]] $B, [int] $Start, [int] $End) {
        if ($End -le $Start) { return -1 }
        $n = $End - $Start
        if ([Convert]::ToHexString($A, $Start, $n) -eq [Convert]::ToHexString($B, $Start, $n)) { return -1 }
        for ($i = $Start; $i -lt $End; $i++) { if ($A[$i] -ne $B[$i]) { return $i } }
        -1
    }

    # Checks that the bytes of a build's .bin, from its start label on,
    # sit in RAM where they were loaded.
    function Test-Loaded([byte[]] $Ram, $Built, [string] $What) {
        $image = (Read-DecbBin $Built.Bin).Segments[0]
        $from  = $Built.Labels['start'] - $image.Address
        $want  = [byte[]]::new($image.Bytes.Length - $from)
        [Array]::Copy($image.Bytes, $from, $want, 0, $want.Length)
        $got   = [byte[]]::new($want.Length)
        [Array]::Copy($Ram, $physical + $Built.Labels['start'], $got, 0, $got.Length)
        $at = Find-Difference $got $want 0 $want.Length
        if ($at -ge 0) {
            throw ('{0}: the program in memory differs from its .bin at ${1:X4}.' -f $What, ($Built.Labels['start'] + $at))
        }
    }

    # Prints a screen as text: '.' empty, 'H' head, 'R' reversed head,
    # '%' a foreign letter in a trail, then '+' bright green, '*' green,
    # ':' dark green.
    function Write-Screen([byte[]] $Cells, [int] $Cols) {
        for ($r = 0; $r -lt $rows; $r++) {
            $line = foreach ($c in 0..($Cols - 1)) {
                $ch = $Cells[($r * $Cols + $c) * 2]
                $at = $Cells[($r * $Cols + $c) * 2 + 1]
                if ($ch -eq 0x20)    { '.' }
                elseif ($at -eq 0x00) { 'H' }
                elseif ($at -eq 0x21) { 'R' }
                elseif ($ch -lt 0x20) { '%' }
                elseif ($at -eq 0x08) { '+' }
                elseif ($at -eq 0x10) { '*' }
                else                  { ':' }
            }
            Write-Host (-join $line)
        }
    }

    foreach ($b in $builds) {
        $size = $b.Cols * $rows * 2
        Write-Host ("`n=== {0} build, {1}x{2} ===" -f $b.Name, $b.Cols, $rows)

        # 1. Screen RAM after 400 frames matches the reference model's.
        $refBin = Join-Path $work "$($b.Name)_reference.bin"
        $cdefs  = @(foreach ($name in $b.Defines) { "-D$name" })
        & $cl65 -t sim6502 -Oi -Cl @cdefs -DSIM_RAW "-DSIM_FRAMES=$testFrames" -o $refBin $reference
        if ($LASTEXITCODE -ne 0) { throw "The $($b.Name) reference model did not build." }
        $expected = [byte[]] @(& $sim65 $refBin | ForEach-Object { [Convert]::ToByte($_, 16) })
        if ($expected.Count -ne $size) { throw "The $($b.Name) reference model printed $($expected.Count) bytes, not $size." }

        $after = Get-ParkedRam $b $testFrames
        $ram   = $after.Ram
        Test-Loaded $ram $after.Build "$($b.Name) test build"

        $cells = [byte[]]::new($size)
        [Array]::Copy($ram, $physical + $screen, $cells, 0, $size)
        Write-Host "`nScreen after $testFrames frames ('.' empty, 'H' head, 'R' reversed head, '%' foreign letter, '+' bright, '*' green, ':' dark):`n"
        Write-Screen $cells $b.Cols

        $at = Find-Difference $cells $expected 0 $size
        if ($at -ge 0) {
            $count = @(0..($size - 1) | Where-Object { $cells[$_] -ne $expected[$_] }).Count
            $cell  = [Math]::Floor($at / 2)
            throw ('{0}: screen RAM differs from the reference model''s in {1} of {2} bytes after {3} frames. The first is the {4} of the cell at row {5}, column {6} (${7:X4}): the CoCo has ${8:X2}, the reference ${9:X2}.' -f `
                $b.Name, $count, $size, $testFrames, ($(if ($at % 2) { 'attribute' } else { 'character' })),
                [Math]::Floor($cell / $b.Cols), ($cell % $b.Cols), ($screen + $at), $cells[$at], $expected[$at])
        }
        Write-Host ("`nScreen RAM: all {0:n0} bytes match the reference model after {1} frames" -f $size, $testFrames)

        # 2. From the moment setup finishes to 400 frames later, nothing
        #    in the 512K outside the screen and the program's own memory
        #    changes.
        $before = (Get-ParkedRam $b 0).Ram
        $ownStart    = $physical + 0x0E00
        $ownEnd      = $physical + $after.Build.Labels['progend']
        $screenStart = $physical + $screen
        $screenEnd   = $screenStart + $size
        foreach ($range in @(@(0, $ownStart), @($ownEnd, $screenStart), @($screenEnd, $ram.Length))) {
            $at = Find-Difference $ram $before $range[0] $range[1]
            if ($at -ge 0) {
                throw ('{0}: RAM outside the screen and the program changed while it ran, first at physical ${1:X5}.' -f $b.Name, $at)
            }
        }
        Write-Host 'Other RAM:  all 512K unchanged while it ran'
    }

    # 3. The images load the shipped programs and run them. Each run traps
    #    on the main loop; the snapshot lands later, but the code and
    #    tables it checks never change.
    function Test-Image([string] $What, $Build, [string[]] $Load) {
        $tag  = $What.Replace(' ', '_')
        $snap = Join-Path $work "$tag.sna"
        if (Test-Path $snap) { Remove-Item $snap }
        $built = $release[$Build.Name]
        $null = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Machine 'coco3' -Log "$tag.log" -Arguments (@('-ram', '512') + $Load + @(
            '-trap', ('pc=0x{0:X4}' -f $built.Labels['mainloop']),
            '-trap-snap', (ConvertTo-XRoarPath $snap), '-trap-timeout', '1'))
        if (-not (Test-Path $snap)) { throw "The $What image never reached the main loop. XRoar's log: $work\$tag.log" }
        Test-Loaded (Read-XRoarRam $snap) $built "$What image"
        Write-Host ('{0,-20} loads and runs' -f "$What`:")
    }
    Write-Host ''
    foreach ($b in $builds) {
        Test-Image "$($b.Name) cassette" $b @('-load-tape', (ConvertTo-XRoarPath $b.Cas), '-type', 'CLOADM:EXEC\r')
    }
    if ((Test-Path (Join-Path $Roms 'disk11.rom')) -or (Test-Path (Join-Path $Roms 'disk10.rom'))) {
        foreach ($b in $builds) {
            Test-Image "$($b.Name) disk" $b @('-machine-cart', 'rsdos', '-load-fd0', (ConvertTo-XRoarPath $dsk),
                '-type', ('LOADM\"{0}\":EXEC\r' -f $b.Tape))
        }
    } else {
        Write-Host "disk:                SKIPPED, no disk11.rom or disk10.rom in $Roms"
    }

    # 4. Cycles per frame, from an instruction trace of frames 101 to 110,
    #    timed from one field sync to the next (the synced label). At
    #    1.79 MHz a trace's dt is eighths of a cycle. Busy leaves out the
    #    sync wait; it includes 22 cycles a frame of the test build's
    #    frame counting.
    Write-Host ''
    foreach ($b in $builds) {
        $timed = Build-Coco3 $b (Join-Path $work "$($b.Name)_test111.bin") 111
        $trace = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Machine 'coco3' -Log "$($b.Name)_test111.trace" -EmulatedSeconds 20 -Arguments @(
            '-ram', '512', '-trace-timing', '-run', (ConvertTo-XRoarPath $timed.Bin),
            '-trap', ('pc=0x{0:X4}' -f $timed.Labels['mainloop']), '-trap-range', '101', '-trap-trace',
            '-trap', ('pc=0x{0:X4}' -f $timed.Labels['testdone']), '-trap-timeout', '1')
        $wait = $timed.Labels['waitsync']
        $perFrame = @(Measure-XRoarTrace -Trace $trace -FrameStart $timed.Labels['synced'] -Stop $timed.Labels['testdone'] `
            -Idle @($wait, ($wait + 3)) -TicksPerCycle 8)
        Remove-Item $trace
        if ($perFrame.Count -ne 10) { throw "$($b.Name): expected 10 traced frames, got $($perFrame.Count)." }
        $busy  = $perFrame | Measure-Object Busy -Average -Maximum
        $field = ($perFrame | Measure-Object Total -Average).Average
        Write-Host ('{0,-10} frame cost: {1:n0} cycles on average, {2:n0} at most, of a {3:n0}-cycle frame ({4:p0} at most)' -f `
            $b.Name, $busy.Average, $busy.Maximum, $field, ($busy.Maximum / $field))
        if ($busy.Maximum -gt $field) { Write-Warning "$($b.Name): a frame took longer than a field, so the rain runs below 60 fps." }
    }
    return
}
