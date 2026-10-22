// Author: Karac V. Thweatt
//
// fast.fx - Flux AST library (port of fast.py)
//
// Every AST class of fast.py is a NodeKind. All nodes share one struct, Node,
// so a node of any kind can be stored in any child slot or list. The meaning
// of the generic slots per kind is documented next to each NodeKind below.
//
// Slots:
//     kind, line, col      node kind and source position
//     op                   Operator, DataType, StorageClass, TokenType or ProtocolKind
//     flags                NF_* bit flags
//     ival, fval           integer and floating point value
//     text, text2, text3   strings (borrowed, never freed by node_free)
//     a, b, c, d, e        child nodes
//     l0 .. l5             child lists (NodeVec*), created on first use
//     ts, ts2              type specs (TypeSpec*)
//
// Unused slots are null. node_free releases a node, its lists and type
// specs and every child recursively. Strings are borrowed from the lexer.
//
// Usage:
//     Node* n = node_new(NodeKind.IDENTIFIER, line, col);
//     n.text = name;
//     node_push(n, 0, child);        // append to list l0
//     Node* c = node_child(n, 0, i); // i-th element of l0

#ifndef FLUX_STANDARD
#import <standard.fx>;
#endif;

#ifndef FLUX_AST
#def FLUX_AST 1;

#def NF_POSTFIX 1;
#def NF_NEGATED 2;
#def NF_GLOBAL 4;
#def NF_IS_STRING 8;
#def NF_DESTRUCTURE 16;
#def NF_HAS_BODY 32;
#def NF_VOLATILE 64;
#def NF_EXPLICIT 128;
#def NF_CONST 256;
#def NF_PROTOTYPE 512;
#def NF_NO_MANGLE 1024;
#def NF_VARIADIC 2048;
#def NF_RECURSIVE 4096;
#def NF_INLINE 8192;
#def NF_DEPRECATED 16384;
#def NF_PRIVATE 32768;
#def NF_STUB 65536;
#def NF_OVERRIDE 131072;
#def NF_NO_OVERRIDE 262144;
#def NF_TEMPLATE 524288;
#def NF_INSTANCE 1048576;    // instantiated template function appended after the program
#def NF_ASYNC 2097152;       // async function (definition or prototype)

#def TS_SIGNED 1;
#def TS_CONST 2;
#def TS_VOLATILE 4;
#def TS_TIED 8;
#def TS_LOCAL 16;
#def TS_ARRAY 32;
#def TS_POINTER 64;
#def TS_CONST_POINTER 128;
#def TS_NO_FUNCTIONS 256;

namespace flux
{
    namespace ast
    {
        enum DataType
        {
            SINT,
            UINT,
            SLONG,
            ULONG,
            FLOAT,
            DOUBLE,
            CHAR,
            BOOL,
            DATA,
            BYTE,
            STRUCT,
            ENUM,
            UNION,
            OBJECT,
            VOID,
            THIS,
            FUNC_PTR,
            DICT
        };

        enum StorageClass
        {
            AUTO,
            STACK,
            HEAP,
            GLOBAL,
            LOCAL,
            REGISTER,
            SINGINIT
        };

        enum SymbolKind
        {
            TYPE,
            VARIABLE,
            FUNCTION,
            NAMESPACE,
            OBJECT,
            STRUCT,
            UNION,
            ENUM,
            TRAIT,
            OPERATOR,
            INTERFACE
        };

        enum ProtocolKind
        {
            CALL_ON,
            PASS_INTO,
            RETURN_TO
        };

        // Operator values follow fast.py ftypesys.Operator; operator_text gives the symbol.
        enum Operator
        {
            ADD,
            SUB,
            INCREMENT,
            DECREMENT,
            MUL,
            DIV,
            MOD,
            NOT,
            POWER,
            AND,
            OR,
            NAND,
            NOR,
            XOR,
            EQUAL,
            NOT_EQUAL,
            LESS_THAN,
            LESS_EQUAL,
            GREATER_THAN,
            GREATER_EQUAL,
            ASSIGN,
            PLUS_ASSIGN,
            MINUS_ASSIGN,
            MULTIPLY_ASSIGN,
            DIVIDE_ASSIGN,
            MODULO_ASSIGN,
            EXPONENT_ASSIGN,
            BITNOT,
            BITAND,
            BITOR,
            BITNAND,
            BITNOR,
            BITXOR,
            BITXNOT,
            BITXNAND,
            BITXNOR,
            AND_ASSIGN,
            OR_ASSIGN,
            XOR_ASSIGN,
            BITAND_ASSIGN,
            BITOR_ASSIGN,
            BITNAND_ASSIGN,
            BITNOR_ASSIGN,
            BITXOR_ASSIGN,
            BITXNOT_ASSIGN,
            BITXNAND_ASSIGN,
            BITXNOR_ASSIGN,
            BITSHIFT_LEFT,
            BITSHIFT_RIGHT,
            BITSHIFT_LEFT_ASSIGN,
            BITSHIFT_RIGHT_ASSIGN,
            ADDRESS_OF,
            RANGE,
            SCOPE,
            QUESTION,
            COLON,
            TIE,
            LAMBDA_ARROW,
            RETURN_ARROW,
            CHAIN_ARROW,
            RECURSE_ARROW,
            NULL_COALESCE,
            NO_MANGLE,
            FUNCTION_POINTER,
            ADDRESS_CAST
        };

