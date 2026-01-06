import "redstandard.fx";

if(!def(TESTING)) { def TESTING 1; };

def main() -> int
{
    if(def(TESTING)) { win_print("GOOD",4); };
    return 0;
};