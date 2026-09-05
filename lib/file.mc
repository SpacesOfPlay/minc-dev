// file.mc — files, directories, paths, environment.
//
// Paths are UTF-8 and use forward slashes on every platform. Windows
// uses wide APIs.
//
// Platforms: Windows (kernel32), Linux (raw syscalls), macOS
// (libSystem.B.dylib). Directory and environment calls report
// empty/false where unsupported (wasm).

#include "str.mc"

// --- Paths (no I/O) --------------------------------------------------

private bool _path_is_sep(u8 c) {
    return c == '/' || c == '\\';
}

// Join with a single separator.
@must_use
string path_join(str a, str b) {
    if a.len == 0 { return str_concat("", b); }
    if b.len == 0 { return str_concat(a, ""); }
    if _path_is_sep(*b.data) { return str_concat("", b); }
    if _path_is_sep(*(a.data + a.len - 1)) { return str_concat(a, b); }
    string mid = str_concat(a, "/");
    defer free(mid);
    return str_concat(str_from(mid.data, mid.len), b);
}

// Everything before the last separator.
str path_dirname(str p) {
    for i32 i = p.len - 1; i >= 0; i-- {
        if _path_is_sep(*(p.data + i)) { return str_slice(p, 0, i); }
    }
    return str_from(p.data, 0);
}

// Everything after the last separator.
str path_basename(str p) {
    for i32 i = p.len - 1; i >= 0; i-- {
        if _path_is_sep(*(p.data + i)) { return str_slice(p, i + 1, p.len); }
    }
    return p;
}

// Extension including the dot, or empty. A leading dot is a hidden
// file, not an extension.
str path_ext(str p) {
    str base = path_basename(p);
    for i32 i = base.len - 1; i > 0; i-- {
        if *(base.data + i) == '.' { return str_slice(base, i, base.len); }
    }
    return str_from(base.data, 0);
}

// Basename without the extension: "src/main.mc" -> "main".
str path_stem(str p) {
    str base = path_basename(p);
    str ext = path_ext(p);
    return str_slice(base, 0, base.len - ext.len);
}

// Same path, different extension. `ext` starts with a dot.
@must_use
string path_with_ext(str p, str ext) {
    str cur = path_ext(p);
    return str_concat(str_slice(p, 0, p.len - cur.len), ext);
}

bool path_is_abs(str p) {
    if p.len == 0 { return false; }
    if _path_is_sep(*p.data) { return true; }
    // win drive letter
    if p.len >= 3 && *(p.data + 1) == ':' && _path_is_sep(*(p.data + 2)) { return true; }
    return false;
}


// --- Reading and writing ---------------------------------------------

struct FileData {
    u8* data;
    i64 len;
}

private const i64 _FILE_IO_CHUNK = 4194304;   // 4 MB per read/write call

when os(wasm) {
    // Host VFS byte count. Returns -1 when the path is unknown.
    private extern "env" i64 __minc_file_size(u8* path);
}

// Size of the file in bytes, or -1 if it cannot be determined.
i64 file_size(str path) {
    when os(wasm) {
        u8* wp = str_to_cstr(path);
        defer free(wp);
        return __minc_file_size(wp);
    }
    else {
        FileStamp st = file_stamp(path);
        if st.ok { return st.size; }
        return -1;
    }
}

// Read entire file as raw bytes. Returns {null, 0} on error.
// Caller must free() .data.
@must_use
FileData file_read(str path) {
    FileData result = { .data = null, .len = 0 };
    u8* cpath = str_to_cstr(path);
    defer free(cpath);
    i64 fd = open(cpath, 0);
    if fd == -1 {
        return result;
    }
    // One byte past the reported size, so a single extra read sees EOF
    // instead of a growth round-trip. An unknown size just grows.
    i64 cap = 4096;
    when !os(wasm) {
        i64 known = file_size(path);
        if known >= 0 { cap = known + 1; }
        if cap < 4096 { cap = 4096; }
    }
    u8* buf = alloc<u8>(cap);
    i64 len = 0;
    while true {
        if len >= cap {
            i64 new_cap = cap * 2;
            u8* new_buf = alloc<u8>(new_cap);
            memcpy(new_buf, buf, len);
            free(buf);
            buf = new_buf;
            cap = new_cap;
        }
        i64 want = cap - len;
        if want > _FILE_IO_CHUNK { want = _FILE_IO_CHUNK; }
        i32 n = read(fd, buf + len, cast(i32, want));
        if n <= 0 { break; }
        len = len + n;
    }
    close(fd);
    result.data = buf;
    result.len = len;
    return result;
}

// Read entire file as owned string. Returns empty string on error.
// A file larger than 2 GB is an error.
@must_use
string file_read_str(str path) {
    FileData fd = file_read(path);
    if fd.len > 2147483647 {
        free(fd.data);
        string empty = { .data = null, .len = 0 };
        return empty;
    }
    string s = { .data = fd.data, .len = cast(i32, fd.len) };
    return s;
}

