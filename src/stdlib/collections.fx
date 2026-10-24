// Author: Karac V. Thweatt

// Flux Collections Library
// Provides dynamic, generic collection types for the reduced specification.

#ifnFLUX_STANDARD_TYPES
#import <types.fx>;
#endif;

#ifnFLUX_STANDARD_MEMORY
#import <memory.fx>;
#endif;

#ifnFLUX_STANDARD_COLLECTIONS
#FLUX_STANDARD_COLLECTIONS 1;

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

        #ARRAY_INITIAL_CAPACITY 8;

        trait BaseSTDArrayTraits
        {
            _grow() -> bool,
            _ptr(size_t) -> byte*,
            len() -> size_t,
            push(void* src) -> bool,
            pop(void* dst) -> bool,
            get(size_t i) -> void*,
            set(size_t i, void* src) -> bool,
            insert(size_t i, void* src) -> bool,
            remove(size_t i) -> bool,
            clear() -> void,
            contains(void* src) -> bool;
        };

        BaseSTDArrayTraits
        object Array
        {
            void*  buf;
            size_t len,
                   capacity,
                   elem_size;

            // Construct an empty Array for elements of elem_size bytes.
            __init(size_t elem_size) -> this
            {
                this.elem_size = elem_size;
                this.len       = 0;
                this.capacity  = (size_t)ARRAY_INITIAL_CAPACITY;
                this.buf       = (void*)fmalloc(this.capacity * elem_size);
                -> this;
            };

            // Free the backing buffer.
            __exit() -> void
            {
                if (this.buf != STDLIB_GVP)
                {
                    ffree(this.buf);
                    this.buf = STDLIB_GVP;
                };
                ->;
            };

            __expr() -> Array*
            {
                -> this;
            };

            // ----------------------------------------------------------------
            // Internal: grow capacity by 2x. Returns false on alloc failure.
            // ----------------------------------------------------------------
            _grow() -> bool
            {
                size_t new_cap = this.capacity * 2;
                void*  new_buf = realloc(this.buf, new_cap * this.elem_size);
                if (new_buf == STDLIB_GVP)
                {
                    -> false;
                };
                this.buf      = new_buf;
                this.capacity = new_cap;
                -> true;
            };

            // ----------------------------------------------------------------
            // Internal: -> byte pointer to element at index i (no bounds check).
            // ----------------------------------------------------------------
            _ptr(size_t i) -> byte*
            {
                -> (byte*)this.buf + i * this.elem_size;
            };

            // ----------------------------------------------------------------
            // len() - number of elements currently stored.
            // ----------------------------------------------------------------
            len() -> size_t
            {
                -> this.len;
            };

            // ----------------------------------------------------------------
            // push(src) - append a copy of the element pointed to by src.
            // Returns false if allocation fails.
            // ----------------------------------------------------------------
            push(void* src) -> bool
            {
                if (this.len >= this.capacity)
                {
                    if (!this._grow())
                    {
                        -> false;
                    };
                };
                memcpy(this._ptr(this.len), src, this.elem_size);
                this.len++;
                -> true;
            };

            // ----------------------------------------------------------------
            // pop(dst) - copy the last element into dst and shrink len by 1.
            // Returns false if the array is empty.
            // ----------------------------------------------------------------
            pop(void* dst) -> bool
            {
                if (this.len == 0)
                {
                    -> false;
                };
                this.len--;
                memcpy(dst, this._ptr(this.len), this.elem_size);
                -> true;
            };

            // ----------------------------------------------------------------
            // get(i) - -> a pointer to element i in the backing buffer.
            // Returns null if i is out of range. Caller casts to their type.
            // ----------------------------------------------------------------
            get(size_t i) -> void*
            {
                if (i >= this.len)
                {
                    -> STDLIB_GVP;
                };
                -> (void*)this._ptr(i);
            };

            // ----------------------------------------------------------------
            // set(i, src) - overwrite element i with a copy of the value at src.
            // Returns false if i is out of range.
            // ----------------------------------------------------------------
            set(size_t i, void* src) -> bool
            {
                if (i >= this.len)
                {
                    -> false;
                };
                memcpy(this._ptr(i), src, this.elem_size);
                -> true;
            };

            // ----------------------------------------------------------------
            // insert(i, src) - insert element at index i, shifting everything
            // from i onward one position to the right.
            // Returns false if i > len or allocation fails.
            // ----------------------------------------------------------------
            insert(size_t i, void* src) -> bool
            {
                if (i > this.len)
                {
                    -> false;
                };
                if (this.len >= this.capacity)
                {
                    if (!this._grow())
                    {
                        -> false;
                    };
                };
                // Shift elements [i .. len) one slot to the right.
                if (i < this.len)
                {
                    size_t n = (this.len - i) * this.elem_size;
                    memmove(this._ptr(i + 1), this._ptr(i), n);
                };
                memcpy(this._ptr(i), src, this.elem_size);
                this.len++;
                -> true;
            };

            // ----------------------------------------------------------------
            // remove(i) - remove the element at index i, shifting everything
            // after it one position to the left.
            // Returns false if i is out of range.
            // ----------------------------------------------------------------
            remove(size_t i) -> bool
            {
                if (i >= this.len)
                {
                    -> false;
                };
                this.len--;
                if (i < this.len)
                {
                    size_t n = (this.len - i) * this.elem_size;
                    memmove(this._ptr(i), this._ptr(i + 1), n);
                };
                -> true;
            };

            // ----------------------------------------------------------------
            // clear() - reset length to zero. Does not free or shrink the buffer.
            // ----------------------------------------------------------------
            clear() -> void
            {
                this.len = 0;
                ->;
            };

            // ----------------------------------------------------------------
            // contains(src) - linear scan; returns true if any element compares
            // equal to the value pointed to by src (byte-for-byte comparison).
            // ----------------------------------------------------------------
            contains(void* src) -> bool
            {
                size_t i;
                while (i < this.len)
                {
                    if (memcmp(this._ptr(i), (byte*)src, this.elem_size) == 0)
                    {
                        -> true;
                    };
                    i++;
                };
                -> false;
            };
        };
    };

    namespace collections
    {
        // -------------------------------------------------------------------------
        // Internal bucket structs
        // -------------------------------------------------------------------------

        struct HMBucket
        {
            u64   key_hash;
            byte* key;
            void* value;
            u64   psl;
        };

        struct HMIBucket
        {
            u64   key_hash, key;
            void* value;
            u64   psl;
        };

        // -------------------------------------------------------------------------
        // Hash functions
        // -------------------------------------------------------------------------

        // FNV-1a 64-bit for string keys
        hm_hash_str(byte* key) -> u64
        {
            u64 hash = 14695981039346656037u,
                prime = 1099511628211u;
            int i;

            while (key[i] != 0)
            {
                hash = hash xor key[i];
                hash = hash * prime;
                i = i + 1;
            };
            // Ensure hash != 0 (reserved for empty slots)
            if (hash == 0)
            {
                hash = 1;
            };
            -> hash;
        };

        // Murmur-inspired mix for integer keys
        hm_hash_u64(u64 key) -> u64
        {
            u64 h = key;
            h = h xor (h >> 33);
            h = h * 18397679294719823053u;
            h = h xor (h >> 33);
            h = h * 14181476777654086739u;
            h = h xor (h >> 33);
            if (h == 0)
            {
                h = 1;
            };
            -> h;
        };

        // -------------------------------------------------------------------------
        // String comparison helper
        // -------------------------------------------------------------------------

        hm_str_eq(byte* a, byte* b) -> bool
        {
            int i;
            while (true)
            {
                if (a[i] != b[i])
                {
                    -> false;
                };
                if (a[i] == 0)
                {
                    -> true;
                };
                i = i + 1;
            };
            -> false;
        };

        // -------------------------------------------------------------------------
        // String key copy helper (allocates new buffer)
        // -------------------------------------------------------------------------

        hm_str_dup(byte* src) -> byte*
        {
            int len, i;
            while (src[len] != 0)
            {
                len = len + 1;
            };
            byte* dst = (byte*)fmalloc(len + 1);
            while (i < len)
            {
                dst[i] = src[i];
                i = i + 1;
            };
            dst[len] = 0;
            -> dst;
        };

        trait BaseSTDHashMapTraits
        {
            _insert_nocopy(u64 hash, byte* key, void* value) -> void,
            _resize() -> void,
            hm_get(byte* key) -> void*,
            hm_set(byte* key, void* value) -> void,
            hm_has(byte* key) -> bool,
            hm_remove(byte* key) -> bool,
            hm_count() -> u64,
            hm_capacity() -> u64;
        };

        BaseSTDHashMapTraits
        object HashMap
        {
            HMBucket* buckets;
            u64       count,
                      cap;

            __init(u64 initial_cap) -> this
            {
                // Round up to next power of two, minimum 16
                u64 c = 16, i;
                while (c < initial_cap)
                {
                    c = c * 2;
                };
                this.cap     = c;
                this.count   = 0;
                u64 nbytes   = c * 32; // sizeof(HMBucket) = 32
                this.buckets = (HMBucket*)fmalloc(nbytes);
                // Zero all buckets (key_hash == 0 means empty)
                while (i < c)
                {
                    this.buckets[i].key_hash = 0;
                    this.buckets[i].key      = (byte*)0;
                    this.buckets[i].value    = (void*)0;
                    this.buckets[i].psl      = 0;
                    i = i + 1;
                };
                -> this;
            };

            __exit() -> void
            {
                // Free all duplicated key strings
                u64 i;
                while (i < this.cap)
                {
                    if (this.buckets[i].key_hash != 0)
                    {
                        ffree((u64)this.buckets[i].key);
                    };
                    i = i + 1;
                };
                ffree((u64)this.buckets);
            };

            __expr() -> HashMap*
            {
                -> this;
            };

            // Internal: insert without copying key (used during resize)
            _insert_nocopy(u64 hash, byte* key, void* value) -> void
            {
                u64 mask = this.cap - 1;
                u64 idx  = hash & mask,
                    psl;
                HMBucket* slot;
                HMBucket  tmp;

                HMBucket insert_bkt;
                insert_bkt.key_hash = hash;
                insert_bkt.key      = key;
                insert_bkt.value    = value;
                insert_bkt.psl      = psl;

                while (true)
                {
                    slot = this.buckets + idx;

                    // Empty slot: place here
                    if (slot.key_hash == 0)
                    {
                        slot.key_hash = insert_bkt.key_hash;
                        slot.key      = insert_bkt.key;
                        slot.value    = insert_bkt.value;
                        slot.psl      = insert_bkt.psl;
                        this.count    = this.count + 1;
                        ->;
                    };

                    // Same key: update value
                    if (slot.key_hash == insert_bkt.key_hash)
                    {
                        if (hm_str_eq(slot.key, insert_bkt.key))
                        {
                            slot.value = insert_bkt.value;
                            ->;
                        };
                    };

                    // Robin hood: steal from rich slot
                    if (slot.psl < insert_bkt.psl)
                    {
                        // Swap insert_bkt with slot
                        tmp.key_hash       = slot.key_hash;
                        tmp.key            = slot.key;
                        tmp.value          = slot.value;
                        tmp.psl            = slot.psl;

                        slot.key_hash      = insert_bkt.key_hash;
                        slot.key           = insert_bkt.key;
                        slot.value         = insert_bkt.value;
                        slot.psl           = insert_bkt.psl;

                        insert_bkt.key_hash = tmp.key_hash;
                        insert_bkt.key      = tmp.key;
                        insert_bkt.value    = tmp.value;
                        insert_bkt.psl      = tmp.psl;
                    };

                    idx = (idx + 1) & mask;
                    insert_bkt.psl = insert_bkt.psl + 1;
                };
            };

            // Internal: grow and rehash
            _resize() -> void
            {
                u64 old_cap   = this.cap,
                    new_cap   = old_cap * 2,
                    nbytes    = new_cap * 32,
                    i;
                HMBucket* old_buckets = this.buckets;

                this.buckets  = (HMBucket*)fmalloc(nbytes);
                this.cap      = new_cap;
                this.count    = 0;

                while (i < new_cap)
                {
                    this.buckets[i].key_hash = 0;
                    this.buckets[i].key      = (byte*)0;
                    this.buckets[i].value    = (void*)0;
                    this.buckets[i].psl      = 0;
                    i = i + 1;
                };

                i = 0;
                while (i < old_cap)
                {
                    if (old_buckets[i].key_hash != 0)
                    {
                        this._insert_nocopy(
                            old_buckets[i].key_hash,
                            old_buckets[i].key,
                            old_buckets[i].value
                        );
                    };
                    i = i + 1;
                };

                ffree((u64)old_buckets);
            };

            // Insert or update a key-value pair.
            hm_set(byte* key, void* value) -> void
            {
                // Resize if load > 75%
                // count * 4 > cap * 3  <=>  load > 0.75
                if (this.count * 4 > this.cap * 3)
                {
                    this._resize();
                };

                u64 hash = hm_hash_str(key);
                u64 mask = this.cap - 1;
                u64 idx  = hash & mask,
                    psl;
                HMBucket* slot;
                HMBucket insert_bkt, tmp;
                insert_bkt.key_hash = hash;
                insert_bkt.key      = hm_str_dup(key);
                insert_bkt.value    = value;
                insert_bkt.psl      = psl;

                while (true)
                {
                    slot = this.buckets + idx;

                    // Empty slot
                    if (slot.key_hash == 0)
                    {
                        slot.key_hash = insert_bkt.key_hash;
                        slot.key      = insert_bkt.key;
                        slot.value    = insert_bkt.value;
                        slot.psl      = insert_bkt.psl;
                        this.count    = this.count + (u64)1;
                        ->;
                    };

                    // Existing key: update, free the new dup
                    if (slot.key_hash == insert_bkt.key_hash)
                    {
                        if (hm_str_eq(slot.key, insert_bkt.key))
                        {
                            ffree((u64)insert_bkt.key);
                            slot.value = insert_bkt.value;
                            ->;
                        };
                    };

                    // Robin hood swap
                    if (slot.psl < insert_bkt.psl)
                    {
                        tmp.key_hash       = slot.key_hash;
                        tmp.key            = slot.key;
                        tmp.value          = slot.value;
                        tmp.psl            = slot.psl;

                        slot.key_hash      = insert_bkt.key_hash;
                        slot.key           = insert_bkt.key;
                        slot.value         = insert_bkt.value;
                        slot.psl           = insert_bkt.psl;

                        insert_bkt.key_hash = tmp.key_hash;
                        insert_bkt.key      = tmp.key;
                        insert_bkt.value    = tmp.value;
                        insert_bkt.psl      = tmp.psl;
                    };

                    idx = (idx + (u64)1) & mask;
                    insert_bkt.psl = insert_bkt.psl + (u64)1;
                };
            };

            // Retrieve value for key. Returns NULL if not found.
            hm_get(byte* key) -> void*
            {
                u64 hash = hm_hash_str(key),
                    mask = this.cap - 1,
                    idx  = hash & mask,
                    psl;
                HMBucket slot;

                while (true)
                {
                    slot = this.buckets + idx;

                    if (slot.key_hash == 0)
                    {
                        -> (void*)0;
                    };

                    if (slot.psl < psl)
                    {
                        // Robin hood invariant: can't be further than this
                        -> (void*)0;
                    };

                    if (slot.key_hash == hash)
                    {
                        if (hm_str_eq(slot.key, key))
                        {
                            -> slot.value;
                        };
                    };

                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                -> (void*)0;
            };

            // Check if a key exists.
            hm_has(byte* key) -> bool
            {
                -> this.hm_get(key) != (void*)0;
            };

            // Remove a key. Returns true if it was present.
            hm_remove(byte* key) -> bool
            {
                u64 hash = hm_hash_str(key),
                    mask = this.cap - 1,
                    idx  = hash & mask,
                    psl,
                    cur, next;
                HMBucket* slot, nx, cr;

                while (true)
                {
                    slot = this.buckets + idx;

                    if (slot.key_hash == 0)
                    {
                        -> false;
                    };

                    if (slot.psl < psl)
                    {
                        -> false;
                    };

                    if (slot.key_hash == hash)
                    {
                        if (hm_str_eq(slot.key, key))
                        {
                            // Free the duplicated key
                            ffree((u64)slot.key);
                            slot.key_hash = 0;
                            slot.key      = (byte*)0;
                            slot.value    = (void*)0;
                            slot.psl      = 0;
                            this.count    = this.count - 1;

                            // Backward shift deletion to maintain robin hood invariant
                            cur  = idx;
                            next = (idx + 1) & mask;
                            while (true)
                            {
                                nx = this.buckets + next;
                                if (nx.key_hash == 0 | nx.psl == 0)
                                {
                                    break;
                                };
                                cr = this.buckets + cur;
                                cr.key_hash = nx.key_hash;
                                cr.key      = nx.key;
                                cr.value    = nx.value;
                                cr.psl      = nx.psl - 1;
                                nx.key_hash = 0;
                                nx.key      = (byte*)0;
                                nx.value    = (void*)0;
                                nx.psl      = 0;
                                cur  = next;
                                next = (next + 1) & mask;
                            };

                            -> true;
                        };
                    };

                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                -> false;
            };

            hm_count() -> u64
            {
                -> this.count;
            };

            hm_capacity() -> u64
            {
                -> this.cap;
            };
        };

        // -------------------------------------------------------------------------
        // HashMapInt (u64 keys)
        // -------------------------------------------------------------------------

        trait BaseSTDHashMapIntTraits
        {
            _insert_raw(u64 hash, u64 key, void* value) -> void,
            _resize() -> void,
            hmi_get(u64 key) -> void*,
            hmi_set(u64 key, void* value) -> void,
            hmi_has(u64 key) -> bool,
            hmi_remove(u64 key) -> bool,
            hmi_count() -> u64,
            hmi_capacity() -> u64;
        };

        BaseSTDHashMapIntTraits
        object HashMapInt
        {
            HMIBucket* buckets;
            u64        count,
                       cap;

            __init(u64 initial_cap) -> this
            {
                u64 c = 16;
                u64 nbytes = c * 32, // sizeof(HMIBucket) = 32
                    i;
                while (c < initial_cap)
                {
                    c = c * 2;
                };
                this.cap     = c;
                this.count   = 0;
                this.buckets = (HMIBucket*)fmalloc(nbytes);
                while (i < c)
                {
                    this.buckets[i].key_hash = 0;
                    this.buckets[i].key      = 0;
                    this.buckets[i].value    = (void*)0;
                    this.buckets[i].psl      = 0;
                    i = i + 1;
                };
                -> this;
            };

            __exit() -> void
            {
                ffree((u64)this.buckets);
            };

            __expr() -> HashMapInt*
            {
                -> this;
            };

            _insert_raw(u64 hash, u64 key, void* value) -> void
            {
                u64 mask = this.cap - 1;
                u64 idx  = hash & mask;

                HMIBucket ins, tmp;
                HMIBucket* slot;
                ins.key_hash = hash;
                ins.key      = key;
                ins.value    = value;
                ins.psl      = 0;

                while (true)
                {
                    slot = this.buckets + idx;

                    if (slot.key_hash == 0)
                    {
                        slot.key_hash = ins.key_hash;
                        slot.key      = ins.key;
                        slot.value    = ins.value;
                        slot.psl      = ins.psl;
                        this.count    = this.count + 1;
                        ->;
                    };

                    if (slot.key_hash == ins.key_hash & slot.key == ins.key)
                    {
                        slot.value = ins.value;
                        ->;
                    };

                    if (slot.psl < ins.psl)
                    {
                        tmp.key_hash  = slot.key_hash;
                        tmp.key       = slot.key;
                        tmp.value     = slot.value;
                        tmp.psl       = slot.psl;

                        slot.key_hash = ins.key_hash;
                        slot.key      = ins.key;
                        slot.value    = ins.value;
                        slot.psl      = ins.psl;

                        ins.key_hash  = tmp.key_hash;
                        ins.key       = tmp.key;
                        ins.value     = tmp.value;
                        ins.psl       = tmp.psl;
                    };

                    idx    = (idx + 1) & mask;
                    ins.psl = ins.psl + 1;
                };
            };

            _resize() -> void
            {
                u64 old_cap     = this.cap;
                u64 new_cap   = old_cap * 2;
                u64 nbytes    = new_cap * 32,
                    i;
                HMIBucket* old_buckets = this.buckets;

                this.buckets  = (HMIBucket*)fmalloc(nbytes);
                this.cap      = new_cap;
                this.count    = 0;

                while (i < new_cap)
                {
                    this.buckets[i].key_hash = 0;
                    this.buckets[i].key      = 0;
                    this.buckets[i].value    = (void*)0;
                    this.buckets[i].psl      = 0;
                    i = i + 1;
                };

                i = 0;
                while (i < old_cap)
                {
                    if (old_buckets[i].key_hash != 0)
                    {
                        this._insert_raw(
                            old_buckets[i].key_hash,
                            old_buckets[i].key,
                            old_buckets[i].value
                        );
                    };
                    i = i + 1;
                };

                ffree((u64)old_buckets);
            };

            hmi_set(u64 key, void* value) -> void
            {
                if (this.count * (u64)4 > this.cap * (u64)3)
                {
                    this._resize();
                };
                u64 hash = hm_hash_u64(key);
                this._insert_raw(hash, key, value);
            };

            hmi_get(u64 key) -> void*
            {
                u64 hash = hm_hash_u64(key),
                    mask = this.cap - 1,
                    idx  = hash & mask,
                    psl;
                HMIBucket slot;

                while (true)
                {
                    slot = this.buckets + idx;

                    if (slot.key_hash == 0)
                    {
                        -> (void*)0;
                    };

                    if (slot.psl < psl)
                    {
                        -> (void*)0;
                    };

                    if (slot.key_hash == hash & slot.key == key)
                    {
                        -> slot.value;
                    };

                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                -> (void*)0;
            };

            hmi_has(u64 key) -> bool
            {
                -> this.hmi_get(key) != (void*)0;
            };

            hmi_remove(u64 key) -> bool
            {
                u64 hash = hm_hash_u64(key),
                    mask = this.cap - (u64)1,
                    idx  = hash & mask,
                    psl,
                    cur, next;

                HMIBucket* slot, nx, cr;

                while (true)
                {
                    slot = this.buckets + idx;

                    if (slot.key_hash == 0)
                    {
                        -> false;
                    };

                    if (slot.psl < psl)
                    {
                        -> false;
                    };

                    if (slot.key_hash == hash & slot.key == key)
                    {
                        slot.key_hash = 0;
                        slot.key      = 0;
                        slot.value    = (void*)0;
                        slot.psl      = 0;
                        this.count    = this.count - 1;

                        // Backward shift deletion
                        cur  = idx;
                        next = (idx + 1) & mask;
                        while (true)
                        {
                            nx = this.buckets + next;
                            if (nx.key_hash == 0 | nx.psl == 0)
                            {
                                break;
                            };
                            cr = this.buckets + cur;
                            cr.key_hash = nx.key_hash;
                            cr.key      = nx.key;
                            cr.value    = nx.value;
                            cr.psl      = nx.psl - 1;
                            nx.key_hash = 0;
                            nx.key      = 0;
                            nx.value    = (void*)0;
                            nx.psl      = 0;
                            cur  = next;
                            next = (next + 1) & mask;
                        };

                        -> true;
                    };

                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                -> false;
            };

            hmi_count() -> u64
            {
                -> this.count;
            };

            hmi_capacity() -> u64
            {
                -> this.cap;
            };
        };

        // ============================================================================
        // LinkedList
        // Doubly-linked list backed by a fixed-capacity node pool.
        // The pool is a single slab allocated at __init time; nodes are carved from
        // it via a free-list.  No per-push malloc, no per-pop free, no alloc/free
        // inside any loop.
        //
        // pool_cap: maximum number of nodes the list can hold (set at __init).
        //
        // Usage example:
        //   LinkedList list((size_t)64);
        //   int x = 42;
        //   LLNode* n = list.push_back(@x);
        //   void*   v = list.pop_front();
        // ============================================================================

        struct LLNode
        {
            LLNode* prev,
                    next;
            void*   value;
        };

        trait BaseSTDLinkedListTraits
        {
            push_front(void* value) -> LLNode*,
            push_back(void* value)  -> LLNode*,
            pop_front()             -> void*,
            pop_back()              -> void*,
            peek_front()            -> void*,
            peek_back()             -> void*,
            remove_node(LLNode* n)  -> void*,
            ll_len()                -> size_t,
            ll_clear()              -> void;
        };

        BaseSTDLinkedListTraits
        object LinkedList
        {
            LLNode* pool,      // backing slab: pool_cap * sizeof(LLNode) bytes
                    freelist,  // head of the free-list threaded through unused nodes
                    head,
                    tail;
            size_t  pool_cap,
                    len;

            // Construct a list with a fixed node pool of pool_cap entries.
            // One fmalloc here; no further allocations ever.
            __init(size_t pool_cap) -> this
            {
                this.pool_cap = pool_cap;
                this.len      = 0;
                this.head     = (LLNode*)STDLIB_GVP;
                this.tail     = (LLNode*)STDLIB_GVP;
                // sizeof(LLNode) = 24 (prev:8, next:8, value:8)
                this.pool     = (LLNode*)fmalloc(pool_cap * 24);
                // Thread free-list through all nodes; next pointer serves as link.
                // All locals must be declared at function top.
                size_t i = 0;
                LLNode* node, nx;
                while (i < pool_cap)
                {
                    node = this.pool + i;
                    if (i + 1 < pool_cap)
                    {
                        nx = this.pool + (i + 1);
                    }
                    else
                    {
                        nx = (LLNode*)STDLIB_GVP;
                    };
                    node.next  = nx;
                    node.prev  = (LLNode*)STDLIB_GVP;
                    node.value = STDLIB_GVP;
                    i = i + 1;
                };
                this.freelist = this.pool;
                -> this;
            };

            // Free the pool slab.  One ffree; no loop.
            __exit() -> void
            {
                ffree((u64)this.pool);
                this.pool     = (LLNode*)STDLIB_GVP;
                this.freelist = (LLNode*)STDLIB_GVP;
                this.head     = (LLNode*)STDLIB_GVP;
                this.tail     = (LLNode*)STDLIB_GVP;
                this.len      = 0;
                ->;
            };

            __expr() -> LinkedList*
            {
                -> this;
            };

            // ----------------------------------------------------------------
            // push_front(value) - prepend. Returns node ptr or STDLIB_GVP if full.
            // ----------------------------------------------------------------
            push_front(void* value) -> LLNode*
            {
                if (this.freelist == (LLNode*)STDLIB_GVP)
                {
                    -> (LLNode*)STDLIB_GVP;
                };
                LLNode* n     = this.freelist;
                this.freelist = n.next;
                n.prev        = (LLNode*)STDLIB_GVP;
                n.next        = this.head;
                n.value       = value;
                if (this.head != (LLNode*)STDLIB_GVP)
                {
                    this.head.prev = n;
                }
                else
                {
                    this.tail = n;
                };
                this.head = n;
                this.len  = this.len + 1;
                -> n;
            };

            // ----------------------------------------------------------------
            // push_back(value) - append. Returns node ptr or STDLIB_GVP if full.
            // ----------------------------------------------------------------
            push_back(void* value) -> LLNode*
            {
                if (this.freelist == (LLNode*)STDLIB_GVP)
                {
                    -> (LLNode*)STDLIB_GVP;
                };
                LLNode* n     = this.freelist;
                this.freelist = n.next;
                n.prev        = this.tail;
                n.next        = (LLNode*)STDLIB_GVP;
                n.value       = value;
                if (this.tail != (LLNode*)STDLIB_GVP)
                {
                    this.tail.next = n;
                }
                else
                {
                    this.head = n;
                };
                this.tail = n;
                this.len  = this.len + 1;
                -> n;
            };

            // ----------------------------------------------------------------
            // pop_front() - remove head, -> its value. Returns STDLIB_GVP if empty.
            // ----------------------------------------------------------------
            pop_front() -> void*
            {
                if (this.head == (LLNode*)STDLIB_GVP)
                {
                    -> STDLIB_GVP;
                };
                LLNode* n   = this.head;
                void*   val = n.value;
                this.head   = n.next;
                if (this.head != (LLNode*)STDLIB_GVP)
                {
                    this.head.prev = (LLNode*)STDLIB_GVP;
                }
                else
                {
                    this.tail = (LLNode*)STDLIB_GVP;
                };
                // Return node to free-list
                n.next        = this.freelist;
                n.prev        = (LLNode*)STDLIB_GVP;
                n.value       = STDLIB_GVP;
                this.freelist = n;
                this.len      = this.len - 1;
                -> val;
            };

            // ----------------------------------------------------------------
            // pop_back() - remove tail, -> its value. Returns STDLIB_GVP if empty.
            // ----------------------------------------------------------------
            pop_back() -> void*
            {
                if (this.tail == (LLNode*)STDLIB_GVP)
                {
                    -> STDLIB_GVP;
                };
                LLNode* n   = this.tail;
                void*   val = n.value;
                this.tail   = n.prev;
                if (this.tail != (LLNode*)STDLIB_GVP)
                {
                    this.tail.next = (LLNode*)STDLIB_GVP;
                }
                else
                {
                    this.head = (LLNode*)STDLIB_GVP;
                };
                // Return node to free-list
                n.next        = this.freelist;
                n.prev        = (LLNode*)STDLIB_GVP;
                n.value       = STDLIB_GVP;
                this.freelist = n;
                this.len      = this.len - 1;
                -> val;
            };

            // ----------------------------------------------------------------
            // peek_front() - head value without removal. STDLIB_GVP if empty.
            // ----------------------------------------------------------------
            peek_front() -> void*
            {
                if (this.head == (LLNode*)STDLIB_GVP)
                {
                    -> STDLIB_GVP;
                };
                -> this.head.value;
            };

            // ----------------------------------------------------------------
            // peek_back() - tail value without removal. STDLIB_GVP if empty.
            // ----------------------------------------------------------------
            peek_back() -> void*
            {
                if (this.tail == (LLNode*)STDLIB_GVP)
                {
                    -> STDLIB_GVP;
                };
                -> this.tail.value;
            };

            // ----------------------------------------------------------------
            // remove_node(n) - unlink a node and -> to free-list.
            // Returns the value stored in the node.
            // ----------------------------------------------------------------
            remove_node(LLNode* n) -> void*
            {
                void* val = n.value;
                if (n.prev != (LLNode*)STDLIB_GVP)
                {
                    n.prev.next = n.next;
                }
                else
                {
                    this.head = n.next;
                };
                if (n.next != (LLNode*)STDLIB_GVP)
                {
                    n.next.prev = n.prev;
                }
                else
                {
                    this.tail = n.prev;
                };
                n.next        = this.freelist;
                n.prev        = (LLNode*)STDLIB_GVP;
                n.value       = STDLIB_GVP;
                this.freelist = n;
                this.len      = this.len - 1;
                -> val;
            };

            // ----------------------------------------------------------------
            // ll_len() - number of nodes currently in the list.
            // ----------------------------------------------------------------
            ll_len() -> size_t
            {
                -> this.len;
            };

            // ----------------------------------------------------------------
            // ll_clear() - -> all live nodes to free-list. No alloc/free.
            // ----------------------------------------------------------------
            ll_clear() -> void
            {
                LLNode* cur = this.head, nxt;
                while (cur != (LLNode*)STDLIB_GVP)
                {
                    nxt           = cur.next;
                    cur.next      = this.freelist;
                    cur.prev      = (LLNode*)STDLIB_GVP;
                    cur.value     = STDLIB_GVP;
                    this.freelist = cur;
                    cur           = nxt;
                };
                this.head = (LLNode*)STDLIB_GVP;
                this.tail = (LLNode*)STDLIB_GVP;
                this.len  = 0;
                ->;
            };
        };

        // ============================================================================
        // Stack
        // LIFO stack backed by LinkedList pool.
        // stack_push/stack_pop/stack_peek are O(1), no alloc.
        //
        // Usage example:
        //   Stack s((size_t)64);
        //   int x = 7;
        //   s.stack_push(@x);
        //   void* v = s.stack_pop();
        // ============================================================================

        trait BaseSTDStackTraits
        {
            stack_push(void* value) -> bool,
            stack_pop()             -> void*,
            stack_peek()            -> void*,
            stack_len()             -> size_t,
            stack_empty()           -> bool;
        };

        BaseSTDStackTraits
        object Stack
        {
            LinkedList ll;

            __init(size_t cap) -> this
            {
                this.ll.__init(cap);
                -> this;
            };

            __exit() -> void
            {
                this.ll.__exit();
                ->;
            };

            __expr() -> Stack*
            {
                -> this;
            };

            stack_push(void* value) -> bool
            {
                LLNode* n = this.ll.push_back(value);
                -> n != (LLNode*)STDLIB_GVP;
            };

            stack_pop() -> void*
            {
                -> this.ll.pop_back();
            };

            stack_peek() -> void*
            {
                -> this.ll.peek_back();
            };

            stack_len() -> size_t
            {
                -> this.ll.ll_len();
            };

            stack_empty() -> bool
            {
                -> this.ll.ll_len() == 0;
            };
        };

        // ============================================================================
        // Queue
        // FIFO queue backed by LinkedList pool.
        // enqueue/dequeue/queue_peek are O(1), no alloc.
        //
        // Usage example:
        //   Queue q((size_t)64);
        //   int x = 3;
        //   q.enqueue(@x);
        //   void* v = q.dequeue();
        // ============================================================================

        trait BaseSTDQueueTraits
        {
            enqueue(void* value) -> bool,
            dequeue()            -> void*,
            queue_peek()         -> void*,
            queue_len()          -> size_t,
            queue_empty()        -> bool;
        };

        BaseSTDQueueTraits
        object Queue
        {
            LinkedList ll;

            __init(size_t cap) -> this
            {
                this.ll.__init(cap);
                -> this;
            };

            __exit() -> void
            {
                this.ll.__exit();
                ->;
            };

            __expr() -> Queue*
            {
                -> this;
            };

            enqueue(void* value) -> bool
            {
                LLNode* n = this.ll.push_back(value);
                -> n != (LLNode*)STDLIB_GVP;
            };

            dequeue() -> void*
            {
                -> this.ll.pop_front();
            };

            queue_peek() -> void*
            {
                -> this.ll.peek_front();
            };

            queue_len() -> size_t
            {
                -> this.ll.ll_len();
            };

            queue_empty() -> bool
            {
                -> this.ll.ll_len() == 0;
            };
        };

        // ============================================================================
        // Deque  (double-ended queue)
        // Ring-buffer backed deque with fixed capacity set at construction time.
        // push_front, push_back, pop_front, pop_back are all O(1), no alloc.
        // The backing buffer holds void* pointers (one per slot).
        // When the buffer is full, push operations -> false.
        //
        // Usage example:
        //   Deque dq((size_t)32);
        //   int x = 5;
        //   dq.dq_push_back(@x);
        //   void* v = dq.dq_pop_front();
        // ============================================================================

        #DEQUE_DEFAULT_CAPACITY 16;

        trait BaseSTDDequeTraits
        {
            dq_push_front(void* value) -> bool,
            dq_push_back(void* value)  -> bool,
            dq_pop_front()             -> void*,
            dq_pop_back()              -> void*,
            dq_peek_front()            -> void*,
            dq_peek_back()             -> void*,
            dq_len()                   -> size_t,
            dq_full()                  -> bool,
            dq_empty()                 -> bool,
            dq_clear()                 -> void;
        };

        BaseSTDDequeTraits
        object Deque
        {
            void** buf;
            size_t cap,
                   head,
                   tail,
                   len;

            // One fmalloc at init; no further alloc ever.
            __init(size_t cap) -> this
            {
                this.cap  = cap;
                this.head = 0;
                this.tail = 0;
                this.len  = 0;
                this.buf  = (void**)fmalloc(cap * 8);
                -> this;
            };

            __exit() -> void
            {
                if (this.buf != (void**)STDLIB_GVP)
                {
                    ffree((u64)this.buf);
                    this.buf = (void**)STDLIB_GVP;
                };
                ->;
            };

            __expr() -> Deque*
            {
                -> this;
            };

            dq_push_back(void* value) -> bool
            {
                if (this.len == this.cap)
                {
                    -> false;
                };
                this.buf[this.tail] = value;
                this.tail = (this.tail + 1) % this.cap;
                this.len  = this.len + 1;
                -> true;
            };

            dq_push_front(void* value) -> bool
            {
                if (this.len == this.cap)
                {
                    -> false;
                };
                this.head           = (this.head + this.cap - 1) % this.cap;
                this.buf[this.head] = value;
                this.len            = this.len + 1;
                -> true;
            };

            dq_pop_front() -> void*
            {
                if (this.len == 0)
                {
                    -> STDLIB_GVP;
                };
                void* val = this.buf[this.head];
                this.head = (this.head + 1) % this.cap;
                this.len  = this.len - 1;
                -> val;
            };

            dq_pop_back() -> void*
            {
                if (this.len == 0)
                {
                    -> STDLIB_GVP;
                };
                this.tail = (this.tail + this.cap - 1) % this.cap;
                void* val = this.buf[this.tail];
                this.len  = this.len - 1;
                -> val;
            };

            dq_peek_front() -> void*
            {
                if (this.len == 0)
                {
                    -> STDLIB_GVP;
                };
                -> (void*)this.buf[this.head];
            };

            dq_peek_back() -> void*
            {
                if (this.len == 0)
                {
                    -> STDLIB_GVP;
                };
                size_t idx = (this.tail + this.cap - 1) % this.cap;
                -> (void*)this.buf[idx];
            };

            dq_len() -> size_t
            {
                -> this.len;
            };

            dq_full() -> bool
            {
                -> this.len == this.cap;
            };

            dq_empty() -> bool
            {
                -> this.len == 0;
            };

            dq_clear() -> void
            {
                this.head = 0;
                this.tail = 0;
                this.len  = 0;
                ->;
            };
        };

        // ============================================================================
        // RingBuffer
        // Fixed-capacity circular buffer for raw bytes.
        // write() copies bytes in; read() copies bytes out.
        // One fmalloc at init; no further alloc.  All loops move bytes only.
        //
        // Usage example:
        //   RingBuffer rb((size_t)1024);
        //   byte buf[4];
        //   rb.rb_write((byte*)@buf, (size_t)4);
        //   rb.rb_read((byte*)@buf, (size_t)4);
        // ============================================================================

        trait BaseSTDRingBufferTraits
        {
            rb_write(byte* src, size_t n) -> size_t,
            rb_read(byte* dst, size_t n)  -> size_t,
            rb_peek(byte* dst, size_t n)  -> size_t,
            rb_skip(size_t n)             -> size_t,
            rb_available()                -> size_t,
            rb_free_space()               -> size_t,
            rb_empty()                    -> bool,
            rb_full()                     -> bool,
            rb_clear()                    -> void;
        };

        BaseSTDRingBufferTraits
        object RingBuffer
        {
            byte*  buf;
            size_t cap,
                   head,
                   tail,
                   used;

            __init(size_t cap) -> this
            {
                this.cap  = cap;
                this.head = 0;
                this.tail = 0;
                this.used = 0;
                this.buf  = (byte*)fmalloc(cap);
                -> this;
            };

            __exit() -> void
            {
                if (this.buf != (byte*)STDLIB_GVP)
                {
                    ffree((u64)this.buf);
                    this.buf = (byte*)STDLIB_GVP;
                };
                ->;
            };

            __expr() -> RingBuffer*
            {
                -> this;
            };

            rb_write(byte* src, size_t n) -> size_t
            {
                size_t space = this.cap - this.used,
                       i;
                if (n > space)
                {
                    n = space;
                };
                while (i < n)
                {
                    this.buf[this.tail] = src[i];
                    this.tail = (this.tail + 1) % this.cap;
                    i = i + 1;
                };
                this.used = this.used + n;
                -> n;
            };

            rb_read(byte* dst, size_t n) -> size_t
            {
                size_t i;
                if (n > this.used)
                {
                    n = this.used;
                };
                while (i < n)
                {
                    dst[i] = this.buf[this.head];
                    this.head = (this.head + 1) % this.cap;
                    i = i + 1;
                };
                this.used = this.used - n;
                -> n;
            };

            rb_peek(byte* dst, size_t n) -> size_t
            {
                size_t i, pos = this.head;
                if (n > this.used)
                {
                    n = this.used;
                };
                while (i < n)
                {
                    dst[i] = this.buf[pos];
                    pos = (pos + 1) % this.cap;
                    i   = i + 1;
                };
                -> n;
            };

            rb_skip(size_t n) -> size_t
            {
                if (n > this.used)
                {
                    n = this.used;
                };
                this.head = (this.head + n) % this.cap;
                this.used = this.used - n;
                -> n;
            };

            rb_available() -> size_t
            {
                -> this.used;
            };

            rb_free_space() -> size_t
            {
                -> this.cap - this.used;
            };

            rb_empty() -> bool
            {
                -> this.used == 0;
            };

            rb_full() -> bool
            {
                -> this.used == this.cap;
            };

            rb_clear() -> void
            {
                this.head = 0;
                this.tail = 0;
                this.used = 0;
                ->;
            };
        };

        // ============================================================================
        // HashSet  (string keys)
        // Open-addressed robin-hood hash set.
        // Keys are stored in a flat key-pool slab allocated once at __init.
        // A bump pointer carves space for each new key; no per-key malloc.
        // __exit frees two slabs (buckets + key pool) — no loop, no per-key free.
        //
        // key_pool_bytes: total bytes reserved for key storage.
        //
        // Usage example:
        //   HashSet hs((u64)16, (u64)1024);
        //   hs.set_add("hello");
        //   bool found = hs.set_has("hello");
        //   hs.set_remove("hello");
        // ============================================================================

        struct HSBucket
        {
            u64   key_hash;
            byte* key;
            u64   psl;
        };

        trait BaseSTDHashSetTraits
        {
            _hs_probe(u64 hash, byte* key)  -> void,
            _hs_resize()                    -> void,
            set_add(byte* key)              -> void,
            set_has(byte* key)              -> bool,
            set_remove(byte* key)           -> bool,
            set_count()                     -> u64,
            set_capacity()                  -> u64;
        };

        BaseSTDHashSetTraits
        object HashSet
        {
            HSBucket* buckets;
            byte*     key_pool;
            u64       count,
                      cap,
                      key_pool_cap,
                      key_pool_used;

            // init: allocate bucket array and key pool in two fmallocs; no loops.
            __init(u64 initial_cap, u64 key_pool_bytes) -> this
            {
                u64 c = 16, i;
                while (c < initial_cap)
                {
                    c = c * 2;
                };
                this.cap           = c;
                this.count         = 0;
                this.key_pool_cap  = key_pool_bytes;
                this.key_pool_used = 0;
                this.buckets       = (HSBucket*)fmalloc(c * 24);
                this.key_pool      = (byte*)fmalloc(key_pool_bytes);
                while (i < c)
                {
                    this.buckets[i].key_hash = 0;
                    this.buckets[i].key      = (byte*)0;
                    this.buckets[i].psl      = 0;
                    i = i + 1;
                };
                -> this;
            };

            // exit: two frees, no loop.
            __exit() -> void
            {
                ffree((u64)this.buckets);
                ffree((u64)this.key_pool);
                this.buckets  = (HSBucket*)STDLIB_GVP;
                this.key_pool = (byte*)STDLIB_GVP;
                ->;
            };

            __expr() -> HashSet*
            {
                -> this;
            };

            // Internal: carve a copy of key from the pool (bump alloc, no malloc).
            // Returns pointer into pool, or STDLIB_GVP if pool is full.
            _hs_pool_dup(byte* src) -> byte*
            {
                u64   slen;
                byte* p    = src;
                while (p[slen] != 0)
                {
                    slen = slen + 1;
                };
                slen = slen + 1; // include null terminator
                if (this.key_pool_used + slen > this.key_pool_cap)
                {
                    -> (byte*)STDLIB_GVP;
                };
                byte* dst = this.key_pool + this.key_pool_used;
                u64   i;
                while (i < slen)
                {
                    dst[i] = src[i];
                    i = i + 1;
                };
                this.key_pool_used = this.key_pool_used + slen;
                -> dst;
            };

            // Internal: robin-hood insert of an already-pooled key.
            // No alloc/free anywhere in this function.
            _hs_probe(u64 hash, byte* key) -> void
            {
                u64 mask = this.cap - 1;
                u64 idx  = hash & mask,
                    psl;
                HSBucket ins, tmp;
                HSBucket* slot;
                ins.key_hash = hash;
                ins.key      = key;
                ins.psl      = 0;
                while (true)
                {
                    slot = this.buckets + idx;
                    if (slot.key_hash == 0)
                    {
                        slot.key_hash = ins.key_hash;
                        slot.key      = ins.key;
                        slot.psl      = ins.psl;
                        this.count    = this.count + 1;
                        ->;
                    };
                    if (slot.key_hash == ins.key_hash)
                    {
                        if (hm_str_eq(slot.key, ins.key))
                        {
                            ->;
                        };
                    };
                    if (slot.psl < ins.psl)
                    {
                        tmp.key_hash  = slot.key_hash;
                        tmp.key       = slot.key;
                        tmp.psl       = slot.psl;
                        slot.key_hash = ins.key_hash;
                        slot.key      = ins.key;
                        slot.psl      = ins.psl;
                        ins.key_hash  = tmp.key_hash;
                        ins.key       = tmp.key;
                        ins.psl       = tmp.psl;
                    };
                    idx = (idx + 1) & mask;
                    ins.psl = ins.psl + 1;
                    psl     = psl + 1;
                };
                ->;
            };

            // resize: one fmalloc before the loop, one ffree after. No alloc in loop.
            _hs_resize() -> void
            {
                u64 old_cap      = this.cap;
                u64 new_cap      = old_cap * 2;
                HSBucket* old_bk = this.buckets;
                u64 i            = 0;
                this.buckets     = (HSBucket*)fmalloc(new_cap * 24);
                this.cap         = new_cap;
                this.count       = 0;
                while (i < new_cap)
                {
                    this.buckets[i].key_hash = 0;
                    this.buckets[i].key      = (byte*)0;
                    this.buckets[i].psl      = 0;
                    i = i + 1;
                };
                i = 0;
                while (i < old_cap)
                {
                    if (old_bk[i].key_hash != 0)
                    {
                        this._hs_probe(old_bk[i].key_hash, old_bk[i].key);
                    };
                    i = i + 1;
                };
                ffree((u64)old_bk);
                ->;
            };

            set_add(byte* key) -> void
            {
                u64   hash = hm_hash_str(key);
                byte* pooled;
                if (this.count * 4 > this.cap * 3)
                {
                    this._hs_resize();
                };
                pooled = this._hs_pool_dup(key);
                if (pooled == (byte*)STDLIB_GVP)
                {
                    ->;
                };
                this._hs_probe(hash, pooled);
                ->;
            };

            set_has(byte* key) -> bool
            {
                u64 hash = hm_hash_str(key),
                    mask = this.cap - 1,
                    idx  = hash & mask,
                    psl  = 0;
                HSBucket* slot;
                while (true)
                {
                    slot = this.buckets + idx;
                    if (slot.key_hash == 0)
                    {
                        -> false;
                    };
                    if (slot.psl < psl)
                    {
                        -> false;
                    };
                    if (slot.key_hash == hash)
                    {
                        if (hm_str_eq(slot.key, key))
                        {
                            -> true;
                        };
                    };
                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                -> false;
            };

            // remove: backward-shift deletion. No alloc/free anywhere.
            // Keys remain in the pool (pool is not compacted on remove).
            set_remove(byte* key) -> bool
            {
                u64 hash = hm_hash_str(key),
                    mask = this.cap - 1;
                u64 idx  = hash & mask,
                    psl  = 0,
                    cur, next;
                HSBucket* slot, nx, cr;
                while (true)
                {
                    slot = this.buckets + idx;
                    if (slot.key_hash == 0)
                    {
                        -> false;
                    };
                    if (slot.psl < psl)
                    {
                        -> false;
                    };
                    if (slot.key_hash == hash)
                    {
                        if (hm_str_eq(slot.key, key))
                        {
                            slot.key_hash = 0;
                            slot.key      = (byte*)0;
                            slot.psl      = 0;
                            this.count    = this.count - 1;
                            cur  = idx;
                            next = (idx + 1) & mask;
                            while (true)
                            {
                                nx = this.buckets + next;
                                if (nx.key_hash == 0 | nx.psl == 0)
                                {
                                    break;
                                };
                                cr = this.buckets + cur;
                                cr.key_hash = nx.key_hash;
                                cr.key      = nx.key;
                                cr.psl      = nx.psl - 1;
                                nx.key_hash = 0;
                                nx.key      = (byte*)0;
                                nx.psl      = 0;
                                cur  = next;
                                next = (next + 1) & mask;
                            };
                            -> true;
                        };
                    };
                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                -> false;
            };

            set_count() -> u64
            {
                -> this.count;
            };

            set_capacity() -> u64
            {
                -> this.cap;
            };
        };

        // ============================================================================
        // HashSetInt  (u64 keys)
        // Robin-hood hash set for integer keys.
        // No string pool needed; __exit is a single ffree.
        //
        // Usage example:
        //   HashSetInt hsi((u64)16);
        //   hsi.seti_add((u64)42);
        //   bool found = hsi.seti_has((u64)42);
        //   hsi.seti_remove((u64)42);
        // ============================================================================

        struct HSIBucket
        {
            u64 key_hash, key, psl;
        };

        trait BaseSTDHashSetIntTraits
        {
            _hsib_probe(u64 hash, u64 key) -> void,
            _hsib_resize()                 -> void,
            seti_add(u64 key)              -> void,
            seti_has(u64 key)              -> bool,
            seti_remove(u64 key)           -> bool,
            seti_count()                   -> u64,
            seti_capacity()                -> u64;
        };

        BaseSTDHashSetIntTraits
        object HashSetInt
        {
            HSIBucket* buckets;
            u64        count,
                       cap;

            __init(u64 initial_cap) -> this
            {
                u64 c = 16, i;
                while (c < initial_cap)
                {
                    c = c * 2;
                };
                this.cap     = c;
                this.count   = 0;
                this.buckets = (HSIBucket*)fmalloc(c * 24);
                while (i < c)
                {
                    this.buckets[i].key_hash = 0;
                    this.buckets[i].key      = 0;
                    this.buckets[i].psl      = 0;
                    i = i + 1;
                };
                -> this;
            };

            __exit() -> void
            {
                ffree((u64)this.buckets);
                this.buckets = (HSIBucket*)STDLIB_GVP;
                ->;
            };

            __expr() -> HashSetInt*
            {
                -> this;
            };

            // No alloc/free in this function.
            _hsib_probe(u64 hash, u64 key) -> void
            {
                u64 mask = this.cap - 1;
                u64 idx  = hash & mask;
                HSIBucket ins, tmp;
                HSIBucket* slot;
                ins.key_hash = hash;
                ins.key      = key;
                ins.psl      = 0;
                while (true)
                {
                    slot = this.buckets + idx;
                    if (slot.key_hash == 0)
                    {
                        slot.key_hash = ins.key_hash;
                        slot.key      = ins.key;
                        slot.psl      = ins.psl;
                        this.count    = this.count + 1;
                        ->;
                    };
                    if (slot.key_hash == ins.key_hash & slot.key == ins.key)
                    {
                        ->;
                    };
                    if (slot.psl < ins.psl)
                    {
                        tmp.key_hash  = slot.key_hash;
                        tmp.key       = slot.key;
                        tmp.psl       = slot.psl;
                        slot.key_hash = ins.key_hash;
                        slot.key      = ins.key;
                        slot.psl      = ins.psl;
                        ins.key_hash  = tmp.key_hash;
                        ins.key       = tmp.key;
                        ins.psl       = tmp.psl;
                    };
                    idx     = (idx + 1) & mask;
                    ins.psl = ins.psl + 1;
                };
                ->;
            };

            // One fmalloc before loops, one ffree after. No alloc in loops.
            _hsib_resize() -> void
            {
                u64 old_cap       = this.cap;
                u64 new_cap       = old_cap * 2,
                    i;
                HSIBucket* old_bk = this.buckets;
                this.buckets      = (HSIBucket*)fmalloc(new_cap * 24);
                this.cap          = new_cap;
                this.count        = 0;
                while (i < new_cap)
                {
                    this.buckets[i].key_hash = 0;
                    this.buckets[i].key      = 0;
                    this.buckets[i].psl      = 0;
                    i = i + 1;
                };
                i = 0;
                while (i < old_cap)
                {
                    if (old_bk[i].key_hash != 0)
                    {
                        this._hsib_probe(old_bk[i].key_hash, old_bk[i].key);
                    };
                    i = i + 1;
                };
                ffree((u64)old_bk);
                ->;
            };

            seti_add(u64 key) -> void
            {
                u64 hash = hm_hash_u64(key);
                if (this.count * (u64)4 > this.cap * (u64)3)
                {
                    this._hsib_resize();
                };
                this._hsib_probe(hash, key);
                ->;
            };

            seti_has(u64 key) -> bool
            {
                u64 hash = hm_hash_u64(key),
                    mask = this.cap - 1;
                u64 idx  = hash & mask,
                    psl  = 0;
                HSIBucket* slot;
                while (true)
                {
                    slot = this.buckets + idx;
                    if (slot.key_hash == 0)
                    {
                        -> false;
                    };
                    if (slot.psl < psl)
                    {
                        -> false;
                    };
                    if (slot.key_hash == hash & slot.key == key)
                    {
                        -> true;
                    };
                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                -> false;
            };

            seti_remove(u64 key) -> bool
            {
                u64 hash = hm_hash_u64(key),
                    mask = this.cap - 1;
                u64 idx  = hash & mask,
                    psl  = 0,
                    cur, next;
                HSIBucket* slot, nx, cr;
                while (true)
                {
                    slot = this.buckets + idx;
                    if (slot.key_hash == 0)
                    {
                        -> false;
                    };
                    if (slot.psl < psl)
                    {
                        -> false;
                    };
                    if (slot.key_hash == hash & slot.key == key)
                    {
                        slot.key_hash = 0;
                        slot.key      = 0;
                        slot.psl      = 0;
                        this.count    = this.count - 1;
                        cur  = idx;
                        next = (idx + 1) & mask;
                        while (true)
                        {
                            nx = this.buckets + next;
                            if (nx.key_hash == 0 | nx.psl == 0)
                            {
                                break;
                            };
                            cr = this.buckets + cur;
                            cr.key_hash = nx.key_hash;
                            cr.key      = nx.key;
                            cr.psl      = nx.psl - 1;
                            nx.key_hash = 0;
                            nx.key      = 0;
                            nx.psl      = 0;
                            cur  = next;
                            next = (next + 1) & mask;
                        };
                        -> true;
                    };
                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                -> false;
            };

            seti_count() -> u64
            {
                -> this.count;
            };

            seti_capacity() -> u64
            {
                -> this.cap;
            };
        };

        // ============================================================================
        // MinHeap  (priority queue, smallest value at top)
        // Binary min-heap backed by a flat Array of void* pointers.
        // A user-supplied comparator determines ordering.
        //
        // Comparator signature:  my_cmp(void* a, void* b) -> int
        //   Return < 0 if a has higher priority (comes before b).
        //   Return   0 if equal.
        //   Return > 0 if b has higher priority.
        //
        // heap_push O(log n), heap_pop O(log n), heap_peek O(1).
        // The function pointer local is declared at function top, outside all loops.
        //
        // Usage example:
        //   int_cmp(void* a, void* b) -> int { -> *(int*)a - *(int*)b; };
        //   MinHeap h;
        //   h.__init(@int_cmp);
        //   int x = 3, y = 1;
        //   h.heap_push(@x);
        //   h.heap_push(@y);
        //   void* top = h.heap_pop(); // points to y (value 1)
        // ============================================================================

        trait BaseSTDMinHeapTraits
        {
            heap_push(void* value) -> bool,
            heap_pop()             -> void*,
            heap_peek()            -> void*,
            heap_len()             -> size_t,
            heap_empty()           -> bool,
            heap_clear()           -> void;
        };

        BaseSTDMinHeapTraits
        object MinHeap
        {
            Array  elems;   // stores void* pointers, elem_size = 8
            long   cmp_fn;  // comparator stored as raw address

            __init(void* cmp) -> this
            {
                this.elems.__init((size_t)8);
                this.cmp_fn = long(cmp);
                -> this;
            };

            __exit() -> void
            {
                this.elems.__exit();
                ->;
            };

            __expr() -> MinHeap*
            {
                -> this;
            };

            // ----------------------------------------------------------------
            // heap_push(value) - insert and sift up.
            // fp declared at function top, outside the sift loop.
            // ----------------------------------------------------------------
            heap_push(void* value) -> bool
            {
                // All locals at function top.
                def{}* fn_cmp(void*, void*) -> int = this.cmp_fn;
                size_t i, parent;
                void** pslot, islot;
                void*  pval, ival, tmp;
                if (!this.elems.push(@value))
                {
                    -> false;
                };
                i = this.elems.len - 1;
                while (i > 0)
                {
                    parent = (i - 1) / 2;
                    pslot  = (void**)this.elems.get(parent);
                    islot  = (void**)this.elems.get(i);
                    pval   = *pslot;
                    ival   = *islot;
                    if (fn_cmp(pval, ival) <= 0)
                    {
                        break;
                    };
                    *pslot = ival;
                    *islot = pval;
                    i      = parent;
                };
                -> true;
            };

            // ----------------------------------------------------------------
            // heap_pop() - remove and -> minimum.
            // All fp locals and temporaries declared at function top.
            // ----------------------------------------------------------------
            heap_pop() -> void*
            {
                // All locals at function top.
                def{}* fn_cmp(void*, void*) -> int = this.cmp_fn;
                size_t n, i, lft, rgt, smallest;
                void** root_slot,
                       last_slot,
                       lslot,
                       rslot,
                       sslot,
                       islot;
                void*  res, tmp;
                n = this.elems.len;
                if (n == 0)
                {
                    -> STDLIB_GVP;
                };
                root_slot        = (void**)this.elems.get(0);
                res              = *root_slot;
                last_slot        = (void**)this.elems.get(n - 1);
                *root_slot       = *last_slot;
                this.elems.len   = this.elems.len - 1;
                n                = this.elems.len;
                while (true)
                {
                    lft      = i * 2 + 1;
                    rgt      = i * 2 + 2;
                    smallest = i;
                    if (lft < n)
                    {
                        lslot = (void**)this.elems.get(lft);
                        sslot = (void**)this.elems.get(smallest);
                        if (fn_cmp(*lslot, *sslot) < 0)
                        {
                            smallest = lft;
                        };
                    };
                    if (rgt < n)
                    {
                        rslot = (void**)this.elems.get(rgt);
                        sslot = (void**)this.elems.get(smallest);
                        if (fn_cmp(*rslot, *sslot) < 0)
                        {
                            smallest = rgt;
                        };
                    };
                    if (smallest == i)
                    {
                        break;
                    };
                    islot    = (void**)this.elems.get(i);
                    sslot    = (void**)this.elems.get(smallest);
                    tmp      = *islot;
                    *islot   = *sslot;
                    *sslot   = tmp;
                    i        = smallest;
                };
                -> res;
            };

            heap_peek() -> void*
            {
                void** slot;
                if (this.elems.len == 0)
                {
                    -> STDLIB_GVP;
                };
                slot = (void**)this.elems.get(0);
                -> *slot;
            };

            heap_len() -> size_t
            {
                -> this.elems.len;
            };

            heap_empty() -> bool
            {
                -> this.elems.len == 0;
            };

            heap_clear() -> void
            {
                this.elems.clear();
                ->;
            };
        };

        // ============================================================================
        // Ptr<T>  (owning smart pointer)
        // Wraps a single heap-allocated T. Owns the allocation; frees on __exit.
        // Move semantics via the tie operator -- copy is not permitted.
        //
        // Usage example:
        //   Ptr<int> p;
        //   p.__init();                  // allocates zeroed T on the heap
        //   *p.get() = 42;
        //   int val = *p.get();          // 42
        //   p.reset();                   // frees and nulls the pointer
        //   bool live = p.valid();       // false after reset
        // ============================================================================

        trait BaseSTDSmartPtrTraits
        {
            get<T>()   -> T*,
            valid() -> bool,
            reset() -> void,
            take<T>()  -> T*;
        };

        BaseSTDSmartPtrTraits
        object SmartPtr<T>
        {
            T* raw;

            // Allocate a zeroed T on the heap.
            __init() -> this
            {
                this.raw = (T*)fmalloc(sizeof(T) / 8);
                -> this;
            };

            // Adopt an existing heap pointer (must have been allocated with fmalloc).
            __init(T* existing) -> this
            {
                this.raw = existing;
                -> this;
            };

            // Free the owned allocation, if any.
            __exit() -> void
            {
                if (this.raw != STDLIB_GVP)
                {
                    ffree(ulong(this.raw));
                    this.raw = (T*)STDLIB_GVP;
                };
                ->;
            };

            __expr() -> SmartPtr<T>*
            {
                -> this;
            };

            // ----------------------------------------------------------------
            // get() - -> the raw pointer. Null if not valid.
            // ----------------------------------------------------------------
            get() -> T*
            {
                -> this.raw;
            };

            // ----------------------------------------------------------------
            // valid() - true if the pointer is non-null.
            // ----------------------------------------------------------------
            valid() -> bool
            {
                -> this.raw != (T*)STDLIB_GVP;
            };

            // ----------------------------------------------------------------
            // reset() - free the owned allocation and null the pointer.
            // ----------------------------------------------------------------
            reset() -> void
            {
                if (this.raw != (T*)STDLIB_GVP)
                {
                    ffree(ulong(this.raw));
                    this.raw = (T*)STDLIB_GVP;
                };
                ->;
            };

            // ----------------------------------------------------------------
            // take() - relinquish ownership and -> the raw pointer.
            // The caller is responsible for freeing it. Ptr is left null.
            // ----------------------------------------------------------------
            take() -> T*
            {
                T* out  = this.raw;
                this.raw = (T*)STDLIB_GVP;
                -> out;
            };
        };
    };
};

#endif;
