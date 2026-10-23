# Welcome to the documentation!

Here you can find what you need to learn and understand IDEKA.

The [language specification](https://github.com/kvthweatt/IDEKA/blob/main/docs/Specs/language_specification.md) covers nearly every aspect of the language.  

---

IDEKA is a very dense language, and certain features have names that mean something else in other languages such as `interface`.  
To help you get started and to make IDEKA easier to understand:

It's very concept-based. This will make more and more sense with each example.  
It's also designed to be highly readable once you start recognizing the patterns.  

## Example 1 - Operators  
C uses `&&` for logical AND, `&` for bitwise AND. Unless you know this, you might think they do the same thing.  
Then you have `= &x` which would be address-of x, this makes you have to memorize an exception to the rule of what `&` means.  
Then you have `int&` as a reference type. That's another exception you have to learn.  

IDEKA doesn't do this to you. Firstly, all bitwise operators start with a backtick like ` because "b"acktick = "b"itwise (both start with b)

This means bitwise AND is `&, logical AND is just plain &, no doubling up logical operators because that makes no sense, "and and", and and what?

All bitwise operators start with a backtick like this, making them visually distinct. You can immediately know which is which.

## Example 2 - Address of  
The address of operator is `@` so taking addresses looks like `@x` which immediately reads as "where x is at".

In C you could never write `&=` to mean address-assignment, because that's logical AND assign.

In Flux you can do address assignment like `int* px @= x;`

## Example 3  
The not-null operator `!?`

`?` is used in null-related operators like null-assign or null-coalesce. Here, you have `!` not and `?` null.

You use it like `if (pointer!?)` and reads like `if pointer not null`

But now think about it - When you're excited and asking a question:

**"Really, buy 1 get 3 free!?"**

You're asking a question specifically hoping its true.  
Using `!?` is identical to `!= 0`, so you can do `if (pointer != 0)`

---

The [keyword reference](https://github.com/kvthweatt/IDEKA/blob/main/docs/keyword_reference.md) will help you learn and use new keywords.

The [operator reference](https://github.com/kvthweatt/IDEKA/blob/main/docs/operator_reference.md) will help you learn the operators.

Undersanding IDEKA's type system will require leaving the world of C and other languages which have strict type safety.  
It's best to [start here](https://github.com/kvthweatt/IDEKA/blob/main/docs/learn_flux_intro.md).

IDEKA also has an [Effects System](https://github.com/kvthweatt/IDEKA/blob/main/docs/effects_system.md) which is a unique compile-time system for tracking, propagating, and constraining behavioral properties across call chains. Effects are labels. The operators applied to them are what give those labels meaning. Together they form a compiler programming interface that lets you describe and enforce what code does -- to memory, to the outside world, to other processes -- without any runtime cost. Everything is verified before the binary exists and erased before codegen.

The [standard library](https://github.com/kvthweatt/IDEKA/blob/main/docs/StandardLibrary/standard_library_v1.1.md) will help walk you through what is what and where.

There are setup guides for [Windows](https://github.com/kvthweatt/IDEKA/blob/main/docs/SetupGuides/windows_setup_guide.md) and [Linux](https://github.com/kvthweatt/IDEKA/blob/main/docs/SetupGuides/linux_setup_guide.md).

Every language needs a [style guide](https://github.com/kvthweatt/IDEKA/blob/main/docs/style_guide.md). This guide is a reflection of the standard library.

Information on the [IDEKA Virtual Machine](https://github.com/kvthweatt/IDEKA/blob/main/docs/fvm.md) and [Borrow Checker](https://github.com/kvthweatt/IDEKA/blob/main/docs/fbc.md)