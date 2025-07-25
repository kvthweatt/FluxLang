#!/usr/bin/env python3
"""
Entry point for the FluxLang compiler
"""

import sys
import os
from pathlib import Path

# Add src/compiler to Python path
sys.path.insert(0, str(Path(__file__).parent / "src" / "compiler"))

# Import compiler components
from fc import FluxCompiler # type: ignore

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 flux_compiler.py <input.fx> [options]")
        print("Options:")
        print("  -v <level>  Verbosity level (0-4)")
        print("  -o <output> Output binary name")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_bin = None
    verbosity = None
    
    # Parse command line arguments
    i = 2
    while i < len(sys.argv):
        if sys.argv[i] == "-v" and i + 1 < len(sys.argv):
            verbosity = int(sys.argv[i + 1])
            i += 2
        elif sys.argv[i] == "-o" and i + 1 < len(sys.argv):
            output_bin = sys.argv[i + 1]
            i += 2
        else:
            i += 1
    
    # Create compiler instance
    compiler = FluxCompiler(verbosity=verbosity)
    
    try:
        # Compile the file
        binary_path = compiler.compile_file(input_file, output_bin)
        print(f"✓ Compilation successful: {binary_path}")
    except Exception as e:
        print(f"✗ Compilation failed: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()