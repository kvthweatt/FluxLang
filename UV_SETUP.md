# UV Setup and Usage Guide

This project uses [uv](https://docs.astral.sh/uv/) for fast, reliable Python package management.

## Prerequisites

- Python 3.10 or later
- Windows with Visual Studio (for compiling executables)
- LLVM/Clang (automatically handled by the compiler)

## Installation

### Install UV

If you don't have `uv` installed:

```powershell
# Windows (PowerShell)
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
```

### Setup Development Environment

```bash
# Install all dependencies (including development tools)
uv sync --extra dev

# Or just install runtime dependencies
uv sync
```

## Common Development Tasks

### Using the Development Helper Script

We've provided a helper script to make common tasks easier:

```bash
# Install dev dependencies
python scripts/dev.py install-dev

# Run tests
python scripts/dev.py test

# Format code
python scripts/dev.py format

# Check code formatting (without changes)
python scripts/dev.py check

# Run linters
python scripts/dev.py lint

# Compile a Flux file
python scripts/dev.py compile tests/test.fx

# Clean build artifacts
python scripts/dev.py clean
```

### Direct UV Commands

```bash
# Run the Flux compiler
uv run python flux_compiler.py tests/test.fx

# Run tests
uv run pytest

# Run type checking
uv run mypy src/ flux_compiler.py

# Format code
uv run black src/ flux_compiler.py tests/

# Run linting
uv run flake8 src/ flux_compiler.py

# Add a new dependency
uv add <package-name>

# Add a development dependency
uv add --dev <package-name>

# Update dependencies
uv sync

# Show installed packages
uv pip list
```

## Project Structure

```
Flux/
├── .venv/              # Virtual environment (auto-created)
├── src/
│   └── compiler/       # Compiler source code
├── tests/              # Test files (.fx and .py)
├── scripts/
│   └── dev.py         # Development helper script
├── pyproject.toml     # Project configuration
├── uv.lock           # Lock file (auto-generated)
└── flux_compiler.py  # Main entry point
```

## Key Files

- **pyproject.toml**: Project metadata, dependencies, and tool configuration
- **uv.lock**: Lock file ensuring reproducible builds (committed to version control)
- **.venv/**: Virtual environment (ignored by git)

## Dependencies

### Runtime Dependencies
- `llvmlite>=0.43.0`: LLVM bindings for code generation

### Development Dependencies
- `pytest>=7.0.0`: Testing framework
- `pytest-cov>=4.0.0`: Test coverage reporting
- `black>=23.0.0`: Code formatter
- `flake8>=6.0.0`: Linting
- `mypy>=1.0.0`: Type checking

## Environment Variables

The Flux compiler supports several environment variables for configuration:

- `FLUX_LOG_LEVEL`: Set default log level (0-5)
- `FLUX_LOG_FILE`: Set default log file path
- `FLUX_LOG_TIMESTAMP`: Enable timestamps (1/true/yes)
- `FLUX_LOG_NO_COLOR`: Disable colors (1/true/yes)
- `FLUX_LOG_COMPONENTS`: Filter components (comma-separated)

## Troubleshooting

### Virtual Environment Issues

```bash
# Remove and recreate virtual environment
rm -rf .venv
uv sync --extra dev
```

### Dependency Issues

```bash
# Update all dependencies
uv sync --upgrade

# Clear UV cache
uv cache clean
```

### Compilation Issues

Make sure you have:
1. Visual Studio installed (for Windows compilation)
2. LLVM/Clang available (usually bundled with VS)
3. All dependencies installed: `uv sync`

## VS Code Integration

If using VS Code, make sure to:

1. Select the Python interpreter from `.venv/Scripts/python.exe`
2. Install the Python extension
3. Optionally install extensions for Black, Flake8, and MyPy

## Getting Started

1. Clone the repository
2. Install UV: `powershell -c "irm https://astral.sh/uv/install.ps1 | iex"`
3. Setup environment: `uv sync --extra dev`
4. Test compilation: `uv run python flux_compiler.py tests/test.fx`
5. Run tests: `uv run pytest`

You're ready to develop!
