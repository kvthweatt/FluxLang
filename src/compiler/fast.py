#!/usr/bin/env python3
"""
Flux Abstract Syntax Tree

Copyright (C) 2025 Karac Thweatt

Contributors:

    Piotr Bednarski
"""

from dataclasses import dataclass, field
from typing import List, Any, Optional, Union, Tuple, ClassVar
from enum import Enum
from llvmlite import ir
from pathlib import Path
import os

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

class Operator(Enum):
    ADD = "+"
    SUB = "-"
    MUL = "*"
    DIV = "/"
    MOD = "%"
    EQUAL = "=="
    NOT_EQUAL = "!="
    LESS_THAN = "<"
    LESS_EQUAL = "<="
    GREATER_THAN = ">"
    GREATER_EQUAL = ">="
    AND = "and"
    OR = "or"
    NOT = "not"
    XOR = "xor"
    BITSHIFT_LEFT = "<<"
    BITSHIFT_RIGHT = ">>"
    INCREMENT = "++"
    DECREMENT = "--"

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
        
        # For now, we need to determine the struct type from context
        # In a complete implementation, this would be resolved during semantic analysis
        # For testing purposes, let's assume we can infer from the fields present
        
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
        
        # Allocate space for the struct instance
        if builder.scope is None:
            # Global context - create a struct constant
            # Generate constant values for each field
            field_values = []
            for member_name in struct_type.names:
                if member_name in self.value:
                    # Field is initialized in the literal
                    field_expr = self.value[member_name]
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
                
                # Generate value and store it
                field_value = field_value_expr.codegen(builder, module)
                
                # Get the expected field type
                expected_type = struct_type.elements[field_index]
                
                # Convert field value to match the expected type if needed
                if field_value.type != expected_type:
                    if isinstance(field_value.type, ir.IntType) and isinstance(expected_type, ir.IntType):
                        if field_value.type.width > expected_type.width:
                            # Truncate to smaller type
                            field_value = builder.trunc(field_value, expected_type)
                        elif field_value.type.width < expected_type.width:
                            # Extend to larger type
                            field_value = builder.sext(field_value, expected_type)
                    # Add other type conversions as needed
                    elif isinstance(field_value.type, ir.IntType) and isinstance(expected_type, ir.FloatType):
                        field_value = builder.sitofp(field_value, expected_type)
                    elif isinstance(field_value.type, ir.FloatType) and isinstance(expected_type, ir.IntType):
                        field_value = builder.fptosi(field_value, expected_type)
                
                builder.store(field_value, field_ptr)
            
            # Return the initialized struct (load it to get the value)
            return builder.load(struct_ptr, name="struct_value")

@dataclass
class Identifier(ASTNode):
    name: str

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Look up the name in the current scope
        if builder.scope is not None and self.name in builder.scope:
            ptr = builder.scope[self.name]
            if self.name == "this":
                return ptr
            # For arrays, return the pointer directly (don't load)
            if isinstance(ptr.type, ir.PointerType) and isinstance(ptr.type.pointee, ir.ArrayType):
                return ptr
            # Load the value if it's a non-array pointer type
            elif isinstance(ptr.type, ir.PointerType):
                ret_val = builder.load(ptr, name=self.name)
                if hasattr(builder, 'volatile_vars') and self.name in builder.volatile_vars:
                    ret_val.volatile = True
                # Do not dereference regular pointers (char*, byte*, etc.)
                return ret_val
            return ptr
        
        # Check for global variables
        if self.name in module.globals:
            gvar = module.globals[self.name]
            # For arrays, return the pointer directly (don't load)
            if isinstance(gvar.type, ir.PointerType) and isinstance(gvar.type.pointee, ir.ArrayType):
                return gvar
            # Load the value if it's a non-array pointer type
            elif isinstance(gvar.type, ir.PointerType):
                ret_val = builder.load(gvar, name=self.name)
                if hasattr(builder, 'volatile_vars') and self.name in getattr(builder,'volatile_vars',set()):
                    ret_val.volatile = True
                return ret_val
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
                    # For arrays, return the pointer directly (don't load)
                    if isinstance(gvar.type, ir.PointerType) and isinstance(gvar.type.pointee, ir.ArrayType):
                        return gvar
                    # Load the value if it's a non-array pointer type
                    elif isinstance(gvar.type, ir.PointerType):
                        ret_val = builder.load(gvar, name=self.name)
                        if hasattr(builder, 'volatile_vars') and self.name in getattr(builder,'volatile_vars',set()):
                            ret_val.volatile = True
                        return ret_val
                    return gvar
                
                # Check in type aliases with mangled name
                if hasattr(module, '_type_aliases') and mangled_name in module._type_aliases:
                    return module._type_aliases[mangled_name]
            
        raise NameError(f"Unknown identifier: {self.name}")

