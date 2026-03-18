#import "standard.fx";

using standard::io::console;

def main() -> int
{
    defer print("Last!\n\0");
	defer print("Second!\n\0");
	print("First!\n\0");
	return 0;
};