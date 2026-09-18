# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Vintage Computing Matrix Rain: a Matrix-style falling character animation for the Commodore PET 8032 and 4032 (6502 assembly, plus a C port) and the TRS-80 Color Computer 1/2 and 3 (6809 assembly). The GitHub repository is SixOThree/VintageComputingMatrixRain, formerly CommodorePetMatrixRain. Original concept from Petopia demo by Milasoft.

## Layout

One folder per machine, each holding its source, reference C, `build.ps1`
and the committed files it builds: `pet/` (8032 and 4032 assembly, the C
port), `coco/` (CoCo 1/2), `coco3/` (CoCo 3, both builds). `tools/` holds
the test harnesses, image writers and profiler; `docs/` the guides. Scripts
find their files from `$PSScriptRoot` and leave the caller's location as it
was, so they run from anywhere: the README runs them from the root
(`.\pet\build.ps1 -Test`), the guides from inside each machine's folder
(`.\build.ps1 -Test`).

## Build Commands

Build with ACME cross-assembler, from `pet/`:
```bash
acme -f cbm -o matrix_rain_8032_noclock_v8.prg matrix_rain_8032_noclock_v8.asm
```

ACME isn't installed on this machine. C64 Studio's command-line assembler is,
and with ACME syntax it rebuilds both committed PET `.prg` files byte for byte:

```powershell
& 'C:\OneDrive\Vintage Computing Development\C64StudioRelease\net8.0-windows\C64Ass\C64Ass.exe' -A ACME -F CBM -O matrix_rain_8032_noclock_v8.prg matrix_rain_8032_noclock_v8.asm
```

`docs/` holds four self-contained HTML guides: running the rain in VICE and in
XRoar, and building for the PET and for the CoCo. Keep their commands and
sample output in step with the scripts.

Run on Commodore PET or emulator (VICE xpet):
```
LOAD "matrix_rain_8032_noclock_v8.prg",8
RUN
```

The .prg file includes a BASIC stub (`10 SYS 1040`) that auto-starts the machine code.

### C version

`pet/matrix_rain_8032.c` is a port of the 8032 assembly, built with cc65:

```powershell
.\pet\build.ps1       # cl65 -t pet -Oi -Cl -o matrix_rain_8032_c.prg matrix_rain_8032.c
.\pet\build.ps1 -Run  # build, then launch in VICE xpet
.\pet\build.ps1 -Test # build for cc65's sim6502 target, dump the screen as
                      # text, fail unless all 2048 screen bytes match the
                      # assembly's, and report cycles per frame for both
.\tools\profile.ps1   # cycles per frame by routine, from a sim65 trace
```

`pet\build.ps1` runs cl65 from inside `pet/`, because `tools/asm_blob.s`
includes the 8032 `.prg` by a path relative to the folder cl65 runs in.

`-Test` is the regression test for the C port. `tools/asm_harness.c` loads
the shipped `matrix_rain_8032_noclock_v8.prg` at $0401 under sim65 (linked
with `tools/sim_asm.cfg`, which moves the harness up to $0800), skips the
KERNAL screen clear and the retrace loop, and calls the original init and
DRAW directly. It checks the bytes at $0410 and $0457 first, so a rebuilt
`.prg` with a different layout fails loudly instead of running the wrong
code. Both sides print screen RAM in hex when built with `-DSIM_RAW`.

`profile.ps1` drops `static` from a copy of the source so the functions get
labels, then refuses to report unless that copy runs to exactly the same
cycle count as the real source. Code layout matters here: moving a routine
changes which branches and indexed loads cross a page boundary, and each
crossing costs a cycle.

`-Cl` gives locals static storage. Nothing recurses, and cc65's software
stack is slow, so this is worth several percent. `-Oi` beats plain `-O`
here by about 7%.

The C version claims zero page $f7-$fe, the same eight bytes the assembly
used: seeds at $fb/$fc, two screen pointers at $fd/$fe and $f7/$f8, and
draw()'s loop index and character at $f9/$fa. A constant address below 256
assembles to zero page addressing, and cc65 emits `lda ($fd),y` directly
for a pointer held there instead of copying it into its own scratch first.

A frame costs about 31,400 cycles against the assembly's 18,450, both
measured under sim65. The C build produces a byte-identical screen.

The C source compiles for two targets. Under `__SIM6502__` it swaps screen
RAM for an array and the retrace wait for a frame counter, which is how
`-Test` checks the logic without a display.

### CoCo 1/2 version

`coco/matrix_rain_coco.asm` is a 6809 port for the TRS-80 Color Computer 1/2,
assembled with LWTOOLS and tested in XRoar:

```powershell
.\coco\build.ps1              # lwasm --decb, then the .cas and .dsk images
.\coco\build.ps1 -Run         # open the .bin in XRoar
.\coco\build.ps1 -Test        # screen vs matrix_rain_coco.c, RAM, images, speed
.\tools\test_coco_tools.ps1   # tests for the image writers and XRoar helpers
```

