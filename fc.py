#!/usr/bin/env python3
"""
Flux Compiler Entrypoint

Copyright (C) 2026 Karac Thweatt

Contributors:

    Piotr Maciej Bednarski


USAGE:
    python fc.py filename.fx
    
    Includes the standard library into the available paths.
    
    Outputs to the same folder with filename.exe (or just filename on *nix systems)
    

This language is in active development. There are known and unknown issues.

Please report any issues to kvthweatt@gmail.com or create an issue on the GitHub page.
"""

import sys
import os
from pathlib import Path
#from fconfig import *

# Add src/compiler and src/stdlib to Python path
sys.path.insert(0, str(Path(__file__).parent / "src" / "compiler"))
sys.path.insert(0, str(Path(__file__).parent / "src" / "stdlib"))
sys.path.insert(0, str(Path(__file__).parent / "src" / "stdlib" / "runtime"))

# Import compiler components
from fc import FluxCompiler # type: ignore
from fc import config

def main():
    if len(sys.argv) < 2:
        print("Flux Language Compiler")
        print("Usage: python3 fc.py <input.fx> [options]\n")
        print("Basic Options:")
        print("  -o <output>         Output binary name")
        print("  -v <level>          Legacy verbosity level (0-5)")
        print("  --library           Compile as static library instead of executable")
        print("")
        print("Advanced Logging Options:")
        print("  --log-level <n>     Logging level: 0=silent, 1=error, 2=warning, 3=info, 4=debug, 5=trace")
        print("  --log-file <path>   Write logs to file")
        print("  --log-timestamp     Include timestamps in log output")
        print("  --log-no-color      Disable colored output")
        print("  --log-filter <comp> Only show logs from specific components (comma-separated)")
        print("                      Examples: lexer,parser or compiler,build")
        print("")
        print("Environment Variables:")
        print("  FLUX_LOG_LEVEL      Set default log level (0-5)")
        print("  FLUX_LOG_FILE       Set default log file path")
        print("  FLUX_LOG_TIMESTAMP  Enable timestamps (1/true/yes)")
        print("  FLUX_LOG_NO_COLOR   Disable colors (1/true/yes)")
        print("  FLUX_LOG_COMPONENTS Filter components (comma-separated)")
        print("")
        print("Examples:")
        print("  python3 fc.py hello.fx")
        print("  python3 fc.py hello.fx -o hello --log-level 4")
        print("  python3 fc.py hello.fx --log-filter lexer,parser --log-timestamp")
        sys.exit(1)
    
    args = sys.argv[1:]  # Skip script name
    input_file = None
    output_bin = None
    verbosity = None
    compile_as_library = False
    logger_config = {}
    
    i = 0
    while i < len(args):
        arg = args[i]
        
        # Check for flags
        if arg == "-v" and i + 1 < len(args):
            verbosity = int(args[i + 1])
            i += 2
        elif arg == "-o" and i + 1 < len(args):
            output_bin = args[i + 1]
            i += 2
        elif arg == "--library":
            compile_as_library = True
            i += 1
        elif arg == "--log-level" and i + 1 < len(args):
            logger_config['level'] = int(args[i + 1])
            i += 2
        elif arg == "--log-file" and i + 1 < len(args):
            logger_config['log_file'] = args[i + 1]
            i += 2
        elif arg == "--log-timestamp":
            logger_config['timestamp'] = True
            i += 1
        elif arg == "--log-no-color":
            logger_config['colors'] = False
            i += 1
        elif arg == "--log-filter" and i + 1 < len(args):
            components = [c.strip() for c in args[i + 1].split(',')]
            logger_config['component_filter'] = components
            i += 2
        elif arg.startswith("-"):
            print(f"Warning: Unknown argument '{arg}'")
            i += 1
        else:
            # Positional argument - should be input file
            if input_file is None:
                input_file = arg
                # Fix Windows path if needed
                if "\\" in input_file and "\\\\" not in input_file:
                    input_file = input_file.replace("\\", "\\")
            else:
                print(f"Warning: Unexpected argument '{arg}'")
            i += 1
    
    # Create compiler instance with advanced logging
    try:
        compiler = FluxCompiler(verbosity=verbosity, **logger_config)
        
        # Show configuration if debug level or higher
        if logger_config.get('level', 0) >= 4:
            print(f"Flux Compiler Configuration:")
            print(f"  Input file: {input_file}")
            print(f"  Output: {output_bin or 'auto-detected'}")
            print(f"  Mode: {'Library' if compile_as_library else 'Executable'}")
            print(f"  Log level: {logger_config.get('level', 'default')}")
            if logger_config.get('log_file'):
                print(f"  Log file: {logger_config['log_file']}")
            if logger_config.get('component_filter'):
                print(f"  Component filter: {', '.join(logger_config['component_filter'])}")
        
        binary_path = ""
        
        # Compile the file
        if config['target'] == "bootloader":
            binary_path = compiler.compile_bootloader(input_file, output_bin)
            return
        if compile_as_library:
            binary_path = compiler.compile_library(input_file, output_bin)
        else:
            binary_path = compiler.compile_file(input_file, output_bin)
        
        # Final success message
        if logger_config.get('level', 0) < 3:
            mode = "library" if compile_as_library else "executable"
            print(f"✓ Compilation successful: {binary_path} ({mode})")
            
    except Exception as e:
        print(f"✗ Compilation failed: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        # Ensure cleanup even on unexpected exit
        try:
            # Comment out cleanup to preserve LLVM IR files for debugging
            # compiler.cleanup()
            pass
        except:
            pass

if __name__ == "__main__":
    main()