// Write raw bytes to file (creates/overwrites). Returns true on success.
bool file_write(str path, FileData data) {
    u8* cpath = str_to_cstr(path);
    defer free(cpath);
    i64 fd = open(cpath, 1);
    if fd == -1 { return false; }
    i64 done = 0;
    while done < data.len {
        i64 want = data.len - done;
        if want > _FILE_IO_CHUNK { want = _FILE_IO_CHUNK; }
        i32 n = write(fd, data.data + done, cast(i32, want));
        if n <= 0 { break; }
        done = done + n;
    }
    close(fd);
    // == len : empty write is a success
    return done == data.len;
}

// Write str to file. Returns true on success.
bool file_write_str(str path, str s) {
    FileData fd = { .data = s.data, .len = s.len };
    return file_write(path, fd);
}

// Copy src's bytes to dst (creates/overwrites). Returns true on
// success. Files minc writes are created 0755, so a copied binary
// stays executable on unix.
bool file_copy(str src, str dst) {
    FileData d = file_read(src);
    if d.data == null { return false; }
    bool ok = file_write(dst, d);
    free(d.data);
    return ok;
}

// file_exists(u8*) is a compiler builtin; path_exists below takes a str.


// --- Platform externs -------------------------------------------------

when os(windows) {
    private {
        extern "kernel32.dll" {
            i32 GetFileAttributesExW(u16* path, i32 level, _Win32FileAttrData* out);
            u32 GetFileAttributesW(u16* path);
            i32 MultiByteToWideChar(u32 cp, u32 flags, u8* mb, i32 cb, u16* wc, i32 cc);
            i32 WideCharToMultiByte(u32 cp, u32 flags, u16* wc, i32 cc, u8* mb, i32 cb, void* def, void* used);
            bool CreateDirectoryW(u16* path, void* sa);
            bool RemoveDirectoryW(u16* path);
            bool DeleteFileW(u16* path);
            i64 FindFirstFileW(u16* pat, _Win32FindDataW* data);
            bool FindNextFileW(i64 h, _Win32FindDataW* data);
            bool FindClose(i64 h);
            i32 GetEnvironmentVariableW(u16* name, u16* buf, i32 size);
            bool SetEnvironmentVariableW(u16* name, u16* val);
            i64 FindFirstChangeNotificationW(u16* path, i32 subtree, u32 filter);
            i32 FindNextChangeNotification(i64 h);
            i32 FindCloseChangeNotification(i64 h);
            u32 WaitForSingleObject(i64 h, u32 ms);
        }

        const u32 _WIN_CP_UTF8 = 65001;
        const i32 _WIN_MAX_PATH = 260;
        const i32 _WIN_PATH_CAP = 1024;      // wide chars, new call sites
        const u32 _WIN_ATTR_DIRECTORY = 0x10;
        const u32 _WIN_ATTR_INVALID = 0xFFFFFFFF;

        // WIN32_FILE_ATTRIBUTE_DATA, 36 bytes. FILETIME is (lo, hi) in
        // 100ns ticks since 1601; size is split hi/lo.
        struct _Win32FileAttrData {
            u32 attrs;
            u32 create_lo;  u32 create_hi;
            u32 access_lo;  u32 access_hi;
            u32 write_lo;   u32 write_hi;
            u32 size_hi;    u32 size_lo;
        }

        // WIN32_FIND_DATAW, 592 bytes: the same head plus the two name
        // buffers.
        struct _Win32FindDataW {
            u32 attrs;
            u32 create_lo;  u32 create_hi;
            u32 access_lo;  u32 access_hi;
            u32 write_lo;   u32 write_hi;
            u32 size_hi;    u32 size_lo;
            u32 reserved0;  u32 reserved1;
            u16[260] file_name;
            u16[14] alt_name;
        }

        // UTF-8 -> UTF-16 for the W APIs. False if it does not fit.
        bool _win_wide(str s, u16* out, i32 cap) {
            u8* c = str_to_cstr(s);
            defer free(c);
            return MultiByteToWideChar(_WIN_CP_UTF8, 0, c, -1, out, cap) > 0;
        }

        // UTF-16 -> UTF-8. Returns the length without the terminator.
        i32 _win_narrow(u16* w, u8* out, i32 cap) {
            i32 n = WideCharToMultiByte(_WIN_CP_UTF8, 0, w, -1, out, cap, null, null);
            if n <= 0 { return 0; }
            return n - 1;
        }
    }
}

