// fileio.flx - File I/O library for Flux
// Uses Windows API with AT&T style inline assembly

import "redtypes.fx";
using standard::types;

// Convenience constants
def STDIN_FILENO  0;
def STDOUT_FILENO 1;
def STDERR_FILENO 2;

// Seek constants
def SEEK_SET 0;
def SEEK_CUR 1;
def SEEK_END 2;

// File mode strings
def MODE_READ      "r";
def MODE_APPEND    "a";
def MODE_WRITE     "w";
def MODE_READWRITE "r+"; // haha rawr

def main() -> int
{
    return 0;
};