# Complete Plan to Fix Flux Structs (With Destructive Casting)

## The Problem

**Current behavior**: Structs use C-style pointers and global string constants

**Required behavior**: Structs are memory ownership containers that store all data inline

---

## CRITICAL: Flux Struct Semantics (Different from ALL other languages)

### Struct Definitions vs Instances

**Struct Definition** = Blueprint/Template (pointer collection describing layout)
```flux
struct Header {
    unsigned data{16} sig;
    unsigned data{32} filesize, reserved, dataoffset;
}
```
- This is NOT actual memory
- It's a specification for what instances should contain
- Members describe types and order, not storage

**Struct Instance** = Actual Memory Container (owns the data)
```flux
Header h = (Header)buffer[0:13];
```
- This IS actual memory
- Data is MOVED/CONSUMED from source into instance
- Instance OWNS this memory

---

## Destructive Casting: The Core Innovation

### Traditional C-style Casting (NOT Flux)
```c
// C/C++ - non-destructive, interprets bytes in-place
Header* h = (Header*)&buffer[0];  // Just reinterpret pointer
// buffer still owns the data, h is just a view
```

### Flux Casting (Actual Behavior)
```flux
// Flux - destructive, transfers ownership
Header h = (Header)buffer[0:13];  // CONSUMES bytes from buffer
// buffer loses those bytes, h now owns them
// buffer is dynamically resized, those bytes are GONE
```

**Key principle**: Two things cannot occupy the same memory at the same time.

### Sequential Consumption Example
```flux
byte[100] buffer = readfile();

// First cast - consume bytes 0-13 from buffer
Header h = (Header)buffer[0:13];
// buffer is now smaller, missing first 14 bytes

// Second cast - starts at NEW buffer[0] (old buffer[14])
InfoHeader ih = (InfoHeader)buffer[0:39];
// buffer is now even smaller

// This is why both start at buffer[0] - destructive consumption
```

---

## Memory Ownership Model

### Rules:
1. **Struct instances OWN their data** - data lives inside the struct, not referenced
2. **Casting TRANSFERS ownership** - source loses bytes, destination gains them
3. **No sharing** - once cast to struct, original source can't access those bytes
4. **Dynamic resizing** - sources shrink when data is consumed

### Why This Matters - Memory Safety:

**Traditional C/C++ memory safety nightmare:**
```c
char* buffer = malloc(1000);
Header* h = (Header*)buffer;  // h points INTO buffer
free(buffer);                  // Oops, h is now dangling
// h->sig is now undefined behavior - use after free!
```

**Flux eliminates this entire class of bugs:**
```flux
byte[1000] buffer = readfile();
Header h = (Header)buffer[0:13];  // h OWNS the data now
(void)buffer;                      // Free buffer
// h.sig is still valid! It owns that memory independently
```

Because struct instances are **memory containers** that **own their data**, not pointers to someone else's data:
- ✅ No use-after-free
- ✅ No dangling pointers
- ✅ No double-free
- ✅ No aliasing bugs
- ✅ No "who owns this memory?" confusion

**The ownership is explicit in the type system.** A `Header` instance **IS** the memory, not a pointer to memory.

This is what Rust tries to achieve with lifetimes and borrow checking. Flux achieves it by **eliminating pointers from data structures entirely**. You can't have a dangling pointer if structs don't contain pointers.

### Additional Benefits:
- **Zero-copy parsing**: No memcpy, data just moves ownership
- **Sequential processing**: Parse binary formats by consuming sequentially
- **Perfect for binary protocols**: Read header, consume it, read next section
- **Predictable performance**: No hidden allocations or copies

---

## Implementation Requirements for V1 (Bootstrap Compiler)

### 1. Type System Changes

#### Fixed Sizes Required
- All struct members MUST have fixed, compile-time-known sizes
- `byte[]` in structs is invalid → must be `byte[N]`
- Parser must enforce explicit array sizes for struct members

#### Type Resolution
```flux
// In redtypes.fx - MUST have explicit size for V1:
unsigned data{8} as byte;
byte[8] as noopstr;  // Fixed size required

// In struct:
struct X {
    noopstr a, b;  // Each is [8 x i8], total 16 bytes inline
}
```

