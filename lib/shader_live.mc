// shader_live.mc — app side of shader live reload.
//
// Usage (include AFTER lib/sokol_all.mc; every call compiles to a
// no-op unless the app is built with -DSHADER_LIVE=1):
//
//   shader_live_init();                      // once, after sg_setup
//   shader_live_register(&pip, &pip_desc,
//                        &cube_vs_shader, &cube_fs_shader);
//   shader_live_frame();                     // per frame, before sg_begin_pass
//
// The registration table, source-swap and pipeline-rebuild are shared
// across targets. Only the transport differs:
//
//   native  — a watcher process (`minc run --shader-live`) recompiles
//             the shaders and pushes translated source over loopback
//             TCP; a listener thread queues frames. Port from
//             MINC_SHADER_LIVE_PORT (set by the launcher), else 6601.
//   wasm    — no sockets, no threads. The JS host recompiles the
//             shaders in-browser and calls the exported
//             __shader_live_push() to queue a frame directly.
//
// Each registered pipeline must OWN its shader handle (the normal
// sokol pattern — one sokol_make_shader per pipeline): the reload
// destroys the old shader along with the old pipeline.
//
// Body edits hot-swap: the watcher/host pushes new translated source,
// the affected shader + pipeline objects are recreated (create-before-
// destroy — buffers, images, bindings, app state untouched).
//
// Interface edits are rejected with a "rebuild app" message. A source
// the GPU backend rejects turns the pipeline pink (when an
// error_source was baked) or keeps the previous shader.
//

when defined(SHADER_LIVE) {

const i32 SL_MAX_REGS = 32;
const i32 SL_MAX_PENDING = 64;
const i32 SL_DEFAULT_PORT = 6601;

bool sl_started;
i32 sl_port_g;

// Listener/host → frame queue (latest record wins per shader name).
// Names and sources are heap copies owned by the queue until
// _shader_live_drain consumes them.
u8*[64] sl_q_names;
i32[64] sl_q_name_lens;
u64[64] sl_q_hashes;
u8*[64] sl_q_sources;       // NUL-terminated
i32[64] sl_q_source_lens;
i32 sl_q_count;

struct SlReg {
    sg_pipeline* pip;
    sg_pipeline_desc desc;   // copy; .shader tracks the CURRENT handle
    ShaderMeta* vs;
    ShaderMeta* fs;
    bool dirty;
}
SlReg[32] sl_regs;
i32 sl_nregs;

// Metas whose .source we've replaced point at a heap buffer (the
// baked original lives in .data and must not be freed).
ShaderMeta*[64] sl_owned;
i32 sl_nowned;

bool sl_is_owned(ShaderMeta* m) {
    for i32 i = 0; i < sl_nowned; i++ {
        if sl_owned[i] == m { return true; }
    }
    return false;
}

void sl_mark_owned(ShaderMeta* m) {
    if sl_is_owned(m) { return; }
    if sl_nowned < 64 {
        sl_owned[sl_nowned] = m;
        sl_nowned++;
    }
}

bool sl_bytes_eq(u8* a, u8* b, i32 n) {
    for i32 i = 0; i < n; i++ {
        if *(a + i) != *(b + i) { return false; }
    }
    return true;
}

i32 sl_zlen(u8* s) {
    i32 n = 0;
    while *(s + n) != 0 { n++; }
    return n;
}

}

