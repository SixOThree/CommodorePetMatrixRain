/* ============================================================
 * Runs the assembly version under cc65's 6502 simulator
 * ============================================================
 * build.ps1 -Test uses this to check the C port against the original
 * and to time both on the same clock.
 *
 * The shipped .prg is copied to $0401, where its absolute addressing
 * expects to live. Two parts of it are skipped: the KERNAL screen
 * clear, because there is no KERNAL here, and the main loop, which
 * would wait forever on a VIA that does not exist. Init and DRAW are
 * the original code, called directly.
 *
 * Build (from the repository root):
 *   cl65 -t sim6502 -C tools/sim_asm.cfg -o harness.bin
 *        tools/asm_harness.c tools/asm_blob.s
 *
 * SIM_FRAMES sets how many frames to draw. SIM_RAW prints every byte
 * of screen RAM afterwards in hex, one per line, in the same format as
 * matrix_rain_8032.c built with SIM_RAW.
 * ============================================================ */

#include <stdio.h>
#include <string.h>

#ifndef SIM_FRAMES
#define SIM_FRAMES 400
#endif

typedef void (*fn)(void);

#define PET_LOAD     ((unsigned char *)0x0401)
#define PET_LIMIT    ((unsigned char *)0x0800)  /* where this program starts */
#define PET_START    ((unsigned char *)0x0410)  /* SYS 1040                  */
#define PET_INIT     ((fn)0x0415)               /* past the screen clear     */
#define PET_MAINLOOP ((unsigned char *)0x0457)
#define PET_DRAW     ((fn)0x0464)

#define SCREEN       ((unsigned char *)0x8000)
#define SCREEN_SIZE  2048
#define CHR_SPACE    32
#define RTS          0x60

/* The .prg, from asm_blob.s. */
extern const unsigned char pet_prg[];
extern const unsigned char pet_prg_end[];

/* What should sit at the addresses above. If the assembly is edited and
 * rebuilt, they move, and this says so rather than jumping into the
 * middle of an instruction. */
static const unsigned char start_code[] = {
    0xA9, 0x93,             /* lda #$93   clear screen */
    0x20, 0xD2, 0xFF        /* jsr $ffd2               */
};
static const unsigned char mainloop_code[] = {
    0xAD, 0x40, 0xE8,       /* lda $e840               */
    0x29, 0x20,             /* and #$20                */
    0xD0, 0xF9,             /* bne MainLoop            */
    0x20, 0x64, 0x04        /* jsr DRAW ($0464)        */
};

int main(void)
{
    unsigned int size = (unsigned int)(pet_prg_end - pet_prg);
    unsigned int i;

    if (size > (unsigned int)(PET_LIMIT - PET_LOAD)) {
        printf("asm_harness: the .prg is %u bytes, too big to fit below $0800\n", size);
        return 1;
    }
    memcpy(PET_LOAD, pet_prg, size);

    if (memcmp(PET_START, start_code, sizeof start_code) != 0 ||
        memcmp(PET_MAINLOOP, mainloop_code, sizeof mainloop_code) != 0) {
        puts("asm_harness: init and DRAW are not where this expects them.");
        puts("The .prg has changed; update the PET_ addresses to match.");
        return 1;
    }
    *PET_MAINLOOP = RTS;                        /* so PET_INIT returns here  */

    memset(SCREEN, CHR_SPACE, SCREEN_SIZE);     /* the skipped screen clear  */

    PET_INIT();
    for (i = 0; i < SIM_FRAMES; ++i) {
        PET_DRAW();
    }

#ifdef SIM_RAW
    for (i = 0; i < SCREEN_SIZE; ++i) {
        printf("%02x\n", SCREEN[i]);
    }
#endif
    return 0;
}
