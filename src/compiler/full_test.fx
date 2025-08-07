import "standard.fx";

using standard::types;

struct myStruct
{
};

object myObject
{
    def __init() -> this
    {
        return this;
    };
    
    def __exit() -> void
    {
        return void;
    };
};

myStruct newStruct;

myObject newObject;

union myUnion
{
};

myUnion newUnion;

def main() -> int
{
    return 0;
};