when os(macos) || os(ios) {
    private {
        extern "libSystem.B.dylib" {
            i32 stat(u8* path, void* buf);
            i32 kqueue();
            i32 kevent(i32 kq, void* changes, i32 nch, void* events, i32 nev, void* timeout);
            void rewinddir(void* dirp);
            void* _dir_open(u8* path) from "opendir";
            void* _dir_read(void* dirp) from "readdir";
            i32 _dir_close(void* dirp) from "closedir";
            i32 _fs_mkdir(u8* path, i32 mode) from "mkdir";
            i32 _fs_rmdir(u8* path) from "rmdir";
            i32 _fs_unlink(u8* path) from "unlink";
            u8* _fs_getenv(u8* name) from "getenv";
            i32 _fs_setenv(u8* name, u8* val, i32 overwrite) from "setenv";
        }

        // struct kevent, 32 bytes.
        struct _KEvent {
            u64 ident;
            i16 filter;
            u16 flags;
            u32 fflags;
            i64 data;
            u64 udata;
        }
        const i32 _FW_MAX_FILES = 256;       // sanity cap on watched entries
        // Darwin dirent (64-bit inode): d_namlen at 18, d_type at 20,
        // d_name at 21.
        const i32 _DIRENT_NAMLEN_OFF = 18;
        const i32 _DIRENT_TYPE_OFF = 20;
        const i32 _DIRENT_NAME_OFF = 21;
    }
}

// Linux uses syscalls to avoid libc dependency.
when os(linux) {
    private {
        const i32 _FS_AT_FDCWD = -100;
        const i32 _FS_AT_REMOVEDIR = 0x200;
        const i32 _FS_DIR_BUF = 4096;

        // linux_dirent64: d_ino(8) d_off(8) d_reclen(2) d_type(1) d_name[].
        // Same offsets as glibc dirent64.
        const i32 _DIRENT_TYPE_OFF = 18;
        const i32 _DIRENT_NAME_OFF = 19;
        const i32 _DIRENT_RECLEN_OFF = 16;

        struct _LinuxDir {
            i64 fd;
            i32 pos;
            i32 len;
            u8* buf;
        }

        void* _dir_open(u8* path) {
            i64 fd = open(path, 0);
            if fd < 0 { return null; }
            u8* buf = alloc<u8>(_FS_DIR_BUF);
            i32 n = sys_getdents64(cast(i32, fd), cast(void*, buf), _FS_DIR_BUF);
            if n < 0 {
                close(fd);
                free(buf);
                return null;
            }
            _LinuxDir* d = new(_LinuxDir);
            *d = _LinuxDir{ .fd = fd, .pos = 0, .len = n, .buf = buf };
            return cast(void*, d);
        }

        void* _dir_read(void* dirp) {
            _LinuxDir* d = cast(_LinuxDir*, dirp);
            if d.pos >= d.len {
                i32 n = sys_getdents64(cast(i32, d.fd), cast(void*, d.buf), _FS_DIR_BUF);
                if n <= 0 { return null; }
                d.len = n;
                d.pos = 0;
            }
            u8* rec = d.buf + d.pos;
            d.pos = d.pos + cast(i32, *cast(u16*, rec + _DIRENT_RECLEN_OFF));
            return cast(void*, rec);
        }

        i32 _dir_close(void* dirp) {
            _LinuxDir* d = cast(_LinuxDir*, dirp);
            close(d.fd);
            free(d.buf);
            free(cast(void*, d));
            return 0;
        }

        i32 _fs_mkdir(u8* path, i32 mode) {
            return sys_mkdirat(_FS_AT_FDCWD, path, mode);
        }
        i32 _fs_rmdir(u8* path) {
            return sys_unlinkat(_FS_AT_FDCWD, path, _FS_AT_REMOVEDIR);
        }
        i32 _fs_unlink(u8* path) {
            return sys_unlinkat(_FS_AT_FDCWD, path, 0);
        }

        // Index of the entry naming `name`, or -1.
        i32 _env_find(u8** block, u8* name, i32 nlen) {
            i32 i = 0;
            while *(block + i) != null {
                u8* entry = *(block + i);
                bool match = true;
                for i32 k = 0; k < nlen; k++ {
                    if *(entry + k) != *(name + k) { match = false; break; }
                }
                if match && *(entry + nlen) == '=' { return i; }
                i++;
            }
            return -1;
        }

        u8* _fs_getenv(u8* name) {
            i32 nlen = str_from_cstr(name).len;
            u8** e = env_block();
            i32 at = _env_find(e, name, nlen);
            if at < 0 { return null; }
            return *(e + at) + nlen + 1;
        }

        // env_set builds its replacement block out of static storage.
        // survives forks
        const i32 _ENV_ARENA_CAP = 8192;
        const i32 _ENV_MAX = 256;

        u8[_ENV_ARENA_CAP] _env_arena;
        i32 _env_arena_used = 0;
        u8*[_ENV_MAX + 1] _env_slots;
        bool _env_owned = false;

        u8* _env_arena_take(i32 n) {
            if _env_arena_used + n > _ENV_ARENA_CAP { return null; }
            u8* p = &_env_arena[_env_arena_used];
            _env_arena_used = _env_arena_used + n;
            return p;
        }

        // Move the live block into _env_slots.
        bool _env_own() {
            if _env_owned { return true; }
            u8** e = env_block();
            i32 n = 0;
            while *(e + n) != null { n++; }
            if n > _ENV_MAX { return false; }
            for i32 i = 0; i < n; i++ { _env_slots[i] = *(e + i); }
            _env_slots[n] = null;
            _env_owned = true;
            sys_set_envp(&_env_slots[0]);
            return true;
        }

        i32 _fs_setenv(u8* name, u8* val, i32 overwrite) {
            i32 nlen = str_from_cstr(name).len;
            i32 vlen = str_from_cstr(val).len;
            if _env_find(env_block(), name, nlen) >= 0 && overwrite == 0 { return 0; }
            if !_env_own() { return -1; }

            u8* entry = _env_arena_take(nlen + vlen + 2);
            if entry == null { return -1; }
            memcpy(entry, name, cast(i64, nlen));
            *(entry + nlen) = '=';
            memcpy(entry + nlen + 1, val, cast(i64, vlen));
            *(entry + nlen + 1 + vlen) = 0;

            i32 at = _env_find(&_env_slots[0], name, nlen);
            if at >= 0 {
                _env_slots[at] = entry;
                return 0;
            }
            i32 n = 0;
            while _env_slots[n] != null { n++; }
            if n >= _ENV_MAX { return -1; }
            _env_slots[n] = entry;
            _env_slots[n + 1] = null;
            return 0;
        }
    }

    // The environment array this process hands to its children.
    u8** env_block() {
        u8** e = sys_envp();
        if e == null {
            e = sys_argv() + get_argc() + 1;
            sys_set_envp(e);
        }
        return e;
    }
}

