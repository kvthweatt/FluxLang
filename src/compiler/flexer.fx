// Flux Language Lexer
// Copyright (C) 2026
// Based on flexer.py
//
// This lexer tokenizes Flux source code without using objects or structs
// Uses arrays and procedural programming style

#import "standard.fx";

enum Tokens
{
    // Token Type Constants
    i32 TOKEN_SINT_LITERAL = 0;
    i32 TOKEN_UINT_LITERAL = 1;
    i32 TOKEN_FLOAT = 2;
    i32 TOKEN_CHAR = 3;
    i32 TOKEN_STRING_LITERAL = 4;
    i32 TOKEN_BOOL = 5;
    i32 TOKEN_I_STRING = 6;
    i32 TOKEN_F_STRING = 7;
    i32 TOKEN_IDENTIFIER = 8;

    // Keywords
    i32 TOKEN_ALIGNOF = 9;
    i32 TOKEN_AND = 10;
    i32 TOKEN_AS = 11;
    i32 TOKEN_ASM = 12;
    i32 TOKEN_ASM_BLOCK = 13;
    i32 TOKEN_ASSERT = 14;
    i32 TOKEN_AUTO = 15;
    i32 TOKEN_BREAK = 16;
    i32 TOKEN_BOOL_KW = 17;
    i32 TOKEN_CASE = 18;
    i32 TOKEN_CATCH = 19;
    i32 TOKEN_CONST = 20;
    i32 TOKEN_CONTINUE = 21;
    i32 TOKEN_DATA = 22;
    i32 TOKEN_DEF = 23;
    i32 TOKEN_DEFAULT = 24;
    i32 TOKEN_DO = 25;
    i32 TOKEN_ELIF = 26;
    i32 TOKEN_ELSE = 27;
    i32 TOKEN_ENUM = 28;
    i32 TOKEN_EXTERN = 29;
    i32 TOKEN_FALSE = 30;
    i32 TOKEN_FLOAT_KW = 31;
    i32 TOKEN_FOR = 32;
    i32 TOKEN_GLOBAL = 33;
    i32 TOKEN_HEAP = 34;
    i32 TOKEN_IF = 35;
    i32 TOKEN_IN = 36;
    i32 TOKEN_IS = 37;
    i32 TOKEN_SINT = 38;
    i32 TOKEN_UINT = 39;
    i32 TOKEN_LOCAL = 40;
    i32 TOKEN_NAMESPACE = 41;
    i32 TOKEN_NOT = 42;
    i32 TOKEN_OBJECT = 43;
    i32 TOKEN_OR = 44;
    i32 TOKEN_PRIVATE = 45;
    i32 TOKEN_PUBLIC = 46;
    i32 TOKEN_REGISTER = 47;
    i32 TOKEN_RETURN = 48;
    i32 TOKEN_SIGNED = 49;
    i32 TOKEN_SIZEOF = 50;
    i32 TOKEN_STACK = 51;
    i32 TOKEN_STRUCT = 52;
    i32 TOKEN_SWITCH = 53;
    i32 TOKEN_THIS = 54;
    i32 TOKEN_THROW = 55;
    i32 TOKEN_TRUE = 56;
    i32 TOKEN_TRY = 57;
    i32 TOKEN_TYPEOF = 58;
    i32 TOKEN_UNION = 59;
    i32 TOKEN_UNSIGNED = 60;
    i32 TOKEN_VOID = 61;
    i32 TOKEN_VOLATILE = 62;
    i32 TOKEN_WHILE = 63;
    i32 TOKEN_XOR = 64;

    // Operators
    i32 TOKEN_PLUS = 65;
    i32 TOKEN_MINUS = 66;
    i32 TOKEN_MULTIPLY = 67;
    i32 TOKEN_DIVIDE = 68;
    i32 TOKEN_MODULO = 69;
    i32 TOKEN_POWER = 70;
    i32 TOKEN_XOR_OP = 71;
    i32 TOKEN_INCREMENT = 72;
    i32 TOKEN_DECREMENT = 73;
    i32 TOKEN_LOGICAL_AND = 74;
    i32 TOKEN_LOGICAL_OR = 75;

    // Comparison
    i32 TOKEN_EQUAL = 76;
    i32 TOKEN_NOT_EQUAL = 77;
    i32 TOKEN_LESS_THAN = 78;
    i32 TOKEN_LESS_EQUAL = 79;
    i32 TOKEN_GREATER_THAN = 80;
    i32 TOKEN_GREATER_EQUAL = 81;

    // Shift
    i32 TOKEN_BITSHIFT_LEFT = 82;
    i32 TOKEN_BITSHIFT_RIGHT = 83;

