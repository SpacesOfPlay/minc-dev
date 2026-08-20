// str.mc - String library for str type
//

// --- Conversion ---

str str_from(u8* data, i32 len) {
    str s = "";
    s.data = data;
    s.len = len;
    return s;
}

str str_from_cstr(u8* cstr) {
    i32 len = 0;
    while *(cstr + len) != 0 {
        len = len + 1;
    }
    return str_from(cstr, len);
}

// Returns owned string — caller must free.
u8* str_to_cstr(str s) {
    u8* buf = alloc<u8>(s.len + 1);
    memcpy(buf, s.data, s.len);
    *(buf + s.len) = 0;
    return buf;
}

// Concatenate two strings. Returns owned string — caller must free.
string str_concat(str a, str b) {
    i32 len = a.len + b.len;
    u8* buf = cast(u8*, alloc(cast(i64, len)));
    memcpy(buf, a.data, cast(i64, a.len));
    memcpy(buf + a.len, b.data, cast(i64, b.len));
    string result;
    result.data = buf;
    result.len = len;
    return result;
}

// --- Comparison ---
// NOTE: str_equal and str_compare operate on raw bytes (no Unicode normalization).
// For correct comparison of Unicode strings with equivalent but differently-encoded
// codepoints (e.g. precomposed vs decomposed), a separate str_equal_normalized /
// str_compare_normalized function with Unicode NFC/NFD normalization is needed.

bool str_equal(str a, str b) {
    if a.len != b.len { return false; }
    for i32 i = 0; i < a.len; i = i + 1 {
        if *(a.data + i) != *(b.data + i) { return false; }
    }
    return true;
}

i32 str_compare(str a, str b) {
    i32 min_len = a.len;
    if b.len < min_len { min_len = b.len; }
    for i32 i = 0; i < min_len; i = i + 1 {
        i32 ca = cast(i32, *(a.data + i));
        i32 cb = cast(i32, *(b.data + i));
        if ca < cb { return 0 - 1; }
        if ca > cb { return 1; }
    }
    if a.len < b.len { return 0 - 1; }
    if a.len > b.len { return 1; }
    return 0;
}

// --- Search ---

i32 str_find_byte(str s, u8 c) {
    for i32 i = 0; i < s.len; i = i + 1 {
        if *(s.data + i) == c { return i; }
    }
    return 0 - 1;
}

i32 str_find(str haystack, str needle) {
    if needle.len == 0 { return 0; }
    if needle.len > haystack.len { return 0 - 1; }
    i32 limit = haystack.len - needle.len + 1;
    for i32 i = 0; i < limit; i = i + 1 {
        bool match = true;
        for i32 j = 0; j < needle.len; j = j + 1 {
            if *(haystack.data + i + j) != *(needle.data + j) {
                match = false;
                break;
            }
        }
        if match { return i; }
    }
    return 0 - 1;
}

bool str_starts_with(str s, str prefix) {
    if prefix.len > s.len { return false; }
    for i32 i = 0; i < prefix.len; i = i + 1 {
        if *(s.data + i) != *(prefix.data + i) { return false; }
    }
    return true;
}

bool str_ends_with(str s, str suffix) {
    if suffix.len > s.len { return false; }
    i32 off = s.len - suffix.len;
    for i32 i = 0; i < suffix.len; i = i + 1 {
        if *(s.data + off + i) != *(suffix.data + i) { return false; }
    }
    return true;
}

bool str_contains(str s, str needle) {
    return str_find(s, needle) >= 0;
}

// --- Slicing ---

str str_slice(str s, i32 start, i32 end) {
    if start < 0 { start = 0; }
    if end > s.len { end = s.len; }
    if start >= end { return str_from(s.data, 0); }
    return str_from(s.data + start, end - start);
}

str str_trim(str s) {
    i32 start = 0;
    while start < s.len {
        u8 c = *(s.data + start);
        if c != 32 && c != 9 && c != 10 && c != 13 { break; }
        start = start + 1;
    }
    i32 end = s.len;
    while end > start {
        u8 c = *(s.data + end - 1);
        if c != 32 && c != 9 && c != 10 && c != 13 { break; }
        end = end - 1;
    }
    return str_slice(s, start, end);
}

// --- String Builder ---

struct str_buf {
    u8* data;
    i32 len;
    i32 cap;
}

void str_buf_init(str_buf* sb) {
    sb.cap = 64;
    sb.len = 0;
    sb.data = cast(u8*, alloc(64));
    return;
}

void str_buf_grow(str_buf* sb, i32 needed) {
    if sb.len + needed <= sb.cap { return; }
    i32 new_cap = sb.cap * 2;
    while new_cap < sb.len + needed {
        new_cap = new_cap * 2;
    }
    u8* new_data = cast(u8*, alloc(cast(i64, new_cap)));
    memcpy(new_data, sb.data, cast(i64, sb.len));
    free(sb.data);
    sb.data = new_data;
    sb.cap = new_cap;
    return;
}

void str_buf_add(str_buf* sb, str s) {
    str_buf_grow(sb, s.len);
    memcpy(sb.data + sb.len, s.data, cast(i64, s.len));
    sb.len = sb.len + s.len;
    return;
}

void str_buf_add_byte(str_buf* sb, u8 c) {
    str_buf_grow(sb, 1);
    *(sb.data + sb.len) = c;
    sb.len = sb.len + 1;
    return;
}

void str_buf_add_bytes(str_buf* sb, u8* data, i32 len) {
    str_buf_grow(sb, len);
    memcpy(sb.data + sb.len, data, cast(i64, len));
    sb.len = sb.len + len;
    return;
}

str str_buf_to_str(str_buf* sb) {
    return str_from(sb.data, sb.len);
}

void str_buf_free(str_buf* sb) {
    free(sb.data);
    sb.data = null;
    sb.len = 0;
    sb.cap = 0;
    return;
}
