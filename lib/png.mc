// png.mc — PNG image decoder + encoder for minc
// Depends on: lib/zlib.mc  (zlib_decompress, zlib_compress, crc32, read_u32_be)
//             lib/file.mc  (file_write, FileData)
//
// Read:  every standard color type and bit depth: grayscale 1/2/4/8/16,
//        RGB 8/16, palette 1/2/4/8, grayscale+alpha 8/16, RGBA 8/16.
//        Adam7 interlacing. tRNS for palette, grayscale and RGB.
//        16-bit samples are rounded to 8 bits. Ancillary chunks
//        (gAMA, iCCP, ...) are skipped.
//        Output is always RGBA8 (4 bytes per pixel). Caller must free(pixels).
//        On failure pixels is null and error holds the reason.
// Write: RGBA8 input only, non-interlaced, filter type 0 (None).
//
// Usage:
//   PngImage img = png_load("image.png");
//   if img.pixels != null { /* use img.width, img.height, img.pixels */ }
//   png_save("out.png", pixels, w, h);

#include "file.mc"
#include "zlib.mc"


struct PngImage {
    u8* pixels;     // RGBA8 data, null on error
    i32 width;      // 0 on error
    i32 height;     // 0 on error
    str error;      // reason pixels is null; "" on success
}

private PngImage png_error(str msg) {
    PngImage r;
    r.error = msg;
    return r;
}

// Paeth predictor (PNG spec)
private i32 png_paeth(i32 a, i32 b, i32 c) {
    i32 p = a + b - c;
    i32 pa = p - a; if pa < 0 { pa = -pa; }
    i32 pb = p - b; if pb < 0 { pb = -pb; }
    i32 pc = p - c; if pc < 0 { pc = -pc; }
    if pa <= pb && pa <= pc { return a; }
    if pb <= pc { return b; }
    return c;
}

private struct PngFmt {
    i32 depth;
    i32 ctype;
    u8* palette;
    i32 palette_n;     // palette entries
    u8* pal_alpha;
    bool has_key;      // tRNS for grayscale / RGB
    i32 key_r;         // gray key for grayscale
    i32 key_g;
    i32 key_b;
}

const i32[7] png_a7_x0 = { 0, 4, 0, 2, 0, 1, 0 };
const i32[7] png_a7_y0 = { 0, 0, 4, 0, 2, 0, 1 };
const i32[7] png_a7_dx = { 8, 8, 4, 4, 2, 2, 1 };
const i32[7] png_a7_dy = { 8, 8, 8, 4, 4, 2, 2 };

private i32 png_channels(i32 ctype) {
    if ctype == 2 { return 3; }
    if ctype == 4 { return 2; }
    if ctype == 6 { return 4; }
    return 1;
}

private i64 png_row_bytes(i32 w, i32 bits_pp) {
    return (cast(i64, w) * bits_pp + 7) / 8;
}

// Sample i of a row, at the file's depth.
private i32 png_sample(u8* row, i32 i, i32 depth) {
    if depth == 8 { return cast(i32, row[i]); }
    if depth == 16 { return (cast(i32, row[i * 2]) << 8) | cast(i32, row[i * 2 + 1]); }
    i32 bit = i * depth;
    i32 shift = 8 - depth - (bit & 7);
    return (cast(i32, row[bit >> 3]) >> shift) & ((1 << depth) - 1);
}

private u8 png_to8(i32 v, i32 depth) {
    if depth == 8 { return cast(u8, v); }
    if depth == 16 { return cast(u8, (v * 255 + 32895) / 65535); }
    return cast(u8, v * 255 / ((1 << depth) - 1));
}

