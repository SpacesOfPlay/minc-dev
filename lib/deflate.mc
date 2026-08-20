// deflate.mc — DEFLATE compressor (RFC 1951). Fixed-Huffman + LZ77 (greedy).
// Companion encoder to inflate.mc. Reuses the length/distance base tables
// initialized by init_len_dist_tables() in inflate.mc.
//
// Public API:
//   i32 deflate(u8* src, i32 srclen, u8* dst, i32 dstlen, i32* out_dstused);
//
// Error codes:
//   0  = success
//  -1  = output buffer overflow
//  -2  = invalid argument

#include "inflate.mc"

// ---------------- bit writer ----------------

private struct BitWriter {
    u8* dst;
    i32 dstlen;
    i32 dstpos;
    i32 bitbuf;
    i32 bitcnt;
    bool overflow;
}

private void bw_init(BitWriter* w, u8* dst, i32 dstlen) {
    w.dst = dst;
    w.dstlen = dstlen;
    w.dstpos = 0;
    w.bitbuf = 0;
    w.bitcnt = 0;
    w.overflow = false;
    return;
}

// Append nbits low bits of val, LSB-first. Used for extra bits and raw fields.
private void bw_bits(BitWriter* w, i32 val, i32 nbits) {
    if w.overflow { return; }
    i32 mask = (1 << nbits) - 1;
    w.bitbuf = w.bitbuf | ((val & mask) << w.bitcnt);
    w.bitcnt = w.bitcnt + nbits;
    while w.bitcnt >= 8 {
        if w.dstpos >= w.dstlen {
            w.overflow = true;
            return;
        }
        *(w.dst + w.dstpos) = cast(u8, w.bitbuf & 255);
        w.dstpos = w.dstpos + 1;
        w.bitbuf = w.bitbuf >> 8;
        w.bitcnt = w.bitcnt - 8;
    }
    return;
}

// Pad remaining bits in the current byte with zeros.
private void bw_align_byte(BitWriter* w) {
    if w.bitcnt > 0 {
        i32 pad = 8 - w.bitcnt;
        bw_bits(w, 0, pad);
    }
    return;
}

// Write one whole byte (must be byte-aligned).
private void bw_byte(BitWriter* w, i32 b) {
    if w.overflow { return; }
    if w.dstpos >= w.dstlen { w.overflow = true; return; }
    *(w.dst + w.dstpos) = cast(u8, b & 255);
    w.dstpos = w.dstpos + 1;
    return;
}

// ---------------- fixed Huffman codes (RFC 1951 §3.2.6) ----------------
// Codes are packed MSB-first on the wire. We precompute each code already
// bit-reversed so emission is a single bw_bits call (which is LSB-first).

private i32[286] fix_lit_rev;
private i32[286] fix_lit_nbits;
private i32[30] fix_dist_rev;
private bool fix_inited = false;

private i32 bit_reverse(i32 v, i32 nbits) {
    i32 r = 0;
    i32 x = v;
    for i32 i = 0; i < nbits; i = i + 1 {
        r = (r << 1) | (x & 1);
        x = x >> 1;
    }
    return r;
}

private void fix_init() {
    if fix_inited { return; }
    fix_inited = true;

    // Literals 0..143: 8-bit codes 0x30..0xBF
    for i32 sym = 0; sym < 144; sym = sym + 1 {
        fix_lit_rev[sym] = bit_reverse(0x30 + sym, 8);
        fix_lit_nbits[sym] = 8;
    }
    // Literals 144..255: 9-bit codes 0x190..0x1FF
    for i32 sym = 144; sym < 256; sym = sym + 1 {
        fix_lit_rev[sym] = bit_reverse(0x190 + (sym - 144), 9);
        fix_lit_nbits[sym] = 9;
    }
    // End-of-block + length symbols 256..279: 7-bit codes 0x00..0x17
    for i32 sym = 256; sym < 280; sym = sym + 1 {
        fix_lit_rev[sym] = bit_reverse(sym - 256, 7);
        fix_lit_nbits[sym] = 7;
    }
    // Length symbols 280..285: 8-bit codes 0xC0..0xC5
    for i32 sym = 280; sym < 286; sym = sym + 1 {
        fix_lit_rev[sym] = bit_reverse(0xC0 + (sym - 280), 8);
        fix_lit_nbits[sym] = 8;
    }
    // Distances 0..29: 5-bit codes (code == symbol)
    for i32 sym = 0; sym < 30; sym = sym + 1 {
        fix_dist_rev[sym] = bit_reverse(sym, 5);
    }
    return;
}

// ---------------- length / distance encoding ----------------
// Inverse of inflate's table lookup. Reuses inf_lens/inf_lext/inf_dists/inf_dext
// from inflate.mc (initialized by init_len_dist_tables).

// Returns length code index 0..28 (symbol = 257 + index) for length in 3..258.
private i32 length_code_for(i32 len) {
    for i32 i = 28; i >= 0; i = i - 1 {
        if inf_lens[i] <= len { return i; }
    }
    return 0;
}

// Returns distance code index 0..29 for distance in 1..32768.
private i32 distance_code_for(i32 dist) {
    for i32 i = 29; i >= 0; i = i - 1 {
        if inf_dists[i] <= dist { return i; }
    }
    return 0;
}

// ---------------- LZ77 matcher ----------------

private i32 DEF_WINDOW_SIZE = 32768;
private i32 DEF_HASH_SIZE = 32768;    // 1 << 15
private i32 DEF_HASH_MASK = 32767;
private i32 DEF_WIN_MASK = 32767;
private i32 DEF_MIN_MATCH = 3;
private i32 DEF_MAX_MATCH = 258;
private i32 DEF_MAX_CHAIN = 128;

