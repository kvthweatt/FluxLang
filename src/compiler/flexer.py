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
    INTEGER = auto()
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
    EXTERN = auto()
    FALSE = auto()
    FLOAT_KW = auto()
    FOR = auto()
    FROM = auto()
    IF = auto()
    IMPORT = auto()
    IN = auto()
    INT = auto()
    NAMESPACE = auto()
    NOT = auto()
    OBJECT = auto()
    OR = auto()
    PRIVATE = auto()
    PUBLIC = auto()
    RETURN = auto()
    SIGNED = auto()
    SIZEOF = auto()
    STRUCT = auto()
    SUPER = auto()
    SWITCH = auto()
    THIS = auto()
    THROW = auto()
    TRUE = auto()
    TRY = auto()
    TYPEOF = auto()
    UNION = auto()
    UNSIGNED = auto()
    USING = auto()
    VIRTUAL = auto()
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
    INCREMENT = auto()      # ++
    DECREMENT = auto()      # --
    
    # Comparison
    EQUAL = auto()          # ==
    NOT_EQUAL = auto()      # !=
    LESS_THAN = auto()      # <
    LESS_EQUAL = auto()     # <=
    GREATER_THAN = auto()   # >
    GREATER_EQUAL = auto()  # >=
    
    # Shift
    LEFT_SHIFT = auto()     # <<
    RIGHT_SHIFT = auto()    # >>
    
    # Assignment
    ASSIGN = auto()         # =
    PLUS_ASSIGN = auto()    # +=
    MINUS_ASSIGN = auto()   # -=
    MULTIPLY_ASSIGN = auto()# *=
    DIVIDE_ASSIGN = auto()  # /=
    MODULO_ASSIGN = auto()  # %=
    POWER_ASSIGN = auto()   # ^=
    XOR_ASSIGN = auto()     # ^^=
    LEFT_SHIFT_ASSIGN = auto()  # <<=
    RIGHT_SHIFT_ASSIGN = auto() # >>=
    
    # Other operators
    ADDRESS_OF = auto()     # @
    RANGE = auto()          # ..
    SCOPE = auto()          # ::
    QUESTION = auto()       # ?
    COLON = auto()          # :

    # Directionals
    RETURN_ARROW = auto()   # ->
    CHAIN_ARROW = auto()    # <-
    RECURSE_ARROW = auto()  # <~
    
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
            'extern': TokenType.EXTERN,
            'false': TokenType.FALSE,
            'float': TokenType.FLOAT_KW,
            'from': TokenType.FROM,
            'for': TokenType.FOR,
            'if': TokenType.IF,
            'import': TokenType.IMPORT,
            'in': TokenType.IN,
            'int': TokenType.INT,
            'namespace': TokenType.NAMESPACE,
            'not': TokenType.NOT,
            'object': TokenType.OBJECT,
            'or': TokenType.OR,
            'private': TokenType.PRIVATE,
            'public': TokenType.PUBLIC,
            'return': TokenType.RETURN,
            'signed': TokenType.SIGNED,
            'sizeof': TokenType.SIZEOF,
            'struct': TokenType.STRUCT,
            'super': TokenType.SUPER,
            'switch': TokenType.SWITCH,
            'this': TokenType.THIS,
            'throw': TokenType.THROW,
            'true': TokenType.TRUE,
            'try': TokenType.TRY,
            'typeof': TokenType.TYPEOF,
            'union': TokenType.UNION,
            'unsigned': TokenType.UNSIGNED,
            'using': TokenType.USING,
            'virtual': TokenType.VIRTUAL,
            'void': TokenType.VOID,
            'volatile': TokenType.VOLATILE,
            'while': TokenType.WHILE,
            'xor': TokenType.XOR,
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
    
    def skip_comment(self) -> None:
        if self.current_char() == '/' and self.peek_char() == '/':
            # Skip until end of line
            while self.current_char() and self.current_char() != '\n':
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
                if escape_char in 'ntr\\''"':
                    escape_map = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', "'": "'", '"': '"'}
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
                if escape_char in 'ntr\\''"':
                    escape_map = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', "'": "'", '"': '"'}
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
        
        # Handle hex (0x) and binary (0b) prefixes
        if self.current_char() == '0':
            result += self.current_char()
            self.advance()
            
            if self.current_char() and self.current_char().lower() == 'x':
                # Hexadecimal
                result += self.current_char()
                self.advance()
                while self.current_char() and self.current_char() in '0123456789abcdefABCDEF':
                    result += self.current_char()
                    self.advance()
                return Token(TokenType.INTEGER, result, start_pos[0], start_pos[1])
            
            elif self.current_char() and self.current_char().lower() == 'b':
                # Binary
                result += self.current_char()
                self.advance()
                while self.current_char() and self.current_char() in '01':
                    result += self.current_char()
                    self.advance()
                return Token(TokenType.INTEGER, result, start_pos[0], start_pos[1])
        
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

        
        token_type = TokenType.FLOAT if is_float else TokenType.INTEGER
        return Token(token_type, result, start_pos[0], start_pos[1])
    
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
        if result == 'true' or result == 'false':
            token_type = TokenType.BOOL
        
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
            
            # Skip comments
            if self.current_char() == '/' and self.peek_char() == '/':
                self.skip_comment()
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
            
            # Multi-character operators (order matters - longest first)
            if char == '<' and self.peek_char() == '<' and self.peek_char(2) == '=':
                tokens.append(Token(TokenType.LEFT_SHIFT_ASSIGN, '<<=', start_pos[0], start_pos[1]))
                self.advance(count=3)
                continue
            
            if char == '>' and self.peek_char() == '>' and self.peek_char(2) == '=':
                tokens.append(Token(TokenType.RIGHT_SHIFT_ASSIGN, '>>=', start_pos[0], start_pos[1]))
                self.advance(count=3)
                continue
            
            if char == '^' and self.peek_char() == '^' and self.peek_char(2) == '=':
                tokens.append(Token(TokenType.XOR_ASSIGN, '^^=', start_pos[0], start_pos[1]))
                self.advance(count=3)
                continue
            
            # Bitwise operators AND with backtick prefix (TODO - VERY EXTENSIVE)
            # Must add corresponding keywords.
            
            # Two-character operators
            if char == '=' and self.peek_char() == '=':
                tokens.append(Token(TokenType.EQUAL, '==', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '!' and self.peek_char() == '=':
                tokens.append(Token(TokenType.NOT_EQUAL, '!=', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '<':
                if self.peek_char() == '=':
                    tokens.append(Token(TokenType.LESS_EQUAL, '<=', start_pos[0], start_pos[1]))
                    self.advance(count=2)
                    continue
                elif self.peek_char() == "-":
                    tokens.append(Token(TokenType.CHAIN_ARROW, '<-', start_pos[0], start_pos[1]))
                    self.advance(count=2)
                    continue
                elif self.peek_char() == "~":
                    tokens.append(Token(TokenType.RECURSE_ARROW, '<~', start_pos[0], start_pos[1]))
                    self.advance(count=2)
                    continue
            
            if char == '>':
                if self.peek_char() == '=':
                    tokens.append(Token(TokenType.GREATER_EQUAL, '>=', start_pos[0], start_pos[1]))
                    self.advance(count=2)
                    continue
            
            if char == '<' and self.peek_char() == '<':
                tokens.append(Token(TokenType.LEFT_SHIFT, '<<', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '>' and self.peek_char() == '>':
                tokens.append(Token(TokenType.RIGHT_SHIFT, '>>', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '+' and self.peek_char() == '+':
                tokens.append(Token(TokenType.INCREMENT, '++', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '-' and self.peek_char() == '-':
                tokens.append(Token(TokenType.DECREMENT, '--', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '+' and self.peek_char() == '=':
                tokens.append(Token(TokenType.PLUS_ASSIGN, '+=', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '-':
                if self.peek_char() == '=':
                    tokens.append(Token(TokenType.MINUS_ASSIGN, '-=', start_pos[0], start_pos[1]))
                    self.advance(count=2)
                    continue
                if self.peek_char() == '>':
                    tokens.append(Token(TokenType.RETURN_ARROW, '->', start_pos[0], start_pos[1]))
                    self.advance(count=2)
                    continue
            
            if char == '*' and self.peek_char() == '=':
                tokens.append(Token(TokenType.MULTIPLY_ASSIGN, '*=', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '/' and self.peek_char() == '=':
                tokens.append(Token(TokenType.DIVIDE_ASSIGN, '/=', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '%' and self.peek_char() == '=':
                tokens.append(Token(TokenType.MODULO_ASSIGN, '%=', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '^' and self.peek_char() == '=':
                tokens.append(Token(TokenType.POWER_ASSIGN, '^=', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '&' and self.peek_char() == '=':
                tokens.append(Token(TokenType.AND_ASSIGN, '&=', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '|' and self.peek_char() == '=':
                tokens.append(Token(TokenType.OR_ASSIGN, '|=', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == '.' and self.peek_char() == '.':
                tokens.append(Token(TokenType.RANGE, '..', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            if char == ':' and self.peek_char() == ':':
                tokens.append(Token(TokenType.SCOPE, '::', start_pos[0], start_pos[1]))
                self.advance(count=2)
                continue
            
            # Single-character operators and delimiters
            single_char_tokens = {
                '+': TokenType.PLUS,
                '-': TokenType.MINUS,
                '*': TokenType.MULTIPLY,
                '/': TokenType.DIVIDE,
                '%': TokenType.MODULO,
                '^': TokenType.POWER,
                '<': TokenType.LESS_THAN,
                '>': TokenType.GREATER_THAN,
                '&': TokenType.AND,
                '|': TokenType.OR,
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
            }
            
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
        
        lexer = FluxLexer(source_code)
        
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