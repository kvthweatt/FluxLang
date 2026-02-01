#import "standard.fx";

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
    BITSHIFT_LEFT,  // <<
    BITSHIFT_RIGHT, // >>
    
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
    QUESTION,       // ?       ?: = Parse as ternary
    COLON,          // :    [x:y] = slice
    TIE,            // ~ Ownership/move semantics

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

object Token
{
    //TokenType type;
    int token;
    string lexeme("");
    i32 line;
    i32 column;
    
    def __init() -> this
    {
        this.token = TokenType.EOF;
        this.lexeme.set();
        this.line = 0;
        this.column = 0;
        return this;
    };
    
    def __exit() -> void
    {
        // Cleanup if needed
        (void)this;
        return;
    };
    
    def token_name() -> noopstr
    {
        // Simple type to name mapping with explicit null termination
        switch (this.token)
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
        return (noopstr)0;
    };
};

def main() -> int
{
	void* v = noinit;
	void* v = (@)0;   // Void pointer to address 0
	u64 pv = @v;      // Address 0
	print("Address of v: 0x"); print((u64)@v); print();
	void* v = noinit; // deinitialize? deinitialize.
	//int[2] b = [a[0]] + [1]; // ARRAY CONCAT NOT WORKINGGGGGGGGGGGGGG
	// Error in statement 8 (VariableDeclaration):
	//  	cannot store [2 x i32]* to [2 x i32]*:
	//  	mismatching types
	//      (they don't look mismatched to me)
	//print((u32)*v); // segfault if you deinitialize.
	exit(0);
	print("Flux Lexer starting ...\n\0");
	noopstr filename = "build\\tmp.fx\0";
	int size = get_file_size(filename);
	byte* file = malloc(size + 1);
	int bytes_read = read_file(filename, file, size);
	print("Read file \0"); print(filename); print(", size: \0"); print(size); print(" bytes.\n\n
[start of file]\n\0");

	Token tokens();
	//(); // Should be able to call function here.

	//byte[size] file = file;

	///int v = "ABCD";
	print(v); // 0, int packing not working again wtf.///

	for (int pos = 0; pos < size;)
	{
		if (file[pos] == 0) { break; };
		byte x = file[pos++];
		print(x);
		//printchar((byte*)@(*file[pos++]));
		i64 z = 0; while (z++ < 100000000) {};
		//print(x);
	};
	print("
[end of file]\n\n\0");

	if (file[0] == '#')
	{
		print("hashtag\n\0");
	};
	///
	if (file[1:6] == "import") // array slice not parsing, : <- issue
	{
		print("yeah converting to array is working\n\0");
	};///
	(void)file; // throw it away
	// just to be sure
	return 0;
};