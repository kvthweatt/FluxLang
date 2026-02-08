#!/usr/bin/env python3
"""
Flux Type System

Copyright (C) 2026 Karac Thweatt

Contributors:
    Piotr Bednarski
"""

import sys, traceback, faulthandler
from dataclasses import dataclass, field
from typing import List, Any, Optional, Union, Dict, Tuple
from enum import Enum
from llvmlite import ir
from flexer import TokenType


debug_counter = 0

class SymbolKind(Enum):
    TYPE = "type"
    VARIABLE = "variable"
    FUNCTION = "function"
    NAMESPACE = "namespace"
    OBJECT = "object"
    STRUCT = "struct"
    UNION = "union"
    ENUM = "enum"

@dataclass
class SymbolEntry:
    """Complete symbol information"""
    kind: SymbolKind
    name: str
    namespace: str = ""
    type_spec: Optional[Any] = None
    llvm_type: Optional[ir.Type] = None
    llvm_value: Optional[ir.Value] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    @property
    def mangled_name(self) -> str:
        if not self.namespace:
            return self.name
        if not isinstance(self.namespace, str) or not isinstance(self.name, str):
            raise TypeError(f"namespace and name must be str, got {type(self.namespace)} and {type(self.name)}")
        return self.namespace.replace('::', '__') + '__' + self.name
    
    @property
    def full_name(self) -> str:
        if not self.namespace:
            return self.name
        return f"{self.namespace}::{self.name}"

class SymbolTable:
    """UNIFIED symbol and scope management"""
    def __init__(self):
        self.scopes: List[Dict[str, SymbolEntry]] = [{}]
        self.current_namespace: str = ""
        self.using_namespaces: List[str] = []
        self.registered_namespaces: List[str] = []
        self._global_symbols: Dict[str, SymbolEntry] = {}
    
    @property
    def scope_level(self):
        """Current scope depth (0 = global)"""
        return len(self.scopes) - 1
    
    def enter_scope(self):
        """Enter function/block scope"""
        self.scopes.append({})
    
    def exit_scope(self):
        """Exit function/block scope"""
        if len(self.scopes) > 1:
            popped = self.scopes.pop()

    def is_global_scope(self) -> bool:
        """Check if we're at global scope (scope_level == 0)"""
        return self.scope_level == 0
    
    def set_namespace(self, namespace: str):
        self.current_namespace = namespace
        if namespace and namespace not in self.registered_namespaces:
            self.registered_namespaces.append(namespace)
    
    def add_using_namespace(self, namespace: str):
        if namespace not in self.using_namespaces:
            self.using_namespaces.append(namespace)
    
    def define(self, name: str, kind: SymbolKind, type_spec=None, 
               llvm_type=None, llvm_value=None, **metadata):
        """Define symbol in current scope"""
        
        if not isinstance(name, str):
            raise TypeError(f"SymbolTable.define() requires name to be str, got {type(name)}: {name}")
        
        entry = SymbolEntry(
            kind=kind,
            name=name,
            namespace=self.current_namespace if self.scope_level == 0 else "",
            type_spec=type_spec,
            llvm_type=llvm_type,
            llvm_value=llvm_value,
            metadata=metadata
        )
        
        self.scopes[-1][name] = entry
        
        if self.scope_level == 0:
            self._global_symbols[entry.mangled_name] = entry
            if name not in self._global_symbols:
                self._global_symbols[name] = entry
    
    def lookup(self, name: str) -> Optional[Tuple[SymbolKind, Any]]:
        """LEGACY backward compat"""
        entry = self.lookup_any(name)
        if entry:
            return (entry.kind, entry.type_spec)
        return None
    
    def lookup_any(self, name: str, current_namespace: str = None) -> Optional[SymbolEntry]:
        """Lookup with namespace resolution"""
        if current_namespace is None:
            current_namespace = self.current_namespace
        
        for i, scope in enumerate(reversed(self.scopes)):
            if name in scope:
                return scope[name]
        
        result = self._resolve_with_namespaces(name, current_namespace)
        return result
    
    def _lookup_with_kinds(self, name: str, kinds, current_namespace: str = None) -> Optional[SymbolEntry]:
        entry = self.lookup_any(name, current_namespace)
        return entry if (entry and entry.kind in kinds) else None
    
    def lookup_type(self, name: str, current_namespace: str = None) -> Optional[SymbolEntry]:
        return self._lookup_with_kinds(name, (SymbolKind.TYPE, SymbolKind.STRUCT, SymbolKind.UNION, SymbolKind.ENUM), current_namespace)
    
    def lookup_variable(self, name: str, current_namespace: str = None) -> Optional[SymbolEntry]:
        return self._lookup_with_kinds(name, (SymbolKind.VARIABLE,), current_namespace)
    
    def lookup_function(self, name: str, current_namespace: str = None) -> Optional[SymbolEntry]:
        return self._lookup_with_kinds(name, (SymbolKind.FUNCTION,), current_namespace)
    
    def _resolve_with_namespaces(self, name: str, current_namespace: str) -> Optional[SymbolEntry]:
        if name in self._global_symbols:
            return self._global_symbols[name]
        
        if current_namespace:
            mangled = SymbolResolver.mangle_name(current_namespace, name)
            if mangled in self._global_symbols:
                return self._global_symbols[mangled]
        
        if current_namespace:
            parts = current_namespace.split('::')
            while parts:
                parts.pop()
                parent_ns = '::'.join(parts)
                mangled = SymbolResolver.mangle_name(parent_ns, name) if parent_ns else name
                if mangled in self._global_symbols:
                    return self._global_symbols[mangled]
        
        for namespace in self.using_namespaces:
            mangled = SymbolResolver.mangle_name(namespace, name)
            if mangled in self._global_symbols:
                return self._global_symbols[mangled]
        
        for namespace in self.registered_namespaces:
            mangled = SymbolResolver.mangle_name(namespace, name)
            if mangled in self._global_symbols:
                return self._global_symbols[mangled]
        
        return None
    
    def is_type(self, name: str) -> bool:
        entry = self.lookup_any(name)
        return entry is not None and entry.kind in (
            SymbolKind.TYPE, SymbolKind.STRUCT, SymbolKind.UNION, SymbolKind.ENUM
        )
    
    def get_type_spec(self, name: str):
        entry = self.lookup_any(name)
        if entry:
            return entry.type_spec
        return None

    def get_llvm_value(self, name: str):
        """Get LLVM value for a variable"""
        entry = self.lookup_variable(name)
        if entry:
            return entry.llvm_value
        return None
    
    def update_llvm_value(self, name: str, llvm_value):
        """Update LLVM value for an existing variable in current scope"""
        for scope in reversed(self.scopes):
            if name in scope:
                scope[name].llvm_value = llvm_value
                return True
        return False
    
    def delete_variable(self, name: str) -> bool:
        """Delete a variable from current scope"""
        if name in self.scopes[-1]:
            del self.scopes[-1][name]
            return True
        return False

    def len(self) -> int:
        return len(self.scopes)


