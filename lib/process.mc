// process.mc — spawn child processes, capture their output, wait for exit.
//
// Built for build scripts and tooling: run a compiler, a packer, qemu,
// gh, etc. Capture exit codes and act on output.
//
//     ProcCmd c = { .args = { "zig", "cc", "-c", src }, .capture = true };
//     ProcResult r = proc_run(&c);
//     if !proc_ok(&r) { print(r.out); }
//     proc_result_free(&r);
//
// proc_init / proc_arg can be used for step by step setup.
//
// Platforms: Windows (kernel32), Linux (raw syscalls), macOS
// (libSystem.B.dylib). On wasm or unsupported platforms proc_run
// reports a spawn failure.
//
// The program is looked up on PATH when it has no directory separator,
// so "zig", "gh", etc. work without an absolute path.
//
// POSIX takes an argv vector directly. Windows takes one command-line
// string. proc_run applies MSVCRT quoting rules.
//

#include "str.mc"
#include "file.mc"

const i32 PROC_MAX_ARGS = 64;

// Returned in ProcResult.exit_code when the child never ran, or ran and
// was killed at the timeout. Both are outside the 0-255 range a POSIX
// child can exit with, and negative, so `!= 0` still means failure.
const i32 PROC_ERR_SPAWN = -1;
const i32 PROC_ERR_TIMEOUT = -2;

// A command. Write it as a literal when the shape is fixed:
//
//     ProcCmd c = { .args = { "zig", "cc", "-c", src }, .capture = true };
//
// or build it up when the arguments are conditional:
//
//     ProcCmd c;
//     proc_init(&c, "zig");
//     proc_arg(&c, "cc");
//
// args[0] is the program. The list ends at the first unset slot, so no
// count is stored; an empty string is still an argument, since only an
// absent one has a null .data. Every option's default is its zero
// value, so a literal never has to spell them out.
struct ProcCmd {
    str[PROC_MAX_ARGS] args;
    str cwd;             // empty: inherit the parent's directory
    i32 timeout_ms;      // 0: wait forever
    bool capture;        // collect the child's stdout into ProcResult.out
    bool split_stderr;   // keep stderr out of the capture; default merges
    bool overflow;       // more than PROC_MAX_ARGS args were added
}

// Argument count, up to the first unset slot.
i32 proc_nargs(ProcCmd* c) {
    i32 n = 0;
    while n < PROC_MAX_ARGS && c.args[n].data != null { n = n + 1; }
    return n;
}

struct ProcResult {
    i32 exit_code;    // the child's status, or a PROC_ERR_* value
    string out;       // captured output; empty unless .capture was set
    bool spawned;     // false when the child could not be started
    bool timed_out;   // true when it was killed at timeout_ms
}

private {
    const i32 _PROC_CHUNK = 4096;        // pipe read buffer
    const i32 _PROC_TICK_MS = 1;         // sleep between wait polls
    const i32 _PROC_KILL_GRACE_MS = 2000;
    const i32 _PROC_KILL_EXIT_CODE = 1;
}

// --- Per-platform externs -------------------------------------------
//

