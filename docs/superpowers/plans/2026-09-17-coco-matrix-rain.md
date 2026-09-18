# CoCo 1/2 Matrix Rain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A 6809 assembly version of the matrix rain for the TRS-80 Color Computer 1/2, with tape and disk images, checked byte for byte against a C reference model in XRoar.

**Architecture:** `matrix_rain_coco.asm` is a port of the PET assembly to the CoCo's 32×16 screen. `matrix_rain_coco.c`, a copy of the proven PET C port with CoCo geometry, runs under cc65's sim65 as the reference. `build-coco.ps1` assembles with LWTOOLS, writes `.cas` and `.dsk` images with `tools/coco_images.ps1`, and tests in XRoar with `tools/xroar.ps1`.

**Tech Stack:** 6809 assembly (LWTOOLS 4.25 `lwasm`), C (cc65 / sim65), PowerShell 7, XRoar 1.9.

**Spec:** `docs/superpowers/specs/2026-09-17-coco-matrix-rain-design.md`

## Global Constraints

- Branch `feature/coco-port`. Commit messages lead with a plain description of the change, never mention Claude or Codex, carry no `Co-Authored-By` line, and end with a line containing only `~`. Write the message to a file with the Write tool and commit with `git commit -F <file>`.
- Write every file with the Write tool. Run shell work with the PowerShell tool. Never put file content in a Bash command.
- Do not modify `matrix_rain_8032.c`, `build.ps1`, `matrix_rain_8032_noclock_v8.*`, `matrix_rain_4032.*` or `matrix_rain_8032_c.prg`.
- Tool paths: LWTOOLS `C:\Development\_VintageDevelopment\lwtools\bin`, XRoar `C:\Program Files\6809.org.uk\XRoar 1.9\xroar.exe`, cc65 `C:\Development\_VintageDevelopment\cc65_snapshot`, ROMs `%USERPROFILE%\Documents\XRoar\ROMS` (no Disk BASIC ROM yet).
- Screen `$0400`–`$05FF` (512 bytes). Program loads at `$0E00`. Test machine `coco2bus`.
- Settings, identical in the `.asm` and the `.c`: GLITCH 64, TRAILMIN 6, TRAILMAX 14, REVERSE 64, NEWCHAR 51, NUMDRIPS 28, SPDSTART 9, SPDRESET 5, GRAPHIC 16.
- Screen codes: empty `$80`; letter `rnd & $3F`, a `$20` becomes `$21`; block `$80 | (rnd & $0F)`, a `$80` becomes `$8F`; highlight sets bit 6; dimming clears bit 6 only (`AND #$BF`).
- XRoar 1.9 facts, measured while planning:
  - A backslash in an option value is an escape. Pass paths with forward slashes, quoted (`ConvertTo-XRoarPath`), and run XRoar from a scratch folder.
  - A trap snapshot is written about 20 frames after its trap fires. Snapshot only a program that has parked in a loop that writes nothing.
  - `-trap-trace` starts tracing on the exact instruction. `-trap-no-trace` has no effect, so a trace runs until XRoar exits.
  - A `pc=` trap on a program's entry address does not fire when `-run` starts it.
  - Several `-trap` options with `-trap-range N` work in one run.
  - `-type` needs `\r` for Enter. A `.bin` given to `-load` is wiped when BASIC starts, so use `-run` for `.bin` files.
  - `-ui null` runs without a window. `-cart help` lists `rsdos` as the disk controller.
  - Trace lines look like `0e06| 4c          INCA   ...  dt=32`. `dt` is the instruction's time in sixteenths of a CPU cycle, except on the first traced line, where it is the time since tracing was armed.
  - An NTSC field is 14,934 CPU cycles.
- LWTOOLS facts: `lwasm --decb` writes the `.bin`; `-D NAME=VALUE` defines a symbol; `--symbol-dump=FILE` writes lines like `mainloop EQU $0E10`; `--list=FILE` needs the `=` form. Labels on a line by themselves are fine. Symbols containing `@` or `?` are local and a blank line ends their scope, so this plan uses only plain global labels. `RMB` at the end of the program is not stored in the `.bin`.

---

## File Structure

| File | Responsibility |
|---|---|
| `matrix_rain_coco.c` (new) | Reference model. Copy of the PET C port with CoCo geometry. sim65 only. |
| `tools/coco_images.ps1` (new) | `Read-DecbBin`, `New-CocoCas`, `New-CocoDsk`. |
| `tools/xroar.ps1` (new) | `ConvertTo-XRoarPath`, `Invoke-XRoar`, `Read-XRoarRam`, `Read-LwasmSymbols`, `Measure-XRoarTrace`. |
| `tools/fixtures/fill.asm` (new) | Small 6809 program with known screen contents and known cycles per frame. |
| `tools/test_coco_tools.ps1` (new) | Tests for the two tool files, using the fixture. |
| `matrix_rain_coco.asm` (new) | The CoCo program. |
| `build-coco.ps1` (new) | Build, `-Run`, `-Test`. |
| `matrix_rain_coco.bin`, `.cas`, `.dsk` (new, generated, committed) | The shipped program and its images. |
| `README.md`, `CLAUDE.md` (modified) | CoCo section. |

---

### Task 1: The C reference model

**Files:**
- Create: `matrix_rain_coco.c`

**Interfaces:**
- Consumes: nothing.
- Produces: `matrix_rain_coco.c`, built with `cl65 -t sim6502 -Oi -Cl -DSIM_RAW -DSIM_FRAMES=<n>`, prints 512 lines of two hex digits, screen offsets 0 to 511. Without `SIM_RAW` it prints a 16×32 text view. Task 4 compares the CoCo program against the `SIM_RAW` output.

- [ ] **Step 1: Write the check that the reference output is sane**

Write `C:\Users\Matth\AppData\Local\Temp\claude\coco_ref_check.ps1`:

```powershell
# Builds matrix_rain_coco.c for sim65 and checks its screen after 400
# frames is made only of codes the CoCo program can produce.
$ErrorActionPreference = 'Stop'
$repo  = 'C:\OneDrive\Vintage Computing Development\CommodorePetMatrixRain'
$cc65  = 'C:\Development\_VintageDevelopment\cc65_snapshot\bin'
$out   = Join-Path $env:TEMP 'coco_ref_check.bin'
& "$cc65\cl65.exe" -t sim6502 -Oi -Cl -DSIM_RAW -o $out (Join-Path $repo 'matrix_rain_coco.c')
if ($LASTEXITCODE -ne 0) { throw 'build failed' }
$b = @(& "$cc65\sim65.exe" $out | ForEach-Object { [Convert]::ToByte($_, 16) })
"bytes: $($b.Count) (want 512)"
$valid = { param($v)
    ($v -eq 0x80) -or
    ($v -lt 0x80 -and ($v -band 0x3F) -ne 0x20) -or
    (($v -band 0xB0) -eq 0x80 -and ($v -band 0x0F) -ne 0) }
$bad = @($b | Where-Object { -not (& $valid $_) })
"invalid codes: $($bad.Count) (want 0)"
"empty cells: "        + @($b | Where-Object { $_ -eq 0x80 }).Count
"letters: "            + @($b | Where-Object { $_ -lt 0x40 }).Count
"highlighted letters: " + @($b | Where-Object { $_ -ge 0x40 -and $_ -lt 0x80 }).Count
"green blocks: "       + @($b | Where-Object { $_ -gt 0x80 -and $_ -lt 0x90 }).Count
"buff blocks: "        + @($b | Where-Object { $_ -ge 0xC0 }).Count
"highlights on the bottom row: " + @($b[480..511] | Where-Object { $_ -ne 0x80 -and ($_ -band 0x40) }).Count + ' (want 0)'
```

- [ ] **Step 2: Run it to see it fail**

Run (PowerShell tool): `& "$env:TEMP\claude\coco_ref_check.ps1"`
Expected: FAIL. `cl65` reports it cannot open `matrix_rain_coco.c`, and the script throws `build failed`.

- [ ] **Step 3: Write `matrix_rain_coco.c`**

