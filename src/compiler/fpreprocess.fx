// Flux Preprocessor - fpreprocess.fx
// Based on fpreprocess.py - Implements the Flux source preprocessor in Flux.
// Handles: #import, #def, #ifdef, #ifndef, #else, #endif, #warn, #stop
// and macro substitution across all processed source lines.

#import "standard.fx";
#import "file_object_raw.fx";
#import "string_object_raw.fx";

using standard::io::file;
using standard::strings;

// Declare system() for directory creation on all platforms
#ifndef __WINDOWS__
extern
{
    def !!
        system(byte*) -> int;
};
#endif;

// ============================================================
// Simple dynamic string buffer for building output
// ============================================================

object StringBuffer
{
    byte* buf;
    int   length;
    int   capacity;

    def __init() -> this
    {
        this.capacity = 4096;
        this.buf     = (byte*)malloc((u64)this.capacity);
        this.length   = 0;
        if (this.buf != (byte*)0)
        {
            this.buf[0] = (byte)0;
        };
        return this;
    };

    def __exit() -> void
    {
        return;
    };

    // Ensure at least `needed` additional bytes are available
    def ensure(int needed) -> bool
    {
        if (this.length + needed + 1 < this.capacity)
        {
            return true;
        };
        int new_cap = this.capacity * 2 + needed + 1;
        byte* new_buf = (byte*)realloc(this.buf, (u64)new_cap);
        if (new_buf == (byte*)0)
        {
            return false;
        };
        this.buf     = new_buf;
        this.capacity = new_cap;
        return true;
    };

    // Append a null-terminated string
    def append(byte* s) -> bool
    {
        int slen = strlen(s);
        if (!this.ensure(slen))
        {
            return false;
        };
        int i = 0;
        while (i < slen)
        {
            this.buf[this.length] = s[i];
            this.length = this.length + 1;
            i = i + 1;
        };
        this.buf[this.length] = (byte)0;
        return true;
    };

    // Append a single character
    def append_char(char c) -> bool
    {
        if (!this.ensure(1))
        {
            return false;
        };
        this.buf[this.length] = (byte)c;
        this.length = this.length + 1;
        this.buf[this.length] = (byte)0;
        return true;
    };

    // Return pointer to accumulated data
    def val() -> byte*
    {
        return this.buf;
    };
};

// ============================================================
// Simple macro table (name->value, fixed-size hash map)
// ============================================================

#def MACRO_TABLE_SIZE 256;

struct MacroEntry
{
    byte* name;
    byte* value;
    bool  used;
};

object MacroTable
{
    MacroEntry[MACRO_TABLE_SIZE] entries;
    int count;

    def __init() -> this
    {
        int i = 0;
        while (i < MACRO_TABLE_SIZE)
        {
            this.entries[i].used  = false;
            this.entries[i].name  = (byte*)0;
            this.entries[i].value = (byte*)0;
            i = i + 1;
        };
        this.count = 0;
        return this;
    };

    def __exit() -> void
    {
        return;
    };

    // Simple hash: sum of bytes mod table size
    def hash(byte* key) -> int
    {
        int h = 0;
        int i = 0;
        while (key[i] != (byte)0)
        {
            h = h + (int)key[i];
            i = i + 1;
        };
        int mod = h % MACRO_TABLE_SIZE;
        if (mod < 0)
        {
            mod = mod + MACRO_TABLE_SIZE;
        };
        return mod;
    };

    // Insert or update a macro
    def set(byte* name, byte* value) -> bool
    {
        int slot = this.hash(name);
        int start = slot;
        while (this.entries[slot].used)
        {
            if (strcmp(this.entries[slot].name, name) == 0)
            {
                // Update existing
                this.entries[slot].value = copy_string(value);
                return true;
            };
            slot = (slot + 1) % MACRO_TABLE_SIZE;
            if (slot == start)
            {
                return false; // Table full
            };
        };
        this.entries[slot].used  = true;
        this.entries[slot].name  = copy_string(name);
        this.entries[slot].value = copy_string(value);
        this.count = this.count + 1;
        return true;
    };

    // Look up a macro, returns null if not found
    def get(byte* name) -> byte*
    {
        int slot = this.hash(name);
        int start = slot;
        while (this.entries[slot].used)
        {
            if (strcmp(this.entries[slot].name, name) == 0)
            {
                return this.entries[slot].value;
            };
            slot = (slot + 1) % MACRO_TABLE_SIZE;
            if (slot == start)
            {
                return (byte*)0;
            };
        };
        return (byte*)0;
    };

