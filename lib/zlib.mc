// zlib.mc - zlib/gzip (de)compression library for minc
// Provides inflate, zlib_decompress, gzip_decompress, adler32, crc32,
// deflate, zlib_compress.

#include "inflate.mc"
#include "deflate.mc"

// --- Adler-32 checksum (RFC 1950) ---

u32 adler32(u8* data, i32 len) {
    u32 a = 1;
    u32 b = 0;
    for i32 i = 0; i < len; i = i + 1 {
        a = (a + cast(u32, *(data + i))) % 65521;
        b = (b + a) % 65521;
    }
    return (b << 16) | a;
}

// --- CRC-32 checksum (RFC 1952) ---

private u32[256] crc32_table;
private bool crc32_inited = false;

private void crc32_init() {
    if crc32_inited { return; }
    crc32_inited = true;
    for u32 i = 0; i < 256; i = i + 1 {
        u32 c = i;
        for i32 j = 0; j < 8; j = j + 1 {
            if (c & 1) != 0 {
                c = (c >> 1) ^ 3988292384; // 0xEDB88320
            } else {
                c = c >> 1;
            }
        }
        crc32_table[i] = c;
    }
    return;
}

u32 crc32(u8* data, i32 len) {
    crc32_init();
    u32 c = 4294967295; // 0xFFFFFFFF
    for i32 i = 0; i < len; i = i + 1 {
        u32 idx = (c ^ cast(u32, *(data + i))) & 255;
        c = (c >> 8) ^ crc32_table[idx];
    }
    return c ^ 4294967295;
}

// --- Helper: read little-endian integers ---

private u32 read_u16_le(u8* p) {
    return cast(u32, *p) | (cast(u32, *(p + 1)) << 8);
}

private u32 read_u32_le(u8* p) {
    return cast(u32, *p) | (cast(u32, *(p + 1)) << 8) |
           (cast(u32, *(p + 2)) << 16) | (cast(u32, *(p + 3)) << 24);
}

u32 read_u32_be(u8* p) {
    return (cast(u32, *p) << 24) | (cast(u32, *(p + 1)) << 16) |
           (cast(u32, *(p + 2)) << 8) | cast(u32, *(p + 3));
}

// --- Zlib decompression (RFC 1950) ---
// Format: 2-byte header (CMF, FLG) + DEFLATE data + 4-byte Adler-32

i32 zlib_decompress(u8* src, i32 srclen, u8* dst, i32 dstlen, i32* out_dstused) {
    if srclen < 6 { return 0 - 1; } // minimum: 2 header + 0 data + 4 checksum

    // Parse header
    i32 cmf = cast(i32, *src);
    i32 flg = cast(i32, *(src + 1));

    // Check method (CM must be 8 = deflate)
    if (cmf & 15) != 8 { return 0 - 8; }

    // Check header checksum
    if ((cmf * 256 + flg) % 31) != 0 { return 0 - 2; }

    // FDICT flag not supported
    if (flg & 32) != 0 { return 0 - 3; }

    if srclen < 6 { return 0 - 1; }

    // Inflate the DEFLATE data
    i32 srcused = 0;
    i32 dstused = 0;
    i32 err = inflate(src + 2, srclen - 6, dst, dstlen, &srcused, &dstused);
    if err != 0 { return err; }

    // Verify Adler-32 trailer bounds
    if 2 + srcused + 4 > srclen { return 0 - 1; }
    u8* trailer = src + 2 + srcused;
    u32 expected = read_u32_be(trailer);
    u32 actual = adler32(dst, dstused);
    if expected != actual { return 0 - 4; }

    if out_dstused != cast(i32*, 0) { *out_dstused = dstused; }
    return 0;
}

// --- Zlib compression (RFC 1950) ---
// Wraps deflate output with a 2-byte header and 4-byte Adler-32 trailer.

i32 zlib_compress(u8* src, i32 srclen, u8* dst, i32 dstlen, i32* out_dstused) {
    if dstlen < 6 { return 0 - 1; }

    // CMF = 0x78: CM=8 (deflate), CINFO=7 (32K window).
    // FLG chosen so (CMF*256 + FLG) % 31 == 0 with FLEVEL=0 (fastest).
    // 0x7801 = 30721 = 991 * 31, so FLG=0x01 satisfies the check.
    *(dst + 0) = 0x78;
    *(dst + 1) = 0x01;

    i32 deflate_used = 0;
    i32 err = deflate(src, srclen, dst + 2, dstlen - 6, &deflate_used);
    if err != 0 { return err; }

    // Adler-32 over the uncompressed data, stored big-endian.
    u32 a = adler32(src, srclen);
    u8* trailer = dst + 2 + deflate_used;
    *(trailer + 0) = cast(u8, (a >> 24) & 255);
    *(trailer + 1) = cast(u8, (a >> 16) & 255);
    *(trailer + 2) = cast(u8, (a >> 8) & 255);
    *(trailer + 3) = cast(u8, a & 255);

    if out_dstused != cast(i32*, 0) { *out_dstused = 2 + deflate_used + 4; }
    return 0;
}

// --- Gzip decompression (RFC 1952) ---
// Format: 10-byte header + optional fields + DEFLATE data + CRC-32 + ISIZE

i32 gzip_decompress(u8* src, i32 srclen, u8* dst, i32 dstlen, i32* out_dstused) {
    if srclen < 18 { return 0 - 1; } // minimum: 10 header + 0 data + 8 trailer

    // Check magic number
    if *src != 0x1f || *(src + 1) != 0x8b { return 0 - 8; }

    // Check method (must be 8 = deflate)
    if *(src + 2) != 8 { return 0 - 8; }

    i32 flg = cast(i32, *(src + 3));
    i32 pos = 10;

    // Skip FEXTRA
    if (flg & 4) != 0 {
        if pos + 2 > srclen { return 0 - 1; }
        i32 xlen = cast(i32, read_u16_le(src + pos));
        pos = pos + 2 + xlen;
    }

    // Skip FNAME (null-terminated)
    if (flg & 8) != 0 {
        while pos < srclen && *(src + pos) != 0 { pos = pos + 1; }
        pos = pos + 1; // skip null terminator
    }

    // Skip FCOMMENT (null-terminated)
    if (flg & 16) != 0 {
        while pos < srclen && *(src + pos) != 0 { pos = pos + 1; }
        pos = pos + 1;
    }

    // Skip FHCRC (2 bytes)
    if (flg & 2) != 0 {
        pos = pos + 2;
    }

    if pos + 8 >= srclen { return 0 - 1; }

    // Inflate
    i32 srcused = 0;
    i32 dstused = 0;
    i32 err = inflate(src + pos, srclen - pos - 8, dst, dstlen, &srcused, &dstused);
    if err != 0 { return err; }

    // Verify trailer bounds
    if pos + srcused + 8 > srclen { return 0 - 1; }
    // Read trailer: CRC-32 and ISIZE
    u8* trailer = src + pos + srcused;
    u32 expected_crc = read_u32_le(trailer);
    u32 expected_size = read_u32_le(trailer + 4);
    u32 actual_crc = crc32(dst, dstused);

    if expected_crc != actual_crc { return 0 - 4; }
    if expected_size != cast(u32, dstused) { return 0 - 4; }

    if out_dstused != cast(i32*, 0) { *out_dstused = dstused; }
    return 0;
}
