// net.mc — basic cross-platform TCP networking.
//
// A thin wrapper over BSD sockets / Winsock for synchronous TCP
// servers and clients. Callers do their own framing on top of
// net_recv / net_send. A separate fd-level non-blocking layer
// (net_nb_socket / net_poll / net_try_* / net_resolve4, below) serves
// readiness-driven runtimes such as event loops.
//
// Platforms: Windows (ws2_32.dll), Linux (raw syscalls, no libc —
// except the non-blocking layer, see below), macOS (libSystem.B.dylib).
//
// Typical server skeleton:
//
//     net_init();
//     Socket srv = net_listen_tcp(8080);
//     while true {
//         Socket c = net_accept(srv);
//         if !c.valid { continue; }
//         u8[1024] buf;
//         i32 n = net_recv(c, &buf[0], 1024);
//         net_send_all(c, response, response_len);
//         net_close(c);
//     }
//     net_close(srv);
//     net_shutdown();

// AF_INET / SOCK_STREAM are fixed by the BSD spec.
const u16 NET_AF_INET = 2;
const i32 NET_SOCK_STREAM = 1;

// SO_REUSEADDR lets the listener re-bind through the kernel's
// TIME_WAIT window after a restart. Constants differ per platform;
// macOS and Winsock share the BSD numbering.
when os(windows) {
    const i32 _NET_SOL_SOCKET = 0xffff;
    const i32 _NET_SO_REUSEADDR = 4;
}
when os(linux) {
    const i32 _NET_SOL_SOCKET = 1;
    const i32 _NET_SO_REUSEADDR = 2;
}
when os(macos) || os(ios) {
    const i32 _NET_SOL_SOCKET = 0xffff;
    const i32 _NET_SO_REUSEADDR = 4;
}

// `struct sockaddr_in` — 16 bytes, identical on every target. Fields
// stay in network byte order; see net_htons.
struct _NetSockAddrIn {
    u16 family;
    u16 port;
    u32 addr;
    u8[8] zero;
}

// `.valid == false` means a syscall failed. `.fd == -1` is the
// no-socket sentinel for both Winsock and POSIX.
struct Socket {
    i64 fd;
    bool valid;
}

// --- Per-platform externs ------------------------------------------

when os(windows) {
    extern "ws2_32.dll" {
        i32 WSAStartup(u16 wVersionRequested, void* lpWSAData);
        i32 WSACleanup();
        i64 socket(i32 af, i32 type, i32 protocol);
        i32 bind(i64 s, void* name, i32 namelen);
        i32 listen(i64 s, i32 backlog);
        i64 accept(i64 s, void* addr, i32* addrlen);
        i32 connect(i64 s, void* name, i32 namelen);
        i32 recv(i64 s, u8* buf, i32 len, i32 flags);
        i32 send(i64 s, u8* buf, i32 len, i32 flags);
        i32 closesocket(i64 s);
        i32 setsockopt(i64 s, i32 level, i32 optname, void* optval, i32 optlen);
        i32 getsockname(i64 s, void* name, i32* namelen);
    }
}

// POSIX fds fit in i32. The public Socket struct widens to i64 so
// the type matches the Windows path; each call casts back at the
// boundary.
// Linux uses libc-free raw-syscall builtins (sys_socket / sys_bind /
// sys_listen / sys_accept / sys_connect / sys_sendto / sys_recvfrom /
// sys_setsockopt / sys_getsockname, emitted by src/linux_stubs*.mc), so
// there is no extern block and no libc.so.6 dependency. send/recv map to
// sendto/recvfrom with a null address. close() is likewise a builtin.

when os(macos) || os(ios) {
    extern "libSystem.B.dylib" {
        i32 socket(i32 domain, i32 type, i32 protocol);
        i32 bind(i32 sockfd, void* addr, i32 addrlen);
        i32 listen(i32 sockfd, i32 backlog);
        i32 accept(i32 sockfd, void* addr, i32* addrlen);
        i32 connect(i32 sockfd, void* addr, i32 addrlen);
        i64 recv(i32 sockfd, u8* buf, i64 len, i32 flags);
        i64 send(i32 sockfd, u8* buf, i64 len, i32 flags);
        i32 setsockopt(i32 sockfd, i32 level, i32 optname, void* optval, i32 optlen);
        i32 getsockname(i32 sockfd, void* addr, i32* addrlen);
    }
}

