#import "redio.fx", "redmemory.fx";

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
                count_spaces() -> int, // count_occurances(" \0")
                
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

            // ===== CONSTRUCTOR & DESTRUCTOR =====
            def __init(byte* x) -> this
            {
                this.value = x;
                this.length = (i32)strlen(x);
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
                    this.length = (i32)strlen(s); // assignment needs to auto coerce
                    return true;
                }
                catch()
                {
                    return false;
                };
                return false;
            };

                def clear() -> void
            {
                this.value[0] = (byte)0;
                this.length = 0;
            };

            def isempty() -> bool
            {
                return this.length == 0;
            };

            // ===== COMPARISON =====
            def equals(byte* s) -> bool
            {
                return strcmp(s, this.value) == 0;
            };

            def compare(byte* s) -> int
            {
                return strcmp(this.value, s);
            };

            def icompare(byte* s) -> int
            {
                // Case-insensitive compare
                return compare_ignore_case(this.value, s);
            };

            // ===== SEARCH =====
            def contains(byte* substr) -> bool
            {
                return strstr(this.value, substr) != 0;
            };

            def startswith(byte* prefix) -> bool
            {
                return starts_with(this.value, prefix);
            };

            def endswith(byte* suffix) -> bool
            {
                return ends_with(this.value, suffix);
            };
///
            def indexof(byte* substr) -> int
            {
                return find_substring(this.value, substr, 0);
            };

            def lastindexof(byte* substr) -> int
            {
                return find_last_substring(this.value, substr);
            };
///
            def indexof_char(char ch) -> int
            {
                return find_char(this.value, ch, 0);
            };
///
            def lastindexof_char(char ch) -> int
            {
                return find_last_char(this.value, ch);
            };

            def count_occurrences(byte* substr) -> int
            {
                return count_substring(this.value, substr);
            };