    // Assignment
    i32 TOKEN_ASSIGN = 84;
    i32 TOKEN_PLUS_ASSIGN = 85;
    i32 TOKEN_MINUS_ASSIGN = 86;
    i32 TOKEN_MULTIPLY_ASSIGN = 87;
    i32 TOKEN_DIVIDE_ASSIGN = 88;
    i32 TOKEN_MODULO_ASSIGN = 89;
    i32 TOKEN_AND_ASSIGN = 90;
    i32 TOKEN_OR_ASSIGN = 91;
    i32 TOKEN_POWER_ASSIGN = 92;
    i32 TOKEN_XOR_ASSIGN = 93;
    i32 TOKEN_BITSHIFT_LEFT_ASSIGN = 94;
    i32 TOKEN_BITSHIFT_RIGHT_ASSIGN = 95;

    // Other operators
    i32 TOKEN_ADDRESS_OF = 96;
    i32 TOKEN_RANGE = 97;
    i32 TOKEN_SCOPE = 98;
    i32 TOKEN_QUESTION = 99;
    i32 TOKEN_COLON = 100;
    i32 TOKEN_TIE = 101;

    // Directionals
    i32 TOKEN_RETURN_ARROW = 102;
    i32 TOKEN_CHAIN_ARROW = 103;
    i32 TOKEN_RECURSE_ARROW = 104;
    i32 TOKEN_NULL_COALESCE = 105;
    i32 TOKEN_NO_MANGLE = 106;

    // Special
    i32 TOKEN_FUNCTION_POINTER = 107;
    i32 TOKEN_ADDRESS_CAST = 108;

    // Delimiters
    i32 TOKEN_LEFT_PAREN = 109;
    i32 TOKEN_RIGHT_PAREN = 110;
    i32 TOKEN_LEFT_BRACKET = 111;
    i32 TOKEN_RIGHT_BRACKET = 112;
    i32 TOKEN_LEFT_BRACE = 113;
    i32 TOKEN_RIGHT_BRACE = 114;
    i32 TOKEN_SEMICOLON = 115;
    i32 TOKEN_COMMA = 116;
    i32 TOKEN_DOT = 117;

    // Special
    i32 TOKEN_EOF = 118;
    i32 TOKEN_NEWLINE = 119;
};


// Token arrays - we'll use parallel arrays to represent tokens
// Maximum tokens we can handle
i32 MAX_TOKENS = 10000;
i32 MAX_TOKEN_VALUE_LEN = 512;

// Token storage arrays
i32[10000] token_types;
byte[10000][512] token_values;
i32[10000] token_lines;
i32[10000] token_columns;
i32 token_count = 0;

// Lexer state
byte* source_code;
i32 source_length;
i32 position;
i32 line;
i32 column;

// Helper function to check if character is alphabetic
def is_alpha(byte c) -> bool
{
    return (c >= (byte)65 & c <= (byte)90) | (c >= (byte)97 & c <= (byte)122);
};

// Helper function to check if character is digit
def is_digit(byte c) -> bool
{
    return c >= (byte)48 & c <= (byte)57;
};

// Helper function to check if character is alphanumeric
def is_alnum(byte c) -> bool
{
    return is_alpha(c) | is_digit(c);
};

// Helper function to check if character is whitespace
def is_whitespace(byte c) -> bool
{
    return c == (byte)32 | c == (byte)9 | c == (byte)13;
};

// Get current character
def current_char() -> byte
{
    if (position >= source_length)
    {
        return (byte)0;
    };
    return source_code[position];
};

// Peek ahead n characters
def peek_char(i32 offset) -> byte
{
    i32 peek_pos = position + offset;
    if (peek_pos >= source_length)
    {
        return (byte)0;
    };
    return source_code[peek_pos];
};

// Advance position by count characters
def advance(i32 count) -> void
{
    i32 i = 0;
    while (i < count)
    {
        if (position >= source_length)
        {
            return;
        };
        
        byte ch = source_code[position];
        position++;
        
        if (ch == (byte)10) // newline
        {
            line++;
            column = 1;
        }
        else
        {
            column++;
        };
        
        i++;
    };
};

// Add a token to the token arrays
def add_token(i32 token_type, byte* value, i32 tok_line, i32 tok_col) -> void
{
    if (token_count >= MAX_TOKENS)
    {
        return; // Out of space
    };
    
    token_types[token_count] = token_type;
    token_lines[token_count] = tok_line;
    token_columns[token_count] = tok_col;
    
    // Copy value string
    i32 i = 0;
    while (value[i] != (byte)0 & i < MAX_TOKEN_VALUE_LEN - 1)
    {
        token_values[token_count][i] = value[i];
        i++;
    };
    token_values[token_count][i] = (byte)0;
    
    token_count++;
};

// String comparison helper
def str_equals(byte* s1, byte* s2) -> bool
{
    i32 i = 0;
    while (true)
    {
        if (s1[i] != s2[i])
        {
            return false;
        };
        if (s1[i] == (byte)0)
        {
            return true;
        };
        i++;
    };
    return false;
};

