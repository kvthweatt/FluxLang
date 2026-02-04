#import "standard.fx";

#import "string_object_raw.fx";


def main() -> int
{
    string s("Test 1!\0");

    s.set("Testing strings!\0");
    print(s.val());
    print();

    s.__exit();
	return 0;
};