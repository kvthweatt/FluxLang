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
			# Check if we have a custom type for this width
			if hasattr(module, '_type_aliases'):
				for name, llvm_type in module._type_aliases.items():
					if isinstance(llvm_type, ir.IntType) and llvm_type.width == 64 and name.startswith('i'):
						return ir.Constant(llvm_type, int(self.value) if isinstance(self.value, str) else self.value)
			return ir.Constant(ir.IntType(32), int(self.value) if isinstance(self.value, str) else self.value)
		elif self.type == DataType.FLOAT:
			return ir.Constant(ir.FloatType(), float(self.value))
		elif self.type == DataType.BOOL:
			return ir.Constant(ir.IntType(1), bool(self.value))
		elif self.type == DataType.CHAR:
			return ir.Constant(ir.IntType(8), ord(self.value[0]) if isinstance(self.value, str) else self.value)
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
				# Ensure we're not returning a pointer
				if isinstance(ret_val.type, ir.PointerType) and not self.name == 'this':
					ret_val = builder.load(ret_val)
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
				return builder.load(gvar, name=self.name)
			return gvar
		
		# Check if this is a custom type
		if hasattr(module, '_type_aliases') and self.name in module._type_aliases:
			return module._type_aliases[self.name]
			
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
			# Check for struct types first
			if hasattr(module, '_struct_types') and self.base_type in module._struct_types:
				return module._struct_types[self.base_type]
			# Check for union types
			if hasattr(module, '_union_types') and self.base_type in module._union_types:
				return module._union_types[self.base_type]
			# Handle custom types (like i64)
			if hasattr(module, '_type_aliases') and self.base_type in module._type_aliases:
				return module._type_aliases[self.base_type]
			return ir.IntType(32)  # Default fallback
		
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

@dataclass
class BinaryOp(Expression):
	left: Expression
	operator: Operator
	right: Expression


	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		left_val = self.left.codegen(builder, module)
		right_val = self.right.codegen(builder, module)
		
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

@dataclass
class UnaryOp(Expression):
	operator: Operator
	operand: Expression
	is_postfix: bool = False

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
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
			one = ir.Constant(operand_val.type, 1)
			new_val = builder.add(operand_val, one)
			if isinstance(self.operand, Identifier):
				builder.scope[self.operand.name] = new_val
			return new_val if not self.is_postfix else operand_val
		elif self.operator == Operator.DECREMENT:
			# Handle both prefix and postfix decrement
			one = ir.Constant(operand_val.type, 1)
			new_val = builder.sub(operand_val, one)
			if isinstance(self.operand, Identifier):
				builder.scope[self.operand.name] = new_val
			return new_val if not self.is_postfix else operand_val
		else:
			raise ValueError(f"Unsupported unary operator: {self.operator}")

@dataclass
class CastExpression(Expression):
	target_type: TypeSpec
	expression: Expression

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		"""Generate code for cast expressions, including zero-cost struct reinterpretation"""
		source_val = self.expression.codegen(builder, module)
		target_llvm_type = self.target_type.get_llvm_type(module)
		
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
		
		# Handle pointer casts
		elif isinstance(source_val.type, ir.PointerType) and isinstance(target_llvm_type, ir.PointerType):
			return builder.bitcast(source_val, target_llvm_type)
		
		else:
			raise ValueError(f"Unsupported cast from {source_val.type} to {target_llvm_type}")

