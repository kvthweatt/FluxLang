// Author: Karac V. Thweatt
//
// fcheck.fx - Flux type check pass (bootstrap)
//
// The base compiler has no general type check. Its only type rules are the
// template constraints in fparser.py:
//     allowed type lists   T : int | long
//     T ~= U               compatible (pointer-ness, pointer depth, bit width)
//     T !~= U              incompatible
//     T !@ U               no address-of
//     T !`< U  / !`<= U    no truncation (independent / between)
//     T !`> U  / !`>= U    no widening   (independent / between)
// This file ports those rules to run over Node trees and adds the
// diagnostic list, the declaration pass over the symbol table, and the
// entry points the parser calls when it instantiates a template.
//
// Expression types are best effort exactly as in the Python: identifiers
// resolve through parameters and local declarations, casts give their target
// type, literals give their DataType. Anything else is unknown and skipped.
//
#ifndef FLUX_STANDARD
#import <standard.fx>;
#endif;

#ifndef FLUX_TYPES
#import "ftypesys.fx";
#endif;

#ifndef FLUX_CHECK
#def FLUX_CHECK 1;

using flux::ast;
using flux::preprocessor;
using flux::types;

namespace flux
{
    namespace check
    {

        enum Severity
        {
            ERROR,
            WARNING
        };

        struct Diag
        {
            int severity, line, col;
            byte* msg;
        };

        // ------------------------------------------------------------------
        // Rules on TypeSpec (no AST needed)
        // ------------------------------------------------------------------

        // Bit width of t, 0 when unknown (fparser._bw)
        def bw(TypeSpec* t) -> int
        {
            if (t == (TypeSpec*)0) { return 0; };
            if (t.bit_width > 0) { return t.bit_width; };
            int w = builtin_bit_width(t.base_type);
            if (w < 0) { return 0; };
            return w;
        };

        // Relational constraint compatibility (fparser._types_compatible)
        def types_compatible(TypeSpec* a, TypeSpec* b) -> bool
        {
            if (ts_is_pointer(a) != ts_is_pointer(b)) { return false; };
            if (ts_is_pointer(a) & a.pointer_depth != b.pointer_depth) { return false; };
            int aw, bw_;
            if (a.bit_width > 0) { aw = a.bit_width; };
            if (b.bit_width > 0) { bw_ = b.bit_width; };
            if (aw != 0 & bw_ != 0 & aw != bw_) { return false; };
            return true;
        };

        // Allowed list match (fparser._ts_matches)
        def ts_matches(TypeSpec* concrete, TypeSpec* allowed) -> bool
        {
            if (concrete.base_type == DataType.OBJECT & allowed.base_type == DataType.DATA &
                allowed.custom_typename != (byte*)0) { return true; };
            if (concrete.base_type != allowed.base_type) { return false; };
            if (ts_is_pointer(concrete) != ts_is_pointer(allowed)) { return false; };
            if (concrete.pointer_depth != allowed.pointer_depth) { return false; };
            if (ts_is_array(concrete) != ts_is_array(allowed)) { return false; };
            if (!cstr_eq(concrete.custom_typename, allowed.custom_typename)) { return false; };
            if (allowed.bit_width > 0 & concrete.bit_width > 0 & concrete.bit_width != allowed.bit_width)
            {
                return false;
            };
            return true;
        };

        // Appends every node of the tree under n (depth first, n first) to out.
        def collect_nodes(Node* n, PtrVec* out) -> void
        {
            if (n == (Node*)0) { return; };
            pv_push(out, (void*)n);
            collect_nodes(n.a, out);
            collect_nodes(n.b, out);
            collect_nodes(n.c, out);
            collect_nodes(n.d, out);
            collect_nodes(n.e, out);
            int s, i, cnt;
            while (s < 6)
            {
                cnt = node_count(n, s);
                i = 0;
                while (i < cnt)
                {
                    collect_nodes(node_child(n, s, i), out);
                    i++;
                };
                s++;
            };
            return;
        };

        // ------------------------------------------------------------------
        // Checker
        // ------------------------------------------------------------------
        object Checker
        {
            FXC_SYMTABLE* st;
            PtrVec* diags;      // Diag*
            PtrVec* tmp_ts;     // TypeSpecs made for literals
            Buf mb;             // message scratch
            int errors, warnings;
            int decls;          // symbols declared by declare_program
            bool warn_implicit; // opt-in: report implicit conversions the compiler allows