        // NodeKind: one value per fast.py class. Slot meaning is listed after each value.
        enum NodeKind
        {
            NODE_LIST,    // (none): l0=items. Generic container used for grouped children.
            LITERAL,    // Literal: ival/fval/text = value, op = DataType
            IDENTIFIER,    // Identifier: text = name
            ARRAY_LITERAL,    // ArrayLiteral: l0 = elements, ts = element_type, text = string_value, op = StorageClass, NF_IS_STRING
            STRING_LITERAL,    // StringLiteral: text = value, op = StorageClass
            BINARY_OP,    // BinaryOp: a = left, op = Operator, b = right
            IN_EXPRESSION,    // InExpression: a = needle, b = haystack, NF_NEGATED
            HAS_EXPRESSION,    // HasExpression: a = subject, text = trait_name
            UNARY_OP,    // UnaryOp: op = Operator, a = operand, NF_POSTFIX
            CAST_EXPRESSION,    // CastExpression: ts = target_type, a = expression
            TYPE_CONVERT_EXPRESSION,    // TypeConvertExpression: ts = target_type, a = expression
            RANGE_EXPRESSION,    // RangeExpression: a = start, b = end, c = step
            ARRAY_COMPREHENSION,    // ArrayComprehension: a = expression, text = variable, ts = variable_type, b = iterable, c = condition
            F_STRING_LITERAL,    // FStringLiteral: l0 = parts (STRING_LITERAL for text parts, expressions otherwise)
            FUNCTION_CALL,    // FunctionCall: text = name, l0 = arguments
            MEMBER_ACCESS,    // MemberAccess: a = object, text = member
            METHOD_CALL,    // MethodCall: a = object, text = method_name, l0 = arguments
            VARIADIC_ACCESS,    // VariadicAccess: a = index
            ARRAY_ACCESS,    // ArrayAccess: a = array, b = index
            ARRAY_SLICE,    // ArraySlice: a = array, b = start, c = end
            BIT_SLICE,    // BitSlice: a = value, b = start, c = end
            BIT_INDEX_ACCESS,    // BitIndexAccess: a = value, b = index
            POINTER_DEREF,    // PointerDeref: a = pointer
            ADDRESS_OF,    // AddressOf: a = expression
            STRINGIFY,    // Stringify: text = name, text2 = member
            CODIFY,    // Codify: a = operand
            ALIGN_OF,    // AlignOf: ts = target type, or a = target expression
            TYPE_OF,    // TypeOf: a = expression
            SIZE_OF,    // SizeOf: ts = target type, or a = target expression
            ENDIAN_OF,    // EndianOf: ts = target type, or a = target expression
            NO_INIT,    // NoInit: no slots
            VARIABLE_DECLARATION,    // VariableDeclaration: text = name, ts = type_spec, a = initial_value, NF_GLOBAL
            TYPE_DECLARATION,    // TypeDeclaration: text = name, ts = type_spec, a = initial_value
            EXPRESSION_STATEMENT,    // ExpressionStatement: a = expression
            ASSIGNMENT,    // Assignment: a = target, b = value
            COMPOUND_ASSIGNMENT,    // CompoundAssignment: a = target, op = TokenType of the compound operator, b = value
            RANGE_ASSIGNMENT,    // RangeAssignment: a = array, b = start, c = end, d = fill
            TERNARY_ASSIGN,    // TernaryAssign: a = target, b = value
            BLOCK,    // Block: l0 = statements
            IF_STATEMENT,    // IfStatement: a = condition, b = then_block, l0 = elif conditions, l1 = elif blocks, c = else_block
            IF_EXPRESSION,    // IfExpression: a = value_expr, b = condition, c = else_expr
            TERNARY_OP,    // TernaryOp: a = condition, b = true_expr, c = false_expr
            NULL_COALESCE,    // NullCoalesce: a = left, b = right
            NOT_NULL,    // NotNull: a = operand
            WHILE_LOOP,    // WhileLoop: a = condition, b = body
            DO_LOOP,    // DoLoop: b = body
            DO_WHILE_LOOP,    // DoWhileLoop: b = body, a = condition
            FOR_LOOP,    // ForLoop: a = init, b = condition, c = update, d = body
            FOR_IN_LOOP,    // ForInLoop: l0 = variables (IDENTIFIER), a = iterable, b = body, NF_DESTRUCTURE
            RETURN_STATEMENT,    // ReturnStatement: a = value
            ERROR_RETURN_STATEMENT,    // ErrorReturnStatement: a = value
            BREAK_STATEMENT,    // BreakStatement: no slots
            BREAK_SWITCH_STATEMENT,    // BreakSwitchStatement: no slots
            CONTINUE_STATEMENT,    // ContinueStatement: no slots
            DEFER_STATEMENT,    // DeferStatement: a = expression, l0 = body statements, NF_HAS_BODY
            NORETURN_STATEMENT,    // NoreturnStatement: no slots
            ESCAPE_STATEMENT,    // EscapeStatement: a = call
            LABEL_STATEMENT,    // LabelStatement: text = name
            GOTO_STATEMENT,    // GotoStatement: text = target
            JUMP_STATEMENT,    // JumpStatement: a = target
            CASE,    // Case: a = value (null for default), b = body
            SWITCH_STATEMENT,    // SwitchStatement: a = expression, l0 = cases
            CATCH_CLAUSE,    // (catch tuple): ts = exception type (null for catch all), text = name, a = block
            TRY_BLOCK,    // TryBlock: a = try_body, l0 = CATCH_CLAUSE nodes
            THROW_STATEMENT,    // ThrowStatement: a = expression
            ASSERT_STATEMENT,    // AssertStatement: a = condition, b = message
            PARAMETER,    // Parameter: text = name, ts = type_spec, a = default_value
            FLUXVM_BLOCK,    // FluxVMBlock: text = body
            INLINE_ASM,    // InlineAsm: text = body, text2 = constraints, NF_VOLATILE
            DEPRECATE_STATEMENT,    // DeprecateStatement: text = namespace_path
            FUNCTION_DEF,    // FunctionDef: text = name, l0 = parameters, ts = return_type, a = body, ts2 = error_type, text2 = calling_conv, b = effect annotation, c = attenuate annotation, l1 = async tag uses (ASYNC_TAG_USE), text3 = friend_of (object methods), NF_ASYNC NF_CONST NF_VOLATILE NF_PROTOTYPE NF_NO_MANGLE NF_VARIADIC NF_RECURSIVE NF_INLINE NF_DEPRECATED NF_PRIVATE NF_OVERRIDE NF_NO_OVERRIDE NF_TEMPLATE (template method or trait prototype stub)
            FUNCTION_POINTER_DECLARATION,    // FunctionPointerDeclaration: text = name, ts = function pointer type (fp_* fields), a = initializer
            FUNCTION_POINTER_CALL,    // FunctionPointerCall: a = pointer, l0 = arguments
            FUNCTION_POINTER_ASSIGNMENT,    // FunctionPointerAssignment: text = pointer_name, a = function_expr
            DESTRUCTURING_ASSIGNMENT,    // DestructuringAssignment: l0 = variables (IDENTIFIER or VARIABLE_DECLARATION), a = source, b = source_type, NF_EXPLICIT
            DUAL_ASSIGN_DECLARATION,    // DualAssignDeclaration: ts = success_type, ts2 = error_type, text = success_name, text2 = error_name, a = call_expr
            ENUM_DEF,    // EnumDef: text = name, l0 = values (IDENTIFIER with ival), ts = underlying_type
            ENUM_DEF_STATEMENT,    // EnumDefStatement: a = enum_def
            UNION_MEMBER,    // UnionMember: text = name, ts = type_spec, a = initial_value
            UNION_DEF,    // UnionDef: text = name, l0 = members, text2 = tag_name
            TIE_EXPRESSION,    // TieExpression: a = operand
            STRUCT_MEMBER,    // StructMember: text = name, ts = type_spec, ival = offset, text2 = friend_of, a = initial_value, NF_PRIVATE
            STRUCT_INSTANCE,    // StructInstance: text = struct_name, l0 = field names (IDENTIFIER), l1 = field values
            STRUCT_LITERAL,    // StructLiteral: text = struct_type, l0 = field names (IDENTIFIER), l1 = field values, l2 = positional values
            STRUCT_DEF,    // StructDef: text = name, op = StorageClass, l0 = members, l1 = base_structs, l2 = post_structs, l3 = nested_structs, l4 = template_params, l5 = comptime_blocks
            STRUCT_FIELD_ACCESS,    // StructFieldAccess: a = struct_instance, text = field_name
            STRUCT_FIELD_ASSIGN,    // StructFieldAssign: a = struct_instance, text = field_name, b = value
            STRUCT_RECAST,    // StructRecast: text = target_type, a = source_expr
            TRAIT_DEF,    // TraitDef: text = name, l0 = prototypes
            INTERFACE_PROTOCOL,    // InterfaceProtocol: text = caller, text2 = callee, l0 = methods, op = ProtocolKind
            INTERFACE_DEF,    // InterfaceDef: text = name, l0 = params (IDENTIFIER, text2 = constraint), l1 = protocols, a = attenuate annotation, b = effect annotation
            OBJECT_METHOD,    // ObjectMethod: text = name, l0 = parameters, ts = return_type, a = body, NF_PRIVATE NF_CONST NF_VOLATILE
            OBJECT_DEF,    // ObjectDef: text = name, l0 = members, l1 = methods, l2 = base_objects, l3 = nested_objects, l4 = nested_structs, l5 = traits, a = NODE_LIST super_calls, b = NODE_LIST virtual_calls, c = NODE_LIST virtual_instances, d = NODE_LIST template_params, e = NODE_LIST interfaces, NF_PROTOTYPE
            EXTERN_BLOCK,    // ExternBlock: l0 = declarations
            EXPORT_BLOCK,    // ExportBlock: l0 = definitions
            NAMESPACE_DEF,    // NamespaceDef: text = name, l0 = functions, l1 = structs, l2 = objects, l3 = enums, l4 = unions, l5 = extern_blocks, a = NODE_LIST variables, b = NODE_LIST nested_namespaces, c = NODE_LIST base_namespaces
            USING_STATEMENT,    // UsingStatement: text = namespace_path
            NOT_USING_STATEMENT,    // NotUsingStatement: text = namespace_path
            FUNCTION_DEF_STATEMENT,    // FunctionDefStatement: a = function_def
            UNION_DEF_STATEMENT,    // UnionDefStatement: a = union_def
            STRUCT_DEF_STATEMENT,    // StructDefStatement: a = struct_def
            OBJECT_DEF_STATEMENT,    // ObjectDefStatement: a = object_def
            NAMESPACE_DEF_STATEMENT,    // NamespaceDefStatement: a = namespace_def
            MACRO_DEF,    // macroDef: text = name, l0 = params (IDENTIFIER), a = body
            MACRO_CALL,    // macroCall: text = name, l0 = arguments
            MACRO_DEF_STATEMENT,    // macroDefStatement: a = macro_def
            CONTRACT_DEF,    // ContractDef: text = name, a = body, l0 = params (IDENTIFIER), b = binding (NODE_LIST of binding refs)
            CONSTRA_RELATION,    // (relation tuple): l0 = lhs names (IDENTIFIER), text = op, l1 = rhs names (IDENTIFIER)
            CONSTRA_DEF,    // ConstraDef: text = name, l0 = params (IDENTIFIER), l1 = CONSTRA_RELATION nodes
            TYPE_FUNC_DEF,    // TypeFuncDef: text = type_name, text2 = func_name, text3 = calling_conv, l0 = parameters, ts = return_type, a = body, ts2 = receiver_type_spec, NF_PROTOTYPE NF_CONST NF_VOLATILE NF_INLINE
            TYPE_FUNC_CALL,    // TypeFuncCall: a = receiver, text = type_name, text2 = func_name, l0 = arguments
            EMIT_FLUX,    // EmitFlux: text = source_text
            COMPTIME_BLOCK,    // ComptimeBlock: text = name, l0 = body
            DICT_LITERAL_EXPR,    // DictLiteralExpr: l0 = keys, l1 = values
            DICT_LITERAL,    // DictLiteral: l0 = entries (flat key, value, key, value)
            EFFECT_NAME,    // EffectName: text = name
            EFFECT_EXPR,    // EffectExpr: text = operator, a = left, b = right
            EFFECT_DEF,    // EffectDef: text = name, a = body
            EFFECT_ANNOTATION,    // EffectAnnotation: a = effects
            ATTENUATE_ANNOTATION,    // AttenuateAnnotation: a = effects
            ASYNC_RELATION,    // AsyncRelation: l0 = operands (IDENTIFIER), l1 = ops (IDENTIFIER, text = "#" ">" "~" or "!", one per adjacent pair)
            ASYNC_TAG_DEF,    // AsyncTagDef: text = name, l0 = params (IDENTIFIER), l1 = ASYNC_RELATION nodes
            ASYNC_TARGET,    // AsyncTarget: text = name ("this" or a function), ival = 1 when a signature is given, l0 = PARAMETER nodes (ts = type), ts = return_type (optional)
            ASYNC_TAG_USE,    // AsyncTagUse: text = tag, l0 = ASYNC_TARGET nodes (a FUNCTION_DEF keeps its uses in l1)
            MODULE_DEF,    // ModuleDef: text = name, text2 = source file, l0 = body statements, l1 = from paths (STRING_LITERAL, text = path), l2 = BUILD_ENTRY nodes
            BUILD_ENTRY,    // BuildEntry: text = tag, flags bit 1 = locked, ival = value kind (0 name or string in text2, 1 bool in op, 2 name list in l0, 3 override block in l1), l2 = override targets (IDENTIFIER)
            PROGRAM    // Program: l0 = statements
        };