```c
/* ============================================================
 * Matrix Rain Effect (TRS-80 Color Computer 1/2) - C reference
 * ============================================================
 * The reference model for matrix_rain_coco.asm. It builds only for
 * cc65's 6502 simulator, not for the CoCo: build-coco.ps1 -Test runs
 * it for 400 frames and requires the 6809 program to leave screen RAM
 * exactly as this does.
 * Original from Petopia demo by Milasoft.
 *
 * Author: Matthew Dugal (github.com/SixOThree)
 * ============================================================
 *
 * Build:  cl65 -t sim6502 -Oi -Cl -DSIM_RAW -o reference.bin matrix_rain_coco.c
 *
 * This is a copy of matrix_rain_8032.c, the PET C port that was
 * checked byte for byte against the PET assembly. Only these differ:
 *
 *   - the screen is 32x16, 512 bytes, and the bounds stop at its edge
 *   - the settings are tuned for the smaller screen, plus GRAPHIC
 *   - the character codes: an empty cell is $80, a graphics block with
 *     no pixels lit, which shows as black; letters are masked with $3F;
 *     bit 6 highlights instead of bit 7
 *   - rnd_char() now and then picks a green graphics block
 *   - there is no PET entry point
 *
 * Diff the two files to see exactly that list.
 *
 * A drop's position is a signed offset from the start of screen RAM.
 * Negative means the drop has not reached the top of the screen yet.
 * The 6809 program keeps the same thing as a screen address: $04xx is
 * the top row and $03xx is above the screen.
 * ============================================================ */

#ifndef __SIM6502__
#error "matrix_rain_coco.c is the CoCo reference model: build it with -t sim6502"
#endif

#include <stdio.h>

/* ------------------------------------------------------------
 * Configuration
 * ------------------------------------------------------------
 * Keep these in step with matrix_rain_coco.asm: the test fails until
 * they agree. */

#define GLITCH      64      /* trail glitch frequency (0=off, 255=constant) */
#define TRAILMIN     6      /* minimum trail length (rows)                  */
#define TRAILMAX    14      /* maximum trail length (rows)                  */
#define REVERSE     64      /* highlight chance (0=never, 255=always)       */
#define NEWCHAR     51      /* new char chance (lower=more flicker)         */
#define NUMDRIPS    28      /* active drops (max 32)                        */
#define SPDSTART     9      /* initial speed range (0 to N-1, lower=faster) */
#define SPDRESET     5      /* reset speed range (0 to N-1, lower=faster)   */
#define GRAPHIC     16      /* graphics block chance (0=never, 255=always)  */

/* ------------------------------------------------------------
 * Screen geometry and character codes
 * ------------------------------------------------------------ */

#define COLS        32
#define ROWS        16
#define CHR_EMPTY   0x80    /* a graphics block with no pixels lit: black  */
#define CHR_SPACE   0x20    /* a letter-set space: an empty dark green cell */
#define CHR_BANG    0x21    /* stands in for a space so heads stay visible */
#define CHARMASK    0x3f    /* the 64 letters, digits and symbols          */
#define RVS         0x40    /* bit 6 highlights: a letter goes dark on a
                             * bright green cell, a green block goes buff  */
#define BLOCK       0x80    /* a green graphics block; pixels in bits 0-3  */
#define BLOCK_FULL  0x8f    /* all four pixels lit                         */

/* The CoCo's screen ends exactly at its last visible row, and BASIC's
 * memory follows it. Unlike the PET there is no spare screen RAM past
 * the bottom for a drop to pass through, so the bounds are the screen. */
#define SCREEN_SIZE 512

/* True when a screen offset lands inside screen RAM. A negative offset
 * wraps to a very large unsigned value, so one comparison does the work
 * of checking both ends. Only safe where the offset cannot legitimately
 * exceed the screen by more than it could fall below zero, which is
 * every use below except the tail. */
#define ON_SCREEN(off) ((unsigned int)(off) < SCREEN_SIZE)

/* No highlighting anywhere on the bottom row, which starts at 480. */
#define NOREVERSE   480

/* The simulator has no CoCo screen, so the screen is an array. */
static unsigned char sim_screen[SCREEN_SIZE];
#define screen sim_screen

/* ------------------------------------------------------------
 * Per-column state
 * ------------------------------------------------------------ */

/* The head offset is held as two byte arrays rather than one array of
 * int. cc65 reads an int array by doubling the index, building a pointer
 * and loading through it, which comes to about 44 cycles; two indexed
 * byte loads cost roughly 12. The assembly kept RAINLO and RAINHI apart
 * for the same reason. */
static unsigned char poslo[COLS];   /* head offset, low byte            */
static unsigned char poshi[COLS];   /* head offset, high byte           */

#define POS_GET(n)    ((int)(unsigned int)(poslo[n] | ((unsigned int)poshi[n] << 8)))
#define POS_SET(n, v) do {                          \
        unsigned int pos_ = (unsigned int)(v);      \
        poslo[n] = (unsigned char)pos_;             \
        poshi[n] = (unsigned char)(pos_ >> 8);      \
    } while (0)

static unsigned char speed[COLS];   /* frames between moves (0=fastest) */
static unsigned char del[COLS];     /* frames waited so far             */
static unsigned char trail[COLS];   /* trail length in rows             */

/* Row offsets, split into bytes for the same reason as the position.
 * This one is read once per column per frame, so an int array here cost
 * more than the position did. */
static unsigned char rowofflo[TRAILMAX + 1];
static unsigned char rowoffhi[TRAILMAX + 1];

#define ROWOFF(n) ((int)(unsigned int)(rowofflo[n] | ((unsigned int)rowoffhi[n] << 8)))

/* Staggered start positions. A mix of "already falling" and "starts at
 * the top" gives the wave effect at startup. These are the first 32
 * entries of the PET's table.
 *
 * ABOVE is 256 cells up, which is what the PET assembly's $7f high byte
 * meant. On this screen that is exactly 8 rows, so a drop starting
 * ABOVE enters in its own column, 8 moves later. */

#define ABOVE   (-256)
#define TOP     0

static const int rainhis[COLS] = {
    ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP,
    ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP, ABOVE, TOP,
    TOP,   TOP, TOP,   TOP, ABOVE, TOP, TOP,   TOP, TOP,   TOP,
    ABOVE, TOP
};

/* ============================================================
 * RANDOM - 16-bit LFSR
 * ============================================================
 * A direct port of the assembly routine, seed and all:
 *
 *   lda seedhi / lsr / rol seedlo / bcc + / eor #$b4 / + sta seedhi
 *   eor seedlo
 * ============================================================ */

/* The seeds, the screen pointers, draw()'s loop index and the character
 * it is placing all sit at the PET port's fixed zero page addresses.
 * There they made the code faster. Here they are kept so that this file
 * differs from matrix_rain_8032.c only where the CoCo needs it; the
 * simulator leaves $f7 to $fe free. */
#define seedlo (*(unsigned char *)0x00FB)
#define seedhi (*(unsigned char *)0x00FC)
#define cell   (*(unsigned char **)0x00FD)
#define cell2  (*(unsigned char **)0x00F7)
#define col    (*(unsigned char *)0x00F9)
#define headch (*(unsigned char *)0x00FA)

static unsigned char rnd(void)
{
    /* The branch is taken before seedlo is overwritten, so there is no
     * need to stash the old top bit. Saying the shift twice costs a few
     * bytes and saves cc65 a spilled temporary on every call. */
    if (seedlo & 0x80) {                            /* carry out of rol */
        seedlo = (unsigned char)((seedlo << 1) | (seedhi & 1));
        seedhi = (unsigned char)((seedhi >> 1) ^ 0xB4);
    } else {
        seedlo = (unsigned char)((seedlo << 1) | (seedhi & 1));
        seedhi >>= 1;
    }
    return (unsigned char)(seedhi ^ seedlo);
}

/* A new rain character: now and then a green graphics block, otherwise
 * a letter, digit or symbol. Never a cell that looks empty: a block with
 * no pixels lit becomes the full block, and a space becomes '!'. */
static unsigned char rnd_char(void)
{
    unsigned char ch;

    if (rnd() < GRAPHIC) {
        ch = (unsigned char)(BLOCK | (rnd() & 0x0f));
        if (ch == BLOCK) {
            ch = BLOCK_FULL;
        }
    } else {
        ch = rnd() & CHARMASK;
        if (ch == CHR_SPACE) {
            ch = CHR_BANG;
        }
    }
    return ch;
}

/* A head character, sometimes highlighted. */
static unsigned char rnd_head(void)
{
    unsigned char ch = rnd_char();

    if (rnd() < REVERSE) {
        ch |= RVS;
    }
    return ch;
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

    for (off = 0; off < SCREEN_SIZE; ++off) {
        screen[off] = CHR_EMPTY;
    }

    for (n = 0; n <= TRAILMAX; ++n) {
        unsigned int off_ = (unsigned int)n * COLS;
        rowofflo[n] = (unsigned char)off_;
        rowoffhi[n] = (unsigned char)(off_ >> 8);
    }

    for (i = 0; i < NUMDRIPS; ++i) {
        do {
            n = rnd();
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
 * For each drop: refresh the head, dim the head it left behind,
 * maybe glitch one character in the trail, then move or wait.
 * ============================================================ */

static void draw(void)
{
    unsigned char row;
    unsigned char t;
    int           p;
    int           other;

    for (col = 0; col < NUMDRIPS; ++col) {
        p = POS_GET(col);
        t = trail[col];

        if (ON_SCREEN(p)) {
            cell = screen + p;

            /* Head: usually keep what is there, sometimes reroll.
             * An empty cell always gets a fresh character. */
            if (rnd() < NEWCHAR) {
                headch = rnd_head();
            } else {
                headch = *cell;
                if (headch == CHR_EMPTY) {
                    headch = rnd_head();
                }
            }

            if (p >= NOREVERSE) {
                headch &= (unsigned char)~RVS;
            }
            *cell = headch;

            /* Drop the highlight off the head one row up. */
            other = p - COLS;
            if (ON_SCREEN(other)) {
                cell2 = screen + other;
                *cell2 = (unsigned char)(*cell2 & ~RVS);

                /* Swap one character somewhere in the trail. */
                if (rnd() < GLITCH) {
                    row = rnd() & 0x0f;
                    if (row != 0 && row < t) {
                        other = p - ROWOFF(row);
                        if (ON_SCREEN(other)) {
                            screen[other] = rnd_char();
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

        /* Erase the last character of the trail. This one stays a signed
         * comparison. A drop that has not reached the top of the screen
         * has a tail far below zero, and ON_SCREEN would read that as
         * having fallen off the bottom. */
        other = p - ROWOFF(t);

        if (other >= SCREEN_SIZE) {
            /* The whole drop has left the screen. Recycle it: new
             * column, new speed, new trail. Reset drops are faster
             * than the initial ones, which makes the rain accelerate. */
            do {
                headch = rnd();
            } while (headch >= COLS);
            POS_SET(col, headch);

            do {
                headch = rnd();
            } while (headch >= SPDRESET);
            speed[col] = headch;

            trail[col] = rnd_trail();
            continue;
        }

        if (other >= 0) {
            screen[other] = CHR_EMPTY;
        }

        POS_SET(col, p + COLS);
    }
}

/* ============================================================
 * Entry point
 * ============================================================ */

#ifndef SIM_FRAMES
#define SIM_FRAMES 400
#endif

/* Print the screen as text: '.' empty, '*' letter, '#' highlighted
 * letter, 'o' green block, '@' highlighted (buff) block.
 *
 * Built with SIM_RAW, print every byte of screen RAM in hex instead,
 * one per line, for build-coco.ps1 -Test to compare with the CoCo's. */
static void dump(void)
{
#ifdef SIM_RAW
    unsigned int r;

    for (r = 0; r < SCREEN_SIZE; ++r) {
        printf("%02x\n", screen[r]);
    }
#else
    unsigned int  r;
    unsigned int  c;
    unsigned char v;

    for (r = 0; r < ROWS; ++r) {
        for (c = 0; c < COLS; ++c) {
            v = screen[r * COLS + c];
            if (v == CHR_EMPTY) {
                putchar('.');
            } else if (v & BLOCK) {
                putchar((v & RVS) ? '@' : 'o');
            } else {
                putchar((v & RVS) ? '#' : '*');
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
    }
    dump();
    return 0;
}
```

