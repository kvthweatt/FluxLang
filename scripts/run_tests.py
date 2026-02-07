#!/usr/bin/env python3
"""
Flux Compiler Test Runner

This script automatically runs the Flux compiler on all test files
in the tests/ directory.

Usage:
    python run_tests.py [options]
    
Options:
    --verbose, -v       Show detailed output for each test
    --keep-artifacts    Keep compiled executables after tests
    --compile-only      Only compile, don't run the executables
    --filter PATTERN    Only run tests matching pattern (substring match)
    --help, -h          Show this help message
"""

import os
import sys
import subprocess
import glob
import argparse
from pathlib import Path
import time
import shutil
from typing import List, Dict, Tuple, Optional

class TestRunner:
    def __init__(self, examples: bool = False, verbose: bool = False, keep_artifacts: bool = False, 
                 compile_only: bool = False, filter_pattern: str = None):
        self.verbose = verbose
        self.keep_artifacts = keep_artifacts
        self.compile_only = compile_only
        self.filter_pattern = filter_pattern.lower() if filter_pattern else None
        self.test_results = []  # Initialize the list
        
        # Get current working directory (project root)
        self.project_root = Path.cwd()
        
        # Compiler is fc.py at project root
        self.compiler_path = self.project_root / "fc.py"
        
        # Tests directory is at project root
        if examples:
            self.test_dir = self.project_root / "examples"
        else:
            self.test_dir = self.project_root / "tests"
        self.build_dir = self.project_root / "build"
        
        # Ensure compiler exists
        if not self.compiler_path.exists():
            print(f"Error: Compiler not found at {self.compiler_path}")
            print(f"   Make sure you're running from the project root directory")
            print(f"   and that fc.py exists in: {self.project_root}")
            sys.exit(1)
            
        # Find or create test directory
        if not self.test_dir.exists():
            print(f"Warning: Test directory not found at {self.test_dir}")
            print(f"   Creating tests/ directory...")
            self.test_dir.mkdir(exist_ok=True)
            print(f"   Created {self.test_dir}")
            print(f"   Please add your .fx test files to this directory")
            
            # Create a simple test file as example
            example_test = self.test_dir / "hello.fx"
            if not example_test.exists():
                example_test.write_text("func main() {\n    print(\"Hello from test!\");\n}\n")
                print(f"   Created example test: {example_test}")
    
    def find_test_files(self) -> List[Path]:
        """Find all .fx files in the tests directory"""
        pattern = self.test_dir / "*.fx"
        files = list(glob.glob(str(pattern)))
        
        if self.filter_pattern:
            files = [f for f in files if self.filter_pattern in os.path.basename(f).lower()]
        
        return [Path(f) for f in sorted(files)]
    
    def run_compiler(self, test_file: Path) -> Tuple[bool, Optional[str], float, str]:
        """Run the Flux compiler on a test file"""
        print(f"Compiling: {test_file.name}...", end="", flush=True)
        
        start_time = time.time()
        
        try:
            # Build the command - compiler expects to be run from project root
            cmd = [sys.executable, str(self.compiler_path), str(test_file)]
            
            if self.verbose:
                print()  # New line for verbose output
                print(f"   Command: {' '.join(cmd)}")
                print(f"   Working dir: {self.project_root}")
            
            # Run the compiler from project root with proper encoding for Windows
            env = os.environ.copy()
            env['PYTHONIOENCODING'] = 'utf-8'
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                cwd=self.project_root,
                encoding='utf-8',
                errors='replace',  # Replace undecodable characters
                env=env
            )
            
            elapsed = time.time() - start_time
            
            if result.returncode == 0:
                # Success - find the executable
                exe_name = test_file.stem
                if sys.platform == "win32":
                    exe_name += ".exe"
                
                # Executable should be created in current directory (project root)
                exe_path = self.project_root / exe_name
                
                if exe_path.exists():
                    print(f"OK ({elapsed:.2f}s)")
                    return True, str(exe_path), elapsed
                else:
                    # Check if it's in the tests directory
                    exe_path = self.build_dir / exe_name.replace(".exe","") / exe_name
                    print(exe_path)
                    if exe_path.exists():
                        print(f"OK ({elapsed:.2f}s)")
                        return True, str(exe_path), elapsed, exe_name
                    else:
                        print(f"FAILED (executable not found)")
                        return False, "Executable not generated", elapsed
            else:
                # Compilation failed
                print(f"FAILED ({elapsed:.2f}s)")
                if self.verbose:
                    # Clean up the output by removing/replacing problematic characters
                    clean_stderr = result.stderr.encode('ascii', 'replace').decode('ascii')
                    print(f"   Error output:\n{clean_stderr}")
                return False, result.stderr, elapsed
                
        except Exception as e:
            elapsed = time.time() - start_time
            print(f"FAILED (error: {str(e)})")
            return False, str(e), elapsed
    
    def run_executable(self, exe_path: str, exe_name: str) -> Tuple[bool, str, float]:
        """Run the compiled executable"""
        exe_path_obj = Path(exe_path)
        if not exe_path_obj.exists():
            return False, f"Executable not found at {exe_path}", 0.0
        
        print(f"   Running {exe_name} ...", end="", flush=True)
        start_time = time.time()
        
        try:
            # Set environment for proper encoding on Windows
            env = os.environ.copy()
            env['PYTHONIOENCODING'] = 'utf-8'
            
            result = subprocess.run(
                [str(exe_path_obj)],
                capture_output=True,
                text=True,
                timeout=5,  # Safety timeout
                cwd=self.project_root,  # Run from project root
                encoding='utf-8',
                errors='replace',  # Replace undecodable characters
                env=env
            )
            
            elapsed = time.time() - start_time
            
            if result.returncode == 0:
                print(f"OK ({elapsed:.2f}s)")
                if self.verbose and result.stdout.strip():
                    print(f"   Output: {result.stdout.strip()}")
                return True, result.stdout, elapsed
            else:
                print(f"RAN (exit code: {result.returncode}) {"PASS" if result.returncode == 0 else "ERR"}")
                if self.verbose:
                    if result.stdout.strip():
                        print(f"   Stdout: {result.stdout.strip()}")
                    if result.stderr.strip():
                        print(f"   Stderr: {result.stderr.strip()}")
                return False, result.stderr, elapsed
                
        except subprocess.TimeoutExpired:
            elapsed = time.time() - start_time
            print(f"FAILED (timeout after {elapsed:.2f}s)")
            return False, "Timeout expired", elapsed
        except Exception as e:
            elapsed = time.time() - start_time
            print(f"FAILED (error: {str(e)})")
            return False, str(e), elapsed
    
    def cleanup_artifacts(self):
        """Clean up generated files"""
        if self.keep_artifacts:
            print("\nArtifacts preserved (--keep-artifacts)")
            return
        
        print("\nCleaning up artifacts...")
        removed_count = 0
        
        # Remove executables from project root
        for test_file in self.find_test_files():
            exe_name = test_file.stem
            if sys.platform == "win32":
                exe_name += ".exe"
            
            # Check project root
            exe_path = self.project_root / exe_name
            if exe_path.exists():
                try:
                    exe_path.unlink()
                    print(f"   Removed: {exe_name}")
                    removed_count += 1
                except Exception as e:
                    print(f"   Warning: Could not remove {exe_name}: {e}")
            
            # Also check tests directory
            exe_path = test_file.parent / exe_name
            if exe_path.exists():
                try:
                    exe_path.unlink()
                    print(f"   Removed: tests/{exe_name}")
                    removed_count += 1
                except Exception as e:
                    print(f"   Warning: Could not remove tests/{exe_name}: {e}")
        
        # Remove build directory if it exists in project root
        build_dir = self.project_root / "build"
        if build_dir.exists():
            try:
                shutil.rmtree(build_dir)
                print(f"   Removed: build/")
                removed_count += 1
            except Exception as e:
                print(f"   Warning: Could not remove build/: {e}")
        
        if removed_count == 0:
            print("   No artifacts to clean up")
    
    def run_tests(self):
        """Run all tests"""
        test_files = self.find_test_files()
        
        if not test_files:
            print(f"No .fx files found in {self.test_dir}")
            print(f"   Add your test files to the tests/ directory")
            return
        
        print(f"Running {len(test_files)} test(s) from {self.test_dir}")
        print(f"   Project root: {self.project_root}")
        print(f"   Verbose: {self.verbose}")
        print(f"   Keep artifacts: {self.keep_artifacts}")
        print(f"   Compile only: {self.compile_only}")
        if self.filter_pattern:
            print(f"   Filter: '{self.filter_pattern}'")
        print()
        
        total_tests = 0
        passed_tests = 0
        total_compile_time = 0
        total_run_time = 0
        
        # Clear any previous results
        self.test_results.clear()
        
        for test_file in test_files:
            total_tests += 1
            
            # Compile the test
            try:
                compile_success, compile_output, compile_time, exe_name = self.run_compiler(test_file)
            except:
                continue
            total_compile_time += compile_time
            
            if compile_success:
                # Run the executable if compilation succeeded
                if not self.compile_only:
                    run_success, run_output, run_time = self.run_executable(compile_output, exe_name)
                    total_run_time += run_time
                    
                    if run_success:
                        passed_tests += 1
                        self.test_results.append((test_file.name, True, True, compile_time, run_time, run_output))
                    else:
                        self.test_results.append((test_file.name, True, False, compile_time, run_time, run_output))
                else:
                    # Just compilation test
                    passed_tests += 1
                    self.test_results.append((test_file.name, True, "N/A", compile_time, 0, ""))
            else:
                # Compilation failed
                self.test_results.append((test_file.name, False, False, compile_time, 0, compile_output))
            
            print()  # Blank line between tests
        
        # Print summary
        print("\n" + "=" * 60)
        print("TEST SUMMARY")
        print("=" * 60)
        
        for test_name, compile_ok, run_ok, c_time, r_time, output in self.test_results:
            if self.compile_only:
                status = "PASS" if compile_ok else "FAIL"
                print(f"{status:5} {test_name:<30} Compile: {'PASS' if compile_ok else 'FAIL'} ({c_time:.2f}s)")
            else:
                if compile_ok and run_ok:
                    status = "PASS"
                    print(f"{status:5} {test_name:<30} Compile: PASS ({c_time:.2f}s), Run: PASS ({r_time:.2f}s)")
                else:
                    status = "FAIL"
                    if not compile_ok:
                        print(f"{status:5} {test_name:<30} Compile: FAIL ({c_time:.2f}s)")
                    else:
                        print(f"{status:5} {test_name:<30} Compile: PASS ({c_time:.2f}s), Run: FAIL ({r_time:.2f}s)")
            
            # Show first line of output/error for failed tests
            if self.verbose and (not compile_ok or (not run_ok and not self.compile_only)):
                error_msg = output if isinstance(output, str) else ""
                if error_msg:
                    # Clean up any problematic characters
                    try:
                        clean_error = error_msg.encode('ascii', 'replace').decode('ascii')
                        first_line = clean_error.split('\n')[0].strip()
                        if first_line:
                            print(f"     {'Error' if not compile_ok or not run_ok else 'Output'}: {first_line[:80]}...")
                    except:
                        print(f"     Error: [Could not decode error message]")
        
        print("=" * 60)
        print(f"Total Tests: {total_tests}")
        print(f"Passed: {passed_tests} ({passed_tests/total_tests*100:.1f}%)")
        print(f"Failed: {total_tests - passed_tests}")
        print(f"Total compile time: {total_compile_time:.2f}s")
        if not self.compile_only:
            print(f"Total run time: {total_run_time:.2f}s")
            print(f"Total time: {total_compile_time + total_run_time:.2f}s")
        print("=" * 60)
        
        # Clean up unless asked to keep artifacts
        self.cleanup_artifacts()
        
        return passed_tests == total_tests

def main():
    parser = argparse.ArgumentParser(
        description="Run Flux compiler tests",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python run_tests.py                  # Run all tests
  python run_tests.py -v               # Run with verbose output
  python run_tests.py --filter hello   # Only run tests with 'hello' in filename
  python run_tests.py --compile-only   # Only compile, don't run executables
  python run_tests.py --keep-artifacts # Keep compiled executables
        """
    )
    
    parser.add_argument("--verbose", "-v", action="store_true",
                       help="Show detailed output for each test")
    parser.add_argument("--keep-artifacts", action="store_true",
                       help="Keep compiled executables after tests")
    parser.add_argument("--compile-only", action="store_true",
                       help="Only compile, don't run the executables")
    parser.add_argument("--filter", type=str,
                       help="Only run tests matching pattern (substring match)")
    parser.add_argument("--examples", action="store_true",
                        help="Only test examples")
    
    args = parser.parse_args()
    
    runner = TestRunner(
        examples=args.examples,
        verbose=args.verbose,
        keep_artifacts=args.keep_artifacts,
        compile_only=args.compile_only,
        filter_pattern=args.filter
    )
    
    success = runner.run_tests()
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()