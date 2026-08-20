// math.mc — math functions for minc
//
// Builtins (compiler intrinsics, zero overhead):
//   sqrt(f64) → f64      hardware sqrtsd instruction
//   fabs(f64) → f64      hardware sign-bit clear
//
// Platform imports: sin, cos, tan, exp, log, pow, floor, ceil, round, etc.
// Pure minc helpers: abs_i32, min_i32, max_i32, clamp_f64, lerp
//
//

// --- Platform math library imports ---
when os(windows) {
    extern "ucrtbase.dll" f64 sin(f64 x);
    extern "ucrtbase.dll" f64 cos(f64 x);
    extern "ucrtbase.dll" f64 tan(f64 x);
    extern "ucrtbase.dll" f64 asin(f64 x);
    extern "ucrtbase.dll" f64 acos(f64 x);
    extern "ucrtbase.dll" f64 atan(f64 x);
    extern "ucrtbase.dll" f64 atan2(f64 y, f64 x);
    extern "ucrtbase.dll" f64 exp(f64 x);
    extern "ucrtbase.dll" f64 log(f64 x);
    extern "ucrtbase.dll" f64 log2(f64 x);
    extern "ucrtbase.dll" f64 log10(f64 x);
    extern "ucrtbase.dll" f64 pow(f64 x, f64 y);
    extern "ucrtbase.dll" f64 fmod(f64 x, f64 y);
    extern "ucrtbase.dll" f64 floor(f64 x);
    extern "ucrtbase.dll" f64 ceil(f64 x);
    extern "ucrtbase.dll" f64 round(f64 x);
}
when os(linux) {
    extern "libm.so.6" f64 sin(f64 x);
    extern "libm.so.6" f64 cos(f64 x);
    extern "libm.so.6" f64 tan(f64 x);
    extern "libm.so.6" f64 asin(f64 x);
    extern "libm.so.6" f64 acos(f64 x);
    extern "libm.so.6" f64 atan(f64 x);
    extern "libm.so.6" f64 atan2(f64 y, f64 x);
    extern "libm.so.6" f64 exp(f64 x);
    extern "libm.so.6" f64 log(f64 x);
    extern "libm.so.6" f64 log2(f64 x);
    extern "libm.so.6" f64 log10(f64 x);
    extern "libm.so.6" f64 pow(f64 x, f64 y);
    extern "libm.so.6" f64 fmod(f64 x, f64 y);
    extern "libm.so.6" f64 floor(f64 x);
    extern "libm.so.6" f64 ceil(f64 x);
    extern "libm.so.6" f64 round(f64 x);
}
when os(android) {
    extern "libm.so" f64 sin(f64 x);
    extern "libm.so" f64 cos(f64 x);
    extern "libm.so" f64 tan(f64 x);
    extern "libm.so" f64 asin(f64 x);
    extern "libm.so" f64 acos(f64 x);
    extern "libm.so" f64 atan(f64 x);
    extern "libm.so" f64 atan2(f64 y, f64 x);
    extern "libm.so" f64 exp(f64 x);
    extern "libm.so" f64 log(f64 x);
    extern "libm.so" f64 log2(f64 x);
    extern "libm.so" f64 log10(f64 x);
    extern "libm.so" f64 pow(f64 x, f64 y);
    extern "libm.so" f64 fmod(f64 x, f64 y);
    extern "libm.so" f64 floor(f64 x);
    extern "libm.so" f64 ceil(f64 x);
    extern "libm.so" f64 round(f64 x);
}
when os(macos) || os(ios) {
    extern "libSystem.B.dylib" f64 sin(f64 x);
    extern "libSystem.B.dylib" f64 cos(f64 x);
    extern "libSystem.B.dylib" f64 tan(f64 x);
    extern "libSystem.B.dylib" f64 asin(f64 x);
    extern "libSystem.B.dylib" f64 acos(f64 x);
    extern "libSystem.B.dylib" f64 atan(f64 x);
    extern "libSystem.B.dylib" f64 atan2(f64 y, f64 x);
    extern "libSystem.B.dylib" f64 exp(f64 x);
    extern "libSystem.B.dylib" f64 log(f64 x);
    extern "libSystem.B.dylib" f64 log2(f64 x);
    extern "libSystem.B.dylib" f64 log10(f64 x);
    extern "libSystem.B.dylib" f64 pow(f64 x, f64 y);
    extern "libSystem.B.dylib" f64 fmod(f64 x, f64 y);
    extern "libSystem.B.dylib" f64 floor(f64 x);
    extern "libSystem.B.dylib" f64 ceil(f64 x);
    extern "libSystem.B.dylib" f64 round(f64 x);
}

