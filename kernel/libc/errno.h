#ifndef KERNEL_LIBC_ERRNO_H
#define KERNEL_LIBC_ERRNO_H

#define EPERM 1
#define ENOENT 2
#define EIO 5
#define ENOMEM 12
#define EACCES 13
#define EEXIST 17
#define EISDIR 21
#define EINVAL 22

extern int errno;

#endif
