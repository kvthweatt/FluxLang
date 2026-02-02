// Flux Language Lexer
// Copyright (C) 2026 Karac Thweatt
// Complete 1:1 port of flexer.py to Flux

#import "standard.fx";

enum TokenType
{
    SINT_LITERAL, UINT_LITERAL, FLOAT, CHAR, STRING_LITERAL, BOOL, I_STRING, F_STRING, IDENTIFIER,
    ALIGNOF, AND, AS, ASM, ASM_BLOCK, ASSERT, AUTO, BREAK, BOOL_KW, CASE, CATCH, COMPT, CONST,
    CONTINUE, DATA, DEF, DEFAULT, DO, ELIF, ELSE, ENUM, EXTERN, FALSE, FLOAT_KW, FOR, FROM,
    GLOBAL, HEAP, IF, IN, IS, SINT, UINT, LOCAL, NAMESPACE, NOT, NO_INIT, OBJECT, OR, PRIVATE, PUBLIC,
    REGISTER, RETURN, SIGNED, SIZEOF, STACK, STRUCT, SWITCH, THIS, THROW, TRUE, TRY, TYPEOF, UNION,
    UNSIGNED, USING, VOID, VOLATILE, WHILE, XOR, PLUS, MINUS, MULTIPLY, DIVIDE, MODULO, POWER, XOR_OP,
    INCREMENT, DECREMENT, LOGICAL_AND, LOGICAL_OR, BITAND_OP, BITOR_OP, EQUAL, NOT_EQUAL, LESS_THAN,
    LESS_EQUAL, GREATER_THAN, GREATER_EQUAL, BITSHIFT_LEFT, BITSHIFT_RIGHT, ASSIGN, PLUS_ASSIGN,
    MINUS_ASSIGN, MULTIPLY_ASSIGN, DIVIDE_ASSIGN, MODULO_ASSIGN, AND_ASSIGN, OR_ASSIGN, POWER_ASSIGN,
    XOR_ASSIGN, BITSHIFT_LEFT_ASSIGN, BITSHIFT_RIGHT_ASSIGN, ADDRESS_OF, RANGE, SCOPE, QUESTION, COLON,
    TIE, RETURN_ARROW, CHAIN_ARROW, RECURSE_ARROW, NULL_COALESCE, NO_MANGLE, FUNCTION_POINTER, ADDRESS_CAST,
    LEFT_PAREN, RIGHT_PAREN, LEFT_BRACKET, RIGHT_BRACKET, LEFT_BRACE, RIGHT_BRACE, SEMICOLON, COMMA, DOT,
    EOF_TOKEN, NEWLINE
};

struct Token
{
    i32 type;
    byte[1024] value;
    i32 line;
    i32 column;
};

i64 MAX_TOKENS = (1000^2) * 100; // 100 million
Token[MAX_TOKENS] tokens;
i32 token_count = 0;

byte* source;
i32 length;
i32 position;
i32 line;
i32 column;

def current_char() -> byte
{
    if (position >= length) { return '\0'; };
    return source[position];
};

def peek_char(i32 offset) -> byte
{
    i32 pos = position + offset;
    if (pos >= length) { return '\0'; };
    return source[pos];
};

def advance_pos(i32 count) -> void
{
    i32 i = 0;
    while (i < count)
    {
        if (position >= length) { return; };
        if (source[position] == '\n')
        {
            line++;
            column = 1;
        }
        else
        {
            column++;
        };
        position++;
        i++;
    };
};

def add_token_str(i32 type, byte* value, i32 tok_line, i32 tok_col) -> void
{
    if (token_count >= MAX_TOKENS) { return; };
    tokens[token_count].type = type;
    strcpy(tokens[token_count].value, value);
    tokens[token_count].line = tok_line;
    tokens[token_count].column = tok_col;
    token_count++;
};

