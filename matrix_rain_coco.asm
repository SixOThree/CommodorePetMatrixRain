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

GLITCH   equ  64           ; trail glitch frequency (0=off, 255=constant)
TRAILMIN equ  6              ; minimum trail length (rows)
TRAILMAX equ  14             ; maximum trail length (rows)
REVERSE  equ  64             ; highlight chance (0=never, 255=always)
NEWCHAR  equ  51             ; new char chance (lower=more flicker)
NUMDRIPS equ  28             ; active drops (max 32)
SPDSTART equ  9              ; initial speed range (0 to N-1, lower=faster)
SPDRESET equ  5              ; reset speed range (0 to N-1, lower=faster)
GRAPHIC  equ  16             ; graphics block chance (0=never, 255=always)

; Speeds and columns are drawn from 0-31, so these cannot exceed 32.
         IFGT SPDSTART-32
         ERROR SPDSTART must be 32 or less
         ENDC
         IFGT SPDRESET-32
         ERROR SPDRESET must be 32 or less
         ENDC
         IFGT NUMDRIPS-32
         ERROR NUMDRIPS must be 32 or less
         ENDC

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
initdrop jsr  random         ; speed: 0 to SPDSTART-1, from 0-31 as
         anda #$1F           ; the trail length is (see RNDTRAIL)
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
synced   jsr  draw           ; build-coco.ps1 times frames from here
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
;
; Both are drawn from 0-31 and rerolled while out of range, the way
; the PET draws trail lengths. The PET rerolled a whole byte until it
; fell under 5, which takes 51 tries on average and hundreds at worst;
; here that made about one frame in 80 miss the field sync.
recycle  jsr  random
         anda #$1F
         cmpa #COLS
         bhs  recycle
         ldx  #SCREEN
         leax a,x            ; A is 0-31, so reading it as signed is fine
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
         lbne nextdrop       ; long branch: DRAW is over 128 bytes
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
