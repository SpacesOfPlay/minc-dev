# minc Language Reference

minc is a minimal C replacement for building native software. It compiles directly to
native executables for x64 Windows (PE), x64/ARM64 Linux (ELF), ARM64 macOS (Mach-O),
ARM64 iOS, ARM64 Android (.so), and WebAssembly — no assembler, linker, or runtime required.

## Types

### Primitive types

| Type   | Size    | Description              |
|--------|---------|--------------------------|
| `i8`   | 1 byte  | Signed 8-bit integer     |
| `i16`  | 2 bytes | Signed 16-bit integer    |
| `i32`  | 4 bytes | Signed 32-bit integer    |
| `i64`  | 8 bytes | Signed 64-bit integer    |
| `u8`   | 1 byte  | Unsigned 8-bit integer   |
| `u16`  | 2 bytes | Unsigned 16-bit integer  |
| `u32`  | 4 bytes | Unsigned 32-bit integer  |
| `u64`  | 8 bytes | Unsigned 64-bit integer  |
| `f32`  | 4 bytes | 32-bit float (IEEE 754)  |
| `f64`  | 8 bytes | 64-bit double (IEEE 754) |
| `bool` | 1 byte  | Boolean (`true`/`false`) |
| `void` | 0       | No value (return type)   |

### Vector and matrix types

Built-in SIMD-friendly types for graphics and math. All elements are 4 bytes.
float4 and int4/uint4 operations compile to packed 128-bit SIMD instructions.

| Type        | Size     | Description                    |
|-------------|----------|--------------------------------|
| `float2`    | 8 bytes  | 2x f32 vector                  |
| `float3`    | 12 bytes | 3x f32 vector                  |
| `float4`    | 16 bytes | 4x f32 vector (SIMD)           |
| `int2`      | 8 bytes  | 2x i32 vector                  |
| `int3`      | 12 bytes | 3x i32 vector                  |
| `int4`      | 16 bytes | 4x i32 vector (SIMD)           |
| `uint2`     | 8 bytes  | 2x u32 vector                  |
| `uint3`     | 12 bytes | 3x u32 vector                  |
| `uint4`     | 16 bytes | 4x u32 vector (SIMD)           |
| `f64x2`     | 16 bytes | 2x f64 vector (SIMD)           |
| `i64x2`     | 16 bytes | 2x i64 vector (SIMD)           |
| `u64x2`     | 16 bytes | 2x u64 vector (SIMD)           |
| `float4x4`  | 64 bytes | 4x4 f32 matrix (SIMD, column-major) |

```c
float3 pos = float3{1.0f, 2.0f, 3.0f};
float4 color = float4{1.0f, 0.0f, 0.0f, 1.0f};
int4 indices = int4{0, 1, 2, 3};
```

#### Component access

Single components via `.x`, `.y`, `.z`, `.w` (or `.r`, `.g`, `.b`, `.a`):

```c
f32 x = pos.x;              // scalar access
pos.y = 5.0f;               // scalar write
```

#### Swizzle

Multi-component swizzle returns a new vector. Supports `.xyzw` and `.rgba` naming
(no mixing). Reordering and duplication allowed:

```c
float2 xy = pos.xy;         // first two components
float3 bgr = color.bgr;     // reversed color channels
float2 xx = pos.xx;          // duplicated component
float4 rev = color.wzyx;     // full reverse
```

#### Arithmetic

Component-wise `+`, `-`, `*`, `/` and unary `-`. Scalar broadcast supported:

```c
float4 a = float4{1.0f, 2.0f, 3.0f, 4.0f};
float4 b = float4{10.0f, 20.0f, 30.0f, 40.0f};
float4 sum = a + b;          // {11, 22, 33, 44}
float4 scaled = a * 3.0f;    // {3, 6, 9, 12}
float4 neg = -a;             // {-1, -2, -3, -4}
```

`int4`/`uint4` support the integer operators `+ - * & | ^ << >> ~`
and unary `-`, all compiling to packed 128-bit SIMD. The shift
count is a uniform scalar; per-lane vector counts are not allowed.
`<<` is sign-agnostic. `>>` is arithmetic for `int4`, logical for
`uint4`.

```c
int4 v = int4{1, 2, 3, 4};
int4 w = (v & 6) | (v << 2);   // pand / pslld / por
int4 n = ~v;                   // bitwise NOT
```

Integer-vector division is not SIMD. SSE2 and NEON have no packed
integer divide, so `int4 / x` and `uint4 / x` scalarize to one
divide per lane. The result follows scalar integer rules; signed
division truncates toward zero. It is correct but slower than the
other operators. For an unsigned power-of-two divisor use `>>`.


#### SIMD Vectors (f64x2, i64x2, u64x2)

The 2-wide 64-bit SIMD vectors. `f64x2` supports component-wise
`+`, `-`, `*`, `/`, and the same operators against a scalar `f64`
(broadcast, either order). Components are `.x` and `.y`.

`i64x2` / `u64x2` are 2-wide 64-bit integer SIMD vectors. They
support only the operators that map to packed SIMD: `+ - & | ^ ~`
and unary `-` (vector with same-type vector), and `<< >>` by a
uniform scalar count (`>>` is logical for `u64x2`, arithmetic for
`i64x2`). `* / %` are rejected — SSE2/NEON have no 64-bit packed
multiply or divide; scalarize those explicitly. Every permitted op
is a single SIMD instruction per target, except `i64x2 >>`
(arithmetic) which expands to a few vector ops on x64.

```c
i64x2 v = i64x2{5000000000, -3000000000};
i64x2 d = (v + v) - i64x2{1, 1};   // packed 2x64
i64x2 s = v >> 2;                  // arithmetic, sign-preserving
u64x2 m = u64x2{0xFF00, 3} & u64x2{0x0FF0, 1};
```

