// Flux Preprocessor written in Flux
// Port of fpreprocess.py to native Flux
// Handles #import, #def, #ifdef, #ifndef, #else, #endif

#import "redminstandard.fx", "ffifio.fx";

// Simple dynamic string implementation for preprocessor
struct String
{
    byte* xdata;
    int length;
    int capacity;
};

// Simple dynamic array of strings
struct StringArray
{
    String* xdata;
    int length;
    int capacity;
};

// Macro entry: name and value
struct Macro
{
    String name;
    String value;
};

// Dynamic array of macros
struct MacroTable
{
    Macro* xdata;
    int length;
    int capacity;
};

// Set of processed file paths
struct FileSet
{
    String* paths;
    int count;
    int capacity;
};

// Main preprocessor state
struct Preprocessor
{
    String source_file;
    FileSet processed_files;
    StringArray output_lines;
    MacroTable macros;
};

// ===== STRING UTILITIES =====

def string_create(int initial_capacity) -> String
{
    String s;
    s.capacity = initial_capacity;
    s.length = 0;
    s.xdata = (byte*)malloc((u64)initial_capacity);
    return s;
};

def string_destroy(String* s) -> void
{
    if (s->xdata != 0)
    {
        free(s->xdata);
        s->xdata = 0;
    };
    s->length = 0;
    s->capacity = 0;
    return void;
};

def string_from_cstr(byte* cstr) -> String
{
    int len = (int)strlen(cstr);
    String s = string_create(len + 1);
    memcpy(s.xdata, cstr, (u64)len);
    s.xdata[len] = 0;
    s.length = len;
    return s;
};

def string_append(String* s, byte* cstr) -> void
{
    int len = (int)strlen(cstr);
    int new_len = s->length + len;
    
    if (new_len >= s->capacity)
    {
        int new_cap = s->capacity * 2;
        if (new_cap < new_len + 1)
        {
            new_cap = new_len + 1;
        };
        
        byte* new_xdata = (byte*)malloc((u64)new_cap);
        memcpy(new_xdata, s->xdata, (u64)s->length);
        free(s->xdata);
        s->xdata = new_xdata;
        s->capacity = new_cap;
    };
    
    memcpy(s->xdata + s->length, cstr, (u64)len);
    s->length = new_len;
    s->xdata[s->length] = 0;
    
    return void;
};

def string_equals(String* a, byte* b) -> bool
{
    return strcmp(a->xdata, b) == 0;
};

def string_starts_with(String* s, byte* prefix) -> bool
{
    int prefix_len = (int)strlen(prefix);
    if (s->length < prefix_len)
    {
        return 0;
    };
    return strncmp(s->xdata, prefix, (u64)prefix_len) == 0;
};

def string_copy(String* s) -> String
{
    return string_from_cstr(s->xdata);
};

// ===== STRING ARRAY UTILITIES =====

def string_array_create(int initial_capacity) -> StringArray
{
    StringArray arr;
    arr.capacity = initial_capacity;
    arr.length = 0;
    arr.xdata = (String*)malloc((u64)(initial_capacity * 12));
    return arr;
};

def string_array_destroy(StringArray* arr) -> void
{
    int i = 0;
    while (i < arr->length)
    {
        string_destroy(@arr->xdata[i]);
        i++;
    };
    
    if (arr->xdata != 0)
    {
        free(arr->xdata);
        arr->xdata = 0;
    };
    arr->length = 0;
    arr->capacity = 0;
    return void;
};

def string_array_push(StringArray* arr, String s) -> void
{
    if (arr->length >= arr->capacity)
    {
        int new_cap = arr->capacity * 2;
        String* new_xdata = (String*)malloc((u64)(new_cap * 12));
        memcpy(new_xdata, arr->xdata, (u64)(arr->length * 12));
        free(arr->xdata);
        arr->xdata = new_xdata;
        arr->capacity = new_cap;
    };
    
    arr->xdata[arr->length] = s;
    arr->length++;
    return void;
};

// ===== MACRO TABLE UTILITIES =====

def macro_table_create(int initial_capacity) -> MacroTable
{
    MacroTable table;
    table.capacity = initial_capacity;
    table.length = 0;
    table.xdata = (Macro*)malloc((u64)(initial_capacity * 24));
    return table;
};

