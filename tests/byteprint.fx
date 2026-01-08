// You can write files sneakily by piping output to a file.
//
// This prints the bytes 0x00, 0x01, 0x02, 0x03
// Doing the following:
//
// byteprint > file.txt
//
// Voila!
//

import "standard.fx";

def main() -> int
{
    // prints ABCD
	char[4] x = [0x41, 0x42, 0x43, 0x44];
	for (int c = 0; c <= 3; c++)
	{
		win_print(@x[c], 1);
	};
	return 0;
};