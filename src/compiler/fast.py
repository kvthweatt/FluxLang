#!/usr/bin/env python3
"""
Flux Abstract Syntax Tree

Copyright (C) 2026 Karac Thweatt

Contributors:

    Piotr Bednarski
"""

from dataclasses import dataclass, field
from typing import List, Any, Optional, Union, Dict, Tuple, ClassVar
from enum import Enum
from llvmlite import ir
from pathlib import Path
import os, sys

from ftypesys import *

# Base classes first
@dataclass
class ASTNode:
    """Base class for all AST nodes"""
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> Any:
        raise NotImplementedError(f"codegen not implemented for {self.__class__.__name__}")

# Literal values (no dependencies)
@dataclass
class Literal(ASTNode):
    value: Any
    type: DataType

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        #print(f"[DEBUG Literal.codegen] value={self.value}, type={self.type}")
        if self.type in (DataType.SINT, DataType.UINT):
            llvm_type = TypeSystem.get_llvm_type(self.type, module, self.value)
            normalized_val = LiteralTypeHandler.normalize_int_value(self.value, self.type, llvm_type.width)
            llvm_val = ir.Constant(llvm_type, normalized_val)
            return TypeSystem.attach_type_metadata(llvm_val, self.type)
        elif self.type == DataType.FLOAT:
            llvm_type = TypeSystem.get_llvm_type(self.type, module, self.value)
            return ir.Constant(llvm_type, float(self.value))
        elif self.type == DataType.BOOL:
            llvm_type = TypeSystem.get_llvm_type(self.type, module, self.value)
            return ir.Constant(llvm_type, bool(self.value))
        elif self.type == DataType.CHAR:
            llvm_type = TypeSystem.get_llvm_type(self.type, module, self.value)
            char_val = LiteralTypeHandler.normalize_char_value(self.value)
            return ir.Constant(llvm_type, char_val)
        elif self.type == DataType.VOID:
            llvm_type = TypeSystem.get_llvm_type(self.type, module, self.value)
            return ir.Constant(llvm_type, 0)
        elif self.type == DataType.DATA:
            # Handle array literals
            if isinstance(self.value, list):
                # For now, just return None for array literals - they should be handled at a higher level
                return None
            # Handle struct literals (dictionaries with field names -> values)
            elif isinstance(self.value, dict):
                return self._handle_struct_literal(builder, module)
            # Handle other DATA types using LiteralTypeHandler
            llvm_type = TypeSystem.get_llvm_type(self.type, module, self.value)
            if isinstance(llvm_type, ir.IntType):
                return ir.Constant(llvm_type, int(self.value) if isinstance(self.value, str) else self.value)
            elif isinstance(llvm_type, ir.FloatType):
                return ir.Constant(llvm_type, float(self.value))
            raise ValueError(f"Unsupported DATA literal: {self.value}")
        else:
            # Handle custom types using LiteralTypeHandler
            llvm_type = TypeSystem.get_llvm_type(self.type, module, self.value)
            if isinstance(llvm_type, ir.IntType):
                return ir.Constant(llvm_type, int(self.value) if isinstance(self.value, str) else self.value)
            elif isinstance(llvm_type, ir.FloatType):
                return ir.Constant(llvm_type, float(self.value))
            raise ValueError(f"Unsupported literal type: {self.type}")

    def _handle_struct_literal(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Handle struct literal initialization (e.g., {a = 10, b = 20})"""
        if not isinstance(self.value, dict):
            raise ValueError("Expected dictionary for struct literal")
        
        # Resolve struct type using LiteralTypeHandler
        struct_type = LiteralTypeHandler.resolve_struct_type(self.value, module)

        if module.symbol_table.is_global_scope():
            # Global context - create a struct constant
            field_values = []
            for member_name in struct_type.names:
                if member_name in self.value:
                    # Field is initialized in the literal
                    field_expr = self.value[member_name]
                    field_index = struct_type.names.index(member_name)
                    expected_type = struct_type.elements[field_index]
                    
                    # Handle string literals for pointer types (like noopstr which is i8*)
                    if (isinstance(field_expr, Literal) and 
                        field_expr.type == DataType.CHAR and
                        LiteralTypeHandler.is_string_pointer_field(expected_type)):
                        # Create a global string constant
                        string_val = field_expr.value
                        string_bytes = string_val.encode('ascii')
                        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
                        str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
                        
                        # Create global variable for the string
                        gv = ir.GlobalVariable(module, str_val.type, 
                                              name=f".str.struct_init_{member_name}")
                        gv.linkage = 'internal'
                        gv.global_constant = True
                        gv.initializer = str_val
                        
                        # Get pointer to first character
                        zero = ir.Constant(ir.IntType(32), 0)
                        str_ptr = gv.gep([zero, zero])
                        field_values.append(str_ptr)
                    else:
                        # Normal field initialization
                        field_value = field_expr.codegen(builder, module)
                        field_values.append(field_value)
                else:
                    # Field not specified, use zero initialization
                    field_type = LiteralTypeHandler.get_struct_field_type(struct_type, member_name)
                    field_values.append(ir.Constant(field_type, 0))
            
            # Create struct constant
            return ir.Constant(struct_type, field_values)
        else:
            # Local context - create an alloca and initialize fields
            struct_ptr = builder.alloca(struct_type, name="struct_literal")
            
            # Initialize each field
            for field_name, field_value_expr in self.value.items():
                # Get field type using LiteralTypeHandler
                expected_type = LiteralTypeHandler.get_struct_field_type(struct_type, field_name)
                
                field_index = struct_type.names.index(field_name)
                
                # Get pointer to the field
                field_ptr = builder.gep(
                    struct_ptr,
                    [ir.Constant(ir.IntType(32), 0),
                     ir.Constant(ir.IntType(32), field_index)],
                    inbounds=True
                )
                
                # Get the expected field type
                expected_type = struct_type.elements[field_index]
                
                # Handle string literals for pointer types (like noopstr which is i8*)
                if (isinstance(field_value_expr, Literal) and 
                    field_value_expr.type == DataType.CHAR and
                    LiteralTypeHandler.is_string_pointer_field(expected_type)):
                    # Create a global string constant for local initialization too
                    string_val = field_value_expr.value
                    string_bytes = string_val.encode('ascii')
                    str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
                    str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
                    
                    # Create global variable for the string
                    gv = ir.GlobalVariable(module, str_val.type, 
                                          name=f".str.local_struct_init_{field_name}")
                    gv.linkage = 'internal'
                    gv.global_constant = True
                    gv.initializer = str_val
                    
                    # Get pointer to first character
                    zero = ir.Constant(ir.IntType(32), 0)
                    str_ptr = builder.gep(gv, [zero, zero], name=f"{field_name}_str_ptr")
                    field_value = str_ptr
                else:
                    # Generate value normally
                    field_value = field_value_expr.codegen(builder, module)
                    
                    # Convert field value to match the expected type if needed
                    if field_value.type != expected_type:
                        if isinstance(field_value.type, ir.IntType) and isinstance(expected_type, ir.IntType):
                            if field_value.type.width > expected_type.width:
                                field_value = builder.trunc(field_value, expected_type)
                            elif field_value.type.width < expected_type.width:
                                field_value = builder.sext(field_value, expected_type)
                        elif isinstance(field_value.type, ir.IntType) and isinstance(expected_type, ir.FloatType):
                            field_value = builder.sitofp(field_value, expected_type)
                        elif isinstance(field_value.type, ir.FloatType) and isinstance(expected_type, ir.IntType):
                            field_value = builder.fptosi(field_value, expected_type)
                
                builder.store(field_value, field_ptr)
            
            # Return the initialized struct (load it to get the value)
            return builder.load(struct_ptr, name="struct_value")

# Expressions (built up from simple to complex)
@dataclass
class Expression(ASTNode):
    pass

@dataclass
class Identifier(Expression):
    name: str

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        #print(f"[IDENTIFIER] Looking up '{self.name}'", file=sys.stderr)
        #print(f"[IDENTIFIER]   Scope level: {module.symbol_table.scope_level}", file=sys.stderr)
        #print(f"[IDENTIFIER]   Scopes count: {len(module.symbol_table.scopes)}", file=sys.stderr)
        
        # Look up the name in the current scope
        if not module.symbol_table.is_global_scope() and module.symbol_table.get_llvm_value(self.name) is not None:
            ptr = module.symbol_table.get_llvm_value(self.name)
            
            # Get type information if available
            type_spec = TypeResolver.resolve_type_spec(self.name, module)
            #print("TYPE SPEC FROM TYPE RESOLVER:",type_spec)

            # Check validity (use after tie)
            IdentifierTypeHandler.check_validity(self.name, builder)

            # Handle special case for 'this' pointer
            if self.name == "this":
                return TypeSystem.attach_type_metadata(ptr, type_spec)

            # For arrays and structs, return the pointer directly (don't load)
            if IdentifierTypeHandler.should_return_pointer(ptr, type_spec):
                return TypeSystem.attach_type_metadata(ptr, type_spec)
            
            # Load the value if it's a non-array, non-struct pointer type
            elif isinstance(ptr.type, ir.PointerType):
                ret_val = builder.load(ptr, name=self.name)
                if IdentifierTypeHandler.is_volatile(self.name, builder):
                    ret_val.volatile = True
                # Attach type metadata to loaded value from multiple sources
                if not hasattr(ret_val, '_flux_type_spec'):
                    # Priority 1: Check scope_type_info
                    if type_spec:
                        ret_val._flux_type_spec = type_spec
                    # Priority 2: Check if alloca itself has metadata
                    elif hasattr(ptr, '_flux_type_spec'):
                        ret_val._flux_type_spec = ptr._flux_type_spec
                return ret_val
            
            # For non-pointer types, attach metadata and return
            return TypeSystem.attach_type_metadata(ptr, type_spec)
        
        # Check for global variables
        if self.name in module.globals:
            gvar = module.globals[self.name]
            type_spec = module.symbol_table.get_type_spec(self.name)
            
            # For arrays and structs, return the pointer directly (don't load)
            if IdentifierTypeHandler.should_return_pointer(gvar, type_spec):
                return TypeSystem.attach_type_metadata(gvar, type_spec)
            
            # Load the value if it's a non-array, non-struct pointer type
            elif isinstance(gvar.type, ir.PointerType):
                ret_val = builder.load(gvar, name=self.name)
                if IdentifierTypeHandler.is_volatile(self.name, builder):
                    ret_val.volatile = True
                return TypeSystem.attach_type_metadata(ret_val, type_spec)
            return TypeSystem.attach_type_metadata(gvar, type_spec)
        
        # Check if this is a custom type
        if IdentifierTypeHandler.is_type_alias(self.name, module):
            return module._type_aliases[self.name]
        
        # Check for namespace-qualified names using 'using' statements
        mangled_name = IdentifierTypeHandler.resolve_namespace_mangled_name(self.name, module)
        if mangled_name:
            # Check in global variables with mangled name
            if mangled_name in module.globals:
                gvar = module.globals[mangled_name]
                type_spec = module.symbol_table.get_type_spec(mangled_name)
                # For arrays and structs, return the pointer directly (don't load)
                if IdentifierTypeHandler.should_return_pointer(gvar, type_spec):
                    return TypeSystem.attach_type_metadata(gvar, type_spec)
                # Load the value if it's a non-array, non-struct pointer type
                elif isinstance(gvar.type, ir.PointerType):
                    ret_val = builder.load(gvar, name=self.name)
                    if IdentifierTypeHandler.is_volatile(self.name, builder):
                        ret_val.volatile = True
                    return TypeSystem.attach_type_metadata(ret_val, type_spec)
                
                return TypeSystem.attach_type_metadata(gvar, type_spec)
            
            # Check in type aliases with mangled name
            if IdentifierTypeHandler.is_type_alias(mangled_name, module):
                return module._type_aliases[mangled_name]
            
        raise NameError(f"Unknown identifier: {self.name}")

@dataclass
class ArrayLiteral(Expression):
    """
    Centralized class for all array literal operations.
    
    Handles:
    - String literals (char arrays)
    - Array literals like [1, 2, 3]
    - Array concatenation
    - Array slicing
    - Memory operations (memcpy, memset)
    - Array information and type checking
    - Compile-time vs runtime array creation
    """
    elements: List[Expression] = field(default_factory=list)
    element_type: Optional[TypeSystem] = None
    is_string: bool = False
    string_value: Optional[str] = None
    storage_class: Optional[StorageClass] = None
    
    # Class-level counter for unique names
    _string_counter: ClassVar[int] = 0
    
    def __post_init__(self):
        """Initialize array literal properties."""
        # Handle string literal conversion
        if not self.is_string and self.elements:
            # Check if all elements are char literals
            all_chars = all(
                isinstance(elem, Literal) and elem.type == DataType.CHAR 
                for elem in self.elements
            )
            if all_chars:
                self.is_string = True
                # Build string from char literals
                chars = []
                for elem in self.elements:
                    if isinstance(elem.value, str):
                        chars.append(elem.value)
                    else:
                        chars.append(chr(elem.value))
                self.string_value = ''.join(chars)
    
    @staticmethod
    def from_string(string_value: str, storage_class: Optional[StorageClass] = None) -> 'ArrayLiteral':
        """
        Create an ArrayLiteral from a string value.
        
        This is a convenience factory method for creating array literals from strings.
        The actual code generation happens in the codegen() method.
        
        Args:
            string_value: The string content
            storage_class: Optional storage class (GLOBAL, STACK, etc.)
            
        Returns:
            ArrayLiteral configured as a string
        """
        # Convert string to list of char literals
        elements = []
        for char in string_value:
            elements.append(Literal(char, DataType.CHAR))
        
        return ArrayLiteral(
            elements=elements,
            is_string=True,
            string_value=string_value,
            storage_class=storage_class
        )
    
    def create_global_string(self, module: ir.Module, string_val: str, name_hint: str = "") -> ir.Value:
        """Create a global string constant."""
        string_bytes = string_val.encode('ascii')
        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
        str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
        
        # Create unique name
        if not name_hint:
            name_hint = f"str_{ArrayLiteral._string_counter}"
            ArrayLiteral._string_counter += 1
        
        gname = f".str.{name_hint}"
        gv = ir.GlobalVariable(module, str_val.type, name=gname)
        gv.linkage = 'internal'
        gv.global_constant = True
        gv.initializer = str_val
        
        # Mark as array pointer for downstream logic
        gv.type._is_array_pointer = True
        
        return gv
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate code for array literal."""
        if self.is_string:
            return self._codegen_string_literal(builder, module)
        else:
            return self._codegen_array_literal(builder, module)
    
    def _codegen_string_literal(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Handle string literals (both single and multiple chars)."""
        if self.string_value is None:
            # Should not happen if is_string is True
            return self._codegen_array_literal(builder, module)
        
        string_bytes = self.string_value.encode('ascii')
        
        # Create array type for the string
        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
        
        # Create constant array with string bytes
        str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
        
        # Determine storage location based on storage_class and context
        use_global = (
            self.storage_class == StorageClass.GLOBAL or
            module.symbol_table.is_global_scope()  # Global scope
        )
        
        use_heap = self.storage_class == StorageClass.HEAP
        use_stack = (
            self.storage_class == StorageClass.STACK or
            self.storage_class == StorageClass.LOCAL or
            (not module.symbol_table.is_global_scope() and not use_global and not use_heap)
        )
        
        if use_heap:
            # Heap allocation: allocate memory and copy array data
            return heap_array_allocation(builder, module, str_val)
        
        if use_global:
            # Create global variable for the string with unique name
            str_name = f".str.{id(self)}"
            gv = ir.GlobalVariable(module, str_val.type, name=str_name)
            gv.linkage = 'internal'
            gv.global_constant = True
            gv.initializer = str_val
            
            # Return a pointer to the first element of the global array
            zero = ir.Constant(ir.IntType(32), 0)
            return builder.gep(gv, [zero, zero], inbounds=True, name="str_ptr")
        
        elif use_stack:
            # Allocate string on stack
            stack_alloca = builder.alloca(str_array_ty, name="str_stack")
            
            # Initialize stack array with string bytes
            for i, byte_val in enumerate(string_bytes):
                zero = ir.Constant(ir.IntType(32), 0)
                index = ir.Constant(ir.IntType(32), i)
                elem_ptr = builder.gep(stack_alloca, [zero, index], name=f"str_char_{i}")
                char_val = ir.Constant(ir.IntType(8), byte_val)
                builder.store(char_val, elem_ptr)
            
            # Return pointer to first element
            zero = ir.Constant(ir.IntType(32), 0)
            return builder.gep(stack_alloca, [zero, zero], inbounds=True, name="str_ptr")
        
        else:
            # Fallback: use global storage
            str_name = f".str.{id(self)}"
            gv = ir.GlobalVariable(module, str_val.type, name=str_name)
            gv.linkage = 'internal'
            gv.global_constant = True
            gv.initializer = str_val
            
            # Return pointer to first element
            zero = ir.Constant(ir.IntType(32), 0)
            return builder.gep(gv, [zero, zero], inbounds=True, name="str_ptr")
    
    def _codegen_array_literal(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Handle regular array literals like [1, 2, 3]."""

        if not self.elements:
            # Empty array - need element type to determine size
            if self.element_type:
                element_llvm_type = TypeSystem.get_llvm_type(self.element_type, module)
                # Create zero-length array
                array_type = ir.ArrayType(element_llvm_type, 0)
                if module.symbol_table.is_global_scope():
                    # Global empty array
                    gvar = ir.GlobalVariable(module, array_type, name=f".empty_array.{id(self)}")
                    gvar.linkage = 'internal'
                    gvar.global_constant = True
                    gvar.initializer = ir.Constant(array_type, [])
                    return gvar
                else:
                    # Local empty array
                    alloca = builder.alloca(array_type, name="empty_array")
                    return alloca
            else:
                raise ValueError("Cannot create empty array without element type")
        
        # Generate elements and infer common type
        element_values = []
        element_types = set()

        for elem in self.elements:
            # Special case: Pack StringLiteral into integer
            if isinstance(elem, StringLiteral):
                # Determine target type - default to i32 if not specified
                if self.element_type:
                    target_type = TypeSystem.get_llvm_type(self.element_type, module)
                else:
                    target_type = ir.IntType(32)  # Default to 32-bit int
                
                # Pack string into integer (little endian)
                if isinstance(target_type, ir.IntType):
                    #print("PACKING STRING")
                    string_val = elem.value
                    byte_count = min(len(string_val), target_type.width // 8)
                    packed_value = 0
                    for j in range(byte_count):
                        packed_value |= (ord(string_val[j]) << (j * 8))
                    elem_val = ir.Constant(target_type, packed_value)
                else:
                    # Not an integer target, use normal codegen
                    elem_val = elem.codegen(builder, module)
            else:
                elem_val = elem.codegen(builder, module)
            
            element_values.append(elem_val)
            element_types.add(elem_val.type)
        
        # Determine common element type
        if len(element_types) == 1:
            element_type = next(iter(element_types))
        else:
            # Try to find a common type
            element_type = find_common_type(list(element_types))
            # Cast all elements to common type
            for i in range(len(element_values)):
                if element_values[i].type != element_type:
                    element_values[i] = cast_to_type(builder, element_values[i], element_type)
        
        # Create array type and constant
        array_type = ir.ArrayType(element_type, len(element_values))
        
        if module.symbol_table.is_global_scope() or all(isinstance(val, ir.Constant) for val in element_values):
            # Global or compile-time constant array
            const_elements = [val if isinstance(val, ir.Constant) else 
                            ir.Constant(element_type, 0) for val in element_values]
            const_array = ir.Constant(array_type, const_elements)
            
            if module.symbol_table.is_global_scope():
                # Global constant
                gvar = ir.GlobalVariable(module, array_type, name=f".array_literal.{id(self)}")
                gvar.linkage = 'internal'
                gvar.global_constant = True
                gvar.initializer = const_array
                # Mark as array pointer
                gvar.type._is_array_pointer = True
                return gvar
            else:
                # Compile-time constant used locally
                alloca = builder.alloca(array_type, name="array_literal_const")
                builder.store(const_array, alloca)
                # Mark as array pointer
                alloca.type._is_array_pointer = True
                return alloca
        else:
            # Runtime array creation
            alloca = builder.alloca(array_type, name="array_literal")
            
            # Initialize each element
            zero = ir.Constant(ir.IntType(32), 0)
            for i, elem_val in enumerate(element_values):
                index = ir.Constant(ir.IntType(32), i)
                elem_ptr = builder.gep(alloca, [zero, index], inbounds=True, name=f"elem_{i}")
                builder.store(elem_val, elem_ptr)
            
            # Mark as array pointer
            alloca.type._is_array_pointer = True
            return alloca

@dataclass
class StringLiteral(Expression):
    """
    Represents a string literal.
    
    Unlike CHAR literals (single characters stored as i8),
    string literals are arrays of i8.
    """
    value: str
    storage_class: Optional[StorageClass] = None
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        string_bytes = self.value.encode('ascii')
        
        # Create array type for the string (no null terminator - Flux strings are not null-terminated)
        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
        
        # Create constant array with string bytes
        str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
        
        # Determine storage location
        use_global = (
            self.storage_class == StorageClass.GLOBAL or
            module.symbol_table.is_global_scope()  # Global scope
        )
        
        use_heap = self.storage_class == StorageClass.HEAP
        use_stack = (
            self.storage_class == StorageClass.STACK or
            self.storage_class == StorageClass.LOCAL or
            (not module.symbol_table.is_global_scope() and not use_global and not use_heap)
        )
        
        if use_heap:
            return string_heap_allocation(builder, module, str_val)
        
        if use_global:
            # Create global variable for the string with unique name
            str_name = f".str.{id(self)}"
            gv = ir.GlobalVariable(module, str_val.type, name=str_name)
            gv.linkage = 'internal'
            gv.global_constant = True
            gv.initializer = str_val
            
            # IMPORTANT: Mark this as an array pointer for downstream logic
            gv.type._is_array_pointer = True
            
            # Return the global variable itself (pointer to array)
            # The GEP to get i8* will be done at the use site if needed
            return gv
        
        elif use_stack:
            # Allocate string on stack
            stack_alloca = builder.alloca(str_array_ty, name="str_stack")
            
            # Initialize stack array with string bytes
            for i, byte_val in enumerate(string_bytes):
                zero = ir.Constant(ir.IntType(32), 0)
                index = ir.Constant(ir.IntType(32), i)
                elem_ptr = builder.gep(stack_alloca, [zero, index], name=f"str_char_{i}")
                char_val = ir.Constant(ir.IntType(8), byte_val)
                builder.store(char_val, elem_ptr)
            
            # IMPORTANT: Mark this as an array pointer for downstream logic
            stack_alloca.type._is_array_pointer = True
            
            # Return the alloca itself (pointer to array)
            # The GEP to get i8* will be done at the use site if needed
            return stack_alloca
        
        else:
            # Fallback: use global storage
            str_name = f".str.{id(self)}"
            gv = ir.GlobalVariable(module, str_val.type, name=str_name)
            gv.linkage = 'internal'
            gv.global_constant = True
            gv.initializer = str_val
            
            # IMPORTANT: Mark this as an array pointer for downstream logic
            gv.type._is_array_pointer = True
            
            # Return the global variable itself (pointer to array)
            return gv

@dataclass
class BinaryOp(Expression):
    left: Expression
    operator: Operator
    right: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        ctx = CoercionContext(builder)

        lhs = self.left.codegen(builder, module)
        rhs = self.right.codegen(builder, module)

        # --------------------------------------------------
        # Array concatenation
        # --------------------------------------------------

        if self.operator in (Operator.ADD, Operator.SUB):
            if (
                ArrayTypeHandler.is_array_or_array_pointer(lhs)
                and ArrayTypeHandler.is_array_or_array_pointer(rhs)
            ):
                return ArrayTypeHandler.concatenate(builder, module, lhs, rhs, self.operator)

        # --------------------------------------------------
        # Pointer arithmetic
        # --------------------------------------------------

        lhs_ptr = isinstance(lhs.type, ir.PointerType)
        rhs_ptr = isinstance(rhs.type, ir.PointerType)
        lhs_int = isinstance(lhs.type, ir.IntType)
        rhs_int = isinstance(rhs.type, ir.IntType)

        if self.operator in (Operator.ADD, Operator.SUB):
            if lhs_ptr and rhs_int:
                offset = rhs
                if self.operator is Operator.SUB:
                    offset = builder.sub(ir.Constant(rhs.type, 0), rhs)
                return builder.gep(lhs, [offset])

            if rhs_ptr and lhs_int and self.operator is Operator.ADD:
                return builder.gep(rhs, [lhs])

            if lhs_ptr and rhs_ptr:
                a = builder.ptrtoint(lhs, ir.IntType(64))
                b = builder.ptrtoint(rhs, ir.IntType(64))
                return builder.sub(a, b)

        # --------------------------------------------------
        # Arithmetic
        # --------------------------------------------------

        if self.operator in (Operator.ADD, Operator.SUB, Operator.MUL, Operator.DIV, Operator.MOD, Operator.POWER):
            if isinstance(lhs.type, ir.FloatType):
                if self.operator == Operator.POWER:
                    # Use LLVM pow intrinsic for floating point power
                    pow_fn_type = ir.FunctionType(lhs.type, [lhs.type, lhs.type])
                    pow_fn = ir.Function(module, pow_fn_type, name="llvm.pow.f64" if lhs.type == ir.DoubleType() else "llvm.pow.f32")
                    return builder.call(pow_fn, [lhs, rhs])
                return {
                    Operator.ADD: builder.fadd,
                    Operator.SUB: builder.fsub,
                    Operator.MUL: builder.fmul,
                    Operator.DIV: builder.fdiv,
                    Operator.MOD: builder.frem,
                }[self.operator](lhs, rhs)

            unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
            
            # Normalize operand widths BEFORE operation
            if isinstance(lhs.type, ir.IntType) and isinstance(rhs.type, ir.IntType):
                if lhs.type.width != rhs.type.width:
                    lhs, rhs = ctx.normalize_ints(lhs, rhs, unsigned=unsigned, promote=True)

            if self.operator == Operator.POWER:
                # Use LLVM powi intrinsic for integer exponent
                # Convert base to double, use powi, then convert back
                base_as_float = builder.sitofp(lhs, ir.DoubleType()) if not unsigned else builder.uitofp(lhs, ir.DoubleType())
                powi_fn_type = ir.FunctionType(ir.DoubleType(), [ir.DoubleType(), ir.IntType(32)])
                powi_fn = ir.Function(module, powi_fn_type, name="llvm.powi.f64.i32")
                # Cast exponent to i32 if needed
                if rhs.type.width > 32:
                    exp_i32 = builder.trunc(rhs, ir.IntType(32))
                elif rhs.type.width < 32:
                    exp_i32 = builder.sext(rhs, ir.IntType(32))
                else:
                    exp_i32 = rhs
                result_float = builder.call(powi_fn, [base_as_float, exp_i32])
                # Convert back to integer
                result = builder.fptoui(result_float, lhs.type) if unsigned else builder.fptosi(result_float, lhs.type)
            else:
                result = {
                    Operator.ADD: builder.add,
                    Operator.SUB: builder.sub,
                    Operator.MUL: builder.mul,
                    Operator.DIV: builder.udiv if unsigned else builder.sdiv,
                    Operator.MOD: builder.urem if unsigned else builder.srem,
                }[self.operator](lhs, rhs)
            
            # Preserve type metadata (signedness) to result
            if unsigned:
                return TypeSystem.attach_type_metadata(result, DataType.UINT)
            else:
                return TypeSystem.attach_type_metadata(result, DataType.SINT)

        # --------------------------------------------------
        # Comparisons
        # --------------------------------------------------

        if self.operator in {
            Operator.EQUAL,
            Operator.NOT_EQUAL,
            Operator.LESS_THAN,
            Operator.LESS_EQUAL,
            Operator.GREATER_THAN,
            Operator.GREATER_EQUAL,
        }:
            op_map = {
                Operator.EQUAL: "==",
                Operator.NOT_EQUAL: "!=",
                Operator.LESS_THAN: "<",
                Operator.LESS_EQUAL: "<=",
                Operator.GREATER_THAN: ">",
                Operator.GREATER_EQUAL: ">=",
            }
            op = op_map[self.operator]

            if isinstance(lhs.type, ir.FloatType):
                return builder.fcmp_ordered(op, lhs, rhs)

            if isinstance(lhs.type, ir.PointerType) or isinstance(rhs.type, ir.PointerType):
                return ctx.emit_ptr_cmp(op, lhs, rhs)

            # Coerce integer operands to same width before comparison
            if isinstance(lhs.type, ir.IntType) and isinstance(rhs.type, ir.IntType):
                if lhs.type.width != rhs.type.width:
                    unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
                    lhs, rhs = ctx.normalize_ints(lhs, rhs, unsigned=unsigned, promote=True)

            return ctx.emit_int_cmp(op, lhs, rhs)

        # --------------------------------------------------
        # Bitwise
        # --------------------------------------------------

        if self.operator in (Operator.BITAND, Operator.BITOR, Operator.BITXOR):
            lhs, rhs = ctx.normalize_ints(lhs, rhs, unsigned=True, promote=True)
            result = {
                Operator.AND: builder.and_,
                Operator.BITAND: builder.and_,
                Operator.OR: builder.or_,
                Operator.BITOR: builder.or_,
                Operator.XOR: builder.xor,
                Operator.BITXOR: builder.xor,
            }[self.operator](lhs, rhs)
            # Bitwise operations preserve signedness from operands
            unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
            return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)

        if self.operator in (Operator.AND, Operator.OR, Operator.XOR):
            lhs, rhs = ctx.normalize_ints(lhs, rhs, unsigned=True, promote=True)
            result = {
                Operator.AND: builder.and_,
                Operator.BITAND: builder.and_,
                Operator.OR: builder.or_,
                Operator.BITOR: builder.or_,
                Operator.XOR: builder.xor,
            }[self.operator](lhs, rhs)
            # Bitwise operations preserve signedness from operands
            unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
            return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)

        # --------------------------------------------------
        # Shifts
        # --------------------------------------------------

        if self.operator in (Operator.BITSHIFT_LEFT, Operator.BITSHIFT_RIGHT):
            # For bitshifts: the shift AMOUNT should match the VALUE's width
            # i64 << i32 should become i64 << i64 (extend amount, preserve value width)
            # i8 << i32 should become i8 << i8 (truncate amount to value width)
            # The result width is always the left operand's width
            if lhs.type.width != rhs.type.width:
                if rhs.type.width < lhs.type.width:
                    # Extend shift amount to match value width
                    rhs = builder.zext(rhs, lhs.type)
                else:
                    # Truncate shift amount to match value width
                    rhs = builder.trunc(rhs, lhs.type)

            if self.operator is Operator.BITSHIFT_LEFT:
                result = builder.shl(lhs, rhs)
                # Shifts preserve signedness of left operand
                unsigned = ctx.is_unsigned(lhs)
                return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)

            result = (
                builder.lshr(lhs, rhs)
                if ctx.is_unsigned(lhs)
                else builder.ashr(lhs, rhs)
            )
            # Shifts preserve signedness of left operand
            unsigned = ctx.is_unsigned(lhs)
            return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)

        # --------------------------------------------------
        # Boolean composites
        # --------------------------------------------------

        if self.operator is Operator.NOR:
            return builder.not_(builder.or_(lhs, rhs))

        if self.operator is Operator.NAND:
            return builder.not_(builder.and_(lhs, rhs))

        if self.operator is Operator.BITNAND:
            result = builder.not_(builder.and_(lhs, rhs))
            unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
            return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)

        if self.operator is Operator.BITNOR:
            result = builder.not_(builder.or_(lhs, rhs))
            unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
            return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)


        raise ValueError(f"Unsupported operator: {self.operator}")