def macro_table_destroy(MacroTable* table) -> void
{
    int i = 0;
    while (i < table->length)
    {
        string_destroy(@(table->xdata[i].name));
        string_destroy(@(table->xdata[i].value));
        i++;
    };
    
    if (table->xdata != 0)
    {
        free(table->xdata);
        table->xdata = 0;
    };
    table->length = 0;
    table->capacity = 0;
    return void;
};

def macro_table_set(MacroTable* table, byte* name, byte* value) -> void
{
    // Check if macro already exists
    int i = 0;
    while (i < table->length)
    {
        if (string_equals(@(table->xdata[i].name), name))
        {
            // Update existing macro
            string_destroy(@(table->xdata[i].value));
            table->xdata[i].value = string_from_cstr(value);
            return void;
        };
        i++;
    };
    
    // Add new macro
    if (table->length >= table->capacity)
    {
        int new_cap = table->capacity * 2;
        Macro* new_xdata = (Macro*)malloc((u64)(new_cap * 24));
        memcpy(new_xdata, table->xdata, (u64)(table->length * 24));
        free(table->xdata);
        table->xdata = new_xdata;
        table->capacity = new_cap;
    };
    
    Macro m;
    m.name = string_from_cstr(name);
    m.value = string_from_cstr(value);
    table->xdata[table->length] = m;
    table->length++;
    return void;
};

def macro_table_get(MacroTable* table, byte* name) -> byte*
{
    int i = 0;
    while (i < table->length)
    {
        if (string_equals(@(table->xdata[i].name), name))
        {
            return table->xdata[i].value.xdata;
        };
        i++;
    };
    return 0;
};

def macro_table_has(MacroTable* table, byte* name) -> bool
{
    return macro_table_get(table, name) != 0;
};

// ===== FILE SET UTILITIES =====

def file_set_create(int initial_capacity) -> FileSet
{
    FileSet set;
    set.capacity = initial_capacity;
    set.count = 0;
    set.paths = (String*)malloc((u64)(initial_capacity * 12));
    return set;
};

def file_set_destroy(FileSet* set) -> void
{
    int i = 0;
    while (i < set->count)
    {
        string_destroy(@(set->paths[i]));
        i++;
    };
    
    if (set->paths != 0)
    {
        free(set->paths);
        set->paths = 0;
    };
    set->count = 0;
    set->capacity = 0;
    return void;
};

def file_set_contains(FileSet* set, byte* path) -> bool
{
    int i = 0;
    while (i < set->count)
    {
        if (string_equals(@(set->paths[i]), path))
        {
            return 1;
        };
        i++;
    };
    return 0;
};

def file_set_add(FileSet* set, byte* path) -> void
{
    if (file_set_contains(set, path))
    {
        return void;
    };
    
    if (set->count >= set->capacity)
    {
        int new_cap = set->capacity * 2;
        String* new_data = (String*)malloc((u64)(new_cap * 12));
        memcpy(new_data, set->paths, (u64)(set->count * 12));
        free(set->paths);
        set->paths = new_data;
        set->capacity = new_cap;
    };
    
    set->paths[set->count] = string_from_cstr(path);
    set->count++;
    return void;
};

// ===== CHARACTER UTILITIES =====

def is_whitespace(byte c) -> bool
{
    return c == 32 | c == 9 | c == 10 | c == 13;
};

def is_delimiter(byte c) -> bool
{
    return c == 46 | c == 44 | c == 59 | c == 58 | c == 40 | c == 41 |
           c == 91 | c == 93 | c == 123 | c == 125 | c == 43 | c == 45 |
           c == 42 | c == 47 | c == 37 | c == 61 | c == 33 | c == 60 |
           c == 62 | c == 124 | c == 38 | c == 94 | c == 126;
};

// ===== STRING PROCESSING =====

def trim_whitespace(byte* str) -> byte*
{
    // Skip leading whitespace
    while (*str != 0 & is_whitespace(*str))
    {
        str++;
    };
    
    if (*str == 0)
    {
        return str;
    };
    
    // Find end
    byte* end = str;
    while (*end != 0)
    {
        end++;
    };
    end--;
    
    // Remove trailing whitespace
    while (end > str & is_whitespace(*end))
    {
        *end = 0;
        end--;
    };
    
    return str;
};

def find_char(byte* str, byte c) -> int
{
    int i = 0;
    while (str[i] != 0)
    {
        if (str[i] == c)
        {
            return i;
        };
        i++;
    };
    return -1;
};

