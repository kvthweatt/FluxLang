import "standard.fx";

using standard::io, standard::types;

// Custom token type using 6-bit signed data
signed data{6} as TokDType;

// Token types as struct literal with assigned values
struct TokenType
{
    TokDType EOF = 0;
    TokDType IDENTIFIER = 1;
    TokDType NUMBER = 2;
    TokDType STRING = 3;
    TokDType CHAR = 4;
    TokDType KEYWORD = 5;
    TokDType OPERATOR = 6;
    TokDType DELIMITER = 7;
    TokDType COMMENT = 8;
    TokDType NEWLINE = 9;
    TokDType WHITESPACE = 10;
    TokDType I_STRING = 11;
    TokDType F_STRING = 12;
    TokDType ASM_BLOCK = 13;
    TokDType DATA_TYPE = 14;
    TokDType ERROR = -1;
};

// Token structure
struct Token
{
    TokDType ttype;
    string value;
    ui32 line;
    ui32 column;
    ui32 position;
};

// Lexer state structure
struct LexerState
{
    string source;
    ui32 position;
    ui32 line;
    ui32 column;
    ui32 length;
    char current_char;
    bool at_end;
};

// Keywords array - all Flux keywords
string[] keywords = [
    "alignof", "and", "as", "asm", "assert", "auto", "break", "bool", 
    "case", "catch", "const", "continue", "data", "def", "default",
    "do", "elif", "else", "false", "float", "for", "global", "if", 
    "import", "in", "is", "int", "namespace", "new", "not", "object", 
    "or", "private", "public", "return", "signed", "sizeof", "struct", 
    "super", "switch", "this", "throw", "true", "try", "typeof",
    "union", "unsigned", "void", "volatile", "while", "xor"
];

// Multi-character operators
string[] multi_char_operators = [
    "==", "!=", "<=", ">=", "&&", "||", "++", "--", "+=", "-=", 
    "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=", "<<", ">>",
    "::", "->", ".."
];

// Single-character operators and delimiters
string single_char_tokens = "+-*/%=<>!&|^~(){}[];,.:@?";

// Initialize lexer state
def init_lexer(string source) -> LexerState
{
    LexerState state;
    state.source = source;
    state.position = 0;
    state.line = 1;
    state.column = 1;
    state.length = sizeof(source);
    state.at_end = (state.length == 0);
    
    if (!state.at_end)
    {
        state.current_char = source[0];
    }
    else
    {
        state.current_char = "\0";
    };
    
    return state;
};

// Advance to next character
def advance(LexerState* state) -> void
{
    if (state->at_end) { return void; };
    
    state->position++;
    
    if (state->current_char == "\n")
    {
        state->line++;
        state->column = 1;
    }
    else
    {
        state->column++;
    };
    
    if (state->position >= state->length)
    {
        state->at_end = true;
        state->current_char = "\0";
    }
    else
    {
        state->current_char = state->source[state->position];
    };
};

// Peek at next character without advancing
def peek(LexerState* state) -> char
{
    if (state->position + 1 >= state->length)
    {
        return "\0";
    };
    return state->source[state->position + 1];
};

// Peek at character n positions ahead
def peek_n(LexerState* state, ui32 n) -> char
{
    if (state->position + n >= state->length)
    {
        return "\0";
    };
    return state->source[state->position + n];
};

// Check if character is alphabetic
def is_alpha(char c) -> bool
{
    return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_";
};

// Check if character is numeric
def is_digit(char c) -> bool
{
    return c >= "0" && c <= "9";
};

// Check if character is alphanumeric
def is_alnum(char c) -> bool
{
    return is_alpha(c) || is_digit(c);
};

// Check if character is whitespace (excluding newlines)
def is_whitespace(char c) -> bool
{
    return c == " " || c == "\t" || c == "\r";
};

// Check if character is hex digit
def is_hex_digit(char c) -> bool
{
    return is_digit(c) || (c >= "a" && c <= "f") || (c >= "A" && c <= "F");
};

