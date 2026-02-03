#import "standard.fx";

// Flux Preprocessor
// Translates fpreprocess.py to Flux

// Macro entry structure
struct Macro
{
    byte[256] name;
    byte[512] value;
    i32 is_defined;
};

// File path tracking
struct ProcessedFile
{
    byte[512] path;
    i32 is_processed;
};

// Global state
i32 MAX_MACROS = 256;
i32 MAX_FILES = 128;
i32 MAX_LINES = 32768;
i32 MAX_LINE_LENGTH = 1024;

Macro[256] macros;
i32 macro_count = 0;

ProcessedFile[128] processed_files;
i32 processed_file_count = 0;

byte** output_lines;
i32 output_line_count = 0;

// Forward declarations
def process_file(byte* filepath) -> void;
def process_line(byte** lines, i32 line_count, i32* i) -> i32;
def strip_comments(byte* content, i32 content_len) -> byte*;
def resolve_path(byte* filepath, byte* result) -> i32;
def substitute_macros(byte* line, byte* result) -> void;
def process_conditional_block(byte** lines, i32 line_count, i32 start_i, byte* macro_name, i32 is_ifndef) -> i32;

// Helper functions
def is_file_processed(byte* filepath) -> i32
{
    i32 i = 0;
    while (i < processed_file_count)
    {
        if (strcmp(processed_files[i].path, filepath) == 0)
        {
            return 1;
        };
        i++;
    };
    return 0;
};

def add_processed_file(byte* filepath) -> void
{
    if (processed_file_count >= MAX_FILES) { return; };
    strcpy(processed_files[processed_file_count].path, filepath);
    processed_files[processed_file_count].is_processed = 1;
    processed_file_count++;
};

def find_macro(byte* name) -> i32
{
    i32 i = 0;
    while (i < macro_count)
    {
        if (strcmp(macros[i].name, name) == 0)
        {
            return i;
        };
        i++;
    };
    return -1;
};

def get_macro_value(byte* name, byte* result) -> i32
{
    i32 idx = find_macro(name);
    if (idx == -1) { return 0; };
    strcpy(result, macros[idx].value);
    return 1;
};

def define_macro(byte* name, byte* value) -> void
{
    i32 idx = find_macro(name);
    if (idx != -1)
    {
        strcpy(macros[idx].value, value);
        return;
    };
    
    if (macro_count >= MAX_MACROS) { return; };
    
    strcpy(macros[macro_count].name, name);
    strcpy(macros[macro_count].value, value);
    macros[macro_count].is_defined = 1;
    macro_count++;
    
    print("[PREPROCESSOR] Defined macro: \0");
    print(name);
    print(" = \0");
    print(value);
    print();
};

// Strip comments from content
def strip_comments(byte* content, i32 content_len) -> byte*
{
    byte* result = malloc((u64)content_len + 1);
    i32 i = 0;
    i32 j = 0;
    
    while (i < content_len)
    {
        if (i + 2 < content_len & content[i] == '/' & content[i+1] == '/' & content[i+2] == '/')
        {
            i = i + 3;
            while (i < content_len)
            {
                if (i + 2 < content_len & content[i] == '/' & content[i+1] == '/' & content[i+2] == '/')
                {
                    i = i + 3;
                    break;
                };
                i++;
            };
            continue;
        };
        
        if (i + 1 < content_len & content[i] == '/' & content[i+1] == '/')
        {
            while (i < content_len & content[i] != '\n')
            {
                i++;
            };
            continue;
        };
        
        result[j] = content[i];
        j++;
        i++;
    };
    
    result[j] = '\0';
    return result;
};

