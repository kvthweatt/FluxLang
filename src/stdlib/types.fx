import "bigint.fx";

namespace standard
{
    // Made constant to prevent modification after import
    const namespace types
    {
        unsigned data{8:8} as(const) byte;  // const types cannot be changed, as in we cannot redefine `byte`

        unsigned data{16} as(const) u16;
        signed data{16}   as(const) i16;

        unsigned data{32} as(const) u32;
        signed data{32}   as(const) i32;

        unsigned data{64} as(const) u64;
        signed data{64}   as(const) i64;

        byte[] as(const) noopstr;
        object string
        {
            noopstr base;

            def __init() -> this
            {
                return this;
            };

            def __init(noopstr arg) -> this
            {
                this.base = arg;
                return this;
            };

            def __exit() -> void
            {
                return void;
            };

            def __value() -> noopstr
            {
                return this.base;
            };
        };

        if (def(BIG_INT))
        {
            local using standard::big_int;
        };

        const namespace pointers
        {
            contract notSame {
                assert(@a != @b, "Cannot assign unique_ptr to itself.");
            };

            contract canMove : notSame {
                assert(a.ptr != void, "Cannot move from empty unique_ptr.");
                assert(b.ptr == void, "Destination must be void.")
            };

            contract didMove {
                assert(a.ptr == void, "Move must invalidate source.");
                assert(b.ptr != void, "Destination must now own the resource.");
            };

            const object unique_ptr<T>
            {
                T* ptr;

                def __init(T* p) -> this
                {
                    this.ptr = p;
                    return this;
                };

                def __exit() -> void
                {
                    if (this.ptr == !void)
                    {
                        (void)this.ptr;
                    };
                };
            };

            const operator (unique_ptr<int> a, unique_ptr<int> b)[=] -> unique_ptr<int> : canMove
            {
                b.ptr = a.ptr;    // Transfer
                a.ptr = void;     // Invalidate source
                return b;
            } : didMove;
        };
    };
};