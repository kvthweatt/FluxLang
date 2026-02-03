# Flux Compiler Architecture

## Compilation Pipeline

```
.fx source → Preprocessor → Lexer → Parser → AST → IR Generator → .ll → Clang → .o → Linker → Binary
```

---

## Components

### Preprocessor (`fpreprocess.py`)

- Resolves `#import`, `#ifdef`, `#ifndef`, `#else`, `#endif`
- Expands `#def` macros (value 0 = undefined)
- Searches: relative path, `src/stdlib/`, custom includes
- Output: `build/tmp.fx`

### Lexer (`flexer.py`)

- Tokenizes preprocessed source
- Outputs token stream with type, value, position

### Parser (`fparser.py`)

- Recursive descent parser
- Operator precedence climbing
- Outputs AST

### AST (`fast.py`)

- Node types: declarations, statements, expressions, type annotations
- Type system (`ftypesys.py`): resolution, validation, bit-precise types, pointers, arrays

### IR Generator (`fc.py` - `FluxCompiler`)

**Methods:**
- `compile_file()` → native executable
- `compile_library()` → static library (.a/.lib)
- `compile_dos(com_file=True/False)` → DOS .COM or .EXE
- `compile_bootloader()` → 512-byte boot sector

**Process:**
1. Initialize LLVM module
2. Map types (int→i32/i64, byte→i8, bool→i1, data{N}→iN)
3. Forward-declare functions/objects
4. Generate function body IR
5. Optimize
6. Write `build/<program>/<program>.ll`

### Backend Toolchain

**Native:**
```bash
clang -c build/program.ll -o build/program.o
clang build/program.o -o program       # or program.exe
```

**Library:**
```bash
ar rcs program.a build/program.o       # Unix
lib /OUT:program.lib build/program.o   # Windows
```

**DOS:**
- 16-bit real mode code
- COM: flat binary at 0x0100, max 64KB
- EXE: MZ header, relocations, unlimited size

**Bootloader:**
- 16-bit real mode
- Exactly 512 bytes
- Boot signature 0x55 0xAA at offset 510-511

---

## Directory Structure

```
build/
  tmp.fx                 # Preprocessor output
  <program>/
    <program>.ll         # LLVM IR
    <program>.o          # Object file
    <program>            # Binary

config/
  flux_configuration.cfg # INI format

src/
  compiler/
    fc.py                # IR generation + main compiler
    fpreprocess.py       # Preprocessor
    flexer.py            # Lexer
    fparser.py           # Parser
    fast.py              # AST nodes
    ftypesys.py          # Type system
    flogger.py           # Logging
    fconfig.py           # Config loader
    futilities.py        # Utilities
  stdlib/
    runtime/

fc.py                    # Entrypoint
```

---

## Configuration

### File (`config/flux_configuration.cfg`)

```ini
[compiler]
target = native          # native, dos, bootloader
optimize = true
debug_symbols = false

[paths]
stdlib = src/stdlib
include = /custom/path

[logging]
level = 3                # 0-5
color = true
timestamp = false
```

### CLI

```bash
python fc.py <input.fx> [options]

-o <name>                # Output name
-v <0-5>                 # Legacy verbosity
-dos                     # Target DOS
-com                     # DOS COM file (requires -dos)
--library                # Static library

--log-level <0-5>        # 0=silent, 1=error, 2=warn, 3=info, 4=debug, 5=trace
--log-file <path>        # Write to file
--log-timestamp          # Add timestamps
--log-no-color           # Disable colors
--log-filter <comp>      # lexer,parser,compiler,build,preprocessor
```

### Environment Variables

- `FLUX_LOG_LEVEL`
- `FLUX_LOG_FILE`
- `FLUX_LOG_TIMESTAMP`
- `FLUX_LOG_NO_COLOR`
- `FLUX_LOG_COMPONENTS`

---

## Logging (`flogger.py`)

| Level | Name    | Output          |
|-------|---------|-----------------|
| 0     | SILENT  | Nothing         |
| 1     | ERROR   | Failures        |
| 2     | WARNING | Warnings        |
| 3     | INFO    | Progress        |
| 4     | DEBUG   | Details         |
| 5     | TRACE   | Everything      |

**Components:** lexer, parser, compiler, build, preprocessor

**Format:**
```
[INFO] Compiling program.fx
[2026-02-03 14:32:15] [DEBUG] Lexer: 1523 tokens
```

**Colors:** ERROR=red, WARNING=yellow, INFO=green, DEBUG=cyan, TRACE=gray

---

## Error Handling

### Frontend

**Preprocessor:** file not found, circular imports, undefined macro  
**Lexer:** invalid character, malformed literal, unterminated string  
**Parser:** unexpected token, syntax error, mismatched delimiters  
**Type System:** type mismatch, invalid conversion, undefined type

### Backend

**IR Generation:** LLVM failure, invalid operation, undefined reference  
**Clang:** invalid IR, unsupported target  
**Linker:** undefined symbol, multiple definitions, missing library

**Format:** `[ERROR] <file>:<line>:<col>: <message>`

---

## Utilities

**`futilities.py`:** File I/O, path manipulation, string processing, error formatting  
**`fconfig.py`:** Config parsing, CLI parsing, merging (CLI > env > file > defaults)

---

## Code Generation

### Functions

1. Allocate LLVM function
2. Create entry basic block
3. Generate parameters
4. Generate body IR
5. Generate return
6. Verify

**Name mangling:** `<qualified_names>__<name>__<param_count>__<params__params__...>__ret_<return_type>`  
(or no mangling with `!!` operator)

### Objects

**Memory layout:** struct with fields  
**Methods:** functions with implicit `this` parameter  
**Dispatch:** static (direct call)

### Expressions

**Binary ops:** generate left, generate right, generate operation  
**Calls:** generate args, lookup function, generate call  
**Member access:** GEP instruction for field offset

### Control Flow

**If:** condition_block → then_block / else_block → merge_block  
**While:** condition_block → body_block → condition_block (loop) or exit_block  
**For:** init → condition_block → body_block → increment_block → condition_block (loop) or exit_block

---

## Platform Linking

**Windows:** LLVM `lld-link.exe`, fallback to Clang  
**Linux:** `lld`, fallback to Clang  
**macOS:** ld64 via Clang driver

**System libraries auto-linked:**
- Windows: Windows SDK, UCRT
- Linux: glibc
- macOS: macOS SDK