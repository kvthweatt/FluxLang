// redhashmap.fx - Flux HashMap Library
//
// Open-addressed hash map with robin hood linear probing.
// Keys are byte* (null-terminated strings) or u64 integers.
// Values are void* (8 bytes; store any pointer or integer via cast).
//
// Two map variants:
//   HashMap       - string keys  (byte*)
//   HashMapInt    - u64 keys
//
// Both share the same internal bucket layout:
//   key_hash  : cached hash of the key (0 = empty slot)
//   key       : string pointer OR raw u64 integer key
//   value     : void* stored value
//   psl       : probe sequence length (robin hood displacement)
//
// Load factor cap: 75%.  Resize doubles capacity and rehashes.
// Default initial capacity: 16 buckets.
//
// API (HashMap / string keys):
//   hm_init(u64 capacity)   -> HashMap
//   hm_free()               -> void
//   hm_set(byte* key, void* value) -> void
//   hm_get(byte* key)              -> void*   (NULL if not found)
//   hm_has(byte* key)              -> bool
//   hm_remove(byte* key)           -> bool    (true if removed)
//   hm_count()                     -> u64
//   hm_capacity()                  -> u64
//
// API (HashMapInt / u64 keys):
//   hmi_init(u64 capacity)         -> HashMapInt
//   hmi_free()                     -> void
//   hmi_set(u64 key, void* value)  -> void
//   hmi_get(u64 key)               -> void*
//   hmi_has(u64 key)               -> bool
//   hmi_remove(u64 key)            -> bool
//   hmi_count()                    -> u64
//   hmi_capacity()                 -> u64

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import "redmemory.fx";
#endif;

#ifndef FLUX_STANDARD_HASHMAP
#def FLUX_STANDARD_HASHMAP 1;


// -------------------------------------------------------------------------
// HashMap (string keys)
// -------------------------------------------------------------------------

