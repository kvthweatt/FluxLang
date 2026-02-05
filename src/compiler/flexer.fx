// flexer.fx - Flux rewrite of flexer.py (lexer)
// Mirrors behavior + token inventory from flexer.py.
// (No attempt to "improve" design; this is a translation.)

//#import "standard.fx";
//using standard::types;
//using standard::io;

// Minimal string alias (matches your docs style)
unsigned data{8}[] as string;

// ==============================
// Token Types (from flexer.py)
// ==============================

enum TokenType
{
    // Literals
    SINT_LITERAL,
    UINT_LITERAL,      // `123u`
    FLOAT,             // `1f` or `1.0`
    CHAR,
    STRING_LITERAL,
    BOOL,

    // String interpolation
    I_STRING,
    F_STRING,

    // Identifiers
    IDENTIFIER,

    // Keywords (subset shown in snippet; matches mapping in flexer.py)
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
    SINT,      // int
    UINT,      // uint
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
    PLUS,                 // +
    MINUS,                // -
    MULTIPLY,             // *
    DIVIDE,               // /
    MODULO,               // %
    POWER,                // ^
    XOR_OP,               // ^^
    INCREMENT,            // ++
    DECREMENT,            // --
    LOGICAL_AND,          // &
    LOGICAL_OR,           // |
    BITAND_OP,            // `&
    BITOR_OP,             // `|

    // Comparison
    EQUAL,                // ==
    NOT_EQUAL,            // !=
    LESS_THAN,            // <
    LESS_EQUAL,           // <=
    GREATER_THAN,         // >
    GREATER_EQUAL,        // >=

    // Shift
    BITSHIFT_LEFT,        // <<
    BITSHIFT_RIGHT,       // >>

    // Assignment
    ASSIGN,               // =
    PLUS_ASSIGN,          // +=
    MINUS_ASSIGN,         // -=
    MULTIPLY_ASSIGN,      // *=
    DIVIDE_ASSIGN,        // /=
    MODULO_ASSIGN,        // %=
    AND_ASSIGN,           // &=
    OR_ASSIGN,            // |=
    POWER_ASSIGN,         // ^=
    XOR_ASSIGN,           // ^^=
    BITSHIFT_LEFT_ASSIGN, // <<=
    BITSHIFT_RIGHT_ASSIGN,// >>=

    // Other operators
    ADDRESS_OF,           // @
    RANGE,                // .   (token name RANGE used for single '.' operator dictionary)
    SCOPE,                // ::
    QUESTION,             // ?
    COLON,                // :
    TIE,                  // ~

    // Directionals
    RETURN_ARROW,         // ->
    CHAIN_ARROW,          // <-
    LAMBDA_ARROW,         // <:-
    RECURSE_ARROW,        // <~
    NULL_COALESCE,        // ??
    NO_MANGLE,            // !!

    // SPECIAL
    FUNCTION_POINTER,     // {}*
    ADDRESS_CAST,         // (@)

    // Delimiters
    LEFT_PAREN,           // (
    RIGHT_PAREN,          // )
    LEFT_BRACKET,         // [
    RIGHT_BRACKET,        // ]
    LEFT_BRACE,           // {
    RIGHT_BRACE,          // }
    SEMICOLON,            // ;
    COMMA,                // ,
    DOT,                  // .   (token name DOT used in single-char dict too)

    // Special
    EOF,
    NEWLINE
};

// ==============================
// Token struct (from flexer.py)
// ==============================

struct Token
{
    TokenType type;
    string value;
    int line;
    int column;
};

// ==============================
// ASCII helpers (so we don’t rely on Python’s isalpha/isdigit/etc.)
// ==============================

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
    return is_digit(c) | (c >= 'A' & c <= 'F') | (c >= 'a' & c <= 'f');
};

// NOTE: flexer.py’s hex loop uses only '0123456789ABCDEF' (uppercase).:contentReference[oaicite:7]{index=7}
// If you want it identical-identical, drop lowercase acceptance above and mirror that exactly.

def to_lower(char c) -> char
{
    if (c >= 'A' & c <= 'Z') { return (char)(c + 32); };
    return c;
};

