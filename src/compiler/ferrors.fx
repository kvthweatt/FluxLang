// Author: Karac V. Thweatt
//
// ferrors.fx - Flux compiler diagnostics (port of ferrors.py)
//
// One place renders every user facing diagnostic of the bootstrap compiler:
//
//     header   "msg at line:col"        (line is file local, through the line map)
//     source   the offending line, tabs expanded to 4 columns
//     caret    "----^ ; expected here"  (a missing ; or , points at the end of the previous line)
//     fix      a suggested line ending in "  // try this", when one can be derived
//
// Colors follow ferrors._render_diagnostic: bold severity color for the message,
// cyan for the location, dim dashes, green for the hint and the suggested line.

#ifndef FLUX_ERRORS
#def FLUX_ERRORS 1;

#ifndef FLUX_STANDARD
#import <standard.fx>;
#endif;

#ifndef FLUX_LEXER
#import "flexer.fx";
#endif;

#ifndef FLUX_PREPROCESSOR
#import "fpreprocess.fx";
#endif;

using standard::io::console;
using flux::lexer;
using flux::preprocessor;

namespace flux
{
    namespace errors
    {
        // Severity
        const int SEV_ERROR = 0;
        const int SEV_WARNING = 1;

        const int DIAG_TAB_WIDTH = 4;

        // Set once by the driver; parsers created later (module files) start with it
        bool DIAG_COLOR_ON = false;

        // Warnings rendered so far, for --warn-as-error
        int WARN_COUNT = 0;

        // ===== COLOR =====

        diag_sgr(Buf* out, byte* code) -> void
        {
            out.put(27);
            out.put_str("[\0");
            out.put_str(code);
            out.put_str("m\0");
        };

        diag_sev_code(int sev) -> byte*
        {
            if (sev == SEV_WARNING) { -> g"93\0"; };
            -> g"91\0";
        };

        // ===== TOKEN SYMBOLS =====

        // ferrors._TOKEN_SYMBOL_MAP: the source text of a token type, or null
        sym_of(int t) -> byte*
        {
            switch (t)
            {
                case (TokenType.PLUS) { -> g"+\0"; }
                case (TokenType.MINUS) { -> g"-\0"; }
                case (TokenType.MULTIPLY) { -> g"*\0"; }
                case (TokenType.DIVIDE) { -> g"/\0"; }
                case (TokenType.MODULO) { -> g"%\0"; }
                case (TokenType.LESS_THAN) { -> g"<\0"; }
                case (TokenType.GREATER_THAN) { -> g">\0"; }
                case (TokenType.ASSIGN) { -> g"=\0"; }
                case (TokenType.LOGICAL_OR) { -> g"|\0"; }
                case (TokenType.LOGICAL_AND) { -> g"&\0"; }
                case (TokenType.BITXOR_OP) { -> g"^\0"; }
                case (TokenType.NOT) { -> g"!\0"; }
                case (TokenType.QUESTION) { -> g"?\0"; }
                case (TokenType.ADDRESS_OF) { -> g"@\0"; }
                case (TokenType.TIE) { -> g"~\0"; }
                case (TokenType.INCREMENT) { -> g"++\0"; }
                case (TokenType.DECREMENT) { -> g"--\0"; }
                case (TokenType.EQUAL) { -> g"==\0"; }
                case (TokenType.NOT_EQUAL) { -> g"!=\0"; }
                case (TokenType.LESS_EQUAL) { -> g"<=\0"; }
                case (TokenType.GREATER_EQUAL) { -> g">=\0"; }
                case (TokenType.NAND_OP) { -> g"!&\0"; }
                case (TokenType.NOR_OP) { -> g"!|\0"; }
                case (TokenType.XOR_OP) { -> g"^|\0"; }
                case (TokenType.BITSHIFT_LEFT) { -> g"<<\0"; }
                case (TokenType.BITSHIFT_RIGHT) { -> g">>\0"; }
                case (TokenType.BITNAND_OP) { -> g"`!&\0"; }
                case (TokenType.BITNOR_OP) { -> g"`!|\0"; }
                case (TokenType.BITXNAND) { -> g"`^|!&\0"; }
                case (TokenType.BITXNOR) { -> g"`^|!|\0"; }
                case (TokenType.LEFT_PAREN) { -> g"(\0"; }
                case (TokenType.RIGHT_PAREN) { -> g")\0"; }
                case (TokenType.LEFT_BRACE) { -> g"{\0"; }
                case (TokenType.RIGHT_BRACE) { -> g"}\0"; }
                case (TokenType.LEFT_BRACKET) { -> g"[\0"; }
                case (TokenType.RIGHT_BRACKET) { -> g"]\0"; }
                case (TokenType.SEMICOLON) { -> g";\0"; }
                case (TokenType.COLON) { -> g":\0"; }
                case (TokenType.COMMA) { -> g",\0"; }
                case (TokenType.DOT) { -> g".\0"; }
                case (TokenType.RETURN_ARROW) { -> g"->\0"; }
                case (TokenType.SCOPE) { -> g"::\0"; }
                case (TokenType.BACKSLASH) { -> g"\\\0"; }
                default { -> (byte*)0; };
            };
            -> (byte*)0;
        };

