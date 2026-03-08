#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include "doom_wad.h"
#include "platform.h"

#define NANOPRINTF_IMPLEMENTATION
#define NANOPRINTF_USE_FIELD_WIDTH_FORMAT_SPECIFIERS 1
#define NANOPRINTF_USE_PRECISION_FORMAT_SPECIFIERS 1
#define NANOPRINTF_USE_FLOAT_FORMAT_SPECIFIERS 0
#define NANOPRINTF_USE_LARGE_FORMAT_SPECIFIERS 1
#define NANOPRINTF_USE_SMALL_FORMAT_SPECIFIERS 1
#define NANOPRINTF_USE_BINARY_FORMAT_SPECIFIERS 0
#define NANOPRINTF_USE_WRITEBACK_FORMAT_SPECIFIERS 0
#define NANOPRINTF_USE_ALT_FORM_FLAG 1
#include "../third_party/nanoprintf/nanoprintf.h"

enum {
    FILE_KIND_STDIN = 1,
    FILE_KIND_STDOUT = 2,
    FILE_KIND_STDERR = 3,
    FILE_KIND_BOOT_WAD = 4,
    FILE_KIND_SINK = 5,
};

static FILE stdin_file = { FILE_KIND_STDIN, 0, 0, 0, 0, 0 };
static FILE stdout_file = { FILE_KIND_STDOUT, 0, 0, 0, 1, 0 };
static FILE stderr_file = { FILE_KIND_STDERR, 0, 0, 0, 1, 0 };

FILE* stdin = &stdin_file;
FILE* stdout = &stdout_file;
FILE* stderr = &stderr_file;

static int max_int(int left, int right) {
    return left > right ? left : right;
}

static void append_char(char* buffer, size_t size, size_t* used, char c) {
    if (*used + 1 < size) {
        buffer[*used] = c;
    }
    ++*used;
}

static void append_text(char* buffer, size_t size, size_t* used, const char* text, size_t len) {
    size_t i;
    for (i = 0; i < len; ++i) {
        append_char(buffer, size, used, text[i]);
    }
}

static void format_unsigned(char* out, size_t out_size,
                            unsigned long long value, unsigned base,
                            int uppercase, int min_digits) {
    static const char digits_lower[] = "0123456789abcdef";
    static const char digits_upper[] = "0123456789ABCDEF";
    const char* digits = uppercase ? digits_upper : digits_lower;
    char temp[64];
    int count = 0;

    if (base < 2 || base > 16) {
        out[0] = '\0';
        return;
    }

    do {
        temp[count++] = digits[value % base];
        value /= base;
    } while (value != 0);

    while (count < min_digits) {
        temp[count++] = '0';
    }

    if ((size_t) count >= out_size) {
        count = (int) out_size - 1;
    }

    {
        int i;
        for (i = 0; i < count; ++i) {
            out[i] = temp[count - 1 - i];
        }
        out[count] = '\0';
    }
}

int format_vbuffer(char* buffer, size_t size, const char* format, va_list* args) {
    return npf_vsnprintf(buffer, size, format, *args);
}

int vsnprintf(char* buffer, size_t size, const char* format, va_list args) {
    va_list copy;
    int result;

    va_copy(copy, args);
    result = npf_vsnprintf(buffer, size, format, copy);
    va_end(copy);
    return result;
}

int snprintf(char* buffer, size_t size, const char* format, ...) {
    va_list args;
    int result;
    va_start(args, format);
    result = format_vbuffer(buffer, size, format, &args);
    va_end(args);
    return result;
}

int sprintf(char* buffer, const char* format, ...) {
    va_list args;
    int result;
    va_start(args, format);
    result = format_vbuffer(buffer, (size_t) -1, format, &args);
    va_end(args);
    return result;
}

static int write_stream(FILE* stream, const char* text, size_t len) {
    size_t i;

    if (stream == 0) {
        return 0;
    }

    switch (stream->kind) {
    case FILE_KIND_STDOUT:
    case FILE_KIND_STDERR:
        for (i = 0; i < len; ++i) {
            if (text[i] == '\n') {
                serial_putc('\r');
            }
            serial_putc(text[i]);
        }
        stream->pos += len;
        return (int) len;
    case FILE_KIND_SINK:
        stream->pos += len;
        if (stream->pos > stream->length) {
            stream->length = stream->pos;
        }
        return (int) len;
    default:
        return 0;
    }
}

int vfprintf(FILE* stream, const char* format, va_list args) {
    char buffer[1024];
    va_list copy;
    int len;
    va_copy(copy, args);
    len = format_vbuffer(buffer, sizeof(buffer), format, &copy);
    va_end(copy);
    write_stream(stream, buffer, (size_t) len);
    return len;
}

int printf(const char* format, ...) {
    va_list args;
    int result;
    va_start(args, format);
    result = vfprintf(stdout, format, args);
    va_end(args);
    return result;
}

int fprintf(FILE* stream, const char* format, ...) {
    va_list args;
    int result;
    va_start(args, format);
    result = vfprintf(stream, format, args);
    va_end(args);
    return result;
}

