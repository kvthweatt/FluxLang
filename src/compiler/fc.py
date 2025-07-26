#!/usr/bin/env python3
"""
Flux Compiler with Full Toolchain Integration

Copyright (C) 2025 Karac Thweatt

Contributors:

    Piotr Bednarski
"""

import sys
import os
import subprocess
from pathlib import Path
from llvmlite import ir
from flexer import FluxLexer
from fparser import FluxParser, ParseError
from fast import *

class FluxCompiler:
    def __init__(self, /, verbosity: int = None):
        self.verbosity = int(verbosity) if verbosity != None else None
        self.module = ir.Module(name="flux_module")
        import platform
        if platform.system() == "Darwin":  # macOS
            # Detect macOS architecture
            import subprocess
            try:
                arch = subprocess.check_output(["uname", "-m"], text=True).strip()
                if arch == "arm64":
                    self.module.triple = "arm64-apple-macosx11.0.0"
                else:
                    self.module.triple = "x86_64-apple-macosx10.15.0"
            except:
                self.module.triple = "arm64-apple-macosx11.0.0"  # Default to ARM64
        else:  # Linux and others
            self.module.triple = "x86_64-pc-linux-gnu"
        #self.module.data_layout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
        self.temp_files = []

    def compile_file(self, filename: str, output_bin: str = None) -> str:
        try:
            # 1. Parse and generate LLVM IR
            with open(filename, 'r') as f:
                source = f.read()
            
            lexer = FluxLexer(source)
            tokens = lexer.tokenize()

            if self.verbosity == 0:
                print(tokens)
            
            parser = FluxParser(tokens)
            ast = parser.parse()

            if self.verbosity == 1:
                print(ast)
            
            print(ast)
            self.module = ast.codegen(self.module)
            llvm_ir = str(self.module)

            if self.verbosity == 2:
                print(llvm_ir)
            
            # Create temp directory
            base_name = Path(filename).stem
            temp_dir = Path(f"build/{base_name}")
            temp_dir.mkdir(exist_ok=True)
            
            # 2. Generate LLVM IR file
            ll_file = temp_dir / f"{base_name}.ll"
            with open(ll_file, 'w') as f:
                f.write(llvm_ir)
            self.temp_files.append(ll_file)
            
            # 3. Compile directly to object file (skip assembly step on macOS)
            obj_file = temp_dir / f"{base_name}.o"
            import platform
            if platform.system() == "Darwin":  # macOS
                # Compile directly to object file to avoid assembly issues
                subprocess.run([
                    "llc",
                    "-O2",               # Enable optimizations  
                    "-filetype=obj",     # Output object file directly
                    str(ll_file),
                    "-o", str(obj_file)
                ], check=True)
            else:  # Linux - use traditional assembly step
                asm_file = temp_dir / f"{base_name}.s"
                subprocess.run([
                    "llc",
                    "-O2",               # Enable optimizations
                    str(ll_file),
                    "-o", str(asm_file)
                ], check=True)
                self.temp_files.append(asm_file)

                if self.verbosity == 3:
                    with open(asm_file, "r") as f:
                        f.seek(0)
                        print(f.read())
                
                subprocess.run([
                    "as", "--64", str(asm_file), "-o", str(obj_file)
                ], check=True)
            
            self.temp_files.append(obj_file)

            if self.verbosity == 4:
                print(tokens)
                print(ast)
                print(llvm_ir)
                with open(asm_file, "r") as f:
                    f.seek(0)
                    print(f.read())
            
            # 5. Link executable
            output_bin = output_bin or f"./{base_name}"
            link_args = [str(obj_file), "-o", output_bin]
            
            if platform.system() == "Darwin":  # macOS
                # Use clang for linking on macOS
                subprocess.run(["clang"] + link_args, check=True)
            else:  # Linux
                subprocess.run(["gcc", "-no-pie"] + link_args, check=True)
            
            print(f"Successfully built: {output_bin}")
            return output_bin
            
        except Exception as e:
            self.cleanup()
            print(f"Compilation failed: {e}", file=sys.stderr)
            sys.exit(1)
    
    def cleanup(self):
        """Remove temporary files"""
        for f in self.temp_files:
            try:
                if os.path.exists(f):
                    os.remove(f)
            except:
                pass

def main():
    if len(sys.argv) < 2:
        print("Usage: python fc.py input.fx [output_binary] ...arguments...\n\n")
        print("\tArguments:\n")
        print("\t\t-vX\tVerbose output. X = 0..4\n")
        print("\t\t\t\t0: Tokens")
        print("\t\t\t\t1: AST")
        print("\t\t\t\t2: LLVM IR")
        print("\t\t\t\t3: ASM")
        print("\t\t\t\t4: Everything")
        sys.exit(1)

    input_file = None
    output_bin = None

    if len(sys.argv) == 2:
        input_file = sys.argv[1]
        output_bin = sys.argv[2] if len(sys.argv) > 2 else None

    verbosity = None

    if len(sys.argv) > 2:
        input_file = sys.argv[1]
        output_bin = sys.argv[2] if len(sys.argv) > 2 else None
        for arg in sys.argv:
            if arg.lower().startswith("-v"):
                if len(arg) > 2 and arg[2:].isdigit():
                    verbosity = int(arg[2:])
            elif arg.lower() == "-o":
                    with open(input_file, 'r') as f:
                        source = f.read()
                    lexer = FluxLexer(source)
                    tokens = lexer.tokenize()
                    parser = FluxParser(tokens)
                    ast = parser.parse()
                    print(ast)
                    return

    
    if not input_file.endswith('.fx'):
        print("Error: Input file must have .fx extension", file=sys.stderr)
        sys.exit(1)
    
    compiler = FluxCompiler(verbosity=verbosity)
    try:
        binary_path = compiler.compile_file(input_file, output_bin)
        print(f"Executable created at: {binary_path}")
    finally:
        compiler.cleanup()

if __name__ == "__main__":
    main()