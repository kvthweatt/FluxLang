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


#faulthandler.enable()

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
        # DEBUG: Check types
        if not isinstance(self.namespace, str):
            print(f"[ERROR] namespace is {type(self.namespace)}, not str!", file=sys.stderr)
            print(f"[ERROR] namespace value: {self.namespace}", file=sys.stderr)
            raise TypeError(f"namespace must be str, got {type(self.namespace)}")
        if not isinstance(self.name, str):
            print(f"[ERROR] name is {type(self.name)}, not str!", file=sys.stderr)
            print(f"[ERROR] name value: {self.name}", file=sys.stderr)
            print(f"[ERROR] namespace: {self.namespace}", file=sys.stderr)
            raise TypeError(f"name must be str, got {type(self.name)}")
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
        #print(f"[SCOPE] enter_scope() called - now at level {self.scope_level}, total scopes: {len(self.scopes)}", file=sys.stderr)
        #print(f"[SCOPE] Call stack:", file=sys.stderr)
        #for line in traceback.format_stack()[-4:-1]:
            #print(f"  {line.strip()}", file=sys.stderr)
    
    def exit_scope(self):
        """Exit function/block scope"""
        if len(self.scopes) > 1:
            popped = self.scopes.pop()
            #print(f"[SCOPE] exit_scope() called - now at level {self.scope_level}, total scopes: {len(self.scopes)}", file=sys.stderr)
            #print(f"[SCOPE]   Popped scope had {len(popped)} entries: {list(popped.keys())}", file=sys.stderr)
        #else:
        #    print(f"[SCOPE] exit_scope() called but already at global scope!", file=sys.stderr)

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
        
        # SAFETY: Validate name is actually a string
        if not isinstance(name, str):
            print(f"[ERROR] define() called with non-string name!", file=sys.stderr)
            print(f"[ERROR]   name type: {type(name)}", file=sys.stderr)
            print(f"[ERROR]   name value: {name}", file=sys.stderr)
            print(f"[ERROR]   kind: {kind}", file=sys.stderr)
            import traceback
            traceback.print_stack()
            raise TypeError(f"SymbolTable.define() requires name to be str, got {type(name)}")

        #print(f"[SYMBOL_TABLE] define(name='{name}', kind={kind})", file=sys.stderr)
        #print(f"[SYMBOL_TABLE]   scope_level: {self.scope_level}", file=sys.stderr)
        #print(f"[SYMBOL_TABLE]   current_namespace: {self.current_namespace}", file=sys.stderr)
        #print(f"[SYMBOL_TABLE]   scopes count: {len(self.scopes)}", file=sys.stderr)
        
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
        #print(f"[SYMBOL_TABLE]   Added '{name}' to scope {len(self.scopes)-1}", file=sys.stderr)
        
        # Only globals go into _global_symbols
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
        #print(f"[SYMBOL_TABLE] lookup_any('{name}')", file=sys.stderr)
        #print(f"[SYMBOL_TABLE]   current_namespace: {current_namespace or self.current_namespace}", file=sys.stderr)
        #print(f"[SYMBOL_TABLE]   scope_level: {self.scope_level}", file=sys.stderr)
        #print(f"[SYMBOL_TABLE]   scopes: {[list(s.keys()) for s in self.scopes]}", file=sys.stderr)
        
        if current_namespace is None:
            current_namespace = self.current_namespace
        
        # Check local scopes first (reverse order)
        for i, scope in enumerate(reversed(self.scopes)):
            if name in scope:
                #print(f"[SYMBOL_TABLE]   Found '{name}' in scope {len(self.scopes)-1-i}", file=sys.stderr)
                return scope[name]
        
        # Then global with namespace resolution
        result = self._resolve_with_namespaces(name, current_namespace)
        #if result:
        #    print(f"[SYMBOL_TABLE]   Found '{name}' via namespace resolution", file=sys.stderr)
        #else:
        #    print(f"[SYMBOL_TABLE]   NOT FOUND: '{name}'", file=sys.stderr)
        return result
    
    def lookup_type(self, name: str, current_namespace: str = None) -> Optional[SymbolEntry]:
        entry = self.lookup_any(name, current_namespace)
        if entry and entry.kind in (SymbolKind.TYPE, SymbolKind.STRUCT, 
                                    SymbolKind.UNION, SymbolKind.ENUM):
            return entry
        return None
    
    def lookup_variable(self, name: str, current_namespace: str = None) -> Optional[SymbolEntry]:
        entry = self.lookup_any(name, current_namespace)
        #print(f"[SYMBOL_TABLE] lookup_variable('{name}')", file=sys.stderr)
        #if entry:
        #    print(f"[SYMBOL_TABLE]   Found entry: kind={entry.kind}, type(kind)={type(entry.kind)}", file=sys.stderr)
        #    print(f"[SYMBOL_TABLE]   SymbolKind.VARIABLE={SymbolKind.VARIABLE}, type={type(SymbolKind.VARIABLE)}", file=sys.stderr)
        #    print(f"[SYMBOL_TABLE]   Comparison: {entry.kind} == {SymbolKind.VARIABLE} = {entry.kind == SymbolKind.VARIABLE}", file=sys.stderr)
        #else:
        #    print(f"[SYMBOL_TABLE]   No entry found", file=sys.stderr)
        if entry and entry.kind == SymbolKind.VARIABLE:
            #print(f"[SYMBOL_TABLE]   Returning variable entry", file=sys.stderr)
            return entry
        #print(f"[SYMBOL_TABLE]   Entry is not a VARIABLE (or None), returning None", file=sys.stderr)
        return
    
    def lookup_function(self, name: str, current_namespace: str = None) -> Optional[SymbolEntry]:
        entry = self.lookup_any(name, current_namespace)
        if entry and entry.kind == SymbolKind.FUNCTION:
            return entry
        return None
    
    def _resolve_with_namespaces(self, name: str, current_namespace: str) -> Optional[SymbolEntry]:
        # 1. Exact match
        if name in self._global_symbols:
            return self._global_symbols[name]
        
        # 2. Current namespace
        if current_namespace:
            mangled = self._mangle_name(current_namespace, name)
            if mangled in self._global_symbols:
                return self._global_symbols[mangled]
        
        # 3. Parent namespaces
        if current_namespace:
            parts = current_namespace.split('::')
            while parts:
                parts.pop()
                parent_ns = '::'.join(parts)
                mangled = self._mangle_name(parent_ns, name) if parent_ns else name
                if mangled in self._global_symbols:
                    return self._global_symbols[mangled]
        
        # 4. Using namespaces
        for namespace in self.using_namespaces:
            mangled = self._mangle_name(namespace, name)
            if mangled in self._global_symbols:
                return self._global_symbols[mangled]
        
        # 5. All registered namespaces
        for namespace in self.registered_namespaces:
            mangled = self._mangle_name(namespace, name)
            if mangled in self._global_symbols:
                return self._global_symbols[mangled]
        
        return None
    
    @staticmethod
    def _mangle_name(namespace: str, name: str) -> str:
        if not namespace:
            return name
        return namespace.replace('::', '__') + '__' + name
    
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
    """
    Centralized resolver for ALL identifier, type, and function lookups.
    Handles ALL module name path scope and mangling.
    """

    def resolve(typename: str, module: ir.Module) -> Optional[ir.Type]:
        """
        Resolve a type name using current namespace from module.
        """
        current_ns = TypeResolver.get_current_namespace(module)
        return TypeResolver.resolve_type(module, typename, current_ns)
    
    # ============================================================================
    # Name Mangling - ALL mangling must use this
    # ============================================================================
    
    @staticmethod
    def mangle_name(namespace: str, name: str) -> str:
        """
        Convert namespace::name to namespace__name.
        THIS is the ONLY place where :: -> __ conversion should happen.
        
        Args:
            namespace: Namespace path (e.g., 'std::types')
            name: Unmangled name
            
        Returns:
            Mangled name (e.g., 'std__types__name')
        """
        if not namespace:
            return name
        return namespace.replace('::', '__') + '__' + name
    
    # ============================================================================
    # Storage Access - Direct lookup in module storage
    # ============================================================================
    
    @staticmethod
    def lookup_in_storage(module: ir.Module, name: str, 
                          storage_name: str) -> Optional[Any]:
        """
        Direct lookup in a specific module storage.
        
        Args:
            module: LLVM module
            name: Name to look up
            storage_name: '_type_aliases', '_struct_types', '_union_types', 
                         '_enum_types', 'globals', '_struct_vtables'
            
        Returns:
            Found item or None
        """
        if not hasattr(module, storage_name):
            return None
        
        storage = getattr(module, storage_name)
        if storage is None or name not in storage:
            return None
        
        result = storage[name]
        
        # Special case: type aliases that are array types return pointer to element
        if storage_name == '_type_aliases' and isinstance(result, ir.ArrayType):
            return ir.PointerType(result.element)
        
        return result
    
    @staticmethod
    def lookup_type(module: ir.Module, name: str) -> Optional[ir.Type]:
        """
        Look up a type in type-related storage (_type_aliases, _struct_types, etc).
        Direct lookup only - no namespace resolution.
        
        Args:
            module: LLVM module
            name: Type name (can be mangled)
            
        Returns:
            LLVM type or None
        """
        # Check all type storage in order
        for storage_name in ['_type_aliases', '_struct_types', '_union_types', '_enum_types']:
            result = TypeResolver.lookup_in_storage(module, name, storage_name)
            if result is not None:
                return result
        return None
    
    @staticmethod
    def lookup_global(module: ir.Module, name: str) -> Optional[Any]:
        """
        Look up in module.globals (variables and functions).
        Direct lookup only - no namespace resolution.
        
        Args:
            module: LLVM module  
            name: Global name (can be mangled)
            
        Returns:
            Global variable/function or None
        """
        return TypeResolver.lookup_in_storage(module, name, 'globals')
    
    # ============================================================================
    # Namespace Resolution - The main algorithm
    # ============================================================================
    
    @staticmethod
    def resolve_with_namespace(
        module: ir.Module,
        name: str,
        current_namespace: str = "",
        lookup_func=None
    ) -> Optional[Any]:
        """
        Resolve a name through the namespace hierarchy.
        
        CORE RESOLUTION ALGORITHM
        Search order:
        1. Exact match (name as-is)
        2. Current namespace + name
        3. Parent namespaces + name (walking up)
        4. Using namespaces + name
        5. All registered namespaces + name
        
        Args:
            module: LLVM module
            name: Name to resolve (unmangled)
            current_namespace: Current namespace context (e.g., 'std::types')
            lookup_func: Function to do actual lookup (default: lookup_type)
                        Should be lookup_type or lookup_global
            
        Returns:
            Resolved item or None
        """
        #print("IN RESOLVE_WITH_NAMESPACE()")
        if lookup_func is None:
            lookup_func = TypeResolver.lookup_type
        
        # 1. Try exact match first
        result = lookup_func(module, name)
        if result is not None:
            return result
        
        # 2. Try current namespace
        if current_namespace:
            mangled = TypeResolver.mangle_name(current_namespace, name)
            result = lookup_func(module, mangled)
            if result is not None:
                return result
        
        # 3. Try parent namespaces (walk up the tree)
        if current_namespace:
            parts = current_namespace.split('::')
            while parts:
                parts.pop()
                parent_ns = '::'.join(parts)
                if parent_ns:
                    mangled = TypeResolver.mangle_name(parent_ns, name)
                else:
                    mangled = name
                
                result = lookup_func(module, mangled)
                if result is not None:
                    return result
        
        # 4. Try using namespaces
        if hasattr(module, '_using_namespaces'):
            for namespace in module._using_namespaces:
                mangled = TypeResolver.mangle_name(namespace, name)
                result = lookup_func(module, mangled)
                if result is not None:
                    return result
        
        # 5. Try all registered namespaces
        if hasattr(module, '_namespaces'):
            for namespace in module._namespaces:
                mangled = TypeResolver.mangle_name(namespace, name)
                result = lookup_func(module, mangled)
                if result is not None:
                    return result
        
        return None
    
    # ============================================================================
    # High-level resolution methods - Use these from other code
    # ============================================================================
    
    @staticmethod
    def resolve_type(module: ir.Module, typename: str, current_namespace: str = "") -> Optional[ir.Type]:
        """
        Resolve a type name.
        
        UPDATED: Now uses symbol_table as the PRIMARY source of truth
        
        Args:
            module: LLVM module
            typename: Type name to resolve
            current_namespace: Current namespace context
            
        Returns:
            LLVM type or None
        """
        #print("IN TYPERESOLVER RESOLVE_TYPE()")
        # 1. SYMBOL TABLE - HIGHEST PRIORITY (PRIMARY SOURCE)
        if hasattr(module, 'symbol_table'):
            result = module.symbol_table.lookup(typename)
            
            if result and result[0] == SymbolKind.TYPE:
                # result[1] should be the TypeSystem for this type alias
                if result[1] is not None:
                    # Convert TypeSystem to LLVM type
                    return result[1].get_llvm_type(module)
                
                # If no TypeSystem stored but it's marked as a type,
                # try to find it in module storage
                # First try direct name
                for storage_name in ['_type_aliases', '_struct_types', '_union_types', '_enum_types']:
                    if hasattr(module, storage_name):
                        storage = getattr(module, storage_name)
                        if typename in storage:
                            return storage[typename]
                
                # Try mangled name in current namespace
                if current_namespace:
                    mangled = TypeResolver.mangle_name(current_namespace, typename)
                    for storage_name in ['_type_aliases', '_struct_types', '_union_types', '_enum_types']:
                        if hasattr(module, storage_name):
                            storage = getattr(module, storage_name)
                            if mangled in storage:
                                return storage[mangled]
        
        # 2. NAMESPACE RESOLUTION - fallback for types not in symbol table yet
        # (e.g., during parsing before all types are registered)
        return TypeResolver.resolve_with_namespace(
            module, typename, current_namespace, TypeResolver.lookup_type
        )
    
    @staticmethod
    def resolve_function(module: ir.Module, func_name: str, current_namespace: str = "") -> Optional[str]:
        """
        Resolve a function name and return its mangled name.
        
        UPDATED: Now uses symbol_table as PRIMARY source
        
        Args:
            module: LLVM module
            func_name: Function name to resolve
            current_namespace: Current namespace context
            
        Returns:
            Mangled function name or None
        """
        # 1. SYMBOL TABLE - HIGHEST PRIORITY
        #print("IN RESOLVE_FUNCTION()")
        if hasattr(module, 'symbol_table'):
            # Use lookup_function which does full namespace resolution
            func_entry = module.symbol_table.lookup_function(func_name, current_namespace)
            
            if func_entry:
                # Found in symbol table - now find it in module.globals
                # Try mangled name first
                if func_entry.mangled_name in module.globals:
                    return func_entry.mangled_name
                
                # Try unmangled name
                if func_name in module.globals:
                    return func_name
        
        # 2. NAMESPACE RESOLUTION - fallback
        result = TypeResolver.resolve_with_namespace(
            module, func_name, current_namespace, TypeResolver.lookup_global
        )
        
        if result is not None and isinstance(result, ir.Function):
            return result.name
        
        return None
    
    @staticmethod
    def resolve_identifier(module: ir.Module, name: str, current_namespace: str = "") -> Optional[str]:
        """
        Resolve an identifier (variable or type alias) and return its mangled name.
        
        UPDATED: Now uses symbol_table as PRIMARY source
        
        Args:
            module: LLVM module
            name: Identifier name
            current_namespace: Current namespace context
            
        Returns:
            Mangled name or None
        """
        # 1. SYMBOL TABLE - HIGHEST PRIORITY
        if hasattr(module, 'symbol_table'):
            #print("IN RESOLVE_IDENTIFIER()")
            result = module.symbol_table.lookup(name)
            
            if result:
                kind = result[0]
                
                # Variable or type - try to find in module
                if kind == SymbolKind.VARIABLE or kind == SymbolKind.TYPE:
                    # Try direct name first
                    if name in module.globals:
                        return name
                    
                    # Try mangled name with current namespace
                    if current_namespace:
                        mangled = TypeResolver.mangle_name(current_namespace, name)
                        if mangled in module.globals:
                            return mangled
                    
                    # Try type aliases for TYPE kind
                    if kind == SymbolKind.TYPE and hasattr(module, '_type_aliases'):
                        if name in module._type_aliases:
                            return name
                        if current_namespace:
                            mangled = TypeResolver.mangle_name(current_namespace, name)
                            if mangled in module._type_aliases:
                                return mangled
        
        # 2. MODULE GLOBALS - direct resolution (fallback)
        result = TypeResolver.resolve_with_namespace(
            module, name, current_namespace, TypeResolver.lookup_global
        )
        
        if result is not None:
            # Find the actual key used in globals
            if name in module.globals:
                return name
            
            if current_namespace:
                mangled = TypeResolver.mangle_name(current_namespace, name)
                if mangled in module.globals:
                    return mangled
            
            if hasattr(module, '_using_namespaces'):
                for namespace in module._using_namespaces:
                    mangled = TypeResolver.mangle_name(namespace, name)
                    if mangled in module.globals:
                        return mangled
        
        # 3. TYPE ALIASES - fallback
        result = TypeResolver.resolve_with_namespace(
            module, name, current_namespace, TypeResolver.lookup_type
        )
        
        if result is not None:
            if hasattr(module, '_type_aliases'):
                if name in module._type_aliases:
                    return name
                
                if current_namespace:
                    mangled = TypeResolver.mangle_name(current_namespace, name)
                    if mangled in module._type_aliases:
                        return mangled
                
                if hasattr(module, '_using_namespaces'):
                    for namespace in module._using_namespaces:
                        mangled = TypeResolver.mangle_name(namespace, name)
                        if mangled in module._type_aliases:
                            return mangled
        
        return None
    
    @staticmethod
    def get_current_namespace(module: ir.Module) -> str:
        """Get current namespace from symbol table (UNIFIED)."""
        if hasattr(module, 'symbol_table'):
            return module.symbol_table.current_namespace
        return ''


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
        """
        Resolve function name and return mangled name.
        First tries symbol table if available, then falls back to type resolver.
        """
        # Try symbol table first if available
        if hasattr(module, 'symbol_table'):
            symbol_result = FunctionResolver._resolve_from_symbol_table(
                func_name, module.symbol_table, current_namespace)
            if symbol_result:
                return symbol_result
        
        # Fall back to existing type resolver
        return TypeResolver.resolve_function(module, func_name, current_namespace)
    
    @staticmethod
    def _resolve_from_symbol_table(func_name: str, symbol_table, current_namespace: str = "", module: ir.Module = None) -> Optional[str]:
        """
        Resolve a function using the symbol table.
        
        Args:
            func_name: The function name to resolve
            symbol_table: The SymbolTable instance
            current_namespace: Current namespace context
            module: LLVM module (to check for actual function existence)
            
        Returns:
            The resolved function name (potentially mangled) or None if not found
        """
        
        # Look up the function in the symbol table
        #print("IN _RESOLVE_FROMsymbol_table()")
        result = symbol_table.lookup(func_name)
        
        if result and result[0] == SymbolKind.FUNCTION:
            # If we have a module, verify the function actually exists
            if module:
                # Try direct name first
                if func_name in module.globals:
                    return func_name
                
                # Try current namespace mangled name
                if current_namespace:
                    mangled = TypeResolver.mangle_name(current_namespace, func_name)
                    if mangled in module.globals:
                        return mangled
                
                # Try using namespaces
                if hasattr(module, '_using_namespaces'):
                    for ns in module._using_namespaces:
                        mangled = TypeResolver.mangle_name(ns, func_name)
                        if mangled in module.globals:
                            return mangled
                # FALLBACK: Try ALL registered namespaces
                # This handles cases where _current_namespace is wrong or using_namespaces incomplete
                if hasattr(module, '_namespaces'):
                    for ns in module._namespaces:
                        mangled = TypeResolver.mangle_name(ns, func_name)
                        if mangled in module.globals:
                            return mangled
            else:
                # No module provided - fall back to old behavior
                if current_namespace:
                    mangled = TypeResolver.mangle_name(current_namespace, func_name)
                    return mangled
                return func_name
        
        return None


