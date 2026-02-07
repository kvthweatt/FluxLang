#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_MEMORY
#def FLUX_STANDARD_MEMORY 1;

extern
{
    // Memory allocation
    def !!malloc(size_t size) -> void*,
          memcpy(void* dst, void* src, size_t n) -> void*,
          free(void* ptr) -> void,
          calloc(size_t num, size_t size) -> void*,
          realloc(void* ptr, size_t size) -> void*,
          memcpy(void* dest, void* src, size_t n) -> void*,
          memmove(void* dest, void* src, size_t n) -> void*,
          memset(void* ptr, int value, size_t n) -> void*,
          memcmp(void* ptr1, void* ptr2, size_t n) -> int,
          //strlen(const char* str) -> size_t,
          strcpy(char* dest, const char* src) -> char,
          strncpy(char* dest, const char* src, size_t n) -> char,
          strcat(char* dest, const char* src) -> char,
          strncat(char* dest, const char* src, size_t n) -> char,
          strcmp(const char* s1, const char* s2) -> int,
          strncmp(const char* s1, const char* s2, size_t n) -> int,
          strchr(const char* str, int ch) -> char,
          strstr(const char* haystack, const char* needle) -> char*,
          abort() -> void,
          exit(int status) -> void,
          atexit(void* null) -> int;
};

#endif;