            def __init(FXC_SYMTABLE* table) -> this
            {
                this.st = table;
                this.diags = pv_new();
                this.tmp_ts = pv_new();
                this.mb.__init();
                this.errors = 0;
                this.warnings = 0;
                this.decls = 0;
                this.warn_implicit = false;
                return this;
            };

            def __expr() -> Checker*
            {
                return this;
            };

            def __exit() -> void
            {
                int i;
                Diag* d;
                while (i < this.diags.len)
                {
                    d = (Diag*)this.diags.items[i];
                    ffree(d.msg);
                    ffree((byte*)d);
                    i++;
                };
                i = 0;
                while (i < this.tmp_ts.len)
                {
                    ffree((byte*)this.tmp_ts.items[i]);
                    i++;
                };
                pv_free(this.diags);
                pv_free(this.tmp_ts);
                this.mb.__exit();
                return;
            };

            def clear_msg() -> void
            {
                this.mb.len = 0;
                if (this.mb.mem != (byte*)0) { this.mb.mem[0] = (byte)0; };
                return;
            };

            // Records the message currently in mb
            def emit(int severity, int line, int col) -> void
            {
                Diag* d = (Diag*)fmalloc((u64)(sizeof(Diag) / 8));
                d.severity = severity;
                d.line = line;
                d.col = col;
                d.msg = ts_dup(this.mb.mem);
                pv_push(this.diags, (void*)d);
                if (severity == Severity.ERROR) { this.errors++; }
                else { this.warnings++; };
                return;
            };

            // Appends the mangled text of a type, or ? when unknown
            def put_type(TypeSpec* t) -> void
            {
                if (t == (TypeSpec*)0)
                {
                    this.mb.put_str(g"?\0");
                    return;
                };
                mangle_type(@this.mb, t);
                return;
            };

            // "T" or "T and U" (a unary relation names the type once)
            def put_type_clause(byte* lname, byte* rname, TypeSpec* l, TypeSpec* r) -> void
            {
                bool same = cstr_eq(lname, rname);
                if (!same)
                {
                    // same mangled text also collapses
                    int mark = this.mb.len;
                    this.put_type(l);
                    int la = this.mb.len - mark;
                    this.put_type(r);
                    int lb = this.mb.len - mark - la;
                    if (la == lb)
                    {
                        same = true;
                        int k;
                        while (k < la)
                        {
                            if (this.mb.mem[mark + k] != this.mb.mem[mark + la + k]) { same = false; };
                            k++;
                        };
                    };
                    this.mb.len = mark;
                    this.mb.mem[mark] = (byte)0;
                };
                this.put_type(l);
                if (!same)
                {
                    this.mb.put_str(g" and \0");
                    this.put_type(r);
                };
                return;
            };

            // Type of an expression, null when unknown. locals maps name -> TypeSpec*.
            def type_of(Node* e, NameMap* locals) -> TypeSpec*
            {
                if (e == (Node*)0) { return (TypeSpec*)0; };
                if (e.kind == NodeKind.CAST_EXPRESSION | e.kind == NodeKind.TYPE_CONVERT_EXPRESSION)
                {
                    return e.ts;
                };
                if (e.kind == NodeKind.IDENTIFIER)
                {
                    if (e.text == (byte*)0) { return (TypeSpec*)0; };
                    return (TypeSpec*)nm_get(locals, e.text);
                };
                if (e.kind == NodeKind.LITERAL)
                {
                    TypeSpec* t = typespec_new();
                    t.base_type = e.op;
                    if (e.op == DataType.SINT | e.op == DataType.SLONG | e.op == DataType.CHAR |
                        e.op == DataType.FLOAT | e.op == DataType.DOUBLE)
                    {
                        t.flags = TS_SIGNED;
                    };
                    pv_push(this.tmp_ts, (void*)t);
                    return t;
                };
                return (TypeSpec*)0;
            };

