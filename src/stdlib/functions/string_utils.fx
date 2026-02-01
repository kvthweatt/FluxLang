// Additional String Manipulation Utilities
// Fresh snippet - pick and choose what you want

#ifndef FLUX_STRING_UTILS
#def FLUX_STRING_UTILS 1;
#endif;

#ifdef FLUX_STRING_UTILS

namespace string_utils
{
    // ===== CHARACTER CLASSIFICATION =====
    
    def is_whitespace(char c) -> bool
    {
        return c == ' ' | c == '\t' | c == '\n' | c == '\r';
    };
    
    def is_digit(char c) -> bool
    {
        return c >= '0' & c <= '9';
    };
    
    def is_alpha(char c) -> bool
    {
        return (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z');
    };
    
    def is_alnum(char c) -> bool
    {
        return is_alpha(c) | is_digit(c);
    };
    
    def is_hex_digit(char c) -> bool
    {
        return is_digit(c) | (c >= 'a' & c <= 'f') | (c >= 'A' & c <= 'F');
    };
    
    def is_identifier_start(char c) -> bool
    {
        return is_alpha(c) | c == '_';
    };
    
    def is_identifier_char(char c) -> bool
    {
        return is_alnum(c) | c == '_';
    };
    
    def is_newline(char c) -> bool
    {
        return c == '\n' | c == '\r';
    };
    
    
    // ===== CHARACTER CONVERSION =====
    
    def to_lower(char c) -> char
    {
        if (c >= 'A' & c <= 'Z')
        {
            return c + 32;
        };
        return c;
    };
    
    def to_upper(char c) -> char
    {
        if (c >= 'a' & c <= 'z')
        {
            return c - 32;
        };
        return c;
    };
    
    def char_to_digit(char c) -> int
    {
        if (c >= '0' & c <= '9')
        {
            return c - '0';
        };
        return -1;
    };
    
    def hex_to_int(char c) -> int
    {
        if (c >= '0' & c <= '9')
        {
            return c - '0';
        };
        if (c >= 'a' & c <= 'f')
        {
            return 10 + (c - 'a');
        };
        if (c >= 'A' & c <= 'F')
        {
            return 10 + (c - 'A');
        };
        return -1;
    };
    
    
    // ===== STRING SEARCHING =====
    
    // Find first occurrence of character
    // Returns index or -1 if not found
    def find_char(byte* str, char ch, int start_pos) -> int
    {
        for (int i = start_pos; str[i] != 0; i = i + 1)
        {
            if (str[i] == ch)
            {
                return i;
            };
        };
        return -1;
    };
    
    // Find last occurrence of character
    def find_char_last(byte* str, char ch) -> int
    {
        int last = -1;
        for (int i = 0; str[i] != 0; i = i + 1)
        {
            if (str[i] == ch)
            {
                last = i;
            };
        };
        return last;
    };
    
    // Find first occurrence of any character from set
    def find_any(byte* str, byte* char_set, int start_pos) -> int
    {
        for (int i = start_pos; str[i] != 0; i = i + 1)
        {
            for (int j = 0; char_set[j] != 0; j = j + 1)
            {
                if (str[i] == char_set[j])
                {
                    return i;
                };
            };
        };
        return -1;
    };
    
    // Find substring
    // Returns index or -1 if not found
    def find_substring(byte* str, byte* substr, int start_pos) -> int
    {
        int str_len = 0;
        while (str[str_len] != 0) { str_len = str_len + 1; };
        
        int substr_len = 0;
        while (substr[substr_len] != 0) { substr_len = substr_len + 1; };
        
        if (substr_len == 0)
        {
            return start_pos;
        };
        
        for (int i = start_pos; i <= str_len - substr_len; i = i + 1)
        {
            bool match = true;
            for (int j = 0; j < substr_len; j = j + 1)
            {
                if (str[i + j] != substr[j])
                {
                    match = false;
                    break;
                };
            };
            if (match)
            {
                return i;
            };
        };
        return -1;
    };
    
    
    // ===== STRING TRIMMING =====
    
    // Skip leading whitespace, return new start position
    def skip_whitespace(byte* str, int pos) -> int
    {
        while (str[pos] != 0 & is_whitespace(str[pos]))
        {
            pos = pos + 1;
        };
        return pos;
    };
    
    // Trim whitespace in-place from end (by writing null terminator)
    def trim_end(byte* str) -> void
    {
        int len = 0;
        while (str[len] != 0) { len = len + 1; };
        
        while (len > 0 & is_whitespace(str[len - 1]))
        {
            len = len - 1;
        };
        str[len] = (byte)0;
        return;
    };
    
    
    // ===== STRING COMPARISON =====
    
    // Compare n characters
    def compare_n(byte* s1, byte* s2, int n) -> int
    {
        for (int i = 0; i < n; i = i + 1)
        {
            if (s1[i] != s2[i])
            {
                return s1[i] - s2[i];
            };
            if (s1[i] == 0)
            {
                return 0;
            };
        };
        return 0;
    };
    
    // Case-insensitive compare
    def compare_ignore_case(byte* s1, byte* s2) -> int
    {
        int i = 0;
        while (s1[i] != 0 & s2[i] != 0)
        {
            char c1 = to_lower(s1[i]);
            char c2 = to_lower(s2[i]);
            if (c1 != c2)
            {
                return c1 - c2;
            };
            i = i + 1;
        };
        return to_lower(s1[i]) - to_lower(s2[i]);
    };
    
    // Check if string starts with prefix
    def starts_with(byte* str, byte* prefix) -> bool
    {
        int i = 0;
        while (prefix[i] != 0)
        {
            if (str[i] != prefix[i])
            {
                return false;
            };
            i = i + 1;
        };
        return true;
    };
    
    // Check if string ends with suffix
    def ends_with(byte* str, byte* suffix) -> bool
    {
        int str_len = 0;
        while (str[str_len] != 0) { str_len = str_len + 1; };
        
        int suffix_len = 0;
        while (suffix[suffix_len] != 0) { suffix_len = suffix_len + 1; };
        
        if (suffix_len > str_len)
        {
            return false;
        };
        
        int offset = str_len - suffix_len;
        for (int i = 0; i < suffix_len; i = i + 1)
        {
            if (str[offset + i] != suffix[i])
            {
                return false;
            };
        };
        return true;
    };
    
    
    // ===== STRING COPYING/MANIPULATION =====
    
    // Copy string (allocates new buffer)
    def copy_string(byte* src) -> byte*
    {
        int len = 0;
        while (src[len] != 0) { len = len + 1; };
        
        byte* dest = malloc(len + 1);
        if (dest == 0)
        {
            return (byte*)0;
        };
        
        for (int i = 0; i <= len; i = i + 1)
        {
            dest[i] = src[i];
        };
        
        return dest;
    };

    // Copy n characters (allocates new buffer with null terminator)
    def copy_n(byte* src, int n) -> byte*
    {
        byte* dest = malloc(n + 1);
        if (dest == 0)
        {
            return (byte*)0;
        };
        
        for (int i = 0; i < n & src[i] != 0; i = i + 1)
        {
            dest[i] = src[i];
        };
        dest[n] = (byte)0;
        
        return dest;
    };
    
    // Extract substring (allocates new buffer)
    def substring(byte* str, int start, int length) -> byte*
    {
        byte* result = malloc(length + 1);
        if (result == 0)
        {
            return (byte*)0;
        };
        
        for (int i = 0; i < length & str[start + i] != 0; i = i + 1)
        {
            result[i] = (byte)str[start + i];
        };
        result[length] = (byte)0;
        
        return result;
    };
    
    // Concatenate two strings (allocates new buffer)
    def concat(byte* s1, byte* s2) -> byte*
    {
        int len1 = 0;
        while (s1[len1] != 0) { len1 = len1 + 1; };
        
        int len2 = 0;
        while (s2[len2] != 0) { len2 = len2 + 1; };
        
        byte* result = malloc(len1 + len2 + 1);
        if (result == 0)
        {
            return (byte*)0;
        };
        
        for (int i = 0; i < len1; i = i + 1)
        {
            result[i] = s1[i];
        };
        for (int i = 0; i < len2; i = i + 1)
        {
            result[len1 + i] = s2[i];
        };
        result[len1 + len2] = (byte)0;
        
        return result;
    };
    
    
    // ===== STRING PARSING =====
    
    // Parse integer from string
    // Returns the parsed value, updates *end_pos to position after last digit
    def parse_int(byte* str, int start_pos, int* end_pos) -> int
    {
        int pos = skip_whitespace(str, start_pos);
        
        bool negative = false;
        if (str[pos] == '-')
        {
            negative = true;
            pos = pos + 1;
        }
        elif (str[pos] == '+')
        {
            pos = pos + 1;
        };
        
        int value = 0;
        while (is_digit(str[pos]))
        {
            value = value * 10 + (str[pos] - '0');
            pos = pos + 1;
        };
        
        *end_pos = pos;
        
        if (negative)
        {
            return -value;
        };
        return value;
    };
    
    // Parse hex integer (expects 0x prefix)
    def parse_hex(byte* str, int start_pos, int* end_pos) -> int
    {
        int pos = skip_whitespace(str, start_pos);
        
        // Skip 0x prefix
        if (str[pos] == '0' & (str[pos + 1] == 'x' | str[pos + 1] == 'X'))
        {
            pos = pos + 2;
        };
        
        int value = 0;
        while (is_hex_digit(str[pos]))
        {
            int digit = hex_to_int(str[pos]);
            value = value * 16 + digit;
            pos = pos + 1;
        };
        
        *end_pos = pos;
        return value;
    };
    
    
    // ===== LINE/WORD OPERATIONS =====
    
    // Count lines in string
    def count_lines(byte* str) -> int
    {
        int count = 0;
        for (int i = 0; str[i] != 0; i = i + 1)
        {
            if (str[i] == '\n')
            {
                count = count + 1;
            };
        };
        // Add 1 if string doesn't end with newline and isn't empty
        if (count > 0 | str[0] != 0)
        {
            count = count + 1;
        };
        return count;
    };
    
    // Get line at specific index (0-based)
    // Returns allocated string or null
    // Caller must free returned string
    def get_line(byte* str, int line_num) -> byte*
    {
        int current_line = 0;
        int line_start = 0;
        
        // Find start of target line
        for (int i = 0; str[i] != 0; i = i + 1)
        {
            if (current_line == line_num)
            {
                line_start = i;
                break;
            };
            if (str[i] == '\n')
            {
                current_line = current_line + 1;
            };
        };
        
        if (current_line != line_num)
        {
            return (byte*)0; // Line not found
        };
        
        // Find end of line
        int line_end = line_start;
        while (str[line_end] != 0 & str[line_end] != '\n')
        {
            line_end = line_end + 1;
        };
        
        // Copy line
        int line_len = line_end - line_start;
        return substring(str, line_start, line_len);
    };
    
    // Count words (whitespace-separated)
    def count_words(byte* str) -> int
    {
        int count = 0;
        bool in_word = false;
        
        for (int i = 0; str[i] != 0; i = i + 1)
        {
            if (is_whitespace(str[i]))
            {
                in_word = false;
            }
            elif (!in_word)
            {
                in_word = true;
                count = count + 1;
            };
        };
        
        return count;
    };

    
    // ===== REPLACEMENT =====
    
    // Replace first occurrence of 'find' with 'replace'
    // Returns new allocated string
    def replace_first(byte* str, byte* find, byte* replace) -> byte*
    {
        int pos = find_substring(str, find, 0);
        if (pos == -1)
        {
            return copy_string(str);
        };
        
        int str_len = 0;
        while (str[str_len] != 0) { str_len = str_len + 1; };
        
        int find_len = 0;
        while (find[find_len] != 0) { find_len = find_len + 1; };
        
        int replace_len = 0;
        while (replace[replace_len] != 0) { replace_len = replace_len + 1; };
        
        int new_len = str_len - find_len + replace_len;
        byte* result = malloc(new_len + 1);
        if (result == 0)
        {
            return (byte*)0;
        };
        
        // Copy before match
        for (int i = 0; i < pos; i = i + 1)
        {
            result[i] = str[i];
        };
        
        // Copy replacement
        for (int i = 0; i < replace_len; i = i + 1)
        {
            result[pos + i] = replace[i];
        };
        
        // Copy after match
        for (int i = pos + find_len; i <= str_len; i = i + 1)
        {
            result[i - find_len + replace_len] = str[i];
        };
        
        return result;
    };
    
    
    // ===== TOKENIZATION HELPERS (for lexer) =====
    
    // Skip until character found or end of string
    def skip_until(byte* str, int pos, char ch) -> int
    {
        while (str[pos] != 0 & str[pos] != ch)
        {
            pos = pos + 1;
        };
        return pos;
    };
    
    // Skip while condition is true
    def skip_while_digit(byte* str, int pos) -> int
    {
        while (str[pos] != 0 & is_digit(str[pos]))
        {
            pos = pos + 1;
        };
        return pos;
    };
    
    def skip_while_alnum(byte* str, int pos) -> int
    {
        while (str[pos] != 0 & is_alnum(str[pos]))
        {
            pos = pos + 1;
        };
        return pos;
    };
    
    def skip_while_identifier(byte* str, int pos) -> int
    {
        while (str[pos] != 0 & is_identifier_char(str[pos]))
        {
            pos = pos + 1;
        };
        return pos;
    };
    
    // Match at position (doesn't advance, just checks)
    def match_at(byte* str, int pos, byte* pattern) -> bool
    {
        int i = 0;
        while (pattern[i] != 0)
        {
            if (str[pos + i] != pattern[i])
            {
                return false;
            };
            i = i + 1;
        };
        return true;
    };
};

using string_utils;

#endif;
