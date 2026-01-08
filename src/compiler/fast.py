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
import os

## TO DO
#
# -> Add `lext` keyword to set external linkage.
#    \_> Cause gv.linkage = 'external'
#
# -> Add `extern` keyword for FFI.
#
## /TODO

# Base classes first
@dataclass
class ASTNode:
    """Base class for all AST nodes"""
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> Any:
        raise NotImplementedError(f"codegen not implemented for {self.__class__.__name__}")

# Enums and simple types
class DataType(Enum):
    INT = "int"
    FLOAT = "float"
    CHAR = "char"
    BOOL = "bool"
    DATA = "data"
    VOID = "void"
    THIS = "this"

class StorageClass(Enum):
    """Storage class specifiers for variables"""
    AUTO = "auto"         # Default: automatic storage (stack for locals, global for module-level)
    STACK = "stack"       # Force stack allocation
    HEAP = "heap"         # Force heap allocation
    GLOBAL = "global"     # Global/static storage
    LOCAL = "local"       # Local scope (restricted to current stack)
    REGISTER = "register" # Hint: keep in register if possible

class Operator(Enum):
    ADD = "+"
    SUB = "-"
    MUL = "*"
    DIV = "/"
    MOD = "%"
    NOT = "!"
    POWER = "^"
    XOR = "^^"
    OR = "||"
    AND = "&&"
    NOR = "!|"
    NAND = "!&"
    INCREMENT = "++"
    DECREMENT = "--"
    
    # Comparison
    EQUAL = "=="
    NOT_EQUAL = "!="
    LESS_THAN = "<"
    LESS_EQUAL = "<="
    GREATER_THAN = ">"
    GREATER_EQUAL = ">="
    
    # Shift
    BITSHIFT_LEFT = "<<"
    BITSHIFT_RIGHT = ">>"
    
    # Assignment
    ASSIGN = "="
    PLUS_ASSIGN = "+="
    MINUS_ASSIGN = "-="
    MULTIPLY_ASSIGN = "*="
    DIVIDE_ASSIGN = "/="
    MODULO_ASSIGN = "%="
    POWER_ASSIGN = "^="
    XOR_ASSIGN = "^^="
    BITSHIFT_LEFT_ASSIGN = "<<="
    BITSHIFT_RIGHT_ASSIGN = ">>="
    
    # Other operators
    ADDRESS_OF = "@"
    RANGE = ".."
    SCOPE = "::"
    QUESTION = "?"
    COLON = ":"

    # Directionals
    RETURN_ARROW = "->"
    CHAIN_ARROW = "<-"
    RECURSE_ARROW = "<~"

