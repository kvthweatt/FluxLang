object myObj
{
	def __init() -> this
	{
	    return this;
	};

	def __exit() -> void
	{
	    return void;
	};

	def foo() -> void
	{
		return void;
	};
};

def main() -> int
{
	myObj newObj();

	newObj.foo();
	
	return 0;
};