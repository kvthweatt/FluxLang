import "redio.fx";

using standard::io;

def main() -> int
{
    int age = 27;
    noopstr str = f"I'm {age}.";
    int len = sizeof(*str) / 8;
    
    win_print(@str, 6);
    wpnl();
    
    return 0;
};