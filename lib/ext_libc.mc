

when os(windows) {
    extern "msvcrt.dll" {
        i32 printf(u8* fmt, ...);
        i32 sprintf(u8* buf, u8* fmt, ...);
        i32 fprintf(void* stream, u8* fmt, ...);
        // i32 _snprintf(u8* buf, u64 size, u8* fmt, ...);
        i32 sscanf(u8* s, u8* fmt, ...);
        i64 clock();
        i32 strcmp(u8* a, u8* b);
        i32 strncmp(u8* a, u8* b, u64 n);
        i32 memcmp(void* a, void* b, u64 n);
        void* memchr(void* s, i32 c, u64 n);
        u64 strlen(u8* s);
        u8* strcpy(u8* dst, u8* src);
        u8* strncpy(u8* dst, u8* src, u64 n);
        i32 strncpy_s(u8* dst, i32 dst_size, u8* src, i32 count);
        u8* strchr(u8* s, i32 c);
        u8* strstr(u8* haystack, u8* needle);
        i32 puts(u8* s);
        i32 abs(i32 x);
        f64 atof(u8* s);
        i64 strtol(u8* s, u8** endptr, i32 base);
        void abort();
    }
    extern "ucrtbase.dll" {
        f64 floor(f64 x);
        f64 ceil(f64 x);
        f64 pow(f64 b, f64 e);
        f64 sin(f64 x);
        f64 cos(f64 x);
        f64 acos(f64 x);
        f64 fmod(f64 x, f64 y);
        f64 log(f64 x);
        f64 log2(f64 x);
        f32 sinf(f32 x);
        f32 cosf(f32 x);
        f32 tanf(f32 x);
        f32 acosf(f32 x);
        f32 atan2f(f32 y, f32 x);
        // sqrtf: provided by the runtime.
        f32 powf(f32 b, f32 e);
        f32 logf(f32 x);
        f32 floorf(f32 x);
        f32 ceilf(f32 x);
        f32 roundf(f32 x);
        f32 fmodf(f32 a, f32 b);
        void qsort(void* base, u64 n, u64 sz, fn(void*, void*): i32 cmp);
        // snprintf / vsnprintf: provided by cvararg_shim.mc.
        // memcpy, memset: provided by the runtime.
        void* memmove(void* dst, void* src, u64 n);
    }
    // MSVC FP-usage sentinel.
    i32 _fltused = 0x9875;
    // POSIX errno; a process-wide slot (not thread-local).
    i32 errno = 0;
    // Win32 high-resolution timer. void* params so LARGE_INTEGER need
    // not be in scope; callers pass a pointer to their own.
    extern "kernel32.dll" {
        i32 QueryPerformanceFrequency(void* p);
        i32 QueryPerformanceCounter(void* p);
    }
}
when os(linux) {
    extern "libc.so.6" {
        void qsort(void* base, u64 n, u64 sz, fn(void*, void*): i32 cmp);
        i32 printf(u8* fmt, ...);
        i32 sprintf(u8* buf, u8* fmt, ...);
        i32 fprintf(void* stream, u8* fmt, ...);
        i32 sscanf(u8* s, u8* fmt, ...);
        i64 clock();
        i32 strcmp(u8* a, u8* b);
        i32 strncmp(u8* a, u8* b, u64 n);
        i32 memcmp(void* a, void* b, u64 n);
        void* memchr(void* s, i32 c, u64 n);
        u64 strlen(u8* s);
        u8* strcpy(u8* dst, u8* src);
        u8* strncpy(u8* dst, u8* src, u64 n);
        i32 strncpy_s(u8* dst, i32 dst_size, u8* src, i32 count);
        u8* strchr(u8* s, i32 c);
        u8* strstr(u8* haystack, u8* needle);
        i32 puts(u8* s);
        i32 abs(i32 x);
        f64 atof(u8* s);
        i64 strtol(u8* s, u8** endptr, i32 base);
        // malloc, calloc, realloc, free: provided by the runtime allocator.
        void abort();
        void* memmove(void* dst, void* src, u64 n);
    }
    // glibc math functions in libm.so.6
    extern "libm.so.6" {
        // fabs, sqrt, fabsf, sqrtf: provided by the runtime.
        f64 floor(f64 x);
        f64 ceil(f64 x);
        f64 pow(f64 b, f64 e);
        f64 sin(f64 x);
        f64 cos(f64 x);
        f64 acos(f64 x);
        f64 fmod(f64 x, f64 y);
        f64 log(f64 x);
        f64 log2(f64 x);
        // f32 math
        f32 sinf(f32 x);
        f32 cosf(f32 x);
        f32 tanf(f32 x);
        f32 acosf(f32 x);
        f32 atan2f(f32 y, f32 x);
        f32 powf(f32 b, f32 e);
        f32 logf(f32 x);
        f32 floorf(f32 x);
        f32 ceilf(f32 x);
        f32 roundf(f32 x);
        f32 fmodf(f32 a, f32 b);
    }
}
when os(android) {
    // Android Bionic
    extern "libc.so" {
        void qsort(void* base, u64 n, u64 sz, fn(void*, void*): i32 cmp);
        i32 printf(u8* fmt, ...);
        i32 sprintf(u8* buf, u8* fmt, ...);
        i32 fprintf(void* stream, u8* fmt, ...);
        i32 sscanf(u8* s, u8* fmt, ...);
        i64 clock();
        i32 strcmp(u8* a, u8* b);
        i32 strncmp(u8* a, u8* b, u64 n);
        i32 memcmp(void* a, void* b, u64 n);
        void* memchr(void* s, i32 c, u64 n);
        u64 strlen(u8* s);
        u8* strcpy(u8* dst, u8* src);
        u8* strncpy(u8* dst, u8* src, u64 n);
        u8* strchr(u8* s, i32 c);
        u8* strstr(u8* haystack, u8* needle);
        i32 puts(u8* s);
        i32 abs(i32 x);
        f64 atof(u8* s);
        i64 strtol(u8* s, u8** endptr, i32 base);
        void abort();
        void* memmove(void* dst, void* src, u64 n);
    }
    extern "libm.so" {
        f64 floor(f64 x);
        f64 ceil(f64 x);
        f64 pow(f64 b, f64 e);
        f64 sin(f64 x);
        f64 cos(f64 x);
        f64 acos(f64 x);
        f64 fmod(f64 x, f64 y);
        f64 log(f64 x);
        f64 log2(f64 x);
        f32 sinf(f32 x);
        f32 cosf(f32 x);
        f32 tanf(f32 x);
        f32 acosf(f32 x);
        f32 atan2f(f32 y, f32 x);
        f32 powf(f32 b, f32 e);
        f32 logf(f32 x);
        f32 floorf(f32 x);
        f32 ceilf(f32 x);
        f32 roundf(f32 x);
        f32 fmodf(f32 a, f32 b);
    }
}
// Numeric constants. Values are stable across platforms.
const i32 MAX_PATH = 260;
const i32 S_IFMT = 0xF000;
const i32 S_IFREG = 0x8000;
const i32 S_IFDIR = 0x4000;
when os(macos) || os(ios) {
    // On macOS, libSystem.B.dylib provides both libc and libm.
    extern "libSystem.B.dylib" {
        void qsort(void* base, u64 n, u64 sz, fn(void*, void*): i32 cmp);
        i32 printf(u8* fmt, ...);
        i32 sprintf(u8* buf, u8* fmt, ...);
        i32 fprintf(void* stream, u8* fmt, ...);
        i32 sscanf(u8* s, u8* fmt, ...);
        i64 clock();
        i32 strcmp(u8* a, u8* b);
        i32 strncmp(u8* a, u8* b, u64 n);
        i32 memcmp(void* a, void* b, u64 n);
        void* memchr(void* s, i32 c, u64 n);
        u64 strlen(u8* s);
        u8* strcpy(u8* dst, u8* src);
        u8* strncpy(u8* dst, u8* src, u64 n);
        i32 strncpy_s(u8* dst, i32 dst_size, u8* src, i32 count);
        u8* strchr(u8* s, i32 c);
        u8* strstr(u8* haystack, u8* needle);
        i32 puts(u8* s);
        i32 abs(i32 x);
        f64 atof(u8* s);
        i64 strtol(u8* s, u8** endptr, i32 base);
        // fabs, sqrt: provided by the runtime.
        f64 floor(f64 x);
        f64 ceil(f64 x);
        f64 pow(f64 b, f64 e);
        f64 sin(f64 x);
        f64 cos(f64 x);
        f64 acos(f64 x);
        f64 fmod(f64 x, f64 y);
        f64 log(f64 x);
        f64 log2(f64 x);
        // f32 math
        f32 sinf(f32 x);
        f32 cosf(f32 x);
        f32 tanf(f32 x);
        f32 acosf(f32 x);
        f32 atan2f(f32 y, f32 x);
        // sqrtf: provided by the runtime.
        f32 powf(f32 b, f32 e);
        f32 logf(f32 x);
        // fabsf: provided by the runtime.
        f32 floorf(f32 x);
        f32 ceilf(f32 x);
        f32 roundf(f32 x);
        f32 fmodf(f32 a, f32 b);
        // malloc, calloc, realloc, free: provided by the runtime allocator.
        void abort();
        void* memmove(void* dst, void* src, u64 n);
    }
}