#### TypeSpec.get_llvm_type() Fix
```python
# byte[8] must resolve to:
[8 x i8]  # Inline array, NOT i8* pointer

# Custom type resolution:
noopstr → byte[8] → [8 x i8]
```

---

### 2. StructDef.codegen() Complete Rewrite

#### Create Pure Packed Inline Struct
```python
def codegen(self, builder: ir.IRBuilder, module: ir.Module) -> ir.Type:
    # Convert ALL members to inline types
    member_types = []
    for member in self.members:
        member_type = member.type_spec.get_llvm_type(module)
        # Ensure it's NOT a pointer type
        if isinstance(member_type, ir.PointerType):
            raise ValueError(f"Struct member '{member.name}' cannot be pointer type")
        member_types.append(member_type)
    
    # Create packed struct with inline data only
    struct_type = ir.LiteralStructType(member_types)
    struct_type.names = [m.name for m in self.members]
    struct_type.packed = True
    struct_type.aligned = True
    
    # Store in module
    if not hasattr(module, '_struct_types'):
        module._struct_types = {}
    module._struct_types[self.name] = struct_type
    
    return struct_type
```

---

### 3. Struct Initialization - String Literals to Inline Arrays

#### Named Initialization
```flux
X x = {a = "TEST", b = "ING!"};
```

**Implementation**:
```python
def handle_struct_literal_named(self, builder, module):
    # Allocate struct memory
    struct_ptr = builder.alloca(struct_type, name="struct_init")
    
    for field_name, field_expr in self.value.items():
        field_index = struct_type.names.index(field_name)
        member_type = struct_type.elements[field_index]
        
        # Get pointer to member (inline in struct)
        member_ptr = builder.gep(struct_ptr, [i32(0), i32(field_index)])
        
        if isinstance(field_expr, Literal) and field_expr.type == DataType.CHAR:
            # String literal - copy bytes INLINE
            string_val = field_expr.value
            
            if isinstance(member_type, ir.ArrayType):
                # Member is array - copy bytes directly
                array_size = member_type.count
                
                for i, char in enumerate(string_val):
                    if i >= array_size:
                        break  # Truncate if too long
                    
                    elem_ptr = builder.gep(member_ptr, [i32(0), i32(i)])
                    builder.store(ir.Constant(i8, ord(char)), elem_ptr)
                
                # Zero-pad remaining bytes
                for i in range(len(string_val), array_size):
                    elem_ptr = builder.gep(member_ptr, [i32(0), i32(i)])
                    builder.store(ir.Constant(i8, 0), elem_ptr)
            
            # NO GLOBAL CONSTANTS, NO POINTERS
        else:
            # Normal value - generate and store
            value = field_expr.codegen(builder, module)
            builder.store(value, member_ptr)
    
    return builder.load(struct_ptr)
```

#### Positional Initialization
```flux
X x = {"TEST", "ING!"};
```
Same logic as named, but map values to members by index order.

---

### 4. Destructive Casting Implementation

This is the HARD part for V1 with LLVM.

#### The Challenge:
```flux
byte[100] buffer = readfile();
Header h = (Header)buffer[0:13];  // Should CONSUME bytes from buffer
```

**Problem**: LLVM doesn't have "destructive move" semantics. Memory is either:
- Copied (memcpy)
- Aliased (pointer)
- Freed (explicit dealloc)

**V1 Workaround** (Bootstrap limitation):
```python
# For V1, simulate destructive casting with:
# 1. Allocate new struct
# 2. Copy bytes from source to struct
# 3. "Invalidate" source by zeroing consumed bytes or marking

def codegen_cast_to_struct(self, builder, module):
    # self is CastExpression(target_type=StructType, expr=array_slice)
    
    # Get source array and slice range
    source_array = self.expr.array  # The buffer
    start_idx = self.expr.start
    end_idx = self.expr.end
    
    # Allocate struct
    struct_type = self.target_type.get_llvm_type(module)
    struct_ptr = builder.alloca(struct_type)
    
    # Copy bytes from source[start:end] to struct
    # For each struct member, copy corresponding bytes
    byte_offset = 0
    for i, member in enumerate(struct_type.elements):
        member_size = member.get_abi_size(module.data_layout)
        member_ptr = builder.gep(struct_ptr, [i32(0), i32(i)])
        
        # Copy bytes from source array
        for j in range(member_size):
            src_idx = start_idx + byte_offset + j
            src_ptr = builder.gep(source_array, [i32(0), i32(src_idx)])
            src_byte = builder.load(src_ptr)
            
            dst_ptr = builder.gep(member_ptr, [i32(0), i32(j)])
            builder.store(src_byte, dst_ptr)
        
        byte_offset += member_size
    
    # V1: Don't actually resize source array (LLVM limitation)
    # V2: Will properly implement destructive move
    
    return builder.load(struct_ptr)
```