// ===== COMMENT STRIPPING =====

def strip_comments(byte* content, int content_len) -> String
{
    String result = string_create(content_len);
    int i = 0;
    
    while (i < content_len)
    {
        // Check for /// multiline comment
        if (i + 2 < content_len & content[i] == 47 & content[i+1] == 47 & content[i+2] == 47)
        {
            i = i + 3;
            // Skip until closing ///
            while (i < content_len)
            {
                if (i + 2 < content_len & content[i] == 47 & content[i+1] == 47 & content[i+2] == 47)
                {
                    i = i + 3;
                    break;
                };
                i++;
            };
            continue;
        };
        
        // Check for // single-line comment
        if (i + 1 < content_len & content[i] == 47 & content[i+1] == 47)
        {
            // Skip to end of line
            while (i < content_len & content[i] != 10)
            {
                i++;
            };
            continue;
        };
        
        // Regular character - append it
        byte ch = content[i];
        byte[2] temp;
        temp[0] = ch;
        temp[1] = 0;
        string_append(@result, temp);
        i++;
    };
    
    return result;
};

// ===== PATH RESOLUTION =====

def resolve_path(byte* filepath) -> byte*
{
    // Check if file exists directly
    if (file_exists(filepath))
    {
        return filepath;
    };
    
    // Try common locations
    byte[512] path_buffer;
    
    // Try src/stdlib/
    strcpy(path_buffer, "src\\\\stdlib\\\\\0");
    strcat(path_buffer, filepath);
    if (file_exists(path_buffer))
    {
        byte* resolved = (byte*)malloc(512);
        strcpy(resolved, path_buffer);
        return resolved;
    };
    
    // Try src/stdlib/runtime/
    strcpy(path_buffer, "src\\\\stdlib\\\\runtime\\\\\0");
    strcat(path_buffer, filepath);
    if (file_exists(path_buffer))
    {
        byte* resolved = (byte*)malloc(512);
        strcpy(resolved, path_buffer);
        return resolved;
    };
    
    // Try src/stdlib/functions/
    strcpy(path_buffer, "src\\\\stdlib\\\\functions\\\\\0");
    strcat(path_buffer, filepath);
    if (file_exists(path_buffer))
    {
        byte* resolved = (byte*)malloc(512);
        strcpy(resolved, path_buffer);
        return resolved;
    };
    
    // Try src/stdlib/builtins/
    strcpy(path_buffer, "src\\\\stdlib\\\\builtins\\\\\0");
    strcat(path_buffer, filepath);
    if (file_exists(path_buffer))
    {
        byte* resolved = (byte*)malloc(512);
        strcpy(resolved, path_buffer);
        return resolved;
    };
    
    return 0;
};

// ===== MACRO SUBSTITUTION =====

def substitute_macros(byte* line, MacroTable* macros) -> String
{
    String result = string_create(512);
    
    bool in_quotes = 0;
    byte[256] current_token;
    int token_idx = 0;
    int i = 0;
    
    while (line[i] != 0)
    {
        byte c = line[i];
        
        if (c == 34)  // Quote character
        {
            in_quotes = !in_quotes;
            current_token[token_idx] = c;
            token_idx++;
        }
        else
        {
            if (is_whitespace(c) | is_delimiter(c))
            {
                // End of token
                if (token_idx > 0)
                {
                    current_token[token_idx] = 0;
                    
                    // Check if token is a macro
                    if (!in_quotes)
                    {
                        byte* macro_value = macro_table_get(macros, current_token);
                        if (macro_value != 0)
                        {
                            string_append(@result, macro_value);
                        }
                        else
                        {
                            string_append(@result, current_token);
                        };
                    }
                    else
                    {
                        string_append(@result, current_token);
                    };
                    
                    token_idx = 0;
                };
                
                // Append delimiter/whitespace
                byte[2] temp;
                temp[0] = c;
                temp[1] = 0;
                string_append(@result, temp);
            }
            else
            {
                current_token[token_idx] = c;
                token_idx++;
            };
        };
        
        i++;
    };
    
    // Handle last token
    if (token_idx > 0)
    {
        current_token[token_idx] = 0;
        
        if (!in_quotes)
        {
            byte* macro_value = macro_table_get(macros, current_token);
            if (macro_value != 0)
            {
                string_append(@result, macro_value);
            }
            else
            {
                string_append(@result, current_token);
            };
        }
        else
        {
            string_append(@result, current_token);
        };
    };
    
    return result;
};

