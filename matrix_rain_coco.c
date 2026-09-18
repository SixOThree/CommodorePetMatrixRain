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
 *   - speeds and columns are masked to 0-31 before the reroll, as
 *     trail lengths already were, so no frame overruns the field
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

#define GLITCH      64    /* trail glitch frequency (0=off, 255=constant) */
#define TRAILMIN     6      /* minimum trail length (rows)                  */
#define TRAILMAX    14      /* maximum trail length (rows)                  */
#define REVERSE     64      /* highlight chance (0=never, 255=always)       */
#define NEWCHAR     51      /* new char chance (lower=more flicker)         */
#define NUMDRIPS    28      /* active drops (max 32)                        */
#define SPDSTART     9      /* initial speed range (0 to N-1, lower=faster) */
#define SPDRESET     5      /* reset speed range (0 to N-1, lower=faster)   */
#define GRAPHIC     16      /* graphics block chance (0=never, 255=always)  */

/* Speeds and columns are drawn from 0-31, so these cannot exceed 32. */
#if SPDSTART > 32 || SPDRESET > 32 || NUMDRIPS > 32
#error "SPDSTART, SPDRESET and NUMDRIPS must be 32 or less"
#endif

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
#define cell  (*(unsigned char **)0x00FD)
#define cell2 (*(unsigned char **)0x00F7)
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
             * than the initial ones, which makes the rain accelerate.
             *
             * Both are drawn from 0-31 and rerolled while out of range,
             * the way rnd_trail() works. The PET rerolled a whole byte
             * until it fell under SPDRESET, which takes 51 tries on
             * average and hundreds at worst: on the CoCo that made about
             * one frame in 80 miss the field sync. */
            do {
                headch = rnd() & 0x1f;
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
