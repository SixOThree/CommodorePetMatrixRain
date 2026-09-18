# CoCo 3 Matrix Rain Implementation Plan

> **Deviations made during execution** (the code in the repo is authoritative):
> - Task 3: the speed check compared the slowest frame with the *average* frame length, which a single overrun inflates, so its warning could not fire. It now takes the shortest frame as the field and counts frames over one and a half fields. The same fix went into `build-coco.ps1`.
> - Task 3: trace runs end with `-trap-timeout 0`, which quits at the trap. A 1-second timeout traced 600,000 more lines at 1.79 MHz, and the CoCo 3 test took over three minutes. It now takes about 30 seconds. The same change went into `build-coco.ps1` and `tools/test_coco_tools.ps1`.
> - Task 4: the user chose optimisation over simply cutting drops. `RAND`, an inline random step, replaces the `JSR random` for the three per-drop rolls in `draw`, and the flicker sweep is unrolled four cells a pass. Neither changes the random sequence, so the `.c` is unchanged. The RGB build ends at `NUMDRIPS` 65, with no misses in 10,800 frames (70 still missed 2 a minute).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A CoCo 3 version of the matrix rain in 6809 assembly, with trails that fade from a white head to dark green: an 80×24 RGB build and a 40×24 composite build, each with tape images and a shared disk image, checked byte for byte against a C reference model in XRoar.

**Architecture:** `matrix_rain_coco3.asm` adapts the CoCo 1/2 program to the GIME's attribute text mode; `-D COMPOSITE` selects the 40-column build. `matrix_rain_coco3.c`, adapted from the CoCo 1/2 reference, is the model under sim65, with the same switch. `build-coco3.ps1` builds both and tests them in XRoar with the existing `tools/` helpers, which gain 512K RAM snapshots, 1.79 MHz trace timing and multi-file disks.

**Tech Stack:** 6809 assembly (LWTOOLS 4.25 `lwasm`), C (cc65 / sim65), PowerShell 7, XRoar 1.9.

**Spec:** `docs/superpowers/specs/2026-09-18-coco3-matrix-rain-design.md`

## Global Constraints

- Branch `feature/coco-port`. Commit messages lead with a plain description of the change, never mention Claude or Codex, carry no `Co-Authored-By` line, and end with a line containing only `~`. Write the message to a file with the Write tool and commit with `git commit -F <file>`.
- Write every file with the Write tool (or Edit). Run shell work with the PowerShell tool. Never put file content in a Bash command.
- PowerShell variable names are case-insensitive: never give a parameter or loop variable the same name, in any case, as a variable it must not hide. (`$Sector` hid `$sector` once and broke the disk writer.)
- Do not modify the PET files, `build.ps1`, `matrix_rain_coco.asm`, `matrix_rain_coco.c` or `build-coco.ps1`. `build-coco.ps1 -Test` and `tools\test_coco_tools.ps1` must keep passing, and a CoCo 1/2 rebuild must leave `matrix_rain_coco.dsk` byte-identical.
- Tool paths: LWTOOLS `C:\Development\_VintageDevelopment\lwtools\bin`, XRoar `C:\Program Files\6809.org.uk\XRoar 1.9\xroar.exe`, cc65 `C:\Development\_VintageDevelopment\cc65_snapshot`, ROMs `%USERPROFILE%\Documents\XRoar\ROMS` (no Disk BASIC ROM).
- XRoar machine for every CoCo 3 run: `-machine coco3 -ram 512`. BASIC's map puts logical `$0000` at physical `$70000`; a 512K snapshot holds RAM in physical order, so the screen at `$2000` is at `$72000`.
- GIME values (read from BASIC's `WIDTH 80`/`WIDTH 40`): `$FF90`=`$4C`, `$FF98`=`$03`, `$FF99`=`$15` (80) or `$05` (40), `$FF9A`=`$00`, `$FF9C`=`$00`, `$FF9D`/`$FF9E`=`$E4`/`$00`, `$FF9F`=`$00`. CPU to 1.79 MHz: write `$FFD9`.
- Attributes: `HEAD` `$00` white, `REVHEAD` `$21` black on bright green, `BRIGHT` `$08`, `GREEN` `$10`, `DARK` `$18`. An empty cell is `$20` with `DARK`.
- Palette slots 0-15: RGB `00 12 00 00 00 00 00 00 3F 12 10 02 00 00 00 00`; composite `00 21 00 00 00 00 00 00 30 21 11 01 00 00 00 00`.
- Settings, identical in the `.asm` and the `.c`: RGB (80) NUMDRIPS 70, TRAILMIN 10, TRAILMAX 23, SPDSTART 9, SPDRESET 5; composite (40) NUMDRIPS 40, TRAILMIN 14, TRAILMAX 23, SPDSTART 15, SPDRESET 8; both GLITCH 64, REVERSE 64, NEWCHAR 51, GRAPHIC 16, BLOCKGLITCH 255.
- A CoCo 3 field at 1.79 MHz is 29,982 cycles. At 1.79 MHz a trace's `dt` is eighths of a cycle (`-TicksPerCycle 8`).
- `lwasm -D NAME=value` takes decimal values only.
- XRoar facts from the CoCo 1/2 work still hold: forward-slash paths (`ConvertTo-XRoarPath`), snapshots land about 20 frames after their trap (so snapshot only parked programs), `-trap-no-trace` does nothing, `-type` needs `\r`, `-ui null` for no window.

---

## File Structure

| File | Responsibility |
|---|---|
| `tools/fixtures/fill.asm` (modify) | Gains `-D FAST`: switch a CoCo 3 to 1.79 MHz first. |
| `tools/xroar.ps1` (modify) | `Read-XRoarRam` accepts 128K and 512K; `Measure-XRoarTrace -TicksPerCycle`. |
| `tools/coco_images.ps1` (modify) | `New-CocoDsk` takes several `.bin` files. |
| `tools/test_coco_tools.ps1` (modify) | Tests for the above: two-file disk, 512K snapshot, 1.79 MHz trace. |
| `matrix_rain_coco3.c` (new) | Reference model, both builds. sim65 only. |
| `matrix_rain_coco3.asm` (new) | The program, both builds. |
| `build-coco3.ps1` (new) | Builds both, `-Run [-Composite]`, `-Test`. |
| `matrix_rain_coco3.bin`, `matrix_rain_coco3_cmp.bin`, `matrix_rain_coco3.cas`, `matrix_rain_coco3_cmp.cas`, `matrix_rain_coco3.dsk` (new, generated, committed) | The shipped builds and images. |
| `README.md`, `CLAUDE.md` (modify) | CoCo 3 sections. |

---

### Task 1: Tool support for the CoCo 3

**Files:**
- Modify: `tools/fixtures/fill.asm`
- Modify: `tools/test_coco_tools.ps1`
- Modify: `tools/xroar.ps1`
- Modify: `tools/coco_images.ps1`

**Interfaces:**
- Consumes: the existing helpers and tests.
- Produces:
  - `Read-XRoarRam` also returns 131,072- and 524,288-byte RAM images.
  - `Measure-XRoarTrace ... [-TicksPerCycle <int> = 16]`: Busy and Total in CPU cycles for that clock.
  - `New-CocoDsk -Bin <string[]> -Name <string[]> [-Extension <string[]> = 'BIN'] -Path <string>`: files take consecutive granules from granule 0 and consecutive directory entries. A single string still works.
  - `tools/fixtures/fill.asm` assembled with `-D FAST` writes `$FFD9` first.

- [ ] **Step 1: Give the fixture a fast option**

In `tools/fixtures/fill.asm`, replace:

```
; snapshot and the 523 cycles through a trace.

        org     $0E00
start   orcc    #$50            ; interrupts off, as the real program does
```

with:

```
; snapshot and the 523 cycles through a trace.
;
; Assembled with -D FAST it first switches a CoCo 3 to 1.79 MHz, for
; testing trace timing at that speed.

        org     $0E00
start   orcc    #$50            ; interrupts off, as the real program does
        IFDEF   FAST
        sta     $FFD9           ; CoCo 3: CPU to 1.79 MHz
        ENDC
```

- [ ] **Step 2: Add the two-file disk test**

In `tools/test_coco_tools.ps1`, insert immediately above the line `# --- XRoar ---`:

```powershell
$twoDsk = Join-Path $work 'two.dsk'
New-CocoDsk -Bin $bin, $big -Name 'FILL', 'BIG' -Path $twoDsk
$tk = [IO.File]::ReadAllBytes($twoDsk)
$bigBytes = [IO.File]::ReadAllBytes($big)
Check 'disk, two files: FILL.BIN then BIG.BIN in the directory' (
    [Text.Encoding]::ASCII.GetString($tk, $dir, 11) -eq 'FILL    BIN' -and
    [Text.Encoding]::ASCII.GetString($tk, $dir + 32, 11) -eq 'BIG     BIN')
Check 'disk, two files: FILL starts in granule 0, BIG in granule 1' ($tk[$dir + 13] -eq 0 -and $tk[$dir + 32 + 13] -eq 1)
Check 'disk, two files: each is its own last granule' ($tk[$fat] -eq 0xC1 -and $tk[$fat + 1] -eq 0xC3)
Check 'disk, two files: granule 1 holds BIG.BIN' ((Hex $tk[2304..(2304 + $bigBytes.Length - 1)]) -eq (Hex $bigBytes))

```

- [ ] **Step 3: Add the CoCo 3 tests**

In `tools/test_coco_tools.ps1`, insert immediately above the line `# --- summary ---`:

```powershell
# --- CoCo 3 ---
# The fixture on a 512K CoCo 3. BASIC maps the processor's $0000 to
# physical $70000, and a snapshot holds RAM in physical order.
$snap3 = Join-Path $work 'coco3.sna'
if (Test-Path $snap3) { Remove-Item $snap3 }
$null = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Machine 'coco3' -Log 'coco3.log' -Arguments @(
    '-ram', '512', '-run', (ConvertTo-XRoarPath $bin),
    '-trap', ('pc=0x{0:X4}' -f $labels['done']), '-trap-snap', (ConvertTo-XRoarPath $snap3), '-trap-timeout', '1')
if (Test-Path $snap3) {
    $ram3 = Read-XRoarRam $snap3
    Check 'coco3: the snapshot holds 512K of RAM' ($ram3.Length -eq 524288) "got $($ram3.Length)"
    $bad3 = @(0..511 | Where-Object { $ram3[0x70400 + $_] -ne ($_ % 256) })
    Check 'coco3: the screen is at physical $70400' ($bad3.Count -eq 0) "$($bad3.Count) bytes wrong"
    $seg3  = $fixture.Segments[0]
    $code3 = [byte[]]::new($seg3.Bytes.Length)
    [Array]::Copy($ram3, 0x70000 + $seg3.Address, $code3, 0, $code3.Length)
    Check 'coco3: the program is at physical $70E00' ((Hex $code3) -eq (Hex $seg3.Bytes))
} else {
    Check 'coco3: reaches DONE' $false "no snapshot, see $work\coco3.log"
}

# At 1.79 MHz a trace's dt counts eighths of a cycle.
$fast    = Join-Path $work 'fillfast.bin'
$fastSym = Join-Path $work 'fillfast.sym'
& (Join-Path $Lwtools 'lwasm.exe') --decb -D FAST -o $fast "--symbol-dump=$fastSym" (Join-Path $PSScriptRoot 'fixtures\fill.asm')
if ($LASTEXITCODE -ne 0) { throw 'the FAST fixture did not assemble' }
$fastLabels = Read-LwasmSymbols $fastSym
$trace3 = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Machine 'coco3' -Log 'fillfast.trace' -Arguments @(
    '-ram', '512', '-trace-timing', '-run', (ConvertTo-XRoarPath $fast),
    '-trap', ('pc=0x{0:X4}' -f $fastLabels['mainloop']), '-trap-range', '2', '-trap-trace',
    '-trap', ('pc=0x{0:X4}' -f $fastLabels['done']), '-trap-timeout', '1')
$wait3 = $fastLabels['waitsync']
$frames3 = @(Measure-XRoarTrace -Trace $trace3 -FrameStart $fastLabels['mainloop'] -Stop $fastLabels['done'] `
    -Idle @($wait3, ($wait3 + 3)) -TicksPerCycle 8)