// Forward declarations
def process_file(Preprocessor* pp, byte* filepath) -> void;
def process_line(Preprocessor* pp, StringArray* lines, int line_idx) -> int;

// ===== CONDITIONAL BLOCK PROCESSING =====

def process_conditional_block(Preprocessor* pp, StringArray* lines, int start_idx, byte* macro_name, bool is_ifndef) -> int
{
    byte* macro_value = macro_table_get(@(pp->macros), macro_name);
    
    // Evaluate condition
    bool condition_true = 0;
    if (is_ifndef)
    {
        condition_true = (macro_value == 0 | strcmp(macro_value, "0\0") == 0);
    }
    else
    {
        condition_true = (macro_value != 0 & strcmp(macro_value, "0\0") != 0);
    };
    
    int i = start_idx + 1;
    int depth = 1;
    bool in_else = 0;
    bool else_seen = 0;
    
    StringArray lines_to_include = string_array_create(32);
    
    while (i < lines->length)
    {
        String line = lines->xdata[i];
        byte* stripped = trim_whitespace(line.xdata);
        
        // Handle nested conditionals
        if (string_starts_with(@line, "#ifdef\0") | string_starts_with(@line, "#ifndef\0"))
        {
            depth++;
        };
        
        // Check for #else at our depth
        if (strcmp(stripped, "#else\0") == 0 & depth == 1)
        {
            if (else_seen)
            {
                print("Error: Multiple #else directives\\n\\0");
                exit(1);
            };
            else_seen = 1;
            in_else = 1;
            i++;
            continue;
        };
        
        // Check for #endif
        if (string_starts_with(@line, "#endif\0"))
        {
            depth--;
            if (depth == 0)
            {
                // Process collected lines
                if (lines_to_include.length > 0)
                {
                    int j = 0;
                    while (j < lines_to_include.length)
                    {
                        j = process_line(pp, @lines_to_include, j);
                    };
                };
                string_array_destroy(@lines_to_include);
                return i + 1;
            };
        };
        
        // Collect lines based on condition
        if ((condition_true & !in_else) | (!condition_true & in_else))
        {
            string_array_push(@lines_to_include, string_copy(@line));
        };
        
        i++;
    };
    
    print("Error: Unclosed conditional block\\n\\0");
    exit(1);
    return i;
};

// ===== LINE PROCESSING =====

