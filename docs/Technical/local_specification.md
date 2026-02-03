# Flux: The `local` Keyword Specification
## Technical Writeup on Scope-Restricted Variable Semantics

**Document Version:** 1.0  
**Date:** January 2026  

---

## Abstract

The `local` keyword introduces a compile-time enforced guarantee: variables declared as `local` cannot cross stack frame boundaries. They cannot be passed as arguments to functions, returned from functions, or have their addresses taken in ways that could escape the current scope. This potentially - enables specific compiler optimizations and provides stronger correctness guarantees - for variables that are semantically bound to a single lexical scope.

---

## 1. Core Semantics

### 1.1 Basic Definition

```flux
def example() -> void {
    int normal = 42;      // Regular variable
    local int restricted = 99;  // Cannot leave this function
    
    // OK: Use within scope
    int sum = normal + restricted;
    
    // ERROR: Cannot pass to function
    some_function(restricted);  // Compile-time error
    
    // ERROR: Cannot return
    return restricted;  // Compile-time error
    
    // ERROR: Cannot take address that might escape
    int* ptr = @restricted;  // Compile-time error
};
```

### 1.2 Formal Rules

A `local` variable `v` declared in scope `S`:

1. **May be used** in any expression within `S`
2. **May not be** an argument to any function call from `S`
3. **May not be** returned from `S`
4. **May not have** its address taken with `@` unless:
   - The pointer is also `local`
   - The pointer does not escape `S`

---

## 2. Implementation and Optimization Opportunities

### 2.1 Compiler Guarantees

Because `local` variables provably don't escape:

```flux
def compute() -> int {
    local int buffer[1024];
    // ... use buffer ...
    return result;
};
```

The compiler can:
1. **Stack allocate with confidence**: No need for escape analysis
2. **Aggressive register allocation**: Variable can live entirely in registers
3. **Dead store elimination**: If not used, can be optimized away completely
4. **No aliasing concerns**: Other pointers cannot reference this memory

### 2.2 LLVM Lowering Example

```flux
def process() -> int {
    local int counter = 0;
    
    for (int i = 0; i < 100; i++) {
        counter += i;
    }
    
    return counter;  // ERROR: Cannot return local
}
```

**Without `local`** (pessimistic):
```llvm
; Stack allocation (may escape)
%counter = alloca i32, align 4
store i32 0, i32* %counter, align 4

; Must use memory operations
%val = load i32, i32* %counter
%new = add i32 %val, %i
store i32 %new, i32* %counter
```

**With `local`** (optimized):
```llvm
; Register only (proven non-escaping)
%counter.reg = 0  ; SSA value, no memory

; Direct computation
%counter.reg = add i32 %counter.reg, %i
```

### 2.3 Control Flow Analysis

```flux
def complex() -> void {
    local int secret = 42;
    
    if (condition) {
        // Still in same lexical scope - OK
        int x = secret * 2;
    } else {
        // Also OK
        for (int i = 0; i < secret; i++) {
            // Nested scope, but still within function
            process(i);
        }
    }
    
    // ERROR: Cannot pass to function
    helper(secret);
};
```

---

## 3. Use Cases and Examples

### 3.1 Temporary Buffers

```flux
def format_string(string input) -> string {
    // Buffer only needed during formatting
    local char buffer[256];
    
    // Format into buffer
    int len = snprintf(buffer, 256, "Result: %s", input); // Error
    
    // Create result (copy allowed)
    string result = copy_from_buffer(buffer, len);
    
    // buffer "dies" here
    // No risk of dangling references
    return result;
};
```

### 3.2 Loop Accumulators

```flux
def sum_matrix(int[][100] matrix, int rows) -> int {
    int total = 0;  // Regular variable for return
    local int accumulator = 0;  // Temporary compute buffer
    
    for (int r = 0; r < rows; r++) {
        accumulator = 0;  // Reset each row
        for (int c = 0; c < 100; c++) {
            accumulator += matrix[r][c];
        }
        total += accumulator;  // Transfer to non-local
    }
    
    return total;  // OK: total is not local
};
```

### 3.3 One-Time Computations

```flux
def compute_hash(string data) -> uint64 {
    // Intermediate state that never leaves
    local uint64 state[4];
    initialize_state(state);  // ERROR: Can't pass local!
    // Actually shows this pattern doesn't work
    
    // Need to rethink: either:
    // 1. Make initialize_state inline
    // 2. Use non-local if function call needed
};
```

This reveals a design constraint: `local` variables work best with inline computation or when the entire algorithm fits in one scope.

---

## 4. Edge Cases and Limitations

### 4.1 Pointers to Local

```flux
def pointer_example() -> void {
    local int value = 42;
    
    // ERROR: Pointer might escape
    int* ptr = @value;
    
    // OK: Local pointer to local data
    local int* local_ptr = @value;
    
    // ERROR: Even local pointer can't be passed
    process_pointer(local_ptr);
};
```

### 4.2 Arrays and Structs

```flux
def array_example() -> void {
    local int[100] buffer;
    
    // OK: Element access
    buffer[0] = 1;
    
    // ERROR: Array-to-pointer decay that might escape
    int* ptr = buffer;
    
    // OK: Iteration within scope
    for (i in 0..99) {
        buffer[i] = i;
    }
    
    // ERROR: Passing slice
    process_slice(buffer[10..20]);
};
```

### 4.3 Nested Functions (if supported)

```flux
def outer() -> void {
    local int counter = 0;
    
    // If Flux had closures/lambdas:
    def inner() -> void {
        // ERROR: Cannot capture local from outer scope
        counter += 1;
    };
    
    inner();
};
```

---

## 5. Comparison with Similar Concepts

### 5.1 vs C's `register` Keyword

