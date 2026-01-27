# Working Keyword & Feature Checklist

- alignof ⚠️ Incomplete, requires full RTTI
- and ✅ 
- as ✅
- asm ✅
- assert ✅
- auto ✅
- bool ✅
- break ✅
- case ✅
- catch
- char ✅
- compt ❌ Deferred for bootsrap
- const ✅
- contract ❌ Deferred for bootsrap
- continue ✅
- data ✅
- def ✅
- default ✅
- do ✅
- elif ✅
- else ✅
- lext ❌ Deferred for bootsrap
- extern ❌ Deferred for bootsrap
- false ✅
- float ✅
- for ✅
- from ⚠️ Incomplete, implementation unfinished
- global ✅
- if ✅
- import ✅
- heap ✅
- in ✅
- int ✅
- is ✅
- local ⚠️ Incomplete, implementation unfinished
- namespace ✅
- not ✅
- object ✅
- operator ❌ Deferred for bootsrap
- or ✅
- private ⚠️ Potentially incomplete, untested
- public ⚠️ Potentially incomplete, untested
- register ✅ Implemented, unverified
- return ✅
- signed ✅
- sizeof ✅
- stack ✅
- struct ✅
- super ❌ Deferred for bootsrap
- switch ✅
- this  ✅
- throw ✅
- trait ❌ Deferred for bootsrap
- true ✅
- try ✅
- typeof ⚠️ Incomplete, requires full RTTI
- union ✅
- unsigned ✅
- using ✅
- void ✅
- volatile ✅
- while ✅
- xor ✅

## Operators:
- ADD = "+" ✅ 
- SUB = "-" ✅
- MUL = "*" ✅
- DIV = "/" ✅
- MOD = "%" ✅
- POWER = "^" ✅
- XOR = "^^" ✅
- OR = "||" ✅
- AND = "&&" ✅
- NOR = "!|" ✅
- NAND = "!&" ✅
- INCREMENT = "++" ✅
- DECREMENT = "--" ✅
    
## Comparison
- EQUAL = "==" ✅
- NOT_EQUAL = "!=" ✅
- LESS_THAN = "<" ✅
- LESS_EQUAL = "<=" ✅
- GREATER_THAN = ">" ✅
- GREATER_EQUAL = ">=" ✅
    
## Shift
- BITSHIFT_LEFT = "<<" ✅
- BITSHIFT_RIGHT = ">>" ✅
    
## Assignment
- ASSIGN = "=" ✅
- PLUS_ASSIGN = "+=" ✅
- MINUS_ASSIGN = "-=" ✅
- MULTIPLY_ASSIGN = "*=" ✅
- DIVIDE_ASSIGN = "/=" ✅
- MODULO_ASSIGN = "%=" ✅
- POWER_ASSIGN = "^=" ✅
- XOR_ASSIGN = "^^=" ✅
- BITSHIFT_LEFT_ASSIGN = "<<=" ✅
- BITSHIFT_RIGHT_ASSIGN = ">>=" ✅
    
## Other operators
- ADDRESS_OF = "@" ✅
- RANGE = ".." ✅
- SCOPE = "::" ✅
- TERMARY = "?:" ✅
- NULL COALESCE = "??" ✅

## Directionals
- RETURN_ARROW = "->" ✅
- CHAIN_ARROW = "<-" ✅
- RECURSE_ARROW = "<~"  ⚠️ Not implemented, can be done in reduced spec