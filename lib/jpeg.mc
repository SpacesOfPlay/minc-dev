// jpeg.mc — JPEG baseline (SOF0) decoder + encoder for minc
// Depends on: lib/file.mc  (file_read, file_write, FileData)
//
// Read:  baseline sequential DCT (SOF0), 8-bit, grayscale or YCbCr with
//        4:4:4 / 4:2:2 / 4:2:0 / 4:4:0 subsampling, restart markers.
//        Progressive (SOF2) is rejected with a clear error.
//        Output is always RGBA8 (4 bytes per pixel). Caller must free(pixels).
// Write: RGBA8 input, 4:2:0 subsampling, quality 1-100 (clamped),
//        standard Annex-K quantization + Huffman tables, JFIF header.
//
// Usage:
//   JpegImage img = jpeg_load("image.jpg");
//   if img.pixels != null { /* use img.width, img.height, img.pixels */ }
//   jpeg_save("out.jpg", pixels, w, h, 85);
//
// Encode error codes:
//    0  success
//   -1  output buffer too small
//   -2  invalid arguments
//   -3  internal error
//   -4  file write failed (jpeg_save only)

#include "file.mc"


struct JpegImage {
    u8* pixels;     // RGBA8 data, null on error
    i32 width;      // 0 on error
    i32 height;     // 0 on error
}

private JpegImage jpeg_error(u8* msg) {
    eprint("jpeg: ");
    i32 ml = 0; while *(msg + ml) != 0 { ml = ml + 1; }
    write(stderr(), msg, ml);
    eprint("\n");
    JpegImage r;
    r.pixels = null;
    r.width = 0;
    r.height = 0;
    return r;
}

// --- Spec constant tables -------------------------------------------

// Zigzag scan order: zigzag index -> natural (row-major) index.
const u8[64] jz_zigzag = {
     0,  1,  8, 16,  9,  2,  3, 10,
    17, 24, 32, 25, 18, 11,  4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13,  6,  7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63
};

// Annex K base quantization tables (natural order), used by the encoder.
const u8[64] jq_luma_base = {
    16, 11, 10, 16, 24, 40, 51, 61,
    12, 12, 14, 19, 26, 58, 60, 55,
    14, 13, 16, 24, 40, 57, 69, 56,
    14, 17, 22, 29, 51, 87, 80, 62,
    18, 22, 37, 56, 68, 109, 103, 77,
    24, 35, 55, 64, 81, 104, 113, 92,
    49, 64, 78, 87, 103, 121, 120, 101,
    72, 92, 95, 98, 112, 100, 103, 99
};
const u8[64] jq_chroma_base = {
    17, 18, 24, 47, 99, 99, 99, 99,
    18, 21, 26, 66, 99, 99, 99, 99,
    24, 26, 56, 99, 99, 99, 99, 99,
    47, 66, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99
};

// AAN scale factors: cos(k*pi/16) * sqrt(2) for k=1..7, 1.0 for k=0
// and k=4. Hardcoded literals (no runtime cos) so numerics are
// identical on every target.
private f32 jaan_factor(i32 k) {
    if k == 1 { return 1.387039845f; }
    if k == 2 { return 1.306562965f; }
    if k == 3 { return 1.175875602f; }
    if k == 5 { return 0.785694958f; }
    if k == 6 { return 0.541196100f; }
    if k == 7 { return 0.275899379f; }
    return 1.0f;   // k == 0 or 4
}

// --- MSB-first bit reader (entropy-coded segment) --------------------
// JPEG bit streams are MSB-first with 0xFF byte stuffing: a 0xFF data
// byte is followed by 0x00 on the wire; 0xFF followed by anything else
// is a marker that terminates the entropy segment. inflate.mc's
// BitState is LSB-first and unrelated.

private struct JBits {
    u8* src;
    i32 len;
    i32 pos;
    u32 bitbuf;     // low `bitcnt` bits valid, MSB of stream toward high bits
    i32 bitcnt;
    bool eof;       // input or marker hit; further reads feed zero bits
    i32 marker;     // marker byte seen during refill (0 = none)
}

private void jb_init(JBits* b, u8* src, i32 len, i32 pos) {
    b.src = src;
    b.len = len;
    b.pos = pos;
    b.bitbuf = 0;
    b.bitcnt = 0;
    b.eof = false;
    b.marker = 0;
}

// Top up the accumulator to >= 25 bits (or until input/marker ends).
private void jb_fill(JBits* b) {
    while b.bitcnt <= 24 {
        if b.eof {
            // Feed zero bits past the end; caller detects via eof.
            b.bitbuf = b.bitbuf << 8;
            b.bitcnt = b.bitcnt + 8;
            continue;
        }
        if b.pos >= b.len {
            b.eof = true;
            continue;
        }
        i32 byte = cast(i32, *(b.src + b.pos));
        if byte == 255 {
            // Peek the follower: 0x00 = stuffed data byte, FF = fill
            // byte (skip), anything else = marker -> stop here.
            i32 nxt = b.pos + 1;
            while nxt < b.len && cast(i32, *(b.src + nxt)) == 255 {
                nxt = nxt + 1;   // skip fill bytes
            }
            if nxt >= b.len {
                b.eof = true;
                continue;
            }
            i32 follow = cast(i32, *(b.src + nxt));
            if follow == 0 {
                // Stuffed 0xFF data byte.
                b.bitbuf = (b.bitbuf << 8) | 255;
                b.bitcnt = b.bitcnt + 8;
                b.pos = nxt + 1;
                continue;
            }
            // Marker: record and stop consuming.
            b.marker = follow;
            b.pos = nxt + 1;
            b.eof = true;
            continue;
        }
        b.bitbuf = (b.bitbuf << 8) | cast(u32, byte);
        b.bitcnt = b.bitcnt + 8;
        b.pos = b.pos + 1;
    }
}

// Read n bits MSB-first (n in 0..16).
private i32 jb_get(JBits* b, i32 n) {
    if n == 0 { return 0; }
    if b.bitcnt < n { jb_fill(b); }
    i32 shift = b.bitcnt - n;
    i32 v = cast(i32, b.bitbuf >> cast(u32, shift)) & ((1 << n) - 1);
    b.bitcnt = shift;
    return v;
}

// Spec F.12 EXTEND: map an s-bit magnitude to its signed value.
private i32 jb_receive_extend(JBits* b, i32 s) {
    i32 v = jb_get(b, s);
    if v < (1 << (s - 1)) {
        return v - (1 << s) + 1;
    }
    return v;
}

// Byte-align and verify the expected restart marker. Returns false on
// a wrong/missing marker.
private bool jb_restart(JBits* b, i32 expect_idx) {
    b.bitbuf = 0;
    b.bitcnt = 0;
    if b.marker == 0 {
        // Marker not yet hit during refill — scan forward for it.
        while b.pos + 1 < b.len {
            if cast(i32, *(b.src + b.pos)) == 255 {
                i32 follow = cast(i32, *(b.src + b.pos + 1));
                if follow != 0 && follow != 255 {
                    b.marker = follow;
                    b.pos = b.pos + 2;
                    break;
                }
            }
            b.pos = b.pos + 1;
        }
    }
    if b.marker != 208 + (expect_idx & 7) {   // 0xD0 + n
        return false;
    }
    b.marker = 0;
    b.eof = false;
    return true;
}

// --- Huffman tables (spec F.16 canonical decode) ----------------------

private struct JHuff {
    i32[17] mincode;
    i32[17] maxcode;   // -1 where no codes of that length
    i32[17] valptr;
    u8[256] vals;
    u8[256] fast_sym;  // 8-bit lookahead LUT (filled in by jh_build)
    u8[256] fast_len;  // code length for fast_sym; 0 = use slow path
    bool present;
}

// Build decode tables from BITS[1..16] + HUFFVAL. Returns false on an
// invalid (over-subscribed) table.
private bool jh_build(JHuff* h, u8* bits, u8* vals, i32 nvals) {
    for i32 i = 0; i < nvals; i++ { h.vals[i] = *(vals + i); }
    i32 code = 0;
    i32 k = 0;
    for i32 len = 1; len <= 16; len++ {
        i32 n = cast(i32, *(bits + len));
        if n == 0 {
            h.mincode[len] = 0;
            h.maxcode[len] = -1;
            h.valptr[len] = 0;
        }
        else {
            h.valptr[len] = k;
            h.mincode[len] = code;
            code = code + n;
            k = k + n;
            h.maxcode[len] = code - 1;
        }
        if code > (1 << len) { return false; }   // over-subscribed
        code = code << 1;
    }
    // 8-bit lookahead LUT: for every code of length <= 8, fill all
    // LUT slots whose top bits match the code.
    for i32 i = 0; i < 256; i++ { h.fast_len[i] = 0; }
    i32 fcode = 0;
    i32 fk = 0;
    for i32 len = 1; len <= 8; len++ {
        i32 n = cast(i32, *(bits + len));
        for i32 ci = 0; ci < n; ci++ {
            i32 prefix = fcode << (8 - len);
            i32 nfill = 1 << (8 - len);
            for i32 f = 0; f < nfill; f++ {
                h.fast_sym[prefix + f] = h.vals[fk];
                h.fast_len[prefix + f] = cast(u8, len);
            }
            fcode = fcode + 1;
            fk = fk + 1;
        }
        fcode = fcode << 1;
    }
    h.present = true;
    return true;
}

// Decode one Huffman symbol. Returns -1 on an invalid code.
private i32 jh_decode(JBits* b, JHuff* h) {
    if b.bitcnt < 16 { jb_fill(b); }
    // Fast path: 8-bit lookahead.
    if b.bitcnt >= 8 {
        i32 peek = cast(i32, (b.bitbuf >> cast(u32, b.bitcnt - 8)) & 255);
        i32 flen = cast(i32, h.fast_len[peek]);
        if flen != 0 {
            b.bitcnt = b.bitcnt - flen;
            return cast(i32, h.fast_sym[peek]);
        }
    }
    // Slow path: per-bit canonical walk (codes 9..16 bits).
    i32 code = jb_get(b, 1);
    i32 len = 1;
    while code > h.maxcode[len] {
        if len >= 16 { return -1; }
        code = (code << 1) | jb_get(b, 1);
        len = len + 1;
    }
    return cast(i32, h.vals[h.valptr[len] + code - h.mincode[len]]);
}

