import io
import json
import os
import sys
from pathlib import Path
from typing import Set, Dict, Optional, List

# Reconfigure stdout/stderr to UTF-8 so Unicode characters in diagnostics
# (arrows, checkmarks, box-drawing, etc.) don't crash on Windows consoles
# that default to a narrow codepage like CP1252.
for _stream_name in ('stdout', 'stderr'):
    _stream = getattr(sys, _stream_name)
    if hasattr(_stream, 'reconfigure'):
        _stream.reconfigure(encoding='utf-8', errors='replace')
    elif hasattr(_stream, 'buffer'):
        setattr(sys, _stream_name,
                io.TextIOWrapper(_stream.buffer, encoding='utf-8', errors='replace'))

FLUXC_SRCDIR = Path(os.environ.get("FLUXC_SRCDIR", Path(__file__).parent)).resolve()

UTF8_BOM = '\ufeff'

def _read_source_file(path) -> str:
    """Read a source file as UTF-8, stripping any BOM and warning on
    invalid byte sequences rather than crashing hard."""
    try:
        with open(path, 'r', encoding='utf-8-sig') as f:   # utf-8-sig auto-strips BOM
            return f.read()
    except UnicodeDecodeError:
        # Fall back: replace undecodable bytes with the replacement char and warn.
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        # Strip BOM manually in case utf-8-sig path wasn't reached
        if content.startswith(UTF8_BOM):
            content = content[1:]
        print(
            f"[PREPROCESSOR] WARNING: '{path}' contains invalid UTF-8 sequences. "
            "Replacement characters (\ufffd) have been substituted. "
            "Save the file as UTF-8 to silence this warning.",
            file=sys.stderr,
        )
        return content