            // Fills locals from the parameters and declarations of fn (name -> TypeSpec*)
            def collect_locals(Node* fn, PtrVec* nodes, NameMap* locals) -> void
            {
                int i, cnt;
                Node* p;
                cnt = node_count(fn, 0);
                while (i < cnt)
                {
                    p = node_child(fn, 0, i);
                    if (p.text != (byte*)0 & p.ts != (TypeSpec*)0) { nm_put(locals, p.text, (void*)p.ts); };
                    i++;
                };
                i = 0;
                while (i < nodes.len)
                {
                    p = (Node*)nodes.items[i];
                    if (p.kind == NodeKind.VARIABLE_DECLARATION & p.text != (byte*)0 & p.ts != (TypeSpec*)0)
                    {
                        nm_put(locals, p.text, (void*)p.ts);
                    };
                    i++;
                };
                return;
            };

            // True when w equals the width of lts or rts
            def width_constrained(int w, TypeSpec* lts, TypeSpec* rts) -> bool
            {
                return w == bw(lts) | w == bw(rts);
            };

            // Reports one width violation
            def report_width(Node* at, byte* op, byte* lname, byte* rname, TypeSpec* lts, TypeSpec* rts,
                             bool is_trunc, bool between) -> void
            {
                this.clear_msg();
                this.mb.put_str(g"Type relation \0");
                this.mb.put_str(lname);
                this.mb.put_str(g" \0");
                this.mb.put_str(op);
                this.mb.put_str(g" \0");
                this.mb.put_str(rname);
                this.mb.put_str(g" violated: illegal \0");
                if (is_trunc) { this.mb.put_str(g"truncation \0"); }
                else { this.mb.put_str(g"widening \0"); };
                if (between) { this.mb.put_str(g"between \0"); }
                else { this.mb.put_str(g"on \0"); };
                this.put_type_clause(lname, rname, lts, rts);
                this.emit(Severity.ERROR, at.line, at.col);
                return;
            };

            // !`< !`<= !`> !`>= over the instantiated function fn
            def check_width_relation(Node* fn, PtrVec* nodes, NameMap* locals, byte* op,
                                     byte* lname, byte* rname, TypeSpec* lts, TypeSpec* rts) -> void
            {
                bool between = cstr_eq(op, g"!`<=\0") | cstr_eq(op, g"!`>=\0");
                bool is_trunc = cstr_eq(op, g"!`<\0") | cstr_eq(op, g"!`<=\0");
                int i, src_w, dst_w, lw, rw, result_w, max_w, expr_w, ret_w;
                bool violated, src_match, dst_match;
                Node* n;
                TypeSpec* s;
                TypeSpec* d;
                TypeSpec* ls;
                TypeSpec* rs;

                while (i < nodes.len)
                {
                    n = (Node*)nodes.items[i];
                    i++;
                    violated = false;

                    if (n.kind == NodeKind.CAST_EXPRESSION | n.kind == NodeKind.TYPE_CONVERT_EXPRESSION)
                    {
                        s = this.type_of(n.a, locals);
                        d = n.ts;
                        src_w = bw(s);
                        dst_w = bw(d);
                        if (src_w == 0 | dst_w == 0) { continue; };
                        if (is_trunc) { if (dst_w >= src_w) { continue; }; }
                        else { if (dst_w <= src_w) { continue; }; };
                        src_match = this.width_constrained(src_w, lts, rts);
                        dst_match = this.width_constrained(dst_w, lts, rts);
                        if (between) { violated = src_match & dst_match; }
                        else { violated = src_match | dst_match; };
                    }
                    elif (n.kind == NodeKind.BINARY_OP)
                    {
                        ls = this.type_of(n.a, locals);
                        rs = this.type_of(n.b, locals);
                        lw = bw(ls);
                        rw = bw(rs);
                        if (lw == 0 | rw == 0) { continue; };
                        result_w = lw;
                        max_w = rw;
                        if (rw < lw)
                        {
                            result_w = rw;
                            max_w = lw;
                        };
                        if (result_w == max_w) { continue; };
                        // The result width is the narrower operand, so a binary operation
                        // never widens (same as the Python: result_w <= min operand width).
                        if (!is_trunc) { continue; };
                        src_match = this.width_constrained(result_w, lts, rts);
                        dst_match = this.width_constrained(max_w, lts, rts);
                        if (between) { violated = src_match & dst_match; }
                        else { violated = src_match | dst_match; };
                    }
                    elif (n.kind == NodeKind.RETURN_STATEMENT)
                    {
                        if (n.a == (Node*)0) { continue; };
                        s = this.type_of(n.a, locals);
                        if (s == (TypeSpec*)0 & n.a.kind == NodeKind.BINARY_OP)
                        {
                            ls = this.type_of(n.a.a, locals);
                            rs = this.type_of(n.a.b, locals);
                            lw = bw(ls);
                            rw = bw(rs);
                            expr_w = lw;
                            if (rw > lw) { expr_w = rw; };
                            if (lw == 0 | rw == 0) { expr_w = 0; };
                        }
                        else { expr_w = bw(s); };
                        ret_w = bw(fn.ts);
                        if (ret_w == 0 | expr_w == 0) { continue; };
                        if (is_trunc) { if (expr_w <= ret_w) { continue; }; }
                        else { if (expr_w >= ret_w) { continue; }; };
                        src_match = this.width_constrained(expr_w, lts, rts);
                        dst_match = this.width_constrained(ret_w, lts, rts);
                        if (between) { violated = src_match & dst_match; }
                        else { violated = src_match | dst_match; };
                    };

                    if (violated) { this.report_width(n, op, lname, rname, lts, rts, is_trunc, between); };
                };
                return;
            };