// Get keyword token type from identifier
def get_keyword_type(byte* identifier) -> i32
{
    if (str_equals(identifier, "alignof\0\0")) { return TOKEN_ALIGNOF; };
    if (str_equals(identifier, "and\0\0")) { return TOKEN_AND; };
    if (str_equals(identifier, "as\0\0")) { return TOKEN_AS; };
    if (str_equals(identifier, "asm\0\0")) { return TOKEN_ASM; };
    if (str_equals(identifier, "assert\0\0")) { return TOKEN_ASSERT; };
    if (str_equals(identifier, "auto\0\0")) { return TOKEN_AUTO; };
    if (str_equals(identifier, "break\0\0")) { return TOKEN_BREAK; };
    if (str_equals(identifier, "bool\0\0")) { return TOKEN_BOOL_KW; };
    if (str_equals(identifier, "case\0\0")) { return TOKEN_CASE; };
    if (str_equals(identifier, "catch\0\0")) { return TOKEN_CATCH; };
    if (str_equals(identifier, "const\0\0")) { return TOKEN_CONST; };
    if (str_equals(identifier, "continue\0\0")) { return TOKEN_CONTINUE; };
    if (str_equals(identifier, "data\0\0")) { return TOKEN_DATA; };
    if (str_equals(identifier, "def\0\0")) { return TOKEN_DEF; };
    if (str_equals(identifier, "default\0\0")) { return TOKEN_DEFAULT; };
    if (str_equals(identifier, "do\0\0")) { return TOKEN_DO; };
    if (str_equals(identifier, "elif\0\0")) { return TOKEN_ELIF; };
    if (str_equals(identifier, "else\0\0")) { return TOKEN_ELSE; };
    if (str_equals(identifier, "enum\0\0")) { return TOKEN_ENUM; };
    if (str_equals(identifier, "extern\0\0")) { return TOKEN_EXTERN; };
    if (str_equals(identifier, "false\0\0")) { return TOKEN_FALSE; };
    if (str_equals(identifier, "float\0\0")) { return TOKEN_FLOAT_KW; };
    if (str_equals(identifier, "for\0\0")) { return TOKEN_FOR; };
    if (str_equals(identifier, "global\0\0")) { return TOKEN_GLOBAL; };
    if (str_equals(identifier, "heap\0\0")) { return TOKEN_HEAP; };
    if (str_equals(identifier, "if\0\0")) { return TOKEN_IF; };
    if (str_equals(identifier, "in\0\0")) { return TOKEN_IN; };
    if (str_equals(identifier, "is\0\0")) { return TOKEN_IS; };
    if (str_equals(identifier, "int\0\0")) { return TOKEN_SINT; };
    if (str_equals(identifier, "uint\0\0")) { return TOKEN_UINT; };
    if (str_equals(identifier, "local\0\0")) { return TOKEN_LOCAL; };
    if (str_equals(identifier, "namespace\0\0")) { return TOKEN_NAMESPACE; };
    if (str_equals(identifier, "not\0\0")) { return TOKEN_NOT; };
    if (str_equals(identifier, "object\0\0")) { return TOKEN_OBJECT; };
    if (str_equals(identifier, "or\0\0")) { return TOKEN_OR; };
    if (str_equals(identifier, "private\0\0")) { return TOKEN_PRIVATE; };
    if (str_equals(identifier, "public\0\0")) { return TOKEN_PUBLIC; };
    if (str_equals(identifier, "register\0\0")) { return TOKEN_REGISTER; };
    if (str_equals(identifier, "return\0\0")) { return TOKEN_RETURN; };
    if (str_equals(identifier, "signed\0\0")) { return TOKEN_SIGNED; };
    if (str_equals(identifier, "sizeof\0\0")) { return TOKEN_SIZEOF; };
    if (str_equals(identifier, "stack\0\0")) { return TOKEN_STACK; };
    if (str_equals(identifier, "struct\0\0")) { return TOKEN_STRUCT; };
    if (str_equals(identifier, "switch\0\0")) { return TOKEN_SWITCH; };
    if (str_equals(identifier, "this\0\0")) { return TOKEN_THIS; };
    if (str_equals(identifier, "throw\0\0")) { return TOKEN_THROW; };
    if (str_equals(identifier, "true\0\0")) { return TOKEN_TRUE; };
    if (str_equals(identifier, "try\0\0")) { return TOKEN_TRY; };
    if (str_equals(identifier, "typeof\0\0")) { return TOKEN_TYPEOF; };
    if (str_equals(identifier, "union\0\0")) { return TOKEN_UNION; };
    if (str_equals(identifier, "unsigned\0\0")) { return TOKEN_UNSIGNED; };
    if (str_equals(identifier, "void\0\0")) { return TOKEN_VOID; };
    if (str_equals(identifier, "volatile\0\0")) { return TOKEN_VOLATILE; };
    if (str_equals(identifier, "while\0\0")) { return TOKEN_WHILE; };
    if (str_equals(identifier, "xor\0\0")) { return TOKEN_XOR; };
    
    return -1; // Not a keyword
};