when os(linux) || os(android) {
    private {
        const i32 _STAT_AT_FDCWD = 0 - 100;
        const i32 _STAT_STATX_BASIC = 0x7ff;
        const i32 _WATCH_IN_NONBLOCK = 0x800;
        // IN_MODIFY|IN_CLOSE_WRITE|IN_MOVED_FROM|IN_MOVED_TO|IN_CREATE|IN_DELETE
        const i32 _WATCH_IN_MASK = 0x3CA;
    }
}

when os(linux) || os(macos) || os(ios) {
    private {
        const i32 _DT_DIR = 4;
        const i32 _DT_REG = 8;
        const i32 _DIR_MODE = 0x1ED;         // 0755
    }
}


// PATH entry separator. Defined on every target: path_which uses it
// outside any platform block.
when os(windows) { private const u8 _PATH_LIST_SEP = ';'; }
else { private const u8 _PATH_LIST_SEP = ':'; }


// --- Metadata ----------------------------------------------------------

// A file's modification time and size. `mtime` is an opaque
// platform-native value. Compare two stamps of the same file to detect
// change. It is not comparable across platforms.
struct FileStamp {
    u64  mtime;
    i64  size;    // bytes, -1 if unknown
    bool ok;      // false == file not found
}

// Read file metadata without reading its contents or allocating.
// Returns {ok = false} for a missing file or on platforms without
// filesystem metadata (wasm).
FileStamp file_stamp(str path) {
    FileStamp r = {
        .mtime = 0,
        .size = -1,
        .ok = false
    };

    when os(windows) {
        noinit u16[_WIN_PATH_CAP] wpath;
        if _win_wide(path, &wpath[0], _WIN_PATH_CAP) {
            _Win32FileAttrData d;
            if GetFileAttributesExW(&wpath[0], 0, &d) != 0 {   // GetFileExInfoStandard
                r.mtime = (cast(u64, d.write_hi) << 32) | cast(u64, d.write_lo);
                r.size = cast(i64, (cast(u64, d.size_hi) << 32) | cast(u64, d.size_lo));
                r.ok = true;
            }
        }
    }
    when os(macos) || os(ios) {
        // struct stat (Darwin 64-bit inode): st_mtimespec at 48, st_size at 96.
        u8* cpath = str_to_cstr(path);
        defer free(cpath);
        u8[160] buf;
        if stat(cpath, &buf[0]) == 0 {
            i64 sec  = *cast(i64*, &buf[48]);
            i64 nsec = *cast(i64*, &buf[56]);
            r.mtime = cast(u64, sec) * 1000000000 + cast(u64, nsec);
            r.size = *cast(i64*, &buf[96]);
            r.ok = true;
        }
    }
    when os(linux) || os(android) {
        // struct statx: stx_size at 40, stx_mtime.tv_sec at 112, .tv_nsec at 120.
        u8* cpath = str_to_cstr(path);
        defer free(cpath);
        u8[256] buf;
        if sys_statx(_STAT_AT_FDCWD, cpath, 0, _STAT_STATX_BASIC, &buf[0]) == 0 {
            i64 sec  = *cast(i64*, &buf[112]);
            u32 nsec = *cast(u32*, &buf[120]);
            r.mtime = cast(u64, sec) * 1000000000 + cast(u64, nsec);
            r.size = cast(i64, *cast(u64*, &buf[40]));
            r.ok = true;
        }
    }

    return r;
}

