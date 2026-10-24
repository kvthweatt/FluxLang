// uaf.fx // use-after-free
//
// Tests simple use-after-free & double-free

module BorrowCheckerTest
{
	#import <standard.fx>;

	using standard::io::console;

    foo(int* a) -> void -> (void)a;

	main() -> int
	{
		heap int x = 100;

        int* px = x;

        foo(x);  // free
        (void)x; // double-free

        println(*px); // UAF

		-> 0;
	};
}
# build
{
	#[borrow_check] = true,
    #[test] =
    {
        #[expect_build_fail]
    }
};