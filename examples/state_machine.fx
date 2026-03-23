// state_machine.fx
// A lexer-style state machine that classifies ASCII input into token kinds.
// Demonstrates: enum, switch, singinit, and Flux operator idioms (`is`, `?=`).

#import "standard.fx";

using standard::io::console,
      standard::strings;

// ---------------------------------------------------------------
// Token kind enum.
// ---------------------------------------------------------------

enum TokKind
{
    TOK_NONE,
    TOK_IDENT,
    TOK_NUMBER,
    TOK_PUNCT,
    TOK_SPACE,
    TOK_END
};

// ---------------------------------------------------------------
// A token is a kind + a slice of the source buffer.
// kind is TokKind so we use enum member access throughout.
// ---------------------------------------------------------------

struct Token
{
    TokKind kind;
    i32     start, len;
};

// ---------------------------------------------------------------
// Helper predicates.
// ---------------------------------------------------------------

def is_alpha(byte c) -> bool
{
    return (c >= (byte)65 & c <= (byte)90) |
           (c >= (byte)97 & c <= (byte)122);
};

def is_digit(byte c) -> bool
{
    return c >= (byte)48 & c <= (byte)57;
};

def is_alnum(byte c) -> bool
{
    return is_alpha(c) | is_digit(c);
};

def is_space(byte c) -> bool
{
    return c == (byte)32 | c == (byte)9 | c == (byte)10 | c == (byte)13;
};

// ---------------------------------------------------------------
// Tokeniser -- returns next Token, advances *pos.
// All locals declared at function top.
// ---------------------------------------------------------------

def next_token(byte* src, i32* pos) -> Token
{
    Token   tok;
    TokKind kinds;
    byte    c;
    i32     start;

    c = src[*pos];

    if (c == (byte)0)
    {
        tok.kind  = kinds.TOK_END;
        tok.start = *pos;
        tok.len   = 0;
        return tok;
    };

    if (is_space(c))
    {
        start = *pos;
        while (is_space(src[*pos]) & src[*pos] != (byte)0)
        {
            *pos = *pos + 1;
        };
        tok.kind  = kinds.TOK_SPACE;
        tok.start = start;
        tok.len   = *pos - start;
        return tok;
    };

    if (is_alpha(c) | c == (byte)95)
    {
        start = *pos;
        while ((is_alnum(src[*pos]) | src[*pos] == (byte)95) & src[*pos] != (byte)0)
        {
            *pos = *pos + 1;
        };
        tok.kind  = kinds.TOK_IDENT;
        tok.start = start;
        tok.len   = *pos - start;
        return tok;
    };

    if (is_digit(c))
    {
        start = *pos;
        while (is_digit(src[*pos]) & src[*pos] != (byte)0)
        {
            *pos = *pos + 1;
        };
        tok.kind  = kinds.TOK_NUMBER;
        tok.start = start;
        tok.len   = *pos - start;
        return tok;
    };

    tok.kind  = kinds.TOK_PUNCT;
    tok.start = *pos;
    tok.len   = 1;
    *pos      = *pos + 1;
    return tok;
};

// ---------------------------------------------------------------
// singinit: call counter that persists across calls.
// ---------------------------------------------------------------

def count_call() -> i32
{
    singinit i32 calls;
    calls++;
    return calls;
};

// ---------------------------------------------------------------
// Print a single token with its kind name and text.
// ---------------------------------------------------------------

def print_token(byte* src, Token t) -> void
{
    TokKind kinds;
    byte*   kind_name;
    byte[64] text;
    i32 i;

    while (i < t.len & i < 63)
    {
        text[i] = src[t.start + i];
        i++;
    };
    text[i] = (byte)0;

    switch (t.kind)
    {
        case (kinds.TOK_IDENT)  { kind_name = "IDENT \0"; }
        case (kinds.TOK_NUMBER) { kind_name = "NUMBER\0"; }
        case (kinds.TOK_PUNCT)  { kind_name = "PUNCT \0"; }
        case (kinds.TOK_SPACE)  { kind_name = "SPACE \0"; }
        case (kinds.TOK_END)    { kind_name = "END   \0"; }
        default                 { kind_name = "??????\0"; };
    };

    print(f"[{kind_name}] '{@text[0]}'\n\0");
    return;
};


def main() -> int
{
    TokKind kinds;
    byte*   src = "foo_bar 123 + baz * 99\0";
    Token   tok;
    i32     pos, call_n;

    while (true)
    {
        tok    = next_token(src, @pos);
        call_n = count_call();

        if (tok.kind is kinds.TOK_SPACE)
        {
            // skip, but still counted above
        }
        elif (tok.kind is kinds.TOK_END)
        {
            print("--- end of input ---\n\0");
            break;
        }
        else
        {
            print_token(src, tok);
        };
    };

    print(f"next_token called {call_n} times total\n\0");

    return 0;
};
