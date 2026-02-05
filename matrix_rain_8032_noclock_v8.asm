; ============================================================
; Matrix Rain Effect (Commodore 8032)
; ============================================================
; Matrix-style falling characters
; Modified for 80-column PET (8032)
; Original from Petopia demo by Milasoft
; ============================================================
;
; Memory Map:
;   Screen RAM: $8000-$87CF (80x25 = 2000 bytes)
;   VIA Port B: $E840 (bit 5 = vertical retrace)
;
; Zero Page Usage:
;   $fb-$fc : temp pointer / calculation
;   $fd-$fe : current rain drop screen address
;   $f7-$fa : multiply workspace
;
; ============================================================

* = $0401

; ------------------------------------------------------------
; BASIC stub: 10 SYS 1040
; ------------------------------------------------------------
!byte $19,$08,$0a,$00,$9e,$20,$28,$31,$30,$34,$30,$29
!byte 0,0,0

; ------------------------------------------------------------
; Constants
; ------------------------------------------------------------
SCREEN_LO    = $00              ; screen starts at $8000
SCREEN_HI    = $80
SCREEN_END   = $88              ; screen ends before $8800
COLS         = 80               ; screen width
CHR_SPACE    = 32               ; space character
CHR_CLEAR    = 147              ; clear screen PETSCII
KERNAL_CHROUT = $ffd2


; ============================================================
; Initialization
; ============================================================

        lda #CHR_CLEAR
        jsr KERNAL_CHROUT      ; clear screen


; ------------------------------------------------------------
; Seed random generator
; ------------------------------------------------------------

        lda #21
        sta .seedlo
        lda #$1c
        sta .seedhi


; ------------------------------------------------------------
; Initialize rain columns
; ------------------------------------------------------------

        ldx #0
InitRain:
        ; Random speed (0-8)
-       jsr RANDOM
        cmp #9
        bcs -
        sta SPEED,x  

        ; Random trail length (TRAILMIN to TRAILMAX-1)
-       jsr RANDOM
        and #$1f               ; 0-31 range
        clc
        adc TRAILMIN
        cmp TRAILMAX
        beq +                  ; equal to max is ok
        bcs -                  ; over max, try again
+       sta TRAIL,x

        ; Set initial X position (column = index)
        txa
        sta RAINLO,x

        inx
        cpx NUMDRIPS
        bne InitRain


; ------------------------------------------------------------
; Initialize Y positions from stagger table
; ------------------------------------------------------------

        ldx #0
-       lda RAINHIS,x          ; get staggered start position
        sta RAINHI,x
        inx
        cpx NUMDRIPS
        bne -


; ============================================================
; Main Loop
; ============================================================

MainLoop:
-       lda $e840              ; VIA Port B
        and #32                ; check vertical retrace bit
        bne -                  ; wait for vsync

        jsr DRAW               ; update all rain drops

        jmp MainLoop


; ============================================================
; DRAW - Update all rain columns
; ============================================================
; Processes each active rain drop:
;   1. Possibly change head character
;   2. Dim previous head (remove reverse)
;   3. Occasionally glitch a trail character
;   4. Move drop down or reset if at bottom
; ============================================================

DRAW:
        ldx #0

NextColumn:
        ldy #0                 ; Y always 0 for indirect addressing

        ; Load current drop position into $fd/$fe
        lda RAINLO,x
        sta $fd
        lda RAINHI,x
        sta $fe

        ; Bounds check: must be in screen range $8000-$87FF
        lda $fe
        cmp #SCREEN_HI
        bcs +                  ; >= $80, check upper bound
        jmp SkipColumn         ; < $8000, not on screen yet
+       cmp #SCREEN_END
        bcc +                  ; < $88, in valid range
        jmp SkipColumn         ; >= $8800, off screen
+

; ------------------------------------------------------------
; Update head character
; ------------------------------------------------------------

        ; Decide: keep existing char or generate new one?
        jsr RANDOM
        cmp NEWCHAR            ; threshold (lower = more new chars)
        bcs .keepChar          ; >= threshold: keep existing

        ; Generate new random character
        jsr RANDOM
        and #$7f               ; mask to 0-127 (normal video)
        sta $fb
        jsr RANDOM
        cmp REVERSE            ; check reverse chance
        bcs .writeHead
        lda $fb
        ora #$80               ; set high bit for reverse video
        sta $fb
        jmp .writeHead

