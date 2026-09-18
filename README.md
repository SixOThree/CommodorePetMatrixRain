# Commodore PET Matrix Rain

A Matrix-style falling character animation for the Commodore PET 8032 (80-column display).

## About

This 6502 assembly program recreates the iconic "digital rain" effect from The Matrix on vintage Commodore PET hardware. Features include:

- 80 independent rain columns with configurable speed and trail length
- Trail "glitch" effect for visual interest
- Reverse video highlighting on lead characters
- Smooth animation synced to vertical retrace

## Guides

Step-by-step guides for running the rain in an emulator, with screenshots of
what you should see:

- [Running in VICE](docs/running-in-vice.html): the PET versions, on a PET 8032 or 4032.
- [Running in XRoar](docs/running-in-xroar.html): the Color Computer 1/2 and 3 versions, including the ROMs XRoar needs.

And for changing it, building every output file, and running the tests:

- [Building for the PET](docs/building-for-the-pet.html): the 6502 assembly and C versions, with ACME or C64 Studio and cc65.
- [Building for the CoCo](docs/building-for-the-coco.html): the Color Computer versions, their tape and disk images, and the XRoar tests.

They're HTML pages. GitHub shows their source, so open them in a browser
from a clone or a download of the repository.

## Layout

Each machine has a folder holding its source, its build script and the
files you load into the machine or an emulator:

| Folder | What's in it |
|--------|--------------|
| `pet/` | The PET 8032 and 4032 assembly, the C version, and their `.prg` files |
| `coco/` | The Color Computer 1/2 version: assembly, its C reference model, and the `.bin`, `.cas` and `.dsk` files |
| `coco3/` | The Color Computer 3 version, both builds, the same way |
| `tools/` | Test harnesses, the tape and disk image writers, and the profiler |
| `docs/` | The guides above, and design notes |

The build scripts work from any folder. The examples below run them from
the repository folder.

## Development