// Read an identifier or keyword
def read_identifier(i32 start_line, i32 start_col) -> void
{
    byte[512] buffer;
    i32 buf_pos = 0;
    
    while (position < source_length & (is_alnum(current_char()) | current_char() == (byte)95))
    {
        if (buf_pos < 511)
        {
            buffer[buf_pos] = current_char();
            buf_pos++;
        };
        advance(1);
    };
    
    buffer[buf_pos] = (byte)0;
    
    // Check if it's a keyword
    i32 keyword_type = get_keyword_type(@buffer[0]);
    if (keyword_type != -1)
    {
        add_token(keyword_type, @buffer[0], start_line, start_col);
    }
    else
    {
        add_token(TOKEN_IDENTIFIER, @buffer[0], start_line, start_col);
    };
};

// Read a number (integer or float)
def read_number(i32 start_line, i32 start_col) -> void
{
    byte[512] buffer;
    i32 buf_pos = 0;
    bool is_hex = false;
    bool is_float = false;
    
    // Check for hex prefix
    if (current_char() == (byte)48 & (peek_char(1) == (byte)120 | peek_char(1) == (byte)88))
    {
        is_hex = true;
        buffer[buf_pos++] = current_char();
        advance(1);
        buffer[buf_pos++] = current_char();
        advance(1);
    };
    
    // Read digits
    while (position < source_length)
    {
        byte ch = current_char();
        
        if (is_hex)
        {
            if (is_digit(ch) | (ch >= (byte)65 & ch <= (byte)70) | (ch >= (byte)97 & ch <= (byte)102))
            {
                if (buf_pos < 511)
                {
                    buffer[buf_pos++] = ch;
                };
                advance(1);
            }
            else
            {
                break;
            };
        }
        else
        {
            if (is_digit(ch))
            {
                if (buf_pos < 511)
                {
                    buffer[buf_pos++] = ch;
                };
                advance(1);
            }
            else
            {
                if (ch == (byte)46) // decimal point
                {
                    is_float = true;
                    if (buf_pos < 511)
                    {
                        buffer[buf_pos++] = ch;
                    };
                    advance(1);
                }
                else
                {
                    break;
                };
            };
        };
    };
    
    // Check for 'u' suffix for unsigned integers
    bool is_unsigned = false;
    if (current_char() == (byte)117 | current_char() == (byte)85) // 'u' or 'U'
    {
        is_unsigned = true;
        advance(1);
    };
    
    buffer[buf_pos] = (byte)0;
    
    if (is_float)
    {
        add_token(TOKEN_FLOAT, @buffer[0], start_line, start_col);
    }
    else
    {
        if (is_unsigned)
        {
            add_token(TOKEN_UINT_LITERAL, @buffer[0], start_line, start_col);
        }
        else
        {
            add_token(TOKEN_SINT_LITERAL, @buffer[0], start_line, start_col);
        };
    };
};

// Read a string literal
def read_string(byte quote_char, i32 start_line, i32 start_col) -> void
{
    byte[512] buffer;
    i32 buf_pos = 0;
    
    advance(1); // Skip opening quote
    
    while (position < source_length & current_char() != quote_char)
    {
        byte ch = current_char();
        
        if (ch == (byte)92) // backslash - escape sequence
        {
            advance(1);
            if (position < source_length)
            {
                byte escaped = current_char();
                // Handle common escape sequences
                if (escaped == (byte)110) // \n
                {
                    if (buf_pos < 511)
                    {
                        buffer[buf_pos++] = (byte)10;
                    };
                }
                else
                {
                    if (escaped == (byte)116) // \t
                    {
                        if (buf_pos < 511)
                        {
                            buffer[buf_pos++] = (byte)9;
                        };
                    }
                    else
                    {
                        if (escaped == (byte)48) // \0
                        {
                            if (buf_pos < 511)
                            {
                                buffer[buf_pos++] = (byte)0;
                            };
                        }
                        else
                        {
                            // Just keep the escaped character
                            if (buf_pos < 511)
                            {
                                buffer[buf_pos++] = escaped;
                            };
                        };
                    };
                };
                advance(1);
            };
        }
        else
        {
            if (buf_pos < 511)
            {
                buffer[buf_pos++] = ch;
            };
            advance(1);
        };
    };
    
    if (current_char() == quote_char)
    {
        advance(1); // Skip closing quote
    };
    
    buffer[buf_pos] = (byte)0;
    
    // Check if it's a character literal (single quote with single char)
    if (quote_char == (byte)39 & buf_pos == 1)
    {
        add_token(TOKEN_CHAR, @buffer[0], start_line, start_col);
    }
    else
    {
        add_token(TOKEN_STRING_LITERAL, @buffer[0], start_line, start_col);
    };
};

