; ============================================================
; Matrix Rain Effect (TRS-80 Color Computer 3)
; ============================================================
; Matrix-style falling characters in colour for the CoCo 3's
; hardware text mode: each trail fades from a white head through
; bright green and green to dark green.
; Ported from the CoCo 1/2 version (matrix_rain_coco.asm), itself
; from matrix_rain_8032_noclock_v8.asm (Commodore PET 8032).
; Original from Petopia demo by Milasoft.
;
; Author: Matthew Dugal (github.com/SixOThree)
; ============================================================
;
; Two builds from this file:
;   lwasm --decb -o matrix_rain_coco3.bin matrix_rain_coco3.asm
;       80x24, 65 drops, palette for an RGB monitor
;   lwasm --decb -D COMPOSITE -o matrix_rain_coco3_cmp.bin matrix_rain_coco3.asm
;       40x24, 40 drops, palette for a TV or composite monitor
; (build-coco3.ps1 does both and writes the tape and disk images.)
; Run:    LOADM"MATRIX3":EXEC, or MATRIX3C for composite
;
; Memory map (as BASIC leaves the MMU, logical $0000 = physical $70000):
;   $0E00-$0E0F  variables, reached through the direct page register
;   $0E10-       code and tables, then drop records and stack
;   $2000-       screen: 2 bytes a cell, character then attribute
;                (physical $72000)
;   $FF02/$FF03  PIA 0 side B: field sync sets bit 7 of $FF03
;   $FF90-$FF9F  GIME video registers; $FFB0-$FFBF palette
;   $FFD9        any write: CPU to 1.79 MHz
;
; Attribute byte: bits 5-3 foreground (palette slots 8-15),
; bits 2-0 background (slots 0-7), bits 7-6 (blink, underline) clear.
;
; matrix_rain_coco3.c is the reference model. build-coco3.ps1 -Test
; requires this program to leave screen RAM exactly as it does, so a
; change to any setting below goes into both files.
; ============================================================

; ------------------------------------------------------------
; Configuration
; ------------------------------------------------------------

         IFDEF COMPOSITE
COLS     equ  40             ; 40x24 for a TV or composite monitor
COLMASK  equ  $3F            ; column rolls: 0-63, rerolled while >= COLS
GIMERES  equ  $05            ; GIME resolution: 40 columns, attributes
GLITCH   equ  64             ; trail glitch frequency (0=off, 255=constant)
TRAILMIN equ  14             ; minimum trail length (rows)
TRAILMAX equ  23             ; maximum trail length (rows)
REVERSE  equ  64             ; reverse head chance (0=never, 255=always)
NEWCHAR  equ  51             ; new char chance (lower=more flicker)
NUMDRIPS equ  40             ; active drops (max COLS)
SPDSTART equ  15             ; initial speed range (0 to N-1, lower=faster)
SPDRESET equ  8              ; reset speed range (0 to N-1, lower=faster)
GRAPHIC  equ  16             ; foreign letter chance (0=never, 255=always)
BLOCKGLITCH equ 255          ; chance a foreign letter in a trail changes
                             ; each time the sweep visits it, every 8
                             ; frames (0=never, 255=always)
         ELSE
COLS     equ  80             ; 80x24 for an RGB monitor
COLMASK  equ  $7F            ; column rolls: 0-127, rerolled while >= COLS
GIMERES  equ  $15            ; GIME resolution: 80 columns, attributes
GLITCH   equ  64
TRAILMIN equ  10
TRAILMAX equ  23
REVERSE  equ  64
NEWCHAR  equ  51
NUMDRIPS equ  65             ; the PET's 70 misses the 60 Hz field now and then
SPDSTART equ  9
SPDRESET equ  5
GRAPHIC  equ  16
BLOCKGLITCH equ 255
         ENDC

; Speeds are drawn from 0-31, and a trail needs rows for the fade.
         IFGT SPDSTART-32
         ERROR SPDSTART must be 32 or less
         ENDC
         IFGT SPDRESET-32
         ERROR SPDRESET must be 32 or less
         ENDC
         IFGT NUMDRIPS-COLS
         ERROR NUMDRIPS must be COLS or less
         ENDC
         IFLT TRAILMIN-5
         ERROR TRAILMIN must be 5 or more for the fade
         ENDC

; ------------------------------------------------------------
; Constants
; ------------------------------------------------------------

