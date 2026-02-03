def r1(int x) -> int { return x; };
def r2(int x) -> int { return x; };


int x = {a / b} <:- (int a:foo(), int b:bar());


int x = 4 * r1()
    <-
    {2; :(1) * :(2);}
    <-1u:r1()
    <-2u:r2(256);



def main() -> int
{
	return 0;
};