def keyword_to_token(byte* word) -> i32
{
    if (strcmp(word, "alignof") == 0) { return TokenType.ALIGNOF; };
    if (strcmp(word, "and") == 0) { return TokenType.AND; };
    if (strcmp(word, "as") == 0) { return TokenType.AS; };
    if (strcmp(word, "asm") == 0) { return TokenType.ASM; };
    if (strcmp(word, "assert") == 0) { return TokenType.ASSERT; };
    if (strcmp(word, "auto") == 0) { return TokenType.AUTO; };
    if (strcmp(word, "break") == 0) { return TokenType.BREAK; };
    if (strcmp(word, "bool") == 0) { return TokenType.BOOL_KW; };
    if (strcmp(word, "case") == 0) { return TokenType.CASE; };
    if (strcmp(word, "catch") == 0) { return TokenType.CATCH; };
    if (strcmp(word, "char") == 0) { return TokenType.CHAR; };
    if (strcmp(word, "compt") == 0) { return TokenType.COMPT; };
    if (strcmp(word, "const") == 0) { return TokenType.CONST; };
    if (strcmp(word, "continue") == 0) { return TokenType.CONTINUE; };
    if (strcmp(word, "data") == 0) { return TokenType.DATA; };
    if (strcmp(word, "def") == 0) { return TokenType.DEF; };
    if (strcmp(word, "default") == 0) { return TokenType.DEFAULT; };
    if (strcmp(word, "do") == 0) { return TokenType.DO; };
    if (strcmp(word, "elif") == 0) { return TokenType.ELIF; };
    if (strcmp(word, "else") == 0) { return TokenType.ELSE; };
    if (strcmp(word, "enum") == 0) { return TokenType.ENUM; };
    if (strcmp(word, "extern") == 0) { return TokenType.EXTERN; };
    if (strcmp(word, "false") == 0) { return TokenType.FALSE; };
    if (strcmp(word, "float") == 0) { return TokenType.FLOAT_KW; };
    if (strcmp(word, "for") == 0) { return TokenType.FOR; };
    if (strcmp(word, "from") == 0) { return TokenType.FROM; };
    if (strcmp(word, "global") == 0) { return TokenType.GLOBAL; };
    if (strcmp(word, "heap") == 0) { return TokenType.HEAP; };
    if (strcmp(word, "if") == 0) { return TokenType.IF; };
    if (strcmp(word, "in") == 0) { return TokenType.IN; };
    if (strcmp(word, "is") == 0) { return TokenType.IS; };
    if (strcmp(word, "int") == 0) { return TokenType.SINT; };
    if (strcmp(word, "local") == 0) { return TokenType.LOCAL; };
    if (strcmp(word, "namespace") == 0) { return TokenType.NAMESPACE; };
    if (strcmp(word, "not") == 0) { return TokenType.NOT; };
    if (strcmp(word, "noinit") == 0) { return TokenType.NO_INIT; };
    if (strcmp(word, "object") == 0) { return TokenType.OBJECT; };
    if (strcmp(word, "or") == 0) { return TokenType.OR; };
    if (strcmp(word, "private") == 0) { return TokenType.PRIVATE; };
    if (strcmp(word, "public") == 0) { return TokenType.PUBLIC; };
    if (strcmp(word, "register") == 0) { return TokenType.REGISTER; };
    if (strcmp(word, "return") == 0) { return TokenType.RETURN; };
    if (strcmp(word, "signed") == 0) { return TokenType.SIGNED; };
    if (strcmp(word, "sizeof") == 0) { return TokenType.SIZEOF; };
    if (strcmp(word, "stack") == 0) { return TokenType.STACK; };
    if (strcmp(word, "struct") == 0) { return TokenType.STRUCT; };
    if (strcmp(word, "switch") == 0) { return TokenType.SWITCH; };
    if (strcmp(word, "this") == 0) { return TokenType.THIS; };
    if (strcmp(word, "throw") == 0) { return TokenType.THROW; };
    if (strcmp(word, "true") == 0) { return TokenType.TRUE; };
    if (strcmp(word, "try") == 0) { return TokenType.TRY; };
    if (strcmp(word, "typeof") == 0) { return TokenType.TYPEOF; };
    if (strcmp(word, "uint") == 0) { return TokenType.UINT; };
    if (strcmp(word, "union") == 0) { return TokenType.UNION; };
    if (strcmp(word, "unsigned") == 0) { return TokenType.UNSIGNED; };
    if (strcmp(word, "using") == 0) { return TokenType.USING; };
    if (strcmp(word, "void") == 0) { return TokenType.VOID; };
    if (strcmp(word, "volatile") == 0) { return TokenType.VOLATILE; };
    if (strcmp(word, "while") == 0) { return TokenType.WHILE; };
    if (strcmp(word, "xor") == 0) { return TokenType.XOR; };
    return TokenType.IDENTIFIER;
};

def read_identifier() -> void
{
    i32 start_line = line;
    i32 start_col = column;
    byte[1024] buffer;
    i32 idx = 0;
    
    while (current_char() != '\0' & is_identifier_char(current_char()))
    {
        buffer[idx] = current_char();
        idx++;
        advance_pos(1);
    };
    buffer[idx] = '\0';
    
    byte* buf_ptr = buffer;
    i32 tok_type = keyword_to_token(buf_ptr);
    add_token_str(tok_type, buf_ptr, start_line, start_col);
};

