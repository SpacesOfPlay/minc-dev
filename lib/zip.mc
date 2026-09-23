// zip.mc: ZIP archive writer.
// Depends on: lib/file.mc (FileData, file_read, file_write)
//             lib/zlib.mc (crc32, deflate)
//
// Builds the archive in memory and writes it with one file_write in
// zip_end. An entry is deflated when that shrinks it, stored otherwise.
// Pass compress=false to force stored: payloads that are already
// compressed, or APK members that must stay mmap-able.
//
// Each entry has a Unix mode. zip_add and zip_add_file store 0644 for
// files and 0755 for directory entries (names ending in '/').
// zip_add_mode and zip_add_file_mode take the permission bits; 0x1ED
// (0755) makes a binary executable after unzip on macOS and Linux.
// Windows extractors ignore the mode.
//
// A zero-initialized ZipWriter is ready to use. zip_end and zip_abort
// free everything and reset the writer to that state for reuse.
//
//   ZipWriter z;
//   ignore zip_add(&z, "lib/arm64-v8a/libapp.so", data, len, true);
//   ignore zip_add_file(&z, "assets/tex.png", "build/tex.png", false);
//   ignore zip_add_file_mode(&z, "tool/bin/tool", "build/tool", true, 0x1ED);
//   if !zip_end(&z, "build/app.apk") { /* failed */ }
//
// Errors are sticky. A failed zip_add poisons the writer, zip_end then
// returns false, so intermediate results can be ignored.
//
// Limits: no zip64, at most 65535 entries, archive under 2GB.
// Backslashes in entry names are stored as forward slashes. Names are
// UTF-8 and get the UTF-8 flag when they contain bytes above 0x7F.

#include "file.mc"
#include "zlib.mc"

struct ZipEntry {
    string name;   // owned, '/'-separated
    u32 crc;
    i32 csize;
    i32 usize;
    i32 method;    // 0 = stored, 8 = deflate
    i32 offset;    // local header offset
    u32 flags;     // general-purpose bits, both headers
    u32 mode;      // Unix st_mode, high half of the external attrs
}

struct ZipWriter {
    u8* buf;
    i32 len;
    i32 cap;
    ZipEntry* entries;
    i32 nentries;
    i32 entries_cap;
    bool err;
}

private {
    // Fixed timestamp (2026-01-01 00:00) so identical inputs produce
    // byte-identical archives. DOS date: (year-1980)<<9 | month<<5 | day.
    const u32 ZIP_DOS_DATE = 0x5C21;
    // Keeps len + appended sizes clear of i32 overflow.
    const i32 ZIP_MAX_SIZE = 0x7FF00000;
    // "Version made by": host OS Unix in the high byte, so extractors
    // read the mode; spec 2.0 in the low byte.
    const u32 ZIP_MADE_BY = 0x0314;
    const u32 ZIP_FLAG_UTF8 = 0x800;
    const u32 ZIP_PERM_FILE = 0x1A4;     // 0644
    const u32 ZIP_PERM_DIR = 0x1ED;      // 0755
    const u32 ZIP_S_IFREG = 0x8000;
    const u32 ZIP_S_IFDIR = 0x4000;
    const u32 ZIP_DOS_DIR = 0x10;        // FAT directory attribute
}

private void zb_reserve(ZipWriter* z, i32 n) {
    if z.err { return; }
    if n < 0 || z.len > ZIP_MAX_SIZE - n {
        z.err = true;
        return;
    }
    i32 needed = z.len + n;
    if needed <= z.cap { return; }
    i32 new_cap = z.cap;
    if new_cap < 4096 { new_cap = 4096; }
    while new_cap < needed { new_cap = new_cap * 2; }
    u8* new_buf = alloc<u8>(new_cap);
    if z.len > 0 { memcpy(new_buf, z.buf, z.len); }
    if z.buf != null { free(z.buf); }
    z.buf = new_buf;
    z.cap = new_cap;
    return;
}