ROWS     equ  24
ROWBYTES equ  COLS*2         ; 2 bytes a cell
SCREEN   equ  $2000          ; screen RAM (physical $72000)
SCREENEND equ SCREEN+ROWS*ROWBYTES
NOREVERSE equ SCREEN+(ROWS-1)*ROWBYTES ; the bottom row: no reverse heads
SWEEPCELLS equ COLS*ROWS/8   ; cells FLICKER sweeps a frame: an eighth

SPACE    equ  $20            ; an empty cell's character
FOREIGN  equ  $20            ; foreign letters are $00-$1F
HEAD     equ  $00            ; white on black
REVHEAD  equ  $21            ; black on bright green
BRIGHT   equ  $08            ; bright green on black
GREEN    equ  $10            ; green on black
DARK     equ  $18            ; dark green on black; also an empty cell's,
                             ; so a character glitched into a gap between
                             ; trails reads as residue, not a stray head

PIA0PB   equ  $FF02          ; reading it clears the field sync flag
PIA0CRB  equ  $FF03          ; bit 7 is set by field sync

; Drop records, one per drop, walked with U.
POS      equ  0              ; head screen address (word)
SPD      equ  2              ; frames between moves (0=fastest)
DEL      equ  3              ; frames waited so far
TRL      equ  4              ; trail length in rows
RECSIZE  equ  5

; RAND: the next random number into A, the LFSR step written inline.
; RANDOM is this plus RTS. DRAW uses RAND for the rolls every drop makes
; every frame, where a JSR and RTS would cost 13 cycles more each.
; Preserves B, X, Y and U.
RAND     macro
         lda  <seedhi
         lsra
         rol  <seedlo
         bcc  @keep
         eora #$B4           ; LFSR tap polynomial
@keep    sta  <seedhi
         eora <seedlo
         endm

         org  $0E00
         setdp $0E

; ------------------------------------------------------------
; Variables ($0E00-$0E0F), on the direct page once start sets DP
; ------------------------------------------------------------

seedlo   fcb  0              ; random generator state
seedhi   fcb  0
headch   fcb  0              ; scratch for RNDHEAD
frames   fdb  0              ; frames drawn; only test builds use it
sweep    fdb  0              ; where FLICKER sweeps next
         zmb  9              ; the rest of the 16-byte area

; ============================================================
; Initialization
; ============================================================

start    orcc #$50           ; mask IRQ and FIRQ
         lds  #stacktop      ; keep every write inside our own memory
         lda  #$0E
         tfr  a,dp           ; direct page = the variables above
         sta  $FFD9          ; CPU to 1.79 MHz

; GIME: text with attributes, reading from physical $72000. These are
; the values BASIC's WIDTH 80 and WIDTH 40 write. The registers cannot
; be read back, so $FF90 is written whole, as BASIC does.
         lda  #$4C           ; CoCo 3 mode, MMU on, ROM as BASIC has it
         sta  $FF90
         lda  #$03           ; text, 8 lines a character row
         sta  $FF98
         lda  #GIMERES
         sta  $FF99
         clr  $FF9A          ; border: palette value 0, black
         clr  $FF9C          ; no vertical scroll
         lda  #$E4           ; video at $E400 x 8 = physical $72000
         sta  $FF9D
         clr  $FF9E
         clr  $FF9F          ; no horizontal offset
         ldx  #palette
         ldy  #$FFB0
setpal   lda  ,x+
         sta  ,y+
         cmpy #$FFC0
         bne  setpal

         ldx  #SCREEN        ; clear the screen to black spaces
         ldd  #SPACE*256+DARK
clrloop  std  ,x++
         cmpx #SCREENEND
         bne  clrloop

         lda  #21            ; seed the random generator, as the PET does
         sta  <seedlo
         lda  #$1C
         sta  <seedhi

         ldx  #SCREEN        ; FLICKER starts at the top
         stx  <sweep

         ldu  #drops
         ldy  #rainhis
         clrb                ; B = drop number x 2 = its column's offset
initdrop jsr  random         ; speed: 0 to SPDSTART-1, from 0-31
         anda #$1F
         cmpa #SPDSTART
         bhs  initdrop
         sta  SPD,u
         jsr  rndtrail
         sta  TRL,u
         clr  DEL,u
         lda  ,y+            ; $20 = top row, $1E = 256 cells above it
         std  POS,u
         leau RECSIZE,u
         addb #2
         cmpb #NUMDRIPS*2
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
synced   jsr  draw           ; build-coco3.ps1 times frames from here
         jsr  flicker
         bra  mainloop

         IFDEF TESTFRAMES
testdone bra  testdone
         ENDC

