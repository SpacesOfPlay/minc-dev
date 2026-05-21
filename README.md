# minc — developer distribution

minc is a minimal C replacement for building native software. It cross-compiles
directly to native executables for x64 Windows (PE), x64/ARM64 Linux (ELF),
ARM64 macOS (Mach-O), ARM64 iOS, ARM64 Android, and WebAssembly — no assembler,
linker, or runtime required. The compiler self-compiles in ~1450 KB.

This repository holds the compiler binary release as platform-specific zip
files attached to GitHub Releases.

See `LANGUAGE.md` for the language reference. An online compiler playground 
and more info is available at [minc.dev](https://minc.dev).

## Release builds

[Releases page](https://github.com/SpacesOfPlay/minc-dev/releases/latest):

| Zip | Target |
| --- | --- |
| `minc-win-x64.zip`      | Windows 10/11, x86-64 |
| `minc-macos-arm64.zip`  | macOS, Apple Silicon |
| `minc-linux-x64.zip`    | Linux, x86-64 |
| `minc-linux-arm64.zip`  | Linux, ARM64 |


```bash
# macOS / Linux
unzip minc-macos-arm64.zip
cd minc-macos-arm64
# Run this to verify compiler is executable, also adds minc to PATH.
# Must be source for PATH update to work directly.
source setup.sh

# Windows (PowerShell)
Expand-Archive minc-win-x64.zip -DestinationPath .
cd minc-win-x64
# Run this to add minc.exe to PATH
.\setup.ps1
```

To undo later: `source setup.sh --remove` or `.\setup.ps1 -Remove`

On macOS, `setup.sh` also strips the `com.apple.quarantine` xattr
that browsers attach to downloaded files. Without it, Gatekeeper
blocks the first `minc` invocation with "cannot be opened because
the developer cannot be verified".

You can also run the compiler directly without with `./minc` or
`.\minc.exe`. Adding to PATH on Windows allows you to run `minc` 
(without .exe).

## Try it

After setup, `minc` is on your `PATH`:

```bash
minc run examples/mandelbrot.mc   # compile + run in one step
minc run examples/hello.mc
minc run examples/sokol_cube.mc   # sokol-app GPU demo

minc examples/raytracer.mc -o rt  # compile only
./rt                              # run separately
```

`minc --help` lists the flags (targets, link, output path, debug
info). See [`LANGUAGE.md`](LANGUAGE.md) for the language reference.

The bundled `build.sh` / `build.ps1` driver handles paths that need
extra bundling — iOS Simulator, iOS device deploy, Android APK
packaging:

```bash
./build.sh ios-sim sokol_cube      # build & launch in iOS Simulator
./build.sh ios sokol_cube          # sign & install on a paired iPhone
./build.sh android                 # build + install APK on connected device
./build.sh bench                   # benchmark suite (vs host clang/gcc/MSVC -O2)
```

`build.sh --help` lists the subcommands.


## What's in the zip

```
minc                  # the compiler binary
minc-lsp              # language server for editor integration
lib/                  # standard library (.mc sources)
examples/             # ready-to-build apps (hello, raytracer, chip8, sokol_cube, …)
bench/                # benchmark suite (.mc + matched .c reference)
SETUP.md              # platform setup notes (iOS, Android, WASM)
editor/               # VS Code extension (.vsix) with syntax + LSP wiring
build.sh / build.ps1  # driver script
setup.sh / setup.ps1  # first-run housekeeping
LANGUAGE.md           # full language reference
AGENTS.md             # cross-tool LLM guidance
LICENSE.md            # license terms
```

## Editor support

Install the bundled VS Code extension:

```bash
code --install-extension editor/minc-syntax-*.vsix
```

## Platform-specific extras

`SETUP.md` covers iOS Simulator, iOS device deploy (provisioning
profile + signing identity), Android (NDK + adb), and WASM.

## Licensing

See [`LICENSE.md`](LICENSE.md). Summary:

- Free for individuals, small companies, students, and evaluation.
- Annual revenue ≥ €100,000 — commercial license required.

Contact: <support@minc.dev>.

## Issues and feedback

Use the [issue tracker](https://github.com/SpacesOfPlay/minc-dev/issues)
for bug reports and feature requests. The bug report template asks for
the minc version (`minc --version`), platform, and a minimal repro.
