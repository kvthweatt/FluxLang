#import "standard.fx";

using standard::io::console;

def main() -> int
{
	byte[] some_bytecode = [0x48, 0x31, 0xC0, 0xC3];  // xor rax,rax ; ret
	def{}* fp()->void = @some_bytecode;
	fp();
	
	return 0;
};