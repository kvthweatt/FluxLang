#!/usr/bin/env python3
"""
Flux Language Lexer - Command Line Tool

Copyright (C) 2026 Karac Thweatt

Contributors:

    Piotr Bednarski


Usage:
    python3 flexer.py file.fx          # Basic token output
    python3 flexer.py file.fx -v       # Verbose output with token positions
    python3 flexer.py file.fx -c       # Show token count summary
    python3 flexer.py file.fx -v -c    # Both verbose and count summary
"""

import re
import io
import sys
from enum import Enum, auto
from dataclasses import dataclass
from typing import List, Optional, Iterator

# Reconfigure stdout/stderr to UTF-8 so Unicode characters in diagnostics
# don't crash on Windows consoles that default to a narrow codepage (e.g. CP1252).
for _stream_name in ('stdout', 'stderr'):
    _stream = getattr(sys, _stream_name)
    if hasattr(_stream, 'reconfigure'):
        _stream.reconfigure(encoding='utf-8', errors='replace')
    elif hasattr(_stream, 'buffer'):
        setattr(sys, _stream_name,
                io.TextIOWrapper(_stream.buffer, encoding='utf-8', errors='replace'))

class TokenType(Enum):
    # Literals
    SINT_LITERAL = auto()
    UINT_LITERAL = auto() # Unsigned integer literal support `123u`
    SLONG_LITERAL = auto() # l
    ULONG_LITERAL = auto() # ul
    FLOAT = auto()  # Support for 1f == float type == 1.0
    DOUBLE = auto() # Support for 64 bit floating point types
    BYTE_LITERAL = auto() # Unsigned byte literal `97b`
    CHAR = auto()
    STRING_LITERAL = auto()
    BOOL = auto()
    
    # String interpolation
    I_STRING = auto()
    F_STRING = auto()
    G_STRING = auto()
    
    # Identifiers and keywords
    IDENTIFIER = auto()
    
    # Keywords
    ALIGNOF = auto()      # builtin: alignof()
    ASSERT = auto()       # ": assert()
    ENDIANOF = auto()     # ": endianof()
    SIZEOF = auto()       # ": sizeof()
    TYPEOF = auto()       # ": typeof()
    AND = auto()          # keyword: and
    AS = auto()           # "        as
    ASM = auto()          # "        asm
    ASM_BLOCK = auto()    # {inline assembly code}
    AUTO = auto()         # "        auto
    BREAK = auto()        # "        break
    BOOL_KW = auto()      # "        bool
    BYTE = auto()         # "        byte
    CASE = auto()         # "        case
    CATCH = auto()        # "        catch
    COMPT = auto()        # "        compt
    CONST = auto()        # "        const
    CONSTRAINT = auto()   # "        constraint
    CONTINUE = auto()     # "        continue
    CONTRACT = auto()     # "        contract
    DATA = auto()         # "        data
    DEF = auto()          # "        def
    DEFER = auto()        # "        defer
    DEFAULT = auto()      # "        default
    DEPRECATE = auto()    # "        deprecate
    DICT = auto()         # "        dict
    DO = auto()           # "        do
    DOUBLE_KW = auto()    # "        double
    ELIF = auto()         # "        elif | else if
    ELSE = auto()         # "        else
    ENUM = auto()         # "        enum
    EFFECT = auto()       # "        effect
    ESCAPE_KW = auto()    # "        escape
    EXPORT = auto()       # "        export
    EXTERN = auto()       # "        extern
    FALSE = auto()        # "        false
    FASTNODE = auto()     # "        fastnode
    FLOAT_KW = auto()     # "        float
    FOR = auto()          # "        for
    FROM = auto()         # "        from
    GLOBAL = auto()       # "        global
    GOTO = auto()         # "        goto
    HAS = auto()          # "        has
    HEAP = auto()         # "        heap
    IF = auto()           # "        if
    IN = auto()           # "        in
    INLINE = auto()       # "        inline
    SINT = auto()         # "        int
    INTERFACE = auto()    # "        interface
    IS = auto()           # "        is
    JUMP = auto()         # "        jump
    LABEL = auto()        # "        label
    LOCAL = auto()        # "        local
    SLONG = auto()        # "        long
    ULONG = auto()        # "        ulong
    UINT = auto()         # "        uint
    MACRO = auto()        # "        macro
    NAMESPACE = auto()    # "        namespace
    NOT = auto()          # "        not            Represents operator: !
    NO_INIT = auto()      # "        noinit
    NORET = auto()        # "        noreturn
    OBJECT = auto()       # "        object
    OPERATOR = auto()     # "        operator
    OR = auto()           # "        or             Represents operator: |
    PRIVATE = auto()      # "        private
    PUBLIC = auto()       # "        public
    REGISTER = auto()     # "        register
    RETURN = auto()       # "        return
    SIGNED = auto()       # "        signed
    SINGINIT = auto()     # "        singinit
    STACK = auto()        # "        stack
    STRUCT = auto()       # "        struct
    SWITCH = auto()       # "        switch
    THIS = auto()         # "        this
    THROW = auto()        # "        throw
    TRAIT = auto()        # "        trait
    TRUE = auto()         # "        true
    TRY = auto()          # "        try
    UNION = auto()        # "        union
    UNSIGNED = auto()     # "        unsigned
    USING = auto()        # "        using
    VECTOR = auto()       # "        vector
    VOID = auto()         # "        void
    VOLATILE = auto()     # "        volatile
    WHILE = auto()        # "        while
    XOR = auto()          # "        xor            Represents operator: ^|

    # Calling conventions (used in place of 'def' to declare a function with a specific ABI)
    CDECL = auto()        # "        cdecl
    STDCALL = auto()      # "        stdcall
    FASTCALL = auto()     # "        fastcall
    THISCALL = auto()     # "        thiscall
    VECTORCALL = auto()   # "        vectorcall

    # Comptime
    COMPTIME = auto()     # "        comptime
    EMITFLUX = auto()     # "        emitflux
    FLUXVM = auto()       # "        fluxvm
    FLUXVM_BLOCK = auto() # {fluxvm bytecode content}

    # Regular Operators
    PLUS = auto()           # +
    MINUS = auto()          # -
    INCREMENT = auto()      # ++
    DECREMENT = auto()      # --
    MULTIPLY = auto()       # *
    DIVIDE = auto()         # /
    MODULO = auto()         # %
    EXPONENT = auto()          # ^
    # Logical
    LOGICAL_AND = auto()    # &
    LOGICAL_OR = auto()     # |
    NAND_OP = auto()        # !&
    NOR_OP = auto()         # !|
    XOR_OP = auto()         # ^|
    #XNOR_OP = auto()        # ^!|
    # Comparison
    EQUAL = auto()          # ==
    NOT_EQUAL = auto()      # !=
    LESS_THAN = auto()      # <
    LESS_EQUAL = auto()     # <=
    GREATER_THAN = auto()   # >
    GREATER_EQUAL = auto()  # >=
    # Assignment
    ASSIGN = auto()         # =
    PLUS_ASSIGN = auto()    # +=
    MINUS_ASSIGN = auto()   # -=
    MULTIPLY_ASSIGN = auto()# *=
    DIVIDE_ASSIGN = auto()  # /=
    MODULO_ASSIGN = auto()  # %=
    EXPONENT_ASSIGN = auto()   # ^=
    # Bitwise Operators
    BACKTICK = auto()       # `
    # Logical
    BITNOT_OP = auto()      # `!
    BITAND_OP = auto()      # `&
    BITOR_OP = auto()       # `|
    BITNAND_OP = auto()     # `!&
    BITNOR_OP = auto()      # `!|
    BITXOR_OP = auto()      # `^|
    BITXNOT = auto()        # `^|!
    BITXNAND = auto()       # `^|!&
    BITXNOR = auto()        # `^|!|
    # Assignment
    AND_ASSIGN = auto()      # &=
    OR_ASSIGN = auto()       # |=
    XOR_ASSIGN = auto()      # ^|=
    BITAND_ASSIGN = auto()   # `&=
    BITOR_ASSIGN = auto()    # `|=
    BITNAND_ASSIGN = auto()  # `!&=
    BITNOR_ASSIGN = auto()   # `!|=
    BITXOR_ASSIGN = auto()   # `^|=
    BITXNOT_ASSIGN = auto()  # `^|!=
    BITXNAND_ASSIGN = auto() # `^|!&=
    BITXNOR_ASSIGN = auto()  # `^|!|=

    
    # Shift
    BITSHIFT_LEFT = auto()     # <<
    BITSHIFT_RIGHT = auto()    # >>
    # Assignment
    BITSHIFT_LEFT_ASSIGN = auto()  # <<=
    BITSHIFT_RIGHT_ASSIGN = auto() # >>=
    
    # Other operators
    ADDRESS_OF = auto()     # @
    RANGE = auto()          # ..
    ELLIPSIS = auto()       # ...
    SCOPE = auto()          # ::
    QUESTION = auto()       # ?     a?b:c = Parse as ternary
    TERNARY_ASSIGN = auto() # ?=    x ?= 45 // assign if x == 0
    ADDRESS_ASSIGN = auto() # @=    byte* x @= "I love anonymous allocations!";
    NULL_COALESCE = auto()  # ??
    NOT_NULL = auto()       # !?
    COLON = auto()          # :
    TIE = auto()            # ~             Ownership/move semantics

    # Directionals
    RETURN_ARROW = auto()   # ->
    CHAIN_ARROW = auto()    # <-
    RECURSE_ARROW = auto()  # <~
    NO_MANGLE = auto()      # !! tell the compiler not to mangle this name at all for any reason.

    # SPECIAL
    FUNCTION_POINTER = auto() # {}*
    ADDRESS_CAST = auto()     # (@)
    STRINGIFY = auto()        # $
    CODIFY = auto()           # ~$
    BITSLICE = auto()         # ``
    DITTO = auto()            # #"
    DICT_LITERAL = auto()     # d{
    
    # Delimiters
    LEFT_PAREN = auto()     # (
    RIGHT_PAREN = auto()    # )
    LEFT_BRACKET = auto()   # [
    RIGHT_BRACKET = auto()  # ]
    LEFT_BRACE = auto()     # {
    RIGHT_BRACE = auto()    # }
    SEMICOLON = auto()      # ;
    COMMA = auto()          # ,
    DOT = auto()            # .
    BACKSLASH = auto()      # \
    TAG = auto()            # #

    # Special
    EOF = auto()
    NEWLINE = auto()