def read_string(byte quote) -> void
{
    i32 start_line = line;
    i32 start_col = column;
    byte[1024] buffer;
    i32 idx = 0;
    
    advance_pos(1);
    
    while (current_char() != '\0' & current_char() != quote)
    {
        if (current_char() == '\\')
        {
            advance_pos(1);
            byte esc = current_char();
            if (esc == 'n') { buffer[idx] = '\n'; }
            else if (esc == 't') { buffer[idx] = '\t'; }
            else if (esc == 'r') { buffer[idx] = '\r'; }
            else if (esc == '0') { buffer[idx] = '\0'; }
            else if (esc == '\\') { buffer[idx] = '\\'; }
            else if (esc == '\'') { buffer[idx] = '\''; }
            else if (esc == '"') { buffer[idx] = '"'; }
            else if (esc == 'x')
            {
                advance_pos(1);
                byte h1 = current_char();
                advance_pos(1);
                byte h2 = current_char();
                i32 val = hex_to_int(h1) * 16 + hex_to_int(h2);
                buffer[idx] = (byte)val;
            }
            else { buffer[idx] = esc; };
            idx++;
            advance_pos(1);
        }
        else
        {
            buffer[idx] = current_char();
            idx++;
            advance_pos(1);
        };
    };
    
    if (current_char() == quote) { advance_pos(1); };
    buffer[idx] = '\0';
    
    i32 tok_type = TokenType.STRING_LITERAL;
    if (quote == '\'' & idx == 1) { tok_type = TokenType.CHAR; };
    byte* buf_ptr = buffer;
    add_token_str(tok_type, buf_ptr, start_line, start_col);
};

def read_number() -> void
{
    i32 start_line = line;
    i32 start_col = column;
    byte[1024] buffer;
    i32 idx = 0;
    bool is_float = false;
    bool is_unsigned = false;
    
    if (current_char() == '0')
    {
        buffer[idx] = current_char();
        idx++;
        advance_pos(1);
        
        byte next = current_char();
        if (next == 'x' | next == 'X')
        {
            buffer[idx] = next;
            idx++;
            advance_pos(1);
            while (is_hex_digit(current_char()))
            {
                buffer[idx] = current_char();
                idx++;
                advance_pos(1);
            };
        }
        else if (next == 'o' | next == 'O')
        {
            buffer[idx] = next;
            idx++;
            advance_pos(1);
            while (current_char() >= '0' & current_char() <= '7')
            {
                buffer[idx] = current_char();
                idx++;
                advance_pos(1);
            };
        }
        else if (next == 'b' | next == 'B')
        {
            buffer[idx] = next;
            idx++;
            advance_pos(1);
            while (current_char() == '0' | current_char() == '1')
            {
                buffer[idx] = current_char();
                idx++;
                advance_pos(1);
            };
        }
        else if (next == 'd' | next == 'D')
        {
            buffer[idx] = next;
            idx++;
            advance_pos(1);
            while ((current_char() >= '0' & current_char() <= '9') |
                   (current_char() >= 'A' & current_char() <= 'V'))
            {
                buffer[idx] = current_char();
                idx++;
                advance_pos(1);
            };
        };
    };
    
    while (is_digit(current_char()))
    {
        buffer[idx] = current_char();
        idx++;
        advance_pos(1);
    };
    
    if (current_char() == '.' & is_digit(peek_char(1)))
    {
        is_float = true;
        buffer[idx] = current_char();
        idx++;
        advance_pos(1);
        while (is_digit(current_char()))
        {
            buffer[idx] = current_char();
            idx++;
            advance_pos(1);
        };
    };
    
    if (!is_float & current_char() == 'u')
    {
        is_unsigned = true;
        advance_pos(1);
    };
    
    buffer[idx] = '\0';
    
    i32 tok_type = TokenType.SINT_LITERAL;
    if (is_float) { tok_type = TokenType.FLOAT; }
    else if (is_unsigned) { tok_type = TokenType.UINT_LITERAL; };
    
    byte* buf_ptr = buffer;
    add_token_str(tok_type, buf_ptr, start_line, start_col);
};