            // !@ over the uninstantiated template function: address-of on a variable
            // or parameter declared with one of the constrained type parameter names.
            def check_no_address(Node* tmpl, PtrVec* nodes, byte* lname, byte* rname,
                                 TypeSpec* lts, TypeSpec* rts) -> void
            {
                NameMap* vars = nm_new();
                int i, cnt;
                Node* n;
                cnt = node_count(tmpl, 0);
                while (i < cnt)
                {
                    n = node_child(tmpl, 0, i);
                    if (n.text != (byte*)0 & n.ts != (TypeSpec*)0)
                    {
                        if (cstr_eq(n.ts.custom_typename, lname) | cstr_eq(n.ts.custom_typename, rname))
                        {
                            nm_put(vars, n.text, (void*)n);
                        };
                    };
                    i++;
                };
                i = 0;
                while (i < nodes.len)
                {
                    n = (Node*)nodes.items[i];
                    if (n.kind == NodeKind.VARIABLE_DECLARATION & n.text != (byte*)0 & n.ts != (TypeSpec*)0)
                    {
                        if (cstr_eq(n.ts.custom_typename, lname) | cstr_eq(n.ts.custom_typename, rname))
                        {
                            nm_put(vars, n.text, (void*)n);
                        };
                    };
                    i++;
                };
                i = 0;
                while (i < nodes.len)
                {
                    n = (Node*)nodes.items[i];
                    i++;
                    if (n.kind != NodeKind.ADDRESS_OF) { continue; };
                    if (n.a == (Node*)0) { continue; };
                    if (n.a.kind != NodeKind.IDENTIFIER) { continue; };
                    if (n.a.text == (byte*)0) { continue; };
                    if (!nm_has(vars, n.a.text)) { continue; };
                    this.clear_msg();
                    this.mb.put_str(g"Type relation \0");
                    this.mb.put_str(lname);
                    this.mb.put_str(g" !@ \0");
                    this.mb.put_str(rname);
                    this.mb.put_str(g" violated: cannot take address of \0");
                    this.put_type_clause(lname, rname, lts, rts);
                    this.emit(Severity.ERROR, n.line, n.col);
                };
                nm_free(vars);
                return;
            };

            // One allowed-list constraint on a template parameter. allowed_text is the
            // source form used in the message, e.g. "int | long".
            def check_allowed(byte* fname, byte* pname, TypeSpec* concrete, TypeSpec** allowed, int n,
                              byte* allowed_text, int line, int col) -> bool
            {
                int i;
                if (concrete == (TypeSpec*)0) { return true; };
                while (i < n)
                {
                    if (ts_matches(concrete, allowed[i])) { return true; };
                    i++;
                };
                this.clear_msg();
                this.mb.put_str(g"Template parameter '\0");
                this.mb.put_str(pname);
                this.mb.put_str(g"' of '\0");
                this.mb.put_str(fname);
                this.mb.put_str(g"' was instantiated with type '\0");
                this.put_type(concrete);
                this.mb.put_str(g"', which does not satisfy the constraint [\0");
                this.mb.put_str(allowed_text);
                this.mb.put_str(g"]\0");
                this.emit(Severity.ERROR, line, col);
                return false;
            };

