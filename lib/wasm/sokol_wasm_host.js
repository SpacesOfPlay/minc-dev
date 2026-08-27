// JS-side glue for the wasm sokol port (env / gl / sapp / math / saudio).
'use strict';

(() => {
const SOKOL = {};
window.sokolWasm = SOKOL;

// Stubs so a script-load throw (missing <canvas>, no WebGL2) surfaces
// as the real error from run() instead of "is not a function".
SOKOL._initError = null;
SOKOL.runFromBytes = async function() { throw SOKOL._initError || new Error('sokol_wasm_host: not initialized'); };
SOKOL.run = SOKOL.runFromBytes;

// Asset VFS.
SOKOL._vfs = {};
SOKOL._fdMap = {};
SOKOL._nextFd = 100;

SOKOL.onLog = (msg, isError) => {
    if (isError) console.warn(msg); else console.log(msg);
};

// Pre-fetch assets into the VFS before runFromBytes.
SOKOL.preloadAssets = async function(paths) {
    if (!paths || paths.length === 0) return;
    await Promise.all(paths.map(async (p) => {
        const url = (typeof p === 'string') ? p : p.url;
        const key = (typeof p === 'string') ? p : p.path;
        try {
            const r = await fetch(url + '?t=' + Date.now());
            if (!r.ok) { console.warn(`preloadAssets: ${url} → HTTP ${r.status}`); return; }
            SOKOL._vfs[key] = new Uint8Array(await r.arrayBuffer());
        } catch (e) {
            console.warn(`preloadAssets: ${url} → ${e.message}`);
        }
    }));
};

// Fade audio out, then tear down.
SOKOL.stopAudio = async function(fadeMs) {
    const ms = (typeof fadeMs === 'number') ? fadeMs : 50;
    const ctx = SOKOL._saudioCtx;
    if (ctx && SOKOL._saudioGain) {
        const t = ctx.currentTime;
        try {
            SOKOL._saudioGain.gain.cancelScheduledValues(t);
            SOKOL._saudioGain.gain.setValueAtTime(SOKOL._saudioGain.gain.value, t);
            SOKOL._saudioGain.gain.linearRampToValueAtTime(0, t + ms / 1000);
        } catch (e) { /* ignore */ }
        await new Promise((res) => setTimeout(res, ms + 20));
    }
    if (SOKOL._saudioProducer) { clearInterval(SOKOL._saudioProducer); SOKOL._saudioProducer = null; }
    if (SOKOL._saudioGain) { SOKOL._saudioGain.disconnect(); SOKOL._saudioGain = null; }
    if (SOKOL._saudioNode) { SOKOL._saudioNode.disconnect(); SOKOL._saudioNode = null; }
    if (SOKOL._saudioCtx) { await SOKOL._saudioCtx.close().catch(() => {}); SOKOL._saudioCtx = null; }
    SOKOL._saudioWorkletReady = false;
};

// Audio worklet is async to load; saudio_js_init is sync; preload first.
SOKOL.preloadAudioWorklet = async function(opts) {
    if (typeof AudioContext === 'undefined') {
        console.warn('preloadAudioWorklet: no AudioContext support');
        return;
    }
    if (SOKOL._saudioWorkletReady) return;
    const ctxOpts = { latencyHint: 'interactive' };
    if (opts && opts.sampleRate) ctxOpts.sampleRate = opts.sampleRate;
    SOKOL._saudioCtx = new AudioContext(ctxOpts);
    const url = (opts && opts.workletURL) || 'sokol_wasm_audio_worklet.js';
    try {
        await SOKOL._saudioCtx.audioWorklet.addModule(url + '?t=' + Date.now());
        SOKOL._saudioWorkletReady = true;
    } catch (e) {
        console.error('preloadAudioWorklet: addModule failed', e);
        SOKOL._saudioCtx.close().catch(() => {});
        SOKOL._saudioCtx = null;
    }
};

// --- Mount point ---------------------------------------------------------
const canvas = document.getElementById('canvas');
if (!canvas) { SOKOL._initError = new Error('sokol_wasm_host: <canvas id="canvas"> required'); return; }
const gl = canvas.getContext('webgl2', { antialias: true, alpha: false });
if (!gl) { SOKOL._initError = new Error('WebGL2 context unavailable: canvas.getContext("webgl2") returned null. Most often the browser has hit its live-WebGL-context limit (~16): close other WebGL/example tabs or restart the browser. Otherwise WebGL2 may be disabled or unsupported in this browser.'); return; }

// Enable every extension so getParameter works for ext-specific pnames.
// WEBGL_debug_renderer_info is skipped: nothing queries the unmasked
// strings and enabling it logs a deprecation warning in Firefox.
(gl.getSupportedExtensions() || []).forEach(name => {
    if (name !== 'WEBGL_debug_renderer_info') gl.getExtension(name);
});

// A lost GL context (GPU recycle, driver reset, tab sleep) used to
// show as a silent black canvas. Surface it loudly; recovery needs
// a reload; sokol's GL objects don't survive a lost context.
let glLost = false;
canvas.addEventListener('webglcontextlost', (e) => {
    e.preventDefault();
    glLost = true;
    const m = 'WebGL context lost (GPU reset / tab slept). Reload the page to recover.';
    console.error('sokol_wasm_host: ' + m);
    try { SOKOL.onLog(m + '\n', true); } catch (_) {}
}, false);
canvas.addEventListener('webglcontextrestored', () => {
    const m = 'WebGL context restored; reload the page to re-run the demo.';
    console.warn('sokol_wasm_host: ' + m);
    try { SOKOL.onLog(m + '\n', true); } catch (_) {}
}, false);

// --- Memory + arg decoding ----------------------------------------------
let memory = null;
const u8view = () => new Uint8Array(memory.buffer);
const readString = (ptr, len) => new TextDecoder().decode(u8view().slice(Number(ptr), Number(ptr) + Number(len)));
const readCStr = (ptr) => {
    const u8 = u8view();
    const start = Number(ptr);
    let end = start;
    while (u8[end] !== 0 && end - start < 4096) end++;
    // slice, not subarray: TextDecoder rejects SharedArrayBuffer-backed
    // views (--threads builds; Safari is the only engine that allows them).
    return new TextDecoder().decode(u8.slice(start, end));
};

// Natural extern ABI: i32/f32/f64/pointer args and returns cross as
// plain Numbers; u32/u64/i64 cross as BigInt.

// Wrap a void-returning import so a stub that returns undefined still
// hands something back. The result of a void import is ignored either way.
const v = (fn) => (...args) => { fn(...args); return 0n; };

// --- WebGL handle table --------------------------------------------------
const handles = [null];
const put = (o)  => { handles.push(o); return BigInt(handles.length - 1); };
const get = (id) => handles[Number(id)];

// --- Quit / raf state ----------------------------------------------------
let quitRequested = false;
let frameCount = 0;
let instance = null;
// Re-run support: runFromBytes can be called again (the playground swaps
// examples without reloading). A new run must cancel the prior rafLoop;
// otherwise two loops stay registered and requestAnimationFrame fires both
// with the SAME timestamp in one frame, so the instance's _sapp_wasm_frame
// runs twice and the second call sees dt = (t - t) = 0. sokol's frame-timing
// avg then collapses to 0, and Dear ImGui asserts "Need a positive DeltaTime!".
let rafId = 0;

// Optional embedder hooks (the shell playground drives run/stop cycles):
// onQuit fires once when the loop ends; stop() halts a run externally.
SOKOL.onQuit = null;
function fireQuit() { const f = SOKOL.onQuit; SOKOL.onQuit = null; if (f) f(); }
SOKOL.stop = function() {
    quitRequested = true;
    if (rafId) { cancelAnimationFrame(rafId); rafId = 0; }
    instance = null;
    SOKOL.instance = null;
};

// A frame exception stops the loop; without this it died in the console
// and the page just looked frozen. Surface it: onLog for embedders, and
// a window ErrorEvent so plain pages' error overlays fire.
function reportFrameError(e) {
    console.error('frame error:', e);
    quitRequested = true;
    const m = 'frame error: ' + ((e && e.message) || e);
    try { SOKOL.onLog(m + '\n', true); } catch (_) {}
    try { window.dispatchEvent(new ErrorEvent('error', { message: m, error: e })); } catch (_) {}
    fireQuit();
}

function rafLoop(time) {
    if (quitRequested || glLost) { fireQuit(); return; }
    if (!instance) return;
    // Sync drawing buffer; dispatch resize when size actually changes.
    const dpr = window.devicePixelRatio || 1;
    const w = Math.max(1, Math.floor(canvas.clientWidth * dpr));
    const h = Math.max(1, Math.floor(canvas.clientHeight * dpr));
    if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w;
        canvas.height = h;
        if (instance && instance.exports._sapp_wasm_event_resized) {
            instance.exports._sapp_wasm_event_resized(w, h);
        }
    }
    SOKOL._lastWidth = canvas.width;
    SOKOL._lastHeight = canvas.height;
    try {
        if (instance.exports._sapp_wasm_frame) {
            instance.exports._sapp_wasm_frame(time || 0);
        }
    } catch (e) {
        reportFrameError(e);
        return;
    }
    frameCount++;
    rafId = requestAnimationFrame(rafLoop);
}

// --- Imports -------------------------------------------------------------
SOKOL.makeImports = function() {
    return {
        env: {
            write: (fd, ptr, len) => {
                const s = readString(ptr, len);
                SOKOL.onLog(s, Number(fd) === 2);
                return BigInt(Number(len));
            },
            clock: () => BigInt(Math.round(performance.now() * 1e6)),
                __wasm_abort: () => { throw new Error('sokol abort(): assertion failed in wasm'); },
            __sys_exit: (code) => {
                console.error(`__sys_exit(${code}): wasm requested process exit`);
                quitRequested = true;
                throw new Error(`__sys_exit(${code})`);
            },
            // VFS-backed open/read/close.
            open: (pathPtr, flags) => {
                const path = readCStr(pathPtr);
                const data = SOKOL._vfs && SOKOL._vfs[path];
                if (!data) return -1n;
                const fd = SOKOL._nextFd++;
                SOKOL._fdMap[fd] = { data, pos: 0 };
                return BigInt(fd);
            },
            read: (fd, ptr, len) => {
                const f = SOKOL._fdMap[Number(fd)];
                if (!f) return 0n;
                const remaining = f.data.length - f.pos;
                const n = Math.min(remaining, Number(len));
                if (n <= 0) return 0n;
                const dst = new Uint8Array(memory.buffer);
                dst.set(f.data.subarray(f.pos, f.pos + n), Number(ptr));
                f.pos += n;
                return BigInt(n);
            },
            close: (fd) => {
                delete SOKOL._fdMap[Number(fd)];
                return 0n;
            },
            // Command-line args: none in the browser. get_argc()<=1 makes
            // argv-driven examples (chip8 picks a ROM from arg[1]) fall back
            // to their default; get_arg is never reached at argc 0.
            get_argc: () => 0n,
            get_arg: (i) => 0n,
        },

        // WebGL2 surface. Proxy stubs any unimplemented gl* extern.
        gl: (() => {
            const stubbedCalls = new Set();
            const autoStub = (name) => (...args) => {
                if (!stubbedCalls.has(name)) {
                    stubbedCalls.add(name);
                    console.warn(`[sokol] gl auto-stub called: ${name}(${args.length} args)`);
                }
                return 0n;
            };
            const wrapTable = (tbl) => new Proxy(tbl, {
                get(target, prop) {
                    if (prop in target) return target[prop];
                    if (typeof prop === 'string' && prop.startsWith('gl')) {
                        return autoStub(prop);
                    }
                    return undefined;
                },
            });
            const N = (x) => Number(x);
            const arr = (kind, ptr, count) => {
                const buf = memory.buffer; const off = N(ptr);
                if (kind === 'f32')  return new Float32Array(buf, off, N(count));
                if (kind === 'f64')  return new Float64Array(buf, off, N(count));
                if (kind === 'i32')  return new Int32Array(buf, off, N(count));
                if (kind === 'u32')  return new Uint32Array(buf, off, N(count));
                if (kind === 'i8')   return new Int8Array(buf, off, N(count));
                if (kind === 'u8')   return new Uint8Array(buf, off, N(count));
            };
            const writeStr = (ptr, s) => { const b = new TextEncoder().encode(s); u8view().set(b, N(ptr)); u8view()[N(ptr) + b.length] = 0; };

            // GL enums
            const GL_RGBA = 0x1908, GL_BGRA = 0x80E1, GL_RGBA_INTEGER = 0x8D99;
            const GL_RGB = 0x1907, GL_RGB_INTEGER = 0x8D98;
            const GL_RG = 0x8227, GL_RG_INTEGER = 0x8228;
            const GL_FLOAT = 0x1406, GL_INT = 0x1404, GL_UNSIGNED_INT = 0x1405;
            const GL_HALF_FLOAT = 0x140B, GL_UNSIGNED_SHORT = 0x1403;
            const GL_UNSIGNED_SHORT_4_4_4_4 = 0x8033, GL_UNSIGNED_SHORT_5_5_5_1 = 0x8034;
            const GL_UNSIGNED_SHORT_5_6_5 = 0x8363, GL_UNSIGNED_SHORT_1_5_5_5_REV = 0x8366;
            const GL_UNSIGNED_INT_2_10_10_10_REV = 0x8368, GL_UNSIGNED_INT_24_8 = 0x84FA;
            const GL_UNSIGNED_INT_10F_11F_11F_REV = 0x8C3B, GL_UNSIGNED_INT_5_9_9_9_REV = 0x8C3E;
            const GL_FLOAT_32_UNSIGNED_INT_24_8_REV = 0x8DAD;
            const GL_UNPACK_ROW_LENGTH = 0x0CF2, GL_UNPACK_IMAGE_HEIGHT = 0x806E;
            const GL_UNPACK_ALIGNMENT = 0x0CF5;

            // Pixel unpack state. WebGL validates uploads against the source
            // view length, so the view must cover the full unpack footprint
            // (row stride from UNPACK_ROW_LENGTH), not just w*h texels.
            const unpack = { rowLength: 0, imageHeight: 0, alignment: 4 };
            const texelSize = (f, t) => {
                // Packed types store the whole texel in one value; the
                // format's channel count does not apply.
                switch (t) {
                    case GL_UNSIGNED_SHORT_4_4_4_4:
                    case GL_UNSIGNED_SHORT_5_5_5_1:
                    case GL_UNSIGNED_SHORT_5_6_5:
                    case GL_UNSIGNED_SHORT_1_5_5_5_REV: return 2;
                    case GL_UNSIGNED_INT_2_10_10_10_REV:
                    case GL_UNSIGNED_INT_24_8:
                    case GL_UNSIGNED_INT_10F_11F_11F_REV:
                    case GL_UNSIGNED_INT_5_9_9_9_REV: return 4;
                    case GL_FLOAT_32_UNSIGNED_INT_24_8_REV: return 8;
                }
                // Single-channel formats (GL_RED, GL_DEPTH_COMPONENT, ...)
                // and 1-byte types fall through.
                const ch = (f === GL_RGBA || f === GL_BGRA || f === GL_RGBA_INTEGER) ? 4
                         : (f === GL_RGB || f === GL_RGB_INTEGER) ? 3
                         : (f === GL_RG || f === GL_RG_INTEGER) ? 2
                         : 1;
                const bpc = (t === GL_FLOAT || t === GL_INT || t === GL_UNSIGNED_INT) ? 4
                          : (t === GL_HALF_FLOAT || t === GL_UNSIGNED_SHORT) ? 2
                          : 1;
                return ch * bpc;
            };
            const uploadBytes = (w, h, d, bpp) => {
                if (w <= 0 || h <= 0 || d <= 0) return 0;
                const rowTexels = unpack.rowLength > 0 ? Math.max(unpack.rowLength, w) : w;
                const align = unpack.alignment;
                const rowStride = Math.ceil((rowTexels * bpp) / align) * align;
                const imgRows = unpack.imageHeight > 0 ? Math.max(unpack.imageHeight, h) : h;
                return (d - 1) * imgRows * rowStride + (h - 1) * rowStride + w * bpp;
            };

            const table = {
                // Clear / viewport / scissor
                glClearColor:   v((r,g,b,a) => gl.clearColor(r, g, b, a)),
                glClear:        v((mask)    => gl.clear(N(mask))),
                glViewport:     v((x,y,w,h) => gl.viewport(N(x), N(y), N(w), N(h))),
                glScissor:      v((x,y,w,h) => gl.scissor(N(x), N(y), N(w), N(h))),

                // Render state
                glEnable:                v((c) => gl.enable(N(c))),
                glDisable:               v((c) => gl.disable(N(c))),
                glColorMask:             v((r,g,b,a) => gl.colorMask(!!N(r), !!N(g), !!N(b), !!N(a))),
                glDepthMask:             v((m) => gl.depthMask(!!N(m))),
                glDepthFunc:             v((f) => gl.depthFunc(N(f))),
                glCullFace:              v((m) => gl.cullFace(N(m))),
                glFrontFace:             v((m) => gl.frontFace(N(m))),
                glPolygonOffset:         v((a,b) => gl.polygonOffset(a, b)),
                glBlendColor:            v((r,g,b,a) => gl.blendColor(r, g, b, a)),
                glBlendEquationSeparate: v((rgb,a) => gl.blendEquationSeparate(N(rgb), N(a))),
                glBlendFuncSeparate:     v((sr,dr,sa,da) => gl.blendFuncSeparate(N(sr), N(dr), N(sa), N(da))),
                glStencilFunc:           v((f,r,m) => gl.stencilFunc(N(f), N(r), N(m))),
                glStencilFuncSeparate:   v((face,f,r,m) => gl.stencilFuncSeparate(N(face), N(f), N(r), N(m))),
                glStencilOp:             v((sf,df,dp) => gl.stencilOp(N(sf), N(df), N(dp))),
                glStencilOpSeparate:     v((face,sf,df,dp) => gl.stencilOpSeparate(N(face), N(sf), N(df), N(dp))),
                glStencilMask:           v((m) => gl.stencilMask(N(m))),
                glPixelStorei:           v((p,v_) => {
                    const pn = N(p), vn = N(v_);
                    if (pn === GL_UNPACK_ROW_LENGTH) unpack.rowLength = vn;
                    else if (pn === GL_UNPACK_IMAGE_HEIGHT) unpack.imageHeight = vn;
                    else if (pn === GL_UNPACK_ALIGNMENT) unpack.alignment = vn;
                    gl.pixelStorei(pn, vn);
                }),

                // Buffer objects
                glGenBuffers: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) v32[k] = Number(put(gl.createBuffer()));
                }),
                glDeleteBuffers: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) { gl.deleteBuffer(get(v32[k])); handles[v32[k]] = null; }
                }),
                glBindBuffer:      v((tgt, b) => gl.bindBuffer(N(tgt), get(b))),
                glBindBufferBase:  v((tgt,idx,b) => gl.bindBufferBase(N(tgt), N(idx), get(b))),
                glBindBufferRange: v((tgt,idx,b,off,sz) => gl.bindBufferRange(N(tgt), N(idx), get(b), N(off), N(sz))),
                glBufferData: v((tgt, sz, ptr, usage) => {
                    if (N(ptr) === 0) gl.bufferData(N(tgt), N(sz), N(usage));
                    else gl.bufferData(N(tgt), arr('u8', ptr, sz), N(usage));
                }),
                glBufferSubData: v((tgt, off, sz, ptr) => gl.bufferSubData(N(tgt), N(off), arr('u8', ptr, sz))),

                // Vertex arrays
                glGenVertexArrays: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) v32[k] = Number(put(gl.createVertexArray()));
                }),
                glDeleteVertexArrays: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) { gl.deleteVertexArray(get(v32[k])); handles[v32[k]] = null; }
                }),
                glBindVertexArray:           v((va) => gl.bindVertexArray(get(va))),
                glEnableVertexAttribArray:   v((i) => gl.enableVertexAttribArray(N(i))),
                glDisableVertexAttribArray:  v((i) => gl.disableVertexAttribArray(N(i))),
                glVertexAttribPointer:       v((i,sz,ty,nm,st,off) => gl.vertexAttribPointer(N(i), N(sz), N(ty), !!N(nm), N(st), N(off))),
                glVertexAttribIPointer:      v((i,sz,ty,st,off) => gl.vertexAttribIPointer(N(i), N(sz), N(ty), N(st), N(off))),
                glVertexAttribDivisor:       v((i,d) => gl.vertexAttribDivisor(N(i), N(d))),

                // Textures
                glGenTextures: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) v32[k] = Number(put(gl.createTexture()));
                }),
                glDeleteTextures: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) { gl.deleteTexture(get(v32[k])); handles[v32[k]] = null; }
                }),
                glActiveTexture: v((u) => gl.activeTexture(N(u))),
                glBindTexture:   v((tgt, t) => gl.bindTexture(N(tgt), get(t))),

                glTexStorage2D: v((tgt, levels, ifmt, w, h) =>
                    gl.texStorage2D(N(tgt), N(levels), N(ifmt), N(w), N(h))),
                glTexStorage3D: v((tgt, levels, ifmt, w, h, d) =>
                    gl.texStorage3D(N(tgt), N(levels), N(ifmt), N(w), N(h), N(d))),
                glTexSubImage2D: v((tgt, lvl, xo, yo, w, h, fmt, ty, ptr) => {
                    const wn = N(w), hn = N(h), tyn = N(ty), fmtn = N(fmt);
                    const bytes = uploadBytes(wn, hn, 1, texelSize(fmtn, tyn));
                    const data = new Uint8Array(memory.buffer, N(ptr), bytes);
                    gl.texSubImage2D(N(tgt), N(lvl), N(xo), N(yo), wn, hn, fmtn, tyn, data);
                }),
                glTexImage2D: v((tgt, lvl, ifmt, w, h, border, fmt, ty, ptr) => {
                    const wn = N(w), hn = N(h), tyn = N(ty), fmtn = N(fmt);
                    const bytes = uploadBytes(wn, hn, 1, texelSize(fmtn, tyn));
                    const ptrN = N(ptr);
                    const data = ptrN ? new Uint8Array(memory.buffer, ptrN, bytes) : null;
                    gl.texImage2D(N(tgt), N(lvl), N(ifmt), wn, hn, N(border), fmtn, tyn, data);
                }),
                glTexParameteri: v((tgt, pname, param) =>
                    gl.texParameteri(N(tgt), N(pname), N(param))),
                glTexParameterf: v((tgt, pname, param) =>
                    gl.texParameterf(N(tgt), N(pname), param)),
                glGenerateMipmap: v((tgt) => gl.generateMipmap(N(tgt))),
                glGetError: () => BigInt(gl.getError()),
                glInvalidateFramebuffer: v((tgt, n, ptr) => {
                    const att = Array.from(arr('u32', ptr, N(n))).map(Number);
                    gl.invalidateFramebuffer(N(tgt), att);
                }),

                // Renderbuffers (sokol_gfx MSAA resolve) + compressed/3D
                // texture uploads. sokol_gfx imports these; Dear ImGui only
                // uses the 2D path, but every import must be provided for the
                // module to instantiate.
                glGenRenderbuffers: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) v32[k] = Number(put(gl.createRenderbuffer()));
                }),
                glBindRenderbuffer: v((tgt, rb) => gl.bindRenderbuffer(N(tgt), get(rb))),
                glRenderbufferStorageMultisample: v((tgt, samples, ifmt, w, h) =>
                    gl.renderbufferStorageMultisample(N(tgt), N(samples), N(ifmt), N(w), N(h))),
                glCompressedTexSubImage2D: v((tgt, lvl, xo, yo, w, h, fmt, sz, ptr) => {
                    const data = new Uint8Array(memory.buffer, N(ptr), N(sz));
                    gl.compressedTexSubImage2D(N(tgt), N(lvl), N(xo), N(yo), N(w), N(h), N(fmt), data);
                }),
                glCompressedTexSubImage3D: v((tgt, lvl, xo, yo, zo, w, h, d, fmt, sz, ptr) => {
                    const data = new Uint8Array(memory.buffer, N(ptr), N(sz));
                    gl.compressedTexSubImage3D(N(tgt), N(lvl), N(xo), N(yo), N(zo), N(w), N(h), N(d), N(fmt), data);
                }),
                glTexSubImage3D: v((tgt, lvl, xo, yo, zo, w, h, d, fmt, ty, ptr) => {
                    const wn = N(w), hn = N(h), dn = N(d), tyn = N(ty), fmtn = N(fmt);
                    const bytes = uploadBytes(wn, hn, dn, texelSize(fmtn, tyn));
                    const data = new Uint8Array(memory.buffer, N(ptr), bytes);
                    gl.texSubImage3D(N(tgt), N(lvl), N(xo), N(yo), N(zo), wn, hn, dn, fmtn, tyn, data);
                }),

                // Samplers
                glGenSamplers: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) v32[k] = Number(put(gl.createSampler()));
                }),
                glDeleteSamplers: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) { gl.deleteSampler(get(v32[k])); handles[v32[k]] = null; }
                }),
                glBindSampler: v((u, s) => gl.bindSampler(N(u), get(s))),
                glSamplerParameteri: v((s, pname, param) =>
                    gl.samplerParameteri(get(s), N(pname), N(param))),
                glSamplerParameterf: v((s, pname, param) =>
                    gl.samplerParameterf(get(s), N(pname), param)),
                glSamplerParameterfv: v((s, pname, ptr) => {
                    const p = N(pname);
                    if (p === 0x1004) return;  // GL_TEXTURE_BORDER_COLOR unsupported on WebGL2
                    const f = arr('f32', ptr, 1);
                    gl.samplerParameterf(get(s), p, f[0]);
                }),

                // Framebuffers / renderbuffers
                glGenFramebuffers: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) v32[k] = Number(put(gl.createFramebuffer()));
                }),
                glDeleteFramebuffers: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) { gl.deleteFramebuffer(get(v32[k])); handles[v32[k]] = null; }
                }),
                glBindFramebuffer:          v((tgt, f) => gl.bindFramebuffer(N(tgt), get(f))),
                glCheckFramebufferStatus:   (tgt) => BigInt(gl.checkFramebufferStatus(N(tgt))),
                glFramebufferTexture2D:     v((tgt,att,texT,t,lvl) => gl.framebufferTexture2D(N(tgt), N(att), N(texT), get(t), N(lvl))),
                glFramebufferTextureLayer:  v((tgt,att,t,lvl,layer) => gl.framebufferTextureLayer(N(tgt), N(att), get(t), N(lvl), N(layer))),
                glFramebufferRenderbuffer:  v((tgt,att,rbTgt,rb) => gl.framebufferRenderbuffer(N(tgt), N(att), N(rbTgt), get(rb))),
                glDeleteRenderbuffers: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    for (let k = 0; k < N(n); k++) { gl.deleteRenderbuffer(get(v32[k])); handles[v32[k]] = null; }
                }),
                glReadBuffer:  v((m) => gl.readBuffer(N(m))),
                glDrawBuffers: v((n, ptr) => {
                    const v32 = arr('u32', ptr, N(n));
                    gl.drawBuffers(Array.from(v32));
                }),
                glBlitFramebuffer: v((sx0,sy0,sx1,sy1,dx0,dy0,dx1,dy1,mask,filter) => gl.blitFramebuffer(N(sx0),N(sy0),N(sx1),N(sy1),N(dx0),N(dy0),N(dx1),N(dy1),N(mask),N(filter))),
                glClearBufferfv: v((buf, drawbuf, ptr) => gl.clearBufferfv(N(buf), N(drawbuf), arr('f32', ptr, 4))),
                glClearBufferiv: v((buf, drawbuf, ptr) => gl.clearBufferiv(N(buf), N(drawbuf), arr('i32', ptr, 4))),
                glClearBufferfi: v((buf, drawbuf, depth, stencil) => gl.clearBufferfi(N(buf), N(drawbuf), depth, N(stencil))),

                // Shaders
                glCreateShader:  (t) => BigInt(put(gl.createShader(N(t)))),
                glDeleteShader:  v((s) => { gl.deleteShader(get(s)); }),
                glShaderSource:  v((s, count, strs_ptr, lens_ptr) => {
                    const strs = arr('u32', strs_ptr, N(count));
                    const lens = N(lens_ptr) === 0 ? null : arr('i32', lens_ptr, N(count));
                    let src = '';
                    for (let k = 0; k < N(count); k++) {
                        const sp = strs[k];
                        const sl = lens ? lens[k] : (() => { let p = sp; while (u8view()[p] !== 0) p++; return p - sp; })();
                        src += readString(sp, sl);
                    }
                    const sh = get(s);
                    gl.shaderSource(sh, src);
                    sh._sokolSrc = src;
                }),
                glCompileShader: v((s) => {
                    const sh = get(s);
                    gl.compileShader(sh);
                    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
                        SOKOL.onLog('--- shader compile failed ---\n', true);
                        SOKOL.onLog(sh._sokolSrc + '\n', true);
                        SOKOL.onLog('---\n' + (gl.getShaderInfoLog(sh) || '') + '\n---\n', true);
                    }
                }),
                glGetShaderiv:   v((s, pname, ptr) => {
                    const pn = N(pname);
                    let val;
                    if (pn === 0x8B84) val = (gl.getShaderInfoLog(get(s)) || '').length + 1;
                    else val = gl.getShaderParameter(get(s), pn);
                    arr('i32', ptr, 1)[0] = val | 0;
                }),
                glGetShaderInfoLog: v((s, max, len_ptr, log_ptr) => {
                    const log = gl.getShaderInfoLog(get(s)) || '';
                    const w = log.slice(0, N(max) - 1);
                    writeStr(log_ptr, w);
                    if (N(len_ptr) !== 0) arr('i32', len_ptr, 1)[0] = w.length;
                }),

                // Programs
                glCreateProgram: () => BigInt(put(gl.createProgram())),
                glDeleteProgram: v((p) => { gl.deleteProgram(get(p)); }),
                glAttachShader:  v((p, s) => gl.attachShader(get(p), get(s))),
                glLinkProgram:   v((p) => {
                    const pr = get(p);
                    gl.linkProgram(pr);
                    if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) {
                        SOKOL.onLog('--- program link failed ---\n', true);
                        SOKOL.onLog((gl.getProgramInfoLog(pr) || '') + '\n---\n', true);
                    }
                }),
                glUseProgram:    v((p) => gl.useProgram(get(p))),
                glGetProgramiv:  v((p, pname, ptr) => {
                    const pn = N(pname);
                    let val;
                    if (pn === 0x8B84) val = (gl.getProgramInfoLog(get(p)) || '').length + 1;
                    else val = gl.getProgramParameter(get(p), pn);
                    arr('i32', ptr, 1)[0] = val | 0;
                }),
                glGetProgramInfoLog: v((p, max, len_ptr, log_ptr) => {
                    const log = gl.getProgramInfoLog(get(p)) || '';
                    const w = log.slice(0, N(max) - 1);
                    writeStr(log_ptr, w);
                    if (N(len_ptr) !== 0) arr('i32', len_ptr, 1)[0] = w.length;
                }),
                glGetAttribLocation:  (p, ptr) => {
                    let q = N(ptr); while (u8view()[q] !== 0) q++;
                    return gl.getAttribLocation(get(p), readString(ptr, q - N(ptr)));
                },
                glGetUniformLocation: (p, ptr) => {
                    let q = N(ptr); while (u8view()[q] !== 0) q++;
                    const loc = gl.getUniformLocation(get(p), readString(ptr, q - N(ptr)));
                    return loc === null ? -1 : Number(put(loc));
                },

                // Uniforms
                glUniform1i:        v((l, x) => gl.uniform1i(get(l), N(x))),
                glUniform1iv:       v((l, n, ptr) => gl.uniform1iv(get(l), arr('i32', ptr, N(n)))),
                glUniform2iv:       v((l, n, ptr) => gl.uniform2iv(get(l), arr('i32', ptr, 2 * N(n)))),
                glUniform3iv:       v((l, n, ptr) => gl.uniform3iv(get(l), arr('i32', ptr, 3 * N(n)))),
                glUniform4iv:       v((l, n, ptr) => gl.uniform4iv(get(l), arr('i32', ptr, 4 * N(n)))),
                glUniform1fv:       v((l, n, ptr) => gl.uniform1fv(get(l), arr('f32', ptr, N(n)))),
                glUniform2fv:       v((l, n, ptr) => gl.uniform2fv(get(l), arr('f32', ptr, 2 * N(n)))),
                glUniform3fv:       v((l, n, ptr) => gl.uniform3fv(get(l), arr('f32', ptr, 3 * N(n)))),
                glUniform4fv:       v((l, n, ptr) => gl.uniform4fv(get(l), arr('f32', ptr, 4 * N(n)))),
                glUniformMatrix4fv: v((l, n, transp, ptr) => gl.uniformMatrix4fv(get(l), !!N(transp), arr('f32', ptr, 16 * N(n)))),

                // Draw
                glDrawArrays:           v((m, f, c) => gl.drawArrays(N(m), N(f), N(c))),
                glDrawElements:         v((m, c, t, off) => gl.drawElements(N(m), N(c), N(t), N(off))),
                glDrawArraysInstanced:  v((m, f, c, ic) => gl.drawArraysInstanced(N(m), N(f), N(c), N(ic))),
                glDrawElementsInstanced:v((m, c, t, off, ic) => gl.drawElementsInstanced(N(m), N(c), N(t), N(off), N(ic))),

                // Query / introspection. Synthesize GLES3 pnames WebGL2 hides.
                glGetIntegerv: v((pname, ptr) => {
                    const np = N(pname);
                    let value;
                    if (np === 0x821B)        value = 3;                                    // MAJOR_VERSION
                    else if (np === 0x821C)   value = 0;                                    // MINOR_VERSION
                    else if (np === 0x821D)   value = (gl.getSupportedExtensions() || []).length;  // NUM_EXTENSIONS
                    else {
                        const r = gl.getParameter(np);
                        if (typeof r === 'number') arr('i32', ptr, 1)[0] = r;
                        else if (r && r.length) { const a = arr('i32', ptr, r.length); for (let k = 0; k < r.length; k++) a[k] = r[k]; }
                        else arr('i32', ptr, 1)[0] = 0;
                        return;
                    }
                    arr('i32', ptr, 1)[0] = value;
                }),
                glGetStringi: (pname, idx) => {
                    if (Number(pname) !== 0x1F03) return 0;  // GL_EXTENSIONS
                    const exts = gl.getSupportedExtensions() || [];
                    const i = Number(idx);
                    if (i < 0 || i >= exts.length) return 0;
                    if (!SOKOL._extBuf) {
                        SOKOL._extBuf = {};
                    }
                    if (SOKOL._extBuf[i] === undefined) {
                        const bytes = new TextEncoder().encode(exts[i] + '\0');
                        const ptr = Number(instance.exports.__wasm_alloc(BigInt(bytes.length)));
                        u8view().set(bytes, ptr);
                        SOKOL._extBuf[i] = ptr;
                    }
                    return SOKOL._extBuf[i];
                },
            };
            return wrapTable(table);
        })(),

        // Math intrinsics. Native f32/f64 signatures, no BigInt dance.
        math: {
            sin: Math.sin, cos: Math.cos, tan: Math.tan,
            sqrt: Math.sqrt, asin: Math.asin, acos: Math.acos,
            atan: Math.atan, atan2: Math.atan2,
            exp: Math.exp, log: Math.log, log2: Math.log2, log10: Math.log10,
            pow: Math.pow, fmod: (a, b) => a % b, fabs: Math.abs,
            floor: Math.floor, ceil: Math.ceil, round: Math.round,
            sinf: Math.sin, cosf: Math.cos, tanf: Math.tan,
            sqrtf: Math.sqrt, asinf: Math.asin, acosf: Math.acos,
            atanf: Math.atan, atan2f: Math.atan2,
            expf: Math.exp, logf: Math.log, powf: Math.pow,
            fmodf: (a, b) => a % b, fabsf: Math.abs,
            floorf: Math.floor, ceilf: Math.ceil, roundf: Math.round,
        },

        // Host helpers.
        sapp: {
            sapp_host_width:  () => canvas.width,
            sapp_host_height: () => canvas.height,
            // devicePixelRatio scaled by 1000 (the seam divides); sapp imports
            // return integers (BigInt) over the wasm ABI, so a fractional dpr
            // like 1.5 can't be returned directly. Used for dpi_scale so
            // sapp_width() stays the native-pixel framebuffer.
            sapp_host_dpi:    () => Math.round((window.devicePixelRatio || 1) * 1000),
            // Icon pixels from the wasm (RGBA8) become the page favicon,
            // matching sokol_app's emscripten backend.
            sapp_js_set_favicon: v((w, h, pixels) => {
                const cw = Number(w), ch = Number(h);
                const c = document.createElement('canvas');
                c.width = cw; c.height = ch;
                const g = c.getContext('2d');
                const img = g.createImageData(cw, ch);
                img.data.set(new Uint8Array(memory.buffer, Number(pixels), cw * ch * 4));
                g.putImageData(img, 0, 0);
                let link = document.getElementById('sokol-app-favicon');
                if (!link) {
                    link = document.createElement('link');
                    link.id = 'sokol-app-favicon';
                    link.rel = 'shortcut icon';
                    document.head.appendChild(link);
                }
                link.href = c.toDataURL();
            }),
            sapp_js_lock_mouse: v((lock) => {
                if (Number(lock)) {
                    const pr = canvas.requestPointerLock && canvas.requestPointerLock();
                    if (pr && pr.catch) pr.catch(() => {});
                } else if (document.pointerLockElement) {
                    document.exitPointerLock();
                }
            }),
            sapp_host_request_quit: v(()    => { quitRequested = true; }),
            sapp_host_quit_pending: () => quitRequested ? 1 : 0,
            sapp_host_log: v((ptr, len) => console.log('[sokol] ' + readString(ptr, len))),
        },

        // sokol_fetch host glue. The wasm arm of sokol_fetch.h has no
        // threads: it calls out here to start a request and we call the
        // _sfetch_emsc_* exports back when the browser answers. Bytes go
        // straight into the buffer the C side already allocated, so no
        // __wasm_alloc round-trip.
        //
        // Mirrors the EM_JS bodies in sokol_fetch.h, which are blanked
        // out of the vendored copy (scripts/blank_emjs.py) because
        // inline JS is not lexable C.
        fetch: {
            sfetch_js_send_head_request: v((slot_id, path_cstr) => {
                // u32 params of a minc export arrive as BigInt; i32/f32 are the
                // only plain-number ones
                const slot = BigInt(slot_id);
                const path = readCStr(path_cstr);
                fetch(path, { method: 'HEAD' }).then((response) => {
                    if (!response.ok) {
                        SOKOL.instance.exports.sfetch_emsc_failed_http_status(slot, BigInt(response.status));
                        return;
                    }
                    const len = response.headers.get('Content-Length');
                    // a range request needs the total size up front; without
                    // Content-Length there is nothing to chunk against
                    if (len === null) {
                        SOKOL.instance.exports.sfetch_emsc_failed_other(slot);
                    } else {
                        SOKOL.instance.exports.sfetch_emsc_head_response(slot, BigInt(len));
                    }
                }).catch((err) => {
                    console.error(`sokol_fetch: HEAD ${path} failed with: `, err);
                    SOKOL.instance.exports.sfetch_emsc_failed_other(slot);
                });
            }),

            // bytes_to_read != 0 asks for a range, otherwise the whole file
            sfetch_js_send_get_request: v((slot_id, path_cstr, offset, bytes_to_read, buf_ptr, buf_size) => {
                // u32 params of a minc export arrive as BigInt; i32/f32 are the
                // only plain-number ones
                const slot = BigInt(slot_id);
                const path = readCStr(path_cstr);
                const off = Number(offset);
                const want = Number(bytes_to_read);
                const dst = Number(buf_ptr);
                const cap = Number(buf_size);
                const headers = new Headers();
                if (want > 0) headers.append('Range', `bytes=${off}-${off + want - 1}`);
                fetch(path, { method: 'GET', headers }).then((response) => {
                    if (!response.ok) {
                        SOKOL.instance.exports.sfetch_emsc_failed_http_status(slot, BigInt(response.status));
                        return;
                    }
                    return response.arrayBuffer().then((data) => {
                        const bytes = new Uint8Array(data);
                        if (bytes.length > cap) {
                            SOKOL.instance.exports.sfetch_emsc_failed_buffer_too_small(slot);
                            return;
                        }
                        // re-read the view: the heap may have grown while the
                        // request was in flight, detaching any earlier buffer
                        new Uint8Array(memory.buffer).set(bytes, dst);
                        SOKOL.instance.exports.sfetch_emsc_get_response(slot, BigInt(want), BigInt(bytes.length));
                    });
                }).catch((err) => {
                    console.error(`sokol_fetch: GET ${path} failed with: `, err);
                    SOKOL.instance.exports.sfetch_emsc_failed_other(slot);
                });
            }),
        },

        // sokol_audio host glue.
        saudio: {
            saudio_js_init: (sample_rate, num_channels, buffer_size) => {
                const sr = Number(sample_rate);
                const nc = Number(num_channels);
                const bs = Number(buffer_size);
                if (typeof AudioContext === 'undefined') return 0;
                if (!SOKOL._saudioCtx) {
                    SOKOL._saudioCtx = new AudioContext({
                        sampleRate: sr,
                        latencyHint: 'interactive',
                    });
                }
                if (!SOKOL._saudioCtx) return 0;
                if (!SOKOL._saudioWorkletReady) {
                    console.warn('saudio: AudioWorklet module not preloaded; call SOKOL.preloadAudioWorklet() before runFromBytes');
                    return 0;
                }
                let node;
                try {
                    node = new AudioWorkletNode(SOKOL._saudioCtx, 'saudio-worklet', {
                        numberOfInputs: 0,
                        numberOfOutputs: 1,
                        outputChannelCount: [nc],
                        processorOptions: { numChannels: nc },
                    });
                } catch (e) {
                    console.error('saudio: AudioWorkletNode construction failed', e);
                    return 0;
                }
                const gain = SOKOL._saudioCtx.createGain();
                gain.gain.value = 1.0;
                node.connect(gain);
                gain.connect(SOKOL._saudioCtx.destination);
                SOKOL._saudioGain = gain;
                SOKOL._saudioNode = node;
                SOKOL._saudioBufferFrames = bs;
                SOKOL._saudioNumChannels = nc;

                // Producer with AudioContext-clock back-pressure.
                const bufferDurationS = bs / sr;
                const targetLatencyS = Math.max(0.05, 2 * bufferDurationS);
                let pushedTime = 0;
                const pullOne = () => {
                    const ptr = SOKOL.instance.exports._saudio_emsc_pull(bs);
                    if (!ptr) return false;
                    const samples = bs * nc;
                    const heap = new Float32Array(SOKOL.instance.exports.memory.buffer);
                    const base = ptr >> 2;
                    const copy = new Float32Array(samples);
                    copy.set(heap.subarray(base, base + samples));
                    SOKOL._saudioNode.port.postMessage(copy);
                    pushedTime = pushedTime + bufferDurationS;
                    return true;
                };
                const periodMs = Math.max(5, Math.floor(bufferDurationS * 1000 / 3));
                SOKOL._saudioProducer = setInterval(() => {
                    if (!SOKOL.instance || !SOKOL._saudioNode) return;
                    const ctx = SOKOL._saudioCtx;
                    if (!ctx) return;
                    if (pushedTime < ctx.currentTime) pushedTime = ctx.currentTime;
                    let n = 0;
                    while (pushedTime - ctx.currentTime < targetLatencyS && n < 8) {
                        if (!pullOne()) break;
                        n = n + 1;
                    }
                }, periodMs);

                // Resume on user gesture.
                const resume = () => {
                    const ctx = SOKOL._saudioCtx;
                    if (ctx && (ctx.state === 'suspended' || ctx.state === 'interrupted')) {
                        ctx.resume().catch(() => {});
                    }
                };
                resume();
                SOKOL._saudioCtx.onstatechange = resume;
                document.addEventListener('click', resume);
                document.addEventListener('touchend', resume);
                document.addEventListener('keydown', resume);
                return 1;
            },
            saudio_js_shutdown: v(() => {
                if (SOKOL._saudioProducer) {
                    clearInterval(SOKOL._saudioProducer);
                    SOKOL._saudioProducer = null;
                }
                if (SOKOL._saudioGain) { SOKOL._saudioGain.disconnect(); SOKOL._saudioGain = null; }
                if (SOKOL._saudioNode) { SOKOL._saudioNode.disconnect(); SOKOL._saudioNode = null; }
                if (SOKOL._saudioCtx) { SOKOL._saudioCtx.close(); SOKOL._saudioCtx = null; }
            }),
            saudio_js_sample_rate: () => (SOKOL._saudioCtx ? SOKOL._saudioCtx.sampleRate : 0),
            saudio_js_buffer_frames: () => (SOKOL._saudioBufferFrames || 0),
            saudio_js_suspended: () => {
                const ctx = SOKOL._saudioCtx;
                if (!ctx) return 0;
                return (ctx.state === 'suspended' || ctx.state === 'interrupted') ? 1 : 0;
            },
        },
    };
};