Remove-Item $trace3
Check 'trace at 1.79 MHz: 10 whole frames' ($frames3.Count -eq 10) "got $($frames3.Count)"
Check 'trace at 1.79 MHz: every frame does exactly 523 cycles of work' (@($frames3 | Where-Object { $_.Busy -ne 523 }).Count -eq 0) (($frames3 | ForEach-Object Busy) -join ', ')
$field3 = ($frames3 | Measure-Object Total -Average).Average
Check 'trace at 1.79 MHz: a frame lasts one CoCo 3 field, about 29,982 cycles' ($field3 -gt 29900 -and $field3 -lt 30060) "average $field3"

```

- [ ] **Step 4: Run the tests to see the new ones fail**

Run: `pwsh -NoProfile -File .\tools\test_coco_tools.ps1`
Expected: the existing image checks pass, then the run stops with an error at the two-file disk step. `New-CocoDsk`'s `-Bin` is still a single string, so PowerShell joins the two paths with a space and the file can't be found. (After Step 7 this passes. The CoCo 3 checks would then fail next: `Read-XRoarRam` rejects 512K, and `-TicksPerCycle` doesn't exist yet. Steps 5 and 6 fix those.)

- [ ] **Step 5: Accept 128K and 512K RAM in `Read-XRoarRam`**

In `tools/xroar.ps1`, replace:

```powershell
# The RAM is a part named "RAM" of type "ram". Its contents are the one
# element in it exactly as long as a CoCo's RAM.
```

with:

```powershell
# The RAM is a part named "RAM" of type "ram". Its contents are the one
# element in it exactly as long as the machine's RAM: 16K to 64K on a
# CoCo 1/2, 128K or 512K on a CoCo 3. A CoCo 3's is in physical order;
# as BASIC maps memory, the processor's $0000 is physical $70000.
```

and replace:

```powershell
        if ($length -in 16384, 32768, 65536) {
```

with:

```powershell
        if ($length -in 16384, 32768, 65536, 131072, 524288) {
```

- [ ] **Step 6: Give `Measure-XRoarTrace` a clock setting**

In `tools/xroar.ps1`, replace:

```powershell
# where dt is the instruction's time in sixteenths of a CPU cycle. The
```

with:

```powershell
# where dt is the instruction's time in ticks of the 14.318 MHz master
# clock: 16 a CPU cycle at 0.89 MHz (the default -TicksPerCycle), 8 at
# a CoCo 3's 1.79 MHz. The
```

replace:

```powershell
        [int[]] $Idle = @()
    )
```

with:

```powershell
        [int[]] $Idle = @(),
        [int]   $TicksPerCycle = 16
    )
```

and replace:

```powershell
                    $frames.Add([pscustomobject] @{ Busy = $busy / 16; Total = $total / 16 })
```

with:

```powershell
                    $frames.Add([pscustomobject] @{ Busy = $busy / $TicksPerCycle; Total = $total / $TicksPerCycle })
```

- [ ] **Step 7: Let `New-CocoDsk` take several files**

In `tools/coco_images.ps1`, replace the whole `New-CocoDsk` function and the comment above it (from `# 35 tracks of 18 sectors` to the end of the file) with:

```powershell
# 35 tracks of 18 sectors of 256 bytes, no header, laid out as Disk
# BASIC's DSKINI leaves a disk, with every unused byte $FF. Track 17
# holds the directory: sector 2 is the allocation table, one byte for
# each of the 68 granules of 9 sectors ($FF free, the next granule's
# number, or $C0 + sectors used for a file's last granule); sectors 3
# to 11 hold 32-byte directory entries. Granules run two to a track,
# skipping track 17. A .bin goes on the disk as is, because LOADM reads
# the same segment format from disk.
#
# Several files may be given, each with its own name: they take
# consecutive granules from granule 0 and consecutive directory entries.
# -Extension is one for all, or one per file.
function New-CocoDsk {
    param(
        [Parameter(Mandatory)] [string[]] $Bin,
        [Parameter(Mandatory)] [string[]] $Name,
        [string[]] $Extension = @('BIN'),
        [Parameter(Mandatory)] [string] $Path
    )
    if ($Name.Count -ne $Bin.Count) { throw 'New-CocoDsk needs one name for each .bin.' }
    if ($Extension.Count -ne 1 -and $Extension.Count -ne $Bin.Count) { throw 'Give one extension, or one for each .bin.' }

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

    $fat = Get-Offset 17 2
    for ($i = 68; $i -lt $sector; $i++) { $disk[$fat + $i] = 0 }

    $next = 0                                        # the next free granule
    for ($k = 0; $k -lt $Bin.Count; $k++) {
        $file = [IO.File]::ReadAllBytes($Bin[$k])
        $null = Read-DecbBin $Bin[$k]                # refuse anything that is not a .bin

        $count = [int] [Math]::Ceiling($file.Length / $granule)
        if ($next + $count -gt 68) { throw 'The files do not fit on one disk.' }
        $first = $next
        for ($g = 0; $g -lt $count; $g++) {
            $n = [Math]::Min($granule, $file.Length - $g * $granule)
            [Array]::Copy($file, $g * $granule, $disk, (Get-GranuleOffset ($first + $g)), $n)
            $disk[$fat + $first + $g] = if ($g -lt $count - 1) { $first + $g + 1 } else { 0xC0 + [int] [Math]::Ceiling($n / $sector) }
        }
        $next += $count

        $last = $file.Length % $sector
        if ($last -eq 0) { $last = $sector }
        $ext   = if ($Extension.Count -eq 1) { $Extension[0] } else { $Extension[$k] }
        $entry = (Get-Offset 17 3) + 32 * $k
        $label = $Name[$k].ToUpperInvariant().PadRight(8).Substring(0, 8) + $ext.ToUpperInvariant().PadRight(3).Substring(0, 3)
        [Text.Encoding]::ASCII.GetBytes($label).CopyTo($disk, $entry)
        $disk[$entry + 11] = 2                      # machine code
        $disk[$entry + 12] = 0                      # binary
        $disk[$entry + 13] = $first                 # first granule
        $disk[$entry + 14] = $last -shr 8
        $disk[$entry + 15] = $last -band 0xFF
        for ($i = 16; $i -lt 32; $i++) { $disk[$entry + $i] = 0 }
    }
    [IO.File]::WriteAllBytes($Path, $disk)
}
```