            // Applies the CONSTRA_RELATION nodes of a template to one instantiation.
            //   pnames/args : template parameter names and their concrete types (n each)
            //   relations   : NodeVec of CONSTRA_RELATION (l0 lhs, text op, l1 rhs)
            //   tmpl        : the template FUNCTION_DEF before substitution (for !@)
            //   concrete    : the substituted FUNCTION_DEF (for width relations)
            // Returns the number of errors reported by this call.
            def check_relations(PtrVec* pnames, TypeSpec** args, int n, NodeVec* relations,
                                Node* tmpl, Node* concrete) -> int
            {
                int before = this.errors;
                if (relations == (NodeVec*)0) { return 0; };

                PtrVec* tnodes = pv_new();
                PtrVec* cnodes = pv_new();
                NameMap* locals = nm_new();
                collect_nodes(tmpl, tnodes);
                if (concrete != (Node*)0)
                {
                    collect_nodes(concrete, cnodes);
                    this.collect_locals(concrete, cnodes, locals);
                };

                int r, a, b, k;
                Node* rel;
                byte* op;
                byte* lname;
                byte* rname;
                TypeSpec* lts;
                TypeSpec* rts;
                int nl, nr;
                while (r < relations.len)
                {
                    rel = relations.items[r];
                    r++;
                    op = rel.text;
                    nl = node_count(rel, 0);
                    nr = node_count(rel, 1);
                    a = 0;
                    while (a < nl)
                    {
                        lname = node_child(rel, 0, a).text;
                        b = 0;
                        while (b < nr)
                        {
                            rname = node_child(rel, 1, b).text;
                            lts = (TypeSpec*)0;
                            rts = (TypeSpec*)0;
                            k = 0;
                            while (k < n)
                            {
                                if (cstr_eq((byte*)pnames.items[k], lname)) { lts = args[k]; };
                                if (cstr_eq((byte*)pnames.items[k], rname)) { rts = args[k]; };
                                k++;
                            };
                            b++;
                            if (lts == (TypeSpec*)0 | rts == (TypeSpec*)0) { continue; };

                            if (cstr_eq(op, g"~=\0"))
                            {
                                if (!types_compatible(lts, rts))
                                {
                                    this.clear_msg();
                                    this.mb.put_str(g"Relation constraint '\0");
                                    this.mb.put_str(lname);
                                    this.mb.put_str(g" ~= \0");
                                    this.mb.put_str(rname);
                                    this.mb.put_str(g"' violated: '\0");
                                    this.put_type(lts);
                                    this.mb.put_str(g"' and '\0");
                                    this.put_type(rts);
                                    this.mb.put_str(g"' are not compatible (pointer mismatch or width mismatch)\0");
                                    this.emit(Severity.ERROR, rel.line, rel.col);
                                };
                            }
                            elif (cstr_eq(op, g"!~=\0"))
                            {
                                if (types_compatible(lts, rts))
                                {
                                    this.clear_msg();
                                    this.mb.put_str(g"Relation constraint '\0");
                                    this.mb.put_str(lname);
                                    this.mb.put_str(g" !~= \0");
                                    this.mb.put_str(rname);
                                    this.mb.put_str(g"' violated: '\0");
                                    this.put_type(lts);
                                    this.mb.put_str(g"' and '\0");
                                    this.put_type(rts);
                                    this.mb.put_str(g"' must be incompatible but are compatible\0");
                                    this.emit(Severity.ERROR, rel.line, rel.col);
                                };
                            }
                            elif (cstr_eq(op, g"!@\0"))
                            {
                                this.check_no_address(tmpl, tnodes, lname, rname, lts, rts);
                            }
                            elif (cstr_eq(op, g"!`<\0") | cstr_eq(op, g"!`<=\0") |
                                  cstr_eq(op, g"!`>\0") | cstr_eq(op, g"!`>=\0"))
                            {
                                if (concrete != (Node*)0)
                                {
                                    this.check_width_relation(concrete, cnodes, locals, op, lname, rname, lts, rts);
                                };
                            };
                        };
                        a++;
                    };
                };

                nm_free(locals);
                pv_free(tnodes);
                pv_free(cnodes);
                return this.errors - before;
            };

            // ------------------------------------------------------------------
            // Declaration pass
            // ------------------------------------------------------------------