// --- Decoder state ----------------------------------------------------

private struct JComp {
    i32 id;
    i32 hsamp;
    i32 vsamp;
    i32 tq;        // quant table id
    i32 td;        // DC huffman table id (from SOS)
    i32 ta;        // AC huffman table id (from SOS)
    i32 dc_pred;
    f32* plane;    // MCU-padded component plane (level-shifted, clamped 0..255)
    i32 pw;        // plane width  (mcux * hsamp * 8)
    i32 ph;        // plane height (mcuy * vsamp * 8)
    i32* coef;     // progressive: bwpad*bhpad blocks of 64 coefficients
                   // (null in baseline — blocks IDCT immediately)
    i32 bwpad;     // block grid across, MCU-padded (mcux * hsamp)
    i32 bhpad;     // block grid down,  MCU-padded (mcuy * vsamp)
    i32 bwn;       // valid block grid across: ceil(ceil(w*hsamp/hmax) / 8)
    i32 bhn;       // valid block grid down (non-interleaved scans use these)
}

private struct JDec {
    u8* data;
    i32 len;
    i32 w;
    i32 h;
    i32 ncomp;
    JComp[3] comp;
    i32 hmax;
    i32 vmax;
    i32 mcux;
    i32 mcuy;
    i32 restart_interval;
    i32 frame_type;        // SOF marker (0xC0 baseline)
    bool got_sof;
    i32[256] qraw;         // 4 tables x 64, natural order
    bool[4] qpresent;
    f32[256] qt_f;         // AAN-prescaled dequant tables (built at SOS)
    JHuff[4] hdc;
    JHuff[4] hac;
}

private void jd_free_planes(JDec* d) {
    for i32 i = 0; i < d.ncomp; i++ {
        if d.comp[i].plane != null {
            free(d.comp[i].plane);
            d.comp[i].plane = null;
        }
        if d.comp[i].coef != null {
            free(d.comp[i].coef);
            d.comp[i].coef = null;
        }
    }
}

// --- Dequant + IDCT (AAN float, vertical-SIMD) --------------------------
// Same flow graph as libjpeg jidctflt, lane-ified: each f32x8 holds one
// row of the block (8 columns in lanes), so the 1D transform runs on all
// 8 columns at once with zero shuffles. The 0.125 final descale and the
// per-coefficient AAN factors are folded into qt. Output is
// level-shifted (+128) and clamped to 0..255.
// Portable: native ymm under --target *-avx2, 2x128 elsewhere.

// One 1D inverse-AAN pass along the vector index (between rows).
// in/out are row-major f32[64]; lanes carry the orthogonal axis.
private void jidct_pass8(f32* in, f32* out) {
    f32x8 i0 = f32x8_load(in);
    f32x8 i1 = f32x8_load(in + 8);
    f32x8 i2 = f32x8_load(in + 16);
    f32x8 i3 = f32x8_load(in + 24);
    f32x8 i4 = f32x8_load(in + 32);
    f32x8 i5 = f32x8_load(in + 40);
    f32x8 i6 = f32x8_load(in + 48);
    f32x8 i7 = f32x8_load(in + 56);

    f32x8 c1414 = f32x8_splat(1.414213562f);

    // Even part
    f32x8 tmp10 = f32x8_add(i0, i4);
    f32x8 tmp11 = f32x8_sub(i0, i4);
    f32x8 tmp13 = f32x8_add(i2, i6);
    f32x8 tmp12 = f32x8_sub(f32x8_mul(f32x8_sub(i2, i6), c1414), tmp13);

    f32x8 e0 = f32x8_add(tmp10, tmp13);
    f32x8 e3 = f32x8_sub(tmp10, tmp13);
    f32x8 e1 = f32x8_add(tmp11, tmp12);
    f32x8 e2 = f32x8_sub(tmp11, tmp12);

    // Odd part
    f32x8 z13 = f32x8_add(i5, i3);
    f32x8 z10 = f32x8_sub(i5, i3);
    f32x8 z11 = f32x8_add(i1, i7);
    f32x8 z12 = f32x8_sub(i1, i7);

    f32x8 t7 = f32x8_add(z11, z13);
    f32x8 t11 = f32x8_mul(f32x8_sub(z11, z13), c1414);

    f32x8 z5 = f32x8_mul(f32x8_add(z10, z12), f32x8_splat(1.847759065f));
    f32x8 t10 = f32x8_sub(f32x8_mul(z12, f32x8_splat(1.082392200f)), z5);
    f32x8 t12 = f32x8_add(f32x8_mul(z10, f32x8_splat(-2.613125930f)), z5);

    f32x8 t6 = f32x8_sub(t12, t7);
    f32x8 t5 = f32x8_sub(t11, t6);
    f32x8 t4 = f32x8_add(t10, t5);

    f32x8_store(out,      f32x8_add(e0, t7));
    f32x8_store(out + 56, f32x8_sub(e0, t7));
    f32x8_store(out + 8,  f32x8_add(e1, t6));
    f32x8_store(out + 48, f32x8_sub(e1, t6));
    f32x8_store(out + 16, f32x8_add(e2, t5));
    f32x8_store(out + 40, f32x8_sub(e2, t5));
    f32x8_store(out + 32, f32x8_add(e3, t4));
    f32x8_store(out + 24, f32x8_sub(e3, t4));
}

// Scalar 8x8 transpose. Wide types have no lane access, so the swap
// between the two 1D passes stays scalar — 64 moves against ~70 vector
// butterfly ops.
private void jpeg_transpose8(f32* src, f32* dst) {
    for i32 y = 0; y < 8; y++ {
        for i32 x = 0; x < 8; x++ {
            *(dst + x * 8 + y) = *(src + y * 8 + x);
        }
    }
}

private void jpeg_idct8x8(i32* coef, f32* qt, f32* out_plane, i32 stride, i32 last_nz) {
    // DC-only fast path: every AC coefficient is zero (very common for
    // 4:2:0 chroma) — skip both passes.
    if last_nz == 0 {
        f32 dcv = cast(f32, coef[0]) * qt[0] + 128.0f;
        if dcv < 0.0f { dcv = 0.0f; }
        if dcv > 255.0f { dcv = 255.0f; }
        for i32 y = 0; y < 8; y++ {
            f32* row = out_plane + y * stride;
            for i32 x = 0; x < 8; x++ { *(row + x) = dcv; }
        }
        return;
    }

    // Dequant: 8 rows of i32x8 -> f32x8 -> multiply by prescaled table.
    noinit f32[64] deq;
    for i32 k = 0; k < 8; k++ {
        f32x8 c = i32x8_to_f32x8(i32x8_load(coef + k * 8));
        f32x8_store(&deq[k * 8], f32x8_mul(c, f32x8_load(qt + k * 8)));
    }

    // Pass 1 transforms along y (lanes = x); transpose; pass 2
    // transforms along x (lanes = y).
    noinit f32[64] ws;
    jidct_pass8(&deq[0], &ws[0]);
    noinit f32[64] wt;
    jpeg_transpose8(&ws[0], &wt[0]);
    noinit f32[64] o;
    jidct_pass8(&wt[0], &o[0]);

    // Level shift + clamp, vectorized.
    f32x8 c128 = f32x8_splat(128.0f);
    f32x8 cmin = f32x8_splat(0.0f);
    f32x8 cmax = f32x8_splat(255.0f);
    for i32 k = 0; k < 8; k++ {
        f32x8 v = f32x8_add(f32x8_load(&o[k * 8]), c128);
        f32x8_store(&o[k * 8], f32x8_min(f32x8_max(v, cmin), cmax));
    }

    // o is transposed ([x][y]); the strided plane store is the second
    // transpose for free.
    for i32 y = 0; y < 8; y++ {
        f32* row = out_plane + y * stride;
        for i32 x = 0; x < 8; x++ {
            *(row + x) = o[x * 8 + y];
        }
    }
}

// --- Block entropy decode ---------------------------------------------
// Decodes one 8x8 block into coef64 (natural order). Returns the last
// nonzero zigzag index, or -1 on error.

private i32 jd_decode_block(JBits* b, JHuff* hdc, JHuff* hac, i32* dc_pred, i32* coef64) {
    for i32 i = 0; i < 64; i++ { coef64[i] = 0; }

    i32 t = jh_decode(b, hdc);
    if t < 0 || t > 11 { return -1; }
    i32 diff = 0;
    if t > 0 { diff = jb_receive_extend(b, t); }
    i32 dc = *dc_pred + diff;
    *dc_pred = dc;
    coef64[0] = dc;

    i32 last_nz = 0;
    i32 k = 1;
    while k <= 63 {
        i32 rs = jh_decode(b, hac);
        if rs < 0 { return -1; }
        i32 r = rs >> 4;
        i32 s = rs & 15;
        if s == 0 {
            if r == 15 {   // ZRL: run of 16 zeros
                k = k + 16;
                continue;
            }
            break;          // EOB
        }
        k = k + r;
        if k > 63 { return -1; }
        coef64[cast(i32, jz_zigzag[k])] = jb_receive_extend(b, s);
        last_nz = k;
        k = k + 1;
    }
    return last_nz;
}

// --- Scan decode (baseline sequential, interleaved) --------------------

private bool jd_scan_baseline(JDec* d, i32 scan_pos, i32* out_pos) {
    JBits b;
    jb_init(&b, d.data, d.len, scan_pos);

    i32[64] coef;
    i32 mcu_count = 0;
    i32 rst_idx = 0;

    for i32 my = 0; my < d.mcuy; my++ {
        for i32 mx = 0; mx < d.mcux; mx++ {
            // Restart interval boundary
            if d.restart_interval > 0 && mcu_count > 0 &&
               mcu_count % d.restart_interval == 0 {
                if !jb_restart(&b, rst_idx) { return false; }
                rst_idx = rst_idx + 1;
                for i32 ci = 0; ci < d.ncomp; ci++ { d.comp[ci].dc_pred = 0; }
            }
            for i32 ci = 0; ci < d.ncomp; ci++ {
                JComp* c = &d.comp[ci];
                for i32 v = 0; v < c.vsamp; v++ {
                    for i32 hh = 0; hh < c.hsamp; hh++ {
                        i32 last_nz = jd_decode_block(&b, &d.hdc[c.td], &d.hac[c.ta],
                                                      &c.dc_pred, &coef[0]);
                        if last_nz < 0 { return false; }
                        i32 bx = (mx * c.hsamp + hh) * 8;
                        i32 by = (my * c.vsamp + v) * 8;
                        jpeg_idct8x8(&coef[0], &d.qt_f[c.tq * 64],
                                     c.plane + by * c.pw + bx, c.pw, last_nz);
                    }
                }
            }
            mcu_count = mcu_count + 1;
            // Strict truncation check: zero-fed bits mean the input ran
            // out mid-scan (unless we just finished the last MCU).
            if b.eof && b.marker == 0 &&
               !(my == d.mcuy - 1 && mx == d.mcux - 1) {
                return false;
            }
        }
    }
    *out_pos = b.pos;
    return true;
}

