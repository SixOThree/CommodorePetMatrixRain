<#
.SYNOPSIS
    Reads CoCo DECB .bin files and writes cassette and disk images of them.

.DESCRIPTION
    Dot-source this file. It provides:

      Read-DecbBin   the segments and exec address of a .bin
      New-CocoCas    a cassette image, for CLOADM
      New-CocoDsk    a Disk BASIC disk image, for LOADM

    Pass full paths: .NET file calls resolve relative paths against the
    process's folder, not PowerShell's current location.
#>

# A .bin is a run of segments, each $00, a 2-byte length, a 2-byte load
# address and the bytes, then $FF, $00 $00 and a 2-byte exec address.
function Read-DecbBin([string] $Path) {
    $b = [IO.File]::ReadAllBytes($Path)
    $segments = [Collections.Generic.List[object]]::new()
    $at = 0
    while ($at + 5 -le $b.Length) {
        $kind    = $b[$at]
        $length  = $b[$at + 1] * 256 + $b[$at + 2]
        $address = $b[$at + 3] * 256 + $b[$at + 4]
        if ($kind -eq 0xFF) {
            return [pscustomobject] @{ Segments = $segments.ToArray(); Exec = $address }
        }
        if ($kind -ne 0x00) {
            throw ('{0}: expected a segment or the end at offset {1}, found ${2:X2}' -f $Path, $at, $kind)
        }
        $bytes = [byte[]]::new($length)
        [Array]::Copy($b, $at + 5, $bytes, 0, $length)
        $segments.Add([pscustomobject] @{ Address = $address; Bytes = $bytes })
        $at += 5 + $length
    }
    throw "$Path ends without an exec address."
}

# The byte stream CSAVEM writes: a leader of 128 $55 bytes, a name
# block, another leader, data blocks of up to 255 bytes and an end
# block. Each block is $55, the sync byte $3C, the block type (0 name,
# 1 data, $FF end), the length, the data, a checksum of type + length +
# data, and a closing $55. CLOADM loads one contiguous block, so the
# .bin must have exactly one segment.
function New-CocoCas {
    param(
        [Parameter(Mandatory)] [string] $Bin,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Path
    )
    $program = Read-DecbBin $Bin
    if ($program.Segments.Count -ne 1) {
        throw "$Bin has $($program.Segments.Count) segments; a cassette file holds one contiguous block."
    }
    $segment = $program.Segments[0]
    $out = [Collections.Generic.List[byte]]::new()

    function Add-Leader { for ($i = 0; $i -lt 128; $i++) { $out.Add(0x55) } }
    function Add-Block([int] $Type, [byte[]] $Data) {
        $sum = $Type + $Data.Length
        $out.AddRange([byte[]] (0x55, 0x3C, $Type, $Data.Length))
        foreach ($d in $Data) { $out.Add($d); $sum += $d }
        $out.AddRange([byte[]] (($sum % 256), 0x55))
    }

    $header = [byte[]]::new(15)
    [Text.Encoding]::ASCII.GetBytes($Name.ToUpperInvariant().PadRight(8).Substring(0, 8)).CopyTo($header, 0)
    $header[8]  = 2                                  # machine code
    $header[9]  = 0                                  # binary, not ASCII
    $header[10] = 0                                  # no gaps between blocks
    $header[11] = $program.Exec -shr 8
    $header[12] = $program.Exec -band 0xFF
    $header[13] = $segment.Address -shr 8
    $header[14] = $segment.Address -band 0xFF

    Add-Leader
    Add-Block 0x00 $header
    Add-Leader
    for ($i = 0; $i -lt $segment.Bytes.Length; $i += 255) {
        $n = [Math]::Min(255, $segment.Bytes.Length - $i)
        $chunk = [byte[]]::new($n)
        [Array]::Copy($segment.Bytes, $i, $chunk, 0, $n)
        Add-Block 0x01 $chunk
    }
    Add-Block 0xFF ([byte[]]::new(0))
    [IO.File]::WriteAllBytes($Path, $out.ToArray())
}

# 35 tracks of 18 sectors of 256 bytes, no header, laid out as Disk
# BASIC's DSKINI leaves a disk, with every unused byte $FF. Track 17
# holds the directory: sector 2 is the allocation table, one byte for
# each of the 68 granules of 9 sectors ($FF free, the next granule's
# number, or $C0 + sectors used for a file's last granule); sectors 3
# to 11 hold 32-byte directory entries. Granules run two to a track,
# skipping track 17. A .bin goes on the disk as is, because LOADM reads
# the same segment format from disk.
function New-CocoDsk {
    param(
        [Parameter(Mandatory)] [string] $Bin,
        [Parameter(Mandatory)] [string] $Name,
        [string] $Extension = 'BIN',
        [Parameter(Mandatory)] [string] $Path
    )
    $file = [IO.File]::ReadAllBytes($Bin)
    $null = Read-DecbBin $Bin                       # refuse anything that is not a .bin

    $sector   = 256
    $perTrack = 18
    $granule  = 9 * $sector
    [byte[]] $disk = @(0xFF) * (35 * $perTrack * $sector)

    # PowerShell names are case-insensitive, so the sector number must not
    # be called $Sector: it would hide the sector size above.
    function Get-Offset([int] $Track, [int] $Number) { ($Track * $perTrack + $Number - 1) * $sector }
    function Get-GranuleOffset([int] $G) {
        $track = [int] [Math]::Floor($G / 2)
        if ($track -ge 17) { $track++ }
        Get-Offset $track (($G % 2) * 9 + 1)
    }

    $count = [int] [Math]::Ceiling($file.Length / $granule)
    if ($count -gt 68) { throw "$Bin is too big for one disk." }

    $fat = Get-Offset 17 2
    for ($i = 68; $i -lt $sector; $i++) { $disk[$fat + $i] = 0 }
    for ($g = 0; $g -lt $count; $g++) {
        $n = [Math]::Min($granule, $file.Length - $g * $granule)
        [Array]::Copy($file, $g * $granule, $disk, (Get-GranuleOffset $g), $n)
        $disk[$fat + $g] = if ($g -lt $count - 1) { $g + 1 } else { 0xC0 + [int] [Math]::Ceiling($n / $sector) }
    }

    $last = $file.Length % $sector
    if ($last -eq 0) { $last = $sector }
    $entry = Get-Offset 17 3
    $label = $Name.ToUpperInvariant().PadRight(8).Substring(0, 8) + $Extension.ToUpperInvariant().PadRight(3).Substring(0, 3)
    [Text.Encoding]::ASCII.GetBytes($label).CopyTo($disk, $entry)
    $disk[$entry + 11] = 2                          # machine code
    $disk[$entry + 12] = 0                          # binary
    $disk[$entry + 13] = 0                          # first granule
    $disk[$entry + 14] = $last -shr 8
    $disk[$entry + 15] = $last -band 0xFF
    for ($i = 16; $i -lt 32; $i++) { $disk[$entry + $i] = 0 }
    [IO.File]::WriteAllBytes($Path, $disk)
}