class Operator(Enum):
    ADD = "+"
    SUB = "-"
    INCREMENT = "++"
    DECREMENT = "--"
    MUL = "*"
    DIV = "/"
    MOD = "%"
    NOT = "!"
    POWER = "^"
    AND = "&"
    OR = "|"
    NAND = "!&"
    NOR = "!|"
    XOR = "^^"
    EQUAL = "=="
    NOT_EQUAL = "!="
    LESS_THAN = "<"
    LESS_EQUAL = "<="
    GREATER_THAN = ">"
    GREATER_EQUAL = ">="
    ASSIGN = "="
    PLUS_ASSIGN = "+="
    MINUS_ASSIGN = "-="
    MULTIPLY_ASSIGN = "*="
    DIVIDE_ASSIGN = "/="
    MODULO_ASSIGN = "%="
    POWER_ASSIGN = "^="
    BITNOT = "`!"
    BITAND = "`&"
    BITOR = "`|"
    BITNAND = "`!&"
    BITNOR = "`!|"
    BITXOR = "`^^"
    AND_ASSIGN = "&="
    OR_ASSIGN = "|="
    XOR_ASSIGN = "^^="
    BITAND_ASSIGN = "`&="
    BITOR_ASSIGN = "`|="
    BITNAND_ASSIGN = "`!&="
    BITNOR_ASSIGN = "`!|="
    BITXOR_ASSIGN = "`^^="
    BITSHIFT_LEFT = "<<"
    BITSHIFT_RIGHT = ">>"
    BITSHIFT_LEFT_ASSIGN = "<<="
    BITSHIFT_RIGHT_ASSIGN = ">>="
    ADDRESS_OF = "@"
    RANGE = ".."
    SCOPE = "::"
    QUESTION = "?"
    COLON = ":"
    TIE = "~"
    LAMBDA_ARROW = "<:-"
    RETURN_ARROW = "->"
    CHAIN_ARROW = "<-"
    RECURSE_ARROW = "<~"
    NULL_COALESCE = "??"
    NO_MANGLE = "!!"
    FUNCTION_POINTER = "{}*"
    ADDRESS_CAST = "(@)"


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


class SymbolResolver:
    """
    Centralized resolver for ALL identifier, namespace, and mangling operations.
    """
    
    @staticmethod
    def mangle_name(namespace: str, name: str) -> str:
        if not namespace:
            return name
        return namespace.replace('::', '__') + '__' + name
    
    @staticmethod
    def get_current_namespace(module: ir.Module) -> str:
        """Get current namespace from symbol table."""
        if hasattr(module, 'symbol_table'):
            return module.symbol_table.current_namespace
        return ''
    
    @staticmethod
    def resolve_identifier(module: ir.Module, name: str, current_namespace: str = "") -> Optional[str]:
        """Resolve identifier name through symbol table and module globals."""
        if hasattr(module, 'symbol_table'):
            result = module.symbol_table.lookup(name)
            
            if result:
                kind = result[0]
                
                if kind == SymbolKind.VARIABLE or kind == SymbolKind.TYPE:
                    if name in module.globals:
                        return name
                    
                    if current_namespace:
                        mangled = SymbolResolver.mangle_name(current_namespace, name)
                        if mangled in module.globals:
                            return mangled
                    
                    if kind == SymbolKind.TYPE and hasattr(module, '_type_aliases'):
                        if name in module._type_aliases:
                            return name
                        if current_namespace:
                            mangled = SymbolResolver.mangle_name(current_namespace, name)
                            if mangled in module._type_aliases:
                                return mangled
        
        result = TypeResolver.resolve_with_namespace(module, name, current_namespace, TypeResolver.lookup_global)
        
        if result is not None:
            if name in module.globals:
                return name
            
            if current_namespace:
                mangled = SymbolResolver.mangle_name(current_namespace, name)
                if mangled in module.globals:
                    return mangled
            
            if hasattr(module, '_using_namespaces'):
                for namespace in module._using_namespaces:
                    mangled = SymbolResolver.mangle_name(namespace, name)
                    if mangled in module.globals:
                        return mangled
        
        result = TypeResolver.resolve_with_namespace(module, name, current_namespace, TypeResolver.lookup_type)
        
        if result is not None:
            if hasattr(module, '_type_aliases'):
                if name in module._type_aliases:
                    return name
                
                if current_namespace:
                    mangled = SymbolResolver.mangle_name(current_namespace, name)
                    if mangled in module._type_aliases:
                        return mangled
                
                if hasattr(module, '_using_namespaces'):
                    for namespace in module._using_namespaces:
                        mangled = SymbolResolver.mangle_name(namespace, name)
                        if mangled in module._type_aliases:
                            return mangled
        
        return None
    
    @staticmethod
    def resolve_function(module: ir.Module, func_name: str, current_namespace: str = "") -> Optional[str]:
        """Resolve function name through symbol table."""
        if hasattr(module, 'symbol_table'):
            func_entry = module.symbol_table.lookup_function(func_name, current_namespace)
            
            if func_entry:
                if func_entry.mangled_name in module.globals:
                    return func_entry.mangled_name
                
                if func_name in module.globals:
                    return func_name
        
        result = TypeResolver.resolve_with_namespace(module, func_name, current_namespace, TypeResolver.lookup_global)
        
        if result is not None and isinstance(result, ir.Function):
            return result.name
        
        return None