For more info see [SIMD intrinsics](#simd-intrinsics) in built-in
functions.

### Literals

```c
42                              // integer (coerces to any int type)
0xFF                            // hexadecimal
0b1010                          // binary
1_000_000                       // digit separators
3.14                            // f64 float
3.                              // f64 float (trailing dot, = 3.0)
.5                              // f64 float (leading dot, = 0.5)
0.5f                            // f32 float (suffix)
3.f                             // f32 float (suffix after trailing dot)
2f                              // f32 float (= 2.0f, integer-with-suffix)
1e6                             // f64 scientific (= 1000000.0)
1.5e-3                          // f64 scientific with negative exponent
2.5E+10                         // f64 scientific (uppercase E, explicit '+')
1.5e3f                          // f32 scientific
"hello"                         // string (type str)
'A'                             // ASCII char literal (Unicode codepoint)
'é'                             // UTF-8 char literal (codepoint 0xE9)
'🎉'                            // non-BMP char literal (codepoint 0x1F389)
'\u{1F389}'                     // Unicode escape in char literal
true, false                     // bool
null                            // null pointer
```

#### UTF-8 in source

Source files are byte-transparent UTF-8. Raw multi-byte characters
pass through unchanged in string literals, comments, and character
literals. Identifiers are restricted to ASCII (`[A-Za-z_][A-Za-z_0-9]*`)
— by design.

- String escapes: `\n \t \r \0 \\ \' \" \xNN \u{HEX}` where `\u{HEX}`
  is 1-6 hex digits naming a Unicode codepoint; the string literal
  emits the UTF-8 encoding of that codepoint (1-4 bytes).
  Surrogates (`U+D800`-`U+DFFF`) and codepoints above `U+10FFFF`
  are rejected.
- Char literals carry a Unicode codepoint in an integer-literal
  node, so `u32 c = '🎉';` is a clean assign. Narrowing to a type
  that can't hold the codepoint is a compile error —
  `u8 c = '🎉';` rejects with `character literal value 127881
  does not fit in u8`.
- A UTF-8 BOM (`EF BB BF`) at the start of a source or included
  file is silently skipped. Mid-file BOMs are not skipped.

### Pointers

```c
i32* p = &x;                    // pointer to i32
*p = 42;                        // dereference
p.field                         // auto-dereference (no -> needed)
p + n                           // pointer arithmetic (advances by n * sizeof(*p))
*p++ = expr;                    // write to *p, then p++ (postfix yields old)
*p-- = expr;                    // write to *p, then p-- (postfix yields old)
```

### Arrays

```c
i32[10] arr;                    // fixed-size array
i32[4] arr = {1, 2, 3, 4};      // array with initializer
arr[0]                          // indexing (bounds-checked by default)
```

### Slices

```c
[]i32 s;                        // slice: pointer + length
s.ptr                           // data pointer
s.len                           // element count
s[i]                            // indexed access
s[1..4]                         // subslice [start, end)
```

### Strings

minc has two string types: `str` (borrowed view) and `string` (owned, heap-allocated).

#### str — borrowed view

```c
str s = "hello";                // UTF-8 string view: { u8* data; i32 len }
s.len                           // byte length (5)
s.data                          // raw u8 pointer
```

`str` is a built-in struct `{ u8* data; i32 len }` — a non-owning view (pointer + length).
String literals are type `str`. Not null-terminated by default.

Copying a `str` copies the pointer and length (16 bytes), not the underlying data.
Functions that only read strings should take `str` parameters.

#### string — owned string

```c
string s = string("hello");     // heap-allocates and copies
defer free(s);                  // freed at scope exit
print("{}\n", s);               // implicit string → str conversion
```

`string` has the same layout as `str` (`{ u8* data; i32 len }`) but owns its data.
The compiler tracks ownership and enforces cleanup:

```c
string s = string("hello");
// error: owned string 's' must be freed or moved before scope exit
```

**Ownership rules:**
- `string` locals must be freed or moved before scope exit
- `free(s)` — frees the string's data
- `defer free(s)` — idiomatic cleanup (freed at scope exit, usable until then)
- `move(s)` — transfers ownership, invalidates source
- `return s` — implicit move (transfers to caller)
- `string → str` — implicit conversion (safe borrow for function calls)

```c
// Construction
string s = string("literal");   // from string literal
string s2 = string(some_str);   // from str view (copies)
string s3 = str_concat(a, b);   // functions that allocate return string

// Transfer
string greeting = make_greeting();  // caller owns returned string
widget.name = move(s);              // transfer ownership, s is invalidated

// Compile-time safety
string s = string("hello");
free(s);
print("{}\n", s);               // error: use of freed string

string s = string("hello");
move(s);
print("{}\n", s);               // error: use of moved string
```

#### String utilities (lib/str.mc)

```c
#include "lib/str.mc"

// Concatenation (returns owned string)
string full = str_concat("hello ", "world");
defer free(full);

// String builder
str_buf sb;
str_buf_init(&sb);
str_buf_add(&sb, "hello ");
str_buf_add(&sb, "world");
str result = str_buf_to_str(&sb);   // borrows sb's buffer
// ... use result ...
str_buf_free(&sb);

// String formatting (built-in, returns owned string)
string msg = format("hello {}", name);           // single placeholder
string line = format("{} + {} = {}", a, b, a+b); // multiple
defer free(msg);
defer free(line);

// format() supports any printable type: integers, floats, bools, str, string, pointers.
// Use {} as placeholder — arguments are matched left-to-right.
// The same {} syntax works with print() and eprint() (which write to stdout/stderr):
print("x = {}\n", x);        // prints to stdout
eprint("error: {}\n", msg);  // prints to stderr

// Float formatting note: `{}` for f32/f64 is a *display* format, not a
// round-trip format. It uses up to 6 fractional digits with trailing
// zeros trimmed (keeping at least one digit so float-ness is visible):
//   format("{}", 3.14)  -> "3.14"
//   format("{}", 3.0)   -> "3.0"
//   format("{}", 0.0)   -> "0.0"
//   format("{}", -1.5)  -> "-1.5"
// Special values print as "nan", "inf", "-inf". Magnitudes of 1e12 or
// more print in scientific notation ("1.0e13", "1.0e308"); smaller
// values print as plain decimals.

// For exact, shortest round-trip output, import the Ryu formatters:
//   import format_f64;   string s = format_f64(0.1);  // "0.1"
//   import format_f32;   string s = format_f32(0.1f); // "0.1"
// Each returns the shortest decimal string that parses back to the same
// bits (lib/format_f64.mc uses Ryu64, lib/format_f32.mc native Ryu32).
// f32_to_str / f64_to_str write into a caller buffer instead. Output
// rules match `{}` (decimal for 1e-4 <= |x| < 1e21, scientific outside,
// "0.0" / "nan" / "inf" / "-inf").
// These Ryu implementations are kept external due to their size.


// Conversion
str view = str_from_cstr(c_string);   // u8* → str (no copy)
u8* cstr = str_to_cstr(s);           // str → null-terminated u8* (allocates)
```

## Declarations

### Variables

```c
i32 x = 42;                     // explicit type
var y = 42;                     // type inference, integer literals default to i32 
                                // unless they exceed the i32 range, in which case 
                                // they become i64.
const i32 MAX = 100;            // compile-time constant
i32 g_count = 0;                // global variable
```

### Functions

```c
i32 add(i32 a, i32 b) {
    return a + b;
}

void greet() {
    print("hello\n");
}
```

### Function overloading

Functions with the same name can be overloaded if their parameter types differ.
Resolution is by exact match (no implicit conversions for disambiguation):

```c
f32 dot(float2 a, float2 b) { return a.x * b.x + a.y * b.y; }
f32 dot(float3 a, float3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
f32 dot(float4 a, float4 b) { return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w; }

float3 v = float3{1.0f, 0.0f, 0.0f};
f32 d = dot(v, v);           // calls float3 overload
```

### Structs

```c
struct Point {
    i32 x;
    i32 y;
}

Point p = Point{3, 4};                // positional literal
Point p2 = Point{.y = 10, .x = 5};    // named fields
var (x, y) = make_point(1, 2);        // var destructuring
```

A field that is itself an array or struct takes a nested `{...}`
initializer; the inner brace-init has no type prefix and resolves
against the field type. Nesting is arbitrary (struct in array in
struct …):

```c
struct Row  { i32[3] v; i32 n; }
struct Grid { Row[2] rows; }

Row  r = Row{ {1, 2, 3}, 0 };                         // array field
Grid g = Grid{ {Row{{1,2,3},0}, {{4,5,6},1}} };       // mix of explicit and bare braces
```

Comma-separated field declarations share the parsed type. Mirrors
local + global multi-decl: `i32 a, b, c;` declares three fields all
of type `i32`. Useful for packed records like RGBA color components:

```c
struct InstanceData {
    f32 pos_x, pos_y, pos_z;
    u8 r, g, b, a;
}
```

Structs and arrays are **zero-initialized by default** when declared without an initializer.
Use `noinit` to skip zero-initialization for performance-critical code:

```c
Point p;                              // p.x = 0, p.y = 0 (zero-init)
noinit Point q;                       // uninitialized (faster, use with care)
i32[1024] buf;                        // all zeros
noinit u8[4096] scratch;              // uninitialized buffer
```

Use `unused` to suppress unused-variable warnings (e.g., platform-specific variables):

```c
unused bool has_feature = false;      // no warning if unused on this platform
unused i32 hlsl_flags = 0;            // used on Windows, not Linux
```

Variables prefixed with `_` also suppress the warning: `i32 _reserved = 0;`

### Enums

```c
enum Color { RED, GREEN, BLUE }       // auto-incremented (0, 1, 2)
enum Flags { A = 1, B = 2, C = 4 }    // explicit values

// Values are integer constant expressions: literals (incl. negatives
// and char literals), parens, unary `! ~ -`, and the full C integer
// operator set (`+ - * / % << >> & | ^ == != < <= > >= && ||`).
// Earlier members of the same enum are in scope.
enum Errno {
    OK = 0,
    EBADF = -9,
    EAGAIN = -11,
    LAST = EAGAIN - 1                 // -12; auto-increment continues from here
}
enum Bits {
    MASK = (1 << 8) - 1,              // 255
    HIGH = 1 << 31
}
```

Enum values are `i32` constants.

### Tagged unions

```c
union Option<T> {
    Some(T),
    None,
}

union Result<T, E> {
    Ok(T),
    Err(E),
}

union Token {
    Number(i32),
    Ident(u8*, i32),
    Plus,
    Eof,
}
```

Construction:

```c
Option<i32> x = Some(42);
Option<i32> y = None;
Result<i32, i32> r = Ok(100);
Token t = Number(123);
Token t2 = Plus;
```

Switch with pattern matching (exhaustive — all variants must be covered):

```c
switch x {
    case Some(val): { print("{}\n", val);   }
    case None:      { print("none\n");      }
}
```

**Example: error handling with Result**

```c
union Result<T, E> {
    Ok(T),
    Err(E),
}

Result<i32, str> parse_int(str input) {
    // ... parsing logic ...
    if valid { return Ok(value); }
    return Err("invalid number");
}

i32 main() {
    Result<i32, str> r = parse_int("42");
    switch r {
        case Ok(val): { print("parsed: {}\n", val); }
        case Err(msg): { print("error: {}\n", msg); }
    }
    return 0;
}
```

**Example: a simple token type**

```c
union Token {
    Number(i32),
    Ident(str),
    Plus,
    Eof,
}

str token_name(Token t) {
    switch t {
        case Number(n): { return format("Number({})", n); }
        case Ident(s):  { return format("Ident({})", s); }
        case Plus:      { return "Plus"; }
        case Eof:       { return "Eof"; }
    }
}
```

Unions can be passed to and returned from functions, stored in arrays and structs,
and used with generics. The compiler enforces exhaustive matching — omitting a
variant in `switch` is a compile error.

### Unsafe unions

`unsafe_union` is a C-style `union`. All members share offset 0,
`sizeof` is the largest member, there is no tag and no active-member
tracking. Reading one member after writing another reinterprets the
bytes.

```c
unsafe_union FloatBits { u32 i; f32 f; }

FloatBits b;
b.i = 0x40490FDB;
f32 x = b.f;             // ≈ 3.14159 — bytes reinterpreted as f32

unsafe_union Mix { u8 lo; u32 w; u64 q; }   // sizeof(Mix) == 8
```

Usable as a variable, parameter, return value, struct field, array
element, or behind a pointer, with `.member` access.

Initializer literals use struct-literal syntax. At most one field
may be initialized; the remaining bytes come from the implicit
zero-fill:

```c
unsafe_union FB { u32 u; f32 f; }

const FB almostone = FB{ .u = 0x3f7fffff };   // named (recommended)
FB minval = FB{ (127 - 13) << 23 };           // positional → first field
FB zero = FB{};                               // empty → all-zero storage
FB declared;                                  // implicit zero (no init)
noinit FB raw;                                // skip zero-fill
```

Multi-field initializers like `FB{ .u = 1, .f = 2.0f }` or `FB{ 1, 2.0f }`
are rejected. `noinit FB x = FB{...};` is rejected (same rule as for
other types).

### Anonymous nested struct/union members

A struct member's type can be an inline anonymous `struct { … }` or
`unsafe_union { … }`. Two shapes:

**Named field, anonymous type** — nested-field access via the field
name:

```c
struct Packet {
    i32 header;
    struct { i32 flag; i32 seq; } stuff;
    i32 payload_len;
}
Packet p;
p.stuff.flag = 1;
Packet q = Packet{ .header = 1, .stuff = { .flag = 2, .seq = 3 } };
```

**Transparent (no field name)** — the inner aggregate's fields are
accessible directly on the enclosing type (C11 anonymous-member
form). Combined with `unsafe_union`:

```c
struct Color {
    unsafe_union {
        struct { u8 r; u8 g; u8 b; u8 a; }
        u32 rgba;
    }
}
Color c;
c.r    = 0xff;
c.rgba = 0x01020304;
Color d = Color{ .r = 1, .g = 2, .b = 3, .a = 4 };
Color e = Color{ .rgba = 0xAABBCCDD };
```

`&c.r` and `&c.rgba` address overlapping storage — same rule as
a plain `unsafe_union`.

Rejected at the type's declaration:

- The aggregate must be anonymous — `struct Inner { … } x;` at the
  member position is a stray nested type declaration.
- Only `struct` and `unsafe_union` are allowed as transparent
  members. Tagged `union` requires `match` for access.
- Promoted names may not collide with each other or with the
  parent's direct fields. Rename one side.
- Types with transparent members require named-field initializer
  syntax (`Color{ .r = 1, … }`); positional `Color{ 1, 2, 3, 4 }`
  is rejected — the transparent slot has no unambiguous position.

### Function pointers

```c
fn(i32, i32): i32 op = add;
i32 result = op(3, 4);
```

Function pointers can also be used as struct fields:

```c
struct Handler {
    fn(i32, i32): i32 op;
    i32 id;
}

Handler h;
h.op = &add;
i32 result = h.op(3, 4);  // call through struct field
```

### Type aliases

```c
type Size = i64;
type Byte = u8;
type IntPtr = i32*;
type BinOp = fn(i32, i32): i32;

Size x = 42;               // same as i64 x = 42
BinOp op = &add;           // alias for function pointer type
struct Calc { BinOp f; }   // alias as struct field type
```

Type aliases are defined at file scope. The alias name becomes interchangeable
with the underlying type.

## Statements

### Control flow

```c
if condition { ... }
else if condition { ... }
else { ... }

while condition { ... }

for i32 i = 0; i < 10; i++ { ... }
for ; i < 10; i++ { ... }               // no init (use existing variable)
for i32 i in 0..10 { ... }              // range-based (0 to 9 inclusive)

switch value {
    case 1, 2, 3: { ... }               // multi-value case
    case 4: { ... }
    default: { ... }
}

break;
continue;
return expr;
```

No fall-through in switch. Braces required for all blocks.

### Defer

```c
i64 fd = open("file.txt", 0);
defer close(fd);
// close(fd) executes automatically at block exit, LIFO order
```

Multi-statement cleanup via the block form:

```c
defer {
    close(handle);
    counter = counter - 1;
    log_exit("done");
}
```

Statements inside `defer { ... }` run in source order at scope exit.
The block as a whole follows the same LIFO order as single-statement
`defer`s relative to its siblings.

`return`, `break`, and `continue` are rejected inside `defer { }` —
they would skip later defers. Loops nested inside the deferred body
can still `break` / `continue` against their own loop.

`defer free(x)` ownership tracking applies only to the single-
statement form. `defer { free(a); free(b); }` does not mark `a` or
`b` as defer-freed. Use one `defer free(x);` per resource for the
tracking.

### `@must_use` and `ignore`

`@must_use` on a function declaration emits a warning when the
caller drops its return value:

```c
@must_use
i32 try_parse(u8* s) { ... }

i32 main() {
    try_parse(input);              // warning: result of 'try_parse' is unused
    i32 r = try_parse(input);      // OK — assigned
    if try_parse(input) == 0 { }   // OK — used in a condition
    return try_parse(input);       // OK — returned
    ignore try_parse(input);       // OK — explicitly dropped
}
```

`ignore <expr>;` evaluates the expression for its side effects and
discards the value. It silences `@must_use` at one call site. The
warning is also suppressed inside `defer { ... }` (the deferred call
has no caller to assign to).

`ignore` is unrelated to the fragment-shader `discard;` intrinsic
(which aborts the current fragment); the keywords were chosen so
they don't collide.

### Bare blocks

Bare `{ }` blocks create a new scope. Variables declared inside are not visible
outside, and `defer` statements fire at block exit:

```c
i32 x = 1;
{
    i32 y = 2;
    defer print("leaving\n");
    // y is visible here
}
// y is out of scope; defer has fired
```

### Compile-time conditionals

```c
when os(windows) { ... }
else when os(linux) { ... }
else when os(macos) { ... }
else { ... }

when arch(x64) { ... }
when arch(arm64) { ... }
when arch(wasm32) { ... }
when defined(DEBUG) { ... }

// Combine with || and && and !
when os(linux) || os(macos) { ... }
when os(windows) && arch(x64) { ... }
when !os(wasm) { ... }

// Integer expressions over -D / @define values: a C-#if-style
// grammar — integer literals, config names, the predicates above,
// and  ! ~ - (unary)  then (low→high)  || && | ^ &  == !=  < <= > >=
//  << >>  + -  * / %  with parentheses. Non-zero is truthy.
@define "API_VERSION" 3
@define "MAX_STRIDE" 16
when API_VERSION >= 3 { ... } else { ... }
when defined(USE_SSE) && SSE_LEVEL >= 2 { ... }
when (NCHANNELS * 4) > MAX_STRIDE { ... }
```

`&&` / `||` short-circuit: the dead operand is parsed but not
evaluated, so `when defined(X) && X >= 3` is legal even when `X` is
undefined. A bare config name that was never `@define`d / `-D`'d,
outside a dead branch, is an error — use `defined(NAME)` to test
presence. Unlike C, an undefined identifier is not implicitly zero.
Division / modulo by zero is an error.

`@define "NAME"` with no value is `@define "NAME" 1`. `@define "NAME"
42` sets an integer value (negative and `_`-separated literals
allowed). On the command line, `-DNAME=42` sets a value; `-DNAME`
sets `1`.

Dead branches are skipped at parse time (no runtime overhead).
Available `os` values: `windows`, `linux`, `macos`, `wasm`, `ios`, `android`.
Available `arch` values: `x64`, `arm64`, `wasm32`.

## Expressions

### Operators

| Category   | Operators                                                      |
|------------|----------------------------------------------------------------|
| Arithmetic | `+  -  *  /  %`                                                |
| Inc/Dec    | `++x  x++  --x  x--` (statement + expression position; see below) |
| Comparison | `==  !=  <  >  <=  >=`                                         |
| Logical    | `&&  \|\|  !`                                                  |
| Bitwise    | `&  \|  ^  ~  <<  >>`                                          |
| Assignment | `=  +=  -=  *=  /=  %=  &=  \|=  ^=  <<=  >>=`                 |
| Ternary    | `condition ? true_expr : false_expr`                           |
| Cast       | `cast(Type, expr)`                                             |
| Sizeof     | `sizeof(Type)` or `sizeof(expr)` (returns size in bytes)       |
| Address-of | `&expr`                                                        |
| Deref      | `*expr`                                                        |
| Member     | `expr.field`                                                   |
| Index      | `expr[index]`                                                  |

### Increment / decrement

Prefix and postfix `++` / `--` work in both statement and expression
position. The operand must be an lvalue of integer (non-bool) or
pointer type. Prefix yields the new value; postfix yields the old
value, then increments / decrements.

```c
i32 i = 5;
i32 a = i++;         // a = 5, i = 6  (postfix yields old)
i32 b = --i;         // b = 5, i = 5  (prefix yields new)
array[idx++] = x;    // write to array[idx], then idx++
while --n > 0 { }    // decrement first, then compare
u8 c = *--end;       // step back one byte, read it
```

Pointer increments step by `sizeof(*T)`, so `p++` on an `i32*`
advances by 4 bytes.

The operand may not contain a function call in its address path.
`func()[i]++`, `arr[func()]++`, `obj.field()[i]++` are rejected at
type-check. Split into a separate statement:

```c
i32* t = func();
t[i]++;
```

### Named arguments

```c
add(a: 3, b: 4)               // named
add(b: 4, a: 3)               // reordered
add(3, b: 4)                  // mixed positional + named
```

### Type conversions

Implicit lossless widening: `i8`->`i16`->`i32`->`i64`, `u8`->`u16`->`u32`->`u64`,
`i32`/`u32`->`f64`, `f32`->`f64`. All lossy conversions require explicit `cast()`.

```c
i64 x = 42;                   // i32 -> i64 (implicit)
i32 y = cast(i32, x);         // i64 -> i32 (explicit, narrowing)
f64 f = y;                    // i32 -> f64 (implicit, i32 fits in f64)
i32 n = cast(i32, 3.14);      // f64 -> i32 (explicit, truncates)
```

### Integer promotion

Arithmetic and shift binops (`+ - * / % << >>`) on two
same-signedness narrow operands (`u8`/`u16` or `i8`/`i16`) produce a
`u32` or `i32` result. The result can exceed the operand width, so
it widens. Byte-assembly works without per-byte casts:

```c
u32 v = b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24);
u32 sum = u8_a + u8_b;        // 255 + 16 = 271
u32 r = u8_a * u8_b;          // 16 * 16 = 256
```

Bitwise `& | ^` do not promote. The result keeps the operand width
(`u8 ^ u8` is `u8`, `u16 & u16` is `u16`), since it cannot exceed
that width. No cast is needed:

```c
u8  g  = a ^ b;
gfx[i] = gfx[i] ^ 1;
h      = h ^ byte;
u16 m  = lo & 0x0FFF;
```

Storing a promoted result into a narrower location is narrowing and
requires `cast()`:

```c
u8 bits = 0x80;
bits = bits << 1;             // error: u32 -> u8 needs a cast
bits = cast(u8, bits << 1);   // wraps to 0 at u8 width
```

Compound assignment to a narrow lvalue is exempt. `x += y`,
`bits <<= 1`, and the other `op=` forms compile without a cast even
when the operation promotes; the store wraps the result back to the
lvalue width. Plain `x = x + y` still needs the cast.

```c
u8 bits = 0x80;
bits <<= 1;                   // wraps to 0 at u8 width
```

Promotion stops at 32 bits. `u32 op u32` stays `u32` and wraps at
u32 width. Assigning to a `u64` zero-extends the truncated 32-bit
value, so bits above 32 are lost. Widen before the operation to
keep them:

```c
u64 hi = u32_val << 32;            // 0 — shifted at u32 width
u64 hi = cast(u64, u32_val) << 32; // operates at u64 width
```

The same holds for overflowing addition and multiplication: `u32 a
+ u32 b` is a u32 result. Cast to `u64` first for the wider sum.

### Mixed signed/unsigned

Mixing signed and unsigned integers in comparisons or arithmetic is an error.
All comparisons (`==`, `!=`, `<`, `>`, `<=`, `>=`) and all arithmetic
(`+`, `-`, `*`, `/`, `%`, `>>`) are affected:

```c
i32 a = -1;
u32 b = 100;
if a < b { }                  // ERROR: mixed signed/unsigned comparison
if a == b { }                 // ERROR: mixed signed/unsigned comparison
i32 c = a + b;                // ERROR: mixed signed/unsigned arithmetic
i32 d = a >> b;               // ERROR: >> is sign-sensitive (SAR vs SHR)
i32 e = a >> 5;               // OK:    integer literal coerces to a's type
```

**Exception 1: integer literals and enum members** — these coerce to the target type:

```c
u32 x = 5;
if x == 0 { }                 // OK: literal coerces
if x < SG_INVALID_ID { }      // OK: enum member coerces
```

**Exception 2: same-width bitwise ops (`&`, `|`, `^`, `<<`)** — these produce
the same bit pattern regardless of how either operand is signed, so cross-sign
is allowed when both operands have the same width. The left operand's type
becomes the result type:

```c
u64 state = ...;
i64 seed  = ...;
state = state ^ seed;         // OK: u64 ^ i64 → u64 (bitwise, sign-agnostic)
u32 mask  = ...;
i32 bits  = ...;
u32 out = mask | bits;        // OK: u32 | i32 → u32
u64 shifted = state << seed;  // OK: << is bit-agnostic
```

`>>` is intentionally excluded — it's sign-sensitive (SAR vs SHR are
different instructions with different results for high-bit-set values),
so the LHS must be explicitly cast to the desired signedness.