int putchar(int c) {
    char ch = (char) c;
    write_stream(stdout, &ch, 1);
    return c;
}

int puts(const char* s) {
    write_stream(stdout, s, strlen(s));
    write_stream(stdout, "\n", 1);
    return 0;
}

static FILE* alloc_file(int kind, int writable, const unsigned char* data, uint64_t length) {
    FILE* file = malloc(sizeof(FILE));
    if (file == 0) {
        errno = ENOMEM;
        return 0;
    }
    file->kind = kind;
    file->pos = 0;
    file->length = length;
    file->data = data;
    file->writable = writable;
    file->error = 0;
    return file;
}

FILE* fopen(const char* path, const char* mode) {
    const uint8_t* data;
    size_t size;

    errno = 0;
    if (path == 0 || mode == 0) {
        errno = EINVAL;
        return 0;
    }

    if (strchr(mode, 'w') != 0 || strchr(mode, 'a') != 0) {
        return alloc_file(FILE_KIND_SINK, 1, 0, 0);
    }

    if (doom_wad_match_path(path, &data, &size)) {
        return alloc_file(FILE_KIND_BOOT_WAD, 0, data, size);
    }

    errno = ENOENT;
    return 0;
}

int fclose(FILE* stream) {
    if (stream == 0 || stream == stdin || stream == stdout || stream == stderr) {
        return 0;
    }
    free(stream);
    return 0;
}

size_t fread(void* ptr, size_t size, size_t count, FILE* stream) {
    size_t total = size * count;
    size_t available;

    if (stream == 0 || stream->kind != FILE_KIND_BOOT_WAD || size == 0) {
        return 0;
    }
    if (stream->pos >= stream->length) {
        return 0;
    }

    available = (size_t) (stream->length - stream->pos);
    if (total > available) {
        total = available;
    }
    memcpy(ptr, stream->data + stream->pos, total);
    stream->pos += total;
    return total / size;
}

size_t fwrite(const void* ptr, size_t size, size_t count, FILE* stream) {
    size_t total = size * count;
    return (size == 0) ? 0 : (size_t) write_stream(stream, (const char*) ptr, total) / size;
}

int fseek(FILE* stream, long offset, int whence) {
    uint64_t target;

    if (stream == 0) {
        return -1;
    }

    switch (whence) {
    case SEEK_SET:
        target = (offset < 0) ? 0 : (uint64_t) offset;
        break;
    case SEEK_CUR:
        target = stream->pos + offset;
        break;
    case SEEK_END:
        target = stream->length + offset;
        break;
    default:
        errno = EINVAL;
        return -1;
    }

    if (stream->kind == FILE_KIND_BOOT_WAD && target > stream->length) {
        target = stream->length;
    }

    stream->pos = target;
    return 0;
}

long ftell(FILE* stream) {
    return stream == 0 ? -1L : (long) stream->pos;
}

int fflush(FILE* stream) {
    (void) stream;
    return 0;
}

int fileno(FILE* stream) {
    if (stream == stdin) {
        return 0;
    }
    if (stream == stdout) {
        return 1;
    }
    if (stream == stderr) {
        return 2;
    }
    return -1;
}

int access(const char* path, int mode) {
    (void) path;
    (void) mode;
    return -1;
}

int isatty(int fd) {
    (void) fd;
    return 0;
}

int close(int fd) {
    (void) fd;
    return 0;
}

int mkdir(const char* path, mode_t mode) {
    (void) path;
    (void) mode;
    return 0;
}

int remove(const char* path) {
    (void) path;
    return -1;
}

int rename(const char* old_path, const char* new_path) {
    (void) old_path;
    (void) new_path;
    return -1;
}

static int scan_unsigned(const char** input, int base, int* out) {
    char* end;
    unsigned long value;
    while (isspace((unsigned char) **input)) {
        ++*input;
    }
    value = strtoul(*input, &end, base);
    if (end == *input) {
        return 0;
    }
    *out = (int) value;
    *input = end;
    return 1;
}

int sscanf(const char* buffer, const char* format, ...) {
    va_list args;
    int matched = 0;

    va_start(args, format);
    while (*format != '\0') {
        if (isspace((unsigned char) *format)) {
            while (isspace((unsigned char) *buffer)) {
                ++buffer;
            }
            ++format;
            continue;
        }

        if (*format != '%') {
            if (*buffer != *format) {
                break;
            }
            ++buffer;
            ++format;
            continue;
        }

        ++format;
        if (*format == 'd') {
            int* out = va_arg(args, int*);
            if (!scan_unsigned(&buffer, 10, out)) {
                break;
            }
            ++matched;
            ++format;
            continue;
        }
        if (*format == 'x' || *format == 'X') {
            int* out = va_arg(args, int*);
            if (!scan_unsigned(&buffer, 16, out)) {
                break;
            }
            ++matched;
            ++format;
            continue;
        }
        if (*format == 'o') {
            int* out = va_arg(args, int*);
            if (!scan_unsigned(&buffer, 8, out)) {
                break;
            }
            ++matched;
            ++format;
            continue;
        }
        break;
    }
    va_end(args);
    return matched;
}
