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
- compt ❌ Incomplete, requires bootstrapped compiler
- const ✅
- contract ❌ Incomplete, deferred for full specification
- continue ✅
- data ✅
- def ⚠️ Incomplete, macros not behaving
- default ✅
- do ✅
- elif ✅
- else ✅
- lext ❌ Incomplete, requires bootstrapped compiler
- extern ❌ Incomplete, deferred for full specification
- false ✅
- float ✅
- for ✅
- from ⚠️ Untested, implementation status unknown.
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
- operator ❌ Not implemented, full specification feature
- or ✅
- private ⚠️ Potentially incomplete, untested
- public ⚠️ Potentially incomplete, untested
- register ⚠️ Implemented, unverified
- return ✅
- signed ✅
- sizeof ✅
- stack ✅
- struct ⚠️ Partially implemented, unverified
- super ❌ Not implemented
- switch ✅
- this  ✅
- throw ✅
- trait ❌ Not implemented, full specification feature
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
- QUESTION = "?" ⚠️ Not implemented, needs to be done
- COLON = ":" ⚠️ Not implemented, needs to be done

## Directionals
- RETURN_ARROW = "->" ✅
- CHAIN_ARROW = "<-" ⚠️ Not implemented, can be done in reduced spec
- RECURSE_ARROW = "<~"  ⚠️ Not implemented, can be done in reduced spec