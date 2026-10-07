// net.mc — basic cross-platform TCP networking.
//
// TCP servers and clients over BSD sockets and Winsock. The blocking
// API reads and writes whole Socket values. Callers frame their own
// messages on top of net_recv and net_send.
//
// The non-blocking API (net_nb_socket, net_poll, net_try_*,
// net_resolve4) is for event loops. The pollers (net_poller_*, at the
// end) report only the sockets that are ready.
//
// Windows uses ws2_32.dll and macOS libSystem. Linux uses system calls
// directly, except in the non-blocking API.
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

private const u16 NET_AF_INET = 2;
private const i32 NET_SOCK_STREAM = 1;

// SO_REUSEADDR lets a restarted server bind its port again at once.
when os(windows) {
    private const i32 _NET_SOL_SOCKET = 0xffff;
    private const i32 _NET_SO_REUSEADDR = 4;
}
when os(linux) {
    private const i32 _NET_SOL_SOCKET = 1;
    private const i32 _NET_SO_REUSEADDR = 2;
}
when os(macos) || os(ios) {
    private const i32 _NET_SOL_SOCKET = 0xffff;
    private const i32 _NET_SO_REUSEADDR = 4;
}
when os(uefi) {
    private const i32 _NET_SOL_SOCKET = 1;
    private const i32 _NET_SO_REUSEADDR = 2;
}

// `struct sockaddr_in`, the same 16 bytes on every target. Port and
// address are in network byte order.
private struct _NetSockAddrIn {
    u16 family;
    u16 port;
    u32 addr;
    u8[8] zero;
}

// `valid` is false when a call failed. `fd` is -1 when there is no
// socket.
struct Socket {
    i64 fd;
    bool valid;
}

// --- Per-platform externs ------------------------------------------