        struct Node, NodeVec, TypeSpec;

        def node_free(Node* n) -> void;
        def node_clone(Node* n) -> Node*;
        def typespec_copy(TypeSpec* t) -> TypeSpec*;
        def typespec_free(TypeSpec* t) -> void;

        struct NodeVec
        {
            Node** items;
            int len, cap;
        };

        struct TypeSpec
        {
            int base_type,          // DataType
                flags,              // TS_* bit flags
                bit_width,          // -1 when unset
                alignment,          // -1 when unset
                endianness,         // 1 default
                pointer_depth,
                storage_class,      // StorageClass, -1 when unset
                dict_capacity,      // -1 when unset
                fp_nparams;
            Node* array_size;
            NodeVec* array_dims;    // array dimension expressions
            TypeSpec* array_elem,
                      dict_key,
                      dict_value,
                      fp_ret;       // function pointer type: -> type
            TypeSpec** fp_params;   // function pointer type: parameter types
            byte* custom_typename, calling_conv;
        };

        struct Node
        {
            int kind, line, col, op, flags;
            i64 ival;
            double fval;
            byte* text, text2, text3;
            Node* a, b, c, d, e;
            NodeVec* l0, l1, l2, l3, l4, l5;
            TypeSpec* ts,
                      ts2,
                      ety;          // expression type set by ExprTyper, borrowed, never freed
        };