// --- Helpers --------------------------------------------------------

// Host → network byte order, 16-bit. Just a swap on x86/x64.
u16 net_htons(u16 host) {
    return cast(u16, ((host & 0xFF) << 8) | ((host >> 8) & 0xFF));
}

Socket _net_invalid() {
    Socket s;
    s.fd = -1;
    s.valid = false;
    return s;
}

// --- Public API -----------------------------------------------------

// Initialise the networking subsystem. Call once before any other
// net_* function. WSAStartup on Windows; no-op on POSIX. Returns
// false on failure.
bool net_init() {
    when os(windows) {
        // WSADATA is 408 bytes for Winsock 2.2. We need the side
        // effect, not the contents.
        u8[408] data;
        return WSAStartup(0x0202, &data[0]) == 0;
    } else when os(linux) || os(macos) || os(ios) {
        return true;
    } else {
        // No socket backend here — net.mc is Win32 / POSIX syscalls
        // only. Fail at the entry point rather than hand out handles
        // the rest of the file cannot service.
        return false;
    }
}

// Tear down. Pairs with net_init().
void net_shutdown() {
    when os(windows) {
        WSACleanup();
    }
}

// Bind a TCP socket to `bind_addr`:port and listen. Backlog is 16.
// `bind_addr` must be in network byte order. Returns an invalid
// socket on any failure.
Socket _net_listen_tcp_at(u16 port, u32 bind_addr, bool reuse) {
    Socket result = _net_invalid();
    i64 fd;

    when os(windows) {
        fd = socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd == -1 { return result; }
    }
    when os(linux) {
        i32 fd_i32 = sys_socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd_i32 < 0 { return result; }
        fd = fd_i32;
    }
    when os(macos) || os(ios) {
        i32 fd_i32 = socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd_i32 < 0 { return result; }
        fd = fd_i32;
    }

    // SO_REUSEADDR eases fast restart, but on Windows it also lets a
    // second socket bind a port an active listener already holds — which
    // would defeat a "find a free port" probe. Callers that scan for a
    // free port pass reuse=false so a busy port fails the bind.
    if reuse {
        // opt is declared per-branch: on the kernel (uefi) target all three os()
        // blocks compile out, and a shared declaration would be flagged unused.
        when os(windows) {
            i32 opt = 1;
            setsockopt(fd, _NET_SOL_SOCKET, _NET_SO_REUSEADDR, &opt, 4);
        }
        when os(linux) {
            i32 opt = 1;
            sys_setsockopt(cast(i32, fd), _NET_SOL_SOCKET, _NET_SO_REUSEADDR, &opt, 4);
        }
        when os(macos) || os(ios) {
            i32 opt = 1;
            setsockopt(cast(i32, fd), _NET_SOL_SOCKET, _NET_SO_REUSEADDR, &opt, 4);
        }
    }

    _NetSockAddrIn addr;
    addr.family = NET_AF_INET;
    addr.port = net_htons(port);
    addr.addr = bind_addr;
    for i32 i = 0; i < 8; i++ { addr.zero[i] = 0; }

    when os(windows) {
        if bind(fd, &addr, 16) != 0 { closesocket(fd); return result; }
        if listen(fd, 16) != 0 { closesocket(fd); return result; }
    }
    when os(linux) {
        if sys_bind(cast(i32, fd), &addr, 16) != 0 { close(fd); return result; }
        if sys_listen(cast(i32, fd), 16) != 0 { close(fd); return result; }
    }
    when os(macos) || os(ios) {
        if bind(cast(i32, fd), &addr, 16) != 0 { close(fd); return result; }
        if listen(cast(i32, fd), 16) != 0 { close(fd); return result; }
    }

    result.fd = fd;
    result.valid = true;
    return result;
}

