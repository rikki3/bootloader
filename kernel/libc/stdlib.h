#ifndef KERNEL_LIBC_STDLIB_H
#define KERNEL_LIBC_STDLIB_H

#include <stddef.h>

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

void* malloc(size_t size);
void* calloc(size_t count, size_t size);
void* realloc(void* ptr, size_t size);
void free(void* ptr);

int atoi(const char* s);
double atof(const char* s);
long strtol(const char* s, char** endptr, int base);
unsigned long strtoul(const char* s, char** endptr, int base);
int abs(int value);

char* getenv(const char* name);
int system(const char* command);
void exit(int status) __attribute__((noreturn));
void abort(void) __attribute__((noreturn));

#endif
