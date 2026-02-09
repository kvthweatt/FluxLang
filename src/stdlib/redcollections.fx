# Flux Collections Library
// redcollections.fx - Data structure implementations for Flux

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import "redmemory.fx";
#endif;

#ifndef FLUX_STANDARD_COLLECTIONS
#def FLUX_STANDARD_COLLECTIONS 1;

namespace standard
{
    namespace collections
    {
        // ===== DYNAMIC ARRAY =====
        object Array
        {
            void** items;
            size_t size;
            size_t capacity;
            
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
                return this.items[this.size];
            };
            
            def get(size_t index) -> void*
            {
                if (index >= this.size)
                {
                    return (void*)0;
                };
                
                return this.items[index];
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
        
        // ===== LINKED LIST NODE =====
        struct LinkedListNode
        {
            void* payload;
            LinkedListNode* next;
            LinkedListNode* prev;
        };
        
        // ===== DOUBLY LINKED LIST =====
        object LinkedList
        {
            LinkedListNode* head;
            LinkedListNode* tail;
            size_t size;
            
            def __init() -> this
            {
                this.head = (LinkedListNode*)0;
                this.tail = (LinkedListNode*)0;
                this.size = (size_t)0;
                return this;
            };
            
            def __exit() -> void
            {
                this.clear();
                return;
            };
            
            def get_size() -> size_t
            {
                return this.size;
            };
            
            def is_empty() -> bool
            {
                return this.size == (size_t)0;
            };
            
            def push_front(void* item) -> bool
            {
                LinkedListNode* node = (LinkedListNode*)malloc(sizeof(LinkedListNode));
                if (node == (LinkedListNode*)0)
                {
                    return false;
                };
                
                node.payload = item;
                node.next = this.head;
                node.prev = (LinkedListNode*)0;
                
                if (this.head != (LinkedListNode*)0)
                {
                    this.head.prev = node;
                }
                else
                {
                    this.tail = node;
                };
                
                this.head = node;
                this.size++;
                return true;
            };
            
            def push_back(void* item) -> bool
            {
                LinkedListNode* node = (LinkedListNode*)malloc(sizeof(LinkedListNode));
                if (node == (LinkedListNode*)0)
                {
                    return false;
                };
                
                node.payload = item;
                node.next = (LinkedListNode*)0;
                node.prev = this.tail;
                
                if (this.tail != (LinkedListNode*)0)
                {
                    this.tail.next = node;
                }
                else
                {
                    this.head = node;
                };
                
                this.tail = node;
                this.size++;
                return true;
            };
            
            def pop_front() -> void*
            {
                if (this.head == (LinkedListNode*)0)
                {
                    return (void*)0;
                };
                
                LinkedListNode* node = this.head;
                void* item = node.payload;
                
                this.head = node.next;
                
                if (this.head != (LinkedListNode*)0)
                {
                    this.head.prev = (LinkedListNode*)0;
                }
                else
                {
                    this.tail = (LinkedListNode*)0;
                };
                
                free(node);
                this.size--;
                return item;
            };
            
            def pop_back() -> void*
            {
                if (this.tail == (LinkedListNode*)0)
                {
                    return (void*)0;
                };
                
                LinkedListNode* node = this.tail;
                void* item = node.payload;
                
                this.tail = node.prev;
                
                if (this.tail != (LinkedListNode*)0)
                {
                    this.tail.next = (LinkedListNode*)0;
                }
                else
                {
                    this.head = (LinkedListNode*)0;
                };
                
                free(node);
                this.size--;
                return item;
            };
            
            def peek_front() -> void*
            {
                if (this.head == (LinkedListNode*)0)
                {
                    return (void*)0;
                };
                
                return this.head.payload;
            };
            
            def peek_back() -> void*
            {
                if (this.tail == (LinkedListNode*)0)
                {
                    return (void*)0;
                };
                
                return this.tail.payload;
            };
            
            def get_at(size_t index) -> void*
            {
                if (index >= this.size)
                {
                    return (void*)0;
                };
                
                LinkedListNode* current = this.head;
                for (size_t i = (size_t)0; i < index; i++)
                {
                    current = current.next;
                };
                
                return current.payload;
            };
            
            def remove_at(size_t index) -> bool
            {
                if (index >= this.size)
                {
                    return false;
                };
                
                if (index == (size_t)0)
                {
                    this.pop_front();
                    return true;
                };
                
                if (index == this.size - (size_t)1)
                {
                    this.pop_back();
                    return true;
                };
                
                LinkedListNode* current = this.head;
                for (size_t i = (size_t)0; i < index; i++)
                {
                    current = current.next;
                };
                
                current.prev.next = current.next;
                current.next.prev = current.prev;
                
                free(current);
                this.size--;
                return true;
            };
            
            def clear() -> void
            {
                while (this.head != (LinkedListNode*)0)
                {
                    this.pop_front();
                };
            };
        };
        
        // ===== QUEUE (FIFO) =====
        object Queue
        {
            LinkedList list;
            
            def __init() -> this
            {
                this.list.__init();
                return this;
            };
            
            def __exit() -> void
            {
                this.list.__exit();
                return;
            };
            
            def enqueue(void* item) -> bool
            {
                return this.list.push_back(item);
            };
            
            def dequeue() -> void*
            {
                return this.list.pop_front();
            };
            
            def peek() -> void*
            {
                return this.list.peek_front();
            };
            
            def get_size() -> size_t
            {
                return this.list.get_size();
            };
            
            def is_empty() -> bool
            {
                return this.list.is_empty();
            };
            
            def clear() -> void
            {
                this.list.clear();
            };
        };
        
        // ===== STACK (LIFO) =====
        object Stack
        {
            DynamicArray array;
            
            def __init() -> this
            {
                this.array.__init();
                return this;
            };
            
            def __exit() -> void
            {
                this.array.__exit();
                return;
            };
            
            def push(void* item) -> bool
            {
                return this.array.push(item);
            };
            
            def pop() -> void*
            {
                return this.array.pop();
            };
            
            def peek() -> void*
            {
                if (this.array.is_empty())
                {
                    return (void*)0;
                };
                
                return this.array.get(this.array.get_size() - (size_t)1);
            };
            
            def get_size() -> size_t
            {
                return this.array.get_size();
            };
            
            def is_empty() -> bool
            {
                return this.array.is_empty();
            };
            
            def clear() -> void
            {
                this.array.clear();
            };
        };
        
        // ===== HASH MAP ENTRY =====
        struct HashMapEntry
        {
            u64 hash;
            void* key;
            void* value;
            HashMapEntry* next;
        };
        
        // ===== HASH MAP =====
        object HashMap
        {
            HashMapEntry** buckets;
            size_t bucket_count;
            size_t size;
            
            def __init() -> this
            {
                this.bucket_count = (size_t)16;
                this.size = (size_t)0;
                this.buckets = (HashMapEntry**)calloc(this.bucket_count, sizeof(HashMapEntry*));
                return this;
            };
            
            def __init(size_t initial_buckets) -> this
            {
                this.bucket_count = initial_buckets;
                this.size = (size_t)0;
                this.buckets = (HashMapEntry**)calloc(this.bucket_count, sizeof(HashMapEntry*));
                return this;
            };
            
            def __exit() -> void
            {
                this.clear();
                if (this.buckets != (HashMapEntry**)0)
                {
                    free(this.buckets);
                };
                return;
            };
            
            def hash_pointer(void* ptr) -> u64
            {
                u64 value = (u64)ptr;
                value = value ^^ (value >> (u64)33);
                value = value * (u64)0xff51afd7ed558ccd;
                value = value ^^ (value >> (u64)33);
                value = value * (u64)0xc4ceb9fe1a85ec53;
                value = value ^^ (value >> (u64)33);
                return value;
            };
            
            def get_size() -> size_t
            {
                return this.size;
            };
            
            def is_empty() -> bool
            {
                return this.size == (size_t)0;
            };
            
            def put(void* key, void* value) -> bool
            {
                u64 hash = this.hash_pointer(key);
                size_t index = (size_t)(hash % (u64)this.bucket_count);
                
                HashMapEntry* entry = this.buckets[index];
                
                // Check if key already exists
                while (entry != (HashMapEntry*)0)
                {
                    if (entry.hash == hash & entry.key == key)
                    {
                        entry.value = value;
                        return true;
                    };
                    entry = entry.next;
                };
                
                // Create new entry
                HashMapEntry* new_entry = (HashMapEntry*)malloc(sizeof(HashMapEntry));
                if (new_entry == (HashMapEntry*)0)
                {
                    return false;
                };
                
                new_entry.hash = hash;
                new_entry.key = key;
                new_entry.value = value;
                new_entry.next = this.buckets[index];
                
                this.buckets[index] = new_entry;
                this.size++;
                return true;
            };
            
            def get(void* key) -> void*
            {
                u64 hash = this.hash_pointer(key);
                size_t index = (size_t)(hash % (u64)this.bucket_count);
                
                HashMapEntry* entry = this.buckets[index];
                
                while (entry != (HashMapEntry*)0)
                {
                    if (entry.hash == hash & entry.key == key)
                    {
                        return entry.value;
                    };
                    entry = entry.next;
                };
                
                return (void*)0;
            };
            
            def contains(void* key) -> bool
            {
                u64 hash = this.hash_pointer(key);
                size_t index = (size_t)(hash % (u64)this.bucket_count);
                
                HashMapEntry* entry = this.buckets[index];
                
                while (entry != (HashMapEntry*)0)
                {
                    if (entry.hash == hash & entry.key == key)
                    {
                        return true;
                    };
                    entry = entry.next;
                };
                
                return false;
            };
            
            def remove(void* key) -> bool
            {
                u64 hash = this.hash_pointer(key);
                size_t index = (size_t)(hash % (u64)this.bucket_count);
                
                HashMapEntry* entry = this.buckets[index];
                HashMapEntry* prev = (HashMapEntry*)0;
                
                while (entry != (HashMapEntry*)0)
                {
                    if (entry.hash == hash & entry.key == key)
                    {
                        if (prev != (HashMapEntry*)0)
                        {
                            prev.next = entry.next;
                        }
                        else
                        {
                            this.buckets[index] = entry.next;
                        };
                        
                        free(entry);
                        this.size--;
                        return true;
                    };
                    
                    prev = entry;
                    entry = entry.next;
                };
                
                return false;
            };
            
            def clear() -> void
            {
                for (size_t i = (size_t)0; i < this.bucket_count; i++)
                {
                    HashMapEntry* entry = this.buckets[i];
                    
                    while (entry != (HashMapEntry*)0)
                    {
                        HashMapEntry* next = entry.next;
                        free(entry);
                        entry = next;
                    };
                    
                    this.buckets[i] = (HashMapEntry*)0;
                };
                
                this.size = (size_t)0;
            };
        };
        
        // ===== BINARY TREE NODE =====
        struct BinaryTreeNode
        {
            void* payload;
            i64 key;
            BinaryTreeNode* left;
            BinaryTreeNode* right;
            BinaryTreeNode* parent;
        };
        
        // ===== BINARY SEARCH TREE =====
        object BinarySearchTree
        {
            BinaryTreeNode* root;
            size_t size;
            
            def __init() -> this
            {
                this.root = (BinaryTreeNode*)0;
                this.size = (size_t)0;
                return this;
            };
            
            def __exit() -> void
            {
                this.clear();
                return;
            };
            
            def get_size() -> size_t
            {
                return this.size;
            };
            
            def is_empty() -> bool
            {
                return this.size == (size_t)0;
            };
            
            def insert(i64 key, void* item) -> bool
            {
                BinaryTreeNode* node = (BinaryTreeNode*)malloc(sizeof(BinaryTreeNode));
                if (node == (BinaryTreeNode*)0)
                {
                    return false;
                };
                
                node.key = key;
                node.payload = item;
                node.left = (BinaryTreeNode*)0;
                node.right = (BinaryTreeNode*)0;
                node.parent = (BinaryTreeNode*)0;
                
                if (this.root == (BinaryTreeNode*)0)
                {
                    this.root = node;
                    this.size++;
                    return true;
                };
                
                BinaryTreeNode* current = this.root;
                BinaryTreeNode* parent = (BinaryTreeNode*)0;
                
                while (current != (BinaryTreeNode*)0)
                {
                    parent = current;
                    
                    if (key < current.key)
                    {
                        current = current.left;
                    }
                    elif (key > current.key)
                    {
                        current = current.right;
                    }
                    else
                    {
                        // Key already exists, update payload
                        current.payload = item;
                        free(node);
                        return true;
                    };
                };
                
                node.parent = parent;
                
                if (key < parent.key)
                {
                    parent.left = node;
                }
                else
                {
                    parent.right = node;
                };
                
                this.size++;
                return true;
            };
            
            def find(i64 key) -> void*
            {
                BinaryTreeNode* current = this.root;
                
                while (current != (BinaryTreeNode*)0)
                {
                    if (key < current.key)
                    {
                        current = current.left;
                    }
                    elif (key > current.key)
                    {
                        current = current.right;
                    }
                    else
                    {
                        return current.payload;
                    };
                };
                
                return (void*)0;
            };
            
            def contains(i64 key) -> bool
            {
                return this.find(key) != (void*)0;
            };
            
            def find_min_node(BinaryTreeNode* node) -> BinaryTreeNode*
            {
                while (node.left != (BinaryTreeNode*)0)
                {
                    node = node.left;
                };
                return node;
            };
            
            def remove(i64 key) -> bool
            {
                BinaryTreeNode* current = this.root;
                
                // Find the node
                while (current != (BinaryTreeNode*)0)
                {
                    if (key < current.key)
                    {
                        current = current.left;
                    }
                    elif (key > current.key)
                    {
                        current = current.right;
                    }
                    else
                    {
                        break;
                    };
                };
                
                if (current == (BinaryTreeNode*)0)
                {
                    return false;
                };
                
                // Case 1: Node has no children
                if (current.left == (BinaryTreeNode*)0 & current.right == (BinaryTreeNode*)0)
                {
                    if (current == this.root)
                    {
                        this.root = (BinaryTreeNode*)0;
                    }
                    elif (current.parent.left == current)
                    {
                        current.parent.left = (BinaryTreeNode*)0;
                    }
                    else
                    {
                        current.parent.right = (BinaryTreeNode*)0;
                    };
                    
                    free(current);
                    this.size--;
                    return true;
                };
                
                // Case 2: Node has one child
                if (current.left == (BinaryTreeNode*)0 | current.right == (BinaryTreeNode*)0)
                {
                    BinaryTreeNode* child = current.left != (BinaryTreeNode*)0 ? current.left : current.right;
                    
                    if (current == this.root)
                    {
                        this.root = child;
                        child.parent = (BinaryTreeNode*)0;
                    }
                    elif (current.parent.left == current)
                    {
                        current.parent.left = child;
                        child.parent = current.parent;
                    }
                    else
                    {
                        current.parent.right = child;
                        child.parent = current.parent;
                    };
                    
                    free(current);
                    this.size--;
                    return true;
                };
                
                // Case 3: Node has two children
                BinaryTreeNode* successor = this.find_min_node(current.right);
                current.key = successor.key;
                current.payload = successor.payload;
                
                if (successor.parent.left == successor)
                {
                    successor.parent.left = successor.right;
                }
                else
                {
                    successor.parent.right = successor.right;
                };
                
                if (successor.right != (BinaryTreeNode*)0)
                {
                    successor.right.parent = successor.parent;
                };
                
                free(successor);
                this.size--;
                return true;
            };
            
            def clear_node(BinaryTreeNode* node) -> void
            {
                if (node == (BinaryTreeNode*)0)
                {
                    return;
                };
                
                this.clear_node(node.left);
                this.clear_node(node.right);
                free(node);
            };
            
            def clear() -> void
            {
                this.clear_node(this.root);
                this.root = (BinaryTreeNode*)0;
                this.size = (size_t)0;
            };
        };
    };
};

using standard::collections;

#endif;