Use explicit `cast()` to resolve mixed-sign errors:

```c
i32 a = -1;
u32 b = 100;
if cast(u32, a) < b { }       // OK: explicit cast
if a < cast(i32, b) { }       // OK: explicit cast
i32 d = cast(i32, b) >> 4;    // OK: arithmetic shift chosen explicitly
u32 e = b >> cast(u32, a);    // OK: logical shift chosen explicitly
```

### Floating-point semantics

minc applies these floating-point optimizations by default:

- **FMA contraction**: `a * b + c` may be fused into a single fused multiply-add
  instruction (FMA). FMA uses one rounding step instead of two, producing
  results that differ by at most 1 ULP from the unfused form. This is more
  accurate but not IEEE 754 conformant (the standard requires two roundings
  unless `fma()` is used explicitly). Matches MSVC `/fp:fast` default behavior.

- **Float strength reduction**: `x * 2.0` may be replaced with `x + x`.

- **SIMD vectorization**: scalar float loops may be auto-vectorized to packed
  SIMD instructions, which can change the order of floating-point operations.

Programs that depend on exact IEEE 754 two-rounding semantics (e.g., Kahan
compensated summation, Dekker exact multiplication) should be aware of these
transformations. There is no flag to disable FP contraction.

## Generics

Monomorphized generics with `<T>` syntax. Zero runtime overhead — each instantiation
generates specialized code at compile time.

