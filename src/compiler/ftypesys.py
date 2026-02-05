#!/usr/bin/env python3
"""
Flux Type System

Copyright (C) 2026 Karac Thweatt

Contributors:
    Piotr Bednarski
"""

from dataclasses import dataclass, field
from typing import List, Any, Optional, Union, Dict, Tuple
from enum import Enum
from llvmlite import ir


class DataType(Enum):
    SINT = "int"
    UINT = "uint"
    FLOAT = "float"
    CHAR = "char"
    BOOL = "bool"
    DATA = "data"
    STRUCT = "struct"
    ENUM = "enum"
    UNION = "union"
    OBJECT = "object"
    VOID = "void"
    THIS = "this"


class StorageClass(Enum):
    AUTO = "auto"
    STACK = "stack"
    HEAP = "heap"
    GLOBAL = "global"
    LOCAL = "local"
    REGISTER = "register"


@dataclass
class BaseType:
    """Base type representation"""
    
    def to_llvm(self, module: ir.Module) -> ir.Type:
        raise NotImplementedError(f"to_llvm not implemented for {self.__class__.__name__}")
    
    def __str__(self) -> str:
        raise NotImplementedError(f"__str__ not implemented for {self.__class__.__name__}")


@dataclass
class PrimitiveType(BaseType):
    kind: DataType
    width: Optional[int] = None
    signed: bool = True
    
    def to_llvm(self, module: ir.Module) -> ir.Type:
        if self.kind == DataType.SINT:
            return ir.IntType(self.width or 32)
        elif self.kind == DataType.UINT:
            return ir.IntType(self.width or 32)
        elif self.kind == DataType.FLOAT:
            return ir.FloatType()
        elif self.kind == DataType.BOOL:
            return ir.IntType(1)
        elif self.kind == DataType.CHAR:
            return ir.IntType(8)
        elif self.kind == DataType.VOID:
            return ir.VoidType()
        elif self.kind == DataType.DATA:
            if self.width is None:
                raise ValueError(f"DATA type requires explicit width")
            return ir.IntType(self.width)
        else:
            raise ValueError(f"Unsupported primitive type: {self.kind}")
    
    def __str__(self) -> str:
        if self.kind == DataType.DATA and self.width:
            return f"data{{{self.width}}}"
        return self.kind.value


@dataclass
class PointerType(BaseType):
    pointee: BaseType
    
    def to_llvm(self, module: ir.Module) -> ir.Type:
        pointee_llvm = self.pointee.to_llvm(module)
        if isinstance(self.pointee, PrimitiveType) and self.pointee.kind == DataType.VOID:
            return ir.PointerType(ir.IntType(8))
        return ir.PointerType(pointee_llvm)
    
    def __str__(self) -> str:
        return f"{self.pointee}*"


@dataclass
class ArrayType(BaseType):
    element: BaseType
    dimensions: List[Optional[int]]
    
    def to_llvm(self, module: ir.Module) -> ir.Type:
        element_llvm = self.element.to_llvm(module)
        current_type = element_llvm
        
        for dim in reversed(self.dimensions):
            if dim is not None:
                current_type = ir.ArrayType(current_type, dim)
            else:
                current_type = ir.PointerType(current_type)
        
        return current_type
    
    def __str__(self) -> str:
        dims = ''.join(f'[{d if d else ""}]' for d in self.dimensions)
        return f"{self.element}{dims}"


@dataclass
class NamedType(BaseType):
    name: str
    
    def to_llvm(self, module: ir.Module) -> ir.Type:
        resolved = TypeResolver.resolve(self.name, module)
        if resolved is None:
            raise NameError(f"Unknown type: {self.name}")
        return resolved
    
    def __str__(self) -> str:
        return self.name


@dataclass
class StructType(BaseType):
    name: str
    
    def to_llvm(self, module: ir.Module) -> ir.Type:
        if hasattr(module, '_struct_types') and self.name in module._struct_types:
            return module._struct_types[self.name]
        raise NameError(f"Unknown struct type: {self.name}")
    
    def __str__(self) -> str:
        return f"struct {self.name}"


@dataclass
class EnumType():
    name: str


@dataclass
class FunctionType(BaseType):
    return_type: BaseType
    parameters: List[BaseType]
    
    def to_llvm(self, module: ir.Module) -> ir.FunctionType:
        ret_type = self.return_type.to_llvm(module)
        param_types = [p.to_llvm(module) for p in self.parameters]
        return ir.FunctionType(ret_type, param_types)
    
    def __str__(self) -> str:
        params = ', '.join(str(p) for p in self.parameters)
        return f"({params}) -> {self.return_type}"


@dataclass
class QualifiedType(BaseType):
    base: BaseType
    is_const: bool = False
    is_volatile: bool = False
    storage_class: Optional[StorageClass] = None
    
    def to_llvm(self, module: ir.Module) -> ir.Type:
        return self.base.to_llvm(module)
    
    def __str__(self) -> str:
        parts = []
        if self.storage_class:
            parts.append(self.storage_class.value)
        if self.is_const:
            parts.append("const")
        if self.is_volatile:
            parts.append("volatile")
        parts.append(str(self.base))
        return ' '.join(parts)


class TypeResolver:
    """Resolves named types and handles namespace lookups"""
    
    @staticmethod
    def resolve(typename: str, module: ir.Module) -> Optional[ir.Type]:
        if hasattr(module, '_type_aliases') and typename in module._type_aliases:
            base_type = module._type_aliases[typename]
            if isinstance(base_type, ir.ArrayType):
                return ir.PointerType(base_type.element)
            return base_type
        
        if hasattr(module, '_struct_types') and typename in module._struct_types:
            return module._struct_types[typename]
        
        if hasattr(module, '_using_namespaces'):
            for namespace in module._using_namespaces:
                mangled_name = namespace.replace('::', '__') + '__' + typename
                
                if hasattr(module, '_type_aliases') and mangled_name in module._type_aliases:
                    base_type = module._type_aliases[mangled_name]
                    if isinstance(base_type, ir.ArrayType):
                        return ir.PointerType(base_type.element)
                    return base_type
                
                if hasattr(module, '_struct_types') and mangled_name in module._struct_types:
                    return module._struct_types[mangled_name]
        
        if hasattr(module, '_namespaces'):
            for registered_namespace in module._namespaces:
                mangled_name = registered_namespace.replace('::', '__') + '__' + typename
                
                if hasattr(module, '_type_aliases') and mangled_name in module._type_aliases:
                    base_type = module._type_aliases[mangled_name]
                    if isinstance(base_type, ir.ArrayType):
                        return ir.PointerType(base_type.element)
                    return base_type
                
                if hasattr(module, '_struct_types') and mangled_name in module._struct_types:
                    return module._struct_types[mangled_name]
        
        if hasattr(module, '_using_namespaces'):
            for namespace in module._using_namespaces:
                namespace_parts = namespace.split('::')
                for i in range(len(namespace_parts), 0, -1):
                    parent_namespace = '::'.join(namespace_parts[:i])
                    mangled_name = parent_namespace.replace('::', '__') + '__' + typename
                    
                    if hasattr(module, '_type_aliases') and mangled_name in module._type_aliases:
                        base_type = module._type_aliases[mangled_name]
                        if isinstance(base_type, ir.ArrayType):
                            return ir.PointerType(base_type.element)
                        return base_type
                    
                    if hasattr(module, '_struct_types') and mangled_name in module._struct_types:
                        return module._struct_types[mangled_name]
        
        return None


