// flexer.fx - Flux Language Lexer Implementation
// Translated from Python to Flux

#ifndef FLUX_LEXER
#def FLUX_LEXER 1;
#endif;

// Import necessary standard library components
#import "standard.fx";
#import "string_utils.fx";

// ============ TOKEN TYPE ENUMERATION ============
enum TokenType
{
    // Literals
    SINT_LITERAL,
    UINT_LITERAL,
    FLOAT,
    CHAR,
    STRING_LITERAL,
    BOOL,
    
    // String interpolation
    I_STRING,
    F_STRING,
    
    // Identifiers and keywords
    IDENTIFIER,
    
    // Keywords
    ALIGNOF,
    AND,
    AS,
    ASM,
    ASM_BLOCK,
    AT,
    ASSERT,
    AUTO,
    BREAK,
    BOOL_KW,
    CASE,
    CATCH,
    COMPT,
    CONST,
    CONTINUE,
    CONTRACT,
    DATA,
    DEF,
    DEFAULT,
    DO,
    ELIF,
    ELSE,
    ENUM,
    EXTERN,
    FALSE,
    FLOAT_KW,
    FOR,
    FROM,
    GLOBAL,
    HEAP,
    IF,
    IN,
    IS,
    SINT,  // int
    UINT,  // uint
    LOCAL,
    NAMESPACE,
    NOT,
    NO_INIT,
    OBJECT,
    OR,
    PRIVATE,
    PUBLIC,
    REGISTER,
    RETURN,
    SIGNED,
    SIZEOF,
    STACK,
    STRUCT,
    SWITCH,
    THIS,
    THROW,
    TRUE,
    TRY,
    TYPEOF,
    UNION,
    UNSIGNED,
    USING,
    VOID,
    VOLATILE,
    WHILE,
    XOR,
    
    // Operators
    PLUS,           // +
    MINUS,          // -
    MULTIPLY,       // *
    DIVIDE,         // /
    MODULO,         // %
    POWER,          // ^
    XOR_OP,         // ^^
    INCREMENT,      // ++
    DECREMENT,      // --
    LOGICAL_AND,    // &
    LOGICAL_OR,     // |
    BITAND_OP,      // `&
    BITOR_OP,       // `|
    
    // Comparison
    EQUAL,          // ==
    NOT_EQUAL,      // !=
    LESS_THAN,      // <
    LESS_EQUAL,     // <=
    GREATER_THAN,   // >
    GREATER_EQUAL,  // >=
    
    // Shift
    BITSHIFT_LEFT,     // <<
    BITSHIFT_RIGHT,    // >>
    
    // Assignment
    ASSIGN,         // =
    PLUS_ASSIGN,    // +=
    MINUS_ASSIGN,   // -=
    MULTIPLY_ASSIGN,// *=
    DIVIDE_ASSIGN,  // /=
    MODULO_ASSIGN,  // %=
    AND_ASSIGN,     // &=
    OR_ASSIGN,      // |=
    POWER_ASSIGN,   // ^=
    XOR_ASSIGN,     // ^^=
    BITSHIFT_LEFT_ASSIGN,  // <<=
    BITSHIFT_RIGHT_ASSIGN, // >>=
    
    // Other operators
    ADDRESS_OF,     // @
    RANGE,          // ..
    SCOPE,          // ::
    QUESTION,       // ?     ?: = Parse as ternary
    COLON,          // :
    TIE,           // ~ Ownership/move semantics

    // Directionals
    RETURN_ARROW,   // ->
    CHAIN_ARROW,    // <-
    RECURSE_ARROW,  // <~
    NULL_COALESCE,  // ??
    NO_MANGLE,      // !! tell the compiler not to mangle this name at all for any reason.

    // SPECIAL
    FUNCTION_POINTER, // {}*
    ADDRESS_CAST,     // (@)
    
    // Delimiters
    LEFT_PAREN,     // (
    RIGHT_PAREN,    // )
    LEFT_BRACKET,   // [
    RIGHT_BRACKET,  // ]
    LEFT_BRACE,     // {
    RIGHT_BRACE,    // }
    SEMICOLON,      // ;
    COMMA,          // ,
    DOT,            // .