// Check if string is a keyword
def is_keyword(string word) -> bool
{
    for (string keyword in keywords)
    {
        if (word == keyword)
        {
            return true;
        };
    };
    return false;
};

// Create a token
def make_token(TokDType ttype, string value, ui32 line, ui32 column, ui32 position) -> Token
{
    Token token;
    token.ttype = ttype;
    token.value = value;
    token.line = line;
    token.column = column;
    token.position = position;
    return token;
};

// Skip whitespace
def skip_whitespace(LexerState* state) -> void
{
    while (!state->at_end && is_whitespace(state->current_char))
    {
        advance(state);
    };
};

// Read identifier or keyword
def read_identifier(LexerState* state) -> Token
{
    ui32 start_line = state->line;
    ui32 start_column = state->column;
    ui32 start_position = state->position;
    string value = "";
    
    while (!state->at_end && is_alnum(state->current_char))
    {
        value += state->current_char;
        advance(state);
    };
    
    TokDType ttype = is_keyword(value) ? TokenType.KEYWORD : TokenType.IDENTIFIER;
    return make_token(ttype, value, start_line, start_column, start_position);
};

// Read number (integer, float, hex, binary)
def read_number(LexerState* state) -> Token
{
    ui32 start_line = state->line;
    ui32 start_column = state->column;
    ui32 start_position = state->position;
    string value = "";
    
    // Check for hex (0x) or binary (0b) prefix
    if (state->current_char == "0" && !state->at_end)
    {
        char next = peek(state);
        if (next == "x" || next == "X")
        {
            // Hexadecimal number
            value += state->current_char;
            advance(state);
            value += state->current_char;
            advance(state);
            
            while (!state->at_end && is_hex_digit(state->current_char))
            {
                value += state->current_char;
                advance(state);
            };
        }
        elif (next == "b" || next == "B")
        {
            // Binary number
            value += state->current_char;
            advance(state);
            value += state->current_char;
            advance(state);
            
            while (!state->at_end && (state->current_char == "0" || state->current_char == "1"))
            {
                value += state->current_char;
                advance(state);
            };
        }
        else
        {
            // Regular number starting with 0
            while (!state->at_end && is_digit(state->current_char))
            {
                value += state->current_char;
                advance(state);
            };
            
            // Check for decimal point
            if (!state->at_end && state->current_char == "." && is_digit(peek(state)))
            {
                value += state->current_char;
                advance(state);
                
                while (!state->at_end && is_digit(state->current_char))
                {
                    value += state->current_char;
                    advance(state);
                };
            };
        };
    }
    else
    {
        // Regular decimal number
        while (!state->at_end && is_digit(state->current_char))
        {
            value += state->current_char;
            advance(state);
        };
        
        // Check for decimal point
        if (!state->at_end && state->current_char == "." && is_digit(peek(state)))
        {
            value += state->current_char;
            advance(state);
            
            while (!state->at_end && is_digit(state->current_char))
            {
                value += state->current_char;
                advance(state);
            };
        };
    };
    
    return make_token(TokenType.NUMBER, value, start_line, start_column, start_position);
};

// Read string literal
def read_string(LexerState* state) -> Token
{
    ui32 start_line = state->line;
    ui32 start_column = state->column;
    ui32 start_position = state->position;
    string value = "";
    char quote_char = state->current_char;
    
    value += state->current_char; // Include opening quote
    advance(state);
    
    while (!state->at_end && state->current_char != quote_char)
    {
        if (state->current_char == "\\")
        {
            value += state->current_char;
            advance(state);
            if (!state->at_end)
            {
                value += state->current_char;
                advance(state);
            };
        }
        else
        {
            value += state->current_char;
            advance(state);
        };
    };
    
    if (!state->at_end)
    {
        value += state->current_char; // Include closing quote
        advance(state);
    };
    
    return make_token(TokenType.STRING, value, start_line, start_column, start_position);
};