// true if two stamps differ
bool file_stamp_changed(FileStamp a, FileStamp b) {
    return a.mtime != b.mtime || a.size != b.size;
}

// True if anything exists at `path`, file or directory. Use
// file_stamp(path).size for the size.
bool path_exists(str path) {
    return file_stamp(path).ok;
}

bool path_is_dir(str path) {
    bool r = false;
    when os(windows) {
        noinit u16[_WIN_PATH_CAP] wpath;
        if _win_wide(path, &wpath[0], _WIN_PATH_CAP) {
            u32 a = GetFileAttributesW(&wpath[0]);
            r = a != _WIN_ATTR_INVALID && (a & _WIN_ATTR_DIRECTORY) != 0;
        }
    }
    when os(linux) || os(macos) || os(ios) {
        u8* cpath = str_to_cstr(path);
        defer free(cpath);
        void* d = _dir_open(cpath);
        if d != null {
            _dir_close(d);
            r = true;
        }
    }
    return r;
}


// --- Directories --------------------------------------------------------

// Owned list of entry names. Free with dir_list_free.
struct DirList {
    str* items;
    i32 count;
    i32 _cap;
}

private void _dir_list_push(DirList* l, u8* name, i32 len) {
    if l.count >= l._cap {
        i32 nc = l._cap * 2;
        if nc < 16 { nc = 16; }
        str* ni = alloc<str>(nc);
        for i32 i = 0; i < l.count; i++ { ni[i] = l.items[i]; }
        if l.items != null { free(cast(void*, l.items)); }
        l.items = ni;
        l._cap = nc;
    }
    u8* copy = alloc<u8>(cast(i64, len + 1));
    memcpy(copy, name, cast(i64, len));
    *(copy + len) = 0;
    l.items[l.count] = str_from(copy, len);
    l.count = l.count + 1;
    return;
}

void dir_list_free(DirList* l) {
    for i32 i = 0; i < l.count; i++ { free(l.items[i].data); }
    if l.items != null { free(cast(void*, l.items)); }
    l.items = null;
    l.count = 0;
    l._cap = 0;
    return;
}

// Entry names (not paths) directly inside `dir`, sorted, "." and ".."
// excluded. `ext` filters by extension when non-empty. `want_dirs`
// selects directories instead of files.
@must_use
DirList dir_list(str dir, str ext, bool want_dirs) {
    DirList l = { .items = null, .count = 0, ._cap = 0 };

    when os(windows) {
        // FindFirstFile needs a wildcard; the extension is filtered
        // (Win32's "*.mc" also matches "x.mcx" where short names are enabled).
        string pat = path_join(dir, "*");
        defer free(pat);
        noinit u16[_WIN_PATH_CAP] wpat;
        bool okpat = _win_wide(str_from(pat.data, pat.len), &wpat[0], _WIN_PATH_CAP);
        if okpat {
            noinit _Win32FindDataW fd;
            i64 h = FindFirstFileW(&wpat[0], &fd);
            if h != -1 {
                noinit u8[_WIN_PATH_CAP] name;
                while true {
                    bool is_dir = (fd.attrs & _WIN_ATTR_DIRECTORY) != 0;
                    i32 nlen = _win_narrow(&fd.file_name[0], &name[0], _WIN_PATH_CAP);
                    str sn = str_from(&name[0], nlen);
                    bool skip = str_equal(sn, ".") || str_equal(sn, "..");
                    if !skip && is_dir == want_dirs {
                        if ext.len == 0 || str_ends_with(sn, ext) {
                            _dir_list_push(&l, &name[0], nlen);
                        }
                    }
                    if !FindNextFileW(h, &fd) { break; }
                }
                FindClose(h);
            }
        }
    }

    when os(linux) || os(macos) || os(ios) {
        u8* cdir = str_to_cstr(dir);
        defer free(cdir);
        void* dp = _dir_open(cdir);
        if dp != null {
            while true {
                u8* de = cast(u8*, _dir_read(dp));
                if de == null { break; }
                u8* name = de + _DIRENT_NAME_OFF;
                i32 nlen = 0;
                while *(name + nlen) != 0 { nlen++; }
                str sn = str_from(name, nlen);
                bool skip = str_equal(sn, ".") || str_equal(sn, "..");
                bool is_dir = cast(i32, *(de + _DIRENT_TYPE_OFF)) == _DT_DIR;
                if !skip && is_dir == want_dirs {
                    if ext.len == 0 || str_ends_with(sn, ext) {
                        _dir_list_push(&l, name, nlen);
                    }
                }
            }
            _dir_close(dp);
        }
    }

    // Insertion sort: listings are small, and the order has to match
    // across platforms so test output is comparable.
    for i32 i = 1; i < l.count; i++ {
        str key = l.items[i];
        i32 j = i - 1;
        while j >= 0 && str_compare(l.items[j], key) > 0 {
            l.items[j + 1] = l.items[j];
            j = j - 1;
        }
        l.items[j + 1] = key;
    }
    return l;
}

