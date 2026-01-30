#import "standard.fx";

def main() -> int
{
	try
	{
		print("Testing!\n\0");
		throw(5);
	}
	catch (int err)
	{
		print(err);
		print();
	};

	return 0;
};