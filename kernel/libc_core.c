#include <ctype.h>
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "platform.h"

int errno;

void* memcpy(void* dest, const void* src, size_t n) {
    size_t i;
    uint8_t* d = (uint8_t*) dest;
    const uint8_t* s = (const uint8_t*) src;
    for (i = 0; i < n; ++i) {
        d[i] = s[i];
    }
    return dest;
}

void* memmove(void* dest, const void* src, size_t n) {
    size_t i;
    uint8_t* d = (uint8_t*) dest;
    const uint8_t* s = (const uint8_t*) src;
    if (d < s) {
        for (i = 0; i < n; ++i) {
            d[i] = s[i];
        }
    } else if (d > s) {
        for (i = n; i > 0; --i) {
            d[i - 1] = s[i - 1];
        }
    }
    return dest;
}

void* memset(void* dest, int c, size_t n) {
    size_t i;
    uint8_t* d = (uint8_t*) dest;
    for (i = 0; i < n; ++i) {
        d[i] = (uint8_t) c;
    }
    return dest;
}

int memcmp(const void* left, const void* right, size_t n) {
    size_t i;
    const uint8_t* l = (const uint8_t*) left;
    const uint8_t* r = (const uint8_t*) right;
    for (i = 0; i < n; ++i) {
        if (l[i] != r[i]) {
            return (int) l[i] - (int) r[i];
        }
    }
    return 0;
}

void* memchr(const void* src, int c, size_t n) {
    size_t i;
    const uint8_t* s = (const uint8_t*) src;
    for (i = 0; i < n; ++i) {
        if (s[i] == (uint8_t) c) {
            return (void*) (s + i);
        }
    }
    return 0;
}

size_t strlen(const char* s) {
    size_t len = 0;
    while (s[len] != '\0') {
        ++len;
    }
    return len;
}

size_t strnlen(const char* s, size_t max_len) {
    size_t len = 0;
    while (len < max_len && s[len] != '\0') {
        ++len;
    }
    return len;
}

int strcmp(const char* left, const char* right) {
    while (*left != '\0' && *left == *right) {
        ++left;
        ++right;
    }
    return (unsigned char) *left - (unsigned char) *right;
}

int strncmp(const char* left, const char* right, size_t n) {
    size_t i;
    for (i = 0; i < n; ++i) {
        if (left[i] != right[i] || left[i] == '\0' || right[i] == '\0') {
            return (unsigned char) left[i] - (unsigned char) right[i];
        }
    }
    return 0;
}

int strcasecmp(const char* left, const char* right) {
    while (*left != '\0' && *right != '\0') {
        int a = tolower((unsigned char) *left);
        int b = tolower((unsigned char) *right);
        if (a != b) {
            return a - b;
        }
        ++left;
        ++right;
    }
    return tolower((unsigned char) *left) - tolower((unsigned char) *right);
}

int strncasecmp(const char* left, const char* right, size_t n) {
    size_t i;
    for (i = 0; i < n; ++i) {
        int a = tolower((unsigned char) left[i]);
        int b = tolower((unsigned char) right[i]);
        if (a != b || left[i] == '\0' || right[i] == '\0') {
            return a - b;
        }
    }
    return 0;
}

char* strcpy(char* dest, const char* src) {
    char* out = dest;
    while ((*out++ = *src++) != '\0') {
    }
    return dest;
}

char* strncpy(char* dest, const char* src, size_t n) {
    size_t i;
    for (i = 0; i < n && src[i] != '\0'; ++i) {
        dest[i] = src[i];
    }
    for (; i < n; ++i) {
        dest[i] = '\0';
    }
    return dest;
}

char* strcat(char* dest, const char* src) {
    strcpy(dest + strlen(dest), src);
    return dest;
}

char* strdup(const char* s) {
    size_t len = strlen(s) + 1;
    char* dup = malloc(len);
    if (dup != 0) {
        memcpy(dup, s, len);
    }
    return dup;
}

