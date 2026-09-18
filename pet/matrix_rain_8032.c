/* ============================================================
 * Matrix Rain Effect (Commodore 8032) - C port
 * ============================================================
 * Matrix-style falling characters for the 80-column PET.
 * Ported from matrix_rain_8032_noclock_v8.asm.
 * Original from Petopia demo by Milasoft.
 *
 * Author: Matthew Dugal (github.com/SixOThree)
 * ============================================================
 *
 * Build:  cl65 -t pet -Oi -Cl -o matrix_rain_8032_c.prg matrix_rain_8032.c
 *
 * Memory Map:
 *   Screen RAM: $8000-$87FF (80x25 = 2000 visible bytes, 2048 addressable)
 *   VIA Port B: $E840 (bit 5 = vertical retrace)
 *   Zero page:  $f7-$fe, the same eight bytes the assembly used
 *
 * A drop's position is a signed offset from the start of screen RAM.
 * Negative means the drop has not reached the top of the screen yet.
 * The assembly version encoded the same idea in the high byte of a
 * screen address: $80 for "at the top", $7f for "above the screen".
 *
 * This runs a frame in about 31,400 cycles against the assembly's
 * 18,450, both measured under cc65's 6502 simulator. It produces the
 * identical screen: all 2048 bytes match the assembly's after 400
 * frames. Several things here are shaped for cc65's code generator
 * rather than for looks, and each one is commented with what it buys.
 * ============================================================ */

#ifdef __SIM6502__
#include <stdio.h>
#endif

/* ------------------------------------------------------------
 * Configuration
 * ------------------------------------------------------------
 * Adjust these to change the effect's appearance. */

#define GLITCH      64    /* trail glitch frequency (0=off, 255=constant) */
#define TRAILMIN    10      /* minimum trail length (rows)                  */
#define TRAILMAX    24      /* maximum trail length (rows)                  */
#define REVERSE     64      /* reverse video chance (0=never, 255=always)   */
#define NEWCHAR     51      /* new char chance (lower=more flicker)         */
#define NUMDRIPS    70      /* active columns (max 80, try 70 for gaps)     */
#define SPDSTART     9      /* initial speed range (0 to N-1, lower=faster) */
#define SPDRESET     5      /* reset speed range (0 to N-1, lower=faster)   */

/* ------------------------------------------------------------
 * Screen geometry
 * ------------------------------------------------------------ */

#define COLS        80
#define ROWS        25
#define CHR_SPACE   32
#define CHR_BANG    33      /* stands in for a space so heads stay visible */
#define RVS         0x80    /* high bit of a screen code = reverse video   */

/* The assembly bounds-checked the whole 2K of screen RAM, not just the
 * 2000 visible cells. Drops live briefly in the 48 cells past the last
 * visible row before their tail clears and they recycle, so the wider
 * range is load-bearing. Keep it. */
#define SCREEN_SIZE 2048

/* True when a screen offset lands inside screen RAM. A negative offset
 * wraps to a very large unsigned value, so one comparison does the work
 * of checking both ends. Only safe where the offset cannot legitimately
 * exceed the screen by more than it could fall below zero, which is
 * every use below except the tail. */
#define ON_SCREEN(off) ((unsigned int)(off) < SCREEN_SIZE)

/* Reverse video is suppressed near the bottom of the screen to stop the
 * lead character flickering against the edge.
 *
 * Note: row 24 starts at offset 1920 ($8780), but the assembly used
 * $87B0. Only the last 32 cells of the bottom row are actually covered.
 * The 40-column source has the equivalent constant right ($83C0 is
 * exactly 24*40), so this looks like a mis-scaled constant in the
 * 80-column port. Kept as-is so the animation matches. Change 1968 to
 * 1920 to cover the whole bottom row. */
#define NOREVERSE   1968

#define VIA_PB      (*(volatile unsigned char *)0xE840)

/* A macro rather than a const pointer variable. cc65 folds a constant
 * address into the instruction, but reloads a pointer variable from
 * memory on every single access. */
#ifdef __SIM6502__
static unsigned char sim_screen[SCREEN_SIZE];
#define screen sim_screen
#else
#define screen ((unsigned char *)0x8000)
#endif

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
 * the top" gives the wave effect at startup.
 *
 * ABOVE is 256 cells up, not one row, which is what the assembly's $7f
 * high byte meant. 256 is not a multiple of 80, so a drop starting
 * ABOVE also enters the screen 64 columns to the right of its index.
 * That sideways scatter is part of the look. */

#define ABOVE   (-256)
#define TOP     0

static const int rainhis[COLS] = {
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
 * A direct port of the assembly routine, seed and all, so the C
 * build produces the same sequence of characters as the original:
 *
 *   lda seedhi / lsr / rol seedlo / bcc + / eor #$b4 / + sta seedhi
 *   eor seedlo
 * ============================================================ */

/* The seeds live at fixed zero page addresses. ca65 assembles a constant
 * address below 256 as zero page, so every read and write here costs 3
 * cycles instead of the 4 an ordinary global would. rnd() runs about 130
 * times a frame, so the byte adds up.
 *
 * $fb and $fc are free on a PET. cc65 keeps its own zero page variables
 * at $55 to $6e, and the assembly version used $f7 to $fe as scratch. */
#define seedlo (*(unsigned char *)0x00FB)
#define seedhi (*(unsigned char *)0x00FC)

/* Two screen pointers, also in zero page. cc65 turns these into
 * lda ($fd),y and sta ($fd),y directly, which is the addressing the
 * assembly used. A pointer held in ordinary memory gets copied into
 * cc65's own scratch pointer before every access, costing four
 * instructions each time. */
#define cell  (*(unsigned char **)0x00FD)
#define cell2 (*(unsigned char **)0x00F7)

/* The last two free bytes hold draw()'s loop index and the character it
 * is placing. Both are read several times per column, and cc65 would
 * otherwise keep them in ordinary memory at four cycles an access. That
 * uses up $f7 to $fe, the same eight bytes the assembly claimed. */
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

/* A printable screen code, never a space. */
static unsigned char rnd_char(void)
{
    unsigned char ch = rnd() & 0x7f;

    if (ch == CHR_SPACE) {
        ch = CHR_BANG;
    }
    return ch;
}

/* A head character, sometimes in reverse video. */
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
        screen[off] = CHR_SPACE;
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
                if (headch == CHR_SPACE) {
                    headch = rnd_head();
                }
            }

            if (p >= NOREVERSE) {
                headch &= 0x7f;
            }
            *cell = headch;

            /* Drop the reverse video off the head one row up. */
            other = p - COLS;
            if (ON_SCREEN(other)) {
                cell2 = screen + other;
                *cell2 = (unsigned char)(*cell2 & 0x7f);

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
            screen[other] = CHR_SPACE;
        }

        POS_SET(col, p + COLS);
    }
}

/* ============================================================
 * Entry point
 * ============================================================ */

#ifdef __SIM6502__

#ifndef SIM_FRAMES
#define SIM_FRAMES 400
#endif

/* Print the screen as text so the shape of the rain can be checked
 * without a display: '.' empty, '*' normal video, '#' reverse video.
 *
 * Built with SIM_RAW, print every byte of screen RAM in hex instead,
 * one per line. tools/asm_harness.c prints the assembly's screen the
 * same way, and build.ps1 -Test requires the two to match. */
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
            putchar(v == CHR_SPACE ? '.' : (v & RVS) ? '#' : '*');
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

#else

int main(void)
{
    init();

    for (;;) {
        while (VIA_PB & 32) {
            /* wait for vertical retrace */
        }
        draw();
    }
}

#endif