// Listen on 0.0.0.0:port — any interface. macOS shows a firewall
// prompt the first time; use net_listen_tcp_loopback to avoid it.
Socket net_listen_tcp(u16 port) {
    return _net_listen_tcp_at(port, 0, true);   // INADDR_ANY
}

// Listen on 127.0.0.1:port — loopback only, no firewall prompt.
Socket net_listen_tcp_loopback(u16 port) {
    // INADDR_LOOPBACK is 0x7F000001 big-endian, written directly
    // for a little-endian host as 0x0100007F.
    return _net_listen_tcp_at(port, 0x0100007F, true);
}

// Loopback listener without SO_REUSEADDR, so binding a port an active
// listener already holds fails (on every platform). For free-port
// scans — try this in a loop and fall through to the next port.
Socket net_listen_tcp_loopback_excl(u16 port) {
    return _net_listen_tcp_at(port, 0x0100007F, false);
}

// Local port the socket is bound to. Use after listen(s, 0) to
// discover the OS-assigned port. Returns 0 on error.
u16 net_socket_port(Socket s) {
    _NetSockAddrIn addr;
    i32 r;
    when os(windows) {
        i32 len = 16;
        r = getsockname(s.fd, &addr, &len);
    }
    when os(linux) {
        i32 len = 16;
        r = sys_getsockname(cast(i32, s.fd), &addr, &len);
    }
    when os(macos) || os(ios) {
        i32 len = 16;
        r = getsockname(cast(i32, s.fd), &addr, &len);
    }
    if r != 0 { return cast(u16, 0); }
    return net_htons(addr.port);   // swap back to host order
}

// Block until a client connects. The peer address is discarded.
Socket net_accept(Socket server) {
    Socket result = _net_invalid();
    i64 c;

    when os(windows) {
        _NetSockAddrIn client_addr;
        i32 addrlen = 16;
        c = accept(server.fd, &client_addr, &addrlen);
        if c == -1 { return result; }
    }
    when os(linux) {
        _NetSockAddrIn client_addr;
        i32 addrlen = 16;
        i32 c_i32 = sys_accept(cast(i32, server.fd), &client_addr, &addrlen);
        if c_i32 < 0 { return result; }
        c = c_i32;
    }
    when os(macos) || os(ios) {
        _NetSockAddrIn client_addr;
        i32 addrlen = 16;
        i32 c_i32 = accept(cast(i32, server.fd), &client_addr, &addrlen);
        if c_i32 < 0 { return result; }
        c = c_i32;
    }

    result.fd = c;
    result.valid = true;
    return result;
}

// Read up to `len` bytes. Returns the byte count, 0 on clean EOF,
// -1 on error.
i32 net_recv(Socket s, u8* buf, i32 len) {
    when os(windows) {
        return recv(s.fd, buf, len, 0);
    } else when os(linux) {
        return cast(i32, sys_recvfrom(cast(i32, s.fd), buf, len, 0, null, null));
    } else when os(macos) || os(ios) {
        return cast(i32, recv(cast(i32, s.fd), buf, len, 0));
    } else {
        return 0 - 1;   // no socket backend on this target
    }
}

// Send up to `len` bytes. May write fewer — see net_send_all.
// Returns byte count, -1 on error.
i32 net_send(Socket s, u8* buf, i32 len) {
    when os(windows) {
        return send(s.fd, buf, len, 0);
    } else when os(linux) {
        return cast(i32, sys_sendto(cast(i32, s.fd), buf, len, 0, null, 0));
    } else when os(macos) || os(ios) {
        return cast(i32, send(cast(i32, s.fd), buf, len, 0));
    } else {
        return 0 - 1;   // no socket backend on this target
    }
}