- [ ] **Step 4: Run the check to see it pass**

Run: `& "$env:TEMP\claude\coco_ref_check.ps1"`
Expected: `bytes: 512`, `invalid codes: 0`, `highlights on the bottom row: 0`, and non-zero counts for empty cells, letters, highlighted letters and green blocks. Buff blocks may be 0 at frame 400.

- [ ] **Step 5: Look at the text view**

Run: `& 'C:\Development\_VintageDevelopment\cc65_snapshot\bin\cl65.exe' -t sim6502 -Oi -Cl -o "$env:TEMP\coco_ref_text.bin" matrix_rain_coco.c; & 'C:\Development\_VintageDevelopment\cc65_snapshot\bin\sim65.exe' "$env:TEMP\coco_ref_text.bin"`
Expected: 16 lines of 32 characters that look like falling columns of `*` with the occasional `o`, `#` near the lower ends of columns, and `.` elsewhere.

- [ ] **Step 6: Review the diff against the PET port**

Run: `git diff --no-index --stat matrix_rain_8032.c matrix_rain_coco.c; git diff --no-index matrix_rain_8032.c matrix_rain_coco.c`
Expected: the only differences are the header comment, the configuration values plus `GRAPHIC`, the geometry and character-code block, the 32-entry `rainhis`, the zero page comment, `rnd_char()`, `CHR_EMPTY` in `init()` and `draw()`, `~RVS` in place of `0x7f` in `draw()`, and the entry point section. No other logic lines differ. (`git diff --no-index` exits 1 when files differ; that is expected.)

- [ ] **Step 7: Commit**

Write `C:\Users\Matth\AppData\Local\Temp\claude\msg_task1.txt`:

```
Add the C reference model for the CoCo version

matrix_rain_coco.c is a copy of the PET C port with the CoCo's 32x16
screen, its character codes, graphics blocks and tuned settings. It
builds only for cc65's simulator, where it gives the screen the 6809
program must reproduce.

~
```

Run: `git add matrix_rain_coco.c; git commit -F "$env:TEMP\claude\msg_task1.txt"`

---

### Task 2: Tape and disk image writers

**Files:**
- Create: `tools/fixtures/fill.asm`
- Create: `tools/coco_images.ps1`
- Create: `tools/test_coco_tools.ps1`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces (dot-source `tools/coco_images.ps1`; every path argument must be a full path):
  - `Read-DecbBin([string] $Path)` → `[pscustomobject] @{ Segments = [object[]] (each @{ Address = [int]; Bytes = [byte[]] }); Exec = [int] }`
  - `New-CocoCas -Bin <full path> -Name <up to 8 chars> -Path <full path>` → writes the file; throws unless the `.bin` has exactly one segment.
  - `New-CocoDsk -Bin <full path> -Name <up to 8 chars> [-Extension 'BIN'] -Path <full path>` → writes a 161,280-byte image.
  - `tools/fixtures/fill.asm` with global labels `start` (`$0E00`), `mainloop`, `waitsync`, `done`.
  - `tools/test_coco_tools.ps1` ending with a `# --- summary ---` section that Task 3 inserts before.

- [ ] **Step 1: Write the fixture program**

`tools/fixtures/fill.asm`:

```
; Fixture for tools\test_coco_tools.ps1.
;
; Fills the 32x16 screen with 0, 1, 2 ... 255, 0, 1 ... 255, then runs
; 12 frames that each do exactly 523 cycles of work after the field
; sync, then parks at DONE. The tests read the pattern back through a
; snapshot and the 523 cycles through a trace.

        org     $0E00
start   orcc    #$50            ; interrupts off, as the real program does
        ldx     #$0400
        clra
fill    sta     ,x+
        inca
        cmpx    #$0600
        bne     fill
        ldy     #0              ; frames run so far

mainloop
        cmpy    #12             ; 5 cycles
        beq     done            ; 3
        leay    1,y             ; 5
        lda     $FF02           ; 5   clear the field sync flag
waitsync
        lda     $FF03           ; waiting, not counted as work
        bpl     waitsync
        ldb     #100            ; 2
busy    decb                    ; 2 } 100 times: 500
        bne     busy            ; 3 }
        bra     mainloop        ; 3   work per frame: 523

done    bra     done
        end     start
```

- [ ] **Step 2: Write the tests**

`tools/test_coco_tools.ps1`:

```powershell
<#
.SYNOPSIS
    Tests for the CoCo helpers in tools\coco_images.ps1 and tools\xroar.ps1.

.DESCRIPTION
    Assembles tools\fixtures\fill.asm and checks the .bin reader and the
    cassette and disk image writers. Prints PASS, FAIL or SKIP for each
    check and exits 1 if any failed.
#>

[CmdletBinding()]
param(
    [string] $Lwtools = 'C:\Development\_VintageDevelopment\lwtools\bin',
    [string] $XRoar   = 'C:\Program Files\6809.org.uk\XRoar 1.9\xroar.exe',
    [string] $Roms    = (Join-Path $env:USERPROFILE 'Documents\XRoar\ROMS')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'coco_images.ps1')

$work = Join-Path $env:TEMP 'coco_tools_test'
New-Item -ItemType Directory -Force $work | Out-Null
$script:failures = 0

function Check([string] $What, [bool] $Ok, [string] $Detail = '') {
    if ($Ok) { Write-Host "PASS  $What" }
    else     { Write-Host "FAIL  $What  $Detail"; $script:failures++ }
}

function Hex([byte[]] $Bytes) { [Convert]::ToHexString($Bytes) }

# A DECB .bin written by hand: one segment per entry of $Segments, each
# @(address, length), filled with the low byte of each byte's address.
function New-TestBin([string] $Path, [object[]] $Segments, [int] $Exec) {
    $out = [Collections.Generic.List[byte]]::new()
    foreach ($s in $Segments) {
        $address, $length = $s
        $out.AddRange([byte[]] (0x00, ($length -shr 8), ($length -band 0xFF), ($address -shr 8), ($address -band 0xFF)))
        for ($i = 0; $i -lt $length; $i++) { $out.Add([byte] (($address + $i) -band 0xFF)) }
    }
    $out.AddRange([byte[]] (0xFF, 0x00, 0x00, ($Exec -shr 8), ($Exec -band 0xFF)))
    [IO.File]::WriteAllBytes($Path, $out.ToArray())
}

# The fixture: see tools\fixtures\fill.asm.
$bin = Join-Path $work 'fill.bin'
$sym = Join-Path $work 'fill.sym'
& (Join-Path $Lwtools 'lwasm.exe') --decb -o $bin "--symbol-dump=$sym" (Join-Path $PSScriptRoot 'fixtures\fill.asm')
if ($LASTEXITCODE -ne 0) { throw 'tools\fixtures\fill.asm did not assemble' }
$binBytes = [IO.File]::ReadAllBytes($bin)

# --- Read-DecbBin ---
$fixture = Read-DecbBin $bin
Check 'Read-DecbBin: one segment, loading at $0E00' ($fixture.Segments.Count -eq 1 -and $fixture.Segments[0].Address -eq 0x0E00)
Check 'Read-DecbBin: the segment is the whole file less its 10 bytes of framing' ($fixture.Segments[0].Bytes.Length -eq $binBytes.Length - 10)
Check 'Read-DecbBin: exec address $0E00' ($fixture.Exec -eq 0x0E00)

# --- New-CocoCas ---
$cas = Join-Path $work 'fill.cas'
New-CocoCas -Bin $bin -Name 'FILL' -Path $cas
$c = [IO.File]::ReadAllBytes($cas)
Check 'cassette: starts with 128 leader bytes' (@($c[0..127] | Where-Object { $_ -ne 0x55 }).Count -eq 0)
Check 'cassette: then a 15-byte name block' ($c[128] -eq 0x55 -and $c[129] -eq 0x3C -and $c[130] -eq 0x00 -and $c[131] -eq 15)
$name = [Text.Encoding]::ASCII.GetString($c, 132, 8)
Check 'cassette: the name is FILL' ($name -eq 'FILL    ') "got '$name'"
Check 'cassette: machine code, binary, no gaps' ($c[140] -eq 2 -and $c[141] -eq 0 -and $c[142] -eq 0)
Check 'cassette: exec and load addresses $0E00' ($c[143] -eq 0x0E -and $c[144] -eq 0 -and $c[145] -eq 0x0E -and $c[146] -eq 0)
$sum = 0; for ($i = 130; $i -lt 147; $i++) { $sum += $c[$i] }
Check 'cassette: name block checksum' ($c[147] -eq ($sum % 256) -and $c[148] -eq 0x55)
Check 'cassette: second leader' (@($c[149..276] | Where-Object { $_ -ne 0x55 }).Count -eq 0)

# Walks the data blocks from $At and returns the bytes they carry, or
# $null if any block is malformed or anything follows the end block.
function Read-CasData([byte[]] $C, [int] $At) {
    $data = [Collections.Generic.List[byte]]::new()
    while ($true) {
        if ($C[$At] -ne 0x55 -or $C[$At + 1] -ne 0x3C) { return $null }
        $type = $C[$At + 2]; $len = $C[$At + 3]
        $sum = $type + $len
        for ($i = 0; $i -lt $len; $i++) {
            $sum += $C[$At + 4 + $i]
            if ($type -eq 1) { $data.Add($C[$At + 4 + $i]) }
        }
        if ($C[$At + 4 + $len] -ne ($sum % 256) -or $C[$At + 5 + $len] -ne 0x55) { return $null }
        $At += 6 + $len
        if ($type -eq 0xFF) { break }
        if ($type -ne 1) { return $null }
    }
    if ($At -ne $C.Length) { return $null }
    ,$data.ToArray()
}
$data = Read-CasData $c 277
Check 'cassette: well-formed data blocks and end block' ($null -ne $data)
Check 'cassette: the data blocks hold the program' ($null -ne $data -and (Hex $data) -eq (Hex $fixture.Segments[0].Bytes))

$big = Join-Path $work 'big.bin'
New-TestBin $big @(, @(0x2000, 600)) 0x2000
$bigCas = Join-Path $work 'big.cas'
New-CocoCas -Bin $big -Name 'BIG' -Path $bigCas
$bc = [IO.File]::ReadAllBytes($bigCas)
Check 'cassette: 600 bytes split 255 + 255 + 90' ($bc[280] -eq 255 -and $bc[280 + 261] -eq 255 -and $bc[280 + 522] -eq 90)
$bigData = Read-CasData $bc 277
Check 'cassette: split blocks reassemble' ($null -ne $bigData -and (Hex $bigData) -eq (Hex (Read-DecbBin $big).Segments[0].Bytes))

$two = Join-Path $work 'two.bin'
New-TestBin $two @(@(0x2000, 10), @(0x3000, 10)) 0x2000
$refused = $false
try { New-CocoCas -Bin $two -Name 'TWO' -Path (Join-Path $work 'two.cas') } catch { $refused = $true }
Check 'cassette: refuses a .bin with two segments' $refused

# --- New-CocoDsk ---
$dsk = Join-Path $work 'fill.dsk'
New-CocoDsk -Bin $bin -Name 'FILL' -Path $dsk
$k = [IO.File]::ReadAllBytes($dsk)
$fat = (17 * 18 + 1) * 256          # track 17, sector 2
$dir = (17 * 18 + 2) * 256          # track 17, sector 3
Check 'disk: 35 tracks of 18 sectors of 256 bytes' ($k.Length -eq 161280)
Check 'disk: directory entry FILL.BIN' ([Text.Encoding]::ASCII.GetString($k, $dir, 11) -eq 'FILL    BIN')
Check 'disk: machine code, binary, starting in granule 0' ($k[$dir + 11] -eq 2 -and $k[$dir + 12] -eq 0 -and $k[$dir + 13] -eq 0)
Check 'disk: bytes in the last sector' (($k[$dir + 14] * 256 + $k[$dir + 15]) -eq $binBytes.Length) 'fill.bin fits in one sector'
Check 'disk: the next directory entry is unused' ($k[$dir + 32] -eq 0xFF)
Check 'disk: granule 0 is the last, using 1 sector' ($k[$fat] -eq 0xC1)
Check 'disk: the other 67 granules are free' (@(1..67 | Where-Object { $k[$fat + $_] -ne 0xFF }).Count -eq 0)
Check 'disk: granule 0 holds the .bin as is' ((Hex $k[0..($binBytes.Length - 1)]) -eq (Hex $binBytes))

$long = Join-Path $work 'long.bin'
New-TestBin $long @(, @(0x2000, 3000)) 0x2000
$longDsk = Join-Path $work 'long.dsk'
New-CocoDsk -Bin $long -Name 'LONG' -Path $longDsk
$lk = [IO.File]::ReadAllBytes($longDsk)
$longBytes = [IO.File]::ReadAllBytes($long)
Check 'disk: a 3,010-byte file chains granule 0 to granule 1' ($lk[$fat] -eq 1 -and $lk[$fat + 1] -eq 0xC3)
Check 'disk: and fills them in order' ((Hex $lk[0..3009]) -eq (Hex $longBytes))
Check 'disk: 194 bytes in its last sector' (($lk[$dir + 14] * 256 + $lk[$dir + 15]) -eq 194)

# --- summary ---
Write-Host ''
if ($script:failures) { Write-Host "$($script:failures) check(s) failed"; exit 1 }
Write-Host 'All checks passed'
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `pwsh -NoProfile -File .\tools\test_coco_tools.ps1`
Expected: FAIL at the dot-source line, because `tools\coco_images.ps1` does not exist.

- [ ] **Step 4: Write `tools/coco_images.ps1`**

```powershell
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

    function Get-Offset([int] $Track, [int] $Sector) { ($Track * $perTrack + $Sector - 1) * $sector }
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
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `pwsh -NoProfile -File .\tools\test_coco_tools.ps1`
Expected: every line `PASS`, then `All checks passed`, exit code 0.

