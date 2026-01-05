# Flux `register` Keyword - Complete Guide

## Overview

The `register` storage class is a **hint** to the compiler to keep a variable in a CPU register for maximum performance. Unlike other storage classes (`stack`, `heap`, `global`), `register` does not mandate a specific memory location—it's an optimization suggestion.

## Syntax

```flux
register <type> <identifier> = <initial_value>;
```

Can be combined with qualifiers:
```flux
const register int x = 10;
volatile register int y = 20;
const volatile register int z = 30;
```

## Behavior

### 1. **Register Allocation Hint**
When you declare a variable as `register`, the compiler:
- Creates a stack allocation (alloca in LLVM)
- Adds metadata hinting aggressive register promotion
- Trusts LLVM's register allocator to keep it in a register when beneficial

### 2. **Automatic Demotion**
The compiler may **ignore** the register hint if:
- All registers are in use (register pressure)
- The variable's address is taken (requires memory location)
- The variable is too large (structs, large arrays)
- The function is not optimized (`-O0`)

### 3. **LLVM Backend**
Behind the scenes:
```llvm
; register int counter = 0;
%counter = alloca i32, align 4
store i32 0, %counter, align 4

; With optimization, LLVM will promote to SSA register:
; %0 = phi i32 [ 0, %entry ], [ %inc, %loop ]
```

## Restrictions

### ❌ **Cannot Be Register**
1. **Arrays**: Arrays cannot be register variables (require contiguous memory)
   ```flux
   register int arr[10];  // ERROR: arrays must have stable addresses
   ```

2. **Structs**: Complex types generally cannot be register (implementation-defined)
   ```flux
   register MyStruct s;   // WARNING: likely ignored by compiler
   ```

### ⚠️ **Discouraged**
3. **Address-of Operation**: Taking the address of a register variable:
   ```flux
   register int x = 10;
   int* ptr = @x;  // WARNING: register hint removed, x demoted to stack
   ```
   - Generates a compiler warning
   - Removes the register hint (variable must have an address)
   - Still valid, but defeats the purpose

### ✅ **Allowed**
4. **Pointers**: Register pointers are valid and useful
   ```flux
   register int* ptr = @some_array[0];  // OK: pointer value in register
   ```

5. **Scalar Types**: Ideal candidates for register
   ```flux
   register int counter = 0;     // Excellent
   register float accumulator;   // Excellent
   register char ch;             // Excellent
   register unsigned data{16} x; // Excellent
   ```

## Best Practices

### 1. **Loop Counters and Accumulators**
```flux
def sum_array(int[] arr, int len) -> int {
    register int sum = 0;  // Accumulator: perfect for register
    register int i = 0;    // Loop counter: perfect for register
    
    for (i = 0; i < len; i++) {
        sum += arr[i];
    };
    
    return sum;
};
```

### 2. **Hot Path Variables**
```flux
def process_pixels(byte[] pixels, int count) -> void {
    register int threshold = 128;  // Frequently accessed constant
    
    for (register int i = 0; i < count; i++) {
        if (pixels[i] > threshold) {
            pixels[i] = 255;
        } else {
            pixels[i] = 0;
        };
    };
    
    return;
};
```

### 3. **Pointer Iteration**
```flux
def find_zero(int* arr, int len) -> int* {
    register int* ptr = arr;      // Pointer in register
    register int* end = arr + len;
    
    while (ptr < end) {
        if (*ptr == 0) {
            return ptr;
        };
        ptr++;
    };
    
    return void;
};
```

### 4. **Avoid Unnecessary Register**
```flux
def bad_example() -> void {
    // ❌ BAD: Large struct won't fit in register anyway
    register struct BigData {
        int data[1000];
        float values[500];
    } big_struct;
    
    // ❌ BAD: Need to take address (defeats purpose)
    register int x = 10;
    process_value(@x);
    
    // ❌ BAD: Rarely accessed variable (wastes register)
    register int rarely_used = compute_something();
    // ... lots of code ...
    return rarely_used;
};

def good_example() -> void {
    // ✅ GOOD: Small scalar in tight loop
    register int sum = 0;
    for (register int i = 0; i < 1000; i++) {
        sum += i;
    };
    
    return;
};
```

## Storage Class Priority

