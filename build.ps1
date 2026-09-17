<#
.SYNOPSIS
    Builds the C version of Matrix Rain for the Commodore PET 8032.

.DESCRIPTION
    Compiles matrix_rain_8032.c with cc65 and writes matrix_rain_8032_c.prg.

    -Run       launches the result in VICE xpet afterwards.
    -Test      builds for cc65's 6502 simulator instead and prints the
               screen as text, plus the measured cost of a frame.

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Run
    .\build.ps1 -Test
#>

[CmdletBinding()]
param(
    [switch] $Run,
    [switch] $Test,
    [string] $Cc65 = 'C:\Development\_VintageDevelopment\cc65_snapshot',
    [string] $Vice = 'C:\This Computer\bin\GTK3VICE-3.9-win64'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

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

if ($Test) {
    $bin = Join-Path $env:TEMP 'matrix_rain_sim.bin'
    & $cl65 -t sim6502 @flags -o $bin $source
    if ($LASTEXITCODE -ne 0) { throw 'simulator build failed' }

    Write-Host "`nScreen after 400 frames ('.' empty, '*' normal, '#' reverse):`n"
    & $sim65 $bin

    # Two runs of different lengths, so init and the text dump cancel out
    # and what is left is 1000 frames of drawing.
    $cycles = @{}
    foreach ($n in 100, 1100) {
        $b = Join-Path $env:TEMP "matrix_rain_sim_$n.bin"
        & $cl65 -t sim6502 @flags "-DSIM_FRAMES=$n" -o $b $source
        $out = & $sim65 -c $b 2>&1 | Select-String -Pattern '(\d+) cycles'
        $cycles[$n] = [int] $out.Matches[0].Groups[1].Value
    }
    $perFrame = ($cycles[1100] - $cycles[100]) / 1000
    $budget   = 16667    # 1 MHz / 60 Hz
    Write-Host ("`nFrame cost: {0:n0} cycles ({1:n2}x the {2:n0}-cycle retrace budget, about {3:n0} fps)" -f `
        $perFrame, ($perFrame / $budget), $budget, (1e6 / $perFrame))
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
