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


class Operator(Enum):
    """Operator enumeration (imported for constant evaluation)"""
    ADD = "+"
    SUB = "-"
    MUL = "*"
    DIV = "/"
    MOD = "%"
    NOT = "!"
    POWER = "^"
    XOR = "^^"
    OR = "|"
    AND = "&"
    BITOR = "`|"
    BITAND = "`&"
    NOR = "!|"
    NAND = "!&"
    INCREMENT = "++"
    DECREMENT = "--"
    
    EQUAL = "=="
    NOT_EQUAL = "!="
    LESS_THAN = "<"
    LESS_EQUAL = "<="
    GREATER_THAN = ">"
    GREATER_EQUAL = ">="
    
    BITSHIFT_LEFT = "<<"
    BITSHIFT_RIGHT = ">>"
    
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
    
    ADDRESS_OF = "@"
    RANGE = ".."
    SCOPE = "::"
    QUESTION = "?"
    COLON = ":"
    
    RETURN_ARROW = "->"
    CHAIN_ARROW = "<-"


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


class IdentifierTypeHandler:
    """Handles type resolution and metadata attachment for identifiers"""
    
    @staticmethod
    def get_type_spec(name: str, builder: ir.IRBuilder, module: ir.Module):
        """
        Get the TypeSpec for an identifier from scope or global type info.
        
        Args:
            name: The identifier name
            builder: LLVM IR builder (for scope access)
            module: LLVM module (for global type info)
            
        Returns:
            TypeSpec if found, None otherwise
        """
        # Check local scope first
        if builder.scope is not None:
            if hasattr(builder, 'scope_type_info') and name in builder.scope_type_info:
                return builder.scope_type_info[name]
        
        # Check global type info
        if hasattr(module, '_global_type_info') and name in module._global_type_info:
            return module._global_type_info[name]
        
        return None
    
    @staticmethod
    def should_return_pointer(llvm_value: ir.Value) -> bool:
        """
        Determine if an identifier should return a pointer (not load).
        Arrays and structs return pointers; other types are loaded.
        
        Args:
            llvm_value: The LLVM value (typically from scope or globals)
            
        Returns:
            True if should return pointer, False if should load
        """
        # For arrays, return the pointer directly (don't load)
        if isinstance(llvm_value.type, ir.PointerType) and isinstance(llvm_value.type.pointee, ir.ArrayType):
            return True
        
        # For structs, return the pointer directly (don't load)
        if isinstance(llvm_value.type, ir.PointerType) and isinstance(llvm_value.type.pointee, ir.LiteralStructType):
            return True
        
        return False
    
    @staticmethod
    def attach_type_metadata(llvm_value: ir.Value, type_spec) -> ir.Value:
        """
        Attach TypeSpec metadata to an LLVM value if not already present.
        
        Args:
            llvm_value: The LLVM value to attach metadata to
            type_spec: The TypeSpec to attach (or None)
            
        Returns:
            The same llvm_value with metadata attached
        """
        if type_spec and not hasattr(llvm_value, '_flux_type_spec'):
            llvm_value._flux_type_spec = type_spec
        return llvm_value
    
    @staticmethod
    def is_volatile(name: str, builder: ir.IRBuilder) -> bool:
        """
        Check if an identifier is marked as volatile.
        
        Args:
            name: The identifier name
            builder: LLVM IR builder
            
        Returns:
            True if volatile, False otherwise
        """
        return hasattr(builder, 'volatile_vars') and name in getattr(builder, 'volatile_vars', set())
    
    @staticmethod
    def check_validity(name: str, builder: ir.IRBuilder) -> None:
        """
        Check if an identifier is valid (not moved/tied).
        
        Args:
            name: The identifier name
            builder: LLVM IR builder
            
        Raises:
            RuntimeError: If variable was moved (use after tie)
        """
        if (hasattr(builder, 'object_validity_flags') and 
            name in builder.object_validity_flags):
            error_msg = f"COMPILE ERROR: Use after tie: variable '{name}' was moved"
            print(error_msg)
            raise RuntimeError(error_msg)
    
    @staticmethod
    def resolve_namespace_mangled_name(name: str, module: ir.Module) -> Optional[str]:
        """
        Resolve an identifier using namespace 'using' statements.
        
        Args:
            name: The unqualified identifier name
            module: LLVM module containing _using_namespaces
            
        Returns:
            Mangled name if found in a using namespace, None otherwise
        """
        if not hasattr(module, '_using_namespaces'):
            return None
        
        for namespace in module._using_namespaces:
            # Convert namespace path to mangled name format
            mangled_prefix = namespace.replace('::', '__') + '__'
            mangled_name = mangled_prefix + name
            
            # Check in global variables with mangled name
            if mangled_name in module.globals:
                return mangled_name
            
            # Check in type aliases with mangled name
            if hasattr(module, '_type_aliases') and mangled_name in module._type_aliases:
                return mangled_name
        
        return None
    
    @staticmethod
    def is_type_alias(name: str, module: ir.Module) -> bool:
        """
        Check if an identifier is a custom type alias.
        
        Args:
            name: The identifier name
            module: LLVM module
            
        Returns:
            True if name is a type alias, False otherwise
        """
        return hasattr(module, '_type_aliases') and name in module._type_aliases