// <float.h> limits + <stdlib.h> RAND_MAX, as constants.
const i32 RAND_MAX = 32767;

const f32 FLT_MAX = 3.40282347e38f;
const f32 FLT_MIN = 1.17549435e-38f;
const f32 FLT_EPSILON = 1.19209290e-7f;
const f64 DBL_MAX = 1.7976931348623157e308;
const f64 DBL_MIN = 2.2250738585072014e-308;
const f64 DBL_EPSILON = 2.2204460492503131e-16;

// <math.h> NAN / INFINITY as f32 constants.
const f32 NAN = 0.0f / 0.0f;
const f32 INFINITY = 1.0f / 0.0f;

// assert(cond): aborts on failure. Param is i64; nonzero = true.
void assert(i64 cond) {
    if cond == 0 {
        eprint("assertion failed\n");
        exit(1);
    }
}

// POSIX <time.h>: timespec + clock_gettime.
struct timespec { i64 tv_sec; i64 tv_nsec; }
when os(windows) {
    i32 clock_gettime(i32 clk_id, timespec* tp) {
        i64 ticks = 0;
        i64 freq = 0;
        QueryPerformanceCounter(cast(void*, &ticks));
        QueryPerformanceFrequency(cast(void*, &freq));
        if freq == 0 { tp.tv_sec = 0; tp.tv_nsec = 0; return 0; }
        tp.tv_sec = ticks / freq;
        tp.tv_nsec = (ticks % freq) * 1000000000 / freq;
        return 0;
    }
} else when os(linux) {
    extern "libc.so.6" i32 clock_gettime(i32 clk_id, void* tp);
} else when os(macos) || os(ios) {
    extern "libSystem.B.dylib" i32 clock_gettime(i32 clk_id, void* tp);
}

