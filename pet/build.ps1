<#
.SYNOPSIS
    Builds the C version of Matrix Rain for the Commodore PET 8032.

.DESCRIPTION
    Compiles matrix_rain_8032.c with cc65 and writes matrix_rain_8032_c.prg,
    both in this folder.

    -Run       launches the result in VICE xpet afterwards.
    -Test      builds for cc65's 6502 simulator instead and prints the
               screen as text. It then runs the assembly version in the
               same simulator, fails unless every byte of screen RAM
               matches, and reports the cost of a frame for both.

.EXAMPLE
    .\pet\build.ps1
    .\pet\build.ps1 -Run
    .\pet\build.ps1 -Test
#>

[CmdletBinding()]
param(
    [switch] $Run,
    [switch] $Test,
    [string] $Cc65 = 'C:\Development\_VintageDevelopment\cc65_snapshot',
    [string] $Vice = 'C:\This Computer\bin\GTK3VICE-3.9-win64'
)

$ErrorActionPreference = 'Stop'

$cl65  = Join-Path $Cc65 'bin\cl65.exe'
$sim65 = Join-Path $Cc65 'bin\sim65.exe'
$xpet  = Join-Path $Vice 'bin\xpet.exe'

if (-not (Test-Path $cl65)) { throw "cl65 not found at $cl65. Pass -Cc65 <path to cc65>." }

$source = 'matrix_rain_8032.c'
$output = 'matrix_rain_8032_c.prg'

# -Oi   inline more aggressively; measurably faster than plain -O here
# -Cl   give locals static storage, which keeps them off cc65's slow
#       software stack. Safe only because nothing in this program recurses.
$flags = @('-Oi', '-Cl')

# cl65 runs from this folder: tools\asm_blob.s includes the assembly's
# .prg by a path relative to the folder cl65 runs in. The caller's
# location is put back afterwards.
Push-Location $PSScriptRoot
try {
    if ($Test) {
        $frames = 400

        # Runs the shipped assembly .prg in the same simulator, so the C
        # version can be checked and timed against it. See tools\asm_harness.c.
        $harness = @('-C', '..\tools\sim_asm.cfg', '..\tools\asm_harness.c', '..\tools\asm_blob.s')

        # Builds for the simulator, runs the result and returns its output.
        function Invoke-Sim([string] $name, [string[]] $arguments, [switch] $Cycles) {
            $bin = Join-Path $env:TEMP "matrix_rain_$name.bin"
            & $cl65 -t sim6502 @flags @arguments -o $bin
            if ($LASTEXITCODE -ne 0) { throw "simulator build failed ($name)" }
            $out = if ($Cycles) { & $sim65 -c $bin 2>&1 } else { & $sim65 $bin }
            if ($LASTEXITCODE -ne 0) { throw "$name failed in the simulator:`n$($out -join "`n")" }
            $out
        }

        # Cycles for one frame. Two runs of different lengths, so startup and
        # init cancel out and what is left is 1000 frames of drawing.
        function Measure-Frame([string] $name, [string[]] $arguments) {
            $total = foreach ($n in 100, 1100) {
                $out = Invoke-Sim "${name}_$n" (@("-DSIM_FRAMES=$n") + $arguments) -Cycles
                [long] [regex]::Match("$out", '(\d+) cycles').Groups[1].Value
            }
            ($total[1] - $total[0]) / 1000
        }

        Write-Host "`nScreen after $frames frames ('.' empty, '*' normal, '#' reverse):`n"
        Invoke-Sim 'c' @("-DSIM_FRAMES=$frames", $source) | Write-Host

        # Same seed, same number of frames: all 2048 bytes of screen RAM,
        # including the 48 past the last visible row, have to come out
        # exactly as the assembly leaves them.
        $size      = 2048
        $cScreen   = @(Invoke-Sim 'c_raw' @('-DSIM_RAW', "-DSIM_FRAMES=$frames", $source))
        $asmScreen = @(Invoke-Sim 'asm_raw' (@('-DSIM_RAW', "-DSIM_FRAMES=$frames") + $harness))
        if ($asmScreen.Count -ne $size) { throw "The assembly harness printed $($asmScreen.Count) lines, not $size." }
        if ($cScreen.Count -ne $size)   { throw "The C version printed $($cScreen.Count) lines, not $size." }

        $diff = @(0..($size - 1) | Where-Object { $cScreen[$_] -ne $asmScreen[$_] })
        if ($diff.Count -gt 0) {
            $at = $diff[0]
            throw ('Screen RAM differs from the assembly''s in {0:n0} of {1:n0} bytes after {2} frames. ' +
                   'The first is at ${3:x4}: C has ${4}, the assembly ${5}.') -f `
                $diff.Count, $size, $frames, (0x8000 + $at), $cScreen[$at], $asmScreen[$at]
        }
        Write-Host ("`nScreen RAM: all {0:n0} bytes match the assembly's after {1} frames" -f $size, $frames)

        $perFrame = Measure-Frame 'c' @($source)
        $asmFrame = Measure-Frame 'asm' $harness
        $budget   = 16667    # 1 MHz / 60 Hz
        Write-Host ("Frame cost: {0:n0} cycles ({1:n2}x the {2:n0}-cycle retrace budget, about {3:n0} fps)" -f `
            $perFrame, ($perFrame / $budget), $budget, (1e6 / $perFrame))
        Write-Host ("Assembly:   {0:n0} cycles, so the C version takes {1:n2}x as long" -f `
            $asmFrame, ($perFrame / $asmFrame))
        return
    }

    & $cl65 -t pet @flags -o $output $source
    if ($LASTEXITCODE -ne 0) { throw 'build failed' }
    Write-Host ("Built {0} ({1:n0} bytes)" -f $output, (Get-Item $output).Length)

    if ($Run) {
        if (-not (Test-Path $xpet)) { throw "xpet not found at $xpet. Pass -Vice <path to VICE>." }
        # Start-Process rather than a background job: VICE runs until closed,
        # and this keeps it off this console. The .prg path is quoted by hand
        # because Start-Process will not do it, and this repo lives under a
        # path with a space in it.
        $prg = '"{0}"' -f (Join-Path $PSScriptRoot $output)
        $proc = Start-Process $xpet -ArgumentList '-model', '8032', '-autostart', $prg -PassThru
        Write-Host ("Launched in VICE xpet (PID {0}). Close the window to stop it." -f $proc.Id)
    }
}
finally {
    Pop-Location
}