class TypeResolver:
    """
    Centralized resolver for ALL type lookups and resolution.
    """

    @staticmethod
    def resolve(typename: str, module: ir.Module) -> Optional[ir.Type]:
        """Resolve a type name using current namespace from module."""
        current_ns = SymbolResolver.get_current_namespace(module)
        return TypeResolver.resolve_type(module, typename, current_ns)
    
    @staticmethod
    def lookup_in_storage(module: ir.Module, name: str, storage_name: str) -> Optional[Any]:
        if not hasattr(module, storage_name):
            return None
        
        storage = getattr(module, storage_name)
        if storage is None or name not in storage:
            return None
        
        result = storage[name]
        
        if storage_name == '_type_aliases' and isinstance(result, ir.ArrayType):
            return ir.PointerType(result.element)
        
        return result
    
    @staticmethod
    def lookup_type(module: ir.Module, name: str) -> Optional[ir.Type]:
        for storage_name in ['_type_aliases', '_struct_types', '_union_types', '_enum_types']:
            result = TypeResolver.lookup_in_storage(module, name, storage_name)
            if result is not None:
                return result
        return None
    
    @staticmethod
    def lookup_global(module: ir.Module, name: str) -> Optional[Any]:
        return TypeResolver.lookup_in_storage(module, name, 'globals')
    
    @staticmethod
    def resolve_with_namespace(module: ir.Module, name: str, current_namespace: str = "", lookup_func=None) -> Optional[Any]:
        if lookup_func is None:
            lookup_func = TypeResolver.lookup_type
        
        result = lookup_func(module, name)
        if result is not None:
            return result
        
        if current_namespace:
            mangled = SymbolResolver.mangle_name(current_namespace, name)
            result = lookup_func(module, mangled)
            if result is not None:
                return result
        
        if current_namespace:
            parts = current_namespace.split('::')
            while parts:
                parts.pop()
                parent_ns = '::'.join(parts)
                if parent_ns:
                    mangled = SymbolResolver.mangle_name(parent_ns, name)
                else:
                    mangled = name
                
                result = lookup_func(module, mangled)
                if result is not None:
                    return result
        
        if hasattr(module, '_using_namespaces'):
            for namespace in module._using_namespaces:
                mangled = SymbolResolver.mangle_name(namespace, name)
                result = lookup_func(module, mangled)
                if result is not None:
                    return result
        
        if hasattr(module, '_namespaces'):
            for namespace in module._namespaces:
                mangled = SymbolResolver.mangle_name(namespace, name)
                result = lookup_func(module, mangled)
                if result is not None:
                    return result
        
        return None
    
    @staticmethod
    def resolve_type(module: ir.Module, typename: str, current_namespace: str = "") -> Optional[ir.Type]:
        """Resolve type name to LLVM type."""
        if hasattr(module, 'symbol_table'):
            result = module.symbol_table.lookup(typename)
            
            if result and result[0] == SymbolKind.TYPE:
                if result[1] is not None:
                    return result[1].get_llvm_type(module)
                
                for storage_name in ['_type_aliases', '_struct_types', '_union_types', '_enum_types']:
                    if hasattr(module, storage_name):
                        storage = getattr(module, storage_name)
                        if typename in storage:
                            return storage[typename]
                
                if current_namespace:
                    mangled = SymbolResolver.mangle_name(current_namespace, typename)
                    for storage_name in ['_type_aliases', '_struct_types', '_union_types', '_enum_types']:
                        if hasattr(module, storage_name):
                            storage = getattr(module, storage_name)
                            if mangled in storage:
                                return storage[mangled]
        
        return TypeResolver.resolve_with_namespace(module, typename, current_namespace, TypeResolver.lookup_type)
    
    @staticmethod
    def resolve_type_spec(name: str, module: ir.Module):
        """Get TypeSystem for identifier."""
        if hasattr(module, 'symbol_table'):
            result = module.symbol_table.lookup(name)
            if result:
                kind, type_spec = result
                if kind == SymbolKind.VARIABLE and type_spec is not None:
                    return type_spec
                if kind == SymbolKind.TYPE and type_spec is not None:
                    return type_spec
            entry = module.symbol_table.lookup_variable(name)
            if entry and entry.type_spec is not None:
                return entry.type_spec
        if hasattr(module, '_global_type_info') and name in module._global_type_info:
            return module._global_type_info[name]
        return None
    
    @staticmethod
    def resolve_custom_type(module: ir.Module, typename: str, current_namespace: str = "") -> Optional[ir.Type]:
        """Resolve custom type name to LLVM type."""
        if hasattr(module, 'symbol_table'):
            result = module.symbol_table.lookup(typename)
            if result and result[0] == SymbolKind.TYPE:
                if result[1] is not None:
                    return result[1].get_llvm_type(module)
        return TypeResolver.resolve_type(module, typename, current_namespace)
    
    @staticmethod
    def is_type_defined(typename: str, module) -> bool:
        """Check if type is defined."""
        if hasattr(module, 'symbol_table'):
            result = module.symbol_table.lookup(typename)
            if result and result[0] == SymbolKind.TYPE:
                return True
        if hasattr(module, '_type_aliases') and typename in module._type_aliases:
            return True
        if hasattr(module, '_struct_types') and typename in module._struct_types:
            return True
        if hasattr(module, '_union_types') and typename in module._union_types:
            return True
        if hasattr(module, '_enum_types') and typename in module._enum_types:
            return True
        return False
    
    @staticmethod
    def resolve_struct_type(literal_value: dict, module: ir.Module):
        """Resolve struct type for a struct literal based on its field names."""
        if not isinstance(literal_value, dict):
            raise ValueError("Expected dictionary for struct literal")
        field_names = list(literal_value.keys())
        if hasattr(module, '_struct_types'):
            for struct_name, candidate_type in module._struct_types.items():
                if hasattr(candidate_type, 'names'):
                    if all(field in candidate_type.names for field in field_names):
                        return candidate_type
        raise ValueError(f"No compatible struct type found for fields: {field_names}")


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
class FunctionResolver:
    """Resolves function names within namespace contexts"""
    
    def resolve_function_name(func_name: str, module: ir.Module, current_namespace: str = "") -> Optional[str]:
        if hasattr(module, 'symbol_table'):
            symbol_result = FunctionResolver._resolve_from_symbol_table(
                func_name, module.symbol_table, current_namespace)
            if symbol_result:
                return symbol_result
        
        return SymbolResolver.resolve_function(module, func_name, current_namespace)
    
    @staticmethod
    def _resolve_from_symbol_table(func_name: str, symbol_table, current_namespace: str = "", module: ir.Module = None) -> Optional[str]:
        result = symbol_table.lookup(func_name)
        
        if result and result[0] == SymbolKind.FUNCTION:
            if module:
                if func_name in module.globals:
                    return func_name
                
                if current_namespace:
                    mangled = SymbolResolver.mangle_name(current_namespace, func_name)
                    if mangled in module.globals:
                        return mangled
                
                if hasattr(module, '_using_namespaces'):
                    for ns in module._using_namespaces:
                        mangled = SymbolResolver.mangle_name(ns, func_name)
                        if mangled in module.globals:
                            return mangled
                if hasattr(module, '_namespaces'):
                    for ns in module._namespaces:
                        mangled = SymbolResolver.mangle_name(ns, func_name)
                        if mangled in module.globals:
                            return mangled
            else:
                if current_namespace:
                    mangled = SymbolResolver.mangle_name(current_namespace, func_name)
                    return mangled
                return func_name
        
        return None