private bool png_unfilter(u8* raw, i32 rows, i32 row_bytes, i32 bpp) {
    i32 stride = 1 + row_bytes;
    for i32 y = 0; y < rows; y++ {
        u8* row = raw + y * stride;
        i32 ftype = cast(i32, *row);
        u8* cur = row + 1;
        u8* prev = null;
        if y > 0 { prev = raw + (y - 1) * stride + 1; }

        if ftype == 0 {
        } else if ftype == 1 {
            for i32 i = bpp; i < row_bytes; i++ {
                *(cur + i) = cast(u8, (cast(i32, *(cur + i)) + cast(i32, *(cur + i - bpp))) & 255);
            }
        } else if ftype == 2 {
            if prev != null {
                for i32 i = 0; i < row_bytes; i++ {
                    *(cur + i) = cast(u8, (cast(i32, *(cur + i)) + cast(i32, *(prev + i))) & 255);
                }
            }
        } else if ftype == 3 {
            for i32 i = 0; i < row_bytes; i++ {
                i32 left = 0; if i >= bpp { left = cast(i32, *(cur + i - bpp)); }
                i32 above = 0; if prev != null { above = cast(i32, *(prev + i)); }
                *(cur + i) = cast(u8, (cast(i32, *(cur + i)) + (left + above) / 2) & 255);
            }
        } else if ftype == 4 {
            for i32 i = 0; i < row_bytes; i++ {
                i32 left = 0; if i >= bpp { left = cast(i32, *(cur + i - bpp)); }
                i32 above = 0; if prev != null { above = cast(i32, *(prev + i)); }
                i32 upper_left = 0; if prev != null && i >= bpp { upper_left = cast(i32, *(prev + i - bpp)); }
                *(cur + i) = cast(u8, (cast(i32, *(cur + i)) + png_paeth(left, above, upper_left)) & 255);
            }
        } else {
            return false;
        }
    }
    return true;
}

// Converts n pixels of an unfiltered row to RGBA8, written step pixels
// apart. False on a palette index outside the palette.
private bool png_expand_row(PngFmt* f, u8* src, i32 n, u8* dst, i32 step) {
    i32 ds = step * 4;
    i32 depth = f.depth;
    if f.ctype == 6 && depth == 8 && step == 1 {
        memcpy(dst, src, cast(i64, n) * 4);
        return true;
    }
    for i32 x = 0; x < n; x++ {
        u8* o = dst + x * ds;
        if f.ctype == 0 {
            i32 v = png_sample(src, x, depth);
            u8 g = png_to8(v, depth);
            o[0] = g; o[1] = g; o[2] = g;
            o[3] = 255;
            if f.has_key && v == f.key_r { o[3] = 0; }
        } else if f.ctype == 2 {
            i32 r = png_sample(src, x * 3, depth);
            i32 g = png_sample(src, x * 3 + 1, depth);
            i32 b = png_sample(src, x * 3 + 2, depth);
            o[0] = png_to8(r, depth);
            o[1] = png_to8(g, depth);
            o[2] = png_to8(b, depth);
            o[3] = 255;
            if f.has_key && r == f.key_r && g == f.key_g && b == f.key_b { o[3] = 0; }
        } else if f.ctype == 3 {
            i32 idx = png_sample(src, x, depth);
            if idx >= f.palette_n { return false; }
            o[0] = f.palette[idx * 3];
            o[1] = f.palette[idx * 3 + 1];
            o[2] = f.palette[idx * 3 + 2];
            o[3] = f.pal_alpha[idx];
        } else if f.ctype == 4 {
            u8 g = png_to8(png_sample(src, x * 2, depth), depth);
            o[0] = g; o[1] = g; o[2] = g;
            o[3] = png_to8(png_sample(src, x * 2 + 1, depth), depth);
        } else {
            for i32 c = 0; c < 4; c++ {
                o[c] = png_to8(png_sample(src, x * 4 + c, depth), depth);
            }
        }
    }
    return true;
}

private bool png_depth_ok(i32 ctype, i32 depth) {
    if ctype == 0 { return depth == 1 || depth == 2 || depth == 4 || depth == 8 || depth == 16; }
    if ctype == 3 { return depth == 1 || depth == 2 || depth == 4 || depth == 8; }
    return depth == 8 || depth == 16;
}

