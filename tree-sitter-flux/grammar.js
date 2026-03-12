/**
 * Tree-sitter grammar for the Flux programming language
 * https://github.com/your-repo/tree-sitter-flux
 *
 * Derived from the Flux recursive descent parser (fparser.py)
 */

module.exports = grammar({
  name: 'flux',

  extras: $ => [
    /\s/,
    $.line_comment,
    $.block_comment,
  ],

  conflicts: $ => [
    // Cast vs parenthesized expression ambiguity
    [$.cast_expression, $.parenthesized_expression],
    // Type name vs identifier in expression context
    [$.type_spec, $.identifier],
    // Variable declaration vs expression statement
    [$.variable_declaration, $.expression_statement],
    // object/struct/trait prefix ambiguity
    [$.object_def, $.trait_prefixed_object],
    // 'struct' as keyword in _base_type vs start of struct_def
    [$._base_type, $.struct_def],
    // 'object' as keyword in _base_type vs start of object_def
    [$._base_type, $.object_def],
    [$._base_type, $.trait_prefixed_object],
    // identifier '<' ambiguity: template call vs less-than
    [$.postfix_expression, $.primary_expression],
    // '{' identifier '=' ambiguity: struct literal named field vs assignment expression
    [$.primary_expression, $.struct_literal],
    // 'void' ambiguity: void_literal in expressions vs _base_type in casts
    [$.void_literal, $._base_type],
    // identifier ambiguity: type name in cast vs identifier in expression
    [$._base_type, $.primary_expression],
    [$._base_type_with_width, $.primary_expression],
    [$._base_type_with_width],
    // (type_spec) ambiguity: cast vs single-param function signature
    [$.parameter, $.cast_expression],
    // postfix vs unary precedence
    [$.unary_expression, $.postfix_expression],
    // type_spec pointer depth ambiguity
    [$.type_spec],
    // argument_list comma ambiguity
    [$.argument_list],
  ],

  word: $ => $.identifier,

  rules: {

    // =========================================================================
    // TOP LEVEL
    // =========================================================================

    source_file: $ => repeat($._top_level_item),

    _top_level_item: $ => choice(
      $.preproc_import,
      $.preproc_ifdef,
      $.preproc_warn,
      $.preproc_stop,
      $.function_def,
      $.function_pointer_declaration,
      $.operator_def,
      $.object_def,
      $.trait_def,
      $.trait_prefixed_object,
      $.struct_def,
      $.enum_def,
      $.union_def,
      $.namespace_def,
      $.extern_block,
      $.variable_declaration_statement,
      $.using_statement,
      $.not_using_statement,
      $.asm_statement,
    ),

    // =========================================================================
    // PREPROCESSOR
    // =========================================================================

    preproc_import: $ => seq(
      '#import',
      $.string_literal,
      repeat(seq(',', $.string_literal)),
      ';',
    ),

    preproc_ifdef: $ => seq(
      choice('#ifdef', '#ifndef'),
      $.identifier,
      repeat($._top_level_item),
      optional(seq('#else', repeat($._top_level_item))),
      '#endif',
      ';',
    ),

    preproc_warn: $ => seq('#warn', $.string_literal, ';'),
    preproc_stop: $ => seq('#stop', $.string_literal, ';'),

    // =========================================================================
    // COMMENTS
    // =========================================================================

    line_comment: $ => token(seq('//', /.*/)),
    block_comment: $ => token(seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/')),

    // =========================================================================
    // LITERALS
    // =========================================================================

    integer_literal: $ => token(choice(
      /0[xX][0-9a-fA-F]+[uUlL]*/,
      /0[bB][01]+[uUlL]*/,
      /0[oO][0-7]+[uUlL]*/,
      /[0-9]+[uUlL]*/,
    )),

    float_literal: $ => token(choice(
      /[0-9]+\.[0-9]*([eE][+-]?[0-9]+)?[fF]?/,
      /\.[0-9]+([eE][+-]?[0-9]+)?[fF]?/,
      /[0-9]+[eE][+-]?[0-9]+[fF]?/,
      /[0-9]+[fF]/,
    )),

    // String and char literals - includes f-string and i-string variants
    string_literal: $ => token(choice(
      seq('"', /[^"\\]*(?:\\.[^"\\]*)*/, '"'),
      seq("'", /[^'\\]*(?:\\.[^'\\]*)*/,"'"),
    )),

    f_string_literal: $ => token(
      seq('f"', /[^"\\]*(?:\\.[^"\\]*)*/, '"')
    ),

    i_string_literal: $ => token(
      seq('i"', /[^"\\]*(?:\\.[^"\\]*)*/, '"')
    ),

    bool_literal: $ => choice('true', 'false'),

    void_literal: $ => 'void',

    noinit_literal: $ => 'noinit',

    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,

    // =========================================================================
    // KEYWORDS (reserved - matched before identifier)
    // =========================================================================

    // All keywords are inlined into rules below as string literals.
    // Tree-sitter handles keyword/identifier disambiguation via the `word` rule.

    // =========================================================================
    // TYPES
    // =========================================================================

    type_spec: $ => prec.right(5, seq(
      optional($._storage_class),
      optional('const'),
      optional('volatile'),
      optional(choice('signed', 'unsigned')),
      optional('~'),
      field('base', $._base_type_with_width),
      repeat($._array_dimension),
      repeat(prec(6, '*')),
    )),

    _base_type_with_width: $ => prec.right(3, choice(
      seq('data', optional($._data_width_spec)),
      'int',
      'uint',
      'float',
      'char',
      'bool',
      prec(2, 'void'),
      'this',
      'auto',
      $.identifier,
    )),

    _storage_class: $ => choice(
      'global', 'local', 'heap', 'stack', 'register'
    ),

    _base_type: $ => prec(3, choice(
      'int',
      'uint',
      'float',
      'char',
      'bool',
      'data',
      prec(2, 'void'),
      'this',
      'auto',
      $.identifier,
    )),

    // data{bit_width} or data{bit_width:alignment} or data{bit_width::endianness}
    _data_width_spec: $ => seq(
      '{',
      $.integer_literal,
      optional(choice(
        seq(':', $.integer_literal, optional(seq(':', $.integer_literal))),
        seq('::', $.integer_literal),
      )),
      '}',
    ),

    _array_dimension: $ => seq(
      '[',
      optional($._expression),
      ']',
    ),

    // =========================================================================
    // FUNCTION DEFINITIONS
    // =========================================================================

    function_def: $ => seq(
      optional('const'),
      optional('volatile'),
      'def',
      optional('!!'),
      field('name', choice($.identifier, $.string_literal)),
      optional($.template_params),
      '(',
      optional($.parameter_list),
      ')',
      '->',
      field('return_type', $.type_spec),
      choice(
        ';',                                        // prototype
        seq($.block, ';'),                          // definition
        seq(',', $.prototype_chain, ';'),           // multi-prototype
      ),
    ),

    template_params: $ => seq(
      '<',
      $.identifier,
      repeat(seq(',', $.identifier)),
      '>',
    ),

    parameter_list: $ => seq(
      $.parameter,
      repeat(seq(',', $.parameter)),
    ),

    parameter: $ => seq(
      $.type_spec,
      optional($.identifier),
    ),

    prototype_chain: $ => seq(
      $.prototype_entry,
      repeat(seq(',', $.prototype_entry)),
    ),

    prototype_entry: $ => seq(
      choice($.identifier, $.string_literal),
      '(',
      optional($.parameter_list),
      ')',
      '->',
      $.type_spec,
    ),

    // =========================================================================
    // FUNCTION POINTER DECLARATION
    // =========================================================================

    // def{}* name(param_types)->return_type;
    function_pointer_declaration: $ => seq(
      'def',
      '{}*',
      $.identifier,
      '(',
      optional($.fp_param_types),
      ')',
      '->',
      $.type_spec,
      optional(seq('=', $._expression)),
      repeat(seq(
        ',',
        $.identifier,
        '(',
        optional($.fp_param_types),
        ')',
        '->',
        $.type_spec,
        optional(seq('=', $._expression)),
      )),
      ';',
    ),

    fp_param_types: $ => seq(
      $.type_spec,
      repeat(seq(',', $.type_spec)),
    ),

    // =========================================================================
    // OPERATOR DEFINITION
    // =========================================================================

    operator_def: $ => seq(
      'operator',
      '(',
      $.parameter_list,
      ')',
      '[',
      repeat1($._operator_token),
      ']',
      '->',
      $.type_spec,
      choice(';', seq($.block, ';')),
    ),

    _operator_token: $ => choice(
      $.identifier,
      '+', '-', '*', '/', '%', '^', '!', '?', '@', '~',
      '++', '--', '==', '!=', '<=', '>=', '<', '>',
      '!&', '!|', '^^', '<<', '>>',
      '`!', '`&', '`|', '`!&', '`!|', '`^^', '`^^!', '`^^!&', '`^^!|',
    ),

    // =========================================================================
    // EXTERN BLOCK
    // =========================================================================

    extern_block: $ => seq(
      'extern',
      choice(
        seq('{', repeat($.function_def), '}', ';'),
        $.function_def,
      ),
    ),

    // =========================================================================
    // NAMESPACE
    // =========================================================================

    namespace_def: $ => seq(
      'namespace',
      field('name', $.identifier),
      optional(seq(':', $.identifier, repeat(seq(',', $.identifier)))),
      choice(
        ';',
        seq('{', repeat($._namespace_item), '}', ';'),
      ),
    ),

    _namespace_item: $ => choice(
      $.function_def,
      $.function_pointer_declaration,
      $.operator_def,
      $.struct_def,
      $.object_def,
      $.trait_def,
      $.trait_prefixed_object,
      $.enum_def,
      $.union_def,
      $.extern_block,
      $.namespace_def,
      $.variable_declaration_statement,
      $.using_statement,
    ),

    // =========================================================================
    // OBJECT
    // =========================================================================

    object_def: $ => seq(
      'object',
      field('name', $.identifier),
      repeat(seq(',', $.identifier)),     // comma-separated prototypes
      choice(
        ';',
        seq('{', repeat($._object_body_item), '}', ';'),
      ),
    ),

    _object_body_item: $ => choice(
      $.access_block,
      $.function_def,
      $.object_def,
      $.struct_def,
      $.variable_declaration_statement,
    ),

    access_block: $ => seq(
      choice('public', 'private'),
      '{',
      repeat($._object_body_item),
      '}',
      ';',
    ),

    // =========================================================================
    // TRAIT
    // =========================================================================

    trait_def: $ => seq(
      'trait',
      field('name', $.identifier),
      '{',
      repeat($.function_def),
      '}',
      ';',
    ),

    // TraitName object MyObj { ... };
    trait_prefixed_object: $ => seq(
      $.identifier,      // trait name(s)
      repeat(seq(',', $.identifier)),
      'object',
      field('name', $.identifier),
      choice(
        ';',
        seq('{', repeat($._object_body_item), '}', ';'),
      ),
    ),

    // =========================================================================
    // STRUCT
    // =========================================================================

    struct_def: $ => seq(
      'struct',
      field('name', $.identifier),
      repeat(seq(',', $.identifier)),
      choice(
        ';',
        seq('{', repeat($._struct_body_item), '}', ';'),
      ),
    ),

    _struct_body_item: $ => choice(
      $.struct_access_block,
      $.struct_def,
      $.struct_member,
    ),

    struct_access_block: $ => seq(
      choice('public', 'private'),
      '{',
      repeat($._struct_body_item),
      '}',
      ';',
    ),

    struct_member: $ => seq(
      $.type_spec,
      $.identifier,
      repeat(seq(',', $.identifier)),
      optional(seq('=', $._expression, repeat(seq(',', $._expression)))),
      ';',
    ),

    // =========================================================================
    // ENUM
    // =========================================================================

    enum_def: $ => seq(
      'enum',
      $.identifier,
      repeat(seq(',', $.identifier)),
      choice(
        ';',
        seq(
          '{',
          $.enum_item,
          repeat(seq(',', $.enum_item)),
          optional(','),
          '}',
          ';',
        ),
      ),
    ),

    enum_item: $ => seq(
      $.identifier,
      optional(seq('=', $.integer_literal)),
    ),

    // =========================================================================
    // UNION
    // =========================================================================

    union_def: $ => seq(
      'union',
      $.identifier,
      choice(
        ';',
        seq(
          '{',
          repeat($.union_member),
          '}',
          optional($.identifier),  // optional tag name
          ';',
        ),
      ),
    ),

    union_member: $ => seq(
      $.type_spec,
      $.identifier,
      optional(seq('=', $._expression)),
      ';',
    ),

    // =========================================================================
    // USING / NOT USING
    // =========================================================================

    using_statement: $ => seq(
      'using',
      $._namespace_path,
      repeat(seq(',', $._namespace_path)),
      ';',
    ),

    not_using_statement: $ => seq(
      choice(token('!using'), seq('not', 'using')),
      $._namespace_path,
      ';',
    ),

    _namespace_path: $ => seq(
      $.identifier,
      repeat(seq('::', $.identifier)),
    ),

    // =========================================================================
    // VARIABLE DECLARATION
    // =========================================================================

    variable_declaration_statement: $ => seq(
      $.variable_declaration,
      ';',
    ),

    variable_declaration: $ => choice(
      $.type_alias_declaration,
      $.typed_variable_declaration,
    ),

    // type_spec 'as' identifier (= expr)?
    type_alias_declaration: $ => seq(
      $.type_spec,
      'as',
      $.identifier,
      optional(seq('=', $._expression)),
      repeat(seq(',', $.identifier, optional(seq('=', $._expression)))),
    ),

    // type_spec name (= expr | from expr | (args) | {fields})?
    typed_variable_declaration: $ => seq(
      $.type_spec,
      $.identifier,
      optional(choice(
        // Constructor call: Type name(args)
        seq('(', optional($.argument_list), ')'),
        // Struct literal: Type name {fields}
        $.struct_literal,
        // Assignment: Type name = expr
        seq('=', $._expression),
        // From unpack: Type name from expr
        seq('from', $._expression),
      )),
      // Optional comma-separated additional names
      repeat(seq(
        ',',
        $.identifier,
        optional(choice(
          seq('=', $._expression),
          seq('from', $._expression),
        )),
      )),
    ),

    // =========================================================================
    // STATEMENTS
    // =========================================================================

    block: $ => seq(
      '{',
      repeat($._statement),
      '}',
    ),

    _statement: $ => choice(
      $.variable_declaration_statement,
      $.if_statement,
      $.while_statement,
      $.do_while_statement,
      $.do_statement,
      $.for_statement,
      $.switch_statement,
      $.try_statement,
      $.return_statement,
      $.break_statement,
      $.continue_statement,
      $.throw_statement,
      $.assert_statement,
      $.asm_statement,
      $.expression_statement,
    ),

    if_statement: $ => seq(
      'if',
      '(',
      $._expression,
      ')',
      $.block,
      repeat($.elif_clause),
      optional($.else_clause),
      ';',
    ),

    elif_clause: $ => seq(
      choice('elif', seq('else', 'if')),
      '(',
      $._expression,
      ')',
      $.block,
    ),

    else_clause: $ => seq('else', $.block),

    while_statement: $ => seq(
      'while',
      '(',
      $._expression,
      ')',
      $.block,
      ';',
    ),

    do_while_statement: $ => seq(
      'do',
      $.block,
      'while',
      '(',
      $._expression,
      ')',
      ';',
    ),

    do_statement: $ => seq('do', $.block, ';'),

    for_statement: $ => seq(
      'for',
      '(',
      choice($.for_in_header, $.for_c_header),
      ')',
      $.block,
      ';',
    ),

    // for (x in y) or for (x, y in z)
    for_in_header: $ => seq(
      $.identifier,
      repeat(seq(',', $.identifier)),
      'in',
      $._expression,
    ),

    // for (init; cond; update)
    for_c_header: $ => seq(
      optional(choice($.variable_declaration, $.expression_statement)),
      ';',
      optional($._expression),
      ';',
      optional($._expression),
    ),

    switch_statement: $ => seq(
      'switch',
      '(',
      $._expression,
      ')',
      '{',
      repeat($.switch_case),
      '}',
      ';',
    ),

    switch_case: $ => choice(
      seq('case', '(', $._expression, ')', $.block),
      seq('default', $.block, ';'),
    ),

    try_statement: $ => seq(
      'try',
      $.block,
      repeat1($.catch_clause),
      ';',
    ),

    catch_clause: $ => seq(
      'catch',
      '(',
      optional(choice(
        seq('auto', $.identifier),
        seq($.type_spec, $.identifier),
      )),
      ')',
      $.block,
    ),

    return_statement: $ => seq('return', optional($._expression), ';'),
    break_statement: $ => seq('break', ';'),
    continue_statement: $ => seq('continue', ';'),

    throw_statement: $ => seq('throw', '(', $._expression, ')', ';'),

    assert_statement: $ => seq(
      'assert',
      '(',
      $._expression,
      optional(seq(',', $.string_literal)),
      ')',
      ';',
    ),

    asm_statement: $ => seq(
      'asm',
      '{',
      repeat($._asm_line),
      '}',
      ';',
    ),

    _asm_line: $ => /[^\}]+/,

    expression_statement: $ => prec(1, seq($._expression, ';')),

    // =========================================================================
    // EXPRESSIONS
    // =========================================================================

    _expression: $ => choice(
      $.assignment_expression,
    ),

    assignment_expression: $ => choice(
      prec.right(1, seq($.postfix_expression, $._assign_op, $.assignment_expression)),
      $.ternary_expression,
    ),

    _assign_op: $ => choice(
      '=', '+=', '-=', '*=', '/=', '%=', '^=',
      '^^=', '&=', '|=',
      '`&=', '`|=', '`!&=', '`!|=', '`^^=', '`^^!=', '`^^!&=', '`^^!|=',
      '<<=', '>>=',
    ),

    ternary_expression: $ => choice(
      prec.right(2, seq($._expression, '?', $._expression, ':', $._expression)),
      $.null_coalesce_expression,
    ),

    null_coalesce_expression: $ => choice(
      prec.right(3, seq($._expression, '??', $._expression)),
      $.logical_or_expression,
    ),

    logical_or_expression: $ => choice(
      prec.left(4, seq($._expression, choice('|', 'or'), $._expression)),
      $.logical_and_expression,
    ),

    logical_and_expression: $ => choice(
      prec.left(5, seq($._expression, choice('&', 'and'), $._expression)),
      $.xor_expression,
    ),

    xor_expression: $ => choice(
      prec.left(6, seq($._expression, choice('^^', 'xor'), $._expression)),
      $.nor_expression,
    ),

    nor_expression: $ => choice(
      prec.left(7, seq($._expression, '!|', $._expression)),
      $.nand_expression,
    ),

    nand_expression: $ => choice(
      prec.left(8, seq($._expression, '!&', $._expression)),
      $.chain_expression,
    ),

    chain_expression: $ => choice(
      prec.left(9, seq($._expression, '<-', $._expression)),
      $.bitwise_or_expression,
    ),

    bitwise_or_expression: $ => choice(
      prec.left(10, seq($._expression, choice('`|', '`!|'), $._expression)),
      $.bitwise_xor_expression,
    ),

    bitwise_xor_expression: $ => choice(
      prec.left(11, seq($._expression, choice('`^^', '`^^!|'), $._expression)),
      $.bitwise_and_expression,
    ),

    bitwise_and_expression: $ => choice(
      prec.left(12, seq($._expression, choice('`&', '`!&'), $._expression)),
      $.equality_expression,
    ),

    equality_expression: $ => choice(
      prec.left(13, seq($._expression, choice('==', '!=', 'is', seq('is', 'not')), $._expression)),
      $.relational_expression,
    ),

    relational_expression: $ => choice(
      prec.left(14, seq($._expression, choice('<', '<=', '>', '>='), $._expression)),
      $.shift_expression,
    ),

    shift_expression: $ => choice(
      prec.left(15, seq($._expression, choice('<<', '>>'), $._expression)),
      $.arithmetic_expression,
    ),

    arithmetic_expression: $ => choice(
      prec.left(16, seq($._expression, choice('+', '-'), $._expression)),
      $.multiplicative_expression,
    ),

    multiplicative_expression: $ => choice(
      prec.left(17, seq($._expression, choice('*', '/', '%', '^'), $._expression)),
      $.cast_expression,
    ),

    // C-style cast: (type)expr
    cast_expression: $ => choice(
      prec(18, seq('(', $.type_spec, ')', $.cast_expression)),
      $.unary_expression,
    ),

    unary_expression: $ => choice(
      prec(19, seq('-',     $.unary_expression)),
      prec(19, seq('+',     $.unary_expression)),
      prec(19, seq('!',     $.unary_expression)),
      prec(19, seq('not',   $.unary_expression)),
      prec(19, seq('*',     $.cast_expression)),
      prec(19, seq('@',     $.unary_expression)),
      prec(19, seq('(@)',   $.unary_expression)),
      prec(19, seq('++',    $.unary_expression)),
      prec(19, seq('--',    $.unary_expression)),
      prec(19, seq('~',     $.unary_expression)),
      prec(19, seq('`!',    $.unary_expression)),
      prec(19, seq('`^^!',  $.unary_expression)),
      prec(19, seq('`^^!&', $.unary_expression)),
      prec(19, seq('`^^!|', $.unary_expression)),
      $.postfix_expression,
    ),

    postfix_expression: $ => choice(
      prec.left(20, seq($.postfix_expression, '[', $._expression, ']')),
      prec.left(20, seq($.postfix_expression, '[', $._expression, ':', $._expression, ']')),
      prec.left(20, seq($.postfix_expression, '(', optional($.argument_list), ')')),
      prec.left(20, seq($.postfix_expression, '.', $.identifier)),
      prec.left(20, seq($.postfix_expression, '++')),
      prec.left(20, seq($.postfix_expression, '--')),
      prec.left(20, seq($.postfix_expression, 'as', $.type_spec)),
      prec.left(20, seq($.postfix_expression, 'from', $.postfix_expression)),
      prec.left(20, seq($.postfix_expression, 'if', '(', $._expression, ')', optional(seq('else', $.postfix_expression)))),
      $.primary_expression,
    ),

    argument_list: $ => prec.right(seq(
      $._expression,
      repeat(seq(',', $._expression)),
    )),

    // =========================================================================
    // PRIMARY EXPRESSIONS
    // =========================================================================

    primary_expression: $ => choice(
      $.integer_literal,
      $.float_literal,
      $.f_string_literal,
      $.i_string_literal,
      $.string_literal,
      $.bool_literal,
      $.void_literal,
      $.noinit_literal,
      $.identifier,
      $.parenthesized_expression,
      $.array_literal,
      $.array_comprehension,
      $.struct_literal,
      $.sizeof_expression,
      $.typeof_expression,
      $.alignof_expression,
      $.recurse_expression,
      $.lambda_expression,
      $.scope_access,
    ),

    parenthesized_expression: $ => seq('(', $._expression, ')'),

    array_literal: $ => seq(
      '[',
      optional(seq(
        $._expression,
        repeat(seq(',', $._expression)),
      )),
      ']',
    ),

    // [expr for (type var in iterable)]
    // [expr for (type var = init; cond; update)]
    array_comprehension: $ => seq(
      '[',
      $._expression,
      'for',
      '(',
      choice(
        seq($.type_spec, $.identifier, 'in', $._expression),
        seq($.type_spec, $.identifier, '=', $._expression, ';', $._expression, ';', $._expression),
      ),
      ')',
      optional(seq('if', '(', $._expression, ')')),
      ']',
    ),

    struct_literal: $ => prec(2, seq(
      '{',
      optional(choice(
        // Named: {x = 1, y = 2}
        seq(
          $.identifier, '=', $._expression,
          repeat(seq(',', $.identifier, '=', $._expression)),
        ),
        // Positional: {1, 2}
        seq(
          $._expression,
          repeat(seq(',', $._expression)),
        ),
      )),
      '}',
    )),

    sizeof_expression: $ => seq('sizeof', '(', choice($.type_spec, $._expression), ')'),
    typeof_expression: $ => seq('typeof', '(', choice($.type_spec, $._expression), ')'),
    alignof_expression: $ => seq('alignof', '(', choice($.type_spec, $._expression), ')'),

    // Recursion arrow: func <~ args
    recurse_expression: $ => seq($.identifier, '<~', $.argument_list),

    // Lambda: (params) <:- expr
    lambda_expression: $ => seq(
      '(', optional($.parameter_list), ')',
      '<:-',
      $._expression,
    ),

    // Namespace scope access: ns::member
    scope_access: $ => seq(
      $.identifier,
      '::',
      $.identifier,
      repeat(seq('::', $.identifier)),
    ),

    // =========================================================================
    // INLINE ASSEMBLY
    // =========================================================================

    asm_statement: $ => seq(
      'asm',
      '{',
      /[^}]*/,
      '}',
      ';',
    ),

    // =========================================================================
    // MISC
    // =========================================================================

    // i-string acceptor block: i"Hello {}" : { expr; expr; }
    i_string_acceptor: $ => seq(
      $.i_string_literal,
      ':',
      '{',
      repeat(seq($._expression, ';')),
      '}',
    ),
  },
});