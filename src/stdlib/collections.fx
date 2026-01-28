// redcollections.fx - Common data structures for the reduced specification
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_IO
#import "redio.fx";
#endif;

#ifndef FLUX_STANDARD_COLLECTIONS
#def FLUX_STANDARD_COLLECTIONS 1;
#endif;

namespace standard
{
    namespace collections
    {
        // Helper function for memory allocation (simplified)
        def malloc(i64 size) -> i64*
        {
            // In reduced spec, we'll use inline assembly for malloc
            #ifdef __WINDOWS__
            #ifdef __ARCH_X86_64__
            i64* result = 0;
            volatile asm
            {
                movq $0, %rcx           // size parameter
                subq $$32, %rsp
                call malloc
                addq $$32, %rsp
                movq %rax, $1           // store result
            } : : "r"(size), "m"(result) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
            return result;
            #endif;
            #else
            // Linux/Mac - using brk/sbrk for simplicity in reduced spec
            // For now, return null pointer
            return (i64*)0;
            #endif;
        };
        
        def free(i64* ptr) -> void
        {
            if (ptr == (i64*)0) return void;
            
            #ifdef __WINDOWS__
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                movq $0, %rcx           // ptr parameter
                subq $$32, %rsp
                call free
                addq $$32, %rsp
            } : : "r"(ptr) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
            #endif;
            #endif;
            return void;
        };
        
        // Dynamic array (like std::vector in C++)
        object Array
        {
            i64* data;
            i64 capacity;
            i64 size;
            
            def __init() -> this
            {
                this.data = (i64*)0;
                this.capacity = 0;
                this.size = 0;
                return this;
            };
            
            def __exit() -> void
            {
                if (this.data != (i64*)0)
                {
                    free(this.data);
                };
                return void;
            };
            
            def grow() -> void
            {
                if (this.capacity == 0)
                {
                    this.capacity = 4;
                    this.data = malloc(this.capacity * 8);  // sizeof(i64) = 8
                }
                else
                {
                    i64 new_capacity = this.capacity * 2;
                    i64* new_data = malloc(new_capacity * 8);
                    
                    // Copy existing data
                    for (i64 i = 0; i < this.size; i++)
                    {
                        new_data[i] = this.data[i];
                    };
                    
                    if (this.data != (i64*)0)
                    {
                        free(this.data);
                    };
                    
                    this.data = new_data;
                    this.capacity = new_capacity;
                };
            };
            
            def push_back(i64 value) -> void
            {
                if (this.size >= this.capacity)
                {
                    this.grow();
                };
                
                this.data[this.size] = value;
                this.size++;
            };
            
            def pop_back() -> i64
            {
                if (this.size == 0)
                {
                    return 0;
                };
                
                this.size--;
                return this.data[this.size];
            };
            
            def get(i64 index) -> i64
            {
                if (index < 0 || index >= this.size)
                {
                    return 0;
                };
                
                return this.data[index];
            };
            
            def set(i64 index, i64 value) -> void
            {
                if (index < 0 || index >= this.size)
                {
                    return void;
                };
                
                this.data[index] = value;
            };
            
            def length() -> i64
            {
                return this.size;
            };
            
            def clear() -> void
            {
                this.size = 0;
            };
            
            def is_empty() -> bool
            {
                return this.size == 0;
            };
        };
        
        // Simple string builder (mutable string)
        object StringBuilder
        {
            byte* buffer;
            i64 capacity;
            i64 length;
            
            def __init() -> this
            {
                this.buffer = (byte*)0;
                this.capacity = 0;
                this.length = 0;
                return this;
            };
            
            def __exit() -> void
            {
                if (this.buffer != (byte*)0)
                {
                    free((i64*)this.buffer);
                };
                return void;
            };
            
            def ensure_capacity(i64 needed) -> void
            {
                if (this.capacity >= needed) return void;
                
                i64 new_capacity = this.capacity == 0 ? 32 : this.capacity * 2;
                while (new_capacity < needed)
                {
                    new_capacity *= 2;
                };
                
                byte* new_buffer = (byte*)malloc(new_capacity);
                
                // Copy existing data
                for (i64 i = 0; i < this.length; i++)
                {
                    new_buffer[i] = this.buffer[i];
                };
                
                if (this.buffer != (byte*)0)
                {
                    free((i64*)this.buffer);
                };
                
                this.buffer = new_buffer;
                this.capacity = new_capacity;
            };
            