sextuple_binary_tokens = {
    "`^|!&=": TokenType.BITXNAND_ASSIGN,
    "`^|!|=": TokenType.BITXNOR_ASSIGN
}

quintuple_binary_tokens = {
    "`^|!&": TokenType.BITXNAND,
    "`^|!|": TokenType.BITXNOR,
    "`^|!=": TokenType.BITXNOT_ASSIGN
}


# Quad-character tokens dictionary - Watch out!
quadruple_binary_tokens = {
    "`^|!": TokenType.BITXNOT,
    '`!&=': TokenType.BITNAND_ASSIGN,
    '`!|=': TokenType.BITNOR_ASSIGN,
    '`^|=': TokenType.BITXOR_ASSIGN
}

triple_binary_tokens = {
    '`!&': TokenType.BITNAND_OP,
    '`!|': TokenType.BITNOR_OP,
    '`&=': TokenType.BITAND_ASSIGN,
    '`|=': TokenType.BITOR_ASSIGN,
    '`^|': TokenType.BITXOR_OP
}

# Triple-character tokens dictionary
triple_char_tokens = {
    '<<=': TokenType.BITSHIFT_LEFT_ASSIGN,
    '>>=': TokenType.BITSHIFT_RIGHT_ASSIGN,
    '^|=': TokenType.XOR_ASSIGN,
    '{}*': TokenType.FUNCTION_POINTER,
    '(@)': TokenType.ADDRESS_CAST,
    '...': TokenType.ELLIPSIS,
} | triple_binary_tokens

double_binary_tokens = {
    '`!': TokenType.BITNOT_OP,
    '`&': TokenType.BITAND_OP,
    '`|': TokenType.BITOR_OP
}

# Double-character tokens dictionary  
double_char_tokens = {
    '==': TokenType.EQUAL,
    '!=': TokenType.NOT_EQUAL,
    '<=': TokenType.LESS_EQUAL,
    '>=': TokenType.GREATER_EQUAL,
    '<<': TokenType.BITSHIFT_LEFT,
    '>>': TokenType.BITSHIFT_RIGHT,
    '++': TokenType.INCREMENT,
    '--': TokenType.DECREMENT,
    '+=': TokenType.PLUS_ASSIGN,
    '-=': TokenType.MINUS_ASSIGN,
    '*=': TokenType.MULTIPLY_ASSIGN,
    '/=': TokenType.DIVIDE_ASSIGN,
    '%=': TokenType.MODULO_ASSIGN,
    '^=': TokenType.EXPONENT_ASSIGN,
    '&=': TokenType.AND_ASSIGN,
    '|=': TokenType.OR_ASSIGN,
    '!&': TokenType.NAND_OP,
    '!|': TokenType.NOR_OP,
    '^|': TokenType.XOR_OP,
    '!!': TokenType.NO_MANGLE,
    '??': TokenType.NULL_COALESCE,
    '->': TokenType.RETURN_ARROW,
    '<-': TokenType.CHAIN_ARROW,
    '<~': TokenType.RECURSE_ARROW,
    '..': TokenType.RANGE,
    '::': TokenType.SCOPE,
    '?=': TokenType.TERNARY_ASSIGN,
    '!?': TokenType.NOT_NULL,
    '@=': TokenType.ADDRESS_ASSIGN,
    '``': TokenType.BITSLICE,
    '~$': TokenType.CODIFY,
    "#\"": TokenType.DITTO,
    "d{": TokenType.DICT_LITERAL
} | double_binary_tokens

