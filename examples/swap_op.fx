#import "standard.fx", "operators.fx";

using standard::io::console,
      standard::operators;

def main() -> int
{
    int a = 5, b = 10;

    @a <> @b;

    print(a); print();
    print(b); print();
    return 0;
};