- [ ] **Step 8: Run the tests to see them pass**

Run: `pwsh -NoProfile -File .\tools\test_coco_tools.ps1`
Expected: every check `PASS` (the disk load `SKIP`), then `All checks passed`.

- [ ] **Step 9: Check the CoCo 1/2 build is unaffected**

Run: `pwsh -NoProfile -File .\build-coco.ps1 -Test; git status --short`
Expected: all CoCo 1/2 checks pass, and `git status` lists only the four tool files: `matrix_rain_coco.dsk` is byte-identical after the rebuild.

- [ ] **Step 10: Commit**

Write `C:\Users\Matth\AppData\Local\Temp\claude\msg3_task1.txt`:

```
Teach the CoCo tools about the CoCo 3

Snapshots of a 512K CoCo 3 now read back, traces can be timed at the
CoCo 3's 1.79 MHz, and a disk image can hold several programs. The
tests cover all three with the fixture, which gains an option to switch
a CoCo 3 to high speed.

~
```

Run: `git add tools/fixtures/fill.asm tools/test_coco_tools.ps1 tools/xroar.ps1 tools/coco_images.ps1; git commit -F "$env:TEMP\claude\msg3_task1.txt"`

---

### Task 2: The C reference model

**Files:**
- Create: `matrix_rain_coco3.c`

**Interfaces:**
- Consumes: nothing.
- Produces: `matrix_rain_coco3.c`. With `cl65 -t sim6502 -Oi -Cl [-DCOMPOSITE] -DSIM_RAW -DSIM_FRAMES=<n>` it prints `COLS × 24 × 2` lines of two hex digits: each cell's character, then its attribute. Without `SIM_RAW` it prints the text view. Task 3's test compares the CoCo 3 program against it.

- [ ] **Step 1: Write the sanity check**

Write `C:\Users\Matth\AppData\Local\Temp\claude\coco3_ref_check.ps1`:

```powershell
# Builds matrix_rain_coco3.c both ways for sim65 and checks the screen
# after 400 and 3,000 frames: only codes and colours the program can
# produce, no reverse heads on the bottom row, and no white or reversed
# character anywhere but at a drop's head.
$ErrorActionPreference = 'Stop'
$repo = 'C:\OneDrive\Vintage Computing Development\CommodorePetMatrixRain'
$cc65 = 'C:\Development\_VintageDevelopment\cc65_snapshot\bin'
$out  = Join-Path $env:TEMP 'coco3_ref_check.bin'
foreach ($build in @(@{ Name = 'rgb'; Cols = 80; Defs = @() }, @{ Name = 'composite'; Cols = 40; Defs = @('-DCOMPOSITE') })) {
    foreach ($n in 400, 3000) {
        & "$cc65\cl65.exe" -t sim6502 -Oi -Cl @($build.Defs) -DSIM_RAW "-DSIM_FRAMES=$n" -o $out (Join-Path $repo 'matrix_rain_coco3.c')
        if ($LASTEXITCODE -ne 0) { throw 'build failed' }
        $b = [byte[]] @(& "$cc65\sim65.exe" $out | ForEach-Object { [Convert]::ToByte($_, 16) })
        $cells = $build.Cols * 24
        $badChar = 0; $badAttr = 0; $bottomRev = 0; $heads = 0; $foreign = 0; $fade = @{ 0x08 = 0; 0x10 = 0; 0x18 = 0 }
        for ($i = 0; $i -lt $cells; $i++) {
            $ch = $b[$i * 2]; $at = $b[$i * 2 + 1]
            if ($ch -gt 0x7E) { $badChar++ }
            if ($at -notin 0x00, 0x21, 0x08, 0x10, 0x18) { $badAttr++ }
            if ($ch -eq 0x20) { continue }
            if ($ch -lt 0x20) { $foreign++ }
            if ($at -in 0x00, 0x21) { $heads++ } else { $fade[[int] $at]++ }
            if ($at -eq 0x21 -and $i -ge 23 * $build.Cols) { $bottomRev++ }
        }
        '{0,-9} {1,4} frames: {2} bytes (want {3}); bad chars {4}, bad attributes {5}, reverse on bottom row {6} (want 0); heads {7}, bright {8}, green {9}, dark {10}, foreign {11}' -f `
            $build.Name, $n, $b.Count, ($cells * 2), $badChar, $badAttr, $bottomRev, $heads, $fade[0x08], $fade[0x10], $fade[0x18], $foreign
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `& "$env:TEMP\claude\coco3_ref_check.ps1"`
Expected: FAIL, because `cl65` cannot open `matrix_rain_coco3.c`.

- [ ] **Step 3: Write `matrix_rain_coco3.c`**