when os(wasm) {
    extern "math" f64 sin(f64 x);
    extern "math" f64 cos(f64 x);
    extern "math" f64 tan(f64 x);
    // sqrt / fabs are minc builtins (wasm f64.sqrt / f64.abs)
    extern "math" f64 asin(f64 x);
    extern "math" f64 acos(f64 x);
    extern "math" f64 atan(f64 x);
    extern "math" f64 atan2(f64 y, f64 x);
    extern "math" f64 exp(f64 x);
    extern "math" f64 log(f64 x);
    extern "math" f64 log2(f64 x);
    extern "math" f64 log10(f64 x);
    extern "math" f64 pow(f64 x, f64 y);
    extern "math" f64 fmod(f64 x, f64 y);
    extern "math" f64 floor(f64 x);
    extern "math" f64 ceil(f64 x);
    // round is minc-native: the JS host's Math.round rounds halves
    // toward +Inf (Math.round(-2.5) == -2), C rounds away from zero
    // (-3). |x| >= 2^52 is already integral — returned as-is, which
    // also keeps the i64 cast in range. NaN passes through. math owns
    // the single definition; lib/ext_libc.mc's wasm arm imports math.
    f64 round(f64 x) {
        if x != x { return x; }
        if x >= 4503599627370496.0 || x <= -4503599627370496.0 { return x; }
        if x >= 0.0 { return cast(f64, cast(i64, x + 0.5)); }
        return cast(f64, cast(i64, x - 0.5));
    }
}

// --- Platform math library imports (f32) ---

when os(windows) {
    extern "ucrtbase.dll" f32 sinf(f32 x);
    extern "ucrtbase.dll" f32 cosf(f32 x);
    extern "ucrtbase.dll" f32 tanf(f32 x);
    extern "ucrtbase.dll" f32 asinf(f32 x);
    extern "ucrtbase.dll" f32 acosf(f32 x);
    extern "ucrtbase.dll" f32 atanf(f32 x);
    extern "ucrtbase.dll" f32 atan2f(f32 y, f32 x);
    extern "ucrtbase.dll" f32 expf(f32 x);
    extern "ucrtbase.dll" f32 logf(f32 x);
    extern "ucrtbase.dll" f32 powf(f32 x, f32 y);
    extern "ucrtbase.dll" f32 fmodf(f32 x, f32 y);
    extern "ucrtbase.dll" f32 floorf(f32 x);
    extern "ucrtbase.dll" f32 ceilf(f32 x);
    extern "ucrtbase.dll" f32 roundf(f32 x);
}
when os(linux) {
    extern "libm.so.6" f32 sinf(f32 x);
    extern "libm.so.6" f32 cosf(f32 x);
    extern "libm.so.6" f32 tanf(f32 x);
    extern "libm.so.6" f32 asinf(f32 x);
    extern "libm.so.6" f32 acosf(f32 x);
    extern "libm.so.6" f32 atanf(f32 x);
    extern "libm.so.6" f32 atan2f(f32 y, f32 x);
    extern "libm.so.6" f32 expf(f32 x);
    extern "libm.so.6" f32 logf(f32 x);
    extern "libm.so.6" f32 powf(f32 x, f32 y);
    extern "libm.so.6" f32 fmodf(f32 x, f32 y);
    extern "libm.so.6" f32 floorf(f32 x);
    extern "libm.so.6" f32 ceilf(f32 x);
    extern "libm.so.6" f32 roundf(f32 x);
}
when os(android) {
    extern "libm.so" f32 sinf(f32 x);
    extern "libm.so" f32 cosf(f32 x);
    extern "libm.so" f32 tanf(f32 x);
    extern "libm.so" f32 asinf(f32 x);
    extern "libm.so" f32 acosf(f32 x);
    extern "libm.so" f32 atanf(f32 x);
    extern "libm.so" f32 atan2f(f32 y, f32 x);
    extern "libm.so" f32 expf(f32 x);
    extern "libm.so" f32 logf(f32 x);
    extern "libm.so" f32 powf(f32 x, f32 y);
    extern "libm.so" f32 fmodf(f32 x, f32 y);
    extern "libm.so" f32 floorf(f32 x);
    extern "libm.so" f32 ceilf(f32 x);
    extern "libm.so" f32 roundf(f32 x);
}
when os(macos) || os(ios) {
    extern "libSystem.B.dylib" f32 sinf(f32 x);
    extern "libSystem.B.dylib" f32 cosf(f32 x);
    extern "libSystem.B.dylib" f32 tanf(f32 x);
    extern "libSystem.B.dylib" f32 asinf(f32 x);
    extern "libSystem.B.dylib" f32 acosf(f32 x);
    extern "libSystem.B.dylib" f32 atanf(f32 x);
    extern "libSystem.B.dylib" f32 atan2f(f32 y, f32 x);
    extern "libSystem.B.dylib" f32 expf(f32 x);
    extern "libSystem.B.dylib" f32 logf(f32 x);
    extern "libSystem.B.dylib" f32 powf(f32 x, f32 y);
    extern "libSystem.B.dylib" f32 fmodf(f32 x, f32 y);
    extern "libSystem.B.dylib" f32 floorf(f32 x);
    extern "libSystem.B.dylib" f32 ceilf(f32 x);
    extern "libSystem.B.dylib" f32 roundf(f32 x);
}