        // ===== NODE VECTORS =====

        def nv_new() -> NodeVec*
        {
            NodeVec* v = (NodeVec*)fmalloc((u64)(sizeof(NodeVec) / 8));
            if (v == (NodeVec*)0) { -> v; };
            v.len = 0;
            v.cap = 4;
            v.items = (Node**)fmalloc((u64)v.cap * (u64)(sizeof(Node*) / 8));
            if (v.items == (Node**)0)
            {
                v.cap = 0;
            };
            -> v;
        };

        def nv_push(NodeVec* v, Node* n) -> bool
        {
            if (v == (NodeVec*)0) { -> false; };
            if (v.len >= v.cap)
            {
                int nc = v.cap * 2;
                if (nc < 4) { nc = 4; };
                u64 np;
                if (v.items == (Node**)0)
                {
                    np = (u64)fmalloc((u64)nc * (u64)(sizeof(Node*) / 8));
                }
                else
                {
                    np = frealloc((u64)v.items, (size_t)((u64)nc * (u64)(sizeof(Node*) / 8)));
                };
                if (np == (u64)0) { -> false; };
                v.items = (Node**)np;
                v.cap = nc;
            };
            v.items[v.len] = n;
            v.len++;
            -> true;
        };

        def nv_free(NodeVec* v) -> void
        {
            if (v == (NodeVec*)0) { ->; };
            int i;
            while (i < v.len)
            {
                node_free(v.items[i]);
                i++;
            };
            if (v.items != (Node**)0) { ffree((byte*)v.items); };
            ffree((byte*)v);
            ->;
        };

        // ===== TYPE SPECS =====

        def typespec_new() -> TypeSpec*
        {
            TypeSpec* t = (TypeSpec*)fmalloc((u64)(sizeof(TypeSpec) / 8));
            if (t == (TypeSpec*)0) { -> t; };
            t
            {
                .base_type = DataType.SINT;
                .flags = 0;
                .bit_width = -1;
                .alignment = -1;
                .endianness = 1;
                .pointer_depth = 0;
                .storage_class = -1;
                .dict_capacity = -1;
                .fp_nparams = 0;
                .array_size = (Node*)0;
                .array_dims = (NodeVec*)0;
                .array_elem = (TypeSpec*)0;
                .dict_key = (TypeSpec*)0;
                .dict_value = (TypeSpec*)0;
                .fp_ret = (TypeSpec*)0;
                .fp_params = (TypeSpec**)0;
                .custom_typename = (byte*)0;
                .calling_conv = (byte*)0;
            };
            -> t;
        };

        def typespec_free(TypeSpec* t) -> void
        {
            if (t == (TypeSpec*)0) { ->; };
            int i;
            if (t.array_dims == (NodeVec*)0) node_free(t.array_size);
            nv_free(t.array_dims);
            typespec_free(t.array_elem);
            typespec_free(t.dict_key);
            typespec_free(t.dict_value);
            typespec_free(t.fp_ret);
            if (t.fp_params != (TypeSpec**)0)
            {
                while (i < t.fp_nparams)
                {
                    typespec_free(t.fp_params[i]);
                    i++;
                };
                ffree((byte*)t.fp_params);
            };
            ffree((byte*)t);
            ->;
        };

        // ===== NODES =====

        def node_new(int kind, int line, int col) -> Node*
        {
            Node* n = (Node*)fmalloc((u64)(sizeof(Node) / 8));
            if (n == (Node*)0) { -> n; };
            n
            {
                .kind = kind;
                .line = line;
                .col = col;
                .op = 0;
                .flags = 0;
                .ival = 0;
                .fval = 0.0;
                .text = (byte*)0;
                .text2 = (byte*)0;
                .text3 = (byte*)0;
                .a = (Node*)0;
                .b = (Node*)0;
                .c = (Node*)0;
                .d = (Node*)0;
                .e = (Node*)0;
                .l0 = (NodeVec*)0;
                .l1 = (NodeVec*)0;
                .l2 = (NodeVec*)0;
                .l3 = (NodeVec*)0;
                .l4 = (NodeVec*)0;
                .l5 = (NodeVec*)0;
                .ts = (TypeSpec*)0;
                .ts2 = (TypeSpec*)0;
                .ety = (TypeSpec*)0;
            };
            -> n;
        };

