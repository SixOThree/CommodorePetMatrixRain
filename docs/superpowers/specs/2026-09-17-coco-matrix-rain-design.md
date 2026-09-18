# Matrix Rain for the TRS-80 Color Computer 1/2: design

Date: 2026-09-17. Branch: `feature/coco-port`.

## Goal

A 6809 assembly version of the matrix rain for the CoCo 1 and 2, ported from
`matrix_rain_8032_noclock_v8.asm`. It runs in XRoar and on real hardware from
disk or cassette. A CoCo 3 version comes later and is not part of this work.

Out of scope: the CoCo 3 version, a C version that runs on the CoCo, and any
way to stop the program other than reset.

## How it looks and behaves

Green rain on a black screen. The CoCo 1/2 video chip (the MC6847) has two
renderings of each of its 64 text characters: dark on a bright green cell,
which is normal CoCo text, and bright green on a dark green cell, which is how
lowercase shows on a CoCo 1/2. Codes `$80`–`$FF` are semigraphics blocks: a
2×2 pattern of pixels in one of eight colours on true black, with green at
`$80`–`$8F` and buff (near white) at `$C0`–`$CF`.

- **Empty cells are `$80`**, the green block with no pixels lit, so the screen
  is true black and matches the black border of text mode.
- **Letters** use the bright-green-on-dark-green rendering. Each one sits on a
  faint dark green cell, which reads as a slight glow around the drops.
- **Green blocks appear sparingly.** When a new character is picked, a
  `GRAPHIC` chance (0 = never, 255 = always, like `GLITCH` and `REVERSE`)
  picks a green block instead of a letter.
- **A highlighted lead** has bit 6 set. A letter becomes dark on a bright
  green cell, the counterpart of the PET's reverse-video leads. A green block
  becomes a buff block, close to the film's bright lead glyph.
- **Dimming the old lead** clears bit 6 only (`AND #$BF`), which returns a
  letter to green on dark green and a buff block to green. Masking with `$3F`
  would be wrong: it would turn a block into a letter.

| | PET 8032 | CoCo 1/2 |
|---|---|---|
| empty cell | `$20` | `$80` (black) |
| new character | random `& $7F` | if random `< GRAPHIC`: `$80` \| (random `& $0F`), else random `& $3F` |
| fix-up of a blank pick | space `$20` becomes `!` `$21` | letter `$20` becomes `$21`; block `$80` becomes `$8F` |
| highlighted lead | set bit 7 | set bit 6 |
| dimming the old lead | clear bit 7 | clear bit 6 |
| "cell is empty" test | `== $20` | `== $80` |

The text characters are uppercase letters, digits and punctuation only.

The algorithm is unchanged: the same 16-bit random number generator with tap
`$B4` and seed `21`/`$1C`, and the same per-drop steps (refresh or replace the
lead character, dim the one above it, now and then swap one trail character,
then either wait, or erase the tail and move down, or recycle the drop once its
tail has left the screen). Only the geometry, the settings, the character codes
and the graphics-block choice in the character picker change. Two geometry
changes are deliberate:

- **Bounds stop at the screen edge.** The PET checks the full 2K of screen RAM,
  48 bytes more than it displays, and drops pass through those bytes on the way
  out. The CoCo's 512-byte screen at `$0400` ends exactly at its last visible
  row, and BASIC's memory follows it, so the checks are exactly `$0400` to
  `$05FF`.
- **No reverse video anywhere on the bottom row** (`$05E0` onwards). The PET's
  equivalent check covers only the last 32 cells of its bottom row, a constant
  that looks wrongly scaled from the 40-column version.

Starting settings, to be tuned by eye in XRoar:

| Setting | PET 8032 | CoCo start |
|---|---|---|
| `NUMDRIPS` (drops) | 70 of 80 columns | 28 of 32 columns |
| `TRAILMIN` / `TRAILMAX` | 10 / 24 rows | 6 / 14 rows |
| `SPDSTART` / `SPDRESET` | 9 / 5 | 9 / 5 |
| `GLITCH` / `REVERSE` / `NEWCHAR` | 64 / 64 / 51 | 64 / 64 / 51 |
| `GRAPHIC` (block chance) | none | 16, about 6% of new characters |