```c
/* ============================================================
 * Matrix Rain Effect (TRS-80 Color Computer 3) - C reference
 * ============================================================
 * The reference model for matrix_rain_coco3.asm. It builds only for
 * cc65's 6502 simulator, not for the CoCo: build-coco3.ps1 -Test runs
 * it for 400 frames and requires the 6809 program to leave screen RAM,
 * characters and attributes, exactly as this does.
 * Original from Petopia demo by Milasoft.
 *
 * Author: Matthew Dugal (github.com/SixOThree)
 * ============================================================
 *
 * Build:  cl65 -t sim6502 -Oi -Cl -DSIM_RAW -o reference.bin matrix_rain_coco3.c
 *         add -DCOMPOSITE for the 40-column composite build
 *
 * This is a copy of matrix_rain_coco.c, the CoCo 1/2 reference, with
 * these changes:
 *
 *   - the screen is 80x24 (40x24 with COMPOSITE), two bytes a cell:
 *     the character, then an attribute giving its colours
 *   - trails fade: a white (or reversed) head, then bright green,
 *     green and dark green, set as each drop moves
 *   - no graphics blocks: the foreign letters $00-$1F take their place,
 *     and flicker() sweeps an eighth of the screen a frame
 *   - letters are printable ASCII $21-$7E, lowercase included
 *   - the PET's full stagger table, and wider column rolls
 *
 * A drop's position is a signed offset in cells from the start of
 * screen RAM. Negative means the drop has not reached the top of the
 * screen yet. The 6809 program keeps the same thing as a screen
 * address: $2000 + offset x 2.
 * ============================================================ */

#ifndef __SIM6502__
#error "matrix_rain_coco3.c is the CoCo 3 reference model: build it with -t sim6502"
#endif

#include <stdio.h>

/* ------------------------------------------------------------
 * Configuration
 * ------------------------------------------------------------
 * Keep these in step with matrix_rain_coco3.asm: the test fails until
 * they agree. */

#ifdef COMPOSITE
#define COLS        40      /* 40x24 for a TV or composite monitor          */
#define COLMASK     0x3f    /* column rolls: 0-63, rerolled while >= COLS   */
#define GLITCH      64      /* trail glitch frequency (0=off, 255=constant) */
#define TRAILMIN    14      /* minimum trail length (rows)                  */
#define TRAILMAX    23      /* maximum trail length (rows)                  */
#define REVERSE     64      /* reverse head chance (0=never, 255=always)    */
#define NEWCHAR     51      /* new char chance (lower=more flicker)         */
#define NUMDRIPS    40      /* active drops (max COLS)                      */
#define SPDSTART    15      /* initial speed range (0 to N-1, lower=faster) */
#define SPDRESET     8      /* reset speed range (0 to N-1, lower=faster)   */
#define GRAPHIC     16      /* foreign letter chance (0=never, 255=always)  */
#define BLOCKGLITCH 255     /* chance a foreign letter in a trail changes
                             * each time the sweep visits it, every 8
                             * frames (0=never, 255=always)                 */
#else
#define COLS        80      /* 80x24 for an RGB monitor                     */
#define COLMASK     0x7f    /* column rolls: 0-127, rerolled while >= COLS  */
#define GLITCH      64
#define TRAILMIN    10
#define TRAILMAX    23
#define REVERSE     64
#define NEWCHAR     51
#define NUMDRIPS    70
#define SPDSTART     9
#define SPDRESET     5
#define GRAPHIC     16
#define BLOCKGLITCH 255
#endif

/* Speeds are drawn from 0-31, and a trail needs rows for the fade. */
#if SPDSTART > 32 || SPDRESET > 32 || NUMDRIPS > COLS || TRAILMIN < 5
#error "SPDSTART and SPDRESET must be 32 or less, NUMDRIPS at most COLS, TRAILMIN 5 or more"
#endif

/* ------------------------------------------------------------
 * Screen geometry, characters and colours
 * ------------------------------------------------------------ */

#define ROWS        24
#define SCREEN_CELLS (COLS * ROWS)
#define CHR_SPACE   0x20    /* an empty cell's character                   */
#define FOREIGN     0x20    /* foreign letters are $00-$1F                 */

/* Attributes: foreground in bits 5-3 (palette slots 8-15), background
 * in bits 2-0 (slots 0-7). */
#define HEAD        0x00    /* white on black                              */
#define REVHEAD     0x21    /* black on bright green                       */
#define BRIGHT      0x08    /* bright green on black                       */
#define GREEN       0x10    /* green on black                              */
#define DARK        0x18    /* dark green on black; also an empty cell's:
                             * a character glitched into a gap between
                             * trails then reads as dark residue, not as
                             * a stray white head                          */

/* True when a screen offset, in cells, lands inside screen RAM. A
 * negative offset wraps to a very large unsigned value, so one
 * comparison does the work of checking both ends. Only safe where the
 * offset cannot legitimately exceed the screen by more than it could
 * fall below zero, which is every use below except the tail. */
#define ON_SCREEN(off) ((unsigned int)(off) < SCREEN_CELLS)

/* No reverse heads anywhere on the bottom row. */
#define NOREVERSE   ((ROWS - 1) * COLS)

/* The simulator has no CoCo screen, so the screen is an array: cell n's
 * character at 2n, its attribute at 2n + 1. */
static unsigned char sim_screen[SCREEN_CELLS * 2];
#define screen sim_screen

/* ------------------------------------------------------------
 * Per-column state
 * ------------------------------------------------------------ */

static unsigned char poslo[NUMDRIPS];   /* head offset, low byte        */
static unsigned char poshi[NUMDRIPS];   /* head offset, high byte       */

#define POS_GET(n)    ((int)(unsigned int)(poslo[n] | ((unsigned int)poshi[n] << 8)))
#define POS_SET(n, v) do {                          \
        unsigned int pos_ = (unsigned int)(v);      \
        poslo[n] = (unsigned char)pos_;             \
        poshi[n] = (unsigned char)(pos_ >> 8);      \
    } while (0)

static unsigned char speed[NUMDRIPS];   /* frames between moves         */
static unsigned char del[NUMDRIPS];     /* frames waited so far         */
static unsigned char trail[NUMDRIPS];   /* trail length in rows         */

/* Row offsets in cells, split into bytes as in the PET port. */
static unsigned char rowofflo[TRAILMAX + 1];
static unsigned char rowoffhi[TRAILMAX + 1];

#define ROWOFF(n) ((int)(unsigned int)(rowofflo[n] | ((unsigned int)rowoffhi[n] << 8)))

/* Staggered start positions: the PET's table. ABOVE is 256 cells up,
 * which is what the PET assembly's $7f high byte meant; at 80 columns
 * that puts a drop about 3 rows up and 64 columns across, as on the
 * PET 8032, and at 40 columns as on the 4032. The first NUMDRIPS
 * entries are used. */

#define ABOVE   (-256)
#define TOP     0

static const int rainhis[80] = {
    ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP,
    ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP,
    TOP,   TOP, TOP,   TOP, ABOVE, TOP, TOP,   TOP, TOP,   TOP,
    ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP,
    ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP,
    TOP,   TOP, TOP,   TOP, ABOVE, TOP, TOP,   TOP, TOP,   TOP,
    ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP,
    ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP
};

/* ============================================================
 * RANDOM - 16-bit LFSR
 * ============================================================
 * A direct port of the assembly routine, seed and all:
 *
 *   lda seedhi / lsr / rol seedlo / bcc + / eor #$b4 / + sta seedhi
 *   eor seedlo
 * ============================================================ */

static unsigned char seedlo;
static unsigned char seedhi;
static unsigned char headch;    /* the head being placed: character     */
static unsigned char headat;    /* and attribute                        */

static unsigned char rnd(void)
{
    if (seedlo & 0x80) {                            /* carry out of rol */
        seedlo = (unsigned char)((seedlo << 1) | (seedhi & 1));
        seedhi = (unsigned char)((seedhi >> 1) ^ 0xB4);
    } else {
        seedlo = (unsigned char)((seedlo << 1) | (seedhi & 1));
        seedhi >>= 1;
    }
    return (unsigned char)(seedhi ^ seedlo);
}

/* A foreign letter, $00-$1F. */
static unsigned char rnd_foreign(void)
{
    return rnd() & 0x1f;
}

/* A new rain character: now and then a foreign letter, otherwise
 * printable ASCII $21-$7E. */
static unsigned char rnd_char(void)
{
    unsigned char ch;

    if (rnd() < GRAPHIC) {
        return rnd_foreign();
    }
    do {
        ch = rnd() & 0x7f;
    } while (ch < 0x21 || ch == 0x7f);
    return ch;
}

/* A new head: a new character, white, or reversed with the REVERSE
 * chance. Sets headch and headat. */
static void rnd_head(void)
{
    headch = rnd_char();
    headat = (rnd() < REVERSE) ? REVHEAD : HEAD;
}

/* Trail length in TRAILMIN..TRAILMAX, drawn the same way as the
 * assembly: mask to 0-31, add the minimum, reroll if over the max. */
static unsigned char rnd_trail(void)
{
    unsigned char n;

    do {
        n = (unsigned char)((rnd() & 0x1f) + TRAILMIN);
    } while (n > TRAILMAX);
    return n;
}

/* Give the cell at off the attribute at, if it is on the screen. */
static void set_attr(int off, unsigned char at)
{
    if (ON_SCREEN(off)) {
        screen[off * 2 + 1] = at;
    }
}

/* ============================================================
 * Initialization
 * ============================================================ */

static void init(void)
{
    unsigned char i;
    unsigned char n;
    int           off;

    seedlo = 21;
    seedhi = 0x1c;

    for (off = 0; off < SCREEN_CELLS; ++off) {
        screen[off * 2]     = CHR_SPACE;
        screen[off * 2 + 1] = DARK;
    }

    for (n = 0; n <= TRAILMAX; ++n) {
        unsigned int off_ = (unsigned int)n * COLS;
        rowofflo[n] = (unsigned char)off_;
        rowoffhi[n] = (unsigned char)(off_ >> 8);
    }

    for (i = 0; i < NUMDRIPS; ++i) {
        do {
            n = rnd() & 0x1f;
        } while (n >= SPDSTART);
        speed[i] = n;

        trail[i] = rnd_trail();
        del[i]   = 0;
        POS_SET(i, rainhis[i] + i);
    }
}

/* ============================================================
 * DRAW - one frame
 * ============================================================
 * For each drop: refresh the head, maybe glitch one character in the
 * trail, then move or wait. Moving erases the tail and sets the fade's
 * colours behind the new head.
 * ============================================================ */

static void draw(void)
{
    unsigned char col;
    unsigned char row;
    unsigned char t;
    unsigned char *cell;
    int           p;
    int           other;

    for (col = 0; col < NUMDRIPS; ++col) {
        p = POS_GET(col);
        t = trail[col];

        if (ON_SCREEN(p)) {
            cell = screen + p * 2;

            /* Head: usually keep what is there, sometimes pick anew.
             * An empty cell always gets a fresh character. A kept
             * character keeps a head's colours, and turns white if it
             * belonged to another drop's trail. */
            if (rnd() < NEWCHAR) {
                rnd_head();
            } else {
                headch = cell[0];
                headat = cell[1];
                if (headch == CHR_SPACE) {
                    rnd_head();
                } else if (headat != HEAD && headat != REVHEAD) {
                    headat = HEAD;
                }
            }

            if (p >= NOREVERSE) {
                headat = HEAD;
            }
            cell[0] = headch;
            cell[1] = headat;

            /* Swap one character somewhere in the trail, keeping its
             * colour. As on the PET, only while the row above the head
             * is on the screen. */
            other = p - COLS;
            if (ON_SCREEN(other)) {
                if (rnd() < GLITCH) {
                    row = rnd() & 0x0f;
                    if (row != 0 && row < t) {
                        other = p - ROWOFF(row);
                        if (ON_SCREEN(other)) {
                            screen[other * 2] = rnd_char();
                        }
                    }
                }
            }
        }

        /* Time to move? */
        if (del[col] != speed[col]) {
            ++del[col];
            continue;
        }
        del[col] = 0;

        /* Erase the tail. This one stays a signed comparison: a drop
         * that has not reached the top of the screen has a tail far
         * below zero, and ON_SCREEN would read that as having fallen
         * off the bottom. */
        other = p - ROWOFF(t);

        if (other >= SCREEN_CELLS) {
            /* The whole drop has left the screen. Recycle it: new
             * column, new speed, new trail. Both rolls take a masked
             * value and reroll while out of range. */
            do {
                headch = rnd() & COLMASK;
            } while (headch >= COLS);
            POS_SET(col, headch);

            do {
                headch = rnd() & 0x1f;
            } while (headch >= SPDRESET);
            speed[col] = headch;

            trail[col] = rnd_trail();
            continue;
        }

        if (other >= 0) {
            screen[other * 2]     = CHR_SPACE;
            screen[other * 2 + 1] = DARK;
        }

        p += COLS;
        POS_SET(col, p);

        /* The fade: bright green 1 row behind the new head, green 2
         * rows behind, dark green t-2 rows behind. */
        set_attr(p - COLS, BRIGHT);
        set_attr(p - 2 * COLS, GREEN);
        set_attr(p - ROWOFF(t - 2), DARK);
    }
}

/* ============================================================
 * FLICKER - the foreign letters in the trails keep changing
 * ============================================================
 * Each frame sweeps an eighth of the screen, a different eighth each
 * time, so every cell is visited every 8 frames. A foreign letter
 * found in a trail (not a head) becomes another with chance
 * BLOCKGLITCH.
 * ============================================================ */

#define SWEEP_CELLS (SCREEN_CELLS / 8)

static unsigned int sweep;  /* the cell where the next sweep starts */

static void flicker(void)
{
    unsigned int  i;
    unsigned int  end = sweep + SWEEP_CELLS;
    unsigned char at;

    for (i = sweep; i < end; ++i) {
        at = screen[i * 2 + 1];
        if (screen[i * 2] < FOREIGN && at != HEAD && at != REVHEAD
            && rnd() < BLOCKGLITCH) {
            screen[i * 2] = rnd_foreign();
        }
    }
    sweep = (end == SCREEN_CELLS) ? 0 : end;
}

/* ============================================================
 * Entry point
 * ============================================================ */

#ifndef SIM_FRAMES
#define SIM_FRAMES 400
#endif

/* Print the screen as text: '.' empty, 'H' head, 'R' reversed head,
 * '%' a foreign letter in a trail, then by colour '+' bright green,
 * '*' green, ':' dark green.
 *
 * Built with SIM_RAW, print every byte of screen RAM in hex instead,
 * one per line: each cell's character, then its attribute. */
static void dump(void)
{
#ifdef SIM_RAW
    unsigned int i;

    for (i = 0; i < SCREEN_CELLS * 2; ++i) {
        printf("%02x\n", screen[i]);
    }
#else
    unsigned int  r;
    unsigned int  c;
    unsigned char ch;
    unsigned char at;

    for (r = 0; r < ROWS; ++r) {
        for (c = 0; c < COLS; ++c) {
            ch = screen[(r * COLS + c) * 2];
            at = screen[(r * COLS + c) * 2 + 1];
            if (ch == CHR_SPACE) {
                putchar('.');
            } else if (at == HEAD) {
                putchar('H');
            } else if (at == REVHEAD) {
                putchar('R');
            } else if (ch < FOREIGN) {
                putchar('%');
            } else {
                putchar(at == BRIGHT ? '+' : at == GREEN ? '*' : ':');
            }
        }
        putchar('\n');
    }
#endif
}

int main(void)
{
    unsigned int f;

    init();
    for (f = 0; f < SIM_FRAMES; ++f) {
        draw();
        flicker();
    }
    dump();
    return 0;
}
```

