#import "standard.fx";

using standard::io::console;

object Lock
{
    bool status = false;  // We'll treat false as unlocked, true as locked.

    def __init() -> this
    {
        print("Created a new lock.\n");
        return this;
    };

    def __exit() -> void
    {
        print("Lock destroyed.\n");
        return;
    };

    def doThis() -> int
    {
        if (this.status)
        {
            //print("Error: Locked.\n");
            return -1;
        };
        print("Doing this!\n");
        return 0;
    };

    def lock() -> bool
    {
        this.status = true;
        print("Status: Locked.\n");
        return;
    };

    def unlock() -> bool
    {
        this.status = false;
        print("Status: Unlocked.\n");
        return;
    };
};

def main() -> int
{
    Lock myNewLock();

    myNewLock.doThis();
    myNewLock.lock();
    myNewLock.doThis();
    myNewLock.unlock();
    myNewLock.doThis();

    return 0;
};