when os(windows) {
    private {
        // Win32 structs. minc alignment matches C.
        struct _ProcSecurityAttrs {
            u32 n_length;
            void* sec_descriptor;
            i32 inherit_handle;
        }

        struct _ProcStartupInfo {
            u32 cb;
            u8* reserved;
            u8* desktop;
            u8* title;
            u32 dw_x;
            u32 dw_y;
            u32 dw_x_size;
            u32 dw_y_size;
            u32 dw_x_count_chars;
            u32 dw_y_count_chars;
            u32 fill_attribute;
            u32 flags;
            u16 show_window;
            u16 cb_reserved2;
            u8* reserved2;
            i64 h_std_input;
            i64 h_std_output;
            i64 h_std_error;
        }

        struct _ProcProcessInfo {
            i64 h_process;
            i64 h_thread;
            u32 process_id;
            u32 thread_id;
        }

        extern "kernel32.dll" {
            bool _proc_create_pipe(i64* rd, i64* wr, _ProcSecurityAttrs* sa, i32 size) from "CreatePipe";
            bool _proc_set_handle_info(i64 h, i32 mask, i32 flags) from "SetHandleInformation";
            bool _proc_create_process(u16* app, u16* cmd, void* pa, void* ta,
                bool inherit, i32 flags, void* env, u16* dir,
                _ProcStartupInfo* si, _ProcProcessInfo* pi) from "CreateProcessW";
            i32 _proc_mb2wc(u32 cp, u32 flags, u8* mb, i32 cb, u16* wc, i32 cc) from "MultiByteToWideChar";
            i32 _proc_wait_single(i64 h, i32 ms) from "WaitForSingleObject";
            bool _proc_get_exit_code(i64 h, i32* code) from "GetExitCodeProcess";
            bool _proc_terminate(i64 h, i32 code) from "TerminateProcess";
            bool _proc_close_handle(i64 h) from "CloseHandle";
            bool _proc_read_file(i64 h, void* buf, i32 n, i32* got, void* ov) from "ReadFile";
            bool _proc_peek_pipe(i64 h, void* buf, i32 n, i32* got, i32* avail, i32* left) from "PeekNamedPipe";
        }

        const u32 _PROC_CP_UTF8 = 65001;
        const i32 _PROC_STARTF_USESTDHANDLES = 0x100;
        const i32 _PROC_HANDLE_FLAG_INHERIT = 1;
        const i32 _PROC_WAIT_OBJECT_0 = 0;
        const i32 _PROC_WAIT_TIMEOUT = 258;
        const i32 _PROC_WAIT_INFINITE = -1;
        const bool _PROC_INHERIT_HANDLES = true;
    }
}

// Linux uses syscalls to avoid libc dependency.
when os(linux) {
    private {
        const i32 _PROC_PATH_CAP = 4096;

        i32 _proc_pipe(i32* fds) { return sys_pipe2(fds, 0); }

        i32 _proc_dup2(i32 oldfd, i32 newfd) {
            // dup3 rejects oldfd == newfd, where dup2 returns it unchanged.
            if oldfd == newfd { return newfd; }
            return sys_dup3(oldfd, newfd, 0);
        }

        i32 _proc_fork() { return sys_fork(); }
        i32 _proc_chdir(u8* path) { return sys_chdir(path); }
        i32 _proc_kill(i32 pid, i32 sig) { return sys_kill(pid, sig); }

        i32 _proc_waitpid(i32 pid, i32* status, i32 opts) {
            return sys_wait4(pid, status, opts, null);
        }

        i32 _proc_poll(void* fds, u64 nfds, i32 timeout) {
            // A negative timeout means wait forever.
            if timeout < 0 {
                return sys_ppoll(fds, cast(i64, nfds), null, null);
            }
            i64[2] ts = { timeout / 1000, cast(i64, timeout % 1000) * 1000000 };
            return sys_ppoll(fds, cast(i64, nfds), cast(void*, &ts[0]), null);
        }

        // Value of NAME in `envp`, or null.
        u8* _proc_env_find(u8** envp, u8* name, i32 nlen) {
            i32 i = 0;
            while *(envp + i) != null {
                u8* e = *(envp + i);
                bool match = true;
                for i32 k = 0; k < nlen; k++ {
                    if *(e + k) != *(name + k) { match = false; break; }
                }
                if match && *(e + nlen) == '=' { return e + nlen + 1; }
                i++;
            }
            return null;
        }

        // execvp on syscalls: exec the file directly when the name contains a
        // separator, else look at PATH. Returns only on failure. Allocation-free
        // for fork-safety.
        i32 _proc_execvp(u8* file, u8** argv) {
            u8** envp = env_block();

            i32 flen = str_from_cstr(file).len;
            bool has_sep = false;
            for i32 i = 0; i < flen; i++ {
                if *(file + i) == '/' { has_sep = true; }
            }
            if has_sep { return sys_execve(file, argv, envp); }

            u8* path = _proc_env_find(envp, "PATH", 4);
            if path == null { return sys_execve(file, argv, envp); }

            noinit u8[_PROC_PATH_CAP] buf;
            i32 i = 0;
            while true {
                i32 n = 0;
                while *(path + i) != 0 && *(path + i) != ':' {
                    if n < _PROC_PATH_CAP - flen - 2 { buf[n] = *(path + i); n++; }
                    i++;
                }
                // An empty element means the working directory, so the name
                // goes in bare — no separator to add.
                if n > 0 && buf[n - 1] != '/' { buf[n] = '/'; n++; }
                for i32 k = 0; k < flen; k++ { buf[n] = *(file + k); n++; }
                buf[n] = 0;
                ignore sys_execve(&buf[0], argv, envp);
                if *(path + i) == 0 { break; }
                i++;
            }
            return -1;
        }
    }
}

