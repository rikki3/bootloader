#ifndef KERNEL_LIBC_MATH_H
#define KERNEL_LIBC_MATH_H

static inline double fabs(double value) {
    return value < 0.0 ? -value : value;
}

static inline float fabsf(float value) {
    return value < 0.0f ? -value : value;
}

#endif