private struct Lz77State {
    u8* src;
    i32 srclen;
    i32* head;   // HASH_SIZE entries, -1 = no prior position for this hash
    i32* prev;   // WINDOW_SIZE entries, chain of prior positions (-1 = end)
}

private i32 lz77_hash(u8* p) {
    i32 b0 = cast(i32, *p);
    i32 b1 = cast(i32, *(p + 1));
    i32 b2 = cast(i32, *(p + 2));
    return ((b0 << 10) ^ (b1 << 5) ^ b2) & DEF_HASH_MASK;
}

private void lz77_insert(Lz77State* s, i32 pos) {
    if pos + DEF_MIN_MATCH > s.srclen { return; }
    i32 h = lz77_hash(s.src + pos);
    *(s.prev + (pos & DEF_WIN_MASK)) = *(s.head + h);
    *(s.head + h) = pos;
    return;
}

// Find longest match starting at pos. Returns length (0 if none ≥ MIN_MATCH).
// Writes winning distance to *out_dist on success.
private i32 lz77_find(Lz77State* s, i32 pos, i32* out_dist) {
    if pos + DEF_MIN_MATCH > s.srclen { return 0; }

    i32 h = lz77_hash(s.src + pos);
    i32 cur = *(s.head + h);
    i32 chain = DEF_MAX_CHAIN;
    i32 best_len = 0;
    i32 best_dist = 0;

    i32 max_len = DEF_MAX_MATCH;
    if s.srclen - pos < max_len { max_len = s.srclen - pos; }

    i32 min_cur = pos - DEF_WINDOW_SIZE;
    if min_cur < 0 { min_cur = 0; }

    while cur >= min_cur && chain > 0 {
        chain = chain - 1;

        // Quick reject: compare the byte one past the current best.
        if best_len > 0 {
            if *(s.src + cur + best_len) != *(s.src + pos + best_len) {
                cur = *(s.prev + (cur & DEF_WIN_MASK));
                continue;
            }
        }

        i32 i = 0;
        while i < max_len && *(s.src + cur + i) == *(s.src + pos + i) {
            i = i + 1;
        }
        if i > best_len {
            best_len = i;
            best_dist = pos - cur;
            if i >= max_len { break; }
        }
        cur = *(s.prev + (cur & DEF_WIN_MASK));
    }

    if best_len >= DEF_MIN_MATCH {
        *out_dist = best_dist;
        return best_len;
    }
    return 0;
}

// ---------------- emit helpers ----------------

private void emit_lit(BitWriter* w, i32 sym) {
    bw_bits(w, fix_lit_rev[sym], fix_lit_nbits[sym]);
    return;
}

private void emit_match(BitWriter* w, i32 len, i32 dist) {
    i32 lc = length_code_for(len);
    i32 lsym = 257 + lc;
    bw_bits(w, fix_lit_rev[lsym], fix_lit_nbits[lsym]);
    i32 lextra = inf_lext[lc];
    if lextra > 0 {
        bw_bits(w, len - inf_lens[lc], lextra);
    }
    i32 dc = distance_code_for(dist);
    bw_bits(w, fix_dist_rev[dc], 5);
    i32 dextra = inf_dext[dc];
    if dextra > 0 {
        bw_bits(w, dist - inf_dists[dc], dextra);
    }
    return;
}

// ---------------- main entry point ----------------

// Compress src into dst using a single final fixed-Huffman block.
// Returns 0 on success, negative on error. On success *out_dstused receives
// the number of bytes written.
i32 deflate(u8* src, i32 srclen, u8* dst, i32 dstlen, i32* out_dstused) {
    if srclen < 0 || dstlen < 0 { return 0 - 2; }

    init_len_dist_tables();
    fix_init();

    BitWriter w;
    bw_init(&w, dst, dstlen);

    // Allocate and seed the LZ77 hash/chain tables (-1 = "no prior position").
    i32* head = cast(i32*, alloc(cast(i64, DEF_HASH_SIZE * 4)));
    i32* prev = cast(i32*, alloc(cast(i64, DEF_WINDOW_SIZE * 4)));
    for i32 i = 0; i < DEF_HASH_SIZE; i = i + 1 { *(head + i) = 0 - 1; }
    for i32 i = 0; i < DEF_WINDOW_SIZE; i = i + 1 { *(prev + i) = 0 - 1; }

    Lz77State st;
    st.src = src;
    st.srclen = srclen;
    st.head = head;
    st.prev = prev;

    // Single fixed-Huffman final block: BFINAL=1, BTYPE=01.
    bw_bits(&w, 1, 1);
    bw_bits(&w, 1, 2);

    i32 pos = 0;
    while pos < srclen {
        i32 match_dist = 0;
        i32 match_len = lz77_find(&st, pos, &match_dist);

        if match_len >= DEF_MIN_MATCH {
            emit_match(&w, match_len, match_dist);
            // Insert every covered position into the hash chain.
            i32 end = pos + match_len;
            for i32 j = pos; j < end; j = j + 1 { lz77_insert(&st, j); }
            pos = end;
        } else {
            emit_lit(&w, cast(i32, *(src + pos)));
            lz77_insert(&st, pos);
            pos = pos + 1;
        }

        if w.overflow { break; }
    }

    // End-of-block (symbol 256).
    bw_bits(&w, fix_lit_rev[256], fix_lit_nbits[256]);
    bw_align_byte(&w);

    free(head);
    free(prev);

    if w.overflow { return 0 - 1; }
    if out_dstused != cast(i32*, 0) { *out_dstused = w.dstpos; }
    return 0;
}