// Files in `dir` with the given extension, sorted.
@must_use
DirList dir_list_ext(str dir, str ext) {
    return dir_list(dir, ext, false);
}

private bool _dir_create_one(str path) {
    bool r = false;
    when os(windows) {
        noinit u16[_WIN_PATH_CAP] wpath;
        if _win_wide(path, &wpath[0], _WIN_PATH_CAP) {
            r = CreateDirectoryW(&wpath[0], null);
        }
    }
    when os(linux) || os(macos) || os(ios) {
        u8* cpath = str_to_cstr(path);
        defer free(cpath);
        r = _fs_mkdir(cpath, _DIR_MODE) == 0;
    }
    return r;
}

// Create `path` and any missing parents. True if it exists afterwards.
bool dir_create(str path) {
    if path.len == 0 { return false; }
    if path_is_dir(path) { return true; }
    for i32 i = 1; i < path.len; i++ {
        if _path_is_sep(*(path.data + i)) {
            str head = str_slice(path, 0, i);
            if !path_is_dir(head) { ignore _dir_create_one(head); }
        }
    }
    ignore _dir_create_one(path);
    return path_is_dir(path);
}

bool file_remove(str path) {
    bool r = false;
    when os(windows) {
        noinit u16[_WIN_PATH_CAP] wpath;
        if _win_wide(path, &wpath[0], _WIN_PATH_CAP) {
            r = DeleteFileW(&wpath[0]);
        }
    }
    when os(linux) || os(macos) || os(ios) {
        u8* cpath = str_to_cstr(path);
        defer free(cpath);
        r = _fs_unlink(cpath) == 0;
    }
    return r;
}

// Delete `dir` and everything under it. True when it is gone.
bool dir_remove(str dir) {
    if !path_is_dir(dir) {
        if path_exists(dir) { return file_remove(dir); }
        return true;
    }
    DirList files = dir_list(dir, "", false);
    for i32 i = 0; i < files.count; i++ {
        string p = path_join(dir, files.items[i]);
        defer free(p);
        ignore file_remove(str_from(p.data, p.len));
    }
    dir_list_free(&files);

    DirList dirs = dir_list(dir, "", true);
    for i32 i = 0; i < dirs.count; i++ {
        string p = path_join(dir, dirs.items[i]);
        defer free(p);
        ignore dir_remove(str_from(p.data, p.len));
    }
    dir_list_free(&dirs);

    bool r = false;
    when os(windows) {
        noinit u16[_WIN_PATH_CAP] wpath;
        if _win_wide(dir, &wpath[0], _WIN_PATH_CAP) { r = RemoveDirectoryW(&wpath[0]); }
    }
    when os(linux) || os(macos) || os(ios) {
        u8* cdir = str_to_cstr(dir);
        defer free(cdir);
        r = _fs_rmdir(cdir) == 0;
    }
    return r;
}


// --- Environment, PATH ---------------------------------------------------

// Value of `name`, or empty when unset. Owned.
@must_use
string env_get(str name) {
    string out = { .data = null, .len = 0 };
    when os(windows) {
        noinit u16[_WIN_PATH_CAP] wname;
        if _win_wide(name, &wname[0], _WIN_PATH_CAP) {
            // Ask for the length first: PATH outgrows any fixed buffer
            // worth putting on the stack.
            i32 nchars = GetEnvironmentVariableW(&wname[0], null, 0);
            if nchars > 0 {
                u16* wval = alloc<u16>(nchars);
                defer free(cast(void*, wval));
                if GetEnvironmentVariableW(&wname[0], wval, nchars) > 0 {
                    // UTF-8 is at most 3 bytes per UTF-16 unit here.
                    i32 cap = nchars * 3 + 1;
                    u8* buf = alloc<u8>(cast(i64, cap));
                    i32 n = _win_narrow(wval, buf, cap);
                    if n > 0 {
                        out.data = buf;
                        out.len = n;
                    } else {
                        free(buf);
                    }
                }
            }
        }
    }
    when os(linux) || os(macos) || os(ios) {
        u8* cname = str_to_cstr(name);
        defer free(cname);
        u8* v = _fs_getenv(cname);
        if v != null {
            i32 n = 0;
            while *(v + n) != 0 { n++; }
            u8* buf = alloc<u8>(cast(i64, n + 1));
            memcpy(buf, v, cast(i64, n + 1));
            out.data = buf;
            out.len = n;
        }
    }
    return out;
}