// --- Progressive scan decode (spec G.2, port of libjpeg jdphuff) -------
// Coefficients accumulate across scans in each component's coef buffer;
// dequant + IDCT happen once at EOI (jd_finish_progressive).

// DC scan data unit. First scan (ah==0): Huffman diff + EXTEND, shifted
// by the successive-approximation low bit. Refinement: one bit.
private bool jd_prog_dc_unit(JBits* b, JDec* d, JComp* c, i32* coef, i32 ah, i32 al) {
    if ah == 0 {
        i32 t = jh_decode(b, &d.hdc[c.td]);
        if t < 0 || t > 11 { return false; }
        i32 diff = 0;
        if t > 0 { diff = jb_receive_extend(b, t); }
        c.dc_pred = c.dc_pred + diff;
        coef[0] = c.dc_pred << al;
    }
    else {
        if jb_get(b, 1) != 0 {
            coef[0] = coef[0] | (1 << al);
        }
    }
    return true;
}

// AC first scan (ah==0) for one block's band [ss..se]. eobrun counts
// whole blocks whose band is all zero.
private bool jd_prog_ac_first(JBits* b, JHuff* hac, i32* coef, i32 ss, i32 se,
                              i32 al, i32* eobrun) {
    if *eobrun > 0 {
        *eobrun = *eobrun - 1;
        return true;
    }
    i32 k = ss;
    while k <= se {
        i32 rs = jh_decode(b, hac);
        if rs < 0 { return false; }
        i32 r = rs >> 4;
        i32 s = rs & 15;
        if s == 0 {
            if r == 15 {
                k = k + 16;   // ZRL
                continue;
            }
            // EOBn: run of (1<<r) + appended bits all-zero bands,
            // including this one.
            *eobrun = (1 << r) - 1;
            if r > 0 { *eobrun = *eobrun + jb_get(b, r); }
            break;
        }
        k = k + r;
        if k > se { return false; }
        coef[cast(i32, jz_zigzag[k])] = jb_receive_extend(b, s) << al;
        k = k + 1;
    }
    return true;
}

// AC refinement scan (ah==al+1) for one block's band. Already-nonzero
// coefficients receive correction bits — including inside EOB runs.
private bool jd_prog_ac_refine(JBits* b, JHuff* hac, i32* coef, i32 ss, i32 se,
                               i32 al, i32* eobrun) {
    i32 p1 = 1 << al;
    i32 m1 = 0 - (1 << al);
    i32 k = ss;
    if *eobrun == 0 {
        while k <= se {
            i32 rs = jh_decode(b, hac);
            if rs < 0 { return false; }
            i32 r = rs >> 4;
            i32 s = rs & 15;
            i32 newval = 0;
            if s == 0 {
                if r != 15 {
                    *eobrun = 1 << r;
                    if r > 0 { *eobrun = *eobrun + jb_get(b, r); }
                    break;
                }
                // r == 15: ZRL — skip 16 zero-history coefficients.
            }
            else {
                // s is always 1 in a refinement scan.
                if jb_get(b, 1) != 0 { newval = p1; } else { newval = m1; }
            }
            // Advance over r zero-history coefficients, appending
            // correction bits to already-nonzero ones along the way.
            while k <= se {
                i32 zz = cast(i32, jz_zigzag[k]);
                if coef[zz] != 0 {
                    if jb_get(b, 1) != 0 {
                        if (coef[zz] & p1) == 0 {
                            if coef[zz] >= 0 { coef[zz] = coef[zz] + p1; }
                            else { coef[zz] = coef[zz] + m1; }
                        }
                    }
                }
                else {
                    if r == 0 { break; }
                    r = r - 1;
                }
                k = k + 1;
            }
            if newval != 0 && k <= se {
                coef[cast(i32, jz_zigzag[k])] = newval;
            }
            k = k + 1;
        }
    }
    if *eobrun > 0 {
        // Inside an EOB run: correction bits for every remaining
        // nonzero coefficient in the band.
        while k <= se {
            i32 zz = cast(i32, jz_zigzag[k]);
            if coef[zz] != 0 {
                if jb_get(b, 1) != 0 {
                    if (coef[zz] & p1) == 0 {
                        if coef[zz] >= 0 { coef[zz] = coef[zz] + p1; }
                        else { coef[zz] = coef[zz] + m1; }
                    }
                }
            }
            k = k + 1;
        }
        *eobrun = *eobrun - 1;
    }
    return true;
}

// One progressive scan. scomp[0..ns-1] are frame-component indices.
private bool jd_scan_progressive(JDec* d, i32* scomp, i32 ns, i32 ss, i32 se,
                                 i32 ah, i32 al, i32 scan_pos, i32* out_pos) {
    JBits b;
    jb_init(&b, d.data, d.len, scan_pos);
    i32 eobrun = 0;
    i32 rst_idx = 0;
    i32 unit = 0;
    for i32 i = 0; i < d.ncomp; i++ { d.comp[i].dc_pred = 0; }

    bool ok = true;
    if ns > 1 {
        // Interleaved (DC scans only): MCU order, like baseline.
        for i32 my = 0; my < d.mcuy; my++ {
            for i32 mx = 0; mx < d.mcux; mx++ {
                if d.restart_interval > 0 && unit > 0 &&
                   unit % d.restart_interval == 0 {
                    if !jb_restart(&b, rst_idx) { return false; }
                    rst_idx = rst_idx + 1;
                    eobrun = 0;
                    for i32 i = 0; i < d.ncomp; i++ { d.comp[i].dc_pred = 0; }
                }
                for i32 si = 0; si < ns; si++ {
                    JComp* c = &d.comp[scomp[si]];
                    for i32 v = 0; v < c.vsamp; v++ {
                        for i32 hh = 0; hh < c.hsamp; hh++ {
                            i32 bx = mx * c.hsamp + hh;
                            i32 by = my * c.vsamp + v;
                            i32* coef = c.coef + (by * c.bwpad + bx) * 64;
                            if !jd_prog_dc_unit(&b, d, c, coef, ah, al) { return false; }
                        }
                    }
                }
                unit = unit + 1;
                if b.eof && b.marker == 0 &&
                   !(my == d.mcuy - 1 && mx == d.mcux - 1) {
                    return false;
                }
            }
        }
    }
    else {
        // Non-interleaved: raster over the component's valid blocks.
        JComp* c = &d.comp[scomp[0]];
        for i32 by = 0; by < c.bhn; by++ {
            for i32 bx = 0; bx < c.bwn; bx++ {
                if d.restart_interval > 0 && unit > 0 &&
                   unit % d.restart_interval == 0 {
                    if !jb_restart(&b, rst_idx) { return false; }
                    rst_idx = rst_idx + 1;
                    eobrun = 0;
                    c.dc_pred = 0;
                }
                i32* coef = c.coef + (by * c.bwpad + bx) * 64;
                if ss == 0 {
                    ok = jd_prog_dc_unit(&b, d, c, coef, ah, al);
                }
                else if ah == 0 {
                    ok = jd_prog_ac_first(&b, &d.hac[c.ta], coef, ss, se, al, &eobrun);
                }
                else {
                    ok = jd_prog_ac_refine(&b, &d.hac[c.ta], coef, ss, se, al, &eobrun);
                }
                if !ok { return false; }
                unit = unit + 1;
                if b.eof && b.marker == 0 &&
                   !(by == c.bhn - 1 && bx == c.bwn - 1) {
                    return false;
                }
            }
        }
    }

    // Push the terminating marker back to the caller's parser.
    if b.marker != 0 {
        *out_pos = b.pos - 2;
    }
    else {
        *out_pos = b.pos;
    }
    return true;
}

// EOI for a progressive frame: dequant + IDCT every block of every
// component from the accumulated coefficients.
private void jd_finish_progressive(JDec* d) {
    for i32 ci = 0; ci < d.ncomp; ci++ {
        JComp* c = &d.comp[ci];
        f32* qt = &d.qt_f[c.tq * 64];
        for i32 by = 0; by < c.bhpad; by++ {
            for i32 bx = 0; bx < c.bwpad; bx++ {
                i32* coef = c.coef + (by * c.bwpad + bx) * 64;
                i32 last_nz = 0;
                for i32 k = 63; k >= 1; k-- {
                    if coef[cast(i32, jz_zigzag[k])] != 0 { last_nz = k; break; }
                }
                jpeg_idct8x8(coef, qt, c.plane + by * 8 * c.pw + bx * 8, c.pw, last_nz);
            }
        }
    }
}

// --- Upsample + color convert -----------------------------------------

