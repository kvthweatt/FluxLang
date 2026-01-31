#import "standard.fx";

def main() -> int
{
    int a = noinit; // No initialized value

    uint x, y = 10, 0;

    uint* px, py = @x, @y;

    // A pointer is simply a variable and its value is an address
    // An address is a number.
    // Therefore, we can store that address
    // 
    uint kx = px;

    // (@) is address-cast. It reinterprets the number as an address
    // When we treat a number as an address, we call that a pointer.
    // Therefore, we can assign this to another pointer.
    //
    py = (@)kx;

    // py now points to x

    // Dereference py to get the value at the address
    // Cast to make sure it's the proper type to print

    if (x == 10 & y == 0 & *py == x & px == py & px == (@)kx)
    {
        print("Success, y unchanged, py points to x.\n\0");
        print((uint)*py);
    };

	return 0;
};