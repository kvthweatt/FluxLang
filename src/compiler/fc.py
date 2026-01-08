#!/usr/bin/env python3
"""
Flux Compiler with Full Toolchain Integration

Copyright (C) 2025 Karac Thweatt

Contributors:

    Piotr Bednarski
"""

import sys, os, subprocess
from pathlib import Path
from llvmlite import ir
from flexer import FluxLexer
from fparser import FluxParser, ParseError
from fast import *
from fpreprocess import *
from flux_logger import FluxLogger, FluxLoggerConfig, LogLevel
from fconfig import *

class FluxCompiler:
    def __init__(self, /, 
                 verbosity: int = None, 
                 logger: FluxLogger = None,
                 **logger_kwargs):
        """
        Initialize the Flux compiler with configurable logging
        
        Args:
            verbosity: Legacy verbosity level (0-5) - maps to new logging system
            logger: Custom FluxLogger instance (overrides verbosity)
            **logger_kwargs: Additional arguments for FluxLogger creation
        """
        # Initialize logger
        print("RIGHT HERE vvv")
        print(config.get('operating_system', 'win'))
        print("RIGHT HERE ^^^")
        if logger:
            self.logger = logger
        else:
            # Map legacy verbosity to new log levels
            if verbosity is not None:
                logger_kwargs['level'] = min(verbosity, 5)
            self.logger = FluxLoggerConfig.create_logger(**logger_kwargs)
        
        # Store legacy verbosity for backward compatibility
        self.verbosity = verbosity
        
        self.module = ir.Module(name="flux_module")
        import platform
        self.platform = platform.system()
        
        # Configure platform-specific settings
        if self.platform == "Windows":
            self.module_triple = "x86_64-pc-windows"
            self.module.triple = self.module_triple
            # Set proper Windows data layout for x86_64
            self.module.data_layout = "e-m:w-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
        elif self.platform == "Darwin":  # macOS
            # Detect macOS architecture
            import subprocess
            try:
                arch = subprocess.check_output(["uname", "-m"], text=True).strip()
                if arch == "arm64":
                    self.module_triple = "arm64-apple-macosx11.0.0"
                    self.module.triple = self.module_triple
                    self.module.data_layout = "e-m:o-i64:64-i128:128-n32:64-S128"
                else:
                    self.module_triple = "x86_64-apple-macosx10.15.0"
                    self.module.triple = self.module_triple
                    self.module.data_layout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
            except:
                self.module_triple = "arm64-apple-macosx11.0.0"  # Default to ARM64
                self.module.triple = self.module_triple
                self.module.data_layout = "e-m:o-i64:64-i128:128-n32:64-S128"
        else:  # Linux and others
            self.module_triple = "x86_64-pc-linux-gnu"
            self.module.triple = self.module_triple
            self.module.data_layout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
        
        self.logger.debug(f"Target platform: {self.platform}", "compiler")
        self.logger.debug(f"Module triple: {self.module_triple}", "compiler")
        
        self.temp_files = []

    def compile_file(self, filename: str, output_bin: str = None) -> str:
        """
        Compile a Flux source file to executable binary
        
        Args:
            filename: Path to the .fx source file
            output_bin: Optional output binary name
            
        Returns:
            Path to the generated executable
        """
        try:
            self.logger.section(f"Preprocessing Flux file: {filename}", LogLevel.INFO)
            preprocessor = FluxPreprocessor()
            result = preprocessor.preprocess(filename)
            self.logger.section(f"Compiling Flux file: {filename}", LogLevel.INFO)
            base_name = Path(filename).stem
            
            # Step 1: Read source code
            self.logger.step("Reading source file", LogLevel.INFO, "compiler")
            try:
                with open(filename, 'r') as f:
                    source = f.read()
                self.logger.debug(f"Read {len(source)} characters from {filename}", "compiler")
            except Exception as e:
                self.logger.error(f"Failed to read source file {filename}: {e}", "compiler")
                raise
            
            # Step 2: Lexical analysis
            self.logger.step("Lexical analysis", LogLevel.INFO, "lexer")
            try:
                print(result)
                lexer = FluxLexer(result)
                tokens = lexer.tokenize()
                self.logger.debug(f"Generated {len(tokens) if hasattr(tokens, '__len__') else '?'} tokens", "lexer")
                
                # Log tokens if requested (legacy compatibility + new system)
                if self.verbosity == 0 or self.logger.level >= LogLevel.TRACE:
                    self.logger.log_data(LogLevel.TRACE, "Generated Tokens", tokens, "lexer")
                    
            except Exception as e:
                self.logger.error(f"Lexical analysis failed: {e}", "lexer")
                raise
            
            # Step 3: Parsing
            self.logger.step("Parsing", LogLevel.INFO, "parser")
            try:
                parser = FluxParser(tokens)
                ast = parser.parse()
                
                # Check if parse errors occurred
                if parser.has_errors():
                    self.logger.error(f"Compilation aborted due to {len(parser.get_errors())} parse error(s)", "parser")
                    for error in parser.get_errors():
                        self.logger.error(error, "parser")
                    raise RuntimeError("Parse errors detected - compilation aborted")
                
                self.logger.debug("AST generation completed", "parser")
                
                # Log AST if requested (legacy compatibility + new system)
                if self.verbosity == 1 or self.logger.level >= LogLevel.DEBUG:
                    self.logger.log_data(LogLevel.DEBUG, "Generated AST", ast, "parser")
                    
                # Legacy: always print AST (TODO: remove this in future versions)
                if not self.logger.level >= LogLevel.DEBUG:
                    print(ast)
                    
            except Exception as e:
                self.logger.error(f"Parsing failed: {e}", "parser")
                raise
            
            # Step 4: Code generation
            self.logger.step("LLVM IR code generation", LogLevel.INFO, "codegen")
            try:
                self.module = ast.codegen(self.module)
                llvm_ir = str(self.module)
                self.logger.debug(f"Generated LLVM IR ({len(llvm_ir)} chars)", "codegen")
                
                # Log LLVM IR if requested (legacy compatibility + new system)
                if self.verbosity == 2 or self.logger.level >= LogLevel.TRACE:
                    self.logger.log_data(LogLevel.TRACE, "Generated LLVM IR", llvm_ir, "codegen")
                    
            except Exception as e:
                self.logger.error(f"Code generation failed: {e}", "codegen")
                raise
            
            # Step 5: Create build directory
            self.logger.step("Preparing build environment", LogLevel.DEBUG, "build")
            temp_dir = Path(f"build/{base_name}")
            temp_dir.mkdir(parents=True, exist_ok=True)
            self.logger.debug(f"Build directory: {temp_dir.absolute()}", "build")
            
            # Step 6: Generate LLVM IR file
            self.logger.step("Writing LLVM IR file", LogLevel.DEBUG, "build")
            ll_file = temp_dir / f"{base_name}.ll"
            try:
                with open(ll_file, 'w') as f:
                    f.write(llvm_ir)
                self.temp_files.append(ll_file)
                self.logger.debug(f"LLVM IR written to: {ll_file}", "build")
            except Exception as e:
                self.logger.error(f"Failed to write LLVM IR file: {e}", "build")
                raise
            
            # Step 7: Compile to object file (platform-specific)
            self.logger.step(f"Compiling to object file ({self.platform})", LogLevel.INFO, "compiler")
            
            if self.platform == "Darwin":  # macOS
                obj_file = temp_dir / f"{base_name}.o"
                
                # Try llc first, fallback to clang if not available
                llc_cmd = ["llc", "-O2", "-filetype=obj", str(ll_file), "-o", str(obj_file)]
                clang_cmd = [
                    "clang",
                    "-c",
                    "-Os",                    # Optimize for size
                    "-O3",                    # Optimize for speed (clang will use the most aggressive)
                    "-ffunction-sections",    # Place each function in its own section
                    "-fdata-sections",        # Place each data in its own section
                    "-fno-unwind-tables",     # Disable unwind tables (saves space)
                    "-fno-asynchronous-unwind-tables",
                    "-fmerge-all-constants",  # Merge duplicate constants
                    "-fno-stack-protector",   # Disable stack protection
                    "-fno-ident",             # Don't emit .ident directive
                    "-Wl,--gc-sections",      # Remove unused sections during linking
                    "-march=native",          # Optimize for current CPU
                    "-mtune=native",
                    "-fomit-frame-pointer",   # Omit frame pointers (smaller, faster)
                    str(ll_file),
                    "-o",
                    str(obj_file)
                ]
                
                success = False
                for cmd, tool_name in [(llc_cmd, "llc"), (clang_cmd, "clang")]:
                    self.logger.debug(f"Trying {tool_name}: {' '.join(cmd)}", "compiler")
                    try:
                        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
                        self.logger.trace(f"{tool_name} output: {result.stdout}", "compiler")
                        if result.stderr:
                            self.logger.warning(f"{tool_name} stderr: {result.stderr}", "compiler")
                        success = True
                        break
                    except (subprocess.CalledProcessError, FileNotFoundError) as e:
                        self.logger.debug(f"{tool_name} failed: {e}", "compiler")
                        continue
                
                if not success:
                    self.logger.error("Neither llc nor clang could compile LLVM IR", "compiler")
                    raise RuntimeError("Compilation failed - no suitable compiler found")
                    
            elif self.platform == "Windows":
                obj_file = temp_dir / f"{base_name}.obj"
                
                # Windows: Use Clang directly to compile LLVM IR to object file
                # Try multiple possible Clang locations
                clang_args = [
                    "-c",
                    "-Os",                    # Optimize for size
                    "-O3",                    # Optimize for speed (clang will use the most aggressive)
                    "-ffunction-sections",    # Place each function in its own section
                    "-fdata-sections",        # Place each data in its own section
                    "-fno-unwind-tables",     # Disable unwind tables (saves space)
                    "-fno-asynchronous-unwind-tables",
                    #"-fmerge-all-constants",  # Merge duplicate constants
                                                # Enabling may cause undefined behavior for Flux programs
                    "-fno-stack-protector",   # Disable stack protection
                    "-fno-ident",             # Don't emit .ident directive
                    "-Wl,--gc-sections",      # Remove unused sections during linking
                    "-march=native",          # Optimize for current CPU
                    "-Wno-override-module",   # Do not override triple presets
                    "-mtune=native",
                    "-fomit-frame-pointer",   # Omit frame pointers (smaller, faster)
                    str(ll_file),
                    "-o",
                    str(obj_file)
                ]

                # Compile LLVM IR to object file using Clang
                cmd = ["clang"] + clang_args
                self.logger.debug(f"Running: {' '.join(cmd)}", "clang")
                
                try:
                    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
                    self.logger.trace(f"Clang output: {result.stdout}", "clang")
                    if result.stderr:
                        self.logger.warning(f"Clang stderr: {result.stderr}", "clang")
                    self.temp_files.append(obj_file)
                    
                except subprocess.CalledProcessError as e:
                    self.logger.error(f"Clang compilation failed: {e.stderr}", "clang")
                    raise
                    
            else:  # Linux and others - use traditional assembly step
                asm_file = temp_dir / f"{base_name}.s"
                obj_file = temp_dir / f"{base_name}.o"
                
                # Generate assembly
                cmd = [
                    "llc",
                    "-O3",                        # Maximum optimization level
                    "-mtriple=x86_64-linux",      # Explicit target triple
                    "-march=x86-64",
                    "-mcpu=native",               # Optimize for current CPU
                    "-enable-misched",            # Enable machine instruction scheduler
                    "-enable-tail-merge",         # Merge similar tail code
                    #"-disable-cfi",               # Disable control flow integrity (smaller)
                    #"-disable-fault-maps",        # Disable fault maps (smaller)
                    #"-disable-live-intervals",    # Disable live interval analysis for speed
                    #"-disable-post-ra-scheduler", # Disable post-register allocation scheduler
                    "-disable-verify",            # Disable verification for speed
                    "-filetype=obj",              # Direct object file output
                    #"-join-physregs",             # Join physical registers
                    "-no-x86-call-frame-opt",     # Disable call frame optimization (smaller)
                    "-optimize-regalloc",         # Optimize register allocation
                    "-relocation-model=static",   # Static relocation (no PIC)
                    #"-spiller=default",
                    #"-strip-debug",               # Strip debug info
                    "-tail-dup-size=3",           # Tail duplication threshold
                    "-tailcallopt",               # Enable tail call optimization
                    #"-tls-direct-seg-refs",       # Direct TLS segment references
                    "-x86-asm-syntax=att",      # Intel syntax assembly (optional)
                    "-x86-use-base-pointer",      # Use base pointer
                    #"-x86-use-recip",             # Use reciprocal approximations
                    #"-stats",                     # Print statistics (optional)
                    str(ll_file),
                    "-o",
                    str(obj_file)
                ]
                self.logger.debug(f"Running: {' '.join(cmd)}", "llc")
                
                try:
                    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
                    self.logger.trace(f"LLC output: {result.stdout}", "llc")
                    if result.stderr:
                        self.logger.warning(f"LLC stderr: {result.stderr}", "llc")
                    self.temp_files.append(asm_file)
                    
                    # Log assembly if requested (legacy compatibility)
                    if self.verbosity == 3 or self.logger.level >= LogLevel.TRACE:
                        with open(asm_file, "r") as f:
                            asm_content = f.read()
                        self.logger.log_data(LogLevel.TRACE, "Generated Assembly", asm_content, "llc")
                    
                    # Assemble to object file
                    as_cmd = ["as", "--64", str(asm_file), "-o", str(obj_file)]
                    self.logger.debug(f"Running: {' '.join(as_cmd)}", "as")
                    
                    as_result = subprocess.run(as_cmd, check=True, capture_output=True, text=True)
                    self.logger.trace(f"AS output: {as_result.stdout}", "as")
                    if as_result.stderr:
                        self.logger.warning(f"AS stderr: {as_result.stderr}", "as")
                        
                except subprocess.CalledProcessError as e:
                    self.logger.error(f"Assembly failed: {e.stderr}", "as")
                    raise
            
            self.temp_files.append(obj_file)
            self.logger.debug(f"Object file created: {obj_file}", "build")
            
            # Legacy verbosity level 4 - show everything
            if self.verbosity == 4:
                self.logger.log_data(LogLevel.INFO, "All Tokens", tokens, "legacy")
                self.logger.log_data(LogLevel.INFO, "Complete AST", ast, "legacy")
                self.logger.log_data(LogLevel.INFO, "Complete LLVM IR", llvm_ir, "legacy")
                if self.platform == "Linux":
                    with open(asm_file, "r") as f:
                        asm_content = f.read()
                    self.logger.log_data(LogLevel.INFO, "Complete Assembly", asm_content, "legacy")
            
            # Step 8: Link executable
            output_bin = output_bin or f"./{base_name}"
            # Add .exe extension for Windows executables
            if self.platform == "Windows" and not output_bin.endswith('.exe'):
                output_bin += ".exe"
            
            self.logger.step(f"Linking executable: {output_bin}", LogLevel.INFO, "linker")
            
            if self.platform == "Darwin":  # macOS
                link_cmd = ["clang", str(obj_file), "-o", output_bin]
            elif self.platform == "Windows":
                # Use LLD 
                link_cmd = [
                    "C:\\Program Files\\LLVM\\bin\\lld-link.exe",
                    "/entry:main",                 # TODO -> f"/entry:{entrypoint}"
                                                   # Custom entrypoint support, default main if unspecified
                    "/nodefaultlib",
                    "/subsystem:console",
                    "/opt:ref",                    # Remove unused functions/data
                    "/opt:icf",                    # Identical COMDAT folding
                    "/merge:.rdata=.text",         # Merge read-only data with code
                    "/merge:.data=.text",          # Merge data with code
                    #"/merge:.bss=.text",           # Merge uninitialized data
                    "/align:32",                    # 32-bit memory alignment (minimal padding)
                    "/filealign:32",                # 32-bit file alignment (tiny executable)
                    "/release",                    # Release mode (no debug info)
                    "/fixed",                      # Fixed base address
                    "/incremental:no",             # Disable incremental linking
                    #"/strip:all",                  # Remove all symbols
                    "/guard:no",                   # Disable CFG (Control Flow Guard)
                    "/dynamicbase:no",             # Disable ASLR (for smaller size)
                    "/nxcompat:no",                # Disable DEP compatibility
                    #"/highentropyva:no",           # Disable high entropy ASLR
                    "/opt:lldlto=3",               # Aggressive LTO optimization if available
                    "/opt:lldltojobs=all",         # Use all cores for LTO
                    str(obj_file),
                    # Only link essential libraries
                    "kernel32.lib",
                    "msvcrt.lib",   # Optional, link with C runtime
                    # "user32.lib",  # Uncomment only if GUI functions are used
                    # "gdi32.lib",   # Uncomment only if drawing functions are used
                    f"/out:{output_bin}"
                ]
                self.logger.debug(f"Running: {' '.join(link_cmd)}", "linker")
                
                try:
                    result = subprocess.run(link_cmd, check=True, capture_output=True, text=True)
                    self.logger.trace(f"Linker output: {result.stdout}", "linker")
                    if result.stderr:
                        self.logger.warning(f"Linker stderr: {result.stderr}", "linker")
                except subprocess.CalledProcessError as e:
                    self.logger.error(f"Linking failed: {e.stderr}", "linker")
                    raise
            else:  # Linux and others
                link_cmd = [
                    "ld",
                    "--gc-sections",                    # Remove unused sections
                    "--as-needed",                      # Only link needed libraries
                    "--strip-all",                      # Strip all symbols
                    "--build-id=none",                  # No build ID
                    "--no-eh-frame-hdr",                # No exception handling frame header
                    "--no-ld-generated-unwind-info",    # No unwind info
                    "-z", "noseparate-code",            # Don't separate code segments
                    "-z", "norelro",                    # Disable RELRO (size tradeoff)
                    "-z", "now",                        # Bind now (alternative to norelro)
                    "-z", "noexecstack",                # No executable stack
                    "-z", "max-page-size=0x1000",       # Small page size
                    "-z", "common-page-size=0x1000",    # Small common page size
                    "-z", "defs",                       # Report undefined symbols (strict)
                    "--hash-style=gnu",                 # GNU hash style (faster)
                    "--sort-section=alignment",         # Sort by alignment
                    "--compress-debug-sections=none",   # No debug compression
                    "--fatal-warnings",                 # Treat warnings as errors
                    "--stats",                          # Show linker statistics
                    "--cref",                           # Cross reference output
                    "-Map", f"{output_bin}.map",        # Generate map file
                    "--orphan-handling=place",          # Handle orphan sections
                    #"--icf=all",                        # Identical Code Folding
                    #"--print-icf-sections",             # Show ICF statistics
                    #"--plugin-opt=O3",                  # LTO optimization level 3
                    #"--plugin-opt=merge-functions",     # Merge similar functions
                    #"--plugin-opt=dce",                 # Dead code elimination
                    #"--plugin-opt=inline",              # Function inlining
                    "--unresolved-symbols=ignore-all",
                    "-Ttext-segment=0x400000",          # Text segment address
                    "--section-start", ".rodata=0x500000",  # Read-only data address
                    "--section-start", ".data=0x600000",    # Data section address
                    "--section-start", ".bss=0x700000",     # BSS section address
                    "-e", "main",                       # Entry point
                    str(obj_file),
                    # Runtime dependencies -- Enable if you want them in your code.
                    #"/usr/lib/x86_64-linux-gnu/Scrt1.o",        # Startup code
                    #"/usr/lib/x86_64-linux-gnu/crti.o",         # C runtime init
                    #"-lc",                                     # C library
                    #"/usr/lib/x86_64-linux-gnu/crtn.o",        # C runtime term
                    #"-lgcc",                                   # GCC runtime
                    #"-lgcc_eh",                                # GCC exception handling
                    "--start-group",
                    "--end-group",
                    "-o", output_bin
                ]
                self.logger.debug(f"Running: {' '.join(link_cmd)}", "linker")
                
                try:
                    result = subprocess.run(link_cmd, check=True, capture_output=True, text=True)
                    self.logger.trace(f"Linker output: {result.stdout}", "linker")
                    if result.stderr:
                        self.logger.warning(f"Linker stderr: {result.stderr}", "linker")
                except subprocess.CalledProcessError as e:
                    self.logger.error(f"Linking failed: {e.stderr}", "linker")
                    raise
                
            # Success!
            self.logger.success(f"Compilation completed: {output_bin}")
            return output_bin
            
        except Exception as e:
            # Comment out cleanup to preserve LLVM IR files for debugging
            # self.cleanup()
            self.logger.failure(f"Compilation failed: {e}")
            sys.exit(1)
    
    def cleanup(self):
        """Remove temporary files and cleanup logger"""
        self.logger.debug(f"Cleaning up {len(self.temp_files)} temporary files", "cleanup")
        
        for f in self.temp_files:
            try:
                if os.path.exists(f):
                    os.remove(f)
                    self.logger.trace(f"Removed: {f}", "cleanup")
            except Exception as e:
                self.logger.warning(f"Failed to remove {f}: {e}", "cleanup")
        
        # Close logger if it has file handles
        try:
            self.logger.close()
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