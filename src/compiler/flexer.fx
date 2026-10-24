// Author: Karac V. Thweatt
//
// flexer.fx - Flux lexer library (port of flexer.py)
//
// Usage from fxc.fx:
//
//     #import "flexer.fx";
//     using flux::lexer;
//
//     Lexer lx(source_bytes, source_length);
//     if (!lx.tokenize()) { /* lx.err_code, lx.err_line, lx.err_col */ };
//     for (int i = 0; i < lx.count; i++)
//     {
//         Token t = lx.tokens[i];
//         byte* v = lx.token_value(i);   // null terminated, t.vlen bytes
//     };
//
// The lexer does not copy the source. The caller keeps `source` alive for the
// lifetime of the Lexer. The source must already be preprocessed text.
//
// Token values live in a lexer-owned arena. Every value is null terminated,
// and Token.vlen holds the length without the terminator because values can
// contain embedded zero bytes (the \0 escape).

#ifndef FLUX_STANDARD
#import <standard.fx>;
#endif;

#ifndef FLUX_LEXER
#def FLUX_LEXER 1;

namespace flux
{
    namespace lexer
    {
        enum TokenType
        {
            SINT_LITERAL,
            UINT_LITERAL,
            SLONG_LITERAL,
            ULONG_LITERAL,
            FLOAT,
            DOUBLE,
            BYTE_LITERAL,
            CHAR,
            STRING_LITERAL,
            BOOL,
            I_STRING,
            F_STRING,
            G_STRING,
            IDENTIFIER,
            ALIGNOF,
            ASSERT,
            ENDIANOF,
            SIZEOF,
            TYPEOF,
            AND,
            AS,
            ASM,
            ASM_BLOCK,
            ASYNC,
            AUTO,
            BREAK,
            BOOL_KW,
            BYTE,
            CASE,
            CATCH,
            COMPT,
            CONST,
            CONSTRAINT,
            CONTINUE,
            CONTRACT,
            DATA,
            DEF,
            DEFER,
            DEFAULT,
            DEPRECATE,
            DICT,
            DO,
            DOUBLE_KW,
            ELIF,
            ELSE,
            ENUM,
            EFFECT,
            ESCAPE_KW,
            EXPORT,
            EXTERN,
            FALSE,
            FASTNODE,
            FLOAT_KW,
            FOR,
            FROM,
            GLOBAL,
            GOTO,
            HAS,
            HEAP,
            IF,
            IN,
            INLINE,
            SINT,
            INTERFACE,
            IS,
            JUMP,
            LABEL,
            LOCAL,
            SLONG,
            ULONG,
            UINT,
            MACRO,
            NAMESPACE,
            NOT,
            NO_INIT,
            NORET,
            OBJECT,
            OPERATOR,
            OR,
            PRIVATE,
            PUBLIC,
            REGISTER,
            RETURN,
            SIGNED,
            SINGINIT,
            STACK,
            STRUCT,
            SWITCH,
            THIS,
            THROW,
            TRAIT,
            TRUE,
            TRY,
            UNION,
            UNSIGNED,
            USING,
            VECTOR,
            VOID,
            VOLATILE,
            WHILE,
            XOR,
            CDECL,
            STDCALL,
            FASTCALL,
            THISCALL,
            VECTORCALL,
            COMPTIME,
            EMITFLUX,
            FLUXVM,
            FLUXVM_BLOCK,
            PLUS,
            MINUS,
            INCREMENT,
            DECREMENT,
            MULTIPLY,
            DIVIDE,
            MODULO,
            EXPONENT,
            LOGICAL_AND,
            LOGICAL_OR,
            NAND_OP,
            NOR_OP,
            XOR_OP,
            EQUAL,
            NOT_EQUAL,
            LESS_THAN,
            LESS_EQUAL,
            GREATER_THAN,
            GREATER_EQUAL,
            ASSIGN,
            PLUS_ASSIGN,
            MINUS_ASSIGN,
            MULTIPLY_ASSIGN,
            DIVIDE_ASSIGN,
            MODULO_ASSIGN,
            EXPONENT_ASSIGN,
            BACKTICK,
            BITNOT_OP,
            BITAND_OP,
            BITOR_OP,
            BITNAND_OP,
            BITNOR_OP,
            BITXOR_OP,
            BITXNOT,
            BITXNAND,
            BITXNOR,
            AND_ASSIGN,
            OR_ASSIGN,
            XOR_ASSIGN,
            BITAND_ASSIGN,
            BITOR_ASSIGN,
            BITNAND_ASSIGN,
            BITNOR_ASSIGN,
            BITXOR_ASSIGN,
            BITXNOT_ASSIGN,
            BITXNAND_ASSIGN,
            BITXNOR_ASSIGN,
            BITSHIFT_LEFT,
            BITSHIFT_RIGHT,
            BITSHIFT_LEFT_ASSIGN,
            BITSHIFT_RIGHT_ASSIGN,
            ADDRESS_OF,
            RANGE,
            ELLIPSIS,
            SCOPE,
            QUESTION,
            TERNARY_ASSIGN,
            ADDRESS_ASSIGN,
            NULL_COALESCE,
            NOT_NULL,
            COLON,
            TIE,
            RETURN_ARROW,
            CHAIN_ARROW,
            RECURSE_ARROW,
            NO_MANGLE,
            FUNCTION_POINTER,
            ADDRESS_CAST,
            STRINGIFY,
            CODIFY,
            BITSLICE,
            DITTO,
            DICT_LITERAL,
            LEFT_PAREN,
            RIGHT_PAREN,
            LEFT_BRACKET,
            RIGHT_BRACKET,
            LEFT_BRACE,
            RIGHT_BRACE,
            SEMICOLON,
            COMMA,
            DOT,
            BACKSLASH,
            TAG,
            EOF,
            NEWLINE
        };

        enum LexError
        {
            NONE,
            FSTRING_UNTERMINATED,
            ALLOC_FAILED,
            EXPONENT_RANGE,
            NON_ASCII
        };

        // type         one of TokenType
        // line, column 1-based, same convention as flexer.py
        // voff, vlen   value location inside the lexer arena, and its length
        // numeric_char 1 for a numeric char literal such as 97c (value is the
        //              codepoint in decimal), 0 for every other token
        struct Token
        {
            int type, line, column, voff, vlen, numeric_char;
        };

        // ===== CHARACTER CLASSES (ASCII) =====

        is_digit(int c) -> bool
        {
            -> c >= '0' & c <= '9';
        };