when os(windows) {
    private extern "ws2_32.dll" {
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

// Socket.fd is i64 to hold a Windows handle. The POSIX calls take an
// i32 and cast at each call.
// The blocking API on Linux calls the sys_* builtins, which make the
// system calls without libc.

when os(macos) || os(ios) {
    private const i32 _NET_SO_NOSIGPIPE = 0x1022;

    private extern "libSystem.B.dylib" {
        i32 socket(i32 domain, i32 type, i32 protocol);
        i32 bind(i32 sockfd, void* addr, i32 addrlen);
        i32 shutdown(i32 s, i32 how);
        i32 listen(i32 sockfd, i32 backlog);
        i32 accept(i32 sockfd, void* addr, i32* addrlen);
        i32 connect(i32 sockfd, void* addr, i32 addrlen);
        i64 recv(i32 sockfd, u8* buf, i64 len, i32 flags);
        i64 send(i32 sockfd, u8* buf, i64 len, i32 flags);
        i32 setsockopt(i32 sockfd, i32 level, i32 optname, void* optval, i32 optlen);
        i32 getsockname(i32 sockfd, void* addr, i32* addrlen);
    }
}

// uefi has no sockets of its own. A program installs a NetBackend with
// the calls the other targets get from the system. The code below then
// reads the same on every target. Errors are -1, with the code from
// last_err.

when os(uefi) {
    private const i32 _NET_EINTR = 4;
    private const i32 _NET_EWOULDBLOCK = 11;
    private const i32 _NET_EINPROGRESS = 115;
    private const i32 _NET_SO_ERROR = 4;

    // The error codes a backend returns from last_err. Any other code
    // counts as a failure.
    const i32 NET_BE_EINTR = _NET_EINTR;
    const i32 NET_BE_EWOULDBLOCK = _NET_EWOULDBLOCK;
    const i32 NET_BE_EINPROGRESS = _NET_EINPROGRESS;
    const i32 NET_BE_SO_ERROR = _NET_SO_ERROR;

    struct NetBackend {
        fn(i32, i32, i32): i64 socket;
        fn(i64, void*, i32): i32 bind;
        fn(i64, i32): i32 listen;
        fn(i64, void*, i32*): i64 accept;
        fn(i64, void*, i32): i32 connect;
        fn(i64, u8*, i32, i32): i32 recv;
        fn(i64, u8*, i32, i32): i32 send;
        fn(i64, i32): i32 shutdown;
        fn(i64): i32 closesocket;
        fn(i64, void*, i32*): i32 getsockname;
        fn(i64, i32, i32, void*, i32*): i32 getsockopt;
        fn(i64, bool): i32 ioctl_nonblock;
        fn(NetPollFd*, i32, i32): i32 poll;
        // IPv4 only. Returns the address, or 0.
        fn(u8*): u32 resolve4;
        fn(): i32 last_err;
        // The pollers. A backend may leave these null. The poller
        // calls then fail.
        fn(): i64 poller_new;
        fn(i64): i32 poller_close;
        fn(i64, i64, i16, i64): i32 poller_set;
        fn(i64, NetPollEvent*, i32, i32): i32 poller_wait;
    }

    private NetBackend* _net_be = null;

    void net_backend_install(NetBackend* b) { _net_be = b; }

    // Without a backend each call fails as it would on a bad socket.
    private bool _net_be_up() { return _net_be != null; }

    private i64 socket(i32 af, i32 type, i32 proto) {
        if !_net_be_up() { return -1; }
        return _net_be.socket(af, type, proto);
    }
    private i32 bind(i64 s, void* addr, i32 len) {
        if !_net_be_up() { return -1; }
        return _net_be.bind(s, addr, len);
    }
    private i32 listen(i64 s, i32 backlog) {
        if !_net_be_up() { return -1; }
        return _net_be.listen(s, backlog);
    }
    private i64 accept(i64 s, void* addr, i32* len) {
        if !_net_be_up() { return -1; }
        return _net_be.accept(s, addr, len);
    }
    private i32 connect(i64 s, void* addr, i32 len) {
        if !_net_be_up() { return -1; }
        return _net_be.connect(s, addr, len);
    }
    private i32 recv(i64 s, u8* buf, i32 len, i32 flags) {
        if !_net_be_up() { return -1; }
        return _net_be.recv(s, buf, len, flags);
    }
    private i32 send(i64 s, u8* buf, i32 len, i32 flags) {
        if !_net_be_up() { return -1; }
        return _net_be.send(s, buf, len, flags);
    }
    private i32 shutdown(i64 s, i32 how) {
        if !_net_be_up() { return -1; }
        return _net_be.shutdown(s, how);
    }
    private i32 closesocket(i64 s) {
        if !_net_be_up() { return -1; }
        return _net_be.closesocket(s);
    }
    private i32 getsockname(i64 s, void* addr, i32* len) {
        if !_net_be_up() { return -1; }
        return _net_be.getsockname(s, addr, len);
    }
    private i32 getsockopt(i64 s, i32 lvl, i32 opt, void* val, i32* len) {
        if !_net_be_up() { return -1; }
        return _net_be.getsockopt(s, lvl, opt, val, len);
    }
    private i32 poll(NetPollFd* fds, i32 n, i32 timeout_ms) {
        if !_net_be_up() { return -1; }
        return _net_be.poll(fds, n, timeout_ms);
    }
    private i32 _net_last_err() {
        if !_net_be_up() { return 0; }
        return _net_be.last_err();
    }
}

// --- Helpers --------------------------------------------------------

// Swaps the two bytes of a port between host and network order.
u16 net_htons(u16 host) {
    return cast(u16, ((host & 0xFF) << 8) | ((host >> 8) & 0xFF));
}

private Socket _net_invalid() {
    Socket s;
    s.fd = -1;
    s.valid = false;
    return s;
}

// --- Public API -----------------------------------------------------

// Starts networking. Call it once before any other net_* function.
// Returns false on failure.
bool net_init() {
    when os(windows) {
        // WSADATA is 408 bytes for Winsock 2.2. Its contents are unused.
        u8[408] data;
        return WSAStartup(0x0202, &data[0]) == 0;
    } else when os(linux) || os(macos) || os(ios) {
        return true;
    } else when os(uefi) {
        return _net_be != null;
    } else {
        // This target has no sockets.
        return false;
    }
}

// Stops networking. Pairs with net_init.
void net_shutdown() {
    when os(windows) {
        WSACleanup();
    }
}

// A send to a peer that has closed returns an error. Without this,
// macOS and iOS stop the process with SIGPIPE. Linux asks for the same
// on each send.
private void _net_no_sigpipe(i64 fd) {
    when os(macos) || os(ios) {
        i32 one = 1;
        ignore setsockopt(cast(i32, fd), _NET_SOL_SOCKET, _NET_SO_NOSIGPIPE, &one, 4);
    }
    return;
}

// Binds a TCP socket to `bind_addr`:port and listens, with a backlog
// of 16. `bind_addr` is in network byte order. Returns an invalid
// socket on failure.
private Socket _net_listen_tcp_at(u16 port, u32 bind_addr, bool reuse) {
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
    when os(uefi) {
        fd = socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd == -1 { return result; }
    }

    // On Windows SO_REUSEADDR also lets a second socket bind a port that
    // a listener holds. A search for a free port passes reuse=false.
    // Then a busy port fails the bind.
    if reuse {
        // Each branch declares its own opt. On uefi no branch remains,
        // and a shared opt would be an unused variable.
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
    when os(uefi) {
        if bind(fd, &addr, 16) != 0 { ignore closesocket(fd); return result; }
        if listen(fd, 16) != 0 { ignore closesocket(fd); return result; }
    }

    result.fd = fd;
    result.valid = true;
    return result;
}

// Listens on port on every interface. macOS asks the user about its
// firewall the first time. net_listen_tcp_loopback avoids the prompt.
Socket net_listen_tcp(u16 port) {
    return _net_listen_tcp_at(port, 0, true);
}

// Listens on 127.0.0.1:port. Only this machine can connect.
Socket net_listen_tcp_loopback(u16 port) {
    // 127.0.0.1 in network byte order.
    return _net_listen_tcp_at(port, 0x0100007F, true);
}

// Listens on 127.0.0.1:port without SO_REUSEADDR. It fails when another
// listener holds the port. Call it on port after port to find a free
// one.
Socket net_listen_tcp_loopback_excl(u16 port) {
    return _net_listen_tcp_at(port, 0x0100007F, false);
}

// The local port of the socket. After a listen on port 0 it returns
// the port the system chose. Returns 0 on error.
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
    when os(uefi) {
        i32 len = 16;
        r = getsockname(s.fd, &addr, &len);
    }
    if r != 0 { return cast(u16, 0); }
    return net_htons(addr.port);
}

// Waits until a client connects. The peer address is discarded.
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
    when os(uefi) {
        _NetSockAddrIn client_addr;
        i32 addrlen = 16;
        c = accept(server.fd, &client_addr, &addrlen);
        if c == -1 { return result; }
    }

    _net_no_sigpipe(c);
    result.fd = c;
    result.valid = true;
    return result;
}

// Reads up to `len` bytes. Returns the count, 0 when the peer has
// closed, or -1 on error.
i32 net_recv(Socket s, u8* buf, i32 len) {
    when os(windows) {
        return recv(s.fd, buf, len, 0);
    } else when os(linux) {
        return cast(i32, sys_recvfrom(cast(i32, s.fd), buf, len, 0, null, null));
    } else when os(macos) || os(ios) {
        return cast(i32, recv(cast(i32, s.fd), buf, len, 0));
    } else when os(uefi) {
        return recv(s.fd, buf, len, 0);
    } else {
        return 0 - 1;   // this target has no sockets
    }
}

// Sends up to `len` bytes and may send fewer. Returns the count, or -1
// on error. net_send_all sends everything.
i32 net_send(Socket s, u8* buf, i32 len) {
    when os(windows) {
        return send(s.fd, buf, len, 0);
    } else when os(linux) {
        return cast(i32, sys_sendto(cast(i32, s.fd), buf, len, _NET_MSG_NOSIGNAL, null, 0));
    } else when os(macos) || os(ios) {
        return cast(i32, send(cast(i32, s.fd), buf, len, 0));
    } else when os(uefi) {
        return send(s.fd, buf, len, 0);
    } else {
        return 0 - 1;   // this target has no sockets
    }
}

// Sends all `len` bytes. Returns false on error.
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
    when os(uefi) {
        ignore closesocket(s.fd);
    }
}