@dataclass
class NamespaceTypeHandler:
    """Handles type resolution and registration within namespace contexts."""
    
    def __init__(self, namespace_path: str = ""):
        self.namespace_path = namespace_path
        self.type_registry = {}
        
    def register_type(self, unmangled_name: str, mangled_name: str):
        self.type_registry[unmangled_name] = mangled_name
    
    def resolve_type_name(self, typename: str, current_namespace: str = "") -> str:
        if current_namespace:
            mangled = f"{current_namespace}__{typename}"
            if mangled in self.type_registry.values():
                return mangled
        
        parts = current_namespace.split("::") if current_namespace else []
        while parts:
            parts.pop()
            parent_ns = "__".join(parts)
            mangled = f"{parent_ns}__{typename}" if parent_ns else typename
            if mangled in self.type_registry.values():
                return mangled
        
        if typename in self.type_registry.values():
            return typename
        
        return typename
    
    @staticmethod
    def register_namespace(module: 'ir.Module', namespace: str):
        if not hasattr(module, '_namespaces'):
            module._namespaces = []
        if namespace not in module._namespaces:
            module._namespaces.append(namespace)
    
    @staticmethod
    def add_using_namespace(module: 'ir.Module', namespace: str):
        if not hasattr(module, '_using_namespaces'):
            module._using_namespaces = []
        if namespace not in module._using_namespaces:
            module._using_namespaces.append(namespace)
    
    @staticmethod
    def register_nested_namespaces(namespace: 'NamespaceDef', parent_path: str, module: 'ir.Module'):
        for nested_ns in namespace.nested_namespaces:
            full_nested_name = f"{parent_path}::{nested_ns.name}"
            NamespaceTypeHandler.register_namespace(module, full_nested_name)
            NamespaceTypeHandler.register_nested_namespaces(nested_ns, full_nested_name, module)
    
    @staticmethod
    def create_static_init_builder(module: 'ir.Module') -> 'ir.IRBuilder':
        init_func_name = "__static_init"

        if init_func_name not in module.globals:
            func_type = ir.FunctionType(ir.VoidType(), [])
            init_func = ir.Function(module, func_type, init_func_name)
            block = init_func.append_basic_block("entry")
        else:
            init_func = module.globals[init_func_name]

            if not init_func.blocks:
                block = init_func.append_basic_block("entry")
            else:
                block = init_func.blocks[-1]
                if block.is_terminated:
                    block = init_func.append_basic_block("cont")

        builder = ir.IRBuilder(block)
        builder.initialized_unions = set()
        return builder
    
    @staticmethod
    def finalize_static_init(module: 'ir.Module'):
        if "__static_init" in module.globals:
            init_func = module.globals["__static_init"]
            if init_func.blocks and not init_func.blocks[-1].is_terminated:
                final_builder = ir.IRBuilder(init_func.blocks[-1])
                final_builder.ret_void()
    
    @staticmethod
    def process_namespace_struct(namespace: str, struct_def: 'StructDef', builder: 'ir.IRBuilder', module: 'ir.Module'):
        original_name = struct_def.name
        struct_def.name = f"{namespace.replace('::', '__')}__{struct_def.name}"
        
        original_namespace = getattr(module, '_current_namespace', '')
        original_st_namespace = module.symbol_table.current_namespace if hasattr(module, 'symbol_table') else ''
        
        module._current_namespace = namespace
        if not hasattr(module, 'symbol_table'):
            raise RuntimeError("Module must have symbol_table for namespace support")

        original_namespace = module.symbol_table.current_namespace
        module.symbol_table.set_namespace(namespace)

        try:
            struct_def.codegen(builder, module)
        finally:
            struct_def.name = original_name
            module.symbol_table.set_namespace(original_namespace)
    
    @staticmethod
    def process_namespace_object(namespace: str, obj_def: 'ObjectDef', builder: 'ir.IRBuilder', module: 'ir.Module'):
        original_name = obj_def.name
        obj_def.name = f"{namespace.replace('::', '__')}__{obj_def.name}"
        
        original_namespace = getattr(module, '_current_namespace', '')
        original_st_namespace = module.symbol_table.current_namespace if hasattr(module, 'symbol_table') else ''
        
        module._current_namespace = namespace
        if not hasattr(module, 'symbol_table'):
            raise RuntimeError("Module must have symbol_table for namespace support")

        original_namespace = module.symbol_table.current_namespace
        module.symbol_table.set_namespace(namespace)

        try:
            obj_def.codegen(builder, module)
        finally:
            obj_def.name = original_name
            module.symbol_table.set_namespace(original_namespace)
    
    @staticmethod
    def process_namespace_enum(namespace: str, enum_def: 'EnumDef', builder: 'ir.IRBuilder', module: 'ir.Module'):
        original_name = enum_def.name
        enum_def.name = f"{namespace.replace('::', '__')}__{enum_def.name}"
        
        original_namespace = getattr(module, '_current_namespace', '')
        original_st_namespace = module.symbol_table.current_namespace if hasattr(module, 'symbol_table') else ''
        
        module._current_namespace = namespace
        if not hasattr(module, 'symbol_table'):
            raise RuntimeError("Module must have symbol_table for namespace support")

        original_namespace = module.symbol_table.current_namespace
        module.symbol_table.set_namespace(namespace)

        try:
            enum_def.codegen(builder, module)
        finally:
            enum_def.name = original_name
            module.symbol_table.set_namespace(original_namespace)
    
    @staticmethod
    def process_namespace_variable(namespace: str, var_def: 'VariableDeclaration', module: 'ir.Module'):
        original_name = var_def.name
        var_def.name = f"{namespace.replace('::', '__')}__{var_def.name}"
        
        original_namespace = getattr(module, '_current_namespace', '')
        original_st_namespace = module.symbol_table.current_namespace if hasattr(module, 'symbol_table') else ''
        
        module._current_namespace = namespace
        if hasattr(module, 'symbol_table'):
            module.symbol_table.set_namespace(namespace)
        
        try:
            result = var_def.codegen(None, module)
            return result
        finally:
            var_def.name = original_name
            module._current_namespace = original_namespace
            if hasattr(module, 'symbol_table'):
                module.symbol_table.set_namespace(original_st_namespace)
    
    @staticmethod
    def process_nested_namespace(parent_namespace: str, nested_ns: 'NamespaceDef', builder: 'ir.IRBuilder', module: 'ir.Module'):
        original_name = nested_ns.name
        full_nested_name = f"{parent_namespace}::{nested_ns.name}"
        nested_ns.name = f"{parent_namespace.replace('::', '__')}__{nested_ns.name}"
        
        original_namespace = getattr(module, '_current_namespace', '')
        original_st_namespace = module.symbol_table.current_namespace if hasattr(module, 'symbol_table') else ''
        
        module._current_namespace = full_nested_name
        if not hasattr(module, 'symbol_table'):
            raise RuntimeError("Module must have symbol_table for namespace support")

        original_namespace = module.symbol_table.current_namespace
        module.symbol_table.set_namespace(parent_namespace)

        try:
            nested_ns.codegen(builder, module)
        finally:
            nested_ns.name = original_name
            module.symbol_table.set_namespace(original_namespace)
    
    @staticmethod
    def process_namespace_function(namespace: str, func_def: 'FunctionDef', builder: 'ir.IRBuilder', module: 'ir.Module'):
        """Process a function within a namespace context."""
        from fast import FunctionTypeHandler
        
        original_name = func_def.name
        mangled_func_name = f"{namespace}__{func_def.name}"
        
        func_def.name = mangled_func_name
        
        original_namespace = getattr(module, '_current_namespace', '')
        original_st_namespace = module.symbol_table.current_namespace if hasattr(module, 'symbol_table') else ''
        
        module._current_namespace = namespace
        if not hasattr(module, 'symbol_table'):
            raise RuntimeError("Module must have symbol_table for namespace support")

        original_namespace = module.symbol_table.current_namespace
        module.symbol_table.set_namespace(namespace)

        try:
            func_def.codegen(builder, module)
        finally:
            func_def.name = original_name
            module.symbol_table.set_namespace(original_namespace)
    
    @staticmethod
    def resolve_custom_type(module: ir.Module, typename: str, current_namespace: str = "") -> Optional[ir.Type]:
        return TypeResolver.resolve_custom_type(module, typename, current_namespace)

    @staticmethod
    def is_type_defined(typename: str, module) -> bool:
        return TypeResolver.is_type_defined(typename, module)


