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

        def feature_name(int f) -> byte*
        {
            switch (f)
            {
                case (Feat.FUNCTION_DEF) { return g"Function Definition\0"; }
                case (Feat.ENUM_DEF) { return g"Enum Definition\0"; }
                case (Feat.MACRO_DEF) { return g"Macro Definition\0"; }
                case (Feat.UNION_DEF) { return g"Union Definition\0"; }
                case (Feat.STRUCT_DEF) { return g"Struct Definition\0"; }
                case (Feat.TRAIT_DEF) { return g"Trait Definition\0"; }
                case (Feat.EFFECT_DEF) { return g"Effect Definition\0"; }
                case (Feat.INTERFACE_DEF) { return g"Interface Definition\0"; }
                case (Feat.OBJECT_DEF) { return g"Object Definition\0"; }
                case (Feat.TRAIT_PREFIXED_OBJECT) { return g"Trait Prefixed Object Definition\0"; }
                case (Feat.NAMESPACE_DEF) { return g"Namespace Definition\0"; }
                case (Feat.USING_STATEMENT) { return g"Using Statement\0"; }
                case (Feat.NOT_USING_STATEMENT) { return g"Not Using Statement\0"; }
                case (Feat.DEPRECATE_STATEMENT) { return g"Deprecate Statement\0"; }
                case (Feat.EXTERN_STATEMENT) { return g"Extern Block\0"; }
                case (Feat.EXPORT_STATEMENT) { return g"Export Block\0"; }
                case (Feat.CONTRACT_DEF) { return g"Contract Definition\0"; }
                case (Feat.CONSTRA_DEF) { return g"Constraint Definition\0"; }
                case (Feat.OPERATOR_DEF) { return g"Operator Definition\0"; }
                case (Feat.TYPE_FUNC_DEF) { return g"Type Function Definition\0"; }
                case (Feat.VARIABLE_DECLARATION) { return g"Variable Declaration\0"; }
                case (Feat.VARIABLE_DECLARATION_STATEMENT) { return g"Variable Declaration Statement\0"; }
                case (Feat.DUAL_ASSIGN_DECLARATION) { return g"Dual Assign Declaration\0"; }
                case (Feat.AUTO_VARIABLE_DECLARATION) { return g"Auto Variable Declaration\0"; }
                case (Feat.DESTRUCTURING_ASSIGNMENT) { return g"Destructuring Assignment\0"; }
                case (Feat.BLOCK_STATEMENT) { return g"Block Statement\0"; }
                case (Feat.ASM_STATEMENT) { return g"Inline Assembly\0"; }
                case (Feat.FLUXVM_STATEMENT) { return g"FluxVM Block\0"; }
                case (Feat.COMPTIME_BLOCK) { return g"Comptime Block\0"; }
                case (Feat.EMITFLUX_STATEMENT) { return g"EmitFlux\0"; }
                case (Feat.IF_STATEMENT) { return g"If Statement\0"; }
                case (Feat.WHILE_STATEMENT) { return g"While Loop\0"; }
                case (Feat.DO_WHILE_STATEMENT) { return g"Do Loop\0"; }
                case (Feat.FOR_STATEMENT) { return g"For Loop\0"; }
                case (Feat.SWITCH_STATEMENT) { return g"Switch Statement\0"; }
                case (Feat.TRY_STATEMENT) { return g"Try Block\0"; }
                case (Feat.RETURN_STATEMENT) { return g"Return Statement\0"; }
                case (Feat.RETURN_ARROW_RET) { return g"Return Arrow Statement\0"; }
                case (Feat.ERROR_RETURN_STATEMENT) { return g"Error Return Statement\0"; }
                case (Feat.BREAK_STATEMENT) { return g"Break Statement\0"; }
                case (Feat.CONTINUE_STATEMENT) { return g"Continue Statement\0"; }
                case (Feat.LABEL_STATEMENT) { return g"Label Statement\0"; }
                case (Feat.GOTO_STATEMENT) { return g"Goto Statement\0"; }
                case (Feat.JUMP_STATEMENT) { return g"Jump Statement\0"; }
                case (Feat.THROW_STATEMENT) { return g"Throw Statement\0"; }
                case (Feat.ASSERT_STATEMENT) { return g"Assert Statement\0"; }
                case (Feat.DEFER_STATEMENT) { return g"Defer Statement\0"; }
                case (Feat.ESCAPE_STATEMENT) { return g"Escape Statement\0"; }
                case (Feat.NORETURN_STATEMENT) { return g"Noreturn Statement\0"; }
                case (Feat.DITTO_STATEMENT) { return g"Ditto Statement\0"; }
                case (Feat.CODIFY_STATEMENT) { return g"Codify Statement\0"; }
                case (Feat.EXPRESSION_STATEMENT) { return g"Expression Statement\0"; }
                case (Feat.FSTRING_EXPR) { return g"f-string Expression\0"; }
                case (Feat.ISTRING_EXPR) { return g"i-string Expression\0"; }
                case (Feat.CODIFY_EXPR) { return g"Codify Expression\0"; }
                case (Feat.TEMPLATE_FUNCTION) { return g"Template Function\0"; }
                case (Feat.FUNCTION_CONTRACT) { return g"Function Contract\0"; }
                case (Feat.TEMPLATE_STRUCT) { return g"Template Struct\0"; }
                case (Feat.TEMPLATE_OBJECT) { return g"Template Object\0"; }
                case (Feat.AS_OPERATOR) { return g"Operator Binding (as operator)\0"; }
                case (Feat.TEMPLATE_OPERATOR) { return g"Template Operator\0"; }
                case (Feat.CONTRACT_BINDING) { return g"Contract Binding Spec\0"; }
                default { return g"Unknown Feature\0"; };
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

        def ps_bytes_eq(byte* a, byte* b, int n) -> bool
        {
            int i;
            while (i < n)
            {
                if (a[i] != b[i]) { return false; };
                i++;
            };
            return true;
        };

        // ===== TREE DUMP =====
        // Canonical text form of a tree, one node per line, used to compare against
        // fparser.py (see dump_ast.py).
        //     KIND [op=..] [text=".."] [text2=".."] [val=N] [flags=N] [ts=..]
        // followed by the slots a..e as "a: ..." and list slots as "l0[i]: ...".

        def dump_pad(int depth) -> void
        {
            int i;
            while (i < depth)
            {
                print(g"  \0");
                i++;
            };
            return;
        };

        // Compact form of a TypeSpec
        def dump_ts(TypeSpec* t) -> void
        {
            if (t.custom_typename != (byte*)0)
            {
                print(t.custom_typename);
            }
            else
            {
                print(datatype_text(t.base_type));
            };
            if ((t.flags `& TS_SIGNED) != 0) { print(g",signed\0"); };
            if ((t.flags `& TS_CONST) != 0) { print(g",const\0"); };
            if ((t.flags `& TS_VOLATILE) != 0) { print(g",volatile\0"); };
            if ((t.flags `& TS_TIED) != 0) { print(g",tied\0"); };
            if ((t.flags `& TS_LOCAL) != 0) { print(g",local\0"); };
            if ((t.flags `& TS_NO_FUNCTIONS) != 0) { print(g",nofunc\0"); };
            if (t.bit_width >= 0) { print(g",w\0"); print(t.bit_width); };
            if (t.alignment >= 0) { print(g",a\0"); print(t.alignment); };
            if (t.endianness != 1) { print(g",e\0"); print(t.endianness); };
            if (t.storage_class >= 0) { print(g",sc\0"); print(t.storage_class); };
            if ((t.flags `& TS_POINTER) != 0) { print(g",ptr\0"); print(t.pointer_depth); };
            if ((t.flags `& TS_ARRAY) != 0)
            {
                print(g",arr\0");
                if (t.array_dims != (NodeVec*)0) { print(t.array_dims.len); };
            };
            if (t.base_type == DataType.DICT)
            {
                print(g"{\0");
                dump_ts(t.dict_key);
                print(g":\0");
                dump_ts(t.dict_value);
                print(g"}\0");
            };
            return;
        };

        def dump_quoted(byte* s) -> void
        {
            print(g"\"\0");
            print(s);
            print(g"\"\0");
            return;
        };

        // slot: -1 none, 0..4 for a..e, 10+s for list slot s (idx is the element index)
        def dump_tag(int slot, int idx) -> void
        {
            if (slot < 0) { return; };
            if (slot == 0) { print(g"a: \0"); }
            elif (slot == 1) { print(g"b: \0"); }
            elif (slot == 2) { print(g"c: \0"); }
            elif (slot == 3) { print(g"d: \0"); }
            elif (slot == 4) { print(g"e: \0"); }
            else
            {
                print(g"l\0");
                print(slot - 10);
                print(g"[\0");
                print(idx);
                print(g"]: \0");
            };
            return;
        };

        def dump_node(Node* n, int depth, int slot, int idx) -> void
        {
            dump_pad(depth);
            dump_tag(slot, idx);
            if (n == (Node*)0)
            {
                println(g"null\0");
                return;
            };
            print(node_kind_name(n.kind));
            int k = n.kind;
            if (k == NodeKind.BINARY_OP | k == NodeKind.UNARY_OP)
            {
                print(g" op=\0");
                print(operator_text(n.op));
            }
            elif (k == NodeKind.LITERAL)
            {
                print(g" op=\0");
                print(datatype_text(n.op));
                if (n.op != DataType.FLOAT & n.op != DataType.DOUBLE & n.op != DataType.CHAR)
                {
                    print(g" val=\0");
                    print(n.ival);
                };
                if (n.op == DataType.CHAR & n.text != (byte*)0)
                {
                    print(g" text=\0");
                    dump_quoted(n.text);
                };
            }
            elif (k == NodeKind.COMPOUND_ASSIGNMENT)
            {
                print(g" op=\0");
                print(token_name(n.op));
            };
            if (k != NodeKind.LITERAL)
            {
                if (n.text != (byte*)0)
                {
                    print(g" text=\0");
                    dump_quoted(n.text);
                };
                if (n.text2 != (byte*)0)
                {
                    print(g" text2=\0");
                    dump_quoted(n.text2);
                };
            };
            if ((n.flags `& (NF_POSTFIX `| NF_NEGATED)) != 0)
            {
                print(g" flags=\0");
                print(n.flags `& (NF_POSTFIX `| NF_NEGATED));
            };
            if (n.ts != (TypeSpec*)0)
            {
                print(g" ts=\0");
                dump_ts(n.ts);
            };
            println(g"\0");
            if (n.a != (Node*)0) { dump_node(n.a, depth + 1, 0, 0); };
            if (n.b != (Node*)0) { dump_node(n.b, depth + 1, 1, 0); };
            if (n.c != (Node*)0) { dump_node(n.c, depth + 1, 2, 0); };
            if (n.d != (Node*)0) { dump_node(n.d, depth + 1, 3, 0); };
            if (n.e != (Node*)0) { dump_node(n.e, depth + 1, 4, 0); };
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
            return;
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

        def te_new() -> TemplateEntry*
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
            return e;
        };

        def te_free(TemplateEntry* e) -> void
        {
            int i;
            if (e == (TemplateEntry*)0) { return; };
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
            return;
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

            def __init(Lexer* lexer) -> this
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
                if (this.feat_hits == (int*)0)
                {
                    this.failed = true;
                    this.err_kind = ParseErr.ALLOC;
                    return this;
                };
                while (z < Feat.COUNT)
                {
                    this.feat_hits[z] = 0;
                    z++;
                };
                return this;
            };

            def __expr() -> Parser*
            {
                return this;
            };

            def __exit() -> void
            {
                if (this.feat_hits != (int*)0) { ffree((byte*)this.feat_hits); };
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
                    if (sp.st != (FXC_SYMTABLE*)0) { st_free(sp.st); };
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
                if (this.chk != (Checker*)0)
                {
                    this.chk.__exit();
                    ffree((byte*)this.chk);
                };
                this.sb.__exit();
                return;
            };

            // ===== TOKEN CURSOR =====

            def cur() -> int
            {
                return this.toks[this.pos].type;
            };

            def cur_line() -> int
            {
                return this.toks[this.pos].line;
            };

            def cur_col() -> int
            {
                return this.toks[this.pos].column;
            };

            // Value of the current token (null terminated)
            def cur_value() -> byte*
            {
                return this.lx.token_value(this.pos);
            };

            def cur_value_len() -> int
            {
                return this.toks[this.pos].vlen;
            };

            // True when the current token value is exactly lit[0, n)
            def val_is(byte* lit, int n) -> bool
            {
                if (this.cur_value_len() != n) { return false; };
                return ps_bytes_eq(this.cur_value(), lit, n);
            };

            // Type of the token at offset off from the current one, -1 outside the stream
            def type_at(int off) -> int
            {
                int p = this.pos + off;
                if (p < 0) { return -1; };
                if (p >= this.count) { return -1; };
                return this.toks[p].type;
            };

            def advance() -> void
            {
                if (this.pos < this.count - 1) { this.pos++; };
                return;
            };

            def expect(int a) -> bool
            {
                return this.cur() == a;
            };

            def expect2(int a, int b) -> bool
            {
                int c = this.cur();
                return c == a | c == b;
            };

            def expect3(int a, int b, int d) -> bool
            {
                int c = this.cur();
                return c == a | c == b | c == d;
            };

            def expect4(int a, int b, int d, int e) -> bool
            {
                int c = this.cur();
                return c == a | c == b | c == d | c == e;
            };

            // Lookahead: save the cursor, run predicates, restore with reset
            def mark() -> int
            {
                return this.pos;
            };

            def reset(int m) -> void
            {
                this.pos = m;
                return;
            };

            def is_calling_conv(int t) -> bool
            {
                return t == TokenType.CDECL | t == TokenType.STDCALL | t == TokenType.FASTCALL
                     | t == TokenType.THISCALL | t == TokenType.VECTORCALL;
            };

            // Tokens that can start the base type of a declaration
            def is_base_type_token() -> bool
            {
                return this.expect4(TokenType.SINT, TokenType.UINT, TokenType.FLOAT_KW, TokenType.DOUBLE_KW)
                     | this.expect4(TokenType.CHAR, TokenType.BOOL_KW, TokenType.BYTE, TokenType.DATA)
                     | this.expect4(TokenType.VOID, TokenType.SLONG, TokenType.ULONG, TokenType.STRUCT)
                     | this.expect3(TokenType.OBJECT, TokenType.IDENTIFIER, TokenType.DICT);
            };

            // ===== ERRORS =====

            // Records a parse error at the current token. Parsing stops at the first error.
            def error(byte* msg) -> void
            {
                if (this.failed) { return; };
                this.failed = true;
                this.err_kind = ParseErr.MESSAGE;
                this.err_msg = msg;
                this.err_line = this.cur_line();
                this.err_col = this.cur_col();
                return;
            };

            def fail_expected(int t) -> void
            {
                if (this.failed) { return; };
                this.failed = true;
                this.err_kind = ParseErr.EXPECTED;
                this.err_expected = t;
                this.err_got = this.cur();
                this.err_line = this.cur_line();
                this.err_col = this.cur_col();
                return;
            };

            // Consumes a token of type t. Records an error and returns false otherwise.
            def consume(int t) -> bool
            {
                if (!this.expect(t))
                {
                    this.fail_expected(t);
                    return false;
                };
                this.advance();
                return true;
            };

            def error_text() -> byte*
            {
                if (this.err_kind == ParseErr.MESSAGE) { return this.err_msg; };
                if (this.err_kind == ParseErr.ALLOC) { return g"parser allocation failed\0"; };
                return g"parse error\0";
            };

            // Prints the recorded error
            def print_error() -> void
            {
                print(g"Parser error: \0");
                if (this.err_kind == ParseErr.EXPECTED)
                {
                    print(g"Unexpected \0");
                    print(flux::lexer::token_name(this.err_got));
                    print(g", expected \0");
                    print(flux::lexer::token_name(this.err_expected));
                }
                else
                {
                    print(this.error_text());
                };
                print(g" at \0");
                print(this.err_line);
                print(g":\0");
                println(this.err_col);
                return;
            };

            // Skips to just after the next statement boundary
            def synchronize() -> void
            {
                this.advance();
                while (!this.expect(TokenType.EOF))
                {
                    if (this.pos > 0)
                    {
                        if (this.toks[this.pos - 1].type == TokenType.SEMICOLON) { return; };
                    };
                    if (this.expect4(TokenType.DEF, TokenType.STRUCT, TokenType.OBJECT, TokenType.NAMESPACE)) { return; };
                    if (this.expect4(TokenType.IF, TokenType.WHILE, TokenType.FOR, TokenType.RETURN)) { return; };
                    this.advance();
                };
                return;
            };

            // ===== STUB SUPPORT =====

            // Consumes tokens through the next semicolon at bracket depth zero.
            // A closing bracket without an opener ends the construct.
            // Returns the number of commas at bracket depth zero outside template
            // arguments, which is how many extra nodes a comma separated list
            // construct (using a, b; int x, y;) yields in fparser.py.
            def skip_construct() -> int
            {
                int depth, t, prev, angle, commas;
                bool in_init = false;
                prev = -1;
                while (true)
                {
                    t = this.cur();
                    if (t == TokenType.EOF) { return commas; };
                    if (t == TokenType.LEFT_PAREN | t == TokenType.LEFT_BRACKET | t == TokenType.LEFT_BRACE)
                    {
                        depth++;
                    }
                    elif (t == TokenType.RIGHT_PAREN | t == TokenType.RIGHT_BRACKET | t == TokenType.RIGHT_BRACE)
                    {
                        depth--;
                    }
                    elif (depth == 0)
                    {
                        if (t == TokenType.SEMICOLON)
                        {
                            this.advance();
                            return commas;
                        }
                        elif (t == TokenType.ASSIGN | t == TokenType.ADDRESS_ASSIGN)
                        {
                            in_init = true;
                        }
                        elif (t == TokenType.LESS_THAN & prev == TokenType.IDENTIFIER & !in_init)
                        {
                            angle++;
                        }
                        elif (t == TokenType.GREATER_THAN & angle > 0)
                        {
                            angle--;
                        }
                        elif (t == TokenType.BITSHIFT_RIGHT & angle > 1)
                        {
                            angle = angle - 2;
                        }
                        elif (t == TokenType.COMMA & angle == 0)
                        {
                            commas++;
                            in_init = false;
                        };
                    };
                    prev = t;
                    this.advance();
                    if (depth < 0) { return commas; };
                };
                return commas;
            };

            // Features whose fparser.py rule returns one node per comma separated name
            def is_list_feature(int feat) -> bool
            {
                return feat == Feat.USING_STATEMENT | feat == Feat.CONTRACT_DEF
                     | feat == Feat.VARIABLE_DECLARATION | feat == Feat.VARIABLE_DECLARATION_STATEMENT;
            };

            // Reports an unimplemented feature, skips the construct and returns a placeholder node
            def stub(int feat, int kind) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = node_new(kind, line, col);
                if (n == (Node*)0)
                {
                    this.failed = true;
                    this.err_kind = ParseErr.ALLOC;
                    return n;
                };
                n.flags = NF_STUB;

                this.stub_total++;
                if (this.feat_hits[feat] == 0) { this.stub_features++; };
                this.feat_hits[feat] = this.feat_hits[feat] + 1;

                if (this.verbose)
                {
                    print(g"[BootstrapParser] \0");
                    print(feature_name(feat));
                    print(g" not implemented (line \0");
                    print(line);
                    print(g", col \0");
                    print(col);
                    println(g")\0");
                }
                elif (this.feat_hits[feat] == 1)
                {
                    print(g"[BootstrapParser] \0");
                    print(feature_name(feat));
                    println(g" not implemented\0");
                };

                int extra = this.skip_construct();
                Node* x;
                if (this.is_list_feature(feat))
                {
                    while (extra > 0)
                    {
                        x = node_new(kind, line, col);
                        if (x == (Node*)0) { break; };
                        x.flags = NF_STUB;
                        nv_push(this.pending, x);
                        extra--;
                    };
                };
                return n;
            };

            // Prints how often each unimplemented feature was hit
            def report() -> void
            {
                int f;
                if (this.stub_total == 0) { return; };
                println(g"[BootstrapParser] Stub summary:\0");
                while (f < Feat.COUNT)
                {
                    if (this.feat_hits[f] != 0)
                    {
                        print(g"  \0");
                        print(feature_name(f));
                        print(g" : \0");
                        println(this.feat_hits[f]);
                    };
                    f++;
                };
                print(g"[BootstrapParser] \0");
                print(this.stub_total);
                print(g" construct(s) skipped across \0");
                print(this.stub_features);
                println(g" feature(s)\0");
                return;
            };

            // ===== LOOKAHEAD PREDICATES =====

            // (NO_MANGLE)? IDENTIFIER '(' ... ')' '->'
            def is_bare_function_def() -> bool
            {
                int m = this.mark();
                int depth;
                bool r = false;
                if (this.expect(TokenType.NO_MANGLE)) { this.advance(); };
                if (this.expect(TokenType.IDENTIFIER))
                {
                    this.advance();
                    if (this.expect(TokenType.LEFT_PAREN))
                    {
                        this.advance();
                        depth = 1;
                        while (depth > 0 & !this.expect(TokenType.EOF))
                        {
                            if (this.expect(TokenType.LEFT_PAREN))
                            {
                                depth++;
                            }
                            elif (this.expect(TokenType.RIGHT_PAREN))
                            {
                                depth--;
                                if (depth == 0) { break; };
                            };
                            this.advance();
                        };
                        if (this.expect(TokenType.RIGHT_PAREN))
                        {
                            this.advance();
                            r = this.expect(TokenType.RETURN_ARROW);
                        };
                    };
                };
                this.reset(m);
                return r;
            };

            // IDENTIFIER+ 'object'
            def is_trait_prefixed_object() -> bool
            {
                int off = 1;
                int t;
                if (!this.expect(TokenType.IDENTIFIER)) { return false; };
                while (true)
                {
                    t = this.type_at(off);
                    if (t < 0) { return false; };
                    if (t == TokenType.OBJECT) { return true; };
                    if (t != TokenType.IDENTIFIER) { return false; };
                    off++;
                };
                return false;
            };

            // Skips a balanced <...> region starting at the current '<'
            def skip_template_args() -> void
            {
                int depth = 1;
                this.advance();
                while (depth > 0 & !this.expect(TokenType.EOF))
                {
                    if (this.expect(TokenType.LESS_THAN))
                    {
                        depth++;
                    }
                    elif (this.expect(TokenType.GREATER_THAN))
                    {
                        depth--;
                        if (depth == 0) { break; };
                    };
                    this.advance();
                };
                if (this.expect(TokenType.GREATER_THAN)) { this.advance(); };
                return;
            };

            // Skips a balanced [...] region starting at the current '['
            def skip_brackets() -> void
            {
                int depth = 1;
                this.advance();
                while (depth > 0 & !this.expect(TokenType.EOF))
                {
                    if (this.expect(TokenType.LEFT_BRACKET))
                    {
                        depth++;
                    }
                    elif (this.expect(TokenType.RIGHT_BRACKET))
                    {
                        depth--;
                        if (depth == 0) { break; };
                    };
                    this.advance();
                };
                if (this.expect(TokenType.RIGHT_BRACKET)) { this.advance(); };
                return;
            };

            def is_variable_declaration() -> bool
            {
                int m = this.mark();
                bool r = false;
                bool done = false;

                if (this.expect(TokenType.CONST)) { this.advance(); };
                if (this.expect(TokenType.VOLATILE)) { this.advance(); };
                if (this.expect2(TokenType.SIGNED, TokenType.UNSIGNED)) { this.advance(); };
                if (this.expect(TokenType.TIE)) { this.advance(); };

                if (!this.is_base_type_token())
                {
                    this.reset(m);
                    return false;
                };
                this.advance();

                while (this.expect(TokenType.SCOPE))
                {
                    this.advance();
                    if (this.expect(TokenType.IDENTIFIER))
                    {
                        this.advance();
                    }
                    else
                    {
                        break;
                    };
                };

                if (this.expect(TokenType.LESS_THAN)) { this.skip_template_args(); };

                if (this.expect(TokenType.LEFT_BRACE))
                {
                    this.advance();
                    if (this.expect(TokenType.SINT_LITERAL)) { this.advance(); };
                    if (this.expect(TokenType.COLON))
                    {
                        this.advance();
                        if (this.expect(TokenType.SINT_LITERAL)) { this.advance(); };
                    }
                    elif (this.expect(TokenType.SCOPE))
                    {
                        this.advance();
                        if (this.expect(TokenType.SINT_LITERAL)) { this.advance(); };
                    };
                    if (this.expect(TokenType.RIGHT_BRACE)) { this.advance(); };
                };

                while (this.expect(TokenType.MULTIPLY)) { this.advance(); };

                while (this.expect(TokenType.LEFT_BRACKET))
                {
                    this.skip_brackets();
                };

                while (this.expect(TokenType.MULTIPLY)) { this.advance(); };

                if (this.expect(TokenType.AS))
                {
                    this.advance();
                    if (this.expect(TokenType.VOID))
                    {
                        r = false;
                    }
                    else
                    {
                        r = this.expect(TokenType.IDENTIFIER);
                    };
                    done = true;
                };

                if (!done)
                {
                    if (this.expect(TokenType.IDENTIFIER))
                    {
                        this.advance();
                        r = this.expect4(TokenType.ASSIGN, TokenType.SEMICOLON, TokenType.LEFT_PAREN, TokenType.LEFT_BRACE)
                          | this.expect4(TokenType.COMMA, TokenType.LEFT_BRACKET, TokenType.FROM, TokenType.ADDRESS_ASSIGN);
                    };
                };

                this.reset(m);
                return r;
            };

            // success_type ^| error_type success_name, error_name = call();
            def is_dual_assign_declaration() -> bool
            {
                int m = this.mark();
                bool r = false;

                if (this.expect(TokenType.CONST)) { this.advance(); };
                if (this.expect(TokenType.VOLATILE)) { this.advance(); };
                if (this.expect2(TokenType.SIGNED, TokenType.UNSIGNED)) { this.advance(); };

                if (!this.is_base_type_token())
                {
                    this.reset(m);
                    return false;
                };
                this.advance();

                while (this.expect(TokenType.SCOPE))
                {
                    this.advance();
                    if (this.expect(TokenType.IDENTIFIER))
                    {
                        this.advance();
                    }
                    else
                    {
                        break;
                    };
                };

                if (this.expect(TokenType.LESS_THAN)) { this.skip_template_args(); };

                if (this.expect(TokenType.LEFT_BRACE))
                {
                    this.advance();
                    if (this.expect(TokenType.SINT_LITERAL)) { this.advance(); };
                    if (this.expect2(TokenType.COLON, TokenType.SCOPE))
                    {
                        this.advance();
                        if (this.expect(TokenType.SINT_LITERAL)) { this.advance(); };
                    };
                    if (this.expect(TokenType.RIGHT_BRACE)) { this.advance(); };
                };

                while (this.expect(TokenType.MULTIPLY)) { this.advance(); };

                while (this.expect(TokenType.LEFT_BRACKET))
                {
                    this.skip_brackets();
                };

                r = this.expect(TokenType.XOR_OP);
                this.reset(m);
                return r;
            };

            // Tokens that can start the receiver of a type function definition
            def is_type_func_receiver(int t) -> bool
            {
                return t == TokenType.BYTE | t == TokenType.SINT | t == TokenType.UINT | t == TokenType.SLONG
                     | t == TokenType.ULONG | t == TokenType.FLOAT_KW | t == TokenType.DOUBLE_KW | t == TokenType.BOOL_KW
                     | t == TokenType.TRUE | t == TokenType.FALSE | t == TokenType.SINT_LITERAL | t == TokenType.UINT_LITERAL
                     | t == TokenType.SLONG_LITERAL | t == TokenType.ULONG_LITERAL | t == TokenType.FLOAT | t == TokenType.DOUBLE
                     | t == TokenType.CHAR | t == TokenType.STRING_LITERAL | t == TokenType.F_STRING | t == TokenType.I_STRING;
            };

            // RECEIVER.func_name([params]) -> return_type
            def is_type_func_def() -> bool
            {
                int m = this.mark();
                int depth, depth_t;
                int t;
                bool r = false;
                bool ok = true;

                if (this.expect(TokenType.TIE)) { this.advance(); };
                t = this.cur();
                if (this.is_type_func_receiver(t))
                {
                    this.advance();
                }
                elif (t == TokenType.IDENTIFIER)
                {
                    this.advance();
                }
                else
                {
                    this.reset(m);
                    return false;
                };

                while (this.expect(TokenType.MULTIPLY)) { this.advance(); };

                if (this.expect(TokenType.LEFT_BRACKET))
                {
                    this.advance();
                    if (!this.expect(TokenType.RIGHT_BRACKET)) { ok = false; };
                    if (ok) { this.advance(); };
                };

                if (ok)
                {
                    if (!this.expect(TokenType.DOT)) { ok = false; };
                };
                if (ok)
                {
                    this.advance();
                    if (!this.expect4(TokenType.IDENTIFIER, TokenType.STRING_LITERAL, TokenType.F_STRING, TokenType.I_STRING)) { ok = false; };
                };
                if (ok)
                {
                    this.advance();
                    if (this.expect2(TokenType.LESS_THAN, TokenType.RECURSE_ARROW))
                    {
                        this.advance();
                        depth_t = 1;
                        while (depth_t > 0 & !this.expect(TokenType.EOF))
                        {
                            if (this.expect2(TokenType.LESS_THAN, TokenType.RECURSE_ARROW))
                            {
                                depth_t++;
                            }
                            elif (this.expect(TokenType.GREATER_THAN))
                            {
                                depth_t--;
                                if (depth_t == 0) { break; };
                            };
                            this.advance();
                        };
                        if (!this.expect(TokenType.GREATER_THAN))
                        {
                            ok = false;
                        }
                        else
                        {
                            this.advance();
                        };
                    };
                };
                if (ok)
                {
                    if (!this.expect(TokenType.LEFT_PAREN)) { ok = false; };
                };
                if (ok)
                {
                    this.advance();
                    depth = 1;
                    while (depth > 0 & !this.expect(TokenType.EOF))
                    {
                        if (this.expect(TokenType.LEFT_PAREN))
                        {
                            depth++;
                        }
                        elif (this.expect(TokenType.RIGHT_PAREN))
                        {
                            depth--;
                            if (depth == 0) { break; };
                        };
                        this.advance();
                    };
                    if (!this.expect(TokenType.RIGHT_PAREN)) { ok = false; };
                };
                if (ok)
                {
                    this.advance();
                    r = this.expect(TokenType.RETURN_ARROW);
                };

                this.reset(m);
                return r;
            };

            // ===== GRAMMAR RULES (STUBS) =====

            // macro_def -> 'macro' IDENTIFIER '(' (IDENTIFIER (',' IDENTIFIER)*)? ')' '{' expression ';'? '}' ';'
            // The name is registered before the body is parsed so a recursive call in the body
            // becomes a MACRO_CALL. The ';' inside the braces is a terminator, not part of the body.
            def macro_def() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* s = this.mk(NodeKind.MACRO_DEF_STATEMENT, line, col);
                if (this.failed) { return s; };
                Node* d = this.mk(NodeKind.MACRO_DEF, line, col);
                if (this.failed)
                {
                    node_free(s);
                    return d;
                };
                s.a = d;
                Node* p;
                bool more;
                this.advance();
                d.text = this.ident();
                if (this.failed) { return this.done(s); };
                if (!this.consume(TokenType.LEFT_PAREN)) { return this.done(s); };
                if (!this.expect(TokenType.RIGHT_PAREN))
                {
                    more = true;
                    while (more & !this.failed)
                    {
                        p = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                        if (this.failed) { break; };
                        node_push(d, 0, p);
                        p.text = this.ident();
                        if (this.failed) { break; };
                        more = this.expect(TokenType.COMMA);
                        if (more) { this.advance(); };
                    };
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (this.failed) { return this.done(s); };
                nm_put(this.macros, d.text, (void*)this.macros);
                if (!this.consume(TokenType.LEFT_BRACE)) { return this.done(s); };
                d.a = this.expression();
                if (this.failed) { return this.done(s); };
                if (this.expect(TokenType.SEMICOLON)) { this.advance(); };
                if (!this.consume(TokenType.RIGHT_BRACE)) { return this.done(s); };
                this.consume(TokenType.SEMICOLON);
                return this.done(s);
            };

            // effect_def -> 'effect' IDENTIFIER ('.' IDENTIFIER)* '{' effect_expr '}' ';'
            def effect_def() -> Node*
            {
                Node* n = this.mk(NodeKind.EFFECT_DEF, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                byte* sub;
                this.advance();
                byte* name = this.ident();
                if (this.failed) { return this.done(n); };
                while (this.expect(TokenType.DOT))
                {
                    this.advance();
                    sub = this.ident();
                    if (this.failed) { break; };
                    name = this.cat2(this.cat2(name, g".\0"), sub);
                };
                if (!this.failed) { this.consume(TokenType.LEFT_BRACE); };
                if (!this.failed) { n.a = this.effect_expr(); };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                n.text = name;
                return this.done(n);
            };

            // Error text of the form "<msg> [line:col]" at the current token (fparser.py raises SyntaxError)
            def interface_error(byte* head, byte* name, byte* tail) -> void
            {
                this.sb.len = 0;
                this.sb.put_str(head);
                if (name != (byte*)0)
                {
                    this.sb.put_str(name);
                    this.sb.put_str(g"' must have a trait constraint (e.g. \0");
                    this.sb.put_str(name);
                    this.sb.put_str(tail);
                }
                else
                {
                    this.sb.put_str(tail);
                };
                this.sb.put_str(g" [\0");
                this.sb.put_int(this.cur_line());
                this.sb.put(':');
                this.sb.put_int(this.cur_col());
                this.sb.put(']');
                this.error(this.own_n(this.sb.mem, this.sb.len));
                return;
            };

            // '{' prototype (',' prototype)* '}'  with  prototype -> IDENTIFIER '(' (type IDENTIFIER (',' type IDENTIFIER)*)? ')' '->' type
            // Each prototype is a FUNCTION_DEF flagged NF_PROTOTYPE with an empty body, pushed to holder.l0.
            def interface_protos(Node* holder) -> void
            {
                int pl, pc;
                Node* f;
                Node* prm;
                bool more;
                if (!this.consume(TokenType.LEFT_BRACE)) { return; };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    pl = this.cur_line();
                    pc = this.cur_col();
                    f = this.mk(NodeKind.FUNCTION_DEF, pl, pc);
                    if (this.failed) { return; };
                    node_push(holder, 0, f);
                    f.text = this.ident();
                    if (!this.failed) { this.consume(TokenType.LEFT_PAREN); };
                    if (!this.failed & !this.expect(TokenType.RIGHT_PAREN))
                    {
                        more = true;
                        while (more & !this.failed)
                        {
                            prm = this.mk(NodeKind.PARAMETER, pl, pc);
                            if (this.failed) { break; };
                            node_push(f, 0, prm);
                            prm.ts = this.type_spec();
                            if (this.failed) { break; };
                            prm.text = this.ident();
                            if (this.failed) { break; };
                            more = this.expect(TokenType.COMMA);
                            if (more) { this.advance(); };
                        };
                    };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                    if (!this.failed) { this.consume(TokenType.RETURN_ARROW); };
                    if (!this.failed) { f.ts = this.type_spec(); };
                    if (this.failed) { return; };
                    this.mark_proto(f);
                    if (this.failed) { return; };
                    if (this.expect(TokenType.COMMA)) { this.advance(); }
                    else { break; };
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                return;
            };

            // interface_def -> 'interface' IDENTIFIER '(' (IDENTIFIER ':' IDENTIFIER (',' ...)*)? ')'
            //                  '{' (protocol ';')* '}' ('#' ('effect' | 'attenuate') '{' effect_expr '}')* ';'
            //   protocol -> IDENTIFIER ':' IDENTIFIER protos      A : B   CALL_ON
            //             | IDENTIFIER '(' IDENTIFIER ')' protos  B(A)    PASS_INTO (caller A, callee B)
            //             | IDENTIFIER '->' IDENTIFIER protos     A -> B  RETURN_TO
            def interface_def() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.INTERFACE_DEF, line, col);
                if (this.failed) { return n; };
                Node* p;
                Node* pr;
                byte* first;
                bool more;
                this.advance();
                n.text = this.ident();
                if (!this.failed) { this.consume(TokenType.LEFT_PAREN); };
                if (!this.failed & !this.expect(TokenType.RIGHT_PAREN))
                {
                    more = true;
                    while (more & !this.failed)
                    {
                        p = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                        if (this.failed) { break; };
                        node_push(n, 0, p);
                        p.text = this.ident();
                        if (this.failed) { break; };
                        if (!this.expect(TokenType.COLON))
                        {
                            this.interface_error(g"Interface parameter '\0", p.text, g": SomeTrait)\0");
                            break;
                        };
                        this.advance();
                        p.text2 = this.ident();
                        if (this.failed) { break; };
                        more = this.expect(TokenType.COMMA);
                        if (more) { this.advance(); };
                    };
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (!this.failed) { this.consume(TokenType.LEFT_BRACE); };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    pr = this.mk(NodeKind.INTERFACE_PROTOCOL, line, col);
                    if (this.failed) { break; };
                    node_push(n, 1, pr);
                    first = this.ident();
                    if (this.failed) { break; };
                    if (this.expect(TokenType.COLON))
                    {
                        this.advance();
                        pr.text = first;
                        pr.text2 = this.ident();
                        pr.op = ProtocolKind.CALL_ON;
                    }
                    elif (this.expect(TokenType.LEFT_PAREN))
                    {
                        this.advance();
                        pr.text = this.ident();
                        if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                        pr.text2 = first;
                        pr.op = ProtocolKind.PASS_INTO;
                    }
                    elif (this.expect(TokenType.RETURN_ARROW))
                    {
                        this.advance();
                        pr.text = first;
                        pr.text2 = this.ident();
                        pr.op = ProtocolKind.RETURN_TO;
                    }
                    else
                    {
                        this.interface_error(g"Expected ':', '(' or '->' in interface protocol block\0", (byte*)0, g"\0");
                        break;
                    };
                    if (this.failed) { break; };
                    this.interface_protos(pr);
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                while (!this.failed & this.expect(TokenType.TAG))
                {
                    this.advance();
                    if (this.expect(TokenType.EFFECT))
                    {
                        node_free(n.b);
                        n.b = this.effect_annotation(NodeKind.EFFECT_ANNOTATION);
                    }
                    elif (this.expect(TokenType.IDENTIFIER) & this.val_is(g"attenuate\0", 9))
                    {
                        node_free(n.a);
                        n.a = this.effect_annotation(NodeKind.ATTENUATE_ANNOTATION);
                    }
                    else
                    {
                        this.error(g"Expected 'effect' or 'attenuate' after '#' in interface definition\0");
                    };
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // deprecate_statement -> 'deprecate' IDENTIFIER ('::' IDENTIFIER)* ';'
            // The path keeps "::" separators, as in fparser.py.
            def deprecate_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.DEPRECATE_STATEMENT, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.advance();
                byte* path = this.ident();
                byte* part;
                while (!this.failed & this.expect(TokenType.SCOPE))
                {
                    this.advance();
                    part = this.ident();
                    if (this.failed) { break; };
                    path = this.cat2(this.cat2(path, g"::\0"), part);
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                n.text = path;
                return this.done(n);
            };

            // ----- templates: registry and parameter lists -----

            // Active template parameter names while a template definition is parsed
            def tp_active(byte* name) -> bool
            {
                if (this.active_tp == (NameMap*)0) { return false; };
                return nm_has(this.active_tp, name);
            };

            def tp_activate(TemplateEntry* e) -> void
            {
                NameMap* a = nm_new();
                int i;
                while (i < e.params.len)
                {
                    nm_put(a, (byte*)e.params.items[i], (void*)a);
                    i++;
                };
                this.active_tp = a;
                return;
            };

            // IDENTIFIER, or a codify splice when allowed
            def tp_id(bool cg) -> byte*
            {
                if (cg & this.expect(TokenType.CODIFY)) { return this.consume_codify(); };
                return this.ident();
            };

            // names joined by '&'
            def tp_idlist(bool cg) -> PtrVec*
            {
                PtrVec* v = pv_new();
                pv_push(v, (void*)this.tp_id(cg));
                while (!this.failed & this.expect(TokenType.LOGICAL_AND))
                {
                    this.advance();
                    pv_push(v, (void*)this.tp_id(cg));
                };
                return v;
            };

            // Source-like text of a type for constraint messages (fparser._ts_repr_simple)
            def tp_repr(TypeSpec* t) -> byte*
            {
                int i;
                this.sb.len = 0;
                if (t.custom_typename != (byte*)0) { this.sb.put_str(t.custom_typename); }
                else { this.sb.put_str(datatype_text(t.base_type)); };
                if (ts_is_pointer(t))
                {
                    while (i < t.pointer_depth)
                    {
                        this.sb.put('*');
                        i++;
                    };
                };
                if (ts_is_array(t)) { this.sb.put_str(g"[]\0"); };
                return this.own_n(this.sb.mem, this.sb.len);
            };

            // Name mapped through the zip of from and to (the last duplicate wins)
            def tp_map_name(PtrVec* fnames, PtrVec* to, byte* n) -> byte*
            {
                int i = fnames.len;
                if (to.len < i) { i = to.len; };
                while (i > 0)
                {
                    i--;
                    if (cstr_eq((byte*)fnames.items[i], n)) { return (byte*)to.items[i]; };
                };
                return n;
            };

            // Copies the relations of constra set cs into e, mapping its formals onto to
            def tp_copy_rels(TemplateEntry* e, Node* cs, PtrVec* to) -> void
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
                return;
            };

            def tp_has_param(TemplateEntry* e, byte* n) -> bool
            {
                int i;
                while (i < e.params.len)
                {
                    if (cstr_eq((byte*)e.params.items[i], n)) { return true; };
                    i++;
                };
                return false;
            };

            // One entry of ':{ ... }': a named constra (with or without arguments) or a raw relation
            def tp_cs_entry(TemplateEntry* e, bool cg) -> void
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
                if (cg & this.expect(TokenType.CODIFY))
                {
                    name = this.consume_codify();
                    codify = true;
                }
                else
                {
                    name = this.ident();
                };
                if (this.failed) { return; };
                if (!codify & this.expect(TokenType.LEFT_PAREN))
                {
                    if (!nm_has(this.constras, name))
                    {
                        this.sb.len = 0;
                        this.sb.put_str(g"Unknown named constraint set '\0");
                        this.sb.put_str(name);
                        this.sb.put('\'');
                        this.cs_error_at(m);
                        return;
                    };
                    csd = (Node*)nm_get(this.constras, name);
                    this.advance();
                    args = pv_new();
                    if (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        pv_push(args, (void*)this.ident());
                        while (!this.failed & this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            pv_push(args, (void*)this.ident());
                        };
                    };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                    if (this.failed)
                    {
                        pv_free(args);
                        return;
                    };
                    if (args.len != node_count(csd, 0))
                    {
                        this.sb.len = 0;
                        this.sb.put_str(g"Named constraint set '\0");
                        this.sb.put_str(name);
                        this.sb.put_str(g"' expects \0");
                        this.sb.put_int(node_count(csd, 0));
                        this.sb.put_str(g" argument(s), got \0");
                        this.sb.put_int(args.len);
                        this.cs_error_at(m);
                        pv_free(args);
                        return;
                    };
                    i = 0;
                    while (i < args.len)
                    {
                        if (!this.tp_has_param(e, (byte*)args.items[i]))
                        {
                            this.sb.len = 0;
                            this.sb.put('\'');
                            this.sb.put_str((byte*)args.items[i]);
                            this.sb.put_str(g"' is not a template parameter; valid parameters are: \0");
                            this.tp_put_params(e);
                            this.error(this.own_n(this.sb.mem, this.sb.len));
                            pv_free(args);
                            return;
                        };
                        i++;
                    };
                    this.tp_copy_rels(e, csd, args);
                    pv_free(args);
                    return;
                };
                if (!codify & nm_has(this.constras, name) & !(this.expect(TokenType.LOGICAL_AND) | this.is_relop()))
                {
                    csd = (Node*)nm_get(this.constras, name);
                    if (e.params.len != node_count(csd, 0))
                    {
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
                        return;
                    };
                    this.tp_copy_rels(e, csd, e.params);
                    return;
                };
                lhs = pv_new();
                pv_push(lhs, (void*)name);
                while (!this.failed & this.expect(TokenType.LOGICAL_AND))
                {
                    this.advance();
                    pv_push(lhs, (void*)this.tp_id(cg));
                };
                if (!this.failed)
                {
                    op = this.consume_relop();
                    if (!this.failed)
                    {
                        rhs = this.tp_idlist(cg);
                        if (!this.failed) { this.cs_emit(e.rels, lhs, op, rhs, line, col); };
                        pv_free(rhs);
                    };
                };
                pv_free(lhs);
                return;
            };

            // Template parameter names joined with ", " into sb
            def tp_put_params(TemplateEntry* e) -> void
            {
                int i;
                while (i < e.params.len)
                {
                    if (i > 0) { this.sb.put_str(g", \0"); };
                    this.sb.put_str((byte*)e.params.items[i]);
                    i++;
                };
                return;
            };

            // ':' '{' entry (',' entry)* '}'
            def tp_constraint_set(TemplateEntry* e, bool cg) -> void
            {
                this.consume(TokenType.COLON);
                if (!this.failed) { this.consume(TokenType.LEFT_BRACE); };
                if (!this.failed) { this.tp_cs_entry(e, cg); };
                while (!this.failed & this.expect(TokenType.COMMA))
                {
                    this.advance();
                    this.tp_cs_entry(e, cg);
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                return;
            };

            // name (':' ['+'] type ('|' ['+'] type)*)?
            def tp_param_entry(TemplateEntry* e, byte* name) -> void
            {
                pv_push(e.params, (void*)name);
                if (!this.expect(TokenType.COLON)) { return; };
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
                    if (is_def)
                    {
                        if (dm < 0) { dm = this.mark(); };
                        this.advance();
                        saw_default = true;
                    };
                    src = (byte*)0;
                    if (this.expect(TokenType.STRING_LITERAL)) { src = g"\"\"\0"; };
                    ts = this.type_spec();
                    if (this.failed)
                    {
                        if (ts != (TypeSpec*)0) { typespec_free(ts); };
                        return;
                    };
                    if (src == (byte*)0) { src = this.tp_repr(ts); };
                    pv_push(e.cparam, (void*)name);
                    pv_push(e.cts, (void*)ts);
                    pv_push(e.ctext, (void*)src);
                    if (is_def) { dts = ts; };
                    more = this.expect(TokenType.LOGICAL_OR);
                    if (more) { this.advance(); };
                };
                if (this.failed | !saw_default) { return; };
                if (nm_has(e.no_default, name))
                {
                    this.reset(dm);
                    this.sb.len = 0;
                    this.sb.put_str(g"Template parameter '\0");
                    this.sb.put_str(name);
                    this.sb.put_str(g"' is marked '!+' (no default) but a default type was supplied with '+'\0");
                    this.error(this.own_n(this.sb.mem, this.sb.len));
                    return;
                };
                pv_push(e.dparam, (void*)name);
                pv_push(e.dts, (void*)typespec_copy(dts));
                return;
            };

            // The relational-constraint-in-the-wrong-place error of a parameter list
            def tp_rel_misplaced(byte* id, bool first) -> void
            {
                this.sb.len = 0;
                this.sb.put_str(g"Relational template constraints must be wrapped in a constraint set\0");
                if (first) { this.sb.put_str(g" as :{T ~= U}. Did you mean :{\0"); }
                else { this.sb.put_str(g": :{T ~= U}. Did you mean :{\0"); };
                this.sb.put_str(id);
                this.sb.put_str(g" ~= ...}, or did you intend a type constraint \0");
                this.sb.put_str(id);
                this.sb.put_str(g": ?\0");
                this.error(this.own_n(this.sb.mem, this.sb.len));
                return;
            };

            // One list entry after the cursor: ':{...}' or ['!+'] name constraint
            def tp_entry(TemplateEntry* e, bool cg, bool first) -> void
            {
                bool nd = false;
                byte* id;
                if (this.expect(TokenType.COLON))
                {
                    this.tp_constraint_set(e, cg);
                    return;
                };
                if (this.expect(TokenType.NOT))
                {
                    this.advance();
                    this.consume(TokenType.PLUS);
                    nd = true;
                };
                if (this.failed) { return; };
                id = this.tp_id(cg);
                if (this.failed) { return; };
                if (nd) { nm_put(e.no_default, id, (void*)e); };
                if (this.expect(TokenType.LOGICAL_AND) | this.is_relop())
                {
                    this.tp_rel_misplaced(id, first);
                    return;
                };
                this.tp_param_entry(e, id);
                return;
            };

            // '<' entries '>' (cursor on '<'). Returns a new entry without a node, or null on error.
            def template_params(bool cg) -> TemplateEntry*
            {
                TemplateEntry* e = te_new();
                this.advance();
                this.tp_entry(e, cg, true);
                while (!this.failed & this.expect(TokenType.COMMA))
                {
                    this.advance();
                    this.tp_entry(e, cg, false);
                };
                if (!this.failed) { this.consume(TokenType.GREATER_THAN); };
                if (this.failed)
                {
                    te_free(e);
                    return (TemplateEntry*)0;
                };
                return e;
            };

            def template_lookup(byte* name) -> TemplateEntry*
            {
                if (name == (byte*)0) { return (TemplateEntry*)0; };
                if (!nm_has(this.templates, name)) { return (TemplateEntry*)0; };
                return (TemplateEntry*)nm_get(this.templates, name);
            };

            def template_alias(byte* alias, byte* original) -> void
            {
                if (!nm_has(this.templates, original)) { return; };
                nm_put(this.templates, this.own(ts_dup(alias)), nm_get(this.templates, original));
                return;
            };

            // Registers e (parsed parameters) with its template node under name.
            // Mirrors TemplateRegistry.register: an entry of the same kind is updated in place.
            def register_template(byte* name, int kind, TemplateEntry* e, Node* node) -> void
            {
                TemplateEntry* ex = this.template_lookup(name);
                PtrVec* tv;
                Node* tn;
                NameMap* tm;
                int i;
                if (ex != (TemplateEntry*)0 & ex.kind == kind)
                {
                    tv = ex.params; ex.params = e.params; e.params = tv;
                    tn = ex.node; ex.node = node; node_free(tn);
                    if (e.cparam.len > 0)
                    {
                        tv = ex.cparam; ex.cparam = e.cparam; e.cparam = tv;
                        tv = ex.cts; ex.cts = e.cts; e.cts = tv;
                        tv = ex.ctext; ex.ctext = e.ctext; e.ctext = tv;
                    };
                    if (node_count(e.rels, 1) > 0)
                    {
                        tn = ex.rels; ex.rels = e.rels; e.rels = tn;
                    };
                    if (e.dparam.len > 0)
                    {
                        tv = ex.dparam; ex.dparam = e.dparam; e.dparam = tv;
                        tv = ex.dts; ex.dts = e.dts; e.dts = tv;
                    };
                    if (e.no_default.count > 0)
                    {
                        tm = ex.no_default; ex.no_default = e.no_default; e.no_default = tm;
                    };
                    te_free(e);
                    return;
                };
                e.kind = kind;
                e.node = node;
                nm_put(this.templates, this.own(ts_dup(name)), (void*)e);
                pv_push(this.tentries, (void*)e);
                return;
            };

            // ----- templates: instantiation -----

            // Records an error at an explicit position
            def error_at(byte* msg, int line, int col) -> void
            {
                if (this.failed) { return; };
                this.failed = true;
                this.err_kind = ParseErr.MESSAGE;
                this.err_msg = msg;
                this.err_line = line;
                this.err_col = col;
                return;
            };

            // The shared checker used for template constraints (created on first use)
            def chk_get() -> Checker*
            {
                if (this.chk == (Checker*)0)
                {
                    this.chk = (Checker*)fmalloc((u64)((sizeof(Checker) + 7) / 8));
                    this.chk.__init(this.st);
                };
                return this.chk;
            };

            // Reports the diagnostic number first (and later ones are ignored) as the parse error
            def chk_fail(int first) -> void
            {
                Diag* d = (Diag*)this.chk.diags.items[first];
                this.error_at(this.own(ts_dup(d.msg)), d.line, d.col);
                return;
            };

            // Short identifying text of a type for name mangling (fparser._type_system_to_mangle_str)
            def ts_mangle(TypeSpec* t) -> byte*
            {
                TypeSpec* inner;
                byte* s;
                if (t.custom_typename != (byte*)0) { return t.custom_typename; };
                if (ts_is_pointer(t))
                {
                    inner = typespec_new();
                    inner.base_type = t.base_type;
                    inner.bit_width = t.bit_width;
                    inner.flags = TS_SIGNED;
                    s = this.ts_mangle(inner);
                    typespec_free(inner);
                    return this.cat2(g"ptr_\0", s);
                };
                if (t.base_type == DataType.DATA & t.bit_width > 0)
                {
                    this.sb.len = 0;
                    this.sb.put_str(g"data_\0");
                    if (ts_is_signed(t)) { this.sb.put('i'); }
                    else { this.sb.put('u'); };
                    this.sb.put_int(t.bit_width);
                    return this.own_n(this.sb.mem, this.sb.len);
                };
                return datatype_text(t.base_type);
            };

            // A TypeSpec owned by the parser until it exits
            def tmp_type() -> TypeSpec*
            {
                TypeSpec* t = typespec_new();
                pv_push(this.tmp_ts, (void*)t);
                return t;
            };

            // Parameter name to TypeSpec* mapping (fparser._build_template_mapping)
            def tp_mapping(TemplateEntry* te, PtrVec* names, PtrVec* specs) -> NameMap*
            {
                NameMap* m = nm_new();
                int i, k;
                TypeSpec* r;
                byte* tn;
                while (i < te.params.len & i < names.len)
                {
                    tn = (byte*)names.items[i];
                    r = (TypeSpec*)0;
                    if (specs != (PtrVec*)0)
                    {
                        if (i < specs.len) { r = (TypeSpec*)specs.items[i]; };
                    };
                    if (r == (TypeSpec*)0 & this.st != (FXC_SYMTABLE*)0) { r = st_get_type_spec(this.st, tn); };
                    k = 0;
                    while (r == (TypeSpec*)0 & k < 18)
                    {
                        if (cstr_eq(datatype_text(k), tn))
                        {
                            r = this.tmp_type();
                            r.base_type = k;
                            if (k == DataType.SINT | k == DataType.CHAR) { r.flags = TS_SIGNED; };
                        };
                        k++;
                    };
                    if (r == (TypeSpec*)0)
                    {
                        r = this.tmp_type();
                        r.base_type = DataType.DATA;
                        r.custom_typename = tn;
                    };
                    nm_put(m, (byte*)te.params.items[i], (void*)r);
                    i++;
                };
                return m;
            };

            // Substitutes template parameters in t. Frees t and returns the replacement
            // (fparser._substitute_type).
            def subst_ts(TypeSpec* t, NameMap* map) -> TypeSpec*
            {
                TypeSpec* r;
                if (t == (TypeSpec*)0) { return t; };
                if (t.base_type == DataType.DICT)
                {
                    t.dict_key = this.subst_ts(t.dict_key, map);
                    t.dict_value = this.subst_ts(t.dict_value, map);
                    return t;
                };
                if (t.custom_typename == (byte*)0) { return t; };
                if (!nm_has(map, t.custom_typename))
                {
                    t.custom_typename = this.subst_deferred_type(t.custom_typename, map);
                    return t;
                };
                r = typespec_copy((TypeSpec*)nm_get(map, t.custom_typename));
                if (ts_is_pointer(t))
                {
                    r.flags = r.flags `| TS_POINTER;
                    r.pointer_depth = r.pointer_depth + t.pointer_depth;
                };
                if (ts_is_array(t))
                {
                    r.flags = r.flags `| TS_ARRAY;
                    r.array_dims = nv_clone(t.array_dims);
                    if (r.array_dims != (NodeVec*)0)
                    {
                        if (r.array_dims.len > 0) { r.array_size = r.array_dims.items[0]; };
                    }
                    else
                    {
                        r.array_size = node_clone(t.array_size);
                    };
                };
                if ((t.flags `& TS_CONST) != 0) { r.flags = r.flags `| TS_CONST; };
                if ((t.flags `& TS_VOLATILE) != 0) { r.flags = r.flags `| TS_VOLATILE; };
                typespec_free(t);
                return r;
            };

            // Splits the arguments of a deferred "name<a,b>" text. Returns the byte index of '<' or -1.
            def tp_split_deferred(byte* s, PtrVec* out) -> int
            {
                int i, lt, start, e;
                int n = pp_cstrlen(s);
                lt = -1;
                while (i < n & lt < 0)
                {
                    if (s[i] == '<') { lt = i; };
                    i++;
                };
                if (lt < 0) { return -1; };
                if (s[n - 1] != '>') { return -1; };
                start = lt + 1;
                i = start;
                while (i <= n - 1)
                {
                    if (i == n - 1 | s[i] == ',')
                    {
                        e = i;
                        while (start < e & s[start] == ' ') { start++; };
                        while (e > start & s[e - 1] == ' ') { e--; };
                        pv_push(out, (void*)this.own_n(s + start, e - start));
                        start = i + 1;
                    };
                    i++;
                };
                return lt;
            };

            // Rewrites a deferred call "f<T,U>" whose arguments are now known (fparser._substitute_node)
            def subst_deferred_call(Node* n, NameMap* map) -> void
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
                if (lt > 0)
                {
                    base = this.own_n(n.text, lt);
                    fe = this.template_lookup(base);
                    while (i < raw.len)
                    {
                        if (nm_has(map, (byte*)raw.items[i])) { any = true; };
                        i++;
                    };
                    if (fe != (TemplateEntry*)0 & any & fe.kind == 0)
                    {
                        i = 0;
                        while (i < raw.len)
                        {
                            a = (byte*)raw.items[i];
                            if (nm_has(map, a))
                            {
                                c = (TypeSpec*)nm_get(map, a);
                                pv_push(names, (void*)this.ts_mangle(c));
                                pv_push(specs, (void*)c);
                            }
                            else
                            {
                                c = this.tmp_type();
                                c.base_type = DataType.DATA;
                                c.custom_typename = a;
                                pv_push(names, (void*)a);
                                pv_push(specs, (void*)c);
                            };
                            i++;
                        };
                        n.text = this.resolve_template_call(base, names, specs, (PtrVec*)0);
                    };
                };
                pv_free(raw);
                pv_free(names);
                pv_free(specs);
                return;
            };

            // Deep substitution over a cloned template tree (fparser._substitute_node)
            def subst_node(Node* n, NameMap* map) -> void
            {
                int s, i, c;
                if (n == (Node*)0 | this.failed) { return; };
                n.ts = this.subst_ts(n.ts, map);
                n.ts2 = this.subst_ts(n.ts2, map);
                if (n.kind == NodeKind.SIZE_OF | n.kind == NodeKind.ALIGN_OF | n.kind == NodeKind.ENDIAN_OF)
                {
                    if (n.a != (Node*)0 & n.ts == (TypeSpec*)0)
                    {
                        if (n.a.kind == NodeKind.IDENTIFIER)
                        {
                            if (nm_has(map, n.a.text))
                            {
                                n.ts = typespec_copy((TypeSpec*)nm_get(map, n.a.text));
                                node_free(n.a);
                                n.a = (Node*)0;
                            };
                        };
                    };
                };
                if (n.kind == NodeKind.FUNCTION_CALL & n.text != (byte*)0)
                {
                    this.subst_deferred_call(n, map);
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
                return;
            };

            // The registry entry holding the constraints for fname: the entry itself, or the
            // entry of the bare name when fname is namespace qualified (name__bare).
            def tp_constraint_entry(byte* fname, TemplateEntry* te, bool want_rels) -> TemplateEntry*
            {
                int i, ln, lk, k;
                bool found;
                bool suffix;
                TemplateEntry* ce;
                byte* key;
                if (want_rels) { found = node_count(te.rels, 1) > 0; } else { found = te.cparam.len > 0; };
                if (found) { return te; };
                ln = pp_cstrlen(fname);
                while (i < this.templates.count)
                {
                    key = this.templates.keys[i];
                    ce = (TemplateEntry*)this.templates.vals[i];
                    i++;
                    if (key == (byte*)0 | ce == (TemplateEntry*)0) { continue; };
                    lk = pp_cstrlen(key);
                    suffix = cstr_eq(fname, key);
                    if (!suffix & ln > lk + 2)
                    {
                        suffix = true;
                        k = 0;
                        while (k < lk)
                        {
                            if (fname[ln - lk + k] != key[k]) { suffix = false; };
                            k++;
                        };
                        if (fname[ln - lk - 1] != '_' | fname[ln - lk - 2] != '_') { suffix = false; };
                    };
                    if (!suffix) { continue; };
                    if (want_rels) { found = node_count(ce.rels, 1) > 0; } else { found = ce.cparam.len > 0; };
                    if (found) { return ce; };
                };
                return te;
            };

            // Allowed-type lists of every parameter against the concrete types
            def tp_check_allowed(byte* fname, TemplateEntry* ce, TemplateEntry* te, PtrVec* specs, PtrVec* poss) -> void
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
                        if (cstr_eq((byte*)ce.cparam.items[j], pname)) { cnt++; };
                        j++;
                    };
                    concrete = (TypeSpec*)0;
                    if (specs != (PtrVec*)0)
                    {
                        if (i < specs.len) { concrete = (TypeSpec*)specs.items[i]; };
                    };
                    if (cnt > 0 & concrete != (TypeSpec*)0)
                    {
                        allowed = (TypeSpec**)fmalloc((u64)cnt * (u64)((sizeof(TypeSpec*) + 7) / 8));
                        this.sb.len = 0;
                        cnt = 0;
                        j = 0;
                        while (j < ce.cparam.len)
                        {
                            if (cstr_eq((byte*)ce.cparam.items[j], pname))
                            {
                                allowed[cnt] = (TypeSpec*)ce.cts.items[j];
                                if (cnt > 0) { this.sb.put_str(g" | \0"); };
                                this.sb.put_str((byte*)ce.ctext.items[j]);
                                cnt++;
                            };
                            j++;
                        };
                        line = this.cur_line();
                        col = this.cur_col();
                        if (poss != (PtrVec*)0)
                        {
                            if (i < poss.len)
                            {
                                at = (Node*)poss.items[i];
                                if (at != (Node*)0)
                                {
                                    line = at.line;
                                    col = at.col;
                                };
                            };
                        };
                        k = this.chk_get();
                        first = k.diags.len;
                        if (!k.check_allowed(fname, pname, concrete, allowed, cnt, this.own_n(this.sb.mem, this.sb.len), line, col))
                        {
                            this.chk_fail(first);
                        };
                        ffree((byte*)allowed);
                    };
                    i++;
                };
                return;
            };

            // Instantiates the template function fname with the given concrete types and returns the
            // name to call (fparser._resolve_template_call). poss holds, per parameter, the argument
            // node the type came from (null entries or a null vector use the current token).
            def resolve_template_call(byte* fname, PtrVec* names, PtrVec* specs, PtrVec* poss) -> byte*
            {
                TemplateEntry* te = this.template_lookup(fname);
                TemplateEntry* ce;
                NameMap* map;
                Node* concrete;
                TypeSpec** argv;
                byte* mangled;
                int i, first;
                Checker* k;
                if (te == (TemplateEntry*)0)
                {
                    this.error(this.cat2(this.cat2(g"Unknown template function '\0", fname), g"'\0"));
                    return fname;
                };
                if (te.kind != 0)
                {
                    this.error(this.cat2(this.cat2(g"Unknown template function '\0", fname), g"'\0"));
                    return fname;
                };
                if (names.len != te.params.len)
                {
                    this.sb.len = 0;
                    this.sb.put_str(g"Template function '\0");
                    this.sb.put_str(fname);
                    this.sb.put_str(g"' expects \0");
                    this.sb.put_int(te.params.len);
                    this.sb.put_str(g" type argument(s), got \0");
                    this.sb.put_int(names.len);
                    this.error(this.own_n(this.sb.mem, this.sb.len));
                    return fname;
                };
                ce = this.tp_constraint_entry(fname, te, false);
                this.tp_check_allowed(fname, ce, te, specs, poss);
                if (this.failed) { return fname; };

                this.sb.len = 0;
                this.sb.put_str(fname);
                this.sb.put_str(g"__tmpl__\0");
                i = 0;
                while (i < names.len)
                {
                    if (i > 0) { this.sb.put_str(g"__\0"); };
                    this.sb.put_str((byte*)names.items[i]);
                    i++;
                };
                mangled = this.own_n(this.sb.mem, this.sb.len);
                if (nm_has(te.emitted, mangled)) { return fname; };
                nm_put(te.emitted, mangled, (void*)te);

                map = this.tp_mapping(te, names, specs);
                concrete = node_clone(te.node);
                this.subst_node(concrete, map);
                if (this.failed)
                {
                    nm_free(map);
                    node_free(concrete);
                    return fname;
                };

                ce = this.tp_constraint_entry(fname, te, true);
                if (node_count(ce.rels, 1) > 0)
                {
                    argv = (TypeSpec**)fmalloc((u64)te.params.len * (u64)((sizeof(TypeSpec*) + 7) / 8));
                    i = 0;
                    while (i < te.params.len)
                    {
                        argv[i] = (TypeSpec*)nm_get(map, (byte*)te.params.items[i]);
                        i++;
                    };
                    k = this.chk_get();
                    first = k.diags.len;
                    if (k.check_relations(te.params, argv, te.params.len, ce.rels.l1, te.node, concrete) > 0)
                    {
                        this.chk_fail(first);
                    };
                    ffree((byte*)argv);
                };
                nm_free(map);
                if (this.failed)
                {
                    node_free(concrete);
                    return fname;
                };
                concrete.text = fname;
                if ((concrete.flags `& NF_NO_MANGLE) != 0) { concrete.flags = concrete.flags - NF_NO_MANGLE; };
                pv_push(this.tinst_f, (void*)concrete);
                return fname;
            };

            // Called after every binary expression: instantiates a template operator registered for
            // the operator symbol when both operand types are known (fparser._try_instantiate_template_op)
            def try_template_op(Node* n) -> void
            {
                byte* key = operator_text(n.op);
                TemplateEntry* te = this.template_lookup(key);
                TypeSpec* lts;
                TypeSpec* rts;
                if (te == (TemplateEntry*)0) { return; };
                if (te.kind != 3) { return; };
                lts = this.infer_arg_type(n.a);
                if (lts == (TypeSpec*)0) { return; };
                rts = this.infer_arg_type(n.b);
                if (rts == (TypeSpec*)0) { return; };
                this.resolve_template_operator(key, te, lts, rts);
                return;
            };

            // Binds template parameter pn from the concrete operand type c (fparser._resolve_template_operator)
            def op_infer_param(TemplateEntry* te, NameMap* inferred, TypeSpec* decl, TypeSpec* c) -> void
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
                if (dn == (byte*)0) { return; };
                if (this.tp_has_param(te, dn))
                {
                    r = c;
                    if (ts_is_pointer(c) & ts_is_pointer(decl))
                    {
                        r = typespec_copy(c);
                        pv_push(this.tmp_ts, (void*)r);
                        cd = c.pointer_depth;
                        if (cd == 0) { cd = 1; };
                        dd = decl.pointer_depth;
                        if (dd == 0) { dd = 1; };
                        r.pointer_depth = cd - dd;
                        if (r.pointer_depth < 0) { r.pointer_depth = 0; };
                        if (r.pointer_depth == 0 & (r.flags `& TS_POINTER) != 0) { r.flags = r.flags - TS_POINTER; };
                    };
                    if (!nm_has(inferred, dn)) { nm_put(inferred, dn, (void*)r); };
                    return;
                };
                raw = pv_new();
                lt = this.tp_split_deferred(dn, raw);
                if (lt > 0)
                {
                    base = this.own_n(dn, lt);
                    cn = c.custom_typename;
                    bl = pp_cstrlen(base);
                    pre = false;
                    if (cn != (byte*)0)
                    {
                        pre = pp_cstrlen(cn) > bl + 2;
                        k = 0;
                        while (pre & k < bl)
                        {
                            if (cn[k] != base[k]) { pre = false; };
                            k++;
                        };
                        if (pre)
                        {
                            if (cn[bl] != '_' | cn[bl + 1] != '_') { pre = false; };
                        };
                    };
                    if (pre & raw.len == 1)
                    {
                        pname = (byte*)raw.items[0];
                        if (this.tp_has_param(te, pname) & !nm_has(inferred, pname))
                        {
                            rem = cn + bl + 2;
                            res = (TypeSpec*)0;
                            if (this.st != (FXC_SYMTABLE*)0) { res = st_get_type_spec(this.st, rem); };
                            k = 0;
                            while (res == (TypeSpec*)0 & k < 18)
                            {
                                if (cstr_eq(datatype_text(k), rem))
                                {
                                    res = this.tmp_type();
                                    res.base_type = k;
                                };
                                k++;
                            };
                            if (res == (TypeSpec*)0)
                            {
                                res = this.tmp_type();
                                res.base_type = DataType.DATA;
                                res.custom_typename = rem;
                            };
                            nm_put(inferred, pname, (void*)res);
                        };
                    };
                };
                pv_free(raw);
                return;
            };

            def op_is_non_builtin(TypeSpec* t) -> bool
            {
                if (t.custom_typename != (byte*)0) { return true; };
                if (t.base_type == DataType.STRUCT | t.base_type == DataType.OBJECT) { return true; };
                return ts_is_pointer(t);
            };

            def resolve_template_operator(byte* key, TemplateEntry* te, TypeSpec* lts, TypeSpec* rts) -> void
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
                if (f == (Node*)0) { return; };
                if (node_count(f, 0) != 2) { return; };
                specs = pv_new();
                names = pv_new();
                if (te.params.len != 2)
                {
                    inferred = nm_new();
                    i = 0;
                    while (i < 2)
                    {
                        c = lts;
                        if (i == 1) { c = rts; };
                        if (node_child(f, 0, i).ts != (TypeSpec*)0) { this.op_infer_param(te, inferred, node_child(f, 0, i).ts, c); };
                        i++;
                    };
                    i = 0;
                    while (i < te.params.len)
                    {
                        if (!nm_has(inferred, (byte*)te.params.items[i]))
                        {
                            nm_free(inferred);
                            pv_free(specs);
                            pv_free(names);
                            return;
                        };
                        pv_push(specs, nm_get(inferred, (byte*)te.params.items[i]));
                        i++;
                    };
                    nm_free(inferred);
                }
                else
                {
                    pv_push(specs, (void*)lts);
                    pv_push(specs, (void*)rts);
                };
                if (!this.op_is_non_builtin(lts) & !this.op_is_non_builtin(rts))
                {
                    pv_free(specs);
                    pv_free(names);
                    return;
                };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                this.sb.put_str(f.text);
                this.sb.put_str(g"__tmpl__\0");
                i = 0;
                while (i < specs.len)
                {
                    if (i > 0) { this.sb.put_str(g"__\0"); };
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
                if (nm_has(te.emitted, mangled))
                {
                    pv_free(specs);
                    pv_free(names);
                    return;
                };
                nm_put(te.emitted, mangled, (void*)te);
                map = this.tp_mapping(te, names, specs);
                pv_free(specs);
                pv_free(names);
                concrete = node_clone(f);
                this.subst_node(concrete, map);
                nm_free(map);
                if (this.failed)
                {
                    node_free(concrete);
                    return;
                };
                if ((concrete.flags `& NF_NO_MANGLE) != 0) { concrete.flags = concrete.flags - NF_NO_MANGLE; };
                pv_push(this.tinst_f, (void*)concrete);
                return;
            };

            // Type implied by one call argument: identifier (symbol table), literal or string
            def infer_arg_type(Node* arg) -> TypeSpec*
            {
                TypeSpec* t;
                int dt;
                if (arg.kind == NodeKind.IDENTIFIER)
                {
                    if (this.st == (FXC_SYMTABLE*)0) { return (TypeSpec*)0; };
                    return st_get_type_spec(this.st, arg.text);
                };
                if (arg.kind == NodeKind.LITERAL)
                {
                    dt = arg.op;
                    if (dt == DataType.SINT | dt == DataType.UINT | dt == DataType.SLONG | dt == DataType.ULONG |
                        dt == DataType.FLOAT | dt == DataType.DOUBLE | dt == DataType.CHAR | dt == DataType.BOOL |
                        dt == DataType.BYTE)
                    {
                        t = this.tmp_type();
                        t.base_type = dt;
                        if (dt == DataType.SINT | dt == DataType.SLONG | dt == DataType.CHAR) { t.flags = TS_SIGNED; };
                        return t;
                    };
                    return (TypeSpec*)0;
                };
                if (arg.kind == NodeKind.STRING_LITERAL)
                {
                    t = this.tmp_type();
                    t.base_type = DataType.BYTE;
                    t.flags = TS_SIGNED `| TS_POINTER;
                    t.bit_width = 8;
                    t.pointer_depth = 1;
                    return t;
                };
                return (TypeSpec*)0;
            };

            // Parameter name to type from the call arguments (fparser._infer_template_params).
            // Dict parameters and template struct parameters are not inferred here yet.
            // Concrete type named carg (symbol table alias, builtin name, or a named type)
            def tp_type_by_name(byte* carg) -> TypeSpec*
            {
                TypeSpec* r = (TypeSpec*)0;
                int k;
                if (this.st != (FXC_SYMTABLE*)0) { r = st_get_type_spec(this.st, carg); };
                while (r == (TypeSpec*)0 & k < 18)
                {
                    if (cstr_eq(datatype_text(k), carg))
                    {
                        r = this.tmp_type();
                        r.base_type = k;
                        if (k == DataType.SINT | k == DataType.CHAR) { r.flags = TS_SIGNED; };
                    };
                    k++;
                };
                if (r == (TypeSpec*)0)
                {
                    r = this.tmp_type();
                    r.base_type = DataType.DATA;
                    r.custom_typename = carg;
                };
                return r;
            };

            // Binds the parameters of a declared Name<T,U> parameter from the mangled type of arg
            def infer_struct_param(TemplateEntry* te, PtrVec* raw, Node* arg, NameMap* out) -> void
            {
                TypeSpec* at;
                byte* ctn;
                byte* key;
                byte* sep;
                TemplateEntry* ce;
                PtrVec* cargs;
                int i, j, kl, cl, st0, pos;
                bool match;
                if (arg.kind != NodeKind.IDENTIFIER) { return; };
                if (this.st == (FXC_SYMTABLE*)0) { return; };
                at = st_get_type_spec(this.st, arg.text);
                if (at == (TypeSpec*)0) { return; };
                ctn = at.custom_typename;
                if (ctn == (byte*)0) { return; };
                cl = pp_cstrlen(ctn);
                while (i < this.templates.count)
                {
                    key = this.templates.keys[i];
                    ce = (TemplateEntry*)this.templates.vals[i];
                    i++;
                    if (key == (byte*)0 | ce == (TemplateEntry*)0) { continue; };
                    if (ce.kind != 1 & ce.kind != 2) { continue; };
                    kl = pp_cstrlen(key);
                    match = cstr_eq(ctn, key);
                    if (!match & cl > kl + 2)
                    {
                        match = true;
                        j = 0;
                        while (j < kl)
                        {
                            if (ctn[j] != key[j]) { match = false; };
                            j++;
                        };
                        if (ctn[kl] != '_' | ctn[kl + 1] != '_') { match = false; };
                    };
                    if (!match) { continue; };
                    // concrete arguments: the text after "key__" split on "__"
                    cargs = pv_new();
                    if (cl > kl + 2)
                    {
                        st0 = kl + 2;
                        j = st0;
                        while (j <= cl)
                        {
                            if (j == cl)
                            {
                                pv_push(cargs, (void*)this.own_n(ctn + st0, j - st0));
                            }
                            elif (ctn[j] == '_' & j + 1 < cl)
                            {
                                if (ctn[j + 1] == '_')
                                {
                                    pv_push(cargs, (void*)this.own_n(ctn + st0, j - st0));
                                    st0 = j + 2;
                                    j++;
                                };
                            };
                            j++;
                        };
                    };
                    pos = 0;
                    while (pos < raw.len)
                    {
                        if (this.tp_has_param(te, (byte*)raw.items[pos]) & pos < cargs.len)
                        {
                            if (!nm_has(out, (byte*)raw.items[pos]))
                            {
                                nm_put(out, (byte*)raw.items[pos], (void*)this.tp_type_by_name((byte*)cargs.items[pos]));
                            };
                        };
                        pos++;
                    };
                    pv_free(cargs);
                    return;
                };
                return;
            };

            def infer_template_params(TemplateEntry* te, Node* holder, bool skip_first, NameMap* out) -> void
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
                if (skip_first) { first = 1; };
                i = first;
                while (i < node_count(decl, 0))
                {
                    if (i - first >= nargs) { break; };
                    dp = node_child(decl, 0, i);
                    i++;
                    if (dp.ts == (TypeSpec*)0) { continue; };
                    arg = node_child(holder, 0, i - 1 - first);
                    if (dp.ts.base_type == DataType.DICT)
                    {
                        at = (TypeSpec*)0;
                        if (arg.kind == NodeKind.IDENTIFIER & this.st != (FXC_SYMTABLE*)0) { at = st_get_type_spec(this.st, arg.text); };
                        if (at != (TypeSpec*)0)
                        {
                            if (at.base_type == DataType.DICT)
                            {
                                kp = (byte*)0;
                                vp = (byte*)0;
                                if (dp.ts.dict_key != (TypeSpec*)0) { kp = dp.ts.dict_key.custom_typename; };
                                if (dp.ts.dict_value != (TypeSpec*)0) { vp = dp.ts.dict_value.custom_typename; };
                                if (kp != (byte*)0)
                                {
                                    if (this.tp_has_param(te, kp) & !nm_has(out, kp)) { nm_put(out, kp, (void*)at.dict_key); };
                                };
                                if (vp != (byte*)0)
                                {
                                    if (this.tp_has_param(te, vp) & !nm_has(out, vp)) { nm_put(out, vp, (void*)at.dict_value); };
                                };
                            };
                        };
                        continue;
                    };
                    pt = dp.ts.custom_typename;
                    if (pt == (byte*)0) { continue; };
                    if (arg.kind == NodeKind.ADDRESS_OF)
                    {
                        if (arg.a != (Node*)0)
                        {
                            if (arg.a.kind == NodeKind.IDENTIFIER) { arg = arg.a; };
                        };
                    };
                    raw = pv_new();
                    if (this.tp_split_deferred(pt, raw) > 0)
                    {
                        this.infer_struct_param(te, raw, arg, out);
                        pv_free(raw);
                        continue;
                    };
                    pv_free(raw);
                    if (!this.tp_has_param(te, pt)) { continue; };
                    t = this.infer_arg_type(arg);
                    if (t != (TypeSpec*)0) { nm_put(out, pt, (void*)t); };
                };
                return;
            };

            // "name<a,b>" for a call whose type arguments are still template parameters
            def deferred_name(byte* fname, PtrVec* names) -> byte*
            {
                int i;
                this.sb.len = 0;
                this.sb.put_str(fname);
                this.sb.put('<');
                while (i < names.len)
                {
                    if (i > 0) { this.sb.put(','); };
                    this.sb.put_str((byte*)names.items[i]);
                    i++;
                };
                this.sb.put('>');
                return this.own_n(this.sb.mem, this.sb.len);
            };

            def tp_free_specs(PtrVec* specs) -> void
            {
                int i;
                while (i < specs.len)
                {
                    typespec_free((TypeSpec*)specs.items[i]);
                    i++;
                };
                pv_free(specs);
                return;
            };

            // foo<int, T>(args)
            def template_call_explicit(Node* expr, TemplateEntry* te) -> Node*
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
                    if (this.failed)
                    {
                        typespec_free(ts);
                        break;
                    };
                    pv_push(names, (void*)this.ts_mangle(ts));
                    pv_push(specs, (void*)ts);
                    more = this.expect(TokenType.COMMA);
                    if (more) { this.advance(); };
                };
                if (!this.failed) { this.consume(TokenType.GREATER_THAN); };
                if (!this.failed) { this.consume(TokenType.LEFT_PAREN); };
                if (!this.failed & !this.expect(TokenType.RIGHT_PAREN)) { this.argument_list(holder, expr.text); };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (this.failed)
                {
                    this.tp_free_specs(specs);
                    pv_free(names);
                    node_free(holder);
                    return expr;
                };
                while (i < names.len)
                {
                    if (this.tp_active((byte*)names.items[i])) { deferred = true; };
                    i++;
                };
                n = this.mk(NodeKind.FUNCTION_CALL, line, col);
                if (this.failed)
                {
                    this.tp_free_specs(specs);
                    pv_free(names);
                    node_free(holder);
                    return expr;
                };
                this.take_args(n, holder);
                if (deferred) { n.text = this.deferred_name(expr.text, names); }
                else { n.text = this.resolve_template_call(expr.text, names, specs, (PtrVec*)0); };
                this.tp_free_specs(specs);
                pv_free(names);
                node_free(expr);
                return n;
            };

            // foo(args): the type arguments are inferred from the argument types
            def template_call_implicit(Node* expr, TemplateEntry* te) -> Node*
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
                if (!this.failed & !this.expect(TokenType.RIGHT_PAREN)) { this.argument_list(holder, expr.text); };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (this.failed)
                {
                    nm_free(inferred);
                    pv_free(names);
                    pv_free(specs);
                    pv_free(poss);
                    pv_free(unresolved);
                    node_free(holder);
                    return expr;
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
                    if (dp.ts != (TypeSpec*)0)
                    {
                        if (dp.ts.custom_typename != (byte*)0)
                        {
                            j = 0;
                            while (j < te.params.len)
                            {
                                if (cstr_eq((byte*)te.params.items[j], dp.ts.custom_typename) & poss.items[j] == (void*)0)
                                {
                                    poss.items[j] = (void*)node_child(holder, 0, i);
                                };
                                j++;
                            };
                        };
                    };
                    i++;
                };

                // defaults for what was not inferred
                i = 0;
                while (i < te.dparam.len)
                {
                    p = (byte*)te.dparam.items[i];
                    if (!nm_has(inferred, p)) { nm_put(inferred, p, te.dts.items[i]); };
                    i++;
                };
                i = 0;
                while (i < te.no_default.count)
                {
                    p = te.no_default.keys[i];
                    i++;
                    if (p == (byte*)0) { continue; };
                    if (!nm_has(inferred, p))
                    {
                        this.sb.len = 0;
                        this.sb.put_str(g"Template parameter '\0");
                        this.sb.put_str(p);
                        this.sb.put_str(g"' of '\0");
                        this.sb.put_str(expr.text);
                        this.sb.put_str(g"' has no default and could not be inferred - it must be supplied explicitly\0");
                        this.error_at(this.own_n(this.sb.mem, this.sb.len), line, col);
                        break;
                    };
                };

                n = (Node*)0;
                if (!this.failed)
                {
                    got = 0;
                    i = 0;
                    while (i < te.params.len)
                    {
                        if (nm_has(inferred, (byte*)te.params.items[i])) { got++; }
                        else { pv_push(unresolved, te.params.items[i]); };
                        i++;
                    };
                    n = this.mk(NodeKind.FUNCTION_CALL, line, col);
                };
                if (!this.failed)
                {
                    this.take_args(n, holder);
                    holder = (Node*)0;
                    n.text = expr.text;
                    if (got == te.params.len)
                    {
                        abstract = false;
                        i = 0;
                        while (i < te.params.len)
                        {
                            t = (TypeSpec*)nm_get(inferred, (byte*)te.params.items[i]);
                            pv_push(specs, (void*)t);
                            p = this.ts_mangle(t);
                            pv_push(names, (void*)p);
                            if (this.tp_has_param(te, p)) { abstract = true; };
                            i++;
                        };
                        if (!abstract) { n.text = this.resolve_template_call(expr.text, names, specs, poss); };
                    }
                    else
                    {
                        all_active = unresolved.len > 0;
                        i = 0;
                        while (i < unresolved.len)
                        {
                            if (!this.tp_active((byte*)unresolved.items[i])) { all_active = false; };
                            i++;
                        };
                        if (all_active)
                        {
                            i = 0;
                            while (i < te.params.len)
                            {
                                p = (byte*)te.params.items[i];
                                if (nm_has(inferred, p)) { pv_push(names, (void*)this.ts_mangle((TypeSpec*)nm_get(inferred, p))); }
                                else { pv_push(names, (void*)p); };
                                i++;
                            };
                            n.text = this.deferred_name(expr.text, names);
                        };
                    };
                };
                nm_free(inferred);
                pv_free(names);
                pv_free(specs);
                pv_free(poss);
                pv_free(unresolved);
                if (holder != (Node*)0) { node_free(holder); };
                if (this.failed)
                {
                    node_free(n);
                    return expr;
                };
                node_free(expr);
                return n;
            };

            // Explicit or inferred call of a template function name
            // Registry key of the type function template implied by receiver expr and member, or null
            def typefunc_key(Node* expr, byte* member) -> byte*
            {
                Node* id = (Node*)0;
                bool tied = false;
                TypeSpec* rt;
                byte* rn;
                byte* cand;
                byte* un;
                int pd, i;
                if (this.st == (FXC_SYMTABLE*)0) { return (byte*)0; };
                if (expr.kind == NodeKind.IDENTIFIER) { id = expr; }
                elif (expr.kind == NodeKind.TIE_EXPRESSION)
                {
                    if (expr.a != (Node*)0)
                    {
                        if (expr.a.kind == NodeKind.IDENTIFIER)
                        {
                            id = expr.a;
                            tied = true;
                        };
                    };
                }
                elif (expr.kind == NodeKind.STRING_LITERAL | expr.kind == NodeKind.F_STRING_LITERAL)
                {
                    cand = this.cat2(g"__typefunc__string__\0", member);
                    if (this.template_lookup(cand) != (TemplateEntry*)0) { return cand; };
                    return (byte*)0;
                };
                if (id == (Node*)0) { return (byte*)0; };
                rt = st_get_type_spec(this.st, id.text);
                if (rt == (TypeSpec*)0) { return (byte*)0; };
                pd = rt.pointer_depth;
                if (rt.custom_typename != (byte*)0) { rn = rt.custom_typename; }
                elif (pd > 0 & rt.base_type == DataType.BYTE) { rn = g"string\0"; }
                elif (pd > 0)
                {
                    rn = datatype_text(rt.base_type);
                    while (i < pd)
                    {
                        rn = this.cat2(rn, g"_ptr\0");
                        i++;
                    };
                }
                else { rn = datatype_text(rt.base_type); };
                if ((rt.flags `& TS_TIED) != 0) { tied = true; };
                if (tied) { cand = this.cat2(this.cat2(this.cat2(g"__typefunc__tied_\0", rn), g"__\0"), member); }
                else { cand = this.cat2(this.cat2(this.cat2(g"__typefunc__\0", rn), g"__\0"), member); };
                if (this.template_lookup(cand) != (TemplateEntry*)0) { return cand; };
                if (tied)
                {
                    un = this.cat2(this.cat2(this.cat2(g"__typefunc__\0", rn), g"__\0"), member);
                    if (this.template_lookup(un) != (TemplateEntry*)0) { return un; };
                };
                return (byte*)0;
            };

            // recv.member<types>(args) for a method or type function template registered under key
            def template_method_explicit(Node* recv, byte* key, bool as_typefunc) -> Node*
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
                    if (this.failed)
                    {
                        typespec_free(ts);
                        break;
                    };
                    pv_push(names, (void*)this.ts_mangle(ts));
                    pv_push(specs, (void*)ts);
                    more = this.expect(TokenType.COMMA);
                    if (more) { this.advance(); };
                };
                if (!this.failed) { this.consume(TokenType.GREATER_THAN); };
                if (!this.failed) { this.consume(TokenType.LEFT_PAREN); };
                if (!this.failed & !this.expect(TokenType.RIGHT_PAREN)) { this.argument_list(holder, (byte*)0); };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                n = (Node*)0;
                if (!this.failed) { n = this.mk(NodeKind.FUNCTION_CALL, line, col); };
                if (this.failed)
                {
                    this.tp_free_specs(specs);
                    pv_free(names);
                    node_free(holder);
                    return recv;
                };
                this.take_args(n, holder);
                n.text = this.resolve_template_call(key, names, specs, (PtrVec*)0);
                this.tp_free_specs(specs);
                pv_free(names);
                if (as_typefunc) { this.push_front(n, recv); }
                else { node_free(recv); };
                return n;
            };

            // obj.member(args) tagged as a type function template: infers the parameters from the
            // arguments. Returns the FUNCTION_CALL, or null when not every parameter was inferred.
            def typefunc_call_implicit(Node* ma, Node* holder, int line, int col) -> Node*
            {
                TemplateEntry* te = this.template_lookup(ma.text2);
                NameMap* inferred;
                PtrVec* names;
                PtrVec* specs;
                Node* n = (Node*)0;
                TypeSpec* t;
                int i;
                bool all = true;
                if (te == (TemplateEntry*)0) { return n; };
                inferred = nm_new();
                this.infer_template_params(te, holder, true, inferred);
                i = 0;
                while (i < te.params.len)
                {
                    if (!nm_has(inferred, (byte*)te.params.items[i])) { all = false; };
                    i++;
                };
                if (all)
                {
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
                    if (!this.failed)
                    {
                        n.text = this.resolve_template_call(ma.text2, names, specs, (PtrVec*)0);
                    };
                    pv_free(names);
                    pv_free(specs);
                };
                nm_free(inferred);
                return n;
            };

            def template_call(Node* expr) -> Node*
            {
                TemplateEntry* te;
                if (expr.kind != NodeKind.IDENTIFIER) { return expr; };
                te = this.template_lookup(expr.text);
                if (te == (TemplateEntry*)0) { return expr; };
                if (te.kind != 0) { return expr; };
                if (this.expect(TokenType.LESS_THAN)) { return this.template_call_explicit(expr, te); };
                if (this.expect(TokenType.LEFT_PAREN)) { return this.template_call_implicit(expr, te); };
                return expr;
            };

            // ----- constra -----

            // True when the cursor starts a relational constraint operator
            def is_relop() -> bool
            {
                int t0 = this.cur();
                int t1 = this.type_at(1);
                int t2 = this.type_at(2);
                if (t0 == TokenType.TIE) { return t1 == TokenType.ASSIGN; };
                if (t0 != TokenType.NOT) { return false; };
                if (t1 == TokenType.TIE) { return t2 == TokenType.ASSIGN; };
                if (t1 == TokenType.ADDRESS_OF) { return true; };
                if (t1 == TokenType.MINUS_ASSIGN) { return true; };
                if (t1 == TokenType.BACKTICK)
                {
                    return t2 == TokenType.LESS_THAN | t2 == TokenType.LESS_EQUAL |
                           t2 == TokenType.GREATER_THAN | t2 == TokenType.GREATER_EQUAL;
                };
                return false;
            };

            // Consumes the operator tokens and returns the operator text
            def consume_relop() -> byte*
            {
                if (this.expect(TokenType.TIE))
                {
                    this.advance();
                    this.consume(TokenType.ASSIGN);
                    return g"~=\0";
                };
                this.consume(TokenType.NOT);
                if (this.expect(TokenType.TIE))
                {
                    this.advance();
                    this.consume(TokenType.ASSIGN);
                    return g"!~=\0";
                };
                if (this.expect(TokenType.ADDRESS_OF)) { this.advance(); return g"!@\0"; };
                if (this.expect(TokenType.MINUS_ASSIGN)) { this.advance(); return g"!-=\0"; };
                this.consume(TokenType.BACKTICK);
                if (this.expect(TokenType.LESS_EQUAL)) { this.advance(); return g"!`<=\0"; };
                if (this.expect(TokenType.LESS_THAN)) { this.advance(); return g"!`<\0"; };
                if (this.expect(TokenType.GREATER_EQUAL)) { this.advance(); return g"!`>=\0"; };
                if (this.expect(TokenType.GREATER_THAN)) { this.advance(); return g"!`>\0"; };
                this.error(g"Unknown constraint operator after '!`'\0");
                return (byte*)0;
            };

            // Appends a CONSTRA_RELATION (l0 = lhs names, text = op, l1 = rhs names) to d.l1
            def cs_emit(Node* d, PtrVec* lhs, byte* op, PtrVec* rhs, int line, int col) -> void
            {
                Node* rel = this.mk(NodeKind.CONSTRA_RELATION, line, col);
                if (this.failed) { return; };
                node_push(d, 1, rel);
                rel.text = op;
                Node* id;
                int i;
                while (i < lhs.len)
                {
                    id = this.mk(NodeKind.IDENTIFIER, line, col);
                    if (this.failed) { return; };
                    id.text = (byte*)lhs.items[i];
                    node_push(rel, 0, id);
                    i++;
                };
                i = 0;
                while (i < rhs.len)
                {
                    id = this.mk(NodeKind.IDENTIFIER, line, col);
                    if (this.failed) { return; };
                    id.text = (byte*)rhs.items[i];
                    node_push(rel, 1, id);
                    i++;
                };
                return;
            };

            // One element of a name list: IDENTIFIER, or '[' names (op names)? ']'
            // A bracket group emits its own relation into d and yields the names of its last side.
            def cs_element(Node* d, PtrVec* out) -> void
            {
                PtrVec* ns;
                PtrVec* rhs;
                byte* op;
                int line, col, i;
                PtrVec* res;
                if (!this.expect(TokenType.LEFT_BRACKET))
                {
                    pv_push(out, (void*)this.ident());
                    return;
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
                if (!this.failed & this.is_relop())
                {
                    op = this.consume_relop();
                    rhs = pv_new();
                    pv_push(rhs, (void*)this.ident());
                    while (!this.failed & this.expect(TokenType.LOGICAL_AND) & this.type_at(1) == TokenType.IDENTIFIER)
                    {
                        this.advance();
                        pv_push(rhs, (void*)this.ident());
                    };
                    if (!this.failed) { this.cs_emit(d, ns, op, rhs, line, col); };
                    res = rhs;
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACKET); };
                while (i < res.len)
                {
                    pv_push(out, res.items[i]);
                    i++;
                };
                if (res != ns) { pv_free(res); };
                pv_free(ns);
                return;
            };

            // names joined by '&'
            def cs_idlist(Node* d, PtrVec* out) -> void
            {
                int t1;
                this.cs_element(d, out);
                while (!this.failed & this.expect(TokenType.LOGICAL_AND))
                {
                    t1 = this.type_at(1);
                    if (t1 != TokenType.IDENTIFIER & t1 != TokenType.LEFT_BRACKET) { break; };
                    this.advance();
                    this.cs_element(d, out);
                };
                return;
            };

            // Chained relation: names op names op names ...
            def cs_rel_expr(Node* d) -> void
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
                    if (!this.failed) { this.cs_emit(d, lhs, op, rhs, line, col); };
                    pv_free(lhs);
                    lhs = rhs;
                };
                pv_free(lhs);
                return;
            };

            def cs_less(byte* a, byte* b) -> bool
            {
                int i;
                while (a[i] != (byte)0 & a[i] == b[i]) { i++; };
                return a[i] < b[i];
            };

            // Same set of names (duplicates ignored)
            def cs_same_set(Node* x, int lx, Node* y, int ly) -> bool
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
                        if (cstr_eq(node_child(x, lx, i).text, node_child(y, ly, j).text)) { hit = true; };
                        j++;
                    };
                    if (!hit) { return false; };
                    i++;
                };
                i = 0;
                while (i < ny)
                {
                    hit = false;
                    j = 0;
                    while (j < nx & !hit)
                    {
                        if (cstr_eq(node_child(y, ly, i).text, node_child(x, lx, j).text)) { hit = true; };
                        j++;
                    };
                    if (!hit) { return false; };
                    i++;
                };
                return true;
            };

            // Writes the names of side l of rel to sb sorted and joined by " & "
            def cs_put_sorted(Node* rel, int l) -> void
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
                    if (i > 0) { this.sb.put_str(g" & \0"); };
                    this.sb.put_str((byte*)v.items[i]);
                    i++;
                };
                pv_free(v);
                return;
            };

            // Mutex partner of op, or null
            def cs_mutex(byte* op) -> byte*
            {
                if (cstr_eq(op, g"~=\0")) { return g"!~=\0"; };
                if (cstr_eq(op, g"!~=\0")) { return g"~=\0"; };
                if (cstr_eq(op, g"!`<=\0")) { return g"!`>=\0"; };
                if (cstr_eq(op, g"!`>=\0")) { return g"!`<=\0"; };
                return (byte*)0;
            };

            // Error at the position m (the 'constra' token) with the text in sb
            def cs_error_at(int m) -> void
            {
                this.reset(m);
                this.error(this.own_n(this.sb.mem, this.sb.len));
                return;
            };

            // Merge form after '=': constra A = B + C;  (rename = optional param list, else null)
            def constra_merge(Node* d, int m0, PtrVec* rename) -> void
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
                    if (this.failed) { break; };
                    if (!nm_has(this.constras, sname))
                    {
                        this.reset(m);
                        this.sb.len = 0;
                        this.sb.put_str(g"Unknown constraint set '\0");
                        this.sb.put_str(sname);
                        this.sb.put_str(g"' in constra merge\0");
                        this.cs_error_at(m);
                        break;
                    };
                    pv_push(srcs, nm_get(this.constras, sname));
                    more = this.expect(TokenType.PLUS);
                    if (more) { this.advance(); };
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (this.failed)
                {
                    pv_free(srcs);
                    pv_free(finals);
                    return;
                };
                src = (Node*)srcs.items[0];
                base = node_count(src, 0);
                i = 1;
                while (i < srcs.len & !this.failed)
                {
                    prev = (Node*)srcs.items[i];
                    if (node_count(prev, 0) != base)
                    {
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
                    };
                    i++;
                };
                if (!this.failed & rename != (PtrVec*)0)
                {
                    if (rename.len != base)
                    {
                        this.sb.len = 0;
                        this.sb.put_str(g"Rename parameter list has \0");
                        this.sb.put_int(rename.len);
                        this.sb.put_str(g" name(s) but merged constraint sets have arity \0");
                        this.sb.put_int(base);
                        this.cs_error_at(m0);
                    };
                };
                if (this.failed)
                {
                    pv_free(srcs);
                    pv_free(finals);
                    return;
                };
                i = 0;
                while (i < base)
                {
                    if (rename != (PtrVec*)0) { pv_push(finals, rename.items[i]); }
                    else { pv_push(finals, (void*)node_child(src, 0, i).text); };
                    id = this.mk(NodeKind.IDENTIFIER, d.line, d.col);
                    if (this.failed) { break; };
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
                        if (this.failed) { break; };
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
                                    if (cstr_eq(node_child(src, 0, base).text, mapped))
                                    {
                                        mapped = (byte*)finals.items[base];
                                        break;
                                    };
                                    base--;
                                };
                                id = this.mk(NodeKind.IDENTIFIER, rel.line, rel.col);
                                if (this.failed) { break; };
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
                        if (cstr_eq(prev.text, mx) &
                            this.cs_same_set(prev, 0, rel, 0) & this.cs_same_set(prev, 1, rel, 1))
                        {
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
                        };
                        j++;
                    };
                    i++;
                };
                pv_free(srcs);
                pv_free(finals);
                return;
            };

            // constra_def -> 'constra' IDENTIFIER ('(' names ')')? ( '=' names_merge | '{' relations '}' ) ';'
            def constra_def() -> Node*
            {
                int m0 = this.mark();
                Node* d = this.mk(NodeKind.CONSTRA_DEF, this.cur_line(), this.cur_col());
                if (this.failed) { return d; };
                Node* id;
                PtrVec* rename;
                int m;
                bool more;
                this.advance();
                d.text = this.ident();
                if (!this.failed & this.expect(TokenType.LEFT_PAREN))
                {
                    m = this.mark();
                    this.advance();
                    rename = pv_new();
                    if (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        more = true;
                        while (more & !this.failed)
                        {
                            pv_push(rename, (void*)this.ident());
                            more = this.expect(TokenType.COMMA);
                            if (more) { this.advance(); };
                        };
                    };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                    if (!this.failed & !this.expect(TokenType.ASSIGN))
                    {
                        pv_free(rename);
                        rename = (PtrVec*)0;
                        this.reset(m);
                    };
                };
                if (!this.failed & this.expect(TokenType.ASSIGN))
                {
                    this.advance();
                    this.constra_merge(d, m0, rename);
                    if (rename != (PtrVec*)0) { pv_free(rename); };
                    if (this.failed) { return this.done(d); };
                    nm_put(this.constras, d.text, (void*)d);
                    return d;
                };
                if (rename != (PtrVec*)0) { pv_free(rename); };
                if (!this.failed & this.expect(TokenType.LEFT_PAREN))
                {
                    this.advance();
                    if (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        more = true;
                        while (more & !this.failed)
                        {
                            id = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                            if (this.failed) { break; };
                            node_push(d, 0, id);
                            id.text = this.ident();
                            more = this.expect(TokenType.COMMA);
                            if (more) { this.advance(); };
                        };
                    };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                };
                if (!this.failed) { this.consume(TokenType.LEFT_BRACE); };
                if (!this.failed) { this.cs_rel_expr(d); };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.COMMA)) { this.advance(); };
                    this.cs_rel_expr(d);
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (this.failed) { return this.done(d); };
                nm_put(this.constras, d.text, (void*)d);
                return d;
            };

            // Canonical receiver type name of the token at the cursor, or null when it is not a receiver
            def tf_receiver_name() -> byte*
            {
                int t = this.cur();
                if (t == TokenType.BYTE) { return g"byte\0"; };
                if (t == TokenType.SINT | t == TokenType.SINT_LITERAL) { return g"int\0"; };
                if (t == TokenType.UINT | t == TokenType.UINT_LITERAL) { return g"uint\0"; };
                if (t == TokenType.SLONG | t == TokenType.SLONG_LITERAL) { return g"long\0"; };
                if (t == TokenType.ULONG | t == TokenType.ULONG_LITERAL) { return g"ulong\0"; };
                if (t == TokenType.FLOAT_KW | t == TokenType.FLOAT) { return g"float\0"; };
                if (t == TokenType.DOUBLE_KW | t == TokenType.DOUBLE) { return g"double\0"; };
                if (t == TokenType.BOOL_KW | t == TokenType.TRUE | t == TokenType.FALSE) { return g"bool\0"; };
                if (t == TokenType.STRING_LITERAL | t == TokenType.F_STRING | t == TokenType.I_STRING) { return g"string\0"; };
                if (t == TokenType.CHAR) { return g"char\0"; };
                if (t == TokenType.IDENTIFIER) { return this.cur_value(); };
                return (byte*)0;
            };

            // Type of the implicit receiver parameter (fparser.py _type_func_receiver_type_spec)
            def tf_receiver_ts(byte* tn, int depth, bool is_array) -> TypeSpec*
            {
                TypeSpec* t = typespec_new();
                int base = -1;
                if (cstr_eq(tn, g"string\0") | (cstr_eq(tn, g"byte\0") & depth >= 1))
                {
                    if (depth < 1) { depth = 1; };
                    t.base_type = DataType.BYTE;
                    t.pointer_depth = depth;
                    t.flags = t.flags `| TS_POINTER;
                    return t;
                };
                if (cstr_eq(tn, g"byte\0")) { base = DataType.BYTE; }
                elif (cstr_eq(tn, g"int\0")) { base = DataType.SINT; }
                elif (cstr_eq(tn, g"uint\0")) { base = DataType.UINT; }
                elif (cstr_eq(tn, g"long\0")) { base = DataType.SLONG; }
                elif (cstr_eq(tn, g"ulong\0")) { base = DataType.ULONG; }
                elif (cstr_eq(tn, g"float\0")) { base = DataType.FLOAT; }
                elif (cstr_eq(tn, g"double\0")) { base = DataType.DOUBLE; }
                elif (cstr_eq(tn, g"bool\0")) { base = DataType.BOOL; }
                elif (cstr_eq(tn, g"char\0")) { base = DataType.CHAR; };
                if (base < 0)
                {
                    t.base_type = DataType.DATA;
                    t.custom_typename = tn;
                }
                else
                {
                    t.base_type = base;
                };
                if (is_array) { t.flags = t.flags `| TS_ARRAY; }
                elif (depth > 0)
                {
                    t.pointer_depth = depth;
                    t.flags = t.flags `| TS_POINTER;
                };
                return t;
            };

            // type_func_def -> '~'? receiver '*'* ('[' ']')? '.' name ('<' ... '>')? '(' params ')' '->' type (';' | block ';')
            def type_func_def() -> Node*
            {
                NameMap* prev_act = this.active_tp;
                TemplateEntry* prev_cur = this.tmpl_cur;
                this.tmpl_cur = (TemplateEntry*)0;
                Node* d = this.type_func_def_inner();
                TemplateEntry* te = this.tmpl_cur;
                this.tmpl_cur = prev_cur;
                if (this.active_tp != prev_act)
                {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                };
                if (te == (TemplateEntry*)0) { return d; };
                if (this.failed | d == (Node*)0)
                {
                    te_free(te);
                    return d;
                };
                this.tf_to_function(d);
                this.last_template = d.text;
                this.register_template(d.text, 0, te, d);
                return (Node*)0;
            };

            // Turns a type function into the synthetic FUNCTION_DEF the Python registers:
            // __typefunc__<type>__<name>(_ receiver, params...)
            def tf_to_function(Node* d) -> void
            {
                PtrVec* tmp = pv_new();
                Node* p0 = this.mk(NodeKind.PARAMETER, d.line, d.col);
                int i, n;
                if (this.failed) { pv_free(tmp); return; };
                p0.text = g"_\0";
                p0.ts = d.ts2;
                d.ts2 = (TypeSpec*)0;
                n = node_count(d, 0);
                while (i < n)
                {
                    pv_push(tmp, (void*)node_child(d, 0, i));
                    i++;
                };
                if (n > 0) { d.l0.len = 0; };
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
                return;
            };

            def type_func_def_inner() -> Node*
            {
                int m = this.mark();
                Node* d = this.mk(NodeKind.TYPE_FUNC_DEF, this.cur_line(), this.cur_col());
                if (this.failed) { return d; };
                bool tied = false;
                bool is_array = false;
                int depth = 0;
                byte* tn;
                byte* eff;
                int k;
                TypeSpec* rts;
                Node* fl;
                if (this.expect(TokenType.TIE)) { tied = true; this.advance(); };
                tn = this.tf_receiver_name();
                if (tn == (byte*)0)
                {
                    this.error(g"Expected a type keyword, literal, or struct name as type function receiver\0");
                    return this.done(d);
                };
                if (this.st != (FXC_SYMTABLE*)0)
                {
                    if (st_is_nofunc(this.st, tn))
                    {
                        this.error(this.cat2(this.cat2(g"Type \0", tn), g" is non-functional (declared with data!) and cannot have type functions defined on it\0"));
                        return this.done(d);
                    };
                };
                this.advance();
                while (this.expect(TokenType.MULTIPLY)) { depth++; this.advance(); };
                if (this.expect(TokenType.LEFT_BRACKET))
                {
                    this.advance();
                    this.consume(TokenType.RIGHT_BRACKET);
                    is_array = true;
                };
                if (!this.failed) { this.consume(TokenType.DOT); };
                if (this.failed) { return this.done(d); };
                if (this.expect2(TokenType.F_STRING, TokenType.I_STRING))
                {
                    fl = this.fstr_node();
                    if (this.failed) { return this.done(d); };
                    d.text2 = this.fstr_resolve(fl);
                    node_free(fl);
                    if (d.text2 == (byte*)0)
                    {
                        this.error(g"The type function name could not be resolved at parse time\0");
                        return this.done(d);
                    };
                }
                elif (this.expect(TokenType.STRING_LITERAL))
                {
                    d.text2 = this.cur_value();
                    this.advance();
                }
                else
                {
                    d.text2 = this.ident();
                };
                if (this.failed) { return this.done(d); };
                if (this.expect(TokenType.RECURSE_ARROW))
                {
                    // the Python parser splits '<~' into '<' and '~', which is not a template list
                    this.fail_expected(TokenType.LEFT_PAREN);
                    this.err_got = TokenType.LESS_THAN;
                    return this.done(d);
                };
                if (this.expect(TokenType.LESS_THAN))
                {
                    this.tmpl_cur = this.template_params(true);
                    if (this.failed) { return this.done(d); };
                    this.tp_activate(this.tmpl_cur);
                };
                this.consume(TokenType.LEFT_PAREN);
                if (!this.failed & !this.expect(TokenType.RIGHT_PAREN)) { this.parameter_list(d); };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (!this.failed) { this.consume(TokenType.RETURN_ARROW); };
                if (!this.failed) { d.ts = this.type_spec(); };
                if (this.failed) { return this.done(d); };
                rts = this.tf_receiver_ts(tn, depth, is_array);
                if (tied) { rts.flags = rts.flags `| TS_TIED; };
                d.ts2 = rts;
                // canonical name used for mangling
                eff = tn;
                if (depth > 0 & cstr_eq(tn, g"byte\0")) { eff = g"string\0"; }
                elif (depth > 0)
                {
                    k = 0;
                    while (k < depth) { eff = this.cat2(eff, g"_ptr\0"); k++; };
                }
                elif (is_array) { eff = this.cat2(tn, g"_arr\0"); };
                if (tied) { eff = this.cat2(g"tied_\0", eff); };
                d.text = eff;
                if (this.expect(TokenType.SEMICOLON))
                {
                    this.advance();
                    d.flags = NF_PROTOTYPE;
                    d.a = this.mk(NodeKind.BLOCK, d.line, d.col);
                    return this.done(d);
                };
                d.a = this.block();
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(d);
            };

            // Appends the source text of the current token to sb (mirrors _token_to_source).
            // Quoted forms are rebuilt, every other token value is already its source text.
            def token_source() -> void
            {
                int tt = this.cur();
                byte* v = this.cur_value();
                int n = this.cur_value_len();
                int i;
                int b;
                if (tt == TokenType.STRING_LITERAL | tt == TokenType.G_STRING)
                {
                    if (tt == TokenType.G_STRING) { this.sb.put('g'); };
                    this.sb.put('"');
                    while (i < n)
                    {
                        b = (int)v[i];
                        if (b == 92 | b == '"') { this.sb.put(92); };
                        this.sb.put(b);
                        i++;
                    };
                    this.sb.put('"');
                    return;
                };
                if (tt == TokenType.CHAR)
                {
                    if (this.toks[this.pos].numeric_char != 0)
                    {
                        this.sb.put_n(v, n);
                        this.sb.put('c');
                        return;
                    };
                    this.sb.put(39);
                    while (i < n)
                    {
                        b = (int)v[i];
                        if (b == 92 | b == 39) { this.sb.put(92); };
                        this.sb.put(b);
                        i++;
                    };
                    this.sb.put(39);
                    return;
                };
                if (tt == TokenType.BYTE_LITERAL)
                {
                    this.sb.put_n(v, n);
                    this.sb.put('b');
                    return;
                };
                this.sb.put_n(v, n);
                return;
            };

            // Separator before an emitflux part: a space between parts, none after '~$'
            def ef_begin(bool glue) -> void
            {
                if (this.sb.len > 0 & !glue) { this.sb.put(' '); };
                return;
            };

            // emitflux_statement -> 'emitflux' '{' <raw source text> '}' ';'
            // Captures the raw source between the braces, with nested braces counted.
            // '#};' is captured as '}' ';' without changing the depth, and '} #' ends
            // the block at any depth. Parts are joined by one space, '~$' fuses with the next part.
            def emitflux_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.EMIT_FLUX, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.advance();
                if (!this.consume(TokenType.LEFT_BRACE)) { return this.done(n); };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                int depth = 1;
                int c;
                bool glue = false;
                bool stop = false;
                while (depth > 0 & !stop & !this.failed)
                {
                    c = this.cur();
                    if (c == TokenType.EOF)
                    {
                        this.error(g"Unexpected EOF inside 'emitflux' block\0");
                        break;
                    };
                    if (c == TokenType.TAG)
                    {
                        if (this.type_at(1) == TokenType.RIGHT_BRACE & this.type_at(2) == TokenType.SEMICOLON)
                        {
                            this.advance();
                            this.ef_begin(glue);
                            this.sb.put('}');
                            this.advance();
                            this.ef_begin(false);
                            this.sb.put(';');
                            this.advance();
                            glue = false;
                            continue;
                        };
                        this.ef_begin(glue);
                        this.token_source();
                        glue = false;
                        this.advance();
                        continue;
                    };
                    if (c == TokenType.LEFT_BRACE)
                    {
                        depth++;
                        this.ef_begin(glue);
                        this.sb.put('{');
                        glue = false;
                    }
                    elif (c == TokenType.RIGHT_BRACE)
                    {
                        if (this.type_at(1) == TokenType.TAG)
                        {
                            this.advance();
                            this.advance();
                            stop = true;
                        }
                        else
                        {
                            depth--;
                            if (depth > 0)
                            {
                                this.ef_begin(glue);
                                this.sb.put('}');
                                glue = false;
                            }
                            else
                            {
                                this.advance();
                                stop = true;
                            };
                        };
                    }
                    else
                    {
                        this.ef_begin(glue);
                        this.token_source();
                        glue = (c == TokenType.CODIFY);
                    };
                    if (!stop) { this.advance(); };
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                n.text = this.own_n(this.sb.mem, this.sb.len);
                return this.done(n);
            };

            // ===== CODIFY (~$) =====

            // Records a byte* string literal initializer so ~$name can splice it
            // (fparser._comptime_strings). The text is borrowed from the token.
            def note_comptime_string(byte* name, TypeSpec* ts, Node* init) -> void
            {
                if (init == (Node*)0) { return; };
                if (init.kind != NodeKind.STRING_LITERAL) { return; };
                if ((ts.flags `& TS_POINTER) == 0) { return; };
                if (ts.base_type != DataType.BYTE) { return; };
                nm_put(this.cstrs, name, (void*)init.text);
                return;
            };

            def codify_unknown(byte* name) -> void
            {
                this.error3(g"~$: '\0", name, g"' is not a compile-time-known byte* string literal. Only variables declared as 'byte* name = \"...\";' are supported.\0");
                return;
            };

            // Text of the f-string or i-string token at the cursor with each {name} replaced by the
            // string recorded for name. strict reports an unrecorded name, otherwise it stands for
            // itself. Returns an owned string, or null with the error recorded.
            def codify_text_of(bool strict) -> byte*
            {
                Node* fl;
                Node* p;
                byte* val;
                int k, cnt;
                if (this.expect(TokenType.F_STRING)) { fl = this.f_string_node(); }
                else { fl = this.i_string_node(); };
                if (this.failed) { return (byte*)0; };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                cnt = node_count(fl, 0);
                while (k < cnt & !this.failed)
                {
                    p = node_child(fl, 0, k);
                    if (p.kind == NodeKind.STRING_LITERAL)
                    {
                        this.sb.put_str(p.text);
                    }
                    elif (p.kind == NodeKind.IDENTIFIER)
                    {
                        val = (byte*)nm_get(this.cstrs, p.text);
                        if (val != (byte*)0) { this.sb.put_str(val); }
                        elif (strict) { this.codify_unknown(p.text); }
                        else { this.sb.put_str(p.text); };
                    }
                    else
                    {
                        this.error(g"~$: an interpolated expression must be an identifier\0");
                    };
                    k++;
                };
                node_free(fl);
                if (this.failed) { return (byte*)0; };
                return this.own_n(this.sb.mem, this.sb.len);
            };

            // ~$ followed by an f-string, i-string or identifier (fparser._consume_codify).
            // An identifier without a recorded string stands for itself.
            def consume_codify() -> byte*
            {
                this.advance();
                if (this.expect2(TokenType.F_STRING, TokenType.I_STRING)) { return this.codify_text_of(false); };
                byte* name = this.ident();
                if (this.failed) { return (byte*)0; };
                byte* val = (byte*)nm_get(this.cstrs, name);
                if (val != (byte*)0) { return val; };
                return name;
            };

            // Parses src with a fresh parser (no shared state, as in fparser.py) and returns its
            // statements: the first is returned, the rest are queued in pending. Null when empty.
            def splice_source(byte* src) -> Node*
            {
                int n = pp_cstrlen(src);
                byte* text = this.own_n(src, n);
                Lexer* sl = (Lexer*)fmalloc((u64)((sizeof(Lexer) + 7) / 8));
                if (sl == (Lexer*)0)
                {
                    this.fail_alloc();
                    return (Node*)0;
                };
                sl.__init(text, n);
                pv_push(this.sublex, (void*)sl);
                if (!sl.tokenize())
                {
                    this.error(flux::lexer::error_message(sl.err_code));
                    return (Node*)0;
                };
                Parser* sp = (Parser*)fmalloc((u64)((sizeof(Parser) + 7) / 8));
                if (sp == (Parser*)0)
                {
                    this.fail_alloc();
                    return (Node*)0;
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
                    if (sp.failed) { break; };
                    if (stmt != (Node*)0)
                    {
                        if (first == (Node*)0) { first = stmt; }
                        else { nv_push(this.pending, stmt); };
                    };
                    k = 0;
                    while (k < sp.pending.len)
                    {
                        if (first == (Node*)0) { first = (Node*)sp.pending.items[k]; }
                        else { nv_push(this.pending, sp.pending.items[k]); };
                        k++;
                    };
                    sp.pending.len = 0;
                };

                // stubs hit while parsing the spliced source count toward this parser
                while (f < Feat.COUNT)
                {
                    if (sp.feat_hits[f] != 0)
                    {
                        if (this.feat_hits[f] == 0) { this.stub_features++; };
                        this.feat_hits[f] = this.feat_hits[f] + sp.feat_hits[f];
                    };
                    f++;
                };
                this.stub_total = this.stub_total + sp.stub_total;

                if (sp.failed)
                {
                    node_free(first);
                    this.failed = true;
                    this.err_kind = sp.err_kind;
                    this.err_expected = sp.err_expected;
                    this.err_got = sp.err_got;
                    this.err_line = sp.err_line;
                    this.err_col = sp.err_col;
                    this.err_msg = sp.err_msg;
                    return (Node*)0;
                };
                return first;
            };

            // ~$ (STRING_LITERAL | F_STRING | I_STRING | IDENTIFIER) ';'
            // The string is parsed as statements that stand in place of this one.
            def codify_statement() -> Node*
            {
                byte* src = (byte*)0;
                byte* name;
                this.advance();
                if (this.expect(TokenType.STRING_LITERAL))
                {
                    src = this.cur_value();
                    this.advance();
                }
                elif (this.expect2(TokenType.F_STRING, TokenType.I_STRING))
                {
                    src = this.codify_text_of(true);
                }
                elif (this.expect(TokenType.IDENTIFIER))
                {
                    name = this.cur_value();
                    this.advance();
                    src = (byte*)nm_get(this.cstrs, name);
                    if (src == (byte*)0) { this.codify_unknown(name); };
                }
                else
                {
                    this.error(g"~$: expected identifier, string literal, f-string, or i-string after codify operator\0");
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (this.failed) { return (Node*)0; };
                return this.splice_source(src);
            };

            // ===== SUPPORT FOR TYPES AND EXPRESSIONS =====

            // Keeps a heap string alive until the parser is destroyed
            def own(byte* s) -> byte*
            {
                pv_push(this.strs, (void*)s);
                return s;
            };

            // Owned copy of s[0, n)
            def own_n(byte* s, int n) -> byte*
            {
                byte* r = (byte*)fmalloc((u64)n + (u64)1);
                int i;
                while (i < n)
                {
                    r[i] = s[i];
                    i++;
                };
                r[n] = (byte)0;
                return this.own(r);
            };

            // Owned a + b
            def cat2(byte* a, byte* b) -> byte*
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
                return this.own(r);
            };

            def fail_alloc() -> void
            {
                if (this.failed) { return; };
                this.failed = true;
                this.err_kind = ParseErr.ALLOC;
                return;
            };

            // New node at (line, col)
            def mk(int kind, int line, int col) -> Node*
            {
                Node* n = node_new(kind, line, col);
                if (n == (Node*)0) { this.fail_alloc(); };
                return n;
            };

            // Clears a recorded error so a speculative parse can be abandoned
            def clear_error() -> void
            {
                this.failed = false;
                this.err_kind = ParseErr.NONE;
                this.err_msg = (byte*)0;
                return;
            };

            // Records a feature hit without consuming anything
            def note_feat(int feat) -> void
            {
                this.stub_total++;
                if (this.feat_hits[feat] == 0) { this.stub_features++; };
                this.feat_hits[feat] = this.feat_hits[feat] + 1;
                if (this.verbose)
                {
                    print(g"[BootstrapParser] \0");
                    print(feature_name(feat));
                    print(g" not implemented (line \0");
                    print(this.cur_line());
                    print(g", col \0");
                    print(this.cur_col());
                    println(g")\0");
                }
                elif (this.feat_hits[feat] == 1)
                {
                    print(g"[BootstrapParser] \0");
                    print(feature_name(feat));
                    println(g" not implemented\0");
                };
                return;
            };

            // "Unexpected token: NAME" at the current token
            def error_unexpected() -> void
            {
                this.error(this.cat2(g"Unexpected token: \0", token_name(this.cur())));
                return;
            };

            // Integer value of a literal. Handles 0x 0b 0o, the base 32 0d form and
            // decimal, ignoring '_'. *ok is cleared when no digit was read.
            def parse_int(byte* s, bool* ok) -> i64
            {
                i64 v = 0;
                i64 base = 10;
                int i = 0;
                int d;
                int c;
                bool any = false;
                if (s[0] == '0' & (s[1] == 'x' | s[1] == 'X')) { base = 16; i = 2; }
                elif (s[0] == '0' & (s[1] == 'b' | s[1] == 'B')) { base = 2; i = 2; }
                elif (s[0] == '0' & (s[1] == 'o' | s[1] == 'O')) { base = 8; i = 2; }
                elif (s[0] == '0' & s[1] == 'd') { base = 32; i = 2; };
                while (s[i] != 0)
                {
                    c = (int)s[i];
                    i++;
                    if (c == '_') { continue; };
                    d = -1;
                    if (c >= '0' & c <= '9') { d = c - '0'; }
                    elif (c >= 'a' & c <= 'z') { d = c - 'a' + 10; }
                    elif (c >= 'A' & c <= 'Z') { d = c - 'A' + 10; };
                    if (d < 0 | (i64)d >= base) { break; };
                    v = v * base + (i64)d;
                    any = true;
                };
                *ok = any;
                return v;
            };

            // Value of a decimal floating literal (digits, '.', optional exponent)
            def parse_double(byte* s) -> double
            {
                double v = 0.0;
                double scale = 1.0;
                int i = 0;
                int c;
                bool frac = false;
                bool neg = false;
                int ex = 0;
                bool exneg = false;
                while (s[i] != 0)
                {
                    c = (int)s[i];
                    if (c >= '0' & c <= '9')
                    {
                        v = v * 10.0 + (double)(c - '0');
                        if (frac) { scale = scale * 10.0; };
                    }
                    elif (c == '.') { frac = true; }
                    elif (c == 'e' | c == 'E')
                    {
                        i++;
                        if (s[i] == '-') { exneg = true; i++; }
                        elif (s[i] == '+') { i++; };
                        while (s[i] >= '0' & s[i] <= '9')
                        {
                            ex = ex * 10 + ((int)s[i] - '0');
                            i++;
                        };
                        break;
                    }
                    elif (c != '_') { break; };
                    i++;
                };
                v = v / scale;
                while (ex > 0)
                {
                    if (exneg) { v = v / 10.0; }
                    else { v = v * 10.0; };
                    ex--;
                };
                return v;
            };

            // Name used when a type argument list is folded into a type name
            // (fparser._type_system_to_mangle_str)
            // "NS::x" to "NS__x"
            def tp_unqual(byte* s) -> byte*
            {
                int i;
                int n = pp_cstrlen(s);
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                while (i < n)
                {
                    if (s[i] == ':' & i + 1 < n)
                    {
                        if (s[i + 1] == ':')
                        {
                            this.sb.put_str(g"__\0");
                            i = i + 2;
                            continue;
                        };
                    };
                    this.sb.put(s[i]);
                    i++;
                };
                return this.own_n(this.sb.mem, this.sb.len);
            };

            // The registry key when name (bare, or NS::x as NS__x) is a template struct or object
            def tmpl_type_key(byte* name) -> byte*
            {
                TemplateEntry* e = this.template_lookup(name);
                byte* q;
                if (e != (TemplateEntry*)0)
                {
                    if (e.kind == 1 | e.kind == 2) { return name; };
                };
                if (nm_has(this.tobj_fwd, name)) { return name; };
                q = this.tp_unqual(name);
                e = this.template_lookup(q);
                if (e != (TemplateEntry*)0)
                {
                    if (e.kind == 1 | e.kind == 2) { return q; };
                };
                if (nm_has(this.tobj_fwd, q)) { return q; };
                return (byte*)0;
            };

            // Name<args> after a named type (cursor on '<'): resolves the instance, or defers
            // as "Key<a,b>" while an argument is still an active template parameter.
            def template_type_use(TypeSpec* t, byte* key) -> void
            {
                PtrVec* names = pv_new();
                PtrVec* specs = pv_new();
                TypeSpec* a;
                bool postpone = false;
                int i;
                this.advance();
                a = this.type_spec();
                pv_push(specs, (void*)a);
                if (!this.failed) { pv_push(names, (void*)this.type_mangle_str(a)); };
                while (!this.failed & this.expect(TokenType.COMMA))
                {
                    this.advance();
                    a = this.type_spec();
                    pv_push(specs, (void*)a);
                    if (!this.failed) { pv_push(names, (void*)this.type_mangle_str(a)); };
                };
                if (!this.failed) { this.consume(TokenType.GREATER_THAN); };
                if (!this.failed)
                {
                    while (i < names.len)
                    {
                        if (this.tp_active((byte*)names.items[i])) { postpone = true; };
                        i++;
                    };
                    if (postpone)
                    {
                        t.custom_typename = this.deferred_name(key, names);
                    }
                    else
                    {
                        t.custom_typename = this.resolve_template_type(key, names, specs);
                    };
                };
                i = 0;
                while (i < specs.len)
                {
                    typespec_free((TypeSpec*)specs.items[i]);
                    i++;
                };
                pv_free(names);
                pv_free(specs);
                return;
            };

            // Instantiates a template struct (kind 1) or object (kind 2); returns the mangled name
            // (fparser._resolve_template_struct / _resolve_template_object / _instantiate_template_node)
            def resolve_template_type(byte* key, PtrVec* names, PtrVec* specs) -> byte*
            {
                TemplateEntry* te = this.template_lookup(key);
                NameMap* map;
                Node* concrete;
                byte* mangled;
                byte* what;
                int i;
                if (te == (TemplateEntry*)0) { what = g"struct\0"; }
                elif (te.kind == 1) { what = g"struct\0"; }
                else { what = g"object\0"; };
                if (te == (TemplateEntry*)0)
                {
                    this.error(this.cat2(this.cat2(g"Unknown template struct '\0", key), g"'\0"));
                    return key;
                };
                if (te.kind != 1 & te.kind != 2)
                {
                    this.error(this.cat2(this.cat2(g"Unknown template struct '\0", key), g"'\0"));
                    return key;
                };
                if (names.len != te.params.len)
                {
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
                    return key;
                };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                this.sb.put_str(key);
                this.sb.put_str(g"__\0");
                while (i < names.len)
                {
                    if (i > 0) { this.sb.put_str(g"_\0"); };
                    this.sb.put_str((byte*)names.items[i]);
                    i++;
                };
                mangled = this.own_n(this.sb.mem, this.sb.len);
                if (nm_has(te.emitted, mangled)) { return mangled; };
                nm_put(te.emitted, mangled, (void*)te);
                map = this.tp_mapping(te, names, specs);
                concrete = node_clone(te.node);
                this.subst_node(concrete, map);
                nm_free(map);
                if (this.failed)
                {
                    node_free(concrete);
                    return mangled;
                };
                concrete.text = mangled;
                if (te.kind == 1)
                {
                    if (concrete.l4 != (NodeVec*)0) { concrete.l4.len = 0; };
                    pv_push(this.tinst_s, (void*)concrete);
                }
                else
                {
                    if (concrete.d != (Node*)0)
                    {
                        node_free(concrete.d);
                        concrete.d = (Node*)0;
                    };
                    pv_push(this.tinst_o, (void*)concrete);
                    nm_put(this.pobjs, mangled, (void*)concrete);
                    if (nm_has(this.oinit, key)) { nm_put(this.oinit, mangled, (void*)concrete); };
                };
                return mangled;
            };

            // "Key<T,U>" inside an instantiated template body whose arguments are now known
            def subst_deferred_type(byte* s, NameMap* map) -> byte*
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
                if (lt > 0)
                {
                    base = this.own_n(s, lt);
                    te = this.template_lookup(base);
                    while (i < raw.len)
                    {
                        if (nm_has(map, (byte*)raw.items[i])) { any = true; };
                        i++;
                    };
                    if (te != (TemplateEntry*)0 & any)
                    {
                        if (te.kind == 1 | te.kind == 2)
                        {
                            i = 0;
                            while (i < raw.len)
                            {
                                a = (byte*)raw.items[i];
                                if (nm_has(map, a))
                                {
                                    c = (TypeSpec*)nm_get(map, a);
                                    pv_push(names, (void*)this.ts_mangle(c));
                                    pv_push(specs, (void*)c);
                                }
                                else
                                {
                                    c = this.tmp_type();
                                    c.base_type = DataType.DATA;
                                    c.custom_typename = a;
                                    pv_push(names, (void*)a);
                                    pv_push(specs, (void*)c);
                                };
                                i++;
                            };
                            r = this.resolve_template_type(base, names, specs);
                        };
                    };
                };
                pv_free(raw);
                pv_free(names);
                pv_free(specs);
                return r;
            };

            def type_mangle_str(TypeSpec* t) -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                if (t.custom_typename != (byte*)0) { return t.custom_typename; };
                if ((t.flags `& TS_POINTER) != 0) { this.sb.put_str(g"ptr_\0"); };
                if (t.base_type == DataType.DATA & t.bit_width > 0)
                {
                    this.sb.put_str(g"data_\0");
                    if ((t.flags `& TS_POINTER) == 0 & (t.flags `& TS_SIGNED) != 0) { this.sb.put_str(g"i\0"); }
                    else { this.sb.put_str(g"u\0"); };
                    this.sb.put_int(t.bit_width);
                }
                else
                {
                    this.sb.put_str(datatype_text(t.base_type));
                };
                return this.own_n(this.sb.mem, this.sb.len);
            };

            // ===== TYPES =====

            // Token that starts a builtin or named type
            def is_type_keyword() -> bool
            {
                return this.expect4(TokenType.SINT, TokenType.UINT, TokenType.FLOAT_KW, TokenType.DOUBLE_KW) |
                       this.expect4(TokenType.SLONG, TokenType.ULONG, TokenType.CHAR, TokenType.BOOL_KW) |
                       this.expect4(TokenType.BYTE, TokenType.DATA, TokenType.VOID, TokenType.THIS) |
                       this.expect4(TokenType.STRUCT, TokenType.OBJECT, TokenType.DICT, TokenType.IDENTIFIER);
            };

            // base_type -> builtin | dict{K:V} | '' | IDENTIFIER ('::' IDENTIFIER)* | codify
            // Fills t.base_type (and custom_typename or dict_key/dict_value).
            // Returns 0 on error, 1 for a builtin, 2 for a named type, 3 for dict,
            // 4 for the "" string type.
            def base_type(TypeSpec* t) -> int
            {
                int c = this.cur();
                if (c == TokenType.SINT) { t.base_type = DataType.SINT; this.advance(); return 1; };
                if (c == TokenType.UINT) { t.base_type = DataType.UINT; this.advance(); return 1; };
                if (c == TokenType.FLOAT_KW) { t.base_type = DataType.FLOAT; this.advance(); return 1; };
                if (c == TokenType.DOUBLE_KW) { t.base_type = DataType.DOUBLE; this.advance(); return 1; };
                if (c == TokenType.SLONG) { t.base_type = DataType.SLONG; this.advance(); return 1; };
                if (c == TokenType.ULONG) { t.base_type = DataType.ULONG; this.advance(); return 1; };
                if (c == TokenType.CHAR) { t.base_type = DataType.CHAR; this.advance(); return 1; };
                if (c == TokenType.BOOL_KW) { t.base_type = DataType.BOOL; this.advance(); return 1; };
                if (c == TokenType.BYTE) { t.base_type = DataType.BYTE; this.advance(); return 1; };
                if (c == TokenType.DATA) { t.base_type = DataType.DATA; this.advance(); return 1; };
                if (c == TokenType.VOID) { t.base_type = DataType.VOID; this.advance(); return 1; };
                if (c == TokenType.THIS) { t.base_type = DataType.THIS; this.advance(); return 1; };
                if (c == TokenType.STRUCT) { t.base_type = DataType.STRUCT; this.advance(); return 1; };
                if (c == TokenType.OBJECT) { t.base_type = DataType.OBJECT; this.advance(); return 1; };
                if (c == TokenType.DICT)
                {
                    this.advance();
                    t.base_type = DataType.DICT;
                    if (!this.consume(TokenType.LEFT_BRACE)) { return 0; };
                    t.dict_key = this.type_spec();
                    if (this.failed) { return 0; };
                    if (!this.consume(TokenType.COLON)) { return 0; };
                    t.dict_value = this.type_spec();
                    if (this.failed) { return 0; };
                    if (!this.consume(TokenType.RIGHT_BRACE)) { return 0; };
                    return 3;
                };
                if (c == TokenType.STRING_LITERAL & this.cur_value_len() == 0)
                {
                    this.advance();
                    t.base_type = DataType.BYTE;
                    return 4;
                };
                if (c == TokenType.IDENTIFIER)
                {
                    byte* name = this.cur_value();
                    this.advance();
                    while (this.expect(TokenType.SCOPE))
                    {
                        this.advance();
                        if (this.expect(TokenType.IDENTIFIER))
                        {
                            name = this.cat2(this.cat2(name, g"::\0"), this.cur_value());
                            this.advance();
                        }
                        else { break; };
                    };
                    t.base_type = DataType.DATA;
                    t.custom_typename = name;
                    return 2;
                };
                if (c == TokenType.CODIFY)
                {
                    // ~$name / ~$f"..." as a type: the resolved string names a builtin or a custom type
                    byte* resolved = this.consume_codify();
                    if (this.failed) { return 0; };
                    int bt = this.codify_builtin(resolved);
                    if (bt >= 0)
                    {
                        t.base_type = bt;
                        return 1;
                    };
                    t.base_type = DataType.DATA;
                    t.custom_typename = resolved;
                    return 2;
                };
                this.error(g"Expected type specifier\0");
                return 0;
            };

            // DataType named by a codified type string, -1 when it is not a builtin type name
            def codify_builtin(byte* s) -> int
            {
                if (cstr_eq(s, g"byte\0")) { return DataType.BYTE; };
                if (cstr_eq(s, g"int\0")) { return DataType.SINT; };
                if (cstr_eq(s, g"uint\0")) { return DataType.UINT; };
                if (cstr_eq(s, g"long\0")) { return DataType.SLONG; };
                if (cstr_eq(s, g"ulong\0")) { return DataType.ULONG; };
                if (cstr_eq(s, g"float\0")) { return DataType.FLOAT; };
                if (cstr_eq(s, g"double\0")) { return DataType.DOUBLE; };
                if (cstr_eq(s, g"bool\0")) { return DataType.BOOL; };
                if (cstr_eq(s, g"char\0")) { return DataType.CHAR; };
                if (cstr_eq(s, g"void\0")) { return DataType.VOID; };
                return -1;
            };

            // Scalar fields of s into d (no shared children)
            def copy_scalar_type(TypeSpec* d, TypeSpec* s) -> void
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
                return;
            };

            // type_spec -> storage? const? volatile? (signed|unsigned)? '~'? base_type
            //              (data width)? '*'* ('[' expression? ']')* '*'*
            // Returns null with the error recorded on failure.
            def type_spec() -> TypeSpec*
            {
                TypeSpec* t = typespec_new();
                if (t == (TypeSpec*)0)
                {
                    this.fail_alloc();
                    return t;
                };
                int sc = -1;
                bool singinit_seen = false;
                bool sign_explicit = false;
                bool is_signed = false;

                if (this.expect(TokenType.SINGINIT))
                {
                    singinit_seen = true;
                    sc = StorageClass.SINGINIT;
                    this.advance();
                };
                if (this.expect(TokenType.GLOBAL)) { sc = StorageClass.GLOBAL; this.advance(); }
                elif (this.expect(TokenType.LOCAL))
                {
                    t.flags = t.flags `| TS_LOCAL;
                    sc = StorageClass.LOCAL;
                    this.advance();
                }
                elif (this.expect(TokenType.HEAP)) { sc = StorageClass.HEAP; this.advance(); }
                elif (this.expect(TokenType.STACK)) { sc = StorageClass.STACK; this.advance(); }
                elif (this.expect(TokenType.REGISTER)) { sc = StorageClass.REGISTER; this.advance(); };

                if (!singinit_seen & this.expect(TokenType.SINGINIT))
                {
                    singinit_seen = true;
                    this.advance();
                };
                if (this.expect(TokenType.CONST)) { t.flags = t.flags `| TS_CONST; this.advance(); };
                if (this.expect(TokenType.VOLATILE)) { t.flags = t.flags `| TS_VOLATILE; this.advance(); };
                if (this.expect(TokenType.SIGNED))
                {
                    is_signed = true;
                    sign_explicit = true;
                    this.advance();
                }
                elif (this.expect(TokenType.UNSIGNED))
                {
                    sign_explicit = true;
                    this.advance();
                };
                if (this.expect(TokenType.TIE)) { t.flags = t.flags `| TS_TIED; this.advance(); };
                if (is_signed) { t.flags = t.flags `| TS_SIGNED; };
                t.storage_class = sc;

                int kind = this.base_type(t);
                if (kind == 0) { return t; };

                int depth = 0;
                if (kind == 3)
                {
                    while (this.expect(TokenType.MULTIPLY))
                    {
                        depth++;
                        this.advance();
                    };
                    t.flags = t.flags `& (TS_CONST `| TS_VOLATILE);
                    if (depth > 0) { t.flags = t.flags `| TS_POINTER; };
                    t.pointer_depth = depth;
                    return t;
                };
                if (kind == 4)
                {
                    t.flags = (t.flags `& (TS_CONST `| TS_VOLATILE)) `| TS_POINTER;
                    t.pointer_depth = 1;
                    return t;
                };

                // Template arguments Name<T, U>: with no template registry yet, an angle
                // list that parses as types is folded into the type name.
                byte* tkey = (byte*)0;
                if (kind == 2 & this.expect(TokenType.LESS_THAN)) { tkey = this.tmpl_type_key(t.custom_typename); };
                if (tkey != (byte*)0)
                {
                    this.template_type_use(t, tkey);
                    if (this.failed) { return t; };
                }
                elif (kind == 2 & this.expect(TokenType.LESS_THAN))
                {
                    int m = this.mark();
                    this.advance();
                    PtrVec* names = pv_new();
                    TypeSpec* a = this.type_spec();
                    bool good = !this.failed;
                    if (good)
                    {
                        pv_push(names, (void*)this.type_mangle_str(a));
                        typespec_free(a);
                        while (this.expect(TokenType.COMMA) & good)
                        {
                            this.advance();
                            a = this.type_spec();
                            if (this.failed) { good = false; }
                            else
                            {
                                pv_push(names, (void*)this.type_mangle_str(a));
                                typespec_free(a);
                            };
                        };
                        if (good & !this.expect(TokenType.GREATER_THAN)) { good = false; };
                    };
                    if (good)
                    {
                        this.advance();
                        this.sb.len = 0;
                        this.sb.mem[0] = (byte)0;
                        this.sb.put_str(t.custom_typename);
                        this.sb.put_str(g"<\0");
                        int i;
                        while (i < names.len)
                        {
                            if (i > 0) { this.sb.put_str(g",\0"); };
                            this.sb.put_str((byte*)names.items[i]);
                            i++;
                        };
                        this.sb.put_str(g">\0");
                        t.custom_typename = this.own_n(this.sb.mem, this.sb.len);
                    }
                    else
                    {
                        this.clear_error();
                        this.reset(m);
                    };
                    pv_free(names);
                };

                // data{width:align:endian}, data!{...}
                bool nofunc = false;
                if (t.base_type == DataType.DATA & t.custom_typename == (byte*)0)
                {
                    if (this.expect(TokenType.NOT))
                    {
                        nofunc = true;
                        this.advance();
                    };
                    if (this.expect(TokenType.LEFT_BRACE))
                    {
                        this.advance();
                        bool ok;
                        if (!this.expect(TokenType.SINT_LITERAL))
                        {
                            this.fail_expected(TokenType.SINT_LITERAL);
                            return t;
                        };
                        t.bit_width = (int)this.parse_int(this.cur_value(), @ok);
                        this.advance();
                        if (this.expect(TokenType.COLON))
                        {
                            this.advance();
                            if (!this.expect(TokenType.SINT_LITERAL))
                            {
                                this.fail_expected(TokenType.SINT_LITERAL);
                                return t;
                            };
                            t.alignment = (int)this.parse_int(this.cur_value(), @ok);
                            this.advance();
                            if (this.expect(TokenType.COLON))
                            {
                                this.advance();
                                if (!this.expect(TokenType.SINT_LITERAL))
                                {
                                    this.fail_expected(TokenType.SINT_LITERAL);
                                    return t;
                                };
                                t.endianness = (int)this.parse_int(this.cur_value(), @ok);
                                this.advance();
                            };
                        }
                        elif (this.expect(TokenType.SCOPE))
                        {
                            this.advance();
                            t.alignment = t.bit_width;
                            if (!this.expect(TokenType.SINT_LITERAL))
                            {
                                this.fail_expected(TokenType.SINT_LITERAL);
                                return t;
                            };
                            t.endianness = (int)this.parse_int(this.cur_value(), @ok);
                            this.advance();
                        };
                        if (!this.consume(TokenType.RIGHT_BRACE)) { return t; };
                    };
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
                    if (dims == (NodeVec*)0) { dims = nv_new(); };
                    if (!this.expect(TokenType.RIGHT_BRACKET))
                    {
                        dim = this.expression();
                        if (this.failed) { return t; };
                        nv_push(dims, dim);
                    }
                    else { nv_push(dims, (Node*)0); };
                    if (!this.consume(TokenType.RIGHT_BRACKET)) { return t; };
                };
                while (this.expect(TokenType.MULTIPLY))
                {
                    pdepth++;
                    this.advance();
                };
                bool is_array = dims != (NodeVec*)0;

                // A named type that is an alias takes the aliased type's fields
                if (t.custom_typename != (byte*)0 & this.st != (FXC_SYMTABLE*)0)
                {
                    TypeSpec* rs = st_get_type_spec(this.st, t.custom_typename);
                    if (rs != (TypeSpec*)0)
                    {
                        if (rs.base_type != DataType.DICT & rs.base_type != DataType.FUNC_PTR)
                        {
                            bool alias_arr = (rs.flags `& TS_ARRAY) != 0;
                            int keep_sc = t.storage_class;
                            int keep_flags = t.flags;
                            this.copy_scalar_type(t, rs);
                            t.flags = t.flags `| (keep_flags `& (TS_TIED `| TS_CONST `| TS_VOLATILE));
                            if (keep_sc != -1)
                            {
                                t.storage_class = keep_sc;
                                if (keep_sc == StorageClass.LOCAL) { t.flags = t.flags `| TS_LOCAL; }
                                elif ((t.flags `& TS_LOCAL) != 0) { t.flags = t.flags - TS_LOCAL; };
                            };
                            if (sign_explicit)
                            {
                                if (is_signed) { t.flags = t.flags `| TS_SIGNED; }
                                elif ((t.flags `& TS_SIGNED) != 0) { t.flags = t.flags - TS_SIGNED; };
                            };
                            if (alias_arr)
                            {
                                // Use-site dimensions come first, then the alias dimensions
                                NodeVec* nd = nv_new();
                                int di;
                                if (is_array)
                                {
                                    while (di < dims.len)
                                    {
                                        nv_push(nd, dims.items[di]);
                                        di++;
                                    };
                                    dims.len = 0;
                                    nv_free(dims);
                                };
                                if (rs.array_dims != (NodeVec*)0)
                                {
                                    di = 0;
                                    while (di < rs.array_dims.len)
                                    {
                                        nv_push(nd, node_clone(rs.array_dims.items[di]));
                                        di++;
                                    };
                                };
                                t.flags = t.flags `| TS_ARRAY;
                                t.array_dims = nd;
                                if (nd.len > 0) { t.array_size = nd.items[0]; };
                                if (rs.array_elem != (TypeSpec*)0) { t.array_elem = typespec_copy(rs.array_elem); }
                                else
                                {
                                    TypeSpec* ael = typespec_new();
                                    this.copy_scalar_type(ael, t);
                                    ael.flags = ael.flags `& (TS_SIGNED `| TS_CONST `| TS_VOLATILE);
                                    ael.pointer_depth = 0;
                                    t.array_elem = ael;
                                };
                            }
                            elif (is_array)
                            {
                                t.flags = t.flags `| TS_ARRAY;
                                t.array_dims = dims;
                                t.array_size = dims.items[0];
                                TypeSpec* el = typespec_new();
                                this.copy_scalar_type(el, t);
                                el.flags = el.flags `& (TS_SIGNED `| TS_CONST `| TS_VOLATILE);
                                el.pointer_depth = 0;
                                t.array_elem = el;
                            };
                            if (pdepth > 0)
                            {
                                t.flags = t.flags `| TS_POINTER;
                                t.pointer_depth = t.pointer_depth + pdepth;
                            };
                            return t;
                        };
                    };
                };

                if (t.base_type == DataType.BYTE & t.bit_width < 0)
                {
                    t.bit_width = this.default_byte_width;
                    if (t.alignment < 0) { t.alignment = t.bit_width; };
                };
                if (nofunc) { t.flags = t.flags `| TS_NO_FUNCTIONS; };
                if (is_array)
                {
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
                };
                if (pdepth > 0)
                {
                    t.flags = t.flags `| TS_POINTER;
                    t.pointer_depth = pdepth;
                };
                return t;
            };

            // ===== EXPRESSIONS =====

            // Token types that can start an operand. Used to detect a missing operator.
            def starts_operand() -> bool
            {
                return this.expect4(TokenType.IDENTIFIER, TokenType.SINT_LITERAL, TokenType.UINT_LITERAL, TokenType.SLONG_LITERAL) |
                       this.expect4(TokenType.ULONG_LITERAL, TokenType.FLOAT, TokenType.DOUBLE, TokenType.CHAR) |
                       this.expect4(TokenType.STRING_LITERAL, TokenType.F_STRING, TokenType.G_STRING, TokenType.I_STRING) |
                       this.expect4(TokenType.TRUE, TokenType.FALSE, TokenType.VOID, TokenType.THIS) |
                       this.expect4(TokenType.NO_INIT, TokenType.LEFT_PAREN, TokenType.LEFT_BRACKET, TokenType.ELLIPSIS);
            };

            def error_missing_operator() -> void
            {
                this.error(this.cat2(this.cat2(g"Unexpected '\0", this.cur_value()),
                                     g"' in expression - missing operator before this token?\0"));
                return;
            };

            // expression -> assignment_expression
            def expression() -> Node*
            {
                return this.assignment_expression();
            };

            def is_compound_assign() -> bool
            {
                return this.expect4(TokenType.PLUS_ASSIGN, TokenType.MINUS_ASSIGN, TokenType.MULTIPLY_ASSIGN, TokenType.DIVIDE_ASSIGN) |
                       this.expect4(TokenType.MODULO_ASSIGN, TokenType.EXPONENT_ASSIGN, TokenType.XOR_ASSIGN, TokenType.BITXOR_ASSIGN) |
                       this.expect4(TokenType.BITXNOR_ASSIGN, TokenType.BITSHIFT_LEFT_ASSIGN, TokenType.BITSHIFT_RIGHT_ASSIGN, TokenType.BITAND_ASSIGN) |
                       this.expect4(TokenType.BITOR_ASSIGN, TokenType.BITNAND_ASSIGN, TokenType.BITNOR_ASSIGN, TokenType.OR_ASSIGN) |
                       this.expect(TokenType.AND_ASSIGN);
            };

            // assignment_expression -> ternary (('=' | op= | '@=' | '?=') assignment_expression)?
            def assignment_expression() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* expr = this.ternary_expression();
                if (this.failed) { return expr; };
                Node* n;
                Node* value;
                if (this.expect(TokenType.ASSIGN))
                {
                    this.advance();
                    if (this.expect(TokenType.DITTO))
                    {
                        this.advance();
                        Node* prev = this.last_stmt;
                        if (prev == (Node*)0)
                        {
                            this.error(g"Ditto in assignment: no preceding statement to repeat\0");
                            return expr;
                        };
                        Node* inner = prev;
                        if (prev.kind == NodeKind.EXPRESSION_STATEMENT) { inner = prev.a; };
                        if (inner == (Node*)0)
                        {
                            this.error(g"Ditto in assignment: preceding statement is not an assignment\0");
                            return expr;
                        };
                        if (inner.kind != NodeKind.ASSIGNMENT)
                        {
                            this.error(g"Ditto in assignment: preceding statement is not an assignment\0");
                            return expr;
                        };
                        value = node_clone(inner.b);
                    }
                    else
                    {
                        value = this.assignment_expression();
                        if (this.failed) { return expr; };
                    };
                    n = this.mk(NodeKind.ASSIGNMENT, line, col);
                    if (this.failed) { return expr; };
                    n.a = expr;
                    n.b = value;
                    return n;
                };
                if (this.is_compound_assign())
                {
                    int optok = this.cur();
                    this.advance();
                    value = this.assignment_expression();
                    if (this.failed) { return expr; };
                    n = this.mk(NodeKind.COMPOUND_ASSIGNMENT, line, col);
                    if (this.failed) { return expr; };
                    n.op = optok;
                    n.a = expr;
                    n.b = value;
                    return n;
                };
                if (this.expect(TokenType.ADDRESS_ASSIGN))
                {
                    int al = this.cur_line();
                    int ac = this.cur_col();
                    this.advance();
                    Node* rhs = this.assignment_expression();
                    if (this.failed) { return expr; };
                    Node* addr = this.mk(NodeKind.ADDRESS_OF, al, ac);
                    if (this.failed) { return expr; };
                    addr.a = rhs;
                    n = this.mk(NodeKind.ASSIGNMENT, line, col);
                    if (this.failed) { return expr; };
                    n.a = expr;
                    n.b = addr;
                    return n;
                };
                if (this.expect(TokenType.TERNARY_ASSIGN))
                {
                    this.advance();
                    value = this.assignment_expression();
                    if (this.failed) { return expr; };
                    n = this.mk(NodeKind.TERNARY_ASSIGN, line, col);
                    if (this.failed) { return expr; };
                    n.a = expr;
                    n.b = value;
                    return n;
                };
                return expr;
            };

            // ternary_expression -> null_coalesce ('?' expression ':' ternary)?
            def ternary_expression() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* expr = this.null_coalesce_expression();
                if (this.failed) { return expr; };
                if (this.expect(TokenType.QUESTION))
                {
                    this.advance();
                    Node* t = this.expression();
                    if (this.failed) { return expr; };
                    if (!this.consume(TokenType.COLON)) { return expr; };
                    Node* f = this.ternary_expression();
                    if (this.failed) { return expr; };
                    Node* n = this.mk(NodeKind.TERNARY_OP, line, col);
                    if (this.failed) { return expr; };
                    n.a = expr;
                    n.b = t;
                    n.c = f;
                    return n;
                };
                return expr;
            };

            // null_coalesce_expression -> logical_or ('??' null_coalesce)?
            def null_coalesce_expression() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* expr = this.bin_level(0);
                if (this.failed) { return expr; };
                if (this.expect(TokenType.NULL_COALESCE))
                {
                    this.advance();
                    Node* r = this.null_coalesce_expression();
                    if (this.failed) { return expr; };
                    Node* n = this.mk(NodeKind.NULL_COALESCE, line, col);
                    if (this.failed) { return expr; };
                    n.a = expr;
                    n.b = r;
                    return n;
                };
                return expr;
            };

            // Operator at the current token for left associative level lv, or -1.
            //   0 or   1 and   2 xor   3 bitor   4 bitxor   5 bitand
            //   6 relational   7 shift   8 additive   9 multiplicative
            def bin_match(int lv) -> int
            {
                int c = this.cur();
                if (lv == 9 & this.cop_mask != 0)
                {
                    if (this.cop_right_here()) { return -1; };
                };
                if (lv == 0) { if (c == TokenType.LOGICAL_OR | c == TokenType.OR) { return Operator.OR; }; }
                elif (lv == 1) { if (c == TokenType.LOGICAL_AND | c == TokenType.AND) { return Operator.AND; }; }
                elif (lv == 2) { if (c == TokenType.XOR_OP | c == TokenType.XOR) { return Operator.XOR; }; }
                elif (lv == 3)
                {
                    if (c == TokenType.BITOR_OP) { return Operator.BITOR; };
                    if (c == TokenType.BITNOR_OP) { return Operator.BITNOR; };
                }
                elif (lv == 4)
                {
                    if (c == TokenType.BITXOR_OP) { return Operator.BITXOR; };
                    if (c == TokenType.BITXNOR) { return Operator.BITXNOR; };
                }
                elif (lv == 5)
                {
                    if (c == TokenType.BITAND_OP) { return Operator.BITAND; };
                    if (c == TokenType.BITNAND_OP) { return Operator.BITNAND; };
                }
                elif (lv == 6)
                {
                    if (c == TokenType.LESS_THAN) { return Operator.LESS_THAN; };
                    if (c == TokenType.LESS_EQUAL) { return Operator.LESS_EQUAL; };
                    if (c == TokenType.GREATER_THAN) { return Operator.GREATER_THAN; };
                    if (c == TokenType.GREATER_EQUAL) { return Operator.GREATER_EQUAL; };
                }
                elif (lv == 7)
                {
                    if (c == TokenType.BITSHIFT_LEFT) { return Operator.BITSHIFT_LEFT; };
                    if (c == TokenType.BITSHIFT_RIGHT) { return Operator.BITSHIFT_RIGHT; };
                }
                elif (lv == 8)
                {
                    if (c == TokenType.PLUS) { return Operator.ADD; };
                    if (c == TokenType.MINUS) { return Operator.SUB; };
                }
                elif (lv == 9)
                {
                    if (c == TokenType.MULTIPLY) { return Operator.MUL; };
                    if (c == TokenType.DIVIDE) { return Operator.DIV; };
                    if (c == TokenType.MODULO) { return Operator.MOD; };
                    if (c == TokenType.EXPONENT) { return Operator.POWER; };
                };
                return -1;
            };

            // The operand parser one level tighter than lv
            def bin_next(int lv) -> Node*
            {
                if (lv < 5) { return this.bin_level(lv + 1); };
                if (lv == 5) { return this.equality_expression(); };
                if (lv == 6) { return this.bin_level(7); };
                if (lv == 7) { return this.range_expression(); };
                if (lv == 8) { return this.custom_op_expression(); };
                return this.cast_expression();
            };

            // One left associative binary level
            def bin_level(int lv) -> Node*
            {
                Node* expr = this.bin_next(lv);
                if (this.failed) { return expr; };
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
                    if (this.failed) { return expr; };
                    n = this.mk(NodeKind.BINARY_OP, line, col);
                    if (this.failed) { return expr; };
                    n.op = op;
                    n.a = expr;
                    n.b = right;
                    expr = n;
                    this.try_template_op(n);
                    if (this.failed) { return expr; };
                    op = this.bin_match(lv);
                };
                if (lv >= 8 & this.starts_operand() & !this.at_custom_op())
                {
                    this.error_missing_operator();
                };
                return expr;
            };

            // equality_expression -> chain (('==' | '!=' | 'is' | 'in' | '!in' | 'has') chain)*
            def equality_expression() -> Node*
            {
                Node* expr = this.chain_expression();
                if (this.failed) { return expr; };
                Node* n;
                Node* r;
                int line, col, c;
                while (true)
                {
                    line = this.cur_line();
                    col = this.cur_col();
                    c = this.cur();
                    if (c == TokenType.NOT & this.type_at(1) == TokenType.IN)
                    {
                        this.advance();
                        this.advance();
                        r = this.chain_expression();
                        if (this.failed) { return expr; };
                        n = this.mk(NodeKind.IN_EXPRESSION, line, col);
                        if (this.failed) { return expr; };
                        n.flags = NF_NEGATED;
                        n.a = expr;
                        n.b = r;
                        expr = n;
                        continue;
                    };
                    if (c == TokenType.IN)
                    {
                        this.advance();
                        r = this.chain_expression();
                        if (this.failed) { return expr; };
                        n = this.mk(NodeKind.IN_EXPRESSION, line, col);
                        if (this.failed) { return expr; };
                        n.a = expr;
                        n.b = r;
                        expr = n;
                    }
                    elif (c == TokenType.HAS)
                    {
                        this.advance();
                        if (!this.expect(TokenType.IDENTIFIER))
                        {
                            this.error(g"Expected trait name after 'has'\0");
                            return expr;
                        };
                        n = this.mk(NodeKind.HAS_EXPRESSION, line, col);
                        if (this.failed) { return expr; };
                        n.text = this.cur_value();
                        this.advance();
                        n.a = expr;
                        expr = n;
                    }
                    elif (c == TokenType.IS | c == TokenType.EQUAL | c == TokenType.NOT_EQUAL)
                    {
                        this.advance();
                        r = this.chain_expression();
                        if (this.failed) { return expr; };
                        n = this.mk(NodeKind.BINARY_OP, line, col);
                        if (this.failed) { return expr; };
                        if (c == TokenType.NOT_EQUAL) { n.op = Operator.NOT_EQUAL; }
                        else { n.op = Operator.EQUAL; };
                        n.a = expr;
                        n.b = r;
                        expr = n;
                        this.try_template_op(n);
                        if (this.failed) { return expr; };
                    }
                    else { break; };
                };
                return expr;
            };

            // chain_expression -> relational ('<-' chain)?   (right is pushed to the call's front)
            def chain_expression() -> Node*
            {
                Node* expr = this.bin_level(6);
                if (this.failed) { return expr; };
                if (this.expect(TokenType.CHAIN_ARROW))
                {
                    this.advance();
                    Node* right = this.chain_expression();
                    if (this.failed) { return expr; };
                    if (expr.kind != NodeKind.FUNCTION_CALL)
                    {
                        this.error(g"Chain arrow requires function call on left side\0");
                        return expr;
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
                    return expr;
                };
                return expr;
            };

            // range_expression -> arithmetic ('..' arithmetic)?
            def range_expression() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* expr = this.bin_level(8);
                if (this.failed) { return expr; };
                if (this.expect(TokenType.RANGE))
                {
                    this.advance();
                    Node* end = this.bin_level(8);
                    if (this.failed) { return expr; };
                    Node* n = this.mk(NodeKind.RANGE_EXPRESSION, line, col);
                    if (this.failed) { return expr; };
                    n.a = expr;
                    n.b = end;
                    return n;
                };
                return expr;
            };

            // Speculative parse of '(' type_spec ')' unary. Returns null when it is not a cast.
            def try_cast() -> Node*
            {
                int m = this.mark();
                int line = this.cur_line();
                int col = this.cur_col();
                this.advance();
                TypeSpec* ts = this.type_spec();
                if (!this.failed & this.expect(TokenType.RIGHT_PAREN))
                {
                    this.advance();
                    Node* inner = this.cast_expression();
                    if (!this.failed)
                    {
                        Node* n = this.mk(NodeKind.CAST_EXPRESSION, line, col);
                        if (this.failed) { return (Node*)0; };
                        n.ts = ts;
                        n.a = inner;
                        return n;
                    };
                };
                typespec_free(ts);
                this.clear_error();
                this.reset(m);
                return (Node*)0;
            };

            // cast_expression -> ('(' type_spec ')')? unary_expression
            def cast_expression() -> Node*
            {
                if (this.expect(TokenType.LEFT_PAREN))
                {
                    Node* c = this.try_cast();
                    if (c != (Node*)0) { return c; };
                    if (this.failed) { return c; };
                };
                return this.unary_expression();
            };

            def unary_node(int op, int line, int col, Node* operand) -> Node*
            {
                if (this.failed) { return operand; };
                Node* n = this.mk(NodeKind.UNARY_OP, line, col);
                if (this.failed) { return operand; };
                n.op = op;
                n.a = operand;
                return n;
            };

            def unary_expression() -> Node*
            {
                int c = this.cur();
                int line = this.cur_line();
                int col = this.cur_col();
                Node* operand;
                Node* n;
                int op = -1;
                bool via_cast = false;

                if (c == TokenType.IS) { op = Operator.EQUAL; }
                elif (c == TokenType.NOT) { op = Operator.NOT; }
                elif (c == TokenType.BITNOT_OP) { op = Operator.BITNOT; }
                elif (c == TokenType.BITXNOT) { op = Operator.BITXNOT; }
                elif (c == TokenType.BITXNAND) { op = Operator.BITXNAND; }
                elif (c == TokenType.BITXNOR) { op = Operator.BITXNOR; }
                elif (c == TokenType.INCREMENT) { op = Operator.INCREMENT; }
                elif (c == TokenType.DECREMENT) { op = Operator.DECREMENT; }
                elif (c == TokenType.MINUS) { op = Operator.SUB; via_cast = true; }
                elif (c == TokenType.PLUS) { op = Operator.ADD; via_cast = true; };

                if (op >= 0)
                {
                    this.advance();
                    if (via_cast) { operand = this.cast_expression(); }
                    else { operand = this.unary_expression(); };
                    return this.unary_node(op, line, col, operand);
                };
                if (c == TokenType.MULTIPLY)
                {
                    this.advance();
                    operand = this.cast_expression();
                    if (this.failed) { return operand; };
                    n = this.mk(NodeKind.POINTER_DEREF, line, col);
                    if (this.failed) { return operand; };
                    n.a = operand;
                    return n;
                };
                if (c == TokenType.ADDRESS_OF)
                {
                    this.advance();
                    operand = this.unary_expression();
                    if (this.failed) { return operand; };
                    n = this.mk(NodeKind.ADDRESS_OF, line, col);
                    if (this.failed) { return operand; };
                    n.a = operand;
                    return n;
                };
                if (c == TokenType.ADDRESS_CAST)
                {
                    this.advance();
                    operand = this.unary_expression();
                    if (this.failed) { return operand; };
                    n = this.mk(NodeKind.CAST_EXPRESSION, line, col);
                    if (this.failed) { return operand; };
                    TypeSpec* vp = typespec_new();
                    vp.base_type = DataType.VOID;
                    vp.flags = TS_POINTER;
                    vp.pointer_depth = 1;
                    n.ts = vp;
                    n.a = operand;
                    return n;
                };
                Node* cu = this.custom_unary();
                if (cu != (Node*)0 | this.failed) { return cu; };
                return this.postfix_expression();
            };

            // argument_list -> expression (',' expression)*   (pushed onto holder.l0)
            // callee is the called name for ditto, or null.
            def argument_list(Node* holder, byte* callee) -> void
            {
                Node* a;
                int pos;
                Node* prev;
                while (true)
                {
                    if (callee != (byte*)0 & this.expect(TokenType.DITTO))
                    {
                        prev = this.last_call;
                        if (prev == (Node*)0)
                        {
                            this.error(g"Ditto in argument list: previous statement is not a function call\0");
                            return;
                        };
                        if (prev.text != (byte*)0)
                        {
                            if (!cstr_eq(prev.text, callee))
                            {
                                this.error(g"Ditto in argument list: previous call was to a different function\0");
                                return;
                            };
                        };
                        if (pos >= node_count(prev, 0))
                        {
                            this.error(g"Ditto in argument list: argument position is out of range\0");
                            return;
                        };
                        this.advance();
                        a = node_clone(node_child(prev, 0, pos));
                    }
                    else
                    {
                        a = this.expression();
                        if (this.failed) { return; };
                    };
                    node_push(holder, 0, a);
                    pos++;
                    if (!this.expect(TokenType.COMMA)) { break; };
                    this.advance();
                };
                return;
            };

            // Moves the arguments collected in holder into call.l0 and frees holder
            def take_args(Node* call, Node* holder) -> void
            {
                call.l0 = holder.l0;
                holder.l0 = (NodeVec*)0;
                node_free(holder);
                return;
            };

            // postfix_expression -> '~'? primary (index | call | '.' name | '++' | '--' | '!!' | as | from | if)*
            def postfix_expression() -> Node*
            {
                int tl = 0;
                int tc = 0;
                bool tied = false;
                if (this.expect(TokenType.TIE))
                {
                    tied = true;
                    tl = this.cur_line();
                    tc = this.cur_col();
                    this.advance();
                };
                Node* expr = this.primary_expression();
                if (this.failed) { return expr; };
                Node* n;
                COp* pc;
                if (tied)
                {
                    n = this.mk(NodeKind.TIE_EXPRESSION, tl, tc);
                    if (this.failed) { return expr; };
                    n.a = expr;
                    expr = n;
                };

                // explicit foo<int>(x) or inferred foo(x) call of a template function
                expr = this.template_call(expr);
                if (this.failed) { return expr; };

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
                    if (this.expect(TokenType.LEFT_BRACKET))
                    {
                        this.advance();
                        if (this.expect(TokenType.BACKTICK))
                        {
                            this.advance();
                            idx = this.expression();
                            if (this.failed) { return expr; };
                            if (!this.consume(TokenType.RIGHT_BRACKET)) { return expr; };
                            n = this.mk(NodeKind.BIT_INDEX_ACCESS, line, col);
                            if (this.failed) { return expr; };
                            n.a = expr;
                            n.b = idx;
                            expr = n;
                            continue;
                        };
                        idx = this.expression();
                        if (this.failed) { return expr; };
                        if (this.expect(TokenType.BITSLICE))
                        {
                            this.advance();
                            end = this.expression();
                            if (this.failed) { return expr; };
                            if (!this.consume(TokenType.RIGHT_BRACKET)) { return expr; };
                            n = this.mk(NodeKind.BIT_SLICE, line, col);
                            if (this.failed) { return expr; };
                            n.a = expr;
                            n.b = idx;
                            n.c = end;
                            expr = n;
                        }
                        elif (this.expect(TokenType.COLON))
                        {
                            this.advance();
                            end = this.expression();
                            if (this.failed) { return expr; };
                            if (!this.consume(TokenType.RIGHT_BRACKET)) { return expr; };
                            n = this.mk(NodeKind.ARRAY_SLICE, line, col);
                            if (this.failed) { return expr; };
                            n.a = expr;
                            n.b = idx;
                            n.c = end;
                            expr = n;
                        }
                        else
                        {
                            if (!this.consume(TokenType.RIGHT_BRACKET)) { return expr; };
                            if (idx.kind == NodeKind.RANGE_EXPRESSION & this.expect(TokenType.ASSIGN))
                            {
                                this.advance();
                                if (!this.consume(TokenType.LEFT_BRACE)) { return expr; };
                                fill = this.expression();
                                if (this.failed) { return expr; };
                                if (!this.consume(TokenType.RIGHT_BRACE)) { return expr; };
                                n = this.mk(NodeKind.RANGE_ASSIGNMENT, line, col);
                                if (this.failed) { return expr; };
                                n.a = expr;
                                n.b = idx.a;
                                n.c = idx.b;
                                n.d = fill;
                                idx.a = (Node*)0;
                                idx.b = (Node*)0;
                                node_free(idx);
                                expr = n;
                                break;
                            };
                            n = this.mk(NodeKind.ARRAY_ACCESS, line, col);
                            if (this.failed) { return expr; };
                            n.a = expr;
                            n.b = idx;
                            expr = n;
                        };
                    }
                    elif (this.expect(TokenType.LEFT_PAREN))
                    {
                        this.advance();
                        holder = this.mk(NodeKind.NODE_LIST, line, col);
                        if (this.failed) { return expr; };
                        callee = (byte*)0;
                        if (expr.kind == NodeKind.IDENTIFIER) { callee = expr.text; };
                        if (!this.expect(TokenType.RIGHT_PAREN))
                        {
                            this.argument_list(holder, callee);
                            if (this.failed) { return expr; };
                        };
                        if (!this.consume(TokenType.RIGHT_PAREN)) { return expr; };
                        if (expr.kind == NodeKind.IDENTIFIER)
                        {
                            // a defined macro name makes a macro invocation, not a function call
                            if (nm_has(this.macros, expr.text)) { n = this.mk(NodeKind.MACRO_CALL, line, col); }
                            else { n = this.mk(NodeKind.FUNCTION_CALL, line, col); };
                            if (this.failed) { return expr; };
                            n.text = expr.text;
                            this.take_args(n, holder);
                        }
                        elif (expr.kind == NodeKind.STRING_LITERAL)
                        {
                            n = this.mk(NodeKind.FUNCTION_CALL, line, col);
                            if (this.failed) { return expr; };
                            n.text = expr.text;
                            this.take_args(n, holder);
                        }
                        elif (expr.kind == NodeKind.F_STRING_LITERAL | expr.kind == NodeKind.STRINGIFY)
                        {
                            n = this.mk(NodeKind.FUNCTION_CALL, line, col);
                            if (this.failed) { return expr; };
                            n.a = expr;
                            expr = (Node*)0;
                            this.take_args(n, holder);
                        }
                        elif (expr.kind == NodeKind.MEMBER_ACCESS)
                        {
                            n = (Node*)0;
                            if (expr.text2 != (byte*)0) { n = this.typefunc_call_implicit(expr, holder, line, col); };
                            if (this.failed) { return expr; };
                            if (n != (Node*)0)
                            {
                                this.take_args(n, holder);
                                this.push_front(n, expr.a);
                                expr.a = (Node*)0;
                            }
                            else
                            {
                                n = this.mk(NodeKind.METHOD_CALL, line, col);
                                if (this.failed) { return expr; };
                                n.a = expr.a;
                                n.text = expr.text;
                                expr.a = (Node*)0;
                                this.take_args(n, holder);
                            };
                        }
                        else
                        {
                            this.error(g"Cannot call function on complex expression\0");
                            return expr;
                        };
                        if (expr != (Node*)0) { node_free(expr); };
                        expr = n;
                    }
                    elif (this.expect(TokenType.DOT))
                    {
                        this.advance();
                        member = (byte*)0;
                        if (this.expect(TokenType.F_STRING) | this.expect(TokenType.I_STRING))
                        {
                            fsn = this.fstr_node();
                            if (this.failed) { return expr; };
                            member = this.fstr_resolve(fsn);
                            node_free(fsn);
                            if (member == (byte*)0)
                            {
                                this.error(g"The member name could not be resolved at parse time\0");
                                return expr;
                            };
                        }
                        elif (this.expect(TokenType.STRING_LITERAL))
                        {
                            member = this.cur_value();
                            this.advance();
                        }
                        elif (this.expect(TokenType.TAG))
                        {
                            this.advance();
                            member = g"#\0";
                        }
                        else
                        {
                            if (!this.expect(TokenType.IDENTIFIER))
                            {
                                this.fail_expected(TokenType.IDENTIFIER);
                                return expr;
                            };
                            member = this.cur_value();
                            this.advance();
                        };
                        tkey = this.typefunc_key(expr, member);
                        if (this.expect(TokenType.LESS_THAN))
                        {
                            qkey = (byte*)0;
                            if (expr.kind == NodeKind.IDENTIFIER)
                            {
                                qkey = this.cat2(this.cat2(expr.text, g".\0"), member);
                                if (this.template_lookup(qkey) == (TemplateEntry*)0) { qkey = (byte*)0; };
                            };
                            if (qkey != (byte*)0)
                            {
                                expr = this.template_method_explicit(expr, qkey, false);
                                if (this.failed) { return expr; };
                                continue;
                            };
                            if (tkey != (byte*)0)
                            {
                                expr = this.template_method_explicit(expr, tkey, true);
                                if (this.failed) { return expr; };
                                continue;
                            };
                        };
                        n = this.mk(NodeKind.MEMBER_ACCESS, line, col);
                        if (this.failed) { return expr; };
                        n.a = expr;
                        n.text = member;
                        if (tkey != (byte*)0 & this.expect(TokenType.LEFT_PAREN)) { n.text2 = tkey; };
                        expr = n;
                    }
                    elif (this.expect(TokenType.INCREMENT) | this.expect(TokenType.DECREMENT))
                    {
                        pop = Operator.INCREMENT;
                        if (this.expect(TokenType.DECREMENT)) { pop = Operator.DECREMENT; };
                        this.advance();
                        n = this.unary_node(pop, line, col, expr);
                        if (this.failed) { return expr; };
                        n.flags = NF_POSTFIX;
                        expr = n;
                    }
                    elif (this.expect(TokenType.NOT_NULL))
                    {
                        this.advance();
                        n = this.mk(NodeKind.NOT_NULL, line, col);
                        if (this.failed) { return expr; };
                        n.a = expr;
                        expr = n;
                    }
                    elif (this.expect(TokenType.AS))
                    {
                        this.advance();
                        target = this.type_spec();
                        if (this.failed) { return expr; };
                        if (target.custom_typename != (byte*)0)
                        {
                            n = this.mk(NodeKind.STRUCT_RECAST, line, col);
                            if (this.failed) { return expr; };
                            n.text = target.custom_typename;
                            n.a = expr;
                            typespec_free(target);
                        }
                        else
                        {
                            n = this.mk(NodeKind.CAST_EXPRESSION, line, col);
                            if (this.failed) { return expr; };
                            n.ts = target;
                            n.a = expr;
                        };
                        expr = n;
                    }
                    elif (this.expect(TokenType.FROM))
                    {
                        this.advance();
                        src = this.postfix_expression();
                        if (this.failed) { return expr; };
                        if (expr.kind != NodeKind.IDENTIFIER)
                        {
                            this.error(g"Expected struct type name before 'from' keyword\0");
                            return expr;
                        };
                        n = this.mk(NodeKind.STRUCT_RECAST, line, col);
                        if (this.failed) { return expr; };
                        n.text = expr.text;
                        n.a = src;
                        node_free(expr);
                        expr = n;
                    }
                    elif (this.expect(TokenType.IF))
                    {
                        this.advance();
                        if (!this.consume(TokenType.LEFT_PAREN)) { return expr; };
                        cond = this.expression();
                        if (this.failed) { return expr; };
                        if (!this.consume(TokenType.RIGHT_PAREN)) { return expr; };
                        els = (Node*)0;
                        if (this.expect(TokenType.ELSE))
                        {
                            this.advance();
                            els = this.postfix_expression();
                            if (this.failed) { return expr; };
                        };
                        n = this.mk(NodeKind.IF_EXPRESSION, line, col);
                        if (this.failed) { return expr; };
                        n.a = expr;
                        n.b = cond;
                        n.c = els;
                        expr = n;
                    }
                    else
                    {
                        pc = this.cop_best(3);
                        if (pc == (COp*)0) { break; };
                        n = this.op_call(pc.func, this.cur_line(), this.cur_col());
                        if (this.failed) { return expr; };
                        this.skip_tokens(pc.left.n);
                        node_push(n, 0, expr);
                        expr = n;
                    };
                };
                return expr;
            };

            // Literal node of a data type at the current token position
            def lit(int dt, i64 v, int line, int col) -> Node*
            {
                Node* n = this.mk(NodeKind.LITERAL, line, col);
                if (this.failed) { return n; };
                n.op = dt;
                n.ival = v;
                return n;
            };

            // Integer literal of the current token
            def int_literal(int dt) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                bool ok;
                i64 v = this.parse_int(this.cur_value(), @ok);
                if (!ok)
                {
                    this.error(g"Invalid integer literal\0");
                    return (Node*)0;
                };
                Node* n = this.lit(dt, v, line, col);
                if (this.failed) { return n; };
                n.text = this.cur_value();
                this.advance();
                return n;
            };

            def is_type_start_kw() -> bool
            {
                return this.expect4(TokenType.SINT, TokenType.FLOAT_KW, TokenType.DOUBLE_KW, TokenType.CHAR) |
                       this.expect4(TokenType.BOOL_KW, TokenType.DATA, TokenType.VOID, TokenType.SLONG) |
                       this.expect4(TokenType.ULONG, TokenType.CONST, TokenType.VOLATILE, TokenType.SIGNED) |
                       this.expect(TokenType.UNSIGNED);
            };

            // '(' already consumed. Parses a type then ')', or an expression then ')'.
            // want_type_first picks which form is tried first; the other is the fallback.
            // allow_ident_type makes a leading identifier try the type form first too (endianof).
            def type_or_expr(int kind, int line, int col, bool type_first) -> Node*
            {
                Node* n = this.mk(kind, line, col);
                if (this.failed) { return n; };
                int m = this.mark();
                int pass;
                bool as_type;
                TypeSpec* ts;
                Node* e;
                while (pass < 2)
                {
                    as_type = type_first;
                    if (pass == 1) { as_type = !type_first; };
                    if (as_type)
                    {
                        ts = this.type_spec();
                        if (!this.failed & this.expect(TokenType.RIGHT_PAREN))
                        {
                            this.advance();
                            n.ts = ts;
                            return n;
                        };
                        if (!this.failed) { this.fail_expected(TokenType.RIGHT_PAREN); };
                        typespec_free(ts);
                    }
                    else
                    {
                        e = this.expression();
                        if (!this.failed & this.expect(TokenType.RIGHT_PAREN))
                        {
                            this.advance();
                            n.a = e;
                            return n;
                        };
                        if (!this.failed) { this.fail_expected(TokenType.RIGHT_PAREN); };
                        node_free(e);
                    };
                    if (pass == 0)
                    {
                        this.clear_error();
                        this.reset(m);
                    };
                    pass++;
                };
                return n;
            };

            // sizeof / alignof / endianof / typeof '(' (type | expression) ')'
            def type_query(int kind, int kw) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.advance();
                if (!this.consume(TokenType.LEFT_PAREN)) { return (Node*)0; };
                bool type_first;
                if (kind == NodeKind.ALIGN_OF) { type_first = true; }
                elif (kind == NodeKind.ENDIAN_OF)
                {
                    type_first = this.is_type_start_kw() | this.expect(TokenType.IDENTIFIER);
                }
                else { type_first = this.is_type_start_kw(); };
                return this.type_or_expr(kind, line, col, type_first);
            };

            def array_literal() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.advance();
                Node* n;
                if (this.expect(TokenType.RIGHT_BRACKET))
                {
                    this.advance();
                    return this.mk(NodeKind.ARRAY_LITERAL, line, col);
                };
                Node* first = this.expression();
                if (this.failed) { return first; };
                if (this.expect(TokenType.FOR))
                {
                    this.advance();
                    if (!this.consume(TokenType.LEFT_PAREN)) { return first; };
                    TypeSpec* vt = this.type_spec();
                    if (this.failed) { return first; };
                    if (!this.expect(TokenType.IDENTIFIER))
                    {
                        this.fail_expected(TokenType.IDENTIFIER);
                        return first;
                    };
                    byte* vname = this.cur_value();
                    this.advance();
                    if (!this.consume(TokenType.IN)) { return first; };
                    Node* iter = this.expression();
                    if (this.failed) { return first; };
                    if (!this.consume(TokenType.RIGHT_PAREN)) { return first; };
                    if (!this.consume(TokenType.RIGHT_BRACKET)) { return first; };
                    n = this.mk(NodeKind.ARRAY_COMPREHENSION, line, col);
                    if (this.failed) { return first; };
                    n.a = first;
                    n.text = vname;
                    n.ts = vt;
                    n.b = iter;
                    return n;
                };
                n = this.mk(NodeKind.ARRAY_LITERAL, line, col);
                if (this.failed) { return first; };
                node_push(n, 0, first);
                Node* e;
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    e = this.expression();
                    if (this.failed) { return n; };
                    node_push(n, 0, e);
                };
                if (!this.consume(TokenType.RIGHT_BRACKET)) { return n; };
                return n;
            };

            // struct_literal -> '{' (name '=' expr (',' name '=' expr)* | expr (',' expr)*)? '}'
            def struct_literal() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.advance();
                Node* n = this.mk(NodeKind.STRUCT_LITERAL, line, col);
                if (this.failed) { return n; };
                Node* nm;
                Node* v;
                if (!this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.IDENTIFIER) & this.type_at(1) == TokenType.ASSIGN)
                    {
                        while (true)
                        {
                            if (!this.expect(TokenType.IDENTIFIER))
                            {
                                this.fail_expected(TokenType.IDENTIFIER);
                                return n;
                            };
                            nm = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                            if (this.failed) { return n; };
                            nm.text = this.cur_value();
                            this.advance();
                            if (!this.consume(TokenType.ASSIGN)) { return n; };
                            v = this.expression();
                            if (this.failed) { return n; };
                            node_push(n, 0, nm);
                            node_push(n, 1, v);
                            if (!this.expect(TokenType.COMMA)) { break; };
                            this.advance();
                        };
                    }
                    else
                    {
                        while (true)
                        {
                            v = this.expression();
                            if (this.failed) { return n; };
                            node_push(n, 2, v);
                            if (!this.expect(TokenType.COMMA)) { break; };
                            this.advance();
                        };
                    };
                };
                this.consume(TokenType.RIGHT_BRACE);
                return n;
            };

            // d{ key : value, ... }
            def dict_literal() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.advance();
                Node* n = this.mk(NodeKind.DICT_LITERAL_EXPR, line, col);
                if (this.failed) { return n; };
                Node* k;
                Node* v;
                while (!this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        return n;
                    };
                    k = this.expression();
                    if (this.failed) { return n; };
                    if (!this.consume(TokenType.COLON)) { return n; };
                    v = this.expression();
                    if (this.failed) { return n; };
                    node_push(n, 0, k);
                    node_push(n, 1, v);
                    if (this.expect(TokenType.COMMA)) { this.advance(); };
                };
                this.consume(TokenType.RIGHT_BRACE);
                return n;
            };

            // IDENTIFIER ('::' IDENTIFIER)*, joined with "__"
            def scoped_identifier() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                byte* name = this.cur_value();
                this.advance();
                while (this.expect(TokenType.SCOPE))
                {
                    this.advance();
                    if (!this.expect(TokenType.IDENTIFIER))
                    {
                        this.fail_expected(TokenType.IDENTIFIER);
                        return (Node*)0;
                    };
                    name = this.cat2(this.cat2(name, g"__\0"), this.cur_value());
                    this.advance();
                };
                Node* n = this.mk(NodeKind.IDENTIFIER, line, col);
                if (this.failed) { return n; };
                n.text = name;
                return n;
            };

            // '$' name ('.' member)? | '$' type-keyword
            def stringify_expr() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                int nx = this.type_at(1);
                bool valid = nx == TokenType.IDENTIFIER | nx == TokenType.CODIFY | nx == TokenType.DOT | nx == TokenType.TAG |
                             nx == TokenType.SINT | nx == TokenType.UINT | nx == TokenType.SLONG | nx == TokenType.ULONG |
                             nx == TokenType.FLOAT_KW | nx == TokenType.DOUBLE_KW | nx == TokenType.BOOL_KW | nx == TokenType.BYTE;
                if (!valid)
                {
                    this.error_unexpected();
                    return (Node*)0;
                };
                this.advance();
                Node* n;
                if (this.expect(TokenType.CODIFY))
                {
                    // $~$expr: the codify result becomes the stringified name
                    byte* resolved = this.consume_codify();
                    if (this.failed) { return (Node*)0; };
                    n = this.mk(NodeKind.STRING_LITERAL, line, col);
                    if (this.failed) { return n; };
                    n.text = resolved;
                    n.op = -1;
                    return n;
                };
                byte* kw = (byte*)0;
                int c = this.cur();
                if (c == TokenType.SINT) { kw = g"int\0"; }
                elif (c == TokenType.UINT) { kw = g"uint\0"; }
                elif (c == TokenType.SLONG) { kw = g"long\0"; }
                elif (c == TokenType.ULONG) { kw = g"ulong\0"; }
                elif (c == TokenType.FLOAT_KW) { kw = g"float\0"; }
                elif (c == TokenType.DOUBLE_KW) { kw = g"double\0"; }
                elif (c == TokenType.BOOL_KW) { kw = g"bool\0"; }
                elif (c == TokenType.BYTE) { kw = g"byte\0"; };
                if (kw != (byte*)0)
                {
                    this.advance();
                    n = this.mk(NodeKind.STRING_LITERAL, line, col);
                    if (this.failed) { return n; };
                    n.text = kw;
                    n.op = -1;
                    return n;
                };
                if (!this.expect(TokenType.IDENTIFIER))
                {
                    this.error(g"Expected identifier after '$'\0");
                    return (Node*)0;
                };
                n = this.mk(NodeKind.STRINGIFY, line, col);
                if (this.failed) { return n; };
                n.text = this.cur_value();
                this.advance();
                if (this.expect(TokenType.DOT))
                {
                    this.advance();
                    if (this.expect(TokenType.IDENTIFIER))
                    {
                        n.text2 = this.cur_value();
                        this.advance();
                    }
                    elif (this.expect(TokenType.TAG))
                    {
                        this.advance();
                        n.text2 = g"#\0";
                    }
                    else
                    {
                        this.error(g"Expected member name after '.' in stringify expression\0");
                        return n;
                    };
                };
                return n;
            };

            // primary_expression -> literal | identifier | '(' expression ')' | literals of arrays, structs, dicts | queries
            def primary_expression() -> Node*
            {
                int c = this.cur();
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n;
                bool ok;

                if (this.vop_sym != (OpSym*)0)
                {
                    if (this.opsym_match(this.vop_sym))
                    {
                        n = this.mk(NodeKind.IDENTIFIER, line, col);
                        if (this.failed) { return n; };
                        n.text = g"__op_count\0";
                        this.skip_tokens(this.vop_sym.n);
                        return n;
                    };
                };
                if (c == TokenType.IDENTIFIER) { return this.scoped_identifier(); };
                if (c == TokenType.SINT_LITERAL) { return this.int_literal(DataType.SINT); };
                if (c == TokenType.UINT_LITERAL) { return this.int_literal(DataType.UINT); };
                if (c == TokenType.SLONG_LITERAL) { return this.int_literal(DataType.SLONG); };
                if (c == TokenType.ULONG_LITERAL) { return this.int_literal(DataType.ULONG); };
                if (c == TokenType.BYTE_LITERAL) { return this.int_literal(DataType.BYTE); };
                if (c == TokenType.FLOAT | c == TokenType.DOUBLE)
                {
                    n = this.mk(NodeKind.LITERAL, line, col);
                    if (this.failed) { return n; };
                    if (c == TokenType.FLOAT) { n.op = DataType.FLOAT; }
                    else { n.op = DataType.DOUBLE; };
                    n.fval = this.parse_double(this.cur_value());
                    n.text = this.cur_value();
                    this.advance();
                    return n;
                };
                if (c == TokenType.CHAR)
                {
                    n = this.mk(NodeKind.LITERAL, line, col);
                    if (this.failed) { return n; };
                    n.op = DataType.CHAR;
                    n.text = this.cur_value();
                    if (this.toks[this.pos].numeric_char != 0) { n.ival = this.parse_int(this.cur_value(), @ok); }
                    else
                    {
                        byte* cv = this.cur_value();
                        n.ival = (i64)cv[0];
                    };
                    this.advance();
                    return n;
                };
                if (c == TokenType.STRING_LITERAL | c == TokenType.G_STRING)
                {
                    n = this.mk(NodeKind.STRING_LITERAL, line, col);
                    if (this.failed) { return n; };
                    n.text = this.cur_value();
                    n.ival = (i64)this.cur_value_len();
                    n.op = -1;
                    if (c == TokenType.G_STRING) { n.op = StorageClass.GLOBAL; };
                    this.advance();
                    return n;
                };
                if (c == TokenType.F_STRING) { return this.f_string_node(); };
                if (c == TokenType.I_STRING) { return this.i_string_node(); };
                if (c == TokenType.TRUE) { this.advance(); return this.lit(DataType.BOOL, 1, line, col); };
                if (c == TokenType.FALSE) { this.advance(); return this.lit(DataType.BOOL, 0, line, col); };
                if (c == TokenType.VOID) { this.advance(); return this.lit(DataType.VOID, 0, line, col); };
                if (c == TokenType.THIS)
                {
                    n = this.mk(NodeKind.IDENTIFIER, line, col);
                    if (this.failed) { return n; };
                    n.text = g"this\0";
                    this.advance();
                    return n;
                };
                if (c == TokenType.NO_INIT)
                {
                    this.advance();
                    return this.mk(NodeKind.NO_INIT, line, col);
                };
                if (c == TokenType.LEFT_PAREN)
                {
                    this.advance();
                    n = this.expression();
                    if (this.failed) { return n; };
                    this.consume(TokenType.RIGHT_PAREN);
                    return n;
                };
                if (c == TokenType.LEFT_BRACKET) { return this.array_literal(); };
                if (c == TokenType.ELLIPSIS)
                {
                    this.advance();
                    if (!this.consume(TokenType.LEFT_BRACKET)) { return (Node*)0; };
                    Node* ix = this.expression();
                    if (this.failed) { return ix; };
                    if (!this.consume(TokenType.RIGHT_BRACKET)) { return ix; };
                    n = this.mk(NodeKind.VARIADIC_ACCESS, line, col);
                    if (this.failed) { return ix; };
                    n.a = ix;
                    return n;
                };
                if (c == TokenType.DICT_LITERAL) { return this.dict_literal(); };
                if (c == TokenType.LEFT_BRACE) { return this.struct_literal(); };
                if (c == TokenType.SIZEOF) { return this.type_query(NodeKind.SIZE_OF, c); };
                if (c == TokenType.ALIGNOF) { return this.type_query(NodeKind.ALIGN_OF, c); };
                if (c == TokenType.ENDIANOF) { return this.type_query(NodeKind.ENDIAN_OF, c); };
                if (c == TokenType.TYPEOF) { return this.type_query(NodeKind.TYPE_OF, c); };
                if (c == TokenType.STRUCT | c == TokenType.OBJECT)
                {
                    this.advance();
                    if (c == TokenType.STRUCT)
                    {
                        n = this.lit(DataType.STRUCT, 0, line, col);
                        if (!this.failed) { n.text = g"struct\0"; };
                    }
                    else
                    {
                        n = this.lit(DataType.OBJECT, 0, line, col);
                        if (!this.failed) { n.text = g"object\0"; };
                    };
                    return n;
                };
                if (c == TokenType.STRINGIFY) { return this.stringify_expr(); };
                if (c == TokenType.CODIFY)
                {
                    // ~$f"..." / ~$i"..." is the string expression itself, ~$name the recorded string
                    this.advance();
                    if (this.expect(TokenType.F_STRING))
                    {
                        n = this.f_string_node();
                    }
                    elif (this.expect(TokenType.I_STRING))
                    {
                        n = this.i_string_node();
                    }
                    else
                    {
                        byte* cname = this.ident();
                        if (this.failed) { return (Node*)0; };
                        byte* cval = (byte*)nm_get(this.cstrs, cname);
                        if (cval == (byte*)0) { cval = cname; };
                        n = this.mk(NodeKind.STRING_LITERAL, line, col);
                        if (this.failed) { return n; };
                        n.text = cval;
                        n.op = -1;
                    };
                    if (this.failed) { return (Node*)0; };
                    n.line = line;
                    n.col = col;
                    return n;
                };

                // int(x) float(x) ... type conversion
                int dt = -1;
                if (c == TokenType.SINT) { dt = DataType.SINT; }
                elif (c == TokenType.UINT) { dt = DataType.UINT; }
                elif (c == TokenType.FLOAT_KW) { dt = DataType.FLOAT; }
                elif (c == TokenType.DOUBLE_KW) { dt = DataType.DOUBLE; }
                elif (c == TokenType.BYTE) { dt = DataType.BYTE; }
                elif (c == TokenType.BOOL_KW) { dt = DataType.BOOL; }
                elif (c == TokenType.SLONG) { dt = DataType.SLONG; }
                elif (c == TokenType.ULONG) { dt = DataType.ULONG; };
                if (dt >= 0)
                {
                    this.advance();
                    if (this.expect(TokenType.LEFT_PAREN))
                    {
                        this.advance();
                        Node* inner = this.expression();
                        if (this.failed) { return inner; };
                        if (!this.consume(TokenType.RIGHT_PAREN)) { return inner; };
                        n = this.mk(NodeKind.TYPE_CONVERT_EXPRESSION, line, col);
                        if (this.failed) { return inner; };
                        TypeSpec* tt = typespec_new();
                        tt.base_type = dt;
                        n.ts = tt;
                        n.a = inner;
                        return n;
                    };
                    this.pos = this.pos - 1;
                    this.error_unexpected();
                    return (Node*)0;
                };
                this.error_unexpected();
                return (Node*)0;
            };

            // ===== EXPRESSION STATEMENTS =====

            // Wraps value as an ExpressionStatement of ASSIGNMENT(lvalue, value)
            def assign_stmt(Node* lvalue, Node* value, int line, int col) -> Node*
            {
                Node* a = this.mk(NodeKind.ASSIGNMENT, line, col);
                if (this.failed) { return a; };
                a.a = lvalue;
                a.b = value;
                Node* s = this.mk(NodeKind.EXPRESSION_STATEMENT, line, col);
                if (this.failed) { return s; };
                s.a = a;
                return s;
            };

            // '{' ('[' index ']' '=' expr ';')* '}'. Statements go to this.pending.
            def array_assign_block(Node* base) -> void
            {
                if (!this.consume(TokenType.LEFT_BRACE)) { return; };
                int line, col;
                Node* ix;
                Node* lv;
                Node* rv;
                Node* acc;
                while (!this.expect(TokenType.RIGHT_BRACE))
                {
                    if (!this.expect(TokenType.LEFT_BRACKET))
                    {
                        this.error(g"only index-assignment items '[idx] = val;' are legal inside an array-assign block; expected '[' or '}'\0");
                        return;
                    };
                    line = this.cur_line();
                    col = this.cur_col();
                    this.advance();
                    ix = this.expression();
                    if (this.failed) { return; };
                    if (!this.consume(TokenType.RIGHT_BRACKET)) { return; };
                    acc = this.mk(NodeKind.ARRAY_ACCESS, line, col);
                    if (this.failed) { return; };
                    acc.a = node_clone(base);
                    acc.b = ix;
                    if (!this.consume(TokenType.ASSIGN)) { return; };
                    rv = this.expression();
                    if (this.failed) { return; };
                    if (!this.consume(TokenType.SEMICOLON)) { return; };
                    nv_push(this.block_out, this.assign_stmt(acc, rv, line, col));
                };
                this.consume(TokenType.RIGHT_BRACE);
                return;
            };

            // '{' ('.' name ( '=' expr | '[' idx ']' '=' expr | '{' nested '}' ) ';')* '}'
            def member_assign_block(Node* base) -> void
            {
                if (!this.consume(TokenType.LEFT_BRACE)) { return; };
                int line, col;
                Node* mem;
                Node* ix;
                Node* lv;
                Node* rv;
                while (!this.expect(TokenType.RIGHT_BRACE))
                {
                    if (!this.expect(TokenType.DOT))
                    {
                        this.error(g"declarations and non-member statements are illegal inside a member-assign block; expected '.' or '}'\0");
                        return;
                    };
                    line = this.cur_line();
                    col = this.cur_col();
                    this.advance();
                    if (!this.expect(TokenType.IDENTIFIER))
                    {
                        this.fail_expected(TokenType.IDENTIFIER);
                        return;
                    };
                    mem = this.mk(NodeKind.MEMBER_ACCESS, line, col);
                    if (this.failed) { return; };
                    mem.a = node_clone(base);
                    mem.text = this.cur_value();
                    this.advance();
                    if (this.expect(TokenType.LEFT_BRACE))
                    {
                        if (this.type_at(1) == TokenType.LEFT_BRACKET) { this.array_assign_block(mem); }
                        else { this.member_assign_block(mem); };
                        if (this.failed) { return; };
                        if (!this.consume(TokenType.SEMICOLON)) { return; };
                        node_free(mem);
                    }
                    elif (this.expect(TokenType.LEFT_BRACKET))
                    {
                        this.advance();
                        ix = this.expression();
                        if (this.failed) { return; };
                        if (!this.consume(TokenType.RIGHT_BRACKET)) { return; };
                        lv = this.mk(NodeKind.ARRAY_ACCESS, line, col);
                        if (this.failed) { return; };
                        lv.a = mem;
                        lv.b = ix;
                        if (this.expect(TokenType.LEFT_BRACE))
                        {
                            this.member_assign_block(lv);
                            if (this.failed) { return; };
                            if (!this.consume(TokenType.SEMICOLON)) { return; };
                            node_free(lv);
                        }
                        else
                        {
                            if (!this.consume(TokenType.ASSIGN)) { return; };
                            rv = this.expression();
                            if (this.failed) { return; };
                            if (!this.consume(TokenType.SEMICOLON)) { return; };
                            nv_push(this.block_out, this.assign_stmt(lv, rv, line, col));
                        };
                    }
                    else
                    {
                        if (!this.consume(TokenType.ASSIGN)) { return; };
                        rv = this.expression();
                        if (this.failed) { return; };
                        if (!this.consume(TokenType.SEMICOLON)) { return; };
                        nv_push(this.block_out, this.assign_stmt(mem, rv, line, col));
                    };
                };
                this.consume(TokenType.RIGHT_BRACE);
                return;
            };

            // expression_statement -> expression ';' | lvalue member_assign_block ';' | lvalue array_assign_block ';'
            def expression_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* expr = this.expression();
                if (this.failed) { return expr; };
                int k = expr.kind;
                Node* s;
                if (this.expect(TokenType.LEFT_BRACE) &
                    (k == NodeKind.IDENTIFIER | k == NodeKind.ARRAY_ACCESS | k == NodeKind.MEMBER_ACCESS))
                {
                    this.block_out = nv_new();
                    if (this.type_at(1) == TokenType.LEFT_BRACKET) { this.array_assign_block(expr); }
                    else { this.member_assign_block(expr); };
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                    this.last_call = (Node*)0;
                    NodeVec* out = this.block_out;
                    this.block_out = (NodeVec*)0;
                    node_free(expr);
                    if (this.failed)
                    {
                        nv_free(out);
                        return (Node*)0;
                    };
                    if (out.len == 0)
                    {
                        nv_free(out);
                        return (Node*)0;
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
                    return s;
                };
                if (!this.consume(TokenType.SEMICOLON)) { return expr; };
                s = this.mk(NodeKind.EXPRESSION_STATEMENT, line, col);
                if (this.failed) { return s; };
                s.a = expr;
                if (k == NodeKind.FUNCTION_CALL) { this.last_call = expr; }
                else { this.last_call = (Node*)0; };
                return s;
            };
            // ===== DECLARATIONS =====

            // Identifier token value, or null with an error recorded
            def ident() -> byte*
            {
                if (!this.expect(TokenType.IDENTIFIER))
                {
                    this.fail_expected(TokenType.IDENTIFIER);
                    return (byte*)0;
                };
                byte* v = this.cur_value();
                this.advance();
                return v;
            };

            def define_var(byte* name, TypeSpec* ts) -> void
            {
                if (this.st != (FXC_SYMTABLE*)0)
                {
                    st_define(this.st, name, SymbolKind.VARIABLE, ts, (Node*)0);
                };
                return;
            };

            def define_type(byte* name, TypeSpec* ts) -> void
            {
                if (this.st != (FXC_SYMTABLE*)0)
                {
                    st_define(this.st, name, SymbolKind.TYPE, ts, (Node*)0);
                    if ((ts.flags `& TS_NO_FUNCTIONS) != 0) { st_mark_nofunc(this.st, name); };
                };
                return;
            };

            // Warns about a declaration in a loop body unless it is a singinit
            def decl_loop_warning() -> void
            {
                if (this.loop_depth > 0 & !this.in_for_init)
                {
                    bool sing = this.expect(TokenType.SINGINIT) | this.type_at(1) == TokenType.SINGINIT;
                    if (!sing)
                    {
                        print(g"Warning: variable declaration inside a loop body - this will continually allocate new slots on the todo each iteration. at \0");
                        print(this.cur_line());
                        print(g":\0");
                        println(this.cur_col());
                    };
                };
                return;
            };

            // Gives a bare struct literal the declared type name
            def literal_type_from(Node* init, TypeSpec* ts) -> void
            {
                if (init == (Node*)0) { return; };
                if (init.kind == NodeKind.STRUCT_LITERAL & init.text == (byte*)0 & ts.custom_typename != (byte*)0)
                {
                    init.text = ts.custom_typename;
                };
                return;
            };

            // Frees what a failed declaration parse still owns
            def decl_abort(TypeSpec* ts, PtrVec* inits, NodeVec* out) -> Node*
            {
                int i;
                if (ts != (TypeSpec*)0) { typespec_free(ts); };
                if (inits != (PtrVec*)0)
                {
                    while (i < inits.len)
                    {
                        if (inits.items[i] != (void*)0) { node_free((Node*)inits.items[i]); };
                        i++;
                    };
                    pv_free(inits);
                };
                if (out != (NodeVec*)0)
                {
                    i = 0;
                    while (i < out.len)
                    {
                        node_free(out.items[i]);
                        i++;
                    };
                    nv_free(out);
                };
                return (Node*)0;
            };

            // Returns the first node of out and queues the rest
            def decl_flatten(NodeVec* out) -> Node*
            {
                Node* first = (Node*)0;
                if (out.len > 0) { first = out.items[0]; };
                int j = 1;
                while (j < out.len)
                {
                    nv_push(this.pending, out.items[j]);
                    j++;
                };
                out.len = 0;
                nv_free(out);
                return first;
            };

            // VARIABLE_DECLARATION. The first declaration of a group owns ts, later ones a copy.
            def var_decl_node(byte* name, TypeSpec* ts, Node* init, int line, int col, bool first) -> Node*
            {
                Node* d = this.mk(NodeKind.VARIABLE_DECLARATION, line, col);
                if (this.failed) { return d; };
                d.text = name;
                if (first) { d.ts = ts; } else { d.ts = typespec_copy(ts); };
                d.a = init;
                if (ts.storage_class == StorageClass.GLOBAL) { d.flags = NF_GLOBAL; };
                return d;
            };

            def type_decl_node(byte* name, TypeSpec* ts, Node* init, int line, int col, bool first) -> Node*
            {
                Node* d = this.mk(NodeKind.TYPE_DECLARATION, line, col);
                if (this.failed) { return d; };
                d.text = name;
                if (first) { d.ts = ts; } else { d.ts = typespec_copy(ts); };
                d.a = init;
                return d;
            };

            // Text "base*..." of a dict key or value type
            def dict_text(TypeSpec* t) -> byte*
            {
                if (t == (TypeSpec*)0) { return g"unknown\0"; };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                if (t.custom_typename != (byte*)0) { this.sb.put_str(t.custom_typename); }
                else { this.sb.put_str(datatype_text(t.base_type)); };
                int i;
                while (i < t.pointer_depth)
                {
                    this.sb.put_str(g"*\0");
                    i++;
                };
                return this.own_n(this.sb.mem, this.sb.len);
            };

            def dict_sig(TypeSpec* t) -> byte*
            {
                byte* s = this.cat2(g"dict{\0", this.dict_text(t.dict_key));
                s = this.cat2(s, g":\0");
                s = this.cat2(s, this.dict_text(t.dict_value));
                return this.cat2(s, g"}\0");
            };

            def dict_same(TypeSpec* a, TypeSpec* b) -> bool
            {
                if (!cstr_eq(this.dict_text(a.dict_key), this.dict_text(b.dict_key))) { return false; };
                return cstr_eq(this.dict_text(a.dict_value), this.dict_text(b.dict_value));
            };

            // Dict operands of init must agree with each other and with the declared type
            def check_dict_init(TypeSpec* ts, Node* init) -> void
            {
                if (this.st == (FXC_SYMTABLE*)0) { return; };
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
                    if (e == (Node*)0) { continue; };
                    nm = (byte*)0;
                    if (e.kind == NodeKind.BINARY_OP)
                    {
                        pv_push(todo, (void*)e.a);
                        pv_push(todo, (void*)e.b);
                    }
                    elif (e.kind == NodeKind.IDENTIFIER | e.kind == NodeKind.FUNCTION_CALL | e.kind == NodeKind.STRINGIFY)
                    {
                        nm = e.text;
                    };
                    if (nm != (byte*)0)
                    {
                        ent = st_lookup_variable(this.st, nm, (byte*)0);
                        if (ent != (FXC_SYMENTRY*)0)
                        {
                            et = (TypeSpec*)ent.ts;
                            if (et != (TypeSpec*)0)
                            {
                                if (et.base_type == DataType.DICT) { pv_push(ops, (void*)et); };
                            };
                        };
                    };
                };
                int i = 1;
                TypeSpec* ref;
                TypeSpec* ots;
                if (ops.len > 1)
                {
                    ref = (TypeSpec*)ops.items[0];
                    while (i < ops.len)
                    {
                        ots = (TypeSpec*)ops.items[i];
                        if (!this.dict_same(ots, ref))
                        {
                            this.error(this.cat2(this.cat2(this.cat2(g"Dict operands are incompatible: \0", this.dict_sig(ref)),
                                                           g" cannot be combined with \0"), this.dict_sig(ots)));
                            pv_free(ops);
                            pv_free(todo);
                            return;
                        };
                        i++;
                    };
                };
                if (ops.len > 0)
                {
                    ref = (TypeSpec*)ops.items[0];
                    if (!this.dict_same(ts, ref))
                    {
                        this.error(this.cat2(this.cat2(this.cat2(g"Dict type mismatch: declared \0", this.dict_sig(ts)),
                                                       g" is incompatible with \0"), this.dict_sig(ref)));
                    };
                };
                pv_free(ops);
                pv_free(todo);
                return;
            };

            // variable_declaration -> type_spec ( 'as' name ('=' expr)? (',' name ('=' expr)?)*
            //                                   | name ( '(' args ')' | '@=' expr | 'from' expr | '=' expr | '{' dict '}' )
            //                                     (',' name ...)* )
            // Several names make several declarations: the first is returned, the rest are queued.
            def variable_declaration() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.decl_loop_warning();
                byte* raw = (byte*)0;
                if (this.expect(TokenType.IDENTIFIER)) { raw = this.cur_value(); };
                TypeSpec* ts = this.type_spec();
                if (this.failed) { return this.decl_abort(ts, (PtrVec*)0, (NodeVec*)0); };

                NodeVec* out = nv_new();
                Node* init;
                Node* d;
                byte* name;

                // ----- type alias: T as Name -----
                if (this.expect(TokenType.AS))
                {
                    this.advance();
                    name = this.ident();
                    if (this.failed) { return this.decl_abort(ts, (PtrVec*)0, out); };
                    this.define_type(name, ts);
                    init = (Node*)0;
                    if (this.expect(TokenType.ASSIGN))
                    {
                        this.advance();
                        init = this.expression();
                        if (this.failed) { return this.decl_abort(ts, (PtrVec*)0, out); };
                        if (init.kind == NodeKind.STRUCT_LITERAL & init.text == (byte*)0 & ts.custom_typename == (byte*)0)
                        {
                            node_free(init);
                            this.error(g"Struct literal initialization requires a custom type\0");
                            return this.decl_abort(ts, (PtrVec*)0, out);
                        };
                        this.literal_type_from(init, ts);
                    };
                    d = this.type_decl_node(name, ts, init, line, col, true);
                    if (this.failed) { return this.decl_abort((TypeSpec*)0, (PtrVec*)0, out); };
                    nv_push(out, d);
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        name = this.ident();
                        if (this.failed) { return this.decl_abort((TypeSpec*)0, (PtrVec*)0, out); };
                        this.define_type(name, ts);
                        init = (Node*)0;
                        if (this.expect(TokenType.ASSIGN))
                        {
                            this.advance();
                            init = this.expression();
                            if (this.failed) { return this.decl_abort((TypeSpec*)0, (PtrVec*)0, out); };
                            if (init.kind == NodeKind.STRUCT_LITERAL & init.text == (byte*)0 & ts.custom_typename == (byte*)0)
                            {
                                node_free(init);
                                this.error(g"Struct literal initialization requires a custom type\0");
                                return this.decl_abort((TypeSpec*)0, (PtrVec*)0, out);
                            };
                            this.literal_type_from(init, ts);
                        };
                        d = this.type_decl_node(name, ts, init, line, col, false);
                        if (this.failed) { return this.decl_abort((TypeSpec*)0, (PtrVec*)0, out); };
                        nv_push(out, d);
                    };
                    return this.decl_flatten(out);
                };

                // ----- variables -----
                nv_free(out);
                out = (NodeVec*)0;
                name = this.ident();
                if (this.failed) { return this.decl_abort(ts, (PtrVec*)0, (NodeVec*)0); };
                this.define_var(name, ts);

                Node* call;
                Node* holder;
                if (this.expect(TokenType.LEFT_PAREN))
                {
                    this.advance();
                    holder = this.mk(NodeKind.NODE_LIST, line, col);
                    if (this.failed) { return this.decl_abort(ts, (PtrVec*)0, (NodeVec*)0); };
                    if (!this.expect(TokenType.RIGHT_PAREN)) { this.argument_list(holder, (byte*)0); };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                    if (this.failed)
                    {
                        node_free(holder);
                        return this.decl_abort(ts, (PtrVec*)0, (NodeVec*)0);
                    };
                    call = this.mk(NodeKind.FUNCTION_CALL, line, col);
                    if (this.failed)
                    {
                        node_free(holder);
                        return this.decl_abort(ts, (PtrVec*)0, (NodeVec*)0);
                    };
                    if (ts.custom_typename != (byte*)0) { call.text = this.cat2(ts.custom_typename, g".__init\0"); }
                    elif (raw != (byte*)0) { call.text = this.cat2(raw, g".__init\0"); }
                    else { call.text = this.cat2(datatype_text(ts.base_type), g"__init\0"); };
                    this.take_args(call, holder);
                    return this.var_decl_node(name, ts, call, line, col, true);
                };

                PtrVec* names = pv_new();
                PtrVec* inits = pv_new();
                pv_push(names, (void*)name);

                Node* rhs;
                Node* src;
                int al;
                int ac;

                if (this.expect(TokenType.ADDRESS_ASSIGN))
                {
                    al = this.cur_line();
                    ac = this.cur_col();
                    this.advance();
                    rhs = this.expression();
                    if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                    d = this.mk(NodeKind.ADDRESS_OF, al, ac);
                    if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                    d.a = rhs;
                    pv_push(inits, (void*)d);
                }
                elif (this.expect(TokenType.FROM))
                {
                    this.advance();
                    src = this.expression();
                    if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                    this.literal_type_from(src, ts);
                    if (ts.custom_typename != (byte*)0)
                    {
                        d = this.mk(NodeKind.STRUCT_RECAST, line, col);
                        if (this.failed) { node_free(src); pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                        d.text = ts.custom_typename;
                        d.a = src;
                        // ival = suppress_invalidate, set by a '!' after the source
                        if (this.expect(TokenType.NOT))
                        {
                            this.advance();
                            d.ival = 1;
                        };
                    }
                    else
                    {
                        d = this.mk(NodeKind.CAST_EXPRESSION, line, col);
                        if (this.failed) { node_free(src); pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                        d.ts = typespec_copy(ts);
                        d.a = src;
                        d.ival = 1;     // is_bitcast
                    };
                    pv_push(inits, (void*)d);
                }
                elif (this.expect(TokenType.ASSIGN))
                {
                    this.advance();
                    rhs = this.expression();
                    if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                    if (ts.base_type == DataType.DICT)
                    {
                        this.check_dict_init(ts, rhs);
                        if (this.failed)
                        {
                            node_free(rhs);
                            pv_free(names);
                            return this.decl_abort(ts, inits, (NodeVec*)0);
                        };
                    };
                    if (this.ctor_sugar(raw, rhs))
                    {
                        call = this.mk(NodeKind.FUNCTION_CALL, line, col);
                        if (this.failed)
                        {
                            node_free(rhs);
                            pv_free(names);
                            return this.decl_abort(ts, inits, (NodeVec*)0);
                        };
                        call.text = this.cat2(raw, g".__init\0");
                        node_push(call, 0, rhs);
                        pv_free(names);
                        pv_free(inits);
                        return this.var_decl_node(name, ts, call, line, col, true);
                    };
                    this.note_comptime_string(name, ts, rhs);
                    pv_push(inits, (void*)rhs);
                }
                elif (this.expect(TokenType.LEFT_BRACE))
                {
                    if (ts.base_type != DataType.DICT)
                    {
                        this.fail_expected(TokenType.ASSIGN);
                        pv_free(names);
                        return this.decl_abort(ts, inits, (NodeVec*)0);
                    };
                    // dict{K:V} Name { k1: v1, k2: v2 };
                    this.advance();
                    d = this.mk(NodeKind.DICT_LITERAL, line, col);
                    if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                    while (!this.expect(TokenType.RIGHT_BRACE) & !this.expect(TokenType.EOF) & !this.failed)
                    {
                        rhs = this.expression();
                        if (this.failed) { break; };
                        node_push(d, 0, rhs);
                        if (!this.consume(TokenType.COLON)) { break; };
                        rhs = this.expression();
                        if (this.failed) { break; };
                        node_push(d, 0, rhs);
                        if (this.expect(TokenType.COMMA)) { this.advance(); };
                    };
                    if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                    if (this.failed)
                    {
                        node_free(d);
                        pv_free(names);
                        return this.decl_abort(ts, inits, (NodeVec*)0);
                    };
                    ts.dict_capacity = node_count(d, 0) / 2;
                    pv_push(inits, (void*)d);
                }
                else
                {
                    pv_push(inits, (void*)0);
                };

                int i, n;
                Node* prev;
                // ----- name list: int x, y, z ... -----
                if (this.expect(TokenType.COMMA) & inits.items[0] == (void*)0)
                {
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        name = this.ident();
                        if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                        this.define_var(name, ts);
                        pv_push(names, (void*)name);
                        if (this.expect(TokenType.ADDRESS_ASSIGN))
                        {
                            al = this.cur_line();
                            ac = this.cur_col();
                            this.advance();
                            rhs = this.expression();
                            if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                            d = this.mk(NodeKind.ADDRESS_OF, al, ac);
                            if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                            d.a = rhs;
                            pv_push(inits, (void*)d);
                        }
                        elif (this.expect(TokenType.ASSIGN))
                        {
                            this.advance();
                            if (this.expect(TokenType.DITTO))
                            {
                                prev = (Node*)inits.items[inits.len - 1];
                                if (prev == (Node*)0)
                                {
                                    this.error(g"Ditto operator '#\"' used before any initializer to repeat\0");
                                    pv_free(names);
                                    return this.decl_abort(ts, inits, (NodeVec*)0);
                                };
                                this.advance();
                                pv_push(inits, (void*)node_clone(prev));
                            }
                            else
                            {
                                rhs = this.expression();
                                if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                                this.note_comptime_string(name, ts, rhs);
                                pv_push(inits, (void*)rhs);
                            };
                        }
                        else
                        {
                            pv_push(inits, (void*)0);
                        };
                    };

                    // no per-name initializer: a bulk 'from' or '=' may follow
                    bool all_null = true;
                    i = 0;
                    while (i < inits.len)
                    {
                        if (inits.items[i] != (void*)0) { all_null = false; };
                        i++;
                    };
                    if (all_null)
                    {
                        inits.len = 0;
                        if (this.expect(TokenType.FROM))
                        {
                            this.advance();
                            src = this.expression();
                            if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                            i = 0;
                            while (i < names.len)
                            {
                                d = this.mk(NodeKind.ARRAY_ACCESS, line, col);
                                if (this.failed) { node_free(src); pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                                if (i == 0) { d.a = src; } else { d.a = node_clone(src); };
                                d.b = this.lit(DataType.SINT, (i64)i, line, col);
                                pv_push(inits, (void*)d);
                                i++;
                            };
                        }
                        elif (this.expect(TokenType.ASSIGN))
                        {
                            this.advance();
                            i = 0;
                            while (i < names.len)
                            {
                                rhs = this.expression();
                                if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                                pv_push(inits, (void*)rhs);
                                if (this.expect(TokenType.COMMA)) { this.advance(); }
                                else { break; };
                                i++;
                            };
                        };
                    };
                }
                elif (this.expect(TokenType.COMMA))
                {
                    // int x = 1, y = 2, z = 3; every name has its own initializer
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        name = this.ident();
                        if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                        this.define_var(name, ts);
                        pv_push(names, (void*)name);
                        if (this.expect(TokenType.ADDRESS_ASSIGN))
                        {
                            al = this.cur_line();
                            ac = this.cur_col();
                            this.advance();
                            rhs = this.expression();
                            if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                            d = this.mk(NodeKind.ADDRESS_OF, al, ac);
                            if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                            d.a = rhs;
                            pv_push(inits, (void*)d);
                        }
                        elif (this.expect(TokenType.ASSIGN))
                        {
                            this.advance();
                            if (this.expect(TokenType.DITTO))
                            {
                                this.advance();
                                prev = (Node*)inits.items[inits.len - 1];
                                if (prev == (Node*)0) { pv_push(inits, (void*)0); }
                                else { pv_push(inits, (void*)node_clone(prev)); };
                            }
                            else
                            {
                                rhs = this.expression();
                                if (this.failed) { pv_free(names); return this.decl_abort(ts, inits, (NodeVec*)0); };
                                pv_push(inits, (void*)rhs);
                            };
                        }
                        else
                        {
                            pv_push(inits, (void*)0);
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
                    if (i < fin.len) { init = (Node*)fin.items[i]; };
                    this.literal_type_from(init, ts);
                    d = this.var_decl_node((byte*)names.items[i], ts, init, line, col, i == 0);
                    if (this.failed)
                    {
                        pv_free(names);
                        pv_free(fin);
                        if (i == 0) { return this.decl_abort(ts, (PtrVec*)0, out); };
                        return this.decl_abort((TypeSpec*)0, (PtrVec*)0, out);
                    };
                    nv_push(out, d);
                    i++;
                };
                pv_free(names);
                pv_free(fin);
                return this.decl_flatten(out);
            };

            // variable_declaration_statement -> variable_declaration ';'
            def variable_declaration_statement() -> Node*
            {
                Node* d = this.variable_declaration();
                if (this.failed) { return d; };
                this.consume(TokenType.SEMICOLON);
                return d;
            };

            // dual_assign_declaration -> type '^|' type IDENTIFIER ',' IDENTIFIER '=' expression ';'
            def dual_assign_declaration() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                TypeSpec* ok_ts = this.type_spec();
                if (this.failed) { typespec_free(ok_ts); return (Node*)0; };
                if (!this.consume(TokenType.XOR_OP)) { typespec_free(ok_ts); return (Node*)0; };
                TypeSpec* err_ts = this.type_spec();
                if (this.failed) { typespec_free(ok_ts); typespec_free(err_ts); return (Node*)0; };
                byte* ok_name = this.ident();
                byte* err_name = (byte*)0;
                Node* call;
                if (!this.failed)
                {
                    if (this.consume(TokenType.COMMA)) { err_name = this.ident(); };
                };
                if (!this.failed) { this.consume(TokenType.ASSIGN); };
                if (!this.failed)
                {
                    call = this.expression();
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                    if (this.failed)
                    {
                        node_free(call);
                    };
                };
                if (this.failed)
                {
                    typespec_free(ok_ts);
                    typespec_free(err_ts);
                    return (Node*)0;
                };
                this.define_var(ok_name, ok_ts);
                this.define_var(err_name, err_ts);
                Node* n = this.mk(NodeKind.DUAL_ASSIGN_DECLARATION, line, col);
                if (this.failed)
                {
                    typespec_free(ok_ts);
                    typespec_free(err_ts);
                    node_free(call);
                    return n;
                };
                n.ts = ok_ts;
                n.ts2 = err_ts;
                n.text = ok_name;
                n.text2 = err_name;
                n.a = call;
                return n;
            };

            // auto_variable_declaration -> 'auto' IDENTIFIER '=' expression
            // The type is a sentinel (void with storage class auto); the compiler infers it.
            def auto_variable_declaration() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.AUTO);
                byte* name = (byte*)0;
                Node* init = (Node*)0;
                if (!this.failed) { name = this.ident(); };
                if (!this.failed) { this.consume(TokenType.ASSIGN); };
                if (!this.failed) { init = this.expression(); };
                if (this.failed)
                {
                    node_free(init);
                    return (Node*)0;
                };
                TypeSpec* ts = typespec_new();
                if (ts == (TypeSpec*)0) { node_free(init); this.fail_alloc(); return (Node*)0; };
                ts.base_type = DataType.VOID;
                ts.storage_class = StorageClass.AUTO;
                this.define_var(name, ts);
                Node* d = this.mk(NodeKind.VARIABLE_DECLARATION, line, col);
                if (this.failed)
                {
                    typespec_free(ts);
                    node_free(init);
                    return d;
                };
                d.text = name;
                d.ts = ts;
                d.a = init;
                return d;
            };

            // destructuring_assignment -> 'auto' '{' (name ('as' type)?) (',' ...)* '}' '=' expression ('from' IDENTIFIER)?
            def destructuring_assignment() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.AUTO);
                if (!this.failed) { this.consume(TokenType.LEFT_BRACE); };
                if (this.failed) { return (Node*)0; };
                Node* n = this.mk(NodeKind.DESTRUCTURING_ASSIGNMENT, line, col);
                if (this.failed) { return n; };
                Node* v;
                byte* name;
                TypeSpec* ts;
                int vl, vc;
                while (!this.expect(TokenType.RIGHT_BRACE) & !this.expect(TokenType.EOF) & !this.failed)
                {
                    if (this.expect(TokenType.IDENTIFIER))
                    {
                        vl = this.cur_line();
                        vc = this.cur_col();
                        name = this.cur_value();
                        this.advance();
                        if (this.expect(TokenType.AS))
                        {
                            this.advance();
                            ts = this.type_spec();
                            if (this.failed) { typespec_free(ts); break; };
                            v = this.mk(NodeKind.VARIABLE_DECLARATION, vl, vc);
                            if (this.failed) { typespec_free(ts); break; };
                            v.text = name;
                            v.ts = ts;
                            n.flags = n.flags `| NF_EXPLICIT;
                        }
                        else
                        {
                            v = this.mk(NodeKind.IDENTIFIER, vl, vc);
                            if (this.failed) { break; };
                            v.text = name;
                        };
                        node_push(n, 0, v);
                    };
                    if (!this.expect(TokenType.RIGHT_BRACE))
                    {
                        if (!this.consume(TokenType.COMMA)) { break; };
                    };
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                if (!this.failed) { this.consume(TokenType.ASSIGN); };
                if (!this.failed)
                {
                    n.a = this.expression();
                };
                if (!this.failed)
                {
                    if (this.expect(TokenType.FROM))
                    {
                        this.advance();
                        vl = this.cur_line();
                        vc = this.cur_col();
                        name = this.ident();
                        if (!this.failed)
                        {
                            v = this.mk(NodeKind.IDENTIFIER, vl, vc);
                            if (!this.failed)
                            {
                                v.text = name;
                                n.b = v;
                            };
                        };
                    };
                };
                if (this.failed)
                {
                    node_free(n);
                    return (Node*)0;
                };
                return n;
            };

            // ===== STATEMENTS =====

            // Frees n and returns null when a parse error was recorded, otherwise returns n
            def done(Node* n) -> Node*
            {
                if (this.failed)
                {
                    node_free(n);
                    return (Node*)0;
                };
                return n;
            };

            // Moves nodes queued by a multi-statement construct into container.l<slot>
            def drain_pending(Node* container, int slot) -> void
            {
                int k;
                while (k < this.pending.len)
                {
                    node_push(container, slot, this.pending.items[k]);
                    this.last_stmt = this.pending.items[k];
                    k++;
                };
                this.pending.len = 0;
                return;
            };

            // Statements up to the closing '}' of an already opened body go to holder.l0
            def statements_until_brace(Node* holder) -> void
            {
                Node* s;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        return;
                    };
                    s = this.statement();
                    if (this.failed) { return; };
                    if (s != (Node*)0)
                    {
                        node_push(holder, 0, s);
                        this.last_stmt = s;
                    };
                    this.drain_pending(holder, 0);
                };
                return;
            };

            // block -> '{' statement* '}'
            def block() -> Node*
            {
                Node* b = this.mk(NodeKind.BLOCK, this.cur_line(), this.cur_col());
                if (this.failed) { return b; };
                this.consume(TokenType.LEFT_BRACE);
                if (!this.failed) { this.statements_until_brace(b); };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                return this.done(b);
            };

            // block body of a loop: loop_depth is raised while it is parsed
            def loop_block() -> Node*
            {
                this.loop_depth++;
                Node* b = this.block();
                this.loop_depth--;
                return b;
            };

            // block_statement -> block (('if' '(' expression ')') ('else' block)? ';' | ';')
            def block_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* body = this.block();
                if (this.failed) { return (Node*)0; };
                Node* n;

                if (this.expect(TokenType.IF))
                {
                    this.advance();
                    n = this.mk(NodeKind.IF_STATEMENT, line, col);
                    if (this.failed) { node_free(body); return n; };
                    n.b = body;
                    this.consume(TokenType.LEFT_PAREN);
                    if (!this.failed) { n.a = this.expression(); };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                    if (!this.failed & this.expect(TokenType.ELSE))
                    {
                        this.advance();
                        n.c = this.block();
                    };
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                    return this.done(n);
                };

                if (this.expect(TokenType.LEFT_BRACE))
                {
                    node_free(body);
                    this.error(g"Unexpected block after block statement. Did you mean '{ ... } if (cond);'?\0");
                    return (Node*)0;
                };
                if (!this.consume(TokenType.SEMICOLON))
                {
                    node_free(body);
                    return (Node*)0;
                };
                return body;
            };

            // block_or_single_stmt -> block | '->' expression | expression   (no trailing ';')
            def block_or_single_stmt() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                if (this.expect(TokenType.LEFT_BRACE)) { return this.block(); };
                Node* b = this.mk(NodeKind.BLOCK, line, col);
                if (this.failed) { return b; };
                Node* s;
                if (this.expect(TokenType.RETURN_ARROW))
                {
                    this.advance();
                    s = this.mk(NodeKind.RETURN_STATEMENT, line, col);
                }
                else
                {
                    s = this.mk(NodeKind.EXPRESSION_STATEMENT, line, col);
                };
                if (this.failed) { node_free(b); return s; };
                node_push(b, 0, s);
                s.a = this.expression();
                return this.done(b);
            };

            // if_statement -> 'if' '(' expr ')' body (('elif' | 'else' 'if') '(' expr ')' body)* ('else' body)? ';'
            def if_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.IF_STATEMENT, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.consume(TokenType.IF);
                if (!this.failed) { this.consume(TokenType.LEFT_PAREN); };
                if (!this.failed) { n.a = this.expression(); };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (!this.failed) { n.b = this.block_or_single_stmt(); };

                Node* c;
                while (!this.failed & (this.expect(TokenType.ELIF) |
                       (this.expect(TokenType.ELSE) & this.type_at(1) == TokenType.IF)))
                {
                    if (this.expect(TokenType.ELIF)) { this.advance(); }
                    else
                    {
                        this.advance();
                        this.advance();
                    };
                    this.consume(TokenType.LEFT_PAREN);
                    if (this.failed) { break; };
                    c = this.expression();
                    if (this.failed) { node_free(c); break; };
                    node_push(n, 0, c);
                    this.consume(TokenType.RIGHT_PAREN);
                    if (this.failed) { break; };
                    c = this.block_or_single_stmt();
                    if (this.failed) { node_free(c); break; };
                    node_push(n, 1, c);
                };

                if (!this.failed & this.expect(TokenType.ELSE))
                {
                    this.advance();
                    n.c = this.block_or_single_stmt();
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // while_statement -> 'while' '(' expression ')' block ';'
            def while_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.WHILE_LOOP, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.consume(TokenType.WHILE);
                if (!this.failed) { this.consume(TokenType.LEFT_PAREN); };
                if (!this.failed) { n.a = this.expression(); };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (!this.failed) { n.b = this.loop_block(); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // do_while_statement -> 'do' block ('while' '(' expression ')' ';' | ';')
            def do_while_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.DO);
                if (this.failed) { return (Node*)0; };
                Node* body = this.loop_block();
                if (this.failed) { return (Node*)0; };
                Node* n;
                if (this.expect(TokenType.WHILE))
                {
                    this.advance();
                    n = this.mk(NodeKind.DO_WHILE_LOOP, line, col);
                    if (this.failed) { node_free(body); return n; };
                    n.b = body;
                    this.consume(TokenType.LEFT_PAREN);
                    if (!this.failed) { n.a = this.expression(); };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                    return this.done(n);
                };
                if (this.expect(TokenType.SEMICOLON))
                {
                    this.advance();
                    n = this.mk(NodeKind.DO_LOOP, line, col);
                    if (this.failed) { node_free(body); return n; };
                    n.b = body;
                    return n;
                };
                node_free(body);
                this.error(g"Expected 'while' or ';' after do block\0");
                return (Node*)0;
            };

            // True when the tokens after 'for (' start a for-in header.
            // Sets destructure to 1 for the 'auto' forms.
            def is_for_in(bool* destructure) -> bool
            {
                int m = this.mark();
                bool r = false;
                *destructure = false;
                if (this.expect(TokenType.IDENTIFIER))
                {
                    this.advance();
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        if (this.expect(TokenType.IDENTIFIER)) { this.advance(); }
                        else { break; };
                    };
                    if (this.expect(TokenType.IN)) { r = true; };
                }
                elif (this.expect(TokenType.AUTO))
                {
                    this.advance();
                    if (this.expect(TokenType.LEFT_BRACE))
                    {
                        this.advance();
                        if (this.expect(TokenType.IDENTIFIER))
                        {
                            this.advance();
                            while (this.expect(TokenType.COMMA))
                            {
                                this.advance();
                                if (this.expect(TokenType.IDENTIFIER)) { this.advance(); }
                                else { break; };
                            };
                            if (this.expect(TokenType.RIGHT_BRACE))
                            {
                                this.advance();
                                if (this.expect(TokenType.IN))
                                {
                                    r = true;
                                    *destructure = true;
                                };
                            };
                        };
                    }
                    elif (this.expect(TokenType.IDENTIFIER))
                    {
                        this.advance();
                        if (this.expect(TokenType.IN))
                        {
                            r = true;
                            *destructure = true;
                        };
                    };
                };
                this.reset(m);
                return r;
            };

            // Pushes an IDENTIFIER node for the current identifier token onto n.l0
            def loop_variable(Node* n) -> void
            {
                int line = this.cur_line();
                int col = this.cur_col();
                byte* name = this.ident();
                if (this.failed) { return; };
                Node* v = this.mk(NodeKind.IDENTIFIER, line, col);
                if (this.failed) { return; };
                v.text = name;
                node_push(n, 0, v);
                return;
            };

            // for_statement -> 'for' '(' (for_in | init ';' cond ';' update) ')' block ';'
            def for_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.FOR);
                if (!this.failed) { this.consume(TokenType.LEFT_PAREN); };
                if (this.failed) { return (Node*)0; };

                bool destructure;
                Node* n;
                if (this.is_for_in(@destructure))
                {
                    n = this.mk(NodeKind.FOR_IN_LOOP, line, col);
                    if (this.failed) { return n; };
                    if (destructure)
                    {
                        n.flags = NF_DESTRUCTURE;
                        this.consume(TokenType.AUTO);
                        if (!this.failed & this.expect(TokenType.LEFT_BRACE))
                        {
                            this.advance();
                            this.loop_variable(n);
                            while (!this.failed & this.expect(TokenType.COMMA))
                            {
                                this.advance();
                                this.loop_variable(n);
                            };
                            if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                        }
                        elif (!this.failed)
                        {
                            this.loop_variable(n);
                        };
                    }
                    else
                    {
                        this.loop_variable(n);
                        while (!this.failed & this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            this.loop_variable(n);
                        };
                    };
                    if (!this.failed) { this.consume(TokenType.IN); };
                    if (!this.failed) { n.a = this.expression(); };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                    if (!this.failed) { n.b = this.loop_block(); };
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                    return this.done(n);
                };

                // C style
                n = this.mk(NodeKind.FOR_LOOP, line, col);
                if (this.failed) { return n; };
                Node* s;
                int sl, sc;
                if (!this.expect(TokenType.SEMICOLON))
                {
                    if (this.is_variable_declaration())
                    {
                        this.in_for_init = true;
                        s = this.variable_declaration();
                        this.in_for_init = false;
                        if (!this.failed)
                        {
                            if (this.pending.len > 0)
                            {
                                // several declarations are wrapped in a block
                                Node* wrap = this.mk(NodeKind.BLOCK, line, col);
                                if (!this.failed)
                                {
                                    node_push(wrap, 0, s);
                                    this.drain_pending(wrap, 0);
                                    n.a = wrap;
                                };
                            }
                            else
                            {
                                n.a = s;
                            };
                        };
                    }
                    else
                    {
                        sl = this.cur_line();
                        sc = this.cur_col();
                        s = this.mk(NodeKind.EXPRESSION_STATEMENT, sl, sc);
                        if (!this.failed)
                        {
                            s.a = this.expression();
                            n.a = s;
                        };
                    };
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (!this.failed & !this.expect(TokenType.SEMICOLON)) { n.b = this.expression(); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (!this.failed & !this.expect(TokenType.RIGHT_PAREN))
                {
                    sl = this.cur_line();
                    sc = this.cur_col();
                    s = this.mk(NodeKind.EXPRESSION_STATEMENT, sl, sc);
                    if (!this.failed)
                    {
                        s.a = this.expression();
                        n.c = s;
                    };
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (!this.failed) { n.d = this.loop_block(); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // switch_case -> 'case' '(' expression ')' block | 'default' block ';'
            def switch_case() -> Node*
            {
                Node* n = this.mk(NodeKind.CASE, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                if (this.expect(TokenType.CASE))
                {
                    this.advance();
                    this.consume(TokenType.LEFT_PAREN);
                    if (!this.failed) { n.a = this.expression(); };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                    if (!this.failed) { n.b = this.block(); };
                }
                elif (this.expect(TokenType.DEFAULT))
                {
                    this.advance();
                    n.b = this.block();
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                }
                else
                {
                    this.error(g"Expected 'case' or 'default'\0");
                };
                return this.done(n);
            };

            // switch_statement -> 'switch' '(' expression ')' '{' switch_case* '}' ';'
            def switch_statement() -> Node*
            {
                int start = this.mark();
                Node* n = this.mk(NodeKind.SWITCH_STATEMENT, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.consume(TokenType.SWITCH);
                if (!this.failed) { this.consume(TokenType.LEFT_PAREN); };
                if (!this.failed) { n.a = this.expression(); };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (!this.failed) { this.consume(TokenType.LEFT_BRACE); };
                Node* c;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    };
                    c = this.switch_case();
                    if (this.failed) { break; };
                    node_push(n, 0, c);
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (this.failed) { return this.done(n); };

                // A tagged union switch (v.#) is checked exhaustively later and needs no default.
                bool tagged = false;
                if (n.a != (Node*)0)
                {
                    if (n.a.kind == NodeKind.MEMBER_ACCESS & n.a.text != (byte*)0)
                    {
                        tagged = n.a.text[0] == '#' & n.a.text[1] == 0;
                    };
                };
                if (!tagged)
                {
                    bool has_default = false;
                    Node* cs;
                    int i;
                    int cnt = node_count(n, 0);
                    while (i < cnt)
                    {
                        cs = node_child(n, 0, i);
                        if (cs.a == (Node*)0) { has_default = true; };
                        i++;
                    };
                    if (!has_default)
                    {
                        int here = this.mark();
                        this.reset(start);
                        this.error(g"Switch statement requires a default case\0");
                        this.reset(here);
                        return this.done(n);
                    };
                };
                return n;
            };

            // try_statement -> 'try' block ('catch' '(' (')' | ('auto' | type) IDENTIFIER ')') block)* ';'
            def try_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.TRY_BLOCK, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.consume(TokenType.TRY);
                if (!this.failed) { n.a = this.block(); };
                Node* c;
                while (!this.failed & this.expect(TokenType.CATCH))
                {
                    c = this.mk(NodeKind.CATCH_CLAUSE, this.cur_line(), this.cur_col());
                    if (this.failed) { break; };
                    node_push(n, 0, c);
                    this.advance();
                    this.consume(TokenType.LEFT_PAREN);
                    if (this.failed) { break; };
                    if (this.expect(TokenType.RIGHT_PAREN))
                    {
                        this.advance();
                        c.a = this.block();
                    }
                    else
                    {
                        if (this.expect(TokenType.AUTO)) { this.advance(); }
                        else { c.ts = this.type_spec(); };
                        if (this.failed) { break; };
                        c.text = this.ident();
                        if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                        if (!this.failed) { c.a = this.block(); };
                    };
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // 'return' expression? ';'   and   '->' expression? ';'
            def return_node(int tok) -> Node*
            {
                Node* n = this.mk(NodeKind.RETURN_STATEMENT, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.consume(tok);
                if (!this.failed & !this.expect(TokenType.SEMICOLON)) { n.a = this.expression(); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            def return_statement() -> Node*
            {
                return this.return_node(TokenType.RETURN);
            };

            def return_arrow_ret() -> Node*
            {
                return this.return_node(TokenType.RETURN_ARROW);
            };

            // 'error' (';' | expression ';' | '->' expression ';' | 'return' expression ';')
            def error_return_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.ERROR_RETURN_STATEMENT, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.advance();
                if (this.expect(TokenType.RETURN_ARROW) | this.expect(TokenType.RETURN))
                {
                    this.advance();
                    n.a = this.expression();
                }
                elif (!this.expect(TokenType.SEMICOLON))
                {
                    n.a = this.expression();
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // 'break' ('switch')? ';'
            def break_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.BREAK);
                if (this.failed) { return (Node*)0; };
                int kind = NodeKind.BREAK_STATEMENT;
                if (this.expect(TokenType.SWITCH))
                {
                    kind = NodeKind.BREAK_SWITCH_STATEMENT;
                    this.advance();
                };
                if (!this.consume(TokenType.SEMICOLON)) { return (Node*)0; };
                return this.mk(kind, line, col);
            };

            // 'continue' ';'
            def continue_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.CONTINUE);
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (this.failed) { return (Node*)0; };
                return this.mk(NodeKind.CONTINUE_STATEMENT, line, col);
            };

            // 'noreturn' ';'
            def noreturn_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                this.consume(TokenType.NORET);
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (this.failed) { return (Node*)0; };
                return this.mk(NodeKind.NORETURN_STATEMENT, line, col);
            };

            // 'label' IDENTIFIER ':'
            def label_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.LABEL_STATEMENT, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.consume(TokenType.LABEL);
                if (!this.failed & this.loop_depth > 0)
                {
                    this.error(g"'label' is not permitted inside a loop body\0");
                };
                if (!this.failed) { n.text = this.ident(); };
                if (!this.failed) { this.consume(TokenType.COLON); };
                return this.done(n);
            };

            // 'goto' IDENTIFIER ';'
            def goto_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.GOTO_STATEMENT, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.consume(TokenType.GOTO);
                if (!this.failed) { n.text = this.ident(); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // 'kw' expression ';' with the expression in slot a
            def keyword_expr_statement(int tok, int kind) -> Node*
            {
                Node* n = this.mk(kind, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.consume(tok);
                if (!this.failed) { n.a = this.expression(); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            def jump_statement() -> Node*
            {
                return this.keyword_expr_statement(TokenType.JUMP, NodeKind.JUMP_STATEMENT);
            };

            def escape_statement() -> Node*
            {
                return this.keyword_expr_statement(TokenType.ESCAPE_KW, NodeKind.ESCAPE_STATEMENT);
            };

            // 'throw' '(' expression ')' ';'
            def throw_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.THROW_STATEMENT, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.consume(TokenType.THROW);
                if (!this.failed) { this.consume(TokenType.LEFT_PAREN); };
                if (!this.failed) { n.a = this.expression(); };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // 'assert' '(' expression (',' (STRING_LITERAL | F_STRING | I_STRING))? ')' ';'
            def assert_statement() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.ASSERT_STATEMENT, line, col);
                Node* msg;
                if (this.failed) { return n; };
                this.consume(TokenType.ASSERT);
                if (!this.failed) { this.consume(TokenType.LEFT_PAREN); };
                if (!this.failed) { n.a = this.expression(); };
                if (!this.failed & this.expect(TokenType.COMMA))
                {
                    this.advance();
                    if (this.expect(TokenType.F_STRING) | this.expect(TokenType.I_STRING))
                    {
                        // reported through note_feat and kept as a stub node
                        n.b = this.primary_expression();
                    }
                    elif (this.expect(TokenType.STRING_LITERAL))
                    {
                        msg = this.mk(NodeKind.STRING_LITERAL, this.cur_line(), this.cur_col());
                        if (!this.failed)
                        {
                            msg.text = this.cur_value();
                            n.b = msg;
                            this.advance();
                        };
                    }
                    else
                    {
                        this.fail_expected(TokenType.STRING_LITERAL);
                    };
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // 'defer' (expression | '{' statement* '}') ';'
            def defer_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.DEFER_STATEMENT, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.consume(TokenType.DEFER);
                if (!this.failed & this.expect(TokenType.LEFT_BRACE))
                {
                    this.advance();
                    n.flags = NF_HAS_BODY;
                    this.statements_until_brace(n);
                    if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                }
                elif (!this.failed)
                {
                    n.a = this.expression();
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // 'fluxvm' FLUXVM_BLOCK ';'
            def fluxvm_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.FLUXVM_BLOCK, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.consume(TokenType.FLUXVM);
                if (!this.failed & this.expect(TokenType.FLUXVM_BLOCK))
                {
                    n.text = this.cur_value();
                    this.advance();
                }
                elif (!this.failed)
                {
                    this.fail_expected(TokenType.FLUXVM_BLOCK);
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // #"; repeats the previous statement
            def ditto_statement() -> Node*
            {
                this.advance();
                if (!this.consume(TokenType.SEMICOLON)) { return (Node*)0; };
                if (this.last_stmt == (Node*)0)
                {
                    this.error(g"Ditto operator '#\"' used as a statement before any preceding statement to repeat\0");
                    return (Node*)0;
                };
                Node* d = node_clone(this.last_stmt);
                if (d == (Node*)0)
                {
                    this.fail_alloc();
                    return d;
                };
                this.last_stmt = d;
                return d;
            };

            // ===== INLINE ASSEMBLY =====

            // Operand list: "constraint"(tokens) joined by ','. Ends before ':' or ';'.
            def asm_operands() -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                int count, depth, start;
                while (!this.expect2(TokenType.COLON, TokenType.SEMICOLON))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.SEMICOLON);
                        return (byte*)0;
                    };
                    if (this.expect(TokenType.STRING_LITERAL))
                    {
                        start = this.sb.len;
                        if (count > 0) { this.sb.put(',' ); };
                        this.sb.put('"');
                        this.sb.put_n(this.cur_value(), this.cur_value_len());
                        this.sb.put('"');
                        this.advance();
                        if (this.expect(TokenType.LEFT_PAREN))
                        {
                            this.advance();
                            this.sb.put('(');
                            depth = 1;
                            while (depth > 0 & !this.expect(TokenType.EOF))
                            {
                                if (this.expect(TokenType.LEFT_PAREN)) { depth++; }
                                elif (this.expect(TokenType.RIGHT_PAREN)) { depth--; };
                                if (depth > 0) { this.sb.put_n(this.cur_value(), this.cur_value_len()); };
                                this.advance();
                            };
                            this.sb.put(')');
                            count++;
                        }
                        else
                        {
                            this.sb.len = start;
                        };
                        if (this.expect(TokenType.COMMA)) { this.advance(); };
                    }
                    else
                    {
                        this.advance();
                    };
                };
                return this.own_n(this.sb.mem, this.sb.len);
            };

            // Clobber list: "reg" (',' "reg")* up to ';'
            def asm_clobbers() -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                int count;
                while (!this.expect(TokenType.SEMICOLON))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.SEMICOLON);
                        return (byte*)0;
                    };
                    if (this.expect(TokenType.STRING_LITERAL))
                    {
                        if (count > 0) { this.sb.put(','); };
                        this.sb.put('"');
                        this.sb.put_n(this.cur_value(), this.cur_value_len());
                        this.sb.put('"');
                        count++;
                        this.advance();
                        if (this.expect(TokenType.COMMA)) { this.advance(); };
                    }
                    else
                    {
                        this.advance();
                    };
                };
                return this.own_n(this.sb.mem, this.sb.len);
            };

            // asm_statement -> ('volatile')? 'asm' ASM_BLOCK (':' operands)? (':' operands)? (':' clobbers)? ';'
            // EXPRESSION_STATEMENT holding an INLINE_ASM (text = body, text2 = constraints)
            def asm_statement(bool is_volatile) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.EXPRESSION_STATEMENT, line, col);
                if (this.failed) { return n; };
                Node* a = this.mk(NodeKind.INLINE_ASM, line, col);
                if (this.failed) { node_free(n); return a; };
                n.a = a;
                if (!is_volatile & this.expect(TokenType.VOLATILE))
                {
                    is_volatile = true;
                    this.advance();
                };
                if (is_volatile) { a.flags = NF_VOLATILE; };
                if (!this.consume(TokenType.ASM)) { return this.done(n); };
                if (!this.expect(TokenType.ASM_BLOCK))
                {
                    this.fail_expected(TokenType.ASM_BLOCK);
                    return this.done(n);
                };
                a.text = this.cur_value();
                this.advance();

                byte* outs = g"\0";
                byte* ins = g"\0";
                byte* clob = g"\0";
                if (!this.expect(TokenType.SEMICOLON))
                {
                    if (this.expect(TokenType.COLON))
                    {
                        this.advance();
                        outs = this.asm_operands();
                    };
                    if (!this.failed & this.expect(TokenType.COLON))
                    {
                        this.advance();
                        ins = this.asm_operands();
                    };
                    if (!this.failed & this.expect(TokenType.COLON))
                    {
                        this.advance();
                        clob = this.asm_clobbers();
                    };
                };
                if (this.failed) { return this.done(n); };
                if (!this.consume(TokenType.SEMICOLON)) { return this.done(n); };

                byte* cons = g"\0";
                if (outs[0] != 0 | ins[0] != 0 | clob[0] != 0)
                {
                    cons = outs;
                    if (ins[0] != 0 | clob[0] != 0)
                    {
                        cons = this.cat2(this.cat2(cons, g":\0"), ins);
                        if (clob[0] != 0) { cons = this.cat2(this.cat2(cons, g":\0"), clob); };
                    };
                };
                a.text2 = cons;
                return n;
            };

            // ===== FUNCTIONS =====

            // Text of a calling convention token
            def cc_text(int t) -> byte*
            {
                if (t == TokenType.CDECL) { return g"cdecl\0"; };
                if (t == TokenType.STDCALL) { return g"stdcall\0"; };
                if (t == TokenType.FASTCALL) { return g"fastcall\0"; };
                if (t == TokenType.THISCALL) { return g"thiscall\0"; };
                return g"vectorcall\0";
            };

            // Function name for messages
            def fn_label(Node* f) -> byte*
            {
                if (f.text != (byte*)0) { return f.text; };
                return g"$\0";
            };

            // ----- effect expressions (inside '# effect { }' and '# attenuate { }') -----

            def effect_bin(byte* op, Node* l, Node* r, int line, int col) -> Node*
            {
                Node* n = this.mk(NodeKind.EFFECT_EXPR, line, col);
                if (this.failed)
                {
                    node_free(l);
                    node_free(r);
                    return n;
                };
                n.text = op;
                n.a = l;
                n.b = r;
                return n;
            };

            // Prefix operator spanning skip tokens followed by its operand
            def effect_prefix(byte* op, int skip, int line, int col) -> Node*
            {
                int i;
                while (i < skip)
                {
                    this.advance();
                    i++;
                };
                Node* n = this.mk(NodeKind.EFFECT_EXPR, line, col);
                if (this.failed) { return n; };
                n.text = op;
                n.a = this.effect_unary();
                return this.done(n);
            };

            def effect_primary() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n;
                Node* e;
                byte* name;
                byte* sub;

                if (this.expect(TokenType.LEFT_PAREN))
                {
                    this.advance();
                    e = this.effect_expr();
                    if (this.failed) { return e; };
                    if (!this.consume(TokenType.RIGHT_PAREN))
                    {
                        node_free(e);
                        return (Node*)0;
                    };
                    return e;
                };
                if (this.expect(TokenType.LEFT_BRACKET))
                {
                    this.advance();
                    e = this.effect_expr();
                    if (this.failed) { return e; };
                    if (!this.consume(TokenType.RIGHT_BRACKET))
                    {
                        node_free(e);
                        return (Node*)0;
                    };
                    return e;
                };
                if (this.expect(TokenType.MULTIPLY))
                {
                    this.advance();
                    if (!this.consume(TokenType.DOT)) { return (Node*)0; };
                    if (!this.expect(TokenType.MULTIPLY))
                    {
                        this.error(g"Expected '*' after '*.' in wildcard effect expression\0");
                        return (Node*)0;
                    };
                    this.advance();
                    n = this.mk(NodeKind.EFFECT_NAME, line, col);
                    if (this.failed) { return n; };
                    n.text = g"*.*\0";
                    return n;
                };
                if (this.expect2(TokenType.IDENTIFIER, TokenType.EFFECT))
                {
                    name = this.cur_value();
                    this.advance();
                    while (this.expect(TokenType.DOT))
                    {
                        this.advance();
                        if (this.expect(TokenType.MULTIPLY))
                        {
                            this.advance();
                            name = this.cat2(name, g".*\0");
                            break;
                        };
                        if (!this.expect(TokenType.IDENTIFIER))
                        {
                            this.error(g"Expected identifier or '*' after '.' in effect name\0");
                            return (Node*)0;
                        };
                        sub = this.cur_value();
                        this.advance();
                        name = this.cat2(this.cat2(name, g".\0"), sub);
                    };
                    n = this.mk(NodeKind.EFFECT_NAME, line, col);
                    if (this.failed) { return n; };
                    n.text = name;
                    return n;
                };
                this.error(g"Expected effect expression (identifier, unary operator, or grouped expression)\0");
                return (Node*)0;
            };

            def effect_unary() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                if (this.expect(TokenType.NOT) & this.type_at(1) == TokenType.ADDRESS_OF)
                {
                    return this.effect_prefix(g"!@\0", 2, line, col);
                };
                if (this.expect(TokenType.NOT)) { return this.effect_prefix(g"!\0", 1, line, col); };
                if (this.expect(TokenType.MULTIPLY) & this.type_at(1) != TokenType.DOT)
                {
                    return this.effect_prefix(g"*\0", 1, line, col);
                };
                if (this.expect(TokenType.TIE)) { return this.effect_prefix(g"~\0", 1, line, col); };
                if (this.expect(TokenType.QUESTION)) { return this.effect_prefix(g"?\0", 1, line, col); };
                if (this.expect(TokenType.ADDRESS_OF)) { return this.effect_prefix(g"@\0", 1, line, col); };
                if (this.expect(TokenType.ELLIPSIS)) { return this.effect_prefix(g"...\0", 1, line, col); };
                if (this.expect(TokenType.RANGE)) { return this.effect_prefix(g"..\0", 1, line, col); };
                if (this.expect(TokenType.EXPONENT) & this.type_at(1) != TokenType.LOGICAL_OR)
                {
                    return this.effect_prefix(g"^suppress\0", 1, line, col);
                };
                if (this.expect(TokenType.LESS_THAN) & this.type_at(1) == TokenType.MULTIPLY)
                {
                    return this.effect_prefix(g"<*\0", 2, line, col);
                };
                return this.effect_primary();
            };

            // <-> mutual implication (lexes as '<-' then '>')
            def effect_mutual() -> Node*
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
                return left;
            };

            def effect_xor() -> Node*
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
                return left;
            };

            def effect_implies() -> Node*
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
                return left;
            };

            def effect_priority() -> Node*
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
                return left;
            };

            def effect_and() -> Node*
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
                return left;
            };

            // effect_expr -> and ('|' and)*   (lowest precedence)
            def effect_expr() -> Node*
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
                return left;
            };

            // '{' effect_expr '}' wrapped in an annotation node of the given kind
            def effect_annotation(int kind) -> Node*
            {
                Node* n = this.mk(kind, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.advance();
                if (!this.consume(TokenType.LEFT_BRACE))
                {
                    node_free(n);
                    return (Node*)0;
                };
                n.a = this.effect_expr();
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                return this.done(n);
            };

            // ('#' ('deprecate' | 'effect' '{' .. '}' | 'attenuate' '{' .. '}'))*
            def fn_tags(Node* f) -> void
            {
                while (!this.failed & this.expect(TokenType.TAG))
                {
                    this.advance();
                    if (this.expect(TokenType.DEPRECATE))
                    {
                        this.advance();
                        f.flags = f.flags `| NF_DEPRECATED;
                    }
                    elif (this.expect(TokenType.EFFECT))
                    {
                        node_free(f.b);
                        f.b = this.effect_annotation(NodeKind.EFFECT_ANNOTATION);
                    }
                    elif (this.expect(TokenType.IDENTIFIER) & this.val_is(g"attenuate\0", 9))
                    {
                        node_free(f.c);
                        f.c = this.effect_annotation(NodeKind.ATTENUATE_ANNOTATION);
                    }
                    else
                    {
                        this.error(g"Expected 'deprecate', 'effect', or 'attenuate' after '#'\0");
                    };
                };
                return;
            };

            // ----- parameters -----

            // parameter -> '...' | type_spec IDENTIFIER? ('=' expression)?
            // The variadic sentinel is a PARAMETER with ival = 1.
            def parameter(Node* f) -> void
            {
                Node* p = this.mk(NodeKind.PARAMETER, this.cur_line(), this.cur_col());
                if (this.failed) { return; };
                node_push(f, 0, p);
                if (this.expect(TokenType.ELLIPSIS))
                {
                    this.advance();
                    p.ival = 1;
                    return;
                };
                p.ts = this.type_spec();
                if (this.failed) { return; };
                if (this.expect(TokenType.IDENTIFIER))
                {
                    p.text = this.cur_value();
                    this.advance();
                    if (this.expect(TokenType.ASSIGN))
                    {
                        this.advance();
                        p.a = this.expression();
                    };
                };
                return;
            };

            def parameter_list(Node* f) -> void
            {
                this.parameter(f);
                while (!this.failed & this.expect(TokenType.COMMA))
                {
                    this.advance();
                    this.parameter(f);
                };
                return;
            };

            // Removes the variadic sentinel and sets NF_VARIADIC
            def strip_variadic(Node* f) -> void
            {
                if (f.l0 == (NodeVec*)0) { return; };
                int i, j;
                Node* p;
                while (i < f.l0.len)
                {
                    p = f.l0.items[i];
                    if (p.ival == 1)
                    {
                        node_free(p);
                        f.flags = f.flags `| NF_VARIADIC;
                    }
                    else
                    {
                        f.l0.items[j] = p;
                        j++;
                    };
                    i++;
                };
                f.l0.len = j;
                return;
            };

            def param_count(Node* f) -> int
            {
                if (f.l0 == (NodeVec*)0) { return 0; };
                return f.l0.len;
            };

            // ----- function pointers -----

            // '(' type_spec (',' type_spec)* ')' '->' type_spec
            def function_pointer_type(byte* conv) -> TypeSpec*
            {
                TypeSpec* t = typespec_new();
                if (t == (TypeSpec*)0)
                {
                    this.fail_alloc();
                    return t;
                };
                t.base_type = DataType.FUNC_PTR;
                t.calling_conv = conv;
                PtrVec* tmp = pv_new();
                TypeSpec* p;
                int i;
                if (this.consume(TokenType.LEFT_PAREN))
                {
                    if (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        p = this.type_spec();
                        pv_push(tmp, (void*)p);
                        while (!this.failed & this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            p = this.type_spec();
                            pv_push(tmp, (void*)p);
                        };
                    };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                    if (!this.failed) { this.consume(TokenType.RETURN_ARROW); };
                    if (!this.failed) { t.fp_ret = this.type_spec(); };
                };
                if (tmp.len > 0)
                {
                    t.fp_params = (TypeSpec**)fmalloc((u64)(tmp.len + 1) * (u64)((sizeof(TypeSpec*) + 7) / 8));
                    while (i < tmp.len)
                    {
                        t.fp_params[i] = (TypeSpec*)tmp.items[i];
                        i++;
                    };
                    t.fp_nparams = tmp.len;
                };
                pv_free(tmp);
                return t;
            };

            // name function_pointer_type ('=' ('@' name ('.' member)* | expression))?
            def fp_one(byte* conv) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.FUNCTION_POINTER_DECLARATION, line, col);
                if (this.failed) { return n; };
                Node* addr;
                Node* e;
                Node* m;
                n.text = this.ident();
                if (this.failed) { return this.done(n); };
                n.ts = this.function_pointer_type(conv);
                if (this.failed) { return this.done(n); };

                if (this.expect(TokenType.ASSIGN))
                {
                    this.advance();
                    if (this.expect(TokenType.ADDRESS_OF))
                    {
                        addr = this.mk(NodeKind.ADDRESS_OF, this.cur_line(), this.cur_col());
                        if (this.failed) { return this.done(n); };
                        n.a = addr;
                        this.advance();
                        e = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                        if (this.failed) { return this.done(n); };
                        addr.a = e;
                        if (this.expect(TokenType.STRING_LITERAL))
                        {
                            e.text = this.cur_value();
                            this.advance();
                        }
                        else
                        {
                            e.text = this.ident();
                        };
                        while (!this.failed & this.expect(TokenType.DOT))
                        {
                            this.advance();
                            m = this.mk(NodeKind.MEMBER_ACCESS, this.cur_line(), this.cur_col());
                            if (this.failed) { return this.done(n); };
                            m.a = e;
                            addr.a = m;
                            e = m;
                            e.text = this.ident();
                        };
                    }
                    else
                    {
                        n.a = this.expression();
                    };
                };
                return this.done(n);
            };

            // 'def{}*' (already consumed) fp_one (',' fp_one)* ';'
            def function_pointer_declaration(byte* conv) -> Node*
            {
                if (this.loop_depth > 0 & !this.in_for_init)
                {
                    print(g"Warning: pointer declaration inside a loop body, this will continually allocate new slots on the stack each iteration. at \0");
                    print(this.cur_line());
                    print(g":\0");
                    println(this.cur_col());
                };
                Node* first = this.fp_one(conv);
                if (this.failed) { return first; };
                Node* x;
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    x = this.fp_one(conv);
                    if (this.failed)
                    {
                        node_free(first);
                        return x;
                    };
                    nv_push(this.pending, x);
                };
                if (!this.consume(TokenType.SEMICOLON))
                {
                    node_free(first);
                    return (Node*)0;
                };
                return first;
            };

            // ----- function definitions -----

            // Abandons the construct being parsed (starting at mark m), reports the unsupported
            // feature and skips it. Returns a stub node of the given kind, or null when keep is false
            // (fparser.py returns None for template constructs).
            def skip_unsupported(int m, int feat, Node* partial, int kind, bool keep) -> Node*
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
                if (!keep) { return (Node*)0; };
                Node* stub_node = this.mk(kind, line, col);
                if (this.failed) { return stub_node; };
                stub_node.flags = NF_STUB;
                return stub_node;
            };

            def func_unsupported(int m, int feat, Node* partial) -> Node*
            {
                return this.skip_unsupported(m, feat, partial, NodeKind.FUNCTION_DEF, feat != Feat.TEMPLATE_FUNCTION);
            };

            // Marks f as a prototype with an empty body
            def mark_proto(Node* f) -> void
            {
                f.flags = f.flags `| NF_PROTOTYPE;
                f.a = this.mk(NodeKind.BLOCK, f.line, f.col);
                return;
            };

            // The f-string or i-string token at the cursor as a node
            def fstr_node() -> Node*
            {
                if (this.expect(TokenType.F_STRING)) { return this.f_string_node(); };
                return this.i_string_node();
            };

            // Text of an f-string node when every part is text or a known compile-time string
            // (fparser._resolve_fstring_name), otherwise null
            def fstr_resolve(Node* fl) -> byte*
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
                    if (p.kind == NodeKind.STRING_LITERAL)
                    {
                        this.sb.put_str(p.text);
                    }
                    elif (p.kind == NodeKind.IDENTIFIER)
                    {
                        val = (byte*)nm_get(this.cstrs, p.text);
                        if (val == (byte*)0) { return (byte*)0; };
                        this.sb.put_str(val);
                    }
                    else { return (byte*)0; };
                };
                return this.own_n(this.sb.mem, this.sb.len);
            };

            // IDENTIFIER | STRING_LITERAL | STRINGIFY name of f
            def fn_name(Node* f) -> void
            {
                Node* fs;
                if (this.expect(TokenType.STRING_LITERAL))
                {
                    f.text = this.cur_value();
                    this.advance();
                }
                elif (this.expect2(TokenType.F_STRING, TokenType.I_STRING))
                {
                    fs = this.fstr_node();
                    if (!this.failed)
                    {
                        f.text = this.fstr_resolve(fs);
                        if (f.text == (byte*)0) { f.d = fs; }
                        else { node_free(fs); };
                    };
                }
                elif (this.expect(TokenType.STRINGIFY))
                {
                    f.d = this.stringify_expr();
                }
                elif (this.expect(TokenType.IDENTIFIER))
                {
                    f.text = this.cur_value();
                    this.advance();
                }
                else
                {
                    this.fail_expected(TokenType.IDENTIFIER);
                };
                return;
            };

            // Return type and optional '^|' error type
            def fn_return(Node* f, bool is_cdecl) -> void
            {
                f.ts = this.type_spec();
                if (this.failed) { return; };
                if (this.expect(TokenType.XOR_OP))
                {
                    if (is_cdecl)
                    {
                        this.error(this.cat2(this.cat2(g"Function '\0", this.fn_label(f)), g"' declared with 'cdecl' cannot have a dual return type: a C ABI function can only return a single value\0"));
                        return;
                    };
                    this.advance();
                    f.ts2 = this.type_spec();
                };
                return;
            };

            // Checks a definition, opens its scope and defines the parameters.
            // Returns false with an error recorded.
            def begin_body(Node* f) -> bool
            {
                int i;
                Node* p;
                while (i < this.param_count(f))
                {
                    if (f.l0.items[i].text == (byte*)0)
                    {
                        this.error(g"Function definition requires parameter names, but a parameter has no name\0");
                        return false;
                    };
                    i++;
                };
                if (this.function_depth > 0)
                {
                    this.error(this.cat2(this.cat2(g"Illegal nested function definition '\0", this.fn_label(f)), g"': function definitions are not allowed inside another function body\0"));
                    return false;
                };
                if (this.st != (FXC_SYMTABLE*)0)
                {
                    st_enter_scope(this.st);
                    i = 0;
                    while (i < this.param_count(f))
                    {
                        p = f.l0.items[i];
                        this.define_var(p.text, p.ts);
                        i++;
                    };
                };
                return true;
            };

            def end_body() -> void
            {
                if (this.st != (FXC_SYMTABLE*)0) { st_exit_scope(this.st); };
                return;
            };

            // Ends the template scope of an extra prototype that failed early
            def proto_scope_end(Node* p, TemplateEntry* pte, NameMap* prev_act) -> Node*
            {
                if (pte != (TemplateEntry*)0)
                {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                    te_free(pte);
                };
                return this.done(p);
            };

            // Additional prototype of a comma separated list: name(params) -> type tags
            def fn_extra_proto(int m, int base_flags, byte* conv, bool is_cdecl) -> Node*
            {
                Node* p = this.mk(NodeKind.FUNCTION_DEF, this.cur_line(), this.cur_col());
                if (this.failed) { return p; };
                p.flags = base_flags;
                p.text2 = conv;
                this.fn_name(p);
                if (this.failed) { return this.done(p); };
                NameMap* prev_act = this.active_tp;
                TemplateEntry* pte = (TemplateEntry*)0;
                if (this.expect(TokenType.LESS_THAN) & this.is_template_list())
                {
                    pte = te_new();
                    this.advance();
                    pv_push(pte.params, (void*)this.own(ts_dup(this.ident())));
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        pv_push(pte.params, (void*)this.own(ts_dup(this.ident())));
                    };
                    if (!this.failed) { this.consume(TokenType.GREATER_THAN); };
                    if (this.failed)
                    {
                        te_free(pte);
                        return this.done(p);
                    };
                    this.tp_activate(pte);
                    p.flags = p.flags `| NF_TEMPLATE;
                };
                if (!this.consume(TokenType.LEFT_PAREN)) { return this.proto_scope_end(p, pte, prev_act); };
                if (!this.expect(TokenType.RIGHT_PAREN)) { this.parameter_list(p); };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                if (!this.failed) { this.consume(TokenType.RETURN_ARROW); };
                if (!this.failed) { this.fn_return(p, is_cdecl); };
                if (pte != (TemplateEntry*)0)
                {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                    te_free(pte);
                };
                if (!this.failed) { this.fn_tags(p); };
                if (this.failed) { return this.done(p); };
                this.strip_variadic(p);
                this.mark_proto(p);
                return this.done(p);
            };

            // function_def -> ('const')? ('volatile')? ('inline')? ('def' | calling_conv)? ('!!')? name
            //                 '(' parameter_list? ')' ('->' | '<~') type_spec ('^|' type_spec)?
            //                 tags (';' | '->' expression ';' | block tags ';')
            // Also 'def{}*' function pointer declarations and comma separated prototype lists
            // (extra prototypes go to the pending queue).
            // Template functions, contracts and 'as operator' are reported and skipped (null).
            def function_def() -> Node*
            {
                NameMap* prev_act = this.active_tp;
                TemplateEntry* prev_cur = this.tmpl_cur;
                this.tmpl_cur = (TemplateEntry*)0;
                Node* f = this.function_def_inner();
                TemplateEntry* te = this.tmpl_cur;
                this.tmpl_cur = prev_cur;
                if (this.active_tp != prev_act)
                {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                };
                if (te == (TemplateEntry*)0) { return f; };
                if (this.failed | f == (Node*)0)
                {
                    te_free(te);
                    return f;
                };
                if (f.text == (byte*)0) { f.text = g"\0"; };
                this.last_template = f.text;
                if (this.in_comptime > 0)
                {
                    this.register_template(f.text, 0, te, node_clone(f));
                    return f;
                };
                this.register_template(f.text, 0, te, f);
                return (Node*)0;
            };

            def function_def_inner() -> Node*
            {
                int m = this.mark();
                int line = this.cur_line();
                int col = this.cur_col();
                int flags = 0;
                byte* conv = (byte*)0;
                bool is_cdecl = false;

                if (this.expect(TokenType.CONST)) { flags = flags `| NF_CONST; this.advance(); };
                if (this.expect(TokenType.VOLATILE)) { flags = flags `| NF_VOLATILE; this.advance(); };
                if (this.expect(TokenType.INLINE)) { flags = flags `| NF_INLINE; this.advance(); };

                if (this.is_calling_conv(this.cur()))
                {
                    conv = this.cc_text(this.cur());
                    is_cdecl = this.expect(TokenType.CDECL);
                    this.advance();
                }
                elif (this.expect(TokenType.DEF))
                {
                    this.advance();
                };

                if (this.expect(TokenType.FUNCTION_POINTER))
                {
                    this.advance();
                    return this.function_pointer_declaration(conv);
                };

                if (is_cdecl) { flags = flags `| NF_NO_MANGLE; };
                if (this.expect(TokenType.NO_MANGLE))
                {
                    flags = flags `| NF_NO_MANGLE;
                    this.advance();
                };

                Node* f = this.mk(NodeKind.FUNCTION_DEF, line, col);
                if (this.failed) { return f; };
                f.flags = flags;
                f.text2 = conv;

                this.fn_name(f);
                if (this.failed) { return this.done(f); };

                if (this.expect(TokenType.LESS_THAN))
                {
                    this.tmpl_cur = this.template_params(false);
                    if (this.failed) { return this.done(f); };
                    this.tp_activate(this.tmpl_cur);
                };

                if (!this.consume(TokenType.LEFT_PAREN)) { return this.done(f); };
                if (!this.expect(TokenType.RIGHT_PAREN)) { this.parameter_list(f); };
                if (this.failed) { return this.done(f); };
                if (!this.consume(TokenType.RIGHT_PAREN)) { return this.done(f); };

                if (this.expect(TokenType.RECURSE_ARROW))
                {
                    f.flags = f.flags `| NF_RECURSIVE;
                    this.advance();
                }
                elif (!this.consume(TokenType.RETURN_ARROW))
                {
                    return this.done(f);
                };
                this.fn_return(f, is_cdecl);
                if (this.failed) { return this.done(f); };

                // Tags before a comma list or a prototype
                if (this.expect2(TokenType.TAG, TokenType.COMMA))
                {
                    this.fn_tags(f);
                    if (this.failed) { return this.done(f); };
                    if (this.expect(TokenType.COMMA))
                    {
                        this.strip_variadic(f);
                        this.mark_proto(f);
                        Node* extra;
                        int pflags = (flags `| NF_PROTOTYPE);
                        while (this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            extra = this.fn_extra_proto(m, pflags, conv, is_cdecl);
                            if (this.failed) { return this.done(f); };
                            if (extra == (Node*)0)
                            {
                                node_free(f);
                                return (Node*)0;
                            };
                            nv_push(this.pending, extra);
                        };
                        if (!this.consume(TokenType.SEMICOLON)) { return this.done(f); };
                        return f;
                    };
                };

                Node* pre = (Node*)0;
                Node* post;
                OpSym* as_l = (OpSym*)0;
                OpSym* as_r = (OpSym*)0;
                int as_bind;
                if (this.expect(TokenType.COLON))
                {
                    this.advance();
                    pre = this.mk(NodeKind.NODE_LIST, line, col);
                    if (this.failed) { return this.done(f); };
                    this.contract_refs(f, pre, false);
                    if (this.failed) { node_free(pre); return this.done(f); };
                };

                this.strip_variadic(f);

                if ((f.flags `& NF_RECURSIVE) != 0)
                {
                    bool void_form = this.param_count(f) == 0 & f.ts.base_type == DataType.VOID;
                    bool single_form = this.param_count(f) == 1 & typespec_equal(f.l0.items[0].ts, f.ts);
                    if (!void_form & !single_form)
                    {
                        if (this.param_count(f) == 0)
                        {
                            this.error(this.cat2(this.cat2(g"Recursive function '\0", this.fn_label(f)), g"' with no parameters must return void\0"));
                        }
                        elif (this.param_count(f) == 1)
                        {
                            this.error(this.cat2(this.cat2(g"Recursive function '\0", this.fn_label(f)), g"': return type must match parameter type\0"));
                        }
                        else
                        {
                            this.error(this.cat2(this.cat2(g"Recursive function '\0", this.fn_label(f)), g"' declared with '<~' must have exactly one parameter, or no parameters with void return\0"));
                        };
                        node_free(pre);
                        return this.done(f);
                    };
                };

                if (this.expect(TokenType.AS))
                {
                    this.advance();
                    if (!this.consume(TokenType.OPERATOR)) { node_free(pre); return this.done(f); };
                    as_l = this.op_bracket();
                    if (!this.failed & this.expect(TokenType.LEFT_BRACKET)) { as_r = this.op_bracket(); };
                    if (!this.failed & as_r == (OpSym*)0)
                    {
                        if (this.param_count(f) == 1) { as_bind = this.unary_binding(f, g"an 'as operator' binding\0"); };
                    };
                    if (this.failed)
                    {
                        node_free(pre);
                        this.opsym_free(as_l);
                        this.opsym_free(as_r);
                        return this.done(f);
                    };
                };

                Node* ret;
                Node* b;
                if (this.expect2(TokenType.TAG, TokenType.SEMICOLON))
                {
                    this.fn_tags(f);
                    if (this.failed) { return this.done(f); };
                    if (this.expect(TokenType.SEMICOLON))
                    {
                        this.advance();
                        this.mark_proto(f);
                    };
                    node_free(pre);
                    if (!this.failed & as_l != (OpSym*)0) { this.register_operator(f, as_l, as_r, as_bind, false, false); };
                    return this.done(f);
                };

                if (this.expect(TokenType.RETURN_ARROW))
                {
                    // name(params) -> type -> expression;
                    if (!this.begin_body(f)) { return this.done(f); };
                    this.advance();
                    b = this.mk(NodeKind.BLOCK, this.cur_line(), this.cur_col());
                    if (this.failed) { this.end_body(); return this.done(f); };
                    f.a = b;
                    ret = this.mk(NodeKind.RETURN_STATEMENT, this.cur_line(), this.cur_col());
                    if (this.failed) { this.end_body(); return this.done(f); };
                    node_push(b, 0, ret);
                    this.function_depth++;
                    ret.a = this.expression();
                    this.function_depth--;
                    this.end_body();
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                    node_free(pre);
                    if (!this.failed & as_l != (OpSym*)0) { this.register_operator(f, as_l, as_r, as_bind, false, false); };
                    return this.done(f);
                };

                if (this.in_trait != 0 & !this.expect(TokenType.LEFT_BRACE))
                {
                    this.fail_expected(TokenType.SEMICOLON);
                    return this.done(f);
                };

                if (!this.begin_body(f)) { return this.done(f); };
                this.function_depth++;
                f.a = this.block();
                this.function_depth--;
                this.end_body();
                if (this.failed) { node_free(pre); return this.done(f); };
                this.prepend_contracts(f, pre);

                post = (Node*)0;
                if (this.expect(TokenType.COLON))
                {
                    this.advance();
                    post = this.mk(NodeKind.NODE_LIST, line, col);
                    if (this.failed) { node_free(pre); return this.done(f); };
                    this.contract_refs(f, post, true);
                    if (!this.failed) { this.apply_post_contracts(f, post); };
                };
                if (!this.failed) { this.validate_bindings(this.fn_label(f), pre, post); };
                node_free(post);
                node_free(pre);
                if (this.failed) { return this.done(f); };

                this.fn_tags(f);
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (!this.failed & as_l != (OpSym*)0) { this.register_operator(f, as_l, as_r, as_bind, false, false); };
                return this.done(f);
            };

            // ----- extern and export blocks -----

            // Adds f to holder.l0, checking prototype versus definition
            def add_func(Node* holder, Node* f, bool want_proto) -> void
            {
                node_push(holder, 0, f);
                if (f.kind != NodeKind.FUNCTION_DEF) { return; };
                bool is_proto = (f.flags `& NF_PROTOTYPE) != 0;
                if (want_proto & !is_proto)
                {
                    this.error(g"Extern functions must be prototypes (declarations only, no body)\0");
                }
                elif (!want_proto & is_proto)
                {
                    this.error(g"'export' requires a full definition, not a prototype\0");
                };
                return;
            };

            // One function_def (with its comma list) into holder.l0
            def collect_funcs(Node* holder, bool want_proto) -> void
            {
                Node* f = this.function_def();
                if (this.failed) { return; };
                int k;
                if (f != (Node*)0) { this.add_func(holder, f, want_proto); };
                while (!this.failed & k < this.pending.len)
                {
                    this.add_func(holder, this.pending.items[k], want_proto);
                    k++;
                };
                this.pending.len = 0;
                return;
            };

            // One entry of an extern block: a function prototype or 'type name;'
            def extern_item(Node* holder) -> void
            {
                if (this.expect(TokenType.DEF) | this.is_calling_conv(this.cur()))
                {
                    this.collect_funcs(holder, true);
                    return;
                };
                Node* v = this.mk(NodeKind.VARIABLE_DECLARATION, this.cur_line(), this.cur_col());
                if (this.failed) { return; };
                node_push(holder, 0, v);
                v.ts = this.type_spec();
                if (this.failed) { return; };
                v.text = this.ident();
                if (this.failed) { return; };
                if (this.expect2(TokenType.ASSIGN, TokenType.ADDRESS_ASSIGN))
                {
                    this.error(g"Extern variable declarations cannot have an initializer\0");
                    return;
                };
                this.consume(TokenType.SEMICOLON);
                return;
            };

            // extern_statement -> 'extern' ('{' extern_item* '}' ';' | extern_item)
            def extern_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.EXTERN_BLOCK, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.advance();
                if (this.expect(TokenType.LEFT_BRACE))
                {
                    this.advance();
                    while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                    {
                        if (this.expect(TokenType.EOF))
                        {
                            this.fail_expected(TokenType.RIGHT_BRACE);
                            break;
                        };
                        this.extern_item(n);
                    };
                    if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                }
                else
                {
                    this.extern_item(n);
                };
                return this.done(n);
            };

            // export_statement -> 'export' ('{' function_def* '}' ';' | function_def)
            def export_statement() -> Node*
            {
                Node* n = this.mk(NodeKind.EXPORT_BLOCK, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.advance();
                if (this.expect(TokenType.LEFT_BRACE))
                {
                    this.advance();
                    while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                    {
                        if (this.expect(TokenType.EOF))
                        {
                            this.fail_expected(TokenType.RIGHT_BRACE);
                            break;
                        };
                        if (this.expect(TokenType.DEF) | this.is_calling_conv(this.cur()))
                        {
                            this.collect_funcs(n, false);
                        }
                        else
                        {
                            this.fail_expected(TokenType.DEF);
                        };
                    };
                    if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                }
                elif (this.expect(TokenType.DEF) | this.is_calling_conv(this.cur()))
                {
                    this.collect_funcs(n, false);
                }
                else
                {
                    this.fail_expected(TokenType.LEFT_BRACE);
                };
                return this.done(n);
            };

            // ===== USING, STRUCTS AND NAMESPACES =====

            // IDENTIFIER ('::' IDENTIFIER)* joined with "__"
            def namespace_path() -> byte*
            {
                byte* path = this.ident();
                if (this.failed) { return (byte*)0; };
                while (this.expect(TokenType.SCOPE))
                {
                    this.advance();
                    path = this.cat2(this.cat2(path, g"__\0"), this.ident());
                    if (this.failed) { return (byte*)0; };
                };
                return path;
            };

            // 'using' path (',' path)* ';'    (kind is USING_STATEMENT or NOT_USING_STATEMENT)
            def using_list(int kind) -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* first = this.mk(kind, line, col);
                if (this.failed) { return first; };
                first.text = this.namespace_path();
                if (this.failed) { return this.done(first); };
                Node* x;
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    x = this.mk(kind, line, col);
                    if (this.failed) { return this.done(first); };
                    nv_push(this.pending, x);
                    x.text = this.namespace_path();
                    if (this.failed) { return this.done(first); };
                };
                if (!this.consume(TokenType.SEMICOLON)) { return this.done(first); };
                return first;
            };

            def using_statement() -> Node*
            {
                this.advance();
                return this.using_list(NodeKind.USING_STATEMENT);
            };

            // 'using' was already consumed by the dispatch, so the '!' is behind us
            def not_using_statement() -> Node*
            {
                return this.using_list(NodeKind.NOT_USING_STATEMENT);
            };

            // '<' IDENTIFIER (',' IDENTIFIER)* '>' ahead of the current token
            def is_template_list() -> bool
            {
                int m = this.mark();
                bool r = false;
                this.advance();
                if (this.expect(TokenType.IDENTIFIER))
                {
                    this.advance();
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        if (!this.expect(TokenType.IDENTIFIER)) { break; };
                        this.advance();
                    };
                    r = this.expect(TokenType.GREATER_THAN);
                };
                this.reset(m);
                return r;
            };

            // Base struct name, with <T,U> arguments kept in the text. Pushed to holder.l<slot>.
            // Returns true when template arguments were present (the struct is then a template).
            def struct_base_ref(Node* holder, int slot) -> bool
            {
                Node* r = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                if (this.failed) { return false; };
                node_push(holder, slot, r);
                byte* name = this.ident();
                if (this.failed) { return false; };
                byte* arg;
                bool generic = false;
                if (this.expect(TokenType.LESS_THAN) & this.is_template_list())
                {
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
                    if (!this.failed) { this.consume(TokenType.GREATER_THAN); };
                    name = this.cat2(name, g">\0");
                };
                r.text = name;
                return generic;
            };

            // Adds a template parameter name to a struct node (l4) unless already declared
            def sd_param_add(Node* h, byte* s) -> void
            {
                int i;
                int c;
                Node* x;
                if (this.failed | s == (byte*)0) { return; };
                c = node_count(h, 4);
                while (i < c)
                {
                    if (cstr_eq(node_child(h, 4, i).text, s)) { return; };
                    i++;
                };
                x = this.mk(NodeKind.IDENTIFIER, h.line, h.col);
                if (this.failed) { return; };
                x.text = s;
                node_push(h, 4, x);
                return;
            };

            // base_ref (',' base_ref)* into holder.l<slot>
            def struct_base_list(Node* holder, int slot) -> bool
            {
                bool generic = this.struct_base_ref(holder, slot);
                while (!this.failed & this.expect(TokenType.COMMA))
                {
                    this.advance();
                    if (this.struct_base_ref(holder, slot)) { generic = true; };
                };
                return generic;
            };

            // struct_member -> type_spec IDENTIFIER (',' IDENTIFIER)* ('=' expression (',' expression)*)? ';'
            // Members are pushed to owner.l0. The first member owns the type, the rest copy it.
            def struct_member(Node* owner, bool is_private) -> void
            {
                int line = this.cur_line();
                int col = this.cur_col();
                TypeSpec* ts = this.type_spec();
                if (this.failed)
                {
                    typespec_free(ts);
                    return;
                };
                int base = 0;
                if (owner.l0 != (NodeVec*)0) { base = owner.l0.len; };
                int cnt = 0;
                Node* mem;
                Node* e;
                int k;
                bool more = true;
                while (more)
                {
                    mem = this.mk(NodeKind.STRUCT_MEMBER, line, col);
                    if (this.failed)
                    {
                        if (cnt == 0) { typespec_free(ts); };
                        return;
                    };
                    node_push(owner, 0, mem);
                    if (cnt == 0) { mem.ts = ts; } else { mem.ts = typespec_copy(ts); };
                    if (is_private) { mem.flags = NF_PRIVATE; };
                    mem.text = this.ident();
                    if (this.failed) { return; };
                    cnt++;
                    more = false;
                    if (this.expect(TokenType.COMMA) & this.type_at(1) == TokenType.IDENTIFIER)
                    {
                        this.advance();
                        more = true;
                    };
                };

                if (this.expect(TokenType.ASSIGN))
                {
                    this.advance();
                    more = true;
                    while (more)
                    {
                        e = this.expression();
                        if (this.failed) { return; };
                        if (k < cnt) { owner.l0.items[base + k].a = e; } else { node_free(e); };
                        k++;
                        more = false;
                        if (this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            more = true;
                        };
                    };
                };
                this.consume(TokenType.SEMICOLON);
                return;
            };

            // A nested struct goes to owner.l3, together with any prototypes queued behind it
            def nested_struct(Node* owner) -> void
            {
                Node* s = this.struct_def();
                if (this.failed) { return; };
                int k;
                if (s != (Node*)0) { node_push(owner, 3, s); };
                while (k < this.pending.len)
                {
                    node_push(owner, 3, this.pending.items[k]);
                    k++;
                };
                this.pending.len = 0;
                return;
            };

            // '{' (struct | struct_member)* '}' ';' of a public or private section
            def struct_section(Node* owner, bool is_private) -> void
            {
                this.advance();
                if (!this.consume(TokenType.LEFT_BRACE)) { return; };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        return;
                    };
                    if (this.expect(TokenType.STRUCT))
                    {
                        this.nested_struct(owner);
                        if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                    }
                    else
                    {
                        this.struct_member(owner, is_private);
                    };
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return;
            };

            // struct_def -> 'struct' IDENTIFIER (',' IDENTIFIER)*
            //               (':' bases (':' bases)?)? (';' | '{' (member | struct | public/private section | comptime)* '}' (':' bases)? ';')
            // Template structs (fparser.py registers them and returns None) are reported and skipped.
            // Extra names of a prototype list go to the pending queue.
            def struct_def() -> Node*
            {
                int m = this.mark();
                Node* n = this.mk(NodeKind.STRUCT_DEF, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                n.op = -1;
                this.advance();
                n.text = this.ident();
                if (this.failed) { return this.done(n); };

                if (this.expect(TokenType.LESS_THAN) & this.is_template_list())
                {
                    this.advance();
                    this.sd_param_add(n, this.ident());
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        this.sd_param_add(n, this.ident());
                    };
                    if (!this.failed) { this.consume(TokenType.GREATER_THAN); };
                    if (this.failed) { return this.done(n); };
                };

                PtrVec* names = pv_new();
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    pv_push(names, (void*)this.ident());
                    if (this.failed) { pv_free(names); return this.done(n); };
                };

                if (this.expect(TokenType.COLON))
                {
                    this.advance();
                    this.struct_base_list(n, 1);
                    if (!this.failed & this.expect(TokenType.COLON))
                    {
                        this.advance();
                        this.struct_base_list(n, 2);
                    };
                    if (this.failed) { pv_free(names); return this.done(n); };
                    if (this.expect(TokenType.SEMICOLON))
                    {
                        this.advance();
                        pv_free(names);
                        return n;
                    };
                };

                int line = n.line;
                int col = n.col;
                Node* x;
                int k;
                bool has_base = false;
                if (n.l1 != (NodeVec*)0) { has_base = n.l1.len > 0; };
                if (this.expect(TokenType.SEMICOLON) & !has_base)
                {
                    this.advance();
                    if (n.l4 != (NodeVec*)0) { n.l4.len = 0; };
                    while (k < names.len)
                    {
                        x = this.mk(NodeKind.STRUCT_DEF, line, col);
                        if (this.failed) { pv_free(names); return this.done(n); };
                        x.op = -1;
                        x.text = (byte*)names.items[k];
                        nv_push(this.pending, x);
                        k++;
                    };
                    pv_free(names);
                    return n;
                };

                if (names.len > 0)
                {
                    pv_free(names);
                    this.error(g"Comma-separated names are only allowed for prototypes (forward declarations)\0");
                    return this.done(n);
                };
                pv_free(names);

                if (!this.consume(TokenType.LEFT_BRACE)) { return this.done(n); };
                Node* cb;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    };
                    if (this.expect(TokenType.PUBLIC)) { this.struct_section(n, false); }
                    elif (this.expect(TokenType.PRIVATE)) { this.struct_section(n, true); }
                    elif (this.expect(TokenType.STRUCT)) { this.nested_struct(n); }
                    elif (this.expect(TokenType.COMPTIME))
                    {
                        cb = this.comptime_block();
                        if (this.failed) { break; };
                        if (n.l0 != (NodeVec*)0) { cb.ival = n.l0.len; };
                        node_push(n, 5, cb);
                    }
                    else { this.struct_member(n, false); };
                };
                if (this.failed) { return this.done(n); };
                this.consume(TokenType.RIGHT_BRACE);

                if (!this.failed & this.expect(TokenType.COLON))
                {
                    this.advance();
                    this.struct_base_list(n, 2);
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (this.failed) { return this.done(n); };
                if (node_count(n, 4) > 0)
                {
                    TemplateEntry* te = te_new();
                    int ti;
                    int tc = node_count(n, 4);
                    while (ti < tc)
                    {
                        pv_push(te.params, (void*)this.own(ts_dup(node_child(n, 4, ti).text)));
                        ti++;
                    };
                    this.last_template = n.text;
                    if (this.in_comptime > 0)
                    {
                        this.register_template(n.text, 1, te, node_clone(n));
                        return n;
                    };
                    this.register_template(n.text, 1, te, n);
                    return (Node*)0;
                };
                return n;
            };

            // ----- namespaces -----

            // Lazily created NODE_LIST held in ns.a (variables), ns.b (nested namespaces) or ns.c (bases)
            def ns_list(Node* ns, int which) -> Node*
            {
                Node* l;
                if (which == 0) { l = ns.a; }
                elif (which == 1) { l = ns.b; }
                else { l = ns.c; };
                if (l != (Node*)0) { return l; };
                l = this.mk(NodeKind.NODE_LIST, ns.line, ns.col);
                if (this.failed) { return l; };
                if (which == 0) { ns.a = l; }
                elif (which == 1) { ns.b = l; }
                else { ns.c = l; };
                return l;
            };

            // Slot of the namespace list that holds nodes of this kind, -1 for the variables list
            def ns_slot(Node* x) -> int
            {
                int k = x.kind;
                if (k == NodeKind.FUNCTION_DEF) { return 0; };
                if (k == NodeKind.STRUCT_DEF) { return 1; };
                if (k == NodeKind.OBJECT_DEF | k == NodeKind.TRAIT_DEF | k == NodeKind.INTERFACE_DEF) { return 2; };
                if (k == NodeKind.ENUM_DEF | k == NodeKind.ENUM_DEF_STATEMENT) { return 3; };
                if (k == NodeKind.UNION_DEF | k == NodeKind.UNION_DEF_STATEMENT) { return 4; };
                if (k == NodeKind.EXTERN_BLOCK) { return 5; };
                return -1;
            };

            // ns__name and, except for variables (already defined by the declaration), name
            def define_in_namespace(byte* name, int kind, TypeSpec* ts) -> void
            {
                if (this.st == (FXC_SYMTABLE*)0 | name == (byte*)0 | this.ns_path == (byte*)0) { return; };
                st_define(this.st, this.cat2(this.cat2(this.ns_path, g"__\0"), name), kind, ts, (Node*)0);
                if (kind != SymbolKind.VARIABLE) { st_define(this.st, name, kind, ts, (Node*)0); };
                return;
            };

            // The definition inside an enum or union statement (null child means a stub, kept as is)
            def unwrap_def(Node* x) -> Node*
            {
                if (x.kind != NodeKind.ENUM_DEF_STATEMENT & x.kind != NodeKind.UNION_DEF_STATEMENT) { return x; };
                if (x.a == (Node*)0) { return x; };
                Node* d = x.a;
                x.a = (Node*)0;
                node_free(x);
                return d;
            };

            // Routes x into its list of ns and registers its name
            def ns_add(Node* ns, Node* x0) -> void
            {
                Node* x = this.unwrap_def(x0);
                int slot = this.ns_slot(x);
                Node* l;
                if (slot >= 0) { node_push(ns, slot, x); }
                else
                {
                    l = this.ns_list(ns, 0);
                    if (this.failed) { return; };
                    node_push(l, 0, x);
                };
                if ((x.flags `& NF_STUB) != 0) { return; };
                if (x.kind == NodeKind.FUNCTION_DEF) { this.define_in_namespace(x.text, SymbolKind.FUNCTION, (TypeSpec*)0); }
                elif (x.kind == NodeKind.STRUCT_DEF) { this.define_in_namespace(x.text, SymbolKind.TYPE, (TypeSpec*)0); }
                elif (x.kind == NodeKind.ENUM_DEF) { this.define_in_namespace(x.text, SymbolKind.ENUM, (TypeSpec*)0); }
                elif (x.kind == NodeKind.UNION_DEF) { this.define_in_namespace(x.text, SymbolKind.UNION, (TypeSpec*)0); }
                elif (x.kind == NodeKind.VARIABLE_DECLARATION) { this.define_in_namespace(x.text, SymbolKind.VARIABLE, x.ts); };
                return;
            };

            // x (may be null) and everything queued behind it
            def ns_add_all(Node* ns, Node* x) -> void
            {
                int k;
                if (x != (Node*)0) { this.ns_add(ns, x); };
                while (!this.failed & k < this.pending.len)
                {
                    this.ns_add(ns, this.pending.items[k]);
                    k++;
                };
                this.pending.len = 0;
                return;
            };

            // Moves every item of from into dst.l<slot>
            def move_items(NodeVec* src, Node* dst, int slot) -> void
            {
                if (src == (NodeVec*)0) { return; };
                int i;
                while (i < src.len)
                {
                    node_push(dst, slot, src.items[i]);
                    i++;
                };
                src.len = 0;
                return;
            };

            // Adds a nested namespace, merging it into an earlier one of the same name
            def ns_nest(Node* ns, Node* x) -> void
            {
                if (x == (Node*)0) { return; };
                Node* lst = this.ns_list(ns, 1);
                if (this.failed) { node_free(x); return; };
                Node* ex;
                Node* dl;
                int i, s;
                int total;
                if (lst.l0 != (NodeVec*)0) { total = lst.l0.len; };
                while (i < total)
                {
                    ex = lst.l0.items[i];
                    if (ex.text != (byte*)0 & x.text != (byte*)0)
                    {
                        if (cstr_eq(ex.text, x.text))
                        {
                            s = 0;
                            while (s < 5)
                            {
                                if (s == 0) { this.move_items(x.l0, ex, 0); }
                                elif (s == 1) { this.move_items(x.l1, ex, 1); }
                                elif (s == 2) { this.move_items(x.l2, ex, 2); }
                                elif (s == 3) { this.move_items(x.l3, ex, 3); }
                                else { this.move_items(x.l4, ex, 4); };
                                s++;
                            };
                            s = 0;
                            while (s < 3)
                            {
                                if (s == 0) { dl = x.a; }
                                elif (s == 1) { dl = x.b; }
                                else { dl = x.c; };
                                if (dl != (Node*)0)
                                {
                                    this.move_items(dl.l0, this.ns_list(ex, s), 0);
                                };
                                s++;
                            };
                            node_free(x);
                            return;
                        };
                    };
                    i++;
                };
                node_push(lst, 0, x);
                return;
            };

            // One entry of a namespace body
            // A template registered inside a namespace is also reachable as ns__name and ns::name
            def ns_tmpl_alias(Node* x) -> void
            {
                byte* bare = this.last_template;
                if (x != (Node*)0 | bare == (byte*)0 | this.ns_path == (byte*)0) { return; };
                this.template_alias(this.cat2(this.cat2(this.ns_path, g"__\0"), bare), bare);
                this.template_alias(this.cat2(this.cat2(this.ns_path, g"::\0"), bare), bare);
                return;
            };

            def ns_item(Node* ns) -> void
            {
                int c = this.cur();
                Node* x;
                if (c == TokenType.GLOBAL | c == TokenType.LOCAL | c == TokenType.HEAP | c == TokenType.STACK |
                    c == TokenType.REGISTER | c == TokenType.SINGINIT | c == TokenType.CONST | c == TokenType.VOLATILE)
                {
                    x = this.variable_declaration();
                    if (this.failed) { return; };
                    this.ns_add_all(ns, x);
                    this.consume(TokenType.SEMICOLON);
                }
                elif (this.expect3(TokenType.INLINE, TokenType.DEF, TokenType.NO_MANGLE) | this.is_calling_conv(c) | this.is_bare_function_def())
                {
                    this.last_template = (byte*)0;
                    x = this.function_def();
                    if (this.failed) { return; };
                    this.ns_tmpl_alias(x);
                    this.ns_add_all(ns, x);
                }
                elif (c == TokenType.STRUCT)
                {
                    x = this.struct_def();
                    if (this.failed) { return; };
                    this.ns_tmpl_alias(x);
                    this.ns_add_all(ns, x);
                }
                elif (c == TokenType.OBJECT)
                {
                    x = this.object_def();
                    if (this.failed) { return; };
                    this.ns_tmpl_alias(x);
                    this.ns_add_all(ns, x);
                }
                elif (c == TokenType.TRAIT)
                {
                    x = this.trait_def();
                    if (this.failed) { return; };
                    this.ns_add_all(ns, x);
                }
                elif (c == TokenType.INTERFACE)
                {
                    x = this.interface_def();
                    if (this.failed) { return; };
                    this.ns_add_all(ns, x);
                }
                elif (this.is_trait_prefixed_object())
                {
                    x = this.trait_prefixed_object();
                    if (this.failed) { return; };
                    this.ns_tmpl_alias(x);
                    this.ns_add_all(ns, x);
                }
                elif (c == TokenType.ENUM | this.type_at(1) == TokenType.ENUM)
                {
                    x = this.enum_def();
                    if (this.failed) { return; };
                    this.ns_add_all(ns, x);
                }
                elif (c == TokenType.UNION)
                {
                    x = this.union_def();
                    if (this.failed) { return; };
                    this.ns_add_all(ns, x);
                }
                elif (c == TokenType.OPERATOR)
                {
                    x = this.operator_def();
                    if (this.failed) { return; };
                    this.ns_add_all(ns, x);
                }
                elif (c == TokenType.EXTERN)
                {
                    x = this.extern_statement();
                    if (this.failed) { return; };
                    this.ns_add_all(ns, x);
                }
                elif (c == TokenType.NAMESPACE)
                {
                    x = this.namespace_def();
                    if (this.failed) { return; };
                    this.ns_nest(ns, x);
                }
                elif (c == TokenType.IF)
                {
                    x = this.if_statement();
                    node_free(x);
                }
                elif (this.is_variable_declaration())
                {
                    x = this.variable_declaration();
                    if (this.failed) { return; };
                    this.ns_add_all(ns, x);
                    this.consume(TokenType.SEMICOLON);
                }
                else
                {
                    this.error(g"Expected function, struct, object, namespace, enum, union, or variable declaration\0");
                };
                return;
            };

            // namespace_def -> 'namespace' IDENTIFIER (':' IDENTIFIER (',' IDENTIFIER)*)? '{' namespace_item* '}' ';'
            def namespace_def() -> Node*
            {
                Node* n = this.mk(NodeKind.NAMESPACE_DEF, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.advance();
                n.text = this.ident();
                if (this.failed) { return this.done(n); };

                byte* saved = this.ns_path;
                if (saved == (byte*)0) { this.ns_path = n.text; }
                else { this.ns_path = this.cat2(this.cat2(saved, g"__\0"), n.text); };

                Node* l;
                Node* b;
                if (this.expect(TokenType.COLON))
                {
                    this.advance();
                    l = this.ns_list(n, 2);
                    bool more = !this.failed;
                    while (more)
                    {
                        b = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                        if (this.failed) { break; };
                        node_push(l, 0, b);
                        b.text = this.ident();
                        if (this.failed) { break; };
                        more = false;
                        if (this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            more = true;
                        };
                    };
                };

                if (!this.failed) { this.consume(TokenType.LEFT_BRACE); };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    };
                    this.ns_item(n);
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                this.ns_path = saved;
                return this.done(n);
            };

            // ===== ENUMS AND UNIONS =====

            // ENUM_DEF_STATEMENT wrapping a fresh ENUM_DEF. The type is copied when ts is given.
            def enum_node(byte* name, TypeSpec* ts, int line, int col) -> Node*
            {
                Node* s = this.mk(NodeKind.ENUM_DEF_STATEMENT, line, col);
                if (this.failed) { return s; };
                Node* d = this.mk(NodeKind.ENUM_DEF, line, col);
                if (this.failed) { node_free(s); return d; };
                s.a = d;
                d.text = name;
                if (ts != (TypeSpec*)0) { d.ts = typespec_copy(ts); };
                return s;
            };

            // enum_def -> (type_spec)? 'enum' IDENTIFIER (',' IDENTIFIER)* (';' | '{' enum_item (',' enum_item)* '}' ';')
            // enum_item -> IDENTIFIER ('=' INTEGER)?
            // Items are IDENTIFIER nodes whose ival is the value.
            def enum_def() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* s = this.mk(NodeKind.ENUM_DEF_STATEMENT, line, col);
                if (this.failed) { return s; };
                Node* d = this.mk(NodeKind.ENUM_DEF, line, col);
                if (this.failed) { node_free(s); return d; };
                s.a = d;

                if (!this.expect(TokenType.ENUM)) { d.ts = this.type_spec(); };
                if (this.failed) { return this.done(s); };
                if (!this.consume(TokenType.ENUM)) { return this.done(s); };
                d.text = this.ident();
                if (this.failed) { return this.done(s); };

                PtrVec* names = pv_new();
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    pv_push(names, (void*)this.ident());
                    if (this.failed)
                    {
                        pv_free(names);
                        return this.done(s);
                    };
                };

                Node* x;
                int k;
                if (this.expect(TokenType.SEMICOLON))
                {
                    this.advance();
                    while (k < names.len)
                    {
                        x = this.enum_node((byte*)names.items[k], d.ts, line, col);
                        if (this.failed)
                        {
                            pv_free(names);
                            return this.done(s);
                        };
                        nv_push(this.pending, x);
                        k++;
                    };
                    pv_free(names);
                    return s;
                };
                if (names.len > 0)
                {
                    pv_free(names);
                    this.error(g"Comma-separated names are only allowed for prototypes (forward declarations)\0");
                    return this.done(s);
                };
                pv_free(names);

                if (!this.consume(TokenType.LEFT_BRACE)) { return this.done(s); };
                i64 current = 0;
                bool ok;
                Node* item;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    };
                    item = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                    if (this.failed) { break; };
                    node_push(d, 0, item);
                    item.text = this.ident();
                    if (this.failed) { break; };
                    if (this.expect(TokenType.ASSIGN))
                    {
                        this.advance();
                        if (!this.expect(TokenType.SINT_LITERAL))
                        {
                            this.fail_expected(TokenType.SINT_LITERAL);
                            break;
                        };
                        ok = true;
                        current = this.parse_int(this.cur_value(), @ok);
                        this.advance();
                    };
                    item.ival = current;
                    current++;
                    if (this.expect(TokenType.COMMA)) { this.advance(); }
                    elif (!this.expect(TokenType.RIGHT_BRACE))
                    {
                        this.error(g"Expected ',' or '}' in enum definition\0");
                    };
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(s);
            };

            // union_member -> type_spec IDENTIFIER ('=' expression)? ';'
            def union_member(Node* d) -> void
            {
                Node* m = this.mk(NodeKind.UNION_MEMBER, this.cur_line(), this.cur_col());
                if (this.failed) { return; };
                node_push(d, 0, m);
                m.ts = this.type_spec();
                if (this.failed) { return; };
                m.text = this.ident();
                if (this.failed) { return; };
                if (this.expect(TokenType.ASSIGN))
                {
                    this.advance();
                    m.a = this.expression();
                    if (this.failed) { return; };
                };
                this.consume(TokenType.SEMICOLON);
                return;
            };

            // union_def -> 'union' IDENTIFIER (';' | '{' union_member* '}' ('#' IDENTIFIER)? ';')
            def union_def() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* s = this.mk(NodeKind.UNION_DEF_STATEMENT, line, col);
                if (this.failed) { return s; };
                Node* d = this.mk(NodeKind.UNION_DEF, line, col);
                if (this.failed) { node_free(s); return d; };
                s.a = d;
                this.advance();
                d.text = this.ident();
                if (this.failed) { return this.done(s); };
                if (this.expect(TokenType.SEMICOLON))
                {
                    this.advance();
                    return s;
                };
                if (!this.consume(TokenType.LEFT_BRACE)) { return this.done(s); };
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    };
                    this.union_member(d);
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                if (!this.failed & this.expect(TokenType.TAG))
                {
                    this.advance();
                    d.text2 = this.ident();
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(s);
            };

            // ===== OBJECTS AND TRAITS =====

            def error3(byte* a, byte* b, byte* c) -> void
            {
                this.error(this.cat2(this.cat2(a, b), c));
                return;
            };

            // TRAIT_DEF registered by trait_def, or null
            def find_trait(byte* name) -> Node*
            {
                int i;
                Node* t;
                while (i < this.trait_defs.len)
                {
                    t = (Node*)this.trait_defs.items[i];
                    if (cstr_eq(t.text, name)) { return t; };
                    i++;
                };
                return (Node*)0;
            };

            // FUNCTION_DEF method of o with this name, or null
            def find_method(Node* o, byte* name) -> Node*
            {
                if (o.l1 == (NodeVec*)0) { return (Node*)0; };
                int i;
                Node* m;
                while (i < o.l1.len)
                {
                    m = o.l1.items[i];
                    if (m.kind == NodeKind.FUNCTION_DEF & m.text != (byte*)0)
                    {
                        if (cstr_eq(m.text, name)) { return m; };
                    };
                    i++;
                };
                return (Node*)0;
            };

            // Parameters other than the implicit 'this'
            def explicit_params(Node* f) -> int
            {
                int n, i;
                Node* p;
                while (i < this.param_count(f))
                {
                    p = f.l0.items[i];
                    if (p.text == (byte*)0) { n++; }
                    elif (!cstr_eq(p.text, g"this\0")) { n++; };
                    i++;
                };
                return n;
            };

            def method_start(int off) -> bool
            {
                int t = this.type_at(off);
                return t == TokenType.INLINE | t == TokenType.DEF | this.is_calling_conv(t);
            };

            // Prototype stub standing for a template method or template trait prototype
            def template_stub() -> Node*
            {
                Node* s = this.mk(NodeKind.FUNCTION_DEF, this.cur_line(), this.cur_col());
                if (this.failed) { return s; };
                s.text = this.last_template;
                TemplateEntry* te = this.template_lookup(this.last_template);
                if (te != (TemplateEntry*)0)
                {
                    if (te.node != (Node*)0)
                    {
                        if (te.node.ts != (TypeSpec*)0) { s.ts = typespec_copy(te.node.ts); };
                    };
                };
                this.mark_proto(s);
                s.flags = s.flags `| NF_TEMPLATE;
                return s;
            };

            def add_method(Node* o, Node* m, bool is_private, byte* friend_name, int ovr) -> void
            {
                if (is_private) { m.flags = m.flags `| NF_PRIVATE; };
                m.flags = m.flags `| ovr;
                if (friend_name != (byte*)0) { m.text3 = friend_name; };
                node_push(o, 1, m);
                return;
            };

            // One method (and the rest of a prototype list) into o.l1
            def collect_method(Node* o, bool is_private, byte* friend_name, int ovr) -> void
            {
                this.last_template = (byte*)0;
                Node* m = this.function_def();
                if (this.failed) { return; };
                int k;
                if (m == (Node*)0)
                {
                    if (this.last_template == (byte*)0)
                    {
                        this.error(g"Internal: template method registered no name\0");
                        return;
                    };
                    if (o.text != (byte*)0)
                    {
                        this.template_alias(this.cat2(this.cat2(o.text, g".\0"), this.last_template), this.last_template);
                    };
                    m = this.template_stub();
                    if (this.failed) { return; };
                };
                this.add_method(o, m, is_private, friend_name, ovr);
                while (k < this.pending.len)
                {
                    this.add_method(o, this.pending.items[k], is_private, friend_name, ovr);
                    k++;
                };
                this.pending.len = 0;
                return;
            };

            // A nested object or struct (and queued prototypes) into o.l<slot>
            def nested_push(Node* o, int slot, Node* x, bool is_private) -> void
            {
                int k;
                if (x != (Node*)0)
                {
                    if (is_private) { x.flags = x.flags `| NF_PRIVATE; };
                    node_push(o, slot, x);
                };
                while (k < this.pending.len)
                {
                    x = this.pending.items[k];
                    if (is_private) { x.flags = x.flags `| NF_PRIVATE; };
                    node_push(o, slot, x);
                    k++;
                };
                this.pending.len = 0;
                return;
            };

            // Field declarations become STRUCT_MEMBER nodes in o.l0
            def field_members(Node* o, bool is_private, byte* friend_name) -> void
            {
                Node* v = this.variable_declaration();
                if (this.failed) { return; };
                int k;
                if (v != (Node*)0)
                {
                    v.kind = NodeKind.STRUCT_MEMBER;
                    v.flags = 0;
                    if (is_private) { v.flags = NF_PRIVATE; };
                    v.text2 = friend_name;
                    node_push(o, 0, v);
                };
                while (k < this.pending.len)
                {
                    v = this.pending.items[k];
                    v.kind = NodeKind.STRUCT_MEMBER;
                    v.flags = 0;
                    if (is_private) { v.flags = NF_PRIVATE; };
                    v.text2 = friend_name;
                    node_push(o, 0, v);
                    k++;
                };
                this.pending.len = 0;
                this.consume(TokenType.SEMICOLON);
                return;
            };

            // method (with '+' override or '!+' no-override marker), nested object, nested struct or field
            def object_member(Node* o, bool is_private, byte* friend_name) -> void
            {
                int ovr = 0;
                if (this.expect(TokenType.NOT) & this.type_at(1) == TokenType.PLUS & this.method_start(2))
                {
                    ovr = NF_NO_OVERRIDE;
                    this.advance();
                    this.advance();
                }
                elif (this.expect(TokenType.PLUS) & this.method_start(1))
                {
                    ovr = NF_OVERRIDE;
                    this.advance();
                };
                Node* x;
                if (this.expect3(TokenType.INLINE, TokenType.DEF, TokenType.CDECL) | this.is_calling_conv(this.cur()))
                {
                    this.collect_method(o, is_private, friend_name, ovr);
                }
                elif (this.expect(TokenType.OBJECT))
                {
                    x = this.object_def();
                    if (this.failed) { return; };
                    this.nested_push(o, 3, x, is_private);
                    this.consume(TokenType.SEMICOLON);
                }
                elif (this.expect(TokenType.STRUCT))
                {
                    x = this.struct_def();
                    if (this.failed) { return; };
                    this.nested_push(o, 4, x, is_private);
                    this.consume(TokenType.SEMICOLON);
                }
                else
                {
                    this.field_members(o, is_private, friend_name);
                };
                return;
            };

            // Members of an object up to (not including) the closing '}'
            def object_body(Node* o) -> void
            {
                bool is_private;
                byte* friend_name;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        return;
                    };
                    if (this.expect2(TokenType.PUBLIC, TokenType.PRIVATE))
                    {
                        is_private = this.expect(TokenType.PRIVATE);
                        friend_name = (byte*)0;
                        this.advance();
                        if (is_private & this.expect(TokenType.COLON))
                        {
                            this.advance();
                            friend_name = this.ident();
                        };
                        if (!this.failed) { this.consume(TokenType.LEFT_BRACE); };
                        while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                        {
                            if (this.expect(TokenType.EOF))
                            {
                                this.fail_expected(TokenType.RIGHT_BRACE);
                                return;
                            };
                            this.object_member(o, is_private, friend_name);
                        };
                        if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                        if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                    }
                    else
                    {
                        this.object_member(o, false, (byte*)0);
                    };
                };
                return;
            };

            // One interface argument: IDENTIFIER or 'this'
            def iface_arg(Node* iface) -> void
            {
                Node* a = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                if (this.failed) { return; };
                node_push(iface, 0, a);
                if (this.expect(TokenType.THIS))
                {
                    a.text = g"this\0";
                    this.advance();
                }
                else
                {
                    a.text = this.ident();
                };
                return;
            };

            // '}' ':' Name '(' args ')' (',' Name '(' args ')')*  : NODE_LIST entries in o.e
            def iface_attachments(Node* o) -> void
            {
                Node* iface;
                bool more = true;
                while (more & !this.failed)
                {
                    this.advance();
                    iface = this.mk(NodeKind.NODE_LIST, this.cur_line(), this.cur_col());
                    if (this.failed) { return; };
                    if (o.e == (Node*)0)
                    {
                        o.e = this.mk(NodeKind.NODE_LIST, iface.line, iface.col);
                        if (this.failed) { node_free(iface); return; };
                    };
                    node_push(o.e, 0, iface);
                    iface.text = this.ident();
                    if (this.failed) { return; };
                    if (!this.consume(TokenType.LEFT_PAREN)) { return; };
                    if (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        this.iface_arg(iface);
                        while (!this.failed & this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            this.iface_arg(iface);
                        };
                    };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                    more = this.expect(TokenType.COMMA);
                };
                return;
            };

            // Trait names go to o.l5 as IDENTIFIER nodes
            def object_traits(Node* o, PtrVec* tnames) -> void
            {
                if (tnames == (PtrVec*)0) { return; };
                int i;
                Node* t;
                while (i < tnames.len)
                {
                    t = this.mk(NodeKind.IDENTIFIER, o.line, o.col);
                    if (this.failed) { return; };
                    t.text = (byte*)tnames.items[i];
                    node_push(o, 5, t);
                    i++;
                };
                return;
            };

            // __init, __exit and __expr are mandatory and have fixed signatures
            def check_object_methods(Node* o) -> void
            {
                Node* m = this.find_method(o, g"__init\0");
                if (m == (Node*)0)
                {
                    this.error3(g"Object '\0", o.text, g"' is missing a __init() method. Every object must define 'def __init(...) -> this { ... };' to specify its constructor.\0");
                    return;
                };
                if (m.ts == (TypeSpec*)0) { this.error3(g"Object '\0", o.text, g"': __init() must return 'this'\0"); return; };
                if (m.ts.base_type != DataType.THIS)
                {
                    this.error3(g"Object '\0", o.text, g"': __init() must return 'this'\0");
                    return;
                };

                m = this.find_method(o, g"__exit\0");
                if (m == (Node*)0)
                {
                    this.error3(g"Object '\0", o.text, g"' is missing a __exit() method. Every object must define 'def __exit() -> void { ... };' to specify its destructor.\0");
                    return;
                };
                if (this.explicit_params(m) > 0)
                {
                    this.error3(g"Object '\0", o.text, g"': __exit() must take no parameters\0");
                    return;
                };
                if (m.ts != (TypeSpec*)0)
                {
                    if (m.ts.base_type != DataType.VOID | m.ts.pointer_depth > 0)
                    {
                        this.error3(g"Object '\0", o.text, g"': __exit() must return void\0");
                        return;
                    };
                };

                m = this.find_method(o, g"__expr\0");
                if (m == (Node*)0)
                {
                    this.error3(g"Object '\0", o.text, g"' is missing a __expr() method. Every object must define 'def __expr() -> <type> { ... };' to specify its expression-context value.\0");
                    return;
                };
                if (this.explicit_params(m) > 0)
                {
                    this.error3(g"Object '\0", o.text, g"': __expr() must take no parameters\0");
                    return;
                };
                if (m.ts == (TypeSpec*)0)
                {
                    this.error3(g"Object '\0", o.text, g"': __expr() must have a non-void return type\0");
                    return;
                };
                if (m.ts.base_type == DataType.VOID & m.ts.pointer_depth == 0)
                {
                    this.error3(g"Object '\0", o.text, g"': __expr() must have a non-void return type\0");
                };
                return;
            };

            // Every non-template prototype of each declared trait must be implemented
            def check_object_traits(Node* o) -> void
            {
                if (o.l5 == (NodeVec*)0) { return; };
                int i, j, total;
                Node* t;
                Node* p;
                while (i < o.l5.len)
                {
                    t = this.find_trait(o.l5.items[i].text);
                    if (t == (Node*)0)
                    {
                        this.error3(g"Object '\0", o.text, this.cat2(this.cat2(g"' declares trait '\0", o.l5.items[i].text), g"' which has not been defined\0"));
                        return;
                    };
                    j = 0;
                    total = 0;
                    if (t.l0 != (NodeVec*)0) { total = t.l0.len; };
                    while (j < total)
                    {
                        p = t.l0.items[j];
                        if ((p.flags `& NF_TEMPLATE) == 0 & p.text != (byte*)0)
                        {
                            if (this.find_method(o, p.text) == (Node*)0)
                            {
                                this.error3(this.cat2(this.cat2(g"Object '\0", o.text), g"' doesn't implement required function '\0"), p.text, this.cat2(this.cat2(g"' from trait '\0", t.text), g"'\0"));
                                return;
                            };
                        };
                        j++;
                    };
                    i++;
                };
                return;
            };

            // One object template parameter: IDENTIFIER into o.d and te.params
            def object_tparam(Node* o, TemplateEntry* te) -> void
            {
                Node* x = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                if (this.failed) { return; };
                x.text = this.ident();
                if (this.failed)
                {
                    node_free(x);
                    return;
                };
                node_push(o.d, 0, x);
                pv_push(te.params, (void*)this.own(ts_dup(x.text)));
                return;
            };

            // object_def -> 'object' IDENTIFIER (',' IDENTIFIER)* (':' bases)? (';' | '{' body '}' (':' interface attachments)? ';')
            // m is the mark of the start of the construct (before any trait names).
            // Template objects and objects with base objects are reported (no inheritance resolution).
            def object_with_traits(int m, PtrVec* tnames) -> Node*
            {
                NameMap* prev_act = this.active_tp;
                TemplateEntry* prev_cur = this.tmpl_cur;
                TemplateEntry* te;
                Node* o;
                this.tmpl_cur = (TemplateEntry*)0;
                o = this.object_with_traits_inner(m, tnames);
                te = this.tmpl_cur;
                this.tmpl_cur = prev_cur;
                if (this.active_tp != prev_act)
                {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                };
                if (te == (TemplateEntry*)0) { return o; };
                if (this.failed | o == (Node*)0)
                {
                    te_free(te);
                    return o;
                };
                if ((o.flags `& NF_PROTOTYPE) != 0)
                {
                    te_free(te);
                    return o;
                };
                this.last_template = o.text;
                if (this.in_comptime > 0)
                {
                    this.register_template(o.text, 2, te, node_clone(o));
                    return o;
                };
                this.register_template(o.text, 2, te, o);
                return (Node*)0;
            };

            def object_with_traits_inner(int m, PtrVec* tnames) -> Node*
            {
                Node* o = this.mk(NodeKind.OBJECT_DEF, this.cur_line(), this.cur_col());
                if (this.failed) { return o; };
                this.advance();
                o.text = this.ident();
                if (this.failed) { return this.done(o); };

                if (this.expect(TokenType.LESS_THAN) & this.is_template_list())
                {
                    TemplateEntry* te = te_new();
                    Node* pl = this.mk(NodeKind.NODE_LIST, o.line, o.col);
                    if (this.failed)
                    {
                        te_free(te);
                        return this.done(o);
                    };
                    o.d = pl;
                    this.advance();
                    this.object_tparam(o, te);
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        this.object_tparam(o, te);
                    };
                    if (!this.failed) { this.consume(TokenType.GREATER_THAN); };
                    if (this.failed)
                    {
                        te_free(te);
                        return this.done(o);
                    };
                    this.tmpl_cur = te;
                    this.tp_activate(te);
                };
                this.object_traits(o, tnames);

                PtrVec* names = pv_new();
                while (this.expect(TokenType.COMMA))
                {
                    this.advance();
                    pv_push(names, (void*)this.ident());
                    if (this.failed) { pv_free(names); return this.done(o); };
                };

                Node* b;
                bool more;
                if (this.expect(TokenType.COLON))
                {
                    if (names.len > 0)
                    {
                        pv_free(names);
                        this.error(g"Cannot use comma-separated prototype names with an inheritance list\0");
                        return this.done(o);
                    };
                    this.advance();
                    more = true;
                    while (more & !this.failed)
                    {
                        b = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                        if (this.failed) { break; };
                        node_push(o, 2, b);
                        b.text = this.ident();
                        more = false;
                        if (!this.failed & this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            more = !this.expect2(TokenType.LEFT_BRACE, TokenType.SEMICOLON);
                        };
                    };
                    if (this.failed) { pv_free(names); return this.done(o); };
                };

                int k;
                Node* x;
                if (this.expect(TokenType.SEMICOLON))
                {
                    this.advance();
                    o.flags = NF_PROTOTYPE;
                    if (o.d != (Node*)0)
                    {
                        node_free(o.d);
                        o.d = (Node*)0;
                    };
                    while (k < names.len)
                    {
                        x = this.mk(NodeKind.OBJECT_DEF, o.line, o.col);
                        if (this.failed) { pv_free(names); return this.done(o); };
                        x.flags = NF_PROTOTYPE;
                        x.text = (byte*)names.items[k];
                        this.object_traits(x, tnames);
                        nv_push(this.pending, x);
                        k++;
                    };
                    pv_free(names);
                    return o;
                };
                if (names.len > 0)
                {
                    pv_free(names);
                    this.error(g"Comma-separated names are only allowed for prototypes (forward declarations)\0");
                    return this.done(o);
                };
                pv_free(names);

                if (o.d != (Node*)0) { nm_put(this.tobj_fwd, o.text, (void*)o); };
                if (!this.consume(TokenType.LEFT_BRACE)) { return this.done(o); };
                if (this.st != (FXC_SYMTABLE*)0) { st_enter_scope(this.st); };
                this.object_body(o);
                if (this.st != (FXC_SYMTABLE*)0) { st_exit_scope(this.st); };
                if (o.d != (Node*)0) { nm_del(this.tobj_fwd, o.text); };
                if (this.failed) { return this.done(o); };
                this.consume(TokenType.RIGHT_BRACE);
                if (!this.failed & this.expect(TokenType.COLON)) { this.iface_attachments(o); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (this.failed) { return this.done(o); };

                if (node_count(o, 2) > 0) { this.resolve_inheritance(o); };
                if (this.failed) { return this.done(o); };
                if (this.find_method(o, g"__init\0") != (Node*)0) { nm_put(this.oinit, o.text, (void*)o); };
                this.check_object_methods(o);
                if (!this.failed) { this.check_object_traits(o); };
                if (!this.failed & o.d == (Node*)0) { nm_put(this.pobjs, o.text, (void*)o); };
                return this.done(o);
            };

            // ----- object inheritance (fparser._resolve_inheritance) -----

            def inh_in_path(PtrVec* path, byte* n) -> bool
            {
                int i;
                while (i < path.len)
                {
                    if (cstr_eq((byte*)path.items[i], n)) { return true; };
                    i++;
                };
                return false;
            };

            // Members of the parent chain of obj, parents first, each paired with its origin object
            def inh_members(byte* obj, PtrVec* path, PtrVec* outm, PtrVec* outo, byte* child) -> void
            {
                Node* ob;
                Node* m;
                int i, c;
                if (this.failed) { return; };
                if (this.inh_in_path(path, obj)) { return; };
                pv_push(path, (void*)obj);
                if (!nm_has(this.pobjs, obj))
                {
                    this.error(this.cat2(this.cat2(this.cat2(this.cat2(g"Inheritance error: '\0", obj), g"' must be fully defined before '\0"), child), g"' can inherit from it\0"));
                    path.len--;
                    return;
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
                    if ((m.flags `& NF_PRIVATE) != 0)
                    {
                        if (m.text2 != (byte*)0)
                        {
                            if (cstr_eq(m.text2, child))
                            {
                                pv_push(outm, (void*)m);
                                pv_push(outo, (void*)obj);
                            };
                        };
                    }
                    else
                    {
                        pv_push(outm, (void*)m);
                        pv_push(outo, (void*)obj);
                    };
                };
                path.len--;
                return;
            };

            def inh_methods(byte* obj, PtrVec* path, PtrVec* outm, byte* child) -> void
            {
                Node* ob;
                Node* m;
                int i, c;
                if (this.inh_in_path(path, obj)) { return; };
                pv_push(path, (void*)obj);
                if (!nm_has(this.pobjs, obj))
                {
                    path.len--;
                    return;
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
                    if (m.kind != NodeKind.FUNCTION_DEF | m.text == (byte*)0) { continue; };
                    if (cstr_eq(m.text, g"__init\0") | cstr_eq(m.text, g"__exit\0") | cstr_eq(m.text, g"__expr\0")) { continue; };
                    if ((m.flags `& NF_PRIVATE) != 0)
                    {
                        if (m.text3 != (byte*)0)
                        {
                            if (cstr_eq(m.text3, child)) { pv_push(outm, (void*)m); };
                        };
                    }
                    else { pv_push(outm, (void*)m); };
                };
                path.len--;
                return;
            };

            // The node an inherited clone was copied from (fparser compares the FunctionDef objects)
            def inh_origin(Node* m) -> Node*
            {
                int i;
                while (i < this.inh_clone.len)
                {
                    if ((Node*)this.inh_clone.items[i] == m) { return (Node*)this.inh_orig.items[i]; };
                    i++;
                };
                return m;
            };

            def inh_clone_of(Node* m) -> Node*
            {
                Node* c = node_clone(m);
                pv_push(this.inh_clone, (void*)c);
                pv_push(this.inh_orig, (void*)this.inh_origin(m));
                return c;
            };

            def method_has_body(Node* m) -> bool
            {
                if (m.a == (Node*)0) { return false; };
                return node_count(m.a, 0) > 0;
            };

            // name(type, type) of a method without its 'this' parameter
            def sig_key(Node* m, bool for_message) -> byte*
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
                    if (p.text != (byte*)0)
                    {
                        if (cstr_eq(p.text, g"this\0")) { continue; };
                    };
                    if (p.ts == (TypeSpec*)0) { t = g"\0"; }
                    else { t = this.tp_repr(p.ts); };
                    pv_push(parts, (void*)t);
                };
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                if (!for_message)
                {
                    this.sb.put_str(m.text);
                    this.sb.put_str(g"(\0");
                };
                i = 0;
                while (i < parts.len)
                {
                    if (i > 0)
                    {
                        if (for_message) { this.sb.put_str(g", \0"); }
                        else { this.sb.put_str(g",\0"); };
                    };
                    this.sb.put_str((byte*)parts.items[i]);
                    i++;
                };
                pv_free(parts);
                return this.own_n(this.sb.mem, this.sb.len);
            };

            def inh_key_has(PtrVec* keys, byte* k) -> int
            {
                int i;
                while (i < keys.len)
                {
                    if (cstr_eq((byte*)keys.items[i], k)) { return i; };
                    i++;
                };
                return -1;
            };

            // Name of the object whose method list holds exactly m, or "?"
            def inh_source(Node* m) -> byte*
            {
                int i, j, c;
                Node* ob;
                while (i < this.pobjs.count)
                {
                    ob = (Node*)this.pobjs.vals[i];
                    i++;
                    if (ob == (Node*)0) { continue; };
                    c = node_count(ob, 1);
                    j = 0;
                    while (j < c)
                    {
                        if (node_child(ob, 1, j) == m) { return ob.text; };
                        j++;
                    };
                };
                return g"?\0";
            };

            def resolve_inheritance(Node* o) -> void
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
                    if (idx >= 0)
                    {
                        prev = (byte*)seen_o.items[idx];
                        if (!cstr_eq(prev, (byte*)po.items[i]))
                        {
                            this.error(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(g"Inheritance conflict: member '\0", m.text), g"' is defined in both '\0"), prev), g"' and '\0"), (byte*)po.items[i]), g"', inherited by '\0"), this.cat2(child, g"'\0")));
                        };
                    }
                    else
                    {
                        pv_push(seen_n, (void*)m.text);
                        pv_push(seen_o, po.items[i]);
                        pv_push(dedup, (void*)m);
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
                        if (cstr_eq(((Node*)own_m.items[j]).text, m.text))
                        {
                            this.error(this.cat2(this.cat2(this.cat2(this.cat2(g"Inheritance conflict: member '\0", m.text), g"' is defined in both a parent of '\0"), child), g"' itself\0"));
                            break;
                        };
                        j++;
                    };
                    i++;
                };
                // methods
                if (!this.failed)
                {
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
                        if (idx < 0)
                        {
                            pv_push(ukeys, (void*)k);
                            cand = pv_new();
                            pv_push(ucands, (void*)cand);
                            idx = ukeys.len - 1;
                        };
                        cand = (PtrVec*)ucands.items[idx];
                        dup = false;
                        j = 0;
                        while (j < cand.len)
                        {
                            if (this.inh_origin((Node*)cand.items[j]) == this.inh_origin(m)) { dup = true; };
                            j++;
                        };
                        if (!dup) { pv_push(cand, (void*)m); };
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
                        if (m.kind != NodeKind.FUNCTION_DEF) { continue; };
                        if ((m.flags `& NF_OVERRIDE) != 0 | this.method_has_body(m)) { pv_push(okeys, (void*)this.sig_key(m, false)); };
                    };
                    i = 0;
                    while (i < okeys.len & !this.failed)
                    {
                        idx = this.inh_key_has(ukeys, (byte*)okeys.items[i]);
                        i++;
                        if (idx < 0) { continue; };
                        cand = (PtrVec*)ucands.items[idx];
                        j = 0;
                        while (j < cand.len)
                        {
                            x = (Node*)cand.items[j];
                            if ((x.flags `& NF_NO_OVERRIDE) != 0)
                            {
                                this.error(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(g"Override error: method '\0", x.text), g"(\0"), this.sig_key(x, true)), g")' is marked no-override in a parent of '\0"), this.cat2(child, g"'\0")));
                                break;
                            };
                            j++;
                        };
                    };
                    i = 0;
                    while (i < ukeys.len & !this.failed)
                    {
                        idx = i;
                        i++;
                        if (this.inh_key_has(okeys, (byte*)ukeys.items[idx]) >= 0) { continue; };
                        cand = (PtrVec*)ucands.items[idx];
                        if (cand.len == 1)
                        {
                            pv_push(final_inh, cand.items[0]);
                            pv_push(fkeys, ukeys.items[idx]);
                        }
                        else
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
                if (!this.failed)
                {
                    // rebuild the member and method lists of o
                    if (o.l0 != (NodeVec*)0) { o.l0.len = 0; };
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
                    if (o.l1 != (NodeVec*)0) { o.l1.len = 0; };
                    i = 0;
                    while (i < own_f.len)
                    {
                        m = (Node*)own_f.items[i];
                        i++;
                        if (m.kind != NodeKind.FUNCTION_DEF)
                        {
                            node_push(o, 1, m);
                            continue;
                        };
                        if ((m.flags `& NF_OVERRIDE) != 0 | this.method_has_body(m) | this.inh_key_has(fkeys, this.sig_key(m, false)) < 0)
                        {
                            node_push(o, 1, m);
                        }
                        else { node_free(m); };
                    };
                    i = 0;
                    while (i < final_inh.len)
                    {
                        node_push(o, 1, this.inh_clone_of((Node*)final_inh.items[i]));
                        i++;
                    };
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
                return;
            };

            // True when `Type name = expr` is rewritten as the constructor call Type.__init(expr)
            def ctor_sugar(byte* raw, Node* rhs) -> bool
            {
                Node* ob;
                Node* ini;
                COp* c;
                int i;
                if (raw == (byte*)0) { return false; };
                if (!nm_has(this.oinit, raw)) { return false; };
                if (rhs.kind == NodeKind.FUNCTION_CALL & rhs.text != (byte*)0)
                {
                    while (i < this.cops.len)
                    {
                        c = (COp*)this.cops.items[i];
                        i++;
                        if (c.kind == 0)
                        {
                            if (cstr_eq(c.func, rhs.text)) { return false; };
                        };
                    };
                };
                ob = (Node*)nm_get(this.oinit, raw);
                ini = this.find_method(ob, g"__init\0");
                if (ini == (Node*)0) { return false; };
                return this.explicit_params(ini) == 1;
            };

            def object_def() -> Node*
            {
                return this.object_with_traits(this.mark(), (PtrVec*)0);
            };

            // IDENTIFIER+ 'object' ...   (the identifiers are trait names)
            def trait_prefixed_object() -> Node*
            {
                int m = this.mark();
                PtrVec* tn = pv_new();
                while (this.expect(TokenType.IDENTIFIER))
                {
                    pv_push(tn, (void*)this.cur_value());
                    this.advance();
                    if (this.expect(TokenType.OBJECT)) { break; };
                };
                Node* o = this.object_with_traits(m, tn);
                pv_free(tn);
                return o;
            };

            // trait_def -> 'trait' IDENTIFIER ('=' IDENTIFIER ('&' IDENTIFIER)* ';' | '{' (function_def)* '}' ';')
            def trait_def() -> Node*
            {
                Node* t = this.mk(NodeKind.TRAIT_DEF, this.cur_line(), this.cur_col());
                if (this.failed) { return t; };
                this.advance();
                t.text = this.ident();
                if (this.failed) { return this.done(t); };

                Node* base;
                Node* p;
                Node* x;
                byte* bname;
                int i, total;
                bool more;
                if (this.expect(TokenType.ASSIGN))
                {
                    // Composition: the prototypes of every named trait are copied in
                    this.advance();
                    more = true;
                    while (more & !this.failed)
                    {
                        bname = this.ident();
                        if (this.failed) { break; };
                        base = this.find_trait(bname);
                        if (base == (Node*)0)
                        {
                            this.error3(this.cat2(this.cat2(g"Trait composition error: '\0", bname), g"' must be defined before it can be composed into '\0"), t.text, g"'\0");
                            break;
                        };
                        i = 0;
                        total = 0;
                        if (base.l0 != (NodeVec*)0) { total = base.l0.len; };
                        while (i < total)
                        {
                            x = node_clone(base.l0.items[i]);
                            node_push(t, 0, x);
                            i++;
                        };
                        more = false;
                        if (this.expect(TokenType.LOGICAL_AND))
                        {
                            this.advance();
                            more = true;
                        };
                    };
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                    if (this.failed) { return this.done(t); };
                    pv_push(this.trait_defs, (void*)t);
                    return t;
                };

                if (!this.consume(TokenType.LEFT_BRACE)) { return this.done(t); };
                this.in_trait++;
                while (!this.failed & !this.expect(TokenType.RIGHT_BRACE))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.RIGHT_BRACE);
                        break;
                    };
                    if (this.expect3(TokenType.INLINE, TokenType.DEF, TokenType.CDECL) | this.is_calling_conv(this.cur()))
                    {
                        this.last_template = (byte*)0;
                        p = this.function_def();
                        if (this.failed) { break; };
                        if (p == (Node*)0)
                        {
                            if (this.last_template == (byte*)0)
                            {
                                this.error(g"Internal: template prototype registered no name\0");
                                break;
                            };
                            p = this.template_stub();
                            if (this.failed) { break; };
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
                    else
                    {
                        this.error3(g"Expected 'def' inside trait '\0", t.text, g"'\0");
                    };
                };
                this.in_trait--;
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (this.failed) { return this.done(t); };
                pv_push(this.trait_defs, (void*)t);
                return t;
            };

            // ===== CUSTOM OPERATORS =====

            // Source text of an operator symbol token, or null when the token cannot be part of one
            def tok_symbol(int t) -> byte*
            {
                switch (t)
                {
                    case (TokenType.PLUS)          { return g"+\0"; }
                    case (TokenType.MINUS)         { return g"-\0"; }
                    case (TokenType.MULTIPLY)      { return g"*\0"; }
                    case (TokenType.DIVIDE)        { return g"/\0"; }
                    case (TokenType.MODULO)        { return g"%\0"; }
                    case (TokenType.LESS_THAN)     { return g"<\0"; }
                    case (TokenType.GREATER_THAN)  { return g">\0"; }
                    case (TokenType.ASSIGN)        { return g"=\0"; }
                    case (TokenType.LOGICAL_OR)    { return g"|\0"; }
                    case (TokenType.LOGICAL_AND)   { return g"&\0"; }
                    case (TokenType.BITXOR_OP)     { return g"^\0"; }
                    case (TokenType.NOT)           { return g"!\0"; }
                    case (TokenType.QUESTION)      { return g"?\0"; }
                    case (TokenType.ADDRESS_OF)    { return g"@\0"; }
                    case (TokenType.TIE)           { return g"~\0"; }
                    case (TokenType.INCREMENT)     { return g"++\0"; }
                    case (TokenType.DECREMENT)     { return g"--\0"; }
                    case (TokenType.EQUAL)         { return g"==\0"; }
                    case (TokenType.NOT_EQUAL)     { return g"!=\0"; }
                    case (TokenType.LESS_EQUAL)    { return g"<=\0"; }
                    case (TokenType.GREATER_EQUAL) { return g">=\0"; }
                    case (TokenType.NAND_OP)       { return g"!&\0"; }
                    case (TokenType.NOR_OP)        { return g"!|\0"; }
                    case (TokenType.XOR_OP)        { return g"^|\0"; }
                    case (TokenType.BITSHIFT_LEFT) { return g"<<\0"; }
                    case (TokenType.BITSHIFT_RIGHT){ return g">>\0"; }
                    case (TokenType.BITNAND_OP)    { return g"`!&\0"; }
                    case (TokenType.BITNOR_OP)     { return g"`!|\0"; }
                    case (TokenType.BITXNAND)      { return g"`^|!&\0"; }
                    case (TokenType.BITXNOR)       { return g"`^|!|\0"; }
                    case (TokenType.LEFT_PAREN)    { return g"(\0"; }
                    case (TokenType.RIGHT_PAREN)   { return g")\0"; }
                    case (TokenType.LEFT_BRACE)    { return g"{\0"; }
                    case (TokenType.RIGHT_BRACE)   { return g"}\0"; }
                    case (TokenType.LEFT_BRACKET)  { return g"[\0"; }
                    case (TokenType.RIGHT_BRACKET) { return g"]\0"; }
                    case (TokenType.SEMICOLON)     { return g";\0"; }
                    case (TokenType.COLON)         { return g":\0"; }
                    case (TokenType.COMMA)         { return g",\0"; }
                    case (TokenType.DOT)           { return g".\0"; }
                    case (TokenType.RETURN_ARROW)  { return g"->\0"; }
                    case (TokenType.SCOPE)         { return g"::\0"; }
                    case (TokenType.BACKSLASH)     { return g"\\\0"; }
                    case (TokenType.STRINGIFY)     { return g"$\0"; }
                    case (TokenType.TAG)           { return g"#\0"; }
                    default                        { return (byte*)0; };
                };
                return (byte*)0;
            };

            // Mangled name of one symbol character, or null when it is written as hex
            def char_mangle(int c) -> byte*
            {
                if (c == '%') { return g"pct\0"; };
                if (c == '+') { return g"plus\0"; };
                if (c == '-') { return g"minus\0"; };
                if (c == '*') { return g"mul\0"; };
                if (c == '/') { return g"div\0"; };
                if (c == '<') { return g"lt\0"; };
                if (c == '>') { return g"gt\0"; };
                if (c == '=') { return g"eq\0"; };
                if (c == '&') { return g"amp\0"; };
                if (c == '|') { return g"pipe\0"; };
                if (c == '^') { return g"xor\0"; };
                if (c == '!') { return g"not\0"; };
                if (c == '?') { return g"qst\0"; };
                if (c == '@') { return g"at\0"; };
                if (c == '~') { return g"tilde\0"; };
                if (c == '\\') { return g"bslash\0"; };
                if (c == '$') { return g"dol\0"; };
                return (byte*)0;
            };

            // Value text of the token at offset off
            def val_at(int off) -> byte*
            {
                return this.lx.token_value(this.pos + off);
            };

            // True when the tokens at the cursor are exactly the symbol s
            def opsym_match(OpSym* s) -> bool
            {
                int i, t;
                while (i < s.n)
                {
                    t = this.type_at(i);
                    if (t != s.t[i]) { return false; };
                    if (t == TokenType.IDENTIFIER)
                    {
                        if (!cstr_eq(this.val_at(i), s.v[i])) { return false; };
                    };
                    i++;
                };
                return true;
            };

            def opsym_same(OpSym* a, OpSym* b) -> bool
            {
                if (a.n != b.n) { return false; };
                int i;
                while (i < a.n)
                {
                    if (a.t[i] != b.t[i]) { return false; };
                    if (a.t[i] == TokenType.IDENTIFIER)
                    {
                        if (!cstr_eq(a.v[i], b.v[i])) { return false; };
                    };
                    i++;
                };
                return true;
            };

            def opsym_free(OpSym* s) -> void
            {
                if (s == (OpSym*)0) { return; };
                if (s.t != (int*)0) { ffree((byte*)s.t); };
                if (s.v != (byte**)0) { ffree((byte*)s.v); };
                ffree((byte*)s);
                return;
            };

            // '[' symbol tokens ']'
            def op_bracket() -> OpSym*
            {
                OpSym* s = (OpSym*)fmalloc((u64)((sizeof(OpSym) + 7) / 8));
                if (s == (OpSym*)0)
                {
                    this.fail_alloc();
                    return s;
                };
                s.n = 0;
                s.t = (int*)0;
                s.v = (byte**)0;
                if (!this.consume(TokenType.LEFT_BRACKET)) { return s; };
                int m = this.mark();
                int cnt, i, tt;
                while (!this.expect(TokenType.RIGHT_BRACKET))
                {
                    if (this.expect(TokenType.EOF))
                    {
                        this.fail_expected(TokenType.RIGHT_BRACKET);
                        this.reset(m);
                        return s;
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
                    if (tt == TokenType.IDENTIFIER)
                    {
                        s.t[i] = tt;
                        s.v[i] = this.cur_value();
                    }
                    elif (this.tok_symbol(tt) != (byte*)0)
                    {
                        s.t[i] = tt;
                        s.v[i] = (byte*)0;
                    }
                    else
                    {
                        this.error3(g"Token '\0", this.cur_value(), g"' cannot be part of an operator symbol\0");
                        return s;
                    };
                    this.advance();
                    i++;
                    s.n = i;
                };
                this.consume(TokenType.RIGHT_BRACKET);
                return s;
            };

            // Symbol text, e.g. "$%"
            def opsym_text(OpSym* s) -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                int i;
                while (i < s.n)
                {
                    if (s.t[i] == TokenType.IDENTIFIER) { this.sb.put_str(s.v[i]); }
                    else { this.sb.put_str(this.tok_symbol(s.t[i])); };
                    i++;
                };
                return this.own_n(this.sb.mem, this.sb.len);
            };

            def put_hex_digit(int d) -> void
            {
                if (d < 10) { this.sb.put(48 + d); }
                else { this.sb.put(87 + d); };
                return;
            };

            // Appends the mangled form of s to sb
            def mangle_into(OpSym* s) -> void
            {
                int i, j, c;
                byte* sym;
                byte* nm;
                while (i < s.n)
                {
                    if (i > 0) { this.sb.put('_'); };
                    if (s.t[i] == TokenType.IDENTIFIER) { this.sb.put_str(s.v[i]); }
                    else
                    {
                        sym = this.tok_symbol(s.t[i]);
                        j = 0;
                        while (sym[j] != 0)
                        {
                            if (j > 0) { this.sb.put('_'); };
                            c = (int)sym[j];
                            nm = this.char_mangle(c);
                            if (nm != (byte*)0) { this.sb.put_str(nm); }
                            else
                            {
                                this.sb.put_str(g"0x\0");
                                if (c / 16 > 0) { this.put_hex_digit(c / 16); };
                                this.put_hex_digit(c % 16);
                            };
                            j++;
                        };
                    };
                    i++;
                };
                return;
            };

            // operator__<mangled>[__<mangled>]
            def op_func_name(OpSym* l, OpSym* r) -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                this.sb.put_str(g"operator__\0");
                this.mangle_into(l);
                if (r != (OpSym*)0)
                {
                    this.sb.put_str(g"__\0");
                    this.mangle_into(r);
                };
                return this.own_n(this.sb.mem, this.sb.len);
            };

            def kind_bit(int kind) -> int
            {
                int bit = 1;
                int k = kind;
                while (k > 0)
                {
                    bit = bit * 2;
                    k--;
                };
                return bit;
            };

            // Registers (or re-points) an operator. kind: 0 binary, 1 variadic, 2 prefix, 3 postfix,
            // 4 ternary, 5 circumfix. Takes ownership of left and right.
            def cop_register(int kind, OpSym* left, OpSym* right, byte* func) -> void
            {
                int i;
                COp* c;
                bool same;
                while (i < this.cops.len)
                {
                    c = (COp*)this.cops.items[i];
                    if (c.kind == kind & this.opsym_same(c.left, left))
                    {
                        same = true;
                        if (right != (OpSym*)0)
                        {
                            if (c.right == (OpSym*)0) { same = false; }
                            else { same = this.opsym_same(c.right, right); };
                        };
                        if (same)
                        {
                            c.func = func;
                            this.opsym_free(left);
                            this.opsym_free(right);
                            return;
                        };
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
                return;
            };

            // Longest left symbol of this kind matching at the cursor, or null
            def cop_best(int kind) -> COp*
            {
                if ((this.cop_mask `& this.kind_bit(kind)) == 0) { return (COp*)0; };
                COp* best = (COp*)0;
                COp* c;
                int i, bn;
                while (i < this.cops.len)
                {
                    c = (COp*)this.cops.items[i];
                    if (c.kind == kind)
                    {
                        if (c.left.n > bn)
                        {
                            if (this.opsym_match(c.left))
                            {
                                best = c;
                                bn = c.left.n;
                            };
                        };
                    };
                    i++;
                };
                return best;
            };

            // Longest right symbol among the operators sharing left's left symbol that matches at the cursor
            def cop_right(COp* left) -> COp*
            {
                COp* best = (COp*)0;
                COp* c;
                int i, bn;
                while (i < this.cops.len)
                {
                    c = (COp*)this.cops.items[i];
                    if (c.kind == left.kind & c.right != (OpSym*)0)
                    {
                        if (this.opsym_same(c.left, left.left))
                        {
                            if (c.right.n > bn)
                            {
                                if (this.opsym_match(c.right))
                                {
                                    best = c;
                                    bn = c.right.n;
                                };
                            };
                        };
                    };
                    i++;
                };
                return best;
            };

            // True when the cursor is at the right symbol of any ternary operator
            def cop_right_here() -> bool
            {
                if ((this.cop_mask `& this.kind_bit(4)) == 0) { return false; };
                COp* c;
                int i;
                while (i < this.cops.len)
                {
                    c = (COp*)this.cops.items[i];
                    if (c.kind == 4)
                    {
                        if (this.opsym_match(c.right)) { return true; };
                    };
                    i++;
                };
                return false;
            };

            // True when the cursor is at a custom binary, variadic or ternary operator
            def at_custom_op() -> bool
            {
                if (this.cop_mask == 0) { return false; };
                if (this.cop_best(0) != (COp*)0) { return true; };
                if (this.cop_best(1) != (COp*)0) { return true; };
                if (this.cop_best(4) != (COp*)0) { return true; };
                return this.cop_right_here();
            };

            // FUNCTION_CALL of func, positioned at line/col
            def op_call(byte* func, int line, int col) -> Node*
            {
                Node* c = this.mk(NodeKind.FUNCTION_CALL, line, col);
                if (this.failed) { return c; };
                c.text = func;
                return c;
            };

            def skip_tokens(int n) -> void
            {
                int i;
                while (i < n)
                {
                    this.advance();
                    i++;
                };
                return;
            };

            // custom_op_expression -> multiplicative ( variadic chain | ternary | binary )*
            def custom_op_expression() -> Node*
            {
                Node* expr = this.bin_level(9);
                if (this.failed) { return expr; };
                if (this.cop_mask == 0) { return expr; };
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
                    if (c != (COp*)0)
                    {
                        call = this.op_call(c.func, line, col);
                        if (this.failed) { return expr; };
                        cnt = this.lit(DataType.SINT, (i64)0, line, col);
                        if (this.failed) { node_free(call); return expr; };
                        node_push(call, 0, cnt);
                        node_push(call, 0, expr);
                        count = 0;
                        more = true;
                        while (more)
                        {
                            if (!this.opsym_match(c.left)) { break; };
                            this.skip_tokens(c.left.n);
                            count++;
                            if (!this.starts_operand()) { break; };
                            right = this.bin_level(9);
                            if (this.failed) { node_free(call); return (Node*)0; };
                            node_push(call, 0, right);
                        };
                        this.set_count_literal(cnt, count);
                        expr = call;
                        continue;
                    };
                    c = this.cop_best(4);
                    if (c != (COp*)0)
                    {
                        this.skip_tokens(c.left.n);
                        mid = this.bin_level(9);
                        if (this.failed) { node_free(expr); return mid; };
                        rc = this.cop_right(c);
                        if (rc == (COp*)0)
                        {
                            node_free(expr);
                            node_free(mid);
                            this.error3(g"Expected right operator of ternary '\0", this.opsym_text(c.left), g"'\0");
                            return (Node*)0;
                        };
                        this.skip_tokens(rc.right.n);
                        right = this.bin_level(9);
                        if (this.failed) { node_free(expr); node_free(mid); return right; };
                        call = this.op_call(rc.func, line, col);
                        if (this.failed) { node_free(expr); node_free(mid); node_free(right); return call; };
                        node_push(call, 0, expr);
                        node_push(call, 0, mid);
                        node_push(call, 0, right);
                        expr = call;
                        continue;
                    };
                    c = this.cop_best(0);
                    if (c == (COp*)0) { break; };
                    this.skip_tokens(c.left.n);
                    right = this.bin_level(9);
                    if (this.failed) { node_free(expr); return right; };
                    call = this.op_call(c.func, line, col);
                    if (this.failed) { node_free(expr); node_free(right); return call; };
                    node_push(call, 0, expr);
                    node_push(call, 0, right);
                    expr = call;
                };
                return expr;
            };

            def set_count_literal(Node* lit_node, int count) -> void
            {
                lit_node.ival = (i64)count;
                lit_node.op = DataType.SINT;
                return;
            };

            // Prefix and circumfix custom operators at the start of a unary expression, or null
            def custom_unary() -> Node*
            {
                if (this.cop_mask == 0) { return (Node*)0; };
                int line = this.cur_line();
                int col = this.cur_col();
                COp* c = this.cop_best(2);
                Node* call;
                Node* operand;
                COp* rc;
                if (c != (COp*)0)
                {
                    this.skip_tokens(c.left.n);
                    operand = this.unary_expression();
                    if (this.failed) { return operand; };
                    call = this.op_call(c.func, line, col);
                    if (this.failed) { node_free(operand); return call; };
                    node_push(call, 0, operand);
                    return call;
                };
                c = this.cop_best(5);
                if (c != (COp*)0)
                {
                    this.skip_tokens(c.left.n);
                    operand = this.unary_expression();
                    if (this.failed) { return operand; };
                    rc = this.cop_right(c);
                    if (rc == (COp*)0)
                    {
                        node_free(operand);
                        this.error3(g"Expected closing operator of circumfix '\0", this.opsym_text(c.left), g"'\0");
                        return (Node*)0;
                    };
                    this.skip_tokens(rc.right.n);
                    call = this.op_call(rc.func, line, col);
                    if (this.failed) { node_free(operand); return call; };
                    node_push(call, 0, operand);
                    return call;
                };
                return (Node*)0;
            };

            // True when s is the text of a built-in operator
            def is_builtin_op(byte* s) -> bool
            {
                int o = 0;
                while (o <= Operator.ADDRESS_CAST)
                {
                    if (cstr_eq(operator_text(o), s)) { return true; };
                    o++;
                };
                return false;
            };

            // Parameter types that make an overload of a built-in operator legal
            def has_non_builtin_param(Node* f) -> bool
            {
                int i;
                TypeSpec* t;
                while (i < this.param_count(f))
                {
                    t = f.l0.items[i].ts;
                    if (t != (TypeSpec*)0)
                    {
                        if (t.custom_typename != (byte*)0) { return true; };
                        if (t.base_type == DataType.STRUCT | t.base_type == DataType.OBJECT | t.base_type == DataType.DATA) { return true; };
                        if (t.pointer_depth > 0) { return true; };
                    };
                    i++;
                };
                return false;
            };

            def define_op_symbol(OpSym* s) -> void
            {
                if (this.st != (FXC_SYMTABLE*)0) { st_define(this.st, this.opsym_text(s), SymbolKind.OPERATOR, (TypeSpec*)0, (Node*)0); };
                return;
            };

            // '# binding {:this}' (postfix, returns 2) or '# binding {this:}' (prefix, returns 1); 0 when absent
            def unary_binding(Node* f, byte* what) -> int
            {
                if (!(this.expect(TokenType.TAG) & this.type_at(1) == TokenType.IDENTIFIER)) { return 0; };
                if (!cstr_eq(this.val_at(1), g"binding\0")) { return 0; };
                if (this.param_count(f) != 1)
                {
                    this.error3(g"# binding on \0", what, g" is only valid for unary operators (exactly one parameter)\0");
                    return 0;
                };
                this.advance();
                this.advance();
                if (!this.consume(TokenType.LEFT_BRACE)) { return 0; };
                int r = 0;
                if (this.expect(TokenType.COLON))
                {
                    this.advance();
                    this.consume(TokenType.THIS);
                    r = 2;
                }
                elif (this.expect(TokenType.THIS))
                {
                    this.advance();
                    this.consume(TokenType.COLON);
                    r = 1;
                }
                else
                {
                    this.error(g"Unary # binding must be {:this} for postfix or {this:} for prefix\0");
                    return 0;
                };
                this.consume(TokenType.RIGHT_BRACE);
                return r;
            };

            // Registers the operator named by the symbols after the definition parsed
            def register_operator(Node* f, OpSym* l, OpSym* r, int bind, bool variadic, bool is_template) -> void
            {
                int np = this.param_count(f);
                if (bind == 1) { this.cop_register(2, l, (OpSym*)0, f.text); this.define_op_symbol(l); return; };
                if (bind == 2) { this.cop_register(3, l, (OpSym*)0, f.text); this.define_op_symbol(l); return; };
                if (r != (OpSym*)0)
                {
                    if (np != 1 & np != 3)
                    {
                        this.error(g"Two-bracket 'as operator' requires either 1 parameter (circumfix) or 3 parameters (ternary)\0");
                        return;
                    };
                    if (np == 1) { this.cop_register(5, l, r, f.text); }
                    else { this.cop_register(4, l, r, f.text); };
                    this.define_op_symbol(r);
                    this.define_op_symbol(l);
                    return;
                };
                if (variadic)
                {
                    this.cop_register(1, l, (OpSym*)0, f.text);
                    this.define_op_symbol(l);
                    return;
                };
                if (this.is_builtin_op(this.opsym_text(l)))
                {
                    if (!is_template & !this.has_non_builtin_param(f))
                    {
                        this.error3(g"Overloading built-in operator '\0", this.opsym_text(l), g"' requires at least one parameter to be a non-builtin type\0");
                    };
                    this.define_op_symbol(l);
                    this.opsym_free(l);
                    return;
                };
                this.cop_register(0, l, (OpSym*)0, f.text);
                this.define_op_symbol(l);
                return;
            };

            // operator_def -> 'operator' '(' parameter_list ')' '[' symbol ']' ('[' symbol ']')? '->' type_spec
            //                 (':' contracts)? (';' | '->' expression ';' | block (':' contracts)? ('# binding {..}')? ';')
            def operator_def() -> Node*
            {
                NameMap* prev_act = this.active_tp;
                TemplateEntry* prev_cur = this.tmpl_cur;
                TemplateEntry* te;
                Node* f;
                this.tmpl_cur = (TemplateEntry*)0;
                f = this.operator_def_inner();
                te = this.tmpl_cur;
                this.tmpl_cur = prev_cur;
                if (this.active_tp != prev_act)
                {
                    nm_free(this.active_tp);
                    this.active_tp = prev_act;
                };
                if (te != (TemplateEntry*)0) { te_free(te); };
                return f;
            };

            // Registers the template operator and gives up ownership of f (the call returns null)
            def op_template_done(Node* f, TemplateEntry* te, byte* key) -> Node*
            {
                this.tmpl_cur = (TemplateEntry*)0;
                this.register_template(key, 3, te, f);
                return (Node*)0;
            };

            def operator_def_inner() -> Node*
            {
                Node* f = this.mk(NodeKind.FUNCTION_DEF, this.cur_line(), this.cur_col());
                TemplateEntry* te = (TemplateEntry*)0;
                byte* opkey = (byte*)0;
                if (this.failed) { return f; };
                this.advance();
                if (this.expect(TokenType.LESS_THAN) & this.is_template_list())
                {
                    te = te_new();
                    this.advance();
                    pv_push(te.params, (void*)this.own(ts_dup(this.ident())));
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        pv_push(te.params, (void*)this.own(ts_dup(this.ident())));
                    };
                    if (!this.failed) { this.consume(TokenType.GREATER_THAN); };
                    if (this.failed)
                    {
                        te_free(te);
                        return this.done(f);
                    };
                    this.tmpl_cur = te;
                };
                if (!this.consume(TokenType.LEFT_PAREN)) { return this.done(f); };
                if (te != (TemplateEntry*)0) { this.tp_activate(te); };
                this.parameter_list(f);
                if (this.failed) { return this.done(f); };
                if (!this.consume(TokenType.RIGHT_PAREN)) { return this.done(f); };

                OpSym* l = this.op_bracket();
                OpSym* r = (OpSym*)0;
                if (!this.failed & this.expect(TokenType.LEFT_BRACKET)) { r = this.op_bracket(); };
                if (this.failed) { return this.op_abort(f, l, r); };
                if (te != (TemplateEntry*)0) { opkey = this.opsym_text(l); };

                if (r != (OpSym*)0)
                {
                    if (this.param_count(f) != 1 & this.param_count(f) != 3)
                    {
                        this.error(g"Two-bracket operator requires either 1 parameter (circumfix) or 3 parameters (ternary)\0");
                        return this.op_abort(f, l, r);
                    };
                };
                f.text = this.op_func_name(l, r);

                if (!this.consume(TokenType.RETURN_ARROW)) { return this.op_abort(f, l, r); };
                f.ts = this.type_spec();
                if (this.failed) { return this.op_abort(f, l, r); };

                Node* pre;
                if (this.expect(TokenType.COLON))
                {
                    this.advance();
                    pre = this.mk(NodeKind.NODE_LIST, f.line, f.col);
                    if (this.failed) { return this.op_abort(f, l, r); };
                    this.contract_refs(f, pre, false);
                    if (this.failed) { node_free(pre); return this.op_abort(f, l, r); };
                };

                // Variadic operators get a hidden leading __op_count parameter
                bool variadic = false;
                int i;
                Node* p;
                while (i < this.param_count(f))
                {
                    if (f.l0.items[i].ival == 1) { variadic = true; };
                    i++;
                };
                this.strip_variadic(f);
                Node* cp;
                if (variadic & r == (OpSym*)0)
                {
                    cp = this.mk(NodeKind.PARAMETER, f.line, f.col);
                    if (this.failed) { node_free(pre); return this.op_abort(f, l, r); };
                    cp.ts = typespec_new();
                    cp.ts.base_type = DataType.SINT;
                    cp.text = g"__op_count\0";
                    this.push_front(f, cp);
                };

                OpSym* prev_vop = this.vop_sym;
                Node* ret;
                Node* b;
                Node* post;
                int bind;
                if (this.expect(TokenType.SEMICOLON))
                {
                    this.advance();
                    this.mark_proto(f);
                }
                elif (this.expect(TokenType.RETURN_ARROW))
                {
                    i = 0;
                    while (i < this.param_count(f))
                    {
                        if (f.l0.items[i].text == (byte*)0)
                        {
                            this.error(g"Operator definition requires parameter names, but a parameter has no name\0");
                            node_free(pre);
                            return this.op_abort(f, l, r);
                        };
                        i++;
                    };
                    if (this.st != (FXC_SYMTABLE*)0)
                    {
                        st_enter_scope(this.st);
                        i = 0;
                        while (i < this.param_count(f))
                        {
                            p = f.l0.items[i];
                            this.define_var(p.text, p.ts);
                            i++;
                        };
                    };
                    if (variadic & r == (OpSym*)0) { this.vop_sym = l; };
                    this.advance();
                    b = this.mk(NodeKind.BLOCK, this.cur_line(), this.cur_col());
                    ret = this.mk(NodeKind.RETURN_STATEMENT, this.cur_line(), this.cur_col());
                    if (this.failed) { node_free(b); node_free(ret); node_free(pre); return this.op_abort(f, l, r); };
                    f.a = b;
                    node_push(b, 0, ret);
                    ret.a = this.expression();
                    this.vop_sym = prev_vop;
                    if (this.st != (FXC_SYMTABLE*)0) { st_exit_scope(this.st); };
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                }
                else
                {
                    if (variadic & r == (OpSym*)0) { this.vop_sym = l; };
                    if (this.st != (FXC_SYMTABLE*)0) { st_enter_scope(this.st); };
                    f.a = this.block();
                    if (this.st != (FXC_SYMTABLE*)0) { st_exit_scope(this.st); };
                    this.vop_sym = prev_vop;
                    if (!this.failed)
                    {
                        this.prepend_contracts(f, pre);
                        post = (Node*)0;
                        if (this.expect(TokenType.COLON))
                        {
                            this.advance();
                            post = this.mk(NodeKind.NODE_LIST, f.line, f.col);
                            if (this.failed) { return this.op_abort(f, l, r); };
                            this.contract_refs(f, post, true);
                            if (!this.failed) { this.apply_post_contracts(f, post); };
                        };
                        if (!this.failed) { this.validate_bindings(this.fn_label(f), pre, post); };
                        node_free(post);
                        node_free(pre);
                        pre = (Node*)0;
                    };
                    if (!this.failed)
                    {
                        bind = this.unary_binding(f, g"an operator definition\0");
                        if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                        if (!this.failed)
                        {
                            this.register_operator(f, l, r, bind, variadic, te != (TemplateEntry*)0);
                            if (te != (TemplateEntry*)0) { return this.op_template_done(f, te, opkey); };
                            return f;
                        };
                    };
                    node_free(pre);
                    return this.op_abort(f, l, r);
                };
                node_free(pre);
                if (this.failed) { return this.op_abort(f, l, r); };
                if (variadic) { f.flags = f.flags `| NF_VARIADIC; };
                this.register_operator(f, l, r, 0, variadic, te != (TemplateEntry*)0);
                if (te != (TemplateEntry*)0) { return this.op_template_done(f, te, opkey); };
                return this.done(f);
            };

            def op_abort(Node* f, OpSym* l, OpSym* r) -> Node*
            {
                this.opsym_free(l);
                this.opsym_free(r);
                return this.done(f);
            };

            // Inserts p at the front of f's parameter list
            def push_front(Node* f, Node* p) -> void
            {
                node_push(f, 0, p);
                int i = f.l0.len - 1;
                while (i > 0)
                {
                    f.l0.items[i] = f.l0.items[i - 1];
                    i--;
                };
                f.l0.items[0] = p;
                return;
            };

            // ===== CONTRACTS =====

            // Latest CONTRACT_DEF with this name, or null
            def contract_find(byte* name) -> Node*
            {
                int i = this.contracts.len - 1;
                Node* c;
                while (i >= 0)
                {
                    c = (Node*)this.contracts.items[i];
                    if (cstr_eq(c.text, name)) { return c; };
                    i--;
                };
                return (Node*)0;
            };

            def contract_param(Node* c) -> void
            {
                Node* p = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                if (this.failed) { return; };
                node_push(c, 0, p);
                p.text = this.ident();
                return;
            };

            // ('(' IDENTIFIER (',' IDENTIFIER)* ')')?
            def contract_params(Node* c) -> void
            {
                if (!this.expect(TokenType.LEFT_PAREN)) { return; };
                this.advance();
                if (!this.expect(TokenType.RIGHT_PAREN))
                {
                    this.contract_param(c);
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        this.contract_param(c);
                    };
                };
                if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                return;
            };

            // contract_def -> 'contract' IDENTIFIER ('(' params ')')? (list of names ';' | block ('# binding {..}')? ';')
            // A name list is a forward declaration. Binding specs are skipped and reported.
            def contract_def() -> Node*
            {
                Node* c = this.mk(NodeKind.CONTRACT_DEF, this.cur_line(), this.cur_col());
                if (this.failed) { return c; };
                this.advance();
                c.text = this.ident();
                if (this.failed) { return this.done(c); };
                this.contract_params(c);
                if (this.failed) { return this.done(c); };

                Node* x;
                if (this.expect2(TokenType.SEMICOLON, TokenType.COMMA))
                {
                    c.a = this.mk(NodeKind.BLOCK, c.line, c.col);
                    if (this.failed) { return this.done(c); };
                    if (this.contract_find(c.text) == (Node*)0) { pv_push(this.contracts, (void*)c); };
                    while (this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        x = this.mk(NodeKind.CONTRACT_DEF, this.cur_line(), this.cur_col());
                        if (this.failed) { return this.done(c); };
                        nv_push(this.pending, x);
                        x.text = this.ident();
                        if (this.failed) { return this.done(c); };
                        this.contract_params(x);
                        if (this.failed) { return this.done(c); };
                        x.a = this.mk(NodeKind.BLOCK, x.line, x.col);
                        if (this.failed) { return this.done(c); };
                        if (this.contract_find(x.text) == (Node*)0) { pv_push(this.contracts, (void*)x); };
                    };
                    this.consume(TokenType.SEMICOLON);
                    return this.done(c);
                };

                c.a = this.block();
                if (this.failed) { return this.done(c); };
                if (this.expect(TokenType.TAG) & this.type_at(1) == TokenType.IDENTIFIER)
                {
                    if (cstr_eq(this.val_at(1), g"binding\0"))
                    {
                        this.advance();
                        this.advance();
                        if (this.consume(TokenType.LEFT_BRACE))
                        {
                            c.b = this.binding_spec();
                            if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                        };
                    };
                };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                if (this.failed) { return this.done(c); };
                pv_push(this.contracts, (void*)c);
                return c;
            };

            def num_text(int v) -> byte*
            {
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                this.sb.put_int(v);
                return this.own_n(this.sb.mem, this.sb.len);
            };

            // Replaces IDENTIFIER names found in from by the matching entry of to, everywhere below n
            def subst_walk(Node* n, PtrVec* from_names, PtrVec* to_names) -> void
            {
                if (n == (Node*)0) { return; };
                int i, s, cnt;
                if (n.kind == NodeKind.IDENTIFIER & n.text != (byte*)0)
                {
                    while (i < from_names.len)
                    {
                        if (cstr_eq((byte*)from_names.items[i], n.text))
                        {
                            n.text = (byte*)to_names.items[i];
                            break;
                        };
                        i++;
                    };
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
                return;
            };

            // contract_ref -> IDENTIFIER ('(' IDENTIFIER (',' IDENTIFIER)* ')')?
            // NODE_LIST: text = name, ival = 1 when an argument list was written, l0 = IDENTIFIER arguments
            def parse_contract_ref() -> Node*
            {
                Node* ref = this.mk(NodeKind.NODE_LIST, this.cur_line(), this.cur_col());
                if (this.failed) { return ref; };
                ref.text = this.ident();
                if (this.failed) { return this.done(ref); };
                if (this.expect(TokenType.LEFT_PAREN))
                {
                    this.advance();
                    ref.ival = 1;
                    if (!this.expect(TokenType.RIGHT_PAREN))
                    {
                        this.contract_param(ref);
                        while (!this.failed & this.expect(TokenType.COMMA))
                        {
                            this.advance();
                            this.contract_param(ref);
                        };
                    };
                    if (!this.failed) { this.consume(TokenType.RIGHT_PAREN); };
                };
                return this.done(ref);
            };

            // Appends substituted copies of the contract's statements to out.l0
            def resolve_contract(Node* f, Node* ref, Node* out) -> void
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
                    if (pn.ival != 1) { pv_push(real, (void*)pn.text); };
                    i++;
                };
                rn = real.len;
                i = 0;
                if (cp > 0)
                {
                    if (ref.ival == 1)
                    {
                        argc = node_count(ref, 0);
                        if (argc != cp)
                        {
                            this.error(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(g"Contract '\0", ref.text), g"' expects \0"), this.num_text(cp)), g" parameter(s) but \0"), this.num_text(argc)), g" argument(s) given at attachment site\0"));
                        }
                        elif (rn < argc)
                        {
                            this.error(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(g"Contract '\0", ref.text), g"' attachment maps \0"), this.num_text(argc)), g" parameter(s) but function only has \0"), this.num_text(rn)), g"\0"));
                        }
                        else
                        {
                            while (i < argc)
                            {
                                if (real.items[i] != (void*)0)
                                {
                                    pv_push(from_names, (void*)ref.l0.items[i].text);
                                    pv_push(to_names, real.items[i]);
                                };
                                i++;
                            };
                        };
                    }
                    elif (cp != rn)
                    {
                        this.error(this.cat2(this.cat2(this.cat2(this.cat2(this.cat2(g"Contract '\0", ref.text), g"' expects \0"), this.num_text(cp)), g" parameter(s) but function has \0"), this.num_text(rn)));
                    }
                    else
                    {
                        while (i < cp)
                        {
                            if (real.items[i] != (void*)0)
                            {
                                pv_push(from_names, (void*)c.l0.items[i].text);
                                pv_push(to_names, real.items[i]);
                            };
                            i++;
                        };
                    };
                };
                Node* s;
                Node* body = c.a;
                if (!this.failed & body != (Node*)0)
                {
                    i = 0;
                    while (i < node_count(body, 0))
                    {
                        s = node_clone(node_child(body, 0, i));
                        this.subst_walk(s, from_names, to_names);
                        node_push(out, 0, s);
                        i++;
                    };
                };
                pv_free(real);
                pv_free(from_names);
                pv_free(to_names);
                return;
            };

            // ':' contract_ref (',' contract_ref)*  statements go to out.l0
            def contract_refs(Node* f, Node* out, bool is_post) -> void
            {
                Node* ref;
                Node* nm;
                bool more = true;
                while (more & !this.failed)
                {
                    ref = this.parse_contract_ref();
                    if (this.failed) { return; };
                    if (this.contract_find(ref.text) == (Node*)0)
                    {
                        if (is_post) { this.error3(g"Undefined post-contract '\0", ref.text, g"'\0"); }
                        else { this.error3(g"Undefined contract '\0", ref.text, g"'\0"); };
                        node_free(ref);
                        return;
                    };
                    this.resolve_contract(f, ref, out);
                    nm = this.mk(NodeKind.IDENTIFIER, ref.line, ref.col);
                    if (!this.failed)
                    {
                        nm.text = ref.text;
                        nm.ival = -1;
                        if (ref.ival == 1) { nm.ival = (i64)node_count(ref, 0); };
                        node_push(out, 1, nm);
                    };
                    node_free(ref);
                    more = false;
                    if (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        more = true;
                    };
                };
                return;
            };

            // Moves pre.l0 in front of the statements of f's body; the caller frees pre
            def prepend_contracts(Node* f, Node* pre) -> void
            {
                if (pre == (Node*)0) { return; };
                if (node_count(pre, 0) > 0 & f.a != (Node*)0)
                {
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
                    if (f.a.l0 != (NodeVec*)0)
                    {
                        f.a.l0.len = 0;
                        nv_free(f.a.l0);
                    };
                    f.a.l0 = merged;
                };
                return;
            };

            // Copies of every post-contract statement into out
            def push_post_copies(NodeVec* out, Node* post) -> void
            {
                int i;
                while (i < node_count(post, 0))
                {
                    nv_push(out, node_clone(post.l0.items[i]));
                    i++;
                };
                return;
            };

            // Rewrites the statements of blk so post-contract code runs before each return
            def rewrite_returns(Node* blk, TypeSpec* rt, Node* post, bool void_mode) -> void
            {
                if (blk == (Node*)0) { return; };
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
                    if (s.kind == NodeKind.RETURN_STATEMENT)
                    {
                        if (!void_mode & s.a != (Node*)0)
                        {
                            decl = this.mk(NodeKind.VARIABLE_DECLARATION, s.line, s.col);
                            ret = this.mk(NodeKind.RETURN_STATEMENT, s.line, s.col);
                            id = this.mk(NodeKind.IDENTIFIER, s.line, s.col);
                            if (this.failed) { nv_push(out, s); continue; };
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
                        };
                        if (void_mode & s.a == (Node*)0)
                        {
                            this.push_post_copies(out, post);
                            nv_push(out, s);
                            continue;
                        };
                    };
                    if (s.kind == NodeKind.BLOCK) { this.rewrite_returns(s, rt, post, void_mode); }
                    elif (s.kind == NodeKind.IF_STATEMENT)
                    {
                        this.rewrite_returns(s.b, rt, post, void_mode);
                        this.rewrite_returns(s.c, rt, post, void_mode);
                        k = 0;
                        while (k < node_count(s, 1))
                        {
                            this.rewrite_returns(s.l1.items[k], rt, post, void_mode);
                            k++;
                        };
                    }
                    elif (s.kind == NodeKind.WHILE_LOOP | s.kind == NodeKind.DO_LOOP | s.kind == NodeKind.DO_WHILE_LOOP | s.kind == NodeKind.FOR_IN_LOOP)
                    {
                        this.rewrite_returns(s.b, rt, post, void_mode);
                    }
                    elif (s.kind == NodeKind.FOR_LOOP) { this.rewrite_returns(s.d, rt, post, void_mode); }
                    elif (s.kind == NodeKind.SWITCH_STATEMENT)
                    {
                        k = 0;
                        while (k < node_count(s, 0))
                        {
                            this.rewrite_returns(s.l0.items[k].b, rt, post, void_mode);
                            k++;
                        };
                    }
                    elif (s.kind == NodeKind.TRY_BLOCK)
                    {
                        this.rewrite_returns(s.a, rt, post, void_mode);
                        k = 0;
                        while (k < node_count(s, 0))
                        {
                            this.rewrite_returns(s.l0.items[k].a, rt, post, void_mode);
                            k++;
                        };
                    };
                    nv_push(out, s);
                };
                if (old != (NodeVec*)0)
                {
                    old.len = 0;
                    nv_free(old);
                };
                blk.l0 = out;
                return;
            };

            // Every return of f's body is rewritten as: r = value; post statements; return r;
            // (void functions run the post statements before each bare return and at the end)
            def apply_post_contracts(Node* f, Node* post) -> void
            {
                if (f.a == (Node*)0 | node_count(post, 0) == 0) { return; };
                bool void_mode = f.ts != (TypeSpec*)0 & f.ts.base_type == DataType.VOID;
                this.rewrite_returns(f.a, f.ts, post, void_mode);
                if (void_mode)
                {
                    if (f.a.l0 == (NodeVec*)0) { f.a.l0 = nv_new(); };
                    this.push_post_copies(f.a.l0, post);
                };
                return;
            };

            // ===== COMPTIME =====

            // comptime_block -> 'comptime' IDENTIFIER? '{' statement* '}' ';'
            def comptime_block() -> Node*
            {
                Node* n = this.mk(NodeKind.COMPTIME_BLOCK, this.cur_line(), this.cur_col());
                if (this.failed) { return n; };
                this.advance();
                if (this.expect(TokenType.IDENTIFIER))
                {
                    n.text = this.cur_value();
                    this.advance();
                };
                if (!this.consume(TokenType.LEFT_BRACE)) { return this.done(n); };
                this.in_comptime++;
                this.statements_until_brace(n);
                this.in_comptime--;
                if (!this.failed) { this.consume(TokenType.RIGHT_BRACE); };
                if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                return this.done(n);
            };

            // ===== STRING INTERPOLATION =====

            // Parses text as an expression with a lexer of its own. The lexer outlives the tree
            // because nodes borrow token text from it, so it is kept in sublex and freed on exit.
            def sub_expr(byte* text, int n) -> Node*
            {
                byte* src = this.own_n(text, n);
                Lexer* sl = (Lexer*)fmalloc((u64)((sizeof(Lexer) + 7) / 8));
                if (sl == (Lexer*)0)
                {
                    this.fail_alloc();
                    return (Node*)0;
                };
                sl.__init(src, n);
                pv_push(this.sublex, (void*)sl);
                if (!sl.tokenize())
                {
                    this.error(g"Invalid expression in string interpolation\0");
                    return (Node*)0;
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
                return e;
            };

            // Pushes the text gathered in sb as a STRING_LITERAL part of holder and clears sb
            def flush_text(Node* holder, int line, int col) -> void
            {
                if (this.sb.len == 0) { return; };
                Node* t = this.mk(NodeKind.STRING_LITERAL, line, col);
                if (this.failed) { return; };
                t.text = this.own_n(this.sb.mem, this.sb.len);
                t.op = -1;
                node_push(holder, 0, t);
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                return;
            };

            def is_space(int c) -> bool
            {
                return c == 32 | c == 9 | c == 10 | c == 13;
            };

            // f"..." token: parts are text and {expression}; {{ and }} are literal braces
            def f_string_node() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.F_STRING_LITERAL, line, col);
                if (this.failed) { return n; };
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
                    if (v[i] == '{' & i + 1 < end & v[i + 1] == '{')
                    {
                        this.sb.put('{');
                        i += 2;
                    }
                    elif (v[i] == '}' & i + 1 < end & v[i + 1] == '}')
                    {
                        this.sb.put('}');
                        i += 2;
                    }
                    elif (v[i] == '{')
                    {
                        j = i + 1;
                        while (j < end & v[j] != '}') { j++; };
                        if (j >= end)
                        {
                            this.error(g"Unclosed expression in f-string\0");
                            return this.done(n);
                        };
                        this.flush_text(n, line, col);
                        e = this.sub_expr(v + i + 1, j - i - 1);
                        if (this.failed) { return this.done(n); };
                        node_push(n, 0, e);
                        i = j + 1;
                    }
                    else
                    {
                        this.sb.put((int)v[i]);
                        i++;
                    };
                };
                this.flush_text(n, line, col);
                return this.done(n);
            };

            // i"template":{expr; expr} token: each {} in the template takes the next expression
            def i_string_node() -> Node*
            {
                int line = this.cur_line();
                int col = this.cur_col();
                Node* n = this.mk(NodeKind.F_STRING_LITERAL, line, col);
                if (this.failed) { return n; };
                byte* v = this.cur_value();
                int len = this.cur_value_len();
                this.advance();
                int i = 2;
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                bool closed = false;
                while (i < len & !closed)
                {
                    if (v[i] == '\\' & i + 1 < len)
                    {
                        this.sb.put((int)v[i]);
                        this.sb.put((int)v[i + 1]);
                        i += 2;
                    }
                    elif (v[i] == '"')
                    {
                        i++;
                        closed = true;
                    }
                    else
                    {
                        this.sb.put((int)v[i]);
                        i++;
                    };
                };
                byte* tpl = this.own_n(this.sb.mem, this.sb.len);
                int tlen = this.sb.len;
                while (i < len & this.is_space((int)v[i])) { i++; };
                if (i < len & v[i] == ':')
                {
                    i++;
                    while (i < len & this.is_space((int)v[i])) { i++; };
                };
                PtrVec* exprs = pv_new();
                int a, b;
                Node* e;
                if (i < len & v[i] == '{' & v[len - 1] == '}')
                {
                    i++;
                    len = len - 1;
                    while (i <= len & !this.failed)
                    {
                        a = i;
                        while (a < len & v[a] != ';') { a++; };
                        b = a;
                        while (i < b & this.is_space((int)v[i])) { i++; };
                        while (b > i & this.is_space((int)v[b - 1])) { b--; };
                        if (b > i)
                        {
                            e = this.sub_expr(v + i, b - i);
                            if (!this.failed) { pv_push(exprs, (void*)e); };
                        };
                        i = a + 1;
                    };
                };
                if (this.failed)
                {
                    pv_free(exprs);
                    return this.done(n);
                };
                int k, used;
                this.sb.len = 0;
                this.sb.mem[0] = (byte)0;
                while (k < tlen)
                {
                    if (tpl[k] == '{' & k + 1 < tlen & tpl[k + 1] == '}')
                    {
                        if (used < exprs.len)
                        {
                            this.flush_text(n, line, col);
                            node_push(n, 0, (Node*)exprs.items[used]);
                            used++;
                        };
                        k += 2;
                    }
                    else
                    {
                        this.sb.put((int)tpl[k]);
                        k++;
                    };
                };
                this.flush_text(n, line, col);
                while (used < exprs.len)
                {
                    node_free((Node*)exprs.items[used]);
                    used++;
                };
                pv_free(exprs);
                return this.done(n);
            };

            // ===== CONTRACT BINDINGS =====
            // Binding node: l0 = pre names (IDENTIFIER text, "!" for none), l1 = post refs
            // (IDENTIFIER text = name, ival = arity or -1, op = 1 when negated), ival = chain operator or 0.

            def binding_name() -> byte*
            {
                if (this.expect(TokenType.THIS))
                {
                    this.advance();
                    return g"this\0";
                };
                return this.ident();
            };

            def binding_pre(Node* b) -> void
            {
                Node* x = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                if (this.failed) { return; };
                node_push(b, 0, x);
                x.text = this.binding_name();
                return;
            };

            // '!'? name ('(' INT ')')?
            def binding_ref(Node* b) -> void
            {
                bool ok;
                Node* x = this.mk(NodeKind.IDENTIFIER, this.cur_line(), this.cur_col());
                if (this.failed) { return; };
                node_push(b, 1, x);
                x.ival = -1;
                if (this.expect(TokenType.NOT))
                {
                    this.advance();
                    x.op = 1;
                };
                x.text = this.binding_name();
                if (this.failed) { return; };
                if (this.expect(TokenType.LEFT_PAREN))
                {
                    this.advance();
                    if (!this.expect(TokenType.SINT_LITERAL))
                    {
                        this.fail_expected(TokenType.SINT_LITERAL);
                        return;
                    };
                    x.ival = this.parse_int(this.cur_value(), @ok);
                    this.advance();
                    this.consume(TokenType.RIGHT_PAREN);
                };
                return;
            };

            // pre_side ':' post_side
            def binding_spec() -> Node*
            {
                Node* b = this.mk(NodeKind.NODE_LIST, this.cur_line(), this.cur_col());
                if (this.failed) { return b; };
                Node* x;
                int cur_op;
                if (this.expect(TokenType.NOT))
                {
                    this.advance();
                    x = this.mk(NodeKind.IDENTIFIER, b.line, b.col);
                    if (this.failed) { return this.done(b); };
                    x.text = g"!\0";
                    node_push(b, 0, x);
                }
                else
                {
                    this.binding_pre(b);
                    while (!this.failed & this.expect(TokenType.COMMA))
                    {
                        this.advance();
                        this.binding_pre(b);
                    };
                };
                if (this.failed) { return this.done(b); };
                if (!this.consume(TokenType.COLON)) { return this.done(b); };

                if (this.expect(TokenType.NOT) & this.type_at(1) == TokenType.RIGHT_BRACE)
                {
                    this.advance();
                    x = this.mk(NodeKind.IDENTIFIER, b.line, b.col);
                    if (this.failed) { return this.done(b); };
                    x.text = g"!\0";
                    x.ival = -1;
                    node_push(b, 1, x);
                    return b;
                };
                this.binding_ref(b);
                while (!this.failed & this.expect3(TokenType.COMMA, TokenType.LOGICAL_OR, TokenType.LOGICAL_AND))
                {
                    if (this.expect(TokenType.COMMA)) { cur_op = ','; }
                    elif (this.expect(TokenType.LOGICAL_OR)) { cur_op = '|'; }
                    else { cur_op = '&'; };
                    if (b.ival == 0) { b.ival = (i64)cur_op; }
                    elif (b.ival != (i64)cur_op)
                    {
                        this.error(g"Mixed operators in # binding post-side are not allowed; use the same operator throughout\0");
                        return this.done(b);
                    };
                    this.advance();
                    this.binding_ref(b);
                };
                return this.done(b);
            };

            // Index of the first entry of list (IDENTIFIER nodes in slot s of holder) named name
            // whose arity matches (arity -1 matches any), or -1
            def ref_index(Node* holder, int s, byte* name, int arity) -> int
            {
                if (holder == (Node*)0) { return -1; };
                int i;
                Node* x;
                while (i < node_count(holder, s))
                {
                    x = node_child(holder, s, i);
                    if (cstr_eq(x.text, name))
                    {
                        if (arity == -1 | (i64)arity == x.ival) { return i; };
                    };
                    i++;
                };
                return -1;
            };

            // Python list repr of the names in slot 1 of holder, e.g. ['A', 'B']
            def names_repr(Node* holder) -> byte*
            {
                byte* r = g"[\0";
                int i;
                while (i < node_count(holder, 1))
                {
                    if (i > 0) { r = this.cat2(r, g", \0"); };
                    r = this.cat2(this.cat2(this.cat2(r, g"'\0"), node_child(holder, 1, i).text), g"'\0");
                    i++;
                };
                return this.cat2(r, g"]\0");
            };

            // "Contract 'C' binding <mid> on function 'F'<tail>"
            def bind_err(byte* cname, byte* mid, byte* fname, byte* tail) -> void
            {
                byte* m = this.cat2(g"Contract '\0", cname);
                m = this.cat2(m, g"' binding \0");
                m = this.cat2(m, mid);
                m = this.cat2(m, g" on function '\0");
                m = this.cat2(m, fname);
                m = this.cat2(m, g"'\0");
                this.error(this.cat2(m, tail));
                return;
            };

            def quoted(byte* a, byte* b, byte* c) -> byte*
            {
                return this.cat2(this.cat2(a, b), c);
            };

            // Checks every # binding of the contracts attached to a function. pre and post hold the
            // attached contract names in slot 1 (either may be null).
            def validate_bindings(byte* fname, Node* pre, Node* post) -> void
            {
                int npre, npost;
                if (pre != (Node*)0) { npre = node_count(pre, 1); };
                if (post != (Node*)0) { npost = node_count(post, 1); };
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
                    if (ci < npre) { cname = node_child(pre, 1, ci).text; }
                    else { cname = node_child(post, 1, ci - npre).text; };
                    ci++;
                    // Only the first occurrence of each name is checked
                    k = 0;
                    found = 0;
                    while (k < ci - 1)
                    {
                        if (k < npre) { rn = node_child(pre, 1, k).text; }
                        else { rn = node_child(post, 1, k - npre).text; };
                        if (cstr_eq(rn, cname)) { found = 1; };
                        k++;
                    };
                    if (found == 1) { continue; };
                    ct = this.contract_find(cname);
                    if (ct == (Node*)0) { continue; };
                    bd = ct.b;
                    if (bd == (Node*)0) { continue; };
                    is_pre = this.ref_index(pre, 1, cname, -1) >= 0;
                    is_post = this.ref_index(post, 1, cname, -1) >= 0;

                    // pre side
                    if (cstr_eq(node_child(bd, 0, 0).text, g"!\0"))
                    {
                        if (npre > 0)
                        {
                            this.bind_err(cname, g"declares no pre-contract is allowed\0", fname, this.cat2(g", but pre-contracts are present: \0", this.names_repr(pre)));
                            return;
                        };
                    }
                    else
                    {
                        i = 0;
                        while (i < node_count(bd, 0) & !this.failed)
                        {
                            rn = node_child(bd, 0, i).text;
                            i++;
                            if (cstr_eq(rn, g"this\0"))
                            {
                                if (!is_pre) { this.bind_err(cname, g"requires itself as a pre-contract\0", fname, g", but it is only used as a post-contract\0"); };
                            }
                            elif (this.ref_index(pre, 1, rn, -1) < 0)
                            {
                                if (this.ref_index(post, 1, rn, -1) >= 0)
                                {
                                    this.bind_err(cname, this.quoted(g"requires '\0", rn, g"' as a pre-contract\0"), fname, g", but it is inverted (used as a post-contract instead)\0");
                                }
                                else
                                {
                                    this.bind_err(cname, this.quoted(g"requires pre-contract '\0", rn, g"'\0"), fname, g", but it is not present\0");
                                };
                            };
                        };
                        if (this.failed) { return; };
                    };

                    // post side
                    if (node_count(bd, 1) == 0) { continue; };
                    if (cstr_eq(node_child(bd, 1, 0).text, g"!\0"))
                    {
                        if (npost > 0)
                        {
                            this.bind_err(cname, g"declares no post-contract is allowed\0", fname, this.cat2(g", but post-contracts are present: \0", this.names_repr(post)));
                            return;
                        };
                        continue;
                    };
                    op = (int)bd.ival;

                    if (op == '&')
                    {
                        i = 0;
                        while (i < node_count(bd, 1) & !this.failed)
                        {
                            x = node_child(bd, 1, i);
                            i++;
                            rn = x.text;
                            if (cstr_eq(rn, g"this\0")) { rn = cname; };
                            matched = this.ref_index(post, 1, rn, (int)x.ival) >= 0;
                            neg = x.op == 1;
                            if (!neg & !matched)
                            {
                                if (this.ref_index(pre, 1, rn, (int)x.ival) >= 0)
                                {
                                    this.bind_err(cname, this.quoted(g"requires '\0", rn, g"' as a post-contract\0"), fname, g", but it is inverted (used as a pre-contract instead)\0");
                                }
                                else
                                {
                                    this.bind_err(cname, this.quoted(g"requires post-contract '\0", rn, g"'\0"), fname, g"\0");
                                };
                            }
                            elif (neg & matched)
                            {
                                this.bind_err(cname, this.quoted(g"forbids post-contract '\0", rn, g"'\0"), fname, g"\0");
                            };
                        };
                        if (this.failed) { return; };
                        continue;
                    };

                    // ',' and '|' chains: forbidden first, then the required ones in order
                    i = 0;
                    while (i < node_count(bd, 1) & !this.failed)
                    {
                        x = node_child(bd, 1, i);
                        i++;
                        if (x.op == 1)
                        {
                            rn = x.text;
                            if (cstr_eq(rn, g"this\0")) { rn = cname; };
                            if (this.ref_index(post, 1, rn, (int)x.ival) >= 0)
                            {
                                this.bind_err(cname, this.quoted(g"forbids post-contract '\0", rn, g"'\0"), fname, g"\0");
                            };
                        };
                    };
                    if (this.failed) { return; };
                    last = -1;
                    i = 0;
                    while (i < node_count(bd, 1) & !this.failed)
                    {
                        x = node_child(bd, 1, i);
                        i++;
                        if (x.op == 1) { continue; };
                        rn = x.text;
                        if (cstr_eq(rn, g"this\0")) { rn = cname; };
                        j = this.ref_index(post, 1, rn, (int)x.ival);
                        if (j < 0)
                        {
                            if (op == '|') { continue; };
                            if (this.ref_index(pre, 1, rn, (int)x.ival) >= 0)
                            {
                                this.bind_err(cname, this.quoted(g"requires '\0", rn, g"' as a post-contract\0"), fname, g", but it is inverted (used as a pre-contract instead)\0");
                            }
                            else
                            {
                                this.bind_err(cname, this.quoted(g"requires post-contract '\0", rn, g"'\0"), fname, g"\0");
                            };
                            continue;
                        };
                        if (j <= last)
                        {
                            this.bind_err(cname, this.cat2(g"requires post-contracts \0", this.required_repr(bd, cname)), fname, g" in that order\0");
                            continue;
                        };
                        last = j;
                    };
                };
                return;
            };

            // Python list repr of the non-negated names of a binding's post side, 'this' resolved
            def required_repr(Node* bd, byte* cname) -> byte*
            {
                byte* r = g"[\0";
                int i, n;
                Node* x;
                byte* nm;
                while (i < node_count(bd, 1))
                {
                    x = node_child(bd, 1, i);
                    i++;
                    if (x.op == 1) { continue; };
                    nm = x.text;
                    if (cstr_eq(nm, g"this\0")) { nm = cname; };
                    if (n > 0) { r = this.cat2(r, g", \0"); };
                    r = this.cat2(this.cat2(this.cat2(r, g"'\0"), nm), g"'\0");
                    n++;
                };
                return this.cat2(r, g"]\0");
            };


            // ===== STATEMENT DISPATCH =====

            // statement -> declaration | definition | control statement | expression statement.
            // Returns null for empty statements.
            def statement() -> Node*
            {
                int sc = -1;
                int m, c;
                bool is_asm, is_func, is_volatile;

                c = this.cur();
                if (c == TokenType.GLOBAL)
                {
                    sc = StorageClass.GLOBAL;
                    this.advance();
                }
                elif (c == TokenType.LOCAL)
                {
                    sc = StorageClass.LOCAL;
                    this.advance();
                }
                elif (c == TokenType.HEAP)
                {
                    sc = StorageClass.HEAP;
                    this.advance();
                }
                elif (c == TokenType.STACK)
                {
                    sc = StorageClass.STACK;
                    this.advance();
                }
                elif (c == TokenType.REGISTER)
                {
                    sc = StorageClass.REGISTER;
                    this.advance();
                }
                elif (c == TokenType.SINGINIT)
                {
                    sc = StorageClass.SINGINIT;
                    this.advance();
                };

                if (sc >= 0 | this.expect2(TokenType.CONST, TokenType.VOLATILE))
                {
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

                    if (is_asm)
                    {
                        is_volatile = false;
                        if (this.expect(TokenType.VOLATILE))
                        {
                            is_volatile = true;
                            this.advance();
                        };
                        return this.asm_statement(is_volatile);
                    }
                    elif (is_func)
                    {
                        return this.function_def();
                    }
                    else
                    {
                        if (sc >= 0) { this.pos--; };
                        return this.variable_declaration_statement();
                    };
                };

                c = this.cur();
                if (c == TokenType.MACRO) { return this.macro_def(); }
                elif (c == TokenType.USING) { return this.using_statement(); }
                elif (c == TokenType.NOT)
                {
                    this.advance();
                    if (this.expect(TokenType.USING))
                    {
                        this.advance();
                        return this.not_using_statement();
                    };
                }
                elif (c == TokenType.OPERATOR) { return this.operator_def(); }
                elif (c == TokenType.EXTERN) { return this.extern_statement(); }
                elif (c == TokenType.EXPORT) { return this.export_statement(); }
                elif (c == TokenType.CONTRACT) { return this.contract_def(); }
                elif (c == TokenType.CONSTRAINT) { return this.constra_def(); }
                elif (c == TokenType.EFFECT) { return this.effect_def(); }
                elif (c == TokenType.INLINE) { return this.function_def(); }
                elif (c == TokenType.DEF) { return this.function_def(); }
                elif (c == TokenType.NO_MANGLE) { return this.function_def(); }
                elif (this.is_calling_conv(c)) { return this.function_def(); }
                elif (this.is_bare_function_def()) { return this.function_def(); }
                elif (c == TokenType.ENUM) { return this.enum_def(); }
                elif (this.type_at(1) == TokenType.ENUM) { return this.enum_def(); }
                elif (c == TokenType.UNION) { return this.union_def(); }
                elif (c == TokenType.STRUCT)
                {
                    if (this.type_at(1) == TokenType.MULTIPLY)
                    {
                        return this.variable_declaration_statement();
                    };
                    return this.struct_def();
                }
                elif (c == TokenType.OBJECT)
                {
                    if (this.type_at(1) == TokenType.MULTIPLY)
                    {
                        return this.variable_declaration_statement();
                    };
                    return this.object_def();
                }
                elif (c == TokenType.TRAIT) { return this.trait_def(); }
                elif (c == TokenType.INTERFACE) { return this.interface_def(); }
                elif (this.is_trait_prefixed_object()) { return this.trait_prefixed_object(); }
                elif (c == TokenType.NAMESPACE) { return this.namespace_def(); }
                elif (c == TokenType.IF) { return this.if_statement(); }
                elif (c == TokenType.DO) { return this.do_while_statement(); }
                elif (c == TokenType.WHILE) { return this.while_statement(); }
                elif (c == TokenType.FOR) { return this.for_statement(); }
                elif (c == TokenType.SWITCH) { return this.switch_statement(); }
                elif (c == TokenType.TRY) { return this.try_statement(); }
                elif (c == TokenType.RETURN) { return this.return_statement(); }
                elif (c == TokenType.RETURN_ARROW) { return this.return_arrow_ret(); }
                elif (c == TokenType.BREAK) { return this.break_statement(); }
                elif (c == TokenType.CONTINUE) { return this.continue_statement(); }
                elif (c == TokenType.LABEL) { return this.label_statement(); }
                elif (c == TokenType.GOTO) { return this.goto_statement(); }
                elif (c == TokenType.JUMP) { return this.jump_statement(); }
                elif (c == TokenType.THROW) { return this.throw_statement(); }
                elif (c == TokenType.ASSERT) { return this.assert_statement(); }
                elif (c == TokenType.DEFER) { return this.defer_statement(); }
                elif (c == TokenType.ESCAPE_KW) { return this.escape_statement(); }
                elif (c == TokenType.DEPRECATE) { return this.deprecate_statement(); }
                elif (c == TokenType.NORET) { return this.noreturn_statement(); }
                elif (c == TokenType.LEFT_BRACE) { return this.block_statement(); }
                elif (this.is_type_func_def()) { return this.type_func_def(); }
                elif (this.is_dual_assign_declaration()) { return this.dual_assign_declaration(); }
                elif (this.is_variable_declaration()) { return this.variable_declaration_statement(); }
                elif (c == TokenType.UNSIGNED) { return this.variable_declaration_statement(); }
                elif (c == TokenType.SIGNED) { return this.variable_declaration_statement(); }
                elif (this.expect4(TokenType.SINT, TokenType.UINT, TokenType.DATA, TokenType.CHAR)
                    | this.expect4(TokenType.BYTE, TokenType.FLOAT_KW, TokenType.DOUBLE_KW, TokenType.BOOL_KW)
                    | this.expect4(TokenType.VOID, TokenType.SLONG, TokenType.ULONG, TokenType.DICT))
                {
                    return this.variable_declaration_statement();
                }
                elif (c == TokenType.DITTO) { return this.ditto_statement(); }
                elif (c == TokenType.SEMICOLON)
                {
                    this.advance();
                    return (Node*)0;
                }
                elif (c == TokenType.AUTO & this.type_at(1) == TokenType.LEFT_BRACE)
                {
                    Node* dn = this.destructuring_assignment();
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                    return dn;
                }
                elif (c == TokenType.AUTO & this.type_at(1) == TokenType.IDENTIFIER)
                {
                    Node* av = this.auto_variable_declaration();
                    if (!this.failed) { this.consume(TokenType.SEMICOLON); };
                    return av;
                }
                elif (c == TokenType.CODIFY) { return this.codify_statement(); }
                elif (c == TokenType.COMPTIME) { return this.comptime_block(); }
                elif (c == TokenType.EMITFLUX)
                {
                    if (this.in_comptime == 0)
                    {
                        this.error(g"'emitflux' is only valid inside a 'comptime' block\0");
                        return (Node*)0;
                    };
                    return this.emitflux_statement();
                }
                elif (c == TokenType.ASM) { return this.asm_statement(false); }
                elif (c == TokenType.FLUXVM)
                {
                    if (this.in_comptime == 0)
                    {
                        this.error(g"'fluxvm' is only valid inside a 'comptime' block\0");
                        return (Node*)0;
                    };
                    return this.fluxvm_statement();
                }
                elif (c == TokenType.IDENTIFIER & this.val_is(g"error\0", 5) & this.type_at(1) >= 0 & this.type_at(1) != TokenType.ASSIGN)
                {
                    return this.error_return_statement();
                }
                else
                {
                    return this.expression_statement();
                };

                return (Node*)0;
            };

            // ===== DRIVER =====

            // program -> statement* EOF. Returns a PROGRAM node (l0 = statements).
            def parse() -> Node*
            {
                Node* prog = node_new(NodeKind.PROGRAM, 1, 1);
                Node* stmt;
                int k;
                if (prog == (Node*)0)
                {
                    this.failed = true;
                    this.err_kind = ParseErr.ALLOC;
                    return prog;
                };
                if (this.failed) { return prog; };

                this.toks = this.lx.tokens;
                this.count = this.lx.count;
                this.pos = 0;
                if (this.count == 0)
                {
                    this.error(g"no tokens to parse\0");
                    return prog;
                };

                while (!this.expect(TokenType.EOF))
                {
                    stmt = this.statement();
                    if (this.failed) { break; };
                    if (stmt != (Node*)0)
                    {
                        node_push(prog, 0, stmt);
                        this.last_stmt = stmt;
                    };
                    k = 0;
                    while (k < this.pending.len)
                    {
                        node_push(prog, 0, this.pending.items[k]);
                        k++;
                    };
                    if (this.pending.len > 0) { this.last_stmt = this.pending.items[this.pending.len - 1]; };
                    this.pending.len = 0;
                };
                if (this.failed) { return prog; };
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
                return prog;
            };
        };
    };
};

#endif;
