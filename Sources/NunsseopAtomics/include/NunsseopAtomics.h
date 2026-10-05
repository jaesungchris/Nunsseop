#ifndef NunsseopAtomics_h
#define NunsseopAtomics_h

#include <stdatomic.h>

// A float shared between the main thread and a real-time audio thread. Relaxed, lock-free
// loads and stores: a 32-bit float is lock-free on arm64 and x86-64, so neither side can block.

static inline float nunsseop_atomic_load_float(float *value) {
    return atomic_load_explicit((_Atomic float *)value, memory_order_relaxed);
}

static inline void nunsseop_atomic_store_float(float *value, float newValue) {
    atomic_store_explicit((_Atomic float *)value, newValue, memory_order_relaxed);
}

#endif