            // Declares n (and anything nested) in the symbol table
            def declare_node(Node* n, byte* ns) -> void
            {
                if (n == (Node*)0) { return; };
                int k = n.kind;
                if (k == NodeKind.FUNCTION_DEF_STATEMENT | k == NodeKind.STRUCT_DEF_STATEMENT |
                    k == NodeKind.OBJECT_DEF_STATEMENT | k == NodeKind.ENUM_DEF_STATEMENT |
                    k == NodeKind.NAMESPACE_DEF_STATEMENT)
                {
                    this.declare_node(n.a, ns);
                    return;
                };

                // Stubbed constructs from the bootstrap parser carry no name
                if (n.text == (byte*)0) { return; };

                if (k == NodeKind.FUNCTION_DEF)
                {
                    st_define(this.st, n.text, SymbolKind.FUNCTION, n.ts, n);
                    this.decls++;
                }
                elif (k == NodeKind.STRUCT_DEF)
                {
                    st_define(this.st, n.text, SymbolKind.STRUCT, (TypeSpec*)0, n);
                    this.decls++;
                }
                elif (k == NodeKind.OBJECT_DEF)
                {
                    st_define(this.st, n.text, SymbolKind.OBJECT, (TypeSpec*)0, n);
                    this.decls++;
                }
                elif (k == NodeKind.ENUM_DEF)
                {
                    st_define(this.st, n.text, SymbolKind.ENUM, n.ts, n);
                    this.decls++;
                }
                elif (k == NodeKind.VARIABLE_DECLARATION)
                {
                    if (n.text != (byte*)0)
                    {
                        st_define(this.st, n.text, SymbolKind.VARIABLE, n.ts, n);
                        this.decls++;
                    };
                }
                elif (k == NodeKind.NAMESPACE_DEF)
                {
                    byte* prev = ts_dup(this.st.current_ns);
                    byte* full;
                    if (prev[0] == 0) { full = ts_dup(n.text); }
                    else
                    {
                        int la = pp_cstrlen(prev);
                        int lb = pp_cstrlen(n.text);
                        full = (byte*)fmalloc((u64)(la + lb + 3));
                        int i, j;
                        while (i < la)
                        {
                            full[i] = prev[i];
                            i++;
                        };
                        full[i] = ':';
                        full[i + 1] = ':';
                        while (j < lb)
                        {
                            full[i + 2 + j] = n.text[j];
                            j++;
                        };
                        full[i + 2 + lb] = (byte)0;
                    };
                    st_define(this.st, n.text, SymbolKind.NAMESPACE, (TypeSpec*)0, n);
                    st_set_namespace(this.st, full);
                    int s, c, e, w;
                    Node* lst;
                    while (s < 6)
                    {
                        c = node_count(n, s);
                        e = 0;
                        while (e < c)
                        {
                            this.declare_node(node_child(n, s, e), full);
                            e++;
                        };
                        s++;
                    };
                    w = 0;
                    while (w < 2)
                    {
                        if (w == 0) { lst = n.a; } else { lst = n.b; };
                        if (lst != (Node*)0)
                        {
                            c = node_count(lst, 0);
                            e = 0;
                            while (e < c)
                            {
                                this.declare_node(node_child(lst, 0, e), full);
                                e++;
                            };
                        };
                        w++;
                    };
                    st_set_namespace(this.st, prev);
                    ffree(prev);
                    ffree(full);
                };
                return;
            };

            // Declares every top level symbol of a PROGRAM node
            def declare_program(Node* prog) -> int
            {
                int i;
                int cnt = node_count(prog, 0);
                while (i < cnt)
                {
                    this.declare_node(node_child(prog, 0, i), g"\0");
                    i++;
                };
                return this.decls;
            };

            // Prints diagnostics as file:line:col: severity: message
            def print_diags(byte* path) -> void
            {
                int i;
                Diag* d;
                while (i < this.diags.len)
                {
                    d = (Diag*)this.diags.items[i];
                    print(path);
                    print(g":\0");
                    print(d.line);
                    print(g":\0");
                    print(d.col);
                    if (d.severity == Severity.ERROR) { print(g": error: \0"); }
                    else { print(g": warning: \0"); };
                    println(d.msg);
                    i++;
                };
                return;
            };
        };
    };
};

#endif;