@dataclass
class TypeSystem:
    """Legacy TypeSystem for backward compatibility - will be phased out"""
    base_type: Union[DataType, str]
    is_signed: bool = True
    is_const: bool = False
    is_volatile: bool = False
    bit_width: Optional[int] = None
    alignment: Optional[int] = None
    endianness: Optional[int] = 0
    is_array: bool = False
    array_size: Optional[Union[int, Any]] = None
    array_dimensions: Optional[List[Optional[Union[int, Any]]]] = None
    array_element_type: Optional['TypeSystem'] = None
    is_pointer: bool = False
    pointer_depth: int = 0
    custom_typename: Optional[str] = None
    storage_class: Optional[StorageClass] = None
    
    def to_new_type(self) -> BaseType:
        """Convert TypeSystem to new Type system"""
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
            current_namespace = getattr(module, '_current_namespace', '')
            
            resolved_type = NamespaceTypeHandler.resolve_custom_type(
                module, self.custom_typename, current_namespace
            )
            
            if resolved_type is not None:
                if isinstance(resolved_type, ir.ArrayType) and not self.is_array:
                    return ir.PointerType(resolved_type.element)
                if isinstance(resolved_type, int):
                    return ir.IntType(32)
                return resolved_type
            
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

        element_type = base_type
        if self.is_pointer:
            if self.base_type == DataType.VOID or self.base_type == DataType.STRUCT:
                element_type = ir.PointerType(ir.IntType(8))
            else:
                for _ in range(self.pointer_depth if hasattr(self, 'pointer_depth') and self.pointer_depth else 1):
                    element_type = ir.PointerType(element_type)
        
        if self.is_array and self.array_dimensions:
            current_type = element_type
            for dim in reversed(self.array_dimensions):
                if dim is not None:
                    if isinstance(dim, int):
                        current_type = ir.ArrayType(current_type, dim)
                    else:
                        return ir.PointerType(element_type)
                else:
                    current_type = ir.PointerType(current_type)
            return current_type
        elif self.is_array:
            if self.array_size is not None:
                if isinstance(self.array_size, int):
                    return ir.ArrayType(element_type, self.array_size)
                else:
                    return ir.PointerType(element_type)
            else:
                if isinstance(element_type, ir.PointerType):
                    return element_type
                else:
                    return ir.PointerType(element_type)
        
        return element_type


@dataclass
class FunctionPointerType:
    return_type: TypeSystem
    parameter_types: List[TypeSystem]
    
    def get_llvm_type(self, module: ir.Module) -> ir.FunctionType:
        """Convert to LLVM function type"""
        ret_type = self.return_type.get_llvm_type(module)
        param_types = [param.get_llvm_type(module) for param in self.parameter_types]
        return ir.FunctionType(ret_type, param_types)
    
    def get_llvm_pointer_type(self, module: ir.Module) -> ir.PointerType:
        """Get pointer to this function type"""
        func_type = self.get_llvm_type(module)
        return ir.PointerType(func_type)


class CoercionContext:
    def __init__(instance, builder: ir.IRBuilder):
        instance.b = builder

    @staticmethod
    def is_unsigned(val: ir.Value) -> bool:
        spec = getattr(val, "_flux_type_spec", None)
        return spec is not None and not spec.is_signed

    @staticmethod
    def comparison_is_unsigned(a: ir.Value, b: ir.Value) -> bool:
        return CoercionContext.is_unsigned(a) or CoercionContext.is_unsigned(b)

    def normalize_ints(instance, a: ir.Value, b: ir.Value, *, unsigned: bool, promote: bool):
        assert isinstance(a.type, ir.IntType)
        assert isinstance(b.type, ir.IntType)

        if a.type.width == b.type.width:
            return a, b

        width = max(a.type.width, b.type.width) if promote else min(a.type.width, b.type.width)
        ty = ir.IntType(width)

        def convert(v):
            if v.type.width == width:
                return v
            elif v.type.width < width:
                result = instance.b.zext(v, ty) if unsigned else instance.b.sext(v, ty)
            else:
                result = instance.b.trunc(v, ty)
            
            if hasattr(v, '_flux_type_spec'):
                result._flux_type_spec = v._flux_type_spec
                result._flux_type_spec.bit_width = width
            
            return result

        return convert(a), convert(b)

    def ptr_to_i64(instance, v: ir.Value) -> ir.Value:
        if isinstance(v.type, ir.PointerType):
            return instance.b.ptrtoint(v, ir.IntType(64))
        return v

    def emit_int_cmp(instance, op: str, a: ir.Value, b: ir.Value):
        unsigned = instance.comparison_is_unsigned(a, b)
        a, b = instance.normalize_ints(a, b, unsigned=unsigned, promote=True)
        return (
            instance.b.icmp_unsigned(op, a, b)
            if unsigned
            else instance.b.icmp_signed(op, a, b)
        )

    def emit_ptr_cmp(instance, op: str, a: ir.Value, b: ir.Value):
        a = instance.ptr_to_i64(a)
        b = instance.ptr_to_i64(b)
        return instance.b.icmp_unsigned(op, a, b)


