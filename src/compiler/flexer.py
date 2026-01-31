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
from enum import Enum, auto
from dataclasses import dataclass
from typing import List, Optional, Iterator

class TokenType(Enum):
    # Literals
    SINT_LITERAL = auto()
    UINT_LITERAL = auto() # Unsigned integer literal support `123u`
    FLOAT = auto()
    CHAR = auto()
    STRING_LITERAL = auto()
    BOOL = auto()
    
    # String interpolation
    I_STRING = auto()
    F_STRING = auto()
    
    # Identifiers and keywords
    IDENTIFIER = auto()
    
    # Keywords
    ALIGNOF = auto()
    AND = auto()
    AS = auto()
    ASM = auto()
    ASM_BLOCK = auto()
    AT = auto()
    ASSERT = auto()
    AUTO = auto()
    BREAK = auto()
    BOOL_KW = auto()
    CASE = auto()
    CATCH = auto()
    COMPT = auto()
    CONST = auto()
    CONTINUE = auto()
    CONTRACT = auto()
    DATA = auto()
    DEF = auto()
    DEFAULT = auto()
    DO = auto()
    ELIF = auto()
    ELSE = auto()
    ENUM = auto()
    EXTERN = auto()
    FALSE = auto()
    FLOAT_KW = auto()
    FOR = auto()
    FROM = auto()
    GLOBAL = auto()
    HEAP = auto()
    IF = auto()
    IN = auto()
    IS = auto()
    SINT = auto()  # int
    UINT = auto()  # uint
    LOCAL = auto()
    NAMESPACE = auto()
    NOT = auto()
    NO_INIT = auto()
    OBJECT = auto()
    OR = auto()
    PRIVATE = auto()
    PUBLIC = auto()
    REGISTER = auto()
    RETURN = auto()
    SIGNED = auto()
    SIZEOF = auto()
    STACK = auto()
    STRUCT = auto()
    #SUPER = auto() #DEFERRED FOR BOOTSTRAP
    SWITCH = auto()
    THIS = auto()
    THROW = auto()
    TRUE = auto()
    TRY = auto()
    TYPEOF = auto()
    UNION = auto()
    UNSIGNED = auto()
    USING = auto()
    #VIRTUAL = auto() #DEFERRED FOR BOOTSTRAP
    VOID = auto()
    VOLATILE = auto()
    WHILE = auto()
    XOR = auto()
    
    # Fixed-width integer types
#    UINT8 = auto()
#    UINT16 = auto()
#    UINT32 = auto()
#    UINT64 = auto()
#    INT8 = auto()
#    INT16 = auto()
#    INT32 = auto()
#    INT64 = auto()
    
    # Operators
    PLUS = auto()           # +
    MINUS = auto()          # -
    MULTIPLY = auto()       # *
    DIVIDE = auto()         # /
    MODULO = auto()         # %
    POWER = auto()          # ^
    XOR_OP = auto()         # ^^
    INCREMENT = auto()      # ++
    DECREMENT = auto()      # --
    LOGICAL_AND = auto()    # &
    LOGICAL_OR = auto()     # |
    BITAND_OP = auto()      # `&
    BITOR_OP = auto()       # `|
    
    # Comparison
    EQUAL = auto()          # ==
    NOT_EQUAL = auto()      # !=
    LESS_THAN = auto()      # <
    LESS_EQUAL = auto()     # <=
    GREATER_THAN = auto()   # >
    GREATER_EQUAL = auto()  # >=
    
    # Shift
    BITSHIFT_LEFT = auto()     # <<
    BITSHIFT_RIGHT = auto()    # >>
    
    # Assignment
    ASSIGN = auto()         # =
    PLUS_ASSIGN = auto()    # +=
    MINUS_ASSIGN = auto()   # -=
    MULTIPLY_ASSIGN = auto()# *=
    DIVIDE_ASSIGN = auto()  # /=
    MODULO_ASSIGN = auto()  # %=
    AND_ASSIGN = auto()     # &=
    OR_ASSIGN = auto()      # |=
    POWER_ASSIGN = auto()   # ^=
    XOR_ASSIGN = auto()     # ^^=
    BITSHIFT_LEFT_ASSIGN = auto()  # <<=
    BITSHIFT_RIGHT_ASSIGN = auto() # >>=
    
    # Other operators
    ADDRESS_OF = auto()     # @
    RANGE = auto()          # ..
    SCOPE = auto()          # ::
    QUESTION = auto()       # ?     ?: = Parse as ternary
    COLON = auto()          # :
    TIE = auto()            # ~ Ownership/move semantics

    # Directionals
    RETURN_ARROW = auto()   # ->
    CHAIN_ARROW = auto()    # <-
    RECURSE_ARROW = auto()  # <~
    NULL_COALESCE = auto()  # ??
    NO_MANGLE = auto()      # !! tell the compiler not to mangle this name at all for any reason.

    # SPECIAL
    FUNCTION_POINTER = auto() # {}*
    ADDRESS_CAST = auto()     # (@)
    
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

    # Special
    EOF = auto()
    NEWLINE = auto()

