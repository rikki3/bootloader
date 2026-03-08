#ifndef KERNEL_LIBC_UNISTD_H
#define KERNEL_LIBC_UNISTD_H

int access(const char* path, int mode);
int isatty(int fd);
int close(int fd);

#endif
