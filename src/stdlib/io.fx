// Input/Output Operations

import "types.fx";

namespace standard
{
    // Made constant to prevent modification after import
    namespace io
    {
        namespace console {};
        namespace file {};
        namespace network {};
    };
};

// Comment out after upgrade to full specification
import "redio.fx";
using standard::io::console;
// Replace with this
// import "io.fx";
// using standard::io::console;