// Send all `len` bytes, looping over partial sends.
bool net_send_all(Socket s, u8* buf, i32 len) {
    i32 sent = 0;
    while sent < len {
        i32 n = net_send(s, buf + sent, len - sent);
        if n <= 0 { return false; }
        sent = sent + n;
    }
    return true;
}

void net_close(Socket s) {
    when os(windows) {
        closesocket(s.fd);
    }
    when os(linux) || os(macos) || os(ios) {
        close(s.fd);
    }
}

// Connect to an arbitrary IPv4 host. `ip_be` is the address with its
// bytes in network order packed into a u32 (e.g. 127.0.0.1 -> 0x0100007F,
// 1.1.1.1 -> 0x01010101). Returns an invalid socket on failure.
Socket net_connect(u32 ip_be, u16 port) {
    Socket result = _net_invalid();
    i64 fd;

    when os(windows) {
        fd = socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd == -1 { return result; }
    }
    when os(linux) {
        i32 fd_i32 = sys_socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd_i32 < 0 { return result; }
        fd = fd_i32;
    }
    when os(macos) || os(ios) {
        i32 fd_i32 = socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd_i32 < 0 { return result; }
        fd = fd_i32;
    }

    _NetSockAddrIn addr;
    addr.family = NET_AF_INET;
    addr.port = net_htons(port);
    addr.addr = ip_be;
    for i32 i = 0; i < 8; i++ { addr.zero[i] = 0; }

    when os(windows) {
        if connect(fd, &addr, 16) != 0 { closesocket(fd); return result; }
    }
    when os(linux) {
        if sys_connect(cast(i32, fd), &addr, 16) != 0 { close(fd); return result; }
    }
    when os(macos) || os(ios) {
        if connect(cast(i32, fd), &addr, 16) != 0 { close(fd); return result; }
    }

    result.fd = fd;
    result.valid = true;
    return result;
}

// Connect to 127.0.0.1:port. Returns an invalid socket on failure.
Socket net_connect_loopback(u16 port) {
    // INADDR_LOOPBACK 0x7F000001 in network order -> 0x0100007F.
    return net_connect(0x0100007F, port);
}

// --- Non-blocking layer ---------------------------------------------
//
// fd-level API for readiness-driven runtimes (event loops, reactors):
// non-blocking sockets, WOULDBLOCK-aware I/O, poll, and DNS. The
// blocking API above is unchanged; a blocking Socket interoperates via
// its .fd (make it non-blocking with net_set_nonblocking).
//
// Return conventions:
//   net_try_recv/send: >=0 bytes moved, 0 clean EOF (recv only),
//                      NET_WOULDBLOCK, or NET_ERR.
//   net_try_accept:    >=0 new fd, NET_WOULDBLOCK, or NET_ERR.
// An fd of -1 is the invalid sentinel on every path.
//
// A send to a peer that already closed is an error return, never a
// process signal (SO_NOSIGPIPE on macOS, MSG_NOSIGNAL on Linux).
//
// On Linux this layer, unlike the blocking one, links libc.so.6:
// poll, fcntl and getaddrinfo have no raw-syscall builtins, and name
// resolution needs the libc resolver anyway. Calling into it is what
// adds the dependency — importing net.mc without it stays standalone.
//
// Targets with no socket backend (wasm, uefi) get fail-fast stubs,
// like the blocking API's — net.mc is in the compiler's own closure
// (web_server, shader_watch), so it must compile on every target.

const i32 NET_WOULDBLOCK = -1;
const i32 NET_ERR = -2;

// 127.0.0.1 in network byte order.
const u32 NET_LOOPBACK_BE = 0x0100007F;

// poll event/result bits. These are the native poll(2) values; the
// Windows arm translates to and from WSAPoll's inside net_poll.
const i16 NET_POLLIN  = 0x0001;
const i16 NET_POLLOUT = 0x0004;
const i16 NET_POLLERR = 0x0008;
const i16 NET_POLLHUP = 0x0010;

// The readiness descriptor for net_poll. fd is i64 to match Socket.fd
// and Winsock; the POSIX arms narrow to the native pollfd inside the
// call.
struct NetPollFd {
    i64 fd;
    i16 events;
    i16 revents;
}

