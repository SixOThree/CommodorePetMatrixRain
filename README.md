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

## Running

Load the .prg file on a Commodore PET 8032 or emulator (such as [VICE xpet](https://vice-emu.sourceforge.io/)):

```
LOAD "*",8
RUN
```

The program includes a BASIC stub that automatically starts the machine code.

## Configuration

Visual parameters can be adjusted by modifying these values in the source (lines 454-459):

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
