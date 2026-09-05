// libc subset: <stdio.h>/<ctype.h>/<math.h>/<string.h>/<stdlib.h>, per OS.
//
// math, ctype, str*/mem*, qsort, rand and the number parsers come from
// the math module, which implements them in minc. Results are identical
// on every target.
//
import math;

when os(windows) {
    extern "msvcrt.dll" {
        // i32 _snprintf(u8* buf, u64 size, u8* fmt, ...);
        i32 sscanf(u8* s, u8* fmt, ...);
        i64 clock();
        i32 strncpy_s(u8* dst, i32 dst_size, u8* src, i32 count);
        i32 puts(u8* s);
    }
    // MSVC FP-usage sentinel.
    i32 _fltused = 0x9875;
    // POSIX errno; a process-wide slot (not thread-local).
    i32 errno = 0;
    // Win32 high-resolution timer, over minc's qpc/qpf builtins.
    i32 QueryPerformanceFrequency(void* p) { *cast(i64*, p) = qpf(); return 1; }
    i32 QueryPerformanceCounter(void* p)   { *cast(i64*, p) = qpc(); return 1; }
}
when os(linux) {
    extern "libc.so.6" {
        i32 sscanf(u8* s, u8* fmt, ...);
        i64 clock();
        i32 strncpy_s(u8* dst, i32 dst_size, u8* src, i32 count);
        i32 puts(u8* s);
    }
}
when os(android) {
    // Android Bionic
    extern "libc.so" {
        i32 sscanf(u8* s, u8* fmt, ...);
        i64 clock();
        i32 puts(u8* s);
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
        i32 sscanf(u8* s, u8* fmt, ...);
        i64 clock();
        i32 strncpy_s(u8* dst, i32 dst_size, u8* src, i32 count);
        i32 puts(u8* s);
    }
}

// <float.h> limits + <stdlib.h> RAND_MAX, as constants.
// rand() comes from the math module and RAND_MAX is 2^31-1.
const i32 RAND_MAX = 0x7FFFFFFF;

const f32 FLT_MAX = 3.40282347e38f;
const f32 FLT_MIN = 1.17549435e-38f;
const f32 FLT_EPSILON = 1.19209290e-7f;
const f64 DBL_MAX = 1.7976931348623157e308;
const f64 DBL_MIN = 2.2250738585072014e-308;
const f64 DBL_EPSILON = 2.2204460492503131e-16;

// <math.h> NAN / INFINITY as f32 constants.
const f32 NAN = 0.0f / 0.0f;
const f32 INFINITY = 1.0f / 0.0f;

// isnan / isinf / isfinite and copysign / ldexp / frexp / hypot come
// from the math module, as f32 and f64 overloads.

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
        i64 ticks = qpc();
        i64 freq = qpf();
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
        u64 fwrite(void* p, u64 sz, u64 n, void* f);
        i64 time(i64* t);
    }
}
when os(linux) {
    extern "libc.so.6" {
        u64 fwrite(void* p, u64 sz, u64 n, void* f);
        i64 time(i64* t);
    }
}
when os(android) {
    extern "libc.so" {
        u64 fwrite(void* p, u64 sz, u64 n, void* f);
        i64 time(i64* t);
    }
}
when os(macos) || os(ios) {
    extern "libSystem.B.dylib" {
        u64 fwrite(void* p, u64 sz, u64 n, void* f);
        i64 time(i64* t);
    }
}