// Simple string builder: append one char (heap grows)
// (Assumes you have array concatenation in your runtime; otherwise replace with your stdlib push.)
def str_append_char(string s, char c) -> string
{
    // naive: new array sized +1 and copy
    int n = sizeof(s) / sizeof(unsigned data{8});
    heap unsigned data{8}[n + 1] tmp;
    for (int i = 0; i < n; i++) { tmp[i] = s[i]; };
    tmp[n] = (unsigned data{8})c;
    return (string)tmp;
};

def str_append_str(string a, string b) -> string
{
    int na = sizeof(a) / sizeof(unsigned data{8});
    int nb = sizeof(b) / sizeof(unsigned data{8});
    heap unsigned data{8}[na + nb] tmp;
    for (int i = 0; i < na; i++) { tmp[i] = a[i]; };
    for (int j = 0; j < nb; j++) { tmp[na + j] = b[j]; };
    return (string)tmp;
};

// ==============================
// Keyword mapping (mirrors self.keywords dict):contentReference[oaicite:8]{index=8}
// ==============================

def keyword_type(string s) -> TokenType
{
    // This is the dict lookup: keywords.get(result, IDENTIFIER)
    // Kept boolean tokens too (true/false map to TRUE/FALSE in the python).:contentReference[oaicite:9]{index=9}
    if (s == "alignof")   { return TokenType.ALIGNOF; };
    if (s == "and")       { return TokenType.AND; };
    if (s == "as")        { return TokenType.AS; };
    if (s == "asm")       { return TokenType.ASM; };
    if (s == "assert")    { return TokenType.ASSERT; };
    if (s == "auto")      { return TokenType.AUTO; };
    if (s == "break")     { return TokenType.BREAK; };
    if (s == "bool")      { return TokenType.BOOL_KW; };
    if (s == "case")      { return TokenType.CASE; };
    if (s == "catch")     { return TokenType.CATCH; };
    if (s == "char")      { return TokenType.CHAR; };
    if (s == "compt")     { return TokenType.COMPT; };
    if (s == "const")     { return TokenType.CONST; };
    if (s == "continue")  { return TokenType.CONTINUE; };
    if (s == "data")      { return TokenType.DATA; };
    if (s == "def")       { return TokenType.DEF; };
    if (s == "default")   { return TokenType.DEFAULT; };
    if (s == "do")        { return TokenType.DO; };
    if (s == "elif")      { return TokenType.ELIF; };
    if (s == "else")      { return TokenType.ELSE; };
    if (s == "enum")      { return TokenType.ENUM; };
    if (s == "extern")    { return TokenType.EXTERN; };
    if (s == "false")     { return TokenType.FALSE; };
    if (s == "float")     { return TokenType.FLOAT_KW; };
    if (s == "from")      { return TokenType.FROM; };
    if (s == "for")       { return TokenType.FOR; };
    if (s == "if")        { return TokenType.IF; };
    if (s == "global")    { return TokenType.GLOBAL; };
    if (s == "heap")      { return TokenType.HEAP; };
    if (s == "in")        { return TokenType.IN; };
    if (s == "is")        { return TokenType.IS; };
    if (s == "int")       { return TokenType.SINT; };
    if (s == "local")     { return TokenType.LOCAL; };
    if (s == "namespace") { return TokenType.NAMESPACE; };
    if (s == "not")       { return TokenType.NOT; };
    if (s == "noinit")    { return TokenType.NO_INIT; };
    if (s == "object")    { return TokenType.OBJECT; };
    if (s == "or")        { return TokenType.OR; };
    if (s == "private")   { return TokenType.PRIVATE; };
    if (s == "public")    { return TokenType.PUBLIC; };
    if (s == "register")  { return TokenType.REGISTER; };
    if (s == "return")    { return TokenType.RETURN; };
    if (s == "signed")    { return TokenType.SIGNED; };
    if (s == "sizeof")    { return TokenType.SIZEOF; };
    if (s == "stack")     { return TokenType.STACK; };
    if (s == "struct")    { return TokenType.STRUCT; };
    if (s == "switch")    { return TokenType.SWITCH; };
    if (s == "this")      { return TokenType.THIS; };
    if (s == "throw")     { return TokenType.THROW; };
    if (s == "true")      { return TokenType.TRUE; };
    if (s == "try")       { return TokenType.TRY; };
    if (s == "typeof")    { return TokenType.TYPEOF; };
    if (s == "uint")      { return TokenType.UINT; };
    if (s == "union")     { return TokenType.UNION; };
    if (s == "unsigned")  { return TokenType.UNSIGNED; };
    if (s == "using")     { return TokenType.USING; };
    if (s == "void")      { return TokenType.VOID; };
    if (s == "volatile")  { return TokenType.VOLATILE; };
    if (s == "while")     { return TokenType.WHILE; };
    if (s == "xor")       { return TokenType.XOR; };

    return TokenType.IDENTIFIER;
};