**Note**: True destructive casting requires runtime support that V1 doesn't have. For bootstrap, we copy bytes but V2 will do proper ownership transfer.

---

### 5. Array Slicing for Casting

```flux
buffer[0:13]  // Slice notation for casting
```

Parser should handle this as:
```python
@dataclass
class ArraySlice(Expression):
    array: Expression
    start: Expression
    end: Expression
```

Used in cast expressions:
```flux
(Header)buffer[0:13]
```

---

## Testing Strategy

### Test 1: Basic Inline Storage
```flux
struct X {
    byte[4] a;
    byte[4] b;
}
X x = {"TEST", "ING!"};
// Memory: [T][E][S][T][I][N][G][!]
// Reading 8 bytes from &x should give "TESTING!"
```

### Test 2: Positional Init
```flux
X x = {"TEST", "ING!"};
// Should map "TEST" → a, "ING!" → b
// Same result as named init
```

### Test 3: Binary Casting (V1 - Copy semantics)
```flux
byte[8] buffer = [0x54, 0x45, 0x53, 0x54, 0x49, 0x4E, 0x47, 0x21];
X x = (X)buffer[0:7];
// x.a should contain "TEST"
// x.b should contain "ING!"
// V1: buffer still contains original data (copy not move)
// V2: buffer would be resized/invalidated (true destructive move)
```

### Test 4: Sequential Parsing
```flux
byte[100] data = readfile();
Header h = (Header)data[0:13];
InfoHeader ih = (InfoHeader)data[0:39];  
// V1: starts at original data[0]
// V2: would start at new data[0] after h consumed first 14 bytes
```

---

## Files to Modify

### 1. fast.py
- `TypeSpec.get_llvm_type()` - fix array resolution, reject pointers in structs
- `StructDef.codegen()` - complete rewrite (inline only)
- `Literal.codegen()` - fix struct literal handling (no global constants)
- `CastExpression.codegen()` - add struct casting logic (copy for V1)
- Add `ArraySlice` AST node if not present

### 2. fparser.py
- Validate: reject unsized arrays in structs
- Ensure array slice parsing: `buffer[0:13]`
- Struct literal parsing (probably already correct)

### 3. redtypes.fx
- Change `byte[] as noopstr;` → `byte[8] as noopstr;`

---

## Success Criteria

✅ `X x = {"TEST", "ING!"};` creates 8-byte struct with inline data  
✅ Reading 8 bytes from `&x` prints "TESTING!" (packed inline)  
✅ No global string constants created  
✅ No pointers in struct layout  
✅ `(Header)buffer[0:13]` copies bytes into struct (V1 limitation)  
✅ `sizeof(X)` returns correct byte count  
✅ Struct members are tightly packed in memory  

---

## What NOT to Do

❌ Create global string constants  
❌ Use pointers for struct members  
❌ Allow unsized arrays in structs  
❌ Make assumptions about Flux behavior  
❌ Compare to C - Flux is fundamentally different  
❌ Forget destructive casting semantics (even if V1 approximates)

---

## Why This Matters

This isn't just a bug fix. This is the fundamental innovation that makes Flux different:

**Memory Safety Without Complexity**: Rust achieves memory safety with lifetimes, borrow checker, and complex type system. Flux achieves it by making structs own their data inline. Can't have dangling pointers if there are no pointers.

**Zero-Copy Binary Processing**: Perfect for parsing file formats, network protocols, embedded systems. Cast binary data directly to structs without copying.

**Predictable Performance**: No hidden allocations, no garbage collection, no reference counting. Data lives where you put it.

**This is why Flux could replace C for systems programming.** It solves the core problems at the design level, not by adding layers of complexity.

This implementation must be correct. The entire language depends on it.