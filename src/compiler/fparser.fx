// Author: Karac V. Thweatt
//
// fparser.fx - Flux parser library, bootstrap skeleton (port of fparser.py)
//
// What is implemented:
//     the token cursor (advance, expect, peek, mark/reset lookahead),
//     consume and error reporting, synchronize,
//     the lookahead predicates of fparser.py
//         (_is_bare_function_def, is_variable_declaration,
//          is_dual_assign_declaration, _is_type_func_def,
//          _is_trait_prefixed_object),
//     parse() and the statement() dispatch.
//
// What is stubbed:
//     every grammar rule that builds nodes (function_def, struct_def, ...).
//     A stub reports "[BootstrapParser] <feature> not implemented", consumes
//     the construct up to its terminating semicolon (brackets balanced), and
//     returns a placeholder node of the matching NodeKind with no children.
//     Each feature is reported once; verbose mode reports every occurrence.
//
// Usage from fxc.fx:
//
//     #import "fparser.fx";
//     using flux::parser;
//
//     Parser ps(@lx);                 // lx is a Lexer that already tokenized
//     defer ps.__exit();
//     Node* program = ps.parse();     // PROGRAM node, l0 = statements
//     if (ps.failed) { /* ps.err_line, ps.err_col, ps.error_text() */ };

#ifndef FLUX_STANDARD
#import <standard.fx>;
#endif;

#ifndef FLUX_LEXER
#import "flexer.fx";
#endif;

#ifndef FLUX_AST
#import "fast.fx";
#endif;

#ifndef FLUX_TYPES
#import "ftypesys.fx";
#endif;

#ifndef FLUX_CHECK
#import "fcheck.fx";
#endif;

using standard::io::console;
using flux::lexer;
using flux::ast;
using flux::preprocessor;
using flux::types;
using flux::check;

#ifndef FLUX_PARSER
#def FLUX_PARSER 1;

namespace flux
{
    namespace parser
    {
        enum Feat
        {
            FUNCTION_DEF,
            ENUM_DEF,
            MACRO_DEF,
            UNION_DEF,
            STRUCT_DEF,
            TRAIT_DEF,
            EFFECT_DEF,
            INTERFACE_DEF,
            OBJECT_DEF,
            TRAIT_PREFIXED_OBJECT,
            NAMESPACE_DEF,
            USING_STATEMENT,
            NOT_USING_STATEMENT,
            DEPRECATE_STATEMENT,
            EXTERN_STATEMENT,
            EXPORT_STATEMENT,
            CONTRACT_DEF,
            CONSTRA_DEF,
            OPERATOR_DEF,
            TYPE_FUNC_DEF,
            VARIABLE_DECLARATION,
            VARIABLE_DECLARATION_STATEMENT,
            DUAL_ASSIGN_DECLARATION,
            AUTO_VARIABLE_DECLARATION,
            DESTRUCTURING_ASSIGNMENT,
            BLOCK_STATEMENT,
            ASM_STATEMENT,
            FLUXVM_STATEMENT,
            COMPTIME_BLOCK,
            EMITFLUX_STATEMENT,
            IF_STATEMENT,
            WHILE_STATEMENT,
            DO_WHILE_STATEMENT,
            FOR_STATEMENT,
            SWITCH_STATEMENT,
            TRY_STATEMENT,
            RETURN_STATEMENT,
            RETURN_ARROW_RET,
            ERROR_RETURN_STATEMENT,
            BREAK_STATEMENT,
            CONTINUE_STATEMENT,
            LABEL_STATEMENT,
            GOTO_STATEMENT,
            JUMP_STATEMENT,
            THROW_STATEMENT,
            ASSERT_STATEMENT,
            DEFER_STATEMENT,
            ESCAPE_STATEMENT,
            NORETURN_STATEMENT,
            DITTO_STATEMENT,
            CODIFY_STATEMENT,
            EXPRESSION_STATEMENT,
            FSTRING_EXPR,
            ISTRING_EXPR,
            CODIFY_EXPR,
            TEMPLATE_FUNCTION,
            FUNCTION_CONTRACT,
            TEMPLATE_STRUCT,
            TEMPLATE_OBJECT,
            AS_OPERATOR,
            TEMPLATE_OPERATOR,
            CONTRACT_BINDING,
            COUNT
        };

        feature_name(int f) -> byte*
        {
            switch (f)
            {
                case (Feat.FUNCTION_DEF) { -> g"Function Definition\0"; }
                case (Feat.ENUM_DEF) { -> g"Enum Definition\0"; }
                case (Feat.MACRO_DEF) { -> g"Macro Definition\0"; }
                case (Feat.UNION_DEF) { -> g"Union Definition\0"; }
                case (Feat.STRUCT_DEF) { -> g"Struct Definition\0"; }
                case (Feat.TRAIT_DEF) { -> g"Trait Definition\0"; }
                case (Feat.EFFECT_DEF) { -> g"Effect Definition\0"; }
                case (Feat.INTERFACE_DEF) { -> g"Interface Definition\0"; }
                case (Feat.OBJECT_DEF) { -> g"Object Definition\0"; }
                case (Feat.TRAIT_PREFIXED_OBJECT) { -> g"Trait Prefixed Object Definition\0"; }
                case (Feat.NAMESPACE_DEF) { -> g"Namespace Definition\0"; }
                case (Feat.USING_STATEMENT) { -> g"Using Statement\0"; }
                case (Feat.NOT_USING_STATEMENT) { -> g"Not Using Statement\0"; }
                case (Feat.DEPRECATE_STATEMENT) { -> g"Deprecate Statement\0"; }
                case (Feat.EXTERN_STATEMENT) { -> g"Extern Block\0"; }
                case (Feat.EXPORT_STATEMENT) { -> g"Export Block\0"; }
                case (Feat.CONTRACT_DEF) { -> g"Contract Definition\0"; }
                case (Feat.CONSTRA_DEF) { -> g"Constraint Definition\0"; }
                case (Feat.OPERATOR_DEF) { -> g"Operator Definition\0"; }
                case (Feat.TYPE_FUNC_DEF) { -> g"Type Function Definition\0"; }
                case (Feat.VARIABLE_DECLARATION) { -> g"Variable Declaration\0"; }
                case (Feat.VARIABLE_DECLARATION_STATEMENT) { -> g"Variable Declaration Statement\0"; }
                case (Feat.DUAL_ASSIGN_DECLARATION) { -> g"Dual Assign Declaration\0"; }
                case (Feat.AUTO_VARIABLE_DECLARATION) { -> g"Auto Variable Declaration\0"; }
                case (Feat.DESTRUCTURING_ASSIGNMENT) { -> g"Destructuring Assignment\0"; }
                case (Feat.BLOCK_STATEMENT) { -> g"Block Statement\0"; }
                case (Feat.ASM_STATEMENT) { -> g"Inline Assembly\0"; }
                case (Feat.FLUXVM_STATEMENT) { -> g"FluxVM Block\0"; }
                case (Feat.COMPTIME_BLOCK) { -> g"Comptime Block\0"; }
                case (Feat.EMITFLUX_STATEMENT) { -> g"EmitFlux\0"; }
                case (Feat.IF_STATEMENT) { -> g"If Statement\0"; }
                case (Feat.WHILE_STATEMENT) { -> g"While Loop\0"; }
                case (Feat.DO_WHILE_STATEMENT) { -> g"Do Loop\0"; }
                case (Feat.FOR_STATEMENT) { -> g"For Loop\0"; }
                case (Feat.SWITCH_STATEMENT) { -> g"Switch Statement\0"; }
                case (Feat.TRY_STATEMENT) { -> g"Try Block\0"; }
                case (Feat.RETURN_STATEMENT) { -> g"Return Statement\0"; }
                case (Feat.RETURN_ARROW_RET) { -> g"Return Arrow Statement\0"; }
                case (Feat.ERROR_RETURN_STATEMENT) { -> g"Error Return Statement\0"; }
                case (Feat.BREAK_STATEMENT) { -> g"Break Statement\0"; }
                case (Feat.CONTINUE_STATEMENT) { -> g"Continue Statement\0"; }
                case (Feat.LABEL_STATEMENT) { -> g"Label Statement\0"; }
                case (Feat.GOTO_STATEMENT) { -> g"Goto Statement\0"; }
                case (Feat.JUMP_STATEMENT) { -> g"Jump Statement\0"; }
                case (Feat.THROW_STATEMENT) { -> g"Throw Statement\0"; }
                case (Feat.ASSERT_STATEMENT) { -> g"Assert Statement\0"; }
                case (Feat.DEFER_STATEMENT) { -> g"Defer Statement\0"; }
                case (Feat.ESCAPE_STATEMENT) { -> g"Escape Statement\0"; }
                case (Feat.NORETURN_STATEMENT) { -> g"Noreturn Statement\0"; }
                case (Feat.DITTO_STATEMENT) { -> g"Ditto Statement\0"; }
                case (Feat.CODIFY_STATEMENT) { -> g"Codify Statement\0"; }
                case (Feat.EXPRESSION_STATEMENT) { -> g"Expression Statement\0"; }
                case (Feat.FSTRING_EXPR) { -> g"f-string Expression\0"; }
                case (Feat.ISTRING_EXPR) { -> g"i-string Expression\0"; }
                case (Feat.CODIFY_EXPR) { -> g"Codify Expression\0"; }
                case (Feat.TEMPLATE_FUNCTION) { -> g"Template Function\0"; }
                case (Feat.FUNCTION_CONTRACT) { -> g"Function Contract\0"; }
                case (Feat.TEMPLATE_STRUCT) { -> g"Template Struct\0"; }
                case (Feat.TEMPLATE_OBJECT) { -> g"Template Object\0"; }
                case (Feat.AS_OPERATOR) { -> g"Operator Binding (as operator)\0"; }
                case (Feat.TEMPLATE_OPERATOR) { -> g"Template Operator\0"; }
                case (Feat.CONTRACT_BINDING) { -> g"Contract Binding Spec\0"; }
                default { -> g"Unknown Feature\0"; };
            };
        };

        // Error kinds
        enum ParseErr
        {
            NONE,
            MESSAGE,
            EXPECTED,
            ALLOC
        };

        ps_bytes_eq(byte* a, byte* b, int n) -> bool
        {
            int i;
            while (i < n)
            {
                switch (a[i] != b[i])
                {
                    case (true) { -> false; }
                    default {};
                };
                i++;
            };
            -> true;
        };

        // ===== TREE DUMP =====
        // Canonical text form of a tree, one node per line, used to compare against
        // fparser.py (see dump_ast.py).
        //     KIND [op=..] [text=".."] [text2=".."] [val=N] [flags=N] [ts=..]
        // followed by the slots a..e as "a: ..." and list slots as "l0[i]: ...".

        dump_pad(int depth) -> void
        {
            int i;
            while (i < depth)
            {
                print(g"  \0");
                i++;
            };
            ->;
        };

        // Compact form of a TypeSpec
        dump_ts(TypeSpec* t) -> void
        {
            switch (t.custom_typename != (byte*)0)
            {
                case (true) {
                print(t.custom_typename);
            }
                default {
                print(datatype_text(t.base_type));
            };
            };
            switch ((t.flags `& TS_SIGNED) != 0)
            {
                case (true) { print(g",signed\0"); }
                default {};
            };
            switch ((t.flags `& TS_CONST) != 0)
            {
                case (true) { print(g",const\0"); }
                default {};
            };
            switch ((t.flags `& TS_VOLATILE) != 0)
            {
                case (true) { print(g",volatile\0"); }
                default {};
            };
            switch ((t.flags `& TS_TIED) != 0)
            {
                case (true) { print(g",tied\0"); }
                default {};
            };
            switch ((t.flags `& TS_LOCAL) != 0)
            {
                case (true) { print(g",local\0"); }
                default {};
            };
            switch ((t.flags `& TS_NO_FUNCTIONS) != 0)
            {
                case (true) { print(g",nofunc\0"); }
                default {};
            };
            switch (t.bit_width >= 0)
            {
                case (true) { print(g",w\0"); print(t.bit_width); }
                default {};
            };
            switch (t.alignment >= 0)
            {
                case (true) { print(g",a\0"); print(t.alignment); }
                default {};
            };
            switch (t.endianness != 1)
            {
                case (true) { print(g",e\0"); print(t.endianness); }
                default {};
            };
            switch (t.storage_class >= 0)
            {
                case (true) { print(g",sc\0"); print(t.storage_class); }
                default {};
            };
            switch ((t.flags `& TS_POINTER) != 0)
            {
                case (true) { print(g",ptr\0"); print(t.pointer_depth); }
                default {};
            };
            switch ((t.flags `& TS_ARRAY) != 0)
            {
                case (true) {
                print(g",arr\0");
                switch (t.array_dims != (NodeVec*)0)
                {
                    case (true) { print(t.array_dims.len); }
                    default {};
                };
            }
                default {};
            };
            switch (t.base_type == DataType.DICT)
            {
                case (true) {
                print(g"{\0");
                dump_ts(t.dict_key);
                print(g":\0");
                dump_ts(t.dict_value);
                print(g"}\0");
            }
                default {};
            };
            ->;
        };

        dump_quoted(byte* s) -> void
        {
            print(g"\"\0");
            print(s);
            print(g"\"\0");
            ->;
        };

        // slot: -1 none, 0..4 for a..e, 10+s for list slot s (idx is the element index)
        dump_tag(int slot, int idx) -> void
        {
            switch (slot < 0)
            {
                case (true) { ->; }
                default {};
            };
            switch (slot)
            {
                case (0) { print(g"a: \0"); }
                case (1) { print(g"b: \0"); }
                case (2) { print(g"c: \0"); }
                case (3) { print(g"d: \0"); }
                case (4) { print(g"e: \0"); }
                default
                {
                    print(g"l\0");
                    print(slot - 10);
                    print(g"[\0");
                    print(idx);
                    print(g"]: \0");
                };
            };
            ->;
        };

        dump_node(Node* n, int depth, int slot, int idx) -> void
        {
            dump_pad(depth);
            dump_tag(slot, idx);
            switch (n == (Node*)0)
            {
                case (true) {
                println(g"null\0");
                ->;
            }
                default {};
            };
            print(node_kind_name(n.kind));
            int k = n.kind;
            switch (k == NodeKind.BINARY_OP | k == NodeKind.UNARY_OP)
            {
                case (true) {
                print(g" op=\0");
                print(operator_text(n.op));
            }
                default {
                    switch (k == NodeKind.LITERAL)
                    {
                        case (true) {
                print(g" op=\0");
                print(datatype_text(n.op));
                switch (n.op != DataType.FLOAT & n.op != DataType.DOUBLE & n.op != DataType.CHAR)
                {
                    case (true) {
                    print(g" val=\0");
                    print(n.ival);
                }
                    default {};
                };
                switch (n.op == DataType.CHAR & n.text != (byte*)0)
                {
                    case (true) {
                    print(g" text=\0");
                    dump_quoted(n.text);
                }
                    default {};
                };
            }
                        default {
                            switch (k == NodeKind.COMPOUND_ASSIGNMENT)
                            {
                                case (true) {
                print(g" op=\0");
                print(token_name(n.op));
            }
                                default {};
                            };
                        };
                    };
                };
            };
            switch (k != NodeKind.LITERAL)
            {
                case (true) {
                switch (n.text != (byte*)0)
                {
                    case (true) {
                    print(g" text=\0");
                    dump_quoted(n.text);
                }
                    default {};
                };
                switch (n.text2 != (byte*)0)
                {
                    case (true) {
                    print(g" text2=\0");
                    dump_quoted(n.text2);
                }
                    default {};
                };
            }
                default {};
            };
            switch ((n.flags `& (NF_POSTFIX `| NF_NEGATED)) != 0)
            {
                case (true) {
                print(g" flags=\0");
                print(n.flags `& (NF_POSTFIX `| NF_NEGATED));
            }
                default {};
            };
            switch (n.ts != (TypeSpec*)0)
            {
                case (true) {
                print(g" ts=\0");
                dump_ts(n.ts);
            }
                default {};
            };
            println(g"\0");
            switch (n.a != (Node*)0)
            {
                case (true) { dump_node(n.a, depth + 1, 0, 0); }
                default {};
            };
            switch (n.b != (Node*)0)
            {
                case (true) { dump_node(n.b, depth + 1, 1, 0); }
                default {};
            };
            switch (n.c != (Node*)0)
            {
                case (true) { dump_node(n.c, depth + 1, 2, 0); }
                default {};
            };
            switch (n.d != (Node*)0)
            {
                case (true) { dump_node(n.d, depth + 1, 3, 0); }
                default {};
            };
            switch (n.e != (Node*)0)
            {
                case (true) { dump_node(n.e, depth + 1, 4, 0); }
                default {};
            };
            int s, i, cnt;
            while (s < 6)
            {
                cnt = node_count(n, s);
                i = 0;
                while (i < cnt)
                {
                    dump_node(node_child(n, s, i), depth + 1, 10 + s, i);
                    i++;
                };
                s++;
            };
            ->;
        };

        struct OpSym
        {
            int n;
            int* t;
            byte** v;
        };

        struct COp
        {
            int kind;
            OpSym* left;
            OpSym* right;
            byte* func;
        };

        // One registered template (fparser.py TemplateEntry plus the registry bookkeeping)
        struct TemplateEntry
        {
            int kind;               // 0 function, 1 struct, 2 object, 3 operator
            PtrVec* params;         // byte* names in declaration order
            PtrVec* cparam;         // allowed-type lists, flattened: parameter name,
            PtrVec* cts;            //   TypeSpec* (owned) and
            PtrVec* ctext;          //   source text, one triple per alternative
            PtrVec* dparam;         // defaults: parameter name and
            PtrVec* dts;            //   TypeSpec* (owned)
            Node* node;             // the template node (owned)
            Node* rels;             // holder: CONSTRA_RELATION nodes in l1
            NameMap* no_default;    // parameters marked '!+'
            NameMap* emitted;       // mangled names already instantiated
        };

        te_new() -> TemplateEntry*
        {
            TemplateEntry* e = (TemplateEntry*)fmalloc((u64)((sizeof(TemplateEntry) + 7) / 8));
            e.kind = 0;
            e.params = pv_new();
            e.cparam = pv_new();
            e.cts = pv_new();
            e.ctext = pv_new();
            e.dparam = pv_new();
            e.dts = pv_new();
            e.node = (Node*)0;
            e.rels = node_new(NodeKind.CONSTRA_DEF, 0, 0);
            e.no_default = nm_new();
            e.emitted = nm_new();
            -> e;
        };

        te_free(TemplateEntry* e) -> void
        {
            int i;
            switch (e == (TemplateEntry*)0)
            {
                case (true) { ->; }
                default {};
            };
            while (i < e.cts.len)
            {
                typespec_free((TypeSpec*)e.cts.items[i]);
                i++;
            };
            i = 0;
            while (i < e.dts.len)
            {
                typespec_free((TypeSpec*)e.dts.items[i]);
                i++;
            };
            pv_free(e.params);
            pv_free(e.cparam);
            pv_free(e.cts);
            pv_free(e.ctext);
            pv_free(e.dparam);
            pv_free(e.dts);
            node_free(e.node);
            node_free(e.rels);
            nm_free(e.no_default);
            nm_free(e.emitted);
            ffree((byte*)e);
            ->;
        };

        object Parser
        {
            Lexer* lx;
            Token* toks;
            int count, pos;
            int* feat_hits;
            int stub_total, stub_features;
            int err_kind, err_expected, err_got, err_line, err_col;
            byte* err_msg;
            int function_depth, loop_depth, in_comptime, in_trait;
            bool in_for_init;       // parsing the init clause of a for loop
            bool failed, verbose;
            Node* last_stmt;
            NodeVec* pending;       // extra nodes of a flattened list construct, drained by parse()
            NodeVec* block_out;     // statements of a member/array assign block being built
            PtrVec* strs;           // heap strings made while parsing, freed on exit
            Buf sb;                 // scratch for building names
            FXC_SYMTABLE* st;        // optional: resolves type aliases in type_spec
            int default_byte_width; // width of byte when not written (__BYTE_WIDTH__)
            Node* last_call;        // FUNCTION_CALL of the previous expression statement (ditto)
            PtrVec* cops;           // registered custom operators (COp*)
            int cop_mask;           // bit per COp kind present
            OpSym* vop_sym;         // symbol of the variadic operator body being parsed
            PtrVec* contracts;      // CONTRACT_DEF nodes defined so far
            PtrVec* sublex;         // lexers made for string interpolation (nodes borrow their text)
            byte* last_template;    // name of the last template function skipped by function_def
            PtrVec* trait_defs;     // TRAIT_DEF nodes defined so far (owned by the tree)
            byte* ns_path;          // enclosing namespaces joined with __, null at file scope
            NameMap* cstrs;         // byte* string literal initializers by variable name (~$name splicing)
            PtrVec* subparsers;     // fresh parsers made for codify statements (nodes borrow their strings)
            NameMap* constras;      // constra sets defined so far (value is the CONSTRA_DEF node)
            NameMap* templates;     // template name (and aliases) to TemplateEntry*
            PtrVec* tentries;       // every TemplateEntry made (owned)
            NameMap* pobjs;         // fully defined objects by name (fparser._parsed_objects)
            NameMap* oinit;         // objects (and template objects) that define __init
            PtrVec* inh_clone;      // inherited method clones and the node each came from
            PtrVec* inh_orig;
            NameMap* tobj_fwd;      // template objects whose body is being parsed (forward declarations)
            NameMap* active_tp;     // template parameter names in scope while a template is parsed
            TemplateEntry* tmpl_cur; // entry parsed by the function being defined
            PtrVec* tinst_s;        // instantiated template structs (appended after the program)
            PtrVec* tinst_o;        // instantiated template objects
            PtrVec* tinst_f;        // instantiated template functions
            PtrVec* tmp_ts;         // TypeSpecs made while inferring, freed on exit
            Checker* chk; // template constraint checker (created on first use)
            NameMap* macros;        // names of the macros defined so far (the value is only a marker)

            __init(Lexer* lexer) -> this
            {
                int z;
                this.lx = lexer;
                this.toks = (Token*)0;
                this.count = 0;
                this.pos = 0;
                this.stub_total = 0;
                this.stub_features = 0;
                this.err_kind = ParseErr.NONE;
                this.err_expected = 0;
                this.err_got = 0;
                this.err_line = 0;
                this.err_col = 0;
                this.err_msg = (byte*)0;
                this.function_depth = 0;
                this.loop_depth = 0;
                this.in_for_init = false;
                this.in_comptime = 0;
                this.in_trait = 0;
                this.failed = false;
                this.verbose = false;
                this.last_stmt = (Node*)0;
                this.pending = nv_new();
                this.block_out = (NodeVec*)0;
                this.strs = pv_new();
                this.sb.__init();
                this.st = (FXC_SYMTABLE*)0;
                this.default_byte_width = 8;
                this.last_call = (Node*)0;
                this.ns_path = (byte*)0;
                this.last_template = (byte*)0;
                this.trait_defs = pv_new();
                this.cops = pv_new();
                this.cop_mask = 0;
                this.vop_sym = (OpSym*)0;
                this.contracts = pv_new();
                this.sublex = pv_new();
                this.cstrs = nm_new();
                this.subparsers = pv_new();
                this.macros = nm_new();
                this.constras = nm_new();
                this.templates = nm_new();
                this.tentries = pv_new();
                this.active_tp = nm_new();
                this.tobj_fwd = nm_new();
                this.pobjs = nm_new();
                this.oinit = nm_new();
                this.inh_clone = pv_new();
                this.inh_orig = pv_new();
                this.tmpl_cur = (TemplateEntry*)0;
                this.tinst_s = pv_new();
                this.tinst_o = pv_new();
                this.tinst_f = pv_new();
                this.tmp_ts = pv_new();
                this.chk = (Checker*)0;
                this.feat_hits = (int*)fmalloc((u64)Feat.COUNT * (u64)((sizeof(int) + 7) / 8));
                switch (this.feat_hits == (int*)0)
                {
                    case (true) {
                    this.failed = true;
                    this.err_kind = ParseErr.ALLOC;
                    -> this;
                }
                    default {};
                };
                while (z < Feat.COUNT)
                {
                    this.feat_hits[z] = 0;
                    z++;
                };
                -> this;
            };

            __expr() -> Parser* -> this;

            __exit() -> void
            {
                switch (this.feat_hits != (int*)0)
                {
                    case (true) { ffree((byte*)this.feat_hits); }
                    default {};
                };
                this.feat_hits = (int*)0;
                nv_free(this.pending);
                this.pending = (NodeVec*)0;
                int si;
                while (si < this.strs.len)
                {
                    ffree((byte*)this.strs.items[si]);
                    si++;
                };
                pv_free(this.strs);
                pv_free(this.trait_defs);
                int ci;
                COp* cc;
                while (ci < this.cops.len)
                {
                    cc = (COp*)this.cops.items[ci];
                    this.opsym_free(cc.left);
                    this.opsym_free(cc.right);
                    ffree((byte*)cc);
                    ci++;
                };
                pv_free(this.cops);
                pv_free(this.contracts);
                int li;
                Lexer* sl;
                while (li < this.sublex.len)
                {
                    sl = (Lexer*)this.sublex.items[li];
                    sl.__exit();
                    ffree((byte*)sl);
                    li++;
                };
                pv_free(this.sublex);
                int pi;
                Parser* sp;
                while (pi < this.subparsers.len)
                {
                    sp = (Parser*)this.subparsers.items[pi];
                    switch (sp.st != (FXC_SYMTABLE*)0)
                    {
                        case (true) { st_free(sp.st); }
                        default {};
                    };
                    sp.__exit();
                    ffree((byte*)sp);
                    pi++;
                };
                pv_free(this.subparsers);
                nm_free(this.cstrs);
                nm_free(this.macros);
                nm_free(this.constras);
                nm_free(this.templates);
                nm_free(this.active_tp);
                nm_free(this.tobj_fwd);
                nm_free(this.pobjs);
                nm_free(this.oinit);
                pv_free(this.inh_clone);
                pv_free(this.inh_orig);
                pi = 0;
                while (pi < this.tentries.len)
                {
                    te_free((TemplateEntry*)this.tentries.items[pi]);
                    pi++;
                };
                pv_free(this.tentries);
                pi = 0;
                while (pi < this.tinst_s.len)
                {
                    node_free((Node*)this.tinst_s.items[pi]);
                    pi++;
                };
                pi = 0;
                while (pi < this.tinst_o.len)
                {
                    node_free((Node*)this.tinst_o.items[pi]);
                    pi++;
                };
                pi = 0;
                while (pi < this.tinst_f.len)
                {
                    node_free((Node*)this.tinst_f.items[pi]);
                    pi++;
                };
                pv_free(this.tinst_s);
                pv_free(this.tinst_o);
                pv_free(this.tinst_f);
                pi = 0;
                while (pi < this.tmp_ts.len)
                {
                    typespec_free((TypeSpec*)this.tmp_ts.items[pi]);
                    pi++;
                };
                pv_free(this.tmp_ts);
                switch (this.chk != (Checker*)0)
                {
                    case (true) {
                    this.chk.__exit();
                    ffree((byte*)this.chk);
                }
                    default {};
                };
                this.sb.__exit();
                ->;
            };

            // ===== TOKEN CURSOR =====

            cur() -> int -> this.toks[this.pos].type;

            cur_line() -> int -> this.toks[this.pos].line;

            cur_col() -> int -> this.toks[this.pos].column;

            // Value of the current token (null terminated)
            cur_value() -> byte* -> this.lx.token_value(this.pos);

            cur_value_len() -> int -> this.toks[this.pos].vlen;

            // True when the current token value is exactly lit[0, n)
            val_is(byte* lit, int n) -> bool
            {
                switch (this.cur_value_len() != n)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> ps_bytes_eq(this.cur_value(), lit, n);
            };

            // Type of the token at offset off from the current one, -1 outside the stream
            type_at(int off) -> int
            {
                int p = this.pos + off;
                switch (p < 0)
                {
                    case (true) { -> -1; }
                    default {};
                };
                switch (p >= this.count)
                {
                    case (true) { -> -1; }
                    default {};
                };
                -> this.toks[p].type;
            };

            advance() -> void
            {
                switch (this.pos < this.count - 1)
                {
                    case (true) { this.pos++; }
                    default {};
                };
                ->;
            };

            expect(int a) -> bool -> this.cur() == a;

            expect2(int a, int b) -> bool
            {
                int c = this.cur();
                -> c == a | c == b;
            };

            expect3(int a, int b, int d) -> bool
            {
                int c = this.cur();
                -> c == a | c == b | c == d;
            };

            expect4(int a, int b, int d, int e) -> bool
            {
                int c = this.cur();
                -> c == a | c == b | c == d | c == e;
            };

            // Lookahead: save the cursor, run predicates, restore with reset
            mark() -> int -> this.pos;

            reset(int m) -> void
            {
                this.pos = m;
                ->;
            };

            is_calling_conv(int t) -> bool -> t == TokenType.CDECL | t == TokenType.STDCALL | t == TokenType.FASTCALL | t == TokenType.THISCALL | t == TokenType.VECTORCALL;

            // Tokens that can start the base type of a declaration
            is_base_type_token() -> bool -> this.expect4(TokenType.SINT, TokenType.UINT, TokenType.FLOAT_KW, TokenType.DOUBLE_KW) | this.expect4(TokenType.CHAR, TokenType.BOOL_KW, TokenType.BYTE, TokenType.DATA) | this.expect4(TokenType.VOID, TokenType.SLONG, TokenType.ULONG, TokenType.STRUCT) | this.expect3(TokenType.OBJECT, TokenType.IDENTIFIER, TokenType.DICT);

            // ===== ERRORS =====

            // Records a parse error at the current token. Parsing stops at the first error.
            error(byte* msg) -> void
            {
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                this.failed = true;
                this.err_kind = ParseErr.MESSAGE;
                this.err_msg = msg;
                this.err_line = this.cur_line();
                this.err_col = this.cur_col();
                ->;
            };

            fail_expected(int t) -> void
            {
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                this.failed = true;
                this.err_kind = ParseErr.EXPECTED;
                this.err_expected = t;
                this.err_got = this.cur();
                this.err_line = this.cur_line();
                this.err_col = this.cur_col();
                ->;
            };

            // Consumes a token of type t. Records an error and returns false otherwise.
            consume(int t) -> bool
            {
                switch (!this.expect(t))
                {
                    case (true) {
                    this.fail_expected(t);
                    -> false;
                }
                    default {};
                };
                this.advance();
                -> true;
            };

            error_text() -> byte*
            {
                switch (this.err_kind == ParseErr.MESSAGE)
                {
                    case (true) { -> this.err_msg; }
                    default {};
                };
                switch (this.err_kind == ParseErr.ALLOC)
                {
                    case (true) { -> g"parser allocation failed\0"; }
                    default {};
                };
                -> g"parse error\0";
            };

            // Prints the recorded error
            print_error() -> void
            {
                print(g"Parser error: \0");
                switch (this.err_kind)
                {
                    case (ParseErr.EXPECTED)
                    {
                        print(g"Unexpected \0");
                        print(flux::lexer::token_name(this.err_got));
                        print(g", expected \0");
                        print(flux::lexer::token_name(this.err_expected));
                    }
                    default
                    {
                        print(this.error_text());
                    };
                };
                print(g" at \0");
                print(this.err_line);
                print(g":\0");
                println(this.err_col);
                ->;
            };

            // Skips to just after the next statement boundary
            synchronize() -> void
            {
                this.advance();
                while (!this.expect(TokenType.EOF))
                {
                    switch (this.pos > 0)
                    {
                        case (true) {
                        switch (this.toks[this.pos - 1].type == TokenType.SEMICOLON)
                        {
                            case (true) { ->; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (this.expect4(TokenType.DEF, TokenType.STRUCT, TokenType.OBJECT, TokenType.NAMESPACE))
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (this.expect4(TokenType.IF, TokenType.WHILE, TokenType.FOR, TokenType.RETURN))
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.advance();
                };
                ->;
            };

            // ===== STUB SUPPORT =====

            // Consumes tokens through the next semicolon at bracket depth zero.
            // A closing bracket without an opener ends the construct.
            // Returns the number of commas at bracket depth zero outside template
            // arguments, which is how many extra nodes a comma separated list
            // construct (using a, b; int x, y;) yields in fparser.py.
            skip_construct() -> int
            {
                int depth, t, prev, angle, commas;
                bool in_init = false;
                prev = -1;
                while (true)
                {
                    t = this.cur();
                    switch (t == TokenType.EOF)
                    {
                        case (true) { -> commas; }
                        default {};
                    };
                    switch (t == TokenType.LEFT_PAREN | t == TokenType.LEFT_BRACKET | t == TokenType.LEFT_BRACE)
                    {
                        case (true) {
                        depth++;
                    }
                        default {
                            switch (t == TokenType.RIGHT_PAREN | t == TokenType.RIGHT_BRACKET | t == TokenType.RIGHT_BRACE)
                            {
                                case (true) {
                        depth--;
                    }
                                default {
                                    switch (depth == 0)
                                    {
                                        case (true) {
                        switch (t == TokenType.SEMICOLON)
                        {
                            case (true) {
                            this.advance();
                            -> commas;
                        }
                            default {
                                switch (t == TokenType.ASSIGN | t == TokenType.ADDRESS_ASSIGN)
                                {
                                    case (true) {
                            in_init = true;
                        }
                                    default {
                                        switch (t == TokenType.LESS_THAN & prev == TokenType.IDENTIFIER & !in_init)
                                        {
                                            case (true) {
                            angle++;
                        }
                                            default {
                                                switch (t == TokenType.GREATER_THAN & angle > 0)
                                                {
                                                    case (true) {
                            angle--;
                        }
                                                    default {
                                                        switch (t == TokenType.BITSHIFT_RIGHT & angle > 1)
                                                        {
                                                            case (true) {
                            angle = angle - 2;
                        }
                                                            default {
                                                                switch (t == TokenType.COMMA & angle == 0)
                                                                {
                                                                    case (true) {
                            commas++;
                            in_init = false;
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
                    }
                                        default {};
                                    };
                                };
                            };
                        };
                    };
                    prev = t;
                    this.advance();
                    switch (depth < 0)
                    {
                        case (true) { -> commas; }
                        default {};
                    };
                };
                -> commas;
            };

            // Features whose fparser.py rule returns one node per comma separated name
            is_list_feature(int feat) -> bool -> feat == Feat.USING_STATEMENT | feat == Feat.CONTRACT_DEF | feat == Feat.VARIABLE_DECLARATION | feat == Feat.VARIABLE_DECLARATION_STATEMENT;

            // Reports an unimplemented feature, skips the construct and returns a placeholder node
            stub(int feat, int kind) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = node_new(kind, line, col);
                switch (n == (Node*)0)
                {
                    case (true) {
                    this.failed = true;
                    this.err_kind = ParseErr.ALLOC;
                    -> n;
                }
                    default {};
                };
                n.flags = NF_STUB;

                this.stub_total++;
                switch (this.feat_hits[feat] == 0)
                {
                    case (true) { this.stub_features++; }
                    default {};
                };
                this.feat_hits[feat] = this.feat_hits[feat] + 1;

                switch (this.verbose)
                {
                    case (true) {
                    print(g"[BootstrapParser] \0");
                    print(feature_name(feat));
                    print(g" not implemented (line \0");
                    print(line);
                    print(g", col \0");
                    print(col);
                    println(g")\0");
                }
                    default {
                        switch (this.feat_hits[feat] == 1)
                        {
                            case (true) {
                    print(g"[BootstrapParser] \0");
                    print(feature_name(feat));
                    println(g" not implemented\0");
                }
                            default {};
                        };
                    };
                };

                int extra = this.skip_construct();
                Node* x;
                switch (this.is_list_feature(feat))
                {
                    case (true) {
                    while (extra > 0)
                    {
                        x = node_new(kind, line, col);
                        switch (x == (Node*)0)
                        {
                            case (true) { break; }
                            default {};
                        };
                        x.flags = NF_STUB;
                        nv_push(this.pending, x);
                        extra--;
                    };
                }
                    default {};
                };
                -> n;
            };

            // Prints how often each unimplemented feature was hit
            report() -> void
            {
                int f;
                switch (this.stub_total == 0)
                {
                    case (true) { ->; }
                    default {};
                };
                println(g"[BootstrapParser] Stub summary:\0");
                while (f < Feat.COUNT)
                {
                    switch (this.feat_hits[f] != 0)
                    {
                        case (true) {
                        print(g"  \0");
                        print(feature_name(f));
                        print(g" : \0");
                        println(this.feat_hits[f]);
                    }
                        default {};
                    };
                    f++;
                };
                print(g"[BootstrapParser] \0");
                print(this.stub_total);
                print(g" construct(s) skipped across \0");
                print(this.stub_features);
                println(g" feature(s)\0");
                ->;
            };

            // ===== LOOKAHEAD PREDICATES =====

            // (NO_MANGLE)? IDENTIFIER '(' ... ')' '->'
            is_bare_function_def() -> bool
            {
                int m = this.mark();
                int depth;
                bool r = false;
                switch (this.expect(TokenType.NO_MANGLE))
                {
                    case (true) { this.advance(); }
                    default {};
                };
                switch (this.expect(TokenType.IDENTIFIER))
                {
                    case (true) {
                    this.advance();
                    switch (this.expect(TokenType.LEFT_PAREN))
                    {
                        case (true) {
                        this.advance();
                        depth = 1;
                        while (depth > 0 & !this.expect(TokenType.EOF))
                        {
                            switch (this.expect(TokenType.LEFT_PAREN))
                            {
                                case (true) {
                                depth++;
                            }
                                default {
                                    switch (this.expect(TokenType.RIGHT_PAREN))
                                    {
                                        case (true) {
                                depth--;
                                switch (depth == 0)
                                {
                                    case (true) { break; }
                                    default {};
                                };
                            }
                                        default {};
                                    };
                                };
                            };
                            this.advance();
                        };
                        switch (this.expect(TokenType.RIGHT_PAREN))
                        {
                            case (true) {
                            this.advance();
                            r = this.expect(TokenType.RETURN_ARROW);
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                this.reset(m);
                -> r;
            };

            // IDENTIFIER+ 'object'
            is_trait_prefixed_object() -> bool
            {
                int off = 1;
                int t;
                switch (!this.expect(TokenType.IDENTIFIER))
                {
                    case (true) { -> false; }
                    default {};
                };
                while (true)
                {
                    t = this.type_at(off);
                    switch (t < 0)
                    {
                        case (true) { -> false; }
                        default {};
                    };
                    switch (t == TokenType.OBJECT)
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    switch (t != TokenType.IDENTIFIER)
                    {
                        case (true) { -> false; }
                        default {};
                    };
                    off++;
                };
                -> false;
            };

            // Skips a balanced <...> region starting at the current '<'
            skip_template_args() -> void
            {
                int depth = 1;
                this.advance();
                while (depth > 0 & !this.expect(TokenType.EOF))
                {
                    switch (this.expect(TokenType.LESS_THAN))
                    {
                        case (true) {
                        depth++;
                    }
                        default {
                            switch (this.expect(TokenType.GREATER_THAN))
                            {
                                case (true) {
                        depth--;
                        switch (depth == 0)
                        {
                            case (true) { break; }
                            default {};
                        };
                    }
                                default {};
                            };
                        };
                    };
                    this.advance();
                };
                switch (this.expect(TokenType.GREATER_THAN))
                {
                    case (true) { this.advance(); }
                    default {};
                };
                ->;
            };

            // Skips a balanced [...] region starting at the current '['
            skip_brackets() -> void
            {
                int depth = 1;
                this.advance();
                while (depth > 0 & !this.expect(TokenType.EOF))
                {
                    switch (this.expect(TokenType.LEFT_BRACKET))
                    {
                        case (true) {
                        depth++;
                    }
                        default {
                            switch (this.expect(TokenType.RIGHT_BRACKET))
                            {
                                case (true) {
                        depth--;
                        switch (depth == 0)
                        {
                            case (true) { break; }
                            default {};
                        };
                    }
                                default {};
                            };
                        };
                    };
                    this.advance();
                };
                switch (this.expect(TokenType.RIGHT_BRACKET))
                {
                    case (true) { this.advance(); }
                    default {};
                };
                ->;
            };

            is_variable_declaration() -> bool
            {
                int m = this.mark();
                bool r = false;
                bool done = false;

                switch (this.expect(TokenType.CONST))
                {
                    case (true) { this.advance(); }
                    default {};
                };
                switch (this.expect(TokenType.VOLATILE))
                {
                    case (true) { this.advance(); }
                    default {};
                };
                switch (this.expect2(TokenType.SIGNED, TokenType.UNSIGNED))
                {
                    case (true) { this.advance(); }
                    default {};
                };
                switch (this.expect(TokenType.TIE))
                {
                    case (true) { this.advance(); }
                    default {};
                };

                switch (!this.is_base_type_token())
                {
                    case (true) {
                    this.reset(m);
                    -> false;
                }
                    default {};
                };
                this.advance();

                while (this.expect(TokenType.SCOPE))
                {
                    this.advance();
                    switch (this.expect(TokenType.IDENTIFIER))
                    {
                        case (true) {
                        this.advance();
                    }
                        default {
                        break;
                    };
                    };
                };

                switch (this.expect(TokenType.LESS_THAN))
                {
                    case (true) { this.skip_template_args(); }
                    default {};
                };

                switch (this.expect(TokenType.LEFT_BRACE))
                {
                    case (true) {
                    this.advance();
                    switch (this.expect(TokenType.SINT_LITERAL))
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                    switch (this.expect(TokenType.COLON))
                    {
                        case (true) {
                        this.advance();
                        switch (this.expect(TokenType.SINT_LITERAL))
                        {
                            case (true) { this.advance(); }
                            default {};
                        };
                    }
                        default {
                            switch (this.expect(TokenType.SCOPE))
                            {
                                case (true) {
                        this.advance();
                        switch (this.expect(TokenType.SINT_LITERAL))
                        {
                            case (true) { this.advance(); }
                            default {};
                        };
                    }
                                default {};
                            };
                        };
                    };
                    switch (this.expect(TokenType.RIGHT_BRACE))
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                }
                    default {};
                };

                while (this.expect(TokenType.MULTIPLY)) { this.advance(); };

                while (this.expect(TokenType.LEFT_BRACKET))
                {
                    this.skip_brackets();
                };

                while (this.expect(TokenType.MULTIPLY)) { this.advance(); };

                switch (this.expect(TokenType.AS))
                {
                    case (true) {
                    this.advance();
                    switch (this.expect(TokenType.VOID))
                    {
                        case (true) {
                        r = false;
                    }
                        default {
                        r = this.expect(TokenType.IDENTIFIER);
                    };
                    };
                    done = true;
                }
                    default {};
                };

                switch (!done)
                {
                    case (true) {
                    switch (this.expect(TokenType.IDENTIFIER))
                    {
                        case (true) {
                        this.advance();
                        r = this.expect4(TokenType.ASSIGN, TokenType.SEMICOLON, TokenType.LEFT_PAREN, TokenType.LEFT_BRACE)
                          | this.expect4(TokenType.COMMA, TokenType.LEFT_BRACKET, TokenType.FROM, TokenType.ADDRESS_ASSIGN);
                    }
                        default {};
                    };
                }
                    default {};
                };

                this.reset(m);
                -> r;
            };

            // success_type ^| error_type success_name, error_name = call();
            is_dual_assign_declaration() -> bool
            {
                int m = this.mark();
                bool r = false;

                switch (this.expect(TokenType.CONST))
                {
                    case (true) { this.advance(); }
                    default {};
                };
                switch (this.expect(TokenType.VOLATILE))
                {
                    case (true) { this.advance(); }
                    default {};
                };
                switch (this.expect2(TokenType.SIGNED, TokenType.UNSIGNED))
                {
                    case (true) { this.advance(); }
                    default {};
                };

                switch (!this.is_base_type_token())
                {
                    case (true) {
                    this.reset(m);
                    -> false;
                }
                    default {};
                };
                this.advance();

                while (this.expect(TokenType.SCOPE))
                {
                    this.advance();
                    switch (this.expect(TokenType.IDENTIFIER))
                    {
                        case (true) {
                        this.advance();
                    }
                        default {
                        break;
                    };
                    };
                };

                switch (this.expect(TokenType.LESS_THAN))
                {
                    case (true) { this.skip_template_args(); }
                    default {};
                };

                switch (this.expect(TokenType.LEFT_BRACE))
                {
                    case (true) {
                    this.advance();
                    switch (this.expect(TokenType.SINT_LITERAL))
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                    switch (this.expect2(TokenType.COLON, TokenType.SCOPE))
                    {
                        case (true) {
                        this.advance();
                        switch (this.expect(TokenType.SINT_LITERAL))
                        {
                            case (true) { this.advance(); }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (this.expect(TokenType.RIGHT_BRACE))
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                }
                    default {};
                };

                while (this.expect(TokenType.MULTIPLY)) { this.advance(); };

                while (this.expect(TokenType.LEFT_BRACKET))
                {
                    this.skip_brackets();
                };

                r = this.expect(TokenType.XOR_OP);
                this.reset(m);
                -> r;
            };

            // Tokens that can start the receiver of a type function definition
            is_type_func_receiver(int t) -> bool -> t == TokenType.BYTE | t == TokenType.SINT | t == TokenType.UINT | t == TokenType.SLONG | t == TokenType.ULONG | t == TokenType.FLOAT_KW | t == TokenType.DOUBLE_KW | t == TokenType.BOOL_KW | t == TokenType.TRUE | t == TokenType.FALSE | t == TokenType.SINT_LITERAL | t == TokenType.UINT_LITERAL | t == TokenType.SLONG_LITERAL | t == TokenType.ULONG_LITERAL | t == TokenType.FLOAT | t == TokenType.DOUBLE | t == TokenType.CHAR | t == TokenType.STRING_LITERAL | t == TokenType.F_STRING | t == TokenType.I_STRING;

            // RECEIVER.func_name([params]) -> return_type
            is_type_func_def() -> bool
            {
                int m = this.mark();
                int depth, depth_t;
                int t;
                bool r = false;
                bool ok = true;

                switch (this.expect(TokenType.TIE))
                {
                    case (true) { this.advance(); }
                    default {};
                };
                t = this.cur();
                switch (this.is_type_func_receiver(t))
                {
                    case (true) {
                    this.advance();
                }
                    default {
                        switch (t == TokenType.IDENTIFIER)
                        {
                            case (true) {
                    this.advance();
                }
                            default {
                    this.reset(m);
                    -> false;
                };
                        };
                    };
                };

                while (this.expect(TokenType.MULTIPLY)) { this.advance(); };

                switch (this.expect(TokenType.LEFT_BRACKET))
                {
                    case (true) {
                    this.advance();
                    switch (!this.expect(TokenType.RIGHT_BRACKET))
                    {
                        case (true) { ok = false; }
                        default {};
                    };
                    switch (ok)
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                }
                    default {};
                };

                switch (ok)
                {
                    case (true) {
                    switch (!this.expect(TokenType.DOT))
                    {
                        case (true) { ok = false; }
                        default {};
                    };
                }
                    default {};
                };
                switch (ok)
                {
                    case (true) {
                    this.advance();
                    switch (!this.expect4(TokenType.IDENTIFIER, TokenType.STRING_LITERAL, TokenType.F_STRING, TokenType.I_STRING))
                    {
                        case (true) { ok = false; }
                        default {};
                    };
                }
                    default {};
                };
                switch (ok)
                {
                    case (true) {
                    this.advance();
                    switch (this.expect2(TokenType.LESS_THAN, TokenType.RECURSE_ARROW))
                    {
                        case (true) {
                        this.advance();
                        depth_t = 1;
                        while (depth_t > 0 & !this.expect(TokenType.EOF))
                        {
                            switch (this.expect2(TokenType.LESS_THAN, TokenType.RECURSE_ARROW))
                            {
                                case (true) {
                                depth_t++;
                            }
                                default {
                                    switch (this.expect(TokenType.GREATER_THAN))
                                    {
                                        case (true) {
                                depth_t--;
                                switch (depth_t == 0)
                                {
                                    case (true) { break; }
                                    default {};
                                };
                            }
                                        default {};
                                    };
                                };
                            };
                            this.advance();
                        };
                        switch (!this.expect(TokenType.GREATER_THAN))
                        {
                            case (true) {
                            ok = false;
                        }
                            default {
                            this.advance();
                        };
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (ok)
                {
                    case (true) {
                    switch (!this.expect(TokenType.LEFT_PAREN))
                    {
                        case (true) { ok = false; }
                        default {};
                    };
                }
                    default {};
                };
                switch (ok)
                {
                    case (true) {
                    this.advance();
                    depth = 1;
                    while (depth > 0 & !this.expect(TokenType.EOF))
                    {
                        switch (this.expect(TokenType.LEFT_PAREN))
                        {
                            case (true) {
                            depth++;
                        }
                            default {
                                switch (this.expect(TokenType.RIGHT_PAREN))
                                {
                                    case (true) {
                            depth--;
                            switch (depth == 0)
                            {
                                case (true) { break; }
                                default {};
                            };
                        }
                                    default {};
                                };
                            };
                        };
                        this.advance();
                    };
                    switch (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        case (true) { ok = false; }
                        default {};
                    };
                }
                    default {};
                };
                switch (ok)
                {
                    case (true) {
                    this.advance();
                    r = this.expect(TokenType.RETURN_ARROW);
                }
                    default {};
                };

                this.reset(m);
                -> r;
            };

            // ===== GRAMMAR RULES (STUBS) =====

            // macro_def -> 'macro' IDENTIFIER '(' (IDENTIFIER (',' IDENTIFIER)*)? ')' '{' expression ';'? '}' ';'
            // The name is registered before the body is parsed so a recursive call in the body
            // becomes a MACRO_CALL. The ';' inside the braces is a terminator, not part of the body.
            macro_def() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* s = this.mk(NodeKind.MACRO_DEF_STATEMENT, line, col);
                switch (this.failed)
                {
                    case (true) { -> s; }
                    default {};
                };
                Node* d = this.mk(NodeKind.MACRO_DEF, line, col);
                switch (this.failed)
                {
                    case (true) {
                    node_free(s);
                    -> d;
                }
                    default {};
                };
                s.a = d;
                Node* p;
                bool more;
                this.advance();
                d.text = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.done(s); }
                    default {};
                };
                switch (!this.consume(TokenType.LEFT_PAREN))
                {
                    case (true) { -> this.done(s); }
                    default {};
                };
                switch (!this.expect(TokenType.RIGHT_PAREN))
                {
                    case (true) {
                    more = true;
                    while (more & !this.failed)
                    {
                        p = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        node_push(d, 0, p);
                        p.text = this.ident();
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        more = this.expect(TokenType.COMMA);
                        switch (more)
                        {
                            case (true) { this.advance(); }
                            default {};
                        };
                    };
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(s); }
                    default {};
                };
                nm_put(this.macros, d.text, (void*)this.macros);
                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { -> this.done(s); }
                    default {};
                };
                d.a = this.expression();
                switch (this.failed)
                {
                    case (true) { -> this.done(s); }
                    default {};
                };
                switch (this.expect(TokenType.SEMICOLON))
                {
                    case (true) { this.advance(); }
                    default {};
                };
                switch (!this.consume(TokenType.RIGHT_BRACE))
                {
                    case (true) { -> this.done(s); }
                    default {};
                };
                this.consume(TokenType.SEMICOLON);
                -> this.done(s);
            };

            // effect_def -> 'effect' IDENTIFIER ('.' IDENTIFIER)* '{' effect_expr '}' ';'
            effect_def() -> Node*
            {
                Node* n = this.mk(NodeKind.EFFECT_DEF, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                byte* sub;
                this.advance();
                byte* name = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.done(n); }
                    default {};
                };
                while (this.expect(TokenType.DOT))
                {
                    this.advance();
                    sub = this.ident();
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    name = this.cat2(this.cat2(name, g".\0"), sub);
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { n.a = this.effect_expr(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                n.text = name;
                -> this.done(n);
            };

            // Error text of the form "<msg> [line:col]" at the current token (fparser.py raises SyntaxError)
            interface_error(byte* head, byte* name, byte* tail) -> void
            {
                this.sb.len = 0;
                this.sb.put_str(head);
                switch (name != (byte*)0)
                {
                    case (true) {
                    this.sb.put_str(name);
                    this.sb.put_str(g"' must have a trait constraint (e.g. \0");
                    this.sb.put_str(name);
                    this.sb.put_str(tail);
                }
                    default {
                    this.sb.put_str(tail);
                };
                };
                this.sb.put_str(g" [\0");
                this.sb.put_int(this.cur_line());
                this.sb.put(':');
                this.sb.put_int(this.cur_col());
                this.sb.put(']');
                this.error(this.own_n(this.sb.mem, this.sb.len));
                ->;
            };

            // '{' prototype (',' prototype)* '}'  with  prototype -> IDENTIFIER '(' (type IDENTIFIER (',' type IDENTIFIER)*)? ')' '->' type
            // Each prototype is a FUNCTION_DEF flagged NF_PROTOTYPE with an empty body, pushed to holder.l0.
            interface_protos(Node* holder) -> void
            {
                int pl, pc;
                Node* f;
                Node* prm;
                bool more;
                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { ->; }
                    default {};
                };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    pl = this.cur_line();
                    pc = this.cur_col();
                    f = this.mk(NodeKind.FUNCTION_DEF, pl, pc);
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    node_push(holder, 0, f);
                    f.text = this.ident();
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.LEFT_PAREN); }
                        default {};
                    };
                    switch (!this.failed & !this.expect(TokenType.RIGHT_PAREN))
                    {
                        case (true) {
                        more = true;
                        while (more & !this.failed)
                        {
                            prm = this.mk(NodeKind.PARAMETER, pl, pc);
                            switch (this.failed)
                            {
                                case (true) { break; }
                                default {};
                            };
                            node_push(f, 0, prm);
                            prm.ts = this.type_spec();
                            switch (this.failed)
                            {
                                case (true) { break; }
                                default {};
                            };
                            prm.text = this.ident();
                            switch (this.failed)
                            {
                                case (true) { break; }
                                default {};
                            };
                            more = this.expect(TokenType.COMMA);
                            switch (more)
                            {
                                case (true) { this.advance(); }
                                default {};
                            };
                        };
                    }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RETURN_ARROW); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { f.ts = this.type_spec(); }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.mark_proto(f);
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (this.expect(TokenType.COMMA))
                    {
                        case (true) { this.advance(); }
                        default { break; };
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                ->;
            };

            // interface_def -> 'interface' IDENTIFIER '(' (IDENTIFIER ':' IDENTIFIER (',' ...)*)? ')'
            //                  '{' (protocol ';')* '}' ('#' ('effect' | 'attenuate') '{' effect_expr '}')* ';'
            //   protocol -> IDENTIFIER ':' IDENTIFIER protos      A : B   CALL_ON
            //             | IDENTIFIER '(' IDENTIFIER ')' protos  B(A)    PASS_INTO (caller A, callee B)
            //             | IDENTIFIER '->' IDENTIFIER protos     A -> B  RETURN_TO
            interface_def() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.INTERFACE_DEF, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                Node* p;
                Node* pr;
                byte* first;
                bool more;
                this.advance();
                n.text = this.ident();
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_PAREN); }
                    default {};
                };
                switch (!this.failed & !this.expect(TokenType.RIGHT_PAREN))
                {
                    case (true) {
                    more = true;
                    while (more & !this.failed)
                    {
                        p = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        node_push(n, 0, p);
                        p.text = this.ident();
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        switch (!this.expect(TokenType.COLON))
                        {
                            case (true) {
                            this.interface_error(g"Interface parameter '\0", p.text, g": SomeTrait)\0");
                            break;
                        }
                            default {};
                        };
                        this.advance();
                        p.text2 = this.ident();
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        more = this.expect(TokenType.COMMA);
                        switch (more)
                        {
                            case (true) { this.advance(); }
                            default {};
                        };
                    };
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_BRACE); }
                    default {};
                };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    pr = this.mk(NodeKind.INTERFACE_PROTOCOL, line, col);
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    node_push(n, 1, pr);
                    first = this.ident();
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    switch (this.expect(TokenType.COLON))
                    {
                        case (true) {
                        this.advance();
                        pr.text = first;
                        pr.text2 = this.ident();
                        pr.op = ProtocolKind.CALL_ON;
                    }
                        default {
                            switch (this.expect(TokenType.LEFT_PAREN))
                            {
                                case (true) {
                        this.advance();
                        pr.text = this.ident();
                        switch (!this.failed)
                        {
                            case (true) { this.consume(TokenType.RIGHT_PAREN); }
                            default {};
                        };
                        pr.text2 = first;
                        pr.op = ProtocolKind.PASS_INTO;
                    }
                                default {
                                    switch (this.expect(TokenType.RETURN_ARROW))
                                    {
                                        case (true) {
                        this.advance();
                        pr.text = first;
                        pr.text2 = this.ident();
                        pr.op = ProtocolKind.RETURN_TO;
                    }
                                        default {
                        this.interface_error(g"Expected ':', '(' or '->' in interface protocol block\0", (byte*)0, g"\0");
                        break;
                    };
                                    };
                                };
                            };
                        };
                    };
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    this.interface_protos(pr);
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                while (!this.failed & this.expect(TokenType.TAG))
                {
                    this.advance();
                    switch (this.expect(TokenType.EFFECT))
                    {
                        case (true) {
                        node_free(n.b);
                        n.b = this.effect_annotation(NodeKind.EFFECT_ANNOTATION);
                    }
                        default {
                            switch (this.expect(TokenType.IDENTIFIER) & this.val_is(g"attenuate\0", 9))
                            {
                                case (true) {
                        node_free(n.a);
                        n.a = this.effect_annotation(NodeKind.ATTENUATE_ANNOTATION);
                    }
                                default {
                        this.error(g"Expected 'effect' or 'attenuate' after '#' in interface definition\0");
                    };
                            };
                        };
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // deprecate_statement -> 'deprecate' IDENTIFIER ('::' IDENTIFIER)* ';'
            // The path keeps "::" separators, as in fparser.py.
            deprecate_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.DEPRECATE_STATEMENT, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.advance();
                byte* path = this.ident();
                byte* part;
                while (!this.failed & this.expect(TokenType.SCOPE))
                {
                    this.advance();
                    part = this.ident();
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    path = this.cat2(this.cat2(path, g"::\0"), part);
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                n.text = path;
                -> this.done(n);
            };

            // ----- templates: registry and parameter lists -----

            // Active template parameter names while a template definition is parsed
            tp_active(byte* name) -> bool
            {
                switch (this.active_tp == (NameMap*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> nm_has(this.active_tp, name);
            };

            tp_activate(TemplateEntry* e) -> void
            {
                NameMap* a = nm_new();
                int i;
                while (i < e.params.len)
                {
                    nm_put(a, (byte*)e.params.items[i], (void*)a);
                    i++;
                };
                this.active_tp = a;
                ->;
            };

            // IDENTIFIER, or a codify splice when allowed
            tp_id(bool cg) -> byte*
            {
                switch (cg & this.expect(TokenType.CODIFY))
                {
                    case (true) { -> this.consume_codify(); }
                    default {};
                };
                -> this.ident();
            };

            // names joined by '&'
            tp_idlist(bool cg) -> PtrVec*
            {
                PtrVec* v = pv_new();
                pv_push(v, (void*)this.tp_id(cg));
                while (!this.failed & this.expect(TokenType.LOGICAL_AND))
                {
                    this.advance();
                    pv_push(v, (void*)this.tp_id(cg));
                };
                -> v;
            };

            // Source-like text of a type for constraint messages (fparser._ts_repr_simple)
            tp_repr(TypeSpec* t) -> byte*
            {
                int i;
                this.sb.len = 0;
                switch (t.custom_typename != (byte*)0)
                {
                    case (true) { this.sb.put_str(t.custom_typename); }
                    default { this.sb.put_str(datatype_text(t.base_type)); };
                };
                switch (ts_is_pointer(t))
                {
                    case (true) {
                    while (i < t.pointer_depth)
                    {
                        this.sb.put('*');
                        i++;
                    };
                }
                    default {};
                };
                switch (ts_is_array(t))
                {
                    case (true) { this.sb.put_str(g"[]\0"); }
                    default {};
                };
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            // Name mapped through the zip of from and to (the last duplicate wins)
            tp_map_name(PtrVec* fnames, PtrVec* to, byte* n) -> byte*
            {
                int i = fnames.len;
                switch (to.len < i)
                {
                    case (true) { i = to.len; }
                    default {};
                };
                while (i > 0)
                {
                    i--;
                    switch (cstr_eq((byte*)fnames.items[i], n))
                    {
                        case (true) { -> (byte*)to.items[i]; }
                        default {};
                    };
                };
                -> n;
            };

            // Copies the relations of constra set cs into e, mapping its formals onto to
            tp_copy_rels(TemplateEntry* e, Node* cs, PtrVec* to) -> void
            {
                PtrVec* fnames = pv_new();
                PtrVec* lhs;
                PtrVec* rhs;
                Node* rel;
                int i, k, n;
                while (i < node_count(cs, 0))
                {
                    pv_push(fnames, (void*)node_child(cs, 0, i).text);
                    i++;
                };
                i = 0;
                n = node_count(cs, 1);
                while (i < n & !this.failed)
                {
                    rel = node_child(cs, 1, i);
                    lhs = pv_new();
                    rhs = pv_new();
                    k = 0;
                    while (k < node_count(rel, 0))
                    {
                        pv_push(lhs, (void*)this.tp_map_name(fnames, to, node_child(rel, 0, k).text));
                        k++;
                    };
                    k = 0;
                    while (k < node_count(rel, 1))
                    {
                        pv_push(rhs, (void*)this.tp_map_name(fnames, to, node_child(rel, 1, k).text));
                        k++;
                    };
                    this.cs_emit(e.rels, lhs, rel.text, rhs, rel.line, rel.col);
                    pv_free(lhs);
                    pv_free(rhs);
                    i++;
                };
                pv_free(fnames);
                ->;
            };

            tp_has_param(TemplateEntry* e, byte* n) -> bool
            {
                int i;
                while (i < e.params.len)
                {
                    switch (cstr_eq((byte*)e.params.items[i], n))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    i++;
                };
                -> false;
            };

            // One entry of ':{ ... }': a named constra (with or without arguments) or a raw relation
            tp_cs_entry(TemplateEntry* e, bool cg) -> void
            {
                int m = this.mark();
                int line = this.cur_line();
                int col = this.cur_col();
                bool codify = false;
                byte* name;
                Node* csd;
                PtrVec* args;
                PtrVec* lhs;
                PtrVec* rhs;
                byte* op;
                int i;
                switch (cg & this.expect(TokenType.CODIFY))
                {
                    case (true) {
                    name = this.consume_codify();
                    codify = true;
                }
                    default {
                    name = this.ident();
                };
                };
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (!codify & this.expect(TokenType.LEFT_PAREN))
                {
                    case (true) {
                    switch (!nm_has(this.constras, name))
                    {
                        case (true) {
                        this.sb.len = 0;
                        this.sb.put_str(g"Unknown named constraint set '\0");
                        this.sb.put_str(name);
                        this.sb.put('\'');
                        this.cs_error_at(m);
                        ->;
                    }
                        default {};
                    };
                    csd = (Node*)nm_get(this.constras, name);
                    this.advance();
                    args = pv_new();
                    switch (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        case (true) {
                        pv_push(args, (void*)this.ident());
                        while (!this.failed & this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            pv_push(args, (void*)this.ident());
                        };
                    }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) {
                        pv_free(args);
                        ->;
                    }
                        default {};
                    };
                    switch (args.len != node_count(csd, 0))
                    {
                        case (true) {
                        this.sb.len = 0;
                        this.sb.put_str(g"Named constraint set '\0");
                        this.sb.put_str(name);
                        this.sb.put_str(g"' expects \0");
                        this.sb.put_int(node_count(csd, 0));
                        this.sb.put_str(g" argument(s), got \0");
                        this.sb.put_int(args.len);
                        this.cs_error_at(m);
                        pv_free(args);
                        ->;
                    }
                        default {};
                    };
                    i = 0;
                    while (i < args.len)
                    {
                        switch (!this.tp_has_param(e, (byte*)args.items[i]))
                        {
                            case (true) {
                            this.sb.len = 0;
                            this.sb.put('\'');
                            this.sb.put_str((byte*)args.items[i]);
                            this.sb.put_str(g"' is not a template parameter; valid parameters are: \0");
                            this.tp_put_params(e);
                            this.error(this.own_n(this.sb.mem, this.sb.len));
                            pv_free(args);
                            ->;
                        }
                            default {};
                        };
                        i++;
                    };
                    this.tp_copy_rels(e, csd, args);
                    pv_free(args);
                    ->;
                }
                    default {};
                };
                switch (!codify & nm_has(this.constras, name) & !(this.expect(TokenType.LOGICAL_AND) | this.is_relop()))
                {
                    case (true) {
                    csd = (Node*)nm_get(this.constras, name);
                    switch (e.params.len != node_count(csd, 0))
                    {
                        case (true) {
                        this.sb.len = 0;
                        this.sb.put_str(g"Named constraint set '\0");
                        this.sb.put_str(name);
                        this.sb.put_str(g"' has \0");
                        this.sb.put_int(node_count(csd, 0));
                        this.sb.put_str(g" parameter(s) but the template has \0");
                        this.sb.put_int(e.params.len);
                        this.sb.put_str(g" parameter(s); use explicit arguments: '\0");
                        this.sb.put_str(name);
                        this.sb.put_str(g"(...)'\0");
                        this.cs_error_at(m);
                        ->;
                    }
                        default {};
                    };
                    this.tp_copy_rels(e, csd, e.params);
                    ->;
                }
                    default {};
                };
                lhs = pv_new();
                pv_push(lhs, (void*)name);
                while (!this.failed & this.expect(TokenType.LOGICAL_AND))
                {
                    this.advance();
                    pv_push(lhs, (void*)this.tp_id(cg));
                };
                switch (!this.failed)
                {
                    case (true) {
                    op = this.consume_relop();
                    switch (!this.failed)
                    {
                        case (true) {
                        rhs = this.tp_idlist(cg);
                        switch (!this.failed)
                        {
                            case (true) { this.cs_emit(e.rels, lhs, op, rhs, line, col); }
                            default {};
                        };
                        pv_free(rhs);
                    }
                        default {};
                    };
                }
                    default {};
                };
                pv_free(lhs);
                ->;
            };

            // Template parameter names joined with ", " into sb
            tp_put_params(TemplateEntry* e) -> void
            {
                int i;
                while (i < e.params.len)
                {
                    switch (i > 0)
                    {
                        case (true) { this.sb.put_str(g", \0"); }
                        default {};
                    };
                    this.sb.put_str((byte*)e.params.items[i]);
                    i++;
                };
                ->;
            };

            // ':' '{' entry (',' entry)* '}'
            tp_constraint_set(TemplateEntry* e, bool cg) -> void
            {
                this.consume(TokenType.COLON);
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.tp_cs_entry(e, cg); }
                    default {};
                };
                while (!this.failed & this.expect(TokenType.COMMA))
                {
                    this.advance();
                    this.tp_cs_entry(e, cg);
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                ->;
            };

            // name (':' ['+'] type ('|' ['+'] type)*)?
            tp_param_entry(TemplateEntry* e, byte* name) -> void
            {
                pv_push(e.params, (void*)name);
                switch (!this.expect(TokenType.COLON))
                {
                    case (true) { ->; }
                    default {};
                };
                this.advance();
                bool saw_default = false;
                bool is_def, more;
                int dm = -1;
                TypeSpec* ts;
                TypeSpec* dts = (TypeSpec*)0;
                byte* src;
                more = true;
                while (more & !this.failed)
                {
                    is_def = this.expect(TokenType.PLUS);
                    switch (is_def)
                    {
                        case (true) {
                        switch (dm < 0)
                        {
                            case (true) { dm = this.mark(); }
                            default {};
                        };
                        this.advance();
                        saw_default = true;
                    }
                        default {};
                    };
                    src = (byte*)0;
                    switch (this.expect(TokenType.STRING_LITERAL))
                    {
                        case (true) { src = g"\"\"\0"; }
                        default {};
                    };
                    ts = this.type_spec();
                    switch (this.failed)
                    {
                        case (true) {
                        switch (ts != (TypeSpec*)0)
                        {
                            case (true) { typespec_free(ts); }
                            default {};
                        };
                        ->;
                    }
                        default {};
                    };
                    switch (src == (byte*)0)
                    {
                        case (true) { src = this.tp_repr(ts); }
                        default {};
                    };
                    pv_push(e.cparam, (void*)name);
                    pv_push(e.cts, (void*)ts);
                    pv_push(e.ctext, (void*)src);
                    switch (is_def)
                    {
                        case (true) { dts = ts; }
                        default {};
                    };
                    more = this.expect(TokenType.LOGICAL_OR);
                    switch (more)
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                };
                switch (this.failed | !saw_default)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (nm_has(e.no_default, name))
                {
                    case (true) {
                    this.reset(dm);
                    this.sb.len = 0;
                    this.sb.put_str(g"Template parameter '\0");
                    this.sb.put_str(name);
                    this.sb.put_str(g"' is marked '!+' (no default) but a default type was supplied with '+'\0");
                    this.error(this.own_n(this.sb.mem, this.sb.len));
                    ->;
                }
                    default {};
                };
                pv_push(e.dparam, (void*)name);
                pv_push(e.dts, (void*)typespec_copy(dts));
                ->;
            };

            // The relational-constraint-in-the-wrong-place error of a parameter list
            tp_rel_misplaced(byte* id, bool first) -> void
            {
                this.sb.len = 0;
                this.sb.put_str(g"Relational template constraints must be wrapped in a constraint set\0");
                switch (first)
                {
                    case (true) { this.sb.put_str(g" as :{T ~= U}. Did you mean :{\0"); }
                    default { this.sb.put_str(g": :{T ~= U}. Did you mean :{\0"); };
                };
                this.sb.put_str(id);
                this.sb.put_str(g" ~= ...}, or did you intend a type constraint \0");
                this.sb.put_str(id);
                this.sb.put_str(g": ?\0");
                this.error(this.own_n(this.sb.mem, this.sb.len));
                ->;
            };

            // One list entry after the cursor: ':{...}' or ['!+'] name constraint
            tp_entry(TemplateEntry* e, bool cg, bool first) -> void
            {
                bool nd = false;
                byte* id;
                switch (this.expect(TokenType.COLON))
                {
                    case (true) {
                    this.tp_constraint_set(e, cg);
                    ->;
                }
                    default {};
                };
                switch (this.expect(TokenType.NOT))
                {
                    case (true) {
                    this.advance();
                    this.consume(TokenType.PLUS);
                    nd = true;
                }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                id = this.tp_id(cg);
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (nd)
                {
                    case (true) { nm_put(e.no_default, id, (void*)e); }
                    default {};
                };
                switch (this.expect(TokenType.LOGICAL_AND) | this.is_relop())
                {
                    case (true) {
                    this.tp_rel_misplaced(id, first);
                    ->;
                }
                    default {};
                };
                this.tp_param_entry(e, id);
                ->;
            };

            // '<' entries '>' (cursor on '<'). Returns a new entry without a node, or null on error.
            template_params(bool cg) -> TemplateEntry*
            {
                TemplateEntry* e = te_new();
                this.advance();
                this.tp_entry(e, cg, true);
                while (!this.failed & this.expect(TokenType.COMMA))
                {
                    this.advance();
                    this.tp_entry(e, cg, false);
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.GREATER_THAN); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) {
                    te_free(e);
                    -> (TemplateEntry*)0;
                }
                    default {};
                };
                -> e;
            };

            template_lookup(byte* name) -> TemplateEntry*
            {
                switch (name == (byte*)0)
                {
                    case (true) { -> (TemplateEntry*)0; }
                    default {};
                };
                switch (!nm_has(this.templates, name))
                {
                    case (true) { -> (TemplateEntry*)0; }
                    default {};
                };
                -> (TemplateEntry*)nm_get(this.templates, name);
            };

            template_alias(byte* alias, byte* original) -> void
            {
                switch (!nm_has(this.templates, original))
                {
                    case (true) { ->; }
                    default {};
                };
                nm_put(this.templates, this.own(ts_dup(alias)), nm_get(this.templates, original));
                ->;
            };

            // Registers e (parsed parameters) with its template node under name.
            // Mirrors TemplateRegistry.register: an entry of the same kind is updated in place.
            register_template(byte* name, int kind, TemplateEntry* e, Node* node) -> void
            {
                TemplateEntry* ex = this.template_lookup(name);
                PtrVec* tv;
                Node* tn;
                NameMap* tm;
                int i;
                switch (ex != (TemplateEntry*)0 & ex.kind == kind)
                {
                    case (true) {
                    tv = ex.params; ex.params = e.params; e.params = tv;
                    tn = ex.node; ex.node = node; node_free(tn);
                    switch (e.cparam.len > 0)
                    {
                        case (true) {
                        tv = ex.cparam; ex.cparam = e.cparam; e.cparam = tv;
                        tv = ex.cts; ex.cts = e.cts; e.cts = tv;
                        tv = ex.ctext; ex.ctext = e.ctext; e.ctext = tv;
                    }
                        default {};
                    };
                    switch (node_count(e.rels, 1) > 0)
                    {
                        case (true) {
                        tn = ex.rels; ex.rels = e.rels; e.rels = tn;
                    }
                        default {};
                    };
                    switch (e.dparam.len > 0)
                    {
                        case (true) {
                        tv = ex.dparam; ex.dparam = e.dparam; e.dparam = tv;
                        tv = ex.dts; ex.dts = e.dts; e.dts = tv;
                    }
                        default {};
                    };
                    switch (e.no_default.count > 0)
                    {
                        case (true) {
                        tm = ex.no_default; ex.no_default = e.no_default; e.no_default = tm;
                    }
                        default {};
                    };
                    te_free(e);
                    ->;
                }
                    default {};
                };
                e.kind = kind;
                e.node = node;
                nm_put(this.templates, this.own(ts_dup(name)), (void*)e);
                pv_push(this.tentries, (void*)e);
                ->;
            };

            // ----- templates: instantiation -----

            // Records an error at an explicit position
            error_at(byte* msg, int line, int col) -> void
            {
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                this.failed = true;
                this.err_kind = ParseErr.MESSAGE;
                this.err_msg = msg;
                this.err_line = line;
                this.err_col = col;
                ->;
            };

            // The shared checker used for template constraints (created on first use)
            chk_get() -> Checker*
            {
                switch (this.chk == (Checker*)0)
                {
                    case (true) {
                    this.chk = (Checker*)fmalloc((u64)((sizeof(Checker) + 7) / 8));
                    this.chk.__init(this.st);
                }
                    default {};
                };
                -> this.chk;
            };

            // Reports the diagnostic number first (and later ones are ignored) as the parse error
            chk_fail(int first) -> void
            {
                Diag* d = (Diag*)this.chk.diags.items[first];
                this.error_at(this.own(ts_dup(d.msg)), d.line, d.col);
                ->;
            };

            // Short identifying text of a type for name mangling (fparser._type_system_to_mangle_str)
            ts_mangle(TypeSpec* t) -> byte*
            {
                TypeSpec* inner;
                byte* s;
                switch (t.custom_typename != (byte*)0)
                {
                    case (true) { -> t.custom_typename; }
                    default {};
                };
                switch (ts_is_pointer(t))
                {
                    case (true) {
                    inner = typespec_new();
                    inner.base_type = t.base_type;
                    inner.bit_width = t.bit_width;
                    inner.flags = TS_SIGNED;
                    s = this.ts_mangle(inner);
                    typespec_free(inner);
                    -> this.cat2(g"ptr_\0", s);
                }
                    default {};
                };
                switch (t.base_type == DataType.DATA & t.bit_width > 0)
                {
                    case (true) {
                    this.sb.len = 0;
                    this.sb.put_str(g"data_\0");
                    switch (ts_is_signed(t))
                    {
                        case (true) { this.sb.put('i'); }
                        default { this.sb.put('u'); };
                    };
                    this.sb.put_int(t.bit_width);
                    -> this.own_n(this.sb.mem, this.sb.len);
                }
                    default {};
                };
                -> datatype_text(t.base_type);
            };

            // A TypeSpec owned by the parser until it exits
            tmp_type() -> TypeSpec*
            {
                TypeSpec* t = typespec_new();
                pv_push(this.tmp_ts, (void*)t);
                -> t;
            };

            // Parameter name to TypeSpec* mapping (fparser._build_template_mapping)
            tp_mapping(TemplateEntry* te, PtrVec* names, PtrVec* specs) -> NameMap*
            {
                NameMap* m = nm_new();
                int i, k;
                TypeSpec* r;
                byte* tn;
                while (i < te.params.len & i < names.len)
                {
                    tn = (byte*)names.items[i];
                    r = (TypeSpec*)0;
                    switch (specs != (PtrVec*)0)
                    {
                        case (true) {
                        switch (i < specs.len)
                        {
                            case (true) { r = (TypeSpec*)specs.items[i]; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (r == (TypeSpec*)0 & this.st != (FXC_SYMTABLE*)0)
                    {
                        case (true) { r = st_get_type_spec(this.st, tn); }
                        default {};
                    };
                    k = 0;
                    while (r == (TypeSpec*)0 & k < 18)
                    {
                        switch (cstr_eq(datatype_text(k), tn))
                        {
                            case (true) {
                            r = this.tmp_type();
                            r.base_type = k;
                            switch (k == DataType.SINT | k == DataType.CHAR)
                            {
                                case (true) { r.flags = TS_SIGNED; }
                                default {};
                            };
                        }
                            default {};
                        };
                        k++;
                    };
                    switch (r == (TypeSpec*)0)
                    {
                        case (true) {
                        r = this.tmp_type();
                        r.base_type = DataType.DATA;
                        r.custom_typename = tn;
                    }
                        default {};
                    };
                    nm_put(m, (byte*)te.params.items[i], (void*)r);
                    i++;
                };
                -> m;
            };

            // Substitutes template parameters in t. Frees t and returns the replacement
            // (fparser._substitute_type).
            subst_ts(TypeSpec* t, NameMap* map) -> TypeSpec*
            {
                TypeSpec* r;
                switch (t == (TypeSpec*)0)
                {
                    case (true) { -> t; }
                    default {};
                };
                switch (t.base_type == DataType.DICT)
                {
                    case (true) {
                    t.dict_key = this.subst_ts(t.dict_key, map);
                    t.dict_value = this.subst_ts(t.dict_value, map);
                    -> t;
                }
                    default {};
                };
                switch (t.custom_typename == (byte*)0)
                {
                    case (true) { -> t; }
                    default {};
                };
                switch (!nm_has(map, t.custom_typename))
                {
                    case (true) {
                    t.custom_typename = this.subst_deferred_type(t.custom_typename, map);
                    -> t;
                }
                    default {};
                };
                r = typespec_copy((TypeSpec*)nm_get(map, t.custom_typename));
                switch (ts_is_pointer(t))
                {
                    case (true) {
                    r.flags = r.flags `| TS_POINTER;
                    r.pointer_depth = r.pointer_depth + t.pointer_depth;
                }
                    default {};
                };
                switch (ts_is_array(t))
                {
                    case (true) {
                    r.flags = r.flags `| TS_ARRAY;
                    r.array_dims = nv_clone(t.array_dims);
                    switch (r.array_dims != (NodeVec*)0)
                    {
                        case (true) {
                        switch (r.array_dims.len > 0)
                        {
                            case (true) { r.array_size = r.array_dims.items[0]; }
                            default {};
                        };
                    }
                        default {
                        r.array_size = node_clone(t.array_size);
                    };
                    };
                }
                    default {};
                };
                switch ((t.flags `& TS_CONST) != 0)
                {
                    case (true) { r.flags = r.flags `| TS_CONST; }
                    default {};
                };
                switch ((t.flags `& TS_VOLATILE) != 0)
                {
                    case (true) { r.flags = r.flags `| TS_VOLATILE; }
                    default {};
                };
                typespec_free(t);
                -> r;
            };

            // Splits the arguments of a deferred "name<a,b>" text. Returns the byte index of '<' or -1.
            tp_split_deferred(byte* s, PtrVec* out) -> int
            {
                int i, lt, start, e;
                int n = pp_cstrlen(s);
                lt = -1;
                while (i < n & lt < 0)
                {
                    switch (s[i] == '<')
                    {
                        case (true) { lt = i; }
                        default {};
                    };
                    i++;
                };
                switch (lt < 0)
                {
                    case (true) { -> -1; }
                    default {};
                };
                switch (s[n - 1] != '>')
                {
                    case (true) { -> -1; }
                    default {};
                };
                start = lt + 1;
                i = start;
                while (i <= n - 1)
                {
                    switch (i == n - 1 | s[i] == ',')
                    {
                        case (true) {
                        e = i;
                        while (start < e & s[start] == ' ') { start++; };
                        while (e > start & s[e - 1] == ' ') { e--; };
                        pv_push(out, (void*)this.own_n(s + start, e - start));
                        start = i + 1;
                    }
                        default {};
                    };
                    i++;
                };
                -> lt;
            };

            // Rewrites a deferred call "f<T,U>" whose arguments are now known (fparser._substitute_node)
            subst_deferred_call(Node* n, NameMap* map) -> void
            {
                PtrVec* raw = pv_new();
                PtrVec* names = pv_new();
                PtrVec* specs = pv_new();
                int lt = this.tp_split_deferred(n.text, raw);
                int i;
                bool any = false;
                byte* base;
                TemplateEntry* fe;
                TypeSpec* c;
                byte* a;
                switch (lt > 0)
                {
                    case (true) {
                    base = this.own_n(n.text, lt);
                    fe = this.template_lookup(base);
                    while (i < raw.len)
                    {
                        switch (nm_has(map, (byte*)raw.items[i]))
                        {
                            case (true) { any = true; }
                            default {};
                        };
                        i++;
                    };
                    switch (fe != (TemplateEntry*)0 & any & fe.kind == 0)
                    {
                        case (true) {
                        i = 0;
                        while (i < raw.len)
                        {
                            a = (byte*)raw.items[i];
                            switch (nm_has(map, a))
                            {
                                case (true) {
                                c = (TypeSpec*)nm_get(map, a);
                                pv_push(names, (void*)this.ts_mangle(c));
                                pv_push(specs, (void*)c);
                            }
                                default {
                                c = this.tmp_type();
                                c.base_type = DataType.DATA;
                                c.custom_typename = a;
                                pv_push(names, (void*)a);
                                pv_push(specs, (void*)c);
                            };
                            };
                            i++;
                        };
                        n.text = this.resolve_template_call(base, names, specs, (PtrVec*)0);
                    }
                        default {};
                    };
                }
                    default {};
                };
                pv_free(raw);
                pv_free(names);
                pv_free(specs);
                ->;
            };

            // Deep substitution over a cloned template tree (fparser._substitute_node)
            subst_node(Node* n, NameMap* map) -> void
            {
                int s, i, c;
                switch (n == (Node*)0 | this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                n.ts = this.subst_ts(n.ts, map);
                n.ts2 = this.subst_ts(n.ts2, map);
                switch (n.kind == NodeKind.SIZE_OF | n.kind == NodeKind.ALIGN_OF | n.kind == NodeKind.ENDIAN_OF)
                {
                    case (true) {
                    switch (n.a != (Node*)0 & n.ts == (TypeSpec*)0)
                    {
                        case (true) {
                        switch (n.a.kind == NodeKind.IDENTIFIER)
                        {
                            case (true) {
                            switch (nm_has(map, n.a.text))
                            {
                                case (true) {
                                n.ts = typespec_copy((TypeSpec*)nm_get(map, n.a.text));
                                node_free(n.a);
                                n.a = (Node*)0;
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (n.kind == NodeKind.FUNCTION_CALL & n.text != (byte*)0)
                {
                    case (true) {
                    this.subst_deferred_call(n, map);
                }
                    default {};
                };
                this.subst_node(n.a, map);
                this.subst_node(n.b, map);
                this.subst_node(n.c, map);
                this.subst_node(n.d, map);
                this.subst_node(n.e, map);
                s = 0;
                while (s < 6)
                {
                    c = node_count(n, s);
                    i = 0;
                    while (i < c)
                    {
                        this.subst_node(node_child(n, s, i), map);
                        i++;
                    };
                    s++;
                };
                ->;
            };

            // The registry entry holding the constraints for fname: the entry itself, or the
            // entry of the bare name when fname is namespace qualified (name__bare).
            tp_constraint_entry(byte* fname, TemplateEntry* te, bool want_rels) -> TemplateEntry*
            {
                int i, ln, lk, k;
                bool found;
                bool suffix;
                TemplateEntry* ce;
                byte* key;
                switch (want_rels)
                {
                    case (true) { found = node_count(te.rels, 1) > 0; }
                    default { found = te.cparam.len > 0; };
                };
                switch (found)
                {
                    case (true) { -> te; }
                    default {};
                };
                ln = pp_cstrlen(fname);
                while (i < this.templates.count)
                {
                    key = this.templates.keys[i];
                    ce = (TemplateEntry*)this.templates.vals[i];
                    i++;
                    switch (key == (byte*)0 | ce == (TemplateEntry*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    lk = pp_cstrlen(key);
                    suffix = cstr_eq(fname, key);
                    switch (!suffix & ln > lk + 2)
                    {
                        case (true) {
                        suffix = true;
                        k = 0;
                        while (k < lk)
                        {
                            switch (fname[ln - lk + k] != key[k])
                            {
                                case (true) { suffix = false; }
                                default {};
                            };
                            k++;
                        };
                        switch (fname[ln - lk - 1] != '_' | fname[ln - lk - 2] != '_')
                        {
                            case (true) { suffix = false; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (!suffix)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (want_rels)
                    {
                        case (true) { found = node_count(ce.rels, 1) > 0; }
                        default { found = ce.cparam.len > 0; };
                    };
                    switch (found)
                    {
                        case (true) { -> ce; }
                        default {};
                    };
                };
                -> te;
            };

            // Allowed-type lists of every parameter against the concrete types
            tp_check_allowed(byte* fname, TemplateEntry* ce, TemplateEntry* te, PtrVec* specs, PtrVec* poss) -> void
            {
                int i, j, cnt, line, col, first;
                byte* pname;
                TypeSpec** allowed;
                PtrVec* texts;
                TypeSpec* concrete;
                Node* at;
                Checker* k;
                while (i < te.params.len & !this.failed)
                {
                    pname = (byte*)te.params.items[i];
                    cnt = 0;
                    j = 0;
                    while (j < ce.cparam.len)
                    {
                        switch (cstr_eq((byte*)ce.cparam.items[j], pname))
                        {
                            case (true) { cnt++; }
                            default {};
                        };
                        j++;
                    };
                    concrete = (TypeSpec*)0;
                    switch (specs != (PtrVec*)0)
                    {
                        case (true) {
                        switch (i < specs.len)
                        {
                            case (true) { concrete = (TypeSpec*)specs.items[i]; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (cnt > 0 & concrete != (TypeSpec*)0)
                    {
                        case (true) {
                        allowed = (TypeSpec**)fmalloc((u64)cnt * (u64)((sizeof(TypeSpec*) + 7) / 8));
                        this.sb.len = 0;
                        cnt = 0;
                        j = 0;
                        while (j < ce.cparam.len)
                        {
                            switch (cstr_eq((byte*)ce.cparam.items[j], pname))
                            {
                                case (true) {
                                allowed[cnt] = (TypeSpec*)ce.cts.items[j];
                                switch (cnt > 0)
                                {
                                    case (true) { this.sb.put_str(g" | \0"); }
                                    default {};
                                };
                                this.sb.put_str((byte*)ce.ctext.items[j]);
                                cnt++;
                            }
                                default {};
                            };
                            j++;
                        };
                        line = this.cur_line();
                        col = this.cur_col();
                        switch (poss != (PtrVec*)0)
                        {
                            case (true) {
                            switch (i < poss.len)
                            {
                                case (true) {
                                at = (Node*)poss.items[i];
                                switch (at != (Node*)0)
                                {
                                    case (true) {
                                    line = at.line;
                                    col = at.col;
                                }
                                    default {};
                                };
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                        k = this.chk_get();
                        first = k.diags.len;
                        switch (!k.check_allowed(fname, pname, concrete, allowed, cnt, this.own_n(this.sb.mem, this.sb.len), line, col))
                        {
                            case (true) {
                            this.chk_fail(first);
                        }
                            default {};
                        };
                        ffree((byte*)allowed);
                    }
                        default {};
                    };
                    i++;
                };
                ->;
            };

            // Instantiates the template function fname with the given concrete types and returns the
            // name to call (fparser._resolve_template_call). poss holds, per parameter, the argument
            // node the type came from (null entries or a null vector use the current token).
            resolve_template_call(byte* fname, PtrVec* names, PtrVec* specs, PtrVec* poss) -> byte*
            {
                TemplateEntry* te = this.template_lookup(fname);
                TemplateEntry* ce;
                NameMap* map;
                Node* concrete;
                TypeSpec** argv;
                byte* mangled;
                int i, first;
                Checker* k;
                switch (te == (TemplateEntry*)0)
                {
                    case (true) {
                    this.error(this.cat2(this.cat2(g"Unknown template function '\0", fname), g"'\0"));
                    -> fname;
                }
                    default {};
                };
                switch (te.kind != 0)
                {
                    case (true) {
                    this.error(this.cat2(this.cat2(g"Unknown template function '\0", fname), g"'\0"));
                    -> fname;
                }
                    default {};
                };
                switch (names.len != te.params.len)
                {
                    case (true) {
                    this.sb.len = 0;
                    this.sb.put_str(g"Template function '\0");
                    this.sb.put_str(fname);
                    this.sb.put_str(g"' expects \0");
                    this.sb.put_int(te.params.len);
                    this.sb.put_str(g" type argument(s), got \0");
                    this.sb.put_int(names.len);
                    this.error(this.own_n(this.sb.mem, this.sb.len));
                    -> fname;
                }
                    default {};
                };
                ce = this.tp_constraint_entry(fname, te, false);
                this.tp_check_allowed(fname, ce, te, specs, poss);
                switch (this.failed)
                {
                    case (true) { -> fname; }
                    default {};
                };

                this.sb.len = 0;
                this.sb.put_str(fname);
                this.sb.put_str(g"__tmpl__\0");
                i = 0;
                while (i < names.len)
                {
                    switch (i > 0)
                    {
                        case (true) { this.sb.put_str(g"__\0"); }
                        default {};
                    };
                    this.sb.put_str((byte*)names.items[i]);
                    i++;
                };
                mangled = this.own_n(this.sb.mem, this.sb.len);
                switch (nm_has(te.emitted, mangled))
                {
                    case (true) { -> fname; }
                    default {};
                };
                nm_put(te.emitted, mangled, (void*)te);

                map = this.tp_mapping(te, names, specs);
                concrete = node_clone(te.node);
                this.subst_node(concrete, map);
                switch (this.failed)
                {
                    case (true) {
                    nm_free(map);
                    node_free(concrete);
                    -> fname;
                }
                    default {};
                };

                ce = this.tp_constraint_entry(fname, te, true);
                switch (node_count(ce.rels, 1) > 0)
                {
                    case (true) {
                    argv = (TypeSpec**)fmalloc((u64)te.params.len * (u64)((sizeof(TypeSpec*) + 7) / 8));
                    i = 0;
                    while (i < te.params.len)
                    {
                        argv[i] = (TypeSpec*)nm_get(map, (byte*)te.params.items[i]);
                        i++;
                    };
                    k = this.chk_get();
                    first = k.diags.len;
                    switch (k.check_relations(te.params, argv, te.params.len, ce.rels.l1, te.node, concrete) > 0)
                    {
                        case (true) {
                        this.chk_fail(first);
                    }
                        default {};
                    };
                    ffree((byte*)argv);
                }
                    default {};
                };
                nm_free(map);
                switch (this.failed)
                {
                    case (true) {
                    node_free(concrete);
                    -> fname;
                }
                    default {};
                };
                concrete.text = fname;
                switch ((concrete.flags `& NF_NO_MANGLE) != 0)
                {
                    case (true) { concrete.flags = concrete.flags - NF_NO_MANGLE; }
                    default {};
                };
                pv_push(this.tinst_f, (void*)concrete);
                -> fname;
            };

            // Called after every binary expression: instantiates a template operator registered for
            // the operator symbol when both operand types are known (fparser._try_instantiate_template_op)
            try_template_op(Node* n) -> void
            {
                byte* key = operator_text(n.op);
                TemplateEntry* te = this.template_lookup(key);
                TypeSpec* lts;
                TypeSpec* rts;
                switch (te == (TemplateEntry*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (te.kind != 3)
                {
                    case (true) { ->; }
                    default {};
                };
                lts = this.infer_arg_type(n.a);
                switch (lts == (TypeSpec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                rts = this.infer_arg_type(n.b);
                switch (rts == (TypeSpec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                this.resolve_template_operator(key, te, lts, rts);
                ->;
            };

            // Binds template parameter pn from the concrete operand type c (fparser._resolve_template_operator)
            op_infer_param(TemplateEntry* te, NameMap* inferred, TypeSpec* decl, TypeSpec* c) -> void
            {
                PtrVec* raw;
                TypeSpec* r;
                TypeSpec* res;
                byte* dn = decl.custom_typename;
                byte* cn;
                byte* base;
                byte* rem;
                byte* pname;
                int lt, bl, k, dd, cd;
                bool pre;
                switch (dn == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (this.tp_has_param(te, dn))
                {
                    case (true) {
                    r = c;
                    switch (ts_is_pointer(c) & ts_is_pointer(decl))
                    {
                        case (true) {
                        r = typespec_copy(c);
                        pv_push(this.tmp_ts, (void*)r);
                        cd = c.pointer_depth;
                        switch (cd == 0)
                        {
                            case (true) { cd = 1; }
                            default {};
                        };
                        dd = decl.pointer_depth;
                        switch (dd == 0)
                        {
                            case (true) { dd = 1; }
                            default {};
                        };
                        r.pointer_depth = cd - dd;
                        switch (r.pointer_depth < 0)
                        {
                            case (true) { r.pointer_depth = 0; }
                            default {};
                        };
                        switch (r.pointer_depth == 0 & (r.flags `& TS_POINTER) != 0)
                        {
                            case (true) { r.flags = r.flags - TS_POINTER; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (!nm_has(inferred, dn))
                    {
                        case (true) { nm_put(inferred, dn, (void*)r); }
                        default {};
                    };
                    ->;
                }
                    default {};
                };
                raw = pv_new();
                lt = this.tp_split_deferred(dn, raw);
                switch (lt > 0)
                {
                    case (true) {
                    base = this.own_n(dn, lt);
                    cn = c.custom_typename;
                    bl = pp_cstrlen(base);
                    pre = false;
                    switch (cn != (byte*)0)
                    {
                        case (true) {
                        pre = pp_cstrlen(cn) > bl + 2;
                        k = 0;
                        while (pre & k < bl)
                        {
                            switch (cn[k] != base[k])
                            {
                                case (true) { pre = false; }
                                default {};
                            };
                            k++;
                        };
                        switch (pre)
                        {
                            case (true) {
                            switch (cn[bl] != '_' | cn[bl + 1] != '_')
                            {
                                case (true) { pre = false; }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (pre & raw.len == 1)
                    {
                        case (true) {
                        pname = (byte*)raw.items[0];
                        switch (this.tp_has_param(te, pname) & !nm_has(inferred, pname))
                        {
                            case (true) {
                            rem = cn + bl + 2;
                            res = (TypeSpec*)0;
                            switch (this.st != (FXC_SYMTABLE*)0)
                            {
                                case (true) { res = st_get_type_spec(this.st, rem); }
                                default {};
                            };
                            k = 0;
                            while (res == (TypeSpec*)0 & k < 18)
                            {
                                switch (cstr_eq(datatype_text(k), rem))
                                {
                                    case (true) {
                                    res = this.tmp_type();
                                    res.base_type = k;
                                }
                                    default {};
                                };
                                k++;
                            };
                            switch (res == (TypeSpec*)0)
                            {
                                case (true) {
                                res = this.tmp_type();
                                res.base_type = DataType.DATA;
                                res.custom_typename = rem;
                            }
                                default {};
                            };
                            nm_put(inferred, pname, (void*)res);
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                pv_free(raw);
                ->;
            };

            op_is_non_builtin(TypeSpec* t) -> bool
            {
                switch (t.custom_typename != (byte*)0)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (t.base_type == DataType.STRUCT | t.base_type == DataType.OBJECT)
                {
                    case (true) { -> true; }
                    default {};
                };
                -> ts_is_pointer(t);
            };

            resolve_template_operator(byte* key, TemplateEntry* te, TypeSpec* lts, TypeSpec* rts) -> void
            {
                Node* f = te.node;
                PtrVec* names;
                PtrVec* specs;
                NameMap* inferred;
                NameMap* map;
                Node* concrete;
                TypeSpec* c;
                byte* mangled;
                int i;
                switch (f == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (node_count(f, 0) != 2)
                {
                    case (true) { ->; }
                    default {};
                };
                specs = pv_new();
                names = pv_new();
                switch (te.params.len != 2)
                {
                    case (true) {
                    inferred = nm_new();
                    i = 0;
                    while (i < 2)
                    {
                        c = lts;
                        switch (i == 1)
                        {
                            case (true) { c = rts; }
                            default {};
                        };
                        switch (node_child(f, 0, i).ts != (TypeSpec*)0)
                        {
                            case (true) { this.op_infer_param(te, inferred, node_child(f, 0, i).ts, c); }
                            default {};
                        };
                        i++;
                    };
                    i = 0;
                    while (i < te.params.len)
                    {
                        switch (!nm_has(inferred, (byte*)te.params.items[i]))
                        {
                            case (true) {
                            nm_free(inferred);
                            pv_free(specs);
                            pv_free(names);
                            ->;
                        }
                            default {};
                        };
                        pv_push(specs, nm_get(inferred, (byte*)te.params.items[i]));
                        i++;
                    };
                    nm_free(inferred);
                }
                    default {
                    pv_push(specs, (void*)lts);
                    pv_push(specs, (void*)rts);
                };
                };
                switch (!this.op_is_non_builtin(lts) & !this.op_is_non_builtin(rts))
                {
                    case (true) {
                    pv_free(specs);
                    pv_free(names);
                    ->;
                }
                    default {};
                };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                this.sb.put_str(f.text);
                this.sb.put_str(g"__tmpl__\0");
                i = 0;
                while (i < specs.len)
                {
                    switch (i > 0)
                    {
                        case (true) { this.sb.put_str(g"__\0"); }
                        default {};
                    };
                    this.sb.put_str(this.ts_mangle((TypeSpec*)specs.items[i]));
                    i++;
                };
                mangled = this.own_n(this.sb.mem, this.sb.len);
                i = 0;
                while (i < specs.len)
                {
                    pv_push(names, (void*)this.ts_mangle((TypeSpec*)specs.items[i]));
                    i++;
                };
                switch (nm_has(te.emitted, mangled))
                {
                    case (true) {
                    pv_free(specs);
                    pv_free(names);
                    ->;
                }
                    default {};
                };
                nm_put(te.emitted, mangled, (void*)te);
                map = this.tp_mapping(te, names, specs);
                pv_free(specs);
                pv_free(names);
                concrete = node_clone(f);
                this.subst_node(concrete, map);
                nm_free(map);
                switch (this.failed)
                {
                    case (true) {
                    node_free(concrete);
                    ->;
                }
                    default {};
                };
                switch ((concrete.flags `& NF_NO_MANGLE) != 0)
                {
                    case (true) { concrete.flags = concrete.flags - NF_NO_MANGLE; }
                    default {};
                };
                pv_push(this.tinst_f, (void*)concrete);
                ->;
            };

            // Type implied by one call argument: identifier (symbol table), literal or string
            infer_arg_type(Node* arg) -> TypeSpec*
            {
                TypeSpec* t;
                int dt;
                switch (arg.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    switch (this.st == (FXC_SYMTABLE*)0)
                    {
                        case (true) { -> (TypeSpec*)0; }
                        default {};
                    };
                    -> st_get_type_spec(this.st, arg.text);
                }
                    default {};
                };
                switch (arg.kind == NodeKind.LITERAL)
                {
                    case (true) {
                    dt = arg.op;
                    switch (dt == DataType.SINT | dt == DataType.UINT | dt == DataType.SLONG | dt == DataType.ULONG |
                        dt == DataType.FLOAT | dt == DataType.DOUBLE | dt == DataType.CHAR | dt == DataType.BOOL |
                        dt == DataType.BYTE)
                    {
                        case (true) {
                        t = this.tmp_type();
                        t.base_type = dt;
                        switch (dt == DataType.SINT | dt == DataType.SLONG | dt == DataType.CHAR)
                        {
                            case (true) { t.flags = TS_SIGNED; }
                            default {};
                        };
                        -> t;
                    }
                        default {};
                    };
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                switch (arg.kind == NodeKind.STRING_LITERAL)
                {
                    case (true) {
                    t = this.tmp_type();
                    t.base_type = DataType.BYTE;
                    t.flags = TS_SIGNED `| TS_POINTER;
                    t.bit_width = 8;
                    t.pointer_depth = 1;
                    -> t;
                }
                    default {};
                };
                -> (TypeSpec*)0;
            };

            // Parameter name to type from the call arguments (fparser._infer_template_params).
            // Dict parameters and template struct parameters are not inferred here yet.
            // Concrete type named carg (symbol table alias, builtin name, or a named type)
            tp_type_by_name(byte* carg) -> TypeSpec*
            {
                TypeSpec* r = (TypeSpec*)0;
                int k;
                switch (this.st != (FXC_SYMTABLE*)0)
                {
                    case (true) { r = st_get_type_spec(this.st, carg); }
                    default {};
                };
                while (r == (TypeSpec*)0 & k < 18)
                {
                    switch (cstr_eq(datatype_text(k), carg))
                    {
                        case (true) {
                        r = this.tmp_type();
                        r.base_type = k;
                        switch (k == DataType.SINT | k == DataType.CHAR)
                        {
                            case (true) { r.flags = TS_SIGNED; }
                            default {};
                        };
                    }
                        default {};
                    };
                    k++;
                };
                switch (r == (TypeSpec*)0)
                {
                    case (true) {
                    r = this.tmp_type();
                    r.base_type = DataType.DATA;
                    r.custom_typename = carg;
                }
                    default {};
                };
                -> r;
            };

            // Binds the parameters of a declared Name<T,U> parameter from the mangled type of arg
            infer_struct_param(TemplateEntry* te, PtrVec* raw, Node* arg, NameMap* out) -> void
            {
                TypeSpec* at;
                byte* ctn;
                byte* key;
                byte* sep;
                TemplateEntry* ce;
                PtrVec* cargs;
                int i, j, kl, cl, st0, pos;
                bool match;
                switch (arg.kind != NodeKind.IDENTIFIER)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (this.st == (FXC_SYMTABLE*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                at = st_get_type_spec(this.st, arg.text);
                switch (at == (TypeSpec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                ctn = at.custom_typename;
                switch (ctn == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                cl = pp_cstrlen(ctn);
                while (i < this.templates.count)
                {
                    key = this.templates.keys[i];
                    ce = (TemplateEntry*)this.templates.vals[i];
                    i++;
                    switch (key == (byte*)0 | ce == (TemplateEntry*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (ce.kind != 1 & ce.kind != 2)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    kl = pp_cstrlen(key);
                    match = cstr_eq(ctn, key);
                    switch (!match & cl > kl + 2)
                    {
                        case (true) {
                        match = true;
                        j = 0;
                        while (j < kl)
                        {
                            switch (ctn[j] != key[j])
                            {
                                case (true) { match = false; }
                                default {};
                            };
                            j++;
                        };
                        switch (ctn[kl] != '_' | ctn[kl + 1] != '_')
                        {
                            case (true) { match = false; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (!match)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    // concrete arguments: the text after "key__" split on "__"
                    cargs = pv_new();
                    switch (cl > kl + 2)
                    {
                        case (true) {
                        st0 = kl + 2;
                        j = st0;
                        while (j <= cl)
                        {
                            switch (j == cl)
                            {
                                case (true) {
                                pv_push(cargs, (void*)this.own_n(ctn + st0, j - st0));
                            }
                                default {
                                    switch (ctn[j] == '_' & j + 1 < cl)
                                    {
                                        case (true) {
                                switch (ctn[j + 1] == '_')
                                {
                                    case (true) {
                                    pv_push(cargs, (void*)this.own_n(ctn + st0, j - st0));
                                    st0 = j + 2;
                                    j++;
                                }
                                    default {};
                                };
                            }
                                        default {};
                                    };
                                };
                            };
                            j++;
                        };
                    }
                        default {};
                    };
                    pos = 0;
                    while (pos < raw.len)
                    {
                        switch (this.tp_has_param(te, (byte*)raw.items[pos]) & pos < cargs.len)
                        {
                            case (true) {
                            switch (!nm_has(out, (byte*)raw.items[pos]))
                            {
                                case (true) {
                                nm_put(out, (byte*)raw.items[pos], (void*)this.tp_type_by_name((byte*)cargs.items[pos]));
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                        pos++;
                    };
                    pv_free(cargs);
                    ->;
                };
                ->;
            };

            infer_template_params(TemplateEntry* te, Node* holder, bool skip_first, NameMap* out) -> void
            {
                int i, first, nargs;
                Node* dp;
                Node* arg;
                byte* pt;
                byte* kp;
                byte* vp;
                TypeSpec* t;
                TypeSpec* at;
                PtrVec* raw;
                Node* decl = te.node;
                nargs = node_count(holder, 0);
                first = 0;
                switch (skip_first)
                {
                    case (true) { first = 1; }
                    default {};
                };
                i = first;
                while (i < node_count(decl, 0))
                {
                    switch (i - first >= nargs)
                    {
                        case (true) { break; }
                        default {};
                    };
                    dp = node_child(decl, 0, i);
                    i++;
                    switch (dp.ts == (TypeSpec*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    arg = node_child(holder, 0, i - 1 - first);
                    switch (dp.ts.base_type == DataType.DICT)
                    {
                        case (true) {
                        at = (TypeSpec*)0;
                        switch (arg.kind == NodeKind.IDENTIFIER & this.st != (FXC_SYMTABLE*)0)
                        {
                            case (true) { at = st_get_type_spec(this.st, arg.text); }
                            default {};
                        };
                        switch (at != (TypeSpec*)0)
                        {
                            case (true) {
                            switch (at.base_type == DataType.DICT)
                            {
                                case (true) {
                                kp = (byte*)0;
                                vp = (byte*)0;
                                switch (dp.ts.dict_key != (TypeSpec*)0)
                                {
                                    case (true) { kp = dp.ts.dict_key.custom_typename; }
                                    default {};
                                };
                                switch (dp.ts.dict_value != (TypeSpec*)0)
                                {
                                    case (true) { vp = dp.ts.dict_value.custom_typename; }
                                    default {};
                                };
                                switch (kp != (byte*)0)
                                {
                                    case (true) {
                                    switch (this.tp_has_param(te, kp) & !nm_has(out, kp))
                                    {
                                        case (true) { nm_put(out, kp, (void*)at.dict_key); }
                                        default {};
                                    };
                                }
                                    default {};
                                };
                                switch (vp != (byte*)0)
                                {
                                    case (true) {
                                    switch (this.tp_has_param(te, vp) & !nm_has(out, vp))
                                    {
                                        case (true) { nm_put(out, vp, (void*)at.dict_value); }
                                        default {};
                                    };
                                }
                                    default {};
                                };
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                        continue;
                    }
                        default {};
                    };
                    pt = dp.ts.custom_typename;
                    switch (pt == (byte*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (arg.kind == NodeKind.ADDRESS_OF)
                    {
                        case (true) {
                        switch (arg.a != (Node*)0)
                        {
                            case (true) {
                            switch (arg.a.kind == NodeKind.IDENTIFIER)
                            {
                                case (true) { arg = arg.a; }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    raw = pv_new();
                    switch (this.tp_split_deferred(pt, raw) > 0)
                    {
                        case (true) {
                        this.infer_struct_param(te, raw, arg, out);
                        pv_free(raw);
                        continue;
                    }
                        default {};
                    };
                    pv_free(raw);
                    switch (!this.tp_has_param(te, pt))
                    {
                        case (true) { continue; }
                        default {};
                    };
                    t = this.infer_arg_type(arg);
                    switch (t != (TypeSpec*)0)
                    {
                        case (true) { nm_put(out, pt, (void*)t); }
                        default {};
                    };
                };
                ->;
            };

            // "name<a,b>" for a call whose type arguments are still template parameters
            deferred_name(byte* fname, PtrVec* names) -> byte*
            {
                int i;
                this.sb.len = 0;
                this.sb.put_str(fname);
                this.sb.put('<');
                while (i < names.len)
                {
                    switch (i > 0)
                    {
                        case (true) { this.sb.put(','); }
                        default {};
                    };
                    this.sb.put_str((byte*)names.items[i]);
                    i++;
                };
                this.sb.put('>');
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            tp_free_specs(PtrVec* specs) -> void
            {
                int i;
                while (i < specs.len)
                {
                    typespec_free((TypeSpec*)specs.items[i]);
                    i++;
                };
                pv_free(specs);
                ->;
            };

            // foo<int, T>(args)
            template_call_explicit(Node* expr, TemplateEntry* te) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                PtrVec* names = pv_new();
                PtrVec* specs = pv_new();
                Node* holder = this.mk(NodeKind.NODE_LIST, line, col);
                Node* n;
                TypeSpec* ts;
                bool more = true;
                bool deferred = false;
                int i;
                this.advance();
                while (more & !this.failed)
                {
                    ts = this.type_spec();
                    switch (this.failed)
                    {
                        case (true) {
                        typespec_free(ts);
                        break;
                    }
                        default {};
                    };
                    pv_push(names, (void*)this.ts_mangle(ts));
                    pv_push(specs, (void*)ts);
                    more = this.expect(TokenType.COMMA);
                    switch (more)
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.GREATER_THAN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_PAREN); }
                    default {};
                };
                switch (!this.failed & !this.expect(TokenType.RIGHT_PAREN))
                {
                    case (true) { this.argument_list(holder, expr.text); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) {
                    this.tp_free_specs(specs);
                    pv_free(names);
                    node_free(holder);
                    -> expr;
                }
                    default {};
                };
                while (i < names.len)
                {
                    switch (this.tp_active((byte*)names.items[i]))
                    {
                        case (true) { deferred = true; }
                        default {};
                    };
                    i++;
                };
                n = this.mk(NodeKind.FUNCTION_CALL, line, col);
                switch (this.failed)
                {
                    case (true) {
                    this.tp_free_specs(specs);
                    pv_free(names);
                    node_free(holder);
                    -> expr;
                }
                    default {};
                };
                this.take_args(n, holder);
                switch (deferred)
                {
                    case (true) { n.text = this.deferred_name(expr.text, names); }
                    default { n.text = this.resolve_template_call(expr.text, names, specs, (PtrVec*)0); };
                };
                this.tp_free_specs(specs);
                pv_free(names);
                node_free(expr);
                -> n;
            };

            // foo(args): the type arguments are inferred from the argument types
            template_call_implicit(Node* expr, TemplateEntry* te) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col() + 1;
                Node* holder = this.mk(NodeKind.NODE_LIST, line, col);
                Node* n;
                Node* dp;
                NameMap* inferred = nm_new();
                PtrVec* names = pv_new();
                PtrVec* specs = pv_new();
                PtrVec* poss = pv_new();
                PtrVec* unresolved = pv_new();
                int i, j, got;
                bool all_active, abstract;
                byte* p;
                TypeSpec* t;
                this.advance();
                switch (!this.failed & !this.expect(TokenType.RIGHT_PAREN))
                {
                    case (true) { this.argument_list(holder, expr.text); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) {
                    nm_free(inferred);
                    pv_free(names);
                    pv_free(specs);
                    pv_free(poss);
                    pv_free(unresolved);
                    node_free(holder);
                    -> expr;
                }
                    default {};
                };
                this.infer_template_params(te, holder, false, inferred);

                // argument each parameter was inferred from (for error positions)
                i = 0;
                while (i < te.params.len)
                {
                    pv_push(poss, (void*)0);
                    i++;
                };
                i = 0;
                while (i < node_count(te.node, 0) & i < node_count(holder, 0))
                {
                    dp = node_child(te.node, 0, i);
                    switch (dp.ts != (TypeSpec*)0)
                    {
                        case (true) {
                        switch (dp.ts.custom_typename != (byte*)0)
                        {
                            case (true) {
                            j = 0;
                            while (j < te.params.len)
                            {
                                switch (cstr_eq((byte*)te.params.items[j], dp.ts.custom_typename) & poss.items[j] == (void*)0)
                                {
                                    case (true) {
                                    poss.items[j] = (void*)node_child(holder, 0, i);
                                }
                                    default {};
                                };
                                j++;
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };

                // defaults for what was not inferred
                i = 0;
                while (i < te.dparam.len)
                {
                    p = (byte*)te.dparam.items[i];
                    switch (!nm_has(inferred, p))
                    {
                        case (true) { nm_put(inferred, p, te.dts.items[i]); }
                        default {};
                    };
                    i++;
                };
                i = 0;
                while (i < te.no_default.count)
                {
                    p = te.no_default.keys[i];
                    i++;
                    switch (p == (byte*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (!nm_has(inferred, p))
                    {
                        case (true) {
                        this.sb.len = 0;
                        this.sb.put_str(g"Template parameter '\0");
                        this.sb.put_str(p);
                        this.sb.put_str(g"' of '\0");
                        this.sb.put_str(expr.text);
                        this.sb.put_str(g"' has no default and could not be inferred - it must be supplied explicitly\0");
                        this.error_at(this.own_n(this.sb.mem, this.sb.len), line, col);
                        break;
                    }
                        default {};
                    };
                };

                n = (Node*)0;
                switch (!this.failed)
                {
                    case (true) {
                    got = 0;
                    i = 0;
                    while (i < te.params.len)
                    {
                        switch (nm_has(inferred, (byte*)te.params.items[i]))
                        {
                            case (true) { got++; }
                            default { pv_push(unresolved, te.params.items[i]); };
                        };
                        i++;
                    };
                    n = this.mk(NodeKind.FUNCTION_CALL, line, col);
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) {
                    this.take_args(n, holder);
                    holder = (Node*)0;
                    n.text = expr.text;
                    switch (got == te.params.len)
                    {
                        case (true) {
                        abstract = false;
                        i = 0;
                        while (i < te.params.len)
                        {
                            t = (TypeSpec*)nm_get(inferred, (byte*)te.params.items[i]);
                            pv_push(specs, (void*)t);
                            p = this.ts_mangle(t);
                            pv_push(names, (void*)p);
                            switch (this.tp_has_param(te, p))
                            {
                                case (true) { abstract = true; }
                                default {};
                            };
                            i++;
                        };
                        switch (!abstract)
                        {
                            case (true) { n.text = this.resolve_template_call(expr.text, names, specs, poss); }
                            default {};
                        };
                    }
                        default {
                        all_active = unresolved.len > 0;
                        i = 0;
                        while (i < unresolved.len)
                        {
                            switch (!this.tp_active((byte*)unresolved.items[i]))
                            {
                                case (true) { all_active = false; }
                                default {};
                            };
                            i++;
                        };
                        switch (all_active)
                        {
                            case (true) {
                            i = 0;
                            while (i < te.params.len)
                            {
                                p = (byte*)te.params.items[i];
                                switch (nm_has(inferred, p))
                                {
                                    case (true) { pv_push(names, (void*)this.ts_mangle((TypeSpec*)nm_get(inferred, p))); }
                                    default { pv_push(names, (void*)p); };
                                };
                                i++;
                            };
                            n.text = this.deferred_name(expr.text, names);
                        }
                            default {};
                        };
                    };
                    };
                }
                    default {};
                };
                nm_free(inferred);
                pv_free(names);
                pv_free(specs);
                pv_free(poss);
                pv_free(unresolved);
                switch (holder != (Node*)0)
                {
                    case (true) { node_free(holder); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) {
                    node_free(n);
                    -> expr;
                }
                    default {};
                };
                node_free(expr);
                -> n;
            };

            // Explicit or inferred call of a template function name
            // Registry key of the type function template implied by receiver expr and member, or null
            typefunc_key(Node* expr, byte* member) -> byte*
            {
                Node* id = (Node*)0;
                bool tied = false;
                TypeSpec* rt;
                byte* rn;
                byte* cand;
                byte* un;
                int pd, i;
                switch (this.st == (FXC_SYMTABLE*)0)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                switch (expr.kind == NodeKind.IDENTIFIER)
                {
                    case (true) { id = expr; }
                    default {
                        switch (expr.kind == NodeKind.TIE_EXPRESSION)
                        {
                            case (true) {
                    switch (expr.a != (Node*)0)
                    {
                        case (true) {
                        switch (expr.a.kind == NodeKind.IDENTIFIER)
                        {
                            case (true) {
                            id = expr.a;
                            tied = true;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                            default {
                                switch (expr.kind == NodeKind.STRING_LITERAL | expr.kind == NodeKind.F_STRING_LITERAL)
                                {
                                    case (true) {
                    cand = this.cat2(g"__typefunc__string__\0", member);
                    switch (this.template_lookup(cand) != (TemplateEntry*)0)
                    {
                        case (true) { -> cand; }
                        default {};
                    };
                    -> (byte*)0;
                }
                                    default {};
                                };
                            };
                        };
                    };
                };
                switch (id == (Node*)0)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                rt = st_get_type_spec(this.st, id.text);
                switch (rt == (TypeSpec*)0)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                pd = rt.pointer_depth;
                switch (rt.custom_typename != (byte*)0)
                {
                    case (true) { rn = rt.custom_typename; }
                    default {
                        switch (pd > 0 & rt.base_type == DataType.BYTE)
                        {
                            case (true) { rn = g"string\0"; }
                            default {
                                switch (pd > 0)
                                {
                                    case (true) {
                    rn = datatype_text(rt.base_type);
                    while (i < pd)
                    {
                        rn = this.cat2(rn, g"_ptr\0");
                        i++;
                    };
                }
                                    default { rn = datatype_text(rt.base_type); };
                                };
                            };
                        };
                    };
                };
                switch ((rt.flags `& TS_TIED) != 0)
                {
                    case (true) { tied = true; }
                    default {};
                };
                switch (tied)
                {
                    case (true) { cand = this.cat2(this.cat2(this.cat2(g"__typefunc__tied_\0", rn), g"__\0"), member); }
                    default { cand = this.cat2(this.cat2(this.cat2(g"__typefunc__\0", rn), g"__\0"), member); };
                };
                switch (this.template_lookup(cand) != (TemplateEntry*)0)
                {
                    case (true) { -> cand; }
                    default {};
                };
                switch (tied)
                {
                    case (true) {
                    un = this.cat2(this.cat2(this.cat2(g"__typefunc__\0", rn), g"__\0"), member);
                    switch (this.template_lookup(un) != (TemplateEntry*)0)
                    {
                        case (true) { -> un; }
                        default {};
                    };
                }
                    default {};
                };
                -> (byte*)0;
            };

            // recv.member<types>(args) for a method or type function template registered under key
            template_method_explicit(Node* recv, byte* key, bool as_typefunc) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                PtrVec* names = pv_new();
                PtrVec* specs = pv_new();
                Node* holder = this.mk(NodeKind.NODE_LIST, line, col);
                Node* n;
                TypeSpec* ts;
                bool more = true;
                this.advance();
                while (more & !this.failed)
                {
                    ts = this.type_spec();
                    switch (this.failed)
                    {
                        case (true) {
                        typespec_free(ts);
                        break;
                    }
                        default {};
                    };
                    pv_push(names, (void*)this.ts_mangle(ts));
                    pv_push(specs, (void*)ts);
                    more = this.expect(TokenType.COMMA);
                    switch (more)
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.GREATER_THAN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_PAREN); }
                    default {};
                };
                switch (!this.failed & !this.expect(TokenType.RIGHT_PAREN))
                {
                    case (true) { this.argument_list(holder, (byte*)0); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                n = (Node*)0;
                switch (!this.failed)
                {
                    case (true) { n = this.mk(NodeKind.FUNCTION_CALL, line, col); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) {
                    this.tp_free_specs(specs);
                    pv_free(names);
                    node_free(holder);
                    -> recv;
                }
                    default {};
                };
                this.take_args(n, holder);
                n.text = this.resolve_template_call(key, names, specs, (PtrVec*)0);
                this.tp_free_specs(specs);
                pv_free(names);
                switch (as_typefunc)
                {
                    case (true) { this.push_front(n, recv); }
                    default { node_free(recv); };
                };
                -> n;
            };

            // obj.member(args) tagged as a type function template: infers the parameters from the
            // arguments. Returns the FUNCTION_CALL, or null when not every parameter was inferred.
            typefunc_call_implicit(Node* ma, Node* holder, int line, int col) -> Node*
            {
                TemplateEntry* te = this.template_lookup(ma.text2);
                NameMap* inferred;
                PtrVec* names;
                PtrVec* specs;
                Node* n = (Node*)0;
                TypeSpec* t;
                int i;
                bool all = true;
                switch (te == (TemplateEntry*)0)
                {
                    case (true) { -> n; }
                    default {};
                };
                inferred = nm_new();
                this.infer_template_params(te, holder, true, inferred);
                i = 0;
                while (i < te.params.len)
                {
                    switch (!nm_has(inferred, (byte*)te.params.items[i]))
                    {
                        case (true) { all = false; }
                        default {};
                    };
                    i++;
                };
                switch (all)
                {
                    case (true) {
                    names = pv_new();
                    specs = pv_new();
                    i = 0;
                    while (i < te.params.len)
                    {
                        t = (TypeSpec*)nm_get(inferred, (byte*)te.params.items[i]);
                        pv_push(specs, (void*)t);
                        pv_push(names, (void*)this.ts_mangle(t));
                        i++;
                    };
                    n = this.mk(NodeKind.FUNCTION_CALL, line, col);
                    switch (!this.failed)
                    {
                        case (true) {
                        n.text = this.resolve_template_call(ma.text2, names, specs, (PtrVec*)0);
                    }
                        default {};
                    };
                    pv_free(names);
                    pv_free(specs);
                }
                    default {};
                };
                nm_free(inferred);
                -> n;
            };

            template_call(Node* expr) -> Node*
            {
                TemplateEntry* te;
                switch (expr.kind != NodeKind.IDENTIFIER)
                {
                    case (true) { -> expr; }
                    default {};
                };
                te = this.template_lookup(expr.text);
                switch (te == (TemplateEntry*)0)
                {
                    case (true) { -> expr; }
                    default {};
                };
                switch (te.kind != 0)
                {
                    case (true) { -> expr; }
                    default {};
                };
                switch (this.expect(TokenType.LESS_THAN))
                {
                    case (true) { -> this.template_call_explicit(expr, te); }
                    default {};
                };
                switch (this.expect(TokenType.LEFT_PAREN))
                {
                    case (true) { -> this.template_call_implicit(expr, te); }
                    default {};
                };
                -> expr;
            };

            // ----- constra -----

            // True when the cursor starts a relational constraint operator
            is_relop() -> bool
            {
                int t0 = this.cur();
                int t1 = this.type_at(1);
                int t2 = this.type_at(2);
                switch (t0 == TokenType.TIE)
                {
                    case (true) { -> t1 == TokenType.ASSIGN; }
                    default {};
                };
                switch (t0 != TokenType.NOT)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (t1 == TokenType.TIE)
                {
                    case (true) { -> t2 == TokenType.ASSIGN; }
                    default {};
                };
                switch (t1 == TokenType.ADDRESS_OF)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (t1 == TokenType.MINUS_ASSIGN)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (t1 == TokenType.BACKTICK)
                {
                    case (true) {
                    -> t2 == TokenType.LESS_THAN | t2 == TokenType.LESS_EQUAL |
                           t2 == TokenType.GREATER_THAN | t2 == TokenType.GREATER_EQUAL;
                }
                    default {};
                };
                -> false;
            };

            // Consumes the operator tokens and returns the operator text
            consume_relop() -> byte*
            {
                switch (this.expect(TokenType.TIE))
                {
                    case (true) {
                    this.advance();
                    this.consume(TokenType.ASSIGN);
                    -> g"~=\0";
                }
                    default {};
                };
                this.consume(TokenType.NOT);
                switch (this.expect(TokenType.TIE))
                {
                    case (true) {
                    this.advance();
                    this.consume(TokenType.ASSIGN);
                    -> g"!~=\0";
                }
                    default {};
                };
                switch (this.expect(TokenType.ADDRESS_OF))
                {
                    case (true) { this.advance(); -> g"!@\0"; }
                    default {};
                };
                switch (this.expect(TokenType.MINUS_ASSIGN))
                {
                    case (true) { this.advance(); -> g"!-=\0"; }
                    default {};
                };
                this.consume(TokenType.BACKTICK);
                switch (this.expect(TokenType.LESS_EQUAL))
                {
                    case (true) { this.advance(); -> g"!`<=\0"; }
                    default {};
                };
                switch (this.expect(TokenType.LESS_THAN))
                {
                    case (true) { this.advance(); -> g"!`<\0"; }
                    default {};
                };
                switch (this.expect(TokenType.GREATER_EQUAL))
                {
                    case (true) { this.advance(); -> g"!`>=\0"; }
                    default {};
                };
                switch (this.expect(TokenType.GREATER_THAN))
                {
                    case (true) { this.advance(); -> g"!`>\0"; }
                    default {};
                };
                this.error(g"Unknown constraint operator after '!`'\0");
                -> (byte*)0;
            };

            // Appends a CONSTRA_RELATION (l0 = lhs names, text = op, l1 = rhs names) to d.l1
            cs_emit(Node* d, PtrVec* lhs, byte* op, PtrVec* rhs, int line, int col) -> void
            {
                Node* rel = this.mk(NodeKind.CONSTRA_RELATION, line, col);
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                node_push(d, 1, rel);
                rel.text = op;
                Node* id;
                int i;
                while (i < lhs.len)
                {
                    id = this.mk(NodeKind.IDENTIFIER, line, col);
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    id.text = (byte*)lhs.items[i];
                    node_push(rel, 0, id);
                    i++;
                };
                i = 0;
                while (i < rhs.len)
                {
                    id = this.mk(NodeKind.IDENTIFIER, line, col);
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    id.text = (byte*)rhs.items[i];
                    node_push(rel, 1, id);
                    i++;
                };
                ->;
            };

            // One element of a name list: IDENTIFIER, or '[' names (op names)? ']'
            // A bracket group emits its own relation into d and yields the names of its last side.
            cs_element(Node* d, PtrVec* out) -> void
            {
                PtrVec* ns;
                PtrVec* rhs;
                byte* op;
                int line, col, i;
                PtrVec* res;
                switch (!this.expect(TokenType.LEFT_BRACKET))
                {
                    case (true) {
                    pv_push(out, (void*)this.ident());
                    ->;
                }
                    default {};
                };
                line = this.cur_line();
                col = this.cur_col();
                this.advance();
                ns = pv_new();
                pv_push(ns, (void*)this.ident());
                while (!this.failed & this.expect(TokenType.LOGICAL_AND) & this.type_at(1) == TokenType.IDENTIFIER)
                {
                    this.advance();
                    pv_push(ns, (void*)this.ident());
                };
                res = ns;
                switch (!this.failed & this.is_relop())
                {
                    case (true) {
                    op = this.consume_relop();
                    rhs = pv_new();
                    pv_push(rhs, (void*)this.ident());
                    while (!this.failed & this.expect(TokenType.LOGICAL_AND) & this.type_at(1) == TokenType.IDENTIFIER)
                    {
                        this.advance();
                        pv_push(rhs, (void*)this.ident());
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.cs_emit(d, ns, op, rhs, line, col); }
                        default {};
                    };
                    res = rhs;
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACKET); }
                    default {};
                };
                while (i < res.len)
                {
                    pv_push(out, res.items[i]);
                    i++;
                };
                switch (res != ns)
                {
                    case (true) { pv_free(res); }
                    default {};
                };
                pv_free(ns);
                ->;
            };

            // names joined by '&'
            cs_idlist(Node* d, PtrVec* out) -> void
            {
                int t1;
                this.cs_element(d, out);
                while (!this.failed & this.expect(TokenType.LOGICAL_AND))
                {
                    t1 = this.type_at(1);
                    switch (t1 != TokenType.IDENTIFIER & t1 != TokenType.LEFT_BRACKET)
                    {
                        case (true) { break; }
                        default {};
                    };
                    this.advance();
                    this.cs_element(d, out);
                };
                ->;
            };

            // Chained relation: names op names op names ...
            cs_rel_expr(Node* d) -> void
            {
                PtrVec* lhs = pv_new();
                PtrVec* rhs;
                byte* op;
                int line = this.cur_line();
                int col = this.cur_col();
                this.cs_idlist(d, lhs);
                while (!this.failed & this.is_relop())
                {
                    op = this.consume_relop();
                    rhs = pv_new();
                    this.cs_idlist(d, rhs);
                    switch (!this.failed)
                    {
                        case (true) { this.cs_emit(d, lhs, op, rhs, line, col); }
                        default {};
                    };
                    pv_free(lhs);
                    lhs = rhs;
                };
                pv_free(lhs);
                ->;
            };

            cs_less(byte* a, byte* b) -> bool
            {
                int i;
                while (a[i] != (byte)0 & a[i] == b[i]) { i++; };
                -> a[i] < b[i];
            };

            // Same set of names (duplicates ignored)
            cs_same_set(Node* x, int lx, Node* y, int ly) -> bool
            {
                int i, j;
                bool hit;
                int nx = node_count(x, lx);
                int ny = node_count(y, ly);
                while (i < nx)
                {
                    hit = false;
                    j = 0;
                    while (j < ny & !hit)
                    {
                        switch (cstr_eq(node_child(x, lx, i).text, node_child(y, ly, j).text))
                        {
                            case (true) { hit = true; }
                            default {};
                        };
                        j++;
                    };
                    switch (!hit)
                    {
                        case (true) { -> false; }
                        default {};
                    };
                    i++;
                };
                i = 0;
                while (i < ny)
                {
                    hit = false;
                    j = 0;
                    while (j < nx & !hit)
                    {
                        switch (cstr_eq(node_child(y, ly, i).text, node_child(x, lx, j).text))
                        {
                            case (true) { hit = true; }
                            default {};
                        };
                        j++;
                    };
                    switch (!hit)
                    {
                        case (true) { -> false; }
                        default {};
                    };
                    i++;
                };
                -> true;
            };

            // Writes the names of side l of rel to sb sorted and joined by " & "
            cs_put_sorted(Node* rel, int l) -> void
            {
                int n = node_count(rel, l);
                PtrVec* v = pv_new();
                int i, j;
                byte* t;
                while (i < n)
                {
                    pv_push(v, (void*)node_child(rel, l, i).text);
                    i++;
                };
                i = 1;
                while (i < v.len)
                {
                    j = i;
                    while (j > 0 & this.cs_less((byte*)v.items[j], (byte*)v.items[j - 1]))
                    {
                        t = (byte*)v.items[j];
                        v.items[j] = v.items[j - 1];
                        v.items[j - 1] = (void*)t;
                        j--;
                    };
                    i++;
                };
                i = 0;
                while (i < v.len)
                {
                    switch (i > 0)
                    {
                        case (true) { this.sb.put_str(g" & \0"); }
                        default {};
                    };
                    this.sb.put_str((byte*)v.items[i]);
                    i++;
                };
                pv_free(v);
                ->;
            };

            // Mutex partner of op, or null
            cs_mutex(byte* op) -> byte*
            {
                switch (cstr_eq(op, g"~=\0"))
                {
                    case (true) { -> g"!~=\0"; }
                    default {};
                };
                switch (cstr_eq(op, g"!~=\0"))
                {
                    case (true) { -> g"~=\0"; }
                    default {};
                };
                switch (cstr_eq(op, g"!`<=\0"))
                {
                    case (true) { -> g"!`>=\0"; }
                    default {};
                };
                switch (cstr_eq(op, g"!`>=\0"))
                {
                    case (true) { -> g"!`<=\0"; }
                    default {};
                };
                -> (byte*)0;
            };

            // Error at the position m (the 'constra' token) with the text in sb
            cs_error_at(int m) -> void
            {
                this.reset(m);
                this.error(this.own_n(this.sb.mem, this.sb.len));
                ->;
            };

            // Merge form after '=': constra A = B + C;  (rename = optional param list, else null)
            constra_merge(Node* d, int m0, PtrVec* rename) -> void
            {
                PtrVec* srcs = pv_new();
                int m, i, j, k, base, nsrc, nrel, rn;
                byte* sname;
                byte* mapped;
                byte* mx;
                Node* src;
                Node* rel;
                Node* nrelnode;
                Node* id;
                Node* prev;
                PtrVec* finals = pv_new();
                bool more = true;
                while (more & !this.failed)
                {
                    m = this.mark();
                    sname = this.ident();
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    switch (!nm_has(this.constras, sname))
                    {
                        case (true) {
                        this.reset(m);
                        this.sb.len = 0;
                        this.sb.put_str(g"Unknown constraint set '\0");
                        this.sb.put_str(sname);
                        this.sb.put_str(g"' in constra merge\0");
                        this.cs_error_at(m);
                        break;
                    }
                        default {};
                    };
                    pv_push(srcs, nm_get(this.constras, sname));
                    more = this.expect(TokenType.PLUS);
                    switch (more)
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) {
                    pv_free(srcs);
                    pv_free(finals);
                    ->;
                }
                    default {};
                };
                src = (Node*)srcs.items[0];
                base = node_count(src, 0);
                i = 1;
                while (i < srcs.len & !this.failed)
                {
                    prev = (Node*)srcs.items[i];
                    switch (node_count(prev, 0) != base)
                    {
                        case (true) {
                        this.sb.len = 0;
                        this.sb.put_str(g"Cannot merge constraint sets of different arity: '\0");
                        this.sb.put_str(src.text);
                        this.sb.put_str(g"' has \0");
                        this.sb.put_int(base);
                        this.sb.put_str(g" parameter(s) but '\0");
                        this.sb.put_str(prev.text);
                        this.sb.put_str(g"' has \0");
                        this.sb.put_int(node_count(prev, 0));
                        this.cs_error_at(m0);
                    }
                        default {};
                    };
                    i++;
                };
                switch (!this.failed & rename != (PtrVec*)0)
                {
                    case (true) {
                    switch (rename.len != base)
                    {
                        case (true) {
                        this.sb.len = 0;
                        this.sb.put_str(g"Rename parameter list has \0");
                        this.sb.put_int(rename.len);
                        this.sb.put_str(g" name(s) but merged constraint sets have arity \0");
                        this.sb.put_int(base);
                        this.cs_error_at(m0);
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) {
                    pv_free(srcs);
                    pv_free(finals);
                    ->;
                }
                    default {};
                };
                i = 0;
                while (i < base)
                {
                    switch (rename != (PtrVec*)0)
                    {
                        case (true) { pv_push(finals, rename.items[i]); }
                        default { pv_push(finals, (void*)node_child(src, 0, i).text); };
                    };
                    id = this.mk(NodeKind.IDENTIFIER, d.line, d.col);
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    id.text = (byte*)finals.items[i];
                    node_push(d, 0, id);
                    i++;
                };
                // remap each source's formals onto the final names
                i = 0;
                while (i < srcs.len & !this.failed)
                {
                    src = (Node*)srcs.items[i];
                    nrel = node_count(src, 1);
                    j = 0;
                    while (j < nrel & !this.failed)
                    {
                        rel = node_child(src, 1, j);
                        nrelnode = this.mk(NodeKind.CONSTRA_RELATION, rel.line, rel.col);
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        node_push(d, 1, nrelnode);
                        nrelnode.text = rel.text;
                        rn = 0;
                        while (rn < 2)
                        {
                            k = 0;
                            while (k < node_count(rel, rn) & !this.failed)
                            {
                                mapped = node_child(rel, rn, k).text;
                                base = node_count(src, 0) - 1;
                                while (base >= 0)
                                {
                                    switch (cstr_eq(node_child(src, 0, base).text, mapped))
                                    {
                                        case (true) {
                                        mapped = (byte*)finals.items[base];
                                        break;
                                    }
                                        default {};
                                    };
                                    base--;
                                };
                                id = this.mk(NodeKind.IDENTIFIER, rel.line, rel.col);
                                switch (this.failed)
                                {
                                    case (true) { break; }
                                    default {};
                                };
                                id.text = mapped;
                                node_push(nrelnode, rn, id);
                                k++;
                            };
                            rn++;
                        };
                        j++;
                    };
                    i++;
                };
                // mutex check: a relation conflicts with an earlier one on the same sides with the partner op
                nrel = node_count(d, 1);
                i = 0;
                while (i < nrel & !this.failed)
                {
                    rel = node_child(d, 1, i);
                    mx = this.cs_mutex(rel.text);
                    j = 0;
                    while (mx != (byte*)0 & j < i & !this.failed)
                    {
                        prev = node_child(d, 1, j);
                        switch (cstr_eq(prev.text, mx) &
                            this.cs_same_set(prev, 0, rel, 0) & this.cs_same_set(prev, 1, rel, 1))
                        {
                            case (true) {
                            this.sb.len = 0;
                            this.sb.put_str(g"Conflicting constraints in merge '\0");
                            this.sb.put_str(d.text);
                            this.sb.put_str(g"': '\0");
                            this.cs_put_sorted(rel, 0);
                            this.sb.put(' ');
                            this.sb.put_str(mx);
                            this.sb.put(' ');
                            this.cs_put_sorted(rel, 1);
                            this.sb.put_str(g"' and '\0");
                            this.cs_put_sorted(rel, 0);
                            this.sb.put(' ');
                            this.sb.put_str(rel.text);
                            this.sb.put(' ');
                            this.cs_put_sorted(rel, 1);
                            this.sb.put_str(g"' cannot be true simultaneously\0");
                            this.cs_error_at(m0);
                        }
                            default {};
                        };
                        j++;
                    };
                    i++;
                };
                pv_free(srcs);
                pv_free(finals);
                ->;
            };

            // constra_def -> 'constra' IDENTIFIER ('(' names ')')? ( '=' names_merge | '{' relations '}' ) ';'
            constra_def() -> Node*
            {
                int m0 = this.mark();
                Node* d = this.mk(NodeKind.CONSTRA_DEF, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> d; }
                    default {};
                };
                Node* id;
                PtrVec* rename;
                int m;
                bool more;
                this.advance();
                d.text = this.ident();
                switch (!this.failed & this.expect(TokenType.LEFT_PAREN))
                {
                    case (true) {
                    m = this.mark();
                    this.advance();
                    rename = pv_new();
                    switch (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        case (true) {
                        more = true;
                        while (more & !this.failed)
                        {
                            pv_push(rename, (void*)this.ident());
                            more = this.expect(TokenType.COMMA);
                            switch (more)
                            {
                                case (true) { this.advance(); }
                                default {};
                            };
                        };
                    }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                    switch (!this.failed & !this.expect(TokenType.ASSIGN))
                    {
                        case (true) {
                        pv_free(rename);
                        rename = (PtrVec*)0;
                        this.reset(m);
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (!this.failed & this.expect(TokenType.ASSIGN))
                {
                    case (true) {
                    this.advance();
                    this.constra_merge(d, m0, rename);
                    switch (rename != (PtrVec*)0)
                    {
                        case (true) { pv_free(rename); }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) { -> this.done(d); }
                        default {};
                    };
                    nm_put(this.constras, d.text, (void*)d);
                    -> d;
                }
                    default {};
                };
                switch (rename != (PtrVec*)0)
                {
                    case (true) { pv_free(rename); }
                    default {};
                };
                switch (!this.failed & this.expect(TokenType.LEFT_PAREN))
                {
                    case (true) {
                    this.advance();
                    switch (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        case (true) {
                        more = true;
                        while (more & !this.failed)
                        {
                            id = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                            switch (this.failed)
                            {
                                case (true) { break; }
                                default {};
                            };
                            node_push(d, 0, id);
                            id.text = this.ident();
                            more = this.expect(TokenType.COMMA);
                            switch (more)
                            {
                                case (true) { this.advance(); }
                                default {};
                            };
                        };
                    }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.cs_rel_expr(d); }
                    default {};
                };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (this.expect(TokenType.COMMA))
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                    this.cs_rel_expr(d);
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(d); }
                    default {};
                };
                nm_put(this.constras, d.text, (void*)d);
                -> d;
            };

            // Canonical receiver type name of the token at the cursor, or null when it is not a receiver
            tf_receiver_name() -> byte*
            {
                int t = this.cur();
                switch (t == TokenType.BYTE)
                {
                    case (true) { -> g"byte\0"; }
                    default {};
                };
                switch (t == TokenType.SINT | t == TokenType.SINT_LITERAL)
                {
                    case (true) { -> g"int\0"; }
                    default {};
                };
                switch (t == TokenType.UINT | t == TokenType.UINT_LITERAL)
                {
                    case (true) { -> g"uint\0"; }
                    default {};
                };
                switch (t == TokenType.SLONG | t == TokenType.SLONG_LITERAL)
                {
                    case (true) { -> g"long\0"; }
                    default {};
                };
                switch (t == TokenType.ULONG | t == TokenType.ULONG_LITERAL)
                {
                    case (true) { -> g"ulong\0"; }
                    default {};
                };
                switch (t == TokenType.FLOAT_KW | t == TokenType.FLOAT)
                {
                    case (true) { -> g"float\0"; }
                    default {};
                };
                switch (t == TokenType.DOUBLE_KW | t == TokenType.DOUBLE)
                {
                    case (true) { -> g"double\0"; }
                    default {};
                };
                switch (t == TokenType.BOOL_KW | t == TokenType.TRUE | t == TokenType.FALSE)
                {
                    case (true) { -> g"bool\0"; }
                    default {};
                };
                switch (t == TokenType.STRING_LITERAL | t == TokenType.F_STRING | t == TokenType.I_STRING)
                {
                    case (true) { -> g"string\0"; }
                    default {};
                };
                switch (t == TokenType.CHAR)
                {
                    case (true) { -> g"char\0"; }
                    default {};
                };
                switch (t == TokenType.IDENTIFIER)
                {
                    case (true) { -> this.cur_value(); }
                    default {};
                };
                -> (byte*)0;
            };

            // Type of the implicit receiver parameter (fparser.py _type_func_receiver_type_spec)
            tf_receiver_ts(byte* tn, int depth, bool is_array) -> TypeSpec*
            {
                TypeSpec* t = typespec_new();
                int base = -1;
                switch (cstr_eq(tn, g"string\0") | (cstr_eq(tn, g"byte\0") & depth >= 1))
                {
                    case (true) {
                    switch (depth < 1)
                    {
                        case (true) { depth = 1; }
                        default {};
                    };
                    t.base_type = DataType.BYTE;
                    t.pointer_depth = depth;
                    t.flags = t.flags `| TS_POINTER;
                    -> t;
                }
                    default {};
                };
                switch (cstr_eq(tn, g"byte\0"))
                {
                    case (true) { base = DataType.BYTE; }
                    default {
                        switch (cstr_eq(tn, g"int\0"))
                        {
                            case (true) { base = DataType.SINT; }
                            default {
                                switch (cstr_eq(tn, g"uint\0"))
                                {
                                    case (true) { base = DataType.UINT; }
                                    default {
                                        switch (cstr_eq(tn, g"long\0"))
                                        {
                                            case (true) { base = DataType.SLONG; }
                                            default {
                                                switch (cstr_eq(tn, g"ulong\0"))
                                                {
                                                    case (true) { base = DataType.ULONG; }
                                                    default {
                                                        switch (cstr_eq(tn, g"float\0"))
                                                        {
                                                            case (true) { base = DataType.FLOAT; }
                                                            default {
                                                                switch (cstr_eq(tn, g"double\0"))
                                                                {
                                                                    case (true) { base = DataType.DOUBLE; }
                                                                    default {
                                                                        switch (cstr_eq(tn, g"bool\0"))
                                                                        {
                                                                            case (true) { base = DataType.BOOL; }
                                                                            default {
                                                                                switch (cstr_eq(tn, g"char\0"))
                                                                                {
                                                                                    case (true) { base = DataType.CHAR; }
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
                switch (base < 0)
                {
                    case (true) {
                    t.base_type = DataType.DATA;
                    t.custom_typename = tn;
                }
                    default {
                    t.base_type = base;
                };
                };
                switch (is_array)
                {
                    case (true) { t.flags = t.flags `| TS_ARRAY; }
                    default {
                        switch (depth > 0)
                        {
                            case (true) {
                    t.pointer_depth = depth;
                    t.flags = t.flags `| TS_POINTER;
                }
                            default {};
                        };
                    };
                };
                -> t;
            };

            // type_func_def -> '~'? receiver '*'* ('[' ']')? '.' name ('<' ... '>')? '(' params ')' '->' type (';' | block ';')
            type_func_def() -> Node*
            {
                NameMap* prev_act = this.active_tp;
                TemplateEntry* prev_cur = this.tmpl_cur;
                this.tmpl_cur = (TemplateEntry*)0;
                Node* d = this.type_func_def_inner();
                TemplateEntry* te = this.tmpl_cur;
                this.tmpl_cur = prev_cur;
                switch (this.active_tp != prev_act)
                {
                    case (true) {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                }
                    default {};
                };
                switch (te == (TemplateEntry*)0)
                {
                    case (true) { -> d; }
                    default {};
                };
                switch (this.failed | d == (Node*)0)
                {
                    case (true) {
                    te_free(te);
                    -> d;
                }
                    default {};
                };
                this.tf_to_function(d);
                this.last_template = d.text;
                this.register_template(d.text, 0, te, d);
                -> (Node*)0;
            };

            // Turns a type function into the synthetic FUNCTION_DEF the Python registers:
            // __typefunc__<type>__<name>(_ receiver, params...)
            tf_to_function(Node* d) -> void
            {
                PtrVec* tmp = pv_new();
                Node* p0 = this.mk(NodeKind.PARAMETER, d.line, d.col);
                int i, n;
                switch (this.failed)
                {
                    case (true) { pv_free(tmp); ->; }
                    default {};
                };
                p0.text = g"_\0";
                p0.ts = d.ts2;
                d.ts2 = (TypeSpec*)0;
                n = node_count(d, 0);
                while (i < n)
                {
                    pv_push(tmp, (void*)node_child(d, 0, i));
                    i++;
                };
                switch (n > 0)
                {
                    case (true) { d.l0.len = 0; }
                    default {};
                };
                node_push(d, 0, p0);
                i = 0;
                while (i < n)
                {
                    node_push(d, 0, (Node*)tmp.items[i]);
                    i++;
                };
                pv_free(tmp);
                d.text = this.cat2(this.cat2(this.cat2(g"__typefunc__\0", d.text), g"__\0"), d.text2);
                d.text2 = (byte*)0;
                d.kind = NodeKind.FUNCTION_DEF;
                ->;
            };

            type_func_def_inner() -> Node*
            {
                int m = this.mark();
                Node* d = this.mk(NodeKind.TYPE_FUNC_DEF, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> d; }
                    default {};
                };
                bool tied = false;
                bool is_array = false;
                int depth = 0;
                byte* tn;
                byte* eff;
                int k;
                TypeSpec* rts;
                Node* fl;
                switch (this.expect(TokenType.TIE))
                {
                    case (true) { tied = true; this.advance(); }
                    default {};
                };
                tn = this.tf_receiver_name();
                switch (tn == (byte*)0)
                {
                    case (true) {
                    this.error(g"Expected a type keyword, literal, or struct name as type function receiver\0");
                    -> this.done(d);
                }
                    default {};
                };
                switch (this.st != (FXC_SYMTABLE*)0)
                {
                    case (true) {
                    switch (st_is_nofunc(this.st, tn))
                    {
                        case (true) {
                        this.error(this.cat2(this.cat2(g"Type \0", tn), g" is non-functional (declared with data!) and cannot have type functions defined on it\0"));
                        -> this.done(d);
                    }
                        default {};
                    };
                }
                    default {};
                };
                this.advance();
                while (this.expect(TokenType.MULTIPLY)) { depth++; this.advance(); };
                switch (this.expect(TokenType.LEFT_BRACKET))
                {
                    case (true) {
                    this.advance();
                    this.consume(TokenType.RIGHT_BRACKET);
                    is_array = true;
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.DOT); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(d); }
                    default {};
                };
                switch (this.expect2(TokenType.F_STRING, TokenType.I_STRING))
                {
                    case (true) {
                    fl = this.fstr_node();
                    switch (this.failed)
                    {
                        case (true) { -> this.done(d); }
                        default {};
                    };
                    d.text2 = this.fstr_resolve(fl);
                    node_free(fl);
                    switch (d.text2 == (byte*)0)
                    {
                        case (true) {
                        this.error(g"The type function name could not be resolved at parse time\0");
                        -> this.done(d);
                    }
                        default {};
                    };
                }
                    default {
                        switch (this.expect(TokenType.STRING_LITERAL))
                        {
                            case (true) {
                    d.text2 = this.cur_value();
                    this.advance();
                }
                            default {
                    d.text2 = this.ident();
                };
                        };
                    };
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(d); }
                    default {};
                };
                switch (this.expect(TokenType.RECURSE_ARROW))
                {
                    case (true) {
                    // the Python parser splits '<~' into '<' and '~', which is not a template list
                    this.fail_expected(TokenType.LEFT_PAREN);
                    this.err_got = TokenType.LESS_THAN;
                    -> this.done(d);
                }
                    default {};
                };
                switch (this.expect(TokenType.LESS_THAN))
                {
                    case (true) {
                    this.tmpl_cur = this.template_params(true);
                    switch (this.failed)
                    {
                        case (true) { -> this.done(d); }
                        default {};
                    };
                    this.tp_activate(this.tmpl_cur);
                }
                    default {};
                };
                this.consume(TokenType.LEFT_PAREN);
                switch (!this.failed & !this.expect(TokenType.RIGHT_PAREN))
                {
                    case (true) { this.parameter_list(d); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RETURN_ARROW); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { d.ts = this.type_spec(); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(d); }
                    default {};
                };
                rts = this.tf_receiver_ts(tn, depth, is_array);
                switch (tied)
                {
                    case (true) { rts.flags = rts.flags `| TS_TIED; }
                    default {};
                };
                d.ts2 = rts;
                // canonical name used for mangling
                eff = tn;
                switch (depth > 0 & cstr_eq(tn, g"byte\0"))
                {
                    case (true) { eff = g"string\0"; }
                    default {
                        switch (depth > 0)
                        {
                            case (true) {
                    k = 0;
                    while (k < depth) { eff = this.cat2(eff, g"_ptr\0"); k++; };
                }
                            default {
                                switch (is_array)
                                {
                                    case (true) { eff = this.cat2(tn, g"_arr\0"); }
                                    default {};
                                };
                            };
                        };
                    };
                };
                switch (tied)
                {
                    case (true) { eff = this.cat2(g"tied_\0", eff); }
                    default {};
                };
                d.text = eff;
                switch (this.expect(TokenType.SEMICOLON))
                {
                    case (true) {
                    this.advance();
                    d.flags = NF_PROTOTYPE;
                    d.a = this.mk(NodeKind.BLOCK, d.line, d.col);
                    -> this.done(d);
                }
                    default {};
                };
                d.a = this.block();
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(d);
            };

            // Appends the source text of the current token to sb (mirrors _token_to_source).
            // Quoted forms are rebuilt, every other token value is already its source text.
            token_source() -> void
            {
                int tt = this.cur();
                byte* v = this.cur_value();
                int n = this.cur_value_len();
                int i;
                int b;
                switch (tt == TokenType.STRING_LITERAL | tt == TokenType.G_STRING)
                {
                    case (true) {
                    switch (tt == TokenType.G_STRING)
                    {
                        case (true) { this.sb.put('g'); }
                        default {};
                    };
                    this.sb.put('"');
                    while (i < n)
                    {
                        b = (int)v[i];
                        switch (b == 92 | b == '"')
                        {
                            case (true) { this.sb.put(92); }
                            default {};
                        };
                        this.sb.put(b);
                        i++;
                    };
                    this.sb.put('"');
                    ->;
                }
                    default {};
                };
                switch (tt == TokenType.CHAR)
                {
                    case (true) {
                    switch (this.toks[this.pos].numeric_char != 0)
                    {
                        case (true) {
                        this.sb.put_n(v, n);
                        this.sb.put('c');
                        ->;
                    }
                        default {};
                    };
                    this.sb.put(39);
                    while (i < n)
                    {
                        b = (int)v[i];
                        switch (b == 92 | b == 39)
                        {
                            case (true) { this.sb.put(92); }
                            default {};
                        };
                        this.sb.put(b);
                        i++;
                    };
                    this.sb.put(39);
                    ->;
                }
                    default {};
                };
                switch (tt == TokenType.BYTE_LITERAL)
                {
                    case (true) {
                    this.sb.put_n(v, n);
                    this.sb.put('b');
                    ->;
                }
                    default {};
                };
                this.sb.put_n(v, n);
                ->;
            };

            // Separator before an emitflux part: a space between parts, none after '~$'
            ef_begin(bool glue) -> void
            {
                switch (this.sb.len > 0 & !glue)
                {
                    case (true) { this.sb.put(' '); }
                    default {};
                };
                ->;
            };

            // emitflux_statement -> 'emitflux' '{' <raw source text> '}' ';'
            // Captures the raw source between the braces, with nested braces counted.
            // '#};' is captured as '}' ';' without changing the depth, and '} #' ends
            // the block at any depth. Parts are joined by one space, '~$' fuses with the next part.
            emitflux_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.EMIT_FLUX, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.advance();
                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { -> this.done(n); }
                    default {};
                };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                int depth = 1;
                int c;
                bool glue = false;
                bool stop = false;
                while (depth > 0 & !stop & !this.failed)
                {
                    c = this.cur();
                    switch (c == TokenType.EOF)
                    {
                        case (true) {
                        this.error(g"Unexpected EOF inside 'emitflux' block\0");
                        break;
                    }
                        default {};
                    };
                    switch (c == TokenType.TAG)
                    {
                        case (true) {
                        switch (this.type_at(1) == TokenType.RIGHT_BRACE & this.type_at(2) == TokenType.SEMICOLON)
                        {
                            case (true) {
                            this.advance();
                            this.ef_begin(glue);
                            this.sb.put('}');
                            this.advance();
                            this.ef_begin(false);
                            this.sb.put(';');
                            this.advance();
                            glue = false;
                            continue;
                        }
                            default {};
                        };
                        this.ef_begin(glue);
                        this.token_source();
                        glue = false;
                        this.advance();
                        continue;
                    }
                        default {};
                    };
                    switch (c)
                    {
                        case (TokenType.LEFT_BRACE)
                        {
                            depth++;
                            this.ef_begin(glue);
                            this.sb.put('{');
                            glue = false;
                        }
                        case (TokenType.RIGHT_BRACE)
                        {
                            switch (this.type_at(1) == TokenType.TAG)
                            {
                                case (true) {
                                this.advance();
                                this.advance();
                                stop = true;
                            }
                                default {
                                depth--;
                                switch (depth > 0)
                                {
                                    case (true) {
                                    this.ef_begin(glue);
                                    this.sb.put('}');
                                    glue = false;
                                }
                                    default {
                                    this.advance();
                                    stop = true;
                                };
                                };
                            };
                            };
                        }
                        default
                        {
                            this.ef_begin(glue);
                            this.token_source();
                            glue = (c == TokenType.CODIFY);
                        };
                    };
                    switch (!stop)
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                n.text = this.own_n(this.sb.mem, this.sb.len);
                -> this.done(n);
            };

            // ===== CODIFY (~$) =====

            // Records a byte* string literal initializer so ~$name can splice it
            // (fparser._comptime_strings). The text is borrowed from the token.
            note_comptime_string(byte* name, TypeSpec* ts, Node* init) -> void
            {
                switch (init == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (init.kind != NodeKind.STRING_LITERAL)
                {
                    case (true) { ->; }
                    default {};
                };
                switch ((ts.flags `& TS_POINTER) == 0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (ts.base_type != DataType.BYTE)
                {
                    case (true) { ->; }
                    default {};
                };
                nm_put(this.cstrs, name, (void*)init.text);
                ->;
            };

            codify_unknown(byte* name) -> void -> this.error3(g"~$: '\0", name, g"' is not a compile-time-known byte* string literal. Only variables declared as 'byte* name = \"...\";' are supported.\0");

            // Text of the f-string or i-string token at the cursor with each {name} replaced by the
            // string recorded for name. strict reports an unrecorded name, otherwise it stands for
            // itself. Returns an owned string, or null with the error recorded.
            codify_text_of(bool strict) -> byte*
            {
                Node* fl;
                Node* p;
                byte* val;
                int k, cnt;
                switch (this.expect(TokenType.F_STRING))
                {
                    case (true) { fl = this.f_string_node(); }
                    default { fl = this.i_string_node(); };
                };
                switch (this.failed)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                cnt = node_count(fl, 0);
                while (k < cnt & !this.failed)
                {
                    p = node_child(fl, 0, k);
                    switch (p.kind)
                    {
                        case (NodeKind.STRING_LITERAL)
                        {
                            this.sb.put_str(p.text);
                        }
                        case (NodeKind.IDENTIFIER)
                        {
                            val = (byte*)nm_get(this.cstrs, p.text);
                            switch (val != (byte*)0)
                            {
                                case (true) { this.sb.put_str(val); }
                                default {
                                    switch (strict)
                                    {
                                        case (true) { this.codify_unknown(p.text); }
                                        default { this.sb.put_str(p.text); };
                                    };
                                };
                            };
                        }
                        default
                        {
                            this.error(g"~$: an interpolated expression must be an identifier\0");
                        };
                    };
                    k++;
                };
                node_free(fl);
                switch (this.failed)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            // ~$ followed by an f-string, i-string or identifier (fparser._consume_codify).
            // An identifier without a recorded string stands for itself.
            consume_codify() -> byte*
            {
                this.advance();
                switch (this.expect2(TokenType.F_STRING, TokenType.I_STRING))
                {
                    case (true) { -> this.codify_text_of(false); }
                    default {};
                };
                byte* name = this.ident();
                switch (this.failed)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                byte* val = (byte*)nm_get(this.cstrs, name);
                switch (val != (byte*)0)
                {
                    case (true) { -> val; }
                    default {};
                };
                -> name;
            };

            // Parses src with a fresh parser (no shared state, as in fparser.py) and returns its
            // statements: the first is returned, the rest are queued in pending. Null when empty.
            splice_source(byte* src) -> Node*
            {
                int n = pp_cstrlen(src);
                byte* text = this.own_n(src, n);
                Lexer* sl = (Lexer*)fmalloc((u64)((sizeof(Lexer) + 7) / 8));
                switch (sl == (Lexer*)0)
                {
                    case (true) {
                    this.fail_alloc();
                    -> (Node*)0;
                }
                    default {};
                };
                sl.__init(text, n);
                pv_push(this.sublex, (void*)sl);
                switch (!sl.tokenize())
                {
                    case (true) {
                    this.error(flux::lexer::error_message(sl.err_code));
                    -> (Node*)0;
                }
                    default {};
                };
                Parser* sp = (Parser*)fmalloc((u64)((sizeof(Parser) + 7) / 8));
                switch (sp == (Parser*)0)
                {
                    case (true) {
                    this.fail_alloc();
                    -> (Node*)0;
                }
                    default {};
                };
                sp.__init(sl);
                pv_push(this.subparsers, (void*)sp);
                sp.st = st_new();
                sp.default_byte_width = this.default_byte_width;
                sp.verbose = this.verbose;
                sp.toks = sl.tokens;
                sp.count = sl.count;
                sp.pos = 0;

                Node* first = (Node*)0;
                Node* stmt;
                int k, f;
                while (!sp.failed & !sp.expect(TokenType.EOF))
                {
                    stmt = sp.statement();
                    switch (sp.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    switch (stmt != (Node*)0)
                    {
                        case (true) {
                        switch (first == (Node*)0)
                        {
                            case (true) { first = stmt; }
                            default { nv_push(this.pending, stmt); };
                        };
                    }
                        default {};
                    };
                    k = 0;
                    while (k < sp.pending.len)
                    {
                        switch (first == (Node*)0)
                        {
                            case (true) { first = (Node*)sp.pending.items[k]; }
                            default { nv_push(this.pending, sp.pending.items[k]); };
                        };
                        k++;
                    };
                    sp.pending.len = 0;
                };

                // stubs hit while parsing the spliced source count toward this parser
                while (f < Feat.COUNT)
                {
                    switch (sp.feat_hits[f] != 0)
                    {
                        case (true) {
                        switch (this.feat_hits[f] == 0)
                        {
                            case (true) { this.stub_features++; }
                            default {};
                        };
                        this.feat_hits[f] = this.feat_hits[f] + sp.feat_hits[f];
                    }
                        default {};
                    };
                    f++;
                };
                this.stub_total = this.stub_total + sp.stub_total;

                switch (sp.failed)
                {
                    case (true) {
                    node_free(first);
                    this.failed = true;
                    this.err_kind = sp.err_kind;
                    this.err_expected = sp.err_expected;
                    this.err_got = sp.err_got;
                    this.err_line = sp.err_line;
                    this.err_col = sp.err_col;
                    this.err_msg = sp.err_msg;
                    -> (Node*)0;
                }
                    default {};
                };
                -> first;
            };

            // ~$ (STRING_LITERAL | F_STRING | I_STRING | IDENTIFIER) ';'
            // The string is parsed as statements that stand in place of this one.
            codify_statement() -> Node*
            {
                byte* src = (byte*)0;
                byte* name;
                this.advance();
                switch (this.expect(TokenType.STRING_LITERAL))
                {
                    case (true) {
                    src = this.cur_value();
                    this.advance();
                }
                    default {
                        switch (this.expect2(TokenType.F_STRING, TokenType.I_STRING))
                        {
                            case (true) {
                    src = this.codify_text_of(true);
                }
                            default {
                                switch (this.expect(TokenType.IDENTIFIER))
                                {
                                    case (true) {
                    name = this.cur_value();
                    this.advance();
                    src = (byte*)nm_get(this.cstrs, name);
                    switch (src == (byte*)0)
                    {
                        case (true) { this.codify_unknown(name); }
                        default {};
                    };
                }
                                    default {
                    this.error(g"~$: expected identifier, string literal, f-string, or i-string after codify operator\0");
                };
                                };
                            };
                        };
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                -> this.splice_source(src);
            };

            // ===== SUPPORT FOR TYPES AND EXPRESSIONS =====

            // Keeps a heap string alive until the parser is destroyed
            own(byte* s) -> byte*
            {
                pv_push(this.strs, (void*)s);
                -> s;
            };

            // Owned copy of s[0, n)
            own_n(byte* s, int n) -> byte*
            {
                byte* r = (byte*)fmalloc((u64)n + (u64)1);
                int i;
                while (i < n)
                {
                    r[i] = s[i];
                    i++;
                };
                r[n] = (byte)0;
                -> this.own(r);
            };

            // Owned a + b
            cat2(byte* a, byte* b) -> byte*
            {
                int la = pp_cstrlen(a);
                int lb = pp_cstrlen(b);
                byte* r = (byte*)fmalloc((u64)(la + lb + 1));
                int i, j;
                while (i < la)
                {
                    r[i] = a[i];
                    i++;
                };
                while (j < lb)
                {
                    r[la + j] = b[j];
                    j++;
                };
                r[la + lb] = (byte)0;
                -> this.own(r);
            };

            fail_alloc() -> void
            {
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                this.failed = true;
                this.err_kind = ParseErr.ALLOC;
                ->;
            };

            // New node at (line, col)
            mk(int kind, int line, int col) -> Node*
            {
                Node* n = node_new(kind, line, col);
                switch (n == (Node*)0)
                {
                    case (true) { this.fail_alloc(); }
                    default {};
                };
                -> n;
            };

            // Clears a recorded error so a speculative parse can be abandoned
            clear_error() -> void
            {
                this.failed = false;
                this.err_kind = ParseErr.NONE;
                this.err_msg = (byte*)0;
                ->;
            };

            // Records a feature hit without consuming anything
            note_feat(int feat) -> void
            {
                this.stub_total++;
                switch (this.feat_hits[feat] == 0)
                {
                    case (true) { this.stub_features++; }
                    default {};
                };
                this.feat_hits[feat] = this.feat_hits[feat] + 1;
                switch (this.verbose)
                {
                    case (true) {
                    print(g"[BootstrapParser] \0");
                    print(feature_name(feat));
                    print(g" not implemented (line \0");
                    print(this.cur_line());
                    print(g", col \0");
                    print(this.cur_col());
                    println(g")\0");
                }
                    default {
                        switch (this.feat_hits[feat] == 1)
                        {
                            case (true) {
                    print(g"[BootstrapParser] \0");
                    print(feature_name(feat));
                    println(g" not implemented\0");
                }
                            default {};
                        };
                    };
                };
                ->;
            };

            // "Unexpected token: NAME" at the current token
            error_unexpected() -> void -> this.error(this.cat2(g"Unexpected token: \0", token_name(this.cur())));

            // Integer value of a literal. Handles 0x 0b 0o, the base 32 0d form and
            // decimal, ignoring '_'. *ok is cleared when no digit was read.
            parse_int(byte* s, bool* ok) -> i64
            {
                i64 v = 0;
                i64 base = 10;
                int i = 0;
                int d;
                int c;
                bool any = false;
                switch (s[0] == '0' & (s[1] == 'x' | s[1] == 'X'))
                {
                    case (true) { base = 16; i = 2; }
                    default {
                        switch (s[0] == '0' & (s[1] == 'b' | s[1] == 'B'))
                        {
                            case (true) { base = 2; i = 2; }
                            default {
                                switch (s[0] == '0' & (s[1] == 'o' | s[1] == 'O'))
                                {
                                    case (true) { base = 8; i = 2; }
                                    default {
                                        switch (s[0] == '0' & s[1] == 'd')
                                        {
                                            case (true) { base = 32; i = 2; }
                                            default {};
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
                while (s[i] != 0)
                {
                    c = (int)s[i];
                    i++;
                    switch (c == '_')
                    {
                        case (true) { continue; }
                        default {};
                    };
                    d = -1;
                    switch (c >= '0' & c <= '9')
                    {
                        case (true) { d = c - '0'; }
                        default {
                            switch (c >= 'a' & c <= 'z')
                            {
                                case (true) { d = c - 'a' + 10; }
                                default {
                                    switch (c >= 'A' & c <= 'Z')
                                    {
                                        case (true) { d = c - 'A' + 10; }
                                        default {};
                                    };
                                };
                            };
                        };
                    };
                    switch (d < 0 | (i64)d >= base)
                    {
                        case (true) { break; }
                        default {};
                    };
                    v = v * base + (i64)d;
                    any = true;
                };
                *ok = any;
                -> v;
            };

            // ---- Exact decimal to double conversion (round to nearest even) ----
            // Big naturals are little endian arrays of 32 bit limbs held in u64 cells.

            bg_trim(u64* a, int* n) -> void
            {
                int k = *n;
                while (k > 0)
                {
                    switch (a[k - 1] != (u64)0)
                    {
                        case (true) { break; }
                        default {};
                    };
                    k--;
                };
                *n = k;
                ->;
            };

            bg_mul_small(u64* a, int* n, u64 m) -> void
            {
                u64 carry = (u64)0;
                u64 t;
                int i = 0;
                int k = *n;
                while (i < k)
                {
                    t = a[i] * m + carry;
                    a[i] = t `& (u64)4294967295;
                    carry = t >> (u64)32;
                    i++;
                };
                while (carry != (u64)0)
                {
                    a[k] = carry `& (u64)4294967295;
                    carry = carry >> (u64)32;
                    k++;
                };
                *n = k;
                ->;
            };

            bg_add_small(u64* a, int* n, u64 v) -> void
            {
                u64 carry = v;
                u64 t;
                int i = 0;
                int k = *n;
                while (carry != (u64)0)
                {
                    switch (i >= k)
                    {
                        case (true) {
                        a[i] = (u64)0;
                        k++;
                    }
                        default {};
                    };
                    t = a[i] + carry;
                    a[i] = t `& (u64)4294967295;
                    carry = t >> (u64)32;
                    i++;
                };
                *n = k;
                ->;
            };

            bg_shl(u64* a, int* n, int sh) -> void
            {
                int ls = sh / 32;
                int bs = sh % 32;
                int old = *n;
                int i;
                u64 v;
                switch (old == 0)
                {
                    case (true) { ->; }
                    default {};
                };
                i = old;
                while (i <= old + ls)
                {
                    a[i] = (u64)0;
                    i++;
                };
                i = old - 1;
                while (i >= 0)
                {
                    v = a[i] << (u64)bs;
                    a[i + ls + 1] = a[i + ls + 1] `| (v >> (u64)32);
                    a[i + ls] = v `& (u64)4294967295;
                    i--;
                };
                i = 0;
                while (i < ls)
                {
                    a[i] = (u64)0;
                    i++;
                };
                *n = old + ls + 1;
                this.bg_trim(a, n);
                ->;
            };

            bg_div_small(u64* a, int* n, u64 d) -> u64
            {
                u64 rem = (u64)0;
                u64 cur;
                int i = *n - 1;
                while (i >= 0)
                {
                    cur = (rem << (u64)32) `| a[i];
                    a[i] = cur / d;
                    rem = cur % d;
                    i--;
                };
                this.bg_trim(a, n);
                -> rem;
            };

            bg_bitlen(u64* a, int n) -> int
            {
                int b = 0;
                u64 top;
                switch (n == 0)
                {
                    case (true) { -> 0; }
                    default {};
                };
                top = a[n - 1];
                while (top != (u64)0)
                {
                    b++;
                    top = top >> (u64)1;
                };
                -> (n - 1) * 32 + b;
            };

            bg_bit(u64* a, int n, int pos) -> u64
            {
                int li = pos / 32;
                switch (pos < 0 | li >= n)
                {
                    case (true) { -> (u64)0; }
                    default {};
                };
                -> (a[li] >> (u64)(pos % 32)) `& (u64)1;
            };

            bg_low_set(u64* a, int n, int pos) -> bool
            {
                int li = pos / 32;
                int i = 0;
                switch (pos <= 0)
                {
                    case (true) { -> false; }
                    default {};
                };
                while (i < li & i < n)
                {
                    switch (a[i] != (u64)0)
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    i++;
                };
                switch (li < n)
                {
                    case (true) {
                    switch ((a[li] `& (((u64)1 << (u64)(pos % 32)) - (u64)1)) != (u64)0)
                    {
                        case (true) { -> true; }
                        default {};
                    };
                }
                    default {};
                };
                -> false;
            };

            // Value of a decimal floating literal (digits, '.', optional exponent)
            parse_double(byte* s) -> double
            {
                u64* a = (u64*)fmalloc((u64)(8 * 160));
                int n = 0;
                int i = 0;
                int c;
                bool frac = false;
                bool exneg = false;
                int fdig = 0;
                int ex = 0;
                int e10;
                int k;
                int sh = 0;
                int bl;
                int r;
                int eb;
                int b;
                bool sticky = false;
                bool rbit;
                u64 mant = (u64)0;
                double v;
                while (s[i] != 0)
                {
                    c = (int)s[i];
                    switch (c >= '0' & c <= '9')
                    {
                        case (true) {
                        switch (n < 100)
                        {
                            case (true) {
                            this.bg_mul_small(a, @n, (u64)10);
                            this.bg_add_small(a, @n, (u64)(c - '0'));
                            switch (frac)
                            {
                                case (true) { fdig++; }
                                default {};
                            };
                        }
                            default {
                                switch (!frac)
                                {
                                    case (true) { ex = ex + 1; }
                                    default {};
                                };
                            };
                        };
                    }
                        default {
                            switch (c == '.')
                            {
                                case (true) { frac = true; }
                                default {
                                    switch (c == 'e' | c == 'E')
                                    {
                                        case (true) {
                        i++;
                        switch (s[i] == '-')
                        {
                            case (true) { exneg = true; i++; }
                            default {
                                switch (s[i] == '+')
                                {
                                    case (true) { i++; }
                                    default {};
                                };
                            };
                        };
                        k = 0;
                        while (s[i] >= '0' & s[i] <= '9')
                        {
                            switch (k < 100000)
                            {
                                case (true) { k = k * 10 + ((int)s[i] - '0'); }
                                default {};
                            };
                            i++;
                        };
                        switch (exneg)
                        {
                            case (true) { ex = ex - k; }
                            default { ex = ex + k; };
                        };
                        break;
                    }
                                        default {
                                            switch (c != '_')
                                            {
                                                case (true) { break; }
                                                default {};
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                    i++;
                };
                // The loop above folded dropped integer digits into ex; fractional digits shift it down
                e10 = ex - fdig;
                switch (n == 0)
                {
                    case (true) {
                    ffree((void*)a);
                    -> 0.0;
                }
                    default {};
                };
                switch (e10 > 400)
                {
                    case (true) { e10 = 400; }
                    default {};
                };
                switch (e10 < -400)
                {
                    case (true) { e10 = -400; }
                    default {};
                };
                switch (e10 >= 0)
                {
                    case (true) {
                    k = e10;
                    while (k >= 9)
                    {
                        this.bg_mul_small(a, @n, (u64)1000000000);
                        k = k - 9;
                    };
                    while (k > 0)
                    {
                        this.bg_mul_small(a, @n, (u64)10);
                        k--;
                    };
                }
                    default {
                    k = 0 - e10;
                    bl = this.bg_bitlen(a, n);
                    sh = 66 + (k * 3322) / 1000 + 1 - bl;
                    switch (sh < 0)
                    {
                        case (true) { sh = 0; }
                        default {};
                    };
                    this.bg_shl(a, @n, sh);
                    while (k >= 9)
                    {
                        switch (this.bg_div_small(a, @n, (u64)1000000000) != (u64)0)
                        {
                            case (true) { sticky = true; }
                            default {};
                        };
                        k = k - 9;
                    };
                    c = 1;
                    while (k > 0)
                    {
                        c = c * 10;
                        k--;
                    };
                    switch (c > 1)
                    {
                        case (true) {
                        switch (this.bg_div_small(a, @n, (u64)c) != (u64)0)
                        {
                            case (true) { sticky = true; }
                            default {};
                        };
                    }
                        default {};
                    };
                };
                };
                bl = this.bg_bitlen(a, n);
                r = bl - 53;
                switch (r < 0)
                {
                    case (true) { r = 0; }
                    default {};
                };
                b = bl - 1;
                while (b >= r)
                {
                    mant = (mant << (u64)1) `| this.bg_bit(a, n, b);
                    b--;
                };
                switch (r > 0)
                {
                    case (true) {
                    rbit = this.bg_bit(a, n, r - 1) != (u64)0;
                    switch (this.bg_low_set(a, n, r - 1))
                    {
                        case (true) { sticky = true; }
                        default {};
                    };
                    switch (rbit)
                    {
                        case (true) {
                        switch (sticky | (mant `& (u64)1) != (u64)0)
                        {
                            case (true) { mant = mant + (u64)1; }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                v = (double)mant;
                eb = r - sh;
                while (eb > 0)
                {
                    v = v * 2.0;
                    eb--;
                };
                while (eb < 0)
                {
                    v = v * 0.5;
                    eb++;
                };
                ffree((void*)a);
                -> v;
            };

            // Name used when a type argument list is folded into a type name
            // (fparser._type_system_to_mangle_str)
            // "NS::x" to "NS__x"
            tp_unqual(byte* s) -> byte*
            {
                int i;
                int n = pp_cstrlen(s);
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                while (i < n)
                {
                    switch (s[i] == ':' & i + 1 < n)
                    {
                        case (true) {
                        switch (s[i + 1] == ':')
                        {
                            case (true) {
                            this.sb.put_str(g"__\0");
                            i = i + 2;
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    this.sb.put(s[i]);
                    i++;
                };
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            // The registry key when name (bare, or NS::x as NS__x) is a template struct or object
            tmpl_type_key(byte* name) -> byte*
            {
                TemplateEntry* e = this.template_lookup(name);
                byte* q;
                switch (e != (TemplateEntry*)0)
                {
                    case (true) {
                    switch (e.kind == 1 | e.kind == 2)
                    {
                        case (true) { -> name; }
                        default {};
                    };
                }
                    default {};
                };
                switch (nm_has(this.tobj_fwd, name))
                {
                    case (true) { -> name; }
                    default {};
                };
                q = this.tp_unqual(name);
                e = this.template_lookup(q);
                switch (e != (TemplateEntry*)0)
                {
                    case (true) {
                    switch (e.kind == 1 | e.kind == 2)
                    {
                        case (true) { -> q; }
                        default {};
                    };
                }
                    default {};
                };
                switch (nm_has(this.tobj_fwd, q))
                {
                    case (true) { -> q; }
                    default {};
                };
                -> (byte*)0;
            };

            // Name<args> after a named type (cursor on '<'): resolves the instance, or defers
            // as "Key<a,b>" while an argument is still an active template parameter.
            template_type_use(TypeSpec* t, byte* key) -> void
            {
                PtrVec* names = pv_new();
                PtrVec* specs = pv_new();
                TypeSpec* a;
                bool postpone = false;
                int i;
                this.advance();
                a = this.type_spec();
                pv_push(specs, (void*)a);
                switch (!this.failed)
                {
                    case (true) { pv_push(names, (void*)this.type_mangle_str(a)); }
                    default {};
                };
                while (!this.failed & this.expect(TokenType.COMMA))
                {
                    this.advance();
                    a = this.type_spec();
                    pv_push(specs, (void*)a);
                    switch (!this.failed)
                    {
                        case (true) { pv_push(names, (void*)this.type_mangle_str(a)); }
                        default {};
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.GREATER_THAN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) {
                    while (i < names.len)
                    {
                        switch (this.tp_active((byte*)names.items[i]))
                        {
                            case (true) { postpone = true; }
                            default {};
                        };
                        i++;
                    };
                    switch (postpone)
                    {
                        case (true) {
                        t.custom_typename = this.deferred_name(key, names);
                    }
                        default {
                        t.custom_typename = this.resolve_template_type(key, names, specs);
                    };
                    };
                }
                    default {};
                };
                i = 0;
                while (i < specs.len)
                {
                    typespec_free((TypeSpec*)specs.items[i]);
                    i++;
                };
                pv_free(names);
                pv_free(specs);
                ->;
            };

            // Instantiates a template struct (kind 1) or object (kind 2); returns the mangled name
            // (fparser._resolve_template_struct / _resolve_template_object / _instantiate_template_node)
            resolve_template_type(byte* key, PtrVec* names, PtrVec* specs) -> byte*
            {
                TemplateEntry* te = this.template_lookup(key);
                NameMap* map;
                Node* concrete;
                byte* mangled;
                byte* what;
                int i;
                switch (te == (TemplateEntry*)0)
                {
                    case (true) { what = g"struct\0"; }
                    default {
                        switch (te.kind == 1)
                        {
                            case (true) { what = g"struct\0"; }
                            default { what = g"object\0"; };
                        };
                    };
                };
                switch (te == (TemplateEntry*)0)
                {
                    case (true) {
                    this.error(this.cat2(this.cat2(g"Unknown template struct '\0", key), g"'\0"));
                    -> key;
                }
                    default {};
                };
                switch (te.kind != 1 & te.kind != 2)
                {
                    case (true) {
                    this.error(this.cat2(this.cat2(g"Unknown template struct '\0", key), g"'\0"));
                    -> key;
                }
                    default {};
                };
                switch (names.len != te.params.len)
                {
                    case (true) {
                    this.sb.len = 0;
                    this.sb.put_str(g"Template \0");
                    this.sb.put_str(what);
                    this.sb.put_str(g" '\0");
                    this.sb.put_str(key);
                    this.sb.put_str(g"' expects \0");
                    this.sb.put_int(te.params.len);
                    this.sb.put_str(g" type argument(s), got \0");
                    this.sb.put_int(names.len);
                    this.error(this.own_n(this.sb.mem, this.sb.len));
                    -> key;
                }
                    default {};
                };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                this.sb.put_str(key);
                this.sb.put_str(g"__\0");
                while (i < names.len)
                {
                    switch (i > 0)
                    {
                        case (true) { this.sb.put_str(g"_\0"); }
                        default {};
                    };
                    this.sb.put_str((byte*)names.items[i]);
                    i++;
                };
                mangled = this.own_n(this.sb.mem, this.sb.len);
                switch (nm_has(te.emitted, mangled))
                {
                    case (true) { -> mangled; }
                    default {};
                };
                nm_put(te.emitted, mangled, (void*)te);
                map = this.tp_mapping(te, names, specs);
                concrete = node_clone(te.node);
                this.subst_node(concrete, map);
                nm_free(map);
                switch (this.failed)
                {
                    case (true) {
                    node_free(concrete);
                    -> mangled;
                }
                    default {};
                };
                concrete.text = mangled;
                switch (te.kind)
                {
                    case (1)
                    {
                        switch (concrete.l4 != (NodeVec*)0)
                        {
                            case (true) { concrete.l4.len = 0; }
                            default {};
                        };
                        pv_push(this.tinst_s, (void*)concrete);
                    }
                    default
                    {
                        switch (concrete.d != (Node*)0)
                        {
                            case (true) {
                            node_free(concrete.d);
                            concrete.d = (Node*)0;
                        }
                            default {};
                        };
                        pv_push(this.tinst_o, (void*)concrete);
                        nm_put(this.pobjs, mangled, (void*)concrete);
                        switch (nm_has(this.oinit, key))
                        {
                            case (true) { nm_put(this.oinit, mangled, (void*)concrete); }
                            default {};
                        };
                    };
                };
                -> mangled;
            };

            // "Key<T,U>" inside an instantiated template body whose arguments are now known
            subst_deferred_type(byte* s, NameMap* map) -> byte*
            {
                PtrVec* raw = pv_new();
                PtrVec* names = pv_new();
                PtrVec* specs = pv_new();
                int lt = this.tp_split_deferred(s, raw);
                int i;
                bool any = false;
                byte* base;
                byte* r = s;
                TemplateEntry* te;
                TypeSpec* c;
                byte* a;
                switch (lt > 0)
                {
                    case (true) {
                    base = this.own_n(s, lt);
                    te = this.template_lookup(base);
                    while (i < raw.len)
                    {
                        switch (nm_has(map, (byte*)raw.items[i]))
                        {
                            case (true) { any = true; }
                            default {};
                        };
                        i++;
                    };
                    switch (te != (TemplateEntry*)0 & any)
                    {
                        case (true) {
                        switch (te.kind == 1 | te.kind == 2)
                        {
                            case (true) {
                            i = 0;
                            while (i < raw.len)
                            {
                                a = (byte*)raw.items[i];
                                switch (nm_has(map, a))
                                {
                                    case (true) {
                                    c = (TypeSpec*)nm_get(map, a);
                                    pv_push(names, (void*)this.ts_mangle(c));
                                    pv_push(specs, (void*)c);
                                }
                                    default {
                                    c = this.tmp_type();
                                    c.base_type = DataType.DATA;
                                    c.custom_typename = a;
                                    pv_push(names, (void*)a);
                                    pv_push(specs, (void*)c);
                                };
                                };
                                i++;
                            };
                            r = this.resolve_template_type(base, names, specs);
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                pv_free(raw);
                pv_free(names);
                pv_free(specs);
                -> r;
            };

            type_mangle_str(TypeSpec* t) -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                switch (t.custom_typename != (byte*)0)
                {
                    case (true) { -> t.custom_typename; }
                    default {};
                };
                switch ((t.flags `& TS_POINTER) != 0)
                {
                    case (true) { this.sb.put_str(g"ptr_\0"); }
                    default {};
                };
                switch (t.base_type == DataType.DATA & t.bit_width > 0)
                {
                    case (true) {
                    this.sb.put_str(g"data_\0");
                    switch ((t.flags `& TS_POINTER) == 0 & (t.flags `& TS_SIGNED) != 0)
                    {
                        case (true) { this.sb.put_str(g"i\0"); }
                        default { this.sb.put_str(g"u\0"); };
                    };
                    this.sb.put_int(t.bit_width);
                }
                    default {
                    this.sb.put_str(datatype_text(t.base_type));
                };
                };
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            // ===== TYPES =====

            // Token that starts a builtin or named type
            is_type_keyword() -> bool -> this.expect4(TokenType.SINT, TokenType.UINT, TokenType.FLOAT_KW, TokenType.DOUBLE_KW) | this.expect4(TokenType.SLONG, TokenType.ULONG, TokenType.CHAR, TokenType.BOOL_KW) | this.expect4(TokenType.BYTE, TokenType.DATA, TokenType.VOID, TokenType.THIS) | this.expect4(TokenType.STRUCT, TokenType.OBJECT, TokenType.DICT, TokenType.IDENTIFIER);

            // base_type -> builtin | dict{K:V} | '' | IDENTIFIER ('::' IDENTIFIER)* | codify
            // Fills t.base_type (and custom_typename or dict_key/dict_value).
            // Returns 0 on error, 1 for a builtin, 2 for a named type, 3 for dict,
            // 4 for the "" string type.
            base_type(TypeSpec* t) -> int
            {
                int c = this.cur();
                switch (c == TokenType.SINT)
                {
                    case (true) { t.base_type = DataType.SINT; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.UINT)
                {
                    case (true) { t.base_type = DataType.UINT; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.FLOAT_KW)
                {
                    case (true) { t.base_type = DataType.FLOAT; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.DOUBLE_KW)
                {
                    case (true) { t.base_type = DataType.DOUBLE; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.SLONG)
                {
                    case (true) { t.base_type = DataType.SLONG; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.ULONG)
                {
                    case (true) { t.base_type = DataType.ULONG; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.CHAR)
                {
                    case (true) { t.base_type = DataType.CHAR; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.BOOL_KW)
                {
                    case (true) { t.base_type = DataType.BOOL; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.BYTE)
                {
                    case (true) { t.base_type = DataType.BYTE; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.DATA)
                {
                    case (true) { t.base_type = DataType.DATA; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.VOID)
                {
                    case (true) { t.base_type = DataType.VOID; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.THIS)
                {
                    case (true) { t.base_type = DataType.THIS; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.STRUCT)
                {
                    case (true) { t.base_type = DataType.STRUCT; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.OBJECT)
                {
                    case (true) { t.base_type = DataType.OBJECT; this.advance(); -> 1; }
                    default {};
                };
                switch (c == TokenType.DICT)
                {
                    case (true) {
                    this.advance();
                    t.base_type = DataType.DICT;
                    switch (!this.consume(TokenType.LEFT_BRACE))
                    {
                        case (true) { -> 0; }
                        default {};
                    };
                    t.dict_key = this.type_spec();
                    switch (this.failed)
                    {
                        case (true) { -> 0; }
                        default {};
                    };
                    switch (!this.consume(TokenType.COLON))
                    {
                        case (true) { -> 0; }
                        default {};
                    };
                    t.dict_value = this.type_spec();
                    switch (this.failed)
                    {
                        case (true) { -> 0; }
                        default {};
                    };
                    switch (!this.consume(TokenType.RIGHT_BRACE))
                    {
                        case (true) { -> 0; }
                        default {};
                    };
                    -> 3;
                }
                    default {};
                };
                switch (c == TokenType.STRING_LITERAL & this.cur_value_len() == 0)
                {
                    case (true) {
                    this.advance();
                    t.base_type = DataType.BYTE;
                    -> 4;
                }
                    default {};
                };
                switch (c == TokenType.IDENTIFIER)
                {
                    case (true) {
                    byte* name = this.cur_value();
                    this.advance();
                    while (this.expect(TokenType.SCOPE))
                    {
                        this.advance();
                        switch (this.expect(TokenType.IDENTIFIER))
                        {
                            case (true) {
                            name = this.cat2(this.cat2(name, g"::\0"), this.cur_value());
                            this.advance();
                        }
                            default { break; };
                        };
                    };
                    t.base_type = DataType.DATA;
                    t.custom_typename = name;
                    -> 2;
                }
                    default {};
                };
                switch (c == TokenType.CODIFY)
                {
                    case (true) {
                    // ~$name / ~$f"..." as a type: the resolved string names a builtin or a custom type
                    byte* resolved = this.consume_codify();
                    switch (this.failed)
                    {
                        case (true) { -> 0; }
                        default {};
                    };
                    int bt = this.codify_builtin(resolved);
                    switch (bt >= 0)
                    {
                        case (true) {
                        t.base_type = bt;
                        -> 1;
                    }
                        default {};
                    };
                    t.base_type = DataType.DATA;
                    t.custom_typename = resolved;
                    -> 2;
                }
                    default {};
                };
                this.error(g"Expected type specifier\0");
                -> 0;
            };

            // DataType named by a codified type string, -1 when it is not a builtin type name
            codify_builtin(byte* s) -> int
            {
                switch (cstr_eq(s, g"byte\0"))
                {
                    case (true) { -> DataType.BYTE; }
                    default {};
                };
                switch (cstr_eq(s, g"int\0"))
                {
                    case (true) { -> DataType.SINT; }
                    default {};
                };
                switch (cstr_eq(s, g"uint\0"))
                {
                    case (true) { -> DataType.UINT; }
                    default {};
                };
                switch (cstr_eq(s, g"long\0"))
                {
                    case (true) { -> DataType.SLONG; }
                    default {};
                };
                switch (cstr_eq(s, g"ulong\0"))
                {
                    case (true) { -> DataType.ULONG; }
                    default {};
                };
                switch (cstr_eq(s, g"float\0"))
                {
                    case (true) { -> DataType.FLOAT; }
                    default {};
                };
                switch (cstr_eq(s, g"double\0"))
                {
                    case (true) { -> DataType.DOUBLE; }
                    default {};
                };
                switch (cstr_eq(s, g"bool\0"))
                {
                    case (true) { -> DataType.BOOL; }
                    default {};
                };
                switch (cstr_eq(s, g"char\0"))
                {
                    case (true) { -> DataType.CHAR; }
                    default {};
                };
                switch (cstr_eq(s, g"void\0"))
                {
                    case (true) { -> DataType.VOID; }
                    default {};
                };
                -> -1;
            };

            // Scalar fields of s into d (no shared children)
            copy_scalar_type(TypeSpec* d, TypeSpec* s) -> void
            {
                d.base_type = s.base_type;
                d.flags = s.flags `& (TS_SIGNED `| TS_CONST `| TS_VOLATILE `| TS_TIED `| TS_LOCAL `|
                                      TS_POINTER `| TS_CONST_POINTER `| TS_NO_FUNCTIONS);
                d.bit_width = s.bit_width;
                d.alignment = s.alignment;
                d.endianness = s.endianness;
                d.pointer_depth = s.pointer_depth;
                d.storage_class = s.storage_class;
                d.custom_typename = s.custom_typename;
                ->;
            };

            // type_spec -> storage? const? volatile? (signed|unsigned)? '~'? base_type
            //              (data width)? '*'* ('[' expression? ']')* '*'*
            // Returns null with the error recorded on failure.
            type_spec() -> TypeSpec*
            {
                TypeSpec* t = typespec_new();
                switch (t == (TypeSpec*)0)
                {
                    case (true) {
                    this.fail_alloc();
                    -> t;
                }
                    default {};
                };
                int sc = -1;
                bool singinit_seen = false;
                bool sign_explicit = false;
                bool is_signed = false;

                switch (this.expect(TokenType.SINGINIT))
                {
                    case (true) {
                    singinit_seen = true;
                    sc = StorageClass.SINGINIT;
                    this.advance();
                }
                    default {};
                };
                switch (this.expect(TokenType.GLOBAL))
                {
                    case (true) { sc = StorageClass.GLOBAL; this.advance(); }
                    default {
                        switch (this.expect(TokenType.LOCAL))
                        {
                            case (true) {
                    t.flags = t.flags `| TS_LOCAL;
                    sc = StorageClass.LOCAL;
                    this.advance();
                }
                            default {
                                switch (this.expect(TokenType.HEAP))
                                {
                                    case (true) { sc = StorageClass.HEAP; this.advance(); }
                                    default {
                                        switch (this.expect(TokenType.STACK))
                                        {
                                            case (true) { sc = StorageClass.STACK; this.advance(); }
                                            default {
                                                switch (this.expect(TokenType.REGISTER))
                                                {
                                                    case (true) { sc = StorageClass.REGISTER; this.advance(); }
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

                switch (!singinit_seen & this.expect(TokenType.SINGINIT))
                {
                    case (true) {
                    singinit_seen = true;
                    this.advance();
                }
                    default {};
                };
                switch (this.expect(TokenType.CONST))
                {
                    case (true) { t.flags = t.flags `| TS_CONST; this.advance(); }
                    default {};
                };
                switch (this.expect(TokenType.VOLATILE))
                {
                    case (true) { t.flags = t.flags `| TS_VOLATILE; this.advance(); }
                    default {};
                };
                switch (this.expect(TokenType.SIGNED))
                {
                    case (true) {
                    is_signed = true;
                    sign_explicit = true;
                    this.advance();
                }
                    default {
                        switch (this.expect(TokenType.UNSIGNED))
                        {
                            case (true) {
                    sign_explicit = true;
                    this.advance();
                }
                            default {};
                        };
                    };
                };
                switch (this.expect(TokenType.TIE))
                {
                    case (true) { t.flags = t.flags `| TS_TIED; this.advance(); }
                    default {};
                };
                switch (is_signed)
                {
                    case (true) { t.flags = t.flags `| TS_SIGNED; }
                    default {};
                };
                t.storage_class = sc;

                int kind = this.base_type(t);
                switch (kind == 0)
                {
                    case (true) { -> t; }
                    default {};
                };

                int depth = 0;
                switch (kind == 3)
                {
                    case (true) {
                    while (this.expect(TokenType.MULTIPLY))
                    {
                        depth++;
                        this.advance();
                    };
                    t.flags = t.flags `& (TS_CONST `| TS_VOLATILE);
                    switch (depth > 0)
                    {
                        case (true) { t.flags = t.flags `| TS_POINTER; }
                        default {};
                    };
                    t.pointer_depth = depth;
                    -> t;
                }
                    default {};
                };
                switch (kind == 4)
                {
                    case (true) {
                    t.flags = (t.flags `& (TS_CONST `| TS_VOLATILE)) `| TS_POINTER;
                    t.pointer_depth = 1;
                    -> t;
                }
                    default {};
                };

                // Template arguments Name<T, U>: with no template registry yet, an angle
                // list that parses as types is folded into the type name.
                byte* tkey = (byte*)0;
                switch (kind == 2 & this.expect(TokenType.LESS_THAN))
                {
                    case (true) { tkey = this.tmpl_type_key(t.custom_typename); }
                    default {};
                };
                switch (tkey != (byte*)0)
                {
                    case (true) {
                    this.template_type_use(t, tkey);
                    switch (this.failed)
                    {
                        case (true) { -> t; }
                        default {};
                    };
                }
                    default {
                        switch (kind == 2 & this.expect(TokenType.LESS_THAN))
                        {
                            case (true) {
                    int m = this.mark();
                    this.advance();
                    PtrVec* names = pv_new();
                    TypeSpec* a = this.type_spec();
                    bool good = !this.failed;
                    switch (good)
                    {
                        case (true) {
                        pv_push(names, (void*)this.type_mangle_str(a));
                        typespec_free(a);
                        while (this.expect(TokenType.COMMA) & good)
                        {
                            this.advance();
                            a = this.type_spec();
                            switch (this.failed)
                            {
                                case (true) { good = false; }
                                default {
                                pv_push(names, (void*)this.type_mangle_str(a));
                                typespec_free(a);
                            };
                            };
                        };
                        switch (good & !this.expect(TokenType.GREATER_THAN))
                        {
                            case (true) { good = false; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (good)
                    {
                        case (true) {
                        this.advance();
                        this.sb.len = 0;
                        this.sb.mem[0] = (byte)0;
                        this.sb.put_str(t.custom_typename);
                        this.sb.put_str(g"<\0");
                        int i;
                        while (i < names.len)
                        {
                            switch (i > 0)
                            {
                                case (true) { this.sb.put_str(g",\0"); }
                                default {};
                            };
                            this.sb.put_str((byte*)names.items[i]);
                            i++;
                        };
                        this.sb.put_str(g">\0");
                        t.custom_typename = this.own_n(this.sb.mem, this.sb.len);
                    }
                        default {
                        this.clear_error();
                        this.reset(m);
                    };
                    };
                    pv_free(names);
                }
                            default {};
                        };
                    };
                };

                // data{width:align:endian}, data!{...}
                bool nofunc = false;
                switch (t.base_type == DataType.DATA & t.custom_typename == (byte*)0)
                {
                    case (true) {
                    switch (this.expect(TokenType.NOT))
                    {
                        case (true) {
                        nofunc = true;
                        this.advance();
                    }
                        default {};
                    };
                    switch (this.expect(TokenType.LEFT_BRACE))
                    {
                        case (true) {
                        this.advance();
                        bool ok;
                        switch (!this.expect(TokenType.SINT_LITERAL))
                        {
                            case (true) {
                            this.fail_expected(TokenType.SINT_LITERAL);
                            -> t;
                        }
                            default {};
                        };
                        t.bit_width = (int)this.parse_int(this.cur_value(), @ok);
                        this.advance();
                        switch (this.expect(TokenType.COLON))
                        {
                            case (true) {
                            this.advance();
                            switch (!this.expect(TokenType.SINT_LITERAL))
                            {
                                case (true) {
                                this.fail_expected(TokenType.SINT_LITERAL);
                                -> t;
                            }
                                default {};
                            };
                            t.alignment = (int)this.parse_int(this.cur_value(), @ok);
                            this.advance();
                            switch (this.expect(TokenType.COLON))
                            {
                                case (true) {
                                this.advance();
                                switch (!this.expect(TokenType.SINT_LITERAL))
                                {
                                    case (true) {
                                    this.fail_expected(TokenType.SINT_LITERAL);
                                    -> t;
                                }
                                    default {};
                                };
                                t.endianness = (int)this.parse_int(this.cur_value(), @ok);
                                this.advance();
                            }
                                default {};
                            };
                        }
                            default {
                                switch (this.expect(TokenType.SCOPE))
                                {
                                    case (true) {
                            this.advance();
                            t.alignment = t.bit_width;
                            switch (!this.expect(TokenType.SINT_LITERAL))
                            {
                                case (true) {
                                this.fail_expected(TokenType.SINT_LITERAL);
                                -> t;
                            }
                                default {};
                            };
                            t.endianness = (int)this.parse_int(this.cur_value(), @ok);
                            this.advance();
                        }
                                    default {};
                                };
                            };
                        };
                        switch (!this.consume(TokenType.RIGHT_BRACE))
                        {
                            case (true) { -> t; }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };

                int pdepth = 0;
                while (this.expect(TokenType.MULTIPLY))
                {
                    pdepth++;
                    this.advance();
                };

                NodeVec* dims = (NodeVec*)0;
                Node* dim;
                while (this.expect(TokenType.LEFT_BRACKET))
                {
                    this.advance();
                    switch (dims == (NodeVec*)0)
                    {
                        case (true) { dims = nv_new(); }
                        default {};
                    };
                    switch (!this.expect(TokenType.RIGHT_BRACKET))
                    {
                        case (true) {
                        dim = this.expression();
                        switch (this.failed)
                        {
                            case (true) { -> t; }
                            default {};
                        };
                        nv_push(dims, dim);
                    }
                        default { nv_push(dims, (Node*)0); };
                    };
                    switch (!this.consume(TokenType.RIGHT_BRACKET))
                    {
                        case (true) { -> t; }
                        default {};
                    };
                };
                while (this.expect(TokenType.MULTIPLY))
                {
                    pdepth++;
                    this.advance();
                };
                bool is_array = dims != (NodeVec*)0;

                // A named type that is an alias takes the aliased type's fields
                switch (t.custom_typename != (byte*)0 & this.st != (FXC_SYMTABLE*)0)
                {
                    case (true) {
                    TypeSpec* rs = st_get_type_spec(this.st, t.custom_typename);
                    switch (rs != (TypeSpec*)0)
                    {
                        case (true) {
                        switch (rs.base_type != DataType.DICT & rs.base_type != DataType.FUNC_PTR)
                        {
                            case (true) {
                            bool alias_arr = (rs.flags `& TS_ARRAY) != 0;
                            int keep_sc = t.storage_class;
                            int keep_flags = t.flags;
                            this.copy_scalar_type(t, rs);
                            t.flags = t.flags `| (keep_flags `& (TS_TIED `| TS_CONST `| TS_VOLATILE));
                            switch (keep_sc != -1)
                            {
                                case (true) {
                                t.storage_class = keep_sc;
                                switch (keep_sc == StorageClass.LOCAL)
                                {
                                    case (true) { t.flags = t.flags `| TS_LOCAL; }
                                    default {
                                        switch ((t.flags `& TS_LOCAL) != 0)
                                        {
                                            case (true) { t.flags = t.flags - TS_LOCAL; }
                                            default {};
                                        };
                                    };
                                };
                            }
                                default {};
                            };
                            switch (sign_explicit)
                            {
                                case (true) {
                                switch (is_signed)
                                {
                                    case (true) { t.flags = t.flags `| TS_SIGNED; }
                                    default {
                                        switch ((t.flags `& TS_SIGNED) != 0)
                                        {
                                            case (true) { t.flags = t.flags - TS_SIGNED; }
                                            default {};
                                        };
                                    };
                                };
                            }
                                default {};
                            };
                            switch (alias_arr)
                            {
                                case (true) {
                                // Use-site dimensions come first, then the alias dimensions
                                NodeVec* nd = nv_new();
                                int di;
                                switch (is_array)
                                {
                                    case (true) {
                                    while (di < dims.len)
                                    {
                                        nv_push(nd, dims.items[di]);
                                        di++;
                                    };
                                    dims.len = 0;
                                    nv_free(dims);
                                }
                                    default {};
                                };
                                switch (rs.array_dims != (NodeVec*)0)
                                {
                                    case (true) {
                                    di = 0;
                                    while (di < rs.array_dims.len)
                                    {
                                        nv_push(nd, node_clone(rs.array_dims.items[di]));
                                        di++;
                                    };
                                }
                                    default {};
                                };
                                t.flags = t.flags `| TS_ARRAY;
                                t.array_dims = nd;
                                switch (nd.len > 0)
                                {
                                    case (true) { t.array_size = nd.items[0]; }
                                    default {};
                                };
                                switch (rs.array_elem != (TypeSpec*)0)
                                {
                                    case (true) { t.array_elem = typespec_copy(rs.array_elem); }
                                    default {
                                    TypeSpec* ael = typespec_new();
                                    this.copy_scalar_type(ael, t);
                                    ael.flags = ael.flags `& (TS_SIGNED `| TS_CONST `| TS_VOLATILE);
                                    ael.pointer_depth = 0;
                                    t.array_elem = ael;
                                };
                                };
                            }
                                default {
                                    switch (is_array)
                                    {
                                        case (true) {
                                t.flags = t.flags `| TS_ARRAY;
                                t.array_dims = dims;
                                t.array_size = dims.items[0];
                                TypeSpec* el = typespec_new();
                                this.copy_scalar_type(el, t);
                                el.flags = el.flags `& (TS_SIGNED `| TS_CONST `| TS_VOLATILE);
                                el.pointer_depth = 0;
                                t.array_elem = el;
                            }
                                        default {};
                                    };
                                };
                            };
                            switch (pdepth > 0)
                            {
                                case (true) {
                                t.flags = t.flags `| TS_POINTER;
                                t.pointer_depth = t.pointer_depth + pdepth;
                            }
                                default {};
                            };
                            -> t;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };

                switch (t.base_type == DataType.BYTE & t.bit_width < 0)
                {
                    case (true) {
                    t.bit_width = this.default_byte_width;
                    switch (t.alignment < 0)
                    {
                        case (true) { t.alignment = t.bit_width; }
                        default {};
                    };
                }
                    default {};
                };
                switch (nofunc)
                {
                    case (true) { t.flags = t.flags `| TS_NO_FUNCTIONS; }
                    default {};
                };
                switch (is_array)
                {
                    case (true) {
                    t.flags = t.flags `| TS_ARRAY;
                    t.array_dims = dims;
                    t.array_size = dims.items[0];
                    TypeSpec* e = typespec_new();
                    e.base_type = t.base_type;
                    e.flags = t.flags `& (TS_SIGNED `| TS_CONST `| TS_VOLATILE);
                    e.bit_width = t.bit_width;
                    e.alignment = t.alignment;
                    e.endianness = t.endianness;
                    e.storage_class = t.storage_class;
                    e.custom_typename = t.custom_typename;
                    t.array_elem = e;
                }
                    default {};
                };
                switch (pdepth > 0)
                {
                    case (true) {
                    t.flags = t.flags `| TS_POINTER;
                    t.pointer_depth = pdepth;
                }
                    default {};
                };
                -> t;
            };

            // ===== EXPRESSIONS =====

            // Token types that can start an operand. Used to detect a missing operator.
            starts_operand() -> bool -> this.expect4(TokenType.IDENTIFIER, TokenType.SINT_LITERAL, TokenType.UINT_LITERAL, TokenType.SLONG_LITERAL) | this.expect4(TokenType.ULONG_LITERAL, TokenType.FLOAT, TokenType.DOUBLE, TokenType.CHAR) | this.expect4(TokenType.STRING_LITERAL, TokenType.F_STRING, TokenType.G_STRING, TokenType.I_STRING) | this.expect4(TokenType.TRUE, TokenType.FALSE, TokenType.VOID, TokenType.THIS) | this.expect4(TokenType.NO_INIT, TokenType.LEFT_PAREN, TokenType.LEFT_BRACKET, TokenType.ELLIPSIS);

            error_missing_operator() -> void -> this.error(this.cat2(this.cat2(g"Unexpected '\0", this.cur_value()), g"' in expression - missing operator before this token?\0"));

            // expression -> assignment_expression
            expression() -> Node* -> this.assignment_expression();

            is_compound_assign() -> bool -> this.expect4(TokenType.PLUS_ASSIGN, TokenType.MINUS_ASSIGN, TokenType.MULTIPLY_ASSIGN, TokenType.DIVIDE_ASSIGN) | this.expect4(TokenType.MODULO_ASSIGN, TokenType.EXPONENT_ASSIGN, TokenType.XOR_ASSIGN, TokenType.BITXOR_ASSIGN) | this.expect4(TokenType.BITXNOR_ASSIGN, TokenType.BITSHIFT_LEFT_ASSIGN, TokenType.BITSHIFT_RIGHT_ASSIGN, TokenType.BITAND_ASSIGN) | this.expect4(TokenType.BITOR_ASSIGN, TokenType.BITNAND_ASSIGN, TokenType.BITNOR_ASSIGN, TokenType.OR_ASSIGN) | this.expect(TokenType.AND_ASSIGN);

            // assignment_expression -> ternary (('=' | op= | '@=' | '?=') assignment_expression)?
            assignment_expression() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* expr = this.ternary_expression();
                switch (this.failed)
                {
                    case (true) { -> expr; }
                    default {};
                };
                Node* n;
                Node* value;
                switch (this.expect(TokenType.ASSIGN))
                {
                    case (true) {
                    this.advance();
                    switch (this.expect(TokenType.DITTO))
                    {
                        case (true) {
                        this.advance();
                        Node* prev = this.last_stmt;
                        switch (prev == (Node*)0)
                        {
                            case (true) {
                            this.error(g"Ditto in assignment: no preceding statement to repeat\0");
                            -> expr;
                        }
                            default {};
                        };
                        Node* inner = prev;
                        switch (prev.kind == NodeKind.EXPRESSION_STATEMENT)
                        {
                            case (true) { inner = prev.a; }
                            default {};
                        };
                        switch (inner == (Node*)0)
                        {
                            case (true) {
                            this.error(g"Ditto in assignment: preceding statement is not an assignment\0");
                            -> expr;
                        }
                            default {};
                        };
                        switch (inner.kind != NodeKind.ASSIGNMENT)
                        {
                            case (true) {
                            this.error(g"Ditto in assignment: preceding statement is not an assignment\0");
                            -> expr;
                        }
                            default {};
                        };
                        value = node_clone(inner.b);
                    }
                        default {
                        value = this.assignment_expression();
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                    };
                    };
                    n = this.mk(NodeKind.ASSIGNMENT, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n.a = expr;
                    n.b = value;
                    -> n;
                }
                    default {};
                };
                switch (this.is_compound_assign())
                {
                    case (true) {
                    int optok = this.cur();
                    this.advance();
                    value = this.assignment_expression();
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n = this.mk(NodeKind.COMPOUND_ASSIGNMENT, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n.op = optok;
                    n.a = expr;
                    n.b = value;
                    -> n;
                }
                    default {};
                };
                switch (this.expect(TokenType.ADDRESS_ASSIGN))
                {
                    case (true) {
                    int al = this.cur_line();
                    int ac = this.cur_col();
                    this.advance();
                    Node* rhs = this.assignment_expression();
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    Node* addr = this.mk(NodeKind.ADDRESS_OF, al, ac);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    addr.a = rhs;
                    n = this.mk(NodeKind.ASSIGNMENT, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n.a = expr;
                    n.b = addr;
                    -> n;
                }
                    default {};
                };
                switch (this.expect(TokenType.TERNARY_ASSIGN))
                {
                    case (true) {
                    this.advance();
                    value = this.assignment_expression();
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n = this.mk(NodeKind.TERNARY_ASSIGN, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n.a = expr;
                    n.b = value;
                    -> n;
                }
                    default {};
                };
                -> expr;
            };

            // ternary_expression -> null_coalesce ('?' expression ':' ternary)?
            ternary_expression() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* expr = this.null_coalesce_expression();
                switch (this.failed)
                {
                    case (true) { -> expr; }
                    default {};
                };
                switch (this.expect(TokenType.QUESTION))
                {
                    case (true) {
                    this.advance();
                    Node* t = this.expression();
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    switch (!this.consume(TokenType.COLON))
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    Node* f = this.ternary_expression();
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    Node* n = this.mk(NodeKind.TERNARY_OP, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n.a = expr;
                    n.b = t;
                    n.c = f;
                    -> n;
                }
                    default {};
                };
                -> expr;
            };

            // null_coalesce_expression -> logical_or ('??' null_coalesce)?
            null_coalesce_expression() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* expr = this.bin_level(0);
                switch (this.failed)
                {
                    case (true) { -> expr; }
                    default {};
                };
                switch (this.expect(TokenType.NULL_COALESCE))
                {
                    case (true) {
                    this.advance();
                    Node* r = this.null_coalesce_expression();
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    Node* n = this.mk(NodeKind.NULL_COALESCE, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n.a = expr;
                    n.b = r;
                    -> n;
                }
                    default {};
                };
                -> expr;
            };

            // Operator at the current token for left associative level lv, or -1.
            //   0 or   1 and   2 xor   3 bitor   4 bitxor   5 bitand
            //   6 relational   7 shift   8 additive   9 multiplicative
            bin_match(int lv) -> int
            {
                int c = this.cur();
                switch (lv == 9 & this.cop_mask != 0)
                {
                    case (true) {
                    switch (this.cop_right_here())
                    {
                        case (true) { -> -1; }
                        default {};
                    };
                }
                    default {};
                };
                switch (lv)
                {
                    case (0) { switch (c == TokenType.LOGICAL_OR | c == TokenType.OR)
 {
     case (true) { -> Operator.OR; }
     default {};
 }; }
                    case (1) { switch (c == TokenType.LOGICAL_AND | c == TokenType.AND)
 {
     case (true) { -> Operator.AND; }
     default {};
 }; }
                    case (2) { switch (c == TokenType.XOR_OP | c == TokenType.XOR)
 {
     case (true) { -> Operator.XOR; }
     default {};
 }; }
                    case (3)
                    {
                        switch (c == TokenType.BITOR_OP)
                        {
                            case (true) { -> Operator.BITOR; }
                            default {};
                        };
                        switch (c == TokenType.BITNOR_OP)
                        {
                            case (true) { -> Operator.BITNOR; }
                            default {};
                        };
                    }
                    case (4)
                    {
                        switch (c == TokenType.BITXOR_OP)
                        {
                            case (true) { -> Operator.BITXOR; }
                            default {};
                        };
                        switch (c == TokenType.BITXNOR)
                        {
                            case (true) { -> Operator.BITXNOR; }
                            default {};
                        };
                    }
                    case (5)
                    {
                        switch (c == TokenType.BITAND_OP)
                        {
                            case (true) { -> Operator.BITAND; }
                            default {};
                        };
                        switch (c == TokenType.BITNAND_OP)
                        {
                            case (true) { -> Operator.BITNAND; }
                            default {};
                        };
                    }
                    case (6)
                    {
                        switch (c == TokenType.LESS_THAN)
                        {
                            case (true) { -> Operator.LESS_THAN; }
                            default {};
                        };
                        switch (c == TokenType.LESS_EQUAL)
                        {
                            case (true) { -> Operator.LESS_EQUAL; }
                            default {};
                        };
                        switch (c == TokenType.GREATER_THAN)
                        {
                            case (true) { -> Operator.GREATER_THAN; }
                            default {};
                        };
                        switch (c == TokenType.GREATER_EQUAL)
                        {
                            case (true) { -> Operator.GREATER_EQUAL; }
                            default {};
                        };
                    }
                    case (7)
                    {
                        switch (c == TokenType.BITSHIFT_LEFT)
                        {
                            case (true) { -> Operator.BITSHIFT_LEFT; }
                            default {};
                        };
                        switch (c == TokenType.BITSHIFT_RIGHT)
                        {
                            case (true) { -> Operator.BITSHIFT_RIGHT; }
                            default {};
                        };
                    }
                    case (8)
                    {
                        switch (c == TokenType.PLUS)
                        {
                            case (true) { -> Operator.ADD; }
                            default {};
                        };
                        switch (c == TokenType.MINUS)
                        {
                            case (true) { -> Operator.SUB; }
                            default {};
                        };
                    }
                    case (9)
                    {
                        switch (c == TokenType.MULTIPLY)
                        {
                            case (true) { -> Operator.MUL; }
                            default {};
                        };
                        switch (c == TokenType.DIVIDE)
                        {
                            case (true) { -> Operator.DIV; }
                            default {};
                        };
                        switch (c == TokenType.MODULO)
                        {
                            case (true) { -> Operator.MOD; }
                            default {};
                        };
                        switch (c == TokenType.EXPONENT)
                        {
                            case (true) { -> Operator.POWER; }
                            default {};
                        };
                    }
                    default {};
                };
                -> -1;
            };

            // The operand parser one level tighter than lv
            bin_next(int lv) -> Node*
            {
                switch (lv < 5)
                {
                    case (true) { -> this.bin_level(lv + 1); }
                    default {};
                };
                switch (lv == 5)
                {
                    case (true) { -> this.equality_expression(); }
                    default {};
                };
                switch (lv == 6)
                {
                    case (true) { -> this.bin_level(7); }
                    default {};
                };
                switch (lv == 7)
                {
                    case (true) { -> this.range_expression(); }
                    default {};
                };
                switch (lv == 8)
                {
                    case (true) { -> this.custom_op_expression(); }
                    default {};
                };
                -> this.cast_expression();
            };

            // One left associative binary level
            bin_level(int lv) -> Node*
            {
                Node* expr = this.bin_next(lv);
                switch (this.failed)
                {
                    case (true) { -> expr; }
                    default {};
                };
                int op = this.bin_match(lv);
                Node* right;
                Node* n;
                int line, col;
                while (op >= 0)
                {
                    line = this.cur_line();
                    col = this.cur_col();
                    this.advance();
                    right = this.bin_next(lv);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n = this.mk(NodeKind.BINARY_OP, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n.op = op;
                    n.a = expr;
                    n.b = right;
                    expr = n;
                    this.try_template_op(n);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    op = this.bin_match(lv);
                };
                switch (lv >= 8 & this.starts_operand() & !this.at_custom_op())
                {
                    case (true) {
                    this.error_missing_operator();
                }
                    default {};
                };
                -> expr;
            };

            // equality_expression -> chain (('==' | '!=' | 'is' | 'in' | '!in' | 'has') chain)*
            equality_expression() -> Node*
            {
                Node* expr = this.chain_expression();
                switch (this.failed)
                {
                    case (true) { -> expr; }
                    default {};
                };
                Node* n;
                Node* r;
                int line, col, c;
                while (true)
                {
                    line = this.cur_line();
                    col = this.cur_col();
                    c = this.cur();
                    switch (c == TokenType.NOT & this.type_at(1) == TokenType.IN)
                    {
                        case (true) {
                        this.advance();
                        this.advance();
                        r = this.chain_expression();
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        n = this.mk(NodeKind.IN_EXPRESSION, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        n.flags = NF_NEGATED;
                        n.a = expr;
                        n.b = r;
                        expr = n;
                        continue;
                    }
                        default {};
                    };
                    switch (c == TokenType.IN)
                    {
                        case (true) {
                        this.advance();
                        r = this.chain_expression();
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        n = this.mk(NodeKind.IN_EXPRESSION, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        n.a = expr;
                        n.b = r;
                        expr = n;
                    }
                        default {
                            switch (c == TokenType.HAS)
                            {
                                case (true) {
                        this.advance();
                        switch (!this.expect(TokenType.IDENTIFIER))
                        {
                            case (true) {
                            this.error(g"Expected trait name after 'has'\0");
                            -> expr;
                        }
                            default {};
                        };
                        n = this.mk(NodeKind.HAS_EXPRESSION, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        n.text = this.cur_value();
                        this.advance();
                        n.a = expr;
                        expr = n;
                    }
                                default {
                                    switch (c == TokenType.IS | c == TokenType.EQUAL | c == TokenType.NOT_EQUAL)
                                    {
                                        case (true) {
                        this.advance();
                        r = this.chain_expression();
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        n = this.mk(NodeKind.BINARY_OP, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        switch (c)
                        {
                            case (TokenType.NOT_EQUAL) { n.op = Operator.NOT_EQUAL; }
                            default { n.op = Operator.EQUAL; };
                        };
                        n.a = expr;
                        n.b = r;
                        expr = n;
                        this.try_template_op(n);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                    }
                                        default { break; };
                                    };
                                };
                            };
                        };
                    };
                };
                -> expr;
            };

            // chain_expression -> relational ('<-' chain)?   (right is pushed to the call's front)
            chain_expression() -> Node*
            {
                Node* expr = this.bin_level(6);
                switch (this.failed)
                {
                    case (true) { -> expr; }
                    default {};
                };
                switch (this.expect(TokenType.CHAIN_ARROW))
                {
                    case (true) {
                    this.advance();
                    Node* right = this.chain_expression();
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    switch (expr.kind != NodeKind.FUNCTION_CALL)
                    {
                        case (true) {
                        this.error(g"Chain arrow requires function call on left side\0");
                        -> expr;
                    }
                        default {};
                    };
                    NodeVec* args = node_list(expr, 0);
                    nv_push(args, right);
                    int i = args.len - 1;
                    while (i > 0)
                    {
                        args.items[i] = args.items[i - 1];
                        i--;
                    };
                    args.items[0] = right;
                    -> expr;
                }
                    default {};
                };
                -> expr;
            };

            // range_expression -> arithmetic ('..' arithmetic)?
            range_expression() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* expr = this.bin_level(8);
                switch (this.failed)
                {
                    case (true) { -> expr; }
                    default {};
                };
                switch (this.expect(TokenType.RANGE))
                {
                    case (true) {
                    this.advance();
                    Node* end = this.bin_level(8);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    Node* n = this.mk(NodeKind.RANGE_EXPRESSION, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n.a = expr;
                    n.b = end;
                    -> n;
                }
                    default {};
                };
                -> expr;
            };

            // Speculative parse of '(' type_spec ')' unary. Returns null when it is not a cast.
            try_cast() -> Node*
            {
                int m = this.mark();
                int line = this.cur_line();
                int col = this.cur_col();
                this.advance();
                TypeSpec* ts = this.type_spec();
                switch (!this.failed & this.expect(TokenType.RIGHT_PAREN))
                {
                    case (true) {
                    this.advance();
                    Node* inner = this.cast_expression();
                    switch (!this.failed)
                    {
                        case (true) {
                        Node* n = this.mk(NodeKind.CAST_EXPRESSION, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> (Node*)0; }
                            default {};
                        };
                        n.ts = ts;
                        n.a = inner;
                        -> n;
                    }
                        default {};
                    };
                }
                    default {};
                };
                typespec_free(ts);
                this.clear_error();
                this.reset(m);
                -> (Node*)0;
            };

            // cast_expression -> ('(' type_spec ')')? unary_expression
            cast_expression() -> Node*
            {
                switch (this.expect(TokenType.LEFT_PAREN))
                {
                    case (true) {
                    Node* c = this.try_cast();
                    switch (c != (Node*)0)
                    {
                        case (true) { -> c; }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) { -> c; }
                        default {};
                    };
                }
                    default {};
                };
                -> this.unary_expression();
            };

            unary_node(int op, int line, int col, Node* operand) -> Node*
            {
                switch (this.failed)
                {
                    case (true) { -> operand; }
                    default {};
                };
                Node* n = this.mk(NodeKind.UNARY_OP, line, col);
                switch (this.failed)
                {
                    case (true) { -> operand; }
                    default {};
                };
                n.op = op;
                n.a = operand;
                -> n;
            };

            unary_expression() -> Node*
            {
                int c = this.cur();
                int line = this.cur_line();
                int col = this.cur_col();
                Node* operand;
                Node* n;
                int op = -1;
                bool via_cast = false;

                switch (c)
                {
                    case (TokenType.IS) { op = Operator.EQUAL; }
                    case (TokenType.NOT) { op = Operator.NOT; }
                    case (TokenType.BITNOT_OP) { op = Operator.BITNOT; }
                    case (TokenType.BITXNOT) { op = Operator.BITXNOT; }
                    case (TokenType.BITXNAND) { op = Operator.BITXNAND; }
                    case (TokenType.BITXNOR) { op = Operator.BITXNOR; }
                    case (TokenType.INCREMENT) { op = Operator.INCREMENT; }
                    case (TokenType.DECREMENT) { op = Operator.DECREMENT; }
                    case (TokenType.MINUS) { op = Operator.SUB; via_cast = true; }
                    case (TokenType.PLUS) { op = Operator.ADD; via_cast = true; }
                    default {};
                };

                switch (op >= 0)
                {
                    case (true) {
                    this.advance();
                    switch (via_cast)
                    {
                        case (true) { operand = this.cast_expression(); }
                        default { operand = this.unary_expression(); };
                    };
                    -> this.unary_node(op, line, col, operand);
                }
                    default {};
                };
                switch (c == TokenType.MULTIPLY)
                {
                    case (true) {
                    this.advance();
                    operand = this.cast_expression();
                    switch (this.failed)
                    {
                        case (true) { -> operand; }
                        default {};
                    };
                    n = this.mk(NodeKind.POINTER_DEREF, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> operand; }
                        default {};
                    };
                    n.a = operand;
                    -> n;
                }
                    default {};
                };
                switch (c == TokenType.ADDRESS_OF)
                {
                    case (true) {
                    this.advance();
                    operand = this.unary_expression();
                    switch (this.failed)
                    {
                        case (true) { -> operand; }
                        default {};
                    };
                    n = this.mk(NodeKind.ADDRESS_OF, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> operand; }
                        default {};
                    };
                    n.a = operand;
                    -> n;
                }
                    default {};
                };
                switch (c == TokenType.ADDRESS_CAST)
                {
                    case (true) {
                    this.advance();
                    operand = this.unary_expression();
                    switch (this.failed)
                    {
                        case (true) { -> operand; }
                        default {};
                    };
                    n = this.mk(NodeKind.CAST_EXPRESSION, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> operand; }
                        default {};
                    };
                    TypeSpec* vp = typespec_new();
                    vp.base_type = DataType.VOID;
                    vp.flags = TS_POINTER;
                    vp.pointer_depth = 1;
                    n.ts = vp;
                    n.a = operand;
                    -> n;
                }
                    default {};
                };
                Node* cu = this.custom_unary();
                switch (cu != (Node*)0 | this.failed)
                {
                    case (true) { -> cu; }
                    default {};
                };
                -> this.postfix_expression();
            };

            // argument_list -> expression (',' expression)*   (pushed onto holder.l0)
            // callee is the called name for ditto, or null.
            argument_list(Node* holder, byte* callee) -> void
            {
                Node* a;
                int pos;
                Node* prev;
                while (true)
                {
                    switch (callee != (byte*)0 & this.expect(TokenType.DITTO))
                    {
                        case (true) {
                        prev = this.last_call;
                        switch (prev == (Node*)0)
                        {
                            case (true) {
                            this.error(g"Ditto in argument list: previous statement is not a function call\0");
                            ->;
                        }
                            default {};
                        };
                        switch (prev.text != (byte*)0)
                        {
                            case (true) {
                            switch (!cstr_eq(prev.text, callee))
                            {
                                case (true) {
                                this.error(g"Ditto in argument list: previous call was to a different function\0");
                                ->;
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                        switch (pos >= node_count(prev, 0))
                        {
                            case (true) {
                            this.error(g"Ditto in argument list: argument position is out of range\0");
                            ->;
                        }
                            default {};
                        };
                        this.advance();
                        a = node_clone(node_child(prev, 0, pos));
                    }
                        default {
                        a = this.expression();
                        switch (this.failed)
                        {
                            case (true) { ->; }
                            default {};
                        };
                    };
                    };
                    node_push(holder, 0, a);
                    pos++;
                    switch (!this.expect(TokenType.COMMA))
                    {
                        case (true) { break; }
                        default {};
                    };
                    this.advance();
                };
                ->;
            };

            // Moves the arguments collected in holder into call.l0 and frees holder
            take_args(Node* call, Node* holder) -> void
            {
                call.l0 = holder.l0;
                holder.l0 = (NodeVec*)0;
                node_free(holder);
                ->;
            };

            // postfix_expression -> '~'? primary (index | call | '.' name | '++' | '--' | '!!' | as | from | if)*
            postfix_expression() -> Node*
            {
                int tl = 0;
                int tc = 0;
                bool tied = false;
                switch (this.expect(TokenType.TIE))
                {
                    case (true) {
                    tied = true;
                    tl = this.cur_line();
                    tc = this.cur_col();
                    this.advance();
                }
                    default {};
                };
                Node* expr = this.primary_expression();
                switch (this.failed)
                {
                    case (true) { -> expr; }
                    default {};
                };
                Node* n;
                switch (tied)
                {
                    case (true) {
                    n = this.mk(NodeKind.TIE_EXPRESSION, tl, tc);
                    switch (this.failed)
                    {
                        case (true) { -> expr; }
                        default {};
                    };
                    n.a = expr;
                    expr = n;
                }
                    default {};
                };

                // explicit foo<int>(x) or inferred foo(x) call of a template function
                expr = this.template_call(expr);
                switch (this.failed)
                {
                    case (true) { -> expr; }
                    default {};
                };
                -> this.postfix_from(expr);
            };

            // The postfix operator loop of postfix_expression, applied to an already parsed
            // operand. Member-assign blocks use it to continue '.a.b(args)' and '.a.b[i]' items.
            postfix_from(Node* expr) -> Node*
            {
                Node* n;
                COp* pc;
                int line, col;
                Node* idx;
                Node* end;
                Node* holder;
                Node* fill;
                byte* callee;
                byte* member;
                int pop;
                TypeSpec* target;
                Node* src;
                Node* cond;
                Node* els;
                byte* tkey;
                byte* qkey;
                Node* fsn;
                while (true)
                {
                    line = this.cur_line();
                    col = this.cur_col();
                    switch (this.expect(TokenType.LEFT_BRACKET))
                    {
                        case (true) {
                        this.advance();
                        switch (this.expect(TokenType.BACKTICK))
                        {
                            case (true) {
                            this.advance();
                            idx = this.expression();
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            switch (!this.consume(TokenType.RIGHT_BRACKET))
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n = this.mk(NodeKind.BIT_INDEX_ACCESS, line, col);
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n.a = expr;
                            n.b = idx;
                            expr = n;
                            continue;
                        }
                            default {};
                        };
                        idx = this.expression();
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        switch (this.expect(TokenType.BITSLICE))
                        {
                            case (true) {
                            this.advance();
                            end = this.expression();
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            switch (!this.consume(TokenType.RIGHT_BRACKET))
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n = this.mk(NodeKind.BIT_SLICE, line, col);
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n.a = expr;
                            n.b = idx;
                            n.c = end;
                            expr = n;
                        }
                            default {
                                switch (this.expect(TokenType.COLON))
                                {
                                    case (true) {
                            this.advance();
                            end = this.expression();
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            switch (!this.consume(TokenType.RIGHT_BRACKET))
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n = this.mk(NodeKind.ARRAY_SLICE, line, col);
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n.a = expr;
                            n.b = idx;
                            n.c = end;
                            expr = n;
                        }
                                    default {
                            switch (!this.consume(TokenType.RIGHT_BRACKET))
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            switch (idx.kind == NodeKind.RANGE_EXPRESSION & this.expect(TokenType.ASSIGN))
                            {
                                case (true) {
                                this.advance();
                                switch (!this.consume(TokenType.LEFT_BRACE))
                                {
                                    case (true) { -> expr; }
                                    default {};
                                };
                                fill = this.expression();
                                switch (this.failed)
                                {
                                    case (true) { -> expr; }
                                    default {};
                                };
                                switch (!this.consume(TokenType.RIGHT_BRACE))
                                {
                                    case (true) { -> expr; }
                                    default {};
                                };
                                n = this.mk(NodeKind.RANGE_ASSIGNMENT, line, col);
                                switch (this.failed)
                                {
                                    case (true) { -> expr; }
                                    default {};
                                };
                                n.a = expr;
                                n.b = idx.a;
                                n.c = idx.b;
                                n.d = fill;
                                idx.a = (Node*)0;
                                idx.b = (Node*)0;
                                node_free(idx);
                                expr = n;
                                break;
                            }
                                default {};
                            };
                            n = this.mk(NodeKind.ARRAY_ACCESS, line, col);
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n.a = expr;
                            n.b = idx;
                            expr = n;
                        };
                                };
                            };
                        };
                    }
                        default {
                            switch (this.expect(TokenType.LEFT_PAREN))
                            {
                                case (true) {
                        this.advance();
                        holder = this.mk(NodeKind.NODE_LIST, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        callee = (byte*)0;
                        switch (expr.kind == NodeKind.IDENTIFIER)
                        {
                            case (true) { callee = expr.text; }
                            default {};
                        };
                        switch (!this.expect(TokenType.RIGHT_PAREN))
                        {
                            case (true) {
                            this.argument_list(holder, callee);
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                        }
                            default {};
                        };
                        switch (!this.consume(TokenType.RIGHT_PAREN))
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        switch (expr.kind == NodeKind.IDENTIFIER)
                        {
                            case (true) {
                            // a defined macro name makes a macro invocation, not a function call
                            switch (nm_has(this.macros, expr.text))
                            {
                                case (true) { n = this.mk(NodeKind.MACRO_CALL, line, col); }
                                default { n = this.mk(NodeKind.FUNCTION_CALL, line, col); };
                            };
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n.text = expr.text;
                            this.take_args(n, holder);
                        }
                            default {
                                switch (expr.kind == NodeKind.STRING_LITERAL)
                                {
                                    case (true) {
                            n = this.mk(NodeKind.FUNCTION_CALL, line, col);
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n.text = expr.text;
                            this.take_args(n, holder);
                        }
                                    default {
                                        switch (expr.kind == NodeKind.F_STRING_LITERAL | expr.kind == NodeKind.STRINGIFY)
                                        {
                                            case (true) {
                            n = this.mk(NodeKind.FUNCTION_CALL, line, col);
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n.a = expr;
                            expr = (Node*)0;
                            this.take_args(n, holder);
                        }
                                            default {
                                                switch (expr.kind == NodeKind.MEMBER_ACCESS)
                                                {
                                                    case (true) {
                            n = (Node*)0;
                            switch (expr.text2 != (byte*)0)
                            {
                                case (true) { n = this.typefunc_call_implicit(expr, holder, line, col); }
                                default {};
                            };
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            switch (n != (Node*)0)
                            {
                                case (true) {
                                this.take_args(n, holder);
                                this.push_front(n, expr.a);
                                expr.a = (Node*)0;
                            }
                                default {
                                n = this.mk(NodeKind.METHOD_CALL, line, col);
                                switch (this.failed)
                                {
                                    case (true) { -> expr; }
                                    default {};
                                };
                                n.a = expr.a;
                                n.text = expr.text;
                                expr.a = (Node*)0;
                                this.take_args(n, holder);
                            };
                            };
                        }
                                                    default {
                            this.error(g"Cannot call function on complex expression\0");
                            -> expr;
                        };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                        switch (expr != (Node*)0)
                        {
                            case (true) { node_free(expr); }
                            default {};
                        };
                        expr = n;
                    }
                                default {
                                    switch (this.expect(TokenType.DOT))
                                    {
                                        case (true) {
                        this.advance();
                        member = (byte*)0;
                        switch (this.expect(TokenType.F_STRING) | this.expect(TokenType.I_STRING))
                        {
                            case (true) {
                            fsn = this.fstr_node();
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            member = this.fstr_resolve(fsn);
                            node_free(fsn);
                            switch (member == (byte*)0)
                            {
                                case (true) {
                                this.error(g"The member name could not be resolved at parse time\0");
                                -> expr;
                            }
                                default {};
                            };
                        }
                            default {
                                switch (this.expect(TokenType.STRING_LITERAL))
                                {
                                    case (true) {
                            member = this.cur_value();
                            this.advance();
                        }
                                    default {
                                        switch (this.expect(TokenType.TAG))
                                        {
                                            case (true) {
                            this.advance();
                            member = g"#\0";
                        }
                                            default {
                            switch (!this.expect(TokenType.IDENTIFIER))
                            {
                                case (true) {
                                this.fail_expected(TokenType.IDENTIFIER);
                                -> expr;
                            }
                                default {};
                            };
                            member = this.cur_value();
                            this.advance();
                        };
                                        };
                                    };
                                };
                            };
                        };
                        tkey = this.typefunc_key(expr, member);
                        switch (this.expect(TokenType.LESS_THAN))
                        {
                            case (true) {
                            qkey = (byte*)0;
                            switch (expr.kind == NodeKind.IDENTIFIER)
                            {
                                case (true) {
                                qkey = this.cat2(this.cat2(expr.text, g".\0"), member);
                                switch (this.template_lookup(qkey) == (TemplateEntry*)0)
                                {
                                    case (true) { qkey = (byte*)0; }
                                    default {};
                                };
                            }
                                default {};
                            };
                            switch (qkey != (byte*)0)
                            {
                                case (true) {
                                expr = this.template_method_explicit(expr, qkey, false);
                                switch (this.failed)
                                {
                                    case (true) { -> expr; }
                                    default {};
                                };
                                continue;
                            }
                                default {};
                            };
                            switch (tkey != (byte*)0)
                            {
                                case (true) {
                                expr = this.template_method_explicit(expr, tkey, true);
                                switch (this.failed)
                                {
                                    case (true) { -> expr; }
                                    default {};
                                };
                                continue;
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                        n = this.mk(NodeKind.MEMBER_ACCESS, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        n.a = expr;
                        n.text = member;
                        switch (tkey != (byte*)0 & this.expect(TokenType.LEFT_PAREN))
                        {
                            case (true) { n.text2 = tkey; }
                            default {};
                        };
                        expr = n;
                    }
                                        default {
                                            switch (this.expect(TokenType.INCREMENT) | this.expect(TokenType.DECREMENT))
                                            {
                                                case (true) {
                        pop = Operator.INCREMENT;
                        switch (this.expect(TokenType.DECREMENT))
                        {
                            case (true) { pop = Operator.DECREMENT; }
                            default {};
                        };
                        this.advance();
                        n = this.unary_node(pop, line, col, expr);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        n.flags = NF_POSTFIX;
                        expr = n;
                    }
                                                default {
                                                    switch (this.expect(TokenType.NOT_NULL))
                                                    {
                                                        case (true) {
                        this.advance();
                        n = this.mk(NodeKind.NOT_NULL, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        n.a = expr;
                        expr = n;
                    }
                                                        default {
                                                            switch (this.expect(TokenType.AS))
                                                            {
                                                                case (true) {
                        this.advance();
                        target = this.type_spec();
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        switch (target.custom_typename != (byte*)0)
                        {
                            case (true) {
                            n = this.mk(NodeKind.STRUCT_RECAST, line, col);
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n.text = target.custom_typename;
                            n.a = expr;
                            typespec_free(target);
                        }
                            default {
                            n = this.mk(NodeKind.CAST_EXPRESSION, line, col);
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                            n.ts = target;
                            n.a = expr;
                        };
                        };
                        expr = n;
                    }
                                                                default {
                                                                    switch (this.expect(TokenType.FROM))
                                                                    {
                                                                        case (true) {
                        this.advance();
                        src = this.postfix_expression();
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        switch (expr.kind != NodeKind.IDENTIFIER)
                        {
                            case (true) {
                            this.error(g"Expected struct type name before 'from' keyword\0");
                            -> expr;
                        }
                            default {};
                        };
                        n = this.mk(NodeKind.STRUCT_RECAST, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        n.text = expr.text;
                        n.a = src;
                        node_free(expr);
                        expr = n;
                    }
                                                                        default {
                                                                            switch (this.expect(TokenType.IF))
                                                                            {
                                                                                case (true) {
                        this.advance();
                        switch (!this.consume(TokenType.LEFT_PAREN))
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        cond = this.expression();
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        switch (!this.consume(TokenType.RIGHT_PAREN))
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        els = (Node*)0;
                        switch (this.expect(TokenType.ELSE))
                        {
                            case (true) {
                            this.advance();
                            els = this.postfix_expression();
                            switch (this.failed)
                            {
                                case (true) { -> expr; }
                                default {};
                            };
                        }
                            default {};
                        };
                        n = this.mk(NodeKind.IF_EXPRESSION, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        n.a = expr;
                        n.b = cond;
                        n.c = els;
                        expr = n;
                    }
                                                                                default {
                        pc = this.cop_best(3);
                        switch (pc == (COp*)0)
                        {
                            case (true) { break; }
                            default {};
                        };
                        n = this.op_call(pc.func, this.cur_line(), this.cur_col());
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        this.skip_tokens(pc.left.n);
                        node_push(n, 0, expr);
                        expr = n;
                    };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
                -> expr;
            };

            // Literal node of a data type at the current token position
            lit(int dt, i64 v, int line, int col) -> Node*
            {
                Node* n = this.mk(NodeKind.LITERAL, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                n.op = dt;
                n.ival = v;
                -> n;
            };

            // Integer literal of the current token
            int_literal(int dt) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                bool ok;
                i64 v = this.parse_int(this.cur_value(), @ok);
                switch (!ok)
                {
                    case (true) {
                    this.error(g"Invalid integer literal\0");
                    -> (Node*)0;
                }
                    default {};
                };
                Node* n = this.lit(dt, v, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                n.text = this.cur_value();
                this.advance();
                -> n;
            };

            is_type_start_kw() -> bool -> this.expect4(TokenType.SINT, TokenType.FLOAT_KW, TokenType.DOUBLE_KW, TokenType.CHAR) | this.expect4(TokenType.BOOL_KW, TokenType.DATA, TokenType.VOID, TokenType.SLONG) | this.expect4(TokenType.ULONG, TokenType.CONST, TokenType.VOLATILE, TokenType.SIGNED) | this.expect(TokenType.UNSIGNED);

            // '(' already consumed. Parses a type then ')', or an expression then ')'.
            // want_type_first picks which form is tried first; the other is the fallback.
            // allow_ident_type makes a leading identifier try the type form first too (endianof).
            type_or_expr(int kind, int line, int col, bool type_first) -> Node*
            {
                Node* n = this.mk(kind, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                int m = this.mark();
                int pass;
                bool as_type;
                TypeSpec* ts;
                Node* e;
                while (pass < 2)
                {
                    as_type = type_first;
                    switch (pass == 1)
                    {
                        case (true) { as_type = !type_first; }
                        default {};
                    };
                    switch (as_type)
                    {
                        case (true) {
                        ts = this.type_spec();
                        switch (!this.failed & this.expect(TokenType.RIGHT_PAREN))
                        {
                            case (true) {
                            this.advance();
                            n.ts = ts;
                            -> n;
                        }
                            default {};
                        };
                        switch (!this.failed)
                        {
                            case (true) { this.fail_expected(TokenType.RIGHT_PAREN); }
                            default {};
                        };
                        typespec_free(ts);
                    }
                        default {
                        e = this.expression();
                        switch (!this.failed & this.expect(TokenType.RIGHT_PAREN))
                        {
                            case (true) {
                            this.advance();
                            n.a = e;
                            -> n;
                        }
                            default {};
                        };
                        switch (!this.failed)
                        {
                            case (true) { this.fail_expected(TokenType.RIGHT_PAREN); }
                            default {};
                        };
                        node_free(e);
                    };
                    };
                    switch (pass == 0)
                    {
                        case (true) {
                        this.clear_error();
                        this.reset(m);
                    }
                        default {};
                    };
                    pass++;
                };
                -> n;
            };

            // sizeof / alignof / endianof / typeof '(' (type | expression) ')'
            type_query(int kind, int kw) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.advance();
                switch (!this.consume(TokenType.LEFT_PAREN))
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                bool type_first;
                switch (kind)
                {
                    case (NodeKind.ALIGN_OF) { type_first = true; }
                    case (NodeKind.ENDIAN_OF)
                    {
                        type_first = this.is_type_start_kw() | this.expect(TokenType.IDENTIFIER);
                    }
                    default { type_first = this.is_type_start_kw(); };
                };
                -> this.type_or_expr(kind, line, col, type_first);
            };

            array_literal() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.advance();
                Node* n;
                switch (this.expect(TokenType.RIGHT_BRACKET))
                {
                    case (true) {
                    this.advance();
                    -> this.mk(NodeKind.ARRAY_LITERAL, line, col);
                }
                    default {};
                };
                Node* first = this.expression();
                switch (this.failed)
                {
                    case (true) { -> first; }
                    default {};
                };
                switch (this.expect(TokenType.FOR))
                {
                    case (true) {
                    this.advance();
                    switch (!this.consume(TokenType.LEFT_PAREN))
                    {
                        case (true) { -> first; }
                        default {};
                    };
                    TypeSpec* vt = this.type_spec();
                    switch (this.failed)
                    {
                        case (true) { -> first; }
                        default {};
                    };
                    switch (!this.expect(TokenType.IDENTIFIER))
                    {
                        case (true) {
                        this.fail_expected(TokenType.IDENTIFIER);
                        -> first;
                    }
                        default {};
                    };
                    byte* vname = this.cur_value();
                    this.advance();
                    switch (!this.consume(TokenType.IN))
                    {
                        case (true) { -> first; }
                        default {};
                    };
                    Node* iter = this.expression();
                    switch (this.failed)
                    {
                        case (true) { -> first; }
                        default {};
                    };
                    switch (!this.consume(TokenType.RIGHT_PAREN))
                    {
                        case (true) { -> first; }
                        default {};
                    };
                    switch (!this.consume(TokenType.RIGHT_BRACKET))
                    {
                        case (true) { -> first; }
                        default {};
                    };
                    n = this.mk(NodeKind.ARRAY_COMPREHENSION, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> first; }
                        default {};
                    };
                    n.a = first;
                    n.text = vname;
                    n.ts = vt;
                    n.b = iter;
                    -> n;
                }
                    default {};
                };
                n = this.mk(NodeKind.ARRAY_LITERAL, line, col);
                switch (this.failed)
                {
                    case (true) { -> first; }
                    default {};
                };
                node_push(n, 0, first);
                Node* e;
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    e = this.expression();
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    node_push(n, 0, e);
                };
                switch (!this.consume(TokenType.RIGHT_BRACKET))
                {
                    case (true) { -> n; }
                    default {};
                };
                -> n;
            };

            // struct_literal -> '{' (name '=' expr (',' name '=' expr)* | expr (',' expr)*)? '}'
            struct_literal() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.advance();
                Node* n = this.mk(NodeKind.STRUCT_LITERAL, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                Node* nm;
                Node* v;
                switch (!this.expect(TokenType.RIGHT_BRACE))
                {
                    case (true) {
                    switch (this.expect(TokenType.IDENTIFIER) & this.type_at(1) == TokenType.ASSIGN)
                    {
                        case (true) {
                        while (true)
                        {
                            switch (!this.expect(TokenType.IDENTIFIER))
                            {
                                case (true) {
                                this.fail_expected(TokenType.IDENTIFIER);
                                -> n;
                            }
                                default {};
                            };
                            nm = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                            switch (this.failed)
                            {
                                case (true) { -> n; }
                                default {};
                            };
                            nm.text = this.cur_value();
                            this.advance();
                            switch (!this.consume(TokenType.ASSIGN))
                            {
                                case (true) { -> n; }
                                default {};
                            };
                            v = this.expression();
                            switch (this.failed)
                            {
                                case (true) { -> n; }
                                default {};
                            };
                            node_push(n, 0, nm);
                            node_push(n, 1, v);
                            switch (!this.expect(TokenType.COMMA))
                            {
                                case (true) { break; }
                                default {};
                            };
                            this.advance();
                        };
                    }
                        default {
                        while (true)
                        {
                            v = this.expression();
                            switch (this.failed)
                            {
                                case (true) { -> n; }
                                default {};
                            };
                            node_push(n, 2, v);
                            switch (!this.expect(TokenType.COMMA))
                            {
                                case (true) { break; }
                                default {};
                            };
                            this.advance();
                        };
                    };
                    };
                }
                    default {};
                };
                this.consume(TokenType.RIGHT_BRACE);
                -> n;
            };

            // d{ key : value, ... }
            dict_literal() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.advance();
                Node* n = this.mk(NodeKind.DICT_LITERAL_EXPR, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                Node* k;
                Node* v;
                while (!this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        -> n;
                    }
                        default {};
                    };
                    k = this.expression();
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    switch (!this.consume(TokenType.COLON))
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    v = this.expression();
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    node_push(n, 0, k);
                    node_push(n, 1, v);
                    switch (this.expect(TokenType.COMMA))
                    {
                        case (true) { this.advance(); }
                        default {};
                    };
                };
                this.consume(TokenType.RIGHT_BRACE);
                -> n;
            };

            // IDENTIFIER ('::' IDENTIFIER)*, joined with "__"
            scoped_identifier() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                byte* name = this.cur_value();
                this.advance();
                while (this.expect(TokenType.SCOPE))
                {
                    this.advance();
                    switch (!this.expect(TokenType.IDENTIFIER))
                    {
                        case (true) {
                        this.fail_expected(TokenType.IDENTIFIER);
                        -> (Node*)0;
                    }
                        default {};
                    };
                    name = this.cat2(this.cat2(name, g"__\0"), this.cur_value());
                    this.advance();
                };
                Node* n = this.mk(NodeKind.IDENTIFIER, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                n.text = name;
                -> n;
            };

            // '$' name ('.' member)? | '$' type-keyword
            stringify_expr() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                int nx = this.type_at(1);
                bool valid = nx == TokenType.IDENTIFIER | nx == TokenType.CODIFY | nx == TokenType.DOT | nx == TokenType.TAG |
                             nx == TokenType.SINT | nx == TokenType.UINT | nx == TokenType.SLONG | nx == TokenType.ULONG |
                             nx == TokenType.FLOAT_KW | nx == TokenType.DOUBLE_KW | nx == TokenType.BOOL_KW | nx == TokenType.BYTE;
                switch (!valid)
                {
                    case (true) {
                    this.error_unexpected();
                    -> (Node*)0;
                }
                    default {};
                };
                this.advance();
                Node* n;
                switch (this.expect(TokenType.CODIFY))
                {
                    case (true) {
                    // $~$expr: the codify result becomes the stringified name
                    byte* resolved = this.consume_codify();
                    switch (this.failed)
                    {
                        case (true) { -> (Node*)0; }
                        default {};
                    };
                    n = this.mk(NodeKind.STRING_LITERAL, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    n.text = resolved;
                    n.op = -1;
                    -> n;
                }
                    default {};
                };
                byte* kw = (byte*)0;
                int c = this.cur();
                switch (c)
                {
                    case (TokenType.SINT) { kw = g"int\0"; }
                    case (TokenType.UINT) { kw = g"uint\0"; }
                    case (TokenType.SLONG) { kw = g"long\0"; }
                    case (TokenType.ULONG) { kw = g"ulong\0"; }
                    case (TokenType.FLOAT_KW) { kw = g"float\0"; }
                    case (TokenType.DOUBLE_KW) { kw = g"double\0"; }
                    case (TokenType.BOOL_KW) { kw = g"bool\0"; }
                    case (TokenType.BYTE) { kw = g"byte\0"; }
                    default {};
                };
                switch (kw != (byte*)0)
                {
                    case (true) {
                    this.advance();
                    n = this.mk(NodeKind.STRING_LITERAL, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    n.text = kw;
                    n.op = -1;
                    -> n;
                }
                    default {};
                };
                switch (!this.expect(TokenType.IDENTIFIER))
                {
                    case (true) {
                    this.error(g"Expected identifier after '$'\0");
                    -> (Node*)0;
                }
                    default {};
                };
                n = this.mk(NodeKind.STRINGIFY, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                n.text = this.cur_value();
                this.advance();
                switch (this.expect(TokenType.DOT))
                {
                    case (true) {
                    this.advance();
                    switch (this.expect(TokenType.IDENTIFIER))
                    {
                        case (true) {
                        n.text2 = this.cur_value();
                        this.advance();
                    }
                        default {
                            switch (this.expect(TokenType.TAG))
                            {
                                case (true) {
                        this.advance();
                        n.text2 = g"#\0";
                    }
                                default {
                        this.error(g"Expected member name after '.' in stringify expression\0");
                        -> n;
                    };
                            };
                        };
                    };
                }
                    default {};
                };
                -> n;
            };

            // primary_expression -> literal | identifier | '(' expression ')' | literals of arrays, structs, dicts | queries
            primary_expression() -> Node*
            {
                int c = this.cur();
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n;
                bool ok;

                switch (this.vop_sym != (OpSym*)0)
                {
                    case (true) {
                    switch (this.opsym_match(this.vop_sym))
                    {
                        case (true) {
                        n = this.mk(NodeKind.IDENTIFIER, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> n; }
                            default {};
                        };
                        n.text = g"__op_count\0";
                        this.skip_tokens(this.vop_sym.n);
                        -> n;
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (c == TokenType.IDENTIFIER)
                {
                    case (true) { -> this.scoped_identifier(); }
                    default {};
                };
                switch (c == TokenType.SINT_LITERAL)
                {
                    case (true) { -> this.int_literal(DataType.SINT); }
                    default {};
                };
                switch (c == TokenType.UINT_LITERAL)
                {
                    case (true) { -> this.int_literal(DataType.UINT); }
                    default {};
                };
                switch (c == TokenType.SLONG_LITERAL)
                {
                    case (true) { -> this.int_literal(DataType.SLONG); }
                    default {};
                };
                switch (c == TokenType.ULONG_LITERAL)
                {
                    case (true) { -> this.int_literal(DataType.ULONG); }
                    default {};
                };
                switch (c == TokenType.BYTE_LITERAL)
                {
                    case (true) { -> this.int_literal(DataType.BYTE); }
                    default {};
                };
                switch (c == TokenType.FLOAT | c == TokenType.DOUBLE)
                {
                    case (true) {
                    n = this.mk(NodeKind.LITERAL, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    switch (c)
                    {
                        case (TokenType.FLOAT) { n.op = DataType.FLOAT; }
                        default { n.op = DataType.DOUBLE; };
                    };
                    n.fval = this.parse_double(this.cur_value());
                    n.text = this.cur_value();
                    this.advance();
                    -> n;
                }
                    default {};
                };
                switch (c == TokenType.CHAR)
                {
                    case (true) {
                    n = this.mk(NodeKind.LITERAL, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    n.op = DataType.CHAR;
                    n.text = this.cur_value();
                    switch (this.toks[this.pos].numeric_char != 0)
                    {
                        case (true) { n.ival = this.parse_int(this.cur_value(), @ok); }
                        default {
                        byte* cv = this.cur_value();
                        n.ival = (i64)cv[0];
                    };
                    };
                    this.advance();
                    -> n;
                }
                    default {};
                };
                switch (c == TokenType.STRING_LITERAL | c == TokenType.G_STRING)
                {
                    case (true) {
                    n = this.mk(NodeKind.STRING_LITERAL, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    n.text = this.cur_value();
                    n.ival = (i64)this.cur_value_len();
                    n.op = -1;
                    switch (c == TokenType.G_STRING)
                    {
                        case (true) { n.op = StorageClass.GLOBAL; }
                        default {};
                    };
                    this.advance();
                    -> n;
                }
                    default {};
                };
                switch (c == TokenType.F_STRING)
                {
                    case (true) { -> this.f_string_node(); }
                    default {};
                };
                switch (c == TokenType.I_STRING)
                {
                    case (true) { -> this.i_string_node(); }
                    default {};
                };
                switch (c == TokenType.TRUE)
                {
                    case (true) { this.advance(); -> this.lit(DataType.BOOL, 1, line, col); }
                    default {};
                };
                switch (c == TokenType.FALSE)
                {
                    case (true) { this.advance(); -> this.lit(DataType.BOOL, 0, line, col); }
                    default {};
                };
                switch (c == TokenType.VOID)
                {
                    case (true) { this.advance(); -> this.lit(DataType.VOID, 0, line, col); }
                    default {};
                };
                switch (c == TokenType.THIS)
                {
                    case (true) {
                    n = this.mk(NodeKind.IDENTIFIER, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    n.text = g"this\0";
                    this.advance();
                    -> n;
                }
                    default {};
                };
                switch (c == TokenType.NO_INIT)
                {
                    case (true) {
                    this.advance();
                    -> this.mk(NodeKind.NO_INIT, line, col);
                }
                    default {};
                };
                switch (c == TokenType.LEFT_PAREN)
                {
                    case (true) {
                    this.advance();
                    n = this.expression();
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    this.consume(TokenType.RIGHT_PAREN);
                    -> n;
                }
                    default {};
                };
                switch (c == TokenType.LEFT_BRACKET)
                {
                    case (true) { -> this.array_literal(); }
                    default {};
                };
                switch (c == TokenType.ELLIPSIS)
                {
                    case (true) {
                    this.advance();
                    switch (!this.consume(TokenType.LEFT_BRACKET))
                    {
                        case (true) { -> (Node*)0; }
                        default {};
                    };
                    Node* ix = this.expression();
                    switch (this.failed)
                    {
                        case (true) { -> ix; }
                        default {};
                    };
                    switch (!this.consume(TokenType.RIGHT_BRACKET))
                    {
                        case (true) { -> ix; }
                        default {};
                    };
                    n = this.mk(NodeKind.VARIADIC_ACCESS, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> ix; }
                        default {};
                    };
                    n.a = ix;
                    -> n;
                }
                    default {};
                };
                switch (c == TokenType.DICT_LITERAL)
                {
                    case (true) { -> this.dict_literal(); }
                    default {};
                };
                switch (c == TokenType.LEFT_BRACE)
                {
                    case (true) { -> this.struct_literal(); }
                    default {};
                };
                switch (c == TokenType.SIZEOF)
                {
                    case (true) { -> this.type_query(NodeKind.SIZE_OF, c); }
                    default {};
                };
                switch (c == TokenType.ALIGNOF)
                {
                    case (true) { -> this.type_query(NodeKind.ALIGN_OF, c); }
                    default {};
                };
                switch (c == TokenType.ENDIANOF)
                {
                    case (true) { -> this.type_query(NodeKind.ENDIAN_OF, c); }
                    default {};
                };
                switch (c == TokenType.TYPEOF)
                {
                    case (true) { -> this.type_query(NodeKind.TYPE_OF, c); }
                    default {};
                };
                switch (c == TokenType.STRUCT | c == TokenType.OBJECT)
                {
                    case (true) {
                    this.advance();
                    switch (c)
                    {
                        case (TokenType.STRUCT)
                        {
                            n = this.lit(DataType.STRUCT, 0, line, col);
                            switch (!this.failed)
                            {
                                case (true) { n.text = g"struct\0"; }
                                default {};
                            };
                        }
                        default
                        {
                            n = this.lit(DataType.OBJECT, 0, line, col);
                            switch (!this.failed)
                            {
                                case (true) { n.text = g"object\0"; }
                                default {};
                            };
                        };
                    };
                    -> n;
                }
                    default {};
                };
                switch (c == TokenType.STRINGIFY)
                {
                    case (true) { -> this.stringify_expr(); }
                    default {};
                };
                switch (c == TokenType.CODIFY)
                {
                    case (true) {
                    // ~$f"..." / ~$i"..." is the string expression itself, ~$name the recorded string
                    this.advance();
                    switch (this.expect(TokenType.F_STRING))
                    {
                        case (true) {
                        n = this.f_string_node();
                    }
                        default {
                            switch (this.expect(TokenType.I_STRING))
                            {
                                case (true) {
                        n = this.i_string_node();
                    }
                                default {
                        byte* cname = this.ident();
                        switch (this.failed)
                        {
                            case (true) { -> (Node*)0; }
                            default {};
                        };
                        byte* cval = (byte*)nm_get(this.cstrs, cname);
                        switch (cval == (byte*)0)
                        {
                            case (true) { cval = cname; }
                            default {};
                        };
                        n = this.mk(NodeKind.STRING_LITERAL, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> n; }
                            default {};
                        };
                        n.text = cval;
                        n.op = -1;
                    };
                            };
                        };
                    };
                    switch (this.failed)
                    {
                        case (true) { -> (Node*)0; }
                        default {};
                    };
                    n.line = line;
                    n.col = col;
                    -> n;
                }
                    default {};
                };

                // int(x) float(x) ... type conversion
                int dt = -1;
                switch (c)
                {
                    case (TokenType.SINT) { dt = DataType.SINT; }
                    case (TokenType.UINT) { dt = DataType.UINT; }
                    case (TokenType.FLOAT_KW) { dt = DataType.FLOAT; }
                    case (TokenType.DOUBLE_KW) { dt = DataType.DOUBLE; }
                    case (TokenType.BYTE) { dt = DataType.BYTE; }
                    case (TokenType.BOOL_KW) { dt = DataType.BOOL; }
                    case (TokenType.SLONG) { dt = DataType.SLONG; }
                    case (TokenType.ULONG) { dt = DataType.ULONG; }
                    default {};
                };
                switch (dt >= 0)
                {
                    case (true) {
                    this.advance();
                    switch (this.expect(TokenType.LEFT_PAREN))
                    {
                        case (true) {
                        this.advance();
                        Node* inner = this.expression();
                        switch (this.failed)
                        {
                            case (true) { -> inner; }
                            default {};
                        };
                        switch (!this.consume(TokenType.RIGHT_PAREN))
                        {
                            case (true) { -> inner; }
                            default {};
                        };
                        n = this.mk(NodeKind.TYPE_CONVERT_EXPRESSION, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> inner; }
                            default {};
                        };
                        TypeSpec* tt = typespec_new();
                        tt.base_type = dt;
                        n.ts = tt;
                        n.a = inner;
                        -> n;
                    }
                        default {};
                    };
                    this.pos = this.pos - 1;
                    this.error_unexpected();
                    -> (Node*)0;
                }
                    default {};
                };
                this.error_unexpected();
                -> (Node*)0;
            };

            // ===== EXPRESSION STATEMENTS =====

            // Wraps value as an ExpressionStatement of ASSIGNMENT(lvalue, value)
            assign_stmt(Node* lvalue, Node* value, int line, int col) -> Node*
            {
                Node* a = this.mk(NodeKind.ASSIGNMENT, line, col);
                switch (this.failed)
                {
                    case (true) { -> a; }
                    default {};
                };
                a.a = lvalue;
                a.b = value;
                Node* s = this.mk(NodeKind.EXPRESSION_STATEMENT, line, col);
                switch (this.failed)
                {
                    case (true) { -> s; }
                    default {};
                };
                s.a = a;
                -> s;
            };

            // '{' ('[' index ']' '=' expr ';')* '}'. Statements go to this.pending.
            array_assign_block(Node* base) -> void
            {
                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { ->; }
                    default {};
                };
                int line, col;
                Node* ix;
                Node* lv;
                Node* rv;
                Node* acc;
                while (!this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (!this.expect(TokenType.LEFT_BRACKET))
                    {
                        case (true) {
                        this.error(g"only index-assignment items '[idx] = val;' are legal inside an array-assign block; expected '[' or '}'\0");
                        ->;
                    }
                        default {};
                    };
                    line = this.cur_line();
                    col = this.cur_col();
                    this.advance();
                    ix = this.expression();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (!this.consume(TokenType.RIGHT_BRACKET))
                    {
                        case (true) { ->; }
                        default {};
                    };
                    acc = this.mk(NodeKind.ARRAY_ACCESS, line, col);
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    acc.a = node_clone(base);
                    acc.b = ix;
                    switch (!this.consume(TokenType.ASSIGN))
                    {
                        case (true) { ->; }
                        default {};
                    };
                    rv = this.expression();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (!this.consume(TokenType.SEMICOLON))
                    {
                        case (true) { ->; }
                        default {};
                    };
                    nv_push(this.block_out, this.assign_stmt(acc, rv, line, col));
                };
                this.consume(TokenType.RIGHT_BRACE);
                ->;
            };

            // '{' ('.' name ('.' name | '[' idx ']')* ( '=' expr | '(' args ')' | '{' nested '}' ) ';')* '}'
            member_assign_block(Node* base) -> void
            {
                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { ->; }
                    default {};
                };
                int line, col;
                Node* mem;
                Node* lv;
                Node* rv;
                Node* es;
                while (!this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (!this.expect(TokenType.DOT))
                    {
                        case (true) {
                        this.error(g"declarations and non-member statements are illegal inside a member-assign block; expected '.' or '}'\0");
                        ->;
                    }
                        default {};
                    };
                    line = this.cur_line();
                    col = this.cur_col();
                    this.advance();
                    switch (!this.expect(TokenType.IDENTIFIER))
                    {
                        case (true) {
                        this.fail_expected(TokenType.IDENTIFIER);
                        ->;
                    }
                        default {};
                    };
                    mem = this.mk(NodeKind.MEMBER_ACCESS, line, col);
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    mem.a = node_clone(base);
                    mem.text = this.cur_value();
                    this.advance();
                    switch (this.expect(TokenType.LEFT_BRACE))
                    {
                        case (true) {
                        switch (this.type_at(1) == TokenType.LEFT_BRACKET)
                        {
                            case (true) { this.array_assign_block(mem); }
                            default { this.member_assign_block(mem); };
                        };
                        switch (this.failed)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        switch (!this.consume(TokenType.SEMICOLON))
                        {
                            case (true) { ->; }
                            default {};
                        };
                        node_free(mem);
                    }
                        default {
                        // '.a.b', '.a[i]', '.a.b(args)': continue the postfix chain from '.name'
                        lv = this.postfix_from(mem);
                        switch (this.failed)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        switch (this.expect(TokenType.LEFT_BRACE))
                        {
                            case (true) {
                            switch (lv.kind != NodeKind.ARRAY_ACCESS & this.type_at(1) == TokenType.LEFT_BRACKET)
                            {
                                case (true) { this.array_assign_block(lv); }
                                default { this.member_assign_block(lv); };
                            };
                            switch (this.failed)
                            {
                                case (true) { ->; }
                                default {};
                            };
                            switch (!this.consume(TokenType.SEMICOLON))
                            {
                                case (true) { ->; }
                                default {};
                            };
                            node_free(lv);
                        }
                            default {
                                switch (this.expect(TokenType.ASSIGN))
                                {
                                    case (true) {
                            this.advance();
                            rv = this.expression();
                            switch (this.failed)
                            {
                                case (true) { ->; }
                                default {};
                            };
                            switch (!this.consume(TokenType.SEMICOLON))
                            {
                                case (true) { ->; }
                                default {};
                            };
                            nv_push(this.block_out, this.assign_stmt(lv, rv, line, col));
                        }
                                    default {
                            // call item such as '.mod.position(m0, eb);'
                            switch (!this.consume(TokenType.SEMICOLON))
                            {
                                case (true) { ->; }
                                default {};
                            };
                            es = this.mk(NodeKind.EXPRESSION_STATEMENT, line, col);
                            switch (this.failed)
                            {
                                case (true) { ->; }
                                default {};
                            };
                            es.a = lv;
                            nv_push(this.block_out, es);
                        };
                                };
                            };
                        };
                    };
                    };
                };
                this.consume(TokenType.RIGHT_BRACE);
                ->;
            };

            // expression_statement -> expression ';' | lvalue member_assign_block ';' | lvalue array_assign_block ';'
            expression_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* expr = this.expression();
                switch (this.failed)
                {
                    case (true) { -> expr; }
                    default {};
                };
                int k = expr.kind;
                Node* s;
                switch (this.expect(TokenType.LEFT_BRACE) &
                    (k == NodeKind.IDENTIFIER | k == NodeKind.ARRAY_ACCESS | k == NodeKind.MEMBER_ACCESS))
                {
                    case (true) {
                    this.block_out = nv_new();
                    switch (this.type_at(1) == TokenType.LEFT_BRACKET)
                    {
                        case (true) { this.array_assign_block(expr); }
                        default { this.member_assign_block(expr); };
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                    this.last_call = (Node*)0;
                    NodeVec* out = this.block_out;
                    this.block_out = (NodeVec*)0;
                    node_free(expr);
                    switch (this.failed)
                    {
                        case (true) {
                        nv_free(out);
                        -> (Node*)0;
                    }
                        default {};
                    };
                    switch (out.len == 0)
                    {
                        case (true) {
                        nv_free(out);
                        -> (Node*)0;
                    }
                        default {};
                    };
                    s = out.items[0];
                    int j = 1;
                    while (j < out.len)
                    {
                        nv_push(this.pending, out.items[j]);
                        j++;
                    };
                    out.len = 0;
                    nv_free(out);
                    -> s;
                }
                    default {};
                };
                switch (!this.consume(TokenType.SEMICOLON))
                {
                    case (true) { -> expr; }
                    default {};
                };
                s = this.mk(NodeKind.EXPRESSION_STATEMENT, line, col);
                switch (this.failed)
                {
                    case (true) { -> s; }
                    default {};
                };
                s.a = expr;
                switch (k)
                {
                    case (NodeKind.FUNCTION_CALL) { this.last_call = expr; }
                    default { this.last_call = (Node*)0; };
                };
                -> s;
            };
            // ===== DECLARATIONS =====

            // Identifier token value, or null with an error recorded
            ident() -> byte*
            {
                switch (!this.expect(TokenType.IDENTIFIER))
                {
                    case (true) {
                    this.fail_expected(TokenType.IDENTIFIER);
                    -> (byte*)0;
                }
                    default {};
                };
                byte* v = this.cur_value();
                this.advance();
                -> v;
            };

            define_var(byte* name, TypeSpec* ts) -> void
            {
                switch (this.st != (FXC_SYMTABLE*)0)
                {
                    case (true) {
                    st_define(this.st, name, SymbolKind.VARIABLE, ts, (Node*)0);
                }
                    default {};
                };
                ->;
            };

            define_type(byte* name, TypeSpec* ts) -> void
            {
                switch (this.st != (FXC_SYMTABLE*)0)
                {
                    case (true) {
                    st_define(this.st, name, SymbolKind.TYPE, ts, (Node*)0);
                    switch ((ts.flags `& TS_NO_FUNCTIONS) != 0)
                    {
                        case (true) { st_mark_nofunc(this.st, name); }
                        default {};
                    };
                }
                    default {};
                };
                ->;
            };

            // Prints "Warning: msg at line:col", the source line with tabs expanded to 4
            // spaces, and a caret line, as ferrors.emit_warning renders a warning
            warn_here(byte* msg) -> void
            {
                int wl = this.cur_line();
                int wc = this.cur_col();
                int p = 0;
                int ln = 1;
                int e;
                int d;
                byte* src = this.lx.src;
                int n = this.lx.length;
                Buf wb;
                wb.__init();
                defer wb.__exit();
                print(g"Warning: \0");
                print(msg);
                print(g" at \0");
                print(wl);
                print(g":\0");
                println(wc);
                while (p < n & ln < wl)
                {
                    switch (src[p] == 10)
                    {
                        case (true) { ln++; }
                        default {};
                    };
                    p++;
                };
                switch (ln != wl)
                {
                    case (true) { ->; }
                    default {};
                };
                e = p;
                while (e < n & src[e] != 10 & src[e] != 13) { e++; };
                while (p < e)
                {
                    switch (src[p] == 9)
                    {
                        case (true) { wb.put_str(g"    \0"); }
                        default { wb.put((int)src[p]); };
                    };
                    p++;
                };
                wb.put(0);
                println(wb.mem);
                wb.clear();
                d = 1;
                while (d < wc)
                {
                    wb.put(45);
                    d++;
                };
                wb.put(94);
                wb.put(0);
                println(wb.mem);
                ->;
            };

            // Warns about a declaration in a loop body unless it is a singinit
            decl_loop_warning() -> void
            {
                switch (this.loop_depth > 0 & !this.in_for_init)
                {
                    case (true) {
                    bool sing = this.expect(TokenType.SINGINIT) | this.type_at(1) == TokenType.SINGINIT;
                    switch (!sing)
                    {
                        case (true) {
                        this.warn_here(g"variable declaration inside a loop body - this will continually allocate new slots on the stack each iteration.\0");
                    }
                        default {};
                    };
                }
                    default {};
                };
                ->;
            };

            // Gives a bare struct literal the declared type name
            literal_type_from(Node* init, TypeSpec* ts) -> void
            {
                switch (init == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (init.kind == NodeKind.STRUCT_LITERAL & init.text == (byte*)0 & ts.custom_typename != (byte*)0)
                {
                    case (true) {
                    init.text = ts.custom_typename;
                }
                    default {};
                };
                ->;
            };

            // Frees what a failed declaration parse still owns
            decl_abort(TypeSpec* ts, PtrVec* inits, NodeVec* out) -> Node*
            {
                int i;
                switch (ts != (TypeSpec*)0)
                {
                    case (true) { typespec_free(ts); }
                    default {};
                };
                switch (inits != (PtrVec*)0)
                {
                    case (true) {
                    while (i < inits.len)
                    {
                        switch (inits.items[i] != (void*)0)
                        {
                            case (true) { node_free((Node*)inits.items[i]); }
                            default {};
                        };
                        i++;
                    };
                    pv_free(inits);
                }
                    default {};
                };
                switch (out != (NodeVec*)0)
                {
                    case (true) {
                    i = 0;
                    while (i < out.len)
                    {
                        node_free(out.items[i]);
                        i++;
                    };
                    nv_free(out);
                }
                    default {};
                };
                -> (Node*)0;
            };

            // Returns the first node of out and queues the rest
            decl_flatten(NodeVec* out) -> Node*
            {
                Node* first = (Node*)0;
                switch (out.len > 0)
                {
                    case (true) { first = out.items[0]; }
                    default {};
                };
                int j = 1;
                while (j < out.len)
                {
                    nv_push(this.pending, out.items[j]);
                    j++;
                };
                out.len = 0;
                nv_free(out);
                -> first;
            };

            // VARIABLE_DECLARATION. The first declaration of a group owns ts, later ones a copy.
            var_decl_node(byte* name, TypeSpec* ts, Node* init, int line, int col, bool first) -> Node*
            {
                Node* d = this.mk(NodeKind.VARIABLE_DECLARATION, line, col);
                switch (this.failed)
                {
                    case (true) { -> d; }
                    default {};
                };
                d.text = name;
                switch (first)
                {
                    case (true) { d.ts = ts; }
                    default { d.ts = typespec_copy(ts); };
                };
                d.a = init;
                switch (ts.storage_class == StorageClass.GLOBAL)
                {
                    case (true) { d.flags = NF_GLOBAL; }
                    default {};
                };
                -> d;
            };

            type_decl_node(byte* name, TypeSpec* ts, Node* init, int line, int col, bool first) -> Node*
            {
                Node* d = this.mk(NodeKind.TYPE_DECLARATION, line, col);
                switch (this.failed)
                {
                    case (true) { -> d; }
                    default {};
                };
                d.text = name;
                switch (first)
                {
                    case (true) { d.ts = ts; }
                    default { d.ts = typespec_copy(ts); };
                };
                d.a = init;
                -> d;
            };

            // Text "base*..." of a dict key or value type
            dict_text(TypeSpec* t) -> byte*
            {
                switch (t == (TypeSpec*)0)
                {
                    case (true) { -> g"unknown\0"; }
                    default {};
                };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                switch (t.custom_typename != (byte*)0)
                {
                    case (true) { this.sb.put_str(t.custom_typename); }
                    default { this.sb.put_str(datatype_text(t.base_type)); };
                };
                int i;
                while (i < t.pointer_depth)
                {
                    this.sb.put_str(g"*\0");
                    i++;
                };
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            dict_sig(TypeSpec* t) -> byte*
            {
                byte* s = this.cat2(g"dict{\0", this.dict_text(t.dict_key));
                s = this.cat2(s, g":\0");
                s = this.cat2(s, this.dict_text(t.dict_value));
                -> this.cat2(s, g"}\0");
            };

            dict_same(TypeSpec* a, TypeSpec* b) -> bool
            {
                switch (!cstr_eq(this.dict_text(a.dict_key), this.dict_text(b.dict_key)))
                {
                    case (true) { -> false; }
                    default {};
                };
                -> cstr_eq(this.dict_text(a.dict_value), this.dict_text(b.dict_value));
            };

            // Dict operands of init must agree with each other and with the declared type
            check_dict_init(TypeSpec* ts, Node* init) -> void
            {
                switch (this.st == (FXC_SYMTABLE*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                PtrVec* ops = pv_new();
                PtrVec* todo = pv_new();
                pv_push(todo, (void*)init);
                Node* e;
                byte* nm;
                FXC_SYMENTRY* ent;
                TypeSpec* et;
                while (todo.len > 0)
                {
                    todo.len--;
                    e = (Node*)todo.items[todo.len];
                    switch (e == (Node*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    nm = (byte*)0;
                    switch (e.kind == NodeKind.BINARY_OP)
                    {
                        case (true) {
                        pv_push(todo, (void*)e.a);
                        pv_push(todo, (void*)e.b);
                    }
                        default {
                            switch (e.kind == NodeKind.IDENTIFIER | e.kind == NodeKind.FUNCTION_CALL | e.kind == NodeKind.STRINGIFY)
                            {
                                case (true) {
                        nm = e.text;
                    }
                                default {};
                            };
                        };
                    };
                    switch (nm != (byte*)0)
                    {
                        case (true) {
                        ent = st_lookup_variable(this.st, nm, (byte*)0);
                        switch (ent != (FXC_SYMENTRY*)0)
                        {
                            case (true) {
                            et = (TypeSpec*)ent.ts;
                            switch (et != (TypeSpec*)0)
                            {
                                case (true) {
                                switch (et.base_type == DataType.DICT)
                                {
                                    case (true) { pv_push(ops, (void*)et); }
                                    default {};
                                };
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                };
                int i = 1;
                TypeSpec* ref;
                TypeSpec* ots;
                switch (ops.len > 1)
                {
                    case (true) {
                    ref = (TypeSpec*)ops.items[0];
                    while (i < ops.len)
                    {
                        ots = (TypeSpec*)ops.items[i];
                        switch (!this.dict_same(ots, ref))
                        {
                            case (true) {
                            this.error(this.cat2(this.cat2(this.cat2(g"Dict operands are incompatible: \0", this.dict_sig(ref)),
                                                           g" cannot be combined with \0"), this.dict_sig(ots)));
                            pv_free(ops);
                            pv_free(todo);
                            ->;
                        }
                            default {};
                        };
                        i++;
                    };
                }
                    default {};
                };
                switch (ops.len > 0)
                {
                    case (true) {
                    ref = (TypeSpec*)ops.items[0];
                    switch (!this.dict_same(ts, ref))
                    {
                        case (true) {
                        this.error(this.cat2(this.cat2(this.cat2(g"Dict type mismatch: declared \0", this.dict_sig(ts)),
                                                       g" is incompatible with \0"), this.dict_sig(ref)));
                    }
                        default {};
                    };
                }
                    default {};
                };
                pv_free(ops);
                pv_free(todo);
                ->;
            };

            // variable_declaration -> type_spec ( 'as' name ('=' expr)? (',' name ('=' expr)?)*
            //                                   | name ( '(' args ')' | '@=' expr | 'from' expr | '=' expr | '{' dict '}' )
            //                                     (',' name ...)* )
            // Several names make several declarations: the first is returned, the rest are queued.
            variable_declaration() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.decl_loop_warning();
                byte* raw = (byte*)0;
                switch (this.expect(TokenType.IDENTIFIER))
                {
                    case (true) { raw = this.cur_value(); }
                    default {};
                };
                TypeSpec* ts = this.type_spec();
                switch (this.failed)
                {
                    case (true) { -> this.decl_abort(ts, (PtrVec*)0, (NodeVec*)0); }
                    default {};
                };

                NodeVec* out = nv_new();
                Node* init;
                Node* d;
                byte* name;

                // ----- type alias: T as Name -----
                switch (this.expect(TokenType.AS))
                {
                    case (true) {
                    this.advance();
                    name = this.ident();
                    switch (this.failed)
                    {
                        case (true) { -> this.decl_abort(ts, (PtrVec*)0, out); }
                        default {};
                    };
                    this.define_type(name, ts);
                    init = (Node*)0;
                    switch (this.expect(TokenType.ASSIGN))
                    {
                        case (true) {
                        this.advance();
                        init = this.expression();
                        switch (this.failed)
                        {
                            case (true) { -> this.decl_abort(ts, (PtrVec*)0, out); }
                            default {};
                        };
                        switch (init.kind == NodeKind.STRUCT_LITERAL & init.text == (byte*)0 & ts.custom_typename == (byte*)0)
                        {
                            case (true) {
                            node_free(init);
                            this.error(g"Struct literal initialization requires a custom type\0");
                            -> this.decl_abort(ts, (PtrVec*)0, out);
                        }
                            default {};
                        };
                        this.literal_type_from(init, ts);
                    }
                        default {};
                    };
                    d = this.type_decl_node(name, ts, init, line, col, true);
                    switch (this.failed)
                    {
                        case (true) { -> this.decl_abort((TypeSpec*)0, (PtrVec*)0, out); }
                        default {};
                    };
                    nv_push(out, d);
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        name = this.ident();
                        switch (this.failed)
                        {
                            case (true) { -> this.decl_abort((TypeSpec*)0, (PtrVec*)0, out); }
                            default {};
                        };
                        this.define_type(name, ts);
                        init = (Node*)0;
                        switch (this.expect(TokenType.ASSIGN))
                        {
                            case (true) {
                            this.advance();
                            init = this.expression();
                            switch (this.failed)
                            {
                                case (true) { -> this.decl_abort((TypeSpec*)0, (PtrVec*)0, out); }
                                default {};
                            };
                            switch (init.kind == NodeKind.STRUCT_LITERAL & init.text == (byte*)0 & ts.custom_typename == (byte*)0)
                            {
                                case (true) {
                                node_free(init);
                                this.error(g"Struct literal initialization requires a custom type\0");
                                -> this.decl_abort((TypeSpec*)0, (PtrVec*)0, out);
                            }
                                default {};
                            };
                            this.literal_type_from(init, ts);
                        }
                            default {};
                        };
                        d = this.type_decl_node(name, ts, init, line, col, false);
                        switch (this.failed)
                        {
                            case (true) { -> this.decl_abort((TypeSpec*)0, (PtrVec*)0, out); }
                            default {};
                        };
                        nv_push(out, d);
                    };
                    -> this.decl_flatten(out);
                }
                    default {};
                };

                // ----- variables -----
                nv_free(out);
                out = (NodeVec*)0;
                name = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.decl_abort(ts, (PtrVec*)0, (NodeVec*)0); }
                    default {};
                };
                this.define_var(name, ts);

                Node* call;
                Node* holder;
                switch (this.expect(TokenType.LEFT_PAREN))
                {
                    case (true) {
                    this.advance();
                    holder = this.mk(NodeKind.NODE_LIST, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> this.decl_abort(ts, (PtrVec*)0, (NodeVec*)0); }
                        default {};
                    };
                    switch (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        case (true) { this.argument_list(holder, (byte*)0); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) {
                        node_free(holder);
                        -> this.decl_abort(ts, (PtrVec*)0, (NodeVec*)0);
                    }
                        default {};
                    };
                    call = this.mk(NodeKind.FUNCTION_CALL, line, col);
                    switch (this.failed)
                    {
                        case (true) {
                        node_free(holder);
                        -> this.decl_abort(ts, (PtrVec*)0, (NodeVec*)0);
                    }
                        default {};
                    };
                    switch (ts.custom_typename != (byte*)0)
                    {
                        case (true) { call.text = this.cat2(ts.custom_typename, g".__init\0"); }
                        default {
                            switch (raw != (byte*)0)
                            {
                                case (true) { call.text = this.cat2(raw, g".__init\0"); }
                                default { call.text = this.cat2(datatype_text(ts.base_type), g"__init\0"); };
                            };
                        };
                    };
                    this.take_args(call, holder);
                    -> this.var_decl_node(name, ts, call, line, col, true);
                }
                    default {};
                };

                PtrVec* names = pv_new();
                PtrVec* inits = pv_new();
                pv_push(names, (void*)name);

                Node* rhs;
                Node* src;
                int al;
                int ac;

                switch (this.expect(TokenType.ADDRESS_ASSIGN))
                {
                    case (true) {
                    al = this.cur_line();
                    ac = this.cur_col();
                    this.advance();
                    rhs = this.expression();
                    switch (this.failed)
                    {
                        case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                        default {};
                    };
                    d = this.mk(NodeKind.ADDRESS_OF, al, ac);
                    switch (this.failed)
                    {
                        case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                        default {};
                    };
                    d.a = rhs;
                    pv_push(inits, (void*)d);
                }
                    default {
                        switch (this.expect(TokenType.FROM))
                        {
                            case (true) {
                    this.advance();
                    src = this.expression();
                    switch (this.failed)
                    {
                        case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                        default {};
                    };
                    this.literal_type_from(src, ts);
                    switch (ts.custom_typename != (byte*)0)
                    {
                        case (true) {
                        d = this.mk(NodeKind.STRUCT_RECAST, line, col);
                        switch (this.failed)
                        {
                            case (true) { node_free(src); pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                            default {};
                        };
                        d.text = ts.custom_typename;
                        d.a = src;
                        // ival = suppress_invalidate, set by a '!' after the source
                        switch (this.expect(TokenType.NOT))
                        {
                            case (true) {
                            this.advance();
                            d.ival = 1;
                        }
                            default {};
                        };
                    }
                        default {
                        d = this.mk(NodeKind.CAST_EXPRESSION, line, col);
                        switch (this.failed)
                        {
                            case (true) { node_free(src); pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                            default {};
                        };
                        d.ts = typespec_copy(ts);
                        d.a = src;
                        d.ival = 1;     // is_bitcast
                    };
                    };
                    pv_push(inits, (void*)d);
                }
                            default {
                                switch (this.expect(TokenType.ASSIGN))
                                {
                                    case (true) {
                    this.advance();
                    rhs = this.expression();
                    switch (this.failed)
                    {
                        case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                        default {};
                    };
                    switch (ts.base_type == DataType.DICT)
                    {
                        case (true) {
                        this.check_dict_init(ts, rhs);
                        switch (this.failed)
                        {
                            case (true) {
                            node_free(rhs);
                            pv_free(names);
                            -> this.decl_abort(ts, inits, (NodeVec*)0);
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (this.ctor_sugar(raw, rhs))
                    {
                        case (true) {
                        call = this.mk(NodeKind.FUNCTION_CALL, line, col);
                        switch (this.failed)
                        {
                            case (true) {
                            node_free(rhs);
                            pv_free(names);
                            -> this.decl_abort(ts, inits, (NodeVec*)0);
                        }
                            default {};
                        };
                        call.text = this.cat2(raw, g".__init\0");
                        node_push(call, 0, rhs);
                        pv_free(names);
                        pv_free(inits);
                        -> this.var_decl_node(name, ts, call, line, col, true);
                    }
                        default {};
                    };
                    this.note_comptime_string(name, ts, rhs);
                    pv_push(inits, (void*)rhs);
                }
                                    default {
                                        switch (this.expect(TokenType.LEFT_BRACE))
                                        {
                                            case (true) {
                    switch (ts.base_type != DataType.DICT)
                    {
                        case (true) {
                        this.fail_expected(TokenType.ASSIGN);
                        pv_free(names);
                        -> this.decl_abort(ts, inits, (NodeVec*)0);
                    }
                        default {};
                    };
                    // dict{K:V} Name { k1: v1, k2: v2 };
                    this.advance();
                    d = this.mk(NodeKind.DICT_LITERAL, line, col);
                    switch (this.failed)
                    {
                        case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                        default {};
                    };
                    while (!this.expect(TokenType.RIGHT_BRACE) & !this.expect(TokenType.EOF) & !this.failed)
                    {
                        rhs = this.expression();
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        node_push(d, 0, rhs);
                        switch (!this.consume(TokenType.COLON))
                        {
                            case (true) { break; }
                            default {};
                        };
                        rhs = this.expression();
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        node_push(d, 0, rhs);
                        switch (this.expect(TokenType.COMMA))
                        {
                            case (true) { this.advance(); }
                            default {};
                        };
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_BRACE); }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) {
                        node_free(d);
                        pv_free(names);
                        -> this.decl_abort(ts, inits, (NodeVec*)0);
                    }
                        default {};
                    };
                    ts.dict_capacity = node_count(d, 0) / 2;
                    pv_push(inits, (void*)d);
                }
                                            default {
                    pv_push(inits, (void*)0);
                };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };

                int i, n;
                Node* prev;
                // ----- name list: int x, y, z ... -----
                switch (this.expect(TokenType.COMMA) & inits.items[0] == (void*)0)
                {
                    case (true) {
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        name = this.ident();
                        switch (this.failed)
                        {
                            case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                            default {};
                        };
                        this.define_var(name, ts);
                        pv_push(names, (void*)name);
                        switch (this.expect(TokenType.ADDRESS_ASSIGN))
                        {
                            case (true) {
                            al = this.cur_line();
                            ac = this.cur_col();
                            this.advance();
                            rhs = this.expression();
                            switch (this.failed)
                            {
                                case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                                default {};
                            };
                            d = this.mk(NodeKind.ADDRESS_OF, al, ac);
                            switch (this.failed)
                            {
                                case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                                default {};
                            };
                            d.a = rhs;
                            pv_push(inits, (void*)d);
                        }
                            default {
                                switch (this.expect(TokenType.ASSIGN))
                                {
                                    case (true) {
                            this.advance();
                            switch (this.expect(TokenType.DITTO))
                            {
                                case (true) {
                                prev = (Node*)inits.items[inits.len - 1];
                                switch (prev == (Node*)0)
                                {
                                    case (true) {
                                    this.error(g"Ditto operator '#\"' used before any initializer to repeat\0");
                                    pv_free(names);
                                    -> this.decl_abort(ts, inits, (NodeVec*)0);
                                }
                                    default {};
                                };
                                this.advance();
                                pv_push(inits, (void*)node_clone(prev));
                            }
                                default {
                                rhs = this.expression();
                                switch (this.failed)
                                {
                                    case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                                    default {};
                                };
                                this.note_comptime_string(name, ts, rhs);
                                pv_push(inits, (void*)rhs);
                            };
                            };
                        }
                                    default {
                            pv_push(inits, (void*)0);
                        };
                                };
                            };
                        };
                    };

                    // no per-name initializer: a bulk 'from' or '=' may follow
                    bool all_null = true;
                    i = 0;
                    while (i < inits.len)
                    {
                        switch (inits.items[i] != (void*)0)
                        {
                            case (true) { all_null = false; }
                            default {};
                        };
                        i++;
                    };
                    switch (all_null)
                    {
                        case (true) {
                        inits.len = 0;
                        switch (this.expect(TokenType.FROM))
                        {
                            case (true) {
                            this.advance();
                            src = this.expression();
                            switch (this.failed)
                            {
                                case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                                default {};
                            };
                            i = 0;
                            while (i < names.len)
                            {
                                d = this.mk(NodeKind.ARRAY_ACCESS, line, col);
                                switch (this.failed)
                                {
                                    case (true) { node_free(src); pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                                    default {};
                                };
                                switch (i)
                                {
                                    case (0) { d.a = src; }
                                    default { d.a = node_clone(src); };
                                };
                                d.b = this.lit(DataType.SINT, (i64)i, line, col);
                                pv_push(inits, (void*)d);
                                i++;
                            };
                        }
                            default {
                                switch (this.expect(TokenType.ASSIGN))
                                {
                                    case (true) {
                            this.advance();
                            i = 0;
                            while (i < names.len)
                            {
                                rhs = this.expression();
                                switch (this.failed)
                                {
                                    case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                                    default {};
                                };
                                pv_push(inits, (void*)rhs);
                                switch (this.expect(TokenType.COMMA))
                                {
                                    case (true) { this.advance(); }
                                    default { break; };
                                };
                                i++;
                            };
                        }
                                    default {};
                                };
                            };
                        };
                    }
                        default {};
                    };
                }
                    default {
                        switch (this.expect(TokenType.COMMA))
                        {
                            case (true) {
                    // int x = 1, y = 2, z = 3; every name has its own initializer
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        name = this.ident();
                        switch (this.failed)
                        {
                            case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                            default {};
                        };
                        this.define_var(name, ts);
                        pv_push(names, (void*)name);
                        switch (this.expect(TokenType.ADDRESS_ASSIGN))
                        {
                            case (true) {
                            al = this.cur_line();
                            ac = this.cur_col();
                            this.advance();
                            rhs = this.expression();
                            switch (this.failed)
                            {
                                case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                                default {};
                            };
                            d = this.mk(NodeKind.ADDRESS_OF, al, ac);
                            switch (this.failed)
                            {
                                case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                                default {};
                            };
                            d.a = rhs;
                            pv_push(inits, (void*)d);
                        }
                            default {
                                switch (this.expect(TokenType.ASSIGN))
                                {
                                    case (true) {
                            this.advance();
                            switch (this.expect(TokenType.DITTO))
                            {
                                case (true) {
                                this.advance();
                                prev = (Node*)inits.items[inits.len - 1];
                                switch (prev == (Node*)0)
                                {
                                    case (true) { pv_push(inits, (void*)0); }
                                    default { pv_push(inits, (void*)node_clone(prev)); };
                                };
                            }
                                default {
                                rhs = this.expression();
                                switch (this.failed)
                                {
                                    case (true) { pv_free(names); -> this.decl_abort(ts, inits, (NodeVec*)0); }
                                    default {};
                                };
                                pv_push(inits, (void*)rhs);
                            };
                            };
                        }
                                    default {
                            pv_push(inits, (void*)0);
                        };
                                };
                            };
                        };
                    };
                }
                            default {};
                        };
                    };
                };

                // ----- build the declarations -----
                out = nv_new();
                // Fewer initializers than names are padded at the front (fparser.py)
                PtrVec* fin = pv_new();
                int pad = names.len - inits.len;
                i = 0;
                while (i < pad)
                {
                    pv_push(fin, (void*)0);
                    i++;
                };
                i = 0;
                while (i < inits.len)
                {
                    pv_push(fin, inits.items[i]);
                    i++;
                };
                pv_free(inits);

                n = names.len;
                i = 0;
                while (i < n)
                {
                    init = (Node*)0;
                    switch (i < fin.len)
                    {
                        case (true) { init = (Node*)fin.items[i]; }
                        default {};
                    };
                    this.literal_type_from(init, ts);
                    d = this.var_decl_node((byte*)names.items[i], ts, init, line, col, i == 0);
                    switch (this.failed)
                    {
                        case (true) {
                        pv_free(names);
                        pv_free(fin);
                        switch (i == 0)
                        {
                            case (true) { -> this.decl_abort(ts, (PtrVec*)0, out); }
                            default {};
                        };
                        -> this.decl_abort((TypeSpec*)0, (PtrVec*)0, out);
                    }
                        default {};
                    };
                    nv_push(out, d);
                    i++;
                };
                pv_free(names);
                pv_free(fin);
                -> this.decl_flatten(out);
            };

            // variable_declaration_statement -> variable_declaration ';'
            variable_declaration_statement() -> Node*
            {
                Node* d = this.variable_declaration();
                switch (this.failed)
                {
                    case (true) { -> d; }
                    default {};
                };
                this.consume(TokenType.SEMICOLON);
                -> d;
            };

            // dual_assign_declaration -> type '^|' type IDENTIFIER ',' IDENTIFIER '=' expression ';'
            dual_assign_declaration() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                TypeSpec* ok_ts = this.type_spec();
                switch (this.failed)
                {
                    case (true) { typespec_free(ok_ts); -> (Node*)0; }
                    default {};
                };
                switch (!this.consume(TokenType.XOR_OP))
                {
                    case (true) { typespec_free(ok_ts); -> (Node*)0; }
                    default {};
                };
                TypeSpec* err_ts = this.type_spec();
                switch (this.failed)
                {
                    case (true) { typespec_free(ok_ts); typespec_free(err_ts); -> (Node*)0; }
                    default {};
                };
                byte* ok_name = this.ident();
                byte* err_name = (byte*)0;
                Node* call;
                switch (!this.failed)
                {
                    case (true) {
                    switch (this.consume(TokenType.COMMA))
                    {
                        case (true) { err_name = this.ident(); }
                        default {};
                    };
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.ASSIGN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) {
                    call = this.expression();
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) {
                        node_free(call);
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) {
                    typespec_free(ok_ts);
                    typespec_free(err_ts);
                    -> (Node*)0;
                }
                    default {};
                };
                this.define_var(ok_name, ok_ts);
                this.define_var(err_name, err_ts);
                Node* n = this.mk(NodeKind.DUAL_ASSIGN_DECLARATION, line, col);
                switch (this.failed)
                {
                    case (true) {
                    typespec_free(ok_ts);
                    typespec_free(err_ts);
                    node_free(call);
                    -> n;
                }
                    default {};
                };
                n.ts = ok_ts;
                n.ts2 = err_ts;
                n.text = ok_name;
                n.text2 = err_name;
                n.a = call;
                -> n;
            };

            // auto_variable_declaration -> 'auto' IDENTIFIER '=' expression
            // The type is a sentinel (void with storage class auto); the compiler infers it.
            auto_variable_declaration() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.AUTO);
                byte* name = (byte*)0;
                Node* init = (Node*)0;
                switch (!this.failed)
                {
                    case (true) { name = this.ident(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.ASSIGN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { init = this.expression(); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) {
                    node_free(init);
                    -> (Node*)0;
                }
                    default {};
                };
                TypeSpec* ts = typespec_new();
                switch (ts == (TypeSpec*)0)
                {
                    case (true) { node_free(init); this.fail_alloc(); -> (Node*)0; }
                    default {};
                };
                ts.base_type = DataType.VOID;
                ts.storage_class = StorageClass.AUTO;
                this.define_var(name, ts);
                Node* d = this.mk(NodeKind.VARIABLE_DECLARATION, line, col);
                switch (this.failed)
                {
                    case (true) {
                    typespec_free(ts);
                    node_free(init);
                    -> d;
                }
                    default {};
                };
                d.text = name;
                d.ts = ts;
                d.a = init;
                -> d;
            };

            // destructuring_assignment -> 'auto' '{' (name ('as' type)?) (',' ...)* '}' '=' expression ('from' IDENTIFIER)?
            destructuring_assignment() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.AUTO);
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_BRACE); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                Node* n = this.mk(NodeKind.DESTRUCTURING_ASSIGNMENT, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                Node* v;
                byte* name;
                TypeSpec* ts;
                int vl, vc;
                while (!this.expect(TokenType.RIGHT_BRACE) & !this.expect(TokenType.EOF) & !this.failed)
                {
                    switch (this.expect(TokenType.IDENTIFIER))
                    {
                        case (true) {
                        vl = this.cur_line();
                        vc = this.cur_col();
                        name = this.cur_value();
                        this.advance();
                        switch (this.expect(TokenType.AS))
                        {
                            case (true) {
                            this.advance();
                            ts = this.type_spec();
                            switch (this.failed)
                            {
                                case (true) { typespec_free(ts); break; }
                                default {};
                            };
                            v = this.mk(NodeKind.VARIABLE_DECLARATION, vl, vc);
                            switch (this.failed)
                            {
                                case (true) { typespec_free(ts); break; }
                                default {};
                            };
                            v.text = name;
                            v.ts = ts;
                            n.flags = n.flags `| NF_EXPLICIT;
                        }
                            default {
                            v = this.mk(NodeKind.IDENTIFIER, vl, vc);
                            switch (this.failed)
                            {
                                case (true) { break; }
                                default {};
                            };
                            v.text = name;
                        };
                        };
                        node_push(n, 0, v);
                    }
                        default {};
                    };
                    switch (!this.expect(TokenType.RIGHT_BRACE))
                    {
                        case (true) {
                        switch (!this.consume(TokenType.COMMA))
                        {
                            case (true) { break; }
                            default {};
                        };
                    }
                        default {};
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.ASSIGN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) {
                    n.a = this.expression();
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) {
                    switch (this.expect(TokenType.FROM))
                    {
                        case (true) {
                        this.advance();
                        vl = this.cur_line();
                        vc = this.cur_col();
                        name = this.ident();
                        switch (!this.failed)
                        {
                            case (true) {
                            v = this.mk(NodeKind.IDENTIFIER, vl, vc);
                            switch (!this.failed)
                            {
                                case (true) {
                                v.text = name;
                                n.b = v;
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) {
                    node_free(n);
                    -> (Node*)0;
                }
                    default {};
                };
                -> n;
            };

            // ===== STATEMENTS =====

            // Frees n and returns null when a parse error was recorded, otherwise returns n
            done(Node* n) -> Node*
            {
                switch (this.failed)
                {
                    case (true) {
                    node_free(n);
                    -> (Node*)0;
                }
                    default {};
                };
                -> n;
            };

            // Moves nodes queued by a multi-statement construct into container.l<slot>
            drain_pending(Node* container, int slot) -> void
            {
                int k;
                while (k < this.pending.len)
                {
                    node_push(container, slot, this.pending.items[k]);
                    this.last_stmt = this.pending.items[k];
                    k++;
                };
                this.pending.len = 0;
                ->;
            };

            // Statements up to the closing '}' of an already opened body go to holder.l0
            statements_until_brace(Node* holder) -> void
            {
                Node* s;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        ->;
                    }
                        default {};
                    };
                    s = this.statement();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (s != (Node*)0)
                    {
                        case (true) {
                        node_push(holder, 0, s);
                        this.last_stmt = s;
                    }
                        default {};
                    };
                    this.drain_pending(holder, 0);
                };
                ->;
            };

            // block -> '{' statement* '}'
            block() -> Node*
            {
                Node* b = this.mk(NodeKind.BLOCK, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> b; }
                    default {};
                };
                this.consume(TokenType.LEFT_BRACE);
                switch (!this.failed)
                {
                    case (true) { this.statements_until_brace(b); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                -> this.done(b);
            };

            // block body of a loop: loop_depth is raised while it is parsed
            loop_block() -> Node*
            {
                this.loop_depth++;
                Node* b = this.block();
                this.loop_depth--;
                -> b;
            };

            // block_statement -> block (('if' '(' expression ')') ('else' block)? ';' | ';')
            block_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* body = this.block();
                switch (this.failed)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                Node* n;

                switch (this.expect(TokenType.IF))
                {
                    case (true) {
                    this.advance();
                    n = this.mk(NodeKind.IF_STATEMENT, line, col);
                    switch (this.failed)
                    {
                        case (true) { node_free(body); -> n; }
                        default {};
                    };
                    n.b = body;
                    this.consume(TokenType.LEFT_PAREN);
                    switch (!this.failed)
                    {
                        case (true) { n.a = this.expression(); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                    switch (!this.failed & this.expect(TokenType.ELSE))
                    {
                        case (true) {
                        this.advance();
                        n.c = this.block();
                    }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                    -> this.done(n);
                }
                    default {};
                };

                switch (this.expect(TokenType.LEFT_BRACE))
                {
                    case (true) {
                    node_free(body);
                    this.error(g"Unexpected block after block statement. Did you mean '{ ... } if (cond);'?\0");
                    -> (Node*)0;
                }
                    default {};
                };
                switch (!this.consume(TokenType.SEMICOLON))
                {
                    case (true) {
                    node_free(body);
                    -> (Node*)0;
                }
                    default {};
                };
                -> body;
            };

            // block_or_single_stmt -> block | '->' expression | expression   (no trailing ';')
            block_or_single_stmt() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                switch (this.expect(TokenType.LEFT_BRACE))
                {
                    case (true) { -> this.block(); }
                    default {};
                };
                Node* b = this.mk(NodeKind.BLOCK, line, col);
                switch (this.failed)
                {
                    case (true) { -> b; }
                    default {};
                };
                Node* s;
                switch (this.expect(TokenType.RETURN_ARROW))
                {
                    case (true) {
                    this.advance();
                    s = this.mk(NodeKind.RETURN_STATEMENT, line, col);
                }
                    default {
                    s = this.mk(NodeKind.EXPRESSION_STATEMENT, line, col);
                };
                };
                switch (this.failed)
                {
                    case (true) { node_free(b); -> s; }
                    default {};
                };
                node_push(b, 0, s);
                s.a = this.expression();
                -> this.done(b);
            };

            // if_statement -> 'if' '(' expr ')' body (('elif' | 'else' 'if') '(' expr ')' body)* ('else' body)? ';'
            if_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.IF_STATEMENT, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(TokenType.IF);
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { n.a = this.expression(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { n.b = this.block_or_single_stmt(); }
                    default {};
                };

                Node* c;
                while (!this.failed & (this.expect(TokenType.ELIF) |
                       (this.expect(TokenType.ELSE) & this.type_at(1) == TokenType.IF)))
                {
                    switch (this.expect(TokenType.ELIF))
                    {
                        case (true) { this.advance(); }
                        default {
                        this.advance();
                        this.advance();
                    };
                    };
                    this.consume(TokenType.LEFT_PAREN);
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    c = this.expression();
                    switch (this.failed)
                    {
                        case (true) { node_free(c); break; }
                        default {};
                    };
                    node_push(n, 0, c);
                    this.consume(TokenType.RIGHT_PAREN);
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    c = this.block_or_single_stmt();
                    switch (this.failed)
                    {
                        case (true) { node_free(c); break; }
                        default {};
                    };
                    node_push(n, 1, c);
                };

                switch (!this.failed & this.expect(TokenType.ELSE))
                {
                    case (true) {
                    this.advance();
                    n.c = this.block_or_single_stmt();
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // while_statement -> 'while' '(' expression ')' block ';'
            while_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.WHILE_LOOP, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(TokenType.WHILE);
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { n.a = this.expression(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { n.b = this.loop_block(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // do_while_statement -> 'do' block ('while' '(' expression ')' ';' | ';')
            do_while_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.DO);
                switch (this.failed)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                Node* body = this.loop_block();
                switch (this.failed)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                Node* n;
                switch (this.expect(TokenType.WHILE))
                {
                    case (true) {
                    this.advance();
                    n = this.mk(NodeKind.DO_WHILE_LOOP, line, col);
                    switch (this.failed)
                    {
                        case (true) { node_free(body); -> n; }
                        default {};
                    };
                    n.b = body;
                    this.consume(TokenType.LEFT_PAREN);
                    switch (!this.failed)
                    {
                        case (true) { n.a = this.expression(); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                    -> this.done(n);
                }
                    default {};
                };
                switch (this.expect(TokenType.SEMICOLON))
                {
                    case (true) {
                    this.advance();
                    n = this.mk(NodeKind.DO_LOOP, line, col);
                    switch (this.failed)
                    {
                        case (true) { node_free(body); -> n; }
                        default {};
                    };
                    n.b = body;
                    -> n;
                }
                    default {};
                };
                node_free(body);
                this.error(g"Expected 'while' or ';' after do block\0");
                -> (Node*)0;
            };

            // True when the tokens after 'for (' start a for-in header.
            // Sets destructure to 1 for the 'auto' forms.
            is_for_in(bool* destructure) -> bool
            {
                int m = this.mark();
                bool r = false;
                *destructure = false;
                switch (this.expect(TokenType.IDENTIFIER))
                {
                    case (true) {
                    this.advance();
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        switch (this.expect(TokenType.IDENTIFIER))
                        {
                            case (true) { this.advance(); }
                            default { break; };
                        };
                    };
                    switch (this.expect(TokenType.IN))
                    {
                        case (true) { r = true; }
                        default {};
                    };
                }
                    default {
                        switch (this.expect(TokenType.AUTO))
                        {
                            case (true) {
                    this.advance();
                    switch (this.expect(TokenType.LEFT_BRACE))
                    {
                        case (true) {
                        this.advance();
                        switch (this.expect(TokenType.IDENTIFIER))
                        {
                            case (true) {
                            this.advance();
                            while (this.expect(TokenType.COMMA))
                            {
                                this.advance();
                                switch (this.expect(TokenType.IDENTIFIER))
                                {
                                    case (true) { this.advance(); }
                                    default { break; };
                                };
                            };
                            switch (this.expect(TokenType.RIGHT_BRACE))
                            {
                                case (true) {
                                this.advance();
                                switch (this.expect(TokenType.IN))
                                {
                                    case (true) {
                                    r = true;
                                    *destructure = true;
                                }
                                    default {};
                                };
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {
                            switch (this.expect(TokenType.IDENTIFIER))
                            {
                                case (true) {
                        this.advance();
                        switch (this.expect(TokenType.IN))
                        {
                            case (true) {
                            r = true;
                            *destructure = true;
                        }
                            default {};
                        };
                    }
                                default {};
                            };
                        };
                    };
                }
                            default {};
                        };
                    };
                };
                this.reset(m);
                -> r;
            };

            // Pushes an IDENTIFIER node for the current identifier token onto n.l0
            loop_variable(Node* n) -> void
            {
                int line = this.cur_line();
                int col = this.cur_col();
                byte* name = this.ident();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                Node* v = this.mk(NodeKind.IDENTIFIER, line, col);
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                v.text = name;
                node_push(n, 0, v);
                ->;
            };

            // for_statement -> 'for' '(' (for_in | init ';' cond ';' update) ')' block ';'
            for_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.FOR);
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_PAREN); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };

                bool destructure;
                Node* n;
                switch (this.is_for_in(@destructure))
                {
                    case (true) {
                    n = this.mk(NodeKind.FOR_IN_LOOP, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    switch (destructure)
                    {
                        case (true) {
                        n.flags = NF_DESTRUCTURE;
                        this.consume(TokenType.AUTO);
                        switch (!this.failed & this.expect(TokenType.LEFT_BRACE))
                        {
                            case (true) {
                            this.advance();
                            this.loop_variable(n);
                            while (!this.failed & this.expect(TokenType.COMMA))
                            {
                                this.advance();
                                this.loop_variable(n);
                            };
                            switch (!this.failed)
                            {
                                case (true) { this.consume(TokenType.RIGHT_BRACE); }
                                default {};
                            };
                        }
                            default {
                                switch (!this.failed)
                                {
                                    case (true) {
                            this.loop_variable(n);
                        }
                                    default {};
                                };
                            };
                        };
                    }
                        default {
                        this.loop_variable(n);
                        while (!this.failed & this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            this.loop_variable(n);
                        };
                    };
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.IN); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { n.a = this.expression(); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { n.b = this.loop_block(); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                    -> this.done(n);
                }
                    default {};
                };

                // C style
                n = this.mk(NodeKind.FOR_LOOP, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                Node* s;
                int sl, sc;
                switch (!this.expect(TokenType.SEMICOLON))
                {
                    case (true) {
                    switch (this.is_variable_declaration())
                    {
                        case (true) {
                        this.in_for_init = true;
                        s = this.variable_declaration();
                        this.in_for_init = false;
                        switch (!this.failed)
                        {
                            case (true) {
                            switch (this.pending.len > 0)
                            {
                                case (true) {
                                // several declarations are wrapped in a block
                                Node* wrap = this.mk(NodeKind.BLOCK, line, col);
                                switch (!this.failed)
                                {
                                    case (true) {
                                    node_push(wrap, 0, s);
                                    this.drain_pending(wrap, 0);
                                    n.a = wrap;
                                }
                                    default {};
                                };
                            }
                                default {
                                n.a = s;
                            };
                            };
                        }
                            default {};
                        };
                    }
                        default {
                        sl = this.cur_line();
                        sc = this.cur_col();
                        s = this.mk(NodeKind.EXPRESSION_STATEMENT, sl, sc);
                        switch (!this.failed)
                        {
                            case (true) {
                            s.a = this.expression();
                            n.a = s;
                        }
                            default {};
                        };
                    };
                    };
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (!this.failed & !this.expect(TokenType.SEMICOLON))
                {
                    case (true) { n.b = this.expression(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (!this.failed & !this.expect(TokenType.RIGHT_PAREN))
                {
                    case (true) {
                    sl = this.cur_line();
                    sc = this.cur_col();
                    s = this.mk(NodeKind.EXPRESSION_STATEMENT, sl, sc);
                    switch (!this.failed)
                    {
                        case (true) {
                        s.a = this.expression();
                        n.c = s;
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { n.d = this.loop_block(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // switch_case -> 'case' '(' expression ')' block | 'default' block ';'
            switch_case() -> Node*
            {
                Node* n = this.mk(NodeKind.CASE, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                switch (this.expect(TokenType.CASE))
                {
                    case (true) {
                    this.advance();
                    this.consume(TokenType.LEFT_PAREN);
                    switch (!this.failed)
                    {
                        case (true) { n.a = this.expression(); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { n.b = this.block(); }
                        default {};
                    };
                }
                    default {
                        switch (this.expect(TokenType.DEFAULT))
                        {
                            case (true) {
                    this.advance();
                    n.b = this.block();
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                }
                            default {
                    this.error(g"Expected 'case' or 'default'\0");
                };
                        };
                    };
                };
                -> this.done(n);
            };

            // switch_statement -> 'switch' '(' expression ')' '{' switch_case* '}' ';'
            switch_statement() -> Node*
            {
                int start = this.mark();
                Node* n = this.mk(NodeKind.SWITCH_STATEMENT, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(TokenType.SWITCH);
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { n.a = this.expression(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_BRACE); }
                    default {};
                };
                Node* c;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    }
                        default {};
                    };
                    c = this.switch_case();
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    node_push(n, 0, c);
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(n); }
                    default {};
                };

                // A tagged union switch (v.#) is checked exhaustively later and needs no default.
                bool tagged = false;
                switch (n.a != (Node*)0)
                {
                    case (true) {
                    switch (n.a.kind == NodeKind.MEMBER_ACCESS & n.a.text != (byte*)0)
                    {
                        case (true) {
                        tagged = n.a.text[0] == '#' & n.a.text[1] == 0;
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (!tagged)
                {
                    case (true) {
                    bool has_default = false;
                    Node* cs;
                    int i;
                    int cnt = node_count(n, 0);
                    while (i < cnt)
                    {
                        cs = node_child(n, 0, i);
                        switch (cs.a == (Node*)0)
                        {
                            case (true) { has_default = true; }
                            default {};
                        };
                        i++;
                    };
                    switch (!has_default)
                    {
                        case (true) {
                        int here = this.mark();
                        this.reset(start);
                        this.error(g"Switch statement requires a default case\0");
                        this.reset(here);
                        -> this.done(n);
                    }
                        default {};
                    };
                }
                    default {};
                };
                -> n;
            };

            // try_statement -> 'try' block ('catch' '(' (')' | ('auto' | type) IDENTIFIER ')') block)* ';'
            try_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.TRY_BLOCK, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(TokenType.TRY);
                switch (!this.failed)
                {
                    case (true) { n.a = this.block(); }
                    default {};
                };
                Node* c;
                while (!this.failed & this.expect(TokenType.CATCH))
                {
                    c = this.mk(NodeKind.CATCH_CLAUSE, this.cur_line(), this.cur_col());
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    node_push(n, 0, c);
                    this.advance();
                    this.consume(TokenType.LEFT_PAREN);
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    switch (this.expect(TokenType.RIGHT_PAREN))
                    {
                        case (true) {
                        this.advance();
                        c.a = this.block();
                    }
                        default {
                        switch (this.expect(TokenType.AUTO))
                        {
                            case (true) { this.advance(); }
                            default { c.ts = this.type_spec(); };
                        };
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        c.text = this.ident();
                        switch (!this.failed)
                        {
                            case (true) { this.consume(TokenType.RIGHT_PAREN); }
                            default {};
                        };
                        switch (!this.failed)
                        {
                            case (true) { c.a = this.block(); }
                            default {};
                        };
                    };
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // 'return' expression? ';'   and   '->' expression? ';'
            return_node(int tok) -> Node*
            {
                Node* n = this.mk(NodeKind.RETURN_STATEMENT, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(tok);
                switch (!this.failed & !this.expect(TokenType.SEMICOLON))
                {
                    case (true) { n.a = this.expression(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            return_statement() -> Node* -> this.return_node(TokenType.RETURN);

            return_arrow_ret() -> Node* -> this.return_node(TokenType.RETURN_ARROW);

            // 'error' (';' | expression ';' | '->' expression ';' | 'return' expression ';')
            error_return_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.ERROR_RETURN_STATEMENT, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.advance();
                switch (this.expect(TokenType.RETURN_ARROW) | this.expect(TokenType.RETURN))
                {
                    case (true) {
                    this.advance();
                    n.a = this.expression();
                }
                    default {
                        switch (!this.expect(TokenType.SEMICOLON))
                        {
                            case (true) {
                    n.a = this.expression();
                }
                            default {};
                        };
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // 'break' ('switch')? ';'
            break_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.BREAK);
                switch (this.failed)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                int kind = NodeKind.BREAK_STATEMENT;
                switch (this.expect(TokenType.SWITCH))
                {
                    case (true) {
                    kind = NodeKind.BREAK_SWITCH_STATEMENT;
                    this.advance();
                }
                    default {};
                };
                switch (!this.consume(TokenType.SEMICOLON))
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                -> this.mk(kind, line, col);
            };

            // 'continue' ';'
            continue_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.CONTINUE);
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                -> this.mk(NodeKind.CONTINUE_STATEMENT, line, col);
            };

            // 'noreturn' ';'
            noreturn_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.NORET);
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                -> this.mk(NodeKind.NORETURN_STATEMENT, line, col);
            };

            // 'label' IDENTIFIER ':'
            label_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.LABEL_STATEMENT, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(TokenType.LABEL);
                switch (!this.failed & this.loop_depth > 0)
                {
                    case (true) {
                    this.error(g"'label' is not permitted inside a loop body\0");
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { n.text = this.ident(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.COLON); }
                    default {};
                };
                -> this.done(n);
            };

            // 'goto' IDENTIFIER ';'
            goto_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.GOTO_STATEMENT, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(TokenType.GOTO);
                switch (!this.failed)
                {
                    case (true) { n.text = this.ident(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // 'kw' expression ';' with the expression in slot a
            keyword_expr_statement(int tok, int kind) -> Node*
            {
                Node* n = this.mk(kind, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(tok);
                switch (!this.failed)
                {
                    case (true) { n.a = this.expression(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            jump_statement() -> Node* -> this.keyword_expr_statement(TokenType.JUMP, NodeKind.JUMP_STATEMENT);

            escape_statement() -> Node* -> this.keyword_expr_statement(TokenType.ESCAPE_KW, NodeKind.ESCAPE_STATEMENT);

            // 'throw' '(' expression ')' ';'
            throw_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.THROW_STATEMENT, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(TokenType.THROW);
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { n.a = this.expression(); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // 'assert' '(' expression (',' (STRING_LITERAL | F_STRING | I_STRING))? ')' ';'
            assert_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.ASSERT_STATEMENT, line, col);
                Node* msg;
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(TokenType.ASSERT);
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { n.a = this.expression(); }
                    default {};
                };
                switch (!this.failed & this.expect(TokenType.COMMA))
                {
                    case (true) {
                    this.advance();
                    switch (this.expect(TokenType.F_STRING) | this.expect(TokenType.I_STRING))
                    {
                        case (true) {
                        // reported through note_feat and kept as a stub node
                        n.b = this.primary_expression();
                    }
                        default {
                            switch (this.expect(TokenType.STRING_LITERAL))
                            {
                                case (true) {
                        msg = this.mk(NodeKind.STRING_LITERAL, this.cur_line(), this.cur_col());
                        switch (!this.failed)
                        {
                            case (true) {
                            msg.text = this.cur_value();
                            n.b = msg;
                            this.advance();
                        }
                            default {};
                        };
                    }
                                default {
                        this.fail_expected(TokenType.STRING_LITERAL);
                    };
                            };
                        };
                    };
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // 'defer' (expression | '{' statement* '}') ';'
            defer_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.DEFER_STATEMENT, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(TokenType.DEFER);
                switch (!this.failed & this.expect(TokenType.LEFT_BRACE))
                {
                    case (true) {
                    this.advance();
                    n.flags = NF_HAS_BODY;
                    this.statements_until_brace(n);
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_BRACE); }
                        default {};
                    };
                }
                    default {
                        switch (!this.failed)
                        {
                            case (true) {
                    n.a = this.expression();
                }
                            default {};
                        };
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // 'fluxvm' FLUXVM_BLOCK ';'
            fluxvm_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.FLUXVM_BLOCK, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.consume(TokenType.FLUXVM);
                switch (!this.failed & this.expect(TokenType.FLUXVM_BLOCK))
                {
                    case (true) {
                    n.text = this.cur_value();
                    this.advance();
                }
                    default {
                        switch (!this.failed)
                        {
                            case (true) {
                    this.fail_expected(TokenType.FLUXVM_BLOCK);
                }
                            default {};
                        };
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // #"; repeats the previous statement
            ditto_statement() -> Node*
            {
                this.advance();
                switch (!this.consume(TokenType.SEMICOLON))
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                switch (this.last_stmt == (Node*)0)
                {
                    case (true) {
                    this.error(g"Ditto operator '#\"' used as a statement before any preceding statement to repeat\0");
                    -> (Node*)0;
                }
                    default {};
                };
                Node* d = node_clone(this.last_stmt);
                switch (d == (Node*)0)
                {
                    case (true) {
                    this.fail_alloc();
                    -> d;
                }
                    default {};
                };
                this.last_stmt = d;
                -> d;
            };

            // ===== INLINE ASSEMBLY =====

            // Operand list: "constraint"(tokens) joined by ','. Ends before ':' or ';'.
            asm_operands() -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                int count, depth, start;
                while (!this.expect2(TokenType.COLON, TokenType.SEMICOLON))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.SEMICOLON);
                        -> (byte*)0;
                    }
                        default {};
                    };
                    switch (this.expect(TokenType.STRING_LITERAL))
                    {
                        case (true) {
                        start = this.sb.len;
                        switch (count > 0)
                        {
                            case (true) { this.sb.put(',' ); }
                            default {};
                        };
                        this.sb.put('"');
                        this.sb.put_n(this.cur_value(), this.cur_value_len());
                        this.sb.put('"');
                        this.advance();
                        switch (this.expect(TokenType.LEFT_PAREN))
                        {
                            case (true) {
                            this.advance();
                            this.sb.put('(');
                            depth = 1;
                            while (depth > 0 & !this.expect(TokenType.EOF))
                            {
                                switch (this.expect(TokenType.LEFT_PAREN))
                                {
                                    case (true) { depth++; }
                                    default {
                                        switch (this.expect(TokenType.RIGHT_PAREN))
                                        {
                                            case (true) { depth--; }
                                            default {};
                                        };
                                    };
                                };
                                switch (depth > 0)
                                {
                                    case (true) { this.sb.put_n(this.cur_value(), this.cur_value_len()); }
                                    default {};
                                };
                                this.advance();
                            };
                            this.sb.put(')');
                            count++;
                        }
                            default {
                            this.sb.len = start;
                        };
                        };
                        switch (this.expect(TokenType.COMMA))
                        {
                            case (true) { this.advance(); }
                            default {};
                        };
                    }
                        default {
                        this.advance();
                    };
                    };
                };
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            // Clobber list: "reg" (',' "reg")* up to ';'
            asm_clobbers() -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                int count;
                while (!this.expect(TokenType.SEMICOLON))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.SEMICOLON);
                        -> (byte*)0;
                    }
                        default {};
                    };
                    switch (this.expect(TokenType.STRING_LITERAL))
                    {
                        case (true) {
                        switch (count > 0)
                        {
                            case (true) { this.sb.put(','); }
                            default {};
                        };
                        this.sb.put('"');
                        this.sb.put_n(this.cur_value(), this.cur_value_len());
                        this.sb.put('"');
                        count++;
                        this.advance();
                        switch (this.expect(TokenType.COMMA))
                        {
                            case (true) { this.advance(); }
                            default {};
                        };
                    }
                        default {
                        this.advance();
                    };
                    };
                };
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            // asm_statement -> ('volatile')? 'asm' ASM_BLOCK (':' operands)? (':' operands)? (':' clobbers)? ';'
            // EXPRESSION_STATEMENT holding an INLINE_ASM (text = body, text2 = constraints)
            asm_statement(bool is_volatile) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.EXPRESSION_STATEMENT, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                Node* a = this.mk(NodeKind.INLINE_ASM, line, col);
                switch (this.failed)
                {
                    case (true) { node_free(n); -> a; }
                    default {};
                };
                n.a = a;
                switch (!is_volatile & this.expect(TokenType.VOLATILE))
                {
                    case (true) {
                    is_volatile = true;
                    this.advance();
                }
                    default {};
                };
                switch (is_volatile)
                {
                    case (true) { a.flags = NF_VOLATILE; }
                    default {};
                };
                switch (!this.consume(TokenType.ASM))
                {
                    case (true) { -> this.done(n); }
                    default {};
                };
                switch (!this.expect(TokenType.ASM_BLOCK))
                {
                    case (true) {
                    this.fail_expected(TokenType.ASM_BLOCK);
                    -> this.done(n);
                }
                    default {};
                };
                a.text = this.cur_value();
                this.advance();

                byte* outs = g"\0";
                byte* ins = g"\0";
                byte* clob = g"\0";
                switch (!this.expect(TokenType.SEMICOLON))
                {
                    case (true) {
                    switch (this.expect(TokenType.COLON))
                    {
                        case (true) {
                        this.advance();
                        outs = this.asm_operands();
                    }
                        default {};
                    };
                    switch (!this.failed & this.expect(TokenType.COLON))
                    {
                        case (true) {
                        this.advance();
                        ins = this.asm_operands();
                    }
                        default {};
                    };
                    switch (!this.failed & this.expect(TokenType.COLON))
                    {
                        case (true) {
                        this.advance();
                        clob = this.asm_clobbers();
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(n); }
                    default {};
                };
                switch (!this.consume(TokenType.SEMICOLON))
                {
                    case (true) { -> this.done(n); }
                    default {};
                };

                byte* cons = g"\0";
                switch (outs[0] != 0 | ins[0] != 0 | clob[0] != 0)
                {
                    case (true) {
                    cons = outs;
                    switch (ins[0] != 0 | clob[0] != 0)
                    {
                        case (true) {
                        cons = this.cat2(this.cat2(cons, g":\0"), ins);
                        switch (clob[0] != 0)
                        {
                            case (true) { cons = this.cat2(this.cat2(cons, g":\0"), clob); }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                a.text2 = cons;
                -> n;
            };

            // ===== FUNCTIONS =====

            // Text of a calling convention token
            cc_text(int t) -> byte*
            {
                switch (t == TokenType.CDECL)
                {
                    case (true) { -> g"cdecl\0"; }
                    default {};
                };
                switch (t == TokenType.STDCALL)
                {
                    case (true) { -> g"stdcall\0"; }
                    default {};
                };
                switch (t == TokenType.FASTCALL)
                {
                    case (true) { -> g"fastcall\0"; }
                    default {};
                };
                switch (t == TokenType.THISCALL)
                {
                    case (true) { -> g"thiscall\0"; }
                    default {};
                };
                -> g"vectorcall\0";
            };

            // Function name for messages
            fn_label(Node* f) -> byte*
            {
                switch (f.text != (byte*)0)
                {
                    case (true) { -> f.text; }
                    default {};
                };
                -> g"$\0";
            };

            // ----- effect expressions (inside '# effect { }' and '# attenuate { }') -----

            effect_bin(byte* op, Node* l, Node* r, int line, int col) -> Node*
            {
                Node* n = this.mk(NodeKind.EFFECT_EXPR, line, col);
                switch (this.failed)
                {
                    case (true) {
                    node_free(l);
                    node_free(r);
                    -> n;
                }
                    default {};
                };
                n.text = op;
                n.a = l;
                n.b = r;
                -> n;
            };

            // Prefix operator spanning skip tokens followed by its operand
            effect_prefix(byte* op, int skip, int line, int col) -> Node*
            {
                int i;
                while (i < skip)
                {
                    this.advance();
                    i++;
                };
                Node* n = this.mk(NodeKind.EFFECT_EXPR, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                n.text = op;
                n.a = this.effect_unary();
                -> this.done(n);
            };

            effect_primary() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n;
                Node* e;
                byte* name;
                byte* sub;

                switch (this.expect(TokenType.LEFT_PAREN))
                {
                    case (true) {
                    this.advance();
                    e = this.effect_expr();
                    switch (this.failed)
                    {
                        case (true) { -> e; }
                        default {};
                    };
                    switch (!this.consume(TokenType.RIGHT_PAREN))
                    {
                        case (true) {
                        node_free(e);
                        -> (Node*)0;
                    }
                        default {};
                    };
                    -> e;
                }
                    default {};
                };
                switch (this.expect(TokenType.LEFT_BRACKET))
                {
                    case (true) {
                    this.advance();
                    e = this.effect_expr();
                    switch (this.failed)
                    {
                        case (true) { -> e; }
                        default {};
                    };
                    switch (!this.consume(TokenType.RIGHT_BRACKET))
                    {
                        case (true) {
                        node_free(e);
                        -> (Node*)0;
                    }
                        default {};
                    };
                    -> e;
                }
                    default {};
                };
                switch (this.expect(TokenType.MULTIPLY))
                {
                    case (true) {
                    this.advance();
                    switch (!this.consume(TokenType.DOT))
                    {
                        case (true) { -> (Node*)0; }
                        default {};
                    };
                    switch (!this.expect(TokenType.MULTIPLY))
                    {
                        case (true) {
                        this.error(g"Expected '*' after '*.' in wildcard effect expression\0");
                        -> (Node*)0;
                    }
                        default {};
                    };
                    this.advance();
                    n = this.mk(NodeKind.EFFECT_NAME, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    n.text = g"*.*\0";
                    -> n;
                }
                    default {};
                };
                switch (this.expect2(TokenType.IDENTIFIER, TokenType.EFFECT))
                {
                    case (true) {
                    name = this.cur_value();
                    this.advance();
                    while (this.expect(TokenType.DOT))
                    {
                        this.advance();
                        switch (this.expect(TokenType.MULTIPLY))
                        {
                            case (true) {
                            this.advance();
                            name = this.cat2(name, g".*\0");
                            break;
                        }
                            default {};
                        };
                        switch (!this.expect(TokenType.IDENTIFIER))
                        {
                            case (true) {
                            this.error(g"Expected identifier or '*' after '.' in effect name\0");
                            -> (Node*)0;
                        }
                            default {};
                        };
                        sub = this.cur_value();
                        this.advance();
                        name = this.cat2(this.cat2(name, g".\0"), sub);
                    };
                    n = this.mk(NodeKind.EFFECT_NAME, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> n; }
                        default {};
                    };
                    n.text = name;
                    -> n;
                }
                    default {};
                };
                this.error(g"Expected effect expression (identifier, unary operator, or grouped expression)\0");
                -> (Node*)0;
            };

            effect_unary() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                switch (this.expect(TokenType.NOT) & this.type_at(1) == TokenType.ADDRESS_OF)
                {
                    case (true) {
                    -> this.effect_prefix(g"!@\0", 2, line, col);
                }
                    default {};
                };
                switch (this.expect(TokenType.NOT))
                {
                    case (true) { -> this.effect_prefix(g"!\0", 1, line, col); }
                    default {};
                };
                switch (this.expect(TokenType.MULTIPLY) & this.type_at(1) != TokenType.DOT)
                {
                    case (true) {
                    -> this.effect_prefix(g"*\0", 1, line, col);
                }
                    default {};
                };
                switch (this.expect(TokenType.TIE))
                {
                    case (true) { -> this.effect_prefix(g"~\0", 1, line, col); }
                    default {};
                };
                switch (this.expect(TokenType.QUESTION))
                {
                    case (true) { -> this.effect_prefix(g"?\0", 1, line, col); }
                    default {};
                };
                switch (this.expect(TokenType.ADDRESS_OF))
                {
                    case (true) { -> this.effect_prefix(g"@\0", 1, line, col); }
                    default {};
                };
                switch (this.expect(TokenType.ELLIPSIS))
                {
                    case (true) { -> this.effect_prefix(g"...\0", 1, line, col); }
                    default {};
                };
                switch (this.expect(TokenType.RANGE))
                {
                    case (true) { -> this.effect_prefix(g"..\0", 1, line, col); }
                    default {};
                };
                switch (this.expect(TokenType.EXPONENT) & this.type_at(1) != TokenType.LOGICAL_OR)
                {
                    case (true) {
                    -> this.effect_prefix(g"^suppress\0", 1, line, col);
                }
                    default {};
                };
                switch (this.expect(TokenType.LESS_THAN) & this.type_at(1) == TokenType.MULTIPLY)
                {
                    case (true) {
                    -> this.effect_prefix(g"<*\0", 2, line, col);
                }
                    default {};
                };
                -> this.effect_primary();
            };

            // <-> mutual implication (lexes as '<-' then '>')
            effect_mutual() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* left = this.effect_unary();
                Node* right;
                while (!this.failed & this.expect(TokenType.CHAIN_ARROW) & this.type_at(1) == TokenType.GREATER_THAN)
                {
                    this.advance();
                    this.advance();
                    right = this.effect_unary();
                    left = this.effect_bin(g"<->\0", left, right, line, col);
                };
                -> left;
            };

            effect_xor() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* left = this.effect_mutual();
                Node* right;
                while (!this.failed & this.expect(TokenType.XOR_OP))
                {
                    this.advance();
                    right = this.effect_mutual();
                    left = this.effect_bin(g"^|\0", left, right, line, col);
                };
                -> left;
            };

            effect_implies() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* left = this.effect_xor();
                Node* right;
                while (!this.failed & this.expect(TokenType.RETURN_ARROW))
                {
                    this.advance();
                    right = this.effect_xor();
                    left = this.effect_bin(g"->\0", left, right, line, col);
                };
                -> left;
            };

            effect_priority() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* left = this.effect_implies();
                Node* right;
                while (!this.failed & this.expect(TokenType.GREATER_THAN))
                {
                    this.advance();
                    right = this.effect_implies();
                    left = this.effect_bin(g">\0", left, right, line, col);
                };
                -> left;
            };

            effect_and() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* left = this.effect_priority();
                Node* right;
                while (!this.failed & this.expect(TokenType.LOGICAL_AND))
                {
                    this.advance();
                    right = this.effect_priority();
                    left = this.effect_bin(g"&\0", left, right, line, col);
                };
                -> left;
            };

            // effect_expr -> and ('|' and)*   (lowest precedence)
            effect_expr() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* left = this.effect_and();
                Node* right;
                while (!this.failed & this.expect(TokenType.LOGICAL_OR))
                {
                    this.advance();
                    right = this.effect_and();
                    left = this.effect_bin(g"|\0", left, right, line, col);
                };
                -> left;
            };

            // '{' effect_expr '}' wrapped in an annotation node of the given kind
            effect_annotation(int kind) -> Node*
            {
                Node* n = this.mk(kind, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.advance();
                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) {
                    node_free(n);
                    -> (Node*)0;
                }
                    default {};
                };
                n.a = this.effect_expr();
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                -> this.done(n);
            };

            // ('#' ('deprecate' | 'effect' '{' .. '}' | 'attenuate' '{' .. '}'))*
            fn_tags(Node* f) -> void
            {
                while (!this.failed & this.expect(TokenType.TAG))
                {
                    this.advance();
                    switch (this.expect(TokenType.DEPRECATE))
                    {
                        case (true) {
                        this.advance();
                        f.flags = f.flags `| NF_DEPRECATED;
                    }
                        default {
                            switch (this.expect(TokenType.EFFECT))
                            {
                                case (true) {
                        node_free(f.b);
                        f.b = this.effect_annotation(NodeKind.EFFECT_ANNOTATION);
                    }
                                default {
                                    switch (this.expect(TokenType.IDENTIFIER) & this.val_is(g"attenuate\0", 9))
                                    {
                                        case (true) {
                        node_free(f.c);
                        f.c = this.effect_annotation(NodeKind.ATTENUATE_ANNOTATION);
                    }
                                        default {
                        this.error(g"Expected 'deprecate', 'effect', or 'attenuate' after '#'\0");
                    };
                                    };
                                };
                            };
                        };
                    };
                };
                ->;
            };

            // ----- parameters -----

            // parameter -> '...' | type_spec IDENTIFIER? ('=' expression)?
            // The variadic sentinel is a PARAMETER with ival = 1.
            parameter(Node* f) -> void
            {
                Node* p = this.mk(NodeKind.PARAMETER, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                node_push(f, 0, p);
                switch (this.expect(TokenType.ELLIPSIS))
                {
                    case (true) {
                    this.advance();
                    p.ival = 1;
                    ->;
                }
                    default {};
                };
                p.ts = this.type_spec();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (this.expect(TokenType.IDENTIFIER))
                {
                    case (true) {
                    p.text = this.cur_value();
                    this.advance();
                    switch (this.expect(TokenType.ASSIGN))
                    {
                        case (true) {
                        this.advance();
                        p.a = this.expression();
                    }
                        default {};
                    };
                }
                    default {};
                };
                ->;
            };

            parameter_list(Node* f) -> void
            {
                this.parameter(f);
                while (!this.failed & this.expect(TokenType.COMMA))
                {
                    this.advance();
                    this.parameter(f);
                };
                ->;
            };

            // Removes the variadic sentinel and sets NF_VARIADIC
            strip_variadic(Node* f) -> void
            {
                switch (f.l0 == (NodeVec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                int i, j;
                Node* p;
                while (i < f.l0.len)
                {
                    p = f.l0.items[i];
                    switch (p.ival)
                    {
                        case (1)
                        {
                            node_free(p);
                            f.flags = f.flags `| NF_VARIADIC;
                        }
                        default
                        {
                            f.l0.items[j] = p;
                            j++;
                        };
                    };
                    i++;
                };
                f.l0.len = j;
                ->;
            };

            param_count(Node* f) -> int
            {
                switch (f.l0 == (NodeVec*)0)
                {
                    case (true) { -> 0; }
                    default {};
                };
                -> f.l0.len;
            };

            // ----- function pointers -----

            // '(' type_spec (',' type_spec)* ')' '->' type_spec
            function_pointer_type(byte* conv) -> TypeSpec*
            {
                TypeSpec* t = typespec_new();
                switch (t == (TypeSpec*)0)
                {
                    case (true) {
                    this.fail_alloc();
                    -> t;
                }
                    default {};
                };
                t.base_type = DataType.FUNC_PTR;
                t.calling_conv = conv;
                PtrVec* tmp = pv_new();
                TypeSpec* p;
                int i;
                switch (this.consume(TokenType.LEFT_PAREN))
                {
                    case (true) {
                    switch (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        case (true) {
                        p = this.type_spec();
                        pv_push(tmp, (void*)p);
                        while (!this.failed & this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            p = this.type_spec();
                            pv_push(tmp, (void*)p);
                        };
                    }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RETURN_ARROW); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { t.fp_ret = this.type_spec(); }
                        default {};
                    };
                }
                    default {};
                };
                switch (tmp.len > 0)
                {
                    case (true) {
                    t.fp_params = (TypeSpec**)fmalloc((u64)(tmp.len + 1) * (u64)((sizeof(TypeSpec*) + 7) / 8));
                    while (i < tmp.len)
                    {
                        t.fp_params[i] = (TypeSpec*)tmp.items[i];
                        i++;
                    };
                    t.fp_nparams = tmp.len;
                }
                    default {};
                };
                pv_free(tmp);
                -> t;
            };

            // name function_pointer_type ('=' ('@' name ('.' member)* | expression))?
            fp_one(byte* conv) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.FUNCTION_POINTER_DECLARATION, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                Node* addr;
                Node* e;
                Node* m;
                n.text = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.done(n); }
                    default {};
                };
                n.ts = this.function_pointer_type(conv);
                switch (this.failed)
                {
                    case (true) { -> this.done(n); }
                    default {};
                };

                switch (this.expect(TokenType.ASSIGN))
                {
                    case (true) {
                    this.advance();
                    switch (this.expect(TokenType.ADDRESS_OF))
                    {
                        case (true) {
                        addr = this.mk(NodeKind.ADDRESS_OF, this.cur_line(), this.cur_col());
                        switch (this.failed)
                        {
                            case (true) { -> this.done(n); }
                            default {};
                        };
                        n.a = addr;
                        this.advance();
                        e = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                        switch (this.failed)
                        {
                            case (true) { -> this.done(n); }
                            default {};
                        };
                        addr.a = e;
                        switch (this.expect(TokenType.STRING_LITERAL))
                        {
                            case (true) {
                            e.text = this.cur_value();
                            this.advance();
                        }
                            default {
                            e.text = this.ident();
                        };
                        };
                        while (!this.failed & this.expect(TokenType.DOT))
                        {
                            this.advance();
                            m = this.mk(NodeKind.MEMBER_ACCESS, this.cur_line(), this.cur_col());
                            switch (this.failed)
                            {
                                case (true) { -> this.done(n); }
                                default {};
                            };
                            m.a = e;
                            addr.a = m;
                            e = m;
                            e.text = this.ident();
                        };
                    }
                        default {
                        n.a = this.expression();
                    };
                    };
                }
                    default {};
                };
                -> this.done(n);
            };

            // 'def{}*' (already consumed) fp_one (',' fp_one)* ';'
            function_pointer_declaration(byte* conv) -> Node*
            {
                switch (this.loop_depth > 0 & !this.in_for_init)
                {
                    case (true) {
                    this.warn_here(g"pointer declaration inside a loop body, this will continually allocate new slots on the stack each iteration.\0");
                }
                    default {};
                };
                Node* first = this.fp_one(conv);
                switch (this.failed)
                {
                    case (true) { -> first; }
                    default {};
                };
                Node* x;
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    x = this.fp_one(conv);
                    switch (this.failed)
                    {
                        case (true) {
                        node_free(first);
                        -> x;
                    }
                        default {};
                    };
                    nv_push(this.pending, x);
                };
                switch (!this.consume(TokenType.SEMICOLON))
                {
                    case (true) {
                    node_free(first);
                    -> (Node*)0;
                }
                    default {};
                };
                -> first;
            };

            // ----- function definitions -----

            // Abandons the construct being parsed (starting at mark m), reports the unsupported
            // feature and skips it. Returns a stub node of the given kind, or null when keep is false
            // (fparser.py returns None for template constructs).
            skip_unsupported(int m, int feat, Node* partial, int kind, bool keep) -> Node*
            {
                int line = partial.line;
                int col = partial.col;
                node_free(partial);
                this.pending.len = 0;
                this.reset(m);
                this.last_stmt = (Node*)0;
                this.last_call = (Node*)0;
                this.note_feat(feat);
                this.skip_construct();
                switch (!keep)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                Node* stub_node = this.mk(kind, line, col);
                switch (this.failed)
                {
                    case (true) { -> stub_node; }
                    default {};
                };
                stub_node.flags = NF_STUB;
                -> stub_node;
            };

            func_unsupported(int m, int feat, Node* partial) -> Node* -> this.skip_unsupported(m, feat, partial, NodeKind.FUNCTION_DEF, feat != Feat.TEMPLATE_FUNCTION);

            // Marks f as a prototype with an empty body
            mark_proto(Node* f) -> void
            {
                f.flags = f.flags `| NF_PROTOTYPE;
                f.a = this.mk(NodeKind.BLOCK, f.line, f.col);
                ->;
            };

            // The f-string or i-string token at the cursor as a node
            fstr_node() -> Node*
            {
                switch (this.expect(TokenType.F_STRING))
                {
                    case (true) { -> this.f_string_node(); }
                    default {};
                };
                -> this.i_string_node();
            };

            // Text of an f-string node when every part is text or a known compile-time string
            // (fparser._resolve_fstring_name), otherwise null
            fstr_resolve(Node* fl) -> byte*
            {
                Node* p;
                byte* val;
                int k, cnt;
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                cnt = node_count(fl, 0);
                while (k < cnt)
                {
                    p = node_child(fl, 0, k);
                    k++;
                    switch (p.kind)
                    {
                        case (NodeKind.STRING_LITERAL)
                        {
                            this.sb.put_str(p.text);
                        }
                        case (NodeKind.IDENTIFIER)
                        {
                            val = (byte*)nm_get(this.cstrs, p.text);
                            switch (val == (byte*)0)
                            {
                                case (true) { -> (byte*)0; }
                                default {};
                            };
                            this.sb.put_str(val);
                        }
                        default { -> (byte*)0; };
                    };
                };
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            // IDENTIFIER | STRING_LITERAL | STRINGIFY name of f
            fn_name(Node* f) -> void
            {
                Node* fs;
                switch (this.expect(TokenType.STRING_LITERAL))
                {
                    case (true) {
                    f.text = this.cur_value();
                    this.advance();
                }
                    default {
                        switch (this.expect2(TokenType.F_STRING, TokenType.I_STRING))
                        {
                            case (true) {
                    fs = this.fstr_node();
                    switch (!this.failed)
                    {
                        case (true) {
                        f.text = this.fstr_resolve(fs);
                        switch (f.text == (byte*)0)
                        {
                            case (true) { f.d = fs; }
                            default { node_free(fs); };
                        };
                    }
                        default {};
                    };
                }
                            default {
                                switch (this.expect(TokenType.STRINGIFY))
                                {
                                    case (true) {
                    f.d = this.stringify_expr();
                }
                                    default {
                                        switch (this.expect(TokenType.IDENTIFIER))
                                        {
                                            case (true) {
                    f.text = this.cur_value();
                    this.advance();
                }
                                            default {
                    this.fail_expected(TokenType.IDENTIFIER);
                };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
                ->;
            };

            // Return type and optional '^|' error type
            fn_return(Node* f, bool is_cdecl) -> void
            {
                f.ts = this.type_spec();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (this.expect(TokenType.XOR_OP))
                {
                    case (true) {
                    switch (is_cdecl)
                    {
                        case (true) {
                        this.error(this.cat2(this.cat2(g"Function '\0", this.fn_label(f)), g"' declared with 'cdecl' cannot have a dual return type: a C ABI function can only return a single value\0"));
                        ->;
                    }
                        default {};
                    };
                    this.advance();
                    f.ts2 = this.type_spec();
                }
                    default {};
                };
                ->;
            };

            // Checks a definition, opens its scope and defines the parameters.
            // Returns false with an error recorded.
            begin_body(Node* f) -> bool
            {
                int i;
                Node* p;
                while (i < this.param_count(f))
                {
                    switch (f.l0.items[i].text == (byte*)0)
                    {
                        case (true) {
                        this.error(g"Function definition requires parameter names, but a parameter has no name\0");
                        -> false;
                    }
                        default {};
                    };
                    i++;
                };
                switch (this.function_depth > 0)
                {
                    case (true) {
                    this.error(this.cat2(this.cat2(g"Illegal nested function definition '\0", this.fn_label(f)), g"': function definitions are not allowed inside another function body\0"));
                    -> false;
                }
                    default {};
                };
                switch (this.st != (FXC_SYMTABLE*)0)
                {
                    case (true) {
                    st_enter_scope(this.st);
                    i = 0;
                    while (i < this.param_count(f))
                    {
                        p = f.l0.items[i];
                        this.define_var(p.text, p.ts);
                        i++;
                    };
                }
                    default {};
                };
                -> true;
            };

            end_body() -> void
            {
                switch (this.st != (FXC_SYMTABLE*)0)
                {
                    case (true) { st_exit_scope(this.st); }
                    default {};
                };
                ->;
            };

            // Ends the template scope of an extra prototype that failed early
            proto_scope_end(Node* p, TemplateEntry* pte, NameMap* prev_act) -> Node*
            {
                switch (pte != (TemplateEntry*)0)
                {
                    case (true) {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                    te_free(pte);
                }
                    default {};
                };
                -> this.done(p);
            };

            // Additional prototype of a comma separated list: name(params) -> type tags
            fn_extra_proto(int m, int base_flags, byte* conv, bool is_cdecl) -> Node*
            {
                Node* p = this.mk(NodeKind.FUNCTION_DEF, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> p; }
                    default {};
                };
                p.flags = base_flags;
                p.text2 = conv;
                this.fn_name(p);
                switch (this.failed)
                {
                    case (true) { -> this.done(p); }
                    default {};
                };
                NameMap* prev_act = this.active_tp;
                TemplateEntry* pte = (TemplateEntry*)0;
                switch (this.expect(TokenType.LESS_THAN) & this.is_template_list())
                {
                    case (true) {
                    pte = te_new();
                    this.advance();
                    pv_push(pte.params, (void*)this.own(ts_dup(this.ident())));
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        pv_push(pte.params, (void*)this.own(ts_dup(this.ident())));
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.GREATER_THAN); }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) {
                        te_free(pte);
                        -> this.done(p);
                    }
                        default {};
                    };
                    this.tp_activate(pte);
                    p.flags = p.flags `| NF_TEMPLATE;
                }
                    default {};
                };
                switch (!this.consume(TokenType.LEFT_PAREN))
                {
                    case (true) { -> this.proto_scope_end(p, pte, prev_act); }
                    default {};
                };
                switch (!this.expect(TokenType.RIGHT_PAREN))
                {
                    case (true) { this.parameter_list(p); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RETURN_ARROW); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.fn_return(p, is_cdecl); }
                    default {};
                };
                switch (pte != (TemplateEntry*)0)
                {
                    case (true) {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                    te_free(pte);
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.fn_tags(p); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(p); }
                    default {};
                };
                this.strip_variadic(p);
                this.mark_proto(p);
                -> this.done(p);
            };

            // function_def -> ('const')? ('volatile')? ('inline')? ('def' | calling_conv)? ('!!')? name
            //                 '(' parameter_list? ')' ('->' | '<~') type_spec ('^|' type_spec)?
            //                 tags (';' | '->' expression ';' | block tags ';')
            // Also 'def{}*' function pointer declarations and comma separated prototype lists
            // (extra prototypes go to the pending queue).
            // Template functions, contracts and 'as operator' are reported and skipped (null).
            function_def() -> Node*
            {
                NameMap* prev_act = this.active_tp;
                TemplateEntry* prev_cur = this.tmpl_cur;
                this.tmpl_cur = (TemplateEntry*)0;
                Node* f = this.function_def_inner();
                TemplateEntry* te = this.tmpl_cur;
                this.tmpl_cur = prev_cur;
                switch (this.active_tp != prev_act)
                {
                    case (true) {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                }
                    default {};
                };
                switch (te == (TemplateEntry*)0)
                {
                    case (true) { -> f; }
                    default {};
                };
                switch (this.failed | f == (Node*)0)
                {
                    case (true) {
                    te_free(te);
                    -> f;
                }
                    default {};
                };
                switch (f.text == (byte*)0)
                {
                    case (true) { f.text = g"\0"; }
                    default {};
                };
                this.last_template = f.text;
                switch (this.in_comptime > 0)
                {
                    case (true) {
                    this.register_template(f.text, 0, te, node_clone(f));
                    -> f;
                }
                    default {};
                };
                this.register_template(f.text, 0, te, f);
                -> (Node*)0;
            };

            function_def_inner() -> Node*
            {
                int m = this.mark();
                int line = this.cur_line();
                int col = this.cur_col();
                int flags = 0;
                byte* conv = (byte*)0;
                bool is_cdecl = false;

                switch (this.expect(TokenType.CONST))
                {
                    case (true) { flags = flags `| NF_CONST; this.advance(); }
                    default {};
                };
                switch (this.expect(TokenType.VOLATILE))
                {
                    case (true) { flags = flags `| NF_VOLATILE; this.advance(); }
                    default {};
                };
                switch (this.expect(TokenType.INLINE))
                {
                    case (true) { flags = flags `| NF_INLINE; this.advance(); }
                    default {};
                };

                switch (this.is_calling_conv(this.cur()))
                {
                    case (true) {
                    conv = this.cc_text(this.cur());
                    is_cdecl = this.expect(TokenType.CDECL);
                    this.advance();
                }
                    default {
                        switch (this.expect(TokenType.DEF))
                        {
                            case (true) {
                    this.advance();
                }
                            default {};
                        };
                    };
                };

                switch (this.expect(TokenType.FUNCTION_POINTER))
                {
                    case (true) {
                    this.advance();
                    -> this.function_pointer_declaration(conv);
                }
                    default {};
                };

                switch (is_cdecl)
                {
                    case (true) { flags = flags `| NF_NO_MANGLE; }
                    default {};
                };
                switch (this.expect(TokenType.NO_MANGLE))
                {
                    case (true) {
                    flags = flags `| NF_NO_MANGLE;
                    this.advance();
                }
                    default {};
                };

                Node* f = this.mk(NodeKind.FUNCTION_DEF, line, col);
                switch (this.failed)
                {
                    case (true) { -> f; }
                    default {};
                };
                f.flags = flags;
                f.text2 = conv;

                this.fn_name(f);
                switch (this.failed)
                {
                    case (true) { -> this.done(f); }
                    default {};
                };

                switch (this.expect(TokenType.LESS_THAN))
                {
                    case (true) {
                    this.tmpl_cur = this.template_params(false);
                    switch (this.failed)
                    {
                        case (true) { -> this.done(f); }
                        default {};
                    };
                    this.tp_activate(this.tmpl_cur);
                }
                    default {};
                };

                switch (!this.consume(TokenType.LEFT_PAREN))
                {
                    case (true) { -> this.done(f); }
                    default {};
                };
                switch (!this.expect(TokenType.RIGHT_PAREN))
                {
                    case (true) { this.parameter_list(f); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(f); }
                    default {};
                };
                switch (!this.consume(TokenType.RIGHT_PAREN))
                {
                    case (true) { -> this.done(f); }
                    default {};
                };

                switch (this.expect(TokenType.RECURSE_ARROW))
                {
                    case (true) {
                    f.flags = f.flags `| NF_RECURSIVE;
                    this.advance();
                }
                    default {
                        switch (!this.consume(TokenType.RETURN_ARROW))
                        {
                            case (true) {
                    -> this.done(f);
                }
                            default {};
                        };
                    };
                };
                this.fn_return(f, is_cdecl);
                switch (this.failed)
                {
                    case (true) { -> this.done(f); }
                    default {};
                };

                // Tags before a comma list or a prototype
                switch (this.expect2(TokenType.TAG, TokenType.COMMA))
                {
                    case (true) {
                    this.fn_tags(f);
                    switch (this.failed)
                    {
                        case (true) { -> this.done(f); }
                        default {};
                    };
                    switch (this.expect(TokenType.COMMA))
                    {
                        case (true) {
                        this.strip_variadic(f);
                        this.mark_proto(f);
                        Node* extra;
                        int pflags = (flags `| NF_PROTOTYPE);
                        while (this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            extra = this.fn_extra_proto(m, pflags, conv, is_cdecl);
                            switch (this.failed)
                            {
                                case (true) { -> this.done(f); }
                                default {};
                            };
                            switch (extra == (Node*)0)
                            {
                                case (true) {
                                node_free(f);
                                -> (Node*)0;
                            }
                                default {};
                            };
                            nv_push(this.pending, extra);
                        };
                        switch (!this.consume(TokenType.SEMICOLON))
                        {
                            case (true) { -> this.done(f); }
                            default {};
                        };
                        -> f;
                    }
                        default {};
                    };
                }
                    default {};
                };

                Node* pre = (Node*)0;
                Node* post;
                OpSym* as_l = (OpSym*)0;
                OpSym* as_r = (OpSym*)0;
                int as_bind;
                switch (this.expect(TokenType.COLON))
                {
                    case (true) {
                    this.advance();
                    pre = this.mk(NodeKind.NODE_LIST, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> this.done(f); }
                        default {};
                    };
                    this.contract_refs(f, pre, false);
                    switch (this.failed)
                    {
                        case (true) { node_free(pre); -> this.done(f); }
                        default {};
                    };
                }
                    default {};
                };

                this.strip_variadic(f);

                switch ((f.flags `& NF_RECURSIVE) != 0)
                {
                    case (true) {
                    bool void_form = this.param_count(f) == 0 & f.ts.base_type == DataType.VOID;
                    bool single_form = this.param_count(f) == 1 & typespec_equal(f.l0.items[0].ts, f.ts);
                    switch (!void_form & !single_form)
                    {
                        case (true) {
                        switch (this.param_count(f) == 0)
                        {
                            case (true) {
                            this.error(this.cat2(this.cat2(g"Recursive function '\0", this.fn_label(f)), g"' with no parameters must return void\0"));
                        }
                            default {
                                switch (this.param_count(f) == 1)
                                {
                                    case (true) {
                            this.error(this.cat2(this.cat2(g"Recursive function '\0", this.fn_label(f)), g"': return type must match parameter type\0"));
                        }
                                    default {
                            this.error(this.cat2(this.cat2(g"Recursive function '\0", this.fn_label(f)), g"' declared with '<~' must have exactly one parameter, or no parameters with void return\0"));
                        };
                                };
                            };
                        };
                        node_free(pre);
                        -> this.done(f);
                    }
                        default {};
                    };
                }
                    default {};
                };

                switch (this.expect(TokenType.AS))
                {
                    case (true) {
                    this.advance();
                    switch (!this.consume(TokenType.OPERATOR))
                    {
                        case (true) { node_free(pre); -> this.done(f); }
                        default {};
                    };
                    as_l = this.op_bracket();
                    switch (!this.failed & this.expect(TokenType.LEFT_BRACKET))
                    {
                        case (true) { as_r = this.op_bracket(); }
                        default {};
                    };
                    switch (!this.failed & as_r == (OpSym*)0)
                    {
                        case (true) {
                        switch (this.param_count(f) == 1)
                        {
                            case (true) { as_bind = this.unary_binding(f, g"an 'as operator' binding\0"); }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) {
                        node_free(pre);
                        this.opsym_free(as_l);
                        this.opsym_free(as_r);
                        -> this.done(f);
                    }
                        default {};
                    };
                }
                    default {};
                };

                Node* ret;
                Node* b;
                switch (this.expect2(TokenType.TAG, TokenType.SEMICOLON))
                {
                    case (true) {
                    this.fn_tags(f);
                    switch (this.failed)
                    {
                        case (true) { -> this.done(f); }
                        default {};
                    };
                    switch (this.expect(TokenType.SEMICOLON))
                    {
                        case (true) {
                        this.advance();
                        this.mark_proto(f);
                    }
                        default {};
                    };
                    node_free(pre);
                    switch (!this.failed & as_l != (OpSym*)0)
                    {
                        case (true) { this.register_operator(f, as_l, as_r, as_bind, false, false); }
                        default {};
                    };
                    -> this.done(f);
                }
                    default {};
                };

                switch (this.expect(TokenType.RETURN_ARROW))
                {
                    case (true) {
                    // name(params) -> type -> expression;
                    switch (!this.begin_body(f))
                    {
                        case (true) { -> this.done(f); }
                        default {};
                    };
                    this.advance();
                    b = this.mk(NodeKind.BLOCK, this.cur_line(), this.cur_col());
                    switch (this.failed)
                    {
                        case (true) { this.end_body(); -> this.done(f); }
                        default {};
                    };
                    f.a = b;
                    ret = this.mk(NodeKind.RETURN_STATEMENT, this.cur_line(), this.cur_col());
                    switch (this.failed)
                    {
                        case (true) { this.end_body(); -> this.done(f); }
                        default {};
                    };
                    node_push(b, 0, ret);
                    this.function_depth++;
                    ret.a = this.expression();
                    this.function_depth--;
                    this.end_body();
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                    node_free(pre);
                    switch (!this.failed & as_l != (OpSym*)0)
                    {
                        case (true) { this.register_operator(f, as_l, as_r, as_bind, false, false); }
                        default {};
                    };
                    -> this.done(f);
                }
                    default {};
                };

                switch (this.in_trait != 0 & !this.expect(TokenType.LEFT_BRACE))
                {
                    case (true) {
                    this.fail_expected(TokenType.SEMICOLON);
                    -> this.done(f);
                }
                    default {};
                };

                switch (!this.begin_body(f))
                {
                    case (true) { -> this.done(f); }
                    default {};
                };
                this.function_depth++;
                f.a = this.block();
                this.function_depth--;
                this.end_body();
                switch (this.failed)
                {
                    case (true) { node_free(pre); -> this.done(f); }
                    default {};
                };
                this.prepend_contracts(f, pre);

                post = (Node*)0;
                switch (this.expect(TokenType.COLON))
                {
                    case (true) {
                    this.advance();
                    post = this.mk(NodeKind.NODE_LIST, line, col);
                    switch (this.failed)
                    {
                        case (true) { node_free(pre); -> this.done(f); }
                        default {};
                    };
                    this.contract_refs(f, post, true);
                    switch (!this.failed)
                    {
                        case (true) { this.apply_post_contracts(f, post); }
                        default {};
                    };
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.validate_bindings(this.fn_label(f), pre, post); }
                    default {};
                };
                node_free(post);
                node_free(pre);
                switch (this.failed)
                {
                    case (true) { -> this.done(f); }
                    default {};
                };

                this.fn_tags(f);
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (!this.failed & as_l != (OpSym*)0)
                {
                    case (true) { this.register_operator(f, as_l, as_r, as_bind, false, false); }
                    default {};
                };
                -> this.done(f);
            };

            // ----- extern and export blocks -----

            // Adds f to holder.l0, checking prototype versus definition
            add_func(Node* holder, Node* f, bool want_proto) -> void
            {
                node_push(holder, 0, f);
                switch (f.kind != NodeKind.FUNCTION_DEF)
                {
                    case (true) { ->; }
                    default {};
                };
                bool is_proto = (f.flags `& NF_PROTOTYPE) != 0;
                switch (want_proto & !is_proto)
                {
                    case (true) {
                    this.error(g"Extern functions must be prototypes (declarations only, no body)\0");
                }
                    default {
                        switch (!want_proto & is_proto)
                        {
                            case (true) {
                    this.error(g"'export' requires a full definition, not a prototype\0");
                }
                            default {};
                        };
                    };
                };
                ->;
            };

            // One function_def (with its comma list) into holder.l0
            collect_funcs(Node* holder, bool want_proto) -> void
            {
                Node* f = this.function_def();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                int k;
                switch (f != (Node*)0)
                {
                    case (true) { this.add_func(holder, f, want_proto); }
                    default {};
                };
                while (!this.failed & k < this.pending.len)
                {
                    this.add_func(holder, this.pending.items[k], want_proto);
                    k++;
                };
                this.pending.len = 0;
                ->;
            };

            // One entry of an extern block: a function prototype or 'type name;'
            extern_item(Node* holder) -> void
            {
                switch (this.expect(TokenType.DEF) | this.is_calling_conv(this.cur()))
                {
                    case (true) {
                    this.collect_funcs(holder, true);
                    ->;
                }
                    default {};
                };
                Node* v = this.mk(NodeKind.VARIABLE_DECLARATION, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                node_push(holder, 0, v);
                v.ts = this.type_spec();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                v.text = this.ident();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (this.expect2(TokenType.ASSIGN, TokenType.ADDRESS_ASSIGN))
                {
                    case (true) {
                    this.error(g"Extern variable declarations cannot have an initializer\0");
                    ->;
                }
                    default {};
                };
                this.consume(TokenType.SEMICOLON);
                ->;
            };

            // extern_statement -> 'extern' ('{' extern_item* '}' ';' | extern_item)
            extern_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.EXTERN_BLOCK, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.advance();
                switch (this.expect(TokenType.LEFT_BRACE))
                {
                    case (true) {
                    this.advance();
                    while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                    {
                        switch (this.expect(TokenType.EOF))
                        {
                            case (true) {
                            this.fail_expected(TokenType.RIGHT_BRACE);
                            break;
                        }
                            default {};
                        };
                        this.extern_item(n);
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_BRACE); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                }
                    default {
                    this.extern_item(n);
                };
                };
                -> this.done(n);
            };

            // export_statement -> 'export' ('{' function_def* '}' ';' | function_def)
            export_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.EXPORT_BLOCK, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.advance();
                switch (this.expect(TokenType.LEFT_BRACE))
                {
                    case (true) {
                    this.advance();
                    while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                    {
                        switch (this.expect(TokenType.EOF))
                        {
                            case (true) {
                            this.fail_expected(TokenType.RIGHT_BRACE);
                            break;
                        }
                            default {};
                        };
                        switch (this.expect(TokenType.DEF) | this.is_calling_conv(this.cur()))
                        {
                            case (true) {
                            this.collect_funcs(n, false);
                        }
                            default {
                            this.fail_expected(TokenType.DEF);
                        };
                        };
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_BRACE); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                }
                    default {
                        switch (this.expect(TokenType.DEF) | this.is_calling_conv(this.cur()))
                        {
                            case (true) {
                    this.collect_funcs(n, false);
                }
                            default {
                    this.fail_expected(TokenType.LEFT_BRACE);
                };
                        };
                    };
                };
                -> this.done(n);
            };

            // ===== USING, STRUCTS AND NAMESPACES =====

            // IDENTIFIER ('::' IDENTIFIER)* joined with "__"
            namespace_path() -> byte*
            {
                byte* path = this.ident();
                switch (this.failed)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                while (this.expect(TokenType.SCOPE))
                {
                    this.advance();
                    path = this.cat2(this.cat2(path, g"__\0"), this.ident());
                    switch (this.failed)
                    {
                        case (true) { -> (byte*)0; }
                        default {};
                    };
                };
                -> path;
            };

            // 'using' path (',' path)* ';'    (kind is USING_STATEMENT or NOT_USING_STATEMENT)
            using_list(int kind) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* first = this.mk(kind, line, col);
                switch (this.failed)
                {
                    case (true) { -> first; }
                    default {};
                };
                first.text = this.namespace_path();
                switch (this.failed)
                {
                    case (true) { -> this.done(first); }
                    default {};
                };
                Node* x;
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    x = this.mk(kind, line, col);
                    switch (this.failed)
                    {
                        case (true) { -> this.done(first); }
                        default {};
                    };
                    nv_push(this.pending, x);
                    x.text = this.namespace_path();
                    switch (this.failed)
                    {
                        case (true) { -> this.done(first); }
                        default {};
                    };
                };
                switch (!this.consume(TokenType.SEMICOLON))
                {
                    case (true) { -> this.done(first); }
                    default {};
                };
                -> first;
            };

            using_statement() -> Node*
            {
                this.advance();
                -> this.using_list(NodeKind.USING_STATEMENT);
            };

            // 'using' was already consumed by the dispatch, so the '!' is behind us
            not_using_statement() -> Node* -> this.using_list(NodeKind.NOT_USING_STATEMENT);

            // '<' IDENTIFIER (',' IDENTIFIER)* '>' ahead of the current token
            is_template_list() -> bool
            {
                int m = this.mark();
                bool r = false;
                this.advance();
                switch (this.expect(TokenType.IDENTIFIER))
                {
                    case (true) {
                    this.advance();
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        switch (!this.expect(TokenType.IDENTIFIER))
                        {
                            case (true) { break; }
                            default {};
                        };
                        this.advance();
                    };
                    r = this.expect(TokenType.GREATER_THAN);
                }
                    default {};
                };
                this.reset(m);
                -> r;
            };

            // Base struct name, with <T,U> arguments kept in the text. Pushed to holder.l<slot>.
            // Returns true when template arguments were present (the struct is then a template).
            struct_base_ref(Node* holder, int slot) -> bool
            {
                Node* r = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> false; }
                    default {};
                };
                node_push(holder, slot, r);
                byte* name = this.ident();
                switch (this.failed)
                {
                    case (true) { -> false; }
                    default {};
                };
                byte* arg;
                bool generic = false;
                switch (this.expect(TokenType.LESS_THAN) & this.is_template_list())
                {
                    case (true) {
                    generic = true;
                    this.advance();
                    arg = this.ident();
                    this.sd_param_add(holder, arg);
                    name = this.cat2(this.cat2(name, g"<\0"), arg);
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        arg = this.ident();
                        this.sd_param_add(holder, arg);
                        name = this.cat2(this.cat2(name, g",\0"), arg);
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.GREATER_THAN); }
                        default {};
                    };
                    name = this.cat2(name, g">\0");
                }
                    default {};
                };
                r.text = name;
                -> generic;
            };

            // Adds a template parameter name to a struct node (l4) unless already declared
            sd_param_add(Node* h, byte* s) -> void
            {
                int i;
                int c;
                Node* x;
                switch (this.failed | s == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                c = node_count(h, 4);
                while (i < c)
                {
                    switch (cstr_eq(node_child(h, 4, i).text, s))
                    {
                        case (true) { ->; }
                        default {};
                    };
                    i++;
                };
                x = this.mk(NodeKind.IDENTIFIER, h.line, h.col);
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                x.text = s;
                node_push(h, 4, x);
                ->;
            };

            // base_ref (',' base_ref)* into holder.l<slot>
            struct_base_list(Node* holder, int slot) -> bool
            {
                bool generic = this.struct_base_ref(holder, slot);
                while (!this.failed & this.expect(TokenType.COMMA))
                {
                    this.advance();
                    switch (this.struct_base_ref(holder, slot))
                    {
                        case (true) { generic = true; }
                        default {};
                    };
                };
                -> generic;
            };

            // struct_member -> type_spec IDENTIFIER (',' IDENTIFIER)* ('=' expression (',' expression)*)? ';'
            // Members are pushed to owner.l0. The first member owns the type, the rest copy it.
            struct_member(Node* owner, bool is_private) -> void
            {
                int line = this.cur_line();
                int col = this.cur_col();
                TypeSpec* ts = this.type_spec();
                switch (this.failed)
                {
                    case (true) {
                    typespec_free(ts);
                    ->;
                }
                    default {};
                };
                int base = 0;
                switch (owner.l0 != (NodeVec*)0)
                {
                    case (true) { base = owner.l0.len; }
                    default {};
                };
                int cnt = 0;
                Node* mem;
                Node* e;
                int k;
                bool more = true;
                while (more)
                {
                    mem = this.mk(NodeKind.STRUCT_MEMBER, line, col);
                    switch (this.failed)
                    {
                        case (true) {
                        switch (cnt == 0)
                        {
                            case (true) { typespec_free(ts); }
                            default {};
                        };
                        ->;
                    }
                        default {};
                    };
                    node_push(owner, 0, mem);
                    switch (cnt)
                    {
                        case (0) { mem.ts = ts; }
                        default { mem.ts = typespec_copy(ts); };
                    };
                    switch (is_private)
                    {
                        case (true) { mem.flags = NF_PRIVATE; }
                        default {};
                    };
                    mem.text = this.ident();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    cnt++;
                    more = false;
                    switch (this.expect(TokenType.COMMA) & this.type_at(1) == TokenType.IDENTIFIER)
                    {
                        case (true) {
                        this.advance();
                        more = true;
                    }
                        default {};
                    };
                };

                switch (this.expect(TokenType.ASSIGN))
                {
                    case (true) {
                    this.advance();
                    more = true;
                    while (more)
                    {
                        e = this.expression();
                        switch (this.failed)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        switch (k < cnt)
                        {
                            case (true) { owner.l0.items[base + k].a = e; }
                            default { node_free(e); };
                        };
                        k++;
                        more = false;
                        switch (this.expect(TokenType.COMMA))
                        {
                            case (true) {
                            this.advance();
                            more = true;
                        }
                            default {};
                        };
                    };
                }
                    default {};
                };
                this.consume(TokenType.SEMICOLON);
                ->;
            };

            // A nested struct goes to owner.l3, together with any prototypes queued behind it
            nested_struct(Node* owner) -> void
            {
                Node* s = this.struct_def();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                int k;
                switch (s != (Node*)0)
                {
                    case (true) { node_push(owner, 3, s); }
                    default {};
                };
                while (k < this.pending.len)
                {
                    node_push(owner, 3, this.pending.items[k]);
                    k++;
                };
                this.pending.len = 0;
                ->;
            };

            // '{' (struct | struct_member)* '}' ';' of a public or private section
            struct_section(Node* owner, bool is_private) -> void
            {
                this.advance();
                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { ->; }
                    default {};
                };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        ->;
                    }
                        default {};
                    };
                    switch (this.expect(TokenType.STRUCT))
                    {
                        case (true) {
                        this.nested_struct(owner);
                        switch (!this.failed)
                        {
                            case (true) { this.consume(TokenType.SEMICOLON); }
                            default {};
                        };
                    }
                        default {
                        this.struct_member(owner, is_private);
                    };
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                ->;
            };

            // struct_def -> 'struct' IDENTIFIER (',' IDENTIFIER)*
            //               (':' bases (':' bases)?)? (';' | '{' (member | struct | public/private section | comptime)* '}' (':' bases)? ';')
            // Template structs (fparser.py registers them and returns None) are reported and skipped.
            // Extra names of a prototype list go to the pending queue.
            struct_def() -> Node*
            {
                int m = this.mark();
                Node* n = this.mk(NodeKind.STRUCT_DEF, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                n.op = -1;
                this.advance();
                n.text = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.done(n); }
                    default {};
                };

                switch (this.expect(TokenType.LESS_THAN) & this.is_template_list())
                {
                    case (true) {
                    this.advance();
                    this.sd_param_add(n, this.ident());
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        this.sd_param_add(n, this.ident());
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.GREATER_THAN); }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) { -> this.done(n); }
                        default {};
                    };
                }
                    default {};
                };

                PtrVec* names = pv_new();
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    pv_push(names, (void*)this.ident());
                    switch (this.failed)
                    {
                        case (true) { pv_free(names); -> this.done(n); }
                        default {};
                    };
                };

                switch (this.expect(TokenType.COLON))
                {
                    case (true) {
                    this.advance();
                    this.struct_base_list(n, 1);
                    switch (!this.failed & this.expect(TokenType.COLON))
                    {
                        case (true) {
                        this.advance();
                        this.struct_base_list(n, 2);
                    }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) { pv_free(names); -> this.done(n); }
                        default {};
                    };
                    switch (this.expect(TokenType.SEMICOLON))
                    {
                        case (true) {
                        this.advance();
                        pv_free(names);
                        -> n;
                    }
                        default {};
                    };
                }
                    default {};
                };

                int line = n.line;
                int col = n.col;
                Node* x;
                int k;
                bool has_base = false;
                switch (n.l1 != (NodeVec*)0)
                {
                    case (true) { has_base = n.l1.len > 0; }
                    default {};
                };
                switch (this.expect(TokenType.SEMICOLON) & !has_base)
                {
                    case (true) {
                    this.advance();
                    switch (n.l4 != (NodeVec*)0)
                    {
                        case (true) { n.l4.len = 0; }
                        default {};
                    };
                    while (k < names.len)
                    {
                        x = this.mk(NodeKind.STRUCT_DEF, line, col);
                        switch (this.failed)
                        {
                            case (true) { pv_free(names); -> this.done(n); }
                            default {};
                        };
                        x.op = -1;
                        x.text = (byte*)names.items[k];
                        nv_push(this.pending, x);
                        k++;
                    };
                    pv_free(names);
                    -> n;
                }
                    default {};
                };

                switch (names.len > 0)
                {
                    case (true) {
                    pv_free(names);
                    this.error(g"Comma-separated names are only allowed for prototypes (forward declarations)\0");
                    -> this.done(n);
                }
                    default {};
                };
                pv_free(names);

                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { -> this.done(n); }
                    default {};
                };
                Node* cb;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    }
                        default {};
                    };
                    switch (this.expect(TokenType.PUBLIC))
                    {
                        case (true) { this.struct_section(n, false); }
                        default {
                            switch (this.expect(TokenType.PRIVATE))
                            {
                                case (true) { this.struct_section(n, true); }
                                default {
                                    switch (this.expect(TokenType.STRUCT))
                                    {
                                        case (true) { this.nested_struct(n); }
                                        default {
                                            switch (this.expect(TokenType.COMPTIME))
                                            {
                                                case (true) {
                        cb = this.comptime_block();
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        switch (n.l0 != (NodeVec*)0)
                        {
                            case (true) { cb.ival = n.l0.len; }
                            default {};
                        };
                        node_push(n, 5, cb);
                    }
                                                default { this.struct_member(n, false); };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(n); }
                    default {};
                };
                this.consume(TokenType.RIGHT_BRACE);

                switch (!this.failed & this.expect(TokenType.COLON))
                {
                    case (true) {
                    this.advance();
                    this.struct_base_list(n, 2);
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(n); }
                    default {};
                };
                switch (node_count(n, 4) > 0)
                {
                    case (true) {
                    TemplateEntry* te = te_new();
                    int ti;
                    int tc = node_count(n, 4);
                    while (ti < tc)
                    {
                        pv_push(te.params, (void*)this.own(ts_dup(node_child(n, 4, ti).text)));
                        ti++;
                    };
                    this.last_template = n.text;
                    switch (this.in_comptime > 0)
                    {
                        case (true) {
                        this.register_template(n.text, 1, te, node_clone(n));
                        -> n;
                    }
                        default {};
                    };
                    this.register_template(n.text, 1, te, n);
                    -> (Node*)0;
                }
                    default {};
                };
                -> n;
            };

            // ----- namespaces -----

            // Lazily created NODE_LIST held in ns.a (variables), ns.b (nested namespaces) or ns.c (bases)
            ns_list(Node* ns, int which) -> Node*
            {
                Node* l;
                switch (which)
                {
                    case (0) { l = ns.a; }
                    case (1) { l = ns.b; }
                    default { l = ns.c; };
                };
                switch (l != (Node*)0)
                {
                    case (true) { -> l; }
                    default {};
                };
                l = this.mk(NodeKind.NODE_LIST, ns.line, ns.col);
                switch (this.failed)
                {
                    case (true) { -> l; }
                    default {};
                };
                switch (which)
                {
                    case (0) { ns.a = l; }
                    case (1) { ns.b = l; }
                    default { ns.c = l; };
                };
                -> l;
            };

            // Slot of the namespace list that holds nodes of this kind, -1 for the variables list
            ns_slot(Node* x) -> int
            {
                int k = x.kind;
                switch (k == NodeKind.FUNCTION_DEF)
                {
                    case (true) { -> 0; }
                    default {};
                };
                switch (k == NodeKind.STRUCT_DEF)
                {
                    case (true) { -> 1; }
                    default {};
                };
                switch (k == NodeKind.OBJECT_DEF | k == NodeKind.TRAIT_DEF | k == NodeKind.INTERFACE_DEF)
                {
                    case (true) { -> 2; }
                    default {};
                };
                switch (k == NodeKind.ENUM_DEF | k == NodeKind.ENUM_DEF_STATEMENT)
                {
                    case (true) { -> 3; }
                    default {};
                };
                switch (k == NodeKind.UNION_DEF | k == NodeKind.UNION_DEF_STATEMENT)
                {
                    case (true) { -> 4; }
                    default {};
                };
                switch (k == NodeKind.EXTERN_BLOCK)
                {
                    case (true) { -> 5; }
                    default {};
                };
                -> -1;
            };

            // ns__name and, except for variables (already defined by the declaration), name
            define_in_namespace(byte* name, int kind, TypeSpec* ts) -> void
            {
                switch (this.st == (FXC_SYMTABLE*)0 | name == (byte*)0 | this.ns_path == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                st_define(this.st, this.cat2(this.cat2(this.ns_path, g"__\0"), name), kind, ts, (Node*)0);
                switch (kind != SymbolKind.VARIABLE)
                {
                    case (true) { st_define(this.st, name, kind, ts, (Node*)0); }
                    default {};
                };
                ->;
            };

            // The definition inside an enum or union statement (null child means a stub, kept as is)
            unwrap_def(Node* x) -> Node*
            {
                switch (x.kind != NodeKind.ENUM_DEF_STATEMENT & x.kind != NodeKind.UNION_DEF_STATEMENT)
                {
                    case (true) { -> x; }
                    default {};
                };
                switch (x.a == (Node*)0)
                {
                    case (true) { -> x; }
                    default {};
                };
                Node* d = x.a;
                x.a = (Node*)0;
                node_free(x);
                -> d;
            };

            // Routes x into its list of ns and registers its name
            ns_add(Node* ns, Node* x0) -> void
            {
                Node* x = this.unwrap_def(x0);
                int slot = this.ns_slot(x);
                Node* l;
                switch (slot >= 0)
                {
                    case (true) { node_push(ns, slot, x); }
                    default {
                    l = this.ns_list(ns, 0);
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    node_push(l, 0, x);
                };
                };
                switch ((x.flags `& NF_STUB) != 0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (x.kind)
                {
                    case (NodeKind.FUNCTION_DEF) { this.define_in_namespace(x.text, SymbolKind.FUNCTION, (TypeSpec*)0); }
                    case (NodeKind.STRUCT_DEF) { this.define_in_namespace(x.text, SymbolKind.TYPE, (TypeSpec*)0); }
                    case (NodeKind.ENUM_DEF) { this.define_in_namespace(x.text, SymbolKind.ENUM, (TypeSpec*)0); }
                    case (NodeKind.UNION_DEF) { this.define_in_namespace(x.text, SymbolKind.UNION, (TypeSpec*)0); }
                    case (NodeKind.VARIABLE_DECLARATION) { this.define_in_namespace(x.text, SymbolKind.VARIABLE, x.ts); }
                    default {};
                };
                ->;
            };

            // x (may be null) and everything queued behind it
            ns_add_all(Node* ns, Node* x) -> void
            {
                int k;
                switch (x != (Node*)0)
                {
                    case (true) { this.ns_add(ns, x); }
                    default {};
                };
                while (!this.failed & k < this.pending.len)
                {
                    this.ns_add(ns, this.pending.items[k]);
                    k++;
                };
                this.pending.len = 0;
                ->;
            };

            // Moves every item of from into dst.l<slot>
            move_items(NodeVec* src, Node* dst, int slot) -> void
            {
                switch (src == (NodeVec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                int i;
                while (i < src.len)
                {
                    node_push(dst, slot, src.items[i]);
                    i++;
                };
                src.len = 0;
                ->;
            };

            // Adds a nested namespace, merging it into an earlier one of the same name
            ns_nest(Node* ns, Node* x) -> void
            {
                switch (x == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                Node* lst = this.ns_list(ns, 1);
                switch (this.failed)
                {
                    case (true) { node_free(x); ->; }
                    default {};
                };
                Node* ex;
                Node* dl;
                int i, s;
                int total;
                switch (lst.l0 != (NodeVec*)0)
                {
                    case (true) { total = lst.l0.len; }
                    default {};
                };
                while (i < total)
                {
                    ex = lst.l0.items[i];
                    switch (ex.text != (byte*)0 & x.text != (byte*)0)
                    {
                        case (true) {
                        switch (cstr_eq(ex.text, x.text))
                        {
                            case (true) {
                            s = 0;
                            while (s < 5)
                            {
                                switch (s)
                                {
                                    case (0) { this.move_items(x.l0, ex, 0); }
                                    case (1) { this.move_items(x.l1, ex, 1); }
                                    case (2) { this.move_items(x.l2, ex, 2); }
                                    case (3) { this.move_items(x.l3, ex, 3); }
                                    default { this.move_items(x.l4, ex, 4); };
                                };
                                s++;
                            };
                            s = 0;
                            while (s < 3)
                            {
                                switch (s)
                                {
                                    case (0) { dl = x.a; }
                                    case (1) { dl = x.b; }
                                    default { dl = x.c; };
                                };
                                switch (dl != (Node*)0)
                                {
                                    case (true) {
                                    this.move_items(dl.l0, this.ns_list(ex, s), 0);
                                }
                                    default {};
                                };
                                s++;
                            };
                            node_free(x);
                            ->;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                node_push(lst, 0, x);
                ->;
            };

            // One entry of a namespace body
            // A template registered inside a namespace is also reachable as ns__name and ns::name
            ns_tmpl_alias(Node* x) -> void
            {
                byte* bare = this.last_template;
                switch (x != (Node*)0 | bare == (byte*)0 | this.ns_path == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                this.template_alias(this.cat2(this.cat2(this.ns_path, g"__\0"), bare), bare);
                this.template_alias(this.cat2(this.cat2(this.ns_path, g"::\0"), bare), bare);
                ->;
            };

            ns_item(Node* ns) -> void
            {
                int c = this.cur();
                Node* x;
                switch (c == TokenType.GLOBAL | c == TokenType.LOCAL | c == TokenType.HEAP | c == TokenType.STACK |
                    c == TokenType.REGISTER | c == TokenType.SINGINIT | c == TokenType.CONST | c == TokenType.VOLATILE)
                {
                    case (true) {
                    x = this.variable_declaration();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_add_all(ns, x);
                    this.consume(TokenType.SEMICOLON);
                }
                    default {
                        switch (this.expect3(TokenType.INLINE, TokenType.DEF, TokenType.NO_MANGLE) | this.is_calling_conv(c) | this.is_bare_function_def())
                        {
                            case (true) {
                    this.last_template = (byte*)0;
                    x = this.function_def();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_tmpl_alias(x);
                    this.ns_add_all(ns, x);
                }
                            default {
                                switch (c == TokenType.STRUCT)
                                {
                                    case (true) {
                    x = this.struct_def();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_tmpl_alias(x);
                    this.ns_add_all(ns, x);
                }
                                    default {
                                        switch (c == TokenType.OBJECT)
                                        {
                                            case (true) {
                    x = this.object_def();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_tmpl_alias(x);
                    this.ns_add_all(ns, x);
                }
                                            default {
                                                switch (c == TokenType.TRAIT)
                                                {
                                                    case (true) {
                    x = this.trait_def();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_add_all(ns, x);
                }
                                                    default {
                                                        switch (c == TokenType.INTERFACE)
                                                        {
                                                            case (true) {
                    x = this.interface_def();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_add_all(ns, x);
                }
                                                            default {
                                                                switch (this.is_trait_prefixed_object())
                                                                {
                                                                    case (true) {
                    x = this.trait_prefixed_object();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_tmpl_alias(x);
                    this.ns_add_all(ns, x);
                }
                                                                    default {
                                                                        switch (c == TokenType.ENUM | this.type_at(1) == TokenType.ENUM)
                                                                        {
                                                                            case (true) {
                    x = this.enum_def();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_add_all(ns, x);
                }
                                                                            default {
                                                                                switch (c == TokenType.UNION)
                                                                                {
                                                                                    case (true) {
                    x = this.union_def();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_add_all(ns, x);
                }
                                                                                    default {
                                                                                        switch (c == TokenType.OPERATOR)
                                                                                        {
                                                                                            case (true) {
                    x = this.operator_def();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_add_all(ns, x);
                }
                                                                                            default {
                                                                                                switch (c == TokenType.EXTERN)
                                                                                                {
                                                                                                    case (true) {
                    x = this.extern_statement();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_add_all(ns, x);
                }
                                                                                                    default {
                                                                                                        switch (c == TokenType.NAMESPACE)
                                                                                                        {
                                                                                                            case (true) {
                    x = this.namespace_def();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_nest(ns, x);
                }
                                                                                                            default {
                                                                                                                switch (c == TokenType.IF)
                                                                                                                {
                                                                                                                    case (true) {
                    x = this.if_statement();
                    node_free(x);
                }
                                                                                                                    default {
                                                                                                                        switch (this.is_variable_declaration())
                                                                                                                        {
                                                                                                                            case (true) {
                    x = this.variable_declaration();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.ns_add_all(ns, x);
                    this.consume(TokenType.SEMICOLON);
                }
                                                                                                                            default {
                    this.error(g"Expected function, struct, object, namespace, enum, union, or variable declaration\0");
                };
                                                                                                                        };
                                                                                                                    };
                                                                                                                };
                                                                                                            };
                                                                                                        };
                                                                                                    };
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
                ->;
            };

            // namespace_def -> 'namespace' IDENTIFIER (':' IDENTIFIER (',' IDENTIFIER)*)? '{' namespace_item* '}' ';'
            namespace_def() -> Node*
            {
                Node* n = this.mk(NodeKind.NAMESPACE_DEF, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.advance();
                n.text = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.done(n); }
                    default {};
                };

                byte* saved = this.ns_path;
                switch (saved == (byte*)0)
                {
                    case (true) { this.ns_path = n.text; }
                    default { this.ns_path = this.cat2(this.cat2(saved, g"__\0"), n.text); };
                };

                Node* l;
                Node* b;
                switch (this.expect(TokenType.COLON))
                {
                    case (true) {
                    this.advance();
                    l = this.ns_list(n, 2);
                    bool more = !this.failed;
                    while (more)
                    {
                        b = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        node_push(l, 0, b);
                        b.text = this.ident();
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        more = false;
                        switch (this.expect(TokenType.COMMA))
                        {
                            case (true) {
                            this.advance();
                            more = true;
                        }
                            default {};
                        };
                    };
                }
                    default {};
                };

                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.LEFT_BRACE); }
                    default {};
                };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    }
                        default {};
                    };
                    this.ns_item(n);
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                this.ns_path = saved;
                -> this.done(n);
            };

            // ===== ENUMS AND UNIONS =====

            // ENUM_DEF_STATEMENT wrapping a fresh ENUM_DEF. The type is copied when ts is given.
            enum_node(byte* name, TypeSpec* ts, int line, int col) -> Node*
            {
                Node* s = this.mk(NodeKind.ENUM_DEF_STATEMENT, line, col);
                switch (this.failed)
                {
                    case (true) { -> s; }
                    default {};
                };
                Node* d = this.mk(NodeKind.ENUM_DEF, line, col);
                switch (this.failed)
                {
                    case (true) { node_free(s); -> d; }
                    default {};
                };
                s.a = d;
                d.text = name;
                switch (ts != (TypeSpec*)0)
                {
                    case (true) { d.ts = typespec_copy(ts); }
                    default {};
                };
                -> s;
            };

            // enum_def -> (type_spec)? 'enum' IDENTIFIER (',' IDENTIFIER)* (';' | '{' enum_item (',' enum_item)* '}' ';')
            // enum_item -> IDENTIFIER ('=' INTEGER)?
            // Items are IDENTIFIER nodes whose ival is the value.
            enum_def() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* s = this.mk(NodeKind.ENUM_DEF_STATEMENT, line, col);
                switch (this.failed)
                {
                    case (true) { -> s; }
                    default {};
                };
                Node* d = this.mk(NodeKind.ENUM_DEF, line, col);
                switch (this.failed)
                {
                    case (true) { node_free(s); -> d; }
                    default {};
                };
                s.a = d;

                switch (!this.expect(TokenType.ENUM))
                {
                    case (true) { d.ts = this.type_spec(); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(s); }
                    default {};
                };
                switch (!this.consume(TokenType.ENUM))
                {
                    case (true) { -> this.done(s); }
                    default {};
                };
                d.text = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.done(s); }
                    default {};
                };

                PtrVec* names = pv_new();
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    pv_push(names, (void*)this.ident());
                    switch (this.failed)
                    {
                        case (true) {
                        pv_free(names);
                        -> this.done(s);
                    }
                        default {};
                    };
                };

                Node* x;
                int k;
                switch (this.expect(TokenType.SEMICOLON))
                {
                    case (true) {
                    this.advance();
                    while (k < names.len)
                    {
                        x = this.enum_node((byte*)names.items[k], d.ts, line, col);
                        switch (this.failed)
                        {
                            case (true) {
                            pv_free(names);
                            -> this.done(s);
                        }
                            default {};
                        };
                        nv_push(this.pending, x);
                        k++;
                    };
                    pv_free(names);
                    -> s;
                }
                    default {};
                };
                switch (names.len > 0)
                {
                    case (true) {
                    pv_free(names);
                    this.error(g"Comma-separated names are only allowed for prototypes (forward declarations)\0");
                    -> this.done(s);
                }
                    default {};
                };
                pv_free(names);

                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { -> this.done(s); }
                    default {};
                };
                i64 current = 0;
                bool ok;
                Node* item;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    }
                        default {};
                    };
                    item = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    node_push(d, 0, item);
                    item.text = this.ident();
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    switch (this.expect(TokenType.ASSIGN))
                    {
                        case (true) {
                        this.advance();
                        switch (!this.expect(TokenType.SINT_LITERAL))
                        {
                            case (true) {
                            this.fail_expected(TokenType.SINT_LITERAL);
                            break;
                        }
                            default {};
                        };
                        ok = true;
                        current = this.parse_int(this.cur_value(), @ok);
                        this.advance();
                    }
                        default {};
                    };
                    item.ival = current;
                    current++;
                    switch (this.expect(TokenType.COMMA))
                    {
                        case (true) { this.advance(); }
                        default {
                            switch (!this.expect(TokenType.RIGHT_BRACE))
                            {
                                case (true) {
                        this.error(g"Expected ',' or '}' in enum definition\0");
                    }
                                default {};
                            };
                        };
                    };
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(s);
            };

            // union_member -> type_spec IDENTIFIER ('=' expression)? ';'
            union_member(Node* d) -> void
            {
                Node* m = this.mk(NodeKind.UNION_MEMBER, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                node_push(d, 0, m);
                m.ts = this.type_spec();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                m.text = this.ident();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (this.expect(TokenType.ASSIGN))
                {
                    case (true) {
                    this.advance();
                    m.a = this.expression();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                }
                    default {};
                };
                this.consume(TokenType.SEMICOLON);
                ->;
            };

            // union_def -> 'union' IDENTIFIER (';' | '{' union_member* '}' ('#' IDENTIFIER)? ';')
            union_def() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* s = this.mk(NodeKind.UNION_DEF_STATEMENT, line, col);
                switch (this.failed)
                {
                    case (true) { -> s; }
                    default {};
                };
                Node* d = this.mk(NodeKind.UNION_DEF, line, col);
                switch (this.failed)
                {
                    case (true) { node_free(s); -> d; }
                    default {};
                };
                s.a = d;
                this.advance();
                d.text = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.done(s); }
                    default {};
                };
                switch (this.expect(TokenType.SEMICOLON))
                {
                    case (true) {
                    this.advance();
                    -> s;
                }
                    default {};
                };
                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { -> this.done(s); }
                    default {};
                };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    }
                        default {};
                    };
                    this.union_member(d);
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                switch (!this.failed & this.expect(TokenType.TAG))
                {
                    case (true) {
                    this.advance();
                    d.text2 = this.ident();
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(s);
            };

            // ===== OBJECTS AND TRAITS =====

            error3(byte* a, byte* b, byte* c) -> void -> this.error(this.cat2(this.cat2(a, b), c));

            // TRAIT_DEF registered by trait_def, or null
            find_trait(byte* name) -> Node*
            {
                int i;
                Node* t;
                while (i < this.trait_defs.len)
                {
                    t = (Node*)this.trait_defs.items[i];
                    switch (cstr_eq(t.text, name))
                    {
                        case (true) { -> t; }
                        default {};
                    };
                    i++;
                };
                -> (Node*)0;
            };

            // FUNCTION_DEF method of o with this name, or null
            find_method(Node* o, byte* name) -> Node*
            {
                switch (o.l1 == (NodeVec*)0)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                int i;
                Node* m;
                while (i < o.l1.len)
                {
                    m = o.l1.items[i];
                    switch (m.kind == NodeKind.FUNCTION_DEF & m.text != (byte*)0)
                    {
                        case (true) {
                        switch (cstr_eq(m.text, name))
                        {
                            case (true) { -> m; }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> (Node*)0;
            };

            // Parameters other than the implicit 'this'
            explicit_params(Node* f) -> int
            {
                int n, i;
                Node* p;
                while (i < this.param_count(f))
                {
                    p = f.l0.items[i];
                    switch (p.text == (byte*)0)
                    {
                        case (true) { n++; }
                        default {
                            switch (!cstr_eq(p.text, g"this\0"))
                            {
                                case (true) { n++; }
                                default {};
                            };
                        };
                    };
                    i++;
                };
                -> n;
            };

            method_start(int off) -> bool
            {
                int t = this.type_at(off);
                -> t == TokenType.INLINE | t == TokenType.DEF | this.is_calling_conv(t);
            };

            // Prototype stub standing for a template method or template trait prototype
            template_stub() -> Node*
            {
                Node* s = this.mk(NodeKind.FUNCTION_DEF, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> s; }
                    default {};
                };
                s.text = this.last_template;
                TemplateEntry* te = this.template_lookup(this.last_template);
                switch (te != (TemplateEntry*)0)
                {
                    case (true) {
                    switch (te.node != (Node*)0)
                    {
                        case (true) {
                        switch (te.node.ts != (TypeSpec*)0)
                        {
                            case (true) { s.ts = typespec_copy(te.node.ts); }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                this.mark_proto(s);
                s.flags = s.flags `| NF_TEMPLATE;
                -> s;
            };

            add_method(Node* o, Node* m, bool is_private, byte* friend_name, int ovr) -> void
            {
                switch (is_private)
                {
                    case (true) { m.flags = m.flags `| NF_PRIVATE; }
                    default {};
                };
                m.flags = m.flags `| ovr;
                switch (friend_name != (byte*)0)
                {
                    case (true) { m.text3 = friend_name; }
                    default {};
                };
                node_push(o, 1, m);
                ->;
            };

            // One method (and the rest of a prototype list) into o.l1
            collect_method(Node* o, bool is_private, byte* friend_name, int ovr) -> void
            {
                this.last_template = (byte*)0;
                Node* m = this.function_def();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                int k;
                switch (m == (Node*)0)
                {
                    case (true) {
                    switch (this.last_template == (byte*)0)
                    {
                        case (true) {
                        this.error(g"Internal: template method registered no name\0");
                        ->;
                    }
                        default {};
                    };
                    switch (o.text != (byte*)0)
                    {
                        case (true) {
                        this.template_alias(this.cat2(this.cat2(o.text, g".\0"), this.last_template), this.last_template);
                    }
                        default {};
                    };
                    m = this.template_stub();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                }
                    default {};
                };
                this.add_method(o, m, is_private, friend_name, ovr);
                while (k < this.pending.len)
                {
                    this.add_method(o, this.pending.items[k], is_private, friend_name, ovr);
                    k++;
                };
                this.pending.len = 0;
                ->;
            };

            // A nested object or struct (and queued prototypes) into o.l<slot>
            nested_push(Node* o, int slot, Node* x, bool is_private) -> void
            {
                int k;
                switch (x != (Node*)0)
                {
                    case (true) {
                    switch (is_private)
                    {
                        case (true) { x.flags = x.flags `| NF_PRIVATE; }
                        default {};
                    };
                    node_push(o, slot, x);
                }
                    default {};
                };
                while (k < this.pending.len)
                {
                    x = this.pending.items[k];
                    switch (is_private)
                    {
                        case (true) { x.flags = x.flags `| NF_PRIVATE; }
                        default {};
                    };
                    node_push(o, slot, x);
                    k++;
                };
                this.pending.len = 0;
                ->;
            };

            // Field declarations become STRUCT_MEMBER nodes in o.l0
            field_members(Node* o, bool is_private, byte* friend_name) -> void
            {
                Node* v = this.variable_declaration();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                int k;
                switch (v != (Node*)0)
                {
                    case (true) {
                    v.kind = NodeKind.STRUCT_MEMBER;
                    v.flags = 0;
                    switch (is_private)
                    {
                        case (true) { v.flags = NF_PRIVATE; }
                        default {};
                    };
                    v.text2 = friend_name;
                    node_push(o, 0, v);
                }
                    default {};
                };
                while (k < this.pending.len)
                {
                    v = this.pending.items[k];
                    v.kind = NodeKind.STRUCT_MEMBER;
                    v.flags = 0;
                    switch (is_private)
                    {
                        case (true) { v.flags = NF_PRIVATE; }
                        default {};
                    };
                    v.text2 = friend_name;
                    node_push(o, 0, v);
                    k++;
                };
                this.pending.len = 0;
                this.consume(TokenType.SEMICOLON);
                ->;
            };

            // method (with '+' override or '!+' no-override marker), nested object, nested struct or field
            object_member(Node* o, bool is_private, byte* friend_name) -> void
            {
                int ovr = 0;
                switch (this.expect(TokenType.NOT) & this.type_at(1) == TokenType.PLUS & this.method_start(2))
                {
                    case (true) {
                    ovr = NF_NO_OVERRIDE;
                    this.advance();
                    this.advance();
                }
                    default {
                        switch (this.expect(TokenType.PLUS) & this.method_start(1))
                        {
                            case (true) {
                    ovr = NF_OVERRIDE;
                    this.advance();
                }
                            default {};
                        };
                    };
                };
                Node* x;
                switch (this.expect3(TokenType.INLINE, TokenType.DEF, TokenType.CDECL) | this.is_calling_conv(this.cur()) | this.is_bare_function_def())
                {
                    case (true) {
                    this.collect_method(o, is_private, friend_name, ovr);
                }
                    default {
                        switch (this.expect(TokenType.OBJECT))
                        {
                            case (true) {
                    x = this.object_def();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.nested_push(o, 3, x, is_private);
                    this.consume(TokenType.SEMICOLON);
                }
                            default {
                                switch (this.expect(TokenType.STRUCT))
                                {
                                    case (true) {
                    x = this.struct_def();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.nested_push(o, 4, x, is_private);
                    this.consume(TokenType.SEMICOLON);
                }
                                    default {
                    this.field_members(o, is_private, friend_name);
                };
                                };
                            };
                        };
                    };
                };
                ->;
            };

            // Members of an object up to (not including) the closing '}'
            object_body(Node* o) -> void
            {
                bool is_private;
                byte* friend_name;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        ->;
                    }
                        default {};
                    };
                    switch (this.expect2(TokenType.PUBLIC, TokenType.PRIVATE))
                    {
                        case (true) {
                        is_private = this.expect(TokenType.PRIVATE);
                        friend_name = (byte*)0;
                        this.advance();
                        switch (is_private & this.expect(TokenType.COLON))
                        {
                            case (true) {
                            this.advance();
                            friend_name = this.ident();
                        }
                            default {};
                        };
                        switch (!this.failed)
                        {
                            case (true) { this.consume(TokenType.LEFT_BRACE); }
                            default {};
                        };
                        while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                        {
                            switch (this.expect(TokenType.EOF))
                            {
                                case (true) {
                                this.fail_expected(TokenType.RIGHT_BRACE);
                                ->;
                            }
                                default {};
                            };
                            this.object_member(o, is_private, friend_name);
                        };
                        switch (!this.failed)
                        {
                            case (true) { this.consume(TokenType.RIGHT_BRACE); }
                            default {};
                        };
                        switch (!this.failed)
                        {
                            case (true) { this.consume(TokenType.SEMICOLON); }
                            default {};
                        };
                    }
                        default {
                        this.object_member(o, false, (byte*)0);
                    };
                    };
                };
                ->;
            };

            // One interface argument: IDENTIFIER or 'this'
            iface_arg(Node* iface) -> void
            {
                Node* a = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                node_push(iface, 0, a);
                switch (this.expect(TokenType.THIS))
                {
                    case (true) {
                    a.text = g"this\0";
                    this.advance();
                }
                    default {
                    a.text = this.ident();
                };
                };
                ->;
            };

            // '}' ':' Name '(' args ')' (',' Name '(' args ')')*  : NODE_LIST entries in o.e
            iface_attachments(Node* o) -> void
            {
                Node* iface;
                bool more = true;
                while (more & !this.failed)
                {
                    this.advance();
                    iface = this.mk(NodeKind.NODE_LIST, this.cur_line(), this.cur_col());
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (o.e == (Node*)0)
                    {
                        case (true) {
                        o.e = this.mk(NodeKind.NODE_LIST, iface.line, iface.col);
                        switch (this.failed)
                        {
                            case (true) { node_free(iface); ->; }
                            default {};
                        };
                    }
                        default {};
                    };
                    node_push(o.e, 0, iface);
                    iface.text = this.ident();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (!this.consume(TokenType.LEFT_PAREN))
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        case (true) {
                        this.iface_arg(iface);
                        while (!this.failed & this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            this.iface_arg(iface);
                        };
                    }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                    more = this.expect(TokenType.COMMA);
                };
                ->;
            };

            // Trait names go to o.l5 as IDENTIFIER nodes
            object_traits(Node* o, PtrVec* tnames) -> void
            {
                switch (tnames == (PtrVec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                int i;
                Node* t;
                while (i < tnames.len)
                {
                    t = this.mk(NodeKind.IDENTIFIER, o.line, o.col);
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    t.text = (byte*)tnames.items[i];
                    node_push(o, 5, t);
                    i++;
                };
                ->;
            };

            // __init, __exit and __expr are mandatory and have fixed signatures
            check_object_methods(Node* o) -> void
            {
                Node* m = this.find_method(o, g"__init\0");
                switch (m == (Node*)0)
                {
                    case (true) {
                    this.error3(g"Object '\0", o.text, g"' is missing a __init() method. Every object must define 'def __init(...) -> this { ... };' to specify its constructor.\0");
                    ->;
                }
                    default {};
                };
                switch (m.ts == (TypeSpec*)0)
                {
                    case (true) { this.error3(g"Object '\0", o.text, g"': __init() must return 'this'\0"); ->; }
                    default {};
                };
                switch (m.ts.base_type != DataType.THIS)
                {
                    case (true) {
                    this.error3(g"Object '\0", o.text, g"': __init() must return 'this'\0");
                    ->;
                }
                    default {};
                };

                m = this.find_method(o, g"__exit\0");
                switch (m == (Node*)0)
                {
                    case (true) {
                    this.error3(g"Object '\0", o.text, g"' is missing a __exit() method. Every object must define 'def __exit() -> void { ... };' to specify its destructor.\0");
                    ->;
                }
                    default {};
                };
                switch (this.explicit_params(m) > 0)
                {
                    case (true) {
                    this.error3(g"Object '\0", o.text, g"': __exit() must take no parameters\0");
                    ->;
                }
                    default {};
                };
                switch (m.ts != (TypeSpec*)0)
                {
                    case (true) {
                    switch (m.ts.base_type != DataType.VOID | m.ts.pointer_depth > 0)
                    {
                        case (true) {
                        this.error3(g"Object '\0", o.text, g"': __exit() must return void\0");
                        ->;
                    }
                        default {};
                    };
                }
                    default {};
                };

                m = this.find_method(o, g"__expr\0");
                switch (m == (Node*)0)
                {
                    case (true) {
                    this.error3(g"Object '\0", o.text, g"' is missing a __expr() method. Every object must define 'def __expr() -> <type> { ... };' to specify its expression-context value.\0");
                    ->;
                }
                    default {};
                };
                switch (this.explicit_params(m) > 0)
                {
                    case (true) {
                    this.error3(g"Object '\0", o.text, g"': __expr() must take no parameters\0");
                    ->;
                }
                    default {};
                };
                switch (m.ts == (TypeSpec*)0)
                {
                    case (true) {
                    this.error3(g"Object '\0", o.text, g"': __expr() must have a non-void return type\0");
                    ->;
                }
                    default {};
                };
                switch (m.ts.base_type == DataType.VOID & m.ts.pointer_depth == 0)
                {
                    case (true) {
                    this.error3(g"Object '\0", o.text, g"': __expr() must have a non-void return type\0");
                }
                    default {};
                };
                ->;
            };

            // Every non-template prototype of each declared trait must be implemented
            check_object_traits(Node* o) -> void
            {
                switch (o.l5 == (NodeVec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                int i, j, total;
                Node* t;
                Node* p;
                while (i < o.l5.len)
                {
                    t = this.find_trait(o.l5.items[i].text);
                    switch (t == (Node*)0)
                    {
                        case (true) {
                        this.error3(g"Object '\0", o.text, this.cat2(this.cat2(g"' declares trait '\0", o.l5.items[i].text), g"' which has not been defined\0"));
                        ->;
                    }
                        default {};
                    };
                    j = 0;
                    total = 0;
                    switch (t.l0 != (NodeVec*)0)
                    {
                        case (true) { total = t.l0.len; }
                        default {};
                    };
                    while (j < total)
                    {
                        p = t.l0.items[j];
                        switch ((p.flags `& NF_TEMPLATE) == 0 & p.text != (byte*)0)
                        {
                            case (true) {
                            switch (this.find_method(o, p.text) == (Node*)0)
                            {
                                case (true) {
                                this.error3(this.cat2(this.cat2(g"Object '\0", o.text), g"' doesn't implement required function '\0"), p.text, this.cat2(this.cat2(g"' from trait '\0", t.text), g"'\0"));
                                ->;
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                        j++;
                    };
                    i++;
                };
                ->;
            };

            // One object template parameter: IDENTIFIER into o.d and te.params
            object_tparam(Node* o, TemplateEntry* te) -> void
            {
                Node* x = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                x.text = this.ident();
                switch (this.failed)
                {
                    case (true) {
                    node_free(x);
                    ->;
                }
                    default {};
                };
                node_push(o.d, 0, x);
                pv_push(te.params, (void*)this.own(ts_dup(x.text)));
                ->;
            };

            // object_def -> 'object' IDENTIFIER (',' IDENTIFIER)* (':' bases)? (';' | '{' body '}' (':' interface attachments)? ';')
            // m is the mark of the start of the construct (before any trait names).
            // Template objects and objects with base objects are reported (no inheritance resolution).
            object_with_traits(int m, PtrVec* tnames) -> Node*
            {
                NameMap* prev_act = this.active_tp;
                TemplateEntry* prev_cur = this.tmpl_cur;
                TemplateEntry* te;
                Node* o;
                this.tmpl_cur = (TemplateEntry*)0;
                o = this.object_with_traits_inner(m, tnames);
                te = this.tmpl_cur;
                this.tmpl_cur = prev_cur;
                switch (this.active_tp != prev_act)
                {
                    case (true) {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                }
                    default {};
                };
                switch (te == (TemplateEntry*)0)
                {
                    case (true) { -> o; }
                    default {};
                };
                switch (this.failed | o == (Node*)0)
                {
                    case (true) {
                    te_free(te);
                    -> o;
                }
                    default {};
                };
                switch ((o.flags `& NF_PROTOTYPE) != 0)
                {
                    case (true) {
                    te_free(te);
                    -> o;
                }
                    default {};
                };
                this.last_template = o.text;
                switch (this.in_comptime > 0)
                {
                    case (true) {
                    this.register_template(o.text, 2, te, node_clone(o));
                    -> o;
                }
                    default {};
                };
                this.register_template(o.text, 2, te, o);
                -> (Node*)0;
            };

            object_with_traits_inner(int m, PtrVec* tnames) -> Node*
            {
                Node* o = this.mk(NodeKind.OBJECT_DEF, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> o; }
                    default {};
                };
                this.advance();
                o.text = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.done(o); }
                    default {};
                };

                switch (this.expect(TokenType.LESS_THAN) & this.is_template_list())
                {
                    case (true) {
                    TemplateEntry* te = te_new();
                    Node* pl = this.mk(NodeKind.NODE_LIST, o.line, o.col);
                    switch (this.failed)
                    {
                        case (true) {
                        te_free(te);
                        -> this.done(o);
                    }
                        default {};
                    };
                    o.d = pl;
                    this.advance();
                    this.object_tparam(o, te);
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        this.object_tparam(o, te);
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.GREATER_THAN); }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) {
                        te_free(te);
                        -> this.done(o);
                    }
                        default {};
                    };
                    this.tmpl_cur = te;
                    this.tp_activate(te);
                }
                    default {};
                };
                this.object_traits(o, tnames);

                PtrVec* names = pv_new();
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    pv_push(names, (void*)this.ident());
                    switch (this.failed)
                    {
                        case (true) { pv_free(names); -> this.done(o); }
                        default {};
                    };
                };

                Node* b;
                bool more;
                switch (this.expect(TokenType.COLON))
                {
                    case (true) {
                    switch (names.len > 0)
                    {
                        case (true) {
                        pv_free(names);
                        this.error(g"Cannot use comma-separated prototype names with an inheritance list\0");
                        -> this.done(o);
                    }
                        default {};
                    };
                    this.advance();
                    more = true;
                    while (more & !this.failed)
                    {
                        b = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        node_push(o, 2, b);
                        b.text = this.ident();
                        more = false;
                        switch (!this.failed & this.expect(TokenType.COMMA))
                        {
                            case (true) {
                            this.advance();
                            more = !this.expect2(TokenType.LEFT_BRACE, TokenType.SEMICOLON);
                        }
                            default {};
                        };
                    };
                    switch (this.failed)
                    {
                        case (true) { pv_free(names); -> this.done(o); }
                        default {};
                    };
                }
                    default {};
                };

                int k;
                Node* x;
                switch (this.expect(TokenType.SEMICOLON))
                {
                    case (true) {
                    this.advance();
                    o.flags = NF_PROTOTYPE;
                    switch (o.d != (Node*)0)
                    {
                        case (true) {
                        node_free(o.d);
                        o.d = (Node*)0;
                    }
                        default {};
                    };
                    while (k < names.len)
                    {
                        x = this.mk(NodeKind.OBJECT_DEF, o.line, o.col);
                        switch (this.failed)
                        {
                            case (true) { pv_free(names); -> this.done(o); }
                            default {};
                        };
                        x.flags = NF_PROTOTYPE;
                        x.text = (byte*)names.items[k];
                        this.object_traits(x, tnames);
                        nv_push(this.pending, x);
                        k++;
                    };
                    pv_free(names);
                    -> o;
                }
                    default {};
                };
                switch (names.len > 0)
                {
                    case (true) {
                    pv_free(names);
                    this.error(g"Comma-separated names are only allowed for prototypes (forward declarations)\0");
                    -> this.done(o);
                }
                    default {};
                };
                pv_free(names);

                switch (o.d != (Node*)0)
                {
                    case (true) { nm_put(this.tobj_fwd, o.text, (void*)o); }
                    default {};
                };
                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { -> this.done(o); }
                    default {};
                };
                switch (this.st != (FXC_SYMTABLE*)0)
                {
                    case (true) { st_enter_scope(this.st); }
                    default {};
                };
                this.object_body(o);
                switch (this.st != (FXC_SYMTABLE*)0)
                {
                    case (true) { st_exit_scope(this.st); }
                    default {};
                };
                switch (o.d != (Node*)0)
                {
                    case (true) { nm_del(this.tobj_fwd, o.text); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(o); }
                    default {};
                };
                this.consume(TokenType.RIGHT_BRACE);
                switch (!this.failed & this.expect(TokenType.COLON))
                {
                    case (true) { this.iface_attachments(o); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(o); }
                    default {};
                };

                switch (node_count(o, 2) > 0)
                {
                    case (true) { this.resolve_inheritance(o); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(o); }
                    default {};
                };
                switch (this.find_method(o, g"__init\0") != (Node*)0)
                {
                    case (true) { nm_put(this.oinit, o.text, (void*)o); }
                    default {};
                };
                this.check_object_methods(o);
                switch (!this.failed)
                {
                    case (true) { this.check_object_traits(o); }
                    default {};
                };
                switch (!this.failed & o.d == (Node*)0)
                {
                    case (true) { nm_put(this.pobjs, o.text, (void*)o); }
                    default {};
                };
                -> this.done(o);
            };

            // ----- object inheritance (fparser._resolve_inheritance) -----

            inh_in_path(PtrVec* path, byte* n) -> bool
            {
                int i;
                while (i < path.len)
                {
                    switch (cstr_eq((byte*)path.items[i], n))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    i++;
                };
                -> false;
            };

            // Members of the parent chain of obj, parents first, each paired with its origin object
            inh_members(byte* obj, PtrVec* path, PtrVec* outm, PtrVec* outo, byte* child) -> void
            {
                Node* ob;
                Node* m;
                int i, c;
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (this.inh_in_path(path, obj))
                {
                    case (true) { ->; }
                    default {};
                };
                pv_push(path, (void*)obj);
                switch (!nm_has(this.pobjs, obj))
                {
                    case (true) {
                    this.error(this.cat2(this.cat2(this.cat2(this.cat2(g"Inheritance error: '\0", obj), g"' must be fully defined before '\0"), child), g"' can inherit from it\0"));
                    path.len--;
                    ->;
                }
                    default {};
                };
                ob = (Node*)nm_get(this.pobjs, obj);
                c = node_count(ob, 2);
                while (i < c)
                {
                    this.inh_members(node_child(ob, 2, i).text, path, outm, outo, child);
                    i++;
                };
                i = 0;
                c = node_count(ob, 0);
                while (i < c)
                {
                    m = node_child(ob, 0, i);
                    i++;
                    switch ((m.flags `& NF_PRIVATE) != 0)
                    {
                        case (true) {
                        switch (m.text2 != (byte*)0)
                        {
                            case (true) {
                            switch (cstr_eq(m.text2, child))
                            {
                                case (true) {
                                pv_push(outm, (void*)m);
                                pv_push(outo, (void*)obj);
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {
                        pv_push(outm, (void*)m);
                        pv_push(outo, (void*)obj);
                    };
                    };
                };
                path.len--;
                ->;
            };

            inh_methods(byte* obj, PtrVec* path, PtrVec* outm, byte* child) -> void
            {
                Node* ob;
                Node* m;
                int i, c;
                switch (this.inh_in_path(path, obj))
                {
                    case (true) { ->; }
                    default {};
                };
                pv_push(path, (void*)obj);
                switch (!nm_has(this.pobjs, obj))
                {
                    case (true) {
                    path.len--;
                    ->;
                }
                    default {};
                };
                ob = (Node*)nm_get(this.pobjs, obj);
                c = node_count(ob, 2);
                while (i < c)
                {
                    this.inh_methods(node_child(ob, 2, i).text, path, outm, child);
                    i++;
                };
                i = 0;
                c = node_count(ob, 1);
                while (i < c)
                {
                    m = node_child(ob, 1, i);
                    i++;
                    switch (m.kind != NodeKind.FUNCTION_DEF | m.text == (byte*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (cstr_eq(m.text, g"__init\0") | cstr_eq(m.text, g"__exit\0") | cstr_eq(m.text, g"__expr\0"))
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch ((m.flags `& NF_PRIVATE) != 0)
                    {
                        case (true) {
                        switch (m.text3 != (byte*)0)
                        {
                            case (true) {
                            switch (cstr_eq(m.text3, child))
                            {
                                case (true) { pv_push(outm, (void*)m); }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default { pv_push(outm, (void*)m); };
                    };
                };
                path.len--;
                ->;
            };

            // The node an inherited clone was copied from (fparser compares the FunctionDef objects)
            inh_origin(Node* m) -> Node*
            {
                int i;
                while (i < this.inh_clone.len)
                {
                    switch ((Node*)this.inh_clone.items[i] == m)
                    {
                        case (true) { -> (Node*)this.inh_orig.items[i]; }
                        default {};
                    };
                    i++;
                };
                -> m;
            };

            inh_clone_of(Node* m) -> Node*
            {
                Node* c = node_clone(m);
                pv_push(this.inh_clone, (void*)c);
                pv_push(this.inh_orig, (void*)this.inh_origin(m));
                -> c;
            };

            method_has_body(Node* m) -> bool
            {
                switch (m.a == (Node*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> node_count(m.a, 0) > 0;
            };

            // name(type, type) of a method without its 'this' parameter
            sig_key(Node* m, bool for_message) -> byte*
            {
                int i;
                int c = node_count(m, 0);
                Node* p;
                bool first = true;
                byte* t;
                PtrVec* parts = pv_new();
                while (i < c)
                {
                    p = node_child(m, 0, i);
                    i++;
                    switch (p.text != (byte*)0)
                    {
                        case (true) {
                        switch (cstr_eq(p.text, g"this\0"))
                        {
                            case (true) { continue; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (p.ts == (TypeSpec*)0)
                    {
                        case (true) { t = g"\0"; }
                        default { t = this.tp_repr(p.ts); };
                    };
                    pv_push(parts, (void*)t);
                };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                switch (!for_message)
                {
                    case (true) {
                    this.sb.put_str(m.text);
                    this.sb.put_str(g"(\0");
                }
                    default {};
                };
                i = 0;
                while (i < parts.len)
                {
                    switch (i > 0)
                    {
                        case (true) {
                        switch (for_message)
                        {
                            case (true) { this.sb.put_str(g", \0"); }
                            default { this.sb.put_str(g",\0"); };
                        };
                    }
                        default {};
                    };
                    this.sb.put_str((byte*)parts.items[i]);
                    i++;
                };
                pv_free(parts);
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            inh_key_has(PtrVec* keys, byte* k) -> int
            {
                int i;
                while (i < keys.len)
                {
                    switch (cstr_eq((byte*)keys.items[i], k))
                    {
                        case (true) { -> i; }
                        default {};
                    };
                    i++;
                };
                -> -1;
            };

            // Name of the object whose method list holds exactly m, or "?"
            inh_source(Node* m) -> byte*
            {
                int i, j, c;
                Node* ob;
                while (i < this.pobjs.count)
                {
                    ob = (Node*)this.pobjs.vals[i];
                    i++;
                    switch (ob == (Node*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    c = node_count(ob, 1);
                    j = 0;
                    while (j < c)
                    {
                        switch (node_child(ob, 1, j) == m)
                        {
                            case (true) { -> ob.text; }
                            default {};
                        };
                        j++;
                    };
                };
                -> g"?\0";
            };

            resolve_inheritance(Node* o) -> void
            {
                byte* child = o.text;
                PtrVec* path = pv_new();
                PtrVec* pm = pv_new();
                PtrVec* po = pv_new();
                PtrVec* seen_n = pv_new();
                PtrVec* seen_o = pv_new();
                PtrVec* dedup = pv_new();
                PtrVec* own_m = pv_new();
                PtrVec* own_f = pv_new();
                PtrVec* inh = pv_new();
                PtrVec* ukeys = pv_new();
                PtrVec* ucands = pv_new();
                PtrVec* okeys = pv_new();
                PtrVec* final_inh = pv_new();
                PtrVec* fkeys = pv_new();
                PtrVec* kept = pv_new();
                PtrVec* cand;
                Node* m;
                Node* x;
                byte* k;
                byte* prev;
                byte* msg;
                int i, j, c, nb, idx;
                bool dup, wins;
                nb = node_count(o, 2);
                i = 0;
                while (i < nb & !this.failed)
                {
                    pv_free(path);
                    path = pv_new();
                    this.inh_members(node_child(o, 2, i).text, path, pm, po, child);
                    i++;
                };
                // members: duplicates of one origin are dropped, different origins conflict
                i = 0;
                while (i < pm.len & !this.failed)
                {
                    m = (Node*)pm.items[i];
                    idx = this.inh_key_has(seen_n, m.text);
                    switch (idx >= 0)
                    {
                        case (true) {
                        prev = (byte*)seen_o.items[idx];
                        switch (!cstr_eq(prev, (byte*)po.items[i]))
                        {
                            case (true) {
                            this.error(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(g"Inheritance conflict: member '\0", m.text), g"' is defined in both '\0"), prev), g"' and '\0"), (byte*)po.items[i]), g"', inherited by '\0"), this.cat2(child, g"'\0")));
                        }
                            default {};
                        };
                    }
                        default {
                        pv_push(seen_n, (void*)m.text);
                        pv_push(seen_o, po.items[i]);
                        pv_push(dedup, (void*)m);
                    };
                    };
                    i++;
                };
                c = node_count(o, 0);
                i = 0;
                while (i < c)
                {
                    pv_push(own_m, (void*)node_child(o, 0, i));
                    i++;
                };
                i = 0;
                while (i < dedup.len & !this.failed)
                {
                    m = (Node*)dedup.items[i];
                    j = 0;
                    while (j < own_m.len)
                    {
                        switch (cstr_eq(((Node*)own_m.items[j]).text, m.text))
                        {
                            case (true) {
                            this.error(this.cat2(this.cat2(this.cat2(this.cat2(g"Inheritance conflict: member '\0", m.text), g"' is defined in both a parent of '\0"), child), g"' itself\0"));
                            break;
                        }
                            default {};
                        };
                        j++;
                    };
                    i++;
                };
                // methods
                switch (!this.failed)
                {
                    case (true) {
                    i = 0;
                    while (i < nb)
                    {
                        pv_free(path);
                        path = pv_new();
                        this.inh_methods(node_child(o, 2, i).text, path, inh, child);
                        i++;
                    };
                    i = 0;
                    while (i < inh.len)
                    {
                        m = (Node*)inh.items[i];
                        k = this.sig_key(m, false);
                        idx = this.inh_key_has(ukeys, k);
                        switch (idx < 0)
                        {
                            case (true) {
                            pv_push(ukeys, (void*)k);
                            cand = pv_new();
                            pv_push(ucands, (void*)cand);
                            idx = ukeys.len - 1;
                        }
                            default {};
                        };
                        cand = (PtrVec*)ucands.items[idx];
                        dup = false;
                        j = 0;
                        while (j < cand.len)
                        {
                            switch (this.inh_origin((Node*)cand.items[j]) == this.inh_origin(m))
                            {
                                case (true) { dup = true; }
                                default {};
                            };
                            j++;
                        };
                        switch (!dup)
                        {
                            case (true) { pv_push(cand, (void*)m); }
                            default {};
                        };
                        i++;
                    };
                    c = node_count(o, 1);
                    i = 0;
                    while (i < c)
                    {
                        pv_push(own_f, (void*)node_child(o, 1, i));
                        i++;
                    };
                    // signatures the child wins: explicit override or a real body
                    i = 0;
                    while (i < own_f.len)
                    {
                        m = (Node*)own_f.items[i];
                        i++;
                        switch (m.kind != NodeKind.FUNCTION_DEF)
                        {
                            case (true) { continue; }
                            default {};
                        };
                        switch ((m.flags `& NF_OVERRIDE) != 0 | this.method_has_body(m))
                        {
                            case (true) { pv_push(okeys, (void*)this.sig_key(m, false)); }
                            default {};
                        };
                    };
                    i = 0;
                    while (i < okeys.len & !this.failed)
                    {
                        idx = this.inh_key_has(ukeys, (byte*)okeys.items[i]);
                        i++;
                        switch (idx < 0)
                        {
                            case (true) { continue; }
                            default {};
                        };
                        cand = (PtrVec*)ucands.items[idx];
                        j = 0;
                        while (j < cand.len)
                        {
                            x = (Node*)cand.items[j];
                            switch ((x.flags `& NF_NO_OVERRIDE) != 0)
                            {
                                case (true) {
                                this.error(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(g"Override error: method '\0", x.text), g"(\0"), this.sig_key(x, true)), g")' is marked no-override in a parent of '\0"), this.cat2(child, g"'\0")));
                                break;
                            }
                                default {};
                            };
                            j++;
                        };
                    };
                    i = 0;
                    while (i < ukeys.len & !this.failed)
                    {
                        idx = i;
                        i++;
                        switch (this.inh_key_has(okeys, (byte*)ukeys.items[idx]) >= 0)
                        {
                            case (true) { continue; }
                            default {};
                        };
                        cand = (PtrVec*)ucands.items[idx];
                        switch (cand.len)
                        {
                            case (1)
                            {
                                pv_push(final_inh, cand.items[0]);
                                pv_push(fkeys, ukeys.items[idx]);
                            }
                            default
                            {
                                x = (Node*)cand.items[0];
                                msg = this.cat2(g"Inheritance conflict: method '\0", x.text);
                                msg = this.cat2(this.cat2(msg, g"(\0"), this.sig_key(x, true));
                                msg = this.cat2(this.cat2(msg, g")' has different implementations in '\0"), this.inh_source(x));
                                msg = this.cat2(this.cat2(msg, g"' and '\0"), this.inh_source((Node*)cand.items[1]));
                                msg = this.cat2(this.cat2(msg, g"'. Object '\0"), child);
                                this.error(this.cat2(msg, g"' must override it.\0"));
                            };
                        };
                    };
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) {
                    // rebuild the member and method lists of o
                    switch (o.l0 != (NodeVec*)0)
                    {
                        case (true) { o.l0.len = 0; }
                        default {};
                    };
                    i = 0;
                    while (i < dedup.len)
                    {
                        node_push(o, 0, node_clone((Node*)dedup.items[i]));
                        i++;
                    };
                    i = 0;
                    while (i < own_m.len)
                    {
                        node_push(o, 0, (Node*)own_m.items[i]);
                        i++;
                    };
                    switch (o.l1 != (NodeVec*)0)
                    {
                        case (true) { o.l1.len = 0; }
                        default {};
                    };
                    i = 0;
                    while (i < own_f.len)
                    {
                        m = (Node*)own_f.items[i];
                        i++;
                        switch (m.kind != NodeKind.FUNCTION_DEF)
                        {
                            case (true) {
                            node_push(o, 1, m);
                            continue;
                        }
                            default {};
                        };
                        switch ((m.flags `& NF_OVERRIDE) != 0 | this.method_has_body(m) | this.inh_key_has(fkeys, this.sig_key(m, false)) < 0)
                        {
                            case (true) {
                            node_push(o, 1, m);
                        }
                            default { node_free(m); };
                        };
                    };
                    i = 0;
                    while (i < final_inh.len)
                    {
                        node_push(o, 1, this.inh_clone_of((Node*)final_inh.items[i]));
                        i++;
                    };
                }
                    default {};
                };
                i = 0;
                while (i < ucands.len)
                {
                    pv_free((PtrVec*)ucands.items[i]);
                    i++;
                };
                pv_free(path);
                pv_free(pm);
                pv_free(po);
                pv_free(seen_n);
                pv_free(seen_o);
                pv_free(dedup);
                pv_free(own_m);
                pv_free(own_f);
                pv_free(inh);
                pv_free(ukeys);
                pv_free(ucands);
                pv_free(okeys);
                pv_free(final_inh);
                pv_free(fkeys);
                pv_free(kept);
                ->;
            };

            // True when `Type name = expr` is rewritten as the constructor call Type.__init(expr)
            ctor_sugar(byte* raw, Node* rhs) -> bool
            {
                Node* ob;
                Node* ini;
                COp* c;
                int i;
                switch (raw == (byte*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (!nm_has(this.oinit, raw))
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (rhs.kind == NodeKind.FUNCTION_CALL & rhs.text != (byte*)0)
                {
                    case (true) {
                    while (i < this.cops.len)
                    {
                        c = (COp*)this.cops.items[i];
                        i++;
                        switch (c.kind == 0)
                        {
                            case (true) {
                            switch (cstr_eq(c.func, rhs.text))
                            {
                                case (true) { -> false; }
                                default {};
                            };
                        }
                            default {};
                        };
                    };
                }
                    default {};
                };
                ob = (Node*)nm_get(this.oinit, raw);
                ini = this.find_method(ob, g"__init\0");
                switch (ini == (Node*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> this.explicit_params(ini) == 1;
            };

            object_def() -> Node* -> this.object_with_traits(this.mark(), (PtrVec*)0);

            // IDENTIFIER+ 'object' ...   (the identifiers are trait names)
            trait_prefixed_object() -> Node*
            {
                int m = this.mark();
                PtrVec* tn = pv_new();
                while (this.expect(TokenType.IDENTIFIER))
                {
                    pv_push(tn, (void*)this.cur_value());
                    this.advance();
                    switch (this.expect(TokenType.OBJECT))
                    {
                        case (true) { break; }
                        default {};
                    };
                };
                Node* o = this.object_with_traits(m, tn);
                pv_free(tn);
                -> o;
            };

            // trait_def -> 'trait' IDENTIFIER ('=' IDENTIFIER ('&' IDENTIFIER)* ';' | '{' (function_def)* '}' ';')
            trait_def() -> Node*
            {
                Node* t = this.mk(NodeKind.TRAIT_DEF, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> t; }
                    default {};
                };
                this.advance();
                t.text = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.done(t); }
                    default {};
                };

                Node* base;
                Node* p;
                Node* x;
                byte* bname;
                int i, total;
                bool more;
                switch (this.expect(TokenType.ASSIGN))
                {
                    case (true) {
                    // Composition: the prototypes of every named trait are copied in
                    this.advance();
                    more = true;
                    while (more & !this.failed)
                    {
                        bname = this.ident();
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        base = this.find_trait(bname);
                        switch (base == (Node*)0)
                        {
                            case (true) {
                            this.error3(this.cat2(this.cat2(g"Trait composition error: '\0", bname), g"' must be defined before it can be composed into '\0"), t.text, g"'\0");
                            break;
                        }
                            default {};
                        };
                        i = 0;
                        total = 0;
                        switch (base.l0 != (NodeVec*)0)
                        {
                            case (true) { total = base.l0.len; }
                            default {};
                        };
                        while (i < total)
                        {
                            x = node_clone(base.l0.items[i]);
                            node_push(t, 0, x);
                            i++;
                        };
                        more = false;
                        switch (this.expect(TokenType.LOGICAL_AND))
                        {
                            case (true) {
                            this.advance();
                            more = true;
                        }
                            default {};
                        };
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) { -> this.done(t); }
                        default {};
                    };
                    pv_push(this.trait_defs, (void*)t);
                    -> t;
                }
                    default {};
                };

                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { -> this.done(t); }
                    default {};
                };
                this.in_trait++;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    }
                        default {};
                    };
                    switch (this.expect3(TokenType.INLINE, TokenType.DEF, TokenType.CDECL) | this.is_calling_conv(this.cur()) | this.is_bare_function_def())
                    {
                        case (true) {
                        this.last_template = (byte*)0;
                        p = this.function_def();
                        switch (this.failed)
                        {
                            case (true) { break; }
                            default {};
                        };
                        switch (p == (Node*)0)
                        {
                            case (true) {
                            switch (this.last_template == (byte*)0)
                            {
                                case (true) {
                                this.error(g"Internal: template prototype registered no name\0");
                                break;
                            }
                                default {};
                            };
                            p = this.template_stub();
                            switch (this.failed)
                            {
                                case (true) { break; }
                                default {};
                            };
                        }
                            default {};
                        };
                        node_push(t, 0, p);
                        i = 0;
                        while (i < this.pending.len)
                        {
                            node_push(t, 0, this.pending.items[i]);
                            i++;
                        };
                        this.pending.len = 0;
                    }
                        default {
                        this.error3(g"Expected 'def' inside trait '\0", t.text, g"'\0");
                    };
                    };
                };
                this.in_trait--;
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(t); }
                    default {};
                };
                pv_push(this.trait_defs, (void*)t);
                -> t;
            };

            // ===== CUSTOM OPERATORS =====

            // Source text of an operator symbol token, or null when the token cannot be part of one
            tok_symbol(int t) -> byte*
            {
                switch (t)
                {
                    case (TokenType.PLUS)          { -> g"+\0"; }
                    case (TokenType.MINUS)         { -> g"-\0"; }
                    case (TokenType.MULTIPLY)      { -> g"*\0"; }
                    case (TokenType.DIVIDE)        { -> g"/\0"; }
                    case (TokenType.MODULO)        { -> g"%\0"; }
                    case (TokenType.LESS_THAN)     { -> g"<\0"; }
                    case (TokenType.GREATER_THAN)  { -> g">\0"; }
                    case (TokenType.ASSIGN)        { -> g"=\0"; }
                    case (TokenType.LOGICAL_OR)    { -> g"|\0"; }
                    case (TokenType.LOGICAL_AND)   { -> g"&\0"; }
                    case (TokenType.BITXOR_OP)     { -> g"^\0"; }
                    case (TokenType.NOT)           { -> g"!\0"; }
                    case (TokenType.QUESTION)      { -> g"?\0"; }
                    case (TokenType.ADDRESS_OF)    { -> g"@\0"; }
                    case (TokenType.TIE)           { -> g"~\0"; }
                    case (TokenType.INCREMENT)     { -> g"++\0"; }
                    case (TokenType.DECREMENT)     { -> g"--\0"; }
                    case (TokenType.EQUAL)         { -> g"==\0"; }
                    case (TokenType.NOT_EQUAL)     { -> g"!=\0"; }
                    case (TokenType.LESS_EQUAL)    { -> g"<=\0"; }
                    case (TokenType.GREATER_EQUAL) { -> g">=\0"; }
                    case (TokenType.NAND_OP)       { -> g"!&\0"; }
                    case (TokenType.NOR_OP)        { -> g"!|\0"; }
                    case (TokenType.XOR_OP)        { -> g"^|\0"; }
                    case (TokenType.BITSHIFT_LEFT) { -> g"<<\0"; }
                    case (TokenType.BITSHIFT_RIGHT){ -> g">>\0"; }
                    case (TokenType.BITNAND_OP)    { -> g"`!&\0"; }
                    case (TokenType.BITNOR_OP)     { -> g"`!|\0"; }
                    case (TokenType.BITXNAND)      { -> g"`^|!&\0"; }
                    case (TokenType.BITXNOR)       { -> g"`^|!|\0"; }
                    case (TokenType.LEFT_PAREN)    { -> g"(\0"; }
                    case (TokenType.RIGHT_PAREN)   { -> g")\0"; }
                    case (TokenType.LEFT_BRACE)    { -> g"{\0"; }
                    case (TokenType.RIGHT_BRACE)   { -> g"}\0"; }
                    case (TokenType.LEFT_BRACKET)  { -> g"[\0"; }
                    case (TokenType.RIGHT_BRACKET) { -> g"]\0"; }
                    case (TokenType.SEMICOLON)     { -> g";\0"; }
                    case (TokenType.COLON)         { -> g":\0"; }
                    case (TokenType.COMMA)         { -> g",\0"; }
                    case (TokenType.DOT)           { -> g".\0"; }
                    case (TokenType.RETURN_ARROW)  { -> g"->\0"; }
                    case (TokenType.SCOPE)         { -> g"::\0"; }
                    case (TokenType.BACKSLASH)     { -> g"\\\0"; }
                    case (TokenType.STRINGIFY)     { -> g"$\0"; }
                    case (TokenType.TAG)           { -> g"#\0"; }
                    default                        { -> (byte*)0; };
                };
                -> (byte*)0;
            };

            // Mangled name of one symbol character, or null when it is written as hex
            char_mangle(int c) -> byte*
            {
                switch (c == '%')
                {
                    case (true) { -> g"pct\0"; }
                    default {};
                };
                switch (c == '+')
                {
                    case (true) { -> g"plus\0"; }
                    default {};
                };
                switch (c == '-')
                {
                    case (true) { -> g"minus\0"; }
                    default {};
                };
                switch (c == '*')
                {
                    case (true) { -> g"mul\0"; }
                    default {};
                };
                switch (c == '/')
                {
                    case (true) { -> g"div\0"; }
                    default {};
                };
                switch (c == '<')
                {
                    case (true) { -> g"lt\0"; }
                    default {};
                };
                switch (c == '>')
                {
                    case (true) { -> g"gt\0"; }
                    default {};
                };
                switch (c == '=')
                {
                    case (true) { -> g"eq\0"; }
                    default {};
                };
                switch (c == '&')
                {
                    case (true) { -> g"amp\0"; }
                    default {};
                };
                switch (c == '|')
                {
                    case (true) { -> g"pipe\0"; }
                    default {};
                };
                switch (c == '^')
                {
                    case (true) { -> g"xor\0"; }
                    default {};
                };
                switch (c == '!')
                {
                    case (true) { -> g"not\0"; }
                    default {};
                };
                switch (c == '?')
                {
                    case (true) { -> g"qst\0"; }
                    default {};
                };
                switch (c == '@')
                {
                    case (true) { -> g"at\0"; }
                    default {};
                };
                switch (c == '~')
                {
                    case (true) { -> g"tilde\0"; }
                    default {};
                };
                switch (c == '\\')
                {
                    case (true) { -> g"bslash\0"; }
                    default {};
                };
                switch (c == '$')
                {
                    case (true) { -> g"dol\0"; }
                    default {};
                };
                -> (byte*)0;
            };

            // Value text of the token at offset off
            val_at(int off) -> byte* -> this.lx.token_value(this.pos + off);

            // True when the tokens at the cursor are exactly the symbol s
            opsym_match(OpSym* s) -> bool
            {
                int i, t;
                while (i < s.n)
                {
                    t = this.type_at(i);
                    switch (t != s.t[i])
                    {
                        case (true) { -> false; }
                        default {};
                    };
                    switch (t == TokenType.IDENTIFIER)
                    {
                        case (true) {
                        switch (!cstr_eq(this.val_at(i), s.v[i]))
                        {
                            case (true) { -> false; }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> true;
            };

            opsym_same(OpSym* a, OpSym* b) -> bool
            {
                switch (a.n != b.n)
                {
                    case (true) { -> false; }
                    default {};
                };
                int i;
                while (i < a.n)
                {
                    switch (a.t[i] != b.t[i])
                    {
                        case (true) { -> false; }
                        default {};
                    };
                    switch (a.t[i] == TokenType.IDENTIFIER)
                    {
                        case (true) {
                        switch (!cstr_eq(a.v[i], b.v[i]))
                        {
                            case (true) { -> false; }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> true;
            };

            opsym_free(OpSym* s) -> void
            {
                switch (s == (OpSym*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (s.t != (int*)0)
                {
                    case (true) { ffree((byte*)s.t); }
                    default {};
                };
                switch (s.v != (byte**)0)
                {
                    case (true) { ffree((byte*)s.v); }
                    default {};
                };
                ffree((byte*)s);
                ->;
            };

            // '[' symbol tokens ']'
            op_bracket() -> OpSym*
            {
                OpSym* s = (OpSym*)fmalloc((u64)((sizeof(OpSym) + 7) / 8));
                switch (s == (OpSym*)0)
                {
                    case (true) {
                    this.fail_alloc();
                    -> s;
                }
                    default {};
                };
                s.n = 0;
                s.t = (int*)0;
                s.v = (byte**)0;
                switch (!this.consume(TokenType.LEFT_BRACKET))
                {
                    case (true) { -> s; }
                    default {};
                };
                int m = this.mark();
                int cnt, i, tt;
                while (!this.expect(TokenType.RIGHT_BRACKET))
                {
                    switch (this.expect(TokenType.EOF))
                    {
                        case (true) {
                        this.fail_expected(TokenType.RIGHT_BRACKET);
                        this.reset(m);
                        -> s;
                    }
                        default {};
                    };
                    cnt++;
                    this.advance();
                };
                this.reset(m);
                s.t = (int*)fmalloc((u64)(cnt + 1) * (u64)((sizeof(int) + 7) / 8));
                s.v = (byte**)fmalloc((u64)(cnt + 1) * (u64)((sizeof(byte*) + 7) / 8));
                while (i < cnt)
                {
                    tt = this.cur();
                    switch (tt == TokenType.IDENTIFIER)
                    {
                        case (true) {
                        s.t[i] = tt;
                        s.v[i] = this.cur_value();
                    }
                        default {
                            switch (this.tok_symbol(tt) != (byte*)0)
                            {
                                case (true) {
                        s.t[i] = tt;
                        s.v[i] = (byte*)0;
                    }
                                default {
                        this.error3(g"Token '\0", this.cur_value(), g"' cannot be part of an operator symbol\0");
                        -> s;
                    };
                            };
                        };
                    };
                    this.advance();
                    i++;
                    s.n = i;
                };
                this.consume(TokenType.RIGHT_BRACKET);
                -> s;
            };

            // Symbol text, e.g. "$%"
            opsym_text(OpSym* s) -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                int i;
                while (i < s.n)
                {
                    switch (s.t[i] == TokenType.IDENTIFIER)
                    {
                        case (true) { this.sb.put_str(s.v[i]); }
                        default { this.sb.put_str(this.tok_symbol(s.t[i])); };
                    };
                    i++;
                };
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            put_hex_digit(int d) -> void
            {
                switch (d < 10)
                {
                    case (true) { this.sb.put(48 + d); }
                    default { this.sb.put(87 + d); };
                };
                ->;
            };

            // Appends the mangled form of s to sb
            mangle_into(OpSym* s) -> void
            {
                int i, j, c;
                byte* sym;
                byte* nm;
                while (i < s.n)
                {
                    switch (i > 0)
                    {
                        case (true) { this.sb.put('_'); }
                        default {};
                    };
                    switch (s.t[i] == TokenType.IDENTIFIER)
                    {
                        case (true) { this.sb.put_str(s.v[i]); }
                        default {
                        sym = this.tok_symbol(s.t[i]);
                        j = 0;
                        while (sym[j] != 0)
                        {
                            switch (j > 0)
                            {
                                case (true) { this.sb.put('_'); }
                                default {};
                            };
                            c = (int)sym[j];
                            nm = this.char_mangle(c);
                            switch (nm != (byte*)0)
                            {
                                case (true) { this.sb.put_str(nm); }
                                default {
                                this.sb.put_str(g"0x\0");
                                switch (c / 16 > 0)
                                {
                                    case (true) { this.put_hex_digit(c / 16); }
                                    default {};
                                };
                                this.put_hex_digit(c % 16);
                            };
                            };
                            j++;
                        };
                    };
                    };
                    i++;
                };
                ->;
            };

            // operator__<mangled>[__<mangled>]
            op_func_name(OpSym* l, OpSym* r) -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                this.sb.put_str(g"operator__\0");
                this.mangle_into(l);
                switch (r != (OpSym*)0)
                {
                    case (true) {
                    this.sb.put_str(g"__\0");
                    this.mangle_into(r);
                }
                    default {};
                };
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            kind_bit(int kind) -> int
            {
                int bit = 1;
                int k = kind;
                while (k > 0)
                {
                    bit = bit * 2;
                    k--;
                };
                -> bit;
            };

            // Registers (or re-points) an operator. kind: 0 binary, 1 variadic, 2 prefix, 3 postfix,
            // 4 ternary, 5 circumfix. Takes ownership of left and right.
            cop_register(int kind, OpSym* left, OpSym* right, byte* func) -> void
            {
                int i;
                COp* c;
                bool same;
                while (i < this.cops.len)
                {
                    c = (COp*)this.cops.items[i];
                    switch (c.kind == kind & this.opsym_same(c.left, left))
                    {
                        case (true) {
                        same = true;
                        switch (right != (OpSym*)0)
                        {
                            case (true) {
                            switch (c.right == (OpSym*)0)
                            {
                                case (true) { same = false; }
                                default { same = this.opsym_same(c.right, right); };
                            };
                        }
                            default {};
                        };
                        switch (same)
                        {
                            case (true) {
                            c.func = func;
                            this.opsym_free(left);
                            this.opsym_free(right);
                            ->;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                c = (COp*)fmalloc((u64)((sizeof(COp) + 7) / 8));
                c.kind = kind;
                c.left = left;
                c.right = right;
                c.func = func;
                pv_push(this.cops, (void*)c);
                this.cop_mask = this.cop_mask `| this.kind_bit(kind);
                ->;
            };

            // Longest left symbol of this kind matching at the cursor, or null
            cop_best(int kind) -> COp*
            {
                switch ((this.cop_mask `& this.kind_bit(kind)) == 0)
                {
                    case (true) { -> (COp*)0; }
                    default {};
                };
                COp* best = (COp*)0;
                COp* c;
                int i, bn;
                while (i < this.cops.len)
                {
                    c = (COp*)this.cops.items[i];
                    switch (c.kind == kind)
                    {
                        case (true) {
                        switch (c.left.n > bn)
                        {
                            case (true) {
                            switch (this.opsym_match(c.left))
                            {
                                case (true) {
                                best = c;
                                bn = c.left.n;
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> best;
            };

            // Longest right symbol among the operators sharing left's left symbol that matches at the cursor
            cop_right(COp* left) -> COp*
            {
                COp* best = (COp*)0;
                COp* c;
                int i, bn;
                while (i < this.cops.len)
                {
                    c = (COp*)this.cops.items[i];
                    switch (c.kind == left.kind & c.right != (OpSym*)0)
                    {
                        case (true) {
                        switch (this.opsym_same(c.left, left.left))
                        {
                            case (true) {
                            switch (c.right.n > bn)
                            {
                                case (true) {
                                switch (this.opsym_match(c.right))
                                {
                                    case (true) {
                                    best = c;
                                    bn = c.right.n;
                                }
                                    default {};
                                };
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> best;
            };

            // True when the cursor is at the right symbol of any ternary operator
            cop_right_here() -> bool
            {
                switch ((this.cop_mask `& this.kind_bit(4)) == 0)
                {
                    case (true) { -> false; }
                    default {};
                };
                COp* c;
                int i;
                while (i < this.cops.len)
                {
                    c = (COp*)this.cops.items[i];
                    switch (c.kind == 4)
                    {
                        case (true) {
                        switch (this.opsym_match(c.right))
                        {
                            case (true) { -> true; }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> false;
            };

            // True when the cursor is at a custom binary, variadic or ternary operator
            at_custom_op() -> bool
            {
                switch (this.cop_mask == 0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (this.cop_best(0) != (COp*)0)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (this.cop_best(1) != (COp*)0)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (this.cop_best(4) != (COp*)0)
                {
                    case (true) { -> true; }
                    default {};
                };
                -> this.cop_right_here();
            };

            // FUNCTION_CALL of func, positioned at line/col
            op_call(byte* func, int line, int col) -> Node*
            {
                Node* c = this.mk(NodeKind.FUNCTION_CALL, line, col);
                switch (this.failed)
                {
                    case (true) { -> c; }
                    default {};
                };
                c.text = func;
                -> c;
            };

            skip_tokens(int n) -> void
            {
                int i;
                while (i < n)
                {
                    this.advance();
                    i++;
                };
                ->;
            };

            // custom_op_expression -> multiplicative ( variadic chain | ternary | binary )*
            custom_op_expression() -> Node*
            {
                Node* expr = this.bin_level(9);
                switch (this.failed)
                {
                    case (true) { -> expr; }
                    default {};
                };
                switch (this.cop_mask == 0)
                {
                    case (true) { -> expr; }
                    default {};
                };
                COp* c;
                COp* rc;
                Node* call;
                Node* mid;
                Node* right;
                Node* cnt;
                int line, col, count;
                bool more;
                while (true)
                {
                    line = this.cur_line();
                    col = this.cur_col();
                    c = this.cop_best(1);
                    switch (c != (COp*)0)
                    {
                        case (true) {
                        call = this.op_call(c.func, line, col);
                        switch (this.failed)
                        {
                            case (true) { -> expr; }
                            default {};
                        };
                        cnt = this.lit(DataType.SINT, (i64)0, line, col);
                        switch (this.failed)
                        {
                            case (true) { node_free(call); -> expr; }
                            default {};
                        };
                        node_push(call, 0, cnt);
                        node_push(call, 0, expr);
                        count = 0;
                        more = true;
                        while (more)
                        {
                            switch (!this.opsym_match(c.left))
                            {
                                case (true) { break; }
                                default {};
                            };
                            this.skip_tokens(c.left.n);
                            count++;
                            switch (!this.starts_operand())
                            {
                                case (true) { break; }
                                default {};
                            };
                            right = this.bin_level(9);
                            switch (this.failed)
                            {
                                case (true) { node_free(call); -> (Node*)0; }
                                default {};
                            };
                            node_push(call, 0, right);
                        };
                        this.set_count_literal(cnt, count);
                        expr = call;
                        continue;
                    }
                        default {};
                    };
                    c = this.cop_best(4);
                    switch (c != (COp*)0)
                    {
                        case (true) {
                        this.skip_tokens(c.left.n);
                        mid = this.bin_level(9);
                        switch (this.failed)
                        {
                            case (true) { node_free(expr); -> mid; }
                            default {};
                        };
                        rc = this.cop_right(c);
                        switch (rc == (COp*)0)
                        {
                            case (true) {
                            node_free(expr);
                            node_free(mid);
                            this.error3(g"Expected right operator of ternary '\0", this.opsym_text(c.left), g"'\0");
                            -> (Node*)0;
                        }
                            default {};
                        };
                        this.skip_tokens(rc.right.n);
                        right = this.bin_level(9);
                        switch (this.failed)
                        {
                            case (true) { node_free(expr); node_free(mid); -> right; }
                            default {};
                        };
                        call = this.op_call(rc.func, line, col);
                        switch (this.failed)
                        {
                            case (true) { node_free(expr); node_free(mid); node_free(right); -> call; }
                            default {};
                        };
                        node_push(call, 0, expr);
                        node_push(call, 0, mid);
                        node_push(call, 0, right);
                        expr = call;
                        continue;
                    }
                        default {};
                    };
                    c = this.cop_best(0);
                    switch (c == (COp*)0)
                    {
                        case (true) { break; }
                        default {};
                    };
                    this.skip_tokens(c.left.n);
                    right = this.bin_level(9);
                    switch (this.failed)
                    {
                        case (true) { node_free(expr); -> right; }
                        default {};
                    };
                    call = this.op_call(c.func, line, col);
                    switch (this.failed)
                    {
                        case (true) { node_free(expr); node_free(right); -> call; }
                        default {};
                    };
                    node_push(call, 0, expr);
                    node_push(call, 0, right);
                    expr = call;
                };
                -> expr;
            };

            set_count_literal(Node* lit_node, int count) -> void
            {
                lit_node.ival = (i64)count;
                lit_node.op = DataType.SINT;
                ->;
            };

            // Prefix and circumfix custom operators at the start of a unary expression, or null
            custom_unary() -> Node*
            {
                switch (this.cop_mask == 0)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                int line = this.cur_line();
                int col = this.cur_col();
                COp* c = this.cop_best(2);
                Node* call;
                Node* operand;
                COp* rc;
                switch (c != (COp*)0)
                {
                    case (true) {
                    this.skip_tokens(c.left.n);
                    operand = this.unary_expression();
                    switch (this.failed)
                    {
                        case (true) { -> operand; }
                        default {};
                    };
                    call = this.op_call(c.func, line, col);
                    switch (this.failed)
                    {
                        case (true) { node_free(operand); -> call; }
                        default {};
                    };
                    node_push(call, 0, operand);
                    -> call;
                }
                    default {};
                };
                c = this.cop_best(5);
                switch (c != (COp*)0)
                {
                    case (true) {
                    this.skip_tokens(c.left.n);
                    operand = this.unary_expression();
                    switch (this.failed)
                    {
                        case (true) { -> operand; }
                        default {};
                    };
                    rc = this.cop_right(c);
                    switch (rc == (COp*)0)
                    {
                        case (true) {
                        node_free(operand);
                        this.error3(g"Expected closing operator of circumfix '\0", this.opsym_text(c.left), g"'\0");
                        -> (Node*)0;
                    }
                        default {};
                    };
                    this.skip_tokens(rc.right.n);
                    call = this.op_call(rc.func, line, col);
                    switch (this.failed)
                    {
                        case (true) { node_free(operand); -> call; }
                        default {};
                    };
                    node_push(call, 0, operand);
                    -> call;
                }
                    default {};
                };
                -> (Node*)0;
            };

            // True when s is the text of a built-in operator
            is_builtin_op(byte* s) -> bool
            {
                int o = 0;
                while (o <= Operator.ADDRESS_CAST)
                {
                    switch (cstr_eq(operator_text(o), s))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    o++;
                };
                -> false;
            };

            // Parameter types that make an overload of a built-in operator legal
            has_non_builtin_param(Node* f) -> bool
            {
                int i;
                TypeSpec* t;
                while (i < this.param_count(f))
                {
                    t = f.l0.items[i].ts;
                    switch (t != (TypeSpec*)0)
                    {
                        case (true) {
                        switch (t.custom_typename != (byte*)0)
                        {
                            case (true) { -> true; }
                            default {};
                        };
                        switch (t.base_type == DataType.STRUCT | t.base_type == DataType.OBJECT | t.base_type == DataType.DATA)
                        {
                            case (true) { -> true; }
                            default {};
                        };
                        switch (t.pointer_depth > 0)
                        {
                            case (true) { -> true; }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> false;
            };

            define_op_symbol(OpSym* s) -> void
            {
                switch (this.st != (FXC_SYMTABLE*)0)
                {
                    case (true) { st_define(this.st, this.opsym_text(s), SymbolKind.OPERATOR, (TypeSpec*)0, (Node*)0); }
                    default {};
                };
                ->;
            };

            // '# binding {:this}' (postfix, returns 2) or '# binding {this:}' (prefix, returns 1); 0 when absent
            unary_binding(Node* f, byte* what) -> int
            {
                switch (!(this.expect(TokenType.TAG) & this.type_at(1) == TokenType.IDENTIFIER))
                {
                    case (true) { -> 0; }
                    default {};
                };
                switch (!cstr_eq(this.val_at(1), g"binding\0"))
                {
                    case (true) { -> 0; }
                    default {};
                };
                switch (this.param_count(f) != 1)
                {
                    case (true) {
                    this.error3(g"# binding on \0", what, g" is only valid for unary operators (exactly one parameter)\0");
                    -> 0;
                }
                    default {};
                };
                this.advance();
                this.advance();
                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { -> 0; }
                    default {};
                };
                int r = 0;
                switch (this.expect(TokenType.COLON))
                {
                    case (true) {
                    this.advance();
                    this.consume(TokenType.THIS);
                    r = 2;
                }
                    default {
                        switch (this.expect(TokenType.THIS))
                        {
                            case (true) {
                    this.advance();
                    this.consume(TokenType.COLON);
                    r = 1;
                }
                            default {
                    this.error(g"Unary # binding must be {:this} for postfix or {this:} for prefix\0");
                    -> 0;
                };
                        };
                    };
                };
                this.consume(TokenType.RIGHT_BRACE);
                -> r;
            };

            // Registers the operator named by the symbols after the definition parsed
            register_operator(Node* f, OpSym* l, OpSym* r, int bind, bool variadic, bool is_template) -> void
            {
                int np = this.param_count(f);
                switch (bind == 1)
                {
                    case (true) { this.cop_register(2, l, (OpSym*)0, f.text); this.define_op_symbol(l); ->; }
                    default {};
                };
                switch (bind == 2)
                {
                    case (true) { this.cop_register(3, l, (OpSym*)0, f.text); this.define_op_symbol(l); ->; }
                    default {};
                };
                switch (r != (OpSym*)0)
                {
                    case (true) {
                    switch (np != 1 & np != 3)
                    {
                        case (true) {
                        this.error(g"Two-bracket 'as operator' requires either 1 parameter (circumfix) or 3 parameters (ternary)\0");
                        ->;
                    }
                        default {};
                    };
                    switch (np)
                    {
                        case (1) { this.cop_register(5, l, r, f.text); }
                        default { this.cop_register(4, l, r, f.text); };
                    };
                    this.define_op_symbol(r);
                    this.define_op_symbol(l);
                    ->;
                }
                    default {};
                };
                switch (variadic)
                {
                    case (true) {
                    this.cop_register(1, l, (OpSym*)0, f.text);
                    this.define_op_symbol(l);
                    ->;
                }
                    default {};
                };
                switch (this.is_builtin_op(this.opsym_text(l)))
                {
                    case (true) {
                    switch (!is_template & !this.has_non_builtin_param(f))
                    {
                        case (true) {
                        this.error3(g"Overloading built-in operator '\0", this.opsym_text(l), g"' requires at least one parameter to be a non-builtin type\0");
                    }
                        default {};
                    };
                    this.define_op_symbol(l);
                    this.opsym_free(l);
                    ->;
                }
                    default {};
                };
                this.cop_register(0, l, (OpSym*)0, f.text);
                this.define_op_symbol(l);
                ->;
            };

            // operator_def -> 'operator' '(' parameter_list ')' '[' symbol ']' ('[' symbol ']')? '->' type_spec
            //                 (':' contracts)? (';' | '->' expression ';' | block (':' contracts)? ('# binding {..}')? ';')
            operator_def() -> Node*
            {
                NameMap* prev_act = this.active_tp;
                TemplateEntry* prev_cur = this.tmpl_cur;
                TemplateEntry* te;
                Node* f;
                this.tmpl_cur = (TemplateEntry*)0;
                f = this.operator_def_inner();
                te = this.tmpl_cur;
                this.tmpl_cur = prev_cur;
                switch (this.active_tp != prev_act)
                {
                    case (true) {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                }
                    default {};
                };
                switch (te != (TemplateEntry*)0)
                {
                    case (true) { te_free(te); }
                    default {};
                };
                -> f;
            };

            // Registers the template operator and gives up ownership of f (the call returns null)
            op_template_done(Node* f, TemplateEntry* te, byte* key) -> Node*
            {
                this.tmpl_cur = (TemplateEntry*)0;
                this.register_template(key, 3, te, f);
                -> (Node*)0;
            };

            operator_def_inner() -> Node*
            {
                Node* f = this.mk(NodeKind.FUNCTION_DEF, this.cur_line(), this.cur_col());
                TemplateEntry* te = (TemplateEntry*)0;
                byte* opkey = (byte*)0;
                switch (this.failed)
                {
                    case (true) { -> f; }
                    default {};
                };
                this.advance();
                switch (this.expect(TokenType.LESS_THAN) & this.is_template_list())
                {
                    case (true) {
                    te = te_new();
                    this.advance();
                    pv_push(te.params, (void*)this.own(ts_dup(this.ident())));
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        pv_push(te.params, (void*)this.own(ts_dup(this.ident())));
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.GREATER_THAN); }
                        default {};
                    };
                    switch (this.failed)
                    {
                        case (true) {
                        te_free(te);
                        -> this.done(f);
                    }
                        default {};
                    };
                    this.tmpl_cur = te;
                }
                    default {};
                };
                switch (!this.consume(TokenType.LEFT_PAREN))
                {
                    case (true) { -> this.done(f); }
                    default {};
                };
                switch (te != (TemplateEntry*)0)
                {
                    case (true) { this.tp_activate(te); }
                    default {};
                };
                this.parameter_list(f);
                switch (this.failed)
                {
                    case (true) { -> this.done(f); }
                    default {};
                };
                switch (!this.consume(TokenType.RIGHT_PAREN))
                {
                    case (true) { -> this.done(f); }
                    default {};
                };

                OpSym* l = this.op_bracket();
                OpSym* r = (OpSym*)0;
                switch (!this.failed & this.expect(TokenType.LEFT_BRACKET))
                {
                    case (true) { r = this.op_bracket(); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.op_abort(f, l, r); }
                    default {};
                };
                switch (te != (TemplateEntry*)0)
                {
                    case (true) { opkey = this.opsym_text(l); }
                    default {};
                };

                switch (r != (OpSym*)0)
                {
                    case (true) {
                    switch (this.param_count(f) != 1 & this.param_count(f) != 3)
                    {
                        case (true) {
                        this.error(g"Two-bracket operator requires either 1 parameter (circumfix) or 3 parameters (ternary)\0");
                        -> this.op_abort(f, l, r);
                    }
                        default {};
                    };
                }
                    default {};
                };
                f.text = this.op_func_name(l, r);

                switch (!this.consume(TokenType.RETURN_ARROW))
                {
                    case (true) { -> this.op_abort(f, l, r); }
                    default {};
                };
                f.ts = this.type_spec();
                switch (this.failed)
                {
                    case (true) { -> this.op_abort(f, l, r); }
                    default {};
                };

                Node* pre;
                switch (this.expect(TokenType.COLON))
                {
                    case (true) {
                    this.advance();
                    pre = this.mk(NodeKind.NODE_LIST, f.line, f.col);
                    switch (this.failed)
                    {
                        case (true) { -> this.op_abort(f, l, r); }
                        default {};
                    };
                    this.contract_refs(f, pre, false);
                    switch (this.failed)
                    {
                        case (true) { node_free(pre); -> this.op_abort(f, l, r); }
                        default {};
                    };
                }
                    default {};
                };

                // Variadic operators get a hidden leading __op_count parameter
                bool variadic = false;
                int i;
                Node* p;
                while (i < this.param_count(f))
                {
                    switch (f.l0.items[i].ival == 1)
                    {
                        case (true) { variadic = true; }
                        default {};
                    };
                    i++;
                };
                this.strip_variadic(f);
                Node* cp;
                switch (variadic & r == (OpSym*)0)
                {
                    case (true) {
                    cp = this.mk(NodeKind.PARAMETER, f.line, f.col);
                    switch (this.failed)
                    {
                        case (true) { node_free(pre); -> this.op_abort(f, l, r); }
                        default {};
                    };
                    cp.ts = typespec_new();
                    cp.ts.base_type = DataType.SINT;
                    cp.text = g"__op_count\0";
                    this.push_front(f, cp);
                }
                    default {};
                };

                OpSym* prev_vop = this.vop_sym;
                Node* ret;
                Node* b;
                Node* post;
                int bind;
                switch (this.expect(TokenType.SEMICOLON))
                {
                    case (true) {
                    this.advance();
                    this.mark_proto(f);
                }
                    default {
                        switch (this.expect(TokenType.RETURN_ARROW))
                        {
                            case (true) {
                    i = 0;
                    while (i < this.param_count(f))
                    {
                        switch (f.l0.items[i].text == (byte*)0)
                        {
                            case (true) {
                            this.error(g"Operator definition requires parameter names, but a parameter has no name\0");
                            node_free(pre);
                            -> this.op_abort(f, l, r);
                        }
                            default {};
                        };
                        i++;
                    };
                    switch (this.st != (FXC_SYMTABLE*)0)
                    {
                        case (true) {
                        st_enter_scope(this.st);
                        i = 0;
                        while (i < this.param_count(f))
                        {
                            p = f.l0.items[i];
                            this.define_var(p.text, p.ts);
                            i++;
                        };
                    }
                        default {};
                    };
                    switch (variadic & r == (OpSym*)0)
                    {
                        case (true) { this.vop_sym = l; }
                        default {};
                    };
                    this.advance();
                    b = this.mk(NodeKind.BLOCK, this.cur_line(), this.cur_col());
                    ret = this.mk(NodeKind.RETURN_STATEMENT, this.cur_line(), this.cur_col());
                    switch (this.failed)
                    {
                        case (true) { node_free(b); node_free(ret); node_free(pre); -> this.op_abort(f, l, r); }
                        default {};
                    };
                    f.a = b;
                    node_push(b, 0, ret);
                    ret.a = this.expression();
                    this.vop_sym = prev_vop;
                    switch (this.st != (FXC_SYMTABLE*)0)
                    {
                        case (true) { st_exit_scope(this.st); }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                }
                            default {
                    switch (variadic & r == (OpSym*)0)
                    {
                        case (true) { this.vop_sym = l; }
                        default {};
                    };
                    switch (this.st != (FXC_SYMTABLE*)0)
                    {
                        case (true) { st_enter_scope(this.st); }
                        default {};
                    };
                    f.a = this.block();
                    switch (this.st != (FXC_SYMTABLE*)0)
                    {
                        case (true) { st_exit_scope(this.st); }
                        default {};
                    };
                    this.vop_sym = prev_vop;
                    switch (!this.failed)
                    {
                        case (true) {
                        this.prepend_contracts(f, pre);
                        post = (Node*)0;
                        switch (this.expect(TokenType.COLON))
                        {
                            case (true) {
                            this.advance();
                            post = this.mk(NodeKind.NODE_LIST, f.line, f.col);
                            switch (this.failed)
                            {
                                case (true) { -> this.op_abort(f, l, r); }
                                default {};
                            };
                            this.contract_refs(f, post, true);
                            switch (!this.failed)
                            {
                                case (true) { this.apply_post_contracts(f, post); }
                                default {};
                            };
                        }
                            default {};
                        };
                        switch (!this.failed)
                        {
                            case (true) { this.validate_bindings(this.fn_label(f), pre, post); }
                            default {};
                        };
                        node_free(post);
                        node_free(pre);
                        pre = (Node*)0;
                    }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) {
                        bind = this.unary_binding(f, g"an operator definition\0");
                        switch (!this.failed)
                        {
                            case (true) { this.consume(TokenType.SEMICOLON); }
                            default {};
                        };
                        switch (!this.failed)
                        {
                            case (true) {
                            this.register_operator(f, l, r, bind, variadic, te != (TemplateEntry*)0);
                            switch (te != (TemplateEntry*)0)
                            {
                                case (true) { -> this.op_template_done(f, te, opkey); }
                                default {};
                            };
                            -> f;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    node_free(pre);
                    -> this.op_abort(f, l, r);
                };
                        };
                    };
                };
                node_free(pre);
                switch (this.failed)
                {
                    case (true) { -> this.op_abort(f, l, r); }
                    default {};
                };
                switch (variadic)
                {
                    case (true) { f.flags = f.flags `| NF_VARIADIC; }
                    default {};
                };
                this.register_operator(f, l, r, 0, variadic, te != (TemplateEntry*)0);
                switch (te != (TemplateEntry*)0)
                {
                    case (true) { -> this.op_template_done(f, te, opkey); }
                    default {};
                };
                -> this.done(f);
            };

            op_abort(Node* f, OpSym* l, OpSym* r) -> Node*
            {
                this.opsym_free(l);
                this.opsym_free(r);
                -> this.done(f);
            };

            // Inserts p at the front of f's parameter list
            push_front(Node* f, Node* p) -> void
            {
                node_push(f, 0, p);
                int i = f.l0.len - 1;
                while (i > 0)
                {
                    f.l0.items[i] = f.l0.items[i - 1];
                    i--;
                };
                f.l0.items[0] = p;
                ->;
            };

            // ===== CONTRACTS =====

            // Latest CONTRACT_DEF with this name, or null
            contract_find(byte* name) -> Node*
            {
                int i = this.contracts.len - 1;
                Node* c;
                while (i >= 0)
                {
                    c = (Node*)this.contracts.items[i];
                    switch (cstr_eq(c.text, name))
                    {
                        case (true) { -> c; }
                        default {};
                    };
                    i--;
                };
                -> (Node*)0;
            };

            contract_param(Node* c) -> void
            {
                Node* p = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                node_push(c, 0, p);
                p.text = this.ident();
                ->;
            };

            // ('(' IDENTIFIER (',' IDENTIFIER)* ')')?
            contract_params(Node* c) -> void
            {
                switch (!this.expect(TokenType.LEFT_PAREN))
                {
                    case (true) { ->; }
                    default {};
                };
                this.advance();
                switch (!this.expect(TokenType.RIGHT_PAREN))
                {
                    case (true) {
                    this.contract_param(c);
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        this.contract_param(c);
                    };
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_PAREN); }
                    default {};
                };
                ->;
            };

            // contract_def -> 'contract' IDENTIFIER ('(' params ')')? (list of names ';' | block ('# binding {..}')? ';')
            // A name list is a forward declaration. Binding specs are skipped and reported.
            contract_def() -> Node*
            {
                Node* c = this.mk(NodeKind.CONTRACT_DEF, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> c; }
                    default {};
                };
                this.advance();
                c.text = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.done(c); }
                    default {};
                };
                this.contract_params(c);
                switch (this.failed)
                {
                    case (true) { -> this.done(c); }
                    default {};
                };

                Node* x;
                switch (this.expect2(TokenType.SEMICOLON, TokenType.COMMA))
                {
                    case (true) {
                    c.a = this.mk(NodeKind.BLOCK, c.line, c.col);
                    switch (this.failed)
                    {
                        case (true) { -> this.done(c); }
                        default {};
                    };
                    switch (this.contract_find(c.text) == (Node*)0)
                    {
                        case (true) { pv_push(this.contracts, (void*)c); }
                        default {};
                    };
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        x = this.mk(NodeKind.CONTRACT_DEF, this.cur_line(), this.cur_col());
                        switch (this.failed)
                        {
                            case (true) { -> this.done(c); }
                            default {};
                        };
                        nv_push(this.pending, x);
                        x.text = this.ident();
                        switch (this.failed)
                        {
                            case (true) { -> this.done(c); }
                            default {};
                        };
                        this.contract_params(x);
                        switch (this.failed)
                        {
                            case (true) { -> this.done(c); }
                            default {};
                        };
                        x.a = this.mk(NodeKind.BLOCK, x.line, x.col);
                        switch (this.failed)
                        {
                            case (true) { -> this.done(c); }
                            default {};
                        };
                        switch (this.contract_find(x.text) == (Node*)0)
                        {
                            case (true) { pv_push(this.contracts, (void*)x); }
                            default {};
                        };
                    };
                    this.consume(TokenType.SEMICOLON);
                    -> this.done(c);
                }
                    default {};
                };

                c.a = this.block();
                switch (this.failed)
                {
                    case (true) { -> this.done(c); }
                    default {};
                };
                switch (this.expect(TokenType.TAG) & this.type_at(1) == TokenType.IDENTIFIER)
                {
                    case (true) {
                    switch (cstr_eq(this.val_at(1), g"binding\0"))
                    {
                        case (true) {
                        this.advance();
                        this.advance();
                        switch (this.consume(TokenType.LEFT_BRACE))
                        {
                            case (true) {
                            c.b = this.binding_spec();
                            switch (!this.failed)
                            {
                                case (true) { this.consume(TokenType.RIGHT_BRACE); }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(c); }
                    default {};
                };
                pv_push(this.contracts, (void*)c);
                -> c;
            };

            num_text(int v) -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                this.sb.put_int(v);
                -> this.own_n(this.sb.mem, this.sb.len);
            };

            // Replaces IDENTIFIER names found in from by the matching entry of to, everywhere below n
            subst_walk(Node* n, PtrVec* from_names, PtrVec* to_names) -> void
            {
                switch (n == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                int i, s, cnt;
                switch (n.kind == NodeKind.IDENTIFIER & n.text != (byte*)0)
                {
                    case (true) {
                    while (i < from_names.len)
                    {
                        switch (cstr_eq((byte*)from_names.items[i], n.text))
                        {
                            case (true) {
                            n.text = (byte*)to_names.items[i];
                            break;
                        }
                            default {};
                        };
                        i++;
                    };
                }
                    default {};
                };
                this.subst_walk(n.a, from_names, to_names);
                this.subst_walk(n.b, from_names, to_names);
                this.subst_walk(n.c, from_names, to_names);
                this.subst_walk(n.d, from_names, to_names);
                this.subst_walk(n.e, from_names, to_names);
                while (s < 6)
                {
                    cnt = node_count(n, s);
                    i = 0;
                    while (i < cnt)
                    {
                        this.subst_walk(node_child(n, s, i), from_names, to_names);
                        i++;
                    };
                    s++;
                };
                ->;
            };

            // contract_ref -> IDENTIFIER ('(' IDENTIFIER (',' IDENTIFIER)* ')')?
            // NODE_LIST: text = name, ival = 1 when an argument list was written, l0 = IDENTIFIER arguments
            parse_contract_ref() -> Node*
            {
                Node* ref = this.mk(NodeKind.NODE_LIST, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> ref; }
                    default {};
                };
                ref.text = this.ident();
                switch (this.failed)
                {
                    case (true) { -> this.done(ref); }
                    default {};
                };
                switch (this.expect(TokenType.LEFT_PAREN))
                {
                    case (true) {
                    this.advance();
                    ref.ival = 1;
                    switch (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        case (true) {
                        this.contract_param(ref);
                        while (!this.failed & this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            this.contract_param(ref);
                        };
                    }
                        default {};
                    };
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.RIGHT_PAREN); }
                        default {};
                    };
                }
                    default {};
                };
                -> this.done(ref);
            };

            // Appends substituted copies of the contract's statements to out.l0
            resolve_contract(Node* f, Node* ref, Node* out) -> void
            {
                Node* c = this.contract_find(ref.text);
                int cp = node_count(c, 0);
                int i, rn, argc;
                PtrVec* real = pv_new();
                PtrVec* from_names = pv_new();
                PtrVec* to_names = pv_new();
                Node* pn;
                while (i < this.param_count(f))
                {
                    pn = f.l0.items[i];
                    switch (pn.ival != 1)
                    {
                        case (true) { pv_push(real, (void*)pn.text); }
                        default {};
                    };
                    i++;
                };
                rn = real.len;
                i = 0;
                switch (cp > 0)
                {
                    case (true) {
                    switch (ref.ival == 1)
                    {
                        case (true) {
                        argc = node_count(ref, 0);
                        switch (argc != cp)
                        {
                            case (true) {
                            this.error(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(g"Contract '\0", ref.text), g"' expects \0"), this.num_text(cp)), g" parameter(s) but \0"), this.num_text(argc)), g" argument(s) given at attachment site\0"));
                        }
                            default {
                                switch (rn < argc)
                                {
                                    case (true) {
                            this.error(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(g"Contract '\0", ref.text), g"' attachment maps \0"), this.num_text(argc)), g" parameter(s) but function only has \0"), this.num_text(rn)), g"\0"));
                        }
                                    default {
                            while (i < argc)
                            {
                                switch (real.items[i] != (void*)0)
                                {
                                    case (true) {
                                    pv_push(from_names, (void*)ref.l0.items[i].text);
                                    pv_push(to_names, real.items[i]);
                                }
                                    default {};
                                };
                                i++;
                            };
                        };
                                };
                            };
                        };
                    }
                        default {
                            switch (cp != rn)
                            {
                                case (true) {
                        this.error(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(g"Contract '\0", ref.text), g"' expects \0"), this.num_text(cp)), g" parameter(s) but function has \0"), this.num_text(rn)));
                    }
                                default {
                        while (i < cp)
                        {
                            switch (real.items[i] != (void*)0)
                            {
                                case (true) {
                                pv_push(from_names, (void*)c.l0.items[i].text);
                                pv_push(to_names, real.items[i]);
                            }
                                default {};
                            };
                            i++;
                        };
                    };
                            };
                        };
                    };
                }
                    default {};
                };
                Node* s;
                Node* body = c.a;
                switch (!this.failed & body != (Node*)0)
                {
                    case (true) {
                    i = 0;
                    while (i < node_count(body, 0))
                    {
                        s = node_clone(node_child(body, 0, i));
                        this.subst_walk(s, from_names, to_names);
                        node_push(out, 0, s);
                        i++;
                    };
                }
                    default {};
                };
                pv_free(real);
                pv_free(from_names);
                pv_free(to_names);
                ->;
            };

            // ':' contract_ref (',' contract_ref)*  statements go to out.l0
            contract_refs(Node* f, Node* out, bool is_post) -> void
            {
                Node* ref;
                Node* nm;
                bool more = true;
                while (more & !this.failed)
                {
                    ref = this.parse_contract_ref();
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (this.contract_find(ref.text) == (Node*)0)
                    {
                        case (true) {
                        switch (is_post)
                        {
                            case (true) { this.error3(g"Undefined post-contract '\0", ref.text, g"'\0"); }
                            default { this.error3(g"Undefined contract '\0", ref.text, g"'\0"); };
                        };
                        node_free(ref);
                        ->;
                    }
                        default {};
                    };
                    this.resolve_contract(f, ref, out);
                    nm = this.mk(NodeKind.IDENTIFIER, ref.line, ref.col);
                    switch (!this.failed)
                    {
                        case (true) {
                        nm.text = ref.text;
                        nm.ival = -1;
                        switch (ref.ival == 1)
                        {
                            case (true) { nm.ival = (i64)node_count(ref, 0); }
                            default {};
                        };
                        node_push(out, 1, nm);
                    }
                        default {};
                    };
                    node_free(ref);
                    more = false;
                    switch (!this.failed & this.expect(TokenType.COMMA))
                    {
                        case (true) {
                        this.advance();
                        more = true;
                    }
                        default {};
                    };
                };
                ->;
            };

            // Moves pre.l0 in front of the statements of f's body; the caller frees pre
            prepend_contracts(Node* f, Node* pre) -> void
            {
                switch (pre == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (node_count(pre, 0) > 0 & f.a != (Node*)0)
                {
                    case (true) {
                    NodeVec* merged = nv_new();
                    int i;
                    while (i < pre.l0.len)
                    {
                        nv_push(merged, pre.l0.items[i]);
                        i++;
                    };
                    i = 0;
                    while (i < node_count(f.a, 0))
                    {
                        nv_push(merged, f.a.l0.items[i]);
                        i++;
                    };
                    pre.l0.len = 0;
                    switch (f.a.l0 != (NodeVec*)0)
                    {
                        case (true) {
                        f.a.l0.len = 0;
                        nv_free(f.a.l0);
                    }
                        default {};
                    };
                    f.a.l0 = merged;
                }
                    default {};
                };
                ->;
            };

            // Copies of every post-contract statement into out
            push_post_copies(NodeVec* out, Node* post) -> void
            {
                int i;
                while (i < node_count(post, 0))
                {
                    nv_push(out, node_clone(post.l0.items[i]));
                    i++;
                };
                ->;
            };

            // Rewrites the statements of blk so post-contract code runs before each return
            rewrite_returns(Node* blk, TypeSpec* rt, Node* post, bool void_mode) -> void
            {
                switch (blk == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                NodeVec* old = blk.l0;
                NodeVec* out = nv_new();
                int i, k;
                Node* s;
                Node* decl;
                Node* ret;
                Node* id;
                while (old != (NodeVec*)0 & i < old.len)
                {
                    s = old.items[i];
                    i++;
                    switch (s.kind == NodeKind.RETURN_STATEMENT)
                    {
                        case (true) {
                        switch (!void_mode & s.a != (Node*)0)
                        {
                            case (true) {
                            decl = this.mk(NodeKind.VARIABLE_DECLARATION, s.line, s.col);
                            ret = this.mk(NodeKind.RETURN_STATEMENT, s.line, s.col);
                            id = this.mk(NodeKind.IDENTIFIER, s.line, s.col);
                            switch (this.failed)
                            {
                                case (true) { nv_push(out, s); continue; }
                                default {};
                            };
                            decl.text = g"r\0";
                            decl.ts = typespec_copy(rt);
                            decl.a = s.a;
                            s.a = (Node*)0;
                            node_free(s);
                            id.text = g"r\0";
                            ret.a = id;
                            nv_push(out, decl);
                            this.push_post_copies(out, post);
                            nv_push(out, ret);
                            continue;
                        }
                            default {};
                        };
                        switch (void_mode & s.a == (Node*)0)
                        {
                            case (true) {
                            this.push_post_copies(out, post);
                            nv_push(out, s);
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (s.kind == NodeKind.BLOCK)
                    {
                        case (true) { this.rewrite_returns(s, rt, post, void_mode); }
                        default {
                            switch (s.kind == NodeKind.IF_STATEMENT)
                            {
                                case (true) {
                        this.rewrite_returns(s.b, rt, post, void_mode);
                        this.rewrite_returns(s.c, rt, post, void_mode);
                        k = 0;
                        while (k < node_count(s, 1))
                        {
                            this.rewrite_returns(s.l1.items[k], rt, post, void_mode);
                            k++;
                        };
                    }
                                default {
                                    switch (s.kind == NodeKind.WHILE_LOOP | s.kind == NodeKind.DO_LOOP | s.kind == NodeKind.DO_WHILE_LOOP | s.kind == NodeKind.FOR_IN_LOOP)
                                    {
                                        case (true) {
                        this.rewrite_returns(s.b, rt, post, void_mode);
                    }
                                        default {
                                            switch (s.kind == NodeKind.FOR_LOOP)
                                            {
                                                case (true) { this.rewrite_returns(s.d, rt, post, void_mode); }
                                                default {
                                                    switch (s.kind == NodeKind.SWITCH_STATEMENT)
                                                    {
                                                        case (true) {
                        k = 0;
                        while (k < node_count(s, 0))
                        {
                            this.rewrite_returns(s.l0.items[k].b, rt, post, void_mode);
                            k++;
                        };
                    }
                                                        default {
                                                            switch (s.kind == NodeKind.TRY_BLOCK)
                                                            {
                                                                case (true) {
                        this.rewrite_returns(s.a, rt, post, void_mode);
                        k = 0;
                        while (k < node_count(s, 0))
                        {
                            this.rewrite_returns(s.l0.items[k].a, rt, post, void_mode);
                            k++;
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
                            };
                        };
                    };
                    nv_push(out, s);
                };
                switch (old != (NodeVec*)0)
                {
                    case (true) {
                    old.len = 0;
                    nv_free(old);
                }
                    default {};
                };
                blk.l0 = out;
                ->;
            };

            // Every return of f's body is rewritten as: r = value; post statements; return r;
            // (void functions run the post statements before each bare return and at the end)
            apply_post_contracts(Node* f, Node* post) -> void
            {
                switch (f.a == (Node*)0 | node_count(post, 0) == 0)
                {
                    case (true) { ->; }
                    default {};
                };
                bool void_mode = f.ts != (TypeSpec*)0 & f.ts.base_type == DataType.VOID;
                this.rewrite_returns(f.a, f.ts, post, void_mode);
                switch (void_mode)
                {
                    case (true) {
                    switch (f.a.l0 == (NodeVec*)0)
                    {
                        case (true) { f.a.l0 = nv_new(); }
                        default {};
                    };
                    this.push_post_copies(f.a.l0, post);
                }
                    default {};
                };
                ->;
            };

            // ===== COMPTIME =====

            // comptime_block -> 'comptime' IDENTIFIER? '{' statement* '}' ';'
            comptime_block() -> Node*
            {
                Node* n = this.mk(NodeKind.COMPTIME_BLOCK, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                this.advance();
                switch (this.expect(TokenType.IDENTIFIER))
                {
                    case (true) {
                    n.text = this.cur_value();
                    this.advance();
                }
                    default {};
                };
                switch (!this.consume(TokenType.LEFT_BRACE))
                {
                    case (true) { -> this.done(n); }
                    default {};
                };
                this.in_comptime++;
                this.statements_until_brace(n);
                this.in_comptime--;
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.RIGHT_BRACE); }
                    default {};
                };
                switch (!this.failed)
                {
                    case (true) { this.consume(TokenType.SEMICOLON); }
                    default {};
                };
                -> this.done(n);
            };

            // ===== STRING INTERPOLATION =====

            // Parses text as an expression with a lexer of its own. The lexer outlives the tree
            // because nodes borrow token text from it, so it is kept in sublex and freed on exit.
            sub_expr(byte* text, int n) -> Node*
            {
                byte* src = this.own_n(text, n);
                Lexer* sl = (Lexer*)fmalloc((u64)((sizeof(Lexer) + 7) / 8));
                switch (sl == (Lexer*)0)
                {
                    case (true) {
                    this.fail_alloc();
                    -> (Node*)0;
                }
                    default {};
                };
                sl.__init(src, n);
                pv_push(this.sublex, (void*)sl);
                switch (!sl.tokenize())
                {
                    case (true) {
                    this.error(g"Invalid expression in string interpolation\0");
                    -> (Node*)0;
                }
                    default {};
                };
                Lexer* s_lx = this.lx;
                Token* s_toks = this.toks;
                int s_count = this.count;
                int s_pos = this.pos;
                this.lx = sl;
                this.toks = sl.tokens;
                this.count = sl.count;
                this.pos = 0;
                Node* e = this.expression();
                this.lx = s_lx;
                this.toks = s_toks;
                this.count = s_count;
                this.pos = s_pos;
                -> e;
            };

            // Pushes the text gathered in sb as a STRING_LITERAL part of holder and clears sb
            flush_text(Node* holder, int line, int col) -> void
            {
                switch (this.sb.len == 0)
                {
                    case (true) { ->; }
                    default {};
                };
                Node* t = this.mk(NodeKind.STRING_LITERAL, line, col);
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                t.text = this.own_n(this.sb.mem, this.sb.len);
                t.op = -1;
                node_push(holder, 0, t);
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                ->;
            };

            is_space(int c) -> bool -> c == 32 | c == 9 | c == 10 | c == 13;

            // f"..." token: parts are text and {expression}; {{ and }} are literal braces
            f_string_node() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.F_STRING_LITERAL, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                byte* v = this.cur_value();
                int end = this.cur_value_len() - 1;
                int i = 2;
                int j;
                Node* e;
                this.advance();
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                while (i < end)
                {
                    switch (v[i] == '{' & i + 1 < end & v[i + 1] == '{')
                    {
                        case (true) {
                        this.sb.put('{');
                        i += 2;
                    }
                        default {
                            switch (v[i] == '}' & i + 1 < end & v[i + 1] == '}')
                            {
                                case (true) {
                        this.sb.put('}');
                        i += 2;
                    }
                                default {
                                    switch (v[i] == '{')
                                    {
                                        case (true) {
                        j = i + 1;
                        while (j < end & v[j] != '}') { j++; };
                        switch (j >= end)
                        {
                            case (true) {
                            this.error(g"Unclosed expression in f-string\0");
                            -> this.done(n);
                        }
                            default {};
                        };
                        this.flush_text(n, line, col);
                        e = this.sub_expr(v + i + 1, j - i - 1);
                        switch (this.failed)
                        {
                            case (true) { -> this.done(n); }
                            default {};
                        };
                        node_push(n, 0, e);
                        i = j + 1;
                    }
                                        default {
                        this.sb.put((int)v[i]);
                        i++;
                    };
                                    };
                                };
                            };
                        };
                    };
                };
                this.flush_text(n, line, col);
                -> this.done(n);
            };

            // i"template":{expr; expr} token: each {} in the template takes the next expression
            i_string_node() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.F_STRING_LITERAL, line, col);
                switch (this.failed)
                {
                    case (true) { -> n; }
                    default {};
                };
                byte* v = this.cur_value();
                int len = this.cur_value_len();
                this.advance();
                int i = 2;
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                bool closed = false;
                while (i < len & !closed)
                {
                    switch (v[i] == '\\' & i + 1 < len)
                    {
                        case (true) {
                        this.sb.put((int)v[i]);
                        this.sb.put((int)v[i + 1]);
                        i += 2;
                    }
                        default {
                            switch (v[i] == '"')
                            {
                                case (true) {
                        i++;
                        closed = true;
                    }
                                default {
                        this.sb.put((int)v[i]);
                        i++;
                    };
                            };
                        };
                    };
                };
                byte* tpl = this.own_n(this.sb.mem, this.sb.len);
                int tlen = this.sb.len;
                while (i < len & this.is_space((int)v[i])) { i++; };
                switch (i < len & v[i] == ':')
                {
                    case (true) {
                    i++;
                    while (i < len & this.is_space((int)v[i])) { i++; };
                }
                    default {};
                };
                PtrVec* exprs = pv_new();
                int a, b;
                Node* e;
                switch (i < len & v[i] == '{' & v[len - 1] == '}')
                {
                    case (true) {
                    i++;
                    len = len - 1;
                    while (i <= len & !this.failed)
                    {
                        a = i;
                        while (a < len & v[a] != ';') { a++; };
                        b = a;
                        while (i < b & this.is_space((int)v[i])) { i++; };
                        while (b > i & this.is_space((int)v[b - 1])) { b--; };
                        switch (b > i)
                        {
                            case (true) {
                            e = this.sub_expr(v + i, b - i);
                            switch (!this.failed)
                            {
                                case (true) { pv_push(exprs, (void*)e); }
                                default {};
                            };
                        }
                            default {};
                        };
                        i = a + 1;
                    };
                }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) {
                    pv_free(exprs);
                    -> this.done(n);
                }
                    default {};
                };
                int k, used;
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                while (k < tlen)
                {
                    switch (tpl[k] == '{' & k + 1 < tlen & tpl[k + 1] == '}')
                    {
                        case (true) {
                        switch (used < exprs.len)
                        {
                            case (true) {
                            this.flush_text(n, line, col);
                            node_push(n, 0, (Node*)exprs.items[used]);
                            used++;
                        }
                            default {};
                        };
                        k += 2;
                    }
                        default {
                        this.sb.put((int)tpl[k]);
                        k++;
                    };
                    };
                };
                this.flush_text(n, line, col);
                while (used < exprs.len)
                {
                    node_free((Node*)exprs.items[used]);
                    used++;
                };
                pv_free(exprs);
                -> this.done(n);
            };

            // ===== CONTRACT BINDINGS =====
            // Binding node: l0 = pre names (IDENTIFIER text, "!" for none), l1 = post refs
            // (IDENTIFIER text = name, ival = arity or -1, op = 1 when negated), ival = chain operator or 0.

            binding_name() -> byte*
            {
                switch (this.expect(TokenType.THIS))
                {
                    case (true) {
                    this.advance();
                    -> g"this\0";
                }
                    default {};
                };
                -> this.ident();
            };

            binding_pre(Node* b) -> void
            {
                Node* x = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                node_push(b, 0, x);
                x.text = this.binding_name();
                ->;
            };

            // '!'? name ('(' INT ')')?
            binding_ref(Node* b) -> void
            {
                bool ok;
                Node* x = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                node_push(b, 1, x);
                x.ival = -1;
                switch (this.expect(TokenType.NOT))
                {
                    case (true) {
                    this.advance();
                    x.op = 1;
                }
                    default {};
                };
                x.text = this.binding_name();
                switch (this.failed)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (this.expect(TokenType.LEFT_PAREN))
                {
                    case (true) {
                    this.advance();
                    switch (!this.expect(TokenType.SINT_LITERAL))
                    {
                        case (true) {
                        this.fail_expected(TokenType.SINT_LITERAL);
                        ->;
                    }
                        default {};
                    };
                    x.ival = this.parse_int(this.cur_value(), @ok);
                    this.advance();
                    this.consume(TokenType.RIGHT_PAREN);
                }
                    default {};
                };
                ->;
            };

            // pre_side ':' post_side
            binding_spec() -> Node*
            {
                Node* b = this.mk(NodeKind.NODE_LIST, this.cur_line(), this.cur_col());
                switch (this.failed)
                {
                    case (true) { -> b; }
                    default {};
                };
                Node* x;
                int cur_op;
                switch (this.expect(TokenType.NOT))
                {
                    case (true) {
                    this.advance();
                    x = this.mk(NodeKind.IDENTIFIER, b.line, b.col);
                    switch (this.failed)
                    {
                        case (true) { -> this.done(b); }
                        default {};
                    };
                    x.text = g"!\0";
                    node_push(b, 0, x);
                }
                    default {
                    this.binding_pre(b);
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        this.binding_pre(b);
                    };
                };
                };
                switch (this.failed)
                {
                    case (true) { -> this.done(b); }
                    default {};
                };
                switch (!this.consume(TokenType.COLON))
                {
                    case (true) { -> this.done(b); }
                    default {};
                };

                switch (this.expect(TokenType.NOT) & this.type_at(1) == TokenType.RIGHT_BRACE)
                {
                    case (true) {
                    this.advance();
                    x = this.mk(NodeKind.IDENTIFIER, b.line, b.col);
                    switch (this.failed)
                    {
                        case (true) { -> this.done(b); }
                        default {};
                    };
                    x.text = g"!\0";
                    x.ival = -1;
                    node_push(b, 1, x);
                    -> b;
                }
                    default {};
                };
                this.binding_ref(b);
                while (!this.failed & this.expect3(TokenType.COMMA, TokenType.LOGICAL_OR, TokenType.LOGICAL_AND))
                {
                    switch (this.expect(TokenType.COMMA))
                    {
                        case (true) { cur_op = ','; }
                        default {
                            switch (this.expect(TokenType.LOGICAL_OR))
                            {
                                case (true) { cur_op = '|'; }
                                default { cur_op = '&'; };
                            };
                        };
                    };
                    switch (b.ival == 0)
                    {
                        case (true) { b.ival = (i64)cur_op; }
                        default {
                            switch (b.ival != (i64)cur_op)
                            {
                                case (true) {
                        this.error(g"Mixed operators in # binding post-side are not allowed; use the same operator throughout\0");
                        -> this.done(b);
                    }
                                default {};
                            };
                        };
                    };
                    this.advance();
                    this.binding_ref(b);
                };
                -> this.done(b);
            };

            // Index of the first entry of list (IDENTIFIER nodes in slot s of holder) named name
            // whose arity matches (arity -1 matches any), or -1
            ref_index(Node* holder, int s, byte* name, int arity) -> int
            {
                switch (holder == (Node*)0)
                {
                    case (true) { -> -1; }
                    default {};
                };
                int i;
                Node* x;
                while (i < node_count(holder, s))
                {
                    x = node_child(holder, s, i);
                    switch (cstr_eq(x.text, name))
                    {
                        case (true) {
                        switch (arity == -1 | (i64)arity == x.ival)
                        {
                            case (true) { -> i; }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> -1;
            };

            // Python list repr of the names in slot 1 of holder, e.g. ['A', 'B']
            names_repr(Node* holder) -> byte*
            {
                byte* r = g"[\0";
                int i;
                while (i < node_count(holder, 1))
                {
                    switch (i > 0)
                    {
                        case (true) { r = this.cat2(r, g", \0"); }
                        default {};
                    };
                    r = this.cat2(this.cat2(this.cat2(r, g"'\0"), node_child(holder, 1, i).text), g"'\0");
                    i++;
                };
                -> this.cat2(r, g"]\0");
            };

            // "Contract 'C' binding <mid> on function 'F'<tail>"
            bind_err(byte* cname, byte* mid, byte* fname, byte* tail) -> void
            {
                byte* m = this.cat2(g"Contract '\0", cname);
                m = this.cat2(m, g"' binding \0");
                m = this.cat2(m, mid);
                m = this.cat2(m, g" on function '\0");
                m = this.cat2(m, fname);
                m = this.cat2(m, g"'\0");
                this.error(this.cat2(m, tail));
                ->;
            };

            quoted(byte* a, byte* b, byte* c) -> byte* -> this.cat2(this.cat2(a, b), c);

            // Checks every # binding of the contracts attached to a function. pre and post hold the
            // attached contract names in slot 1 (either may be null).
            validate_bindings(byte* fname, Node* pre, Node* post) -> void
            {
                int npre, npost;
                switch (pre != (Node*)0)
                {
                    case (true) { npre = node_count(pre, 1); }
                    default {};
                };
                switch (post != (Node*)0)
                {
                    case (true) { npost = node_count(post, 1); }
                    default {};
                };
                int total = npre + npost;
                int ci, k, i, j, last, found, ni;
                Node* ct;
                Node* bd;
                Node* x;
                byte* cname;
                byte* rn;
                bool is_pre, is_post, matched, neg;
                int op;
                while (ci < total & !this.failed)
                {
                    switch (ci < npre)
                    {
                        case (true) { cname = node_child(pre, 1, ci).text; }
                        default { cname = node_child(post, 1, ci - npre).text; };
                    };
                    ci++;
                    // Only the first occurrence of each name is checked
                    k = 0;
                    found = 0;
                    while (k < ci - 1)
                    {
                        switch (k < npre)
                        {
                            case (true) { rn = node_child(pre, 1, k).text; }
                            default { rn = node_child(post, 1, k - npre).text; };
                        };
                        switch (cstr_eq(rn, cname))
                        {
                            case (true) { found = 1; }
                            default {};
                        };
                        k++;
                    };
                    switch (found == 1)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    ct = this.contract_find(cname);
                    switch (ct == (Node*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    bd = ct.b;
                    switch (bd == (Node*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    is_pre = this.ref_index(pre, 1, cname, -1) >= 0;
                    is_post = this.ref_index(post, 1, cname, -1) >= 0;

                    // pre side
                    switch (cstr_eq(node_child(bd, 0, 0).text, g"!\0"))
                    {
                        case (true) {
                        switch (npre > 0)
                        {
                            case (true) {
                            this.bind_err(cname, g"declares no pre-contract is allowed\0", fname, this.cat2(g", but pre-contracts are present: \0", this.names_repr(pre)));
                            ->;
                        }
                            default {};
                        };
                    }
                        default {
                        i = 0;
                        while (i < node_count(bd, 0) & !this.failed)
                        {
                            rn = node_child(bd, 0, i).text;
                            i++;
                            switch (cstr_eq(rn, g"this\0"))
                            {
                                case (true) {
                                switch (!is_pre)
                                {
                                    case (true) { this.bind_err(cname, g"requires itself as a pre-contract\0", fname, g", but it is only used as a post-contract\0"); }
                                    default {};
                                };
                            }
                                default {
                                    switch (this.ref_index(pre, 1, rn, -1) < 0)
                                    {
                                        case (true) {
                                switch (this.ref_index(post, 1, rn, -1) >= 0)
                                {
                                    case (true) {
                                    this.bind_err(cname, this.quoted(g"requires '\0", rn, g"' as a pre-contract\0"), fname, g", but it is inverted (used as a post-contract instead)\0");
                                }
                                    default {
                                    this.bind_err(cname, this.quoted(g"requires pre-contract '\0", rn, g"'\0"), fname, g", but it is not present\0");
                                };
                                };
                            }
                                        default {};
                                    };
                                };
                            };
                        };
                        switch (this.failed)
                        {
                            case (true) { ->; }
                            default {};
                        };
                    };
                    };

                    // post side
                    switch (node_count(bd, 1) == 0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (cstr_eq(node_child(bd, 1, 0).text, g"!\0"))
                    {
                        case (true) {
                        switch (npost > 0)
                        {
                            case (true) {
                            this.bind_err(cname, g"declares no post-contract is allowed\0", fname, this.cat2(g", but post-contracts are present: \0", this.names_repr(post)));
                            ->;
                        }
                            default {};
                        };
                        continue;
                    }
                        default {};
                    };
                    op = (int)bd.ival;

                    switch (op == '&')
                    {
                        case (true) {
                        i = 0;
                        while (i < node_count(bd, 1) & !this.failed)
                        {
                            x = node_child(bd, 1, i);
                            i++;
                            rn = x.text;
                            switch (cstr_eq(rn, g"this\0"))
                            {
                                case (true) { rn = cname; }
                                default {};
                            };
                            matched = this.ref_index(post, 1, rn, (int)x.ival) >= 0;
                            neg = x.op == 1;
                            switch (!neg & !matched)
                            {
                                case (true) {
                                switch (this.ref_index(pre, 1, rn, (int)x.ival) >= 0)
                                {
                                    case (true) {
                                    this.bind_err(cname, this.quoted(g"requires '\0", rn, g"' as a post-contract\0"), fname, g", but it is inverted (used as a pre-contract instead)\0");
                                }
                                    default {
                                    this.bind_err(cname, this.quoted(g"requires post-contract '\0", rn, g"'\0"), fname, g"\0");
                                };
                                };
                            }
                                default {
                                    switch (neg & matched)
                                    {
                                        case (true) {
                                this.bind_err(cname, this.quoted(g"forbids post-contract '\0", rn, g"'\0"), fname, g"\0");
                            }
                                        default {};
                                    };
                                };
                            };
                        };
                        switch (this.failed)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        continue;
                    }
                        default {};
                    };

                    // ',' and '|' chains: forbidden first, then the required ones in order
                    i = 0;
                    while (i < node_count(bd, 1) & !this.failed)
                    {
                        x = node_child(bd, 1, i);
                        i++;
                        switch (x.op == 1)
                        {
                            case (true) {
                            rn = x.text;
                            switch (cstr_eq(rn, g"this\0"))
                            {
                                case (true) { rn = cname; }
                                default {};
                            };
                            switch (this.ref_index(post, 1, rn, (int)x.ival) >= 0)
                            {
                                case (true) {
                                this.bind_err(cname, this.quoted(g"forbids post-contract '\0", rn, g"'\0"), fname, g"\0");
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    };
                    switch (this.failed)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    last = -1;
                    i = 0;
                    while (i < node_count(bd, 1) & !this.failed)
                    {
                        x = node_child(bd, 1, i);
                        i++;
                        switch (x.op == 1)
                        {
                            case (true) { continue; }
                            default {};
                        };
                        rn = x.text;
                        switch (cstr_eq(rn, g"this\0"))
                        {
                            case (true) { rn = cname; }
                            default {};
                        };
                        j = this.ref_index(post, 1, rn, (int)x.ival);
                        switch (j < 0)
                        {
                            case (true) {
                            switch (op == '|')
                            {
                                case (true) { continue; }
                                default {};
                            };
                            switch (this.ref_index(pre, 1, rn, (int)x.ival) >= 0)
                            {
                                case (true) {
                                this.bind_err(cname, this.quoted(g"requires '\0", rn, g"' as a post-contract\0"), fname, g", but it is inverted (used as a pre-contract instead)\0");
                            }
                                default {
                                this.bind_err(cname, this.quoted(g"requires post-contract '\0", rn, g"'\0"), fname, g"\0");
                            };
                            };
                            continue;
                        }
                            default {};
                        };
                        switch (j <= last)
                        {
                            case (true) {
                            this.bind_err(cname, this.cat2(g"requires post-contracts \0", this.required_repr(bd, cname)), fname, g" in that order\0");
                            continue;
                        }
                            default {};
                        };
                        last = j;
                    };
                };
                ->;
            };

            // Python list repr of the non-negated names of a binding's post side, 'this' resolved
            required_repr(Node* bd, byte* cname) -> byte*
            {
                byte* r = g"[\0";
                int i, n;
                Node* x;
                byte* nm;
                while (i < node_count(bd, 1))
                {
                    x = node_child(bd, 1, i);
                    i++;
                    switch (x.op == 1)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    nm = x.text;
                    switch (cstr_eq(nm, g"this\0"))
                    {
                        case (true) { nm = cname; }
                        default {};
                    };
                    switch (n > 0)
                    {
                        case (true) { r = this.cat2(r, g", \0"); }
                        default {};
                    };
                    r = this.cat2(this.cat2(this.cat2(r, g"'\0"), nm), g"'\0");
                    n++;
                };
                -> this.cat2(r, g"]\0");
            };


            // ===== STATEMENT DISPATCH =====

            // statement -> declaration | definition | control statement | expression statement.
            // Returns null for empty statements.
            statement() -> Node*
            {
                int sc = -1;
                int m, c;
                bool is_asm, is_func, is_volatile;

                c = this.cur();
                switch (c)
                {
                    case (TokenType.GLOBAL)
                    {
                        sc = StorageClass.GLOBAL;
                        this.advance();
                    }
                    case (TokenType.LOCAL)
                    {
                        sc = StorageClass.LOCAL;
                        this.advance();
                    }
                    case (TokenType.HEAP)
                    {
                        sc = StorageClass.HEAP;
                        this.advance();
                    }
                    case (TokenType.STACK)
                    {
                        sc = StorageClass.STACK;
                        this.advance();
                    }
                    case (TokenType.REGISTER)
                    {
                        sc = StorageClass.REGISTER;
                        this.advance();
                    }
                    case (TokenType.SINGINIT)
                    {
                        sc = StorageClass.SINGINIT;
                        this.advance();
                    }
                    default {};
                };

                switch (sc >= 0 | this.expect2(TokenType.CONST, TokenType.VOLATILE))
                {
                    case (true) {
                    m = this.mark();
                    while (this.expect4(TokenType.CONST, TokenType.VOLATILE, TokenType.SINGINIT, TokenType.INLINE))
                    {
                        this.advance();
                    };
                    is_asm = this.expect(TokenType.ASM);
                    is_func = this.expect3(TokenType.DEF, TokenType.INLINE, TokenType.NO_MANGLE)
                            | this.is_calling_conv(this.cur())
                            | this.is_bare_function_def();
                    this.reset(m);

                    switch (is_asm)
                    {
                        case (true) {
                        is_volatile = false;
                        switch (this.expect(TokenType.VOLATILE))
                        {
                            case (true) {
                            is_volatile = true;
                            this.advance();
                        }
                            default {};
                        };
                        -> this.asm_statement(is_volatile);
                    }
                        default {
                            switch (is_func)
                            {
                                case (true) {
                        -> this.function_def();
                    }
                                default {
                        switch (sc >= 0)
                        {
                            case (true) { this.pos--; }
                            default {};
                        };
                        -> this.variable_declaration_statement();
                    };
                            };
                        };
                    };
                }
                    default {};
                };

                c = this.cur();
                switch (c == TokenType.MACRO)
                {
                    case (true) { -> this.macro_def(); }
                    default {
                        switch (c == TokenType.USING)
                        {
                            case (true) { -> this.using_statement(); }
                            default {
                                switch (c == TokenType.NOT)
                                {
                                    case (true){
                    this.advance();
                    switch (this.expect(TokenType.USING))
                    {
                        case (true) {
                        this.advance();
                        -> this.not_using_statement();
                    }
                        default {};
                    };
                }
                                    default {
                                        switch (c == TokenType.OPERATOR)
                                        {
                                            case (true) { -> this.operator_def(); }
                                            default {
                                                switch (c == TokenType.EXTERN)
                                                {
                                                    case (true) { -> this.extern_statement(); }
                                                    default {
                                                        switch (c == TokenType.EXPORT)
                                                        {
                                                            case (true) { -> this.export_statement(); }
                                                            default {
                                                                switch (c == TokenType.CONTRACT)
                                                                {
                                                                    case (true) { -> this.contract_def(); }
                                                                    default {
                                                                        switch (c == TokenType.CONSTRAINT)
                                                                        {
                                                                            case (true) { -> this.constra_def(); }
                                                                            default {
                                                                                switch (c == TokenType.EFFECT)
                                                                                {
                                                                                    case (true) { -> this.effect_def(); }
                                                                                    default {
                                                                                        switch (c == TokenType.INLINE)
                                                                                        {
                                                                                            case (true) { -> this.function_def(); }
                                                                                            default {
                                                                                                switch (c == TokenType.DEF)
                                                                                                {
                                                                                                    case (true) { -> this.function_def(); }
                                                                                                    default {
                                                                                                        switch (c == TokenType.NO_MANGLE)
                                                                                                        {
                                                                                                            case (true) { -> this.function_def(); }
                                                                                                            default {
                                                                                                                switch (this.is_calling_conv(c))
                                                                                                                {
                                                                                                                    case (true) { -> this.function_def(); }
                                                                                                                    default {
                                                                                                                        switch (this.is_bare_function_def())
                                                                                                                        {
                                                                                                                            case (true) { -> this.function_def(); }
                                                                                                                            default {
                                                                                                                                switch (c == TokenType.ENUM)
                                                                                                                                {
                                                                                                                                    case (true) { -> this.enum_def(); }
                                                                                                                                    default {
                                                                                                                                        switch (this.type_at(1) == TokenType.ENUM)
                                                                                                                                        {
                                                                                                                                            case (true) { -> this.enum_def(); }
                                                                                                                                            default {
                                                                                                                                                switch (c == TokenType.UNION)
                                                                                                                                                {
                                                                                                                                                    case (true) { -> this.union_def(); }
                                                                                                                                                    default {
                                                                                                                                                        switch (c == TokenType.STRUCT)
                                                                                                                                                        {
                                                                                                                                                            case (true) {
                    switch (this.type_at(1) == TokenType.MULTIPLY)
                    {
                        case (true) {
                        -> this.variable_declaration_statement();
                    }
                        default {};
                    };
                    -> this.struct_def();
                }
                                                                                                                                                            default {
                                                                                                                                                                switch (c == TokenType.OBJECT)
                                                                                                                                                                {
                                                                                                                                                                    case (true) {
                    switch (this.type_at(1) == TokenType.MULTIPLY)
                    {
                        case (true) {
                        -> this.variable_declaration_statement();
                    }
                        default {};
                    };
                    -> this.object_def();
                }
                                                                                                                                                                    default {
                                                                                                                                                                        switch (c == TokenType.TRAIT)
                                                                                                                                                                        {
                                                                                                                                                                            case (true) { -> this.trait_def(); }
                                                                                                                                                                            default {
                                                                                                                                                                                switch (c == TokenType.INTERFACE)
                                                                                                                                                                                {
                                                                                                                                                                                    case (true) { -> this.interface_def(); }
                                                                                                                                                                                    default {
                                                                                                                                                                                        switch (this.is_trait_prefixed_object())
                                                                                                                                                                                        {
                                                                                                                                                                                            case (true) { -> this.trait_prefixed_object(); }
                                                                                                                                                                                            default {
                                                                                                                                                                                                switch (c == TokenType.NAMESPACE)
                                                                                                                                                                                                {
                                                                                                                                                                                                    case (true) { -> this.namespace_def(); }
                                                                                                                                                                                                    default {
                                                                                                                                                                                                        switch (c == TokenType.IF)
                                                                                                                                                                                                        {
                                                                                                                                                                                                            case (true) { -> this.if_statement(); }
                                                                                                                                                                                                            default {
                                                                                                                                                                                                                switch (c == TokenType.DO)
                                                                                                                                                                                                                {
                                                                                                                                                                                                                    case (true) { -> this.do_while_statement(); }
                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                        switch (c == TokenType.WHILE)
                                                                                                                                                                                                                        {
                                                                                                                                                                                                                            case (true) { -> this.while_statement(); }
                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                switch (c == TokenType.FOR)
                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                    case (true) { -> this.for_statement(); }
                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                        switch (c == TokenType.SWITCH)
                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                            case (true) { -> this.switch_statement(); }
                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                switch (c == TokenType.TRY)
                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                    case (true) { -> this.try_statement(); }
                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                        switch (c == TokenType.RETURN)
                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                            case (true) { -> this.return_statement(); }
                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                switch (c == TokenType.RETURN_ARROW)
                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                    case (true) { -> this.return_arrow_ret(); }
                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                        switch (c == TokenType.BREAK)
                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                            case (true) { -> this.break_statement(); }
                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                switch (c == TokenType.CONTINUE)
                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                    case (true) { -> this.continue_statement(); }
                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                        switch (c == TokenType.LABEL)
                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                            case (true) { -> this.label_statement(); }
                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                switch (c == TokenType.GOTO)
                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                    case (true) { -> this.goto_statement(); }
                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                        switch (c == TokenType.JUMP)
                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                            case (true) { -> this.jump_statement(); }
                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                switch (c == TokenType.THROW)
                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                    case (true) { -> this.throw_statement(); }
                                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                                        switch (c == TokenType.ASSERT)
                                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                                            case (true) { -> this.assert_statement(); }
                                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                                switch (c == TokenType.DEFER)
                                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                                    case (true) { -> this.defer_statement(); }
                                                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                                                        switch (c == TokenType.ESCAPE_KW)
                                                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                                                            case (true) { -> this.escape_statement(); }
                                                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                                                switch (c == TokenType.DEPRECATE)
                                                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                                                    case (true) { -> this.deprecate_statement(); }
                                                                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                                                                        switch (c == TokenType.NORET)
                                                                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                                                                            case (true) { -> this.noreturn_statement(); }
                                                                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                                                                switch (c == TokenType.LEFT_BRACE)
                                                                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                                                                    case (true) { -> this.block_statement(); }
                                                                                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                                                                                        switch (this.is_type_func_def())
                                                                                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                                                                                            case (true) { -> this.type_func_def(); }
                                                                                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                                                                                switch (this.is_dual_assign_declaration())
                                                                                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                                                                                    case (true) { -> this.dual_assign_declaration(); }
                                                                                                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                                                                                                        switch (this.is_variable_declaration())
                                                                                                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                                                                                                            case (true) { -> this.variable_declaration_statement(); }
                                                                                                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                                                                                                switch (c == TokenType.UNSIGNED)
                                                                                                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                                                                                                    case (true) { -> this.variable_declaration_statement(); }
                                                                                                                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                                                                                                                        switch (c == TokenType.SIGNED)
                                                                                                                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                                                                                                                            case (true) { -> this.variable_declaration_statement(); }
                                                                                                                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                                                                                                                switch (this.expect4(TokenType.SINT, TokenType.UINT, TokenType.DATA, TokenType.CHAR)
                    | this.expect4(TokenType.BYTE, TokenType.FLOAT_KW, TokenType.DOUBLE_KW, TokenType.BOOL_KW)
                    | this.expect4(TokenType.VOID, TokenType.SLONG, TokenType.ULONG, TokenType.DICT))
                                                                                                                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                                                                                                                    case (true) {
                    -> this.variable_declaration_statement();
                }
                                                                                                                                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                                                                                                                                        switch (c == TokenType.DITTO)
                                                                                                                                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                                                                                                                                            case (true) { -> this.ditto_statement(); }
                                                                                                                                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                                                                                                                                switch (c == TokenType.SEMICOLON)
                                                                                                                                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                                                                                                                                    case (true) {
                    this.advance();
                    -> (Node*)0;
                }
                                                                                                                                                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                                                                                                                                                        switch (c == TokenType.AUTO & this.type_at(1) == TokenType.LEFT_BRACE)
                                                                                                                                                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                                                                                                                                                            case (true) {
                    Node* dn = this.destructuring_assignment();
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                    -> dn;
                }
                                                                                                                                                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                                                                                                                                                switch (c == TokenType.AUTO & this.type_at(1) == TokenType.IDENTIFIER)
                                                                                                                                                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                                                                                                                                                    case (true) {
                    Node* av = this.auto_variable_declaration();
                    switch (!this.failed)
                    {
                        case (true) { this.consume(TokenType.SEMICOLON); }
                        default {};
                    };
                    -> av;
                }
                                                                                                                                                                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                                                                                                                                                                        switch (c == TokenType.CODIFY)
                                                                                                                                                                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                                                                                                                                                                            case (true) { -> this.codify_statement(); }
                                                                                                                                                                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                switch (c == TokenType.COMPTIME)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                    case (true) { -> this.comptime_block(); }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                        switch (c == TokenType.EMITFLUX)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                            case (true) {
                    switch (this.in_comptime == 0)
                    {
                        case (true) {
                        this.error(g"'emitflux' is only valid inside a 'comptime' block\0");
                        -> (Node*)0;
                    }
                        default {};
                    };
                    -> this.emitflux_statement();
                }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                switch (c == TokenType.ASM)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    case (true) { -> this.asm_statement(false); }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    default {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        switch (c == TokenType.FLUXVM)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            case (true) {
                    switch (this.in_comptime == 0)
                    {
                        case (true) {
                        this.error(g"'fluxvm' is only valid inside a 'comptime' block\0");
                        -> (Node*)0;
                    }
                        default {};
                    };
                    -> this.fluxvm_statement();
                }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            default {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                switch (c == TokenType.IDENTIFIER & this.val_is(g"error\0", 5) & this.type_at(1) >= 0 & this.type_at(1) != TokenType.ASSIGN)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    case (true) {
                    -> this.error_return_statement();
                }
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    default {
                    -> this.expression_statement();
                };
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                                };
                                                                                                                                                                                                                                            };
                                                                                                                                                                                                                                        };
                                                                                                                                                                                                                                    };
                                                                                                                                                                                                                                };
                                                                                                                                                                                                                            };
                                                                                                                                                                                                                        };
                                                                                                                                                                                                                    };
                                                                                                                                                                                                                };
                                                                                                                                                                                                            };
                                                                                                                                                                                                        };
                                                                                                                                                                                                    };
                                                                                                                                                                                                };
                                                                                                                                                                                            };
                                                                                                                                                                                        };
                                                                                                                                                                                    };
                                                                                                                                                                                };
                                                                                                                                                                            };
                                                                                                                                                                        };
                                                                                                                                                                    };
                                                                                                                                                                };
                                                                                                                                                            };
                                                                                                                                                        };
                                                                                                                                                    };
                                                                                                                                                };
                                                                                                                                            };
                                                                                                                                        };
                                                                                                                                    };
                                                                                                                                };
                                                                                                                            };
                                                                                                                        };
                                                                                                                    };
                                                                                                                };
                                                                                                            };
                                                                                                        };
                                                                                                    };
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };

                -> (Node*)0;
            };

            // ===== DRIVER =====

            // program -> statement* EOF. Returns a PROGRAM node (l0 = statements).
            parse() -> Node*
            {
                Node* prog = node_new(NodeKind.PROGRAM, 1, 1);
                Node* stmt;
                int k;
                switch (prog == (Node*)0)
                {
                    case (true) {
                    this.failed = true;
                    this.err_kind = ParseErr.ALLOC;
                    -> prog;
                }
                    default {};
                };
                switch (this.failed)
                {
                    case (true) { -> prog; }
                    default {};
                };

                this.toks = this.lx.tokens;
                this.count = this.lx.count;
                this.pos = 0;
                switch (this.count == 0)
                {
                    case (true) {
                    this.error(g"no tokens to parse\0");
                    -> prog;
                }
                    default {};
                };

                while (!this.expect(TokenType.EOF))
                {
                    stmt = this.statement();
                    switch (this.failed)
                    {
                        case (true) { break; }
                        default {};
                    };
                    switch (stmt != (Node*)0)
                    {
                        case (true) {
                        node_push(prog, 0, stmt);
                        this.last_stmt = stmt;
                    }
                        default {};
                    };
                    k = 0;
                    while (k < this.pending.len)
                    {
                        node_push(prog, 0, this.pending.items[k]);
                        k++;
                    };
                    switch (this.pending.len > 0)
                    {
                        case (true) { this.last_stmt = this.pending.items[this.pending.len - 1]; }
                        default {};
                    };
                    this.pending.len = 0;
                };
                switch (this.failed)
                {
                    case (true) { -> prog; }
                    default {};
                };
                // template instances go after everything else: structs, objects, then functions
                k = 0;
                while (k < this.tinst_s.len)
                {
                    node_push(prog, 0, (Node*)this.tinst_s.items[k]);
                    k++;
                };
                k = 0;
                while (k < this.tinst_o.len)
                {
                    node_push(prog, 0, (Node*)this.tinst_o.items[k]);
                    k++;
                };
                k = 0;
                while (k < this.tinst_f.len)
                {
                    node_push(prog, 0, (Node*)this.tinst_f.items[k]);
                    k++;
                };
                this.tinst_s.len = 0;
                this.tinst_o.len = 0;
                this.tinst_f.len = 0;
                -> prog;
            };
        };
    };
};

#endif;