class TypeChecker:
    """Type compatibility and casting validation"""
    
    @staticmethod
    def is_compatible(source: BaseType, target: BaseType) -> bool:
        if isinstance(source, PrimitiveType) and isinstance(target, PrimitiveType):
            if source.kind == target.kind:
                return True
            if source.kind in (DataType.SINT, DataType.UINT) and target.kind in (DataType.SINT, DataType.UINT):
                return True
        
        if isinstance(source, PointerType) and isinstance(target, PointerType):
            return TypeChecker.is_compatible(source.pointee, target.pointee)
        
        if type(source) == type(target):
            return True
        
        return False
    
    @staticmethod
    def can_cast(source: BaseType, target: BaseType) -> bool:
        if isinstance(source, PrimitiveType) and isinstance(target, PrimitiveType):
            return True
        
        if isinstance(source, PointerType) or isinstance(target, PointerType):
            return True
        
        return False
    
    @staticmethod
    def common_type(a: BaseType, b: BaseType) -> BaseType:
        if isinstance(a, PrimitiveType) and isinstance(b, PrimitiveType):
            if a.kind == DataType.FLOAT or b.kind == DataType.FLOAT:
                return PrimitiveType(DataType.FLOAT)
            
            if a.kind == DataType.UINT or b.kind == DataType.UINT:
                max_width = max(a.width or 32, b.width or 32)
                return PrimitiveType(DataType.UINT, width=max_width)
            
            max_width = max(a.width or 32, b.width or 32)
            return PrimitiveType(DataType.SINT, width=max_width)
        
        return a


@dataclass
class TypeSpec:
    """Legacy TypeSpec for backward compatibility - will be phased out"""
    base_type: Union[DataType, str]
    is_signed: bool = True
    is_const: bool = False
    is_volatile: bool = False
    bit_width: Optional[int] = None
    alignment: Optional[int] = None
    endianness: Optional[int] = 0
    is_array: bool = False
    array_size: Optional[Union[int, Any]] = None  # Can be int literal or Expression (evaluated at runtime if needed)
    array_dimensions: Optional[List[Optional[Union[int, Any]]]] = None  # Same for multi-dimensional arrays
    is_pointer: bool = False
    pointer_depth: int = 0
    custom_typename: Optional[str] = None
    storage_class: Optional[StorageClass] = None
    
    def to_new_type(self) -> BaseType:
        """Convert TypeSpec to new Type system"""
        base = None
        
        if self.custom_typename:
            base = NamedType(self.custom_typename)
        elif isinstance(self.base_type, DataType):
            base = PrimitiveType(self.base_type, self.bit_width, self.is_signed)
        else:
            base = NamedType(self.base_type)
        
        if self.is_array and self.array_dimensions:
            base = ArrayType(base, self.array_dimensions)
        elif self.is_array and self.array_size:
            base = ArrayType(base, [self.array_size])
        
        if self.is_pointer:
            base = PointerType(base)
        
        if self.is_const or self.is_volatile or self.storage_class:
            base = QualifiedType(base, self.is_const, self.is_volatile, self.storage_class)
        
        return base
    
    def get_llvm_type(self, module: ir.Module) -> ir.Type:
        if self.custom_typename:
            if hasattr(module, '_type_aliases') and self.custom_typename in module._type_aliases:
                base_type = module._type_aliases[self.custom_typename]
                if isinstance(base_type, ir.ArrayType) and not self.is_array:
                    return ir.PointerType(base_type.element)
                return base_type

            if hasattr(module, '_enum_types') and self.custom_typename in module._enum_types:
                return ir.IntType(32)
            
            if hasattr(module, '_struct_types') and self.custom_typename in module._struct_types:
                return module._struct_types[self.custom_typename]
            
            if hasattr(module, '_union_types') and self.custom_typename in module._union_types:
                return module._union_types[self.custom_typename]
            
            if hasattr(module, '_using_namespaces'):
                for namespace in module._using_namespaces:
                    mangled_name = namespace.replace('::', '__') + '__' + self.custom_typename
                    
                    if hasattr(module, '_type_aliases') and mangled_name in module._type_aliases:
                        base_type = module._type_aliases[mangled_name]
                        if isinstance(base_type, ir.ArrayType) and not self.is_array:
                            return ir.PointerType(base_type.element)
                        return base_type
                    
                    if hasattr(module, '_struct_types') and mangled_name in module._struct_types:
                        return module._struct_types[mangled_name]
                    
                    if hasattr(module, '_union_types') and mangled_name in module._union_types:
                        return module._union_types[mangled_name]
            
            if hasattr(module, '_namespaces'):
                for registered_namespace in module._namespaces:
                    mangled_name = registered_namespace.replace('::', '__') + '__' + self.custom_typename
                    
                    if hasattr(module, '_type_aliases') and mangled_name in module._type_aliases:
                        base_type = module._type_aliases[mangled_name]
                        if isinstance(base_type, ir.ArrayType) and not self.is_array:
                            return ir.PointerType(base_type.element)
                        return base_type
                    
                    if hasattr(module, '_struct_types') and mangled_name in module._struct_types:
                        return module._struct_types[mangled_name]
                    
                    if hasattr(module, '_union_types') and mangled_name in module._union_types:
                        return module._union_types[mangled_name]
            
            if hasattr(module, '_using_namespaces'):
                for namespace in module._using_namespaces:
                    namespace_parts = namespace.split('::')
                    for i in range(len(namespace_parts), 0, -1):
                        parent_namespace = '::'.join(namespace_parts[:i])
                        mangled_name = parent_namespace.replace('::', '__') + '__' + self.custom_typename
                        
                        if hasattr(module, '_type_aliases') and mangled_name in module._type_aliases:
                            base_type = module._type_aliases[mangled_name]
                            if isinstance(base_type, ir.ArrayType) and not self.is_array:
                                return ir.PointerType(base_type.element)
                            return base_type
                        
                        if hasattr(module, '_struct_types') and mangled_name in module._struct_types:
                            return module._struct_types[mangled_name]
                        
                        if hasattr(module, '_union_types') and mangled_name in module._union_types:
                            return module._union_types[mangled_name]
            
            raise NameError(f"Unknown type: {self.custom_typename}")
        
        if self.base_type == DataType.SINT:
            return ir.IntType(32)
        elif self.base_type == DataType.UINT:
            return ir.IntType(32)
        elif self.base_type == DataType.FLOAT:
            return ir.FloatType()
        elif self.base_type == DataType.BOOL:
            return ir.IntType(1)
        elif self.base_type == DataType.CHAR:
            return ir.IntType(8)
        elif self.base_type == DataType.STRUCT:
            return ir.IntType(8)
        elif self.base_type == DataType.ENUM:
            return ir.IntType(32)
        elif self.base_type == DataType.VOID:
            return ir.VoidType()
        elif self.base_type == DataType.DATA:
            if self.bit_width is None:
                raise ValueError(f"DATA type missing bit_width for {self}")
            return ir.IntType(self.bit_width)
        else:
            raise ValueError(f"Unsupported type: {self.base_type}")
    
    def get_llvm_type_with_array(self, module: ir.Module) -> ir.Type:
        base_type = self.get_llvm_type(module)
        
        if self.is_pointer:
            if self.base_type == DataType.VOID or self.base_type == DataType.STRUCT:
                return ir.PointerType(ir.IntType(8))
            return ir.PointerType(base_type)
        
        if self.is_array and self.array_dimensions:
            current_type = base_type
            for dim in reversed(self.array_dimensions):
                if dim is not None:
                    # Only handle compile-time constant dimensions
                    if isinstance(dim, int):
                        current_type = ir.ArrayType(current_type, dim)
                    else:
                        # Runtime size - return pointer to element type
                        # The actual allocation will be handled in _codegen_local
                        return ir.PointerType(base_type)
                else:
                    current_type = ir.PointerType(current_type)
            return current_type
        elif self.is_array:
            if self.array_size is not None:
                # Check if it's a compile-time constant
                if isinstance(self.array_size, int):
                    return ir.ArrayType(base_type, self.array_size)
                else:
                    # Runtime size - return pointer to element type
                    # The actual allocation will be handled in _codegen_local
                    return ir.PointerType(base_type)
            else:
                if isinstance(base_type, ir.PointerType):
                    return base_type
                else:
                    return ir.PointerType(base_type)
        
        if self.is_pointer:
            return ir.PointerType(base_type)
        
        return base_type