// <stdio.h> file I/O. SEEK_* standard ANSI values.
const i32 SEEK_SET = 0;
const i32 SEEK_CUR = 1;
const i32 SEEK_END = 2;
when os(windows) {
    extern "msvcrt.dll" {
        i64 time(i64* t);
    }
}
when os(linux) {
    extern "libc.so.6" {
        i64 time(i64* t);
    }
}
when os(macos) || os(ios) {
    extern "libSystem.B.dylib" {
        i64 time(i64* t);
    }
}


// --- wasm target ---
// libc subset for wasm.
when os(wasm) {
    // abort delegates to the JS host (which logs + stops).
    extern "env" void __wasm_abort();
    void abort() { __wasm_abort(); }

    // Math comes from the math module (it defines the wasm versions).
    import math;

    // --- memory ---
    i32 memcmp(void* a, void* b, u64 n) {
        u8* pa = cast(u8*, a); u8* pb = cast(u8*, b);
        for u64 i = 0; i < n; i = i + 1 {
            if *(pa + i) != *(pb + i) {
                return cast(i32, *(pa + i)) - cast(i32, *(pb + i));
            }
        }
        return 0;
    }
    void* memmove(void* dst, void* src, u64 n) {
        u8* d = cast(u8*, dst); u8* s = cast(u8*, src);
        if cast(i64, d) < cast(i64, s) {
            for u64 i = 0; i < n; i = i + 1 { *(d + i) = *(s + i); }
        } else {
            for u64 i = n; i > 0; i = i - 1 { *(d + (i - 1)) = *(s + (i - 1)); }
        }
        return dst;
    }
    void* memchr(void* s, i32 c, u64 n) {
        u8* p = cast(u8*, s); u8 ch = cast(u8, c);
        for u64 i = 0; i < n; i = i + 1 {
            if *(p + i) == ch { return cast(void*, p + i); }
        }
        return cast(void*, 0);
    }

    // --- strings ---
    u64 strlen(u8* s) { u64 n = 0; while *(s + n) != 0 { n = n + 1; } return n; }
    i32 strcmp(u8* a, u8* b) {
        while *a != 0 && *a == *b { a = a + 1; b = b + 1; }
        return cast(i32, *a) - cast(i32, *b);
    }
    i32 strncmp(u8* a, u8* b, u64 n) {
        for u64 i = 0; i < n; i = i + 1 {
            u8 ca = *(a + i); u8 cb = *(b + i);
            if ca != cb { return cast(i32, ca) - cast(i32, cb); }
            if ca == 0 { return 0; }
        }
        return 0;
    }
    u8* strcpy(u8* dst, u8* src) {
        u64 i = 0;
        while *(src + i) != 0 { *(dst + i) = *(src + i); i = i + 1; }
        *(dst + i) = 0;
        return dst;
    }
    u8* strncpy(u8* dst, u8* src, u64 n) {
        for u64 i = 0; i < n; i = i + 1 {
            *(dst + i) = *(src + i);
            if *(src + i) == 0 {
                for u64 j = i + 1; j < n; j = j + 1 { *(dst + j) = 0; }
                return dst;
            }
        }
        return dst;
    }
    u8* strchr(u8* s, i32 c) {
        u8 ch = cast(u8, c);
        while *s != 0 { if *s == ch { return s; } s = s + 1; }
        if ch == 0 { return s; }
        return null;
    }
    u8* strstr(u8* hay, u8* needle) {
        if *needle == 0 { return hay; }
        while *hay != 0 {
            u8* h = hay; u8* n = needle;
            while *h != 0 && *h == *n { h = h + 1; n = n + 1; }
            if *n == 0 { return hay; }
            hay = hay + 1;
        }
        return null;
    }

    // --- time ---
    // Host monotonic clock in nanoseconds.
    extern "env" i64 clock();
    i32 clock_gettime(i32 clk_id, void* tp) {
        i64 ns = clock();
        i64* p = cast(i64*, tp);
        *p = ns / 1000000000;
        *(p + 1) = ns % 1000000000;
        return 0;
    }
    // No blocking sleep in the browser; nanosleep is a no-op.
    i32 nanosleep(void* req, void* rem) { ignore req; ignore rem; return 0; }
    i64 time(i64* t) {
        i64 s = clock() / 1000000000;
        if t != null { *t = s; }
        return s;
    }

    // --- stdio (console) ---
    // puts writes the string + a newline to stdout.
    i32 puts(u8* s) {
        str line = { .data = s, .len = cast(i32, strlen(s)) };
        print("{}\n", line);
        return 0;
    }

    // --- stdlib numerics ---
    i32 abs(i32 x) { if x < 0 { return -x; } return x; }
    // Minimal atof: sign, integer + fraction, optional e-exponent.
    f64 atof(u8* s) {
        while *s == cast(u8, 32) || *s == cast(u8, 9) { s = s + 1; }
        f64 sign = 1.0;
        if *s == cast(u8, 45) { sign = -1.0; s = s + 1; }
        else if *s == cast(u8, 43) { s = s + 1; }
        f64 r = 0.0;
        while *s >= cast(u8, 48) && *s <= cast(u8, 57) { r = r * 10.0 + cast(f64, *s - cast(u8, 48)); s = s + 1; }
        if *s == cast(u8, 46) {
            s = s + 1; f64 frac = 0.1;
            while *s >= cast(u8, 48) && *s <= cast(u8, 57) { r = r + cast(f64, *s - cast(u8, 48)) * frac; frac = frac * 0.1; s = s + 1; }
        }
        if *s == cast(u8, 101) || *s == cast(u8, 69) {
            s = s + 1; f64 esign = 1.0;
            if *s == cast(u8, 45) { esign = -1.0; s = s + 1; } else if *s == cast(u8, 43) { s = s + 1; }
            i32 e = 0;
            while *s >= cast(u8, 48) && *s <= cast(u8, 57) { e = e * 10 + cast(i32, *s - cast(u8, 48)); s = s + 1; }
            f64 p = 1.0;
            for i32 i = 0; i < e; i = i + 1 { p = p * 10.0; }
            if esign < 0.0 { r = r / p; } else { r = r * p; }
        }
        return r * sign;
    }
    // Insertion sort; cmp follows the C qsort contract (<0, 0, >0).
    void qsort(void* base, u64 nmemb, u64 size, fn(void*, void*): i32 cmp) {
        u8* b = cast(u8*, base);
        for u64 i = 1; i < nmemb; i = i + 1 {
            for u64 j = i; j > 0; j = j - 1 {
                u8* x = b + (j - 1) * size; u8* y = b + j * size;
                if cmp(cast(void*, x), cast(void*, y)) <= 0 { break; }
                for u64 k = 0; k < size; k = k + 1 {
                    u8 t = *(x + k); *(x + k) = *(y + k); *(y + k) = t;
                }
            }
        }
    }
}