// --- DOM event delivery -------------------------------------------------
const SAPP_MOD = { SHIFT: 0x1, CTRL: 0x2, ALT: 0x4, SUPER: 0x8,
                   LMB: 0x100, RMB: 0x200, MMB: 0x400 };

function modsFromEvent(ev) {
    let m = 0;
    if (ev.shiftKey) m |= SAPP_MOD.SHIFT;
    if (ev.ctrlKey)  m |= SAPP_MOD.CTRL;
    if (ev.altKey)   m |= SAPP_MOD.ALT;
    if (ev.metaKey)  m |= SAPP_MOD.SUPER;
    if (typeof ev.buttons === 'number') {
        if (ev.buttons & 1) m |= SAPP_MOD.LMB;
        if (ev.buttons & 2) m |= SAPP_MOD.RMB;
        if (ev.buttons & 4) m |= SAPP_MOD.MMB;
    }
    return m;
}

// DOM: 0=left, 1=middle, 2=right. sokol: LEFT=0, RIGHT=1, MIDDLE=2.
function mapMouseButton(domBtn) {
    if (domBtn === 0) return 0;
    if (domBtn === 1) return 2;
    if (domBtn === 2) return 1;
    return 0x100;
}

const KEYCODE_MAP = {
    'Space': 32, 'Quote': 39, 'Comma': 44, 'Minus': 45, 'Period': 46, 'Slash': 47,
    'Digit0': 48, 'Digit1': 49, 'Digit2': 50, 'Digit3': 51, 'Digit4': 52,
    'Digit5': 53, 'Digit6': 54, 'Digit7': 55, 'Digit8': 56, 'Digit9': 57,
    'Semicolon': 59, 'Equal': 61,
    'KeyA': 65, 'KeyB': 66, 'KeyC': 67, 'KeyD': 68, 'KeyE': 69, 'KeyF': 70,
    'KeyG': 71, 'KeyH': 72, 'KeyI': 73, 'KeyJ': 74, 'KeyK': 75, 'KeyL': 76,
    'KeyM': 77, 'KeyN': 78, 'KeyO': 79, 'KeyP': 80, 'KeyQ': 81, 'KeyR': 82,
    'KeyS': 83, 'KeyT': 84, 'KeyU': 85, 'KeyV': 86, 'KeyW': 87, 'KeyX': 88,
    'KeyY': 89, 'KeyZ': 90,
    'BracketLeft': 91, 'Backslash': 92, 'BracketRight': 93, 'Backquote': 96,
    'Escape': 256, 'Enter': 257, 'Tab': 258, 'Backspace': 259,
    'Insert': 260, 'Delete': 261,
    'ArrowRight': 262, 'ArrowLeft': 263, 'ArrowDown': 264, 'ArrowUp': 265,
    'PageUp': 266, 'PageDown': 267, 'Home': 268, 'End': 269,
    'CapsLock': 280, 'ScrollLock': 281, 'NumLock': 282,
    'PrintScreen': 283, 'Pause': 284,
    'F1': 290, 'F2': 291, 'F3': 292, 'F4': 293, 'F5': 294, 'F6': 295,
    'F7': 296, 'F8': 297, 'F9': 298, 'F10': 299, 'F11': 300, 'F12': 301,
    'Numpad0': 320, 'Numpad1': 321, 'Numpad2': 322, 'Numpad3': 323,
    'Numpad4': 324, 'Numpad5': 325, 'Numpad6': 326, 'Numpad7': 327,
    'Numpad8': 328, 'Numpad9': 329,
    'NumpadDecimal': 330, 'NumpadDivide': 331, 'NumpadMultiply': 332,
    'NumpadSubtract': 333, 'NumpadAdd': 334, 'NumpadEnter': 335, 'NumpadEqual': 336,
    'ShiftLeft': 340, 'ControlLeft': 341, 'AltLeft': 342, 'MetaLeft': 343,
    'ShiftRight': 344, 'ControlRight': 345, 'AltRight': 346, 'MetaRight': 347,
    'ContextMenu': 348,
};