// =====================================================================
// Native transport: loopback-TCP listener thread.
// =====================================================================
when defined(SHADER_LIVE) && !os(wasm) {

import net;
import thread;

when os(windows) {
    extern "kernel32.dll" i32 GetEnvironmentVariableA(u8* name, u8* buf, i32 size);
}
when os(macos) {
    extern "libSystem.B.dylib" u8* getenv(u8* name);
}

Mutex sl_lock;
Thread sl_thread;

// Queue mutex — real on native (the listener runs on its own thread).
void sl_mlock() { mutex_lock(&sl_lock); }
void sl_munlock() { mutex_unlock(&sl_lock); }

i32 sl_ru32(u8* p) {
    i32 v = cast(i32, *(p + 0));
    v = v | (cast(i32, *(p + 1)) << 8);
    v = v | (cast(i32, *(p + 2)) << 16);
    v = v | (cast(i32, *(p + 3)) << 24);
    return v;
}

u64 sl_ru64(u8* p) {
    u64 v = 0;
    for i32 i = 7; i >= 0; i-- {
        v = (v << 8) | cast(u64, *(p + i));
    }
    return v;
}

bool sl_recv_all(Socket c, u8* buf, i32 len) {
    i32 got = 0;
    while got < len {
        i32 n = net_recv(c, buf + got, len - got);
        if n <= 0 { return false; }
        got += n;
    }
    return true;
}

// Listener thread: connect to the watcher (retry every 500ms — works
// whichever side starts first), receive frames, queue them under the
// lock. Never touches sg_* — all GPU work happens on the app's main
// thread in shader_live_frame.
void sl_listener(void* arg) {
    while true {
        Socket c = net_connect_loopback(cast(u16, sl_port_g));
        if !c.valid {
            thread_sleep(500);
            continue;
        }
        while true {
            u8[28] hdr;
            if !sl_recv_all(c, &hdr[0], 28) { break; }
            if sl_ru32(&hdr[0]) != 0x564C534D || sl_ru32(&hdr[4]) != 1 { break; }
            i32 nl = sl_ru32(&hdr[20]);
            i32 srcl = sl_ru32(&hdr[24]);
            if nl <= 0 || nl > 256 || srcl < 0 || srcl > 8388608 { break; }
            u8* nm = alloc<u8>(nl);
            if !sl_recv_all(c, nm, nl) { free(nm); break; }
            u8* src = alloc<u8>(srcl + 1);
            if !sl_recv_all(c, src, srcl) { free(nm); free(src); break; }
            src[srcl] = 0;
            u64 h = sl_ru64(&hdr[12]);

            mutex_lock(&sl_lock);
            i32 slot = sl_q_count;
            for i32 i = 0; i < sl_q_count; i++ {
                if sl_q_name_lens[i] == nl && sl_bytes_eq(sl_q_names[i], nm, nl) {
                    slot = i;
                    break;
                }
            }
            if slot < sl_q_count {
                free(sl_q_names[slot]);
                free(sl_q_sources[slot]);
            }
            else if sl_q_count >= SL_MAX_PENDING {
                mutex_unlock(&sl_lock);
                free(nm);
                free(src);
                continue;
            }
            else {
                sl_q_count++;
            }
            sl_q_names[slot] = nm;
            sl_q_name_lens[slot] = nl;
            sl_q_hashes[slot] = h;
            sl_q_sources[slot] = src;
            sl_q_source_lens[slot] = srcl;
            mutex_unlock(&sl_lock);
        }
        net_close(c);
        thread_sleep(500);
    }
}

// Parse a decimal port from `s` (len bytes). 0 = invalid.
i32 sl_parse_port(u8* s, i32 len) {
    i32 v = 0;
    for i32 i = 0; i < len; i++ {
        u8 c = *(s + i);
        if c < 48 || c > 57 { return 0; }
        v = v * 10 + cast(i32, c - 48);
        if v > 65535 { return 0; }
    }
    return v;
}

// The watcher (`minc run --shader-live`) exports MINC_SHADER_LIVE_PORT
// into the app's environment, so the port never lives in app source
// and --port works end-to-end. Returns 0 when unset/invalid.
i32 sl_env_port() {
    when os(windows) {
        u8[16] buf;
        i32 n = GetEnvironmentVariableA("MINC_SHADER_LIVE_PORT", &buf[0], 16);
        if n > 0 && n < 16 { return sl_parse_port(&buf[0], n); }
        return 0;
    }
    when os(macos) {
        u8* v = getenv("MINC_SHADER_LIVE_PORT");
        if v == null { return 0; }
        return sl_parse_port(v, sl_zlen(v));
    }
    when os(linux) {
        // Static minc binaries carry no libc — scan the environ file.
        u8[16384] env;
        i64 fd = open("/proc/self/environ", 0);
        if fd < 0 { return 0; }
        i32 n = read(fd, cast(void*, &env[0]), 16384);
        close(fd);
        u8* key = "MINC_SHADER_LIVE_PORT=";
        i32 i = 0;
        while i < n {
            i32 s = i;
            while i < n && env[i] != 0 { i++; }
            if i - s > 22 && sl_bytes_eq(&env[s], key, 22) {
                return sl_parse_port(&env[s + 22], i - s - 22);
            }
            i++;
        }
        return 0;
    }
    return 0;
}

// Environment port (set by `minc run --shader-live`) wins over the
// argument — the launcher knows which port its watcher bound.
void shader_live_init(i32 port) {
    if sl_started { return; }
    sl_started = true;
    i32 ep = sl_env_port();
    if ep > 0 { port = ep; }
    sl_port_g = port;
    net_init();
    mutex_init(&sl_lock);
    thread_create(&sl_thread, sl_listener, null);
}

// Preferred form — no port in app source: MINC_SHADER_LIVE_PORT when
// launched via `minc run --shader-live`, default 6601 otherwise.
void shader_live_init() {
    shader_live_init(SL_DEFAULT_PORT);
}

}