        // _END_OF_PREV_LINE_TYPES: the missing token belongs at the end of the previous line
        ends_prev_line(int t) -> bool -> t == TokenType.SEMICOLON | t == TokenType.COMMA;

        // ===== SOURCE LINES =====

        // Byte range [ls, le) of the 1-based line ln of src, without the line terminator
        line_bounds(byte* src, int n, int ln, int* ls, int* le) -> bool
        {
            int k = 1;
            int p = 0;
            int e;
            while (k < ln & p < n)
            {
                if (src[p] == 10) { k++; };
                p++;
            };
            if (k != ln) { -> false; };
            e = p;
            while (e < n & src[e] != 10 & src[e] != 13) { e++; };
            *ls = p;
            *le = e;
            -> true;
        };

        // _expand_tabs: appends raw[0..rn) with tabs aligned to DIAG_TAB_WIDTH to out and
        // returns the 1-based visual column that raw column stop_col lands on
        expand_tabs(Buf* out, byte* raw, int rn, int stop_col) -> int
        {
            int i = 0;
            int vis = 1;
            int sp, col_in_raw, k;
            int base = out.len;
            while (i < rn)
            {
                col_in_raw = i + 1;
                if (raw[i] == 9)
                {
                    sp = DIAG_TAB_WIDTH - ((out.len - base) % DIAG_TAB_WIDTH);
                    k = 0;
                    while (k < sp) { out.put(32); k++; };
                    if (col_in_raw < stop_col) { vis = vis + sp; };
                }
                else
                {
                    out.put((int)raw[i]);
                    if (col_in_raw < stop_col) { vis++; };
                };
                i++;
            };
            -> vis;
        };

        is_space(int c) -> bool -> c == 32 | c == 9 | c == 10 | c == 13 | c == 11 | c == 12;

        // ===== SUGGESTION =====