function mapKeyCode(code) { return KEYCODE_MAP[code] || 0; }

// CSS pixel → framebuffer pixel.
function fbX(ev) {
    const dpr = window.devicePixelRatio || 1;
    const r = canvas.getBoundingClientRect();
    return (ev.clientX - r.left) * dpr;
}
function fbY(ev) {
    const dpr = window.devicePixelRatio || 1;
    const r = canvas.getBoundingClientRect();
    return (ev.clientY - r.top) * dpr;
}

function attachEventListeners() {
    if (!instance.exports._sapp_wasm_event_mouse_move) return;

    canvas.addEventListener('mousemove', (ev) => {
        if (!instance) return;
        const dpr = window.devicePixelRatio || 1;
        instance.exports._sapp_wasm_event_mouse_move(fbX(ev), fbY(ev),
            ev.movementX * dpr, ev.movementY * dpr, BigInt(modsFromEvent(ev)));
    });
    // Pointer Lock state changes reach the wasm; a rejected request
    // (no user gesture) simply leaves the state unlocked.
    const plChange = () => {
        if (instance && instance.exports._sapp_wasm_event_mouse_locked) {
            instance.exports._sapp_wasm_event_mouse_locked(document.pointerLockElement === canvas ? 1 : 0);
        }
    };
    document.addEventListener('pointerlockchange', plChange);
    document.addEventListener('pointerlockerror', plChange);
    canvas.addEventListener('mousedown', (ev) => {
        if (!instance) return;
        instance.exports._sapp_wasm_event_mouse_button(1, mapMouseButton(ev.button), fbX(ev), fbY(ev), BigInt(modsFromEvent(ev)));
    });
    window.addEventListener('mouseup', (ev) => {
        if (!instance) return;
        instance.exports._sapp_wasm_event_mouse_button(0, mapMouseButton(ev.button), fbX(ev), fbY(ev), BigInt(modsFromEvent(ev)));
    });
    canvas.addEventListener('mouseenter', (ev) => {
        if (!instance) return;
        instance.exports._sapp_wasm_event_mouse_enter_leave(1, BigInt(modsFromEvent(ev)));
    });
    canvas.addEventListener('mouseleave', (ev) => {
        if (!instance) return;
        instance.exports._sapp_wasm_event_mouse_enter_leave(0, BigInt(modsFromEvent(ev)));
    });
    canvas.addEventListener('wheel', (ev) => {
        if (!instance) return;
        ev.preventDefault();
        const sx = -ev.deltaX / 100;
        const sy = -ev.deltaY / 100;
        instance.exports._sapp_wasm_event_mouse_scroll(sx, sy, BigInt(modsFromEvent(ev)));
    }, { passive: false });
    canvas.addEventListener('contextmenu', (ev) => {
        ev.preventDefault();
    });

    const KEYS_TO_PREVENT = new Set(['Tab', 'ArrowUp', 'ArrowDown',
        'ArrowLeft', 'ArrowRight', 'F1', 'F2', 'F3', 'F4', 'F5',
        'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12']);
    const isEditableFocused = () => {
        const t = document.activeElement;
        return t && (t.tagName === 'TEXTAREA' || t.tagName === 'INPUT'
                     || t.isContentEditable);
    };
    window.addEventListener('keydown', (ev) => {
        if (!instance || isEditableFocused()) return;
        if (KEYS_TO_PREVENT.has(ev.code)) ev.preventDefault();
        instance.exports._sapp_wasm_event_key(1, mapKeyCode(ev.code), BigInt(modsFromEvent(ev)), ev.repeat ? 1 : 0);
        if (typeof ev.key === 'string' && ev.key.length === 1) {
            const cp = ev.key.codePointAt(0);
            if (cp >= 0x20) {
                instance.exports._sapp_wasm_event_char(BigInt(cp), BigInt(modsFromEvent(ev)), ev.repeat ? 1 : 0);
            }
        }
    });
    window.addEventListener('keyup', (ev) => {
        if (!instance || isEditableFocused()) return;
        if (KEYS_TO_PREVENT.has(ev.code)) ev.preventDefault();
        instance.exports._sapp_wasm_event_key(0, mapKeyCode(ev.code), BigInt(modsFromEvent(ev)), 0);
    });
}