// Resolve file path
def resolve_path(byte* filepath, byte* result) -> i32
{
    byte[512] temp;
    
    i64 handle = open_read(filepath);
    if (handle != INVALID_HANDLE_VALUE)
    {
        win_close(handle);
        strcpy(result, filepath);
        return 1;
    };
    
    strcpy(temp, "src\\stdlib\\\0");
    concat(temp, filepath);
    handle = open_read(temp);
    if (handle != INVALID_HANDLE_VALUE)
    {
        win_close(handle);
        strcpy(result, temp);
        return 1;
    };
    
    strcpy(temp, "src\\stdlib\\runtime\\\0");
    concat(temp, filepath);
    handle = open_read(temp);
    if (handle != INVALID_HANDLE_VALUE)
    {
        win_close(handle);
        strcpy(result, temp);
        return 1;
    };
    
    strcpy(temp, "src\\stdlib\\functions\\\0");
    concat(temp, filepath);
    handle = open_read(temp);
    if (handle != INVALID_HANDLE_VALUE)
    {
        win_close(handle);
        strcpy(result, temp);
        return 1;
    };
    
    strcpy(temp, "src\\stdlib\\builtins\\\0");
    concat(temp, filepath);
    handle = open_read(temp);
    if (handle != INVALID_HANDLE_VALUE)
    {
        win_close(handle);
        strcpy(result, temp);
        return 1;
    };
    
    return 0;
};

// Get file size (Windows)
def get_file_size(byte* filename) -> i32
{
    i64 handle = open_read(filename);
    if (handle == INVALID_HANDLE_VALUE) { return -1; };
    
    i32 size = 0;
    volatile asm
    {
        movq $0, %rcx
        xorq %rdx, %rdx
        subq $$32, %rsp
        call GetFileSize
        addq $$32, %rsp
        movl %eax, $1
    } : : "r"(handle), "m"(size) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
    
    win_close(handle);
    return size;
};

// Read entire file
def read_file(byte* filename, byte* buffer, i32 size) -> i32
{
    i64 handle = open_read(filename);
    if (handle == INVALID_HANDLE_VALUE) { return -1; };
    
    i32 bytes_read = win_read(handle, buffer, (u32)size);
    buffer[bytes_read] = '\0';
    
    win_close(handle);
    return bytes_read;
};

// Write entire file
def write_file(byte* filename, byte* content, i32 size) -> i32
{
    i64 handle = open_write(filename);
    if (handle == INVALID_HANDLE_VALUE) { return -1; };
    
    i32 bytes_written = win_write(handle, content, (u32)size);
    
    win_close(handle);
    return bytes_written;
};

// Split content into lines
def split_lines(byte* content, byte*** lines_ptr, i32* line_count_ptr) -> void
{
    *line_count_ptr = count_lines(content);
    *lines_ptr = (byte**)malloc((u64)(*line_count_ptr) * 8);
    
    i32 line_idx = 0;
    i32 line_start = 0;
    i32 i = 0;
    
    while (content[i] != '\0')
    {
        if (content[i] == '\n')
        {
            i32 line_len = i - line_start;
            byte* line = substring(content, line_start, line_len);
            (*lines_ptr)[line_idx] = line;
            line_idx++;
            line_start = i + 1;
        };
        i++;
    };
    
    if (line_start < i)
    {
        i32 line_len = i - line_start;
        byte* line = substring(content, line_start, line_len);
        (*lines_ptr)[line_idx] = line;
        line_idx++;
    };
};

// Trim whitespace from string
def trim(byte* str, byte* result) -> void
{
    i32 start = 0;
    while (is_whitespace(str[start])) { start++; };
    
    i32 end = strlen(str) - 1;
    while (end >= start & is_whitespace(str[end])) { end--; };
    
    i32 i = 0;
    while (start <= end)
    {
        result[i] = str[start];
        i++;
        start++;
    };
    result[i] = '\0';
};