    // Returns true if the macro is defined (even if value is "0")
    def has(byte* name) -> bool
    {
        return this.get(name) != (byte*)0;
    };

    // Returns true if macro is defined AND value is not "0"
    def is_true(byte* name) -> bool
    {
        byte* v = this.get(name);
        if (v == (byte*)0)
        {
            return false;
        };
        if (v[0] == (byte)'0' & v[1] == (byte)0)
        {
            return false;
        };
        return true;
    };
};

// ============================================================
// Processed-file set (to prevent circular imports)
// ============================================================

#def PROCESSED_SET_SIZE 512;

object ProcessedSet
{
    byte[PROCESSED_SET_SIZE]* paths;
    int count;

    def __init() -> this
    {
        int i = 0;
        while (i < PROCESSED_SET_SIZE)
        {
            this.paths[i] = (byte*)0;
            i = i + 1;
        };
        this.count = 0;
        return this;
    };

    def __exit() -> void
    {
        return;
    };

    def contains(byte* path) -> bool
    {
        int i = 0;
        while (i < this.count)
        {
            if (strcmp(this.paths[i], path) == 0)
            {
                return true;
            };
            i = i + 1;
        };
        return false;
    };

    def add(byte* path) -> bool
    {
        if (this.count >= PROCESSED_SET_SIZE)
        {
            return false;
        };
        this.paths[this.count] = copy_string(path);
        this.count = this.count + 1;
        return true;
    };
};

// ============================================================
// Preprocessor object
// ============================================================

object FXPreprocessor
{
    byte*         source_file;
    MacroTable    macros;
    ProcessedSet  processed;
    StringBuffer  output;
    int           file_count;

    def __init(byte* src) -> this
    {
        this.source_file = src;
        this.file_count  = 0;
        return this;
    };

    def __exit() -> void
    {
        return;
    };

    // --------------------------------------------------------
    // Utility: check if character is identifier-valid
    // --------------------------------------------------------
    def is_ident_char(char c) -> bool
    {
        if (is_alpha(c))  { return true; };
        if (is_digit(c))  { return true; };
        if (c == '_')     { return true; };
        return false;
    };

    // --------------------------------------------------------
    // Utility: copy N bytes from src into a new heap buffer
    // --------------------------------------------------------
    def copy_n_str(byte* src, int n) -> byte*
    {
        byte* buf = (byte*)malloc((u64)n + 1);
        if (buf == (byte*)0) { return (byte*)0; };
        int i = 0;
        while (i < n)
        {
            buf[i] = src[i];
            i = i + 1;
        };
        buf[n] = (byte)0;
        return buf;
    };

    // --------------------------------------------------------
    // Utility: trim leading whitespace, returns pointer into src
    // --------------------------------------------------------
    def ltrim(byte* s) -> byte*
    {
        while (s[0] == ' ' | s[0] == '\t' | s[0] == '\r')
        {
            s = s + 1;
        };
        return s;
    };

    // --------------------------------------------------------
    // Utility: length of a line up to (but not including) '\n' or '\0'
    // --------------------------------------------------------
    def line_len(byte* s) -> int
    {
        int n = 0;
        while (s[n] != (byte)0 & s[n] != '\n')
        {
            n = n + 1;
        };
        return n;
    };

    // --------------------------------------------------------
    // Utility: does line (up to its end) end with ';'?
    // ignores trailing whitespace and \r
    // --------------------------------------------------------
    def line_ends_with_semi(byte* line) -> bool
    {
        int n = this.line_len(line);
        // Walk backwards past spaces, tabs, \r
        while (n > 0)
        {
            n = n - 1;
            char c = (char)line[n];
            if (c != ' ' & c != '\t' & c != '\r')
            {
                return c == ';';
            };
        };
        return false;
    };