        is_alpha(int c) -> bool
        {
            -> (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z');
        };

        is_ident_char(int c) -> bool
        {
            -> is_alpha(c) | is_digit(c) | c == '_';
        };

        is_hex_upper(int c) -> bool
        {
            -> is_digit(c) | (c >= 'A' & c <= 'F');
        };

        is_hex_any(int c) -> bool
        {
            -> is_digit(c) | (c >= 'A' & c <= 'F') | (c >= 'a' & c <= 'f');
        };

        hex_value(int c) -> int
        {
            switch (c >= '0' & c <= '9')
            {
                case (true) { -> c - 48; }
                default
                {
                    switch (c >= 'A' & c <= 'F')
                    {
                        case (true) { -> c - 55; }
                        default
                        {
                            -> c - 87;
                        };
                    };
                };
            };
        };

        is_base32_digit(int c) -> bool
        {
            -> is_digit(c) | (c >= 'A' & c <= 'V');
        };

        is_space(int c) -> bool
        {
            -> c == 32 | (c >= 9 & c <= 13) | (c >= 28 & c <= 31);
        };

        is_continuation(int c) -> bool
        {
            -> c >= 0x80 & c < 0xC0;
        };

        bytes_eq(byte* a, byte* b, int n) -> bool
        {
            int i;
            while (i < n)
            {
                switch (a[i] != b[i])
                {
                    case (true) { -> false; }
                    default
                    {
                        i++;
                    };
                };
            };
            -> true;
        };

        // Keyword table. Returns TokenType.IDENTIFIER when s[0..n) is not a keyword.
        keyword_type(byte* s, int n) -> int
        {
            switch (n == 2)
            {
                case (true) {
                switch (bytes_eq(s, g"as", 2))
                {
                    case (true) { -> TokenType.AS; }
                    default
                    {
                        switch (bytes_eq(s, g"do", 2))
                        {
                            case (true) { -> TokenType.DO; }
                            default
                            {
                                switch (bytes_eq(s, g"if", 2))
                                {
                                    case (true) { -> TokenType.IF; }
                                    default
                                    {
                                        switch (bytes_eq(s, g"in", 2))
                                        {
                                            case (true) { -> TokenType.IN; }
                                            default
                                            {
                                                switch (bytes_eq(s, g"is", 2))
                                                {
                                                    case (true) { -> TokenType.IS; }
                                                    default
                                                    {
                                                        switch (bytes_eq(s, g"or", 2))
                                                        {
                                                            case (true) { -> TokenType.OR; }
                                                            default {};
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            switch (n == 3)
            {
                case (true) {
                switch (bytes_eq(s, g"and", 3))
                {
                    case (true) { -> TokenType.AND; }
                    default
                    {
                        switch (bytes_eq(s, g"asm", 3))
                        {
                            case (true) { -> TokenType.ASM; }
                            default
                            {
                                switch (bytes_eq(s, g"def", 3))
                                {
                                    case (true) { -> TokenType.DEF; }
                                    default
                                    {
                                        switch (bytes_eq(s, g"for", 3))
                                        {
                                            case (true) { -> TokenType.FOR; }
                                            default
                                            {
                                                switch (bytes_eq(s, g"has", 3))
                                                {
                                                    case (true) { -> TokenType.HAS; }
                                                    default
                                                    {
                                                        switch (bytes_eq(s, g"int", 3))
                                                        {
                                                            case (true) { -> TokenType.SINT; }
                                                            default
                                                            {
                                                                switch (bytes_eq(s, g"not", 3))
                                                                {
                                                                    case (true) { -> TokenType.NOT; }
                                                                    default
                                                                    {
                                                                        switch (bytes_eq(s, g"try", 3))
                                                                        {
                                                                            case (true) { -> TokenType.TRY; }
                                                                            default
                                                                            {
                                                                                switch (bytes_eq(s, g"xor", 3))
                                                                                {
                                                                                    case (true) { -> TokenType.XOR; }
                                                                                    default {};
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            switch (n == 4)
            {
                case (true) {
                switch (bytes_eq(s, g"auto", 4))
                {
                    case (true) { -> TokenType.AUTO; }
                    default
                    {
                        switch (bytes_eq(s, g"bool", 4))
                        {
                            case (true) { -> TokenType.BOOL_KW; }
                            default
                            {
                                switch (bytes_eq(s, g"byte", 4))
                                {
                                    case (true) { -> TokenType.BYTE; }
                                    default
                                    {
                                        switch (bytes_eq(s, g"case", 4))
                                        {
                                            case (true) { -> TokenType.CASE; }
                                            default
                                            {
                                                switch (bytes_eq(s, g"char", 4))
                                                {
                                                    case (true) { -> TokenType.CHAR; }
                                                    default
                                                    {
                                                        switch (bytes_eq(s, g"data", 4))
                                                        {
                                                            case (true) { -> TokenType.DATA; }
                                                            default
                                                            {
                                                                switch (bytes_eq(s, g"dict", 4))
                                                                {
                                                                    case (true) { -> TokenType.DICT; }
                                                                    default
                                                                    {
                                                                        switch (bytes_eq(s, g"elif", 4))
                                                                        {
                                                                            case (true) { -> TokenType.ELIF; }
                                                                            default
                                                                            {
                                                                                switch (bytes_eq(s, g"else", 4))
                                                                                {
                                                                                    case (true) { -> TokenType.ELSE; }
                                                                                    default
                                                                                    {
                                                                                        switch (bytes_eq(s, g"enum", 4))
                                                                                        {
                                                                                            case (true) { -> TokenType.ENUM; }
                                                                                            default
                                                                                            {
                                                                                                switch (bytes_eq(s, g"from", 4))
                                                                                                {
                                                                                                    case (true) { -> TokenType.FROM; }
                                                                                                    default
                                                                                                    {
                                                                                                        switch (bytes_eq(s, g"goto", 4))
                                                                                                        {
                                                                                                            case (true) { -> TokenType.GOTO; }
                                                                                                            default
                                                                                                            {
                                                                                                                switch (bytes_eq(s, g"heap", 4))
                                                                                                                {
                                                                                                                    case (true) { -> TokenType.HEAP; }
                                                                                                                    default
                                                                                                                    {
                                                                                                                        switch (bytes_eq(s, g"jump", 4))
                                                                                                                        {
                                                                                                                            case (true) { -> TokenType.JUMP; }
                                                                                                                            default
                                                                                                                            {
                                                                                                                                switch (bytes_eq(s, g"long", 4))
                                                                                                                                {
                                                                                                                                    case (true) { -> TokenType.SLONG; }
                                                                                                                                    default
                                                                                                                                    {
                                                                                                                                        switch (bytes_eq(s, g"this", 4))
                                                                                                                                        {
                                                                                                                                            case (true) { -> TokenType.THIS; }
                                                                                                                                            default
                                                                                                                                            {
                                                                                                                                                switch (bytes_eq(s, g"true", 4))
                                                                                                                                                {
                                                                                                                                                    case (true) { -> TokenType.TRUE; }
                                                                                                                                                    default
                                                                                                                                                    {
                                                                                                                                                        switch (bytes_eq(s, g"uint", 4))
                                                                                                                                                        {
                                                                                                                                                            case (true) { -> TokenType.UINT; }
                                                                                                                                                            default
                                                                                                                                                            {
                                                                                                                                                                switch (bytes_eq(s, g"void", 4))
                                                                                                                                                                {
                                                                                                                                                                    case (true) { -> TokenType.VOID; }
                                                                                                                                                                    default {};
                                                                                                                                                                };
                                                                                                                                                            };
                                                                                                                                                        };
                                                                                                                                                    };
                                                                                                                                                };
                                                                                                                                            };
                                                                                                                                        };
                                                                                                                                    };
                                                                                                                                };
                                                                                                                            };
                                                                                                                        };
                                                                                                                    };
                                                                                                                };
                                                                                                            };
                                                                                                        };
                                                                                                    };
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            switch (n == 5)
            {
                case (true) {
                switch (bytes_eq(s, g"break", 5))
                {
                    case (true) { -> TokenType.BREAK; }
                    default
                    {
                        switch (bytes_eq(s, g"catch", 5))
                        {
                            case (true) { -> TokenType.CATCH; }
                            default
                            {
                                switch (bytes_eq(s, g"compt", 5))
                                {
                                    case (true) { -> TokenType.COMPT; }
                                    default
                                    {
                                        switch (bytes_eq(s, g"const", 5))
                                        {
                                            case (true) { -> TokenType.CONST; }
                                            default
                                            {
                                                switch (bytes_eq(s, g"defer", 5))
                                                {
                                                    case (true) { -> TokenType.DEFER; }
                                                    default
                                                    {
                                                        switch (bytes_eq(s, g"macro", 5))
                                                        {
                                                            case (true) { -> TokenType.MACRO; }
                                                            default
                                                            {
                                                                switch (bytes_eq(s, g"false", 5))
                                                                {
                                                                    case (true) { -> TokenType.FALSE; }
                                                                    default
                                                                    {
                                                                        switch (bytes_eq(s, g"float", 5))
                                                                        {
                                                                            case (true) { -> TokenType.FLOAT_KW; }
                                                                            default
                                                                            {
                                                                                switch (bytes_eq(s, g"label", 5))
                                                                                {
                                                                                    case (true) { -> TokenType.LABEL; }
                                                                                    default
                                                                                    {
                                                                                        switch (bytes_eq(s, g"local", 5))
                                                                                        {
                                                                                            case (true) { -> TokenType.LOCAL; }
                                                                                            default
                                                                                            {
                                                                                                switch (bytes_eq(s, g"ulong", 5))
                                                                                                {
                                                                                                    case (true) { -> TokenType.ULONG; }
                                                                                                    default
                                                                                                    {
                                                                                                        switch (bytes_eq(s, g"stack", 5))
                                                                                                        {
                                                                                                            case (true) { -> TokenType.STACK; }
                                                                                                            default
                                                                                                            {
                                                                                                                switch (bytes_eq(s, g"throw", 5))
                                                                                                                {
                                                                                                                    case (true) { -> TokenType.THROW; }
                                                                                                                    default
                                                                                                                    {
                                                                                                                        switch (bytes_eq(s, g"trait", 5))
                                                                                                                        {
                                                                                                                            case (true) { -> TokenType.TRAIT; }
                                                                                                                            default
                                                                                                                            {
                                                                                                                                switch (bytes_eq(s, g"union", 5))
                                                                                                                                {
                                                                                                                                    case (true) { -> TokenType.UNION; }
                                                                                                                                    default
                                                                                                                                    {
                                                                                                                                        switch (bytes_eq(s, g"using", 5))
                                                                                                                                        {
                                                                                                                                            case (true) { -> TokenType.USING; }
                                                                                                                                            default
                                                                                                                                            {
                                                                                                                                                switch (bytes_eq(s, g"while", 5))
                                                                                                                                                {
                                                                                                                                                    case (true) { -> TokenType.WHILE; }
                                                                                                                                                    default
                                                                                                                                                    {
                                                                                                                                                        switch (bytes_eq(s, g"cdecl", 5))
                                                                                                                                                        {
                                                                                                                                                            case (true) { -> TokenType.CDECL; }
                                                                                                                                                            default
                                                                                                                                                            {
                                                                                                                                                                switch (bytes_eq(s, g"async", 5))
                                                                                                                                                                {
                                                                                                                                                                    case (true) { -> TokenType.ASYNC; }
                                                                                                                                                                    default {};
                                                                                                                                                                };
                                                                                                                                                            };
                                                                                                                                                        };
                                                                                                                                                    };
                                                                                                                                                };
                                                                                                                                            };
                                                                                                                                        };
                                                                                                                                    };
                                                                                                                                };
                                                                                                                            };
                                                                                                                        };
                                                                                                                    };
                                                                                                                };
                                                                                                            };
                                                                                                        };
                                                                                                    };
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            switch (n == 6)
            {
                case (true) {
                switch (bytes_eq(s, g"assert", 6))
                {
                    case (true) { -> TokenType.ASSERT; }
                    default
                    {
                        switch (bytes_eq(s, g"double", 6))
                        {
                            case (true) { -> TokenType.DOUBLE_KW; }
                            default
                            {
                                switch (bytes_eq(s, g"effect", 6))
                                {
                                    case (true) { -> TokenType.EFFECT; }
                                    default
                                    {
                                        switch (bytes_eq(s, g"escape", 6))
                                        {
                                            case (true) { -> TokenType.ESCAPE_KW; }
                                            default
                                            {
                                                switch (bytes_eq(s, g"export", 6))
                                                {
                                                    case (true) { -> TokenType.EXPORT; }
                                                    default
                                                    {
                                                        switch (bytes_eq(s, g"extern", 6))
                                                        {
                                                            case (true) { -> TokenType.EXTERN; }
                                                            default
                                                            {
                                                                switch (bytes_eq(s, g"global", 6))
                                                                {
                                                                    case (true) { -> TokenType.GLOBAL; }
                                                                    default
                                                                    {
                                                                        switch (bytes_eq(s, g"inline", 6))
                                                                        {
                                                                            case (true) { -> TokenType.INLINE; }
                                                                            default
                                                                            {
                                                                                switch (bytes_eq(s, g"noinit", 6))
                                                                                {
                                                                                    case (true) { -> TokenType.NO_INIT; }
                                                                                    default
                                                                                    {
                                                                                        switch (bytes_eq(s, g"object", 6))
                                                                                        {
                                                                                            case (true) { -> TokenType.OBJECT; }
                                                                                            default
                                                                                            {
                                                                                                switch (bytes_eq(s, g"public", 6))
                                                                                                {
                                                                                                    case (true) { -> TokenType.PUBLIC; }
                                                                                                    default
                                                                                                    {
                                                                                                        switch (bytes_eq(s, g"return", 6))
                                                                                                        {
                                                                                                            case (true) { -> TokenType.RETURN; }
                                                                                                            default
                                                                                                            {
                                                                                                                switch (bytes_eq(s, g"signed", 6))
                                                                                                                {
                                                                                                                    case (true) { -> TokenType.SIGNED; }
                                                                                                                    default
                                                                                                                    {
                                                                                                                        switch (bytes_eq(s, g"sizeof", 6))
                                                                                                                        {
                                                                                                                            case (true) { -> TokenType.SIZEOF; }
                                                                                                                            default
                                                                                                                            {
                                                                                                                                switch (bytes_eq(s, g"struct", 6))
                                                                                                                                {
                                                                                                                                    case (true) { -> TokenType.STRUCT; }
                                                                                                                                    default
                                                                                                                                    {
                                                                                                                                        switch (bytes_eq(s, g"switch", 6))
                                                                                                                                        {
                                                                                                                                            case (true) { -> TokenType.SWITCH; }
                                                                                                                                            default
                                                                                                                                            {
                                                                                                                                                switch (bytes_eq(s, g"typeof", 6))
                                                                                                                                                {
                                                                                                                                                    case (true) { -> TokenType.TYPEOF; }
                                                                                                                                                    default
                                                                                                                                                    {
                                                                                                                                                        switch (bytes_eq(s, g"vector", 6))
                                                                                                                                                        {
                                                                                                                                                            case (true) { -> TokenType.VECTOR; }
                                                                                                                                                            default
                                                                                                                                                            {
                                                                                                                                                                switch (bytes_eq(s, g"fluxvm", 6))
                                                                                                                                                                {
                                                                                                                                                                    case (true) { -> TokenType.FLUXVM; }
                                                                                                                                                                    default {};
                                                                                                                                                                };
                                                                                                                                                            };
                                                                                                                                                        };
                                                                                                                                                    };
                                                                                                                                                };
                                                                                                                                            };
                                                                                                                                        };
                                                                                                                                    };
                                                                                                                                };
                                                                                                                            };
                                                                                                                        };
                                                                                                                    };
                                                                                                                };
                                                                                                            };
                                                                                                        };
                                                                                                    };
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            switch (n == 7)
            {
                case (true) {
                switch (bytes_eq(s, g"alignof", 7))
                {
                    case (true) { -> TokenType.ALIGNOF; }
                    default
                    {
                        switch (bytes_eq(s, g"default", 7))
                        {
                            case (true) { -> TokenType.DEFAULT; }
                            default
                            {
                                switch (bytes_eq(s, g"private", 7))
                                {
                                    case (true) { -> TokenType.PRIVATE; }
                                    default
                                    {
                                        switch (bytes_eq(s, g"stdcall", 7))
                                        {
                                            case (true) { -> TokenType.STDCALL; }
                                            default {};
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            switch (n == 8)
            {
                case (true) {
                switch (bytes_eq(s, g"continue", 8))
                {
                    case (true) { -> TokenType.CONTINUE; }
                    default
                    {
                        switch (bytes_eq(s, g"contract", 8))
                        {
                            case (true) { -> TokenType.CONTRACT; }
                            default
                            {
                                switch (bytes_eq(s, g"endianof", 8))
                                {
                                    case (true) { -> TokenType.ENDIANOF; }
                                    default
                                    {
                                        switch (bytes_eq(s, g"fastnode", 8))
                                        {
                                            case (true) { -> TokenType.FASTNODE; }
                                            default
                                            {
                                                switch (bytes_eq(s, g"noreturn", 8))
                                                {
                                                    case (true) { -> TokenType.NORET; }
                                                    default
                                                    {
                                                        switch (bytes_eq(s, g"operator", 8))
                                                        {
                                                            case (true) { -> TokenType.OPERATOR; }
                                                            default
                                                            {
                                                                switch (bytes_eq(s, g"register", 8))
                                                                {
                                                                    case (true) { -> TokenType.REGISTER; }
                                                                    default
                                                                    {
                                                                        switch (bytes_eq(s, g"singinit", 8))
                                                                        {
                                                                            case (true) { -> TokenType.SINGINIT; }
                                                                            default
                                                                            {
                                                                                switch (bytes_eq(s, g"unsigned", 8))
                                                                                {
                                                                                    case (true) { -> TokenType.UNSIGNED; }
                                                                                    default
                                                                                    {
                                                                                        switch (bytes_eq(s, g"volatile", 8))
                                                                                        {
                                                                                            case (true) { -> TokenType.VOLATILE; }
                                                                                            default
                                                                                            {
                                                                                                switch (bytes_eq(s, g"fastcall", 8))
                                                                                                {
                                                                                                    case (true) { -> TokenType.FASTCALL; }
                                                                                                    default
                                                                                                    {
                                                                                                        switch (bytes_eq(s, g"thiscall", 8))
                                                                                                        {
                                                                                                            case (true) { -> TokenType.THISCALL; }
                                                                                                            default
                                                                                                            {
                                                                                                                switch (bytes_eq(s, g"comptime", 8))
                                                                                                                {
                                                                                                                    case (true) { -> TokenType.COMPTIME; }
                                                                                                                    default
                                                                                                                    {
                                                                                                                        switch (bytes_eq(s, g"emitflux", 8))
                                                                                                                        {
                                                                                                                            case (true) { -> TokenType.EMITFLUX; }
                                                                                                                            default {};
                                                                                                                        };
                                                                                                                    };
                                                                                                                };
                                                                                                            };
                                                                                                        };
                                                                                                    };
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            switch (n == 9)
            {
                case (true) {
                switch (bytes_eq(s, g"deprecate", 9))
                {
                    case (true) { -> TokenType.DEPRECATE; }
                    default
                    {
                        switch (bytes_eq(s, g"interface", 9))
                        {
                            case (true) { -> TokenType.INTERFACE; }
                            default
                            {
                                switch (bytes_eq(s, g"namespace", 9))
                                {
                                    case (true) { -> TokenType.NAMESPACE; }
                                    default {};
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            switch (n == 10)
            {
                case (true) {
                switch (bytes_eq(s, g"constraint", 10))
                {
                    case (true) { -> TokenType.CONSTRAINT; }
                    default
                    {
                        switch (bytes_eq(s, g"vectorcall", 10))
                        {
                            case (true) { -> TokenType.VECTORCALL; }
                            default {};
                        };
                    };
                };
            }
                default {};
            };
            -> TokenType.IDENTIFIER;
        };

        error_message(int code) -> byte*
        {
            switch (code)
            {
                case (LexError.FSTRING_UNTERMINATED) { -> g"unterminated f-string interpolation, } expected\0"; }
                case (LexError.ALLOC_FAILED)         { -> g"lexer allocation failed\0"; }
                case (LexError.EXPONENT_RANGE)       { -> g"numeric literal exponent out of range\0"; }
                case (LexError.NON_ASCII)            { -> g"non-ASCII character is only valid inside string literals\0"; }
                default                              { -> g"no error\0"; };
            };
        };

        token_name(int t) -> byte*
        {
            switch (t)
            {
                case (TokenType.SINT_LITERAL) { -> g"SINT_LITERAL\0"; }
                case (TokenType.UINT_LITERAL) { -> g"UINT_LITERAL\0"; }
                case (TokenType.SLONG_LITERAL) { -> g"SLONG_LITERAL\0"; }
                case (TokenType.ULONG_LITERAL) { -> g"ULONG_LITERAL\0"; }
                case (TokenType.FLOAT) { -> g"FLOAT\0"; }
                case (TokenType.DOUBLE) { -> g"DOUBLE\0"; }
                case (TokenType.BYTE_LITERAL) { -> g"BYTE_LITERAL\0"; }
                case (TokenType.CHAR) { -> g"CHAR\0"; }
                case (TokenType.STRING_LITERAL) { -> g"STRING_LITERAL\0"; }
                case (TokenType.BOOL) { -> g"BOOL\0"; }
                case (TokenType.I_STRING) { -> g"I_STRING\0"; }
                case (TokenType.F_STRING) { -> g"F_STRING\0"; }
                case (TokenType.G_STRING) { -> g"G_STRING\0"; }
                case (TokenType.IDENTIFIER) { -> g"IDENTIFIER\0"; }
                case (TokenType.ALIGNOF) { -> g"ALIGNOF\0"; }
                case (TokenType.ASSERT) { -> g"ASSERT\0"; }
                case (TokenType.ENDIANOF) { -> g"ENDIANOF\0"; }
                case (TokenType.SIZEOF) { -> g"SIZEOF\0"; }
                case (TokenType.TYPEOF) { -> g"TYPEOF\0"; }
                case (TokenType.AND) { -> g"AND\0"; }
                case (TokenType.AS) { -> g"AS\0"; }
                case (TokenType.ASM) { -> g"ASM\0"; }
                case (TokenType.ASM_BLOCK) { -> g"ASM_BLOCK\0"; }
                case (TokenType.ASYNC) { -> g"ASYNC\0"; }
                case (TokenType.AUTO) { -> g"AUTO\0"; }
                case (TokenType.BREAK) { -> g"BREAK\0"; }
                case (TokenType.BOOL_KW) { -> g"BOOL_KW\0"; }
                case (TokenType.BYTE) { -> g"BYTE\0"; }
                case (TokenType.CASE) { -> g"CASE\0"; }
                case (TokenType.CATCH) { -> g"CATCH\0"; }
                case (TokenType.COMPT) { -> g"COMPT\0"; }
                case (TokenType.CONST) { -> g"CONST\0"; }
                case (TokenType.CONSTRAINT) { -> g"CONSTRAINT\0"; }
                case (TokenType.CONTINUE) { -> g"CONTINUE\0"; }
                case (TokenType.CONTRACT) { -> g"CONTRACT\0"; }
                case (TokenType.DATA) { -> g"DATA\0"; }
                case (TokenType.DEF) { -> g"DEF\0"; }
                case (TokenType.DEFER) { -> g"DEFER\0"; }
                case (TokenType.DEFAULT) { -> g"DEFAULT\0"; }
                case (TokenType.DEPRECATE) { -> g"DEPRECATE\0"; }
                case (TokenType.DICT) { -> g"DICT\0"; }
                case (TokenType.DO) { -> g"DO\0"; }
                case (TokenType.DOUBLE_KW) { -> g"DOUBLE_KW\0"; }
                case (TokenType.ELIF) { -> g"ELIF\0"; }
                case (TokenType.ELSE) { -> g"ELSE\0"; }
                case (TokenType.ENUM) { -> g"ENUM\0"; }
                case (TokenType.EFFECT) { -> g"EFFECT\0"; }
                case (TokenType.ESCAPE_KW) { -> g"ESCAPE_KW\0"; }
                case (TokenType.EXPORT) { -> g"EXPORT\0"; }
                case (TokenType.EXTERN) { -> g"EXTERN\0"; }
                case (TokenType.FALSE) { -> g"FALSE\0"; }
                case (TokenType.FASTNODE) { -> g"FASTNODE\0"; }
                case (TokenType.FLOAT_KW) { -> g"FLOAT_KW\0"; }
                case (TokenType.FOR) { -> g"FOR\0"; }
                case (TokenType.FROM) { -> g"FROM\0"; }
                case (TokenType.GLOBAL) { -> g"GLOBAL\0"; }
                case (TokenType.GOTO) { -> g"GOTO\0"; }
                case (TokenType.HAS) { -> g"HAS\0"; }
                case (TokenType.HEAP) { -> g"HEAP\0"; }
                case (TokenType.IF) { -> g"IF\0"; }
                case (TokenType.IN) { -> g"IN\0"; }
                case (TokenType.INLINE) { -> g"INLINE\0"; }
                case (TokenType.SINT) { -> g"SINT\0"; }
                case (TokenType.INTERFACE) { -> g"INTERFACE\0"; }
                case (TokenType.IS) { -> g"IS\0"; }
                case (TokenType.JUMP) { -> g"JUMP\0"; }
                case (TokenType.LABEL) { -> g"LABEL\0"; }
                case (TokenType.LOCAL) { -> g"LOCAL\0"; }
                case (TokenType.SLONG) { -> g"SLONG\0"; }
                case (TokenType.ULONG) { -> g"ULONG\0"; }
                case (TokenType.UINT) { -> g"UINT\0"; }
                case (TokenType.MACRO) { -> g"MACRO\0"; }
                case (TokenType.NAMESPACE) { -> g"NAMESPACE\0"; }
                case (TokenType.NOT) { -> g"NOT\0"; }
                case (TokenType.NO_INIT) { -> g"NO_INIT\0"; }
                case (TokenType.NORET) { -> g"NORET\0"; }
                case (TokenType.OBJECT) { -> g"OBJECT\0"; }
                case (TokenType.OPERATOR) { -> g"OPERATOR\0"; }
                case (TokenType.OR) { -> g"OR\0"; }
                case (TokenType.PRIVATE) { -> g"PRIVATE\0"; }
                case (TokenType.PUBLIC) { -> g"PUBLIC\0"; }
                case (TokenType.REGISTER) { -> g"REGISTER\0"; }
                case (TokenType.RETURN) { -> g"RETURN\0"; }
                case (TokenType.SIGNED) { -> g"SIGNED\0"; }
                case (TokenType.SINGINIT) { -> g"SINGINIT\0"; }
                case (TokenType.STACK) { -> g"STACK\0"; }
                case (TokenType.STRUCT) { -> g"STRUCT\0"; }
                case (TokenType.SWITCH) { -> g"SWITCH\0"; }
                case (TokenType.THIS) { -> g"THIS\0"; }
                case (TokenType.THROW) { -> g"THROW\0"; }
                case (TokenType.TRAIT) { -> g"TRAIT\0"; }
                case (TokenType.TRUE) { -> g"TRUE\0"; }
                case (TokenType.TRY) { -> g"TRY\0"; }
                case (TokenType.UNION) { -> g"UNION\0"; }
                case (TokenType.UNSIGNED) { -> g"UNSIGNED\0"; }
                case (TokenType.USING) { -> g"USING\0"; }
                case (TokenType.VECTOR) { -> g"VECTOR\0"; }
                case (TokenType.VOID) { -> g"VOID\0"; }
                case (TokenType.VOLATILE) { -> g"VOLATILE\0"; }
                case (TokenType.WHILE) { -> g"WHILE\0"; }
                case (TokenType.XOR) { -> g"XOR\0"; }
                case (TokenType.CDECL) { -> g"CDECL\0"; }
                case (TokenType.STDCALL) { -> g"STDCALL\0"; }
                case (TokenType.FASTCALL) { -> g"FASTCALL\0"; }
                case (TokenType.THISCALL) { -> g"THISCALL\0"; }
                case (TokenType.VECTORCALL) { -> g"VECTORCALL\0"; }
                case (TokenType.COMPTIME) { -> g"COMPTIME\0"; }
                case (TokenType.EMITFLUX) { -> g"EMITFLUX\0"; }
                case (TokenType.FLUXVM) { -> g"FLUXVM\0"; }
                case (TokenType.FLUXVM_BLOCK) { -> g"FLUXVM_BLOCK\0"; }
                case (TokenType.PLUS) { -> g"PLUS\0"; }
                case (TokenType.MINUS) { -> g"MINUS\0"; }
                case (TokenType.INCREMENT) { -> g"INCREMENT\0"; }
                case (TokenType.DECREMENT) { -> g"DECREMENT\0"; }
                case (TokenType.MULTIPLY) { -> g"MULTIPLY\0"; }
                case (TokenType.DIVIDE) { -> g"DIVIDE\0"; }
                case (TokenType.MODULO) { -> g"MODULO\0"; }
                case (TokenType.EXPONENT) { -> g"EXPONENT\0"; }
                case (TokenType.LOGICAL_AND) { -> g"LOGICAL_AND\0"; }
                case (TokenType.LOGICAL_OR) { -> g"LOGICAL_OR\0"; }
                case (TokenType.NAND_OP) { -> g"NAND_OP\0"; }
                case (TokenType.NOR_OP) { -> g"NOR_OP\0"; }
                case (TokenType.XOR_OP) { -> g"XOR_OP\0"; }
                case (TokenType.EQUAL) { -> g"EQUAL\0"; }
                case (TokenType.NOT_EQUAL) { -> g"NOT_EQUAL\0"; }
                case (TokenType.LESS_THAN) { -> g"LESS_THAN\0"; }
                case (TokenType.LESS_EQUAL) { -> g"LESS_EQUAL\0"; }
                case (TokenType.GREATER_THAN) { -> g"GREATER_THAN\0"; }
                case (TokenType.GREATER_EQUAL) { -> g"GREATER_EQUAL\0"; }
                case (TokenType.ASSIGN) { -> g"ASSIGN\0"; }
                case (TokenType.PLUS_ASSIGN) { -> g"PLUS_ASSIGN\0"; }
                case (TokenType.MINUS_ASSIGN) { -> g"MINUS_ASSIGN\0"; }
                case (TokenType.MULTIPLY_ASSIGN) { -> g"MULTIPLY_ASSIGN\0"; }
                case (TokenType.DIVIDE_ASSIGN) { -> g"DIVIDE_ASSIGN\0"; }
                case (TokenType.MODULO_ASSIGN) { -> g"MODULO_ASSIGN\0"; }
                case (TokenType.EXPONENT_ASSIGN) { -> g"EXPONENT_ASSIGN\0"; }
                case (TokenType.BACKTICK) { -> g"BACKTICK\0"; }
                case (TokenType.BITNOT_OP) { -> g"BITNOT_OP\0"; }
                case (TokenType.BITAND_OP) { -> g"BITAND_OP\0"; }
                case (TokenType.BITOR_OP) { -> g"BITOR_OP\0"; }
                case (TokenType.BITNAND_OP) { -> g"BITNAND_OP\0"; }
                case (TokenType.BITNOR_OP) { -> g"BITNOR_OP\0"; }
                case (TokenType.BITXOR_OP) { -> g"BITXOR_OP\0"; }
                case (TokenType.BITXNOT) { -> g"BITXNOT\0"; }
                case (TokenType.BITXNAND) { -> g"BITXNAND\0"; }
                case (TokenType.BITXNOR) { -> g"BITXNOR\0"; }
                case (TokenType.AND_ASSIGN) { -> g"AND_ASSIGN\0"; }
                case (TokenType.OR_ASSIGN) { -> g"OR_ASSIGN\0"; }
                case (TokenType.XOR_ASSIGN) { -> g"XOR_ASSIGN\0"; }
                case (TokenType.BITAND_ASSIGN) { -> g"BITAND_ASSIGN\0"; }
                case (TokenType.BITOR_ASSIGN) { -> g"BITOR_ASSIGN\0"; }
                case (TokenType.BITNAND_ASSIGN) { -> g"BITNAND_ASSIGN\0"; }
                case (TokenType.BITNOR_ASSIGN) { -> g"BITNOR_ASSIGN\0"; }
                case (TokenType.BITXOR_ASSIGN) { -> g"BITXOR_ASSIGN\0"; }
                case (TokenType.BITXNOT_ASSIGN) { -> g"BITXNOT_ASSIGN\0"; }
                case (TokenType.BITXNAND_ASSIGN) { -> g"BITXNAND_ASSIGN\0"; }
                case (TokenType.BITXNOR_ASSIGN) { -> g"BITXNOR_ASSIGN\0"; }
                case (TokenType.BITSHIFT_LEFT) { -> g"BITSHIFT_LEFT\0"; }
                case (TokenType.BITSHIFT_RIGHT) { -> g"BITSHIFT_RIGHT\0"; }
                case (TokenType.BITSHIFT_LEFT_ASSIGN) { -> g"BITSHIFT_LEFT_ASSIGN\0"; }
                case (TokenType.BITSHIFT_RIGHT_ASSIGN) { -> g"BITSHIFT_RIGHT_ASSIGN\0"; }
                case (TokenType.ADDRESS_OF) { -> g"ADDRESS_OF\0"; }
                case (TokenType.RANGE) { -> g"RANGE\0"; }
                case (TokenType.ELLIPSIS) { -> g"ELLIPSIS\0"; }
                case (TokenType.SCOPE) { -> g"SCOPE\0"; }
                case (TokenType.QUESTION) { -> g"QUESTION\0"; }
                case (TokenType.TERNARY_ASSIGN) { -> g"TERNARY_ASSIGN\0"; }
                case (TokenType.ADDRESS_ASSIGN) { -> g"ADDRESS_ASSIGN\0"; }
                case (TokenType.NULL_COALESCE) { -> g"NULL_COALESCE\0"; }
                case (TokenType.NOT_NULL) { -> g"NOT_NULL\0"; }
                case (TokenType.COLON) { -> g"COLON\0"; }
                case (TokenType.TIE) { -> g"TIE\0"; }
                case (TokenType.RETURN_ARROW) { -> g"RETURN_ARROW\0"; }
                case (TokenType.CHAIN_ARROW) { -> g"CHAIN_ARROW\0"; }
                case (TokenType.RECURSE_ARROW) { -> g"RECURSE_ARROW\0"; }
                case (TokenType.NO_MANGLE) { -> g"NO_MANGLE\0"; }
                case (TokenType.FUNCTION_POINTER) { -> g"FUNCTION_POINTER\0"; }
                case (TokenType.ADDRESS_CAST) { -> g"ADDRESS_CAST\0"; }
                case (TokenType.STRINGIFY) { -> g"STRINGIFY\0"; }
                case (TokenType.CODIFY) { -> g"CODIFY\0"; }
                case (TokenType.BITSLICE) { -> g"BITSLICE\0"; }
                case (TokenType.DITTO) { -> g"DITTO\0"; }
                case (TokenType.DICT_LITERAL) { -> g"DICT_LITERAL\0"; }
                case (TokenType.LEFT_PAREN) { -> g"LEFT_PAREN\0"; }
                case (TokenType.RIGHT_PAREN) { -> g"RIGHT_PAREN\0"; }
                case (TokenType.LEFT_BRACKET) { -> g"LEFT_BRACKET\0"; }
                case (TokenType.RIGHT_BRACKET) { -> g"RIGHT_BRACKET\0"; }
                case (TokenType.LEFT_BRACE) { -> g"LEFT_BRACE\0"; }
                case (TokenType.RIGHT_BRACE) { -> g"RIGHT_BRACE\0"; }
                case (TokenType.SEMICOLON) { -> g"SEMICOLON\0"; }
                case (TokenType.COMMA) { -> g"COMMA\0"; }
                case (TokenType.DOT) { -> g"DOT\0"; }
                case (TokenType.BACKSLASH) { -> g"BACKSLASH\0"; }
                case (TokenType.TAG) { -> g"TAG\0"; }
                case (TokenType.EOF) { -> g"EOF\0"; }
                case (TokenType.NEWLINE) { -> g"NEWLINE\0"; }
                default { -> g"UNKNOWN\0"; };
            };
        };

        object Lexer
        {
            byte* src;
            int length, position, line, column;

            Token* tokens;
            int count, cap;

            byte* arena;
            int arena_len, arena_cap;

            int err_code, err_line, err_col;

            // Non-ASCII characters outside string literals are skipped with a
            // warning in flexer.py. The first occurrence is recorded here.
            int warn_count, warn_line, warn_col, warn_cp;
            int err_cp, err_start, err_nbytes;   // the offending character of LexError.NON_ASCII

            __init(byte* source, int len) -> this
            {
                this.src = source;
                this.length = len;
                this.position = 0;
                this.line = 1;
                this.column = 1;
                this.count = 0;
                this.err_code = 0;

                // Skip a UTF-8 BOM if present
                switch (len >= 3)
                {
                    case (true) {
                    switch (source[0] == 0xEF & source[1] == 0xBB & source[2] == 0xBF)
                    {
                        case (true) {
                        this.position = 3;
                    }
                        default {};
                    };
                }
                    default {};
                };

                // Every token consumes at least one source byte, plus EOF.
                this.cap = len + 2;
                this.tokens = (Token*)fmalloc((u64)this.cap * (u64)(sizeof(Token) / 8));

                this.arena_cap = len * 2 + 64;
                this.arena_len = 0;
                this.arena = (byte*)fmalloc((u64)this.arena_cap);

                switch (this.tokens == (Token*)0 | this.arena == (byte*)0)
                {
                    case (true) {
                    this.err_code = LexError.ALLOC_FAILED;
                    this.err_line = 1;
                    this.err_col = 1;
                }
                    default {};
                };
                -> this;
            };

            __expr() -> Lexer*
            {
                -> this;
            };

            __exit() -> void
            {
                switch (this.tokens != (Token*)0)
                {
                    case (true) { ffree((byte*)this.tokens); }
                    default {};
                };
                switch (this.arena != (byte*)0)
                {
                    case (true) { ffree(this.arena); }
                    default {};
                };
                this.tokens = (Token*)0;
                this.arena = (byte*)0;
                ->;
            };

            // ===== SOURCE CURSOR =====

            // Current byte as 0..255, or -1 at end of input
            cur() -> int
            {
                switch (this.position >= this.length)
                {
                    case (true) { -> -1; }
                    default
                    {
                        -> (int)this.src[this.position];
                    };
                };
            };

            peek(int offset) -> int
            {
                int p = this.position + offset;
                switch (p >= this.length)
                {
                    case (true) { -> -1; }
                    default
                    {
                        -> (int)this.src[p];
                    };
                };
            };

            // Mirrors FluxLexer.advance. Newline resets the column, a single
            // tab advances to 4 columns, UTF-8 continuation bytes do not add a
            // column so columns count characters like the Python lexer does.
            adv(int n) -> void
            {
                int c;
                switch (this.position < this.length)
                {
                    case (true) {
                    c = (int)this.src[this.position];
                    switch (c == 10)
                    {
                        case (true) {
                        this.line++;
                        this.column = 1;
                    }
                        default {
                            switch (n == 1 & c == 9)
                            {
                                case (true) {
                        this.column += 4;
                    }
                                default {
                                    switch (n == 1 & is_continuation(c))
                                    {
                                        case (true) {
                        this.column += 0;
                    }
                                        default {
                        this.column += n;
                    };
                                    };
                                };
                            };
                        };
                    };
                }
                    default {
                    this.column += n;
                };
                };
                this.position += n;
                ->;
            };

            skip_whitespace() -> bool
            {
                bool skipped = false;
                while (this.cur() != -1 & is_space(this.cur()))
                {
                    this.adv(1);
                    skipped = true;
                };
                -> skipped;
            };

            // Does the source at the current position start with lit[0..n)?
            match(byte* lit, int n) -> bool
            {
                int i;
                while (i < n)
                {
                    switch (this.position + i >= this.length)
                    {
                        case (true) { -> false; }
                        default
                        {
                            switch (this.src[this.position + i] != lit[i])
                            {
                                case (true) { -> false; }
                                default
                                {
                                    i++;
                                };
                            };
                        };
                    };
                };
                -> true;
            };

            // ===== ERRORS =====

            fail(int code, int ln, int col) -> void
            {
                switch (this.err_code == 0)
                {
                    case (true) {
                    this.err_code = code;
                    this.err_line = ln;
                    this.err_col = col;
                }
                    default {};
                };
                ->;
            };

            // ===== VALUE ARENA =====

            grow() -> void
            {
                int new_cap = this.arena_cap * 2;
                u64 np = frealloc((u64)this.arena, (size_t)new_cap);
                switch (np == (u64)0)
                {
                    case (true) {
                    -> this.fail(LexError.ALLOC_FAILED, this.line, this.column);
                }
                    default
                    {
                        this.arena = (byte*)np;
                        this.arena_cap = new_cap;
                        ->;
                    };
                };
            };

            vbegin() -> int
            {
                -> this.arena_len;
            };

            vput(int b) -> void
            {
                switch (this.arena_len + 2 > this.arena_cap)
                {
                    case (true) { this.grow(); }
                    default {};
                };
                switch (this.err_code != 0)
                {
                    case (true) { ->; }
                    default
                    {
                        this.arena[this.arena_len] = (byte)b;
                        this.arena_len++;
                        ->;
                    };
                };
            };

            // UTF-8 encode a codepoint below 0x800
            vput_cp(int v) -> void
            {
                switch (v < 128)
                {
                    case (true) {
                    this.vput(v);
                }
                    default {
                    this.vput(0xC0 | (v >> 6));
                    this.vput(0x80 | (v & 0x3F));
                };
                };
                ->;
            };

            // Null terminate the value that started at `start`. Returns its length.
            vend(int start) -> int
            {
                this.vput(0);
                -> this.arena_len - 1 - start;
            };

            emit(int tt, int ln, int col, int voff, int vlen, int numeric) -> void
            {
                switch (this.err_code != 0)
                {
                    case (true) { ->; }
                    default
                    {
                        switch (this.count >= this.cap)
                        {
                            case (true) {
                            -> this.fail(LexError.ALLOC_FAILED, ln, col);
                        }
                            default
                            {
                                this.tokens[this.count].type = tt;
                                this.tokens[this.count].line = ln;
                                this.tokens[this.count].column = col;
                                this.tokens[this.count].voff = voff;
                                this.tokens[this.count].vlen = vlen;
                                this.tokens[this.count].numeric_char = numeric;
                                this.count++;
                                ->;
                            };
                        };
                    };
                };
            };

            emit_text(int tt, int ln, int col, byte* s, int n) -> void
            {
                int vb = this.vbegin();
                int i;
                while (i < n)
                {
                    this.vput((int)s[i]);
                    i++;
                };
                int vl = this.vend(vb);
                -> this.emit(tt, ln, col, vb, vl, 0);
            };

            token_value(int i) -> byte*
            {
                -> this.arena + this.tokens[i].voff;
            };

            // ===== BLOCKS =====

            // asm"..." form: current character is the opening quote
            read_asm_quoted() -> void
            {
                int ln = this.line;
                int col = this.column;
                int vb = this.vbegin();
                this.adv(1);
                while (this.cur() != -1 & !(this.cur() == '"' & this.peek(1) == '"'))
                {
                    this.vput(this.cur());
                    this.adv(1);
                };
                switch (this.cur() == '"' & this.peek(1) == '"')
                {
                    case (true) { this.adv(2); }
                    default {};
                };
                int vl = this.vend(vb);
                -> this.emit(TokenType.ASM_BLOCK, ln, col, vb, vl, 0);
            };

            // { ... } block after the asm or fluxvm keyword. Content is raw
            // text with nested braces balanced, outer whitespace stripped.
            read_brace_block(int tt) -> void
            {
                int ln = this.line;
                int col = this.column;
                int c;
                while (this.cur() == 32 | this.cur() == 9 | this.cur() == 13 | this.cur() == 10)
                {
                    this.adv(1);
                };
                switch (this.cur() != '{')
                {
                    case (true) { ->; }
                    default
                    {
                        this.adv(1);

                        int depth = 1;
                        int vb = this.vbegin();
                        while (this.cur() != -1 & depth > 0)
                        {
                            c = this.cur();
                            switch (c)
                            {
                                case ('{') { depth++; }
                                case ('}') { depth--; }
                                default {};
                            };
                            switch (depth > 0)
                            {
                                case (true) { this.vput(c); }
                                default {};
                            };
                            this.adv(1);
                        };

                        int s = vb;
                        int e = this.arena_len;
                        while (s < e & is_space((int)this.arena[s])) { s++; };
                        while (e > s & is_space((int)this.arena[e - 1])) { e--; };
                        int k;
                        int n = e - s;
                        while (k < n)
                        {
                            this.arena[vb + k] = this.arena[s + k];
                            k++;
                        };
                        this.arena_len = vb + n;
                        int vl = this.vend(vb);
                        -> this.emit(tt, ln, col, vb, vl, 0);
                    };
                };
            };

            // ===== STRINGS =====

            // Reads a quoted string with escape processing into the arena.
            // The current character is the opening quote.
            read_string(int quote) -> void
            {
                int e, hv, hn;
                bool stop = false;
                bool skip;
                this.adv(1);
                while (!stop & this.cur() != -1 & this.cur() != quote)
                {
                    skip = false;
                    switch (this.cur() == '\\')
                    {
                        case (true) {
                        this.adv(1);
                        e = this.cur();
                        switch (e)
                        {
                            case (-1)
                            {
                                stop = true;
                            }
                            case ('n') { this.vput(10); }
                            case ('t') { this.vput(9); }
                            case ('r') { this.vput(13); }
                            case ('0') { this.vput(0); }
                            case ('\\') { this.vput(92); }
                            case ('"') { this.vput(34); }
                            case ('x')
                            {
                                this.adv(1);
                                hv = 0;
                                hn = 0;
                                while (hn < 2 & is_hex_any(this.cur()))
                                {
                                    hv = hv * 16 + hex_value(this.cur());
                                    this.adv(1);
                                    hn++;
                                };
                                switch (hn > 0)
                                {
                                    case (true) {
                                    this.vput_cp(hv);
                                    skip = true;
                                }
                                    default {};
                                };
                            }
                            default
                            {
                                this.vput(e);
                            };
                        };
                    }
                        default {
                        this.vput(this.cur());
                    };
                    };
                    switch (!stop & !skip)
                    {
                        case (true) { this.adv(1); }
                        default {};
                    };
                };
                switch (this.cur() == quote)
                {
                    case (true) { this.adv(1); }
                    default {};
                };
                ->;
            };

            // f-string body. Embedded { ... } expressions are copied verbatim.
            // Returns false (and sets the error) on an unterminated interpolation.
            read_f_string_body() -> bool
            {
                int e, depth;
                bool stop = false;
                this.adv(1);
                while (!stop & this.cur() != -1 & this.cur() != '"')
                {
                    switch (this.cur() == '{')
                    {
                        case (true) {
                        this.vput('{');
                        this.adv(1);
                        depth = 1;
                        while (this.cur() != -1 & depth > 0)
                        {
                            switch (this.cur() == '"')
                            {
                                case (true) {
                                this.fail(LexError.FSTRING_UNTERMINATED, this.line, this.column);
                                -> false;
                            }
                                default
                                {
                                    switch (this.cur() == '{')
                                    {
                                        case (true) { depth++; }
                                        default {
                                            switch (this.cur() == '}')
                                            {
                                                case (true) { depth--; }
                                                default {};
                                            };
                                        };
                                    };
                                    this.vput(this.cur());
                                    this.adv(1);
                                };
                            };
                        };
                    }
                        default {
                            switch (this.cur() == '\\')
                            {
                                case (true) {
                        this.adv(1);
                        e = this.cur();
                        switch (e)
                        {
                            case (-1)
                            {
                                stop = true;
                            }
                            default
                            {
                                switch (e)
                                {
                                    case ('n') { this.vput(10); }
                                    case ('t') { this.vput(9); }
                                    case ('r') { this.vput(13); }
                                    case ('0') { this.vput(0); }
                                    case ('\\') { this.vput(92); }
                                    case ('"') { this.vput(34); }
                                    default { this.vput(e); };
                                };
                                this.adv(1);
                            };
                        };
                    }
                                default {
                        this.vput(this.cur());
                        this.adv(1);
                    };
                            };
                        };
                    };
                };
                switch (this.cur() == '"')
                {
                    case (true) { this.adv(1); }
                    default {};
                };
                -> true;
            };

            // i"name":{ expr; ... }  The leading i is already consumed.
            read_i_string() -> void
            {
                int ln = this.line;
                int col = this.column;
                int vb = this.vbegin();
                int depth;
                this.vput('i');
                this.vput('"');
                this.read_string('"');
                this.vput('"');

                this.skip_whitespace();
                switch (this.cur() == ':')
                {
                    case (true) { this.adv(1); }
                    default {};
                };
                this.skip_whitespace();
                switch (this.cur() == '{')
                {
                    case (true) {
                    this.vput(':');
                    this.vput('{');
                    this.adv(1);
                    depth = 1;
                    while (this.cur() != -1 & depth > 0)
                    {
                        switch (this.cur() == '{')
                        {
                            case (true) { depth++; }
                            default {
                                switch (this.cur() == '}')
                                {
                                    case (true) { depth--; }
                                    default {};
                                };
                            };
                        };
                        this.vput(this.cur());
                        this.adv(1);
                    };
                }
                    default {};
                };
                int vl = this.vend(vb);
                -> this.emit(TokenType.I_STRING, ln, col, vb, vl, 0);
            };

            // ===== NUMBERS =====

            // Suffix handling shared by 0x / 0o / 0d / 0b literals
            finish_prefixed(int ln, int col, int vb, bool allow_byte) -> void
            {
                int tt = TokenType.SINT_LITERAL;
                int c = this.cur();
                switch (c == 'u')
                {
                    case (true) {
                    this.adv(1);
                    switch (this.cur() == 'l')
                    {
                        case (true) {
                        this.adv(1);
                        tt = TokenType.ULONG_LITERAL;
                    }
                        default {
                        tt = TokenType.UINT_LITERAL;
                    };
                    };
                }
                    default {
                        switch (c == 'l')
                        {
                            case (true) {
                    this.adv(1);
                    tt = TokenType.SLONG_LITERAL;
                }
                            default {
                                switch (allow_byte & c == 'b')
                                {
                                    case (true) {
                    this.adv(1);
                    tt = TokenType.BYTE_LITERAL;
                }
                                    default {};
                                };
                            };
                        };
                    };
                };
                int vl = this.vend(vb);
                -> this.emit(tt, ln, col, vb, vl, 0);
            };

            digit_at(int vb, int int_len, int n, int i) -> int
            {
                switch (i >= n)
                {
                    case (true) { -> '0'; }
                    default
                    {
                        switch (i < int_len)
                        {
                            case (true) { -> (int)this.arena[vb + i]; }
                            default
                            {
                                -> (int)this.arena[vb + i + 1];
                            };
                        };
                    };
                };
            };

            // Mantissa digits are already in the arena at vb (integer part,
            // optional '.', fraction). The current character is the 'e'/'E'.
            // The value is rewritten as an exact plain decimal string.
            read_scientific(int ln, int col, int vb, int int_len, bool had_dot) -> void
            {
                this.adv(1);
                int sign = 1;
                switch (this.cur() == '+' | this.cur() == '-')
                {
                    case (true) {
                    switch (this.cur() == '-')
                    {
                        case (true) { sign = -1; }
                        default {};
                    };
                    this.adv(1);
                }
                    default {};
                };
                int exponent = 0;
                bool too_big = false;
                while (is_digit(this.cur()))
                {
                    switch (exponent > 1000000)
                    {
                        case (true) { too_big = true; }
                        default { exponent = exponent * 10 + (this.cur() - 48); };
                    };
                    this.adv(1);
                };
                switch (too_big | exponent > 1000000)
                {
                    case (true) {
                    -> this.fail(LexError.EXPONENT_RANGE, ln, col);
                }
                    default
                    {
                        exponent = exponent * sign;

                        int n = this.arena_len - vb;
                        switch (had_dot)
                        {
                            case (true) { n = n - 1; }
                            default {};
                        };
                        int point = int_len + exponent;
                        int out_start = this.arena_len;

                        // integer part
                        int ipart = 0;
                        switch (point > 0)
                        {
                            case (true) { ipart = point; }
                            default {};
                        };
                        int j, j0 = -1;
                        while (j < ipart)
                        {
                            switch (this.digit_at(vb, int_len, n, j) != '0')
                            {
                                case (true) {
                                j0 = j;
                                break;
                            }
                                default
                                {
                                    j++;
                                };
                            };
                        };
                        switch (j0)
                        {
                            case (-1)
                            {
                                this.vput('0');
                            }
                            default
                            {
                                j = j0;
                                while (j < ipart)
                                {
                                    this.vput(this.digit_at(vb, int_len, n, j));
                                    j++;
                                };
                            };
                        };

                        // fractional part
                        int z = 0;
                        switch (point < 0)
                        {
                            case (true) { z = 0 - point; }
                            default {};
                        };
                        int fstart = 0;
                        switch (point > 0)
                        {
                            case (true) { fstart = point; }
                            default {};
                        };
                        int flen = 0;
                        switch (n > fstart)
                        {
                            case (true) { flen = z + (n - fstart); }
                            default {};
                        };

                        int lt, m = flen, idx, dch;
                        while (m > 0)
                        {
                            idx = m - 1;
                            switch (idx < z)
                            {
                                case (true) { dch = '0'; }
                                default { dch = this.digit_at(vb, int_len, n, fstart + (idx - z)); };
                            };
                            switch (dch != '0')
                            {
                                case (true) {
                                lt = m;
                                break;
                            }
                                default
                                {
                                    m--;
                                };
                            };
                        };
                        switch (lt > 0)
                        {
                            case (true) {
                            this.vput('.');
                            m = 0;
                            while (m < lt)
                            {
                                switch (m < z)
                                {
                                    case (true) { dch = '0'; }
                                    default { dch = this.digit_at(vb, int_len, n, fstart + (m - z)); };
                                };
                                this.vput(dch);
                                m++;
                            };
                        }
                            default {};
                        };

                        // move the expanded text down over the mantissa
                        int out_len = this.arena_len - out_start;
                        int k;
                        while (k < out_len)
                        {
                            this.arena[vb + k] = this.arena[out_start + k];
                            k++;
                        };
                        this.arena_len = vb + out_len;
                        int vl = this.vend(vb);

                        int tt;
                        switch (this.cur() == 'f')
                        {
                            case (true) {
                            this.adv(1);
                            tt = TokenType.FLOAT;
                        }
                            default {
                                switch (this.cur() == 'd')
                                {
                                    case (true) {
                            this.adv(1);
                            tt = TokenType.DOUBLE;
                        }
                                    default {
                            int abs_exp = exponent;
                            switch (abs_exp < 0)
                            {
                                case (true) { abs_exp = 0 - abs_exp; }
                                default {};
                            };
                            switch (abs_exp <= 5)
                            {
                                case (true) { tt = TokenType.FLOAT; }
                                default { tt = TokenType.DOUBLE; };
                            };
                        };
                                };
                            };
                        };
                        -> this.emit(tt, ln, col, vb, vl, 0);
                    };
                };
            };

            read_number() -> void
            {
                int ln = this.line;
                int col = this.column;
                int vb = this.vbegin();
                int c, vl;
                bool is_float, is_double;

                switch (this.cur() == '0')
                {
                    case (true) {
                    this.vput('0');
                    this.adv(1);
                    c = this.cur();

                    switch (c == 'd' | c == 'D')
                    {
                        case (true) {
                        this.vput(c);
                        this.adv(1);
                        while (is_base32_digit(this.cur()))
                        {
                            this.vput(this.cur());
                            this.adv(1);
                        };
                        -> this.finish_prefixed(ln, col, vb, true);
                    }
                        default
                        {
                            switch (c == 'x' | c == 'X')
                            {
                                case (true) {
                                this.vput(c);
                                this.adv(1);
                                while (is_hex_upper(this.cur()))
                                {
                                    this.vput(this.cur());
                                    this.adv(1);
                                };
                                -> this.finish_prefixed(ln, col, vb, true);
                            }
                                default
                                {
                                    switch (c == 'o' | c == 'O')
                                    {
                                        case (true) {
                                        this.vput(c);
                                        this.adv(1);
                                        while (this.cur() >= '0' & this.cur() <= '7')
                                        {
                                            this.vput(this.cur());
                                            this.adv(1);
                                        };
                                        -> this.finish_prefixed(ln, col, vb, true);
                                    }
                                        default
                                        {
                                            switch (c == 'b' | c == 'B')
                                            {
                                                case (true) {
                                                this.vput(c);
                                                this.adv(1);
                                                while (this.cur() == '0' | this.cur() == '1')
                                                {
                                                    this.vput(this.cur());
                                                    this.adv(1);
                                                };
                                                // `0b` with no digits is the byte-suffix form of 0
                                                switch (c == 'b' & this.arena_len - vb == 2)
                                                {
                                                    case (true) {
                                                    this.arena_len = vb;
                                                    this.vput('0');
                                                    vl = this.vend(vb);
                                                    -> this.emit(TokenType.BYTE_LITERAL, ln, col, vb, vl, 0);
                                                }
                                                    default
                                                    {
                                                        -> this.finish_prefixed(ln, col, vb, false);
                                                    };
                                                };
                                            }
                                                default {};
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                }
                    default {};
                };

                // decimal digits
                while (is_digit(this.cur()))
                {
                    this.vput(this.cur());
                    this.adv(1);
                };

                int int_len = this.arena_len - vb;
                int dc = 0;
                bool had_dot = false;
                switch (this.cur() == '.' & is_digit(this.peek(1)))
                {
                    case (true) {
                    is_float = true;
                    had_dot = true;
                    this.vput('.');
                    this.adv(1);
                    while (is_digit(this.cur()))
                    {
                        dc++;
                        this.vput(this.cur());
                        this.adv(1);
                    };
                }
                    default {};
                };

                // scientific notation: e/E, optional sign, digits
                c = this.cur();
                switch (c == 'e' | c == 'E')
                {
                    case (true) {
                    int n1 = this.peek(1);
                    int n2 = this.peek(2);
                    bool exp_valid = false;
                    switch (is_digit(n1))
                    {
                        case (true) { exp_valid = true; }
                        default {
                            switch ((n1 == '+' | n1 == '-') & is_digit(n2))
                            {
                                case (true) { exp_valid = true; }
                                default {};
                            };
                        };
                    };
                    switch (exp_valid)
                    {
                        case (true) {
                        -> this.read_scientific(ln, col, vb, int_len, had_dot);
                    }
                        default {};
                    };
                }
                    default {};
                };

                // suffixes
                int tt = TokenType.SINT_LITERAL;
                switch (this.cur() == 'f')
                {
                    case (true) {
                    tt = TokenType.FLOAT;
                    is_float = true;
                    this.adv(1);
                }
                    default {};
                };
                c = this.cur();
                switch (c == 'd')
                {
                    case (true) {
                    tt = TokenType.DOUBLE;
                    is_double = true;
                    this.adv(1);
                }
                    default {
                        switch (!is_float & c == 'u' & this.peek(1) == 'l')
                        {
                            case (true) {
                    tt = TokenType.ULONG_LITERAL;
                    this.adv(2);
                }
                            default {
                                switch (!is_float & c == 'u')
                                {
                                    case (true) {
                    tt = TokenType.UINT_LITERAL;
                    this.adv(1);
                }
                                    default {
                                        switch (!is_float & c == 'l')
                                        {
                                            case (true) {
                    tt = TokenType.SLONG_LITERAL;
                    this.adv(1);
                }
                                            default {
                                                switch (!is_float & c == 'b')
                                                {
                                                    case (true) {
                    tt = TokenType.BYTE_LITERAL;
                    this.adv(1);
                }
                                                    default {
                                                        switch (!is_float & c == 'c')
                                                        {
                                                            case (true) {
                    // numeric char literal: value is the codepoint in decimal
                    this.adv(1);
                    int s = vb;
                    int e = this.arena_len;
                    while (s < e - 1 & this.arena[s] == '0') { s++; };
                    int k;
                    int n = e - s;
                    while (k < n)
                    {
                        this.arena[vb + k] = this.arena[s + k];
                        k++;
                    };
                    this.arena_len = vb + n;
                    vl = this.vend(vb);
                    -> this.emit(TokenType.CHAR, ln, col, vb, vl, 1);
                }
                                                            default {};
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };

                switch (is_float & dc <= 5)
                {
                    case (true) { tt = TokenType.FLOAT; }
                    default {};
                };
                switch (is_double | dc > 5)
                {
                    case (true) { tt = TokenType.DOUBLE; }
                    default {};
                };

                vl = this.vend(vb);
                -> this.emit(tt, ln, col, vb, vl, 0);
            };

            // ===== IDENTIFIERS =====

            // Reads an identifier or keyword, emits it, returns its token type
            read_identifier() -> int
            {
                int ln = this.line;
                int col = this.column;
                int start = this.position;
                while (this.cur() != -1 & is_ident_char(this.cur()))
                {
                    this.adv(1);
                };
                int n = this.position - start;
                int tt = keyword_type(this.src + start, n);
                this.emit_text(tt, ln, col, this.src + start, n);
                -> tt;
            };

            // ===== OPERATORS =====

            // Longest match first, 6 down to 1 characters, exactly the order of
            // the dictionaries in flexer.py. Returns the match length (0 if none)
            // and the token type through ttype.
            match_op(int* ttype) -> int
            {
                int avail = this.length - this.position;
            switch (avail >= 6)
            {
                case (true) {
                switch (this.match(g"`^|!&=", 6))
                {
                    case (true) { *ttype = TokenType.BITXNAND_ASSIGN; -> 6; }
                    default
                    {
                        switch (this.match(g"`^|!|=", 6))
                        {
                            case (true) { *ttype = TokenType.BITXNOR_ASSIGN; -> 6; }
                            default {};
                        };
                    };
                };
            }
                default {};
            };
            switch (avail >= 5)
            {
                case (true) {
                switch (this.match(g"`^|!&", 5))
                {
                    case (true) { *ttype = TokenType.BITXNAND; -> 5; }
                    default
                    {
                        switch (this.match(g"`^|!|", 5))
                        {
                            case (true) { *ttype = TokenType.BITXNOR; -> 5; }
                            default
                            {
                                switch (this.match(g"`^|!=", 5))
                                {
                                    case (true) { *ttype = TokenType.BITXNOT_ASSIGN; -> 5; }
                                    default {};
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            switch (avail >= 4)
            {
                case (true) {
                switch (this.match(g"`^|!", 4))
                {
                    case (true) { *ttype = TokenType.BITXNOT; -> 4; }
                    default
                    {
                        switch (this.match(g"`!&=", 4))
                        {
                            case (true) { *ttype = TokenType.BITNAND_ASSIGN; -> 4; }
                            default
                            {
                                switch (this.match(g"`!|=", 4))
                                {
                                    case (true) { *ttype = TokenType.BITNOR_ASSIGN; -> 4; }
                                    default
                                    {
                                        switch (this.match(g"`^|=", 4))
                                        {
                                            case (true) { *ttype = TokenType.BITXOR_ASSIGN; -> 4; }
                                            default {};
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            switch (avail >= 3)
            {
                case (true) {
                switch (this.match(g"<<=", 3))
                {
                    case (true) { *ttype = TokenType.BITSHIFT_LEFT_ASSIGN; -> 3; }
                    default
                    {
                        switch (this.match(g">>=", 3))
                        {
                            case (true) { *ttype = TokenType.BITSHIFT_RIGHT_ASSIGN; -> 3; }
                            default
                            {
                                switch (this.match(g"^|=", 3))
                                {
                                    case (true) { *ttype = TokenType.XOR_ASSIGN; -> 3; }
                                    default
                                    {
                                        switch (this.match(g"{}*", 3))
                                        {
                                            case (true) { *ttype = TokenType.FUNCTION_POINTER; -> 3; }
                                            default
                                            {
                                                switch (this.match(g"(@)", 3))
                                                {
                                                    case (true) { *ttype = TokenType.ADDRESS_CAST; -> 3; }
                                                    default
                                                    {
                                                        switch (this.match(g"...", 3))
                                                        {
                                                            case (true) { *ttype = TokenType.ELLIPSIS; -> 3; }
                                                            default
                                                            {
                                                                switch (this.match(g"`!&", 3))
                                                                {
                                                                    case (true) { *ttype = TokenType.BITNAND_OP; -> 3; }
                                                                    default
                                                                    {
                                                                        switch (this.match(g"`!|", 3))
                                                                        {
                                                                            case (true) { *ttype = TokenType.BITNOR_OP; -> 3; }
                                                                            default
                                                                            {
                                                                                switch (this.match(g"`&=", 3))
                                                                                {
                                                                                    case (true) { *ttype = TokenType.BITAND_ASSIGN; -> 3; }
                                                                                    default
                                                                                    {
                                                                                        switch (this.match(g"`|=", 3))
                                                                                        {
                                                                                            case (true) { *ttype = TokenType.BITOR_ASSIGN; -> 3; }
                                                                                            default
                                                                                            {
                                                                                                switch (this.match(g"`^|", 3))
                                                                                                {
                                                                                                    case (true) { *ttype = TokenType.BITXOR_OP; -> 3; }
                                                                                                    default {};
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            switch (avail >= 2)
            {
                case (true) {
                switch (this.match(g"==", 2))
                {
                    case (true) { *ttype = TokenType.EQUAL; -> 2; }
                    default
                    {
                        switch (this.match(g"!=", 2))
                        {
                            case (true) { *ttype = TokenType.NOT_EQUAL; -> 2; }
                            default
                            {
                                switch (this.match(g"<=", 2))
                                {
                                    case (true) { *ttype = TokenType.LESS_EQUAL; -> 2; }
                                    default
                                    {
                                        switch (this.match(g">=", 2))
                                        {
                                            case (true) { *ttype = TokenType.GREATER_EQUAL; -> 2; }
                                            default
                                            {
                                                switch (this.match(g"<<", 2))
                                                {
                                                    case (true) { *ttype = TokenType.BITSHIFT_LEFT; -> 2; }
                                                    default
                                                    {
                                                        switch (this.match(g">>", 2))
                                                        {
                                                            case (true) { *ttype = TokenType.BITSHIFT_RIGHT; -> 2; }
                                                            default
                                                            {
                                                                switch (this.match(g"++", 2))
                                                                {
                                                                    case (true) { *ttype = TokenType.INCREMENT; -> 2; }
                                                                    default
                                                                    {
                                                                        switch (this.match(g"--", 2))
                                                                        {
                                                                            case (true) { *ttype = TokenType.DECREMENT; -> 2; }
                                                                            default
                                                                            {
                                                                                switch (this.match(g"+=", 2))
                                                                                {
                                                                                    case (true) { *ttype = TokenType.PLUS_ASSIGN; -> 2; }
                                                                                    default
                                                                                    {
                                                                                        switch (this.match(g"-=", 2))
                                                                                        {
                                                                                            case (true) { *ttype = TokenType.MINUS_ASSIGN; -> 2; }
                                                                                            default
                                                                                            {
                                                                                                switch (this.match(g"*=", 2))
                                                                                                {
                                                                                                    case (true) { *ttype = TokenType.MULTIPLY_ASSIGN; -> 2; }
                                                                                                    default
                                                                                                    {
                                                                                                        switch (this.match(g"/=", 2))
                                                                                                        {
                                                                                                            case (true) { *ttype = TokenType.DIVIDE_ASSIGN; -> 2; }
                                                                                                            default
                                                                                                            {
                                                                                                                switch (this.match(g"%=", 2))
                                                                                                                {
                                                                                                                    case (true) { *ttype = TokenType.MODULO_ASSIGN; -> 2; }
                                                                                                                    default
                                                                                                                    {
                                                                                                                        switch (this.match(g"^=", 2))
                                                                                                                        {
                                                                                                                            case (true) { *ttype = TokenType.EXPONENT_ASSIGN; -> 2; }
                                                                                                                            default
                                                                                                                            {
                                                                                                                                switch (this.match(g"&=", 2))
                                                                                                                                {
                                                                                                                                    case (true) { *ttype = TokenType.AND_ASSIGN; -> 2; }
                                                                                                                                    default
                                                                                                                                    {
                                                                                                                                        switch (this.match(g"|=", 2))
                                                                                                                                        {
                                                                                                                                            case (true) { *ttype = TokenType.OR_ASSIGN; -> 2; }
                                                                                                                                            default
                                                                                                                                            {
                                                                                                                                                switch (this.match(g"!&", 2))
                                                                                                                                                {
                                                                                                                                                    case (true) { *ttype = TokenType.NAND_OP; -> 2; }
                                                                                                                                                    default
                                                                                                                                                    {
                                                                                                                                                        switch (this.match(g"!|", 2))
                                                                                                                                                        {
                                                                                                                                                            case (true) { *ttype = TokenType.NOR_OP; -> 2; }
                                                                                                                                                            default
                                                                                                                                                            {
                                                                                                                                                                switch (this.match(g"^|", 2))
                                                                                                                                                                {
                                                                                                                                                                    case (true) { *ttype = TokenType.XOR_OP; -> 2; }
                                                                                                                                                                    default
                                                                                                                                                                    {
                                                                                                                                                                        switch (this.match(g"!!", 2))
                                                                                                                                                                        {
                                                                                                                                                                            case (true) { *ttype = TokenType.NO_MANGLE; -> 2; }
                                                                                                                                                                            default
                                                                                                                                                                            {
                                                                                                                                                                                switch (this.match(g"??", 2))
                                                                                                                                                                                {
                                                                                                                                                                                    case (true) { *ttype = TokenType.NULL_COALESCE; -> 2; }
                                                                                                                                                                                    default
                                                                                                                                                                                    {
                                                                                                                                                                                        switch (this.match(g"->", 2))
                                                                                                                                                                                        {
                                                                                                                                                                                            case (true) { *ttype = TokenType.RETURN_ARROW; -> 2; }
                                                                                                                                                                                            default
                                                                                                                                                                                            {
                                                                                                                                                                                                switch (this.match(g"<-", 2))
                                                                                                                                                                                                {
                                                                                                                                                                                                    case (true) { *ttype = TokenType.CHAIN_ARROW; -> 2; }
                                                                                                                                                                                                    default
                                                                                                                                                                                                    {
                                                                                                                                                                                                        switch (this.match(g"<~", 2))
                                                                                                                                                                                                        {
                                                                                                                                                                                                            case (true) { *ttype = TokenType.RECURSE_ARROW; -> 2; }
                                                                                                                                                                                                            default
                                                                                                                                                                                                            {
                                                                                                                                                                                                                switch (this.match(g"..", 2))
                                                                                                                                                                                                                {
                                                                                                                                                                                                                    case (true) { *ttype = TokenType.RANGE; -> 2; }
                                                                                                                                                                                                                    default
                                                                                                                                                                                                                    {
                                                                                                                                                                                                                        switch (this.match(g"::", 2))
                                                                                                                                                                                                                        {
                                                                                                                                                                                                                            case (true) { *ttype = TokenType.SCOPE; -> 2; }
                                                                                                                                                                                                                            default
                                                                                                                                                                                                                            {
                                                                                                                                                                                                                                switch (this.match(g"?=", 2))
                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                    case (true) { *ttype = TokenType.TERNARY_ASSIGN; -> 2; }
                                                                                                                                                                                                                                    default
                                                                                                                                                                                                                                    {
                                                                                                                                                                                                                                        switch (this.match(g"!?", 2))
                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                            case (true) { *ttype = TokenType.NOT_NULL; -> 2; }
                                                                                                                                                                                                                                            default
                                                                                                                                                                                                                                            {
                                                                                                                                                                                                                                                switch (this.match(g"@=", 2))
                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                    case (true) { *ttype = TokenType.ADDRESS_ASSIGN; -> 2; }
                                                                                                                                                                                                                                                    default
                                                                                                                                                                                                                                                    {
                                                                                                                                                                                                                                                        switch (this.match(g"``", 2))
                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                            case (true) { *ttype = TokenType.BITSLICE; -> 2; }
                                                                                                                                                                                                                                                            default
                                                                                                                                                                                                                                                            {
                                                                                                                                                                                                                                                                switch (this.match(g"~$", 2))
                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                    case (true) { *ttype = TokenType.CODIFY; -> 2; }
                                                                                                                                                                                                                                                                    default
                                                                                                                                                                                                                                                                    {
                                                                                                                                                                                                                                                                        switch (this.match(g"#\"", 2))
                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                            case (true) { *ttype = TokenType.DITTO; -> 2; }
                                                                                                                                                                                                                                                                            default
                                                                                                                                                                                                                                                                            {
                                                                                                                                                                                                                                                                                switch (this.match(g"d{", 2))
                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                    case (true) { *ttype = TokenType.DICT_LITERAL; -> 2; }
                                                                                                                                                                                                                                                                                    default
                                                                                                                                                                                                                                                                                    {
                                                                                                                                                                                                                                                                                        switch (this.match(g"`!", 2))
                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                            case (true) { *ttype = TokenType.BITNOT_OP; -> 2; }
                                                                                                                                                                                                                                                                                            default
                                                                                                                                                                                                                                                                                            {
                                                                                                                                                                                                                                                                                                switch (this.match(g"`&", 2))
                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                    case (true) { *ttype = TokenType.BITAND_OP; -> 2; }
                                                                                                                                                                                                                                                                                                    default
                                                                                                                                                                                                                                                                                                    {
                                                                                                                                                                                                                                                                                                        switch (this.match(g"`|", 2))
                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                            case (true) { *ttype = TokenType.BITOR_OP; -> 2; }
                                                                                                                                                                                                                                                                                                            default {};
                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                };
                                                                                                                                                                                                                            };
                                                                                                                                                                                                                        };
                                                                                                                                                                                                                    };
                                                                                                                                                                                                                };
                                                                                                                                                                                                            };
                                                                                                                                                                                                        };
                                                                                                                                                                                                    };
                                                                                                                                                                                                };
                                                                                                                                                                                            };
                                                                                                                                                                                        };
                                                                                                                                                                                    };
                                                                                                                                                                                };
                                                                                                                                                                            };
                                                                                                                                                                        };
                                                                                                                                                                    };
                                                                                                                                                                };
                                                                                                                                                            };
                                                                                                                                                        };
                                                                                                                                                    };
                                                                                                                                                };
                                                                                                                                            };
                                                                                                                                        };
                                                                                                                                    };
                                                                                                                                };
                                                                                                                            };
                                                                                                                        };
                                                                                                                    };
                                                                                                                };
                                                                                                            };
                                                                                                        };
                                                                                                    };
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            }
                default {};
            };
            // single character tokens
            switch (this.match(g"+", 1))
            {
                case (true) { *ttype = TokenType.PLUS; -> 1; }
                default
                {
                    switch (this.match(g"-", 1))
                    {
                        case (true) { *ttype = TokenType.MINUS; -> 1; }
                        default
                        {
                            switch (this.match(g"*", 1))
                            {
                                case (true) { *ttype = TokenType.MULTIPLY; -> 1; }
                                default
                                {
                                    switch (this.match(g"/", 1))
                                    {
                                        case (true) { *ttype = TokenType.DIVIDE; -> 1; }
                                        default
                                        {
                                            switch (this.match(g"%", 1))
                                            {
                                                case (true) { *ttype = TokenType.MODULO; -> 1; }
                                                default
                                                {
                                                    switch (this.match(g"^", 1))
                                                    {
                                                        case (true) { *ttype = TokenType.EXPONENT; -> 1; }
                                                        default
                                                        {
                                                            switch (this.match(g"<", 1))
                                                            {
                                                                case (true) { *ttype = TokenType.LESS_THAN; -> 1; }
                                                                default
                                                                {
                                                                    switch (this.match(g">", 1))
                                                                    {
                                                                        case (true) { *ttype = TokenType.GREATER_THAN; -> 1; }
                                                                        default
                                                                        {
                                                                            switch (this.match(g"&", 1))
                                                                            {
                                                                                case (true) { *ttype = TokenType.LOGICAL_AND; -> 1; }
                                                                                default
                                                                                {
                                                                                    switch (this.match(g"|", 1))
                                                                                    {
                                                                                        case (true) { *ttype = TokenType.LOGICAL_OR; -> 1; }
                                                                                        default
                                                                                        {
                                                                                            switch (this.match(g"!", 1))
                                                                                            {
                                                                                                case (true) { *ttype = TokenType.NOT; -> 1; }
                                                                                                default
                                                                                                {
                                                                                                    switch (this.match(g"@", 1))
                                                                                                    {
                                                                                                        case (true) { *ttype = TokenType.ADDRESS_OF; -> 1; }
                                                                                                        default
                                                                                                        {
                                                                                                            switch (this.match(g"=", 1))
                                                                                                            {
                                                                                                                case (true) { *ttype = TokenType.ASSIGN; -> 1; }
                                                                                                                default
                                                                                                                {
                                                                                                                    switch (this.match(g"?", 1))
                                                                                                                    {
                                                                                                                        case (true) { *ttype = TokenType.QUESTION; -> 1; }
                                                                                                                        default
                                                                                                                        {
                                                                                                                            switch (this.match(g":", 1))
                                                                                                                            {
                                                                                                                                case (true) { *ttype = TokenType.COLON; -> 1; }
                                                                                                                                default
                                                                                                                                {
                                                                                                                                    switch (this.match(g"(", 1))
                                                                                                                                    {
                                                                                                                                        case (true) { *ttype = TokenType.LEFT_PAREN; -> 1; }
                                                                                                                                        default
                                                                                                                                        {
                                                                                                                                            switch (this.match(g")", 1))
                                                                                                                                            {
                                                                                                                                                case (true) { *ttype = TokenType.RIGHT_PAREN; -> 1; }
                                                                                                                                                default
                                                                                                                                                {
                                                                                                                                                    switch (this.match(g"[", 1))
                                                                                                                                                    {
                                                                                                                                                        case (true) { *ttype = TokenType.LEFT_BRACKET; -> 1; }
                                                                                                                                                        default
                                                                                                                                                        {
                                                                                                                                                            switch (this.match(g"]", 1))
                                                                                                                                                            {
                                                                                                                                                                case (true) { *ttype = TokenType.RIGHT_BRACKET; -> 1; }
                                                                                                                                                                default
                                                                                                                                                                {
                                                                                                                                                                    switch (this.match(g"{", 1))
                                                                                                                                                                    {
                                                                                                                                                                        case (true) { *ttype = TokenType.LEFT_BRACE; -> 1; }
                                                                                                                                                                        default
                                                                                                                                                                        {
                                                                                                                                                                            switch (this.match(g"}", 1))
                                                                                                                                                                            {
                                                                                                                                                                                case (true) { *ttype = TokenType.RIGHT_BRACE; -> 1; }
                                                                                                                                                                                default
                                                                                                                                                                                {
                                                                                                                                                                                    switch (this.match(g";", 1))
                                                                                                                                                                                    {
                                                                                                                                                                                        case (true) { *ttype = TokenType.SEMICOLON; -> 1; }
                                                                                                                                                                                        default
                                                                                                                                                                                        {
                                                                                                                                                                                            switch (this.match(g",", 1))
                                                                                                                                                                                            {
                                                                                                                                                                                                case (true) { *ttype = TokenType.COMMA; -> 1; }
                                                                                                                                                                                                default
                                                                                                                                                                                                {
                                                                                                                                                                                                    switch (this.match(g".", 1))
                                                                                                                                                                                                    {
                                                                                                                                                                                                        case (true) { *ttype = TokenType.DOT; -> 1; }
                                                                                                                                                                                                        default
                                                                                                                                                                                                        {
                                                                                                                                                                                                            switch (this.match(g"~", 1))
                                                                                                                                                                                                            {
                                                                                                                                                                                                                case (true) { *ttype = TokenType.TIE; -> 1; }
                                                                                                                                                                                                                default
                                                                                                                                                                                                                {
                                                                                                                                                                                                                    switch (this.match(g"$", 1))
                                                                                                                                                                                                                    {
                                                                                                                                                                                                                        case (true) { *ttype = TokenType.STRINGIFY; -> 1; }
                                                                                                                                                                                                                        default
                                                                                                                                                                                                                        {
                                                                                                                                                                                                                            switch (this.match(g"\\", 1))
                                                                                                                                                                                                                            {
                                                                                                                                                                                                                                case (true) { *ttype = TokenType.BACKSLASH; -> 1; }
                                                                                                                                                                                                                                default
                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                    switch (this.match(g"`", 1))
                                                                                                                                                                                                                                    {
                                                                                                                                                                                                                                        case (true) { *ttype = TokenType.BACKTICK; -> 1; }
                                                                                                                                                                                                                                        default
                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                            switch (this.match(g"#", 1))
                                                                                                                                                                                                                                            {
                                                                                                                                                                                                                                                case (true) { *ttype = TokenType.TAG; -> 1; }
                                                                                                                                                                                                                                                default
                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                    -> 0;
                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                };
                                                                                                                                                                                                                            };
                                                                                                                                                                                                                        };
                                                                                                                                                                                                                    };
                                                                                                                                                                                                                };
                                                                                                                                                                                                            };
                                                                                                                                                                                                        };
                                                                                                                                                                                                    };
                                                                                                                                                                                                };
                                                                                                                                                                                            };
                                                                                                                                                                                        };
                                                                                                                                                                                    };
                                                                                                                                                                                };
                                                                                                                                                                            };
                                                                                                                                                                        };
                                                                                                                                                                    };
                                                                                                                                                                };
                                                                                                                                                            };
                                                                                                                                                        };
                                                                                                                                                    };
                                                                                                                                                };
                                                                                                                                            };
                                                                                                                                        };
                                                                                                                                    };
                                                                                                                                };
                                                                                                                            };
                                                                                                                        };
                                                                                                                    };
                                                                                                                };
                                                                                                            };
                                                                                                        };
                                                                                                    };
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };
            };

            // ===== MAIN LOOP =====

            // Tokenizes the whole source. Returns false on error, in which case
            // err_code / err_line / err_col describe it.
            // Splits a '>>' that closes two nested template argument lists into two '>'
            // tokens (mirrors flexer.py _split_template_closers).
            split_template_closers() -> void
            {
                int i, depth, t, extra, vb, vl, j, n = this.count, prev = -1;
                while (i < n)
                {
                    t = this.tokens[i].type;
                    if (t == TokenType.LESS_THAN & prev == TokenType.IDENTIFIER) { depth++; };
                    if (t == TokenType.GREATER_THAN & depth > 0) { depth--; };
                    prev = t;
                    if (t == TokenType.BITSHIFT_RIGHT & depth >= 2)
                    {
                        this.tokens[i].numeric_char = 2;
                        depth = depth - 2;
                        extra++;
                        prev = TokenType.GREATER_THAN;
                    };
                    if (t == TokenType.SEMICOLON | t == TokenType.LEFT_PAREN | t == TokenType.RIGHT_PAREN | (depth == 0 & (t == TokenType.LEFT_BRACE | t == TokenType.RIGHT_BRACE)))
                    {
                        depth = 0;
                    };
                    i++;
                };
                if (extra == 0) { ->; };
                if (n + extra > this.cap)
                {
                    -> this.fail(LexError.ALLOC_FAILED, this.tokens[0].line, this.tokens[0].column);
                };
                vb = this.vbegin();
                this.vput('>');
                vl = this.vend(vb);
                j = n - 1 + extra;
                i = n - 1;
                while (i >= 0)
                {
                    if (this.tokens[i].numeric_char == 2)
                    {
                        this.tokens[j] = this.tokens[i];
                        this.tokens[j].type = TokenType.GREATER_THAN;
                        this.tokens[j].column = this.tokens[i].column + 1;
                        this.tokens[j].voff = vb;
                        this.tokens[j].vlen = vl;
                        this.tokens[j].numeric_char = 0;
                        this.tokens[j - 1] = this.tokens[j];
                        this.tokens[j - 1].column = this.tokens[i].column;
                        j = j - 2;
                    }
                    else
                    {
                        this.tokens[j] = this.tokens[i];
                        j--;
                    };
                    i--;
                };
                this.count = n + extra;
                ->;
            };

            tokenize() -> bool
            {
                int c, ln, col, tt, vb, vl, cnt, i, oplen, optype, cp, extra, wstart;
                int saved_pos, saved_line, saved_col;

                while (this.position < this.length)
                {
                    switch (this.err_code != 0)
                    {
                        case (true) { -> false; }
                        default
                        {
                            switch (this.skip_whitespace())
                            {
                                case (true) { continue; }
                                default
                                {
                                    c = this.cur();
                                    switch (c == -1)
                                    {
                                        case (true) { break; }
                                        default
                                        {
                                            ln = this.line;
                                            col = this.column;

                                            // i-string. Its token position is taken after the leading i.
                                            switch (c == 'i' & this.peek(1) == '"')
                                            {
                                                case (true) {
                                                this.adv(1);
                                                this.read_i_string();
                                                continue;
                                            }
                                                default
                                                {
                                                    // f-string
                                                    switch (c == 'f' & this.peek(1) == '"')
                                                    {
                                                        case (true) {
                                                        this.adv(1);
                                                        vb = this.vbegin();
                                                        this.vput('f');
                                                        this.vput('"');
                                                        switch (!this.read_f_string_body())
                                                        {
                                                            case (true) { -> false; }
                                                            default {};
                                                        };
                                                        this.vput('"');
                                                        vl = this.vend(vb);
                                                        this.emit(TokenType.F_STRING, ln, col, vb, vl, 0);
                                                        continue;
                                                    }
                                                        default
                                                        {
                                                            // g-string
                                                            switch (c == 'g' & this.peek(1) == '"')
                                                            {
                                                                case (true) {
                                                                this.adv(1);
                                                                vb = this.vbegin();
                                                                this.read_string('"');
                                                                vl = this.vend(vb);
                                                                this.emit(TokenType.G_STRING, ln, col, vb, vl, 0);
                                                                continue;
                                                            }
                                                                default
                                                                {
                                                                    // string and char literals
                                                                    switch (c == '"')
                                                                    {
                                                                        case (true) {
                                                                        vb = this.vbegin();
                                                                        this.read_string('"');
                                                                        vl = this.vend(vb);
                                                                        this.emit(TokenType.STRING_LITERAL, ln, col, vb, vl, 0);
                                                                        continue;
                                                                    }
                                                                        default
                                                                        {
                                                                            switch (c == 39)
                                                                            {
                                                                                case (true) {
                                                                                vb = this.vbegin();
                                                                                this.read_string(39);
                                                                                vl = this.vend(vb);

                                                                                // exactly one character (codepoint) is a CHAR literal
                                                                                cnt = 0;
                                                                                i = 0;
                                                                                while (i < vl)
                                                                                {
                                                                                    switch (!is_continuation((int)this.arena[vb + i]))
                                                                                    {
                                                                                        case (true) { cnt++; }
                                                                                        default {};
                                                                                    };
                                                                                    i++;
                                                                                };
                                                                                switch (cnt)
                                                                                {
                                                                                    case (1)
                                                                                    {
                                                                                        this.emit(TokenType.CHAR, ln, col, vb, vl, 0);
                                                                                    }
                                                                                    default
                                                                                    {
                                                                                        this.emit(TokenType.STRING_LITERAL, ln, col, vb, vl, 0);
                                                                                    };
                                                                                };
                                                                                continue;
                                                                            }
                                                                                default
                                                                                {
                                                                                    // asm"..." inline assembly
                                                                                    switch (c == 'a' & this.peek(1) == 's' & this.peek(2) == 'm' & this.peek(3) == '"')
                                                                                    {
                                                                                        case (true) {
                                                                                        this.adv(3);
                                                                                        this.emit_text(TokenType.ASM, ln, col, "asm", 3);
                                                                                        this.read_asm_quoted();
                                                                                        continue;
                                                                                    }
                                                                                        default
                                                                                        {
                                                                                            // dict literal opener d{
                                                                                            switch (c == 'd' & this.peek(1) == '{')
                                                                                            {
                                                                                                case (true) {
                                                                                                this.adv(2);
                                                                                                this.emit_text(TokenType.DICT_LITERAL, ln, col, "d{", 2);
                                                                                                continue;
                                                                                            }
                                                                                                default
                                                                                                {
                                                                                                    // numbers
                                                                                                    switch (is_digit(c))
                                                                                                    {
                                                                                                        case (true) {
                                                                                                        this.read_number();
                                                                                                        continue;
                                                                                                    }
                                                                                                        default
                                                                                                        {
                                                                                                            // identifiers and keywords
                                                                                                            switch (is_alpha(c) | c == '_')
                                                                                                            {
                                                                                                                case (true) {
                                                                                                                tt = this.read_identifier();

                                                                                                                switch (tt == TokenType.ASM)
                                                                                                                {
                                                                                                                    case (true) {
                                                                                                                    while (this.cur() == 32 | this.cur() == 9 | this.cur() == 13 | this.cur() == 10)
                                                                                                                    {
                                                                                                                        this.adv(1);
                                                                                                                    };
                                                                                                                    switch (this.cur() == '{')
                                                                                                                    {
                                                                                                                        case (true) {
                                                                                                                        this.read_brace_block(TokenType.ASM_BLOCK);
                                                                                                                        continue;
                                                                                                                    }
                                                                                                                        default {};
                                                                                                                    };
                                                                                                                }
                                                                                                                    default {};
                                                                                                                };

                                                                                                                switch (tt == TokenType.FLUXVM)
                                                                                                                {
                                                                                                                    case (true) {
                                                                                                                    saved_pos = this.position;
                                                                                                                    saved_line = this.line;
                                                                                                                    saved_col = this.column;
                                                                                                                    while (this.cur() == 32 | this.cur() == 9 | this.cur() == 13 | this.cur() == 10)
                                                                                                                    {
                                                                                                                        this.adv(1);
                                                                                                                    };
                                                                                                                    switch (this.cur() == '{')
                                                                                                                    {
                                                                                                                        case (true) {
                                                                                                                        this.read_brace_block(TokenType.FLUXVM_BLOCK);
                                                                                                                        continue;
                                                                                                                    }
                                                                                                                        default {
                                                                                                                        this.position = saved_pos;
                                                                                                                        this.line = saved_line;
                                                                                                                        this.column = saved_col;
                                                                                                                    };
                                                                                                                    };
                                                                                                                }
                                                                                                                    default {};
                                                                                                                };
                                                                                                                continue;
                                                                                                            }
                                                                                                                default
                                                                                                                {
                                                                                                                    // operators and delimiters
                                                                                                                    oplen = this.match_op(@optype);
                                                                                                                    switch (oplen > 0)
                                                                                                                    {
                                                                                                                        case (true) {
                                                                                                                        this.emit_text(optype, ln, col, this.src + this.position, oplen);
                                                                                                                        this.adv(oplen);
                                                                                                                        continue;
                                                                                                                    }
                                                                                                                        default
                                                                                                                        {
                                                                                                                            // unknown character. Non-ASCII outside strings is recorded and skipped.
                                                                                                                            switch (c >= 128)
                                                                                                                            {
                                                                                                                                case (true) {
                                                                                                                                extra = 0;
                                                                                                                                cp = c;
                                                                                                                                switch (c >= 0xF0)
                                                                                                                                {
                                                                                                                                    case (true) { cp = c & 0x07; extra = 3; }
                                                                                                                                    default {
                                                                                                                                        switch (c >= 0xE0)
                                                                                                                                        {
                                                                                                                                            case (true) { cp = c & 0x0F; extra = 2; }
                                                                                                                                            default {
                                                                                                                                                switch (c >= 0xC0)
                                                                                                                                                {
                                                                                                                                                    case (true) { cp = c & 0x1F; extra = 1; }
                                                                                                                                                    default {};
                                                                                                                                                };
                                                                                                                                            };
                                                                                                                                        };
                                                                                                                                    };
                                                                                                                                };

                                                                                                                                wstart = this.position;
                                                                                                                                this.warn_count++;
                                                                                                                                switch (this.warn_count == 1)
                                                                                                                                {
                                                                                                                                    case (true) {
                                                                                                                                    this.warn_line = ln;
                                                                                                                                    this.warn_col = col;
                                                                                                                                }
                                                                                                                                    default {};
                                                                                                                                };

                                                                                                                                this.adv(1);
                                                                                                                                while (extra > 0 & is_continuation(this.cur()))
                                                                                                                                {
                                                                                                                                    cp = (cp << 6) | (this.cur() & 0x3F);
                                                                                                                                    this.adv(1);
                                                                                                                                    extra--;
                                                                                                                                };
                                                                                                                                this.fail(LexError.NON_ASCII, ln, col);
 this.err_cp = cp;
 this.err_start = wstart;
 this.err_nbytes = this.position - wstart;
                                                                                                                            }
                                                                                                                                default {
                                                                                                                                this.adv(1);
                                                                                                                            };
                                                                                                                            };
                                                                                                                        };
                                                                                                                    };
                                                                                                                };
                                                                                                            };
                                                                                                        };
                                                                                                    };
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };

                vb = this.vbegin();
                vl = this.vend(vb);
                this.emit(TokenType.EOF, this.line, this.column, vb, vl, 0);
                this.split_template_closers();
                -> this.err_code == 0;
            };
        };
    };
};

#endif;
