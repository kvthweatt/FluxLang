#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_MEMORY
#def FLUX_STANDARD_MEMORY 1;

extern
{
    // Memory allocation
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

#endif;