class FXPreprocessor:
    def __init__(self, source_file, compiler_constants=None, verbose=False):
        self.source_file = source_file
        self.verbose = verbose
        self.processed_files: Set[str] = set()
        self.output_lines = []
        self.constants: Dict[str, str] = {}
        self.psubs: Dict[str, tuple] = {}  # name -> (params: List[str], body: str)
        self.lib_dirs: List[str] = []
        # Maps each output line index (0-based) -> (filename, local_line_number 1-based)
        self.line_map: List[tuple] = []
        # Stack of directories for the files currently being processed (for local imports)
        self._dir_stack: List[Path] = []

        if compiler_constants:
            self.constants.update(compiler_constants)
    
    def process(self) -> str:
        """Main processing pipeline"""
        # Step 1: Process all imports and build content in memory
        self._process_file(self.source_file)
        
        # Step 2: Build combined source
        combined_source = '\n'.join(self.output_lines)
        
        # Step 4: Keep replacing constants until no more replacements occur
        replaced = True
        iteration = 0
        while replaced:
            iteration += 1
            if self.verbose:
                print(f"[PREPROCESSOR] constant substitution passes: {iteration}")
            replaced = False
            lines = combined_source.split('\n')
            new_lines = []
            
            for line in lines:
                new_line = self._substitute_constants(line)
                if new_line != line:
                    replaced = True
                new_lines.append(new_line)
            
            combined_source = '\n'.join(new_lines)
        ending = "es." if iteration > 1 else "."
        if self.verbose:
            print(f"[PREPROCESSOR] Completed after {iteration} constant pass{ending}")
        
        # Step 5: Write to build/tmp.fx
        build_dir = Path("build")
        build_dir.mkdir(exist_ok=True)
        output_file = build_dir / "tmp.fx"
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(combined_source)
        
        if self.verbose:
            print(f"[PREPROCESSOR] Generated: {output_file}")
            print(f"[PREPROCESSOR] Processed {len(self.processed_files)} file(s)")
        
        return combined_source
    
    def _strip_comments(self, content: str) -> str:
        """Strip all comments from content: // and /// ... ///
        String literals (double or single quoted) are passed through unchanged
        so that URLs like https:// inside strings are not treated as comments.
        Newlines inside block comments are preserved so that line numbers in the
        stripped output always match line numbers in the original source."""
        result = []
        i = 0
        n = len(content)
        in_string = False      # True while inside a string literal
        string_char = ''       # The quote character that opened the string

        while i < n:
            c = content[i]

            # ── String literal tracking ───────────────────────────────────────
            if in_string:
                result.append(c)
                if c == '\\' and i + 1 < n:
                    # Escaped character -- consume both so \" doesn't close the string
                    i += 1
                    result.append(content[i])
                elif c == string_char:
                    in_string = False
                i += 1
                continue

            if c in ('"', "'"):
                in_string = True
                string_char = c
                result.append(c)
                i += 1
                continue

            # ── Block comment: /// ... /// ────────────────────────────────────
            if i + 2 < n and c == '/' and content[i+1] == '/' and content[i+2] == '/':
                i += 3
                while i < n:
                    if i + 2 < n and content[i] == '/' and content[i+1] == '/' and content[i+2] == '/':
                        i += 3
                        break
                    if content[i] == '\n':
                        result.append('\n')
                    i += 1
                continue

            # ── Line comment: // ──────────────────────────────────────────────
            if i + 1 < n and c == '/' and content[i+1] == '/':
                while i < n and content[i] != '\n':
                    i += 1
                continue

            # ── Regular character ─────────────────────────────────────────────
            result.append(c)
            i += 1

        return ''.join(result)
    
    # ------------------------------------------------------------------
    # Import resolution -- three distinct search domains
    # ------------------------------------------------------------------

    def _resolve_path_local(self, filepath: str) -> Optional[Path]:
        """Resolve a local import (#import "file.fx").
        Search order:
          1. Relative to the importing file's directory (top of _dir_stack).
          2. Relative to the initial source file's directory.
          3. CWD.
          4. Any directories added via #dir.
        """
        locations: List[Path] = []

        # 1. Relative to the currently-processing file's directory
        if self._dir_stack:
            locations.append(self._dir_stack[-1] / filepath)

        # 2. Relative to the root source file's directory
        root_dir = Path(self.source_file).resolve().parent
        locations.append(root_dir / filepath)

        # 3. CWD
        locations.append(Path.cwd() / filepath)

        # 4. Extra dirs from #dir
        for lib_dir in self.lib_dirs:
            locations.append(Path(lib_dir) / filepath)

        for loc in locations:
            if loc.exists():
                return loc.resolve()
        return None

    def _resolve_path_stdlib(self, filepath: str) -> Optional[Path]:
        """Resolve a stdlib import (#import <file.fx>).
        Only the stdlib trees under FLUXC_SRCDIR are searched.
        """
        cwd = FLUXC_SRCDIR
        locations = [
            cwd / "src" / "stdlib" / filepath,
            cwd / "src" / "stdlib" / "runtime" / filepath,
            cwd / "src" / "stdlib" / "functions" / filepath,
            cwd / "src" / "stdlib" / "builtins" / filepath,
            cwd / "src" / "stdlib" / "utility" / filepath,
        ]
        for loc in locations:
            if Path(loc).exists():
                return Path(loc).resolve()
        return None

    def _resolve_path(self, filepath: str) -> Optional[Path]:
        """Legacy resolver used internally (e.g. for the root source file).
        Searches local, stdlib, and package trees in order.
        """
        path = Path(filepath)
        if path.exists():
            return path.resolve()

        result = self._resolve_path_local(filepath)
        if result:
            return result
        result = self._resolve_path_stdlib(filepath)
        if result:
            return result
        return self._resolve_path_stdlib(filepath)
    
    def _process_package(self, package_name: str):
        """Resolve and import a package by name via #package.
        Reads .fpm/packages/<name>/package.json, finds the entrypoint,
        and processes it with the package directory on the dir stack so
        relative imports inside the package resolve correctly.
        """
        fpm_packages_dir = Path.cwd() / ".fpm" / "packages"
        package_dir = fpm_packages_dir / package_name
        if not package_dir.is_dir():
            raise FileNotFoundError(
                f"[PREPROCESSOR] Package '{package_name}' not found in {fpm_packages_dir}"
            )

        manifest_path = package_dir / "package.json"
        if not manifest_path.exists():
            raise FileNotFoundError(
                f"[PREPROCESSOR] Package '{package_name}' is missing package.json"
            )

        with open(manifest_path, 'r', encoding='utf-8') as f:
            manifest = json.load(f)

        # Support both {"entrypoint": "..."} at top level and nested under "entries"
        entries = manifest.get("entries", manifest)
        entrypoint = entries.get("entrypoint")
        if not entrypoint:
            raise KeyError(
                f"[PREPROCESSOR] Package '{package_name}' package.json has no 'entrypoint' field"
            )

        entrypoint_path = (package_dir / entrypoint).resolve()
        if not entrypoint_path.exists():
            raise FileNotFoundError(
                f"[PREPROCESSOR] Package '{package_name}' entrypoint '{entrypoint}' not found"
            )

        # Check if already processed (guard by absolute path)
        abs_path = str(entrypoint_path)
        if abs_path in self.processed_files:
            return

        if self.verbose:
            print(f"[PREPROCESSOR] Package import: {package_name} -> {entrypoint}")
        # Push the package directory so the entrypoint's local imports resolve within it
        self._dir_stack.append(package_dir)
        self._process_file(str(entrypoint_path), resolver=self._resolve_path_local)
        self._dir_stack.pop()

    def _process_file(self, filepath: str, resolver=None):
        """Process a file and its imports.
        resolver: callable(filepath)->Optional[Path] to use instead of _resolve_path.
        """
        if resolver is None:
            resolver = self._resolve_path
        # Normalize path separators to the OS convention so that Windows-style
        # backslash paths in source files (e.g. runtime\runtime.fx) resolve
        # correctly on both Windows and Unix.
        filepath = filepath.replace('\\', os.sep).replace('/', os.sep)
        resolved_path = resolver(filepath)
        
        if not resolved_path:
            # Check if it looks like a stdlib file used with "" instead of <>
            if resolver.__name__ == "_resolve_path_local" and self._resolve_path_stdlib(filepath):
                print(f'[PREPROCESSOR] Could not find local import: {filepath}', flush=True)
                print(f'#import "{filepath}";', flush=True)
                print(f'--------^', flush=True)
                print(f'#import <{filepath}>; // try this', flush=True)
            raise FileNotFoundError(f"Could not find import: {filepath}")
        
        # Avoid circular imports
        abs_path = str(resolved_path.resolve())
        if abs_path in self.processed_files:
            return
        
        self.processed_files.add(abs_path)
        if self.verbose:
            print(f"[PREPROCESSOR] Processing: {filepath}")
        
        # Read the file and strip comments immediately
        file_content = _read_source_file(resolved_path)
        
        # Strip all comments before processing
        file_content = self._strip_comments(file_content)
        
        # Enforce semicolons on directives before processing
        for lineno, raw_line in enumerate(file_content.splitlines(), start=1):
            s = raw_line.strip()
            if s.startswith("#import") or s.startswith("#package") or s.startswith("#warn") or s.startswith("#stop") or s.startswith("#def") or s.startswith("#dir"):
                if not s.endswith(';'):
                    directive = s.split()[0]
                    raise SyntaxError(f"[PREPROCESSOR] {directive} directive missing semicolon in {filepath} at line {lineno}")
        
        # Process line by line, tracking current file and local line number
        lines = file_content.splitlines()
        prev_current_file = getattr(self, '_current_file', None)
        prev_current_lines = getattr(self, '_current_lines', None)
        self._current_file = str(resolved_path)
        self._current_lines = lines
        # Push this file's directory onto the stack so nested local imports resolve correctly
        self._dir_stack.append(resolved_path.parent)
        i = 0
        while i < len(lines):
            self._current_local_lineno = i + 1  # 1-based
            i = self._process_line(lines, i)
        self._dir_stack.pop()
        self._current_file = prev_current_file
        self._current_lines = prev_current_lines
    
    def _process_line(self, lines: List[str], i: int) -> int:
        """Process a single line, return next line index"""
        line = lines[i]
        
        # Skip empty lines but preserve them in line_map so line numbers stay accurate
        if not line.strip():
            self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
            self.output_lines.append('')
            return i + 1
        
        stripped = line.strip()
        
        # Check for #dir
        if stripped.startswith("#dir"):
            if not stripped.rstrip().endswith(';'):
                raise SyntaxError(f"[PREPROCESSOR] #dir directive missing semicolon at line {i + 1}")
            start_idx = line.find('"')
            if start_idx != -1:
                end_idx = line.find('"', start_idx + 1)
                if end_idx != -1:
                    dir_path = line[start_idx + 1:end_idx]
                    # Normalize: replace backslashes with forward slashes
                    dir_path = dir_path.replace('\\', '/')
                    if dir_path not in self.lib_dirs:
                        self.lib_dirs.append(dir_path)
                        if self.verbose:
                            print(f"[PREPROCESSOR] Added library directory: {dir_path}")
            self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
            self.output_lines.append('')
            return i + 1
        
        # Check for #psub
        if stripped.startswith("#psub"):
            # Collect the full definition, supporting # line continuation.
            # Each line ending with # (after stripping) continues onto the next.
            collected = stripped[len('#psub'):].strip()
            while collected.endswith('#'):
                collected = collected[:-1]  # drop trailing #
                i += 1
                if i >= len(lines):
                    break
                self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
                self.output_lines.append('')
                self._current_local_lineno = i + 1
                collected = collected.rstrip() + ' ' + lines[i].strip()
            rest = collected.strip()
            # Must have NAME(params) body form
            paren_open = rest.find('(')
            if paren_open == -1:
                raise SyntaxError(f"[PREPROCESSOR] #psub missing parameter list at line {i + 1}")
            name = rest[:paren_open].strip()
            paren_close = rest.find(')', paren_open)
            if paren_close == -1:
                raise SyntaxError(f"[PREPROCESSOR] #psub unclosed parameter list at line {i + 1}")
            raw_params = rest[paren_open + 1:paren_close]
            params = [p.strip() for p in raw_params.split(',') if p.strip()]
            body = rest[paren_close + 1:].strip()
            self.psubs[name] = (params, body)
            if self.verbose:
                print(f"[PREPROCESSOR] Defined PSUB: {name}({', '.join(params)}) = {body}")
            self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
            self.output_lines.append('')
            return i + 1

        # Check for #def
        if stripped.startswith("#def"):
            # Find the semicolon
            semicolon_pos = line.find(';')
            if semicolon_pos == -1:
                semicolon_pos = len(line)
            
            # Extract the part up to semicolon
            constant_line = line[:semicolon_pos].strip()
            
            parts = constant_line.split()
            if len(parts) >= 3:
                constant_name = parts[1]
                # Join the rest as the value (skip #def and constant_name)
                constant_value = ' '.join(parts[2:]).strip()
                
                # Remove any trailing semicolon if it's still there
                if constant_value.endswith(';'):
                    constant_value = constant_value.rstrip(';').strip()
                    
                self.constants[constant_name] = constant_value
                if self.verbose:
                    print(f"[PREPROCESSOR] Defined constant: {constant_name} = {constant_value}")
            self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
            self.output_lines.append('')
            return i + 1
        
        # Check for #ifnpsub (must be checked before #ifpsub to avoid prefix clash)
        if stripped.startswith("#ifnpsub"):
            parts = line.split()
            if len(parts) >= 2:
                macro_name = parts[1].split('(')[0].strip()
                return self._process_conditional_block(lines, i, macro_name, True, check_macros=True)

        # Check for #ifpsub
        if stripped.startswith("#ifpsub"):
            parts = line.split()
            if len(parts) >= 2:
                macro_name = parts[1].split('(')[0].strip()
                return self._process_conditional_block(lines, i, macro_name, False, check_macros=True)

        # Check for #ifdef
        if stripped.startswith("#ifdef"):
            parts = line.split()
            if len(parts) >= 2:
                constant_name = parts[1]
                return self._process_conditional_block(lines, i, constant_name, False)
        
        # Check for #ifndef
        if stripped.startswith("#ifndef"):
            parts = line.split()
            if len(parts) >= 2:
                constant_name = parts[1]
                return self._process_conditional_block(lines, i, constant_name, True)
        
        # Check for #package
        if stripped.startswith("#package"):
            if not stripped.rstrip().endswith(';'):
                raise SyntaxError(f"[PREPROCESSOR] #package directive missing semicolon at line {i + 1}")
            rest = stripped[len('#package'):].rstrip(';').strip()
            package_names = [p.strip() for p in rest.split(',') if p.strip()]
            for pkg_name in package_names:
                self._process_package(pkg_name)
            self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
            self.output_lines.append('')
            return i + 1

                # Check for import
        if stripped.startswith("#import"):
            if not stripped.rstrip().endswith(';'):
                raise SyntaxError(f"[PREPROCESSOR] #import directive missing semicolon at line {i + 1}")
            # Determine import kind and extract filenames.
            #
            #   #import "file.fx";          -- local: resolve relative to importing file / root dir / CWD
            #   #import <file.fx>;          -- stdlib: search only stdlib trees
            #   #import @"pkg/file.fx";     -- package: search only .fpm/packages tree
            #
            # Multiple imports on one line are supported for all forms.

            rest = line[line.index('#import') + len('#import'):].rstrip(';').strip()

            # Parse each token from left to right
            j = 0
            while j < len(rest):
                c = rest[j]

                # Stdlib import: <...>
                if c == '<':
                    j += 1
                    end = rest.find('>', j)
                    if end == -1:
                        raise SyntaxError(f"[PREPROCESSOR] Unterminated <> in #import at line {i + 1}")
                    std_path = rest[j:end].strip()
                    if self.verbose:
                        print(f"[PREPROCESSOR] Stdlib import: {std_path}")
                    self._process_file(std_path, resolver=self._resolve_path_stdlib)
                    j = end + 1

                # Local import: "..."
                elif c == '"':
                    j += 1
                    end = rest.find('"', j)
                    if end == -1:
                        raise SyntaxError(f"[PREPROCESSOR] Unterminated \"\" in #import at line {i + 1}")
                    local_path = rest[j:end].strip()
                    if self.verbose:
                        print(f"[PREPROCESSOR] Local import: {local_path}")
                    self._process_file(local_path, resolver=self._resolve_path_local)
                    j = end + 1

                else:
                    j += 1

            self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
            self.output_lines.append('')
            return i + 1
        
        # Check for #warn
        if stripped.startswith("#warn"):
            if not stripped.rstrip().endswith(';'):
                raise SyntaxError(f"[PREPROCESSOR] #warn directive missing semicolon at line {i + 1}")
            start_idx = line.find('"')
            if start_idx != -1:
                end_idx = line.find('"', start_idx + 1)
                if end_idx != -1:
                    message = line[start_idx + 1:end_idx]
                    print(f"[PREPROCESSOR] {message}")
            self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
            self.output_lines.append('')
            return i + 1
        
        # Check for #stop
        if stripped.startswith("#stop"):
            if not stripped.rstrip().endswith(';'):
                raise SyntaxError(f"[PREPROCESSOR] #stop directive missing semicolon at line {i + 1}")
            start_idx = line.find('"')
            if start_idx != -1:
                end_idx = line.find('"', start_idx + 1)
                if end_idx != -1:
                    message = line[start_idx + 1:end_idx]
                    print(f"[PREPROCESSOR] {message}")
            print("Compilation failed, preprocessor stopped by constant.")
            raise SystemExit(1)
        
        # Check for #endif - skip it
        if stripped.startswith("#endif;"):
            self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
            self.output_lines.append('')
            return i + 1
        
        # Check for #else - skip it (handled in conditional processing)
        if stripped == "#else":
            self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
            self.output_lines.append('')
            return i + 1
        
        # Regular line - do constant substitution
        processed_line = self._substitute_constants(line)
        self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
        self.output_lines.append(processed_line)
        return i + 1
    
    def _process_conditional_block(self, lines: List[str], start_i: int, constant_name: str, is_ifndef: bool, check_macros: bool = False) -> int:
        """Process an #ifdef/#ifndef block (with optional #elif/#else) and
        return the next line index after #endif.

        Branch collection pass: walk the block at depth 1, splitting on #elif
        and #else into a list of (condition_fn, lines, origins) branches.
        Then evaluate them in order and process the first true branch.

        Each branch is stored as:
            (condition_fn: callable() -> bool, lines: list[str], origins: list[int])
        condition_fn is a zero-argument callable so evaluation is deferred until
        all branches have been collected (important if a branch defines a constant
        that a later #elif tests -- consistent with standard preprocessor behaviour
        of evaluating conditions lazily in order).
        """
        entry_local_lineno = self._current_local_lineno

        # Emit blank for the opening #ifdef/#ifndef line
        self.line_map.append((getattr(self, '_current_file', self.source_file), self._current_local_lineno))
        self.output_lines.append('')

        # --- Branch collection -------------------------------------------------
        # Each entry: (condition_fn, [(line_text, original_lineno), ...])
        branches = []

        def _make_ifdef_cond(cname, invert):
            def _cond():
                if check_macros:
                    defined = cname in self.psubs
                else:
                    val = self.constants.get(cname)
                    defined = val is not None and val != '0'
                return not defined if invert else defined
            return _cond

        # First branch condition is the opening #ifdef/#ifndef
        current_cond = _make_ifdef_cond(constant_name, is_ifndef)
        current_lines = []   # list of (line_text, original_lineno)
        has_else = False

        i = start_i + 1
        depth = 1

        while i < len(lines):
            line = lines[i]
            stripped = line.strip()
            original_lineno = entry_local_lineno + (i - start_i)

            # Track nesting depth for inner conditionals
            if (stripped.startswith("#ifdef") or stripped.startswith("#ifndef")
                    or stripped.startswith("#ifnpsub") or stripped.startswith("#ifpsub")):
                depth += 1

            # #endif always decrements depth; only act on it when it closes OUR block
            if stripped.startswith("#endif;"):
                depth -= 1
                if depth == 0:
                    # Flush last branch
                    branches.append((current_cond, current_lines))
                    # Emit blank for the #endif line
                    self.line_map.append((getattr(self, '_current_file', self.source_file), original_lineno))
                    self.output_lines.append('')

                    # --- Branch evaluation ---------------------------------
                    # Find the first true branch; all others are excluded.
                    chosen_lines = []
                    chosen_origins = []
                    excluded_origins = []

                    branch_taken = False
                    for cond_fn, blines in branches:
                        if not branch_taken and cond_fn():
                            branch_taken = True
                            for bline, borigin in blines:
                                chosen_lines.append(bline)
                                chosen_origins.append(borigin)
                        else:
                            for _, borigin in blines:
                                excluded_origins.append(borigin)

                    # Emit blanks for all excluded lines so line_map stays in sync
                    for orig in excluded_origins:
                        self.line_map.append((getattr(self, '_current_file', self.source_file), orig))
                        self.output_lines.append('')

                    # Process chosen lines
                    if chosen_lines:
                        j = 0
                        while j < len(chosen_lines):
                            self._current_local_lineno = chosen_origins[j]
                            j = self._process_line(chosen_lines, j)

                    return i + 1
                else:
                    # Inner #endif -- collect as content
                    current_lines.append((line, original_lineno))
                    i += 1
                    continue

            if depth == 1:
                # #elif at our level -- start a new branch
                if stripped.startswith("#elif"):
                    if has_else:
                        raise SyntaxError(f"[PREPROCESSOR] #elif after #else at line {i + 1}")
                    # Save current branch
                    branches.append((current_cond, current_lines))
                    current_lines = []
                    # Parse condition: #elif SYMBOL  or  #elif defined(SYMBOL)
                    rest = stripped[len('#elif'):].rstrip(';').strip()
                    cname, invert = self._parse_ifdef_condition(rest, i + 1)
                    current_cond = _make_ifdef_cond(cname, invert)
                    # Emit blank for the #elif line
                    self.line_map.append((getattr(self, '_current_file', self.source_file), original_lineno))
                    self.output_lines.append('')
                    i += 1
                    continue

                # #else at our level
                if stripped == "#else" or stripped == "#else;":
                    if has_else:
                        raise SyntaxError(f"[PREPROCESSOR] Multiple #else in same conditional block at line {i + 1}")
                    has_else = True
                    branches.append((current_cond, current_lines))
                    current_lines = []
                    # #else branch always true (first-true-wins logic handles it)
                    current_cond = lambda: True
                    # Emit blank for the #else line
                    self.line_map.append((getattr(self, '_current_file', self.source_file), original_lineno))
                    self.output_lines.append('')
                    i += 1
                    continue

            # Ordinary line (or inner-block directive) -- collect into current branch
            current_lines.append((line, original_lineno))
            i += 1

        raise SyntaxError(f"Unclosed conditional block starting at line {start_i + 1}")

    def _parse_ifdef_condition(self, expr: str, lineno: int):
        """Parse a condition expression from #ifdef, #ifndef, or #elif.

        Supported forms:
            SYMBOL              -> (SYMBOL, is_ifndef=False)
            defined(SYMBOL)     -> (SYMBOL, is_ifndef=False)
            !defined(SYMBOL)    -> (SYMBOL, is_ifndef=True)

        Returns (constant_name: str, is_ifndef: bool).
        Raises SyntaxError for unsupported expressions.
        """
        import re
        expr = expr.strip()

        # defined(X)
        m = re.match(r'^defined\s*\(\s*(\w+)\s*\)$', expr)
        if m:
            return m.group(1), False

        # !defined(X)
        m = re.match(r'^!\s*defined\s*\(\s*(\w+)\s*\)$', expr)
        if m:
            return m.group(1), True

        # Plain identifier
        m = re.match(r'^\w+$', expr)
        if m:
            return expr, False

        raise SyntaxError(
            f"[PREPROCESSOR] Unsupported #elif condition '{expr}' at line {lineno}. "
            "Only 'SYMBOL', 'defined(SYMBOL)', and '!defined(SYMBOL)' are supported."
        )
    
    def _expand_macros(self, line: str, _depth: int = 0) -> str:
        """Expand #psub parameterized macros in a line.

        Scans the line for NAME(...) call sites where NAME is a known macro,
        substitutes positional arguments into the body, then recurses to handle
        macros that expand to other macro calls.  A depth limit guards against
        infinite recursion.
        """
        MAX_DEPTH = 64
        if _depth > MAX_DEPTH:
            raise RecursionError(f"[PREPROCESSOR] Macro expansion exceeded depth limit ({MAX_DEPTH}). Possible infinite recursion.")

        if not self.psubs:
            return line

        result = []
        i = 0
        n = len(line)
        changed = False

        while i < n:
            # Collect an identifier
            if line[i].isalpha() or line[i] == '_':
                j = i
                while j < n and (line[j].isalnum() or line[j] == '_'):
                    j += 1
                name = line[i:j]

                if name in self.psubs and j < n and line[j] == '(':
                    # Found a macro call -- extract the argument list
                    params, body = self.psubs[name]
                    # Find matching closing paren, respecting nesting and strings
                    k = j + 1  # start after '('
                    depth = 1
                    in_str = False
                    str_char = ''
                    while k < n and depth > 0:
                        c = line[k]
                        if in_str:
                            if c == '\\':
                                k += 1  # skip escaped char
                            elif c == str_char:
                                in_str = False
                        else:
                            if c in ('"', "'"):
                                in_str = True
                                str_char = c
                            elif c == '(':
                                depth += 1
                            elif c == ')':
                                depth -= 1
                        k += 1
                    # k now points one past the closing ')'
                    raw_args = line[j + 1:k - 1]

                    # Split args by top-level commas
                    args = self._split_macro_args(raw_args)

                    if len(args) != len(params):
                        raise SyntaxError(
                            f"[PREPROCESSOR] Macro '{name}' expects {len(params)} argument(s), "
                            f"got {len(args)}: '{line[i:k]}'"
                        )

                    # Substitute params into body
                    expanded = body
                    for param, arg in zip(params, args):
                        # Whole-word replacement only
                        import re
                        expanded = re.sub(r'\b' + re.escape(param) + r'\b', arg.strip(), expanded)

                    result.append(expanded)
                    changed = True
                    i = k
                else:
                    result.append(name)
                    i = j
            else:
                result.append(line[i])
                i += 1

        expanded_line = ''.join(result)
        # Recurse if anything changed (handles macros expanding to macro calls)
        if changed:
            return self._expand_macros(expanded_line, _depth + 1)
        return expanded_line

    def _split_macro_args(self, raw: str) -> List[str]:
        """Split a raw argument string by top-level commas (respecting
        nested parentheses and string literals)."""
        args = []
        current = []
        depth = 0
        in_str = False
        str_char = ''
        for c in raw:
            if in_str:
                current.append(c)
                if c == str_char:
                    in_str = False
            elif c in ('"', "'"):
                in_str = True
                str_char = c
                current.append(c)
            elif c == '(':
                depth += 1
                current.append(c)
            elif c == ')':
                depth -= 1
                current.append(c)
            elif c == ',' and depth == 0:
                args.append(''.join(current))
                current = []
            else:
                current.append(c)
        if current or args:
            args.append(''.join(current))
        return args

    def _substitute_constants(self, line: str) -> str:
        """Expand macros then substitute scalar constants."""
        # First pass: expand any #psub parameterized macros
        line = self._expand_macros(line)

        # Second pass: scalar constant substitution
        if not line or line.strip() == ';':
            return line
        
        # Split line into tokens, preserving whitespace structure
        result_parts = []
        in_quotes = False
        current_token = ""
        
        for char in line:
            if char == '"':
                in_quotes = not in_quotes
                current_token += char
            elif char.isspace() or char in '.,;:()[]{}+-*/%=!<>|&^~':
                # End of token
                if current_token:
                    # Check if token is a constant
                    if not in_quotes and current_token in self.constants:
                        # Get constant value and strip trailing semicolon if present
                        constant_value = self.constants[current_token]
                        # Remove trailing semicolon if it's at the end
                        if constant_value.endswith(';'):
                            constant_value = constant_value.rstrip(';').strip()
                        result_parts.append(constant_value)
                    else:
                        result_parts.append(current_token)
                    current_token = ""
                result_parts.append(char)
            else:
                current_token += char
        
        # Handle last token
        if current_token:
            if not in_quotes and current_token in self.constants:
                constant_value = self.constants[current_token]
                # Remove trailing semicolon if it's at the end
                if constant_value.endswith(';'):
                    constant_value = constant_value.rstrip(';').strip()
                result_parts.append(constant_value)
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