// --- wasm target ---
// libc subset for wasm.
when os(wasm) {

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

    // --- buffered file I/O over the host VFS ---
    struct __rl_file { u8* data; i64 size; i64 pos; i32 err; }
    // The host VFS is read-only. Set err and return zero.
    u64 fwrite(void* p, u64 sz, u64 n, void* stream) {
        ignore p; ignore sz; ignore n;
        if stream != null {
            __rl_file* f = cast(__rl_file*, stream);
            f.err = 1;
        }
        return 0;
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


// printf-family formatting in pure minc: %d %i %u %o %x %X %c %s %p
// %f %F %e %E %g %G %%, with the '-' '+' ' ' '0' '#' flags, field
// width, precision, and the h/hh/l/ll/z/j/t length modifiers.
//
// Owned rather than bound so output does not vary with the platform
// CRT. msvcrt, glibc and Apple libc disagree on half-way rounding of
// %.Nf and on %g's shortest form; this file picks one behaviour for
// every target: round-half-away-from-zero on the value as the double
// actually holds it.
//
// Shape: every conversion renders its digits into a small local
// buffer, then one field-emit applies width, padding and alignment.
// That keeps '-' (left-align) working uniformly instead of per
// conversion, and keeps the hot path to one bounds check per byte.
//
// Not supported: %a/%A (hex float), %n, wide/positional forms. Those
// fall through and echo the conversion literally, as before.
import math;

i32 _vp(u8* buf, u64 cap, i32 pos, u8 c) {
    if pos >= 0 && cap > 0 && cast(u64, pos) < cap - 1 { *(buf + pos) = c; }
    return pos + 1;
}

i32 _vp_run(u8* buf, u64 cap, i32 pos, u8* src, i32 len) {
    for i32 i = 0; i < len; i = i + 1 { pos = _vp(buf, cap, pos, *(src + i)); }
    return pos;
}

i32 _vp_fill(u8* buf, u64 cap, i32 pos, u8 c, i32 n) {
    for i32 i = 0; i < n; i = i + 1 { pos = _vp(buf, cap, pos, c); }
    return pos;
}

// Emit `body` in a `width` field. `lead` is the sign/prefix that must
// stay left of any zero padding ("-", "+", "0x").
i32 _vp_field(u8* buf, u64 cap, i32 pos, u8* lead, i32 llen,
              u8* body, i32 blen, i32 width, bool zero, bool left) {
    i32 total = llen + blen;
    i32 pad = width - total;
    if pad < 0 { pad = 0; }
    if left {
        pos = _vp_run(buf, cap, pos, lead, llen);
        pos = _vp_run(buf, cap, pos, body, blen);
        return _vp_fill(buf, cap, pos, 32, pad);
    }
    if zero {
        pos = _vp_run(buf, cap, pos, lead, llen);
        pos = _vp_fill(buf, cap, pos, 48, pad);
        return _vp_run(buf, cap, pos, body, blen);
    }
    pos = _vp_fill(buf, cap, pos, 32, pad);
    pos = _vp_run(buf, cap, pos, lead, llen);
    return _vp_run(buf, cap, pos, body, blen);
}

// Unsigned digits, most-significant first. Returns the length.
i32 _vp_digits(u8* out, u64 v, i32 base, bool upper) {
    noinit u8[24] tmp;
    i32 n = 0;
    if v == 0 { tmp[0] = 48; n = 1; }
    while v > 0 {
        u64 d = v % cast(u64, base);
        if d < 10 { tmp[n] = cast(u8, 48 + d); }
        else { tmp[n] = cast(u8, (upper ? 55 : 87) + cast(i32, d)); }
        n = n + 1;
        v = v / cast(u64, base);
    }
    for i32 i = 0; i < n; i = i + 1 { *(out + i) = tmp[n - 1 - i]; }
    return n;
}

// --- float rendering --------------------------------------------------
//
// 10^(2^k) ladders, so normalising a 1e308 value takes ~9 steps rather
// than 308 multiplies.
f64[9] __vf_pow_up = {1e1, 1e2, 1e4, 1e8, 1e16, 1e32, 1e64, 1e128, 1e256};
f64[9] __vf_pow_dn = {1e-1, 1e-2, 1e-4, 1e-8, 1e-16, 1e-32, 1e-64, 1e-128, 1e-256};

// Scale |v| into [1, 10) and return its decimal exponent. v must be
// finite and > 0.
i32 __vf_norm(f64* v, f64 x) {
    i32 e = 0;
    if x >= 10.0 {
        for i32 k = 8; k >= 0; k = k - 1 {
            f64 p = __vf_pow_up[k];
            while x >= p { x = x / p; e = e + (1 << k); }
        }
    } else if x < 1.0 {
        for i32 k = 8; k >= 0; k = k - 1 {
            f64 p = __vf_pow_dn[k];
            // step down only while it stays below 1
            while x < p * 10.0 { x = x / p; e = e - (1 << k); }
        }
    }
    // the ladder can land a hair outside on the boundary
    while x >= 10.0 { x = x / 10.0; e = e + 1; }
    while x < 1.0 { x = x * 10.0; e = e - 1; }
    *v = x;
    return e;
}

// nan / inf body. Returns 0 when v is finite.
i32 __vf_special(u8* out, f64 v, bool upper) {
    if v != v {
        *(out + 0) = cast(u8, upper ? 78 : 110); *(out + 1) = cast(u8, upper ? 65 : 97);
        *(out + 2) = cast(u8, upper ? 78 : 110);
        return 3;
    }
    if v == v && v - v != 0.0 {
        *(out + 0) = cast(u8, upper ? 73 : 105); *(out + 1) = cast(u8, upper ? 78 : 110);
        *(out + 2) = cast(u8, upper ? 70 : 102);
        return 3;
    }
    return 0;
}

// %f body for a non-negative finite v. prec >= 0.
i32 __vf_fixed(u8* out, f64 v, i32 prec, bool alt) {
    if prec > 30 { prec = 30; }
    noinit u8[40] fd;
    // Integer part. Values at or above 2^63 cannot go through u64, so
    // they render through the scientific path instead (guarded by the
    // caller); here the cast is safe.
    u64 ip = cast(u64, v);
    f64 fr = v - cast(f64, ip);
    for i32 i = 0; i < prec; i = i + 1 {
        fr = fr * 10.0;
        i32 d = cast(i32, fr);
        if d > 9 { d = 9; }
        if d < 0 { d = 0; }
        fd[i] = cast(u8, d);
        fr = fr - cast(f64, d);
    }
    // one guard digit decides the rounding, then carry propagates
    fr = fr * 10.0;
    i32 guard = cast(i32, fr);
    if guard >= 5 {
        i32 i = prec - 1;
        bool carry = true;
        while i >= 0 && carry {
            if fd[i] == 9 { fd[i] = 0; } else { fd[i] = cast(u8, fd[i] + 1); carry = false; }
            i = i - 1;
        }
        if carry { ip = ip + 1; }
    }
    i32 n = _vp_digits(out, ip, 10, false);
    if prec > 0 {
        *(out + n) = 46;
        n = n + 1;
        for i32 i = 0; i < prec; i = i + 1 { *(out + n + i) = cast(u8, 48 + fd[i]); }
        n = n + prec;
    } else if alt {
        *(out + n) = 46;
        n = n + 1;
    }
    return n;
}

// %e body for a non-negative finite v. prec >= 0.
i32 __vf_sci(u8* out, f64 v, i32 prec, bool upper, bool alt) {
    if prec > 30 { prec = 30; }
    f64 m = 0.0;
    i32 e = 0;
    if v != 0.0 { e = __vf_norm(&m, v); } else { m = 0.0; }
    // digits of the mantissa, with a guard digit for rounding
    noinit u8[40] md;
    for i32 i = 0; i <= prec; i = i + 1 {
        i32 d = cast(i32, m);
        if d > 9 { d = 9; }
        if d < 0 { d = 0; }
        md[i] = cast(u8, d);
        m = (m - cast(f64, d)) * 10.0;
    }
    if cast(i32, m) >= 5 {
        i32 i = prec;
        bool carry = true;
        while i >= 0 && carry {
            if md[i] == 9 { md[i] = 0; } else { md[i] = cast(u8, md[i] + 1); carry = false; }
            i = i - 1;
        }
        // 9.99 -> 10.0: shift right and bump the exponent
        if carry {
            for i32 k = prec; k > 0; k = k - 1 { md[k] = md[k - 1]; }
            md[0] = 1;
            e = e + 1;
        }
    }
    i32 n = 0;
    *(out + n) = cast(u8, 48 + md[0]); n = n + 1;
    if prec > 0 || alt { *(out + n) = 46; n = n + 1; }
    for i32 i = 0; i < prec; i = i + 1 { *(out + n + i) = cast(u8, 48 + md[i + 1]); }
    n = n + prec;
    *(out + n) = cast(u8, upper ? 69 : 101); n = n + 1;
    if e < 0 { *(out + n) = 45; e = 0 - e; } else { *(out + n) = 43; }
    n = n + 1;
    // C mandates at least two exponent digits
    if e < 10 { *(out + n) = 48; n = n + 1; }
    n = n + _vp_digits(out + n, cast(u64, e), 10, false);
    return n;
}

// %g body: %e when the exponent is far from 1, %f otherwise, with
// trailing zeros trimmed unless '#'.
i32 __vf_gen(u8* out, f64 v, i32 prec, bool upper, bool alt) {
    i32 p = prec;
    if p < 0 { p = 6; }
    if p == 0 { p = 1; }
    i32 e = 0;
    if v != 0.0 { f64 m = 0.0; e = __vf_norm(&m, v); }
    i32 n = 0;
    bool sci = e < (0 - 4) || e >= p;
    if sci { n = __vf_sci(out, v, p - 1, upper, alt); }
    else { n = __vf_fixed(out, v, p - 1 - e, alt); }
    if alt { return n; }
    // trim trailing zeros in the fractional part (before any exponent)
    i32 stop = n;
    if sci {
        stop = 0;
        while stop < n && *(out + stop) != 101 && *(out + stop) != 69 { stop = stop + 1; }
    }
    bool hasdot = false;
    for i32 i = 0; i < stop; i = i + 1 { if *(out + i) == 46 { hasdot = true; } }
    if !hasdot { return n; }
    i32 end = stop;
    while end > 0 && *(out + end - 1) == 48 { end = end - 1; }
    if end > 0 && *(out + end - 1) == 46 { end = end - 1; }
    if end == stop { return n; }
    // close the gap over the trimmed run
    i32 tail = n - stop;
    for i32 i = 0; i < tail; i = i + 1 { *(out + end + i) = *(out + stop + i); }
    return end + tail;
}

i32 _vp_str_prec(u8* buf, u64 cap, i32 pos, u8* s, i32 prec) {
    if s == null { s = "(null)"; }
    i32 i = 0;
    while *(s + i) != 0 {
        if prec >= 0 && i >= prec { break; }
        pos = _vp(buf, cap, pos, *(s + i));
        i = i + 1;
    }
    return pos;
}

i32 __minc_vfmt(u8* buf, u64 cap, u8* fmt, &... ap) {
    i32 pos = 0;
    i32 i = 0;
    noinit u8[64] body;
    noinit u8[4] lead;
    while *(fmt + i) != 0 {
        u8 c = *(fmt + i);
        if c != 37 { pos = _vp(buf, cap, pos, c); i = i + 1; continue; }
        i = i + 1;
        // --- flags
        bool zero = false;
        bool left = false;
        bool plus = false;
        bool space = false;
        bool alt = false;
        while true {
            u8 f = *(fmt + i);
            if f == 48 { zero = true; }
            else if f == 45 { left = true; }
            else if f == 43 { plus = true; }
            else if f == 32 { space = true; }
            else if f == 35 { alt = true; }
            else { break; }
            i = i + 1;
        }
        // --- width (incl. `*`)
        i32 width = 0;
        if *(fmt + i) == 42 {
            width = arg_read_i32(ap);
            if width < 0 { left = true; width = 0 - width; }
            i = i + 1;
        } else {
            while *(fmt + i) >= 48 && *(fmt + i) <= 57 {
                width = width * 10 + cast(i32, *(fmt + i) - 48);
                i = i + 1;
            }
        }
        // --- precision (incl. `*`)
        i32 prec = 0 - 1;
        if *(fmt + i) == 46 {
            i = i + 1;
            if *(fmt + i) == 42 { prec = arg_read_i32(ap); i = i + 1; }
            else {
                prec = 0;
                while *(fmt + i) >= 48 && *(fmt + i) <= 57 {
                    prec = prec * 10 + cast(i32, *(fmt + i) - 48);
                    i = i + 1;
                }
            }
            if prec < 0 { prec = 0 - 1; }
        }
        // --- length modifiers
        bool islong = false;
        bool isshort = false;
        while true {
            u8 L = *(fmt + i);
            if L == 108 || L == 122 || L == 106 || L == 116 { islong = true; }
            else if L == 104 { isshort = true; }
            else { break; }
            i = i + 1;
        }
        ignore isshort;
        u8 conv = *(fmt + i);
        i = i + 1;
        if left { zero = false; }
        i32 llen = 0;
        i32 blen = 0;

        if conv == 100 || conv == 105 {
            i64 sv = islong ? arg_read_i64(ap) : cast(i64, arg_read_i32(ap));
            u64 mag = 0;
            if sv < 0 { lead[0] = 45; llen = 1; mag = cast(u64, 0 - sv); }
            else {
                mag = cast(u64, sv);
                if plus { lead[0] = 43; llen = 1; }
                else if space { lead[0] = 32; llen = 1; }
            }
            blen = _vp_digits(cast(u8*, &body), mag, 10, false);
        } else if conv == 117 || conv == 111 || conv == 120 || conv == 88 {
            u64 uv = islong ? cast(u64, arg_read_i64(ap))
                            : cast(u64, cast(u32, arg_read_i32(ap)));
            i32 base = 10;
            if conv == 111 { base = 8; }
            else if conv == 120 || conv == 88 { base = 16; }
            if alt && base == 16 && uv != 0 {
                lead[0] = 48; lead[1] = cast(u8, conv == 88 ? 88 : 120); llen = 2;
            }
            blen = _vp_digits(cast(u8*, &body), uv, base, conv == 88);
            // '#' on octal forces a leading zero (C says: raise the
            // precision so the first digit is a 0)
            if alt && base == 8 && body[0] != 48 {
                for i32 k = blen; k > 0; k = k - 1 { body[k] = body[k - 1]; }
                body[0] = 48;
                blen = blen + 1;
            }
        } else if conv == 102 || conv == 70 || conv == 101 || conv == 69
                  || conv == 103 || conv == 71 {
            f64 fv = arg_read_f64(ap);
            bool upper = conv == 70 || conv == 69 || conv == 71;
            bool neg = fv < 0.0 || (fv == 0.0 && 1.0 / fv < 0.0);
            if neg { lead[0] = 45; llen = 1; fv = 0.0 - fv; }
            else if plus { lead[0] = 43; llen = 1; }
            else if space { lead[0] = 32; llen = 1; }
            blen = __vf_special(cast(u8*, &body), fv, upper);
            if blen > 0 {
                zero = false;      // never zero-pad nan/inf
            } else if conv == 103 || conv == 71 {
                blen = __vf_gen(cast(u8*, &body), fv, prec, upper, alt);
            } else if conv == 101 || conv == 69 {
                blen = __vf_sci(cast(u8*, &body), fv, prec < 0 ? 6 : prec, upper, alt);
            } else if fv >= 9.2e18 {
                // beyond u64: the fixed path cannot hold the integer
                // part, so render in scientific form rather than wrap
                blen = __vf_sci(cast(u8*, &body), fv, prec < 0 ? 6 : prec, upper, alt);
            } else {
                blen = __vf_fixed(cast(u8*, &body), fv, prec < 0 ? 6 : prec, alt);
            }
        } else if conv == 115 {
            u8* s = arg_read_ptr(ap);
            if s == null { s = "(null)"; }
            i32 slen = 0;
            while *(s + slen) != 0 {
                if prec >= 0 && slen >= prec { break; }
                slen = slen + 1;
            }
            i32 pad = width - slen;
            if pad < 0 { pad = 0; }
            if !left { pos = _vp_fill(buf, cap, pos, 32, pad); }
            pos = _vp_run(buf, cap, pos, s, slen);
            if left { pos = _vp_fill(buf, cap, pos, 32, pad); }
            continue;
        } else if conv == 99 {
            body[0] = cast(u8, arg_read_i32(ap));
            blen = 1;
        } else if conv == 112 {
            lead[0] = 48; lead[1] = 120; llen = 2;
            blen = _vp_digits(cast(u8*, &body), cast(u64, arg_read_ptr(ap)), 16, false);
        } else if conv == 37 {
            body[0] = 37;
            blen = 1;
        } else {
            // unsupported conversion: echo it so the miss is visible
            pos = _vp(buf, cap, pos, 37);
            pos = _vp(buf, cap, pos, conv);
            continue;
        }
        // integer precision is a minimum digit count, not a width
        if prec >= 0 && (conv == 100 || conv == 105 || conv == 117
                         || conv == 111 || conv == 120 || conv == 88) {
            zero = false;
            i32 need = prec - blen;
            if need > 0 {
                for i32 k = blen - 1; k >= 0; k = k - 1 { body[k + need] = body[k]; }
                for i32 k = 0; k < need; k = k + 1 { body[k] = 48; }
                blen = blen + need;
            }
        }
        pos = _vp_field(buf, cap, pos, cast(u8*, &lead), llen,
                        cast(u8*, &body), blen, width, zero, left);
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
// printf / sprintf / fprintf idenctial for all targets.
// (legacy msvcrt prints three exponent digits, `1.0e+003`, where C99,
// glibc and the UCRT print two).
//
// sscanf is a subset (no %x, no multi-char scansets) for wasm.

// unbounded
i32 sprintf(u8* buf, u8* fmt, ...) { return __minc_vfmt(buf, cast(u64, 2147483647), fmt, &...); }

private void __vf_emit(u8* line, i32 n, bool to_stderr) {
    str s;
    s.data = line;
    s.len = n;
    if to_stderr { eprint("{}", s); } else { print("{}", s); }
}

i32 printf(u8* fmt, ...) {
    noinit u8[1024] line;
    i32 n = __minc_vfmt(cast(u8*, &line), 1024, fmt, &...);
    if n < 1024 { __vf_emit(cast(u8*, &line), n, false); return n; }
    u8* big = cast(u8*, alloc(cast(i64, n) + 1));
    ignore __minc_vfmt(big, cast(u64, n) + 1, fmt, &...);
    __vf_emit(big, n, false);
    free(big);
    return n;
}
when !os(wasm) {
    i32 fprintf(void* stream, u8* fmt, ...) {
        noinit u8[1024] line;
        i32 n = __minc_vfmt(cast(u8*, &line), 1024, fmt, &...);
        if n < 1024 {
            ignore fwrite(cast(void*, &line), 1, cast(u64, n), stream);
            return n;
        }
        u8* big = cast(u8*, alloc(cast(i64, n) + 1));
        ignore __minc_vfmt(big, cast(u64, n) + 1, fmt, &...);
        ignore fwrite(cast(void*, big), 1, cast(u64, n), stream);
        free(big);
        return n;
    }
}

when os(wasm) {
    // no real files on wasm; the host gets the line on stderr
    i32 fprintf(void* stream, u8* fmt, ...) {
        ignore stream;
        noinit u8[1024] line;
        i32 n = __minc_vfmt(cast(u8*, &line), 1024, fmt, &...);
        __vf_emit(cast(u8*, &line), n, true);
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