private void zb_bytes(ZipWriter* z, u8* p, i32 n) {
    zb_reserve(z, n);
    if z.err || n == 0 { return; }
    memcpy(z.buf + z.len, p, n);
    z.len = z.len + n;
    return;
}

private void zb_u16(ZipWriter* z, u32 v) {
    zb_reserve(z, 2);
    if z.err { return; }
    z.buf[z.len] = cast(u8, v & 255);
    z.buf[z.len + 1] = cast(u8, (v >> 8) & 255);
    z.len = z.len + 2;
    return;
}

private void zb_u32(ZipWriter* z, u32 v) {
    zb_reserve(z, 4);
    if z.err { return; }
    z.buf[z.len] = cast(u8, v & 255);
    z.buf[z.len + 1] = cast(u8, (v >> 8) & 255);
    z.buf[z.len + 2] = cast(u8, (v >> 16) & 255);
    z.buf[z.len + 3] = cast(u8, (v >> 24) & 255);
    z.len = z.len + 4;
    return;
}

void zip_abort(ZipWriter* z) {
    for i32 i = 0; i < z.nentries; i++ {
        free(z.entries[i].name.data);
    }
    if z.entries != null { free(z.entries); }
    if z.buf != null { free(z.buf); }
    *z = ZipWriter{};
    return;
}

// Add an entry with the default mode: 0644, or 0755 for a directory
// entry (name ending in '/').
bool zip_add(ZipWriter* z, str name, u8* data, i64 nbytes, bool compress) {
    bool is_dir = name.len > 0 && name.data[name.len - 1] == '/';
    return zip_add_mode(z, name, data, nbytes, compress, is_dir ? ZIP_PERM_DIR : ZIP_PERM_FILE);
}

// Add an entry with explicit Unix permission bits (0x1ED = 0755,
// 0x1A4 = 0644). The file-type bits are supplied by the writer.
bool zip_add_mode(ZipWriter* z, str name, u8* data, i64 nbytes, bool compress, u32 perm) {
    if z.err { return false; }
    if nbytes > 2147483647 { z.err = true; return false; }
    i32 len = cast(i32, nbytes);
    if name.len <= 0 || name.len > 65535 || len < 0 || (len > 0 && data == null) {
        z.err = true;
        return false;
    }
    if z.nentries >= 65535 {
        z.err = true;
        return false;
    }

    u32 crc = crc32(data, len);
    i32 method = 0;
    u8* payload = data;
    i32 csize = len;
    u8* cbuf = null;
    // Give deflate one byte less than the input: success means the
    // compressed form is strictly smaller, otherwise store.
    if compress && len > 1 {
        cbuf = alloc<u8>(len - 1);
        i32 used = 0;
        if deflate(data, len, cbuf, len - 1, &used) == 0 {
            method = 8;
            payload = cbuf;
            csize = used;
        } else {
            free(cbuf);
            cbuf = null;
        }
    }

    // Owned name copy, '\' stored as '/'.
    string nm = { .data = alloc<u8>(name.len), .len = name.len };
    u32 flags = 0;
    for i32 i = 0; i < name.len; i++ {
        u8 c = name.data[i];
        if c == 92 { c = 47; }
        if c >= 128 { flags = ZIP_FLAG_UTF8; }
        nm.data[i] = c;
    }
    bool is_dir = nm.data[nm.len - 1] == '/';
    u32 mode = (is_dir ? ZIP_S_IFDIR : ZIP_S_IFREG) | (perm & 0xFFF);

    i32 lho = z.len;
    zb_u32(z, 0x04034B50);           // local file header
    zb_u16(z, 20);                   // version needed
    zb_u16(z, flags);
    zb_u16(z, cast(u32, method));
    zb_u16(z, 0);                    // mod time
    zb_u16(z, ZIP_DOS_DATE);         // mod date
    zb_u32(z, crc);
    zb_u32(z, cast(u32, csize));
    zb_u32(z, cast(u32, len));
    zb_u16(z, cast(u32, nm.len));
    zb_u16(z, 0);                    // extra len
    zb_bytes(z, nm.data, nm.len);
    zb_bytes(z, payload, csize);
    if cbuf != null { free(cbuf); }
    if z.err {
        free(nm);
        return false;
    }

    if z.nentries >= z.entries_cap {
        i32 new_cap = z.entries_cap * 2;
        if new_cap < 16 { new_cap = 16; }
        ZipEntry* ne = alloc<ZipEntry>(new_cap);
        if z.nentries > 0 {
            memcpy(ne, z.entries, cast(i64, z.nentries) * sizeof(ZipEntry));
        }
        if z.entries != null { free(z.entries); }
        z.entries = ne;
        z.entries_cap = new_cap;
    }
    z.entries[z.nentries++] = ZipEntry{
        .name = move(nm),
        .crc = crc,
        .csize = csize,
        .usize = len,
        .method = method,
        .offset = lho,
        .flags = flags,
        .mode = mode,
    };
    return true;
}