// Connects to an IPv4 host. `ip_be` holds the address bytes in network
// order: 127.0.0.1 is 0x0100007F. Returns an invalid socket on failure.
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
    when os(uefi) {
        fd = socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd == -1 { return result; }
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
    when os(uefi) {
        if connect(fd, &addr, 16) != 0 { ignore closesocket(fd); return result; }
    }

    _net_no_sigpipe(fd);
    result.fd = fd;
    result.valid = true;
    return result;
}

// Connects to 127.0.0.1:port. Returns an invalid socket on failure.
Socket net_connect_loopback(u16 port) {
    return net_connect(0x0100007F, port);
}

// --- Non-blocking layer ---------------------------------------------
//
// Calls on plain descriptors for event loops. A call that would wait
// returns NET_WOULDBLOCK instead. A blocking Socket works here through
// its fd, after net_set_nonblocking.
//
// net_try_recv and net_try_send return the bytes moved, NET_WOULDBLOCK
// or NET_ERR. net_try_recv returns 0 when the peer has closed.
// net_try_accept returns the new descriptor, NET_WOULDBLOCK or NET_ERR.
// A descriptor of -1 means none.
//
// A send to a peer that has closed returns an error.
//
// On Linux these calls use libc.so.6 for poll, fcntl and name lookup.
// A program that calls none of them does not link libc.
//
// On wasm every call fails.

const i32 NET_WOULDBLOCK = -1;
const i32 NET_ERR = -2;

// 127.0.0.1 in network byte order.
const u32 NET_LOOPBACK_BE = 0x0100007F;

// The readiness bits of net_poll and the pollers.
const i16 NET_POLLIN  = 0x0001;
const i16 NET_POLLOUT = 0x0004;
const i16 NET_POLLERR = 0x0008;
const i16 NET_POLLHUP = 0x0010;

