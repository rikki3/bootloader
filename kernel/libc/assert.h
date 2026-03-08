#ifndef KERNEL_LIBC_ASSERT_H
#define KERNEL_LIBC_ASSERT_H

#include "platform.h"

#define assert(expr) do { if (!(expr)) platform_panic("assertion failed: %s", #expr); } while (0)

#endif
