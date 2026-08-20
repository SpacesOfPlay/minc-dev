// terminal.mc — TTY size detection and VT-mode enable.
//
// Per-OS extern surface for terminal queries (ioctl winsize on
// POSIX, GetConsoleScreenBufferInfo / SetConsoleMode on Windows).
//

// --- Per-OS externs + structs (private) -----------------------------

when os(macos) || os(ios) {
    // ioctl is variadic in libc; the trailing ... selects the per-arch
    // varargs ABI (Apple ARM64 stack-only vs AAPCS64 reg-then-stack).
    private extern "libSystem.B.dylib" i32 ioctl(i32 fd, u64 req, ...);
    private const u64 _TERM_TIOCGWINSZ = 0x40087468;
}
when os(linux) || os(android) {
    private extern "libc.so.6" i32 ioctl(i32 fd, u64 req, ...);
    private const u64 _TERM_TIOCGWINSZ = 0x5413;
}
when os(macos) || os(ios) || os(linux) || os(android) {
    // POSIX struct winsize. ws_xpixel/ws_ypixel are 0 on most
    // emulators and unused here.
    private struct _TermWinSize {
        u16 ws_row;
        u16 ws_col;
        u16 ws_xpixel;
        u16 ws_ypixel;
    }
}
when os(windows) {
    private extern "kernel32.dll" i64 GetStdHandle(i32 std);
    private extern "kernel32.dll" i32 SetConsoleMode(i64 h, u32 mode);
    private extern "kernel32.dll" i32 GetConsoleScreenBufferInfo(i64 h, void* info);
    // CONSOLE_SCREEN_BUFFER_INFO, 22 bytes. Visible region is
    // srWindow.{right-left+1, bottom-top+1}; dwSize is the
    // scrollback buffer.
    private struct _TermConsoleInfo {
        i16 size_x;
        i16 size_y;
        i16 cursor_x;
        i16 cursor_y;
        u16 attrs;
        i16 left;
        i16 top;
        i16 right;
        i16 bottom;
        i16 max_x;
        i16 max_y;
    }
}

// --- Public API -----------------------------------------------------

struct TermSize {
    i32 cols;
    i32 rows;
}

// Returns (0, 0) when no size is available (pipe, no tty, wasm).
// Callers pick their own fallback.
TermSize term_size() {
    TermSize r;
    when os(macos) || os(ios) || os(linux) || os(android) {
        _TermWinSize ws;
        if ioctl(1, _TERM_TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0 {
            r.cols = cast(i32, ws.ws_col);
            r.rows = cast(i32, ws.ws_row);
        }
    }
    when os(windows) {
        _TermConsoleInfo info;
        i64 h = GetStdHandle(0 - 11);   // STD_OUTPUT_HANDLE
        if GetConsoleScreenBufferInfo(h, &info) != 0 {
            i32 c = info.right - info.left + 1;
            i32 rr = info.bottom - info.top + 1;
            if c > 0 && rr > 0 { r.cols = c; r.rows = rr; }
        }
    }
    return r;
}

// Enable ANSI escape processing on legacy Windows cmd. No-op on
// modern Windows Terminal, Unix, and wasm.
void term_enable_vt() {
    when os(windows) {
        i64 h = GetStdHandle(0 - 11);   // STD_OUTPUT_HANDLE
        // ENABLE_PROCESSED_OUTPUT (0x1) | ENABLE_WRAP_AT_EOL_OUTPUT (0x2)
        // | ENABLE_VIRTUAL_TERMINAL_PROCESSING (0x4) = 0x7
        SetConsoleMode(h, 7);
    }
}