- [ ] **Step 4: Run the check to see it pass**

Run: `& "$env:TEMP\claude\coco3_ref_check.ps1"`
Expected, for each build at 400 and 3,000 frames: the byte count matches, `bad chars 0`, `bad attributes 0`, `reverse on bottom row 0`, and non-zero counts of heads, bright, green, dark and foreign cells. There should be roughly as many heads as drops on screen. A few dozen at most would be normal; hundreds would mean trails are keeping head colours.

- [ ] **Step 5: Look at the text views**

Run: `$c='C:\Development\_VintageDevelopment\cc65_snapshot\bin'; foreach ($d in @(@(), @('-DCOMPOSITE'))) { & "$c\cl65.exe" -t sim6502 -Oi -Cl @d -o "$env:TEMP\coco3_text.bin" matrix_rain_coco3.c; & "$c\sim65.exe" "$env:TEMP\coco3_text.bin" }`
Expected: 24 lines of 80 characters, then 24 of 40. Columns read, from the bottom of each trail upwards, `H` (or `R`), `+`, then `*`s, then `:` near the top end. There should be no `H` in the middle of a trail.

- [ ] **Step 6: Commit**

Write `C:\Users\Matth\AppData\Local\Temp\claude\msg3_task2.txt`:

```
Add the C reference model for the CoCo 3 version

matrix_rain_coco3.c adapts the CoCo 1/2 reference to the CoCo 3's
attribute text mode: 80x24, or 40x24 with COMPOSITE, trails that fade
from a white head to dark green, and flickering foreign letters in
place of graphics blocks. It builds only for cc65's simulator.

~
```

Run: `git add matrix_rain_coco3.c; git commit -F "$env:TEMP\claude\msg3_task2.txt"`

---

### Task 3: The program and its tests

**Files:**
- Create: `build-coco3.ps1`
- Create: `matrix_rain_coco3.asm`
- Create (generated): `matrix_rain_coco3.bin`, `matrix_rain_coco3_cmp.bin`, `matrix_rain_coco3.cas`, `matrix_rain_coco3_cmp.cas`, `matrix_rain_coco3.dsk`

**Interfaces:**
- Consumes: `matrix_rain_coco3.c` (Task 2); `Read-DecbBin`, `New-CocoCas`, `New-CocoDsk -Bin <string[]> -Name <string[]>` (Task 1); `ConvertTo-XRoarPath`, `Invoke-XRoar`, `Read-XRoarRam` (512K), `Read-LwasmSymbols`, `Measure-XRoarTrace -TicksPerCycle` (Task 1).
- Produces: global labels in `matrix_rain_coco3.asm`: `start`, `mainloop`, `waitsync` (the `LDA $FF03`, with the `BPL` 3 bytes on), `synced`, `draw`, `flicker`, `codeend`, `progend`, and `testdone` in test builds. `build-coco3.ps1 -Test` prints, per build, the text screen, `Screen RAM: all N bytes match the reference model after 400 frames` and `Other RAM:  all 512K unchanged while it ran`, then the image lines and a `frame cost` line per build.

- [ ] **Step 1: Write `build-coco3.ps1`**

```powershell
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
```

- [ ] **Step 2: Run the test to see it fail**

Run: `pwsh -NoProfile -File .\build-coco3.ps1 -Test`
Expected: FAIL with `...matrix_rain_coco3.asm not found.`

- [ ] **Step 3: Write `matrix_rain_coco3.asm`**

