// Author: Karac V. Thweatt

// containers.fx - Typed, generic containers for Flux.
//
// Unlike collections.fx (void* / byte payloads), every container here is a
// template over its element type, so no casts are needed at the call site and
// elements are stored by value.
//
//   DynArray<T>     growable array
//   RingBuffer<T>   growable double-ended ring buffer
//   MinHeap<T>      binary min-heap, ordered with the `<` operator (user types may overload it)
//   HashMap<K,V>    open-addressing hash map for integer-like keys (ints, enums, pointers)
//   HashSet<K>      hash set for integer-like keys
//   StrHashMap<V>   hash map with string keys (keys are copied and owned by the map)
//
// Absence is expressed with the language's own idioms rather than wrapper types:
//   get(key, V* out) -> bool     false when the key is absent, *out untouched
//   get_or(key, fallback) -> V   the value, or fallback
//   find(key) -> V*              pointer to the stored value, or null (`!?` / `??` apply)
//
// Elements are copied with `=`. Containers free their own storage in __exit.
//
// Dependencies: standard::types, standard::memory (fmalloc / ffree)

#ifndef FLUX_STANDARD_TYPES
#import <types.fx>;
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import <memory.fx>;
#endif;

#ifndef FLUX_STANDARD_CONTAINERS
#FLUX_STANDARD_CONTAINERS 1;

namespace standard
{
    namespace containers
    {
        // ====================================================================
        // Hashing helpers
        // ====================================================================

