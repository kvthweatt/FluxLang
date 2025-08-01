if (!def(FLUX_STANDARD_EXCEPTIONS))
{
    global import "exception.fx";
};

using standard::exceptions;

namespace standard
{
    const namespace math
    {
        def abs(float x) -> float {
            return x < 0 ? -x : x;
        };

        def is_nan(float x) -> bool {
            return x != x;
        };
    };
};