@dataclass
class FunctionCall(Expression):
	name: str
	arguments: List[Expression] = field(default_factory=list)

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		# Look up the function in the module
		func = module.globals.get(self.name, None)
		if func is None or not isinstance(func, ir.Function):
			raise NameError(f"Unknown function: {self.name}")
		
		print(f"DEBUG FunctionCall: Calling {self.name} with {len(self.arguments)} arguments")
		print(f"DEBUG FunctionCall: Function signature: {func.type}")
		
		# Generate code for arguments
		arg_vals = []
		for i, arg in enumerate(self.arguments):
			arg_val = arg.codegen(builder, module)
			print(f"DEBUG FunctionCall: arg[{i}] original type: {arg_val.type}")
			
			# Handle array-to-pointer decay for function arguments
			if isinstance(arg_val.type, ir.PointerType) and isinstance(arg_val.type.pointee, ir.ArrayType):
				print(f"DEBUG FunctionCall: arg[{i}] is pointer to array type")
				# Check if function parameter expects a pointer to the element type
				if i < len(func.args):
					param_type = func.args[i].type
					array_element_type = arg_val.type.pointee.element
					print(f"DEBUG FunctionCall: param type: {param_type}, array element: {array_element_type}")
					if isinstance(param_type, ir.PointerType) and param_type.pointee == array_element_type:
						print(f"DEBUG FunctionCall: Converting array to pointer")
						# Convert array to pointer by GEP to first element
						zero = ir.Constant(ir.IntType(32), 0)
						array_ptr = builder.gep(arg_val, [zero, zero], name="array_decay")
						arg_val = array_ptr
						print(f"DEBUG FunctionCall: arg[{i}] after decay: {arg_val.type}")
			
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
		
		if isinstance(obj_val.type, ir.PointerType):
			# Handle pointer to struct
			if isinstance(obj_val.type.pointee, ir.LiteralStructType):
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
				
				try:
					member_index = struct_type.names.index(self.member)
				except ValueError:
					raise ValueError(f"Member '{self.member}' not found in struct")
				
				member_ptr = builder.gep(
					obj_val,
					[ir.Constant(ir.IntType(32), 0)],
					[ir.Constant(ir.IntType(32), member_index)],
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
		else:
			raise ValueError(f"Cannot access array element for type: {array_val.type}")

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
		# Generate code for the target expression
		target = self.expression.codegen(builder, module)
		
		# Special case: If the target is a variable declaration, we need to ensure it's allocated first
		if isinstance(self.expression, Identifier):
			var_name = self.expression.name
			
			# Check if it's a local variable
			if builder.scope is not None and var_name in builder.scope:
				return builder.scope[var_name]
			
			# Check if it's a global variable
			if var_name in module.globals:
				return module.globals[var_name]
			
			# If we get here, the variable hasn't been declared yet
			raise NameError(f"Unknown variable: {var_name}")
		
		# Handle member access
		elif isinstance(self.expression, MemberAccess):
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
							 bytearray(type_name.encode('utf-8')))
		
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
		print(f"DEBUG SizeOf: target type = {type(self.target).__name__}, target = {self.target}")
		# Handle TypeSpec case (like sizeof(data{8}[]))
		if isinstance(self.target, TypeSpec):
			print(f"DEBUG SizeOf: Taking TypeSpec path")
			llvm_type = self.target.get_llvm_type_with_array(module)
			
			# Calculate size in BITS
			if isinstance(llvm_type, ir.IntType):
				return ir.Constant(ir.IntType(32), llvm_type.width)  # Already in bits
			elif isinstance(llvm_type, ir.ArrayType):
				element_bits = llvm_type.element.width
				return ir.Constant(ir.IntType(32), element_bits * llvm_type.count)
			elif isinstance(llvm_type, ir.PointerType):
				return ir.Constant(ir.IntType(32), 64)  # 64-bit pointers = 64 bits
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
						return ir.Constant(ir.IntType(32), llvm_type.width)
					elif isinstance(llvm_type, ir.ArrayType):
						element_bits = llvm_type.element.width
						return ir.Constant(ir.IntType(32), element_bits * llvm_type.count)
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
				return ir.Constant(ir.IntType(64), element_bits * arr_type.count)
			return ir.Constant(ir.IntType(64), 64)  # Pointer size
		
		# Direct types
		if hasattr(val_type, 'width'):
			return ir.Constant(ir.IntType(64), val_type.width)  # Already in bits
		raise ValueError(f"Cannot determine size of type: {val_type}")