@dataclass
class NamespaceTypeHandler:
    """Handles type resolution and registration within namespace contexts."""
    
    def __init__(self, namespace_path: str = ""):
        self.namespace_path = namespace_path
        self.type_registry = {}  # Maps unmangled names to mangled names
        
    def register_type(self, unmangled_name: str, mangled_name: str):
        """Register a type alias with both its unmangled and mangled names."""
        self.type_registry[unmangled_name] = mangled_name
    
    def resolve_type_name(self, typename: str, current_namespace: str = "") -> str:
        """
        Resolve a type name to its fully qualified mangled name.
        Searches in order:
        1. Current namespace
        2. Parent namespaces
        3. Global namespace
        """
        # Try current namespace first
        if current_namespace:
            mangled = f"{current_namespace}__{typename}"
            if mangled in self.type_registry.values():
                return mangled
        
        # Try parent namespaces
        parts = current_namespace.split("::") if current_namespace else []
        while parts:
            parts.pop()
            parent_ns = "__".join(parts)
            mangled = f"{parent_ns}__{typename}" if parent_ns else typename
            if mangled in self.type_registry.values():
                return mangled
        
        # Try global/unmangled name
        if typename in self.type_registry.values():
            return typename
        
        # Return as-is if not found (will be caught later)
        return typename
    
    @staticmethod
    def register_namespace(module: 'ir.Module', namespace: str):
        """Register a namespace with the module."""
        if not hasattr(module, '_namespaces'):
            module._namespaces = []
        if namespace not in module._namespaces:
            module._namespaces.append(namespace)
    
    @staticmethod
    def add_using_namespace(module: 'ir.Module', namespace: str):
        """Add a namespace to the using namespaces list."""
        if not hasattr(module, '_using_namespaces'):
            module._using_namespaces = []
        if namespace not in module._using_namespaces:
            module._using_namespaces.append(namespace)
    
    @staticmethod
    def register_nested_namespaces(namespace: 'NamespaceDef', parent_path: str, module: 'ir.Module'):
        """
        Recursively register all nested namespaces.
        
        Args:
            namespace: The namespace definition containing nested namespaces
            parent_path: The full path of the parent namespace (e.g., "standard::io")
            module: LLVM module to register namespaces in
        """
        for nested_ns in namespace.nested_namespaces:
            full_nested_name = f"{parent_path}::{nested_ns.name}"
            # Use register_namespace which handles initialization and duplicate checking
            NamespaceTypeHandler.register_namespace(module, full_nested_name)
            # Recursively register deeper nested namespaces
            NamespaceTypeHandler.register_nested_namespaces(nested_ns, full_nested_name, module)
    
    @staticmethod
    def create_static_init_builder(module: 'ir.Module') -> 'ir.IRBuilder':
        """
        Create or get a builder for the __static_init function.
        
        This function is used to initialize static/global variables in namespaces.
        
        Args:
            module: LLVM module
            
        Returns:
            IRBuilder positioned in a non-terminated block of __static_init
        """
        init_func_name = "__static_init"

        # Create function if it doesn't exist
        if init_func_name not in module.globals:
            func_type = ir.FunctionType(ir.VoidType(), [])
            init_func = ir.Function(module, func_type, init_func_name)
            block = init_func.append_basic_block("entry")
        else:
            init_func = module.globals[init_func_name]

            # ALWAYS emit into a non-terminated block
            if not init_func.blocks:
                block = init_func.append_basic_block("entry")
            else:
                block = init_func.blocks[-1]
                if block.is_terminated:
                    block = init_func.append_basic_block("cont")

        builder = ir.IRBuilder(block)
        # Scope management now handled by module.symbol_table
        builder.initialized_unions = set()
        return builder
    
    @staticmethod
    def finalize_static_init(module: 'ir.Module'):
        """
        Finalize the __static_init function by adding a return if needed.
        
        Args:
            module: LLVM module
        """
        if "__static_init" in module.globals:
            init_func = module.globals["__static_init"]
            if init_func.blocks and not init_func.blocks[-1].is_terminated:
                # Get a builder positioned at the end of the last block
                final_builder = ir.IRBuilder(init_func.blocks[-1])
                final_builder.ret_void()
    
    @staticmethod
    def process_namespace_struct(namespace: str, struct_def: 'StructDef', builder: 'ir.IRBuilder', module: 'ir.Module'):
        """
        Process a struct within a namespace context.
        
        Args:
            namespace: The namespace path (e.g., "standard::io")
            struct_def: The struct definition to process
            builder: LLVM IR builder
            module: LLVM module
        """
        original_name = struct_def.name
        struct_def.name = f"{namespace.replace('::', '__')}__{struct_def.name}"
        
        # Set current namespace context on BOTH module and symbol_table
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
        """
        Process an object within a namespace context.
        
        Args:
            namespace: The namespace path (e.g., "standard::io")
            obj_def: The object definition to process
            builder: LLVM IR builder
            module: LLVM module
        """
        original_name = obj_def.name
        obj_def.name = f"{namespace.replace('::', '__')}__{obj_def.name}"
        
        # Set current namespace context on BOTH module and symbol_table
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
        """
        Process an enum within a namespace context.
        
        Args:
            namespace: The namespace path (e.g., "standard::io")
            enum_def: The enum definition to process
            builder: LLVM IR builder
            module: LLVM module
        """
        original_name = enum_def.name
        enum_def.name = f"{namespace.replace('::', '__')}__{enum_def.name}"
        
        # Set current namespace context on BOTH module and symbol_table
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
        """
        Process a variable (including type declarations) within a namespace context.
        
        Args:
            namespace: The namespace path (e.g., "standard::io")
            var_def: The variable declaration to process
            module: LLVM module
        """
        original_name = var_def.name
        # Always mangle namespace-level variables
        var_def.name = f"{namespace.replace('::', '__')}__{var_def.name}"
        
        # Set current namespace context on BOTH module and symbol_table
        original_namespace = getattr(module, '_current_namespace', '')
        original_st_namespace = module.symbol_table.current_namespace if hasattr(module, 'symbol_table') else ''
        
        module._current_namespace = namespace
        if hasattr(module, 'symbol_table'):
            module.symbol_table.set_namespace(namespace)
        
        try:
            result = var_def.codegen(None, module)  # Always use None builder for globals
            return result
        finally:
            # Restore original context
            var_def.name = original_name
            module._current_namespace = original_namespace
            if hasattr(module, 'symbol_table'):
                module.symbol_table.set_namespace(original_st_namespace)
    
    @staticmethod
    def process_nested_namespace(parent_namespace: str, nested_ns: 'NamespaceDef', builder: 'ir.IRBuilder', module: 'ir.Module'):
        """
        Process a nested namespace within a parent namespace.
        
        Args:
            parent_namespace: The parent namespace path (e.g., "standard")
            nested_ns: The nested namespace definition
            builder: LLVM IR builder
            module: LLVM module
        """
        original_name = nested_ns.name
        # Nested namespace gets parent path prepended
        full_nested_name = f"{parent_namespace}::{nested_ns.name}"
        nested_ns.name = f"{parent_namespace.replace('::', '__')}__{nested_ns.name}"
        
        # Set current namespace context on BOTH module and symbol_table
        original_namespace = getattr(module, '_current_namespace', '')
        original_st_namespace = module.symbol_table.current_namespace if hasattr(module, 'symbol_table') else ''
        
        module._current_namespace = full_nested_name
        if not hasattr(module, 'symbol_table'):
            raise RuntimeError("Module must have symbol_table for namespace support")

        original_namespace = module.symbol_table.current_namespace
        module.symbol_table.set_namespace(parent_namespace)

        # nested_ns is NamespaceDef
        try:
            nested_ns.codegen(builder, module)
        finally:
            nested_ns.name = original_name
            module.symbol_table.set_namespace(original_namespace)
    
    @staticmethod
    def process_namespace_function(namespace: str, func_def: 'FunctionDef', builder: 'ir.IRBuilder', module: 'ir.Module'):
        """Process a function within a namespace context."""
        from fast import FunctionTypeHandler  # Import here to avoid circular dependency
        
        original_name = func_def.name
        # Mangle the name for LLVM IR (so functions don't collide)
        mangled_func_name = f"{namespace}__{func_def.name}"
        
        # Temporarily set the function name for LLVM
        func_def.name = mangled_func_name
        
        # Set current namespace context on BOTH module and symbol_table  
        # This will be used by FunctionDef.codegen to register in symbol table
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
        """
        Resolve a custom type name (struct, enum, type alias) to its LLVM type.
        
        UPDATED: Now uses symbol_table as PRIMARY source
        
        Args:
            module: LLVM module
            typename: Type name to resolve (unmangled)
            current_namespace: Current namespace context
            
        Returns:
            LLVM type or None
        """
        # 1. SYMBOL TABLE - HIGHEST PRIORITY
        if hasattr(module, 'symbol_table'):
            #print("IN RESOLVE_CUSTOM_TYPE")
            result = module.symbol_table.lookup(typename)
            
            if result and result[0] == SymbolKind.TYPE:
                # If we have a TypeSystem stored, use it
                if result[1] is not None:
                    return result[1].get_llvm_type(module)
        
        # 2. Use TypeResolver for comprehensive namespace resolution
        return TypeResolver.resolve_type(module, typename, current_namespace)

    @staticmethod
    def is_type_defined(typename: str, module) -> bool:
        """
        Check if a type is defined, prioritizing symbol_table.
        
        Args:
            typename: Type name to check
            module: LLVM module
            
        Returns:
            True if type is defined, False otherwise
        """
        # 1. Check symbol table first
        #print("IN IS_TYPE_DEFINED")
        if hasattr(module, 'symbol_table'):
            result = module.symbol_table.lookup(typename)
            if result and result[0] == SymbolKind.TYPE:
                return True
        #print("FALLING BACK IN IS_TYPE_DEFINED")
        
        # 2. Check module storage (fallback)
        if hasattr(module, '_type_aliases') and typename in module._type_aliases:
            return True
        if hasattr(module, '_struct_types') and typename in module._struct_types:
            return True
        if hasattr(module, '_union_types') and typename in module._union_types:
            return True
        if hasattr(module, '_enum_types') and typename in module._enum_types:
            return True
        
        return False


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
    array_size: Optional[Union[int, Any]] = None  # Can be int literal or Expression (evaluated at runtime if needed)
    array_dimensions: Optional[List[Optional[Union[int, Any]]]] = None  # Same for multi-dimensional arrays
    array_element_type: Optional['TypeSystem'] = None  # For tracking element type signedness in arrays
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
        #print("IN GET_LLVM_TYPE()")
        if self.custom_typename:
            # Get the current namespace context
            current_namespace = getattr(module, '_current_namespace', '')
            
            # Use NamespaceTypeHandler to resolve the custom type
            resolved_type = NamespaceTypeHandler.resolve_custom_type(
                module, self.custom_typename, current_namespace
            )
            
            if resolved_type is not None:
                # Handle array types that shouldn't be returned as-is
                if isinstance(resolved_type, ir.ArrayType) and not self.is_array:
                    return ir.PointerType(resolved_type.element)
                # Handle enum types
                if isinstance(resolved_type, int):  # Enum types are stored as int
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
        
        # CRITICAL FIX: Handle arrays of pointers (like noopstr[3] -> [3 x i8*])
        # We need to create the element type FIRST (including pointer indirection),
        # THEN wrap it in an array type
        
        # Step 1: Create the element type (including pointer depth)
        element_type = base_type
        if self.is_pointer:
            if self.base_type == DataType.VOID or self.base_type == DataType.STRUCT:
                element_type = ir.PointerType(ir.IntType(8))
            else:
                # Apply pointer depth to get element type
                # For noopstr (byte*), pointer_depth=1, so element_type = i8*
                # For noopstr* (byte**), pointer_depth=2, so element_type = i8**
                for _ in range(self.pointer_depth if hasattr(self, 'pointer_depth') and self.pointer_depth else 1):
                    element_type = ir.PointerType(element_type)
        
        # Step 2: If this is an array, wrap element_type in ArrayType
        if self.is_array and self.array_dimensions:
            current_type = element_type
            for dim in reversed(self.array_dimensions):
                if dim is not None:
                    # Only handle compile-time constant dimensions
                    if isinstance(dim, int):
                        current_type = ir.ArrayType(current_type, dim)
                    else:
                        # Runtime size - return pointer to element type
                        # The actual allocation will be handled in _codegen_local
                        return ir.PointerType(element_type)
                else:
                    current_type = ir.PointerType(current_type)
            return current_type
        elif self.is_array:
            if self.array_size is not None:
                # Check if it's a compile-time constant
                if isinstance(self.array_size, int):
                    # Return array of element_type
                    # For noopstr[3], this returns [3 x i8*]
                    return ir.ArrayType(element_type, self.array_size)
                else:
                    # Runtime size - return pointer to element type
                    # The actual allocation will be handled in _codegen_local
                    return ir.PointerType(element_type)
            else:
                if isinstance(element_type, ir.PointerType):
                    return element_type
                else:
                    return ir.PointerType(element_type)
        
        # Step 3: If not an array, just return element_type (which may be a pointer)
        return element_type


