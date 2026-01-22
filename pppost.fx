// Test file for preprocessor directives

// Define some macros

// Test #ifdef
def debug_print(byte* msg, int len) -> void
{
    print(msg, len);
    return void;
}

// Test #ifndef
global const int buffer_size = 1024;

// Nested conditionals
def log_level() -> int { return 1; }

// Macro substitution in code
def get_version() -> byte*
{
    byte[] version = "1.0.0";
    return @version;
}

def allocate_buffer() -> int
{
    return 1024;
}

// Conditional main function example
def main() -> void
{
    // Standard entry point
    debug_print(@"Starting application...\n", 25);
    exit();
}