# Variable declarations
@dataclass
class VariableDeclaration(ASTNode):
	name: str
	type_spec: TypeSpec
	initial_value: Optional[Expression] = None

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		print(f"DEBUG VariableDeclaration: name={self.name}, type_spec.base_type={self.type_spec.base_type}")
		print(f"DEBUG VariableDeclaration: module has _union_types: {hasattr(module, '_union_types')}")
		if hasattr(module, '_union_types'):
			print(f"DEBUG VariableDeclaration: _union_types keys: {list(module._union_types.keys())}")
		llvm_type = self.type_spec.get_llvm_type_with_array(module)
		print(f"DEBUG VariableDeclaration: resolved llvm_type = {llvm_type}")
		
		# Handle global variables
		if builder.scope is None:
			# Check if global already exists
			if self.name in module.globals:
				return module.globals[self.name]
				
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
				if isinstance(llvm_type, ir.ArrayType) and isinstance(llvm_type.element, ir.IntType) and llvm_type.element.width == 8:
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
						
				elif isinstance(llvm_type, ir.PointerType):
					# Create global string constant for pointer types
					str_val = ir.Constant(ir.ArrayType(ir.IntType(8)), bytearray(self.initial_value.value.encode('utf-8') + b'\0'))
					gv = ir.GlobalVariable(module, str_val.type, name=f".str.{self.name}")
					gv.linkage = 'internal'
					gv.global_constant = True
					gv.initializer = str_val
					
					# Get pointer to the string
					zero = ir.Constant(ir.IntType(32), 0)
					str_ptr = builder.gep(gv, [zero, zero], name=f"{self.name}.ptr")
					builder.store(str_ptr, alloca)
				else:
					# For non-pointer, non-array data types, just store the first character
					char_val = ir.Constant(ir.IntType(8), ord(self.initial_value.value[0]))
					builder.store(char_val, alloca)
			elif isinstance(self.initial_value, FunctionCall) and self.initial_value.name.endswith('.__init'):
				# This is an object constructor call
				# We need to call the constructor with 'this' pointer as first argument
				constructor_func = module.globals.get(self.initial_value.name)
				if constructor_func is None:
					raise NameError(f"Constructor not found: {self.initial_value.name}")
				
				# Call constructor with 'this' pointer (alloca) as first argument
				args = [alloca]  # 'this' pointer
				# Add any additional constructor arguments
				for arg_expr in self.initial_value.arguments:
					args.append(arg_expr.codegen(builder, module))
				
				# Call the constructor
				init_val = builder.call(constructor_func, args)
				# Note: For constructors that return 'this', init_val will be the initialized object pointer
				# But since we already have the object in alloca, we don't need to store init_val
			else:
				# Regular initialization for non-string literals
				init_val = self.initial_value.codegen(builder, module)
				if init_val is not None:
					# Cast init value to match variable type if needed
					if init_val.type != llvm_type:
						# Handle pointer type compatibility (for AddressOf expressions)
						if isinstance(llvm_type, ir.PointerType) and isinstance(init_val.type, ir.PointerType):
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
		llvm_type = self.base_type.get_llvm_type_with_array(module)
		
		if not hasattr(module, '_type_aliases'):
			module._type_aliases = {}
		module._type_aliases[self.name] = llvm_type
		
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
			
			builder.store(val, ptr)
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
			
			print(f"DEBUG Assignment: obj.type = {obj.type}, pointee = {getattr(obj.type, 'pointee', None)}")
			print(f"DEBUG Assignment: member_name = {member_name}")
			if hasattr(module, '_union_types'):
				print(f"DEBUG Assignment: Union types available: {list(module._union_types.keys())}")
				for union_name, union_type in module._union_types.items():
					print(f"DEBUG Assignment: Union {union_name} type: {union_type}")
			
			if isinstance(obj.type, ir.PointerType) and isinstance(obj.type.pointee, ir.LiteralStructType):
				struct_type = obj.type.pointee
				
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
			
			raise ValueError(f"Cannot assign to member '{member_name}' of non-struct type")
	
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
class Block(Statement):
	statements: List[Statement] = field(default_factory=list)

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		result = None
		print(f"DEBUG Block: Processing {len(self.statements)} statements")
		for i, stmt in enumerate(self.statements):
			print(f"DEBUG Block: Processing statement {i}: {type(stmt).__name__}")
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
				builder.ret(ret_val)
		else:
			builder.ret_void()
		return None

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
		# For bare-metal systems programming, we'll use setjmp/longjmp style
		# No C++ RTTI nonsense, no hidden runtime functions
		
		# Create basic blocks
		func = builder.block.function
		try_block = func.append_basic_block('try')
		end_block = func.append_basic_block('try.end')
		
		# Set up jump buffer (simplified)
		jmpbuf = builder.alloca(ir.ArrayType(ir.IntType(32), 6), name='jmpbuf')
		
		# Mock setjmp
		setjmp = builder.call(
			module.declare_intrinsic('llvm.eh.sjlj.setjmp'),
			[builder.bitcast(jmpbuf, ir.PointerType(ir.IntType(8)))],
			name='setjmp'
		)
		
		# Branch based on setjmp result
		builder.cbranch(
			builder.icmp_unsigned('==', setjmp, ir.Constant(ir.IntType(32), 0)),
			try_block,
			end_block
		)
		
		# TRY block
		builder.position_at_start(try_block)
		self.try_body.codegen(builder, module)
		if not builder.block.is_terminated:
			builder.branch(end_block)
			
		# CATCH blocks would be implemented via longjmp targets
		# Flux would handle this at the callsite of throw:
		# 1. Check handler registry
		# 2. Restore registers
		# 3. Branch to handler
		
		builder.position_at_start(end_block)
		return None

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
			msg_bytes = msg_str.encode('utf-8')
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
            print(f"DEBUG: Parsing constraints: {self.constraints}")
            constraint_parts = self.constraints.split(':')
            print(f"DEBUG: Split into parts: {constraint_parts}")
            
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
            print(f"DEBUG: Input part: '{input_part}'")
            if input_part:
                # Parse input operands like '"r"(stdout_handle), "r"(message), "m"(bytes_written)'
                import re
                input_matches = re.findall(r'"([^"]+)"\s*\(([^)]+)\)', input_part)
                print(f"DEBUG: Input matches: {input_matches}")
                for constraint, var_name in input_matches:
                    print(f"DEBUG: Looking for variable '{var_name}' with constraint '{constraint}'")
                    # Look up the variable
                    if builder.scope and var_name in builder.scope:
                        var_ptr = builder.scope[var_name]
                        # For arrays or memory constraints, pass the pointer; for register constraints, load the value
                        if constraint in ['m'] or (isinstance(var_ptr.type, ir.PointerType) and isinstance(var_ptr.type.pointee, ir.ArrayType)):
                            input_operands.append(var_ptr)
                            print(f"DEBUG: Found in scope, using pointer: {var_ptr}")
                        else:
                            var_val = builder.load(var_ptr, name=f"{var_name}_load")
                            input_operands.append(var_val)
                            print(f"DEBUG: Found in scope, loaded value: {var_val}")
                        input_constraints.append(constraint)
                    elif var_name in module.globals:
                        var_ptr = module.globals[var_name]
                        # For arrays or memory constraints, pass the pointer; for register constraints, load the value
                        if constraint in ['m'] or isinstance(var_ptr.type.pointee, ir.ArrayType):
                            input_operands.append(var_ptr)
                            print(f"DEBUG: Found in globals, using pointer: {var_ptr}")
                        else:
                            var_val = builder.load(var_ptr, name=f"{var_name}_load")
                            input_operands.append(var_val)
                            print(f"DEBUG: Found in globals, loaded value: {var_val}")
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
        
        print(f"DEBUG: output_constraints = {output_constraints}")
        print(f"DEBUG: input_constraints = {input_constraints}")
        print(f"DEBUG: clobber_list = {clobber_list}")
        
        # Only input operands are passed as parameters
        print(f"DEBUG: input_operands = {input_operands}")
        print(f"DEBUG: output_operands = {output_operands}")
        
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
        
        print(f"DEBUG: final constraint_str = '{constraint_str}'")
        print(f"DEBUG: final_input_operands = {final_input_operands}")
        
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
		
		# Create function
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
		print(f"DEBUG FunctionDef: Generating body for {self.name}")
		print(f"DEBUG FunctionDef: Body has {len(self.body.statements)} statements")
		for i, stmt in enumerate(self.body.statements):
			print(f"DEBUG FunctionDef: Statement {i}: {type(stmt).__name__} = {stmt}")
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
		# Convert member types
		member_types = []
		member_names = []
		for member in self.members:
			member_type = self._convert_type(member.type_spec, module)
			member_types.append(member_type)
			member_names.append(member.name)
		
		# Create the struct type
		struct_type = ir.LiteralStructType(member_types)
		struct_type.names = member_names
		
		# Store the type in the module's context
		if not hasattr(module, '_struct_types'):
			module._struct_types = {}
		module._struct_types[self.name] = struct_type
		
		# Create global variables for initialized members
		for member in self.members:
			if member.initial_value is not None:  # Check for initial_value here
				# Create global variable for initialized members
				gvar = ir.GlobalVariable(
					module, 
					member_type, 
					f"{self.name}.{member.name}"
				)
				gvar.initializer = member.initial_value.codegen(builder, module)
				gvar.linkage = 'internal'
		
		return struct_type
	
	def _convert_type(self, type_spec: TypeSpec, module: ir.Module) -> ir.Type:
		if isinstance(type_spec.base_type, str):
			# Check if it's a struct type
			if hasattr(module, '_struct_types') and type_spec.base_type in module._struct_types:
				return module._struct_types[type_spec.base_type]
			# Check if it's a type alias
			if hasattr(module, '_type_aliases') and type_spec.base_type in module._type_aliases:
				return module._type_aliases[type_spec.base_type]
			# Default to i32
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
				alloca = method_builder.alloca(param.type, name=f"{param.name}.addr")
				method_builder.store(param, alloca)
				if i == 0:  # 'this' pointer
					method_builder.scope["this"] = alloca
				else:
					method_builder.scope[method.parameters[i-1].name] = alloca
			
			# Generate method body
			if isinstance(method, FunctionDef):
				# For __init__, return 'this' pointer directly
				if method.name == '__init':
					method_builder.ret(func.args[0])
				else:
					# For other methods, generate normal body
					method.body.codegen(method_builder, module)
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
		if isinstance(type_spec.base_type, str):
			# Check if it's a struct type
			if hasattr(module, '_struct_types') and type_spec.base_type in module._struct_types:
				return module._struct_types[type_spec.base_type]
			# Check if it's a type alias
			if hasattr(module, '_type_aliases') and type_spec.base_type in module._type_aliases:
				return module._type_aliases[type_spec.base_type]
			# Default to i32
			return ir.IntType(32)
		
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
		
		# Save the current module state
		old_module = module
		
		# Create a new module for the namespace if we want isolation
		# Alternatively, we can just mangle names in the existing module
		# For now, we'll use name mangling in the existing module
		
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
		
		return None

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