class LoweringContext:
    def __init__(instance, builder: ir.IRBuilder):
        instance.b = builder

    # --------------------------------------------------
    # Signedness
    # --------------------------------------------------

    @staticmethod
    def is_unsigned(val: ir.Value) -> bool:
        spec = getattr(val, "_flux_type_spec", None)
        return spec is not None and not spec.is_signed

    @staticmethod
    def comparison_is_unsigned(a: ir.Value, b: ir.Value) -> bool:
        return LoweringContext.is_unsigned(a) or LoweringContext.is_unsigned(b)

    # --------------------------------------------------
    # Integer normalization
    # --------------------------------------------------

    def normalize_ints(instance, a: ir.Value, b: ir.Value, *, unsigned: bool, promote: bool):
        """
        Normalize two integer values to the same width.
        
        Args:
            a, b: Integer values to normalize
            unsigned: Whether to use unsigned extension semantics when extending
            promote: If True, normalize to MAXIMUM width (for arithmetic/bitwise/comparisons).
                     If False, normalize to MINIMUM width (for bitshifts only).
        
        Context:
            - Bitshift operations (<<, >>): promote=False (shift amount matches value width)
            - All other operations: promote=True (preserve full range and precision)
        """
        assert isinstance(a.type, ir.IntType)
        assert isinstance(b.type, ir.IntType)

        if a.type.width == b.type.width:
            return a, b

        # Promote to max for arithmetic/bitwise, lower to min for bitshifts
        width = max(a.type.width, b.type.width) if promote else min(a.type.width, b.type.width)
        ty = ir.IntType(width)

        def convert(v):
            #direction = "PROMOTING" if promote else "LOWERING"
            #print(f"{direction} NORMALIZE", v.type, v.type.width, ty, width)
            if v.type.width == width:
                return v
            elif v.type.width < width:
                # Extending to larger width
                result = instance.b.zext(v, ty) if unsigned else instance.b.zext(v, ty)
            else:
                # Truncating to smaller width
                result = instance.b.trunc(v, ty)
            
            # Preserve _flux_type_spec metadata
            if hasattr(v, '_flux_type_spec'):
                result._flux_type_spec = v._flux_type_spec
                # Update bit width to match new type
                result._flux_type_spec.bit_width = width
            
            return result

        return convert(a), convert(b)

    # --------------------------------------------------
    # Pointer helpers
    # --------------------------------------------------

    def ptr_to_i64(instance, v: ir.Value) -> ir.Value:
        if isinstance(v.type, ir.PointerType):
            return instance.b.ptrtoint(v, ir.IntType(64))
        return v

    # --------------------------------------------------
    # Comparisons
    # --------------------------------------------------

    def emit_int_cmp(instance, op: str, a: ir.Value, b: ir.Value):
        unsigned = instance.comparison_is_unsigned(a, b)
        a, b = instance.normalize_ints(a, b, unsigned=unsigned, promote=True)
        return (
            instance.b.icmp_unsigned(op, a, b)
            if unsigned
            else instance.b.icmp_signed(op, a, b)
        )

    def emit_ptr_cmp(instance, op: str, a: ir.Value, b: ir.Value):
        # Explicit raw-address semantics
        a = instance.ptr_to_i64(a)
        b = instance.ptr_to_i64(b)
        return instance.b.icmp_unsigned(op, a, b)


def infer_int_width(value: int, data_type: DataType) -> int:
    """
    Infer the integer width (32 or 64 bits) based on value and type.
    
    Args:
        value: The integer value
        data_type: SINT or UINT
        
    Returns:
        32 or 64 (bit width)
        
    Raises:
        ValueError: If data_type is not an integer type
    """
    if data_type == DataType.SINT:
        if -(1 << 31) <= value <= (1 << 31) - 1:
            return 32
        else:
            return 64
    elif data_type == DataType.UINT:
        if 0 <= value <= (1 << 32) - 1:
            return 32
        else:
            return 64
    else:
        raise ValueError("Not an integer literal")


def attach_type_metadata(llvm_value: ir.Value, type_spec: Optional[Any] = None, 
                        base_type: Optional[DataType] = None) -> ir.Value:
    """
    Attach Flux type information to LLVM value for proper signedness tracking.
    
    Args:
        llvm_value: The LLVM value to annotate
        type_spec: Optional TypeSpec object
        base_type: Optional DataType for creating default TypeSpec
        
    Returns:
        The same llvm_value with metadata attached
    """
    bit_width = llvm_value.type.width if hasattr(llvm_value.type, 'width') else None
    
    if type_spec is None and base_type is not None:
        # Create a minimal TypeSpec-like structure
        type_spec = type(
            'TypeSpec',
            (),
            {
                'base_type': base_type,
                'is_signed': (base_type == DataType.SINT),
                'bit_width': bit_width
            }
        )()
    
    if type_spec is not None:
        llvm_value._flux_type_spec = type_spec
    
    return llvm_value


def is_unsigned(val: ir.Value) -> bool:
    """
    Determine if an LLVM value represents an unsigned integer.
    
    Args:
        val: LLVM value to check
        
    Returns:
        True if unsigned, False otherwise
    """
    if hasattr(val, '_flux_type_spec'):
        type_spec = val._flux_type_spec
        if hasattr(type_spec, 'base_type'):
            return type_spec.base_type == DataType.UINT
        if hasattr(type_spec, 'is_signed'):
            return not type_spec.is_signed
    return False


def get_comparison_signedness(left_val: ir.Value, right_val: ir.Value) -> bool:
    """
    Determine signedness for comparison operations.
    
    Args:
        left_val: Left operand
        right_val: Right operand
        
    Returns:
        True if signed comparison, False if unsigned
    """
    left_unsigned = is_unsigned(left_val)
    right_unsigned = is_unsigned(right_val)
    
    # Use unsigned comparison if EITHER operand is unsigned
    if left_unsigned or right_unsigned:
        return False  # unsigned
    return True  # signed