// --- Boot ----------------------------------------------------------------
SOKOL.runFromBytes = async function(bytes) {
    quitRequested = false;
    frameCount = 0;
    // Stop any previous run's loop before starting a new one (see rafId above).
    // Cancel before the await so a stale frame can't fire while we instantiate.
    if (rafId) { cancelAnimationFrame(rafId); rafId = 0; }
    const imports = SOKOL.makeImports();
    if (SOKOL._threadsEnv) Object.assign(imports.env, SOKOL._threadsEnv);
    const r = await WebAssembly.instantiate(bytes, imports);
    const inst = r.instance || r;  // bytes or precompiled Module input
    instance = inst;
    memory = inst.exports.memory;
    SOKOL.instance = inst;
    const dpr = window.devicePixelRatio || 1;
    canvas.width  = Math.max(1, Math.floor(canvas.clientWidth  * dpr));
    canvas.height = Math.max(1, Math.floor(canvas.clientHeight * dpr));
    if (!SOKOL._listenersAttached) {
        attachEventListeners();
        SOKOL._listenersAttached = true;
    }
    // --threads: copy the passive data segment into the shared memory,
    // first instance only; workers must never re-run it.
    if (inst.exports.__minc_init_data && !SOKOL._didInitData) {
        SOKOL._didInitData = true;
        inst.exports.__minc_init_data();
    }
    inst.exports.main();
    rafId = requestAnimationFrame(rafLoop);
};