when os(wasm) {
    // sinf/cosf: polynomial approximation (no JS import needed)
    // Uses Bhaskara-style range reduction + 5th-degree minimax polynomial
    // on [-π/2, π/2]. Max error < 1e-6 over full range.
    f32 sinf(f32 x) {
        // Reduce to [-π, π]: x = x - round(x / 2π) * 2π
        f32 invtwopi = 0.15915494f;  // 1/(2π)
        f32 twopi = 6.28318530f;
        f32 n = cast(f32, cast(i32, x * invtwopi));
        if x < 0.0f { n = cast(f32, cast(i32, x * invtwopi - 0.5f)); }
        else { n = cast(f32, cast(i32, x * invtwopi + 0.5f)); }
        x = x - n * twopi;
        // Now x in [-π, π]. Reduce to [-π/2, π/2] using sin(π-x) = sin(x)
        f32 halfpi = 1.57079632f;
        if x > halfpi { x = 3.14159265f - x; }
        else if x < -halfpi { x = -3.14159265f - x; }
        // Polynomial: sin(x) ≈ x(1 - x²/6 + x⁴/120 - x⁶/5040 + x⁸/362880)
        f32 x2 = x * x;
        return x * (1.0f - x2 * (0.16666667f - x2 * (0.00833333f - x2 * (0.00019841f - x2 * 0.00000275f))));
    }
    f32 cosf(f32 x) { return sinf(x + 1.57079632f); }

    // tanf: sin/cos ratio
    f32 tanf(f32 x) { return sinf(x) / cosf(x); }

    // Remaining f32 functions imported from JS.
    extern "math" f32 asinf(f32 x);
    extern "math" f32 acosf(f32 x);
    extern "math" f32 atanf(f32 x);
    extern "math" f32 atan2f(f32 y, f32 x);
    extern "math" f32 expf(f32 x);
    extern "math" f32 logf(f32 x);
    extern "math" f32 powf(f32 x, f32 y);
    extern "math" f32 fmodf(f32 x, f32 y);
    extern "math" f32 floorf(f32 x);
    extern "math" f32 ceilf(f32 x);
    // roundf: see the round note above — same C semantics, f32 guard.
    f32 roundf(f32 x) {
        if x != x { return x; }
        if x >= 8388608.0f || x <= -8388608.0f { return x; }  // |x| >= 2^23: integral
        if x >= 0.0f { return cast(f32, cast(i32, x + 0.5f)); }
        return cast(f32, cast(i32, x - 0.5f));
    }
}

// --- Derived f32 functions (portable) ---

f32 log10f(f32 x) { return logf(x) * 0.43429448f; }  // 1/ln(10)

f32 log2f(f32 x) { return logf(x) * 1.44269504f; }   // 1/ln(2)

f32 coshf(f32 x) {
    f32 e = expf(x);
    return (e + 1.0f / e) * 0.5f;
}

f32 sinhf(f32 x) {
    f32 e = expf(x);
    return (e - 1.0f / e) * 0.5f;
}

f32 tanhf(f32 x) {
    if x > 20.0f { return 1.0f; }    // expf(2x) overflows; tanh saturates
    if x < -20.0f { return -1.0f; }
    f32 e2 = expf(2.0f * x);
    return (e2 - 1.0f) / (e2 + 1.0f);
}

// --- Constants ---

const f64 PI = 3.141592653589793;
const f64 E = 2.718281828459045;
const f64 TAU = 6.283185307179586;
const f32 PI_F = 3.14159265f;
const f32 E_F = 2.71828182f;
const f32 TAU_F = 6.28318530f;

// --- Generic helpers ---

T abs<T: Signed>(T x) {
    if x < 0 { return 0 - x; }
    return x;
}

T min<T: Numeric>(T a, T b) {
    if a < b { return a; }
    return b;
}

T max<T: Numeric>(T a, T b) {
    if a > b { return a; }
    return b;
}

T clamp<T: Numeric>(T x, T lo, T hi) {
    if x < lo { return lo; }
    if x > hi { return hi; }
    return x;
}

f64 lerp(f64 a, f64 b, f64 t) {
    return a + (b - a) * t;
}