def get_builtin_bit_width(base_type: DataType) -> int:
    """
    Get the bit width for built-in types.
    
    Args:
        base_type: The Flux DataType
        
    Returns:
        Bit width as integer
        
    Raises:
        ValueError: If type doesn't have a defined bit width
    """
    if base_type in (DataType.SINT, DataType.UINT):
        return 32  # Default integer width
    elif base_type == DataType.FLOAT:
        return 32  # Single precision float
    elif base_type == DataType.CHAR:
        return 8
    elif base_type == DataType.BOOL:
        return 1
    else:
        raise ValueError(f"Type {base_type} does not have a defined bit width")


def get_custom_type_info(typename: str, module: ir.Module) -> Dict:
    """
    Retrieve information about a custom type from the module.
    
    Args:
        typename: Name of the custom type
        module: LLVM module containing type definitions
        
    Returns:
        Dictionary with type information
        
    Raises:
        ValueError: If type is not found
    """
    if hasattr(module, '_type_aliases') and typename in module._type_aliases:
        llvm_type = module._type_aliases[typename]
        return {
            'llvm_type': llvm_type,
            'bit_width': llvm_type.width if hasattr(llvm_type, 'width') else None,
            'is_integer': isinstance(llvm_type, ir.IntType),
            'is_float': isinstance(llvm_type, (ir.FloatType, ir.DoubleType))
        }
    
    raise ValueError(f"Custom type '{typename}' not found in module")


def find_common_type(types: List[ir.Type]) -> ir.Type:
    """
    Find a common type for a list of LLVM types (for array elements, etc.).
    
    Args:
        types: List of LLVM types
        
    Returns:
        The common type or the first type if all compatible
        
    Raises:
        ValueError: If no common type can be determined
    """
    if not types:
        raise ValueError("Cannot find common type of empty list")
    
    first_type = types[0]
    
    # Check if all types are the same
    if all(t == first_type for t in types):
        return first_type
    
    # Check if all are integer types - promote to largest
    if all(isinstance(t, ir.IntType) for t in types):
        max_width = max(t.width for t in types)
        return ir.IntType(max_width)
    
    # Check if all are float types - promote to double
    if all(isinstance(t, (ir.FloatType, ir.DoubleType)) for t in types):
        return ir.DoubleType()
    
    # Mixed types - use first type as fallback
    return first_type


def cast_to_type(builder: ir.IRBuilder, value: ir.Value, target_type: ir.Type) -> ir.Value:
    """
    Cast an LLVM value to a target type with appropriate conversion.
    
    Args:
        builder: LLVM IR builder
        value: Value to cast
        target_type: Target LLVM type
        
    Returns:
        Casted LLVM value
    """
    source_type = value.type
    
    # No cast needed if types match
    if source_type == target_type:
        return value
    
    # Integer to integer
    if isinstance(source_type, ir.IntType) and isinstance(target_type, ir.IntType):
        if source_type.width < target_type.width:
            # Check if source is unsigned
            if is_unsigned(value):
                return builder.zext(value, target_type)
            else:
                return builder.sext(value, target_type)
        elif source_type.width > target_type.width:
            return builder.trunc(value, target_type)
        return value
    
    # Integer to float
    if isinstance(source_type, ir.IntType) and isinstance(target_type, (ir.FloatType, ir.DoubleType)):
        if is_unsigned(value):
            return builder.uitofp(value, target_type)
        else:
            return builder.sitofp(value, target_type)
    
    # Float to integer
    if isinstance(source_type, (ir.FloatType, ir.DoubleType)) and isinstance(target_type, ir.IntType):
        # Default to signed conversion (fptosi)
        return builder.fptosi(value, target_type)
    
    # Float to float
    if isinstance(source_type, (ir.FloatType, ir.DoubleType)) and isinstance(target_type, (ir.FloatType, ir.DoubleType)):
        if source_type.width < target_type.width:
            return builder.fpext(value, target_type)
        elif source_type.width > target_type.width:
            return builder.fptrunc(value, target_type)
        return value
    
    # Pointer conversions
    if isinstance(source_type, ir.PointerType) and isinstance(target_type, ir.PointerType):
        return builder.bitcast(value, target_type)
    
    # Fallback: bitcast
    return builder.bitcast(value, target_type)


# ============================================================================
# Function Type Helper
# ============================================================================