            def append(noopstr str) -> void
            {
                i64 str_len = 0;
                while (str[str_len] != 0)
                {
                    str_len++;
                };
                
                this.ensure_capacity(this.length + str_len + 1);
                
                for (i64 i = 0; i < str_len; i++)
                {
                    this.buffer[this.length + i] = str[i];
                };
                
                this.length += str_len;
                this.buffer[this.length] = 0;  // Null terminator
            };
            
            def append_char(byte ch) -> void
            {
                this.ensure_capacity(this.length + 2);
                this.buffer[this.length] = ch;
                this.length++;
                this.buffer[this.length] = 0;
            };
            
            def clear() -> void
            {
                this.length = 0;
                if (this.buffer != (byte*)0)
                {
                    this.buffer[0] = 0;
                };
            };
            
            def to_string() -> noopstr
            {
                if (this.buffer == (byte*)0)
                {
                    return "\0";
                };
                return this.buffer;
            };
            
            def get_length() -> i64
            {
                return this.length;
            };
        };
        
        // Key-Value pair for HashTable
        struct KVPair
        {
            noopstr key;
            i64 value;
        };
        
        // Simple hash table (string -> i64)
        object HashTable
        {
            KVPair* buckets;
            i64 bucket_count;
            i64 item_count;
            
            def __init() -> this
            {
                this.bucket_count = 16;
                this.buckets = (KVPair*)malloc(this.bucket_count * 24);  // sizeof(KVPair) = 8 + 8 + padding
                this.item_count = 0;
                
                // Initialize buckets
                for (i64 i = 0; i < this.bucket_count; i++)
                {
                    this.buckets[i].key = (noopstr)0;
                    this.buckets[i].value = 0;
                };
                
                return this;
            };
            
            def __exit() -> void
            {
                if (this.buckets != (KVPair*)0)
                {
                    free((i64*)this.buckets);
                };
                return void;
            };
            
            def hash_string(noopstr str) -> i64
            {
                i64 hash = 5381;
                i64 i = 0;
                
                while (str[i] != 0)
                {
                    hash = ((hash << 5) + hash) + str[i];  // hash * 33 + c
                    i++;
                };
                
                return hash;
            };
            
            def rehash() -> void
            {
                i64 old_count = this.bucket_count;
                KVPair* old_buckets = this.buckets;
                
                this.bucket_count *= 2;
                this.buckets = (KVPair*)malloc(this.bucket_count * 24);
                this.item_count = 0;
                
                // Initialize new buckets
                for (i64 i = 0; i < this.bucket_count; i++)
                {
                    this.buckets[i].key = (noopstr)0;
                    this.buckets[i].value = 0;
                };
                
                // Reinsert all items
                for (i64 i = 0; i < old_count; i++)
                {
                    if (old_buckets[i].key != (noopstr)0 && old_buckets[i].key[0] != 0)
                    {
                        this.set(old_buckets[i].key, old_buckets[i].value);
                    };
                };
                
                free((i64*)old_buckets);
            };
            
            def set(noopstr key, i64 value) -> void
            {
                // Check load factor
                if (this.item_count * 4 > this.bucket_count * 3)  // 75% load factor
                {
                    this.rehash();
                };
                
                i64 hash = this.hash_string(key);
                i64 index = hash % this.bucket_count;
                
                // Linear probing
                while (this.buckets[index].key != (noopstr)0 && 
                       this.buckets[index].key[0] != 0)
                {
                    // Check if key matches
                    i64 i = 0;
                    bool match = true;
                    while (key[i] != 0 && this.buckets[index].key[i] != 0)
                    {
                        if (key[i] != this.buckets[index].key[i])
                        {
                            match = false;
                            break;
                        };
                        i++;
                    };
                    
                    if (match && key[i] == 0 && this.buckets[index].key[i] == 0)
                    {
                        // Update existing key
                        this.buckets[index].value = value;
                        return void;
                    };
                    
                    index = (index + 1) % this.bucket_count;
                };
                
                // Insert new key
                this.buckets[index].key = key;
                this.buckets[index].value = value;
                this.item_count++;
            };
            
