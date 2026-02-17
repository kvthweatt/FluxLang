#import "standard.fx";

namespace standard
{
    namespace collections
    {
        // ===== DYNAMIC ARRAY =====
        object Array
        {
            void** items;
            size_t size, capacity;
            
            def __init() -> this
            {
                this.capacity = (size_t)16;
                this.size = (size_t)0;
                this.items = (void**)malloc(this.capacity * sizeof(void*));
                return this;
            };
            
            def __init(size_t initial_capacity) -> this
            {
                this.capacity = initial_capacity;
                this.size = (size_t)0;
                this.items = (void**)malloc(this.capacity * sizeof(void*));
                return this;
            };
            
            def __exit() -> void
            {
                if (this.items != (void**)0)
                {
                    free(this.items);
                };
                return;
            };
            
            def get_size() -> size_t
            {
                return this.size;
            };
            
            def get_capacity() -> size_t
            {
                return this.capacity;
            };
            
            def is_empty() -> bool
            {
                return this.size == (size_t)0;
            };
            
            def resize() -> bool
            {
                size_t new_capacity = this.capacity * (size_t)2;
                void** new_items = (void**)realloc(this.items, new_capacity * sizeof(void*));
                
                if (new_items == (void**)0)
                {
                    return false;
                };
                
                this.items = new_items;
                this.capacity = new_capacity;
                return true;
            };
            
            def push(void* item) -> bool
            {
                if (this.size >= this.capacity)
                {
                    if (!this.resize())
                    {
                        return false;
                    };
                };
                
                this.items[this.size] = item;
                this.size++;
                return true;
            };
            
            def pop() -> void*
            {
                if (this.size == (size_t)0)
                {
                    return (void*)0;
                };
                
                this.size--;
                return (void*)this.items[this.size];
            };
            
            def get(size_t index) -> void*
            {
                if (index >= this.size)
                {
                    return (void*)0;
                };
                
                return (void*)this.items[index];
            };
            
            def set(size_t index, void* item) -> bool
            {
                if (index >= this.size)
                {
                    return false;
                };
                
                this.items[index] = item;
                return true;
            };
            
            def clear() -> void
            {
                this.size = (size_t)0;
            };
            
            def remove_at(size_t index) -> bool
            {
                if (index >= this.size)
                {
                    return false;
                };
                
                // Shift elements left
                for (size_t i = index; i < this.size - (size_t)1; i++)
                {
                    this.items[i] = this.items[i + (size_t)1];
                };
                
                this.size--;
                return true;
            };
            
            def insert_at(size_t index, void* item) -> bool
            {
                if (index > this.size)
                {
                    return false;
                };
                
                if (this.size >= this.capacity)
                {
                    if (!this.resize())
                    {
                        return false;
                    };
                };
                
                // Shift elements right
                for (size_t i = this.size; i > index; i--)
                {
                    this.items[i] = this.items[i - (size_t)1];
                };
                
                this.items[index] = item;
                this.size++;
                return true;
            };
        };
    };
};

def main() -> int
{
    // ===== CONSTRUCTION =====
    print("--- Construction ---\n\0");
    Array arr;
    arr.__init();

    print("size:     \0");
    print((int)arr.get_size());
    print("\n\0");
    print("capacity: \0");
    print((int)arr.get_capacity());
    print("\n\0");
    print("empty:    \0");
    print(arr.is_empty());
    print("\n\0");

    // ===== PUSH =====
    print("--- Push 5 items ---\n\0");
    int a = 10;
    int b = 20;
    int c = 30;
    int d = 40;
    int e = 50;
    arr.push((void*)@a);
    arr.push((void*)@b);
    arr.push((void*)@c);
    arr.push((void*)@d);
    arr.push((void*)@e);

    print("size:  \0");
    print((int)arr.get_size());
    print("\n\0");
    print("empty: \0");
    print(arr.is_empty());
    print("\n\0");

    // ===== GET =====
    print("--- Get by index ---\n\0");
    for (size_t i = (size_t)0; i < arr.get_size(); i++)
    {
        void* ptr = arr.get(i);
        int val = *(int*)ptr;
        print("  [\0");
        print((int)i);
        print("] = \0");
        print(val);
        print("\n\0");
    };

    // ===== SET =====
    print("--- Set index 2 = 999 ---\n\0");
    int replacement = 999;
    arr.set((size_t)2, (void*)@replacement);
    void* ptr2 = arr.get((size_t)2);
    print("  [2] = \0");
    print(*(int*)ptr2);
    print("\n\0");

    // ===== REMOVE_AT =====
    print("--- Remove index 1 ---\n\0");
    arr.remove_at((size_t)1);
    print("size after remove: \0");
    print((int)arr.get_size());
    print("\n\0");
    print("remaining: \0");
    for (size_t i = (size_t)0; i < arr.get_size(); i++)
    {
        int val = *(int*)arr.get(i);
        print(val);
        print(" \0");
    };
    print("\n\0");

    // ===== INSERT_AT =====
    print("--- Insert 77 at index 0 ---\n\0");
    int ins = 77;
    arr.insert_at((size_t)0, (void*)@ins);
    print("size after insert: \0");
    print((int)arr.get_size());
    print("\n\0");
    print("items: \0");
    for (size_t i = (size_t)0; i < arr.get_size(); i++)
    {
        int val = *(int*)arr.get(i);
        print(val);
        print(" \0");
    };
    print("\n\0");

    // ===== RESIZE =====
    print("--- Fill past initial capacity (16) ---\n\0");
    Array big;
    big.__init((size_t)4);
    int[20] vals = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
    for (size_t i = (size_t)0; i < (size_t)20; i++)
    {
        big.push((void*)@vals[i]);
    };
    print("size:     \0");
    print((int)big.get_size());
    print("\n\0");
    print("capacity: \0");
    print((int)big.get_capacity());
    print("\n\0");

    // ===== POP =====
    print("--- Pop ---\n\0");
    void* popped = big.pop();
    print("popped: \0");
    print(*(int*)popped);
    print("\n\0");
    print("size after pop: \0");
    print((int)big.get_size());
    print("\n\0");

    // ===== CLEAR =====
    print("--- Clear ---\n\0");
    arr.clear();
    print("size after clear: \0");
    print((int)arr.get_size());
    print("\n\0");
    print("empty after clear: \0");
    print(arr.is_empty());
    print("\n\0");

    // ===== CLEANUP =====
    arr.__exit();
    big.__exit();

    print("--- Done ---\n\0");
    return 0;
};