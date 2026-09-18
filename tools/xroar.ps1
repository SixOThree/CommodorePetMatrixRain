<#
.SYNOPSIS
    Runs XRoar for automated tests and reads what it leaves behind.

.DESCRIPTION
    Dot-source this file. It provides:

      ConvertTo-XRoarPath   a path in the form XRoar's options accept
      Invoke-XRoar          runs XRoar with no window and waits for it
      Read-XRoarRam         the RAM image inside a snapshot
      Read-LwasmSymbols     label addresses from lwasm --symbol-dump,
                            for placing traps
      Measure-XRoarTrace    cycles per frame from an instruction trace

    Three XRoar 1.9 behaviours shape all of this:

      - A backslash in an option value is an escape, so C:\a\b.sna
        arrives as C:ab.sna, a path relative to the current folder.
        Paths go to XRoar with forward slashes, and XRoar runs from a
        scratch folder so a mistake cannot write into the repository.
      - A trap snapshot is written some time after its trap fires,
        roughly 20 frames later. Snapshot a program that has parked in
        a loop that writes nothing, and the delay does not matter.
      - A trap that starts tracing acts on the exact instruction, but
        one that stops tracing does nothing. A trace therefore runs
        until XRoar exits, and Measure-XRoarTrace stops reading at a
        given address.
#>