// Process conditional block
def process_conditional_block(byte** lines, i32 line_count, i32 start_i, byte* macro_name, i32 is_ifndef) -> i32
{
    byte[512] macro_value;
    i32 has_value = get_macro_value(macro_name, macro_value);
    
    i32 condition_true = 0;
    if (is_ifndef)
    {
        condition_true = (!has_value) | (strcmp(macro_value, "0\0") == 0);
    }
    else
    {
        condition_true = has_value & (strcmp(macro_value, "0\0") != 0);
    };
    
    i32 i = start_i + 1;
    i32 depth = 1;
    i32 in_else = 0;
    i32 else_seen = 0;
    
    byte**lines_to_include = (byte**)malloc((u64)line_count * 8);
    i32 lines_to_include_count = 0;
    
    while (i < line_count)
    {
        byte[1024] stripped;
        trim(lines[i], stripped);
        
        if (starts_with(stripped, "#ifdef\0") | starts_with(stripped, "#ifndef\0"))
        {
            depth++;
        };
        
        if (strcmp(stripped, "#else\0") == 0 & depth == 1)
        {
            in_else = 1;
            i++;
            continue;
        };
        
        if (starts_with(stripped, "#endif\0"))
        {
            depth--;
            if (depth == 0)
            {
                i32 j = 0;
                while (j < lines_to_include_count)
                {
                    j = process_line(lines_to_include, lines_to_include_count, @j);
                };
                free(lines_to_include);
                return i + 1;
            };
        };
        
        if (depth > 1)
        {
            if ((condition_true & !in_else) | (!condition_true & in_else))
            {
                lines_to_include[lines_to_include_count] = lines[i];
                lines_to_include_count++;
            };
        }
        else
        {
            if ((condition_true & !in_else) | (!condition_true & in_else))
            {
                lines_to_include[lines_to_include_count] = lines[i];
                lines_to_include_count++;
            };
        };
        
        i++;
    };
    
    free(lines_to_include);
    return i;
};