// ==============================
// Lexer Object (FluxLexer)
// ==============================

object FluxLexer
{
    string source;
    int position;
    int line;
    int column;
    int length;

    def __init(string source_code) -> this
    {
        this.source   = source_code;
        this.position = 0;
        this.line     = 1;
        this.column   = 1;

        // length = len(source_code)
        this.length = sizeof(source_code) / sizeof(unsigned data{8});
        return this;
    };

    def current_char() -> char
    {
        if (this.position >= this.length) { return (char)0; };
        return (char)this.source[this.position];
    };

    def peek_char(int offset) -> char
    {
        int pos = this.position + offset;
        if (pos >= this.length) { return (char)0; };
        return (char)this.source[pos];
    };

    // Mirrors advance(count) including line/column behavior.:contentReference[oaicite:10]{index=10}
    def advance(int count) -> void
    {
        if (this.position < this.length & this.source[this.position] == '\n')
        {
            this.line += 1;
            this.column = count;
        }
        else
        {
            this.column += count;
        };
        this.position += count;
        return;
    };

    def skip_whitespace() -> void
    {
        while (true)
        {
            char c = this.current_char();
            if (c == 0) { break; };
            if (c == ' ' | c == '\t' | c == '\r' | c == '\n')
            {
                this.advance(1);
                continue;
            };
            break;
        };
        return;
    };

    // Read string contents until delimiter; supports backslash escaping lightly.
    // Python version is read_string(delim) used by normal strings and i-string parsing.:contentReference[oaicite:11]{index=11}
    def read_string(char delim) -> string
    {
        // current char is delim
        this.advance(1);

        string out("\0"); // start empty

        while (true)
        {
            char c = this.current_char();
            if (c == 0) { break; };

            if (c == '\\')
            {
                // keep escape sequences like Python version would (basic)
                this.advance(1);
                char e = this.current_char();
                if (e == 0) { break; };
                out = str_append_char(out, e);
                this.advance(1);
                continue;
            };

            if (c == delim)
            {
                this.advance(1);
                break;
            };

            out = str_append_char(out, c);
            this.advance(1);
        };

        return out;
    };

    // asm "" block: python reads until a doubled quote terminator: not (c == '"' and peek == '"'):contentReference[oaicite:12]{index=12}
    def read_asm_block() -> Token
    {
        int start_line = this.line;
        int start_col  = this.column;

        // Skip opening quote
        this.advance(1);

        string out("\0"); // start empty

        while (true)
        {
            char c = this.current_char();
            if (c == 0) { break; };

            if (c == '"' & this.peek_char(1) == '"')
            {
                break;
            };

            out = str_append_char(out, c);
            this.advance(1);
        };

        if (this.current_char() == '"' & this.peek_char(1) == '"')
        {
            this.advance(2); // closing quotes
        };

        Token t;
        t.type   = TokenType.ASM_BLOCK;
        t.value  = out;
        t.line   = start_line;
        t.column = start_col;
        return t;
    };

