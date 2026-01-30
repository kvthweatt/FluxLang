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
            
            if hasattr(module, '_struct_types') and self.custom_typename in module._struct_types:
                return module._struct_types[self.custom_typename]
            
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
            if self.base_type == DataType.VOID:
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