### Generic functions

```c
T identity<T>(T x) { return x; }
void swap<T>(T* a, T* b) { T tmp = *a; *a = *b; *b = tmp; }

// Type inference from arguments
swap(&a, &b);              // infers T from pointer type

// Explicit type argument (turbofish syntax)
identity<i64>(42);         // forces T = i64

// Bidirectional inference from return type
Pair<i32> p = make_default_pair(10);  // infers T = i32 from expected type
```

### Generic structs

```c
struct Pair<T> { T first; T second; }
Pair<i32> p;
Pair<i64> q;

// Multi-parameter
struct Triple<A, B, C> { A x; B y; C z; }

// Nested generics
Pair<Pair<i32>> nested;
```

### Type constraints

Constraints restrict which types can be used with a generic parameter:

```c
T add<T: Numeric>(T a, T b) { return a + b; }
T neg<T: Signed>(T x) { return 0 - x; }
T half<T: Float>(T x) { return x / cast(T, 2); }

struct NumBox<T: Numeric> { T val; }
```

| Constraint | Types                                    |
|------------|------------------------------------------|
| `Numeric`  | `i8, i16, i32, i64, u8, u16, u32, u64, f32, f64` |
| `Integer`  | `i8, i16, i32, i64, u8, u16, u32, u64`  |
| `Signed`   | `i8, i16, i32, i64, f32, f64`            |
| `Unsigned` | `u8, u16, u32, u64`                      |
| `Float`    | `f32, f64`                               |

