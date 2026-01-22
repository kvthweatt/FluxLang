// Test file for preprocessor directives

// Define some macros
#def DEBUG_MODE 1
#def MAX_BUFFER_SIZE 1024
#def VERSION "1.0.0"

// Test #ifdef
#ifdef DEBUG_MODE
def debug_print(byte* msg, int len) -> void
{
    print(msg, len);
    return void;
}
#else
def debug_print(byte* msg, int len) -> void
{
    // No-op in release mode
    return void;
}
#endif

// Test #ifndef
#ifndef RELEASE_MODE
global const int buffer_size = MAX_BUFFER_SIZE;
#else
global const int buffer_size = 512;
#endif

// Nested conditionals
#ifdef DEBUG_MODE
#ifdef VERBOSE_DEBUG
def log_level() -> int { return 2; }
#else
def log_level() -> int { return 1; }
#endif
#else
def log_level() -> int { return 0; }
#endif

// Macro substitution in code
def get_version() -> byte*
{
    byte[] version = VERSION;
    return @version;
}

def allocate_buffer() -> int
{
    return MAX_BUFFER_SIZE;
}

// Conditional main function example
#ifdef CUSTOM_MAIN
def main() -> int
{
    // Custom entry point
    return 42;
}
#else
def main() -> void
{
    // Standard entry point
    debug_print(@"Starting application...\n", 25);
    exit();
}
#endif