@dataclass
class UnaryOp(Expression):
    operator: Operator
    operand: Expression
    is_postfix: bool = False

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Handle special case: ++@x or --@x (increment/decrement address of)
        if (self.operator in (Operator.INCREMENT, Operator.DECREMENT) and 
            isinstance(self.operand, AddressOf)):
            return self._handle_increment_address_of(builder, module)
        
        operand_val = self.operand.codegen(builder, module)
        
        # For increment/decrement, we need the actual value, not just the pointer
        # If operand is a pointer variable (T**), load it to get the value (T*)
        if self.operator in (Operator.INCREMENT, Operator.DECREMENT):
            if isinstance(self.operand, Identifier):
                # Check if we got a pointer that needs loading
                if isinstance(operand_val.type, ir.PointerType) and isinstance(operand_val.type.pointee, ir.PointerType):
                    # This is T** - load to get T*
                    operand_val = builder.load(operand_val, name=f"{self.operand.name}_loaded")
        
        if self.operator == Operator.NOT:
            # Handle NOT in global scope by creating constant
            if module.symbol_table.is_global_scope() and isinstance(operand_val, ir.Constant):
                if isinstance(operand_val.type, ir.IntType):
                    return ir.Constant(operand_val.type, ~operand_val.constant)
            return builder.not_(operand_val)
        elif self.operator == Operator.SUB:
            # Handle negation - for constants in global scope, create negative constant
            if module.symbol_table.is_global_scope() and isinstance(operand_val, ir.Constant):
                if isinstance(operand_val.type, ir.IntType):
                    return ir.Constant(operand_val.type, -operand_val.constant)
                elif isinstance(operand_val.type, ir.FloatType):
                    return ir.Constant(operand_val.type, -operand_val.constant)
            
            # Use appropriate negation based on type
            if isinstance(operand_val.type, ir.FloatType):
                # For floats, use fsub with 0.0
                zero = ir.Constant(operand_val.type, 0.0)
                return builder.fsub(zero, operand_val)
            else:
                # For integers, use regular neg (which uses sub)
                return builder.neg(operand_val)
        elif self.operator == Operator.INCREMENT:
            # Handle both prefix and postfix increment
            if isinstance(operand_val.type, ir.PointerType):
                # Pointer arithmetic: use GEP to increment by one element
                one = ir.Constant(ir.IntType(32), 1)
                new_val = builder.gep(operand_val, [one], name="ptr_inc")
            else:
                # Regular integer increment
                one = ir.Constant(operand_val.type, 1)
                new_val = builder.add(operand_val, one)
            
            if isinstance(self.operand, Identifier):
                # Retrieve the variable's pointer from the current scope or globals and store the updated value
                if not module.symbol_table.is_global_scope() and module.symbol_table.get_llvm_value(self.operand.name) is not None:
                    ptr = module.symbol_table.get_llvm_value(self.operand.name)
                elif self.operand.name in module.globals:
                    ptr = module.globals[self.operand.name]
                else:
                    raise NameError(f"Variable '{self.operand.name}' not found in any scope")
                st = builder.store(new_val, ptr)
                if hasattr(builder,'volatile_vars') and self.operand.name in builder.volatile_vars:
                    st.volatile = True
            return new_val if not self.is_postfix else operand_val
        elif self.operator == Operator.DECREMENT:
            # Handle both prefix and postfix decrement
            if isinstance(operand_val.type, ir.PointerType):
                # Pointer arithmetic: use GEP to decrement by one element
                neg_one = ir.Constant(ir.IntType(32), -1)
                new_val = builder.gep(operand_val, [neg_one], name="ptr_dec")
            else:
                # Regular integer decrement
                one = ir.Constant(operand_val.type, 1)
                new_val = builder.sub(operand_val, one)
            
            if isinstance(self.operand, Identifier):
                # Retrieve the variable's pointer from the current scope or globals and store the updated value
                if not module.symbol_table.is_global_scope() and module.symbol_table.get_llvm_value(self.operand.name) is not None:
                    ptr = module.symbol_table.get_llvm_value(self.operand.name)
                elif self.operand.name in module.globals:
                    ptr = module.globals[self.operand.name]
                else:
                    raise NameError(f"Variable '{self.operand.name}' not found in any scope")
                st = builder.store(new_val, ptr)
                if hasattr(builder,'volatile_vars') and self.operand.name in builder.volatile_vars:
                    st.volatile = True
            return new_val if not self.is_postfix else operand_val
        else:
            raise ValueError(f"Unsupported unary operator: {self.operator}")
    
    def _handle_increment_address_of(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Handle ++@x and --@x syntax (increment/decrement address of)"""
        #print(f"DEBUG: Handling {self.operator.value}@ for {self.operand.expression}")
        
        # Get the base address without dereferencing
        base_address = self.operand.codegen(builder, module)
        #print(f"DEBUG: Base address type: {base_address.type}")
        
        # Handle different address types
        if isinstance(base_address.type, ir.PointerType):
            if isinstance(base_address.type.pointee, ir.ArrayType):
                # For array pointers, get pointer to first element, then increment
                zero = ir.Constant(ir.IntType(32), 0)
                array_start = builder.gep(base_address, [zero, zero], name="array_start")
                
                # Now increment this element pointer
                if self.operator == Operator.INCREMENT:
                    offset = ir.Constant(ir.IntType(32), 1)
                    new_address = builder.gep(array_start, [offset], name="inc_addr")
                else:  # DECREMENT
                    offset = ir.Constant(ir.IntType(32), -1)
                    new_address = builder.gep(array_start, [offset], name="dec_addr")
            else:
                # For regular pointer types, perform direct pointer arithmetic
                if self.operator == Operator.INCREMENT:
                    offset = ir.Constant(ir.IntType(32), 1)
                    new_address = builder.gep(base_address, [offset], name="inc_addr")
                else:  # DECREMENT
                    offset = ir.Constant(ir.IntType(32), -1)
                    new_address = builder.gep(base_address, [offset], name="dec_addr")
        else:
            raise ValueError(f"Cannot increment/decrement address of non-pointer type: {base_address.type}")
        
        #print(f"DEBUG: New address type: {new_address.type}")
        #print(f"DEBUG: Returning incremented/decremented address (not loaded value)")
        
        # Return the new address, not the value at that address
        return new_address

@dataclass
class CastExpression(Expression):
    target_type: TypeSystem
    expression: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate code for cast expressions, including zero-cost struct reinterpretation and void casting"""
        
        # This must happen BEFORE any struct checking logic
        target_llvm_type = TypeSystem.get_llvm_type(self.target_type, module, include_array=True)
        
        # Handle void casting - frees memory according to Flux specification
        if isinstance(target_llvm_type, ir.VoidType):
            return self._handle_void_cast(builder, module)
        
        source_val = self.expression.codegen(builder, module)
        
        # If source and target are the same type, no cast needed
        if source_val.type == target_llvm_type:
            return source_val

        #Handle void pointer casts
        void_ptr_type = ir.PointerType(ir.IntType(8))

        # Cast TO void* from any pointer type
        if (target_llvm_type == void_ptr_type and isinstance(source_val.type, ir.PointerType)):
            return builder.bitcast(source_val, void_ptr_type, name="to_void_ptr")
        
        # Cast FROM void* to any pointer type
        if (source_val.type == void_ptr_type and isinstance(target_llvm_type, ir.PointerType)):
            return builder.bitcast(source_val, target_llvm_type, name="from_void_ptr")
        
        # Now check if RESOLVED types are structs (after alias resolution)
        # This prevents treating "byte" (which resolves to i8) as a struct
        
        # Handle struct-to-struct reinterpretation (zero-cost when sizes match)
        if (isinstance(source_val.type, ir.PointerType) and 
            isinstance(source_val.type.pointee, ir.LiteralStructType) and
            isinstance(target_llvm_type, ir.LiteralStructType)):
            
            source_struct_type = source_val.type.pointee
            target_struct_type = target_llvm_type
            
            # Check if sizes are compatible (same total bytes)
            source_size = sum(elem.width for elem in source_struct_type.elements if hasattr(elem, 'width'))
            target_size = sum(elem.width for elem in target_struct_type.elements if hasattr(elem, 'width'))
            
            if source_size == target_size:
                # Zero-cost reinterpretation: bitcast pointer, then load
                target_ptr_type = ir.PointerType(target_struct_type)
                reinterpreted_ptr = builder.bitcast(source_val, target_ptr_type, name="struct_reinterpret")
                return builder.load(reinterpreted_ptr, name="reinterpreted_struct")
            else:
                raise ValueError(f"Cannot cast struct of size {source_size} to struct of size {target_size}")
        
        # Handle loaded struct-to-struct cast (when source is already loaded from pointer)
        elif (isinstance(source_val.type, ir.LiteralStructType) and
            isinstance(target_llvm_type, ir.LiteralStructType)):
            
            # Check size compatibility
            source_size = sum(elem.width for elem in source_val.type.elements if hasattr(elem, 'width'))
            target_size = sum(elem.width for elem in target_llvm_type.elements if hasattr(elem, 'width'))
            
            if source_size == target_size:
                # Create temporary storage for reinterpretation
                source_ptr = builder.alloca(source_val.type, name="temp_source")
                builder.store(source_val, source_ptr)
                
                # Bitcast to target type pointer and load
                target_ptr_type = ir.PointerType(target_llvm_type)
                reinterpreted_ptr = builder.bitcast(source_ptr, target_ptr_type, name="struct_reinterpret")
                return builder.load(reinterpreted_ptr, name="reinterpreted_struct")
            else:
                raise ValueError(f"Cannot cast struct of size {source_size} to struct of size {target_size}")
        
        # Handle standard numeric casts
        if isinstance(source_val.type, ir.IntType) and isinstance(target_llvm_type, ir.IntType):
            if source_val.type.width > target_llvm_type.width:
                result = builder.trunc(source_val, target_llvm_type)
            elif source_val.type.width < target_llvm_type.width:
                # Determine if we should zero extend or sign extend
                if isinstance(self.expression, Literal):
                    # Check the literal's type
                    if self.expression.type == DataType.UINT:
                        # Unsigned literal -> zero extend
                        result = builder.zext(source_val, target_llvm_type)
                    elif self.expression.type == DataType.SINT:
                        # Signed literal -> sign extend
                        result = builder.sext(source_val, target_llvm_type)
                    else:
                        # Default to sign extend
                        result = builder.sext(source_val, target_llvm_type)
                else:
                    # Not a literal - check if target type is unsigned
                    if self.target_type.base_type == DataType.UINT or (
                        self.target_type.custom_typename and 
                        self.target_type.custom_typename.startswith('u')
                    ):
                        result = builder.zext(source_val, target_llvm_type)
                    else:
                        result = builder.sext(source_val, target_llvm_type)
            else:
                result = source_val
            
            # Attach target type metadata to result - ALWAYS, not just for truncation
            if hasattr(self, 'target_type'):
                result._flux_type_spec = self.target_type
            
            return result
        
        # Handle int to float
        elif isinstance(source_val.type, ir.IntType) and isinstance(target_llvm_type, (ir.FloatType, ir.DoubleType)):
            return builder.sitofp(source_val, target_llvm_type)
        
        # Handle float to int
        elif isinstance(source_val.type, (ir.FloatType, ir.DoubleType)) and isinstance(target_llvm_type, ir.IntType):
            return builder.fptosi(source_val, target_llvm_type)
        
        # Handle pointer to struct reinterpretation (e.g., char* -> MyStruct)
        elif isinstance(source_val.type, ir.PointerType) and isinstance(target_llvm_type, ir.LiteralStructType):
            # Bitcast the pointer to pointer-to-struct then load
            target_ptr_type = ir.PointerType(target_llvm_type)
            casted_ptr = builder.bitcast(source_val, target_ptr_type, name="ptr_to_struct")
            return builder.load(casted_ptr, name="loaded_struct")
        
        # Handle struct to pointer cast (e.g., struct A -> i8*)
        elif isinstance(source_val.type, ir.LiteralStructType) and isinstance(target_llvm_type, ir.PointerType):
            # Check if source is already a loaded struct value from a pointer
            if hasattr(source_val, 'name') and source_val.name and 'struct' in source_val.name:
                # This is a loaded struct - find the original pointer in scope
                source_name = source_val.name.replace('_struct_load', '').replace('_load', '')
                if module.symbol_table.get_llvm_value(source_name) is not None:
                    original_ptr = module.symbol_table.get_llvm_value(source_name)
                    return builder.bitcast(original_ptr, target_llvm_type, name="struct_to_ptr")
            
            # Create persistent storage for the struct that won't go out of scope
            source_ptr = builder.alloca(source_val.type, name="struct_for_cast")
            builder.store(source_val, source_ptr)
            
            # Bitcast the struct pointer to the target pointer type
            return builder.bitcast(source_ptr, target_llvm_type, name="struct_to_ptr")
        
        # Handle pointer casts (pointer -> pointer)
        elif isinstance(source_val.type, ir.PointerType) and isinstance(target_llvm_type, ir.PointerType):
            return builder.bitcast(source_val, target_llvm_type)

        # Handle integer to pointer cast (ADDRESS_CAST support)
        elif isinstance(source_val.type, ir.IntType) and isinstance(target_llvm_type, ir.PointerType):
            return builder.inttoptr(source_val, target_llvm_type, name="int_to_ptr")

        # Handle pointer to integer cast
        elif isinstance(source_val.type, ir.PointerType) and isinstance(target_llvm_type, ir.IntType):
            # Special case: array pointer to integer -> pack array elements
            if isinstance(source_val.type.pointee, ir.ArrayType):
                return ArrayTypeHandler.pack_array_pointer_to_integer(builder, module, source_val, target_llvm_type)
            # Regular pointer to integer (reinterpret cast like (i64*)ptr)
            return builder.ptrtoint(source_val, target_llvm_type, name="ptr_to_int")
        else:
            raise ValueError(f"Unsupported cast from {source_val.type} to {target_llvm_type}")
    
    def _handle_void_cast(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Handle void casting - immediately free memory according to Flux specification"""
        if isinstance(self.expression, Identifier):
            var_name = self.expression.name
            
            if not module.symbol_table.is_global_scope() and module.symbol_table.get_llvm_value(var_name) is not None:
                var_ptr = module.symbol_table.get_llvm_value(var_name)
                self._generate_runtime_free(builder, module, var_ptr, var_name)
                module.symbol_table.delete_variable(var_name)
                
            elif var_name in module.globals:
                gvar = module.globals[var_name]
                self._generate_runtime_free(builder, module, gvar, var_name)
            else:
                raise NameError(f"Cannot void cast unknown variable: {var_name}")
        else:
            expr_val = self.expression.codegen(builder, module)
            if isinstance(expr_val.type, ir.PointerType):
                self._generate_runtime_free(builder, module, expr_val, "<expression>")
        
        return None
    
    def _generate_runtime_free(self, builder: ir.IRBuilder, module: ir.Module, ptr_value: ir.Value, var_name: str) -> None:
        """Generate direct syscall to free memory - no external dependencies"""
        
        # Cast pointer to i8* if needed
        i8_ptr = ir.PointerType(ir.IntType(8))
        if ptr_value.type != i8_ptr:
            void_ptr = builder.bitcast(ptr_value, i8_ptr, name=f"{var_name}_void_ptr")
        else:
            void_ptr = ptr_value
        
        # Check OS macros
        is_windows = SymbolTable.is_macro_defined(module, '__WINDOWS__')
        is_linux = SymbolTable.is_macro_defined(module, '__LINUX__')
        is_macos = SymbolTable.is_macro_defined(module, '__MACOS__')
        
        if is_windows:
            # Windows free syscall - use proper Intel syntax with size suffixes
            asm_code = """
                movq %rcx, %r10
                movl $$0x1E, %eax
                syscall
            """
            # Note: Using AT&T syntax (source, dest) which LLVM expects
            # %rcx contains the pointer (first argument)
            # Move to r10 (Windows syscall convention)
            # 0x1E is the syscall number for NtFreeVirtualMemory
            constraints = "r,~{rax},~{r10},~{r11},~{memory}"
            
        elif is_linux:
            # Linux munmap syscall
            asm_code = """
                movq $$11, %rax
                syscall
            """
            # 11 is the syscall number for munmap on x86_64
            constraints = "r,~{rax},~{r11},~{memory}"
            
        elif is_macos:
            # macOS munmap syscall
            asm_code = """
                movq $$0x2000049, %rax
                syscall
            """
            # 0x2000049 is the syscall number for munmap on macOS
            constraints = "r,~{rax},~{memory}"
            
        else:
            # Unknown platform - skip free
            return
        
        asm_type = ir.FunctionType(ir.VoidType(), [i8_ptr])
        inline_asm = ir.InlineAsm(asm_type, asm_code, constraints, side_effect=True)
        builder.call(inline_asm, [void_ptr])

@dataclass
class RangeExpression(Expression):
    start: Expression
    end: Expression
    step: Optional[Expression] = None  # For future extension: start..end..step

    def codegen(self, builder: ir.IRBuilder, module: ir.Module, element_type=None) -> ir.Value:
        """Generate code for range expression - returns an iterable range object
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            element_type: Optional LLVM type to use for range bounds (defaults to i32)
        """
        start_val = self.start.codegen(builder, module)
        end_val = self.end.codegen(builder, module)
        
        # Determine the type to use for the range structure
        range_type = element_type if element_type is not None else ir.IntType(32)
        
        # For now, we'll create a simple range structure with start and end
        # In a full implementation, this would be a proper iterable object
        range_struct_type = ir.LiteralStructType([range_type, range_type])
        range_struct_type.names = ['start', 'end']
        
        # Allocate range struct
        range_ptr = builder.alloca(range_struct_type, name="range")
        
        # Cast start and end values to the appropriate type if needed
        from llvmlite import ir as _ir
        if isinstance(start_val.type, _ir.IntType) and isinstance(range_type, _ir.IntType) and start_val.type.width != range_type.width:
            start_val = builder.trunc(start_val, range_type) if start_val.type.width > range_type.width else builder.sext(start_val, range_type)
        if isinstance(end_val.type, _ir.IntType) and isinstance(range_type, _ir.IntType) and end_val.type.width != range_type.width:
            end_val = builder.trunc(end_val, range_type) if end_val.type.width > range_type.width else builder.sext(end_val, range_type)
        
        # Store start value
        start_ptr = builder.gep(range_ptr, [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), 0)], inbounds=True)
        builder.store(start_val, start_ptr)
        
        # Store end value
        end_ptr = builder.gep(range_ptr, [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), 1)], inbounds=True)
        builder.store(end_val, end_ptr)
        
        return range_ptr

@dataclass
class ArrayComprehension(Expression):
    expression: Expression  # The expression to evaluate for each element
    variable: str  # Loop variable name
    variable_type: Optional[TypeSystem]  # Type of loop variable
    iterable: Expression  # What to iterate over (e.g., range expression or ArrayLiteral)
    condition: Optional[Expression] = None  # Optional filter condition

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate code for array comprehension [expr for var in iterable]"""
        # Resolve element type using type handler
        element_type = ArrayTypeHandler.resolve_comprehension_element_type(self.variable_type, module)
        
        # Handle ArrayLiteral as iterable
        if isinstance(self.iterable, ArrayLiteral):
            iterable_elements = self.iterable.elements
            num_elements = len(iterable_elements)
            
            # Allocate result array
            array_type = ir.ArrayType(element_type, num_elements)
            array_ptr = builder.alloca(array_type, name="comprehension_array")
            
            # Allocate iterable array and populate it
            iterable_array_ptr = builder.alloca(array_type, name="iterable_array")
            for i, elem_expr in enumerate(iterable_elements):
                elem_val = elem_expr.codegen(builder, module)
                
                # Cast to element_type if needed
                elem_val = ArrayTypeHandler.cast_to_target_int_type(builder, elem_val, element_type)
                
                elem_ptr = builder.gep(iterable_array_ptr, [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), i)])
                builder.store(elem_val, elem_ptr)
            
            # Create loop variable and index
            var_ptr = builder.alloca(element_type, name=self.variable)
            module.symbol_table.define(self.variable, SymbolKind.VARIABLE, llvm_value=var_ptr)
            index_ptr = builder.alloca(ir.IntType(32), name="comp_index")
            builder.store(ir.Constant(ir.IntType(32), 0), index_ptr)
            
            # Loop blocks
            func = builder.block.function
            loop_cond = func.append_basic_block('comp_loop_cond')
            loop_body = func.append_basic_block('comp_loop_body')
            loop_end = func.append_basic_block('comp_loop_end')
            
            builder.branch(loop_cond)
            
            # Loop condition: index < num_elements
            builder.position_at_start(loop_cond)
            current_index = builder.load(index_ptr)
            cond = builder.icmp_signed('<', current_index, ir.Constant(ir.IntType(32), num_elements))
            builder.cbranch(cond, loop_body, loop_end)
            
            # Loop body
            builder.position_at_start(loop_body)
            
            # Load current element from iterable
            elem_ptr = builder.gep(iterable_array_ptr, [ir.Constant(ir.IntType(32), 0), current_index])
            current_var = builder.load(elem_ptr)
            builder.store(current_var, var_ptr)
            
            # Evaluate expression
            expr_val = self.expression.codegen(builder, module)
            
            # Cast result to element_type if needed
            expr_val = ArrayTypeHandler.cast_to_target_int_type(builder, expr_val, element_type)
            
            # Store result
            result_elem_ptr = builder.gep(array_ptr, [ir.Constant(ir.IntType(32), 0), current_index])
            builder.store(expr_val, result_elem_ptr)
            
            # Increment index
            next_index = builder.add(current_index, ir.Constant(ir.IntType(32), 1))
            builder.store(next_index, index_ptr)
            builder.branch(loop_cond)
            
            # End of loop
            builder.position_at_start(loop_end)
            return array_ptr
        
        # Handle RangeExpression (existing code)
        elif isinstance(self.iterable, RangeExpression):
            _ = self.iterable.codegen(builder, module, element_type)
            
            start_val = self.iterable.start.codegen(builder, module)
            end_val = self.iterable.end.codegen(builder, module)
            
            # Cast range bounds to element_type
            start_val_sized = ArrayTypeHandler.cast_to_target_int_type(builder, start_val, element_type)
            end_val_sized = ArrayTypeHandler.cast_to_target_int_type(builder, end_val, element_type)
                
            size_val = builder.sub(end_val_sized, start_val_sized, name="range_size")
            
            max_size = 100
            array_type = ir.ArrayType(element_type, max_size)
            array_ptr = builder.alloca(array_type, name="comprehension_array")
            
            index_ptr = builder.alloca(ir.IntType(32), name="comp_index")
            builder.store(ir.Constant(ir.IntType(32), 0), index_ptr)
            
            var_ptr = builder.alloca(element_type, name=self.variable)
            module.symbol_table.define(self.variable, SymbolKind.VARIABLE, llvm_value=var_ptr)
            
            # Cast start_val and end_val if needed
            start_val = ArrayTypeHandler.cast_to_target_int_type(builder, start_val, element_type)
            end_val = ArrayTypeHandler.cast_to_target_int_type(builder, end_val, element_type)
            
            func = builder.block.function
            loop_cond = func.append_basic_block('comp_loop_cond')
            loop_body = func.append_basic_block('comp_loop_body')
            loop_end = func.append_basic_block('comp_loop_end')
            
            builder.store(start_val, var_ptr)
            builder.branch(loop_cond)
            
            builder.position_at_start(loop_cond)
            current_var = builder.load(var_ptr, name="current_var")
            cond = builder.icmp_signed('<', current_var, end_val, name="loop_cond")
            builder.cbranch(cond, loop_body, loop_end)
            
            builder.position_at_start(loop_body)
            
            expr_val = self.expression.codegen(builder, module)
            
            expr_val = ArrayTypeHandler.cast_to_target_int_type(builder, expr_val, element_type)
            
            current_index = builder.load(index_ptr, name="current_index")
            array_elem_ptr = builder.gep(array_ptr, [ir.Constant(ir.IntType(32), 0), current_index], inbounds=True)
            builder.store(expr_val, array_elem_ptr)
            
            next_index = builder.add(current_index, ir.Constant(ir.IntType(32), 1), name="next_index")
            builder.store(next_index, index_ptr)
            
            next_var = builder.add(current_var, ir.Constant(element_type, 1), name="next_var")
            builder.store(next_var, var_ptr)
            
            builder.branch(loop_cond)
            
            builder.position_at_start(loop_end)
            
            return array_ptr
        else:
            raise NotImplementedError("Array comprehension only supports range expressions and array literals")