class FunctionPointerType:
    return_type: TypeSpec
    parameter_types: List[TypeSpec]
    
    def get_llvm_type(self, module: ir.Module) -> ir.FunctionType:
        ret_type = self.return_type.get_llvm_type(module)
        param_types = [param.get_llvm_type(module) for param in self.parameter_types]
        return ir.FunctionType(ret_type, param_types)
    
    def get_llvm_pointer_type(self, module: ir.Module) -> ir.PointerType:
        func_type = self.get_llvm_type(module)
        return ir.PointerType(func_type)

class VariableTypeHandler:
    """Handles all type-related operations for variable declarations"""
    
    @staticmethod
    def resolve_type_spec(type_spec: TypeSpec, initial_value, module: ir.Module) -> TypeSpec:
        """Resolve type spec with automatic array size inference for string literals."""
        # Import here to avoid circular dependency
        from fast import StringLiteral
        
        if not (initial_value and isinstance(initial_value, StringLiteral)):
            return type_spec
        
        # Direct array type check
        if type_spec.is_array and type_spec.array_size is None:
            return TypeSpec(
                base_type=type_spec.base_type,
                is_signed=type_spec.is_signed,
                is_const=type_spec.is_const,
                is_volatile=type_spec.is_volatile,
                bit_width=type_spec.bit_width or 8,
                alignment=type_spec.alignment,
                is_array=True,
                array_size=len(initial_value.value),
                is_pointer=type_spec.is_pointer,
                custom_typename=type_spec.custom_typename
            )
        
        # Type alias check
        if type_spec.custom_typename:
            try:
                resolved_llvm_type = type_spec.get_llvm_type(module)
                if (isinstance(resolved_llvm_type, ir.PointerType) and 
                    isinstance(resolved_llvm_type.pointee, ir.IntType) and 
                    resolved_llvm_type.pointee.width == 8):
                    return TypeSpec(
                        base_type=DataType.DATA,
                        is_signed=False,
                        is_const=type_spec.is_const,
                        is_volatile=type_spec.is_volatile,
                        bit_width=8,
                        alignment=type_spec.alignment,
                        is_array=True,
                        array_size=len(initial_value.value),
                        is_pointer=False
                    )
            except (NameError, AttributeError):
                pass
        
        return type_spec
    
    @staticmethod
    def create_global_initializer(initial_value, llvm_type: ir.Type, module: ir.Module) -> Optional[ir.Constant]:
        """Create compile-time constant initializer for global variable."""
        # Import here to avoid circular dependency
        from fast import (Literal, Identifier, BinaryOp, UnaryOp, StringLiteral, 
                         ArrayLiteral, ArrayAccess, DataType as FastDataType)
        
        # Handle different expression types
        if isinstance(initial_value, Literal):
            return VariableTypeHandler._literal_to_constant(initial_value, llvm_type)
        
        elif isinstance(initial_value, Identifier):
            return VariableTypeHandler._identifier_to_constant(initial_value, module)
        
        elif isinstance(initial_value, BinaryOp):
            return VariableTypeHandler._eval_const_expr(initial_value, module)
        
        elif isinstance(initial_value, UnaryOp):
            return VariableTypeHandler._eval_const_expr(initial_value, module)
        
        elif isinstance(initial_value, StringLiteral):
            return ArrayTypeHandler.create_global_string_initializer(
                initial_value.value, llvm_type
            )
        
        elif isinstance(initial_value, ArrayLiteral):
            # Check if target is an integer (bitfield packing) or an array
            if isinstance(llvm_type, ir.IntType):
                # Pack array into integer for bitfield initialization
                return VariableTypeHandler._pack_array_literal_to_int_constant(
                    initial_value, llvm_type, module
                )
            else:
                return ArrayTypeHandler.create_global_array_initializer(
                    initial_value, llvm_type, module
                )
        
        elif isinstance(initial_value, ArrayAccess):
            return VariableTypeHandler._eval_array_access_const(initial_value, module)
        
        return None
    
    @staticmethod
    def _eval_array_access_const(array_access, module: ir.Module) -> Optional[ir.Constant]:
        """Evaluate array indexing at compile time for global initialization."""
        from fast import Identifier, Literal, DataType as FastDataType
        
        # Get the array being indexed
        if not isinstance(array_access.array, Identifier):
            return None  # Can only index into named globals at compile time
        
        array_name = array_access.array.name
        if array_name not in module.globals:
            return None
        
        global_array = module.globals[array_name]
        if not hasattr(global_array, 'initializer') or global_array.initializer is None:
            return None
        
        # Get the index
        if not isinstance(array_access.index, Literal) or array_access.index.type != FastDataType.SINT:
            return None  # Can only use constant integer indices at compile time
        
        index_value = array_access.index.value
        
        # Extract the element from the constant array
        array_const = global_array.initializer
        if isinstance(array_const.type, ir.ArrayType):
            if 0 <= index_value < len(array_const.constant):
                return array_const.constant[index_value]
        
        return None
    
    @staticmethod
    def _pack_array_literal_to_int_constant(array_literal, target_type: ir.IntType, 
                                           module: ir.Module) -> Optional[ir.Constant]:
        """Pack an array literal into an integer constant for global bitfield initialization."""
        from fast import Literal, Identifier
        
        packed_value = 0
        bit_offset = 0
        
        # Pack in reverse order: first element at high bits, last element at low bits (big-endian)
        for elem in reversed(array_literal.elements):
            # Get the constant value and bit width
            if isinstance(elem, Literal):
                elem_val = elem.value
                # Default to 32-bit for literals unless we can infer better
                elem_width = 32
            elif isinstance(elem, Identifier):
                # Look up the global variable
                var_name = elem.name
                if var_name not in module.globals:
                    return None  # Can't resolve at compile time
                
                global_var = module.globals[var_name]
                if not hasattr(global_var, 'initializer') or global_var.initializer is None:
                    return None
                
                elem_val = global_var.initializer.constant
                
                # Get actual bit width from the global variable's type
                if isinstance(global_var.type, ir.PointerType):
                    actual_type = global_var.type.pointee
                else:
                    actual_type = global_var.type
                
                if isinstance(actual_type, ir.IntType):
                    elem_width = actual_type.width
                else:
                    return None  # Not an integer type
            else:
                return None  # Can't evaluate at compile time
            
            # Pack the value
            packed_value |= (elem_val << bit_offset)
            bit_offset += elem_width
        
        # Verify total bits match target
        if bit_offset != target_type.width:
            raise ValueError(
                f"Bitfield packing size mismatch: packed {bit_offset} bits into {target_type.width}-bit integer"
            )
        
        return ir.Constant(target_type, packed_value)
    
    @staticmethod
    def _literal_to_constant(lit, llvm_type: ir.Type) -> ir.Constant:
        """Convert literal to LLVM constant."""
        from fast import DataType as FastDataType
        
        if lit.type == FastDataType.SINT:
            return ir.Constant(llvm_type, lit.value)
        elif lit.type == FastDataType.FLOAT:
            return ir.Constant(llvm_type, lit.value)
        elif lit.type == FastDataType.BOOL:
            return ir.Constant(llvm_type, 1 if lit.value else 0)
        return None
    
    @staticmethod
    def _identifier_to_constant(ident, module: ir.Module) -> Optional[ir.Constant]:
        """Get constant from identifier (reference to another global)."""
        var_name = ident.name
        if var_name in module.globals:
            other_global = module.globals[var_name]
            if hasattr(other_global, 'initializer') and other_global.initializer:
                return other_global.initializer
        
        # Check namespace-qualified names
        if hasattr(module, '_using_namespaces'):
            for namespace in module._using_namespaces:
                mangled_name = namespace.replace('::', '__') + '__' + var_name
                if mangled_name in module.globals:
                    other_global = module.globals[mangled_name]
                    if hasattr(other_global, 'initializer') and other_global.initializer:
                        return other_global.initializer
        
        return None
    
    @staticmethod
    def _eval_const_expr(expr, module: ir.Module) -> Optional[ir.Constant]:
        """Recursively evaluate constant expressions at compile time."""
        from fast import Literal, Identifier, BinaryOp, UnaryOp, DataType as FastDataType
        
        if isinstance(expr, Literal):
            if expr.type == FastDataType.SINT:
                return ir.Constant(ir.IntType(32), expr.value)
            elif expr.type == FastDataType.FLOAT:
                return ir.Constant(ir.FloatType(), expr.value)
            elif expr.type == FastDataType.BOOL:
                return ir.Constant(ir.IntType(1), 1 if expr.value else 0)
            return None
        
        elif isinstance(expr, Identifier):
            return VariableTypeHandler._identifier_to_constant(expr, module)
        
        elif isinstance(expr, BinaryOp):
            left = VariableTypeHandler._eval_const_expr(expr.left, module)
            right = VariableTypeHandler._eval_const_expr(expr.right, module)
            
            if left is None or right is None:
                return None
            
            return VariableTypeHandler._eval_binary_op(left, right, expr.operator)
        
        elif isinstance(expr, UnaryOp):
            operand = VariableTypeHandler._eval_const_expr(expr.operand, module)
            
            if operand is None:
                return None
            
            return VariableTypeHandler._eval_unary_op(operand, expr.operator)
        
        return None
    
    @staticmethod
    def _eval_binary_op(left: ir.Constant, right: ir.Constant, op) -> Optional[ir.Constant]:
        """Evaluate binary operation on constants."""
        from fast import Operator
        
        if isinstance(left.type, ir.IntType):
            ops = {
                Operator.ADD: lambda l, r: l + r,
                Operator.SUB: lambda l, r: l - r,
                Operator.MUL: lambda l, r: l * r,
                Operator.DIV: lambda l, r: l // r,
                Operator.MOD: lambda l, r: l % r,
                Operator.POWER: lambda l, r: l ** r,
                Operator.AND: lambda l, r: l & r,
                Operator.OR: lambda l, r: l | r,
                Operator.XOR: lambda l, r: l ^ r,
                Operator.BITSHIFT_LEFT: lambda l, r: l << r,
                Operator.BITSHIFT_RIGHT: lambda l, r: l >> r,
            }
            if op in ops:
                result = ops[op](left.constant, right.constant)
                return ir.Constant(left.type, result)
        
        elif isinstance(left.type, ir.FloatType):
            ops = {
                Operator.ADD: lambda l, r: l + r,
                Operator.SUB: lambda l, r: l - r,
                Operator.MUL: lambda l, r: l * r,
                Operator.DIV: lambda l, r: l / r,
                Operator.MOD: lambda l, r: l % r,
                Operator.POWER: lambda l, r: l ** r,
            }
            if op in ops:
                result = ops[op](left.constant, right.constant)
                return ir.Constant(left.type, result)
        
        return None
    
    @staticmethod
    def _eval_unary_op(operand: ir.Constant, op) -> Optional[ir.Constant]:
        """Evaluate unary operation on constant."""
        from fast import Operator
        
        if isinstance(operand.type, ir.IntType):
            if op == Operator.SUB:
                result = -operand.constant
            elif op == Operator.NOT:
                result = ~operand.constant
            else:
                return None
            return ir.Constant(operand.type, result)
        
        elif isinstance(operand.type, ir.FloatType):
            if op == Operator.SUB:
                result = -operand.constant
            else:
                return None
            return ir.Constant(operand.type, result)
        
        return None
    
    @staticmethod
    def store_with_type_conversion(builder: ir.IRBuilder, alloca: ir.Value, 
                                   llvm_type: ir.Type, init_val: ir.Value,
                                   initial_value, module: ir.Module) -> None:
        """Store value with automatic type conversion if needed."""
        from fast import CastExpression, BinaryOp, Operator, ArrayLiteral
        from futilities import is_unsigned
        
        # Handle special case: cast expression to array
        if (isinstance(initial_value, CastExpression) and
            isinstance(init_val.type, ir.PointerType) and
            isinstance(llvm_type, ir.ArrayType)):
            array_ptr_type = ir.PointerType(llvm_type)
            casted_ptr = builder.bitcast(init_val, array_ptr_type, name="cast_to_array_ptr")
            array_value = builder.load(casted_ptr, name="loaded_array")
            builder.store(array_value, alloca)
            return
        
        # Handle type mismatch
        if init_val.type != llvm_type:
            # Special case: array concatenation result to array variable
            # e.g., int[2] b = [a[0]] + [1];
            # init_val.type is [2 x i32]* (pointer), llvm_type is [2 x i32] (value)
            if (isinstance(initial_value, BinaryOp) and 
                initial_value.operator in (Operator.ADD, Operator.SUB) and
                isinstance(init_val.type, ir.PointerType) and 
                isinstance(init_val.type.pointee, ir.ArrayType) and
                isinstance(llvm_type, ir.ArrayType)):
                # Load the array value from the concat result pointer and store it
                array_value = builder.load(init_val, name="concat_array_value")
                builder.store(array_value, alloca)
                return

            # Special case: array concatenation result
            if (isinstance(initial_value, BinaryOp) and 
                initial_value.operator in (Operator.ADD, Operator.SUB) and
                isinstance(init_val.type, ir.PointerType) and 
                isinstance(init_val.type.pointee, ir.ArrayType) and
                isinstance(llvm_type, ir.PointerType) and 
                isinstance(llvm_type.pointee, ir.IntType)):
                zero = ir.Constant(ir.IntType(32), 0)
                array_ptr = builder.gep(init_val, [zero, zero], name="concat_array_to_ptr")
                builder.store(array_ptr, alloca)
                return
            
            # Pointer to array to integer packing (for bitfield initialization)
            if (isinstance(init_val.type, ir.PointerType) and 
                isinstance(init_val.type.pointee, ir.ArrayType) and 
                isinstance(llvm_type, ir.IntType)):
                # Pack array bits into integer
                init_val = ArrayTypeHandler.pack_array_pointer_to_integer(
                    builder, module, init_val, llvm_type
                )
            
            # Pointer to integer conversion (addresses are just numbers in Flux)
            elif isinstance(init_val.type, ir.PointerType) and isinstance(llvm_type, ir.IntType):
                init_val = builder.ptrtoint(init_val, llvm_type, name="ptr_to_int")
            
            # Integer to pointer conversion
            elif isinstance(init_val.type, ir.IntType) and isinstance(llvm_type, ir.PointerType):
                init_val = builder.inttoptr(init_val, llvm_type, name="int_to_ptr")
            
            # Pointer type conversion
            elif isinstance(llvm_type, ir.PointerType) and isinstance(init_val.type, ir.PointerType):
                if llvm_type.pointee != init_val.type.pointee:
                    init_val = builder.bitcast(init_val, llvm_type)

                elif isinstance(init_val.type.pointee, ir.ArrayType):
                    # Pack array bits into integer
                    init_val = ArrayTypeHandler.pack_array_pointer_to_integer(
                        builder, module, init_val, llvm_type
                    )

            # Integer type conversion
            elif isinstance(init_val.type, ir.IntType) and isinstance(llvm_type, ir.IntType):
                if init_val.type.width > llvm_type.width:
                    init_val = builder.trunc(init_val, llvm_type)
                elif init_val.type.width < llvm_type.width:
                    # Use zext for unsigned, sext for signed
                    if is_unsigned(init_val):
                        init_val = builder.zext(init_val, llvm_type)
                    else:
                        init_val = builder.sext(init_val, llvm_type)
            
            # Int to float conversion
            elif isinstance(init_val.type, ir.IntType) and isinstance(llvm_type, ir.FloatType):
                init_val = builder.sitofp(init_val, llvm_type)
            
            # Float to int conversion
            elif isinstance(init_val.type, ir.FloatType) and isinstance(llvm_type, ir.IntType):
                init_val = builder.fptosi(init_val, llvm_type)
        
        # Preserve _flux_type_spec metadata if present on init_val
        # This helps maintain signedness through store/load cycles
        if hasattr(init_val, '_flux_type_spec'):
            # Store metadata on the alloca so it can be retrieved on loads
            if not hasattr(alloca, '_flux_type_spec'):
                alloca._flux_type_spec = init_val._flux_type_spec
        
        builder.store(init_val, alloca)