///

            // ===== CHARACTER ACCESS =====
            def charat(int index) -> char
            {
                if (index < 0 | index >= this.length)
                {
                    return (char)0;
                };
                return (char)this.value[index];
            };

            def setat(int index, char ch) -> bool
            {
                if (index < 0 | index >= this.length)
                {
                    return false;
                };
                this.value[index] = (byte)ch;
                return true;
            };

            // ===== SUBSTRING & MANIPULATION =====
            def substring(int start, int length) -> byte*
            {
                if (start < 0 | start >= this.length)
                {
                    return (byte*)0;
                };
                if (length < 0 | start + length > this.length)
                {
                    length = this.length - start;
                };
                return copy_n(this.value + start, length);
            };

            def left(int n) -> byte*
            {
                if (n < 0)
                {
                    return (byte*)0;
                };
                if (n > this.length)
                {
                    n = this.length;
                };
                return copy_n(this.value, n);
            };

            def right(int n) -> byte*
            {
                if (n < 0)
                {
                    return (byte*)0;
                };
                if (n > this.length)
                {
                    n = this.length;
                };
                return copy_n(this.value + (this.length - n), n);
            };

            // ===== CONCATENATION =====
            def concat(byte* s) -> byte*
            {
                return concat(this.value, s);
            };

            def append(byte* s) -> bool
            {
                try
                {
                    byte* newval = concat(this.value, s);
                    if (newval == 0)
                    {
                        return false;
                    };
                    this.value = newval;
                    this.length = (i32)strlen(newval);
                    return true;
                }
                catch()
                {
                    return false;
                };
                return false;
            };

            def prepend(byte* s) -> bool
            {
                try
                {
                    byte* newval = concat(s, this.value);
                    if (newval == 0)
                    {
                        return false;
                    };
                    this.value = newval;
                    this.length = (i32)strlen(newval);
                    return true;
                }
                catch()
                {
                    return false;
                };
                return false;
            };

            // ===== MODIFICATION =====
            def replace(byte* find, byte* replace) -> byte*
            {
                return replace_first(this.value, find, replace);
            };


            def replace_all(byte* find, byte* replace) -> byte*
            {
                // Replace all occurrences
                byte* result = copy_string(this.value);
                if (result == 0)
                {
                    return (byte*)0;
                };

                int find_len = strlen(find);
                if (find_len == 0)
                {
                    return result;
                };

                while (true)
                {
                    int pos = find_substring(result, find, 0);
                    if (pos == -1)
                    {
                        break;
                    };
                    
                    byte* temp = replace_first(result, find, replace);
                    free(result);
                    result = temp;
                    
                    if (result == 0)
                    {
                        return (byte*)0;
                    };
                };

                return result;
            };


            def replace_char(char oldch, char newch) -> bool
            {
                for (int i = 0; i < this.length; i = i + 1)
                {
                    if ((char)this.value[i] == oldch)
                    {
                        this.value[i] = (byte)newch;
                    };
                };
                return true;
            };

            def insert(int pos, byte* s) -> bool
            {
                if (pos < 0 | pos > this.length)
                {
                    return false;
                };

                byte* before = copy_n(this.value, pos);
                byte* after = copy_string(this.value + pos);
                
                if (before == 0 | after == 0)
                {
                    if (before != 0) { free(before); };
                    if (after != 0) { free(after); };
                    return false;
                };

                byte* temp = concat(before, s);
                free(before);
                
                if (temp == 0)
                {
                    free(after);
                    return false;
                };

                byte* result = concat(temp, after);
                free(temp);
                free(after);

                if (result == 0)
                {
                    return false;
                };

                this.value = result;
                this.length = (i32)strlen(result);
                return true;
            };

            def remove(int start, int length) -> bool
            {
                if (start < 0 | start >= this.length)
                {
                    return false;
                };
                if (length < 0)
                {
                    return false;
                };
                if (start + length > this.length)
                {
                    length = this.length - start;
                };

                byte* before = copy_n(this.value, start);
                byte* after = copy_string(this.value + start + length);

                if (before == 0 | after == 0)
                {
                    if (before != 0) { free(before); };
                    if (after != 0) { free(after); };
                    return false;
                };

                byte* result = concat(before, after);
                free(before);
                free(after);

                if (result == 0)
                {
                    return false;
                };

                this.value = result;
                this.length = (i32)strlen(result);
                return true;
            };

            // ===== CASE CONVERSION =====
            def toupper() -> bool
            {
                for (int i = 0; i < this.length; i = i + 1)
                {
                    this.value[i] = (byte)to_upper((char)this.value[i]);
                };
                return true;
            };

            def tolower() -> bool
            {
                for (int i = 0; i < this.length; i = i + 1)
                {
                    this.value[i] = (byte)to_lower((char)this.value[i]);
                };
                return true;
            };

            def totitle() -> bool
            {
                // Capitalize first letter of each word
                bool at_word_start = true;
                for (int i = 0; i < this.length; i = i + 1)
                {
                    char ch = (char)this.value[i];
                    if (is_whitespace(ch))
                    {
                        at_word_start = true;
                    }
                    elif (at_word_start)
                    {
                        this.value[i] = (byte)to_upper(ch);
                        at_word_start = false;
                    }
                    else
                    {
                        this.value[i] = (byte)to_lower(ch);
                    };
                };
                return true;
            };

            // ===== TRIMMING =====
            def trim() -> bool
            {
                int start = 0;
                while (start < this.length & is_whitespace((char)this.value[start]))
                {
                    start = start + 1;
                };

                int end = this.length - 1;
                while (end >= start & is_whitespace((char)this.value[end]))
                {
                    end = end - 1;
                };

                int newlen = end - start + 1;
                if (newlen <= 0)
                {
                    this.clear();
                    return true;
                };

                byte* result = copy_n(this.value + start, newlen);
                if (result == 0)
                {
                    return false;
                };

                this.value = result;
                this.length = newlen;
                return true;
            };

            def trimstart() -> bool
            {
                int start = 0;
                while (start < this.length & is_whitespace((char)this.value[start]))
                {
                    start = start + 1;
                };

                if (start == 0)
                {
                    return true;
                };

                byte* result = copy_string(this.value + start);
                if (result == 0)
                {
                    return false;
                };

                this.value = result;
                this.length = (i32)strlen(result);
                return true;
            };

            def trimend() -> bool
            {
                int end = this.length - 1;
                while (end >= 0 & is_whitespace((char)this.value[end]))
                {
                    end = end - 1;
                };

                if (end == this.length - 1)
                {
                    return true;
                };

                this.value[end + 1] = (byte)0;
                this.length = end + 1;
                return true;
            };

            def trim_char(char ch) -> bool
            {
                int start = 0;
                while (start < this.length & (char)this.value[start] == ch)
                {
                    start = start + 1;
                };

                int end = this.length - 1;
                while (end >= start & (char)this.value[end] == ch)
                {
                    end = end - 1;
                };

                int newlen = end - start + 1;
                if (newlen <= 0)
                {
                    this.clear();
                    return true;
                };

                byte* result = copy_n(this.value + start, newlen);
                if (result == 0)
                {
                    return false;
                };

                this.value = result;
                this.length = newlen;
                return true;
            };

            // ===== VALIDATION =====
            def isalpha() -> bool
            {
                if (this.length == 0)
                {
                    return false;
                };
                for (int i = 0; i < this.length; i = i + 1)
                {
                    if (!is_alpha((char)this.value[i]))
                    {
                        return false;
                    };
                };
                return true;
            };

            def isdigit() -> bool
            {
                if (this.length == 0)
                {
                    return false;
                };
                for (int i = 0; i < this.length; i = i + 1)
                {
                    if (!is_digit((char)this.value[i]))
                    {
                        return false;
                    };
                };
                return true;
            };

            def isalnum() -> bool
            {
                if (this.length == 0)
                {
                    return false;
                };
                for (int i = 0; i < this.length; i = i + 1)
                {
                    if (!is_alnum((char)this.value[i]))
                    {
                        return false;
                    };
                };
                return true;
            };