        // ferrors._build_suggestion. raw is the source line (tabs intact), ex the tab expanded
        // line, expected the missing token type, got the token found instead (type and length),
        // prev_line the line of the token before it (0 when none), tok_line/tok_col where the
        // found token starts. Returns true and fills out when a fix can be derived.
        build_suggestion(Buf* out, int expected, int got, int got_len, int tok_line, int tok_col, int prev_line, byte* raw, int rn, byte* ex, int en, int dash_count) -> bool
        {
            byte* fix_sym = sym_of(expected);
            int i, j, k, be, ind_end, t_end, v_start, v_end, col0, end_col, before_end, after_start, bn;
            bool has_after, starts;
            Buf fixed;
            if (fix_sym == (byte*)0) { -> false; };
            if (ends_prev_line(expected))
            {
                // C style array "type name[N];" where "type[N] name;" belongs
                if (expected == TokenType.SEMICOLON & got == TokenType.LEFT_BRACKET & prev_line > 0)
                {
                    be = rn;
                    while (be > 0 & is_space((int)raw[be - 1])) { be--; };
                    ind_end = 0;
                    while (ind_end < be & is_space((int)raw[ind_end])) { ind_end++; };
                    t_end = ind_end;
                    while (t_end < be & !is_space((int)raw[t_end])) { t_end++; };
                    if (t_end > ind_end & t_end < be)
                    {
                        v_start = t_end;
                        while (v_start < be & is_space((int)raw[v_start])) { v_start++; };
                        v_end = be;
                        if (v_end > v_start & raw[v_end - 1] == ';') { v_end--; };
                        // v_start..v_end must read name[digits]
                        if (v_end > v_start & raw[v_end - 1] == ']')
                        {
                            k = v_end - 2;
                            while (k >= v_start & raw[k] >= '0' & raw[k] <= '9') { k--; };
                            if (k >= v_start & raw[k] == '[' & k < v_end - 2 & k > v_start)
                            {
                                j = v_start;
                                while (j < k & !is_space((int)raw[j])) { j++; };
                                if (j == k)
                                {
                                    out.put_n(raw, t_end);
                                    out.put_n(raw + k, v_end - k);
                                    out.put(32);
                                    out.put_n(raw + v_start, k - v_start);
                                    out.put_str(";  // try this\0");
                                    -> true;
                                };
                            };
                        };
                    };
                };
                // Something unexpected sits on the same line as the last valid token
                if (prev_line > 0 & prev_line == tok_line)
                {
                    bn = pp_cstrlen(fix_sym);
                    be = rn;
                    while (be > 0 & is_space((int)raw[be - 1])) { be--; };
                    if (be >= bn)
                    {
                        starts = true;
                        k = 0;
                        while (k < bn) { if (raw[be - bn + k] != fix_sym[k]) { starts = false; }; k++; };
                        if (starts) { -> false; };
                    };
                    col0 = tok_col - 1;
                    end_col = col0 + got_len;
                    if (end_col > rn) { end_col = rn; };
                    if (col0 > rn) { col0 = rn; };
                    before_end = col0;
                    while (before_end > 0 & is_space((int)raw[before_end - 1])) { before_end--; };
                    after_start = end_col;
                    while (after_start < rn & is_space((int)raw[after_start])) { after_start++; };
                    has_after = after_start < rn;
                    starts = false;
                    if (has_after & rn - after_start >= bn)
                    {
                        starts = true;
                        k = 0;
                        while (k < bn) { if (raw[after_start + k] != fix_sym[k]) { starts = false; }; k++; };
                    };
                    fixed.__init();
                    defer fixed.__exit();
                    fixed.put_n(raw, before_end);
                    if (before_end > 0 & has_after & !starts) { fixed.put(32); };
                    fixed.put_n(raw + after_start, rn - after_start);
                    // rstrip
                    while (fixed.len > 0 & is_space((int)fixed.mem[fixed.len - 1])) { fixed.len--; };
                    fixed.mem[fixed.len] = (byte)0;
                    starts = false;
                    if (fixed.len >= bn)
                    {
                        starts = true;
                        k = 0;
                        while (k < bn) { if (fixed.mem[fixed.len - bn + k] != fix_sym[k]) { starts = false; }; k++; };
                    };
                    out.put_n(fixed.mem, fixed.len);
                    if (!starts) { out.put_str(fix_sym); };
                    out.put_str("  // try this\0");
                    -> true;
                };
                // Default: the terminator goes at the end of the line
                out.put_n(ex, en);
                out.put_str(fix_sym);
                out.put_str("  // try this\0");
                -> true;
            };
            if (expected == TokenType.RETURN_ARROW | (expected == TokenType.ASSIGN & got == TokenType.LEFT_BRACE))
            {
                i = dash_count;
                if (i > en) { i = en; };
                out.put_n(ex, i);
                out.put_str(fix_sym);
                out.put(32);
                while (i < en & is_space((int)ex[i])) { i++; };
                out.put_n(ex + i, en - i);
                out.put_str("  // try this\0");
                -> true;
            };
            -> false;
        };

        // ===== RENDER =====

