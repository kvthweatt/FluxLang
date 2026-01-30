# Flux Namespace Access Specification
## `using`, `!using`, and `::` Qualified Access

---

## **Core Principles**

1. **Explicit is better than implicit** - You must declare what you're using
2. **Scope-aware** - `using` and `!using` respect lexical scope
3. **Qualified access requires availability** - Can only use `::` on things already in scope

---

## **1. `using` - Bring Symbols Into Scope**

### **Syntax**
```flux
using namespace::path;              // Brings entire namespace
using namespace::path::symbol;      // Brings specific symbol (all overloads)
```

### **Behavior**
- Makes symbols accessible in current scope
- For functions: brings in ALL overloads of that name
- Nested: can bring in nested namespaces
- Local `using` overrides global scope

### **Examples**
```flux
// Bring entire namespace
using standard::io::console;
print("Hello\0");  // ✅ Works - print is in console

// Bring specific symbol
using standard::math::abs;
x = abs(-5);  // ✅ Works

// Bring nested namespace
using standard::io;
console::print("Hi\0");  // ✅ Works - io is in scope, can qualify console

// Local override
!using standard::io::console::input;  // Blocked globally

def foo() -> int
{
    using standard::io::console::input;  // ✅ Local override
    input(buf, 10);  // ✅ Works in this function
    return 0;
};

def bar() -> int
{
    input(buf, 10);  // ❌ Error - input not in scope
    return 0;
};
```

---

## **2. `!using` - Block/Remove Symbols From Scope**

### **Syntax**
```flux
!using namespace::path;              // Blocks entire namespace
!using namespace::path::symbol;      // Blocks specific symbol
```

### **Behavior**
- **Preemptive blocking**: Can block before any `using` statements
- **Scope-aware**: Global blocks apply to global scope only
- **Local override**: Can still `using` something in local scope even if globally blocked
- **Error on use**: Trying to reference blocked symbol = `NameError: symbol not found`

### **Use Cases**
1. **Reduce binary size** - Exclude unused stdlib components
2. **Prevent accidental use** - Block dangerous functions (memcpy, etc)
3. **Sensible defaults** - Library authors can block advanced/unsafe features by default

### **Examples**
```flux
#import "standard.fx"

// Preemptively block dangerous/large things
!using standard::types::memcpy;
!using standard::io::console::input;
!using standard::math::sin;  // Don't need trig

// Now bring in what you want
using standard::io::console::print;
using standard::math::abs;

def main() -> int
{
    print("Hello\0");     // ✅ Works
    input(buf, 10);       // ❌ NameError: 'input' not found
    x = abs(-5);          // ✅ Works
    y = sin(3.14);        // ❌ NameError: 'sin' not found
    memcpy(dst, src, 10); // ❌ NameError: 'memcpy' not found
    return 0;
};

// But you can still pull it in locally if needed
def unsafe_fast_path() -> void
{
    using standard::types::memcpy;  // ✅ Local override
    memcpy(dst, src, size);         // ✅ Works here only
    return;
};
```

### **Block Entire Namespace**
```flux
!using standard::io;  // Block everything in io

using standard::io::console::print;  // ❌ Blocked - io is not available
```

---

## **3. `::` Qualified Access**

### **Syntax**
```flux
namespace::symbol
namespace::nested::symbol
```

### **Behavior**
- **Requires availability**: Can ONLY qualify within namespaces/symbols already brought into scope via `using`
- **Cannot skip levels**: If `io` isn't used, can't do `io::console::print`
- **Disambiguation**: Use qualified access to distinguish between symbols with same name

### **Rules**
1. The **leftmost namespace** must be in scope via `using`
2. Can then qualify any members within that namespace
3. Cannot use `::` to access things not brought into scope

### **Examples**

#### **Basic Qualified Access**
```flux
using standard::io::console;

def main() -> int
{
    console::print("Hello\0");  // ✅ console is in scope
    return 0;
};
```

#### **Cannot Skip Levels**
```flux
using standard::io;

def main() -> int
{
    console::print("Hello\0");        // ✅ io is in scope, can qualify console
    standard::io::console::print();   // ❌ 'standard' not in scope
    io::console::print();             // ❌ 'io' not in scope (only 'standard::io')
    return 0;
};
```

#### **Disambiguation**
```flux
using std::math;      // Namespace with abs()
using custom::math;   // Different namespace with abs()

def main() -> int
{
    x = abs(-5);              // ❌ Ambiguous - which abs()?
    x = std::math::abs(-5);   // ✅ Explicitly std version
    y = custom::math::abs(-5); // ✅ Explicitly custom version
    return 0;
};
```

#### **Nested Qualification**
```flux
using standard;  // Bring in 'standard' namespace

def main() -> int
{
    standard::io::console::print("Hello\0");  // ✅ standard in scope, qualify everything within
    return 0;
};
```

---

## **Complete Example**

```flux
#import "standard.fx"

// Global blocks (sensible defaults)
!using standard::io::console::input;   // Dangerous - block by default
!using standard::types::memcpy;        // Use safe wrapper instead
!using standard::math::sin;            // Don't need trig

// Bring in what we need globally
using standard::io;                    // Bring io namespace
using standard::math;                  // Bring math namespace

def main() -> int
{
    // Qualified access within used namespaces
    io::console::print("Starting...\n\0");
    
    int x = -42;
    int y = math::abs(x);  // ✅ math in scope
    
    // This would fail - input blocked globally
    // io::console::input(buf, 10);  // ❌ NameError
    
    io::console::print("Done!\n\0");
    return 0;
};

// But can still use blocked things locally if needed
def get_user_input() -> void
{
    using standard::io::console::input;  // ✅ Local override
    
    byte[256] buffer;
    input(buffer, 256);  // ✅ Works in this function only
    
    return;
};

// This function has no access to input
def other_function() -> void
{
    input(buf, 10);  // ❌ NameError - not in scope
    return;
};
```

---

## **Implementation Notes**

### **Parser/Symbol Table**
1. Maintain `available_symbols` set per scope
2. Maintain `blocked_symbols` set per scope
3. When processing `using`:
   - Check if symbol is in `blocked_symbols`
   - If not blocked, add to `available_symbols`
4. When processing `!using`:
   - Add to `blocked_symbols`
   - Remove from `available_symbols` if present
5. When resolving names:
   - Check `available_symbols` in current scope
   - Walk up scope chain if not found
   - Treat absence as `NameError`

### **Qualified Access Resolution**
1. Split `namespace::path::symbol` on `::`
2. Check if leftmost component is in `available_symbols`
3. If yes, resolve rest of path within that namespace
4. If no, `NameError: 'leftmost' not found`

---

## **Key Differences from Other Languages**

| Language | `using` behavior | Qualified access |
|----------|------------------|------------------|
| **C++** | `using namespace std;` pulls everything | Can always use `std::vector` |
| **Python** | `from x import y` or `import x` | Can always use `module.symbol` |
| **Rust** | `use std::io::Write;` | Can always use `std::io::Write` |
| **Flux** | Must `using` before access | Can ONLY qualify what's `using`'d |

**Flux is more restrictive** - this is intentional for:
- Explicit dependency tracking
- Binary size control via `!using`
- No mystery symbols from deep namespaces

---

## **Summary**

✅ **`using`** - Brings symbols/namespaces into scope  
✅ **`!using`** - Blocks symbols/namespaces (even preemptively)  
✅ **`::`** - Qualified access within what's already in scope  

**Rule of thumb:** If it's not `using`'d, it doesn't exist.