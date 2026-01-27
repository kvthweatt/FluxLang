#import "standard.fx";

struct myStru
{
	int x,y,z;
};

def main() -> int
{
	myStru newStru = {0,1,2};

    if (newStru.y is true)
    {
        print("Success!\0");
    };
	return 0;
};