// Build one full-resolution chroma row for output row y using a
// triangle (bilinear) filter — libjpeg's "fancy upsampling". For a 2:1
// axis the nearer source sample gets weight 3, the farther 1. Edges
// clamp. `tmp` is a caller-provided scratch row (>= valid chroma
// width). Falls back to plain copies on 1:1 axes.
private void jd_upsample_row(JComp* c, i32 y, i32 w, i32 h, i32 hmax, i32 vmax,
                             f32* tmp, f32* dst) {
    // Valid (non-padding) chroma extents.
    i32 cwv = (w * c.hsamp + hmax - 1) / hmax;
    i32 chv = (h * c.vsamp + vmax - 1) / vmax;

    // Vertical: blend the two nearest chroma rows 3:1, or pass through.
    f32* vrow = tmp;
    if c.vsamp == vmax {
        vrow = c.plane + y * c.pw;
    }
    else {
        i32 r0 = y >> 1;
        i32 r1 = r0 + 1;
        if (y & 1) == 0 { r1 = r0 - 1; }
        if r1 < 0 { r1 = 0; }
        if r1 > chv - 1 { r1 = chv - 1; }
        f32* s0 = c.plane + r0 * c.pw;
        f32* s1 = c.plane + r1 * c.pw;
        for i32 x = 0; x < cwv; x++ {
            *(tmp + x) = (*(s0 + x) * 3.0f + *(s1 + x)) * 0.25f;
        }
    }

    // Horizontal: expand 2:1 with 3:1 neighbor blend, or copy.
    if c.hsamp == hmax {
        for i32 x = 0; x < w; x++ { *(dst + x) = *(vrow + x); }
        return;
    }
    for i32 x = 0; x < cwv; x++ {
        f32 cc = *(vrow + x);
        f32 lf = cc;
        f32 rt = cc;
        if x > 0 { lf = *(vrow + x - 1); }
        if x < cwv - 1 { rt = *(vrow + x + 1); }
        i32 ox = x * 2;
        if ox < w { *(dst + ox) = (cc * 3.0f + lf) * 0.25f; }
        if ox + 1 < w { *(dst + ox + 1) = (cc * 3.0f + rt) * 0.25f; }
    }
}

private void jd_color_convert(JDec* d, u8* pixels) {
    i32 w = d.w;
    i32 h = d.h;
    JComp* cy = &d.comp[0];
    i32 w8 = w & ~7;   // 8-wide vector body; scalar tail below

    if d.ncomp == 1 {
        for i32 y = 0; y < h; y++ {
            f32* yrow = cy.plane + y * cy.pw;
            u8* dst = pixels + y * w * 4;
            // Plane values are already clamped to 0..255 at IDCT exit;
            // just round 8 at a time.
            noinit i32[8] gi;
            for i32 x = 0; x < w8; x = x + 8 {
                i32x8_store(&gi[0], f32x8_to_i32x8(f32x8_load(yrow + x)));
                for i32 i = 0; i < 8; i++ {
                    u8 g = cast(u8, gi[i]);
                    *(dst + (x + i) * 4 + 0) = g;
                    *(dst + (x + i) * 4 + 1) = g;
                    *(dst + (x + i) * 4 + 2) = g;
                    *(dst + (x + i) * 4 + 3) = 255;
                }
            }
            for i32 x = w8; x < w; x++ {
                i32 g = cast(i32, *(yrow + x) + 0.5f);
                if g > 255 { g = 255; }
                *(dst + x * 4 + 0) = cast(u8, g);
                *(dst + x * 4 + 1) = cast(u8, g);
                *(dst + x * 4 + 2) = cast(u8, g);
                *(dst + x * 4 + 3) = 255;
            }
        }
        return;
    }

    JComp* ccb = &d.comp[1];
    JComp* ccr = &d.comp[2];
    // Reusable upsampled chroma rows + vertical-blend scratch. The
    // triangle filter stays scalar (neighbor access has no f32x8
    // shuffle); it feeds the vector color math below.
    f32* cb_row = alloc<f32>(w);
    f32* cr_row = alloc<f32>(w);
    f32* ups_tmp = alloc<f32>(w);
    defer free(cb_row);
    defer free(cr_row);
    defer free(ups_tmp);

    f32x8 c128 = f32x8_splat(128.0f);
    f32x8 cmin = f32x8_splat(0.0f);
    f32x8 cmax = f32x8_splat(255.0f);
    f32x8 c1402 = f32x8_splat(1.402f);
    f32x8 c0344 = f32x8_splat(0.344136f);
    f32x8 c0714 = f32x8_splat(0.714136f);
    f32x8 c1772 = f32x8_splat(1.772f);

    for i32 y = 0; y < h; y++ {
        f32* yrow = cy.plane + y * cy.pw;
        jd_upsample_row(ccb, y, w, h, d.hmax, d.vmax, ups_tmp, cb_row);
        jd_upsample_row(ccr, y, w, h, d.hmax, d.vmax, ups_tmp, cr_row);

        u8* dst = pixels + y * w * 4;
        // BT.601: 8 pixels per iteration.
        noinit i32[8] ri;
        noinit i32[8] gi;
        noinit i32[8] bi;
        for i32 x = 0; x < w8; x = x + 8 {
            f32x8 vy = f32x8_load(yrow + x);
            f32x8 vcb = f32x8_sub(f32x8_load(cb_row + x), c128);
            f32x8 vcr = f32x8_sub(f32x8_load(cr_row + x), c128);
            f32x8 vr = f32x8_add(vy, f32x8_mul(vcr, c1402));
            f32x8 vg = f32x8_sub(vy, f32x8_add(f32x8_mul(vcb, c0344), f32x8_mul(vcr, c0714)));
            f32x8 vb = f32x8_add(vy, f32x8_mul(vcb, c1772));
            vr = f32x8_min(f32x8_max(vr, cmin), cmax);
            vg = f32x8_min(f32x8_max(vg, cmin), cmax);
            vb = f32x8_min(f32x8_max(vb, cmin), cmax);
            i32x8_store(&ri[0], f32x8_to_i32x8(vr));
            i32x8_store(&gi[0], f32x8_to_i32x8(vg));
            i32x8_store(&bi[0], f32x8_to_i32x8(vb));
            for i32 i = 0; i < 8; i++ {
                *(dst + (x + i) * 4 + 0) = cast(u8, ri[i]);
                *(dst + (x + i) * 4 + 1) = cast(u8, gi[i]);
                *(dst + (x + i) * 4 + 2) = cast(u8, bi[i]);
                *(dst + (x + i) * 4 + 3) = 255;
            }
        }
        for i32 x = w8; x < w; x++ {
            f32 yv = *(yrow + x);
            f32 cb = *(cb_row + x) - 128.0f;
            f32 cr = *(cr_row + x) - 128.0f;
            i32 r = cast(i32, yv + 1.402f * cr + 0.5f);
            i32 g = cast(i32, yv - 0.344136f * cb - 0.714136f * cr + 0.5f);
            i32 bl = cast(i32, yv + 1.772f * cb + 0.5f);
            if r < 0 { r = 0; }
            if r > 255 { r = 255; }
            if g < 0 { g = 0; }
            if g > 255 { g = 255; }
            if bl < 0 { bl = 0; }
            if bl > 255 { bl = 255; }
            *(dst + x * 4 + 0) = cast(u8, r);
            *(dst + x * 4 + 1) = cast(u8, g);
            *(dst + x * 4 + 2) = cast(u8, bl);
            *(dst + x * 4 + 3) = 255;
        }
    }
}

// --- Marker-level decode ------------------------------------------------

private u32 jd_read_u16(u8* p) {
    return (cast(u32, *(p + 0)) << 8) | cast(u32, *(p + 1));
}

// Error exit that releases any planes/coefficient buffers already
// allocated — progressive parsing continues past the first SOS, so
// later marker errors must clean up.
private JpegImage jd_fail(JDec* d, u8* msg) {
    jd_free_planes(d);
    return jpeg_error(msg);
}