// Read character literal
def read_char(LexerState* state) -> Token
{
    ui32 start_line = state->line;
    ui32 start_column = state->column;
    ui32 start_position = state->position;
    string value = "";
    
    value += state->current_char; // Include opening quote
    advance(state);
    
    if (!state->at_end)
    {
        if (state->current_char == "\\")
        {
            value += state->current_char;
            advance(state);
            if (!state->at_end)
            {
                value += state->current_char;
                advance(state);
            };
        }
        else
        {
            value += state->current_char;
            advance(state);
        };
    };
    
    if (!state->at_end && state->current_char == "")
    {
        value += state->current_char; // Include closing quote
        advance(state);
    };
    
    return make_token(TokenType.CHAR, value, start_line, start_column, start_position);
};

// Read i-string (interpolated string)
def read_i_string(LexerState* state) -> Token
{
    ui32 start_line = state->line;
    ui32 start_column = state->column;
    ui32 start_position = state->position;
    string value = "i";
    
    advance(state); // Skip "i"
    
    // Read the string part
    if (!state->at_end && state->current_char == "\"")
    {
        value += state->current_char;
        advance(state);
        
        while (!state->at_end && state->current_char != "\"")
        {
            value += state->current_char;
            advance(state);
        };
        
        if (!state->at_end)
        {
            value += state->current_char; // Closing quote
            advance(state);
        };
        
        // Look for the colon and statement block
        skip_whitespace(state);
        if (!state->at_end && state->current_char == ":")
        {
            value += state->current_char;
            advance(state);
            
            // Read until we find the matching brace structure
            ui32 brace_count = 0;
            bool found_opening = false;
            
            while (!state->at_end)
            {
                if (state->current_char == "{")
                {
                    brace_count++;
                    found_opening = true;
                }
                elif (state->current_char == "}")
                {
                    brace_count--;
                };
                
                value += state->current_char;
                advance(state);
                
                if (found_opening && brace_count == 0)
                {
                    break;
                };
            };
        };
    };
    
    return make_token(TokenType.I_STRING, value, start_line, start_column, start_position);
};

// Read f-string (formatted string)
def read_f_string(LexerState* state) -> Token
{
    ui32 start_line = state->line;
    ui32 start_column = state->column;
    ui32 start_position = state->position;
    string value = "f";
    
    advance(state); // Skip "f"
    
    if (!state->at_end && state->current_char == "\"")
    {
        value += state->current_char;
        advance(state);
        
        while (!state->at_end && state->current_char != "\"")
        {
            value += state->current_char;
            advance(state);
        };
        
        if (!state->at_end)
        {
            value += state->current_char; // Closing quote
            advance(state);
        };
    };
    
    return make_token(TokenType.F_STRING, value, start_line, start_column, start_position);
};

// Read assembly block
def read_asm_block(LexerState* state) -> Token
{
    ui32 start_line = state->line;
    ui32 start_column = state->column;
    ui32 start_position = state->position;
    string value = "asm";
    
    // Skip "asm"
    advance(state); advance(state); advance(state);
    
    skip_whitespace(state);
    
    if (!state->at_end && state->current_char == "{")
    {
        value += state->current_char;
        advance(state);
        
        ui32 brace_count = 1;
        while (!state->at_end && brace_count > 0)
        {
            if (state->current_char == "{")
            {
                brace_count++;
            }
            elif (state->current_char == "}")
            {
                brace_count--;
            };
            
            value += state->current_char;
            advance(state);
        };
    };
    
    return make_token(TokenType.ASM_BLOCK, value, start_line, start_column, start_position);
};

// Read single-line comment
def read_single_comment(LexerState* state) -> Token
{
    ui32 start_line = state->line;
    ui32 start_column = state->column;
    ui32 start_position = state->position;
    string value = "";
    
    while (!state->at_end && state->current_char != "\n")
    {
        value += state->current_char;
        advance(state);
    };
    
    return make_token(TokenType.COMMENT, value, start_line, start_column, start_position);
};

