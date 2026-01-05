import "redstandard.fx";

using standard::io::console;

// Fix pathing because this is ridiculous
import "redfrt.fx"; // Reduced-spec 'red' Flux Runtime

def main() -> int
{
	assert(0!=0, "ERROR"); // Guaranteed to throw
    // Updated to support assert(bool, string);
    // We don't want to have to type 0!=0 every time, 0 is sufficient (false).
	return 0;
};