Calling a constrained function with the wrong type is a compile error:
```c
add<str>("a", "b");  // error: str does not satisfy Numeric
```

## Modules

### Import

```c
// all public symbols directly in scope
import helpers;
import "lib/helpers.mc";

// Selective: only named symbols
import { Vec, vec_push } from "lib/vec.mc";

// Qualified: access via prefix
import math = "lib/math_helper.mc";
math.add(2, 3);
```

### Private

```c
// Single declaration
private i32 helper() { return 42; }

// Block
private {
    i32 internal_a() { ... }
    i32 internal_b() { ... }
}
```

Private declarations are hidden from `import` but still visible via `#include`.

### Export

```c
// Single declaration
export i32 frame_tick(i32 dt_ms) { ... }

// Block
export {
    i32 sokol_main_call() { ... }
    void on_event(i32 ev_ptr) { ... }
}
```

Exported functions are surfaced at the platform module boundary so an
external host can call them — primarily for **WASM**, where each
`export`-marked function appears in the module's `exports` section and
is callable as `instance.exports.frame_tick(...)` from JavaScript. On
native targets (PE / ELF executable / Mach-O) the keyword is currently
a no-op; it parses uniformly so source code stays portable, and once
shared-library output (.so / .dll / .dylib) lands on those targets the
same marker will drive their symbol-table exports.

`main` is auto-exported on WASM regardless. `export` is for *additional*
entry points beyond `main`.

### Include

```c
#include "path/to/file.mc"      // textual inclusion (include-once)
```

`#include` makes all declarations visible, including `private` ones (C-style usage).

#### API Version Tag

Library headers can declare a version, and `#include` can require a specific version.
This catches mismatches when a program is compiled against the wrong version of a library.

```c
// In the library header (lib/vec.mc):
@api-version 3

// In the program that includes it:
#include "lib/vec.mc" @api-version 3
```

If the included file declares a different `@api-version` than required, or has no
`@api-version` at all, the compiler emits an error. If no version is required on the
`#include` line, the check is skipped.

## Built-in functions

### Memory

```c
void* alloc(i64 size)            // raw heap allocate (uninitialized, untyped)
T*    alloc<T>(count)            // typed uninit: count * sizeof(T), returns T*
T*    new(T)                     // single zero-initialized T, returns T*
T*    new(T[count])              // array of count zero-initialized T, returns T*
void  free(void* ptr)            // heap free (also accepts string directly)
void  memcpy(u8* dst, u8* src, i64 n)
void  memset(u8* dst, u8 val, i64 n)
string string(str s)             // allocate + copy → owned string
string move(string s)            // transfer ownership, invalidate source
```

`alloc<T>(count)` and `new(T[count])` fold the `sizeof(T)` multiplication
and the pointer cast into the builtin:

```c
i32* a = cast(i32*, alloc(n * 4));   // untyped — explicit casts
i32* b = alloc<i32>(n);              // typed, uninit (no zero fill)
i32* c = new(i32[n]);                // typed, zero-init
```

### I/O

```c
i64 stdout()
i64 stderr()
i64 open(u8* path, i32 mode)    // 0=read, 1=write/create
i32 read(i64 fd, u8* buf, i32 n)
i32 write(i64 fd, u8* buf, i32 n)
void close(i64 fd)
bool file_exists(u8* path)
```

### Print

```c
print("hello\n")
print("{} + {} = {}\n", 2, 3, 5)  // compile-time format expansion
eprint("error: {}\n", code)       // to stderr
```

Supported format types: `i32`, `i64`, `u32`, `u64`, `f64`, `bool`, `str`, `string`, pointers.

### Program

```c
void exit(i32 code)
i32 get_argc()
u8* get_arg(i32 index)           // null if out of range
```

### Bit manipulation

```c
i32 popcount(i32 x)             // count set bits
i32 clz(i32 x)                  // count leading zeros
i32 ctz(i32 x)                  // count trailing zeros
i32 bswap(i32 x)                // byte swap
```

### Math (builtins)

```c
f64 sqrt(f64 x)                 // hardware sqrtsd
f64 fabs(f64 x)                 // hardware sign-bit clear
f32 sqrtf(f32 x)                // hardware sqrtss
f32 fabsf(f32 x)                // hardware sign-bit clear (f32)
```

### SIMD intrinsics

