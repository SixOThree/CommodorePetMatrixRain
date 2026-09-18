# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a 6502 assembly language project that creates a Matrix-style falling character animation for the Commodore PET 8032 (80-column display). Original concept from Petopia demo by Milasoft.

## Build Commands

Build with ACME cross-assembler:
```bash
acme -o matrix_rain_8032_noclock_v8.prg matrix_rain_8032_noclock_v8.asm
```

Run on Commodore PET or emulator (VICE xpet):
```
LOAD "matrix_rain_8032_noclock_v8.prg",8
RUN
```

The .prg file includes a BASIC stub (`10 SYS 1040`) that auto-starts the machine code.

### C version

`matrix_rain_8032.c` is a port of the 8032 assembly, built with cc65:

```powershell
.\build.ps1          # cl65 -t pet -Oi -Cl -o matrix_rain_8032_c.prg matrix_rain_8032.c
.\build.ps1 -Run     # build, then launch in VICE xpet
.\build.ps1 -Test    # build for cc65's sim6502 target, dump the screen as
                     # text, fail unless all 2048 screen bytes match the
                     # assembly's, and report cycles per frame for both
.\tools\profile.ps1  # cycles per frame by routine, from a sim65 trace
```

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