// Process a single line
def process_line(byte** lines, i32 line_count, i32* i_ptr) -> i32
{
    i32 i = *i_ptr;
    byte* line = lines[i];
    byte[1024] stripped;
    trim(line, stripped);
    
    if (strlen(stripped) == 0)
    {
        return i + 1;
    };
    
    if (starts_with(stripped, "#def\0"))
    {
        byte[256][8] parts;
        i32 part_count = 0;
        i32 j = 0;
        i32 part_start = 0;
        i32 in_part = 0;
        
        while (stripped[j] != '\0')
        {
            if (is_whitespace(stripped[j]))
            {
                if (in_part)
                {
                    i32 part_len = j - part_start;
                    i32 k = 0;
                    while (k < part_len & k < 255)
                    {
                        parts[part_count][k] = stripped[part_start + k];
                        k++;
                    };
                    parts[part_count][k] = '\0';
                    part_count++;
                    in_part = 0;
                };
            }
            else if (!in_part)
            {
                part_start = j;
                in_part = 1;
            };
            j++;
        };
        
        if (in_part)
        {
            i32 part_len = j - part_start;
            i32 k = 0;
            while (k < part_len & k < 255)
            {
                parts[part_count][k] = stripped[part_start + k];
                k++;
            };
            parts[part_count][k] = '\0';
            part_count++;
        };
        
        if (part_count >= 3)
        {
            byte[256] macro_value;
            i32 value_start = 2;
            i32 value_len = 0;
            i32 v = value_start;
            while (v < part_count)
            {
                if (v > value_start)
                {
                    macro_value[value_len] = ' ';
                    value_len++;
                };
                i32 plen = strlen(parts[v]);
                i32 p = 0;
                while (p < plen)
                {
                    macro_value[value_len] = parts[v][p];
                    value_len++;
                    p++;
                };
                v++;
            };
            macro_value[value_len] = '\0';
            
            i32 mvlen = strlen(macro_value);
            if (macro_value[mvlen - 1] == ';')
            {
                macro_value[mvlen - 1] = '\0';
            };
            
            define_macro(parts[1], macro_value);
        };
        
        return i + 1;
    };
    
    if (starts_with(stripped, "#ifdef\0"))
    {
        byte[256][4] parts;
        i32 part_count = 0;
        i32 j = 0;
        i32 part_start = 0;
        i32 in_part = 0;
        
        while (stripped[j] != '\0' & part_count < 4)
        {
            if (is_whitespace(stripped[j]))
            {
                if (in_part)
                {
                    i32 part_len = j - part_start;
                    i32 k = 0;
                    while (k < part_len & k < 255)
                    {
                        parts[part_count][k] = stripped[part_start + k];
                        k++;
                    };
                    parts[part_count][k] = '\0';
                    part_count++;
                    in_part = 0;
                };
            }
            else if (!in_part)
            {
                part_start = j;
                in_part = 1;
            };
            j++;
        };
        
        if (in_part & part_count < 4)
        {
            i32 part_len = j - part_start;
            i32 k = 0;
            while (k < part_len & k < 255)
            {
                parts[part_count][k] = stripped[part_start + k];
                k++;
            };
            parts[part_count][k] = '\0';
            part_count++;
        };
        
        if (part_count >= 2)
        {
            return process_conditional_block(lines, line_count, i, parts[1], 0);
        };
    };
    
    if (starts_with(stripped, "#ifndef\0"))
    {
        byte[256][4] parts;
        i32 part_count = 0;
        i32 j = 0;
        i32 part_start = 0;
        i32 in_part = 0;
        
        while (stripped[j] != '\0' & part_count < 4)
        {
            if (is_whitespace(stripped[j]))
            {
                if (in_part)
                {
                    i32 part_len = j - part_start;
                    i32 k = 0;
                    while (k < part_len & k < 255)
                    {
                        parts[part_count][k] = stripped[part_start + k];
                        k++;
                    };
                    parts[part_count][k] = '\0';
                    part_count++;
                    in_part = 0;
                };
            }
            else if (!in_part)
            {
                part_start = j;
                in_part = 1;
            };
            j++;
        };
        
        if (in_part & part_count < 4)
        {
            i32 part_len = j - part_start;
            i32 k = 0;
            while (k < part_len & k < 255)
            {
                parts[part_count][k] = stripped[part_start + k];
                k++;
            };
            parts[part_count][k] = '\0';
            part_count++;
        };
        
        if (part_count >= 2)
        {
            return process_conditional_block(lines, line_count, i, parts[1], 1);
        };
    };
    
    if (starts_with(stripped, "#import\0"))
    {
        i32 j = 0;
        while (line[j] != '\0')
        {
            if (line[j] == '"')
            {
                i32 start_idx = j + 1;
                i32 end_idx = start_idx;
                while (line[end_idx] != '\0' & line[end_idx] != '"')
                {
                    end_idx++;
                };
                
                if (line[end_idx] == '"')
                {
                    byte[512] import_file;
                    i32 k = 0;
                    while (start_idx < end_idx)
                    {
                        import_file[k] = line[start_idx];
                        k++;
                        start_idx++;
                    };
                    import_file[k] = '\0';
                    
                    process_file(import_file);
                    j = end_idx;
                };
            };
            j++;
        };
        
        return i + 1;
    };
    
    if (starts_with(stripped, "#endif\0"))
    {
        return i + 1;
    };
    
    if (strcmp(stripped, "#else\0") == 0)
    {
        return i + 1;
    };
    
    byte[1024] processed_line;
    substitute_macros(line, processed_line);
    
    byte* new_line = copy_string(processed_line);
    output_lines[output_line_count] = new_line;
    output_line_count++;
    
    return i + 1;
};