    // --------------------------------------------------------
    // Strip block (///) and line (//) comments from content.
    // Returns new heap-allocated string.
    // --------------------------------------------------------
    def strip_comments(byte* content) -> byte*
    {
        int n = strlen(content);
        byte* result = (byte*)malloc((u64)n + 1);
        if (result == (byte*)0) { return content; };

        int ri = 0;
        int i  = 0;

        while (i < n)
        {
            // Check for /// block comment
            if (content[i] == '/' & content[i+1] == '/' & content[i+2] == '/')
            {
                i = i + 3;
                while (i < n)
                {
                    if (content[i] == '/' & content[i+1] == '/' & content[i+2] == '/')
                    {
                        i = i + 3;
                        break;
                    };
                    i = i + 1;
                };
                continue;
            };

            // Check for // line comment
            if (content[i] == '/' & content[i+1] == '/')
            {
                while (i < n & content[i] != '\n')
                {
                    i = i + 1;
                };
                continue;
            };

            result[ri] = content[i];
            ri = ri + 1;
            i  = i + 1;
        };
        result[ri] = (byte)0;
        return result;
    };

    // --------------------------------------------------------
    // Substitute macros in a single line.
    // Returns new heap-allocated string.
    // --------------------------------------------------------
    def substitute_macros(byte* line) -> byte*
    {
        int n = strlen(line);
        if (n == 0) { return copy_string(line); };

        StringBuffer buf;
        bool in_quotes = false;
        int i = 0;

        while (i < n)
        {
            char c = (char)line[i];

            if (c == '"')
            {
                in_quotes = !in_quotes;
                buf.append_char(c);
                i = i + 1;
                continue;
            };

            // Inside a quoted string - copy verbatim
            if (in_quotes)
            {
                buf.append_char(c);
                i = i + 1;
                continue;
            };

            // Start of an identifier token?
            if (is_alpha(c) | c == '_')
            {
                // Collect full identifier
                int start = i;
                while (i < n & this.is_ident_char((char)line[i]))
                {
                    i = i + 1;
                };
                int toklen = i - start;
                byte* tok = this.copy_n_str(line + start, toklen);

                // Check if it's a macro
                byte* mval = this.macros.get(tok);
                if (mval != (byte*)0)
                {
                    // Strip trailing semicolon from value if present
                    int vlen = strlen(mval);
                    if (vlen > 0 & mval[vlen - 1] == ';')
                    {
                        byte* trimmed = this.copy_n_str(mval, vlen - 1);
                        buf.append(trimmed);
                        free(trimmed);
                    }
                    else
                    {
                        buf.append(mval);
                    };
                }
                else
                {
                    buf.append(tok);
                };
                free(tok);
            }
            else
            {
                buf.append_char(c);
                i = i + 1;
            };
        };

        byte* result = copy_string(buf.val());
        return result;
    };

    // --------------------------------------------------------
    // Resolve an import path to an actual file path.
    // Returns heap-allocated path string, or null if not found.
    // --------------------------------------------------------
    def resolve_path(byte* filepath) -> byte*
    {
        // Try as given
        if (file_exists(filepath))
        {
            return copy_string(filepath);
        };

        // Try common stdlib subdirectories
        byte[5]* prefixes;
        prefixes[0] = "src/stdlib/\0";
        prefixes[1] = "src/stdlib/runtime/\0";
        prefixes[2] = "src/stdlib/functions/\0";
        prefixes[3] = "src/stdlib/builtins/\0";
        prefixes[4] = (byte*)0;

        int pi = 0;
        while (prefixes[pi] != (byte*)0)
        {
            // Build candidate path
            StringBuffer candidate;
            candidate.append(prefixes[pi]);
            candidate.append(filepath);
            byte* cpath = copy_string(candidate.val());

            if (file_exists(cpath))
            {
                return cpath;
            };
            free(cpath);
            pi = pi + 1;
        };

        return (byte*)0;
    };

    // --------------------------------------------------------
    // Forward declaration for mutual recursion
    // --------------------------------------------------------
    def process_file(byte* filepath) -> bool;
    def process_lines(byte* content) -> bool;
    def process_conditional(byte* content, int start, bool is_ifndef) -> int;