    // Special
    EOF,
    NEWLINE
};


    // ============ TOKEN STRUCTURE ============
    object Token
    {
        //TokenType type;
        int type;
        noopstr value;
        i32 line;
        i32 column;
        
        def __init() -> this
        {
            this.type = TokenType.EOF;
            this.value = "\0";
            this.line = 0;
            this.column = 0;
            return this;
        };
        
        def __init(TokenType t, noopstr v, i32 l, i32 c) -> this
        {
            this.type = t;
            this.value = v;
            this.line = l;
            this.column = c;
            return this;
        };
        
        def __exit() -> void
        {
            // Cleanup if needed
            return;
        };
        
        def type_name() -> noopstr
        {
            // Simple type to name mapping with explicit null termination
            switch (this.type)
            {
                case (TokenType.SINT_LITERAL) {return "SINT_LITERAL\0";}
                case (TokenType.UINT_LITERAL) {return "UINT_LITERAL\0";}
                case (TokenType.FLOAT) {return "FLOAT\0";}
                case (TokenType.CHAR) {return "CHAR\0";}
                case (TokenType.STRING_LITERAL) {return "STRING_LITERAL\0";}
                case (TokenType.IDENTIFIER) {return "IDENTIFIER\0";}
                case (TokenType.ASM_BLOCK) {return "ASM_BLOCK\0";}
                case (TokenType.EOF) {return "EOF\0";}
                default {return "UNKNOWN\0";};
            };
        };
    };

namespace lexer
{

    // ============ LEXER CLASS ============
    object Lexer
    {
        noopstr source;
        i32 position;
        i32 line;
        i32 column;
        i32 length;
        
        // Keywords lookup table
        noopstr[100] keywords;
        TokenType[100] keyword_types;
        i32 keyword_count;
        
        def __init(noopstr source_code) -> this
        {
            this.source = source_code;
            this.position = 0;
            this.line = 1;
            this.column = 1;
            this.length = strlen(source_code);
            this.keyword_count = 0;
            
            // Initialize keywords
            this.init_keywords();
            return this;
        };
        
        def __exit() -> void
        {
            return;
        };
        
        def init_keywords() -> void
        {
            // Add all keywords to the lookup tables with explicit null termination
            this.add_keyword("alignof\0", TokenType.ALIGNOF);
            this.add_keyword("and\0", TokenType.AND);
            this.add_keyword("as\0", TokenType.AS);
            this.add_keyword("asm\0", TokenType.ASM);
            this.add_keyword("at\0", TokenType.AT);
            this.add_keyword("assert\0", TokenType.ASSERT);
            this.add_keyword("auto\0", TokenType.AUTO);
            this.add_keyword("break\0", TokenType.BREAK);
            this.add_keyword("bool\0", TokenType.BOOL_KW);
            this.add_keyword("case\0", TokenType.CASE);
            this.add_keyword("catch\0", TokenType.CATCH);
            this.add_keyword("compt\0", TokenType.COMPT);
            this.add_keyword("const\0", TokenType.CONST);
            this.add_keyword("continue\0", TokenType.CONTINUE);
            this.add_keyword("data\0", TokenType.DATA);
            this.add_keyword("def\0", TokenType.DEF);
            this.add_keyword("default\0", TokenType.DEFAULT);
            this.add_keyword("do\0", TokenType.DO);
            this.add_keyword("elif\0", TokenType.ELIF);
            this.add_keyword("else\0", TokenType.ELSE);
            this.add_keyword("enum\0", TokenType.ENUM);
            this.add_keyword("extern\0", TokenType.EXTERN);
            this.add_keyword("false\0", TokenType.FALSE);
            this.add_keyword("float\0", TokenType.FLOAT_KW);
            this.add_keyword("for\0", TokenType.FOR);
            this.add_keyword("from\0", TokenType.FROM);
            this.add_keyword("global\0", TokenType.GLOBAL);
            this.add_keyword("heap\0", TokenType.HEAP);
            this.add_keyword("if\0", TokenType.IF);
            this.add_keyword("in\0", TokenType.IN);
            this.add_keyword("is\0", TokenType.IS);
            this.add_keyword("int\0", TokenType.SINT);
            this.add_keyword("local\0", TokenType.LOCAL);
            this.add_keyword("namespace\0", TokenType.NAMESPACE);
            this.add_keyword("not\0", TokenType.NOT);
            this.add_keyword("noinit\0", TokenType.NO_INIT);
            this.add_keyword("object\0", TokenType.OBJECT);
            this.add_keyword("or\0", TokenType.OR);
            this.add_keyword("private\0", TokenType.PRIVATE);
            this.add_keyword("public\0", TokenType.PUBLIC);
            this.add_keyword("register\0", TokenType.REGISTER);
            this.add_keyword("return\0", TokenType.RETURN);
            this.add_keyword("signed\0", TokenType.SIGNED);
            this.add_keyword("sizeof\0", TokenType.SIZEOF);
            this.add_keyword("stack\0", TokenType.STACK);
            this.add_keyword("struct\0", TokenType.STRUCT);
            this.add_keyword("switch\0", TokenType.SWITCH);
            this.add_keyword("this\0", TokenType.THIS);
            this.add_keyword("throw\0", TokenType.THROW);
            this.add_keyword("true\0", TokenType.TRUE);
            this.add_keyword("try\0", TokenType.TRY);
            this.add_keyword("typeof\0", TokenType.TYPEOF);
            this.add_keyword("uint\0", TokenType.UINT);
            this.add_keyword("union\0", TokenType.UNION);
            this.add_keyword("unsigned\0", TokenType.UNSIGNED);
            this.add_keyword("using\0", TokenType.USING);
            this.add_keyword("void\0", TokenType.VOID);
            this.add_keyword("volatile\0", TokenType.VOLATILE);
            this.add_keyword("while\0", TokenType.WHILE);
            this.add_keyword("xor\0", TokenType.XOR);
        };
        
