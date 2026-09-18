# Matrix Rain for the TRS-80 Color Computer 3: design

Date: 2026-09-18. Branch: `feature/coco-port`.

## Goal

An 80-column version of the matrix rain for the CoCo 3, in 6809 assembly,
built on the CoCo 1/2 version (`docs/superpowers/specs/2026-09-17-coco-matrix-rain-design.md`).
It uses the CoCo 3's colour attributes to fade each trail from a white head
down to dark green, and its 1.79 MHz speed mode to run 70 drops at 60 fps.
It runs in XRoar and on real hardware from disk or cassette, on an RGB or a
composite monitor.

Out of scope: a 40-column version, a C version that runs on the CoCo 3, and
any way to stop the program other than reset.

## The screen

80×24 text in the GIME's hardware text mode with attributes: two bytes a
cell, the character then its attribute, 3,840 bytes in all. The screen sits
at physical `$72000`, which the processor sees at `$2000` in the memory map
BASIC leaves, so the program writes it directly. The border is black.

The 80-column font has 128 characters; codes 128-255 repeat them. `$20`-`$7F`
are ASCII, including lowercase. `$00`-`$1F` are accented and foreign letters:
`Ç ü é â ä à å ç ê ë è ï î ß Ä Å Ó æ Æ ô ö ø û ù Ø Ü § £ ± ° ƒ`. There
are no graphics blocks.

## Colours

An attribute byte holds a foreground colour (palette slots 8-15) and a
background colour (slots 0-7); the program uses neither blink nor underline.
The palette holds:

| Use | Slot |
|---|---|
| background: black | a background slot |
| background: bright green, behind reverse heads | a background slot |
| foreground: white, heads | a foreground slot |
| foreground: bright green | a foreground slot |
| foreground: green | a foreground slot |
| foreground: dark green | a foreground slot |
| foreground: black, the character in a reverse head | a foreground slot |

The exact slot numbers are fixed in the plan. The palette values come from
one of two tables, RGB or composite, chosen when assembling (`-D MONITOR=...`,
RGB by default), because the same palette code shows a different colour on
the two kinds of monitor.

## The fade

A trail's colour depends on how many rows it is behind its head:

| Rows behind | Look |
|---|---|
| 0 (the head) | white on black; or, with the `REVERSE` chance, black on bright green |
| 1 | bright green |
| 2 to trail−3 | green |
| trail−2 and trail−1 | dark green |
| trail | erased |

Colours are set when a drop moves: after the move, the cells 1, 2 and
trail−2 rows behind the new head get bright green, green and dark green.
Each cell takes on its colours as the drop passes it, so a move costs three
attribute writes and the drop algorithm itself is unchanged. A trail glitch
replaces only the character and keeps the cell's colour.

**Heads.** A head given a new character is white, or reversed with the
`REVERSE` chance. A head that keeps the character already in its cell keeps
its colour if that is a head colour (white or reversed); otherwise, a cell
of another drop's trail, it turns white. No reverse heads on the bottom row.

**Characters.** A letter is printable ASCII `$21`-`$7E`: `random & $7F`,
rerolled while below `$21` or equal to `$7F`. With the `GRAPHIC` chance a new
character is instead a foreign letter, `random & $1F`. An empty cell is a
space, black on black.

**Flicker.** Each frame a sweep covers an eighth of the screen (240 cells),
a different eighth each time, so every cell is visited every 8 frames. A
foreign letter it finds in a trail, not a head, becomes another random
foreign letter with the `BLOCKGLITCH` chance. At 255 that is about 7
changes a second, close to the CoCo 1/2's rate. The CoCo 1/2 sweeps a
quarter of its screen; the CoCo 3's screen has 3.75 times as many cells.

## Program structure

**Memory.** The program loads at `$0E00`. Code, tables, the drop records
and the stack sit between there and the screen at `$2000`.

**Startup.**

1. Mask interrupts, point the stack at the program's own memory, and point
   the direct page at the program's variables, as on the CoCo 1/2.
2. Switch the CPU to 1.79 MHz by writing `$FFD9`. An NTSC field is then
   29,868 cycles.
3. Set the GIME to 80×24 text with attributes reading from physical
   `$72000`: clear the CoCo 1/2 compatibility bit in `$FF90` while keeping
   its memory-mapping and ROM bits as BASIC left them, set the video mode
   (`$FF98`), resolution (`$FF99`), video address (`$FF9D`/`$FF9E`),
   horizontal offset (`$FF9F`) and border (`$FF9A`), and load the palette
   (`$FFB0`-`$FFBF`). The register values come from what BASIC's
   `WIDTH 80` writes, read out of an XRoar snapshot while planning, not
   from memory.
4. Clear the screen to black spaces, seed the random number generator and
   set up the drops, as the PET does.