// --- runtime helpers ---
// Widen a narrow string to a u16* buffer for L"…" literals.
// Allocates per call.
u16* __wide_literal(u8* s) {
    if s == null { return null; }
    i32 n = 0;
    while *(s + n) != 0 { n = n + 1; }
    u16* buf = alloc<u16>(n + 1);
    for i32 i = 0; i < n; i = i + 1 {
        *(buf + i) = cast(u16, *(s + i));
    }
    *(buf + n) = 0;
    return buf;
}


// Extra libc surface for the sokol headers (macOS/iOS).

when os(macos) || os(ios) {
    // Stand-in for the C FILE* `stderr` global
    // Its value is unused; output routes to stderr directly.
    void* c_stderr;
    // Writes a preformatted line to stderr.
    i32 _sokol_fputs(u8* s, void* stream) {
        write(stderr(), s, cast(i32, strlen(s)));
        return 0;
    }
}


// printf-family formatting (%d %i %u %x %X %c %s %f %p %%) in pure minc.
// Supports l/ll/z length modifiers, field width, zero-pad, float precision.

i32 _vp(u8* buf, u64 cap, i32 pos, u8 c) {
    if pos >= 0 && cap > 0 && cast(u64, pos) < cap - 1 { *(buf + pos) = c; }
    return pos + 1;
}

