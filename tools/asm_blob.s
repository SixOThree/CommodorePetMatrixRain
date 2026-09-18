; The shipped 8032 binary, minus its two-byte load address, for
; asm_harness.c to copy into place. The path is relative to the
; repository root, which is where build.ps1 runs cl65 from.

        .export _pet_prg, _pet_prg_end

        .rodata
_pet_prg:
        .incbin "matrix_rain_8032_noclock_v8.prg", 2
_pet_prg_end:
