#import "redstandard.fx";
#import "redallocators.fx";
#import "redformat.fx";

using standard::format;

object Stack
{
    int* xdat;
    int capacity;
    int top;
    
    def __init(int size) -> this
    {
        this.capacity = size;
        this.top = -1;
        this.xdat = (int*)fmalloc((size_t)(size * 4));
        
        if (this.xdat == (int*)0) 
        {
            print_error("Failed to allocate stack\0");
            this.capacity = 0;
        };
        
        return this;
    };
    
    def __exit() -> void
    {
        if (this.xdat != (int*)0) 
        {
            ffree((u64)this.xdat);
        };
    };
    
    def push(int value) -> bool
    {
        if (this.top >= this.capacity - 1) 
        {
            print_warning("Stack overflow\0");
            return false;
        };
        
        this.top = this.top + 1;
        this.xdat[this.top] = value;
        return true;
    };
    
    def pop() -> int
    {
        if (this.is_empty()) 
        {
            print_warning("Stack underflow\0");
            return 0;
        };
        
        int value = this.xdat[this.top];
        this.top = this.top - 1;
        return value;
    };
    
    def peek() -> int
    {
        if (this.is_empty()) 
        {
            print_warning("Stack is empty\0");
            return 0;
        };
        
        return this.xdat[this.top];
    };
    
    def is_empty() -> bool
    {
        if (this.top < 0) 
        {
            return true;
        };
        return false;
    };
    
    def is_full() -> bool
    {
        if (this.top >= this.capacity - 1) 
        {
            return true;
        };
        return false;
    };
    
    def size() -> int
    {
        return this.top + 1;
    };
    
    def display() -> void
    {
        if (this.is_empty()) 
        {
            print_warning("Stack is empty\0");
            return;
        };
        
        print("Stack (top to bottom): \0");
        
        for (int i = this.top; i >= 0; i--)
        {
            print(this.xdat[i]);
            
            if (i > 0) 
            {
                print(" -> \0");
            };
        };
        
        print("\n\0");
    };
};

def main() -> int
{
    print_banner("Stack Implementation\0", 40);
    
    Stack stk(5);
    
    print_info("Pushing values onto stack:\0");
    
    for (int i = 1; i <= 5; i++)
    {
        if (stk.push(i * 10)) 
        {
            print("Pushed: \0");
            print(i * 10);
            print("\n\0");
        };
    };
    
    // Try to push when full
    if (!stk.push(60)) 
    {
        print_warning("Could not push 60 (stack full)\0");
    };
    
    print("\n\0");
    stk.display();
    
    print_info("Top element: \0");
    print(stk.peek());
    print();
    
    print_info("Popping elements:");
    while (!stk.is_empty())
    {
        int value = stk.pop();
        print("Popped: \0");
        print(value);
        print();
    };
    
    // Try to pop when empty
    int empty_pop = stk.pop();
    
    return 0;
};