Trail lengths are still drawn as `(random & $1F) + TRAILMIN`, rerolled while
above `TRAILMAX`, and the glitch row as `random & $0F`. Picking a new character
takes one more random number than on the PET (the `GRAPHIC` roll), so the
CoCo's sequence of characters is its own, which is fine: the CoCo is checked
against its own reference model, not against the PET.

A CoCo 1/2 runs at 0.894886 MHz. An NTSC field is 262 lines of 57 cycles,
14,934 cycles at 60 Hz. A frame of drawing is expected to take about half of
that, so the rain should run at the full 60 fps.

To run it: `LOADM"MATRIX":EXEC` from disk, or `CLOADM"MATRIX":EXEC` from tape.
It needs 16K of RAM and runs until reset.

## Program structure

**Memory.** The program loads at `$0E00`, the first free address on a Disk
BASIC machine and safe on a cassette machine. Code, data and stack come to well
under 1K. The screen is `$0400`–`$05FF`.

**Startup.**

1. Mask interrupts (`ORCC #$50`). BASIC's 60 Hz interrupt handler would
   otherwise clear the vertical sync flag before the program could see it.
2. Point the stack at the program's own memory, so that every byte the program
   writes is either screen or its own memory (the test relies on this).
3. Point the direct page register at the program's variable page.
4. Put the display in text mode showing `$0400`, in case it was started after a
   graphics program: clear bits 3–7 of `$FF22` (the video chip's mode lines),
   and set the SAM (the chip that feeds screen memory to the video chip) to
   text mode with display offset `$0400`.
5. Fill the screen with `$80` (black), seed the random number generator and
   set up the drops, as the PET does.

**Frame timing.** The field sync signal from the video chip sets bit 7 of
`$FF03` on PIA 0. The main loop waits for that bit, clears it by reading
`$FF02`, draws one frame, and repeats. This replaces the PET's wait on bit 5 of
`$E840`.

**Drop data.** Each drop is a 5-byte record: screen address (2 bytes), speed,
delay count, trail length. A pointer walks from record to record, which is
cheaper on the 6809 than the PET's five separate tables indexed by drop number.
Drops start at `$04xx` (top row) or `$03xx` (above the screen), the PET's
`$80`/`$7F` high-byte trick moved to the CoCo's screen address. A drop starting
above the screen begins 8 rows up in its own column. On the PET the same trick
puts it about 3 rows up and 64 columns across, because 256 does not divide
evenly by 80, so the CoCo's opening wave is more drawn out. The stagger table is
the first 32 entries of the PET's.

**Arithmetic.**

- Trail length × 32 uses the 6809's `MUL` (11 cycles), replacing the PET's
  `MultiplyBy80`.
- Bounds checks are unsigned 16-bit compares against `$0400` and `$0600`.
  Addresses never fall below zero (the lowest a tail reaches is `$0140`), so no
  wraparound trick is needed.
- The random number generator ports instruction for instruction (`LSRA`, `ROL`,
  `BCC`, `EORA`): the carry behaves exactly as it does on the 6502.
- The seed and working variables sit on one page addressed through the direct
  page register, as cheap as the 6502's zero page. Safe because the program
  never returns to BASIC, and reset restores the register.

## Reference model

`matrix_rain_coco.c` is a copy of `matrix_rain_8032.c` with only the screen
geometry, the settings, the character codes and the graphics-block choice in
`rnd_char()` changed. Every other line of logic stays as it is, so that:

- a plain diff between the two C files lists exactly what the CoCo changed, and
- apart from that one addition, the logic is the version already proven byte
  for byte against the PET assembly.

It builds only for cc65's sim65 simulator, as the test reference; it is not
built for the CoCo. With `-DSIM_RAW` it prints the 512 screen bytes it expects
after a given number of frames. `matrix_rain_8032.c`, `build.ps1` and the PET
files do not change.

## Testing

`build-coco.ps1 -Test` does the following, and fails on any mismatch.

1. **Screen matches the reference.** XRoar runs the shipped `.bin`, unmodified.
   A trap on the main loop fires on its 401st arrival, exactly 400 frames in,
   and writes a snapshot. The test reads RAM from the snapshot by following the
   file's chunk structure, not a fixed offset, and compares `$0400`–`$05FF`
   with the reference model's output. A failure names the first differing
   address and both values.
2. **Nothing written outside the screen.** A second snapshot is taken on the
   first arrival at the main loop, after setup. Every byte of RAM outside the
   screen (`$0400`–`$05FF`) and the program's own memory (`$0E00` up to the
   end label, which includes its variables and stack) has to be identical in
   the two snapshots. This catches a write just past the screen, which would leave the
   screen itself matching.