when os(macos) {
    private {
        extern "libSystem.B.dylib" {
            i32 _proc_pipe(i32* fds) from "pipe";
            i32 _proc_dup2(i32 oldfd, i32 newfd) from "dup2";
            i32 _proc_fork() from "fork";
            i32 _proc_execvp(u8* file, u8** argv) from "execvp";
            i32 _proc_waitpid(i32 pid, i32* status, i32 opts) from "waitpid";
            i32 _proc_chdir(u8* path) from "chdir";
            i32 _proc_kill(i32 pid, i32 sig) from "kill";
            i32 _proc_poll(void* fds, u32 nfds, i32 timeout) from "poll";
        }
    }
}

when os(linux) || os(macos) {
    private {
        // native struct pollfd; int fd
        struct _ProcPollFd {
            i32 fd;
            i16 events;
            i16 revents;
        }
        const i16 _PROC_POLLIN = 0x0001;
        const i32 _PROC_POLL_WAIT_MS = 5;
        const i32 _PROC_WNOHANG = 1;
        const i32 _PROC_SIGKILL = 9;
        const i32 _PROC_STDOUT_FD = 1;
        const i32 _PROC_STDERR_FD = 2;
        // Exit status of a child that could not exec, by convention.
        const i32 _PROC_EXEC_FAILED = 127;
        // wait(2) packs the exit code into bits 8-15; a signal death
        // puts the signal in the low 7 bits.
        const i32 _PROC_STATUS_SHIFT = 8;
        const i32 _PROC_STATUS_MASK = 0xFF;
        const i32 _PROC_STATUS_SIG_MASK = 0x7F;
    }
}

// --- Building a command ---------------------------------------------

void proc_init(ProcCmd* c, str program) {
    c.args[0] = program;
    c.args[1] = str_from(null, 0);
    c.cwd = "";
    c.timeout_ms = 0;
    c.capture = false;
    c.split_stderr = false;
    c.overflow = false;
    return;
}

void proc_arg(ProcCmd* c, str a) {
    i32 n = proc_nargs(c);
    if n >= PROC_MAX_ARGS {
        c.overflow = true;
        return;
    }
    c.args[n] = a;
    if n + 1 < PROC_MAX_ARGS { c.args[n + 1] = str_from(null, 0); }
    return;
}

void proc_arg_cstr(ProcCmd* c, u8* a) {
    proc_arg(c, str_from_cstr(a));
    return;
}

// Working directory for the child. The parent's own cwd is untouched.
void proc_cwd(ProcCmd* c, str dir) {
    c.cwd = dir;
    return;
}

// Kill the child after ms milliseconds and report timed_out. 0 waits
// forever.
void proc_timeout(ProcCmd* c, i32 ms) {
    c.timeout_ms = ms;
    return;
}

// Collect the child's output into ProcResult.out instead of letting it
// through to the parent's stdout. stderr follows stdout unless
// proc_merge_stderr turns that off.
void proc_capture(ProcCmd* c, bool on) {
    c.capture = on;
    return;
}

void proc_merge_stderr(ProcCmd* c, bool on) {
    c.split_stderr = !on;
    return;
}

bool proc_ok(ProcResult* r) {
    return r.spawned && r.exit_code == 0;
}