    // asm { ... } content (used when lexer sees "asm" keyword followed by '{'):contentReference[oaicite:13]{index=13}
    def read_asm_block_content() -> Token
    {
        int start_line = this.line;
        int start_col  = this.column;

        // Skip whitespace/newlines to find opening brace
        while (true)
        {
            char c = this.current_char();
            if (c == 0) { break; };
            if (c == ' ' | c == '\t' | c == '\r' | c == '\n') { this.advance(1); continue; };
            break;
        };

        // Expect '{'
        // (If not, return empty block token - matches "best effort" translation.)
        if (this.current_char() != '{')
        {
            string out("\0"); // start empty
            Token bad;
            bad.type = TokenType.ASM_BLOCK;
            bad.value = out.val();
            bad.line = start_line;
            bad.column = start_col;
            return bad;
        };

        int brace_count = 0;
        string out("\0"); // start empty

        while (true)
        {
            char c = this.current_char();
            if (c == 0) { break; };

            if (c == '{') { brace_count += 1; };
            if (c == '}') { brace_count -= 1; };

            out = str_append_char(out, c);
            this.advance(1);

            if (brace_count == 0) { break; };
        };

        Token t;
        t.type   = TokenType.ASM_BLOCK;
        t.value  = out;
        t.line   = start_line;
        t.column = start_col;
        return t;
    };

    // f-string read helper: reads content between quotes, allowing { } pairs (simple version).
    // Python version calls read_f_string() then wraps it into f"..." token.:contentReference[oaicite:14]{index=14}
    def read_f_string() -> string
    {
        // current char is '"'
        this.advance(1);

        string out("\0"); // start empty
        int brace_depth = 0;

        while (true)
        {
            char c = this.current_char();
            if (c == 0) { break; };

            if (c == '\\')
            {
                this.advance(1);
                char e = this.current_char();
                if (e == 0) { break; };
                out = str_append_char(out, e);
                this.advance(1);
                continue;
            };

            if (c == '{') { brace_depth += 1; };
            if (c == '}') { if (brace_depth > 0) { brace_depth -= 1; }; };

            if (c == '"' & brace_depth == 0)
            {
                this.advance(1);
                break;
            };

            out = str_append_char(out, c);
            this.advance(1);
        };

        return out;
    };