@dataclass
class FStringLiteral(Expression):
    """Represents an f-string - evaluated at compile time when possible"""
    parts: List[Union[str, Expression]]
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Try to evaluate ALL parts at compile time
        try:
            # Concatenate all parts, evaluating expressions if needed
            full_string = ""
            for part in self.parts:
                if isinstance(part, str):
                    # Clean string literal part
                    clean_part = part
                    if clean_part.startswith('f"'):
                        clean_part = clean_part[2:]
                    if clean_part.endswith('"'):
                        clean_part = clean_part[:-1]
                    full_string += clean_part
                else:
                    # Try to evaluate the expression at compile time
                    # This only works for simple literals and constants
                    part_val = self._evaluate_compile_time_expression(part, builder, module)
                    full_string += str(part_val)
            
            # Use ArrayLiteral to create the compile-time string
            return ArrayLiteral.from_string(full_string).codegen(builder, module)
            
        except (ValueError, NotImplementedError):
            return self._generate_runtime_fstring(builder, module)

    def _generate_runtime_fstring(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Generate runtime code for f-string evaluation.
        
        This method generates code that:
        1. Evaluates each part (literals and expressions) at runtime
        2. Converts values to strings
        3. Concatenates them into the final string
        """
        # Estimate buffer size conservatively
        max_size = 256
        for part in self.parts:
            if isinstance(part, Literal) and part.type == DataType.CHAR:
                max_size += len(part.value)
            else:
                max_size += 32  # Conservative estimate for numeric conversions
        
        # Allocate buffer on stack
        buffer_type = ir.ArrayType(ir.IntType(8), max_size)
        buffer = builder.alloca(buffer_type, name="fstring_buffer")
        
        # Initialize position counter
        pos_ptr = builder.alloca(ir.IntType(32), name="fstring_pos")
        builder.store(ir.Constant(ir.IntType(32), 0), pos_ptr)
        
        # Declare sprintf for number-to-string conversion
        sprintf_fn = module.globals.get('sprintf')
        if sprintf_fn is None:
            sprintf_type = ir.FunctionType(
                ir.IntType(32),
                [ir.PointerType(ir.IntType(8)), ir.PointerType(ir.IntType(8))],
                var_arg=True
            )
            sprintf_fn = ir.Function(module, sprintf_type, 'sprintf')
            sprintf_fn.linkage = 'external'
        
        # Process each part
        for part in self.parts:
            pos = builder.load(pos_ptr, name="current_pos")
            dest_ptr = builder.gep(buffer, [ir.Constant(ir.IntType(32), 0), pos], name="dest")
            
            if isinstance(part, str):
                # Plain string part: clean and copy character by character
                clean_part = part
                if clean_part.startswith('f"'):
                    clean_part = clean_part[2:]
                if clean_part.endswith('"'):
                    clean_part = clean_part[:-1]
                
                # Create a string literal from the cleaned part
                str_literal = ArrayLiteral.from_string(clean_part)
                src_val = str_literal.codegen(builder, module)
                str_len = len(clean_part)
                
                for i in range(str_len):
                    char_ptr = builder.gep(src_val, [ir.Constant(ir.IntType(32), i)])
                    char_val = builder.load(char_ptr)
                    dest_char_ptr = builder.gep(dest_ptr, [ir.Constant(ir.IntType(32), i)])
                    builder.store(char_val, dest_char_ptr)
                
                new_pos = builder.add(pos, ir.Constant(ir.IntType(32), str_len))
                builder.store(new_pos, pos_ptr)
            elif isinstance(part, Literal) and part.type == DataType.CHAR:
                # String literal: copy character by character
                src_val = part.codegen(builder, module)
                if isinstance(src_val.type, ir.PointerType):
                    str_len = len(part.value)
                    for i in range(str_len):
                        char_ptr = builder.gep(src_val, [ir.Constant(ir.IntType(32), i)])
                        char_val = builder.load(char_ptr)
                        dest_char_ptr = builder.gep(dest_ptr, [ir.Constant(ir.IntType(32), i)])
                        builder.store(char_val, dest_char_ptr)
                    
                    new_pos = builder.add(pos, ir.Constant(ir.IntType(32), str_len))
                    builder.store(new_pos, pos_ptr)
            else:
                # Expression: evaluate and convert to string using sprintf
                val = part.codegen(builder, module)
                
                # Determine format string based on type
                if isinstance(val.type, ir.IntType):
                    fmt_str = "%llu" if is_unsigned(val) else "%lld"
                elif isinstance(val.type, ir.FloatType):
                    fmt_str = "%f"
                else:
                    fmt_str = "%p"
                
                # Create format string global
                fmt_bytes = (fmt_str + "\\0").encode('ascii')
                fmt_array_ty = ir.ArrayType(ir.IntType(8), len(fmt_bytes))
                fmt_val = ir.Constant(fmt_array_ty, bytearray(fmt_bytes))
                
                fmt_gv = ir.GlobalVariable(module, fmt_val.type, 
                                          name=f".fstring_fmt_{id(part)}")
                fmt_gv.linkage = 'internal'
                fmt_gv.global_constant = True
                fmt_gv.initializer = fmt_val
                
                zero = ir.Constant(ir.IntType(32), 0)
                fmt_ptr = builder.gep(fmt_gv, [zero, zero])
                
                # Extend value to 64-bit for variadic args if needed
                if isinstance(val.type, ir.IntType) and val.type.width < 64:
                    val = builder.zext(val, ir.IntType(64)) if is_unsigned(val) else builder.sext(val, ir.IntType(64))
                
                chars_written = builder.call(sprintf_fn, [dest_ptr, fmt_ptr, val])
                new_pos = builder.add(pos, chars_written)
                builder.store(new_pos, pos_ptr)
        
        # Null-terminate the string
        final_pos = builder.load(pos_ptr)
        null_ptr = builder.gep(buffer, [ir.Constant(ir.IntType(32), 0), final_pos])
        builder.store(ir.Constant(ir.IntType(8), 0), null_ptr)
        
        # Return pointer to the buffer
        zero = ir.Constant(ir.IntType(32), 0)
        return builder.gep(buffer, [zero, zero], name="fstring_result")

    def _evaluate_compile_time_expression(self, expr: Expression, builder: ir.IRBuilder, module: ir.Module) -> Any:
        """Try to evaluate an expression at compile time"""
        
        # Handle literals
        if isinstance(expr, Literal):
            if expr.type == DataType.SINT:
                return int(expr.value)
            elif expr.type == DataType.FLOAT:
                return float(expr.value)
            elif expr.type == DataType.BOOL:
                return bool(expr.value)
            elif expr.type == DataType.CHAR:
                return str(expr.value) if isinstance(expr.value, str) else chr(expr.value)
            else:
                raise ValueError(f"Cannot convert {expr.type} literal to string at compile time")
        
        # Handle simple binary operations with compile-time constants
        elif isinstance(expr, BinaryOp):
            left = self._evaluate_compile_time_expression(expr.left, builder, module)
            right = self._evaluate_compile_time_expression(expr.right, builder, module)
            
            if expr.operator == Operator.ADD:
                return left + right
            elif expr.operator == Operator.SUB:
                return left - right
            elif expr.operator == Operator.MUL:
                return left * right
            elif expr.operator == Operator.DIV:
                return left / right
            elif expr.operator == Operator.MOD:
                return left % right
            elif expr.operator == Operator.EQUAL:
                return left == right
            elif expr.operator == Operator.NOT_EQUAL:
                return left != right
            elif expr.operator == Operator.LESS_THAN:
                return left < right
            elif expr.operator == Operator.LESS_EQUAL:
                return left <= right
            elif expr.operator == Operator.GREATER_THAN:
                return left > right
            elif expr.operator == Operator.GREATER_EQUAL:
                return left >= right
            else:
                raise NotImplementedError(f"Operator {expr.operator} not supported for compile-time f-string evaluation")
        
        # Handle unary operations
        elif isinstance(expr, UnaryOp):
            operand = self._evaluate_compile_time_expression(expr.operand, builder, module)
            
            if expr.operator == Operator.IS:
                return operand
            elif expr.operator == Operator.NOT:
                return not operand
            elif expr.operator == Operator.SUB:
                return -operand
            else:
                raise NotImplementedError(f"Unary operator {expr.operator} not supported for compile-time f-string evaluation")
        
        # Handle identifiers that refer to compile-time constants
        elif isinstance(expr, Identifier):
            # Check if this is a global constant
            if expr.name in module.globals:
                gvar = module.globals[expr.name]
                if hasattr(gvar, 'initializer') and gvar.initializer is not None:
                    # Try to extract constant value
                    if hasattr(gvar.initializer, 'constant'):
                        const_val = gvar.initializer.constant
                        if isinstance(const_val, int):
                            return const_val
                        elif isinstance(const_val, float):
                            return const_val
                        elif isinstance(const_val, bool):
                            return const_val
        
        # Handle sizeof/alignof with compile-time types
        elif isinstance(expr, SizeOf):
            if isinstance(expr.target, TypeSystem):
                # We can compute sizeof for TypeSystem at compile time
                llvm_type = TypeSystem.get_llvm_type(expr.target, module, include_array=True)
                if isinstance(llvm_type, ir.IntType):
                    return llvm_type.width // 8  # Convert bits to bytes
                elif isinstance(llvm_type, ir.ArrayType):
                    element_bits = llvm_type.element.width
                    total_bits = element_bits * llvm_type.count
                    return total_bits // 8  # Convert bits to bytes
        
        # Handle function calls to constexpr functions (future enhancement)
        # elif isinstance(expr, FunctionCall):
        #     # Could check if function is marked as constexpr
        #     pass
        
        # If we get here, we can't evaluate at compile time
        raise NotImplementedError(f"Cannot evaluate {type(expr).__name__} at compile time for f-string")

@dataclass
class FunctionCall(Expression):
    name: str
    arguments: List[Expression] = field(default_factory=list)
    
    # Class-level counter for globally unique string literals
    _string_counter = 0

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Generate code for function calls with full overload resolution support.
        
        Resolution order:
        1. Check if this is a function pointer variable
        2. Check direct name in module.globals
        3. Check for overloaded functions in _function_overloads
        4. Check symbol table for function definitions
        5. Check namespace-qualified names via _using_namespaces
        6. Check namespace-qualified overloads
        7. Raise error if still not found
        """
        #print(f"[RESOLUTION START] Trying to resolve function '{self.name}'", file=sys.stderr)
        
        # Step 1: Check if this is a function pointer variable
        if self._is_function_pointer_variable(builder, module):
            func_ptr_call = FunctionPointerCall(pointer=Identifier(self.name), arguments=self.arguments)
            return func_ptr_call.codegen(builder, module)
        
        # Step 2: Try direct lookup
        func = self._try_direct_lookup(module)
        #if func:
        #    print(f"[RESOLUTION] Found '{self.name}' via direct lookup", file=sys.stderr)
        
        # Step 3: If not found, try overload resolution
        if func is None:
            func = self._try_overload_resolution(builder, module, self.name)
            #if func:
            #    print(f"[RESOLUTION] Found '{self.name}' via overload resolution", file=sys.stderr)
            #else:
            #    print(f"[RESOLUTION] Overload resolution for '{self.name}' returned None", file=sys.stderr)
        
        # Step 4: If still not found, try symbol table resolution
        if func is None:
            #print(f"[SYMBOL TABLE] Trying TypeResolver.resolve_function for '{self.name}'", file=sys.stderr)
            current_ns = module.symbol_table.current_namespace if hasattr(module, 'symbol_table') else ""
            resolved_name = TypeResolver.resolve_function(module, self.name, current_ns)
            #print(f"[SYMBOL TABLE] TypeResolver returned: {resolved_name}", file=sys.stderr)
            if resolved_name and resolved_name in module.globals:
                func = module.globals[resolved_name]
                if not isinstance(func, ir.Function):
                    func = None
            #if func:
            #    print(f"[RESOLUTION] Found '{self.name}' via symbol table", file=sys.stderr)
        
        # Step 5: If still not found, try namespace-qualified names
        if func is None and hasattr(module, '_using_namespaces'):
            #print(f"[RESOLUTION] Trying namespace resolution for '{self.name}'", file=sys.stderr)
            func = self._try_namespace_resolution(builder, module)
            #if func:
            #    print(f"[RESOLUTION] Found '{self.name}' via namespace resolution", file=sys.stderr)
        
        # Step 6: Error if still not found
        if func is None:
            #print(f"[RESOLUTION] All resolution steps failed for '{self.name}'", file=sys.stderr)
            self._raise_function_not_found_error(module)
        
        #print(f"Generating function call for {self.name}")
        # Generate the actual function call
        return self._generate_call(builder, module, func)
    
    def _is_function_pointer_variable(self, builder: ir.IRBuilder, module: ir.Module) -> bool:
        """
        Check if the function name refers to a function pointer variable.
        
        Returns:
            True if this is a function pointer variable, False otherwise
        """
        
        # Check local scope
        if module.symbol_table.get_llvm_value(self.name) is not None:
            var_ptr = module.symbol_table.get_llvm_value(self.name)
            # Check if it's a pointer to a function type
            # Note: Local variables are allocated with alloca, so we get a pointer to the pointer
            if isinstance(var_ptr.type, ir.PointerType):
                pointee = var_ptr.type.pointee
                # Check for both direct function pointer and double-pointer (from alloca)
                if isinstance(pointee, ir.FunctionType):
                    return True
                elif isinstance(pointee, ir.PointerType) and isinstance(pointee.pointee, ir.FunctionType):
                    return True
        
        # Check global scope
        elif self.name in module.globals:
            gvar = module.globals[self.name]
            if not isinstance(gvar, ir.Function):
                if isinstance(gvar.type, ir.PointerType):
                    if isinstance(gvar.type.pointee, ir.FunctionType):
                        return True

        return False

    def _try_direct_lookup(self, module: ir.Module) -> Optional[ir.Function]:
        """
        Try to find the function by direct name lookup.
        
        Returns:
            Function object if found, None otherwise
        """
        #print(f"[DIRECT LOOKUP] Checking for '{self.name}' in module.globals", file=sys.stderr)
        #print(f"[DIRECT LOOKUP] Total items in module.globals: {len(module.globals)}", file=sys.stderr)
        
        # Show all functions in globals
        all_funcs = [name for name, obj in module.globals.items() if isinstance(obj, ir.Function)]
        #print(f"[DIRECT LOOKUP] All functions in globals: {all_funcs[:20]}", file=sys.stderr)
        
        func = module.globals.get(self.name, None)
        if func:
            #print(f"[DIRECT LOOKUP] Found '{self.name}': {type(func)}", file=sys.stderr)
            if isinstance(func, ir.Function):
                return func
        #else:
        #    print(f"[DIRECT LOOKUP] '{self.name}' not in module.globals", file=sys.stderr)
        return None
    
    def _try_overload_resolution(self, builder: ir.IRBuilder, module: ir.Module, 
                                 base_name: str) -> Optional[ir.Function]:
        """
        Try to resolve the function through overload resolution.
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            base_name: Base function name (unmangled)
        Returns:
            Function object if found, None otherwise
        """
        #print(f"[OVERLOAD] Checking for overloads of '{base_name}'", file=sys.stderr)
        if not hasattr(module, '_function_overloads'):
            #print(f"[OVERLOAD] No _function_overloads attribute on module", file=sys.stderr)
            return None
        # Check if this base_name has any overloads registered
        if base_name not in module._function_overloads:
            #print(f"[OVERLOAD] '{base_name}' not in _function_overloads", file=sys.stderr)
            #print(f"[OVERLOAD] Available overloaded functions: {list(module._function_overloads.keys())}", file=sys.stderr)
            return None
        #print(f"[OVERLOAD] Found {len(module._function_overloads[base_name])} overload(s) for '{base_name}'", file=sys.stderr)
        # Use _resolve_overload which internally uses FunctionTypeHandler
        return self._resolve_overload(builder, module, base_name, 
                                     module._function_overloads[base_name])
    
    def _try_namespace_resolution(self, builder: ir.IRBuilder, module: ir.Module) -> Optional[ir.Function]:
        """
        Try to resolve the function through namespace-qualified names using SymbolTable.
        
        Returns:
            Function object if found, None otherwise
        """
        #print(f"[NAMESPACE RESOLVE] Trying to resolve '{self.name}'", file=sys.stderr)
        
        # Get current namespace context from symbol table or module
        if hasattr(module, 'symbol_table'):
            current_namespace = module.symbol_table.current_namespace
            #print(f"[NAMESPACE RESOLVE]   current_namespace='{current_namespace}' (from symbol_table)", file=sys.stderr)
            
            # Try to lookup the function in the symbol table
            func_entry = module.symbol_table.lookup_function(self.name, current_namespace)
            if func_entry:
                #print(f"[NAMESPACE RESOLVE]   Found in symbol_table: {func_entry.mangled_name}", file=sys.stderr)
                
                # First, try to get it directly from llvm_value (fastest)
                if func_entry.llvm_value and isinstance(func_entry.llvm_value, ir.Function):
                    #print(f"[NAMESPACE RESOLVE]   Found function in symbol_table.llvm_value!", file=sys.stderr)
                    return func_entry.llvm_value
                
                # Fallback: Try to get the function from module.globals
                if func_entry.mangled_name in module.globals:
                    candidate_func = module.globals[func_entry.mangled_name]
                    if isinstance(candidate_func, ir.Function):
                        #print(f"[NAMESPACE RESOLVE]   Found function in globals via mangled_name!", file=sys.stderr)
                        return candidate_func
                
                # Last resort: try the unmangled name
                if self.name in module.globals:
                    candidate_func = module.globals[self.name]
                    if isinstance(candidate_func, ir.Function):
                        #print(f"[NAMESPACE RESOLVE]   Found function in globals via unmangled name!", file=sys.stderr)
                        return candidate_func
        else:
            current_namespace = module.symbol_table.current_namespace if hasattr(module, 'symbol_table') else ''
            #print(f"[NAMESPACE RESOLVE]   current_namespace='{current_namespace}' (from module attr)", file=sys.stderr)
        
        # Fallback: use old TypeResolver method
        #print(f"[NAMESPACE RESOLVE]   Trying TypeResolver.resolve_type", file=sys.stderr)
        resolved_name = TypeResolver.resolve_type(module, self.name, current_namespace)
        if resolved_name:
            #print(f"[NAMESPACE RESOLVE]   resolved_name='{resolved_name}'", file=sys.stderr)
            
            if resolved_name in module.globals:
                candidate_func = module.globals[resolved_name]
                if isinstance(candidate_func, ir.Function):
                    #print(f"[NAMESPACE RESOLVE]   Found function in globals!", file=sys.stderr)
                    return candidate_func
                
                # Also check for overloaded versions of the resolved name
                func = self._try_overload_resolution(builder, module, resolved_name)
                #print("TRYING OVERLOAD RESOLUTION")
                if func is not None:
                    #print(f"[NAMESPACE RESOLVE]   Found via overload resolution!", file=sys.stderr)
                    return func
        
        #print(f"[NAMESPACE RESOLVE]   NOT FOUND", file=sys.stderr)
        return None
    
    def _raise_function_not_found_error(self, module: ir.Module) -> None:
        """
        Raise an appropriate error when the function cannot be found.
        
        Raises:
            ValueError: If function exists but with wrong argument count
            NameError: If function not found at all
        """
        if hasattr(module, '_function_overloads') and self.name in module._function_overloads:
            available_counts = [o['param_count'] for o in module._function_overloads[self.name]]
            if len(self.arguments) not in available_counts:
                raise ValueError(
                    f"Function '{self.name}' found but no overload accepts {len(self.arguments)} arguments. "
                    f"Available overloads accept: {available_counts} arguments."
                )
        
        # Function not found anywhere - raise a clear error
        raise NameError(f"Function '{self.name}' not found in module or any imported namespaces")

    def _resolve_overload(self, builder: ir.IRBuilder, module: ir.Module, base_name: str, overloads: list) -> ir.Function:
        """
        Resolve function overload by matching argument count and types.
        """
        arg_count = len(self.arguments)
        
        # Filter by argument count first
        candidates = [o for o in overloads if o['param_count'] == arg_count]
        
        if len(candidates) == 0:
            return None
        elif len(candidates) == 1:
            # Only one candidate - use it
            func = candidates[0]['function']
            
            # DEFENSIVE CHECK: If function is a string, look it up in module.globals
            if isinstance(func, str):
                print(f"[WARNING] Overload metadata contains string '{func}' instead of function object", file=sys.stderr)
                print(f"[WARNING] This indicates a bug in overload registration", file=sys.stderr)
                if func in module.globals:
                    func = module.globals[func]
                    if isinstance(func, ir.Function):
                        return func
                return None
            
            return func
        else:
            # Multiple candidates - generate argument values and use FunctionTypeHandler
            arg_vals = [arg.codegen(builder, module) for arg in self.arguments]
            
            # Delegate to FunctionTypeHandler for type-based resolution
            return FunctionTypeHandler.resolve_overload_by_types(module, base_name, arg_vals)

    def _generate_call(self, builder: ir.IRBuilder, module: ir.Module, func: ir.Function) -> ir.Value:
        """
        Generate the actual function call with argument processing.
        Uses FunctionTypeHandler for argument type conversion.
        """
        # Handle deferred type resolution
        if isinstance(func, tuple) and func[0] == '__NEEDS_TYPE_RESOLUTION__':
            _, base_name, candidates = func
            # NOW generate argument values for type resolution
            arg_vals = [arg.codegen(builder, module) for arg in self.arguments]
            # Resolve using types
            func = FunctionTypeHandler.resolve_overload_by_types(module, base_name, arg_vals)
            if func is None:
                raise ValueError(f"Could not resolve overload for {base_name} with argument types {[str(v.type) for v in arg_vals]}")
        # Check if this is a method call (has dot in name)
        is_method_call = '.' in self.name
        parameter_offset = 1 if is_method_call else 0  # Account for implicit 'this' parameter
        
        # Generate code for arguments
        arg_vals = []
        for i, arg in enumerate(self.arguments):
            param_index = i + parameter_offset
            
            # Handle string literals specially
            if self._is_string_literal_for_pointer(arg, func, param_index):
                arg_val = self._create_string_constant(builder, module, arg, i)
            else:
                arg_val = arg.codegen(builder, module)
            
            # Use FunctionTypeHandler for type checking and conversion
            if param_index < len(func.args):
                expected_type = func.args[param_index].type
                arg_val = FunctionTypeHandler.convert_argument_to_parameter_type(builder, module, arg_val, expected_type, i)
            
            arg_vals.append(arg_val)
        #print(f"Generated call for {self.name}")
        return builder.call(func, arg_vals)

    def _is_string_literal_for_pointer(self, arg: Expression, func: ir.Function, 
                                      param_index: int) -> bool:
        """
        Check if argument is a string literal being passed to an i8* parameter.
        
        Args:
            arg: Argument expression
            func: Target function
            param_index: Parameter index
            
        Returns:
            True if this is a string literal that needs special handling
        """
        return (isinstance(arg, Literal) and 
                arg.type == DataType.CHAR and 
                param_index < len(func.args) and 
                isinstance(func.args[param_index].type, ir.PointerType) and 
                isinstance(func.args[param_index].type.pointee, ir.IntType) and 
                func.args[param_index].type.pointee.width == 8)
    
    def _create_string_constant(self, builder: ir.IRBuilder, module: ir.Module, 
                               arg: Literal, arg_index: int) -> ir.Value:
        """
        Create a global string constant for a string literal argument.
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            arg: String literal argument
            arg_index: Argument index (for naming)
            
        Returns:
            Pointer to the string constant
        """
        string_val = arg.value
        string_bytes = string_val.encode('ascii')
        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
        str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
        
        # Create global variable for the string with globally unique name
        # Use class-level counter to ensure uniqueness across all function calls
        str_name = f".str.{FunctionCall._string_counter}"
        FunctionCall._string_counter += 1
        
        gv = ir.GlobalVariable(module, str_val.type, name=str_name)
        gv.linkage = 'internal'
        gv.global_constant = True
        gv.initializer = str_val
        
        # Get pointer to the first character of the string
        zero = ir.Constant(ir.IntType(32), 0)
        return builder.gep(gv, [zero, zero], name=f"arg{arg_index}_str_ptr")


@dataclass
class MemberAccess(Expression):
    object: Expression
    member: str

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Handle enum member access FIRST (before trying to codegen the identifier)
        if isinstance(self.object, Identifier):
            type_name = self.object.name
            if MemberAccessTypeHandler.is_enum_type(type_name, module):
                enum_value = MemberAccessTypeHandler.get_enum_value(type_name, self.member, module)
                return ir.Constant(ir.IntType(32), enum_value)
        
        # Check if this is a struct type
        if hasattr(module, '_struct_types'):
            obj = self.object.codegen(builder, module)
            if MemberAccessTypeHandler.is_struct_type(obj, module):
                # This is struct field access
                field_access = StructFieldAccess(self.object, self.member)
                return field_access.codegen(builder, module)
        # Handle static struct/union member access (A.x where A is a struct/union type)
        if isinstance(self.object, Identifier):
            type_name = self.object.name
            if MemberAccessTypeHandler.is_static_struct_member(type_name, module):
                # Look for the global variable representing this member
                global_name = f"{type_name}.{self.member}"
                for global_var in module.global_values:
                    if global_var.name == global_name:
                        return builder.load(global_var)
                
                raise NameError(f"Static member '{self.member}' not found in struct '{type_name}'")
            # Check for union types
            elif MemberAccessTypeHandler.is_static_union_member(type_name, module):
                # Look for the global variable representing this member
                global_name = f"{type_name}.{self.member}"
                for global_var in module.global_values:
                    if global_var.name == global_name:
                        return builder.load(global_var)
                
                raise NameError(f"Static member '{self.member}' not found in union '{type_name}'")
        
        # Handle regular member access (obj.x where obj is an instance)
        obj_val = self.object.codegen(builder, module)
        
        # Special case: if this is accessing 'this' in a method, handle the double pointer issue
        if (isinstance(self.object, Identifier) and self.object.name == "this" and \
            MemberAccessTypeHandler.is_this_double_pointer(obj_val)):
            # Load the actual 'this' pointer from the alloca
            obj_val = builder.load(obj_val, name="this_ptr")
        
        if isinstance(obj_val.type, ir.PointerType):
            # Handle pointer to struct (both literal and identified struct types)
            if MemberAccessTypeHandler.is_struct_pointer(obj_val.type):
                struct_type = obj_val.type.pointee
                
                # Check if this is actually a union (unions are implemented as structs)
                if MemberAccessTypeHandler.is_union_type(struct_type, module):
                    union_name = MemberAccessTypeHandler.get_union_name_from_type(struct_type, module)
                    # This is a union - handle union member access
                    return self._handle_union_member_access(builder, module, obj_val, union_name)
                
                # Regular struct member access
                member_index = MemberAccessTypeHandler.get_member_index(struct_type, self.member)
                
                # FIXED: Pass indices as a single list argument
                member_ptr = builder.gep(
                    obj_val,
                    [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), member_index)],
                    inbounds=True
                )
                
                # If the member is an array, return the pointer for indexing
                # If it's a struct, return the pointer for member access
                # Otherwise, load the value
                if isinstance(member_ptr.type, ir.PointerType):
                    pointee = member_ptr.type.pointee
                    if isinstance(pointee, ir.ArrayType):
                        # Return pointer to array for indexing
                        # Attach element type spec if available
                        struct_name = MemberAccessTypeHandler.get_struct_name_from_type(struct_type, module)
                        
                        if struct_name:
                            type_spec = MemberAccessTypeHandler.get_member_type_spec(struct_name, self.member, module)
                            if type_spec:
                                MemberAccessTypeHandler.attach_array_element_type_spec(member_ptr, type_spec, module)
                        
                        return member_ptr
                    elif MemberAccessTypeHandler.should_return_pointer_for_member(pointee):
                        return member_ptr  # Return pointer to struct for member access
                
                loaded = builder.load(member_ptr)
                # Preserve type metadata from struct member type
                return MemberAccessTypeHandler.attach_member_type_metadata(loaded, struct_type, self.member, module)
        
        raise ValueError(f"Member access on unsupported type: {obj_val.type}")
    
    def _handle_union_member_access(self, builder: ir.IRBuilder, module: ir.Module, union_ptr: ir.Value, union_name: str) -> ir.Value:
        """Handle union member access by casting the union to the appropriate member type"""
        # Get union member information
        union_info = MemberAccessTypeHandler.get_union_member_info(union_name, module)
        member_names = union_info['member_names']
        member_types = union_info['member_types']
        is_tagged = union_info['is_tagged']
        
        # Handle special ._ tag access for tagged unions
        if self.member == '_':
            if not is_tagged:
                raise ValueError(f"Cannot access tag '._' on non-tagged union '{union_name}'")
            
            # For tagged unions, the tag is at index 0
            tag_ptr = builder.gep(
                union_ptr,
                [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), 0)],
                inbounds=True,
                name="union_tag_ptr"
            )
            return builder.load(tag_ptr, name="union_tag_value")
        
        # Find the requested member
        MemberAccessTypeHandler.validate_union_member(union_name, self.member, module)
        
        member_index = MemberAccessTypeHandler.get_union_member_index(union_name, self.member, module)
        member_type = MemberAccessTypeHandler.get_union_member_type(union_name, self.member, module)
        
        # For tagged unions, we need to cast the data field (index 1), not the whole union
        if is_tagged:
            # Get pointer to the data field (index 1)
            data_ptr = builder.gep(
                union_ptr,
                [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), 1)],
                inbounds=True,
                name="union_data_ptr"
            )
            # Cast the data pointer to the appropriate member type pointer
            member_ptr_type = ir.PointerType(member_type)
            casted_ptr = builder.bitcast(data_ptr, member_ptr_type, name=f"union_as_{self.member}")
            return builder.load(casted_ptr, name=f"union_{self.member}_value")
        else:
            # For regular unions, cast the union pointer directly
            member_ptr_type = ir.PointerType(member_type)
            casted_ptr = builder.bitcast(union_ptr, member_ptr_type, name=f"union_as_{self.member}")
            return builder.load(casted_ptr, name=f"union_{self.member}_value")