; ============================================================
; DRAW - one frame
; ============================================================
; For each drop: refresh the head, maybe glitch one character in the
; trail, then move or wait. Moving erases the tail and sets the fade's
; colours behind the new head. U walks the drop records, and X holds
; the head address throughout.
; ============================================================

draw     ldu  #drops
nextdrop ldx  POS,u
         cmpx #SCREEN
         lblo timing         ; not on the screen yet
         cmpx #SCREENEND
         lbhs timing         ; already below it

; Head: usually keep what is there, sometimes pick anew. An empty cell
; always gets a fresh character. A kept character keeps a head's
; colours, and turns white if it belonged to another drop's trail.
         RAND
         cmpa #NEWCHAR
         bhs  keephead
         jsr  rndhead        ; A = character, B = attribute
         bra  placehead
keephead ldd  ,x
         cmpa #SPACE
         bne  keepattr
         jsr  rndhead
         bra  placehead
keepattr cmpb #HEAD
         beq  placehead
         cmpb #REVHEAD
         beq  placehead
         ldb  #HEAD
placehead
         cmpx #NOREVERSE
         blo  writehead
         ldb  #HEAD          ; no reverse heads on the bottom row
writehead
         std  ,x

; Now and then swap one character somewhere in the trail, keeping its
; colour. As on the PET, only while the row above the head is on screen.
         leay -ROWBYTES,x
         cmpy #SCREEN
         blo  timing
         RAND
         cmpa #GLITCH
         bhs  timing
         RAND
         anda #$0F           ; rows 1-15 up from the head
         beq  timing         ; row 0 is the head itself
         cmpa TRL,u
         bhs  timing         ; past the end of the trail
         ldb  #ROWBYTES
         mul                 ; D = rows x ROWBYTES
         coma                ; D = -D
         comb
         addd #1
         leay d,x
         cmpy #SCREEN
         blo  timing         ; above the screen (it cannot be below)
         jsr  rndchar
         sta  ,y

; Time to move?
timing   lda  DEL,u
         cmpa SPD,u
         beq  move
         inc  DEL,u
         lbra advance
move     clr  DEL,u

; Erase the tail, or recycle the drop once its whole trail has left
; the bottom of the screen.
         lda  TRL,u
         ldb  #ROWBYTES
         mul                 ; D = trail x ROWBYTES
         coma                ; D = -D
         comb
         addd #1
         leay d,x            ; Y = the tail
         cmpy #SCREENEND
         bhs  recycle
         cmpy #SCREEN
         blo  movedown       ; the tail is still above the screen
         ldd  #SPACE*256+DARK
         std  ,y
movedown leax ROWBYTES,x
         stx  POS,u

; The fade: bright green 1 row behind the new head, green 2 rows
; behind, dark green trail-2 rows behind. Every cell passes each point
; as the drop falls, so it takes on each colour in turn.
         ldb  #BRIGHT
         leay -ROWBYTES,x
         bsr  setattr
         ldb  #GREEN
         leay -2*ROWBYTES,x
         bsr  setattr
         lda  TRL,u
         suba #2
         ldb  #ROWBYTES
         mul
         coma
         comb
         addd #1
         leay d,x
         ldb  #DARK
         bsr  setattr
         bra  advance

; New column on the top row, new speed, new trail. Both rolls take a
; masked value and reroll while out of range, as the trail length does.
recycle  jsr  random
         anda #COLMASK
         cmpa #COLS
         bhs  recycle
         tfr  a,b
         lslb                ; the column's byte offset: 0-158
         ldx  #SCREEN
         abx                 ; ABX adds B unsigned
         stx  POS,u
newspeed jsr  random
         anda #$1F
         cmpa #SPDRESET
         bhs  newspeed
         sta  SPD,u
         jsr  rndtrail
         sta  TRL,u

advance  leau RECSIZE,u
         cmpu #drops+NUMDRIPS*RECSIZE
         lbne nextdrop
         rts

; SETATTR: store attribute B in the cell at Y, if Y is on the screen.
setattr  cmpy #SCREEN
         blo  setattrx
         cmpy #SCREENEND
         bhs  setattrx
         stb  1,y
setattrx rts

; ============================================================
; FLICKER - the foreign letters in the trails keep changing
; ============================================================
; Each frame sweeps an eighth of the screen, a different eighth each
; time, so every cell is visited every 8 frames. A foreign letter
; found in a trail (not a head) becomes another with chance
; BLOCKGLITCH.
;
; The loop takes four cells a pass, so its overhead is paid once for
; four; most cells hold no foreign letter and cost a load, a compare
; and an untaken branch. B counts the passes. Cells are still visited
; in order, so random numbers are used exactly as in the reference.
; ============================================================

         IFNE SWEEPCELLS&3
         ERROR SWEEPCELLS must be a multiple of 4
         ENDC