// =====================================================================
// Wasm transport: the JS host pushes recompiled shader source directly.
// =====================================================================
when defined(SHADER_LIVE) && os(wasm) {

// Single-threaded: the host calls __shader_live_push and the frame
// callback drains, both on the one wasm thread. No lock needed.
void sl_mlock() { return; }
void sl_munlock() { return; }

// No sockets, no env, no listener thread — the host drives the queue.
void shader_live_init(i32 port) {
    if sl_started { return; }
    sl_started = true;
}
void shader_live_init() {
    shader_live_init(SL_DEFAULT_PORT);
}

// Called by the JS host (sokol_wasm_host.js → SOKOL.pushShader).
// `nm` and `src` are heap blocks the host allocated via __wasm_alloc;
// the queue takes ownership and _shader_live_drain frees them, exactly
// as the native listener's alloc<u8> buffers are freed. `src` is
// NUL-terminated by the host. Mirrors one native enqueue iteration:
// latest record per shader name wins. Returns 1 when queued.
export i32 __shader_live_push(u8* nm, i32 nl, u64 h, u8* src, i32 srcl) {
    if nl <= 0 || nl > 256 || srcl < 0 { return 0; }
    i32 slot = sl_q_count;
    for i32 i = 0; i < sl_q_count; i++ {
        if sl_q_name_lens[i] == nl && sl_bytes_eq(sl_q_names[i], nm, nl) {
            slot = i;
            break;
        }
    }
    if slot < sl_q_count {
        free(sl_q_names[slot]);
        free(sl_q_sources[slot]);
    }
    else if sl_q_count >= SL_MAX_PENDING {
        free(nm);
        free(src);
        return 0;
    }
    else {
        sl_q_count++;
    }
    sl_q_names[slot] = nm;
    sl_q_name_lens[slot] = nl;
    sl_q_hashes[slot] = h;
    sl_q_sources[slot] = src;
    sl_q_source_lens[slot] = srcl;
    return 1;
}

}