// --- per-platform pieces the blocking layer doesn't have -------------

when os(windows) {
    const i32 _NET_FIONBIO = 0x8004667E;
    const i32 _NET_SO_ERROR = 0x1007;
    const i32 _NET_WSAEWOULDBLOCK = 10035;
    // WSAPoll bits
    const i16 _NET_W_POLLRDNORM = 0x0100;
    const i16 _NET_W_POLLWRNORM = 0x0010;
    const i16 _NET_W_POLLERR    = 0x0001;
    const i16 _NET_W_POLLHUP    = 0x0002;
    const i16 _NET_W_POLLNVAL   = 0x0004;

    extern "ws2_32.dll" {
        i32 ioctlsocket(i64 s, i32 cmd, u32* argp);
        i32 getsockopt(i64 s, i32 level, i32 opt, void* val, i32* len);
        i32 WSAPoll(void* fds, u32 nfds, i32 timeout);
        i32 WSAGetLastError();
        i32 getaddrinfo(u8* node, u8* service, void* hints, void** res);
        void freeaddrinfo(void* res);
    }

    // ADDRINFOA, x64 layout: ai_canonname before ai_addr.
    struct _NetAddrInfo {
        i32 ai_flags;
        i32 ai_family;
        i32 ai_socktype;
        i32 ai_protocol;
        u64 ai_addrlen;
        u8* ai_canonname;
        void* ai_addr;
        void* ai_next;
    }

    private i32 _net_last_err() { return WSAGetLastError(); }
}

when os(macos) {
    const i32 _NET_SO_ERROR = 0x1007;
    const i32 _NET_SO_NOSIGPIPE = 0x1022;
    const i32 _NET_O_NONBLOCK = 0x0004;
    const i32 _NET_EWOULDBLOCK = 35;
    const i32 _NET_EINPROGRESS = 36;

    extern "libSystem.B.dylib" {
        i32 fcntl(i32 fd, i32 cmd, ...);
        i32 poll(void* fds, u32 nfds, i32 timeout);
        i32 getsockopt(i32 fd, i32 level, i32 opt, void* val, i32* len);
        i32 getaddrinfo(u8* node, u8* service, void* hints, void** res);
        void freeaddrinfo(void* res);
    }
    private extern "libSystem.B.dylib" i32* _net_errno_loc() from "__error";

    // BSD addrinfo: ai_canonname before ai_addr, 32-bit ai_addrlen.
    struct _NetAddrInfo {
        i32 ai_flags;
        i32 ai_family;
        i32 ai_socktype;
        i32 ai_protocol;
        u32 ai_addrlen;
        u32 _pad;
        u8* ai_canonname;
        void* ai_addr;
        void* ai_next;
    }

    private i32 _net_last_err() { return *(_net_errno_loc()); }
}

when os(linux) {
    const i32 _NET_SO_ERROR = 4;
    const i32 _NET_O_NONBLOCK = 0x0800;
    const i32 _NET_EWOULDBLOCK = 11;
    const i32 _NET_EINPROGRESS = 115;
    const i32 _NET_MSG_NOSIGNAL = 0x4000;

    extern "libc.so.6" {
        i32 fcntl(i32 fd, i32 cmd, ...);
        i32 poll(void* fds, u64 nfds, i32 timeout);
        i32 getsockopt(i32 fd, i32 level, i32 opt, void* val, i32* len);
        i32 getaddrinfo(u8* node, u8* service, void* hints, void** res);
        void freeaddrinfo(void* res);
    }

    // glibc addrinfo: ai_addr before ai_canonname, 32-bit ai_addrlen.
    struct _NetAddrInfo {
        i32 ai_flags;
        i32 ai_family;
        i32 ai_socktype;
        i32 ai_protocol;
        u32 ai_addrlen;
        u32 _pad;
        void* ai_addr;
        u8* ai_canonname;
        void* ai_next;
    }

    // sys_* socket builtins return -errno directly; no accessor needed
    // for them. libc's poll/getsockopt failures are not inspected.
}

