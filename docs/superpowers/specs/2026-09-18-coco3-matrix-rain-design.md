# Matrix Rain for the TRS-80 Color Computer 3: design

Date: 2026-09-18. Branch: `feature/coco-port`.

## Goal

A version of the matrix rain for the CoCo 3, in 6809 assembly, built on the
CoCo 1/2 version (`docs/superpowers/specs/2026-09-17-coco-matrix-rain-design.md`).
It uses the CoCo 3's colour attributes to fade each trail from a white head
down to dark green, and its 1.79 MHz speed mode to run at 60 fps. There are
two builds from one source:

- **RGB:** 80×24 with 65 drops, the PET 8032's width, for an RGB monitor
  such as the CM-8.
- **Composite:** 40×24 with 40 drops, the PET 4032's width, for a TV or
  composite monitor. A composite colour signal cannot carry 80 columns:
  in XRoar's composite modes 80-column text dissolves into coloured dots,
  while 40 columns stays readable (checked while planning).

Both run in XRoar and on real hardware from disk or cassette.

Out of scope: a C version that runs on the CoCo 3, and any way to stop the
program other than reset.

## The screen

The GIME's hardware text mode with attributes: two bytes a cell, the
character then its attribute. 80×24 is 3,840 bytes, 160 a row; 40×24 is
1,920 bytes, 80 a row. The screen sits at physical `$72000`, which the
processor sees at `$2000` in the memory map BASIC leaves, so the program
writes it directly. The border is black.

The font has 128 characters; codes 128-255 repeat them. `$20`-`$7F` are
ASCII, including lowercase. `$00`-`$1F` are accented and foreign letters:
`Ç ü é â ä à å ç ê ë è ï î ß Ä Å Ó æ Æ ô ö ø û ù Ø Ü § £ ± ° ƒ`. There
are no graphics blocks.

## Colours

An attribute byte holds a foreground colour in bits 5-3 (palette slots
8-15) and a background colour in bits 2-0 (slots 0-7); bit 7 (blink) and
bit 6 (underline) stay clear. Checked in XRoar while planning.

| Slot | Use | RGB value | Composite value |
|---|---|---|---|
| 0 | background: black | `$00` | `$00` |
| 1 | background: bright green, behind reverse heads | `$12` | `$21` |
| 8 | foreground: white, heads | `$3F` | `$30` |
| 9 | foreground: bright green | `$12` | `$21` |
| 10 | foreground: green | `$10` | `$11` |
| 11 | foreground: dark green | `$02` | `$01` |
| 12 | foreground: black, the character in a reverse head | `$00` | `$00` |

Other slots are black. The resulting attributes are:

| Name | Attribute | Look |
|---|---|---|
| `HEAD` | `$00` | white on black |
| `REVHEAD` | `$21` | black on bright green |
| `BRIGHT` | `$08` | bright green on black |
| `GREEN` | `$10` | green on black |
| `DARK` | `$18` | dark green on black |

The RGB values give 2 bits a colour channel (`$10` is green at two thirds).
The composite values use hue 1, the greenest in XRoar's rendering (BASIC's
own "green", hue 2, leans yellow), at brightness 0 to 2. On composite, white
heads show a coloured fringe, which is how a composite signal treats thin
bright strokes.

## The fade

A trail's colour depends on how many rows it is behind its head:

| Rows behind | Look |
|---|---|
| 0 (the head) | `HEAD`; or `REVHEAD` with the `REVERSE` chance |
| 1 | `BRIGHT` |
| 2 to trail−3 | `GREEN` |
| trail−2 and trail−1 | `DARK` |
| trail | erased |

Colours are set when a drop moves: after the move, the cells 1, 2 and
trail−2 rows behind the new head get `BRIGHT`, `GREEN` and `DARK`. Each
cell takes on its colours as the drop passes it, so a move costs three
attribute writes and the drop algorithm itself is unchanged. A trail glitch
replaces only the character and keeps the cell's colour.

**Heads.** A head given a new character gets `HEAD`, or `REVHEAD` with the
`REVERSE` chance. A head that keeps the character already in its cell keeps
its attribute if that is `HEAD` or `REVHEAD`; otherwise, a cell of another
drop's trail, it gets `HEAD`. No `REVHEAD` on the bottom row.

