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
            EXPONENT_RANGE
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

        def is_digit(int c) -> bool
        {
            -> c >= '0' & c <= '9';
        };

        def is_alpha(int c) -> bool
        {
            -> (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z');
        };

        def is_ident_char(int c) -> bool
        {
            -> is_alpha(c) | is_digit(c) | c == '_';
        };

        def is_hex_upper(int c) -> bool
        {
            -> is_digit(c) | (c >= 'A' & c <= 'F');
        };

        def is_hex_any(int c) -> bool
        {
            -> is_digit(c) | (c >= 'A' & c <= 'F') | (c >= 'a' & c <= 'f');
        };

        def hex_value(int c) -> int
        {
            if (c >= '0' & c <= '9') { -> c - 48; };
            if (c >= 'A' & c <= 'F') { -> c - 55; };
            -> c - 87;
        };

        def is_base32_digit(int c) -> bool
        {
            -> is_digit(c) | (c >= 'A' & c <= 'V');
        };

        def is_space(int c) -> bool
        {
            -> c == 32 | (c >= 9 & c <= 13) | (c >= 28 & c <= 31);
        };

        def is_continuation(int c) -> bool
        {
            -> c >= 0x80 & c < 0xC0;
        };

        def bytes_eq(byte* a, byte* b, int n) -> bool
        {
            int i;
            while (i < n)
            {
                if (a[i] != b[i]) { -> false; };
                i++;
            };
            -> true;
        };

        // Keyword table. Returns TokenType.IDENTIFIER when s[0..n) is not a keyword.
        def keyword_type(byte* s, int n) -> int
        {
            if (n == 2)
            {
                if (bytes_eq(s, g"as", 2)) { -> TokenType.AS; };
                if (bytes_eq(s, g"do", 2)) { -> TokenType.DO; };
                if (bytes_eq(s, g"if", 2)) { -> TokenType.IF; };
                if (bytes_eq(s, g"in", 2)) { -> TokenType.IN; };
                if (bytes_eq(s, g"is", 2)) { -> TokenType.IS; };
                if (bytes_eq(s, g"or", 2)) { -> TokenType.OR; };
            };
            if (n == 3)
            {
                if (bytes_eq(s, g"and", 3)) { -> TokenType.AND; };
                if (bytes_eq(s, g"asm", 3)) { -> TokenType.ASM; };
                if (bytes_eq(s, g"def", 3)) { -> TokenType.DEF; };
                if (bytes_eq(s, g"for", 3)) { -> TokenType.FOR; };
                if (bytes_eq(s, g"has", 3)) { -> TokenType.HAS; };
                if (bytes_eq(s, g"int", 3)) { -> TokenType.SINT; };
                if (bytes_eq(s, g"not", 3)) { -> TokenType.NOT; };
                if (bytes_eq(s, g"try", 3)) { -> TokenType.TRY; };
                if (bytes_eq(s, g"xor", 3)) { -> TokenType.XOR; };
            };
            if (n == 4)
            {
                if (bytes_eq(s, g"auto", 4)) { -> TokenType.AUTO; };
                if (bytes_eq(s, g"bool", 4)) { -> TokenType.BOOL_KW; };
                if (bytes_eq(s, g"byte", 4)) { -> TokenType.BYTE; };
                if (bytes_eq(s, g"case", 4)) { -> TokenType.CASE; };
                if (bytes_eq(s, g"char", 4)) { -> TokenType.CHAR; };
                if (bytes_eq(s, g"data", 4)) { -> TokenType.DATA; };
                if (bytes_eq(s, g"dict", 4)) { -> TokenType.DICT; };
                if (bytes_eq(s, g"elif", 4)) { -> TokenType.ELIF; };
                if (bytes_eq(s, g"else", 4)) { -> TokenType.ELSE; };
                if (bytes_eq(s, g"enum", 4)) { -> TokenType.ENUM; };
                if (bytes_eq(s, g"from", 4)) { -> TokenType.FROM; };
                if (bytes_eq(s, g"goto", 4)) { -> TokenType.GOTO; };
                if (bytes_eq(s, g"heap", 4)) { -> TokenType.HEAP; };
                if (bytes_eq(s, g"jump", 4)) { -> TokenType.JUMP; };
                if (bytes_eq(s, g"long", 4)) { -> TokenType.SLONG; };
                if (bytes_eq(s, g"this", 4)) { -> TokenType.THIS; };
                if (bytes_eq(s, g"true", 4)) { -> TokenType.TRUE; };
                if (bytes_eq(s, g"uint", 4)) { -> TokenType.UINT; };
                if (bytes_eq(s, g"void", 4)) { -> TokenType.VOID; };
            };
            if (n == 5)
            {
                if (bytes_eq(s, g"break", 5)) { -> TokenType.BREAK; };
                if (bytes_eq(s, g"catch", 5)) { -> TokenType.CATCH; };
                if (bytes_eq(s, g"compt", 5)) { -> TokenType.COMPT; };
                if (bytes_eq(s, g"const", 5)) { -> TokenType.CONST; };
                if (bytes_eq(s, g"defer", 5)) { -> TokenType.DEFER; };
                if (bytes_eq(s, g"macro", 5)) { -> TokenType.MACRO; };
                if (bytes_eq(s, g"false", 5)) { -> TokenType.FALSE; };
                if (bytes_eq(s, g"float", 5)) { -> TokenType.FLOAT_KW; };
                if (bytes_eq(s, g"label", 5)) { -> TokenType.LABEL; };
                if (bytes_eq(s, g"local", 5)) { -> TokenType.LOCAL; };
                if (bytes_eq(s, g"ulong", 5)) { -> TokenType.ULONG; };
                if (bytes_eq(s, g"stack", 5)) { -> TokenType.STACK; };
                if (bytes_eq(s, g"throw", 5)) { -> TokenType.THROW; };
                if (bytes_eq(s, g"trait", 5)) { -> TokenType.TRAIT; };
                if (bytes_eq(s, g"union", 5)) { -> TokenType.UNION; };
                if (bytes_eq(s, g"using", 5)) { -> TokenType.USING; };
                if (bytes_eq(s, g"while", 5)) { -> TokenType.WHILE; };
                if (bytes_eq(s, g"cdecl", 5)) { -> TokenType.CDECL; };
            };
            if (n == 6)
            {
                if (bytes_eq(s, g"assert", 6)) { -> TokenType.ASSERT; };
                if (bytes_eq(s, g"double", 6)) { -> TokenType.DOUBLE_KW; };
                if (bytes_eq(s, g"effect", 6)) { -> TokenType.EFFECT; };
                if (bytes_eq(s, g"escape", 6)) { -> TokenType.ESCAPE_KW; };
                if (bytes_eq(s, g"export", 6)) { -> TokenType.EXPORT; };
                if (bytes_eq(s, g"extern", 6)) { -> TokenType.EXTERN; };
                if (bytes_eq(s, g"global", 6)) { -> TokenType.GLOBAL; };
                if (bytes_eq(s, g"inline", 6)) { -> TokenType.INLINE; };
                if (bytes_eq(s, g"noinit", 6)) { -> TokenType.NO_INIT; };
                if (bytes_eq(s, g"object", 6)) { -> TokenType.OBJECT; };
                if (bytes_eq(s, g"public", 6)) { -> TokenType.PUBLIC; };
                if (bytes_eq(s, g"return", 6)) { -> TokenType.RETURN; };
                if (bytes_eq(s, g"signed", 6)) { -> TokenType.SIGNED; };
                if (bytes_eq(s, g"sizeof", 6)) { -> TokenType.SIZEOF; };
                if (bytes_eq(s, g"struct", 6)) { -> TokenType.STRUCT; };
                if (bytes_eq(s, g"switch", 6)) { -> TokenType.SWITCH; };
                if (bytes_eq(s, g"typeof", 6)) { -> TokenType.TYPEOF; };
                if (bytes_eq(s, g"vector", 6)) { -> TokenType.VECTOR; };
                if (bytes_eq(s, g"fluxvm", 6)) { -> TokenType.FLUXVM; };
            };
            if (n == 7)
            {
                if (bytes_eq(s, g"alignof", 7)) { -> TokenType.ALIGNOF; };
                if (bytes_eq(s, g"default", 7)) { -> TokenType.DEFAULT; };
                if (bytes_eq(s, g"private", 7)) { -> TokenType.PRIVATE; };
                if (bytes_eq(s, g"stdcall", 7)) { -> TokenType.STDCALL; };
            };
            if (n == 8)
            {
                if (bytes_eq(s, g"continue", 8)) { -> TokenType.CONTINUE; };
                if (bytes_eq(s, g"contract", 8)) { -> TokenType.CONTRACT; };
                if (bytes_eq(s, g"endianof", 8)) { -> TokenType.ENDIANOF; };
                if (bytes_eq(s, g"fastnode", 8)) { -> TokenType.FASTNODE; };
                if (bytes_eq(s, g"noreturn", 8)) { -> TokenType.NORET; };
                if (bytes_eq(s, g"operator", 8)) { -> TokenType.OPERATOR; };
                if (bytes_eq(s, g"register", 8)) { -> TokenType.REGISTER; };
                if (bytes_eq(s, g"singinit", 8)) { -> TokenType.SINGINIT; };
                if (bytes_eq(s, g"unsigned", 8)) { -> TokenType.UNSIGNED; };
                if (bytes_eq(s, g"volatile", 8)) { -> TokenType.VOLATILE; };
                if (bytes_eq(s, g"fastcall", 8)) { -> TokenType.FASTCALL; };
                if (bytes_eq(s, g"thiscall", 8)) { -> TokenType.THISCALL; };
                if (bytes_eq(s, g"comptime", 8)) { -> TokenType.COMPTIME; };
                if (bytes_eq(s, g"emitflux", 8)) { -> TokenType.EMITFLUX; };
            };
            if (n == 9)
            {
                if (bytes_eq(s, g"deprecate", 9)) { -> TokenType.DEPRECATE; };
                if (bytes_eq(s, g"interface", 9)) { -> TokenType.INTERFACE; };
                if (bytes_eq(s, g"namespace", 9)) { -> TokenType.NAMESPACE; };
            };
            if (n == 10)
            {
                if (bytes_eq(s, g"constraint", 10)) { -> TokenType.CONSTRAINT; };
                if (bytes_eq(s, g"vectorcall", 10)) { -> TokenType.VECTORCALL; };
            };
            -> TokenType.IDENTIFIER;
        };

        def error_message(int code) -> byte*
        {
            switch (code)
            {
                case (LexError.FSTRING_UNTERMINATED) { -> g"unterminated f-string interpolation, } expected\0"; }
                case (LexError.ALLOC_FAILED)         { -> g"lexer allocation failed\0"; }
                case (LexError.EXPONENT_RANGE)       { -> g"numeric literal exponent out of range\0"; }
                default                              { -> g"no error\0"; };
            };
        };

        def token_name(int t) -> byte*
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

            def __init(byte* source, int len) -> this
            {
                this.src = source;
                this.length = len;
                this.position = 0;
                this.line = 1;
                this.column = 1;
                this.count = 0;
                this.err_code = 0;

                // Skip a UTF-8 BOM if present
                if (len >= 3)
                {
                    if (source[0] == 0xEF & source[1] == 0xBB & source[2] == 0xBF)
                    {
                        this.position = 3;
                    };
                };

                // Every token consumes at least one source byte, plus EOF.
                this.cap = len + 2;
                this.tokens = (Token*)fmalloc((u64)this.cap * (u64)(sizeof(Token) / 8));

                this.arena_cap = len * 2 + 64;
                this.arena_len = 0;
                this.arena = (byte*)fmalloc((u64)this.arena_cap);

                if (this.tokens == (Token*)0 | this.arena == (byte*)0)
                {
                    this.err_code = LexError.ALLOC_FAILED;
                    this.err_line = 1;
                    this.err_col = 1;
                };
                -> this;
            };

            def __expr() -> Lexer*
            {
                -> this;
            };

            def __exit() -> void
            {
                if (this.tokens != (Token*)0) { ffree((byte*)this.tokens); };
                if (this.arena != (byte*)0) { ffree(this.arena); };
                this.tokens = (Token*)0;
                this.arena = (byte*)0;
                return;
            };

            // ===== SOURCE CURSOR =====

            // Current byte as 0..255, or -1 at end of input
            def cur() -> int
            {
                if (this.position >= this.length) { -> -1; };
                -> (int)this.src[this.position];
            };

            def peek(int offset) -> int
            {
                int p = this.position + offset;
                if (p >= this.length) { -> -1; };
                -> (int)this.src[p];
            };

            // Mirrors FluxLexer.advance. Newline resets the column, a single
            // tab advances to 4 columns, UTF-8 continuation bytes do not add a
            // column so columns count characters like the Python lexer does.
            def adv(int n) -> void
            {
                int c;
                if (this.position < this.length)
                {
                    c = (int)this.src[this.position];
                    if (c == 10)
                    {
                        this.line++;
                        this.column = 1;
                    }
                    elif (n == 1 & c == 9)
                    {
                        this.column += 4;
                    }
                    elif (n == 1 & is_continuation(c))
                    {
                        this.column += 0;
                    }
                    else
                    {
                        this.column += n;
                    };
                }
                else
                {
                    this.column += n;
                };
                this.position += n;
                return;
            };

            def skip_whitespace() -> bool
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
            def match(byte* lit, int n) -> bool
            {
                int i;
                while (i < n)
                {
                    if (this.position + i >= this.length) { -> false; };
                    if (this.src[this.position + i] != lit[i]) { -> false; };
                    i++;
                };
                -> true;
            };

            // ===== ERRORS =====

            def fail(int code, int ln, int col) -> void
            {
                if (this.err_code == 0)
                {
                    this.err_code = code;
                    this.err_line = ln;
                    this.err_col = col;
                };
                return;
            };

            // ===== VALUE ARENA =====

            def grow() -> void
            {
                int new_cap = this.arena_cap * 2;
                u64 np = frealloc((u64)this.arena, (size_t)new_cap);
                if (np == (u64)0)
                {
                    this.fail(LexError.ALLOC_FAILED, this.line, this.column);
                    return;
                };
                this.arena = (byte*)np;
                this.arena_cap = new_cap;
                return;
            };

            def vbegin() -> int
            {
                -> this.arena_len;
            };

            def vput(int b) -> void
            {
                if (this.arena_len + 2 > this.arena_cap) { this.grow(); };
                if (this.err_code != 0) { return; };
                this.arena[this.arena_len] = (byte)b;
                this.arena_len++;
                return;
            };

            // UTF-8 encode a codepoint below 0x800
            def vput_cp(int v) -> void
            {
                if (v < 128)
                {
                    this.vput(v);
                }
                else
                {
                    this.vput(0xC0 | (v >> 6));
                    this.vput(0x80 | (v & 0x3F));
                };
                return;
            };

            // Null terminate the value that started at `start`. Returns its length.
            def vend(int start) -> int
            {
                this.vput(0);
                -> this.arena_len - 1 - start;
            };

            def emit(int tt, int ln, int col, int voff, int vlen, int numeric) -> void
            {
                if (this.err_code != 0) { return; };
                if (this.count >= this.cap)
                {
                    this.fail(LexError.ALLOC_FAILED, ln, col);
                    return;
                };
                this.tokens[this.count].type = tt;
                this.tokens[this.count].line = ln;
                this.tokens[this.count].column = col;
                this.tokens[this.count].voff = voff;
                this.tokens[this.count].vlen = vlen;
                this.tokens[this.count].numeric_char = numeric;
                this.count++;
                return;
            };

            def emit_text(int tt, int ln, int col, byte* s, int n) -> void
            {
                int vb = this.vbegin();
                int i;
                while (i < n)
                {
                    this.vput((int)s[i]);
                    i++;
                };
                int vl = this.vend(vb);
                this.emit(tt, ln, col, vb, vl, 0);
                return;
            };

            def token_value(int i) -> byte*
            {
                -> this.arena + this.tokens[i].voff;
            };

            // ===== BLOCKS =====

            // asm"..." form: current character is the opening quote
            def read_asm_quoted() -> void
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
                if (this.cur() == '"' & this.peek(1) == '"') { this.adv(2); };
                int vl = this.vend(vb);
                this.emit(TokenType.ASM_BLOCK, ln, col, vb, vl, 0);
                return;
            };

            // { ... } block after the asm or fluxvm keyword. Content is raw
            // text with nested braces balanced, outer whitespace stripped.
            def read_brace_block(int tt) -> void
            {
                int ln = this.line;
                int col = this.column;
                int c;
                while (this.cur() == 32 | this.cur() == 9 | this.cur() == 13 | this.cur() == 10)
                {
                    this.adv(1);
                };
                if (this.cur() != '{') { return; };
                this.adv(1);

                int depth = 1;
                int vb = this.vbegin();
                while (this.cur() != -1 & depth > 0)
                {
                    c = this.cur();
                    if (c == '{') { depth++; }
                    elif (c == '}') { depth--; };
                    if (depth > 0) { this.vput(c); };
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
                this.emit(tt, ln, col, vb, vl, 0);
                return;
            };

            // ===== STRINGS =====

            // Reads a quoted string with escape processing into the arena.
            // The current character is the opening quote.
            def read_string(int quote) -> void
            {
                int e, hv, hn;
                bool stop = false;
                bool skip;
                this.adv(1);
                while (!stop & this.cur() != -1 & this.cur() != quote)
                {
                    skip = false;
                    if (this.cur() == '\\')
                    {
                        this.adv(1);
                        e = this.cur();
                        if (e == -1)
                        {
                            stop = true;
                        }
                        elif (e == 'n') { this.vput(10); }
                        elif (e == 't') { this.vput(9); }
                        elif (e == 'r') { this.vput(13); }
                        elif (e == '0') { this.vput(0); }
                        elif (e == '\\') { this.vput(92); }
                        elif (e == '"') { this.vput(34); }
                        elif (e == 'x')
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
                            if (hn > 0)
                            {
                                this.vput_cp(hv);
                                skip = true;
                            };
                        }
                        else
                        {
                            this.vput(e);
                        };
                    }
                    else
                    {
                        this.vput(this.cur());
                    };
                    if (!stop & !skip) { this.adv(1); };
                };
                if (this.cur() == quote) { this.adv(1); };
                return;
            };

            // f-string body. Embedded { ... } expressions are copied verbatim.
            // Returns false (and sets the error) on an unterminated interpolation.
            def read_f_string_body() -> bool
            {
                int e, depth;
                bool stop = false;
                this.adv(1);
                while (!stop & this.cur() != -1 & this.cur() != '"')
                {
                    if (this.cur() == '{')
                    {
                        this.vput('{');
                        this.adv(1);
                        depth = 1;
                        while (this.cur() != -1 & depth > 0)
                        {
                            if (this.cur() == '"')
                            {
                                this.fail(LexError.FSTRING_UNTERMINATED, this.line, this.column);
                                -> false;
                            };
                            if (this.cur() == '{') { depth++; }
                            elif (this.cur() == '}') { depth--; };
                            this.vput(this.cur());
                            this.adv(1);
                        };
                    }
                    elif (this.cur() == '\\')
                    {
                        this.adv(1);
                        e = this.cur();
                        if (e == -1)
                        {
                            stop = true;
                        }
                        else
                        {
                            if (e == 'n') { this.vput(10); }
                            elif (e == 't') { this.vput(9); }
                            elif (e == 'r') { this.vput(13); }
                            elif (e == '0') { this.vput(0); }
                            elif (e == '\\') { this.vput(92); }
                            elif (e == '"') { this.vput(34); }
                            else { this.vput(e); };
                            this.adv(1);
                        };
                    }
                    else
                    {
                        this.vput(this.cur());
                        this.adv(1);
                    };
                };
                if (this.cur() == '"') { this.adv(1); };
                -> true;
            };

            // i"name":{ expr; ... }  The leading i is already consumed.
            def read_i_string() -> void
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
                if (this.cur() == ':') { this.adv(1); };
                this.skip_whitespace();
                if (this.cur() == '{')
                {
                    this.vput(':');
                    this.vput('{');
                    this.adv(1);
                    depth = 1;
                    while (this.cur() != -1 & depth > 0)
                    {
                        if (this.cur() == '{') { depth++; }
                        elif (this.cur() == '}') { depth--; };
                        this.vput(this.cur());
                        this.adv(1);
                    };
                };
                int vl = this.vend(vb);
                this.emit(TokenType.I_STRING, ln, col, vb, vl, 0);
                return;
            };

            // ===== NUMBERS =====

            // Suffix handling shared by 0x / 0o / 0d / 0b literals
            def finish_prefixed(int ln, int col, int vb, bool allow_byte) -> void
            {
                int tt = TokenType.SINT_LITERAL;
                int c = this.cur();
                if (c == 'u')
                {
                    this.adv(1);
                    if (this.cur() == 'l')
                    {
                        this.adv(1);
                        tt = TokenType.ULONG_LITERAL;
                    }
                    else
                    {
                        tt = TokenType.UINT_LITERAL;
                    };
                }
                elif (c == 'l')
                {
                    this.adv(1);
                    tt = TokenType.SLONG_LITERAL;
                }
                elif (allow_byte & c == 'b')
                {
                    this.adv(1);
                    tt = TokenType.BYTE_LITERAL;
                };
                int vl = this.vend(vb);
                this.emit(tt, ln, col, vb, vl, 0);
                return;
            };

            def digit_at(int vb, int int_len, int n, int i) -> int
            {
                if (i >= n) { -> '0'; };
                if (i < int_len) { -> (int)this.arena[vb + i]; };
                -> (int)this.arena[vb + i + 1];
            };

            // Mantissa digits are already in the arena at vb (integer part,
            // optional '.', fraction). The current character is the 'e'/'E'.
            // The value is rewritten as an exact plain decimal string.
            def read_scientific(int ln, int col, int vb, int int_len, bool had_dot) -> void
            {
                this.adv(1);
                int sign = 1;
                if (this.cur() == '+' | this.cur() == '-')
                {
                    if (this.cur() == '-') { sign = -1; };
                    this.adv(1);
                };
                int exponent = 0;
                bool too_big = false;
                while (is_digit(this.cur()))
                {
                    if (exponent > 1000000) { too_big = true; }
                    else { exponent = exponent * 10 + (this.cur() - 48); };
                    this.adv(1);
                };
                if (too_big | exponent > 1000000)
                {
                    this.fail(LexError.EXPONENT_RANGE, ln, col);
                    return;
                };
                exponent = exponent * sign;

                int n = this.arena_len - vb;
                if (had_dot) { n = n - 1; };
                int point = int_len + exponent;
                int out_start = this.arena_len;

                // integer part
                int ipart = 0;
                if (point > 0) { ipart = point; };
                int j, j0 = -1;
                while (j < ipart)
                {
                    if (this.digit_at(vb, int_len, n, j) != '0')
                    {
                        j0 = j;
                        break;
                    };
                    j++;
                };
                if (j0 == -1)
                {
                    this.vput('0');
                }
                else
                {
                    j = j0;
                    while (j < ipart)
                    {
                        this.vput(this.digit_at(vb, int_len, n, j));
                        j++;
                    };
                };

                // fractional part
                int z = 0;
                if (point < 0) { z = 0 - point; };
                int fstart = 0;
                if (point > 0) { fstart = point; };
                int flen = 0;
                if (n > fstart) { flen = z + (n - fstart); };

                int lt, m = flen, idx, dch;
                while (m > 0)
                {
                    idx = m - 1;
                    if (idx < z) { dch = '0'; }
                    else { dch = this.digit_at(vb, int_len, n, fstart + (idx - z)); };
                    if (dch != '0')
                    {
                        lt = m;
                        break;
                    };
                    m--;
                };
                if (lt > 0)
                {
                    this.vput('.');
                    m = 0;
                    while (m < lt)
                    {
                        if (m < z) { dch = '0'; }
                        else { dch = this.digit_at(vb, int_len, n, fstart + (m - z)); };
                        this.vput(dch);
                        m++;
                    };
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
                if (this.cur() == 'f')
                {
                    this.adv(1);
                    tt = TokenType.FLOAT;
                }
                elif (this.cur() == 'd')
                {
                    this.adv(1);
                    tt = TokenType.DOUBLE;
                }
                else
                {
                    int abs_exp = exponent;
                    if (abs_exp < 0) { abs_exp = 0 - abs_exp; };
                    if (abs_exp <= 5) { tt = TokenType.FLOAT; }
                    else { tt = TokenType.DOUBLE; };
                };
                this.emit(tt, ln, col, vb, vl, 0);
                return;
            };

            def read_number() -> void
            {
                int ln = this.line;
                int col = this.column;
                int vb = this.vbegin();
                int c, vl;
                bool is_float, is_double;

                if (this.cur() == '0')
                {
                    this.vput('0');
                    this.adv(1);
                    c = this.cur();

                    if (c == 'd' | c == 'D')
                    {
                        this.vput(c);
                        this.adv(1);
                        while (is_base32_digit(this.cur()))
                        {
                            this.vput(this.cur());
                            this.adv(1);
                        };
                        this.finish_prefixed(ln, col, vb, true);
                        return;
                    };

                    if (c == 'x' | c == 'X')
                    {
                        this.vput(c);
                        this.adv(1);
                        while (is_hex_upper(this.cur()))
                        {
                            this.vput(this.cur());
                            this.adv(1);
                        };
                        this.finish_prefixed(ln, col, vb, true);
                        return;
                    };

                    if (c == 'o' | c == 'O')
                    {
                        this.vput(c);
                        this.adv(1);
                        while (this.cur() >= '0' & this.cur() <= '7')
                        {
                            this.vput(this.cur());
                            this.adv(1);
                        };
                        this.finish_prefixed(ln, col, vb, true);
                        return;
                    };

                    if (c == 'b' | c == 'B')
                    {
                        this.vput(c);
                        this.adv(1);
                        while (this.cur() == '0' | this.cur() == '1')
                        {
                            this.vput(this.cur());
                            this.adv(1);
                        };
                        // `0b` with no digits is the byte-suffix form of 0
                        if (c == 'b' & this.arena_len - vb == 2)
                        {
                            this.arena_len = vb;
                            this.vput('0');
                            vl = this.vend(vb);
                            this.emit(TokenType.BYTE_LITERAL, ln, col, vb, vl, 0);
                            return;
                        };
                        this.finish_prefixed(ln, col, vb, false);
                        return;
                    };
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
                if (this.cur() == '.' & is_digit(this.peek(1)))
                {
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
                };

                // scientific notation: e/E, optional sign, digits
                c = this.cur();
                if (c == 'e' | c == 'E')
                {
                    int n1 = this.peek(1);
                    int n2 = this.peek(2);
                    bool exp_valid = false;
                    if (is_digit(n1)) { exp_valid = true; }
                    elif ((n1 == '+' | n1 == '-') & is_digit(n2)) { exp_valid = true; };
                    if (exp_valid)
                    {
                        this.read_scientific(ln, col, vb, int_len, had_dot);
                        return;
                    };
                };

                // suffixes
                int tt = TokenType.SINT_LITERAL;
                if (this.cur() == 'f')
                {
                    tt = TokenType.FLOAT;
                    is_float = true;
                    this.adv(1);
                };
                c = this.cur();
                if (c == 'd')
                {
                    tt = TokenType.DOUBLE;
                    is_double = true;
                    this.adv(1);
                }
                elif (!is_float & c == 'u' & this.peek(1) == 'l')
                {
                    tt = TokenType.ULONG_LITERAL;
                    this.adv(2);
                }
                elif (!is_float & c == 'u')
                {
                    tt = TokenType.UINT_LITERAL;
                    this.adv(1);
                }
                elif (!is_float & c == 'l')
                {
                    tt = TokenType.SLONG_LITERAL;
                    this.adv(1);
                }
                elif (!is_float & c == 'b')
                {
                    tt = TokenType.BYTE_LITERAL;
                    this.adv(1);
                }
                elif (!is_float & c == 'c')
                {
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
                    this.emit(TokenType.CHAR, ln, col, vb, vl, 1);
                    return;
                };

                if (is_float & dc <= 5) { tt = TokenType.FLOAT; };
                if (is_double | dc > 5) { tt = TokenType.DOUBLE; };

                vl = this.vend(vb);
                this.emit(tt, ln, col, vb, vl, 0);
                return;
            };

            // ===== IDENTIFIERS =====

            // Reads an identifier or keyword, emits it, returns its token type
            def read_identifier() -> int
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
            def match_op(int* ttype) -> int
            {
                int avail = this.length - this.position;
            if (avail >= 6)
            {
                if (this.match(g"`^|!&=", 6)) { *ttype = TokenType.BITXNAND_ASSIGN; -> 6; };
                if (this.match(g"`^|!|=", 6)) { *ttype = TokenType.BITXNOR_ASSIGN; -> 6; };
            };
            if (avail >= 5)
            {
                if (this.match(g"`^|!&", 5)) { *ttype = TokenType.BITXNAND; -> 5; };
                if (this.match(g"`^|!|", 5)) { *ttype = TokenType.BITXNOR; -> 5; };
                if (this.match(g"`^|!=", 5)) { *ttype = TokenType.BITXNOT_ASSIGN; -> 5; };
            };
            if (avail >= 4)
            {
                if (this.match(g"`^|!", 4)) { *ttype = TokenType.BITXNOT; -> 4; };
                if (this.match(g"`!&=", 4)) { *ttype = TokenType.BITNAND_ASSIGN; -> 4; };
                if (this.match(g"`!|=", 4)) { *ttype = TokenType.BITNOR_ASSIGN; -> 4; };
                if (this.match(g"`^|=", 4)) { *ttype = TokenType.BITXOR_ASSIGN; -> 4; };
            };
            if (avail >= 3)
            {
                if (this.match(g"<<=", 3)) { *ttype = TokenType.BITSHIFT_LEFT_ASSIGN; -> 3; };
                if (this.match(g">>=", 3)) { *ttype = TokenType.BITSHIFT_RIGHT_ASSIGN; -> 3; };
                if (this.match(g"^|=", 3)) { *ttype = TokenType.XOR_ASSIGN; -> 3; };
                if (this.match(g"{}*", 3)) { *ttype = TokenType.FUNCTION_POINTER; -> 3; };
                if (this.match(g"(@)", 3)) { *ttype = TokenType.ADDRESS_CAST; -> 3; };
                if (this.match(g"...", 3)) { *ttype = TokenType.ELLIPSIS; -> 3; };
                if (this.match(g"`!&", 3)) { *ttype = TokenType.BITNAND_OP; -> 3; };
                if (this.match(g"`!|", 3)) { *ttype = TokenType.BITNOR_OP; -> 3; };
                if (this.match(g"`&=", 3)) { *ttype = TokenType.BITAND_ASSIGN; -> 3; };
                if (this.match(g"`|=", 3)) { *ttype = TokenType.BITOR_ASSIGN; -> 3; };
                if (this.match(g"`^|", 3)) { *ttype = TokenType.BITXOR_OP; -> 3; };
            };
            if (avail >= 2)
            {
                if (this.match(g"==", 2)) { *ttype = TokenType.EQUAL; -> 2; };
                if (this.match(g"!=", 2)) { *ttype = TokenType.NOT_EQUAL; -> 2; };
                if (this.match(g"<=", 2)) { *ttype = TokenType.LESS_EQUAL; -> 2; };
                if (this.match(g">=", 2)) { *ttype = TokenType.GREATER_EQUAL; -> 2; };
                if (this.match(g"<<", 2)) { *ttype = TokenType.BITSHIFT_LEFT; -> 2; };
                if (this.match(g">>", 2)) { *ttype = TokenType.BITSHIFT_RIGHT; -> 2; };
                if (this.match(g"++", 2)) { *ttype = TokenType.INCREMENT; -> 2; };
                if (this.match(g"--", 2)) { *ttype = TokenType.DECREMENT; -> 2; };
                if (this.match(g"+=", 2)) { *ttype = TokenType.PLUS_ASSIGN; -> 2; };
                if (this.match(g"-=", 2)) { *ttype = TokenType.MINUS_ASSIGN; -> 2; };
                if (this.match(g"*=", 2)) { *ttype = TokenType.MULTIPLY_ASSIGN; -> 2; };
                if (this.match(g"/=", 2)) { *ttype = TokenType.DIVIDE_ASSIGN; -> 2; };
                if (this.match(g"%=", 2)) { *ttype = TokenType.MODULO_ASSIGN; -> 2; };
                if (this.match(g"^=", 2)) { *ttype = TokenType.EXPONENT_ASSIGN; -> 2; };
                if (this.match(g"&=", 2)) { *ttype = TokenType.AND_ASSIGN; -> 2; };
                if (this.match(g"|=", 2)) { *ttype = TokenType.OR_ASSIGN; -> 2; };
                if (this.match(g"!&", 2)) { *ttype = TokenType.NAND_OP; -> 2; };
                if (this.match(g"!|", 2)) { *ttype = TokenType.NOR_OP; -> 2; };
                if (this.match(g"^|", 2)) { *ttype = TokenType.XOR_OP; -> 2; };
                if (this.match(g"!!", 2)) { *ttype = TokenType.NO_MANGLE; -> 2; };
                if (this.match(g"??", 2)) { *ttype = TokenType.NULL_COALESCE; -> 2; };
                if (this.match(g"->", 2)) { *ttype = TokenType.RETURN_ARROW; -> 2; };
                if (this.match(g"<-", 2)) { *ttype = TokenType.CHAIN_ARROW; -> 2; };
                if (this.match(g"<~", 2)) { *ttype = TokenType.RECURSE_ARROW; -> 2; };
                if (this.match(g"..", 2)) { *ttype = TokenType.RANGE; -> 2; };
                if (this.match(g"::", 2)) { *ttype = TokenType.SCOPE; -> 2; };
                if (this.match(g"?=", 2)) { *ttype = TokenType.TERNARY_ASSIGN; -> 2; };
                if (this.match(g"!?", 2)) { *ttype = TokenType.NOT_NULL; -> 2; };
                if (this.match(g"@=", 2)) { *ttype = TokenType.ADDRESS_ASSIGN; -> 2; };
                if (this.match(g"``", 2)) { *ttype = TokenType.BITSLICE; -> 2; };
                if (this.match(g"~$", 2)) { *ttype = TokenType.CODIFY; -> 2; };
                if (this.match(g"#\"", 2)) { *ttype = TokenType.DITTO; -> 2; };
                if (this.match(g"d{", 2)) { *ttype = TokenType.DICT_LITERAL; -> 2; };
                if (this.match(g"`!", 2)) { *ttype = TokenType.BITNOT_OP; -> 2; };
                if (this.match(g"`&", 2)) { *ttype = TokenType.BITAND_OP; -> 2; };
                if (this.match(g"`|", 2)) { *ttype = TokenType.BITOR_OP; -> 2; };
            };
            // single character tokens
            if (this.match(g"+", 1)) { *ttype = TokenType.PLUS; -> 1; };
            if (this.match(g"-", 1)) { *ttype = TokenType.MINUS; -> 1; };
            if (this.match(g"*", 1)) { *ttype = TokenType.MULTIPLY; -> 1; };
            if (this.match(g"/", 1)) { *ttype = TokenType.DIVIDE; -> 1; };
            if (this.match(g"%", 1)) { *ttype = TokenType.MODULO; -> 1; };
            if (this.match(g"^", 1)) { *ttype = TokenType.EXPONENT; -> 1; };
            if (this.match(g"<", 1)) { *ttype = TokenType.LESS_THAN; -> 1; };
            if (this.match(g">", 1)) { *ttype = TokenType.GREATER_THAN; -> 1; };
            if (this.match(g"&", 1)) { *ttype = TokenType.LOGICAL_AND; -> 1; };
            if (this.match(g"|", 1)) { *ttype = TokenType.LOGICAL_OR; -> 1; };
            if (this.match(g"!", 1)) { *ttype = TokenType.NOT; -> 1; };
            if (this.match(g"@", 1)) { *ttype = TokenType.ADDRESS_OF; -> 1; };
            if (this.match(g"=", 1)) { *ttype = TokenType.ASSIGN; -> 1; };
            if (this.match(g"?", 1)) { *ttype = TokenType.QUESTION; -> 1; };
            if (this.match(g":", 1)) { *ttype = TokenType.COLON; -> 1; };
            if (this.match(g"(", 1)) { *ttype = TokenType.LEFT_PAREN; -> 1; };
            if (this.match(g")", 1)) { *ttype = TokenType.RIGHT_PAREN; -> 1; };
            if (this.match(g"[", 1)) { *ttype = TokenType.LEFT_BRACKET; -> 1; };
            if (this.match(g"]", 1)) { *ttype = TokenType.RIGHT_BRACKET; -> 1; };
            if (this.match(g"{", 1)) { *ttype = TokenType.LEFT_BRACE; -> 1; };
            if (this.match(g"}", 1)) { *ttype = TokenType.RIGHT_BRACE; -> 1; };
            if (this.match(g";", 1)) { *ttype = TokenType.SEMICOLON; -> 1; };
            if (this.match(g",", 1)) { *ttype = TokenType.COMMA; -> 1; };
            if (this.match(g".", 1)) { *ttype = TokenType.DOT; -> 1; };
            if (this.match(g"~", 1)) { *ttype = TokenType.TIE; -> 1; };
            if (this.match(g"$", 1)) { *ttype = TokenType.STRINGIFY; -> 1; };
            if (this.match(g"\\", 1)) { *ttype = TokenType.BACKSLASH; -> 1; };
            if (this.match(g"`", 1)) { *ttype = TokenType.BACKTICK; -> 1; };
            if (this.match(g"#", 1)) { *ttype = TokenType.TAG; -> 1; };
                -> 0;
            };

            // ===== MAIN LOOP =====

            // Tokenizes the whole source. Returns false on error, in which case
            // err_code / err_line / err_col describe it.
            def tokenize() -> bool
            {
                int c, ln, col, tt, vb, vl, cnt, i, oplen, optype, cp, extra;
                int saved_pos, saved_line, saved_col;

                while (this.position < this.length)
                {
                    if (this.err_code != 0) { -> false; };

                    if (this.skip_whitespace()) { continue; };

                    c = this.cur();
                    if (c == -1) { break; };
                    ln = this.line;
                    col = this.column;

                    // i-string. Its token position is taken after the leading i.
                    if (c == 'i' & this.peek(1) == '"')
                    {
                        this.adv(1);
                        this.read_i_string();
                        continue;
                    };

                    // f-string
                    if (c == 'f' & this.peek(1) == '"')
                    {
                        this.adv(1);
                        vb = this.vbegin();
                        this.vput('f');
                        this.vput('"');
                        if (!this.read_f_string_body()) { -> false; };
                        this.vput('"');
                        vl = this.vend(vb);
                        this.emit(TokenType.F_STRING, ln, col, vb, vl, 0);
                        continue;
                    };

                    // g-string
                    if (c == 'g' & this.peek(1) == '"')
                    {
                        this.adv(1);
                        vb = this.vbegin();
                        this.read_string('"');
                        vl = this.vend(vb);
                        this.emit(TokenType.G_STRING, ln, col, vb, vl, 0);
                        continue;
                    };

                    // string and char literals
                    if (c == '"')
                    {
                        vb = this.vbegin();
                        this.read_string('"');
                        vl = this.vend(vb);
                        this.emit(TokenType.STRING_LITERAL, ln, col, vb, vl, 0);
                        continue;
                    };

                    if (c == 39)
                    {
                        vb = this.vbegin();
                        this.read_string(39);
                        vl = this.vend(vb);

                        // exactly one character (codepoint) is a CHAR literal
                        cnt = 0;
                        i = 0;
                        while (i < vl)
                        {
                            if (!is_continuation((int)this.arena[vb + i])) { cnt++; };
                            i++;
                        };
                        if (cnt == 1)
                        {
                            this.emit(TokenType.CHAR, ln, col, vb, vl, 0);
                        }
                        else
                        {
                            this.emit(TokenType.STRING_LITERAL, ln, col, vb, vl, 0);
                        };
                        continue;
                    };

                    // asm"..." inline assembly
                    if (c == 'a' & this.peek(1) == 's' & this.peek(2) == 'm' & this.peek(3) == '"')
                    {
                        this.adv(3);
                        this.emit_text(TokenType.ASM, ln, col, "asm", 3);
                        this.read_asm_quoted();
                        continue;
                    };

                    // dict literal opener d{
                    if (c == 'd' & this.peek(1) == '{')
                    {
                        this.adv(2);
                        this.emit_text(TokenType.DICT_LITERAL, ln, col, "d{", 2);
                        continue;
                    };

                    // numbers
                    if (is_digit(c))
                    {
                        this.read_number();
                        continue;
                    };

                    // identifiers and keywords
                    if (is_alpha(c) | c == '_')
                    {
                        tt = this.read_identifier();

                        if (tt == TokenType.ASM)
                        {
                            while (this.cur() == 32 | this.cur() == 9 | this.cur() == 13 | this.cur() == 10)
                            {
                                this.adv(1);
                            };
                            if (this.cur() == '{')
                            {
                                this.read_brace_block(TokenType.ASM_BLOCK);
                                continue;
                            };
                        };

                        if (tt == TokenType.FLUXVM)
                        {
                            saved_pos = this.position;
                            saved_line = this.line;
                            saved_col = this.column;
                            while (this.cur() == 32 | this.cur() == 9 | this.cur() == 13 | this.cur() == 10)
                            {
                                this.adv(1);
                            };
                            if (this.cur() == '{')
                            {
                                this.read_brace_block(TokenType.FLUXVM_BLOCK);
                                continue;
                            }
                            else
                            {
                                this.position = saved_pos;
                                this.line = saved_line;
                                this.column = saved_col;
                            };
                        };
                        continue;
                    };

                    // operators and delimiters
                    oplen = this.match_op(@optype);
                    if (oplen > 0)
                    {
                        this.emit_text(optype, ln, col, this.src + this.position, oplen);
                        this.adv(oplen);
                        continue;
                    };

                    // unknown character. Non-ASCII outside strings is recorded and skipped.
                    if (c >= 128)
                    {
                        extra = 0;
                        cp = c;
                        if (c >= 0xF0) { cp = c & 0x07; extra = 3; }
                        elif (c >= 0xE0) { cp = c & 0x0F; extra = 2; }
                        elif (c >= 0xC0) { cp = c & 0x1F; extra = 1; };

                        this.warn_count++;
                        if (this.warn_count == 1)
                        {
                            this.warn_line = ln;
                            this.warn_col = col;
                        };

                        this.adv(1);
                        while (extra > 0 & is_continuation(this.cur()))
                        {
                            cp = (cp << 6) | (this.cur() & 0x3F);
                            this.adv(1);
                            extra--;
                        };
                        if (this.warn_count == 1) { this.warn_cp = cp; };
                    }
                    else
                    {
                        this.adv(1);
                    };
                };

                vb = this.vbegin();
                vl = this.vend(vb);
                this.emit(TokenType.EOF, this.line, this.column, vb, vl, 0);
                -> this.err_code == 0;
            };
        };
    };
};

#endif;