# Type definitions
@dataclass
class TypeSpec(ASTNode):
    base_type: Union[DataType, str]  # Can be DataType enum or custom type name
    is_signed: bool = True
    is_const: bool = False
    is_volatile: bool = False
    bit_width: Optional[int] = None
    alignment: Optional[int] = None
    is_array: bool = False
    array_size: Optional[int] = None
    is_pointer: bool = False


    def get_llvm_type(self, module: ir.Module) -> ir.Type:  # Renamed from get_llvm_type
        if isinstance(self.base_type, str):
            #print(f"DEBUG get_llvm_type: Resolving base_type='{self.base_type}'")
            # Check for struct types first
            if hasattr(module, '_struct_types') and self.base_type in module._struct_types:
                #print(f"DEBUG get_llvm_type: Found struct type {self.base_type}")
                return module._struct_types[self.base_type]
            # Check for union types
            if hasattr(module, '_union_types') and self.base_type in module._union_types:
                #print(f"DEBUG get_llvm_type: Found union type {self.base_type}")
                return module._union_types[self.base_type]
            # Handle custom types (like i64)
            if hasattr(module, '_type_aliases') and self.base_type in module._type_aliases:
                alias_type = module._type_aliases[self.base_type]
                #print(f"DEBUG get_llvm_type: Found direct type alias {self.base_type} -> {alias_type}")
                # Return the alias type as-is (for noopstr -> i8*, we want i8*, not i8)
                return alias_type
            
            # Check for namespace-qualified names using 'using' statements
            if hasattr(module, '_using_namespaces'):
                #print(f"DEBUG get_llvm_type: Checking namespaces for '{self.base_type}'")
                #print(f"DEBUG get_llvm_type: Available namespaces: {module._using_namespaces}")
                
                # Check ALL possible mangled names that could exist
                #print(f"DEBUG get_llvm_type: Available type aliases: {list(module._type_aliases.keys()) if hasattr(module, '_type_aliases') else 'None'}")
                
                for namespace in module._using_namespaces:
                    # Convert namespace path to mangled name format
                    mangled_prefix = namespace.replace('::', '__') + '__'
                    mangled_name = mangled_prefix + self.base_type
                    #print(f"DEBUG get_llvm_type: Checking mangled name '{mangled_name}' in namespace '{namespace}'")
                    
                    # Check in type aliases with mangled name
                    if hasattr(module, '_type_aliases') and mangled_name in module._type_aliases:
                        alias_type = module._type_aliases[mangled_name]
                        #print(f"DEBUG get_llvm_type: Found namespace type alias {mangled_name} -> {alias_type}")
                        # Return the alias type as-is
                        return alias_type
                
                # FORCE CHECK: Look for any type alias that ends with our type name
                # This handles cases where the namespace processing order causes issues
                if hasattr(module, '_type_aliases'):
                    for alias_name, alias_type in module._type_aliases.items():
                        # Check if this alias ends with our type name (e.g., 'standard__types__byte' ends with 'byte')
                        if alias_name.endswith('__' + self.base_type):
                            # Extract the namespace part to verify it's in our using list
                            namespace_part = alias_name[:-len('__' + self.base_type)]
                            # Convert back to namespace format (e.g., 'standard__types' -> 'standard::types')
                            namespace_name = namespace_part.replace('__', '::')
                            #print(f"DEBUG get_llvm_type: Found potential match {alias_name} for namespace {namespace_name}")
                            # Check if this namespace is in our using list
                            if namespace_name in module._using_namespaces:
                                #print(f"DEBUG get_llvm_type: Using forced match {alias_name} -> {alias_type}")
                                return alias_type
            #else:
                #print(f"DEBUG get_llvm_type: No _using_namespaces found on module")
            
            #print(f"DEBUG get_llvm_type: No alias found for '{self.base_type}'")
            raise NameError(f"Unknown type: {self.base_type}")
        
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
            if self.bit_width is not None:
                return ir.IntType(self.bit_width)
            else:
                # If bit_width is None, this should not happen for properly resolved DATA types
                raise ValueError(f"DATA type missing bit_width for {self}")
        else:
            raise ValueError(f"Unsupported type: {self.base_type}")
    
    def get_llvm_type_with_array(self, module: ir.Module) -> ir.Type:
        """Get LLVM type with array support"""
        base_type = self.get_llvm_type(module)
        
        if self.is_array:
            if self.array_size is not None:
                return ir.ArrayType(base_type, self.array_size)
            else:
                # For unsized arrays (like byte[]), treat as pointer type
                return ir.PointerType(base_type)
        elif self.is_pointer:
            return ir.PointerType(base_type)
        else:
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
        zero = ir.Constant(ir.IntType(32), 0)
        ptr = builder.gep(gv, [zero, zero], name=f"{name_hint}_str_ptr")
        # Mark as array pointer for downstream logic that preserves array semantics
        ptr.type._is_array_pointer = True
        return ptr

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        # Attempt to promote string literals to array pointers when using + or - for concatenation
        left_expr, right_expr = self.left, self.right
        left_val = None
        right_val = None
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
            zero = ir.Constant(ir.IntType(32), 0)
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
    target_type: TypeSpec
    expression: Expression

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        """Generate code for cast expressions, including zero-cost struct reinterpretation and void casting"""
        target_llvm_type = self.target_type.get_llvm_type(module)
        
        # Handle void casting - frees memory according to Flux specification
        if isinstance(target_llvm_type, ir.VoidType):
            return self._handle_void_cast(builder, module)
        
        source_val = self.expression.codegen(builder, module)
        
        # If source and target are the same type, no cast needed
        if source_val.type == target_llvm_type:
            return source_val
        
        # Handle struct-to-struct reinterpretation (zero-cost when sizes match)
        if (isinstance(source_val.type, ir.PointerType) and 
            isinstance(source_val.type.pointee, ir.LiteralStructType) and
            isinstance(target_llvm_type, ir.LiteralStructType)):
            
            source_struct_type = source_val.type.pointee
            target_struct_type = target_llvm_type
            
            # Check if sizes are compatible (same total bytes)
            # Calculate size by summing element bit widths
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
        
        # Handle value-to-struct cast (load from pointer if needed)
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
        elif isinstance(source_val.type, ir.IntType) and isinstance(target_llvm_type, ir.FloatType):
            return builder.sitofp(source_val, target_llvm_type)
        
        # Handle float to int
        elif isinstance(source_val.type, ir.FloatType) and isinstance(target_llvm_type, ir.IntType):
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
            # In this case, we need to get the original struct pointer
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
        # According to Flux specification:
        # - Casting anything to void immediately frees the memory occupied by that thing
        # - This works for both stack and heap allocated items
        # - (void) is essentially "free this memory now" no matter where it is
        # - After void casting, the variable becomes unusable (use-after-free)
        # - This is a RUNTIME operation that generates actual free() calls
        #
        # NOTE: We DO NOT remove variables from scope at compile-time to allow
        # testing of runtime crashes. The free() call will happen at runtime,
        # and subsequent use will cause crashes as intended.
        
        if isinstance(self.expression, Identifier):
            # This is a variable being cast to void - free it immediately at runtime
            var_name = self.expression.name
            
            if builder.scope is not None and var_name in builder.scope:
                # Local variable - generate runtime free call
                var_ptr = builder.scope[var_name]
                
                # Generate runtime free call
                self._generate_runtime_free(builder, module, var_ptr, var_name)
                
                # Remove from scope - variable becomes unusable at compile-time AND runtime
                del builder.scope[var_name]  # RE-ENABLED: compile-time + runtime checking
                
            elif var_name in module.globals:
                # Global variable - generate runtime free call
                gvar = module.globals[var_name]
                self._generate_runtime_free(builder, module, gvar, var_name)
                # Note: We can't remove globals from the symbol table, but the memory is freed
            else:
                raise NameError(f"Cannot void cast unknown variable: {var_name}")
        else:
            # For expressions (not simple variables), generate the value and try to free it
            expr_val = self.expression.codegen(builder, module)
            if isinstance(expr_val.type, ir.PointerType):
                # This is a pointer expression - we can free it
                self._generate_runtime_free(builder, module, expr_val, "<expression>")
            # For non-pointer expressions, there's nothing to free
        
        # Void casting doesn't return a value (returns void)
        # In LLVM IR, we represent this as returning None
        return None
    
    def _generate_runtime_free(self, builder: ir.IRBuilder, module: ir.Module, ptr_value: ir.Value, var_name: str) -> None:
        """Generate runtime free() call for the given pointer value"""
        # Only generate runtime free() calls - no compile-time optimizations
        # This ensures we can test the actual runtime behavior and crashes
        
        # Declare free() function if not already declared
        free_func = module.globals.get('free')
        if free_func is None:
            # Create free() function signature: void free(void* ptr)
            free_type = ir.FunctionType(
                ir.VoidType(),  # void return
                [ir.PointerType(ir.IntType(8))]  # void* parameter
            )
            free_func = ir.Function(module, free_type, 'free')
            # Mark as external function to prevent optimization
            free_func.linkage = 'external'
        
        # Force runtime execution by making the free call volatile/unoptimizable
        if isinstance(ptr_value.type, ir.PointerType):
            if isinstance(ptr_value.type.pointee, ir.PointerType):
                # This is a pointer to a pointer (e.g., char** or noopstr)
                # Load the actual pointer value and free that
                actual_ptr = builder.load(ptr_value, name=f"{var_name}_ptr_load")
                # Mark the load as volatile to prevent optimization
                actual_ptr.volatile = True
                # Cast to void* (i8*) for free()
                void_ptr = builder.bitcast(actual_ptr, ir.PointerType(ir.IntType(8)), name=f"{var_name}_void_ptr")
                # Generate the free() call - this will definitely happen at runtime
                free_call = builder.call(free_func, [void_ptr])
                # Mark call as having side effects to prevent elimination
                free_call.tail = False
            elif isinstance(ptr_value.type.pointee, ir.ArrayType):
                # This is a pointer to an array (stack allocated)
                # Calling free() on stack memory will cause undefined behavior/crash - perfect for testing
                void_ptr = builder.bitcast(ptr_value, ir.PointerType(ir.IntType(8)), name=f"{var_name}_void_ptr")
                free_call = builder.call(free_func, [void_ptr])
                free_call.tail = False
            else:
                # This is a pointer to a regular value type
                # Cast to void* (i8*) for free()
                void_ptr = builder.bitcast(ptr_value, ir.PointerType(ir.IntType(8)), name=f"{var_name}_void_ptr")
                free_call = builder.call(free_func, [void_ptr])
                free_call.tail = False
        else:
            # This is not a pointer - nothing to free
            pass

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
        
        #print(f"DEBUG FunctionCall: Calling {self.name} with {len(self.arguments)} arguments")
        #print(f"DEBUG FunctionCall: Function signature: {func.type}")
        
        # Generate code for arguments
        arg_vals = []
        for i, arg in enumerate(self.arguments):
            #print(f"DEBUG FunctionCall: Processing arg {i}: {type(arg).__name__} = {arg}")
            #print(f"DEBUG FunctionCall: arg.type = {getattr(arg, 'type', None)}")
            param_index = i + parameter_offset  # Adjust index for method calls
            #if param_index < len(func.args):
                #print(f"DEBUG FunctionCall: func.args[{param_index}].type = {func.args[param_index].type}")
                
            # Check if this is a string literal that needs to be converted to pointer
            #print(f"DEBUG: Checking string literal conversion for arg {i} (param_index {param_index}):")
            #print(f"DEBUG:   isinstance(arg, Literal) = {isinstance(arg, Literal)}")
            #if isinstance(arg, Literal):
                #print(f"DEBUG:   arg.type == DataType.CHAR = {arg.type == DataType.CHAR}")
            #print(f"DEBUG:   param_index < len(func.args) = {param_index < len(func.args)}")
            #if param_index < len(func.args):
                #print(f"DEBUG:   func.args[{param_index}].type = {func.args[param_index].type}")
                #print(f"DEBUG:   isinstance(func.args[{param_index}].type, ir.PointerType) = {isinstance(func.args[param_index].type, ir.PointerType)}")
                #if isinstance(func.args[param_index].type, ir.PointerType):
                    #print(f"DEBUG:   isinstance(func.args[{param_index}].type.pointee, ir.IntType) = {isinstance(func.args[param_index].type.pointee, ir.IntType)}")
                    #if isinstance(func.args[param_index].type.pointee, ir.IntType):
                        #print(f"DEBUG:   func.args[{param_index}].type.pointee.width == 8 = {func.args[param_index].type.pointee.width == 8}")
                        
            if (isinstance(arg, Literal) and arg.type == DataType.CHAR and 
                param_index < len(func.args) and isinstance(func.args[param_index].type, ir.PointerType) and 
                isinstance(func.args[param_index].type.pointee, ir.IntType) and func.args[param_index].type.pointee.width == 8):
                # This is a string literal being passed to a function expecting i8*
                # Create a global string constant and return pointer to it
                string_val = arg.value
                string_bytes = string_val.encode('ascii')
                str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
                str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
                
                # Create global variable for the string
                gv = ir.GlobalVariable(module, str_val.type, name=f".str.arg{i}")
                gv.linkage = 'internal'
                gv.global_constant = True
                gv.initializer = str_val
                
                # Get pointer to the first character of the string
                zero = ir.Constant(ir.IntType(32), 0)
                str_ptr = builder.gep(gv, [zero, zero], name=f"arg{i}_str_ptr")
                arg_val = str_ptr
            else:
                arg_val = arg.codegen(builder, module)
            
            #print(f"DEBUG FunctionCall: arg[{i}] original type: {arg_val.type}")
            
            # Handle array-to-pointer decay for function arguments
            if isinstance(arg_val.type, ir.PointerType) and isinstance(arg_val.type.pointee, ir.ArrayType):
                #print(f"DEBUG FunctionCall: arg[{i}] is pointer to array type")
                # Check if function parameter expects a pointer to the element type
                if param_index < len(func.args):
                    param_type = func.args[param_index].type
                    array_element_type = arg_val.type.pointee.element
                    #print(f"DEBUG FunctionCall: param type: {param_type}, array element: {array_element_type}")
                    if isinstance(param_type, ir.PointerType) and param_type.pointee == array_element_type:
                        #print(f"DEBUG FunctionCall: Converting array to pointer")
                        # Convert array to pointer by GEP to first element
                        zero = ir.Constant(ir.IntType(32), 0)
                        array_ptr = builder.gep(arg_val, [zero, zero], name="array_decay")
                        arg_val = array_ptr
                        #print(f"DEBUG FunctionCall: arg[{i}] after decay: {arg_val.type}")
            
            # Check if we have a type mismatch and need to call __expr for automatic conversion
            if param_index < len(func.args):
                expected_type = func.args[param_index].type
                if arg_val.type != expected_type:
                    # Check if this is an object type that has a __expr method for automatic conversion
                    if isinstance(arg_val.type, ir.PointerType):
                        # Get the struct name - handle both identified and literal struct types
                        struct_name = None
                        
                        # Try to get name from identified struct types
                        if hasattr(arg_val.type.pointee, '_name'):
                            struct_name = arg_val.type.pointee._name.strip('"')
                            #print(f"DEBUG FunctionCall: Found struct name from _name: {struct_name}")
                        
                        # Try to get name from module's struct types
                        if struct_name is None and hasattr(module, '_struct_types'):
                            #print(f"DEBUG FunctionCall: Checking module._struct_types: {list(module._struct_types.keys())}")
                            for name, struct_type in module._struct_types.items():
                                #print(f"DEBUG FunctionCall: Comparing {name}: {struct_type} vs {arg_val.type.pointee}")
                                # More robust comparison that handles both identified and literal struct types
                                if (struct_type == arg_val.type.pointee or 
                                    (hasattr(struct_type, '_name') and hasattr(arg_val.type.pointee, '_name') and
                                     struct_type._name == arg_val.type.pointee._name) or
                                    (str(struct_type) == str(arg_val.type.pointee))):
                                    struct_name = name
                                    #print(f"DEBUG FunctionCall: Found struct name from module: {struct_name}")
                                    break
                        
                        # If we found a struct name, look for __expr method
                        if struct_name:
                            #print(f"DEBUG FunctionCall: Looking for __expr method for struct type: {struct_name}")
                            expr_method_name = f"{struct_name}.__expr"
                            #print(f"DEBUG FunctionCall: Checking for method: {expr_method_name}")
                            #print(f"DEBUG FunctionCall: Available globals: {list(module.globals.keys())}")
                            
                            if expr_method_name in module.globals:
                                expr_func = module.globals[expr_method_name]
                                if isinstance(expr_func, ir.Function):
                                    #print(f"DEBUG FunctionCall: Found __expr method, calling it for automatic conversion")
                                    # Call the __expr method to get the underlying representation
                                    converted_val = builder.call(expr_func, [arg_val])
                                    #print(f"DEBUG FunctionCall: Converted {arg_val.type} to {converted_val.type}, expected {expected_type}")
                                    # Check if the converted type matches what's expected
                                    if converted_val.type == expected_type:
                                        arg_val = converted_val
                                #else:
                                    #print(f"DEBUG FunctionCall: __expr method not a function: {type(expr_func)}")
                            #else:
                                #print(f"DEBUG FunctionCall: __expr method not found: {expr_method_name}")
                        #else:
                            #print(f"DEBUG FunctionCall: No struct name found for type: {arg_val.type}")
            
            arg_vals.append(arg_val)
            
        return builder.call(func, arg_vals)