def process_line(Preprocessor* pp, StringArray* lines, int line_idx) -> int
{
    String line = lines->xdata[line_idx];
    byte* stripped = trim_whitespace(line.xdata);
    
    // Skip empty lines
    if (strlen(stripped) == 0)
    {
        return line_idx + 1;
    };
    
    // Check for #def
    if (string_starts_with(@line, "#def\0"))
    {
        byte[512] macro_line;
        strcpy(macro_line, line.xdata);
        
        // Find semicolon
        int semicolon_pos = find_char(macro_line, 59);
        if (semicolon_pos >= 0)
        {
            macro_line[semicolon_pos] = 0;
        };
        
        // Parse: #def NAME VALUE
        byte[128] macro_name;
        byte[256] macro_value;
        
        // Skip "#def "
        byte* ptr = macro_line + 5;
        while (*ptr == 32 | *ptr == 9)
        {
            ptr++;
        };
        
        // Get macro name
        int name_idx = 0;
        while (*ptr != 0 & !is_whitespace(*ptr))
        {
            macro_name[name_idx] = *ptr;
            name_idx++;
            ptr++;
        };
        macro_name[name_idx] = 0;
        
        // Skip whitespace
        while (*ptr == 32 | *ptr == 9)
        {
            ptr++;
        };
        
        // Get macro value
        int val_idx = 0;
        while (*ptr != 0)
        {
            macro_value[val_idx] = *ptr;
            val_idx++;
            ptr++;
        };
        macro_value[val_idx] = 0;
        
        macro_table_set(@(pp->macros), macro_name, trim_whitespace(macro_value));
        
        print("[PREPROCESSOR] Defined macro: \0");
        print(macro_name);
        print(" = \0");
        print(macro_value);
        print("\\n\\0");
        
        return line_idx + 1;
    };
    
    // Check for #ifdef
    if (string_starts_with(@line, "#ifdef\0"))
    {
        byte[128] macro_name;
        byte* ptr = stripped + 7;
        while (*ptr == 32 | *ptr == 9)
        {
            ptr++;
        };
        
        int i = 0;
        while (*ptr != 0 & !is_whitespace(*ptr))
        {
            macro_name[i] = *ptr;
            i++;
            ptr++;
        };
        macro_name[i] = 0;
        
        return process_conditional_block(pp, lines, line_idx, macro_name, 0);
    };
    
    // Check for #ifndef
    if (string_starts_with(@line, "#ifndef\0"))
    {
        byte[128] macro_name;
        byte* ptr = stripped + 8;
        while (*ptr == 32 | *ptr == 9)
        {
            ptr++;
        };
        
        int i = 0;
        while (*ptr != 0 & !is_whitespace(*ptr))
        {
            macro_name[i] = *ptr;
            i++;
            ptr++;
        };
        macro_name[i] = 0;
        
        return process_conditional_block(pp, lines, line_idx, macro_name, 1);
    };
    
    // Check for #import
    if (string_starts_with(@line, "#import\0"))
    {
        // Extract quoted filenames
        int i = 0;
        while (line.xdata[i] != 0)
        {
            if (line.xdata[i] == 34)  // Quote
            {
                i++;
                byte[256] import_file;
                int file_idx = 0;
                
                while (line.xdata[i] != 0 & line.xdata[i] != 34)
                {
                    import_file[file_idx] = line.xdata[i];
                    file_idx++;
                    i++;
                };
                import_file[file_idx] = 0;
                
                // Process the import
                process_file(pp, trim_whitespace(import_file));
            };
            i++;
        };
        
        return line_idx + 1;
    };
    
    // Check for #endif - skip it
    if (string_starts_with(@line, "#endif\0"))
    {
        return line_idx + 1;
    };
    
    // Check for #else - skip it
    if (strcmp(stripped, "#else\0") == 0)
    {
        return line_idx + 1;
    };
    
    // Regular line - do macro substitution
    String processed = substitute_macros(line.xdata, @(pp->macros));
    string_array_push(@(pp->output_lines), processed);
    
    return line_idx + 1;
};

// ===== FILE PROCESSING =====

def process_file(Preprocessor* pp, byte* filepath) -> void
{
    byte* resolved_path = resolve_path(filepath);
    
    if (resolved_path == 0)
    {
        print("Error: Could not find import: \0");
        print(filepath);
        print("\\n\\0");
        exit(1);
    };
    
    // Avoid circular imports
    if (file_set_contains(@(pp->processed_files), resolved_path))
    {
        return void;
    };
    
    file_set_add(@(pp->processed_files), resolved_path);
    
    print("[PREPROCESSOR] Processing: \0");
    print(filepath);
    print("\\n\\0");
    
    // Read file
    int file_size = get_file_size(resolved_path);
    if (file_size < 0)
    {
        print("Error: Could not read file: \0");
        print(resolved_path);
        print("\\n\\0");
        exit(1);
    };
    
    byte* content = (byte*)malloc((u64)file_size + 1);
    int bytes_read = read_file(resolved_path, content, file_size);
    content[bytes_read] = 0;
    
    // Strip comments
    String stripped_content = strip_comments(content, bytes_read);
    free(content);
    
    // Split into lines
    StringArray file_lines = string_array_create(256);
    
    byte[4096] line_buffer;
    int line_idx = 0;
    int i = 0;
    
    while (i <= stripped_content.length)
    {
        byte c = stripped_content.xdata[i];
        
        if (c == 10 | c == 0)  // Newline or end
        {
            line_buffer[line_idx] = 0;
            string_array_push(@file_lines, string_from_cstr(line_buffer));
            line_idx = 0;
        }
        else
        {
            if (c != 13)  // Skip carriage return
            {
                line_buffer[line_idx] = c;
                line_idx++;
            };
        };
        
        i++;
    };
    
    string_destroy(@stripped_content);
    
    // Process each line
    int j = 0;
    while (j < file_lines.length)
    {
        j = process_line(pp, @file_lines, j);
    };
    
    string_array_destroy(@file_lines);
    
    return void;
};

// ===== MAIN PREPROCESSING FUNCTION =====

