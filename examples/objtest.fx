object Counter
{
    int count = 0;

    def __init() -> this
    {
        this.count = 0;
        return this;
    };

    def increment() -> void
    {
        this.count++;
    };

    def __exit() -> void
    {
        return void;
    };
};

def main() -> int {
    Counter myCounter();
    myCounter.increment();
    myCounter.__exit();  // Explicit destruction
    return 0;
};