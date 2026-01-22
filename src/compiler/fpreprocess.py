#!/usr/bin/env python3
"""
Flux Import Preprocessor with Macro Support
Simple line-by-line processing without regex overcomplication.
"""

import os
from pathlib import Path
from typing import Set, Dict, Optional, List, Tuple

class FluxPreprocessor:
    def __init__(self, compiler_macros=None):
        self.processed_files: Set[str] = set()
        self.output_lines = []
        self.macros: Dict[str, str] = {}  # macro_name -> value

        if compiler_macros:
            self.macros.update(compiler_macros)

    def preprocess(self, source_file: str) -> str:
        """
        Preprocess a Flux source file, resolving all imports and macros.
        """
        # Reset state
        self.processed_files.clear()
        self.output_lines = []
        
        # Process the main file and all its imports
        self._process_file(source_file)
        
        # Write output to build directory
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
        
        return combined_source
    
    def _process_file(self, filepath: str):
        """Process a file and its imports"""
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
            content = f.read()
        
        # Process line by line
        lines = content.splitlines()
        i = 0
        while i < len(lines):
            i = self._process_line(lines, i)
    
    def _process_line(self, lines: List[str], i: int) -> int:
        """Process a single line, return next line index"""
        line = lines[i].rstrip()
        
        # Skip empty lines
        if not line:
            self.output_lines.append("")
            return i + 1
        
        # Check for import
        if line.strip().startswith("#import"):
            # Get the file path between quotes
            if '"' in line:
                import_start = line.find('"') + 1
                import_end = line.find('"', import_start)
                if import_end > import_start:
                    import_file = line[import_start:import_end].strip()
                    self._process_file(import_file)
            return i + 1
        
        # Check for #def
        if line.strip().startswith("#def"):
            parts = line.split()
            if len(parts) >= 3:
                macro_name = parts[1]
                macro_value = ' '.join(parts[2:]).rstrip(';').strip()
                self.macros[macro_name] = macro_value
                print(f"[PREPROCESSOR] Defined macro: {macro_name} = {macro_value}")
            return i + 1
        
        # Check for #ifdef
        if line.strip().startswith("#ifdef"):
            parts = line.split()
            if len(parts) >= 2:
                macro_name = parts[1]
                return self._process_conditional_block(lines, i, macro_name, False)
        
        # Check for #ifndef
        if line.strip().startswith("#ifndef"):
            parts = line.split()
            if len(parts) >= 2:
                macro_name = parts[1]
                return self._process_conditional_block(lines, i, macro_name, True)
        
        # Regular line - do macro substitution
        processed_line = self._substitute_macros(line)
        self.output_lines.append(processed_line)
        return i + 1
    
    def _process_conditional_block(self, lines: List[str], start_i: int, macro_name: str, is_ifndef: bool) -> int:
        """Process an #ifdef/#ifndef block and return next line index after #endif"""
        # Get macro value
        macro_value = self.macros.get(macro_name)
        
        # Evaluate condition
        if is_ifndef:
            condition_true = macro_value is None or macro_value == '0'
        else:
            condition_true = macro_value is not None and macro_value == '1'
        
        directive = "#ifndef" if is_ifndef else "#ifdef"
        print(f"[PREPROCESSOR] {directive} {macro_name} (value={macro_value}): {'TRUE' if condition_true else 'FALSE'}")
        
        i = start_i + 1
        depth = 1
        in_else = False
        else_seen = False
        
        # Store lines that should be included
        lines_to_process = []
        
        while i < len(lines):
            line = lines[i].rstrip()
            stripped = line.strip()
            
            # Handle nested conditionals
            if stripped.startswith("#ifdef") or stripped.startswith("#ifndef"):
                # We need to process nested conditionals regardless of current state
                # because they might define their own macros
                nested_end = self._skip_conditional_block(lines, i)
                
                if condition_true and not in_else:
                    # Include the nested block if we're in the active branch
                    for j in range(i, nested_end):
                        lines_to_process.append(lines[j].rstrip())
                i = nested_end
                continue
            
            # Check for #else
            elif stripped == "#else" and depth == 1:
                if else_seen:
                    raise SyntaxError("Multiple #else directives in same conditional block")
                else_seen = True
                in_else = True
                i += 1
                continue
            
            # Check for #endif
            elif stripped.startswith("#endif"):
                depth -= 1
                if depth == 0:
                    # Process the collected lines
                    if lines_to_process:
                        # Create a temporary processor for this block
                        # to handle nested directives properly
                        temp_processor = FluxPreprocessor(self.macros.copy())
                        temp_processor.output_lines = []
                        j = 0
                        while j < len(lines_to_process):
                            j = temp_processor._process_line(lines_to_process, j)
                        
                        # Add the processed lines to our output
                        self.output_lines.extend(temp_processor.output_lines)
                        
                        # Update our macros with any new ones defined in the block
                        self.macros.update(temp_processor.macros)
                    
                    return i + 1
                else:
                    # Nested #endif
                    if condition_true and not in_else:
                        lines_to_process.append(line)
                    i += 1
                    continue
            
            # Regular line
            if condition_true and not in_else:
                lines_to_process.append(line)
            elif not condition_true and in_else:
                lines_to_process.append(line)
            # Otherwise skip the line
            
            i += 1
        
        raise SyntaxError(f"Unclosed {directive} block starting at line {start_i + 1}")
    
    def _skip_conditional_block(self, lines: List[str], start_i: int) -> int:
        """Skip over a conditional block without processing it, return index after #endif"""
        i = start_i
        depth = 0
        
        while i < len(lines):
            stripped = lines[i].strip()
            
            if stripped.startswith("#ifdef") or stripped.startswith("#ifndef"):
                depth += 1
            elif stripped.startswith("#endif"):
                depth -= 1
                if depth == 0:
                    return i + 1
            
            i += 1
        
        raise SyntaxError(f"Unclosed conditional block starting at line {start_i + 1}")
    
    def _substitute_macros(self, line: str) -> str:
        """Simple macro substitution - replace macro names with their values"""
        if not line or ';' in line and line.strip() == ';':
            return line
        
        # Split line into tokens, preserving whitespace structure
        result_parts = []
        in_quotes = False
        in_comment = False
        current_token = ""
        
        for char in line:
            if char == '"' and not in_comment:
                in_quotes = not in_quotes
                current_token += char
            elif char == '/' and not in_quotes and not in_comment:
                # Check for comment start
                if current_token.endswith('/'):
                    in_comment = True
                    current_token = current_token[:-1]  # Remove the /
                    result_parts.append(current_token)
                    current_token = "//"
                else:
                    current_token += char
            elif in_comment:
                current_token += char
            elif char.isspace() or char in '.,;:()[]{}+-*/%=!<>|&^~':
                # End of token
                if current_token:
                    # Check if token is a macro
                    if current_token in self.macros:
                        result_parts.append(self.macros[current_token])
                    else:
                        result_parts.append(current_token)
                    current_token = ""
                result_parts.append(char)
            else:
                current_token += char
        
        # Handle last token
        if current_token:
            if current_token in self.macros:
                result_parts.append(self.macros[current_token])
            else:
                result_parts.append(current_token)
        
        return ''.join(result_parts)
    
    def _resolve_path(self, filepath: str) -> Optional[Path]:
        """Resolve import path - SIMPLE VERSION"""
        # Convert to Path object
        path = Path(filepath)
        
        # If it exists as given, return it
        if path.exists():
            return path
        
        # Try relative to current directory
        cwd = Path.cwd()
        
        # Common locations to check
        locations = [
            filepath,  # original
            cwd / "src" / "stdlib" / filepath,
            cwd / "src" / "stdlib" / "runtime" / filepath,
            cwd / "src" / "stdlib" / "functions" / filepath,
            #cwd / "tests" / filepath,
        ]
        
        for location in locations:
            loc_path = Path(location)
            if loc_path.exists():
                return loc_path
        
        return None


# Example usage
if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python fpreprocess.py [input.fx]")
        print("Output will be written to build/tmp.fx")
        sys.exit(1)
    
    input_file = sys.argv[1]
    
    preprocessor = FluxPreprocessor()
    result = preprocessor.preprocess(input_file)
    
    print("\n=== Preprocessing Complete ===")