class ArrayTypeHandler:
    """
    Handles all array type operations and conversions.
    
    This includes:
    - Array type checking and information
    - Array concatenation (compile-time and runtime)
    - Array resizing for assignment
    - Array slicing
    - Array initialization (global and local)
    - Array packing into integers (for bitfields)
    - Memory operations (memcpy, memset)
    """
    
    @staticmethod
    def is_array_or_array_pointer(val: ir.Value) -> bool:
        """Check if value is an array type or a pointer to an array type."""
        return (isinstance(val.type, ir.ArrayType) or 
                (isinstance(val.type, ir.PointerType) and 
                 isinstance(val.type.pointee, ir.ArrayType)))
    
    @staticmethod
    def is_array_pointer(val: ir.Value) -> bool:
        """Check if value is a pointer to an array type."""
        return (isinstance(val.type, ir.PointerType) and 
                isinstance(val.type.pointee, ir.ArrayType))
    
    @staticmethod
    def get_array_info(val: ir.Value) -> Tuple[ir.Type, int]:
        """Get (element_type, length) for array or array pointer."""
        if isinstance(val.type, ir.ArrayType):
            # Direct array type (loaded from a pointer)
            return (val.type.element, val.type.count)
        elif isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, ir.ArrayType):
            # Pointer to array type
            array_type = val.type.pointee
            return (array_type.element, array_type.count)
        else:
            raise ValueError(f"Value is not an array or array pointer: {val.type}")
    
    @staticmethod
    def emit_memcpy(builder: ir.IRBuilder, module: ir.Module, dst_ptr: ir.Value, src_ptr: ir.Value, bytes: int) -> None:
        """Emit llvm.memcpy intrinsic call."""
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
    
    @staticmethod
    def emit_memset(builder: ir.IRBuilder, module: ir.Module, dst_ptr: ir.Value, value: int, bytes: int) -> None:
        """Emit llvm.memset intrinsic call."""
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
        
        # Cast pointer to i8* if needed
        i8_ptr = ir.PointerType(ir.IntType(8))
        if dst_ptr.type != i8_ptr:
            dst_ptr = builder.bitcast(dst_ptr, i8_ptr)
        
        # Call memset
        builder.call(memset_func, [
            dst_ptr,
            ir.Constant(ir.IntType(8), value),
            ir.Constant(ir.IntType(64), bytes),
            ir.Constant(ir.IntType(1), 0)  # not volatile
        ])
    
    @staticmethod
    def concatenate(builder: ir.IRBuilder, module: ir.Module, 
                   left_val: ir.Value, right_val: ir.Value, 
                   operator) -> ir.Value:
        """
        Handle array concatenation (+ and -) operations.
        
        Args:
            builder: IR builder
            module: LLVM module
            left_val: Left operand (array or array pointer)
            right_val: Right operand (array or array pointer)
            operator: ADD for concatenation, SUB for truncation
            
        Returns:
            Pointer to new concatenated/truncated array
        """
        from fast import Operator
        
        # Get array information
        left_elem_type, left_len = ArrayTypeHandler.get_array_info(left_val)
        right_elem_type, right_len = ArrayTypeHandler.get_array_info(right_val)
        
        # Type compatibility check
        if left_elem_type != right_elem_type:
            raise ValueError(f"Cannot {operator.value} arrays with different element types: {left_elem_type} vs {right_elem_type}")
        
        # Calculate result length
        if operator == Operator.ADD:
            result_len = left_len + right_len
        else:  # SUB
            result_len = max(left_len - right_len, 0)
        
        # Create result array type
        result_array_type = ir.ArrayType(left_elem_type, result_len)
        
        # Check if both operands are global constants for compile-time concatenation
        if (isinstance(left_val, ir.GlobalVariable) and 
            isinstance(right_val, ir.GlobalVariable) and 
            getattr(left_val, 'global_constant', False) and 
            getattr(right_val, 'global_constant', False)):
            # Compile-time concatenation
            return ArrayTypeHandler.create_global_array_concat(
                module, left_val, right_val, result_array_type, operator
            )
        else:
            # Runtime concatenation
            return ArrayTypeHandler.create_runtime_array_concat(
                builder, module, left_val, right_val, result_array_type, operator
            )
    
    @staticmethod
    def create_global_array_concat(module: ir.Module, left_val: ir.Value, 
                                    right_val: ir.Value, result_array_type: ir.ArrayType, 
                                    operator) -> ir.Value:
        """Create compile-time array concatenation for global constants."""
        from fast import Operator
        
        # Get the initializers from both global constants
        left_init = left_val.initializer if hasattr(left_val, 'initializer') else None
        right_init = right_val.initializer if hasattr(right_val, 'initializer') else None
        
        if left_init is None or right_init is None:
            raise ValueError("Both operands must be global constants for compile-time concatenation")
        
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
        global_name = f".array_concat_{id(module)}_{id(left_val)}_{id(right_val)}"
        global_array = ir.GlobalVariable(module, result_array_type, name=global_name)
        global_array.linkage = 'internal'
        global_array.global_constant = True
        global_array.initializer = ir.Constant(result_array_type, new_elements)
        
        # Mark as array pointer
        global_array.type._is_array_pointer = True
        
        return global_array
    
    @staticmethod
    def create_runtime_array_concat(builder: ir.IRBuilder, module: ir.Module, 
                                     left_val: ir.Value, right_val: ir.Value, 
                                     result_array_type: ir.ArrayType, 
                                     operator) -> ir.Value:
        """Create runtime array concatenation using memcpy."""
        from fast import Operator
        
        # Get array info
        left_elem_type, left_len = ArrayTypeHandler.get_array_info(left_val)
        right_elem_type, right_len = ArrayTypeHandler.get_array_info(right_val)
        
        # Calculate element size in bytes
        elem_size_bytes = left_elem_type.width // 8
        
        # Allocate new array for result
        result_ptr = builder.alloca(result_array_type, name="array_concat_result")
        
        # Copy left array to result
        if left_len > 0:
            # Get pointer to first element of result array
            zero = ir.Constant(ir.IntType(32), 0)
            result_start = builder.gep(result_ptr, [zero, zero], name="result_start")
            
            # Get pointer to source array start
            left_start = builder.gep(left_val, [zero, zero], name="left_start")
            
            # Copy left array
            left_bytes = left_len * elem_size_bytes
            ArrayTypeHandler.emit_memcpy(builder, module, result_start, left_start, left_bytes)
        
        # Copy right array to result (for ADD operation)
        if operator == Operator.ADD and right_len > 0:
            zero = ir.Constant(ir.IntType(32), 0)
            # Get pointer to position after left array in result
            left_len_const = ir.Constant(ir.IntType(32), left_len)
            result_right_start = builder.gep(result_ptr, [zero, left_len_const], name="result_right_start")
            
            # Get pointer to source array start
            right_start = builder.gep(right_val, [zero, zero], name="right_start")
            
            # Copy right array
            right_bytes = right_len * elem_size_bytes
            ArrayTypeHandler.emit_memcpy(builder, module, result_right_start, right_start, right_bytes)
        
        # Mark as array pointer
        result_ptr.type._is_array_pointer = True
        
        return result_ptr
    
    @staticmethod
    def resize_for_assignment(builder: ir.IRBuilder, module: ir.Module, 
                             ptr: ir.Value, val: ir.Value, 
                             var_name: str = None) -> ir.Value:
        """
        Dynamically resize arrays to accommodate new values during assignment.
        
        Args:
            builder: IR builder
            module: LLVM module
            ptr: Pointer to existing array
            val: New value to assign (array)
            var_name: Optional variable name for scope updates
            
        Returns:
            Pointer to resized array (may be same as ptr if no resize needed)
        """
        # Get array information
        val_elem_type, val_len = ArrayTypeHandler.get_array_info(val)
        ptr_elem_type, ptr_len = ArrayTypeHandler.get_array_info(ptr)
        
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
                ArrayTypeHandler.emit_memcpy(builder, module, new_start, old_start, old_bytes)
            
            # Copy new data to the new array (overwriting all elements)
            new_bytes = val_len * (val_elem_type.width // 8)
            zero = ir.Constant(ir.IntType(32), 0)
            new_start = builder.gep(new_alloca, [zero, zero], name="new_start")
            val_start = builder.gep(val, [zero, zero], name="val_start")
            ArrayTypeHandler.emit_memcpy(builder, module, new_start, val_start, new_bytes)
            
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
            ArrayTypeHandler.emit_memcpy(builder, module, ptr_start, val_start, copy_bytes)
            
            # If the new array is smaller, zero out the remaining elements
            if val_len < ptr_len:
                remaining_bytes = (ptr_len - val_len) * (ptr_elem_type.width // 8)
                if remaining_bytes > 0:
                    # Get pointer to remaining area
                    val_len_const = ir.Constant(ir.IntType(32), val_len)
                    remaining_start = builder.gep(ptr, [zero, val_len_const], name="remaining_start")
                    
                    # Zero out remaining bytes
                    ArrayTypeHandler.emit_memset(builder, module, remaining_start, 0, remaining_bytes)
            
            return ptr
    
    @staticmethod
    def slice_array(builder: ir.IRBuilder, module: ir.Module, 
                   array_val: ir.Value, start_val: ir.Value, end_val: ir.Value,
                   is_reverse: bool = False) -> ir.Value:
        """
        Extract array slice with optional reverse.
        
        Args:
            builder: IR builder
            module: LLVM module
            array_val: Source array
            start_val: Start index (i32)
            end_val: End index (i32, inclusive)
            is_reverse: True for reverse slicing (e.g., s[3..0])
            
        Returns:
            Pointer to new array containing the slice
        """
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
        
        # Create fixed-size array to hold the slice
        max_slice_size = 256  # Should be enough for most string operations
        slice_array_type = ir.ArrayType(element_type, max_slice_size)
        slice_ptr = builder.alloca(slice_array_type, name="slice_array")
        
        # Get pointer to the start of the source array/string
        zero = ir.Constant(ir.IntType(32), 0)
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
    
    @staticmethod
    def create_global_string_initializer(string_value: str, llvm_type: ir.Type) -> Optional[ir.Constant]:
        """Create a compile-time constant initializer for a global string."""
        if isinstance(llvm_type, ir.ArrayType) and \
           isinstance(llvm_type.element, ir.IntType) and \
           llvm_type.element.width == 8:
            
            string_val = string_value
            char_values = []
            for i, char in enumerate(string_val):
                if i >= llvm_type.count:
                    break
                char_values.append(ir.Constant(ir.IntType(8), ord(char)))
            while len(char_values) < llvm_type.count:
                char_values.append(ir.Constant(ir.IntType(8), 0))
            return ir.Constant(llvm_type, char_values)
        
        return None

    @staticmethod
    def create_global_array_initializer(array_literal, llvm_type: ir.Type, 
                                        module: ir.Module) -> Optional[ir.Constant]:
        """Create a compile-time constant initializer for a global array."""
        from fast import StringLiteral, Literal, DataType as FastDataType, Identifier
        
        if not isinstance(llvm_type, ir.ArrayType):
            return None
        
        const_elements = []
        for elem in array_literal.elements:
            # Pack StringLiteral into integer
            if isinstance(elem, StringLiteral) and isinstance(llvm_type.element, ir.IntType):
                string_val = elem.value
                byte_count = min(len(string_val), llvm_type.element.width // 8)
                packed_value = 0
                for j in range(byte_count):
                    packed_value |= (ord(string_val[j]) << (j * 8))
                const_elements.append(ir.Constant(llvm_type.element, packed_value))
            
            # Pack nested ArrayLiteral into integer
            elif hasattr(elem, 'elements') and isinstance(llvm_type.element, ir.IntType):
                # Pack the array elements into a single integer constant
                packed_value = 0
                bit_offset = 0  # Start from low bits
                
                for inner_elem in reversed(elem.elements):
                    # For global constants, we need constant values
                    if isinstance(inner_elem, Literal):
                        if inner_elem.type == FastDataType.INT or inner_elem.type == FastDataType.SINT:
                            elem_val = inner_elem.value
                            elem_width = 32  # This is wrong - need to infer from context
                        else:
                            raise ValueError(f"Cannot pack {inner_elem.type} in global array initializer")
                    elif isinstance(inner_elem, Identifier):
                        # Look up the global constant value
                        var_name = inner_elem.name
                        if var_name in module.globals:
                            global_var = module.globals[var_name]
                            if hasattr(global_var, 'initializer') and global_var.initializer:
                                elem_val = global_var.initializer.constant
                                # Get the actual type width from the global variable's type
                                if isinstance(global_var.type, ir.PointerType):
                                    actual_type = global_var.type.pointee
                                else:
                                    actual_type = global_var.type
                                
                                if isinstance(actual_type, ir.IntType):
                                    elem_width = actual_type.width
                                else:
                                    raise ValueError(f"Global {var_name} is not an integer type: {actual_type}")
                            else:
                                raise ValueError(f"Global {var_name} has no initializer")
                        else:
                            raise ValueError(f"Global {var_name} not found")
                    else:
                        raise ValueError(f"Cannot evaluate {type(inner_elem)} at compile time for global array")
                    
                    # Pack in reverse order: last element at low bits
                    packed_value |= (elem_val << bit_offset)
                    bit_offset += elem_width
                
                # Verify we used all the bits
                if bit_offset != llvm_type.element.width:
                    raise ValueError(
                        f"Bit offset mismatch after packing: expected {llvm_type.element.width}, got {bit_offset}"
                    )
                
                const_elements.append(ir.Constant(llvm_type.element, packed_value))

            elif isinstance(elem, Literal):
                if elem.type == FastDataType.SINT or elem.type == FastDataType.UINT:
                    const_elements.append(ir.Constant(llvm_type.element, elem.value))
                elif elem.type == FastDataType.FLOAT:
                    const_elements.append(ir.Constant(llvm_type.element, elem.value))
                elif elem.type == FastDataType.BOOL:
                    const_elements.append(ir.Constant(llvm_type.element, 1 if elem.value else 0))
            else:
                # Can't evaluate at compile time
                const_elements.append(ir.Constant(llvm_type.element, 0))
        
        return ir.Constant(llvm_type, const_elements)

    @staticmethod
    def initialize_local_array(builder: ir.IRBuilder, module: ir.Module, 
                              alloca: ir.Value, llvm_type: ir.Type, 
                              array_literal) -> None:
        """Initialize a local array variable with an array literal."""
        from fast import StringLiteral
        
        if not isinstance(llvm_type, ir.ArrayType):
            raise ValueError(f"ArrayLiteral can only initialize array types, got {llvm_type}")
        
        # Initialize each array element individually
        for i, elem in enumerate(array_literal.elements):
            zero = ir.Constant(ir.IntType(32), 0)
            index = ir.Constant(ir.IntType(32), i)
            elem_ptr = builder.gep(alloca, [zero, index], inbounds=True, name=f"elem_{i}")
            
            # Generate code for each element
            # Handle packing strings to integers
            if isinstance(elem, StringLiteral) and isinstance(llvm_type.element, ir.IntType):
                string_val = elem.value
                byte_count = min(len(string_val), llvm_type.element.width // 8)
                packed_value = 0
                for j in range(byte_count):
                    packed_value |= (ord(string_val[j]) << (j * 8))
                elem_val = ir.Constant(llvm_type.element, packed_value)
            
            # Handle packing array literals to integers
            elif hasattr(elem, 'elements') and isinstance(llvm_type.element, ir.IntType):
                # This is an array that needs to be packed into an integer
                elem_val = ArrayTypeHandler.pack_array_to_integer(builder, module, elem, llvm_type.element)
            
            else:
                elem_val = elem.codegen(builder, module)
                
                # Handle result being an array pointer that needs packing
                if (isinstance(elem_val.type, ir.PointerType) and 
                    isinstance(elem_val.type.pointee, ir.ArrayType) and
                    isinstance(llvm_type.element, ir.IntType)):
                    # Load and pack the array into the target integer
                    elem_val = ArrayTypeHandler.pack_array_pointer_to_integer(
                        builder, module, elem_val, llvm_type.element
                    )
            
            # Ensure type matches
            if elem_val.type != llvm_type.element:
                if isinstance(elem_val.type, ir.IntType) and isinstance(llvm_type.element, ir.IntType):
                    if elem_val.type.width > llvm_type.element.width:
                        elem_val = builder.trunc(elem_val, llvm_type.element)
                    elif elem_val.type.width < llvm_type.element.width:
                        elem_val = builder.sext(elem_val, llvm_type.element)
            
            builder.store(elem_val, elem_ptr)

    @staticmethod
    def pack_array_to_integer(builder: ir.IRBuilder, module: ir.Module, 
                               array_lit, target_type: ir.IntType) -> ir.Value:
        """Pack an array literal's elements into a single integer."""
        packed_value = 0
        bit_offset = 0
        
        for elem in array_lit.elements:
            elem_val = elem.codegen(builder, module)
            
            # Load if it's a pointer
            if isinstance(elem_val.type, ir.PointerType):
                elem_val = builder.load(elem_val)
            
            # Must be an integer
            if not isinstance(elem_val.type, ir.IntType):
                raise ValueError(f"Cannot pack non-integer type {elem_val.type} into integer")
            
            elem_width = elem_val.type.width
            
            # Convert to runtime packing if not constant
            if not isinstance(elem_val, ir.Constant):
                return ArrayTypeHandler.pack_array_to_integer_runtime(
                    builder, module, array_lit, target_type
                )
            
            # Pack constant value
            packed_value |= (elem_val.constant << bit_offset)
            bit_offset += elem_width
        
        # Verify total width matches target
        if bit_offset != target_type.width:
            raise ValueError(
                f"Array packing size mismatch: packed {bit_offset} bits into {target_type.width}-bit integer"
            )
        
        return ir.Constant(target_type, packed_value)

    @staticmethod
    def pack_array_to_integer_runtime(builder: ir.IRBuilder,
                                       module: ir.Module,
                                       array_lit, 
                                       target_type: ir.IntType) -> ir.Value:
        """Pack array elements into integer at runtime."""
        result = ir.Constant(target_type, 0)
        bit_offset = 0
        
        for elem in array_lit.elements:
            elem_val = elem.codegen(builder, module)
            
            # Load if it's a pointer
            if isinstance(elem_val.type, ir.PointerType):
                elem_val = builder.load(elem_val)
            
            # Must be an integer
            if not isinstance(elem_val.type, ir.IntType):
                raise ValueError(f"Cannot pack non-integer type {elem_val.type} into integer")
            
            elem_width = elem_val.type.width
            
            # Extend/truncate to target width if needed
            if elem_val.type.width != target_type.width:
                elem_val = builder.zext(elem_val, target_type)
            
            # Shift into position
            if bit_offset > 0:
                shift_amount = ir.Constant(target_type, bit_offset)
                elem_val = builder.shl(elem_val, shift_amount)
            
            # OR into result
            result = builder.or_(result, elem_val)
            bit_offset += elem_width
        
        return result

    @staticmethod
    def pack_array_pointer_to_integer(builder: ir.IRBuilder, module: ir.Module,
                                       array_ptr: ir.Value, target_type: ir.IntType) -> ir.Value:
        """Pack an array (via pointer) into a single integer at runtime."""
        if not isinstance(array_ptr.type, ir.PointerType):
            raise ValueError("Expected pointer to array")
        
        if not isinstance(array_ptr.type.pointee, ir.ArrayType):
            raise ValueError("Expected pointer to array type")
        
        array_type = array_ptr.type.pointee
        elem_type = array_type.element
        
        if not isinstance(elem_type, ir.IntType):
            raise ValueError(f"Cannot pack array of non-integer type {elem_type}")
        
        # Calculate expected total bits
        total_bits = array_type.count * elem_type.width
        if total_bits != target_type.width:
            raise ValueError(
                f"Array packing size mismatch: {array_type.count} x {elem_type.width} = {total_bits} bits "
                f"into {target_type.width}-bit integer"
            )
        
        # Pack at runtime (big-endian: first element at high bits, last at low bits)
        result = ir.Constant(target_type, 0)
        bit_offset = 0
        
        zero = ir.Constant(ir.IntType(32), 0)
        # Iterate in reverse: last element goes to low bits
        for i in range(array_type.count - 1, -1, -1):
            index = ir.Constant(ir.IntType(32), i)
            elem_ptr = builder.gep(array_ptr, [zero, index], inbounds=True)
            elem_val = builder.load(elem_ptr)
            
            # Extend to target width
            if elem_type.width != target_type.width:
                elem_val = builder.zext(elem_val, target_type)
            
            # Shift into position
            if bit_offset > 0:
                shift_amount = ir.Constant(target_type, bit_offset)
                elem_val = builder.shl(elem_val, shift_amount)
            
            # OR into result
            result = builder.or_(result, elem_val)
            bit_offset += elem_type.width
        
        return result

    @staticmethod
    def initialize_local_string(builder: ir.IRBuilder, module: ir.Module, 
                               alloca: ir.Value, llvm_type: ir.Type, 
                               string_literal) -> None:
        """Initialize a local variable with a string literal."""
        string_val = string_literal.value
        
        # Case 1: Pointer to i8 (char*)
        if isinstance(llvm_type, ir.PointerType) and \
           isinstance(llvm_type.pointee, ir.IntType) and \
           llvm_type.pointee.width == 8:
            
            # Store string data on stack
            string_bytes = string_val.encode('ascii')
            str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
            
            str_alloca = builder.alloca(str_array_ty, name="str_data")
            
            for i, byte_val in enumerate(string_bytes):
                zero = ir.Constant(ir.IntType(32), 0)
                index = ir.Constant(ir.IntType(32), i)
                elem_ptr = builder.gep(str_alloca, [zero, index], name=f"char_{i}")
                char_val = ir.Constant(ir.IntType(8), byte_val)
                builder.store(char_val, elem_ptr)
            
            zero = ir.Constant(ir.IntType(32), 0)
            str_ptr = builder.gep(str_alloca, [zero, zero], name="str_ptr")
            builder.store(str_ptr, alloca)
        
        # Case 2: Array of i8 (char[N])
        elif isinstance(llvm_type, ir.ArrayType) and \
             isinstance(llvm_type.element, ir.IntType) and \
             llvm_type.element.width == 8:
            
            for i, char in enumerate(string_val):
                if i >= llvm_type.count:
                    break
                
                zero = ir.Constant(ir.IntType(32), 0)
                index = ir.Constant(ir.IntType(32), i)
                elem_ptr = builder.gep(alloca, [zero, index], name=f"char_{i}")
                
                char_val = ir.Constant(ir.IntType(8), ord(char))
                builder.store(char_val, elem_ptr)
            
            # Null-terminate remaining
            for i in range(len(string_val), llvm_type.count):
                zero = ir.Constant(ir.IntType(32), 0)
                index = ir.Constant(ir.IntType(32), i)
                elem_ptr = builder.gep(alloca, [zero, index], name=f"char_{i}")
                zero_char = ir.Constant(ir.IntType(8), 0)
                builder.store(zero_char, elem_ptr)

    @staticmethod
    def create_local_string_for_arg(builder: ir.IRBuilder, module: ir.Module, 
                                    string_value: str, name_hint: str) -> ir.Value:
        """Create a local string on the stack for passing as an argument."""
        string_bytes = string_value.encode('ascii')
        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
        
        str_alloca = builder.alloca(str_array_ty, name=f"{name_hint}_str_data")
        
        for j, byte_val in enumerate(string_bytes):
            zero = ir.Constant(ir.IntType(32), 0)
            index = ir.Constant(ir.IntType(32), j)
            elem_ptr = builder.gep(str_alloca, [zero, index])
            char_val = ir.Constant(ir.IntType(8), byte_val)
            builder.store(char_val, elem_ptr)
        
        zero = ir.Constant(ir.IntType(32), 0)
        str_ptr = builder.gep(str_alloca, [zero, zero], name=f"{name_hint}_str_ptr")
        return str_ptr

    @staticmethod
    def copy_array_to_local(builder: ir.IRBuilder, module: ir.Module, 
                           alloca: ir.Value, llvm_type: ir.Type, 
                           source_identifier) -> None:
        """Copy an array from one variable to another."""
        # Get the source array
        init_val = source_identifier.codegen(builder, module)
        
        # Check if it's an array type
        if not (isinstance(init_val.type, ir.PointerType) and 
                isinstance(init_val.type.pointee, ir.ArrayType)):
            raise ValueError(f"Cannot initialize array from non-array type: {init_val.type}")
        
        # Copy array element by element
        source_array_type = init_val.type.pointee
        copy_count = min(llvm_type.count, source_array_type.count)
        
        zero = ir.Constant(ir.IntType(32), 0)
        for i in range(copy_count):
            index = ir.Constant(ir.IntType(32), i)
            # Load from source
            src_ptr = builder.gep(init_val, [zero, index], inbounds=True, name=f"src_{i}")
            src_val = builder.load(src_ptr, name=f"val_{i}")
            # Store to destination
            dst_ptr = builder.gep(alloca, [zero, index], inbounds=True, name=f"dst_{i}")
            builder.store(src_val, dst_ptr)


class LiteralTypeHandler:
    """Handles type resolution and LLVM type determination for literal values"""
    
    @staticmethod
    def get_llvm_type(literal_type: DataType, literal_value: Any, module: ir.Module) -> ir.Type:
        """
        Determine the LLVM type for a literal based on its DataType and value.
        
        Args:
            literal_type: The DataType of the literal
            literal_value: The actual value of the literal
            module: LLVM module (for type aliases)
            
        Returns:
            LLVM IR type for the literal
        """
        from futilities import infer_int_width
        
        if literal_type in (DataType.SINT, DataType.UINT):
            val = int(literal_value, 0) if isinstance(literal_value, str) else int(literal_value)
            width = infer_int_width(val, literal_type)
            return ir.IntType(width)
        elif literal_type == DataType.FLOAT:
            return ir.FloatType()
        elif literal_type == DataType.BOOL:
            return ir.IntType(1)
        elif literal_type == DataType.CHAR:
            return ir.IntType(8)
        elif literal_type == DataType.VOID:
            return ir.IntType(1)
        elif literal_type == DataType.DATA:
            return LiteralTypeHandler._get_data_llvm_type(literal_value, literal_type, module)
        else:
            # Handle custom types
            return LiteralTypeHandler._get_custom_llvm_type(literal_value, literal_type, module)
    
    @staticmethod
    def _get_data_llvm_type(literal_value: Any, literal_type: DataType, module: ir.Module) -> ir.Type:
        """Get LLVM type for DATA type literals."""
        # Handle array literals
        if isinstance(literal_value, list):
            raise ValueError("Array literals should be handled at a higher level")
        
        # Handle struct literals (dictionaries with field names -> values)
        if isinstance(literal_value, dict):
            struct_type = LiteralTypeHandler.resolve_struct_type(literal_value, module)
            return struct_type
        
        # Handle other DATA types via type aliases
        if hasattr(module, '_type_aliases') and str(literal_type) in module._type_aliases:
            return module._type_aliases[str(literal_type)]
        
        raise ValueError(f"Unsupported DATA literal: {literal_value}")
    
    @staticmethod
    def _get_custom_llvm_type(literal_value: Any, literal_type: DataType, module: ir.Module) -> ir.Type:
        """Get LLVM type for custom type literals."""
        if hasattr(module, '_type_aliases') and str(literal_type) in module._type_aliases:
            return module._type_aliases[str(literal_type)]
        raise ValueError(f"Unsupported literal type: {literal_type}")
    
    @staticmethod
    def resolve_struct_type(literal_value: dict, module: ir.Module):
        """
        Resolve the struct type for a struct literal based on its field names.
        
        Args:
            literal_value: Dictionary mapping field names to values
            module: LLVM module containing struct type definitions
            
        Returns:
            LLVM struct type
            
        Raises:
            ValueError: If no compatible struct type is found
        """
        if not isinstance(literal_value, dict):
            raise ValueError("Expected dictionary for struct literal")
        
        field_names = list(literal_value.keys())
        
        if hasattr(module, '_struct_types'):
            for struct_name, candidate_type in module._struct_types.items():
                if hasattr(candidate_type, 'names'):
                    # Check if all fields in the literal exist in this struct
                    if all(field in candidate_type.names for field in field_names):
                        return candidate_type
        
        raise ValueError(f"No compatible struct type found for fields: {field_names}")
    
    @staticmethod
    def normalize_int_value(literal_value: Any, literal_type: DataType, width: int) -> int:
        """
        Normalize integer value for LLVM constant creation.
        Handles unsigned types with values >= 2^63 by converting to signed equivalent.
        
        Args:
            literal_value: The integer value (int or str)
            literal_type: SINT or UINT
            width: Bit width (32 or 64)
            
        Returns:
            Normalized integer value for LLVM IR constant
        """
        val = int(literal_value, 0) if isinstance(literal_value, str) else int(literal_value)
        
        # For unsigned types with values >= 2^63, ensure proper handling
        if literal_type == DataType.UINT and width == 64 and val >= (1 << 63):
            # Convert to signed equivalent for LLVM (two's complement)
            # LLVM stores 0xFFFFFFFFFFFFFFFF as -1 internally
            return val if val < (1 << 63) else val - (1 << 64)
        
        return val
    
    @staticmethod
    def normalize_char_value(literal_value: Any) -> int:
        """
        Normalize character value for LLVM constant creation.
        
        Args:
            literal_value: Character value (str or int)
            
        Returns:
            Integer value (0-255) for the character
        """
        if isinstance(literal_value, str):
            if len(literal_value) == 0:
                # Handle empty string - return null character
                return 0
            else:
                return ord(literal_value[0])
        else:
            return literal_value
    
    @staticmethod
    def get_struct_field_type(struct_type, field_name: str) -> ir.Type:
        """
        Get the LLVM type of a specific field in a struct.
        
        Args:
            struct_type: LLVM struct type
            field_name: Name of the field
            
        Returns:
            LLVM type of the field
            
        Raises:
            ValueError: If field is not found in struct
        """
        if not hasattr(struct_type, 'names'):
            raise ValueError("Struct type does not have field names")
        
        if field_name not in struct_type.names:
            raise ValueError(f"Field '{field_name}' not found in struct")
        
        field_index = struct_type.names.index(field_name)
        return struct_type.elements[field_index]
    
    @staticmethod
    def is_string_pointer_field(field_type: ir.Type) -> bool:
        """
        Check if a field type is a pointer to i8 (string pointer).
        
        Args:
            field_type: LLVM type of the field
            
        Returns:
            True if field is i8* (char*), False otherwise
        """
        return (isinstance(field_type, ir.PointerType) and
                isinstance(field_type.pointee, ir.IntType) and
                field_type.pointee.width == 8)