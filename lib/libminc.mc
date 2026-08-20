// libminc.mc — embeddable minc JIT compiler.
//
// This is the load-time-linking path: libminc.dll must be present next
// to the main executable at launch. Hosts that want the compiler to be 
// optional should LoadLibrary/GetProcAddress the same exports instead.
//
// All three native platforms have in-process loaders. On macOS the
// writer rewrites the dylib name to @loader_path/libminc.dylib (next
// to the host binary.) On Linux the writer's DT_RUNPATH=$ORIGIN does
// the same for libminc.so.
//
// `minc run` additionally lets the child fall back to the library
// shipped next to the compiler (DYLD_FALLBACK_LIBRARY_PATH /
// LD_LIBRARY_PATH), so a host runs without a local copy — mirroring
// Windows, where libminc.dll resolves from the install dir on PATH.
// A binary launched by hand still needs the copy.
//

const i32 MINC_ABI_VERSION = 1;

// Imports in compiled source resolve against, in order: siblings of the
// importing file, the minc_set_root directory (<root>/lib/<name>.mc then
// <root>/<name>.mc), the host cwd (lib/ + parent walk), and lib/ next to
// the libminc library itself (+ parent walk) — so scripts reach the
// bundled stdlib with no host setup, and minc_set_root overrides.

when os(windows) {
extern "libminc.dll" {
    // lifecycle
    void* minc_create();
    void  minc_destroy(void* ctx);
    void  minc_set_root(void* ctx, u8* dir);

    // compile: takes an in-memory source code buffer. vpath sets a name 
    // used for diagnostics and is used for relative imports. 
    // returns a loaded executable module, or null on error (see minc_errors).
    void* minc_compile(void* ctx, u8* src, i32 len, u8* vpath);
    void* minc_compile_file(void* ctx, u8* path);

    // null-terminated diagnostic text of the last failed compile (empty on success). 
    // valid until the next compile.
    u8*   minc_errors(void* ctx);

    // closure of the last successful compile.
    // hash this to know when to recompile (root source excluded).
    i32   minc_closure_count(void* ctx);
    u8*   minc_closure_path(void* ctx, i32 i);

    // module: resolve an export to a callable pointer, or free the image.
    void* minc_sym(void* module, u8* name);
    void  minc_module_free(void* module);

    i32   minc_abi_version();
}
}

when os(macos) {
extern "libminc.dylib" {
    void* minc_create();
    void  minc_destroy(void* ctx);
    void  minc_set_root(void* ctx, u8* dir);

    void* minc_compile(void* ctx, u8* src, i32 len, u8* vpath);
    void* minc_compile_file(void* ctx, u8* path);

    u8*   minc_errors(void* ctx);

    i32   minc_closure_count(void* ctx);
    u8*   minc_closure_path(void* ctx, i32 i);

    void* minc_sym(void* module, u8* name);
    void  minc_module_free(void* module);

    i32   minc_abi_version();
}
}

when os(linux) {
extern "libminc.so" {
    void* minc_create();
    void  minc_destroy(void* ctx);
    void  minc_set_root(void* ctx, u8* dir);

    void* minc_compile(void* ctx, u8* src, i32 len, u8* vpath);
    void* minc_compile_file(void* ctx, u8* path);

    u8*   minc_errors(void* ctx);

    i32   minc_closure_count(void* ctx);
    u8*   minc_closure_path(void* ctx, i32 i);

    void* minc_sym(void* module, u8* name);
    void  minc_module_free(void* module);

    i32   minc_abi_version();
}
}