flicker  ldx  <sweep
         ldb  #SWEEPCELLS/4
flickpass
         lda  ,x             ; foreign letters are below $20
         cmpa #FOREIGN
         blo  flick0
flickc1  lda  2,x
         cmpa #FOREIGN
         blo  flick1
flickc2  lda  4,x
         cmpa #FOREIGN
         blo  flick2
flickc3  lda  6,x
         cmpa #FOREIGN
         blo  flick3
flicknext
         leax 8,x
         decb
         bne  flickpass
         cmpx #SCREENEND     ; after the last eighth, back to the top
         bne  flicksave
         ldx  #SCREEN
flicksave
         stx  <sweep
         rts

flick0   leay ,x
         bsr  flickone
         bra  flickc1
flick1   leay 2,x
         bsr  flickone
         bra  flickc2
flick2   leay 4,x
         bsr  flickone
         bra  flickc3
flick3   leay 6,x
         bsr  flickone
         bra  flicknext

; FLICKONE: the foreign letter in the cell at Y, unless it is a head,
; becomes another with chance BLOCKGLITCH. Preserves B and X.
flickone lda  1,y            ; heads are left to DRAW
         cmpa #HEAD
         beq  flickonex
         cmpa #REVHEAD
         beq  flickonex
         jsr  random
         cmpa #BLOCKGLITCH
         bhs  flickonex
         jsr  rndforeign
         sta  ,y
flickonex
         rts

; ============================================================
; RNDHEAD - a head: a new character, white, or reversed with the
; REVERSE chance. Out: A = character, B = attribute.
; ============================================================

rndhead  jsr  rndchar
         sta  <headch
         jsr  random
         ldb  #HEAD
         cmpa #REVERSE
         bhs  rndheadx
         ldb  #REVHEAD
rndheadx lda  <headch
         rts

; ============================================================
; RNDCHAR - a new rain character. Out: A.
; ============================================================
; Now and then a foreign letter, otherwise printable ASCII $21-$7E.

rndchar  jsr  random
         cmpa #GRAPHIC
         bhs  letter
                             ; fall into RNDFOREIGN
; RNDFOREIGN - a foreign letter, $00-$1F. Out: A.
rndforeign
         jsr  random
         anda #$1F
         rts
letter   jsr  random
         anda #$7F
         cmpa #$21
         blo  letter         ; control codes and space: reroll
         cmpa #$7F
         beq  letter
         rts

; ============================================================
; RNDTRAIL - trail length, TRAILMIN to TRAILMAX. Out: A.
; ============================================================

rndtrail jsr  random
         anda #$1F
         adda #TRAILMIN
         cmpa #TRAILMAX
         bhi  rndtrail
         rts

; ============================================================
; RANDOM - 16-bit LFSR, the PET routine instruction for instruction
; (see RAND). Out: A. Preserves B, X, Y and U.
; ============================================================

random   RAND
         rts

; ============================================================
; Data
; ============================================================

; Palette slots 0-7 (backgrounds), then 8-15 (foregrounds).
; Backgrounds: black, bright green. Foregrounds: white, bright green,
; green, dark green, black.
palette
         IFDEF COMPOSITE
         fcb  $00,$21,$00,$00,$00,$00,$00,$00
         fcb  $30,$21,$11,$01,$00,$00,$00,$00
         ELSE
         fcb  $00,$12,$00,$00,$00,$00,$00,$00
         fcb  $3F,$12,$10,$02,$00,$00,$00,$00
         ENDC

; Starting high byte for each drop: $20 is the top row, $1E is 256
; cells above it. The PET's table, $7f and $80 becoming $1E and $20;
; the first NUMDRIPS entries are used.
rainhis  fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20
         fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20
         fcb  $20,$20,$20,$20,$1E,$20,$20,$20,$20,$20
         fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20
         fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20
         fcb  $20,$20,$20,$20,$1E,$20,$20,$20,$20,$20
         fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20
         fcb  $1E,$20,$1E,$20,$1E,$20,$1E,$20,$1E,$20

codeend  equ  *              ; the .bin loads $0E00 up to here

; Reserved, not stored in the .bin.
drops    rmb  NUMDRIPS*RECSIZE
stack    rmb  64
stacktop equ  *
progend  equ  *

         IFGT progend-SCREEN
         ERROR the program runs into the screen at $2000
         ENDC

         end  start