@dataclass
class MemberAccess(Expression):
    object: Expression
    member: str

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
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
        #print(f"DEBUG MemberAccess: obj_val.type = {obj_val.type}")
        #print(f"DEBUG MemberAccess: self.object = {self.object}")
        #print(f"DEBUG MemberAccess: self.member = {self.member}")
        
        # Special case: if this is accessing 'this' in a method, handle the double pointer issue
        #print(f"DEBUG MemberAccess: isinstance(self.object, Identifier) = {isinstance(self.object, Identifier)}")
        #print(f"DEBUG MemberAccess: self.object.name == 'this' = {self.object.name == 'this' if isinstance(self.object, Identifier) else 'N/A'}")
        #print(f"DEBUG MemberAccess: isinstance(obj_val.type, ir.PointerType) = {isinstance(obj_val.type, ir.PointerType)}")
        #if isinstance(obj_val.type, ir.PointerType):
            #print(f"DEBUG MemberAccess: obj_val.type.pointee = {obj_val.type.pointee}")
            #print(f"DEBUG MemberAccess: isinstance(obj_val.type.pointee, ir.PointerType) = {isinstance(obj_val.type.pointee, ir.PointerType)}")
            #if isinstance(obj_val.type.pointee, ir.PointerType):
                #print(f"DEBUG MemberAccess: obj_val.type.pointee.pointee = {obj_val.type.pointee.pointee}")
                #print(f"DEBUG MemberAccess: isinstance(obj_val.type.pointee.pointee, ir.LiteralStructType) = {isinstance(obj_val.type.pointee.pointee, ir.LiteralStructType)}")
        if (isinstance(self.object, Identifier) and self.object.name == "this" and 
            isinstance(obj_val.type, ir.PointerType) and 
            isinstance(obj_val.type.pointee, ir.PointerType) and
            isinstance(obj_val.type.pointee.pointee, ir.LiteralStructType)):
            #print(f"DEBUG MemberAccess: Detected double pointer 'this', loading actual pointer")
            # Load the actual 'this' pointer from the alloca
            obj_val = builder.load(obj_val, name="this_ptr")
            #print(f"DEBUG MemberAccess: After load, obj_val.type = {obj_val.type}")
        
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
        else:
            # Regular single element access
            index_val = self.index.codegen(builder, module)
            
            # Handle global arrays (like const arrays)
            if isinstance(array_val, ir.GlobalVariable):
                # Create GEP to access array element
                zero = ir.Constant(ir.IntType(32), 0)
                gep = builder.gep(array_val, [zero, index_val], name="array_gep")
                return builder.load(gep, name="array_load")
            # Handle local arrays
            elif isinstance(array_val.type, ir.PointerType) and isinstance(array_val.type.pointee, ir.ArrayType):
                zero = ir.Constant(ir.IntType(32), 0)
                gep = builder.gep(array_val, [zero, index_val], name="array_gep")
                return builder.load(gep, name="array_load")
            # Handle pointer types (like char*)
            elif isinstance(array_val.type, ir.PointerType):
                # Pointer arithmetic - add index to pointer
                gep = builder.gep(array_val, [index_val], name="ptr_gep")
                return builder.load(gep, name="ptr_load")
            else:
                raise ValueError(f"Cannot access array element for type: {array_val.type}")
    
    def _handle_array_slice(self, builder: ir.IRBuilder, module: ir.Module, array_val: ir.Value) -> ir.Value:
        """Handle array slicing with range expressions like s[0..3] or s[3..0] (inclusive on both ends)"""
        start_val = self.index.start.codegen(builder, module)
        end_val = self.index.end.codegen(builder, module)
        
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
        if isinstance(array_val, ir.GlobalVariable):
            # Global array access
            zero = ir.Constant(ir.IntType(32), 0)
            source_start_ptr = builder.gep(array_val, [zero, start_val], name="source_start")
        elif isinstance(array_val.type, ir.PointerType) and isinstance(array_val.type.pointee, ir.ArrayType):
            # Local array access
            zero = ir.Constant(ir.IntType(32), 0)
            source_start_ptr = builder.gep(array_val, [zero, start_val], name="source_start")
        elif isinstance(array_val.type, ir.PointerType):
            # Pointer arithmetic for strings (char*, etc.)
            source_start_ptr = builder.gep(array_val, [start_val], name="source_start")
        else:
            raise ValueError(f"Unsupported array type for slicing: {array_val.type}")
        
        # Get pointer to the start of the slice array
        zero = ir.Constant(ir.IntType(32), 0)
        slice_start_ptr = builder.gep(slice_ptr, [zero, zero], name="slice_start")
        
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
            # counter=0 -> source_index = start (3)
            # counter=1 -> source_index = start-1 (2)
            # counter=2 -> source_index = start-2 (1)
            # counter=3 -> source_index = start-3 (0)
            source_offset = builder.sub(start_val, counter, name="reverse_source_offset")
        else:
            # For forward slices: source index goes forwards from start
            # counter=0 -> source_index = start+0
            # counter=1 -> source_index = start+1
            source_offset = builder.add(start_val, counter, name="forward_source_offset")
        
        # Get source element at calculated offset
        if isinstance(array_val, ir.GlobalVariable):
            # Global array access
            zero = ir.Constant(ir.IntType(32), 0)
            source_elem_ptr = builder.gep(array_val, [zero, source_offset], name="source_elem")
        elif isinstance(array_val.type, ir.PointerType) and isinstance(array_val.type.pointee, ir.ArrayType):
            # Local array access
            zero = ir.Constant(ir.IntType(32), 0)
            source_elem_ptr = builder.gep(array_val, [zero, source_offset], name="source_elem")
        elif isinstance(array_val.type, ir.PointerType):
            # Pointer arithmetic for strings (char*, etc.)
            source_elem_ptr = builder.gep(array_val, [source_offset], name="source_elem")
        
        source_elem = builder.load(source_elem_ptr, name="source_val")
        
        # Store in slice array at sequential destination index (always forward)
        dest_elem_ptr = builder.gep(slice_start_ptr, [counter], name="dest_elem")
        builder.store(source_elem, dest_elem_ptr)
        
        # Increment counter
        next_counter = builder.add(counter, ir.Constant(ir.IntType(32), 1), name="next_counter")
        builder.store(next_counter, counter_ptr)
        builder.branch(loop_cond)
        
        # End of loop - add null terminator for strings
        builder.position_at_start(loop_end)
        if element_type == ir.IntType(8):  # For string slices, add null terminator
            final_counter = builder.load(counter_ptr, name="final_counter")
            null_ptr = builder.gep(slice_start_ptr, [final_counter], name="null_pos")
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
        #print(f"DEBUG AddressOf: Starting codegen for AddressOf of {self.expression}")
        # Special case: Handle Identifier directly to avoid the codegen call that might fail
        if isinstance(self.expression, Identifier):
            var_name = self.expression.name
            #print(f"DEBUG AddressOf: Processing Identifier '{var_name}'")
            
            # Check if it's a local variable
            if builder.scope is not None and var_name in builder.scope:
                ptr = builder.scope[var_name]
                #print(f"DEBUG AddressOf: Found {var_name} in local scope, type: {ptr.type}")
                # Special case: if this is a function parameter that's already a pointer type
                # (like array parameters), return the loaded value directly
                if (isinstance(ptr.type, ir.PointerType) and 
                    isinstance(ptr.type.pointee, ir.PointerType)):
                    #print(f"DEBUG AddressOf: Double pointer detected, loading...")
                    # This is a pointer to a pointer (function parameter storage)
                    # Return the loaded pointer value, not the address of the storage
                    result = builder.load(ptr, name=f"{var_name}_ptr")
                    #print(f"DEBUG AddressOf: Loaded result type: {result.type}")
                    return result
                #print(f"DEBUG AddressOf: Returning local pointer directly: {ptr.type}")
                return ptr
            
            # Check if it's a global variable
            if var_name in module.globals:
                gvar = module.globals[var_name]
                #print(f"DEBUG AddressOf: Found {var_name} in globals, type: {gvar.type}")
                # For arrays (including string arrays like noopstr), return the global directly
                # For other pointer types, check if it's a pointer to pointer
                if (isinstance(gvar.type, ir.PointerType) and 
                    isinstance(gvar.type.pointee, ir.PointerType) and
                    not isinstance(gvar.type.pointee, ir.ArrayType)):
                    #print(f"DEBUG AddressOf: Global double pointer (non-array) detected, loading...")
                    # This is a pointer to a pointer (non-array global variable storage of pointer type)
                    # Return the loaded pointer value, not the address of the storage
                    result = builder.load(gvar, name=f"{var_name}_ptr")
                    #print(f"DEBUG AddressOf: Loaded global result type: {result.type}")
                    return result
                #print(f"DEBUG AddressOf: Returning global pointer directly: {gvar.type}")
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
                        #print(f"DEBUG AddressOf: Found {var_name} as {mangled_name}, type: {gvar.type}")
                        if isinstance(gvar.type, ir.PointerType):
                            #print(f"DEBUG AddressOf: pointee type: {gvar.type.pointee}")
                            #print(f"DEBUG AddressOf: is array type: {isinstance(gvar.type.pointee, ir.ArrayType)}")
                            # For arrays (including string arrays like noopstr), return the global directly
                            # For other pointer types, check if it's a pointer to pointer
                            if (isinstance(gvar.type.pointee, ir.PointerType) and not isinstance(gvar.type.pointee, ir.ArrayType)):
                                #print(f"DEBUG AddressOf: Namespace global double pointer (non-array) detected, loading...")
                                # This is a pointer to a pointer (non-array global variable storage of pointer type)
                                # Return the loaded pointer value, not the address of the storage
                                result = builder.load(gvar, name=f"{var_name}_ptr")
                                #print(f"DEBUG AddressOf: Loaded namespace global result type: {result.type}")
                                return result
                        #print(f"DEBUG AddressOf: Returning namespace global directly: {gvar.type}")
                        return gvar
            
            # If we get here, the variable hasn't been declared yet
            raise NameError(f"Unknown variable: {var_name}")
        
        # Handle pointer dereference - &(*ptr) is equivalent to ptr
        if isinstance(self.expression, PointerDeref):
            # For &(*ptr), just return the pointer value directly
            # This is a fundamental identity: &(*ptr) == ptr
            return self.expression.pointer.codegen(builder, module)
        
        # For non-Identifier expressions, generate code normally
        target = self.expression.codegen(builder, module)
        
        # Handle member access
        if isinstance(self.expression, MemberAccess):
            obj = self.expression.object.codegen(builder, module)
            member_name = self.expression.member
            
            if isinstance(obj.type, ir.PointerType) and isinstance(obj.type.pointee, ir.LiteralStructType):
                struct_type = obj.type.pointee
                if hasattr(struct_type, 'names'):
                    try:
                        idx = struct_type.names.index(member_name)
                        return builder.gep(
                            obj,
                            [ir.Constant(ir.IntType(32), 0)],
                            [ir.Constant(ir.IntType(32), idx)],
                            inbounds=True
                        )
                    except ValueError:
                        raise ValueError(f"Member '{member_name}' not found in struct")
        
        # Handle array access
        elif isinstance(self.expression, ArrayAccess):
            array = self.expression.array.codegen(builder, module)
            index = self.expression.index.codegen(builder, module)
            
            if isinstance(array.type, ir.PointerType):
                zero = ir.Constant(ir.IntType(32), 0)
                return builder.gep(array, [zero, index], inbounds=True)
        
        # Handle pointer dereference - &(*ptr) is equivalent to ptr
        elif isinstance(self.expression, PointerDeref):
            # For &(*ptr), just return the pointer value directly
            # This is a fundamental identity: &(*ptr) == ptr
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

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        #print(f"DEBUG VariableDeclaration: name={self.name}, type_spec.base_type={self.type_spec.base_type}")
        #print(f"DEBUG VariableDeclaration: type_spec={self.type_spec}")
        #if hasattr(module, '_type_aliases'):
            #print(f"DEBUG VariableDeclaration: available type aliases: {list(module._type_aliases.keys())}")
            #for alias_name, alias_type in module._type_aliases.items():
                #print(f"DEBUG VariableDeclaration:   {alias_name} -> {alias_type}")
        
        # Check for automatic array size inference with string literals
        # This handles both direct array types and type aliases that resolve to arrays
        infer_array_size = False
        resolved_type_spec = self.type_spec
        
        # Direct array type check
        if (self.type_spec.is_array and self.type_spec.array_size is None and
            self.initial_value and isinstance(self.initial_value, Literal) and
            self.initial_value.type == DataType.CHAR):
            infer_array_size = True
        
        # Type alias check - if base_type is a string, it might be a type alias
        elif (isinstance(self.type_spec.base_type, str) and
            self.initial_value and isinstance(self.initial_value, Literal) and
            self.initial_value.type == DataType.CHAR):
            # Check if the type alias resolves to an array type
            # Use the same resolution logic as TypeSpec.get_llvm_type to handle namespaced types
            try:
                resolved_llvm_type = self.type_spec.get_llvm_type(module)
            except NameError:
                resolved_llvm_type = None
            
            if resolved_llvm_type is not None:
                # If it resolves to a pointer type (unsized array), we can infer the size
                if isinstance(resolved_llvm_type, ir.PointerType) and isinstance(resolved_llvm_type.pointee, ir.IntType) and resolved_llvm_type.pointee.width == 8:
                    infer_array_size = True
                    # Create a proper array TypeSpec from the alias
                    resolved_type_spec = TypeSpec(
                        base_type=DataType.DATA,
                        is_signed=False,
                        is_const=self.type_spec.is_const,
                        is_volatile=self.type_spec.is_volatile,
                        bit_width=8,
                        alignment=self.type_spec.alignment,
                        is_array=True,
                        array_size=None,  # Will be inferred below
                        is_pointer=False
                    )
        
        # Check for struct-to-byte-array cast (e.g., noopstr s = (noopstr)struct_var)
        elif (isinstance(self.type_spec.base_type, str) and
            self.initial_value and isinstance(self.initial_value, CastExpression)):
            # Check if target type is a byte array alias and source is a struct
            if hasattr(module, '_type_aliases') and self.type_spec.base_type in module._type_aliases:
                resolved_llvm_type = module._type_aliases[self.type_spec.base_type]
                # If casting to a byte array type (i8* alias)
                if isinstance(resolved_llvm_type, ir.PointerType) and isinstance(resolved_llvm_type.pointee, ir.IntType) and resolved_llvm_type.pointee.width == 8:
                    # Get the source value to determine its size
                    source_val = self.initial_value.expression.codegen(builder, module)
                    if isinstance(source_val.type, ir.LiteralStructType):
                        # Calculate struct size in bytes
                        struct_size_bits = sum(elem.width for elem in source_val.type.elements if hasattr(elem, 'width'))
                        struct_size_bytes = struct_size_bits // 8
                        # Create array TypeSpec with inferred size
                        infer_array_size = True
                        resolved_type_spec = TypeSpec(
                            base_type=DataType.DATA,
                            is_signed=False,
                            is_const=self.type_spec.is_const,
                            is_volatile=self.type_spec.is_volatile,
                            bit_width=8,
                            alignment=self.type_spec.alignment,
                            is_array=True,
                            array_size=struct_size_bytes,
                            is_pointer=False
                        )
                        # Use the struct size for array inference
                        string_length = struct_size_bytes
        
        if infer_array_size:
            # Infer array size - check if it's from struct cast or string literal
            if isinstance(self.initial_value, CastExpression) and 'string_length' in locals():
                # For struct casts, we already calculated the size above
                pass  # string_length was set in the struct cast detection code
            else:
                # For string literals
                string_length = len(self.initial_value.value)
            # Create a new TypeSpec with the inferred size
            inferred_type_spec = TypeSpec(
                base_type=resolved_type_spec.base_type,
                is_signed=resolved_type_spec.is_signed,
                is_const=resolved_type_spec.is_const,
                is_volatile=resolved_type_spec.is_volatile,
                bit_width=resolved_type_spec.bit_width,
                alignment=resolved_type_spec.alignment,
                is_array=True,
                array_size=string_length,  # Infer the size from string
                is_pointer=resolved_type_spec.is_pointer
            )
            llvm_type = inferred_type_spec.get_llvm_type_with_array(module)
        else:
            llvm_type = self.type_spec.get_llvm_type_with_array(module)
        #print(f"DEBUG VariableDeclaration: resolved llvm_type = {llvm_type}")
        
        # Handle global variables
        if builder.scope is None:
            # Check if global already exists (handle both original name and potential namespaced names)
            if self.name in module.globals:
                return module.globals[self.name]
            
            # For namespaced variables, check if any existing global has the same effective name
            # E.g., if we're defining 'standard__types__nl', check for any existing 'nl' variants
            base_name = self.name.split('__')[-1]  # Extract the final name part (e.g., 'nl' from 'standard__types__nl')
            for existing_name in list(module.globals.keys()):
                existing_base_name = existing_name.split('__')[-1]
                if existing_base_name == base_name and existing_name != self.name:
                    # Found a global with the same base name but different namespace
                    # Return the existing one to prevent duplicates
                    return module.globals[existing_name]
                elif existing_name == self.name:
                    # Exact match - return existing
                    return module.globals[existing_name]
                
            # Create new global
            gvar = ir.GlobalVariable(module, llvm_type, self.name)
            
            # Set initializer
            if self.initial_value:
                # Handle array literals specially
                if isinstance(llvm_type, ir.ArrayType) and hasattr(self.initial_value, 'value') and isinstance(self.initial_value.value, list):
                    # Create array constant from list of values
                    element_values = []
                    for item in self.initial_value.value:
                        if hasattr(item, 'value'):
                            # Convert each element to LLVM constant
                            element_values.append(ir.Constant(llvm_type.element, item.value))
                        else:
                            element_values.append(ir.Constant(llvm_type.element, item))
                    gvar.initializer = ir.Constant(llvm_type, element_values)
                # Handle string literals for char arrays
                elif isinstance(llvm_type, ir.ArrayType) and isinstance(llvm_type.element, ir.IntType) and llvm_type.element.width == 8 and isinstance(self.initial_value, Literal) and self.initial_value.type == DataType.CHAR:
                    # Convert string to array of characters
                    string_val = self.initial_value.value
                    char_values = []
                    for i, char in enumerate(string_val):
                        if i >= llvm_type.count:
                            break
                        char_values.append(ir.Constant(ir.IntType(8), ord(char)))
                    # Pad remaining with zeros if needed
                    while len(char_values) < llvm_type.count:
                        char_values.append(ir.Constant(ir.IntType(8), 0))
                    gvar.initializer = ir.Constant(llvm_type, char_values)
                # Handle string literals for pointer types (global variables)
                elif isinstance(llvm_type, ir.PointerType) and isinstance(llvm_type.pointee, ir.IntType) and llvm_type.pointee.width == 8 and isinstance(self.initial_value, Literal) and self.initial_value.type == DataType.CHAR:
                    # Create global string constant for pointer types
                    string_val = self.initial_value.value
                    string_bytes = string_val.encode('ascii')
                    str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
                    str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
                    
                    # Create a separate global variable for the string data
                    str_gv = ir.GlobalVariable(module, str_val.type, name=f".str.{self.name}")
                    str_gv.linkage = 'internal'
                    str_gv.global_constant = True
                    str_gv.initializer = str_val
                    
                    # Get pointer to the first character of the string as the initializer
                    zero = ir.Constant(ir.IntType(32), 0)
                    str_ptr = str_gv.gep([zero, zero])
                    gvar.initializer = str_ptr
                else:
                    init_val = self.initial_value.codegen(builder, module)
                    if init_val is not None:
                        gvar.initializer = init_val
                    else:
                        # Fallback for None return from codegen
                        if isinstance(llvm_type, ir.ArrayType):
                            gvar.initializer = ir.Constant(llvm_type, ir.Undefined)
                        else:
                            gvar.initializer = ir.Constant(llvm_type, 0)
            else:
                # Default initialize based on type
                if isinstance(llvm_type, ir.ArrayType):
                    gvar.initializer = ir.Constant(llvm_type, ir.Undefined)
                elif isinstance(llvm_type, ir.IntType):
                    gvar.initializer = ir.Constant(llvm_type, 0)
                elif isinstance(llvm_type, ir.FloatType):
                    gvar.initializer = ir.Constant(llvm_type, 0.0)
                else:
                    gvar.initializer = ir.Constant(llvm_type, None)
            
            # Set linkage and visibility
            gvar.linkage = 'internal'
            return gvar
        
        # Handle local variables
        alloca = builder.alloca(llvm_type, name=self.name)
        if self.initial_value:
            # Handle string literals specially
            if (isinstance(self.initial_value, Literal) and self.initial_value.type == DataType.CHAR):
                if isinstance(llvm_type, ir.PointerType) and isinstance(llvm_type.pointee, ir.IntType) and llvm_type.pointee.width == 8:
                    # Handle string literal initialization for local pointer types (like noopstr)
                    string_val = self.initial_value.value
                    string_bytes = string_val.encode('ascii')
                    str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
                    str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
                    
                    # Create global variable for the string data
                    str_gv = ir.GlobalVariable(module, str_val.type, name=f".str.{self.name}")
                    str_gv.linkage = 'internal'
                    str_gv.global_constant = True
                    str_gv.initializer = str_val
                    
                    # Get pointer to the first character of the string as the initializer
                    zero = ir.Constant(ir.IntType(32), 0)
                    str_ptr = builder.gep(str_gv, [zero, zero], name=f"{self.name}_str_ptr")
                    builder.store(str_ptr, alloca)
                elif isinstance(llvm_type, ir.ArrayType) and isinstance(llvm_type.element, ir.IntType) and llvm_type.element.width == 8:
                    # Handle string literal initialization for local char arrays
                    string_val = self.initial_value.value
                    
                    # Store each character individually
                    for i, char in enumerate(string_val):
                        if i >= llvm_type.count:
                            break
                        
                        # Get pointer to array element
                        zero = ir.Constant(ir.IntType(32), 0)
                        index = ir.Constant(ir.IntType(32), i)
                        elem_ptr = builder.gep(alloca, [zero, index], name=f"{self.name}[{i}]")
                        
                        # Store the character
                        char_val = ir.Constant(ir.IntType(8), ord(char))
                        builder.store(char_val, elem_ptr)
                    
                    # Zero-fill remaining elements if needed
                    for i in range(len(string_val), llvm_type.count):
                        zero_val = ir.Constant(ir.IntType(32), 0)
                        index = ir.Constant(ir.IntType(32), i)
                        elem_ptr = builder.gep(alloca, [zero_val, index], name=f"{self.name}[{i}]")
                        zero_char = ir.Constant(ir.IntType(8), 0)
                        builder.store(zero_char, elem_ptr)
                        
            elif isinstance(self.initial_value, FunctionCall) and self.initial_value.name.endswith('.__init'):
                # This is an object constructor call
                # We need to call the constructor with 'this' pointer as first argument
                constructor_func = module.globals.get(self.initial_value.name)
                if constructor_func is None:
                    raise NameError(f"Constructor not found: {self.initial_value.name}")
                
                # Call constructor with 'this' pointer (alloca) as first argument
                args = [alloca]  # 'this' pointer
                
                # Process constructor arguments using the same logic as FunctionCall.codegen
                # This ensures string literals are properly converted to global string constants
                for i, arg_expr in enumerate(self.initial_value.arguments):
                    # Check if this is a string literal that needs conversion
                    param_index = i + 1  # +1 because args[0] is 'this' pointer
                    if (isinstance(arg_expr, Literal) and arg_expr.type == DataType.CHAR and
                        param_index < len(constructor_func.args) and
                        isinstance(constructor_func.args[param_index].type, ir.PointerType) and
                        isinstance(constructor_func.args[param_index].type.pointee, ir.IntType) and
                        constructor_func.args[param_index].type.pointee.width == 8):
                        # Convert string literal to global constant
                        string_val = arg_expr.value
                        string_bytes = string_val.encode('ascii')
                        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
                        str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
                        
                        # Create global variable for the string
                        gv = ir.GlobalVariable(module, str_val.type, name=f".str.ctor_{self.name}_arg{i}")
                        gv.linkage = 'internal'
                        gv.global_constant = True
                        gv.initializer = str_val
                        
                        # Get pointer to the first character of the string
                        zero = ir.Constant(ir.IntType(32), 0)
                        str_ptr = builder.gep(gv, [zero, zero], name=f"ctor_arg{i}_str_ptr")
                        arg_val = str_ptr
                    else:
                        # Normal argument processing
                        arg_val = arg_expr.codegen(builder, module)
                    
                    args.append(arg_val)
                
                # Call the constructor
                init_val = builder.call(constructor_func, args)
                # Note: For constructors that return 'this', init_val will be the initialized object pointer
                # But since we already have the object in alloca, we don't need to store init_val
            else:
                # Regular initialization for non-string literals
                init_val = self.initial_value.codegen(builder, module)
                if init_val is not None:
                    # Special case: Handle single byte to string conversion
                    if (isinstance(init_val.type, ir.IntType) and init_val.type.width == 8 and
                        isinstance(llvm_type, ir.PointerType) and isinstance(llvm_type.pointee, ir.IntType) and
                        llvm_type.pointee.width == 8):
                        # Create a single-character string from the byte
                        # This handles cases like: noopstr x = s[1];
                        char_array = ir.ArrayType(ir.IntType(8), 2)  # [i8 x 2] for char + null terminator
                        temp_alloca = builder.alloca(char_array, name=f"{self.name}_temp_str")
                        
                        # Store the character at index 0
                        zero = ir.Constant(ir.IntType(32), 0)
                        char_ptr = builder.gep(temp_alloca, [zero, zero], name="char_pos")
                        builder.store(init_val, char_ptr)
                        
                        # Store null terminator at index 1
                        one = ir.Constant(ir.IntType(32), 1)
                        null_ptr = builder.gep(temp_alloca, [zero, one], name="null_pos")
                        null_char = ir.Constant(ir.IntType(8), 0)
                        builder.store(null_char, null_ptr)
                        
                        # Get pointer to the first character (this is our string)
                        string_ptr = builder.gep(temp_alloca, [zero, zero], name=f"{self.name}_str_ptr")
                        builder.store(string_ptr, alloca)
                        return alloca
                    
                    # Special handling for cast to array initialization
                    if (isinstance(self.initial_value, CastExpression) and
                        isinstance(init_val.type, ir.PointerType) and
                        isinstance(llvm_type, ir.ArrayType)):
                        # Bitcast source pointer to match destination array pointer type
                        array_ptr_type = ir.PointerType(llvm_type)
                        casted_ptr = builder.bitcast(init_val, array_ptr_type, name="cast_to_array_ptr")
                        # Load the entire array from the casted pointer
                        array_value = builder.load(casted_ptr, name="loaded_array")
                        # Store the loaded array into our allocated array
                        builder.store(array_value, alloca)
                    else:
                        # Cast init value to match variable type if needed
                        if init_val.type != llvm_type:
                            # Handle array concatenation results - preserve array pointer semantics
                            if (isinstance(self.initial_value, BinaryOp) and 
                                self.initial_value.operator in (Operator.ADD, Operator.SUB) and
                                isinstance(init_val.type, ir.PointerType) and 
                                isinstance(init_val.type.pointee, ir.ArrayType) and
                                isinstance(llvm_type, ir.PointerType) and 
                                isinstance(llvm_type.pointee, ir.IntType)):
                                # This is array concatenation result being assigned to pointer type (like noopstr)
                                # Convert array to pointer by GEP to first element, preserving array semantics
                                zero = ir.Constant(ir.IntType(32), 0)
                                array_ptr = builder.gep(init_val, [zero, zero], name="concat_array_to_ptr")
                                builder.store(array_ptr, alloca)
                                return alloca
                            # Handle pointer type compatibility (for AddressOf expressions)
                            elif isinstance(llvm_type, ir.PointerType) and isinstance(init_val.type, ir.PointerType):
                                # Both are pointers - check if compatible or cast
                                if llvm_type.pointee != init_val.type.pointee:
                                    # Cast pointer types if needed
                                    init_val = builder.bitcast(init_val, llvm_type)
                            # Handle integer type casting
                            elif isinstance(init_val.type, ir.IntType) and isinstance(llvm_type, ir.IntType):
                                if init_val.type.width > llvm_type.width:
                                    # Truncate to smaller type
                                    init_val = builder.trunc(init_val, llvm_type)
                                elif init_val.type.width < llvm_type.width:
                                    # Extend to larger type (sign extend)
                                    init_val = builder.sext(init_val, llvm_type)
                            # Handle other type conversions as needed
                            elif isinstance(init_val.type, ir.IntType) and isinstance(llvm_type, ir.FloatType):
                                init_val = builder.sitofp(init_val, llvm_type)
                            elif isinstance(init_val.type, ir.FloatType) and isinstance(llvm_type, ir.IntType):
                                init_val = builder.fptosi(init_val, llvm_type)
                        builder.store(init_val, alloca)
        
        builder.scope[self.name] = alloca
        # Track volatile variables so that subsequent loads/stores use the 'volatile' flag
        if self.type_spec.is_volatile:
            if not hasattr(builder, 'volatile_vars'):
                builder.volatile_vars = set()
            builder.volatile_vars.add(self.name)
        return alloca
    
    def get_llvm_type(self, module: ir.Module) -> ir.Type:
        if isinstance(self.type_spec.base_type, str):
            # Check if it's a struct type
            if hasattr(module, '_struct_types') and self.type_spec.base_type in module._struct_types:
                return module._struct_types[self.type_spec.base_type]
            # Check if it's a type alias
            if hasattr(module, '_type_aliases') and self.type_spec.base_type in module._type_aliases:
                return module._type_aliases[self.type_spec.base_type]
            # Default to i32
            return ir.IntType(type_spec.bit_width)
        
        # Handle primitive types
        if self.type_spec.base_type == DataType.INT:
            return ir.IntType(32)
        elif self.type_spec.base_type == DataType.FLOAT:
            return ir.FloatType()
        elif self.type_spec.base_type == DataType.BOOL:
            return ir.IntType(1)
        elif self.type_spec.base_type == DataType.CHAR:
            return ir.IntType(8)
        elif self.type_spec.base_type == DataType.VOID:
            return ir.VoidType()
        elif self.type_spec.base_type == DataType.DATA:
            return ir.IntType(self.type_spec.bit_width)
        else:
            raise ValueError(f"Unsupported type: {self.type_spec.base_type}")

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
    
    def get_llvm_type(self, type_spec: TypeSpec) -> ir.Type:
        if isinstance(type_spec.base_type, str):
            # Handle custom types by looking them up in the module
            if hasattr(module, '_type_aliases') and type_spec.base_type in module._type_aliases:
                return module._type_aliases[type_spec.base_type]
            # Default to i32 if type not found
            return ir.IntType(32)
        elif type_spec.base_type == DataType.INT:
            return ir.IntType(32)
        elif type_spec.base_type == DataType.FLOAT:
            return ir.FloatType()
        elif type_spec.base_type == DataType.BOOL:
            return ir.IntType(1)
        elif type_spec.base_type == DataType.CHAR:
            return ir.IntType(8)
        elif type_spec.base_type == DataType.VOID:
            return ir.VoidType()
        elif type_spec.base_type == DataType.DATA:
            # For data types, use the specified bit width
            width = type_spec.bit_width
            return ir.IntType(width)
        else:
            raise ValueError(f"Unsupported type: {type_spec.base_type}")

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
            string_bytes = self.macro_value.encode('ascii') + b'\0'  # null terminated
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
                    zero = ir.Constant(ir.IntType(32), 0)
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
                    zero = ir.Constant(ir.IntType(32), 0)
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
                zero = ir.Constant(ir.IntType(32), 0)
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
                        zero = ir.Constant(ir.IntType(32), 0)
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
                zero = ir.Constant(ir.IntType(32), 0)
                old_start = builder.gep(ptr, [zero, zero], name="old_start")
                
                # Get pointer to start of new array
                new_start = builder.gep(new_alloca, [zero, zero], name="new_start")
                
                # Copy old data
                emit_memcpy(builder, module, new_start, old_start, old_bytes)
            
            # Copy new data to the new array (overwriting all elements)
            new_bytes = val_len * (val_elem_type.width // 8)
            zero = ir.Constant(ir.IntType(32), 0)
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
            
            zero = ir.Constant(ir.IntType(32), 0)
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
                    #print(f"DEBUG Block: Error in statement {i} ({type(stmt).__name__}): {e}")
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
        builder.branch(merge_block)
        
        # Emit else block
        builder.position_at_start(else_block)
        if self.else_block:
            self.else_block.codegen(builder, module)
        builder.branch(merge_block)
        
        # Position builder at merge block
        builder.position_at_start(merge_block)
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
        builder.branch(cond_block)  # Loop back
        
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
                zero = ir.Constant(ir.IntType(32), 0)
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
        
        # Insert unreachable instruction if there's trailing code
        if builder.block.is_terminated:
            return None
            
        builder.branch(builder.break_block)
        # Mark following code as unreachable
        builder.unreachable()
        return None

@dataclass
class ContinueStatement(Statement):
    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
        if not hasattr(builder, 'continue_block'):
            raise SyntaxError("'continue' outside of loop")
        
        # Insert unreachable instruction if there's trailing code  
        if builder.block.is_terminated:
            return None
            
        builder.branch(builder.continue_block)
        # Mark following code as unreachable
        builder.unreachable()
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
        
        # Create basic blocks for each case (including default)
        func = builder.block.function
        case_blocks = []
        default_block = None
        
        # Create blocks for all cases first
        for case in self.cases:
            if case.value is None:  # Default case
                default_block = func.append_basic_block("switch_default")
                case_blocks.append((None, default_block))
            else:
                case_block = func.append_basic_block(f"case_{len(case_blocks)}")
                case_blocks.append((case.value, case_block))
        
        # Create the switch instruction
        switch = builder.switch(switch_val, default_block)
        
        # Add all cases to the switch
        for value, block in case_blocks:
            if value is not None:
                case_const = value.codegen(builder, module)
                switch.add_case(case_const, block)
        
        # Generate code for each case block
        for i, (value, case_block) in enumerate(case_blocks):
            builder.position_at_start(case_block)
            self.cases[i].body.codegen(builder, module)
            
            # Add terminator if not already present
            if not builder.block.is_terminated:
                if default_block:
                    builder.branch(default_block)
                else:
                    # If no default, branch to function return
                    if isinstance(func.return_type, ir.VoidType):
                        builder.ret_void()
                    else:
                        builder.ret(ir.Constant(func.return_type, 0))
        
        # Position builder after the switch
        merge_block = func.append_basic_block("switch_merge")
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
            [ir.Constant(ir.IntType(32), 0)],
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
                name='assert_msg'
            )
            msg_gv.initializer = msg_const
            msg_gv.linkage = 'internal'
            msg_gv.global_constant = True
            
            # Get pointer to message
            zero = ir.Constant(ir.IntType(32), 0)
            msg_ptr = builder.gep(msg_gv, [zero, zero], inbounds=True)
            
            # Declare puts if not already present
            puts = module.globals.get('puts')
            if puts is None:
                puts_ty = ir.FunctionType(
                    ir.IntType(32),  # int return
                    [ir.PointerType(ir.IntType(8))],  # char*
                )
                puts = ir.Function(module, puts_ty, 'puts')
            
            builder.call(puts, [msg_ptr])

        # Declare abort if not present
        abort = module.globals.get('abort')
        if abort is None:
            abort_ty = ir.FunctionType(ir.VoidType(), [])
            abort = ir.Function(module, abort_ty, 'abort')
        
        builder.call(abort, [])
        builder.unreachable()

        # Success block
        builder.position_at_start(pass_block)
        return None

