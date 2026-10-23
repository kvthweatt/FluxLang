#import <standard.fx>;

using standard::io::console;

// varop.fx - Variadic Operator example

operator(...) [##] -> void
{
    println(f"Operator count:    {##}");
    println(f"Operand count:     {...}");
    println(f"Is {$##} leading:  " + "true" if (##.is_leading) else "false");
    println(f"Is {$##} trailing: " + "true" if (##.is_trailing) else "false");
};

main() -> int
{
    ## 0 ## 1 ## 2 ## 3 ##;
    -> 0;
};