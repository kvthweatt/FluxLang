# Flux on Linux - Setup Guide

Flux on Linux needs Python (runs the compiler), LLVM (`llc`, optionally `opt`), the system linker (`ld`) with libc development files, and git. Clang is not required.

## Toolchain

1. **Python 3.10+** (3.12+ recommended) - runs `fxc.py`
2. **llvmlite 0.43+** - Python bindings used for code generation
3. **LLVM** - `llc` compiles IR to an object file; `opt` is used when present
4. **binutils + libc development files** - `ld` links the object file against libc
5. **Git**

## Quick Start

```bash
# Ubuntu / Debian
sudo apt update
sudo apt install python3 python3-pip python3-venv llvm binutils libc6-dev git

git clone https://github.com/kvthweatt/Flux
cd Flux

python3 -m venv .venv && source .venv/bin/activate
pip install "llvmlite>=0.43.0"

# Install the Python compiler (v1.5.4), which v2.0.8 does not ship
cp src/compiler/v1.5.4/core/* src/compiler/
cp src/compiler/v1.5.4/entrypoint/* .

# Bootstrap the compiler
python fxc.py fxc.fx

# From here on, use the native compiler
export FLUXC_SRCDIR="$PWD"
./build/fxc/fxc examples/helloworld.fx
./build/helloworld/helloworld
```

## Detailed Installation

### System packages

**Ubuntu/Debian**
```bash
sudo apt install python3 python3-pip python3-venv llvm binutils libc6-dev git
```

**Fedora/RHEL**
```bash
sudo dnf install python3 python3-pip llvm binutils glibc-devel git
```

**Arch**
```bash
sudo pacman -S python python-pip llvm binutils glibc git
```

### Python dependency

Recent distributions mark the system Python as externally managed, so a plain `pip install` is refused. Use a virtual environment (shown above) or `uv`:

```bash
cd Flux
uv sync
uv run python fxc.py examples/helloworld.fx
```

If you use the virtual environment, run `source .venv/bin/activate` in every new shell before compiling.

### Clone Flux

```bash
git clone https://github.com/kvthweatt/Flux
cd Flux
```

## Bootstrap the Compiler

Flux compiles itself. Version 2.0.8 does not ship the Python compiler, so copy it in from the bundled v1.5.4 sources first:

```bash
cp src/compiler/v1.5.4/core/* src/compiler/
cp src/compiler/v1.5.4/entrypoint/* .
```

Then bootstrap. The Python compiler builds the Flux-written compiler (`fxc.fx`) into a native binary:

```bash
python fxc.py fxc.fx
```

This takes a few minutes and produces `build/fxc/fxc`. The same command works on every platform.

**Use the native compiler from now on.** It is much faster than the Python compiler. It finds the standard library through `FLUXC_SRCDIR`, so set that to the repo root:

```bash
export FLUXC_SRCDIR=~/Flux          # add to ~/.bashrc to keep it
./build/fxc/fxc examples/helloworld.fx
./build/helloworld/helloworld
```

To check the result, recompile the compiler with itself:

```bash
./build/fxc/fxc fxc.fx -o fxc2
```

If you only want the native compiler, the Python files you copied in can be deleted afterwards, and only those files: the ones from `core/` and `entrypoint/`. Other Python files in the repo are still needed. Rebuild stage 1 with `python fxc.py fxc.fx` whenever the compiler sources need newer compiler features than your native binary has.

## Verification Steps

```bash
python3 --version                               # 3.10+
python3 -c "import llvmlite; print(llvmlite.__version__)"
llc --version                                   # LLVM 21+ is what the project targets
ld --version
git --version
python fxc.py tests/test.fx --log-level 3       # should produce build/test/test
```

If your distribution's `llc` is older than 21, check the version your distro offers (for example `llvm-21` on newer Ubuntu or the LLVM apt repository at apt.llvm.org) and make sure `llc` on your PATH is that one.

## Editor Support

Syntax definitions live in `editor-support/` (`sublime/`, `vscode/`, `notepad++/`). Copy the Sublime syntax into `~/.config/sublime-text/Packages/User/` and restart the editor. Any editor works.

## Common Issues

**`ModuleNotFoundError: llvmlite`** - the interpreter running `fxc.py` is not the one pip installed into. Activate the virtual environment, or run `python -m pip install "llvmlite>=0.43.0"` with the same `python` you use to compile.

**`error: externally-managed-environment`** - use a virtual environment or `uv`, see above.

**`llc: command not found`** - install LLVM (`sudo apt install llvm`). Some distributions install it as `llc-21`; add a symlink or put the versioned bin directory on your PATH.

**`ld: cannot find -lc`** - libc development files are missing. Install `libc6-dev` (Debian/Ubuntu), `glibc-devel` (Fedora) or `glibc` (Arch).

**Permission errors in `build/`** - make sure you own the repo directory: `sudo chown -R $USER:$USER ~/Flux`.

## Build Output

Everything for a program `name` goes in `build/name/`: the IR (`.ll`), the object file (`.o`) and the executable `name`.

```bash
python fxc.py program.fx --log-level 4 --log-timestamp    # show every stage and tool call
```

## Compilation Process

1. **Preprocess** - macros and includes
2. **Lex and parse** - tokens, then the AST
3. **Generate** - LLVM IR through llvmlite
4. **Assemble** - `llc` (and `opt` when available) produces an object file
5. **Link** - `ld` links against libc

## Next Steps

- `docs/learn_flux_intro.md`, then `docs/learn_flux_adept.md`
- `docs/Specs/language_specification.md`
- Examples in `examples/`, tests in `tests/`, standard library in `src/stdlib/`
- [Discord](https://discord.gg/RAHjbYuNUc), [GitHub](https://github.com/kvthweatt/Flux)