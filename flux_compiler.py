#!/usr/bin/env python3
"""
Entry point for the FluxLang compiler
"""

import sys
import os
from pathlib import Path

# Add src/compiler and src/stdlib to Python path
sys.path.insert(0, str(Path(__file__).parent / "src" / "compiler"))
sys.path.insert(0, str(Path(__file__).parent / "src" / "stdlib"))

print(sys.path)

# Import compiler components
from fc import FluxCompiler # type: ignore

def main():
    if len(sys.argv) < 2:
        print("Flux Language Compiler")
        print("Usage: python3 flux_compiler.py <input.fx> [options]\n")
        print("Basic Options:")
        print("  -o <output>         Output binary name")
        print("  -v <level>          Legacy verbosity level (0-5)")
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
        print("  python3 flux_compiler.py hello.fx")
        print("  python3 flux_compiler.py hello.fx -o hello --log-level 4")
        print("  python3 flux_compiler.py hello.fx --log-filter lexer,parser --log-timestamp")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_bin = None
    verbosity = None
    logger_config = {}
    
    # Parse command line arguments
    i = 2
    while i < len(sys.argv):
        arg = sys.argv[i]
        
        if arg == "-v" and i + 1 < len(sys.argv):
            verbosity = int(sys.argv[i + 1])
            i += 2
        elif arg == "-o" and i + 1 < len(sys.argv):
            output_bin = sys.argv[i + 1]
            i += 2
        elif arg == "--log-level" and i + 1 < len(sys.argv):
            logger_config['level'] = int(sys.argv[i + 1])
            i += 2
        elif arg == "--log-file" and i + 1 < len(sys.argv):
            logger_config['log_file'] = sys.argv[i + 1]
            i += 2
        elif arg == "--log-timestamp":
            logger_config['timestamp'] = True
            i += 1
        elif arg == "--log-no-color":
            logger_config['colors'] = False
            i += 1
        elif arg == "--log-filter" and i + 1 < len(sys.argv):
            components = [c.strip() for c in sys.argv[i + 1].split(',')]
            logger_config['component_filter'] = components
            i += 2
        else:
            print(f"Warning: Unknown argument '{arg}'")
            i += 1
    
    # Validate input file
    if not input_file.endswith('.fx'):
        print("Error: Input file must have .fx extension", file=sys.stderr)
        sys.exit(1)
    
    if not os.path.exists(input_file):
        print(f"Error: Input file '{input_file}' not found", file=sys.stderr)
        sys.exit(1)
    
    # Create compiler instance with advanced logging
    try:
        compiler = FluxCompiler(verbosity=verbosity, **logger_config)
        
        # Show configuration if debug level or higher
        if logger_config.get('level', 0) >= 4:
            print(f"Flux Compiler Configuration:")
            print(f"  Input file: {input_file}")
            print(f"  Output binary: {output_bin or 'auto-detected'}")
            print(f"  Log level: {logger_config.get('level', 'default')}")
            if logger_config.get('log_file'):
                print(f"  Log file: {logger_config['log_file']}")
            if logger_config.get('component_filter'):
                print(f"  Component filter: {', '.join(logger_config['component_filter'])}")
        
        # Compile the file
        binary_path = compiler.compile_file(input_file, output_bin)
        
        # Final success message (don't duplicate if logger already showed it)
        if logger_config.get('level', 0) < 3:  # Only show if not INFO level or higher
            print(f"✓ Compilation successful: {binary_path}")
            
    except Exception as e:
        print(f"✗ Compilation failed: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        # Ensure cleanup even on unexpected exit
        try:
            compiler.cleanup()
        except:
            pass

if __name__ == "__main__":
    main()