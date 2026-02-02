#import "redstandard.fx";


def foo(bool* src, bool* dst) -> void
{
	dst = src;
	return;
};


def main() -> int
{
	bool x = true;
	bool y = false;

	bool* px = @x;
	bool* py = @y;

	foo(px,py);

	if (!*py or !y)
	{
		print("y unchanged\0");
	}
    else
    {
        print("y changed\0");
    };
	return 0;
};