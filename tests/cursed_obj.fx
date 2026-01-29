#import "standard.fx";

object myObj
{
	int x;

	def __init() -> this
	{
        print("Hello from myObj.__init()!\n\0");
        this.x = 5;
		return this;
	};

	def __exit() -> void
	{
        print("Killing myObj instance...\n\0");
        // dereference this, get address, cast to void pointer, dereference, cast to void.
        // can get way more cursed.
		return; // compiles.
	};

	def get() -> int
	{
        print("Getting this.x\n\0");
        int y = this.x;
        print("Got this.x!\n\0");
		return y;
	};
};

def main() -> int
{
	*(byte*)0 = (byte*)0;

	myObj newObj();
	newObj.__exit();

	int y = newObj.get(); // Should fail...

	if (y == 5) // ...but doesn't.
	{
		print("Success!\n\0");
        newObj.__exit();
	};
    //(void)newObj;

	return 0;
};