def infer_int_width(value: int, data_type: DataType) -> int:
    if data_type not in (DataType.SINT, DataType.UINT):
        raise ValueError("Not an integer literal")
    
    if data_type == DataType.SINT:
        if -(1 << 31) <= value <= (1 << 31) - 1:
            return 32
        else:
            return 64
    else:
        if 0 <= value <= (1 << 32) - 1:
            return 32
        else:
            return 64


def attach_type_metadata(llvm_value: ir.Value, type_spec: Optional[Any] = None, 
                        base_type: Optional[DataType] = None) -> ir.Value:
    bit_width = llvm_value.type.width if hasattr(llvm_value.type, 'width') else None
    
    if type_spec is None and base_type is not None:
        type_spec = type(
            'TypeSystem', (),
            {
                'base_type': base_type,
                'is_signed': (base_type == DataType.SINT),
                'bit_width': bit_width
            })()
    
    if type_spec is not None:
        llvm_value._flux_type_spec = type_spec
    
    return llvm_value


def attach_type_metadata_from_llvm_type(llvm_value: ir.Value, llvm_type: ir.Type, module: ir.Module) -> ir.Value:
    if hasattr(module, '_type_aliases'):
        for alias_name, alias_type in module._type_aliases.items():
            types_match = (str(alias_type) == str(llvm_type)) or (alias_type == llvm_type)
            if types_match:
                is_unsigned_type = False
                if hasattr(module, '_type_alias_specs') and alias_name in module._type_alias_specs:
                    alias_spec = module._type_alias_specs[alias_name]
                    if hasattr(alias_spec, 'is_signed'):
                        is_unsigned_type = not alias_spec.is_signed
                    elif hasattr(alias_spec, 'base_type') and alias_spec.base_type == DataType.UINT:
                        is_unsigned_type = True
                else:
                    is_unsigned_type = alias_name.startswith('u') or alias_name == 'byte'
                
                type_spec = type(
                    'TypeSystem',
                    (),
                    {
                        'base_type': DataType.UINT if is_unsigned_type else DataType.SINT,
                        'is_signed': not is_unsigned_type,
                        'bit_width': llvm_type.width if hasattr(llvm_type, 'width') else None,
                        'custom_typename': alias_name
                    }
                )()
                llvm_value._flux_type_spec = type_spec
                return llvm_value
    
    return llvm_value


def get_array_element_type_spec(array_val: ir.Value):
    if hasattr(array_val, '_flux_array_element_type_spec'):
        return array_val._flux_array_element_type_spec
    
    if hasattr(array_val, '_flux_type_spec'):
        type_spec = array_val._flux_type_spec
        if hasattr(type_spec, 'array_element_type') and type_spec.array_element_type:
            return type_spec.array_element_type
    
    return None


def get_comparison_signedness(left_val: ir.Value, right_val: ir.Value) -> bool:
    left_unsigned = CoercionContext.is_unsigned(left_val)
    right_unsigned = CoercionContext.is_unsigned(right_val)
    
    if left_unsigned or right_unsigned:
        return False
    return True


def get_builtin_bit_width(base_type: DataType) -> int:
    if base_type in (DataType.SINT, DataType.UINT):
        return 32
    elif base_type == DataType.FLOAT:
        return 32
    elif base_type == DataType.CHAR:
        return 8
    elif base_type == DataType.BOOL:
        return 1
    else:
        raise ValueError(f"Type {base_type} does not have a defined bit width")


def get_custom_type_info(typename: str, module: ir.Module) -> Dict:
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
    if not types:
        raise ValueError("Cannot find common type of empty list")
    
    first_type = types[0]
    
    if all(t == first_type for t in types):
        return first_type
    
    if all(isinstance(t, ir.IntType) for t in types):
        max_width = max(t.width for t in types)
        return ir.IntType(max_width)
    
    if all(isinstance(t, (ir.FloatType, ir.DoubleType)) for t in types):
        return ir.DoubleType()
    
    return first_type


def cast_to_type(builder: ir.IRBuilder, value: ir.Value, target_type: ir.Type) -> ir.Value:
    source_type = value.type
    
    if source_type == target_type:
        return value
    
    if isinstance(source_type, ir.IntType) and isinstance(target_type, ir.IntType):
        if source_type.width < target_type.width:
            if CoercionContext.is_unsigned(value):
                return builder.zext(value, target_type)
            else:
                return builder.sext(value, target_type)
        elif source_type.width > target_type.width:
            return builder.trunc(value, target_type)
        return value
    
    if isinstance(source_type, ir.IntType) and isinstance(target_type, (ir.FloatType, ir.DoubleType)):
        if CoercionContext.is_unsigned(value):
            return builder.uitofp(value, target_type)
        else:
            return builder.sitofp(value, target_type)
    
    if isinstance(source_type, (ir.FloatType, ir.DoubleType)) and isinstance(target_type, ir.IntType):
        return builder.fptosi(value, target_type)
    
    if isinstance(source_type, (ir.FloatType, ir.DoubleType)) and isinstance(target_type, (ir.FloatType, ir.DoubleType)):
        if source_type.width < target_type.width:
            return builder.fpext(value, target_type)
        elif source_type.width > target_type.width:
            return builder.fptrunc(value, target_type)
        return value
    
    if isinstance(source_type, ir.PointerType) and isinstance(target_type, ir.PointerType):
        return builder.bitcast(value, target_type)
    
    return builder.bitcast(value, target_type)


def infer_struct_name(instance: ir.Value, module: ir.Module) -> str:
    """
    Infer the struct name from an LLVM struct instance.
    """
    struct_type = instance.type
    if isinstance(struct_type, ir.PointerType):
        struct_type = struct_type.pointee
    
    if hasattr(struct_type, 'name') and struct_type.name:
        return struct_type.name
    
    if hasattr(module, '_struct_types'):
        for name, registered_type in module._struct_types.items():
            if registered_type == struct_type:
                return name
    
    raise ValueError("Cannot infer struct name from instance")


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
        return (val.type.element, val.type.count)
    elif isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, ir.ArrayType):
        array_type = val.type.pointee
        return (array_type.element, array_type.count)
    else:
        raise ValueError(f"Value is not an array or array pointer: {val.type}")

def emit_memcpy(builder: ir.IRBuilder, module: ir.Module, dst_ptr: ir.Value, src_ptr: ir.Value, bytes: int) -> None:
    """Emit llvm.memcpy intrinsic call"""
    memcpy_name = "llvm.memcpy.p0i8.p0i8.i64"
    if memcpy_name not in module.globals:
        memcpy_type = ir.FunctionType(
            ir.VoidType(),
            [ir.PointerType(ir.IntType(8)),
             ir.PointerType(ir.IntType(8)),
             ir.IntType(64),
             ir.IntType(1)])
        memcpy_func = ir.Function(module, memcpy_type, name=memcpy_name)
        memcpy_func.attributes.add('nounwind')
    else:
        memcpy_func = module.globals[memcpy_name]
    
    i8_ptr = ir.PointerType(ir.IntType(8))
    if dst_ptr.type != i8_ptr:
        dst_ptr = builder.bitcast(dst_ptr, i8_ptr)
    if src_ptr.type != i8_ptr:
        src_ptr = builder.bitcast(src_ptr, i8_ptr)
    
    builder.call(memcpy_func, [
        dst_ptr,
        src_ptr,
        ir.Constant(ir.IntType(64), bytes),
        ir.Constant(ir.IntType(1), 0)
    ])