namespace standard
{
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
        def hm_hash_str(byte* key) -> u64
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
            return hash;
        };

        // Murmur-inspired mix for integer keys
        def hm_hash_u64(u64 key) -> u64
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
            return h;
        };

        // -------------------------------------------------------------------------
        // String comparison helper
        // -------------------------------------------------------------------------

        def hm_str_eq(byte* a, byte* b) -> bool
        {
            int i;
            while (true)
            {
                if (a[i] != b[i])
                {
                    return false;
                };
                if (a[i] == 0)
                {
                    return true;
                };
                i = i + 1;
            };
            return false;
        };

        // -------------------------------------------------------------------------
        // String key copy helper (allocates new buffer)
        // -------------------------------------------------------------------------

        def hm_str_dup(byte* src) -> byte*
        {
            int len, i;
            while (src[len] != 0)
            {
                len = len + 1;
            };
            byte* dst = (byte*)stdheap::fmalloc(len + 1);
            while (i < len)
            {
                dst[i] = src[i];
                i = i + 1;
            };
            dst[len] = 0;
            return dst;
        };

        object HashMap
        {
            HMBucket* buckets;
            u64       count,
                      cap;

            def __init(u64 initial_cap) -> this
            {
                // Round up to next power of two, minimum 16
                u64 c = 16;
                while (c < initial_cap)
                {
                    c = c * 2;
                };
                this.cap     = c;
                this.count   = 0;
                u64 nbytes   = c * 32; // sizeof(HMBucket) = 32
                this.buckets = (HMBucket*)stdheap::fmalloc(nbytes);
                // Zero all buckets (key_hash == 0 means empty)
                u64 i = 0;
                while (i < c)
                {
                    this.buckets[i].key_hash = 0;
                    this.buckets[i].key      = (byte*)0;
                    this.buckets[i].value    = (void*)0;
                    this.buckets[i].psl      = 0;
                    i = i + (u64)1;
                };
                return this;
            };

            def __exit() -> void
            {
                // Free all duplicated key strings
                u64 i;
                while (i < this.cap)
                {
                    if (this.buckets[i].key_hash != 0)
                    {
                        stdheap::ffree((u64)this.buckets[i].key);
                    };
                    i = i + 1;
                };
                stdheap::ffree((u64)this.buckets);
            };

            // Internal: insert without copying key (used during resize)
            def _insert_nocopy(u64 hash, byte* key, void* value) -> void
            {
                u64 mask = this.cap - (u64)1;
                u64 idx  = hash & mask,
                    psl;

                HMBucket insert_bkt;
                insert_bkt.key_hash = hash;
                insert_bkt.key      = key;
                insert_bkt.value    = value;
                insert_bkt.psl      = psl;

                while (true)
                {
                    HMBucket* slot = this.buckets + idx;

                    // Empty slot: place here
                    if (slot.key_hash == 0)
                    {
                        slot.key_hash = insert_bkt.key_hash;
                        slot.key      = insert_bkt.key;
                        slot.value    = insert_bkt.value;
                        slot.psl      = insert_bkt.psl;
                        this.count    = this.count + 1;
                        return;
                    };

                    // Same key: update value
                    if (slot.key_hash == insert_bkt.key_hash)
                    {
                        if (hm_str_eq(slot.key, insert_bkt.key))
                        {
                            slot.value = insert_bkt.value;
                            return;
                        };
                    };

                    // Robin hood: steal from rich slot
                    if (slot.psl < insert_bkt.psl)
                    {
                        // Swap insert_bkt with slot
                        HMBucket tmp;
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
            def _resize() -> void
            {
                u64 old_cap   = this.cap,
                    new_cap   = old_cap * 2,
                    nbytes    = new_cap * 32,
                    i;
                HMBucket* old_buckets = this.buckets;

                this.buckets  = (HMBucket*)stdheap::fmalloc(nbytes);
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

                stdheap::ffree((u64)old_buckets);
            };

            // Insert or update a key-value pair.
            def hm_set(byte* key, void* value) -> void
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

                HMBucket insert_bkt;
                insert_bkt.key_hash = hash;
                insert_bkt.key      = hm_str_dup(key);
                insert_bkt.value    = value;
                insert_bkt.psl      = psl;

                while (true)
                {
                    HMBucket* slot = this.buckets + idx;

                    // Empty slot
                    if (slot.key_hash == 0)
                    {
                        slot.key_hash = insert_bkt.key_hash;
                        slot.key      = insert_bkt.key;
                        slot.value    = insert_bkt.value;
                        slot.psl      = insert_bkt.psl;
                        this.count    = this.count + (u64)1;
                        return;
                    };

                    // Existing key: update, free the new dup
                    if (slot.key_hash == insert_bkt.key_hash)
                    {
                        if (hm_str_eq(slot.key, insert_bkt.key))
                        {
                            stdheap::ffree((u64)insert_bkt.key);
                            slot.value = insert_bkt.value;
                            return;
                        };
                    };

                    // Robin hood swap
                    if (slot.psl < insert_bkt.psl)
                    {
                        HMBucket tmp;
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
            def hm_get(byte* key) -> void*
            {
                u64 hash = hm_hash_str(key),
                    mask = this.cap - 1,
                    idx  = hash & mask,
                    psl  = 0;

                while (true)
                {
                    HMBucket* slot = this.buckets + idx;

                    if (slot.key_hash == 0)
                    {
                        return (void*)0;
                    };

                    if (slot.psl < psl)
                    {
                        // Robin hood invariant: can't be further than this
                        return (void*)0;
                    };

                    if (slot.key_hash == hash)
                    {
                        if (hm_str_eq(slot.key, key))
                        {
                            return slot.value;
                        };
                    };

                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                return (void*)0;
            };

            // Check if a key exists.
            def hm_has(byte* key) -> bool
            {
                return this.hm_get(key) != (void*)0;
            };

            // Remove a key. Returns true if it was present.
            def hm_remove(byte* key) -> bool
            {
                u64 hash = hm_hash_str(key),
                    mask = this.cap - 1;
                u64 idx  = hash & mask,
                    psl  = 0;

                while (true)
                {
                    HMBucket* slot = this.buckets + idx;

                    if (slot.key_hash == 0)
                    {
                        return false;
                    };

                    if (slot.psl < psl)
                    {
                        return false;
                    };

                    if (slot.key_hash == hash)
                    {
                        if (hm_str_eq(slot.key, key))
                        {
                            // Free the duplicated key
                            stdheap::ffree((u64)slot.key);
                            slot.key_hash = 0;
                            slot.key      = (byte*)0;
                            slot.value    = (void*)0;
                            slot.psl      = 0;
                            this.count    = this.count - 1;

                            // Backward shift deletion to maintain robin hood invariant
                            u64 cur  = idx;
                            u64 next = (idx + 1) & mask;
                            while (true)
                            {
                                HMBucket* nx = this.buckets + next;
                                if (nx.key_hash == 0 | nx.psl == 0)
                                {
                                    break;
                                };
                                HMBucket* cr = this.buckets + cur;
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

                            return true;
                        };
                    };

                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                return false;
            };

            def hm_count() -> u64
            {
                return this.count;
            };

            def hm_capacity() -> u64
            {
                return this.cap;
            };
        };

        // -------------------------------------------------------------------------
        // HashMapInt (u64 keys)
        // -------------------------------------------------------------------------

        object HashMapInt
        {
            HMIBucket* buckets;
            u64        count;
            u64        cap;

            def __init(u64 initial_cap) -> this
            {
                u64 c = 16,
                    nbytes   = c * 32, // sizeof(HMIBucket) = 32
                    i;
                while (c < initial_cap)
                {
                    c = c * 2;
                };
                this.cap     = c;
                this.count   = 0;
                this.buckets = (HMIBucket*)stdheap::fmalloc(nbytes);
                while (i < c)
                {
                    this.buckets[i].key_hash = 0;
                    this.buckets[i].key      = 0;
                    this.buckets[i].value    = (void*)0;
                    this.buckets[i].psl      = 0;
                    i = i + 1;
                };
                return this;
            };

            def __exit() -> void
            {
                stdheap::ffree((u64)this.buckets);
            };

            def _insert_raw(u64 hash, u64 key, void* value) -> void
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
                        return;
                    };

                    if (slot.key_hash == ins.key_hash & slot.key == ins.key)
                    {
                        slot.value = ins.value;
                        return;
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

            def _resize() -> void
            {
                u64 old_cap     = this.cap;
                u64 new_cap   = old_cap * 2;
                u64 nbytes    = new_cap * 32;
                HMIBucket* old_buckets = this.buckets;

                this.buckets  = (HMIBucket*)stdheap::fmalloc(nbytes);
                this.cap      = new_cap;
                this.count    = 0;

                u64 i;
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

                stdheap::ffree((u64)old_buckets);
            };

            def hmi_set(u64 key, void* value) -> void
            {
                if (this.count * (u64)4 > this.cap * (u64)3)
                {
                    this._resize();
                };
                u64 hash = hm_hash_u64(key);
                this._insert_raw(hash, key, value);
            };

            def hmi_get(u64 key) -> void*
            {
                u64 hash = hm_hash_u64(key),
                    mask = this.cap - 1;
                u64 idx  = hash & mask,
                    psl  = 0;

                while (true)
                {
                    HMIBucket* slot = this.buckets + idx;

                    if (slot.key_hash == 0)
                    {
                        return (void*)0;
                    };

                    if (slot.psl < psl)
                    {
                        return (void*)0;
                    };

                    if (slot.key_hash == hash & slot.key == key)
                    {
                        return slot.value;
                    };

                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                return (void*)0;
            };

            def hmi_has(u64 key) -> bool
            {
                return this.hmi_get(key) != (void*)0;
            };

            def hmi_remove(u64 key) -> bool
            {
                u64 hash = hm_hash_u64(key),
                    mask = this.cap - (u64)1;
                u64 idx  = hash & mask,
                    psl  = 0,
                    cur, next;

                HMIBucket* slot, nx, cr;

                while (true)
                {
                    slot = this.buckets + idx;

                    if (slot.key_hash == 0)
                    {
                        return false;
                    };

                    if (slot.psl < psl)
                    {
                        return false;
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

                        return true;
                    };

                    idx = (idx + 1) & mask;
                    psl = psl + 1;
                };
                return false;
            };

            def hmi_count() -> u64
            {
                return this.count;
            };

            def hmi_capacity() -> u64
            {
                return this.cap;
            };
        };
    };
};

#endif;
