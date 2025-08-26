import "redio.fx";

using standard::io;

def main() -> int
{
    noopstr str = "Hello World!";
    int len = sizeof(str) / 8;
    
    win_print(@str, len);
    wpnl();
    
    return 0;
};