**Characters.** A letter is printable ASCII `$21`-`$7E`: `random & $7F`,
rerolled while below `$21` or equal to `$7F`. With the `GRAPHIC` chance a
new character is instead a foreign letter, `random & $1F`. An empty cell is
a space with attribute `DARK`, which shows as black. (Found while planning:
with `HEAD` there, a tail erased in the middle of another drop's trail left
a white gap attribute, and a trail glitch landing in it drew a stray white
character; the reference model showed 3 to 13 of them at any time. With
`DARK` it showed none.)

**Flicker.** Each frame a sweep covers an eighth of the screen, a different
eighth each time, so every cell is visited every 8 frames. A foreign letter
it finds whose attribute is not `HEAD` or `REVHEAD` becomes another random
foreign letter with the `BLOCKGLITCH` chance. At 255 that is about 7
changes a second, close to the CoCo 1/2's rate.

## Program structure

**Memory.** The program loads at `$0E00`. Code, tables, the drop records
and the stack sit between there and the screen at `$2000`.

**Startup.**

1. Mask interrupts, point the stack at the program's own memory, and point
   the direct page at the program's variables, as on the CoCo 1/2.
2. Switch the CPU to 1.79 MHz by writing `$FFD9`.
3. Set the GIME to text with attributes at physical `$72000`, with the
   values BASIC's `WIDTH 80` and `WIDTH 40` write (read from XRoar
   snapshots while planning): `$FF90` = `$4C`, `$FF98` = `$03`, `$FF99` =
   `$15` for 80 columns or `$05` for 40, `$FF9A` = `$00` (black border),
   `$FF9C` = `$00`, `$FF9D`/`$FF9E` = `$E4`/`$00` (physical `$72000`),
   `$FF9F` = `$00`. The GIME's registers cannot be read back, so `$FF90`
   is written whole; `$4C` is exactly what BASIC writes, keeping memory
   mapping on and the ROM mapped as BASIC has it. Then load the 16
   palette slots (`$FFB0`-`$FFBF`).
4. Clear the screen to spaces with `DARK`, seed the random number
   generator and set up the drops, as the PET does.

**Frame timing.** The same wait on PIA 0's field sync flag (`$FF03` bit 7,
cleared by reading `$FF02`) as the CoCo 1/2; it still works on a CoCo 3.
In XRoar a CoCo 3 field at 1.79 MHz is 29,982 CPU cycles (263 lines of
114).

