namespace standard
{
	namespace types
	{
		unsigned data{4} as nybble;
        unsigned data{8} as byte;
        byte[] as noopstr;
        unsigned data{16} as u16;
        unsigned data{32} as u32;
        unsigned data{64} as u64;
        signed data{8}  as i8;
        signed data{16} as i16;
        signed data{32} as i32;
        signed data{64} as i64;
        byte* as byte_ptr;
        i32* as i32_ptr;
        i64* as i64_ptr;
        void* as void_ptr;
        noopstr* as noopstr_ptr;
        i64* as intptr;
        u64* as uintptr;
        i64 as ssize_t;
        u64 as size_t;
        i16 as wchar;
        u64 as double;  
        unsigned data{16::1} as be16;
        unsigned data{32::1} as be32;
        unsigned data{64::1} as be64;
        unsigned data{16::0} as le16;
        unsigned data{32::0} as le32;
        unsigned data{64::0} as le64;
        def bswap16(u16 value) -> u16
        {
            return (i16)((value & 0xFF) << 8) | (i16)((value >> 8) & 0xFF);
        };
        def bswap32(u32 value) -> u32
        {
            return ((value & 0xFF) << 24) |
                   ((value & 0xFF00) << 8) |
                   ((value >> 8) & 0xFF00) |
                   ((value >> 24) & 0xFF);
        };
        def bswap64(u64 value) -> u64
        {
            return ((value & 0xFF) << 56) |
                   ((value & 0xFF00) << 40) |
                   ((value & 0xFF0000) << 24) |
                   ((value & 0xFF000000) << 8) |
                   ((value >> 8) & 0xFF000000) |
                   ((value >> 24) & 0xFF0000) |
                   ((value >> 40) & 0xFF00) |
                   ((value >> 56) & 0xFF);
        };
        def ntoh16(be16 net_value) -> le16
        {
            return (le16)bswap16((u16)net_value);
        };
        def ntoh32(be32 net_value) -> le32
        {
            return (le32)bswap32((u32)net_value);
        };
        def hton16(le16 host_value) -> be16
        {
            return (be16)bswap16((u16)host_value);
        };
        def hton32(le32 host_value) -> be32
        {
            return (be32)bswap32((u32)host_value);
        };
        def bit_test(u32 value, u32 bit) -> bool
        {
            return (value & (1 << bit)) != 0;
        };
        def align_up(u64 value, u64 alignment) -> u64
        {
            return (value + alignment - 1) & (alignment - 1);
        };
        def align_down(u64 value, u64 alignment) -> u64
        {
            return value & (alignment - 1);
        };
        def is_aligned(u64 value, u64 alignment) -> bool
        {
            return (value & (alignment - 1)) == 0;
        };
	};
};
using standard::types;
extern
{
    def !!malloc(size_t size) -> void*;
    def !!memcpy(void* dst, void* src, size_t n) -> void*;
    def !!free(void* ptr) -> void;
    def !!calloc(size_t num, size_t size) -> void*;
    def !!realloc(void* ptr, size_t size) -> void*;
    def !!memcpy(void* dest, void* src, size_t n) -> void*;
    def !!memmove(void* dest, void* src, size_t n) -> void*;
    def !!memset(void* ptr, int value, size_t n) -> void*;
    def !!memcmp(void* ptr1, void* ptr2, size_t n) -> int;
    def !!strlen(const char* str) -> size_t;
    def !!strcpy(char* dest, const char* src) -> char*;
    def !!strncpy(char* dest, const char* src, size_t n) -> char*;
    def !!strcat(char* dest, const char* src) -> char*;
    def !!strncat(char* dest, const char* src, size_t n) -> char*;
    def !!strcmp(const char* s1, const char* s2) -> int;
    def !!strncmp(const char* s1, const char* s2, size_t n) -> int;
    def !!strchr(const char* str, int ch) -> char*;
    def !!strstr(const char* haystack, const char* needle) -> char*;
    def !!abort() -> void;
    def !!exit(int status) -> void;
    def !!atexit(void* null) -> int;
};
extern
{
    def !!
        strcmp(byte* x, byte* y) -> int,
        printf(byte* x, byte* y) -> void,
        strncpy(byte* dest, byte* src, size_t n) -> byte*,
        strcat(byte* dest, byte* src) -> byte*,
        strncat(byte* dest, byte* src, size_t n) -> byte*,
        strncmp(byte* s1, byte* s2, size_t n) -> int,
        strchr(byte* str, int ch) -> byte*,
        strstr(byte* haystack, byte* needle) -> byte*;
};
def strlen(byte* ps) -> int
{
    int c = 0;
    while (true)
    {
        byte* ch = ps++;
        if (*ch == 0)
        {
            break;
        };
        c++;
    };
    return c;
};
def strcpy(noopstr dest, noopstr src) -> noopstr
{
    size_t i = 0;
    while (src[i] != 0)
    {
        dest[i] = src[i];
        i++;
    };
    dest[i] = (byte)0;
    return dest;
};
def i32str(i32 value, byte* buffer) -> i32
{
    if (value == 0)
    {
        buffer[0] = (byte)48; 
        buffer[1] = (byte)0;  
        return 1;
    };
    i32 is_negative = 0;
    if (value < 0)
    {
        is_negative = 1;
        value = -value;
    };
    i32 pos = 0;
    byte[32] temp;
    while (value > 0)
    {
        temp[pos] = (byte)((value % 10) + 48); 
        value = value / 10;
        pos++;
    };
    i32 write_pos = 0;
    if (is_negative == 1)
    {
        buffer[0] = (byte)45; 
        write_pos = 1;
    };
    i32 i = pos - 1;
    while (i >= 0)
    {
        buffer[write_pos] = temp[i];
        write_pos++;
        i--;
    };
    buffer[write_pos] = (byte)0; 
    return write_pos;
};
def i64str(i64 value, byte* buffer) -> i64
{
    if (value == (i64)0)
    {
        buffer[0] = (byte)48; 
        buffer[1] = (byte)0;  
        return 1;
    };
    i64 is_negative = (i64)0;
    if (value < (i64)0)
    {
        is_negative = (i64)1;
        value = -value;
    };
    i64 pos = (i64)0;
    byte[32] temp;
    while (value > (i64)0)
    {
        temp[pos] = (byte)((value % (i64)10) + (i64)48); 
        value = value / (i64)10;
        pos++;
    };
    i64 write_pos = 0;
    if (is_negative == (i64)1)
    {
        buffer[0] = (byte)45; 
        write_pos = (i64)1;
    };
    i64 i = pos - (i64)1;
    while (i >= (i64)0)
    {
        buffer[write_pos] = temp[i];
        write_pos++;
        i--;
    };
    buffer[write_pos] = (byte)0; 
    return write_pos;
};
def u32str(u32 value, byte* buffer) -> u32
{
    if (value == (u32)0)
    {
        buffer[0] = (byte)48; 
        buffer[1] = (byte)0;  
        return (u32)1;
    };
    u32 pos = (u32)0;
    byte[32] temp;
    while (value > (u32)0)
    {
        temp[pos] = (byte)((value % (u32)10) + (u32)48); 
        value = value / (u32)10;
        pos++;
    };
    u32 write_pos = (u32)0;
    u32 i = pos - (u32)1;
    while (i >= (u32)0)
    {
        buffer[write_pos] = temp[i];
        write_pos++;
        i--;
    };
    buffer[write_pos] = (byte)0; 
    return write_pos;
};
def u64str(u64 value, byte* buffer) -> u64
{
    if (value == (u64)0)
    {
        buffer[0] = (byte)48; 
        buffer[1] = (byte)0;  
        return (u64)1;
    };
    u64 pos = (u64)0;
    byte[32] temp;
    while (value != (u64)0)
    {
        temp[pos] = (byte)((value % (u64)10) + (u64)48); 
        value = value / (u64)10;
        pos++;
    };
    u64 write_pos = (u64)0;
    u64 remaining = pos;  
    while (remaining != (u64)0)
    {
        remaining--;  
        buffer[write_pos] = temp[remaining];
        write_pos++;
    };
    buffer[write_pos] = (byte)0; 
    return write_pos;
};
def str2i32(byte* str) -> int
{
    int result = 0;
    int sign = 1;
    int i = 0;
    while (str[i] == 32 | str[i] == 9 | str[i] == 10 | str[i] == 13)
    {
        i++;
    };
    if (str[i] == 45)  
    {
        sign = -1;
        i++;
    }
    elif (str[i] == 43)  
    {
        i++;
    };
    while (str[i] != 0)
    {
        byte c = str[i];
        if (c >= 48 & c <= 57)
        {
            int digit = (int)(c - 48);
            result = result * 10 + digit;
        }
        else
        {
            break;
        };
        i++;
    };
    return result * sign;
};
def str2u32(byte* str) -> uint
{
    uint result = (uint)0;
    int i = 0;
    while (str[i] == (byte)32 | str[i] == (byte)9 | str[i] == (byte)10 | str[i] == (byte)13)
    {
        i++;
    };
    if (str[i] == (byte)45)  
    {
        return (uint)0;  
    }
    elif (str[i] == (byte)43)  
    {
        i++;
    };
    while (str[i] != (byte)0)
    {
        byte c = str[i];
        if (c >= (byte)48 & c <= (byte)57)
        {
            uint digit = (uint)(c - (byte)48);
            result = result * (uint)10 + digit;
        }
        else
        {
            break;
        };
        i++;
    };
    return result;
};
def str2i64(byte* str) -> i64
{
    i64 result = (i64)0;
    i64 sign = (i64)1;
    int i = 0;
    while (str[i] == (byte)32 | str[i] == (byte)9 | str[i] == (byte)10 | str[i] == (byte)13)
    {
        i++;
    };
    if (str[i] == (byte)45)  
    {
        sign = (i64)-1;
        i++;
    }
    elif (str[i] == (byte)43)  
    {
        i++;
    };
    while (str[i] != (byte)0)
    {
        byte c = str[i];
        if (c >= (byte)48 & c <= (byte)57)
        {
            i64 digit = (i64)(c - (byte)48);
            result = result * (i64)10 + digit;
        }
        else
        {
            break;
        };
        i++;
    };
    return result * sign;
};
def str2u64(byte* str) -> u64
{
    u64 result = (u64)0;
    int i = 0;
    while (str[i] == (byte)32 | str[i] == (byte)9 | str[i] == (byte)10 | str[i] == (byte)13)
    {
        i++;
    };
    if (str[i] == (byte)45)  
    {
        return (u64)0;  
    }
    elif (str[i] == (byte)43)  
    {
        i++;
    };
    while (str[i] != (byte)0)
    {
        byte c = str[i];
        if (c >= (byte)48 & c <= (byte)57)
        {
            u64 digit = (u64)(c - (byte)48);
            result = result * (u64)10 + digit;
        }
        else
        {
            break;
        };
        i++;
    };
    return result;
};
def float2str(float value, byte* buffer, i32 precision) -> i32
{
    i32 write_pos = 0;
    if (value < 0.0)
    {
        buffer[0] = (byte)45; 
        write_pos = 1;
        value = -value;
    };
    if (value == 0.0)
    {
        buffer[write_pos] = (byte)48; 
        buffer[write_pos + 1] = (byte)46; 
        i32 i = 0;
        while (i < precision)
        {
            buffer[write_pos + 2 + i] = (byte)48; 
            i++;
        };
        buffer[write_pos + 2 + precision] = (byte)0;
        return write_pos + 1 + precision;
    };
    i32 int_part = (i32)value;
    float fractional = value - (float)int_part;
    i32 frac_multiplier = 1;
    i32 j = 0;
    while (j < precision)
    {
        frac_multiplier = frac_multiplier * 10;
        j++;
    };
    float scaled_frac = fractional * (float)frac_multiplier;
    i32 frac_part = (i32)(scaled_frac + 0.5);
    if (frac_part >= frac_multiplier)
    {
        int_part = int_part + 1;
        frac_part = 0;
        if (int_part % 10 == 0 & precision > 0)
        {
        };
    };
    if (int_part == 0)
    {
        buffer[write_pos] = (byte)48; 
        write_pos = write_pos + 1;
    }
    else
    {
        byte[32] int_temp;
        i32 temp_pos = 0;
        i32 temp_int = int_part;
        while (temp_int > 0)
        {
            int_temp[temp_pos] = (byte)((temp_int % 10) + 48);
            temp_int = temp_int / 10;
            temp_pos++;
        };
        i32 k = temp_pos - 1;
        while (k >= 0)
        {
            buffer[write_pos] = int_temp[k];
            write_pos = write_pos + 1;
            k--;
        };
    };
    if (precision > 0)
    {
        buffer[write_pos] = (byte)46; 
        write_pos = write_pos + 1;
        if (frac_part == 0)
        {
            i32 m = 0;
            while (m < precision)
            {
                buffer[write_pos] = (byte)48; 
                write_pos = write_pos + 1;
                m++;
            };
        }
        else
        {
            byte[32] frac_temp;
            i32 frac_digits = 0;
            i32 temp_frac = frac_part;
            while (temp_frac > 0)
            {
                frac_temp[frac_digits] = (byte)((temp_frac % 10) + 48);
                temp_frac = temp_frac / 10;
                frac_digits++;
            };
            i32 leading_zeros = precision - frac_digits;
            i32 n = 0;
            while (n < leading_zeros)
            {
                buffer[write_pos] = (byte)48; 
                write_pos = write_pos + 1;
                n++;
            };
            i32 p = frac_digits - 1;
            while (p >= 0)
            {
                buffer[write_pos] = frac_temp[p];
                write_pos = write_pos + 1;
                p--;
            };
        };
    };
    buffer[write_pos] = (byte)0;
    return write_pos;
};
    def is_whitespace(char c) -> bool
    {
        return c == ' ' | c == '\t' | c == '\n' | c == '\r';
    };
    def is_digit(char c) -> bool
    {
        return c >= '0' & c <= '9';
    };
    def is_alpha(char c) -> bool
    {
        return (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z');
    };
    def is_alnum(char c) -> bool
    {
        return is_alpha(c) | is_digit(c);
    };
    def is_hex_digit(char c) -> bool
    {
        return is_digit(c) | (c >= 'a' & c <= 'f') | (c >= 'A' & c <= 'F');
    };
    def is_identifier_start(char c) -> bool
    {
        return is_alpha(c) | c == '_';
    };
    def is_identifier_char(char c) -> bool
    {
        return is_alnum(c) | c == '_';
    };
    def is_newline(char c) -> bool
    {
        return c == '\n' | c == '\r';
    };
    def to_lower(char c) -> char
    {
        if (c >= 'A' & c <= 'Z')
        {
            return c + 32;
        };
        return c;
    };
    def to_upper(char c) -> char
    {
        if (c >= 'a' & c <= 'z')
        {
            return c - 32;
        };
        return c;
    };
    def char_to_digit(char c) -> int
    {
        if (c >= '0' & c <= '9')
        {
            return c - '0';
        };
        return -1;
    };
    def hex_to_int(char c) -> int
    {
        if (c >= '0' & c <= '9')
        {
            return c - '0';
        };
        if (c >= 'a' & c <= 'f')
        {
            return 10 + (c - 'a');
        };
        if (c >= 'A' & c <= 'F')
        {
            return 10 + (c - 'A');
        };
        return -1;
    };
    def find_char(byte* str, char ch, int start_pos) -> int
    {
        for (int i = start_pos; str[i] != 0; i = i + 1)
        {
            if (str[i] == ch)
            {
                return i;
            };
        };
        return -1;
    };
    def find_char_last(byte* str, char ch) -> int
    {
        int last = -1;
        for (int i = 0; str[i] != 0; i = i + 1)
        {
            if (str[i] == ch)
            {
                last = i;
            };
        };
        return last;
    };
    def find_any(byte* str, byte* char_set, int start_pos) -> int
    {
        for (int i = start_pos; str[i] != 0; i = i + 1)
        {
            for (int j = 0; char_set[j] != 0; j = j + 1)
            {
                if (str[i] == char_set[j])
                {
                    return i;
                };
            };
        };
        return -1;
    };
    def find_substring(byte* str, byte* substr, int start_pos) -> int
    {
        int str_len = 0;
        while (str[str_len] != 0) { str_len = str_len + 1; };
        int substr_len = 0;
        while (substr[substr_len] != 0) { substr_len = substr_len + 1; };
        if (substr_len == 0)
        {
            return start_pos;
        };
        for (int i = start_pos; i <= str_len - substr_len; i = i + 1)
        {
            bool match = true;
            for (int j = 0; j < substr_len; j = j + 1)
            {
                if (str[i + j] != substr[j])
                {
                    match = false;
                    break;
                };
            };
            if (match)
            {
                return i;
            };
        };
        return -1;
    };
    def skip_whitespace(byte* str, int pos) -> int
    {
        while (str[pos] != 0 & is_whitespace(str[pos]))
        {
            pos = pos + 1;
        };
        return pos;
    };
    def trim_end(byte* str) -> void
    {
        int len = 0;
        while (str[len] != 0) { len = len + 1; };
        while (len > 0 & is_whitespace(str[len - 1]))
        {
            len = len - 1;
        };
        str[len] = (byte)0;
        return;
    };
    def compare_n(byte* s1, byte* s2, int n) -> int
    {
        for (int i = 0; i < n; i = i + 1)
        {
            if (s1[i] != s2[i])
            {
                return s1[i] - s2[i];
            };
            if (s1[i] == 0)
            {
                return 0;
            };
        };
        return 0;
    };
    def compare_ignore_case(byte* s1, byte* s2) -> int
    {
        int i = 0;
        while (s1[i] != 0 & s2[i] != 0)
        {
            char c1 = to_lower(s1[i]);
            char c2 = to_lower(s2[i]);
            if (c1 != c2)
            {
                return c1 - c2;
            };
            i = i + 1;
        };
        return to_lower(s1[i]) - to_lower(s2[i]);
    };
    def starts_with(byte* str, byte* prefix) -> bool
    {
        int i = 0;
        while (prefix[i] != 0)
        {
            if (str[i] != prefix[i])
            {
                return false;
            };
            i = i + 1;
        };
        return true;
    };
    def ends_with(byte* str, byte* suffix) -> bool
    {
        int str_len = 0;
        while (str[str_len] != 0) { str_len = str_len + 1; };
        int suffix_len = 0;
        while (suffix[suffix_len] != 0) { suffix_len = suffix_len + 1; };
        if (suffix_len > str_len)
        {
            return false;
        };
        int offset = str_len - suffix_len;
        for (int i = 0; i < suffix_len; i = i + 1)
        {
            if (str[offset + i] != suffix[i])
            {
                return false;
            };
        };
        return true;
    };
    def copy_string(byte* src) -> byte*
    {
        int len = 0;
        while (src[len] != 0) { len = len + 1; };
        byte* dest = malloc((u64)len + 1);
        if (dest == 0)
        {
            return (byte*)0;
        };
        for (int i = 0; i <= len; i = i + 1)
        {
            dest[i] = src[i];
        };
        return dest;
    };
    def copy_n(byte* src, int n) -> byte*
    {
        byte* dest = malloc((u64)n + 1);
        if (dest == 0)
        {
            return (byte*)0;
        };
        for (int i = 0; i < n & src[i] != 0; i = i + 1)
        {
            dest[i] = src[i];
        };
        dest[n] = (byte)0;
        return dest;
    };
    def substring(byte* str, int start, int length) -> byte*
    {
        byte* result = malloc((u64)length + 1);
        if (result == 0)
        {
            return (byte*)0;
        };
        for (int i = 0; i < length & str[start + i] != 0; i = i + 1)
        {
            result[i] = (byte)str[start + i];
        };
        result[length] = (byte)0;
        return result;
    };
    def concat(byte* s1, byte* s2) -> byte*
    {
        int len1 = 0;
        while (s1[len1] != 0) { len1 = len1 + 1; };
        int len2 = 0;
        while (s2[len2] != 0) { len2 = len2 + 1; };
        byte* result = malloc((u64)len1 + len2 + 1);
        if (result == 0)
        {
            return (byte*)0;
        };
        for (int i = 0; i < len1; i = i + 1)
        {
            result[i] = s1[i];
        };
        for (int i = 0; i < len2; i = i + 1)
        {
            result[len1 + i] = s2[i];
        };
        result[len1 + len2] = (byte)0;
        return result;
    };
    def parse_int(byte* str, int start_pos, int* end_pos) -> int
    {
        int pos = skip_whitespace(str, start_pos);
        bool negative = false;
        if (str[pos] == '-')
        {
            negative = true;
            pos = pos + 1;
        }
        elif (str[pos] == '+')
        {
            pos = pos + 1;
        };
        int value = 0;
        while (is_digit(str[pos]))
        {
            value = value * 10 + (str[pos] - '0');
            pos = pos + 1;
        };
        *end_pos = pos;
        if (negative)
        {
            return -value;
        };
        return value;
    };
    def parse_hex(byte* str, int start_pos, int* end_pos) -> int
    {
        int pos = skip_whitespace(str, start_pos);
        if (str[pos] == '0' & (str[pos + 1] == 'x' | str[pos + 1] == 'X'))
        {
            pos = pos + 2;
        };
        int value = 0;
        while (is_hex_digit(str[pos]))
        {
            int digit = hex_to_int(str[pos]);
            value = value * 16 + digit;
            pos = pos + 1;
        };
        *end_pos = pos;
        return value;
    };
    def count_lines(byte* str) -> int
    {
        int count = 0;
        for (int i = 0; str[i] != 0; i = i + 1)
        {
            if (str[i] == '\n')
            {
                count = count + 1;
            };
        };
        if (count > 0 | str[0] != 0)
        {
            count = count + 1;
        };
        return count;
    };
    def get_line(byte* str, int line_num) -> byte*
    {
        int current_line = 0;
        int line_start = 0;
        for (int i = 0; str[i] != 0; i = i + 1)
        {
            if (current_line == line_num)
            {
                line_start = i;
                break;
            };
            if (str[i] == '\n')
            {
                current_line = current_line + 1;
            };
        };
        if (current_line != line_num)
        {
            return (byte*)0; 
        };
        int line_end = line_start;
        while (str[line_end] != 0 & str[line_end] != '\n')
        {
            line_end = line_end + 1;
        };
        int line_len = line_end - line_start;
        return substring(str, line_start, line_len);
    };
    def count_words(byte* str) -> int
    {
        int count = 0;
        bool in_word = false;
        for (int i = 0; str[i] != 0; i = i + 1)
        {
            if (is_whitespace(str[i]))
            {
                in_word = false;
            }
            elif (!in_word)
            {
                in_word = true;
                count = count + 1;
            };
        };
        return count;
    };
    def replace_first(byte* str, byte* find, byte* replace) -> byte*
    {
        int pos = find_substring(str, find, 0);
        if (pos == -1)
        {
            return copy_string(str);
        };
        int str_len = 0;
        while (str[str_len] != 0) { str_len = str_len + 1; };
        int find_len = 0;
        while (find[find_len] != 0) { find_len = find_len + 1; };
        int replace_len = 0;
        while (replace[replace_len] != 0) { replace_len = replace_len + 1; };
        int new_len = str_len - find_len + replace_len;
        byte* result = malloc((u64)new_len + 1);
        if (result == 0)
        {
            return (byte*)0;
        };
        for (int i = 0; i < pos; i = i + 1)
        {
            result[i] = str[i];
        };
        for (int i = 0; i < replace_len; i = i + 1)
        {
            result[pos + i] = replace[i];
        };
        for (int i = pos + find_len; i <= str_len; i = i + 1)
        {
            result[i - find_len + replace_len] = str[i];
        };
        return result;
    };
    def skip_until(byte* str, int pos, char ch) -> int
    {
        while (str[pos] != 0 & str[pos] != ch)
        {
            pos = pos + 1;
        };
        return pos;
    };
    def skip_while_digit(byte* str, int pos) -> int
    {
        while (str[pos] != 0 & is_digit(str[pos]))
        {
            pos = pos + 1;
        };
        return pos;
    };
    def skip_while_alnum(byte* str, int pos) -> int
    {
        while (str[pos] != 0 & is_alnum(str[pos]))
        {
            pos = pos + 1;
        };
        return pos;
    };
    def skip_while_identifier(byte* str, int pos) -> int
    {
        while (str[pos] != 0 & is_identifier_char(str[pos]))
        {
            pos = pos + 1;
        };
        return pos;
    };
    def match_at(byte* str, int pos, byte* pattern) -> bool
    {
        int i = 0;
        while (pattern[i] != 0)
        {
            if (str[pos + i] != pattern[i])
            {
                return false;
            };
            i = i + 1;
        };
        return true;
    };
object string
{
    noopstr value;
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
    def set(noopstr s) -> bool
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
};
extern
{
    def !!fopen(byte* filename, byte* mode) -> void*;
    def !!fclose(void* stream) -> int;
    def !!fread(void* ptr, int size, int count, void* stream) -> int;
    def !!fwrite(void* ptr, int size, int count, void* stream) -> int;
    def !!fseek(void* stream, int offset, int whence) -> int;
    def !!ftell(void* stream) -> int;
    def !!rewind(void* stream) -> void;
    def !!feof(void* stream) -> int;
    def !!ferror(void* stream) -> int;
};
namespace standard
{
    namespace io
    {
        namespace file
        {
            int SEEK_SET = 0;  
            int SEEK_CUR = 1;  
            int SEEK_END = 2;  
            def read_file(byte* filename, byte[] buffer, int buffer_size) -> int
            {
                void* file = fopen(filename, "rb\0");
                if (file == 0)
                {
                    return -1;
                };
                fseek(file, 0, 2);
                int file_size = ftell(file);
                rewind(file);
                int bytes_to_read = file_size;
                if (bytes_to_read > buffer_size)
                {
                    bytes_to_read = buffer_size;
                };
                int bytes_read = fread(buffer, 1, bytes_to_read, file);
                fclose(file);
                return bytes_read;
            };
            def write_file(byte* filename, byte[] xd, int data_size) -> int
            {
                void* file = fopen(filename, "wb\0");
                if (file == 0)
                {
                    return -1;
                };
                int bytes_written = fwrite(xd, 1, data_size, file);
                fclose(file);
                return bytes_written;
            };
            def append_file(byte* filename, byte[] xd, int data_size) -> int
            {
                void* file = fopen(filename, "ab\0");
                if (file == 0)
                {
                    return -1;
                };
                int bytes_written = fwrite(xd, 1, data_size, file);
                fclose(file);
                return bytes_written;
            };
            def get_file_size(byte* filename) -> int
            {
                void* file = fopen(filename, "rb\0");
                if (file == 0)
                {
                    return -1;
                };
                fseek(file, 0, 2);
                int size = ftell(file);
                fclose(file);
                return size;
            };
            def file_exists(byte* filename) -> bool
            {
                void* file = fopen(filename, "rb\0");
                if (file == 0)
                {
                    return 0;
                };
                fclose(file);
                return 1;
            };
        };
    };
};
using standard::io::file;
global const int OS_UNKNOWN = 0;
global const int OS_WINDOWS = 1;
global const int OS_LINUX = 2;
global const int OS_MACOS = 3;
namespace standard
{
    namespace system
    {
    };
};
using standard::system;
namespace standard
{
    namespace io
    {
        namespace console
        {
            def win_input(byte[] buffer, int max_len) -> int;
            def input(byte[] buffer, int max_len) -> int;
            def win_print(byte* msg, int x) -> void;
            def print(noopstr s, int len) -> void;
            def print(noopstr s) -> void;
            def print(byte s) -> void; 
            def reset_from_input() -> void;
            def win_input(byte[] buf, int max_len) -> int
            {
                i32 bytes_read = 0;
                i32* bytes_read_ptr = @bytes_read;
                i32 original_mode = 0;
                i32* mode_ptr = @original_mode;
                volatile asm
                {
                    movq $$-10, %rcx
                    subq $$32, %rsp
                    call GetStdHandle
                    addq $$32, %rsp
                    movq %rax, %r12
                    movq %rax, %rcx
                    movq $3, %rdx
                    subq $$32, %rsp
                    call GetConsoleMode
                    addq $$32, %rsp
                    movq %r12, %rcx
                    movq $$0x001F, %rdx
                    subq $$32, %rsp
                    call SetConsoleMode
                    addq $$32, %rsp
                    movq %r12, %rcx
                    movq $0, %rdx           
                    movl $1, %r8d           
                    movq $2, %r9            
                    subq $$40, %rsp
                    movq $$0, 32(%rsp)
                    call ReadFile
                    addq $$40, %rsp
                    movq %r12, %rcx
                    movl ($3), %edx
                    subq $$32, %rsp
                    call SetConsoleMode
                    addq $$32, %rsp
                    movl ($2), %eax
                } : : "r"(buf), "r"(max_len), "r"(bytes_read_ptr), "r"(mode_ptr)
                  : "rax","rcx","rdx","r8","r9","r10","r11","r12","memory";
                reset_from_input();
                return bytes_read - 2;
            };
            def input(byte[] buffer, int max_len) -> int
            {
                switch (1)
                {
                    case (1)
                    {
                        return win_input(buffer, max_len);
                    }
                    default
                    { return 0; };
                };
                return 0;
            };
            def win_print(byte* msg, int x) -> void
            {
                volatile asm
                {
                    movq $$-11, %rcx
                    subq $$32, %rsp
                    call GetStdHandle
                    addq $$32, %rsp
                    movq %rax, %rcx         
                    movq $0, %rdx           
                    movl $1, %r8d           
                    xorq %r9, %r9           
                    subq $$40, %rsp         
                    movq %r9, 32(%rsp)      
                    call WriteFile
                    addq $$40, %rsp
                } : : "r"(msg), "r"(x) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                return;
            };
            def reset_from_input() -> void
            {
                char bs = 8;
                win_print(@bs,1);
                win_print(@bs,1);
                return;
            };
    		def print(noopstr s, int len) -> void
    		{
                switch (1)
                {
                    case (1) 
                    {
                        win_print(@s, len);
                    }
                    default { return; }; 
                };
    			(void)s;
    			return;
    		};
            def print(noopstr s) -> void
            {
                int len = strlen(@s);
                switch (1)
                {
                    case (1) 
                    {
                        win_print(@s, len);
                    }
                    default { return; }; 
                };
                (void)s;
                return;
            };
            def printchar(noopstr x) -> void;
            def print(byte x) -> void;
            def print(i8 x) -> void;
            def print(i16 x) -> void;
            def print(int x) -> void;
            def print(i64 x) -> void;
            def print(u16 x) -> void;
            def print(uint x) -> void;
            def print(u64 x) -> void;
            def print(float x) -> void;
            def print(float x, int y) -> void;
            def print(byte s) -> void
            {
                byte[2] x = [s, 0];
                print(x);
                return;
            };
            def print(int x) -> void
            {
                byte[21] buf;
                i32str(x,buf);
                print(buf);
                return;
            };
            def print(uint x) -> void
            {
                byte[21] buf;
                u32str(x,buf);
                print(buf);
                return;
            };
            def print(i64 x) -> void
            {
                byte[21] buf;
                i64str(x,buf);
                print(buf);
                return;
            };
            def print(u64 x) -> void
            {
                byte[21] buf;
                u64str(x,buf);
                print(buf);
                return;
            };
            def print(float x) -> void
            {
                byte[256] buffer;
                float2str(x, @buffer, 5);
                print(buffer);
                return;
            };
            def print(float x, int y) -> void
            {
                byte[256] buffer;
                float2str(x, @buffer, y);
                print(buffer);
                return;
            };
            def print() -> void
            {
                switch (1)
                {
                    case (1) 
                    {
                        win_print("\n", 1);
                    }
                    default { return; }; 
                };
                return;
            };
        };      
        namespace file
        {
            def win_open(byte* path, u32 access, u32 share, u32 disposition, u32 attributes) -> i64;
            def win_read(i64 handle, byte* buffer, u32 bytes_to_read) -> i32;
            def win_write(i64 handle, byte* buffer, u32 bytes_to_write) -> i32;
            def win_close(i64 handle) -> i32;
            def win_open(byte* path, u32 access, u32 share, u32 disposition, u32 attributes) -> i64
            {
                i64 handle = -1;
                volatile asm
                {
                    movq $0, %rcx           
                    movl $1, %edx           
                    movl $2, %r8d           
                    xorq %r9, %r9           
                    subq $$56, %rsp
                    movl $3, %eax           
                    movl %eax, 32(%rsp)     
                    movl $4, %eax           
                    movl %eax, 40(%rsp)     
                    xorq %rax, %rax
                    movq %rax, 48(%rsp)     
                    call CreateFileA
                    movq %rax, $5           
                    addq $$56, %rsp
                } : : "r"(path), "r"(access), "r"(share), "r"(disposition), "r"(attributes), "m"(handle)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                return handle;
            };
            def win_read(i64 handle, byte* buffer, u32 bytes_to_read) -> i32
            {
                u32 bytes_read = 0;
                u32* bytes_read_ptr = @bytes_read;
                i32 success = 0;
                volatile asm
                {
                    movq $0, %rcx           
                    movq $1, %rdx           
                    movl $2, %r8d           
                    movq $3, %r9            
                    subq $$40, %rsp
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)     
                    call ReadFile
                    movl %eax, $4           
                    addq $$40, %rsp
                } : : "r"(handle), "r"(buffer), "r"(bytes_to_read), "r"(bytes_read_ptr), "m"(success)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                if (success == 0)
                {
                    return -1;
                };
                return (i32)bytes_read;
            };
            def win_write(i64 handle, byte* buffer, u32 bytes_to_write) -> i32
            {
                u32 bytes_written = 0;
                u32* bytes_written_ptr = @bytes_written;
                i32 success = 0;
                volatile asm
                {
                    movq $0, %rcx           
                    movq $1, %rdx           
                    movl $2, %r8d           
                    movq $3, %r9            
                    subq $$40, %rsp
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)     
                    call WriteFile
                    movl %eax, $4           
                    addq $$40, %rsp
                } : : "r"(handle), "r"(buffer), "r"(bytes_to_write), "r"(bytes_written_ptr), "m"(success)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                if (success == 0)
                {
                    return -1;
                };
                return (i32)bytes_written;
            };
            def win_close(i64 handle) -> i32
            {
                i32 result = 0;
                volatile asm
                {
                    movq $0, %rcx           
                    subq $$32, %rsp
                    call CloseHandle
                    movl %eax, $1           
                    addq $$32, %rsp
                } : : "r"(handle), "m"(result)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                return result;
            };
            def open_read(byte* path) -> i64
            {
                return win_open(path, (i32)0x80000000, (i32)0x00000001, (i32)3, (i32)0x80);
            };
            def open_write(byte* path) -> i64
            {
                return win_open(path, (i32)0x40000000, (i32)0, (i32)2, (i32)0x80);
            };
            def open_append(byte* path) -> i64
            {
                return win_open(path, (i32)0x40000000, (i32)0x00000001, (i32)4, (i32)0x80);
            };
            def open_read_write(byte* path) -> i64
            {
                return win_open(path, (i32)0xC0000000, (i32)0x00000001, (i32)4, (i32)0x80);
            };
        };
    };
};
using standard::io::console;
using standard::io::file;
extern
{
    def !!
        GetCommandLineW() -> wchar*,
        CommandLineToArgvW(wchar* x, int* y) -> wchar**, 
        LocalFree(void* x) -> void*,
        exit(int code) -> void,
        abort() -> void;
};
def !!main() -> int;
def !!main(int* argc, byte** argv) -> int;
def !!FRTStartup() -> int; 
def !!FRTStartup() -> int
{
    int return_code;
    switch (1)
    {
        case (1)
        {
            return_code = main();
        }
        default
        {
            return return_code;
        };
    };
    if (return_code != 0)
    {
    };
    return return_code;
};
extern
{
};
def main() -> int
{
    print("Hello World!\n\0");
    return 0;
};