    // Number reader: mirrors bases 32/16/8/2 via 0d/0x/0o/0b and suffix u/f behavior.:contentReference[oaicite:15]{index=15}:contentReference[oaicite:16]{index=16}
    def read_number() -> Token
    {
        int start_line = this.line;
        int start_col  = this.column;

        string out("\0"); // start empty
        bool is_float = false;
        bool is_unsigned = false;

        char c0 = this.current_char();

        // Leading 0 + base prefix logic
        if (c0 == '0')
        {
            out = str_append_char(out, c0);
            this.advance(1);

            char p = to_lower(this.current_char());

            // base-32: 0d (Duotrigesimal):contentReference[oaicite:17]{index=17}
            if (p == 'd')
            {
                out = str_append_char(out, this.current_char());
                this.advance(1);

                while (true)
                {
                    char c = this.current_char();
                    if (c == 0) { break; };

                    // Python allows '0123456789ABCDEFGHIJKLMNOPQRSTUV' (uppercase):contentReference[oaicite:18]{index=18}
                    bool ok =
                        (c >= '0' & c <= '9') |
                        (c >= 'A' & c <= 'V');
                    if (!ok) { break; };

                    out = str_append_char(out, c);
                    this.advance(1);
                };

                if (this.current_char() == 'u')
                {
                    is_unsigned = true;
                    this.advance(1);
                };

                Token t;
                t.type = is_unsigned ? TokenType.UINT_LITERAL : TokenType.SINT_LITERAL;
                t.value = out; // python strips 'u' from token value; we never appended it
                t.line = start_line;
                t.column = start_col;
                return t;
            };

            // hex: 0x:contentReference[oaicite:19]{index=19}
            if (p == 'x')
            {
                out = str_append_char(out, this.current_char());
                this.advance(1);

                while (true)
                {
                    char c = this.current_char();
                    if (c == 0) { break; };

                    // python only checks uppercase A-F in that loop; match it by uppercasing:
                    char u = c;
                    if (u >= 'a' & u <= 'f') { u = (char)(u - 32); };

                    bool ok = (u >= '0' & u <= '9') | (u >= 'A' & u <= 'F');
                    if (!ok) { break; };

                    out = str_append_char(out, u);
                    this.advance(1);
                };

                if (this.current_char() == 'u')
                {
                    is_unsigned = true;
                    this.advance(1);
                };

                Token t;
                t.type = is_unsigned ? TokenType.UINT_LITERAL : TokenType.SINT_LITERAL;
                t.value = out;
                t.line = start_line;
                t.column = start_col;
                return t;
            };

            // octal: 0o:contentReference[oaicite:20]{index=20}
            if (p == 'o')
            {
                out = str_append_char(out, this.current_char());
                this.advance(1);

                while (true)
                {
                    char c = this.current_char();
                    if (c == 0) { break; };
                    if (!(c >= '0' & c <= '7')) { break; };
                    out = str_append_char(out, c);
                    this.advance(1);
                };

                if (this.current_char() == 'u')
                {
                    is_unsigned = true;
                    this.advance(1);
                };

                Token t;
                t.type = is_unsigned ? TokenType.UINT_LITERAL : TokenType.SINT_LITERAL;
                t.value = out;
                t.line = start_line;
                t.column = start_col;
                return t;
            };

            // binary: 0b:contentReference[oaicite:21]{index=21}
            if (p == 'b')
            {
                out = str_append_char(out, this.current_char());
                this.advance(1);

                while (true)
                {
                    char c = this.current_char();
                    if (c == 0) { break; };
                    if (!(c == '0' | c == '1')) { break; };
                    out = str_append_char(out, c);
                    this.advance(1);
                };

                if (this.current_char() == 'u')
                {
                    is_unsigned = true;
                    this.advance(1);
                };

                Token t;
                t.type = is_unsigned ? TokenType.UINT_LITERAL : TokenType.SINT_LITERAL;
                t.value = out;
                t.line = start_line;
                t.column = start_col;
                return t;
            };

            // fallthrough: 0 followed by normal decimal continuation handled below
        };

        // Read remaining decimal digits:contentReference[oaicite:22]{index=22}
        while (is_digit(this.current_char()))
        {
            out = str_append_char(out, this.current_char());
            this.advance(1);
        };

        // Decimal point + digits => float (only when '.' and next is digit):contentReference[oaicite:23]{index=23}
        if (this.current_char() == '.' & is_digit(this.peek_char(1)))
        {
            is_float = true;
            out = str_append_char(out, '.');
            this.advance(1);
            while (is_digit(this.current_char()))
            {
                out = str_append_char(out, this.current_char());
                this.advance(1);
            };
        };

        // Suffix rules: 'f' forces FLOAT; else 'u' forces UINT_LITERAL; else float stays FLOAT.:contentReference[oaicite:24]{index=24}
        TokenType tt = TokenType.SINT_LITERAL;

        if (this.current_char() == 'f')
        {
            tt = TokenType.FLOAT;
            is_float = true;
            this.advance(1);
        }
        elif (!is_float & this.current_char() == 'u')
        {
            tt = TokenType.UINT_LITERAL;
            this.advance(1);
        }
        elif (is_float)
        {
            tt = TokenType.FLOAT;
        };

        Token t;
        t.type = tt;
        t.value = out;
        t.line = start_line;
        t.column = start_col;
        return t;
    };

    def read_identifier() -> Token
    {
        int start_line = this.line;
        int start_col  = this.column;

        string out("\0"); // start empty

        while (true)
        {
            char c = this.current_char();
            if (c == 0) { break; };
            if (!(is_alnum(c) | c == '_')) { break; };
            out = str_append_char(out, c);
            this.advance(1);
        };

        TokenType tt = keyword_type(out);
        // python has special bool handling for true/false; keyword_type already does that.:contentReference[oaicite:25]{index=25}

        Token t;
        t.type = tt;
        t.value = out;
        t.line = start_line;
        t.column = start_col;
        return t;
    };

