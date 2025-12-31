import "standard.fx";

using standard::io;

def main() -> int
{
    noopstr s = "TEST";
    noopstr* ps = @s;
    s as void;
    
    print(@(**ps),4);
    wpnl();

    return 0;
};