@dataclass
class MethodCall(Expression):
    object: Expression
    method_name: str
    arguments: List[Expression] = field(default_factory=list)

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # For method calls, we need the pointer to the object, not the loaded value
        if isinstance(self.object, Identifier):
            # Look up the variable in scope to get the pointer directly
            var_name = self.object.name
            if module.symbol_table.get_llvm_value(var_name) is not None:
                obj_ptr = module.symbol_table.get_llvm_value(var_name)
            else:
                raise NameError(f"Unknown variable: {var_name}")
        else:
            # For other expressions, generate code normally
            obj_ptr = self.object.codegen(builder, module)
        
        # Determine the object's type to construct the method name
        if not isinstance(obj_ptr.type, ir.PointerType):
            raise ValueError(f"Method call internal error, expected alloca pointer, got: {obj_ptr.type}")

        slot_pointee = obj_ptr.type.pointee

        # Case A: variable is an object stored locally: slot is T* where T is struct
        if isinstance(slot_pointee, ir.IdentifiedStructType):
            this_ptr = obj_ptr  # already a pointer to the object

        # Case B: variable is a pointer to an object: slot is (T*)*  => T**
        elif isinstance(slot_pointee, ir.PointerType) and isinstance(slot_pointee.pointee, ir.IdentifiedStructType):
            this_ptr = builder.load(obj_ptr, name=f"{var_name}_load")  # load T* out of T**

        else:
            raise ValueError(f"Cannot determine object type for method call: {obj_ptr.type}")

        # Now infer the object type name from the struct type (NOT pointer)
        struct_ty = this_ptr.type.pointee
        obj_type_name = None
        if hasattr(module, "_struct_types"):
            for type_name, struct_type in module._struct_types.items():
                if struct_type == struct_ty:
                    obj_type_name = type_name
                    break
        if obj_type_name is None:
            raise ValueError(f"Cannot determine object type for method call: {struct_ty}")

        method_func_name = f"{obj_type_name}.{self.method_name}"
        # Construct the base method name (e.g., "standard__strings__string.val")
        method_func_name = f"{obj_type_name}.{self.method_name}"
        
        #print(f"[METHOD CALL] Looking for method: {method_func_name}", file=sys.stderr)
        #print(f"[METHOD CALL]   Object type: {obj_type_name}", file=sys.stderr)
        #print(f"[METHOD CALL]   Method name: {self.method_name}", file=sys.stderr)
        #print(f"[METHOD CALL]   Arguments: {len(self.arguments)}", file=sys.stderr)
        
        # Try to find the method using overload resolution
        # This is necessary because methods are now mangled with parameter/return type info
        func = module.globals.get(method_func_name, None)
        
        #if func:
        #    print(f"[METHOD CALL] Found via direct lookup!", file=sys.stderr)
        
        # If not found directly, try overload resolution
        if func is None and hasattr(module, '_function_overloads'):
            #print(f"[METHOD CALL] Trying overload resolution...", file=sys.stderr)
            if method_func_name in module._function_overloads:
                #print(f"[METHOD CALL]   Found in overloads table with {len(module._function_overloads[method_func_name])} overload(s)", file=sys.stderr)
                # We need to resolve which overload matches our arguments
                # Create a temporary FunctionCall to reuse its overload resolution
                temp_call = FunctionCall(name=method_func_name, arguments=self.arguments)
                func = temp_call._resolve_overload(builder, module, method_func_name,
                                                   module._function_overloads[method_func_name])
            #    if func:
            #        print(f"[METHOD CALL] Resolved to: {func.name}", file=sys.stderr)
            #    else:
            #        print(f"[METHOD CALL] Overload resolution returned None!", file=sys.stderr)
            #else:
            #    print(f"[METHOD CALL] Not found in overloads table", file=sys.stderr)
        
        #if func is None:
        #    print(f"[METHOD CALL] ERROR: Could not find method!", file=sys.stderr)
        if func is None:
            raise NameError(f"Unknown method: {method_func_name}")

        args = [this_ptr]  # 'this' is ALWAYS a T* now
        # (then keep your existing arg generation loop)

        for i, arg_expr in enumerate(self.arguments):
            arg_val = arg_expr.codegen(builder, module)

            # Expected type: method params include 'this' as arg0, so user args start at arg1
            expected_type = func.args[i + 1].type

            # Array-to-pointer decay: [N x i8]* -> i8* (and same for other element types)
            if (isinstance(arg_val.type, ir.PointerType) and
                isinstance(arg_val.type.pointee, ir.ArrayType) and
                isinstance(expected_type, ir.PointerType) and
                arg_val.type.pointee.element == expected_type.pointee):

                zero = ir.Constant(ir.IntType(32), 0)
                arg_val = builder.gep(arg_val, [zero, zero], name=f"marg{i}_decay")

            args.append(arg_val)

        return builder.call(func, args)

@dataclass
class ArrayAccess(Expression):
    array: Expression
    index: Expression
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Get the array (should be a pointer to array or global)
        array_val = self.array.codegen(builder, module)
        
        # This happens with scalar pointer variables like `noopstr src` (byte*)
        # which are stored as i8** but need to be loaded to i8* for array indexing
        if (isinstance(array_val.type, ir.PointerType) and 
            isinstance(array_val.type.pointee, ir.PointerType) and
            not isinstance(array_val.type.pointee.pointee, ir.ArrayType)):
            # This is T** where T is NOT an array - load to get T*
            array_val = builder.load(array_val, name="ptr_loaded_for_access")
        
        # Check if this is a range expression (array slicing)
        if isinstance(self.index, RangeExpression):
            # Delegate to ArrayLiteral for slicing
            start_val = self.index.start.codegen(builder, module)
            end_val = self.index.end.codegen(builder, module)
            
            # Determine if this is a reverse range
            is_reverse = False
            if isinstance(start_val, ir.Constant) and isinstance(end_val, ir.Constant):
                is_reverse = start_val.constant > end_val.constant
            
            return ArrayTypeHandler.slice_array(
                builder, module, array_val, start_val, end_val, is_reverse
            )
        
        # Regular single element access - generate the index expression
        index_val = self.index.codegen(builder, module)
        
        # Ensure index is i32 for GEP (LLVM requirement)
        if index_val.type != ir.IntType(32):
            if isinstance(index_val.type, ir.IntType):
                if index_val.type.width > 32:
                    index_val = builder.trunc(index_val, ir.IntType(32), name="idx_trunc")
                else:
                    index_val = builder.sext(index_val, ir.IntType(32), name="idx_ext")
        
        # Handle global arrays (like const arrays)
        if isinstance(array_val, ir.GlobalVariable):
            zero = ir.Constant(ir.IntType(32), 0)
            gep = builder.gep(array_val, [zero, index_val], inbounds=True, name="array_gep")
            # Check if the result is itself an array (multidimensional) or struct - if so, don't load
            if isinstance(gep.type, ir.PointerType):
                if isinstance(gep.type.pointee, ir.ArrayType):
                    return gep  # Return pointer to sub-array for further indexing
                elif (isinstance(gep.type.pointee, ir.LiteralStructType) or
                      hasattr(gep.type.pointee, '_name') or  # Identified struct type
                      hasattr(gep.type.pointee, 'elements')):  # Other struct-like types
                    return gep  # Return pointer to struct for member access
            loaded = builder.load(gep, name="array_load")
            # Preserve type metadata from array element type
            return ArrayTypeHandler.preserve_array_element_type_metadata(loaded, array_val, module)
        
        # Handle local arrays
        elif isinstance(array_val.type, ir.PointerType) and isinstance(array_val.type.pointee, ir.ArrayType):
            zero = ir.Constant(ir.IntType(32), 0)
            gep = builder.gep(array_val, [zero, index_val], inbounds=True, name="array_gep")
            # Check if the result is itself an array (multidimensional) or struct - if so, don't load
            if isinstance(gep.type, ir.PointerType):
                if isinstance(gep.type.pointee, ir.ArrayType):
                    return gep  # Return pointer to sub-array for further indexing
                elif (isinstance(gep.type.pointee, ir.LiteralStructType) or
                      hasattr(gep.type.pointee, '_name') or  # Identified struct type
                      hasattr(gep.type.pointee, 'elements')):  # Other struct-like types
                    return gep  # Return pointer to struct for member access
            loaded = builder.load(gep, name="array_load")
            # Preserve type metadata from array element type
            return ArrayTypeHandler.preserve_array_element_type_metadata(loaded, array_val, module)
        
        # Handle pointer types (like char*)
        elif isinstance(array_val.type, ir.PointerType):
            gep = builder.gep(array_val, [index_val], inbounds=True, name="ptr_gep")
            # Check if the result points to a struct - if so, don't load
            if isinstance(gep.type, ir.PointerType):
                if (isinstance(gep.type.pointee, ir.LiteralStructType) or
                    hasattr(gep.type.pointee, '_name') or  # Identified struct type
                    hasattr(gep.type.pointee, 'elements')):  # Other struct-like types
                    return gep  # Return pointer to struct for member access
            loaded = builder.load(gep, name="ptr_load")
            # Preserve type metadata from pointer element type
            return ArrayTypeHandler.preserve_array_element_type_metadata(loaded, array_val, module)
        
        else:
            raise ValueError(f"Cannot access array element for type: {array_val.type}")

@dataclass
class ArraySlice(Expression):
    """Slice expression using Flux syntax: base[start:end]

    NOTE: In Flux, `x..y` is a Range. This node is specifically for `[start:end]`.
    For now, codegen materializes a fixed-size array value (copy) when the slice
    length can be proven to be a compile-time constant from the AST.

    This matches existing call semantics where functions may take `T[N]` by value.
    """

    array: Expression
    start: Expression
    end: Expression

    def _try_const_len(self) -> Optional[int]:
        """Best-effort compile-time slice length inference.

        Supports common patterns like:
          - a:b where both are integer literals
          - i:i+K or i:(i+K)
          - i+K:i  (NOT supported; slice must be forward)
        """
        # Literal case
        if isinstance(self.start, Literal) and isinstance(self.end, Literal):
            if isinstance(self.start.value, int) and isinstance(self.end.value, int):
                return self.end.value - self.start.value

        # i : i + K  or  i : K + i
        if isinstance(self.end, BinaryOp) and self.end.operator == Operator.ADD:
            lhs, rhs = self.end.left, self.end.right
            # start matches lhs
            if repr(lhs) == repr(self.start) and isinstance(rhs, Literal) and isinstance(rhs.value, int):
                return rhs.value
            # start matches rhs
            if repr(rhs) == repr(self.start) and isinstance(lhs, Literal) and isinstance(lhs.value, int):
                return lhs.value

        # 0 : K
        if isinstance(self.start, Literal) and isinstance(self.start.value, int) and self.start.value == 0:
            if isinstance(self.end, Literal) and isinstance(self.end.value, int):
                return self.end.value

        return None

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        array_val = self.array.codegen(builder, module)
        start_val = self.start.codegen(builder, module)
        end_val = self.end.codegen(builder, module)

        # Indices must be i32 for GEP
        def as_i32(v: ir.Value, name: str) -> ir.Value:
            if v.type == ir.IntType(32):
                return v
            if isinstance(v.type, ir.IntType):
                if v.type.width > 32:
                    return builder.trunc(v, ir.IntType(32), name=f"{name}_trunc")
                return builder.sext(v, ir.IntType(32), name=f"{name}_ext")
            raise ValueError("Slice indices must be integers")

        start_i32 = as_i32(start_val, "slice_start")
        end_i32 = as_i32(end_val, "slice_end")

        # Flux slice semantics: [start:end] is END-EXCLUSIVE.
        const_len = self._try_const_len()
        if const_len is None:
            raise ValueError(
                "Array slice length must be statically known right now (e.g. i:i+64). "
                "The compiler couldn't prove the length as a constant."
            )
        if const_len < 0:
            raise ValueError("Array slice must be forward (start <= end)")

        # Determine element type using type handler
        elem_ty = ArrayTypeHandler.get_element_type_from_array_value(array_val)
        
        # Get pointer to first element
        zero = ir.Constant(ir.IntType(32), 0)

        if isinstance(array_val, ir.GlobalVariable) and isinstance(array_val.type.pointee, ir.ArrayType):
            src_ptr = builder.gep(array_val, [zero, start_i32], inbounds=True, name="slice_src")
        elif isinstance(array_val.type, ir.PointerType) and isinstance(array_val.type.pointee, ir.ArrayType):
            src_ptr = builder.gep(array_val, [zero, start_i32], inbounds=True, name="slice_src")
        elif isinstance(array_val.type, ir.PointerType):
            # Pointer-to-element (e.g. byte[] lowered as i8*)
            src_ptr = builder.gep(array_val, [start_i32], inbounds=True, name="slice_src")
        else:
            raise ValueError(f"Cannot slice type: {array_val.type}")

        # Materialize [const_len x elem] on the stack and memcpy.
        dst_arr_ty = ir.ArrayType(elem_ty, const_len)
        dst_alloca = builder.alloca(dst_arr_ty, name="slice_tmp")
        dst_ptr = builder.gep(dst_alloca, [zero, zero], inbounds=True, name="slice_dst")

        # Compute bytes using type handler
        elem_bytes = ArrayTypeHandler.compute_element_size_bytes(elem_ty)

        total_bytes = const_len * elem_bytes
        ArrayTypeHandler.emit_memcpy(builder, module, dst_ptr, src_ptr, total_bytes)

        # Return ARRAY VALUE (not pointer) so it can be passed to params like `byte[64]`.
        return builder.load(dst_alloca, name="slice_val")

@dataclass
class PointerDeref(Expression):
    pointer: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Generate code for the pointer expression
        ptr_val = self.pointer.codegen(builder, module)
        
        # Verify we have a pointer type
        if not isinstance(ptr_val.type, ir.PointerType):
            raise ValueError("Cannot dereference non-pointer type")
        
        # Load the value from the pointer
        return builder.load(ptr_val, name="deref")

@dataclass
class AddressOf(Expression):
    expression: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Handle address of literal (integers, bools, floats, and void for now).
        # @4 @true @3.14 @void
        if isinstance(self.expression, Literal):
            # Create storage for the literal
            literal_val = self.expression.codegen(builder, module)
            temp = builder.alloca(literal_val.type)
            builder.store(literal_val, temp)
            return temp
        # Special case: Handle Identifier directly to avoid the codegen call that might fail
        if isinstance(self.expression, Identifier):
            var_name = self.expression.name
            
            # Check if it's a local variable
            if not module.symbol_table.is_global_scope() and module.symbol_table.get_llvm_value(var_name) is not None:
                ptr = module.symbol_table.get_llvm_value(var_name)
                # Special case: if this is a function parameter that's already a pointer type
                # (like array parameters), return the loaded value directly
                if (isinstance(ptr.type, ir.PointerType) and 
                    isinstance(ptr.type.pointee, ir.PointerType)):
                    # This is a pointer to a pointer (function parameter storage)
                    # Return the loaded pointer value, not the address of the storage
                    result = builder.load(ptr, name=f"{var_name}_ptr")
                    return result
                return ptr
            
            # Check if it's a global variable
            if var_name in module.globals:
                gvar = module.globals[var_name]
                # For arrays (including string arrays like noopstr), return the global directly
                # For other pointer types, check if it's a pointer to pointer
                if (isinstance(gvar.type, ir.PointerType) and 
                    isinstance(gvar.type.pointee, ir.PointerType) and
                    not isinstance(gvar.type.pointee, ir.ArrayType)):
                    # This is a pointer to a pointer (non-array global variable storage of pointer type)
                    # Return the loaded pointer value, not the address of the storage
                    result = builder.load(gvar, name=f"{var_name}_ptr")
                    return result
                return gvar
            
            # **NEW: Check for functions (including mangled names)**
            # Try direct lookup first
            if var_name in module.globals:
                func_or_var = module.globals[var_name]
                if isinstance(func_or_var, ir.Function):
                    # Return the function directly - LLVM will handle it as a function pointer
                    # The function object itself can be used as a constant pointer value
                    return func_or_var
            
            # Try function overload resolution
            if hasattr(module, '_function_overloads') and var_name in module._function_overloads:
                overloads = module._function_overloads[var_name]
                # For function pointer assignment with @func (no arguments),
                # we need to pick the right overload
                # If there's only one overload, use it
                if len(overloads) == 1:
                    # Return the function - it will be used as a constant function pointer
                    return overloads[0]['function']
                else:
                    # Multiple overloads - need to disambiguate
                    # For now, we'll require explicit type annotation or pick 0-arg version
                    zero_arg_overload = next(
                        (o for o in overloads if o['param_count'] == 0),
                        None
                    )
                    if zero_arg_overload:
                        return zero_arg_overload['function']
                    else:
                        raise ValueError(
                            f"Ambiguous function reference '@{var_name}': "
                            f"multiple overloads exist. Please use explicit cast or "
                            f"specify parameter types."
                        )
            
            # Check for namespace-qualified names using 'using' statements
            if hasattr(module, '_using_namespaces'):
                for namespace in module._using_namespaces:
                    # Convert namespace path to mangled name format
                    mangled_prefix = namespace.replace('::', '__') + '__'
                    mangled_name = mangled_prefix + var_name
                    
                    # Check in global variables with mangled name
                    if mangled_name in module.globals:
                        gvar = module.globals[mangled_name]
                        
                        # Check if it's a function
                        if isinstance(gvar, ir.Function):
                            return gvar
                        
                        if isinstance(gvar.type, ir.PointerType):
                            # For arrays (including string arrays like noopstr), return the global directly
                            # For other pointer types, check if it's a pointer to pointer
                            if (isinstance(gvar.type.pointee, ir.PointerType) and not isinstance(gvar.type.pointee, ir.ArrayType)):
                                # This is a pointer to a pointer (non-array global variable storage of pointer type)
                                # Return the loaded pointer value, not the address of the storage
                                result = builder.load(gvar, name=f"{var_name}_ptr")
                                return result
                        return gvar
                    
                    # **NEW: Check for mangled function overloads**
                    if hasattr(module, '_function_overloads') and mangled_name in module._function_overloads:
                        overloads = module._function_overloads[mangled_name]
                        if len(overloads) == 1:
                            return overloads[0]['function']
                        else:
                            zero_arg_overload = next(
                                (o for o in overloads if o['param_count'] == 0),
                                None
                            )
                            if zero_arg_overload:
                                return zero_arg_overload['function']
            
            # If we get here, the variable/function hasn't been declared yet
            raise NameError(f"Unknown identifier: {var_name}")
        
        # Handle pointer dereference - @(*ptr) is equivalent to ptr
        if isinstance(self.expression, PointerDeref):
            # For @(*ptr), just return the pointer value directly
            # This is a fundamental identity: @(*ptr) == ptr
            return self.expression.pointer.codegen(builder, module)
        
        # Handle member access BEFORE calling codegen to avoid loading the value
        if isinstance(self.expression, MemberAccess):
            obj = self.expression.object.codegen(builder, module)
            member_name = self.expression.member
            
            if isinstance(obj.type, ir.PointerType) and isinstance(obj.type.pointee, ir.LiteralStructType):
                struct_type = obj.type.pointee
                
                if hasattr(struct_type, 'names'):
                    try:
                        idx = struct_type.names.index(member_name)
                        
                        # Return pointer to member WITHOUT loading
                        member_ptr = builder.gep(
                            obj,
                            [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), idx)],
                            inbounds=True,
                            name=f"ptr_to_{member_name}"
                        )
                        return member_ptr
                    except ValueError:
                        raise ValueError(f"Member '{member_name}' not found in struct")
        
        # Handle array access
        if isinstance(self.expression, ArrayAccess):
            array = self.expression.array.codegen(builder, module)
            index = self.expression.index.codegen(builder, module)
            
            if isinstance(array.type, ir.PointerType):
                zero = ir.Constant(ir.IntType(32), 0)
                # FIXED: Pass indices as a single list
                return builder.gep(array, [zero, index], inbounds=True)
        
        # Handle pointer dereference - @(*ptr) is equivalent to ptr
        if isinstance(self.expression, PointerDeref):
            # For @(*ptr), just return the pointer value directly
            # This is a fundamental identity: @(*ptr) == ptr
            return self.expression.pointer.codegen(builder, module)
        
        # Handle function calls - create temporary storage for the result
        elif isinstance(self.expression, FunctionCall):
            # Generate the function call result
            func_result = self.expression.codegen(builder, module)
            
            # Create temporary storage for the result
            temp_alloca = builder.alloca(func_result.type, name="func_result_temp")
            builder.store(func_result, temp_alloca)
            
            # Return pointer to the temporary storage
            return temp_alloca
        
        raise ValueError(f"Cannot take address of {type(self.expression).__name__}")

@dataclass
class AlignOf(Expression):
    target: Union[TypeSystem, Expression]

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Returns alignment in bytes for:
        - Explicitly specified alignments (data{bits:align})
        - Data types: alignment equals width in bytes (data{bits})
        - Other types: Natural alignment from target platform
        """

        align = AlignOfTypeHandler.alignof_bytes_for_target(self.target, builder, module)
        if align is not None:
            return ir.Constant(ir.IntType(32), align)

        # Fallback: evaluate expression to discover LLVM type
        val = self.target.codegen(builder, module)
        val_type = val.type.pointee if isinstance(val.type, ir.PointerType) else val.type

        align2 = AlignOfTypeHandler.alignment_from_llvm_type(val_type, module)
        if align2 is None:
            raise ValueError(f"Cannot determine alignment of type: {val_type}")

        return ir.Constant(ir.IntType(32), align2)

@dataclass
class TypeOf(Expression):
    expression: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        typeof(expr) - Returns type information (as a runtime value)
        """
        # Generate code for the expression
        val = self.expression.codegen(builder, module)
        
        # Create a type descriptor structure
        type_info = self._create_type_info(val.type, module)
        
        # Return pointer to type info
        gv = ir.GlobalVariable(module, type_info, name=f"typeinfo.{uuid.uuid4().hex}")
        gv.initializer = type_info
        gv.linkage = 'internal'
        return builder.bitcast(gv, ir.PointerType(ir.IntType(8)))

    def _create_type_info(self, llvm_type: ir.Type, module: ir.Module) -> ir.Constant:
        """Create a type descriptor constant"""
        # Basic type info structure:
        # - size (i32)
        # - alignment (i32)
        # - name (i8*)
        
        size = module.data_layout.get_type_size(llvm_type)
        align = module.data_layout.preferred_alignment(llvm_type)
        
        # Get type name
        type_name = str(llvm_type)
        name_constant = ir.Constant(ir.ArrayType(ir.IntType(8), len(type_name)),
                             bytearray(type_name.encode('ascii')))
        
        # Create struct constant
        return ir.Constant(ir.LiteralStructType([
            ir.IntType(32),  # size
            ir.IntType(32),  # alignment
            # ENDIANNESS HERE
            ir.PointerType(ir.IntType(8))  # name pointer
        ]), [
            ir.Constant(ir.IntType(32), size),
            ir.Constant(ir.IntType(32), align),
            # ENDIANNESS HERE
            builder.gep(name_constant, [ir.Constant(ir.IntType(32), 0)],
                      [ir.Constant(ir.IntType(32), 0)])
            ])

