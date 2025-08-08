import sys
import os
from pathlib import Path

# Add src/compiler to PYTHONPATH so tests can import local packages easily
project_root = Path(__file__).parent.parent
src_compiler_path = project_root / "src" / "compiler"
sys.path.insert(0, str(src_compiler_path))