// One descriptor for net_poll: the readiness asked for in `events`,
// the readiness found in `revents`.
struct NetPollFd {
    i64 fd;
    i16 events;
    i16 revents;
}

// --- Per-platform pieces of the non-blocking API ---------------------

when os(windows) {
    private const i32 _NET_FIONBIO = 0x8004667E;
    private const i32 _NET_SO_ERROR = 0x1007;
    private const i32 _NET_WSAEWOULDBLOCK = 10035;
    // WSAPoll bits
    private const i16 _NET_W_POLLRDNORM = 0x0100;
    private const i16 _NET_W_POLLWRNORM = 0x0010;
    private const i16 _NET_W_POLLERR    = 0x0001;
    private const i16 _NET_W_POLLHUP    = 0x0002;
    private const i16 _NET_W_POLLNVAL   = 0x0004;

    private extern "kernel32.dll" {
        void Sleep(u32 ms);
    }
    private extern "ws2_32.dll" {
        i32 ioctlsocket(i64 s, i32 cmd, u32* argp);
        i32 getsockopt(i64 s, i32 level, i32 opt, void* val, i32* len);
        i32 WSAPoll(void* fds, u32 nfds, i32 timeout);
        i32 shutdown(i64 s, i32 how);
        i32 WSAGetLastError();
        i32 getaddrinfo(u8* node, u8* service, void* hints, void** res);
        void freeaddrinfo(void* res);
    }

    // ADDRINFOA, x64 layout: ai_canonname before ai_addr.
    private struct _NetAddrInfo {
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
    private const i32 _NET_SO_ERROR = 0x1007;
    private const i32 _NET_O_NONBLOCK = 0x0004;
    private const i32 _NET_EWOULDBLOCK = 35;
    private const i32 _NET_EINPROGRESS = 36;

    private extern "libSystem.B.dylib" {
        i32 fcntl(i32 fd, i32 cmd, ...);
        i32 poll(void* fds, u32 nfds, i32 timeout);
        i32 kqueue();
        i32 kevent(i32 kq, void* changelist, i32 nchanges, void* eventlist, i32 nevents, void* timeout);
        i32 getsockopt(i32 fd, i32 level, i32 opt, void* val, i32* len);
        i32 getaddrinfo(u8* node, u8* service, void* hints, void** res);
        void freeaddrinfo(void* res);
    }
    private extern "libSystem.B.dylib" i32* _net_errno_loc() from "__error";

    // BSD addrinfo: ai_canonname before ai_addr, 32-bit ai_addrlen.
    private struct _NetAddrInfo {
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
    private const i32 _NET_SO_ERROR = 4;
    private const i32 _NET_O_NONBLOCK = 0x0800;
    private const i32 _NET_EWOULDBLOCK = 11;
    private const i32 _NET_EINPROGRESS = 115;
    private const i32 _NET_MSG_NOSIGNAL = 0x4000;

    private extern "libc.so.6" {
        i32 fcntl(i32 fd, i32 cmd, ...);
        i32 poll(void* fds, u64 nfds, i32 timeout);
        i32 epoll_create1(i32 flags);
        i32 epoll_ctl(i32 epfd, i32 op, i32 fd, void* event);
        i32 epoll_wait(i32 epfd, void* events, i32 maxevents, i32 timeout);
        i32 shutdown(i32 s, i32 how);
        i32 getsockopt(i32 fd, i32 level, i32 opt, void* val, i32* len);
        i32 getaddrinfo(u8* node, u8* service, void* hints, void** res);
        void freeaddrinfo(void* res);
    }

    // glibc addrinfo: ai_addr before ai_canonname, 32-bit ai_addrlen.
    private struct _NetAddrInfo {
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

    // The sys_* builtins return the error code negated.
}

when os(linux) || os(macos) {
    private const i32 _NET_F_GETFL = 3;
    private const i32 _NET_F_SETFL = 4;
    private const i32 _NET_EINTR = 4;

    // struct pollfd, with an i32 descriptor.
    private struct _NetPosixPollFd {
        i32 fd;
        i16 events;
        i16 revents;
    }
    private const i16 _NET_P_POLLNVAL = 0x0020;
}

// Makes a descriptor non-blocking. Returns false on failure.
bool net_set_nonblocking(i64 fd) {
    when os(windows) {
        u32 one = 1;
        return ioctlsocket(fd, _NET_FIONBIO, &one) == 0;
    } else when os(linux) || os(macos) {
        i32 fl = fcntl(cast(i32, fd), _NET_F_GETFL, 0);
        if fl < 0 { return false; }
        return fcntl(cast(i32, fd), _NET_F_SETFL, fl | _NET_O_NONBLOCK) >= 0;
    } else when os(uefi) {
        if _net_be == null { return false; }
        return _net_be.ioctl_nonblock(fd, true) == 0;
    } else {
        return false;   // this target has no sockets
    }
}

// Setup for every socket the non-blocking API creates.
private void _net_nb_setup(i64 fd) {
    ignore net_set_nonblocking(fd);
    when os(macos) {
        i32 one = 1;
        ignore setsockopt(cast(i32, fd), _NET_SOL_SOCKET, _NET_SO_NOSIGPIPE, &one, 4);
    }
}

// A new non-blocking TCP socket, or -1.
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
    } else when os(uefi) {
        fd = socket(NET_AF_INET, NET_SOCK_STREAM, 0);
        if fd == -1 { return -1; }
    } else {
        return -1;   // this target has no sockets
    }
    _net_nb_setup(fd);
    return fd;
}

// A non-blocking listener on bind_be:port with SO_REUSEADDR.
// `bind_be` is in network byte order, and 0 means every interface.
// Returns the descriptor, or -1.
i64 net_nb_listen4(u32 bind_be, u16 port) {
    Socket s = _net_listen_tcp_at(port, bind_be, true);
    if !s.valid { return -1; }
    _net_nb_setup(s.fd);
    return s.fd;
}

// The local port of a descriptor, or 0.
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

// Accepts a waiting connection on a non-blocking listener. Returns the
// new non-blocking descriptor, NET_WOULDBLOCK or NET_ERR.
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
    } else when os(uefi) {
        _NetSockAddrIn a;
        i32 len = 16;
        i64 c = accept(lfd, &a, &len);
        if c == -1 {
            i32 e = _net_last_err();
            if e == _NET_EWOULDBLOCK || e == _NET_EINTR { return NET_WOULDBLOCK; }
            return NET_ERR;
        }
        _net_nb_setup(c);
        return c;
    } else {
        return NET_ERR;   // this target has no sockets
    }
}