// Decode JPEG from raw bytes in memory.
JpegImage jpeg_decode(u8* data, i64 nbytes) {
    if nbytes > 2147483647 { return jpeg_error("image larger than 2 GB"); }
    i32 len = cast(i32, nbytes);
    if len < 4 { return jpeg_error("invalid SOI marker"); }
    if cast(i32, *(data + 0)) != 255 || cast(i32, *(data + 1)) != 216 {
        return jpeg_error("invalid SOI marker");
    }

    JDec d;
    d.data = data;
    d.len = len;
    d.ncomp = 0;
    d.restart_interval = 0;
    d.got_sof = false;
    for i32 i = 0; i < 4; i++ {
        d.qpresent[i] = false;
        d.hdc[i].present = false;
        d.hac[i].present = false;
    }
    for i32 i = 0; i < 3; i++ {
        d.comp[i].plane = null;
        d.comp[i].coef = null;
        d.comp[i].dc_pred = 0;
    }

    bool scan_done = false;
    bool planes_alloced = false;
    i32 nscans = 0;
    i32 pos = 2;
    while !scan_done {
        // Find the next marker (skip fill bytes).
        if pos >= len { return jd_fail(&d, "missing SOS marker"); }
        if cast(i32, *(data + pos)) != 255 { return jd_fail(&d, "truncated marker segment"); }
        while pos < len && cast(i32, *(data + pos)) == 255 { pos = pos + 1; }
        if pos >= len { return jd_fail(&d, "missing SOS marker"); }
        i32 m = cast(i32, *(data + pos));
        pos = pos + 1;

        if m == 216 { continue; }            // stray SOI: ignore
        if m == 217 {
            // EOI: end of a progressive frame — reconstruct from the
            // accumulated coefficients. Before any scan it's an error.
            if d.frame_type == 194 && nscans > 0 {
                jd_finish_progressive(&d);
                scan_done = true;
                continue;
            }
            return jd_fail(&d, "missing SOS marker");
        }
        if m == 1 { continue; }              // TEM: standalone
        if m >= 208 && m <= 215 { continue; }  // RSTn outside scan: ignore

        // All remaining markers carry a 16-bit length.
        if pos + 2 > len { return jd_fail(&d, "truncated marker segment"); }
        i32 seglen = cast(i32, jd_read_u16(data + pos));
        if seglen < 2 || pos + seglen > len { return jd_fail(&d, "truncated marker segment"); }
        u8* seg = data + pos + 2;
        i32 segdata = seglen - 2;

        if m == 219 {
            // DQT — may hold several tables.
            i32 sp = 0;
            while sp < segdata {
                i32 pq = cast(i32, *(seg + sp)) >> 4;
                i32 tq = cast(i32, *(seg + sp)) & 15;
                sp = sp + 1;
                if tq > 3 || pq > 1 { return jd_fail(&d, "invalid quantization table"); }
                i32 n = 64;
                if pq == 1 { n = 128; }
                if sp + n > segdata { return jd_fail(&d, "invalid quantization table"); }
                for i32 i = 0; i < 64; i++ {
                    i32 qv = 0;
                    if pq == 1 {
                        qv = cast(i32, jd_read_u16(seg + sp + i * 2));
                    }
                    else {
                        qv = cast(i32, *(seg + sp + i));
                    }
                    d.qraw[tq * 64 + cast(i32, jz_zigzag[i])] = qv;
                }
                d.qpresent[tq] = true;
                sp = sp + n;
            }
        }
        else if m == 196 {
            // DHT — may hold several tables.
            i32 sp = 0;
            while sp < segdata {
                if sp + 17 > segdata { return jd_fail(&d, "invalid huffman table"); }
                i32 tc = cast(i32, *(seg + sp)) >> 4;
                i32 th = cast(i32, *(seg + sp)) & 15;
                if tc > 1 || th > 3 { return jd_fail(&d, "invalid huffman table"); }
                u8[17] bits;
                bits[0] = 0;
                i32 total = 0;
                for i32 i = 1; i <= 16; i++ {
                    bits[i] = *(seg + sp + i);
                    total = total + cast(i32, bits[i]);
                }
                if total > 256 || sp + 17 + total > segdata {
                    return jd_fail(&d, "invalid huffman table");
                }
                JHuff* h = &d.hdc[th];
                if tc == 1 { h = &d.hac[th]; }
                if !jh_build(h, &bits[0], seg + sp + 17, total) {
                    return jd_fail(&d, "invalid huffman table");
                }
                sp = sp + 17 + total;
            }
        }
        else if m == 192 || m == 194 {
            // SOF0 (baseline) / SOF2 (progressive) — shared frame header.
            if d.got_sof { return jd_fail(&d, "invalid scan header"); }
            if segdata < 6 { return jd_fail(&d, "truncated marker segment"); }
            i32 prec = cast(i32, *(seg + 0));
            if prec != 8 { return jd_fail(&d, "unsupported precision (only 8-bit)"); }
            d.h = cast(i32, jd_read_u16(seg + 1));
            d.w = cast(i32, jd_read_u16(seg + 3));
            d.ncomp = cast(i32, *(seg + 5));
            if d.w <= 0 || d.h <= 0 { return jd_fail(&d, "invalid image dimensions"); }
            if d.w > 32768 || d.h > 32768 { return jd_fail(&d, "image too large (max 32768x32768)"); }
            if d.ncomp != 1 && d.ncomp != 3 { return jd_fail(&d, "unsupported component count"); }
            if segdata < 6 + d.ncomp * 3 { return jd_fail(&d, "truncated marker segment"); }
            d.hmax = 1;
            d.vmax = 1;
            for i32 i = 0; i < d.ncomp; i++ {
                JComp* c = &d.comp[i];
                c.id = cast(i32, *(seg + 6 + i * 3));
                i32 hv = cast(i32, *(seg + 7 + i * 3));
                c.hsamp = hv >> 4;
                c.vsamp = hv & 15;
                c.tq = cast(i32, *(seg + 8 + i * 3));
                if c.hsamp < 1 || c.hsamp > 2 || c.vsamp < 1 || c.vsamp > 2 {
                    return jd_fail(&d, "unsupported sampling factors");
                }
                if i > 0 && (c.hsamp != 1 || c.vsamp != 1) {
                    return jd_fail(&d, "unsupported sampling factors");
                }
                if c.tq > 3 { return jd_fail(&d, "invalid quantization table"); }
                if c.hsamp > d.hmax { d.hmax = c.hsamp; }
                if c.vsamp > d.vmax { d.vmax = c.vsamp; }
            }
            d.frame_type = m;
            d.got_sof = true;
        }
        else if m == 193 || m == 195 || (m >= 197 && m <= 199) ||
                  (m >= 201 && m <= 203) || (m >= 205 && m <= 207) {
            return jd_fail(&d, "unsupported SOF marker (only baseline SOF0 / progressive SOF2)");
        }
        else if m == 221 {
            // DRI
            if segdata < 2 { return jd_fail(&d, "truncated marker segment"); }
            d.restart_interval = cast(i32, jd_read_u16(seg));
        }
        else if m == 218 {
            // SOS
            if !d.got_sof { return jd_fail(&d, "invalid scan header"); }
            if segdata < 1 { return jd_fail(&d, "invalid scan header"); }
            bool progressive = d.frame_type == 194;
            i32 ns = cast(i32, *(seg + 0));
            if ns < 1 || ns > 3 || segdata < 1 + ns * 2 + 3 {
                return jd_fail(&d, "invalid scan header");
            }
            if !progressive && ns != d.ncomp {
                return jd_fail(&d, "invalid scan header");
            }
            i32[3] scomp;
            for i32 i = 0; i < ns; i++ {
                i32 cid = cast(i32, *(seg + 1 + i * 2));
                i32 tt = cast(i32, *(seg + 2 + i * 2));
                // Match scan component to frame component by id.
                i32 found = -1;
                for i32 j = 0; j < d.ncomp; j++ {
                    if d.comp[j].id == cid { found = j; break; }
                }
                if found < 0 { return jd_fail(&d, "invalid scan header"); }
                scomp[i] = found;
                d.comp[found].td = tt >> 4;
                d.comp[found].ta = tt & 15;
                if d.comp[found].td > 3 || d.comp[found].ta > 3 {
                    return jd_fail(&d, "invalid scan header");
                }
            }
            // Spectral selection / successive approximation.
            i32 ss = cast(i32, *(seg + 1 + ns * 2));
            i32 se = cast(i32, *(seg + 2 + ns * 2));
            i32 ahal = cast(i32, *(seg + 3 + ns * 2));
            i32 ah = ahal >> 4;
            i32 al = ahal & 15;
            if !progressive {
                if ss != 0 || se != 63 || ahal != 0 {
                    return jd_fail(&d, "invalid scan header");
                }
            }
            else {
                if ss == 0 {
                    if se != 0 { return jd_fail(&d, "invalid scan header"); }
                }
                else {
                    // AC scans are single-component by spec.
                    if ns != 1 || se < ss || se > 63 {
                        return jd_fail(&d, "invalid scan header");
                    }
                }
                if al > 13 || (ah != 0 && ah != al + 1) {
                    return jd_fail(&d, "invalid scan header");
                }
            }
            // Verify the tables this scan needs exist. (DC refinement
            // scans read raw bits, no Huffman table.)
            for i32 i = 0; i < ns; i++ {
                JComp* c = &d.comp[scomp[i]];
                if !progressive {
                    if !d.qpresent[c.tq] { return jd_fail(&d, "invalid scan header"); }
                    if !d.hdc[c.td].present || !d.hac[c.ta].present {
                        return jd_fail(&d, "invalid scan header");
                    }
                }
                else {
                    if ss == 0 && ah == 0 && !d.hdc[c.td].present {
                        return jd_fail(&d, "invalid scan header");
                    }
                    if ss > 0 && !d.hac[c.ta].present {
                        return jd_fail(&d, "invalid scan header");
                    }
                }
            }

            // Build AAN-prescaled dequant tables (idempotent).
            for i32 t = 0; t < 4; t++ {
                if d.qpresent[t] {
                    for i32 row = 0; row < 8; row++ {
                        for i32 col = 0; col < 8; col++ {
                            d.qt_f[t * 64 + row * 8 + col] =
                                cast(f32, d.qraw[t * 64 + row * 8 + col]) *
                                jaan_factor(row) * jaan_factor(col) * 0.125f;
                        }
                    }
                }
            }

            // First scan: allocate MCU-padded planes (+ coefficient
            // buffers for progressive accumulation).
            if !planes_alloced {
                planes_alloced = true;
                d.mcux = (d.w + d.hmax * 8 - 1) / (d.hmax * 8);
                d.mcuy = (d.h + d.vmax * 8 - 1) / (d.vmax * 8);
                for i32 i = 0; i < d.ncomp; i++ {
                    JComp* c = &d.comp[i];
                    c.pw = d.mcux * c.hsamp * 8;
                    c.ph = d.mcuy * c.vsamp * 8;
                    c.plane = alloc<f32>(c.pw * c.ph);
                    c.dc_pred = 0;
                    c.bwpad = d.mcux * c.hsamp;
                    c.bhpad = d.mcuy * c.vsamp;
                    i32 cpixw = (d.w * c.hsamp + d.hmax - 1) / d.hmax;
                    i32 cpixh = (d.h * c.vsamp + d.vmax - 1) / d.vmax;
                    c.bwn = (cpixw + 7) / 8;
                    c.bhn = (cpixh + 7) / 8;
                    if progressive {
                        i32 ncoef = c.bwpad * c.bhpad * 64;
                        c.coef = alloc<i32>(ncoef);
                        memset(c.coef, 0, cast(i64, ncoef) * 4);
                    }
                }
            }

            i32 after_pos = 0;
            if !progressive {
                if !jd_scan_baseline(&d, pos + seglen, &after_pos) {
                    return jd_fail(&d, "truncated entropy data");
                }
                scan_done = true;
                pos = after_pos;
                continue;
            }
            if !jd_scan_progressive(&d, &scomp[0], ns, ss, se, ah, al,
                                    pos + seglen, &after_pos) {
                return jd_fail(&d, "truncated entropy data");
            }
            nscans = nscans + 1;
            pos = after_pos;
            continue;
        }
        else {
            // APPn / COM / other: skip.
        }
        pos = pos + seglen;
    }

    // Convert planes to RGBA8.
    i32 out_size = d.w * d.h * 4;
    u8* pixels = alloc<u8>(out_size);
    jd_color_convert(&d, pixels);
    jd_free_planes(&d);

    JpegImage result;
    result.pixels = pixels;
    result.width = d.w;
    result.height = d.h;
    return result;
}

// Load JPEG from file path.
JpegImage jpeg_load(str path) {
    FileData fd = file_read(path);
    if fd.data == null {
        eprint("jpeg: cannot open '{}'\n", path);
        JpegImage r;
        r.pixels = null;
        r.width = 0;
        r.height = 0;
        return r;
    }
    JpegImage result = jpeg_decode(fd.data, fd.len);
    free(fd.data);
    return result;
}

// ====================== Encoder ======================================
// 4:2:0 subsampling, quality 1-100 (clamped), standard Annex-K
// quantization (quality-scaled) + Huffman tables, JFIF APP0 header.

// --- MSB-first bit writer with 0xFF byte stuffing ----------------------