bool env_set(str name, str value) {
    bool r = false;
    when os(windows) {
        noinit u16[_WIN_PATH_CAP] wname;
        noinit u16[_WIN_PATH_CAP] wval;
        if _win_wide(name, &wname[0], _WIN_PATH_CAP)
            && _win_wide(value, &wval[0], _WIN_PATH_CAP) {
            r = SetEnvironmentVariableW(&wname[0], &wval[0]);
        }
    }
    when os(linux) || os(macos) || os(ios) {
        u8* cname = str_to_cstr(name);
        defer free(cname);
        u8* cval = str_to_cstr(value);
        defer free(cval);
        r = _fs_setenv(cname, cval, 1) == 0;
    }
    return r;
}

// Path to `program` as found on PATH, or empty. A name that already
// holds a separator is returned as-is when it exists. On Windows
// ".exe" is tried when the name has no extension. Owned.
@must_use
string path_which(str program) {
    string none = { .data = null, .len = 0 };
    if program.len == 0 { return none; }

    bool has_sep = false;
    for i32 i = 0; i < program.len; i++ {
        if _path_is_sep(*(program.data + i)) { has_sep = true; }
    }
    if has_sep {
        if path_exists(program) { return str_concat(program, ""); }
        when os(windows) {
            string withexe = str_concat(program, ".exe");
            if path_exists(str_from(withexe.data, withexe.len)) { return withexe; }
            free(withexe);
        }
        return none;
    }

    string path = env_get("PATH");
    defer free(path);
    if path.len == 0 { return none; }
    i32 start = 0;
    for i32 i = 0; i <= path.len; i++ {
        bool at_end = i == path.len;
        if !at_end && *(path.data + i) != _PATH_LIST_SEP { continue; }
        if i > start {
            str dir = str_from(path.data + start, i - start);
            string cand = path_join(dir, program);
            if path_exists(str_from(cand.data, cand.len)) { return cand; }
            when os(windows) {
                string withexe = str_concat(str_from(cand.data, cand.len), ".exe");
                if path_exists(str_from(withexe.data, withexe.len)) {
                    free(cand);
                    return withexe;
                }
                free(withexe);
            }
            free(cand);
        }
        start = i + 1;
    }
    return none;
}


// --- file_watch: event-driven directory change notification ------------
//
// Watch a directory for changes to its entries (create / modify /
// delete / rename).
//
// macOS: a kqueue watch on the directory alone only sees entry create /
// delete / rename. Each file in the directory gets its own watch.

// FileWatch. Fields are opaque platform internals.
struct FileWatch {
    i64  h;      // win: notify handle; linux: inotify fd; macos: kqueue fd
    i64  aux;    // macos: watched dir fd; unused elsewhere
    bool ok;     // false if the watch could not be opened, or on wasm
    i64* files;  // macos: fds of per-entry vnode watches
    i32  nfiles;
    u8*  dir;    // macos: owned dir path, for entry rescans
}

when os(macos) || os(ios) {
    // (Re)register a vnode watch on every regular file in w.dir.
    private void _fw_scan_files(FileWatch* w) {
        for i32 i = 0; i < w.nfiles; i++ { close(w.files[i]); }
        w.nfiles = 0;
        if w.files != null { free(cast(void*, w.files)); w.files = null; }
        void* dp = _dir_open(w.dir);
        if dp == null { return; }
        // size the fd array to the actual entry count
        i32 nreg = 0;
        while true {
            u8* d = cast(u8*, _dir_read(dp));
            if d == null { break; }
            if cast(i32, *(d + _DIRENT_TYPE_OFF)) == _DT_REG { nreg++; }
        }
        if nreg == 0 { _dir_close(dp); return; }
        if nreg > _FW_MAX_FILES { nreg = _FW_MAX_FILES; }
        w.files = alloc<i64>(nreg);
        rewinddir(dp);
        i64 dlen = 0;
        while *(w.dir + dlen) != 0 { dlen++; }
        // dir + '/' prefix once.
        noinit u8[1024] p;
        if dlen + 1 >= 1024 { _dir_close(dp); return; }
        memcpy(&p[0], w.dir, dlen);
        p[dlen] = '/';
        while w.nfiles < nreg {
            u8* de = cast(u8*, _dir_read(dp));
            if de == null { break; }
            if cast(i32, *(de + _DIRENT_TYPE_OFF)) != _DT_REG { continue; }
            i64 nlen = cast(i64, *cast(u16*, de + _DIRENT_NAMLEN_OFF));
            if dlen + 1 + nlen + 1 > 1024 { continue; }
            memcpy(&p[dlen + 1], de + _DIRENT_NAME_OFF, nlen);
            p[dlen + 1 + nlen] = 0;
            i64 fd = open(&p[0], 0);
            if fd == -1 { continue; }
            _KEvent ch = {
                .ident = cast(u64, fd),
                .filter = -4,       // EVFILT_VNODE
                .flags = 0x21,      // EV_ADD|EV_CLEAR
                .fflags = 0x27,     // NOTE_DELETE|WRITE|EXTEND|RENAME
                .data = 0,
                .udata = 0
            };
            if kevent(cast(i32, w.h), &ch, 1, null, 0, null) == -1 {
                close(fd);
                continue;
            }
            w.files[w.nfiles] = fd;
            w.nfiles++;
        }
        _dir_close(dp);
    }
}