char* strchr(const char* s, int c) {
    while (*s != '\0') {
        if (*s == (char) c) {
            return (char*) s;
        }
        ++s;
    }
    return c == 0 ? (char*) s : 0;
}

char* strrchr(const char* s, int c) {
    char* found = 0;
    while (*s != '\0') {
        if (*s == (char) c) {
            found = (char*) s;
        }
        ++s;
    }
    if (c == 0) {
        return (char*) s;
    }
    return found;
}

char* strstr(const char* haystack, const char* needle) {
    size_t needle_len = strlen(needle);
    if (needle_len == 0) {
        return (char*) haystack;
    }
    while (*haystack != '\0') {
        if (strncmp(haystack, needle, needle_len) == 0) {
            return (char*) haystack;
        }
        ++haystack;
    }
    return 0;
}

char* strerror(int errnum) {
    switch (errnum) {
    case ENOENT: return "not found";
    case ENOMEM: return "out of memory";
    case EINVAL: return "invalid argument";
    case EISDIR: return "is a directory";
    default: return "error";
    }
}

int isspace(int c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

int isdigit(int c) {
    return c >= '0' && c <= '9';
}

int isxdigit(int c) {
    return isdigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

int isalpha(int c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

int isalnum(int c) {
    return isalpha(c) || isdigit(c);
}

int isprint(int c) {
    return c >= 32 && c <= 126;
}

int toupper(int c) {
    return (c >= 'a' && c <= 'z') ? (c - 32) : c;
}

int tolower(int c) {
    return (c >= 'A' && c <= 'Z') ? (c + 32) : c;
}

void* malloc(size_t size) {
    return heap_malloc(size);
}

void* calloc(size_t count, size_t size) {
    return heap_calloc(count, size);
}

void* realloc(void* ptr, size_t size) {
    return heap_realloc(ptr, size);
}

void free(void* ptr) {
    heap_free(ptr);
}

int abs(int value) {
    return value < 0 ? -value : value;
}

static int digit_value(int c) {
    if (isdigit(c)) {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    return -1;
}

unsigned long strtoul(const char* s, char** endptr, int base) {
    unsigned long value = 0;
    int sign = 1;

    while (isspace((unsigned char) *s)) {
        ++s;
    }
    if (*s == '+') {
        ++s;
    } else if (*s == '-') {
        sign = -1;
        ++s;
    }

    if (base == 0) {
        if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
            base = 16;
            s += 2;
        } else if (s[0] == '0') {
            base = 8;
            ++s;
        } else {
            base = 10;
        }
    } else if (base == 16 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        s += 2;
    }

    while (*s != '\0') {
        int digit = digit_value((unsigned char) *s);
        if (digit < 0 || digit >= base) {
            break;
        }
        value = value * (unsigned long) base + (unsigned long) digit;
        ++s;
    }

    if (endptr != 0) {
        *endptr = (char*) s;
    }
    return sign < 0 ? (unsigned long) (-(long) value) : value;
}

long strtol(const char* s, char** endptr, int base) {
    return (long) strtoul(s, endptr, base);
}

int atoi(const char* s) {
    return (int) strtol(s, 0, 10);
}

double atof(const char* s) {
    double value = 0.0;
    double scale = 1.0;
    int sign = 1;

    while (isspace((unsigned char) *s)) {
        ++s;
    }
    if (*s == '+') {
        ++s;
    } else if (*s == '-') {
        sign = -1;
        ++s;
    }

    while (isdigit((unsigned char) *s)) {
        value = value * 10.0 + (double) (*s - '0');
        ++s;
    }

    if (*s == '.') {
        ++s;
        while (isdigit((unsigned char) *s)) {
            value = value * 10.0 + (double) (*s - '0');
            scale *= 10.0;
            ++s;
        }
    }

    return (sign < 0 ? -value : value) / scale;
}

char* getenv(const char* name) {
    (void) name;
    return 0;
}

int system(const char* command) {
    (void) command;
    return -1;
}

void exit(int status) {
    platform_panic("exit(%d)", status);
}

void abort(void) {
    platform_panic("abort()");
}