///
            def isupper() -> bool
            {
                if (this.length == 0)
                {
                    return false;
                };
                bool has_alpha = false;
                for (int i = 0; i < this.length; i = i + 1)
                {
                    char ch = (char)this.value[i];
                    if (is_alpha(ch))
                    {
                        has_alpha = true;
                        if (!is_upper(ch))
                        {
                            return false;
                        };
                    };
                };
                return has_alpha;
            };

            def islower() -> bool
            {
                if (this.length == 0)
                {
                    return false;
                };
                bool has_alpha = false;
                for (int i = 0; i < this.length; i = i + 1)
                {
                    char ch = (char)this.value[i];
                    if (is_alpha(ch))
                    {
                        has_alpha = true;
                        if (!is_lower(ch))
                        {
                            return false;
                        };
                    };
                };
                return has_alpha;
            };
///
            // ===== CONVERSION =====
            def toint() -> int
            {
                return str2i32(this.value);
            };

            def toi32() -> i32
            {
                return str2i32(this.value);
            };

            def toi64() -> i64
            {
                return str2i64(this.value);
            };

            def tou32() -> u32
            {
                return str2u32(this.value);
            };

            def tou64() -> u64
            {
                return str2u64(this.value);
            };

            def fromint(int value) -> bool
            {
                byte[32] buffer;
                i32str(value, buffer);
                return this.set(copy_string(buffer));
            };

            // ===== LINE OPERATIONS =====
            def count_lines() -> int
            {
                return count_lines(this.value);
            };

            def get_line(int line_num) -> byte*
            {
                return get_line(this.value, line_num);
            };

            def count_words() -> int
            {
                return count_words(this.value);
            };

            // ===== SPLITTING (Note: These return arrays that must be freed) =====
            def split(char delimiter) -> byte**
            {
                // Count delimiters to know array size
                int count = 1;
                for (int i = 0; i < this.length; i = i + 1)
                {
                    if ((char)this.value[i] == delimiter)
                    {
                        count = count + 1;
                    };
                };

                // Allocate array of string pointers
                byte** result = (byte**)malloc((u64)(count + 1) * 8); // +1 for null terminator
                if (result == 0)
                {
                    return (byte**)0;
                };

                int part_idx = 0;
                int start = 0;

                for (int i = 0; i <= this.length; i = i + 1)
                {
                    if (i == this.length | (char)this.value[i] == delimiter)
                    {
                        int part_len = i - start;
                        *result[part_idx] = copy_n(this.value + start, part_len);
                        part_idx = part_idx + 1;
                        start = i + 1;
                    };
                };

                *result[part_idx] = (byte*)0; // Null-terminate array
                return result;
            };

            def split_lines() -> byte**
            {
                return this.split('\n');
            };

            def split_words() -> byte**
            {
                return this.split(' ');
            };

            // ===== OTHER =====
            def reverse() -> bool
            {
                for (int i = 0; i < this.length / 2; i = i + 1)
                {
                    byte temp = this.value[i];
                    this.value[i] = this.value[this.length - 1 - i];
                    this.value[this.length - 1 - i] = temp;
                };
                return true;
            };

            def copy() -> byte*
            {
                return copy_string(this.value);
            };

            def hash() -> int
            {
                // Simple DJB2 hash
                int hash = 5381;
                for (int i = 0; i < this.length; i = i + 1)
                {
                    hash = ((hash << 5) + hash) + (int)this.value[i];
                };
                return hash;
            };

            def printval() -> void
            {
                print(this.value);
            };

            def println() -> void
            {
                print(this.value);
                print("\n\0");
            };

            def printval() -> void { print(this.value); };
        };
    };
};

using standard::strings;

#endif;

def main() -> int
{
    string s("Testing!\0");

    print(s.val());

    s.__exit();
	return 0;
};