// Skip single-line comment
def skip_line_comment() -> void
{
    while (position < source_length & current_char() != (byte)10)
    {
        advance(1);
    };
};

// Skip multi-line comment
def skip_block_comment() -> void
{
    advance(2); // Skip /*
    
    while (position < source_length - 1)
    {
        if (current_char() == (byte)42 & peek_char(1) == (byte)47) // */
        {
            advance(2);
            return;
        };
        advance(1);
    };
};

// Check if next chars match a string
def matches_string(byte* str, i32 len) -> bool
{
    i32 i = 0;
    while (i < len)
    {
        if (peek_char(i) != str[i])
        {
            return false;
        };
        i++;
    };
    return true;
};

// Main tokenize function
def tokenize(byte* source) -> i32
{
    // Initialize lexer state
    source_code = source;
    source_length = strlen(source);
    position = 0;
    line = 1;
    column = 1;
    token_count = 0;
    
    while (position < source_length)
    {
        i32 start_line = line;
        i32 start_col = column;
        byte ch = current_char();
        
        // Skip whitespace
        if (is_whitespace(ch))
        {
            advance(1);
            continue;
        };
        
        // Skip newlines
        if (ch == (byte)10)
        {
            advance(1);
            continue;
        };
        
        // Skip comments
        if (ch == (byte)47 & peek_char(1) == (byte)47) // //
        {
            skip_line_comment();
            continue;
        };
        
        if (ch == (byte)47 & peek_char(1) == (byte)42) // /*
        {
            skip_block_comment();
            continue;
        };
        
        // String literals
        if (ch == (byte)34 | ch == (byte)39) // " or '
        {
            read_string(ch, start_line, start_col);
            continue;
        };
        
        // Numbers
        if (is_digit(ch))
        {
            read_number(start_line, start_col);
            continue;
        };
        
        // Identifiers and keywords
        if (is_alpha(ch) | ch == (byte)95)
        {
            read_identifier(start_line, start_col);
            continue;
        };
        
        // Three-character operators
        if (matches_string("<<=\0\0", 3))
        {
            byte[4] op;
            op[0] = (byte)60; op[1] = (byte)60; op[2] = (byte)61; op[3] = (byte)0;
            add_token(TOKEN_BITSHIFT_LEFT_ASSIGN, @op[0], start_line, start_col);
            advance(3);
            continue;
        };
        
        if (matches_string(">>=\0\0", 3))
        {
            byte[4] op;
            op[0] = (byte)62; op[1] = (byte)62; op[2] = (byte)61; op[3] = (byte)0;
            add_token(TOKEN_BITSHIFT_RIGHT_ASSIGN, @op[0], start_line, start_col);
            advance(3);
            continue;
        };
        
        if (matches_string("^^=\0\0", 3))
        {
            byte[4] op;
            op[0] = (byte)94; op[1] = (byte)94; op[2] = (byte)61; op[3] = (byte)0;
            add_token(TOKEN_XOR_ASSIGN, @op[0], start_line, start_col);
            advance(3);
            continue;
        };
        
        if (matches_string("{}*\0\0", 3))
        {
            byte[4] op;
            op[0] = (byte)123; op[1] = (byte)125; op[2] = (byte)42; op[3] = (byte)0;
            add_token(TOKEN_FUNCTION_POINTER, @op[0], start_line, start_col);
            advance(3);
            continue;
        };
        
        if (matches_string("(@)\0\0", 3))
        {
            byte[4] op;
            op[0] = (byte)40; op[1] = (byte)64; op[2] = (byte)41; op[3] = (byte)0;
            add_token(TOKEN_ADDRESS_CAST, @op[0], start_line, start_col);
            advance(3);
            continue;
        };
        
        // Two-character operators
        if (matches_string("==\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)61; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_EQUAL, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("!=\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)33; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_NOT_EQUAL, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("!!\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)33; op[1] = (byte)33; op[2] = (byte)0;
            add_token(TOKEN_NO_MANGLE, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("??\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)63; op[1] = (byte)63; op[2] = (byte)0;
            add_token(TOKEN_NULL_COALESCE, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("<=\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)60; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_LESS_EQUAL, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string(">=\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)62; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_GREATER_EQUAL, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("<<\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)60; op[1] = (byte)60; op[2] = (byte)0;
            add_token(TOKEN_BITSHIFT_LEFT, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string(">>\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)62; op[1] = (byte)62; op[2] = (byte)0;
            add_token(TOKEN_BITSHIFT_RIGHT, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("++\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)43; op[1] = (byte)43; op[2] = (byte)0;
            add_token(TOKEN_INCREMENT, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("--\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)45; op[1] = (byte)45; op[2] = (byte)0;
            add_token(TOKEN_DECREMENT, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("+=\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)43; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_PLUS_ASSIGN, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("-=\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)45; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_MINUS_ASSIGN, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("*=\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)42; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_MULTIPLY_ASSIGN, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("/=\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)47; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_DIVIDE_ASSIGN, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("%=\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)37; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_MODULO_ASSIGN, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("^=\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)94; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_POWER_ASSIGN, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("&=\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)38; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_AND_ASSIGN, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("|=\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)124; op[1] = (byte)61; op[2] = (byte)0;
            add_token(TOKEN_OR_ASSIGN, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("&&\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)38; op[1] = (byte)38; op[2] = (byte)0;
            add_token(TOKEN_AND, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("||\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)124; op[1] = (byte)124; op[2] = (byte)0;
            add_token(TOKEN_OR, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("^^\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)94; op[1] = (byte)94; op[2] = (byte)0;
            add_token(TOKEN_XOR_OP, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("->\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)45; op[1] = (byte)62; op[2] = (byte)0;
            add_token(TOKEN_RETURN_ARROW, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("<-\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)60; op[1] = (byte)45; op[2] = (byte)0;
            add_token(TOKEN_CHAIN_ARROW, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("<~\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)60; op[1] = (byte)126; op[2] = (byte)0;
            add_token(TOKEN_RECURSE_ARROW, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("..\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)46; op[1] = (byte)46; op[2] = (byte)0;
            add_token(TOKEN_RANGE, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        if (matches_string("::\0\0", 2))
        {
            byte[3] op;
            op[0] = (byte)58; op[1] = (byte)58; op[2] = (byte)0;
            add_token(TOKEN_SCOPE, @op[0], start_line, start_col);
            advance(2);
            continue;
        };
        
        // Single-character tokens
        if (ch == (byte)43) // +
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_PLUS, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)45) // -
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_MINUS, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)42) // *
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_MULTIPLY, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)47) // /
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_DIVIDE, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)37) // %
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_MODULO, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)94) // ^
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_POWER, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)60) // <
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_LESS_THAN, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)62) // >
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_GREATER_THAN, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)38) // &
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_LOGICAL_AND, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)124) // |
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_LOGICAL_OR, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)33) // !
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_NOT, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)64) // @
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_ADDRESS_OF, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)61) // =
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_ASSIGN, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)63) // ?
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_QUESTION, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)58) // :
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_COLON, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)40) // (
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_LEFT_PAREN, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)41) // )
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_RIGHT_PAREN, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)91) // [
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_LEFT_BRACKET, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)93) // ]
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_RIGHT_BRACKET, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)123) // {
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_LEFT_BRACE, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)125) // }
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_RIGHT_BRACE, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)59) // ;
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_SEMICOLON, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)44) // ,
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_COMMA, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)46) // .
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_DOT, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        if (ch == (byte)126) // ~
        {
            byte[2] op;
            op[0] = ch; op[1] = (byte)0;
            add_token(TOKEN_TIE, @op[0], start_line, start_col);
            advance(1);
            continue;
        };
        
        // Unknown character - skip it
        advance(1);
    };
    
    // Add EOF token
    byte[4] eof_val;
    eof_val[0] = (byte)0;
    add_token(TOKEN_EOF, @eof_val[0], line, column);
    
    return token_count;
};