    // i-string: i"string": { ... } (reads nested braces):contentReference[oaicite:26]{index=26}
    def read_interpolation_string() -> Token
    {
        int start_line = this.line;
        int start_col  = this.column;

        string string_part = this.read_string('"');

        this.skip_whitespace();
        if (this.current_char() == ':') { this.advance(1); };

        this.skip_whitespace();

        string out("\0"); // start empty
        full = str_append_str(full, "i\"");
        full = str_append_str(full, string_part);
        full = str_append_str(full, "\"");

        if (this.current_char() == '{')
        {
            int brace_count = 1;
            string out("\0"); // start empty

            interp = str_append_char(interp, '{');
            this.advance(1);

            while (true)
            {
                char c = this.current_char();
                if (c == 0) { break; };

                if (c == '{') { brace_count += 1; }
                elif (c == '}') { brace_count -= 1; };

                interp = str_append_char(interp, c);
                this.advance(1);

                if (brace_count == 0) { break; };
            };

            full = str_append_str(full, ":");
            full = str_append_str(full, interp);
        };

        Token t;
        t.type = TokenType.I_STRING;
        t.value = full;
        t.line = start_line;
        t.column = start_col;
        return t;
    };

    // ==============================
    // tokenize()
    // ==============================
    def tokenize() -> Token[]
    {
        // Dynamic array placeholder. Replace with your real vector/list type if you have one.
        // For now: over-allocate worst-case (length) and return trimmed.
        heap Token[this.length + 1] tmp;
        int count = 0;

        while (this.position < this.length)
        {
            // Skip whitespace:contentReference[oaicite:27]{index=27}
            char c = this.current_char();
            if (c == ' ' | c == '\t' | c == '\r' | c == '\n')
            {
                this.skip_whitespace();
                continue;
            };

            int start_line = this.line;
            int start_col  = this.column;

            // i"...":contentReference[oaicite:28]{index=28}
            if (c == 'i' & this.peek_char(1) == '"')
            {
                this.advance(1); // skip i
                tmp[count] = this.read_interpolation_string(); count++;
                continue;
            };

            // f"...":contentReference[oaicite:29]{index=29}
            if (c == 'f' & this.peek_char(1) == '"')
            {
                this.advance(1); // skip f
                string inner = this.read_f_string();

                Token t;
                t.type = TokenType.F_STRING;

                string out("\0"); // start empty
                wrapped = str_append_str(wrapped, "f\"");
                wrapped = str_append_str(wrapped, inner);
                wrapped = str_append_str(wrapped, "\"");

                t.value = wrapped;
                t.line = start_line;
                t.column = start_col;

                tmp[count] = t; count++;
                continue;
            };

            // Normal string / char literals:contentReference[oaicite:30]{index=30}
            if (c == '"' | c == '\'')
            {
                if (c == '"')
                {
                    string content = this.read_string('"');
                    Token t; t.type = TokenType.STRING_LITERAL; t.value = content; t.line = start_line; t.column = start_col;
                    tmp[count] = t; count++;
                }
                else
                {
                    string content = this.read_string('\'');
                    // CHAR if len == 1 else STRING_LITERAL (python behavior):contentReference[oaicite:31]{index=31}
                    int n = sizeof(content) / sizeof(unsigned data{8});
                    Token t;
                    t.type = (n == 1) ? TokenType.CHAR : TokenType.STRING_LITERAL;
                    t.value = content;
                    t.line = start_line;
                    t.column = start_col;
                    tmp[count] = t; count++;
                };
                continue;
            };

            // Special: asm"..." inline quoting (exact python check):contentReference[oaicite:32]{index=32}
            if (c == 'a' & this.peek_char(1) == 's' & this.peek_char(2) == 'm' & this.peek_char(3) == '"')
            {
                this.advance(3); // skip asm
                Token kw; kw.type = TokenType.ASM; kw.value = "asm"; kw.line = start_line; kw.column = start_col;
                tmp[count] = kw; count++;

                Token blk = this.read_asm_block();
                tmp[count] = blk; count++;
                continue;
            };

            // Numbers:contentReference[oaicite:33]{index=33}
            if (is_digit(c))
            {
                tmp[count] = this.read_number(); count++;
                continue;
            };

            // Identifiers + keywords, plus special asm { } handling:contentReference[oaicite:34]{index=34}
            if (is_alpha(c) | c == '_')
            {
                Token t = this.read_identifier();
                tmp[count] = t; count++;

                if (t.type == TokenType.ASM)
                {
                    // look ahead skipping whitespace; if next is '{', read asm block content as a whole:contentReference[oaicite:35]{index=35}
                    int saved_pos = this.position;
                    int saved_line = this.line;
                    int saved_col = this.column;

                    while (true)
                    {
                        char w = this.current_char();
                        if (w == 0) { break; };
                        if (w == ' ' | w == '\t' | w == '\r' | w == '\n') { this.advance(1); continue; };
                        break;
                    };

                    if (this.current_char() == '{')
                    {
                        Token blk = this.read_asm_block_content();
                        tmp[count] = blk; count++;
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

            // ==============================
            // Operators / delimiters (cascading longest-first):contentReference[oaicite:36]{index=36}:contentReference[oaicite:37]{index=37}
            // ==============================

            // 3-char tokens:contentReference[oaicite:38]{index=38}
            char c1 = this.peek_char(1);
            char c2 = this.peek_char(2);

            // Match explicitly (no dict)
            if (c == '<' & c1 == '<' & c2 == '=')
            { Token t; t.type=TokenType.BITSHIFT_LEFT_ASSIGN; t.value="<<="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(3); continue; };
            if (c == '>' & c1 == '>' & c2 == '=')
            { Token t; t.type=TokenType.BITSHIFT_RIGHT_ASSIGN; t.value=">>="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(3); continue; };
            if (c == '^' & c1 == '^' & c2 == '=')
            { Token t; t.type=TokenType.XOR_ASSIGN; t.value="^^="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(3); continue; };
            if (c == '{' & c1 == '}' & c2 == '*')
            { Token t; t.type=TokenType.FUNCTION_POINTER; t.value="{}*"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(3); continue; };
            if (c == '(' & c1 == '@' & c2 == ')')
            { Token t; t.type=TokenType.ADDRESS_CAST; t.value="(@)"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(3); continue; };
            if (c == '<' & c1 == ':' & c2 == '-')
            { Token t; t.type=TokenType.LAMBDA_ARROW; t.value="<:-"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(3); continue; };

            // 2-char tokens:contentReference[oaicite:39]{index=39}:contentReference[oaicite:40]{index=40}
            if (c == '=' & c1 == '=')
            { Token t; t.type=TokenType.EQUAL; t.value="=="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '!' & c1 == '=')
            { Token t; t.type=TokenType.NOT_EQUAL; t.value="!="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '!' & c1 == '!')
            { Token t; t.type=TokenType.NO_MANGLE; t.value="!!"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '?' & c1 == '?')
            { Token t; t.type=TokenType.NULL_COALESCE; t.value="??"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '<' & c1 == '=')
            { Token t; t.type=TokenType.LESS_EQUAL; t.value="<="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '>' & c1 == '=')
            { Token t; t.type=TokenType.GREATER_EQUAL; t.value=">="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '<' & c1 == '<')
            { Token t; t.type=TokenType.BITSHIFT_LEFT; t.value="<<"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '>' & c1 == '>')
            { Token t; t.type=TokenType.BITSHIFT_RIGHT; t.value=">>"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '+' & c1 == '+')
            { Token t; t.type=TokenType.INCREMENT; t.value="++"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '-' & c1 == '-')
            { Token t; t.type=TokenType.DECREMENT; t.value="--"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '+' & c1 == '=')
            { Token t; t.type=TokenType.PLUS_ASSIGN; t.value="+="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '-' & c1 == '=')
            { Token t; t.type=TokenType.MINUS_ASSIGN; t.value="-="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '*' & c1 == '=')
            { Token t; t.type=TokenType.MULTIPLY_ASSIGN; t.value="*="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '/' & c1 == '=')
            { Token t; t.type=TokenType.DIVIDE_ASSIGN; t.value="/="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '%' & c1 == '=')
            { Token t; t.type=TokenType.MODULO_ASSIGN; t.value="%="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '^' & c1 == '=')
            { Token t; t.type=TokenType.POWER_ASSIGN; t.value="^="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '&' & c1 == '=')
            { Token t; t.type=TokenType.AND_ASSIGN; t.value="&="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '|' & c1 == '=')
            { Token t; t.type=TokenType.OR_ASSIGN; t.value="|="; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '^' & c1 == '^')
            { Token t; t.type=TokenType.XOR_OP; t.value="^^"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '-' & c1 == '>')
            { Token t; t.type=TokenType.RETURN_ARROW; t.value="->"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '<' & c1 == '-')
            { Token t; t.type=TokenType.CHAIN_ARROW; t.value="<-"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '<' & c1 == '~')
            { Token t; t.type=TokenType.RECURSE_ARROW; t.value="<~"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == ':' & c1 == ':')
            { Token t; t.type=TokenType.SCOPE; t.value="::"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '`' & c1 == '&')
            { Token t; t.type=TokenType.BITAND_OP; t.value="`&"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };
            if (c == '`' & c1 == '|')
            { Token t; t.type=TokenType.BITOR_OP; t.value="`|"; t.line=start_line; t.column=start_col; tmp[count]=t; count++; this.advance(2); continue; };

            // 1-char tokens (mirror dict):contentReference[oaicite:41]{index=41}
            Token t1;
            t1.line = start_line; t1.column = start_col;

            if (c == '+') { t1.type=TokenType.PLUS; t1.value="+"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '-') { t1.type=TokenType.MINUS; t1.value="-"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '*') { t1.type=TokenType.MULTIPLY; t1.value="*"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '/') { t1.type=TokenType.DIVIDE; t1.value="/"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '%') { t1.type=TokenType.MODULO; t1.value="%"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '^') { t1.type=TokenType.POWER; t1.value="^"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '<') { t1.type=TokenType.LESS_THAN; t1.value="<"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '>') { t1.type=TokenType.GREATER_THAN; t1.value=">"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '&') { t1.type=TokenType.LOGICAL_AND; t1.value="&"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '|') { t1.type=TokenType.LOGICAL_OR; t1.value="|"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '!') { t1.type=TokenType.NOT; t1.value="!"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '@') { t1.type=TokenType.ADDRESS_OF; t1.value="@"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '=') { t1.type=TokenType.ASSIGN; t1.value="="; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '?') { t1.type=TokenType.QUESTION; t1.value="?"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == ':') { t1.type=TokenType.COLON; t1.value=":"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '(') { t1.type=TokenType.LEFT_PAREN; t1.value="("; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == ')') { t1.type=TokenType.RIGHT_PAREN; t1.value=")"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '[') { t1.type=TokenType.LEFT_BRACKET; t1.value="["; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == ']') { t1.type=TokenType.RIGHT_BRACKET; t1.value="]"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '{') { t1.type=TokenType.LEFT_BRACE; t1.value="{"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '}') { t1.type=TokenType.RIGHT_BRACE; t1.value="}"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == ';') { t1.type=TokenType.SEMICOLON; t1.value=";"; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == ',') { t1.type=TokenType.COMMA; t1.value=","; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '.') { t1.type=TokenType.DOT; t1.value="."; tmp[count]=t1; count++; this.advance(1); continue; };
            if (c == '~') { t1.type=TokenType.TIE; t1.value="~"; tmp[count]=t1; count++; this.advance(1); continue; };

            // Unknown character: skip (python behavior):contentReference[oaicite:42]{index=42}
            this.advance(1);
        };

        // EOF token:contentReference[oaicite:43]{index=43}
        string out("\0"); // start empty
        Token eof;
        eof.type = TokenType.EOF;
        eof.value = out.val();
        eof.line = this.line;
        eof.column = this.column;
        tmp[count] = eof; count++;

        // Trim return
        heap Token[count] out;
        for (int i = 0; i < count; i++) { out[i] = tmp[i]; };
        return out;
    };
};

