# minc — developer distribution

minc is a minimal C replacement for building native software. It compiles directly to
native executables for x64 Windows (PE), x64/ARM64 Linux (ELF), ARM64 macOS (Mach-O),
ARM64 iOS, ARM64 Android (.so), and WebAssembly.

This repository holds the compiler binary release as platform-specific zip files
attached to GitHub Releases.

See `LANGUAGE.md` for the language reference. An online compiler playground 
and more info is available at [minc.dev](https://minc.dev).


## Setup

Easiest way to install minc:

```
# Windows
powershell -c "irm minc.dev/install.ps1 | iex"

# macOS / Linux
curl -fsSL https://minc.dev/install | bash
```

Then clone the minc-samples repo and run any example straight from the root:

```
git clone https://github.com/SpacesOfPlay/minc-samples
cd minc-samples
minc run hello.mc
minc run sokol_cube.mc
```

## Licensing

See [`LICENSE.md`](LICENSE.md). Summary:

- Free for individuals, small companies, students, and evaluation.
- Annual revenue ≥ €100,000 — commercial license required.

Contact: <support@minc.dev>.

## Issues and feedback

Use the [issue tracker](https://github.com/SpacesOfPlay/minc-dev/issues)
for bug reports and feature requests. The bug report template asks for
the minc version (`minc --version`), platform, and a minimal repro.
