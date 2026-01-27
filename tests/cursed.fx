#import "standard.fx";

def main() -> int
{
    // Pack "HELL" into an integer
    int cursed = (int)"HELL\0";
    
    // Cast that integer to a pointer
    volatile char* demon = (@)0xDEADBEEF;
    
    // Take the address of the pointer itself
    int** void_ptr = (int**)@demon;
    
    // Dereference through the chaos
    //int sacrificed = @void_ptr;    // Causes another i32* != i32*
    //int* sacrificed = *sacrificed;
    
    // Array comprehension that does nothing useful
    int[5] summoning = [i * cursed for (int i in [0, 1, 2, 3, 4])];
    
    // Reinterpret the array as a single integer // Data lost
    int portal = (int)summoning;
    
    // Cast the portal back to a pointer and dereference
    int* gateway = (@)portal;
    
    // Void cast to free something that was never allocated
    (void)gateway;
    
    // If we somehow survived
    if ((int)demon == 0xDEADBEEF)
    {
        print("CURSED\0");
    };
    
    return 0dCURSED;
};