// Decode PNG from raw bytes in memory
PngImage png_decode(u8* data, i64 nbytes) {
    if nbytes > 2147483647 { return png_error("image larger than 2 GB"); }
    i32 len = cast(i32, nbytes);
    // Check minimum size and PNG signature
    if len < 8 { return png_error("file too small"); }
    if *(data + 0) != 137 || *(data + 1) != 80 || *(data + 2) != 78 || *(data + 3) != 71 ||
       *(data + 4) != 13 || *(data + 5) != 10 || *(data + 6) != 26 || *(data + 7) != 10 {
        return png_error("invalid PNG signature");
    }

    // Parse chunks
    i32 pos = 8;
    i32 img_w = 0;
    i32 img_h = 0;
    i32 bit_depth = 0;
    i32 color_type = 0;
    i32 interlace = 0;
    bool got_ihdr = false;
    bool got_iend = false;

    // IDAT accumulation — collect all IDAT data
    i32 idat_cap = 65536;
    i32 idat_len = 0;
    u8* idat_buf = cast(u8*, alloc(cast(i64, idat_cap)));

    // PLTE palette (color type 3) + optional per-index tRNS alpha
    noinit u8[768] palette;
    i32 palette_len = 0;
    noinit u8[256] pal_alpha;
    for i32 i = 0; i < 256; i = i + 1 { pal_alpha[i] = 255; }
    PngFmt f;

    while pos + 12 <= len && !got_iend {
        u32 chunk_len = read_u32_be(data + pos);
        u8* chunk_type = data + pos + 4;
        u8* chunk_data = data + pos + 8;
        i32 chunk_total = 12 + cast(i32, chunk_len);

        if chunk_len > 2147483635 || pos + chunk_total > len {
            free(idat_buf);
            return png_error("truncated chunk");
        }

        // CRC check (over type + data)
        u32 expected_crc = read_u32_be(data + pos + 8 + cast(i32, chunk_len));
        u32 actual_crc = crc32(data + pos + 4, cast(i32, chunk_len) + 4);
        if expected_crc != actual_crc {
            free(idat_buf);
            return png_error("CRC mismatch");
        }

        // IHDR
        if *(chunk_type+0)==73 && *(chunk_type+1)==72 && *(chunk_type+2)==68 && *(chunk_type+3)==82 {
            if chunk_len != 13 { free(idat_buf); return png_error("invalid IHDR length"); }
            got_ihdr = true;
            img_w = cast(i32, read_u32_be(chunk_data));
            img_h = cast(i32, read_u32_be(chunk_data + 4));
            bit_depth = cast(i32, *(chunk_data + 8));
            color_type = cast(i32, *(chunk_data + 9));
            i32 compression = cast(i32, *(chunk_data + 10));
            i32 filter = cast(i32, *(chunk_data + 11));
            interlace = cast(i32, *(chunk_data + 12));

            if compression != 0 { free(idat_buf); return png_error("unsupported compression method"); }
            if filter != 0 { free(idat_buf); return png_error("unsupported filter method"); }
            if interlace > 1 { free(idat_buf); return png_error("unsupported interlace method"); }
            if color_type != 0 && color_type != 2 && color_type != 3 && color_type != 4 && color_type != 6 {
                free(idat_buf);
                return png_error("unsupported color type");
            }
            if !png_depth_ok(color_type, bit_depth) { free(idat_buf); return png_error("invalid bit depth"); }
            if img_w <= 0 || img_h <= 0 { free(idat_buf); return png_error("invalid image dimensions"); }
            if img_w > 32768 || img_h > 32768 || cast(i64, img_w) * img_h * 4 > 2147483647 {
                free(idat_buf);
                return png_error("image too large");
            }
        }
        // IDAT
        else if *(chunk_type+0)==73 && *(chunk_type+1)==68 && *(chunk_type+2)==65 && *(chunk_type+3)==84 {
            if !got_ihdr { free(idat_buf); return png_error("IDAT before IHDR"); }
            // Grow idat_buf if needed
            i32 needed = idat_len + cast(i32, chunk_len);
            while needed > idat_cap {
                if idat_cap > 1073741823 { idat_cap = needed; } else { idat_cap = idat_cap * 2; }
                u8* new_buf = cast(u8*, alloc(cast(i64, idat_cap)));
                memcpy(new_buf, idat_buf, cast(i64, idat_len));
                free(idat_buf);
                idat_buf = new_buf;
            }
            memcpy(idat_buf + idat_len, chunk_data, cast(i64, chunk_len));
            idat_len = idat_len + cast(i32, chunk_len);
        }
        // IEND
        else if *(chunk_type+0)==73 && *(chunk_type+1)==69 && *(chunk_type+2)==78 && *(chunk_type+3)==68 {
            got_iend = true;
        }
        // PLTE — RGB triples for indexed color
        else if *(chunk_type+0)==80 && *(chunk_type+1)==76 && *(chunk_type+2)==84 && *(chunk_type+3)==69 {
            if chunk_len > 768 || chunk_len % 3 != 0 {
                free(idat_buf);
                return png_error("invalid PLTE length");
            }
            memcpy(&palette[0], chunk_data, cast(i64, chunk_len));
            palette_len = cast(i32, chunk_len);
        }
        // tRNS — alpha per palette index, or the transparent gray / RGB value
        else if *(chunk_type+0)==116 && *(chunk_type+1)==82 && *(chunk_type+2)==78 && *(chunk_type+3)==83 {
            if color_type == 3 {
                i32 n = cast(i32, chunk_len);
                if n > 256 { n = 256; }
                for i32 i = 0; i < n; i = i + 1 {
                    pal_alpha[i] = *(chunk_data + i);
                }
            } else if color_type == 0 && chunk_len >= 2 {
                f.has_key = true;
                f.key_r = png_sample(chunk_data, 0, 16);
            } else if color_type == 2 && chunk_len >= 6 {
                f.has_key = true;
                f.key_r = png_sample(chunk_data, 0, 16);
                f.key_g = png_sample(chunk_data, 1, 16);
                f.key_b = png_sample(chunk_data, 2, 16);
            }
        }
        // Unknown critical chunk — first byte of type is uppercase (65-90)
        else {
            u8 first = *(chunk_type + 0);
            if first >= 65 && first <= 90 {
                free(idat_buf);
                return png_error("unknown critical chunk");
            }
            // Ancillary chunk (lowercase first byte): skip
        }

        pos = pos + chunk_total;
    }

    if !got_ihdr { free(idat_buf); return png_error("missing IHDR"); }
    if idat_len == 0 { free(idat_buf); return png_error("no IDAT data"); }

    if color_type == 3 && palette_len == 0 {
        free(idat_buf);
        return png_error("indexed PNG without PLTE");
    }

    f.depth = bit_depth;
    f.ctype = color_type;
    f.palette = &palette[0];
    f.palette_n = palette_len / 3;
    f.pal_alpha = &pal_alpha[0];

    i32 bits_pp = png_channels(color_type) * bit_depth;
    i32 bpp = (bits_pp + 7) / 8;   // filter distance in bytes

    // Filtered size: one filter byte per row of each pass.
    i32 npass = 1;
    if interlace == 1 { npass = 7; }
    i64 raw_len64 = 0;
    for i32 p = 0; p < npass; p++ {
        i32 pw = img_w;
        i32 ph = img_h;
        if interlace == 1 {
            pw = (img_w - png_a7_x0[p] + png_a7_dx[p] - 1) / png_a7_dx[p];
            ph = (img_h - png_a7_y0[p] + png_a7_dy[p] - 1) / png_a7_dy[p];
        }
        if pw > 0 && ph > 0 {
            raw_len64 = raw_len64 + cast(i64, ph) * (1 + png_row_bytes(pw, bits_pp));
        }
    }
    if raw_len64 > 2147483647 { free(idat_buf); return png_error("image too large"); }
    i32 raw_len = cast(i32, raw_len64);

    u8* raw = cast(u8*, alloc(cast(i64, raw_len)));
    i32 out_used = 0;
    i32 zret = zlib_decompress(idat_buf, idat_len, raw, raw_len, &out_used);
    free(idat_buf);

    if zret != 0 {
        free(raw);
        return png_error("zlib decompression failed");
    }
    if out_used != raw_len {
        free(raw);
        return png_error("decompressed size mismatch");
    }

    u8* pixels = cast(u8*, alloc(cast(i64, img_w) * img_h * 4));
    u8* pass_raw = raw;
    for i32 p = 0; p < npass; p++ {
        i32 x0 = 0; i32 y0 = 0; i32 dx = 1; i32 dy = 1;
        if interlace == 1 {
            x0 = png_a7_x0[p]; y0 = png_a7_y0[p];
            dx = png_a7_dx[p]; dy = png_a7_dy[p];
        }
        i32 pw = (img_w - x0 + dx - 1) / dx;
        i32 ph = (img_h - y0 + dy - 1) / dy;
        if pw <= 0 || ph <= 0 { continue; }
        i32 row_bytes = cast(i32, png_row_bytes(pw, bits_pp));
        if !png_unfilter(pass_raw, ph, row_bytes, bpp) {
            free(raw);
            free(pixels);
            return png_error("invalid filter type");
        }
        for i32 y = 0; y < ph; y++ {
            u8* src = pass_raw + y * (1 + row_bytes) + 1;
            u8* dst = pixels + (cast(i64, y0 + y * dy) * img_w + x0) * 4;
            if !png_expand_row(&f, src, pw, dst, dx) {
                free(raw);
                free(pixels);
                return png_error("palette index out of range");
            }
        }
        pass_raw = pass_raw + ph * (1 + row_bytes);
    }

    free(raw);

    PngImage result;
    result.pixels = pixels;
    result.width = img_w;
    result.height = img_h;
    return result;
}