function ConvertTo-XRoarPath([string] $Path) {
    '"' + [IO.Path]::GetFullPath($Path).Replace('\', '/') + '"'
}

function Invoke-XRoar {
    param(
        [Parameter(Mandatory)] [string]   $XRoar,
        [Parameter(Mandatory)] [string]   $WorkDir,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [string] $Machine = 'coco2bus',
        [string] $Log = 'xroar.log',
        [int]    $EmulatedSeconds = 60,    # stops a run whose trap never fires
        [int]    $WaitSeconds = 120        # real time, in case XRoar hangs
    )
    New-Item -ItemType Directory -Force $WorkDir | Out-Null
    $logPath = Join-Path $WorkDir $Log
    $all = @('-machine', $Machine, '-ui', 'null', '-ao', 'null', '-no-ratelimit') +
           $Arguments + @('-timeout', "$EmulatedSeconds")
    $run = Start-Process $XRoar -ArgumentList $all -WorkingDirectory $WorkDir `
        -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" -PassThru
    if (-not $run.WaitForExit($WaitSeconds * 1000)) {
        taskkill /PID $run.Id /T /F | Out-Null
        throw "XRoar was still running after $WaitSeconds seconds. Its log: $logPath"
    }
    $logPath
}

# A snapshot, as far as reading RAM needs it, is a run of elements: a
# tag number, then (unless the tag is 0, which closes a group) a length
# and that many bytes. Numbers are variable length: the count of leading
# 1 bits in the first byte is how many more bytes follow, and the rest of
# the first byte holds the top of the value. 07 is 7; C1 00 00 is 0x10000.
function Read-XRoarNumber([byte[]] $Bytes, [ref] $At) {
    $first = [int] $Bytes[$At.Value]
    $At.Value++
    $more = 0
    $bit  = 0x80
    while ($bit -and ($first -band $bit)) { $more++; $bit = $bit -shr 1 }
    if ($more -gt 4) { throw ('Unexpected number encoding ${0:X2} in the snapshot.' -f $first) }
    [long] $value = $first -band ($bit - 1)
    for ($i = 0; $i -lt $more; $i++) {
        $value = ($value -shl 8) -bor $Bytes[$At.Value]
        $At.Value++
    }
    $value
}

# The RAM is a part named "RAM" of type "ram". Its contents are the one
# element in it exactly as long as the machine's RAM: 16K to 64K on a
# CoCo 1/2, 128K or 512K on a CoCo 3. A CoCo 3's is in physical order;
# as BASIC maps memory, the processor's $0000 is physical $70000.
function Read-XRoarRam([string] $Snapshot) {
    $bytes = [IO.File]::ReadAllBytes($Snapshot)
    $text  = [Text.Encoding]::Latin1.GetString($bytes)
    $open  = [string] [char] 1 + [char] 3 + 'RAM' + [char] 2 + [char] 3 + 'ram'
    $start = $text.IndexOf($open, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "$Snapshot has no RAM part." }

    $at = $start + $open.Length
    while ($at -lt $bytes.Length) {
        $tag = Read-XRoarNumber $bytes ([ref] $at)
        if ($tag -eq 0) { continue }
        $length = Read-XRoarNumber $bytes ([ref] $at)
        if ($length -in 16384, 32768, 65536, 131072, 524288) {
            $ram = [byte[]]::new($length)
            [Array]::Copy($bytes, $at, $ram, 0, $length)
            return ,$ram
        }
        $at += $length
    }
    throw "$Snapshot has a RAM part but no RAM contents in it."
}

# lwasm --symbol-dump writes one "name EQU $XXXX" line per label.
function Read-LwasmSymbols([string] $Path) {
    $symbols = @{}
    foreach ($line in Get-Content $Path) {
        if ($line -match '^(\S+)\s+(?:EQU|SET)\s+\$([0-9A-Fa-f]+)') {
            $symbols[$Matches[1]] = [Convert]::ToInt32($Matches[2], 16)
        }
    }
    $symbols
}

# Trace lines, one per instruction, look like
#   0e06| 4c          INCA        cc=80 a=01 ... dt=32
# where dt is the instruction's time in ticks of the 14.318 MHz master
# clock: 16 a CPU cycle at 0.89 MHz (the default -TicksPerCycle), 8 at
# a CoCo 3's 1.79 MHz. The
# first line traced is the exception: its dt is the time since tracing
# was armed, so it is never counted, and a frame that begins on it is
# dropped. A frame runs from one line at $FrameStart to the next; Busy
# leaves out the $Idle addresses, Total does not. Whatever comes before
# the first $FrameStart is dropped, and reading stops at the first line
# at $Stop, dropping the part-frame before it.
#
# Put $FrameStart just after a wait for the field sync. Each Total is
# then one field. Anywhere else, a Total is a field plus this frame's
# work minus the last one's.
function Measure-XRoarTrace {
    param(
        [Parameter(Mandatory)] [string] $Trace,
        [Parameter(Mandatory)] [int]    $FrameStart,
        [Parameter(Mandatory)] [int]    $Stop,
        [int[]] $Idle = @(),
        [int]   $TicksPerCycle = 16
    )
    $idleSet = [Collections.Generic.HashSet[int]]::new()
    foreach ($address in $Idle) { [void] $idleSet.Add($address) }

    $frames  = [Collections.Generic.List[object]]::new()
    $inFrame = $false       # inside a frame that began on a countable line
    $first   = $true
    $busy    = 0L
    $total   = 0L
    $reader  = [IO.StreamReader]::new($Trace)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line.Length -lt 5 -or $line[4] -ne '|') { continue }
            $pc = [Convert]::ToInt32($line.Substring(0, 4), 16)
            if ($pc -eq $Stop) { break }
            if ($pc -eq $FrameStart) {
                if ($inFrame) {
                    $frames.Add([pscustomobject] @{ Busy = $busy / $TicksPerCycle; Total = $total / $TicksPerCycle })
                }
                $inFrame = -not $first
                $busy    = 0L
                $total   = 0L
            }
            if ($first) { $first = $false; continue }
            $i = $line.LastIndexOf('dt=')
            if ($i -lt 0) { continue }
            $dt = [long] $line.Substring($i + 3).Trim()
            $total += $dt
            if (-not $idleSet.Contains($pc)) { $busy += $dt }
        }
    }
    finally {
        $reader.Dispose()
    }
    $frames.ToArray()
}