@dataclass
class SizeOf(Expression):
    target: Union[TypeSystem, Expression]

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate LLVM IR that returns size in BITS"""

        bits = SizeOfTypeHandler.sizeof_bits_for_target(self.target, builder, module)
        if bits is not None:
            return ir.Constant(ir.IntType(32), bits)

        # Fallback: evaluate expression to discover LLVM type
        value = self.target.codegen(builder, module)
        bits2 = SizeOfTypeHandler.bits_from_llvm_type(value.type, module)
        if bits2 is None:
            raise ValueError(f"Cannot determine size of type: {value.type}")

        return ir.Constant(ir.IntType(32), bits2)

@dataclass
class NoInit(Expression):
    """
    Represents the noinit keyword for uninitialized variable declarations.
    This is a special marker expression that indicates a variable should not
    be automatically initialized to zero.
    
    Example:
        int x = noinit;  // x is declared but not initialized
    
    Note: This expression type should never generate code directly - it is
    handled specially in VariableDeclaration.codegen()
    """
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> None:
        """
        NoInit should never be code-generated directly.
        It's a compile-time marker that's handled in VariableDeclaration.
        """
        raise RuntimeError(
            "noinit is a compile-time marker and should not generate code directly. "
            "It should only be used as an initializer in variable declarations."
        )

# Variable declarations
@dataclass
class VariableDeclaration(ASTNode):
    name: str
    type_spec: TypeSystem
    initial_value: Optional[Expression] = None
    is_global: bool = False

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Resolve type (with automatic array size inference if needed)
        resolved_type_spec = VariableTypeHandler.infer_array_size(self.type_spec, self.initial_value, module)
        llvm_type = TypeSystem.get_llvm_type(resolved_type_spec, module, include_array=True)
        #print(f"[VAR DECL] name={self.name}, type_spec={resolved_type_spec}, llvm_type={llvm_type}", file=sys.stderr)
        
        # Check if this is global scope
        is_global_scope = (
            builder is None or 
            self.is_global or 
            module.symbol_table.is_global_scope()
        )
        
        # Handle global variables
        if is_global_scope:
            return self._codegen_global(module, llvm_type, resolved_type_spec)
        
        # Handle local variables
        return self._codegen_local(builder, module, llvm_type, resolved_type_spec)
    
    def _codegen_global(self, module: ir.Module, llvm_type: ir.Type, 
                       resolved_type_spec: TypeSystem) -> ir.Value:
        """Generate code for global variable."""
        # Check if global already exists
        if self.name in module.globals:
            return module.globals[self.name]
        
        # Check for namespaced duplicates
        base_name = self.name.split('__')[-1]
        for existing_name in list(module.globals.keys()):
            existing_base_name = existing_name.split('__')[-1]
            if existing_base_name == base_name and existing_name != self.name:
                return module.globals[existing_name]
            elif existing_name == self.name:
                return module.globals[existing_name]
        
        # Create new global
        gvar = ir.GlobalVariable(module, llvm_type, self.name)
        
        # Handle noinit for global variables
        if isinstance(self.initial_value, NoInit):
            # Global variables in LLVM IR require an initializer
            # Use Undefined to represent uninitialized state
            # This is the LLVM equivalent of "no initialization"
            gvar.initializer = ir.Undefined(llvm_type)
        # Set initializer if value provided
        elif self.initial_value:
            init_const = self._create_global_initializer(module, llvm_type)
            if init_const is not None:
                gvar.initializer = init_const
            else:
                gvar.initializer = TypeSystem.get_default_initializer(llvm_type)
        else:
            # Default behavior: zero-initialize
            gvar.initializer = TypeSystem.get_default_initializer(llvm_type)
        
        gvar.linkage = 'internal'
        
        # Register global variable in symbol table
        if hasattr(module, 'symbol_table'):
            #print(f"[GLOBAL VAR] Registering global variable '{self.name}' in symbol table", file=sys.stderr)
            module.symbol_table.define(
                self.name,
                SymbolKind.VARIABLE,
                type_spec=resolved_type_spec,
                llvm_type=llvm_type,
                llvm_value=gvar
            )
        
        return gvar
    
    def _create_global_initializer(self, module: ir.Module, llvm_type: ir.Type) -> Optional[ir.Constant]:
        """Create compile-time constant initializer for global variable."""
        return VariableTypeHandler.create_global_initializer(self.initial_value, llvm_type, module)
    
    def _codegen_local(self, builder: ir.IRBuilder, module: ir.Module, 
                      llvm_type: ir.Type, resolved_type_spec: TypeSystem) -> ir.Value:
        """Generate code for local variable."""
        alloca = builder.alloca(llvm_type, name=self.name)
        
        # Type information is now stored in symbol table during define()

        # Handle noinit keyword - skip initialization entirely
        if isinstance(self.initial_value, NoInit):
            # Mark variable as explicitly uninitialized for tracking
            if not hasattr(builder, 'uninitialized_vars'):
                builder.uninitialized_vars = set()
            builder.uninitialized_vars.add(self.name)
            # Do NOT initialize the alloca - it will contain undefined value
        # Initialize variable if value is provided (and it's not noinit)
        elif self.initial_value:
            self._initialize_local(builder, module, alloca, llvm_type)
        # If no initial_value at all, Flux currently zero-initializes
        # This maintains backward compatibility with existing behavior
        
        # Register in scope
        #print(f"[LOCAL VAR] Registering local variable '{self.name}' in scope level {module.symbol_table.scope_level}", file=sys.stderr)
        #print(f"[LOCAL VAR]   Scopes count: {len(module.symbol_table.scopes)}", file=sys.stderr)
        module.symbol_table.define(self.name, SymbolKind.VARIABLE, type_spec=resolved_type_spec, llvm_value=alloca)
        #print(f"[LOCAL VAR]   Variable '{self.name}' registered successfully", file=sys.stderr)
        if resolved_type_spec.is_volatile:
            if not hasattr(builder, 'volatile_vars'):
                builder.volatile_vars = set()
            builder.volatile_vars.add(self.name)
        
        return alloca
    
    def _initialize_local(self, builder: ir.IRBuilder, module: ir.Module, 
                         alloca: ir.Value, llvm_type: ir.Type) -> None:
        """Initialize local variable with initial value."""
        # Handle array instance initialization
        if isinstance(self.initial_value, ArrayLiteral):
            # If target is an integer, pack the array into it
            if isinstance(llvm_type, ir.IntType):
                packed_val = ArrayTypeHandler.pack_array_to_integer(builder, module, self.initial_value, llvm_type)
                builder.store(packed_val, alloca)
            # Otherwise, initialize as array
            else:
                ArrayTypeHandler.initialize_local_array(builder, module, alloca, llvm_type, self.initial_value)
            return

        if isinstance(self.initial_value, ArrayComprehension):
            comp_result = self.initial_value.codegen(builder, module)
            # comp_result is [5 x i32]*, alloca is [5 x i32]*
            # Load from comp_result and store into alloca
            loaded_array = builder.load(comp_result, name="comp_array_load")
            builder.store(loaded_array, alloca)
            return
        
        # Delegate string literal initialization to ArrayLiteral
        if isinstance(self.initial_value, StringLiteral):
            ArrayTypeHandler.initialize_local_string(
                builder, module, alloca, llvm_type, self.initial_value)
            return
        
        # Handle constructor calls
        if isinstance(self.initial_value, FunctionCall) and self.initial_value.name.endswith('.__init'):
            self._call_constructor(builder, module, alloca)
            return
        
        # Handle array-to-array copy
        if isinstance(llvm_type, ir.ArrayType) and isinstance(self.initial_value, Identifier):
            ArrayTypeHandler.copy_array_to_local(
                builder, module, alloca, llvm_type, self.initial_value
            )
            return
        
        # Handle regular initialization
        init_val = self.initial_value.codegen(builder, module)
        if init_val is not None:
            self._store_with_type_conversion(builder, alloca, llvm_type, init_val)
    
    def _call_constructor(self, builder: ir.IRBuilder, module: ir.Module, alloca: ir.Value) -> None:
        """Call constructor for object initialization using proper overload resolution."""
        # Use the FunctionCall's existing resolution logic to find the constructor
        # This handles namespace resolution, overloading, and name mangling properly
        func_call = self.initial_value  # This is a FunctionCall with name like "string.__init"
        
        print(f"[CONSTRUCTOR] Looking for constructor: {func_call.name}", file=sys.stderr)
        print(f"[CONSTRUCTOR] Available globals matching pattern:", file=sys.stderr)
        for name in module.globals:
            if '__init' in name:
                print(f"  - {name}", file=sys.stderr)
        
        if hasattr(module, '_function_overloads'):
            print(f"[CONSTRUCTOR] Available overloads:", file=sys.stderr)
            for base_name in module._function_overloads:
                if '__init' in base_name or 'string' in base_name:
                    print(f"  - {base_name}: {len(module._function_overloads[base_name])} overload(s)", file=sys.stderr)
        
        # Try to resolve the constructor using the same multi-step resolution as regular calls
        func = None
        
        # Step 1: Try direct lookup
        func = module.globals.get(func_call.name, None)
        if func and isinstance(func, ir.Function):
            print(f"[CONSTRUCTOR] Found via direct lookup: {func_call.name}", file=sys.stderr)
            pass  # Found it
        else:
            print("[CONSTRUCTOR] ATTEMPTING OVERLOAD RESOLUTION", file=sys.stderr)
            # Step 2: Try overload resolution
            if hasattr(module, '_function_overloads') and func_call.name in module._function_overloads:
                func = func_call._resolve_overload(builder, module, func_call.name, 
                                                   module._function_overloads[func_call.name])
                if func:
                    print(f"[CONSTRUCTOR] Found via overload resolution: {func_call.name}", file=sys.stderr)
        
        # Step 3: Try namespace resolution if still not found
        if func is None and hasattr(module, '_using_namespaces'):
            print("[CONSTRUCTOR] NOT FOUND, USING NAMESPACE RESOLUTION", file=sys.stderr)
            for namespace in module._using_namespaces:
                print(f"[CONSTRUCTOR]   Trying namespace: {namespace}", file=sys.stderr)
                mangled_prefix = namespace.replace("::", "__") + "__"
                mangled_name = mangled_prefix + func_call.name
                print(f"[CONSTRUCTOR]   Mangled name: {mangled_name}", file=sys.stderr)
                
                # Try direct lookup with namespace prefix
                func = module.globals.get(mangled_name, None)
                if func and isinstance(func, ir.Function):
                    print(f"[CONSTRUCTOR] Found via namespace direct lookup: {mangled_name}", file=sys.stderr)
                    break
                
                # Try overload resolution with namespace prefix
                if hasattr(module, '_function_overloads'):
                    print(f"[CONSTRUCTOR]   Checking overloads for: {mangled_name}", file=sys.stderr)
                    if mangled_name in module._function_overloads:
                        print(f"[CONSTRUCTOR]   FOUND in overloads!", file=sys.stderr)
                        func = func_call._resolve_overload(builder, module, mangled_name,
                                                           module._function_overloads[mangled_name])
                        if func:
                            print(f"[CONSTRUCTOR] Found via namespace overload resolution: {mangled_name}", file=sys.stderr)
                            break
        
        if func is None:
            raise NameError(f"Constructor not found: {func_call.name}")
        
        # Build arguments: 'this' pointer first, then constructor arguments
        args = [alloca]

        for i, arg_expr in enumerate(func_call.arguments):
            param_index = i + 1
            if (isinstance(arg_expr, StringLiteral) and
                param_index < len(func.args) and
                isinstance(func.args[param_index].type, ir.PointerType) and
                isinstance(func.args[param_index].type.pointee, ir.IntType) and
                func.args[param_index].type.pointee.width == 8):
                
                arg_val = ArrayTypeHandler.create_local_string_for_arg(
                    builder, module, arg_expr.value, f"ctor_arg{i}"
                )
            else:
                arg_val = arg_expr.codegen(builder, module)
            
            args.append(arg_val)
        
        builder.call(func, args)
    
    def _store_with_type_conversion(self, builder: ir.IRBuilder, alloca: ir.Value, 
                                    llvm_type: ir.Type, init_val: ir.Value) -> None:
        """Store value with automatic type conversion if needed."""
        VariableTypeHandler.store_with_type_conversion(builder, alloca, llvm_type, init_val, self.initial_value, builder.module)

# Type declarations
@dataclass
class TypeDeclaration(Expression):
    """AST node for type declarations using AS keyword"""
    name: str
    type_spec: TypeSystem
    initial_value: Optional[Expression] = None
    
    def __repr__(self):
        init_str = f" = {self.initial_value}" if self.initial_value else ""
        return f"TypeDeclaration({self.type_spec} as {self.name}{init_str})"
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Use TypeSystem's proper resolution instead of guessing
        llvm_type = TypeSystem.get_llvm_type(self.type_spec, module, include_array=True)
        
        # Register the type alias
        if not hasattr(module, '_type_aliases'):
            module._type_aliases = {}
        module._type_aliases[self.name] = llvm_type
        
        if not hasattr(module, "_type_alias_specs"):
            module._type_alias_specs = {}
        module._type_alias_specs[self.name] = self.type_spec
        
        # Register type alias in symbol table
        if hasattr(module, 'symbol_table'):
            #print(f"[TYPE ALIAS] Registering type alias '{self.name}' in symbol table", file=sys.stderr)
            module.symbol_table.define(
                self.name,
                SymbolKind.TYPE,
                type_spec=self.type_spec,
                llvm_type=llvm_type,
                llvm_value=None
            )
        
        # If there's an initial value, create a global constant
        if self.initial_value:
            init_val = self.initial_value.codegen(builder, module)
            gvar = ir.GlobalVariable(module, llvm_type, self.name)
            gvar.linkage = 'internal'
            gvar.global_constant = True
            gvar.initializer = init_val
            return gvar
        
        return None

# Statements
@dataclass
class Statement(ASTNode):
    pass

@dataclass
class ExpressionStatement(Statement):
    expression: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        return self.expression.codegen(builder, module)

@dataclass
class Assignment(Statement):
    target: Expression
    value: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        
        # Generate code for the value to be assigned
        val = self.value.codegen(builder, module)
        
        # Handle different types of targets
        if isinstance(self.target, Identifier):
            # Simple variable assignment - delegate to type handler
            return AssignmentTypeHandler.handle_identifier_assignment(
                builder, module, self.target.name, val, self.value)
            
        elif isinstance(self.target, MemberAccess):
            # Struct/union/object member assignment - delegate to type handler
            return AssignmentTypeHandler.handle_member_assignment(
                builder, module, self.target.object, self.target.member, val)
    
        elif isinstance(self.target, ArrayAccess):
            # Array element assignment - delegate to type handler
            return AssignmentTypeHandler.handle_array_element_assignment(
                builder, module, self.target.array, self.target.index, self.value, val)
                
        elif isinstance(self.target, PointerDeref):
            # Pointer dereference assignment - delegate to type handler
            ptr = self.target.pointer.codegen(builder, module)
            if (isinstance(ptr.type, ir.PointerType) and 
                isinstance(ptr.type.pointee, ir.PointerType)):
                # Load the pointer value
                ptr = builder.load(ptr, name="deref_ptr_loaded")
            return AssignmentTypeHandler.handle_pointer_deref_assignment(builder, ptr, val)
                
        else:
            raise ValueError(f"Cannot assign to {type(self.target).__name__}")

@dataclass
class CompoundAssignment(Statement):
    target: Expression
    op_token: Any  # TokenType enum for the compound operator  
    value: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate code for compound assignments like +=, -=, *=, /=, %="""
        
        return AssignmentTypeHandler.handle_compound_assignment(
            builder, module, self.target, self.op_token, self.value)
    
@dataclass
class Block(Statement):
    statements: List[Statement] = field(default_factory=list)

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        debug = False
        if debug:
            current_frame = inspect.currentframe()
            caller_frame = current_frame.f_back
            caller_name = caller_frame.f_code.co_name
            stack = inspect.stack()
            print("Full call stack (from current to outermost):")
            for i, frame_info in enumerate(reversed(stack)):
                print(f"  {i}: {frame_info.function}() in {frame_info.filename}:{frame_info.lineno}")

        result = None
        #print(self.statements)
        #print(f"DEBUG Block: Processing {len(self.statements)} statements")
        for i, stmt in enumerate(self.statements):
            #print(f"DEBUG Block: Processing statement {i}: {type(stmt).__name__}")
            if stmt is not None:  # Skip None statements
                try:
                    #traceback.print_exc()
                    stmt_result = stmt.codegen(builder, module)
                    if stmt_result is not None:  # Only update result if not None
                        result = stmt_result
                except Exception as e:
                    raise ValueError(f"Block{{}} Debug: Error in statement {i} ({type(stmt).__name__}): {e} \n\n {stmt} \n\n {module.name}")
        return result


@dataclass
class IRStore(Expression):
    """
    Wrapper that holds a pre-computed IR value.
    Used to substitute placeholders in acceptor blocks with their evaluated results.
    """
    ir_value: ir.Value
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        return self.ir_value


@dataclass
class AcceptorPlaceholder(Expression):
    """
    Represents :(N) placeholder in acceptor blocks.
    
    Example:
        {:(1) + :(2)}  // Two placeholders with indices 1 and 2
    
    These should be substituted with IRStore nodes before codegen is called.
    """
    index: int
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        raise RuntimeError(
            f"AcceptorPlaceholder :({self.index}) should be substituted before codegen. "
            f"This indicates a bug in the acceptor block implementation."
        )


@dataclass
class AcceptorBlock(Expression):
    """
    Represents acceptor block syntax for collecting multiple function results.
    
    Syntax:
        {expression_with_placeholders} <- N:function_call <- N:function_call ...
    
    Example:
        {2 * :(1) * :(2)} <- 1:sqrt(36) <- 2:foo(256)
    
    Execution:
        1. Evaluates labeled inputs in numeric order (1, 2, 3...)
        2. Substitutes placeholders with evaluated values
        3. Evaluates the final expression
    
    Fields:
        expression: The block expression containing AcceptorPlaceholder nodes
        labeled_inputs: List of (label_number, function_call) tuples
    """
    expression: Expression
    labeled_inputs: List[Tuple[int, Expression]]
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Sort inputs by label to ensure execution order (1, 2, 3...)
        sorted_inputs = sorted(self.labeled_inputs, key=lambda x: x[0])
        
        # Evaluate each labeled input in order
        placeholder_values = {}
        for label, expr in sorted_inputs:
            value = expr.codegen(builder, module)
            placeholder_values[label] = value
        
        # Substitute placeholders with IRStore nodes containing evaluated values
        substituted_expr = self._substitute_placeholders(self.expression, placeholder_values)
        
        # Evaluate the final expression
        return substituted_expr.codegen(builder, module)
    
    def _substitute_placeholders(self, expr: Expression, values: Dict[int, ir.Value]) -> Expression:
        """
        Recursively walk the expression tree and replace AcceptorPlaceholder nodes
        with IRStore nodes containing the pre-computed values.
        """
        if isinstance(expr, AcceptorPlaceholder):
            if expr.index not in values:
                raise RuntimeError(
                    f"Placeholder :({expr.index}) referenced but no corresponding "
                    f"labeled input provided"
                )
            return IRStore(values[expr.index])
        
        # Handle BinaryOp
        if isinstance(expr, BinaryOp):
            return BinaryOp(
                left=self._substitute_placeholders(expr.left, values),
                operator=expr.operator,
                right=self._substitute_placeholders(expr.right, values)
            )
        
        # Handle UnaryOp
        if isinstance(expr, UnaryOp):
            return UnaryOp(
                operator=expr.operator,
                operand=self._substitute_placeholders(expr.operand, values)
            )
        
        # Handle FunctionCall
        if isinstance(expr, FunctionCall):
            return FunctionCall(
                name=expr.name,
                arguments=[self._substitute_placeholders(arg, values) for arg in expr.arguments],
                type_arguments=expr.type_arguments if hasattr(expr, 'type_arguments') else None
            )
        
        # Handle ArrayAccess
        if isinstance(expr, ArrayAccess):
            return ArrayAccess(
                array=self._substitute_placeholders(expr.array, values),
                index=self._substitute_placeholders(expr.index, values)
            )
        
        # Handle MemberAccess
        if isinstance(expr, MemberAccess):
            return MemberAccess(
                object=self._substitute_placeholders(expr.object, values),
                member=expr.member
            )
        
        # Handle Cast
        if isinstance(expr, Cast):
            return Cast(
                expression=self._substitute_placeholders(expr.expression, values),
                target_type=expr.target_type
            )
        
        # Handle TernaryOp
        if isinstance(expr, TernaryOp):
            return TernaryOp(
                condition=self._substitute_placeholders(expr.condition, values),
                true_expr=self._substitute_placeholders(expr.true_expr, values),
                false_expr=self._substitute_placeholders(expr.false_expr, values)
            )
        
        # Handle nested AcceptorBlock
        if isinstance(expr, AcceptorBlock):
            return AcceptorBlock(
                expression=self._substitute_placeholders(expr.expression, values),
                labeled_inputs=[(label, self._substitute_placeholders(inp, values)) 
                               for label, inp in expr.labeled_inputs]
            )
        
        # For literals, identifiers, and other leaf nodes, return as-is
        # (they don't contain placeholders)
        return expr

