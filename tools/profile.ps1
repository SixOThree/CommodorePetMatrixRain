<#
.SYNOPSIS
    Shows where the C version's frame time goes, routine by routine.

.DESCRIPTION
    Builds matrix_rain_8032.c for cc65's 6502 simulator, traces every
    instruction of a 2-frame run and a 12-frame run, and charges each
    instruction's cycles to the routine it sits in, up to the point where
    the program starts printing the screen. Subtracting the two runs
    cancels startup and init, which leaves 10 frames of drawing, reported
    per frame.

    Names with a leading underscore are the program's own C functions.
    The rest are cc65 runtime routines the compiler calls into, such as
    tossubax for 16-bit subtraction and pushax for pushing a value onto
    cc65's software stack.

    Static functions get no linker label, so the traced copy of the
    source has 'static' dropped from its function definitions and is
    otherwise untouched. To show that this changes nothing, the copy is
    timed against the real source, and the two have to agree to the
    cycle. Even moving code around counts: a branch or indexed load that
    crosses a page boundary costs a cycle more.

    Early frames are cheaper than later ones, because some drops start
    above the screen, so the total here comes in under the per-frame
    figure from build.ps1 -Test, which averages frames 101 to 1100.

.EXAMPLE
    .\tools\profile.ps1
#>

[CmdletBinding()]
param(
    [string] $Cc65 = 'C:\Development\_VintageDevelopment\cc65_snapshot'
)

$ErrorActionPreference = 'Stop'

$root  = Split-Path $PSScriptRoot -Parent
$cl65  = Join-Path $Cc65 'bin\cl65.exe'
$sim65 = Join-Path $Cc65 'bin\sim65.exe'
$work  = Join-Path $env:TEMP 'matrix_rain_profile'
$flags = @('-Oi', '-Cl')    # the same flags build.ps1 uses

if (-not (Test-Path $cl65)) { throw "cl65 not found at $cl65. Pass -Cc65 <path to cc65>." }
New-Item -ItemType Directory -Force $work | Out-Null

$source  = Join-Path $root 'matrix_rain_8032.c'
$lines   = Get-Content $source
$static  = '^static (?=[\w ]+\([^;]*\)\s*$)'
if (-not ($lines -match $static)) { throw 'Found no static function definitions to expose.' }

$exposed = Join-Path $work 'exposed.c'
Set-Content $exposed ($lines -replace $static, '')

function Build-Sim([string] $from, [string] $name, [int] $frames, [string] $labels) {
    $bin = Join-Path $work "$name.$frames.bin"
    $extra = if ($labels) { @('-Ln', $labels) } else { @() }
    & $cl65 -t sim6502 @flags "-DSIM_FRAMES=$frames" @extra -o $bin $from
    if ($LASTEXITCODE -ne 0) { throw "Simulator build of $from failed." }
    $bin
}

function Get-Cycles([string] $bin) {
    $out = & $sim65 -c $bin 2>&1
    if ($LASTEXITCODE -ne 0) { throw "$bin failed in the simulator." }
    [long] [regex]::Match("$out", '(\d+) cycles').Groups[1].Value
}

# Where each routine starts, from a label file of lines like
# "al 000229 ._rnd". Local labels (@L1, L1) and the linker's own symbols
# (__BSS_SIZE__) are skipped, so the cycles spent past a local label
# still count towards the routine it belongs to.
function Read-Labels([string] $path) {
    $names = @{}
    foreach ($line in Get-Content $path) {
        if ($line -notmatch '^al\s+([0-9A-Fa-f]+)\s+\.(\S+)$') { continue }
        $address = [Convert]::ToInt32($Matches[1], 16)
        $name    = $Matches[2]
        if ($address -lt 0x200 -or $name -match '^(@|L\d+$|__\w+__$)') { continue }
        if (-not $names.ContainsKey($address)) { $names[$address] = $name }
    }
    $starts = [int[]] ($names.Keys | Sort-Object)
    [pscustomobject] @{ Starts = $starts; Names = [string[]] ($starts | ForEach-Object { $names[$_] }) }
}