when os(linux) || os(macos) {
    const i32 _NET_F_GETFL = 3;
    const i32 _NET_F_SETFL = 4;
    const i32 _NET_EINTR = 4;

    // native struct pollfd — int fd, unlike WSAPOLLFD's i64
    struct _NetPosixPollFd {
        i32 fd;
        i16 events;
        i16 revents;
    }
    const i16 _NET_P_POLLNVAL = 0x0020;
}

// Switch an fd (from this layer or a blocking Socket) to non-blocking
// mode. Returns false on failure.
bool net_set_nonblocking(i64 fd) {
    when os(windows) {
        u32 one = 1;
        return ioctlsocket(fd, _NET_FIONBIO, &one) == 0;
    } else when os(linux) || os(macos) {
        i32 fl = fcntl(cast(i32, fd), _NET_F_GETFL, 0);
        if fl < 0 { return false; }
        return fcntl(cast(i32, fd), _NET_F_SETFL, fl | _NET_O_NONBLOCK) >= 0;
    } else {
        return false;   // no socket backend on this target
    }
}

// Post-creation setup shared by every socket this layer hands out.
private void _net_nb_setup(i64 fd) {
    ignore net_set_nonblocking(fd);
    when os(macos) {
        i32 one = 1;
        ignore setsockopt(cast(i32, fd), _NET_SOL_SOCKET, _NET_SO_NOSIGPIPE, &one, 4);
    }
}

// A fresh non-blocking TCP socket, or -1.
i64 net_nb_socket() {
    i64 fd;
    when os(windows) {
        fd = socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd == -1 { return -1; }
    } else when os(linux) {
        i32 fd_i32 = sys_socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd_i32 < 0 { return -1; }
        fd = fd_i32;
    } else when os(macos) {
        i32 fd_i32 = socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd_i32 < 0 { return -1; }
        fd = fd_i32;
    } else {
        return -1;   // no socket backend on this target
    }
    _net_nb_setup(fd);
    return fd;
}

// Bind + listen on bind_be:port, non-blocking, SO_REUSEADDR, backlog
// 128. bind_be is in network byte order (0 = INADDR_ANY). Returns the
// fd or -1.
i64 net_nb_listen4(u32 bind_be, u16 port) {
    Socket s = _net_listen_tcp_at(port, bind_be, true);
    if !s.valid { return -1; }
    _net_nb_setup(s.fd);
    return s.fd;
}

// Local port an fd is bound to (host order), or 0.
u16 net_fd_port(i64 fd) {
    Socket s;
    s.fd = fd;
    s.valid = true;
    return net_socket_port(s);
}

void net_fd_close(i64 fd) {
    Socket s;
    s.fd = fd;
    s.valid = true;
    net_close(s);
}

// Accept a pending connection off a non-blocking listener: the new
// fd (already non-blocking), NET_WOULDBLOCK, or NET_ERR.
i64 net_try_accept(i64 lfd) {
    when os(windows) || os(linux) || os(macos) {
        _NetSockAddrIn a;
        i32 len = 16;
        i64 c;
        when os(windows) {
            c = accept(lfd, &a, &len);
            if c == -1 {
                if _net_last_err() == _NET_WSAEWOULDBLOCK { return NET_WOULDBLOCK; }
                return NET_ERR;
            }
        }
        when os(linux) {
            i32 r = sys_accept(cast(i32, lfd), &a, &len);
            if r < 0 {
                if r == -_NET_EWOULDBLOCK || r == -_NET_EINTR { return NET_WOULDBLOCK; }
                return NET_ERR;
            }
            c = r;
        }
        when os(macos) {
            i32 r = accept(cast(i32, lfd), &a, &len);
            if r < 0 {
                i32 e = _net_last_err();
                if e == _NET_EWOULDBLOCK || e == _NET_EINTR { return NET_WOULDBLOCK; }
                return NET_ERR;
            }
            c = r;
        }
        _net_nb_setup(c);
        return c;
    } else {
        return NET_ERR;   // no socket backend on this target
    }
}