// Open a watch on directory `dir`.
// Returns {ok = false} on failure or where unsupported (wasm).
FileWatch file_watch_dir(str dir) {
    FileWatch r = { .h = -1, .aux = -1, .ok = false };
    u8* cdir = str_to_cstr(dir);
    defer free(cdir);

    when os(windows) {
        u16[_WIN_MAX_PATH] wdir;
        MultiByteToWideChar(_WIN_CP_UTF8, 0, cdir, -1, &wdir[0], _WIN_MAX_PATH);
        // FILE_NOTIFY_CHANGE_FILE_NAME|SIZE|LAST_WRITE, no subtree
        i64 h = FindFirstChangeNotificationW(&wdir[0], 0, 0x19);
        if h != -1 && h != 0 { r.h = h; r.ok = true; }
    }
    when os(linux) || os(android) {
        i32 fd = sys_inotify_init1(_WATCH_IN_NONBLOCK);
        if fd >= 0 {
            if sys_inotify_add_watch(fd, cdir, _WATCH_IN_MASK) >= 0 {
                r.h = fd;
                r.ok = true;
            }
            else {
                close(fd);
            }
        }
    }
    when os(macos) || os(ios) {
        i64 dirfd = open(cdir, 0);   // O_RDONLY directory fd
        if dirfd != -1 {
            i32 kq = kqueue();
            if kq >= 0 {
                _KEvent ch = {
                    .ident = cast(u64, dirfd),
                    .filter = -4,       // EVFILT_VNODE
                    .flags = 0x21,      // EV_ADD|EV_CLEAR
                    .fflags = 0x27,     // NOTE_DELETE|WRITE|EXTEND|RENAME
                    .data = 0,
                    .udata = 0
                };
                if kevent(kq, &ch, 1, null, 0, null) != -1 {
                    r.h = kq;
                    r.aux = dirfd;
                    r.ok = true;
                    i64 dl = 0;
                    while *(cdir + dl) != 0 { dl++; }
                    r.dir = alloc<u8>(dl + 1);
                    memcpy(r.dir, cdir, dl + 1);
                    _fw_scan_files(&r);
                }
                else {
                    close(kq);
                    close(dirfd);
                }
            }
            else {
                close(dirfd);
            }
        }
    }

    return r;
}

// Non-blocking, clear events.
// Return true if any change fired since the last poll.
bool file_watch_poll(FileWatch* w) {
    if !w.ok { return false; }
    when os(windows) {
        if WaitForSingleObject(w.h, 0) == 0 {    // WAIT_OBJECT_0
            FindNextChangeNotification(w.h);     // re-arm
            return true;
        }
        return false;
    } else when os(linux) || os(android) {
        u8[4096] buf;
        bool got = false;
        while read(w.h, &buf[0], 4096) > 0 { got = true; }
        return got;
    } else when os(macos) || os(ios) {
        _KEvent ev;
        i64[2] ts;   // struct timespec {0,0}: non-blocking
        bool got = false;
        bool rescan = false;
        while kevent(cast(i32, w.h), null, 0, &ev, 1, &ts[0]) > 0 {
            got = true;
            // Dir entries changed, or a watched file was renamed-over /
            // deleted (its fd now tracks a dead inode): re-register.
            if ev.ident == cast(u64, w.aux) { rescan = true; }
            else if (ev.fflags & 0x21) != 0 { rescan = true; }   // DELETE|RENAME
        }
        if rescan { _fw_scan_files(w); }
        return got;
    } else {
        return false;   // no file-watch backend on this target
    }
}

// Close the watch and release its handles.
void file_watch_close(FileWatch* w) {
    if !w.ok { return; }
    when os(windows) {
        FindCloseChangeNotification(w.h);
    }
    when os(linux) || os(android) {
        close(w.h);
    }
    when os(macos) || os(ios) {
        for i32 i = 0; i < w.nfiles; i++ { close(w.files[i]); }
        w.nfiles = 0;
        if w.files != null { free(w.files); w.files = null; }
        if w.dir != null { free(w.dir); w.dir = null; }
        close(w.h);
        close(w.aux);
    }
    w.ok = false;
}