// Substitute macros in a line
def substitute_macros(byte* line, byte* result) -> void
{
    i32 result_idx = 0;
    i32 i = 0;
    i32 in_quotes = 0;
    byte[256] token;
    i32 token_idx = 0;
    
    while (line[i] != '\0')
    {
        byte ch = line[i];
        
        if (ch == '"')
        {
            in_quotes = !in_quotes;
            if (token_idx > 0)
            {
                token[token_idx] = '\0';
                if (!in_quotes)
                {
                    byte[512] macro_value;
                    if (get_macro_value(token, macro_value))
                    {
                        i32 mvlen = strlen(macro_value);
                        if (macro_value[mvlen - 1] == ';')
                        {
                            macro_value[mvlen - 1] = '\0';
                            mvlen--;
                        };
                        i32 j = 0;
                        while (j < mvlen)
                        {
                            result[result_idx] = macro_value[j];
                            result_idx++;
                            j++;
                        };
                    }
                    else
                    {
                        i32 j = 0;
                        while (j < token_idx)
                        {
                            result[result_idx] = token[j];
                            result_idx++;
                            j++;
                        };
                    };
                }
                else
                {
                    i32 j = 0;
                    while (j < token_idx)
                    {
                        result[result_idx] = token[j];
                        result_idx++;
                        j++;
                    };
                };
                token_idx = 0;
            };
            result[result_idx] = ch;
            result_idx++;
        }
        else if (is_whitespace(ch) | ch == '.' | ch == ',' | ch == ';' | ch == ':' | ch == '(' | ch == ')' | ch == '[' | ch == ']' | ch == '{' | ch == '}' | ch == '+' | ch == '-' | ch == '*' | ch == '/' | ch == '%' | ch == '=' | ch == '!' | ch == '<' | ch == '>' | ch == '|' | ch == '&' | ch == '^' | ch == '~')
        {
            if (token_idx > 0)
            {
                token[token_idx] = '\0';
                if (!in_quotes)
                {
                    byte[512] macro_value;
                    if (get_macro_value(token, macro_value))
                    {
                        i32 mvlen = strlen(macro_value);
                        if (macro_value[mvlen - 1] == ';')
                        {
                            macro_value[mvlen - 1] = '\0';
                            mvlen--;
                        };
                        i32 j = 0;
                        while (j < mvlen)
                        {
                            result[result_idx] = macro_value[j];
                            result_idx++;
                            j++;
                        };
                    }
                    else
                    {
                        i32 j = 0;
                        while (j < token_idx)
                        {
                            result[result_idx] = token[j];
                            result_idx++;
                            j++;
                        };
                    };
                }
                else
                {
                    i32 j = 0;
                    while (j < token_idx)
                    {
                        result[result_idx] = token[j];
                        result_idx++;
                        j++;
                    };
                };
                token_idx = 0;
            };
            result[result_idx] = ch;
            result_idx++;
        }
        else
        {
            token[token_idx] = ch;
            token_idx++;
        };
        
        i++;
    };
    
    if (token_idx > 0)
    {
        token[token_idx] = '\0';
        if (!in_quotes)
        {
            byte[512] macro_value;
            if (get_macro_value(token, macro_value))
            {
                i32 mvlen = strlen(macro_value);
                if (macro_value[mvlen - 1] == ';')
                {
                    macro_value[mvlen - 1] = '\0';
                    mvlen--;
                };
                i32 j = 0;
                while (j < mvlen)
                {
                    result[result_idx] = macro_value[j];
                    result_idx++;
                    j++;
                };
            }
            else
            {
                i32 j = 0;
                while (j < token_idx)
                {
                    result[result_idx] = token[j];
                    result_idx++;
                    j++;
                };
            };
        }
        else
        {
            i32 j = 0;
            while (j < token_idx)
            {
                result[result_idx] = token[j];
                result_idx++;
                j++;
            };
        };
    };
    
    result[result_idx] = '\0';
};

// Process a file
def process_file(byte* filepath) -> void
{
    byte[512] resolved_path;
    if (!resolve_path(filepath, resolved_path))
    {
        print("[PREPROCESSOR ERROR] Could not find import: \0");
        print(filepath);
        print();
        return;
    };
    
    if (is_file_processed(resolved_path))
    {
        return;
    };
    
    add_processed_file(resolved_path);
    print("[PREPROCESSOR] Processing: \0");
    print(filepath);
    print();
    
    i32 size = get_file_size(resolved_path);
    if (size == -1)
    {
        print("[PREPROCESSOR ERROR] Could not get file size: \0");
        print(filepath);
        print();
        return;
    };
    
    byte* content = malloc((u64)size + 1);
    i32 bytes_read = read_file(resolved_path, content, size);
    if (bytes_read == -1)
    {
        print("[PREPROCESSOR ERROR] Could not read file: \0");
        print(filepath);
        print();
        free(content);
        return;
    };
    
    byte* stripped_content = strip_comments(content, bytes_read);
    free(content);
    
    byte** lines;
    i32 line_count;
    split_lines(stripped_content, @lines, @line_count);
    free(stripped_content);
    
    i32 i = 0;
    while (i < line_count)
    {
        i = process_line(lines, line_count, @i);
    };
    
    i32 j = 0;
    while (j < line_count)
    {
        free(lines[j]);
        j++;
    };
    free(lines);
};

// Main preprocessing function
def preprocess(byte* source_file, byte** compiler_macros, i32 compiler_macro_count) -> byte*
{
    macro_count = 0;
    processed_file_count = 0;
    output_line_count = 0;
    output_lines = (byte**)malloc((u64)MAX_LINES * 8);
    
    i32 i = 0;
    while (i < compiler_macro_count)
    {
        define_macro(compiler_macros[i * 2], compiler_macros[i * 2 + 1]);
        i++;
    };
    
    print("[PREPROCESSOR] Standard library / user-defined macros:\n\n\0");
    
    process_file(source_file);
    
    i32 total_len = 0;
    i = 0;
    while (i < output_line_count)
    {
        if (strlen(output_lines[i]) > 0)
        {
            total_len = total_len + strlen(output_lines[i]) + 1;
        };
        i++;
    };
    
    byte* combined_source = malloc((u64)total_len + 1);
    i32 combined_idx = 0;
    i = 0;
    while (i < output_line_count)
    {
        if (strlen(output_lines[i]) > 0)
        {
            i32 line_len = strlen(output_lines[i]);
            i32 j = 0;
            while (j < line_len)
            {
                combined_source[combined_idx] = output_lines[i][j];
                combined_idx++;
                j++;
            };
            combined_source[combined_idx] = '\n';
            combined_idx++;
        };
        i++;
    };
    combined_source[combined_idx] = '\0';
    
    i32 iteration = 0;
    i32 replaced = 1;
    while (replaced)
    {
        iteration++;
        print("[PREPROCESSOR] Macro substitution passes: \0");
        print(iteration);
        print();
        replaced = 0;
        
        byte** new_lines;
        i32 new_line_count;
        split_lines(combined_source, @new_lines, @new_line_count);
        free(combined_source);
        
        total_len = 0;
        i = 0;
        while (i < new_line_count)
        {
            byte[1024] processed_line;
            substitute_macros(new_lines[i], processed_line);
            if (strcmp(new_lines[i], processed_line) != 0)
            {
                replaced = 1;
            };
            total_len = total_len + strlen(processed_line) + 1;
            free(new_lines[i]);
            new_lines[i] = copy_string(processed_line);
            i++;
        };
        
        combined_source = malloc((u64)total_len + 1);
        combined_idx = 0;
        i = 0;
        while (i < new_line_count)
        {
            i32 line_len = strlen(new_lines[i]);
            i32 j = 0;
            while (j < line_len)
            {
                combined_source[combined_idx] = new_lines[i][j];
                combined_idx++;
                j++;
            };
            combined_source[combined_idx] = '\n';
            combined_idx++;
            free(new_lines[i]);
            i++;
        };
        combined_source[combined_idx] = '\0';
        free(new_lines);
    };
    
    byte* ending = "es.\0";
    if (iteration == 1) { ending = ".\0"; };
    print("[PREPROCESSOR] Completed after \0");
    print(iteration);
    print(" macro pass\0");
    print(ending);
    print();
    
    i32 write_result = write_file("build\\tmp.fx\0", combined_source, strlen(combined_source));
    if (write_result != -1)
    {
        print("[PREPROCESSOR] Generated: build\\tmp.fx\n\0");
    };
    
    print("[PREPROCESSOR] Processed \0");
    print(processed_file_count);
    print(" file(s)\n\0");
    
    i = 0;
    while (i < output_line_count)
    {
        free(output_lines[i]);
        i++;
    };
    free(output_lines);
    
    return combined_source;
};

def main() -> int
{
    byte[256] source_file;
    print("Enter source file: \0");
    win_input(source_file, 256);
    print();
    
    byte* result = preprocess(source_file, (byte**)0, 0);
    
    print("Preprocessing complete.\n\0");
    free(result);
    
    return 0;
};