// --- PNG encode ---

private void png_write_u32_be(u8* p, u32 v) {
    *(p + 0) = cast(u8, (v >> 24) & 255);
    *(p + 1) = cast(u8, (v >> 16) & 255);
    *(p + 2) = cast(u8, (v >> 8) & 255);
    *(p + 3) = cast(u8, v & 255);
    return;
}

// Write a PNG chunk: [len BE][type 4B][data][CRC-32 BE over type+data].
// Returns new dstpos, or -1 on overflow.
private i32 png_write_chunk(u8* dst, i32 dstlen, i32 dstpos, u8* type4, u8* data, i32 dlen) {
    if dlen < 0 { return 0 - 1; }
    if dstpos + 12 + dlen > dstlen { return 0 - 1; }
    png_write_u32_be(dst + dstpos, cast(u32, dlen));
    *(dst + dstpos + 4) = *(type4 + 0);
    *(dst + dstpos + 5) = *(type4 + 1);
    *(dst + dstpos + 6) = *(type4 + 2);
    *(dst + dstpos + 7) = *(type4 + 3);
    if dlen > 0 {
        memcpy(dst + dstpos + 8, data, cast(i64, dlen));
    }
    // CRC over type (4 bytes) + data (already contiguous in dst).
    u32 c = crc32(dst + dstpos + 4, 4 + dlen);
    png_write_u32_be(dst + dstpos + 8 + dlen, c);
    return dstpos + 12 + dlen;
}