# Literal values (no dependencies)
@dataclass
class Literal(ASTNode):
    value: Any
    type: DataType

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        if self.type == DataType.INT:
            # Always generate i32 for DataType.INT literals
            return ir.Constant(ir.IntType(32), int(self.value) if isinstance(self.value, str) else self.value)
        elif self.type == DataType.FLOAT:
            return ir.Constant(ir.FloatType(), float(self.value))
        elif self.type == DataType.BOOL:
            return ir.Constant(ir.IntType(1), bool(self.value))
        elif self.type == DataType.CHAR:
            if isinstance(self.value, str):
                if len(self.value) == 0:
                    # Handle empty string - return null character
                    return ir.Constant(ir.IntType(8), 0)
                else:
                    return ir.Constant(ir.IntType(8), ord(self.value[0]))
            else:
                return ir.Constant(ir.IntType(8), self.value)
        elif self.type == DataType.VOID:
            return None
        elif self.type == DataType.DATA:
            # Handle array literals
            if isinstance(self.value, list):
                # For now, just return None for array literals - they should be handled at a higher level
                return None
            # Handle struct literals (dictionaries with field names -> values)
            elif isinstance(self.value, dict):
                return self._handle_struct_literal(builder, module)
            # Handle other DATA types
            if hasattr(module, '_type_aliases') and str(self.type) in module._type_aliases:
                llvm_type = module._type_aliases[str(self.type)]
                if isinstance(llvm_type, ir.IntType):
                    return ir.Constant(llvm_type, int(self.value) if isinstance(self.value, str) else self.value)
                elif isinstance(llvm_type, ir.FloatType):
                    return ir.Constant(llvm_type, float(self.value))
            raise ValueError(f"Unsupported DATA literal: {self.value}")
        else:
            # Handle custom types
            if hasattr(module, '_type_aliases') and str(self.type) in module._type_aliases:
                llvm_type = module._type_aliases[str(self.type)]
                if isinstance(llvm_type, ir.IntType):
                    return ir.Constant(llvm_type, int(self.value) if isinstance(self.value, str) else self.value)
                elif isinstance(llvm_type, ir.FloatType):
                    return ir.Constant(llvm_type, float(self.value))
        raise ValueError(f"Unsupported literal type: {self.type}")

    def _handle_struct_literal(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Handle struct literal initialization (e.g., {a = 10, b = 20})"""
        if not isinstance(self.value, dict):
            raise ValueError("Expected dictionary for struct literal")
        
        # Look for a compatible struct type in the module
        struct_type = None
        field_names = list(self.value.keys())
        
        if hasattr(module, '_struct_types'):
            for struct_name, candidate_type in module._struct_types.items():
                if hasattr(candidate_type, 'names'):
                    # Check if all fields in the literal exist in this struct
                    if all(field in candidate_type.names for field in field_names):
                        struct_type = candidate_type
                        break
        
        if struct_type is None:
            raise ValueError(f"No compatible struct type found for fields: {field_names}")
        
        ## -- URGENT
        ## TODO -> REWORK THIS V V V
        # Allocate space for the struct instance
        if builder.scope is None:
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
                        isinstance(expected_type, ir.PointerType) and
                        isinstance(expected_type.pointee, ir.IntType) and
                        expected_type.pointee.width == 8):
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
                        zero = ir.Constant(ir.IntType(1), 0)
                        str_ptr = gv.gep([zero, zero])
                        field_values.append(str_ptr)
                    else:
                        # Normal field initialization
                        field_value = field_expr.codegen(builder, module)
                        field_values.append(field_value)
                else:
                    # Field not specified, use zero initialization
                    field_index = struct_type.names.index(member_name)
                    field_type = struct_type.elements[field_index]
                    field_values.append(ir.Constant(field_type, 0))
            
            # Create struct constant
            return ir.Constant(struct_type, field_values)
        else:
            # Local context - create an alloca and initialize fields
            struct_ptr = builder.alloca(struct_type, name="struct_literal")
            
            # Initialize each field
            for field_name, field_value_expr in self.value.items():
                # Find field index
                if field_name not in struct_type.names:
                    raise ValueError(f"Field '{field_name}' not found in struct")
                
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
                    isinstance(expected_type, ir.PointerType) and
                    isinstance(expected_type.pointee, ir.IntType) and
                    expected_type.pointee.width == 8):
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
                    zero = ir.Constant(ir.IntType(1), 0)
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

# Type definitions
@dataclass
class TypeSpec:
    base_type: Union[DataType, str]
    is_signed: bool = True
    is_const: bool = False
    is_volatile: bool = False
    bit_width: Optional[int] = None
    alignment: Optional[int] = None
    is_array: bool = False
    array_size: Optional[int] = None
    array_dimensions: Optional[List[Optional[int]]] = None
    is_pointer: bool = False
    pointer_depth: int = 0
    custom_typename: Optional[str] = None
    storage_class: Optional[StorageClass] = None  # NEW: storage class

    def get_llvm_type(self, module: ir.Module) -> ir.Type:
        """Get LLVM type for this TypeSpec, resolving custom type names"""
        
        # URGENT
        # MAYBE HERE? MAYBE THERE? MAYBE Z:\LOST\FOLDER
        # MAYBE THE MOON!
        # TODO -> FIX THIS BULLSHIT VVV WHAT THE FUCK IS THIS
        if self.custom_typename:
            # Look up the type alias with various namespace prefixes
            potential_names = [
                self.custom_typename,
                f"standard__types__{self.custom_typename}",
                f"standard__{self.custom_typename}",
                f"types__{self.custom_typename}"
            ]
            
            for name in potential_names:
                if hasattr(module, '_type_aliases') and name in module._type_aliases:
                    base_type = module._type_aliases[name]
                    
                    # If it's an array type with no size specified, return pointer to element
                    if isinstance(base_type, ir.ArrayType) and not self.is_array:
                        return ir.PointerType(base_type.element)
                    
                    return base_type
            
            # Check struct types
            for name in potential_names:
                if hasattr(module, '_struct_types') and name in module._struct_types:
                    return module._struct_types[name]
            
            # If not found, raise error
            raise NameError(f"Unknown type: {self.custom_typename} (searched: {potential_names})")
        
        # Handle built-in types
        if self.base_type == DataType.INT:
            return ir.IntType(32)
        elif self.base_type == DataType.FLOAT:
            return ir.FloatType()
        elif self.base_type == DataType.BOOL:
            return ir.IntType(1)
        elif self.base_type == DataType.CHAR:
            return ir.IntType(8)
        elif self.base_type == DataType.VOID:
            return ir.VoidType()
        elif self.base_type == DataType.DATA:
            # Only require bit_width for explicit data{N} types without custom names
            if self.bit_width is None:
                raise ValueError(f"DATA type missing bit_width for {self}")
            return ir.IntType(self.bit_width)
        else:
            raise ValueError(f"Unsupported type: {self.base_type}")
    
    def get_llvm_type_with_array(self, module: ir.Module) -> ir.Type:
        """Get LLVM type including array/pointer specifications"""
        
        # Get base type (this handles custom type names)
        base_type = self.get_llvm_type(module)
        
        # Handle array types - support multi-dimensional arrays
        if self.is_array and self.array_dimensions:
            # Build array type from the inside out
            # e.g., byte[4][4] becomes ArrayType(ArrayType(byte, 4), 4)
            current_type = base_type
            for dim in reversed(self.array_dimensions):
                if dim is not None:
                    current_type = ir.ArrayType(current_type, dim)
                else:
                    # Unsized array dimension - use pointer
                    current_type = ir.PointerType(current_type)
            return current_type
        elif self.is_array:
            # Single-dimensional array (backward compatibility)
            if self.array_size is not None:
                # Fixed-size array
                return ir.ArrayType(base_type, self.array_size)
            else:
                # Unsized array - return pointer to element type
                if isinstance(base_type, ir.PointerType):
                    return base_type
                else:
                    return ir.PointerType(base_type)
        
        # Handle pointer types
        if self.is_pointer:
            return ir.PointerType(base_type)
        
        return base_type

@dataclass
class CustomType(ASTNode):
    name: str
    type_spec: TypeSpec

# Expressions (built up from simple to complex)
@dataclass
class Expression(ASTNode):
    pass

@dataclass
class Identifier(Expression):
    name: str

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Look up the name in the current scope
        if builder.scope is not None and self.name in builder.scope:
            ptr = builder.scope[self.name]
            
            # Get type information if available
            type_spec = None
            if hasattr(builder, 'scope_type_info') and self.name in builder.scope_type_info:
                type_spec = builder.scope_type_info[self.name]
            
            # Handle special case for 'this' pointer
            if self.name == "this":
                if type_spec and not hasattr(ptr, '_flux_type_spec'):
                    ptr._flux_type_spec = type_spec
                return ptr
            
            # For arrays, return the pointer directly (don't load)
            if isinstance(ptr.type, ir.PointerType) and isinstance(ptr.type.pointee, ir.ArrayType):
                if type_spec and not hasattr(ptr, '_flux_type_spec'):
                    ptr._flux_type_spec = type_spec
                return ptr
            
            # For structs, return the pointer directly (don't load)
            elif isinstance(ptr.type, ir.PointerType) and isinstance(ptr.type.pointee, ir.LiteralStructType):
                if type_spec and not hasattr(ptr, '_flux_type_spec'):
                    ptr._flux_type_spec = type_spec
                return ptr
            
            # Load the value if it's a non-array, non-struct pointer type
            elif isinstance(ptr.type, ir.PointerType):
                is_volatile = hasattr(builder, 'volatile_vars') and self.name in builder.volatile_vars
                ret_val = builder.load(ptr, name=self.name)
                if is_volatile:
                    ret_val.volatile = True
                # Attach type metadata to loaded value
                if type_spec and not hasattr(ret_val, '_flux_type_spec'):
                    ret_val._flux_type_spec = type_spec
                return ret_val
            
            # For non-pointer types, attach metadata and return
            if type_spec and not hasattr(ptr, '_flux_type_spec'):
                ptr._flux_type_spec = type_spec
            return ptr
        
        # Check for global variables
        if self.name in module.globals:
            gvar = module.globals[self.name]
            
            # Try to get type information from global metadata
            type_spec = None
            if hasattr(module, '_global_type_info') and self.name in module._global_type_info:
                type_spec = module._global_type_info[self.name]
            
            # For arrays, return the pointer directly (don't load)
            if isinstance(gvar.type, ir.PointerType) and isinstance(gvar.type.pointee, ir.ArrayType):
                if type_spec and not hasattr(gvar, '_flux_type_spec'):
                    gvar._flux_type_spec = type_spec
                return gvar
            
            # For structs, return the pointer directly (don't load)
            elif isinstance(gvar.type, ir.PointerType) and isinstance(gvar.type.pointee, ir.LiteralStructType):
                if type_spec and not hasattr(gvar, '_flux_type_spec'):
                    gvar._flux_type_spec = type_spec
                return gvar
            
            # Load the value if it's a non-array, non-struct pointer type
            elif isinstance(gvar.type, ir.PointerType):
                is_volatile = hasattr(builder, 'volatile_vars') and self.name in getattr(builder, 'volatile_vars', set())
                ret_val = builder.load(gvar, name=self.name)
                if is_volatile:
                    ret_val.volatile = True
                # Attach type metadata
                if type_spec and not hasattr(ret_val, '_flux_type_spec'):
                    ret_val._flux_type_spec = type_spec
                return ret_val
            
            if type_spec and not hasattr(gvar, '_flux_type_spec'):
                gvar._flux_type_spec = type_spec
            return gvar
        
        # Check if this is a custom type
        if hasattr(module, '_type_aliases') and self.name in module._type_aliases:
            return module._type_aliases[self.name]
        
        # Check for namespace-qualified names using 'using' statements
        if hasattr(module, '_using_namespaces'):
            for namespace in module._using_namespaces:
                # Convert namespace path to mangled name format
                mangled_prefix = namespace.replace('::', '__') + '__'
                mangled_name = mangled_prefix + self.name
                
                # Check in global variables with mangled name
                if mangled_name in module.globals:
                    gvar = module.globals[mangled_name]
                    
                    # Try to get type information
                    type_spec = None
                    if hasattr(module, '_global_type_info') and mangled_name in module._global_type_info:
                        type_spec = module._global_type_info[mangled_name]
                    
                    # For arrays, return the pointer directly (don't load)
                    if isinstance(gvar.type, ir.PointerType) and isinstance(gvar.type.pointee, ir.ArrayType):
                        if type_spec and not hasattr(gvar, '_flux_type_spec'):
                            gvar._flux_type_spec = type_spec
                        return gvar
                    
                    # For structs, return the pointer directly (don't load)
                    elif isinstance(gvar.type, ir.PointerType) and isinstance(gvar.type.pointee, ir.LiteralStructType):
                        if type_spec and not hasattr(gvar, '_flux_type_spec'):
                            gvar._flux_type_spec = type_spec
                        return gvar
                    
                    # Load the value if it's a non-array, non-struct pointer type
                    elif isinstance(gvar.type, ir.PointerType):
                        is_volatile = hasattr(builder, 'volatile_vars') and self.name in getattr(builder, 'volatile_vars', set())
                        ret_val = builder.load(gvar, name=self.name)
                        if is_volatile:
                            ret_val.volatile = True
                        # Attach type metadata
                        if type_spec and not hasattr(ret_val, '_flux_type_spec'):
                            ret_val._flux_type_spec = type_spec
                        return ret_val
                    
                    if type_spec and not hasattr(gvar, '_flux_type_spec'):
                        gvar._flux_type_spec = type_spec
                    return gvar
                
                # Check in type aliases with mangled name
                if hasattr(module, '_type_aliases') and mangled_name in module._type_aliases:
                    return module._type_aliases[mangled_name]
            
        raise NameError(f"Unknown identifier: {self.name}")

@dataclass
class QualifiedName(Expression):
    """Represents qualified names with super:: or virtual:: or super::virtual:: for objects or structs"""
    qualifiers: List[str]
    member: Optional[str] = None
    
    def __str__(self):
        qual_str = "::".join(self.qualifiers)
        if self.member:
            return f"{qual_str}.{self.member}"
        return qual_str

# Helper utilities for array operations
def is_array_or_array_pointer(val: ir.Value) -> bool:
    """Check if value is an array type or a pointer to an array type"""
    return (isinstance(val.type, ir.ArrayType) or 
            (isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, ir.ArrayType)))

def is_array_pointer(val: ir.Value) -> bool:
    """Check if value is a pointer to an array type"""
    return (isinstance(val.type, ir.PointerType) and 
            isinstance(val.type.pointee, ir.ArrayType))

def get_array_info(val: ir.Value) -> tuple:
    """Get (element_type, length) for array or array pointer"""
    if isinstance(val.type, ir.ArrayType):
        # Direct array type (loaded from a pointer)
        return (val.type.element, val.type.count)
    elif isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, ir.ArrayType):
        # Pointer to array type
        array_type = val.type.pointee
        return (array_type.element, array_type.count)
    else:
        raise ValueError(f"Value is not an array or array pointer: {val.type}")

def emit_memcpy(builder: ir.IRBuilder, module: ir.Module, dst_ptr: ir.Value, src_ptr: ir.Value, bytes: int) -> None:
    """Emit llvm.memcpy intrinsic call"""
    # Declare llvm.memcpy.p0i8.p0i8.i64 if not already declared
    memcpy_name = "llvm.memcpy.p0i8.p0i8.i64"
    if memcpy_name not in module.globals:
        memcpy_type = ir.FunctionType(
            ir.VoidType(),
            [ir.PointerType(ir.IntType(8)),  # dst
             ir.PointerType(ir.IntType(8)),  # src
             ir.IntType(64),                 # len
             ir.IntType(1)]                  # volatile
        )
        memcpy_func = ir.Function(module, memcpy_type, name=memcpy_name)
        memcpy_func.attributes.add('nounwind')
    else:
        memcpy_func = module.globals[memcpy_name]
    
    # Cast pointers to i8* if needed
    i8_ptr = ir.PointerType(ir.IntType(8))
    if dst_ptr.type != i8_ptr:
        dst_ptr = builder.bitcast(dst_ptr, i8_ptr)
    if src_ptr.type != i8_ptr:
        src_ptr = builder.bitcast(src_ptr, i8_ptr)
    
    # Call memcpy
    builder.call(memcpy_func, [
        dst_ptr,
        src_ptr,
        ir.Constant(ir.IntType(64), bytes),
        ir.Constant(ir.IntType(1), 0)  # not volatile
    ])

@dataclass
class BinaryOp(Expression):
    left: Expression
    operator: Operator
    right: Expression

    def _literal_string_to_array_ptr(self, builder: ir.IRBuilder, module: ir.Module, lit: Literal, name_hint: str) -> ir.Value:
        """Turn a string Literal(DataType.CHAR with python str value) into a pointer-to-array value preserving array semantics.
        Returns a pointer to the first element (via gep) of an internal global array. The pointee is an ArrayType(i8, N).
        """
        if not isinstance(lit, Literal) or lit.type != DataType.CHAR or not isinstance(lit.value, str):
            raise ValueError("Expected string Literal for conversion")
        string_bytes = lit.value.encode('ascii')
        arr_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
        const_arr = ir.Constant(arr_ty, bytearray(string_bytes))
        gname = f".str.binop.{name_hint}.{id(lit)}"
        gv = ir.GlobalVariable(module, const_arr.type, name=gname)
        gv.linkage = 'internal'
        gv.global_constant = True
        gv.initializer = const_arr
        zero = ir.Constant(ir.IntType(1), 0)
        ptr = builder.gep(gv, [zero, zero], name=f"{name_hint}_str_ptr")
        # Mark as array pointer for downstream logic that preserves array semantics
        ptr.type._is_array_pointer = True
        return ptr

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Attempt to promote string literals to array pointers when using + or - for concatenation
        left_expr, right_expr = self.left, self.right
        left_val = self.left.codegen(builder, module)
        right_val = self.right.codegen(builder, module)
        # Handle pointer arithmetic - treat pointers as integers
        if isinstance(left_val.type, ir.PointerType) or isinstance(right_val.type, ir.PointerType):
            # For pointer arithmetic, convert to intptr and back
            intptr_type = ir.IntType(32)  # Use 64-bit for addresses
            
            if isinstance(left_val.type, ir.PointerType):
                left_val = builder.ptrtoint(left_val, intptr_type, name="ptr_to_int")
            
            if isinstance(right_val.type, ir.PointerType):
                right_val = builder.ptrtoint(right_val, intptr_type, name="ptr_to_int")
            
            # Now do the arithmetic on integers
            if self.operator == Operator.ADD:
                result = builder.add(left_val, right_val, name="ptr_add")
            elif self.operator == Operator.SUB:
                result = builder.sub(left_val, right_val, name="ptr_sub")
            
            # Return as integer - let Assignment cast back to pointer if needed
            return result
        if self.operator in (Operator.ADD, Operator.SUB):
            # Fast path: both operands are string literals -> compile-time constant concat
            if isinstance(left_expr, Literal) and isinstance(right_expr, Literal) \
                and left_expr.type == DataType.CHAR and right_expr.type == DataType.CHAR \
                and isinstance(left_expr.value, str) and isinstance(right_expr.value, str):
                # Build concatenated constant array
                concat = left_expr.value + (right_expr.value if self.operator == Operator.ADD else '')
                lit_concat = Literal(concat, DataType.CHAR)
                return self._literal_string_to_array_ptr(builder, module, lit_concat, "concat")
            # Otherwise, codegen operands first
            left_val = left_expr.codegen(builder, module)
            right_val = right_expr.codegen(builder, module)
            # Promote any string literal that resulted in scalar i8 into array pointer
            def promote_if_scalar_char(val, expr, hint):
                if isinstance(expr, Literal) and expr.type == DataType.CHAR and isinstance(expr.value, str):
                    # If val is i8, promote to array pointer using the literal content
                    if isinstance(val.type, ir.IntType) and val.type.width == 8:
                        return self._literal_string_to_array_ptr(builder, module, expr, hint)
                return val
            left_val = promote_if_scalar_char(left_val, left_expr, "lhs")
            right_val = promote_if_scalar_char(right_val, right_expr, "rhs")
        else:
            # Non-concat operators: regular codegen
            left_val = left_expr.codegen(builder, module)
            right_val = right_expr.codegen(builder, module)
        
        # Handle array concatenation (ADD) and subtraction (SUB)
        if (self.operator in (Operator.ADD, Operator.SUB) and 
            is_array_or_array_pointer(left_val) and is_array_or_array_pointer(right_val)):
            # Get array information
            left_elem_type, left_len = get_array_info(left_val)
            right_elem_type, right_len = get_array_info(right_val)
            # Type compatibility check
            if left_elem_type != right_elem_type:
                raise ValueError(f"Cannot {self.operator.value} arrays with different element types: {left_elem_type} vs {right_elem_type}")
            # Calculate result length
            if self.operator == Operator.ADD:
                result_len = left_len + right_len
            else:  # SUB
                result_len = max(left_len - right_len, 0)
            # Create result array type
            result_array_type = ir.ArrayType(left_elem_type, result_len)
            # Check if both operands are global constants for compile-time concatenation
            if (isinstance(left_val, ir.GlobalVariable) and 
                isinstance(right_val, ir.GlobalVariable) and 
                getattr(left_val, 'global_constant', False) and getattr(right_val, 'global_constant', False)):
                # Compile-time concatenation of global constants
                return self._create_global_array_concat(module, left_val, right_val, result_array_type, self.operator)
            else:
                # Runtime concatenation
                return self._create_runtime_array_concat(builder, module, left_val, right_val, result_array_type, self.operator)
        
        # Ensure types match by casting if necessary
        if left_val.type != right_val.type:
            if isinstance(left_val.type, ir.IntType) and isinstance(right_val.type, ir.IntType):
                # Promote to the wider type
                if left_val.type.width > right_val.type.width:
                    right_val = builder.zext(right_val, left_val.type)
                else:
                    left_val = builder.zext(left_val, right_val.type)
            elif isinstance(left_val.type, ir.FloatType) and isinstance(right_val.type, ir.IntType):
                right_val = builder.sitofp(right_val, left_val.type)
            elif isinstance(left_val.type, ir.IntType) and isinstance(right_val.type, ir.FloatType):
                left_val = builder.sitofp(left_val, right_val.type)
        
        if self.operator == Operator.ADD:
            if isinstance(left_val.type, ir.FloatType):
                return builder.fadd(left_val, right_val)
            else:
                return builder.add(left_val, right_val)
        elif self.operator == Operator.SUB:
            if isinstance(left_val.type, ir.FloatType):
                return builder.fsub(left_val, right_val)
            else:
                return builder.sub(left_val, right_val)
        elif self.operator == Operator.MUL:
            if isinstance(left_val.type, ir.FloatType):
                return builder.fmul(left_val, right_val)
            else:
                return builder.mul(left_val, right_val)
        elif self.operator == Operator.DIV:
            if isinstance(left_val.type, ir.FloatType):
                return builder.fdiv(left_val, right_val)
            else:
                return builder.sdiv(left_val, right_val)
        elif self.operator == Operator.EQUAL:
            if isinstance(left_val.type, ir.FloatType):
                return builder.fcmp_ordered('==', left_val, right_val)
            else:
                return builder.icmp_signed('==', left_val, right_val)
        elif self.operator == Operator.NOT_EQUAL:
            if isinstance(left_val.type, ir.FloatType):
                return builder.fcmp_ordered('!=', left_val, right_val)
            else:
                return builder.icmp_signed('!=', left_val, right_val)
        elif self.operator == Operator.LESS_THAN:
            if isinstance(left_val.type, ir.FloatType):
                return builder.fcmp_ordered('<', left_val, right_val)
            else:
                return builder.icmp_signed('<', left_val, right_val)
        elif self.operator == Operator.LESS_EQUAL:
            if isinstance(left_val.type, ir.FloatType):
                return builder.fcmp_ordered('<=', left_val, right_val)
            else:
                return builder.icmp_signed('<=', left_val, right_val)
        elif self.operator == Operator.GREATER_THAN:
            if isinstance(left_val.type, ir.FloatType):
                return builder.fcmp_ordered('>', left_val, right_val)
            else:
                return builder.icmp_signed('>', left_val, right_val)
        elif self.operator == Operator.GREATER_EQUAL:
            if isinstance(left_val.type, ir.FloatType):
                return builder.fcmp_ordered('>=', left_val, right_val)
            else:
                return builder.icmp_signed('>=', left_val, right_val)
        elif self.operator == Operator.AND:
            return builder.and_(left_val, right_val)
        elif self.operator == Operator.OR:
            return builder.or_(left_val, right_val)
        elif self.operator == Operator.XOR:
            return builder.xor(left_val, right_val)
        elif self.operator == Operator.MOD:
            if isinstance(left_val.type, ir.FloatType):
                return builder.frem(left_val, right_val)
            else:
                return builder.srem(left_val, right_val)
        elif self.operator == Operator.BITSHIFT_LEFT:
            return builder.shl(left_val, right_val)
        elif self.operator == Operator.BITSHIFT_RIGHT:
            return builder.ashr(left_val, right_val)
        elif self.operator == Operator.NOR:
            # NOR is !(A | B) = NOT(OR(A, B))
            or_result = builder.or_(left_val, right_val)
            return builder.not_(or_result)
        elif self.operator == Operator.NAND:
            # NAND is !(A & B) = NOT(AND(A, B))
            and_result = builder.and_(left_val, right_val)
            return builder.not_(and_result)
        elif self.operator == Operator.POWER:
            # Power operator using LLVM intrinsics
            if isinstance(left_val.type, ir.FloatType):
                # For floating point, use llvm.pow
                pow_name = "llvm.pow.f64" if left_val.type == ir.DoubleType() else "llvm.pow.f32"
                if pow_name not in module.globals:
                    pow_type = ir.FunctionType(left_val.type, [left_val.type, left_val.type])
                    pow_func = ir.Function(module, pow_type, name=pow_name)
                    pow_func.attributes.add('nounwind')
                    pow_func.attributes.add('readonly')
                else:
                    pow_func = module.globals[pow_name]
                return builder.call(pow_func, [left_val, right_val])
            else:
                # For integers, implement as repeated multiplication (or call pow function)
                # Convert to double, use pow, then convert back
                double_type = ir.DoubleType()
                left_fp = builder.sitofp(left_val, double_type)
                right_fp = builder.sitofp(right_val, double_type)
                
                pow_name = "llvm.pow.f64"
                if pow_name not in module.globals:
                    pow_type = ir.FunctionType(double_type, [double_type, double_type])
                    pow_func = ir.Function(module, pow_type, name=pow_name)
                    pow_func.attributes.add('nounwind')
                    pow_func.attributes.add('readonly')
                else:
                    pow_func = module.globals[pow_name]
                
                result_fp = builder.call(pow_func, [left_fp, right_fp])
                return builder.fptosi(result_fp, left_val.type)
        else:
            raise ValueError(f"Unsupported operator: {self.operator}")
    
    def _create_global_array_concat(self, module: ir.Module, left_val: ir.Value, right_val: ir.Value, result_array_type: ir.ArrayType, operator: Operator) -> ir.Value:
        """Create compile-time array concatenation for global constants"""
        # Get the initializers from both global constants
        left_init = left_val.initializer
        right_init = right_val.initializer
        
        # Extract array elements
        left_elements = list(left_init.constant)
        right_elements = list(right_init.constant) if operator == Operator.ADD else []
        
        # Create new array with concatenated elements
        if operator == Operator.ADD:
            new_elements = left_elements + right_elements
        else:  # SUB
            left_len = len(left_elements)
            right_len = len(right_elements)
            new_len = max(left_len - right_len, 0)
            new_elements = left_elements[:new_len]
        
        # Create global constant
        global_name = f".array_concat_{id(self)}"
        global_array = ir.GlobalVariable(module, result_array_type, name=global_name)
        global_array.linkage = 'internal'
        global_array.global_constant = True
        global_array.initializer = ir.Constant(result_array_type, new_elements)
        
        # CRITICAL: Mark as array pointer to preserve type information
        global_array.type._is_array_pointer = True
        
        return global_array
    
    def _create_runtime_array_concat(self, builder: ir.IRBuilder, module: ir.Module, left_val: ir.Value, right_val: ir.Value, result_array_type: ir.ArrayType, operator: Operator) -> ir.Value:
        """Create runtime array concatenation using memcpy"""
        # Allocate new array for result
        result_ptr = builder.alloca(result_array_type, name="array_concat_result")
        
        # Get array info
        left_elem_type, left_len = get_array_info(left_val)
        right_elem_type, right_len = get_array_info(right_val)
        
        # Calculate element size in bytes
        elem_size_bytes = left_elem_type.width // 8
        
        # Copy left array to result
        if left_len > 0:
            # Get pointer to first element of result array
            zero = ir.Constant(ir.IntType(1), 0)
            result_start = builder.gep(result_ptr, [zero, zero], name="result_start")
            
            # Get pointer to source array start
            left_start = builder.gep(left_val, [zero, zero], name="left_start")
            
            # Copy left array
            left_bytes = left_len * elem_size_bytes
            emit_memcpy(builder, module, result_start, left_start, left_bytes)
        
        # Copy right array to result (for ADD operation)
        if operator == Operator.ADD and right_len > 0:
            # Get pointer to position after left array in result
            left_len_const = ir.Constant(ir.IntType(32), left_len)
            result_right_start = builder.gep(result_ptr, [zero, left_len_const], name="result_right_start")
            
            # Get pointer to source array start
            right_start = builder.gep(right_val, [zero, zero], name="right_start")
            
            # Copy right array
            right_bytes = right_len * elem_size_bytes
            emit_memcpy(builder, module, result_right_start, right_start, right_bytes)
        
        # CRITICAL: Mark as array pointer to preserve type information
        result_ptr.type._is_array_pointer = True
        
        return result_ptr

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
        
        if self.operator == Operator.NOT:
            # Handle NOT in global scope by creating constant
            if builder.scope is None and isinstance(operand_val, ir.Constant):
                if isinstance(operand_val.type, ir.IntType):
                    return ir.Constant(operand_val.type, ~operand_val.constant)
            return builder.not_(operand_val)
        elif self.operator == Operator.SUB:
            # Handle negation - for constants in global scope, create negative constant
            if builder.scope is None and isinstance(operand_val, ir.Constant):
                if isinstance(operand_val.type, ir.IntType):
                    return ir.Constant(operand_val.type, -operand_val.constant)
                elif isinstance(operand_val.type, ir.FloatType):
                    return ir.Constant(operand_val.type, -operand_val.constant)
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
                # Retrieve the variable's pointer from the current scope and store the updated value
                ptr = builder.scope[self.operand.name]
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
                # Retrieve the variable's pointer from the current scope and store the updated value
                ptr = builder.scope[self.operand.name]
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
                zero = ir.Constant(ir.IntType(1), 0)
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
    target_type: TypeSpec
    expression: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate code for cast expressions, including zero-cost struct reinterpretation and void casting"""
        
        # CRITICAL: Use get_llvm_type() which handles type alias resolution
        # This must happen BEFORE any struct checking logic
        target_llvm_type = self.target_type.get_llvm_type(module)
        
        # Handle void casting - frees memory according to Flux specification
        if isinstance(target_llvm_type, ir.VoidType):
            return self._handle_void_cast(builder, module)
        
        source_val = self.expression.codegen(builder, module)
        
        # If source and target are the same type, no cast needed
        if source_val.type == target_llvm_type:
            return source_val
        
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
                # Truncate to smaller integer
                return builder.trunc(source_val, target_llvm_type)
            elif source_val.type.width < target_llvm_type.width:
                # Extend to larger integer (sign extend)
                return builder.sext(source_val, target_llvm_type)
            else:
                # Same width, no cast needed
                return source_val
        
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
                if builder.scope and source_name in builder.scope:
                    original_ptr = builder.scope[source_name]
                    return builder.bitcast(original_ptr, target_llvm_type, name="struct_to_ptr")
            
            # Create persistent storage for the struct that won't go out of scope
            source_ptr = builder.alloca(source_val.type, name="struct_for_cast")
            builder.store(source_val, source_ptr)
            
            # Bitcast the struct pointer to the target pointer type
            return builder.bitcast(source_ptr, target_llvm_type, name="struct_to_ptr")
        
        # Handle pointer casts (pointer -> pointer)
        elif isinstance(source_val.type, ir.PointerType) and isinstance(target_llvm_type, ir.PointerType):
            return builder.bitcast(source_val, target_llvm_type)
        
        else:
            raise ValueError(f"Unsupported cast from {source_val.type} to {target_llvm_type}")
    
    def _handle_void_cast(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Handle void casting - immediately free memory according to Flux specification"""
        if isinstance(self.expression, Identifier):
            var_name = self.expression.name
            
            if builder.scope is not None and var_name in builder.scope:
                var_ptr = builder.scope[var_name]
                self._generate_runtime_free(builder, module, var_ptr, var_name)
                del builder.scope[var_name]
                
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
        is_windows = is_macro_defined(module, 'WINDOWS')
        is_linux = is_macro_defined(module, 'LINUX')
        is_macos = is_macro_defined(module, 'MACOS')
        
        if is_windows:
            asm_code = """
                mov r10, rcx
                mov eax, 0x1E
                syscall
            """
            constraints = "r,~{rax},~{r10},~{r11},~{memory}"
        elif is_linux:
            asm_code = """
                mov rax, 11
                syscall
            """
            constraints = "r,~{rax},~{r11},~{memory}"
        elif is_macos:
            asm_code = """
                mov rax, 0x2000049
                syscall
            """
            constraints = "r,~{rax},~{memory}"
        else:
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
    variable_type: Optional[TypeSpec]  # Type of loop variable
    iterable: Expression  # What to iterate over (e.g., range expression)
    condition: Optional[Expression] = None  # Optional filter condition

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate code for array comprehension [expr for var in iterable]
        Bit-width aware: use the declared loop variable type as the element type."""
        # Resolve element type from the declared loop variable type; default to i32 if unspecified
        if self.variable_type is not None:
            element_type = self.variable_type.get_llvm_type(module)
        else:
            element_type = ir.IntType(32)
        
        # Generate the iterable (e.g., range) with the resolved element type
        if isinstance(self.iterable, RangeExpression):
            # Pass the element_type to the range expression codegen
            _ = self.iterable.codegen(builder, module, element_type)
        else:
            _ = self.iterable.codegen(builder, module)
        
        # Determine the size of the result array (may be used for bounds, though we currently use a fixed-cap buffer)
        if isinstance(self.iterable, RangeExpression):
            # For ranges, calculate size = end - start using element_type consistently
            start_val = self.iterable.start.codegen(builder, module)
            end_val = self.iterable.end.codegen(builder, module)
            
            # Cast range bounds to element_type for size calculation
            from llvmlite import ir as _ir
            if isinstance(start_val.type, _ir.IntType) and isinstance(element_type, _ir.IntType) and start_val.type.width != element_type.width:
                start_val_sized = builder.trunc(start_val, element_type) if start_val.type.width > element_type.width else builder.sext(start_val, element_type)
            else:
                start_val_sized = start_val
                
            if isinstance(end_val.type, _ir.IntType) and isinstance(element_type, _ir.IntType) and end_val.type.width != element_type.width:
                end_val_sized = builder.trunc(end_val, element_type) if end_val.type.width > element_type.width else builder.sext(end_val, element_type)
            else:
                end_val_sized = end_val
                
            size_val = builder.sub(end_val_sized, start_val_sized, name="range_size")
        else:
            raise NotImplementedError("Array comprehension only supports range expressions for now")
        
        # Allocate result array buffer (fixed-capacity for now)
        max_size = 100  # Fixed maximum for now
        array_type = ir.ArrayType(element_type, max_size)
        array_ptr = builder.alloca(array_type, name="comprehension_array")
        
        # Create index variable (use i32 for indexing into arrays)
        index_ptr = builder.alloca(ir.IntType(32), name="comp_index")
        builder.store(ir.Constant(ir.IntType(32), 0), index_ptr)
        
        # Create loop variable with element_type
        var_ptr = builder.alloca(element_type, name=self.variable)
        builder.scope[self.variable] = var_ptr
        
        # Cast range bounds to element_type if both are integers of differing widths
        from llvmlite import ir as _ir
        if isinstance(start_val.type, _ir.IntType) and isinstance(element_type, _ir.IntType) and start_val.type.width != element_type.width:
            start_val = builder.trunc(start_val, element_type) if start_val.type.width > element_type.width else builder.sext(start_val, element_type)
        if isinstance(end_val.type, _ir.IntType) and isinstance(element_type, _ir.IntType) and end_val.type.width != element_type.width:
            end_val = builder.trunc(end_val, element_type) if end_val.type.width > element_type.width else builder.sext(end_val, element_type)
        
        # Create loop: for (var = start; var < end; var++)
        func = builder.block.function
        loop_cond = func.append_basic_block('comp_loop_cond')
        loop_body = func.append_basic_block('comp_loop_body')
        loop_end = func.append_basic_block('comp_loop_end')
        
        # Initialize loop variable with start value
        builder.store(start_val, var_ptr)
        builder.branch(loop_cond)
        
        # Loop condition: var < end (compare using element_type)
        builder.position_at_start(loop_cond)
        current_var = builder.load(var_ptr, name="current_var")
        cond = builder.icmp_signed('<', current_var, end_val, name="loop_cond")
        builder.cbranch(cond, loop_body, loop_end)
        
        # Loop body: evaluate expression and store in array
        builder.position_at_start(loop_body)
        
        # Evaluate the comprehension expression
        expr_val = self.expression.codegen(builder, module)
        # Cast expression value to element_type if needed
        if isinstance(expr_val.type, _ir.IntType) and isinstance(element_type, _ir.IntType) and expr_val.type.width != element_type.width:
            expr_val = builder.trunc(expr_val, element_type) if expr_val.type.width > element_type.width else builder.sext(expr_val, element_type)
        
        # Store in array at current index
        current_index = builder.load(index_ptr, name="current_index")
        array_elem_ptr = builder.gep(array_ptr, [ir.Constant(ir.IntType(32), 0), current_index], inbounds=True)
        builder.store(expr_val, array_elem_ptr)
        
        # Increment index (i32)
        next_index = builder.add(current_index, ir.Constant(ir.IntType(32), 1), name="next_index")
        builder.store(next_index, index_ptr)
        
        # Increment loop variable by 1 of element_type
        next_var = builder.add(current_var, ir.Constant(element_type, 1), name="next_var")
        builder.store(next_var, var_ptr)
        
        # Continue loop
        builder.branch(loop_cond)
        
        # End of loop
        builder.position_at_start(loop_end)
        
        # Return the array pointer
        return array_ptr

@dataclass
class FStringLiteral(Expression):
    """Represents an f-string - parsing only, evaluation happens at codegen"""
    parts: List[Union[str, Expression]]
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # For simple f-strings with only string parts (no expressions), 
        # we can create a compile-time string literal
        if all(isinstance(part, str) for part in self.parts):
            return self._create_string_literal(builder, module)
        else:
            # For f-strings with expressions, we need runtime evaluation
            return self._create_runtime_fstring(builder, module)
    
    def _create_string_literal(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Create a compile-time string literal for f-strings without expressions"""
        # Concatenate all string parts
        full_string = ""
        for part in self.parts:
            clean_part = part
            if clean_part.startswith('f"'):
                clean_part = clean_part[2:]
            if clean_part.endswith('"'):
                clean_part = clean_part[:-1]
            full_string += clean_part
        
        # Create string literal similar to how regular string literals are handled
        string_bytes = full_string.encode('ascii')
        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
        str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
        
        # Create global variable for the string
        gv = ir.GlobalVariable(module, str_val.type, name=f".fstr.{id(self)}")
        gv.linkage = 'internal'
        gv.global_constant = True
        gv.initializer = str_val
        
        # Return the global array directly (not a pointer to first element)
        # This preserves the array type information [N x i8] instead of decaying to i8*
        return gv
    
    def _create_runtime_fstring(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Create runtime-evaluated f-string by building string dynamically"""
        # Estimate maximum buffer size we might need
        max_size = 0
        for part in self.parts:
            if isinstance(part, str):
                clean_part = part
                if clean_part.startswith('f"'):
                    clean_part = clean_part[2:]
                if clean_part.endswith('"'):
                    clean_part = clean_part[:-1]
                max_size += len(clean_part)
            else:
                # Assume expressions can generate up to 32 characters
                max_size += 32
        
        # Allocate buffer with maximum estimated size
        buffer_array_type = ir.ArrayType(ir.IntType(8), max_size)
        buffer_ptr = builder.alloca(buffer_array_type, name="fstring_buffer")
        
        # Track current position in buffer
        pos_ptr = builder.alloca(ir.IntType(32), name="fstring_pos")
        builder.store(ir.Constant(ir.IntType(32), 0), pos_ptr)
        
        # Process each part of the f-string
        for part in self.parts:
            if isinstance(part, str):
                # Copy string literal
                current_pos = builder.load(pos_ptr, name="current_pos")
                new_pos = self._copy_string_to_buffer(builder, buffer_ptr, current_pos, part)
                builder.store(new_pos, pos_ptr)
            else:
                # Evaluate expression and convert to string at runtime
                current_pos = builder.load(pos_ptr, name="current_pos")
                new_pos = self._append_expression_to_buffer(builder, module, buffer_ptr, current_pos, part)
                builder.store(new_pos, pos_ptr)
        
        # Get final size
        final_size = builder.load(pos_ptr, name="final_size")
        
        # Create properly sized result array
        # Since LLVM needs compile-time array sizes, we'll allocate based on final_size at runtime
        result_ptr = builder.alloca(ir.IntType(8), final_size, name="fstring_result")
        
        # Copy the constructed string to the final buffer
        self._runtime_memcpy(builder, result_ptr, 
                           builder.gep(buffer_ptr, [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), 0)]), 
                           final_size)
        
        # Return the final buffer - this preserves the runtime-computed size
        return result_ptr
    
    def _copy_string(self, builder: ir.IRBuilder, buffer_ptr: ir.Value, 
                   start_pos: int, string: str) -> int:
        """Copy string literal to buffer"""
        # Clean string by removing f" prefix and " suffix if present
        clean_string = string
        if clean_string.startswith('f"'):
            clean_string = clean_string[2:]
        if clean_string.endswith('"'):
            clean_string = clean_string[:-1]
        
        for i, char in enumerate(clean_string):
            char_ptr = builder.gep(
                buffer_ptr,
                [ir.Constant(ir.IntType(32), 0),
                 ir.Constant(ir.IntType(32), start_pos + i)],
                inbounds=True
            )
            builder.store(ir.Constant(ir.IntType(8), ord(char)), char_ptr)
        return start_pos + len(clean_string)
    
    def _append_expression(self, builder: ir.IRBuilder, module: ir.Module,
                         buffer_ptr: ir.Value, start_pos: int, expr: Expression) -> int:
        """Evaluate expression and convert to string - happens at runtime"""
        # This is where the actual evaluation occurs, during codegen
        value = expr.codegen(builder, module)
        
        # Convert value to string using runtime functions
        # (This would call itoa, ftoa, etc. based on type)
        # For now, implement proper runtime string conversion based on type
        if isinstance(value.type, ir.IntType):
            # Call runtime itoa function to convert integer to string
            # This is where we'd implement or call actual runtime conversion
            # For now, store the actual converted integer as a placeholder
            return self._convert_integer_to_string(builder, module, buffer_ptr, start_pos, value)
        elif isinstance(value.type, ir.FloatType):
            # Call runtime ftoa function to convert float to string
            return self._convert_float_to_string(builder, module, buffer_ptr, start_pos, value)
        else:
            # For other types, just store placeholder for now
            temp_str = "[value]"
            for i, char in enumerate(temp_str):
                char_ptr = builder.gep(
                    buffer_ptr,
                    [ir.Constant(ir.IntType(32), 0),
                     ir.Constant(ir.IntType(32), start_pos + i)],
                    inbounds=True
                )
                builder.store(ir.Constant(ir.IntType(8), ord(char)), char_ptr)
            return start_pos + len(temp_str)
    
    def _convert_integer_to_string(self, builder: ir.IRBuilder, module: ir.Module,
                                 buffer_ptr: ir.Value, start_pos: int, value: ir.Value) -> int:
        """Convert integer to string at runtime using LLVM IR"""
        # This implements a simple integer-to-string conversion in LLVM IR
        # We'll use a divide-by-10 approach to extract digits
        
        func = builder.block.function
        
        # Create blocks for the conversion algorithm
        entry_block = builder.block
        negative_block = func.append_basic_block('negative_block')
        positive_block = func.append_basic_block('positive_block')
        zero_check_block = func.append_basic_block('zero_check')
        zero_block = func.append_basic_block('zero_block')
        conversion_cond = func.append_basic_block('conversion_cond')
        conversion_loop = func.append_basic_block('conversion_loop')
        reverse_cond = func.append_basic_block('reverse_cond')
        reverse_loop = func.append_basic_block('reverse_loop')
        done_block = func.append_basic_block('conversion_done')
        
        # Allocate temporary buffer for digits (max 12 digits for 32-bit int + sign)
        temp_buffer_type = ir.ArrayType(ir.IntType(8), 12)
        temp_buffer = builder.alloca(temp_buffer_type, name="temp_digits")
        
        # Position counter for writing into the final buffer
        pos_counter = builder.alloca(ir.IntType(32), name="pos_counter")
        builder.store(ir.Constant(ir.IntType(32), start_pos), pos_counter)
        
        # Digit counter and working value
        digit_count = builder.alloca(ir.IntType(32), name="digit_count")
        builder.store(ir.Constant(ir.IntType(32), 0), digit_count)
        working_val = builder.alloca(value.type, name="working_val")
        
        # Check if the number is negative
        zero = ir.Constant(value.type, 0)
        is_negative = builder.icmp_signed('<', value, zero, name="is_negative")
        builder.cbranch(is_negative, negative_block, positive_block)
        
        # Handle negative numbers
        builder.position_at_start(negative_block)
        # Store minus sign
        current_pos = builder.load(pos_counter, name="current_pos")
        minus_ptr = builder.gep(
            buffer_ptr,
            [ir.Constant(ir.IntType(32), 0), current_pos],
            inbounds=True
        )
        builder.store(ir.Constant(ir.IntType(8), ord('-')), minus_ptr)
        # Increment position
        new_pos = builder.add(current_pos, ir.Constant(ir.IntType(32), 1), name="new_pos")
        builder.store(new_pos, pos_counter)
        # Store absolute value
        abs_val = builder.sub(zero, value, name="abs_val")
        builder.store(abs_val, working_val)
        builder.branch(zero_check_block)
        
        # Handle positive numbers
        builder.position_at_start(positive_block)
        builder.store(value, working_val)
        builder.branch(zero_check_block)
        
        # Handle special case of zero
        builder.position_at_start(zero_check_block)
        current_val = builder.load(working_val, name="current_val")
        is_zero = builder.icmp_signed('==', current_val, zero, name="is_zero")
        builder.cbranch(is_zero, zero_block, conversion_cond)
        
        # Zero case
        builder.position_at_start(zero_block)
        current_pos = builder.load(pos_counter, name="current_pos")
        zero_ptr = builder.gep(
            buffer_ptr,
            [ir.Constant(ir.IntType(32), 0), current_pos],
            inbounds=True
        )
        builder.store(ir.Constant(ir.IntType(8), ord('0')), zero_ptr)
        # Increment position and jump to done
        new_pos = builder.add(current_pos, ir.Constant(ir.IntType(32), 1), name="new_pos")
        builder.store(new_pos, pos_counter)
        builder.branch(done_block)
        
        # Conversion condition: while working_val > 0
        builder.position_at_start(conversion_cond)
        current_val = builder.load(working_val, name="current_val")
        is_nonzero = builder.icmp_signed('>', current_val, zero, name="is_nonzero")
        builder.cbranch(is_nonzero, conversion_loop, reverse_cond)
        
        # Conversion loop: extract digit
        builder.position_at_start(conversion_loop)
        current_val = builder.load(working_val, name="current_val")
        current_count = builder.load(digit_count, name="current_count")
        
        # Get remainder (digit) and quotient
        ten = ir.Constant(value.type, 10)
        digit_val = builder.srem(current_val, ten, name="digit_val")
        quotient = builder.sdiv(current_val, ten, name="quotient")
        
        # Convert digit to ASCII and store in temp buffer
        digit_char = builder.add(digit_val, ir.Constant(value.type, ord('0')), name="digit_char")
        digit_char_i8 = builder.trunc(digit_char, ir.IntType(8), name="digit_char_i8")
        
        # Store in temporary buffer
        temp_ptr = builder.gep(
            temp_buffer,
            [ir.Constant(ir.IntType(32), 0), current_count],
            inbounds=True
        )
        builder.store(digit_char_i8, temp_ptr)
        
        # Update counters
        builder.store(quotient, working_val)
        new_count = builder.add(current_count, ir.Constant(ir.IntType(32), 1), name="new_count")
        builder.store(new_count, digit_count)
        
        builder.branch(conversion_cond)
        
        # Reverse the digits into the final buffer
        builder.position_at_start(reverse_cond)
        final_count = builder.load(digit_count, name="final_count")
        reverse_index = builder.alloca(ir.IntType(32), name="reverse_index")
        builder.store(final_count, reverse_index)
        
        # Check if we have digits to reverse
        has_digits = builder.icmp_signed('>', final_count, ir.Constant(ir.IntType(32), 0), name="has_digits")
        builder.cbranch(has_digits, reverse_loop, done_block)
        
        # Reverse loop: copy digits from temp buffer to final buffer in reverse order
        builder.position_at_start(reverse_loop)
        current_reverse_index = builder.load(reverse_index, name="current_reverse_index")
        current_pos = builder.load(pos_counter, name="current_pos")
        
        # Decrement reverse index (we're going backwards)
        prev_reverse_index = builder.sub(current_reverse_index, ir.Constant(ir.IntType(32), 1), name="prev_reverse_index")
        builder.store(prev_reverse_index, reverse_index)
        
        # Load digit from temp buffer
        temp_digit_ptr = builder.gep(
            temp_buffer,
            [ir.Constant(ir.IntType(32), 0), prev_reverse_index],
            inbounds=True
        )
        temp_digit = builder.load(temp_digit_ptr, name="temp_digit")
        
        # Store in final buffer
        final_ptr = builder.gep(
            buffer_ptr,
            [ir.Constant(ir.IntType(32), 0), current_pos],
            inbounds=True
        )
        builder.store(temp_digit, final_ptr)
        
        # Increment final position
        new_pos = builder.add(current_pos, ir.Constant(ir.IntType(32), 1), name="new_pos")
        builder.store(new_pos, pos_counter)
        
        # Check if more digits to reverse
        is_more = builder.icmp_signed('>', prev_reverse_index, ir.Constant(ir.IntType(32), 0), name="is_more")
        builder.cbranch(is_more, reverse_loop, done_block)
        
        # Done
        builder.position_at_start(done_block)
        final_pos = builder.load(pos_counter, name="final_pos")
        
        # Return the final position (as an integer, not an LLVM Value)
        # Since we can't return a dynamic value from this function, we need to 
        # return a conservative estimate and fix this differently
        return start_pos + 11  # Maximum possible digits for a 32-bit integer
    
    def _convert_float_to_string(self, builder: ir.IRBuilder, module: ir.Module,
                               buffer_ptr: ir.Value, start_pos: int, value: ir.Value) -> int:
        """Convert float to string at runtime - proper implementation needed"""
        # For now, just store "1.23" as placeholder
        # In a real implementation, this would call ftoa or similar runtime function
        temp_str = "1.23"
        for i, char in enumerate(temp_str):
            char_ptr = builder.gep(
                buffer_ptr,
                [ir.Constant(ir.IntType(32), 0),
                 ir.Constant(ir.IntType(32), start_pos + i)],
                inbounds=True
            )
            builder.store(ir.Constant(ir.IntType(8), ord(char)), char_ptr)
        return start_pos + len(temp_str)

# Utility functions for macro management
def define_macro(module: ir.Module, macro_name: str) -> None:
    """Define a macro in the module's macro registry"""
    if not hasattr(module, '_defined_macros'):
        module._defined_macros = set()
    module._defined_macros.add(macro_name)

def is_macro_defined(module: ir.Module, macro_name: str) -> bool:
    """Check if a macro is defined in the module's macro registry"""
    if not hasattr(module, '_defined_macros'):
        return False
    return macro_name in module._defined_macros

def get_defined_macros(module: ir.Module) -> set:
    """Get the set of currently defined macros"""
    if not hasattr(module, '_defined_macros'):
        return set()
    return module._defined_macros.copy()

@dataclass
class DefMacro(Expression):
    """AST node for def(MACRO_NAME) expressions - checks if a macro is defined"""
    macro_name: str
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate code that returns true if macro is defined, false otherwise"""
        # Check if the macro is defined in the module's macro registry
        if not hasattr(module, '_defined_macros'):
            module._defined_macros = set()
        
        is_defined = self.macro_name in module._defined_macros
        # Return a boolean constant (i1 type in LLVM)
        return ir.Constant(ir.IntType(1), is_defined)


@dataclass
class FunctionCall(Expression):
    name: str
    arguments: List[Expression] = field(default_factory=list)
    
    # Class-level counter for globally unique string literals
    _string_counter = 0

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Look up the function in the module
        func = module.globals.get(self.name, None)
        
        # If not found directly, check for namespace-qualified names using 'using' statements
        if func is None or not isinstance(func, ir.Function):
            if hasattr(module, '_using_namespaces'):
                for namespace in module._using_namespaces:
                    # Convert namespace path to mangled name format
                    mangled_prefix = namespace.replace('::', '__') + '__'
                    mangled_name = mangled_prefix + self.name
                    
                    # Check for mangled function name
                    if mangled_name in module.globals:
                        candidate_func = module.globals[mangled_name]
                        if isinstance(candidate_func, ir.Function):
                            func = candidate_func
                            break
        
        if func is None or not isinstance(func, ir.Function):
            raise NameError(f"Unknown function: {self.name}")
        
        # Check if this is a method call (has dot in name)
        is_method_call = '.' in self.name
        parameter_offset = 1 if is_method_call else 0  # Account for implicit 'this' parameter
        
        # Generate code for arguments
        arg_vals = []
        for i, arg in enumerate(self.arguments):
            param_index = i + parameter_offset
            
            if (isinstance(arg, Literal) and arg.type == DataType.CHAR and 
                param_index < len(func.args) and isinstance(func.args[param_index].type, ir.PointerType) and 
                isinstance(func.args[param_index].type.pointee, ir.IntType) and func.args[param_index].type.pointee.width == 8):
                # This is a string literal being passed to a function expecting i8*
                # Create a global string constant and return pointer to it
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
                zero = ir.Constant(ir.IntType(1), 0)
                str_ptr = builder.gep(gv, [zero, zero], name=f"arg{i}_str_ptr")
                arg_val = str_ptr
            else:
                arg_val = arg.codegen(builder, module)
            
            # Type checking and conversion logic
            if param_index < len(func.args):
                expected_type = func.args[param_index].type
                
                if arg_val.type != expected_type:
                    # If we have [N x T]* and expect T*, convert via GEP
                    if (isinstance(arg_val.type, ir.PointerType) and 
                        isinstance(arg_val.type.pointee, ir.ArrayType) and
                        isinstance(expected_type, ir.PointerType) and
                        arg_val.type.pointee.element == expected_type.pointee):
                        # Array to pointer decay: [4 x i8]* -> i8*
                        zero = ir.Constant(ir.IntType(1), 0)
                        arg_val = builder.gep(arg_val, [zero, zero], name=f"arg{i}_decay")
                    
                    # Check if this is an object type that has a __expr method for automatic conversion
                    elif isinstance(arg_val.type, ir.PointerType):
                        # Get the struct name - handle both identified and literal struct types
                        struct_name = None
                        
                        # Try to get name from identified struct types
                        if hasattr(arg_val.type.pointee, '_name'):
                            struct_name = arg_val.type.pointee._name.strip('"')
                        
                        # Try to get name from module's struct types
                        if struct_name is None and hasattr(module, '_struct_types'):
                            for name, struct_type in module._struct_types.items():
                                # More robust comparison that handles both identified and literal struct types
                                if (struct_type == arg_val.type.pointee or 
                                    (hasattr(struct_type, '_name') and hasattr(arg_val.type.pointee, '_name') and
                                     struct_type._name == arg_val.type.pointee._name) or
                                    (str(struct_type) == str(arg_val.type.pointee))):
                                    struct_name = name
                                    break
                        
                        # If we found a struct name, look for __expr method
                        if struct_name:
                            expr_method_name = f"{struct_name}.__expr"
                            
                            if expr_method_name in module.globals:
                                expr_func = module.globals[expr_method_name]
                                if isinstance(expr_func, ir.Function):
                                    # Call the __expr method to get the underlying representation
                                    converted_val = builder.call(expr_func, [arg_val])
                                    # Check if the converted type matches what's expected
                                    if converted_val.type == expected_type:
                                        arg_val = converted_val
            
            arg_vals.append(arg_val)
        
        return builder.call(func, arg_vals)

@dataclass
class MemberAccess(Expression):
    object: Expression
    member: str

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Check if this is a struct type
        if hasattr(module, '_struct_types'):
            obj = self.object.codegen(builder, module)
            for struct_name, struct_type in module._struct_types.items():
                if obj.type == struct_type or (isinstance(obj.type, ir.PointerType) and obj.type.pointee == struct_type):
                    # This is struct field access
                    field_access = StructFieldAccess(self.object, self.member)
                    return field_access.codegen(builder, module)
        # Handle static struct/union member access (A.x where A is a struct/union type)
        if isinstance(self.object, Identifier):
            type_name = self.object.name
            if hasattr(module, '_struct_types') and type_name in module._struct_types:
                # Look for the global variable representing this member
                global_name = f"{type_name}.{self.member}"
                for global_var in module.global_values:
                    if global_var.name == global_name:
                        return builder.load(global_var)
                
                raise NameError(f"Static member '{self.member}' not found in struct '{type_name}'")
            # Check for union types
            elif hasattr(module, '_union_types') and type_name in module._union_types:
                # Look for the global variable representing this member
                global_name = f"{type_name}.{self.member}"
                for global_var in module.global_values:
                    if global_var.name == global_name:
                        return builder.load(global_var)
                
                raise NameError(f"Static member '{self.member}' not found in union '{type_name}'")
        
        # Handle regular member access (obj.x where obj is an instance)
        obj_val = self.object.codegen(builder, module)
        
        # Special case: if this is accessing 'this' in a method, handle the double pointer issue
        if (isinstance(self.object, Identifier) and self.object.name == "this" and 
            isinstance(obj_val.type, ir.PointerType) and 
            isinstance(obj_val.type.pointee, ir.PointerType) and
            isinstance(obj_val.type.pointee.pointee, ir.LiteralStructType)):
            # Load the actual 'this' pointer from the alloca
            obj_val = builder.load(obj_val, name="this_ptr")
        
        if isinstance(obj_val.type, ir.PointerType):
            # Handle pointer to struct (both literal and identified struct types)
            is_struct_pointer = (isinstance(obj_val.type.pointee, ir.LiteralStructType) or
                                hasattr(obj_val.type.pointee, '_name') or  # Identified struct type
                                hasattr(obj_val.type.pointee, 'elements'))  # Other struct-like types
            
            if is_struct_pointer:
                struct_type = obj_val.type.pointee
                
                # Check if this is actually a union (unions are implemented as structs)
                if hasattr(module, '_union_types'):
                    for union_name, union_type in module._union_types.items():
                        if union_type == struct_type:
                            # This is a union - handle union member access
                            return self._handle_union_member_access(builder, module, obj_val, union_name)
                
                # Regular struct member access
                if not hasattr(struct_type, 'names'):
                    raise ValueError("Struct type missing member names")
                
                member_index = 0
                try:
                    member_index = struct_type.names.index(self.member)
                except ValueError:
                    raise ValueError(f"Member '{self.member}' not found in struct")
                
                # FIXED: Pass indices as a single list argument
                member_ptr = builder.gep(
                    obj_val,
                    [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), member_index)],
                    inbounds=True
                )
                return builder.load(member_ptr)
        
        raise ValueError(f"Member access on unsupported type: {obj_val.type}")
    
    def _handle_union_member_access(self, builder: ir.IRBuilder, module: ir.Module, union_ptr: ir.Value, union_name: str) -> ir.Value:
        """Handle union member access by casting the union to the appropriate member type"""
        # Get union member information
        if not hasattr(module, '_union_member_info') or union_name not in module._union_member_info:
            raise ValueError(f"Union member info not found for '{union_name}'")
        
        union_info = module._union_member_info[union_name]
        member_names = union_info['member_names']
        member_types = union_info['member_types']
        
        # Find the requested member
        if self.member not in member_names:
            raise ValueError(f"Member '{self.member}' not found in union '{union_name}'")
        
        member_index = member_names.index(self.member)
        member_type = member_types[member_index]
        
        # Cast the union pointer to the appropriate member type pointer and load the value
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
            if builder.scope and var_name in builder.scope:
                obj_ptr = builder.scope[var_name]
            else:
                raise NameError(f"Unknown variable: {var_name}")
        else:
            # For other expressions, generate code normally
            obj_ptr = self.object.codegen(builder, module)
        
        # Determine the object's type to construct the method name
        if isinstance(obj_ptr.type, ir.PointerType):
            pointee_type = obj_ptr.type.pointee
            # Check if it's a named struct type
            if hasattr(module, '_struct_types'):
                for type_name, struct_type in module._struct_types.items():
                    if struct_type == pointee_type:
                        obj_type_name = type_name
                        break
                else:
                    raise ValueError(f"Cannot determine object type for method call: {pointee_type}")
            else:
                raise ValueError(f"Method call requires pointer to object, got: {obj_ptr.type}")
        else:
            raise ValueError(f"Method call requires pointer to object, got: {obj_ptr.type}")
        
        # Construct the method name: ObjectType.methodName
        method_func_name = f"{obj_type_name}.{self.method_name}"
        
        # Look up the method function
        func = module.globals.get(method_func_name)
        if func is None:
            raise NameError(f"Unknown method: {method_func_name}")
        
        # Generate arguments with 'this' pointer as first argument
        args = [obj_ptr]  # 'this' pointer is the object pointer
        for arg_expr in self.arguments:
            args.append(arg_expr.codegen(builder, module))
        
        # Call the method
        return builder.call(func, args)

@dataclass
class ArrayAccess(Expression):
    array: Expression
    index: Expression
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Get the array (should be a pointer to array or global)
        array_val = self.array.codegen(builder, module)
        
        # Check if this is a range expression (array slicing)
        if isinstance(self.index, RangeExpression):
            return self._handle_array_slice(builder, module, array_val)
        
        # Regular single element access - generate the index expression
        index_val = self.index.codegen(builder, module)
        
        # CRITICAL FIX: Ensure index is i32 for GEP
        # GEP expects i32 indices, but expressions might return i64
        if index_val.type != ir.IntType(32):
            if isinstance(index_val.type, ir.IntType):
                # Truncate or extend to i32 as needed
                if index_val.type.width > 32:
                    index_val = builder.trunc(index_val, ir.IntType(32), name="idx_trunc")
                else:
                    index_val = builder.sext(index_val, ir.IntType(32), name="idx_ext")
        
        # Handle global arrays (like const arrays)
        if isinstance(array_val, ir.GlobalVariable):
            # Create GEP to access array element
            # Need two indices: [0] to dereference pointer, [index] to access element
            zero = ir.Constant(ir.IntType(32), 0)  # CHANGED from IntType(1) to IntType(32)
            gep = builder.gep(array_val, [zero, index_val], inbounds=True, name="array_gep")
            return builder.load(gep, name="array_load")
        
        # Handle local arrays
        elif isinstance(array_val.type, ir.PointerType) and isinstance(array_val.type.pointee, ir.ArrayType):
            # Local array allocated with alloca
            # Need two indices: [0] to dereference the alloca pointer, [index] to access element
            zero = ir.Constant(ir.IntType(32), 0)  # CHANGED from IntType(1) to IntType(32)
            gep = builder.gep(array_val, [zero, index_val], inbounds=True, name="array_gep")
            return builder.load(gep, name="array_load")
        
        # Handle pointer types (like char*)
        elif isinstance(array_val.type, ir.PointerType):
            # For pointers, we only need one index (direct pointer arithmetic)
            gep = builder.gep(array_val, [index_val], inbounds=True, name="ptr_gep")
            return builder.load(gep, name="ptr_load")
        
        else:
            raise ValueError(f"Cannot access array element for type: {array_val.type}")
    
    def _handle_array_slice(self, builder: ir.IRBuilder, module: ir.Module, array_val: ir.Value) -> ir.Value:
        """Handle array slicing with range expressions like s[0..3] or s[3..0] (inclusive on both ends)"""
        start_val = self.index.start.codegen(builder, module)
        end_val = self.index.end.codegen(builder, module)
        
        # Ensure indices are i32
        if start_val.type != ir.IntType(32):
            if isinstance(start_val.type, ir.IntType):
                if start_val.type.width > 32:
                    start_val = builder.trunc(start_val, ir.IntType(32), name="start_trunc")
                else:
                    start_val = builder.sext(start_val, ir.IntType(32), name="start_ext")
        
        if end_val.type != ir.IntType(32):
            if isinstance(end_val.type, ir.IntType):
                if end_val.type.width > 32:
                    end_val = builder.trunc(end_val, ir.IntType(32), name="end_trunc")
                else:
                    end_val = builder.sext(end_val, ir.IntType(32), name="end_ext")
        
        # Determine if this is a forward or reverse range
        # For compile-time constants, we can check directly
        is_reverse = False
        if (isinstance(start_val, ir.Constant) and isinstance(end_val, ir.Constant)):
            is_reverse = start_val.constant > end_val.constant
        else:
            # For runtime values, generate a comparison
            reverse_cmp = builder.icmp_signed('>', start_val, end_val, name="is_reverse")
            # For now, we'll handle only compile-time constants to keep it simple
            # Runtime reverse detection would require conditional logic
            raise ValueError("Runtime reverse range detection not yet implemented")
        
        # Calculate slice length based on direction
        if is_reverse:
            # Reverse range: length = (start - end) + 1
            slice_len_exclusive = builder.sub(start_val, end_val, name="slice_len_exclusive")
            slice_len = builder.add(slice_len_exclusive, ir.Constant(ir.IntType(32), 1), name="slice_len")
        else:
            # Forward range: length = (end - start) + 1
            slice_len_exclusive = builder.sub(end_val, start_val, name="slice_len_exclusive")
            slice_len = builder.add(slice_len_exclusive, ir.Constant(ir.IntType(32), 1), name="slice_len")
        
        # Determine the element type
        if isinstance(array_val, ir.GlobalVariable):
            if isinstance(array_val.type.pointee, ir.ArrayType):
                element_type = array_val.type.pointee.element
            else:
                raise ValueError("Cannot slice non-array global variable")
        elif isinstance(array_val.type, ir.PointerType):
            if isinstance(array_val.type.pointee, ir.ArrayType):
                element_type = array_val.type.pointee.element
            else:
                # For pointer types like i8*, the element type is the pointee
                element_type = array_val.type.pointee
        else:
            raise ValueError(f"Cannot slice type: {array_val.type}")
        
        # For now, we'll create a fixed-size array to hold the slice
        # In a full implementation, this could be dynamically sized
        # We'll use a maximum reasonable slice size
        max_slice_size = 256  # Should be enough for most string operations
        slice_array_type = ir.ArrayType(element_type, max_slice_size)
        slice_ptr = builder.alloca(slice_array_type, name="slice_array")
        
        # Get pointer to the start of the source array/string
        zero = ir.Constant(ir.IntType(1), 0)
        if isinstance(array_val, ir.GlobalVariable):
            # Global array access
            source_start_ptr = builder.gep(array_val, [zero, start_val], inbounds=True, name="source_start")
        elif isinstance(array_val.type, ir.PointerType) and isinstance(array_val.type.pointee, ir.ArrayType):
            # Local array access
            source_start_ptr = builder.gep(array_val, [zero, start_val], inbounds=True, name="source_start")
        elif isinstance(array_val.type, ir.PointerType):
            # Pointer arithmetic for strings (char*, etc.)
            source_start_ptr = builder.gep(array_val, [start_val], inbounds=True, name="source_start")
        else:
            raise ValueError(f"Unsupported array type for slicing: {array_val.type}")
        
        # Get pointer to the start of the slice array
        slice_start_ptr = builder.gep(slice_ptr, [zero, zero], inbounds=True, name="slice_start")
        
        # Copy the slice using a loop that handles both forward and reverse directions
        func = builder.block.function
        loop_cond = func.append_basic_block('slice_loop_cond')
        loop_body = func.append_basic_block('slice_loop_body')
        loop_end = func.append_basic_block('slice_loop_end')
        
        # Create loop counter
        counter_ptr = builder.alloca(ir.IntType(32), name="slice_counter")
        builder.store(ir.Constant(ir.IntType(32), 0), counter_ptr)
        builder.branch(loop_cond)
        
        # Loop condition: counter < slice_len
        builder.position_at_start(loop_cond)
        counter = builder.load(counter_ptr, name="counter")
        cond = builder.icmp_signed('<', counter, slice_len, name="slice_cond")
        builder.cbranch(cond, loop_body, loop_end)
        
        # Loop body: copy one element with direction-aware indexing
        builder.position_at_start(loop_body)
        
        if is_reverse:
            # For reverse slices: source index goes backwards from start to end
            source_offset = builder.sub(start_val, counter, name="reverse_source_offset")
        else:
            # For forward slices: source index goes forwards from start
            source_offset = builder.add(start_val, counter, name="forward_source_offset")
        
        # Get source element at calculated offset
        if isinstance(array_val, ir.GlobalVariable):
            # Global array access
            source_elem_ptr = builder.gep(array_val, [zero, source_offset], inbounds=True, name="source_elem")
        elif isinstance(array_val.type, ir.PointerType) and isinstance(array_val.type.pointee, ir.ArrayType):
            # Local array access
            source_elem_ptr = builder.gep(array_val, [zero, source_offset], inbounds=True, name="source_elem")
        elif isinstance(array_val.type, ir.PointerType):
            # Pointer arithmetic for strings (char*, etc.)
            source_elem_ptr = builder.gep(array_val, [source_offset], inbounds=True, name="source_elem")
        
        source_elem = builder.load(source_elem_ptr, name="source_val")
        
        # Store in slice array at sequential destination index (always forward)
        dest_elem_ptr = builder.gep(slice_start_ptr, [counter], inbounds=True, name="dest_elem")
        builder.store(source_elem, dest_elem_ptr)
        
        # Increment counter
        next_counter = builder.add(counter, ir.Constant(ir.IntType(32), 1), name="next_counter")
        builder.store(next_counter, counter_ptr)
        builder.branch(loop_cond)
        
        # End of loop - add null terminator for strings
        builder.position_at_start(loop_end)
        if element_type == ir.IntType(8):  # For string slices, add null terminator
            final_counter = builder.load(counter_ptr, name="final_counter")
            null_ptr = builder.gep(slice_start_ptr, [final_counter], inbounds=True, name="null_pos")
            null_char = ir.Constant(ir.IntType(8), 0)
            builder.store(null_char, null_ptr)
        
        return slice_ptr

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
        # Special case: Handle Identifier directly to avoid the codegen call that might fail
        if isinstance(self.expression, Identifier):
            var_name = self.expression.name
            
            # Check if it's a local variable
            if builder.scope is not None and var_name in builder.scope:
                ptr = builder.scope[var_name]
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
            
            # Check for namespace-qualified names using 'using' statements
            if hasattr(module, '_using_namespaces'):
                for namespace in module._using_namespaces:
                    # Convert namespace path to mangled name format
                    mangled_prefix = namespace.replace('::', '__') + '__'
                    mangled_name = mangled_prefix + var_name
                    
                    # Check in global variables with mangled name
                    if mangled_name in module.globals:
                        gvar = module.globals[mangled_name]
                        if isinstance(gvar.type, ir.PointerType):
                            # For arrays (including string arrays like noopstr), return the global directly
                            # For other pointer types, check if it's a pointer to pointer
                            if (isinstance(gvar.type.pointee, ir.PointerType) and not isinstance(gvar.type.pointee, ir.ArrayType)):
                                # This is a pointer to a pointer (non-array global variable storage of pointer type)
                                # Return the loaded pointer value, not the address of the storage
                                result = builder.load(gvar, name=f"{var_name}_ptr")
                                return result
                        return gvar
            
            # If we get here, the variable hasn't been declared yet
            raise NameError(f"Unknown variable: {var_name}")
        
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
                zero = ir.Constant(ir.IntType(1), 0)
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
    target: Union[TypeSpec, Expression]

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Returns alignment in bytes for:
        - Explicitly specified alignments (data{bits:align})
        - Data types: alignment equals width in bytes (data{bits})
        - Other types: Natural alignment from target platform
        """
        # Get alignment for TypeSpec
        if isinstance(self.target, TypeSpec):
            # Use explicitly specified alignment if present
            if self.target.alignment is not None:
                return ir.Constant(ir.IntType(32), self.target.alignment)
            
            # Special case: Data types default to width alignment
            if self.target.base_type == DataType.DATA and self.target.bit_width is not None:
                return ir.Constant(ir.IntType(32), (self.target.bit_width + 7) // 8)
            
            # Default case: Use platform alignment
            llvm_type = self.target.get_llvm_type(module)
            return ir.Constant(ir.IntType(32), module.data_layout.preferred_alignment(llvm_type))
        
        # Get alignment for expressions
        val = self.target.codegen(builder, module)
        val_type = val.type.pointee if isinstance(val.type, ir.PointerType) else val.type
        
        # Handle data types in expressions
        if (isinstance(self.target, VariableDeclaration) and 
            self.target.type_spec.base_type == DataType.DATA and
            self.target.type_spec.bit_width is not None):
            return ir.Constant(ir.IntType(32), (self.target.type_spec.bit_width + 7) // 8)
        
        # Default case for expressions
        return ir.Constant(ir.IntType(32), module.data_layout.preferred_alignment(val_type))

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
            ir.PointerType(ir.IntType(8))  # name pointer
        ]), [
            ir.Constant(ir.IntType(32), size),
            ir.Constant(ir.IntType(32), align),
            builder.gep(name_constant, [ir.Constant(ir.IntType(32), 0)],
                      [ir.Constant(ir.IntType(32), 0)])
            ])