SOKOL.run = async function(wasmPath) {
    const bytes = await fetch(wasmPath + '?t=' + Date.now()).then(r => r.arrayBuffer());
    return SOKOL.runFromBytes(bytes);
};

// --- --threads builds ----------------------------------------------------
// Dual artifacts: base.threads.wasm when the page is cross-origin
// isolated, base.wasm otherwise. Workers are pre-spawned and park on
// Atomics slots; a spinning wasm main never yields the event loop.
SOKOL.threadsAvailable = function() {
    if (new URLSearchParams(location.search).get('threads') === '0') return false;
    if (typeof crossOriginIsolated !== 'undefined' && !crossOriginIsolated) return false;
    if (typeof SharedArrayBuffer === 'undefined') return false;
    try { new WebAssembly.Memory({ initial: 1, maximum: 1, shared: true }); return true; }
    catch (e) { return false; }
};

const THREADS_WORKER = `
onmessage = async (e) => {
    const { module, memory, ctrl, ctrlOff } = e.data;
    const math = new Proxy({
        sin: Math.sin, cos: Math.cos, tan: Math.tan, sqrt: Math.sqrt,
        asin: Math.asin, acos: Math.acos, atan: Math.atan, atan2: Math.atan2,
        exp: Math.exp, log: Math.log, pow: Math.pow, fmod: (a, b) => a % b,
        fabs: Math.abs, floor: Math.floor, ceil: Math.ceil, round: Math.round,
        sinf: Math.sin, cosf: Math.cos, tanf: Math.tan, sqrtf: Math.sqrt,
        asinf: Math.asin, acosf: Math.acos, atanf: Math.atan, atan2f: Math.atan2,
        expf: Math.exp, logf: Math.log, powf: Math.pow, fmodf: (a, b) => a % b,
        fabsf: Math.abs, floorf: Math.floor, ceilf: Math.ceil, roundf: Math.round,
    }, { get: (t, k) => (k in t ? t[k] : (x) => x) });
    const env = new Proxy({ memory,
        clock: () => BigInt(Math.round(performance.now() * 1e6)),
        write: (fd, ptr, len) => len,
    }, { get: (t, k) => (k in t ? t[k] : (...a) => 0n) });
    const stubMod = new Proxy({}, { get: () => (...a) => 0n });
    const imports = new Proxy({ env, math }, { get: (t, k) => t[k] || stubMod });
    const inst = await WebAssembly.instantiate(module, imports);
    const i32v = new Int32Array(ctrl, ctrlOff, 16);
    const i64v = new BigInt64Array(ctrl, ctrlOff, 8);
    postMessage('ready');
    for (;;) {
        Atomics.wait(i32v, 0, 0);
        inst.exports.__stack_pointer.value = Number(i64v[4]);
        inst.exports.__minc_thread_entry(i64v[1], i64v[2], i64v[3]);
        if (i64v[5] && new Int32Array(memory.buffer, Number(i64v[5]), 1)[0] !== 0x7C0FFEE5)
            console.error('minc: worker stack overflow detected (canary smashed)');
        Atomics.store(i32v, 0, 0);
        Atomics.notify(i32v, 0);
    }
};`;