// Start a non-blocking connect. Returns the fd (connection in progress
// or already complete), or -1 on immediate failure. Poll the fd for
// writable, then confirm with net_connect_result.
i64 net_connect_start(u32 ip_be, u16 port) {
    i64 fd = net_nb_socket();
    if fd == -1 { return -1; }
    _NetSockAddrIn addr;
    addr.family = NET_AF_INET;
    addr.port = net_htons(port);
    addr.addr = ip_be;
    for i32 i = 0; i < 8; i++ { addr.zero[i] = 0; }
    when os(windows) {
        if connect(fd, &addr, 16) == 0 { return fd; }      // rare: instant
        if _net_last_err() == _NET_WSAEWOULDBLOCK { return fd; }
    }
    when os(linux) {
        i32 r = sys_connect(cast(i32, fd), &addr, 16);
        if r == 0 { return fd; }
        if r == -_NET_EINPROGRESS || r == -_NET_EINTR { return fd; }
    }
    when os(macos) {
        if connect(cast(i32, fd), &addr, 16) == 0 { return fd; }
        i32 e = _net_last_err();
        if e == _NET_EINPROGRESS || e == _NET_EINTR { return fd; }
    }
    net_fd_close(fd);
    return -1;
}

// After the fd polls writable: 0 = connected, >0 = the connect errno,
// NET_ERR if the state could not be read (checked via SO_ERROR).
i32 net_connect_result(i64 fd) {
    when os(windows) || os(linux) || os(macos) {
        i32 err = 0;
        i32 len = 4;
        i32 r;
        when os(windows) {
            r = getsockopt(fd, _NET_SOL_SOCKET, _NET_SO_ERROR, &err, &len);
        }
        when os(linux) || os(macos) {
            r = getsockopt(cast(i32, fd), _NET_SOL_SOCKET, _NET_SO_ERROR, &err, &len);
        }
        if r != 0 { return NET_ERR; }
        return err;
    } else {
        return NET_ERR;   // no socket backend on this target
    }
}

// Read up to len bytes off a non-blocking fd: the byte count, 0 on
// clean EOF, NET_WOULDBLOCK, or NET_ERR.
i32 net_try_recv(i64 fd, u8* buf, i32 len) {
    when os(windows) {
        i32 n = recv(fd, buf, len, 0);
        if n >= 0 { return n; }
        if _net_last_err() == _NET_WSAEWOULDBLOCK { return NET_WOULDBLOCK; }
        return NET_ERR;
    } else when os(linux) {
        i64 n = sys_recvfrom(cast(i32, fd), buf, len, 0, null, null);
        if n >= 0 { return cast(i32, n); }
        if n == -_NET_EWOULDBLOCK || n == -_NET_EINTR { return NET_WOULDBLOCK; }
        return NET_ERR;
    } else when os(macos) {
        i64 n = recv(cast(i32, fd), buf, len, 0);
        if n >= 0 { return cast(i32, n); }
        i32 e = _net_last_err();
        if e == _NET_EWOULDBLOCK || e == _NET_EINTR { return NET_WOULDBLOCK; }
        return NET_ERR;
    } else {
        return NET_ERR;   // no socket backend on this target
    }
}

// Write up to len bytes to a non-blocking fd: the byte count,
// NET_WOULDBLOCK, or NET_ERR.
i32 net_try_send(i64 fd, u8* buf, i32 len) {
    when os(windows) {
        i32 n = send(fd, buf, len, 0);
        if n >= 0 { return n; }
        if _net_last_err() == _NET_WSAEWOULDBLOCK { return NET_WOULDBLOCK; }
        return NET_ERR;
    } else when os(linux) {
        i64 n = sys_sendto(cast(i32, fd), buf, len, _NET_MSG_NOSIGNAL, null, 0);
        if n >= 0 { return cast(i32, n); }
        if n == -_NET_EWOULDBLOCK || n == -_NET_EINTR { return NET_WOULDBLOCK; }
        return NET_ERR;
    } else when os(macos) {
        i64 n = send(cast(i32, fd), buf, len, 0);
        if n >= 0 { return cast(i32, n); }
        i32 e = _net_last_err();
        if e == _NET_EWOULDBLOCK || e == _NET_EINTR { return NET_WOULDBLOCK; }
        return NET_ERR;
    } else {
        return NET_ERR;   // no socket backend on this target
    }
}

