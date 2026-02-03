# Flux Compiler Logging System

The Flux compiler includes a comprehensive, configurable logging system that provides detailed insight into the compilation process. This document describes how to use and configure the logging system.

## Features

- **Multiple Log Levels**: 6 levels from silent to maximum verbosity
- **Component Filtering**: Show logs from specific compiler components only
- **Multiple Output Options**: Console, file, or both
- **Colored Output**: Colored console output with automatic terminal detection
- **Timestamps**: Optional timestamp inclusion for debugging
- **Environment Variables**: Configuration via environment variables
- **Legacy Compatibility**: Backwards compatible with old `-v` verbosity flags

## Log Levels

| Level | Name    | Description |
|-------|---------|-------------|
| 0     | SILENT  | No output except errors |
| 1     | ERROR   | Errors only |
| 2     | WARNING | Warnings and errors |
| 3     | INFO    | General information (default) |
| 4     | DEBUG   | Detailed debugging info |
| 5     | TRACE   | Maximum verbosity |

## Components

The Flux compiler logs messages from various components:

- **compiler**: General compiler initialization and configuration
- **lexer**: Lexical analysis (tokenization)
- **parser**: Parsing and AST generation  
- **codegen**: LLVM IR code generation
- **build**: Build environment and file operations
- **llc**: LLVM compiler invocation
- **as**: Assembler invocation
- **lld-link**: Linker invocation (Windows)
- **linker**: Final executable linking
- **cleanup**: Temporary file cleanup

## Usage Examples

### Basic Usage

```bash
# Compile with default logging (INFO level)
python3 flux_compiler.py hello.fx

# Compile with DEBUG level logging
python3 flux_compiler.py hello.fx --log-level 4

# Compile with maximum verbosity
python3 flux_compiler.py hello.fx --log-level 5
```

### Advanced Configuration

```bash
# Enable timestamps and write to log file
python3 flux_compiler.py hello.fx --log-timestamp --log-file compilation.log

# Show only lexer and parser logs
python3 flux_compiler.py hello.fx --log-filter lexer,parser --log-level 4

# Disable colors (useful for CI/CD)
python3 flux_compiler.py hello.fx --log-no-color --log-level 3
```

### Environment Variables

```bash
# Set default log level
export FLUX_LOG_LEVEL=4

# Enable timestamps by default
export FLUX_LOG_TIMESTAMP=true

# Set default log file
export FLUX_LOG_FILE="logs/flux.log"

# Filter to specific components
export FLUX_LOG_COMPONENTS="compiler,codegen,linker"

# Disable colors
export FLUX_LOG_NO_COLOR=true

# Now compile with these settings
python3 flux_compiler.py hello.fx
```

### Legacy Compatibility

The old `-v` verbosity flags are still supported:

```bash
# Legacy: Show tokens (maps to TRACE level with lexer filter)
python3 flux_compiler.py hello.fx -v 0

# Legacy: Show AST (maps to DEBUG level with parser filter)
python3 flux_compiler.py hello.fx -v 1

# Legacy: Show LLVM IR (maps to TRACE level with codegen filter)
python3 flux_compiler.py hello.fx -v 2

# Legacy: Show assembly (maps to TRACE level with llc filter)
python3 flux_compiler.py hello.fx -v 3

# Legacy: Show everything (maps to INFO level with no filter)
python3 flux_compiler.py hello.fx -v 4
```

## Command Line Options

| Option | Argument | Description |
|--------|----------|-------------|
| `--log-level` | `0-5` | Set logging level |
| `--log-file` | `path` | Write logs to file |
| `--log-timestamp` | - | Include timestamps |
| `--log-no-color` | - | Disable colored output |
| `--log-filter` | `components` | Filter by components (comma-separated) |

## Configuration Files

You can create JSON configuration files for consistent logging settings:

```json
{
  "logging": {
    "level": 4,
    "timestamp": true,
    "colors": true,
    "log_file": "logs/flux_debug.log",
    "component_filter": ["lexer", "parser", "codegen"]
  }
}
```

## Sample Output

### INFO Level (Default)
```
==================================================
  Compiling Flux file: hello.fx
==================================================
► Reading source file
► Lexical analysis
► Parsing
► LLVM IR code generation
► Compiling to object file (Windows)
► Linking executable: hello
✓ Compilation completed: hello
```

### DEBUG Level with Timestamps
```
[14:32:15.123] [INFO] [compiler] ► Reading source file
[14:32:15.124] [DEBUG] [compiler] Read 156 characters from hello.fx
[14:32:15.125] [INFO] [lexer] ► Lexical analysis
[14:32:15.126] [DEBUG] [lexer] Generated 23 tokens
[14:32:15.127] [INFO] [parser] ► Parsing
[14:32:15.128] [DEBUG] [parser] AST generation completed
```

### TRACE Level with Component Filter
```
[TRACE] [lexer] Generated Tokens:
  [0] Token(IMPORT, 'import')
  [1] Token(STRING, '"standard.fx"')
  [2] Token(SEMICOLON, ';')
  [3] Token(DEF, 'def')
  ...

[TRACE] [codegen] Generated LLVM IR:
  ; ModuleID = 'flux_module'
  source_filename = "flux_module"
  
  define i32 @main() {
  entry:
    ret i32 0
  }
```

## Programming Interface

For advanced users, the logging system can be used programmatically:

```python
from flux_logger import FluxLogger, LogLevel

# Create custom logger
logger = FluxLogger(
    level=LogLevel.DEBUG,
    timestamp=True,
    log_file="debug.log",
    component_filter=["lexer", "parser"]
)

# Use logger
logger.info("Starting compilation", "compiler")
logger.debug("Generated AST", "parser")
logger.log_data(LogLevel.TRACE, "Tokens", tokens, "lexer")

# Create compiler with custom logger
compiler = FluxCompiler(logger=logger)
```

## Best Practices

1. **Development**: Use DEBUG or TRACE level with component filtering
2. **Production**: Use ERROR or WARNING level with log files
3. **CI/CD**: Disable colors and use structured logging
4. **Debugging**: Use TRACE level with timestamps and log files
5. **Performance**: Lower log levels reduce overhead

## Troubleshooting

### Common Issues

1. **No log output**: Check log level - might be set to SILENT (0)
2. **Missing component logs**: Check component filter settings
3. **Colors not working**: Terminal might not support ANSI colors
4. **Log file not created**: Check directory permissions and path

### Debug Settings

For maximum debugging information:

```bash
python3 flux_compiler.py your_file.fx \
  --log-level 5 \
  --log-timestamp \
  --log-file debug.log
```

## Migration from Old System

The old verbosity system is deprecated but still works:

| Old | New Equivalent |
|-----|----------------|
| `-v 0` | `--log-level 5 --log-filter lexer` |
| `-v 1` | `--log-level 4 --log-filter parser` |
| `-v 2` | `--log-level 5 --log-filter codegen` |
| `-v 3` | `--log-level 5 --log-filter llc` |
| `-v 4` | `--log-level 4` |

We recommend migrating to the new system for better control and features.
