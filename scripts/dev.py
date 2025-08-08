#!/usr/bin/env python3
"""
Development helper script for the Flux compiler project.

This script provides convenient commands for common development tasks
using uv for dependency management.
"""

import sys
import subprocess
from pathlib import Path


def run_command(cmd: list[str], description: str = None):
    """Run a command and handle errors"""
    if description:
        print(f"Running: {description}")
    print(f"Command: {' '.join(cmd)}")
    try:
        result = subprocess.run(cmd, check=True)
        return result.returncode == 0
    except subprocess.CalledProcessError as e:
        print(f"Error: Command failed with exit code {e.returncode}")
        return False
    except FileNotFoundError:
        print(f"Error: Command not found: {cmd[0]}")
        return False


def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        print("Flux Development Helper")
        print("Usage: python scripts/dev.py <command>")
        print("")
        print("Commands:")
        print("  install     - Install all dependencies")
        print("  install-dev - Install with development dependencies")
        print("  test        - Run tests")
        print("  lint        - Run linters (flake8, mypy)")
        print("  format      - Format code with black")
        print("  check       - Run format check without modifying files")
        print("  compile     - Compile a test file (requires .fx file as argument)")
        print("  clean       - Clean build artifacts")
        print("")
        print("Examples:")
        print("  python scripts/dev.py install-dev")
        print("  python scripts/dev.py test")
        print("  python scripts/dev.py format")
        print("  python scripts/dev.py compile tests/test.fx")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "install":
        run_command(["uv", "sync"], "Installing dependencies")
    
    elif command == "install-dev":
        run_command(["uv", "sync", "--extra", "dev"], "Installing with dev dependencies")
    
    elif command == "test":
        run_command(["uv", "run", "pytest"], "Running tests")
    
    elif command == "lint":
        print("Running linters...")
        run_command(["uv", "run", "flake8", "src/", "flux_compiler.py"], "Running flake8")
        run_command(["uv", "run", "mypy", "src/", "flux_compiler.py"], "Running mypy")
    
    elif command == "format":
        run_command(["uv", "run", "black", "src/", "flux_compiler.py", "tests/"], "Formatting code")
    
    elif command == "check":
        run_command(["uv", "run", "black", "--check", "src/", "flux_compiler.py", "tests/"], 
                   "Checking code format")
    
    elif command == "compile":
        if len(sys.argv) < 3:
            print("Error: compile command requires a .fx file argument")
            print("Usage: python scripts/dev.py compile <file.fx>")
            sys.exit(1)
        
        fx_file = sys.argv[2]
        if not Path(fx_file).exists():
            print(f"Error: File not found: {fx_file}")
            sys.exit(1)
        
        run_command(["uv", "run", "python", "flux_compiler.py", fx_file], 
                   f"Compiling {fx_file}")
    
    elif command == "clean":
        print("Cleaning build artifacts...")
        import shutil
        
        # Remove common build artifacts
        artifacts = [
            "build/temp*",
            "dist/",
            "*.egg-info/",
            "__pycache__/",
            ".pytest_cache/",
            ".mypy_cache/",
            "*.exe",
            "*.obj",
            "*.o",
        ]
        
        for pattern in artifacts:
            for path in Path(".").rglob(pattern):
                if path.is_dir():
                    shutil.rmtree(path)
                    print(f"Removed directory: {path}")
                elif path.is_file():
                    path.unlink()
                    print(f"Removed file: {path}")
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
