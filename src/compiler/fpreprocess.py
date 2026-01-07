#!/usr/bin/env python3
"""
Flux Import Preprocessor

Resolves all import statements by concatenating files in dependency order.
Creates a single tmp.fx file with all imports resolved.
"""

import re
from pathlib import Path
from typing import Set

class FluxPreprocessor:
    def __init__(self):
        self.processed_files: Set[str] = set()
        self.output_lines = []
        
    def preprocess(self, source_file: str) -> str:
        """
        Preprocess a Flux source file, resolving all imports.
        
        Args:
            source_file: Path to the main .fx file
            output_file: Optional output path (defaults to build/tmp.fx)
            
        Returns:
            Path to the generated tmp.fx file
        """
        # Reset state
        self.processed_files.clear()
        self.output_lines = []
        
        # Process the main file and all its imports
        self._process_file(source_file)
        build_dir = Path("build")
        build_dir.mkdir(exist_ok=True)
        output_file = build_dir / "tmp.fx"
        
        # Write the combined output
        combined_source = '\n'.join(self.output_lines)
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(combined_source)
        
        print(f"[PREPROCESSOR] Generated: {output_file}")
        print(f"[PREPROCESSOR] Processed {len(self.processed_files)} file(s)")
        
        return str(combined_source)
    
    def _process_file(self, filepath: str):
        """Recursively process a file and its imports"""
        resolved_path = self._resolve_path(filepath)
        
        if not resolved_path:
            raise FileNotFoundError(f"Could not find import: {filepath}")
        
        # Avoid circular imports and duplicate processing
        abs_path = str(resolved_path.resolve())
        if abs_path in self.processed_files:
            return
        
        self.processed_files.add(abs_path)
        print(f"[PREPROCESSOR] Processing: {filepath}")
        
        # Read the file
        with open(resolved_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        # Process each line
        for line in lines:
            # Check if this line is an import statement
            match = re.match(r'^\s*import\s+"([^"]+)"\s*;', line)
            
            if match:
                # Found an import - recursively process it first
                import_file = match.group(1)
                self._process_file(import_file)
                # Don't add the import line itself
            else:
                # Regular line - add to output
                self.output_lines.append(line.rstrip())
    
    def _resolve_path(self, filepath: str) -> Path:
        """Resolve import path using standard search locations"""
        # Try direct path first
        if (path := Path(filepath)).exists():
            return path.resolve()
        
        # Search in standard locations
        search_paths = [
            Path.cwd(),
            Path.cwd() / "src" / "stdlib",
            Path.cwd() / "src" / "stdlib" / "runtime",
            Path(__file__).parent.parent / "stdlib",
            Path(__file__).parent / "stdlib",
            Path.home() / ".flux" / "stdlib",
            Path("/usr/local/flux/stdlib/"),
            Path("/usr/flux/stdlib")
        ]
        
        for search_path in search_paths:
            if (full_path := search_path / filepath).exists():
                return full_path.resolve()
        
        return None


# Example usage
if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python fpreprocess.py [input.fx] [output.fx]")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    preprocessor = FluxPreprocessor()
    result = preprocessor.preprocess(input_file, output_file)
    print(f"Preprocessed file: {result}")