        def add_keyword(noopstr keyword, TokenType type) -> void
        {
            if (this.keyword_count < 100)
            {
                this.keywords[this.keyword_count] = keyword;
                this.keyword_types[this.keyword_count] = type;
                this.keyword_count = this.keyword_count + 1;
            };
        };
        
        def current_char() -> byte
        {
            if (this.position >= this.length)
            {
                return 0;
            };
            return this.source[this.position];
        };
        
        def peek_char(i32 offset) -> byte
        {
            i32 pos = this.position + offset;
            if (pos >= this.length)
            {
                return 0;
            };
            return this.source[pos];
        };
        
        def advance(i32 count) -> void
        {
            i32 i = 0;
            while (i < count & this.position < this.length)
            {
                if (this.source[this.position] == '\n')
                {
                    this.line = this.line + 1;
                    this.column = 1;
                }
                else
                {
                    this.column = this.column + 1;
                };
                this.position = this.position + 1;
                i = i + 1;
            };
        };
        
        def skip_whitespace() -> void
        {
            while (this.current_char() != 0)
            {
                byte c = this.current_char();
                if (c == ' ' | c == '\t' | c == '\r' | c == '\n')
                {
                    this.advance();
                }
                else
                {
                    break;
                };
            };
        };
        
        def read_string(byte quote_char) -> noopstr
        {
            // Allocate buffer with extra space for null terminator
            byte* buffer = malloc(1024);
            if (buffer == 0)
            {
                return "\0";
            };
            
            i32 buf_pos = 0;
            
            this.advance();  // Skip opening quote
            
            while (this.current_char() != 0 & this.current_char() != quote_char & buf_pos < 1023)
            {
                byte c = this.current_char();
                
                if (c == '\\')
                {
                    this.advance();
                    byte escape_char = this.current_char();
                    
                    if (escape_char == 'n')
                    {
                        buffer[buf_pos] = '\n';
                    }
                    elif (escape_char == 't')
                    {
                        buffer[buf_pos] = '\t';
                    }
                    elif (escape_char == 'r')
                    {
                        buffer[buf_pos] = '\r';
                    }
                    elif (escape_char == '0')
                    {
                        buffer[buf_pos] = 0;
                    }
                    elif (escape_char == '\\')
                    {
                        buffer[buf_pos] = '\\';
                    }
                    elif (escape_char == '\'' | escape_char == '"')
                    {
                        buffer[buf_pos] = escape_char;
                    }
                    elif (escape_char == 'x')
                    {
                        // Hex escape - simplified for now
                        this.advance();
                        byte hex1 = this.current_char();
                        this.advance();
                        byte hex2 = this.current_char();
                        // Would need hex conversion here
                        buffer[buf_pos] = '?'; // Placeholder
                    }
                    else
                    {
                        buffer[buf_pos] = escape_char;
                    };
                    
                    buf_pos = buf_pos + 1;
                    this.advance();
                }
                else
                {
                    buffer[buf_pos] = c;
                    buf_pos = buf_pos + 1;
                    this.advance();
                };
            };
            
            if (this.current_char() == quote_char)
            {
                this.advance();  // Skip closing quote
            };
            
            // Null terminate the string
            buffer[buf_pos] = 0;
            return buffer;
        };
        