void proc_result_free(ProcResult* r) {
    if r.out.data != null { free(r.out.data); }
    r.out.data = null;
    r.out.len = 0;
    return;
}

// --- Windows command-line quoting ------------------------------------
//

when os(windows) {
    private {
        void _proc_win_quote(str_buf* sb, str a) {
            bool need = a.len == 0;
            for i32 i = 0; i < a.len; i++ {
                u8 ch = *(a.data + i);
                if ch == ' ' || ch == '\t' || ch == '"' { need = true; }
            }
            if !need {
                str_buf_add(sb, a);
                return;
            }
            str_buf_add_byte(sb, '"');
            i32 nbs = 0;
            for i32 i = 0; i < a.len; i++ {
                u8 ch = *(a.data + i);
                if ch == '\\' {
                    nbs = nbs + 1;
                } else if ch == '"' {
                    for i32 k = 0; k < nbs * 2 + 1; k++ { str_buf_add_byte(sb, '\\'); }
                    str_buf_add_byte(sb, '"');
                    nbs = 0;
                } else {
                    for i32 k = 0; k < nbs; k++ { str_buf_add_byte(sb, '\\'); }
                    nbs = 0;
                    str_buf_add_byte(sb, ch);
                }
            }
            for i32 k = 0; k < nbs * 2; k++ { str_buf_add_byte(sb, '\\'); }
            str_buf_add_byte(sb, '"');
            return;
        }

        // UTF-8 -> UTF-16 for CreateProcessW, owned. Null on failure.
        u16* _proc_wide(u8* s) {
            i32 n = _proc_mb2wc(_PROC_CP_UTF8, 0, s, -1, null, 0);
            if n <= 0 { return null; }
            u16* w = alloc<u16>(n);
            if _proc_mb2wc(_PROC_CP_UTF8, 0, s, -1, w, n) <= 0 {
                free(cast(void*, w));
                return null;
            }
            return w;
        }

        // argv[0] : Normalize to / for CreateProcess.
        void _proc_win_program(str_buf* sb, str prog) {
            u8* buf = alloc<u8>(cast(i64, prog.len));
            defer free(buf);
            for i32 i = 0; i < prog.len; i++ {
                u8 ch = *(prog.data + i);
                if ch == '/' { ch = '\\'; }
                *(buf + i) = ch;
            }
            _proc_win_quote(sb, str_from(buf, prog.len));
            return;
        }
    }
}

// --- Running ---------------------------------------------------------