class FunctionPointerType:
    return_type: TypeSystem
    parameter_types: List[TypeSystem]
    
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
    def resolve_type_spec(type_spec: TypeSystem, initial_value, module: ir.Module) -> TypeSystem:
        """Resolve type spec with automatic array size inference for string literals."""
        # Import here to avoid circular dependency
        from fast import StringLiteral
        
        if not (initial_value and isinstance(initial_value, StringLiteral)):
            return type_spec
        
        # Direct array type check
        if type_spec.is_array and type_spec.array_size is None:
            return TypeSystem(
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
                    return TypeSystem(
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
            return VariableTypeHandler.identifier_to_constant(initial_value, module)
        
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
    
    def identifier_to_constant_namespace_lookup(var_name: str, module: ir.Module) -> Optional[ir.Constant]:
        """
        Look up identifier in using namespaces for constant resolution.
        """
        #print("IN IDENTIFIER_TO_CONSTANT_NAMESPACE_LOOKUP()")
        current_ns = TypeResolver.get_current_namespace(module)
        mangled_name = TypeResolver.resolve_identifier(module, var_name, current_ns)
        
        if mangled_name and mangled_name in module.globals:
            other_global = module.globals[mangled_name]
            if hasattr(other_global, 'initializer') and other_global.initializer:
                return other_global.initializer
        
        return None
    
    @staticmethod
    def identifier_to_constant(identifier, module: ir.Module) -> Optional[ir.Constant]:
        """
        Convert an identifier to a compile-time constant for global initialization.
        
        UPDATED: Now uses symbol_table for identifier resolution
        
        Args:
            identifier: Identifier AST node
            module: LLVM module
            
        Returns:
            LLVM constant or None
        """
        
        # 1. Check symbol table first
        if hasattr(module, 'symbol_table'):
            #print("IN IDENTIFIER_TO_CONSTANT()")
            result = module.symbol_table.lookup(identifier.name)
            if result:
                kind, type_spec = result
                
                # If it's a variable, try to find it in globals
                if kind == SymbolKind.VARIABLE:
                    # Try direct name
                    if identifier.name in module.globals:
                        global_var = module.globals[identifier.name]
                        if hasattr(global_var, 'initializer'):
                            return global_var.initializer
                    
                    # Try with namespace mangling
                    current_ns = TypeResolver.get_current_namespace(module)
                    mangled = TypeResolver.resolve_identifier(module, identifier.name, current_ns)
                    if mangled and mangled in module.globals:
                        global_var = module.globals[mangled]
                        if hasattr(global_var, 'initializer'):
                            return global_var.initializer
        
        # 2. Fallback to namespace resolution (for backwards compatibility)
        current_ns = TypeResolver.get_current_namespace(module)
        mangled_name = TypeResolver.resolve_identifier(module, identifier.name, current_ns)
        
        if mangled_name and mangled_name in module.globals:
            global_var = module.globals[mangled_name]
            if hasattr(global_var, 'initializer'):
                return global_var.initializer
        
        # 3. Direct lookup (last resort)
        if identifier.name in module.globals:
            global_var = module.globals[identifier.name]
            if hasattr(global_var, 'initializer'):
                return global_var.initializer
        
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
            return VariableTypeHandler.identifier_to_constant(expr, module)
        
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
    def preserve_array_element_type_metadata(loaded_val: ir.Value, array_val: ir.Value, module: ir.Module) -> ir.Value:
        element_type_spec = get_array_element_type_spec(array_val)
        #print(f"[PRESERVE] element_type_spec={element_type_spec}", file=sys.stderr)
        #if element_type_spec:
            #print(f"[PRESERVE]   base_type={element_type_spec.base_type}", file=sys.stderr)
            #print(f"[PRESERVE]   is_signed={element_type_spec.is_signed}", file=sys.stderr)
            #print(f"[PRESERVE]   custom_typename={element_type_spec.custom_typename}", file=sys.stderr)
        
        if element_type_spec:
            return attach_type_metadata(loaded_val, type_spec=element_type_spec)
        
        return attach_type_metadata_from_llvm_type(loaded_val, loaded_val.type, module)
    
    @staticmethod
    def _zero() -> ir.Constant:
        """Return i32 zero constant."""
        return ir.Constant(ir.IntType(32), 0)
    
    @staticmethod
    def _index(value: int) -> ir.Constant:
        """Return i32 constant for given index."""
        return ir.Constant(ir.IntType(32), value)
    
    @staticmethod
    def _get_array_element_ptr(builder: ir.IRBuilder, array_val: ir.Value, index: ir.Value, name: str = "elem") -> ir.Value:
        """
        Get pointer to an element in an array, handling all array types.
        Works with: GlobalVariable arrays, local arrays (pointer to array), and raw pointers.
        """
        zero = ArrayTypeHandler._zero()
        
        if isinstance(array_val, ir.GlobalVariable) or \
           (isinstance(array_val.type, ir.PointerType) and isinstance(array_val.type.pointee, ir.ArrayType)):
            # Global or local array: need [zero, index]
            return builder.gep(array_val, [zero, index], inbounds=True, name=name)
        elif isinstance(array_val.type, ir.PointerType):
            # Raw pointer (like char*): just [index]
            return builder.gep(array_val, [index], inbounds=True, name=name)
        else:
            raise ValueError(f"Cannot get element pointer for type: {array_val.type}")
    
    @staticmethod
    def _get_array_start_ptr(builder: ir.IRBuilder, array_ptr: ir.Value, name: str = "start") -> ir.Value:
        """Get pointer to first element of array."""
        zero = ArrayTypeHandler._zero()
        return builder.gep(array_ptr, [zero, zero], name=name)
    
    @staticmethod
    def _load_if_pointer(builder: ir.IRBuilder, val: ir.Value) -> ir.Value:
        """Load value if it's a pointer, otherwise return as-is."""
        if isinstance(val.type, ir.PointerType):
            return builder.load(val)
        return val
    
    @staticmethod
    def _cast_int_to_width(builder: ir.IRBuilder, val: ir.Value, target_type: ir.IntType) -> ir.Value:
        """Extend or truncate integer to target width."""
        if not isinstance(val.type, ir.IntType) or not isinstance(target_type, ir.IntType):
            raise ValueError(f"Cannot cast non-integer types: {val.type} to {target_type}")
        
        if val.type.width < target_type.width:
            return builder.zext(val, target_type)
        elif val.type.width > target_type.width:
            return builder.trunc(val, target_type)
        return val
    
    @staticmethod
    def _store_byte_at_index(builder: ir.IRBuilder, array_ptr: ir.Value, index: int, byte_value: int) -> None:
        """Store a single byte at the given index in a byte array."""
        zero = ArrayTypeHandler._zero()
        idx = ArrayTypeHandler._index(index)
        elem_ptr = builder.gep(array_ptr, [zero, idx])
        builder.store(ir.Constant(ir.IntType(8), byte_value), elem_ptr)
    
    @staticmethod
    def _store_bytes_to_array(builder: ir.IRBuilder, array_ptr: ir.Value, bytes_data: bytes, start_index: int = 0) -> None:
        """Store a sequence of bytes into an array at the given starting index."""
        zero = ir.Constant(ir.IntType(32), 0)
        for i, byte_val in enumerate(bytes_data):
            index = ir.Constant(ir.IntType(32), start_index + i)
            elem_ptr = builder.gep(array_ptr, [zero, index])
            char_val = ir.Constant(ir.IntType(8), byte_val)
            builder.store(char_val, elem_ptr)
    
    @staticmethod
    def _pack_value_into_integer(builder: ir.IRBuilder, result: ir.Value, elem_val: ir.Value, target_type: ir.IntType, bit_offset: int) -> Tuple[ir.Value, int]:
        """
        Pack a single integer value into a larger integer at the specified bit offset.
        Returns (new_result, new_bit_offset).
        """
        elem_width = elem_val.type.width
        
        # Extend to target width if needed
        elem_val = ArrayTypeHandler._cast_int_to_width(builder, elem_val, target_type)
        
        # Shift into position if needed
        if bit_offset > 0:
            elem_val = builder.shl(elem_val, ir.Constant(target_type, bit_offset))
        
        # OR into result
        result = builder.or_(result, elem_val)
        return result, bit_offset + elem_width

    @staticmethod
    def emit_memcpy(builder: ir.IRBuilder, module: ir.Module, dst_ptr: ir.Value, src_ptr: ir.Value, bytes: int) -> None:
        """Emit llvm.memcpy intrinsic call."""
        # Declare llvm.memcpy.p0i8.p0i8.i64 if not already declared
        memcpy_name = "llvm.memcpy.p0i8.p0i8.i64"
        if memcpy_name not in module.globals:
            memcpy_type = ir.FunctionType(ir.VoidType(), [ir.PointerType(ir.IntType(8)), ir.PointerType(ir.IntType(8)), ir.IntType(64), ir.IntType(1)])
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
        builder.call(memcpy_func, [dst_ptr, src_ptr, ir.Constant(ir.IntType(64), bytes), ir.Constant(ir.IntType(1), 0)])
    
    @staticmethod
    def emit_memset(builder: ir.IRBuilder, module: ir.Module, dst_ptr: ir.Value, value: int, bytes: int) -> None:
        """Emit llvm.memset intrinsic call."""
        memset_name = "llvm.memset.p0i8.i64"
        if memset_name not in module.globals:
            memset_type = ir.FunctionType(
                ir.VoidType(),
                [ir.PointerType(ir.IntType(8)), ir.IntType(8), ir.IntType(64), ir.IntType(1)])
            memset_func = ir.Function(module, memset_type, name=memset_name)
            memset_func.attributes.add('nounwind')
        else:
            memset_func = module.globals[memset_name]
        
        # Cast pointer to i8* if needed
        i8_ptr = ir.PointerType(ir.IntType(8))
        if dst_ptr.type != i8_ptr:
            dst_ptr = builder.bitcast(dst_ptr, i8_ptr)
        
        # Call memset
        builder.call(memset_func, [dst_ptr, ir.Constant(ir.IntType(8), value), ir.Constant(ir.IntType(64), bytes), ir.Constant(ir.IntType(1), 0)])
    
    @staticmethod
    def concatenate(builder: ir.IRBuilder, module: ir.Module, left_val: ir.Value, right_val: ir.Value, operator) -> ir.Value:
        """Handle array concatenation (+ and -) operations."""
        
        # Get array information
        left_elem_type, left_len = ArrayTypeHandler.get_array_info(left_val)
        right_elem_type, right_len = ArrayTypeHandler.get_array_info(right_val)
        
        # Type compatibility check
        if left_elem_type != right_elem_type:
            raise ValueError(f"Cannot {operator.value} arrays with different element types: {left_elem_type} vs {right_elem_type}")
        
        result_len = left_len + right_len if operator == Operator.ADD else max(left_len - right_len, 0)
        result_array_type = ir.ArrayType(left_elem_type, result_len)
        
        # Check for compile-time concatenation
        if (isinstance(left_val, ir.GlobalVariable) and isinstance(right_val, ir.GlobalVariable) and 
            getattr(left_val, 'global_constant', False) and getattr(right_val, 'global_constant', False)):
            return ArrayTypeHandler.create_global_array_concat(module, left_val, right_val, result_array_type, operator)
        else:
            return ArrayTypeHandler.create_runtime_array_concat(builder, module, left_val, right_val, result_array_type, operator)
    
    @staticmethod
    def create_global_array_concat(module: ir.Module, left_val: ir.Value, right_val: ir.Value, result_array_type: ir.ArrayType, operator) -> ir.Value:
        """Create compile-time global array concatenation."""
        from fast import Operator
        
        # Get array initializers
        left_init = left_val.initializer
        right_init = right_val.initializer
        
        # Create concatenated constant
        if operator == Operator.ADD:
            result_elements = list(left_init.constant) + list(right_init.constant)
        else:  # SUB
            result_elements = list(left_init.constant[:result_array_type.count])
        
        result_constant = ir.Constant(result_array_type, result_elements)
        
        # Create new global variable
        global_var = ir.GlobalVariable(module, result_array_type, name=module.get_unique_name("array_concat"))
        global_var.initializer = result_constant
        global_var.global_constant = True
        global_var.linkage = 'internal'
        
        return global_var
    
    @staticmethod
    def create_runtime_array_concat(builder: ir.IRBuilder, module: ir.Module, left_val: ir.Value, right_val: ir.Value, result_array_type: ir.ArrayType, operator) -> ir.Value:
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
            result_start = ArrayTypeHandler._get_array_start_ptr(builder, result_ptr, "result_start")
            left_start = ArrayTypeHandler._get_array_start_ptr(builder, left_val, "left_start")
            ArrayTypeHandler.emit_memcpy(builder, module, result_start, left_start, left_len * elem_size_bytes)
        if operator == Operator.ADD and right_len > 0:
            zero = ArrayTypeHandler._zero()
            left_len_const = ArrayTypeHandler._index(left_len)
            result_right_start = builder.gep(result_ptr, [zero, left_len_const], name="result_right_start")
            right_start = ArrayTypeHandler._get_array_start_ptr(builder, right_val, "right_start")
            ArrayTypeHandler.emit_memcpy(builder, module, result_right_start, right_start, right_len * elem_size_bytes)
        
        # Mark as array pointer
        result_ptr.type._is_array_pointer = True
        
        return result_ptr
    
    @staticmethod
    def resize_for_assignment(builder: ir.IRBuilder, module: ir.Module, ptr: ir.Value, val: ir.Value, var_name: str = None) -> ir.Value:
        """Dynamically resize arrays to accommodate new values during assignment."""
        # Get array information
        val_elem_type, val_len = ArrayTypeHandler.get_array_info(val)
        ptr_elem_type, ptr_len = ArrayTypeHandler.get_array_info(ptr)
        
        # If the new array is larger, we need to reallocate
        if val_len > ptr_len:
            # Need to reallocate
            new_array_type = ir.ArrayType(val_elem_type, val_len)
            
            # Allocate new storage for the resized array
            new_alloca = builder.alloca(new_array_type, name=f"{var_name}_resized" if var_name else "array_resized")
            
            # Copy old data
            if ptr_len > 0:
                elem_size_bytes = ptr_elem_type.width // 8
                old_start = ArrayTypeHandler._get_array_start_ptr(builder, ptr, "old_start")
                new_start = ArrayTypeHandler._get_array_start_ptr(builder, new_alloca, "new_start")
                ArrayTypeHandler.emit_memcpy(builder, module, new_start, old_start, ptr_len * elem_size_bytes)
            
            # Copy new data (overwrites all elements)
            new_bytes = val_len * (val_elem_type.width // 8)
            new_start = ArrayTypeHandler._get_array_start_ptr(builder, new_alloca, "new_start")
            val_start = ArrayTypeHandler._get_array_start_ptr(builder, val, "val_start")
            ArrayTypeHandler.emit_memcpy(builder, module, new_start, val_start, new_bytes)
            
            # Update scope
            if var_name and module.symbol_table.get_llvm_value(var_name) is not None:
                module.symbol_table.update_llvm_value(var_name, new_alloca)
            
            return new_alloca
        else:
            # Just copy the data
            copy_bytes = min(val_len, ptr_len) * (val_elem_type.width // 8)
            ptr_start = ArrayTypeHandler._get_array_start_ptr(builder, ptr, "ptr_start")
            val_start = ArrayTypeHandler._get_array_start_ptr(builder, val, "val_start")
            
            # Copy the data
            ArrayTypeHandler.emit_memcpy(builder, module, ptr_start, val_start, copy_bytes)
            
            # Zero out remaining if smaller
            if val_len < ptr_len:
                remaining_bytes = (ptr_len - val_len) * (ptr_elem_type.width // 8)
                if remaining_bytes > 0:
                    zero = ArrayTypeHandler._zero()
                    val_len_const = ArrayTypeHandler._index(val_len)
                    remaining_start = builder.gep(ptr, [zero, val_len_const], name="remaining_start")
                    ArrayTypeHandler.emit_memset(builder, module, remaining_start, 0, remaining_bytes)
            
            return ptr
    
    @staticmethod
    def slice_array(builder: ir.IRBuilder, module: ir.Module, array_val: ir.Value, start_val: ir.Value, end_val: ir.Value,is_reverse: bool = False) -> ir.Value:
        """Extract array slice with optional reverse."""
        # Calculate slice length
        if is_reverse:
            # Reverse range: length = (start - end) + 1
            slice_len_exclusive = builder.sub(start_val, end_val, name="slice_len_exclusive")
        else:
            # Forward range: length = (end - start) + 1
            slice_len_exclusive = builder.sub(end_val, start_val, name="slice_len_exclusive")
        slice_len = builder.add(slice_len_exclusive, ArrayTypeHandler._index(1), name="slice_len")
        
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
        slice_start_ptr = ArrayTypeHandler._get_array_start_ptr(builder, slice_ptr, "slice_start")
        
        # Create slice loop
        func = builder.block.function
        loop_cond = func.append_basic_block('slice_loop_cond')
        loop_body = func.append_basic_block('slice_loop_body')
        loop_end = func.append_basic_block('slice_loop_end')
        
        # Create loop counter
        counter_ptr = builder.alloca(ir.IntType(32), name="slice_counter")
        builder.store(ArrayTypeHandler._index(0), counter_ptr)
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
        
        # Get source element using helper (handles all array types)
        source_elem_ptr = ArrayTypeHandler._get_array_element_ptr(builder, array_val, source_offset, "source_elem")
        
        source_elem = builder.load(source_elem_ptr, name="source_val")
        
        # Store in slice array at sequential destination index (always forward)
        dest_elem_ptr = builder.gep(slice_start_ptr, [counter], inbounds=True, name="dest_elem")
        builder.store(source_elem, dest_elem_ptr)
        
        # Increment counter
        next_counter = builder.add(counter, ArrayTypeHandler._index(1), name="next_counter")
        builder.store(next_counter, counter_ptr)
        builder.branch(loop_cond)
        
        # Loop end - null terminate strings
        # Only way for this to work is to null terminate so this is an exception to the no null terminate rule.
        builder.position_at_start(loop_end)
        if element_type == ir.IntType(8):
            final_counter = builder.load(counter_ptr, name="final_counter")
            null_ptr = builder.gep(slice_start_ptr, [final_counter], inbounds=True, name="null_pos")
            builder.store(ir.Constant(ir.IntType(8), 0), null_ptr)
        
        return slice_ptr
    
    @staticmethod
    def create_global_string_initializer(string_value: str, llvm_type: ir.Type) -> Optional[ir.Constant]:
        """Create a compile-time constant initializer for a global string."""
        if isinstance(llvm_type, ir.ArrayType) and isinstance(llvm_type.element, ir.IntType) and llvm_type.element.width == 8:
            
            string_val = string_value
            char_values = []
            for i, char in enumerate(string_value):
                if i >= llvm_type.count:
                    break
                char_values.append(ir.Constant(ir.IntType(8), ord(char)))
            while len(char_values) < llvm_type.count:
                char_values.append(ir.Constant(ir.IntType(8), 0))
            return ir.Constant(llvm_type, char_values)
        
        return None

    @staticmethod
    def create_global_array_initializer(array_literal, llvm_type: ir.Type, module: ir.Module) -> Optional[ir.Constant]:
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
                                    actual_type = global_var.type.pointee if isinstance(global_var.type, ir.PointerType) else global_var.type
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
                    raise ValueError(f"Array packing size mismatch: packed {bit_offset} bits into {llvm_type.element.width}-bit integer")
                
                const_elements.append(ir.Constant(llvm_type.element, packed_value))
            
            # Direct constant elements
            elif isinstance(elem, Literal):
                llvm_val = elem.codegen(None, module)
                
                # Convert to target element type if needed
                if llvm_val.type != llvm_type.element:
                    # Both must be integer types for conversion
                    if isinstance(llvm_val.type, ir.IntType) and isinstance(llvm_type.element, ir.IntType):
                        # Get the literal value
                        if isinstance(llvm_val, ir.Constant):
                            # Truncate or extend to target width
                            target_width = llvm_type.element.width
                            source_width = llvm_val.type.width
                            
                            if source_width > target_width:
                                # Truncate - mask to target width
                                mask = (1 << target_width) - 1
                                truncated_val = llvm_val.constant & mask
                                llvm_val = ir.Constant(llvm_type.element, truncated_val)
                            elif source_width < target_width:
                                # Extend - just use the value directly
                                llvm_val = ir.Constant(llvm_type.element, llvm_val.constant)
                            # If widths are equal but types differ, recreate constant
                            else:
                                llvm_val = ir.Constant(llvm_type.element, llvm_val.constant)
                        else:
                            raise ValueError(f"Cannot convert non-constant literal to array element type")
                    else:
                        raise ValueError(f"Array element type mismatch: expected {llvm_type.element}, got {llvm_val.type}")
                
                const_elements.append(llvm_val)
            
            else:
                raise ValueError(f"Cannot create global initializer for element type: {type(elem)}")
        
        # Pad with zeros if needed
        while len(const_elements) < llvm_type.count:
            const_elements.append(ir.Constant(llvm_type.element, 0))
        
        return ir.Constant(llvm_type, const_elements)

    @staticmethod
    def initialize_local_array(builder: ir.IRBuilder, module: ir.Module, alloca: ir.Value, llvm_type: ir.Type, array_literal) -> None:
        """Initialize a local array variable with an array literal."""
        print("[TYPESYS] In initialize_local_array()")
        from fast import StringLiteral
        
        zero = ArrayTypeHandler._zero()
        
        for i, elem in enumerate(array_literal.elements):
            if i >= llvm_type.count:
                break
            
            # Pack StringLiteral into integer if the target is integer type
            if isinstance(elem, StringLiteral) and isinstance(llvm_type.element, ir.IntType):
                packed_value = 0
                for j in range(min(len(elem.value), llvm_type.element.width // 8)):
                    packed_value |= (ord(elem.value[j]) << (j * 8))
                
                elem_ptr = builder.gep(alloca, [zero, ArrayTypeHandler._index(i)], name=f"elem_{i}")
                builder.store(ir.Constant(llvm_type.element, packed_value), elem_ptr)
            else:
                from fast import ArrayLiteral
                
                # Handle nested array packing: if element is an ArrayLiteral and target is integer, pack it
                if isinstance(elem, ArrayLiteral) and isinstance(llvm_type.element, ir.IntType):
                    # Pack the nested array literal into an integer
                    elem_val = ArrayTypeHandler.pack_array_to_integer(
                        builder, module, elem, llvm_type.element)
                else:
                    elem_val = elem.codegen(builder, module)
                    
                    # CRITICAL FIX: If target element is a pointer and elem_val is pointer-to-array,
                    # convert to pointer-to-element (for string literals in pointer arrays)
                    if isinstance(llvm_type.element, ir.PointerType) and isinstance(elem_val.type, ir.PointerType):
                        # Check if this is a pointer to array (like [8 x i8]*)
                        if isinstance(elem_val.type.pointee, ir.ArrayType):
                            # Convert [N x i8]* to i8* by GEP to first element
                            zero_idx = ir.Constant(ir.IntType(32), 0)
                            elem_val = builder.gep(elem_val, [zero_idx, zero_idx], name="str_to_ptr")
                    else:
                        # For non-pointer targets, load if needed
                        elem_val = ArrayTypeHandler._load_if_pointer(builder, elem_val)
                
                if elem_val.type != llvm_type.element:
                    if isinstance(elem_val.type, ir.IntType) and isinstance(llvm_type.element, ir.IntType):
                        elem_val = ArrayTypeHandler._cast_int_to_width(builder, elem_val, llvm_type.element)
                    else:
                        raise ValueError(f"Array element type mismatch: expected {llvm_type.element}, got {elem_val.type}")
                
                index = ir.Constant(ir.IntType(32), i)
                elem_ptr = builder.gep(alloca, [zero, ArrayTypeHandler._index(i)], name=f"elem_{i}")
                builder.store(elem_val, elem_ptr)

    @staticmethod
    def pack_array_to_integer(builder: ir.IRBuilder, module: ir.Module, 
                             array_lit, target_type: ir.IntType) -> ir.Value:
        """Pack array literal elements into a single integer (compile-time if possible)."""
        print("[TYPESYS] In pack_array_to_integer()")
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
                return ArrayTypeHandler.pack_array_to_integer_runtime(builder, module, array_lit, target_type)
            
            # Pack constant value
            packed_value |= (elem_val.constant << bit_offset)
            bit_offset += elem_width
        
        # Verify total width matches target
        if bit_offset != target_type.width:
            raise ValueError(f"Array packing size mismatch: packed {bit_offset} bits into {target_type.width}-bit integer")
        
        return ir.Constant(target_type, packed_value)

    @staticmethod
    def pack_array_to_integer_runtime(builder: ir.IRBuilder, module: ir.Module, array_lit,  target_type: ir.IntType) -> ir.Value:
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
            
            # Use helper to pack value
            result, bit_offset = ArrayTypeHandler._pack_value_into_integer(builder, result, elem_val, target_type, bit_offset)
        
        return result

    @staticmethod
    def pack_array_pointer_to_integer(builder: ir.IRBuilder, module: ir.Module, array_ptr: ir.Value, target_type: ir.IntType) -> ir.Value:
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
            raise ValueError(f"Array packing size mismatch: {array_type.count} x {elem_type.width} = {total_bits} bits into {target_type.width}-bit integer")
        
        # Pack at runtime (big-endian: first element at high bits, last at low bits)
        result = ir.Constant(target_type, 0)
        bit_offset = 0
        
        zero = ArrayTypeHandler._zero()
        # Iterate in reverse: last element goes to low bits
        for i in range(array_type.count - 1, -1, -1):
            elem_ptr = builder.gep(array_ptr, [zero, ArrayTypeHandler._index(i)], inbounds=True)
            elem_val = builder.load(elem_ptr)
            
            result, bit_offset = ArrayTypeHandler._pack_value_into_integer(builder, result, elem_val, target_type, bit_offset)
        
        return result

    @staticmethod
    def initialize_local_string(builder: ir.IRBuilder, module: ir.Module, alloca: ir.Value, llvm_type: ir.Type, string_literal) -> None:
        """Initialize a local variable with a string literal."""
        string_val = string_literal.value
        
        # Case 1: Pointer to i8 (char*)
        if isinstance(llvm_type, ir.PointerType) and isinstance(llvm_type.pointee, ir.IntType) and llvm_type.pointee.width == 8:
            
            # Store string data on stack
            string_bytes = string_val.encode('ascii')
            str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
            str_alloca = builder.alloca(str_array_ty, name="str_data")
            
            # Use helper to store bytes
            ArrayTypeHandler._store_bytes_to_array(builder, str_alloca, string_bytes)
            
            str_ptr = ArrayTypeHandler._get_array_start_ptr(builder, str_alloca, "str_ptr")
            builder.store(str_ptr, alloca)
        
        # Case 2: Array of i8 (char[N])
        elif isinstance(llvm_type, ir.ArrayType) and isinstance(llvm_type.element, ir.IntType) and llvm_type.element.width == 8:
            
            # Store string characters
            string_bytes = string_val.encode('ascii')[:llvm_type.count]
            ArrayTypeHandler._store_bytes_to_array(builder, alloca, string_bytes)
            
            # Null-terminate remaining
            zero = ArrayTypeHandler._zero()
            for i in range(len(string_bytes), llvm_type.count):
                elem_ptr = builder.gep(alloca, [zero, ArrayTypeHandler._index(i)])

    @staticmethod
    def create_local_string_for_arg(builder: ir.IRBuilder, module: ir.Module, string_value: str, name_hint: str) -> ir.Value:
        """Create a local string on the stack for passing as an argument."""
        string_bytes = string_value.encode('ascii')
        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
        str_alloca = builder.alloca(str_array_ty, name=f"{name_hint}_str_data")
        
        # Use helper to store bytes
        ArrayTypeHandler._store_bytes_to_array(builder, str_alloca, string_bytes)
        
        return ArrayTypeHandler._get_array_start_ptr(builder, str_alloca, f"{name_hint}_str_ptr")

    @staticmethod
    def copy_array_to_local(builder: ir.IRBuilder, module: ir.Module, alloca: ir.Value, llvm_type: ir.Type, source_identifier) -> None:
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
        
        zero = ArrayTypeHandler._zero()
        for i in range(copy_count):
            idx = ArrayTypeHandler._index(i)
            src_ptr = builder.gep(init_val, [zero, idx], inbounds=True, name=f"src_{i}")
            src_val = builder.load(src_ptr, name=f"val_{i}")
            dst_ptr = builder.gep(alloca, [zero, idx], inbounds=True, name=f"dst_{i}")
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
        # Parse the value if it's a string (hex literals come as strings)
        val = int(literal_value, 0) if isinstance(literal_value, str) else int(literal_value)
        
        # For unsigned types with large values, convert to signed representation
        # LLVM IR constants are always signed, but we need to preserve the bit pattern
        if literal_type == DataType.UINT:
            # If value is larger than max signed value for this width, convert to negative
            max_signed = (1 << (width - 1)) - 1
            if val > max_signed:
                # Convert to two's complement signed representation
                val = val - (1 << width)
        
        return val
        
    @staticmethod
    def preserve_array_element_type_metadata(loaded_val: ir.Value, array_val: ir.Value, module: ir.Module) -> ir.Value:
        """
        Preserve type metadata when loading an element from an array.
        
        This extracts the element type spec from the array's metadata and attaches it
        to the loaded value, maintaining type information through array access operations.
        
        Args:
            loaded_val: The loaded element value
            array_val: The source array
            module: LLVM module for type resolution
            
        Returns:
            The loaded value with appropriate type metadata attached
        """
        # Try to get the element type spec from the array value's metadata
        element_type_spec = get_array_element_type_spec(array_val)
        
        if element_type_spec:
            return attach_type_metadata(loaded_val, type_spec=element_type_spec)
        
        return attach_type_metadata_from_llvm_type(loaded_val, loaded_val.type, module)
    
    @staticmethod
    def cast_to_target_int_type(builder: ir.IRBuilder, value: ir.Value, target_type: ir.Type) -> ir.Value:
        """
        Cast an integer value to a target integer type using appropriate trunc/sext.
        
        This handles type conversions needed when storing values into arrays with
        specific element types, or when converting between different integer widths.
        
        Args:
            builder: IR builder
            value: Source integer value
            target_type: Target integer type
            
        Returns:
            Value cast to target type (or original if no cast needed)
        """
        # Only handle integer-to-integer casts
        if not (isinstance(value.type, ir.IntType) and isinstance(target_type, ir.IntType)):
            return value
        
        # If same width, no cast needed
        if value.type.width == target_type.width:
            return value
        
        # Truncate if source is wider
        if value.type.width > target_type.width:
            return builder.trunc(value, target_type)
        
        # Sign-extend if source is narrower
        return builder.sext(value, target_type)
    
    @staticmethod
    def get_element_type_from_array_value(array_val: ir.Value) -> ir.Type:
        """
        Extract the element type from an array value.
        
        Handles global arrays, local arrays (pointer to array), and raw pointers.
        
        Args:
            array_val: Array value (GlobalVariable, pointer to array, or pointer)
            
        Returns:
            The LLVM element type
            
        Raises:
            ValueError: If unable to determine element type
        """
        if isinstance(array_val, ir.GlobalVariable) and isinstance(array_val.type.pointee, ir.ArrayType):
            return array_val.type.pointee.element
        elif isinstance(array_val.type, ir.PointerType) and isinstance(array_val.type.pointee, ir.ArrayType):
            return array_val.type.pointee.element
        elif isinstance(array_val.type, ir.PointerType):
            # Pointer-to-element (e.g. byte[] lowered as i8*)
            return array_val.type.pointee
        else:
            raise ValueError(f"Cannot determine element type for: {array_val.type}")
    
    @staticmethod
    def compute_element_size_bytes(elem_type: ir.Type) -> int:
        """
        Compute the size in bytes of an element type.
        
        Handles common LLVM types with sensible defaults.
        
        Args:
            elem_type: LLVM element type
            
        Returns:
            Size in bytes
        """
        if isinstance(elem_type, ir.IntType):
            return max(1, elem_type.width // 8)
        elif isinstance(elem_type, ir.FloatType):
            return 4
        elif isinstance(elem_type, ir.DoubleType):
            return 8
        else:
            # Struct/other: fallback to 1 byte
            return 1
    
    @staticmethod
    def resolve_comprehension_element_type(variable_type, module: ir.Module) -> ir.Type:
        """
        Resolve the element type for an array comprehension from the variable type.
        
        Args:
            variable_type: TypeSystem object for the loop variable, or None
            module: LLVM module for type resolution
            
        Returns:
            LLVM type for array elements (defaults to i32 if not specified)
        """
        if variable_type is not None:
            return variable_type.get_llvm_type(module)
        else:
            return ir.IntType(32)

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
        Get the TypeSystem for an identifier from scope or global type info.
        
        UPDATED: Now checks symbol_table FIRST before other sources
        
        Args:
            name: The identifier name
            builder: LLVM IR builder (for scope access)
            module: LLVM module (for global type info)
            
        Returns:
            TypeSystem if found, None otherwise
        """
        # 1. SYMBOL TABLE - HIGHEST PRIORITY (NEW: moved to top)
        if hasattr(module, 'symbol_table'):
            #print("IDENTIFIERTYPEHANDLER GET_TYPE_SPEC()")
            result = module.symbol_table.lookup(name)
            if result:
                kind, type_spec = result
                
                # For variables, return the TypeSystem directly
                if kind == SymbolKind.VARIABLE and type_spec is not None:
                    return type_spec
                
                # For types, the type_spec might be a TypeSystem or None
                if kind == SymbolKind.TYPE and type_spec is not None:
                    return type_spec
        
        # 2. Check local scope (for local variables not yet in symbol table)
        # Type info now stored in symbol_table
        entry = module.symbol_table.lookup_variable(name)
        if entry and entry.type_spec is not None:
            return entry.type_spec
        
        # 3. Check global type info (fallback)
        if hasattr(module, '_global_type_info') and name in module._global_type_info:
            return module._global_type_info[name]
        
        return None
    
    @staticmethod
    def should_return_pointer(llvm_value: ir.Value, type_spec=None) -> bool:
        """
        Determine if an identifier should return a pointer (not load).
        Arrays and structs return pointers; other types are loaded.
        
        Args:
            llvm_value: The LLVM value (typically from scope or globals)
            type_spec: The TypeSystem for this identifier (optional)
            
        Returns:
            True if should return pointer, False if should load
        """
        import sys
        print(f"[SHOULD_RETURN_PTR] llvm_value.type: {llvm_value.type}", file=sys.stderr)
        if type_spec:
            print(f"[SHOULD_RETURN_PTR] type_spec: {type_spec}", file=sys.stderr)
        
        # For arrays, return the pointer directly (don't load)
        if isinstance(llvm_value.type, ir.PointerType) and isinstance(llvm_value.type.pointee, ir.ArrayType):
            print(f"[SHOULD_RETURN_PTR] Returning True - is ArrayType", file=sys.stderr)
            return True
        
        # For structs, return the pointer directly (don't load)
        if isinstance(llvm_value.type, ir.PointerType) and isinstance(llvm_value.type.pointee, ir.LiteralStructType):
            print(f"[SHOULD_RETURN_PTR] Returning True - is StructType", file=sys.stderr)
            return True
        
        # CRITICAL: Check type_spec parameter for arrays of pointers (like noopstr[3])
        # These are stored as i8** in LLVM but should not be loaded
        if type_spec is not None:
            if hasattr(type_spec, 'array_size') and type_spec.array_size is not None:
                # This is an array variable - don't load it
                print(f"[SHOULD_RETURN_PTR] Returning True - has array_size: {type_spec.array_size}", file=sys.stderr)
                return True
        
        # Fallback: Check type metadata already attached
        if hasattr(llvm_value, '_flux_type_spec'):
            ts = llvm_value._flux_type_spec
            if hasattr(ts, 'array_size') and ts.array_size is not None:
                # This is an array variable - don't load it
                print(f"[SHOULD_RETURN_PTR] Returning True - has _flux_type_spec.array_size: {ts.array_size}", file=sys.stderr)
                return True
        
        print(f"[SHOULD_RETURN_PTR] Returning False - will load", file=sys.stderr)
        return False
    
    @staticmethod
    def attach_type_metadata(llvm_value: ir.Value, type_spec) -> ir.Value:
        """
        Attach TypeSystem metadata to an LLVM value if not already present.
        
        Args:
            llvm_value: The LLVM value to attach metadata to
            type_spec: The TypeSystem to attach (or None)
            
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
    
    def resolve_namespace_mangled_name(name: str, module: ir.Module) -> Optional[str]:
        """
        Resolve identifier using namespace 'using' statements.
        """
        current_ns = TypeResolver.get_current_namespace(module)
        return TypeResolver.resolve_identifier(module, name, current_ns)
    
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


class CoercionContext:
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
        return CoercionContext.is_unsigned(a) or CoercionContext.is_unsigned(b)

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
                result = instance.b.zext(v, ty) if unsigned else instance.b.sext(v, ty)
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
    
    Note:
        CHANGED: Now defaults to 32-bit for all values that fit in 32 bits.
        This ensures literals are generated as i32 instead of i64 by default.
    """
    if data_type not in (DataType.SINT, DataType.UINT):
        raise ValueError("Not an integer literal")
    
    # Default to 32-bit - only use 64-bit if value doesn't fit in 32-bit
    if data_type == DataType.SINT:
        # Signed: -2^31 to 2^31-1
        if -(1 << 31) <= value <= (1 << 31) - 1:
            return 32
        else:
            return 64
    else:  # DataType.UINT
        # Unsigned: 0 to 2^32-1
        if 0 <= value <= (1 << 32) - 1:
            #print(f"[DEBUG infer_int_width UINT] Returning 32 for value={value}")
            return 32
        else:
            #print(f"[DEBUG infer_int_width UINT] Returning 64 for value={value}")
            return 64


def attach_type_metadata(llvm_value: ir.Value, type_spec: Optional[Any] = None, 
                        base_type: Optional[DataType] = None) -> ir.Value:
    """
    Attach Flux type information to LLVM value for proper signedness tracking.
    
    Args:
        llvm_value: The LLVM value to annotate
        type_spec: Optional TypeSystem object
        base_type: Optional DataType for creating default TypeSystem
        
    Returns:
        The same llvm_value with metadata attached
    """
    bit_width = llvm_value.type.width if hasattr(llvm_value.type, 'width') else None
    
    if type_spec is None and base_type is not None:
        # Create a minimal TypeSystem-like structure
        type_spec = type(
            'TypeSystem',
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


def attach_type_metadata_from_llvm_type(llvm_value: ir.Value, llvm_type: ir.Type, module: ir.Module) -> ir.Value:
    """
    Attach Flux type metadata to a loaded value based on LLVM type and module type aliases.
    
    This is used when loading from arrays or struct members to preserve signedness information.
    
    Args:
        llvm_value: The LLVM value to annotate (typically just loaded)
        llvm_type: The LLVM type of the value
        module: LLVM module containing type alias information
        
    Returns:
        The same llvm_value with metadata attached if type information is found
    """
    # Check if this type has a known alias in the module
    if hasattr(module, '_type_aliases'):
        for alias_name, alias_type in module._type_aliases.items():
            # Compare types properly - use str() comparison or type equivalence
            types_match = (str(alias_type) == str(llvm_type)) or (alias_type == llvm_type)
            if types_match:
                # Found a matching type alias - determine if it's unsigned
                # u8, u16, u32, u64 are unsigned
                # i8, i16, i32, i64, s8, s16, s32, s64 are signed
                # byte is unsigned (u8)
                # Check _type_alias_specs for correct signedness
                is_unsigned_type = False
                if hasattr(module, '_type_alias_specs') and alias_name in module._type_alias_specs:
                    alias_spec = module._type_alias_specs[alias_name]
                    if hasattr(alias_spec, 'is_signed'):
                        is_unsigned_type = not alias_spec.is_signed
                    elif hasattr(alias_spec, 'base_type') and alias_spec.base_type == DataType.UINT:
                        is_unsigned_type = True
                else:
                    # Fallback to name-based heuristic
                    is_unsigned_type = alias_name.startswith('u') or alias_name == 'byte'
                
                # Create type spec with appropriate signedness
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
                #print("IN ATTACH_TYPE_METADATA_FROM_LLVM_TYPE() JUST BEFORE BASE_NAME ERROR, PRINTING TRACEBACK STACK")
                #traceback.print_stack()
                llvm_value._flux_type_spec = type_spec
                return llvm_value
    
    # No type alias found - return value as-is
    return llvm_value



def get_array_element_type_spec(array_val: ir.Value):
    """
    Get the element type specification from an array value's metadata.
    
    This is used when indexing into arrays to preserve element signedness.
    For example, if array_val is a pointer to u32[8], this returns the u32 TypeSystem spec.
    
    Args:
        array_val: The array value (pointer to array or global array)
        
    Returns:
        TypeSystem spec for array elements, or None if not found
    """
    # Check if the array value has type metadata attached
    if hasattr(array_val, '_flux_array_element_type_spec'):
        return array_val._flux_array_element_type_spec
    
    # Check if it has a general type spec with array element info
    if hasattr(array_val, '_flux_type_spec'):
        type_spec = array_val._flux_type_spec
        if hasattr(type_spec, 'array_element_type') and type_spec.array_element_type:
            return type_spec.array_element_type
    
    return None


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



class ObjectTypeHandler:
    """
    Helper class for managing object type operations, including member types,
    vtable creation, and method processing.
    """
    
    @staticmethod
    def initialize_object_storage(module: 'ir.Module'):
        """
        Initialize module attributes for object type storage.
        
        Args:
            module: LLVM module
        """
        if not hasattr(module, '_struct_vtables'):
            module._struct_vtables = {}
        if not hasattr(module, '_struct_types'):
            module._struct_types = {}
    
    @staticmethod
    def create_member_types(members: List, module: 'ir.Module') -> tuple:
        """
        Create LLVM types for object members.
        
        Args:
            members: List of StructMember objects
            module: LLVM module
            
        Returns:
            Tuple of (member_types, member_names)
        """
        member_types = []
        member_names = []
        
        for member in members:
            member_type = FunctionTypeHandler.convert_type_spec_to_llvm(member.type_spec, module)
            member_types.append(member_type)
            member_names.append(member.name)
        
        return member_types, member_names
    
    @staticmethod
    def create_struct_type(name: str, member_types: List, member_names: List, 
                          module: 'ir.Module') -> 'ir.Type':
        """
        Create and register a struct type for an object.
        
        Args:
            name: Object name
            member_types: List of LLVM member types
            member_names: List of member names
            module: LLVM module
            
        Returns:
            Created struct type
        """
        struct_type = ir.global_context.get_identified_type(name)
        struct_type.set_body(*member_types)
        struct_type.names = member_names
        
        if not hasattr(module, '_struct_types'):
            module._struct_types = {}
        module._struct_types[name] = struct_type
        
        return struct_type
    
    @staticmethod
    def calculate_field_layout(members: List, member_types: List) -> List[tuple]:
        """
        Calculate field layout for vtable.
        
        Args:
            members: List of StructMember objects
            member_types: List of LLVM member types
            
        Returns:
            List of (name, bit_offset, bit_width, alignment) tuples
        """
        fields = []
        for i, member in enumerate(members):
            member_type = member_types[i]
            if isinstance(member_type, ir.IntType):
                bit_width = member_type.width
                alignment = member_type.width
            elif isinstance(member_type, ir.FloatType):
                bit_width = 32
                alignment = 32
            else:
                bit_width = 64  # pointer or other
                alignment = 64
            
            bit_offset = i * bit_width
            fields.append((member.name, bit_offset, bit_width, alignment))
        
        return fields
    
    @staticmethod
    def create_vtable(name: str, fields: List[tuple], module: 'ir.Module'):
        """
        Create and register a vtable for an object.
        
        Args:
            name: Object name
            fields: List of field tuples
            module: LLVM module
        """
        from fast import StructVTable
        
        vtable = StructVTable(
            struct_name=name,
            total_bits=sum(f[2] for f in fields),
            total_bytes=(sum(f[2] for f in fields) + 7) // 8,
            alignment=max(f[3] for f in fields) if fields else 1,
            fields=fields
        )
        
        if not hasattr(module, '_struct_vtables'):
            module._struct_vtables = {}
        module._struct_vtables[name] = vtable
    
    @staticmethod
    def create_method_signature(object_name: str, method_name: str, method, 
                                struct_type: 'ir.Type', module: 'ir.Module') -> tuple:
        """
        Create method signature with 'this' parameter.
        
        Args:
            object_name: Name of the object
            method_name: Name of the method
            method: Method definition
            struct_type: LLVM struct type for the object
            module: LLVM module
            
        Returns:
            Tuple of (func_type, func_name)
        """
        from fast import DataType
        
        # Return type
        if method.return_type.base_type == DataType.THIS:
            ret_type = ir.PointerType(struct_type)
        else:
            ret_type = FunctionTypeHandler.convert_type_spec_to_llvm(method.return_type, module)
        
        # Param types: always 'this' first
        param_types = [ir.PointerType(struct_type)]
        param_types.extend([FunctionTypeHandler.convert_type_spec_to_llvm(p.type_spec, module) 
                          for p in method.parameters])
        
        func_type = ir.FunctionType(ret_type, param_types)
        mangled_method_name = FunctionTypeHandler.mangle_function_name(
            method_name, 
            method.parameters, 
            method.return_type,
            no_mangle=False  # Always mangle object methods
        )
        
        # Combine object name with mangled method name
        # For namespace__objectname, this produces: namespace__objectname.__init_0_ret_void
        func_name = f"{object_name}.{mangled_method_name}"
        
        return func_type, func_name
    
    @staticmethod
    def predeclare_method(func_type: 'ir.FunctionType', func_name: str, method, 
                         module: 'ir.Module') -> 'ir.Function':
        """
        Predeclare a method function or reuse existing.
        
        Args:
            func_type: LLVM function type
            func_name: Full method name
            method: Method definition
            module: LLVM module
            
        Returns:
            LLVM function
        """
        existing = module.globals.get(func_name)
        if existing is None:
            func = ir.Function(module, func_type, func_name)
        else:
            if not isinstance(existing, ir.Function):
                raise RuntimeError(f"{func_name} already exists and is not a function")
            if existing.function_type != func_type:
                raise RuntimeError(f"Conflicting signatures for {func_name}")
            func = existing
        
        # Name arguments
        func.args[0].name = "this"
        for i, arg in enumerate(func.args[1:], 1):
            param_name = method.parameters[i - 1].name if method.parameters[i - 1].name is not None else f"arg{i - 1}"
            arg.name = param_name

        # Register method in function overloads table for proper resolution
        # We have the actual method name from the method object, so we don't need to parse it
        # The base name is: object_name.method_name (without mangling)
        # func_name has the structure: object_name.mangled_method_name
        
        if '.' in func_name:
            # Find the dot that separates object from method
            dot_index = func_name.rfind('.')
            
            # Everything before the dot is the object name (with namespace prefix)
            object_part = func_name[:dot_index]
            
            # The base name is just object_name.actual_method_name
            base_name = f"{object_part}.{method.name}"
            
            print(f"[REGISTER METHOD] Registering method overload:", file=sys.stderr)
            print(f"  Full name: {func_name}", file=sys.stderr)
            print(f"  Method name: {method.name}", file=sys.stderr)
            print(f"  Base name: {base_name}", file=sys.stderr)
            
            FunctionTypeHandler.register_function_overload(
                module, base_name, func_name, method.parameters, method.return_type, func
            )
        
        return func

    
    @staticmethod
    def emit_method_body(method, func: 'ir.Function', object_name: str, module: 'ir.Module'):
        from fast import DataType, TypeSystem, FunctionDef
        
        if isinstance(method, FunctionDef) and method.is_prototype:
            return
        
        if len(func.blocks) != 0:
            return
        
        entry_block = func.append_basic_block('entry')
        method_builder = ir.IRBuilder(entry_block)
        
        # CRITICAL FIX: Save the current namespace context
        saved_namespace = module.symbol_table.current_namespace
        
        # Enter method scope
        module.symbol_table.enter_scope()
        
        # Register 'this' parameter
        this_type_spec = TypeSystem(base_type=DataType.DATA, custom_typename=object_name, is_pointer=True)
        module.symbol_table.define(
            "this",
            SymbolKind.VARIABLE,
            llvm_value=func.args[0],
            type_spec=this_type_spec
        )
        
        # Store other params
        for i, param in enumerate(func.args[1:], 1):
            param_name = method.parameters[i - 1].name if method.parameters[i - 1].name is not None else f"arg{i - 1}"
            alloca = method_builder.alloca(param.type, name=f"{param_name}.addr")
            method_builder.store(param, alloca)
            module.symbol_table.define(param_name, SymbolKind.VARIABLE, llvm_value=alloca)
        
        # Emit body - namespace context is still available via saved_namespace
        method.body.codegen(method_builder, module)
        
        # __init implicit return
        if isinstance(method, FunctionDef) and method.name == '__init' and not method_builder.block.is_terminated:
            method_builder.ret(func.args[0])
        
        # Implicit return for void
        if not method_builder.block.is_terminated:
            if isinstance(func.function_type.return_type, ir.VoidType):
                method_builder.ret_void()
            else:
                raise RuntimeError(f"Method {method.name} must end with return statement")
        
        # Exit method scope
        module.symbol_table.exit_scope()
        
        # CRITICAL FIX: Restore the namespace context
        module.symbol_table.current_namespace = saved_namespace
        

    @staticmethod
    def process_nested_definitions(nested_objects: List, nested_structs: List, 
                                   builder: 'ir.IRBuilder', module: 'ir.Module'):
        """
        Process nested objects and structs.
        
        Args:
            nested_objects: List of nested ObjectDef
            nested_structs: List of nested StructDef
            builder: LLVM IR builder
            module: LLVM module
        """
        for nested_obj in nested_objects:
            nested_obj.codegen(builder, module)
        
        for nested_struct in nested_structs:
            nested_struct.codegen(builder, module)


class FunctionTypeHandler:
    """
    Helper class for managing function type conversions, parameter handling,
    and function signature operations.
    """
    
    @staticmethod
    def convert_type_spec_to_llvm(type_spec, module: ir.Module) -> ir.Type:
        """
        Convert a TypeSystem to LLVM type, handling arrays and pointers.
        
        Args:
            type_spec: TypeSystem object to convert
            module: LLVM module for type resolution
            
        Returns:
            Corresponding LLVM type
        """
        return type_spec.get_llvm_type_with_array(module)
    
    @staticmethod
    def create_function_type(return_type_spec, param_type_specs: List, module: ir.Module) -> ir.FunctionType:
        """
        Create an LLVM function type from TypeSystem objects.
        
        Args:
            return_type_spec: Return type TypeSystem
            param_type_specs: List of parameter TypeSystem objects
            module: LLVM module
            
        Returns:
            LLVM FunctionType
        """
        ret_type = FunctionTypeHandler.convert_type_spec_to_llvm(return_type_spec, module)
        param_types = [FunctionTypeHandler.convert_type_spec_to_llvm(pts, module) 
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
            return_type_spec: Return type TypeSystem
            no_mangle: If True, return base name without mangling
            
        Returns:
            Mangled function name
        """
        #print("MANGLE_FUNCTION_NAME BEFORE IF CHECK OR BASE_NAME == 'main'")
        if no_mangle or base_name == "main":
            return base_name
        #print("MANGLE_FUNCTION_NAME AFTER IF CHECK OR BASE_NAME == 'main'")
        
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
            
            # Add bit width for DATA types (with signedness)
            if type_spec.base_type == DataType.DATA and type_spec.bit_width:
                sign_prefix = "sbits" if type_spec.is_signed else "ubits"
                mangled += f"_{sign_prefix}{type_spec.bit_width}"
        
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
            return_type_spec: Return type TypeSystem
            func: LLVM Function object
        """
        if not hasattr(module, '_function_overloads'):
            module._function_overloads = {}
        
        #print("IN REGISTER_FUNCTION_OVERLOAD BEFORE BASE_NAME NOT IN MODULE")
        if base_name not in module._function_overloads:
            module._function_overloads[base_name] = []
        #print("IN REGISTER_FUNCTION_OVERLOAD AFTER BASE_NAME NOT IN MODULE")
        
        # Add overload info
        # CRITICAL: Resolve custom type names to get correct signedness
        resolved_param_types = []
        for p in parameters:
            param_type = p.type_spec
            if param_type is None:
                raise ValueError(f"Parameter '{p.name}' has no type specification (symbol lookup may have failed)")
            # If this is a custom type, resolve it to get correct signedness
            if param_type.custom_typename and hasattr(module, '_type_alias_specs'):
                alias_spec = None
                type_name = param_type.custom_typename
                
                # Try to resolve through namespaces (same as in overload resolution)
                if hasattr(module, "_using_namespaces"):
                    for ns in module._using_namespaces:
                        #print("REGISTER FUNCTION OVERLOAD:",ns)
                        mangled_type_name = TypeResolver.mangle_name(ns, type_name)
                        if mangled_type_name in module._type_alias_specs:
                            alias_spec = module._type_alias_specs[mangled_type_name]
                            break
                
                # Also try direct lookup for global types
                if not alias_spec and type_name in module._type_alias_specs:
                    alias_spec = module._type_alias_specs[type_name]
                
                # If we found the alias spec, use it
                if alias_spec:
                    # Copy the is_signed from the resolved type
                    from ftypesys import TypeSystem
                    param_type = TypeSystem(
                        base_type=param_type.base_type,
                        is_signed=alias_spec.is_signed,  # Use resolved signedness
                        is_const=param_type.is_const,
                        is_volatile=param_type.is_volatile,
                        bit_width=param_type.bit_width,
                        alignment=param_type.alignment,
                        endianness=param_type.endianness,
                        is_array=param_type.is_array,
                        array_size=param_type.array_size,
                        array_dimensions=param_type.array_dimensions,
                        array_element_type=param_type.array_element_type,
                        is_pointer=param_type.is_pointer,
                        pointer_depth=param_type.pointer_depth,
                        custom_typename=param_type.custom_typename,
                        storage_class=param_type.storage_class
                    )
            resolved_param_types.append(param_type)
        
        overload_info = {
            'mangled_name': mangled_name,
            'param_types': resolved_param_types,
            'return_type': return_type_spec,
            'function': func,
            'param_count': len(parameters)
        }
        #print("END OF REGISTER_FUNCTION_OVERLOAD()")
        module._function_overloads[base_name].append(overload_info)
        #print("AFTER APPENDING OVERLOAD_INFO")
    
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
        # DEBUG: Overload resolution
        #print(f"[OVERLOAD DEBUG] Resolving {base_name} with {len(arg_vals)} args", file=sys.stderr)
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
                    #print(f"[OVERLOAD] Param {i}: custom_typename={getattr(param_type, 'custom_typename', None)}, is_array={getattr(param_type, 'is_array', None)}, is_pointer={getattr(param_type, 'is_pointer', None)}", file=sys.stderr)
                    expected_llvm_type = param_type.get_llvm_type_with_array(module)
                    #print(f"[OVERLOAD] Arg {i}: arg_type={arg_val.type}, expected={expected_llvm_type}", file=sys.stderr)
                    
                    # Check for exact type match first
                    if arg_val.type == expected_llvm_type:
                        continue
                    
                    # Handle array-to-pointer decay: [N x T]* can decay to T*
                    if (isinstance(arg_val.type, ir.PointerType) and 
                        isinstance(arg_val.type.pointee, ir.ArrayType) and
                        isinstance(expected_llvm_type, ir.PointerType)):
                        # Check if array element type matches pointer pointee type
                        if arg_val.type.pointee.element == expected_llvm_type.pointee:
                            continue  # Compatible via array decay
                    
                    # Check signedness for integer types (even if width matches)
                    if isinstance(arg_val.type, ir.IntType) and isinstance(expected_llvm_type, ir.IntType):
                        # Check if signedness matches
                        #print(f"[SIGN DEBUG] Checking arg {i}: arg_is_unsigned={is_unsigned(arg_val)}", file=sys.stderr)
                        #if hasattr(param_type, "base_type"):
                            #print(f"[SIGN DEBUG]   param has base_type={param_type.base_type}", file=sys.stderr)
                        #if hasattr(param_type, "is_signed"):
                            #print(f"[SIGN DEBUG]   param has is_signed={param_type.is_signed}", file=sys.stderr)
                        arg_is_unsigned = is_unsigned(arg_val)
                        # Determine parameter signedness by resolving type aliases
                        param_is_unsigned = False
                        
                        # If param has custom_typename, resolve it to get the underlying type
                        if hasattr(param_type, 'custom_typename') and param_type.custom_typename:
                            # Try to resolve the custom type from module type aliases
                            type_name = param_type.custom_typename
                            resolved_type_spec = None
                            
                            #print(f"[TYPE RESOLVE] Looking for {type_name} in type aliases", file=sys.stderr)
                            
                            # Use TypeResolver to resolve type through namespace system
                            # Types in namespaces are mangled (u32 -> standard__types__u32)
                            if hasattr(module, "_using_namespaces"):
                                for ns in module._using_namespaces:
                                    mangled_name = TypeResolver.mangle_name(ns, type_name)
                                    if hasattr(module, '_type_alias_specs') and mangled_name in module._type_alias_specs:
                                        resolved_type_spec = module._type_alias_specs[mangled_name]
                                        #print(f"[TYPE RESOLVE] Found {type_name} as {mangled_name}", file=sys.stderr)
                                        break
                            
                            # Also try direct lookup for global types
                            if not resolved_type_spec and hasattr(module, '_type_alias_specs'):
                                if type_name in module._type_alias_specs:
                                    resolved_type_spec = module._type_alias_specs[type_name]
                                    #print(f"[TYPE RESOLVE] Found {type_name} directly", file=sys.stderr)
                            
                            # If we resolved the type spec, use it
                            if resolved_type_spec:
                                if hasattr(resolved_type_spec, 'base_type') and resolved_type_spec.base_type == DataType.UINT:
                                    param_is_unsigned = True
                                elif hasattr(resolved_type_spec, 'is_signed'):
                                    param_is_unsigned = not resolved_type_spec.is_signed
                            # Fall back to using param_type's own is_signed if available
                            elif hasattr(param_type, 'is_signed'):
                                param_is_unsigned = not param_type.is_signed
                        # Check base_type directly
                        elif hasattr(param_type, 'base_type') and param_type.base_type == DataType.UINT:
                            param_is_unsigned = True
                        elif hasattr(param_type, 'is_signed'):
                            param_is_unsigned = not param_type.is_signed
                        if arg_is_unsigned != param_is_unsigned:
                            # Signedness mismatch
                            match = False
                            break
                        # Signedness matches, continue
                        continue
                    
                    # No other compatibility - types don't match
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
        
        # Integer type coercion - handle width mismatches
        if isinstance(arg_val.type, ir.IntType) and isinstance(expected_type, ir.IntType):
            if arg_val.type.width != expected_type.width:
                # Check if argument is unsigned
                unsigned = CoercionContext.is_unsigned(arg_val)
                
                if arg_val.type.width < expected_type.width:
                    # Extending to larger width
                    return builder.zext(arg_val, expected_type) if unsigned else builder.sext(arg_val, expected_type)
                else:
                    # Truncating to smaller width
                    return builder.trunc(arg_val, expected_type)
        
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
    #print("IN MANGLE_NAME()")
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
    ctx = CoercionContext(builder)
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
            unsigned = CoercionContext.is_unsigned(value)
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


class AssignmentTypeHandler:
    """
    Helper class for managing assignment type conversions, compatibility checks,
    and special assignment handling (array, struct member, union, pointer deref).
    """
    
    @staticmethod
    def handle_identifier_assignment(builder, module, target_name: str, val, value_expr):
        """
        Handle assignment to a simple identifier (variable).
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            target_name: Name of the target variable
            val: Value to assign (already generated)
            value_expr: The value expression AST node (for type checking)
            
        Returns:
            The assigned value
        """
        # Get the variable pointer
        if module.symbol_table.get_llvm_value(target_name) is not None:
            # Local variable
            ptr = module.symbol_table.get_llvm_value(target_name)
        elif target_name in module.globals:
            # Global variable
            ptr = module.globals[target_name]
        else:
            raise NameError(f"Unknown variable: {target_name}")
        
        # Check if this is an array concatenation assignment that requires resizing
        from fast import BinaryOp, Operator
        if (isinstance(value_expr, BinaryOp) and value_expr.operator == Operator.ADD and
            isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, ir.ArrayType)):
            # This is the result of array concatenation - update variable to point to new array
            if module.symbol_table.get_llvm_value(target_name) is not None:
                # For local variables, update the scope to point to the new array
                module.symbol_table.update_llvm_value(target_name, val)
                return val
            else:
                # For global variables, we can't easily resize, so convert to element pointer
                zero = ir.Constant(ir.IntType(1), 0)
                array_ptr = builder.gep(val, [zero, zero], name="array_to_ptr")
                builder.store(array_ptr, ptr)
                return array_ptr
        
        # Handle type compatibility for assignments
        val = AssignmentTypeHandler.convert_value_for_assignment(builder, val, ptr.type.pointee)
        
        st = builder.store(val, ptr)
        st.volatile = True
        return val
    
    @staticmethod
    def convert_value_for_assignment(builder, val, target_type):
        """
        Convert value type to match target type if needed.
        
        Args:
            builder: LLVM IR builder
            val: Value to potentially convert
            target_type: Expected target type
            
        Returns:
            Converted value
        """
        if val.type == target_type:
            return val
        
        # CRITICAL FIX: If val is T** and target is T*, load to get T*
        # This happens when assigning a pointer variable to a struct member
        if (isinstance(val.type, ir.PointerType) and 
            isinstance(val.type.pointee, ir.PointerType) and
            isinstance(target_type, ir.PointerType) and
            val.type.pointee == target_type):
            # Load T** to get T*
            return builder.load(val, name="ptr_val_loaded")
        
        # Handle pointer type compatibility - if both are pointers to the same pointee type
        if isinstance(val.type, ir.PointerType) and isinstance(target_type, ir.PointerType):
            # Check if pointee types are equivalent
            if val.type.pointee == target_type.pointee:
                # Types are structurally identical, just use bitcast to make LLVM happy
                return builder.bitcast(val, target_type, name="ptr_compat")
            # Special case: both are pointers to i8 (byte* compatibility)
            if (isinstance(val.type.pointee, ir.IntType) and val.type.pointee.width == 8 and
                isinstance(target_type.pointee, ir.IntType) and target_type.pointee.width == 8):
                return builder.bitcast(val, target_type, name="i8ptr_compat")
        
        # Handle array pointer assignments - for arrays, just store the pointer directly
        if (isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, ir.ArrayType) and
            isinstance(target_type, ir.PointerType)):
            # This is assigning an array to a pointer type (like noopstr)
            # Get pointer to first element of array
            zero = ir.Constant(ir.IntType(1), 0)
            array_ptr = builder.gep(val, [zero, zero], name="array_to_ptr")
            return array_ptr
        
        # Handle void* to typed pointer assignment (e.g., py = (@)pxk where pxk is int)
        if (isinstance(val.type, ir.PointerType) and 
              isinstance(val.type.pointee, ir.IntType) and val.type.pointee.width == 8 and
              isinstance(target_type, ir.PointerType)):
            # This is assigning void* (i8*) to a typed pointer
            return builder.bitcast(val, target_type, name="void_ptr_to_typed")
        
        # Handle integer type mismatches using CoercionContext
        if isinstance(val.type, ir.IntType) and isinstance(target_type, ir.IntType):
            if val.type.width != target_type.width:
                # Determine signedness from the value's metadata using CoercionContext
                unsigned = CoercionContext.is_unsigned(val)
                
                # Handle widening (extending to larger type)
                if val.type.width < target_type.width:
                    if unsigned:
                        result = builder.zext(val, target_type)
                    else:
                        result = builder.sext(val, target_type)
                    
                    # Preserve metadata
                    if hasattr(val, '_flux_type_spec'):
                        result._flux_type_spec = val._flux_type_spec
                        result._flux_type_spec.bit_width = target_type.width
                    
                    return result
                
                # Handle narrowing (truncating to smaller type)
                else:
                    result = builder.trunc(val, target_type)
                    
                    # Preserve metadata
                    if hasattr(val, '_flux_type_spec'):
                        result._flux_type_spec = val._flux_type_spec
                        result._flux_type_spec.bit_width = target_type.width
                    
                    return result
        
        return val
    
    @staticmethod
    def handle_member_assignment(builder, module, target_obj_expr, member_name: str, val):
        """
        Handle assignment to a struct/object member.
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            target_obj_expr: The object expression (e.g., Identifier)
            member_name: Name of the member being assigned
            val: Value to assign
            
        Returns:
            The assigned value
        """
        from fast import Identifier
        
        # For member access, we need the pointer, not the loaded value
        if isinstance(target_obj_expr, Identifier):
            # Get the variable pointer directly from scope instead of loading
            var_name = target_obj_expr.name
            if module.symbol_table.get_llvm_value(var_name) is not None:
                obj = module.symbol_table.get_llvm_value(var_name)  # This is the pointer
                if isinstance(obj.type, ir.PointerType) and isinstance(obj.type.pointee, ir.PointerType):
                    # Check if the pointee-pointee is a struct
                    if (isinstance(obj.type.pointee.pointee, ir.LiteralStructType) or
                        hasattr(obj.type.pointee.pointee, '_name') or
                        hasattr(obj.type.pointee.pointee, 'elements')):
                        # This is a pointer parameter - load it to get the actual pointer
                        obj = builder.load(obj, name=f"{var_name}_ptr")
            elif var_name in module.globals:
                obj = module.globals[var_name]  # This is the pointer
            else:
                raise NameError(f"Unknown variable: {var_name}")
        else:
            # For other expressions, generate code normally
            obj = target_obj_expr.codegen(builder, module)
        
        # Handle both literal struct types and identified struct types
        is_struct_pointer = (isinstance(obj.type, ir.PointerType) and 
                        (isinstance(obj.type.pointee, ir.LiteralStructType) or
                         hasattr(obj.type.pointee, '_name') or  # Identified struct type
                         hasattr(obj.type.pointee, 'elements')))  # Other struct-like types
        
        if is_struct_pointer:
            struct_type = obj.type.pointee
            
            # Check if this is a union first
            if hasattr(module, '_union_types'):
                for union_name, union_type in module._union_types.items():
                    if union_type == struct_type:
                        # This is a union - handle union member assignment
                        return handle_union_member_assignment(builder, module, obj, union_name, member_name, val)
            
            # Regular struct member assignment
            if hasattr(struct_type, 'names'):
                try:
                    idx = struct_type.names.index(member_name)
                    member_ptr = builder.gep(
                        obj,
                        [ir.Constant(ir.IntType(1), 0),
                         ir.Constant(ir.IntType(32), idx)],
                        inbounds=True
                    )
                    # Convert value type to match target member type if needed
                    member_type = member_ptr.type.pointee
                    val = AssignmentTypeHandler.convert_value_for_assignment(builder, val, member_type)
                    builder.store(val, member_ptr)
                    return val
                except ValueError:
                    raise ValueError(f"Member '{member_name}' not found in struct")
            else:
                # This is a byte-array based struct - use vtable for field assignment
                return AssignmentTypeHandler.handle_vtable_struct_assignment(
                    builder, module, obj, target_obj_expr, member_name, val)
        
        raise ValueError(f"Cannot assign to member '{member_name}' of non-struct type: {obj.type}")
    
    @staticmethod
    def handle_vtable_struct_assignment(builder, module, struct_ptr, target_obj_expr, member_name: str, val):
        """
        Handle struct member assignment for byte-array based structs using vtable.
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            struct_ptr: Pointer to the struct
            target_obj_expr: The target object expression (for type info)
            member_name: Name of the member
            val: Value to assign
            
        Returns:
            The assigned value
        """
        from fast import Identifier
        
        # Determine struct name from the pointer type
        struct_name = None
        struct_type = struct_ptr.type.pointee
        
        # Try to match with registered struct types
        if hasattr(module, '_struct_types'):
            for name, registered_type in module._struct_types.items():
                if registered_type == struct_type:
                    struct_name = name
                    break
        
        if struct_name is None:
            # Try to infer from symbol table type information
            if isinstance(target_obj_expr, Identifier):
                var_name = target_obj_expr.name
                entry = module.symbol_table.lookup_variable(var_name)
                if entry and entry.type_spec is not None:
                    type_spec = entry.type_spec
                    if type_spec.custom_typename:
                        struct_name = type_spec.custom_typename
        
        if struct_name is None:
            raise ValueError(f"Cannot determine struct type for member assignment")
        
        # Get vtable
        if not hasattr(module, '_struct_vtables') or struct_name not in module._struct_vtables:
            raise ValueError(f"Vtable not found for struct '{struct_name}'")
        
        vtable = module._struct_vtables[struct_name]
        
        # Find field in vtable
        field_info = next(
            (f for f in vtable.fields if f[0] == member_name),
            None
        )
        if not field_info:
            raise ValueError(f"Field '{member_name}' not found in struct '{struct_name}'")
        
        _, bit_offset, bit_width, alignment = field_info
        
        # Load the current struct value
        current_struct = builder.load(struct_ptr, name="current_struct")
        
        # Convert float to integer if needed
        if isinstance(val.type, ir.FloatType):
            int_type = ir.IntType(bit_width)
            val = builder.bitcast(val, int_type)
        
        # Generate inline assignment code based on struct storage type
        if isinstance(current_struct.type, ir.IntType):
            # Integer type - simple bit operations
            return AssignmentTypeHandler._assign_bitfield_integer(
                builder, current_struct, struct_ptr, val, bit_offset, bit_width)
        else:
            # Array type - byte manipulation
            return AssignmentTypeHandler._assign_bitfield_array(
                builder, current_struct, struct_ptr, val, bit_offset, bit_width)
    
    @staticmethod
    def _assign_bitfield_integer(builder, current_struct, struct_ptr, val, bit_offset: int, bit_width: int):
        """
        Assign a value to a bitfield in an integer-type struct.
        
        Args:
            builder: LLVM IR builder
            current_struct: Current struct value
            struct_ptr: Pointer to the struct
            val: Value to assign
            bit_offset: Bit offset of the field
            bit_width: Bit width of the field
            
        Returns:
            The assigned value
        """
        instance_type = current_struct.type
        
        # Create mask to clear the field
        mask = ((1 << bit_width) - 1) << bit_offset
        inverse_mask = (~mask) & ((1 << instance_type.width) - 1)
        
        # Clear the field
        cleared = builder.and_(current_struct, ir.Constant(instance_type, inverse_mask))
        
        # Shift value to position
        if val.type.width < instance_type.width:
            val_extended = builder.zext(val, instance_type)
        elif val.type.width > instance_type.width:
            val_extended = builder.trunc(val, instance_type)
        else:
            val_extended = val
        
        if bit_offset > 0:
            val_shifted = builder.shl(val_extended, ir.Constant(instance_type, bit_offset))
        else:
            val_shifted = val_extended
        
        # Combine
        new_struct = builder.or_(cleared, val_shifted)
        
        # Store back
        builder.store(new_struct, struct_ptr)
        return val
    
    @staticmethod
    def _assign_bitfield_array(builder, current_struct, struct_ptr, val, bit_offset: int, bit_width: int):
        """
        Assign a value to a bitfield in an array-type struct.
        
        Args:
            builder: LLVM IR builder
            current_struct: Current struct value
            struct_ptr: Pointer to the struct
            val: Value to assign
            bit_offset: Bit offset of the field
            bit_width: Bit width of the field
            
        Returns:
            The assigned value
        """
        byte_offset = bit_offset // 8
        bit_in_byte = bit_offset % 8
        
        if bit_in_byte == 0 and bit_width % 8 == 0:
            # Byte-aligned field - simple case
            field_bytes = bit_width // 8
            
            # Ensure val is the right type
            if val.type.width != bit_width:
                if val.type.width < bit_width:
                    val = builder.zext(val, ir.IntType(bit_width))
                else:
                    val = builder.trunc(val, ir.IntType(bit_width))
            
            # Insert bytes into the struct
            new_struct = current_struct
            for i in range(field_bytes):
                # Extract byte from value
                shift_amount = i * 8
                byte_val = builder.lshr(val, ir.Constant(val.type, shift_amount))
                byte_val = builder.and_(byte_val, ir.Constant(val.type, 0xFF))
                byte_val = builder.trunc(byte_val, ir.IntType(8))
                
                # Insert into array
                new_struct = builder.insert_value(new_struct, byte_val, byte_offset + i)
            
            # Store back
            builder.store(new_struct, struct_ptr)
            return val
        else:
            raise NotImplementedError("Unaligned field assignment in large structs not yet supported")
    
    @staticmethod
    def handle_array_element_assignment(builder, module, array_expr, index_expr, value_expr, val):
        """
        Handle assignment to an array element.
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            array_expr: Array expression AST node (the array part, not the whole ArrayAccess)
            index_expr: Index expression AST node
            value_expr: Value expression AST node
            val: Generated value to assign
            
        Returns:
            The assigned value
        """
        from fast import StringLiteral, Identifier
        
        # For array assignment, generate the array expression normally
        # This handles all the loading logic correctly through Identifier codegen
        array = array_expr.codegen(builder, module)
        
        import sys
        print(f"[ARRAY ASSIGN DEBUG] INITIAL array.type: {array.type}", file=sys.stderr)
        if hasattr(array, '_flux_type_spec'):
            print(f"[ARRAY ASSIGN DEBUG] array has _flux_type_spec: {array._flux_type_spec}", file=sys.stderr)
        
        # CRITICAL FIX: If we got i8** (pointer-to-pointer), we need to load it
        # This happens with scalar pointer variables like `noopstr dest` (byte*)
        # which are stored as i8** but need to be loaded to i8* for array indexing
        # HOWEVER: Don't load if:
        # 1. This is an array of pointers (like noopstr[3]) with array_size in metadata
        # 2. This is a pointer to pointer type (like byte**) used for dynamic arrays
        if (isinstance(array.type, ir.PointerType) and 
            isinstance(array.type.pointee, ir.PointerType) and
            not isinstance(array.type.pointee.pointee, ir.ArrayType)):
            
            # Check type metadata to determine if we should load
            should_load = True
            if hasattr(array, '_flux_type_spec'):
                type_spec = array._flux_type_spec
                # Case 1: Array variable (noopstr[3]) - has array_size
                if hasattr(type_spec, 'array_size') and type_spec.array_size is not None:
                    should_load = False
                # Case 2: Pointer-to-pointer variable (byte**) - has pointer_depth >= 2
                # These are used for dynamic arrays and should NOT be loaded
                elif hasattr(type_spec, 'pointer_depth') and type_spec.pointer_depth >= 2:
                    should_load = False
            
            if should_load:
                # This is T* stored as T** - load to get T*
                import sys
                print(f"[LOAD DEBUG] BEFORE load: array.type = {array.type}", file=sys.stderr)
                array = builder.load(array, name="ptr_loaded_for_indexing")
                print(f"[LOAD DEBUG] AFTER load: array.type = {array.type}", file=sys.stderr)
        index = index_expr.codegen(builder, module)
        
        import sys
        print(f"[ARRAY ASSIGN] array.type: {array.type}", file=sys.stderr)
        print(f"[ARRAY ASSIGN] val.type: {val.type}", file=sys.stderr)
        
        if isinstance(array.type, ir.PointerType) and isinstance(array.type.pointee, ir.ArrayType):
            # Calculate element pointer for pointer-to-array
            zero = ir.Constant(ir.IntType(1), 0)
            elem_ptr = builder.gep(array, [zero, index], inbounds=True)
            
            # FIX: Handle StringLiteral assignment to byte array elements
            element_type = array.type.pointee.element
            if isinstance(value_expr, StringLiteral) and isinstance(element_type, ir.IntType) and element_type.width == 8:
                # Extract first character from string literal
                if len(value_expr.value) > 0:
                    val = ir.Constant(ir.IntType(8), ord(value_expr.value[0]))
                else:
                    val = ir.Constant(ir.IntType(8), 0)
            else:
                # No conversion - LLVM handles compatible pointer types
                pass
            builder.store(val, elem_ptr)
            return val
        elif isinstance(array.type, ir.PointerType):
            # Handle plain pointer types (like byte*) - pointer arithmetic
            import sys
            print(f"[PTR ASSIGN DEBUG] array.type: {array.type}", file=sys.stderr)
            print(f"[PTR ASSIGN DEBUG] array.type.pointee: {array.type.pointee}", file=sys.stderr)
            elem_ptr = builder.gep(array, [index], inbounds=True)
            
            import sys
            print(f"[PTR ASSIGN] elem_ptr.type: {elem_ptr.type}", file=sys.stderr)
            print(f"[PTR ASSIGN] elem_ptr.type.pointee: {elem_ptr.type.pointee}", file=sys.stderr)
            
            # FIX: Handle StringLiteral assignment to byte pointer elements
            element_type = array.type.pointee
            if isinstance(value_expr, StringLiteral) and isinstance(element_type, ir.IntType) and element_type.width == 8:
                # Extract first character from string literal
                if len(value_expr.value) > 0:
                    val = ir.Constant(ir.IntType(8), ord(value_expr.value[0]))
                else:
                    val = ir.Constant(ir.IntType(8), 0)
            
            print(f"[PTR ASSIGN] val.type: {val.type}", file=sys.stderr)
            print(f"[PTR ASSIGN] element_type: {element_type}", file=sys.stderr)
            print(f"[PTR ASSIGN] isinstance(val.type, ir.PointerType): {isinstance(val.type, ir.PointerType)}", file=sys.stderr)
            print(f"[PTR ASSIGN] isinstance(element_type, ir.PointerType): {isinstance(element_type, ir.PointerType)}", file=sys.stderr)
            
            # Handle pointer type compatibility - if both are pointers, bitcast if needed
            if isinstance(val.type, ir.PointerType) and isinstance(element_type, ir.PointerType):
                print(f"[PTR ASSIGN] Both are pointers, checking equality", file=sys.stderr)
                print(f"[PTR ASSIGN] val.type == element_type: {val.type == element_type}", file=sys.stderr)
                if val.type != element_type:
                    print(f"[PTR ASSIGN] Doing bitcast", file=sys.stderr)
                    val = builder.bitcast(val, element_type, name="ptr_cast")
            
            # Note: val is already generated in the caller, so we just use it directly
            # No type conversion needed - LLVM handles compatible pointer types
            print(f"[PTR ASSIGN] About to store, val.type: {val.type}", file=sys.stderr)
            builder.store(val, elem_ptr)
            return val
        else:
            raise ValueError("Cannot index non-array type")
    
    @staticmethod
    def handle_pointer_deref_assignment(builder, ptr, val):
        """
        Handle assignment through pointer dereference.
        
        Args:
            builder: LLVM IR builder
            ptr: Pointer to dereference
            val: Value to assign
            
        Returns:
            The assigned value
        """
        if isinstance(ptr.type, ir.PointerType):
            # Convert value type to match pointee type if needed
            pointee_type = ptr.type.pointee
            val = AssignmentTypeHandler.convert_value_for_assignment(builder, val, pointee_type)
            builder.store(val, ptr)
            return val
        else:
            raise ValueError(f"Cannot dereference non-pointer type: {ptr.type}")
    
    @staticmethod
    def handle_compound_assignment(builder, module, target_expr, op_token, value_expr):
        """
        Handle compound assignments like +=, -=, *=, /=, %=, etc.
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            target_expr: Target expression AST node
            op_token: TokenType for the compound operator
            value_expr: Value expression AST node
            
        Returns:
            The assigned value
        """
        from fast import TokenType, Operator, Identifier, BinaryOp, Assignment
        
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
        
        if op_token not in op_map:
            raise ValueError(f"Unsupported compound assignment operator: {op_token}")
        
        binary_op = op_map[op_token]
        
        # For compound assignment like s += q, this is equivalent to s = s + q
        # But we need to handle array concatenation specially to support dynamic resizing
        
        # Check if this is array concatenation (ADD operation with array operands)
        if binary_op == Operator.ADD and isinstance(target_expr, Identifier):
            # Get the target variable
            if module.symbol_table.get_llvm_value(target_expr.name) is not None:
                target_ptr = module.symbol_table.get_llvm_value(target_expr.name)
            elif target_expr.name in module.globals:
                target_ptr = module.globals[target_expr.name]
            else:
                raise NameError(f"Unknown variable: {target_expr.name}")
            
            # Load the current value of the target
            target_val = target_expr.codegen(builder, module)
            right_val = value_expr.codegen(builder, module)
            
            # Check if both operands are arrays or array pointers
            if (is_array_or_array_pointer(target_val) and is_array_or_array_pointer(right_val)):
                # This is array concatenation - create the binary operation
                binary_expr = BinaryOp(target_expr, binary_op, value_expr)
                concat_result = binary_expr.codegen(builder, module)
                
                # For array concatenation, we need to resize the variable to accommodate the new array
                # This is similar to dynamic reallocation - create new storage and update the variable
                if isinstance(concat_result.type, ir.PointerType) and isinstance(concat_result.type.pointee, ir.ArrayType):
                    # The concatenated result is a new array with the proper size
                    # Update the variable to point to this new array
                    if module.symbol_table.get_llvm_value(target_expr.name) is not None:
                        # For local variables, update the scope to point to the new array
                        module.symbol_table.update_llvm_value(target_expr.name, concat_result)
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
        binary_expr = BinaryOp(target_expr, binary_op, value_expr)
        assignment = Assignment(target_expr, binary_expr)
        return assignment.codegen(builder, module)


class StructTypeHandler:
    """
    Helper class for managing struct type operations, including vtable creation,
    field packing/unpacking, field access, and struct literal handling.
    """
    
    @staticmethod
    def initialize_struct_storage(module: 'ir.Module'):
        """
        Initialize module attributes for struct type storage.
        
        Args:
            module: LLVM module
        """
        if not hasattr(module, '_struct_vtables'):
            module._struct_vtables = {}
        if not hasattr(module, '_struct_types'):
            module._struct_types = {}
        if not hasattr(module, '_struct_storage_classes'):
            module._struct_storage_classes = {}
        if not hasattr(module, '_struct_member_type_specs'):
            module._struct_member_type_specs = {}
    
    @staticmethod
    def calculate_vtable(members: List, module: 'ir.Module') -> 'StructVTable':
        """
        Calculate struct layout and generate vtable (TLD).
        
        Args:
            members: List of StructMember objects
            module: LLVM module
            
        Returns:
            StructVTable with field layout information
        """
        from fast import StructVTable, get_builtin_bit_width
        
        fields = []
        field_types = {}
        current_offset = 0
        max_alignment = 1
        
        for member in members:
            member_type = member.type_spec
            
            # Get the LLVM type for this field - use get_llvm_type_with_array to handle arrays
            llvm_field_type = member_type.get_llvm_type_with_array(module)
            field_types[member.name] = llvm_field_type
            
            if member_type.bit_width is not None:
                bit_width = member_type.bit_width
                alignment = member_type.alignment if member_type.alignment is not None else bit_width
            elif member_type.custom_typename:
                # Use TypeSystem.get_llvm_type() which handles all type lookups properly
                llvm_type = llvm_field_type
                
                # Calculate bit width and alignment from the LLVM type
                if isinstance(llvm_type, ir.IntType):
                    bit_width = llvm_type.width
                    alignment = llvm_type.width
                elif isinstance(llvm_type, ir.FloatType):
                    bit_width = 32
                    alignment = 32
                elif isinstance(llvm_type, ir.DoubleType):
                    bit_width = 64
                    alignment = 64
                elif isinstance(llvm_type, ir.ArrayType):
                    # For arrays, calculate total bit width
                    element_type = llvm_type.element
                    if isinstance(element_type, ir.IntType):
                        bit_width = element_type.width * llvm_type.count
                        alignment = element_type.width
                    else:
                        # Default fallback
                        bit_width = 8 * llvm_type.count
                        alignment = 8
                else:
                    # Default fallback for other types
                    bit_width = 32
                    alignment = 32
            else:
                bit_width = get_builtin_bit_width(member_type.base_type)
                alignment = bit_width
            
            if alignment > 1:
                misalignment = current_offset % alignment
                if misalignment != 0:
                    current_offset += alignment - misalignment
            
            fields.append((member.name, current_offset, bit_width, alignment))
            member.offset = current_offset
            
            current_offset += bit_width
            max_alignment = max(max_alignment, alignment)
        
        total_bits = current_offset
        
        if max_alignment > 1:
            misalignment = total_bits % max_alignment
            if misalignment != 0:
                total_bits += max_alignment - misalignment
        
        total_bytes = (total_bits + 7) // 8
        
        return StructVTable(
            struct_name="",  # Will be set by caller
            total_bits=total_bits,
            total_bytes=total_bytes,
            alignment=max_alignment,
            fields=fields,
            field_types=field_types
        )
    
    @staticmethod
    def create_struct_type(name: str, vtable: 'StructVTable', module: 'ir.Module') -> 'ir.Type':
        """
        Create proper LLVM struct type with named fields.
        
        Args:
            name: Struct name
            vtable: StructVTable with field information
            module: LLVM module
            
        Returns:
            Created struct type
        """
        field_types = [vtable.field_types[field_name] for field_name, _, _, _ in vtable.fields]
        instance_type = ir.LiteralStructType(field_types)
        instance_type.names = [field_name for field_name, _, _, _ in vtable.fields]
        
        return instance_type
    
    @staticmethod
    def pack_field_value(builder: 'ir.IRBuilder', instance: 'ir.Value', field_value: 'ir.Value',
                        bit_offset: int, bit_width: int, total_bits: int) -> 'ir.Value':
        """
        Pack a field value into the struct instance at the correct bit offset.
        
        Args:
            builder: LLVM IR builder
            instance: Current struct instance value
            field_value: Value to pack into field
            bit_offset: Bit offset of the field
            bit_width: Bit width of the field
            total_bits: Total bits in the struct
            
        Returns:
            Updated instance value
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
            byte_offset = bit_offset // 8
            bit_in_byte = bit_offset % 8
            
            # For now, support only byte-aligned fields in array structs
            if bit_in_byte != 0 or bit_width % 8 != 0:
                raise NotImplementedError(
                    "Unaligned fields in large structs not yet supported"
                )
            
            # Insert bytes at correct position
            field_bytes = bit_width // 8
            
            # Convert float to integer representation if needed
            if isinstance(field_value.type, ir.FloatType):
                # Convert float to its integer bit representation
                int_type = ir.IntType(bit_width)
                field_value = builder.bitcast(field_value, int_type)
            
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
    
    @staticmethod
    def create_zeroed_instance(struct_type: 'ir.Type', vtable: 'StructVTable') -> 'ir.Constant':
        """
        Create a zeroed instance of a struct.
        
        Args:
            struct_type: LLVM struct type
            vtable: StructVTable with field information
            
        Returns:
            Zero-initialized struct constant
        """
        if isinstance(struct_type, ir.IntType):
            return ir.Constant(struct_type, 0)
        elif isinstance(struct_type, ir.LiteralStructType):
            # For proper struct types, initialize each field to zero
            zero_values = []
            for field_type in struct_type.elements:
                if isinstance(field_type, ir.IntType):
                    zero_values.append(ir.Constant(field_type, 0))
                elif isinstance(field_type, ir.FloatType):
                    zero_values.append(ir.Constant(field_type, 0.0))
                elif isinstance(field_type, ir.DoubleType):
                    zero_values.append(ir.Constant(field_type, 0.0))
                else:
                    # Default to an integer constant for other types
                    zero_values.append(ir.Constant(ir.IntType(32), 0))
            return ir.Constant(struct_type, zero_values)
        else:
            return ir.Constant(struct_type, [ir.Constant(ir.IntType(8), 0)] * vtable.total_bytes)
    
    @staticmethod
    def pack_struct_literal(builder: 'ir.IRBuilder', module: 'ir.Module', struct_type: str,
                           field_values: dict, positional_values: list) -> 'ir.Value':
        """
        Pack field values into a struct literal.
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            struct_type: Name of the struct type
            field_values: Dictionary of field_name -> Expression
            positional_values: List of positional Expression values
            
        Returns:
            Packed struct instance
        """
        # Get struct vtable
        if not hasattr(module, '_struct_vtables'):
            raise ValueError(f"Struct '{struct_type}' not defined")
        
        vtable = module._struct_vtables.get(struct_type)
        if not vtable:
            raise ValueError(f"Struct '{struct_type}' not defined")
        
        llvm_struct_type = module._struct_types[struct_type]
        
        # Handle positional initialization
        if positional_values:
            # Convert positional to named based on field order
            if len(positional_values) > len(vtable.fields):
                raise ValueError(
                    f"Too many initializers for struct '{struct_type}': "
                    f"got {len(positional_values)}, expected {len(vtable.fields)}"
                )
            
            # Map positional values to field names
            for i, value in enumerate(positional_values):
                field_name = vtable.fields[i][0]
                field_values[field_name] = value
        
        # Create zeroed instance
        instance = StructTypeHandler.create_zeroed_instance(llvm_struct_type, vtable)
        
        # Pack field values
        if isinstance(llvm_struct_type, ir.LiteralStructType):
            # For proper struct types, build the constant directly with all field values
            field_constants = []
            for i, (field_name, _, _, _) in enumerate(vtable.fields):
                if field_name in field_values:
                    # Generate the field value
                    field_value_expr = field_values[field_name]
                    field_value = field_value_expr.codegen(builder, module)
                    # For constants, we can use them directly
                    if isinstance(field_value, ir.Constant):
                        field_constants.append(field_value)
                    else:
                        # Non-constant value - we need to use insertvalue instructions
                        # But for struct literals, all values should be constants
                        raise ValueError(f"Struct literal field '{field_name}' must be a constant expression")
                else:
                    # Use the zero value we created
                    field_constants.append(instance.constant_value[i])
            
            # Create the final struct constant
            instance = ir.Constant(llvm_struct_type, field_constants)
        else:
            # For packed integer or byte array structs, use the old packing method
            for field_name, field_value_expr in field_values.items():
                field_info = next(
                    (f for f in vtable.fields if f[0] == field_name),
                    None
                )
                if not field_info:
                    raise ValueError(f"Field '{field_name}' not found in struct '{struct_type}'")
                
                _, bit_offset, bit_width, alignment = field_info
                
                # Generate value
                field_value = field_value_expr.codegen(builder, module)
                
                # Pack into instance
                instance = StructTypeHandler.pack_field_value(
                    builder, instance, field_value, 
                    bit_offset, bit_width, vtable.total_bits
                )
        
        return instance
    
    @staticmethod
    def extract_field_value(builder: 'ir.IRBuilder', module: 'ir.Module', instance: 'ir.Value',
                           struct_name: str, field_name: str, vtable: 'StructVTable') -> 'ir.Value':
        """
        Extract a field value from a struct instance.
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            instance: Struct instance value
            struct_name: Name of the struct type
            field_name: Name of the field to extract
            vtable: StructVTable with field information
            
        Returns:
            Extracted field value
        """
        field_info = next((f for f in vtable.fields if f[0] == field_name), None)
        if not field_info:
            raise ValueError(f"Field '{field_name}' not found in struct '{struct_name}'")
        
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
                return builder.trunc(masked, field_type, name=field_name)
            return masked
        
        # Struct value extraction by index (vtable order)
        if isinstance(instance.type, (ir.LiteralStructType, ir.IdentifiedStructType)):
            field_index = None
            for i, f in enumerate(vtable.fields):
                if f[0] == field_name:
                    field_index = i
                    break
            if field_index is None:
                raise ValueError(f"Field '{field_name}' not found in struct '{struct_name}'")
            return builder.extract_value(instance, field_index, name=field_name)
        
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
            
            # Optional typed reinterpret (if vtable carries it)
            if hasattr(vtable, "field_types") and field_name in vtable.field_types:
                target_type = vtable.field_types[field_name]
                if isinstance(target_type, ir.FloatType) and isinstance(result.type, ir.IntType):
                    result = builder.bitcast(result, target_type)
            return result
        
        raise NotImplementedError("Unaligned field access in large structs not yet supported")
    
    @staticmethod
    def assign_field_value(builder: 'ir.IRBuilder', module: 'ir.Module', instance_ptr: 'ir.Value',
                          struct_name: str, field_name: str, new_value: 'ir.Value',
                          vtable: 'StructVTable') -> 'ir.Value':
        """
        Assign a value to a struct field.
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            instance_ptr: Pointer to struct instance
            struct_name: Name of the struct type
            field_name: Name of the field to assign
            new_value: New value to assign
            vtable: StructVTable with field information
            
        Returns:
            Updated instance value
        """
        # Load current value
        instance = builder.load(instance_ptr)
        
        # Find field
        field_info = next(
            (f for f in vtable.fields if f[0] == field_name),
            None
        )
        if not field_info:
            raise ValueError(f"Field '{field_name}' not found")
        
        _, bit_offset, bit_width, alignment = field_info
        
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
    
    @staticmethod
    def perform_struct_recast(builder: 'ir.IRBuilder', module: 'ir.Module',
                             target_type: str, source_value: 'ir.Value') -> 'ir.Value':
        """
        Perform zero-cost struct reinterpretation cast.
        
        Args:
            builder: LLVM IR builder
            module: LLVM module
            target_type: Name of target struct type
            source_value: Source value to recast
            
        Returns:
            Recasted value
        """
        # Get target struct vtable
        if not hasattr(module, '_struct_vtables'):
            raise ValueError(f"Struct '{target_type}' not defined")
        
        target_vtable = module._struct_vtables.get(target_type)
        if not target_vtable:
            raise ValueError(f"Struct '{target_type}' not defined")
        
        llvm_target_type = module._struct_types[target_type]
        
        # Compile-time size check if source size is known
        if hasattr(source_value.type, 'count'):
            # Array type - check size at compile time
            source_bytes = source_value.type.count
            if source_bytes != target_vtable.total_bytes:
                raise ValueError(
                    f"Size mismatch in cast to {target_type}: "
                    f"source is {source_bytes} bytes, target requires {target_vtable.total_bytes} bytes"
                )
        
        # Perform zero-cost bitcast
        if isinstance(source_value.type, ir.PointerType):
            # Cast pointer, then load
            casted_ptr = builder.bitcast(source_value, llvm_target_type.as_pointer())
            result = builder.load(casted_ptr)
        else:
            # Direct bitcast (reinterpret bits)
            result = builder.bitcast(source_value, llvm_target_type)
        
        return result


class SizeOfTypeHandler:
    """
    Type-only handling for sizeof().
    Returns size in BITS or None if it cannot be determined at compile time.
    """

    @staticmethod
    def bits_from_llvm_type(llvm_type: ir.Type, module: ir.Module) -> Optional[int]:
        # Integers
        if isinstance(llvm_type, ir.IntType):
            return llvm_type.width

        # Floats
        if isinstance(llvm_type, ir.FloatType):
            return 32
        if isinstance(llvm_type, ir.DoubleType):
            return 64

        # Arrays
        if isinstance(llvm_type, ir.ArrayType):
            elem_bits = SizeOfTypeHandler.bits_from_llvm_type(
                llvm_type.element, module
            )
            if elem_bits is None:
                return module.data_layout.get_type_size(llvm_type) * 8
            return elem_bits * llvm_type.count

        # Pointers (Flux assumption)
        if isinstance(llvm_type, ir.PointerType):
            return 64

        # Structs (literal or identified)
        if isinstance(llvm_type, ir.LiteralStructType) or hasattr(llvm_type, "elements"):
            elements = getattr(llvm_type, "elements", None)
            if elements is None:
                return module.data_layout.get_type_size(llvm_type) * 8

            total = 0
            for el in elements:
                el_bits = SizeOfTypeHandler.bits_from_llvm_type(el, module)
                if el_bits is None:
                    total += module.data_layout.get_type_size(el) * 8
                else:
                    total += el_bits
            return total

        # Fallback to data layout if LLVM knows
        try:
            return module.data_layout.get_type_size(llvm_type) * 8
        except Exception:
            return None

    @staticmethod
    def sizeof_bits_for_target(target, builder, module) -> Optional[int]:
        """
        Resolve sizeof(target) using TYPE INFORMATION ONLY.
        No IR emission, no value loading.
        """
        from fast import Identifier

        # sizeof(TypeSystem)
        if isinstance(target, TypeSystem):
            llvm_type = target.get_llvm_type_with_array(module)
            return SizeOfTypeHandler.bits_from_llvm_type(llvm_type, module)

        # sizeof(identifier)
        if isinstance(target, Identifier):
            # Struct type name
            if hasattr(module, "_struct_vtables") and target.name in module._struct_vtables:
                return module._struct_vtables[target.name].total_bits

            # Preferred path: type system info
            ts = IdentifierTypeHandler.get_type_spec(target.name, builder, module)
            if ts is not None:
                llvm_type = ts.get_llvm_type_with_array(module)
                return SizeOfTypeHandler.bits_from_llvm_type(llvm_type, module)

            # Fallback: derive from existing LLVM storage
            if module.symbol_table.get_llvm_value(target.name) is not None:
                ptr = module.symbol_table.get_llvm_value(target.name)
                if isinstance(ptr.type, ir.PointerType):
                    return SizeOfTypeHandler.bits_from_llvm_type(ptr.type.pointee, module)

            if target.name in module.globals:
                gvar = module.globals[target.name]
                if isinstance(gvar.type, ir.PointerType):
                    return SizeOfTypeHandler.bits_from_llvm_type(gvar.type.pointee, module)

            return None

        return None


class AlignOfTypeHandler:
    """
    Type-only handling for alignof().
    Returns alignment in BYTES or None if it cannot be determined at compile time.
    """

    @staticmethod
    def alignment_from_llvm_type(llvm_type: ir.Type, module: ir.Module) -> Optional[int]:
        try:
            return module.data_layout.preferred_alignment(llvm_type)
        except Exception:
            return None

    @staticmethod
    def alignment_bytes_for_type_spec(type_spec: 'TypeSystem', module: ir.Module) -> int:
        # Explicit alignment wins
        if type_spec.alignment is not None:
            return type_spec.alignment

        # Flux special-case: data{bits} defaults to width alignment (in bytes)
        if type_spec.base_type == DataType.DATA and type_spec.bit_width is not None:
            return (type_spec.bit_width + 7) // 8

        # Default: platform preferred alignment for the LLVM type
        llvm_type = type_spec.get_llvm_type(module)
        return module.data_layout.preferred_alignment(llvm_type)

    @staticmethod
    def alignof_bytes_for_target(target, builder, module) -> Optional[int]:
        """
        Resolve alignof(target) using type information only.
        No IR emission, no value loading.
        """
        from fast import Identifier

        # alignof(TypeSystem)
        if isinstance(target, TypeSystem):
            return AlignOfTypeHandler.alignment_bytes_for_type_spec(target, module)

        # alignof(identifier) using stored type info first
        if isinstance(target, Identifier):
            # If the identifier names a struct type, use vtable info if it exists
            if hasattr(module, "_struct_vtables") and target.name in module._struct_vtables:
                vt = module._struct_vtables[target.name]
                if hasattr(vt, "alignment_bytes"):
                    return vt.alignment_bytes
                if hasattr(vt, "alignment"):
                    return vt.alignment

            ts = IdentifierTypeHandler.get_type_spec(target.name, builder, module)
            if ts is not None:
                return AlignOfTypeHandler.alignment_bytes_for_type_spec(ts, module)

            # Fallback: derive from existing LLVM storage (scope/globals)
            if module.symbol_table.get_llvm_value(target.name) is not None:
                ptr = module.symbol_table.get_llvm_value(target.name)
                if isinstance(ptr.type, ir.PointerType):
                    return AlignOfTypeHandler.alignment_from_llvm_type(ptr.type.pointee, module)

            if target.name in module.globals:
                gvar = module.globals[target.name]
                if isinstance(gvar.type, ir.PointerType):
                    return AlignOfTypeHandler.alignment_from_llvm_type(gvar.type.pointee, module)

            return None

        # Some callsites may accidentally pass a decl node; support it without importing AST classes.
        if hasattr(target, "type_spec") and isinstance(getattr(target, "type_spec"), TypeSystem):
            return AlignOfTypeHandler.alignment_bytes_for_type_spec(target.type_spec, module)

        return None