# Single-character tokens dictionary
single_char_tokens = {
    '+': TokenType.PLUS,
    '-': TokenType.MINUS,
    '*': TokenType.MULTIPLY,
    '/': TokenType.DIVIDE,
    '%': TokenType.MODULO,
    '^': TokenType.EXPONENT,
    '<': TokenType.LESS_THAN,
    '>': TokenType.GREATER_THAN,
    '&': TokenType.LOGICAL_AND,
    '|': TokenType.LOGICAL_OR,
    '!': TokenType.NOT,
    '@': TokenType.ADDRESS_OF,
    '=': TokenType.ASSIGN,
    '?': TokenType.QUESTION,
    ':': TokenType.COLON,
    '(': TokenType.LEFT_PAREN,
    ')': TokenType.RIGHT_PAREN,
    '[': TokenType.LEFT_BRACKET,
    ']': TokenType.RIGHT_BRACKET,
    '{': TokenType.LEFT_BRACE,
    '}': TokenType.RIGHT_BRACE,
    ';': TokenType.SEMICOLON,
    ',': TokenType.COMMA,
    '.': TokenType.DOT,
    '~': TokenType.TIE,
    '$': TokenType.STRINGIFY,
    '\\': TokenType.BACKSLASH,
    '`': TokenType.BACKTICK,
    '#': TokenType.TAG
}

_TOKEN_TYPE_TO_STR: dict = {
    # Operators - symbol maps
    **{v: k for k, v in single_char_tokens.items()},
    **{v: k for k, v in double_char_tokens.items()},
    **{v: k for k, v in triple_char_tokens.items()},
    **{v: k for k, v in quadruple_binary_tokens.items()},
    **{v: k for k, v in quintuple_binary_tokens.items()},
    **{v: k for k, v in sextuple_binary_tokens.items()},
    # Keywords
    TokenType.ALIGNOF:    'alignof',
    TokenType.ASSERT:     'assert',
    TokenType.ENDIANOF:   'endianof',
    TokenType.SIZEOF:     'sizeof',
    TokenType.TYPEOF:     'typeof',
    TokenType.AND:        'and',
    TokenType.AS:         'as',
    TokenType.ASM:        'asm',
    TokenType.AUTO:       'auto',
    TokenType.BREAK:      'break',
    TokenType.BOOL_KW:    'bool',
    TokenType.BYTE:       'byte',
    TokenType.CASE:       'case',
    TokenType.CATCH:      'catch',
    TokenType.COMPT:      'compt',
    TokenType.CONST:      'const',
    TokenType.CONSTRAINT: 'constraint',
    TokenType.CONTINUE:   'continue',
    TokenType.CONTRACT:   'contract',
    TokenType.DATA:       'data',
    TokenType.DEF:        'def',
    TokenType.DEFER:      'defer',
    TokenType.DEFAULT:    'default',
    TokenType.DEPRECATE:  'deprecate',
    TokenType.DICT:       'dict',
    TokenType.DO:         'do',
    TokenType.DOUBLE_KW:  'double',
    TokenType.ELIF:       'elif',
    TokenType.ELSE:       'else',
    TokenType.MACRO:      'macro',
    TokenType.ENUM:       'enum',
    TokenType.ESCAPE_KW:  'escape',
    TokenType.EXPORT:     'export',
    TokenType.EXTERN:     'extern',
    TokenType.FALSE:      'false',
    TokenType.FASTNODE:   'fastnode',
    TokenType.FLOAT_KW:   'float',
    TokenType.FOR:        'for',
    TokenType.FROM:       'from',
    TokenType.GLOBAL:     'global',
    TokenType.GOTO:       'goto',
    TokenType.HAS:        'has',
    TokenType.HEAP:       'heap',
    TokenType.IF:         'if',
    TokenType.IN:         'in',
    TokenType.INTERFACE:  'interface',
    TokenType.INLINE:     'inline',
    TokenType.IS:         'is',
    TokenType.JUMP:       'jump',
    TokenType.LABEL:      'label',
    TokenType.LOCAL:      'local',
    TokenType.SLONG:      'long',
    TokenType.ULONG:      'ulong',
    TokenType.SINT:       'int',
    TokenType.UINT:       'uint',
    TokenType.NAMESPACE:  'namespace',
    TokenType.NOT:        'not',
    TokenType.NO_INIT:    'noinit',
    TokenType.NORET:      'noreturn',
    TokenType.OBJECT:     'object',
    TokenType.OPERATOR:   'operator',
    TokenType.OR:         'or',
    TokenType.PRIVATE:    'private',
    TokenType.PUBLIC:     'public',
    TokenType.REGISTER:   'register',
    TokenType.RETURN:     'return',
    TokenType.SIGNED:     'signed',
    TokenType.SINGINIT:   'singinit',
    TokenType.STACK:      'stack',
    TokenType.STRUCT:     'struct',
    TokenType.SWITCH:     'switch',
    TokenType.THIS:       'this',
    TokenType.THROW:      'throw',
    TokenType.TRAIT:      'trait',
    TokenType.TRUE:       'true',
    TokenType.TRY:        'try',
    TokenType.UNION:      'union',
    TokenType.UNSIGNED:   'unsigned',
    TokenType.USING:      'using',
    TokenType.VECTOR:     'vector',
    TokenType.VOID:       'void',
    TokenType.VOLATILE:   'volatile',
    TokenType.WHILE:      'while',
    TokenType.XOR:        'xor',
    TokenType.CDECL:      'cdecl',
    TokenType.STDCALL:    'stdcall',
    TokenType.FASTCALL:   'fastcall',
    TokenType.THISCALL:   'thiscall',
    TokenType.VECTORCALL: 'vectorcall',
    TokenType.COMPTIME:   'comptime',
    TokenType.EMITFLUX:   'emitflux',
    TokenType.FLUXVM:     'fluxvm',
    TokenType.FLUXVM_BLOCK: '<fluxvm>',
    # Literals / special
    TokenType.SINT_LITERAL:   '<int>',
    TokenType.UINT_LITERAL:   '<uint>',
    TokenType.SLONG_LITERAL:  '<long>',
    TokenType.ULONG_LITERAL:  '<ulong>',
    TokenType.FLOAT:          '<float>',
    TokenType.DOUBLE:         '<double>',
    TokenType.BYTE_LITERAL:   '<byte>',
    TokenType.CHAR:           '<char>',
    TokenType.STRING_LITERAL: '<string>',
    TokenType.BOOL:           '<bool>',
    TokenType.I_STRING:       '<istring>',
    TokenType.F_STRING:       '<fstring>',
    TokenType.G_STRING:       '<gstring>',
    TokenType.IDENTIFIER:     '<identifier>',
    TokenType.ASM_BLOCK:      '<asm>',
    TokenType.EOF:            '<EOF>',
    TokenType.NEWLINE:        '<newline>',
}

