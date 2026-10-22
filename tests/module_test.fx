#import <standard.fx>;

using standard::io::console;

module A
{
    foo() -> void -> println("Foo from A!");

	main() -> int
	{
		println("I'm program A!");
		->0;
	};
}
# build
{
	#[name] = "prog_a",
    !+#[borrow_check] = true
};

module B
{
	main() -> int
	{
        foo();
		println("I'm program B!");
		->0;
	};
}
# build
{
	#[entrypoint] = this,
	#[name] = "prog_b",
	#[override for A] =
	{
		#[borrow_check] = false
	}
};