// Encode RGBA8 pixels into a PNG byte stream.
// Returns 0 on success, negative on error:
//   -1 output buffer too small
//   -2 invalid dimensions
//   -3 internal compression error
i32 png_encode(u8* pixels, i32 width, i32 height, u8* dst, i32 dstlen, i32* out_dstused) {
    if width <= 0 || height <= 0 { return 0 - 2; }

    i32 pos = 0;

    // PNG signature (8 bytes).
    if dstlen < 8 { return 0 - 1; }
    u8[8] sig = {137, 80, 78, 71, 13, 10, 26, 10};
    memcpy(dst, &sig[0], 8);
    pos = 8;

    // IHDR chunk: 13 bytes.
    u8[13] ihdr;
    png_write_u32_be(&ihdr[0], cast(u32, width));
    png_write_u32_be(&ihdr[4], cast(u32, height));
    ihdr[8] = 8;   // bit depth
    ihdr[9] = 6;   // color type: truecolor + alpha (RGBA)
    ihdr[10] = 0;  // compression: deflate
    ihdr[11] = 0;  // filter: adaptive
    ihdr[12] = 0;  // interlace: none
    u8[4] ihdr_type = {73, 72, 68, 82}; // "IHDR"
    pos = png_write_chunk(dst, dstlen, pos, &ihdr_type[0], &ihdr[0], 13);
    if pos < 0 { return 0 - 1; }

    // Build raw scanline buffer: each row is [filter=0][RGBA pixels].
    i32 stride = 1 + width * 4;
    i32 raw_len = height * stride;
    u8* raw = cast(u8*, alloc(cast(i64, raw_len)));
    for i32 y = 0; y < height; y = y + 1 {
        *(raw + y * stride) = 0;
        memcpy(raw + y * stride + 1, pixels + y * width * 4, cast(i64, width * 4));
    }

    // Compress with zlib. Worst case ~ input + 12.5% + overhead; add margin.
    i32 zcap = raw_len + (raw_len >> 2) + 1024;
    if zcap < 128 { zcap = 128; }
    u8* zbuf = cast(u8*, alloc(cast(i64, zcap)));
    i32 zlen = 0;
    i32 zerr = zlib_compress(raw, raw_len, zbuf, zcap, &zlen);
    free(raw);
    if zerr != 0 {
        free(zbuf);
        return 0 - 3;
    }

    // IDAT chunk.
    u8[4] idat_type = {73, 68, 65, 84}; // "IDAT"
    pos = png_write_chunk(dst, dstlen, pos, &idat_type[0], zbuf, zlen);
    free(zbuf);
    if pos < 0 { return 0 - 1; }

    // IEND chunk (zero-length).
    u8[4] iend_type = {73, 69, 78, 68}; // "IEND"
    u8[1] empty;
    empty[0] = 0;
    pos = png_write_chunk(dst, dstlen, pos, &iend_type[0], &empty[0], 0);
    if pos < 0 { return 0 - 1; }

    if out_dstused != cast(i32*, 0) { *out_dstused = pos; }
    return 0;
}