# Function parameter
@dataclass
class Parameter(ASTNode):
    name: str
    type_spec: TypeSpec

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
        
        # Convert parameter types
        param_types = [self._convert_type(param.type_spec, module) for param in self.parameters]
        
        # Create function type
        func_type = ir.FunctionType(ret_type, param_types)
        
        # Check if function already exists (from prototype)
        if self.name in module.globals:
            existing = module.globals[self.name]
            if isinstance(existing, ir.Function):
                # Verify the signatures match
                #print(f"DEBUG: Comparing function types for '{self.name}':")
                #print(f"DEBUG: Existing type: {existing.type}")
                #print(f"DEBUG: New type:      {func_type}")
                #print(f"DEBUG: Types equal:   {existing.type == func_type}")
                #print(f"DEBUG: Existing function type: {existing.ftype}")
                #print(f"DEBUG: Existing.ftype == func_type: {existing.ftype == func_type}")
                # Compare the actual function type, not the pointer type
                if existing.ftype != func_type:
                    raise ValueError(f"Function '{self.name}' redefined with different signature\nExisting: {existing.ftype}\nNew: {func_type}")
                func = existing
            else:
                raise ValueError(f"Name '{self.name}' already used for non-function")
        else:
            # Create new function
            func = ir.Function(module, func_type, self.name)

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
        
        # Allocate space for parameters and store initial values
        for i, param in enumerate(func.args):
            alloca = builder.alloca(param.type, name=f"{param.name}.addr")
            builder.store(param, alloca)
            builder.scope[self.parameters[i].name] = alloca
        
        # Generate function body
        #print(f"DEBUG FunctionDef: Generating body for {self.name}")
        #print(f"DEBUG FunctionDef: Body has {len(self.body.statements)} statements")
        #for i, stmt in enumerate(self.body.statements):
            #print(f"DEBUG FunctionDef: Statement {i}: {type(stmt).__name__} = {stmt}")
        self.body.codegen(builder, module)
        
        # Add implicit return if needed
        if not builder.block.is_terminated:
            if isinstance(ret_type, ir.VoidType):
                builder.ret_void()
            else:
                raise RuntimeError("Function must end with return statement")
        
        # Restore previous scope
        builder.scope = old_scope
        return func
    
    def _convert_type(self, type_spec: TypeSpec, module: ir.Module = None) -> ir.Type:
        # Use the proper method that handles arrays and pointers
        if module is None:
            module = ir.Module()
        return type_spec.get_llvm_type_with_array(module)

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