// Get token type name as string
def get_token_type_name(i32 type) -> byte*
{
    if (type == TOKEN_SINT_LITERAL) { return "SINT_LITERAL\0\0"; };
    if (type == TOKEN_UINT_LITERAL) { return "UINT_LITERAL\0\0"; };
    if (type == TOKEN_FLOAT) { return "FLOAT\0\0"; };
    if (type == TOKEN_CHAR) { return "CHAR\0\0"; };
    if (type == TOKEN_STRING_LITERAL) { return "STRING_LITERAL\0\0"; };
    if (type == TOKEN_BOOL) { return "BOOL\0\0"; };
    if (type == TOKEN_I_STRING) { return "I_STRING\0\0"; };
    if (type == TOKEN_F_STRING) { return "F_STRING\0\0"; };
    if (type == TOKEN_IDENTIFIER) { return "IDENTIFIER\0\0"; };
    if (type == TOKEN_ALIGNOF) { return "ALIGNOF\0\0"; };
    if (type == TOKEN_AND) { return "AND\0\0"; };
    if (type == TOKEN_AS) { return "AS\0\0"; };
    if (type == TOKEN_ASM) { return "ASM\0\0"; };
    if (type == TOKEN_ASSERT) { return "ASSERT\0\0"; };
    if (type == TOKEN_AUTO) { return "AUTO\0\0"; };
    if (type == TOKEN_BREAK) { return "BREAK\0\0"; };
    if (type == TOKEN_BOOL_KW) { return "BOOL_KW\0\0"; };
    if (type == TOKEN_CASE) { return "CASE\0\0"; };
    if (type == TOKEN_CATCH) { return "CATCH\0\0"; };
    if (type == TOKEN_CONST) { return "CONST\0\0"; };
    if (type == TOKEN_CONTINUE) { return "CONTINUE\0\0"; };
    if (type == TOKEN_DATA) { return "DATA\0\0"; };
    if (type == TOKEN_DEF) { return "DEF\0\0"; };
    if (type == TOKEN_DEFAULT) { return "DEFAULT\0\0"; };
    if (type == TOKEN_DO) { return "DO\0\0"; };
    if (type == TOKEN_ELIF) { return "ELIF\0\0"; };
    if (type == TOKEN_ELSE) { return "ELSE\0\0"; };
    if (type == TOKEN_ENUM) { return "ENUM\0\0"; };
    if (type == TOKEN_EXTERN) { return "EXTERN\0\0"; };
    if (type == TOKEN_FALSE) { return "FALSE\0\0"; };
    if (type == TOKEN_FLOAT_KW) { return "FLOAT_KW\0\0"; };
    if (type == TOKEN_FOR) { return "FOR\0\0"; };
    if (type == TOKEN_GLOBAL) { return "GLOBAL\0\0"; };
    if (type == TOKEN_HEAP) { return "HEAP\0\0"; };
    if (type == TOKEN_IF) { return "IF\0\0"; };
    if (type == TOKEN_IN) { return "IN\0\0"; };
    if (type == TOKEN_IS) { return "IS\0\0"; };
    if (type == TOKEN_SINT) { return "SINT\0\0"; };
    if (type == TOKEN_UINT) { return "UINT\0\0"; };
    if (type == TOKEN_LOCAL) { return "LOCAL\0\0"; };
    if (type == TOKEN_NAMESPACE) { return "NAMESPACE\0\0"; };
    if (type == TOKEN_NOT) { return "NOT\0\0"; };
    if (type == TOKEN_OBJECT) { return "OBJECT\0\0"; };
    if (type == TOKEN_OR) { return "OR\0\0"; };
    if (type == TOKEN_PRIVATE) { return "PRIVATE\0\0"; };
    if (type == TOKEN_PUBLIC) { return "PUBLIC\0\0"; };
    if (type == TOKEN_REGISTER) { return "REGISTER\0\0"; };
    if (type == TOKEN_RETURN) { return "RETURN\0\0"; };
    if (type == TOKEN_SIGNED) { return "SIGNED\0\0"; };
    if (type == TOKEN_SIZEOF) { return "SIZEOF\0\0"; };
    if (type == TOKEN_STACK) { return "STACK\0\0"; };
    if (type == TOKEN_STRUCT) { return "STRUCT\0\0"; };
    if (type == TOKEN_SWITCH) { return "SWITCH\0\0"; };
    if (type == TOKEN_THIS) { return "THIS\0\0"; };
    if (type == TOKEN_THROW) { return "THROW\0\0"; };
    if (type == TOKEN_TRUE) { return "TRUE\0\0"; };
    if (type == TOKEN_TRY) { return "TRY\0\0"; };
    if (type == TOKEN_TYPEOF) { return "TYPEOF\0\0"; };
    if (type == TOKEN_UNION) { return "UNION\0\0"; };
    if (type == TOKEN_UNSIGNED) { return "UNSIGNED\0\0"; };
    if (type == TOKEN_VOID) { return "VOID\0\0"; };
    if (type == TOKEN_VOLATILE) { return "VOLATILE\0\0"; };
    if (type == TOKEN_WHILE) { return "WHILE\0\0"; };
    if (type == TOKEN_XOR) { return "XOR\0\0"; };
    if (type == TOKEN_PLUS) { return "PLUS\0\0"; };
    if (type == TOKEN_MINUS) { return "MINUS\0\0"; };
    if (type == TOKEN_MULTIPLY) { return "MULTIPLY\0\0"; };
    if (type == TOKEN_DIVIDE) { return "DIVIDE\0\0"; };
    if (type == TOKEN_MODULO) { return "MODULO\0\0"; };
    if (type == TOKEN_POWER) { return "POWER\0\0"; };
    if (type == TOKEN_XOR_OP) { return "XOR_OP\0\0"; };
    if (type == TOKEN_INCREMENT) { return "INCREMENT\0\0"; };
    if (type == TOKEN_DECREMENT) { return "DECREMENT\0\0"; };
    if (type == TOKEN_LOGICAL_AND) { return "LOGICAL_AND\0\0"; };
    if (type == TOKEN_LOGICAL_OR) { return "LOGICAL_OR\0\0"; };
    if (type == TOKEN_EQUAL) { return "EQUAL\0\0"; };
    if (type == TOKEN_NOT_EQUAL) { return "NOT_EQUAL\0\0"; };
    if (type == TOKEN_LESS_THAN) { return "LESS_THAN\0\0"; };
    if (type == TOKEN_LESS_EQUAL) { return "LESS_EQUAL\0\0"; };
    if (type == TOKEN_GREATER_THAN) { return "GREATER_THAN\0\0"; };
    if (type == TOKEN_GREATER_EQUAL) { return "GREATER_EQUAL\0\0"; };
    if (type == TOKEN_BITSHIFT_LEFT) { return "BITSHIFT_LEFT\0\0"; };
    if (type == TOKEN_BITSHIFT_RIGHT) { return "BITSHIFT_RIGHT\0\0"; };
    if (type == TOKEN_ASSIGN) { return "ASSIGN\0\0"; };
    if (type == TOKEN_PLUS_ASSIGN) { return "PLUS_ASSIGN\0\0"; };
    if (type == TOKEN_MINUS_ASSIGN) { return "MINUS_ASSIGN\0\0"; };
    if (type == TOKEN_MULTIPLY_ASSIGN) { return "MULTIPLY_ASSIGN\0\0"; };
    if (type == TOKEN_DIVIDE_ASSIGN) { return "DIVIDE_ASSIGN\0\0"; };
    if (type == TOKEN_MODULO_ASSIGN) { return "MODULO_ASSIGN\0\0"; };
    if (type == TOKEN_AND_ASSIGN) { return "AND_ASSIGN\0\0"; };
    if (type == TOKEN_OR_ASSIGN) { return "OR_ASSIGN\0\0"; };
    if (type == TOKEN_POWER_ASSIGN) { return "POWER_ASSIGN\0\0"; };
    if (type == TOKEN_XOR_ASSIGN) { return "XOR_ASSIGN\0\0"; };
    if (type == TOKEN_BITSHIFT_LEFT_ASSIGN) { return "BITSHIFT_LEFT_ASSIGN\0\0"; };
    if (type == TOKEN_BITSHIFT_RIGHT_ASSIGN) { return "BITSHIFT_RIGHT_ASSIGN\0\0"; };
    if (type == TOKEN_ADDRESS_OF) { return "ADDRESS_OF\0\0"; };
    if (type == TOKEN_RANGE) { return "RANGE\0\0"; };
    if (type == TOKEN_SCOPE) { return "SCOPE\0\0"; };
    if (type == TOKEN_QUESTION) { return "QUESTION\0\0"; };
    if (type == TOKEN_COLON) { return "COLON\0\0"; };
    if (type == TOKEN_TIE) { return "TIE\0\0"; };
    if (type == TOKEN_RETURN_ARROW) { return "RETURN_ARROW\0\0"; };
    if (type == TOKEN_CHAIN_ARROW) { return "CHAIN_ARROW\0\0"; };
    if (type == TOKEN_RECURSE_ARROW) { return "RECURSE_ARROW\0\0"; };
    if (type == TOKEN_NULL_COALESCE) { return "NULL_COALESCE\0\0"; };
    if (type == TOKEN_NO_MANGLE) { return "NO_MANGLE\0\0"; };
    if (type == TOKEN_FUNCTION_POINTER) { return "FUNCTION_POINTER\0\0"; };
    if (type == TOKEN_ADDRESS_CAST) { return "ADDRESS_CAST\0\0"; };
    if (type == TOKEN_LEFT_PAREN) { return "LEFT_PAREN\0\0"; };
    if (type == TOKEN_RIGHT_PAREN) { return "RIGHT_PAREN\0\0"; };
    if (type == TOKEN_LEFT_BRACKET) { return "LEFT_BRACKET\0\0"; };
    if (type == TOKEN_RIGHT_BRACKET) { return "RIGHT_BRACKET\0\0"; };
    if (type == TOKEN_LEFT_BRACE) { return "LEFT_BRACE\0\0"; };
    if (type == TOKEN_RIGHT_BRACE) { return "RIGHT_BRACE\0\0"; };
    if (type == TOKEN_SEMICOLON) { return "SEMICOLON\0\0"; };
    if (type == TOKEN_COMMA) { return "COMMA\0\0"; };
    if (type == TOKEN_DOT) { return "DOT\0\0"; };
    if (type == TOKEN_EOF) { return "EOF\0\0"; };
    if (type == TOKEN_NEWLINE) { return "NEWLINE\0\0"; };
    
    return "UNKNOWN\0\0";
};

// Print all tokens (for testing/debugging)
def print_tokens() -> void
{
    i32 i = 0;
    while (i < token_count)
    {
        // This would need proper printf implementation
        // For now, this is a placeholder showing the structure
        i++;
    };
};

// Example main function for testing
def main(int* argc, byte** argv) -> int
{
    noopstr f = "examples\\malloc.fx\0";
    int size = get_file_size(f);
    byte* buffer = malloc((u64)size + 1);

    int bytes_read = read_file(f, buffer, size);
    
    i32 num_tokens = tokenize(@buffer);

    print("Flux Tokenizer v1.0.1 - Written in Flux
    Currently supports Flux source files that do not have preprocessor directives.\n\n\0");
    print("Token count: \0"); print(num_tokens);
    
    return 0;
};