```
; ============================================================
; Matrix Rain Effect (TRS-80 Color Computer 3)
; ============================================================
; Matrix-style falling characters in colour for the CoCo 3's
; hardware text mode: each trail fades from a white head through
; bright green and green to dark green.
; Ported from the CoCo 1/2 version (matrix_rain_coco.asm), itself
; from matrix_rain_8032_noclock_v8.asm (Commodore PET 8032).
; Original from Petopia demo by Milasoft.
;
; Author: Matthew Dugal (github.com/SixOThree)
; ============================================================
;
; Two builds from this file:
;   lwasm --decb -o matrix_rain_coco3.bin matrix_rain_coco3.asm
;       80x24, 70 drops, palette for an RGB monitor
;   lwasm --decb -D COMPOSITE -o matrix_rain_coco3_cmp.bin matrix_rain_coco3.asm
;       40x24, 40 drops, palette for a TV or composite monitor
; (build-coco3.ps1 does both and writes the tape and disk images.)
; Run:    LOADM"MATRIX3":EXEC, or MATRIX3C for composite
;
; Memory map (as BASIC leaves the MMU, logical $0000 = physical $70000):
;   $0E00-$0E0F  variables, reached through the direct page register
;   $0E10-       code and tables, then drop records and stack
;   $2000-       screen: 2 bytes a cell, character then attribute
;                (physical $72000)
;   $FF02/$FF03  PIA 0 side B: field sync sets bit 7 of $FF03
;   $FF90-$FF9F  GIME video registers; $FFB0-$FFBF palette
;   $FFD9        any write: CPU to 1.79 MHz
;
; Attribute byte: bits 5-3 foreground (palette slots 8-15),
; bits 2-0 background (slots 0-7), bits 7-6 (blink, underline) clear.
;
; matrix_rain_coco3.c is the reference model. build-coco3.ps1 -Test
; requires this program to leave screen RAM exactly as it does, so a
; change to any setting below goes into both files.
; ============================================================

; ------------------------------------------------------------
; Configuration
; ------------------------------------------------------------

         IFDEF COMPOSITE
COLS     equ  40             ; 40x24 for a TV or composite monitor
COLMASK  equ  $3F            ; column rolls: 0-63, rerolled while >= COLS
GIMERES  equ  $05            ; GIME resolution: 40 columns, attributes
GLITCH   equ  64             ; trail glitch frequency (0=off, 255=constant)
TRAILMIN equ  14             ; minimum trail length (rows)
TRAILMAX equ  23             ; maximum trail length (rows)
REVERSE  equ  64             ; reverse head chance (0=never, 255=always)
NEWCHAR  equ  51             ; new char chance (lower=more flicker)
NUMDRIPS equ  40             ; active drops (max COLS)
SPDSTART equ  15             ; initial speed range (0 to N-1, lower=faster)
SPDRESET equ  8              ; reset speed range (0 to N-1, lower=faster)
GRAPHIC  equ  16             ; foreign letter chance (0=never, 255=always)
BLOCKGLITCH equ 255          ; chance a foreign letter in a trail changes
                             ; each time the sweep visits it, every 8
                             ; frames (0=never, 255=always)
         ELSE
COLS     equ  80             ; 80x24 for an RGB monitor
COLMASK  equ  $7F            ; column rolls: 0-127, rerolled while >= COLS
GIMERES  equ  $15            ; GIME resolution: 80 columns, attributes
GLITCH   equ  64
TRAILMIN equ  10
TRAILMAX equ  23
REVERSE  equ  64
NEWCHAR  equ  51
NUMDRIPS equ  70
SPDSTART equ  9
SPDRESET equ  5
GRAPHIC  equ  16
BLOCKGLITCH equ 255
         ENDC

; Speeds are drawn from 0-31, and a trail needs rows for the fade.
         IFGT SPDSTART-32
         ERROR SPDSTART must be 32 or less
         ENDC
         IFGT SPDRESET-32
         ERROR SPDRESET must be 32 or less
         ENDC
         IFGT NUMDRIPS-COLS
         ERROR NUMDRIPS must be COLS or less
         ENDC
         IFLT TRAILMIN-5
         ERROR TRAILMIN must be 5 or more for the fade
         ENDC

; ------------------------------------------------------------
; Constants
; ------------------------------------------------------------

ROWS     equ  24
ROWBYTES equ  COLS*2         ; 2 bytes a cell
SCREEN   equ  $2000          ; screen RAM (physical $72000)
SCREENEND equ SCREEN+ROWS*ROWBYTES
NOREVERSE equ SCREEN+(ROWS-1)*ROWBYTES ; the bottom row: no reverse heads
SWEEPCELLS equ COLS*ROWS/8   ; cells FLICKER sweeps a frame: an eighth

SPACE    equ  $20            ; an empty cell's character
FOREIGN  equ  $20            ; foreign letters are $00-$1F
HEAD     equ  $00            ; white on black
REVHEAD  equ  $21            ; black on bright green
BRIGHT   equ  $08            ; bright green on black
GREEN    equ  $10            ; green on black
DARK     equ  $18            ; dark green on black; also an empty cell's,
                             ; so a character glitched into a gap between
                             ; trails reads as residue, not a stray head

PIA0PB   equ  $FF02          ; reading it clears the field sync flag
PIA0CRB  equ  $FF03          ; bit 7 is set by field sync

; Drop records, one per drop, walked with U.
POS      equ  0              ; head screen address (word)
SPD      equ  2              ; frames between moves (0=fastest)
DEL      equ  3              ; frames waited so far
TRL      equ  4              ; trail length in rows
RECSIZE  equ  5

         org  $0E00
         setdp $0E

; ------------------------------------------------------------
; Variables ($0E00-$0E0F), on the direct page once start sets DP
; ------------------------------------------------------------

seedlo   fcb  0              ; random generator state
seedhi   fcb  0
headch   fcb  0              ; scratch for RNDHEAD
frames   fdb  0              ; frames drawn; only test builds use it
sweep    fdb  0              ; where FLICKER sweeps next
         zmb  9              ; the rest of the 16-byte area

; ============================================================
; Initialization
; ============================================================

start    orcc #$50           ; mask IRQ and FIRQ
         lds  #stacktop      ; keep every write inside our own memory
         lda  #$0E
         tfr  a,dp           ; direct page = the variables above
         sta  $FFD9          ; CPU to 1.79 MHz

; GIME: text with attributes, reading from physical $72000. These are
; the values BASIC's WIDTH 80 and WIDTH 40 write. The registers cannot
; be read back, so $FF90 is written whole, as BASIC does.
         lda  #$4C           ; CoCo 3 mode, MMU on, ROM as BASIC has it
         sta  $FF90
         lda  #$03           ; text, 8 lines a character row
         sta  $FF98
         lda  #GIMERES
         sta  $FF99
         clr  $FF9A          ; border: palette value 0, black
         clr  $FF9C          ; no vertical scroll
         lda  #$E4           ; video at $E400 x 8 = physical $72000
         sta  $FF9D
         clr  $FF9E
         clr  $FF9F          ; no horizontal offset
         ldx  #palette
         ldy  #$FFB0
setpal   lda  ,x+
         sta  ,y+
         cmpy #$FFC0
         bne  setpal

         ldx  #SCREEN        ; clear the screen to black spaces
         ldd  #SPACE*256+DARK
clrloop  std  ,x++
         cmpx #SCREENEND
         bne  clrloop

         lda  #21            ; seed the random generator, as the PET does
         sta  <seedlo
         lda  #$1C
         sta  <seedhi

         ldx  #SCREEN        ; FLICKER starts at the top
         stx  <sweep

         ldu  #drops
         ldy  #rainhis
         clrb                ; B = drop number x 2 = its column's offset
initdrop jsr  random         ; speed: 0 to SPDSTART-1, from 0-31
         anda #$1F
         cmpa #SPDSTART
         bhs  initdrop
         sta  SPD,u
         jsr  rndtrail
         sta  TRL,u
         clr  DEL,u
         lda  ,y+            ; $20 = top row, $1E = 256 cells above it
         std  POS,u
         leau RECSIZE,u
         addb #2
         cmpb #NUMDRIPS*2
         bne  initdrop

; ============================================================
; Main loop
; ============================================================

mainloop
         IFDEF TESTFRAMES
         ldd  <frames        ; a test build parks after TESTFRAMES frames,
         cmpd #TESTFRAMES    ; somewhere nothing changes, so a snapshot
         beq  testdone       ; shows exactly that frame
         addd #1
         std  <frames
         ENDC
         lda  PIA0PB         ; clear a field sync already flagged
waitsync lda  PIA0CRB        ; and wait for the next one
         bpl  waitsync
synced   jsr  draw           ; build-coco3.ps1 times frames from here
         jsr  flicker
         bra  mainloop

         IFDEF TESTFRAMES
testdone bra  testdone
         ENDC

; ============================================================
; DRAW - one frame
; ============================================================
; For each drop: refresh the head, maybe glitch one character in the
; trail, then move or wait. Moving erases the tail and sets the fade's
; colours behind the new head. U walks the drop records, and X holds
; the head address throughout.
; ============================================================

draw     ldu  #drops
nextdrop ldx  POS,u
         cmpx #SCREEN
         lblo timing         ; not on the screen yet
         cmpx #SCREENEND
         lbhs timing         ; already below it

; Head: usually keep what is there, sometimes pick anew. An empty cell
; always gets a fresh character. A kept character keeps a head's
; colours, and turns white if it belonged to another drop's trail.
         jsr  random
         cmpa #NEWCHAR
         bhs  keephead
         jsr  rndhead        ; A = character, B = attribute
         bra  placehead
keephead ldd  ,x
         cmpa #SPACE
         bne  keepattr
         jsr  rndhead
         bra  placehead
keepattr cmpb #HEAD
         beq  placehead
         cmpb #REVHEAD
         beq  placehead
         ldb  #HEAD
placehead
         cmpx #NOREVERSE
         blo  writehead
         ldb  #HEAD          ; no reverse heads on the bottom row
writehead
         std  ,x

; Now and then swap one character somewhere in the trail, keeping its
; colour. As on the PET, only while the row above the head is on screen.
         leay -ROWBYTES,x
         cmpy #SCREEN
         blo  timing
         jsr  random
         cmpa #GLITCH
         bhs  timing
         jsr  random
         anda #$0F           ; rows 1-15 up from the head
         beq  timing         ; row 0 is the head itself
         cmpa TRL,u
         bhs  timing         ; past the end of the trail
         ldb  #ROWBYTES
         mul                 ; D = rows x ROWBYTES
         coma                ; D = -D
         comb
         addd #1
         leay d,x
         cmpy #SCREEN
         blo  timing         ; above the screen (it cannot be below)
         jsr  rndchar
         sta  ,y

; Time to move?
timing   lda  DEL,u
         cmpa SPD,u
         beq  move
         inc  DEL,u
         lbra advance
move     clr  DEL,u

; Erase the tail, or recycle the drop once its whole trail has left
; the bottom of the screen.
         lda  TRL,u
         ldb  #ROWBYTES
         mul                 ; D = trail x ROWBYTES
         coma                ; D = -D
         comb
         addd #1
         leay d,x            ; Y = the tail
         cmpy #SCREENEND
         bhs  recycle
         cmpy #SCREEN
         blo  movedown       ; the tail is still above the screen
         ldd  #SPACE*256+DARK
         std  ,y
movedown leax ROWBYTES,x
         stx  POS,u

; The fade: bright green 1 row behind the new head, green 2 rows
; behind, dark green trail-2 rows behind. Every cell passes each point
; as the drop falls, so it takes on each colour in turn.
         ldb  #BRIGHT
         leay -ROWBYTES,x
         bsr  setattr
         ldb  #GREEN
         leay -2*ROWBYTES,x
         bsr  setattr
         lda  TRL,u
         suba #2
         ldb  #ROWBYTES
         mul
         coma
         comb
         addd #1
         leay d,x
         ldb  #DARK
         bsr  setattr
         bra  advance

; New column on the top row, new speed, new trail. Both rolls take a
; masked value and reroll while out of range, as the trail length does.
recycle  jsr  random
         anda #COLMASK
         cmpa #COLS
         bhs  recycle
         tfr  a,b
         lslb                ; the column's byte offset: 0-158
         ldx  #SCREEN
         abx                 ; ABX adds B unsigned
         stx  POS,u
newspeed jsr  random
         anda #$1F
         cmpa #SPDRESET
         bhs  newspeed
         sta  SPD,u
         jsr  rndtrail
         sta  TRL,u

advance  leau RECSIZE,u
         cmpu #drops+NUMDRIPS*RECSIZE
         lbne nextdrop
         rts

; SETATTR: store attribute B in the cell at Y, if Y is on the screen.
setattr  cmpy #SCREEN
         blo  setattrx
         cmpy #SCREENEND
         bhs  setattrx
         stb  1,y
setattrx rts

; ============================================================
; FLICKER - the foreign letters in the trails keep changing
; ============================================================
; Each frame sweeps an eighth of the screen, a different eighth each
; time, so every cell is visited every 8 frames. A foreign letter
; found in a trail (not a head) becomes another with chance
; BLOCKGLITCH. B counts the cells.
; ============================================================

flicker  ldx  <sweep
         ldb  #SWEEPCELLS
flickcell
         lda  ,x             ; foreign letters are below $20
         cmpa #FOREIGN
         bhs  flicknext
         lda  1,x            ; heads are left to DRAW
         cmpa #HEAD
         beq  flicknext
         cmpa #REVHEAD
         beq  flicknext
         jsr  random
         cmpa #BLOCKGLITCH
         bhs  flicknext
         jsr  rndforeign
         sta  ,x
flicknext
         leax 2,x
         decb
         bne  flickcell
         cmpx #SCREENEND     ; after the last eighth, back to the top
         bne  flicksave
         ldx  #SCREEN
flicksave
         stx  <sweep
         rts

; ============================================================
; RNDHEAD - a head: a new character, white, or reversed with the
; REVERSE chance. Out: A = character, B = attribute.
; ============================================================

rndhead  jsr  rndchar
         sta  <headch
         jsr  random
         ldb  #HEAD
         cmpa #REVERSE
         bhs  rndheadx
         ldb  #REVHEAD
rndheadx lda  <headch
         rts

; ============================================================
; RNDCHAR - a new rain character. Out: A.
; ============================================================
; Now and then a foreign letter, otherwise printable ASCII $21-$7E.

rndchar  jsr  random
         cmpa #GRAPHIC
         bhs  letter
                             ; fall into RNDFOREIGN
; RNDFOREIGN - a foreign letter, $00-$1F. Out: A.
rndforeign
         jsr  random
         anda #$1F
         rts
letter   jsr  random
         anda #$7F
         cmpa #$21
         blo  letter         ; control codes and space: reroll
         cmpa #$7F
         beq  letter
         rts

; ============================================================
; RNDTRAIL - trail length, TRAILMIN to TRAILMAX. Out: A.
; ============================================================

rndtrail jsr  random
         anda #$1F
         adda #TRAILMIN
         cmpa #TRAILMAX
         bhi  rndtrail
         rts

; ============================================================
; RANDOM - 16-bit LFSR, the PET routine instruction for instruction.
; Out: A. Preserves B, X, Y and U.
; ============================================================

random   lda  <seedhi
         lsra
         rol  <seedlo
         bcc  randomx
         eora #$B4           ; LFSR tap polynomial
randomx  sta  <seedhi
         eora <seedlo
         rts

; ============================================================
; Data
; ============================================================

; Palette slots 0-7 (backgrounds), then 8-15 (foregrounds).
; Backgrounds: black, bright green. Foregrounds: white, bright green,
; green, dark green, black.
palette
         IFDEF COMPOSITE
         fcb  $00,$21,$00,$00,$00,$00,$00,$00
         fcb  $30,$21,$11,$01,$00,$00,$00,$00
         ELSE
         fcb  $00,$12,$00,$00,$00,$00,$00,$00
         fcb  $3F,$12,$10,$02,$00,$00,$00,$00
         ENDC

; Starting high byte for each drop: $20 is the top row, $1E is 256
; cells above it. The PET's table, $7f and $80 becoming $1E and $20;
; the first NUMDRIPS entries are used.
rainhis  fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20
         fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20
         fcb  $20,$20,$20,$20,$1E,$20,$20,$20,$20,$20
         fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20
         fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20
         fcb  $20,$20,$20,$20,$1E,$20,$20,$20,$20,$20
         fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20
         fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20

codeend  equ  *              ; the .bin loads $0E00 up to here

; Reserved, not stored in the .bin.
drops    rmb  NUMDRIPS*RECSIZE
stack    rmb  64
stacktop equ  *
progend  equ  *

         IFGT progend-SCREEN
         ERROR the program runs into the screen at $2000
         ENDC

         end  start
```