Tools on this machine: LWTOOLS 4.25 in
`C:\Development\_VintageDevelopment\lwtools\bin`, built from source with
Visual Studio; XRoar 1.9 in `C:\Program Files\6809.org.uk\XRoar 1.9`; ROMs
in `%USERPROFILE%\Documents\XRoar\ROMS`, which has no Disk BASIC ROM, so
`-Test` skips the disk image.

`matrix_rain_coco.c` is the test reference: a copy of the PET C port with
the CoCo's geometry, settings, character codes, graphics blocks, block
flicker and masked speed/column rolls. It builds only for sim65. Any change
to the drawing or the settings goes into both it and the `.asm`, in the same
order of random number calls, and `-Test` fails until they agree. Screen
codes: `$80` is an empty (black) cell, letters are `$00`-`$3F`, bit 6
highlights, green blocks are `$81`-`$8F`.

A frame must fit in 14,934 cycles (one NTSC field). `-Test` reports the
cost of frames 101-110; it is about 9,000, peaking near 9,800.

XRoar 1.9 behaviours the tests depend on:
- A `\` in an option value is an escape. Pass forward-slash paths
  (`ConvertTo-XRoarPath` in `tools/xroar.ps1`).
- A trap snapshot is written about 20 frames after its trap fires. The tests
  snapshot test builds (`lwasm -D TESTFRAMES=n`) that park at `testdone`.
- `-trap-trace` starts on the exact instruction; `-trap-no-trace` does
  nothing. A `pc=` trap on the entry address does not fire under `-run`.
- `-type` needs `\r` for Enter. A `.bin` given to `-load` is wiped when BASIC
  starts; use `-run`. `-ui null` runs with no window.
- Trace `dt=` is sixteenths of a CPU cycle. Time frames from just after the
  sync wait (the `synced` label), or a frame's total is off by the
  difference between consecutive frames' work.

### CoCo 3 version

`coco3/matrix_rain_coco3.asm` is the CoCo 3 port: GIME attribute text at
1.79 MHz, `-D COMPOSITE` for the 40-column composite build (default 80
columns, RGB). `matrix_rain_coco3.c` is its reference, with the same
switch; change both together.

```powershell
.\coco3\build.ps1 [-Run [-Composite]] [-Test]
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
- The RGB build runs 65 drops. At 70 it misses the field a few times a
  minute, even with the inline random step (`RAND`) and the four-cell
  flicker loop. `-Test` samples only 10 frames, so check a longer run
  before raising `NUMDRIPS` or adding work per drop.
- Test on `-machine coco3 -ram 512`. A snapshot holds RAM in physical
  order, with logical `$0000` at `$70000`. A field is 29,982 cycles, and
  trace `dt` is eighths of a cycle (`Measure-XRoarTrace -TicksPerCycle 8`).
- On XRoar's true composite modes (`-tv-input cmp-br`/`cmp-rb`), 80
  columns turns to coloured dots. `cmp` is really S-video.
- `lwasm -D` values are decimal only.

## Architecture

### Memory Layout
- **Code starts at**: `$0401` (1025) - standard PET BASIC program area
- **Screen RAM**: `$8000-$87CF` (80×25 = 2000 bytes)
- **VIA Port B**: `$E840` - bit 5 used for vertical retrace sync

### Zero Page Usage
- `$fb-$fc`: Temporary pointer/calculation
- `$fd-$fe`: Current rain drop screen address
- `$f7-$fa`: Multiply workspace

### Program Flow
1. **Init** (lines 40-98): Clears screen, seeds LFSR, initializes 80 columns with random speed/trail
2. **MainLoop** (lines 105-112): Waits for VIA vertical retrace, calls DRAW
3. **DRAW** (lines 125-357): Core animation - updates head char, dims previous head, applies trail glitch, handles movement timing
4. **MultiplyBy80** (lines 369-401): Utility using shift-add (n×80 = n×64 + n×16)
5. **RANDOM** (lines 411-419): 16-bit LFSR with polynomial tap `$b4`

### Per-Column Data Arrays (80 bytes each)
- `RAINLO/RAINHI`: Screen address (low/high byte)
- `SPEED`: Movement delay (0=fastest)
- `DEL`: Current delay counter
- `TRAIL`: Trail length

## Configuration Variables

Tunable parameters that affect visual appearance:
```
GLITCH   = 64   ; Trail glitch frequency (0=off, 255=constant)
TRAILMIN = 10   ; Minimum trail length in rows
TRAILMAX = 24   ; Maximum trail length in rows
REVERSE  = 64   ; Reverse video chance (0=never, 255=always)
NEWCHAR  = 51   ; New char generation chance (lower=more flicker)
NUMDRIPS = 70   ; Active columns (max 80, use 70 for gaps)
SPDSTART = 9    ; Initial speed range 0 to N-1 (lower=faster)
SPDRESET = 5    ; Reset speed range 0 to N-1 (lower=faster)
```

## Technical Notes

- Uses VIA vertical retrace for frame sync rather than cycle-counting
- Staggered Y start positions in `RAINHIS` create organic wave effect at startup
- Bottom screen row ($87B0+) forces normal video to prevent display glitches
- SPDRESET < SPDSTART creates acceleration effect as drops reset