// Starts a connect without waiting. Returns the descriptor, or -1. Wait
// for NET_POLLOUT on it, then read the outcome with net_connect_result.
i64 net_connect_start(u32 ip_be, u16 port) {
    i64 fd = net_nb_socket();
    if fd == -1 { return -1; }
    _NetSockAddrIn addr;
    addr.family = NET_AF_INET;
    addr.port = net_htons(port);
    addr.addr = ip_be;
    for i32 i = 0; i < 8; i++ { addr.zero[i] = 0; }
    when os(windows) {
        if connect(fd, &addr, 16) == 0 { return fd; }
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
    when os(uefi) {
        if connect(fd, &addr, 16) == 0 { return fd; }
        i32 e = _net_last_err();
        if e == _NET_EINPROGRESS || e == _NET_EINTR { return fd; }
    }
    net_fd_close(fd);
    return -1;
}

// The outcome of a connect, once the descriptor reports NET_POLLOUT.
// 0 when connected, the system's error code when not, or NET_ERR.
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
    } else when os(uefi) {
        i32 err = 0;
        i32 len = 4;
        if getsockopt(fd, _NET_SOL_SOCKET, _NET_SO_ERROR, &err, &len) != 0 { return NET_ERR; }
        return err;
    } else {
        return NET_ERR;   // this target has no sockets
    }
}

// Reads up to `len` bytes. Returns the count, 0 when the peer has
// closed, NET_WOULDBLOCK or NET_ERR.
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
    } else when os(uefi) {
        i32 n = recv(fd, buf, len, 0);
        if n >= 0 { return n; }
        i32 e = _net_last_err();
        if e == _NET_EWOULDBLOCK || e == _NET_EINTR { return NET_WOULDBLOCK; }
        return NET_ERR;
    } else {
        return NET_ERR;   // this target has no sockets
    }
}

// Sends up to `len` bytes. Returns the count, NET_WOULDBLOCK or
// NET_ERR.
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
    } else when os(uefi) {
        i32 n = send(fd, buf, len, 0);
        if n >= 0 { return n; }
        i32 e = _net_last_err();
        if e == _NET_EWOULDBLOCK || e == _NET_EINTR { return NET_WOULDBLOCK; }
        return NET_ERR;
    } else {
        return NET_ERR;   // this target has no sockets
    }
}