def is_macro_defined(module: ir.Module, macro_name: str) -> bool:
    """
    Check if a preprocessor macro is defined in the module.
    """
    if not hasattr(module, '_preprocessor_macros'):
        return False
    
    if macro_name not in module._preprocessor_macros:
        return False
    
    value = module._preprocessor_macros[macro_name]
    
    if isinstance(value, str):
        if value == "" or value == "0":
            return False
        return True
    
    return bool(value)


def string_heap_allocation(builder: ir.IRBuilder, module: ir.Module, str_val):
    malloc_fn = module.globals.get('malloc')
    if malloc_fn is None:
        malloc_type = ir.FunctionType(ir.PointerType(ir.IntType(8)), [ir.IntType(64)])
        malloc_fn = ir.Function(module, malloc_type, 'malloc')
        malloc_fn.linkage = 'external'
    
    size = ir.Constant(ir.IntType(64), len(str_val.type))
    heap_ptr = builder.call(malloc_fn, [size], name="heap_str")
    
    array_ptr = builder.bitcast(heap_ptr, ir.PointerType(str_val.type))
    
    builder.store(str_val, array_ptr)
    
    zero = ir.Constant(ir.IntType(32), 0)
    return builder.gep(array_ptr, [zero, zero], name="heap_str_ptr")

def array_heap_allocation(builder: ir.IRBuilder, module: ir.Module, str_val):
    malloc_fn = module.globals.get('malloc')
    if malloc_fn is None:
        malloc_type = ir.FunctionType(ir.PointerType(ir.IntType(8)), [ir.IntType(64)])
        malloc_fn = ir.Function(module, malloc_type, 'malloc')
        malloc_fn.linkage = 'external'
    
    element_size = str_val.type.element.width // 8
    array_count = str_val.type.count
    total_bytes = element_size * array_count
    
    size = ir.Constant(ir.IntType(64), total_bytes)
    heap_ptr = builder.call(malloc_fn, [size], name="heap_array")
    
    array_ptr = builder.bitcast(heap_ptr, ir.PointerType(str_val.type))
    
    builder.store(str_val, array_ptr)
    
    array_ptr.type._is_array_pointer = True
    
    zero = ir.Constant(ir.IntType(32), 0)
    return builder.gep(array_ptr, [zero, zero], name="heap_array_ptr")


def handle_union_member_assignment(builder, module, union_ptr, union_name, member_name, val):
    if not hasattr(module, '_union_member_info') or union_name not in module._union_member_info:
        raise ValueError(f"Union member info not found for '{union_name}'")
    
    union_info = module._union_member_info[union_name]
    member_names = union_info['member_names']
    member_types = union_info['member_types']
    is_tagged = union_info['is_tagged']
    
    if member_name == '_':
        if not is_tagged:
            raise ValueError(f"Cannot assign to tag '._' on non-tagged union '{union_name}'")
        
        tag_ptr = builder.gep(
            union_ptr,
            [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), 0)],
            inbounds=True,
            name="union_tag_ptr"
        )
        builder.store(val, tag_ptr)
        return val
    
    if member_name not in member_names:
        raise ValueError(f"Member '{member_name}' not found in union '{union_name}'")
    
    member_index = member_names.index(member_name)
    member_type = member_types[member_index]
    
    union_var_id = f"{union_ptr.name}_{id(union_ptr)}"
    
    if hasattr(builder, 'initialized_unions') and union_var_id in builder.initialized_unions:
        raise RuntimeError(f"Union variable is immutable after initialization. Cannot reassign member '{member_name}' of union '{union_name}'")
    
    if not hasattr(builder, 'initialized_unions'):
        builder.initialized_unions = set()
    builder.initialized_unions.add(union_var_id)
    
    if is_tagged:
        data_ptr = builder.gep(
            union_ptr,
            [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), 1)],
            inbounds=True,
            name="union_data_ptr"
        )
        member_ptr_type = ir.PointerType(member_type)
        casted_ptr = builder.bitcast(data_ptr, member_ptr_type, name=f"union_as_{member_name}")
        builder.store(val, casted_ptr)
        return val
    else:
        member_ptr_type = ir.PointerType(member_type)
        casted_ptr = builder.bitcast(union_ptr, member_ptr_type, name=f"union_as_{member_name}")
        builder.store(val, casted_ptr)
        return val


def coerce_return_value(builder: ir.IRBuilder,value: ir.Value,expected: ir.Type) -> ir.Value:
    ctx = CoercionContext(builder)
    src = value.type

    if src == expected:
        return value

    if isinstance(src, ir.IntType) and isinstance(expected, ir.IntType):
        if src.width < expected.width:
            unsigned = CoercionContext.is_unsigned(value)
            result = builder.zext(value, expected) if unsigned else builder.sext(value, expected)
            if hasattr(value, '_flux_type_spec'):
                result._flux_type_spec = value._flux_type_spec
                result._flux_type_spec.bit_width = expected.width
            return result
        elif src.width > expected.width:
            result = builder.trunc(value, expected)
            if hasattr(value, '_flux_type_spec'):
                result._flux_type_spec = value._flux_type_spec
                result._flux_type_spec.bit_width = expected.width
            return result

    if isinstance(src, ir.PointerType) and isinstance(expected, ir.PointerType):
        return builder.bitcast(value, expected)

    if isinstance(src, ir.LiteralStructType) and isinstance(expected, ir.LiteralStructType):
        if src != expected:
            raise TypeError(
                f"Return struct type mismatch: {src} != {expected}"
            )
        return value

    if isinstance(src, ir.ArrayType) and isinstance(expected, ir.ArrayType):
        src_elem = src.element
        exp_elem = expected.element
        
        if isinstance(src_elem, ir.IntType) and isinstance(exp_elem, ir.IntType):
            src_total_bits = src.count * src_elem.width
            exp_total_bits = expected.count * exp_elem.width
            
            if src_total_bits == exp_total_bits:
                temp = builder.alloca(src, name="array_convert_temp")
                
                builder.store(value, temp)
                
                temp_as_expected = builder.bitcast(temp, ir.PointerType(expected))
                
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
    
    raise TypeError(f"Cannot coerce {src} to {expected}")


