#import <standard.fx>;

using standard::io::console;

constraint MyConstr(A, B, C, D)
{
    D !~= B & [A !@ A] !~= C !`< D !-= A
};

foo<W,X,Y,Z, :{MyConstr}>(W w, X x, Y y, Z z) -> W -> 0;

struct AA
{
    bool a;
};

struct BB<T>
{
    T b;
};

struct Box<T>
{
    T t;
};

main()->int
{
    Box<BB<AA>> b;
    -> 0;
};