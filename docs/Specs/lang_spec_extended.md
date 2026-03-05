# Language Specification Extensions

These are features that are deferred for the bootstrapped version of Flux.

---

## **Compile-Time with `compt`:**
`compt` is used to create anonymous blocks that are executed in their order of appearance.
Any variable declarations become global definitions in the resulting program.  
compt blocks can only be declared in global scope, never inside a function, namespace, or anywhere else.  
The Flux compiler will have the runtime built into it allowing for full Flux capabilities during comptime.  
`compt` blocks act as guard rails that guarantees everything inside resolves at compile time.
```
compt {
	// This anonymous compt block will execute in-line at compile time.
	def test1() -> void
	{
		global def MY_MACRO 1;
	    return void;
	};

	if (!def(MY_MACRO))
	{
	    test1();
	};
};
```