This project was developed using [C64 Studio](https://github.com/GeorgRottensteiner/C64Studio), an IDE for 6502 assembly targeting Commodore 8-bit computers.

## The C version

`pet/matrix_rain_8032.c` is the same effect written in C, compiled for the PET
with [cc65](https://cc65.github.io/). It pokes the same screen RAM, waits on
the same VIA retrace bit, and carries the same LFSR with the same seed, so it
draws the same sequence of characters as the assembly.

```powershell
.\pet\build.ps1          # writes pet\matrix_rain_8032_c.prg
.\pet\build.ps1 -Run     # and launches it in VICE xpet
.\pet\build.ps1 -Test    # runs it under cc65's 6502 simulator and checks
                         # it against the assembly
.\tools\profile.ps1      # shows which routines a frame's cycles go to
```

Or by hand, from the `pet` folder:

```
cl65 -t pet -Oi -Cl -o matrix_rain_8032_c.prg matrix_rain_8032.c
```

It draws the identical screen. After 400 frames all 2048 screen bytes match
what the assembly produces. `-Test` checks this on every run: it loads the
shipped `matrix_rain_8032_noclock_v8.prg` into the same simulator
(`tools/asm_harness.c`), runs both versions from the same seed, and fails
if a single byte of screen RAM differs. It compares against that `.prg`,
not the `.asm` source, so rebuild the `.prg` after editing the assembly.
Changing a configuration value in only one of the two versions will make
it fail too, which is the point.

It is slower. A frame costs about 31,400 cycles against the assembly's
18,450 and a 16,667-cycle retrace budget, so the rain falls at roughly 32
fps instead of 54. Worth knowing: the assembly misses 60 fps too.

Getting there took some shaping for cc65's code generator. The hot
variables sit at fixed zero page addresses, the head offset and row offset
tables are kept as separate low and high byte arrays because cc65 reads an
`int` array by building a pointer every time, and the bounds checks lean on
unsigned wraparound so one comparison covers both ends. Every one of those
is commented in the source with what it saves. The assembly version remains
the one to use on real hardware.

## The Color Computer version

`coco/matrix_rain_coco.asm` is the effect on the TRS-80 Color Computer 1 and 2,
in 6809 assembly. It uses the CoCo's 32×16 text screen: bright green letters
on a black screen, with the odd green graphics block that keeps flickering
through new patterns as its trail falls. A highlighted lead shows as a dark
letter on a bright green cell, and a highlighted block turns buff.

Load it from disk with `LOADM"MATRIX":EXEC`, or from tape with
`CLOADM"MATRIX":EXEC`. It needs 16K and runs until you press reset.
To run it in the XRoar emulator, follow
[Running in XRoar](docs/running-in-xroar.html).

```powershell
.\coco\build.ps1         # writes matrix_rain_coco.bin, .cas and .dsk
.\coco\build.ps1 -Run    # and opens the .bin in XRoar
.\coco\build.ps1 -Test   # checks it in XRoar against matrix_rain_coco.c
```

Building needs [LWTOOLS](http://www.lwtools.ca/). Running and testing need
[XRoar](https://www.6809.org.uk/xroar/) with CoCo ROMs, and cc65 for the
reference model the test compares against.

The algorithm is the PET's, with the same random number generator, seed and
steps for each drop. Two things differ. Speeds and columns are drawn from
0 to 31 before the reroll, as trail lengths always were, because rerolling a
whole byte until it fell under 5 made about one frame in 80 miss the 60 Hz
deadline. And each frame sweeps a quarter of the screen, giving the green
blocks it finds a chance at a new pattern.

A frame takes at most about two thirds of the time between screen refreshes,
so it holds 60 fps. The settings are tuned for the smaller screen and sit at
the top of both `matrix_rain_coco.asm` and `matrix_rain_coco.c`, which have
to agree:

| Variable | CoCo default |
|----------|--------------|
| GLITCH   | 64 |
| TRAILMIN | 6 |
| TRAILMAX | 14 |
| REVERSE  | 64 |
| NEWCHAR  | 51 |
| NUMDRIPS | 28 (max 32) |
| SPDSTART | 9 (max 32) |
| SPDRESET | 5 (max 32) |
| GRAPHIC  | 16: the chance, out of 256, that a new character is a graphics block |
| BLOCKGLITCH | 128: the chance, out of 256, that a block changes each time the sweep reaches it, every 4 frames |

## The Color Computer 3 version

`coco3/matrix_rain_coco3.asm` is the effect in colour on the TRS-80 Color
Computer 3, using its hardware text mode, where every character has its
own colours. Each trail fades from a white head through bright green and
green to dark green, and accented letters flicker through the trails in
place of the CoCo 1/2's graphics blocks. It runs the CPU at 1.79 MHz.

There are two builds:

- `MATRIX3`: 80×24 with 65 drops, for an RGB monitor such as the CM-8.
  The PET's 70 drops miss the 60 Hz frame now and then.
- `MATRIX3C`: 40×24 with 40 drops, for a TV or composite monitor.
  A composite colour signal can't carry 80 columns.

Load one with `LOADM"MATRIX3":EXEC` (the disk holds both) or
`CLOADM"MATRIX3":EXEC` from its tape image. It runs until you press
reset. [Running in XRoar](docs/running-in-xroar.html) covers both builds,
including which TV input each one needs.

```powershell
.\coco3\build.ps1                  # writes both builds, their tapes and the disk
.\coco3\build.ps1 -Run             # opens the RGB build in XRoar
.\coco3\build.ps1 -Run -Composite  # opens the composite build
.\coco3\build.ps1 -Test            # checks both in XRoar against matrix_rain_coco3.c
```

The settings sit at the top of `matrix_rain_coco3.asm` and
`matrix_rain_coco3.c`, one block per build, and the two files have to
agree. They start from the PET 8032's (RGB) and 4032's (composite), with
trails capped at 23 rows.

## Running

Load a .prg file from the `pet` folder on a Commodore PET 8032 or emulator (such as [VICE xpet](https://vice-emu.sourceforge.io/)):

```
LOAD "*",8
RUN
```

The program includes a BASIC stub that automatically starts the machine code.
To run it in VICE, follow [Running in VICE](docs/running-in-vice.html).

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