- [ ] **Step 6: Commit**

Write `C:\Users\Matth\AppData\Local\Temp\claude\msg_task2.txt`:

```
Add cassette and disk image writers for the CoCo

tools/coco_images.ps1 reads a DECB .bin and writes it as a .cas for
CLOADM and a Disk BASIC .dsk for LOADM. tools/test_coco_tools.ps1 checks
both against a small fixture program and hand-made .bin files.

~
```

Run: `git add tools/coco_images.ps1 tools/test_coco_tools.ps1 tools/fixtures/fill.asm; git commit -F "$env:TEMP\claude\msg_task2.txt"`

---

### Task 3: XRoar helpers

**Files:**
- Create: `tools/xroar.ps1`
- Modify: `tools/test_coco_tools.ps1` (insert before `# --- summary ---`)

**Interfaces:**
- Consumes: `Read-DecbBin`, `New-CocoCas`, `New-CocoDsk`, the fixture and its labels from Task 2.
- Produces (dot-source `tools/xroar.ps1`):
  - `ConvertTo-XRoarPath([string] $Path)` → `"C:/full/path"` including the quotes.
  - `Invoke-XRoar -XRoar <exe> -WorkDir <folder> -Arguments <string[]> [-Machine 'coco2bus'] [-Log 'xroar.log'] [-EmulatedSeconds 60] [-WaitSeconds 120]` → returns the path of the log file holding XRoar's standard output (and so any trace). Adds `-machine`, `-ui null`, `-ao null`, `-no-ratelimit` and `-timeout`.
  - `Read-XRoarRam([string] $Snapshot)` → `[byte[]]` of 16K, 32K or 64K.
  - `Read-LwasmSymbols([string] $Path)` → hashtable, label to address (`[int]`), case-insensitive.
  - `Measure-XRoarTrace -Trace <path> -FrameStart <int> -Stop <int> [-Idle <int[]>]` → one object per whole frame, `@{ Busy = [double] cycles; Total = [double] cycles }`. It discards the frame that begins on the first traced line.

- [ ] **Step 1: Add the XRoar tests**

In `tools/test_coco_tools.ps1`, insert this immediately above the line `# --- summary ---`:

```powershell
# --- XRoar ---
if (-not (Test-Path $XRoar)) { throw "XRoar not found at $XRoar" }
. (Join-Path $PSScriptRoot 'xroar.ps1')

$labels = Read-LwasmSymbols $sym
Check 'Read-LwasmSymbols: finds start, mainloop, waitsync and done' (
    $labels['start'] -eq 0x0E00 -and $labels.ContainsKey('mainloop') -and $labels.ContainsKey('waitsync') -and $labels.ContainsKey('done'))

# Runs the fixture until it parks at DONE and returns its RAM, or $null.
function Get-FixtureRam([string] $What, [string[]] $Load) {
    $snap = Join-Path $work "$What.sna"
    if (Test-Path $snap) { Remove-Item $snap }
    $null = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Log "$What.log" -Arguments ($Load + @(
        '-trap', ('pc=0x{0:X4}' -f $labels['done']),
        '-trap-snap', (ConvertTo-XRoarPath $snap), '-trap-timeout', '1'))
    if (-not (Test-Path $snap)) { return $null }
    Read-XRoarRam $snap
}

function Test-FixtureRam([string] $What, $Ram) {
    if ($null -eq $Ram) { Check "$What`: reaches DONE" $false "no snapshot, see $work\$What.log"; return }
    Check "$What`: reaches DONE" $true
    Check "$What`: the snapshot holds 64K of RAM" ($Ram.Length -eq 65536) "got $($Ram.Length)"
    $bad = @(0..511 | Where-Object { $Ram[0x400 + $_] -ne ($_ % 256) })
    Check "$What`: the screen holds the fixture's pattern" ($bad.Count -eq 0) "$($bad.Count) bytes wrong"
    $seg  = $fixture.Segments[0]
    $code = [byte[]]::new($seg.Bytes.Length)
    [Array]::Copy($Ram, $seg.Address, $code, 0, $code.Length)
    Check "$What`: the program sits where it was loaded" ((Hex $code) -eq (Hex $seg.Bytes))
}

Test-FixtureRam 'bin' (Get-FixtureRam 'bin' @('-run', (ConvertTo-XRoarPath $bin)))
Test-FixtureRam 'cassette' (Get-FixtureRam 'cassette' @('-load-tape', (ConvertTo-XRoarPath $cas), '-type', 'CLOADM:EXEC\r'))
if ((Test-Path (Join-Path $Roms 'disk11.rom')) -or (Test-Path (Join-Path $Roms 'disk10.rom'))) {
    Test-FixtureRam 'disk' (Get-FixtureRam 'disk' @('-machine-cart', 'rsdos', '-load-fd0', (ConvertTo-XRoarPath $dsk), '-type', 'LOADM\"FILL\":EXEC\r'))
} else {
    Write-Host "SKIP  disk: no disk11.rom or disk10.rom in $Roms"
}

$trace = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Log 'fill.trace' -Arguments @(
    '-trace-timing', '-run', (ConvertTo-XRoarPath $bin),
    '-trap', ('pc=0x{0:X4}' -f $labels['mainloop']), '-trap-range', '2', '-trap-trace',
    '-trap', ('pc=0x{0:X4}' -f $labels['done']), '-trap-timeout', '1')
