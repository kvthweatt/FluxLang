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
		return void;
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
	myObj newObj();

	int y = newObj.get();

	if (y == 5)
	{
		print("Success!\n\0");
        newObj.__exit();
	};
    (void)newObj;
	return 0;
};