Streaming load/store and lane reductions for the packed vec types
(`int4`, `uint4`, `f64x2`, `i64x2`, `u64x2`). Each call is one
SIMD instruction, or a small fixed sequence; codegen is the same
shape on x64 and ARM64.

#### Streaming load/store

One 16-byte SIMD access over the named type's lanes. The function
name encodes the lane type; the pointer must match.

| Function                     | Returns | Notes                |
|------------------------------|---------|----------------------|
| `int4_load(i32*)`            | `int4`  | 4×i32, one `movdqu`  |
| `uint4_load(u32*)`           | `uint4` | 4×u32                |
| `f64x2_load(f64*)`           | `f64x2` | 2×f64                |
| `i64x2_load(i64*)`           | `i64x2` | 2×i64                |
| `u64x2_load(u64*)`           | `u64x2` | 2×u64                |
| `int4_store(i32*, int4)`     | `void`  | matching store       |
| `uint4_store(u32*, uint4)`   | `void`  |                      |
| `f64x2_store(f64*, f64x2)`   | `void`  |                      |
| `i64x2_store(i64*, i64x2)`   | `void`  |                      |
| `u64x2_store(u64*, u64x2)`   | `void`  |                      |

```c
f64x2 a = f64x2_load(p);
f64x2 b = f64x2_load(q);
f64x2 r = a * 2.0 + b;            // component-wise, scalar broadcast
f64x2_store(p, r);

uint4 v = uint4_load(&a[i]);      // one 16-byte load
v = v * 1103515245 + 12345;
uint4_store(&a[i], v);
```

#### Sum and reduce (int4 / uint4)

`sum4` adds the four lanes with 32-bit wrap: `int4` gives `i32`,
`uint4` gives `u32`. `sum4_wide` widens each lane first, then adds
in 64 bits — `int4` sign-extends to `i64`, `uint4` zero-extends to
`u64`. Use `sum4_wide` when the lane total can exceed 32 bits.

`accum4` carries a deferred 2x64 sum across a loop; `reduce4`
collapses the carrier to a scalar once at the end. The carrier is
a real `u64x2`/`i64x2` SIMD vreg, so the fold is one packed add
per iteration with no horizontal work. Reach for them whenever a
per-iteration `sum4`/`sum4_wide` would do horizontal work that can
wait until after the loop.

| Function                     | Returns | Notes                                 |
|------------------------------|---------|---------------------------------------|
| `sum4(int4)`                 | `i32`   | 4-lane horizontal add, 32-bit wrap    |
| `sum4(uint4)`                | `u32`   | 4-lane horizontal add, 32-bit wrap    |
| `sum4_wide(int4)`            | `i64`   | sign-extend each lane to i64 then sum |
| `sum4_wide(uint4)`           | `u64`   | zero-extend each lane to u64 then sum |
| `accum4(u64x2 acc, uint4 v)` | `u64x2` | deferred sum; zero-extend lanes       |
| `accum4(i64x2 acc, int4 v)`  | `i64x2` | deferred sum; sign-extend lanes       |
| `reduce4(u64x2)`             | `u64`   | final reduce of `accum4` carrier      |
| `reduce4(i64x2)`             | `i64`   | final reduce of `accum4` carrier      |

```c
int4 v = int4{1, 2, 3, 4};
i32 s = sum4(v);                  // 10, 32-bit wrap
i64 w = sum4_wide(v);             // 10, widened

u64x2 acc;
for i32 i = 0; i < n; i = i + 4 {
    uint4 v = uint4_load(&a[i]);
    v = v * 1103515245 + 12345;       // map
    uint4_store(&a[i], v);            // write the mapped lanes back
    acc = accum4(acc, v);             // fold into the carried total
}
u64 total = reduce4(acc);             // one reduction, after the loop
```

### Threading

```c
i64 thread_create(fn(void*): void entry, void* arg)
void thread_join(i64 tid)
void thread_sleep(i32 ms)
void mutex_init(void* m)
void mutex_lock(void* m)
void mutex_unlock(void* m)
void mutex_destroy(void* m)
```

## Standard library

Include with `#include` or `import`:

| Library     | File             | Description                                                      |
|-------------|------------------|------------------------------------------------------------------|
| **Vec**     | `lib/vec.mc`     | Generic dynamic array `Vec<T>`                                   |
| **String**  | `lib/str.mc`     | String operations (find, slice, trim, compare, builder)          |
| **Math**    | `lib/math.mc`    | sin, cos, tan, exp, log, pow, floor, ceil, round + helpers       |
| **Float fmt** | `lib/format_f64.mc` / `lib/format_f32.mc` | Ryu shortest-round-trip float-to-string (`format_f64`, `format_f32`) |
| **File**    | `lib/file.mc`    | File read/write (whole file), file_exists                        |
| **Memory**  | `lib/mem.mc`     | Arena allocator and pool allocator                               |
| **Thread**  | `lib/thread.mc`  | OS threads and mutexes                                           |
| **Atomic**  | `lib/atomic.mc`  | Atomic load/store/CAS/RMW with `MemOrder` (relaxed → seq_cst)    |
| **Fiber**   | `lib/fiber.mc`   | Cooperative coroutines (fiber_create, fiber_switch, fiber_yield) |
| **Linear**  | `lib/linear.mc`  | Vector/matrix/quaternion math (dot, cross, normalize, perspective, look_at, quaternions) |
| **Inflate** | `lib/inflate.mc` | DEFLATE decompressor (RFC 1951)                                  |
| **Deflate** | `lib/deflate.mc` | DEFLATE compressor (RFC 1951; fixed-Huffman + LZ77)              |
| **Zlib**    | `lib/zlib.mc`    | zlib + gzip wrappers around inflate/deflate (CRC32, Adler-32)    |
| **PNG**     | `lib/png.mc`     | PNG image decoder (grayscale, RGB, RGBA → RGBA8)                 |
| **Sokol**   | `lib/sokol_all.mc` | Cross-platform graphics/app via sokol C bridge                 |
| **Obj-C**   | `lib/objc_runtime.mc` | Objective-C runtime bindings for Cocoa/UIKit/Metal — *macOS / iOS only* |

### Vec<T>

```c
#include "lib/vec.mc"

Vec<i32> v;
vec_init<i32>(&v, 16);              // initial capacity 16
vec_push<i32>(&v, 42);              // append
i32 x = vec_get<i32>(&v, 0);        // read
vec_set<i32>(&v, 0, 99);            // write
i32 top = vec_pop<i32>(&v);         // pop last
vec_free<i32>(&v);                  // free
```

### String library

```c
#include "lib/str.mc"

str s = "hello world";
bool eq = str_equal(s, "hello world");
i32 idx = str_find(s, "world");         // 6
str sub = str_slice(s, 0, 5);           // "hello"
bool sw = str_starts_with(s, "hello");
bool ew = str_ends_with(s, "world");
bool ct = str_contains(s, "lo w");
str trimmed = str_trim("  hi  ");

// String builder
str_buf sb;
str_buf_init(&sb, 64);
str_buf_add(&sb, "hello ");
str_buf_add(&sb, "world");
str result = str_buf_to_str(&sb);
str_buf_free(&sb);
```

### Math library

```c
#include "lib/math.mc"

f64 r = sqrt(4.0);                  // 2.0 (builtin, hardware)
f64 a = fabs(0.0 - 3.14);           // 3.14 (builtin, hardware)
f64 s = sin(PI / 2.0);              // 1.0 (platform library)
f64 c = cos(0.0);                   // 1.0
f64 e = exp(1.0);                   // 2.718...
f64 l = log(E);                     // 1.0
f64 p = pow(2.0, 10.0);             // 1024.0
f64 f = floor(3.7);                 // 3.0

i32 a = abs_i32(0 - 5);             // 5
f64 c = clamp_f64(15.0, 0.0, 10.0); // 10.0
f64 l = lerp(0.0, 10.0, 0.5);       // 5.0
```