// Waits up to `timeout_ms` for any of `n` descriptors to be ready. -1
// waits without a limit. Sets each `revents`. Returns the number ready,
// 0 on timeout, or -1 on error.
i32 net_poll(NetPollFd* fds, i32 n, i32 timeout_ms) {
    if n <= 0 { return 0; }
    when os(windows) {
        // NetPollFd has the layout of WSAPOLLFD. Only the bits differ.
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
        // The bits are the same. Only the descriptor width differs.
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
            // A bad descriptor reports as an error.
            if (re & _NET_P_POLLNVAL) != 0 { re = cast(i16, re | NET_POLLERR); }
            (fds + i).revents = re;
        }
        return r < 0 ? -1 : r;
    } else when os(uefi) {
        return poll(fds, n, timeout_ms);
    } else {
        return -1;   // this target has no sockets
    }
}

// Closes the sending side and keeps the receiving side open. The peer
// sees the end of the stream and can still answer. Returns 0, or -1.
i32 net_shutdown_write(i64 fd) {
    when os(windows) || os(uefi) {
        return shutdown(fd, 1);                    // SD_SEND
    } else when os(linux) || os(macos) || os(ios) {
        return shutdown(cast(i32, fd), 1);         // SHUT_WR
    } else {
        return -1;   // this target has no sockets
    }
}

// The first IPv4 address of a host name, in network byte order, or 0.
// An address such as "10.0.0.1" converts without a lookup.
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
    } else when os(uefi) {
        if _net_be == null { return 0; }
        return _net_be.resolve4(host);
    } else {
        return 0;   // this target has no sockets
    }
}

// --- Pollers ---------------------------------------------------------
//
// A poller holds descriptors a program adds once. Each has the
// readiness it wants and a token of the program's choice. A wait
// returns only the ready entries. net_poll, by contrast, checks the
// whole list on every call.
//
// An entry stays ready until the program reads or writes what made it
// ready, as in net_poll. A poller belongs to the thread that waits on
// it. A program with a loop per core makes one per loop.
//
// Linux uses epoll and macOS kqueue. On Windows a poller is a list that
// each wait passes to net_poll. A wait there costs as much as net_poll.
// When more entries are ready than a wait can return, the earliest in
// the list come first.

// A ready entry: its token and its readiness bits.
struct NetPollEvent {
    i64 token;
    i16 revents;
}

when os(linux) {
    private const i32 _NET_EPOLL_CTL_ADD = 1;
    private const i32 _NET_EPOLL_CTL_DEL = 2;
    private const i32 _NET_EPOLL_CTL_MOD = 3;
    // struct epoll_event, a u32 then a u64. It is packed to 12 bytes on
    // x64 and padded to 16 on arm64.
    when arch(x64) {
        private const i32 _NET_EPEV_SIZE = 12;
        private const i32 _NET_EPEV_DATA = 4;
    }
    when !arch(x64) {
        private const i32 _NET_EPEV_SIZE = 16;
        private const i32 _NET_EPEV_DATA = 8;
    }
}

when os(macos) {
    private const i16 _NET_EVFILT_READ = -1;
    private const i16 _NET_EVFILT_WRITE = -2;
    private const u16 _NET_EV_ADD = 0x0001;
    private const u16 _NET_EV_DELETE = 0x0002;
    private const u16 _NET_EV_ENABLE = 0x0004;
    private const u16 _NET_EV_RECEIPT = 0x0040;
    private const u16 _NET_EV_ERROR = 0x4000;
    private const u16 _NET_EV_EOF = 0x8000;
    private const i64 _NET_ENOENT = 2;

    // struct kevent on 64-bit Darwin.
    private struct _NetKEvent {
        u64 ident;
        i16 filter;
        u16 flags;
        u32 fflags;
        i64 data;
        u64 udata;
    }
    private struct _NetTimespec {
        i64 sec;
        i64 nsec;
    }

    // Applies one change. Returns 0, the error code, or -1.
    private i64 _net_kq_change(i32 kq, i64 fd, i16 filter, u16 flags, i64 token) {
        _NetKEvent ch;
        ch.ident = cast(u64, fd);
        ch.filter = filter;
        ch.flags = cast(u16, flags | _NET_EV_RECEIPT);
        ch.fflags = 0;
        ch.data = 0;
        ch.udata = cast(u64, token);
        _NetKEvent out;
        if kevent(kq, &ch, 1, &out, 1, null) < 1 { return -1; }
        return out.data;
    }
}

when os(windows) {
    // Threads may create pollers at the same time. Each claims a slot
    // with atomic_cas.
    private struct _NetWinPoller {
        i32 used;
        i64* fds;
        i16* events;
        i64* tokens;
        i32 n;
        i32 cap;
    }
    private const i32 _NET_WIN_POLLERS = 64;
    private _NetWinPoller[64] _net_win_pollers;

    private _NetWinPoller* _net_win_poller(i64 p) {
        if p < 0 || p >= cast(i64, _NET_WIN_POLLERS) { return null; }
        _NetWinPoller* w = &_net_win_pollers[cast(i32, p)];
        return w.used != 0 ? w : null;
    }
}

