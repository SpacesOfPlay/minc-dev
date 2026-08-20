// sokol_wgpu_host.js: the host for the sokol WebGPU backend on the web.
//
(function () {
  'use strict';
  // Expose the same surface as the GLES3 host (sokol_wasm_host.js) so the
  // shared harness (sokol_wasm_harness.html) drives either backend:
  // window.sokolWasm.{preloadAudioWorklet, preloadAssets, run}.
  const WGPU = (window.sokolWasm = {});
  window.sokolWgpu = WGPU;                       // back-compat alias
  // Audio (saudio) state, ported from the GLES3 host. The AudioWorklet
  // module loads async, but saudio_js_init is sync, so preloadAudioWorklet
  // must run before the wasm starts.
  let _saCtx = null, _saGain = null, _saNode = null, _saProducer = null;
  let _saBufFrames = 0, _saReady = false;
  WGPU.preloadAudioWorklet = async function (opts) {
    if (typeof AudioContext === 'undefined') { console.warn('preloadAudioWorklet: no AudioContext'); return; }
    if (_saReady) return;
    const ctxOpts = { latencyHint: 'interactive' };
    if (opts && opts.sampleRate) ctxOpts.sampleRate = opts.sampleRate;
    _saCtx = new AudioContext(ctxOpts);
    const url = (opts && opts.workletURL) || 'sokol_wasm_audio_worklet.js';
    try {
      await _saCtx.audioWorklet.addModule(url + '?t=' + Date.now());
      _saReady = true;
    } catch (e) { console.error('preloadAudioWorklet: addModule failed', e); _saCtx.close().catch(() => {}); _saCtx = null; }
  };
  // Asset VFS (same shape as the GLES3 host): fetch files into _vfs before
  // run(), serve them to the wasm via env open/read/close.
  const _vfs = {}, _fdMap = {};
  let _nextFd = 100;
  WGPU.preloadAssets = async function (paths) {
    if (!paths || !paths.length) return;
    await Promise.all(paths.map(async (p) => {
      try {
        const r = await fetch(p + '?t=' + Date.now());
        if (!r.ok) { console.warn(`preloadAssets: ${p} -> HTTP ${r.status}`); return; }
        _vfs[p] = new Uint8Array(await r.arrayBuffer());
      } catch (e) { console.warn(`preloadAssets: ${p} -> ${e.message}`); }
    }));
  };
  let memory = null, exp = null, device = null, queue = null, ctx = null;
  let canvasEl = null, presFormat = null, depthTex = null, depthView = null;
  let depthFormat = 'depth32float-stencil8';   // matches sokol's WGPU swapchain depth
  let quitRequested = false;
  // Re-run support: a host can run() more than once (the playground swaps apps
  // without reloading). Each run owns a generation; the prior frame loop bails
  // when it sees a newer one, and the prior device is destroyed so two devices
  // never fight over the canvas ("TextureView device doesn't match").
  let rafId = 0, runGen = 0;

  // Embedder hooks (the shell playground drives run/stop cycles):
  // onQuit fires once when a run's loop ends; stop() halts one externally.
  WGPU.onQuit = null;
  function fireQuit() { const f = WGPU.onQuit; WGPU.onQuit = null; if (f) f(); }
  // Fatal error: stop the loop and surface it. a console-only error
  // leaves a frozen canvas.
  function fatal(prefix, e) {
    if (quitRequested) return;
    quitRequested = true;
    if (rafId) { cancelAnimationFrame(rafId); rafId = 0; }
    // Include the message text; console stringifies the error object.
    console.error(prefix + ': ' + ((e && e.message) || e), e);
    const m = prefix + ': ' + ((e && e.message) || e);
    try { window.dispatchEvent(new ErrorEvent('error', { message: m, error: e })); } catch (_) {}
    fireQuit();
  }
  WGPU.stop = function () {
    quitRequested = true;
    if (rafId) { cancelAnimationFrame(rafId); rafId = 0; }
    exp = null;
  };

  // --- handle table (wasm sees small ints; JS keeps the GPU objects) ---
  const handles = [null];
  const put = (o) => { handles.push(o); return handles.length - 1; };
  const get = (h) => handles[Number(h)];

  const N = (x) => typeof x === 'bigint' ? Number(x) : x;
  const dv = () => new DataView(memory.buffer);
  const cstr = (p) => { const u = new Uint8Array(memory.buffer); let s = ''; while (u[p]) s += String.fromCharCode(u[p++]); return s; };

  // --- transminc wasm32 struct offsets (4-byte pointers; from layout dump) ---
  const OFF = {
    rpDesc:   { colorCount: 24, colorAtt: 32, depthAtt: 36 },           // WGPURenderPassDescriptor (size 48)
    colorAtt: { view: 4, depthSlice: 8, resolve: 12, loadOp: 16, storeOp: 20, clear: 24, stride: 56 },
    depthAtt: { view: 4, depthLoad: 8, depthStore: 12, depthClear: 16, depthReadOnly: 20,
                stencilLoad: 24, stencilStore: 28, stencilClear: 32, stencilReadOnly: 36 },
  };
  const LOAD = { 1: 'load', 2: 'clear' };
  const STORE = { 1: 'store', 2: 'discard' };
  // WGPUTextureFormat to WebGPU format string, full enum.
  const FMT = {
    1:'r8unorm', 2:'r8snorm', 3:'r8uint', 4:'r8sint',
    5:'r16unorm', 6:'r16snorm', 7:'r16uint', 8:'r16sint', 9:'r16float',
    10:'rg8unorm', 11:'rg8snorm', 12:'rg8uint', 13:'rg8sint',
    14:'r32float', 15:'r32uint', 16:'r32sint',
    17:'rg16unorm', 18:'rg16snorm', 19:'rg16uint', 20:'rg16sint', 21:'rg16float',
    22:'rgba8unorm', 23:'rgba8unorm-srgb', 24:'rgba8snorm', 25:'rgba8uint', 26:'rgba8sint',
    27:'bgra8unorm', 28:'bgra8unorm-srgb',
    29:'rgb10a2uint', 30:'rgb10a2unorm', 31:'rg11b10ufloat', 32:'rgb9e5ufloat',
    33:'rg32float', 34:'rg32uint', 35:'rg32sint',
    36:'rgba16unorm', 37:'rgba16snorm', 38:'rgba16uint', 39:'rgba16sint', 40:'rgba16float',
    41:'rgba32float', 42:'rgba32uint', 43:'rgba32sint',
    44:'stencil8', 45:'depth16unorm', 46:'depth24plus', 47:'depth24plus-stencil8',
    48:'depth32float', 49:'depth32float-stencil8',
    50:'bc1-rgba-unorm', 51:'bc1-rgba-unorm-srgb', 52:'bc2-rgba-unorm', 53:'bc2-rgba-unorm-srgb',
    54:'bc3-rgba-unorm', 55:'bc3-rgba-unorm-srgb', 56:'bc4-r-unorm', 57:'bc4-r-snorm',
    58:'bc5-rg-unorm', 59:'bc5-rg-snorm', 60:'bc6h-rgb-ufloat', 61:'bc6h-rgb-float',
    62:'bc7-rgba-unorm', 63:'bc7-rgba-unorm-srgb',
    64:'etc2-rgb8unorm', 65:'etc2-rgb8unorm-srgb', 66:'etc2-rgb8a1unorm', 67:'etc2-rgb8a1unorm-srgb',
    68:'etc2-rgba8unorm', 69:'etc2-rgba8unorm-srgb',
    70:'eac-r11unorm', 71:'eac-r11snorm', 72:'eac-rg11unorm', 73:'eac-rg11snorm',
    74:'astc-4x4-unorm', 75:'astc-4x4-unorm-srgb', 76:'astc-5x4-unorm', 77:'astc-5x4-unorm-srgb',
    78:'astc-5x5-unorm', 79:'astc-5x5-unorm-srgb', 80:'astc-6x5-unorm', 81:'astc-6x5-unorm-srgb',
    82:'astc-6x6-unorm', 83:'astc-6x6-unorm-srgb', 84:'astc-8x5-unorm', 85:'astc-8x5-unorm-srgb',
    86:'astc-8x6-unorm', 87:'astc-8x6-unorm-srgb', 88:'astc-8x8-unorm', 89:'astc-8x8-unorm-srgb',
    90:'astc-10x5-unorm', 91:'astc-10x5-unorm-srgb', 92:'astc-10x6-unorm', 93:'astc-10x6-unorm-srgb',
    94:'astc-10x8-unorm', 95:'astc-10x8-unorm-srgb', 96:'astc-10x10-unorm', 97:'astc-10x10-unorm-srgb',
    98:'astc-12x10-unorm', 99:'astc-12x10-unorm-srgb', 100:'astc-12x12-unorm', 101:'astc-12x12-unorm-srgb',
  };
  // texture / sampler / storage enum value -> WebGPU JS string
  const TDIM = { 1: '1d', 2: '2d', 3: '3d' };
  const VDIM = { 1: '1d', 2: '2d', 3: '2d-array', 4: 'cube', 5: 'cube-array', 6: '3d' };
  const ADDR = { 1: 'clamp-to-edge', 2: 'repeat', 3: 'mirror-repeat' };
  const FILTER = { 1: 'nearest', 2: 'linear' };
  const SAMPLETYPE = { 2: 'float', 3: 'unfilterable-float', 4: 'depth', 5: 'sint', 6: 'uint' };
  const SAMPLERBIND = { 2: 'filtering', 3: 'non-filtering', 4: 'comparison' };
  const STORAGEACCESS = { 2: 'write-only', 3: 'read-only', 4: 'read-write' };
  // WGPU enum value -> WebGPU JS string (the JS API takes strings, not the
  // numeric C enums). Values from ext/webgpu.h.
  // WGPUVertexFormat -> GPUVertexFormat. The full enum: sokol emits 28 of
  // these, and a missing one reaches createRenderPipeline as undefined
  // ("Missing required 'format' member") rather than a clear error.
  const VFMT = { 0x01: 'uint8', 0x02: 'uint8x2', 0x03: 'uint8x4',
                0x04: 'sint8', 0x05: 'sint8x2', 0x06: 'sint8x4',
                0x07: 'unorm8', 0x08: 'unorm8x2', 0x09: 'unorm8x4',
                0x0a: 'snorm8', 0x0b: 'snorm8x2', 0x0c: 'snorm8x4',
                0x0d: 'uint16', 0x0e: 'uint16x2', 0x0f: 'uint16x4',
                0x10: 'sint16', 0x11: 'sint16x2', 0x12: 'sint16x4',
                0x13: 'unorm16', 0x14: 'unorm16x2', 0x15: 'unorm16x4',
                0x16: 'snorm16', 0x17: 'snorm16x2', 0x18: 'snorm16x4',
                0x19: 'float16', 0x1a: 'float16x2', 0x1b: 'float16x4',
                0x1c: 'float32', 0x1d: 'float32x2', 0x1e: 'float32x3',
                0x1f: 'float32x4', 0x20: 'uint32', 0x21: 'uint32x2',
                0x22: 'uint32x3', 0x23: 'uint32x4', 0x24: 'sint32',
                0x25: 'sint32x2', 0x26: 'sint32x3', 0x27: 'sint32x4',
                0x28: 'unorm10-10-10-2', 0x29: 'unorm8x4-bgra' };
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
  const mapKeyCode = (code) => KEYCODE_MAP[code] || 0;
  const KEYS_TO_PREVENT = new Set(['Tab', 'ArrowUp', 'ArrowDown',
    'ArrowLeft', 'ArrowRight', 'F1', 'F2', 'F3', 'F4', 'F5',
    'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12']);
  const BLENDOP = { 1: 'add', 2: 'subtract', 3: 'reverse-subtract', 4: 'min',
                   5: 'max' };
  const BLENDFAC = { 1: 'zero', 2: 'one', 3: 'src', 4: 'one-minus-src',
                    5: 'src-alpha', 6: 'one-minus-src-alpha', 7: 'dst',
                    8: 'one-minus-dst', 9: 'dst-alpha',
                    10: 'one-minus-dst-alpha', 11: 'src-alpha-saturated',
                    12: 'constant', 13: 'one-minus-constant', 14: 'src1',
                    15: 'one-minus-src1', 16: 'src1-alpha',
                    17: 'one-minus-src1-alpha' };
  const TOPO = { 1: 'point-list', 2: 'line-list', 3: 'line-strip', 4: 'triangle-list', 5: 'triangle-strip' };
  const CULL = { 1: 'none', 2: 'front', 3: 'back' };
  const FRONT = { 1: 'ccw', 2: 'cw' };
  const STEP = { 1: 'vertex', 2: 'instance' };
  const COMPARE = { 1: 'never', 2: 'less', 3: 'equal', 4: 'less-equal', 5: 'greater',
                    6: 'not-equal', 7: 'greater-equal', 8: 'always', 0: 'always' };

  const u32 = (p) => dv().getUint32(p, true);
  const u64 = (p) => Number(dv().getBigUint64(p, true));
  // WGPUStringView at p: data ptr @0, length (u64) @8. length == SIZE_MAX
  // (WGPU_STRLEN) means NUL-terminated.
  const svStr = (p) => {
    const data = u32(p), len = u64(p + 8);
    if (len === 0) return '';
    if (len > 0x7fffffff) return cstr(data);
    // slice: TextDecoder rejects SharedArrayBuffer-backed views.
    return new TextDecoder().decode(new Uint8Array(memory.buffer, data, len).slice());
  };
  const mapState = {};   // handle(Number) -> { buf, wptr, off, size } for mappedAtCreation buffers

  // WGPULimits. Order matches webgpu.h
  const LIMITS = [
    'maxTextureDimension1D','maxTextureDimension2D','maxTextureDimension3D','maxTextureArrayLayers',
    'maxBindGroups','maxBindGroupsPlusVertexBuffers','maxBindingsPerBindGroup',
    'maxDynamicUniformBuffersPerPipelineLayout','maxDynamicStorageBuffersPerPipelineLayout',
    'maxSampledTexturesPerShaderStage','maxSamplersPerShaderStage','maxStorageBuffersPerShaderStage',
    'maxStorageTexturesPerShaderStage','maxUniformBuffersPerShaderStage',
    ['maxUniformBufferBindingSize',8],['maxStorageBufferBindingSize',8],
    'minUniformBufferOffsetAlignment','minStorageBufferOffsetAlignment','maxVertexBuffers',
    ['maxBufferSize',8],'maxVertexAttributes','maxVertexBufferArrayStride','maxInterStageShaderVariables',
    'maxColorAttachments','maxColorAttachmentBytesPerSample','maxComputeWorkgroupStorageSize',
    'maxComputeInvocationsPerWorkgroup','maxComputeWorkgroupSizeX','maxComputeWorkgroupSizeY',
    'maxComputeWorkgroupSizeZ','maxComputeWorkgroupsPerDimension','maxImmediateSize',
  ];
  const writeLimits = (p) => {
    const d = dv(); const lim = device.limits; let o = 4;          // skip nextInChain (4B ptr)
    for (const f of LIMITS) {
      const name = Array.isArray(f) ? f[0] : f, u64 = Array.isArray(f);
      if (u64) { o = (o + 7) & ~7; const v = BigInt(lim[name] ?? 0); d.setBigUint64(p + o, v, true); o += 8; }
      else     { d.setUint32(p + o, (lim[name] ?? 0) >>> 0, true); o += 4; }
    }
  };

  // Host-owned depth-stencil and MSAA color targets, recreated on canvas
  // resize or a sample-count change. Attachments of one pass share the
  // sample count.
  let sampleCount = 1;
  const ensureDepth = () => {
    const w = canvasEl.width, h = canvasEl.height;
    if (depthTex && depthTex.width === w && depthTex.height === h &&
        depthTex.sampleCount === sampleCount) return;
    if (depthTex) depthTex.destroy();
    // Must match sokol's swapchain depth format (it uses depth32float-stencil8
    // by default), so the pipeline's depthStencil.format and this attachment
    // agree. Falls back if the feature is unavailable.
    depthTex = device.createTexture({ size: [w, h], format: depthFormat,
      sampleCount, usage: GPUTextureUsage.RENDER_ATTACHMENT });
    depthView = depthTex.createView();
  };
  let msaaTex = null, msaaView = null;
  const ensureMsaa = () => {
    const w = canvasEl.width, h = canvasEl.height;
    if (msaaTex && msaaTex.width === w && msaaTex.height === h &&
        msaaTex.sampleCount === sampleCount) return;
    if (msaaTex) msaaTex.destroy();
    msaaTex = device.createTexture({ size: [w, h], format: presFormat,
      sampleCount, usage: GPUTextureUsage.RENDER_ATTACHMENT });
    msaaView = msaaTex.createView();
  };
  // Sync the drawing buffer and dispatch resize into the wasm when the
  // size actually changes; sokol's viewport and scissor come from the
  // dims stored there, and a stale width against the fresh canvas
  // texture fails WebGPU validation.
  const syncCanvasSize = () => {
    const dpr = window.devicePixelRatio || 1;
    const w = Math.max(1, Math.floor(canvasEl.clientWidth * dpr));
    const h = Math.max(1, Math.floor(canvasEl.clientHeight * dpr));
    if (canvasEl.width !== w || canvasEl.height !== h) {
      canvasEl.width = w; canvasEl.height = h;
      if (exp && exp._sapp_wasm_event_resized) exp._sapp_wasm_event_resized(w, h);
    }
  };

  // ===== import module: sapp (host helpers) =====
  const sapp = {
    sapp_host_width: () => canvasEl.width,
    sapp_host_height: () => canvasEl.height,
    sapp_host_dpi: () => Math.round((window.devicePixelRatio || 1) * 1000),
    // Icon pixels from the wasm (RGBA8) become the page favicon,
    // matching sokol_app's emscripten backend.
    sapp_js_set_favicon: (w, h, pixels) => {
      const cw = N(w), ch = N(h);
      const c = document.createElement('canvas');
      c.width = cw; c.height = ch;
      const g = c.getContext('2d');
      const img = g.createImageData(cw, ch);
      img.data.set(new Uint8Array(memory.buffer, N(pixels), cw * ch * 4));
      g.putImageData(img, 0, 0);
      let link = document.getElementById('sokol-app-favicon');
      if (!link) {
        link = document.createElement('link');
        link.id = 'sokol-app-favicon';
        link.rel = 'shortcut icon';
        document.head.appendChild(link);
      }
      link.href = c.toDataURL();
    },
    sapp_js_lock_mouse: (lock) => {
      if (N(lock)) {
        const pr = canvasEl.requestPointerLock && canvasEl.requestPointerLock();
        if (pr && pr.catch) pr.catch(() => {});
      } else if (document.pointerLockElement) {
        document.exitPointerLock();
      }
    },
    sapp_host_request_quit: () => { quitRequested = true; },
    sapp_host_quit_pending: () => quitRequested ? 1 : 0,
    sapp_host_log: (p, len) => { console.log(cstr(N(p)).slice(0, N(len))); },
  };

  // ===== import module: wgpu (the C entry points + bridge) =====
  const wgpu = {
    // bridge
    wgpu_get_device: () => put(device),
    wgpu_get_render_format: () => (presFormat === 'rgba8unorm' ? 0x16 : 0x1B),
    wgpu_get_current_view: () => put(ctx.getCurrentTexture().createView()),
    wgpu_get_depth_view: () => { ensureDepth(); return put(depthView); },
    // Set at init before the first view fetch; the ensure helpers key on it.
    wgpu_set_sample_count: (n) => { sampleCount = Math.max(1, Number(n) | 0); },
    wgpu_get_msaa_view: () => { ensureMsaa(); return put(msaaView); },

    // device
    wgpuDeviceGetQueue: () => put(queue),
    wgpuDeviceGetLimits: (_d, p) => { writeLimits(N(p)); return 1; },   // WGPUStatus_Success
    wgpuDeviceHasFeature: () => 0n,

    // resources. WGPUBufferDescriptor: usage@24 (u64, real GPUBufferUsage
    // bits), size@32 (u64), mappedAtCreation@40 (u32).
    wgpuDeviceCreateBuffer: (_d, p) => {
      p = N(p); const d = dv();
      const mapped = d.getUint32(p + 40, true) !== 0;
      const buf = device.createBuffer({
        usage: Number(d.getBigUint64(p + 24, true)),
        size: Number(d.getBigUint64(p + 32, true)),
        mappedAtCreation: mapped,
      });
      const h = put(buf);
      if (mapped) mapState[Number(h)] = { buf };
      return h;
    },
    // sokol writes immutable buffer data into the mappedAtCreation range:
    // hand it a wasm scratch buffer to write into, copy to the real mapped
    // range on Unmap.
    wgpuBufferGetMappedRange: (bufH, off, size) => {
      const st = mapState[Number(bufH)];
      const sz = N(size), wptr = Number(exp.__wasm_alloc(BigInt(sz)));   // __wasm_alloc takes i64
      if (st) { st.wptr = wptr; st.off = N(off); st.size = sz; }
      return wptr;
    },
    wgpuBufferUnmap: (bufH) => {
      const st = mapState[Number(bufH)];
      if (st && st.wptr != null) {
        new Uint8Array(st.buf.getMappedRange(st.off, st.size))
          .set(new Uint8Array(memory.buffer, st.wptr, st.size));
        st.buf.unmap();
        st.wptr = null;
      }
    },
    wgpuQueueWriteBuffer: (_q, bufH, off, dataPtr, size) =>
      queue.writeBuffer(get(bufH), N(off), memory.buffer, N(dataPtr), N(size)),

    // TextureDescriptor: usage@24(u64), dimension@32, size@36(Extent3D
    // w@36/h@40/depth@44), format@48, mipLevelCount@52, sampleCount@56.
    // GPUTextureUsage bits match WGPU's, so usage passes through.
    wgpuDeviceCreateTexture: (_d, p) => {
      p = N(p); const d = dv();
      return put(device.createTexture({
        usage: Number(d.getBigUint64(p + 24, true)),
        dimension: TDIM[u32(p + 32)] || '2d',
        size: [u32(p + 36), u32(p + 40), u32(p + 44) || 1],
        format: FMT[u32(p + 48)],
        mipLevelCount: u32(p + 52) || 1,
        sampleCount: u32(p + 56) || 1,
      }));
    },
    // TextureViewDescriptor: format@24, dimension@28, baseMipLevel@32,
    // mipLevelCount@36, baseArrayLayer@40, arrayLayerCount@44, aspect@48.
    // 0xFFFFFFFF counts mean undefined.
    wgpuTextureCreateView: (texH, p) => {
      p = N(p);
      if (!p) return put(get(texH).createView());
      const desc = {}, f = u32(p + 24), dim = u32(p + 28);
      if (f) desc.format = FMT[f];
      if (dim) desc.dimension = VDIM[dim];
      const undef = 0xFFFFFFFF;
      const bml = u32(p + 32), mlc = u32(p + 36);
      const bal = u32(p + 40), alc = u32(p + 44);
      if (bml && bml !== undef) desc.baseMipLevel = bml;
      if (mlc && mlc !== undef) desc.mipLevelCount = mlc;
      if (bal && bal !== undef) desc.baseArrayLayer = bal;
      if (alc && alc !== undef) desc.arrayLayerCount = alc;
      const aspect = u32(p + 48);
      if (aspect === 2) desc.aspect = 'stencil-only';
      else if (aspect === 3) desc.aspect = 'depth-only';
      return put(get(texH).createView(desc));
    },
    // SamplerDescriptor: addressMode U/V/W@24/28/32, mag@36, min@40,
    // mipmap@44, compare@56.
    wgpuDeviceCreateSampler: (_d, p) => {
      p = N(p);
      const desc = {
        addressModeU: ADDR[u32(p + 24)] || 'clamp-to-edge',
        addressModeV: ADDR[u32(p + 28)] || 'clamp-to-edge',
        addressModeW: ADDR[u32(p + 32)] || 'clamp-to-edge',
        magFilter: FILTER[u32(p + 36)] || 'nearest',
        minFilter: FILTER[u32(p + 40)] || 'nearest',
        mipmapFilter: FILTER[u32(p + 44)] || 'nearest',
      };
      const cmp = u32(p + 56); if (cmp) desc.compare = COMPARE[cmp];
      return put(device.createSampler(desc));
    },
    // QueueWriteTexture(queue, dest*, data*, dataSize, layout*, writeSize*).
    // dest: texture@0, mipLevel@4, origin@8(x/y/z), aspect@20 (default all).
    // layout: offset@0(u64), bytesPerRow@8, rowsPerImage@12. size: Extent3D.
    wgpuQueueWriteTexture: (_q, destP, dataPtr, dataSize, layoutP, sizeP) => {
      destP = N(destP); layoutP = N(layoutP); sizeP = N(sizeP);
      const dest = {
        texture: get(u32(destP + 0)),
        mipLevel: u32(destP + 4),
        origin: { x: u32(destP + 8), y: u32(destP + 12), z: u32(destP + 16) },
      };
      const layout = { offset: u64(layoutP + 0), bytesPerRow: u32(layoutP + 8), rowsPerImage: u32(layoutP + 12) };
      const size = [u32(sizeP + 0), u32(sizeP + 4), u32(sizeP + 8) || 1];
      queue.writeTexture(dest, new Uint8Array(memory.buffer, N(dataPtr), N(dataSize)), layout, size);
    },

    wgpuDeviceCreateShaderModule: (_d, p) => {
      p = N(p);
      const wgslPtr = u32(p + 0);            // SMD.nextInChain -> WGPUShaderSourceWGSL
      return put(device.createShaderModule({ code: svStr(wgslPtr + 8) }));   // WGSL.code @8
    },
    // BindGroupLayoutDescriptor: entryCount@24, entries@32 (WGPUBindGroupLayoutEntry[],
    // stride 88: binding@4, visibility@8(u64), buffer@24{type@28, hasDynamicOffset@32}).
    // sokol's WGPU uses dynamic-offset uniform buffers (group 0) + storage/
    // texture/sampler (group 1); handle uniform + storage buffers here.
    wgpuDeviceCreateBindGroupLayout: (_d, p) => {
      p = N(p); const n = u64(p + 24), arr = u32(p + 32), entries = [];
      for (let i = 0; i < n; i++) {
        const e = arr + i * 88;
        const binding = u32(e + 4), visibility = u64(e + 8);
        // Exactly one of buffer@24 / sampler@48 / texture@56 / storageTexture@72
        // is populated (sub-struct discriminator = its first enum field).
        const bufType = u32(e + 28);           // BufferBindingLayout.type
        const smpType = u32(e + 52);           // SamplerBindingLayout.type @48+4
        const texType = u32(e + 60);           // TextureBindingLayout.sampleType @56+4
        const simgAcc = u32(e + 76);           // StorageTextureBindingLayout.access @72+4
        if (bufType) {
          const type = bufType === 2 ? 'uniform' : (bufType === 3 ? 'storage' : 'read-only-storage');
          entries.push({ binding, visibility, buffer: { type, hasDynamicOffset: u32(e + 32) !== 0 } });
        } else if (smpType) {
          entries.push({ binding, visibility, sampler: { type: SAMPLERBIND[smpType] || 'filtering' } });
        } else if (texType) {
          entries.push({ binding, visibility, texture: {
            sampleType: SAMPLETYPE[texType] || 'float',
            viewDimension: VDIM[u32(e + 64)] || '2d',               // TextureBindingLayout.viewDimension @56+8
            multisampled: u32(e + 68) !== 0 } });                   // .multisampled @56+12
        } else if (simgAcc) {
          entries.push({ binding, visibility, storageTexture: {
            access: STORAGEACCESS[simgAcc] || 'write-only',
            format: FMT[u32(e + 80)],                                // @72+8
            viewDimension: VDIM[u32(e + 84)] || '2d' } });           // @72+12
        } else {
          console.warn('wgpu: bind-group-layout entry', binding, 'has no recognized binding kind');
        }
      }
      return put(device.createBindGroupLayout({ entries }));
    },
    // BindGroupDescriptor: layout@24, entryCount@32, entries@40
    // (WGPUBindGroupEntry[], stride 40: binding@4, buffer@8, offset@16,
    // size@24, sampler@32, textureView@36).
    wgpuDeviceCreateBindGroup: (_d, p) => {
      p = N(p); const layout = get(u32(p + 24)), n = u64(p + 32), arr = u32(p + 40), entries = [];
      for (let i = 0; i < n; i++) {
        const e = arr + i * 40;
        const binding = u32(e + 4), buf = u32(e + 8), smp = u32(e + 32), tv = u32(e + 36);
        let resource;
        if (buf) resource = { buffer: get(buf), offset: u64(e + 16), size: u64(e + 24) };
        else if (tv) resource = get(tv);
        else if (smp) resource = get(smp);
        else { console.warn('wgpu: bind-group entry', binding, 'empty'); continue; }
        entries.push({ binding, resource });
      }
      return put(device.createBindGroup({ layout, entries }));
    },
    wgpuDeviceCreatePipelineLayout: (_d, p) => {
      p = N(p); const n = u64(p + 24), arr = u32(p + 32), bgls = [];
      for (let i = 0; i < n; i++) bgls.push(get(u32(arr + i * 4)));
      return put(device.createPipelineLayout({ bindGroupLayouts: bgls }));
    },
    wgpuDeviceCreateRenderPipeline: (_d, p) => {
      p = N(p);
      // vertex @32: module@4, entryPoint(StringView)@8, bufferCount@40, buffers@48
      const vp = p + 32, buffers = [];
      const vbufN = u64(vp + 40), vbufP = u32(vp + 48);
      for (let i = 0; i < vbufN; i++) {
        const bp = vbufP + i * 32;           // WGPUVertexBufferLayout size 32
        const attN = u64(bp + 16), attP = u32(bp + 24), attributes = [];
        for (let j = 0; j < attN; j++) {
          const ap = attP + j * 24;          // WGPUVertexAttribute size 24
          attributes.push({ format: VFMT[u32(ap + 4)], offset: u64(ap + 8), shaderLocation: u32(ap + 16) });
        }
        buffers.push({ arrayStride: u64(bp + 8), stepMode: STEP[u32(bp + 4)] || 'vertex', attributes });
      }
      const desc = {
        layout: get(u32(p + 24)),
        vertex: { module: get(u32(vp + 4)), entryPoint: svStr(vp + 8), buffers },
        primitive: { topology: TOPO[u32(p + 88 + 4)] || 'triangle-list',
                     frontFace: FRONT[u32(p + 88 + 12)] || 'ccw',
                     cullMode: CULL[u32(p + 88 + 16)] || 'none' },
        multisample: { count: u32(p + 116 + 4) || 1, mask: u32(p + 116 + 8) || 0xFFFFFFFF },
      };
      const dsP = u32(p + 112);              // depthStencil ptr
      if (dsP) desc.depthStencil = {
        format: FMT[u32(dsP + 4)],
        depthWriteEnabled: u32(dsP + 8) === 1,
        depthCompare: COMPARE[u32(dsP + 12)] || 'always',
      };
      const fP = u32(p + 132);               // fragment ptr
      if (fP) {
        const tN = u64(fP + 40), tP = u32(fP + 48), targets = [];
        for (let i = 0; i < tN; i++) {
          const tp = tP + i * 24;            // WGPUColorTargetState size 24
          // WGPUColorTargetState: nextInChain@0, format@4, blend@8 (nullable
          // ptr), writeMask@16. blend was never read, so nothing ever
          // blended; ImGui's atlas is white with the glyph in alpha, so
          // text drew as solid white rectangles.
          const t = { format: FMT[u32(tp + 4)] || presFormat, writeMask: u32(tp + 16) };
          const bp = u32(tp + 8);
          if (bp) {
            // WGPUBlendState = two WGPUBlendComponent {operation, srcFactor,
            // dstFactor}, 12 bytes each: color@0, alpha@12.
            const comp = (o) => ({
              operation: BLENDOP[u32(bp + o)] || 'add',
              srcFactor: BLENDFAC[u32(bp + o + 4)] || 'one',
              dstFactor: BLENDFAC[u32(bp + o + 8)] || 'zero',
            });
            t.blend = { color: comp(0), alpha: comp(12) };
          }
          targets.push(t);
        }
        desc.fragment = { module: get(u32(fP + 4)), entryPoint: svStr(fP + 8), targets };
      }
      return put(device.createRenderPipeline(desc));
    },
    // compute. ComputePipelineDescriptor: layout@24, compute@32
    // (WGPUComputeState: module@4, entryPoint@8).
    wgpuDeviceCreateComputePipeline: (_d, p) => {
      p = N(p); const cp = p + 32;
      return put(device.createComputePipeline({
        layout: get(u32(p + 24)),
        compute: { module: get(u32(cp + 4)), entryPoint: svStr(cp + 8) },
      }));
    },
    wgpuCommandEncoderBeginComputePass: (encH, _p) => put(get(encH).beginComputePass()),
    wgpuComputePassEncoderSetPipeline: (passH, pipH) => get(passH).setPipeline(get(pipH)),
    wgpuComputePassEncoderSetBindGroup: (passH, groupIndex, bgH, dynCount, dynPtr) => {
      const bg = get(bgH);
      if (!bg) return;
      const d = dv(), n = N(dynCount), pp = N(dynPtr), offs = [];
      for (let i = 0; i < n; i++) offs.push(d.getUint32(pp + i * 4, true));
      get(passH).setBindGroup(N(groupIndex), bg, offs);
    },
    wgpuComputePassEncoderDispatchWorkgroups: (passH, x, y, z) => get(passH).dispatchWorkgroups(N(x), N(y), N(z)),
    wgpuComputePassEncoderEnd: (passH) => get(passH).end(),

    wgpuRenderPassEncoderSetPipeline: (passH, pipH) => get(passH).setPipeline(get(pipH)),
    wgpuRenderPassEncoderSetVertexBuffer: (passH, slot, bufH, off, size) =>
      get(passH).setVertexBuffer(N(slot), get(bufH), N(off), N(size)),
    wgpuRenderPassEncoderSetIndexBuffer: (passH, bufH, fmt, off, size) =>
      get(passH).setIndexBuffer(get(bufH), N(fmt) === 2 ? 'uint32' : 'uint16', N(off), N(size)),
    wgpuRenderPassEncoderDraw: (passH, vc, ic, fv, fi) => get(passH).draw(N(vc), N(ic), N(fv), N(fi)),
    wgpuRenderPassEncoderDrawIndexed: (passH, ic, inst, fi, bv, ff) =>
      get(passH).drawIndexed(N(ic), N(inst), N(fi), N(bv), N(ff)),
    wgpuRenderPassEncoderSetBindGroup: (passH, groupIndex, bgH, dynCount, dynPtr) => {
      const bg = get(bgH);
      if (!bg) return;                       // empty slot, leave unset
      const d = dv(), n = N(dynCount), pp = N(dynPtr), offs = [];
      for (let i = 0; i < n; i++) offs.push(d.getUint32(pp + i * 4, true));
      get(passH).setBindGroup(N(groupIndex), bg, offs);
    },

    // command encoder + render pass (clear path)
    wgpuDeviceCreateCommandEncoder: () => put(device.createCommandEncoder()),
    wgpuCommandEncoderBeginRenderPass: (encH, p) => {
      p = N(p); const d = dv();
      const n = Number(d.getBigInt64 ? d.getUint32(p + OFF.rpDesc.colorCount, true) : 0);
      const caBase = d.getUint32(p + OFF.rpDesc.colorAtt, true);
      const colorAttachments = [];
      for (let i = 0; i < n; i++) {
        const a = caBase + i * OFF.colorAtt.stride, o = OFF.colorAtt;
        colorAttachments.push({
          view: get(d.getUint32(a + o.view, true)),
          resolveTarget: get(d.getUint32(a + o.resolve, true)) || undefined,
          loadOp: LOAD[d.getInt32(a + o.loadOp, true)] || 'clear',
          storeOp: STORE[d.getInt32(a + o.storeOp, true)] || 'store',
          clearValue: { r: d.getFloat64(a + o.clear, true), g: d.getFloat64(a + o.clear + 8, true),
                        b: d.getFloat64(a + o.clear + 16, true), a: d.getFloat64(a + o.clear + 24, true) },
        });
      }
      const desc = { colorAttachments };
      const daPtr = d.getUint32(p + OFF.rpDesc.depthAtt, true);
      if (daPtr) {
        const o = OFF.depthAtt;
        desc.depthStencilAttachment = {
          view: get(d.getUint32(daPtr + o.view, true)),
          depthLoadOp: LOAD[d.getInt32(daPtr + o.depthLoad, true)] || 'clear',
          depthStoreOp: STORE[d.getInt32(daPtr + o.depthStore, true)] || 'store',
          depthClearValue: d.getFloat32(daPtr + o.depthClear, true),
          stencilClearValue: d.getUint32(daPtr + o.stencilClear, true),
        };
        // Pass stencil ops through as encoded; sokol sets them only when
        // the format has a stencil aspect, WebGPU rejects them otherwise.
        const da = desc.depthStencilAttachment;
        if (d.getUint32(daPtr + o.depthReadOnly, true)) {
          da.depthReadOnly = true;
          delete da.depthLoadOp; delete da.depthStoreOp; delete da.depthClearValue;
        }
        if (d.getUint32(daPtr + o.stencilReadOnly, true)) {
          da.stencilReadOnly = true;
          delete da.stencilClearValue;
        } else {
          const sLoad = LOAD[d.getInt32(daPtr + o.stencilLoad, true)];
          const sStore = STORE[d.getInt32(daPtr + o.stencilStore, true)];
          if (sLoad) da.stencilLoadOp = sLoad;
          if (sStore) da.stencilStoreOp = sStore;
          if (!sLoad && !sStore) delete da.stencilClearValue;
        }
      }
      return put(get(encH).beginRenderPass(desc));
    },
    wgpuRenderPassEncoderSetViewport: (passH, x, y, w, h, minD, maxD) =>
      get(passH).setViewport(x, y, w, h, minD, maxD),
    wgpuRenderPassEncoderSetScissorRect: (passH, x, y, w, h) =>
      get(passH).setScissorRect(N(x), N(y), N(w), N(h)),
    wgpuRenderPassEncoderEnd: (passH) => get(passH).end(),
    wgpuCommandEncoderFinish: (encH) => put(get(encH).finish()),
    wgpuQueueSubmit: (_q, count, cmdsPtr) => {
      const d = dv(); const cmds = []; cmdsPtr = N(cmdsPtr);
      for (let i = 0; i < N(count); i++) cmds.push(get(d.getUint32(cmdsPtr + i * 4, true)));
      queue.submit(cmds);
    },

    // lifetime: JS objects are GC'd; the C ref-count calls are no-ops.
    // (left to the wrap default 0n; listed here for documentation)
  };

  const wrap = (o) => new Proxy(o, { get(t, k) {
    const f = t[k];
    return (...a) => { const r = f ? f(...a) : undefined; return r === undefined ? 0n : r; };
  }});

  // Math intrinsics. Native f32/f64 signatures, no BigInt dance.
  const math = {
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
  };

  const env = wrap({
    __wasm_abort: () => { throw new Error('wasm abort'); },
    // fd 2 is stderr; sokol's logger writes there.
    write: (fd, ptr, len) => {
      const s = new TextDecoder().decode(new Uint8Array(memory.buffer, N(ptr), N(len)).slice());
      if (N(fd) === 2) { console.error(s); } else { console.log(s); }
      return BigInt(N(len));
    },
    clock: () => BigInt(Math.round(performance.now() * 1e6)),
    // VFS-backed file ops (assets fetched by preloadAssets), mirroring the
    // GLES3 host so file-loading examples (textures, etc.) work on WGPU.
    open: (pathPtr) => {
      const data = _vfs[cstr(N(pathPtr))];
      if (!data) return -1n;
      const fd = _nextFd++; _fdMap[fd] = { data, pos: 0 };
      return BigInt(fd);
    },
    read: (fd, ptr, len) => {
      const f = _fdMap[Number(fd)]; if (!f) return 0n;
      const n = Math.min(f.data.length - f.pos, N(len)); if (n <= 0) return 0n;
      new Uint8Array(memory.buffer).set(f.data.subarray(f.pos, f.pos + n), N(ptr));
      f.pos += n; return BigInt(n);
    },
    close: (fd) => { delete _fdMap[Number(fd)]; return 0n; },
    get_argc: () => 0n, get_arg: () => 0n,
  });

  // saudio module (ported from the GLES3 host): sokol_audio's web backend.
  // sokol_fetch glue: requests start here, responses call the
  // _sfetch_emsc_* exports, bytes land in the caller's buffer.
  const sfetch = wrap({
    sfetch_js_send_head_request: (slot_id, path_cstr) => {
      const slot = BigInt(slot_id);
      const path = cstr(N(path_cstr));
      fetch(path, { method: 'HEAD' }).then((response) => {
        if (!exp) return;
        if (!response.ok) {
          exp.sfetch_emsc_failed_http_status(slot, BigInt(response.status));
          return;
        }
        const len = response.headers.get('Content-Length');
        // a range request needs the total size up front; without
        // Content-Length there is nothing to chunk against
        if (len === null) exp.sfetch_emsc_failed_other(slot);
        else exp.sfetch_emsc_head_response(slot, BigInt(len));
      }).catch((err) => {
        console.error(`sokol_fetch: HEAD ${path} failed with: `, err);
        if (exp) exp.sfetch_emsc_failed_other(slot);
      });
    },
    // bytes_to_read != 0 asks for a range, otherwise the whole file
    sfetch_js_send_get_request: (slot_id, path_cstr, offset, bytes_to_read, buf_ptr, buf_size) => {
      const slot = BigInt(slot_id);
      const path = cstr(N(path_cstr));
      const off = N(offset), want = N(bytes_to_read);
      const dst = N(buf_ptr), cap = N(buf_size);
      const headers = new Headers();
      if (want > 0) headers.append('Range', `bytes=${off}-${off + want - 1}`);
      fetch(path, { method: 'GET', headers }).then((response) => {
        if (!exp) return;
        if (!response.ok) {
          exp.sfetch_emsc_failed_http_status(slot, BigInt(response.status));
          return;
        }
        return response.arrayBuffer().then((data) => {
          if (!exp) return;
          const bytes = new Uint8Array(data);
          if (bytes.length > cap) {
            exp.sfetch_emsc_failed_buffer_too_small(slot);
            return;
          }
          // re-read the view: the heap may have grown while the request
          // was in flight, detaching any earlier buffer
          new Uint8Array(memory.buffer).set(bytes, dst);
          exp.sfetch_emsc_get_response(slot, BigInt(want), BigInt(bytes.length));
        });
      }).catch((err) => {
        console.error(`sokol_fetch: GET ${path} failed with: `, err);
        if (exp) exp.sfetch_emsc_failed_other(slot);
      });
    },
  });

  // AudioWorkletNode fed by a setInterval producer that pulls mixed frames
  // from the wasm (_saudio_emsc_pull) with AudioContext-clock back-pressure.
  const saudio = wrap({
    saudio_js_init: (sample_rate, num_channels, buffer_size) => {
      const sr = N(sample_rate), nc = N(num_channels), bs = N(buffer_size);
      if (typeof AudioContext === 'undefined') return 0;
      if (!_saCtx) _saCtx = new AudioContext({ sampleRate: sr, latencyHint: 'interactive' });
      if (!_saCtx) return 0;
      if (!_saReady) { console.warn('saudio: AudioWorklet not preloaded; call preloadAudioWorklet first'); return 0; }
      let node;
      try {
        node = new AudioWorkletNode(_saCtx, 'saudio-worklet',
          { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [nc], processorOptions: { numChannels: nc } });
      } catch (e) { console.error('saudio: AudioWorkletNode failed', e); return 0; }
      const gain = _saCtx.createGain();
      gain.gain.value = 1.0; node.connect(gain); gain.connect(_saCtx.destination);
      _saGain = gain; _saNode = node; _saBufFrames = bs;

      const bufDurS = bs / sr, targetLatencyS = Math.max(0.05, 2 * bufDurS);
      let pushedTime = 0;
      const pullOne = () => {
        const ptr = exp._saudio_emsc_pull(bs); if (!ptr) return false;
        const samples = bs * nc, heap = new Float32Array(memory.buffer), base = N(ptr) >> 2;
        const copy = new Float32Array(samples); copy.set(heap.subarray(base, base + samples));
        _saNode.port.postMessage(copy); pushedTime += bufDurS; return true;
      };
      _saProducer = setInterval(() => {
        if (!_saNode || !_saCtx) return;
        if (pushedTime < _saCtx.currentTime) pushedTime = _saCtx.currentTime;
        let n = 0;
        while (pushedTime - _saCtx.currentTime < targetLatencyS && n < 8) { if (!pullOne()) break; n++; }
      }, Math.max(5, Math.floor(bufDurS * 1000 / 3)));

      const resume = () => { if (_saCtx && (_saCtx.state === 'suspended' || _saCtx.state === 'interrupted')) _saCtx.resume().catch(() => {}); };
      resume(); _saCtx.onstatechange = resume;
      document.addEventListener('click', resume);
      document.addEventListener('touchend', resume);
      document.addEventListener('keydown', resume);
      return 1;
    },
    saudio_js_shutdown: () => {
      if (_saProducer) { clearInterval(_saProducer); _saProducer = null; }
      if (_saGain) { _saGain.disconnect(); _saGain = null; }
      if (_saNode) { _saNode.disconnect(); _saNode = null; }
      if (_saCtx) { _saCtx.close().catch(() => {}); _saCtx = null; }
      _saReady = false;
    },
    saudio_js_sample_rate: () => (_saCtx ? _saCtx.sampleRate : 0),
    saudio_js_buffer_frames: () => (_saBufFrames || 0),
    saudio_js_suspended: () => (_saCtx && (_saCtx.state === 'suspended' || _saCtx.state === 'interrupted')) ? 1 : 0,
  });

  WGPU.run = async function (wasmURL) {
    if (!navigator.gpu) throw new Error('WebGPU not available (need a WebGPU-capable browser)');
    canvasEl = document.getElementById('canvas');
    if (!canvasEl) throw new Error('sokol_wgpu_host: <canvas id="canvas"> required');
    // Tear down a previous run() before starting another (see runGen above).
    const myGen = ++runGen;
    if (rafId) { cancelAnimationFrame(rafId); rafId = 0; }
    if (device) { try { device.destroy(); } catch (e) {} }
    device = null; queue = null; depthTex = null; depthView = null;
    exp = null; memory = null; quitRequested = false;
    const adapter = await navigator.gpu.requestAdapter();
    if (!adapter) throw new Error('no GPU adapter: navigator.gpu.requestAdapter() returned null. Try restarting the browser.');
    // sokol's WGPU swapchain uses depth32float-stencil8 (an optional feature);
    // enable it so the pipeline + depth attachment are valid.
    const requiredFeatures = [];
    if (adapter.features.has('depth32float-stencil8')) requiredFeatures.push('depth32float-stencil8');
    else depthFormat = 'depth24plus-stencil8';
    device = await adapter.requestDevice({ requiredFeatures });
    // Validation errors don't throw; without these the app keeps
    // submitting invalid work every frame with only console warnings.
    device.onuncapturederror = (ev) => { if (myGen === runGen) fatal('GPU error', ev.error); };
    device.lost.then((info) => {
      if (myGen === runGen && info.reason !== 'destroyed') fatal('GPU device lost', info);
    });
    queue = device.queue;
    ctx = canvasEl.getContext('webgpu');
    presFormat = navigator.gpu.getPreferredCanvasFormat();
    syncCanvasSize();
    ctx.configure({ device, format: presFormat, alphaMode: 'opaque' });
    ensureDepth();

    const res = await WebAssembly.instantiateStreaming(fetch(wasmURL),
      { env, math, sapp: wrap(sapp), wgpu: wrap(wgpu), saudio, fetch: sfetch });
    exp = res.instance.exports;
    memory = exp.memory;
    if (exp.main) exp.main();                       // sapp_run → _sapp_emsc_run (stores device)

    const loop = (ts) => {
      if (quitRequested) { fireQuit(); return; }
      if (myGen !== runGen || !exp) return;            // superseded by a newer run()
      syncCanvasSize();
      try {
        exp._sapp_wasm_frame(ts);                   // refreshes views, runs sokol frame
      } catch (e) {
        fatal('frame error', e);
        return;
      }
      rafId = requestAnimationFrame(loop);
    };
    rafId = requestAnimationFrame(loop);

    // basic input forwarding. minc's wasm ABI: i32/f32 params arrive as JS
    // numbers, u32/u64 as BigInt (unsigned widens to i64). So `modifiers`
    // (u32) is BigInt; down/button/keycode/repeat (i32) and coords (f32)
    // are plain numbers. Attached once; re-runs reuse the same canvas and
    // the handlers poke the current `exp` (null after stop()).
    if (!WGPU._listenersAttached) {
      WGPU._listenersAttached = true;
      const mods = (e) => BigInt((e.shiftKey?1:0)|(e.ctrlKey?2:0)|(e.altKey?4:0)|(e.metaKey?8:0));
      // sokol_app reports mouse position in FRAMEBUFFER pixels; offsetX/Y are
      // CSS pixels. sokol_imgui then divides by dpi_scale to get back to
      // logical, so passing CSS through leaves ImGui a factor of dpr short
      // and the hover trails the cursor on a scaled display.
      const fbX = (e) => (e.clientX - canvasEl.getBoundingClientRect().left) * (window.devicePixelRatio || 1);
      const fbY = (e) => (e.clientY - canvasEl.getBoundingClientRect().top) * (window.devicePixelRatio || 1);
      canvasEl.addEventListener('mousemove', (e) => {
        if (!exp) return;
        const dpr = window.devicePixelRatio || 1;
        exp._sapp_wasm_event_mouse_move(fbX(e), fbY(e), e.movementX * dpr, e.movementY * dpr, mods(e));
      });
      // Pointer Lock state changes reach the wasm; a rejected request
      // (no user gesture) simply leaves the state unlocked.
      const plChange = () => {
        if (exp && exp._sapp_wasm_event_mouse_locked) {
          exp._sapp_wasm_event_mouse_locked(document.pointerLockElement === canvasEl ? 1 : 0);
        }
      };
      document.addEventListener('pointerlockchange', plChange);
      document.addEventListener('pointerlockerror', plChange);
      canvasEl.addEventListener('mousedown', (e) => { if (exp) exp._sapp_wasm_event_mouse_button(1, e.button, fbX(e), fbY(e), mods(e)); });
      canvasEl.addEventListener('mouseup',   (e) => { if (exp) exp._sapp_wasm_event_mouse_button(0, e.button, fbX(e), fbY(e), mods(e)); });
      canvasEl.addEventListener('mouseenter', (e) => { if (exp) exp._sapp_wasm_event_mouse_enter_leave(1, mods(e)); });
      canvasEl.addEventListener('mouseleave', (e) => { if (exp) exp._sapp_wasm_event_mouse_enter_leave(0, mods(e)); });
      canvasEl.addEventListener('wheel', (e) => {
        if (!exp) return;
        e.preventDefault();
        exp._sapp_wasm_event_mouse_scroll(-e.deltaX / 100, -e.deltaY / 100, mods(e));
      }, { passive: false });
      canvasEl.addEventListener('contextmenu', (e) => e.preventDefault());
      // sokol keycodes are GLFW-style and keyed on KeyboardEvent.code, not the
      // legacy keyCode: an unmapped code reaches sokol as a different key.
      window.addEventListener('keydown', (e) => {
        if (!exp) return;
        if (KEYS_TO_PREVENT.has(e.code)) e.preventDefault();
        exp._sapp_wasm_event_key(1, mapKeyCode(e.code), mods(e), e.repeat ? 1 : 0);
      });
      window.addEventListener('keyup', (e) => {
        if (exp) exp._sapp_wasm_event_key(0, mapKeyCode(e.code), mods(e), 0);
      });
      // Text input: without this an ImGui text field takes no characters.
      window.addEventListener('keypress', (e) => {
        if (!exp) return;
        const cp = e.charCode || e.keyCode;
        if (cp) exp._sapp_wasm_event_char(BigInt(cp), mods(e), e.repeat ? 1 : 0);   // u32 -> BigInt
      });
    }
  };

  // Run from in-memory bytes (the shell playground compiles in-browser).
  WGPU.runFromBytes = function (bytes) {
    const blob = new Blob([bytes], { type: 'application/wasm' });
    return WGPU.run(URL.createObjectURL(blob));
  };
})();