def eval_const_binary_op(left: ir.Constant, right: ir.Constant, 
                        op: Operator) -> Optional[ir.Constant]:
    if not (isinstance(left.type, ir.IntType) and isinstance(right.type, ir.IntType)):
        return None
    
    left_val = left.constant
    right_val = right.constant
    result_type = left.type
    
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
        elif op == Operator.POWER:
            result = left_val ** right_val
        elif op == Operator.BITAND:
            result = left_val & right_val
        elif op == Operator.BITOR:
            result = left_val | right_val
        elif op == Operator.XOR:
            result = left_val ^ right_val
        elif op == Operator.BITXOR:
            result = left_val ^ right_val
        elif op == Operator.AND:
            result = left_val & right_val
        elif op == Operator.OR:
            result = left_val | right_val
        elif op == Operator.BITSHIFT_LEFT:
            result = left_val << right_val
        elif op == Operator.BITSHIFT_RIGHT:
            result = left_val >> right_val
        elif op == Operator.NAND:
            result = ~(left_val & right_val)
        elif op == Operator.NOR:
            result = ~(left_val | right_val)
        elif op == Operator.BITNAND:
            result = ~(left_val & right_val)
        elif op == Operator.BITNOR:
            result = ~(left_val | right_val)
        else:
            return None
        
        return ir.Constant(result_type, result)
    except:
        return None


def eval_const_unary_op(operand: ir.Constant, op: Operator) -> Optional[ir.Constant]:
    if not isinstance(operand.type, ir.IntType):
        return None
    
    val = operand.constant
    result_type = operand.type
    
    try:
        if op == Operator.SUB:
            result = -val
        elif op == Operator.NOT:
            result = 1 if val == 0 else 0
        else:
            return None
        
        return ir.Constant(result_type, result)
    except:
        return None


def get_default_initializer(llvm_type: ir.Type) -> ir.Constant:
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
        return ir.Constant(llvm_type, None)


def pack_array_to_integer(builder: ir.IRBuilder, module: ir.Module,
                         array_val: ir.Value, element_type: ir.Type,
                         element_count: int) -> ir.Value:
    if not isinstance(element_type, ir.IntType):
        raise ValueError("Can only pack integer arrays")
    
    element_bits = element_type.width
    total_bits = element_bits * element_count
    
    packed_type = ir.IntType(total_bits)
    result = ir.Constant(packed_type, 0)
    
    for i in range(element_count):
        elem_ptr = builder.gep(array_val, [ir.Constant(ir.IntType(32), 0),
                                           ir.Constant(ir.IntType(32), i)])
        elem = builder.load(elem_ptr)
        
        elem_extended = builder.zext(elem, packed_type)
        
        shift_amount = ir.Constant(packed_type, i * element_bits)
        elem_shifted = builder.shl(elem_extended, shift_amount)
        
        result = builder.or_(result, elem_shifted)
    
    return result


def pack_array_to_integer_runtime(builder: ir.IRBuilder,
                                  array_ptr: ir.Value,
                                  element_type: ir.Type,
                                  element_count: ir.Value) -> ir.Value:
    element_bits = element_type.width
    
    packed_type = ir.IntType(64)
    result = ir.Constant(packed_type, 0)
    
    return result


def pack_array_pointer_to_integer(builder: ir.IRBuilder, module: ir.Module,
                                  array_ptr: ir.Value, element_type: ir.Type,
                                  element_count: int) -> ir.Value:
    if not isinstance(element_type, ir.IntType):
        raise ValueError("Can only pack integer arrays")
    
    element_bits = element_type.width
    total_bits = element_bits * element_count
    packed_type = ir.IntType(total_bits)
    
    result = ir.Constant(packed_type, 0)
    
    for i in range(element_count):
        idx = ir.Constant(ir.IntType(32), i)
        elem_ptr = builder.gep(array_ptr, [ir.Constant(ir.IntType(32), 0), idx])
        elem = builder.load(elem_ptr)
        
        elem_extended = builder.zext(elem, packed_type)
        shift_amount = ir.Constant(packed_type, i * element_bits)
        elem_shifted = builder.shl(elem_extended, shift_amount)
        
        result = builder.or_(result, elem_shifted)
    
    return result


def create_global_array_concat(module: ir.Module, left_val: ir.Value,
                               right_val: ir.Value) -> ir.Value:
    if not (isinstance(left_val, ir.Constant) and isinstance(right_val, ir.Constant)):
        raise ValueError("Global array concatenation requires constants")
    
    left_type = left_val.type
    right_type = right_val.type
    
    if not (isinstance(left_type, ir.ArrayType) and isinstance(right_type, ir.ArrayType)):
        raise ValueError("Can only concatenate arrays")
    
    if left_type.element != right_type.element:
        raise ValueError("Array element types must match for concatenation")
    
    new_count = left_type.count + right_type.count
    new_type = ir.ArrayType(left_type.element, new_count)
    
    left_elements = list(left_val.constant) if hasattr(left_val, 'constant') else []
    right_elements = list(right_val.constant) if hasattr(right_val, 'constant') else []
    
    combined = left_elements + right_elements
    return ir.Constant(new_type, combined)


def create_runtime_array_concat(builder: ir.IRBuilder, module: ir.Module,
                                left_val: ir.Value, right_val: ir.Value) -> ir.Value:
    left_type = left_val.type.pointee if isinstance(left_val.type, ir.PointerType) else left_val.type
    right_type = right_val.type.pointee if isinstance(right_val.type, ir.PointerType) else right_val.type
    
    if not (isinstance(left_type, ir.ArrayType) and isinstance(right_type, ir.ArrayType)):
        raise ValueError("Can only concatenate arrays")
    
    left_count = left_type.count
    right_count = right_type.count
    new_count = left_count + right_count
    
    element_type = left_type.element
    new_array_type = ir.ArrayType(element_type, new_count)
    new_array = builder.alloca(new_array_type)
    
    for i in range(left_count):
        src_ptr = builder.gep(left_val, [ir.Constant(ir.IntType(32), 0),
                                        ir.Constant(ir.IntType(32), i)])
        dst_ptr = builder.gep(new_array, [ir.Constant(ir.IntType(32), 0),
                                         ir.Constant(ir.IntType(32), i)])
        val = builder.load(src_ptr)
        builder.store(val, dst_ptr)
    
    for i in range(right_count):
        src_ptr = builder.gep(right_val, [ir.Constant(ir.IntType(32), 0),
                                        ir.Constant(ir.IntType(32), i)])
        dst_ptr = builder.gep(new_array, [ir.Constant(ir.IntType(32), 0),
                                         ir.Constant(ir.IntType(32), left_count + i)])
        val = builder.load(src_ptr)
        builder.store(val, dst_ptr)
    
    return new_array