        // ferrors._render_diagnostic. Appends the formatted diagnostic to out (no trailing newline).
        //   sev          SEV_ERROR or SEV_WARNING
        //   msg          message text (callers prepend "Warning: " themselves, as emit_warning does)
        //   line, col    1-based position of the token in the merged source src (length n)
        //   lmap, lmapn  merged line to file local line map (null when none)
        //   expected     missing token type for the caret hint and the suggestion, or -1
        //   got, got_len the token found instead (type and source length)
        //   prev_line    line of the token before the current one, 0 when none
        //   annotation   trailing note after the caret line, or null
        render(Buf* out, bool color, int sev, byte* msg, int line, int col, byte* src, int n, int* lmap, int lmapn, byte** lfiles, int expected, int got, int got_len, int prev_line, byte* annotation) -> void
        {
            int show_line = line;
            int show_col = col;
            int ls, le, pls, ple, disp_line, rn, en, vis, dash, k;
            byte* sym;
            Buf ex, sug;
            bool have_sug;

            if (sev == SEV_WARNING) { WARN_COUNT++; };
            if (expected >= 0 & ends_prev_line(expected) & prev_line > 0 & prev_line < line)
            {
                if (line_bounds(src, n, prev_line, @pls, @ple))
                {
                    show_line = prev_line;
                    show_col = (ple - pls) + 1;
                };
            };
            disp_line = show_line;
            if (lmap != (int*)0 & show_line >= 1 & show_line <= lmapn) { disp_line = lmap[show_line - 1]; };
            byte* disp_file = (byte*)0;
            if (lfiles != (byte**)0 & show_line >= 1 & show_line <= lmapn) { disp_file = lfiles[show_line - 1]; };

            // header
            if (color)
            {
                diag_sgr(out, "1\0");
                diag_sgr(out, diag_sev_code(sev));
                out.put_str(msg);
                diag_sgr(out, "0\0");
                out.put(32);
                diag_sgr(out, "96\0");
                out.put_str("at \0");
                if (disp_file != (byte*)0) { out.put_str(disp_file); out.put(58); };
                out.put_int(disp_line);
                out.put(58);
                out.put_int(show_col);
                diag_sgr(out, "0\0");
            }
            else
            {
                out.put_str(msg);
                out.put_str(" at \0");
                if (disp_file != (byte*)0) { out.put_str(disp_file); out.put(58); };
                out.put_int(disp_line);
                out.put(58);
                out.put_int(show_col);
            };

            if (!line_bounds(src, n, show_line, @ls, @le)) { ->; };
            rn = le - ls;
            ex.__init();
            defer ex.__exit();
            vis = expand_tabs(@ex, src + ls, rn, show_col);
            en = ex.len;
            if (show_col > rn) { dash = en; } else { dash = vis - 1; };
            if (dash < 0) { dash = 0; };

            sug.__init();
            defer sug.__exit();
            have_sug = false;
            if (expected >= 0)
            {
                have_sug = build_suggestion(@sug, expected, got, got_len, line, col, prev_line, src + ls, rn, ex.mem, en, dash);
            };

            out.put(10);
            out.put_n(ex.mem, en);
            out.put(10);

            // caret line
            if (color)
            {
                diag_sgr(out, "2\0");
                k = 0;
                while (k < dash) { out.put(45); k++; };
                diag_sgr(out, "0\0");
                diag_sgr(out, "1\0");
                diag_sgr(out, diag_sev_code(sev));
                out.put(94);
                diag_sgr(out, "0\0");
            }
            else
            {
                k = 0;
                while (k < dash) { out.put(45); k++; };
                out.put(94);
            };
            if (expected >= 0)
            {
                sym = sym_of(expected);
                if (color) { diag_sgr(out, "92\0"); };
                out.put(32);
                if (sym != (byte*)0) { out.put_str(sym); } else { out.put_str(token_name(expected)); };
                out.put_str(" expected here\0");
                if (color) { diag_sgr(out, "0\0"); };
            };

            if (have_sug)
            {
                out.put(10);
                if (color) { diag_sgr(out, "92\0"); };
                out.put_n(sug.mem, sug.len);
                if (color) { diag_sgr(out, "0\0"); };
            }
            else
            {
                if (annotation != (byte*)0)
                {
                    if (annotation[0] != 0)
                    {
                        out.put(32);
                        if (color) { diag_sgr(out, "95\0"); };
                        out.put_str(annotation);
                        if (color) { diag_sgr(out, "0\0"); };
                    };
                };
            };
            ->;
        };

        // True when diagnostics should be colored: NO_COLOR off, FORCE_COLOR=1 or stderr is a terminal
        // (tty is the caller's isatty(2) answer)
        diag_color_enabled(bool tty, byte* no_color, byte* force_color) -> bool
        {
            if (no_color != (byte*)0) { -> false; };
            if (force_color != (byte*)0) { if (force_color[0] == '1' & force_color[1] == 0) { -> true; }; };
            -> tty;
        };
    };
};

#endif;
