// linear.mc — Vector and matrix math using float2/3/4 and float4x4 types

// Requires: math.mc (sinf, cosf, sqrtf)
#include "math.mc"

// --- Vector operations ---

// Overloaded vector functions: dot, length, normalize for float2/3/4

f32 dot(float2 a, float2 b) { return a.x * b.x + a.y * b.y; }
f32 dot(float3 a, float3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
// f32 dot(float4, float4) is a compiler builtin.

float3 cross(float3 a, float3 b) {
    return float3{
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    };
}

// float4 cross(float4, float4) is a compiler builtin.

f32 length(float2 v) { return sqrtf(v.x * v.x + v.y * v.y); }
f32 length(float3 v) { return sqrtf(v.x * v.x + v.y * v.y + v.z * v.z); }

// dot(float4, float4) is a compiler builtin with SIMD support.
f32 length(float4 v) { return sqrtf(dot(v, v)); }

float2 normalize(float2 v) {
    f32 len = length(v);
    if len > 0.0f { f32 inv = 1.0f / len; return float2{ v.x * inv, v.y * inv }; }
    return v;
}

float3 normalize(float3 v) {
    f32 len = length(v);
    if len > 0.0f { f32 inv = 1.0f / len; return float3{ v.x * inv, v.y * inv, v.z * inv }; }
    return v;
}

// float4 normalize(float4 v) is a compiler builtin.


// --- Matrix operations (float4x4, column-major) ---

float4x4 identity() {
    float4x4 m;
    f32* p = cast(f32*, &m);
    *(p + 0) = 1.0f;  *(p + 5) = 1.0f;  *(p + 10) = 1.0f;  *(p + 15) = 1.0f;
    return m;
}

// mul(a, b) with float4x4 and/or float4 args is handled as a compiler
// builtin, it rewrites to `a * b` and produces identical binaries.

float4x4 perspective(f32 fovy, f32 aspect, f32 near, f32 far) {
    float4x4 out;
    f32* p = cast(f32*, &out);
    f32 f = cosf(fovy * 0.5f) / sinf(fovy * 0.5f);
    *(p + 0) = f / aspect;
    *(p + 5) = f;
    when os(windows) || os(macos) || os(ios) {
        // D3D/Metal clip space: z ∈ [0, 1]
        *(p + 10) = far / (near - far);
        *(p + 14) = near * far / (near - far);
    }
    when os(linux) || os(wasm) || os(android) {
        // OpenGL/GLES clip space: z ∈ [-1, 1]
        *(p + 10) = (far + near) / (near - far);
        *(p + 14) = 2.0f * near * far / (near - far);
    }
    *(p + 11) = -1.0f;
    return out;
}

float4x4 look_at(float3 eye, float3 target, float3 up) {
    float3 f = normalize(target - eye);
    float3 s = normalize(cross(f, up));
    float3 u = cross(s, f);

    float4x4 out;
    f32* p = cast(f32*, &out);
    *(p + 0)  = s.x;  *(p + 1)  = u.x;  *(p + 2)  = -f.x;
    *(p + 4)  = s.y;  *(p + 5)  = u.y;  *(p + 6)  = -f.y;
    *(p + 8)  = s.z;  *(p + 9)  = u.z;  *(p + 10) = -f.z;
    *(p + 12) = -dot(s, eye);
    *(p + 13) = -dot(u, eye);
    *(p + 14) = dot(f, eye);
    *(p + 15) = 1.0f;
    return out;
}

// Rotation matrices: right-handed, matches GLM convention
float4x4 rotate_x(f32 angle) {
    float4x4 out = identity();
    f32* p = cast(f32*, &out);
    f32 c = cosf(angle); f32 s = sinf(angle);
    *(p + 5) = c;  *(p + 6) = s;
    *(p + 9) = -s; *(p + 10) = c;
    return out;
}

float4x4 rotate_y(f32 angle) {
    float4x4 out = identity();
    f32* p = cast(f32*, &out);
    f32 c = cosf(angle); f32 s = sinf(angle);
    *(p + 0) = c;   *(p + 2) = -s;
    *(p + 8) = s;   *(p + 10) = c;
    return out;
}

float4x4 rotate_z(f32 angle) {
    float4x4 out = identity();
    f32* p = cast(f32*, &out);
    f32 c = cosf(angle); f32 s = sinf(angle);
    *(p + 0) = c;  *(p + 1) = s;
    *(p + 4) = -s; *(p + 5) = c;
    return out;
}


// --- Quaternion operations (float4: x, y, z, w) ---

float4 quat_identity() { return float4{0.0f, 0.0f, 0.0f, 1.0f}; }

float4 quat_axis_angle(float3 axis, f32 angle) {
    f32 half = angle * 0.5f;
    f32 s = sinf(half);
    float3 n = normalize(axis);
    return float4{ n.x * s, n.y * s, n.z * s, cosf(half) };
}

float4 quat_mul(float4 a, float4 b) {
    return float4{
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
    };
}

float3 quat_rotate(float4 q, float3 v) {
    // v' = q * (0,v) * q^-1  (for unit quaternions, q^-1 = conjugate)
    float3 u = float3{q.x, q.y, q.z};
    f32 s = q.w;
    // Optimized: v' = 2*dot(u,v)*u + (s*s - dot(u,u))*v + 2*s*cross(u,v)
    f32 d = dot(u, v);
    f32 uu = dot(u, u);
    float3 c = cross(u, v);
    f32 s2 = s * s;
    return float3{
        2.0f * d * u.x + (s2 - uu) * v.x + 2.0f * s * c.x,
        2.0f * d * u.y + (s2 - uu) * v.y + 2.0f * s * c.y,
        2.0f * d * u.z + (s2 - uu) * v.z + 2.0f * s * c.z
    };
}

float4x4 quat_to_mat4(float4 q) {
    f32 x = q.x; f32 y = q.y; f32 z = q.z; f32 w = q.w;
    f32 x2 = x + x;  f32 y2 = y + y;  f32 z2 = z + z;
    f32 xx = x * x2; f32 xy = x * y2; f32 xz = x * z2;
    f32 yy = y * y2; f32 yz = y * z2; f32 zz = z * z2;
    f32 wx = w * x2; f32 wy = w * y2; f32 wz = w * z2;

    // Literal order is column-fill: each source row below is one column.
    return float4x4{
        1.0f - (yy + zz), xy + wz         , xz - wy         , 0.0f,
        xy - wz         , 1.0f - (xx + zz), yz + wx         , 0.0f,
        xz + wy         , yz - wx         , 1.0f - (xx + yy), 0.0f,
        0.0f            , 0.0f            , 0.0f            , 1.0f
    };
}

float4 quat_slerp(float4 a, float4 b, f32 t) {
    f32 bx = b.x; f32 by = b.y; f32 bz = b.z; f32 bw = b.w;
    f32 d = a.x * bx + a.y * by + a.z * bz + a.w * bw;
    // If dot is negative, negate b to take the short path
    if d < 0.0f {
        bx = 0.0f - bx; by = 0.0f - by; bz = 0.0f - bz; bw = 0.0f - bw;
        d = 0.0f - d;
    }
    if d > 1.0f { d = 1.0f; }
    // If very close, use linear interpolation
    if d > 0.9995f {
        return normalize(float4{
            a.x + t * (bx - a.x),
            a.y + t * (by - a.y),
            a.z + t * (bz - a.z),
            a.w + t * (bw - a.w)
        });
    }
    f32 theta = cast(f32, acos(cast(f64, d)));
    f32 sin_theta = sinf(theta);
    f32 wa = sinf((1.0f - t) * theta) / sin_theta;
    f32 wb = sinf(t * theta) / sin_theta;
    return float4{
        wa * a.x + wb * bx,
        wa * a.y + wb * by,
        wa * a.z + wb * bz,
        wa * a.w + wb * bw
    };
}
