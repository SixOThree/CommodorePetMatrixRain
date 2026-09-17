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
 * Build:  cl65 -t pet -O -Cl -o matrix_rain_8032_c.prg matrix_rain_8032.c
 *
 * Memory Map:
 *   Screen RAM: $8000-$87FF (80x25 = 2000 visible bytes, 2048 addressable)
 *   VIA Port B: $E840 (bit 5 = vertical retrace)
 *
 * A drop's position is a signed offset from the start of screen RAM.
 * Negative means the drop has not reached the top of the screen yet.
 * The assembly version encoded the same idea in the high byte of a
 * screen address: $80 for "at the top", $7f for "above the screen".
 * ============================================================ */

#ifdef __SIM6502__
#include <stdio.h>
#endif

/* ------------------------------------------------------------
 * Configuration
 * ------------------------------------------------------------
 * Adjust these to change the effect's appearance. */

#define GLITCH      64      /* trail glitch frequency (0=off, 255=constant) */
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

#ifdef __SIM6502__
static unsigned char sim_screen[SCREEN_SIZE];
static unsigned char *const screen = sim_screen;
#else
static unsigned char *const screen = (unsigned char *)0x8000;
#endif

/* ------------------------------------------------------------
 * Per-column state
 * ------------------------------------------------------------ */

static int           pos[COLS];     /* head offset into screen RAM      */
static unsigned char speed[COLS];   /* frames between moves (0=fastest) */
static unsigned char del[COLS];     /* frames waited so far             */
static unsigned char trail[COLS];   /* trail length in rows             */

static int rowoff[TRAILMAX + 1];    /* rowoff[n] == n * COLS            */

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

static unsigned char seedlo = 21;
static unsigned char seedhi = 0x1c;

static unsigned char rnd(void)
{
    unsigned char lo = seedlo;
    unsigned char a  = seedhi;

    seedlo = (unsigned char)((lo << 1) | (a & 1));  /* rol seedlo */
    a >>= 1;                                        /* lsr        */
    if (lo & 0x80) {                                /* bcc +      */
        a ^= 0xB4;                                  /* tap polynomial */
    }
    seedhi = a;
    return (unsigned char)(a ^ seedlo);
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

    for (off = 0; off < SCREEN_SIZE; ++off) {
        screen[off] = CHR_SPACE;
    }

    for (n = 0; n <= TRAILMAX; ++n) {
        rowoff[n] = (int)n * COLS;
    }

    for (i = 0; i < NUMDRIPS; ++i) {
        do {
            n = rnd();
        } while (n >= SPDSTART);
        speed[i] = n;

        trail[i] = rnd_trail();
        del[i]   = 0;
        pos[i]   = rainhis[i] + i;
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
    unsigned char i;
    unsigned char ch;
    unsigned char row;
    int           p;
    int           other;

    for (i = 0; i < NUMDRIPS; ++i) {
        p = pos[i];

        if (p >= 0 && p < SCREEN_SIZE) {

            /* Head: usually keep what is there, sometimes reroll.
             * An empty cell always gets a fresh character. */
            if (rnd() < NEWCHAR) {
                ch = rnd_head();
            } else {
                ch = screen[p];
                if (ch == CHR_SPACE) {
                    ch = rnd_head();
                }
            }

            if (p >= NOREVERSE) {
                ch &= 0x7f;
            }
            screen[p] = ch;

            /* Drop the reverse video off the head one row up. */
            other = p - COLS;
            if (other >= 0) {
                screen[other] &= 0x7f;

                /* Swap one character somewhere in the trail. */
                if (rnd() < GLITCH) {
                    row = rnd() & 0x0f;
                    if (row != 0 && row < trail[i]) {
                        other = p - rowoff[row];
                        if (other >= 0 && other < SCREEN_SIZE) {
                            screen[other] = rnd_char();
                        }
                    }
                }
            }
        }

        /* Time to move? */
        if (del[i] != speed[i]) {
            ++del[i];
            continue;
        }
        del[i] = 0;

        /* Erase the last character of the trail. */
        other = p - rowoff[trail[i]];

        if (other >= SCREEN_SIZE) {
            /* The whole drop has left the screen. Recycle it: new
             * column, new speed, new trail. Reset drops are faster
             * than the initial ones, which makes the rain accelerate. */
            do {
                ch = rnd();
            } while (ch >= COLS);
            pos[i] = ch;

            do {
                ch = rnd();
            } while (ch >= SPDRESET);
            speed[i] = ch;

            trail[i] = rnd_trail();
            continue;
        }

        if (other >= 0) {
            screen[other] = CHR_SPACE;
        }

        pos[i] = p + COLS;
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
 * without a display: '.' empty, '*' normal video, '#' reverse video. */
static void dump(void)
{
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