// Read multi-line comment
def read_multi_comment(LexerState* state) -> Token
{
    ui32 start_line = state->line;
    ui32 start_column = state->column;
    ui32 start_position = state->position;
    string value = "";
    
    value += state->current_char; // "/"
    advance(state);
    value += state->current_char; // "*"
    advance(state);
    
    while (!state->at_end)
    {
        if (state->current_char == "*" && peek(state) == "/")
        {
            value += state->current_char;
            advance(state);
            value += state->current_char;
            advance(state);
            break;
        };
        
        value += state->current_char;
        advance(state);
    };
    
    return make_token(TokenType.COMMENT, value, start_line, start_column, start_position);
};

// Read data type declaration
def read_data_type(LexerState* state) -> Token
{
    ui32 start_line = state->line;
    ui32 start_column = state->column;
    ui32 start_position = state->position;
    string value = "data";
    
    // Skip "data"
    advance(state); advance(state); advance(state); advance(state);
    
    skip_whitespace(state);
    
    // Read the bit width specification
    if (!state->at_end && state->current_char == "{")
    {
        ui32 brace_count = 1;
        value += state->current_char;
        advance(state);
        
        while (!state->at_end && brace_count > 0)
        {
            if (state->current_char == "{")
            {
                brace_count++;
            }
            elif (state->current_char == "}")
            {
                brace_count--;
            };
            
            value += state->current_char;
            advance(state);
        };
    };
    
    return make_token(TokenType.DATA_TYPE, value, start_line, start_column, start_position);
};

// Get next token
def next_token(LexerState* state) -> Token
{
    while (!state->at_end)
    {
        // Skip whitespace
        if (is_whitespace(state->current_char))
        {
            skip_whitespace(state);
            continue;
        };
        
        // Newlines
        if (state->current_char == "\n")
        {
            Token token = make_token(TokenType.NEWLINE, "\n", state->line, state->column, state->position);
            advance(state);
            return token;
        };
        
        // Comments
        if (state->current_char == "/" && peek(state) == "/")
        {
            return read_single_comment(state);
        };
        
        if (state->current_char == "/" && peek(state) == "*")
        {
            return read_multi_comment(state);
        };
        
        // Identifiers and keywords
        if (is_alpha(state->current_char))
        {
            // Check for special prefixed strings
            if (state->current_char == "i" && peek(state) == """)
            {
                return read_i_string(state);
            };
            
            if (state->current_char == "f" && peek(state) == """)
            {
                return read_f_string(state);
            };
            
            // Check for asm block
            if (state->current_char == "a" && peek(state) == "s" && peek_n(state, 2) == "m" && 
                !is_alnum(peek_n(state, 3)))
            {
                return read_asm_block(state);
            };
            
            // Check for data type
            if (state->current_char == "d" && peek(state) == "a" && peek_n(state, 2) == "t" && 
                peek_n(state, 3) == "a" && !is_alnum(peek_n(state, 4)))
            {
                return read_data_type(state);
            };
            
            return read_identifier(state);
        };
        
        // Numbers
        if (is_digit(state->current_char))
        {
            return read_number(state);
        };
        
        // String literals
        if (state->current_char == "\"")
        {
            return read_string(state);
        };
        
        // Character literals
        if (state->current_char == "\"")
        {
            return read_char(state);
        };
        
        // Multi-character operators
        for (string op in multi_char_operators)
        {
            ui32 op_len = sizeof(op);
            bool matches = true;
            
            for (ui32 i = 0; i < op_len; i++)
            {
                if (peek_n(state, i) != op[i])
                {
                    matches = false;
                    break;
                };
            };
            
            if (matches)
            {
                Token token = make_token(TokenType.OPERATOR, op, state->line, state->column, state->position);
                for (ui32 i = 0; i < op_len; i++)
                {
                    advance(state);
                };
                return token;
            };
        };
        
        // Single-character operators and delimiters
        for (ui32 i = 0; i < sizeof(single_char_tokens); i++)
        {
            if (state->current_char == single_char_tokens[i])
            {
                string value = "";
                value += state->current_char;
                TokDType ttype = TokenType.OPERATOR;
                
                // Classify as delimiter for certain characters
                if (state->current_char == "(" || state->current_char == ")" ||
                    state->current_char == "{" || state->current_char == "}" ||
                    state->current_char == "[" || state->current_char == "]" ||
                    state->current_char == ";" || state->current_char == "," ||
                    state->current_char == ":")
                {
                    ttype = TokenType.DELIMITER;
                };
                
                Token token = make_token(ttype, value, state->line, state->column, state->position);
                advance(state);
                return token;
            };
        };
        
        // Unknown character - create error token
        string error_value = "";
        error_value += state->current_char;
        Token token = make_token(TokenType.ERROR, error_value, state->line, state->column, state->position);
        advance(state);
        return token;
    };
    
    // End of file
    return make_token(TokenType.EOF, "", state->line, state->column, state->position);
};