SOKOL._runThreads = async function(url, opts) {
    const pool = (opts && opts.pool) || 8;
    const resp = await fetch(url + '?t=' + Date.now());
    if (!resp.ok) throw new Error('HTTP ' + resp.status);
    const module = await WebAssembly.compile(await resp.arrayBuffer());
    // Import limits aren't introspectable; probe-instantiate (passive
    // segments make this side-effect-free) with growing initial sizes.
    let mem = null, lastErr = null;
    const stubMod = new Proxy({}, { get: () => (...a) => 0n });
    for (const initial of [64, 256, 1024, 4096]) {
        // 2GB maximum when the browser allows it; the wasm heap never
        // frees, so restart-heavy pages need the headroom.
        let m;
        try { m = new WebAssembly.Memory({ initial, maximum: 32768, shared: true }); }
        catch (e) { m = new WebAssembly.Memory({ initial, maximum: 16384, shared: true }); }
        const probe = new Proxy({ env: new Proxy({ memory: m },
            { get: (t, k) => (k in t ? t[k] : (...a) => 0n) }) },
            { get: (t, k) => t[k] || stubMod });
        try { await WebAssembly.instantiate(module, probe); mem = m; break; }
        catch (e) { lastErr = e; }
    }
    if (!mem) throw lastErr;

    const STACK = 2097152;
    const ctrl = new SharedArrayBuffer(pool * 64);
    const views = [];
    const ready = [];
    const blobUrl = URL.createObjectURL(new Blob([THREADS_WORKER], { type: 'text/javascript' }));
    for (let k = 0; k < pool; k++) {
        const w = new Worker(blobUrl);
        w.onerror = (e) => console.error('[sokol] pool worker:', e.message || e);
        w.postMessage({ module, memory: mem, ctrl, ctrlOff: k * 64 });
        views.push({ i32: new Int32Array(ctrl, k * 64, 16), i64: new BigInt64Array(ctrl, k * 64, 8) });
        ready.push(new Promise((res) => { w.onmessage = res; }));
    }
    await Promise.all(ready);

    SOKOL._threadsEnv = {
        memory: mem,
        __minc_cpu_count_host: () => BigInt(navigator.hardwareConcurrency || 1),
        __minc_thread_create: (entry, arg) => {
            const flag = Number(instance.exports.__wasm_alloc(16n));
            const fv = new Int32Array(mem.buffer, flag, 1);
            fv[0] = 0;
            // Bounded: spinning forever here would wedge the tab if the
            // pool is exhausted. On timeout the thread is born dead
            // (flag pre-set); the scheduler just runs with fewer
            // workers via its finish-side help-out.
            const deadline = performance.now() + 2000;
            for (;;) {
                for (let k = 0; k < pool; k++) {
                    const v = views[k];
                    if (Atomics.load(v.i32, 0) === 0) {
                        // One stack per pool slot, reused across every
                        // thread that slot ever runs; the wasm heap
                        // never frees, so per-thread stacks would leak
                        // 2MB per create (restart-heavy pages OOM'd).
                        if (!v.stack) v.stack = Number(instance.exports.__wasm_alloc(BigInt(STACK)));
                        new Int32Array(mem.buffer, v.stack, 1)[0] = 0x7C0FFEE5;  // canary
                        v.i64[1] = entry; v.i64[2] = arg; v.i64[3] = BigInt(flag);
                        v.i64[4] = BigInt((v.stack + STACK) & ~15);
                        v.i64[5] = BigInt(v.stack);
                        Atomics.store(v.i32, 0, 1);
                        Atomics.notify(v.i32, 0);
                        return BigInt(flag);
                    }
                }
                if (performance.now() > deadline) {
                    console.warn('[sokol] thread pool exhausted; thread dropped');
                    Atomics.store(fv, 0, 1);
                    return BigInt(flag);
                }
            }
        },
    };
    SOKOL.threadsActive = true;
    return SOKOL.runFromBytes(module);
};

