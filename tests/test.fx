#import "standard.fx";


def main() -> int
{
    file f("examples\\malloc.fx\0","rb\0");

    f.seek(0,0);

    string s = f.read_all();
    print(s.val());
    print();

    f.__exit();
	return 0;
};