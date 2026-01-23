# Change Log

## 1/23/2026
- Implemented `ArrayLiteral` in the AST, solving many issues.
- Made `StringLiteral` use `ArrayLiteral`
- Solved an issue with array access and assignment, can now do `array[index] = value;`
- Refactored the runtime a bit. Prepared for `GetStdHandle` so `win_print()` doesn't have to call it every time.
- Fixed runtime for Linux so programs no longer `SEGFAULT` after execution.

## 1/22/2026
- Began some runtime implementation.  
- `strlen()` in `tests\strlen.fx` is a working example. Requires including the C runtime (for now).  
- Removed macro definition from `def`, and instead put macros where they belong, in the preprocessor.  
You can now do `#def MYMACRO 1;` `#ifdef MYMACRO` or `#ifndef MYMACRO`, `#else` and `#endif;`. The preprocessor enforces the semicolon for `#endif;`.    
This means you can now do this:
```
#ifdef SOME_THING
def only_defined_if_some_thing_defined() -> void
{
	// implementation
	return void;
};
#else
def other_thing_if_not_defined() -> void
{
	// implementation
	return void;
};
#endif
```
The appropriate function will be present.

## 1/5/2026
- `switch` statements now work fully.  
- All built-in operators are working, ex `++`, `--`, `!&`, `^=`, `<<=`, `>>=` etc.  
- All loops working, `do`, `do-while`, `while`, and `for`. Recursion as well naturally.  
- Added the ability to control memory better with `stack`, `heap`, `global`.
- A new `local` keyword is in the works, used to restrict scope.  