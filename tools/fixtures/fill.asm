; Fixture for tools\test_coco_tools.ps1.
;
; Fills the 32x16 screen with 0, 1, 2 ... 255, 0, 1 ... 255, then runs
; 12 frames that each do exactly 523 cycles of work after the field
; sync, then parks at DONE. The tests read the pattern back through a
; snapshot and the 523 cycles through a trace.
;
; Assembled with -D FAST it first switches a CoCo 3 to 1.79 MHz, for
; testing trace timing at that speed.

        org     $0E00
start   orcc    #$50            ; interrupts off, as the real program does
        IFDEF   FAST
        sta     $FFD9           ; CoCo 3: CPU to 1.79 MHz
        ENDC
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