$wait = $labels['waitsync']
$frames = @(Measure-XRoarTrace -Trace $trace -FrameStart $labels['mainloop'] -Stop $labels['done'] -Idle @($wait, ($wait + 3)))
Remove-Item $trace
Check 'trace: 10 whole frames between the 2nd pass and DONE' ($frames.Count -eq 10) "got $($frames.Count)"
Check 'trace: every frame does exactly 523 cycles of work' (@($frames | Where-Object { $_.Busy -ne 523 }).Count -eq 0) (($frames | ForEach-Object Busy) -join ', ')
$field = ($frames | Measure-Object Total -Average).Average
Check 'trace: a frame lasts one NTSC field, 14,934 cycles' ($field -gt 14900 -and $field -lt 14970) "average $field"

```

- [ ] **Step 2: Run the tests to see the new ones fail**

Run: `pwsh -NoProfile -File .\tools\test_coco_tools.ps1`
Expected: Task 2's checks pass, then the script stops at the dot-source of `tools\xroar.ps1`, which does not exist.

- [ ] **Step 3: Write `tools/xroar.ps1`**

```powershell
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
# element in it exactly as long as a CoCo's RAM.
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
        if ($length -in 16384, 32768, 65536) {
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
# where dt is the instruction's time in sixteenths of a CPU cycle. The
# first line traced is the exception: its dt is the time since tracing
# was armed, so the frame it begins is dropped. A frame runs from one
# line at $FrameStart to the next; Busy leaves out the $Idle addresses,
# Total does not. Reading stops at the first line at $Stop, and the
# part-frame before it is dropped too.
function Measure-XRoarTrace {
    param(
        [Parameter(Mandatory)] [string] $Trace,
        [Parameter(Mandatory)] [int]    $FrameStart,
        [Parameter(Mandatory)] [int]    $Stop,
        [int[]] $Idle = @()
    )
    $idleSet = [Collections.Generic.HashSet[int]]::new()
    foreach ($address in $Idle) { [void] $idleSet.Add($address) }

    $frames = [Collections.Generic.List[object]]::new()
    $starts = 0
    $busy   = 0L
    $total  = 0L
    $reader = [IO.StreamReader]::new($Trace)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line.Length -lt 5 -or $line[4] -ne '|') { continue }
            $pc = [Convert]::ToInt32($line.Substring(0, 4), 16)
            if ($pc -eq $Stop) { break }
            if ($pc -eq $FrameStart) {
                if ($starts -ge 2) {
                    $frames.Add([pscustomobject] @{ Busy = $busy / 16; Total = $total / 16 })
                }
                $starts++
                $busy  = 0L
                $total = 0L
            }
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
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `pwsh -NoProfile -File .\tools\test_coco_tools.ps1`
Expected: every check `PASS`, the disk load reported as `SKIP  disk: no disk11.rom or disk10.rom in ...`, then `All checks passed`. If `cassette: reaches DONE` fails, read `%TEMP%\coco_tools_test\cassette.log`; if the trace frame count is off by one, check that the first traced line is at `mainloop` (it should be, because the trap starts the trace there).

- [ ] **Step 5: Commit**

Write `C:\Users\Matth\AppData\Local\Temp\claude\msg_task3.txt`:

```
Add XRoar helpers for automated CoCo tests

tools/xroar.ps1 runs XRoar with no window, reads RAM from its
snapshots, reads lwasm's symbol dump for trap addresses, and times
frames from an instruction trace. The tests run the fixture from a
.bin and from a cassette image and check what comes back.

~
```

Run: `git add tools/xroar.ps1 tools/test_coco_tools.ps1; git commit -F "$env:TEMP\claude\msg_task3.txt"`

---

### Task 4: The 6809 program and its screen test

**Files:**
- Create: `build-coco.ps1`
- Create: `matrix_rain_coco.asm`
- Create (generated): `matrix_rain_coco.bin`, `matrix_rain_coco.cas`, `matrix_rain_coco.dsk`

**Interfaces:**
- Consumes: `matrix_rain_coco.c` (Task 1); `Read-DecbBin`, `New-CocoCas`, `New-CocoDsk` (Task 2); `ConvertTo-XRoarPath`, `Invoke-XRoar`, `Read-XRoarRam`, `Read-LwasmSymbols` (Task 3).
- Produces: global labels in `matrix_rain_coco.asm`: `start`, `mainloop`, `waitsync` (the `LDA $FF03` of the sync wait; the `BPL` follows 3 bytes later), `draw`, `codeend`, `progend`, and `testdone` in test builds. In `build-coco.ps1`: `$release` (`@{ Bin; Labels }`), `Build-Coco`, and the `-Test` block ending with the line `    Write-Host 'Other RAM:  unchanged while it ran'` followed by `    return`, which Task 5 extends.

- [ ] **Step 1: Write `build-coco.ps1`**

```powershell
<#
.SYNOPSIS
    Builds the TRS-80 Color Computer 1/2 version of Matrix Rain.

.DESCRIPTION
    Assembles matrix_rain_coco.asm with LWTOOLS into matrix_rain_coco.bin,
    then writes the cassette and disk images matrix_rain_coco.cas and
    matrix_rain_coco.dsk from it. The program is MATRIX on tape and
    MATRIX.BIN on disk.

    -Run    opens the .bin in XRoar.
    -Test   checks the program in XRoar, with no window:
              1. After 400 frames, screen RAM matches what
                 matrix_rain_coco.c leaves after 400 frames under cc65's
                 6502 simulator.
              2. Nothing outside the screen and the program's own memory
                 changes while it runs.
            These use test builds, assembled with TESTFRAMES=n so that
            the main loop parks after n frames. XRoar writes a snapshot
            some time after the trap that asks for it, so the program
            has to be holding still by then.

.EXAMPLE
    .\build-coco.ps1
    .\build-coco.ps1 -Run
    .\build-coco.ps1 -Test
#>

[CmdletBinding()]
param(
    [switch] $Run,
    [switch] $Test,
    [string] $Lwtools = 'C:\Development\_VintageDevelopment\lwtools\bin',
    [string] $XRoar   = 'C:\Program Files\6809.org.uk\XRoar 1.9\xroar.exe',
    [string] $Cc65    = 'C:\Development\_VintageDevelopment\cc65_snapshot',
    [string] $Roms    = (Join-Path $env:USERPROFILE 'Documents\XRoar\ROMS'),
    [string] $Machine = 'coco2bus'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools\xroar.ps1')
. (Join-Path $PSScriptRoot 'tools\coco_images.ps1')

$lwasm  = Join-Path $Lwtools 'lwasm.exe'
$source = Join-Path $PSScriptRoot 'matrix_rain_coco.asm'
$bin    = Join-Path $PSScriptRoot 'matrix_rain_coco.bin'
$cas    = Join-Path $PSScriptRoot 'matrix_rain_coco.cas'
$dsk    = Join-Path $PSScriptRoot 'matrix_rain_coco.dsk'
$work   = Join-Path $env:TEMP 'matrix_rain_coco'
New-Item -ItemType Directory -Force $work | Out-Null

if (-not (Test-Path $lwasm))  { throw "lwasm not found at $lwasm. Pass -Lwtools <folder holding lwasm.exe>." }
if (-not (Test-Path $source)) { throw "$source not found." }

# Assembles the program and returns the .bin path and its label
# addresses. With $Frames of 0 or more it is a test build that parks
# at testdone after that many frames.
function Build-Coco([string] $Out, [int] $Frames = -1) {
    $symbols = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($Out) + '.sym')
    $defines = if ($Frames -ge 0) { @('-D', "TESTFRAMES=$Frames") } else { @() }
    & $lwasm --decb @defines -o $Out "--symbol-dump=$symbols" $source
    if ($LASTEXITCODE -ne 0) { throw "lwasm failed on $source" }
    [pscustomobject] @{ Bin = $Out; Labels = (Read-LwasmSymbols $symbols) }
}

$release = Build-Coco $bin
New-CocoCas -Bin $bin -Name 'MATRIX' -Path $cas
New-CocoDsk -Bin $bin -Name 'MATRIX' -Path $dsk
Write-Host ('Built matrix_rain_coco.bin ({0:n0} bytes), matrix_rain_coco.cas and matrix_rain_coco.dsk' -f (Get-Item $bin).Length)

if ($Run) {
    if (-not (Test-Path $XRoar)) { throw "XRoar not found at $XRoar. Pass -XRoar <path to xroar.exe>." }
    # Start-Process, so XRoar runs in its own window until closed and
    # never reads this console.
    $proc = Start-Process $XRoar -ArgumentList '-machine', $Machine, '-run', (ConvertTo-XRoarPath $bin) -PassThru
    Write-Host ('Launched in XRoar (PID {0}). Close the window to stop it.' -f $proc.Id)
}

if ($Test) {
    if (-not (Test-Path $XRoar)) { throw "XRoar not found at $XRoar. Pass -XRoar <path to xroar.exe>." }
    $cl65   = Join-Path $Cc65 'bin\cl65.exe'
    $sim65  = Join-Path $Cc65 'bin\sim65.exe'
    $frames = 400
    $screen = 0x0400
    $size   = 512

    # Runs a test build until it parks, and returns its RAM and build.
    function Get-ParkedRam([int] $Frames) {
        $build = Build-Coco (Join-Path $work "test$Frames.bin") $Frames
        $snap  = Join-Path $work "test$Frames.sna"
        if (Test-Path $snap) { Remove-Item $snap }
        $null = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Machine $Machine -Log "test$Frames.log" -Arguments @(
            '-run', (ConvertTo-XRoarPath $build.Bin),
            '-trap', ('pc=0x{0:X4}' -f $build.Labels['testdone']),
            '-trap-snap', (ConvertTo-XRoarPath $snap), '-trap-timeout', '1')
        if (-not (Test-Path $snap)) { throw "The $Frames-frame test build never reached testdone. XRoar's log: $work\test$Frames.log" }
        [pscustomobject] @{ Ram = (Read-XRoarRam $snap); Build = $build }
    }

    # 1. Screen RAM after 400 frames matches the reference model's.
    $reference = Join-Path $work 'reference.bin'
    & $cl65 -t sim6502 -Oi -Cl -DSIM_RAW "-DSIM_FRAMES=$frames" -o $reference (Join-Path $PSScriptRoot 'matrix_rain_coco.c')
    if ($LASTEXITCODE -ne 0) { throw 'The reference model did not build.' }
    $expected = @(& $sim65 $reference | ForEach-Object { [Convert]::ToByte($_, 16) })
    if ($expected.Count -ne $size) { throw "The reference model printed $($expected.Count) bytes, not $size." }

    $after = Get-ParkedRam $frames
    $ram   = $after.Ram

    # The code and tables must be intact in memory. This also shows the
    # snapshot was read from the right place.
    $image = (Read-DecbBin $after.Build.Bin).Segments[0]
    for ($addr = $after.Build.Labels['start']; $addr -lt $image.Address + $image.Bytes.Length; $addr++) {
        if ($ram[$addr] -ne $image.Bytes[$addr - $image.Address]) {
            throw ('The program in memory differs from its .bin at ${0:X4}: the snapshot was misread, or the program wrote over itself.' -f $addr)
        }
    }

    Write-Host "`nScreen after $frames frames ('.' empty, '*' letter, '#' highlighted letter, 'o' block, '@' highlighted block):`n"
    for ($row = 0; $row -lt 16; $row++) {
        $line = foreach ($c in 0..31) {
            $v = $ram[$screen + $row * 32 + $c]
            if ($v -eq 0x80)       { '.' }
            elseif ($v -band 0x80) { if ($v -band 0x40) { '@' } else { 'o' } }
            elseif ($v -band 0x40) { '#' }
            else                   { '*' }
        }
        Write-Host (-join $line)
    }

    $diff = @(0..($size - 1) | Where-Object { $ram[$screen + $_] -ne $expected[$_] })
    if ($diff.Count) {
        $at = $diff[0]
        throw ('Screen RAM differs from the reference model''s in {0} of {1} bytes after {2} frames. The first is at ${3:X4}: the CoCo has ${4:X2}, the reference ${5:X2}.' -f `
            $diff.Count, $size, $frames, ($screen + $at), $ram[$screen + $at], $expected[$at])
    }
    Write-Host ("`nScreen RAM: all {0} bytes match the reference model after {1} frames" -f $size, $frames)

    # 2. From the moment setup finishes to 400 frames later, nothing
    #    outside the screen and the program's own memory changes.
    $before  = (Get-ParkedRam 0).Ram
    $ownEnd  = $after.Build.Labels['progend']
    $changed = @(for ($addr = 0; $addr -lt $ram.Length; $addr++) {
        if ($addr -ge $screen -and $addr -lt $screen + $size) { continue }
        if ($addr -ge 0x0E00 -and $addr -lt $ownEnd) { continue }
        if ($ram[$addr] -ne $before[$addr]) { $addr }
    })
    if ($changed.Count) {
        throw ('{0} bytes outside the screen and the program changed while it ran. The first is at ${1:X4}.' -f $changed.Count, $changed[0])
    }
    Write-Host 'Other RAM:  unchanged while it ran'
    return
}
```

- [ ] **Step 2: Run the test to see it fail**

Run: `pwsh -NoProfile -File .\build-coco.ps1 -Test`
Expected: FAIL with `...matrix_rain_coco.asm not found.`

- [ ] **Step 3: Write `matrix_rain_coco.asm`**

```
; ============================================================
; Matrix Rain Effect (TRS-80 Color Computer 1/2)
; ============================================================
; Matrix-style falling characters for the CoCo's 32x16 text screen.
; Ported from matrix_rain_8032_noclock_v8.asm (Commodore PET 8032).
; Original from Petopia demo by Milasoft.
;
; Author: Matthew Dugal (github.com/SixOThree)
; ============================================================
;
; Build:  lwasm --decb -o matrix_rain_coco.bin matrix_rain_coco.asm
;         (build-coco.ps1 does this and writes tape and disk images)
; Run:    LOADM"MATRIX":EXEC from disk, CLOADM"MATRIX":EXEC from tape
;
; Memory map:
;   $0400-$05FF  screen, 32x16
;   $0E00-$0E0F  variables, reached through the direct page register
;   $0E10-       code and tables, then drop records and stack
;   $FF02/$FF03  PIA 0 side B: field sync sets bit 7 of $FF03
;   $FF22        PIA 1 side B: bits 3-7 are the video chip's mode
;   $FFC0-$FFD3  SAM: video mode and display offset
;
; Screen codes (MC6847 video chip):
;   $00-$3F  letters, digits, symbols: bright green on dark green
;   $40-$7F  the same, dark on bright green: a highlighted letter
;   $80-$8F  green graphics blocks on black; $80 has no pixels lit
;   $C0-$CF  buff graphics blocks: a highlighted green block
;
; matrix_rain_coco.c is the reference model. build-coco.ps1 -Test
; requires this program to leave screen RAM exactly as it does, so a
; change to any setting below goes into both files.
; ============================================================

; ------------------------------------------------------------
; Configuration
; ------------------------------------------------------------

GLITCH   equ  64             ; trail glitch frequency (0=off, 255=constant)
TRAILMIN equ  6              ; minimum trail length (rows)
TRAILMAX equ  14             ; maximum trail length (rows)
REVERSE  equ  64             ; highlight chance (0=never, 255=always)
NEWCHAR  equ  51             ; new char chance (lower=more flicker)
NUMDRIPS equ  28             ; active drops (max 32)
SPDSTART equ  9              ; initial speed range (0 to N-1, lower=faster)
SPDRESET equ  5              ; reset speed range (0 to N-1, lower=faster)
GRAPHIC  equ  16             ; graphics block chance (0=never, 255=always)

; ------------------------------------------------------------
; Constants
; ------------------------------------------------------------

SCREEN   equ  $0400          ; screen RAM
SCREENEND equ $0600          ; first byte past it
COLS     equ  32
NOREVERSE equ $05E0          ; the bottom row: never highlighted

EMPTY    equ  $80            ; graphics block, no pixels lit: black
SPACE    equ  $20            ; a letter-set space: an empty dark green cell
BANG     equ  $21            ; stands in for a space so heads stay visible
CHARMASK equ  $3F            ; the 64 letters, digits and symbols
RVS      equ  $40            ; bit 6: highlight
NORVS    equ  $BF            ; clears bit 6 and nothing else
BLOCK    equ  $80            ; green graphics block, pixels in bits 0-3
PIXELS   equ  $0F            ; the pixel bits of a block
FULL     equ  $0F            ; all four pixels lit

PIA0PB   equ  $FF02          ; reading it clears the field sync flag
PIA0CRB  equ  $FF03          ; bit 7 is set by field sync
PIA1PB   equ  $FF22          ; bits 3-7: video chip mode
SAM      equ  $FFC0          ; SAM control bits, a clear/set address pair each

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
; FCB and ZMB rather than RMB, so the whole program loads as one block.

seedlo   fcb  0              ; random generator state
seedhi   fcb  0
headch   fcb  0              ; scratch for RNDHEAD
frames   fdb  0              ; frames drawn; only test builds use it
         zmb  11             ; the rest of the 16-byte area

; ============================================================
; Initialization
; ============================================================

start    orcc #$50           ; mask IRQ and FIRQ: BASIC's 60 Hz handler
                             ; would otherwise clear the sync flag first
         lds  #stacktop      ; keep every write inside our own memory
         lda  #$0E
         tfr  a,dp           ; direct page = the variables above

; Text mode with the screen at $0400, in case a graphics program ran first.
         lda  PIA1PB
         anda #$07           ; video chip: alphanumeric, green set (CSS=0)
         sta  PIA1PB
         sta  SAM            ; V0 = 0 \
         sta  SAM+2          ; V1 = 0  > SAM text mode
         sta  SAM+4          ; V2 = 0 /
         sta  SAM+6          ; F0 = 0 \
         sta  SAM+9          ; F1 = 1  |
         sta  SAM+10         ; F2 = 0  |
         sta  SAM+12         ; F3 = 0  > display offset 2 x 512 = $0400
         sta  SAM+14         ; F4 = 0  |
         sta  SAM+16         ; F5 = 0  |
         sta  SAM+18         ; F6 = 0 /

         ldx  #SCREEN        ; clear the screen to black
         ldd  #EMPTY*256+EMPTY
clrloop  std  ,x++
         cmpx #SCREENEND
         bne  clrloop

         lda  #21            ; seed the random generator, as the PET does
         sta  <seedlo
         lda  #$1C
         sta  <seedhi

         ldu  #drops
         ldy  #rainhis
         clrb                ; B = drop number = its starting column
initdrop jsr  random         ; speed: 0 to SPDSTART-1
         cmpa #SPDSTART
         bhs  initdrop
         sta  SPD,u
         jsr  rndtrail
         sta  TRL,u
         clr  DEL,u
         lda  ,y+            ; $03 = above the screen, $04 = top row
         std  POS,u          ; so the address is $03xx or $04xx, xx = column
         leau RECSIZE,u
         incb
         cmpb #NUMDRIPS
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
         jsr  draw
         bra  mainloop

         IFDEF TESTFRAMES
testdone bra  testdone
         ENDC

; ============================================================
; DRAW - one frame
; ============================================================
; For each drop: refresh the head, dim the head it left behind, maybe
; glitch one character in the trail, then move or wait. U walks the
; drop records, and X holds the head address throughout.
; ============================================================

draw     ldu  #drops
nextdrop ldx  POS,u
         cmpx #SCREEN
         blo  timing         ; not on the screen yet
         cmpx #SCREENEND
         bhs  timing         ; already below it

; Head: usually keep what is there, sometimes pick anew. An empty cell
; always gets a fresh character.
         jsr  random
         cmpa #NEWCHAR
         bhs  keephead
         jsr  rndhead
         bra  placehead
keephead lda  ,x
         cmpa #EMPTY
         bne  placehead
         jsr  rndhead
placehead
         cmpx #NOREVERSE
         blo  writehead
         anda #NORVS         ; no highlight on the bottom row
