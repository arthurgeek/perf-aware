# perf-aware

Homework for [Casey Muratori's Performance-Aware Programming course](https://www.computerenhance.com/), written in [Odin](https://odin-lang.org/).

## Part 1: 8086 decoder

The [Nix](https://nixos.org/) dev shell provides the toolchain (odin, nasm):

```sh
nix develop
cd part1
./fetch-listings.sh
odin build . -out:build/sim8086
./check.sh
```

`sim8086` disassembles an 8086 binary. `check.sh` round-trips every listing through nasm and compares the resulting binaries.

The course listings are (C) Molly Rocket, Inc. and are not part of this repository; `fetch-listings.sh` downloads them from the official [computer_enhance](https://github.com/cmuratori/computer_enhance) repository.

## License

MIT. Course listings are excluded and remain under [their own license](https://mollyrocket.com/celicense.txt).