@dataclass
class IfStatement(Statement):
    condition: Expression
    then_block: Block
    elif_blocks: List[tuple] = field(default_factory=list)  # (condition, block) pairs
    else_block: Optional[Block] = None

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Check if we're in global scope (conditional compilation)
        if builder.block is None:
            return self._codegen_global_scope(builder, module)
        
        # Normal if statement inside a function
        # Generate condition
        try:
            cond_val = self.condition.codegen(builder, module)
        except Exception as e:
            print(f"if statement condition: {e}")
        
        # Create basic blocks
        func = builder.block.function
        then_block = func.append_basic_block('then')
        else_block = func.append_basic_block('else')
        merge_block = func.append_basic_block('ifcont')
        
        builder.cbranch(cond_val, then_block, else_block)
        
        # Emit then block
        builder.position_at_start(then_block)
        self.then_block.codegen(builder, module)
        if not builder.block.is_terminated:
            builder.branch(merge_block)
        
        # Emit else block (which may contain elif chain)
        builder.position_at_start(else_block)
        
        # Process elif blocks as a chain
        current_block = else_block
        for i, (elif_cond, elif_body) in enumerate(self.elif_blocks):
            # Generate the elif condition
            elif_cond_val = elif_cond.codegen(builder, module)
            
            # Create blocks for this elif
            elif_then = func.append_basic_block(f'elif_then_{i}')
            elif_else = func.append_basic_block(f'elif_else_{i}')
            
            # Branch based on elif condition
            builder.cbranch(elif_cond_val, elif_then, elif_else)
            
            # Emit elif body
            builder.position_at_start(elif_then)
            elif_body.codegen(builder, module)
            if not builder.block.is_terminated:
                builder.branch(merge_block)
            
            # Continue in the elif_else block for next elif or final else
            builder.position_at_start(elif_else)
            current_block = elif_else
        
        # After all elifs, emit the final else block if present
        if self.else_block:
            self.else_block.codegen(builder, module)
        
        # Branch to merge if not already terminated
        if not builder.block.is_terminated:
            builder.branch(merge_block)
        
        # Position builder at merge block
        builder.position_at_start(merge_block)
        return None
    
    def _codegen_global_scope(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Handle if statements at global scope (conditional compilation)"""
        # Evaluate condition at compile time
        try:
            # Try to evaluate the condition
            cond_val = self.condition.codegen(builder, module)
            
            # For compile-time conditionals (like def() checks), we get a constant
            if isinstance(cond_val, ir.Constant):
                # Evaluate the constant boolean value
                if cond_val.constant:
                    # Condition is true - execute then block
                    self.then_block.codegen(builder, module)
                else:
                    # Condition is false - check elif blocks or execute else
                    executed = False
                    for elif_cond, elif_block in self.elif_blocks:
                        elif_val = elif_cond.codegen(builder, module)
                        if isinstance(elif_val, ir.Constant) and elif_val.constant:
                            elif_block.codegen(builder, module)
                            executed = True
                            break
                    
                    if not executed and self.else_block:
                        self.else_block.codegen(builder, module)
            else:
                # Runtime condition in global scope - not supported
                raise RuntimeError("Cannot use runtime conditions in global scope if statements")
        except Exception as e:
            raise RuntimeError(f"Warning: Could not evaluate global if condition: {e}")
            # Default to executing the then block for safety
            #self.then_block.codegen(builder, module)
        
        return None

@dataclass
class TernaryOp(Expression):
    """
    Ternary conditional operator: condition ? true_expr : false_expr
    
    Example:
        x > 0 ? x : -x  // Absolute value
        a == b ? 1 : 0  // Boolean to int
    """
    condition: Expression
    true_expr: Expression
    false_expr: Expression
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Generate code for ternary operator.
        
        Creates:
        1. Evaluate condition
        2. Branch to true_block or false_block
        3. Evaluate true_expr in true_block
        4. Evaluate false_expr in false_block
        5. Use phi node to merge results
        """
        # Evaluate condition
        cond_val = self.condition.codegen(builder, module)
        
        # Convert to i1 if needed
        if isinstance(cond_val.type, ir.IntType) and cond_val.type.width != 1:
            cond_val = builder.icmp_signed('!=', cond_val, ir.Constant(cond_val.type, 0))
        
        # Create blocks
        func = builder.block.function
        true_block = func.append_basic_block('ternary_true')
        false_block = func.append_basic_block('ternary_false')
        merge_block = func.append_basic_block('ternary_merge')
        
        # Branch based on condition
        builder.cbranch(cond_val, true_block, false_block)
        
        # Generate true branch
        builder.position_at_start(true_block)
        true_val = self.true_expr.codegen(builder, module)
        true_end_block = builder.block  # May have changed due to nested control flow
        builder.branch(merge_block)
        
        # Generate false branch
        builder.position_at_start(false_block)
        false_val = self.false_expr.codegen(builder, module)
        false_end_block = builder.block  # May have changed due to nested control flow
        builder.branch(merge_block)
        
        # Merge results with phi node
        builder.position_at_start(merge_block)
        
        # Type compatibility check
        if true_val.type != false_val.type:
            # Try to convert types
            if isinstance(true_val.type, ir.IntType) and isinstance(false_val.type, ir.IntType):
                # Integer type mismatch - extend to larger type
                if true_val.type.width < false_val.type.width:
                    builder.position_at_end(true_end_block)
                    true_val = builder.sext(true_val, false_val.type)
                    builder.branch(merge_block)
                    builder.position_at_start(merge_block)
                elif false_val.type.width < true_val.type.width:
                    builder.position_at_end(false_end_block)
                    false_val = builder.sext(false_val, true_val.type)
                    builder.branch(merge_block)
                    builder.position_at_start(merge_block)
            else:
                raise TypeError(
                    f"Ternary operator branches have incompatible types: "
                    f"{true_val.type} vs {false_val.type}"
                )
        
        # Create phi node to select result
        phi = builder.phi(true_val.type, name='ternary_result')
        phi.add_incoming(true_val, true_end_block)
        phi.add_incoming(false_val, false_end_block)
        
        return phi

@dataclass
class NullCoalesce(Expression):
    """
    Null coalescing operator: value ?? default
    
    Returns the left operand if it's not null/zero, otherwise returns the right operand.
    
    Example:
        ptr ?? default_ptr     // Use ptr if non-null, else default_ptr
        x ?? 0                 // Use x if non-zero, else 0
    """
    left: Expression
    right: Expression
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Generate code for null coalesce operator.
        
        Similar to: left != null ? left : right
        But we only evaluate left once.
        """
        # Evaluate left operand
        left_val = self.left.codegen(builder, module)
        
        # Check if left is null/zero
        if isinstance(left_val.type, ir.PointerType):
            # Pointer - compare to null pointer
            null_ptr = ir.Constant(left_val.type, None)
            is_null = builder.icmp_unsigned('==', left_val, null_ptr, name='is_null')
        elif isinstance(left_val.type, ir.IntType):
            # Integer - compare to zero
            zero = ir.Constant(left_val.type, 0)
            is_null = builder.icmp_signed('==', left_val, zero, name='is_zero')
        else:
            raise TypeError(f"Null coalesce not supported for type: {left_val.type}")
        
        # Create blocks
        func = builder.block.function
        right_block = func.append_basic_block('coalesce_right')
        merge_block = func.append_basic_block('coalesce_merge')
        left_block = builder.block
        
        # Branch: if null, evaluate right; else skip to merge
        builder.cbranch(is_null, right_block, merge_block)
        
        # Right block - evaluate default value
        builder.position_at_start(right_block)
        right_val = self.right.codegen(builder, module)
        right_end_block = builder.block
        builder.branch(merge_block)
        
        # Merge block - phi node
        builder.position_at_start(merge_block)
        
        # Type compatibility check
        if left_val.type != right_val.type:
            # Try to convert types
            if isinstance(left_val.type, ir.IntType) and isinstance(right_val.type, ir.IntType):
                if left_val.type.width < right_val.type.width:
                    # Extend left to match right
                    builder.position_at_end(left_block)
                    left_val = builder.sext(left_val, right_val.type)
                    builder.branch(merge_block)
                    builder.position_at_start(merge_block)
                elif right_val.type.width < left_val.type.width:
                    # Extend right to match left
                    builder.position_at_end(right_end_block)
                    right_val = builder.sext(right_val, left_val.type)
                    builder.branch(merge_block)
                    builder.position_at_start(merge_block)
            else:
                raise TypeError(
                    f"Null coalesce operands have incompatible types: "
                    f"{left_val.type} vs {right_val.type}"
                )
        
        # Phi node to select result
        phi = builder.phi(left_val.type, name='coalesce_result')
        phi.add_incoming(left_val, left_block)
        phi.add_incoming(right_val, right_end_block)
        
        return phi

@dataclass
class WhileLoop(Statement):
    condition: Expression
    body: Block
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        func = builder.block.function
        cond_block = func.append_basic_block('while.cond')
        body_block = func.append_basic_block('while.body')
        end_block = func.append_basic_block('while.end')
        
        # Save current break/continue targets
        old_break = getattr(builder, 'break_block', None)
        old_continue = getattr(builder, 'continue_block', None)
        builder.break_block = end_block
        builder.continue_block = cond_block
        
        # Jump to condition block
        builder.branch(cond_block)
        
        # Emit condition block
        builder.position_at_start(cond_block)
        cond_val = self.condition.codegen(builder, module)
        builder.cbranch(cond_val, body_block, end_block)
        
        # Emit body block
        builder.position_at_start(body_block)
        self.body.codegen(builder, module)
        
        # Only branch back if body didn't terminate (no break/return)
        if not builder.block.is_terminated:
            builder.branch(cond_block)  # Loop back
        
        # Restore break/continue targets
        builder.break_block = old_break
        builder.continue_block = old_continue
        
        # Position builder at end block
        builder.position_at_start(end_block)
        return None

@dataclass
class DoLoop(Statement):
    """Plain do loop - executes body once"""
    body: Block

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # A plain do loop just executes the body once
        # It's essentially just a block with break/continue support
        
        if builder.block is None:
            # For global scope, create a temporary function
            func_type = ir.FunctionType(ir.VoidType(), [])
            temp_func = ir.Function(module, func_type, name="__do_temp")
            temp_block = temp_func.append_basic_block("entry")
            temp_builder = ir.IRBuilder(temp_block)
            
            # Generate using temporary builder
            self._generate_loop(temp_builder, module)
            temp_builder.ret_void()
            return None
        else:
            return self._generate_loop(builder, module)

    def _generate_loop(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Internal method that generates the actual loop structure"""
        func = builder.block.function
        
        # Create blocks
        body_block = func.append_basic_block('do.body')
        end_block = func.append_basic_block('do.end')
        
        # Save current break/continue targets
        old_break = getattr(builder, 'break_block', None)
        old_continue = getattr(builder, 'continue_block', None)
        builder.break_block = end_block
        builder.continue_block = body_block  # Continue jumps back to start of body
        
        # Jump to body
        builder.branch(body_block)
        
        # Generate the body
        builder.position_at_start(body_block)
        self.body.codegen(builder, module)
        
        # If body didn't terminate (no break/return), loop back to body (infinite loop)
        if not builder.block.is_terminated:
            builder.branch(body_block)
        
        # Restore break/continue targets
        builder.break_block = old_break
        builder.continue_block = old_continue
        
        # Position builder at end block
        builder.position_at_start(end_block)
        return None

@dataclass
class DoWhileLoop(Statement):
    body: Block
    condition: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Get the current function or create a temporary one if in global scope
        if builder.block is None:
            # For global scope, create a temporary function and builder
            func_type = ir.FunctionType(ir.VoidType(), [])
            temp_func = ir.Function(module, func_type, name="__dowhile_temp")
            temp_block = temp_func.append_basic_block("entry")
            temp_builder = ir.IRBuilder(temp_block)
            
            # Generate the loop using the temporary builder
            self._generate_loop(temp_builder, module)
            
            # Terminate the temporary function
            temp_builder.ret_void()
            return None
        else:
            # Normal case - we're inside a function
            return self._generate_loop(builder, module)

    def _generate_loop(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Internal method that generates the actual loop structure"""
        func = builder.block.function
        
        # Create blocks for the loop
        body_block = func.append_basic_block('dowhile.body')
        cond_block = func.append_basic_block('dowhile.cond')
        end_block = func.append_basic_block('dowhile.end')
        
        # Save current break/continue targets
        old_break = getattr(builder, 'break_block', None)
        old_continue = getattr(builder, 'continue_block', None)
        builder.break_block = end_block
        builder.continue_block = cond_block
        
        # Jump to the body block (do-while always executes body first)
        builder.branch(body_block)
        
        # Generate the body
        builder.position_at_start(body_block)
        self.body.codegen(builder, module)
        
        # If body didn't terminate, branch to condition
        if not builder.block.is_terminated:
            builder.branch(cond_block)
        
        # Generate the condition
        builder.position_at_start(cond_block)
        cond_val = self.condition.codegen(builder, module)
        builder.cbranch(cond_val, body_block, end_block)
        
        # Restore break/continue targets
        builder.break_block = old_break
        builder.continue_block = old_continue
        
        # Position builder at end block
        builder.position_at_start(end_block)
        return None

@dataclass
class ForLoop(Statement):
    init: Optional[Statement]
    condition: Optional[Expression]
    update: Optional[Statement]
    body: Block

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Create basic blocks
        func = builder.block.function
        cond_block = func.append_basic_block('for.cond')
        body_block = func.append_basic_block('for.body')
        update_block = func.append_basic_block('for.update')
        end_block = func.append_basic_block('for.end')

        # Generate initialization
        if self.init:
            self.init.codegen(builder, module)

        # Jump to condition block
        builder.branch(cond_block)

        # Condition block
        builder.position_at_start(cond_block)
        if self.condition:
            cond_val = self.condition.codegen(builder, module)
            builder.cbranch(cond_val, body_block, end_block)
        else:  # Infinite loop if no condition
            builder.branch(body_block)

        # Body block
        builder.position_at_start(body_block)
        old_break = getattr(builder, 'break_block', None)
        old_continue = getattr(builder, 'continue_block', None)
        builder.break_block = end_block
        builder.continue_block = update_block
        
        self.body.codegen(builder, module)
        
        if not builder.block.is_terminated:
            builder.branch(update_block)

        # Update block
        builder.position_at_start(update_block)
        if self.update:
            self.update.codegen(builder, module)
        builder.branch(cond_block)  # Loop back

        # Restore break/continue
        builder.break_block = old_break
        builder.continue_block = old_continue

        # End block
        builder.position_at_start(end_block)
        return None

@dataclass
class ForInLoop(Statement):
    variables: List[str]
    iterable: Expression
    body: Block

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Generate the iterable value
        collection = self.iterable.codegen(builder, module)
        coll_type = collection.type

        # Create basic blocks
        func = builder.block.function
        entry_block = builder.block
        cond_block = func.append_basic_block('forin.cond')
        body_block = func.append_basic_block('forin.body')
        end_block = func.append_basic_block('forin.end')

        # Handle different iterable types
        if isinstance(coll_type, ir.PointerType) and isinstance(coll_type.pointee, ir.ArrayType):
            # Array iteration
            arr_type = coll_type.pointee
            size = arr_type.count
            elem_type = arr_type.element
            
            # Create index variable
            index_ptr = builder.alloca(ir.IntType(32), name='forin.idx')
            builder.store(ir.Constant(ir.IntType(32), 0), index_ptr)
            
            # Jump to condition
            builder.branch(cond_block)
            
            # Condition block
            builder.position_at_start(cond_block)
            current_idx = builder.load(index_ptr, name='idx')
            cmp = builder.icmp_unsigned('<', current_idx, 
                                      ir.Constant(ir.IntType(32), size), 
                                      name='loop.cond')
            builder.cbranch(cmp, body_block, end_block)
            
            # Body block - get current element
            builder.position_at_start(body_block)
            elem_ptr = builder.gep(collection, 
                                 [ir.Constant(ir.IntType(32), 0)], 
                                 [current_idx], 
                                 name='elem.ptr')
            elem_val = builder.load(elem_ptr, name='elem')
            
            # Store in loop variable
            var_ptr = builder.alloca(elem_type, name=self.variables[0])
            builder.store(elem_val, var_ptr)
            module.symbol_table.define(self.variables[0], SymbolKind.VARIABLE, llvm_value=var_ptr)
            
        elif isinstance(collection.type, ir.PointerType) and isinstance(collection.type.pointee, ir.IntType(8)):
            # String iteration (char*)
            zero = ir.Constant(ir.IntType(32), 0)
            current_ptr = builder.alloca(collection.type, name='char.ptr')
            builder.store(collection, current_ptr)
            
            builder.branch(cond_block)
            
            # Condition block
            builder.position_at_start(cond_block)
            ptr_val = builder.load(current_ptr, name='ptr')
            char_val = builder.load(ptr_val, name='char')
            cmp = builder.icmp_unsigned('!=', char_val, 
                                       ir.Constant(ir.IntType(8), 0), 
                                       name='loop.cond')
            builder.cbranch(cmp, body_block, end_block)
            
            # Body block
            builder.position_at_start(body_block)
            var_ptr = builder.alloca(ir.IntType(8), name=self.variables[0])
            builder.store(char_val, var_ptr)
            module.symbol_table.define(self.variables[0], SymbolKind.VARIABLE, llvm_value=var_ptr)
            
            # Increment pointer
            next_ptr = builder.gep(ptr_val, [ir.Constant(ir.IntType(32), 1)], name='next.ptr')
            builder.store(next_ptr, current_ptr)
            
        else:
            raise ValueError(f"Cannot iterate over type {coll_type}")

        # Generate loop body
        old_break = getattr(builder, 'break_block', None)
        old_continue = getattr(builder, 'continue_block', None)
        builder.break_block = end_block
        builder.continue_block = cond_block
        
        self.body.codegen(builder, module)
        
        if not builder.block.is_terminated:
            # For arrays: increment index
            if isinstance(coll_type, ir.PointerType) and isinstance(coll_type.pointee, ir.ArrayType):
                current_idx = builder.load(index_ptr, name='idx')
                next_idx = builder.add(current_idx, ir.Constant(ir.IntType(32), 1), name='next.idx')
                builder.store(next_idx, index_ptr)
            builder.branch(cond_block)

        # Clean up
        builder.break_block = old_break
        builder.continue_block = old_continue
        builder.position_at_start(end_block)
        return None

@dataclass
class ReturnStatement(Statement):
    value: Optional[Expression] = None

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        if self.value is None:
            builder.ret_void()
            return None

        ret_val = self.value.codegen(builder, module)

        if ret_val is None:
            builder.ret_void()
            return None

        func = builder.block.function

        if hasattr(func.type, 'return_type'):
            expected = func.type.return_type
        elif hasattr(func.type, 'pointee') and hasattr(func.type.pointee, 'return_type'):
            expected = func.type.pointee.return_type
        else:
            raise RuntimeError("Cannot determine function return type")

        # Rework to use lowering context.
        ret_val = CoercionContext.coerce_return_value(builder, ret_val, expected)

        builder.ret(ret_val)
        return None

@dataclass
class BreakStatement(Statement):
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        if not hasattr(builder, 'break_block'):
            raise SyntaxError("'break' outside of loop or switch")
        
        # Don't do anything if block is already terminated
        if builder.block.is_terminated:
            return None
            
        # Branch to break block - this terminates the block
        builder.branch(builder.break_block)
        
        # Don't call unreachable() - the branch already terminated the block
        # Any subsequent code will naturally be unreachable
        return None

@dataclass
class ContinueStatement(Statement):
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        if not hasattr(builder, 'continue_block'):
            raise SyntaxError("'continue' outside of loop")
        
        # Don't do anything if block is already terminated
        if builder.block.is_terminated:
            return None
            
        # Branch to continue block - this terminates the block
        builder.branch(builder.continue_block)
        
        # Don't call unreachable() - the branch already terminated the block
        # Any subsequent code will naturally be unreachable
        return None

@dataclass
class Case(ASTNode):
    value: Optional[Expression]  # None for default case
    body: Block

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Generate code for the case body
        return self.body.codegen(builder, module)

@dataclass
class SwitchStatement(Statement):
    expression: Expression
    cases: List[Case] = field(default_factory=list)
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        switch_val = self.expression.codegen(builder, module)
        
        # Create basic blocks
        func = builder.block.function
        merge_block = func.append_basic_block("switch_merge")
        default_block = None
        case_blocks = []
        
        # Create blocks for all cases
        for i, case in enumerate(self.cases):
            if case.value is None:  # Default case
                default_block = func.append_basic_block("switch_default")
                case_blocks.append((None, default_block))
            else:
                case_block = func.append_basic_block(f"switch_case_{i}")
                case_blocks.append((case.value, case_block))
        
        # If no default block was specified, use merge block as default
        if default_block is None:
            default_block = merge_block
        
        # Create the switch instruction
        switch = builder.switch(switch_val, default_block)
        
        # Add all non-default cases to the switch
        for value, block in case_blocks:
            if value is not None:
                case_const = value.codegen(builder, module)
                switch.add_case(case_const, block)
        
        # Generate code for each case block
        for i, (value, case_block) in enumerate(case_blocks):
            builder.position_at_start(case_block)
            
            # Generate the case body
            self.cases[i].body.codegen(builder, module)
            
            # Add branch to merge block if the case doesn't already have a terminator
            # (cases with return/break will already be terminated)
            if not builder.block.is_terminated:
                builder.branch(merge_block)
        
        # Position builder at merge block for subsequent code
        builder.position_at_start(merge_block)
        
        return None

@dataclass
class TryBlock(Statement):
    try_body: Block
    catch_blocks: List[Tuple[Optional[TypeSystem], str, Block]]

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Flag-based try/catch using stack-allocated exception state"""
        
        # Allocate exception flag and value on the STACK (not global)
        exc_flag = builder.alloca(ir.IntType(1), name='exception_flag')
        exc_value = builder.alloca(ir.IntType(64), name='exception_value')
        
        # Save old exception state (for nested try blocks)
        old_exc_flag = getattr(builder, 'flux_exception_flag', None)
        old_exc_value = getattr(builder, 'flux_exception_value', None)
        
        # Set current exception state pointers
        builder.flux_exception_flag = exc_flag
        builder.flux_exception_value = exc_value
        
        # Create basic blocks
        func = builder.block.function
        try_block = func.append_basic_block('try.body')
        catch_check_block = func.append_basic_block('catch.check')
        catch_blocks_ir = []
        end_block = func.append_basic_block('try.end')
        
        # Create catch blocks
        for i, (exc_type, exc_name, catch_body) in enumerate(self.catch_blocks):
            catch_block = func.append_basic_block(f'catch.{i}')
            catch_blocks_ir.append(catch_block)
        
        # Set exception handler for this try block
        builder.flux_exception_handler = catch_check_block
        
        # Clear exception flag before entering try block
        builder.store(ir.Constant(ir.IntType(1), 0), exc_flag)
        
        # Branch to try block
        builder.branch(try_block)
        
        # Generate TRY block
        builder.position_at_start(try_block)
        self.try_body.codegen(builder, module)
        
        # After try block, check if exception occurred
        if not builder.block.is_terminated:
            builder.branch(catch_check_block)
        
        # Check exception flag
        builder.position_at_start(catch_check_block)
        exc_flag_val = builder.load(exc_flag, name='exc_flag')
        zero = ir.Constant(ir.IntType(1), 0)
        has_exception = builder.icmp_signed('!=', exc_flag_val, zero, name='has_exception')
        
        # Branch: if exception, go to first catch; otherwise go to end
        if catch_blocks_ir:
            builder.cbranch(has_exception, catch_blocks_ir[0], end_block)
        else:
            builder.cbranch(has_exception, end_block, end_block)
        
        # Generate CATCH blocks
        for i, (exc_type, exc_name, catch_body) in enumerate(self.catch_blocks):
            builder.position_at_start(catch_blocks_ir[i])
            
            # Clear exception flag since we're handling it
            builder.store(ir.Constant(ir.IntType(1), 0), exc_flag)
            
            # Load the exception value
            if exc_name:
                exc_val_i64 = builder.load(exc_value, name='exc_val')
                
                # Allocate local variable for exception
                if exc_type:
                    exc_type_llvm = TypeSystem.get_llvm_type(exc_type, module)
                else:
                    exc_type_llvm = ir.IntType(32)
                
                exc_var = builder.alloca(exc_type_llvm, name=exc_name)
                
                # Truncate or extend the exception value to match the type
                if isinstance(exc_type_llvm, ir.IntType):
                    if exc_type_llvm.width < 64:
                        exc_val = builder.trunc(exc_val_i64, exc_type_llvm, name='exc_trunc')
                    elif exc_type_llvm.width > 64:
                        exc_val = builder.zext(exc_val_i64, exc_type_llvm, name='exc_ext')
                    else:
                        exc_val = exc_val_i64
                else:
                    exc_val = builder.bitcast(exc_val_i64, exc_type_llvm)
                
                builder.store(exc_val, exc_var)
                
                # Add to scope
                if not module.symbol_table.is_global_scope():
                    module.symbol_table.define(exc_name, SymbolKind.VARIABLE, llvm_value=exc_var)
            
            # Generate catch body
            catch_body.codegen(builder, module)
            
            # Remove exception variable from scope
            if exc_name and not module.symbol_table.is_global_scope() and module.symbol_table.get_llvm_value(exc_name) is not None:
                module.symbol_table.delete_variable(exc_name)
            
            # Branch to end if not already terminated
            if not builder.block.is_terminated:
                builder.branch(end_block)
        
        # Restore old exception state
        builder.flux_exception_flag = old_exc_flag
        builder.flux_exception_value = old_exc_value
        builder.flux_exception_handler = None
        
        # Position at end block
        builder.position_at_start(end_block)
        return None

@dataclass
class ThrowStatement(Statement):
    expression: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Throw an exception using stack-allocated exception state"""
        
        # Get the exception state from builder (set by TryBlock)
        if not hasattr(builder, 'flux_exception_flag') or builder.flux_exception_flag is None:
            raise RuntimeError("throw statement used outside of try block")
        
        exc_flag = builder.flux_exception_flag
        exc_value = builder.flux_exception_value
        
        # Evaluate the exception value
        exc_val = self.expression.codegen(builder, module)
        
        # Convert exception value to i64 for storage
        if isinstance(exc_val.type, ir.IntType):
            if exc_val.type.width < 64:
                exc_val_i64 = builder.zext(exc_val, ir.IntType(64), name='exc_zext')
            elif exc_val.type.width > 64:
                exc_val_i64 = builder.trunc(exc_val, ir.IntType(64), name='exc_trunc')
            else:
                exc_val_i64 = exc_val
        else:
            exc_val_i64 = builder.bitcast(exc_val, ir.IntType(64))
        
        # Store the exception value
        builder.store(exc_val_i64, exc_value)
        
        # Set exception flag
        builder.store(ir.Constant(ir.IntType(1), 1), exc_flag)
        
        # Branch to exception handler
        if hasattr(builder, 'flux_exception_handler') and builder.flux_exception_handler is not None:
            builder.branch(builder.flux_exception_handler)
        else:
            builder.unreachable()
        
        return None

@dataclass
class AssertStatement(Statement):
    condition: Expression
    message: Optional[Expression] = None

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Generate condition value
        cond_val = self.condition.codegen(builder, module)
        
        # Convert to boolean if needed
        if not isinstance(cond_val.type, ir.IntType) or cond_val.type.width != 1:
            zero = ir.Constant(cond_val.type, 0)
            cond_val = builder.icmp_signed('!=', cond_val, zero)

        # Create basic blocks
        func = builder.block.function
        pass_block = func.append_basic_block('assert.pass')
        fail_block = func.append_basic_block('assert.fail')
        
        # Branch based on condition
        builder.cbranch(cond_val, pass_block, fail_block)

        # Failure block
        builder.position_at_start(fail_block)
        
        if self.message:
            # Handle message - it can be a string literal or an Expression
            if isinstance(self.message, str):
                # Parser gave us a string directly - create a global constant
                msg_bytes = self.message.encode('ascii')
                msg_type = ir.ArrayType(ir.IntType(8), len(msg_bytes))
                msg_const = ir.Constant(msg_type, bytearray(msg_bytes))
                
                msg_gv = ir.GlobalVariable(module, msg_type, name=f"assert_msg_{id(self)}")
                msg_gv.initializer = msg_const
                msg_gv.linkage = 'internal'
                msg_gv.global_constant = True
                
                zero = ir.Constant(ir.IntType(32), 0)
                msg_ptr = builder.gep(msg_gv, [zero, zero], inbounds=True)
            else:
                # Message is an Expression - evaluate it
                msg_val = self.message.codegen(builder, module)
                
                # Handle array pointers - get pointer to first element
                if isinstance(msg_val.type, ir.PointerType) and isinstance(msg_val.type.pointee, ir.ArrayType):
                    zero = ir.Constant(ir.IntType(32), 0)
                    msg_ptr = builder.gep(msg_val, [zero, zero], inbounds=True, name="assert_msg_ptr")
                else:
                    msg_ptr = msg_val
            
            # Look for Flux print function
            print_fn = module.globals.get('print')
            
            if print_fn is not None:
                builder.call(print_fn, [msg_ptr])
            else:
                # Fallback to puts
                puts_fn = module.globals.get('puts')
                if puts_fn is None:
                    puts_type = ir.FunctionType(ir.IntType(32), [ir.PointerType(ir.IntType(8))])
                    puts_fn = ir.Function(module, puts_type, 'puts')
                    puts_fn.linkage = 'external'
                builder.call(puts_fn, [msg_ptr])

        # Call abort
        abort = module.globals.get('abort')
        if abort is None:
            abort_type = ir.FunctionType(ir.VoidType(), [])
            abort = ir.Function(module, abort_type, 'abort')
            abort.linkage = 'external'
        
        builder.call(abort, [])
        builder.unreachable()

        # Success block
        builder.position_at_start(pass_block)
        return None

# Function parameter
@dataclass
class Parameter:
    name: Optional[str] # Can be none for unnamed prototype parameters
    type_spec: TypeSystem
    
    def __post_init__(self):
        # Store the original type name for debugging/metadata
        if self.type_spec.custom_typename:
            self.original_type_name = self.type_spec.custom_typename
        else:
            self.original_type_name = str(self.type_spec.base_type)

@dataclass
class InlineAsm(Expression):
    """Represents inline assembly block"""
    body: str
    is_volatile: bool = False
    constraints: str = ""

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Clean and format the assembly string - remove comment lines
        asm_lines = []
        for line in self.body.split('\n'):
            # Strip whitespace and check if it's a comment line
            stripped = line.strip()
            if stripped and not stripped.startswith('//'):
                asm_lines.append(line)
        asm = '\n'.join(asm_lines)
        
        # Parse constraints and extract operands
        output_operands = []
        input_operands = []
        output_constraints = []
        input_constraints = []
        clobber_list = []
        
        if self.constraints:
            # Parse the constraint string format: "outputs:inputs:clobbers"
            # Example: '"=r"(stdout_handle)::"eax","memory"'
            # or ': : "r"(stdout_handle), "r"(message), "m"(bytes_written) : "eax", "ecx", "edx", "memory"'
            #print(f"DEBUG: Parsing constraints: {self.constraints}")
            constraint_parts = self.constraints.split(':')
            #print(f"DEBUG: Split into parts: {constraint_parts}")
            
            # Ensure we have at least 3 parts (outputs:inputs:clobbers)
            while len(constraint_parts) < 3:
                constraint_parts.append('')
            
            # Handle outputs (first part)
            output_part = constraint_parts[0].strip()
            if output_part:
                # Parse output operands like '"=r"(stdout_handle)'
                import re
                output_matches = re.findall(r'"([^"]+)"\s*\(([^)]+)\)', output_part)
                for constraint, var_name in output_matches:
                    # Look up the variable
                    if module.symbol_table.get_llvm_value(var_name) is not None:
                        var_ptr = module.symbol_table.get_llvm_value(var_name)
                        output_operands.append(var_ptr)
                        output_constraints.append(constraint)
                    elif var_name in module.globals:
                        var_ptr = module.globals[var_name]
                        output_operands.append(var_ptr)
                        output_constraints.append(constraint)
                            
            # Handle inputs (second part)
            input_part = constraint_parts[1].strip()
            #print(f"DEBUG: Input part: '{input_part}'")
            if input_part:
                # Parse input operands like '"r"(stdout_handle), "r"(message), "m"(bytes_written)'
                import re
                input_matches = re.findall(r'"([^"]+)"\s*\(([^)]+)\)', input_part)
                #print(f"DEBUG: Input matches: {input_matches}")
                for constraint, var_name in input_matches:
                    #print(f"DEBUG: Looking for variable '{var_name}' with constraint '{constraint}'")
                    # Look up the variable
                    if module.symbol_table.get_llvm_value(var_name) is not None:
                        var_ptr = module.symbol_table.get_llvm_value(var_name)
                        # For arrays or memory constraints, pass the pointer; for register constraints, load the value
                        if constraint in ['m'] or (isinstance(var_ptr.type, ir.PointerType) and isinstance(var_ptr.type.pointee, ir.ArrayType)):
                            input_operands.append(var_ptr)
                            #print(f"DEBUG: Found in scope, using pointer: {var_ptr}")
                        else:
                            var_val = builder.load(var_ptr, name=f"{var_name}_load")
                            input_operands.append(var_val)
                            #print(f"DEBUG: Found in scope, loaded value: {var_val}")
                        input_constraints.append(constraint)
                    elif var_name in module.globals:
                        var_ptr = module.globals[var_name]
                        # For arrays or memory constraints, pass the pointer; for register constraints, load the value
                        if constraint in ['m'] or isinstance(var_ptr.type.pointee, ir.ArrayType):
                            input_operands.append(var_ptr)
                            #print(f"DEBUG: Found in globals, using pointer: {var_ptr}")
                        else:
                            var_val = builder.load(var_ptr, name=f"{var_name}_load")
                            input_operands.append(var_val)
                            #print(f"DEBUG: Found in globals, loaded value: {var_val}")
                        input_constraints.append(constraint)
                            
            # Handle clobbers (third part)
            clobber_part = constraint_parts[2].strip()
            if clobber_part:
                # Parse clobbers like '"eax", "ecx", "edx", "memory"'
                import re
                clobber_matches = re.findall(r'"([^"]+)"', clobber_part)
                clobber_list = clobber_matches
        
        # Build the final constraint string in LLVM format
        # LLVM inline assembly constraint format:
        # - Each operand gets one constraint
        # - Clobbers are prefixed with ~ and added to the constraint list
        # - Format: "constraint1,constraint2,~clobber1,~clobber2"
        
        #print(f"DEBUG: output_constraints = {output_constraints}")
        #print(f"DEBUG: input_constraints = {input_constraints}")
        #print(f"DEBUG: clobber_list = {clobber_list}")
        
        # Only input operands are passed as parameters
        #print(f"DEBUG: input_operands = {input_operands}")
        #print(f"DEBUG: output_operands = {output_operands}")
        
        # For memory output operands (=m), we need to pass them as input operands in LLVM
        # but treat the constraint as an input/output constraint
        final_input_operands = input_operands[:]
        final_constraints = input_constraints[:]
        
        # Handle output operands - for memory operands (=m), convert to input/output (+m)
        for i, (output_op, output_constraint) in enumerate(zip(output_operands, output_constraints)):
            if output_constraint.startswith('=m'):
                # Memory output becomes an input/output constraint
                final_input_operands.insert(0, output_op)  # Add to beginning
                # Convert =m to +m (input/output)
                modified_constraint = output_constraint.replace('=m', '+m')
                final_constraints.insert(0, modified_constraint)
            elif output_constraint.startswith('=r'):
                # Register output - LLVM will return this as a value
                final_constraints.insert(0, output_constraint)
            else:
                # Other output constraints - assume register-like behavior
                final_constraints.insert(0, output_constraint)
        
        # Add clobbers with ~ prefix and curly braces
        clobber_constraints = [f"~{{{clobber}}}" for clobber in clobber_list]
        final_constraints.extend(clobber_constraints)
        
        # Join all constraints with commas
        constraint_str = ','.join(final_constraints)
        
        #print(f"DEBUG: final constraint_str = '{constraint_str}'")
        #print(f"DEBUG: final_input_operands = {final_input_operands}")
        
        # Create function type based on final input operands
        input_types = [op.type for op in final_input_operands]
        
        # Determine return type - for register outputs, we return a value; otherwise void
        has_register_output = any(constraint.startswith('=r') or constraint.startswith('=a') or constraint.startswith('=b') for constraint in output_constraints)
        
        if has_register_output and output_operands:
            # Return the type of the first register output
            output_type = output_operands[0].type
            if isinstance(output_type, ir.PointerType(ir.IntType(16))):
                output_type = output_type.pointee
            fn_type = ir.FunctionType(output_type, input_types)
        else:
            # For void return, still need proper function signature if we have operands
            fn_type = ir.FunctionType(ir.VoidType(), input_types)
        
        # Create the inline assembly
        inline_asm = ir.InlineAsm(
            fn_type,              # Function type with input operand types
            asm,                  # Assembly string
            constraint_str,       # Clean constraints
            self.is_volatile      # Volatile flag
        )
        
        # Emit the call with final input operands
        result = builder.call(inline_asm, final_input_operands)
        
        # If we have register output operands, store the result
        if has_register_output and output_operands:
            builder.store(result, output_operands[0])
        
        return result

# Function definition
@dataclass
class FunctionDef(ASTNode):
    name: str
    parameters: List[Parameter]
    return_type: TypeSystem
    body: Block
    is_const: bool = False
    is_volatile: bool = False
    is_prototype: bool = False
    no_mangle: bool = False
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Function:
        # Convert return type and parameter types using FunctionTypeHandler
        ret_type = FunctionTypeHandler.convert_type_spec_to_llvm(self.return_type, module)
        
        # Convert parameter types and build metadata
        param_types = []
        param_metadata = FunctionTypeHandler.build_param_metadata(self.parameters, module)
        for param in self.parameters:
            param_type = FunctionTypeHandler.convert_type_spec_to_llvm(param.type_spec, module)
            param_types.append(param_type)
        
        # Create function type
        func_type = ir.FunctionType(ret_type, param_types)
        
        # Generate mangled name using FunctionTypeHandler
        mangled_name = SymbolTable.mangle_function_name(self.name, self.parameters, self.return_type, self.no_mangle)
        
        # Check if this exact mangled function already exists
        if mangled_name in module.globals:
            existing_func = module.globals[mangled_name]
            if isinstance(existing_func, ir.Function):
                # Function with this exact signature already exists
                if self.is_prototype:
                    # This is just another prototype/declaration - that's fine, use the existing one
                    func = existing_func
                elif existing_func.is_declaration:
                    # This is providing the body for a previously declared function - that's fine
                    func = existing_func
                else:
                    # Both existing and new are definitions - that's an error
                    raise ValueError(f"Function '{self.name}' with signature '{mangled_name}' redefined")
            else:
                raise ValueError(f"Name '{mangled_name}' already used for non-function")
        else:
            # Create new function with mangled name
            func = ir.Function(module, func_type, mangled_name)
            
            # Extract base name for symbol table registration
            # The function name might be namespace-mangled like "standard__types__bswap16"
            # We need to extract just "bswap16" for the symbol table (namespace is tracked separately)
            # Check if we're in a namespace
            if hasattr(module, 'symbol_table') and module.symbol_table.current_namespace:
                # Remove the namespace prefix from the name
                namespace_prefix = module.symbol_table.current_namespace + "__"
                if self.name.startswith(namespace_prefix):
                    base_name = self.name[len(namespace_prefix):]
                else:
                    # No prefix, use as-is
                    base_name = self.name
            else:
                # Not in a namespace or no :: in name
                base_name = self.name.split('::')[-1] if '::' in self.name else self.name
            
            # Register this as an overload using FunctionTypeHandler
            #print(f"[FUNC REG] Registering {base_name} (mangled: {mangled_name})", file=sys.stderr)
            SymbolTable.register_function_overload(module, base_name, mangled_name, self.parameters, self.return_type, func)
            #print(f"[FUNC REG] Registered! Overloads for {base_name}: {len(module._function_overloads.get(base_name, []))}", file=sys.stderr)

            # Also register in symbol table if available
            if hasattr(module, 'symbol_table'):
                try:
                    #print(f"DEFINING FUNCTION: {base_name} -> {mangled_name}", file=sys.stderr)
                    module.symbol_table.define(
                        base_name, 
                        SymbolKind.FUNCTION, 
                        type_spec=self.return_type,
                        llvm_type=func_type,
                        llvm_value=func)
                    # Also register the full name if it's different
                    if base_name != self.name:
                        module.symbol_table.define(
                            self.name, 
                            SymbolKind.FUNCTION, 
                            type_spec=self.return_type,
                            llvm_type=func_type,
                            llvm_value=func)
                except Exception as e:
                    import traceback
                    print(f"[ERROR] Failed to register function in symbol table:", file=sys.stderr)
                    print(f"[ERROR]   base_name={base_name}", file=sys.stderr)
                    print(f"[ERROR]   self.name={self.name}", file=sys.stderr)
                    print(f"[ERROR]   mangled_name={mangled_name}", file=sys.stderr)
                    print(f"[ERROR]   symbol_table type: {type(module.symbol_table)}", file=sys.stderr)
                    print(f"[ERROR]   symbol_table.scope_level: {module.symbol_table.scope_level if hasattr(module, 'symbol_table') else 'N/A'}", file=sys.stderr)
                    print(f"[ERROR]   symbol_table.current_namespace: {module.symbol_table.current_namespace if hasattr(module, 'symbol_table') else 'N/A'}", file=sys.stderr)
                    print(f"[ERROR]   symbol_table.scopes: {module.symbol_table.scopes if hasattr(module, 'symbol_table') else 'N/A'}", file=sys.stderr)
                    print(f"[ERROR]   Exception type: {type(e).__name__}", file=sys.stderr)
                    print(f"[ERROR]   Exception: {e}", file=sys.stderr)
                    traceback.print_exc()
                    raise
        
        if self.is_prototype:
            return func
        
        # Set parameter names (use generic names for unnamed parameters)
        for i, param in enumerate(func.args):
            if self.parameters[i].name is not None:
                param.name = self.parameters[i].name
            else:
                param.name = f"arg{i}"
        
        # Create entry block
        entry_block = func.append_basic_block('entry')
        builder.position_at_start(entry_block)
        
        # Create new scope for function body
        module.symbol_table.enter_scope()  # Enter function scope
        # Initialize union tracking for this function scope
        if not hasattr(builder, 'initialized_unions'):
            builder.initialized_unions = set()
        
        # Store parameter type information in scope metadata
        
        # Allocate space for parameters and store initial values WITH type information
        for i, param in enumerate(func.args):
            param_name = self.parameters[i].name if self.parameters[i].name is not None else f"arg{i}"
            alloca = builder.alloca(param.type, name=f"{param_name}.addr")
            
            # Attach type metadata to the parameter value before storing
            # This ensures the parameter carries the correct signedness information
            param_with_metadata = TypeSystem.attach_type_metadata(param, type_spec=self.parameters[i].type_spec)
            
            builder.store(param_with_metadata, alloca)
            # Define parameter in symbol table with type information
            module.symbol_table.define(
                param_name, 
                SymbolKind.VARIABLE,
                type_spec=self.parameters[i].type_spec,
                llvm_value=alloca
            )
        
        # Generate function body
        self.body.codegen(builder, module)
        
        # Add implicit return if needed
        if not builder.block.is_terminated:
            if isinstance(ret_type, ir.VoidType):
                builder.ret_void()
            else:
                raise RuntimeError("Function must end with return statement")
        
        # Restore previous scope
        module.symbol_table.exit_scope()  # Exit function scope
        return func

@dataclass
class FunctionPointer(Expression):
    """
    Function pointer type and operations.
    
    Supports:
    - Function pointer declarations: int (*fp)(int, int)
    - Function pointer assignments: fp = @my_function
    - Function pointer calls: result = fp(arg1, arg2)
    """
    name: str
    return_type: TypeSystem
    parameter_types: List[TypeSystem]
    
    def get_function_type(self, module: ir.Module) -> ir.FunctionType:
        """Get LLVM function type for this function pointer"""
        ret_type = TypeSystem.get_llvm_type(self.return_type, module)
        param_types = [TypeSystem.get_llvm_type(param, module) for param in self.parameter_types]
        return ir.FunctionType(ret_type, param_types)
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate function pointer variable"""
        func_type = self.get_function_type(module)
        ptr_type = ir.PointerType(func_type)
        
        # Allocate space for function pointer
        if module.symbol_table.is_global_scope():
            # Global function pointer
            gvar = ir.GlobalVariable(module, ptr_type, self.name)
            gvar.initializer = ir.Constant(ptr_type, None)
            gvar.linkage = 'internal'
            return gvar
        else:
            # Local function pointer
            alloca = builder.alloca(ptr_type, name=self.name)
            module.symbol_table.define(self.name, SymbolKind.VARIABLE, type_spec=resolved_type_spec, llvm_value=alloca)
            return alloca

@dataclass
class FunctionPointerDeclaration(Statement):
    """
    Function pointer variable declaration.
    
    Syntax: void{}* fp() = @foo;
    """
    name: str
    fp_type: FunctionPointerType
    initializer: Optional[Expression] = None
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate function pointer variable"""
        resolved_type_spec = None
        ptr_type = self.fp_type.get_llvm_pointer_type(module)
        
        # Store type information for later lookup
        
        # Type information will be stored in symbol table during define()
        
        # Allocate storage
        if module.symbol_table.is_global_scope():
            # Global function pointer
            gvar = ir.GlobalVariable(module, ptr_type, self.name)
            gvar.linkage = 'internal'
            
            if self.initializer:
                # Evaluate initializer
                init_val = self.initializer.codegen(builder, module)
                gvar.initializer = init_val
            else:
                gvar.initializer = ir.Constant(ptr_type, None)
            
            return gvar
        else:
            # Local function pointer
            alloca = builder.alloca(ptr_type, name=self.name)
            module.symbol_table.define(self.name, SymbolKind.VARIABLE, type_spec=resolved_type_spec, llvm_value=alloca)
            
            if self.initializer:
                init_val = self.initializer.codegen(builder, module)
                # If init_val is a function, we need to ensure it's properly converted
                # to a function pointer with correct type
                if isinstance(init_val, ir.Function):
                    # For Windows PE compatibility, explicitly convert via ptrtoint/inttoptr
                    # This ensures the linker properly resolves the function address
                    func_as_int = builder.ptrtoint(init_val, ir.IntType(64))
                    init_val = builder.inttoptr(func_as_int, ptr_type)
                builder.store(init_val, alloca)
            
            return alloca

@dataclass
class FunctionPointerCall(Expression):
    """Call through a function pointer"""
    pointer: Expression  # Expression that evaluates to function pointer
    arguments: List[Expression]
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate indirect function call through pointer"""
        # Get the function pointer value
        func_ptr = self.pointer.codegen(builder, module)
        
        # If it's stored in memory, load it
        if isinstance(func_ptr.type, ir.PointerType):
            if isinstance(func_ptr.type.pointee, ir.PointerType):
                # Double pointer - load once to get function pointer
                func_ptr = builder.load(func_ptr, name="func_ptr_load")
        
        # Generate arguments
        args = [arg.codegen(builder, module) for arg in self.arguments]
        
        # Simple indirect call - just call through the pointer
        # The key issue: llvmlite's builder.call() should work, but we need
        # to ensure the function pointer is properly typed
        return builder.call(func_ptr, args, name="indirect_call")

@dataclass
class FunctionPointerAssignment(Statement):
    """Assign a function to a function pointer"""
    pointer_name: str
    function_expr: Expression  # Usually AddressOf(Identifier("function_name"))
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Assign function address to function pointer"""
        # Get the function pointer storage location
        if module.symbol_table.get_llvm_value(self.pointer_name) is not None:
            ptr_storage = module.symbol_table.get_llvm_value(self.pointer_name)
        elif self.pointer_name in module.globals:
            ptr_storage = module.globals[self.pointer_name]
        else:
            raise NameError(f"Function pointer '{self.pointer_name}' not found")
        
        # Evaluate the function expression (should be a function address)
        func_value = self.function_expr.codegen(builder, module)
        
        # Store function address in the pointer
        builder.store(func_value, ptr_storage)
        return func_value

@dataclass
class DestructuringAssignment(Statement):
    """Destructuring assignment"""
    variables: List[Union[str, Tuple[str, TypeSystem]]]  # Can be simple names or (name, type) pairs
    source: Expression
    source_type: Optional[Identifier]  # For the "from" clause
    is_explicit: bool  # True if using "as" syntax

@dataclass
class EnumDef(ASTNode):
    name: str
    values: dict

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> None:
        if not hasattr(module, '_enum_types'):
            module._enum_types = {}
        module._enum_types[self.name] = self.values
        
        # Register enum in symbol table
        if hasattr(module, 'symbol_table'):
            #print(f"[ENUM] Registering enum '{self.name}' in symbol table", file=sys.stderr)
            module.symbol_table.define(
                self.name,
                SymbolKind.ENUM,
                type_spec=None,  # Enums don't have a TypeSystem
                llvm_type=ir.IntType(32),  # Enums are i32
                llvm_value=None  # Enums don't have a single value
            )
        
        for name, value in self.values.items():
            const_name = f"{self.name}.{name}"
            const_value = ir.Constant(ir.IntType(32), value)
            global_const = ir.GlobalVariable(module, ir.IntType(32), name=const_name)
            global_const.initializer = const_value
            global_const.global_constant = True
            
            # Register each enum value in symbol table
            if hasattr(module, 'symbol_table'):
                full_name = f"{self.name}.{name}"
                module.symbol_table.define(
                    full_name,
                    SymbolKind.VARIABLE,  # Enum values are constants (variables)
                    type_spec=None,
                    llvm_type=ir.IntType(32),
                    llvm_value=global_const
                )

@dataclass
class EnumDefStatement(Statement):
    enum_def: EnumDef

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> Optional[ir.Value]:
        # Delegate codegen to the contained EnumDef
        self.enum_def.codegen(builder, module)
        return None

@dataclass
class UnionMember(ASTNode):
    name: str
    type_spec: TypeSystem
    initial_value: Optional[Expression] = None

@dataclass
class UnionDef(ASTNode):
    name: str
    members: List[UnionMember] = field(default_factory=list)
    tag_name: Optional[str] = None  # Name of the enum type used as tag
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Type:
        # First convert all member types to LLVM types
        member_types = []
        member_names = []
        max_size = 0
        max_type = None
        
        for member in self.members:
            member_type = TypeSystem.get_llvm_type(member.type_spec, module)
            if isinstance(member_type, str):
                # Handle named types
                if hasattr(module, '_type_aliases') and member_type in module._type_aliases:
                    member_type = module._type_aliases[member_type]
                else:
                    raise ValueError(f"Unknown type: {member_type}")
            
            member_types.append(member_type)
            member_names.append(member.name)
            
            # Calculate size
            if hasattr(member_type, 'width'):  # For integer types
                size = (member_type.width + 7) // 8  # Convert bits to bytes
            else:
                size = module.data_layout.get_type_size(member_type)
                
            if size > max_size:
                max_size = size
                max_type = member_type
        
        # For tagged unions, create a struct with tag field + union data
        if self.tag_name:
            # Verify the tag is an enum type
            if not hasattr(module, '_enum_types') or self.tag_name not in module._enum_types:
                raise ValueError(f"Tag '{self.tag_name}' is not a defined enum type")
            
            # Tagged union structure: { i32 tag, [max_size x i8] data }
            tag_type = ir.IntType(32)  # Enum is i32
            data_type = ir.ArrayType(ir.IntType(8), max_size)
            
            union_type = ir.LiteralStructType([tag_type, data_type])
            union_type.names = [f"{self.name}_tagged"]
        else:
            # Regular union: just the data
            union_type = ir.LiteralStructType([max_type])
            union_type.names = [self.name]
        
        # Store the type in the module's context
        if not hasattr(module, '_union_types'):
            module._union_types = {}
        module._union_types[self.name] = union_type
        
        # Store member info for later access
        if not hasattr(module, '_union_member_info'):
            module._union_member_info = {}
        module._union_member_info[self.name] = {
            'member_types': member_types,
            'member_names': member_names,
            'max_size': max_size,
            'tag_name': self.tag_name,
            'is_tagged': bool(self.tag_name)
        }
        
        # Register union in symbol table
        if hasattr(module, 'symbol_table'):
            #print(f"[UNION] Registering union '{self.name}' in symbol table", file=sys.stderr)
            module.symbol_table.define(
                self.name,
                SymbolKind.UNION,
                type_spec=None,
                llvm_type=union_type,
                llvm_value=None
            )
        
        return union_type

@dataclass
class TieExpression(Expression):
    """
    Tie operator: ~variable
    
    Transfers ownership and marks source as tied-from.
    Only creates tracking when explicitly used.
    """
    operand: Expression
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate tie (move) operation."""
        # Must be an identifier (lvalue)
        if not isinstance(self.operand, Identifier):
            raise ValueError("Tie operator ~ can only be applied to variables")
        
        var_name = self.operand.name
        
        # Get the variable pointer
        if module.symbol_table.get_llvm_value(var_name) is not None:
            var_ptr = module.symbol_table.get_llvm_value(var_name)
        elif var_name in module.globals:
            var_ptr = module.globals[var_name]
        else:
            raise NameError(f"Unknown variable: {var_name}")
        
        # Load the value (this is the tie/move)
        tied_value = builder.load(var_ptr, name=f"{var_name}_tied")
        
        # Create validity flag NOW (lazy initialization)
        if not hasattr(builder, 'object_validity_flags'):
            builder.object_validity_flags = {}
        
        if var_name not in builder.object_validity_flags:
            # Create validity flag on first tie
            validity_flag = builder.alloca(ir.IntType(1), name=f"{var_name}_valid")
            # Initialize to 1 (was valid before this tie)
            builder.store(ir.Constant(ir.IntType(1), 1), validity_flag)
            builder.object_validity_flags[var_name] = validity_flag
        
        # Mark as tied-from (invalid)
        validity_flag = builder.object_validity_flags[var_name]
        builder.store(ir.Constant(ir.IntType(1), 0), validity_flag)
        
        # Zero out source to prevent accidental reuse
        if isinstance(var_ptr.type.pointee, ir.PointerType):
            builder.store(ir.Constant(var_ptr.type.pointee, None), var_ptr)
        elif isinstance(var_ptr.type.pointee, ir.IntType):
            builder.store(ir.Constant(var_ptr.type.pointee, 0), var_ptr)
        
        return tied_value

# Struct member
@dataclass
class StructMember(ASTNode):
    name: str
    type_spec: TypeSystem
    offset: Optional[int] = None  # Bit offset, calculated during vtable gen
    is_private: bool = False
    initial_value: Optional[Expression] = None

# Struct instance
@dataclass
class StructInstance(Expression):
    """
    Struct instance - actual data container.
    
    This represents an actual struct in memory with data packed inline.
    The data is already serialized according to the struct's vtable layout.
    
    Syntax:
        StructName instance_name;                    # Uninitialized
        StructName instance_name {field1 = val1};   # Initialized with literal
    
    Example:
        struct Data { 
            unsigned data{32} a; 
            unsigned data{32} b; 
        };
        
        Data d {a = 0x54534554, b = 0x21474E49};  # "TEST" "ING!"
        // Memory layout: [54 53 45 54 21 47 4E 49] = "TESTING!"
    """
    struct_name: str
    field_values: Dict[str, Expression] = field(default_factory=dict)
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Generate struct instance with data packed inline.
        
        Returns an LLVM value containing the raw packed bits.
        """
        # Get struct definition
        if not hasattr(module, '_struct_vtables'):
            raise ValueError(f"Struct '{self.struct_name}' not defined")
        
        vtable = module._struct_vtables.get(self.struct_name)
        if not vtable:
            raise ValueError(f"Struct '{self.struct_name}' not defined")
        
        struct_type = module._struct_types[self.struct_name]
        
        # Create zeroed instance
        instance = StructTypeHandler.create_zeroed_instance(struct_type, vtable)
        
        # Pack field values into the instance
        for field_name, field_value_expr in self.field_values.items():
            # Find field in vtable
            field_info = next(
                (f for f in vtable.fields if f[0] == field_name),
                None
            )
            if not field_info:
                raise ValueError(f"Field '{field_name}' not found in struct '{self.struct_name}'")
            
            _, bit_offset, bit_width, alignment = field_info
            
            # Generate value
            field_value = field_value_expr.codegen(builder, module)
            
            # Pack value into instance at correct bit offset
            instance = StructTypeHandler.pack_field_value(
                builder, instance, field_value, 
                bit_offset, bit_width, vtable.total_bits
            )
        
        return instance
    
# Struct literal
@dataclass
class StructLiteral(Expression):
    """
    Struct literal - inline struct initialization.
    Can be either named fields {a=1, b=2} or positional {1, 2, 3}
    """
    field_values: Dict[str, Expression] = field(default_factory=dict)
    positional_values: List[Expression] = field(default_factory=list)
    struct_type: Optional[str] = None  # Can be inferred from context
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate code for struct literal."""
        # Struct type MUST be known from context (variable declaration)
        if self.struct_type is None:
            raise ValueError(
                "Struct literal must have type context. "
                "This should be set by VariableDeclaration during parsing."
            )

        return StructTypeHandler.pack_struct_literal(
            builder, module, self.struct_type, 
            self.field_values, self.positional_values
        )

# Struct pointer vtable
@dataclass
class StructVTable:
    struct_name: str
    total_bits: int
    total_bytes: int
    alignment: int
    fields: List[Tuple[str, int, int, int]]  # (name, bit_offset, bit_width, alignment)
    field_types: Dict[str, ir.Type] = field(default_factory=dict)  # field_name -> LLVM type
    
    def to_llvm_constant(self, module: ir.Module) -> ir.Constant:
        """
        Generate LLVM IR constant for vtable metadata.
        
        Format:
        {
            i32 total_bits,
            i32 field_count,
            [N x {i32 offset, i32 width, i32 alignment}] fields
        }
        """
        i32 = ir.IntType(32) # REPLACE WITH CODE TO EVALUATE INSTEAD OF HARD-CODE
        
        # Create field metadata array type
        field_type = ir.LiteralStructType([i32, i32, i32])
        field_array_type = ir.ArrayType(field_type, len(self.fields))
        
        # Build field array
        field_constants = []
        for name, offset, width, alignment in self.fields:
            field_constants.append(ir.Constant(field_type, [
                ir.Constant(i32, offset),
                ir.Constant(i32, width),
                ir.Constant(i32, alignment)
            ]))
        
        # Build vtable struct
        vtable_type = ir.LiteralStructType([
            i32,              # total_bits
            i32,              # field_count
            field_array_type  # fields
        ])
        
        return ir.Constant(vtable_type, [
            ir.Constant(i32, self.total_bits),
            ir.Constant(i32, len(self.fields)),
            ir.Constant(field_array_type, field_constants)
        ])

# Struct definition
@dataclass
class StructDef(ASTNode):
    """
    Struct definition - creates a Table Layout Descriptor (TLD).
    Struct instances are pure data with no overhead.
    """
    name: str
    members: List[StructMember] = field(default_factory=list)
    base_structs: List[str] = field(default_factory=list)
    nested_structs: List['StructDef'] = field(default_factory=list)
    storage_class: Optional[StorageClass] = None
    vtable: Optional[StructVTable] = None
    
    def calculate_vtable(self, module: ir.Module) -> StructVTable:
            """Calculate struct layout and generate TLD."""
            vtable = StructTypeHandler.calculate_vtable(self.members, module)
            vtable.struct_name = self.name
            #print(f"DEBUG calculate_vtable: Created vtable for '{self.name}' with field_types={vtable.field_types}")
            return vtable
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Type:
        """Generate LLVM IR for struct definition."""
        self.vtable = self.calculate_vtable(module)
        
        # Generate TLD global constant
        vtable_constant = self.vtable.to_llvm_constant(module)
        vtable_global = ir.GlobalVariable(
            module,
            vtable_constant.type,
            name=f"{self.name}.TLD"
        )
        vtable_global.initializer = vtable_constant
        vtable_global.linkage = 'internal'
        vtable_global.global_constant = True
        
        # Create proper LLVM struct type with named fields
        instance_type = StructTypeHandler.create_struct_type(self.name, self.vtable, module)
        
        # Store type information in module
        StructTypeHandler.initialize_struct_storage(module)
        
        module._struct_types[self.name] = instance_type
        module._struct_vtables[self.name] = self.vtable
        
        # Register in symbol table
        if hasattr(module, 'symbol_table'):
            #print(f"[STRUCT] Registering struct '{self.name}' in symbol table", file=sys.stderr)
            module.symbol_table.define(
                self.name,
                SymbolKind.STRUCT,
                type_spec=None,  # Structs don't have a TypeSystem, they ARE a type
                llvm_type=instance_type,
                llvm_value=vtable_global
            )
        
        # Store member type specifications for signedness tracking
        member_type_specs = {}
        for member in self.members:
            name = member.name
            type_spec = member.type_spec
            # For array types, we need to extract the element type
            # First check if type_spec is a TypeSystem instance with array properties
            if isinstance(type_spec, TypeSystem) and type_spec.is_array:

                # Determine correct is_signed value - look up from type system
                # Handle case where type_spec might be DataType instead of TypeSystem
                if isinstance(type_spec, DataType):
                    # If it's a raw DataType, default signedness based on the type
                    is_signed_value = type_spec in (DataType.SINT, DataType.CHAR, DataType.FLOAT)
                elif hasattr(type_spec, 'is_signed'):
                    is_signed_value = type_spec.is_signed
                else:
                    # Default to True for unknown types
                    is_signed_value = True
                    
                if hasattr(type_spec, 'custom_typename') and type_spec.custom_typename and hasattr(module, '_type_alias_specs'):
                    if type_spec.custom_typename in module._type_alias_specs:
                        alias_spec = module._type_alias_specs[type_spec.custom_typename]
                        if hasattr(alias_spec, 'is_signed'):
                            is_signed_value = alias_spec.is_signed
                        
                # Create element type spec - handle both TypeSystem and DataType
                if isinstance(type_spec, TypeSystem):
                    element_type_spec = TypeSystem(
                        base_type=type_spec.base_type,
                        is_signed=is_signed_value,
                        bit_width=type_spec.bit_width if hasattr(type_spec, 'bit_width') else None,
                        custom_typename=type_spec.custom_typename if hasattr(type_spec, 'custom_typename') else None,
                        is_const=type_spec.is_const if hasattr(type_spec, 'is_const') else False,
                        is_volatile=type_spec.is_volatile if hasattr(type_spec, 'is_volatile') else False,
                        storage_class=type_spec.storage_class if hasattr(type_spec, 'storage_class') else None,
                        # Don't copy array properties
                        is_array=False,
                        array_size=None,
                        array_dimensions=None,
                        is_pointer=False,
                        pointer_depth=0
                    )
                elif isinstance(type_spec, DataType):
                    # If type_spec is a raw DataType, create a basic TypeSystem
                    element_type_spec = TypeSystem(
                        base_type=type_spec,
                        is_signed=is_signed_value,
                        bit_width=None,
                        custom_typename=None,
                        is_const=False,
                        is_volatile=False,
                        storage_class=None,
                        is_array=False,
                        array_size=None,
                        array_dimensions=None,
                        is_pointer=False,
                        pointer_depth=0
                    )
                else:
                    raise TypeError(f"Expected TypeSystem or DataType, got {type(type_spec)}")
                
                # Attach element type to the array type spec
                type_spec.array_element_type = element_type_spec
                
            member_type_specs[name] = type_spec
        # DEBUG: Print member type specs
        #print(f"[STRUCT] Storing member specs for {self.name}", file=sys.stderr)
        #for mem_name, mem_spec in member_type_specs.items():
        #    print(f"  {mem_name}: is_array={mem_spec.is_array}, array_element_type={mem_spec.array_element_type}", file=sys.stderr)
        #    if mem_spec.array_element_type:
        #        print(f"    element is_signed={mem_spec.array_element_type.is_signed}", file=sys.stderr)
        module._struct_member_type_specs[self.name] = member_type_specs
        
        if self.storage_class is not None:
            module._struct_storage_classes[self.name] = self.storage_class
        
        # Handle member initial values
        for member in self.members:
            if member.initial_value is not None:
                if not hasattr(module, '_struct_member_defaults'):
                    module._struct_member_defaults = {}
                member_key = f"{self.name}.{member.name}"
                module._struct_member_defaults[member_key] = member.initial_value
        
        # Process nested structs
        for nested in self.nested_structs:
            nested.codegen(builder, module)
        
        return instance_type

@dataclass
class StructFieldAccess(Expression):
    """
    Access a field from a struct/object instance.

    Syntax: instance.field_name
    """
    struct_instance: Expression
    field_name: str

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        instance_val = self.struct_instance.codegen(builder, module)

        struct_name: Optional[str] = None
        is_pointer_hint = False

        # If accessing from an Identifier, look up its type in symbol table
        if isinstance(self.struct_instance, Identifier):
            var_name = self.struct_instance.name
            entry = module.symbol_table.lookup_variable(var_name)
            if entry and entry.type_spec:
                type_spec = entry.type_spec
                if getattr(type_spec, "custom_typename", None):
                    struct_name = type_spec.custom_typename
                is_pointer_hint = bool(getattr(type_spec, "is_pointer", False))

        # Resolve namespace-mangled struct name (using/imports) for vtables/types
        def _resolve_struct_name(name: Optional[str]) -> Optional[str]:
            if not name:
                return None

            # Prefer vtable hits (field access uses vtable metadata elsewhere)
            if hasattr(module, "_struct_vtables") and name in module._struct_vtables:
                return name

            if hasattr(module, "_using_namespaces") and hasattr(module, "_struct_vtables"):
                for ns in module._using_namespaces:
                    mangled = ns.replace("::", "__") + "__" + name
                    if mangled in module._struct_vtables:
                        return mangled

            # Fallback: also try _struct_types (some paths may rely on that)
            if hasattr(module, "_struct_types") and name in module._struct_types:
                return name

            if hasattr(module, "_using_namespaces") and hasattr(module, "_struct_types"):
                for ns in module._using_namespaces:
                    mangled = ns.replace("::", "__") + "__" + name
                    if mangled in module._struct_types:
                        return mangled

            return name

        struct_name = _resolve_struct_name(struct_name)

        # --- Fast path: pointer-to-struct/object -> use LLVM struct GEP by FIELD INDEX ---
        # This is the correct behavior for normal object/struct fields.
        if isinstance(instance_val.type, ir.PointerType):
            pointee = instance_val.type.pointee

            # Treat identified + literal structs as structs
            is_struct = isinstance(pointee, (ir.LiteralStructType, ir.IdentifiedStructType))
            if is_struct:
                struct_type = pointee

                # Ensure we have names metadata
                if not hasattr(struct_type, "names") or not struct_type.names:
                    raise ValueError("Struct type missing member names")

                try:
                    field_index = struct_type.names.index(self.field_name)
                except ValueError:
                    raise ValueError(f"Field '{self.field_name}' not found in struct")

                zero = ir.Constant(ir.IntType(32), 0)
                idx = ir.Constant(ir.IntType(32), field_index)
                field_ptr = builder.gep(instance_val, [zero, idx], inbounds=True, name=f"{self.field_name}_ptr")

                # Arrays/struct fields return pointer for further indexing/member access
                if isinstance(field_ptr.type, ir.PointerType):
                    fp = field_ptr.type.pointee
                    if isinstance(fp, ir.ArrayType):
                        return field_ptr
                    if isinstance(fp, (ir.LiteralStructType, ir.IdentifiedStructType)):
                        return field_ptr

                return builder.load(field_ptr, name=self.field_name)

        # --- Non-pointer / packed representation fallback ---
        # Load if we have a pointer-to-value (non-struct pointer scenarios)
        if isinstance(instance_val.type, ir.PointerType):
            instance = builder.load(instance_val, name="struct_load")
        else:
            instance = instance_val

        # Infer struct name if we didn't get it from scope info (or using-resolve failed)
        if struct_name is None:
            struct_name = StructTypeHandler.infer_struct_name(instance, module)
            struct_name = _resolve_struct_name(struct_name)

        # Need vtable for packed extraction paths
        vtable = getattr(module, "_struct_vtables", {}).get(struct_name)
        if not vtable:
            raise ValueError("Cannot determine struct type for field access")

        field_info = next((f for f in vtable.fields if f[0] == self.field_name), None)
        if not field_info:
            raise ValueError(f"Field '{self.field_name}' not found in struct '{struct_name}'")

        _, bit_offset, bit_width, alignment = field_info

        # If instance is integer-packed, do bit extraction
        if isinstance(instance.type, ir.IntType):
            instance_type = instance.type

            # Shift
            if bit_offset > 0:
                shifted = builder.lshr(instance, ir.Constant(instance_type, bit_offset))
            else:
                shifted = instance

            # Mask
            mask = (1 << bit_width) - 1
            masked = builder.and_(shifted, ir.Constant(instance_type, mask))

            # Trunc
            field_type = ir.IntType(bit_width)
            if instance_type.width != bit_width:
                return builder.trunc(masked, field_type, name=self.field_name)
            return masked

        # Struct value extraction by index (vtable order)
        if isinstance(instance.type, (ir.LiteralStructType, ir.IdentifiedStructType)):
            field_index = None
            for i, f in enumerate(vtable.fields):
                if f[0] == self.field_name:
                    field_index = i
                    break
            if field_index is None:
                raise ValueError(f"Field '{self.field_name}' not found in struct '{struct_name}'")
            return builder.extract_value(instance, field_index, name=self.field_name)

        # Array-backed packed struct (byte extraction)
        byte_offset = bit_offset // 8
        bit_in_byte = bit_offset % 8

        if bit_in_byte == 0 and bit_width % 8 == 0:
            field_bytes = bit_width // 8
            field_type = ir.IntType(bit_width)

            result = ir.Constant(field_type, 0)
            for i in range(field_bytes):
                byte_val = builder.extract_value(instance, byte_offset + i)
                byte_ext = builder.zext(byte_val, field_type)
                byte_shifted = builder.shl(byte_ext, ir.Constant(field_type, i * 8))
                result = builder.or_(result, byte_shifted)

            # Optional typed reinterpret (if your vtable carries it)
            if hasattr(vtable, "field_types") and self.field_name in vtable.field_types:
                target_type = vtable.field_types[self.field_name]
                if isinstance(target_type, ir.FloatType) and isinstance(result.type, ir.IntType):
                    result = builder.bitcast(result, target_type)
            return result

        raise NotImplementedError("Unaligned field access in large structs not yet supported")

@dataclass
class StructFieldAssign(Statement):
    struct_instance: Expression
    field_name: str
    value: Expression
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Generate inline field assignment code.
        
        This modifies the struct in place using bit manipulation.
        """
        # Get struct instance (must be lvalue/pointer)
        instance_ptr = self.struct_instance.codegen(builder, module)
        
        # Load current value to get struct type
        instance = builder.load(instance_ptr)
        
        # Get struct type
        struct_name = StructTypeHandler.infer_struct_name(instance, module)
        vtable = module._struct_vtables[struct_name]
        
        # Generate new value
        new_value = self.value.codegen(builder, module)
        
        # Use StructTypeHandler to assign the field value
        return StructTypeHandler.assign_field_value(
            builder, module, instance_ptr, struct_name, 
            self.field_name, new_value, vtable)


@dataclass
class StructRecast(Expression):
    """
    Zero-cost struct reinterpretation cast.
    
    Syntax: (TargetStruct)source_data
    
    This performs:
    1. Runtime size check (can be optimized away if size is known)
    2. Bitcast pointer (zero cost)
    3. No data movement or copying
    """
    target_type: str  # Struct type name
    source_expr: Expression
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Generate zero-cost reinterpret cast.
        
        Size checking is done at compile time when possible.
        Invalid casts result in undefined behavior (programmer's responsibility).
        """
        # Get source value
        source_value = self.source_expr.codegen(builder, module)

        # Use StructTypeHandler to perform the recast
        return StructTypeHandler.perform_struct_recast(
            builder, module, self.target_type, source_value)


# ============================================================================
# Helper Functions
# ============================================================================

def register_struct_type(module: ir.Module, type_name: str, bit_width: int, alignment: int):
    """
    Register a custom type in the module's type registry.
    
    Used for `unsigned data{N:M} as typename` declarations.
    """
    if not hasattr(module, '_custom_types'):
        module._custom_types = {}
    
    module._custom_types[type_name] = {
        'bit_width': bit_width,
        'alignment': alignment
        #'endianness': endianness
    }

def get_struct_vtable(module: ir.Module, struct_name: str) -> Optional[StructVTable]:
    """Get vtable for a struct type"""
    if not hasattr(module, '_struct_vtables'):
        return None
    return module._struct_vtables.get(struct_name)

# Object method
@dataclass
class ObjectMethod(ASTNode):
    name: str
    parameters: List[Parameter]
    return_type: TypeSystem
    body: Block
    is_private: bool = False
    is_const: bool = False
    is_volatile: bool = False

# Object definition
@dataclass
class ObjectDef(ASTNode):
    name: str
    methods: List[ObjectMethod] = field(default_factory=list)
    members: List[StructMember] = field(default_factory=list)
    #base_objects: List[str] = field(default_factory=list)
    nested_objects: List['ObjectDef'] = field(default_factory=list)
    nested_structs: List[StructDef] = field(default_factory=list)
    super_calls: List[Tuple[str, str, List[Expression]]] = field(default_factory=list)
    virtual_calls: List[Tuple[str, str, List[Expression]]] = field(default_factory=list)
    virtual_instances: List[Tuple[str, str, List[Expression]]] = field(default_factory=list)
    is_prototype: bool = False

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Type:
        # Initialize object storage
        ObjectTypeHandler.initialize_object_storage(module)
        
        # Create member types
        member_types, member_names = ObjectTypeHandler.create_member_types(self.members, module)
        
        # Create struct type
        struct_type = ObjectTypeHandler.create_struct_type(self.name, member_types, member_names, module)
        
        # Calculate field layout
        fields = ObjectTypeHandler.calculate_field_layout(self.members, member_types)
        
        # Create vtable
        ObjectTypeHandler.create_vtable(self.name, fields, module)
        
        # Register object in symbol table
        if hasattr(module, 'symbol_table'):
            #print(f"[OBJECT] Registering object '{self.name}' in symbol table", file=sys.stderr)
            module.symbol_table.define(
                self.name,
                SymbolKind.STRUCT,  # Objects are treated like structs for type purposes
                type_spec=None,
                llvm_type=struct_type,
                llvm_value=None
            )
        
        # PASS 1: Predeclare all methods
        method_funcs = {}

        for method in self.methods:
            func_type, func_name = ObjectTypeHandler.create_method_signature(
                self.name, method.name, method, struct_type, module)
            func = ObjectTypeHandler.predeclare_method(func_type, func_name, method, module)

            method_funcs[method.name] = func

        # --- PASS 2: Emit method bodies (skip prototypes) ---
        for method in self.methods:
            if isinstance(method, FunctionDef) and method.is_prototype:
                continue

            func = method_funcs.get(method.name)
            if func is None:
                raise RuntimeError(f"Internal error: missing function for method {method.name}")
        
            # Handle nested objects and structs
            ObjectTypeHandler.emit_method_body(method, func, self.name, module)
        
        return struct_type

# Extern declaration
@dataclass
class ExternBlock(Statement):
    """
    Extern block for FFI declarations.
    
    Syntax:
        extern {
            def function_name(params) -> return_type;
        };
    
    Or single declaration:
        extern def function_name(params) -> return_type;
    """
    declarations: List['FunctionDef']  # List of function prototypes
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> None:
        """Generate external function declarations"""
        for func_def in self.declarations:
            # Ensure these are prototypes
            if not func_def.is_prototype:
                raise ValueError(f"Extern functions must be prototypes (no body): {func_def.name}")
            
            # Generate the function declaration with external linkage using FunctionTypeHandler
            ret_type = TypeSystem.get_llvm_type(func_def.return_type,module)
            param_types = [TypeSystem.get_llvm_type(param.type_spec, module) for param in func_def.parameters]
            func_type = ir.FunctionType(ret_type, param_types)
            
            # Strip any namespace prefix that might have been added
            func_name = func_def.name or ""

            # Always define base_name no matter what
            base_name = func_name

            # Strip any namespace/prefix schemes you use
            if "::" in base_name:
                base_name = base_name.split("::")[-1]
            if "__" in base_name:
                base_name = base_name.split("__")[-1]

            # Now base_name is guaranteed defined
            if func_def.no_mangle:
                final_name = base_name
            else:
                # DO NOT mutate func_def.name; just pass base_name into mangler
                final_name = SymbolTable.mangle_function_name(base_name, func_def.parameters, func_def.return_type, False)
            
            # Create or get the function
            if final_name in module.globals:
                func = module.globals[final_name]
                if not isinstance(func, ir.Function):
                    raise ValueError(f"Name '{final_name}' already used for non-function")
            else:
                func = ir.Function(module, func_type, final_name)
            
            # Set external linkage
            func.linkage = 'external'
            
            # Name the parameters
            for i, param in enumerate(func.args):
                if i < len(func_def.parameters):
                    if func_def.parameters[i].name is not None:
                        param.name = func_def.parameters[i].name
                    else:
                        param.name = f"arg{i}"

# Namespace definition
@dataclass
class NamespaceDef(ASTNode):
    name: str
    functions: List[FunctionDef] = field(default_factory=list)
    structs: List[StructDef] = field(default_factory=list)
    objects: List[ObjectDef] = field(default_factory=list)
    enums: List[EnumDef] = field(default_factory=list)
    extern_blocks: List[ExternBlock] = field(default_factory=list)
    variables: List[VariableDeclaration] = field(default_factory=list)
    nested_namespaces: List['NamespaceDef'] = field(default_factory=list)
    base_namespaces: List[str] = field(default_factory=list)  # inheritance

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> None:
        """Generate LLVM IR for a namespace definition."""
        #print(f"[NAMESPACE] Processing namespace: {self.name}", file=sys.stderr)
        #print(f"[NAMESPACE]   Functions: {len(self.functions)}", file=sys.stderr)
        #print(f"[NAMESPACE]   Nested namespaces: {len(self.nested_namespaces)}", file=sys.stderr)
        # Register this namespace using NamespaceTypeHandler
        SymbolTable.register_namespace(module, self.name)

        # Register nested namespaces recursively using NamespaceTypeHandler
        for nested_ns in self.nested_namespaces:
            full_nested_name = f"{self.name}__{nested_ns.name}"
            #print("FULL NESTED NAME:",full_nested_name)
            SymbolTable.register_namespace(module, full_nested_name)
            SymbolTable.register_nested_namespaces(nested_ns, full_nested_name, module)
        
        # Add to using namespaces using NamespaceTypeHandler
        NamespaceTypeHandler.add_using_namespace(module, self.name)

        # Set current namespace context for this namespace
        if not hasattr(module, 'symbol_table'):
            raise RuntimeError("Module must have symbol_table for namespace support")

        original_namespace = module.symbol_table.current_namespace
        module.symbol_table.set_namespace(self.name)
        
        # Create builder context if we're at module level using NamespaceTypeHandler
        if builder is None or not hasattr(builder, 'block') or builder.block is None:
            work_builder = NamespaceTypeHandler.create_static_init_builder(module)
        else:
            work_builder = builder

        # Process extern blocks (ALWAYS global, no namespace mangling)
        # Extern declarations are inherently global and should not be namespaced
        for extern_block in self.extern_blocks:
            extern_block.codegen(work_builder, module)
        # Process nested namespaces FIRST (they may contain types we need)
        for nested_ns in self.nested_namespaces:
            NamespaceTypeHandler.process_nested_namespace(self.name, nested_ns, work_builder, module)

        # Process variables (including type declarations) using NamespaceTypeHandler
        for var in self.variables:
            try:
                NamespaceTypeHandler.process_namespace_variable(self.name, var, module)
            except Exception as e:
                var_name = getattr(var, 'name', '<unknown>')
                print(f"\nError processing variable '{var_name}' in namespace '{self.name}':")
                traceback.print_exc()
                raise

        # Process functions using NamespaceTypeHandler
        for func in self.functions:
            NamespaceTypeHandler.process_namespace_function(
                self.name, func, work_builder, module)

        # Process structs using NamespaceTypeHandler
        for struct in self.structs:
            NamespaceTypeHandler.process_namespace_struct(self.name, struct, work_builder, module)
        
        # Process objects using NamespaceTypeHandler
        for obj in self.objects:
            NamespaceTypeHandler.process_namespace_object(self.name, obj, work_builder, module)

        # Process enums using NamespaceTypeHandler
        for enum in self.enums:
            NamespaceTypeHandler.process_namespace_enum(self.name, enum, work_builder, module)

        # Process extern blocks (ALWAYS global, no namespace mangling)
        # Extern declarations are inherently global and should not be namespaced
        for extern_block in self.extern_blocks:
            extern_block.codegen(work_builder, module)

        # Finalize static init function using NamespaceTypeHandler
        NamespaceTypeHandler.finalize_static_init(module)
        
        # Restore original namespace context
        module._current_namespace = original_namespace

        return None

# Import statement
@dataclass
class UsingStatement(Statement):
    namespace_path: str  # e.g., "standard::io"
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> None:
        """Using statements are compile-time directives - no runtime code generated"""
        # For now, just store the namespace information for symbol resolution
        if not hasattr(module, '_using_namespaces'):
            module._using_namespaces = []
        self.namespace_path = self.namespace_path.replace("::","__")
        module._using_namespaces.append(self.namespace_path)
        #print(f"[USING] Registered namespace: {self.namespace_path}", file=sys.stderr)

# Function definition statement
@dataclass
class FunctionDefStatement(Statement):
    function_def: FunctionDef

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> Optional[ir.Value]:
        # Delegate codegen to the contained FunctionDef
        self.function_def.codegen(builder, module)
        return None

# Union definition statement
@dataclass
class UnionDefStatement(Statement):
    union_def: UnionDef

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> Optional[ir.Value]:
        # Delegate codegen to the contained UnionDef
        self.union_def.codegen(builder, module)
        return None

# Struct definition statement
@dataclass
class StructDefStatement(Statement):
    struct_def: StructDef

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> Optional[ir.Value]:
        # Delegate codegen to the contained StructDef
        self.struct_def.codegen(builder, module)
        return None

# Object definition statement
@dataclass
class ObjectDefStatement(Statement):
    object_def: ObjectDef

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> Optional[ir.Value]:
        self.object_def.codegen(builder, module)
        return None

# Namespace definition statement
@dataclass
class NamespaceDefStatement(Statement):
    namespace_def: NamespaceDef

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> Optional[ir.Value]:
        self.namespace_def.codegen(builder, module)
        return None

# Program root
@dataclass
class Program(ASTNode):
    symbol_table: 'SymbolTable'  # Forward reference since SymbolTable is in ftypesys
    statements: List[Statement] = field(default_factory=list)

    # DO NOT DO TRY/EXCEPT AROUND THE STATEMENT CODEGEN CALLS IN THIS CODEGEN
    # IT WILL CAPTURE EVERYTHING AND MAKE A VAGUE ERROR UNLOCATABLE
    # CAPTURE CODEGEN CALLS AT OTHER NODES TO IDENTIFY THE CALL SITE

    def codegen(self, module: ir.Module = None) -> ir.Module:
        print("[AST] Begining codegen for Flux program ...")
        print(f"[AST] Total statements in AST: {len(self.statements)}", file=sys.stderr)
        namespace_count = sum(1 for s in self.statements if isinstance(s, NamespaceDef))
        print(f"[AST] Namespace definitions: {namespace_count}", file=sys.stderr)
        for s in self.statements:
            if isinstance(s, NamespaceDef):
                print(f"[AST]   - namespace {s.name} (funcs: {len(s.functions)}, nested: {len(s.nested_namespaces)})", file=sys.stderr)
        if module is None:
            module = ir.Module(name='flux_module') # Update to support module system.
        
        # Validate and attach symbol table to module
        if not isinstance(self.symbol_table, SymbolTable):
            print(f"[ERROR] Program.symbol_table is {type(self.symbol_table)}, not SymbolTable!", file=sys.stderr)
            print(f"[ERROR] Creating new SymbolTable to replace it", file=sys.stderr)
            self.symbol_table = SymbolTable()
        
        module.symbol_table = self.symbol_table
        
        # Create global builder with no function context
        builder = ir.IRBuilder()
        # Symbol table already at global scope (level 0)
        # Track initialized unions for immutability enforcement
        builder.initialized_unions = set()

        # 3-pass compilation
        print("[AST] Pass 1: Processing extern blocks...")
        for stmt in self.statements:
            if isinstance(stmt, ExternBlock):
                stmt.codegen(builder, module)

        print("[AST] Pass 2: Processing using statements...")
        for stmt in self.statements:
            if isinstance(stmt, UsingStatement):
                stmt.codegen(builder, module)

        # Pass 3: Process all other statements
        print("[AST] Pass 3: Processing all other statements...")
        for stmt in self.statements:
            if not isinstance(stmt, UsingStatement) and not isinstance(stmt, ExternBlock):
                stmt.codegen(builder, module)
        
        return module

# Example usage
if __name__ == "__main__":
    # Create a simple program AST
    main_func = FunctionDef(
        name="main",
        parameters=[],
        return_type=TypeSystem(base_type=DataType.SINT),
        body=Block([
            ReturnStatement(Literal(0, DataType.SINT))
        ])
    )
    
    program = Program(
        statements=[
            FunctionDefStatement(main_func)
        ]
    )
    
    print("AST created successfully!")
    print(f"Program has {len(program.statements)} statements")
    print(f"Main function has {len(main_func.body.statements)} statements")