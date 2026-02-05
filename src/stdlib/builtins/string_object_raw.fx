#ifndef FLUX_STANDARD_IO
#import "redio.fx";
#endif;

#ifndef FLUX_STANDARD_STRINGS
#def FLUX_STANDARD_STRINGS 1;
#endif

#ifdef FLUX_STANDARD_STRINGS

namespace standard
{
    namespace strings
    {
        object string
        {
            noopstr value;
            int length;

            // ===== PROTOTYPES =====
            def val() -> byte*,
                len() -> int,
                set(byte*) -> bool,
                clear() -> void,
                isempty() -> bool,
                
                // Comparison
                equals(byte*) -> bool,
                compare(byte*) -> int,
                icompare(byte*) -> int,
                
                // Search
                contains(byte*) -> bool,
                startswith(byte*) -> bool,
                endswith(byte*) -> bool,
                indexof(byte*) -> int,
                lastindexof(byte*) -> int,
                indexof_char(char) -> int,
                lastindexof_char(char) -> int,
                count_occurrences(byte*) -> int,
                
                // Character access
                charat(int) -> char,
                setat(int, char) -> bool,
                
                // Substring & manipulation
                substring(int, int) -> byte*,
                left(int) -> byte*,
                right(int) -> byte*,
                
                // Concatenation
                concat(byte*) -> byte*,
                append(byte*) -> bool,
                prepend(byte*) -> bool,
                
                // Modification
                replace(byte*, byte*) -> byte*,
                replace_all(byte*, byte*) -> byte*,
                replace_char(char, char) -> bool,
                insert(int, byte*) -> bool,
                remove(int, int) -> bool,
                
                // Case conversion
                toupper() -> bool,
                tolower() -> bool,
                totitle() -> bool,
                
                // Trimming
                trim() -> bool,
                trimstart() -> bool,
                trimend() -> bool,
                trim_char(char) -> bool,
                
                // Splitting & joining
                split(char) -> byte**,
                split_lines() -> byte**,
                split_words() -> byte**,
                
                // Validation
                isalpha() -> bool,
                isdigit() -> bool,
                isalnum() -> bool,
                isupper() -> bool,
                islower() -> bool,
                
                // Conversion
                toint() -> int,
                toi32() -> i32,
                toi64() -> i64,
                tou32() -> u32,
                tou64() -> u64,
                fromint(int) -> bool,
                
                // Line operations
                count_lines() -> int,
                get_line(int) -> byte*,
                count_words() -> int,
                
                // Other
                reverse() -> bool,
                copy() -> byte*,
                hash() -> int,
                printval() -> void,
                println() -> void;

            def __init(byte* x) -> this
            {
                this.value = x;
                return this;
            };

            def __exit() -> void
            {
                return;
            };

            def val() -> byte*
            {
                return this.value;
            };

            def len() -> int
            {
                return strlen(this.value);
            };

            def set(byte* s) -> bool
            {
                try
                {
                    this.value = s;
                    return true;
                }
                catch()
                {
                    return false;
                };
                return false;
            };

            def equals(byte* s) -> bool
            {
                return strcmp(s, this.value) == 0;
            };

            def printval() -> void { print(this.value); };
        };
    };
};

using standard::strings;

#endif;