i32 _vp_uint(u8* buf, u64 cap, i32 pos, u64 v, i32 base, bool upper, i32 width, bool zero) {
    u8[24] tmp;
    i32 n = 0;
    if v == 0 { tmp[0] = 48; n = 1; }
    while v > 0 {
        u64 d = v % cast(u64, base);
        if d < 10 { tmp[n] = cast(u8, 48 + d); }
        else { tmp[n] = cast(u8, (upper ? 65 : 97) + cast(i32, d - 10)); }
        n = n + 1;
        v = v / cast(u64, base);
    }
    while n < width { pos = _vp(buf, cap, pos, cast(u8, zero ? 48 : 32)); width = width - 1; }
    for i32 i = n - 1; i >= 0; i = i - 1 { pos = _vp(buf, cap, pos, tmp[i]); }
    return pos;
}

i32 _vp_int(u8* buf, u64 cap, i32 pos, i64 v, i32 width, bool zero) {
    if v < 0 {
        pos = _vp(buf, cap, pos, 45);
        v = 0 - v;
        if width > 0 { width = width - 1; }
    }
    return _vp_uint(buf, cap, pos, cast(u64, v), 10, false, width, zero);
}

i32 _vp_str(u8* buf, u64 cap, i32 pos, u8* s) {
    if s == null { s = "(null)"; }
    i32 i = 0;
    while *(s + i) != 0 { pos = _vp(buf, cap, pos, *(s + i)); i = i + 1; }
    return pos;
}