.keepChar:
        ; Keep existing character (preserve reverse state)
        lda ($fd),y
        cmp #CHR_SPACE         ; is it a space?
        beq .newCharForSpace   ; spaces need a new character
        sta $fb
        jmp .writeHead

.newCharForSpace:
        ; Current cell is empty, generate new character
        jsr RANDOM
        and #$7f               ; normal video
        sta $fb
        jsr RANDOM
        cmp REVERSE
        bcs .writeHead
        lda $fb
        ora #$80               ; reverse video
        sta $fb

.writeHead:
        ; Special case: no reverse video on bottom line
        ; (prevents visual glitches at screen edge)
        lda $fe
        cmp #$87               ; bottom line is $87B0-$87FF
        bne .doWrite
        lda $fd
        cmp #$B0               ; >= $87B0?
        bcc .doWrite
        lda $fb
        and #$7f               ; force normal video
        sta $fb

.doWrite:
        lda $fb
        sta ($fd),y            ; write head character

; ------------------------------------------------------------
; Dim previous head (one row up)
; ------------------------------------------------------------

        ; Calculate address one row up (subtract 80)
        lda $fd
        sec
        sbc #COLS
        sta $fb
        lda $fe
        sbc #0
        sta $fc
        
        ; Bounds check
        cmp #SCREEN_HI
        bcc SkipColumn         ; above screen top
        
        ; Remove reverse video from previous head
        lda ($fb),y
        and #$7f
        sta ($fb),y

; ------------------------------------------------------------
; Trail glitch effect
; ------------------------------------------------------------

        ; Random chance to glitch a trail character
        jsr RANDOM
        cmp GLITCH             ; threshold (0=off, higher=more frequent)
        bcs SkipColumn         ; no glitch this frame
        
        ; Pick random row within trail (skip row 0 = head)
        jsr RANDOM
        and #$0f               ; 0-15
        cmp TRAIL,x
        bcs SkipColumn         ; beyond trail length
        cmp #0
        beq SkipColumn         ; skip the head
        
        ; Calculate position: head - (row * 80)
        sta $f7                ; save row number
        jsr MultiplyBy80       ; result in $f9/$fa
        
        ; Subtract from head position
        lda RAINLO,x
        sec
        sbc $f9
        sta $fb
        lda RAINHI,x
        sbc $fa
        sta $fc
        
        ; Bounds check
        lda $fc
        cmp #SCREEN_HI
        bcc SkipColumn
        cmp #SCREEN_END
        bcs SkipColumn
        
        ; Write random character (normal video)
        jsr RANDOM
        and #$7f
        sta ($fb),y

; ------------------------------------------------------------
; Movement timing
; ------------------------------------------------------------

SkipColumn:
        ; Check if it's time to move this drop
        lda DEL,x
        cmp SPEED,x
        beq MoveDown
        inc DEL,x              ; not yet, increment delay
        jmp Advance

MoveDown:
        lda #0
        sta DEL,x              ; reset delay counter

; ------------------------------------------------------------
; Clear tail and move down
; ------------------------------------------------------------

        ; Calculate tail position (TRAIL rows up from head)
        lda TRAIL,x
        sta $f7
        jsr MultiplyBy80       ; result in $f9/$fa
        
        ; Subtract from current position
        lda RAINLO,x
        sec
        sbc $f9
        sta $fd
        lda RAINHI,x
        sbc $fa
        sta $fe

        ; Check tail position
        lda $fe
        cmp #SCREEN_HI
        bcc SkipTail           ; above screen, don't clear
        cmp #SCREEN_END
        bcc ClearTail          ; on screen, clear it

        ; Tail went off bottom - reset this drop
        lda #SCREEN_HI
        sta RAINHI,x

        ; New random X position (0-79)
-       jsr RANDOM
        cmp #COLS
        bcs -
        sta RAINLO,x 

        ; New random speed (0-4, faster than initial)