    // --------------------------------------------------------
    // Process a file: read it, strip comments, handle lines
    // --------------------------------------------------------
    def process_file(byte* filepath) -> bool
    {
        byte* resolved = this.resolve_path(filepath);
        if (resolved == (byte*)0)
        {
            print("[PREPROCESSOR] ERROR: Could not find import: \0");
            print(filepath);
            print("\n\0");
            return false;
        };

        // Check for circular imports
        if (this.processed.contains(resolved))
        {
            free(resolved);
            return true;
        };

        this.processed.add(resolved);
        this.file_count = this.file_count + 1;

        print("[PREPROCESSOR] Processing: \0");
        print(filepath);
        print("\n\0");

        // Open and read file
        file f(resolved, "rb\0");
        if (!f.is_open())
        {
            print("[PREPROCESSOR] ERROR: Failed to open: \0");
            print(resolved);
            print("\n\0");
            free(resolved);
            return false;
        };

        string content_str = f.read_all();
        f.close();
        free(resolved);

        byte* raw = content_str.val();

        // Validate semicolons on directives
        // Walk line by line and check #import, #warn, #stop, #def
        {
            int pos = 0;
            int lineno = 1;
            int rlen = strlen(raw);
            while (pos < rlen)
            {
                // Find start and end of current line
                int ls = pos;
                while (pos < rlen & raw[pos] != '\n')
                {
                    pos = pos + 1;
                };
                int le = pos;
                if (pos < rlen) { pos = pos + 1; }; // consume '\n'

                // Build line copy
                int ll = le - ls;
                byte* line = this.copy_n_str(raw + ls, ll);
                byte* trimmed = this.ltrim(line);

                bool need_semi = false;
                if (starts_with(trimmed, "#import\0"))  { need_semi = true; };
                if (starts_with(trimmed, "#warn\0"))    { need_semi = true; };
                if (starts_with(trimmed, "#stop\0"))    { need_semi = true; };
                if (starts_with(trimmed, "#def\0"))     { need_semi = true; };

                if (need_semi & !this.line_ends_with_semi(trimmed))
                {
                    print("[PREPROCESSOR] ERROR: Directive missing semicolon in \0");
                    print(filepath);
                    print(" at line \0");
                    byte[16] nbuf;
                    i32str(lineno, nbuf);
                    print(nbuf);
                    print("\n\0");
                    free(line);
                    return false;
                };

                free(line);
                lineno = lineno + 1;
            };
        };

        // Strip comments
        byte* stripped = this.strip_comments(raw);

        // Process lines
        bool ok = this.process_lines(stripped);

        free(stripped);
        return ok;
    };