class FunctionTypeHelper:
    """
    Helper class for managing function type conversions, parameter handling,
    and function signature operations.
    """
    
    @staticmethod
    def convert_type_spec_to_llvm(type_spec, module: ir.Module) -> ir.Type:
        """
        Convert a TypeSpec to LLVM type, handling arrays and pointers.
        
        Args:
            type_spec: TypeSpec object to convert
            module: LLVM module for type resolution
            
        Returns:
            Corresponding LLVM type
        """
        return type_spec.get_llvm_type_with_array(module)
    
    @staticmethod
    def create_function_type(return_type_spec, param_type_specs: List, module: ir.Module) -> ir.FunctionType:
        """
        Create an LLVM function type from TypeSpec objects.
        
        Args:
            return_type_spec: Return type TypeSpec
            param_type_specs: List of parameter TypeSpec objects
            module: LLVM module
            
        Returns:
            LLVM FunctionType
        """
        ret_type = FunctionTypeHelper.convert_type_spec_to_llvm(return_type_spec, module)
        param_types = [FunctionTypeHelper.convert_type_spec_to_llvm(pts, module) 
                      for pts in param_type_specs]
        return ir.FunctionType(ret_type, param_types)
    
    @staticmethod
    def build_param_metadata(parameters: List, module: ir.Module) -> List[dict]:
        """
        Build parameter metadata for type tracking.
        
        Args:
            parameters: List of Parameter objects
            module: LLVM module
            
        Returns:
            List of metadata dictionaries
        """
        param_metadata = []
        for param in parameters:
            metadata = {
                'name': param.name,
                'original_type': param.type_spec.custom_typename if param.type_spec.custom_typename else None,
                'type_spec': param.type_spec
            }
            param_metadata.append(metadata)
        return param_metadata
    
    @staticmethod
    def mangle_function_name(base_name: str, parameters: List, return_type_spec, 
                            no_mangle: bool = False) -> str:
        """
        Generate a mangled name for a function based on its signature.
        
        Args:
            base_name: Base function name
            parameters: List of Parameter objects
            return_type_spec: Return type TypeSpec
            no_mangle: If True, return base name without mangling
            
        Returns:
            Mangled function name
        """
        if no_mangle or base_name == "main":
            return base_name
        
        # Start with base name
        mangled = base_name
        
        # Add parameter count for quick filtering
        mangled += f"__{len(parameters)}"
        
        # Add parameter type information
        for param in parameters:
            type_spec = param.type_spec
            
            # Handle custom type names
            if type_spec.custom_typename:
                # For custom types, use the type name (sanitized)
                type_name = type_spec.custom_typename.replace(':', '_').replace('.', '_')
                mangled += f"__{type_name}"
            else:
                # For built-in types, use base type
                mangled += f"__{type_spec.base_type.value}"
            
            # Add array/pointer qualifiers
            if type_spec.is_array:
                if type_spec.array_size:
                    mangled += f"_arr{type_spec.array_size}"
                else:
                    mangled += "_arr"
            
            if type_spec.is_pointer:
                mangled += f"_ptr{type_spec.pointer_depth}"
            
            # Add bit width for DATA types
            if type_spec.base_type == DataType.DATA and type_spec.bit_width:
                mangled += f"_bits{type_spec.bit_width}"
        
        # Add return type information
        if return_type_spec.custom_typename:
            ret_name = return_type_spec.custom_typename.replace(':', '_').replace('.', '_')
            mangled += f"__ret_{ret_name}"
        else:
            mangled += f"__ret_{return_type_spec.base_type.value}"
        
        return mangled
    
    @staticmethod
    def register_function_overload(module: ir.Module, base_name: str, mangled_name: str,
                                   parameters: List, return_type_spec, func: ir.Function):
        """
        Register a function as an overload in the module.
        
        Args:
            module: LLVM module
            base_name: Unmangled function name
            mangled_name: Mangled function name
            parameters: List of Parameter objects
            return_type_spec: Return type TypeSpec
            func: LLVM Function object
        """
        if not hasattr(module, '_function_overloads'):
            module._function_overloads = {}
        
        if base_name not in module._function_overloads:
            module._function_overloads[base_name] = []
        
        # Add overload info
        overload_info = {
            'mangled_name': mangled_name,
            'param_types': [p.type_spec for p in parameters],
            'return_type': return_type_spec,
            'function': func,
            'param_count': len(parameters)
        }
        module._function_overloads[base_name].append(overload_info)
    
    @staticmethod
    def resolve_overload_by_types(module: ir.Module, base_name: str, 
                                  arg_vals: List[ir.Value]) -> Optional[ir.Function]:
        """
        Resolve function overload by matching argument types.
        
        Args:
            module: LLVM module
            base_name: Function base name
            arg_vals: List of argument values
            
        Returns:
            Matching function or None if no match found
        """
        if not hasattr(module, '_function_overloads'):
            return None
        
        if base_name not in module._function_overloads:
            return None
        
        overloads = module._function_overloads[base_name]
        arg_count = len(arg_vals)
        
        # Filter by argument count first
        candidates = [o for o in overloads if o['param_count'] == arg_count]
        
        if len(candidates) == 0:
            return None
        elif len(candidates) == 1:
            # Only one candidate - use it
            return candidates[0]['function']
        else:
            # Multiple candidates - need type matching
            for candidate in candidates:
                param_types = candidate['param_types']
                if len(param_types) != len(arg_vals):
                    continue
                
                # Check if types match (with compatibility rules)
                match = True
                for i, (param_type, arg_val) in enumerate(zip(param_types, arg_vals)):
                    expected_llvm_type = param_type.get_llvm_type(module)
                    
                    # Handle array/pointer compatibility
                    if isinstance(arg_val.type, ir.PointerType) and isinstance(arg_val.type.pointee, ir.ArrayType):
                        # Array pointer - check element type compatibility
                        if isinstance(expected_llvm_type, ir.PointerType):
                            if arg_val.type.pointee.element != expected_llvm_type.pointee:
                                match = False
                                break
                        else:
                            match = False
                            break
                    elif arg_val.type != expected_llvm_type:
                        # Type mismatch
                        match = False
                        break
                
                if match:
                    return candidate['function']
            
            # No exact match found
            return None
    
    @staticmethod
    def convert_argument_to_parameter_type(builder: ir.IRBuilder, module: ir.Module, 
                                          arg_val: ir.Value, expected_type: ir.Type, 
                                          arg_index: int) -> ir.Value:
        """
        Convert an argument value to match the expected parameter type.
        Handles void* conversions, array decay, and __expr method calls.
        
        Args:
            builder: LLVM IR builder
            module: LLVM module (for __expr method lookups)
            arg_val: Argument value to convert
            expected_type: Expected parameter type
            arg_index: Argument index (for naming)
            
        Returns:
            Converted argument value
        """
        if arg_val.type == expected_type:
            return arg_val
        
        # Handle void* conversions (i8*)
        void_ptr_type = ir.PointerType(ir.IntType(8))
        
        # Convert TO void*
        if (isinstance(expected_type, ir.PointerType) and 
            isinstance(expected_type.pointee, ir.IntType) and 
            expected_type.pointee.width == 8):
            if isinstance(arg_val.type, ir.PointerType):
                return builder.bitcast(arg_val, expected_type, name=f"arg{arg_index}_to_void_ptr")
        
        # Convert FROM void*
        elif (isinstance(arg_val.type, ir.PointerType) and 
              isinstance(arg_val.type.pointee, ir.IntType) and 
              arg_val.type.pointee.width == 8 and
              isinstance(expected_type, ir.PointerType)):
            return builder.bitcast(arg_val, expected_type, name=f"arg{arg_index}_from_void_ptr")
        
        # Array to pointer decay: [N x T]* -> T*
        if (isinstance(arg_val.type, ir.PointerType) and 
            isinstance(arg_val.type.pointee, ir.ArrayType) and
            isinstance(expected_type, ir.PointerType) and
            arg_val.type.pointee.element == expected_type.pointee):
            zero = ir.Constant(ir.IntType(32), 0)
            return builder.gep(arg_val, [zero, zero], name=f"arg{arg_index}_decay")
        
        # Check if this is an object type that has a __expr method for automatic conversion
        if isinstance(arg_val.type, ir.PointerType):
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
                            return converted_val
        
        return arg_val



