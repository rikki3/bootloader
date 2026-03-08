#ifndef KERNEL_LIBC_STDIO_H
#define KERNEL_LIBC_STDIO_H

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define EOF (-1)

typedef struct FILE {
    int kind;
    uint64_t pos;
    uint64_t length;
    const unsigned char* data;
    int writable;
    int error;
} FILE;

extern FILE* stdin;
extern FILE* stdout;
extern FILE* stderr;

int printf(const char* format, ...);
int fprintf(FILE* stream, const char* format, ...);
int vfprintf(FILE* stream, const char* format, va_list args);
int sprintf(char* buffer, const char* format, ...);
int snprintf(char* buffer, size_t size, const char* format, ...);
int vsnprintf(char* buffer, size_t size, const char* format, va_list args);
int sscanf(const char* buffer, const char* format, ...);

FILE* fopen(const char* path, const char* mode);
int fclose(FILE* stream);
size_t fread(void* ptr, size_t size, size_t count, FILE* stream);
size_t fwrite(const void* ptr, size_t size, size_t count, FILE* stream);
int fseek(FILE* stream, long offset, int whence);
long ftell(FILE* stream);
int fflush(FILE* stream);
int putchar(int c);
int puts(const char* s);
int fileno(FILE* stream);
int remove(const char* path);
int rename(const char* old_path, const char* new_path);

#endif
