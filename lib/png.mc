// png.mc — PNG image decoder + encoder for minc
// Depends on: lib/zlib.mc  (zlib_decompress, zlib_compress, crc32, read_u32_be)
//             lib/file.mc  (file_read, file_write, FileData)
//
// Read:  8-bit grayscale, RGB, grayscale+alpha, RGBA, non-interlaced.
//        Output is always RGBA8 (4 bytes per pixel). Caller must free(pixels).
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
}

private PngImage png_error(u8* msg) {
    eprint("png: ");
    // TODO: remove this strlen, use str instead
    i32 ml = 0; while *(msg + ml) != 0 { ml = ml + 1; }
    write(stderr(), msg, ml);
    eprint("\n");
    PngImage r;
    r.pixels = null;
    r.width = 0;
    r.height = 0;
    return r;
}

// Paeth predictor (PNG spec)
private i32 png_paeth(i32 a, i32 b, i32 c) {
    i32 p = a + b - c;
    i32 pa = p - a; if pa < 0 { pa = 0 - pa; }
    i32 pb = p - b; if pb < 0 { pb = 0 - pb; }
    i32 pc = p - c; if pc < 0 { pc = 0 - pc; }
    if pa <= pb && pa <= pc { return a; }
    if pb <= pc { return b; }
    return c;
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

    while pos + 12 <= len && !got_iend {
        u32 chunk_len = read_u32_be(data + pos);
        u8* chunk_type = data + pos + 4;
        u8* chunk_data = data + pos + 8;
        i32 chunk_total = 12 + cast(i32, chunk_len);

        if pos + chunk_total > len {
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
            if bit_depth != 8 { free(idat_buf); return png_error("unsupported bit depth (only 8-bit)"); }
            if interlace != 0 { free(idat_buf); return png_error("interlaced PNG not supported"); }
            if color_type != 0 && color_type != 2 && color_type != 3 && color_type != 4 && color_type != 6 {
                free(idat_buf);
                return png_error("unsupported color type");
            }
            if img_w <= 0 || img_h <= 0 { free(idat_buf); return png_error("invalid image dimensions"); }
            // Guard against i32 overflow in pixel buffer allocation (max ~32K x 32K)
            if img_w > 32768 || img_h > 32768 { free(idat_buf); return png_error("image too large (max 32768x32768)"); }
        }
        // IDAT
        else if *(chunk_type+0)==73 && *(chunk_type+1)==68 && *(chunk_type+2)==65 && *(chunk_type+3)==84 {
            if !got_ihdr { free(idat_buf); return png_error("IDAT before IHDR"); }
            // Grow idat_buf if needed
            i32 needed = idat_len + cast(i32, chunk_len);
            while needed > idat_cap {
                idat_cap = idat_cap * 2;
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
            for i32 i = 0; i < cast(i32, chunk_len); i = i + 1 {
                palette[i] = *(chunk_data + i);
            }
            palette_len = cast(i32, chunk_len);
        }
        // tRNS — per-index alpha for indexed color (transparency key
        // forms for other color types are ignored)
        else if *(chunk_type+0)==116 && *(chunk_type+1)==82 && *(chunk_type+2)==78 && *(chunk_type+3)==83 {
            if color_type == 3 {
                i32 n = cast(i32, chunk_len);
                if n > 256 { n = 256; }
                for i32 i = 0; i < n; i = i + 1 {
                    pal_alpha[i] = *(chunk_data + i);
                }
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

    // Bytes per pixel for this color type
    i32 bpp = 1;
    if color_type == 0 { bpp = 1; }       // grayscale
    else if color_type == 2 { bpp = 3; }   // RGB
    else if color_type == 3 { bpp = 1; }   // palette index
    else if color_type == 4 { bpp = 2; }   // gray + alpha
    else if color_type == 6 { bpp = 4; }   // RGBA

    if color_type == 3 && palette_len == 0 {
        free(idat_buf);
        return png_error("indexed PNG without PLTE");
    }

    // Decompress IDAT (zlib format)
    i32 raw_len = img_h * (1 + img_w * bpp);  // filter byte + pixels per row
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

    // Unfilter scanlines in place
    i32 stride = 1 + img_w * bpp;  // filter byte + row bytes
    i32 row_bytes = img_w * bpp;

    for i32 y = 0; y < img_h; y = y + 1 {
        u8* row = raw + y * stride;
        i32 ftype = cast(i32, *row);
        u8* cur = row + 1;         // pixel data starts after filter byte
        u8* prev = null;
        if y > 0 { prev = raw + (y - 1) * stride + 1; }

        if ftype == 0 {
            // None: no-op
        } else if ftype == 1 {
            // Sub: cur[i] += cur[i - bpp]
            for i32 i = bpp; i < row_bytes; i = i + 1 {
                *(cur + i) = cast(u8, (cast(i32, *(cur + i)) + cast(i32, *(cur + i - bpp))) & 255);
            }
        } else if ftype == 2 {
            // Up: cur[i] += prev[i]
            if prev != null {
                for i32 i = 0; i < row_bytes; i = i + 1 {
                    *(cur + i) = cast(u8, (cast(i32, *(cur + i)) + cast(i32, *(prev + i))) & 255);
                }
            }
        } else if ftype == 3 {
            // Average: cur[i] += (left + above) / 2
            for i32 i = 0; i < row_bytes; i = i + 1 {
                i32 left = 0; if i >= bpp { left = cast(i32, *(cur + i - bpp)); }
                i32 above = 0; if prev != null { above = cast(i32, *(prev + i)); }
                *(cur + i) = cast(u8, (cast(i32, *(cur + i)) + (left + above) / 2) & 255);
            }
        } else if ftype == 4 {
            // Paeth: cur[i] += paeth(left, above, upper_left)
            for i32 i = 0; i < row_bytes; i = i + 1 {
                i32 left = 0; if i >= bpp { left = cast(i32, *(cur + i - bpp)); }
                i32 above = 0; if prev != null { above = cast(i32, *(prev + i)); }
                i32 upper_left = 0; if prev != null && i >= bpp { upper_left = cast(i32, *(prev + i - bpp)); }
                *(cur + i) = cast(u8, (cast(i32, *(cur + i)) + png_paeth(left, above, upper_left)) & 255);
            }
        } else {
            free(raw);
            return png_error("invalid filter type");
        }
    }

    // Convert to RGBA8
    i32 out_size = img_w * img_h * 4;
    u8* pixels = cast(u8*, alloc(cast(i64, out_size)));

    for i32 y = 0; y < img_h; y = y + 1 {
        u8* src = raw + y * stride + 1;  // skip filter byte
        u8* dst = pixels + y * img_w * 4;

        if color_type == 6 {
            // RGBA: direct copy
            memcpy(dst, src, cast(i64, img_w * 4));
        } else if color_type == 2 {
            // RGB → RGBA
            for i32 x = 0; x < img_w; x = x + 1 {
                *(dst + x * 4 + 0) = *(src + x * 3 + 0);
                *(dst + x * 4 + 1) = *(src + x * 3 + 1);
                *(dst + x * 4 + 2) = *(src + x * 3 + 2);
                *(dst + x * 4 + 3) = 255;
            }
        } else if color_type == 0 {
            // Grayscale → RGBA
            for i32 x = 0; x < img_w; x = x + 1 {
                u8 g = *(src + x);
                *(dst + x * 4 + 0) = g;
                *(dst + x * 4 + 1) = g;
                *(dst + x * 4 + 2) = g;
                *(dst + x * 4 + 3) = 255;
            }
        } else if color_type == 4 {
            // Grayscale+Alpha → RGBA
            for i32 x = 0; x < img_w; x = x + 1 {
                u8 g = *(src + x * 2 + 0);
                u8 a = *(src + x * 2 + 1);
                *(dst + x * 4 + 0) = g;
                *(dst + x * 4 + 1) = g;
                *(dst + x * 4 + 2) = g;
                *(dst + x * 4 + 3) = a;
            }
        } else if color_type == 3 {
            // Palette index → RGBA
            for i32 x = 0; x < img_w; x = x + 1 {
                i32 idx = cast(i32, *(src + x));
                if idx * 3 + 2 >= palette_len {
                    free(raw);
                    free(pixels);
                    return png_error("palette index out of range");
                }
                *(dst + x * 4 + 0) = palette[idx * 3 + 0];
                *(dst + x * 4 + 1) = palette[idx * 3 + 1];
                *(dst + x * 4 + 2) = palette[idx * 3 + 2];
                *(dst + x * 4 + 3) = pal_alpha[idx];
            }
        }
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
        eprint("png: cannot open '{}'\n", path);
        PngImage r;
        r.pixels = null; r.width = 0; r.height = 0;
        return r;
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