        // splitmix64 finalizer: mixes any integer-like key into a well spread hash.
        key_hash<K>(K k) -> u64
        {
            u64 x = (u64)k + (u64)0x9E3779B97F4A7C15;
            x = (x `^| (x >> 30)) * (u64)0xBF58476D1CE4E5B9;
            x = (x `^| (x >> 27)) * (u64)0x94D049BB133111EB;
            -> x `^| (x >> 31);
        };

        // FNV-1a over a null-terminated string.
        str_hash(byte* s) -> u64
        {
            u64 h = (u64)0xCBF29CE484222325;
            int i;
            while (s[i] != (byte)0)
            {
                h = (h `^| (u64)s[i]) * (u64)0x100000001B3;
                i++;
            };
            -> h;
        };

        str_eq(byte* a, byte* b) -> bool
        {
            int i;
            while (a[i] != (byte)0 & b[i] != (byte)0)
            {
                if (a[i] != b[i]) { -> false; };
                i++;
            };
            -> a[i] == b[i];
        };

        str_dup(byte* s) -> byte*
        {
            int n;
            while (s[n] != (byte)0) { n++; };
            byte* d = (byte*)fmalloc((size_t)(n + 1));
            int i;
            while (i <= n) { d[i] = s[i]; i++; };
            -> d;
        };

        // ====================================================================
        // DynArray<T>
        // ====================================================================

        trait BaseSTD_COMMON_BUFFER_Traits
        {
            len() -> size_t,
            is_empty() -> bool,
            clear() -> void;
        };
        trait BaseSTD_COMMON_BUFFER_Traits_Ext
        {
            capacity() -> size_t,
            reserve(size_t n) -> bool,
        };

        BaseSTD_COMMON_BUFFER_Traits BaseSTD_COMMON_BUFFER_Traits_Ext
        object DynArray<T>
        {
            T*     buf;
            size_t n,
                   cap;

            __init() -> this
            {
                this.buf = (T*)STDLIB_GVP;
                this.n   = 0;
                this.cap = 0;
                -> this;
            };

            __init(size_t initial) -> this
            {
                this.buf = (T*)STDLIB_GVP;
                this.n   = 0;
                this.cap = 0;
                this.reserve(initial);
                -> this;
            };

            __exit() -> void
            {
                if (this.buf != (T*)STDLIB_GVP)
                {
                    ffree((byte*)this.buf);
                    this.buf = (T*)STDLIB_GVP;
                };
                ->;
            };

            __expr() -> DynArray<T>*
            {
                -> this;
            };

            len() -> size_t { -> this.n; };

            capacity() -> size_t { -> this.cap; };

            is_empty() -> bool { -> this.n == 0; };

            // Ensures room for at least `want` elements. False on allocation failure.
            reserve(size_t want) -> bool
            {
                if (want <= this.cap) { -> true; };
                size_t nc = this.cap == 0 ? 8 : this.cap;
                while (nc < want) { nc = nc * 2; };
                T* nb = (T*)fmalloc(nc * (sizeof(T) / 8));
                if (nb == (T*)STDLIB_GVP) { -> false; };
                size_t i;
                while (i < this.n)
                {
                    nb[i] = this.buf[i];
                    i++;
                };
                if (this.buf != (T*)STDLIB_GVP) { ffree((byte*)this.buf); };
                this.buf = nb;
                this.cap = nc;
                -> true;
            };

            push(T v) -> bool
            {
                if (!this.reserve(this.n + 1)) { -> false; };
                this.buf[this.n] = v;
                this.n++;
                -> true;
            };

            // Removes the last element into *out. False when empty.
            pop(T* out) -> bool
            {
                if (this.n == 0) { -> false; };
                this.n--;
                *out = this.buf[this.n];
                -> true;
            };

            // Element access. The index must be below len().
            at(size_t i) -> T
            {
                -> this.buf[i];
            };

            // Pointer to element i, or null when out of range.
            ptr(size_t i) -> T*
            {
                if (i >= this.n) { -> (T*)STDLIB_GVP; };
                -> @this.buf[i];
            };

            // Checked read: false when i is out of range.
            get(size_t i, T* out) -> bool
            {
                if (i >= this.n) { -> false; };
                *out = this.buf[i];
                -> true;
            };

            set(size_t i, T v) -> bool
            {
                if (i >= this.n) { -> false; };
                this.buf[i] = v;
                -> true;
            };

            // Raw storage, valid until the next growth.
            raw() -> T*
            {
                -> this.buf;
            };

            insert(size_t i, T v) -> bool
            {
                if (i > this.n) { -> false; };
                if (!this.reserve(this.n + 1)) { -> false; };
                size_t k = this.n;
                while (k > i)
                {
                    this.buf[k] = this.buf[k - 1];
                    k--;
                };
                this.buf[i] = v;
                this.n++;
                -> true;
            };

            // Removes element i, keeping order.
            remove_at(size_t i) -> bool
            {
                if (i >= this.n) { -> false; };
                size_t k = i;
                while (k + 1 < this.n)
                {
                    this.buf[k] = this.buf[k + 1];
                    k++;
                };
                this.n--;
                -> true;
            };

            // Removes element i by moving the last element into its place. O(1), order not kept.
            swap_remove(size_t i) -> bool
            {
                if (i >= this.n) { -> false; };
                this.n--;
                this.buf[i] = this.buf[this.n];
                -> true;
            };

            // Index of the first element equal to v, or -1.
            index_of(T v) -> i64
            {
                size_t i;
                while (i < this.n)
                {
                    if (this.buf[i] == v) { -> (i64)i; };
                    i++;
                };
                -> (i64)-1;
            };

            contains(T v) -> bool
            {
                -> this.index_of(v) >= (i64)0;
            };

            clear() -> void
            {
                this.n = 0;
                ->;
            };
        };

        // ====================================================================
        // RingBuffer<T>: growable double-ended queue on a ring buffer
        // ====================================================================

        BaseSTD_COMMON_BUFFER_Traits
        object RingBuffer<T>
        {
            T*     buf;
            size_t head,
                   n,
                   cap;

            __init() -> this
            {
                this.buf  = (T*)STDLIB_GVP;
                this.head = 0;
                this.n    = 0;
                this.cap  = 0;
                -> this;
            };

            __exit() -> void
            {
                if (this.buf != (T*)STDLIB_GVP)
                {
                    ffree((byte*)this.buf);
                    this.buf = (T*)STDLIB_GVP;
                };
                ->;
            };

            __expr() -> RingBuffer<T>*
            {
                -> this;
            };

            len() -> size_t { -> this.n; };

            is_empty() -> bool { -> this.n == 0; };

            _grow() -> bool
            {
                size_t nc = this.cap == 0 ? 8 : this.cap * 2;
                T* nb = (T*)fmalloc(nc * (sizeof(T) / 8));
                if (nb == (T*)STDLIB_GVP) { -> false; };
                size_t i;
                while (i < this.n)
                {
                    nb[i] = this.buf[(this.head + i) % this.cap];
                    i++;
                };
                if (this.buf != (T*)STDLIB_GVP) { ffree((byte*)this.buf); };
                this.buf  = nb;
                this.head = 0;
                this.cap  = nc;
                -> true;
            };

            push_back(T v) -> bool
            {
                if (this.n == this.cap)
                {
                    if (!this._grow()) { -> false; };
                };
                this.buf[(this.head + this.n) % this.cap] = v;
                this.n++;
                -> true;
            };

            push_front(T v) -> bool
            {
                if (this.n == this.cap)
                {
                    if (!this._grow()) { -> false; };
                };
                this.head = (this.head + this.cap - 1) % this.cap;
                this.buf[this.head] = v;
                this.n++;
                -> true;
            };

            pop_front(T* out) -> bool
            {
                if (this.n == 0) { -> false; };
                *out = this.buf[this.head];
                this.head = (this.head + 1) % this.cap;
                this.n--;
                -> true;
            };

            pop_back(T* out) -> bool
            {
                if (this.n == 0) { -> false; };
                this.n--;
                *out = this.buf[(this.head + this.n) % this.cap];
                -> true;
            };

            peek_front(T* out) -> bool
            {
                if (this.n == 0) { -> false; };
                *out = this.buf[this.head];
                -> true;
            };

            peek_back(T* out) -> bool
            {
                if (this.n == 0) { -> false; };
                *out = this.buf[(this.head + this.n - 1) % this.cap];
                -> true;
            };

            // Element i counted from the front. The index must be below len().
            at(size_t i) -> T
            {
                -> this.buf[(this.head + i) % this.cap];
            };

            clear() -> void
            {
                this.head = 0;
                this.n    = 0;
                ->;
            };
        };

        // ====================================================================
        // MinHeap<T>: binary min-heap ordered by `<`
        // ====================================================================

        BaseSTD_COMMON_BUFFER_Traits
        object MinHeap<T>
        {
            T*     buf;
            size_t n,
                   cap;

            __init() -> this
            {
                this.buf = (T*)STDLIB_GVP;
                this.n   = 0;
                this.cap = 0;
                -> this;
            };

            __exit() -> void
            {
                if (this.buf != (T*)STDLIB_GVP)
                {
                    ffree((byte*)this.buf);
                    this.buf = (T*)STDLIB_GVP;
                };
                ->;
            };

            __expr() -> MinHeap<T>*
            {
                -> this;
            };

            len() -> size_t { -> this.n; };

            is_empty() -> bool { -> this.n == 0; };

            push(T v) -> bool
            {
                if (this.n == this.cap)
                {
                    size_t nc = this.cap == 0 ? 8 : this.cap * 2;
                    T* nb = (T*)fmalloc(nc * (sizeof(T) / 8));
                    if (nb == (T*)STDLIB_GVP) { -> false; };
                    size_t j;
                    while (j < this.n)
                    {
                        nb[j] = this.buf[j];
                        j++;
                    };
                    if (this.buf != (T*)STDLIB_GVP) { ffree((byte*)this.buf); };
                    this.buf = nb;
                    this.cap = nc;
                };
                size_t i = this.n;
                this.n++;
                size_t parent;
                while (i > 0)
                {
                    parent = (i - 1) / 2;
                    if (!(v < this.buf[parent])) { break; };
                    this.buf[i] = this.buf[parent];
                    i = parent;
                };
                this.buf[i] = v;
                -> true;
            };

            // Smallest element without removing it.
            peek(T* out) -> bool
            {
                if (this.n == 0) { -> false; };
                *out = this.buf[0];
                -> true;
            };

            // Removes the smallest element into *out.
            pop(T* out) -> bool
            {
                if (this.n == 0) { -> false; };
                *out = this.buf[0];
                this.n--;
                if (this.n == 0) { -> true; };
                T last = this.buf[this.n];
                size_t i = 0;
                size_t child;
                while (true)
                {
                    child = i * 2 + 1;
                    if (child >= this.n) { break; };
                    if (child + 1 < this.n & this.buf[child + 1] < this.buf[child]) { child++; };
                    if (!(this.buf[child] < last)) { break; };
                    this.buf[i] = this.buf[child];
                    i = child;
                };
                this.buf[i] = last;
                -> true;
            };

            clear() -> void
            {
                this.n = 0;
                ->;
            };
        };

        // ====================================================================
        // HashMap<K,V>: open addressing, linear probing, tombstone deletion.
        // K must be integer-like (casts to u64) and comparable with ==.
        // Slot states: 0 empty, 1 full, 2 deleted.
        // ====================================================================

        BaseSTD_COMMON_BUFFER_Traits
        object HashMap<K, V>
        {
            K*     keys;
            V*     vals;
            byte*  state;
            size_t n,
                   used,
                   cap;

            __init() -> this
            {
                this.keys  = (K*)STDLIB_GVP;
                this.vals  = (V*)STDLIB_GVP;
                this.state = (byte*)STDLIB_GVP;
                this.n     = 0;
                this.used  = 0;
                this.cap   = 0;
                -> this;
            };

            __exit() -> void
            {
                if (this.state != (byte*)STDLIB_GVP)
                {
                    ffree((byte*)this.keys);
                    ffree((byte*)this.vals);
                    ffree(this.state);
                    this.state = (byte*)STDLIB_GVP;
                };
                ->;
            };

            __expr() -> HashMap<K, V>*
            {
                -> this;
            };

            len() -> size_t { -> this.n; };

            is_empty() -> bool { -> this.n == 0; };

            // Slot holding key, or -1.
            _find(K key) -> i64
            {
                if (this.cap == 0) { -> (i64)-1; };
                size_t mask = this.cap - 1;
                size_t i = (size_t)(key_hash(key) `& (u64)mask);
                size_t probes;
                while (probes < this.cap)
                {
                    if (this.state[i] == (byte)0) { -> (i64)-1; };
                    if (this.state[i] == (byte)1 & this.keys[i] == key) { -> (i64)i; };
                    i = (i + 1) `& mask;
                    probes++;
                };
                -> (i64)-1;
            };

            _rehash(size_t ncap) -> bool
            {
                K*    ok = this.keys;
                V*    ov = this.vals;
                byte* os = this.state;
                size_t oc = this.cap;
                K*    nk = (K*)fmalloc(ncap * (sizeof(K) / 8));
                V*    nv = (V*)fmalloc(ncap * (sizeof(V) / 8));
                byte* ns = (byte*)fmalloc(ncap);
                if (nk == (K*)STDLIB_GVP | nv == (V*)STDLIB_GVP | ns == (byte*)STDLIB_GVP) { -> false; };
                size_t i;
                while (i < ncap) { ns[i] = (byte)0; i++; };
                this.keys  = nk;
                this.vals  = nv;
                this.state = ns;
                this.cap   = ncap;
                this.n     = 0;
                this.used  = 0;
                size_t mask = ncap - 1;
                size_t j, s;
                while (j < oc)
                {
                    if (os[j] == (byte)1)
                    {
                        s = (size_t)(key_hash(ok[j]) `& (u64)mask);
                        while (this.state[s] != (byte)0) { s = (s + 1) `& mask; };
                        this.state[s] = (byte)1;
                        this.keys[s]  = ok[j];
                        this.vals[s]  = ov[j];
                        this.n++;
                        this.used++;
                    };
                    j++;
                };
                if (os != (byte*)STDLIB_GVP)
                {
                    ffree((byte*)ok);
                    ffree((byte*)ov);
                    ffree(os);
                };
                -> true;
            };

            // Inserts or replaces. False on allocation failure.
            put(K key, V value) -> bool
            {
                i64 f = this._find(key);
                if (f >= (i64)0)
                {
                    this.vals[(size_t)f] = value;
                    -> true;
                };
                // Keep (full + deleted) below 70 percent of capacity
                if (this.cap == 0)
                {
                    if (!this._rehash(16)) { -> false; };
                }
                elif ((this.used + 1) * 10 > this.cap * 7)
                {
                    size_t target = this.cap;
                    if ((this.n + 1) * 10 > this.cap * 35 / 10) { target = this.cap * 2; };
                    if (!this._rehash(target)) { -> false; };
                };
                size_t mask = this.cap - 1;
                size_t i = (size_t)(key_hash(key) `& (u64)mask);
                while (this.state[i] == (byte)1) { i = (i + 1) `& mask; };
                if (this.state[i] == (byte)0) { this.used++; };
                this.state[i] = (byte)1;
                this.keys[i]  = key;
                this.vals[i]  = value;
                this.n++;
                -> true;
            };

            // Reads the value for key into *out. False when absent.
            get(K key, V* out) -> bool
            {
                i64 f = this._find(key);
                if (f < (i64)0) { -> false; };
                *out = this.vals[(size_t)f];
                -> true;
            };

            get_or(K key, V fallback) -> V
            {
                i64 f = this._find(key);
                if (f < (i64)0) { -> fallback; };
                -> this.vals[(size_t)f];
            };

            // Pointer to the stored value, or null when absent. Valid until the next insert.
            find(K key) -> V*
            {
                i64 f = this._find(key);
                if (f < (i64)0) { -> (V*)STDLIB_GVP; };
                -> @this.vals[(size_t)f];
            };

            contains(K key) -> bool
            {
                -> this._find(key) >= (i64)0;
            };

            remove(K key) -> bool
            {
                i64 f = this._find(key);
                if (f < (i64)0) { -> false; };
                this.state[(size_t)f] = (byte)2;
                this.n--;
                -> true;
            };

            clear() -> void
            {
                size_t i;
                while (i < this.cap) { this.state[i] = (byte)0; i++; };
                this.n    = 0;
                this.used = 0;
                ->;
            };

            // Iteration over slots: for (size_t i = 0; i < m.slots(); i++) { if (m.slot_used(i)) ... }
            slots() -> size_t { -> this.cap; };

            slot_used(size_t i) -> bool
            {
                -> i < this.cap & this.state[i] == (byte)1;
            };

            key_at(size_t i) -> K { -> this.keys[i]; };

            val_at(size_t i) -> V { -> this.vals[i]; };
        };

        // ====================================================================
        // HashSet<K>: hash set of integer-like keys
        // ====================================================================

        BaseSTD_COMMON_BUFFER_Traits
        object HashSet<K>
        {
            K*     keys;
            byte*  state;
            size_t n,
                   used,
                   cap;

            __init() -> this
            {
                this.keys  = (K*)STDLIB_GVP;
                this.state = (byte*)STDLIB_GVP;
                this.n     = 0;
                this.used  = 0;
                this.cap   = 0;
                -> this;
            };

            __exit() -> void
            {
                if (this.state != (byte*)STDLIB_GVP)
                {
                    ffree((byte*)this.keys);
                    ffree(this.state);
                    this.state = (byte*)STDLIB_GVP;
                };
                ->;
            };

            __expr() -> HashSet<K>*
            {
                -> this;
            };

            len() -> size_t { -> this.n; };

            is_empty() -> bool { -> this.n == 0; };

            _find(K key) -> i64
            {
                if (this.cap == 0) { -> (i64)-1; };
                size_t mask = this.cap - 1;
                size_t i = (size_t)(key_hash(key) `& (u64)mask);
                size_t probes;
                while (probes < this.cap)
                {
                    if (this.state[i] == (byte)0) { -> (i64)-1; };
                    if (this.state[i] == (byte)1 & this.keys[i] == key) { -> (i64)i; };
                    i = (i + 1) `& mask;
                    probes++;
                };
                -> (i64)-1;
            };

            _rehash(size_t ncap) -> bool
            {
                K*    ok = this.keys;
                byte* os = this.state;
                size_t oc = this.cap;
                K*    nk = (K*)fmalloc(ncap * (sizeof(K) / 8));
                byte* ns = (byte*)fmalloc(ncap);
                if (nk == (K*)STDLIB_GVP | ns == (byte*)STDLIB_GVP) { -> false; };
                size_t i;
                while (i < ncap) { ns[i] = (byte)0; i++; };
                this.keys  = nk;
                this.state = ns;
                this.cap   = ncap;
                this.n     = 0;
                this.used  = 0;
                size_t mask = ncap - 1;
                size_t j, s;
                while (j < oc)
                {
                    if (os[j] == (byte)1)
                    {
                        s = (size_t)(key_hash(ok[j]) `& (u64)mask);
                        while (this.state[s] != (byte)0) { s = (s + 1) `& mask; };
                        this.state[s] = (byte)1;
                        this.keys[s]  = ok[j];
                        this.n++;
                        this.used++;
                    };
                    j++;
                };
                if (os != (byte*)STDLIB_GVP)
                {
                    ffree((byte*)ok);
                    ffree(os);
                };
                -> true;
            };

            // Adds key. True when it was newly added, false when it was already present
            // (or allocation failed; check len() if that matters).
            add(K key) -> bool
            {
                if (this._find(key) >= (i64)0) { -> false; };
                if (this.cap == 0)
                {
                    if (!this._rehash(16)) { -> false; };
                }
                elif ((this.used + 1) * 10 > this.cap * 7)
                {
                    size_t target = this.cap;
                    if ((this.n + 1) * 10 > this.cap * 35 / 10) { target = this.cap * 2; };
                    if (!this._rehash(target)) { -> false; };
                };
                size_t mask = this.cap - 1;
                size_t i = (size_t)(key_hash(key) `& (u64)mask);
                while (this.state[i] == (byte)1) { i = (i + 1) `& mask; };
                if (this.state[i] == (byte)0) { this.used++; };
                this.state[i] = (byte)1;
                this.keys[i]  = key;
                this.n++;
                -> true;
            };

            contains(K key) -> bool
            {
                -> this._find(key) >= (i64)0;
            };

            remove(K key) -> bool
            {
                i64 f = this._find(key);
                if (f < (i64)0) { -> false; };
                this.state[(size_t)f] = (byte)2;
                this.n--;
                -> true;
            };

            clear() -> void
            {
                size_t i;
                while (i < this.cap) { this.state[i] = (byte)0; i++; };
                this.n    = 0;
                this.used = 0;
                ->;
            };

            slots() -> size_t { -> this.cap; };

            slot_used(size_t i) -> bool
            {
                -> i < this.cap & this.state[i] == (byte)1;
            };

            key_at(size_t i) -> K { -> this.keys[i]; };
        };

        // ====================================================================
        // StrHashMap<V>: string-keyed hash map. Keys are copied; the map owns them.
        // ====================================================================

        BaseSTD_COMMON_BUFFER_Traits
        object StrHashMap<V>
        {
            byte** keys;
            V*     vals;
            byte*  state;
            size_t n,
                   used,
                   cap;

            __init() -> this
            {
                this.keys  = (byte**)STDLIB_GVP;
                this.vals  = (V*)STDLIB_GVP;
                this.state = (byte*)STDLIB_GVP;
                this.n     = 0;
                this.used  = 0;
                this.cap   = 0;
                -> this;
            };

            _free_keys() -> void
            {
                size_t i;
                while (i < this.cap)
                {
                    if (this.state[i] == (byte)1 | this.state[i] == (byte)2)
                    {
                        ffree(this.keys[i]);
                    };
                    i++;
                };
                ->;
            };

            __exit() -> void
            {
                if (this.state != (byte*)STDLIB_GVP)
                {
                    this._free_keys();
                    ffree((byte*)this.keys);
                    ffree((byte*)this.vals);
                    ffree(this.state);
                    this.state = (byte*)STDLIB_GVP;
                };
                ->;
            };

            __expr() -> StrHashMap<V>*
            {
                -> this;
            };

            len() -> size_t { -> this.n; };

            is_empty() -> bool { -> this.n == 0; };

            _find(byte* key) -> i64
            {
                if (this.cap == 0) { -> (i64)-1; };
                size_t mask = this.cap - 1;
                size_t i = (size_t)(str_hash(key) `& (u64)mask);
                size_t probes;
                while (probes < this.cap)
                {
                    if (this.state[i] == (byte)0) { -> (i64)-1; };
                    if (this.state[i] == (byte)1 & str_eq(this.keys[i], key)) { -> (i64)i; };
                    i = (i + 1) `& mask;
                    probes++;
                };
                -> (i64)-1;
            };

            _rehash(size_t ncap) -> bool
            {
                byte** ok = this.keys,
                       nk = (byte**)fmalloc(ncap * 8);
                V*     ov = this.vals,
                       nv = (V*)fmalloc(ncap * (sizeof(V) / 8));
                byte*  os = this.state,
                       ns = (byte*)fmalloc(ncap);
                size_t oc = this.cap,
                       i, j, s,
                       mask;

                if (nk == (byte**)STDLIB_GVP | nv == (V*)STDLIB_GVP | ns == (byte*)STDLIB_GVP) { -> false; };
                
                while (i < ncap) { ns[i] = (byte)0; i++; };
                
                this
                {
                    .keys  = nk;
                    .vals  = nv;
                    .state = ns;
                    .cap   = ncap;
                    .n     = 0;
                    .used  = 0;
                };
                mask = ncap - 1;
                
                while (j < oc)
                {
                    if (os[j] == (byte)1)
                    {
                        // The key string moves to the new table
                        s = (size_t)(str_hash(ok[j]) `& (u64)mask);
                        while (this.state[s] != (byte)0) { s = (s + 1) `& mask; };
                        this.state[s] = (byte)1;
                        this.keys[s]  = ok[j];
                        this.vals[s]  = ov[j];
                        this.n++;
                        this.used++;
                    }
                    elif (os[j] == (byte)2)
                    {
                        ffree(ok[j]);
                    };
                    j++;
                };
                if (os != (byte*)STDLIB_GVP)
                {
                    ffree((byte*)ok);
                    ffree((byte*)ov);
                    ffree(os);
                };
                -> true;
            };

            put(byte* key, V value) -> bool
            {
                i64 f = this._find(key);
                if (f >= (i64)0)
                {
                    this.vals[(size_t)f] = value;
                    -> true;
                };
                if (this.cap == 0)
                {
                    if (!this._rehash(16)) { -> false; };
                }
                elif ((this.used + 1) * 10 > this.cap * 7)
                {
                    size_t target = this.cap;
                    if ((this.n + 1) * 10 > this.cap * 35 / 10) { target = this.cap * 2; };
                    if (!this._rehash(target)) { -> false; };
                };
                size_t mask = this.cap - 1;
                size_t i = (size_t)(str_hash(key) `& (u64)mask);
                while (this.state[i] == (byte)1) { i = (i + 1) `& mask; };
                if (this.state[i] == (byte)0) { this.used++; }
                else { ffree(this.keys[i]); };
                this.state[i] = (byte)1;
                this.keys[i]  = str_dup(key);
                this.vals[i]  = value;
                this.n++;
                -> true;
            };

            get(byte* key, V* out) -> bool
            {
                i64 f = this._find(key);
                if (f < (i64)0) { -> false; };
                *out = this.vals[(size_t)f];
                -> true;
            };

            get_or(byte* key, V fallback) -> V
            {
                i64 f = this._find(key);
                if (f < (i64)0) { -> fallback; };
                -> this.vals[(size_t)f];
            };

            find(byte* key) -> V*
            {
                i64 f = this._find(key);
                if (f < (i64)0) { -> (V*)STDLIB_GVP; };
                -> @this.vals[(size_t)f];
            };

            contains(byte* key) -> bool
            {
                -> this._find(key) >= (i64)0;
            };

            remove(byte* key) -> bool
            {
                i64 f = this._find(key);
                if (f < (i64)0) { -> false; };
                this.state[(size_t)f] = (byte)2;
                this.n--;
                -> true;
            };

            clear() -> void
            {
                this._free_keys();
                size_t i;
                while (i < this.cap) { this.state[i] = (byte)0; i++; };
                this.n    = 0;
                this.used = 0;
                ->;
            };

            slots() -> size_t { -> this.cap; };

            slot_used(size_t i) -> bool
            {
                -> i < this.cap & this.state[i] == (byte)1;
            };

            key_at(size_t i) -> byte* { -> this.keys[i]; };

            val_at(size_t i) -> V { -> this.vals[i]; };
        };
    };
};

#endif;