    // --------------------------------------------------------
    // Process content line by line.
    // Returns false on fatal error.
    // --------------------------------------------------------
    def process_lines(byte* content) -> bool
    {
        int pos   = 0;
        int clen  = strlen(content);

        while (pos < clen)
        {
            // Find line boundaries
            int ls = pos;
            while (pos < clen & content[pos] != '\n')
            {
                pos = pos + 1;
            };
            int le = pos;
            if (pos < clen) { pos = pos + 1; }; // consume '\n'

            int ll = le - ls;
            byte* line = this.copy_n_str(content + ls, ll);
            byte* trimmed = this.ltrim(line);

            // Skip empty lines
            if (trimmed[0] == (byte)0 | (trimmed[0] == '\r' & trimmed[1] == (byte)0))
            {
                free(line);
                continue;
            };

            // ---- #def ----
            if (starts_with(trimmed, "#def\0"))
            {
                // Find semicolon (already validated)
                int semi = find_char(trimmed, ';', 0);
                int macro_end = semi;
                if (macro_end < 0) { macro_end = strlen(trimmed); };

                // Extract portion: "#def NAME VALUE"
                byte* mline = this.copy_n_str(trimmed, macro_end);

                // Parse: skip "#def", skip whitespace, read name, rest is value
                int mp = 4; // after "#def"
                while (mline[mp] == ' ' | mline[mp] == '\t') { mp = mp + 1; };

                // Read name
                int name_start = mp;
                while (mline[mp] != (byte)0 & mline[mp] != ' ' & mline[mp] != '\t')
                {
                    mp = mp + 1;
                };
                int name_len = mp - name_start;
                byte* mname = this.copy_n_str(mline + name_start, name_len);

                // Skip whitespace to value
                while (mline[mp] == ' ' | mline[mp] == '\t') { mp = mp + 1; };
                byte* mval_raw = mline + mp;

                // Strip trailing semicolon from value
                int vlen = strlen(mval_raw);
                while (vlen > 0 & (mval_raw[vlen-1] == ';' | mval_raw[vlen-1] == ' ' | mval_raw[vlen-1] == '\t'))
                {
                    vlen = vlen - 1;
                };
                byte* mval = this.copy_n_str(mval_raw, vlen);

                this.macros.set(mname, mval);

                print("[PREPROCESSOR] Defined macro: \0");
                print(mname);
                print(" = \0");
                print(mval);
                print("\n\0");

                free(mname);
                free(mval);
                free(mline);
                free(line);
                continue;
            };

            // ---- #ifdef ----
            if (starts_with(trimmed, "#ifdef\0"))
            {
                // Extract macro name
                int mp = 6;
                while (trimmed[mp] == ' ' | trimmed[mp] == '\t') { mp = mp + 1; };
                int name_start = mp;
                while (trimmed[mp] != (byte)0 & trimmed[mp] != ' ' & trimmed[mp] != '\t' & trimmed[mp] != '\r' & trimmed[mp] != ';')
                {
                    mp = mp + 1;
                };
                byte* mname = this.copy_n_str(trimmed + name_start, mp - name_start);

                // We need to process the conditional block.
                // Re-build content from current pos and handle inline.
                // Since we've already split off this line, we need to work from the
                // remaining content. Build a sub-buffer for the rest.

                // Remaining content starts at 'pos' in parent content.
                // We pass it to process_conditional which handles depth tracking.
                // process_conditional returns the new position.

                byte* remaining = content + pos;
                int new_pos = this.process_conditional(remaining, 0, false);
                if (new_pos < 0)
                {
                    print("[PREPROCESSOR] ERROR: Unclosed #ifdef block\n\0");
                    free(mname);
                    free(line);
                    return false;
                };

                // Determine if macro is true
                bool cond_true = this.macros.is_true(mname);
                free(mname);

                // Collect the if-block and else-block from remaining
                // We need to re-parse the block to pick the right branch
                // process_conditional_branch does this properly.
                bool ok = this.handle_conditional_block(remaining, false, cond_true);
                if (!ok)
                {
                    free(line);
                    return false;
                };

                // Advance past the entire conditional block
                pos = pos + this.skip_conditional_block(remaining);
                free(line);
                continue;
            };

            // ---- #ifndef ----
            if (starts_with(trimmed, "#ifndef\0"))
            {
                int mp = 7;
                while (trimmed[mp] == ' ' | trimmed[mp] == '\t') { mp = mp + 1; };
                int name_start = mp;
                while (trimmed[mp] != (byte)0 & trimmed[mp] != ' ' & trimmed[mp] != '\t' & trimmed[mp] != '\r' & trimmed[mp] != ';')
                {
                    mp = mp + 1;
                };
                byte* mname = this.copy_n_str(trimmed + name_start, mp - name_start);

                byte* remaining = content + pos;
                bool cond_false = !this.macros.is_true(mname);

                // For #ifndef: condition is true when macro is NOT defined/true
                bool ok = this.handle_conditional_block(remaining, true, cond_false);
                free(mname);
                if (!ok)
                {
                    free(line);
                    return false;
                };

                pos = pos + this.skip_conditional_block(remaining);
                free(line);
                continue;
            };

            // ---- #import ----
            if (starts_with(trimmed, "#import\0"))
            {
                // Extract all quoted filenames
                int tp = 0;
                int tlen = strlen(trimmed);
                while (tp < tlen)
                {
                    if (trimmed[tp] == '"')
                    {
                        tp = tp + 1;
                        int fname_start = tp;
                        while (tp < tlen & trimmed[tp] != '"')
                        {
                            tp = tp + 1;
                        };
                        if (tp < tlen)
                        {
                            byte* fname = this.copy_n_str(trimmed + fname_start, tp - fname_start);
                            bool ok = this.process_file(fname);
                            free(fname);
                            if (!ok)
                            {
                                free(line);
                                return false;
                            };
                            tp = tp + 1; // skip closing quote
                        };
                    }
                    else
                    {
                        tp = tp + 1;
                    };
                };
                free(line);
                continue;
            };

            // ---- #warn ----
            if (starts_with(trimmed, "#warn\0"))
            {
                int tp = find_char(trimmed, '"', 0);
                if (tp >= 0)
                {
                    tp = tp + 1;
                    int msg_start = tp;
                    int tlen = strlen(trimmed);
                    while (tp < tlen & trimmed[tp] != '"') { tp = tp + 1; };
                    byte* msg = this.copy_n_str(trimmed + msg_start, tp - msg_start);
                    print("[PREPROCESSOR] \0");
                    print(msg);
                    print("\n\0");
                    free(msg);
                };
                free(line);
                continue;
            };

            // ---- #stop ----
            if (starts_with(trimmed, "#stop\0"))
            {
                int tp = find_char(trimmed, '"', 0);
                if (tp >= 0)
                {
                    tp = tp + 1;
                    int msg_start = tp;
                    int tlen = strlen(trimmed);
                    while (tp < tlen & trimmed[tp] != '"') { tp = tp + 1; };
                    byte* msg = this.copy_n_str(trimmed + msg_start, tp - msg_start);
                    print("[PREPROCESSOR] \0");
                    print(msg);
                    print("\n\0");
                    free(msg);
                };
                print("Compilation failed, preprocessor stopped by macro.\n\0");
                free(line);
                exit(1);
                return false;
            };

            // ---- #endif (stray - skip) ----
            if (starts_with(trimmed, "#endif\0"))
            {
                free(line);
                continue;
            };

            // ---- #else (stray - skip) ----
            if (starts_with(trimmed, "#else\0"))
            {
                free(line);
                continue;
            };

            // ---- Regular line: macro substitution ----
            byte* subst = this.substitute_macros(line);
            this.output.append(subst);
            this.output.append_char('\n');
            free(subst);
            free(line);
        };

        return true;
    };