// =====================================================================
// Shared: registration, queue drain, pipeline rebuild, frame entry.
// =====================================================================
when defined(SHADER_LIVE) {

void shader_live_register(sg_pipeline* pip, sg_pipeline_desc* desc, ShaderMeta* vs, ShaderMeta* fs) {
    if sl_nregs >= SL_MAX_REGS {
        eprint("shader live: register table full\n");
        return;
    }
    SlReg* r = &sl_regs[sl_nregs];
    r.pip = pip;
    if desc != null { r.desc = *desc; }
    r.vs = vs;
    r.fs = fs;
    r.dirty = false;
    sl_nregs++;
}

// Match one pending record against a meta. Returns true when the
// record belongs to this meta (regardless of whether a swap happened).
bool sl_apply_to_meta(ShaderMeta* m, u8* nm, i32 nl, u64 h, u8* src, i32 srcl, bool* did_swap) {
    if m == null || m.name == null { return false; }
    if sl_zlen(m.name) != nl || !sl_bytes_eq(m.name, nm, nl) { return false; }
    if m.source == src {
        // Already swapped via another registration sharing this meta.
        *did_swap = true;
        return true;
    }
    if m.iface_hash != h {
        str ns;
        ns.data = nm;
        ns.len = nl;
        eprint("shader live: '{}' interface changed — rebuild the app\n", ns);
        return true;
    }
    if sl_zlen(m.source) == srcl && sl_bytes_eq(m.source, src, srcl) {
        // Identical source (watcher restart replay) — nothing to do.
        return true;
    }
    if sl_is_owned(m) { free(m.source); }
    m.source = src;
    sl_mark_owned(m);
    *did_swap = true;
    return true;
}

// Drain the queue: swap sources on matching metas, mark affected
// registrations dirty. No sg_* calls — the rebuild layer below picks
// the dirty flags up.
void _shader_live_drain() {
    sl_mlock();
    i32 n = sl_q_count;
    u8*[64] names;
    i32[64] name_lens;
    u64[64] hashes;
    u8*[64] sources;
    i32[64] source_lens;
    for i32 i = 0; i < n; i++ {
        names[i] = sl_q_names[i];
        name_lens[i] = sl_q_name_lens[i];
        hashes[i] = sl_q_hashes[i];
        sources[i] = sl_q_sources[i];
        source_lens[i] = sl_q_source_lens[i];
    }
    sl_q_count = 0;
    sl_munlock();

    for i32 i = 0; i < n; i++ {
        bool swapped = false;
        for i32 ri = 0; ri < sl_nregs; ri++ {
            SlReg* r = &sl_regs[ri];
            bool hit = false;
            if sl_apply_to_meta(r.vs, names[i], name_lens[i], hashes[i], sources[i], source_lens[i], &swapped) { hit = true; }
            if sl_apply_to_meta(r.fs, names[i], name_lens[i], hashes[i], sources[i], source_lens[i], &swapped) { hit = true; }
            if hit && swapped { r.dirty = true; }
        }
        free(names[i]);
        if !swapped { free(sources[i]); }
    }
}

when !defined(SHADER_LIVE_NO_GFX) {

// Rebuild every dirty registration: create-before-destroy, pink
// fallback on GPU-compile failure, keep-old on total failure. Runs on
// the app's main thread (sokol_gfx is single-threaded).
void _shader_live_rebuild() {
    for i32 ri = 0; ri < sl_nregs; ri++ {
        SlReg* r = &sl_regs[ri];
        if !r.dirty { continue; }
        r.dirty = false;
        if r.pip == null { continue; }

        bool pink = false;
        sg_shader new_shd = sokol_make_shader(r.vs, r.fs);
        if sg_query_shader_state(new_shd) == SG_RESOURCESTATE_FAILED {
            sg_destroy_shader(new_shd);
            if r.fs != null && r.fs.error_source != null {
                u8* saved = r.fs.source;
                r.fs.source = r.fs.error_source;
                new_shd = sokol_make_shader(r.vs, r.fs);
                r.fs.source = saved;
                if sg_query_shader_state(new_shd) == SG_RESOURCESTATE_FAILED {
                    sg_destroy_shader(new_shd);
                    eprint("shader live: GPU compile failed — kept previous shader\n");
                    continue;
                }
                pink = true;
            } else {
                eprint("shader live: GPU compile failed — kept previous shader\n");
                continue;
            }
        }

        sg_pipeline_desc d = r.desc;
        d.shader = new_shd;
        sg_pipeline new_pip = sg_make_pipeline(&d);
        if sg_query_pipeline_state(new_pip) == SG_RESOURCESTATE_FAILED {
            sg_destroy_pipeline(new_pip);
            sg_destroy_shader(new_shd);
            eprint("shader live: pipeline rebuild failed — kept previous\n");
            continue;
        }

        sg_destroy_pipeline(*r.pip);
        sg_destroy_shader(r.desc.shader);
        *r.pip = new_pip;
        r.desc.shader = new_shd;
        if pink {
            eprint("shader live: GPU compile failed — pink fallback on screen\n");
        } else {
            print("shader live: shader reloaded\n");
        }
    }
}

void shader_live_frame() {
    if !sl_started { return; }
    _shader_live_drain();
    _shader_live_rebuild();
}

}

when defined(SHADER_LIVE_NO_GFX) {
void shader_live_frame() {
    if !sl_started { return; }
    _shader_live_drain();
}
}

}

when !defined(SHADER_LIVE) {
void shader_live_init() { return; }
void shader_live_init(i32 port) { return; }
void shader_live_register(sg_pipeline* pip, sg_pipeline_desc* desc, ShaderMeta* vs, ShaderMeta* fs) { return; }
void shader_live_frame() { return; }
}
