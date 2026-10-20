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
        bw(TypeSpec* t) -> int
        {
            switch (t == (TypeSpec*)0)
            {
                case (true) { -> 0; }
                default {};
            };
            switch (t.bit_width > 0)
            {
                case (true) { -> t.bit_width; }
                default {};
            };
            int w = builtin_bit_width(t.base_type);
            switch (w < 0)
            {
                case (true) { -> 0; }
                default {};
            };
            -> w;
        };

        // Relational constraint compatibility (fparser._types_compatible)
        types_compatible(TypeSpec* a, TypeSpec* b) -> bool
        {
            switch (ts_is_pointer(a) != ts_is_pointer(b))
            {
                case (true) { -> false; }
                default {};
            };
            switch (ts_is_pointer(a) & a.pointer_depth != b.pointer_depth)
            {
                case (true) { -> false; }
                default {};
            };
            int aw, bw_;
            switch (a.bit_width > 0)
            {
                case (true) { aw = a.bit_width; }
                default {};
            };
            switch (b.bit_width > 0)
            {
                case (true) { bw_ = b.bit_width; }
                default {};
            };
            switch (aw != 0 & bw_ != 0 & aw != bw_)
            {
                case (true) { -> false; }
                default {};
            };
            -> true;
        };

        // Allowed list match (fparser._ts_matches)
        ts_matches(TypeSpec* concrete, TypeSpec* allowed) -> bool
        {
            switch (concrete.base_type == DataType.OBJECT & allowed.base_type == DataType.DATA &
                allowed.custom_typename != (byte*)0)
            {
                case (true) { -> true; }
                default {};
            };
            switch (concrete.base_type != allowed.base_type)
            {
                case (true) { -> false; }
                default {};
            };
            switch (ts_is_pointer(concrete) != ts_is_pointer(allowed))
            {
                case (true) { -> false; }
                default {};
            };
            switch (concrete.pointer_depth != allowed.pointer_depth)
            {
                case (true) { -> false; }
                default {};
            };
            switch (ts_is_array(concrete) != ts_is_array(allowed))
            {
                case (true) { -> false; }
                default {};
            };
            switch (!cstr_eq(concrete.custom_typename, allowed.custom_typename))
            {
                case (true) { -> false; }
                default {};
            };
            switch (allowed.bit_width > 0 & concrete.bit_width > 0 & concrete.bit_width != allowed.bit_width)
            {
                case (true) {
                -> false;
            }
                default {};
            };
            -> true;
        };

        // Appends every node of the tree under n (depth first, n first) to out.
        collect_nodes(Node* n, PtrVec* out) -> void
        {
            switch (n == (Node*)0)
            {
                case (true) { ->; }
                default {};
            };
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
            ->;
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

            __init(FXC_SYMTABLE* table) -> this
            {
                this.st = table;
                this.diags = pv_new();
                this.tmp_ts = pv_new();
                this.mb.__init();
                this.errors = 0;
                this.warnings = 0;
                this.decls = 0;
                this.warn_implicit = false;
                -> this;
            };

            __expr() -> Checker* -> this;

            __exit() -> void
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
                ->;
            };

            clear_msg() -> void
            {
                this.mb.len = 0;
                switch (this.mb.mem != (byte*)0)
                {
                    case (true) { this.mb.mem[0] = (byte)0; }
                    default {};
                };
                ->;
            };

            // Records the message currently in mb
            emit(int severity, int line, int col) -> void
            {
                Diag* d = (Diag*)fmalloc((u64)(sizeof(Diag) / 8));
                d.severity = severity;
                d.line = line;
                d.col = col;
                d.msg = ts_dup(this.mb.mem);
                pv_push(this.diags, (void*)d);
                switch (severity)
                {
                    case (Severity.ERROR) { this.errors++; }
                    default { this.warnings++; };
                };
                ->;
            };

            // Appends the mangled text of a type, or ? when unknown
            put_type(TypeSpec* t) -> void
            {
                switch (t == (TypeSpec*)0)
                {
                    case (true) {
                    this.mb.put_str(g"?\0");
                    ->;
                }
                    default {};
                };
                mangle_type(@this.mb, t);
                ->;
            };

            // "T" or "T and U" (a unary relation names the type once)
            put_type_clause(byte* lname, byte* rname, TypeSpec* l, TypeSpec* r) -> void
            {
                bool same = cstr_eq(lname, rname);
                switch (!same)
                {
                    case (true) {
                    // same mangled text also collapses
                    int mark = this.mb.len;
                    this.put_type(l);
                    int la = this.mb.len - mark;
                    this.put_type(r);
                    int lb = this.mb.len - mark - la;
                    switch (la == lb)
                    {
                        case (true) {
                        same = true;
                        int k;
                        while (k < la)
                        {
                            switch (this.mb.mem[mark + k] != this.mb.mem[mark + la + k])
                            {
                                case (true) { same = false; }
                                default {};
                            };
                            k++;
                        };
                    }
                        default {};
                    };
                    this.mb.len = mark;
                    this.mb.mem[mark] = (byte)0;
                }
                    default {};
                };
                this.put_type(l);
                switch (!same)
                {
                    case (true) {
                    this.mb.put_str(g" and \0");
                    this.put_type(r);
                }
                    default {};
                };
                ->;
            };

            // Type of an expression, null when unknown. locals maps name -> TypeSpec*.
            type_of(Node* e, NameMap* locals) -> TypeSpec*
            {
                switch (e == (Node*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                switch (e.kind == NodeKind.CAST_EXPRESSION | e.kind == NodeKind.TYPE_CONVERT_EXPRESSION)
                {
                    case (true) {
                    -> e.ts;
                }
                    default {};
                };
                switch (e.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    switch (e.text == (byte*)0)
                    {
                        case (true) { -> (TypeSpec*)0; }
                        default {};
                    };
                    -> (TypeSpec*)nm_get(locals, e.text);
                }
                    default {};
                };
                switch (e.kind == NodeKind.LITERAL)
                {
                    case (true) {
                    TypeSpec* t = typespec_new();
                    t.base_type = e.op;
                    switch (e.op == DataType.SINT | e.op == DataType.SLONG | e.op == DataType.CHAR |
                        e.op == DataType.FLOAT | e.op == DataType.DOUBLE)
                    {
                        case (true) {
                        t.flags = TS_SIGNED;
                    }
                        default {};
                    };
                    pv_push(this.tmp_ts, (void*)t);
                    -> t;
                }
                    default {};
                };
                -> (TypeSpec*)0;
            };

            // Fills locals from the parameters and declarations of fn (name -> TypeSpec*)
            collect_locals(Node* fn, PtrVec* nodes, NameMap* locals) -> void
            {
                int i, cnt;
                Node* p;
                cnt = node_count(fn, 0);
                while (i < cnt)
                {
                    p = node_child(fn, 0, i);
                    switch (p.text != (byte*)0 & p.ts != (TypeSpec*)0)
                    {
                        case (true) { nm_put(locals, p.text, (void*)p.ts); }
                        default {};
                    };
                    i++;
                };
                i = 0;
                while (i < nodes.len)
                {
                    p = (Node*)nodes.items[i];
                    switch (p.kind == NodeKind.VARIABLE_DECLARATION & p.text != (byte*)0 & p.ts != (TypeSpec*)0)
                    {
                        case (true) {
                        nm_put(locals, p.text, (void*)p.ts);
                    }
                        default {};
                    };
                    i++;
                };
                ->;
            };

            // True when w equals the width of lts or rts
            width_constrained(int w, TypeSpec* lts, TypeSpec* rts) -> bool -> w == bw(lts) | w == bw(rts);

            // Reports one width violation
            report_width(Node* at, byte* op, byte* lname, byte* rname, TypeSpec* lts, TypeSpec* rts,
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
                switch (is_trunc)
                {
                    case (true) { this.mb.put_str(g"truncation \0"); }
                    default { this.mb.put_str(g"widening \0"); };
                };
                switch (between)
                {
                    case (true) { this.mb.put_str(g"between \0"); }
                    default { this.mb.put_str(g"on \0"); };
                };
                this.put_type_clause(lname, rname, lts, rts);
                this.emit(Severity.ERROR, at.line, at.col);
                ->;
            };

            // !`< !`<= !`> !`>= over the instantiated function fn
            check_width_relation(Node* fn, PtrVec* nodes, NameMap* locals, byte* op,
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

                    switch (n.kind == NodeKind.CAST_EXPRESSION | n.kind == NodeKind.TYPE_CONVERT_EXPRESSION)
                    {
                        case (true) {
                        s = this.type_of(n.a, locals);
                        d = n.ts;
                        src_w = bw(s);
                        dst_w = bw(d);
                        switch (src_w == 0 | dst_w == 0)
                        {
                            case (true) { continue; }
                            default {};
                        };
                        switch (is_trunc)
                        {
                            case (true) { switch (dst_w >= src_w)
 {
     case (true) { continue; }
     default {};
 }; }
                            default { switch (dst_w <= src_w)
 {
     case (true) { continue; }
     default {};
 }; };
                        };
                        src_match = this.width_constrained(src_w, lts, rts);
                        dst_match = this.width_constrained(dst_w, lts, rts);
                        switch (between)
                        {
                            case (true) { violated = src_match & dst_match; }
                            default { violated = src_match | dst_match; };
                        };
                    }
                        default {
                        switch (n.kind)
                        {
                            case (NodeKind.BINARY_OP)
                            {
                                ls = this.type_of(n.a, locals);
                                rs = this.type_of(n.b, locals);
                                lw = bw(ls);
                                rw = bw(rs);
                                switch (lw == 0 | rw == 0)
                                {
                                    case (true) { continue; }
                                    default {};
                                };
                                result_w = lw;
                                max_w = rw;
                                switch (rw < lw)
                                {
                                    case (true) {
                                    result_w = rw;
                                    max_w = lw;
                                }
                                    default {};
                                };
                                switch (result_w == max_w)
                                {
                                    case (true) { continue; }
                                    default {};
                                };
                                // The result width is the narrower operand, so a binary operation
                                // never widens (same as the Python: result_w <= min operand width).
                                switch (!is_trunc)
                                {
                                    case (true) { continue; }
                                    default {};
                                };
                                src_match = this.width_constrained(result_w, lts, rts);
                                dst_match = this.width_constrained(max_w, lts, rts);
                                switch (between)
                                {
                                    case (true) { violated = src_match & dst_match; }
                                    default { violated = src_match | dst_match; };
                                };
                            }
                            case (NodeKind.RETURN_STATEMENT)
                            {
                                switch (n.a == (Node*)0)
                                {
                                    case (true) { continue; }
                                    default {};
                                };
                                s = this.type_of(n.a, locals);
                                switch (s == (TypeSpec*)0 & n.a.kind == NodeKind.BINARY_OP)
                                {
                                    case (true) {
                                    ls = this.type_of(n.a.a, locals);
                                    rs = this.type_of(n.a.b, locals);
                                    lw = bw(ls);
                                    rw = bw(rs);
                                    expr_w = lw;
                                    switch (rw > lw)
                                    {
                                        case (true) { expr_w = rw; }
                                        default {};
                                    };
                                    switch (lw == 0 | rw == 0)
                                    {
                                        case (true) { expr_w = 0; }
                                        default {};
                                    };
                                }
                                    default { expr_w = bw(s); };
                                };
                                ret_w = bw(fn.ts);
                                switch (ret_w == 0 | expr_w == 0)
                                {
                                    case (true) { continue; }
                                    default {};
                                };
                                switch (is_trunc)
                                {
                                    case (true) { switch (expr_w <= ret_w)
 {
     case (true) { continue; }
     default {};
 }; }
                                    default { switch (expr_w >= ret_w)
 {
     case (true) { continue; }
     default {};
 }; };
                                };
                                src_match = this.width_constrained(expr_w, lts, rts);
                                dst_match = this.width_constrained(ret_w, lts, rts);
                                switch (between)
                                {
                                    case (true) { violated = src_match & dst_match; }
                                    default { violated = src_match | dst_match; };
                                };
                            }
                            default {};
                        };
                    };
                    };

                    switch (violated)
                    {
                        case (true) { this.report_width(n, op, lname, rname, lts, rts, is_trunc, between); }
                        default {};
                    };
                };
                ->;
            };

            // !@ over the uninstantiated template function: address-of on a variable
            // or parameter declared with one of the constrained type parameter names.
            check_no_address(Node* tmpl, PtrVec* nodes, byte* lname, byte* rname,
                                 TypeSpec* lts, TypeSpec* rts) -> void
            {
                NameMap* vars = nm_new();
                int i, cnt;
                Node* n;
                cnt = node_count(tmpl, 0);
                while (i < cnt)
                {
                    n = node_child(tmpl, 0, i);
                    switch (n.text != (byte*)0 & n.ts != (TypeSpec*)0)
                    {
                        case (true) {
                        switch (cstr_eq(n.ts.custom_typename, lname) | cstr_eq(n.ts.custom_typename, rname))
                        {
                            case (true) {
                            nm_put(vars, n.text, (void*)n);
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                i = 0;
                while (i < nodes.len)
                {
                    n = (Node*)nodes.items[i];
                    switch (n.kind == NodeKind.VARIABLE_DECLARATION & n.text != (byte*)0 & n.ts != (TypeSpec*)0)
                    {
                        case (true) {
                        switch (cstr_eq(n.ts.custom_typename, lname) | cstr_eq(n.ts.custom_typename, rname))
                        {
                            case (true) {
                            nm_put(vars, n.text, (void*)n);
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                i = 0;
                while (i < nodes.len)
                {
                    n = (Node*)nodes.items[i];
                    i++;
                    switch (n.kind != NodeKind.ADDRESS_OF)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (n.a == (Node*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (n.a.kind != NodeKind.IDENTIFIER)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (n.a.text == (byte*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (!nm_has(vars, n.a.text))
                    {
                        case (true) { continue; }
                        default {};
                    };
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
                ->;
            };

            // One allowed-list constraint on a template parameter. allowed_text is the
            // source form used in the message, e.g. "int | long".
            check_allowed(byte* fname, byte* pname, TypeSpec* concrete, TypeSpec** allowed, int n,
                              byte* allowed_text, int line, int col) -> bool
            {
                int i;
                switch (concrete == (TypeSpec*)0)
                {
                    case (true) { -> true; }
                    default {};
                };
                while (i < n)
                {
                    switch (ts_matches(concrete, allowed[i]))
                    {
                        case (true) { -> true; }
                        default {};
                    };
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
                -> false;
            };

            // Applies the CONSTRA_RELATION nodes of a template to one instantiation.
            //   pnames/args : template parameter names and their concrete types (n each)
            //   relations   : NodeVec of CONSTRA_RELATION (l0 lhs, text op, l1 rhs)
            //   tmpl        : the template FUNCTION_DEF before substitution (for !@)
            //   concrete    : the substituted FUNCTION_DEF (for width relations)
            // Returns the number of errors reported by this call.
            check_relations(PtrVec* pnames, TypeSpec** args, int n, NodeVec* relations,
                                Node* tmpl, Node* concrete) -> int
            {
                int before = this.errors;
                switch (relations == (NodeVec*)0)
                {
                    case (true) { -> 0; }
                    default {};
                };

                PtrVec* tnodes = pv_new();
                PtrVec* cnodes = pv_new();
                NameMap* locals = nm_new();
                collect_nodes(tmpl, tnodes);
                switch (concrete != (Node*)0)
                {
                    case (true) {
                    collect_nodes(concrete, cnodes);
                    this.collect_locals(concrete, cnodes, locals);
                }
                    default {};
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
                                switch (cstr_eq((byte*)pnames.items[k], lname))
                                {
                                    case (true) { lts = args[k]; }
                                    default {};
                                };
                                switch (cstr_eq((byte*)pnames.items[k], rname))
                                {
                                    case (true) { rts = args[k]; }
                                    default {};
                                };
                                k++;
                            };
                            b++;
                            switch (lts == (TypeSpec*)0 | rts == (TypeSpec*)0)
                            {
                                case (true) { continue; }
                                default {};
                            };

                            switch (cstr_eq(op, g"~=\0"))
                            {
                                case (true) {
                                switch (!types_compatible(lts, rts))
                                {
                                    case (true) {
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
                                }
                                    default {};
                                };
                            }
                                default {
                                    switch (cstr_eq(op, g"!~=\0"))
                                    {
                                        case (true) {
                                switch (types_compatible(lts, rts))
                                {
                                    case (true) {
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
                                }
                                    default {};
                                };
                            }
                                        default {
                                            switch (cstr_eq(op, g"!@\0"))
                                            {
                                                case (true) {
                                this.check_no_address(tmpl, tnodes, lname, rname, lts, rts);
                            }
                                                default {
                                                    switch (cstr_eq(op, g"!`<\0") | cstr_eq(op, g"!`<=\0") |
                                  cstr_eq(op, g"!`>\0") | cstr_eq(op, g"!`>=\0"))
                                                    {
                                                        case (true) {
                                switch (concrete != (Node*)0)
                                {
                                    case (true) {
                                    this.check_width_relation(concrete, cnodes, locals, op, lname, rname, lts, rts);
                                }
                                    default {};
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
                        };
                        a++;
                    };
                };

                nm_free(locals);
                pv_free(tnodes);
                pv_free(cnodes);
                -> this.errors - before;
            };

            // ------------------------------------------------------------------
            // Declaration pass
            // ------------------------------------------------------------------

            // Declares n (and anything nested) in the symbol table
            declare_node(Node* n, byte* ns) -> void
            {
                switch (n == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                int k = n.kind;
                switch (k == NodeKind.FUNCTION_DEF_STATEMENT | k == NodeKind.STRUCT_DEF_STATEMENT |
                    k == NodeKind.OBJECT_DEF_STATEMENT | k == NodeKind.ENUM_DEF_STATEMENT | k == NodeKind.UNION_DEF_STATEMENT |
                    k == NodeKind.NAMESPACE_DEF_STATEMENT)
                {
                    case (true) {
                    this.declare_node(n.a, ns);
                    ->;
                }
                    default {};
                };

                switch (k == NodeKind.EXTERN_BLOCK | k == NodeKind.EXPORT_BLOCK)
                {
                    case (true) {
                    int bi;
                    int bc = node_count(n, 0);
                    while (bi < bc)
                    {
                        this.declare_node(node_child(n, 0, bi), ns);
                        bi++;
                    };
                    ->;
                }
                    default {};
                };

                // Stubbed constructs from the bootstrap parser carry no name
                switch (n.text == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };

                switch (k)
                {
                    case (NodeKind.FUNCTION_DEF)
                    {
                        st_define(this.st, n.text, SymbolKind.FUNCTION, n.ts, n);
                        switch ((n.flags `& NF_TEMPLATE) == 0)
                        {
                            case (true) {
                            byte* fkey = mangle_namespace_name(ns, n.text);
                            this.reg_overload(fkey, n);
                            ffree(fkey);
                        }
                            default {};
                        };
                        this.decls++;
                    }
                    case (NodeKind.TYPE_FUNC_DEF)
                    {
                        switch (n.text2 != (byte*)0)
                        {
                            case (true) {
                            byte* tmid = join3(g"__typefunc__\0", n.text, g"__\0");
                            byte* tkey = join3(tmid, n.text2, g"\0");
                            this.reg_overload(tkey, n);
                            ffree(tmid);
                            ffree(tkey);
                        }
                            default {};
                        };
                    }
                    case (NodeKind.TYPE_DECLARATION)
                    {
                        st_define(this.st, n.text, SymbolKind.TYPE, n.ts, n);
                        this.decls++;
                    }
                    case (NodeKind.UNION_DEF)
                    {
                        st_define(this.st, n.text, SymbolKind.UNION, (TypeSpec*)0, n);
                        this.decls++;
                    }
                    case (NodeKind.FUNCTION_POINTER_DECLARATION)
                    {
                        st_define(this.st, n.text, SymbolKind.VARIABLE, n.ts, n);
                        this.decls++;
                    }
                    case (NodeKind.STRUCT_DEF)
                    {
                        st_define(this.st, n.text, SymbolKind.STRUCT, (TypeSpec*)0, n);
                        int si;
                        int sc = node_count(n, 3);
                        while (si < sc)
                        {
                            this.declare_node(node_child(n, 3, si), ns);
                            si++;
                        };
                        this.decls++;
                    }
                    case (NodeKind.OBJECT_DEF)
                    {
                        st_define(this.st, n.text, SymbolKind.OBJECT, (TypeSpec*)0, n);
                        switch (n.d == (Node*)0)
                        {
                            case (true) {
                            byte* okey = mangle_namespace_name(ns, n.text);
                            int mi;
                            int mc = node_count(n, 1);
                            Node* meth;
                            byte* mkey;
                            while (mi < mc)
                            {
                                meth = node_child(n, 1, mi);
                                switch (meth.text != (byte*)0 & (meth.flags `& NF_TEMPLATE) == 0)
                                {
                                    case (true) {
                                    mkey = join3(okey, g".\0", meth.text);
                                    this.reg_overload(mkey, meth);
                                    ffree(mkey);
                                }
                                    default {};
                                };
                                mi++;
                            };
                            ffree(okey);
                            mi = 0;
                            mc = node_count(n, 3);
                            while (mi < mc)
                            {
                                this.declare_node(node_child(n, 3, mi), ns);
                                mi++;
                            };
                            mi = 0;
                            mc = node_count(n, 4);
                            while (mi < mc)
                            {
                                this.declare_node(node_child(n, 4, mi), ns);
                                mi++;
                            };
                        }
                            default {};
                        };
                        this.decls++;
                    }
                    case (NodeKind.ENUM_DEF)
                    {
                        st_define(this.st, n.text, SymbolKind.ENUM, n.ts, n);
                        this.decls++;
                    }
                    case (NodeKind.VARIABLE_DECLARATION)
                    {
                        switch (n.text != (byte*)0)
                        {
                            case (true) {
                            st_define(this.st, n.text, SymbolKind.VARIABLE, n.ts, n);
                            this.decls++;
                        }
                            default {};
                        };
                    }
                    case (NodeKind.NAMESPACE_DEF)
                    {
                        byte* prev = ts_dup(this.st.current_ns);
                        byte* full;
                        switch (prev[0] == 0)
                        {
                            case (true) { full = ts_dup(n.text); }
                            default {
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
                            switch (w)
                            {
                                case (0) { lst = n.a; }
                                default { lst = n.b; };
                            };
                            switch (lst != (Node*)0)
                            {
                                case (true) {
                                c = node_count(lst, 0);
                                e = 0;
                                while (e < c)
                                {
                                    this.declare_node(node_child(lst, 0, e), full);
                                    e++;
                                };
                            }
                                default {};
                            };
                            w++;
                        };
                        st_set_namespace(this.st, prev);
                        ffree(prev);
                        ffree(full);
                    }
                    default {};
                };
                ->;
            };

            // Registers fn as an overload of key (parameter types from its declaration)
            reg_overload(byte* key, Node* fn) -> void
            {
                int i;
                int cnt = node_count(fn, 0);
                Node* p;
                TypeSpec** ps = (TypeSpec**)fmalloc((u64)(cnt + 1) * (u64)(sizeof(TypeSpec*) / 8));
                while (i < cnt)
                {
                    p = node_child(fn, 0, i);
                    switch (p.ts == (TypeSpec*)0)
                    {
                        case (true) {
                        ffree((byte*)ps);
                        ->;
                    }
                        default {};
                    };
                    ps[i] = p.ts;
                    i++;
                };
                switch (fn.ts == (TypeSpec*)0)
                {
                    case (true) {
                    ffree((byte*)ps);
                    ->;
                }
                    default {};
                };
                this.clear_msg();
                mangle_function(@this.mb, key, ps, cnt, fn.ts);
                st_register_function_overload(this.st, key, this.mb.mem, ps, cnt, fn.ts, fn,
                                              (fn.flags `& NF_DEPRECATED) != 0);
                ffree((byte*)ps);
                ->;
            };

            // Declares every top level symbol of a PROGRAM node
            declare_program(Node* prog) -> int
            {
                int i;
                int cnt = node_count(prog, 0);
                while (i < cnt)
                {
                    this.declare_node(node_child(prog, 0, i), g"\0");
                    i++;
                };
                -> this.decls;
            };

            // Prints diagnostics as file:line:col: severity: message
            print_diags(byte* path) -> void
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
                    switch (d.severity)
                    {
                        case (Severity.ERROR) { print(g": error: \0"); }
                        default { print(g": warning: \0"); };
                    };
                    println(d.msg);
                    i++;
                };
                ->;
            };
        };
    };
};

#endif;