def _token_type_str(self):
    return _TOKEN_TYPE_TO_STR.get(self, self.name)

TokenType.__str__ = _token_type_str
TokenType.__repr__ = _token_type_str

@dataclass
class Token:
    type: TokenType
    value: str
    line: int
    column: int

    def __repr__(self) -> str:
        sym = _TOKEN_TYPE_TO_STR.get(self.type)
        if sym:
            return sym
        if self.value:
            return self.value
        return self.type.name

class FluxLexer:
    def __init__(self, source_code: str):
        # Strip UTF-8 BOM if present (can appear when source is read without utf-8-sig)
        if source_code.startswith('\ufeff'):
            source_code = source_code[1:]
        self.source = source_code
        self.position = 0
        self.line = 1
        self.column = 1
        self.length = len(source_code)
        
        # Keywords mapping
        self.keywords = {
            'alignof': TokenType.ALIGNOF,
            'and': TokenType.AND,
            'as': TokenType.AS,
            'asm': TokenType.ASM,
            'asm': TokenType.ASM,
            'assert': TokenType.ASSERT,
            'auto': TokenType.AUTO,
            'break': TokenType.BREAK,
            'bool': TokenType.BOOL_KW,
            'byte': TokenType.BYTE,
            'case': TokenType.CASE,
            'catch': TokenType.CATCH,
            'char': TokenType.CHAR,
            'compt': TokenType.COMPT,
            'const': TokenType.CONST,
            'constraint': TokenType.CONSTRAINT,
            'continue': TokenType.CONTINUE,
            'contract': TokenType.CONTRACT,
            'data': TokenType.DATA,
            'def': TokenType.DEF,
            'defer': TokenType.DEFER,
            'default': TokenType.DEFAULT,
            'deprecate': TokenType.DEPRECATE,
            'dict': TokenType.DICT,
            'do': TokenType.DO,
            'double': TokenType.DOUBLE_KW,
            'elif': TokenType.ELIF,
            'else': TokenType.ELSE,
            'macro': TokenType.MACRO,
            'endianof': TokenType.ENDIANOF,
            'enum': TokenType.ENUM,
            'effect': TokenType.EFFECT,
            'escape': TokenType.ESCAPE_KW,
            'export': TokenType.EXPORT,
            'extern': TokenType.EXTERN,
            'false': TokenType.FALSE,
            'fastnode': TokenType.FASTNODE,
            'float': TokenType.FLOAT_KW,
            'from': TokenType.FROM,
            'for': TokenType.FOR,
            'global': TokenType.GLOBAL,
            'goto': TokenType.GOTO,
            'has': TokenType.HAS,
            'heap': TokenType.HEAP,
            'if': TokenType.IF,
            'in': TokenType.IN,
            'inline': TokenType.INLINE,
            'int': TokenType.SINT,
            'interface': TokenType.INTERFACE,
            'is': TokenType.IS,
            'jump': TokenType.JUMP,
            'label': TokenType.LABEL,
            'local': TokenType.LOCAL,
            'long': TokenType.SLONG,
            'ulong': TokenType.ULONG,
            'namespace': TokenType.NAMESPACE,
            'not': TokenType.NOT,
            'noinit': TokenType.NO_INIT,
            'noreturn': TokenType.NORET,
            'object': TokenType.OBJECT,
            'operator': TokenType.OPERATOR,
            'or': TokenType.OR,
            'private': TokenType.PRIVATE,
            'public': TokenType.PUBLIC,
            'register': TokenType.REGISTER,
            'return': TokenType.RETURN,
            'signed': TokenType.SIGNED,
            'singinit': TokenType.SINGINIT,
            'sizeof': TokenType.SIZEOF,
            'stack': TokenType.STACK,
            'struct': TokenType.STRUCT,
            'switch': TokenType.SWITCH,
            'this': TokenType.THIS,
            'throw': TokenType.THROW,
            'trait': TokenType.TRAIT,
            'true': TokenType.TRUE,
            'try': TokenType.TRY,
            'typeof': TokenType.TYPEOF,
            'uint': TokenType.UINT,
            'union': TokenType.UNION,
            'unsigned': TokenType.UNSIGNED,
            'using': TokenType.USING,
            'vector': TokenType.VECTOR,
            'void': TokenType.VOID,
            'volatile': TokenType.VOLATILE,
            'while': TokenType.WHILE,
            'xor': TokenType.XOR,
            'cdecl': TokenType.CDECL,
            'stdcall': TokenType.STDCALL,
            'fastcall': TokenType.FASTCALL,
            'thiscall': TokenType.THISCALL,
            'vectorcall': TokenType.VECTORCALL,
            'comptime': TokenType.COMPTIME,
            'emitflux': TokenType.EMITFLUX,
            'fluxvm': TokenType.FLUXVM,
        }
    
    def current_char(self) -> Optional[str]:
        if self.position >= self.length:
            return None
        return self.source[self.position]
    
    def peek_char(self, offset: int = 1) -> Optional[str]:
        pos = self.position + offset
        if pos >= self.length:
            return None
        return self.source[pos]
    
    def advance(self, count=1) -> None:
        if self.position < self.length and self.source[self.position] == '\n':
            self.line += 1
            self.column = 1
        elif self.position < self.length and count == 1 and self.source[self.position] == '\t':
            # Tabs expand to 4-column tab stops for diagnostic column reporting,
            # matching common editor display, rather than advancing by 1 like
            # every other character. Only applies to single-character advances
            # (count==1) -- the count>1 call sites are all fixed-content
            # multi-char tokens (quotes, keywords) that never contain a tab.
            self.column += 4
        else:
            self.column += count
        self.position += count
    
    def skip_whitespace(self) -> bool:
        skipped = False
        while self.current_char() and (self.current_char() in ' \t\r\n' or self.current_char().isspace()):
            self.advance()
            skipped = True
        return skipped
    
    def read_asm_block(self) -> Token:
        """Read an inline assembly block"""
        start_pos = (self.line, self.column)
        self.advance()  # Skip opening quote
        
        result = ""
        while self.current_char() and not (self.current_char() == '"' and self.peek_char() == '"'):
            result += self.current_char()
            self.advance()
        
        if self.current_char() == '"' and self.peek_char() == '"':
            self.advance(count=2)  # Skip closing quotes
        
        return Token(TokenType.ASM_BLOCK, result, start_pos[0], start_pos[1])
    
    def read_asm_block_content(self) -> Token:
        """Read an ASM block between braces { ... }"""
        start_pos = (self.line, self.column)
        
        # Skip whitespace and newlines to find opening brace
        while self.current_char() and self.current_char() in ' \t\r\n':
            self.advance()
        
        if not self.current_char() or self.current_char() != '{':
            raise ValueError("Expected '{' after 'asm' keyword")
        
        self.advance()  # Skip opening brace
        brace_depth = 1
        result = ""
        
        while self.current_char() and brace_depth > 0:
            char = self.current_char()
            if char == '{':
                brace_depth += 1
            elif char == '}':
                brace_depth -= 1
                
            if brace_depth > 0:  # Don't include the closing brace
                result += char
            self.advance()
        
        # Clean up the result: strip leading/trailing whitespace but preserve line structure
        result = result.strip()
        
        return Token(TokenType.ASM_BLOCK, result, start_pos[0], start_pos[1])
    
    def read_fluxvm_block_content(self) -> 'Token':
        """Read a fluxvm block between braces { ... }"""
        start_pos = (self.line, self.column)
        while self.current_char() and self.current_char() in ' \t\r\n':
            self.advance()
        if not self.current_char() or self.current_char() != '{':
            raise ValueError("Expected '{' after 'fluxvm' keyword")
        self.advance()  # skip opening brace
        brace_depth = 1
        result = ""
        while self.current_char() and brace_depth > 0:
            char = self.current_char()
            if char == '{':
                brace_depth += 1
            elif char == '}':
                brace_depth -= 1
            if brace_depth > 0:
                result += char
            self.advance()
        return Token(TokenType.FLUXVM_BLOCK, result.strip(), start_pos[0], start_pos[1])

    def read_string(self, quote_char: str) -> str:
        result = ""
        self.advance()  # Skip opening quote
        
        while self.current_char() and self.current_char() != quote_char:
            if self.current_char() == '\\':
                self.advance()
                escape_char = self.current_char()
                if escape_char in 'ntr0\\''"':
                    escape_map = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '0':'\0', "'": "'", '"': '"'}
                    result += escape_map.get(escape_char, escape_char)
                elif escape_char == 'x':
                    # Hex escape
                    self.advance()
                    hex_digits = ""
                    for _ in range(2):
                        if self.current_char() and self.current_char() in '0123456789abcdefABCDEF':
                            hex_digits += self.current_char()
                            self.advance()
                        else:
                            break
                    if hex_digits:
                        result += chr(int(hex_digits, 16))
                        continue
                else:
                    result += escape_char if escape_char else '\\'
            else:
                result += self.current_char()
            self.advance()
        
        if self.current_char() == quote_char:
            self.advance()  # Skip closing quote
        
        return result
    
    def read_f_string(self) -> str:
        """Read f-string with embedded expressions"""
        result = ""
        self.advance()  # Skip opening quote
        
        while self.current_char() and self.current_char() != '"':
            if self.current_char() == '{':
                # Start of embedded expression
                result += self.current_char()
                self.advance()
                brace_count = 1
                
                while self.current_char() and brace_count > 0:
                    if self.current_char() == '"':
                        # Closing quote before '}' - unterminated interpolation.
                        err_line   = self.line
                        err_col    = self.column  # 1-based, pointing at the '"'
                        src_lines  = self.source.splitlines()
                        raw_line   = src_lines[err_line - 1].rstrip('\n') if 1 <= err_line <= len(src_lines) else ''
                        dash_count = max(0, err_col - 1)
                        caret_line = '-' * dash_count + '^ } expected here'
                        suggestion = raw_line[:dash_count] + '}' + raw_line[dash_count:] + '  // try this'
                        raise ValueError(
                            f"Parse error: Expected RIGHT_BRACE, got DOUBLE_QUOTE at {err_line}:{err_col}\n"
                            f"{raw_line}\n"
                            f"{caret_line}\n"
                            f"{suggestion}"
                        )
                    if self.current_char() == '{':
                        brace_count += 1
                    elif self.current_char() == '}':
                        brace_count -= 1
                    result += self.current_char()
                    self.advance()
            elif self.current_char() == '\\':
                self.advance()
                escape_char = self.current_char()
                if escape_char in 'ntr0\\''"':
                    escape_map = {'n': '\n', 't': '\t', 'r': '\r', '0': '\0', '\\': '\\', "'": "'", '"': '"'}
                    result += escape_map.get(escape_char, escape_char)
                else:
                    result += escape_char if escape_char else '\\'
                self.advance()
            else:
                result += self.current_char()
                self.advance()
        
        if self.current_char() == '"':
            self.advance()  # Skip closing quote
        
        return result
    
    def read_number(self) -> Token:
        start_pos = (self.line, self.column)
        result = ""
        is_float = False
        is_double = False
        is_unsigned = False
        
        # Handle duotrigesimal (0d), hex (0x), octal (0o), and binary (0b) prefixes
        if self.current_char() == '0':
            result += self.current_char()
            self.advance()

            if self.current_char() and self.current_char().lower() == 'd':
                # Duotrigesimal (Base 32)
                result += self.current_char()
                self.advance()
                while self.current_char() and self.current_char() in '0123456789ABCDEFGHIJKLMNOPQRSTUV':
                    result += self.current_char()
                    self.advance()
                
                # Check for ul (unsigned long) or u (unsigned) suffix
                if self.current_char() and self.current_char() == 'u':
                    self.advance()  # consume 'u'
                    if self.current_char() and self.current_char() == 'l':
                        self.advance()  # consume 'l'
                        return Token(TokenType.ULONG_LITERAL, result, start_pos[0], start_pos[1])
                    return Token(TokenType.UINT_LITERAL, result, start_pos[0], start_pos[1])
                # Check for l (long) suffix
                if self.current_char() and self.current_char() == 'l':
                    self.advance()  # consume 'l'
                    return Token(TokenType.SLONG_LITERAL, result, start_pos[0], start_pos[1])
                # Check for b (byte) suffix
                if self.current_char() and self.current_char() == 'b':
                    self.advance()  # consume 'b'
                    return Token(TokenType.BYTE_LITERAL, result, start_pos[0], start_pos[1])
                
                return Token(TokenType.SINT_LITERAL, result, start_pos[0], start_pos[1])
            
            if self.current_char() and self.current_char().lower() == 'x':
                # Hexadecimal
                result += self.current_char()
                self.advance()
                while self.current_char() and self.current_char() in '0123456789ABCDEF':
                    result += self.current_char()
                    self.advance()
                
                # Check for ul (unsigned long) or u (unsigned) suffix
                if self.current_char() and self.current_char() == 'u':
                    self.advance()  # consume 'u'
                    if self.current_char() and self.current_char() == 'l':
                        self.advance()  # consume 'l'
                        return Token(TokenType.ULONG_LITERAL, result, start_pos[0], start_pos[1])
                    return Token(TokenType.UINT_LITERAL, result, start_pos[0], start_pos[1])
                # Check for l (long) suffix
                if self.current_char() and self.current_char() == 'l':
                    self.advance()  # consume 'l'
                    return Token(TokenType.SLONG_LITERAL, result, start_pos[0], start_pos[1])
                # Check for b (byte) suffix
                if self.current_char() and self.current_char() == 'b':
                    self.advance()  # consume 'b'
                    return Token(TokenType.BYTE_LITERAL, result, start_pos[0], start_pos[1])
                
                return Token(TokenType.SINT_LITERAL, result, start_pos[0], start_pos[1])

            if self.current_char() and self.current_char().lower() == 'o':
                # Octal
                result += self.current_char()
                self.advance()
                while self.current_char() and self.current_char() in '01234567':
                    result += self.current_char()
                    self.advance()
                
                # Check for ul (unsigned long) or u (unsigned) suffix
                if self.current_char() and self.current_char() == 'u':
                    self.advance()  # consume 'u'
                    if self.current_char() and self.current_char() == 'l':
                        self.advance()  # consume 'l'
                        return Token(TokenType.ULONG_LITERAL, result, start_pos[0], start_pos[1])
                    return Token(TokenType.UINT_LITERAL, result, start_pos[0], start_pos[1])
                # Check for l (long) suffix
                if self.current_char() and self.current_char() == 'l':
                    self.advance()  # consume 'l'
                    return Token(TokenType.SLONG_LITERAL, result, start_pos[0], start_pos[1])
                # Check for b (byte) suffix
                if self.current_char() and self.current_char() == 'b':
                    self.advance()  # consume 'b'
                    return Token(TokenType.BYTE_LITERAL, result, start_pos[0], start_pos[1])
                
                return Token(TokenType.SINT_LITERAL, result, start_pos[0], start_pos[1])
            
            elif self.current_char() and self.current_char().lower() == 'b':
                # Could be a binary literal (0b101) or the byte suffix on 0 (0b == 0 as byte).
                # Consume the 'b' speculatively.
                result += self.current_char()
                self.advance()
                while self.current_char() and self.current_char() in '01':
                    result += self.current_char()
                    self.advance()

                # If no binary digits followed the 'b', this is `0b` meaning the
                # byte-suffix form of the integer 0, i.e. equivalent to `0b` -> byte(0).
                if result == '0b':
                    return Token(TokenType.BYTE_LITERAL, '0', start_pos[0], start_pos[1])

                # Check for ul (unsigned long) or u (unsigned) suffix
                if self.current_char() and self.current_char() == 'u':
                    self.advance()  # consume 'u'
                    if self.current_char() and self.current_char() == 'l':
                        self.advance()  # consume 'l'
                        return Token(TokenType.ULONG_LITERAL, result, start_pos[0], start_pos[1])
                    return Token(TokenType.UINT_LITERAL, result, start_pos[0], start_pos[1])
                # Check for l (long) suffix
                if self.current_char() and self.current_char() == 'l':
                    self.advance()  # consume 'l'
                    return Token(TokenType.SLONG_LITERAL, result, start_pos[0], start_pos[1])

                return Token(TokenType.SINT_LITERAL, result, start_pos[0], start_pos[1])
        
        # Read decimal digits
        while self.current_char() and self.current_char().isdigit():
            result += self.current_char()
            self.advance()
        
        dc = 0
        # Check for decimal point
        if self.current_char() == '.' and self.peek_char() and self.peek_char().isdigit():
            is_float = True
            result += self.current_char()
            self.advance()
            dc = 0
            while self.current_char() and self.current_char().isdigit():
                dc += 1
                result += self.current_char()
                self.advance()
        #print("DECIMAL COUNT:", dc)

        # Check for scientific notation: e/E followed by optional +/- and digits
        # e.g. 1e-15, 2.5E+10, 3e6
        if self.current_char() and self.current_char() in 'eE':
            exp_char = self.current_char()
            next1 = self.peek_char(1)
            next2 = self.peek_char(2)

            # Valid if next is a digit, or +/- followed by a digit
            exp_valid = (next1 and next1.isdigit()) or \
                        (next1 in '+-' and next2 and next2.isdigit())

            if exp_valid:
                # Consume 'e'/'E'
                self.advance()
                exp_str = ""
                sign = 1
                if self.current_char() in '+-':
                    if self.current_char() == '-':
                        sign = -1
                    self.advance()
                while self.current_char() and self.current_char().isdigit():
                    exp_str += self.current_char()
                    self.advance()

                exponent = int(exp_str) * sign  # may be negative

                # Expand into a plain decimal string (no scientific notation in value)
                # Use Python's Decimal for exact string expansion without float drift
                from decimal import Decimal
                expanded_decimal = Decimal(result) * (Decimal(10) ** exponent)

                # Format as plain fixed-point string (no 'E' notation)
                expanded_str = format(expanded_decimal, 'f')
                if '.' in expanded_str:
                    expanded_str = expanded_str.rstrip('0').rstrip('.')

                # An explicit f/d suffix must be consumed here and take priority
                # over the magnitude heuristic below. This branch returns directly
                # and never reaches the generic suffix-handling code further down
                # in this function (the one used for non-scientific-notation
                # literals), so previously a suffix like the 'd' in 1.0e18d was
                # left completely unconsumed: the cursor stayed sitting on it,
                # and the next call to read a token would start mid-suffix,
                # producing a stray identifier-like token with no operator
                # before it. Affects any explicit f/d suffix after an exponent,
                # not just 'd' on a large exponent specifically.
                if self.current_char() == 'f':
                    self.advance()
                    return Token(TokenType.FLOAT, expanded_str, start_pos[0], start_pos[1])
                if self.current_char() == 'd':
                    self.advance()
                    return Token(TokenType.DOUBLE, expanded_str, start_pos[0], start_pos[1])

                # No explicit suffix: choose float vs double based on the absolute
                # magnitude of the exponent (unchanged prior behavior).
                abs_exp = abs(exponent)
                if abs_exp <= 5:
                    return Token(TokenType.FLOAT, expanded_str, start_pos[0], start_pos[1])
                else:
                    return Token(TokenType.DOUBLE, expanded_str, start_pos[0], start_pos[1])

        # Determine token type based on suffixes
        token_type = TokenType.SINT_LITERAL
        
        # Check for float suffix (lowercase 'f' only)
        if self.current_char() and self.current_char() == 'f':
            token_type = TokenType.FLOAT
            is_float = True
            self.advance()
        if self.current_char() and self.current_char() == 'd':
            token_type = TokenType.DOUBLE
            is_double = True
            self.advance()
        # Check for unsigned long suffix 'ul' (must check before 'u' alone)
        elif not is_float and self.current_char() and self.current_char() == 'u' and self.peek_char() == 'l':
            token_type = TokenType.ULONG_LITERAL
            self.advance()  # consume 'u'
            self.advance()  # consume 'l'
        # Check for unsigned suffix (lowercase 'u' only) - but NOT if we already found 'f'
        elif not is_float and self.current_char() and self.current_char() == 'u':
            token_type = TokenType.UINT_LITERAL
            #result += self.current_char()  # Keep the 'u' in the token value
            self.advance()
        # Check for long suffix (lowercase 'l' only)
        elif not is_float and self.current_char() and self.current_char() == 'l':
            token_type = TokenType.SLONG_LITERAL
            self.advance()  # consume 'l'
        # Check for byte suffix (lowercase 'b' only) -- e.g. 97b -> unsigned byte literal
        elif not is_float and self.current_char() and self.current_char() == 'b':
            token_type = TokenType.BYTE_LITERAL
            self.advance()  # consume 'b'
        # Check for char suffix (lowercase 'c' only) -- e.g. 97c -> unsigned char literal
        # Store the value as an int so the parser can distinguish a numeric char literal
        # (value is already the codepoint) from a quoted char literal (value is the character
        # and needs ord() applied). The Token.value field accepts any Python type.
        elif not is_float and self.current_char() and self.current_char() == 'c':
            token_type = TokenType.CHAR
            self.advance()  # consume 'c'
            return Token(token_type, int(result), start_pos[0], start_pos[1])
        # If we have a decimal point but no 'f' suffix, it's still a float
        if is_float and dc <= 5:
            token_type = TokenType.FLOAT
        if is_double or dc > 5:
            token_type = TokenType.DOUBLE
        
        return Token(token_type, result, start_pos[0], start_pos[1])
    
    def read_identifier(self) -> Token:
        start_pos = (self.line, self.column)
        result = ""
        
        while (self.current_char() and 
               (self.current_char().isascii() and
                (self.current_char().isalnum() or self.current_char() == '_'))):
            result += self.current_char()
            self.advance()
        
        # Check if it's a keyword
        token_type = self.keywords.get(result, TokenType.IDENTIFIER)
        
        # Special handling for boolean literals
        if result == 'true':
            token_type = TokenType.TRUE
        elif result == 'false':
            token_type = TokenType.FALSE
        
        return Token(token_type, result, start_pos[0], start_pos[1])
    
    def read_interpolation_string(self) -> Token:
        """Read i-string format: i"string": {expr1; expr2; ...}"""
        start_pos = (self.line, self.column)
        
        # Read the string part
        string_part = self.read_string('"')
        
        # Skip whitespace and colon
        self.skip_whitespace()
        if self.current_char() == ':':
            self.advance()
        
        # Read the interpolation block
        self.skip_whitespace()
        if self.current_char() == '{':
            interpolation_part = ""
            brace_count = 1
            interpolation_part += self.current_char()
            self.advance()
            
            while self.current_char() and brace_count > 0:
                if self.current_char() == '{':
                    brace_count += 1
                elif self.current_char() == '}':
                    brace_count -= 1
                interpolation_part += self.current_char()
                self.advance()
            
            result = f'i"{string_part}":{interpolation_part}'
        else:
            result = f'i"{string_part}"'
        
        return Token(TokenType.I_STRING, result, start_pos[0], start_pos[1])
    
    def tokenize(self) -> List[Token]:
        tokens = []
        
        while self.position < self.length:
            # Skip whitespace
            if self.skip_whitespace():
                continue
            
            start_pos = (self.line, self.column)
            char = self.current_char()
            
            if not char:
                break
            
            # String interpolation
            if char == 'i' and self.peek_char() == '"':
                self.advance()  # Skip 'i'
                tokens.append(self.read_interpolation_string())
                continue
            
            if char == 'f' and self.peek_char() == '"':
                self.advance()  # Skip 'f'
                f_string_content = self.read_f_string()
                tokens.append(Token(TokenType.F_STRING, f'f"{f_string_content}"', start_pos[0], start_pos[1]))
                continue

            if char == 'g' and self.peek_char() == '"':
                self.advance()  # Skip 'g'
                content_g = self.read_string('"')
                tokens.append(Token(TokenType.G_STRING, content_g, start_pos[0], start_pos[1]))
                continue
            
            # String literals
            if char in '"\'':
                if char == '"':
                    content = self.read_string('"')
                    tokens.append(Token(TokenType.STRING_LITERAL, content, start_pos[0], start_pos[1]))
                else:
                    content = self.read_string("'")
                    # Single quotes with exactly one character are CHAR literals, not strings
                    if len(content) == 1:
                        tokens.append(Token(TokenType.CHAR, content, start_pos[0], start_pos[1]))
                    else:
                        tokens.append(Token(TokenType.STRING_LITERAL, content, start_pos[0], start_pos[1]))
                continue

            if char == 'a' and self.peek_char() == 's' and self.peek_char(2) == 'm' and self.peek_char(3) == '"':
                self.advance(count=3)  # Skip 'asm'
                tokens.append(Token(TokenType.ASM, 'asm', start_pos[0], start_pos[1]))
                tokens.append(self.read_asm_block())
                continue
            
            if char == 'd' and self.peek_char() == '{':
                self.advance(count=2)  # consume 'd' and '{'
                tokens.append(Token(TokenType.DICT_LITERAL, 'd{', start_pos[0], start_pos[1]))
                continue

            # Numbers
            if char.isdigit():
                tokens.append(self.read_number())
                continue
            
            # Identifiers and keywords
            if char.isascii() and (char.isalpha() or char == '_'):
                token = self.read_identifier()
                tokens.append(token)
                
                # Special handling for ASM keyword followed by brace
                if token.type == TokenType.ASM:
                    # Look ahead to see if this is followed by a brace (skip whitespace)
                    saved_pos = self.position
                    saved_line = self.line
                    saved_col = self.column
                    
                    # Skip whitespace and newlines
                    while self.current_char() and self.current_char() in ' \t\r\n':
                        self.advance()
                    
                    # Check if next character is opening brace
                    if self.current_char() == '{':
                        # This is an ASM block, read it as a whole
                        asm_block_token = self.read_asm_block_content()
                        tokens.append(asm_block_token)
                        continue

                # Special handling for FLUXVM keyword followed by brace
                if token.type == TokenType.FLUXVM:
                    saved_pos = self.position
                    saved_line = self.line
                    saved_col = self.column
                    while self.current_char() and self.current_char() in ' \t\r\n':
                        self.advance()
                    if self.current_char() == '{':
                        fluxvm_block_token = self.read_fluxvm_block_content()
                        tokens.append(fluxvm_block_token)
                        continue
                    else:
                        self.position = saved_pos
                        self.line = saved_line
                        self.column = saved_col
                
                continue
            
            # Cascading check for operators
            lookahead = char
            for i in range(1, 6):
                next_char = self.peek_char(i)
                if next_char:
                    lookahead += next_char
                else:
                    break

            # Check for 6-char tokens
            if len(lookahead) >= 6:
                six_char = lookahead[:6]
                if six_char in sextuple_binary_tokens:
                    tokens.append(Token(sextuple_binary_tokens[six_char], six_char, start_pos[0], start_pos[1]))
                    self.advance(count=6)
                    continue

            # Check for 5-char tokens
            if len(lookahead) >= 5:
                pent_char = lookahead[:5]
                if pent_char in quintuple_binary_tokens:
                    tokens.append(Token(quintuple_binary_tokens[pent_char], pent_char, start_pos[0], start_pos[1]))
                    self.advance(count=5)
                    continue

            # Check for 4-char tokens
            if len(lookahead) >= 4:
                quad_char = lookahead[:4]
                if quad_char in quadruple_binary_tokens:
                    tokens.append(Token(quadruple_binary_tokens[quad_char], quad_char, start_pos[0], start_pos[1]))
                    self.advance(count=4)
                    continue

            # Check for 3-char tokens
            if len(lookahead) >= 3:
                triple_char = lookahead[:3]
                if triple_char in triple_char_tokens:
                    tokens.append(Token(triple_char_tokens[triple_char], triple_char, start_pos[0], start_pos[1]))
                    self.advance(count=3)
                    continue
            
            # Check for 2-char tokens  
            if len(lookahead) >= 2:
                double_char = lookahead[:2]
                if double_char in double_char_tokens:
                    tokens.append(Token(double_char_tokens[double_char], double_char, start_pos[0], start_pos[1]))
                    self.advance(count=2)
                    continue
            
            # Check for 1-char tokens
            if char in single_char_tokens:
                tokens.append(Token(single_char_tokens[char], char, start_pos[0], start_pos[1]))
                self.advance()
                continue
            
            # Unknown character - warn if non-ASCII (UTF-8 is only valid inside strings)
            if not char.isascii():
                print(
                    f"[LEXER] WARNING: non-ASCII character {char!r} (U+{ord(char):04X}) "
                    f"at line {start_pos[0]}, col {start_pos[1]} is only valid inside string literals - skipped.",
                    file=sys.stderr,
                )
            self.advance()
        
        # Add EOF token
        tokens.append(Token(TokenType.EOF, '', self.line, self.column))
        return tokens