// A new poller, or -1.
i64 net_poller_new() {
    when os(linux) {
        i32 fd = epoll_create1(0);
        return fd < 0 ? -1 : cast(i64, fd);
    } else when os(macos) {
        i32 fd = kqueue();
        return fd < 0 ? -1 : cast(i64, fd);
    } else when os(windows) {
        for i32 i = 0; i < _NET_WIN_POLLERS; i++ {
            _NetWinPoller* w = &_net_win_pollers[i];
            if !atomic_cas(&w.used, 0, 1) { continue; }
            w.fds = null;
            w.events = null;
            w.tokens = null;
            w.n = 0;
            w.cap = 0;
            return cast(i64, i);
        }
        return -1;
    } else when os(uefi) {
        if !_net_be_up() || _net_be.poller_new == null { return -1; }
        return _net_be.poller_new();
    } else {
        return -1;   // this target has no sockets
    }
}

// Closes a poller. The descriptors in it stay open.
i32 net_poller_close(i64 p) {
    when os(linux) || os(macos) {
        close(p);
        return 0;
    } else when os(windows) {
        _NetWinPoller* w = _net_win_poller(p);
        if w == null { return -1; }
        if w.fds != null { free(w.fds); }
        if w.events != null { free(w.events); }
        if w.tokens != null { free(w.tokens); }
        w.used = 0;
        return 0;
    } else when os(uefi) {
        if !_net_be_up() || _net_be.poller_close == null { return -1; }
        return _net_be.poller_close(p);
    } else {
        return -1;
    }
}

// Adds `fd` to the poller, or changes its entry. `events` takes
// NET_POLLIN and NET_POLLOUT. A wait reports the entry by `token`.
// `events` of 0 removes the entry, and fails when there is none.
// Returns 0, or -1.
//
// Closing a descriptor removes it on Linux, macOS and uefi. On Windows
// remove it before closing it.
i32 net_poller_set(i64 p, i64 fd, i16 events, i64 token) {
    when os(linux) {
        noinit u8[16] ev;
        u32 bits = 0;
        if (events & NET_POLLIN) != 0 { bits = bits | 1; }
        if (events & NET_POLLOUT) != 0 { bits = bits | 4; }
        *cast(u32*, &ev[0]) = bits;
        *cast(u64*, &ev[_NET_EPEV_DATA]) = cast(u64, token);
        if events == 0 {
            return epoll_ctl(cast(i32, p), _NET_EPOLL_CTL_DEL, cast(i32, fd), &ev[0]) < 0 ? -1 : 0;
        }
        // Change the entry, or add it when there is none.
        if epoll_ctl(cast(i32, p), _NET_EPOLL_CTL_MOD, cast(i32, fd), &ev[0]) == 0 { return 0; }
        return epoll_ctl(cast(i32, p), _NET_EPOLL_CTL_ADD, cast(i32, fd), &ev[0]) < 0 ? -1 : 0;
    } else when os(macos) {
        // kqueue keeps one filter for reading and one for writing.
        // Removing a filter that is absent fails only when both are.
        i32 kq = cast(i32, p);
        u16 on = cast(u16, _NET_EV_ADD | _NET_EV_ENABLE);
        i64 r = _net_kq_change(kq, fd, _NET_EVFILT_READ, (events & NET_POLLIN) != 0 ? on : _NET_EV_DELETE, token);
        if r != 0 && !(r == _NET_ENOENT && (events & NET_POLLIN) == 0) { return -1; }
        bool had_read = r == 0;
        r = _net_kq_change(kq, fd, _NET_EVFILT_WRITE, (events & NET_POLLOUT) != 0 ? on : _NET_EV_DELETE, token);
        if r != 0 && !(r == _NET_ENOENT && (events & NET_POLLOUT) == 0) { return -1; }
        if events == 0 && !had_read && r != 0 { return -1; }
        return 0;
    } else when os(windows) {
        _NetWinPoller* w = _net_win_poller(p);
        if w == null { return -1; }
        i32 at = -1;
        for i32 i = 0; i < w.n; i++ {
            if *(w.fds + i) == fd { at = i; break; }
        }
        if events == 0 {
            if at < 0 { return -1; }
            w.n--;
            *(w.fds + at) = *(w.fds + w.n);
            *(w.events + at) = *(w.events + w.n);
            *(w.tokens + at) = *(w.tokens + w.n);
            return 0;
        }
        if at < 0 {
            if w.n == w.cap {
                i32 cap = w.cap == 0 ? 64 : w.cap * 2;
                i64* nf = alloc<i64>(cap);
                i16* ne = alloc<i16>(cap);
                i64* nt = alloc<i64>(cap);
                if nf == null || ne == null || nt == null { return -1; }
                for i32 i = 0; i < w.n; i++ {
                    *(nf + i) = *(w.fds + i);
                    *(ne + i) = *(w.events + i);
                    *(nt + i) = *(w.tokens + i);
                }
                if w.fds != null { free(w.fds); }
                if w.events != null { free(w.events); }
                if w.tokens != null { free(w.tokens); }
                w.fds = nf;
                w.events = ne;
                w.tokens = nt;
                w.cap = cap;
            }
            at = w.n;
            w.n++;
            *(w.fds + at) = fd;
        }
        *(w.events + at) = events;
        *(w.tokens + at) = token;
        return 0;
    } else when os(uefi) {
        if !_net_be_up() || _net_be.poller_set == null { return -1; }
        return _net_be.poller_set(p, fd, events, token);
    } else {
        return -1;
    }
}