# ============================================================================
# Name Mangling
# ============================================================================

def mangle_name(base_name: str, param_types: List[ir.Type], module: ir.Module) -> str:
    """
    Generate a mangled name for function overloading.
    
    Args:
        base_name: Base function name
        param_types: List of parameter types
        module: LLVM module
        
    Returns:
        Mangled function name
    """
    if not param_types:
        return base_name
    
    type_suffix = "_".join(_type_to_string(t, module) for t in param_types)
    return f"{base_name}__{type_suffix}"


def _type_to_string(llvm_type: ir.Type, module: ir.Module) -> str:
    """
    Convert an LLVM type to a string representation for mangling.
    
    Args:
        llvm_type: LLVM type to convert
        module: LLVM module (for struct name lookups)
        
    Returns:
        String representation of the type
    """
    if isinstance(llvm_type, ir.IntType):
        return f"i{llvm_type.width}"
    elif isinstance(llvm_type, ir.FloatType):
        return "f32"
    elif isinstance(llvm_type, ir.DoubleType):
        return "f64"
    elif isinstance(llvm_type, ir.PointerType):
        pointee_str = _type_to_string(llvm_type.pointee, module)
        return f"ptr_{pointee_str}"
    elif isinstance(llvm_type, ir.ArrayType):
        element_str = _type_to_string(llvm_type.element, module)
        return f"arr{llvm_type.count}_{element_str}"
    elif hasattr(llvm_type, 'name') and llvm_type.name:
        # Struct or named type
        return llvm_type.name.replace('.', '_')
    else:
        # Fallback for unknown types
        return "unknown"


# ============================================================================
# Constant Evaluation
# ============================================================================

def eval_const_binary_op(left: ir.Constant, right: ir.Constant, 
                        op: Operator) -> Optional[ir.Constant]:
    """
    Evaluate a binary operation on constants at compile time.
    
    Args:
        left: Left constant operand
        right: Right constant operand
        op: Binary operator
        
    Returns:
        Result constant or None if not evaluable
    """
    # Only handle integer constants for now
    if not (isinstance(left.type, ir.IntType) and isinstance(right.type, ir.IntType)):
        return None
    
    left_val = left.constant
    right_val = right.constant
    result_type = left.type  # Assume same type
    
    try:
        if op == Operator.ADD:
            result = left_val + right_val
        elif op == Operator.SUB:
            result = left_val - right_val
        elif op == Operator.MUL:
            result = left_val * right_val
        elif op == Operator.DIV:
            if right_val == 0:
                return None
            result = left_val // right_val
        elif op == Operator.MOD:
            if right_val == 0:
                return None
            result = left_val % right_val
        elif op == Operator.BITAND:
            result = left_val & right_val
        elif op == Operator.BITOR:
            result = left_val | right_val
        elif op == Operator.XOR:
            result = left_val ^ right_val
        elif op == Operator.BITSHIFT_LEFT:
            result = left_val << right_val
        elif op == Operator.BITSHIFT_RIGHT:
            result = left_val >> right_val
        else:
            return None
        
        return ir.Constant(result_type, result)
    except:
        return None


def eval_const_unary_op(operand: ir.Constant, op: Operator) -> Optional[ir.Constant]:
    """
    Evaluate a unary operation on a constant at compile time.
    
    Args:
        operand: Constant operand
        op: Unary operator
        
    Returns:
        Result constant or None if not evaluable
    """
    if not isinstance(operand.type, ir.IntType):
        return None
    
    val = operand.constant
    result_type = operand.type
    
    try:
        if op == Operator.SUB:  # Negation
            result = -val
        elif op == Operator.NOT:  # Logical NOT
            result = 1 if val == 0 else 0
        else:
            return None
        
        return ir.Constant(result_type, result)
    except:
        return None


# ============================================================================
# Default Initializers
# ============================================================================

