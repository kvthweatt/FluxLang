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
	# Fixed-width integer types
	# These are to be defined in `types.fx`
	#UINT8 = "uint8"
	#UINT16 = "uint16"
	#UINT32 = "uint32"
	#UINT64 = "uint64"
	#INT8 = "int8"
	#INT16 = "int16"
	#INT32 = "int32"
	#INT64 = "int64"

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
		# Fixed-width integer types
#		elif self.type == DataType.UINT8:
#			return ir.Constant(ir.IntType(8), int(self.value) if isinstance(self.value, str) else self.value)
#		elif self.type == DataType.UINT16:
#			return ir.Constant(ir.IntType(16), int(self.value) if isinstance(self.value, str) else self.value)
#		elif self.type == DataType.UINT32:
#			return ir.Constant(ir.IntType(32), int(self.value) if isinstance(self.value, str) else self.value)
#		elif self.type == DataType.UINT64:
#			return ir.Constant(ir.IntType(64), int(self.value) if isinstance(self.value, str) else self.value)
#		elif self.type == DataType.INT8:
#			return ir.Constant(ir.IntType(8), int(self.value) if isinstance(self.value, str) else self.value)
#		elif self.type == DataType.INT16:
#			return ir.Constant(ir.IntType(16), int(self.value) if isinstance(self.value, str) else self.value)
#		elif self.type == DataType.INT32:
#			return ir.Constant(ir.IntType(32), int(self.value) if isinstance(self.value, str) else self.value)
#		elif self.type == DataType.INT64:
#			return ir.Constant(ir.IntType(64), int(self.value) if isinstance(self.value, str) else self.value)
#		elif self.type == DataType.DATA:
			# Handle array literals
			if isinstance(self.value, list):
				# For now, just return None for array literals - they should be handled at a higher level
				return None
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

@dataclass
class Identifier(ASTNode):
	name: str

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		# Look up the name in the current scope
		if builder.scope is not None and self.name in builder.scope:
			ptr = builder.scope[self.name]
			# Load the value if it's a pointer type
			if isinstance(ptr.type, ir.PointerType):
				return builder.load(ptr, name=self.name)
			return ptr
		
		# Check for global variables - need to load their value
		if self.name in module.globals:
			gvar = module.globals[self.name]
			if isinstance(gvar.type, ir.PointerType):
				return builder.load(gvar, name=self.name)
			return gvar
		
		# Check if this is a custom type
		if hasattr(module, '_type_aliases') and self.name in module._type_aliases:
			return module._type_aliases[self.name]
			
		raise NameError(f"Unknown identifier: {self.name}")

# Type definitions
@dataclass
class TypeSpec(ASTNode):
	base_type: DataType
	is_signed: bool = True
	is_const: bool = False
	is_volatile: bool = False
	bit_width: Optional[int] = None
	alignment: Optional[int] = None
	is_array: bool = False
	array_size: Optional[int] = None
	is_pointer: bool = False


	def get_llvm_type(self, module: ir.Module) -> ir.Type:  # Renamed from get_llvm_type
		if hasattr(module, '_union_types') and self.base_type in module._union_types:
			return module._union_types[self.base_type]
		if isinstance(self.base_type, str):
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
			return ir.IntType(self.bit_width)
		# Fixed-width integer types
#		elif self.base_type == DataType.UINT8:
#			return ir.IntType(8)
#		elif self.base_type == DataType.UINT16:
#			return ir.IntType(16)
#		elif self.base_type == DataType.UINT32:
#			return ir.IntType(32)
#		elif self.base_type == DataType.UINT64:
#			return ir.IntType(64)
#		elif self.base_type == DataType.INT8:
#			return ir.IntType(8)
#		elif self.base_type == DataType.INT16:
#			return ir.IntType(16)
#		elif self.base_type == DataType.INT32:
#			return ir.IntType(32)
#		elif self.base_type == DataType.INT64:
#			return ir.IntType(64)
		else:
			raise ValueError(f"Unsupported type: {self.base_type}")
	
	def get_llvm_type_with_array(self, module: ir.Module) -> ir.Type:
		"""Get LLVM type with array support"""
		base_type = self.get_llvm_type(module)
		
		if self.is_array and self.array_size:
			return ir.ArrayType(base_type, self.array_size)
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
			return builder.not_(operand_val)
		elif self.operator == Operator.SUB:
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