// Convert token type to string for debugging
def token_type_to_string(TokDType ttype) -> string
{
    if (ttype == TokenType.EOF) { return "EOF"; };
    if (ttype == TokenType.IDENTIFIER) { return "IDENTIFIER"; };
    if (ttype == TokenType.NUMBER) { return "NUMBER"; };
    if (ttype == TokenType.STRING) { return "STRING"; };
    if (ttype == TokenType.CHAR) { return "CHAR"; };
    if (ttype == TokenType.KEYWORD) { return "KEYWORD"; };
    if (ttype == TokenType.OPERATOR) { return "OPERATOR"; };
    if (ttype == TokenType.DELIMITER) { return "DELIMITER"; };
    if (ttype == TokenType.COMMENT) { return "COMMENT"; };
    if (ttype == TokenType.NEWLINE) { return "NEWLINE"; };
    if (ttype == TokenType.WHITESPACE) { return "WHITESPACE"; };
    if (ttype == TokenType.I_STRING) { return "I_STRING"; };
    if (ttype == TokenType.F_STRING) { return "F_STRING"; };
    if (ttype == TokenType.ASM_BLOCK) { return "ASM_BLOCK"; };
    if (ttype == TokenType.DATA_TYPE) { return "DATA_TYPE"; };
    if (ttype == TokenType.ERROR) { return "ERROR"; };
    return "UNKNOWN";
};

// Print token for debugging
def print_token(Token token) -> void
{
    print(f"Token({token_type_to_string(token.ttype)}, "{token.value}", {token.line}:{token.column})");
};

// Main lexer function - tokenize entire source
def tokenize(string source) -> Token[]
{
    LexerState state = init_lexer(source);
    Token[] tokens;
    
    while (true)
    {
        Token token = next_token(@state);
        tokens += token;
        
        if (token.ttype == TokenType.EOF)
        {
            break;
        };
    };
    
    return tokens;
};

// Example usage and test function
def main() -> int
{
    string test_source = "
def factorial(int n) -> int
{
    if (n <= 1) { return 1; };
    return n * factorial(n - 1);
};

unsigned data{8}[] as string;
string greeting = f\"Hello {name}!\";
int x = 0xFF;
float pi = 3.14159;

asm
{
    mov eax, 1
    int 0x80
};";
    print("Tokenizing Flux source code...");
    Token[] tokens = tokenize(test_source);
    
    print(f"Found {sizeof(tokens) / sizeof(Token)} tokens:");
    
    for (Token token in tokens)
    {
        if (token.ttype != TokenType.NEWLINE && token.ttype != TokenType.WHITESPACE)
        {
            print_token(token);
        };
    };
    
    return 0;
};