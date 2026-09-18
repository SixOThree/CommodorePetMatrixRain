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
#define NUMDRIPS    65      /* the PET's 70 misses the 60 Hz field now and then */
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