    // --------------------------------------------------------
    // Skip over a full conditional block in `content` starting
    // right after the opening #ifdef/#ifndef line.
    // Returns number of bytes consumed.
    // --------------------------------------------------------
    def skip_conditional_block(byte* content) -> int
    {
        int pos   = 0;
        int clen  = strlen(content);
        int depth = 1;

        while (pos < clen & depth > 0)
        {
            int ls = pos;
            while (pos < clen & content[pos] != '\n') { pos = pos + 1; };
            int le = pos;
            if (pos < clen) { pos = pos + 1; };

            int ll = le - ls;
            byte* line = this.copy_n_str(content + ls, ll);
            byte* t = this.ltrim(line);

            if (starts_with(t, "#ifdef\0") | starts_with(t, "#ifndef\0"))
            {
                depth = depth + 1;
            }
            elif (starts_with(t, "#endif\0"))
            {
                depth = depth - 1;
            };

            free(line);
        };

        return pos;
    };

    // --------------------------------------------------------
    // Handle a conditional block from `content` (right after the
    // opening directive line).
    // is_ifndef: true if this was #ifndef, false if #ifdef.
    // cond_true: whether the condition evaluates to true.
    // --------------------------------------------------------
    def handle_conditional_block(byte* content, bool is_ifndef, bool cond_true) -> bool
    {
        int pos   = 0;
        int clen  = strlen(content);
        int depth = 1;

        // Two string buffers: one for the "if" branch, one for "else" branch
        StringBuffer if_buf;
        StringBuffer else_buf;
        bool in_else = false;

        while (pos < clen & depth > 0)
        {
            int ls = pos;
            while (pos < clen & content[pos] != '\n') { pos = pos + 1; };
            int le = pos;
            if (pos < clen) { pos = pos + 1; };

            int ll = le - ls;
            byte* line = this.copy_n_str(content + ls, ll);
            byte* t = this.ltrim(line);

            if (starts_with(t, "#ifdef\0") | starts_with(t, "#ifndef\0"))
            {
                depth = depth + 1;
                // Include nested directive in current branch
                if (!in_else)
                {
                    if_buf.append(line);
                    if_buf.append_char('\n');
                }
                else
                {
                    else_buf.append(line);
                    else_buf.append_char('\n');
                };
            }
            elif (starts_with(t, "#else\0") & depth == 1)
            {
                in_else = true;
            }
            elif (starts_with(t, "#endif\0"))
            {
                depth = depth - 1;
                if (depth > 0)
                {
                    // Nested #endif - include in current branch
                    if (!in_else)
                    {
                        if_buf.append(line);
                        if_buf.append_char('\n');
                    }
                    else
                    {
                        else_buf.append(line);
                        else_buf.append_char('\n');
                    };
                };
            }
            else
            {
                // Regular line or nested directive body
                if (!in_else)
                {
                    if_buf.append(line);
                    if_buf.append_char('\n');
                }
                else
                {
                    else_buf.append(line);
                    else_buf.append_char('\n');
                };
            };

            free(line);
        };

        // Now process the correct branch
        if (cond_true)
        {
            byte* branch = if_buf.val();
            if (strlen(branch) > 0)
            {
                return this.process_lines(branch);
            };
        }
        else
        {
            byte* branch = else_buf.val();
            if (strlen(branch) > 0)
            {
                return this.process_lines(branch);
            };
        };

        return true;
    };

