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

def get_debug_level(level: str):
    match(level):
        case ("none"):
            return 0
        case ("lexer"):
            return 1
        case ("parser"):
            return 2
        case ("ast"):
            return 3
        case ("compiler"):
            return 4
        case ("linker"):
            return 5
        case ("codegen"):
            return 6
        case ("trace"):
            return 7
        case ("everything"):
            return 8
        case _:
            return 0

def set_debug_level():
    tmp_debug_levels = []
    debug_level = config['debug_level']
    debug_level = debug_level.split(" | ")
    if len(debug_level) == 1:
        debug_level = debug_level[0]
        return [get_debug_level(debug_level)]
        return
    for level in debug_level:
        tmp_debug_levels.append(get_debug_level(level))
    return tmp_debug_levels


def debugger(debug_levels: list, target_levels: list, args: list):
    for level in target_levels:
        if level in debug_levels:
            try:
                print("START DEBUG")
                print('\n'.join(args))
                print("END DEBUG")
            except:
                print("START DEBUG")
                print(args)
                print("END DEBUG")
            continue


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
        self.debug_levels = set_debug_level()
        if logger:
            self.logger = logger
        else:
            # Map legacy verbosity to new log levels
            if verbosity is not None:
                logger_kwargs['level'] = min(verbosity, 5)
            self.logger = FluxLoggerConfig.create_logger(**logger_kwargs)

        self.temp_files = []
        
        # Store legacy verbosity for backward compatibility
        self.verbosity = verbosity
        
        self.module = ir.Module(name="flux_module")
        import platform
        self.platform = platform.system()

        if config['target'] == "bootloader":
            # intentionally break this for the else coming after this.
            self.platform = None
            # heheh yeah qemu time
            self.module_triple = "i386-unknown-none-code16"
            # 16-bit data layout
            self.module.data_layout = "e-m:e-p:16:16-i64:32-f80:32-n8:16-a:0:16-S16"
        else:
            # Configure platform-specific settings
            if self.platform == "Windows":
                self.module_triple = "x86_64-pc-windows"
                # Set proper Windows data layout for x86_64
                # Hahaha we're gonna mess this up and make Windows like it.
                self.module.data_layout = "e-m:w-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
            elif self.platform == "Darwin":  # macOS
                # Detect macOS architecture
                try:
                    arch = subprocess.check_output(["uname", "-m"], text=True).strip()
                    if arch == "arm64":
                        self.module_triple = "arm64-apple-macosx11.0.0"
                        self.module.data_layout = "e-m:o-i64:64-i128:128-n32:64-S128"
                        return
                    else:
                        self.module_triple = "x86_64-apple-macosx10.15.0"
                        self.module.data_layout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
                        return
                except:
                    self.module_triple = "arm64-apple-macosx11.0.0"  # Default to ARM64
                    self.module.data_layout = "e-m:o-i64:64-i128:128-n32:64-S128"
                    return
            else:  # Linux and others
                self.module_triple = "x86_64-pc-linux-gnu"
                self.module.data_layout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
            
        debugger(self.debug_levels, [4,5,6,7,8], [f"Target platform: {self.platform}",
                                              f"Module triple: {self.module_triple}"])

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
            self.predefined_macros = {
                # Compiler identification
                '__FLUX__': '1',
                '__FLUX_MAJOR__': '1',
                '__FLUX_MINOR__': '0',
                '__FLUX_PATCH__': '0',
                '__FLUX_VERSION__': '1',
                
                # LLVM backend info
                # Remove when we're no longer using LLVM
                '__LLVM__': '1',
                
                # Architecture detection
                '__ARCH_X86__': '0',
                '__ARCH_X86_64__': '0',
                '__ARCH_ARM__': '0',
                '__ARCH_ARM64__': '0',
                '__ARCH_RISCV__': '0',
                
                # Platform detection
                '__WINDOWS__': '0',
                '__LINUX__': '0',
                '__MACOS__': '0',
                '__POSIX__': '0',
                
                # Feature detection
                '__LITTLE_ENDIAN__': '0',  # Switch if desired.
                '__BIG_ENDIAN__': '1',     # Always big-endian.
                '__SIZEOF_PTR__': '8',     # Assume 64-bit.
                '__SIZEOF_INT__': '4',     # Always 32-bit
                '__SIZEOF_LONG__': '8',    # Always 64-bit
                
                # Compilation mode
                '__DEBUG__': '1' if config.get('debug', False) else '0',
                '__RELEASE__': '0' if config.get('debug', True) else '1',
                '__OPTIMIZE__': config.get('optimization_level', '0'),
            }
            
            # Set platform-specific values
            if self.platform == "Windows":
                self.predefined_macros.update({
                    '__WINDOWS__': '1',
                    '__WIN32__': '1',
                    '__WIN64__': '1' if 'x86_64' in self.module_triple else '0',
                })
            elif self.platform == "Darwin":  # macOS
                self.predefined_macros.update({
                    '__MACOS__': '1',
                    '__APPLE__': '1',
                    '__MACH__': '1',
                    '__POSIX__': '1',
                })
            else:  # Linux/Unix
                self.predefined_macros.update({
                    '__LINUX__': '1',
                    '__UNIX__': '1',
                    '__POSIX__': '1',
                    '__gnu_linux__': '1',
                })
            
            # Set architecture
            if 'x86_64' in self.module_triple or 'amd64' in self.module_triple:
                self.predefined_macros.update({
                    '__ARCH_X86_64__': '1',
                    '__x86_64__': '1',
                    '__amd64__': '1',
                })
            elif 'i386' in self.module_triple or 'i686' in self.module_triple:
                self.predefined_macros.update({
                    '__ARCH_X86__': '1',
                    '__i386__': '1',
                    '__i686__': '1',
                })
            elif 'arm64' in self.module_triple or 'aarch64' in self.module_triple:
                self.predefined_macros.update({
                    '__ARCH_ARM64__': '1',
                    '__arm64__': '1',
                    '__aarch64__': '1',
                })
            print("[COMPILER] Pre-defined / built in macros:\n")
            for key, value in self.predefined_macros.items():
                print("[COMPILER]", key, value)
            
            # Pass to preprocessor
            print("\n[PREPROCESSOR] Standard library / user-defined macros:\n")
            preprocessor = FXPreprocessor(filename, compiler_macros=self.predefined_macros)
            result = preprocessor.process()
            # NOTE: ADD DEBUG LEVEL IN COMPILER & CONFIG FOR PREPROCESSOR
            # WRAP IN DEBUGGER
            #print("[PREPROCESSOR] All Macros:")
            #for key, value in preprocessor.macros.items():
            #    print("[PREPROCESSOR]", key, value)
            # /WRAP
            
            # Store macros in AST
            if not hasattr(self.module, '_preprocessor_macros'):
                self.module._preprocessor_macros = {}
            self.module._preprocessor_macros.update(preprocessor.macros)
            self.module._preprocessor_macros.update(self.predefined_macros)
            self.logger.section(f"Compiling Flux file: {filename}", LogLevel.INFO)

            base_name = Path(filename).stem
            
            # Step 1: Read source code
            self.logger.step("Reading source file", LogLevel.INFO, "compiler")
            try:
                with open(filename, 'r') as f:
                    source = f.read()
                debugger(self.debug_levels, [4,8], [f"Compiler: Read {len(source)} characters from {filename}"])
            except Exception as e:
                debugger(self.debug_levels, [4,8], [f"Compiler: Failed to read source file {filename}: {e}"])
                raise
            
            # Step 2: Lexical analysis
            self.logger.step("Lexical analysis", LogLevel.INFO, "lexer")
            try:
                lexer = FluxLexer(result)
                tokens = lexer.tokenize()
                # Log tokens if requested (legacy compatibility + new system)
                debugger(self.debug_levels, [1,8], ["Lexer",tokens])
            except Exception as e:
                self.logger.error(f"Lexical analysis failed: {e}", "lexer")
                raise
            
            # Step 3: Parsing
            self.logger.step("Parsing", LogLevel.INFO, "parser")
            try:
                debugger(self.debug_levels, [2,8], [result])
                parser = FluxParser(tokens)
                ast = parser.parse()
                
                # Check if parse errors occurred
                if parser.has_errors():
                    self.logger.error(f"Compilation aborted due to {len(parser.get_errors())} parse error(s)", "parser")
                    for error in parser.get_errors():
                        self.logger.error(error, "parser")
                    raise RuntimeError("Parse errors detected - compilation aborted")
                
                # Log AST if requested (legacy compatibility + new system)
                if self.verbosity == 1 or self.logger.level >= LogLevel.DEBUG:
                    self.logger.log_data(LogLevel.DEBUG, "Generated AST", ast, "parser")
                
                debugger(self.debug_levels, [3,8], [ast])
                    
            except Exception as e:
                debugger(self.debug_levels, [2,8], [f"Parser: {e}"])
                raise

            # CHECK FIRST
            #
            # LEFT OFF REPLACING LOG DEBUGGER WITH DEBUGGER FUNCTION
            # CONTINUE BELOW
            
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

            # Check for default configuration
            compiler = config.get('compiler')
            if compiler == "none":
                raise RuntimeError("Compiler not set! Please set your compiler in config\\flux_config.cfg")

            if self.platform == "Darwin":  # macOS
                obj_file = temp_dir / f"{base_name}.o"
                compiler_path = subprocess.check_output(["where", compiler], text=True, stderr=subprocess.DEVNULL).strip()
                
                # Try llc first, fallback to clang if not available
                command_line = None
                match (compiler):
                    case "llc":
                        command_line = [
                            compiler_path,
                            "-O" + config['lto_optimization_level'],  # Aggressive optimization level
                            "-filetype=obj",                    # Direct object file output
                            "-mtriple=" + self.module_triple,   # Target triple
                            #"-march=" + config['architecture'], # Architecture
                            #"-mcpu=" + config['cpu'],           # Target CPU
                            "-enable-misched",                  # Enable machine instruction scheduler
                            "-enable-tail-merge",               # Merge similar tail code
                            "-optimize-regalloc",               # Optimize register allocation
                            "-relocation-model=static",         # Static relocation (no PIC)
                            "-tail-dup-size=3",                 # Tail duplication threshold
                            "-tailcallopt",                     # Enable tail call optimization
                            "-x86-asm-syntax=intel",            # Intel syntax assembly
                            "-x86-use-base-pointer",            # Use base pointer
                            "-no-x86-call-frame-opt",           # Disable call frame optimization (smaller)
                            "-disable-verify",                  # Disable verification for speed
                            str(ll_file),
                            "-o",
                            str(obj_file)
                        ]
                    case "clang":
                        command_line = [
                            compiler_path,
                            "-c",
                            "-O3",
                            str(ll_file),
                            "-o",
                            str(obj_file)
                        ]
                
                success = False
                try:
                    result = subprocess.run(command_line, check=True, capture_output=True, text=True)
                    print(result)
                    success = True
                except Exception as e:
                    self.logger.warning(f"{compiler}: {e}", "compiler")
                
                if not success:
                    self.logger.error("Neither llc nor clang could compile LLVM IR", "compiler")
                    raise RuntimeError("Compilation failed - no suitable compiler found")
                    
            elif self.platform == "Windows":
                obj_file = temp_dir / f"{base_name}.obj"
                
                # Use configuration to determine desired compiler.
                compiler = config.get('compiler')
                # TODO:
                # match (compiler):   case "clang", case "llc", etc...
                compiler_args = [
                    "-O" + config['lto_optimization_level'],  # Aggressive optimization level
                    "-filetype=obj",                    # Direct object file output
                    "-mtriple=" + self.module_triple,   # Target triple
                    #"-march=" + config['architecture'], # Architecture
                    #"-mcpu=" + config['cpu'],           # Target CPU
                    "-enable-misched",                  # Enable machine instruction scheduler
                    "-enable-tail-merge",               # Merge similar tail code
                    "-optimize-regalloc",               # Optimize register allocation
                    "-relocation-model=static",         # Static relocation (no PIC)
                    "-tail-dup-size=3",                 # Tail duplication threshold
                    "-tailcallopt",                     # Enable tail call optimization
                    "-x86-asm-syntax=intel",            # Intel syntax assembly
                    "-x86-use-base-pointer",            # Use base pointer
                    "-no-x86-call-frame-opt",           # Disable call frame optimization (smaller)
                    "-disable-verify",                  # Disable verification for speed
                    str(ll_file),
                    "-o",
                    str(obj_file)
                ]

                # Compile LLVM IR to object file using desired compiler
                cmd = [compiler] + compiler_args
                self.logger.debug(f"Running: {' '.join(cmd)}", compiler)
                
                try:
                    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
                    self.logger.trace(f"{compiler} output: {result.stdout}", compiler)
                    if result.stderr:
                        self.logger.warning(f"{compiler} stderr: {result.stderr}", compiler)
                    self.temp_files.append(obj_file)
                    
                except subprocess.CalledProcessError as e:
                    self.logger.error(f"{compiler} compilation failed: {e.stderr}", compiler)
                    raise
                    
            else:  # Linux and others - use traditional assembly step
                asm_file = temp_dir / f"{base_name}.s"
                obj_file = temp_dir / f"{base_name}.o"
                
                # Generate assembly
                cmd = [
                    "llc",
                    "-O3",                        # Maximum optimization level
                    #"-mtriple=x86_64-linux",      # Explicit target triple
                    "-march=x86-64",
                    "-mcpu=native",               # Optimize for current CPU
                    "-enable-misched",            # Enable machine instruction scheduler
                    "-enable-tail-merge",         # Merge similar tail code
                    "-disable-verify",            # Disable verification for speed
                    "-filetype=asm",              # Assembly file output
                    "-no-x86-call-frame-opt",     # Disable call frame optimization (smaller)
                    "-optimize-regalloc",         # Optimize register allocation
                    "-relocation-model=static",   # Static relocation (no PIC)
                    "-tail-dup-size=3",           # Tail duplication threshold
                    "-tailcallopt",               # Enable tail call optimization
                    "-x86-asm-syntax=att",        # ATT syntax assembly
                    "-x86-use-base-pointer",      # Use base pointer
                    str(ll_file),
                    "-o",
                    str(asm_file)                 # Output to assembly file
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
                    f"C:\\Program Files\\LLVM\\bin\\{config['linker']}.exe",
                    "/entry:" + config.get('entrypoint', 'main'),                 # TODO -> f"/entry:{entrypoint}"
                                                   # Custom entrypoint support, default main if unspecified
                    "/nodefaultlib" if int(config['no_default_libraries']) == 1 else "",
                    "/subsystem:" + config['subsystem'],
                    "/opt:ref" if int(config['remove_unused_funcs']) == 1 else "",                    # Remove unused functions/data
                    "/opt:icf" if int(config['comdat_folding']) == 1 else "",                    # Identical COMDAT folding
                    "/merge:.rdata=.text" if int(config['merge_read_only_w_text']) == 1 else "",         # Merge read-only data with code
                    "/merge:.data=.text" if int(config['marge_data_and_code']) == 1 else "",          # Merge data with code
                    "/align:" + config['memory_alignment'] if int(config['memory_alignment']) != 0 else "",                    # 32-bit memory alignment (minimal padding)
                    "/filealign:" + config['bin_disk_alignment'] if int(config['bin_disk_alignment']) != 0 else "",                # 32-bit file alignment (tiny executable)
                    "/driver" if int(config['driver_mode']) == 1 else "",      # Driver mode
                    "/" + config['mode'],                    # Release mode (no debug info)
                    "/fixed" if int(config['fixed_base_address']) == 1 else "",                      # Fixed base address
                    "/incremental:no" if int(config['incremental_linking']) == 1 else "",             # Disable incremental linking
                    "/strip" if int(config['strip_executable']) == 1 else "",                  # Remove all symbols
                    "/guard:no" if int(config['control_flow_guard']) == 1 else "",                   # Disable CFG (Control Flow Guard)
                    "/dynamicbase:no" if int(config['aslr']) == 1 else "",             # Disable ASLR (for smaller size)
                    #"/highentropyva:no" if int(config['no_default_libraries']) == 0 else "",           # Disable high entropy ASLR
                    "/nxcompat:no" if int(config['dep_compatibility']) == 1 else "",                # Disable DEP compatibility
                    "/opt:lldlto=" + config['lto_optimization_level'],               # Aggressive LTO optimization if available
                    "/opt:lldltojobs=all" if int(config['all_cores_for_lto']) == 1 else "",         # Use all cores for LTO
                    str(obj_file),
                    # Only link essential libraries
                    #config['lib_files'],
                    "kernel32.lib",
                    #"ntdll.lib",
                    "msvcrt.lib",   # Optional, link with C runtime
                    #"ntdll.lib",
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
                    "-e", "_start",                       # Entry point
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
                #link_cmd = ["clang", "-static", str(obj_file), "-o", output_bin]
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

    def compile_bootloader(self, filename: str, output_bin: str = None) -> str:
        """
        Compile a Flux source file to a raw 16-bit bootloader binary
        """
        try:
            self.logger.section(f"COMPILING {filename.upper()} IN BOOTLOADER MODE", LogLevel.INFO)
            base_name = Path(filename).stem
            preprocessor = FluxPreprocessor()
            result = preprocessor.preprocess(filename)
            
            # Step 2: Lexical analysis
            self.logger.step("Lexical analysis", LogLevel.INFO, "lexer")
            try:
                lexer = FluxLexer(result)
                tokens = lexer.tokenize()
                #self.logger.debug(f"Generated {len(tokens) if hasattr(tokens, '__len__') else '?'} tokens", "lexer")
                
                debugger(self.debug_levels, [1,8], [f"Lexer produced {len(tokens)} tokens:", tokens])
            except Exception as e:
                self.logger.error(f"Lexical analysis failed: {e}", "lexer")
                raise
            
            # Step 3: Parsing
            self.logger.step("Parsing", LogLevel.INFO, "parser")
            try:
                parser = FluxParser(tokens)
                ast = parser.parse()
                
                if parser.has_errors():
                    self.logger.error(f"Compilation aborted due to {len(parser.get_errors())} parse error(s)", "parser")
                    for error in parser.get_errors():
                        self.logger.error(error, "parser")
                    raise RuntimeError("Parse errors detected - compilation aborted")
                
                debugger(self.debug_levels, [3,8], ["AST:", ast])
                        
            except Exception as e:
                self.logger.error(f"Parsing failed: {e}", "parser")
                raise
            
            # Step 4: Code generation with 16-bit configuration
            self.logger.step("LLVM IR code generation (16-bit mode)", LogLevel.INFO, "codegen")
            try:                
                self.module = ast.codegen(self.module)
                llvm_ir = str(self.module)
                
                self.logger.debug(f"Generated LLVM IR ({len(llvm_ir)} chars)", "codegen")
                
                if self.logger.level >= LogLevel.TRACE:
                    self.logger.log_data(LogLevel.TRACE, "Generated LLVM IR", llvm_ir, "codegen")
                        
            except Exception as e:
                self.logger.error(f"Code generation failed: {e}", "codegen")
                raise
            
            # Step 5: Create build directory
            self.logger.step("Preparing build environment", LogLevel.DEBUG, "build")
            temp_dir = Path(f"build/{base_name}")
            temp_dir.mkdir(parents=True, exist_ok=True)
            self.logger.debug(f"Build directory: {temp_dir.absolute()}", "build")
            
            # Step 6: Write LLVM IR file
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
            
            # Step 7: Generate 32-bit assembly (we'll add .code16 directive manually)
            self.logger.step("Generating x86 assembly", LogLevel.INFO, "llc")
            asm_file = temp_dir / f"{base_name}.s"
            
            llc_cmd = [
                "llc",
                "-march=x86",              # x86 architecture
                "-mcpu=i386",              # Target 386 CPU
                "-relocation-model=static", # Static addressing (no PIC)
                "-code-model=small",       # Small code model
                "-filetype=asm",           # Assembly output
                "-x86-asm-syntax=intel",   # Intel syntax
                str(ll_file),
                "-o",
                str(asm_file)
            ]
            
            self.logger.debug(f"Running: {' '.join(llc_cmd)}", "llc")
            
            try:
                result = subprocess.run(llc_cmd, check=True, capture_output=True, text=True)
                self.logger.trace(f"LLC output: {result.stdout}", "llc")
                if result.stderr:
                    self.logger.warning(f"LLC stderr: {result.stderr}", "llc")
                self.temp_files.append(asm_file)
            except subprocess.CalledProcessError as e:
                self.logger.error(f"Assembly generation failed: {e.stderr}", "llc")
                raise
            
            # Step 8: Modify assembly to add .code16 directive and remove unwanted sections
            self.logger.step("Modifying assembly for 16-bit real mode", LogLevel.INFO, "build")
            modified_asm_file = temp_dir / f"{base_name}_16bit.s"
            
            try:
                with open(asm_file, 'r') as f:
                    asm_content = f.read()
                
                # Add .code16 at the beginning and clean up
                modified_asm = ".code16\n"
                modified_asm += ".section .boot, \"ax\"\n"  # Bootable section
                modified_asm += ".global _start\n"
                modified_asm += "_start:\n"
                
                # Filter out problematic directives and 32-bit instructions
                for line in asm_content.split('\n'):
                    line_stripped = line.strip()
                    
                    # Skip these directives/sections
                    if any(skip in line_stripped for skip in [
                        '.section',
                        '.text',
                        '.data',
                        '.bss',
                        '.file',
                        '.globl main',
                        '.type',
                        '.size',
                        '.ident',
                        '.addrsig'
                    ]):
                        continue
                    
                    # Keep function labels and code
                    if line_stripped and not line_stripped.startswith('.'):
                        modified_asm += line + "\n"
                
                with open(modified_asm_file, 'w') as f:
                    f.write(modified_asm)
                
                self.temp_files.append(modified_asm_file)
                self.logger.debug(f"Modified assembly written to: {modified_asm_file}", "build")
                
                if self.logger.level >= LogLevel.TRACE:
                    self.logger.log_data(LogLevel.TRACE, "Modified Assembly", modified_asm, "build")
                    
            except Exception as e:
                self.logger.error(f"Failed to modify assembly: {e}", "build")
                raise
            
            # Step 9: Assemble to object file
            self.logger.step("Assembling to object file", LogLevel.INFO, "as")
            obj_file = temp_dir / f"{base_name}.o"
            
            as_cmd = [
                "as",
                "--32",                    # 32-bit mode (for .code16)
                str(modified_asm_file),
                "-o",
                str(obj_file)
            ]
            
            self.logger.debug(f"Running: {' '.join(as_cmd)}", "as")
            
            try:
                result = subprocess.run(as_cmd, check=True, capture_output=True, text=True)
                self.logger.trace(f"AS output: {result.stdout}", "as")
                if result.stderr:
                    self.logger.warning(f"AS stderr: {result.stderr}", "as")
                self.temp_files.append(obj_file)
            except subprocess.CalledProcessError as e:
                self.logger.error(f"Assembly failed: {e.stderr}", "as")
                raise
            
            # Step 10: Link to raw binary
            self.logger.step("Linking to raw binary", LogLevel.INFO, "linker")
            
            output_bin = output_bin or f"{base_name}.bin"
            
            ld_cmd = [
                "ld",
                "-m", "elf_i386",          # 32-bit ELF (for 16-bit code)
                "-T", self._create_bootloader_linker_script(temp_dir),  # Custom linker script
                "--oformat=binary",        # Raw binary output
                "-nostdlib",               # No standard library
                str(obj_file),
                "-o",
                output_bin
            ]
            
            self.logger.debug(f"Running: {' '.join(ld_cmd)}", "linker")
            
            try:
                result = subprocess.run(ld_cmd, check=True, capture_output=True, text=True)
                self.logger.trace(f"Linker output: {result.stdout}", "linker")
                if result.stderr:
                    self.logger.warning(f"Linker stderr: {result.stderr}", "linker")
            except subprocess.CalledProcessError as e:
                self.logger.error(f"Linking failed: {e.stderr}", "linker")
                raise
            
            # Step 11: Verify binary size and add boot signature
            self.logger.step("Adding boot signature", LogLevel.INFO, "build")
            
            try:
                with open(output_bin, 'rb') as f:
                    bootloader = bytearray(f.read())
                
                # Bootloader must be exactly 512 bytes
                if len(bootloader) > 510:
                    self.logger.error(f"Bootloader too large: {len(bootloader)} bytes (max 510)", "build")
                    raise RuntimeError(f"Bootloader exceeds 510 bytes")
                
                # Pad to 510 bytes
                bootloader.extend([0] * (510 - len(bootloader)))
                
                # Add boot signature (0x55AA in little-endian)
                bootloader.extend([0x55, 0xAA])
                
                # Write final bootloader
                with open(output_bin, 'wb') as f:
                    f.write(bootloader)
                
                self.logger.debug(f"Bootloader is {len(bootloader)} bytes with signature", "build")
                
            except Exception as e:
                self.logger.error(f"Failed to add boot signature: {e}", "build")
                raise
            
            # Success!
            self.logger.success(f"Bootloader compiled: {output_bin} ({len(bootloader)} bytes)")
            return output_bin
            
        except Exception as e:
            self.logger.failure(f"Bootloader compilation failed: {e}")
            sys.exit(1)

    def _create_bootloader_linker_script(self, temp_dir: Path) -> str:
        """
        Create a custom linker script for bootloader
        
        Returns:
            Path to linker script
        """
        linker_script = temp_dir / "bootloader.ld"
        
        script_content = """
    OUTPUT_FORMAT("binary")
    OUTPUT_ARCH(i386)
    ENTRY(_start)

    SECTIONS
    {
        . = 0x7C00;  /* BIOS loads bootloader here */
        
        .boot : {
            *(.boot)
            *(.text)
            *(.rodata)
            *(.data)
        }
        
        /DISCARD/ : {
            *(.eh_frame)
            *(.comment)
            *(.note*)
        }
    }
    """
        
        with open(linker_script, 'w') as f:
            f.write(script_content)
        
        self.temp_files.append(linker_script)
        return str(linker_script)
    
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
                    return

    
    if not input_file.endswith('.fx'):
        print("Error: Input file must have .fx extension", file=sys.stderr)
        sys.exit(1)
    
    compiler = FluxCompiler(verbosity=verbosity)
    try:
        match (config['target']):
            case "bootloader":
                print("BOOTLOADER")
                binary_path = compiler.compile_bootloader(input_file, output_bin)
                print(f"Bootloader created at: {binary_path}")
                return
            case _:
                binary_path = compiler.compile_file(input_file, output_bin)
                print(f"Executable created at: {binary_path}")
                return
    except:
        pass
    return

if __name__ == "__main__":
    main()
    exit()