def preprocessor_create(byte* source_file) -> Preprocessor
{
    Preprocessor pp;
    pp.source_file = string_from_cstr(source_file);
    pp.processed_files = file_set_create(32);
    pp.output_lines = string_array_create(1024);
    pp.macros = macro_table_create(64);
    return pp;
};

def preprocessor_destroy(Preprocessor* pp) -> void
{
    string_destroy(@(pp->source_file));
    file_set_destroy(@(pp->processed_files));
    string_array_destroy(@(pp->output_lines));
    macro_table_destroy(@(pp->macros));
    return void;
};

def preprocessor_process(Preprocessor* pp) -> void
{
    print("[PREPROCESSOR] Starting preprocessing...\\n\\0");
    
    // Process main file and all imports
    process_file(pp, pp->source_file.xdata);
    
    // Build combined source
    String combined = string_create(65536);
    
    int i = 0;
    while (i < pp->output_lines.length)
    {
        String line = pp->output_lines.xdata[i];
        byte* trimmed = trim_whitespace(line.xdata);
        
        // Only include non-empty lines
        if (strlen(trimmed) > 0)
        {
            string_append(@combined, trimmed);
            string_append(@combined, "\\n\0");
        };
        
        i++;
    };
    
    // Iterative macro substitution
    bool replaced = 1;
    int iteration = 0;
    
    while (replaced)
    {
        iteration++;
        print("[PREPROCESSOR] Macro substitution pass: \0");
        // Print iteration number (simple approach)
        if (iteration == 1) { print("1\\n\\0"); };
        if (iteration == 2) { print("2\\n\\0"); };
        if (iteration == 3) { print("3\\n\\0"); };
        if (iteration >= 4) { print("4+\\n\\0"); };
        
        replaced = 0;
        
        StringArray new_lines = string_array_create(pp->output_lines.length);
        
        // Split combined source into lines again
        byte[4096] line_buffer;
        int line_idx = 0;
        int j = 0;
        
        while (j <= combined.length)
        {
            byte c = combined.xdata[j];
            
            if (c == 10 | c == 0)
            {
                line_buffer[line_idx] = 0;
                
                String original_line = string_from_cstr(line_buffer);
                String substituted_line = substitute_macros(line_buffer, @(pp->macros));
                
                if (!string_equals(@substituted_line, original_line.xdata))
                {
                    replaced = 1;
                };
                
                string_array_push(@new_lines, substituted_line);
                string_destroy(@original_line);
                
                line_idx = 0;
            }
            else
            {
                if (c != 13)
                {
                    line_buffer[line_idx] = c;
                    line_idx++;
                };
            };
            
            j++;
        };
        
        // Rebuild combined source
        string_destroy(@combined);
        combined = string_create(65536);
        
        j = 0;
        while (j < new_lines.length)
        {
            string_append(@combined, new_lines.xdata[j].xdata);
            string_append(@combined, "\\n\0");
            j++;
        };
        
        string_array_destroy(@new_lines);
    };
    
    print("[PREPROCESSOR] Completed after \0");
    if (iteration == 1) { print("1 macro pass.\\n\\0"); };
    if (iteration == 2) { print("2 macro passes.\\n\\0"); };
    if (iteration == 3) { print("3 macro passes.\\n\\0"); };
    if (iteration >= 4) { print("4+ macro passes.\\n\\0"); };
    
    // Write output file
    int bytes_written = write_file("build\\\\tmp.fx\\0", combined.xdata, combined.length);
    
    if (bytes_written > 0)
    {
        print("[PREPROCESSOR] Generated: build\\\\tmp.fx\\n\\0");
        print("[PREPROCESSOR] Processed \0");
        // Simple count printing
        if (pp->processed_files.count == 1) { print("1 file\\n\\0"); }
        else { print("multiple files\\n\\0"); };
    }
    else
    {
        print("[PREPROCESSOR] Error writing output file\\n\\0");
    };
    
    string_destroy(@combined);
    
    return void;
};

// ===== EXAMPLE USAGE =====
///
def main() -> int
{
    print("Flux Preprocessor (written in Flux)\\n\\0");
    print("Usage: fxpreprocess <source_file.fx>\\n\\0");
    
    // Example:
    // Preprocessor pp = preprocessor_create("examples\\\\helloworld.fx\\0");
    // preprocessor_process(@pp);
    // preprocessor_destroy(@pp);
    
    return 0;
};
///