3. **The images load and run.** The same comparison runs with the program
   loaded from the `.cas`, and from the `.dsk` when `disk11.rom` (Disk Extended
   Color BASIC 1.1) is in the ROM folder. Without that ROM the disk check is
   reported as skipped, never as passed.
4. **Speed.** Cycles per frame come from XRoar's instruction trace with timings
   over frames 101–110, excluding the time spent waiting for vertical sync, and
   are reported against the 14,934-cycle budget with a warning if a frame goes
   over. Going over slows the animation but is not a failure.

Tuning: `-Run` opens the program in XRoar to watch. A settings change goes into
both the assembly and `matrix_rain_coco.c`; the test fails until they agree.

## Files

New:

- `matrix_rain_coco.asm`: the 6809 source, LWTOOLS syntax.
- `matrix_rain_coco.c`: the reference model.
- `matrix_rain_coco.bin`, `.cas`, `.dsk`: the built program and its images,
  committed like the `.prg` files. The file is named `MATRIX` on tape and
  `MATRIX.BIN` on disk.
- `build-coco.ps1`: builds all three. `-Run` opens the `.bin` in XRoar;
  `-Test` runs the tests above. Takes the LWTOOLS, XRoar and cc65 folders as
  parameters, defaulting to this machine's.
- `tools/coco_images.ps1`: writes the `.cas` and `.dsk` from a `.bin`.
- `tools/xroar.ps1`: runs XRoar with traps (forward-slash paths, a scratch
  working folder, a timeout), reads RAM from a snapshot, and sums cycle counts
  from a trace.

Changed: `README.md` and `CLAUDE.md` gain a CoCo section.

**Image formats.** The `.cas` is the CoCo cassette byte stream: leader bytes
(`$55`), then blocks of sync byte `$3C`, block type, length, up to 255 data
bytes and a checksum. There is a name block (file name, type 2 for machine
code, exec and load addresses), data blocks and an end-of-file block. The
`.dsk` is a 35-track, 18-sector, 256-byte-sector Disk BASIC image with the
directory on track 17 (allocation table in sector 2, directory entries in
sectors 3–11) and the file stored in 9-sector granules.

## Toolchain

- LWTOOLS 4.25 in `C:\Development\_VintageDevelopment\lwtools\bin`, built from
  source with Visual Studio 2026.
- XRoar 1.9 in `C:\Program Files\6809.org.uk\XRoar 1.9`. ROMs in
  `C:\Users\Matth\Documents\XRoar\ROMS`: Color BASIC 1.0–1.4, Extended Color
  BASIC 1.0 and 1.1, CoCo 3. Test machine: `coco2bus` (NTSC CoCo 2B).
- cc65 with sim65, as for the PET work, for the reference model.
- XRoar treats `\` in option values as an escape, so every path passed to it
  uses forward slashes.

## To confirm early in implementation

- The character renderings in XRoar, on both `coco2bus` and `cocous`:
  `$00`–`$3F` bright green on dark green, `$40`–`$7F` dark on bright green,
  `$80`–`$8F` green blocks on black, `$C0`–`$CF` buff blocks on black.
- That XRoar accepts two traps in one run with `-trap-range`; if not, run it
  twice, which gives the same result because the program is deterministic.
- XRoar's snapshot chunk layout, its trace line format, and how `-run` starts a
  `.cas` and a `.dsk`.
