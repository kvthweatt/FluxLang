#!/usr/bin/env python3
"""
Flux Import Preprocessor with Macro Support

Resolves all import statements and preprocessor directives (#def, #ifdef, #ifndef, #else, #endif).
Creates a single processed output with all imports resolved and conditional compilation applied.
"""

import re
from pathlib import Path
from typing import Set, Dict, Optional

class FluxPreprocessor:
    def __init__(self):
        self.processed_files: Set[str] = set()
        self.output_lines = []
        self.macros: Dict[str, str] = {}  # macro_name -> value
        
    def preprocess(self, source_file: str) -> str:
        """
        Preprocess a Flux source file, resolving all imports and macros.
        
        Args:
            source_file: Path to the main .fx file
            
        Returns:
            The preprocessed source code as a string
        """
        # Reset state
        self.processed_files.clear()
        self.output_lines = []
        self.macros.clear()
        
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
        print(f"[PREPROCESSOR] Defined {len(self.macros)} macro(s)")
        
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
        
        # Process lines with conditional compilation
        self._process_lines(lines)
    
    def _process_lines(self, lines):
        """Process lines with support for preprocessor directives"""
        i = 0
        while i < len(lines):
            line = lines[i].rstrip()
            
            # Check for import statement
            import_match = re.match(r'^\s*#import\s+"([^"]+)"\s*;', line)
            if import_match:
                import_file = import_match.group(1)
                self._process_file(import_file)
                i += 1
                continue
            
            # Check for #def directive
            def_match = re.match(r'^\s*#def\s+(\w+)\s+(.+?)\s*;?\s*$', line)
            if def_match:
                macro_name = def_match.group(1)
                macro_value = def_match.group(2).rstrip(';').strip()
                self.macros[macro_name] = macro_value
                print(f"[PREPROCESSOR] Defined macro: {macro_name} = {macro_value}")
                i += 1
                continue
            
            # Check for #ifdef directive
            ifdef_match = re.match(r'^\s*#ifdef\s+(\w+)\s*$', line)
            if ifdef_match:
                macro_name = ifdef_match.group(1)
                i = self._process_conditional(lines, i, macro_name, is_ifndef=False)
                continue
            
            # Check for #ifndef directive
            ifndef_match = re.match(r'^\s*#ifndef\s+(\w+)\s*$', line)
            if ifndef_match:
                macro_name = ifndef_match.group(1)
                i = self._process_conditional(lines, i, macro_name, is_ifndef=True)
                continue
            
            # Regular line - perform macro substitution and add to output
            processed_line = self._substitute_macros(line)
            self.output_lines.append(processed_line)
            i += 1
    
    def _process_conditional(self, lines, start_index, macro_name, is_ifndef):
        """
        Process #ifdef/#ifndef blocks with #else and #endif support
        
        Returns the index after the #endif
        """
        # Determine if condition is true
        macro_defined = macro_name in self.macros
        condition_true = (not macro_defined) if is_ifndef else macro_defined
        
        directive_type = "#ifndef" if is_ifndef else "#ifdef"
        print(f"[PREPROCESSOR] {directive_type} {macro_name}: {'TRUE' if condition_true else 'FALSE'}")
        
        i = start_index + 1
        depth = 1  # Track nested conditionals
        in_else = False
        then_block = []
        else_block = []
        
        while i < len(lines) and depth > 0:
            line = lines[i].rstrip()
            
            # Check for nested #ifdef/#ifndef
            if re.match(r'^\s*#ifdef\s+\w+\s*$', line) or re.match(r'^\s*#ifndef\s+\w+\s*$', line):
                depth += 1
                if condition_true and not in_else:
                    then_block.append(line)
                elif not condition_true and in_else:
                    else_block.append(line)
            # Check for #else
            elif re.match(r'^\s*#else\s*$', line) and depth == 1:
                in_else = True
            # Check for #endif
            elif re.match(r'^\s*#endif;\s*$', line):
                depth -= 1
                if depth == 0:
                    # Process the appropriate block
                    block_to_process = then_block if condition_true else else_block
                    self._process_lines(block_to_process)
                    return i + 1
                else:
                    # Nested #endif
                    if condition_true and not in_else:
                        then_block.append(line)
                    elif not condition_true and in_else:
                        else_block.append(line)
            else:
                # Regular line in conditional block
                if condition_true and not in_else:
                    then_block.append(line)
                elif not condition_true and in_else:
                    else_block.append(line)
            
            i += 1
        
        # If we reach here, #endif was not found
        raise SyntaxError(f"Unclosed {directive_type} {macro_name} - missing #endif")
    
    def _substitute_macros(self, line: str) -> str:
        """Substitute macro references in a line"""
        result = line
        
        # Sort macros by length (longest first) to handle overlapping names
        sorted_macros = sorted(self.macros.items(), key=lambda x: len(x[0]), reverse=True)
        
        for macro_name, macro_value in sorted_macros:
            # Use word boundaries to avoid partial matches
            # Match macro_name as a whole word (not part of another identifier)
            pattern = r'\b' + re.escape(macro_name) + r'\b'
            result = re.sub(pattern, macro_value, result)
        
        return result
    
    def _resolve_path(self, filepath: str) -> Optional[Path]:
        """Resolve import path using standard search locations"""
        # Try direct path first
        if (path := Path(filepath)).exists():
            return path.resolve()
        
        # Search in standard locations
        search_paths = [
            Path.cwd(),
            Path.cwd() / "src" / "stdlib",
            Path.cwd() / "src" / "stdlib" / "runtime",
            Path.cwd() / "src" / "stdlib" / "functions",
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
    result = preprocessor.preprocess(input_file)
    
    if output_file:
        with open(output_file, 'w') as f:
            f.write(result)
        print(f"Written to: {output_file}")
    else:
        print("\n=== Preprocessed Output ===")
        print(result)