        def read_number() -> Token
        {
            i32 start_line = this.line;
            i32 start_col = this.column;
            
            // Allocate buffer for the number
            byte* buffer = malloc(64);
            if (buffer == 0)
            {
                return Token(TokenType.SINT_LITERAL, "\0", start_line, start_col);
            };
            
            i32 buf_pos = 0;
            bool is_float = false;
            bool is_unsigned = false;
            
            // Check for special prefixes
            if (this.current_char() == '0')
            {
                buffer[buf_pos] = this.current_char();
                buf_pos = buf_pos + 1;
                this.advance();
                
                byte next_char = this.current_char();
                
                // Check for base prefixes
                if (next_char == 'd' | next_char == 'D')
                {
                    // Duotrigesimal (Base 32)
                    buffer[buf_pos] = this.current_char();
                    buf_pos = buf_pos + 1;
                    this.advance();
                    
                    while (this.current_char() != 0 & buf_pos < 63)
                    {
                        byte c = this.current_char();
                        if ((c >= '0' & c <= '9') | 
                            (c >= 'A' & c <= 'V') | 
                            (c >= 'a' & c <= 'v'))
                        {
                            buffer[buf_pos] = c;
                            buf_pos = buf_pos + 1;
                            this.advance();
                        }
                        else
                        {
                            break;
                        };
                    };
                    
                    // Check for unsigned suffix
                    if (this.current_char() == 'u')
                    {
                        is_unsigned = true;
                        this.advance();
                    };
                    
                    // Null terminate
                    buffer[buf_pos] = 0;
                    return Token(is_unsigned ? TokenType.UINT_LITERAL : TokenType.SINT_LITERAL, 
                               buffer, start_line, start_col);
                }
                elif (next_char == 'x' | next_char == 'X')
                {
                    // Hexadecimal
                    buffer[buf_pos] = this.current_char();
                    buf_pos = buf_pos + 1;
                    this.advance();
                    
                    while (this.current_char() != 0 & buf_pos < 63)
                    {
                        byte c = this.current_char();
                        if ((c >= '0' & c <= '9') | 
                            (c >= 'A' & c <= 'F') | 
                            (c >= 'a' & c <= 'f'))
                        {
                            buffer[buf_pos] = c;
                            buf_pos = buf_pos + 1;
                            this.advance();
                        }
                        else
                        {
                            break;
                        };
                    };
                    
                    // Check for unsigned suffix
                    if (this.current_char() == 'u')
                    {
                        is_unsigned = true;
                        this.advance();
                    };
                    
                    // Null terminate
                    buffer[buf_pos] = 0;
                    return Token(is_unsigned ? TokenType.UINT_LITERAL : TokenType.SINT_LITERAL, 
                               buffer, start_line, start_col);
                }
                elif (next_char == 'o' | next_char == 'O')
                {
                    // Octal
                    buffer[buf_pos] = this.current_char();
                    buf_pos = buf_pos + 1;
                    this.advance();
                    
                    while (this.current_char() != 0 & buf_pos < 63)
                    {
                        byte c = this.current_char();
                        if (c >= '0' & c <= '7')
                        {
                            buffer[buf_pos] = c;
                            buf_pos = buf_pos + 1;
                            this.advance();
                        }
                        else
                        {
                            break;
                        };
                    };
                    
                    // Check for unsigned suffix
                    if (this.current_char() == 'u')
                    {
                        is_unsigned = true;
                        this.advance();
                    };
                    
                    // Null terminate
                    buffer[buf_pos] = 0;
                    return Token(is_unsigned ? TokenType.UINT_LITERAL : TokenType.SINT_LITERAL, 
                               buffer, start_line, start_col);
                }
                elif (next_char == 'b' | next_char == 'B')
                {
                    // Binary
                    buffer[buf_pos] = this.current_char();
                    buf_pos = buf_pos + 1;
                    this.advance();
                    
                    while (this.current_char() != 0 & buf_pos < 63)
                    {
                        byte c = this.current_char();
                        if (c == '0' | c == '1')
                        {
                            buffer[buf_pos] = c;
                            buf_pos = buf_pos + 1;
                            this.advance();
                        }
                        else
                        {
                            break;
                        };
                    };
                    
                    // Check for unsigned suffix
                    if (this.current_char() == 'u')
                    {
                        is_unsigned = true;
                        this.advance();
                    };
                    
                    // Null terminate
                    buffer[buf_pos] = 0;
                    return Token(is_unsigned ? TokenType.UINT_LITERAL : TokenType.SINT_LITERAL, 
                               buffer, start_line, start_col);
                };
            };
            
            // Read decimal digits
            while (this.current_char() != 0 & buf_pos < 63)
            {
                byte c = this.current_char();
                if (c >= '0' & c <= '9')
                {
                    buffer[buf_pos] = c;
                    buf_pos = buf_pos + 1;
                    this.advance();
                }
                else
                {
                    break;
                };
            };
            
            // Check for decimal point
            if (this.current_char() == '.' & 
                this.peek_char() >= '0' & this.peek_char() <= '9')
            {
                is_float = true;
                buffer[buf_pos] = '.';
                buf_pos = buf_pos + 1;
                this.advance();
                
                while (this.current_char() != 0 & buf_pos < 63)
                {
                    byte c = this.current_char();
                    if (c >= '0' & c <= '9')
                    {
                        buffer[buf_pos] = c;
                        buf_pos = buf_pos + 1;
                        this.advance();
                    }
                    else
                    {
                        break;
                    };
                };
            };
            
            // Check for unsigned suffix (not for floats)
            if (!is_float & this.current_char() == 'u')
            {
                is_unsigned = true;
                this.advance();
            };
            
            // Null terminate
            buffer[buf_pos] = 0;
            
            TokenType token_type;
            if (is_float)
            {
                token_type = TokenType.FLOAT;
            }
            elif (is_unsigned)
            {
                token_type = TokenType.UINT_LITERAL;
            }
            else
            {
                token_type = TokenType.SINT_LITERAL;
            };
            
            return Token(token_type, buffer, start_line, start_col);
        };
        
