// async_bc_test.fx

// One allocation: [0, 1024) is the input signal, [1024, 2048) is the output.
// Each worker reads a window that overlaps its neighbours' windows (a halo of
// one element on each side) and writes only its own slice of the output half.
// 

#import <standard.fx>, <threading.fx>;

using standard::io::console;

// smooth must finish before total starts.
async After(a, b)
{
    b > a;
};

async smooth(i32* arena, i32 lo, i32 hi) -> void
{
    i32 i = lo;
    while (i < hi)
    {
        arena[1024 + i] = arena[i - 1] + arena[i] + arena[i + 1];
        i++;
    };
};

async total(i32* arena, i32 lo, i32 hi) -> i64
{
    i64 t;
    i32 i = lo;
    while (i < hi)
    {
        t = t + arena[1024 + i++];
    };
    return t;
} #<After>(this, smooth);

main() -> int
{
    i32[2048] arena;
    
    i32 i;
    while (i < 1024) { arena[i++] = 1; };

    smooth(@arena[0], 1, 256);
    smooth(@arena[0], 256, 512);
    smooth(@arena[0], 512, 768);
    smooth(@arena[0], 768, 1023);

    i64 s = total(@arena[0], 1, 1023);

    if (s != (i64)3066) { return 1; };
    return 0;
};