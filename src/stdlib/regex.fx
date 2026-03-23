// Author: Karac V. Thweatt

// redregex.fx - Flux Regular Expression Library
//
// Full NFA-based regex engine.
//
// Supported syntax:
//   .          Any character except newline
//   ^  $       Anchors (beginning / end of line)
//   *  +  ?    Greedy quantifiers
//   {n} {n,} {n,m}  Counted quantifiers
//   [abc]      Character class
//   [^abc]     Negated character class
//   [a-z]      Character range inside class
//   (...)      Capturing group
//   a|b        Alternation
//   \d \D      Digit / non-digit
//   \w \W      Word char / non-word char
//   \s \S      Whitespace / non-whitespace
//   \n \t \r   Literal escapes
//   \\         Literal backslash
//   \0..\9     Literal null / digit (outside replacement)
//
// Replacement strings (replace / replace_all):
//   \0         Entire match
//   \1..\9     Capture group 1..9
//   \\         Literal backslash
//
// Usage:
//   #import "redregex.fx";
//   using standard::regex;
//
//   Regex re;
//   re.__init("\\d+\0");
//   RegexMatch m;
//   if (re.match("hello 42\0", @m))
//   {
//       // m.start, m.end
//       // m.groups[0].start, m.groups[0].end
//   };
//   re.__exit();
//
//   // Or use free functions for one-shot use:
//   bool found = rx_test("\\d+\0", "abc 99\0");
//   byte* result = rx_replace("(\\w+)\0", "hello\0", "[\1]\0"); // "[hello]"
//   free(result);

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_STRINGS
#import "red_string_utilities.fx";
#endif;

#ifndef FLUX_STANDARD_REGEX
#def FLUX_STANDARD_REGEX 1;

// ====================================================================
// STRUCTS
// ====================================================================

struct RxNode
{
    int   kind;
    byte  value;         // RXK_LITERAL
    bool  neg;           // RXK_CLASS: negated
    byte* bits;          // RXK_CLASS: 32-byte bitvector (heap)
    int   out1;          // primary successor (-1 = none)
    int   out2;          // secondary successor, SPLIT only
    int   save_slot;     // RXK_SAVE: index into saves array
};

struct RegexGroup
{
    int start;   // -1 if not captured
    int end;
};

struct RegexMatch
{
    bool       matched;
    int        start;
    int        end;
    int        group_count;
    RegexGroup[RX_MAX_GROUPS] groups;
};

// NFA simulation thread
struct RxThread
{
    int node;
    int[32] saves;   // RX_MAX_GROUPS * 2
};

// Compiler state (passed around by pointer)
struct RxC
{
    byte* pat;
    int   pos;
    int   len;
    RxNode* nodes;
    int   nc;          // node count
    int   gc;          // group count
    int   err;
    byte* errmsg;
};

namespace standard
{
    namespace regex
    {
        // ====================================================================
        // LIMITS
        // ====================================================================
        const int RX_MAX_NODES    = 2048;
        const int RX_MAX_GROUPS   = 16;
        const int RX_MAX_THREADS  = 512;
        const int RX_CLASS_BYTES  = 32;   // 256-bit bitvector

        // Error codes
        const int RX_OK              = 0;
        const int RX_ERR_NOMEM       = 1;
        const int RX_ERR_BADPATTERN  = 2;
        const int RX_ERR_TOOBIG      = 3;

        // Node kinds
        const int RXK_LITERAL  = 0;
        const int RXK_ANY      = 1;
        const int RXK_CLASS    = 2;
        const int RXK_SPLIT    = 3;
        const int RXK_JUMP     = 4;
        const int RXK_SAVE     = 5;
        const int RXK_MATCH    = 6;
        const int RXK_BOL      = 7;
        const int RXK_EOL      = 8;

        // ====================================================================
        // CHARACTER CLASS BITVECTOR
        // ====================================================================

        def rx_bit_set(byte* bits, byte ch) -> void
        {
            int i = (int)ch / 8;
            int b = (int)ch % 8;
            bits[i] = bits[i] | (byte)(1 << b);
        };

        def rx_bit_test(byte* bits, byte ch) -> bool
        {
            int i = (int)ch / 8;
            int b = (int)ch % 8;
            return (bits[i] & (byte)(1 << b)) != (byte)0;
        };

        def rx_bit_range(byte* bits, byte lo, byte hi) -> void
        {
            byte c = lo;
            while (true)
            {
                rx_bit_set(bits, c);
                if (c == hi) { break; };
                c = c + (byte)1;
            };
        };

        def rx_bits_zero(byte* bits) -> void
        {
            int i = 0;
            while (i < RX_CLASS_BYTES) { bits[i] = (byte)0; i++; };
        };

        def rx_fill_digit(byte* bits) -> void
        {
            rx_bit_range(bits, '0', '9');
        };

        def rx_fill_word(byte* bits) -> void
        {
            rx_bit_range(bits, 'a', 'z');
            rx_bit_range(bits, 'A', 'Z');
            rx_bit_range(bits, '0', '9');
            rx_bit_set(bits, '_');
        };

        def rx_fill_space(byte* bits) -> void
        {
            rx_bit_set(bits, ' ');
            rx_bit_set(bits, '\t');
            rx_bit_set(bits, '\n');
            rx_bit_set(bits, '\r');
            rx_bit_set(bits, (byte)11);
            rx_bit_set(bits, (byte)12);
        };