def get_default_initializer(llvm_type: ir.Type) -> ir.Constant:
    """
    Get a default zero initializer for an LLVM type.
    
    Args:
        llvm_type: The LLVM type to initialize
        
    Returns:
        Zero/null constant of the appropriate type
    """
    if isinstance(llvm_type, ir.IntType):
        return ir.Constant(llvm_type, 0)
    elif isinstance(llvm_type, (ir.FloatType, ir.DoubleType)):
        return ir.Constant(llvm_type, 0.0)
    elif isinstance(llvm_type, ir.PointerType):
        return ir.Constant(llvm_type, None)
    elif isinstance(llvm_type, ir.ArrayType):
        element_init = get_default_initializer(llvm_type.element)
        return ir.Constant(llvm_type, [element_init] * llvm_type.count)
    elif isinstance(llvm_type, ir.LiteralStructType):
        field_inits = [get_default_initializer(field) for field in llvm_type.elements]
        return ir.Constant(llvm_type, field_inits)
    else:
        # Fallback: try to create a zeroed value
        return ir.Constant(llvm_type, None)


# ============================================================================
# Array Packing Utilities
# ============================================================================

def pack_array_to_integer(builder: ir.IRBuilder, module: ir.Module,
                         array_val: ir.Value, element_type: ir.Type,
                         element_count: int) -> ir.Value:
    """
    Pack a small array into an integer for efficient storage (compile-time known).
    
    Args:
        builder: LLVM IR builder
        module: LLVM module
        array_val: Array value to pack
        element_type: Type of array elements
        element_count: Number of elements
        
    Returns:
        Packed integer value
    """
    if not isinstance(element_type, ir.IntType):
        raise ValueError("Can only pack integer arrays")
    
    element_bits = element_type.width
    total_bits = element_bits * element_count
    
    # Create target integer type
    packed_type = ir.IntType(total_bits)
    result = ir.Constant(packed_type, 0)
    
    # Pack each element
    for i in range(element_count):
        # Extract element
        elem_ptr = builder.gep(array_val, [ir.Constant(ir.IntType(32), 0),
                                           ir.Constant(ir.IntType(32), i)])
        elem = builder.load(elem_ptr)
        
        # Zero-extend to packed size
        elem_extended = builder.zext(elem, packed_type)
        
        # Shift to position
        shift_amount = ir.Constant(packed_type, i * element_bits)
        elem_shifted = builder.shl(elem_extended, shift_amount)
        
        # OR into result
        result = builder.or_(result, elem_shifted)
    
    return result


def pack_array_to_integer_runtime(builder: ir.IRBuilder,
                                  array_ptr: ir.Value,
                                  element_type: ir.Type,
                                  element_count: ir.Value) -> ir.Value:
    """
    Pack array to integer at runtime with dynamic element count.
    
    Args:
        builder: LLVM IR builder
        array_ptr: Pointer to array
        element_type: Type of elements
        element_count: Runtime element count
        
    Returns:
        Packed integer value
    """
    # Similar to compile-time version but with loops
    # This is a simplified version - full implementation would use loops
    element_bits = element_type.width
    
    # For now, assume max 64 bits total
    packed_type = ir.IntType(64)
    result = ir.Constant(packed_type, 0)
    
    # Would need to implement runtime loop here
    # Placeholder for now
    return result


def pack_array_pointer_to_integer(builder: ir.IRBuilder, module: ir.Module,
                                  array_ptr: ir.Value, element_type: ir.Type,
                                  element_count: int) -> ir.Value:
    """
    Pack array (given by pointer) to integer.
    
    Args:
        builder: LLVM IR builder
        module: LLVM module
        array_ptr: Pointer to array
        element_type: Type of array elements
        element_count: Number of elements
        
    Returns:
        Packed integer value
    """
    if not isinstance(element_type, ir.IntType):
        raise ValueError("Can only pack integer arrays")
    
    element_bits = element_type.width
    total_bits = element_bits * element_count
    packed_type = ir.IntType(total_bits)
    
    result = ir.Constant(packed_type, 0)
    
    for i in range(element_count):
        # Get element pointer
        idx = ir.Constant(ir.IntType(32), i)
        elem_ptr = builder.gep(array_ptr, [ir.Constant(ir.IntType(32), 0), idx])
        elem = builder.load(elem_ptr)
        
        # Zero-extend and shift
        elem_extended = builder.zext(elem, packed_type)
        shift_amount = ir.Constant(packed_type, i * element_bits)
        elem_shifted = builder.shl(elem_extended, shift_amount)
        
        # Combine
        result = builder.or_(result, elem_shifted)
    
    return result


# ============================================================================
# Array Concatenation
# ============================================================================

def create_global_array_concat(module: ir.Module, left_val: ir.Value,
                               right_val: ir.Value) -> ir.Value:
    """
    Concatenate two arrays at global/compile time.
    
    Args:
        module: LLVM module
        left_val: Left array constant
        right_val: Right array constant
        
    Returns:
        Concatenated array constant
    """
    if not (isinstance(left_val, ir.Constant) and isinstance(right_val, ir.Constant)):
        raise ValueError("Global array concatenation requires constants")
    
    # Get array types
    left_type = left_val.type
    right_type = right_val.type
    
    if not (isinstance(left_type, ir.ArrayType) and isinstance(right_type, ir.ArrayType)):
        raise ValueError("Can only concatenate arrays")
    
    # Ensure compatible element types
    if left_type.element != right_type.element:
        raise ValueError("Array element types must match for concatenation")
    
    # Create new array type
    new_count = left_type.count + right_type.count
    new_type = ir.ArrayType(left_type.element, new_count)
    
    # Combine constants
    left_elements = list(left_val.constant) if hasattr(left_val, 'constant') else []
    right_elements = list(right_val.constant) if hasattr(right_val, 'constant') else []
    
    combined = left_elements + right_elements
    return ir.Constant(new_type, combined)