# Struct member
@dataclass
class StructMember(ASTNode):
    name: str
    type_spec: TypeSpec
    initial_value: Optional[Expression] = None
    is_private: bool = False

# Struct definition
@dataclass
class StructDef(ASTNode):
    name: str
    members: List[StructMember] = field(default_factory=list)
    base_structs: List[str] = field(default_factory=list)  # inheritance
    nested_structs: List['StructDef'] = field(default_factory=list)

    def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Type:
        print("HERE1")
        # Convert member types
        member_types = []
        member_names = []
        for member in self.members:
            member_type = self._convert_type(member.type_spec, module)
            member_types.append(member_type)
            member_names.append(member.name)
        print("HERE2")
        # Create the struct type
        struct_type = ir.LiteralStructType(member_types)
        struct_type.names = member_names
        print("HERE3")
        # Store the type in the module's context
        if not hasattr(module, '_struct_types'):
            module._struct_types = {}
        module._struct_types[self.name] = struct_type
        print("HERE4")
        # Create global variables for initialized members
        for member in self.members:
            if member.initial_value is not None:  # Check for initial_value here
                print("HERE5")
                # Create global variable for initialized members
                gvar = ir.GlobalVariable(
                    module, 
                    member_type, 
                    f"{self.name}.{member.name}"
                )
                gvar.initializer = member.initial_value.codegen(builder, module)
                gvar.linkage = 'internal'
            else:
                print("HERE6")
        print("RETURNED!?")
        return struct_type
    
    def _convert_type(self, type_spec: TypeSpec, module: ir.Module) -> ir.Type:
        if isinstance(type_spec.base_type, str):
            print("HERE22")
            # Check if it's a struct type
            if hasattr(module, '_struct_types') and type_spec.base_type in module._struct_types:
                return module._struct_types[type_spec.base_type]
            print("HERE33")
            # Check if it's a type alias
            if hasattr(module, '_type_aliases') and type_spec.base_type in module._type_aliases:
                return module._type_aliases[type_spec.base_type]
        
        print("TYPE SPEC:", type_spec)
        
        if type_spec.bit_width is None:
            #print(module._type_aliases)
            #print(module._type_aliases.values())
            print(type_spec.base_type)
            print("DEFAULTING")
            #print(type_spec.bit_width) # NONE when `noopstr` custom type
            return ir.IntType(type_spec.bit_width)
        
        # Handle primitive types
        if type_spec.base_type == DataType.INT:
            return ir.IntType(32)
        elif type_spec.base_type == DataType.FLOAT:
            return ir.FloatType()
        elif type_spec.base_type == DataType.BOOL:
            return ir.IntType(1)
        elif type_spec.base_type == DataType.CHAR:
            return ir.IntType(8)
        elif type_spec.base_type == DataType.VOID:
            return ir.VoidType()
        elif type_spec.base_type == DataType.DATA:
            return ir.IntType(type_spec.bit_width)
        else:
            raise ValueError(f"Unsupported type: {type_spec.base_type}")

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
        # Parse and validate namespace path
        namespace_parts = self.namespace_path.split("::")
        
        # Initialize namespace registry if it doesn't exist
        if not hasattr(module, '_namespaces'):
            module._namespaces = set()
        
        # Check if the namespace exists
        namespace_exists = self.namespace_path in module._namespaces
        
        # Also check for partial matches (e.g., "standard" exists if "standard::types" was defined)
        if not namespace_exists:
            for registered_ns in module._namespaces:
                if registered_ns == namespace_parts[0] or registered_ns.startswith(self.namespace_path + "::"):
                    namespace_exists = True
                    break
        
        if not namespace_exists:
            raise NameError(f"Namespace '{self.namespace_path}' is not defined")
        
        # Store the namespace information for symbol resolution
        if not hasattr(module, '_using_namespaces'):
            module._using_namespaces = []
        module._using_namespaces.append(self.namespace_path)
        
        # Also add the leaf namespace name for direct access (e.g., 'types' from 'standard::types')
        leaf_name = self.namespace_path.split('::')[-1]
        if leaf_name not in module._using_namespaces:
            module._using_namespaces.append(leaf_name)
        
        # Create unqualified aliases for symbols and generate code if needed
        namespace_mangled = self.namespace_path.replace('::', '__')
        
        # Look for imported symbols that match this namespace and generate code if needed
        if hasattr(module, '_imported_symbols'):
            for import_path, statements in module._imported_symbols.items():
                # Process statements from imported modules recursively
                self._process_statements_for_namespace(statements, self.namespace_path, builder, module)
    
    def _process_statements_for_namespace(self, statements, target_namespace, builder, module):
        """Recursively process statements looking for matching namespace definitions"""
        #print(f"DEBUG: Processing statements for namespace: {target_namespace}")
        
        # FIRST PASS: Process all using statements to establish type resolution context
        #print(f"DEBUG: First pass - processing using statements")
        for stmt in statements:
            if hasattr(stmt, '__class__') and stmt.__class__.__name__ == 'UsingStatement':
                #print(f"DEBUG: Found using statement: {stmt.namespace_path}")
                # Add namespace to using list without recursive processing
                if not hasattr(module, '_using_namespaces'):
                    module._using_namespaces = []
                if stmt.namespace_path not in module._using_namespaces:
                    module._using_namespaces.append(stmt.namespace_path)
                    #print(f"DEBUG: Added {stmt.namespace_path} to using namespaces")
                    
                    # Also add the leaf namespace name for direct access (e.g., 'types' from 'standard::types')
                    leaf_name = stmt.namespace_path.split('::')[-1]
                    if leaf_name not in module._using_namespaces:
                        module._using_namespaces.append(leaf_name)
                        #print(f"DEBUG: Added leaf namespace '{leaf_name}' to using namespaces")
        
        # SECOND PASS: Process namespace definitions with full context
        #print(f"DEBUG: Second pass - processing namespace definitions")
        for stmt in statements:
            #print(f"DEBUG: Checking statement: {type(stmt).__name__}")
            # Look for NamespaceDefStatement that matches our target
            if isinstance(stmt, NamespaceDefStatement):
                #print(f"DEBUG: Found NamespaceDefStatement: {stmt.namespace_def.name}")
                # Get the mangled name (how it was stored during codegen)
                mangled_name = stmt.namespace_def.name.replace('::', '__')
                target_mangled = target_namespace.replace('::', '__')
                #print(f"DEBUG: Comparing {mangled_name} with {target_mangled}")
                
                # Check if this namespace matches our target
                if mangled_name == target_mangled or stmt.namespace_def.name == target_namespace:
                    #print(f"DEBUG: Match found! Generating code for namespace")
                    # Generate code for this namespace now
                    stmt.namespace_def.codegen(builder, module)
                    break
                # Check if this is a parent namespace that contains our target
                elif target_namespace.startswith(stmt.namespace_def.name + '::'):
                    #print(f"DEBUG: Parent namespace found, processing contents")
                    # This is a parent namespace, process its contents
                    self._process_namespace_contents(stmt.namespace_def, target_namespace, builder, module)
            
            # Look for nested namespace definitions within other statements
            elif hasattr(stmt, 'namespace_def') and hasattr(stmt.namespace_def, 'nested_namespaces'):
                #print(f"DEBUG: Checking nested namespaces in statement")
                # Recursively search nested namespaces
                for nested_ns in stmt.namespace_def.nested_namespaces:
                    self._process_statements_for_namespace([NamespaceDefStatement(nested_ns)], target_namespace, builder, module)
            
            # Direct NamespaceDef objects (handle both wrapped and unwrapped)
            elif hasattr(stmt, '__class__') and stmt.__class__.__name__ == 'NamespaceDef':
                #print(f"DEBUG: Found direct NamespaceDef: {stmt.name}")
                # Get the mangled name (how it was stored during codegen)
                mangled_name = stmt.name.replace('::', '__')
                target_mangled = target_namespace.replace('::', '__')
                #print(f"DEBUG: Comparing direct {mangled_name} with {target_mangled}")
                
                # Check if this namespace matches our target
                if mangled_name == target_mangled or stmt.name == target_namespace:
                    #print(f"DEBUG: Direct match found! Generating code for namespace")
                    # Generate code for this namespace now
                    stmt.codegen(builder, module)
                    break
                # Check if this is a parent namespace that contains our target
                elif target_namespace.startswith(stmt.name + '::'):
                    #print(f"DEBUG: Direct parent namespace found, processing contents")
                    # This is a parent namespace, process its contents
                    self._process_namespace_contents(stmt, target_namespace, builder, module)

    def _process_namespace_contents(self, namespace_def, target_namespace, builder, module):
        """Process contents of a namespace looking for nested namespaces that match our target"""
        #print(f"DEBUG: Processing namespace contents for {namespace_def.name}, looking for {target_namespace}")
        # Look through nested namespaces
        for nested_ns in namespace_def.nested_namespaces:
            #print(f"DEBUG: Checking nested namespace: {nested_ns.name}")
            # Construct the full nested namespace path
            full_nested_name = f"{namespace_def.name}::{nested_ns.name}"
            #print(f"DEBUG: Full nested name: {full_nested_name}")
            if full_nested_name == target_namespace:
                # Found the target namespace - generate its code
                #print(f"DEBUG: Found target namespace {target_namespace}, generating code")
                # IMPORTANT: Before generating the target namespace, first process its dependencies
                # by recursively processing any using statements it contains
                self._process_namespace_dependencies(nested_ns, builder, module)
                nested_ns.codegen(builder, module)
                break
            elif target_namespace.startswith(full_nested_name + '::'):
                # This nested namespace is a parent of our target, recurse deeper
                #print(f"DEBUG: Recursing deeper into {full_nested_name}")
                self._process_namespace_contents(nested_ns, target_namespace, builder, module)

    def _process_namespace_dependencies(self, namespace_def, builder, module):
        """Process all dependencies of a namespace before generating its code"""
        #print(f"DEBUG: Processing dependencies for namespace {namespace_def.name}")
        
        # Look through all variables in this namespace to find using statements
        # In the AST structure, using statements might be within the namespace variables
        # or we need to check the imported symbols for dependencies
        
        # For the standard::io namespace, we know it depends on standard::types
        # Let's check if standard::types needs to be processed first
        if namespace_def.name == 'io' and hasattr(module, '_using_namespaces'):
            if 'standard::types' in module._using_namespaces:
                #print(f"DEBUG: Processing standard::types dependency first")
                # Find and process standard::types
                if hasattr(module, '_imported_symbols'):
                    for import_path, statements in module._imported_symbols.items():
                        for stmt in statements:
                            if hasattr(stmt, '__class__') and stmt.__class__.__name__ == 'NamespaceDef':
                                if stmt.name == 'standard':
                                    # Found the standard namespace, look for types nested namespace
                                    for nested_ns in stmt.nested_namespaces:
                                        if nested_ns.name == 'types':
                                            #print(f"DEBUG: Generating code for standard::types dependency")
                                            # Generate the types namespace first
                                            nested_ns.codegen(builder, module)
                                            return

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
            with open(resolved_path, 'r', encoding='ascii') as f:
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
            
            # Process imports in the imported module
            for stmt in imported_ast.statements:
                if isinstance(stmt, ImportStatement):
                    stmt.codegen(import_builder, module)
            
            # Pre-register namespace definitions to make them available for using statements
            # This registers namespace names without generating code yet
            for stmt in imported_ast.statements:
                # Handle both NamespaceDefStatement and direct NamespaceDef objects
                namespace_def = None
                if isinstance(stmt, NamespaceDefStatement):
                    namespace_def = stmt.namespace_def
                elif hasattr(stmt, '__class__') and stmt.__class__.__name__ == 'NamespaceDef':
                    # Direct NamespaceDef object
                    namespace_def = stmt
                
                if namespace_def is not None:
                    # Register the namespace and its nested namespaces
                    if not hasattr(module, '_namespaces'):
                        module._namespaces = set()
                    module._namespaces.add(namespace_def.name)
                    
                    # Register nested namespaces with their full qualified names
                    for nested_ns in namespace_def.nested_namespaces:
                        full_nested_name = f"{namespace_def.name}::{nested_ns.name}"
                        module._namespaces.add(full_nested_name)
                        # Recursively register deeper nested namespaces
                        self._register_nested_namespaces_for_import(nested_ns, full_nested_name, module)
            
            # Store metadata about exported symbols but DON'T generate code yet
            # This metadata will be used later by UsingStatement to create aliases
            if not hasattr(module, '_imported_symbols'):
                module._imported_symbols = {}
            
            # Store the AST for later code generation when used
            module._imported_symbols[str(resolved_path)] = imported_ast.statements

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

    def _register_nested_namespaces_for_import(self, namespace, parent_path, module):
        """Recursively register all nested namespaces with their full qualified names for imported modules"""
        for nested_ns in namespace.nested_namespaces:
            full_nested_name = f"{parent_path}::{nested_ns.name}"
            module._namespaces.add(full_nested_name)
            self._register_nested_namespaces_for_import(nested_ns, full_nested_name, module)

    def _resolve_path(self, module_name: str) -> Optional[Path]:
        """Robust path resolution with proper error handling"""
        try:
            # Check direct path first
            if (path := Path(module_name)).exists():
                return path.resolve()

            # Check in standard locations
            search_paths = [
                Path.cwd(),
                Path.cwd() / "lib",
                Path(__file__).parent.parent / "stdlib",  # src/stdlib directory
                Path(__file__).parent.parent / "lib",
                Path.home() / ".flux" / "lib",
                Path("/usr/local/lib/flux"),
                Path("/usr/lib/flux")
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