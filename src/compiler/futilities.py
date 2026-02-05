#!/usr/bin/env python3
"""
Flux AST Utilities Module

Helper and utility functions extracted from the Flux AST.
These functions provide common operations for type conversion,
type inference, name mangling, constant evaluation, and more.

Copyright (C) 2026 Karac Thweatt

Contributors:
    Piotr Bednarski
"""

from typing import Any, Optional, List, Dict, Tuple
from enum import Enum
from llvmlite import ir

from ftypesys import DataType

# ============================================================================
# Type System Utilities
# ============================================================================


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