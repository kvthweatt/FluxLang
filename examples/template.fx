#import "standard.fx";


def foo<T>(T x) -> T
{
    return x;
};


def main() -> int
{
    float y = foo<float>(5.5f);
    int z = foo<int>(3);

    print(y); print();
    print(z); print();

    system("pause\0");
    return 0;
};