private struct JBitsW {
    u8* dst;
    i32 dstlen;
    i32 dstpos;
    u32 bitbuf;
    i32 bitcnt;
    bool overflow;
}

private void jw_init(JBitsW* w, u8* dst, i32 dstlen) {
    w.dst = dst;
    w.dstlen = dstlen;
    w.dstpos = 0;
    w.bitbuf = 0;
    w.bitcnt = 0;
    w.overflow = false;
}

private void jw_byte(JBitsW* w, i32 b) {
    if w.overflow { return; }
    if w.dstpos >= w.dstlen { w.overflow = true; return; }
    *(w.dst + w.dstpos) = cast(u8, b & 255);
    w.dstpos = w.dstpos + 1;
}

// Append nbits of val, MSB-first. A 0xFF data byte gets a stuffed 0x00.
private void jw_bits(JBitsW* w, i32 val, i32 nbits) {
    if nbits == 0 { return; }
    w.bitbuf = (w.bitbuf << cast(u32, nbits)) |
               (cast(u32, val) & ((cast(u32, 1) << cast(u32, nbits)) - 1));
    w.bitcnt = w.bitcnt + nbits;
    while w.bitcnt >= 8 {
        i32 b = cast(i32, w.bitbuf >> cast(u32, w.bitcnt - 8)) & 255;
        jw_byte(w, b);
        if b == 255 { jw_byte(w, 0); }   // stuffing
        w.bitcnt = w.bitcnt - 8;
    }
}

// Flush remaining bits, padding with 1s (spec convention).
private void jw_flush(JBitsW* w) {
    if w.bitcnt > 0 {
        i32 pad = 8 - w.bitcnt;
        jw_bits(w, (1 << pad) - 1, pad);
    }
}

// --- Encoder Huffman code tables (spec C.2) ----------------------------

private void je_build_codes(u8* bits, u8* vals, i32* code_out, i32* size_out) {
    i32 code = 0;
    i32 k = 0;
    for i32 len = 1; len <= 16; len++ {
        i32 n = cast(i32, *(bits + len));
        for i32 i = 0; i < n; i++ {
            i32 sym = cast(i32, *(vals + k));
            *(code_out + sym) = code;
            *(size_out + sym) = len;
            code = code + 1;
            k = k + 1;
        }
        code = code << 1;
    }
}

// Build an optimal Huffman table from symbol frequencies (libjpeg's
// jpeg_gen_optimal_table / spec K.2). freq is i32[257] and is
// destroyed; slot 256 is the reserved symbol that guarantees no real
// code is all ones. Code lengths are limited to 16 bits by the
// standard adjustment loop. Outputs spec BITS[1..16] + HUFFVAL.
private void je_optimal_table(i32* freq, u8* bits_out, u8* vals_out, i32* nvals_out) {
    noinit i32[257] codesize;
    noinit i32[257] others;
    noinit i32[33] bits;
    for i32 i = 0; i < 257; i++ {
        codesize[i] = 0;
        others[i] = -1;
    }
    for i32 i = 0; i < 33; i++ { bits[i] = 0; }
    *(freq + 256) = 1;

    while true {
        // Two least-frequent entries; ties pick the larger symbol so
        // shorter codes go to smaller (more common) categories.
        i32 c1 = -1;
        i32 v = 1000000000;
        for i32 i = 0; i <= 256; i++ {
            if *(freq + i) != 0 && *(freq + i) <= v { v = *(freq + i); c1 = i; }
        }
        i32 c2 = -1;
        v = 1000000000;
        for i32 i = 0; i <= 256; i++ {
            if *(freq + i) != 0 && *(freq + i) <= v && i != c1 { v = *(freq + i); c2 = i; }
        }
        if c2 < 0 { break; }

        *(freq + c1) = *(freq + c1) + *(freq + c2);
        *(freq + c2) = 0;

        codesize[c1] = codesize[c1] + 1;
        while others[c1] >= 0 {
            c1 = others[c1];
            codesize[c1] = codesize[c1] + 1;
        }
        others[c1] = c2;
        codesize[c2] = codesize[c2] + 1;
        while others[c2] >= 0 {
            c2 = others[c2];
            codesize[c2] = codesize[c2] + 1;
        }
    }

    for i32 i = 0; i <= 256; i++ {
        if codesize[i] > 0 { bits[codesize[i]] = bits[codesize[i]] + 1; }
    }
    // Limit code lengths to 16 bits (spec K.2 adjustment).
    for i32 len = 32; len > 16; len-- {
        while bits[len] > 0 {
            i32 j = len - 2;
            while bits[j] == 0 { j = j - 1; }
            bits[len] = bits[len] - 2;
            bits[len - 1] = bits[len - 1] + 1;
            bits[j + 1] = bits[j + 1] + 2;
            bits[j] = bits[j] - 1;
        }
    }
    // Remove the reserved symbol's slot from the longest used length.
    i32 top = 16;
    while bits[top] == 0 { top = top - 1; }
    bits[top] = bits[top] - 1;

    *(bits_out + 0) = 0;
    for i32 len = 1; len <= 16; len++ { *(bits_out + len) = cast(u8, bits[len]); }
    // HUFFVAL: symbols sorted by (original) code size, then value.
    i32 k = 0;
    for i32 len = 1; len <= 32; len++ {
        for i32 s = 0; s <= 255; s++ {
            if codesize[s] == len {
                *(vals_out + k) = cast(u8, s);
                k = k + 1;
            }
        }
    }
    *nvals_out = k;
}

// --- Forward DCT (AAN float, vertical-SIMD) -----------------------------
// Same flow graph as libjpeg jfdctflt, lane-ified like the IDCT above.
// Operates on a TRANSPOSED input block (see je_load_block) so pass 1
// transforms along x with lanes = y; one scalar transpose flips to
// row-major for pass 2 along y. Output needs the per-coefficient AAN
// descale, folded into the quantizer reciprocals.

// One 1D forward-AAN pass along the vector index.
private void jfdct_pass8(f32* in, f32* out) {
    f32x8 d0 = f32x8_load(in);
    f32x8 d1 = f32x8_load(in + 8);
    f32x8 d2 = f32x8_load(in + 16);
    f32x8 d3 = f32x8_load(in + 24);
    f32x8 d4 = f32x8_load(in + 32);
    f32x8 d5 = f32x8_load(in + 40);
    f32x8 d6 = f32x8_load(in + 48);
    f32x8 d7 = f32x8_load(in + 56);

    f32x8 tmp0 = f32x8_add(d0, d7);
    f32x8 tmp7 = f32x8_sub(d0, d7);
    f32x8 tmp1 = f32x8_add(d1, d6);
    f32x8 tmp6 = f32x8_sub(d1, d6);
    f32x8 tmp2 = f32x8_add(d2, d5);
    f32x8 tmp5 = f32x8_sub(d2, d5);
    f32x8 tmp3 = f32x8_add(d3, d4);
    f32x8 tmp4 = f32x8_sub(d3, d4);

    // Even part
    f32x8 tmp10 = f32x8_add(tmp0, tmp3);
    f32x8 tmp13 = f32x8_sub(tmp0, tmp3);
    f32x8 tmp11 = f32x8_add(tmp1, tmp2);
    f32x8 tmp12 = f32x8_sub(tmp1, tmp2);

    f32x8_store(out,      f32x8_add(tmp10, tmp11));
    f32x8_store(out + 32, f32x8_sub(tmp10, tmp11));

    f32x8 z1 = f32x8_mul(f32x8_add(tmp12, tmp13), f32x8_splat(0.707106781f));
    f32x8_store(out + 16, f32x8_add(tmp13, z1));
    f32x8_store(out + 48, f32x8_sub(tmp13, z1));

    // Odd part
    tmp10 = f32x8_add(tmp4, tmp5);
    tmp11 = f32x8_add(tmp5, tmp6);
    tmp12 = f32x8_add(tmp6, tmp7);

    f32x8 z5 = f32x8_mul(f32x8_sub(tmp10, tmp12), f32x8_splat(0.382683433f));
    f32x8 z2 = f32x8_add(f32x8_mul(tmp10, f32x8_splat(0.541196100f)), z5);
    f32x8 z4 = f32x8_add(f32x8_mul(tmp12, f32x8_splat(1.306562965f)), z5);
    f32x8 z3 = f32x8_mul(tmp11, f32x8_splat(0.707106781f));

    f32x8 z11 = f32x8_add(tmp7, z3);
    f32x8 z13 = f32x8_sub(tmp7, z3);

    f32x8_store(out + 40, f32x8_add(z13, z2));
    f32x8_store(out + 24, f32x8_sub(z13, z2));
    f32x8_store(out + 8,  f32x8_add(z11, z4));
    f32x8_store(out + 56, f32x8_sub(z11, z4));
}

// 2D forward DCT of a transposed block ([x][y] layout, see
// je_load_block). Result is row-major frequency coefficients.
private void jpeg_fdct8x8(f32* blkT, f32* out) {
    // Pass 1: transform along x (vector index = x, lanes = y).
    noinit f32[64] t1;
    jfdct_pass8(blkT, &t1[0]);
    // Flip to row-major, then pass 2 along y (lanes = x).
    noinit f32[64] t2;
    jpeg_transpose8(&t1[0], &t2[0]);
    jfdct_pass8(&t2[0], out);
}

// --- Block entropy encode -----------------------------------------------

// Bit-length of |v| (DC category / AC size). v != 0.
private i32 je_bitsize(i32 v) {
    if v < 0 { v = -v; }
    i32 n = 0;
    while v > 0 {
        n = n + 1;
        v = v >> 1;
    }
    return n;
}

