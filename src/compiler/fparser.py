#!/usr/bin/env python3
"""
Flux Language Parser

Copyright (C) 2026 Karac Thweatt

Contributors:

    Piotr Bednarski

A recursive descent parser for the Flux programming language.
Converts tokens from the lexer into an Abstract Syntax Tree (AST).

Usage:
    python3 parser.py file.fx          # Parse and show AST
    python3 parser.py file.fx -v       # Verbose parsing with debug info
    python3 parser.py file.fx -a       # Show AST structure
"""

import sys
from typing import List, Optional, Union, Any
from flexer import FluxLexer, TokenType, Token
from fast import *

class ParseError(Exception):
    """Exception raised when parsing fails"""
    def __init__(self, message: str, token: Optional[Token] = None):
        self.message = message
        self.token = token
        super().__init__(f"{message}" + (f" at {token.line}:{token.column}" if token else ""))

class FluxParser:
    def __init__(self, tokens: List[Token]):
        self.tokens = tokens
        self.position = 0
        self.current_token = self.tokens[0] if tokens else None
        self.parse_errors = []  # Track parse errors
        self._processing_imports = set()
    
    def error(self, message: str) -> None:
        """Raise a parse error with current token context"""
        raise ParseError(message, self.current_token)
    
    def advance(self) -> Token:
        """Move to the next token"""
        if self.position < len(self.tokens) - 1:
            self.position += 1
            self.current_token = self.tokens[self.position]
        return self.current_token
    
    def peek(self, offset: int = 1) -> Optional[Token]:
        """Look ahead at the next token without consuming it"""
        pos = self.position + offset
        if pos < len(self.tokens):
            return self.tokens[pos]
        return None
    
    def expect(self, *token_types: TokenType) -> bool:
        """Check if current token matches any of the given types"""
        if self.current_token is None:
            return False
        return self.current_token.type in token_types
    
    def consume(self, expected_type: TokenType, message: str = None) -> Token:
        """Consume a token of the expected type or raise error"""
        if not self.expect(expected_type):
            msg = message or f"Expected {expected_type.name}, got {self.current_token.type.name if self.current_token else 'EOF'}"
            self.error(msg)
        token = self.current_token
        self.advance()
        return token
    
    def synchronize(self) -> None:
        """Synchronize parser state after an error"""
        self.advance()
        while not self.expect(TokenType.EOF):
            if self.tokens[self.position - 1].type == TokenType.SEMICOLON:
                return
            if self.expect(TokenType.DEF, TokenType.STRUCT, TokenType.OBJECT, 
                         TokenType.NAMESPACE, TokenType.IF, TokenType.WHILE,
                         TokenType.FOR, TokenType.RETURN):
                return
            self.advance()

    # ============ GRAMMAR RULES ============
    
    def parse(self) -> Program:
        """
        program -> statement* EOF
        """
        statements = []
        while not self.expect(TokenType.EOF):
            try:
                stmt = self.statement()
                if isinstance(stmt, list):
                    statements.extend(stmt)
                elif stmt:
                    statements.append(stmt)
            except ParseError as e:
                error_msg = f"Parse error: {e}"
                print(error_msg, file=sys.stderr)
                self.parse_errors.append(error_msg)
                self.synchronize()
        return Program(statements)
    
    def has_errors(self) -> bool:
        """Check if any parse errors occurred during parsing"""
        return len(self.parse_errors) > 0
    
    def get_errors(self) -> List[str]:
        """Get list of parse error messages"""
        return self.parse_errors.copy()
    
    def statement(self) -> Optional[Statement]:
        """
        statement -> 
                  | function_def_statement
                  | struct_def
                  | object_def_statement
                  | namespace_def
                  | custom_type_statement
                  | variable_declaration ';'
                  | expression_statement
                  | assignment_statement
                  | control_statement
        """
        storage_class = None
        is_const = False
        is_volatile = False
        
        # Parse storage class FIRST (global, local, heap, stack, register)
        if self.expect(TokenType.GLOBAL):
            storage_class = 'global'
            self.advance()
        elif self.expect(TokenType.LOCAL):
            storage_class = 'local'
            self.advance()
        elif self.expect(TokenType.HEAP):
            storage_class = 'heap'
            self.advance()
        elif self.expect(TokenType.STACK):
            storage_class = 'stack'
            self.advance()
        elif self.expect(TokenType.REGISTER):
            storage_class = 'register'
            self.advance()
        
        # Parse qualifiers AFTER storage class (const, volatile)
        if self.expect(TokenType.CONST):
            is_const = True
            self.advance()
        
        if self.expect(TokenType.VOLATILE):
            is_volatile = True
            self.advance()
        
        # If we have storage class OR qualifiers, it MUST be a variable declaration or function
        if storage_class or is_const or is_volatile:
            if self.expect(TokenType.ASM):
                return self.asm_statement(is_volatile=is_volatile)
            elif self.expect(TokenType.DEF):
                return self.function_def()
            else:
                # It's a variable declaration - consume it
                var_decl = self.variable_declaration()
                self.consume(TokenType.SEMICOLON)
                return var_decl
        
        # No storage class or qualifiers - check for other statement types
        if self.expect(TokenType.USING):
            return self.using_statement()
        elif self.expect(TokenType.DEF):
            return self.function_def()
        elif self.expect(TokenType.UNION):
            return self.union_def()
        elif self.expect(TokenType.STRUCT):
            return self.struct_def()
        elif self.expect(TokenType.OBJECT):
            return self.object_def()
        elif self.expect(TokenType.NAMESPACE):
            return self.namespace_def()
        elif self.expect(TokenType.IF):
            return self.if_statement()
        elif self.expect(TokenType.DO):
            return self.do_while_statement()
        elif self.expect(TokenType.WHILE):
            return self.while_statement()
        elif self.expect(TokenType.FOR):
            return self.for_statement()
        elif self.expect(TokenType.SWITCH):
            return self.switch_statement()
        elif self.expect(TokenType.TRY):
            return self.try_statement()
        elif self.expect(TokenType.RETURN):
            return self.return_statement()
        elif self.expect(TokenType.BREAK):
            return self.break_statement()
        elif self.expect(TokenType.CONTINUE):
            return self.continue_statement()
        elif self.expect(TokenType.THROW):
            return self.throw_statement()
        elif self.expect(TokenType.ASSERT):
            return self.assert_statement()
        elif self.expect(TokenType.LEFT_BRACE):
            return self.block_statement()
        elif self.is_variable_declaration():
            return self.variable_declaration_statement()
        elif self.expect(TokenType.UNSIGNED):
            return self.variable_declaration_statement()
        elif self.expect(TokenType.SIGNED):
            return self.variable_declaration_statement()
        elif self.expect(TokenType.INT, TokenType.DATA, TokenType.CHAR, 
                         TokenType.FLOAT_KW, TokenType.BOOL_KW, TokenType.VOID):
            return self.variable_declaration_statement()
        elif self.expect(TokenType.SEMICOLON):
            self.advance()
            return None
        elif self.expect(TokenType.AUTO) and self.peek() and self.peek().type == TokenType.LEFT_BRACE:
            # Handle destructuring assignment
            destructure = self.destructuring_assignment()
            self.consume(TokenType.SEMICOLON)
            return destructure
        elif self.expect(TokenType.ASM):
            return self.asm_statement()
        else:
            return self.expression_statement()
    
    def using_statement(self) -> UsingStatement:
        """
        using_statement -> 'using' namespace_path (',' namespace_path)* ';'
        namespace_path -> IDENTIFIER ('::' IDENTIFIER)*
        """
        self.consume(TokenType.USING)
        
        # Parse namespace path (e.g., "standard::io")
        namespace_path = self.consume(TokenType.IDENTIFIER).value
        while self.expect(TokenType.SCOPE):  # ::
            self.advance()
            namespace_path += "::" + self.consume(TokenType.IDENTIFIER).value
        
        # For now, handle only single namespace per statement
        # TODO: Add support for comma-separated namespaces
        self.consume(TokenType.SEMICOLON)
        return UsingStatement(namespace_path)
    
    def function_def(self) -> Union[FunctionDef]:
        """
        function_def -> ('const')? ('volatile')? 'def' IDENTIFIER '(' parameter_list? ')' '->' type_spec ';'
        function_def -> ('const')? ('volatile')? 'def' IDENTIFIER '(' parameter_list? ')' '->' type_spec block ';'
        """
        is_const = False
        is_volatile = False
        
        if self.expect(TokenType.CONST):
            is_const = True
            self.advance()
        
        if self.expect(TokenType.VOLATILE):
            is_volatile = True
            self.advance()
        
        self.consume(TokenType.DEF)
        name = self.consume(TokenType.IDENTIFIER).value
        
        # This is a function definition
        self.consume(TokenType.LEFT_PAREN)
        parameters = self.parameter_list() if not self.expect(TokenType.RIGHT_PAREN) else []
        self.consume(TokenType.RIGHT_PAREN)
        
        self.consume(TokenType.RETURN_ARROW)
        return_type = self.type_spec()
        
        # Check if this is a prototype (ends with semicolon) or definition (has block)
        is_prototype = False
        body = None
        if self.expect(TokenType.SEMICOLON):
            is_prototype = True
            self.advance()
            body = Block([])  # Empty block for prototype
        else:
            body = self.block()
            self.consume(TokenType.SEMICOLON)
        
        return FunctionDef(name, parameters, return_type, body, is_const, is_volatile, is_prototype)
    
    def parameter_list(self) -> List[Parameter]:
        """
        parameter_list -> parameter (',' parameter)*
        """
        params = [self.parameter()]
        
        while self.expect(TokenType.COMMA):
            self.advance()
            params.append(self.parameter())
        
        return params
    
    def parameter(self) -> Parameter:
        """
        parameter -> type_spec IDENTIFIER
        """
        type_spec = self.type_spec()
        name = self.consume(TokenType.IDENTIFIER).value
        return Parameter(name, type_spec)

    def union_def(self) -> UnionDefStatement:
        """
        union_def -> 'union' IDENTIFIER (';' | '{' union_member* '}' ';')
        """
        self.consume(TokenType.UNION)
        name = self.consume(TokenType.IDENTIFIER).value
        
        # Handle forward declaration
        if self.expect(TokenType.SEMICOLON):
            self.advance()
            return UnionDefStatement(UnionDef(name, []))
        
        self.consume(TokenType.LEFT_BRACE)
        members = []
        
        while not self.expect(TokenType.RIGHT_BRACE):
            members.append(self.union_member())
        
        self.consume(TokenType.RIGHT_BRACE)
        self.consume(TokenType.SEMICOLON)
        return UnionDefStatement(UnionDef(name, members))

    def union_member(self) -> UnionMember:
        """
        union_member -> type_spec IDENTIFIER ('=' expression)? ';'
        """
        type_spec = self.type_spec()
        name = self.consume(TokenType.IDENTIFIER).value
        
        # Optional initial value
        initial_value = None
        if self.expect(TokenType.ASSIGN):
            self.advance()
            initial_value = self.expression()
        
        self.consume(TokenType.SEMICOLON)
        return UnionMember(name, type_spec, initial_value)
    
    def struct_def(self) -> StructDef:
        """
        struct_def -> 'struct' IDENTIFIER'{' struct_member* '}'
        """
        self.consume(TokenType.STRUCT)
        name = self.consume(TokenType.IDENTIFIER).value
        
        base_structs = []
        members = []
        nested_structs = []

        # Handle forward declarations
        if self.expect(TokenType.SEMICOLON):
            self.advance()
            return StructDef(name, members, base_structs, nested_structs)

        self.consume(TokenType.LEFT_BRACE)
        
        while not self.expect(TokenType.RIGHT_BRACE):
            if self.expect(TokenType.PUBLIC):
                self.advance()
                self.consume(TokenType.LEFT_BRACE)
                while not self.expect(TokenType.RIGHT_BRACE):
                    if self.expect(TokenType.STRUCT):
                        nested_struct = self.struct_def()
                        nested_structs.append(nested_struct)
                        self.consume(TokenType.SEMICOLON)
                    else:
                        member = self.struct_member()
                        if isinstance(member, list):
                            for m in member:
                                m.is_private = False
                                members.append(m)
                        else:
                            member.is_private = False
                            members.append(member)
                self.consume(TokenType.RIGHT_BRACE)
                self.consume(TokenType.SEMICOLON)
            elif self.expect(TokenType.PRIVATE):
                self.advance()
                self.consume(TokenType.LEFT_BRACE)
                while not self.expect(TokenType.RIGHT_BRACE):
                    if self.expect(TokenType.STRUCT):
                        nested_struct = self.struct_def()
                        nested_structs.append(nested_struct)
                        self.consume(TokenType.SEMICOLON)
                    else:
                        member = self.struct_member()
                        if isinstance(member, list):
                            for m in member:
                                m.is_private = True
                                members.append(m)
                        else:
                            member.is_private = True
                            members.append(member)
                self.consume(TokenType.RIGHT_BRACE)
                self.consume(TokenType.SEMICOLON)
            elif self.expect(TokenType.STRUCT):
                # Handle nested struct
                nested_struct = self.struct_def()
                nested_structs.append(nested_struct)
                # Allow both with and without semicolon for nested structs
                self.expect(TokenType.SEMICOLON)
            else:
                member = self.struct_member()
                if isinstance(member, list):
                    members.extend(member)
                else:
                    members.append(member)
        
        self.consume(TokenType.RIGHT_BRACE)
        self.expect(TokenType.SEMICOLON)
        self.advance()
        return StructDef(name, members, base_structs, nested_structs)
    
    def struct_member(self) -> Union[StructMember, List[StructMember]]:
        """
        struct_member -> type_spec IDENTIFIER (',' IDENTIFIER)* ';'
        """
        type_spec = self.type_spec()
        name = self.consume(TokenType.IDENTIFIER).value
        members = [name]

        # Handle comma-separated variable names
        while self.expect(TokenType.COMMA):
            self.advance()
            members.append(self.consume(TokenType.IDENTIFIER).value)
        
        # Handle optional initial value (only applies to last variable)
        initial_value = None
        if self.expect(TokenType.ASSIGN):
            self.advance()
            initial_value = self.expression()
        
        self.consume(TokenType.SEMICOLON)
        
        # If multiple members, return a list
        if len(members) > 1:
            result = []
            for i, member_name in enumerate(members):
                # Only the last member can have an initial value
                member_initial_value = initial_value if i == len(members) - 1 else None
                result.append(StructMember(member_name, type_spec, member_initial_value))
            return result
        else:
            return StructMember(members[0], type_spec, initial_value)
    
    def object_def(self) -> ObjectDef:
        """
        object_def -> 'object' IDENTIFIER '{' object_body '}'
        object_body -> (object_member | access_specifier)*
        """
        self.consume(TokenType.OBJECT)
        name = self.consume(TokenType.IDENTIFIER).value

        
        # Parse inheritance -- TODO, impelment after we have v1 Flux base
        #base_objects = []
        #if self.expect(TokenType.COLON):
        #    self.advance()
        #    base_objects.append(self.consume(TokenType.IDENTIFIER).value)
        #    while self.expect(TokenType.COMMA):
        #        self.advance()
        #        base_objects.append(self.consume(TokenType.IDENTIFIER).value)
        
        methods = []
        members = []
        nested_objects = []
        nested_structs = []

        if self.expect(TokenType.SEMICOLON):
            is_prototype = True
            self.advance()
            return ObjectDef(name, methods, members, nested_objects, nested_structs)

        self.consume(TokenType.LEFT_BRACE)
        
        while not self.expect(TokenType.RIGHT_BRACE):
            if self.expect(TokenType.PUBLIC, TokenType.PRIVATE):
                is_private = self.current_token.type == TokenType.PRIVATE
                self.advance()
                self.consume(TokenType.LEFT_BRACE)
                
                while not self.expect(TokenType.RIGHT_BRACE):
                    if self.expect(TokenType.DEF):
                        method = self.function_def()
                        method.is_private = is_private
                        methods.append(method)
                    elif self.expect(TokenType.OBJECT):
                        nested_obj = self.object_def()
                        nested_obj.is_private = is_private
                        nested_objects.append(nested_obj)
                        self.consume(TokenType.SEMICOLON)
                    elif self.expect(TokenType.STRUCT):
                        nested_struct = self.struct_def()
                        nested_struct.is_private = is_private
                        nested_structs.append(nested_struct)
                        self.consume(TokenType.SEMICOLON)
                    else:
                        # Field declaration
                        var = self.variable_declaration()
                        self.consume(TokenType.SEMICOLON)
                        member = StructMember(var.name, var.type_spec, var.initial_value, is_private)
                        members.append(member)
                
                self.consume(TokenType.RIGHT_BRACE)
                self.consume(TokenType.SEMICOLON)
            else:
                # Regular member (defaults to public)
                if self.expect(TokenType.DEF):
                    method = self.function_def()
                    methods.append(method)
                elif self.expect(TokenType.OBJECT):
                    nested_obj = self.object_def()
                    nested_objects.append(nested_obj)
                    self.consume(TokenType.SEMICOLON)
                elif self.expect(TokenType.STRUCT):
                    nested_struct = self.struct_def()
                    nested_structs.append(nested_struct)
                    self.consume(TokenType.SEMICOLON)
                else:
                    # Field declaration
                    var = self.variable_declaration()
                    self.consume(TokenType.SEMICOLON)
                    member = StructMember(var.name, var.type_spec, var.initial_value, False)
                    members.append(member)
        
        self.consume(TokenType.RIGHT_BRACE)
        self.consume(TokenType.SEMICOLON)
        return ObjectDef(name, methods, members, nested_objects, nested_structs)
    
    def namespace_def(self) -> NamespaceDef:
        """
        namespace_def -> 'namespace' IDENTIFIER  '{' namespace_body* '}'
        """
        self.consume(TokenType.NAMESPACE)
        namespace_parts = [self.consume(TokenType.IDENTIFIER).value]
        while self.expect(TokenType.SCOPE):
            self.consume(TokenType.SCOPE)
            namespace_parts.append(self.consume(TokenType.IDENTIFIER).value)
        name = '__'.join(namespace_parts)
        
        # INHERITANCE - TODO after v1 Flux
        base_namespaces = []
        
        functions = []
        structs = []
        objects = []
        variables = []
        nested_namespaces = []
        
        if self.expect(TokenType.SEMICOLON):
            self.advance()
            return NamespaceDef(name, functions, structs, objects, variables, nested_namespaces, base_namespaces)
        
        self.consume(TokenType.LEFT_BRACE)
        
        while not self.expect(TokenType.RIGHT_BRACE):
            # Check for storage class keywords FIRST
            if self.expect(TokenType.GLOBAL, TokenType.LOCAL, TokenType.HEAP, 
                           TokenType.STACK, TokenType.REGISTER,
                           TokenType.CONST, TokenType.VOLATILE):
                var_decl = self.variable_declaration()
                variables.append(var_decl)
                self.consume(TokenType.SEMICOLON)
            elif self.expect(TokenType.DEF):
                functions.append(self.function_def())
            elif self.expect(TokenType.STRUCT):
                structs.append(self.struct_def())
            elif self.expect(TokenType.OBJECT):
                objects.append(self.object_def())
            elif self.expect(TokenType.NAMESPACE):
                nested_ns = self.namespace_def()
                # MERGE NESTED NAMESPACES WITH SAME NAME
                merged = False
                for existing_ns in nested_namespaces:
                    if existing_ns.name == nested_ns.name:
                        # Merge content into existing namespace
                        existing_ns.functions.extend(nested_ns.functions)
                        existing_ns.structs.extend(nested_ns.structs)
                        existing_ns.objects.extend(nested_ns.objects)
                        existing_ns.variables.extend(nested_ns.variables)
                        existing_ns.nested_namespaces.extend(nested_ns.nested_namespaces)
                        existing_ns.base_namespaces.extend(nested_ns.base_namespaces)
                        merged = True
                        break
                if not merged:
                    nested_namespaces.append(nested_ns)
            elif self.expect(TokenType.IF):
                if_stmt = self.if_statement()
                pass
            elif self.is_variable_declaration():
                var_decl = self.variable_declaration()
                variables.append(var_decl)
                self.consume(TokenType.SEMICOLON)
            else:
                self.error("Expected function, struct, object, namespace, if or def, or variable declaration")
        
        self.consume(TokenType.RIGHT_BRACE)
        self.consume(TokenType.SEMICOLON)
        return NamespaceDef(name, functions, structs, objects, variables, nested_namespaces, base_namespaces)
    
    def type_spec(self) -> TypeSpec:
        """
        type_spec -> ('global'|'local'|'heap'|'stack'|'register')? ('const')? ('volatile')? ('signed'|'unsigned')? base_type alignment? array_spec? pointer_spec?
        array_spec -> ('[' expression? ']')+
        
        NOTE: Storage class can come FIRST, before qualifiers
        """
        is_const = False
        is_volatile = False
        is_signed = True
        storage_class = None

        # Parse storage class FIRST (before qualifiers)
        if self.expect(TokenType.GLOBAL):
            storage_class = StorageClass.GLOBAL
            self.advance()
        elif self.expect(TokenType.LOCAL):
            storage_class = StorageClass.LOCAL
            self.advance()
        elif self.expect(TokenType.HEAP):
            storage_class = StorageClass.HEAP
            self.advance()
        elif self.expect(TokenType.STACK):
            storage_class = StorageClass.STACK
            self.advance()
        elif self.expect(TokenType.REGISTER):
            storage_class = StorageClass.REGISTER
            self.advance()

        # Parse qualifiers AFTER storage class
        if self.expect(TokenType.CONST):
            is_const = True
            self.advance()
        
        if self.expect(TokenType.VOLATILE):
            is_volatile = True
            self.advance()
        
        if self.expect(TokenType.SIGNED):
            is_signed = True
            self.advance()
        elif self.expect(TokenType.UNSIGNED):
            is_signed = False
            self.advance()
        
        # Base type parsing
        base_type_result = self.base_type()
        custom_typename = None
        
        # Handle custom type names
        if isinstance(base_type_result, list):
            base_type = base_type_result[0]
            custom_typename = base_type_result[1]
        else:
            base_type = base_type_result
        
        # Bit width and alignment for data types
        bit_width = None
        alignment = None
        
        if base_type == DataType.DATA and custom_typename is None:
            if self.expect(TokenType.LEFT_BRACE):
                self.advance()
                bit_width = int(self.consume(TokenType.INTEGER).value)
                
                if self.expect(TokenType.COLON):
                    self.advance()
                    alignment = int(self.consume(TokenType.INTEGER).value)
                else:
                    alignment = bit_width
                
                self.consume(TokenType.RIGHT_BRACE)
        
        # Array specification - support multiple dimensions
        array_dims = []
        
        while self.expect(TokenType.LEFT_BRACKET):
            self.advance()
            if not self.expect(TokenType.RIGHT_BRACKET):
                if self.expect(TokenType.INTEGER):
                    array_size = int(self.current_token.value)
                    array_dims.append(array_size)
                    self.advance()
                else:
                    expr = self.expression()
                    array_dims.append(expr)
            else:
                array_dims.append(None)
            self.consume(TokenType.RIGHT_BRACKET)
        
        is_array = len(array_dims) > 0
        array_size = array_dims[0] if array_dims else None
        array_dimensions = array_dims if array_dims else None
        
        # Pointer specification - support multiple levels
        pointer_depth = 0
        while self.expect(TokenType.MULTIPLY):
            pointer_depth += 1
            self.advance()

        return TypeSpec(
            base_type=base_type,
            is_signed=is_signed,
            is_const=is_const,
            is_volatile=is_volatile,
            bit_width=bit_width,
            alignment=alignment,
            is_array=is_array,
            array_size=array_size,
            array_dimensions=array_dimensions,
            is_pointer=pointer_depth > 0,
            pointer_depth=pointer_depth,
            custom_typename=custom_typename,
            storage_class=storage_class
        )
    
    def base_type(self) -> Union[DataType, List]:
        """
        base_type -> 'int' | 'float' | 'char' | 'bool' | 'data' | 'void' | IDENTIFIER
        Returns DataType for built-in types, or [DataType.DATA, typename] for custom types
        """
        # ADD {}* function pointer support
        # URGENT
        if self.expect(TokenType.INT):
            if self.expect(TokenType.FUNCTION_POINTER):
                # Do function_pointer_declaration() returns FunctionPointer <- Add to AST
                print(self.current_token.type)
            self.advance()
            return DataType.INT
        elif self.expect(TokenType.FLOAT_KW):
            self.advance()
            return DataType.FLOAT
        elif self.expect(TokenType.CHAR):
            self.advance()
            return DataType.CHAR
        elif self.expect(TokenType.BOOL_KW):
            self.advance()
            return DataType.BOOL
        elif self.expect(TokenType.DATA):
            self.advance()
            return DataType.DATA
        elif self.expect(TokenType.VOID):
            self.advance()
            return DataType.VOID
        elif self.expect(TokenType.THIS):
            self.advance()
            return DataType.THIS
        elif self.expect(TokenType.OBJECT):
            self.error("Objects cannot be used as types in struct members.")
        elif self.expect(TokenType.IDENTIFIER):
            # Custom type - return [DataType.DATA, typename]
            custom_typename = self.current_token.value
            self.advance()
            return [DataType.DATA, custom_typename]
        else:
            self.error("Expected type specifier")
    
    def is_variable_declaration(self) -> bool:
        """Check if current position starts a variable declaration"""
        saved_pos = self.position
        try:
            # Skip type specifiers
            if self.expect(TokenType.CONST):
                self.advance()
            if self.expect(TokenType.VOLATILE):
                self.advance()
            if self.expect(TokenType.SIGNED, TokenType.UNSIGNED):
                self.advance()
            
            # Must have a base type
            if not self.expect(TokenType.INT, TokenType.FLOAT_KW, TokenType.CHAR, 
                             TokenType.BOOL_KW, TokenType.DATA, TokenType.VOID, 
                             TokenType.IDENTIFIER):
                return False
            
            self.advance()
            
            # Skip data type specification
            if self.expect(TokenType.LEFT_BRACE):
                self.advance()
                if self.expect(TokenType.INTEGER):
                    self.advance()
                if self.expect(TokenType.COLON):
                    self.advance()
                    if self.expect(TokenType.INTEGER):
                        self.advance()
                if self.expect(TokenType.RIGHT_BRACE):
                    self.advance()
            
            # Skip array specification - support multiple dimensions
            while self.expect(TokenType.LEFT_BRACKET):
                self.advance()
                if self.expect(TokenType.INTEGER):
                    self.advance()
                if self.expect(TokenType.RIGHT_BRACKET):
                    self.advance()
            
            # Skip pointer
            if self.expect(TokenType.MULTIPLY):
                self.advance()
            
            # Check for 'as' followed by void - this is a void cast, not a type declaration
            if self.expect(TokenType.AS):
                self.advance()
                if self.expect(TokenType.VOID):
                    return False  # This is "x as void" - a void cast expression, not a type declaration
                return self.expect(TokenType.IDENTIFIER)  # Type declaration like "int as myint"
            
            # Must have identifier for regular variable declaration
            # After identifier, we can have: =, ;, (, {, or [
            if not self.expect(TokenType.IDENTIFIER):
                return False
            
            self.advance()  # consume the variable name
            
            # Valid next tokens after variable name
            return self.expect(TokenType.ASSIGN, TokenType.SEMICOLON, 
                             TokenType.LEFT_PAREN, TokenType.LEFT_BRACE,
                             TokenType.COMMA, TokenType.LEFT_BRACKET)
        finally:
            self.position = saved_pos
            self.current_token = self.tokens[self.position] if self.position < len(self.tokens) else None
    
    def variable_declaration_statement(self) -> Statement:
        """
        variable_declaration_statement -> variable_declaration ';'
        """
        decl = self.variable_declaration()
        self.consume(TokenType.SEMICOLON)
        return decl
    
    def variable_declaration(self) -> Union[VariableDeclaration, TypeDeclaration]:
        """
        variable_declaration -> type_spec IDENTIFIER ('=' expression)?
                             | type_spec 'as' IDENTIFIER ('=' expression)?
                             | type_spec IDENTIFIER '{' struct_init '}'  # Struct literal init
        
        Note: Array dimensions must be part of type_spec, not after IDENTIFIER
        """
        type_spec = self.type_spec()

        # Check if this is a type declaration (using 'as')
        if self.expect(TokenType.AS):
            self.advance()
            type_name = self.consume(TokenType.IDENTIFIER).value
            
            # Optional initial value
            initial_value = None
            if self.expect(TokenType.ASSIGN):
                self.advance()
                initial_value = self.expression()
                
                # If the initial value is a struct literal, infer the type from the variable's type_spec
                if isinstance(initial_value, StructLiteral) and initial_value.struct_type is None:
                    if type_spec.custom_typename:
                        initial_value.struct_type = type_spec.custom_typename
                    else:
                        self.error("Struct literal initialization requires a custom type")
            
            return TypeDeclaration(type_name, type_spec, initial_value)
        else:
            # Regular variable declaration
            name = self.consume(TokenType.IDENTIFIER).value
            
            # Check for array dimensions AFTER the identifier (C-style: int arr[4])
            # This extends the type_spec that was already parsed
            if self.expect(TokenType.LEFT_BRACKET):
                array_dims = []
                while self.expect(TokenType.LEFT_BRACKET):
                    self.advance()
                    if not self.expect(TokenType.RIGHT_BRACKET):
                        try:
                            array_size = int(self.consume(TokenType.INTEGER).value)
                            array_dims.append(array_size)
                        except:
                            expr = self.expression()
                            array_dims.append(expr)
                    else:
                        array_dims.append(None)
                    self.consume(TokenType.RIGHT_BRACKET)
                
                # Update type_spec with array information
                type_spec.is_array = True
                type_spec.array_size = array_dims[0] if array_dims else None
                type_spec.array_dimensions = array_dims if array_dims else None
            
            # Check for struct literal initialization: StructName var {fields}
            if self.expect(TokenType.LEFT_BRACE):
                # This is struct literal initialization without explicit cast
                struct_literal = self.struct_literal()
                
                # Get struct name from type_spec
                if type_spec.custom_typename:
                    struct_name = type_spec.custom_typename
                else:
                    self.error("Struct initialization requires a custom type name")
                
                # Set the struct type on the literal (inferred from declaration)
                struct_literal.struct_type = struct_name
                
                # Create StructInstance with the literal's field values
                var_decl = VariableDeclaration(name, type_spec, struct_literal)
                # Mark as global if storage_class is GLOBAL
                if type_spec.storage_class == StorageClass.GLOBAL:
                    var_decl.is_global = True
                return var_decl
            
            # Check for object instantiation: identifier(args)
            if self.expect(TokenType.LEFT_PAREN):
                # Object instantiation syntax: Type identifier(args)
                self.advance()  # consume '('
                args = []
                if not self.expect(TokenType.RIGHT_PAREN):
                    args = self.argument_list()
                self.consume(TokenType.RIGHT_PAREN)
                
                # Create a function call to the constructor as the initial value
                if type_spec.custom_typename:
                    constructor_name = f"{type_spec.custom_typename}.__init"
                else:
                    constructor_name = type_spec.base_type.value + "__init"
                
                constructor_call = FunctionCall(constructor_name, args)
                var_decl = VariableDeclaration(name, type_spec, constructor_call)
                # Mark as global if storage_class is GLOBAL
                if type_spec.storage_class == StorageClass.GLOBAL:
                    var_decl.is_global = True
                return var_decl
            
            # Handle comma-separated variables
            names = [name]
            while self.expect(TokenType.COMMA):
                self.advance()
                names.append(self.consume(TokenType.IDENTIFIER).value)
            
            # Optional initial value (only for last variable)
            initial_value = None
            if self.expect(TokenType.ASSIGN):
                self.advance()
                initial_value = self.expression()
            
            # Create variable declaration
            var_decl = VariableDeclaration(names[0], type_spec, initial_value)
            
            # Mark as global if storage_class is GLOBAL
            if type_spec.storage_class == StorageClass.GLOBAL:
                var_decl.is_global = True
            
            return var_decl
    
    def block_statement(self) -> Block:
        """
        block_statement -> block
        """
        return self.block()
    
    def block(self) -> Block:
        """
        block -> '{' statement* '}'
        """
        self.consume(TokenType.LEFT_BRACE)
        statements = []
        
        while not self.expect(TokenType.RIGHT_BRACE):
            stmt = self.statement()
            if stmt:
                statements.append(stmt)
        
        self.consume(TokenType.RIGHT_BRACE)
        return Block(statements)

    def asm_statement(self, is_volatile: bool = False) -> ExpressionStatement:
        """
        asm_statement -> ('volatile')? 'asm' ASM_BLOCK (':' operand_list)? (':' operand_list)? (':' clobber_list)? ';'
        """
        # Check for volatile keyword if not already passed in
        if not is_volatile and self.expect(TokenType.VOLATILE):
            is_volatile = True
            self.advance()
        
        self.consume(TokenType.ASM)
        
        # Get the ASM block content
        asm_block_token = self.consume(TokenType.ASM_BLOCK)
        asm_body = asm_block_token.value
        
        # Parse optional output operands (first colon)
        output_operands = ""
        if self.expect(TokenType.COLON):
            self.advance()
            output_operands = self.parse_operand_list()
        
        # Parse optional input operands (second colon)
        input_operands = ""
        if self.expect(TokenType.COLON):
            self.advance()
            input_operands = self.parse_operand_list()
        
        # Parse optional clobber list (third colon)
        clobber_list = ""
        if self.expect(TokenType.COLON):
            self.advance()
            clobber_list = self.parse_clobber_list()
        
        self.consume(TokenType.SEMICOLON)
        
        # Construct constraints string for LLVM
        # The full LLVM inline asm syntax is: asm "code" : outputs : inputs : clobbers
        constraints = ""
        if output_operands or input_operands or clobber_list:
            # Build full constraint string with all parts
            constraint_parts = []
            
            # Add output operands
            if output_operands:
                constraint_parts.append(output_operands)
            else:
                constraint_parts.append("")  # Empty output section
            
            # Add input operands if any inputs or clobbers exist
            if input_operands or clobber_list:
                if input_operands:
                    constraint_parts.append(input_operands)
                else:
                    constraint_parts.append("")  # Empty input section
            
            # Add clobber list if it exists
            if clobber_list:
                constraint_parts.append(clobber_list)
            
            # Join with colons for LLVM format
            constraints = ":".join(constraint_parts)
        
        return ExpressionStatement(InlineAsm(
            body=asm_body,
            is_volatile=is_volatile,
            constraints=constraints
        ))
    
    def parse_operand_list(self) -> str:
        """
        Parse operand list like: "=r" (variable), "m" (memory)
        """
        operands = []
        
        # Handle empty operand list
        if self.expect(TokenType.COLON, TokenType.SEMICOLON):
            return ""
        
        while not self.expect(TokenType.COLON, TokenType.SEMICOLON):
            # Parse constraint string
            if self.expect(TokenType.STRING_LITERAL):
                constraint = self.current_token.value
                self.advance()
                
                # Parse operand expression in parentheses
                if self.expect(TokenType.LEFT_PAREN):
                    self.advance()
                    # For now, just consume until closing paren
                    operand_expr = ""
                    paren_depth = 1
                    while paren_depth > 0 and not self.expect(TokenType.EOF):
                        if self.expect(TokenType.LEFT_PAREN):
                            paren_depth += 1
                        elif self.expect(TokenType.RIGHT_PAREN):
                            paren_depth -= 1
                        
                        if paren_depth > 0:
                            operand_expr += self.current_token.value
                        self.advance()
                    
                    operands.append(f'"{constraint}"({operand_expr})')
                
                # Handle comma separation
                if self.expect(TokenType.COMMA):
                    self.advance()
            else:
                # Skip unexpected tokens
                self.advance()
        
        return ",".join(operands)
    
    def parse_clobber_list(self) -> str:
        """
        Parse clobber list like: "rax", "rcx", "memory"
        """
        clobbers = []
        
        # Handle empty clobber list
        if self.expect(TokenType.SEMICOLON):
            return ""
        
        while not self.expect(TokenType.SEMICOLON):
            if self.expect(TokenType.STRING_LITERAL):
                clobbers.append(f'"{self.current_token.value}"')
                self.advance()
                
                if self.expect(TokenType.COMMA):
                    self.advance()
            else:
                # Skip unexpected tokens
                self.advance()
        
        return ",".join(clobbers)
    
    def if_statement(self) -> IfStatement:
        """
        if_statement -> 'if' '(' expression ')' block ('elif' '(' expression ')' block)* ('else' block)? ';'
        """
        self.consume(TokenType.IF)
        self.consume(TokenType.LEFT_PAREN)
        condition = self.expression()
        self.consume(TokenType.RIGHT_PAREN)
        then_block = self.block()
        
        elif_blocks = []
        while self.expect(TokenType.ELIF):
            self.advance()
            self.consume(TokenType.LEFT_PAREN)
            elif_condition = self.expression()
            self.consume(TokenType.RIGHT_PAREN)
            elif_block = self.block()
            elif_blocks.append((elif_condition, elif_block))
        
        else_block = None
        if self.expect(TokenType.ELSE):
            self.advance()
            else_block = self.block()
        
        self.consume(TokenType.SEMICOLON)
        return IfStatement(condition, then_block, elif_blocks, else_block)
    
    def while_statement(self) -> WhileLoop:
        """
        while_statement -> 'while' '(' expression ')' block ';'
        """
        self.consume(TokenType.WHILE)
        self.consume(TokenType.LEFT_PAREN)
        condition = self.expression()
        self.consume(TokenType.RIGHT_PAREN)
        body = self.block()
        self.consume(TokenType.SEMICOLON)
        return WhileLoop(condition, body)
    
    def do_while_statement(self) -> Union[DoLoop, DoWhileLoop]:
        """
        do_while_statement -> 'do' block ('while' '(' expression ')' ';' | ';')
        
        Supports both:
            do { ... };              # Plain do loop (executes once)
            do { ... } while (cond); # Do-while loop (repeats while condition is true)
        """
        self.consume(TokenType.DO)
        body = self.block()
        
        # Check if this is a do-while or plain do
        if self.expect(TokenType.WHILE):
            # Do-while loop
            self.advance()
            self.consume(TokenType.LEFT_PAREN)
            condition = self.expression()
            self.consume(TokenType.RIGHT_PAREN)
            self.consume(TokenType.SEMICOLON)
            return DoWhileLoop(body, condition)
        elif self.expect(TokenType.SEMICOLON):
            # Plain do loop
            self.advance()
            return DoLoop(body)
        else:
            self.error("Expected 'while' or ';' after do block")
    
    def for_statement(self) -> Union[ForLoop, ForInLoop]:
        """
        for_statement -> 'for' '(' (for_in_loop | for_c_loop) ')' block ';'
        """
        self.consume(TokenType.FOR)
        self.consume(TokenType.LEFT_PAREN)
        
        # Check if it's a for-in loop by looking ahead
        saved_pos = self.position
        is_for_in = False
        
        # Look for pattern: identifier (',' identifier)* 'in' expression
        if self.expect(TokenType.IDENTIFIER):
            self.advance()
            while self.expect(TokenType.COMMA):
                self.advance()
                if self.expect(TokenType.IDENTIFIER):
                    self.advance()
                else:
                    break
            if self.expect(TokenType.IN):
                is_for_in = True
        
        # Restore position
        self.position = saved_pos
        self.current_token = self.tokens[self.position]
        
        if is_for_in:
            # for-in loop
            variables = []
            variables.append(self.consume(TokenType.IDENTIFIER).value)
            
            while self.expect(TokenType.COMMA):
                self.advance()
                variables.append(self.consume(TokenType.IDENTIFIER).value)
            
            self.consume(TokenType.IN)
            iterable = self.expression()
            self.consume(TokenType.RIGHT_PAREN)
            body = self.block()
            self.consume(TokenType.SEMICOLON)
            
            return ForInLoop(variables, iterable, body)
        else:
            # C-style for loop
            init = None
            if not self.expect(TokenType.SEMICOLON):
                if self.is_variable_declaration():
                    init = self.variable_declaration()  # Don't wrap in ExpressionStatement
                else:
                    init = ExpressionStatement(self.expression())
            self.consume(TokenType.SEMICOLON)
            
            condition = None
            if not self.expect(TokenType.SEMICOLON):
                condition = self.expression()
            self.consume(TokenType.SEMICOLON)
            
            update = None
            if not self.expect(TokenType.RIGHT_PAREN):
                update = ExpressionStatement(self.expression())
            
            self.consume(TokenType.RIGHT_PAREN)
            body = self.block()
            self.consume(TokenType.SEMICOLON)
            
            return ForLoop(init, condition, update, body)
    
    def switch_statement(self) -> SwitchStatement:
        """
        switch_statement -> 'switch' '(' expression ')' '{' switch_case* '}' ';'
        """
        self.consume(TokenType.SWITCH)
        self.consume(TokenType.LEFT_PAREN)
        expression = self.expression()
        self.consume(TokenType.RIGHT_PAREN)
        self.consume(TokenType.LEFT_BRACE)
        
        cases = []
        while not self.expect(TokenType.RIGHT_BRACE):
            case = self.switch_case()
            cases.append(case)
        
        self.consume(TokenType.RIGHT_BRACE)
        self.consume(TokenType.SEMICOLON)
        return SwitchStatement(expression, cases)
    
    def switch_case(self) -> Case:
        """
        switch_case -> ('case' '(' expression ')' | 'default' '{' statement* '}' ';') block
        """
        value = None
        if self.expect(TokenType.CASE):
            self.advance()
            self.consume(TokenType.LEFT_PAREN)
            value = self.expression()
            self.consume(TokenType.RIGHT_PAREN)
            body = self.block()
        elif self.expect(TokenType.DEFAULT):
            self.advance()
            body = self.block()
            self.consume(TokenType.SEMICOLON)
            value = None
        else:
            self.error("Expected 'case' or 'default'")
        return Case(value, body)
    
    def try_statement(self) -> TryBlock:
        """
        try_statement -> 'try' block catch_block+ ';'
        """
        self.consume(TokenType.TRY)
        try_body = self.block()
        
        catch_blocks = []
        while self.expect(TokenType.CATCH):
            self.advance()
            self.consume(TokenType.LEFT_PAREN)
            
            # Handle empty catch blocks (catch-all)
            if self.expect(TokenType.RIGHT_PAREN):
                self.advance()
                catch_body = self.block()
                catch_blocks.append((None, None, catch_body))
            else:
                # Exception type and name
                if self.expect(TokenType.AUTO):
                    self.advance()
                    exception_type = None
                    exception_name = self.consume(TokenType.IDENTIFIER).value
                else:
                    exception_type = self.type_spec()
                    exception_name = self.consume(TokenType.IDENTIFIER).value
                
                self.consume(TokenType.RIGHT_PAREN)
                catch_body = self.block()
                catch_blocks.append((exception_type, exception_name, catch_body))
        
        self.consume(TokenType.SEMICOLON)
        return TryBlock(try_body, catch_blocks)
    
    def return_statement(self) -> ReturnStatement:
        """
        return_statement -> 'return' expression? ';'
        """
        self.consume(TokenType.RETURN)
        value = None
        if not self.expect(TokenType.SEMICOLON):
            value = self.expression()
        self.consume(TokenType.SEMICOLON)
        return ReturnStatement(value)
    
    def break_statement(self) -> BreakStatement:
        """
        break_statement -> 'break' ';'
        """
        self.consume(TokenType.BREAK)
        self.consume(TokenType.SEMICOLON)
        return BreakStatement()
    
    def continue_statement(self) -> ContinueStatement:
        """
        continue_statement -> 'continue' ';'
        """
        self.consume(TokenType.CONTINUE)
        self.consume(TokenType.SEMICOLON)
        return ContinueStatement()

    def throw_statement(self) -> ThrowStatement:
        """
        throw_statement -> 'throw' '(' expression ')' ';'
        """
        self.consume(TokenType.THROW)
        self.consume(TokenType.LEFT_PAREN)
        expression = self.expression()
        self.consume(TokenType.RIGHT_PAREN)
        self.consume(TokenType.SEMICOLON)
        return ThrowStatement(expression)
    
    def assert_statement(self) -> AssertStatement:
        """
        assert_statement -> 'assert' '(' expression (',' CHAR)? ')' ';'
        """
        self.consume(TokenType.ASSERT)
        self.consume(TokenType.LEFT_PAREN)
        condition = self.expression()
        
        message = None
        if self.expect(TokenType.COMMA):
            self.advance()
            message = self.consume(TokenType.STRING_LITERAL).value
        
        self.consume(TokenType.RIGHT_PAREN)
        self.consume(TokenType.SEMICOLON)
        return AssertStatement(condition, message)
    
    def expression_statement(self) -> ExpressionStatement:
        """
        expression_statement -> expression ';'
        """
        expr = self.expression()
        self.consume(TokenType.SEMICOLON)
        return ExpressionStatement(expr)
    
    def expression(self) -> Expression:
        """
        expression -> assignment_expression
        """
        return self.assignment_expression()
    
    def assignment_expression(self) -> Expression:
        """
        assignment_expression -> logical_or_expression (('=' | '+=' | '-=' | '*=' | '/=' | '%=') assignment_expression)?
        
        Now handles struct field assignment:
            struct_instance.field = value
        """
        expr = self.logical_or_expression()
        
        if self.expect(TokenType.ASSIGN):
            self.advance()
            value = self.assignment_expression()
            
            # Check if this is struct field assignment
            if isinstance(expr, MemberAccess):
                # This could be struct field assignment or object member assignment
                # The codegen will determine based on type
                # For now, use Assignment and let codegen handle it
                return Assignment(expr, value)
            else:
                return Assignment(expr, value)
        # NOTE: MUST ADD BITWISE ASSIGNMENTS
        elif self.expect(TokenType.PLUS_ASSIGN, TokenType.MINUS_ASSIGN, TokenType.MULTIPLY_ASSIGN, 
                         TokenType.DIVIDE_ASSIGN, TokenType.MODULO_ASSIGN, TokenType.POWER_ASSIGN,
                         TokenType.XOR_ASSIGN, TokenType.BITSHIFT_LEFT_ASSIGN, TokenType.BITSHIFT_RIGHT_ASSIGN):
            # Handle compound assignments
            op_token = self.current_token.type
            self.advance()
            value = self.assignment_expression()
            return CompoundAssignment(expr, op_token, value)
        
        return expr
    
    def logical_or_expression(self) -> Expression:
        """
        logical_or_expression -> logical_and_expression ('or' logical_and_expression)*
        """
        expr = self.logical_and_expression()
        
        while self.expect(TokenType.LOGICAL_OR):
            operator = Operator.OR
            self.advance()
            right = self.logical_and_expression()
            expr = BinaryOp(expr, operator, right)
        
        return expr
    
    def logical_and_expression(self) -> Expression:
        """
        logical_and_expression -> bitwise_or_expression ('and' bitwise_or_expression)*
        """
        expr = self.bitwise_or_expression()
        
        while self.expect(TokenType.LOGICAL_AND):
            operator = Operator.AND
            self.advance()
            right = self.bitwise_or_expression()
            expr = BinaryOp(expr, operator, right)
        
        return expr

    def logical_xor_expression(self) -> Expression:
        """
        logical_xor_expression -> bitwise_or_expression ('xor' bitwise_or_expression)*
        """
        expr = self.bitwise_or_expression()

        while self.expect(TokenType.XOR_OP):
            operator = Operator.XOR
            self.advance()
            right = self.bitwise_or_expression()
            expr = BinaryOp(expr, operator, right)

        return expr
    
    def equality_expression(self) -> Expression:
        """
        equality_expression -> relational_expression (('==' | '!=') relational_expression)*
        """
        expr = self.relational_expression()
        
        while self.expect(TokenType.EQUAL, TokenType.NOT_EQUAL):
            if self.current_token.type == TokenType.EQUAL:
                operator = Operator.EQUAL
            elif self.current_token.type == TokenType.NOT_EQUAL:
                operator = Operator.NOT_EQUAL
            
            self.advance()
            right = self.relational_expression()
            expr = BinaryOp(expr, operator, right)
        
        return expr

    def bitwise_or_expression(self) -> Expression:
        """
        bitwise_or_expression -> bitwise_xor_expression ('|' bitwise_xor_expression)*
        """
        expr = self.bitwise_xor_expression()
        
        while self.expect(TokenType.BITOR_OP):
            operator = Operator.BITOR
            self.advance()
            right = self.bitwise_xor_expression()
            expr = BinaryOp(expr, operator, right)
        
        return expr

    def bitwise_xor_expression(self) -> Expression:
        """
        bitwise_xor_expression -> bitwise_and_expression ('^' bitwise_and_expression)*
        """
        expr = self.bitwise_and_expression()
        
        while self.expect(TokenType.XOR):
            operator = Operator.XOR
            self.advance()
            right = self.bitwise_and_expression()
            expr = BinaryOp(expr, operator, right)
        
        return expr

    def bitwise_and_expression(self) -> Expression:
        """
        bitwise_and_expression -> equality_expression ('&' equality_expression)*
        """
        expr = self.equality_expression()
        
        while self.expect(TokenType.BITAND_OP):
            operator = Operator.BITAND
            self.advance()
            right = self.equality_expression()
            expr = BinaryOp(expr, operator, right)
        
        return expr
    
    def relational_expression(self) -> Expression:
        """
        relational_expression -> shift_expression (('<' | '<=' | '>' | '>=') shift_expression)*
        """
        expr = self.shift_expression()
        
        while self.expect(TokenType.LESS_THAN, TokenType.LESS_EQUAL, TokenType.GREATER_THAN, TokenType.GREATER_EQUAL):
            if self.current_token.type == TokenType.LESS_THAN:
                operator = Operator.LESS_THAN
            elif self.current_token.type == TokenType.LESS_EQUAL:
                operator = Operator.LESS_EQUAL
            elif self.current_token.type == TokenType.GREATER_THAN:
                operator = Operator.GREATER_THAN
            else:  # GREATER_EQUAL
                operator = Operator.GREATER_EQUAL
            
            self.advance()
            right = self.shift_expression()
            expr = BinaryOp(expr, operator, right)
        
        return expr
    
    def shift_expression(self) -> Expression:
        """
        shift_expression -> additive_expression (('<<' | '>>') additive_expression)*
        """
        expr = self.additive_expression()
        
        while self.expect(TokenType.BITSHIFT_LEFT, TokenType.BITSHIFT_RIGHT):
            if self.current_token.type == TokenType.BITSHIFT_LEFT:
                operator = Operator.BITSHIFT_LEFT
            else:  # RIGHT_SHIFT
                operator = Operator.BITSHIFT_RIGHT
            
            self.advance()
            right = self.additive_expression()
            expr = BinaryOp(expr, operator, right)
        
        return expr
    
    def additive_expression(self) -> Expression:
        """
        additive_expression -> range_expression
        """
        return self.range_expression()
    
    def range_expression(self) -> Expression:
        """
        range_expression -> arithmetic_expression ('..' arithmetic_expression)?
        """
        expr = self.arithmetic_expression()
        
        if self.expect(TokenType.RANGE):  # ..
            self.advance()
            end_expr = self.arithmetic_expression()
            return RangeExpression(expr, end_expr)
        
        return expr
    
    def arithmetic_expression(self) -> Expression:
        """
        arithmetic_expression -> multiplicative_expression (('+' | '-') multiplicative_expression)*
        """
        expr = self.multiplicative_expression()
        
        while self.expect(TokenType.PLUS, TokenType.MINUS):
            if self.current_token.type == TokenType.PLUS:
                operator = Operator.ADD
            else:  # MINUS
                operator = Operator.SUB
            
            self.advance()
            right = self.multiplicative_expression()
            expr = BinaryOp(expr, operator, right)
        
        return expr
    
    def multiplicative_expression(self) -> Expression:
        """
        multiplicative_expression -> cast_expression (('*' | '/' | '%' | '^') cast_expression)*
        """
        expr = self.cast_expression()
        
        while self.expect(TokenType.MULTIPLY, TokenType.DIVIDE, TokenType.MODULO, TokenType.POWER):
            if self.current_token.type == TokenType.MULTIPLY:
                operator = Operator.MUL
            elif self.current_token.type == TokenType.DIVIDE:
                operator = Operator.DIV
            elif self.current_token.type == TokenType.MODULO:
                operator = Operator.MOD
            else:
                operator = Operator.POWER

            
            self.advance()
            right = self.cast_expression()
            expr = BinaryOp(expr, operator, right)
        
        return expr
    
    def cast_expression(self) -> Expression:
        """
        cast_expression -> ('(' type_spec ')')? unary_expression
        
        Handles:
        - (Type)expr -> CastExpression (for ALL types - struct or primitive)
        - expr (no cast)
        """
        if self.expect(TokenType.LEFT_PAREN):
            # Look ahead to see if this is a cast
            saved_pos = self.position
            try:
                self.advance()  # consume '('
                target_type = self.type_spec()
                if self.expect(TokenType.RIGHT_PAREN):
                    self.advance()  # consume ')'
                    expr = self.unary_expression()
                    
                    # ALWAYS use CastExpression - let codegen figure out if it's a struct
                    return CastExpression(target_type, expr)
                else:
                    # Not a cast, restore position
                    self.position = saved_pos
                    self.current_token = self.tokens[self.position]
            except:
                # Not a cast, restore position
                self.position = saved_pos
                self.current_token = self.tokens[self.position]
        
        return self.unary_expression()
    
    def unary_expression(self) -> Expression:
        """
        unary_expression -> ('not' | '-' | '+' | '*' | '@' | '++' | '--') unary_expression
                         | postfix_expression
        """
        if self.expect(TokenType.NOT):
            operator = Operator.NOT
            self.advance()
            operand = self.unary_expression()
            return UnaryOp(operator, operand)
        elif self.expect(TokenType.MINUS):
            operator = Operator.SUB
            self.advance()
            operand = self.unary_expression()
            return UnaryOp(operator, operand)
        elif self.expect(TokenType.PLUS):
            operator = Operator.ADD
            self.advance()
            operand = self.unary_expression()
            return UnaryOp(operator, operand)
        elif self.expect(TokenType.MULTIPLY):
            # Pointer dereference - this handles *x, **x, ***x, etc.
            self.advance()
            operand = self.unary_expression()
            return PointerDeref(operand)
        elif self.expect(TokenType.ADDRESS_OF):
            # Address-of operator
            self.advance()
            operand = self.unary_expression()
            return AddressOf(operand)
        elif self.expect(TokenType.INCREMENT):
            # Prefix increment
            self.advance()
            operand = self.unary_expression()
            return UnaryOp(Operator.INCREMENT, operand)
        elif self.expect(TokenType.DECREMENT):
            # Prefix decrement
            self.advance()
            operand = self.unary_expression()
            return UnaryOp(Operator.DECREMENT, operand)
        else:
            return self.postfix_expression()
    
    def postfix_expression(self) -> Expression:
        """
        postfix_expression -> primary_expression (postfix_operator)*
        postfix_operator -> '[' expression ']'
                         | '(' argument_list? ')'
                         | '.' IDENTIFIER        # Field access for structs
                         | '->' IDENTIFIER
                         | '++'
                         | '--'
        """
        expr = self.primary_expression()
        
        while True:
            if self.expect(TokenType.LEFT_BRACKET):
                # Array access
                self.advance()
                index = self.expression()
                self.consume(TokenType.RIGHT_BRACKET)
                expr = ArrayAccess(expr, index)
            elif self.expect(TokenType.LEFT_PAREN):
                # Function call
                self.advance()
                args = []
                if not self.expect(TokenType.RIGHT_PAREN):
                    args = self.argument_list()
                self.consume(TokenType.RIGHT_PAREN)
                if isinstance(expr, Identifier):
                    expr = FunctionCall(expr.name, args)
                elif isinstance(expr, MemberAccess):
                    # Method call: obj.method() -> call obj_type.method with obj as first arg
                    method_name = f"{{obj_type}}.{expr.member}"
                    expr = MethodCall(expr.object, expr.member, args)
                else:
                    raise SyntaxError(f"Cannot call function on complex expression: {type(expr).__name__}")
            elif self.expect(TokenType.DOT):
                # Member access - could be struct field or object method/member
                self.advance()
                member = self.consume(TokenType.IDENTIFIER).value
                
                # Create MemberAccess node - codegen will determine if it's
                # StructFieldAccess or object member based on type
                expr = MemberAccess(expr, member)
            elif self.expect(TokenType.INCREMENT):
                # Postfix increment
                self.advance()
                expr = UnaryOp(Operator.INCREMENT, expr, is_postfix=True)
            elif self.expect(TokenType.DECREMENT):
                # Postfix decrement
                self.advance()
                expr = UnaryOp(Operator.DECREMENT, expr, is_postfix=True)
            elif self.expect(TokenType.AS):
                # AS cast expression (postfix) - support all type casts
                self.advance()
                target_type = self.type_spec()
                
                # Check if this is a struct cast
                if target_type.custom_typename:
                    expr = StructRecast(target_type.custom_typename, expr)
                else:
                    expr = CastExpression(target_type, expr)
            else:
                break
        
        return expr
    
    def argument_list(self) -> List[Expression]:
        """
        argument_list -> expression (',' expression)*
        """
        args = [self.expression()]
        
        while self.expect(TokenType.COMMA):
            self.advance()
            args.append(self.expression())
        
        return args

    def parse_f_string(self, f_string_content: str) -> FStringLiteral:
        """Parse f-string into parts without evaluating anything"""
        parts = []
        i = 0
        n = len(f_string_content)
        
        while i < n:
            if f_string_content[i] == '{' and i + 1 < n and f_string_content[i + 1] == '{':
                # Escaped {{
                parts.append('{')
                i += 2
            elif f_string_content[i] == '}' and i + 1 < n and f_string_content[i + 1] == '}':
                # Escaped }}
                parts.append('}')
                i += 2
            elif f_string_content[i] == '{':
                # Start of embedded expression - parse but don't evaluate
                expr_start = i + 1
                expr_end = f_string_content.find('}', expr_start)
                if expr_end == -1:
                    self.error("Unclosed expression in f-string")
                
                # Extract expression text
                expr_text = f_string_content[expr_start:expr_end]
                
                # Parse the expression normally (but don't evaluate it)
                from flexer import FluxLexer
                lexer = FluxLexer(expr_text)
                tokens = lexer.tokenize()
                expr_parser = FluxParser(tokens)
                expression = expr_parser.expression()
                
                parts.append(expression)
                i = expr_end + 1
            else:
                # Regular character - accumulate into current string part
                if not parts or not isinstance(parts[-1], str):
                    parts.append(f_string_content[i])
                else:
                    parts[-1] += f_string_content[i]
                i += 1
        
        return FStringLiteral(parts)
    
    def primary_expression(self) -> Expression:
        """
        primary_expression -> IDENTIFIER
                           | INTEGER
                           | FLOAT
                           | CHAR
                           | STRING_LITERAL
                           | 'true'
                           | 'false'
                           | 'void'
                           | 'this'
                           | 'super'
                           | '(' expression ')'
                           | array_literal
                           | struct_literal  # Returns StructLiteral, not old Literal
        """
        if self.expect(TokenType.IDENTIFIER):
            return self.scoped_identifier()
        elif self.expect(TokenType.INTEGER):
            value = int(self.current_token.value, 0)
            self.advance()
            return Literal(value, DataType.INT)
        elif self.expect(TokenType.FLOAT):
            value = float(self.current_token.value)
            self.advance()
            return Literal(value, DataType.FLOAT)
        elif self.expect(TokenType.CHAR):
            value = self.current_token.value
            self.advance()
            return Literal(value, DataType.CHAR)
        elif self.expect(TokenType.STRING_LITERAL):
            value = self.current_token.value
            self.advance()
            return StringLiteral(value)
        elif self.expect(TokenType.F_STRING):
            f_string_content = self.current_token.value
            self.advance()
            return self.parse_f_string(f_string_content)
        elif self.expect(TokenType.I_STRING):
            print("GOT I-STRING")
            return
        elif self.expect(TokenType.TRUE):
            self.advance()
            return Literal(True, DataType.BOOL)
        elif self.expect(TokenType.FALSE):
            self.advance()
            return Literal(False, DataType.BOOL)
        elif self.expect(TokenType.VOID):
            self.advance()
            return Literal(None, DataType.VOID)
        elif self.expect(TokenType.THIS):
            self.advance()
            return Identifier("this")
        elif self.expect(TokenType.SUPER):
            self.advance()
            return Identifier("super")
        elif self.expect(TokenType.LEFT_PAREN):
            self.advance()
            expr = self.expression()
            self.consume(TokenType.RIGHT_PAREN)
            return expr
        elif self.expect(TokenType.LEFT_BRACKET):
            return self.array_literal()
        elif self.expect(TokenType.LEFT_BRACE):
            # Parse struct literal - returns StructLiteral node
            return self.struct_literal()
        elif self.expect(TokenType.SIZEOF):
            return self.sizeof_expression()
        elif self.expect(TokenType.ALIGNOF):
            return self.alignof_expression()
        else:
            self.error(f"Unexpected token: {self.current_token.type.name if self.current_token else 'EOF'}")

    def scoped_identifier(self) -> Expression:
        """
        scoped_identifier -> IDENTIFIER ('::' IDENTIFIER)*
        
        Handles:
        - Simple identifier: x
        - Scoped identifier: namespace::x
        - Nested scope: namespace::subnamespace::x
        - Type member: Type::static_member
        """
        parts = [self.consume(TokenType.IDENTIFIER).value]
        
        while self.expect(TokenType.SCOPE):
            self.advance()
            parts.append(self.consume(TokenType.IDENTIFIER).value)
        
        # If we have multiple parts, it's a scoped identifier
        if len(parts) > 1:
            # Join with :: to create the full scoped name
            full_name = "__".join(parts)
            return Identifier(full_name)
        else:
            # Single identifier
            return Identifier(parts[0])

    def alignof_expression(self) -> AlignOf:
        """
        alignof_expression -> 'alignof' '(' (type_spec | expression) ')'
        """
        self.consume(TokenType.ALIGNOF)
        self.consume(TokenType.LEFT_PAREN)
        
        # Look ahead to determine if it's a type or expression
        saved_pos = self.position
        try:
            # Try to parse as type spec first
            target = self.type_spec()
            self.consume(TokenType.RIGHT_PAREN)
            return AlignOf(target)
        except ParseError:
            # If type parsing fails, try as expression
            self.position = saved_pos
            self.current_token = self.tokens[self.position]
            expr = self.expression()
            self.consume(TokenType.RIGHT_PAREN)
            return AlignOf(expr)

    def sizeof_expression(self) -> SizeOf:
        """
        sizeof_expression -> 'sizeof' '(' (type_spec | expression) ')'
        """
        self.consume(TokenType.SIZEOF)
        self.consume(TokenType.LEFT_PAREN)
        
        # Look ahead to determine if it's a type or expression
        saved_pos = self.position
        
        # Check if it starts with a known type keyword
        if self.expect(TokenType.INT, TokenType.FLOAT_KW, TokenType.CHAR, 
                      TokenType.BOOL_KW, TokenType.DATA, TokenType.VOID,
                      TokenType.CONST, TokenType.VOLATILE, TokenType.SIGNED, TokenType.UNSIGNED):
            # Definitely a type, parse as type_spec
            try:
                target = self.type_spec()
                self.consume(TokenType.RIGHT_PAREN)
                return SizeOf(target)
            except ParseError:
                # If type parsing fails, try as expression
                self.position = saved_pos
                self.current_token = self.tokens[self.position]
                expr = self.expression()
                self.consume(TokenType.RIGHT_PAREN)
                return SizeOf(expr)
        else:
            # Could be identifier (variable) or custom type - try expression first
            try:
                expr = self.expression()
                self.consume(TokenType.RIGHT_PAREN)
                return SizeOf(expr)
            except ParseError:
                # If expression parsing fails, try as type spec
                self.position = saved_pos
                self.current_token = self.tokens[self.position]
                target = self.type_spec()
                self.consume(TokenType.RIGHT_PAREN)
                return SizeOf(target)

    def array_literal(self) -> Expression:
        """
        array_literal -> '[' (array_comprehension | expression (',' expression)*)? ']'
        array_comprehension -> expression 'for' '(' type_spec IDENTIFIER 'in' expression ')'
        """
        self.consume(TokenType.LEFT_BRACKET)
        
        if self.expect(TokenType.RIGHT_BRACKET):
            self.advance()
            return ArrayLiteral([])  # Empty array literal
        
        # Parse first expression
        first_expr = self.expression()
        
        # Check if this is an array comprehension
        if self.expect(TokenType.FOR):
            # This is an array comprehension: [expr for (type var in iterable)]
            self.advance()  # consume 'for'
            self.consume(TokenType.LEFT_PAREN)
            
            # Parse variable type and name
            variable_type = self.type_spec()
            variable_name = self.consume(TokenType.IDENTIFIER).value
            
            self.consume(TokenType.IN)
            
            # Parse iterable expression
            iterable = self.expression()
            
            self.consume(TokenType.RIGHT_PAREN)
            self.consume(TokenType.RIGHT_BRACKET)
            
            return ArrayComprehension(
                expression=first_expr,
                variable=variable_name,
                variable_type=variable_type,
                iterable=iterable
            )
        else:
            # Regular array literal: [expr, expr, ...]
            elements = [first_expr]
            
            while self.expect(TokenType.COMMA):
                self.advance()
                elements.append(self.expression())
            
            self.consume(TokenType.RIGHT_BRACKET)
            return ArrayLiteral(elements)  # Array literal
    
    def struct_literal(self) -> StructLiteral:
        """
        struct_literal -> '{' (named_init | positional_init)? '}'
        named_init -> IDENTIFIER '=' expression (',' IDENTIFIER '=' expression)*
        positional_init -> expression (',' expression)*
        
        Returns StructLiteral AST node.
        Supports both:
            {a = 10, b = 20}  // Named fields
            {10, 20}          // Positional (field order from struct definition)
        """
        self.consume(TokenType.LEFT_BRACE)
        field_values = {}
        positional_values = []
        is_positional = False
        
        if not self.expect(TokenType.RIGHT_BRACE):
            # Look ahead to determine if this is named or positional
            # If we see IDENTIFIER followed by '=', it's named
            # Otherwise, it's positional
            if self.expect(TokenType.IDENTIFIER) and self.peek() and self.peek().type == TokenType.ASSIGN:
                # Named initialization
                is_positional = False
                name = self.consume(TokenType.IDENTIFIER).value
                self.consume(TokenType.ASSIGN)
                value = self.expression()
                field_values[name] = value
                
                while self.expect(TokenType.COMMA):
                    self.advance()
                    name = self.consume(TokenType.IDENTIFIER).value
                    self.consume(TokenType.ASSIGN)
                    value = self.expression()
                    field_values[name] = value
            else:
                # Positional initialization
                is_positional = True
                value = self.expression()
                positional_values.append(value)
                
                while self.expect(TokenType.COMMA):
                    self.advance()
                    value = self.expression()
                    positional_values.append(value)
        
        self.consume(TokenType.RIGHT_BRACE)
        
        # Return StructLiteral with either named or positional values
        if is_positional:
            return StructLiteral(field_values={}, positional_values=positional_values)
        else:
            return StructLiteral(field_values=field_values, positional_values=[])

    def struct_body_item(self):
            if self.expect(TokenType.PUBLIC):
                self.advance()
                self.consume(TokenType.LEFT_BRACE)
                while not self.expect(TokenType.RIGHT_BRACE):
                    self.parse_object_body_item(methods, members, nested_objects, nested_structs, is_private=False)
                self.consume(TokenType.RIGHT_BRACE)
                self.consume(TokenType.SEMICOLON)
            elif self.expect(TokenType.PRIVATE):
                self.advance()
                self.consume(TokenType.LEFT_BRACE)
                while not self.expect(TokenType.RIGHT_BRACE):
                    self.parse_object_body_item(methods, members, nested_objects, nested_structs, is_private=True)
                self.consume(TokenType.RIGHT_BRACE)
                self.consume(TokenType.SEMICOLON)

    def destructuring_assignment(self) -> DestructuringAssignment:
        """
        destructuring_assignment -> 'auto' '{' destructure_vars '}' '=' expression ('from' IDENTIFIER)?
        """
        self.consume(TokenType.AUTO)
        self.consume(TokenType.LEFT_BRACE)
        
        # Parse variables in destructuring pattern
        variables = []
        while not self.expect(TokenType.RIGHT_BRACE):
            if self.expect(TokenType.IDENTIFIER):
                name = self.consume(TokenType.IDENTIFIER).value
                if self.expect(TokenType.AS):
                    self.advance()
                    type_spec = self.type_spec()
                    variables.append((name, type_spec))
                else:
                    variables.append(name)
            
            if not self.expect(TokenType.RIGHT_BRACE):
                self.consume(TokenType.COMMA)
        
        self.consume(TokenType.RIGHT_BRACE)
        self.consume(TokenType.ASSIGN)
        source = self.expression()
        
        # Optional 'from' clause
        source_type = None
        if self.expect(TokenType.FROM):
            self.advance()
            source_type = Identifier(self.consume(TokenType.IDENTIFIER).value)
        
        is_explicit = any(isinstance(var, tuple) for var in variables)
        return DestructuringAssignment(variables, source, source_type, is_explicit)

# Add main function for testing
def main():
    """Main function for testing the parser"""
    if len(sys.argv) < 2:
        print("Usage: python3 parser3.py <file.fx> [-v] [-a]")
        sys.exit(1)
    
    filename = sys.argv[1]
    verbose = "-v" in sys.argv
    show_ast = "-a" in sys.argv
    
    try:
        with open(filename, 'r') as f:
            source = f.read()
        
        # Tokenize
        lexer = FluxLexer(source)
        tokens = lexer.tokenize()
        
        if verbose:
            print("Tokens:")
            for token in tokens:
                print(f"  {token}")
            print()
        
        # Parse
        parser = FluxParser(tokens)
        ast = parser.parse()
        
        if show_ast:
            print("AST:")
            print(ast)
        else:
            print("Parse successful!")
            print(f"Generated AST with {len(ast.statements)} top-level statements")
    
    except FileNotFoundError:
        print(f"Error: File '{filename}' not found")
        sys.exit(1)
    except ParseError as e:
        print(f"Parse error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()