// Save RGBA8 pixels to a PNG file.
// Returns 0 on success, negative on error.
i32 png_save(str path, u8* pixels, i32 width, i32 height) {
    if width <= 0 || height <= 0 { return 0 - 2; }
    i32 raw = width * height * 4;
    i32 cap = raw + (raw >> 2) + 4096;
    if cap < 4096 { cap = 4096; }
    u8* buf = cast(u8*, alloc(cast(i64, cap)));
    i32 len = 0;
    i32 err = png_encode(pixels, width, height, buf, cap, &len);
    if err != 0 {
        free(buf);
        return err;
    }
    FileData fd;
    fd.data = buf;
    fd.len = len;
    bool ok = file_write(path, fd);
    free(buf);
    if !ok { return 0 - 4; }
    return 0;
}

// Load PNG from file path
PngImage png_load(str path) {
    u8* cpath = str_to_cstr(path);
    i64 fd = open(cpath, 0);
    free(cpath);
    if fd == cast(i64, 0) - 1 {
        return png_error("cannot open file");
    }
    // Read entire file
    i32 cap = 65536;
    i32 len = 0;
    u8* buf = cast(u8*, alloc(cast(i64, cap)));
    while true {
        if len + 4096 > cap {
            i32 new_cap = cap * 2;
            u8* new_buf = cast(u8*, alloc(cast(i64, new_cap)));
            memcpy(new_buf, buf, cast(i64, len));
            free(buf);
            buf = new_buf;
            cap = new_cap;
        }
        i32 n = read(fd, buf + len, 4096);
        if n <= 0 { break; }
        len = len + n;
    }
    close(fd);

    PngImage result = png_decode(buf, len);
    free(buf);
    return result;
}