# Example usage and testing
if __name__ == "__main__":
    import sys
    import argparse
    
    def main():
        parser = argparse.ArgumentParser(description='Flux Language Lexer (flexer.py)')
        parser.add_argument('file', help='Flux source file to tokenize (.fx)')
        parser.add_argument('-v', '--verbose', action='store_true', 
                          help='Show detailed token information')
        parser.add_argument('-c', '--count', action='store_true',
                          help='Show token count summary')
        
        args = parser.parse_args()
        
        try:
            try:
                with open(args.file, 'r', encoding='utf-8-sig') as f:
                    source_code = f.read()
            except UnicodeDecodeError:
                import sys as _sys
                with open(args.file, 'r', encoding='utf-8', errors='replace') as f:
                    source_code = f.read()
                print(
                    f"Warning: '{args.file}' contains invalid UTF-8 sequences; "
                    "replacement characters have been substituted.",
                    file=_sys.stderr,
                )
        except FileNotFoundError:
            print(f"Error: File '{args.file}' not found.", file=sys.stderr)
            sys.exit(1)
        except IOError as e:
            print(f"Error reading file '{args.file}': {e}", file=sys.stderr)
            sys.exit(1)

        print("\n[PREPROCESSOR] Standard library / user-defined macros:\n")
        from fpreprocess import FXPreprocessor
        preprocessor = FXPreprocessor(args.file)
        result = preprocessor.process()
        
        lexer = FluxLexer(result)
        
        try:
            tokens = lexer.tokenize()
        except Exception as e:
            print(f"Lexer error: {e}", file=sys.stderr)
            sys.exit(1)
        
        # Filter out EOF token for cleaner output unless verbose
        display_tokens = tokens[:-1] if not args.verbose else tokens
        
        if args.count:
            # Token count summary
            token_counts = {}
            for token in tokens:
                if token.type != TokenType.EOF:
                    token_counts[token.type.name] = token_counts.get(token.type.name, 0) + 1
            
            print(f"=== Token Summary for {args.file} ===")
            print(f"Total tokens: {len(tokens) - 1}")  # Exclude EOF
            print(f"Token types: {len(token_counts)}")
            print("\nToken counts:")
            for token_type, count in sorted(token_counts.items()):
                print(f"  {token_type:20} : {count:4}")
            print()
        
        if args.verbose:
            print(f"=== Detailed Tokens for {args.file} ===")
            for i, token in enumerate(display_tokens):
                print(f"{i+1:4}: {token.type.name:20} | {repr(token.value):25} | Line {token.line:3}, Col {token.column:3}")
        else:
            print(f"=== Token Summary for {args.file} ===")
            print(f"Total tokens: {len(tokens) - 1}")  # Exclude EOF

    main()