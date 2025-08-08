# Flux on Windows - Setup Guide

This guide helps you understand and configure your Windows development environment for Flux. Rather than providing automated scripts, we believe in helping you understand each component and make informed choices about your setup.

## Understanding the Toolchain

Flux compilation on Windows involves several components working together:

1. **Python 3.8+** - Runs the Flux compiler itself
2. **LLVM/Clang** - Compiles LLVM IR to object files
3. **Visual Studio/MSVC** - Provides the linker and Windows SDK
4. **llvmlite** - Python bindings to LLVM for code generation

## Component Installation

### Python 3.8+
- Download from [python.org](https://www.python.org/downloads/)
- Ensure it's added to your PATH during installation
- Verify: `python --version`

### LLVM/Clang
Choose one of these methods:

**Option 1: Official LLVM (Recommended)**
```powershell
winget install LLVM.LLVM
```

**Option 2: Manual Installation**
- Download from [LLVM Releases](https://github.com/llvm/llvm-project/releases)
- Install to a standard location like `C:\Program Files\LLVM`
- Add `C:\Program Files\LLVM\bin` to your PATH

**Option 3: Package Manager**
```powershell
# If you use Chocolatey
choco install llvm

# If you use Scoop
scoop install llvm
```

### Visual Studio
Visual Studio provides the MSVC toolchain that Clang uses for linking on Windows.

**Visual Studio Community (Free):**
- Download from [Visual Studio Downloads](https://visualstudio.microsoft.com/downloads/)
- During installation, select **"Desktop development with C++"** workload
- This includes MSVC compiler, Windows SDK, and CMake tools

**Visual Studio Build Tools (Minimal):**
If you prefer a lighter installation:
- Download "Build Tools for Visual Studio"
- Install the "Visual C++ build tools" package

### Python Dependencies
```powershell
pip install llvmlite==0.41.0 dataclasses
```

## Verification Steps

### 1. Check Python
```powershell
python --version                    # Should show 3.8+
python -c "import llvmlite; print('llvmlite OK')"
```

### 2. Check LLVM/Clang
```powershell
clang --version                     # Should show LLVM version
clang --print-targets | findstr x86_64  # Should show x86_64 targets
```

### 3. Check Visual Studio Tools
Open **Developer Command Prompt for VS** or **Developer PowerShell for VS**:
```powershell
cl                                  # Should show MSVC compiler
link                               # Should show Microsoft linker
```

### 4. Test Flux Compilation
From a **Visual Studio Developer Command Prompt**:
```powershell
cd C:\path\to\Flux
python flux_compiler.py tests\test.fx --log-level 3
```

## Common Issues and Solutions

### "Clang: warning: unable to find a Visual Studio installation"
**Cause:** Clang can't locate MSVC tools for linking.

**Solutions:**
1. Run Flux from a **Visual Studio Developer Command Prompt**
2. Ensure Visual Studio includes the "Desktop development with C++" workload
3. Verify environment variables are set: `echo $env:VCINSTALLDIR`

### "Command 'clang' not found"
**Cause:** LLVM not in PATH or not installed.

**Solutions:**
1. Reinstall LLVM and ensure PATH is updated
2. Use full path: `C:\Program Files\LLVM\bin\clang.exe --version`
3. Restart your terminal after installation

### "Module 'llvmlite' not found"
**Cause:** Python dependencies not installed.

**Solutions:**
1. Install with: `pip install llvmlite==0.41.0`
2. If using multiple Python versions, ensure you're using the right pip
3. Try: `python -m pip install llvmlite==0.41.0`

### Permission Errors
**Cause:** Insufficient permissions for installation or compilation.

**Solutions:**
1. Run terminals as Administrator when installing tools
2. Ensure you have write permissions to your Flux directory
3. Check Windows Defender or antivirus isn't blocking operations

## Development Workflow

### Recommended Terminal Setup
1. Use **Visual Studio Developer Command Prompt** or **Developer PowerShell**
2. These terminals automatically configure environment variables for MSVC tools
3. Available through: Start Menu → Visual Studio → Developer Command Prompt

### Environment Variables
When properly configured, you should see these environment variables:
- `VCINSTALLDIR` - Points to Visual Studio installation
- `WindowsSdkDir` - Points to Windows SDK
- `PATH` - Includes LLVM, Python, and MSVC tools

### Compilation Process Understanding
When you run `python flux_compiler.py program.fx`, Flux:
1. **Lexes** your Flux source code into tokens
2. **Parses** tokens into an Abstract Syntax Tree (AST)
3. **Generates** LLVM Intermediate Representation (IR)
4. **Compiles** IR to object file using Clang
5. **Links** object file to executable using MSVC linker

## Advanced Configuration

### Custom LLVM Installation
If you have LLVM installed in a non-standard location, Flux will automatically search:
- `C:\Program Files\LLVM\bin\clang.exe`
- `clang.exe` (if in PATH)
- `clang` (Unix-style name)

### Build Directory
Flux creates temporary files in `build/` directory:
- `program.ll` - LLVM IR code
- `program.obj` - Object file
- `program.exe` - Final executable (Windows)

### Debugging Compilation Issues
Enable detailed logging to understand what's happening:
```powershell
python flux_compiler.py program.fx --log-level 4 --log-timestamp
```

This shows exactly which tools are being called and their output.

## Next Steps

Once your environment is working:
1. Try compiling the examples in `examples/`
2. Read the language specification in `docs/`
3. Explore the standard library in `src/stdlib/`
4. Write your first Flux program!

## Philosophy

This manual setup process helps you:
- Understand each component of the toolchain
- Make informed choices about your development environment
- Debug issues more effectively
- Appreciate how modern compilers work

As Flux matures, we'll eventually provide a self-hosted installer written in Flux itself - demonstrating the language's capabilities while maintaining transparency about what's being installed.

Happy Flux development! 🚀
