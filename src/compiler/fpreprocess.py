import os
from pathlib import Path
from typing import Set, Dict, Optional, List

class FXPreprocessor:
    def __init__(self, source_file, compiler_macros=None):
        self.source_file = source_file
        self.processed_files: Set[str] = set()
        self.output_lines = []
        self.macros: Dict[str, str] = {}
        
        if compiler_macros:
            self.macros.update(compiler_macros)
    
    def process(self) -> str:
        """Main processing pipeline"""
        # Step 1: Process all imports and build content in memory
        self._process_file(self.source_file)
        
        # Step 2: Build combined source
        combined_source = '\n'.join(self.output_lines)
        
        # Step 3: Keep replacing macros until no more replacements occur
        replaced = True
        iteration = 0
        while replaced:
            iteration += 1
            print(f"[PREPROCESSOR] Macro substitution pass {iteration}")
            replaced = False
            lines = combined_source.split('\n')
            new_lines = []
            
            for line in lines:
                new_line = self._substitute_macros(line)
                if new_line != line:
                    replaced = True
                new_lines.append(new_line)
            
            combined_source = '\n'.join(new_lines)
        
        print(f"[PREPROCESSOR] Completed after {iteration} macro passes")
        
        # Step 4: Write to build/tmp.fx
        build_dir = Path("build")
        build_dir.mkdir(exist_ok=True)
        output_file = build_dir / "tmp.fx"
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(combined_source)
        
        print(f"[PREPROCESSOR] Generated: {output_file}")
        print(f"[PREPROCESSOR] Processed {len(self.processed_files)} file(s)")
        
        return combined_source
    
    def _resolve_path(self, filepath: str) -> Optional[Path]:
        """Resolve import path"""
        path = Path(filepath)
        
        # If it exists as given, return it
        if path.exists():
            return path
        
        # Try relative to current directory
        cwd = Path.cwd()
        
        # Common locations to check
        locations = [
            filepath,
            cwd / "src" / "stdlib" / filepath,
            cwd / "src" / "stdlib" / "runtime" / filepath,
            cwd / "src" / "stdlib" / "functions" / filepath,
        ]
        
        for location in locations:
            loc_path = Path(location)
            if loc_path.exists():
                return loc_path
        
        return None
    
    def _process_file(self, filepath: str):
        """Process a file and its imports"""
        resolved_path = self._resolve_path(filepath)
        
        if not resolved_path:
            raise FileNotFoundError(f"Could not find import: {filepath}")
        
        # Avoid circular imports
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
        
        stripped = line.strip()
        
        # Check for #def
        if stripped.startswith("#def"):
            parts = line.split()
            if len(parts) >= 3:
                macro_name = parts[1]
                macro_value = ' '.join(parts[2:]).rstrip(';').strip()
                self.macros[macro_name] = macro_value
                print(f"[PREPROCESSOR] Defined macro: {macro_name} = {macro_value}")
            return i + 1
        
        # Check for #ifdef
        if stripped.startswith("#ifdef"):
            parts = line.split()
            if len(parts) >= 2:
                macro_name = parts[1]
                return self._process_conditional_block(lines, i, macro_name, False)
        
        # Check for #ifndef
        if stripped.startswith("#ifndef"):
            parts = line.split()
            if len(parts) >= 2:
                macro_name = parts[1]
                return self._process_conditional_block(lines, i, macro_name, True)
        
        # Check for import
        if stripped.startswith("#import"):
            # Get the file path between quotes
            if '"' in line:
                import_start = line.find('"') + 1
                import_end = line.find('"', import_start)
                if import_end > import_start:
                    import_file = line[import_start:import_end].strip()
                    self._process_file(import_file)
            return i + 1
        
        # Check for #endif - skip it
        if stripped.startswith("#endif"):
            return i + 1
        
        # Check for #else - skip it (handled in conditional processing)
        if stripped == "#else":
            return i + 1
        
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
            condition_true = macro_value is not None and macro_value != '0'
        
        print(f"[PREPROCESSOR] {'#ifndef' if is_ifndef else '#ifdef'} {macro_name}: {'TRUE' if condition_true else 'FALSE'} (value={macro_value})")
        
        i = start_i + 1
        depth = 1
        in_else = False
        else_seen = False
        
        # Store lines that should be included
        lines_to_include = []
        
        while i < len(lines):
            line = lines[i].rstrip()
            stripped = line.strip()
            
            # Handle nested conditionals
            if stripped.startswith("#ifdef") or stripped.startswith("#ifndef"):
                depth += 1
            
            # Check for #else at our depth level
            if stripped == "#else" and depth == 1:
                if else_seen:
                    raise SyntaxError("Multiple #else directives in same conditional block")
                else_seen = True
                in_else = True
                i += 1
                continue
            
            # Check for #endif
            if stripped.startswith("#endif"):
                depth -= 1
                if depth == 0:
                    # End of our block - process collected lines
                    if lines_to_include:
                        j = 0
                        while j < len(lines_to_include):
                            j = self._process_line(lines_to_include, j)
                    return i + 1
            
            # Collect lines based on condition
            if depth > 1:
                # Inside nested block - always include
                if (condition_true and not in_else) or (not condition_true and in_else):
                    lines_to_include.append(line)
            else:
                # Our depth level
                if (condition_true and not in_else) or (not condition_true and in_else):
                    lines_to_include.append(line)
            
            i += 1
        
        raise SyntaxError(f"Unclosed conditional block starting at line {start_i + 1}")
    
    def _substitute_macros(self, line: str) -> str:
        """Simple macro substitution - replace macro names with their values"""
        if not line or line.strip() == ';':
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
                    current_token = current_token[:-1]
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


# Usage
if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python preprocessor.py <source_file.fx>")
        sys.exit(1)
    
    preprocessor = FXPreprocessor(sys.argv[1])
    preprocessor.process()