i32 _vp_f64(u8* buf, u64 cap, i32 pos, f64 v, i32 prec) {
    if prec < 0 { prec = 6; }
    if v < 0.0 { pos = _vp(buf, cap, pos, 45); v = 0.0 - v; }
    i64 ip = cast(i64, v);
    pos = _vp_uint(buf, cap, pos, cast(u64, ip), 10, false, 0, false);
    if prec > 0 {
        pos = _vp(buf, cap, pos, 46);
        f64 frac = v - cast(f64, ip);
        for i32 i = 0; i < prec; i = i + 1 {
            frac = frac * 10.0;
            i32 dig = cast(i32, frac);
            pos = _vp(buf, cap, pos, cast(u8, 48 + dig));
            frac = frac - cast(f64, dig);
        }
    }
    return pos;
}

i32 __minc_vfmt(u8* buf, u64 cap, u8* fmt, &... ap) {
    i32 pos = 0;
    i32 i = 0;
    while *(fmt + i) != 0 {
        u8 c = *(fmt + i);
        if c != 37 { pos = _vp(buf, cap, pos, c); i = i + 1; continue; }
        i = i + 1;
        bool zero = false;
        while *(fmt + i) == 48 || *(fmt + i) == 45 || *(fmt + i) == 43 || *(fmt + i) == 32 {
            if *(fmt + i) == 48 { zero = true; }
            i = i + 1;
        }
        i32 width = 0;
        while *(fmt + i) >= 48 && *(fmt + i) <= 57 { width = width * 10 + cast(i32, *(fmt + i) - 48); i = i + 1; }
        i32 prec = 0 - 1;
        if *(fmt + i) == 46 {
            i = i + 1; prec = 0;
            while *(fmt + i) >= 48 && *(fmt + i) <= 57 { prec = prec * 10 + cast(i32, *(fmt + i) - 48); i = i + 1; }
        }
        bool islong = false;
        while *(fmt + i) == 108 || *(fmt + i) == 104 || *(fmt + i) == 122 || *(fmt + i) == 106 || *(fmt + i) == 116 {
            if *(fmt + i) == 108 || *(fmt + i) == 122 || *(fmt + i) == 106 { islong = true; }
            i = i + 1;
        }
        u8 conv = *(fmt + i);
        i = i + 1;
        if conv == 100 || conv == 105 {
            if islong { pos = _vp_int(buf, cap, pos, arg_read_i64(ap), width, zero); }
            else { pos = _vp_int(buf, cap, pos, cast(i64, arg_read_i32(ap)), width, zero); }
        } else if conv == 117 {
            if islong { pos = _vp_uint(buf, cap, pos, cast(u64, arg_read_i64(ap)), 10, false, width, zero); }
            else { pos = _vp_uint(buf, cap, pos, cast(u64, cast(u32, arg_read_i32(ap))), 10, false, width, zero); }
        } else if conv == 120 || conv == 88 {
            if islong { pos = _vp_uint(buf, cap, pos, cast(u64, arg_read_i64(ap)), 16, conv == 88, width, zero); }
            else { pos = _vp_uint(buf, cap, pos, cast(u64, cast(u32, arg_read_i32(ap))), 16, conv == 88, width, zero); }
        } else if conv == 102 || conv == 70 {
            pos = _vp_f64(buf, cap, pos, arg_read_f64(ap), prec);
        } else if conv == 115 {
            pos = _vp_str(buf, cap, pos, arg_read_ptr(ap));
        } else if conv == 99 {
            pos = _vp(buf, cap, pos, cast(u8, arg_read_i32(ap)));
        } else if conv == 112 {
            pos = _vp(buf, cap, pos, 48); pos = _vp(buf, cap, pos, 120);
            pos = _vp_uint(buf, cap, pos, cast(u64, arg_read_ptr(ap)), 16, false, 0, false);
        } else if conv == 37 {
            pos = _vp(buf, cap, pos, 37);
        } else {
            pos = _vp(buf, cap, pos, 37); pos = _vp(buf, cap, pos, conv);
        }
    }
    if cap > 0 {
        i32 t = pos;
        if cast(u64, t) >= cap { t = cast(i32, cap - 1); }
        *(buf + t) = 0;
    }
    return pos;
}