### Linear math library

```c
#include "lib/linear.mc"

// Vector operations (overloaded for float2/3/4)
f32 d = dot(a, b);                   // dot product
f32 l = length(v);                   // magnitude
float3 n = normalize(v);             // unit vector
float3 c = cross(a, b);              // cross product (float3 only)

// Matrix operations (float4x4, column-major)
float4x4 id = identity();
float4x4 proj = perspective(fovy, aspect, near, far);
float4x4 view = look_at(eye, target, up);
float4x4 mvp = mul(proj, view);
float4x4 rx = rotate_x(angle);

// Quaternion operations (float4: x, y, z, w)
float4 q = quat_identity();
float4 q = quat_axis_angle(axis, angle);
float4 q = quat_mul(a, b);
float3 v = quat_rotate(q, point);
float4x4 m = quat_to_mat4(q);
float4 q = quat_slerp(a, b, t);
```

### File I/O

```c
#include "lib/file.mc"

FileData fd = file_read("input.txt");
if fd.data != null {
    // process fd.data[0..fd.len]
    free(fd.data);
}

string contents = file_read_str("input.txt");  // returns owned string
defer free(contents);

file_write("output.txt", fd);
file_write_str("output.txt", "hello");
```

### Memory allocators

```c
#include "lib/mem.mc"

// Arena (bump allocator)
Arena a;
arena_create(&a, 4096);
void* p = arena_alloc_mem(&a, 64);
arena_reset(&a);                // reuse without freeing
arena_destroy(&a);

// Pool (fixed-size blocks)
Pool p;
pool_create(&p, sizeof(Node), 100);
Node* n = cast(Node*, pool_alloc(&p));
pool_free(&p, n);
pool_destroy(&p);
```

### Threading

```c
#include "lib/thread.mc"

void worker(void* arg) {
    i32 id = cast(i32, cast(i64, arg));
    print("worker {}\n", id);
}

i32 main() {
    i64 t1 = thread_create(worker, cast(void*, cast(i64, 1)));
    i64 t2 = thread_create(worker, cast(void*, cast(i64, 2)));
    thread_join(t1);
    thread_join(t2);
    return 0;
}
```

### Fibers

```c
#include "lib/fiber.mc"

void my_fiber(void* arg) {
    print("step 1\n");
    fiber_yield();
    print("step 2\n");
    fiber_yield();
    print("step 3\n");
}

i32 main() {
    fiber_init();
    Fiber* f = fiber_create(my_fiber, null);
    fiber_switch(f);    // "step 1"
    fiber_switch(f);    // "step 2"
    fiber_switch(f);    // "step 3"
    fiber_free(f);
    return 0;
}
```

## C interop

### DLL imports (Windows)

```c
extern "kernel32.dll" void Sleep(i32 ms);
extern "ucrtbase.dll" f64 sin(f64 x);
```

### Shared library imports (Linux/Android)

```c
extern "libc.so.6" i32 getpid();
extern "libm.so.6" f64 sin(f64 x);

// Block syntax for multiple imports from the same library
extern "libm.so.6" {
    f64 sin(f64 x);
    f64 cos(f64 x);
    f64 sqrt(f64 x);
    f64 pow(f64 base, f64 exp);
}
```

### Framework imports (macOS/iOS)

```c
extern "libSystem.B.dylib" f64 sin(f64 x);
extern "libSystem.B.dylib" i64 clock_gettime_nsec_np(i32 clock_id);
```

### Linked object imports

Functions defined in linked `.o` files use bare `extern` (no library name):

```c
extern void sokol_gfx_setup();
extern void my_c_function(i32 x);
```

### Static linking

```bash
# Windows: compile C to .obj, link into minc binary
zig cc -c helper.c -o helper.obj
minc app.mc --link helper.obj -o app.exe

# Linux: compile C to .o
gcc -c helper.c -o helper.o -fno-pie
minc app.mc --link helper.o -o app

# macOS: compile C to .o or link .dylib
clang -c helper.c -o helper.o
minc app.mc --link helper.o -o app

# macOS: dynamic library
minc app.mc --link libhelper.dylib -o app
```

### Exposing minc functions to C

When a minc function is registered as a callback in a C library or
installed as an Objective-C method, it must follow the platform's C ABI
so struct arguments and return values are decoded correctly.

The compiler detects this automatically when the function's address flows
into a C-shaped destination:

- `cast(void*, &fn)` or `cast(void*, fn)`
- `&fn` assigned to a `void*` variable or struct field
- `&fn` passed as an argument whose corresponding parameter is `void*`
- `&fn` passed to an `extern` function

For indirect chains the compiler can't track — for example, `&fn` stored
in a same-typed minc fn-ptr field that is later copied into a `void*`
field — use the explicit `@c_abi` annotation on the function declaration:

```c
@c_abi
void my_method_impl(NSRect rect, u64 flags) {
    // receives the NSRect correctly per the C ABI
}
```

Cases that typically need the C ABI: callbacks taking or returning a
small struct of floats (`NSPoint`, `NSSize`, `NSRect`, `CGRect`, …) or a
9-16 byte non-float struct (`NSRange`, …). Callbacks with only pointer
or scalar parameters use the same convention either way and need no
annotation.

## Shaders

GPU shaders written in minc syntax. The compiler generates HLSL (Windows/D3D11),
GLSL (Linux/WebGL2), or Metal MSL (macOS/iOS) for the target platform.

### Shader functions

Use `@shader` annotations to define vertex, fragment, or compute shader functions:

```c
struct VsOut {
    float4 pos;
    float4 color;
}

@shader vertex
VsOut cube_vs(
    @attr(0) float4 position,
    @attr(1) float4 color,
    @uniform float4x4 mvp
) {
    VsOut outp;
    outp.pos = mul(mvp, position);
    outp.color = color;
    return outp;
}

@shader fragment
float4 cube_fs(VsOut input) {
    return input.color;
}

@shader compute(64, 1, 1)
void my_compute(@storage(rgba8) RWTexture2D img, @uniform f32 scale) {
    uint2 pixel = thread_id().xy;
    img[pixel] = float4{scale, scale, scale, 1.0f};
}
```

Shader functions don't generate native code — they compile to GPU shader source
text. The compiler auto-generates a `funcname_shader` global (of type `ShaderMeta`)
for each `@shader` function. The first field of the VS output struct is treated as
the clip-space position (`gl_Position` / `SV_Position`).

