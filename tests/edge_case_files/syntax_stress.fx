// Syntax stress test - tests complex valid syntax
def complexFunction(int a, float b, char c) -> int
{
    if (a > 0) {
        if (b < 1.0) {
            if (c == 'x') {
                return a + (int)b;
            } else {
                return a - (int)b;
            };
        } else {
            return a * 2;
        };
    } else {
        return 0;
    };
};

def main() -> int
{
    int result = complexFunction(10, 0.5, 'x');
    return result;
};