**Frame timing.** The same wait on PIA 0's field sync flag (`$FF03` bit 7,
cleared by reading `$FF02`) as the CoCo 1/2, if the CoCo 3 still delivers
it there (to confirm).

**Drops.** The CoCo 1/2's 5-byte records walked with a pointer. A position
is its cell's screen address, `$2000 + (row × 80 + column) × 2`. A drop
that starts above the screen starts 256 cells up, as on the PET; at 80
columns that also reproduces the PET's quirk of the drop entering about 3
rows later and 64 columns across. The stagger table is the PET's full
80-entry table. Rows behind the head are `rows × 160` bytes, from `MUL`.

**Settings**, starting from the PET's with trails capped for 24 rows:

| Setting | Start |
|---|---|
| `NUMDRIPS` | 70 |
| `TRAILMIN` / `TRAILMAX` | 10 / 23 |
| `GLITCH` / `REVERSE` / `NEWCHAR` | 64 / 64 / 51 |
| `SPDSTART` / `SPDRESET` | 9 / 5 |
| `GRAPHIC` | 16 |
| `BLOCKGLITCH` | 255 |

Random rolls keep the CoCo 1/2's masked form: speeds from `random & $1F`,
and columns from `random & $7F`, rerolled while 80 or more.

**Budget.** About 260 cycles a drop for 70 drops, roughly 18,000 cycles,
plus about 5,000 for the sweep: roughly 23,000 of 29,868 (77%). The speed
test reports the real figure; if it is too close, `NUMDRIPS` or the sweep
size comes down.

## Reference model

`matrix_rain_coco3.c` is a copy of `matrix_rain_coco.c` changed for the
80×24 screen of two-byte cells, the fade, foreign letters, the eighth-screen
sweep, the PET's stagger table and the 0-127 column roll. It builds only for
cc65's sim65; with `-DSIM_RAW` it prints all 3,840 screen bytes, characters
and attributes. Any change to the drawing or the settings goes into both it
and the `.asm`, in the same order of random number calls.

## Testing

`build-coco3.ps1 -Test`, on XRoar's `coco3` machine with 512K:

1. **Screen matches the reference.** A 400-frame test build
   (`-D TESTFRAMES=400`) parks; its 3,840 screen bytes, attributes
   included, must match the reference model's.
2. **Nothing written outside the screen.** A 0-frame test build parks
   right after setup. Every byte of all 512K outside the screen and the
   program's own memory must be the same in both snapshots. The whole 512K
   is compared because a wrong address or memory-mapping setting could
   write anywhere in it.
3. **The images load and run.** The tape images with `CLOADM`, the disk
   image with `LOADM` when Disk BASIC's ROM is available; each variant must
   load its own bytes.
4. **Speed.** Frames 101-110 timed from the `synced` label, reported
   against the 29,868-cycle budget.

The RGB and composite builds differ only in their palette table, so the
screen checks run once, on the RGB build.

## Files

New:

- `matrix_rain_coco3.asm`: the program.
- `matrix_rain_coco3.c`: the reference model.
- `build-coco3.ps1`: builds both variants and their images. `-Run` opens
  the RGB build in XRoar set to an RGB monitor; `-Run -Composite` opens the
  composite build with XRoar set to composite; `-Test` runs the checks.
  Takes the same tool-path parameters as `build-coco.ps1`.
- Built and committed: `matrix_rain_coco3.bin` and
  `matrix_rain_coco3_cmp.bin`, `matrix_rain_coco3.cas` and
  `matrix_rain_coco3_cmp.cas`, and `matrix_rain_coco3.dsk` holding both.
  The files are `MATRIX3` (RGB) and `MATRIX3C` (composite) on tape and disk.

Changed:

- `tools/xroar.ps1`: `Read-XRoarRam` accepts 128K and 512K RAM;
  `Measure-XRoarTrace` takes the number of trace time units per CPU cycle
  as a parameter.
- `tools/coco_images.ps1`: `New-CocoDsk` can put several files on one disk.
- `tools/test_coco_tools.ps1`: tests for both changes.
- `README.md`, `CLAUDE.md`: a CoCo 3 section.

The CoCo 1/2 files do not change, other than through the shared tools, and
the CoCo 1/2 tests must keep passing.

## To confirm in XRoar before writing the program

- The GIME register values BASIC's `WIDTH 80` writes, and which bits of
  `$FF90` must be kept.
- The attribute byte layout: foreground in bits 5-3 (slots 8-15),
  background in bits 2-0 (slots 0-7).
- That PIA 0's field sync flag still works on a CoCo 3.
- How a 512K snapshot lays out RAM, so the screen is found at physical
  `$72000`.
- What a trace's `dt` counts at 1.79 MHz (sixteenths of a slow cycle on the
  CoCo 1/2; possibly eighths of a fast one here).
- XRoar's option for an RGB or composite monitor.
- Palette values that give white and the four greens on each monitor.
