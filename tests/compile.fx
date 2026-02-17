#import "standard.fx";

def main(int argc, byte** argv) -> int
{
    if (argc > 2)
    {
        print("Too many arguments given.
Usage: compile program.fx

Invokes Python on the Flux compiler backend on program.fx\0");
        return 0;
    }
    else if (argc == 2)
    {
        string command("python fc.py \0");
        if (command.append(argv[1]))
        {
            system(command.val());
        }
        else
        {
            print("Failed to append command line argument.\n\0");
            return 1;
        };
        return 0;
    }
    else if (argc == 0)
    {
        print("Mock Flux Compiler, written in Flux. Calls Python on the Flux compiler.
Usage: compile program.fx\0");
        return 0;
    };

    return 0;
};