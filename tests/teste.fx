#import "standard.fx";

using standard::io::console;

def main() -> int
{
    char[] word = ['F','l','u','x','\0'];
    

    println(f"First character value: {word[0]}");
    
    println(f"Second character value: {word[1]}");

    println(f"First character: {(byte[1])word[0]}");
    
    println(f"Second character: {(byte[2])word[2:3]}");
    
    return 0;
};