        // Returns list slot s (0 to 5) of n, creating it when missing
        def node_list(Node* n, int s) -> NodeVec*
        {
            switch (s)
            {
                case (0)
                {
                    if (n.l0 == (NodeVec*)0) { n.l0 = nv_new(); };
                    -> n.l0;
                }
                case (1)
                {
                    if (n.l1 == (NodeVec*)0) { n.l1 = nv_new(); };
                    -> n.l1;
                }
                case (2)
                {
                    if (n.l2 == (NodeVec*)0) { n.l2 = nv_new(); };
                    -> n.l2;
                }
                case (3)
                {
                    if (n.l3 == (NodeVec*)0) { n.l3 = nv_new(); };
                    -> n.l3;
                }
                case (4)
                {
                    if (n.l4 == (NodeVec*)0) { n.l4 = nv_new(); };
                    -> n.l4;
                }
                default {};
            };
            if (n.l5 == (NodeVec*)0) { n.l5 = nv_new(); };
            -> n.l5;
        };

        // Appends child to list slot s of n
        def node_push(Node* n, int s, Node* child) -> bool
        {
            -> nv_push(node_list(n, s), child);
        };

        // Number of elements in list slot s of n
        def node_count(Node* n, int s) -> int
        {
            NodeVec* v;
            if (s == 0) { v = n.l0; }
            elif (s == 1) { v = n.l1; }
            elif (s == 2) { v = n.l2; }
            elif (s == 3) { v = n.l3; }
            elif (s == 4) { v = n.l4; }
            else { v = n.l5; };
            if (v == (NodeVec*)0) { -> 0; };
            -> v.len;
        };

        // Element i of list slot s of n
        def node_child(Node* n, int s, int i) -> Node*
        {
            NodeVec* v;
            if (s == 0) { v = n.l0; }
            elif (s == 1) { v = n.l1; }
            elif (s == 2) { v = n.l2; }
            elif (s == 3) { v = n.l3; }
            elif (s == 4) { v = n.l4; }
            else { v = n.l5; };
            -> v.items[i];
        };

        def node_free(Node* n) -> void
        {
            if (n == (Node*)0) { ->; };
            node_free(n.a);
            node_free(n.b);
            node_free(n.c);
            node_free(n.d);
            node_free(n.e);
            nv_free(n.l0);
            nv_free(n.l1);
            nv_free(n.l2);
            nv_free(n.l3);
            nv_free(n.l4);
            nv_free(n.l5);
            typespec_free(n.ts);
            typespec_free(n.ts2);
            ffree((byte*)n);
            ->;
        };

        // ===== DEEP COPIES =====

        def nv_clone(NodeVec* v) -> NodeVec*
        {
            if (v == (NodeVec*)0) { -> v; };
            NodeVec* r = nv_new();
            int i;
            while (i < v.len)
            {
                nv_push(r, node_clone(v.items[i]));
                i++;
            };
            -> r;
        };

        // Deep copy of a TypeSpec. Strings stay borrowed. When array_size aliases
        // the first array dimension the copy aliases its own first dimension.
        def typespec_copy(TypeSpec* t) -> TypeSpec*
        {
            if (t == (TypeSpec*)0) { -> t; };
            TypeSpec* r = typespec_new();
            int i;
            r
            {
                .base_type = t.base_type;
                .flags = t.flags;
                .bit_width = t.bit_width;
                .alignment = t.alignment;
                .endianness = t.endianness;
                .pointer_depth = t.pointer_depth;
                .storage_class = t.storage_class;
                .dict_capacity = t.dict_capacity;
                .fp_nparams = t.fp_nparams;
                .custom_typename = t.custom_typename;
                .calling_conv = t.calling_conv;
            };
            if (t.array_dims != (NodeVec*)0)
            {
                r.array_dims = nv_clone(t.array_dims);
                if (r.array_dims.len > 0) { r.array_size = r.array_dims.items[0]; };
            }
            else
            {
                r.array_size = node_clone(t.array_size);
            };
            r
            {
                .array_elem = typespec_copy(t.array_elem);
                .dict_key = typespec_copy(t.dict_key);
                .dict_value = typespec_copy(t.dict_value);
                .fp_ret = typespec_copy(t.fp_ret);
            };
            if (t.fp_params != (TypeSpec**)0)
            {
                r.fp_params = (TypeSpec**)fmalloc((u64)(t.fp_nparams + 1) * (u64)(sizeof(TypeSpec*) / 8));
                while (i < t.fp_nparams)
                {
                    r.fp_params[i] = typespec_copy(t.fp_params[i]);
                    i++;
                };
            };
            -> r;
        };

        // Deep copy of a node tree (strings stay borrowed)
        def node_clone(Node* n) -> Node*
        {
            if (n == (Node*)0) { -> n; };
            Node* r = node_new(n.kind, n.line, n.col);
            r.op = n.op;
            r.flags = n.flags;
            r.ival = n.ival;
            r.fval = n.fval;
            r.text = n.text;
            r.text2 = n.text2;
            r.text3 = n.text3;
            r.a = node_clone(n.a);
            r.b = node_clone(n.b);
            r.c = node_clone(n.c);
            r.d = node_clone(n.d);
            r.e = node_clone(n.e);
            r.l0 = nv_clone(n.l0);
            r.l1 = nv_clone(n.l1);
            r.l2 = nv_clone(n.l2);
            r.l3 = nv_clone(n.l3);
            r.l4 = nv_clone(n.l4);
            r.l5 = nv_clone(n.l5);
            r.ts = typespec_copy(n.ts);
            r.ts2 = typespec_copy(n.ts2);
            -> r;
        };

        // ===== NAMES =====

