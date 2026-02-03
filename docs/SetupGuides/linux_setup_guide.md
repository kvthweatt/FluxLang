# Flux on Linux - Setup Guide

This guide walks you through setting up a clean, effective Flux development environment on Linux. We'll use standard tools that integrate well with the Unix philosophy: Sublime Text for editing, your terminal for compilation, and LLVM from your package manager.

## Toolchain Overview

Flux on Linux requires:

1. **Python 3.8+** - Runs the Flux compiler
2. **LLVM/Clang** - Compiles LLVM IR to native code and handles linking
3. **llvmlite** - Python bindings to LLVM for code generation
4. **Git** - To clone the Flux repository
5. **Sublime Text** - Your code editor (optional but recommended)

## Quick Start

For the impatient, here's the complete setup:

```bash
# Install toolchain
sudo apt update
sudo apt install python3 python3-pip llvm clang git

# Install Python dependencies
pip3 install llvmlite==0.41.0 dataclasses

# Clone Flux
git clone https://github.com/kvthweatt/FluxLang.git
cd FluxLang

# Test compilation
python3 fc.py tests/test.fx --log-level 3

# Install Sublime Text (optional)
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg
echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
sudo apt update
sudo apt install sublime-text
```

Done! Skip to [Verification Steps](#verification-steps) to confirm everything works.

## Detailed Installation

### System Packages

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install python3 python3-pip llvm clang git
```

**Fedora/RHEL:**
```bash
sudo dnf install python3 python3-pip llvm clang git
```

**Arch Linux:**
```bash
sudo pacman -S python python-pip llvm clang git
```

### Python Dependencies

Install llvmlite and dataclasses:
```bash
pip3 install llvmlite==0.41.0 dataclasses
```

**Note:** If you encounter permissions issues, either:
- Use `--user` flag: `pip3 install --user llvmlite==0.41.0`
- Or use a virtual environment (see [Advanced Configuration](#virtual-environments))

### Sublime Text

**Ubuntu/Debian:**
```bash
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg
echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
sudo apt update
sudo apt install sublime-text
```

**Fedora:**
```bash
sudo rpm -v --import https://download.sublimetext.com/sublimehq-rpm-pub.gpg
sudo dnf config-manager --add-repo https://download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo
sudo dnf install sublime-text
```

**Arch Linux:**
```bash
# Sublime Text is in AUR
yay -S sublime-text-4
# or
paru -S sublime-text-4
```

**Alternative editors:** Any text editor works fine - VS Code, Vim, Emacs, Kate, Gedit, nano. Sublime Text is just our recommendation for a clean, fast experience.

### Clone Flux

```bash
git clone https://github.com/kvthweatt/FluxLang Flux
cd Flux
```

## Verification Steps

### 1. Check Python
```bash
python3 --version                           # Should show 3.8+
python3 -c "import llvmlite; print('llvmlite OK')"
```

### 2. Check LLVM/Clang
```bash
clang --version                             # Should show LLVM version
llvm-config --version                       # Should match clang version
```

### 3. Check Git
```bash
git --version                               # Any recent version is fine
```

### 4. Test Flux Compilation
```bash
cd Flux
python3 fc.py tests/test.fx --log-level 3
```

You should see compilation succeed and an executable created.

## Development Workflow

### Basic Compilation

Navigate to your Flux directory and compile a program:
```bash
cd ~/Flux
python3 fc.py examples/hello.fx
./hello
```

### Using Sublime Text

**Open a Flux file:**
```bash
subl examples/hello.fx
```

**Open entire project:**
```bash
subl ~/Flux
```

**Build system (optional):**
Create a Flux build system in Sublime Text:
1. Tools → Build System → New Build System
2. Paste this configuration:

```json
{
    "cmd": ["python3", "fc.py", "$file"],
    "working_dir": "$folder",
    "selector": "source.flux",
    "file_regex": "^(.+?):(\\d+):(\\d+): (.*)$"
}
```

3. Save as `Flux.sublime-build`
4. Now you can press `Ctrl+B` to compile the current file

### Syntax Highlighting (Optional)

Create a basic syntax file for Flux in Sublime Text:

1. Create `~/.config/sublime-text/Packages/User/Flux.sublime-syntax`
2. Add basic syntax rules:

```yaml
%YAML 1.2
---
name: Flux
file_extensions: [fx]
scope: source.flux

contexts:
  main:
    - match: '\b(def|object|struct|if|else|while|for|return|import|using|extern|compt|unsigned|data)\b'
      scope: keyword.control.flux
    
    - match: '\b(int|float|byte|bool|void|this)\b'
      scope: storage.type.flux
    
    - match: '//.*$'
      scope: comment.line.flux
    
    - match: '"'
      scope: punctuation.definition.string.begin.flux
      push: string
    
    - match: '\b\d+\b'
      scope: constant.numeric.flux

  string:
    - meta_scope: string.quoted.double.flux
    - match: '"'
      scope: punctuation.definition.string.end.flux
      pop: true
```

Restart Sublime Text, and `.fx` files will have basic highlighting.

## Common Issues and Solutions

### "Module 'llvmlite' not found"
**Cause:** llvmlite not installed or not in Python path.

**Solutions:**
```bash
# Try installing with --user
pip3 install --user llvmlite==0.41.0

# Or check if it's installed
pip3 list | grep llvmlite

# Ensure you're using the right Python
which python3
```

### "Command 'clang' not found"
**Cause:** LLVM not installed.

**Solutions:**
```bash
# Reinstall LLVM
sudo apt install llvm clang

# Verify installation
which clang
clang --version
```

### Permission Errors During Compilation
**Causes:** No write permissions in Flux directory, still compiling, executable open in debugger.

**Solutions:**
```bash
# Check permissions
ls -la

# Fix if needed
sudo chown -R $USER:$USER ~/FluxLang
```
Or just wait and try again.

## Advanced Configuration
### Virtual Environments

For isolated Python dependencies:

```bash
# Install venv if needed
sudo apt install python3-venv

# Create virtual environment
cd ~/FluxLang
python3 -m venv flux-env

# Activate it
source flux-env/bin/activate

# Install dependencies
pip install llvmlite==0.41.0 dataclasses

# Now compile normally
python fc.py examples/hello.fx

# Deactivate when done
deactivate
```

Add to your `~/.bashrc` for convenience:
```bash
alias flux-dev='cd ~/FluxLang && source flux-env/bin/activate'
```

### Shell Aliases

Add these to `~/.bashrc` or `~/.zshrc`:

```bash
# Quick flux compilation
alias fluxc='python3 ~/FluxLang/fc.py'
```

Apply changes:
```bash
source ~/.bashrc
```

Now you can:
```bash
fluxc myprogram.fx       # Compile
```

### Build Directory

Flux creates temporary files in `build/`:
- `program.ll` - LLVM IR code (human-readable)
- `program.o` - Object file
- `program` - Final executable (Linux)

Inspect generated IR:
```bash
python3 fc.py program.fx
cat build/program.ll
```

### Debugging Compilation

Enable detailed logging:
```bash
python3 fc.py program.fx --log-level 4 --log-timestamp
```

This shows:
- Lexing and parsing stages
- LLVM IR generation
- Clang invocation and arguments
- Linking process

## Understanding the Compilation Process

When you run `python3 fc.py program.fx`, Flux:
1. **Preprocesses** - Handles macros, strips comments and empty lines, output to `build\tmp.fx`
2. **Lexes** - Breaks source code into tokens
3. **Parses** - Builds an Abstract Syntax Tree (AST)
4. **Generates Code** - Creates LLVM Intermediate Representation (IR)
5. **Compiles** - Uses Clang to convert IR to object code
6. **Links** - Creates final executable (Clang handles this on Linux)

Unlike Windows, Linux doesn't need a separate Visual Studio toolchain - Clang handles both compilation and linking using system libraries.

## Next Steps

Now that your environment is ready:

1. **Learn the language:**
   - Read `docs/learn_flux_intro.md` for a tutorial
   - Study `docs/lang_spec_reduced.md` for core features
   - Reference `docs/lang_spec_full.md` for complete details

2. **Try examples:**
   ```bash
   cd examples
   python3 ../fc.py hello.fx && ./hello
   python3 ../fc.py bit_fields.fx && ./bit_fields
   ```

3. **Write your first program:**
   ```bash
   subl myprogram.fx
   # Write some Flux code
   python3 fc.py myprogram.fx
   ./myprogram
   ```

4. **Explore the standard library:**
   ```bash
   ls src/stdlib/
   ```

5. **Join the community:**
   - [Discord](https://discord.gg/RAHjbYuNUc) - Ask questions, share projects
   - [GitHub](https://github.com/kvthweatt/FluxLang) - Report issues, contribute

## This manual setup helps you:
- Helps you understand how to compile Flux programs
- Use familiar, standard Linux tools
- Keep your development environment simple and transparent
- Debug issues effectively when they arise

Linux's philosophy of small, composable tools aligns perfectly with Flux's design. You're using standard system packages, a straightforward Python script, and LLVM - the same toolchain that powers production languages.

As Flux matures toward self-hosting, we'll eventually provide a Flux-written installer - demonstrating the language's systems programming capabilities while maintaining this same transparency.

Happy Flux development!