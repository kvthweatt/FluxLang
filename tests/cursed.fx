#import "standard.fx";

#import "redmath.fx";

def main() -> int
{
    // Pack "HELL" into an integer
    int cursed = (int)"HELL";
    
    // Cast that integer to a pointer
    volatile int demon = 0xDEADBEEF;
    
    // Take the address of the pointer itself
    int** void_ptr = (int**)@demon;
    u32 demon = (u32)['H','E','L','L'];
    
    // Dereference through the chaos
    //int sacrificed = @void_ptr;    // Causes another i32* != i32*
    //int* sacrificed = *sacrificed;
    
    // Array comprehension that does nothing useful
    int[5] summoning = [i for (int i in [0, 1, demon, 3, 4])];
    
    // Reinterpret the array as a single integer // Data lost
    int portal = summoning[2];
    
    // Cast the portal back to a pointer and dereference
    int* gateway = (@)portal;
    
    // Void cast to free something that was never allocated
    (void)gateway;
    
    // If we somehow survived
    if (portal == 0xDEADBEEF)
    {
        print("CURSED\0");
    };
    
    return 0dCURSED;
};