-       jsr RANDOM
        cmp #5
        bcs -
        sta SPEED,x

        ; New random trail length
-       jsr RANDOM
        and #$1f
        clc
        adc TRAILMIN
        cmp TRAILMAX
        beq +
        bcs -
+       sta TRAIL,x

        jmp Advance

ClearTail:
        lda #CHR_SPACE
        sta ($fd),y

SkipTail:
        ; Move down one row (add 80 to position)
        lda RAINLO,x
        clc
        adc #COLS
        sta RAINLO,x
        lda RAINHI,x
        adc #0
        sta RAINHI,x

Advance:
        inx
        cpx NUMDRIPS
        beq +
        jmp NextColumn
+       rts


; ============================================================
; MultiplyBy80 - Multiply $f7 by 80
; ============================================================
; Input:  $f7 = value to multiply
; Output: $f9/$fa = result (low/high)
; Destroys: $f8
; Method: n*80 = n*64 + n*16
; ============================================================

MultiplyBy80:
        lda #0
        sta $f8                ; high byte for shifts
        lda $f7
        
        ; Calculate n*16
        asl                    ; *2
        rol $f8
        asl                    ; *4
        rol $f8
        asl                    ; *8
        rol $f8
        asl                    ; *16
        rol $f8
        sta $f9                ; save n*16 low
        lda $f8
        sta $fa                ; save n*16 high
        
        ; Continue to n*64
        lda $f9
        asl                    ; *32
        rol $fa
        asl                    ; *64
        rol $fa
        
        ; Add n*16 to get n*80
        clc
        adc $f9
        sta $f9
        lda $fa
        adc $f8
        sta $fa
        rts


; ============================================================
; RANDOM - 16-bit LFSR random number generator
; ============================================================
; Output: A = random byte
; Preserves: X, Y
; ============================================================

RANDOM:
        lda .seedhi
        lsr
        rol .seedlo
        bcc +
        eor #$b4               ; LFSR tap polynomial
+       sta .seedhi
        eor .seedlo
        rts


; ============================================================
; Data Tables
; ============================================================

; Column X positions (low byte, high byte set from RAINHIS)
RAINLO   !fill 80,0

; Staggered start positions (high byte of screen address)
; $7f = one row above screen (appears immediately)
; $80 = at top of screen (slight delay)
; Mix creates organic "wave" effect at startup
RAINHIS  !byte $7f,$80,$7f,$80,$7f,$80,$7f,$80,$7f,$80
         !byte $7f,$80,$7f,$80,$7f,$80,$7f,$80,$7f,$80
         !byte $80,$80,$80,$80,$7f,$80,$80,$80,$80,$80
         !byte $7f,$80,$7f,$80,$7f,$80,$7f,$80,$7f,$80
         !byte $7f,$80,$7f,$80,$7f,$80,$7f,$80,$7f,$80
         !byte $80,$80,$80,$80,$7f,$80,$80,$80,$80,$80
         !byte $7f,$80,$7f,$80,$7f,$80,$7f,$80,$7f,$80
         !byte $7f,$80,$7f,$80,$7f,$80,$7f,$80,$7f,$80

; Runtime state (per-column)
RAINHI   !fill 80,0            ; current Y position (high byte)
SPEED    !fill 80,0            ; movement delay (0=fastest)
DEL      !fill 80,0            ; current delay counter
TRAIL    !fill 80,0            ; trail length for this column


; ============================================================
; Configuration Variables
; ============================================================
; Adjust these to change the effect's appearance

GLITCH   !byte 64              ; trail glitch frequency (0=off, 255=constant)
TRAILMIN !byte 10              ; minimum trail length (rows)
TRAILMAX !byte 24              ; maximum trail length (rows)
REVERSE  !byte 64              ; reverse video chance (0=never, 255=always)
NEWCHAR  !byte 51              ; new char chance (lower=more flicker)
NUMDRIPS !byte 80              ; active columns (max 80, try 70 for gaps)


; ============================================================
; Random seed (runtime)
; ============================================================

.seedlo  !byte 0
.seedhi  !byte 0