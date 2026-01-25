#import "redstandard.fx";


def foo(bool* src, bool* dst) -> void
{
	*dst = *src;
	return void;
};


def main() -> int
{
	bool x = true;
	bool y = false;

	bool* px = @x;
	bool* py = @y;

	foo(px,py);

	if (!*py `| !y)
	{
		print("y unchanged",11);
	}
    else
    {
        print("y changed",9);
    };
	return 0;
};