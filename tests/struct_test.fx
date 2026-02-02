#import "standard.fx";

struct myStru
{
	int x,y,z;
};

struct bits
{
    unsigned data{1} a,b,c,d,e,f,g,h;
};

def main() -> int
{
	myStru newStru = {0,1,2};

    if (newStru.y is true and sizeof(newStru) == 96 and sizeof(bits) == 8)
    {
        print("Structs working!\n\0");
        print("Size of newStru: \0");
        print(sizeof(newStru));
    };
	return 0;
};