@dataclass
class Token:
    type: TokenType
    value: str
    line: int
    column: int

class FluxLexer:
    def __init__(self, source_code: str):
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
            'at': TokenType.AT,
            'asm': TokenType.ASM,
            'assert': TokenType.ASSERT,
            'auto': TokenType.AUTO,
            'break': TokenType.BREAK,
            'bool': TokenType.BOOL_KW,
            'case': TokenType.CASE,
            'catch': TokenType.CATCH,
            'char': TokenType.CHAR,
            'compt': TokenType.COMPT,
            'const': TokenType.CONST,
            'continue': TokenType.CONTINUE,
            'data': TokenType.DATA,
            'def': TokenType.DEF,
            'default': TokenType.DEFAULT,
            'do': TokenType.DO,
            'elif': TokenType.ELIF,
            'else': TokenType.ELSE,
            'enum': TokenType.ENUM,
            'extern': TokenType.EXTERN,
            'false': TokenType.FALSE,
            'float': TokenType.FLOAT_KW,
            'from': TokenType.FROM,
            'for': TokenType.FOR,
            'if': TokenType.IF,
            'global': TokenType.GLOBAL,
            'heap': TokenType.HEAP,
            'in': TokenType.IN,
            'is': TokenType.IS,
            'int': TokenType.SINT,
            'local': TokenType.LOCAL,
            'namespace': TokenType.NAMESPACE,
            'not': TokenType.NOT,
            'noinit': TokenType.NO_INIT,
            'object': TokenType.OBJECT,
            'or': TokenType.OR,
            'private': TokenType.PRIVATE,
            'public': TokenType.PUBLIC,
            'register': TokenType.REGISTER,
            'return': TokenType.RETURN,
            'signed': TokenType.SIGNED,
            'sizeof': TokenType.SIZEOF,
            'stack': TokenType.STACK,
            'struct': TokenType.STRUCT,
            #'super': TokenType.SUPER, #DEFERRED FOR BOOTSTRAP
            'switch': TokenType.SWITCH,
            'this': TokenType.THIS,
            'throw': TokenType.THROW,
            'true': TokenType.TRUE,
            'try': TokenType.TRY,
            'typeof': TokenType.TYPEOF,
            'uint': TokenType.UINT,
            'union': TokenType.UNION,
            'unsigned': TokenType.UNSIGNED,
            'using': TokenType.USING,
            #'virtual': TokenType.VIRTUAL, #DEFERRED FOR BOOTSTRAP
            'void': TokenType.VOID,
            'volatile': TokenType.VOLATILE,
            'while': TokenType.WHILE,
            'xor': TokenType.XOR,
            #'contract': TokenType.CONTRACT,
            # Fixed-width integer types
            #'uint8': TokenType.UINT8,
            #'uint16': TokenType.UINT16,
            #'uint32': TokenType.UINT32,
            #'uint64': TokenType.UINT64,
            #'int8': TokenType.INT8,
            #'int16': TokenType.INT16,
            #'int32': TokenType.INT32,
            #'int64': TokenType.INT64
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
            self.column = count
        else:
            self.column += count
        self.position += count
    
    def skip_whitespace(self) -> None:
        while self.current_char() and self.current_char() in ' \t\r\n':
            self.advance()
    
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
                
                # Check for unsigned suffix (lowercase 'u' only)
                if self.current_char() and self.current_char() == 'u':
                    is_unsigned = True
                    result += self.current_char()
                    self.advance()
                
                return Token(TokenType.UINT_LITERAL if is_unsigned else TokenType.SINT_LITERAL, 
                           result.replace("u",""), start_pos[0], start_pos[1])
            
            if self.current_char() and self.current_char().lower() == 'x':
                # Hexadecimal
                result += self.current_char()
                self.advance()
                while self.current_char() and self.current_char() in '0123456789ABCDEF':
                    result += self.current_char()
                    self.advance()
                
                # Check for unsigned suffix (lowercase 'u' only)
                if self.current_char() and self.current_char() == 'u':
                    is_unsigned = True
                    result += self.current_char()
                    self.advance()
                
                return Token(TokenType.UINT_LITERAL if is_unsigned else TokenType.SINT_LITERAL, 
                           result.replace("u",""), start_pos[0], start_pos[1])

            if self.current_char() and self.current_char().lower() == 'o':
                # Octal
                result += self.current_char()
                self.advance()
                while self.current_char() and self.current_char() in '01234567':
                    result += self.current_char()
                    self.advance()
                
                # Check for unsigned suffix (lowercase 'u' only)
                if self.current_char() and self.current_char() == 'u':
                    is_unsigned = True
                    result += self.current_char()
                    self.advance()
                
                return Token(TokenType.UINT_LITERAL if is_unsigned else TokenType.SINT_LITERAL, 
                           result.replace("u",""), start_pos[0], start_pos[1])
            
            elif self.current_char() and self.current_char().lower() == 'b':
                # Binary
                result += self.current_char()
                self.advance()
                while self.current_char() and self.current_char() in '01':
                    result += self.current_char()
                    self.advance()
                
                # Check for unsigned suffix (lowercase 'u' only)
                if self.current_char() and self.current_char() == 'u':
                    is_unsigned = True
                    result += self.current_char()
                    self.advance()
                
                return Token(TokenType.UINT_LITERAL if is_unsigned else TokenType.SINT_LITERAL, 
                           result.replace("u",""), start_pos[0], start_pos[1])
        
        # Read decimal digits
        while self.current_char() and self.current_char().isdigit():
            result += self.current_char()
            self.advance()
        
        # Check for decimal point
        if self.current_char() == '.' and self.peek_char() and self.peek_char().isdigit():
            is_float = True
            result += self.current_char()
            self.advance()
            while self.current_char() and self.current_char().isdigit():
                result += self.current_char()
                self.advance()

        
        token_type = TokenType.FLOAT if is_float else TokenType.SINT_LITERAL
        
        # Check for unsigned suffix (lowercase 'u' only) - but NOT for floats
        if not is_float and self.current_char() and self.current_char() == 'u':
            token_type = TokenType.UINT_LITERAL
            result += self.current_char()
            self.advance()
        
        return Token(token_type, result.replace("u",""), start_pos[0], start_pos[1])
    
    def read_identifier(self) -> Token:
        start_pos = (self.line, self.column)
        result = ""
        
        while (self.current_char() and 
               (self.current_char().isalnum() or self.current_char() == '_')):
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
            if self.current_char() and self.current_char() in ' \t\r\n':
                self.skip_whitespace()
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
            
            # String literals
            if char in '"\'':
                if char == '"':
                    content = self.read_string('"')
                    tokens.append(Token(TokenType.STRING_LITERAL, content, start_pos[0], start_pos[1]))
                else:
                    content = self.read_string("'")
                    tokens.append(Token(TokenType.STRING_LITERAL, content, start_pos[0], start_pos[1]))
                continue

            if char == 'a' and self.peek_char() == 's' and self.peek_char(2) == 'm' and self.peek_char(3) == '"':
                self.advance(count=3)  # Skip 'asm'
                tokens.append(Token(TokenType.ASM, 'asm', start_pos[0], start_pos[1]))
                tokens.append(self.read_asm_block())
                continue
            
            # Numbers
            if char.isdigit():
                tokens.append(self.read_number())
                continue
            
            # Identifiers and keywords
            if char.isalpha() or char == '_':
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
                    else:
                        # Not an ASM block, restore position and continue normally
                        self.position = saved_pos
                        self.line = saved_line
                        self.column = saved_col
                
                continue
            
            # Triple-character tokens dictionary
            triple_char_tokens = {
                '<<=': TokenType.BITSHIFT_LEFT_ASSIGN,
                '>>=': TokenType.BITSHIFT_RIGHT_ASSIGN,
                '^^=': TokenType.XOR_ASSIGN,
                '{}*': TokenType.FUNCTION_POINTER,
                '(@)': TokenType.ADDRESS_CAST
            }
            
            # Double-character tokens dictionary  
            double_char_tokens = {
                '==': TokenType.EQUAL,
                '!=': TokenType.NOT_EQUAL,
                '!!': TokenType.NO_MANGLE,
                '??': TokenType.NULL_COALESCE,
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
                '^=': TokenType.POWER_ASSIGN,
                '&=': TokenType.AND_ASSIGN,
                '|=': TokenType.OR_ASSIGN,
                '^^': TokenType.XOR_OP,
                '&&': TokenType.AND,
                '||': TokenType.OR,
                '->': TokenType.RETURN_ARROW,
                '<-': TokenType.CHAIN_ARROW,
                '<~': TokenType.RECURSE_ARROW,
                '..': TokenType.RANGE,
                '::': TokenType.SCOPE,
                '`&': TokenType.BITAND_OP,
                '`|': TokenType.BITOR_OP
            }
            
            # Single-character tokens dictionary
            single_char_tokens = {
                '+': TokenType.PLUS,
                '-': TokenType.MINUS,
                '*': TokenType.MULTIPLY,
                '/': TokenType.DIVIDE,
                '%': TokenType.MODULO,
                '^': TokenType.POWER,
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
                '~': TokenType.TIE
            }
            
            # Cascading check - longest first
            # Check for 3-char tokens
            triple_char = char + (self.peek_char() or '') + (self.peek_char(2) or '')
            if triple_char in triple_char_tokens:
                tokens.append(Token(triple_char_tokens[triple_char], triple_char, start_pos[0], start_pos[1]))
                self.advance(count=3)
                continue
            
            # Check for 2-char tokens  
            double_char = char + (self.peek_char() or '')
            if double_char in double_char_tokens:
                tokens.append(Token(double_char_tokens[double_char], double_char, start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            # Check for 1-char tokens
            if char in single_char_tokens:
                tokens.append(Token(single_char_tokens[char], char, start_pos[0], start_pos[1]))
                self.advance()
                continue
            
            # Unknown character - skip it or raise error (depending on preference)
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
            with open(args.file, 'r', encoding='utf-8') as f:
                source_code = f.read()
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
            print(f"=== Tokens for {args.file} ===")
            for token in display_tokens:
                if token.value.strip():  # Only show tokens with non-empty values
                    print(f"{token.type.name:20} | {repr(token.value):20} | L{token.line}:C{token.column}")
                else:
                    print(f"{token.type.name:20} | {'<empty>':20} | L{token.line}:C{token.column}")
    
    main()