@dataclass
class SizeOf(Expression):
    target: Union[TypeSpec, Expression]

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate LLVM IR that returns size in BITS"""
        #print(f"DEBUG SizeOf: target type = {type(self.target).__name__}, target = {self.target}")
        # Handle TypeSpec case (like sizeof(data{8}[]))
        if isinstance(self.target, TypeSpec):
            #print(f"DEBUG SizeOf: Taking TypeSpec path")
            llvm_type = self.target.get_llvm_type_with_array(module)
            
            # Calculate size in BITS
            if isinstance(llvm_type, ir.IntType):
                return ir.Constant(ir.IntType(llvm_type.width), llvm_type.width)  # Already in bits
            elif isinstance(llvm_type, ir.ArrayType):
                element_bits = llvm_type.element.width
                return ir.Constant(ir.IntType(llvm_type.width), element_bits * llvm_type.count)
            elif isinstance(llvm_type, ir.PointerType):
                return ir.Constant(ir.IntType(llvm_type.width), llvm_type.width)  # 64-bit pointers = 64 bits
            else:
                raise ValueError(f"Unknown type in sizeof: {llvm_type}")
        
        # Handle Identifier case - look up the declared type instead of loading the value
        if isinstance(self.target, Identifier):
            # Look up the variable declaration in the current scope
            if builder.scope is not None and self.target.name in builder.scope:
                ptr = builder.scope[self.target.name]
                if isinstance(ptr.type, ir.PointerType):
                    llvm_type = ptr.type.pointee  # Get the type being pointed to
                    # Calculate size in BITS using the same logic as TypeSpec
                    if isinstance(llvm_type, ir.IntType):
                        return ir.Constant(ir.IntType(llvm_type.width), llvm_type.width)
                    elif isinstance(llvm_type, ir.ArrayType):
                        element_bits = llvm_type.element.width
                        return ir.Constant(ir.IntType(llvm_type.element.width), element_bits * llvm_type.count)
                    elif isinstance(llvm_type, ir.PointerType):
                        # For parameter that is a pointer (like i8* from unsized array parameter), 
                        # we can't determine the size at compile time, so return 0
                        # In a real implementation, this might require runtime size tracking
                        return ir.Constant(ir.IntType(32), 0)
                    elif isinstance(llvm_type, ir.LiteralStructType):
                        # Calculate struct size in bits by summing all member sizes
                        total_bits = 0
                        for element in llvm_type.elements:
                            if isinstance(element, ir.IntType):
                                total_bits += element.width
                            elif isinstance(element, ir.FloatType):
                                total_bits += 32  # Float is 32 bits
                            else:
                                # For other types, use data layout to get size in bytes, then convert to bits
                                bytes_size = module.data_layout.get_type_size(element)
                                total_bits += bytes_size * 8
                        return ir.Constant(ir.IntType(32), total_bits)
                    elif hasattr(llvm_type, 'elements'):  # Identified struct type
                        # Calculate struct size in bits by summing all member sizes
                        total_bits = 0
                        for element in llvm_type.elements:
                            if isinstance(element, ir.IntType):
                                total_bits += element.width
                            elif isinstance(element, ir.FloatType):
                                total_bits += 32  # Float is 32 bits
                            elif isinstance(element, ir.PointerType):
                                total_bits += 64  # Assume 64-bit pointers
                            else:
                                # For other types, use data layout to get size in bytes, then convert to bits
                                bytes_size = module.data_layout.get_type_size(element)
                                total_bits += bytes_size * 8
                        return ir.Constant(ir.IntType(32), total_bits)
                    else:
                        raise ValueError(f"Unknown type in sizeof for identifier {self.target.name}: {llvm_type}")
                
            # Check for global variables
            if self.target.name in module.globals:
                gvar = module.globals[self.target.name]
                if isinstance(gvar.type, ir.PointerType):
                    llvm_type = gvar.type.pointee  # Get the type being pointed to
                    # Calculate size in BITS using the same logic as TypeSpec
                    if isinstance(llvm_type, ir.IntType):
                        return ir.Constant(ir.IntType(32), llvm_type.width)
                    elif isinstance(llvm_type, ir.ArrayType):
                        element_bits = llvm_type.element.width
                        return ir.Constant(ir.IntType(32), element_bits * llvm_type.count)
                    elif isinstance(llvm_type, ir.PointerType):
                        # For pointer variables, return 0 (unknown size)
                        return ir.Constant(ir.IntType(32), 0)
                    else:
                        raise ValueError(f"Unknown type in sizeof for global {self.target.name}: {llvm_type}")
        
        # Handle other Expression cases (like sizeof(expression))
        target_val = self.target.codegen(builder, module)
        val_type = target_val.type
        
        # Pointer types (arrays decay to pointers)
        if isinstance(val_type, ir.PointerType):
            if isinstance(val_type.pointee, ir.ArrayType):
                arr_type = val_type.pointee
                element_bits = arr_type.element.width
                return ir.Constant(ir.IntType(32), element_bits * arr_type.count)
            return ir.Constant(ir.IntType(32), 64)  # Pointer size
        
        # Direct types
        if hasattr(val_type, 'width'):
            return ir.Constant(ir.IntType(32), val_type.width)  # Already in bits
        raise ValueError(f"Cannot determine size of type: {val_type}")

# Variable declarations
@dataclass
class VariableDeclaration(ASTNode):
    name: str
    type_spec: TypeSpec
    initial_value: Optional[Expression] = None
    is_global: bool = False

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Check for automatic array size inference with string literals
        infer_array_size = False
        resolved_type_spec = self.type_spec
        
        # Direct array type check
        if (self.type_spec.is_array and self.type_spec.array_size is None and
            self.initial_value and isinstance(self.initial_value, Literal) and
            self.initial_value.type == DataType.CHAR):
            infer_array_size = True
            string_length = len(self.initial_value.value)
        
        # Type alias check - if custom_typename exists, check if it resolves to an array
        elif (self.type_spec.custom_typename and
              self.initial_value and isinstance(self.initial_value, Literal) and
              self.initial_value.type == DataType.CHAR):
            try:
                resolved_llvm_type = self.type_spec.get_llvm_type(module)
                # If it's a pointer to i8 (string type), we can infer size
                if isinstance(resolved_llvm_type, ir.PointerType) and \
                   isinstance(resolved_llvm_type.pointee, ir.IntType) and \
                   resolved_llvm_type.pointee.width == 8:
                    infer_array_size = True
                    string_length = len(self.initial_value.value)
                    resolved_type_spec = TypeSpec(
                        base_type=DataType.DATA,
                        is_signed=False,
                        is_const=self.type_spec.is_const,
                        is_volatile=self.type_spec.is_volatile,
                        bit_width=8,
                        alignment=self.type_spec.alignment,
                        is_array=True,
                        array_size=string_length,
                        is_pointer=False
                    )
            except (NameError, AttributeError):
                pass  # Type not found, continue with normal processing
        
        if infer_array_size:
            # Create TypeSpec with inferred array size
            inferred_type_spec = TypeSpec(
                base_type=resolved_type_spec.base_type,
                is_signed=resolved_type_spec.is_signed,
                is_const=resolved_type_spec.is_const,
                is_volatile=resolved_type_spec.is_volatile,
                bit_width=resolved_type_spec.bit_width or 8,
                alignment=resolved_type_spec.alignment,
                is_array=True,
                array_size=string_length,
                is_pointer=resolved_type_spec.is_pointer,
                custom_typename=resolved_type_spec.custom_typename
            )
            llvm_type = inferred_type_spec.get_llvm_type_with_array(module)
        else:
            # Normal type resolution using the improved get_llvm_type_with_array
            llvm_type = self.type_spec.get_llvm_type_with_array(module)
        
        # Handle global variables (either at module scope OR explicitly marked with 'global' keyword)
        if builder.scope is None or self.is_global:
            # Check if global already exists (handle both original name and potential namespaced names)
            if self.name in module.globals:
                return module.globals[self.name]
            
            # For namespaced variables, check if any existing global has the same effective name
            base_name = self.name.split('__')[-1]
            for existing_name in list(module.globals.keys()):
                existing_base_name = existing_name.split('__')[-1]
                if existing_base_name == base_name and existing_name != self.name:
                    return module.globals[existing_name]
                elif existing_name == self.name:
                    return module.globals[existing_name]
                
            # Create new global
            gvar = ir.GlobalVariable(module, llvm_type, self.name)
            
            # Set initializer
            if self.initial_value:
                # Handle array literals specially
                if isinstance(llvm_type, ir.ArrayType) and hasattr(self.initial_value, 'value') and isinstance(self.initial_value.value, list):
                    element_values = []
                    for item in self.initial_value.value:
                        if hasattr(item, 'value'):
                            element_values.append(ir.Constant(llvm_type.element, item.value))
                        else:
                            element_values.append(ir.Constant(llvm_type.element, item))
                    gvar.initializer = ir.Constant(llvm_type, element_values)
                # Handle string literals for char arrays
                elif isinstance(llvm_type, ir.ArrayType) and isinstance(llvm_type.element, ir.IntType) and llvm_type.element.width == 8 and isinstance(self.initial_value, Literal) and self.initial_value.type == DataType.CHAR:
                    string_val = self.initial_value.value
                    char_values = []
                    for i, char in enumerate(string_val):
                        if i >= llvm_type.count:
                            break
                        char_values.append(ir.Constant(ir.IntType(8), ord(char)))
                    while len(char_values) < llvm_type.count:
                        char_values.append(ir.Constant(ir.IntType(8), 0))
                    gvar.initializer = ir.Constant(llvm_type, char_values)
                # Handle string literals for pointer types (global variables)
                elif isinstance(llvm_type, ir.PointerType) and isinstance(llvm_type.pointee, ir.IntType) and llvm_type.pointee.width == 8 and isinstance(self.initial_value, Literal) and self.initial_value.type == DataType.CHAR:
                    string_val = self.initial_value.value
                    string_bytes = string_val.encode('ascii')
                    str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
                    str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
                    
                    str_gv = ir.GlobalVariable(module, str_val.type, name=f".str.{self.name}")
                    str_gv.linkage = 'internal'
                    str_gv.global_constant = True
                    str_gv.initializer = str_val
                    
                    zero = ir.Constant(ir.IntType(1), 0)
                    str_ptr = str_gv.gep([zero, zero])
                    gvar.initializer = str_ptr
                else:
                    init_val = self.initial_value.codegen(builder, module)
                    if init_val is not None:
                        gvar.initializer = init_val
                    else:
                        if isinstance(llvm_type, ir.ArrayType):
                            gvar.initializer = ir.Constant(llvm_type, ir.Undefined)
                        else:
                            gvar.initializer = ir.Constant(llvm_type, 0)
            else:
                if isinstance(llvm_type, ir.ArrayType):
                    gvar.initializer = ir.Constant(llvm_type, ir.Undefined)
                elif isinstance(llvm_type, ir.IntType):
                    gvar.initializer = ir.Constant(llvm_type, 0)
                elif isinstance(llvm_type, ir.FloatType):
                    gvar.initializer = ir.Constant(llvm_type, 0.0)
                else:
                    gvar.initializer = ir.Constant(llvm_type, None)
            
            gvar.linkage = 'internal'
            return gvar
        
        # Handle local variables
        alloca = builder.alloca(llvm_type, name=self.name)
        
        # Store type information in scope metadata
        if not hasattr(builder, 'scope_type_info'):
            builder.scope_type_info = {}
        builder.scope_type_info[self.name] = self.type_spec
        
        if self.initial_value:
            # CRITICAL FIX: Handle array literals with proper element-by-element initialization
            if (isinstance(self.initial_value, Literal) and 
                self.initial_value.type == DataType.DATA and
                isinstance(self.initial_value.value, list) and
                isinstance(llvm_type, ir.ArrayType)):
                
                # Initialize each array element individually
                for i, elem in enumerate(self.initial_value.value):
                    zero = ir.Constant(ir.IntType(1), 0)
                    index = ir.Constant(ir.IntType(32), i)
                    elem_ptr = builder.gep(alloca, [zero, index], inbounds=True, name=f"{self.name}[{i}]")
                    
                    # Generate the element value
                    if isinstance(elem, Literal):
                        elem_val = elem.codegen(builder, module)
                    elif isinstance(elem, (int, float)):
                        elem_val = ir.Constant(llvm_type.element, elem)
                    else:
                        elem_val = elem.codegen(builder, module)
                    
                    # Ensure the element value matches the array element type
                    if elem_val.type != llvm_type.element:
                        if isinstance(elem_val.type, ir.IntType) and isinstance(llvm_type.element, ir.IntType):
                            if elem_val.type.width > llvm_type.element.width:
                                elem_val = builder.trunc(elem_val, llvm_type.element)
                            elif elem_val.type.width < llvm_type.element.width:
                                elem_val = builder.sext(elem_val, llvm_type.element)
                    
                    builder.store(elem_val, elem_ptr)
            
            # Handle string literals specially
            elif (isinstance(self.initial_value, Literal) and self.initial_value.type == DataType.CHAR):
                if isinstance(llvm_type, ir.PointerType) and isinstance(llvm_type.pointee, ir.IntType) and llvm_type.pointee.width == 8:
                    # Store string data on stack
                    string_val = self.initial_value.value
                    string_bytes = string_val.encode('ascii')
                    str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
                    
                    str_alloca = builder.alloca(str_array_ty, name=f"{self.name}_str_data")
                    
                    for i, byte_val in enumerate(string_bytes):
                        zero = ir.Constant(ir.IntType(1), 0)
                        index = ir.Constant(ir.IntType(32), i)
                        elem_ptr = builder.gep(str_alloca, [zero, index], name=f"{self.name}_char{i}")
                        char_val = ir.Constant(ir.IntType(8), byte_val)
                        builder.store(char_val, elem_ptr)
                    
                    zero = ir.Constant(ir.IntType(1), 0)
                    str_ptr = builder.gep(str_alloca, [zero, zero], name=f"{self.name}_str_ptr")
                    builder.store(str_ptr, alloca)
                    
                elif isinstance(llvm_type, ir.ArrayType) and isinstance(llvm_type.element, ir.IntType) and llvm_type.element.width == 8:
                    string_val = self.initial_value.value
                    
                    for i, char in enumerate(string_val):
                        if i >= llvm_type.count:
                            break
                        
                        zero = ir.Constant(ir.IntType(1), 0)
                        index = ir.Constant(ir.IntType(32), i)
                        elem_ptr = builder.gep(alloca, [zero, index], name=f"{self.name}[{i}]")
                        
                        char_val = ir.Constant(ir.IntType(8), ord(char))
                        builder.store(char_val, elem_ptr)
                    
                    for i in range(len(string_val), llvm_type.count):
                        zero = ir.Constant(ir.IntType(1), 0)
                        index = ir.Constant(ir.IntType(32), i)
                        elem_ptr = builder.gep(alloca, [zero, index], name=f"{self.name}[{i}]")
                        zero_char = ir.Constant(ir.IntType(8), 0)
                        builder.store(zero_char, elem_ptr)
                        
            elif isinstance(self.initial_value, FunctionCall) and self.initial_value.name.endswith('.__init'):
                constructor_func = module.globals.get(self.initial_value.name)
                if constructor_func is None:
                    raise NameError(f"Constructor not found: {self.initial_value.name}")
                
                args = [alloca]
                
                for i, arg_expr in enumerate(self.initial_value.arguments):
                    param_index = i + 1
                    if (isinstance(arg_expr, Literal) and arg_expr.type == DataType.CHAR and
                        param_index < len(constructor_func.args) and
                        isinstance(constructor_func.args[param_index].type, ir.PointerType) and
                        isinstance(constructor_func.args[param_index].type.pointee, ir.IntType) and
                        constructor_func.args[param_index].type.pointee.width == 8):
                        string_val = arg_expr.value
                        string_bytes = string_val.encode('ascii')
                        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
                        
                        str_alloca = builder.alloca(str_array_ty, name=f"ctor_arg{i}_str_data")
                        
                        for j, byte_val in enumerate(string_bytes):
                            zero = ir.Constant(ir.IntType(1), 0)
                            index = ir.Constant(ir.IntType(32), j)
                            elem_ptr = builder.gep(str_alloca, [zero, index])
                            char_val = ir.Constant(ir.IntType(8), byte_val)
                            builder.store(char_val, elem_ptr)
                        
                        zero = ir.Constant(ir.IntType(1), 0)
                        str_ptr = builder.gep(str_alloca, [zero, zero], name=f"ctor_arg{i}_str_ptr")
                        arg_val = str_ptr
                    else:
                        arg_val = arg_expr.codegen(builder, module)
                    
                    args.append(arg_val)
                
                init_val = builder.call(constructor_func, args)
            else:
                init_val = self.initial_value.codegen(builder, module)
                if init_val is not None:
                    if (isinstance(self.initial_value, CastExpression) and
                        isinstance(init_val.type, ir.PointerType) and
                        isinstance(llvm_type, ir.ArrayType)):
                        array_ptr_type = ir.PointerType(llvm_type)
                        casted_ptr = builder.bitcast(init_val, array_ptr_type, name="cast_to_array_ptr")
                        array_value = builder.load(casted_ptr, name="loaded_array")
                        builder.store(array_value, alloca)
                    else:
                        if init_val.type != llvm_type:
                            if (isinstance(self.initial_value, BinaryOp) and 
                                self.initial_value.operator in (Operator.ADD, Operator.SUB) and
                                isinstance(init_val.type, ir.PointerType) and 
                                isinstance(init_val.type.pointee, ir.ArrayType) and
                                isinstance(llvm_type, ir.PointerType) and 
                                isinstance(llvm_type.pointee, ir.IntType)):
                                zero = ir.Constant(ir.IntType(1), 0)
                                array_ptr = builder.gep(init_val, [zero, zero], name="concat_array_to_ptr")
                                builder.store(array_ptr, alloca)
                                builder.scope[self.name] = alloca
                                if self.type_spec.is_volatile:
                                    if not hasattr(builder, 'volatile_vars'):
                                        builder.volatile_vars = set()
                                    builder.volatile_vars.add(self.name)
                                return alloca
                            elif isinstance(llvm_type, ir.PointerType) and isinstance(init_val.type, ir.PointerType):
                                if llvm_type.pointee != init_val.type.pointee:
                                    init_val = builder.bitcast(init_val, llvm_type)
                            elif isinstance(init_val.type, ir.IntType) and isinstance(llvm_type, ir.IntType):
                                if init_val.type.width > llvm_type.width:
                                    init_val = builder.trunc(init_val, llvm_type)
                                elif init_val.type.width < llvm_type.width:
                                    init_val = builder.sext(init_val, llvm_type)
                            elif isinstance(init_val.type, ir.IntType) and isinstance(llvm_type, ir.FloatType):
                                init_val = builder.sitofp(init_val, llvm_type)
                            elif isinstance(init_val.type, ir.FloatType) and isinstance(llvm_type, ir.IntType):
                                init_val = builder.fptosi(init_val, llvm_type)
                        builder.store(init_val, alloca)
        
        builder.scope[self.name] = alloca
        if self.type_spec.is_volatile:
            if not hasattr(builder, 'volatile_vars'):
                builder.volatile_vars = set()
            builder.volatile_vars.add(self.name)
        return alloca
    
    def get_llvm_type(self, module: ir.Module) -> ir.Type:
        if infer_array_size:
            inferred_type_spec = TypeSpec(
                base_type=resolved_type_spec.base_type,
                is_signed=resolved_type_spec.is_signed,
                is_const=resolved_type_spec.is_const,
                is_volatile=resolved_type_spec.is_volatile,
                bit_width=resolved_type_spec.bit_width or 8,
                alignment=resolved_type_spec.alignment,
                is_array=True,
                array_size=string_length,
                is_pointer=resolved_type_spec.is_pointer,
                custom_typename=resolved_type_spec.custom_typename,
                storage_class=resolved_type_spec.storage_class  # NEW
            )
            llvm_type = inferred_type_spec.get_llvm_type_with_array(module)
        else:
            llvm_type = self.type_spec.get_llvm_type_with_array(module)

# Type declarations
@dataclass
class TypeDeclaration(Expression):
    """AST node for type declarations using AS keyword"""
    name: str
    base_type: TypeSpec
    initial_value: Optional[Expression] = None

    def __repr__(self):
        init_str = f" = {self.initial_value}" if self.initial_value else ""
        return f"TypeDeclaration({self.base_type} as {self.name}{init_str})"

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        #print(f"DEBUG TypeDeclaration: Creating alias '{self.name}' for base_type '{self.base_type}'")
        #print(f"DEBUG TypeDeclaration: base_type={self.base_type}")
        llvm_type = self.base_type.get_llvm_type_with_array(module)
        #print(f"DEBUG TypeDeclaration: resolved llvm_type={llvm_type}")
        
        if not hasattr(module, '_type_aliases'):
            module._type_aliases = {}
        module._type_aliases[self.name] = llvm_type
        #print(f"DEBUG TypeDeclaration: Added alias '{self.name}' -> {llvm_type}")
        
        if self.initial_value:
            init_val = self.initial_value.codegen(builder, module)
            gvar = ir.GlobalVariable(module, llvm_type, self.name)
            gvar.linkage = 'internal'
            gvar.global_constant = True
            gvar.initializer = init_val
            return gvar
        return None
    
    def get_llvm_type(self, module: ir.Module) -> ir.Type:
        # Handle custom type names (type aliases)
        if self.custom_typename:
            # Look up the type alias
            if hasattr(module, '_type_aliases') and self.custom_typename in module._type_aliases:
                return module._type_aliases[self.custom_typename]
            
            # Check for namespaced types (e.g., standard__types__noopstr)
            potential_names = [
                self.custom_typename,
                f"standard__types__{self.custom_typename}",
                f"standard__{self.custom_typename}"
            ]
            
            for name in potential_names:
                if hasattr(module, '_type_aliases') and name in module._type_aliases:
                    return module._type_aliases[name]
            
            # If not found in aliases, check struct types
            if hasattr(module, '_struct_types') and self.custom_typename in module._struct_types:
                return module._struct_types[self.custom_typename]
            
            raise NameError(f"Unknown type: {self.custom_typename}")
        
        # Handle built-in types
        if self.base_type == DataType.INT:
            return ir.IntType(32)
        elif self.base_type == DataType.FLOAT:
            return ir.FloatType()
        elif self.base_type == DataType.BOOL:
            return ir.IntType(1)
        elif self.base_type == DataType.CHAR:
            return ir.IntType(8)
        elif self.base_type == DataType.VOID:
            return ir.VoidType()
        elif self.base_type == DataType.DATA:
            if self.bit_width is None:
                raise ValueError(f"DATA type missing bit_width for {self}")
            return ir.IntType(self.bit_width)
        else:
            raise ValueError(f"Unsupported type: {self.base_type}")

# Statements
@dataclass
class Statement(ASTNode):
    pass

@dataclass
class MacroDefinition(Statement):
    """AST node for def IDENTIFIER LITERAL; statements - defines a macro"""
    macro_name: str
    macro_value: Union[str, int, float, bool]
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> None:
        """Generate code to define a macro and create a global constant"""
        # Add macro to the module's macro registry
        define_macro(module, self.macro_name)
        
        # Create a global constant for the macro value
        if isinstance(self.macro_value, str):
            # String literal - create global string constant
            string_bytes = self.macro_value.encode('ascii') #+ b'\0'  # NEVER NULL TERMINATE
            str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
            str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
            
            # Create global variable
            gv = ir.GlobalVariable(module, str_val.type, name=self.macro_name)
            gv.linkage = 'internal'
            gv.global_constant = True
            gv.initializer = str_val
        elif isinstance(self.macro_value, int):
            # Integer literal - create global integer constant
            int_val = ir.Constant(ir.IntType(32), self.macro_value)
            gv = ir.GlobalVariable(module, int_val.type, name=self.macro_name)
            gv.linkage = 'internal'
            gv.global_constant = True
            gv.initializer = int_val
        elif isinstance(self.macro_value, float):
            # Float literal - create global float constant
            float_val = ir.Constant(ir.FloatType(), self.macro_value)
            gv = ir.GlobalVariable(module, float_val.type, name=self.macro_name)
            gv.linkage = 'internal'
            gv.global_constant = True
            gv.initializer = float_val
        elif isinstance(self.macro_value, bool):
            # Boolean literal - create global boolean constant
            bool_val = ir.Constant(ir.IntType(1), self.macro_value)
            gv = ir.GlobalVariable(module, bool_val.type, name=self.macro_name)
            gv.linkage = 'internal'
            gv.global_constant = True
            gv.initializer = bool_val

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
            # Simple variable assignment
            if builder.scope is not None and self.target.name in builder.scope:
                # Local variable
                ptr = builder.scope[self.target.name]
            elif self.target.name in module.globals:
                # Global variable
                ptr = module.globals[self.target.name]
            else:
                raise NameError(f"Unknown variable: {self.target.name}")
            
            # Check if this is an array concatenation assignment that requires resizing
            if (isinstance(self.value, BinaryOp) and self.value.operator == Operator.ADD and
                isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, ir.ArrayType)):
                # This is the result of array concatenation - update variable to point to new array
                if builder.scope is not None and self.target.name in builder.scope:
                    # For local variables, update the scope to point to the new array
                    builder.scope[self.target.name] = val
                    return val
                else:
                    # For global variables, we can't easily resize, so convert to element pointer
                    zero = ir.Constant(ir.IntType(1), 0)
                    array_ptr = builder.gep(val, [zero, zero], name="array_to_ptr")
                    builder.store(array_ptr, ptr)
                    return array_ptr
            
            # Handle type compatibility for assignments
            if val.type != ptr.type.pointee:
                # Handle array pointer assignments - for arrays, just store the pointer directly
                if (isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, ir.ArrayType) and
                    isinstance(ptr.type, ir.PointerType) and isinstance(ptr.type.pointee, ir.PointerType)):
                    # This is assigning an array to a pointer type (like noopstr)
                    # Get pointer to first element of array
                    zero = ir.Constant(ir.IntType(1), 0)
                    array_ptr = builder.gep(val, [zero, zero], name="array_to_ptr")
                    builder.store(array_ptr, ptr)
                    return array_ptr
                # Handle other type mismatches as needed
                elif isinstance(val.type, ir.IntType) and isinstance(ptr.type.pointee, ir.IntType):
                    if val.type.width != ptr.type.pointee.width:
                        if val.type.width < ptr.type.pointee.width:
                            val = builder.sext(val, ptr.type.pointee)
                        else:
                            val = builder.trunc(val, ptr.type.pointee)
            
            st = builder.store(val, ptr)
            st.volatile = True
            return val
            
        elif isinstance(self.target, MemberAccess):
            # Struct/union/object member assignment
            # For member access, we need the pointer, not the loaded value
            if isinstance(self.target.object, Identifier):
                # Get the variable pointer directly from scope instead of loading
                var_name = self.target.object.name
                if builder.scope is not None and var_name in builder.scope:
                    obj = builder.scope[var_name]  # This is the pointer
                elif var_name in module.globals:
                    obj = module.globals[var_name]  # This is the pointer
                else:
                    raise NameError(f"Unknown variable: {var_name}")
            else:
                # For other expressions, generate code normally
                obj = self.target.object.codegen(builder, module)
            
            member_name = self.target.member
            
            #print(f"DEBUG Assignment: obj = {obj}")
            #print(f"DEBUG Assignment: obj.type = {obj.type}")
            #if hasattr(obj.type, 'pointee'):
                #print(f"DEBUG Assignment: obj.type.pointee = {obj.type.pointee}")
            #print(f"DEBUG Assignment: member_name = {member_name}")
            #print(f"DEBUG Assignment: isinstance(obj.type, ir.PointerType) = {isinstance(obj.type, ir.PointerType)}")
            #if isinstance(obj.type, ir.PointerType):
                #print(f"DEBUG Assignment: isinstance(obj.type.pointee, ir.LiteralStructType) = {isinstance(obj.type.pointee, ir.LiteralStructType)}")
            #if hasattr(module, '_union_types'):
                #print(f"DEBUG Assignment: Union types available: {list(module._union_types.keys())}")
                #for union_name, union_type in module._union_types.items():
                    #print(f"DEBUG Assignment: Union {union_name} type: {union_type}")
            
            # Handle both literal struct types and identified struct types
            is_struct_pointer = (isinstance(obj.type, ir.PointerType) and 
                            (isinstance(obj.type.pointee, ir.LiteralStructType) or
                             hasattr(obj.type.pointee, '_name') or  # Identified struct type
                             hasattr(obj.type.pointee, 'elements')))  # Other struct-like types
            
            if is_struct_pointer:
                struct_type = obj.type.pointee
                #print(f"DEBUG Assignment: Detected struct type: {struct_type}")
                #print(f"DEBUG Assignment: struct_type has names: {hasattr(struct_type, 'names')}")
                #if hasattr(struct_type, 'names'):
                    #print(f"DEBUG Assignment: struct_type.names: {struct_type.names}")
                
                # Check if this is a union first
                if hasattr(module, '_union_types'):
                    for union_name, union_type in module._union_types.items():
                        if union_type == struct_type:
                            # This is a union - handle union member assignment
                            return self._handle_union_member_assignment(builder, module, obj, union_name, member_name, val)
                
                # Regular struct member assignment
                if hasattr(struct_type, 'names'):
                    try:
                        idx = struct_type.names.index(member_name)
                        #print(f"DEBUG Assignment: Found member '{member_name}' at index {idx}")
                        member_ptr = builder.gep(
                            obj,
                            [ir.Constant(ir.IntType(32), 0),
                             ir.Constant(ir.IntType(32), idx)],
                            inbounds=True
                        )
                        builder.store(val, member_ptr)
                        return val
                    except ValueError:
                        raise ValueError(f"Member '{member_name}' not found in struct")
                else:
                    raise ValueError(f"Struct type missing member names: {struct_type}")
            
            raise ValueError(f"Cannot assign to member '{member_name}' of non-struct type: {obj.type}")
    
        elif isinstance(self.target, ArrayAccess):
            # Array element assignment
            array = self.target.array.codegen(builder, module)
            index = self.target.index.codegen(builder, module)
            
            if isinstance(array.type, ir.PointerType) and isinstance(array.type.pointee, ir.ArrayType):
                # Calculate element pointer
                zero = ir.Constant(ir.IntType(1), 0)
                elem_ptr = builder.gep(array, [zero, index], inbounds=True)
                builder.store(val, elem_ptr)
                return val
            else:
                raise ValueError("Cannot index non-array type")
                
        elif isinstance(self.target, PointerDeref):
            # Pointer dereference assignment (*ptr = val)
            ptr = self.target.pointer.codegen(builder, module)
            if isinstance(ptr.type, ir.PointerType):
                builder.store(val, ptr)
                return val
            else:
                raise ValueError("Cannot dereference non-pointer type")
                
        else:
            raise ValueError(f"Cannot assign to {type(self.target).__name__}")
    
    def _handle_union_member_assignment(self, builder: ir.IRBuilder, module: ir.Module, union_ptr: ir.Value, union_name: str, member_name: str, val: ir.Value) -> ir.Value:
        """Handle union member assignment by casting the union to the appropriate member type"""
        # Get union member information
        if not hasattr(module, '_union_member_info') or union_name not in module._union_member_info:
            raise ValueError(f"Union member info not found for '{union_name}'")
        
        union_info = module._union_member_info[union_name]
        member_names = union_info['member_names']
        member_types = union_info['member_types']
        
        # Find the requested member
        if member_name not in member_names:
            raise ValueError(f"Member '{member_name}' not found in union '{union_name}'")
        
        member_index = member_names.index(member_name)
        member_type = member_types[member_index]
        
        # Create unique identifier for this union variable instance
        union_var_id = f"{union_ptr.name}_{id(union_ptr)}"
        
        # Check if union has already been initialized (immutability check)
        if hasattr(builder, 'initialized_unions') and union_var_id in builder.initialized_unions:
            raise RuntimeError(f"Union variable is immutable after initialization. Cannot reassign member '{member_name}' of union '{union_name}'")
        
        # Mark this union as initialized
        if not hasattr(builder, 'initialized_unions'):
            builder.initialized_unions = set()
        builder.initialized_unions.add(union_var_id)
        
        # Cast the union pointer to the appropriate member type pointer and store the value
        member_ptr_type = ir.PointerType(member_type)
        casted_ptr = builder.bitcast(union_ptr, member_ptr_type, name=f"union_as_{member_name}")
        builder.store(val, casted_ptr)
        return val

@dataclass
class CompoundAssignment(Statement):
    target: Expression
    op_token: Any  # TokenType enum for the compound operator  
    value: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate code for compound assignments like +=, -=, *=, /=, %="""
        from flexer import TokenType
        
        # Map compound assignment tokens to binary operators
        op_map = {
            TokenType.PLUS_ASSIGN: Operator.ADD,
            TokenType.MINUS_ASSIGN: Operator.SUB,
            TokenType.MULTIPLY_ASSIGN: Operator.MUL,
            TokenType.DIVIDE_ASSIGN: Operator.DIV,
            TokenType.MODULO_ASSIGN: Operator.MOD,
            TokenType.POWER_ASSIGN: Operator.POWER,
            TokenType.XOR_ASSIGN: Operator.XOR,
            TokenType.BITSHIFT_LEFT_ASSIGN: Operator.BITSHIFT_LEFT,
            TokenType.BITSHIFT_RIGHT_ASSIGN: Operator.BITSHIFT_RIGHT,
        }
        
        if self.op_token not in op_map:
            raise ValueError(f"Unsupported compound assignment operator: {self.op_token}")
        
        binary_op = op_map[self.op_token]
        
        # For compound assignment like s += q, this is equivalent to s = s + q
        # But we need to handle array concatenation specially to support dynamic resizing
        
        # Check if this is array concatenation (ADD operation with array operands)
        if binary_op == Operator.ADD and isinstance(self.target, Identifier):
            # Get the target variable
            if builder.scope is not None and self.target.name in builder.scope:
                target_ptr = builder.scope[self.target.name]
            elif self.target.name in module.globals:
                target_ptr = module.globals[self.target.name]
            else:
                raise NameError(f"Unknown variable: {self.target.name}")
            
            # Load the current value of the target
            target_val = self.target.codegen(builder, module)
            right_val = self.value.codegen(builder, module)
            
            # Check if both operands are arrays or array pointers
            if (is_array_or_array_pointer(target_val) and is_array_or_array_pointer(right_val)):
                # This is array concatenation - create the binary operation
                binary_expr = BinaryOp(self.target, binary_op, self.value)
                concat_result = binary_expr.codegen(builder, module)
                
                # For array concatenation, we need to resize the variable to accommodate the new array
                # This is similar to dynamic reallocation - create new storage and update the variable
                if isinstance(concat_result.type, ir.PointerType) and isinstance(concat_result.type.pointee, ir.ArrayType):
                    # The concatenated result is a new array with the proper size
                    # Update the variable to point to this new array
                    if builder.scope is not None and self.target.name in builder.scope:
                        # For local variables, update the scope to point to the new array
                        builder.scope[self.target.name] = concat_result
                        return concat_result
                    else:
                        # For global variables, we can't easily resize, so convert to element pointer
                        zero = ir.Constant(ir.IntType(1), 0)
                        array_ptr = builder.gep(concat_result, [zero, zero], name="array_to_ptr")
                        builder.store(array_ptr, target_ptr)
                        return array_ptr
                else:
                    # Direct storage for other pointer types
                    builder.store(concat_result, target_ptr)
                    return concat_result
        
        # For non-array operations, fall back to the simple approach
        binary_expr = BinaryOp(self.target, binary_op, self.value)
        assignment = Assignment(self.target, binary_expr)
        return assignment.codegen(builder, module)
    
        """Dynamically resize arrays to accommodate new values during assignment"""
        # Get array information
        val_elem_type, val_len = get_array_info(val)
        ptr_elem_type, ptr_len = get_array_info(ptr)
        
        # If the new array is larger, we need to reallocate
        if val_len > ptr_len:
            # Create new array type with the larger size
            new_array_type = ir.ArrayType(val_elem_type, val_len)
            
            # Allocate new storage for the resized array
            new_alloca = builder.alloca(new_array_type, name=f"{var_name}_resized" if var_name else "array_resized")
            
            # Copy existing data from old array to new array (first ptr_len elements)
            if ptr_len > 0:
                elem_size_bytes = ptr_elem_type.width // 8
                old_bytes = ptr_len * elem_size_bytes
                
                # Get pointer to start of old array
                zero = ir.Constant(ir.IntType(1), 0)
                old_start = builder.gep(ptr, [zero, zero], name="old_start")
                
                # Get pointer to start of new array
                new_start = builder.gep(new_alloca, [zero, zero], name="new_start")
                
                # Copy old data
                emit_memcpy(builder, module, new_start, old_start, old_bytes)
            
            # Copy new data to the new array (overwriting all elements)
            new_bytes = val_len * (val_elem_type.width // 8)
            zero = ir.Constant(ir.IntType(1), 0)
            new_start = builder.gep(new_alloca, [zero, zero], name="new_start")
            val_start = builder.gep(val, [zero, zero], name="val_start")
            emit_memcpy(builder, module, new_start, val_start, new_bytes)
            
            # Update the original variable to point to the new array
            if var_name and builder.scope and var_name in builder.scope:
                builder.scope[var_name] = new_alloca
            
            return new_alloca
        else:
            # If new array is smaller or same size, just copy the data
            copy_len = min(val_len, ptr_len)
            copy_bytes = copy_len * (val_elem_type.width // 8)
            
            zero = ir.Constant(ir.IntType(1), 0)
            ptr_start = builder.gep(ptr, [zero, zero], name="ptr_start")
            val_start = builder.gep(val, [zero, zero], name="val_start")
            
            # Copy the data
            emit_memcpy(builder, module, ptr_start, val_start, copy_bytes)
            
            # If the new array is smaller, zero out the remaining elements
            if val_len < ptr_len:
                remaining_bytes = (ptr_len - val_len) * (ptr_elem_type.width // 8)
                if remaining_bytes > 0:
                    # Get pointer to remaining area
                    val_len_const = ir.Constant(ir.IntType(32), val_len)
                    remaining_start = builder.gep(ptr, [zero, val_len_const], name="remaining_start")
                    
                    # Declare memset if not already declared
                    memset_name = "llvm.memset.p0i8.i64"
                    if memset_name not in module.globals:
                        memset_type = ir.FunctionType(
                            ir.VoidType(),
                            [ir.PointerType(ir.IntType(8)),  # dst
                             ir.IntType(8),                  # val
                             ir.IntType(64),                 # len
                             ir.IntType(1)]                  # volatile
                        )
                        memset_func = ir.Function(module, memset_type, name=memset_name)
                        memset_func.attributes.add('nounwind')
                    else:
                        memset_func = module.globals[memset_name]
                    
                    # Cast to i8* if needed
                    i8_ptr = ir.PointerType(ir.IntType(8))
                    if remaining_start.type != i8_ptr:
                        remaining_start = builder.bitcast(remaining_start, i8_ptr)
                    
                    # Zero out remaining bytes
                    builder.call(memset_func, [
                        remaining_start,
                        ir.Constant(ir.IntType(8), 0),  # zero
                        ir.Constant(ir.IntType(64), remaining_bytes),
                        ir.Constant(ir.IntType(1), 0)  # not volatile
                    ])
            
            return ptr
    
    def _handle_union_member_assignment(self, builder: ir.IRBuilder, module: ir.Module, union_ptr: ir.Value, union_name: str, member_name: str, val: ir.Value) -> ir.Value:
        """Handle union member assignment by casting the union to the appropriate member type"""
        # Get union member information
        if not hasattr(module, '_union_member_info') or union_name not in module._union_member_info:
            raise ValueError(f"Union member info not found for '{union_name}'")
        
        union_info = module._union_member_info[union_name]
        member_names = union_info['member_names']
        member_types = union_info['member_types']
        
        # Find the requested member
        if member_name not in member_names:
            raise ValueError(f"Member '{member_name}' not found in union '{union_name}'")
        
        member_index = member_names.index(member_name)
        member_type = member_types[member_index]
        
        # Create unique identifier for this union variable instance
        union_var_id = f"{union_ptr.name}_{id(union_ptr)}"
        
        # Check if union has already been initialized (immutability check)
        if hasattr(builder, 'initialized_unions') and union_var_id in builder.initialized_unions:
            raise RuntimeError(f"Union variable is immutable after initialization. Cannot reassign member '{member_name}' of union '{union_name}'")
        
        # Mark this union as initialized
        if not hasattr(builder, 'initialized_unions'):
            builder.initialized_unions = set()
        builder.initialized_unions.add(union_var_id)
        
        # Cast the union pointer to the appropriate member type pointer and store the value
        member_ptr_type = ir.PointerType(member_type)
        casted_ptr = builder.bitcast(union_ptr, member_ptr_type, name=f"union_as_{member_name}")
        builder.store(val, casted_ptr)
        return val

@dataclass
class Block(Statement):
    statements: List[Statement] = field(default_factory=list)

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        result = None
        #print(f"DEBUG Block: Processing {len(self.statements)} statements")
        for i, stmt in enumerate(self.statements):
            #print(f"DEBUG Block: Processing statement {i}: {type(stmt).__name__}")
            if stmt is not None:  # Skip None statements
                try:
                    stmt_result = stmt.codegen(builder, module)
                    if stmt_result is not None:  # Only update result if not None
                        result = stmt_result
                except Exception as e:
                    print(f"DEBUG Block: Error in statement {i} ({type(stmt).__name__}): {e}")
                    raise
        return result

@dataclass
class XorStatement(Statement):
    expressions: List[Expression] = field(default_factory=list)

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
        cond_val = self.condition.codegen(builder, module)
        
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
        
        # Emit else block
        builder.position_at_start(else_block)
        if self.else_block:
            self.else_block.codegen(builder, module)
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
            print(f"Warning: Could not evaluate global if condition: {e}")
            # Default to executing the then block for safety
            self.then_block.codegen(builder, module)
        
        return None

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
            builder.scope[self.variables[0]] = var_ptr
            
        elif isinstance(collection.type, ir.PointerType) and isinstance(collection.type.pointee, ir.IntType(8)):
            # String iteration (char*)
            zero = ir.Constant(ir.IntType(1), 0)
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
            builder.scope[self.variables[0]] = var_ptr
            
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
        if self.value is not None:
            ret_val = self.value.codegen(builder, module)
            # Handle void literal returns
            if ret_val is None or (isinstance(self.value, Literal) and self.value.type == DataType.VOID):
                builder.ret_void()
            else:
                # Get the function's declared return type
                func = builder.block.function
                #print(f"DEBUG: func = {func}")
                #print(f"DEBUG: func.type = {func.type}")
                #print(f"DEBUG: type(func.type) = {type(func.type)}")
                
                # The function type is accessed differently in LLVM
                if hasattr(func.type, 'return_type'):
                    expected_ret_type = func.type.return_type
                elif hasattr(func.type, 'pointee') and hasattr(func.type.pointee, 'return_type'):
                    expected_ret_type = func.type.pointee.return_type
                else:
                    raise RuntimeError(f"Cannot determine return type from func.type: {func.type}")
                
                # Cast return value to match function signature if needed
                if ret_val.type != expected_ret_type:
                    ret_val = self._cast_to_return_type(builder, ret_val, expected_ret_type)
                
                builder.ret(ret_val)
        else:
            builder.ret_void()
        return None
    
    def _cast_to_return_type(self, builder: ir.IRBuilder, value: ir.Value, target_type: ir.Type) -> ir.Value:
        """Automatically cast return value to match function signature"""
        source_type = value.type
        
        # If types already match, no cast needed
        if source_type == target_type:
            return value
        
        # Handle string literal to pointer conversion
        if (isinstance(source_type, ir.IntType) and source_type.width == 8 and 
            isinstance(target_type, ir.PointerType) and isinstance(target_type.pointee, ir.IntType) and target_type.pointee.width == 8):
            # Convert single character to string pointer
            # Check if this is from an empty string literal by looking at the original expression
            if (hasattr(self, 'value') and isinstance(self.value, Literal) and 
                self.value.type == DataType.CHAR and self.value.value == ''):
                # Create a global empty string constant
                empty_str = "\0"  # Null terminated empty string
                str_bytes = empty_str.encode('ascii')
                str_array_ty = ir.ArrayType(ir.IntType(8), len(str_bytes))
                str_val = ir.Constant(str_array_ty, bytearray(str_bytes))
                
                # Get module reference - need to pass it properly
                func = builder.block.function
                module = func.module
                
                gv = ir.GlobalVariable(module, str_val.type, name=".str.empty")
                gv.linkage = 'internal'
                gv.global_constant = True
                gv.initializer = str_val
                
                # Get pointer to the first character of the string
                zero = ir.Constant(ir.IntType(1), 0)
                str_ptr = builder.gep(gv, [zero, zero], name="empty_str_ptr")
                return str_ptr
        
        # Handle integer type conversions
        if isinstance(source_type, ir.IntType) and isinstance(target_type, ir.IntType):
            if source_type.width < target_type.width:
                # Extend to larger integer type (sign extend)
                return builder.sext(value, target_type)
            elif source_type.width > target_type.width:
                # Truncate to smaller integer type
                return builder.trunc(value, target_type)
            else:
                # Same width, should not happen but return as-is
                return value
        
        # Handle int to float conversion
        elif isinstance(source_type, ir.IntType) and isinstance(target_type, ir.FloatType):
            return builder.sitofp(value, target_type)
        
        # Handle float to int conversion
        elif isinstance(source_type, ir.FloatType) and isinstance(target_type, ir.IntType):
            return builder.fptosi(value, target_type)
        
        # Handle pointer casts
        elif isinstance(source_type, ir.PointerType) and isinstance(target_type, ir.PointerType):
            return builder.bitcast(value, target_type)
        
        else:
            raise ValueError(f"Cannot automatically cast return value from {source_type} to {target_type}")

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
    catch_blocks: List[Tuple[Optional[TypeSpec], str, Block]]  # (type, name, block)

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Flux try/catch using LLVM's native exception handling.
        Generates proper LLVM IR that can catch runtime errors including UAF.
        
        Uses LLVM's invoke/landingpad mechanism for structured exception handling.
        """
        
        # Create basic blocks
        func = builder.block.function
        try_block = func.append_basic_block('try')
        landing_pad_block = func.append_basic_block('lpad')
        catch_blocks_ir = []
        end_block = func.append_basic_block('try.end')
        
        # Create catch blocks
        for i, (exc_type, exc_name, catch_body) in enumerate(self.catch_blocks):
            catch_block = func.append_basic_block(f'catch_{i}')
            catch_blocks_ir.append(catch_block)
        
        # Branch to try block
        builder.branch(try_block)
        
        # Generate TRY block with invoke instead of direct calls
        builder.position_at_start(try_block)
        
        # Generate try body code with exception-aware calls
        # Store landing pad info for exception-throwing operations
        old_landing_pad = getattr(builder, 'flux_landing_pad', None)
        builder.flux_landing_pad = landing_pad_block
        
        # Generate the try body - this will use invoke for potentially throwing operations
        self.try_body.codegen(builder, module)
        
        # Restore previous landing pad
        builder.flux_landing_pad = old_landing_pad
        
        # If try block completes normally, branch to end
        if not builder.block.is_terminated:
            builder.branch(end_block)
        
        # Generate LANDING PAD block
        builder.position_at_start(landing_pad_block)
        
        # Create personality function for exception handling
        personality_func = self._get_or_create_personality_func(module)
        # Set personality function on the containing function
        # Note: In llvmlite, personality function is set differently
        try:
            if hasattr(func, 'personality'):
                func.personality = personality_func
            elif hasattr(func.attributes, 'personality'):
                func.attributes.personality = personality_func
            else:
                # Skip personality function setting for now
                pass
        except Exception as e:
            # If setting personality function fails, continue without it
            print(f"Warning: Could not set personality function: {e}")
            pass
        
        # Create landing pad instruction
        # This catches all exceptions (catch-all with cleanup)
        landing_pad = builder.landingpad(
            ir.LiteralStructType([ir.PointerType(ir.IntType(8)), ir.IntType(32)]),
            personality_func
        )
        
        # Add catch-all clause (catches any exception)
        landing_pad.add_clause(ir.Constant(ir.PointerType(ir.IntType(8)), None))
        landing_pad.cleanup = True
        
        # Extract exception pointer and selector from landing pad
        exc_ptr = builder.extract_value(landing_pad, 0, name='exc_ptr')
        exc_selector = builder.extract_value(landing_pad, 1, name='exc_sel')
        
        # For catch-all blocks, we don't need to check the selector
        # Just jump to the first catch block (assuming catch() means catch-all)
        if catch_blocks_ir:
            builder.branch(catch_blocks_ir[0])
        else:
            # No catch blocks - resume exception
            builder.resume(landing_pad)
        
        # Generate CATCH blocks
        for i, (exc_type, exc_name, catch_body) in enumerate(self.catch_blocks):
            builder.position_at_start(catch_blocks_ir[i])
            
            # Create scope for catch block if there's an exception variable
            if exc_name:
                # Allocate space for exception value
                if exc_type:
                    exc_type_llvm = exc_type.get_llvm_type(module)
                else:
                    exc_type_llvm = ir.IntType(32)  # Default exception type
                
                exc_var = builder.alloca(exc_type_llvm, name=exc_name)
                # For now, store a constant exception value
                # In a full implementation, this would extract info from exc_ptr
                exc_value = ir.Constant(exc_type_llvm, 1001)  # UAF exception code
                builder.store(exc_value, exc_var)
                builder.scope[exc_name] = exc_var
            
            # Generate catch body
            catch_body.codegen(builder, module)
            
            # Remove exception variable from scope
            if exc_name and exc_name in builder.scope:
                del builder.scope[exc_name]
            
            # Branch to end if not already terminated
            if not builder.block.is_terminated:
                builder.branch(end_block)
        
        # Position at end block
        builder.position_at_start(end_block)
        return None
    
    def _get_or_create_personality_func(self, module: ir.Module) -> ir.Function:
        """Get or create the exception personality function"""
        func_name = '__flux_personality_v0'
        if func_name in module.globals:
            return module.globals[func_name]
        
        # Create personality function signature
        # This is platform-specific, but typically looks like:
        # i32 @personality(i32, i32, i64, i8*, i8*)
        func_type = ir.FunctionType(
            ir.IntType(32),
            [ir.IntType(32), ir.IntType(32), ir.IntType(64), 
             ir.PointerType(ir.IntType(8)), ir.PointerType(ir.IntType(8))]
        )
        func = ir.Function(module, func_type, func_name)
        func.linkage = 'external'
        
        # Generate basic personality function body
        entry_block = func.append_basic_block('entry')
        pers_builder = ir.IRBuilder(entry_block)
        
        # For now, always return 1 (EXCEPTION_EXECUTE_HANDLER)
        # This means "handle the exception"
        pers_builder.ret(ir.Constant(ir.IntType(32), 1))
        
        return func

@dataclass
class ThrowStatement(Statement):
    expression: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Bare-metal longjmp implementation
        exc_val = self.expression.codegen(builder, module)
        
        # Store exception in known location
        exc_slot = builder.gep(
            module.globals.get('__flux_exception_slot'),
            [ir.Constant(ir.IntType(64), 0)],
            name='exc.ptr'
        )
        builder.store(exc_val, exc_slot)
        
        # longjmp to handler
        builder.call(
            module.declare_intrinsic('llvm.eh.sjlj.longjmp'),
            [builder.bitcast(
                builder.load(builder.globals.get('__flux_jmpbuf')),
                ir.PointerType(ir.IntType(8))
            )],
        )
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
            # Create message string constant
            msg_str = self.message + '\n'
            msg_bytes = msg_str.encode('ascii')
            msg_type = ir.ArrayType(ir.IntType(8), len(msg_bytes))
            msg_const = ir.Constant(msg_type, bytearray(msg_bytes))
            
            msg_gv = ir.GlobalVariable(
                module,
                msg_type,
                name='ASSERT_MSG'
            )
            msg_gv.initializer = msg_const
            msg_gv.linkage = 'internal'
            msg_gv.global_constant = True
            
            # Get pointer to message
            zero = ir.Constant(ir.IntType(1), 0)
            msg_ptr = builder.gep(msg_gv, [zero, zero], inbounds=True)
            
            # Declare puts if not already present
            # URGENT -> CALL PRINT
            # TODO: DEFINE GENERIC PRINT IN STANDARD LIBRARY
            puts = module.globals.get('puts')
            builder.call(puts, [msg_ptr])

        # Abort
        abort = module.globals.get('abort')
        builder.call(abort, [])
        builder.unreachable()

        # Success block
        builder.position_at_start(pass_block)
        return None

# Function parameter
@dataclass
class Parameter:
    name: str
    type_spec: TypeSpec
    
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
                    if builder.scope and var_name in builder.scope:
                        var_ptr = builder.scope[var_name]
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
                    if builder.scope and var_name in builder.scope:
                        var_ptr = builder.scope[var_name]
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
            if isinstance(output_type, ir.PointerType):
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
    return_type: TypeSpec
    body: Block
    is_const: bool = False
    is_volatile: bool = False
    is_prototype: bool = False
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Function:
        # Convert return type
        ret_type = self._convert_type(self.return_type, module)
        
        # Convert parameter types - preserve type aliases in metadata
        param_types = []
        param_metadata = []
        for param in self.parameters:
            param_type = self._convert_type(param.type_spec, module)
            param_types.append(param_type)
            # Store original type information for later use
            if param.type_spec.custom_typename:
                param_metadata.append({
                    'name': param.name,
                    'original_type': param.type_spec.custom_typename,
                    'type_spec': param.type_spec
                })
            else:
                param_metadata.append({
                    'name': param.name,
                    'original_type': None,
                    'type_spec': param.type_spec
                })
        
        # Create function type
        func_type = ir.FunctionType(ret_type, param_types)
        
        # Check if function already exists (from prototype)
        if self.name in module.globals:
            existing = module.globals[self.name]
            if isinstance(existing, ir.Function):
                # Verify the signatures match
                if existing.ftype != func_type:
                    raise ValueError(f"Function '{self.name}' redefined with different signature\nExisting: {existing.ftype}\nNew: {func_type}")
                func = existing
            else:
                raise ValueError(f"Name '{self.name}' already used for non-function")
        else:
            # Create new function
            func = ir.Function(module, func_type, self.name)
        
        # Store parameter metadata on the function for later retrieval
        if not hasattr(module, '_function_param_metadata'):
            module._function_param_metadata = {}
        module._function_param_metadata[self.name] = param_metadata
        
        # Store return type metadata
        if not hasattr(module, '_function_return_metadata'):
            module._function_return_metadata = {}
        module._function_return_metadata[self.name] = {
            'original_type': self.return_type.custom_typename if self.return_type.custom_typename else None,
            'type_spec': self.return_type
        }
        
        if self.is_prototype == True:
            return func
        
        # Set parameter names
        for i, param in enumerate(func.args):
            param.name = self.parameters[i].name
        
        # Create entry block
        entry_block = func.append_basic_block('entry')
        builder.position_at_start(entry_block)
        
        # Create new scope for function body
        old_scope = builder.scope
        builder.scope = {}
        # Initialize union tracking for this function scope
        if not hasattr(builder, 'initialized_unions'):
            builder.initialized_unions = set()
        
        # Store parameter type information in scope metadata
        if not hasattr(builder, 'scope_type_info'):
            builder.scope_type_info = {}
        old_scope_type_info = builder.scope_type_info
        builder.scope_type_info = {}
        
        # Allocate space for parameters and store initial values WITH type information
        for i, param in enumerate(func.args):
            alloca = builder.alloca(param.type, name=f"{param.name}.addr")
            builder.store(param, alloca)
            builder.scope[self.parameters[i].name] = alloca
            # Store the original type spec for this parameter
            builder.scope_type_info[self.parameters[i].name] = self.parameters[i].type_spec
        
        # Generate function body
        self.body.codegen(builder, module)
        
        # Add implicit return if needed
        if not builder.block.is_terminated:
            if isinstance(ret_type, ir.VoidType):
                builder.ret_void()
            else:
                raise RuntimeError("Function must end with return statement")
        
        # Restore previous scope
        builder.scope = old_scope
        builder.scope_type_info = old_scope_type_info
        return func
    
    def _convert_type(self, type_spec: TypeSpec, module: ir.Module = None) -> ir.Type:
        # Use the proper method that handles arrays and pointers
        if module is None:
            module = ir.Module()
        return type_spec.get_llvm_type_with_array(module)

@dataclass
class FunctionPointer(ASTNode):
    pass

@dataclass
class DestructuringAssignment(Statement):
    """Destructuring assignment"""
    variables: List[Union[str, Tuple[str, TypeSpec]]]  # Can be simple names or (name, type) pairs
    source: Expression
    source_type: Optional[Identifier]  # For the "from" clause
    is_explicit: bool  # True if using "as" syntax

@dataclass
class UnionMember(ASTNode):
    name: str
    type_spec: TypeSpec
    initial_value: Optional[Expression] = None

@dataclass
class UnionDef(ASTNode):
    name: str
    members: List[UnionMember] = field(default_factory=list)
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Type:
        # First convert all member types to LLVM types
        member_types = []
        member_names = []
        max_size = 0
        max_type = None
        
        for member in self.members:
            member_type = member.type_spec.get_llvm_type(module)
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
        
        # Create a struct type with proper padding
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
            'max_size': max_size
        }
        
        return union_type


"""
Flux Struct Implementation according to struct_specification.md

This implements structs as type contracts with runtime-queryable vtables,
enabling zero-cost data reinterpretation through destructive casting.

Key concepts:
1. Struct declarations create vtables (metadata about memory layout)
2. Struct instances are pure data with no vtable pointers
3. Field access consults vtable at compile time
4. Casting between structs is zero-cost bitcast operation
"""

# Struct member
@dataclass
class StructMember(ASTNode):
    """
    Struct member with explicit type specification.
    
    Attributes:
        name: Member field name
        type_spec: Type specification (must include bit_width for data types)
        offset: Calculated bit offset in struct (set during vtable generation)
        is_private: Whether this is a private member
        initial_value: Optional initialization expression (not stored in vtable)
    """
    name: str
    type_spec: TypeSpec
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
        if isinstance(struct_type, ir.IntType):
            # Small struct - integer type
            instance = ir.Constant(struct_type, 0)
        else:
            # Large struct - array of bytes
            instance = ir.Constant(struct_type, [ir.Constant(ir.IntType(8), 0)] * vtable.total_bytes)
        
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
            instance = self._pack_field_value(
                builder, instance, field_value, 
                bit_offset, bit_width, vtable.total_bits
            )
        
        return instance
    
    def _pack_field_value(
        self, 
        builder: ir.IRBuilder, 
        instance: ir.Value,
        field_value: ir.Value,
        bit_offset: int,
        bit_width: int,
        total_bits: int
    ) -> ir.Value:
        """
        Pack a field value into the struct instance at the correct bit offset.
        
        This performs bit manipulation to insert the field value at the
        correct position in the packed struct.
        """
        if isinstance(instance.type, ir.IntType):
            # Integer type - use bit operations
            instance_type = instance.type
            
            # Convert field value to same width as instance for manipulation
            if field_value.type.width < instance_type.width:
                field_value_extended = builder.zext(field_value, instance_type)
            elif field_value.type.width > instance_type.width:
                field_value_extended = builder.trunc(field_value, instance_type)
            else:
                field_value_extended = field_value
            
            # Shift field value to correct position
            if bit_offset > 0:
                field_value_shifted = builder.shl(
                    field_value_extended,
                    ir.Constant(instance_type, bit_offset)
                )
            else:
                field_value_shifted = field_value_extended
            
            # Create mask to clear target bits in instance
            mask = ((1 << bit_width) - 1) << bit_offset
            clear_mask = (~mask) & ((1 << total_bits) - 1)
            
            # Clear target bits
            instance_cleared = builder.and_(
                instance,
                ir.Constant(instance_type, clear_mask)
            )
            
            # Insert field value
            result = builder.or_(instance_cleared, field_value_shifted)
            
            return result
        else:
            # Array type - byte-level manipulation
            # Calculate byte offset and bit offset within byte
            byte_offset = bit_offset // 8
            bit_in_byte = bit_offset % 8
            
            # For now, support only byte-aligned fields in array structs
            if bit_in_byte != 0 or bit_width % 8 != 0:
                raise NotImplementedError(
                    "Unaligned fields in large structs not yet supported"
                )
            
            # Insert bytes at correct position
            field_bytes = bit_width // 8
            
            # Extract bytes from field value
            for i in range(field_bytes):
                byte_val = builder.trunc(
                    builder.lshr(
                        field_value,
                        ir.Constant(field_value.type, i * 8)
                    ),
                    ir.IntType(8)
                )
                
                # Insert into array
                instance = builder.insert_value(
                    instance,
                    byte_val,
                    byte_offset + i
                )
            
            return instance

# Struct literal
@dataclass
class StructLiteral(Expression):
    """
    Struct literal for inline initialization.
    
    Syntax: (StructType){field1 = value1, field2 = value2}
    
    Examples:
        Data d = (Data){a = 10, b = 20};
        process((Data){a = 100, b = 200});
        d = (Data){a = 30, b = 40};  // Re-assign with new literal
    
    The struct type MUST be explicitly specified via cast syntax.
    No implicit type inference - this is explicit Flux style.
    """
    field_values: Dict[str, Expression]
    positional_values: Dict[str, Expression]
    struct_type: Optional[str] = None  # Set by CastExpression wrapper
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Generate packed struct literal.
        
        The struct type must be explicitly specified via cast before codegen.
        This should never be called directly - always wrapped in CastExpression.
        """
        if self.struct_type is None:
            raise ValueError(
                "Struct literal must be cast to a type: (StructType){fields...}"
            )
        
        # Create StructInstance with explicit type
        instance = StructInstance(self.struct_type, self.field_values)
        return instance.codegen(builder, module)

# Struct pointer vtable
@dataclass
class StructVTable:
    """
    Virtual table containing struct layout metadata.
    
    This is generated at compile time and stored as a global constant.
    It enables zero-cost struct reinterpretation and field access.
    
    Attributes:
        struct_name: Name of the struct
        total_bits: Total size in bits
        total_bytes: Total size in bytes (rounded up)
        alignment: Required alignment in bits
        fields: List of (name, offset, width, alignment) tuples
    """
    struct_name: str
    total_bits: int
    total_bytes: int
    alignment: int
    fields: List[Tuple[str, int, int, int]]  # (name, bit_offset, bit_width, alignment)
    
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
    Struct definition - creates a type contract (vtable).
    
    Unlike traditional structs, this does NOT allocate data.
    It creates compile-time metadata that describes memory layout.
    
    Actual struct instances are pure data with no overhead.
    """
    name: str
    members: List[StructMember] = field(default_factory=list)
    base_structs: List[str] = field(default_factory=list)
    nested_structs: List['StructDef'] = field(default_factory=list)
    vtable: Optional[StructVTable] = None  # Generated during codegen
    
    def calculate_vtable(self, module: ir.Module) -> StructVTable:
        """
        Calculate struct layout and generate vtable.
        
        This determines:
        - Bit offset for each field
        - Total struct size in bits
        - Required alignment
        
        Returns: StructVTable with all metadata
        """
        fields = []
        current_offset = 0
        max_alignment = 1
        
        for member in self.members:
            # Get member type information
            member_type = member.type_spec
            
            # Calculate bit width
            if member_type.bit_width is not None:
                bit_width = member_type.bit_width
                alignment = member_type.alignment or bit_width
            elif member_type.custom_typename:
                # Look up custom type in module's type table
                custom_type_info = self._get_custom_type_info(
                    member_type.custom_typename, module
                )
                bit_width = custom_type_info['bit_width']
                alignment = custom_type_info['alignment']
            else:
                # Built-in types
                bit_width = self._get_builtin_bit_width(member_type.base_type)
                alignment = bit_width
            
            # Handle alignment
            if alignment > 1:
                # Align current offset to alignment boundary
                misalignment = current_offset % alignment
                if misalignment != 0:
                    current_offset += alignment - misalignment
            
            # Record field metadata
            fields.append((member.name, current_offset, bit_width, alignment))
            member.offset = current_offset  # Store in member for later use
            
            # Advance offset
            current_offset += bit_width
            max_alignment = max(max_alignment, alignment)
        
        # Calculate total size
        total_bits = current_offset
        
        # Align total size to max alignment
        if max_alignment > 1:
            misalignment = total_bits % max_alignment
            if misalignment != 0:
                total_bits += max_alignment - misalignment
        
        total_bytes = (total_bits + 7) // 8  # Round up to bytes
        
        return StructVTable(
            struct_name=self.name,
            total_bits=total_bits,
            total_bytes=total_bytes,
            alignment=max_alignment,
            fields=fields
        )
    
    def _get_builtin_bit_width(self, base_type: DataType) -> int:
        """Get bit width for built-in types"""
        widths = {
            DataType.BOOL: 1,
            DataType.CHAR: 8,
            DataType.INT: 32,
            DataType.FLOAT: 32,
            DataType.VOID: 0
        }
        return widths.get(base_type, 32)
    
    def _get_custom_type_info(self, typename: str, module: ir.Module) -> Dict:
        """
        Look up custom type information from module's type registry.
        
        Returns: dict with 'bit_width' and 'alignment' keys
        """
        if not hasattr(module, '_custom_types'):
            raise NameError(f"Custom type '{typename}' not found")
        
        if typename not in module._custom_types:
            raise NameError(f"Custom type '{typename}' not defined")
        
        return module._custom_types[typename]
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Type:
        """
        Generate LLVM IR for struct definition.
        
        This creates:
        1. Global vtable constant with metadata
        2. Type alias for instances (raw bits)
        3. Helper functions for field access
        
        Returns: LLVM type representing struct instances (integer type)
        """
        # Calculate vtable
        self.vtable = self.calculate_vtable(module)
        
        # Generate vtable global constant
        vtable_constant = self.vtable.to_llvm_constant(module)
        vtable_global = ir.GlobalVariable(
            module,
            vtable_constant.type,
            name=f"{self.name}.vtable"
        )
        vtable_global.initializer = vtable_constant
        vtable_global.linkage = 'internal'
        vtable_global.global_constant = True
        
        # Create type alias for instances
        # Instances are just raw bits - represented as integer type
        if self.vtable.total_bits <= 64:
            # Small structs: use native integer type
            instance_type = ir.IntType(self.vtable.total_bits)
        else:
            # Large structs: use byte array
            instance_type = ir.ArrayType(ir.IntType(8), self.vtable.total_bytes)
        
        # Store type information in module
        if not hasattr(module, '_struct_types'):
            module._struct_types = {}
        if not hasattr(module, '_struct_vtables'):
            module._struct_vtables = {}
        
        module._struct_types[self.name] = instance_type
        module._struct_vtables[self.name] = self.vtable
        
        # Generate field access helpers
        self._generate_field_accessors(module, instance_type)
        
        # Process nested structs
        for nested in self.nested_structs:
            nested.codegen(builder, module)
        
        return instance_type
    
    def _generate_field_accessors(self, module: ir.Module, struct_type: ir.Type):
        """
        Store field access information in vtable.
        
        Field access is done inline at the call site, not via helper functions.
        The vtable metadata tells the compiler how to generate the correct
        bit manipulation code for each field access.
        
        This function just validates the layout - actual access code is
        generated on-demand when fields are accessed.
        """
        # No hidden functions generated - field access is always inline
        # The vtable is sufficient metadata for the compiler to generate
        # correct access code at each use site
        pass
    
    def _get_field_llvm_type(self, type_spec: TypeSpec, module: ir.Module) -> ir.Type:
        """Convert TypeSpec to LLVM type"""
        try:
            return type_spec.get_llvm_type(module)
        except:
            # Fallback for data types
            if type_spec.bit_width:
                return ir.IntType(type_spec.bit_width)
            return ir.IntType(32)

# ============================================================================
# Struct Operations
# ============================================================================

@dataclass
class StructFieldAccess(Expression):
    """
    Access a field from a struct instance.
    
    Syntax: instance.field_name
    
    This generates inline bit manipulation code to extract the field value
    from the packed struct data using vtable metadata.
    """
    struct_instance: Expression
    field_name: str
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Generate inline field access code.
        
        Uses vtable metadata to determine bit offset and generates
        the appropriate shift/mask operations inline.
        """
        # Get struct instance value
        instance = self.struct_instance.codegen(builder, module)
        
        # Determine struct type from instance
        # For now, we need the struct name - this should be tracked in type system
        # TODO: Add type tracking to expressions
        struct_name = self._infer_struct_name(instance, module)
        
        # Get vtable
        vtable = module._struct_vtables.get(struct_name)
        if not vtable:
            raise ValueError(f"Cannot determine struct type for field access")
        
        # Find field in vtable
        field_info = next(
            (f for f in vtable.fields if f[0] == self.field_name),
            None
        )
        if not field_info:
            raise ValueError(f"Field '{self.field_name}' not found in struct '{struct_name}'")
        
        _, bit_offset, bit_width, alignment = field_info
        
        # Generate inline extraction code
        if isinstance(instance.type, ir.IntType):
            # Integer type - simple bit operations
            instance_type = instance.type
            
            # Shift to position
            if bit_offset > 0:
                shifted = builder.lshr(
                    instance,
                    ir.Constant(instance_type, bit_offset)
                )
            else:
                shifted = instance
            
            # Mask to field width
            mask = (1 << bit_width) - 1
            masked = builder.and_(
                shifted,
                ir.Constant(instance_type, mask)
            )
            
            # Truncate to field width if needed
            field_type = ir.IntType(bit_width)
            if instance_type.width != bit_width:
                result = builder.trunc(masked, field_type)
            else:
                result = masked
            
            return result
        else:
            # Array type - byte extraction
            byte_offset = bit_offset // 8
            bit_in_byte = bit_offset % 8
            
            if bit_in_byte == 0 and bit_width % 8 == 0:
                # Byte-aligned - simple extraction
                field_bytes = bit_width // 8
                field_type = ir.IntType(bit_width)
                
                # Extract bytes and combine
                result = ir.Constant(field_type, 0)
                for i in range(field_bytes):
                    byte_val = builder.extract_value(instance, byte_offset + i)
                    byte_extended = builder.zext(byte_val, field_type)
                    byte_shifted = builder.shl(
                        byte_extended,
                        ir.Constant(field_type, i * 8)
                    )
                    result = builder.or_(result, byte_shifted)
                
                return result
            else:
                # Unaligned - complex bit manipulation
                raise NotImplementedError(
                    "Unaligned field access in large structs not yet supported"
                )
    
    def _infer_struct_name(self, instance: ir.Value, module: ir.Module) -> str:
        """
        Infer struct name from instance type.
        
        TODO: This should be tracked in the type system properly.
        For now, we match by type equality.
        """
        if not hasattr(module, '_struct_types'):
            raise ValueError("No struct types defined")
        
        for struct_name, struct_type in module._struct_types.items():
            if instance.type == struct_type:
                return struct_name
        
        raise ValueError("Cannot determine struct type from instance")

@dataclass
class StructFieldAssign(Statement):
    """
    Assign a value to a struct field.
    
    Syntax: instance.field_name = value;
    
    Generates inline bit manipulation to update the field in place.
    """
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
        
        # Load current value
        instance = builder.load(instance_ptr)
        
        # Get struct type
        struct_name = self._infer_struct_name(instance, module)
        vtable = module._struct_vtables[struct_name]
        
        # Find field
        field_info = next(
            (f for f in vtable.fields if f[0] == self.field_name),
            None
        )
        if not field_info:
            raise ValueError(f"Field '{self.field_name}' not found")
        
        _, bit_offset, bit_width, alignment = field_info
        
        # Generate new value
        new_value = self.value.codegen(builder, module)
        
        # Pack new value into instance
        if isinstance(instance.type, ir.IntType):
            instance_type = instance.type
            
            # Extend/truncate new value to instance width
            if new_value.type.width < instance_type.width:
                new_value_extended = builder.zext(new_value, instance_type)
            elif new_value.type.width > instance_type.width:
                new_value_extended = builder.trunc(new_value, instance_type)
            else:
                new_value_extended = new_value
            
            # Shift to position
            if bit_offset > 0:
                new_value_shifted = builder.shl(
                    new_value_extended,
                    ir.Constant(instance_type, bit_offset)
                )
            else:
                new_value_shifted = new_value_extended
            
            # Create clear mask
            mask = ((1 << bit_width) - 1) << bit_offset
            clear_mask = (~mask) & ((1 << vtable.total_bits) - 1)
            
            # Clear old value
            instance_cleared = builder.and_(
                instance,
                ir.Constant(instance_type, clear_mask)
            )
            
            # Insert new value
            updated_instance = builder.or_(instance_cleared, new_value_shifted)
            
            # Store back
            builder.store(updated_instance, instance_ptr)
            
            return updated_instance
        else:
            raise NotImplementedError(
                "Field assignment in large structs not yet supported"
            )
    
    def _infer_struct_name(self, instance: ir.Value, module: ir.Module) -> str:
        """Infer struct name from instance type"""
        if not hasattr(module, '_struct_types'):
            raise ValueError("No struct types defined")
        
        for struct_name, struct_type in module._struct_types.items():
            if instance.type == struct_type:
                return struct_name
        
        raise ValueError("Cannot determine struct type from instance")

@dataclass
class StructRecast(Expression):
    """
    Zero-cost struct reinterpretation cast.
    
    Syntax: (TargetStruct)source_data
    
    This performs:
    1. Runtime size check (can be optimized away if sizes known)
    2. Bitcast pointer (zero cost)
    3. No data movement or copying
    """
    target_type: str  # Struct type name
    source_expr: Expression
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """
        Generate zero-cost reinterpret cast.
        
        Size checking is done at compile time when possible.
        If sizes don't match at compile time, it's a compilation error.
        Runtime size checks only occur for dynamic arrays.
        Invalid casts result in undefined behavior (programmer's responsibility).
        """
        # Get target struct vtable
        if not hasattr(module, '_struct_vtables'):
            raise ValueError(f"Struct '{self.target_type}' not defined")
        
        target_vtable = module._struct_vtables.get(self.target_type)
        if not target_vtable:
            raise ValueError(f"Struct '{self.target_type}' not defined")
        
        # Get source value
        source_value = self.source_expr.codegen(builder, module)
        target_type = module._struct_types[self.target_type]
        
        # Compile-time size check if source size is known
        if hasattr(source_value.type, 'count'):
            # Array type - check size at compile time
            source_bytes = source_value.type.count
            if source_bytes != target_vtable.total_bytes:
                raise ValueError(
                    f"Size mismatch in cast to {self.target_type}: "
                    f"source is {source_bytes} bytes, target requires {target_vtable.total_bytes} bytes"
                )
        
        # Perform zero-cost bitcast
        if isinstance(source_value.type, ir.PointerType):
            # Cast pointer, then load
            casted_ptr = builder.bitcast(source_value, target_type.as_pointer())
            result = builder.load(casted_ptr)
        else:
            # Direct bitcast (reinterpret bits)
            # This is a no-op in machine code
            result = builder.bitcast(source_value, target_type)
        
        return result

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
    return_type: TypeSpec
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
        print(f"[codegen] Processing object: {self.name}")
        # First create a struct type for the object's data members
        member_types = []
        member_names = []
        
        for member in self.members:
            member_type = self._convert_type(member.type_spec, module)
            member_types.append(member_type)
            member_names.append(member.name)
        
        print(f"[codegen] Object {self.name} has {len(member_types)} members")
        # Create the struct type for data members
        struct_type = ir.global_context.get_identified_type(self.name)
        struct_type.set_body(*member_types)
        struct_type.names = member_names
        
        # Store the struct type in the module
        if not hasattr(module, '_struct_types'):
            module._struct_types = {}
        module._struct_types[self.name] = struct_type
        
        print(f"[codegen] Created struct type for {self.name}: {struct_type}")
        # Create methods as functions with 'this' parameter
        for method in self.methods:
            print(f"[codegen] Processing method: {method.name}")
            # Convert return type
            if method.return_type.base_type == DataType.THIS:
                ret_type = ir.PointerType(struct_type)
            else:
                ret_type = self._convert_type(method.return_type, module)
            
            print(f"[codegen] Method {method.name} return type: {ret_type}")
            # Create parameter types - first parameter is always 'this' pointer
            param_types = [ir.PointerType(struct_type)]
            
            # Add other parameters
            param_types.extend([self._convert_type(param.type_spec, module) for param in method.parameters])
            
            # Create function type
            func_type = ir.FunctionType(ret_type, param_types)
            
            print(f"[codegen] Method {method.name} function type: {func_type}")
            # Create function with mangled name
            func_name = f"{self.name}.{method.name}"
            func = ir.Function(module, func_type, func_name)
            
            # Set parameter names
            func.args[0].name = "this"  # First arg is 'this' pointer
            for i, param in enumerate(func.args[1:], 1):
                param.name = method.parameters[i-1].name
            
            # If it's a prototype, we're done
            if isinstance(method, FunctionDef) and method.is_prototype:
                continue
            
            # Create entry block
            entry_block = func.append_basic_block('entry')
            method_builder = ir.IRBuilder(entry_block)
            
            # Create scope for method
            method_builder.scope = {}
            
            # Store parameters in scope
            for i, param in enumerate(func.args):
                if i == 0:  # 'this' pointer - store the parameter directly, not an alloca
                    # The 'this' pointer is already a pointer to the struct, we don't need to
                    # allocate storage for it since we just need to access its members
                    method_builder.scope["this"] = param
                else:
                    # For other parameters, create alloca as usual
                    alloca = method_builder.alloca(param.type, name=f"{param.name}.addr")
                    method_builder.store(param, alloca)
                    method_builder.scope[method.parameters[i-1].name] = alloca
            
            # Generate method body
            if isinstance(method, FunctionDef):
                # Generate normal body for all methods, including __init
                method.body.codegen(method_builder, module)
                # For __init__, add return 'this' pointer after body if not already terminated
                if method.name == '__init' and not method_builder.block.is_terminated:
                    method_builder.ret(func.args[0])
            else:
                method.body.codegen(method_builder, module)
            
            # Add implicit return if needed
            if not method_builder.block.is_terminated:
                if isinstance(ret_type, ir.VoidType):
                    method_builder.ret_void()
                else:
                    raise RuntimeError(f"Method {method.name} must end with return statement")
        
        # Handle nested objects and structs
        for nested_obj in self.nested_objects:
            nested_obj.codegen(builder, module)
        
        for nested_struct in self.nested_structs:
            nested_struct.codegen(builder, module)
        
        return struct_type

    def _convert_type(self, type_spec: TypeSpec, module: ir.Module) -> ir.Type:
        # Use the comprehensive get_llvm_type_with_array method that handles all cases properly
        return type_spec.get_llvm_type_with_array(module)

# Namespace definition
@dataclass
class NamespaceDef(ASTNode):
    name: str
    functions: List[FunctionDef] = field(default_factory=list)
    structs: List[StructDef] = field(default_factory=list)
    objects: List[ObjectDef] = field(default_factory=list)
    variables: List[VariableDeclaration] = field(default_factory=list)
    nested_namespaces: List['NamespaceDef'] = field(default_factory=list)
    base_namespaces: List[str] = field(default_factory=list)  # inheritance

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> None:
        """
        Generate LLVM IR for a namespace definition.
        
        Namespaces in Flux are primarily a compile-time construct that affects name mangling.
        At the LLVM level, we'll mangle names with the namespace prefix.
        """
        # Register this namespace so using statements can reference it
        if not hasattr(module, '_namespaces'):
            module._namespaces = set()
        module._namespaces.add(self.name)
        
        # Also register nested namespaces with their full qualified names
        for nested_ns in self.nested_namespaces:
            full_nested_name = f"{self.name}::{nested_ns.name}"
            module._namespaces.add(full_nested_name)
            # Recursively register deeper nested namespaces
            self._register_nested_namespaces(nested_ns, full_nested_name, module)
        
        # Enable type resolution within this namespace by adding it to _using_namespaces
        if not hasattr(module, '_using_namespaces'):
            module._using_namespaces = []
        # Add the current namespace to the using list so types defined in this namespace
        # can reference each other (like 'byte' can be found when defining 'noopstr')
        old_using_namespaces = module._using_namespaces[:]
        if self.name not in module._using_namespaces:
            module._using_namespaces.append(self.name)
        
        # Save the current module state
        old_module = module
        
        # Create a new module for the namespace if we want isolation
        # Alternatively, we can just mangle names in the existing module
        # For now, we'll use name mangling in the existing module
        
        try:
            # Process all namespace members with name mangling
            for struct in self.structs:
                # Mangle the struct name with namespace
                original_name = struct.name
                struct.name = f"{self.name}__{struct.name}"
                struct.codegen(builder, module)
                struct.name = original_name  # Restore original name
            
            for obj in self.objects:
                # Mangle the object name with namespace
                original_name = obj.name
                obj.name = f"{self.name}__{obj.name}"
                obj.codegen(builder, module)
                obj.name = original_name
            
            for func in self.functions:
                # Mangle the function name with namespace
                original_name = func.name
                func.name = f"{self.name}__{func.name}"
                func.codegen(builder, module)
                func.name = original_name
            
            for var in self.variables:
                # Mangle the variable name with namespace
                original_name = var.name
                var.name = f"{self.name}__{var.name}"
                var.codegen(builder, module)
                var.name = original_name
            
            # Process nested namespaces
            for nested_ns in self.nested_namespaces:
                # Mangle the nested namespace name
                original_name = nested_ns.name
                nested_ns.name = f"{self.name}__{nested_ns.name}"
                nested_ns.codegen(builder, module)
                nested_ns.name = original_name
            
            # Handle inheritance here
        finally:
            # Restore original using namespaces list to avoid namespace pollution
            module._using_namespaces = old_using_namespaces
        
        return None
    
    def _register_nested_namespaces(self, namespace, parent_path, module):
        """Recursively register all nested namespaces with their full qualified names"""
        for nested_ns in namespace.nested_namespaces:
            full_nested_name = f"{parent_path}::{nested_ns.name}"
            module._namespaces.add(full_nested_name)
            self._register_nested_namespaces(nested_ns, full_nested_name, module)

# Import statement
@dataclass
class UsingStatement(Statement):
    namespace_path: str  # e.g., "standard::io"
    
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> None:
        """Using statements are compile-time directives - no runtime code generated"""
        # For now, just store the namespace information for symbol resolution
        if not hasattr(module, '_using_namespaces'):
            module._using_namespaces = []
        module._using_namespaces.append(self.namespace_path)

@dataclass
class ImportStatement(Statement):
    module_name: str
    _processed_imports: ClassVar[dict] = {}

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> None:
        """
        Fully implements Flux import semantics with proper AST code generation.
        Handles circular imports, maintains context, and properly processes all declarations.
        """
        resolved_path = self._resolve_path(self.module_name)
        if not resolved_path:
            raise ImportError(f"Module not found: {self.module_name}")

        # Skip if already processed (but reuse the existing module)
        if str(resolved_path) in self._processed_imports:
            return

        # Mark as processing to detect circular imports
        self._processed_imports[str(resolved_path)] = None

        try:
            with open(resolved_path, 'r', encoding='utf-8') as f:
                source = f.read()

            # Create fresh parser/lexer instances
            from flexer import FluxLexer
            tokens = FluxLexer(source).tokenize()
            
            # Get parser class without circular import
            parser_class = self._get_parser_class()
            imported_ast = parser_class(tokens).parse()

            # Create a new builder for the imported file
            import_builder = ir.IRBuilder()
            import_builder.scope = builder.scope  # Share the same scope
            
            # Generate code for each statement
            for stmt in imported_ast.statements:
                if isinstance(stmt, ImportStatement):
                    stmt.codegen(import_builder, module)
                else:
                    try:
                        stmt.codegen(import_builder, module)
                    except Exception as e:
                        raise RuntimeError(
                            f"Failed to generate code for {resolved_path}: {str(e)}"
                        ) from e

            # Store the processed module
            self._processed_imports[str(resolved_path)] = module

        except Exception as e:
            # Clean up failed import
            if str(resolved_path) in self._processed_imports:
                del self._processed_imports[str(resolved_path)]
            raise

    def _get_parser_class(self):
        """Dynamically imports the parser class to avoid circular imports"""
        import fparser
        return fparser.FluxParser

    def _resolve_path(self, module_name: str) -> Optional[Path]:
        """Robust path resolution with proper error handling"""
        try:
            # Check direct path first
            if (path := Path(module_name)).exists():
                return path.resolve()

            # Check in standard locations
            search_paths = [
                Path.cwd(),
                Path.cwd() / "src/stdlib",
                Path.cwd() / "src/stdlib/runtime",
                Path(__file__).parent.parent / "stdlib",
                Path.home() / ".flux" / "stdlib",
                Path("/usr/local/flux/stdlib/"),
                Path("/usr/flux/stdlib")
            ]

            for path in search_paths:
                if (full_path := path / module_name).exists():
                    return full_path.resolve()

            return None
        except (TypeError, OSError) as e:
            raise ImportError(f"Invalid path resolution for {module_name}: {str(e)}")

# Custom type definition
@dataclass
class CustomTypeStatement(Statement):
    name: str
    type_spec: TypeSpec

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
    statements: List[Statement] = field(default_factory=list)

    def codegen(self, module: ir.Module = None) -> ir.Module:
        if module is None:
            module = ir.Module(name='flux_module')
        
        # Create global builder with no function context
        builder = ir.IRBuilder()
        builder.scope = None  # Indicates global scope
        # Track initialized unions for immutability enforcement
        builder.initialized_unions = set()
        
        # Process all statements
        for stmt in self.statements:
            try:
                stmt.codegen(builder, module)
            except Exception as e:
                print(f"Error generating code for statement: {stmt}")
                raise
        
        return module

# Example usage
if __name__ == "__main__":
    # Create a simple program AST
    main_func = FunctionDef(
        name="main",
        parameters=[],
        return_type=TypeSpec(base_type=DataType.INT),
        body=Block([
            ReturnStatement(Literal(0, DataType.INT))
        ])
    )
    
    program = Program(
        statements=[
            ImportStatement("standard.fx"),
            FunctionDefStatement(main_func)
        ]
    )
    
    print("AST created successfully!")
    print(f"Program has {len(program.statements)} statements")
    print(f"Main function has {len(main_func.body.statements)} statements")