@dataclass
class FunctionCall(Expression):
	name: str
	arguments: List[Expression] = field(default_factory=list)

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		# Look up the function in the module
		func = module.globals.get(self.name, None)
		if func is None or not isinstance(func, ir.Function):
			raise NameError(f"Unknown function: {self.name}")
		
		# Generate code for arguments
		arg_vals = [arg.codegen(builder, module) for arg in self.arguments]
		return builder.call(func, arg_vals)

@dataclass
class MemberAccess(Expression):
	object: Expression
	member: str

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		# Handle static struct member access (A.x where A is a struct type)
		if isinstance(self.object, Identifier):
			struct_name = self.object.name
			if hasattr(module, '_struct_types') and struct_name in module._struct_types:
				# Look for the global variable representing this member
				global_name = f"{struct_name}.{self.member}"
				for global_var in module.global_values:
					if global_var.name == global_name:
						return builder.load(global_var)
				
				raise NameError(f"Static member '{self.member}' not found in struct '{struct_name}'")
		
		# Handle regular member access (obj.x where obj is an instance)
		obj_val = self.object.codegen(builder, module)
		
		if isinstance(obj_val.type, ir.PointerType):
			# Handle pointer to struct
			if isinstance(obj_val.type.pointee, ir.LiteralStructType):
				struct_type = obj_val.type.pointee
				if not hasattr(struct_type, 'names'):
					raise ValueError("Struct type missing member names")
				
				try:
					member_index = struct_type.names.index(self.member)
				except ValueError:
					raise ValueError(f"Member '{self.member}' not found in struct")
				
				member_ptr = builder.gep(
					obj_val,
					[ir.Constant(ir.IntType(32)), 0],
					[ir.Constant(ir.IntType(32)), member_index],
					inbounds=True
				)
				return builder.load(member_ptr)
		
		raise ValueError(f"Member access on unsupported type: {obj_val.type}")

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

@dataclass
class AddressOf(Expression):
	expression: Expression

@dataclass
class AlignOf(Expression):
	target: Union[TypeSpec, Expression]

@dataclass
class SizeOf(Expression):
	target: Union[TypeSpec, Expression]

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		"""Generate LLVM IR that returns size in BITS"""
		# Handle TypeSpec case (like sizeof(data{8}[]))
		if isinstance(self.target, TypeSpec):
			llvm_type = self.target.get_llvm_type_with_array(module)
			
			# Calculate size in BITS
			if isinstance(llvm_type, ir.IntType):
				return ir.Constant(ir.IntType(64), llvm_type.width)  # Already in bits
			elif isinstance(llvm_type, ir.ArrayType):
				element_bits = llvm_type.element.width if hasattr(llvm_type.element, 'width') else 8
				return ir.Constant(ir.IntType(64), element_bits * llvm_type.count)
			elif isinstance(llvm_type, ir.PointerType):
				return ir.Constant(ir.IntType(64), 64)  # 64-bit pointers = 64 bits
			else:
				return ir.Constant(ir.IntType(64), 0)  # Unknown type
		
		# Handle Expression case (like sizeof(variable))
		target_val = self.target.codegen(builder, module)
		val_type = target_val.type
		
		# Pointer types (arrays decay to pointers)
		if isinstance(val_type, ir.PointerType):
			if isinstance(val_type.pointee, ir.ArrayType):
				arr_type = val_type.pointee
				element_bits = arr_type.element.width if hasattr(arr_type.element, 'width') else 8
				return ir.Constant(ir.IntType(64), element_bits * arr_type.count)
			return ir.Constant(ir.IntType(64), 64)  # Pointer size
		
		# Direct types
		if hasattr(val_type, 'width'):
			return ir.Constant(ir.IntType(64), val_type.width)  # Already in bits
		return ir.Constant(ir.IntType(64), 0)  # Fallback