            def get(noopstr key) -> i64
            {
                i64 hash = this.hash_string(key);
                i64 index = hash % this.bucket_count;
                i64 start_index = index;
                
                while (this.buckets[index].key != (noopstr)0)
                {
                    // Check if key matches
                    i64 i = 0;
                    bool match = true;
                    while (key[i] != 0 && this.buckets[index].key[i] != 0)
                    {
                        if (key[i] != this.buckets[index].key[i])
                        {
                            match = false;
                            break;
                        };
                        i++;
                    };
                    
                    if (match && key[i] == 0 && this.buckets[index].key[i] == 0)
                    {
                        return this.buckets[index].value;
                    };
                    
                    index = (index + 1) % this.bucket_count;
                    if (index == start_index)
                    {
                        break;
                    };
                };
                
                return 0;  // Not found
            };
            
            def contains(noopstr key) -> bool
            {
                return this.get(key) != 0;
            };
            
            def remove(noopstr key) -> void
            {
                i64 hash = this.hash_string(key);
                i64 index = hash % this.bucket_count;
                i64 start_index = index;
                
                while (this.buckets[index].key != (noopstr)0)
                {
                    // Check if key matches
                    i64 i = 0;
                    bool match = true;
                    while (key[i] != 0 && this.buckets[index].key[i] != 0)
                    {
                        if (key[i] != this.buckets[index].key[i])
                        {
                            match = false;
                            break;
                        };
                        i++;
                    };
                    
                    if (match && key[i] == 0 && this.buckets[index].key[i] == 0)
                    {
                        // Mark as deleted (empty string)
                        this.buckets[index].key = "\0";
                        this.buckets[index].value = 0;
                        this.item_count--;
                        return void;
                    };
                    
                    index = (index + 1) % this.bucket_count;
                    if (index == start_index)
                    {
                        break;
                    };
                };
            };
            
            def count() -> i64
            {
                return this.item_count;
            };
            
            def clear() -> void
            {
                for (i64 i = 0; i < this.bucket_count; i++)
                {
                    this.buckets[i].key = (noopstr)0;
                    this.buckets[i].value = 0;
                };
                this.item_count = 0;
            };
        };
        
        // Stack (LIFO) data structure
        object Stack
        {
            Array data;
            
            def __init() -> this
            {
                this.data = Array();
                return this;
            };
            
            def __exit() -> void
            {
                this.data.__exit();
                return void;
            };
            
            def push(i64 value) -> void
            {
                this.data.push_back(value);
            };
            
            def pop() -> i64
            {
                if (this.data.is_empty())
                {
                    return 0;
                };
                
                return this.data.pop_back();
            };
            
            def peek() -> i64
            {
                if (this.data.is_empty())
                {
                    return 0;
                };
                
                return this.data.get(this.data.length() - 1);
            };
            
            def is_empty() -> bool
            {
                return this.data.is_empty();
            };
            
            def size() -> i64
            {
                return this.data.length();
            };
            
            def clear() -> void
            {
                this.data.clear();
            };
        };
        
        // Queue (FIFO) data structure
        object Queue
        {
            Array data;
            i64 head;
            i64 tail;
            
            def __init() -> this
            {
                this.data = Array();
                this.head = 0;
                this.tail = 0;
                return this;
            };
            
            def __exit() -> void
            {
                this.data.__exit();
                return void;
            };
            
            def enqueue(i64 value) -> void
            {
                this.data.push_back(value);
                this.tail++;
            };
            
            def dequeue() -> i64
            {
                if (this.head >= this.tail)
                {
                    return 0;
                };
                
                i64 value = this.data.get(this.head);
                this.head++;
                
                // Compact if queue is half empty
                if (this.head > this.data.length() / 2)
                {
                    // Shift elements down
                    i64 new_length = this.tail - this.head;
                    for (i64 i = 0; i < new_length; i++)
                    {
                        this.data.set(i, this.data.get(this.head + i));
                    };
                    this.head = 0;
                    this.tail = new_length;
                    this.data.size = new_length;
                };
                
                return value;
            };
            
            def front() -> i64
            {
                if (this.head >= this.tail)
                {
                    return 0;
                };
                
                return this.data.get(this.head);
            };
            
            def is_empty() -> bool
            {
                return this.head >= this.tail;
            };
            
            def size() -> i64
            {
                return this.tail - this.head;
            };
            
            def clear() -> void
            {
                this.data.clear();
                this.head = 0;
                this.tail = 0;
            };
        };
    };
};

using standard::collections;