// Waits up to `timeout_ms` for entries to be ready. -1 waits without a
// limit. Puts up to `max` ready entries in `out` and returns how many,
// 0 on timeout, or -1 on error.
//
// On macOS one entry can appear twice in a wait, once for reading and
// once for writing. A program that closes a socket on the first should
// skip tokens it no longer knows.
i32 net_poller_wait(i64 p, NetPollEvent* out, i32 max, i32 timeout_ms) {
    if max <= 0 { return 0; }
    when os(linux) {
        u8* evs = alloc<u8>(max * _NET_EPEV_SIZE);
        if evs == null { return -1; }
        defer free(evs);
        i32 r = epoll_wait(cast(i32, p), evs, max, timeout_ms);
        if r < 0 { return -1; }
        for i32 i = 0; i < r; i++ {
            u8* e = evs + i * _NET_EPEV_SIZE;
            u32 bits = *cast(u32*, e);
            i16 re = 0;
            if (bits & 1) != 0 { re = cast(i16, re | NET_POLLIN); }
            if (bits & 4) != 0 { re = cast(i16, re | NET_POLLOUT); }
            if (bits & 8) != 0 { re = cast(i16, re | NET_POLLERR); }
            if (bits & 0x10) != 0 { re = cast(i16, re | NET_POLLHUP); }
            (out + i).token = cast(i64, *cast(u64*, e + _NET_EPEV_DATA));
            (out + i).revents = re;
        }
        return r;
    } else when os(macos) {
        _NetKEvent* evs = alloc<_NetKEvent>(max);
        if evs == null { return -1; }
        defer free(evs);
        _NetTimespec ts;
        ts.sec = cast(i64, timeout_ms) / 1000;
        ts.nsec = (cast(i64, timeout_ms) % 1000) * 1000000;
        i32 r = kevent(cast(i32, p), null, 0, evs, max, timeout_ms < 0 ? null : &ts);
        if r < 0 { return -1; }
        for i32 i = 0; i < r; i++ {
            _NetKEvent* e = evs + i;
            i16 re = 0;
            if e.filter == _NET_EVFILT_READ { re = NET_POLLIN; }
            else if e.filter == _NET_EVFILT_WRITE { re = NET_POLLOUT; }
            if (e.flags & _NET_EV_EOF) != 0 { re = cast(i16, re | NET_POLLHUP); }
            if (e.flags & _NET_EV_ERROR) != 0 { re = cast(i16, re | NET_POLLERR); }
            (out + i).token = cast(i64, e.udata);
            (out + i).revents = re;
        }
        return r;
    } else when os(windows) {
        _NetWinPoller* w = _net_win_poller(p);
        if w == null { return -1; }
        if w.n == 0 {
            // An empty poller sleeps out the timeout. Without a limit it
            // never returns, as on Linux and macOS.
            if timeout_ms < 0 { Sleep(0xFFFFFFFF); }
            if timeout_ms > 0 { Sleep(cast(u32, timeout_ms)); }
            return 0;
        }
        NetPollFd* fds = alloc<NetPollFd>(w.n);
        if fds == null { return -1; }
        defer free(fds);
        for i32 i = 0; i < w.n; i++ {
            (fds + i).fd = *(w.fds + i);
            (fds + i).events = *(w.events + i);
            (fds + i).revents = 0;
        }
        i32 r = net_poll(fds, w.n, timeout_ms);
        if r < 0 { return -1; }
        i32 k = 0;
        for i32 i = 0; i < w.n && k < max; i++ {
            if (fds + i).revents == 0 { continue; }
            (out + k).token = *(w.tokens + i);
            (out + k).revents = (fds + i).revents;
            k++;
        }
        return k;
    } else when os(uefi) {
        if !_net_be_up() || _net_be.poller_wait == null { return -1; }
        return _net_be.poller_wait(p, out, max, timeout_ms);
    } else {
        return -1;
    }
}