// Wait up to timeout_ms (-1 = indefinitely) for readiness on n
// descriptors. Returns the number of ready descriptors, 0 on timeout,
// -1 on error; revents is filled with NET_POLL* bits.
i32 net_poll(NetPollFd* fds, i32 n, i32 timeout_ms) {
    if n <= 0 { return 0; }
    when os(windows) {
        // translate the portable bits to WSAPoll's and back; the
        // NetPollFd layout already matches WSAPOLLFD
        for i32 i = 0; i < n; i++ {
            i16 ev = 0;
            if ((fds + i).events & NET_POLLIN) != 0 { ev = cast(i16, ev | _NET_W_POLLRDNORM); }
            if ((fds + i).events & NET_POLLOUT) != 0 { ev = cast(i16, ev | _NET_W_POLLWRNORM); }
            (fds + i).events = ev;
            (fds + i).revents = 0;
        }
        i32 r = WSAPoll(cast(void*, fds), cast(u32, n), timeout_ms);
        for i32 i = 0; i < n; i++ {
            i16 re = (fds + i).revents;
            i16 out = 0;
            if (re & _NET_W_POLLRDNORM) != 0 { out = cast(i16, out | NET_POLLIN); }
            if (re & _NET_W_POLLWRNORM) != 0 { out = cast(i16, out | NET_POLLOUT); }
            if (re & (_NET_W_POLLERR | _NET_W_POLLNVAL)) != 0 { out = cast(i16, out | NET_POLLERR); }
            if (re & _NET_W_POLLHUP) != 0 { out = cast(i16, out | NET_POLLHUP); }
            (fds + i).revents = out;
        }
        return r;
    } else when os(linux) || os(macos) {
        // same bit values natively; only the fd width differs
        _NetPosixPollFd* pp = alloc<_NetPosixPollFd>(n);
        defer free(pp);
        for i32 i = 0; i < n; i++ {
            (pp + i).fd = cast(i32, (fds + i).fd);
            (pp + i).events = (fds + i).events;
            (pp + i).revents = 0;
        }
        i32 r;
        when os(linux) {
            r = poll(pp, cast(u64, n), timeout_ms);
        }
        when os(macos) {
            r = poll(pp, cast(u32, n), timeout_ms);
        }
        for i32 i = 0; i < n; i++ {
            i16 re = (pp + i).revents;
            // a bad descriptor reads as an error condition
            if (re & _NET_P_POLLNVAL) != 0 { re = cast(i16, re | NET_POLLERR); }
            (fds + i).revents = re;
        }
        return r < 0 ? -1 : r;
    } else {
        return -1;   // no socket backend on this target
    }
}

// Resolve a hostname to its first IPv4 address (network-order u32),
// or 0 on failure. A dotted-quad string resolves without a lookup.
u32 net_resolve4(u8* host) {
    when os(windows) || os(linux) || os(macos) {
        void* res = null;
        if getaddrinfo(host, null, null, &res) != 0 { return 0; }
        u32 out = 0;
        void* cur = res;
        while cur != null {
            _NetAddrInfo* ai = cast(_NetAddrInfo*, cur);
            if ai.ai_family == NET_AF_INET && ai.ai_addr != null {
                _NetSockAddrIn* sa = cast(_NetSockAddrIn*, ai.ai_addr);
                out = sa.addr;
                break;
            }
            cur = ai.ai_next;
        }
        freeaddrinfo(res);
        return out;
    } else {
        return 0;   // no resolver on this target
    }
}