def read_asm_block() -> void
{
    i32 start_line = line;
    i32 start_col = column;
    byte[4096] buffer;
    i32 idx = 0;
    
    advance_pos(1);
    
    while (current_char() != '\0')
    {
        if (current_char() == '"' & peek_char(1) == '"')
        {
            advance_pos(2);
            break;
        };
        buffer[idx] = current_char();
        idx++;
        advance_pos(1);
    };
    
    buffer[idx] = '\0';
    byte* buf_ptr = buffer;
    add_token_str(TokenType.ASM_BLOCK, buf_ptr, start_line, start_col);
};

def read_asm_block_braces() -> void
{
    i32 start_line = line;
    i32 start_col = column;
    byte[4096] buffer;
    i32 idx = 0;
    
    skip_whitespace();
    if (current_char() != '{') { return; };
    
    advance_pos(1);
    i32 brace_depth = 1;
    
    while (current_char() != '\0' & brace_depth > 0)
    {
        if (current_char() == '{') { brace_depth++; }
        else if (current_char() == '}')
        {
            brace_depth--;
            if (brace_depth == 0) { break; };
        };
        buffer[idx] = current_char();
        idx++;
        advance_pos(1);
    };
    
    if (current_char() == '}') { advance_pos(1); };
    buffer[idx] = '\0';
    byte* buf_ptr = buffer;
    add_token_str(TokenType.ASM_BLOCK, buf_ptr, start_line, start_col);
};

def read_i_string() -> void
{
    i32 start_line = line;
    i32 start_col = column;
    byte[2048] buffer;
    i32 idx = 0;
    
    buffer[0] = 'i';
    buffer[1] = '"';
    idx = 2;
    
    advance_pos(1);
    while (current_char() != '\0' & current_char() != '"')
    {
        buffer[idx] = current_char();
        idx++;
        advance_pos(1);
    };
    
    buffer[idx] = '"';
    idx++;
    if (current_char() == '"') { advance_pos(1); };
    
    skip_whitespace();
    if (current_char() == ':')
    {
        buffer[idx] = ':';
        idx++;
        advance_pos(1);
    };
    
    skip_whitespace();
    if (current_char() == '{')
    {
        i32 brace_count = 1;
        buffer[idx] = current_char();
        idx++;
        advance_pos(1);
        
        while (current_char() != '\0' & brace_count > 0)
        {
            if (current_char() == '{') { brace_count++; }
            else if (current_char() == '}') { brace_count--; };
            buffer[idx] = current_char();
            idx++;
            advance_pos(1);
        };
    };
    
    buffer[idx] = '\0';
    byte* buf_ptr = buffer;
    add_token_str(TokenType.I_STRING, buf_ptr, start_line, start_col);
};

def read_f_string() -> void
{
    i32 start_line = line;
    i32 start_col = column;
    byte[2048] buffer;
    i32 idx = 0;
    
    buffer[0] = 'f';
    buffer[1] = '"';
    idx = 2;
    
    advance_pos(1);
    
    while (current_char() != '\0' & current_char() != '"')
    {
        if (current_char() == '{')
        {
            i32 brace_count = 1;
            buffer[idx] = current_char();
            idx++;
            advance_pos(1);
            
            while (current_char() != '\0' & brace_count > 0)
            {
                if (current_char() == '{') { brace_count++; }
                else if (current_char() == '}') { brace_count--; };
                buffer[idx] = current_char();
                idx++;
                advance_pos(1);
            };
        }
        else if (current_char() == '\\')
        {
            advance_pos(1);
            byte esc = current_char();
            if (esc == 'n') { buffer[idx] = '\n'; }
            else if (esc == 't') { buffer[idx] = '\t'; }
            else if (esc == 'r') { buffer[idx] = '\r'; }
            else if (esc == '0') { buffer[idx] = '\0'; }
            else if (esc == '\\') { buffer[idx] = '\\'; }
            else { buffer[idx] = esc; };
            idx++;
            advance_pos(1);
        }
        else
        {
            buffer[idx] = current_char();
            idx++;
            advance_pos(1);
        };
    };
    
    buffer[idx] = '"';
    idx++;
    if (current_char() == '"') { advance_pos(1); };
    buffer[idx] = '\0';
    
    byte* buf_ptr = buffer;
    add_token_str(TokenType.F_STRING, buf_ptr, start_line, start_col);
};