def create_runtime_array_concat(builder: ir.IRBuilder, module: ir.Module,
                                left_val: ir.Value, right_val: ir.Value) -> ir.Value:
    """
    Concatenate two arrays at runtime.
    
    Args:
        builder: LLVM IR builder
        module: LLVM module
        left_val: Left array value (pointer)
        right_val: Right array value (pointer)
        
    Returns:
        Pointer to new concatenated array
    """
    # Get array types
    left_type = left_val.type.pointee if isinstance(left_val.type, ir.PointerType) else left_val.type
    right_type = right_val.type.pointee if isinstance(right_val.type, ir.PointerType) else right_val.type
    
    if not (isinstance(left_type, ir.ArrayType) and isinstance(right_type, ir.ArrayType)):
        raise ValueError("Can only concatenate arrays")
    
    # Calculate new size
    left_count = left_type.count
    right_count = right_type.count
    new_count = left_count + right_count
    
    # Allocate new array
    element_type = left_type.element
    new_array_type = ir.ArrayType(element_type, new_count)
    new_array = builder.alloca(new_array_type)
    
    # Copy left array
    for i in range(left_count):
        src_ptr = builder.gep(left_val, [ir.Constant(ir.IntType(32), 0),
                                        ir.Constant(ir.IntType(32), i)])
        dst_ptr = builder.gep(new_array, [ir.Constant(ir.IntType(32), 0),
                                         ir.Constant(ir.IntType(32), i)])
        val = builder.load(src_ptr)
        builder.store(val, dst_ptr)
    
    # Copy right array
    for i in range(right_count):
        src_ptr = builder.gep(right_val, [ir.Constant(ir.IntType(32), 0),
                                        ir.Constant(ir.IntType(32), i)])
        dst_ptr = builder.gep(new_array, [ir.Constant(ir.IntType(32), 0),
                                         ir.Constant(ir.IntType(32), left_count + i)])
        val = builder.load(src_ptr)
        builder.store(val, dst_ptr)
    
    return new_array


# ============================================================================
# Struct Name Inference
# ============================================================================

def infer_struct_name(instance: ir.Value, module: ir.Module) -> str:
    """
    Infer the struct name from an LLVM struct instance.
    
    Args:
        instance: LLVM struct value or pointer
        module: LLVM module
        
    Returns:
        Struct name string
        
    Raises:
        ValueError: If struct name cannot be determined
    """
    # Get the actual type
    struct_type = instance.type
    if isinstance(struct_type, ir.PointerType):
        struct_type = struct_type.pointee
    
    # Check if it's a named struct
    if hasattr(struct_type, 'name') and struct_type.name:
        return struct_type.name
    
    # Try to find in module's struct registry
    if hasattr(module, '_struct_types'):
        for name, registered_type in module._struct_types.items():
            if registered_type == struct_type:
                return name
    
    raise ValueError("Cannot infer struct name from instance")


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

# ALERT
# DO NOT REMOVE IS_MACRO_DEFINED DO NOT REMOVE
# ALERT
def is_macro_defined(module: ir.Module, macro_name: str) -> bool:
    """
    Check if a preprocessor macro is defined in the module.
    
    Args:
        module: LLVM IR module containing preprocessor macros
        macro_name: Name of the macro to check
        
    Returns:
        True if macro is defined and evaluates to truthy value, False otherwise
    """
    if not hasattr(module, '_preprocessor_macros'):
        return False
    
    if macro_name not in module._preprocessor_macros:
        return False
    
    # Get macro value
    value = module._preprocessor_macros[macro_name]
    
    # Handle string values - check if it's "1" or other truthy string
    if isinstance(value, str):
        # Empty string or "0" are falsy
        if value == "" or value == "0":
            return False
        # Everything else is truthy
        return True
    
    # Handle other types (shouldn't happen but be defensive)
    return bool(value)


# String Heap Allocation

def string_heap_allocation(builder: ir.IRBuilder, module: ir.Module, str_val):
    # Heap allocation: allocate memory and copy string data
    # Declare malloc if not already present
    malloc_fn = module.globals.get('malloc')
    if malloc_fn is None:
        malloc_type = ir.FunctionType(ir.PointerType(ir.IntType(8)), [ir.IntType(64)])
        malloc_fn = ir.Function(module, malloc_type, 'malloc')
        malloc_fn.linkage = 'external'
    
    # Allocate memory for the string
    size = ir.Constant(ir.IntType(64), len(str_val.type))
    heap_ptr = builder.call(malloc_fn, [size], name="heap_str")
    
    # Cast to array pointer type
    array_ptr = builder.bitcast(heap_ptr, ir.PointerType(str_val.type))
    
    # Store the string constant in the allocated memory
    builder.store(str_val, array_ptr)
    
    # Return pointer to first element
    zero = ir.Constant(ir.IntType(32), 0)
    return builder.gep(array_ptr, [zero, zero], name="heap_str_ptr")

# Array Heap Allocation
def array_heap_allocation(builder: ir.IRBuilder, module: ir.Module, str_val):
    # Heap allocation: allocate memory and copy array data
    malloc_fn = module.globals.get('malloc')
    if malloc_fn is None:
        malloc_type = ir.FunctionType(ir.PointerType(ir.IntType(8)), [ir.IntType(64)])
        malloc_fn = ir.Function(module, malloc_type, 'malloc')
        malloc_fn.linkage = 'external'
    
    # Calculate total bytes needed for the array
    element_size = str_val.type.element.width // 8  # bits to bytes
    array_count = str_val.type.count
    total_bytes = element_size * array_count
    
    size = ir.Constant(ir.IntType(64), total_bytes)
    heap_ptr = builder.call(malloc_fn, [size], name="heap_array")
    
    # Cast to appropriate array pointer type
    array_ptr = builder.bitcast(heap_ptr, ir.PointerType(str_val.type))
    
    # Store the array constant in the allocated memory
    builder.store(str_val, array_ptr)
    
    # Mark as array pointer for downstream logic
    array_ptr.type._is_array_pointer = True
    
    # Return the array pointer
    zero = ir.Constant(ir.IntType(32), 0)
    return builder.gep(array_ptr, [zero, zero], name="heap_array_ptr")