        def node_kind_name(int k) -> byte*
        {
            switch (k)
            {
                case (NodeKind.NODE_LIST) { -> g"NODE_LIST\0"; }
                case (NodeKind.LITERAL) { -> g"LITERAL\0"; }
                case (NodeKind.IDENTIFIER) { -> g"IDENTIFIER\0"; }
                case (NodeKind.ARRAY_LITERAL) { -> g"ARRAY_LITERAL\0"; }
                case (NodeKind.STRING_LITERAL) { -> g"STRING_LITERAL\0"; }
                case (NodeKind.BINARY_OP) { -> g"BINARY_OP\0"; }
                case (NodeKind.IN_EXPRESSION) { -> g"IN_EXPRESSION\0"; }
                case (NodeKind.HAS_EXPRESSION) { -> g"HAS_EXPRESSION\0"; }
                case (NodeKind.UNARY_OP) { -> g"UNARY_OP\0"; }
                case (NodeKind.CAST_EXPRESSION) { -> g"CAST_EXPRESSION\0"; }
                case (NodeKind.TYPE_CONVERT_EXPRESSION) { -> g"TYPE_CONVERT_EXPRESSION\0"; }
                case (NodeKind.RANGE_EXPRESSION) { -> g"RANGE_EXPRESSION\0"; }
                case (NodeKind.ARRAY_COMPREHENSION) { -> g"ARRAY_COMPREHENSION\0"; }
                case (NodeKind.F_STRING_LITERAL) { -> g"F_STRING_LITERAL\0"; }
                case (NodeKind.FUNCTION_CALL) { -> g"FUNCTION_CALL\0"; }
                case (NodeKind.MEMBER_ACCESS) { -> g"MEMBER_ACCESS\0"; }
                case (NodeKind.METHOD_CALL) { -> g"METHOD_CALL\0"; }
                case (NodeKind.VARIADIC_ACCESS) { -> g"VARIADIC_ACCESS\0"; }
                case (NodeKind.ARRAY_ACCESS) { -> g"ARRAY_ACCESS\0"; }
                case (NodeKind.ARRAY_SLICE) { -> g"ARRAY_SLICE\0"; }
                case (NodeKind.BIT_SLICE) { -> g"BIT_SLICE\0"; }
                case (NodeKind.BIT_INDEX_ACCESS) { -> g"BIT_INDEX_ACCESS\0"; }
                case (NodeKind.POINTER_DEREF) { -> g"POINTER_DEREF\0"; }
                case (NodeKind.ADDRESS_OF) { -> g"ADDRESS_OF\0"; }
                case (NodeKind.STRINGIFY) { -> g"STRINGIFY\0"; }
                case (NodeKind.CODIFY) { -> g"CODIFY\0"; }
                case (NodeKind.ALIGN_OF) { -> g"ALIGN_OF\0"; }
                case (NodeKind.TYPE_OF) { -> g"TYPE_OF\0"; }
                case (NodeKind.SIZE_OF) { -> g"SIZE_OF\0"; }
                case (NodeKind.ENDIAN_OF) { -> g"ENDIAN_OF\0"; }
                case (NodeKind.NO_INIT) { -> g"NO_INIT\0"; }
                case (NodeKind.VARIABLE_DECLARATION) { -> g"VARIABLE_DECLARATION\0"; }
                case (NodeKind.TYPE_DECLARATION) { -> g"TYPE_DECLARATION\0"; }
                case (NodeKind.EXPRESSION_STATEMENT) { -> g"EXPRESSION_STATEMENT\0"; }
                case (NodeKind.ASSIGNMENT) { -> g"ASSIGNMENT\0"; }
                case (NodeKind.COMPOUND_ASSIGNMENT) { -> g"COMPOUND_ASSIGNMENT\0"; }
                case (NodeKind.RANGE_ASSIGNMENT) { -> g"RANGE_ASSIGNMENT\0"; }
                case (NodeKind.TERNARY_ASSIGN) { -> g"TERNARY_ASSIGN\0"; }
                case (NodeKind.BLOCK) { -> g"BLOCK\0"; }
                case (NodeKind.IF_STATEMENT) { -> g"IF_STATEMENT\0"; }
                case (NodeKind.IF_EXPRESSION) { -> g"IF_EXPRESSION\0"; }
                case (NodeKind.TERNARY_OP) { -> g"TERNARY_OP\0"; }
                case (NodeKind.NULL_COALESCE) { -> g"NULL_COALESCE\0"; }
                case (NodeKind.NOT_NULL) { -> g"NOT_NULL\0"; }
                case (NodeKind.WHILE_LOOP) { -> g"WHILE_LOOP\0"; }
                case (NodeKind.DO_LOOP) { -> g"DO_LOOP\0"; }
                case (NodeKind.DO_WHILE_LOOP) { -> g"DO_WHILE_LOOP\0"; }
                case (NodeKind.FOR_LOOP) { -> g"FOR_LOOP\0"; }
                case (NodeKind.FOR_IN_LOOP) { -> g"FOR_IN_LOOP\0"; }
                case (NodeKind.RETURN_STATEMENT) { -> g"RETURN_STATEMENT\0"; }
                case (NodeKind.ERROR_RETURN_STATEMENT) { -> g"ERROR_RETURN_STATEMENT\0"; }
                case (NodeKind.BREAK_STATEMENT) { -> g"BREAK_STATEMENT\0"; }
                case (NodeKind.BREAK_SWITCH_STATEMENT) { -> g"BREAK_SWITCH_STATEMENT\0"; }
                case (NodeKind.CONTINUE_STATEMENT) { -> g"CONTINUE_STATEMENT\0"; }
                case (NodeKind.DEFER_STATEMENT) { -> g"DEFER_STATEMENT\0"; }
                case (NodeKind.NORETURN_STATEMENT) { -> g"NORETURN_STATEMENT\0"; }
                case (NodeKind.ESCAPE_STATEMENT) { -> g"ESCAPE_STATEMENT\0"; }
                case (NodeKind.LABEL_STATEMENT) { -> g"LABEL_STATEMENT\0"; }
                case (NodeKind.GOTO_STATEMENT) { -> g"GOTO_STATEMENT\0"; }
                case (NodeKind.JUMP_STATEMENT) { -> g"JUMP_STATEMENT\0"; }
                case (NodeKind.CASE) { -> g"CASE\0"; }
                case (NodeKind.SWITCH_STATEMENT) { -> g"SWITCH_STATEMENT\0"; }
                case (NodeKind.CATCH_CLAUSE) { -> g"CATCH_CLAUSE\0"; }
                case (NodeKind.TRY_BLOCK) { -> g"TRY_BLOCK\0"; }
                case (NodeKind.THROW_STATEMENT) { -> g"THROW_STATEMENT\0"; }
                case (NodeKind.ASSERT_STATEMENT) { -> g"ASSERT_STATEMENT\0"; }
                case (NodeKind.PARAMETER) { -> g"PARAMETER\0"; }
                case (NodeKind.FLUXVM_BLOCK) { -> g"FLUXVM_BLOCK\0"; }
                case (NodeKind.INLINE_ASM) { -> g"INLINE_ASM\0"; }
                case (NodeKind.DEPRECATE_STATEMENT) { -> g"DEPRECATE_STATEMENT\0"; }
                case (NodeKind.FUNCTION_DEF) { -> g"FUNCTION_DEF\0"; }
                case (NodeKind.FUNCTION_POINTER_DECLARATION) { -> g"FUNCTION_POINTER_DECLARATION\0"; }
                case (NodeKind.FUNCTION_POINTER_CALL) { -> g"FUNCTION_POINTER_CALL\0"; }
                case (NodeKind.FUNCTION_POINTER_ASSIGNMENT) { -> g"FUNCTION_POINTER_ASSIGNMENT\0"; }
                case (NodeKind.DESTRUCTURING_ASSIGNMENT) { -> g"DESTRUCTURING_ASSIGNMENT\0"; }
                case (NodeKind.DUAL_ASSIGN_DECLARATION) { -> g"DUAL_ASSIGN_DECLARATION\0"; }
                case (NodeKind.ENUM_DEF) { -> g"ENUM_DEF\0"; }
                case (NodeKind.ENUM_DEF_STATEMENT) { -> g"ENUM_DEF_STATEMENT\0"; }
                case (NodeKind.UNION_MEMBER) { -> g"UNION_MEMBER\0"; }
                case (NodeKind.UNION_DEF) { -> g"UNION_DEF\0"; }
                case (NodeKind.TIE_EXPRESSION) { -> g"TIE_EXPRESSION\0"; }
                case (NodeKind.STRUCT_MEMBER) { -> g"STRUCT_MEMBER\0"; }
                case (NodeKind.STRUCT_INSTANCE) { -> g"STRUCT_INSTANCE\0"; }
                case (NodeKind.STRUCT_LITERAL) { -> g"STRUCT_LITERAL\0"; }
                case (NodeKind.STRUCT_DEF) { -> g"STRUCT_DEF\0"; }
                case (NodeKind.STRUCT_FIELD_ACCESS) { -> g"STRUCT_FIELD_ACCESS\0"; }
                case (NodeKind.STRUCT_FIELD_ASSIGN) { -> g"STRUCT_FIELD_ASSIGN\0"; }
                case (NodeKind.STRUCT_RECAST) { -> g"STRUCT_RECAST\0"; }
                case (NodeKind.TRAIT_DEF) { -> g"TRAIT_DEF\0"; }
                case (NodeKind.INTERFACE_PROTOCOL) { -> g"INTERFACE_PROTOCOL\0"; }
                case (NodeKind.INTERFACE_DEF) { -> g"INTERFACE_DEF\0"; }
                case (NodeKind.OBJECT_METHOD) { -> g"OBJECT_METHOD\0"; }
                case (NodeKind.OBJECT_DEF) { -> g"OBJECT_DEF\0"; }
                case (NodeKind.EXTERN_BLOCK) { -> g"EXTERN_BLOCK\0"; }
                case (NodeKind.EXPORT_BLOCK) { -> g"EXPORT_BLOCK\0"; }
                case (NodeKind.NAMESPACE_DEF) { -> g"NAMESPACE_DEF\0"; }
                case (NodeKind.USING_STATEMENT) { -> g"USING_STATEMENT\0"; }
                case (NodeKind.NOT_USING_STATEMENT) { -> g"NOT_USING_STATEMENT\0"; }
                case (NodeKind.FUNCTION_DEF_STATEMENT) { -> g"FUNCTION_DEF_STATEMENT\0"; }
                case (NodeKind.UNION_DEF_STATEMENT) { -> g"UNION_DEF_STATEMENT\0"; }
                case (NodeKind.STRUCT_DEF_STATEMENT) { -> g"STRUCT_DEF_STATEMENT\0"; }
                case (NodeKind.OBJECT_DEF_STATEMENT) { -> g"OBJECT_DEF_STATEMENT\0"; }
                case (NodeKind.NAMESPACE_DEF_STATEMENT) { -> g"NAMESPACE_DEF_STATEMENT\0"; }
                case (NodeKind.MACRO_DEF) { -> g"MACRO_DEF\0"; }
                case (NodeKind.MACRO_CALL) { -> g"MACRO_CALL\0"; }
                case (NodeKind.MACRO_DEF_STATEMENT) { -> g"MACRO_DEF_STATEMENT\0"; }
                case (NodeKind.CONTRACT_DEF) { -> g"CONTRACT_DEF\0"; }
                case (NodeKind.CONSTRA_RELATION) { -> g"CONSTRA_RELATION\0"; }
                case (NodeKind.CONSTRA_DEF) { -> g"CONSTRA_DEF\0"; }
                case (NodeKind.TYPE_FUNC_DEF) { -> g"TYPE_FUNC_DEF\0"; }
                case (NodeKind.TYPE_FUNC_CALL) { -> g"TYPE_FUNC_CALL\0"; }
                case (NodeKind.EMIT_FLUX) { -> g"EMIT_FLUX\0"; }
                case (NodeKind.COMPTIME_BLOCK) { -> g"COMPTIME_BLOCK\0"; }
                case (NodeKind.DICT_LITERAL_EXPR) { -> g"DICT_LITERAL_EXPR\0"; }
                case (NodeKind.DICT_LITERAL) { -> g"DICT_LITERAL\0"; }
                case (NodeKind.EFFECT_NAME) { -> g"EFFECT_NAME\0"; }
                case (NodeKind.EFFECT_EXPR) { -> g"EFFECT_EXPR\0"; }
                case (NodeKind.EFFECT_DEF) { -> g"EFFECT_DEF\0"; }
                case (NodeKind.EFFECT_ANNOTATION) { -> g"EFFECT_ANNOTATION\0"; }
                case (NodeKind.ATTENUATE_ANNOTATION) { -> g"ATTENUATE_ANNOTATION\0"; }
                case (NodeKind.ASYNC_RELATION) { -> g"ASYNC_RELATION\0"; }
                case (NodeKind.ASYNC_TAG_DEF) { -> g"ASYNC_TAG_DEF\0"; }
                case (NodeKind.ASYNC_TARGET) { -> g"ASYNC_TARGET\0"; }
                case (NodeKind.ASYNC_TAG_USE) { -> g"ASYNC_TAG_USE\0"; }
                case (NodeKind.MODULE_DEF) { -> g"MODULE_DEF\0"; }
                case (NodeKind.BUILD_ENTRY) { -> g"BUILD_ENTRY\0"; }
                case (NodeKind.PROGRAM) { -> g"PROGRAM\0"; }
                default { -> g"UNKNOWN\0"; };
            };
        };

