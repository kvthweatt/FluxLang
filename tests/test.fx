#import "standard.fx";

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

def keyword_type(string* s) -> TokenType
{
    // This is the dict lookup: keywords.get(result, IDENTIFIER)
    // Kept boolean tokens too (true/false map to TRUE/FALSE in the python).:contentReference[oaicite:9]{index=9}
    if (s.equals("alignof\0"))   { return TokenType.ALIGNOF; };
    if (s.equals("and\0"))       { return TokenType.AND; };
    if (s.equals("as\0"))        { return TokenType.AS; };
    if (s.equals("asm\0"))       { return TokenType.ASM; };
    if (s.equals("assert\0"))    { return TokenType.ASSERT; };
    if (s.equals("auto\0"))      { return TokenType.AUTO; };
    if (s.equals("break\0"))     { return TokenType.BREAK; };
    if (s.equals("bool\0"))      { return TokenType.BOOL_KW; };
    if (s.equals("case\0"))      { return TokenType.CASE; };
    if (s.equals("catch\0"))     { return TokenType.CATCH; };
    if (s.equals("char\0"))      { return TokenType.CHAR; };
    if (s.equals("compt\0"))     { return TokenType.COMPT; };
    if (s.equals("const\0"))     { return TokenType.CONST; };
    if (s.equals("continue\0"))  { return TokenType.CONTINUE; };
    if (s.equals("data\0"))      { return TokenType.DATA; };
    if (s.equals("def\0"))       { return TokenType.DEF; };
    if (s.equals("default\0"))   { return TokenType.DEFAULT; };
    if (s.equals("do\0"))        { return TokenType.DO; };
    if (s.equals("elif\0"))      { return TokenType.ELIF; };
    if (s.equals("else\0"))      { return TokenType.ELSE; };
    if (s.equals("enum\0"))      { return TokenType.ENUM; };
    if (s.equals("extern\0"))    { return TokenType.EXTERN; };
    if (s.equals("false\0"))     { return TokenType.FALSE; };
    if (s.equals("float\0"))     { return TokenType.FLOAT_KW; };
    if (s.equals("from\0"))      { return TokenType.FROM; };
    if (s.equals("for\0"))       { return TokenType.FOR; };
    if (s.equals("if\0"))        { return TokenType.IF; };
    if (s.equals("global\0"))    { return TokenType.GLOBAL; };
    if (s.equals("heap\0"))      { return TokenType.HEAP; };
    if (s.equals("in\0"))        { return TokenType.IN; };
    if (s.equals("is\0"))        { return TokenType.IS; };
    if (s.equals("int\0"))       { return TokenType.SINT; };
    if (s.equals("local\0"))     { return TokenType.LOCAL; };
    if (s.equals("namespace\0")) { return TokenType.NAMESPACE; };
    if (s.equals("not\0"))       { return TokenType.NOT; };
    if (s.equals("noinit\0"))    { return TokenType.NO_INIT; };
    if (s.equals("object\0"))    { return TokenType.OBJECT; };
    if (s.equals("or\0"))        { return TokenType.OR; };
    if (s.equals("private\0"))   { return TokenType.PRIVATE; };
    if (s.equals("public\0"))    { return TokenType.PUBLIC; };
    if (s.equals("register\0"))  { return TokenType.REGISTER; };
    if (s.equals("return\0"))    { return TokenType.RETURN; };
    if (s.equals("signed\0"))    { return TokenType.SIGNED; };
    if (s.equals("sizeof\0"))    { return TokenType.SIZEOF; };
    if (s.equals("stack\0"))     { return TokenType.STACK; };
    if (s.equals("struct\0"))    { return TokenType.STRUCT; };
    if (s.equals("switch\0"))    { return TokenType.SWITCH; };
    if (s.equals("this\0"))      { return TokenType.THIS; };
    if (s.equals("throw\0"))     { return TokenType.THROW; };
    if (s.equals("true\0"))      { return TokenType.TRUE; };
    if (s.equals("try\0"))       { return TokenType.TRY; };
    if (s.equals("typeof\0"))    { return TokenType.TYPEOF; };
    if (s.equals("uint\0"))      { return TokenType.UINT; };
    if (s.equals("union\0"))     { return TokenType.UNION; };
    if (s.equals("unsigned\0"))  { return TokenType.UNSIGNED; };
    if (s.equals("using\0"))     { return TokenType.USING; };
    if (s.equals("void\0"))      { return TokenType.VOID; };
    if (s.equals("volatile\0"))  { return TokenType.VOLATILE; };
    if (s.equals("while\0"))     { return TokenType.WHILE; };
    if (s.equals("xor\0"))       { return TokenType.XOR; };

    return TokenType.IDENTIFIER;
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

def main() -> int
{
    string s("bool\0");

    string* ps = @s;

    s.printval();
    print();

    print(keyword_type(ps));
    return 0;
};