        def read_identifier() -> Token
        {
            i32 start_line = this.line;
            i32 start_col = this.column;
            
            // Allocate buffer for identifier
            byte* buffer = malloc(256);
            if (buffer == 0)
            {
                return Token(TokenType.IDENTIFIER, "\0", start_line, start_col);
            };
            
            i32 buf_pos = 0;
            
            while (this.current_char() != 0 & buf_pos < 255)
            {
                byte c = this.current_char();
                if ((c >= 'a' & c <= 'z') | 
                    (c >= 'A' & c <= 'Z') | 
                    (c >= '0' & c <= '9') | 
                    c == '_')
                {
                    buffer[buf_pos] = c;
                    buf_pos = buf_pos + 1;
                    this.advance();
                }
                else
                {
                    break;
                };
            };
            
            // Null terminate
            buffer[buf_pos] = 0;
            
            // Check if it's a keyword
            TokenType token_type = TokenType.IDENTIFIER;
            
            i32 i = 0;
            while (i < this.keyword_count)
            {
                if (strcmp(buffer, this.keywords[i]) == 0)
                {
                    token_type = this.keyword_types[i];
                    break;
                };
                i = i + 1;
            };
            
            // Special handling for boolean literals
            if (strcmp(buffer, "true\0") == 0)
            {
                token_type = TokenType.TRUE;
            }
            elif (strcmp(buffer, "false\0") == 0)
            {
                token_type = TokenType.FALSE;
            };
            
            return Token(token_type, buffer, start_line, start_col);
        };
        
        def match_multi_char(noopstr pattern) -> bool
        {
            i32 len = strlen(pattern);
            i32 i = 0;
            while (i < len)
            {
                if (this.peek_char(i) != pattern[i])
                {
                    return false;
                };
                i = i + 1;
            };
            return true;
        };
        