        def operator_text(int o) -> byte*
        {
            switch (o)
            {
                case (Operator.ADD) { -> g"+\0"; }
                case (Operator.SUB) { -> g"-\0"; }
                case (Operator.INCREMENT) { -> g"++\0"; }
                case (Operator.DECREMENT) { -> g"--\0"; }
                case (Operator.MUL) { -> g"*\0"; }
                case (Operator.DIV) { -> g"/\0"; }
                case (Operator.MOD) { -> g"%\0"; }
                case (Operator.NOT) { -> g"!\0"; }
                case (Operator.POWER) { -> g"^\0"; }
                case (Operator.AND) { -> g"&\0"; }
                case (Operator.OR) { -> g"|\0"; }
                case (Operator.NAND) { -> g"!&\0"; }
                case (Operator.NOR) { -> g"!|\0"; }
                case (Operator.XOR) { -> g"^|\0"; }
                case (Operator.EQUAL) { -> g"==\0"; }
                case (Operator.NOT_EQUAL) { -> g"!=\0"; }
                case (Operator.LESS_THAN) { -> g"<\0"; }
                case (Operator.LESS_EQUAL) { -> g"<=\0"; }
                case (Operator.GREATER_THAN) { -> g">\0"; }
                case (Operator.GREATER_EQUAL) { -> g">=\0"; }
                case (Operator.ASSIGN) { -> g"=\0"; }
                case (Operator.PLUS_ASSIGN) { -> g"+=\0"; }
                case (Operator.MINUS_ASSIGN) { -> g"-=\0"; }
                case (Operator.MULTIPLY_ASSIGN) { -> g"*=\0"; }
                case (Operator.DIVIDE_ASSIGN) { -> g"/=\0"; }
                case (Operator.MODULO_ASSIGN) { -> g"%=\0"; }
                case (Operator.EXPONENT_ASSIGN) { -> g"^=\0"; }
                case (Operator.BITNOT) { -> g"`!\0"; }
                case (Operator.BITAND) { -> g"`&\0"; }
                case (Operator.BITOR) { -> g"`|\0"; }
                case (Operator.BITNAND) { -> g"`!&\0"; }
                case (Operator.BITNOR) { -> g"`!|\0"; }
                case (Operator.BITXOR) { -> g"`^|\0"; }
                case (Operator.BITXNOT) { -> g"`^|!\0"; }
                case (Operator.BITXNAND) { -> g"`^|!&\0"; }
                case (Operator.BITXNOR) { -> g"`^|!|\0"; }
                case (Operator.AND_ASSIGN) { -> g"&=\0"; }
                case (Operator.OR_ASSIGN) { -> g"|=\0"; }
                case (Operator.XOR_ASSIGN) { -> g"^|=\0"; }
                case (Operator.BITAND_ASSIGN) { -> g"`&=\0"; }
                case (Operator.BITOR_ASSIGN) { -> g"`|=\0"; }
                case (Operator.BITNAND_ASSIGN) { -> g"`!&=\0"; }
                case (Operator.BITNOR_ASSIGN) { -> g"`!|=\0"; }
                case (Operator.BITXOR_ASSIGN) { -> g"`^|=\0"; }
                case (Operator.BITXNOT_ASSIGN) { -> g"`^|!=\0"; }
                case (Operator.BITXNAND_ASSIGN) { -> g"`^|!&=\0"; }
                case (Operator.BITXNOR_ASSIGN) { -> g"`^|!|=\0"; }
                case (Operator.BITSHIFT_LEFT) { -> g"<<\0"; }
                case (Operator.BITSHIFT_RIGHT) { -> g">>\0"; }
                case (Operator.BITSHIFT_LEFT_ASSIGN) { -> g"<<=\0"; }
                case (Operator.BITSHIFT_RIGHT_ASSIGN) { -> g">>=\0"; }
                case (Operator.ADDRESS_OF) { -> g"@\0"; }
                case (Operator.RANGE) { -> g"..\0"; }
                case (Operator.SCOPE) { -> g"::\0"; }
                case (Operator.QUESTION) { -> g"?\0"; }
                case (Operator.COLON) { -> g":\0"; }
                case (Operator.TIE) { -> g"~\0"; }
                case (Operator.LAMBDA_ARROW) { -> g"<:-\0"; }
                case (Operator.RETURN_ARROW) { -> g"->\0"; }
                case (Operator.CHAIN_ARROW) { -> g"<-\0"; }
                case (Operator.RECURSE_ARROW) { -> g"<~\0"; }
                case (Operator.NULL_COALESCE) { -> g"??\0"; }
                case (Operator.NO_MANGLE) { -> g"!!\0"; }
                case (Operator.FUNCTION_POINTER) { -> g"{}*\0"; }
                case (Operator.ADDRESS_CAST) { -> g"(@)\0"; }
                default { -> g"?\0"; };
            };
        };
    };
};

#endif;