When combined with other storage classes:
```flux
register heap int x;    // ERROR: conflicting storage classes
register stack int y;   // ERROR: conflicting storage classes
register global int z;  // ERROR: conflicting storage classes

const register int a = 10;        // OK: const is qualifier, not storage
volatile register int b = 20;     // OK: volatile is qualifier
```

**Rule**: Only one storage class per variable:
- `register`, `stack`, `heap`, `global`, `local` are mutually exclusive
- `const`, `volatile` are qualifiers and can be combined with any storage class

## Performance Considerations

### When Register Helps
1. **Tight loops** with small iteration counts (< 10,000)
2. **Frequently accessed** variables (> 10 accesses per function)
3. **Simple arithmetic** operations on scalars
4. **Small functions** with few local variables

### When Register Doesn't Help
1. **Already optimized** code at `-O2` or higher
2. **Complex functions** with high register pressure
3. **Variables whose address is taken**
4. **Large data structures**
5. **Infrequently accessed** variables

### Measuring Impact
```flux
// Benchmark with and without register
def benchmark_register() -> void {
    // Version 1: With register (may be faster)
    register int sum = 0;
    for (register int i = 0; i < 1000000; i++) {
        sum += i;
    };
    
    // Version 2: Without register (may be same speed with -O2)
    int sum2 = 0;
    for (int i = 0; i < 1000000; i++) {
        sum2 += i;
    };
    
    return;
};
```

**Reality Check**: Modern compilers (LLVM, GCC) are excellent at register allocation. The `register` keyword:
- **May help** at `-O0` (debug builds)
- **Rarely helps** at `-O2` or higher (optimized builds)
- **Serves as documentation** of programmer intent

## Interaction with Other Features

### With `volatile`
```flux
volatile register int hardware_status;
```
- **Volatile**: Must read from/write to memory (never cache in register)
- **Register**: Prefer register over memory
- **Result**: Volatile takes precedence—variable will NOT be kept in register
- **Warning**: Conflicting semantics; compiler will warn or error

### With `const`
```flux
const register int MAX_SIZE = 1000;
```
- **Const**: Value cannot change after initialization
- **Register**: Keep in register for fast access
- **Result**: Excellent combination—constant in register is very efficient

### With Inline Assembly
```flux
def asm_with_register() -> int {
    register int x = 10;
    
    volatile asm {
        addl $5, x   // May not work if x is in register
    };
    
    return x;
};
```
- Inline asm often needs memory operands
- Register variables may not have stable memory addresses
- Use explicit register constraints in asm blocks

## Comparison to C/C++

### C Standard
```c
// C language
register int x = 10;  // Hint to keep in register
int* ptr = &x;        // ERROR in C: cannot take address of register variable
```

### Flux Approach
```flux
// Flux language
register int x = 10;  // Hint to keep in register
int* ptr = @x;        // WARNING: allowed but removes register hint
```

**Key Difference**: Flux allows taking addresses of register variables but:
1. Generates a warning
2. Automatically removes the register hint
3. Treats the variable as a normal stack variable thereafter

This provides more flexibility while still catching potential mistakes.

## Future Enhancements

Potential future features:

1. **Explicit Register Names** (architecture-specific)
   ```flux
   register("rax") int counter;  // Force specific register
   ```

2. **Register Classes**
   ```flux
   register(integer) int x;      // Use integer register
   register(floating) float y;   // Use FP register
   register(simd) int[4] vec;    // Use SIMD register
   ```

3. **Register Pressure Analysis**
   ```flux
   @pragma(show_register_pressure)
   def hot_function() -> void {
       // Compiler reports: "11/16 registers in use"
   };
   ```

## Summary

| Feature | Behavior |
|---------|----------|
| **Purpose** | Hint for register allocation |
| **Binding** | Non-binding optimization hint |
| **Scope** | Function-local only |
| **Arrays** | Not allowed |
| **Address-of** | Allowed with warning, removes hint |
| **Pointers** | Allowed and useful |
| **With volatile** | Conflict: volatile takes precedence |
| **With const** | Excellent combination |
| **Performance** | Minimal at `-O2`, helps at `-O0` |

**Bottom Line**: Use `register` for:
- Loop counters and accumulators
- Hot path scalar variables
- Documentation of performance-critical variables

Don't use for:
- Large structures or arrays
- Variables whose address is taken
- Rarely accessed variables
- Any variable in optimized builds (compiler knows best)