        def tokenize() -> int
        {
            // Allocate array for tokens
            Token* tokens_ptr = malloc(1000 * sizeof(Token));
            if (tokens_ptr == 0)
            {
                // Return empty array
                Token[] empty;
                return empty;
            };
            
            Token[] tokens = @tokens_ptr[0];
            i32 token_count = 0;
            
            while (this.position < this.length & token_count < 1000)
            {
                // Skip whitespace
                byte c = this.current_char();
                if (c == ' ' | c == '\t' | c == '\r' | c == '\n')
                {
                    this.skip_whitespace();
                    continue;
                };
                
                i32 start_line = this.line;
                i32 start_col = this.column;
                
                // String literals
                if (c == '"' | c == '\'')
                {
                    noopstr str_content = this.read_string(c);
                    
                    // Check if it's a character literal
                    TokenType token_type;
                    if (c == '\'' & strlen(str_content) == 1)
                    {
                        token_type = TokenType.CHAR;
                    }
                    else
                    {
                        token_type = TokenType.STRING_LITERAL;
                    };
                    
                    tokens[token_count] = Token(token_type, str_content, start_line, start_col);
                    token_count = token_count + 1;
                    continue;
                };
                
                // Numbers
                if (c >= '0' & c <= '9')
                {
                    tokens[token_count] = this.read_number();
                    token_count = token_count + 1;
                    continue;
                };
                
                // Identifiers and keywords
                if ((c >= 'a' & c <= 'z') | 
                    (c >= 'A' & c <= 'Z') | 
                    c == '_')
                {
                    tokens[token_count] = this.read_identifier();
                    token_count = token_count + 1;
                    continue;
                };
                
                // Check for multi-character operators
                bool matched = false;
                
                // Triple-character operators
                if (this.match_multi_char("<<=\0"))
                {
                    byte* value = malloc(4);
                    if (value != 0)
                    {
                        value[0] = '<';
                        value[1] = '<';
                        value[2] = '=';
                        value[3] = 0;
                        tokens[token_count] = Token(TokenType.BITSHIFT_LEFT_ASSIGN, value, start_line, start_col);
                        token_count = token_count + 1;
                    };
                    this.advance(3);
                    matched = true;
                }
                elif (this.match_multi_char(">>=\0"))
                {
                    byte* value = malloc(4);
                    if (value != 0)
                    {
                        value[0] = '>';
                        value[1] = '>';
                        value[2] = '=';
                        value[3] = 0;
                        tokens[token_count] = Token(TokenType.BITSHIFT_RIGHT_ASSIGN, value, start_line, start_col);
                        token_count = token_count + 1;
                    };
                    this.advance(3);
                    matched = true;
                }
                elif (this.match_multi_char("^^=\0"))
                {
                    byte* value = malloc(4);
                    if (value != 0)
                    {
                        value[0] = '^';
                        value[1] = '^';
                        value[2] = '=';
                        value[3] = 0;
                        tokens[token_count] = Token(TokenType.XOR_ASSIGN, value, start_line, start_col);
                        token_count = token_count + 1;
                    };
                    this.advance(3);
                    matched = true;
                };
                
                if (!matched)
                {
                    // Double-character operators
                    if (this.match_multi_char("==\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '=';
                            value[1] = '=';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.EQUAL, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char("!=\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '!';
                            value[1] = '=';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.NOT_EQUAL, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char("<=\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '<';
                            value[1] = '=';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.LESS_EQUAL, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char(">=\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '>';
                            value[1] = '=';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.GREATER_EQUAL, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char("++\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '+';
                            value[1] = '+';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.INCREMENT, value, start_line, start_col);
                        token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char("--\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '-';
                            value[1] = '-';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.DECREMENT, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char("->\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '-';
                            value[1] = '>';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.RETURN_ARROW, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char("..\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '.';
                            value[1] = '.';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.RANGE, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char("::\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = ':';
                            value[1] = ':';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.SCOPE, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char("!!\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '!';
                            value[1] = '!';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.NO_MANGLE, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char("^^\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '^';
                            value[1] = '^';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.XOR_OP, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char("<<\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '<';
                            value[1] = '<';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.BITSHIFT_LEFT, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char(">>\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '>';
                            value[1] = '>';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.BITSHIFT_RIGHT, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    }
                    elif (this.match_multi_char("??\0"))
                    {
                        byte* value = malloc(3);
                        if (value != 0)
                        {
                            value[0] = '?';
                            value[1] = '?';
                            value[2] = 0;
                            tokens[token_count] = Token(TokenType.NULL_COALESCE, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance(2);
                        matched = true;
                    };
                };
                
                if (!matched)
                {
                    // Single-character operators
                    TokenType single_type = TokenType.EOF;
                    bool has_single = true;
                    
                    switch (c)
                    {
                        case ('+') {single_type = TokenType.PLUS;}
                        case ('-') {single_type = TokenType.MINUS;}
                        case ('*') {single_type = TokenType.MULTIPLY;}
                        case ('/') {single_type = TokenType.DIVIDE;}
                        case ('%') {single_type = TokenType.MODULO;}
                        case ('^') {single_type = TokenType.POWER;}
                        case ('<') {single_type = TokenType.LESS_THAN;}
                        case ('>') {single_type = TokenType.GREATER_THAN;}
                        case ('&') {single_type = TokenType.LOGICAL_AND;}
                        case ('|') {single_type = TokenType.LOGICAL_OR;}
                        case ('!') {single_type = TokenType.NOT;}
                        case ('@') {single_type = TokenType.ADDRESS_OF;}
                        case ('=') {single_type = TokenType.ASSIGN;}
                        case ('?') {single_type = TokenType.QUESTION;}
                        case (':') {single_type = TokenType.COLON;}
                        case ('(') {single_type = TokenType.LEFT_PAREN;}
                        case (')') {single_type = TokenType.RIGHT_PAREN;}
                        case ('[') {single_type = TokenType.LEFT_BRACKET;}
                        case (']') {single_type = TokenType.RIGHT_BRACKET;}
                        case ('{') {single_type = TokenType.LEFT_BRACE;}
                        case ('}') {single_type = TokenType.RIGHT_BRACE;}
                        case (';') {single_type = TokenType.SEMICOLON;}
                        case (',') {single_type = TokenType.COMMA;}
                        case ('.') {single_type = TokenType.DOT;}
                        case ('~') {single_type = TokenType.TIE;}
                        default {has_single = false;};
                    };
                    
                    if (has_single)
                    {
                        byte* value = malloc(2);
                        if (value != 0)
                        {
                            value[0] = c;
                            value[1] = 0;
                            tokens[token_count] = Token(single_type, value, start_line, start_col);
                            token_count = token_count + 1;
                        };
                        this.advance();
                    }
                    else
                    {
                        // Unknown character, skip it
                        this.advance();
                    };
                };
            };
            
            // Add EOF token
            if (token_count < 1000)
            {
                byte* eof_str = malloc(1);
                if (eof_str != 0)
                {
                    eof_str[0] = 0;
                    tokens[token_count] = Token(TokenType.EOF, eof_str, this.line, this.column);
                    token_count = token_count + 1;
                };
            };
            
            // Return slice of tokens
            return token_count;
        };
    };

    // ============ UTILITY FUNCTIONS ============
    def print_tokens(Token[] tokens, bool verbose) -> void
    {
        i32 count = 0;
        while (tokens[count].type != TokenType.EOF)
        {
            count = count + 1;
        };
        count = count + 1;  // Include EOF
        
        print("=== Tokens ===\0");
        print();
        
        i32 i = 0;
        while (i < count)
        {
            Token token = tokens[i];
            
            if (verbose)
            {
                print("Token \0");
                print(i + 1);
                print(": \0");
                print(token.type_name());
                print(" | '\0");
                print(token.value);
                print("' | Line \0");
                print(token.line);
                print(", Col \0");
                print(token.column);
                print();
            }
            else
            {
                print(token.type_name());
                print(" | '\0");
                print(token.value);
                print("' | L\0");
                print(token.line);
                print(":C\0");
                print(token.column);
                print();
            };
            i = i + 1;
        };
        
        print("Total tokens: \0");
        print(count);
        print();
    };
};

using lexer;

// Main function for testing
def main() -> int
{
    // Test the lexer with some sample code
    // Note: string literals in source code need null termination too
    noopstr test_code = "def hello() -> void\n{\n    print(\"Hello, Flux!\\0\");\n    return;\n}\0";
    
    Lexer lex = Lexer(test_code);
    //Token[] tokens = lex.tokenize();
    
    print("Testing Flux Lexer\0");
    print("==================\0");
    print();
    print_tokens(tokens, false);
    
    // Clean up allocated memory
    // Note: In a real application, you'd need to free all the token values
    // and the token array itself
    
    return 0;
};