i32 vsnprintf(u8* buf, u64 size, u8* fmt, &... ap) { return __minc_vfmt(buf, size, fmt, ap); }
i32 snprintf(u8* buf, u64 size, u8* fmt, ...) { return __minc_vfmt(buf, size, fmt, &...); }
i32 vsprintf(u8* buf, u8* fmt, &... ap) { return __minc_vfmt(buf, cast(u64, 2147483647), fmt, ap); }
i32 vprintf(u8* fmt, &... ap) {
    noinit u8[1024] line;
    i32 n = __minc_vfmt(cast(u8*, &line), 1024, fmt, ap);
    puts(cast(u8*, &line));
    return n;
}
when os(wasm) {
    // unbounded
    i32 sprintf(u8* buf, u8* fmt, ...) { return __minc_vfmt(buf, cast(u64, 2147483647), fmt, &...); }
    // printf / fprintf format into a scratch buffer
    i32 printf(u8* fmt, ...) {
        noinit u8[1024] line;
        i32 n = __minc_vfmt(cast(u8*, &line), 1024, fmt, &...);
        str s;
        s.data = cast(u8*, &line);
        s.len = n;
        print("{}", s);
        return n;
    }
    i32 fprintf(void* stream, u8* fmt, ...) {
        ignore stream;
        noinit u8[1024] line;
        i32 n = __minc_vfmt(cast(u8*, &line), 1024, fmt, &...);
        str s;
        s.data = cast(u8*, &line);
        s.len = n;
        eprint("{}", s);
        return n;
    }
    // sscanf sub-set: %i/%d/%u (decimal int), %f (float), %s
    // (non-whitespace token), %[^c]/%[c] single-char scanset with optional
    // width (e.g. %128[^"]), %% , literal chars, and whitespace-skips.
    // no Hex/%x and multi-char scansets.
    private bool __sc_ws(u8 c) { return c == 32 || c == 9 || c == 10 || c == 13 || c == 11 || c == 12; }
    private f32 __sc_atof(u8* s, i32 len) {
        f32 result = 0.0f;
        f32 sign = 1.0f;
        i32 i = 0;
        if i < len && *(s + i) == 45 { sign = 0.0f - 1.0f; i = i + 1; }
        else if i < len && *(s + i) == 43 { i = i + 1; }
        while i < len && *(s + i) >= 48 && *(s + i) <= 57 {
            result = result * 10.0f + cast(f32, *(s + i) - 48);
            i = i + 1;
        }
        if i < len && *(s + i) == 46 {
            i = i + 1;
            f32 frac = 0.1f;
            while i < len && *(s + i) >= 48 && *(s + i) <= 57 {
                result = result + cast(f32, *(s + i) - 48) * frac;
                frac = frac * 0.1f;
                i = i + 1;
            }
        }
        return result * sign;
    }

    i32 __minc_vsscanf(u8* s, u8* fmt, &... ap) {
        i32 si = 0;
        i32 fi = 0;
        i32 count = 0;
        while *(fmt + fi) != 0 {
            u8 fc = *(fmt + fi);
            if __sc_ws(fc) {
                while __sc_ws(*(s + si)) { si = si + 1; }
                fi = fi + 1;
            } else if fc != 37 {
                if *(s + si) != fc { break; }
                si = si + 1;
                fi = fi + 1;
            } else {
                fi = fi + 1;                 // past '%'
                i32 width = 0;
                bool hasWidth = false;
                while *(fmt + fi) >= 48 && *(fmt + fi) <= 57 {
                    width = width * 10 + cast(i32, *(fmt + fi) - 48);
                    hasWidth = true;
                    fi = fi + 1;
                }
                u8 conv = *(fmt + fi);
                fi = fi + 1;
                if conv == 105 || conv == 100 || conv == 117 {   // %i %d %u
                    while __sc_ws(*(s + si)) { si = si + 1; }
                    i64 sign = 1;
                    if *(s + si) == 45 { sign = 0 - 1; si = si + 1; }
                    else if *(s + si) == 43 { si = si + 1; }
                    bool any = false;
                    i64 v = 0;
                    while *(s + si) >= 48 && *(s + si) <= 57 {
                        v = v * 10 + cast(i64, *(s + si) - 48);
                        si = si + 1;
                        any = true;
                    }
                    if !any { break; }
                    i32* out = cast(i32*, arg_read_ptr(ap));
                    *out = cast(i32, v * sign);
                    count = count + 1;
                } else if conv == 102 {                          // %f
                    while __sc_ws(*(s + si)) { si = si + 1; }
                    i32 start = si;
                    if *(s + si) == 45 || *(s + si) == 43 { si = si + 1; }
                    while (*(s + si) >= 48 && *(s + si) <= 57) || *(s + si) == 46 { si = si + 1; }
                    if si == start { break; }
                    f32* out = cast(f32*, arg_read_ptr(ap));
                    *out = __sc_atof(s + start, si - start);
                    count = count + 1;
                } else if conv == 115 {                          // %s
                    while __sc_ws(*(s + si)) { si = si + 1; }
                    u8* out = cast(u8*, arg_read_ptr(ap));
                    i32 n = 0;
                    while *(s + si) != 0 && !__sc_ws(*(s + si)) && (!hasWidth || n < width - 1) {
                        *(out + n) = *(s + si); n = n + 1; si = si + 1;
                    }
                    *(out + n) = 0;
                    count = count + 1;
                } else if conv == 91 {                           // %[set]
                    bool negate = false;
                    if *(fmt + fi) == 94 { negate = true; fi = fi + 1; }   // '^'
                    u8 setc = *(fmt + fi);                                  // single-char set
                    while *(fmt + fi) != 0 && *(fmt + fi) != 93 { fi = fi + 1; }  // to ']'
                    if *(fmt + fi) == 93 { fi = fi + 1; }
                    u8* out = cast(u8*, arg_read_ptr(ap));
                    i32 n = 0;
                    while *(s + si) != 0 && (!hasWidth || n < width - 1) {
                        bool inset = *(s + si) == setc;
                        if negate && inset { break; }
                        if !negate && !inset { break; }
                        *(out + n) = *(s + si); n = n + 1; si = si + 1;
                    }
                    *(out + n) = 0;
                    count = count + 1;
                } else if conv == 37 {                           // %%
                    if *(s + si) == 37 { si = si + 1; }
                }
            }
        }
        return count;
    }
    i32 sscanf(u8* s, u8* fmt, ...) { return __minc_vsscanf(s, fmt, &...); }
}