// Read a file and add it under the given entry name, mode 0644.
bool zip_add_file(ZipWriter* z, str name, str path, bool compress) {
    return zip_add_file_mode(z, name, path, compress, ZIP_PERM_FILE);
}

// Read a file and add it with explicit permission bits (0x1ED = 0755).
bool zip_add_file_mode(ZipWriter* z, str name, str path, bool compress, u32 perm) {
    if z.err { return false; }
    FileData fd = file_read(path);
    if fd.data == null {
        z.err = true;
        return false;
    }
    bool ok = zip_add_mode(z, name, fd.data, fd.len, compress, perm);
    free(fd.data);
    return ok;
}

// Append the central directory, write the archive, reset the writer.
// False if any prior add failed or the file write fails; the writer is
// freed and reusable either way.
@must_use
bool zip_end(ZipWriter* z, str out_path) {
    if z.err {
        zip_abort(z);
        return false;
    }
    i32 cd_off = z.len;
    for i32 i = 0; i < z.nentries; i++ {
        ZipEntry* e = z.entries + i;
        zb_u32(z, 0x02014B50);       // central directory header
        zb_u16(z, ZIP_MADE_BY);
        zb_u16(z, 20);               // version needed
        zb_u16(z, e.flags);
        zb_u16(z, cast(u32, e.method));
        zb_u16(z, 0);                // mod time
        zb_u16(z, ZIP_DOS_DATE);     // mod date
        zb_u32(z, e.crc);
        zb_u32(z, cast(u32, e.csize));
        zb_u32(z, cast(u32, e.usize));
        zb_u16(z, cast(u32, e.name.len));
        zb_u16(z, 0);                // extra len
        zb_u16(z, 0);                // comment len
        zb_u16(z, 0);                // disk number start
        zb_u16(z, 0);                // internal attrs
        // External attrs: st_mode in the high half, FAT bits in the low.
        u32 dos_attr = (e.mode & ZIP_S_IFDIR) != 0 ? ZIP_DOS_DIR : 0;
        zb_u32(z, (e.mode << 16) | dos_attr);
        zb_u32(z, cast(u32, e.offset));
        zb_bytes(z, e.name.data, e.name.len);
    }
    i32 cd_size = z.len - cd_off;
    zb_u32(z, 0x06054B50);           // end of central directory
    zb_u16(z, 0);                    // disk number
    zb_u16(z, 0);                    // central dir disk
    zb_u16(z, cast(u32, z.nentries));
    zb_u16(z, cast(u32, z.nentries));
    zb_u32(z, cast(u32, cd_size));
    zb_u32(z, cast(u32, cd_off));
    zb_u16(z, 0);                    // comment len
    if z.err {
        zip_abort(z);
        return false;
    }
    FileData out = { .data = z.buf, .len = z.len };
    bool ok = file_write(out_path, out);
    zip_abort(z);
    return ok;
}
