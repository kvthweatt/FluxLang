// Basic Collection Types (Non-Templated Implementation)

import "types.fx";

namespace standard
{
    namespace collections
    {
        // Dynamic array for integers (would need separate implementations for other types)
        object array<T>
        {
            T* ptr;
            u32 size, capacity;

            def __init(T* ptr, u32 size, u32 capacity) -> this
            {
                this.ptr = ptr;
                this.size = size;
                this.capacity = capacity;
                return this;
            };

            def __exit() -> void
            {
                (void)this.ptr;
                return void;
            };
        };
    };
};