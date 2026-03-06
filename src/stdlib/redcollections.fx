// Flux Collections Library
// Provides dynamic, generic collection types for the reduced specification.

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
        // ============================================================================
        // Dynamic Array
        // A heap-allocated, dynamically resizing array of fixed-size elements.
        // Elements are stored as raw bytes; the caller is responsible for casting.
        // elem_size: size in bytes of each element, passed at construction time.
        // Capacity doubles when full (2x growth strategy).
        //
        // Usage example:
        //   Array arr((size_t)4);          // array of 4-byte (int) elements
        //   int x = 42;
        //   arr.push(@x);
        //   int* p = (int*)arr.get((size_t)0);
        //   int val = *p;
        // ============================================================================

        #def ARRAY_INITIAL_CAPACITY 8;

        object Array
        {
            void*  buf;
            size_t len;
            size_t capacity;
            size_t elem_size;

            // Construct an empty Array for elements of elem_size bytes.
            def __init(size_t elem_size) -> this
            {
                this.elem_size = elem_size;
                this.len       = (size_t)0;
                this.capacity  = (size_t)ARRAY_INITIAL_CAPACITY;
                this.buf       = malloc(this.capacity * elem_size);
                return this;
            };

            // Free the backing buffer.
            def __exit() -> void
            {
                if (this.buf != STDLIB_GVP)
                {
                    free(this.buf);
                    this.buf = STDLIB_GVP;
                };
                return;
            };

            // ----------------------------------------------------------------
            // Internal: grow capacity by 2x. Returns false on alloc failure.
            // ----------------------------------------------------------------
            def _grow() -> bool
            {
                size_t new_cap = this.capacity * (size_t)2;
                void*  new_buf = realloc(this.buf, new_cap * this.elem_size);
                if (new_buf == STDLIB_GVP)
                {
                    return false;
                };
                this.buf      = new_buf;
                this.capacity = new_cap;
                return true;
            };

            // ----------------------------------------------------------------
            // Internal: return byte pointer to element at index i (no bounds check).
            // ----------------------------------------------------------------
            def _ptr(size_t i) -> byte*
            {
                return (byte*)this.buf + i * this.elem_size;
            };

            // ----------------------------------------------------------------
            // len() - number of elements currently stored.
            // ----------------------------------------------------------------
            def len() -> size_t
            {
                return this.len;
            };

            // ----------------------------------------------------------------
            // push(src) - append a copy of the element pointed to by src.
            // Returns false if allocation fails.
            // ----------------------------------------------------------------
            def push(void* src) -> bool
            {
                if (this.len >= this.capacity)
                {
                    if (!this._grow())
                    {
                        return false;
                    };
                };
                memcpy(this._ptr(this.len), src, this.elem_size);
                this.len++;
                return true;
            };

            // ----------------------------------------------------------------
            // pop(dst) - copy the last element into dst and shrink len by 1.
            // Returns false if the array is empty.
            // ----------------------------------------------------------------
            def pop(void* dst) -> bool
            {
                if (this.len == (size_t)0)
                {
                    return false;
                };
                this.len--;
                memcpy(dst, this._ptr(this.len), this.elem_size);
                return true;
            };

            // ----------------------------------------------------------------
            // get(i) - return a pointer to element i in the backing buffer.
            // Returns null if i is out of range. Caller casts to their type.
            // ----------------------------------------------------------------
            def get(size_t i) -> void*
            {
                if (i >= this.len)
                {
                    return STDLIB_GVP;
                };
                return (void*)this._ptr(i);
            };

            // ----------------------------------------------------------------
            // set(i, src) - overwrite element i with a copy of the value at src.
            // Returns false if i is out of range.
            // ----------------------------------------------------------------
            def set(size_t i, void* src) -> bool
            {
                if (i >= this.len)
                {
                    return false;
                };
                memcpy(this._ptr(i), src, this.elem_size);
                return true;
            };

            // ----------------------------------------------------------------
            // insert(i, src) - insert element at index i, shifting everything
            // from i onward one position to the right.
            // Returns false if i > len or allocation fails.
            // ----------------------------------------------------------------
            def insert(size_t i, void* src) -> bool
            {
                if (i > this.len)
                {
                    return false;
                };
                if (this.len >= this.capacity)
                {
                    if (!this._grow())
                    {
                        return false;
                    };
                };
                // Shift elements [i .. len) one slot to the right.
                if (i < this.len)
                {
                    size_t n = (this.len - i) * this.elem_size;
                    memmove(this._ptr(i + (size_t)1), this._ptr(i), n);
                };
                memcpy(this._ptr(i), src, this.elem_size);
                this.len++;
                return true;
            };

            // ----------------------------------------------------------------
            // remove(i) - remove the element at index i, shifting everything
            // after it one position to the left.
            // Returns false if i is out of range.
            // ----------------------------------------------------------------
            def remove(size_t i) -> bool
            {
                if (i >= this.len)
                {
                    return false;
                };
                this.len--;
                if (i < this.len)
                {
                    size_t n = (this.len - i) * this.elem_size;
                    memmove(this._ptr(i), this._ptr(i + (size_t)1), n);
                };
                return true;
            };

            // ----------------------------------------------------------------
            // clear() - reset length to zero. Does not free or shrink the buffer.
            // ----------------------------------------------------------------
            def clear() -> void
            {
                this.len = (size_t)0;
                return;
            };

            // ----------------------------------------------------------------
            // contains(src) - linear scan; returns true if any element compares
            // equal to the value pointed to by src (byte-for-byte comparison).
            // ----------------------------------------------------------------
            def contains(void* src) -> bool
            {
                size_t i = (size_t)0;
                while (i < this.len)
                {
                    if (memcmp(this._ptr(i), (byte*)src, this.elem_size) == 0)
                    {
                        return true;
                    };
                    i++;
                };
                return false;
            };
        };
    };
};

using standard::collections;

#endif;