        def rx_fill_nondigit(byte* bits) -> void
        {
            byte c = (byte)0;
            while (true)
            {
                if (c < '0' | c > '9') { rx_bit_set(bits, c); };
                if (c == (byte)255) { break; };
                c = c + (byte)1;
            };
        };

        def rx_fill_nonword(byte* bits) -> void
        {
            byte c = (byte)0;
            while (true)
            {
                bool w = (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z') |
                         (c >= '0' & c <= '9') | (c == '_');
                if (!w) { rx_bit_set(bits, c); };
                if (c == (byte)255) { break; };
                c = c + (byte)1;
            };
        };

        def rx_fill_nonspace(byte* bits) -> void
        {
            byte c = (byte)0;
            while (true)
            {
                bool sp = (c == ' ') | (c == '\t') | (c == '\n') | (c == '\r') |
                          (c == (byte)11) | (c == (byte)12);
                if (!sp) { rx_bit_set(bits, c); };
                if (c == (byte)255) { break; };
                c = c + (byte)1;
            };
        };

        // ====================================================================
        // COMPILER HELPERS
        // ====================================================================

        def rxc_peek(RxC* c) -> byte
        {
            if (c.pos >= c.len) { return (byte)0; };
            return c.pat[c.pos];
        };

        def rxc_eat(RxC* c) -> byte
        {
            if (c.pos >= c.len) { return (byte)0; };
            byte ch = c.pat[c.pos];
            c.pos++;
            return ch;
        };

        def rxc_node(RxC* c) -> int
        {
            if (c.nc >= RX_MAX_NODES)
            {
                c.err = RX_ERR_TOOBIG;
                c.errmsg = "Pattern too complex\0";
                return -1;
            };
            int idx = c.nc;
            c.nodes[idx].kind      = RXK_LITERAL;
            c.nodes[idx].value     = (byte)0;
            c.nodes[idx].neg       = false;
            c.nodes[idx].bits      = (byte*)0;
            c.nodes[idx].out1      = -1;
            c.nodes[idx].out2      = -1;
            c.nodes[idx].save_slot = -1;
            c.nc++;
            return idx;
        };

        def rxc_int(RxC* c) -> int
        {
            int v = 0;
            bool got = false;
            while (c.pos < c.len)
            {
                byte ch = rxc_peek(c);
                if (ch >= '0' & ch <= '9')
                {
                    v = v * 10 + (int)(ch - '0');
                    rxc_eat(c);
                    got = true;
                }
                else { break; };
            };
            if (!got) { return -1; };
            return v;
        };

        // Allocate and zero a class bitvector
        def rxc_alloc_bits(RxC* c) -> byte*
        {
            byte* bits = (byte*)malloc((u64)RX_CLASS_BYTES);
            if (bits == (byte*)0)
            {
                c.err    = RX_ERR_NOMEM;
                c.errmsg = "Out of memory\0";
                return (byte*)0;
            };
            rx_bits_zero(bits);
            return bits;
        };

        // Fill bits from a \X escape sequence
        def rxc_escape_to_bits(byte esc, byte* bits) -> bool
        {
            if (esc == 'd') { rx_fill_digit(bits);    return true; };
            if (esc == 'D') { rx_fill_nondigit(bits); return true; };
            if (esc == 'w') { rx_fill_word(bits);     return true; };
            if (esc == 'W') { rx_fill_nonword(bits);  return true; };
            if (esc == 's') { rx_fill_space(bits);    return true; };
            if (esc == 'S') { rx_fill_nonspace(bits); return true; };
            return false;
        };

        // Resolve a single escape to its literal byte value
        def rxc_escape_byte(byte esc) -> byte
        {
            if (esc == 'n') { return '\n'; };
            if (esc == 't') { return '\t'; };
            if (esc == 'r') { return '\r'; };
            return esc;
        };

        // ====================================================================
        // FORWARD DECLARATIONS
        // ====================================================================
        def rxc_alt   (RxC* c, int* s, int* e) -> bool;
        def rxc_concat(RxC* c, int* s, int* e) -> bool;
        def rxc_quant (RxC* c, int* s, int* e) -> bool;
        def rxc_atom  (RxC* c, int* s, int* e) -> bool;

        // ====================================================================
        // CHARACTER CLASS  [...]
        // ====================================================================
        def rxc_class(RxC* c, int* out) -> bool
        {
            rxc_eat(c); // consume '['

            int n = rxc_node(c);
            if (n < 0) { return false; };
            c.nodes[n].kind = RXK_CLASS;

            byte* bits = rxc_alloc_bits(c);
            if (bits == (byte*)0) { return false; };
            c.nodes[n].bits = bits;

            if (rxc_peek(c) == '^')
            {
                c.nodes[n].neg = true;
                rxc_eat(c);
            };

            bool first = true;
            while (c.pos < c.len)
            {
                byte ch = rxc_peek(c);

                // ']' closes the class (but not if it's the very first char)
                if (ch == ']' & !first) { rxc_eat(c); break; };
                first = false;

                if (ch == '\\')
                {
                    rxc_eat(c);
                    byte esc = rxc_eat(c);
                    if (!rxc_escape_to_bits(esc, bits))
                    {
                        rx_bit_set(bits, rxc_escape_byte(esc));
                    };
                }
                else
                {
                    rxc_eat(c);
                    // Check for a-z range
                    if (rxc_peek(c) == '-' & c.pos + 1 < c.len & c.pat[c.pos + 1] != ']')
                    {
                        rxc_eat(c); // consume '-'
                        byte hi = rxc_eat(c);
                        if (hi >= ch)
                        {
                            rx_bit_range(bits, ch, hi);
                        }
                        else
                        {
                            rx_bit_set(bits, ch);
                            rx_bit_set(bits, '-');
                            rx_bit_set(bits, hi);
                        };
                    }
                    else
                    {
                        rx_bit_set(bits, ch);
                    };
                };
            };

            *out = n;
            return true;
        };

        // ====================================================================
        // ATOM
        // ====================================================================
        def rxc_atom(RxC* c, int* s, int* e) -> bool
        {
            byte ch = rxc_peek(c);

            if (ch == '^')
            {
                rxc_eat(c);
                int n = rxc_node(c); if (n < 0) { return false; };
                c.nodes[n].kind = RXK_BOL;
                *s = n; *e = n;
                return true;
            };

            if (ch == '$')
            {
                rxc_eat(c);
                int n = rxc_node(c); if (n < 0) { return false; };
                c.nodes[n].kind = RXK_EOL;
                *s = n; *e = n;
                return true;
            };

            if (ch == '.')
            {
                rxc_eat(c);
                int n = rxc_node(c); if (n < 0) { return false; };
                c.nodes[n].kind = RXK_ANY;
                *s = n; *e = n;
                return true;
            };

            if (ch == '[')
            {
                int n = 0;
                if (!rxc_class(c, @n)) { return false; };
                *s = n; *e = n;
                return true;
            };

            if (ch == '\\')
            {
                rxc_eat(c);
                byte esc = rxc_eat(c);
                if (esc == (byte)0)
                {
                    c.err    = RX_ERR_BADPATTERN;
                    c.errmsg = "Trailing backslash\0";
                    return false;
                };
                int n = rxc_node(c); if (n < 0) { return false; };

                byte* bits = rxc_alloc_bits(c);
                if (bits == (byte*)0) { return false; };

                if (rxc_escape_to_bits(esc, bits))
                {
                    c.nodes[n].kind = RXK_CLASS;
                    c.nodes[n].bits = bits;
                }
                else
                {
                    free(bits);
                    c.nodes[n].kind  = RXK_LITERAL;
                    c.nodes[n].value = rxc_escape_byte(esc);
                };
                *s = n; *e = n;
                return true;
            };

            if (ch == '(')
            {
                rxc_eat(c);
                if (c.gc >= RX_MAX_GROUPS)
                {
                    c.err    = RX_ERR_TOOBIG;
                    c.errmsg = "Too many capture groups\0";
                    return false;
                };
                int gi = c.gc;
                c.gc++;

                int open = rxc_node(c); if (open < 0) { return false; };
                c.nodes[open].kind      = RXK_SAVE;
                c.nodes[open].save_slot = gi * 2;

                int ix = 0; int ie = 0;
                if (!rxc_alt(c, @ix, @ie)) { return false; };

                if (rxc_peek(c) != ')')
                {
                    c.err    = RX_ERR_BADPATTERN;
                    c.errmsg = "Missing ')'\0";
                    return false;
                };
                rxc_eat(c);

                int close = rxc_node(c); if (close < 0) { return false; };
                c.nodes[close].kind      = RXK_SAVE;
                c.nodes[close].save_slot = gi * 2 + 1;

                c.nodes[open].out1 = ix;
                c.nodes[ie].out1   = close;

                *s = open; *e = close;
                return true;
            };

            // Plain literal
            if (ch == (byte)0 | ch == '|' | ch == ')' | ch == '*' |
                ch == '+' | ch == '?' | ch == '{')
            {
                c.err    = RX_ERR_BADPATTERN;
                c.errmsg = "Unexpected metacharacter where atom expected\0";
                return false;
            };

            rxc_eat(c);
            int n = rxc_node(c); if (n < 0) { return false; };
            c.nodes[n].kind  = RXK_LITERAL;
            c.nodes[n].value = ch;
            *s = n; *e = n;
            return true;
        };

        // ====================================================================
        // QUANTIFIER  atom[*+?{n,m}]
        // ====================================================================
        def rxc_quant(RxC* c, int* s, int* e) -> bool
        {
            int ax = 0; int ae = 0;
            if (!rxc_atom(c, @ax, @ae)) { return false; };

            byte q = rxc_peek(c);

            if (q == '*')
            {
                rxc_eat(c);
                // split(atom, exit) -- atom loops back to split
                int sp = rxc_node(c); if (sp < 0) { return false; };
                c.nodes[sp].kind = RXK_SPLIT;
                c.nodes[sp].out1 = ax;   // greedy: try atom first
                c.nodes[sp].out2 = -1;   // exit (dangling)
                c.nodes[ae].out1 = sp;   // atom tail -> split
                *s = sp; *e = sp;        // e.out2 is the exit
                return true;
            };

            if (q == '+')
            {
                rxc_eat(c);
                // atom  then  split(atom, exit)
                int sp = rxc_node(c); if (sp < 0) { return false; };
                c.nodes[sp].kind = RXK_SPLIT;
                c.nodes[sp].out1 = ax;  // loop
                c.nodes[sp].out2 = -1;  // exit (dangling)
                c.nodes[ae].out1 = sp;
                *s = ax; *e = sp;       // e.out2 dangling
                return true;
            };

            if (q == '?')
            {
                rxc_eat(c);
                // split(atom, join)  atom->join
                int sp = rxc_node(c); if (sp < 0) { return false; };
                int jn = rxc_node(c); if (jn < 0) { return false; };
                c.nodes[sp].kind = RXK_SPLIT;
                c.nodes[sp].out1 = ax;
                c.nodes[sp].out2 = jn;
                c.nodes[jn].kind = RXK_JUMP;
                c.nodes[jn].out1 = -1;  // dangling
                c.nodes[ae].out1 = jn;
                *s = sp; *e = jn;
                return true;
            };

            if (q == '{')
            {
                rxc_eat(c);
                int mn = rxc_int(c);
                if (mn < 0) { mn = 0; };
                int mx = mn;
                if (rxc_peek(c) == ',')
                {
                    rxc_eat(c);
                    if (rxc_peek(c) == '}') { mx = -1; }
                    else
                    {
                        mx = rxc_int(c);
                        if (mx < 0) { mx = mn; };
                    };
                };
                if (rxc_peek(c) != '}')
                {
                    c.err    = RX_ERR_BADPATTERN;
                    c.errmsg = "Expected '}'\0";
                    return false;
                };
                rxc_eat(c);

                // Build mandatory chain (mn copies sharing the atom subgraph via JUMP)
                int cs = ax; int ce = ae;
                int i = 1;
                while (i < mn)
                {
                    int jn = rxc_node(c); if (jn < 0) { return false; };
                    c.nodes[jn].kind = RXK_JUMP;
                    c.nodes[jn].out1 = ax;
                    c.nodes[ce].out1 = jn;
                    ce = ae;
                    i++;
                };

                if (mx == -1)
                {
                    // Unbounded tail: split(atom, exit)
                    int sp = rxc_node(c); if (sp < 0) { return false; };
                    c.nodes[sp].kind = RXK_SPLIT;
                    c.nodes[sp].out1 = ax;
                    c.nodes[sp].out2 = -1;
                    c.nodes[ce].out1 = sp;
                    *s = cs; *e = sp;
                }
                else
                {
                    // (mx-mn) optional copies
                    int opt = mx - mn;
                    int last = ce;
                    int oi = 0;
                    while (oi < opt)
                    {
                        int sp = rxc_node(c); if (sp < 0) { return false; };
                        int jn = rxc_node(c); if (jn < 0) { return false; };
                        c.nodes[sp].kind = RXK_SPLIT;
                        c.nodes[sp].out1 = ax;
                        c.nodes[sp].out2 = jn;
                        c.nodes[jn].kind = RXK_JUMP;
                        c.nodes[jn].out1 = -1;
                        c.nodes[last].out1 = sp;
                        c.nodes[ae].out1   = jn;
                        last = jn;
                        oi++;
                    };
                    *s = cs; *e = last;
                };
                return true;
            };

            *s = ax; *e = ae;
            return true;
        };

        // ====================================================================
        // CONCATENATION
        // ====================================================================
        def rxc_concat(RxC* c, int* s, int* e) -> bool
        {
            byte ch = rxc_peek(c);
            if (ch == (byte)0 | ch == '|' | ch == ')')
            {
                // Empty -- epsilon via JUMP
                int n = rxc_node(c); if (n < 0) { return false; };
                c.nodes[n].kind = RXK_JUMP;
                *s = n; *e = n;
                return true;
            };

            int cs = 0; int ce = 0;
            if (!rxc_quant(c, @cs, @ce)) { return false; };

            while (true)
            {
                ch = rxc_peek(c);
                if (ch == (byte)0 | ch == '|' | ch == ')') { break; };
                int ns = 0; int ne = 0;
                if (!rxc_quant(c, @ns, @ne)) { return false; };
                c.nodes[ce].out1 = ns;
                ce = ne;
            };

            *s = cs; *e = ce;
            return true;
        };

        // ====================================================================
        // ALTERNATION
        // ====================================================================
        def rxc_alt(RxC* c, int* s, int* e) -> bool
        {
            int ls = 0; int le = 0;
            if (!rxc_concat(c, @ls, @le)) { return false; };

            if (rxc_peek(c) != '|')
            {
                *s = ls; *e = le;
                return true;
            };

            // Join node that all branches feed into
            int jn = rxc_node(c); if (jn < 0) { return false; };
            c.nodes[jn].kind = RXK_JUMP;
            c.nodes[jn].out1 = -1;
            c.nodes[le].out1 = jn;

            // First split
            int sp = rxc_node(c); if (sp < 0) { return false; };
            c.nodes[sp].kind = RXK_SPLIT;
            c.nodes[sp].out1 = ls;
            c.nodes[sp].out2 = -1; // will be patched

            int prev_sp = sp;

            while (rxc_peek(c) == '|')
            {
                rxc_eat(c);
                int rs = 0; int re = 0;
                if (!rxc_concat(c, @rs, @re)) { return false; };
                c.nodes[re].out1 = jn;

                if (rxc_peek(c) == '|')
                {
                    // Chain another split for additional alternatives
                    int nsp = rxc_node(c); if (nsp < 0) { return false; };
                    c.nodes[nsp].kind = RXK_SPLIT;
                    c.nodes[nsp].out1 = rs;
                    c.nodes[nsp].out2 = -1;
                    c.nodes[prev_sp].out2 = nsp;
                    prev_sp = nsp;
                }
                else
                {
                    c.nodes[prev_sp].out2 = rs;
                };
            };

            *s = sp; *e = jn;
            return true;
        };

        // ====================================================================
        // REGEX OBJECT
        // ====================================================================
        object Regex
        {
            RxNode* nodes;
            int     nc;
            int     gc;
            int     root;
            int     err;
            byte*   errmsg;
            bool    ok;

            // ----------------------------------------------------------------
            def __init() -> this
            {
                this.nodes  = (RxNode*)0;
                this.nc     = 0;
                this.gc     = 0;
                this.root   = -1;
                this.err    = RX_OK;
                this.errmsg = (byte*)0;
                this.ok     = false;
                return this;
            };

            def __init(byte* pattern) -> this
            {
                this.nodes  = (RxNode*)0;
                this.nc     = 0;
                this.gc     = 0;
                this.root   = -1;
                this.err    = RX_OK;
                this.errmsg = (byte*)0;
                this.ok     = false;
                this.compile(pattern);
                return this;
            };

            def __exit() -> void
            {
                this.release();
                return;
            };

            def release() -> void
            {
                if (this.nodes == (RxNode*)0) { return; };
                int i = 0;
                while (i < this.nc)
                {
                    if (this.nodes[i].bits != (byte*)0)
                    {
                        free(this.nodes[i].bits);
                        this.nodes[i].bits = (byte*)0;
                    };
                    i++;
                };
                free(this.nodes);
                this.nodes = (RxNode*)0;
                this.nc    = 0;
                this.ok    = false;
            };

            // ----------------------------------------------------------------
            // compile
            // ----------------------------------------------------------------
            def compile(byte* pattern) -> bool
            {
                this.release();
                this.err    = RX_OK;
                this.errmsg = (byte*)0;
                this.gc     = 0;

                int plen = 0;
                while (pattern[plen] != (byte)0) { plen++; };

                this.nodes = (RxNode*)malloc((u64)(sizeof(RxNode) * RX_MAX_NODES));
                if (this.nodes == (RxNode*)0)
                {
                    this.err    = RX_ERR_NOMEM;
                    this.errmsg = "Out of memory\0";
                    return false;
                };

                RxC c;
                c.pat    = pattern;
                c.pos    = 0;
                c.len    = plen;
                c.nodes  = this.nodes;
                c.nc     = 0;
                c.gc     = 0;
                c.err    = RX_OK;
                c.errmsg = (byte*)0;

                int rs = 0; int re = 0;
                bool compiled = rxc_alt(@c, @rs, @re);

                this.nc  = c.nc;
                this.gc  = c.gc;
                this.err = c.err;
                this.errmsg = c.errmsg;

                if (!compiled)
                {
                    this.release();
                    return false;
                };

                // Attach MATCH node
                int mn = rxc_node(@c);
                if (mn < 0)
                {
                    this.nc = c.nc;
                    this.release();
                    return false;
                };
                this.nc = c.nc;
                this.nodes[mn].kind  = RXK_MATCH;
                this.nodes[re].out1  = mn;
                this.root = rs;
                this.ok   = true;
                return true;
            };

            // ----------------------------------------------------------------
            // Internal: does a node consume a character?
            // ----------------------------------------------------------------
            def node_consumes(int nid) -> bool
            {
                int k = this.nodes[nid].kind;
                return k == RXK_LITERAL | k == RXK_ANY | k == RXK_CLASS;
            };

            // ----------------------------------------------------------------
            // Internal: does node match byte ch?
            // ----------------------------------------------------------------
            def node_match_ch(int nid, byte ch) -> bool
            {
                int k = this.nodes[nid].kind;
                if (k == RXK_LITERAL) { return ch == this.nodes[nid].value; };
                if (k == RXK_ANY)     { return ch != '\n'; };
                if (k == RXK_CLASS)
                {
                    bool hit = rx_bit_test(this.nodes[nid].bits, ch);
                    if (this.nodes[nid].neg) { return !hit; };
                    return hit;
                };
                return false;
            };

            // ----------------------------------------------------------------
            // run_at: try to match at subject[start_pos]
            // ----------------------------------------------------------------
            def run_at(byte* subj, int slen, int start, RegexMatch* m) -> bool
            {
                // Allocate two thread pools on heap
                u64 pool_bytes = (u64)(sizeof(RxThread) * RX_MAX_THREADS);
                RxThread* cur  = (RxThread*)malloc(pool_bytes);
                RxThread* nxt  = (RxThread*)malloc(pool_bytes);
                int* vis       = (int*)malloc((u64)(sizeof(int) * this.nc));

                if (cur == (RxThread*)0 | nxt == (RxThread*)0 | vis == (int*)0)
                {
                    if (cur != (RxThread*)0) { free(cur); };
                    if (nxt != (RxThread*)0) { free(nxt); };
                    if (vis != (int*)0)      { free(vis); };
                    return false;
                };

                int epoch = 0;
                int vi = 0;
                while (vi < this.nc) { vis[vi] = -1; vi++; };

                // Best match tracking
                bool best_ok     = false;
                int  best_end    = -1;
                int[32]  best_saves;
                int  bsi = 0;
                while (bsi < 32) { best_saves[bsi] = -1; bsi++; };

                // Seed first thread
                int cur_n = 0;
                cur[0].node = this.root;
                int si = 0;
                while (si < 32) { cur[0].saves[si] = -1; si++; };
                cur_n = 1;

                int pos = start;
                bool running = true;

                while (running)
                {
                    // ---- epsilon closure ----
                    // Re-use vis to track which nodes are already in cur
                    vi = 0; while (vi < this.nc) { vis[vi] = epoch; vi++; }; epoch++;

                    int qi = 0;
                    while (qi < cur_n)
                    {
                        int nid = cur[qi].node;
                        if (nid < 0 | nid >= this.nc) { qi++; continue; };
                        int k = this.nodes[nid].kind;

                        if (k == RXK_MATCH)
                        {
                            if (!best_ok | pos > best_end)
                            {
                                best_ok  = true;
                                best_end = pos;
                                int cpi = 0;
                                while (cpi < 32)
                                {
                                    best_saves[cpi] = cur[qi].saves[cpi];
                                    cpi++;
                                };
                            };
                            qi++; continue;
                        };

                        if (k == RXK_JUMP)
                        {
                            int o1 = this.nodes[nid].out1;
                            if (o1 >= 0 & vis[o1] != epoch & cur_n < RX_MAX_THREADS)
                            {
                                vis[o1] = epoch;
                                cur[cur_n].node = o1;
                                int cpi = 0;
                                while (cpi < 32) { cur[cur_n].saves[cpi] = cur[qi].saves[cpi]; cpi++; };
                                cur_n++;
                            };
                            qi++; continue;
                        };

                        if (k == RXK_SPLIT)
                        {
                            int o1 = this.nodes[nid].out1;
                            int o2 = this.nodes[nid].out2;
                            if (o1 >= 0 & vis[o1] != epoch & cur_n < RX_MAX_THREADS)
                            {
                                vis[o1] = epoch;
                                cur[cur_n].node = o1;
                                int cpi = 0;
                                while (cpi < 32) { cur[cur_n].saves[cpi] = cur[qi].saves[cpi]; cpi++; };
                                cur_n++;
                            };
                            if (o2 >= 0 & vis[o2] != epoch & cur_n < RX_MAX_THREADS)
                            {
                                vis[o2] = epoch;
                                cur[cur_n].node = o2;
                                int cpi = 0;
                                while (cpi < 32) { cur[cur_n].saves[cpi] = cur[qi].saves[cpi]; cpi++; };
                                cur_n++;
                            };
                            qi++; continue;
                        };

                        if (k == RXK_SAVE)
                        {
                            int slot = this.nodes[nid].save_slot;
                            int o1   = this.nodes[nid].out1;
                            if (o1 >= 0 & vis[o1] != epoch & cur_n < RX_MAX_THREADS)
                            {
                                vis[o1] = epoch;
                                cur[cur_n].node = o1;
                                int cpi = 0;
                                while (cpi < 32) { cur[cur_n].saves[cpi] = cur[qi].saves[cpi]; cpi++; };
                                if (slot >= 0 & slot < 32) { cur[cur_n].saves[slot] = pos; };
                                cur_n++;
                            };
                            qi++; continue;
                        };

                        if (k == RXK_BOL)
                        {
                            bool at = (pos == 0) | (pos > 0 & subj[pos - 1] == '\n');
                            int o1  = this.nodes[nid].out1;
                            if (at & o1 >= 0 & vis[o1] != epoch & cur_n < RX_MAX_THREADS)
                            {
                                vis[o1] = epoch;
                                cur[cur_n].node = o1;
                                int cpi = 0;
                                while (cpi < 32) { cur[cur_n].saves[cpi] = cur[qi].saves[cpi]; cpi++; };
                                cur_n++;
                            };
                            qi++; continue;
                        };

                        if (k == RXK_EOL)
                        {
                            bool at = (pos >= slen) | (pos < slen & subj[pos] == '\n');
                            int o1  = this.nodes[nid].out1;
                            if (at & o1 >= 0 & vis[o1] != epoch & cur_n < RX_MAX_THREADS)
                            {
                                vis[o1] = epoch;
                                cur[cur_n].node = o1;
                                int cpi = 0;
                                while (cpi < 32) { cur[cur_n].saves[cpi] = cur[qi].saves[cpi]; cpi++; };
                                cur_n++;
                            };
                            qi++; continue;
                        };

                        // Consuming node -- stays as-is for the character step
                        qi++;
                    };

                    if (pos >= slen) { running = false; break; };

                    // ---- consume one character ----
                    byte ch   = subj[pos];
                    int nxt_n = 0;

                    qi = 0;
                    while (qi < cur_n)
                    {
                        int nid = cur[qi].node;
                        if (nid >= 0 & nid < this.nc)
                        {
                            if (this.node_consumes(nid) & this.node_match_ch(nid, ch))
                            {
                                int o1 = this.nodes[nid].out1;
                                if (o1 >= 0 & nxt_n < RX_MAX_THREADS)
                                {
                                    nxt[nxt_n].node = o1;
                                    int cpi = 0;
                                    while (cpi < 32) { nxt[nxt_n].saves[cpi] = cur[qi].saves[cpi]; cpi++; };
                                    nxt_n++;
                                };
                            };
                        };
                        qi++;
                    };

                    pos++;

                    if (nxt_n == 0) { running = false; break; };

                    // Swap pools
                    RxThread* tmp = cur;
                    cur   = nxt;
                    nxt   = tmp;
                    cur_n = nxt_n;
                };

                if (best_ok)
                {
                    m.matched     = true;
                    m.start       = start;
                    m.end         = best_end;
                    m.group_count = this.gc;
                    int gi = 0;
                    while (gi < this.gc & gi < RX_MAX_GROUPS)
                    {
                        m.groups[gi].start = best_saves[gi * 2];
                        m.groups[gi].end   = best_saves[gi * 2 + 1];
                        gi++;
                    };
                };

                free(cur); free(nxt); free(vis);
                return best_ok;
            };

            // ----------------------------------------------------------------
            // match -- first match anywhere in subject
            // ----------------------------------------------------------------
            def match(byte* subj, RegexMatch* m) -> bool
            {
                if (!this.ok) { return false; };
                m.matched = false; m.group_count = 0;
                int slen = 0;
                while (subj[slen] != (byte)0) { slen++; };
                int i = 0;
                while (i <= slen)
                {
                    if (this.run_at(subj, slen, i, m)) { return true; };
                    i++;
                };
                return false;
            };

            // match on string object
            def match(string* subj, RegexMatch* m) -> bool
            {
                return this.match(subj.val(), m);
            };

            // ----------------------------------------------------------------
            // match_at -- anchored at offset
            // ----------------------------------------------------------------
            def match_at(byte* subj, int offset, RegexMatch* m) -> bool
            {
                if (!this.ok) { return false; };
                m.matched = false; m.group_count = 0;
                int slen = 0;
                while (subj[slen] != (byte)0) { slen++; };
                return this.run_at(subj, slen, offset, m);
            };

            def match_at(string* subj, int offset, RegexMatch* m) -> bool
            {
                return this.match_at(subj.val(), offset, m);
            };

            // ----------------------------------------------------------------
            // match_full -- must span the entire subject
            // ----------------------------------------------------------------
            def match_full(byte* subj, RegexMatch* m) -> bool
            {
                if (!this.ok) { return false; };
                m.matched = false; m.group_count = 0;
                int slen = 0;
                while (subj[slen] != (byte)0) { slen++; };
                if (!this.run_at(subj, slen, 0, m)) { return false; };
                if (m.start != 0 | m.end != slen) { m.matched = false; return false; };
                return true;
            };

            def match_full(string* subj, RegexMatch* m) -> bool
            {
                return this.match_full(subj.val(), m);
            };

            // ----------------------------------------------------------------
            // test -- true if matches anywhere
            // ----------------------------------------------------------------
            def test(byte* subj) -> bool
            {
                RegexMatch m;
                return this.match(subj, @m);
            };

            def test(string* subj) -> bool
            {
                return this.test(subj.val());
            };

            // ----------------------------------------------------------------
            // find_all -- all non-overlapping matches, returns count
            // ----------------------------------------------------------------
            def find_all(byte* subj, RegexMatch* out, int max) -> int
            {
                if (!this.ok) { return 0; };
                int slen = 0;
                while (subj[slen] != (byte)0) { slen++; };
                int count = 0;
                int pos   = 0;
                while (pos <= slen & count < max)
                {
                    RegexMatch m;
                    m.matched = false;
                    if (this.run_at(subj, slen, pos, @m))
                    {
                        out[count] = m;
                        count++;
                        if (m.end > pos) { pos = m.end; }
                        else             { pos++;        };
                    }
                    else { pos++; };
                };
                return count;
            };

            def find_all(string* subj, RegexMatch* out, int max) -> int
            {
                return this.find_all(subj.val(), out, max);
            };

            // ----------------------------------------------------------------
            // expand_replacement -- expand \0..\9 backrefs in repl string.
            // Returns heap string; caller frees.
            // ----------------------------------------------------------------
            def expand_repl(byte* subj, byte* repl, int rlen, RegexMatch* m) -> byte*
            {
                // Measure output
                int olen = 0;
                int ri = 0;
                while (ri < rlen)
                {
                    if (repl[ri] == '\\' & ri + 1 < rlen)
                    {
                        byte nx = repl[ri + 1];
                        if (nx == '0')
                        {
                            olen += m.end - m.start;
                            ri += 2;
                        }
                        elif (nx >= '1' & nx <= '9')
                        {
                            int gi = (int)(nx - '1');
                            if (gi < m.group_count & m.groups[gi].start >= 0)
                            {
                                olen += m.groups[gi].end - m.groups[gi].start;
                            };
                            ri += 2;
                        }
                        else
                        {
                            olen++;
                            ri += 2;
                        };
                    }
                    else { olen++; ri++; };
                };

                byte* out = (byte*)malloc((u64)(olen + 1));
                if (out == (byte*)0) { return (byte*)0; };

                int oi = 0;
                ri = 0;
                while (ri < rlen)
                {
                    if (repl[ri] == '\\' & ri + 1 < rlen)
                    {
                        byte nx = repl[ri + 1];
                        if (nx == '0')
                        {
                            int p = m.start;
                            while (p < m.end) { out[oi] = subj[p]; oi++; p++; };
                            ri += 2;
                        }
                        elif (nx >= '1' & nx <= '9')
                        {
                            int gi = (int)(nx - '1');
                            if (gi < m.group_count & m.groups[gi].start >= 0)
                            {
                                int p = m.groups[gi].start;
                                while (p < m.groups[gi].end) { out[oi] = subj[p]; oi++; p++; };
                            };
                            ri += 2;
                        }
                        else
                        {
                            out[oi] = nx; oi++;
                            ri += 2;
                        };
                    }
                    else { out[oi] = repl[ri]; oi++; ri++; };
                };
                out[oi] = (byte)0;
                return out;
            };

            // ----------------------------------------------------------------
            // replace -- first match; returns heap string, caller frees
            // ----------------------------------------------------------------
            def replace(byte* subj, byte* repl) -> byte*
            {
                if (!this.ok) { return (byte*)0; };
                int slen = 0; while (subj[slen] != (byte)0) { slen++; };
                int rlen = 0; while (repl[rlen] != (byte)0) { rlen++; };

                RegexMatch m; m.matched = false;
                if (!this.match(subj, @m))
                {
                    // No match: return copy
                    byte* cp = (byte*)malloc((u64)(slen + 1));
                    if (cp == (byte*)0) { return (byte*)0; };
                    int ci = 0; while (ci < slen) { cp[ci] = subj[ci]; ci++; };
                    cp[slen] = (byte)0;
                    return cp;
                };

                byte* exp = this.expand_repl(subj, repl, rlen, @m);
                if (exp == (byte*)0) { return (byte*)0; };
                int elen = 0; while (exp[elen] != (byte)0) { elen++; };

                int olen = m.start + elen + (slen - m.end);
                byte* out = (byte*)malloc((u64)(olen + 1));
                if (out == (byte*)0) { free(exp); return (byte*)0; };

                int oi = 0;
                int i  = 0; while (i < m.start) { out[oi] = subj[i]; oi++; i++; };
                i = 0;      while (i < elen)     { out[oi] = exp[i];  oi++; i++; };
                i = m.end;  while (i < slen)      { out[oi] = subj[i]; oi++; i++; };
                out[oi] = (byte)0;

                free(exp);
                return out;
            };

            def replace(string* subj, byte* repl) -> byte*
            {
                return this.replace(subj.val(), repl);
            };

            // ----------------------------------------------------------------
            // replace_all -- all matches; returns heap string, caller frees
            // ----------------------------------------------------------------
            def replace_all(byte* subj, byte* repl) -> byte*
            {
                if (!this.ok) { return (byte*)0; };
                int slen = 0; while (subj[slen] != (byte)0) { slen++; };
                int rlen = 0; while (repl[rlen] != (byte)0) { rlen++; };

                RegexMatch[256] matches;
                int count = this.find_all(subj, @matches[0], 256);

                if (count == 0)
                {
                    byte* cp = (byte*)malloc((u64)(slen + 1));
                    if (cp == (byte*)0) { return (byte*)0; };
                    int ci = 0; while (ci < slen) { cp[ci] = subj[ci]; ci++; };
                    cp[slen] = (byte)0;
                    return cp;
                };

                // Measure output length
                int olen = slen;
                int mi = 0;
                while (mi < count)
                {
                    byte* exp = this.expand_repl(subj, repl, rlen, @matches[mi]);
                    if (exp != (byte*)0)
                    {
                        int elen = 0; while (exp[elen] != (byte)0) { elen++; };
                        olen = olen - (matches[mi].end - matches[mi].start) + elen;
                        free(exp);
                    };
                    mi++;
                };

                byte* out = (byte*)malloc((u64)(olen + 2));
                if (out == (byte*)0) { return (byte*)0; };

                int oi   = 0;
                int spos = 0;
                mi = 0;
                while (mi < count)
                {
                    while (spos < matches[mi].start) { out[oi] = subj[spos]; oi++; spos++; };
                    byte* exp = this.expand_repl(subj, repl, rlen, @matches[mi]);
                    if (exp != (byte*)0)
                    {
                        int ei = 0; while (exp[ei] != (byte)0) { out[oi] = exp[ei]; oi++; ei++; };
                        free(exp);
                    };
                    spos = matches[mi].end;
                    if (spos <= matches[mi].start) { spos++; };
                    mi++;
                };
                while (spos < slen) { out[oi] = subj[spos]; oi++; spos++; };
                out[oi] = (byte)0;
                return out;
            };

            def replace_all(string* subj, byte* repl) -> byte*
            {
                return this.replace_all(subj.val(), repl);
            };

            // ----------------------------------------------------------------
            // Accessors
            // ----------------------------------------------------------------
            def is_valid() -> bool     { return this.ok; };
            def error_code() -> int    { return this.err; };
            def error_msg() -> byte*
            {
                if (this.errmsg != (byte*)0) { return this.errmsg; };
                return "No error\0";
            };
        };

        // ====================================================================
        // CONVENIENCE FREE FUNCTIONS
        // ====================================================================

        def rx_test(byte* pattern, byte* subj) -> bool
        {
            Regex re; re.__init(pattern);
            if (!re.is_valid()) { re.__exit(); return false; };
            bool r = re.test(subj);
            re.__exit();
            return r;
        };

        def rx_match(byte* pattern, byte* subj, RegexMatch* m) -> bool
        {
            Regex re; re.__init(pattern);
            if (!re.is_valid()) { re.__exit(); return false; };
            bool r = re.match(subj, m);
            re.__exit();
            return r;
        };

        // Caller must free the returned string
        def rx_replace(byte* pattern, byte* subj, byte* repl) -> byte*
        {
            Regex re; re.__init(pattern);
            if (!re.is_valid()) { re.__exit(); return (byte*)0; };
            byte* r = re.replace(subj, repl);
            re.__exit();
            return r;
        };

        // Caller must free the returned string
        def rx_replace_all(byte* pattern, byte* subj, byte* repl) -> byte*
        {
            Regex re; re.__init(pattern);
            if (!re.is_valid()) { re.__exit(); return (byte*)0; };
            byte* r = re.replace_all(subj, repl);
            re.__exit();
            return r;
        };

    };
};

using standard::regex;

#endif; // FLUX_STANDARD_REGEX