ProcResult proc_run(ProcCmd* c) {
    // Unset fields zero: out empty, spawned and timed_out false.
    ProcResult r = { .exit_code = PROC_ERR_SPAWN };

    i32 nargs = proc_nargs(c);
    if nargs <= 0 || c.overflow { return r; }

    bool cap = c.capture;
    str_buf ob;
    if cap { str_buf_init(&ob); }
    noinit u8[_PROC_CHUNK] chunk;
    i64 freq = qpf();
    i64 start = qpc();

    when os(windows) {
        _ProcSecurityAttrs sa = {
            .n_length = cast(u32, sizeof(_ProcSecurityAttrs)),
            .inherit_handle = 1
        };

        i64 hread = 0;
        i64 hwrite = 0;
        if cap {
            if !_proc_create_pipe(&hread, &hwrite, &sa, 0) {
                str_buf_free(&ob);
                return r;
            }
            _proc_set_handle_info(hread, _PROC_HANDLE_FLAG_INHERIT, 0);
        }

        // Both structs start zeroed.
        _ProcStartupInfo si;
        _ProcProcessInfo pi;
        si.cb = cast(u32, sizeof(_ProcStartupInfo));
        si.flags = _PROC_STARTF_USESTDHANDLES;
        si.h_std_input = stdin();
        if cap {
            si.h_std_output = hwrite;
            if !c.split_stderr { si.h_std_error = hwrite; }
            else { si.h_std_error = stderr(); }
        } else {
            // Explicit handles rather than plain inheritance so the
            // child follows the parent's redirection.
            si.h_std_output = stdout();
            si.h_std_error = stderr();
        }

        str_buf cl;
        str_buf_init(&cl);
        for i32 i = 0; i < nargs; i++ {
            if i > 0 { str_buf_add_byte(&cl, ' '); }
            if i == 0 { _proc_win_program(&cl, c.args[0]); }
            else { _proc_win_quote(&cl, c.args[i]); }
        }
        str_buf_add_byte(&cl, '\0');

        // The W command-line buffer must be writable: CreateProcessW
        // is documented to modify it in place.
        u16* wcl = _proc_wide(cl.data);
        str_buf_free(&cl);
        u16* wcwd = null;
        bool cwd_ok = true;
        if c.cwd.len > 0 {
            u8* cwdp = str_to_cstr(c.cwd);
            defer free(cwdp);
            wcwd = _proc_wide(cwdp);
            cwd_ok = wcwd != null;
        }

        // Null application name so the command line drives PATH lookup.
        bool ok = wcl != null && cwd_ok &&
                  _proc_create_process(null, wcl, null, null,
                                       _PROC_INHERIT_HANDLES, 0,
                                       null, wcwd, &si, &pi);
        if wcl != null { free(cast(void*, wcl)); }
        if wcwd != null { free(cast(void*, wcwd)); }
        // The parent's copy of the write end has to go before the read
        // loop, or EOF never arrives.
        if cap { _proc_close_handle(hwrite); }
        if !ok {
            if cap {
                _proc_close_handle(hread);
                str_buf_free(&ob);
            }
            return r;
        }
        r.spawned = true;

        i64 hproc = pi.h_process;
        i64 hthread = pi.h_thread;

        if !cap {
            i32 ms = _PROC_WAIT_INFINITE;
            if c.timeout_ms > 0 { ms = c.timeout_ms; }
            if _proc_wait_single(hproc, ms) == _PROC_WAIT_TIMEOUT {
                _proc_terminate(hproc, _PROC_KILL_EXIT_CODE);
                _proc_wait_single(hproc, _PROC_KILL_GRACE_MS);
                r.timed_out = true;
            }
        } else {
            // Drain while waiting.
            while true {
                i32 avail = 0;
                if _proc_peek_pipe(hread, null, 0, null, &avail, null) && avail > 0 {
                    i32 want = avail;
                    if want > _PROC_CHUNK { want = _PROC_CHUNK; }
                    i32 got = 0;
                    if _proc_read_file(hread, cast(void*, &chunk[0]), want, &got, null) && got > 0 {
                        str_buf_add_bytes(&ob, &chunk[0], got);
                        continue;
                    }
                }
                if _proc_wait_single(hproc, 0) == _PROC_WAIT_OBJECT_0 {
                    // Exited. Take whatever is still in the pipe.
                    i32 left = 0;
                    if _proc_peek_pipe(hread, null, 0, null, &left, null) && left > 0 { continue; }
                    break;
                }
                if c.timeout_ms > 0 {
                    i64 el = (qpc() - start) * 1000 / freq;
                    if el >= cast(i64, c.timeout_ms) {
                        _proc_terminate(hproc, _PROC_KILL_EXIT_CODE);
                        _proc_wait_single(hproc, _PROC_KILL_GRACE_MS);
                        r.timed_out = true;
                        break;
                    }
                }
                thread_sleep(_PROC_TICK_MS);
            }
        }

        i32 code = 0;
        _proc_get_exit_code(hproc, &code);
        _proc_close_handle(hproc);
        _proc_close_handle(hthread);
        if cap { _proc_close_handle(hread); }
        r.exit_code = code;
    }

    when os(linux) || os(macos) {
        // +1 for null terminator
        u8*[PROC_MAX_ARGS + 1] argv;
        for i32 i = 0; i < nargs; i++ { argv[i] = str_to_cstr(c.args[i]); }
        argv[nargs] = null;
        defer { for i32 i = 0; i < nargs; i++ { free(argv[i]); } }

        i32[2] fds = { -1, -1 };
        if cap {
            if _proc_pipe(cast(i32*, &fds[0])) != 0 {
                str_buf_free(&ob);
                return r;
            }
        }

        u8* cwdp = null;
        if c.cwd.len > 0 { cwdp = str_to_cstr(c.cwd); }
        defer free(cwdp);

        i32 pid = _proc_fork();
        if pid == 0 {
            if cap {
                close(cast(i64, fds[0]));
                _proc_dup2(fds[1], _PROC_STDOUT_FD);
                if !c.split_stderr { _proc_dup2(fds[1], _PROC_STDERR_FD); }
                close(cast(i64, fds[1]));
            }
            // A bad cwd is a spawn failure.
            if cwdp != null && _proc_chdir(cwdp) != 0 { exit(_PROC_EXEC_FAILED); }
            _proc_execvp(argv[0], cast(u8**, &argv[0]));
            exit(_PROC_EXEC_FAILED);
        }

        if pid < 0 {
            if cap {
                close(cast(i64, fds[0]));
                close(cast(i64, fds[1]));
                str_buf_free(&ob);
            }
            return r;
        }
        r.spawned = true;
        // parent's write 'end' keeps the pipe from reaching EOF.
        if cap { close(cast(i64, fds[1])); }

        i32 status = 0;
        if !cap && c.timeout_ms <= 0 {
            _proc_waitpid(pid, &status, 0);
        } else {
            // poll, the wait doubles as timeout tick.
            _ProcPollFd pfd = { .fd = fds[0], .events = _PROC_POLLIN };
            while true {
                if cap {
                    pfd.revents = 0;
                    if _proc_poll(cast(void*, &pfd), 1, _PROC_POLL_WAIT_MS) > 0 {
                        i32 got = read(cast(i64, fds[0]), cast(void*, &chunk[0]), _PROC_CHUNK);
                        if got > 0 {
                            str_buf_add_bytes(&ob, &chunk[0], got);
                            continue;
                        }
                    }
                }
                if _proc_waitpid(pid, &status, _PROC_WNOHANG) == pid {
                    if cap {
                        // Anything still buffered outlives the child.
                        while true {
                            i32 g = read(cast(i64, fds[0]), cast(void*, &chunk[0]), _PROC_CHUNK);
                            if g <= 0 { break; }
                            str_buf_add_bytes(&ob, &chunk[0], g);
                        }
                    }
                    break;
                }
                if c.timeout_ms > 0 {
                    i64 el = (qpc() - start) * 1000 / freq;
                    if el >= cast(i64, c.timeout_ms) {
                        _proc_kill(pid, _PROC_SIGKILL);
                        _proc_waitpid(pid, &status, 0);
                        r.timed_out = true;
                        break;
                    }
                }
                if !cap { thread_sleep(_PROC_TICK_MS); }
            }
        }
        if cap { close(cast(i64, fds[0])); }
        // A signal death (crash, kill) reports 128+sig.
        // A crashed child is never proc_ok.
        i32 sig = status & _PROC_STATUS_SIG_MASK;
        if sig != 0 { r.exit_code = 128 + sig; }
        else { r.exit_code = (status >> _PROC_STATUS_SHIFT) & _PROC_STATUS_MASK; }
        // fork() succeeds before the program is known to exist. 
        // if child fails to spawn it returns _PROC_EXEC_FAILED.
        if !r.timed_out && r.exit_code == _PROC_EXEC_FAILED { r.spawned = false; }
    }

    if cap {
        r.out.data = ob.data;
        r.out.len = ob.len;
    }
    if !r.spawned { r.exit_code = PROC_ERR_SPAWN; }
    else if r.timed_out { r.exit_code = PROC_ERR_TIMEOUT; }
    return r;
}

// --- Convenience -----------------------------------------------------

// Run a program with no arguments, output inherited. Returns the exit
// code, or PROC_ERR_SPAWN.
i32 proc_exec(str program) {
    ProcCmd c = { .args = { program } };
    ProcResult r = proc_run(&c);
    return r.exit_code;
}
