# Commodore PET Matrix Rain

A Matrix-style falling character animation for the Commodore PET 8032 (80-column display).

## About

This 6502 assembly program recreates the iconic "digital rain" effect from The Matrix on vintage Commodore PET hardware. Features include:

- 80 independent rain columns with configurable speed and trail length
- Trail "glitch" effect for visual interest
- Reverse video highlighting on lead characters
- Smooth animation synced to vertical retrace

## Development

This project was developed using [C64 Studio](https://github.com/GeorgRottensteiner/C64Studio), an IDE for 6502 assembly targeting Commodore 8-bit computers.

## The C version

`matrix_rain_8032.c` is the same effect written in C, compiled for the PET
with [cc65](https://cc65.github.io/). It pokes the same screen RAM, waits on
the same VIA retrace bit, and carries the same LFSR with the same seed, so it
draws the same sequence of characters as the assembly.

```powershell
.\build.ps1            # writes matrix_rain_8032_c.prg
.\build.ps1 -Run       # and launches it in VICE xpet
.\build.ps1 -Test      # runs it under cc65's 6502 simulator instead
```

Or by hand:

```
cl65 -t pet -Oi -Cl -o matrix_rain_8032_c.prg matrix_rain_8032.c
```

It is slower. A frame costs about 40,500 cycles against a 16,667-cycle
retrace budget, so the rain falls at roughly 25 fps instead of 60. Most of
that goes on the random number generator, which cc65 compiles to around 90
cycles against the assembly's 25. The assembly version remains the one to
use on real hardware. The C version is there to read.

## Running

Load the .prg file on a Commodore PET 8032 or emulator (such as [VICE xpet](https://vice-emu.sourceforge.io/)):

```
LOAD "*",8
RUN
```

The program includes a BASIC stub that automatically starts the machine code.

## Configuration

Visual parameters can be adjusted by modifying these values in the source.
In the assembly they are the data bytes near the end of the file; in the C
version they are the `#define`s at the top. Both use the same names and
defaults.

| Variable | Default | Description |
|----------|---------|-------------|
| GLITCH   | 64      | Trail glitch frequency - how often existing trail characters change (0=off, 255=constant) |
| TRAILMIN | 10      | Minimum trail length in rows |
| TRAILMAX | 24      | Maximum trail length in rows |
| REVERSE  | 64      | Reverse video chance (0=never, 255=always) |
| NEWCHAR  | 51      | New character chance - characters are written every frame, so too high of a value looks noisy |
| NUMDRIPS | 70      | Active columns (max 80, use 70 for gaps) |
| SPDSTART | 9       | Initial speed range 0 to N-1 (lower=faster) |
| SPDRESET | 5       | Reset speed range 0 to N-1 (lower=faster, creates acceleration) |

## Credits

- **Author**: Matthew Dugal ([@SixOThree](https://github.com/SixOThree))
- **Original concept**: Petopia demo by Milasoft

## License

This project is provided for educational and hobbyist purposes.