| Aspect | `register` | `local` |
|--------|------------|---------|
| Purpose | Hint for register allocation | Guarantee of non-escaping |
| Enforcement | Optional suggestion | Mandatory restriction |
| Scope | Variable lifetime | Stack frame boundaries |
| Address | Cannot take address | Cannot take escaping address |

### 5.2 vs Rust's Borrow Checker

```rust
fn example() {
    let x = 42;
    let y = &x;  // OK in Rust
    use_ref(y);  // OK in Rust
}
```

```flux
def example() -> void {
    local int x = 42;
    int* y = @x;  // ERROR in Flux
    use_ref(y);   // Would be error even if pointer allowed
};
```

**Key difference**: Rust tracks lifetimes; Flux `local` prohibits cross-frame movement entirely.

### 5.3 vs Java's `final` / C++'s `const`

`final`/`const` prevent modification; `local` prevents cross-scope movement. Orthogonal concepts:

```flux
def example() -> void {
    const local int x = 42;  // Both immutable AND non-escaping
    // x = 10;  // ERROR: const violation
    // process(x);  // ERROR: local violation
};
```

---

## 6. Compiler Implementation

### 6.1 Type System Extension

```flux
// Type qualifier system
Type ::= BaseType | local Type

// Flow-sensitive check
CheckLocal(e, env):
    if e is Variable(name) and env[name].is_local:
        if current_context != env[name].declared_context:
            ERROR "local variable escapes scope"
```

### 6.2 Escape Analysis Integration

The `local` keyword makes escape analysis trivial:

```
EscapeAnalysis(variable):
    if variable.declared_local:
        return NO_ESCAPE  // Proven by declaration
    else:
        // Run traditional escape analysis
        return analyze_usage(variable)
```

### 6.3 Error Messages

Clear diagnostics are essential:

```
Error: local variable 'buffer' cannot be passed to function
  --> src/main.fx:42:12
   |
42 |     process(buffer);
   |            ^^^^^^
   |
Note: 'buffer' was declared as local on line 37
   |
37 |     local char[256] buffer;
   |     ^^^^^^^^^^^^^^^^^^^^^^
   = help: Remove 'local' if you need to pass this variable
   = help: Or rewrite to keep computation within current scope
```

---

## 7. Practical Applications

### 7.1 Performance-Critical Loops

```flux
def hot_loop(float[] data) -> float {
    // Intermediate values stay in registers
    local float sum = 0.0;
    local float sum_sq = 0.0;
    
    for (x in data) {
        sum += x;
        sum_sq += x * x;
    }
    
    // Final computation
    float mean = sum / data.len;
    float variance = sum_sq / data.len - mean * mean;
    return variance;  // ERROR: Can't return locals!
    // Need to copy to non-local:
    float result = variance;
    return result;
};
```

### 7.2 Resource Cleanup Patterns

```flux
def with_temp_file() -> string {
    // Create temp path
    string path = generate_temp_path();
    
    {
        // File only exists in this block
        local File temp = File.open(path, "w");
        temp.write("data");
        // File closed automatically at block end
        // Guaranteed: no reference to 'temp' escapes
    }
    
    // Read back results
    return read_file(path);
};
```

### 7.3 Algorithmic Intermediate States

```flux
def inplace_sort(int[] data) -> void {
    // Temporary swap space that never leaves
    if (data.len > 1) {
        local int temp;
        
        for (i in 0..data.len-1) {
            for (j in i+1..data.len-1) {
                if (data[j] < data[i]) {
                    temp = data[i];
                    data[i] = data[j];
                    data[j] = temp;
                }
            }
        }
    }
    // 'temp' inaccessible here - guaranteed
};
```

---

## 8. Limitations and Design Trade-offs

### 8.1 The Inlining Requirement

Because `local` variables can't be passed to functions, algorithms using them often require inlining:

```flux
// Instead of this (doesn't work):
def process(local int x) -> void {  // ERROR: Parameters can't be local
    // ...
}

// Need this:
def outer() -> void {
    local int x = compute();
    
    // Inline the processing
    int result = x * 2 + x / 3;  // Whatever process() would do
    
    use(result);
};
```

### 8.2 Composition Challenges

```flux
def composed() -> void {
    local int a = compute_a();
    local int b = compute_b();
    
    // Can't do this:
    // int c = combine(a, b);  // ERROR
    
    // Must inline combine():
    int c = a * b + (a << 2) - b / 3;  // Inlined combine logic
};
```

### 8.3 Testing and Mocking

Unit testing becomes challenging when functions can't accept `local` variables:

```flux
// Hard to test:
def algorithm() -> int {
    local int state = initialize();
    // ... complex logic with state ...
    return finalize(state);  // ERROR: Can't pass local
};

// Testing requires refactoring or different patterns
```

---

## 9. Conclusion

The `local` keyword provides a simple, enforceable guarantee: **this variable lives and dies within this scope**. While restrictive, this enables:

1. **Compiler optimizations** without complex analysis
2. **Clear ownership semantics** without borrow checking complexity  
3. **Scope-bound resource management** with guaranteed cleanup
4. **Elimination of certain error classes** (use-after-return from scope)

The trade-off is reduced composability—functions cannot accept `local` parameters, encouraging algorithmic inlining and self-contained scope design. For performance-critical code where variables are truly scope-bound, `local` provides both optimization opportunities and stronger correctness guarantees through compile-time enforcement.

---

## Appendix: Grammar Additions

```
Declaration ::= StorageClass? Type Identifier ('=' Expression)? ';'
StorageClass ::= 'local' | 'const' | 'volatile' | 'register'

// local cannot appear in:
// - Function parameters
// - Return types  
// - Struct/class fields
// - Global variables
```

**Type Qualifier Order**: `const local int x` not `local const int x` (though both could be supported).