# Cycles spent in each routine, from the start of a traced run until it
# first reaches dump(). Each trace line gives the running cycle count
# before an instruction executes, then its address, so the gap to the
# next line is what that instruction cost.
function Measure-Routines([string] $bin, [string] $labelFile) {
    $labels = Read-Labels $labelFile
    $k = [array]::IndexOf($labels.Names, '_dump')
    if ($k -lt 0) { throw "No _dump label in $labelFile." }
    $stop = $labels.Starts[$k]

    $trace = [IO.Path]::ChangeExtension($bin, 'trace')
    $run = Start-Process $sim65 -ArgumentList '--trace', "`"$bin`"" -RedirectStandardOutput $trace `
        -NoNewWindow -Wait -PassThru
    if ($run.ExitCode -ne 0) { throw "$bin failed in the simulator." }

    $perAddress = [long[]]::new(65536)
    $lastPc = -1
    $lastCycles = 0L
    $reader = [IO.StreamReader]::new($trace)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            $f = $line.Split([char[]] ' ', 4, [StringSplitOptions]::RemoveEmptyEntries)
            $cycles = 0L
            $pc = 0
            if ($f.Count -lt 3 -or
                -not [long]::TryParse($f[1], [ref] $cycles) -or
                -not [int]::TryParse($f[2], [Globalization.NumberStyles]::HexNumber, $null, [ref] $pc)) {
                continue
            }
            if ($lastPc -ge 0) { $perAddress[$lastPc] += $cycles - $lastCycles }
            if ($pc -eq $stop) { break }
            $lastPc = $pc
            $lastCycles = $cycles
        }
    }
    finally {
        $reader.Dispose()
    }
    Remove-Item $trace

    $routines = @{}
    for ($pc = 0; $pc -lt 65536; ++$pc) {
        if ($perAddress[$pc] -eq 0) { continue }
        $k = [Array]::BinarySearch($labels.Starts, $pc)
        if ($k -lt 0) { $k = (-bnot $k) - 1 }
        $name = if ($k -ge 0) { $labels.Names[$k] } else { '?' }
        $routines[$name] += $perAddress[$pc]
    }
    $routines
}

$real   = Get-Cycles (Build-Sim $source 'real' 12)
$traced = Get-Cycles (Build-Sim $exposed 'exposed' 12)
if ($real -ne $traced) {
    throw ("Dropping 'static' changed the program ({0:n0} cycles with it, {1:n0} without), " +
           'so a profile of the copy would not describe the real build.') -f $real, $traced
}

$runs = @{}
foreach ($n in 2, 12) {
    $labelFile = Join-Path $work "exposed.$n.lbl"
    $runs[$n] = Measure-Routines (Build-Sim $exposed 'exposed' $n $labelFile) $labelFile
}

$perFrame = foreach ($name in $runs[12].Keys) {
    $cycles = ($runs[12][$name] - [long] $runs[2][$name]) / 10
    if ($cycles -gt 0) { [pscustomobject] @{ Routine = $name; Cycles = $cycles } }
}
$total  = ($perFrame | Measure-Object Cycles -Sum).Sum
$random = ($perFrame | Where-Object Routine -like '_rnd*' | Measure-Object Cycles -Sum).Sum

Write-Host "`nCycles per frame by routine, averaged over frames 3 to 12`n"
Write-Host ('{0,-14} {1,9} {2,7}' -f 'routine', 'cycles', 'share')
Write-Host ('-' * 32)
foreach ($r in $perFrame | Sort-Object Cycles -Descending) {
    Write-Host ('{0,-14} {1,9:n0} {2,6:p1}' -f $r.Routine, $r.Cycles, ($r.Cycles / $total))
}
Write-Host ('-' * 32)
Write-Host ('{0,-14} {1,9:n0}' -f 'total', $total)
Write-Host ("`nThe _rnd routines together: {0:n0} cycles, {1:p0} of the frame" -f $random, ($random / $total))