`ShaderMeta.uniforms` points at a flat array of `ShaderUniformDesc` (one entry per
scalar/vector/matrix field across all uniform blocks); `ShaderMeta.uniforms_count`
is its length. Plain `@uniform float4x4 mvp` produces one descriptor; struct
`@uniform(N) PerFrame frame { mat4 mvp; vec4 light_dir; }` produces one per field
(with each field's name + offset). Each descriptor's `type_kind` is one of:

| Value | Kind | Source-language type |
|-------|------|----------------------|
| 1  | FLOAT  | `f32` |
| 2  | FLOAT2 | `float2` |
| 3  | FLOAT3 | `float3` |
| 4  | FLOAT4 | `float4` |
| 5  | INT    | `i32` |
| 6  | INT2   | `int2` |
| 7  | INT3   | `int3` |
| 8  | INT4   | `int4` |
| 9  | MAT4   | `float4x4` |
| 10 | UINT   | `u32` |
| 11 | UINT2  | `uint2` |
| 12 | UINT3  | `uint3` |
| 13 | UINT4  | `uint4` |

The values are runtime-agnostic; adapters map them to their own per-uniform
type system (sokol's `sg_uniform_type` uses the same numbers). `import shader;`
exposes a `ShaderUType` enum with these constants for code that walks the
descriptors. Limitation: nested structs in `@uniform` structs are rejected;
flatten to scalar/vector/matrix fields.

`ShaderMeta.bindings` points at a flat array of `ShaderBinding` (one entry per
`@texture` / `@sampler` / `@storage` / `@buffer` / `@rwbuffer` parameter, in
declaration order); `bindings_count` is its length. Each entry carries the
binding's name, kind, slot, image type, storage-image format string, access
mode, structured-buffer element size, and stage. Runtime adapters (e.g.
`sokol_make_shader` in `lib/sokol_all.mc`) walk the array to build their
backend-specific descriptors. `import shader;` exposes `ShaderBindingKind`,
`ShaderImageType`, and `ShaderBindingAccess` enums.

### Parameter annotations

| Annotation | Stage | Description |
|------------|-------|-------------|
| `@attr(N)` | Vertex | Vertex attribute at location N |
| `@uniform` | VS/FS | Uniform buffer variable (each gets its own block) |
| `@storage(fmt[, slot][, rw])` | Compute | Storage image (e.g., `rgba8`); writeonly by default, readwrite with the `rw` keyword |
| `@texture(N)` | Fragment | Read-only texture at slot N |
| `@sampler(N)` | Fragment | Texture sampler at slot N |
| `@flat` | Varying | Disable interpolation (for integer varyings) |
| `@buffer(N)` | VS/FS/Compute | Read-only structured buffer |
| `@rwbuffer(N)` | Compute | Read-write structured buffer |
| `@shared` | Compute | Group shared memory (local variable) |

### Shader builtins

These functions are available inside `@shader` functions. Use GPU-standard
names (not C-style `sinf` / `cosf` — the checker errors with the expected
name).

**Math**:
`sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `sqrt`, `rsqrt`, `abs`,
`exp`, `log`, `log2`, `pow`, `floor`, `ceil`, `round`, `frac`, `sign`, `saturate`

**Interpolation**:
`lerp` / `mix`, `step`, `smoothstep`, `clamp`, `min`, `max`

**Vector**:
`dot`, `cross`, `normalize`, `length`, `distance`, `reflect`, `refract`

**Conversion**: `radians`, `degrees`

**Matrix**: `mul` (matrix × vector, matrix × matrix)

**Derivatives** (fragment only): `ddx`, `ddy`, `fwidth`

**Texture**:
`sample(tex, smp, uv)`, `sample_level(tex, smp, uv, lod)`,
`sample_cmp(tex, smp, uv, cmp)`, `sample_offset(tex, smp, uv, offset)`,
`gather(tex, smp, uv)`, `texture_size(tex)`

**Stage builtins**:
`thread_id()`, `group_id()`, `local_id()` (compute),
`vertex_id()`, `instance_id()` (vertex),
`frag_coord()`, `front_facing()` (fragment),
`group_barrier()`, `memory_barrier()` (compute)

**Atomic** (compute):
`atomic_add`, `atomic_min`, `atomic_max`, `atomic_exchange`, `atomic_cmp_exchange`

### Using shaders with sokol

Each `@shader` function generates a `ShaderMeta` global named `funcname_shader`.
Create a sokol shader from a vertex + fragment pair:

```c
sg_shader shd = sokol_make_shader(&cube_vs_shader, &cube_fs_shader);
```

Pass uniforms via `sg_apply_uniforms()` — each `@uniform` parameter becomes a
separate uniform block (block 0 for the first, block 1 for the second, etc.).

### Cross-platform GPU targets

The shader backend is selected automatically from `--target`:

| Target | GPU backend | Shader language |
|--------|-------------|-----------------|
| Windows | D3D11 | HLSL |
| Linux | OpenGL | GLSL 330 |
| WASM/Android | OpenGL ES | GLSL ES 300 |
| macOS/iOS | Metal | MSL |

Override with `@gpu "target"` at file scope (before shader functions):
`@gpu "opengl"`, `@gpu "d3d11"`, `@gpu "metal"`, `@gpu "opengles"`.

## Build commands

```
minc main.mc                    # build release, output main.exe (or main)
minc build main.mc              # same as above
minc build debug main.mc        # build with debug info
minc run main.mc                # build and run
minc run debug main.mc          # build debug and run
minc main.mc -o custom.exe      # explicit output name
minc main.mc --target linux     # cross-compile to Linux
```

Output filename is derived from input: `app.mc` → `app.exe` (Windows) or `app` (Linux/macOS).
Use `-o` to override.

## Source tags

Build options can be specified in source files using `@` directives.
Tags propagate transitively through `#include` — if a library has `@link`,
any program that includes it automatically links the specified file.

```c
@link "c_code.obj"              // link external object file
@gui                            // set PE subsystem to GUI (no console)
@unchecked                      // disable bounds checking
@define "SG_D3D11"              // define compile-time flag (for when defined())
@must_use i32 try_parse(...)    // warn when caller discards the result
```

Tags are typically placed in library files:
```c
// lib/my_library.mc
when os(windows) {
    @link "c_code.obj"
    @gui
}
when os(linux) {
    @link "c_code.o"
}
```

With this, `minc app.mc` is all that's needed to compile a linked app —
no `--link` or `--gui` flags required.

## Compiler flags

```
minc [build|run] [debug] <input.mc> [options]

-o FILE                 Output filename (default: derived from input)
--target <t>            Cross-compile (see target table below)
--link <file>           Link external object file (also available as @link tag)
--shared                Emit shared library (.so) instead of executable
--gui                   Set PE subsystem to GUI (also available as @gui tag)
--def <file.def>        Load additional .def file for DLL mapping (Windows)
-g                      Emit DWARF debug info (same as `build debug`)
-unchecked              Disable bounds checking
-DFLAG                  Define compile-time flag
-DFLAG=value            Define with value
--check                 Type-check only
--list-builtins         List built-in Windows API symbols
--version               Print compiler version
```

Standard Windows API symbols (kernel32, user32, gdi32, ucrtbase, d3d11, ole32,
shell32) are built into the compiler — no `--def` flags needed for common APIs.
Run `minc --list-builtins` to see all 263 available symbols.

### Cross-compilation targets

| Target         | Output format       | Architecture | Example                                    |
|----------------|--------------------|--------------|--------------------------------------------|
| `windows`      | PE executable      | x86-64       | `minc app.mc --target windows -o app.exe`  |
| `linux`        | ELF executable     | x86-64       | `minc app.mc --target linux -o app`        |
| `linux-arm64`  | ELF executable     | ARM64        | `minc app.mc --target linux-arm64 -o app`  |
| `macos`        | Mach-O executable  | ARM64        | `minc app.mc --target macos -o app`        |
| `wasm`         | WebAssembly        | WASM32       | `minc app.mc --target wasm -o app.wasm`    |
| `ios`          | Mach-O executable  | ARM64        | `minc app.mc --target ios -o app`          |
| `ios-sim`      | Mach-O executable  | ARM64        | `minc app.mc --target ios-sim -o app`      |
| `android`      | ELF shared library | ARM64        | `minc app.mc --target android -o libapp.so`|

The default target matches the host platform. Cross-compilation produces native
binaries without requiring any toolchain for the target platform.

Packaging for distribution still needs the platform's standard tools. iOS
needs Xcode (`xcode-select --install`) and an Apple Developer account for
on-device signing. Android needs the SDK + JDK for APK assembly, plus the
NDK if the app pulls in C code. See `SETUP.md` for setup details.

## Design principles

- **Explicit over implicit**: sizes in type names, explicit casts for lossy conversions
- **No preprocessor**: `when` for conditionals, `enum` for constants, `#include` for files
- **Safe by default**: bounds checking on, wrapping arithmetic (no UB)
- **Zero-cost abstractions**: generics monomorphize, `defer` compiles to inline cleanup
- **Minimal runtime**: no GC, no exceptions, no hidden allocations
- **Direct hardware access**: pointers, `cast()`, `extern` for FFI, inline x64/ARM64