# Variable declarations
@dataclass
class VariableDeclaration(ASTNode):
	name: str
	type_spec: TypeSpec
	initial_value: Optional[Expression] = None

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		llvm_type = self.type_spec.get_llvm_type_with_array(module)
		
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
			init_val = self.initial_value.codegen(builder, module)
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
		llvm_type = self.base_type.get_llvm_type(module)
		
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
			# Struct/object member assignment
			obj = self.target.object.codegen(builder, module)
			member_name = self.target.member
			
			if isinstance(obj.type, ir.PointerType) and isinstance(obj.type.pointee, ir.LiteralStructType):
				struct_type = obj.type.pointee
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

@dataclass
class Block(Statement):
	statements: List[Statement] = field(default_factory=list)

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		result = None
		for stmt in self.statements:
			result = stmt.codegen(builder, module)
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

@dataclass
class ForInLoop(Statement):
	variables: List[str]
	iterable: Expression
	body: Block

@dataclass
class ReturnStatement(Statement):
	value: Optional[Expression] = None

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		if self.value is not None:
			ret_val = self.value.codegen(builder, module)
			# Ensure we're not returning a pointer
			if isinstance(ret_val.type, ir.PointerType):
				ret_val = builder.load(ret_val)
			builder.ret(ret_val)
		else:
			builder.ret_void()
		return None

@dataclass
class BreakStatement(Statement):
	pass

@dataclass
class ContinueStatement(Statement):
	pass

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
	catch_blocks: List[tuple] = field(default_factory=list)  # (exception_type, exception_name, body) tuples

@dataclass
class ThrowStatement(Statement):
	expression: Expression

@dataclass
class AssertStatement(Statement):
	condition: Expression
	message: Optional[str] = None

# Function parameter
@dataclass
class Parameter(ASTNode):
	name: str
	type_spec: TypeSpec

@dataclass
class InlineAsm(Expression):
	"""Represents inline assembly block"""
	body: str  # The raw assembly code
	is_volatile: bool = False  # New flag for volatile assembly

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
		ret_type = self._convert_type(self.return_type)
		
		# Convert parameter types
		param_types = [self._convert_type(param.type_spec) for param in self.parameters]
		
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
		
		# Allocate space for parameters and store initial values
		for i, param in enumerate(func.args):
			alloca = builder.alloca(param.type, name=f"{param.name}.addr")
			builder.store(param, alloca)
			builder.scope[self.parameters[i].name] = alloca
		
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
		return func
	
	def _convert_type(self, type_spec: TypeSpec) -> ir.Type:
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
			return ir.IntType(type_spec.bit_width or 8)
		else:
			raise ValueError(f"Unsupported type: {type_spec.base_type}")

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
		# First create a struct type for the object's data members
		member_types = []
		member_names = []
		
		for member in self.members:
			member_type = self._convert_type(member.type_spec, module)
			member_types.append(member_type)
			member_names.append(member.name)
		
		# Create the struct type for data members
		struct_type = ir.LiteralStructType(member_types)
		struct_type.names = member_names
		
		# Store the struct type in the module
		if not hasattr(module, '_struct_types'):
			module._struct_types = {}
		module._struct_types[self.name] = struct_type
		
		# Create methods as functions with 'this' parameter
		for method in self.methods:
			# Convert return type
			ret_type = self._convert_type(method.return_type, module)
			
			# Create parameter types - first parameter is always 'this' pointer
			param_types = [ir.PointerType(struct_type)]
			
			# Add other parameters
			param_types.extend([self._convert_type(param.type_spec, module) for param in method.parameters])
			
			# Create function type
			func_type = ir.FunctionType(ret_type, param_types)
			
			# Create function with mangled name
			func_name = f"{self.name}__{method.name}"
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
				Path.cwd() / "lib",
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

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		# Delegate codegen to the contained FunctionDef
		return self.function_def.codegen(builder, module)

# Struct definition statement
@dataclass
class StructDefStatement(Statement):
	struct_def: StructDef

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		# Delegate codegen to the contained StructDef
		return self.struct_def.codegen(builder, module)

# Object definition statement
@dataclass
class ObjectDefStatement(Statement):
	object_def: ObjectDef

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		return self.object_def.codegen(builder, module)

# Namespace definition statement
@dataclass
class NamespaceDefStatement(Statement):
	namespace_def: NamespaceDef

	def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Value:
		return self.namespace_def.codegen(builder, module)

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