// Encode one quantized block (natural order). dc_code/dc_size and
// ac_code/ac_size are the per-symbol Huffman tables for this component.
private void je_encode_block(JBitsW* w, i32* qblk, i32* dc_pred,
                             i32* dc_code, i32* dc_size,
                             i32* ac_code, i32* ac_size) {
    // DC
    i32 diff = qblk[0] - *dc_pred;
    *dc_pred = qblk[0];
    i32 sz = 0;
    if diff != 0 { sz = je_bitsize(diff); }
    jw_bits(w, *(dc_code + sz), *(dc_size + sz));
    if sz > 0 {
        i32 v = diff;
        if v < 0 { v = v - 1; }
        jw_bits(w, v & ((1 << sz) - 1), sz);
    }

    // AC: walk in zigzag order.
    i32 run = 0;
    for i32 k = 1; k <= 63; k++ {
        i32 v = qblk[cast(i32, jz_zigzag[k])];
        if v == 0 {
            run = run + 1;
            continue;
        }
        while run > 15 {
            jw_bits(w, *(ac_code + 240), *(ac_size + 240));   // ZRL
            run = run - 16;
        }
        i32 s = je_bitsize(v);
        i32 rs = (run << 4) | s;
        jw_bits(w, *(ac_code + rs), *(ac_size + rs));
        i32 m = v;
        if m < 0 { m = m - 1; }
        jw_bits(w, m & ((1 << s) - 1), s);
        run = 0;
    }
    if run > 0 {
        jw_bits(w, *(ac_code + 0), *(ac_size + 0));           // EOB
    }
}

// Frequency-counting twin of je_encode_block (pass A of the optimal-
// Huffman encoder). Must emit the exact symbol sequence pass B will.
private void je_count_block(i32* qblk, i32* dc_pred, i32* dc_freq, i32* ac_freq) {
    i32 diff = qblk[0] - *dc_pred;
    *dc_pred = qblk[0];
    i32 sz = 0;
    if diff != 0 { sz = je_bitsize(diff); }
    *(dc_freq + sz) = *(dc_freq + sz) + 1;

    i32 run = 0;
    for i32 k = 1; k <= 63; k++ {
        i32 v = qblk[cast(i32, jz_zigzag[k])];
        if v == 0 {
            run = run + 1;
            continue;
        }
        while run > 15 {
            *(ac_freq + 240) = *(ac_freq + 240) + 1;          // ZRL
            run = run - 16;
        }
        i32 s = je_bitsize(v);
        i32 rs = (run << 4) | s;
        *(ac_freq + rs) = *(ac_freq + rs) + 1;
        run = 0;
    }
    if run > 0 {
        *(ac_freq + 0) = *(ac_freq + 0) + 1;                  // EOB
    }
}

// --- Header emission ----------------------------------------------------

private void je_marker(JBitsW* w, i32 m) {
    jw_byte(w, 255);
    jw_byte(w, m);
}

private void je_u16(JBitsW* w, i32 v) {
    jw_byte(w, (v >> 8) & 255);
    jw_byte(w, v & 255);
}

// Extract an 8x8 block at (bx,by) from a plane, minus the 128 level
// shift, TRANSPOSED ([x][y] layout) — the FDCT's pass-1 orientation.
// The loads are scalar either way, so the transposed write is free.
private void je_load_block(f32* plane, i32 pw, i32 bx, i32 by, f32* blkT) {
    for i32 y = 0; y < 8; y++ {
        f32* src = plane + (by + y) * pw + bx;
        for i32 x = 0; x < 8; x++ {
            *(blkT + x * 8 + y) = *(src + x) - 128.0f;
        }
    }
}

// Quantize an FDCT output block with the reciprocal table.
// f32x8_to_i32x8 rounds half-to-even (vcvtps2dq) — differs from
// libjpeg's half-away only at exact-.5 quantizer boundaries.
private void je_quantize(f32* blk, f32* qrecip, i32* out) {
    for i32 k = 0; k < 8; k++ {
        f32x8 v = f32x8_mul(f32x8_load(blk + k * 8), f32x8_load(qrecip + k * 8));
        i32x8_store(out + k * 8, f32x8_to_i32x8(v));
    }
}