    // process_conditional is used only for error-checking; real work is in handle_conditional_block
    def process_conditional(byte* content, int start, bool is_ifndef) -> int
    {
        // Validate block is closed
        int pos   = start;
        int clen  = strlen(content);
        int depth = 1;
        while (pos < clen & depth > 0)
        {
            int ls = pos;
            while (pos < clen & content[pos] != '\n') { pos = pos + 1; };
            int le = pos;
            if (pos < clen) { pos = pos + 1; };
            int ll = le - ls;
            byte* line = this.copy_n_str(content + ls, ll);
            byte* t = this.ltrim(line);
            if (starts_with(t, "#ifdef\0") | starts_with(t, "#ifndef\0"))
            {
                depth = depth + 1;
            }
            elif (starts_with(t, "#endif\0"))
            {
                depth = depth - 1;
            };
            free(line);
        };
        if (depth != 0)
        {
            return -1;
        };
        return pos;
    };

    // --------------------------------------------------------
    // Main processing pipeline
    // --------------------------------------------------------
    def process() -> bool
    {
        // Process the source file
        bool ok = this.process_file(this.source_file);
        if (!ok)
        {
            return false;
        };

        // Macro substitution passes
        bool replaced = true;
        int iteration = 0;
        while (replaced)
        {
            iteration = iteration + 1;
            byte[16] ibuf;
            i32str(iteration, ibuf);
            print("[PREPROCESSOR] Macro substitution passes: \0");
            print(ibuf);
            print("\n\0");

            replaced = false;
            byte* combined = copy_string(this.output.val());
            int clen = strlen(combined);

            // Reset output buffer
            this.output.length = 0;
            if (this.output.buf != (byte*)0)
            {
                this.output.buf[0] = (byte)0;
            };

            // Process line by line
            int pos = 0;
            while (pos < clen)
            {
                int ls = pos;
                while (pos < clen & combined[pos] != '\n') { pos = pos + 1; };
                int le = pos;
                if (pos < clen) { pos = pos + 1; };

                byte* line = this.copy_n_str(combined + ls, le - ls);
                byte* subst = this.substitute_macros(line);

                if (strcmp(subst, line) != 0)
                {
                    replaced = true;
                };

                this.output.append(subst);
                this.output.append_char('\n');
                free(subst);
                free(line);
            };
            free(combined);
        };

        // Print completion message
        if (iteration > 1)
        {
            byte[16] ibuf2;
            i32str(iteration, ibuf2);
            print("[PREPROCESSOR] Completed after \0");
            print(ibuf2);
            print(" macro passes.\n\0");
        }
        else
        {
            print("[PREPROCESSOR] Completed after 1 macro pass.\n\0");
        };

        // Write output to build/tmp.fx
        // Ensure build directory exists
        #ifdef __LINUX__
        system("mkdir -p build\0");
        #endif;
        #ifdef __MACOS__
        system("mkdir -p build\0");
        #endif;
        #ifdef __WINDOWS__
        system("mkdir build 2>nul\0");
        #endif;

        byte* out_path = "build/tmp.fx\0";
        file out_f(out_path, "wb\0");
        if (!out_f.is_open())
        {
            print("[PREPROCESSOR] ERROR: Could not open output file: build/tmp.fx\n\0");
            return false;
        };

        byte* final_out = this.output.val();
        int final_len   = this.output.length;
        out_f.write_bytes(final_out, final_len);
        out_f.close();

        print("[PREPROCESSOR] Generated: build/tmp.fx\n\0");

        byte[16] fbuf;
        i32str(this.file_count, fbuf);
        print("[PREPROCESSOR] Processed \0");
        print(fbuf);
        print(" file(s)\n\0");

        return true;
    };
};

// ============================================================
// Entry point
// ============================================================

def main(int argc, byte** argv) -> int
{
    if (argc == 0)
    {
        print("Usage: fpreprocess <source_file.fx>\n\0");
        return 1;
    }
    elif (argc == 2)
    {
        byte* source = argv[1];

        FXPreprocessor pp(source);
        bool ok = pp.process();

        if (!ok)
        {
            return 1;
        };

        return 0;
    }
    else
    {
        print("Usage: fpreprocess <source_file.fx>\n\0");
        return 1;
    };

    return 0;
};
