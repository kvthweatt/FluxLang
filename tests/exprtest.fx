#import "standard.fx";

using standard::io::console,
      standard::strings;

def main() -> int
{
    string str = "hello";

    str.printval(); print();
    println(str.val());
    println(str);
    println(str[str.len()-1:0]);
    println("ll" in str.val());
    println("ll" in str);

    return 0;
};