def tokenize(byte* src, i32 len) -> i32
{
    source = src;
    length = len;
    position = 0;
    line = 1;
    column = 1;
    token_count = 0;
    
    while (position < length)
    {
        skip_whitespace();
        if (position >= length) { break; };
        
        i32 start_line = line;
        i32 start_col = column;
        byte ch = current_char();
        
        if (ch == '/' & peek_char(1) == '/')
        {
            while (current_char() != '\0' & current_char() != '\n') { advance_pos(1); };
            continue;
        };
        
        if (ch == '/' & peek_char(1) == '*')
        {
            advance_pos(2);
            while (current_char() != '\0')
            {
                if (current_char() == '*' & peek_char(1) == '/') { advance_pos(2); break; };
                advance_pos(1);
            };
            continue;
        };
        
        if (ch == 'i' & peek_char(1) == '"') { advance_pos(1); read_i_string(); continue; };
        if (ch == 'f' & peek_char(1) == '"') { advance_pos(1); read_f_string(); continue; };
        
        if (ch == 'a' & peek_char(1) == 's' & peek_char(2) == 'm' & peek_char(3) == '"')
        {
            advance_pos(3);
            add_token_str(TokenType.ASM, "asm", start_line, start_col);
            read_asm_block();
            continue;
        };
        
        if (ch == '"' | ch == '\'') { read_string(ch); continue; };
        if (is_digit(ch)) { read_number(); continue; };
        
        if (is_identifier_start(ch))
        {
            read_identifier();
            if (tokens[token_count - 1].type == TokenType.ASM)
            {
                i32 saved_pos = position;
                i32 saved_line = line;
                i32 saved_col = column;
                skip_whitespace();
                if (current_char() == '{') { read_asm_block_braces(); continue; }
                else { position = saved_pos; line = saved_line; column = saved_col; };
            };
            continue;
        };
        
        byte c1 = ch;
        byte c2 = peek_char(1);
        byte c3 = peek_char(2);
        
        if (c1 == '<' & c2 == '<' & c3 == '=') { add_token_str(TokenType.BITSHIFT_LEFT_ASSIGN, "<<=", start_line, start_col); advance_pos(3); continue; };
        if (c1 == '>' & c2 == '>' & c3 == '=') { add_token_str(TokenType.BITSHIFT_RIGHT_ASSIGN, ">>=", start_line, start_col); advance_pos(3); continue; };
        if (c1 == '^' & c2 == '^' & c3 == '=') { add_token_str(TokenType.XOR_ASSIGN, "^^=", start_line, start_col); advance_pos(3); continue; };
        if (c1 == '{' & c2 == '}' & c3 == '*') { add_token_str(TokenType.FUNCTION_POINTER, "{}*", start_line, start_col); advance_pos(3); continue; };
        if (c1 == '(' & c2 == '@' & c3 == ')') { add_token_str(TokenType.ADDRESS_CAST, "(@)", start_line, start_col); advance_pos(3); continue; };
        
        if (c1 == '=' & c2 == '=') { add_token_str(TokenType.EQUAL, "==", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '!' & c2 == '=') { add_token_str(TokenType.NOT_EQUAL, "!=", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '!' & c2 == '!') { add_token_str(TokenType.NO_MANGLE, "!!", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '?' & c2 == '?') { add_token_str(TokenType.NULL_COALESCE, "??", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '<' & c2 == '=') { add_token_str(TokenType.LESS_EQUAL, "<=", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '>' & c2 == '=') { add_token_str(TokenType.GREATER_EQUAL, ">=", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '<' & c2 == '<') { add_token_str(TokenType.BITSHIFT_LEFT, "<<", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '>' & c2 == '>') { add_token_str(TokenType.BITSHIFT_RIGHT, ">>", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '+' & c2 == '+') { add_token_str(TokenType.INCREMENT, "++", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '-' & c2 == '-') { add_token_str(TokenType.DECREMENT, "--", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '+' & c2 == '=') { add_token_str(TokenType.PLUS_ASSIGN, "+=", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '-' & c2 == '=') { add_token_str(TokenType.MINUS_ASSIGN, "-=", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '*' & c2 == '=') { add_token_str(TokenType.MULTIPLY_ASSIGN, "*=", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '/' & c2 == '=') { add_token_str(TokenType.DIVIDE_ASSIGN, "/=", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '%' & c2 == '=') { add_token_str(TokenType.MODULO_ASSIGN, "%=", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '^' & c2 == '=') { add_token_str(TokenType.POWER_ASSIGN, "^=", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '&' & c2 == '=') { add_token_str(TokenType.AND_ASSIGN, "&=", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '|' & c2 == '=') { add_token_str(TokenType.OR_ASSIGN, "|=", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '^' & c2 == '^') { add_token_str(TokenType.XOR_OP, "^^", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '&' & c2 == '&') { add_token_str(TokenType.AND, "&&", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '|' & c2 == '|') { add_token_str(TokenType.OR, "||", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '-' & c2 == '>') { add_token_str(TokenType.RETURN_ARROW, "->", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '<' & c2 == '-') { add_token_str(TokenType.CHAIN_ARROW, "<-", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '<' & c2 == '~') { add_token_str(TokenType.RECURSE_ARROW, "<~", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '.' & c2 == '.') { add_token_str(TokenType.RANGE, "..", start_line, start_col); advance_pos(2); continue; };
        if (c1 == ':' & c2 == ':') { add_token_str(TokenType.SCOPE, "::", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '`' & c2 == '&') { add_token_str(TokenType.BITAND_OP, "`&", start_line, start_col); advance_pos(2); continue; };
        if (c1 == '`' & c2 == '|') { add_token_str(TokenType.BITOR_OP, "`|", start_line, start_col); advance_pos(2); continue; };
        
        if (ch == '+') { add_token_str(TokenType.PLUS, "+", start_line, start_col); advance_pos(1); continue; };
        if (ch == '-') { add_token_str(TokenType.MINUS, "-", start_line, start_col); advance_pos(1); continue; };
        if (ch == '*') { add_token_str(TokenType.MULTIPLY, "*", start_line, start_col); advance_pos(1); continue; };
        if (ch == '/') { add_token_str(TokenType.DIVIDE, "/", start_line, start_col); advance_pos(1); continue; };
        if (ch == '%') { add_token_str(TokenType.MODULO, "%", start_line, start_col); advance_pos(1); continue; };
        if (ch == '^') { add_token_str(TokenType.POWER, "^", start_line, start_col); advance_pos(1); continue; };
        if (ch == '<') { add_token_str(TokenType.LESS_THAN, "<", start_line, start_col); advance_pos(1); continue; };
        if (ch == '>') { add_token_str(TokenType.GREATER_THAN, ">", start_line, start_col); advance_pos(1); continue; };
        if (ch == '&') { add_token_str(TokenType.LOGICAL_AND, "&", start_line, start_col); advance_pos(1); continue; };
        if (ch == '|') { add_token_str(TokenType.LOGICAL_OR, "|", start_line, start_col); advance_pos(1); continue; };
        if (ch == '!') { add_token_str(TokenType.NOT, "!", start_line, start_col); advance_pos(1); continue; };
        if (ch == '@') { add_token_str(TokenType.ADDRESS_OF, "@", start_line, start_col); advance_pos(1); continue; };
        if (ch == '=') { add_token_str(TokenType.ASSIGN, "=", start_line, start_col); advance_pos(1); continue; };
        if (ch == '?') { add_token_str(TokenType.QUESTION, "?", start_line, start_col); advance_pos(1); continue; };
        if (ch == ':') { add_token_str(TokenType.COLON, ":", start_line, start_col); advance_pos(1); continue; };
        if (ch == '(') { add_token_str(TokenType.LEFT_PAREN, "(", start_line, start_col); advance_pos(1); continue; };
        if (ch == ')') { add_token_str(TokenType.RIGHT_PAREN, ")", start_line, start_col); advance_pos(1); continue; };
        if (ch == '[') { add_token_str(TokenType.LEFT_BRACKET, "[", start_line, start_col); advance_pos(1); continue; };
        if (ch == ']') { add_token_str(TokenType.RIGHT_BRACKET, "]", start_line, start_col); advance_pos(1); continue; };
        if (ch == '{') { add_token_str(TokenType.LEFT_BRACE, "{", start_line, start_col); advance_pos(1); continue; };
        if (ch == '}') { add_token_str(TokenType.RIGHT_BRACE, "}", start_line, start_col); advance_pos(1); continue; };
        if (ch == ';') { add_token_str(TokenType.SEMICOLON, ";", start_line, start_col); advance_pos(1); continue; };
        if (ch == ',') { add_token_str(TokenType.COMMA, ",", start_line, start_col); advance_pos(1); continue; };
        if (ch == '.') { add_token_str(TokenType.DOT, ".", start_line, start_col); advance_pos(1); continue; };
        if (ch == '~') { add_token_str(TokenType.TIE, "~", start_line, start_col); advance_pos(1); continue; };
        
        advance_pos(1);
    };
    
    add_token_str(TokenType.EOF_TOKEN, "", line, column);
    return token_count;
};