- [ ] **Step 4: Run the test to see it pass**

Run: `pwsh -NoProfile -File .\build-coco3.ps1 -Test`
Expected, for the rgb build and then the composite build: a text screen, `Screen RAM: all 3,840 bytes match` (1,920 for composite) and `Other RAM:  all 512K unchanged while it ran`. Then `rgb cassette:` and `composite cassette:` `loads and runs`, the disk `SKIPPED`, and two `frame cost` lines with no warning. The spec estimates about 77% for rgb.

If a screen check fails, the message names the row, column and whether the character or the attribute differs. Compare that drop's handling in `draw` against `draw()` in the `.c`, especially the order of `random` calls and the three fade writes. If the RAM check fails at an address inside BASIC's area, compare the two snapshots there. If it's also different between two runs of the same build, XRoar runs aren't repeatable, and both snapshots need to come from one run instead.

- [ ] **Step 5: Check that the test catches a real difference**

Edit `matrix_rain_coco3.asm`: in the `ELSE` (RGB) block, change `GLITCH   equ  64` to `GLITCH   equ  65`.
Run: `pwsh -NoProfile -File .\build-coco3.ps1 -Test`
Expected: FAIL with `rgb: screen RAM differs from the reference model's ...`.
Edit it back to `64`. Change the fade instead: replace `ldb  #GREEN` with `ldb  #BRIGHT` in the fade block, run the test, and expect FAIL with an attribute difference. Revert that too, then run the test once more. Expected: PASS.

- [ ] **Step 6: Commit**

Write `C:\Users\Matth\AppData\Local\Temp\claude\msg3_task3.txt`:

```
Add the TRS-80 Color Computer 3 version

matrix_rain_coco3.asm runs the rain in the CoCo 3's attribute text
mode at 1.79 MHz: 80x24 with 70 drops for an RGB monitor, or with
COMPOSITE 40x24 with 40 drops for a TV. Trails fade from a white head
to dark green, and foreign letters flicker in the trails.
build-coco3.ps1 builds both with tape and disk images, and with -Test
checks each in XRoar against matrix_rain_coco3.c, checks that nothing
else in memory changes and that the images load, and times a frame.

~
```

Run: `git add build-coco3.ps1 matrix_rain_coco3.asm matrix_rain_coco3.bin matrix_rain_coco3_cmp.bin matrix_rain_coco3.cas matrix_rain_coco3_cmp.cas matrix_rain_coco3.dsk; git commit -F "$env:TEMP\claude\msg3_task3.txt"`

---

### Task 4: A minute without overruns

**Files:**
- No repository files unless tuning is needed (then `matrix_rain_coco3.asm`, `matrix_rain_coco3.c` and the generated files).

**Interfaces:**
- Consumes: `matrix_rain_coco3.asm`, `tools/xroar.ps1`.
- Produces: evidence that neither build misses a field over 3,600 frames.

The speed check samples only 10 frames. The CoCo 1/2 version needed a minute-long run to find its occasional slow frames.

- [ ] **Step 1: Write the overrun diagnostic**

Write `C:\Users\Matth\AppData\Local\Temp\claude\coco3_overrun.ps1`:

```powershell
# Runs a copy of matrix_rain_coco3.asm for many frames and counts frames
# whose drawing ran past the next field sync, plus the shortest wait for
# sync seen. The counters sit in spare variable bytes $0E0B-$0E0E.
param([int] $Frames = 3600)
$ErrorActionPreference = 'Stop'
$repo  = 'C:\OneDrive\Vintage Computing Development\CommodorePetMatrixRain'
. (Join-Path $repo 'tools\xroar.ps1')
$work  = Join-Path $env:TEMP 'matrix_rain_coco3'
$xroar = 'C:\Program Files\6809.org.uk\XRoar 1.9\xroar.exe'
$lwasm = 'C:\Development\_VintageDevelopment\lwtools\bin\lwasm.exe'

$src = (Get-Content (Join-Path $repo 'matrix_rain_coco3.asm') -Raw).Replace("`r`n", "`n")
$old = @'
         lda  PIA0PB         ; clear a field sync already flagged
waitsync lda  PIA0CRB        ; and wait for the next one
         bpl  waitsync