# ============================================================================
# Union Member Assignment
# ============================================================================

def handle_union_member_assignment(builder, module, union_ptr, union_name, member_name, val):
    """
    Handle union member assignment by casting the union to the appropriate member type.
    
    This function handles both regular unions and tagged unions, with special support
    for the ._ syntax to access/modify the tag field in tagged unions.
    
    Args:
        builder: LLVM IR builder
        module: LLVM module containing union type information
        union_ptr: Pointer to the union instance
        union_name: Name of the union type
        member_name: Name of the member to assign (or '_' for tag)
        val: Value to assign
        
    Returns:
        The assigned value
        
    Raises:
        ValueError: If union info not found, member not found, or invalid tag access
        RuntimeError: If trying to reassign an already initialized union member
    """
    # Get union member information
    if not hasattr(module, '_union_member_info') or union_name not in module._union_member_info:
        raise ValueError(f"Union member info not found for '{union_name}'")
    
    union_info = module._union_member_info[union_name]
    member_names = union_info['member_names']
    member_types = union_info['member_types']
    is_tagged = union_info['is_tagged']
    
    # Handle special ._ tag assignment for tagged unions
    if member_name == '_':
        if not is_tagged:
            raise ValueError(f"Cannot assign to tag '._' on non-tagged union '{union_name}'")
        
        # For tagged unions, the tag is at index 0
        tag_ptr = builder.gep(
            union_ptr,
            [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), 0)],
            inbounds=True,
            name="union_tag_ptr"
        )
        builder.store(val, tag_ptr)
        return val
    
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
        casted_ptr = builder.bitcast(data_ptr, member_ptr_type, name=f"union_as_{member_name}")
        builder.store(val, casted_ptr)
        return val
    else:
        # For regular unions, cast the union pointer directly
        member_ptr_type = ir.PointerType(member_type)
        casted_ptr = builder.bitcast(union_ptr, member_ptr_type, name=f"union_as_{member_name}")
        builder.store(val, casted_ptr)
        return val


def coerce_return_value(
    builder: ir.IRBuilder,
    value: ir.Value,
    expected: ir.Type
) -> ir.Value:
    """
    Coerce a return value to the expected function return type.
    
    Args:
        builder: LLVM IR builder
        value: The value being returned
        expected: The expected return type
        
    Returns:
        The coerced value
        
    Raises:
        TypeError: If the value cannot be coerced to the expected type
    """
    ctx = LoweringContext(builder)
    src = value.type

    # Exact match
    if src == expected:
        return value

    # === ALLOWED IMPLICIT CASE ===
    # Integer type conversion (widening and narrowing)
    # This includes literals, binary operations, and all integer expressions
    if isinstance(src, ir.IntType) and isinstance(expected, ir.IntType):
        if src.width < expected.width:
            # Widening: use zero-extension for unsigned, sign-extension for signed
            unsigned = LoweringContext.is_unsigned(value)
            result = builder.zext(value, expected) if unsigned else builder.sext(value, expected)
            # Preserve type metadata
            if hasattr(value, '_flux_type_spec'):
                result._flux_type_spec = value._flux_type_spec
                result._flux_type_spec.bit_width = expected.width
            return result
        elif src.width > expected.width:
            result = builder.trunc(value, expected)
            # Preserve type metadata
            if hasattr(value, '_flux_type_spec'):
                result._flux_type_spec = value._flux_type_spec
                result._flux_type_spec.bit_width = expected.width
            return result

    # Pointer ABI cast
    if isinstance(src, ir.PointerType) and isinstance(expected, ir.PointerType):
        return builder.bitcast(value, expected)

    # Struct exact match only
    if isinstance(src, ir.LiteralStructType) and isinstance(expected, ir.LiteralStructType):
        if src != expected:
            raise TypeError(
                f"Return struct type mismatch: {src} != {expected}"
            )
        return value

    # === Array type conversion when bit widths match ===
    # This handles cases like [8 x i32] -> [32 x i8] where 8*32 = 32*8 = 256 bits
    # Flux allows "anything so long as the widths match"
    if isinstance(src, ir.ArrayType) and isinstance(expected, ir.ArrayType):
        # Check if element types are both integers
        src_elem = src.element
        exp_elem = expected.element
        
        if isinstance(src_elem, ir.IntType) and isinstance(exp_elem, ir.IntType):
            # Calculate total bit widths
            src_total_bits = src.count * src_elem.width
            exp_total_bits = expected.count * exp_elem.width
            
            # If bit widths match, we can convert by storing and loading through memory
            if src_total_bits == exp_total_bits:
                # Allocate temporary storage for source type
                temp = builder.alloca(src, name="array_convert_temp")
                
                # Store the source value
                builder.store(value, temp)
                
                # Bitcast the pointer to the expected type
                temp_as_expected = builder.bitcast(temp, ir.PointerType(expected))
                
                # Load as the expected type
                return builder.load(temp_as_expected, name="array_converted")
            else:
                raise TypeError(
                    f"Invalid return type: array bit width mismatch: "
                    f"cannot return {src} ({src_total_bits} bits) "
                    f"from function returning {expected} ({exp_total_bits} bits)"
                )
        else:
            raise TypeError(
                f"Invalid return type: can only convert between integer arrays, "
                f"got {src} -> {expected}")