SOKOL.runAuto = async function(base, opts) {
    if (SOKOL.threadsAvailable()) {
        try { return await SOKOL._runThreads(base + '.threads.wasm', opts); }
        catch (e) {
            console.warn('[sokol] threads boot failed, serial fallback:', e.message || e);
            SOKOL._threadsEnv = null;
            SOKOL.threadsActive = false;
        }
    }
    return SOKOL.run(base + '.wasm');
};

// --- Shader live reload --------------------------------------------------
// The host recompiles shaders in-browser and pushes translated GLSL into
// the running instance; it swaps the shader + pipeline in place on the
// next frame (lib/shader_live.mc wasm arm); no restart, app state kept.
SOKOL.hasLiveReload = function() {
    return !!(instance && instance.exports && instance.exports.__shader_live_push);
};

// name: @shader function name. ifaceHash: u64 (BigInt). glsl: translated
// source. Both buffers are allocated in the instance via __wasm_alloc;
// the wasm side takes ownership and frees them when the swap is drained.
// Returns true when the record was queued.
SOKOL.pushShader = function(name, ifaceHash, glsl) {
    if (!SOKOL.hasLiveReload()) return false;
    const enc = new TextEncoder();
    const nameBytes = enc.encode(name);
    const srcBytes = enc.encode(glsl);
    const alloc = instance.exports.__wasm_alloc;
    const namePtr = Number(alloc(BigInt(nameBytes.length)));
    const srcPtr = Number(alloc(BigInt(srcBytes.length + 1)));  // +NUL
    const mem = new Uint8Array(memory.buffer);  // after alloc → never stale
    mem.set(nameBytes, namePtr);
    mem.set(srcBytes, srcPtr);
    mem[srcPtr + srcBytes.length] = 0;
    const ok = instance.exports.__shader_live_push(
        namePtr, nameBytes.length,
        BigInt.asUintN(64, BigInt(ifaceHash)),
        srcPtr, srcBytes.length);
    return Number(ok) === 1;
};

})();