synced   jsr  draw           ; build-coco3.ps1 times frames from here
'@.Replace("`r`n", "`n")
$new = @'
         lda  PIA0CRB        ; diagnostic: a sync flagged during the draw
         bpl  diagok         ; means the frame overran
         ldd  <$0B
         addd #1
         std  <$0B
diagok   lda  PIA0PB
         ldx  #0
waitsync leax 1,x            ; 13 cycles a poll
         lda  PIA0CRB
         bpl  waitsync
         lda  PIA0PB         ; clear it now, so the check above means something
         cmpx <$0D
         bhs  diagmin
         stx  <$0D           ; fewest polls in any frame
diagmin  jsr  draw
'@.Replace("`r`n", "`n")
if (-not $src.Contains($old)) { throw 'main loop text not found' }
$src = $src.Replace($old, $new)
# Force extended addressing: DP is still BASIC's 0 at this point.
$src = $src.Replace("start    orcc #`$50", "start    ldd  #`$FFFF`n         std  >`$0E0D`n         orcc #`$50")
$asm = Join-Path $work 'overrun.asm'
Set-Content $asm $src

foreach ($build in @(@{ Name = 'rgb'; Defs = @() }, @{ Name = 'composite'; Defs = @('-D', 'COMPOSITE') })) {
    $bin = Join-Path $work "overrun_$($build.Name).bin"
    $sym = Join-Path $work "overrun_$($build.Name).sym"
    & $lwasm --decb @($build.Defs) -D "TESTFRAMES=$Frames" -o $bin "--symbol-dump=$sym" $asm
    if ($LASTEXITCODE -ne 0) { throw 'diagnostic build failed' }
    $labels = Read-LwasmSymbols $sym
    $snap = Join-Path $work "overrun_$($build.Name).sna"
    if (Test-Path $snap) { Remove-Item $snap }
    $null = Invoke-XRoar -XRoar $xroar -WorkDir $work -Machine 'coco3' -Log "overrun_$($build.Name).log" -EmulatedSeconds ($Frames / 60 + 30) -WaitSeconds 600 -Arguments @(
        '-ram', '512', '-run', (ConvertTo-XRoarPath $bin),
        '-trap', ('pc=0x{0:X4}' -f $labels['testdone']), '-trap-snap', (ConvertTo-XRoarPath $snap), '-trap-timeout', '1')
    $ram = Read-XRoarRam $snap
    $overruns = $ram[0x70E0B] * 256 + $ram[0x70E0C]
    $minPolls = $ram[0x70E0D] * 256 + $ram[0x70E0E]
    '{0,-9} frames: {1}  overran: {2} (the first frame may count once)  fewest polls: {3}, about {4:n0} cycles spare' -f `
        $build.Name, $Frames, $overruns, $minPolls, ($minPolls * 13)
}
```

- [ ] **Step 2: Run it**

Run: `& "$env:TEMP\claude\coco3_overrun.ps1"`
Expected: for both builds, `overran` of 0 or 1 (the first frame can count once because the flag is set when it starts), and a positive `fewest polls`.

- [ ] **Step 3: Tune only if needed**

If either build overran more than once, lower its `NUMDRIPS` by 5 in both `matrix_rain_coco3.asm` and `matrix_rain_coco3.c` (in the matching `IFDEF`/`#ifdef` block). Then re-run `pwsh -NoProfile -File .\build-coco3.ps1 -Test` and the diagnostic until both pass. Commit the change and the regenerated files with a message giving the measured before and after. If nothing overran, there's nothing to commit.

---

### Task 5: Look check and documentation

**Files:**
- Modify: `README.md` (new section after "## The Color Computer version")
- Modify: `CLAUDE.md` (new section after "### CoCo 1/2 version")
- Modify: `C:\Users\Matth\.claude\projects\C--OneDrive-Vintage-Computing-Development-CommodorePetMatrixRain\memory\coco-toolchain.md`

**Interfaces:**
- Consumes: everything above.
- Produces: documentation only, plus any tuning the user asks for.

- [ ] **Step 1: Show it to the user**

Run: `pwsh -NoProfile -File .\build-coco3.ps1 -Run`, then `pwsh -NoProfile -File .\build-coco3.ps1 -Run -Composite`.
Ask the user to confirm:
- **RGB window:** 80 columns; white heads over trails that fade through bright green and green to dark green; the odd reversed head, as black on bright green; flickering foreign letters in the trails.
- **Composite window:** the same at 40 columns. Coloured fringes on white heads are normal for composite.

Any tuning goes into both files. Then `-Test` must pass again, and the regenerated files are committed with the change.

- [ ] **Step 2: Add the README section**

In `README.md`, insert immediately above the line `## Running`:

````markdown
## The Color Computer 3 version

`matrix_rain_coco3.asm` is the effect in colour on the TRS-80 Color
Computer 3, using its hardware text mode, where every character has its
own colours. Each trail fades from a white head through bright green and
green to dark green, and foreign letters flicker through the trails in
place of the CoCo 1/2's graphics blocks. It runs the CPU at 1.79 MHz.

There are two builds:

- `MATRIX3`: 80×24 with 70 drops, for an RGB monitor such as the CM-8.
- `MATRIX3C`: 40×24 with 40 drops, for a TV or composite monitor.
  A composite colour signal can't carry 80 columns.

Load one with `LOADM"MATRIX3":EXEC` (the disk holds both) or
`CLOADM"MATRIX3":EXEC` from its tape image. It runs until you press
reset.

```powershell
.\build-coco3.ps1                  # writes both builds, their tapes and the disk
.\build-coco3.ps1 -Run             # opens the RGB build in XRoar
.\build-coco3.ps1 -Run -Composite  # opens the composite build
.\build-coco3.ps1 -Test            # checks both in XRoar against matrix_rain_coco3.c
```

The settings sit at the top of `matrix_rain_coco3.asm` and
`matrix_rain_coco3.c`, one block per build, and the two files have to
agree. They start from the PET 8032's (RGB) and 4032's (composite), with
trails capped at 23 rows.

````

- [ ] **Step 3: Add the CLAUDE.md section**

In `CLAUDE.md`, insert immediately above the line `## Architecture`:

````markdown
### CoCo 3 version

`matrix_rain_coco3.asm` is the CoCo 3 port: GIME attribute text at
1.79 MHz, `-D COMPOSITE` for the 40-column composite build (default 80
columns, RGB). `matrix_rain_coco3.c` is its reference, with the same
switch; change both together.

```powershell
.\build-coco3.ps1 [-Run [-Composite]] [-Test]
```

- The screen is at `$2000`, which is physical `$72000` in BASIC's memory
  map. It has 2 bytes a cell: the character, then an attribute. The
  attribute's foreground is in bits 5–3 (palette slots 8–15) and its
  background in bits 2–0 (slots 0–7).
- The GIME values come from BASIC's `WIDTH 80`/`40`: `$FF90`=`$4C`,
  `$FF98`=`$03`, `$FF99`=`$15`/`$05`, and `$FF9D`/`$FF9E`=`$E4`/`$00`.
  These registers are write-only.
- An empty cell is a space in `DARK`, not `HEAD`. Otherwise a glitch into
  a gap left by another drop's tail draws a stray white character.
- Test on `-machine coco3 -ram 512`. A snapshot holds RAM in physical
  order, with logical `$0000` at `$70000`. A field is 29,982 cycles, and
  trace `dt` is eighths of a cycle (`Measure-XRoarTrace -TicksPerCycle 8`).
- On XRoar's true composite modes (`-tv-input cmp-br`/`cmp-rb`), 80
  columns turns to coloured dots. `cmp` is really S-video.
- `lwasm -D` values are decimal only.
````

- [ ] **Step 4: Update the memory note**

Read `coco-toolchain.md`, then add this paragraph before its `**Why:**` line:

```markdown
- **CoCo 3**: XRoar `-machine coco3 -ram 512`; `-tv-input rgb`, `cmp`
  (S-video), `cmp-br`/`cmp-rb` (composite, where 80 columns is unreadable).
  GIME registers are write-only; read them from a snapshot's `GIME` part
  (tag `18`, 16 bytes for `$FF90`-`$FF9F`). Composite green is hue 1
  (`$01`/`$11`/`$21`), not BASIC's hue 2.
```

- [ ] **Step 5: Run everything once more**

Run: `pwsh -NoProfile -File .\tools\test_coco_tools.ps1; pwsh -NoProfile -File .\build-coco3.ps1 -Test; pwsh -NoProfile -File .\build-coco.ps1 -Test; pwsh -NoProfile -File .\build.ps1 -Test; git status --short`
Expected: all four pass, and `git status` shows only `README.md` and `CLAUDE.md` modified.

- [ ] **Step 6: Commit**

Write `C:\Users\Matth\AppData\Local\Temp\claude\msg3_task5.txt`:

```
Document the Color Computer 3 version

README gains a section on its two builds and how to load, build and
test them. CLAUDE.md records the GIME setup, the memory layout, why an
empty cell is dark green, and the XRoar facts the tests rely on.

~
```

Run: `git add README.md CLAUDE.md; git commit -F "$env:TEMP\claude\msg3_task5.txt"`