// Encode RGBA8 pixels into a JPEG byte stream (4:2:0, quality 1-100).
// Returns 0 on success, negative on error:
//   -1 output buffer too small
//   -2 invalid arguments
//   -3 internal error
i32 jpeg_encode(u8* pixels, i32 width, i32 height, i32 quality,
                u8* dst, i32 dstlen, i32* out_dstused) {
    if pixels == null || width <= 0 || height <= 0 { return -2; }
    if width > 32768 || height > 32768 { return -2; }
    if quality < 1 { quality = 1; }
    if quality > 100 { quality = 100; }

    // Quality-scaled quant tables (libjpeg formula), zigzag order for
    // the DQT segment, natural order for the quantizer.
    i32 scale = 200 - 2 * quality;
    if quality < 50 { scale = 5000 / quality; }
    noinit i32[64] qluma;
    noinit i32[64] qchroma;
    for i32 i = 0; i < 64; i++ {
        i32 ql = (cast(i32, jq_luma_base[i]) * scale + 50) / 100;
        if ql < 1 { ql = 1; }
        if ql > 255 { ql = 255; }
        qluma[i] = ql;
        i32 qc = (cast(i32, jq_chroma_base[i]) * scale + 50) / 100;
        if qc < 1 { qc = 1; }
        if qc > 255 { qc = 255; }
        qchroma[i] = qc;
    }
    // Reciprocal quantizers with the AAN descale folded in. Scalar
    // divides on purpose: f32x8_rcp is a 12-bit approximation and
    // must not be used here.
    noinit f32[64] qrl;
    noinit f32[64] qrc;
    for i32 row = 0; row < 8; row++ {
        for i32 col = 0; col < 8; col++ {
            f32 aan = jaan_factor(row) * jaan_factor(col) * 8.0f;
            qrl[row * 8 + col] = 1.0f / (cast(f32, qluma[row * 8 + col]) * aan);
            qrc[row * 8 + col] = 1.0f / (cast(f32, qchroma[row * 8 + col]) * aan);
        }
    }

    // Pad to whole 16x16 MCUs by edge replication; build f32 planes.
    i32 pw = (width + 15) & ~15;
    i32 ph = (height + 15) & ~15;
    i32 cw = pw / 2;
    i32 ch = ph / 2;
    f32* yplane = alloc<f32>(pw * ph);
    f32* cbplane = alloc<f32>(cw * ch);
    f32* crplane = alloc<f32>(cw * ch);
    defer free(yplane);
    defer free(cbplane);
    defer free(crplane);

    // RGB -> Y (BT.601/JFIF) at full resolution. Scalar RGBA
    // deinterleave (no gather), vector multiply-add, scalar edge pad.
    f32x8 kr = f32x8_splat(0.299f);
    f32x8 kg = f32x8_splat(0.587f);
    f32x8 kb = f32x8_splat(0.114f);
    i32 ww8 = width & ~7;
    noinit f32[8] lr;
    noinit f32[8] lg;
    noinit f32[8] lb;
    for i32 y = 0; y < ph; y++ {
        i32 sy = y;
        if sy >= height { sy = height - 1; }
        u8* srow = pixels + sy * width * 4;
        f32* yrow = yplane + y * pw;
        for i32 x = 0; x < ww8; x = x + 8 {
            for i32 i = 0; i < 8; i++ {
                lr[i] = cast(f32, *(srow + (x + i) * 4 + 0));
                lg[i] = cast(f32, *(srow + (x + i) * 4 + 1));
                lb[i] = cast(f32, *(srow + (x + i) * 4 + 2));
            }
            f32x8 vy = f32x8_add(f32x8_add(f32x8_mul(f32x8_load(&lr[0]), kr),
                                           f32x8_mul(f32x8_load(&lg[0]), kg)),
                                 f32x8_mul(f32x8_load(&lb[0]), kb));
            f32x8_store(yrow + x, vy);
        }
        for i32 x = ww8; x < pw; x++ {
            i32 sx = x;
            if sx >= width { sx = width - 1; }
            f32 r = cast(f32, *(srow + sx * 4 + 0));
            f32 g = cast(f32, *(srow + sx * 4 + 1));
            f32 b = cast(f32, *(srow + sx * 4 + 2));
            *(yrow + x) = 0.299f * r + 0.587f * g + 0.114f * b;
        }
    }
    // Chroma at half resolution: 2x2 box average of the source RGB,
    // then convert. (Averaging RGB then converting equals converting
    // then averaging — the transform is affine.)
    for i32 y = 0; y < ch; y++ {
        i32 sy0 = y * 2;
        i32 sy1 = sy0 + 1;
        if sy0 >= height { sy0 = height - 1; }
        if sy1 >= height { sy1 = height - 1; }
        u8* row0 = pixels + sy0 * width * 4;
        u8* row1 = pixels + sy1 * width * 4;
        f32* cbrow = cbplane + y * cw;
        f32* crrow = crplane + y * cw;
        for i32 x = 0; x < cw; x++ {
            i32 sx0 = x * 2;
            i32 sx1 = sx0 + 1;
            if sx0 >= width { sx0 = width - 1; }
            if sx1 >= width { sx1 = width - 1; }
            f32 r = (cast(f32, *(row0 + sx0 * 4 + 0)) + cast(f32, *(row0 + sx1 * 4 + 0)) +
                     cast(f32, *(row1 + sx0 * 4 + 0)) + cast(f32, *(row1 + sx1 * 4 + 0))) * 0.25f;
            f32 g = (cast(f32, *(row0 + sx0 * 4 + 1)) + cast(f32, *(row0 + sx1 * 4 + 1)) +
                     cast(f32, *(row1 + sx0 * 4 + 1)) + cast(f32, *(row1 + sx1 * 4 + 1))) * 0.25f;
            f32 b = (cast(f32, *(row0 + sx0 * 4 + 2)) + cast(f32, *(row0 + sx1 * 4 + 2)) +
                     cast(f32, *(row1 + sx0 * 4 + 2)) + cast(f32, *(row1 + sx1 * 4 + 2))) * 0.25f;
            *(cbrow + x) = -0.168736f * r - 0.331264f * g + 0.5f * b + 128.0f;
            *(crrow + x) = 0.5f * r - 0.418688f * g - 0.081312f * b + 128.0f;
        }
    }

    // --- Pass A: transform + quantize every block into a coefficient
    // buffer (in emit order: per MCU, 4x Y then Cb then Cr) and collect
    // Huffman symbol frequencies for the optimal-table build.
    i32 mcux = pw / 16;
    i32 mcuy = ph / 16;
    i32 total_blocks = mcux * mcuy * 6;
    i32* coefbuf = alloc<i32>(total_blocks * 64);
    defer free(coefbuf);

    i32[257] freq_dc_l;
    i32[257] freq_ac_l;
    i32[257] freq_dc_c;
    i32[257] freq_ac_c;

    i32 dcy = 0;
    i32 dcb = 0;
    i32 dcr = 0;
    noinit f32[64] blk;
    noinit f32[64] fblk;
    i32 seq = 0;
    for i32 my = 0; my < mcuy; my++ {
        for i32 mx = 0; mx < mcux; mx++ {
            for i32 v = 0; v < 2; v++ {
                for i32 hh = 0; hh < 2; hh++ {
                    i32* qb = coefbuf + seq * 64;
                    je_load_block(yplane, pw, mx * 16 + hh * 8, my * 16 + v * 8, &blk[0]);
                    jpeg_fdct8x8(&blk[0], &fblk[0]);
                    je_quantize(&fblk[0], &qrl[0], qb);
                    je_count_block(qb, &dcy, &freq_dc_l[0], &freq_ac_l[0]);
                    seq = seq + 1;
                }
            }
            i32* qcb = coefbuf + seq * 64;
            je_load_block(cbplane, cw, mx * 8, my * 8, &blk[0]);
            jpeg_fdct8x8(&blk[0], &fblk[0]);
            je_quantize(&fblk[0], &qrc[0], qcb);
            je_count_block(qcb, &dcb, &freq_dc_c[0], &freq_ac_c[0]);
            seq = seq + 1;
            i32* qcr = coefbuf + seq * 64;
            je_load_block(crplane, cw, mx * 8, my * 8, &blk[0]);
            jpeg_fdct8x8(&blk[0], &fblk[0]);
            je_quantize(&fblk[0], &qrc[0], qcr);
            je_count_block(qcr, &dcr, &freq_dc_c[0], &freq_ac_c[0]);
            seq = seq + 1;
        }
    }

    // --- Optimal Huffman tables from the measured frequencies.
    noinit u8[17] hb_dc_l;
    noinit u8[256] hv_dc_l;
    i32 hn_dc_l = 0;
    noinit u8[17] hb_ac_l;
    noinit u8[256] hv_ac_l;
    i32 hn_ac_l = 0;
    noinit u8[17] hb_dc_c;
    noinit u8[256] hv_dc_c;
    i32 hn_dc_c = 0;
    noinit u8[17] hb_ac_c;
    noinit u8[256] hv_ac_c;
    i32 hn_ac_c = 0;
    je_optimal_table(&freq_dc_l[0], &hb_dc_l[0], &hv_dc_l[0], &hn_dc_l);
    je_optimal_table(&freq_ac_l[0], &hb_ac_l[0], &hv_ac_l[0], &hn_ac_l);
    je_optimal_table(&freq_dc_c[0], &hb_dc_c[0], &hv_dc_c[0], &hn_dc_c);
    je_optimal_table(&freq_ac_c[0], &hb_ac_c[0], &hv_ac_c[0], &hn_ac_c);

    // Per-symbol code tables for the emit pass.
    noinit i32[256] code_dc_l;
    noinit i32[256] size_dc_l;
    noinit i32[256] code_ac_l;
    noinit i32[256] size_ac_l;
    noinit i32[256] code_dc_c;
    noinit i32[256] size_dc_c;
    noinit i32[256] code_ac_c;
    noinit i32[256] size_ac_c;
    je_build_codes(&hb_dc_l[0], &hv_dc_l[0], &code_dc_l[0], &size_dc_l[0]);
    je_build_codes(&hb_ac_l[0], &hv_ac_l[0], &code_ac_l[0], &size_ac_l[0]);
    je_build_codes(&hb_dc_c[0], &hv_dc_c[0], &code_dc_c[0], &size_dc_c[0]);
    je_build_codes(&hb_ac_c[0], &hv_ac_c[0], &code_ac_c[0], &size_ac_c[0]);

    JBitsW w;
    jw_init(&w, dst, dstlen);

    // SOI
    je_marker(&w, 216);
    // APP0 JFIF: version 1.01, units 0 (aspect ratio), density 1x1.
    je_marker(&w, 224);
    je_u16(&w, 16);
    jw_byte(&w, 74); jw_byte(&w, 70); jw_byte(&w, 73); jw_byte(&w, 70); jw_byte(&w, 0);  // "JFIF\0"
    jw_byte(&w, 1); jw_byte(&w, 1);   // version 1.01
    jw_byte(&w, 0);                   // units
    je_u16(&w, 1); je_u16(&w, 1);     // density 1x1
    jw_byte(&w, 0); jw_byte(&w, 0);   // no thumbnail
    // DQT x2 (8-bit precision, zigzag order)
    je_marker(&w, 219);
    je_u16(&w, 2 + 65);
    jw_byte(&w, 0);                   // Pq=0, Tq=0
    for i32 i = 0; i < 64; i++ { jw_byte(&w, qluma[cast(i32, jz_zigzag[i])]); }
    je_marker(&w, 219);
    je_u16(&w, 2 + 65);
    jw_byte(&w, 1);                   // Pq=0, Tq=1
    for i32 i = 0; i < 64; i++ { jw_byte(&w, qchroma[cast(i32, jz_zigzag[i])]); }
    // SOF0
    je_marker(&w, 192);
    je_u16(&w, 8 + 3 * 3);
    jw_byte(&w, 8);                   // precision
    je_u16(&w, height);
    je_u16(&w, width);
    jw_byte(&w, 3);                   // 3 components
    jw_byte(&w, 1); jw_byte(&w, 34); jw_byte(&w, 0);   // Y:  id 1, samp 2x2, qt 0
    jw_byte(&w, 2); jw_byte(&w, 17); jw_byte(&w, 1);   // Cb: id 2, samp 1x1, qt 1
    jw_byte(&w, 3); jw_byte(&w, 17); jw_byte(&w, 1);   // Cr: id 3, samp 1x1, qt 1
    // DHT x4 (optimal tables from the pass-A frequencies)
    je_marker(&w, 196);
    je_u16(&w, 2 + 1 + 16 + hn_dc_l);
    jw_byte(&w, 0);                   // class 0 (DC), id 0
    for i32 i = 1; i <= 16; i++ { jw_byte(&w, cast(i32, hb_dc_l[i])); }
    for i32 i = 0; i < hn_dc_l; i++ { jw_byte(&w, cast(i32, hv_dc_l[i])); }
    je_marker(&w, 196);
    je_u16(&w, 2 + 1 + 16 + hn_ac_l);
    jw_byte(&w, 16);                  // class 1 (AC), id 0
    for i32 i = 1; i <= 16; i++ { jw_byte(&w, cast(i32, hb_ac_l[i])); }
    for i32 i = 0; i < hn_ac_l; i++ { jw_byte(&w, cast(i32, hv_ac_l[i])); }
    je_marker(&w, 196);
    je_u16(&w, 2 + 1 + 16 + hn_dc_c);
    jw_byte(&w, 1);                   // class 0 (DC), id 1
    for i32 i = 1; i <= 16; i++ { jw_byte(&w, cast(i32, hb_dc_c[i])); }
    for i32 i = 0; i < hn_dc_c; i++ { jw_byte(&w, cast(i32, hv_dc_c[i])); }
    je_marker(&w, 196);
    je_u16(&w, 2 + 1 + 16 + hn_ac_c);
    jw_byte(&w, 17);                  // class 1 (AC), id 1
    for i32 i = 1; i <= 16; i++ { jw_byte(&w, cast(i32, hb_ac_c[i])); }
    for i32 i = 0; i < hn_ac_c; i++ { jw_byte(&w, cast(i32, hv_ac_c[i])); }
    // SOS
    je_marker(&w, 218);
    je_u16(&w, 6 + 3 * 2);
    jw_byte(&w, 3);                   // 3 components in scan
    jw_byte(&w, 1); jw_byte(&w, 0);   // Y:  DC 0 / AC 0
    jw_byte(&w, 2); jw_byte(&w, 17);  // Cb: DC 1 / AC 1
    jw_byte(&w, 3); jw_byte(&w, 17);  // Cr: DC 1 / AC 1
    jw_byte(&w, 0);                   // Ss
    jw_byte(&w, 63);                  // Se
    jw_byte(&w, 0);                   // Ah/Al

    // --- Pass B: entropy-encode the buffered blocks with the optimal
    // tables (4x Y then Cb then Cr per MCU — same order as pass A).
    dcy = 0;
    dcb = 0;
    dcr = 0;
    seq = 0;
    for i32 my = 0; my < mcuy; my++ {
        for i32 mx = 0; mx < mcux; mx++ {
            for i32 b = 0; b < 4; b++ {
                je_encode_block(&w, coefbuf + seq * 64, &dcy,
                                &code_dc_l[0], &size_dc_l[0],
                                &code_ac_l[0], &size_ac_l[0]);
                seq = seq + 1;
            }
            je_encode_block(&w, coefbuf + seq * 64, &dcb,
                            &code_dc_c[0], &size_dc_c[0],
                            &code_ac_c[0], &size_ac_c[0]);
            seq = seq + 1;
            je_encode_block(&w, coefbuf + seq * 64, &dcr,
                            &code_dc_c[0], &size_dc_c[0],
                            &code_ac_c[0], &size_ac_c[0]);
            seq = seq + 1;
        }
    }

    jw_flush(&w);
    je_marker(&w, 217);   // EOI

    if w.overflow { return -1; }
    if out_dstused != null { *out_dstused = w.dstpos; }
    return 0;
}

// Save RGBA8 pixels to a JPEG file (4:2:0, quality 1-100).
// Returns 0 on success, negative on error (see jpeg_encode; -4 = write failed).
i32 jpeg_save(str path, u8* pixels, i32 width, i32 height, i32 quality) {
    if pixels == null || width <= 0 || height <= 0 { return -2; }
    // Comfortable upper bound: headers + entropy data can't approach
    // 1.5 bytes/pixel on real images; jpeg_encode still reports -1 if
    // the bound is ever wrong.
    i32 cap = width * height * 3 / 2 + 4096;
    u8* buf = alloc<u8>(cap);
    i32 len = 0;
    i32 err = jpeg_encode(pixels, width, height, quality, buf, cap, &len);
    if err != 0 {
        free(buf);
        return err;
    }
    FileData fd;
    fd.data = buf;
    fd.len = len;
    bool ok = file_write(path, fd);
    free(buf);
    if !ok { return -4; }
    return 0;
}