writehead
         sta  ,x

; Take the highlight off the head one row up.
         leay -COLS,x
         cmpy #SCREEN
         blo  timing         ; that row is above the screen
         lda  ,y
         anda #NORVS
         sta  ,y

; Now and then swap one character somewhere in the trail.
         jsr  random
         cmpa #GLITCH
         bhs  timing
         jsr  random
         anda #$0F           ; rows 1-15 up from the head
         beq  timing         ; row 0 is the head itself
         cmpa TRL,u
         bhs  timing         ; past the end of the trail
         ldb  #COLS
         mul                 ; D = row * 32
         coma                ; D = -D
         comb
         addd #1
         leay d,x            ; Y = head - row * 32
         cmpy #SCREEN
         blo  timing         ; above the screen (it cannot be below)
         jsr  rndchar
         sta  ,y

; Time to move?
timing   lda  DEL,u
         cmpa SPD,u
         beq  move
         inc  DEL,u
         bra  advance
move     clr  DEL,u

; Erase the last character of the trail, or recycle the drop once its
; whole trail has left the bottom of the screen.
         lda  TRL,u
         ldb  #COLS
         mul                 ; D = trail * 32
         coma                ; D = -D
         comb
         addd #1
         leay d,x            ; Y = tail = head - trail * 32
         cmpy #SCREENEND
         bhs  recycle
         cmpy #SCREEN
         blo  movedown       ; the tail is still above the screen
         lda  #EMPTY
         sta  ,y
movedown leax COLS,x
         stx  POS,u
         bra  advance

; New column on the top row, new speed, new trail. Reset drops are
; faster than the first ones, which makes the rain accelerate.
recycle  jsr  random
         cmpa #COLS
         bhs  recycle
         ldx  #SCREEN
         leax a,x            ; A is 0-31, so reading it as signed is fine
         stx  POS,u
newspeed jsr  random
         cmpa #SPDRESET
         bhs  newspeed
         sta  SPD,u
         jsr  rndtrail
         sta  TRL,u

advance  leau RECSIZE,u
         cmpu #drops+NUMDRIPS*RECSIZE
         bne  nextdrop
         rts

; ============================================================
; RNDHEAD - a head character, sometimes highlighted. Out: A.
; ============================================================

rndhead  jsr  rndchar
         sta  <headch
         jsr  random
         cmpa #REVERSE       ; carry set when A < REVERSE
         lda  <headch        ; LDA leaves the carry alone
         bhs  rndheadx
         ora  #RVS
rndheadx rts

; ============================================================
; RNDCHAR - a new rain character. Out: A.
; ============================================================
; Now and then a green graphics block, otherwise a letter, digit or
; symbol. Never a cell that looks empty.

rndchar  jsr  random
         cmpa #GRAPHIC
         bhs  letter
         jsr  random
         anda #PIXELS
         bne  block
         lda  #FULL          ; no pixels lit would look empty
block    ora  #BLOCK
         rts
letter   jsr  random
         anda #CHARMASK
         cmpa #SPACE
         bne  letterx
         lda  #BANG          ; a space would look empty
letterx  rts

; ============================================================
; RNDTRAIL - trail length, TRAILMIN to TRAILMAX. Out: A.
; ============================================================
; Masked to 0-31, the minimum added, rerolled while over the maximum,
; as on the PET.

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

; Starting high byte for each drop: $03 is above the screen (256 cells,
; 8 rows up), $04 is the top row. The first 32 entries of the PET's table.
rainhis  fcb  $03,$04,$03,$04,$03,$04,$03,$04,$03,$04
         fcb  $03,$04,$03,$04,$03,$04,$03,$04,$03,$04
         fcb  $04,$04,$04,$04,$03,$04,$04,$04,$04,$04
         fcb  $03,$04

codeend  equ  *              ; the .bin loads $0E00 up to here

; Reserved, not stored in the .bin.
drops    rmb  NUMDRIPS*RECSIZE
stack    rmb  64
stacktop equ  *
progend  equ  *

         end  start
```

- [ ] **Step 4: Run the test to see it pass**

Run: `pwsh -NoProfile -File .\build-coco.ps1 -Test`
Expected: `Built matrix_rain_coco.bin (...)`, a 16-line text screen, `Screen RAM: all 512 bytes match the reference model after 400 frames`, `Other RAM:  unchanged while it ran`, exit code 0.

If the screen check fails, the first differing address points at a drop column (`address & 31`). Compare that drop's handling between the `.asm` and `draw()` in the `.c`, especially the order of `random` calls. If the unchanged-RAM check fails, print the first few changed addresses and their values from both snapshots: a change in BASIC's area that appears even for identical builds would mean XRoar runs are not repeatable, and the check needs both snapshots from one run instead.

- [ ] **Step 5: Check that the test catches a real difference**

Edit `matrix_rain_coco.asm`: `GLITCH   equ  64` to `GLITCH   equ  65`.
Run: `pwsh -NoProfile -File .\build-coco.ps1 -Test`
Expected: FAIL with `Screen RAM differs from the reference model's in N of 512 bytes after 400 frames`, exit code 1.
Edit it back to `64` and run the test again. Expected: PASS.

- [ ] **Step 6: Commit**

Write `C:\Users\Matth\AppData\Local\Temp\claude\msg_task4.txt`:

```
Add the TRS-80 Color Computer 1/2 version

matrix_rain_coco.asm ports the PET assembly to the CoCo's 32x16 screen
in 6809: green letters on black, the odd green graphics block, and
highlighted leads. build-coco.ps1 assembles it with LWTOOLS, writes
tape and disk images, and with -Test runs it in XRoar and requires
screen RAM after 400 frames to match matrix_rain_coco.c, with nothing
else in memory disturbed.

~
```

Run: `git add build-coco.ps1 matrix_rain_coco.asm matrix_rain_coco.bin matrix_rain_coco.cas matrix_rain_coco.dsk; git commit -F "$env:TEMP\claude\msg_task4.txt"`

---

### Task 5: Image and speed checks

**Files:**
- Modify: `build-coco.ps1` (help text; the end of the `-Test` block)

**Interfaces:**
- Consumes: `$release`, `Build-Coco`, `$work`, `$Machine`, `$Roms`, `$cas`, `$dsk` from `build-coco.ps1`; `Measure-XRoarTrace` from `tools/xroar.ps1`; labels `mainloop`, `waitsync`, `testdone`, `start`.
- Produces: `-Test` output lines `cassette: loads and runs`, `disk: loads and runs` or `disk: SKIPPED, ...`, and `Frame cost: ...`.

- [ ] **Step 1: Extend the help text**

In `build-coco.ps1`, replace:

```
              2. Nothing outside the screen and the program's own memory
                 changes while it runs.
            These use test builds, assembled with TESTFRAMES=n so that
```

with:

```
              2. Nothing outside the screen and the program's own memory
                 changes while it runs.
              3. The cassette image loads with CLOADM and runs, and the
                 disk image with LOADM when Disk BASIC's ROM is in the
                 ROM folder; otherwise the disk check is skipped.
              4. It reports the cycles a frame takes, from a trace.
            Checks 1, 2 and 4 use test builds, assembled with TESTFRAMES=n so that
```

- [ ] **Step 2: Add the image and speed checks**

In `build-coco.ps1`, replace:

```powershell
    Write-Host 'Other RAM:  unchanged while it ran'
    return
}
```

with:

```powershell
    Write-Host 'Other RAM:  unchanged while it ran'

    # 3. The images load the shipped program and run it. Each run traps
    #    on the main loop; the snapshot lands later, but the code and
    #    tables it checks never change.
    function Test-Image([string] $What, [string[]] $Load) {
        $snap = Join-Path $work "$What.sna"
        if (Test-Path $snap) { Remove-Item $snap }
        $null = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Machine $Machine -Log "$What.log" -Arguments ($Load + @(
            '-trap', ('pc=0x{0:X4}' -f $release.Labels['mainloop']),
            '-trap-snap', (ConvertTo-XRoarPath $snap), '-trap-timeout', '1'))
        if (-not (Test-Path $snap)) { throw "The $What image never reached the main loop. XRoar's log: $work\$What.log" }
        $loaded = Read-XRoarRam $snap
        $image  = (Read-DecbBin $release.Bin).Segments[0]
        for ($addr = $release.Labels['start']; $addr -lt $image.Address + $image.Bytes.Length; $addr++) {
            if ($loaded[$addr] -ne $image.Bytes[$addr - $image.Address]) {
                throw ('The {0} image loaded different bytes from the .bin, first at ${1:X4}.' -f $What, $addr)
            }
        }
        Write-Host ('{0,-11} loads and runs' -f "$What`:")
    }
    Test-Image 'cassette' @('-load-tape', (ConvertTo-XRoarPath $cas), '-type', 'CLOADM:EXEC\r')
    if ((Test-Path (Join-Path $Roms 'disk11.rom')) -or (Test-Path (Join-Path $Roms 'disk10.rom'))) {
        Test-Image 'disk' @('-machine-cart', 'rsdos', '-load-fd0', (ConvertTo-XRoarPath $dsk), '-type', 'LOADM\"MATRIX\":EXEC\r')
    } else {
        Write-Host "disk:       SKIPPED, no disk11.rom or disk10.rom in $Roms"
    }

    # 4. Cycles per frame, from an instruction trace of frames 101 to 110.
    #    Busy leaves out the sync wait. It includes 22 cycles a frame of
    #    the test build's frame counting.
    $timed = Build-Coco (Join-Path $work 'test110.bin') 110
    $trace = Invoke-XRoar -XRoar $XRoar -WorkDir $work -Machine $Machine -Log 'test110.trace' -EmulatedSeconds 20 -Arguments @(
        '-trace-timing', '-run', (ConvertTo-XRoarPath $timed.Bin),
        '-trap', ('pc=0x{0:X4}' -f $timed.Labels['mainloop']), '-trap-range', '100', '-trap-trace',
        '-trap', ('pc=0x{0:X4}' -f $timed.Labels['testdone']), '-trap-timeout', '1')
    $wait = $timed.Labels['waitsync']
    $perFrame = @(Measure-XRoarTrace -Trace $trace -FrameStart $timed.Labels['mainloop'] -Stop $timed.Labels['testdone'] -Idle @($wait, ($wait + 3)))
    Remove-Item $trace
    if ($perFrame.Count -ne 10) { throw "Expected 10 traced frames, got $($perFrame.Count)." }
    $busy  = $perFrame | Measure-Object Busy -Average -Maximum
    $field = ($perFrame | Measure-Object Total -Average).Average
    Write-Host ('Frame cost: {0:n0} cycles on average, {1:n0} at most, of a {2:n0}-cycle frame ({3:p0} at most)' -f `
        $busy.Average, $busy.Maximum, $field, ($busy.Maximum / $field))
    if ($busy.Maximum -gt $field) { Write-Warning 'A frame took longer than a field, so the rain runs below 60 fps.' }
    return
}
```

- [ ] **Step 3: Run the test**

Run: `pwsh -NoProfile -File .\build-coco.ps1 -Test`
Expected: the Task 4 output, then `cassette:  loads and runs`, `disk:       SKIPPED, no disk11.rom or disk10.rom in ...`, and a `Frame cost:` line with an average below 14,934 (the spec expects about half). Exit code 0.

- [ ] **Step 4: Commit**

Write `C:\Users\Matth\AppData\Local\Temp\claude\msg_task5.txt`:

```
Test the CoCo tape and disk images and time a frame

build-coco.ps1 -Test now loads the shipped program from its cassette
image with CLOADM, and from its disk image with LOADM when Disk BASIC's
ROM is present, and checks the bytes that arrive. It also times frames
101 to 110 from an XRoar instruction trace.

~
```

Run: `git add build-coco.ps1; git commit -F "$env:TEMP\claude\msg_task5.txt"`

---

### Task 6: Look check and documentation

**Files:**
- Modify: `README.md` (new section after "## The C version")
- Modify: `CLAUDE.md` (new section after "### C version")
- Modify: `C:\Users\Matth\.claude\projects\C--OneDrive-Vintage-Computing-Development-CommodorePetMatrixRain\memory\coco-toolchain.md`

**Interfaces:**
- Consumes: everything above.
- Produces: documentation only.

- [ ] **Step 1: Show it to the user**

Run: `pwsh -NoProfile -File .\build-coco.ps1 -Run`, then `pwsh -NoProfile -File .\build-coco.ps1 -Run -Machine cocous`.
Ask the user to confirm on both machines: a black screen; bright green letters on dark green cells; now and then a green block; highlighted leads showing as dark letters on bright green cells or as buff blocks; no highlight on the bottom row. Record their answer. Any tuning they ask for changes the setting in both `matrix_rain_coco.asm` and `matrix_rain_coco.c`, then `-Test` must pass again and the regenerated `.bin`, `.cas` and `.dsk` are committed with the change.

- [ ] **Step 2: Add the README section**

In `README.md`, insert immediately above the line `## Running`:

````markdown
## The Color Computer version

`matrix_rain_coco.asm` is the effect on the TRS-80 Color Computer 1 and 2,
in 6809 assembly. It uses the CoCo's 32×16 text screen: bright green letters
on a black screen, with the odd green graphics block. A highlighted lead
shows as a dark letter on a bright green cell, and a highlighted block turns
buff.

Load it from disk with `LOADM"MATRIX":EXEC`, or from tape with
`CLOADM"MATRIX":EXEC`. It needs 16K and runs until you press reset.

```powershell
.\build-coco.ps1         # writes matrix_rain_coco.bin, .cas and .dsk
.\build-coco.ps1 -Run    # and opens the .bin in XRoar
.\build-coco.ps1 -Test   # checks it in XRoar against matrix_rain_coco.c
```

Building needs [LWTOOLS](http://www.lwtools.ca/). Running and testing need
[XRoar](https://www.6809.org.uk/xroar/) with CoCo ROMs, and cc65 for the
reference model the test compares against.

The algorithm is the PET's, with the same random number generator, seed and
steps for each drop. The settings are tuned for the smaller screen and sit
at the top of both `matrix_rain_coco.asm` and `matrix_rain_coco.c`, which
have to agree:

| Variable | CoCo default |
|----------|--------------|
| GLITCH   | 64 |
| TRAILMIN | 6 |
| TRAILMAX | 14 |
| REVERSE  | 64 |
| NEWCHAR  | 51 |
| NUMDRIPS | 28 (max 32) |
| SPDSTART | 9 |
| SPDRESET | 5 |
| GRAPHIC  | 16: the chance, out of 256, that a new character is a graphics block |

````

- [ ] **Step 3: Add the CLAUDE.md section**

In `CLAUDE.md`, insert immediately above the line `## Architecture`:

````markdown
### CoCo 1/2 version

`matrix_rain_coco.asm` is a 6809 port for the TRS-80 Color Computer 1/2,
assembled with LWTOOLS and tested in XRoar:

```powershell
.\build-coco.ps1              # lwasm --decb, then the .cas and .dsk images
.\build-coco.ps1 -Run         # open the .bin in XRoar
.\build-coco.ps1 -Test        # screen vs matrix_rain_coco.c, RAM, images, speed
.\tools\test_coco_tools.ps1   # tests for the image writers and XRoar helpers
```

Tools on this machine: LWTOOLS 4.25 in
`C:\Development\_VintageDevelopment\lwtools\bin`, built from source with
Visual Studio; XRoar 1.9 in `C:\Program Files\6809.org.uk\XRoar 1.9`; ROMs
in `%USERPROFILE%\Documents\XRoar\ROMS`, which has no Disk BASIC ROM, so
`-Test` skips the disk image.

`matrix_rain_coco.c` is the test reference: a copy of the PET C port with
only the geometry, settings, character codes and graphics blocks changed.
It builds only for sim65. A settings change goes into both it and the
`.asm`, and `-Test` fails until they agree. Screen codes: `$80` is an empty
(black) cell, letters are `$00`-`$3F`, bit 6 highlights, green blocks are
`$81`-`$8F`.

XRoar 1.9 behaviours the tests depend on:
- A `\` in an option value is an escape. Pass forward-slash paths
  (`ConvertTo-XRoarPath` in `tools/xroar.ps1`).
- A trap snapshot is written about 20 frames after its trap fires. The tests
  snapshot test builds (`lwasm -D TESTFRAMES=n`) that park at `testdone`.
- `-trap-trace` starts on the exact instruction; `-trap-no-trace` does
  nothing. A `pc=` trap on the entry address does not fire under `-run`.
- `-type` needs `\r` for Enter. A `.bin` given to `-load` is wiped when BASIC
  starts; use `-run`. `-ui null` runs with no window.
- Trace `dt=` is sixteenths of a CPU cycle. An NTSC frame is 14,934 cycles.
````

- [ ] **Step 4: Update the memory note**

Overwrite `C:\Users\Matth\.claude\projects\C--OneDrive-Vintage-Computing-Development-CommodorePetMatrixRain\memory\coco-toolchain.md` with (Read it first; the Write tool requires that):

```markdown
---
name: coco-toolchain
description: Where the TRS-80 CoCo tools live on this machine (LWTOOLS built from source, XRoar 1.9, ROMs) and the XRoar quirks the automated tests work around
metadata:
  type: project
---

Set up 2026-09-17 for the CoCo 1/2 port of the matrix rain.

- **LWTOOLS 4.25**: built from source with VS Community 2026 (MSBuild,
  `win\lwtools.sln`, `/p:Platform=Win32 /p:PlatformToolset=v145`).
  `lwlink\output.c` calls `strcasecmp` without including `lw_win.h`, so it
  needs `$env:CL='/Dstrcasecmp=_stricmp'` and `/t:lwlink:Rebuild`.
  Binaries in `C:\Development\_VintageDevelopment\lwtools\bin`.
- **XRoar 1.9**: `C:\Program Files\6809.org.uk\XRoar 1.9\xroar.exe`. ROMs in
  `C:\Users\Matth\Documents\XRoar\ROMS` (bas10-14, extbas10/11, coco3.rom;
  no Disk BASIC ROM as of 2026-09-17).
- **Automated tests**: `tools/xroar.ps1` and `build-coco.ps1 -Test` in the
  repo hold the working recipe.

**Why:** XRoar 1.9 quirks, all measured: a `\` in an option value is an
escape (`C:\a\b.sna` became `C:ab.sna` and landed in the repo); trap
snapshots are written about 20 frames after the trap; `-trap-no-trace`
does nothing; a `pc=` trap on the entry address does not fire under
`-run`; `-type` needs `\r`; a `.bin` given to `-load` is wiped by BASIC's
startup; `-ui null` runs with no window.

**How to apply:** use the helpers in `tools/xroar.ps1` rather than calling
XRoar by hand; snapshot only programs parked in a loop that writes nothing
(test builds with `-D TESTFRAMES=n`); pass forward-slash paths; run XRoar
from a scratch folder. See also [[bash-tool-8191-truncation]].
```

- [ ] **Step 5: Run everything once more**

Run: `pwsh -NoProfile -File .\tools\test_coco_tools.ps1; pwsh -NoProfile -File .\build-coco.ps1 -Test; pwsh -NoProfile -File .\build.ps1 -Test; git status --short`
Expected: all three pass. `git status` shows only `README.md` and `CLAUDE.md` modified; the regenerated `.bin`, `.cas` and `.dsk` are unchanged, and `matrix_rain_8032_c.prg` is unchanged.

- [ ] **Step 6: Commit**

Write `C:\Users\Matth\AppData\Local\Temp\claude\msg_task6.txt`:

```
Document the Color Computer version

README gains a section on loading, building and tuning it, and
CLAUDE.md records the toolchain and the XRoar behaviours its tests
depend on.

~
```

Run: `git add README.md CLAUDE.md; git commit -F "$env:TEMP\claude\msg_task6.txt"`