**Drops.** The CoCo 1/2's 5-byte records walked with a pointer. A position
is its cell's screen address, `$2000 + (row × COLS + column) × 2`. A drop
that starts above the screen starts 256 cells up, as on the PET, which at
80 columns reproduces the PET 8032's sideways scatter (the drop enters
about 3 rows later and 64 columns across) and at 40 columns the 4032's.
Both builds take the first `NUMDRIPS` entries of the PET's 80-entry stagger
table (the 4032's table is its first 40). Rows behind the head are
`rows × COLS × 2` bytes, from `MUL`.

**Settings**, from the PET 8032 and 4032, with trails capped for 24 rows:

| Setting | RGB (80 columns) | Composite (40 columns) |
|---|---|---|
| `NUMDRIPS` | 65 (70 missed the field; see Budget) | 40 |
| `TRAILMIN` / `TRAILMAX` | 10 / 23 | 14 / 23 |
| `SPDSTART` / `SPDRESET` | 9 / 5 | 15 / 8 |
| `GLITCH` / `REVERSE` / `NEWCHAR` | 64 / 64 / 51 | 64 / 64 / 51 |
| `GRAPHIC` | 16 | 16 |
| `BLOCKGLITCH` | 255 | 255 |

Random rolls keep the CoCo 1/2's masked form: speeds from `random & $1F`;
columns from `random & $7F` rerolled while 80 or more (80 columns), or
`random & $3F` rerolled while 40 or more (40 columns).

**Budget.** For 80 columns, about 260 cycles a drop for 70 drops, roughly
18,000 cycles, plus about 5,000 for the sweep: roughly 23,000 of 29,982
(77%). 40 columns is about half that. The speed test reports the real
figures; if the 80-column build is too close, `NUMDRIPS` or the sweep size
comes down.

**Measured during implementation.** At 70 drops the RGB build averaged
25,866 cycles a frame, peaked at 30,100, and missed the field in 20 of
3,600 frames. A frame's work swings by about 6,000 cycles, from frames
where many drops move and recycle at once, so the average alone hides the
problem. Two changes that leave the random number sequence, and so the
screen, exactly as before:

- the random number step is written inline (`RAND`) for the three rolls
  every drop makes every frame, saving a `JSR` and `RTS` (13 cycles)
  each; `RANDOM` is `RAND` plus `RTS`;
- the flicker sweep takes four cells a pass, paying the loop's overhead
  once for four.

Together they saved about 2,900 cycles a frame. At 70 drops that still
left 2 misses a minute; at 65 there were none in 10,800 frames (three
minutes), with the tightest frame 1,250 cycles short of the field. The RGB
build therefore has 65 drops. The composite build peaks at 46%.

## Reference model

`matrix_rain_coco3.c` is a copy of `matrix_rain_coco.c` changed for
two-byte cells, the fade, foreign letters, the eighth-screen sweep, the
PET's stagger table and the wider column rolls. `-DCOMPOSITE` selects the
40-column geometry and settings, as the same define does in the `.asm`. It
builds only for cc65's sim65; with `-DSIM_RAW` it prints every screen byte,
characters and attributes. Any change to the drawing or the settings goes
into both it and the `.asm`, in the same order of random number calls.

## Testing

`build-coco3.ps1 -Test`, on XRoar's `coco3` machine with 512K, for each
build:

1. **Screen matches the reference.** A 400-frame test build
   (`-D TESTFRAMES=400`) parks; its screen, attributes included, must match
   the reference model's for the same geometry.
2. **Nothing written outside the screen.** A 0-frame test build parks
   right after setup. Every byte of all 512K outside the screen and the
   program's own memory must be the same in both snapshots.
3. **The images load and run.** The tape image with `CLOADM`, and the disk
   image with `LOADM` when Disk BASIC's ROM is available; each build must
   load its own bytes.
4. **Speed.** Frames 101-110 timed from the `synced` label (trace `dt` is
   eighths of a cycle at 1.79 MHz), reported against the 29,982-cycle
   field.

## Files

New:

- `matrix_rain_coco3.asm`: the program; `-D COMPOSITE` makes the 40-column
  composite build.
- `matrix_rain_coco3.c`: the reference model; `-DCOMPOSITE` likewise.
- `build-coco3.ps1`: builds both and their images. `-Run` opens the RGB
  build in XRoar set to an RGB monitor; `-Run -Composite` opens the
  composite build with XRoar set to composite (`cmp-br`); `-Test` runs the
  checks for both. Takes the same tool-path parameters as `build-coco.ps1`.
- Built and committed: `matrix_rain_coco3.bin` and
  `matrix_rain_coco3_cmp.bin`, `matrix_rain_coco3.cas` and
  `matrix_rain_coco3_cmp.cas`, and `matrix_rain_coco3.dsk` holding both.
  The files are `MATRIX3` (RGB) and `MATRIX3C` (composite) on tape and disk.

Changed:

- `tools/xroar.ps1`: `Read-XRoarRam` accepts 128K and 512K RAM (a 512K
  snapshot stores RAM in physical order, so logical `$2000` is at offset
  `$72000`); `Measure-XRoarTrace` takes the number of trace time units per
  CPU cycle as a parameter (16 on a CoCo 1/2, 8 at 1.79 MHz).
- `tools/coco_images.ps1`: `New-CocoDsk` can put several files on one disk.
- `tools/test_coco_tools.ps1`: tests for both changes.
- `README.md`, `CLAUDE.md`: a CoCo 3 section.

The CoCo 1/2 files do not change, other than through the shared tools, and
the CoCo 1/2 tests must keep passing.

## Confirmed in XRoar while planning

- `WIDTH 80` leaves `$FF90`-`$FF9F` as `4C 00 00 00 FF FF 00 00 03 15 12 00
  00 D8 00 00`; `WIDTH 40` differs only in `$FF99` = `$05`. MMU task 0 maps
  blocks `$38`-`$3F`, so logical `$2000` is physical `$72000`.
- The attribute layout and the palette values above, by screenshots of
  test patterns on `-tv-input rgb`, `cmp`, `cmp-br` and `cmp-rb`.
- PIA 0's field sync works on a CoCo 3; a field is 29,982 cycles.
- A 512K snapshot's RAM element starts at file offset 230 in the probe and
  holds RAM in physical order.
- At 1.79 MHz a trace's `dt` counts eighths of a cycle: a known 523-cycle
  loop measured 523 with `dt / 8`.
- `lwasm -D NAME=value` takes decimal values; `$20` is not read as hex
  there.
