// objc_runtime.mc — Objective-C runtime bindings for macOS / iOS
//
// Call Cocoa / UIKit / Metal APIs directly from minc — no clang -ObjC
// shim required. Two capabilities:
//
//   1. Send messages to existing classes (NSApplication, NSWindow,
//      CAMetalLayer, NSEvent, …) by calling the typed `objc.msg_*`
//      fields on the dispatch table below. Pick the field whose
//      shape matches the selector's signature; for one-off shapes
//      not in the table, cast `objc.raw` at the call site.
//
//   2. Define new Obj-C classes the OS will call back into (app
//      delegates, window delegates, NSResponder subclasses) via
//      `objc_allocateClassPair` + `class_addMethod` +
//      `objc_registerClassPair`. Each method body is a regular minc
//      function whose first two parameters are
//      `void* self, void* _cmd` — the standard Obj-C IMP signature.
//
// Call objc_runtime_init() once at startup before any objc.msg_*
// dispatch. It resolves objc_msgSend / objc_msgSendSuper via dlsym
// and populates the table. The function is idempotent.
//
// On ARM64 there is a single objc_msgSend entry point (no _stret or
// _fpret variants); the runtime applies the per-shape calling
// convention from the cast type alone.
//
// --- Sending one-off shapes -----------------------------------------------
//
// For selectors whose shape isn't in the table, cast objc.raw inline:
//
//     CGFloat v = cast(fn(void*, void*): f64, objc.raw)(
//         screen, sel_registerName("backingScaleFactor"));
//
// --- Defining classes with method overrides -------------------------------
//
//     void my_window_did_resize(void* self, void* _cmd, void* note) { ... }
//
//     void* cls = objc_allocateClassPair(
//         objc_getClass("NSObject"), "MyWindowDelegate", 0);
//     class_addMethod(cls,
//         sel_registerName("windowDidResize:"),
//         cast(void*, &my_window_did_resize),
//         OBJC_ENC_v_i);
//     objc_registerClassPair(cls);
//
// --- Type-encoding cheatsheet (third arg to class_addMethod) --------------
//
//   "v@:"      -(void)method;
//   "v@:@"     -(void)method:(id)arg;          (events, notifications)
//   "v@:@@"    -(void)method:(id)a tag:(id)b;
//   "c@:"      -(BOOL)method;                  (BOOL = signed char)
//   "c@:@"     -(BOOL)method:(id)arg;          (e.g. windowShouldClose:)
//   "@@:"      -(id)method;
//   "@@:@"     -(id)method:(id)arg;
//   "q@:"      -(NSInteger)method;             (NSInteger = i64 on ARM64)
//   "q@:@"     -(NSInteger)method:(id)arg;
//   "Q@:"      -(NSUInteger)method;
//   "d@:"      -(double)method;
//
// Compose by appending arg encodings: i (i32), f (f32), * (char*),
// {CGRect=…} for structs by value, etc. The OBJC_ENC_* constants
// below cover the most common shapes.

when os(macos) || os(ios) {

// --- libobjc / libSystem extern declarations -------------------------------

extern "libSystem.B.dylib" void* dlopen(u8* path, i32 mode);
extern "libSystem.B.dylib" void* dlsym(void* handle, u8* symbol);

extern "/usr/lib/libobjc.A.dylib" void* objc_getClass(u8* name);
extern "/usr/lib/libobjc.A.dylib" void* objc_getMetaClass(u8* name);
extern "/usr/lib/libobjc.A.dylib" void* object_getClass(void* obj);
extern "/usr/lib/libobjc.A.dylib" void* sel_registerName(u8* name);
extern "/usr/lib/libobjc.A.dylib" void* objc_getProtocol(u8* name);
extern "/usr/lib/libobjc.A.dylib" void* objc_allocateClassPair(void* super, u8* name, i64 extra_bytes);
extern "/usr/lib/libobjc.A.dylib" bool class_addMethod(void* cls, void* sel, void* imp, u8* types);
extern "/usr/lib/libobjc.A.dylib" bool class_addProtocol(void* cls, void* protocol);
extern "/usr/lib/libobjc.A.dylib" void objc_registerClassPair(void* cls);
extern "/usr/lib/libobjc.A.dylib" void* class_getSuperclass(void* cls);
// objc_msgSend / objc_msgSendSuper as *linked* symbols. Declared with a
// placeholder (void*, void*) shape only so we can take their address — every
// dispatch casts objc.raw / objc.raw_super to the real per-call shape. Linking
// them (instead of dlopen+dlsym) keeps the image free of any runtime libobjc
// lookup; libobjc is already pulled in by the externs above + objc_classref.
extern "/usr/lib/libobjc.A.dylib" void* objc_msgSend(void* recv, void* sel);
extern "/usr/lib/libobjc.A.dylib" void* objc_msgSendSuper(void* sup, void* sel);

// --- super dispatch -------------------------------------------------------
//
// To call `[super foo:arg]` from inside a method override, populate
// an `objc_super` struct on the stack and dispatch through
// `objc.raw_super`:
//
//     objc_super sup;
//     sup.receiver    = self;
//     sup.super_class = class_getSuperclass(object_getClass(self));
//     cast(fn(objc_super*, void*, void*): void*, objc.raw_super)(
//         &sup, sel_registerName("foo:"), arg);
//
// The runtime walks the superclass's method list, so the override
// can chain into its parent without infinite-looping back to itself.
struct objc_super {
    void* receiver;
    void* super_class;
}

// --- Typed objc_msgSend dispatch table -------------------------------------
//
// Field naming: msg_<ret>_<args> with single-letter shorthand:
//   v = void   (return only) / no args (after self/sel)
//   i = id     (void* — any Obj-C object)
//   b = bool   (BOOL)
//   q = i64    (NSInteger / signed 64-bit)
//   Q = u64    (NSUInteger / unsigned 64-bit / NSEventMask / window-style mask)
//   I = i32
//   U = u32
//   d = f64    (CGFloat / double)
//
// So `msg_id_iq` is `-(id)method:(id)a :(NSUInteger)b;` and `msg_d_v`
// is `-(double)method;`. Pick the field whose return + args match
// the selector's signature; for any shape not listed, cast
// `objc.raw` inline at the call site.

struct ObjcMsgTable {
    void* raw;        // objc_msgSend entry point — cast inline for
                      // one-off shapes not covered by the typed fields below
    void* raw_super;  // objc_msgSendSuper — for [super …] dispatch
                      // (see the example in the file header)

    fn(void*, void*): void                                  msg_void_v;
    fn(void*, void*, void*): void                           msg_void_i;
    fn(void*, void*, void*, void*): void                    msg_void_ii;
    fn(void*, void*, void*, void*, void*): void             msg_void_iii;
    fn(void*, void*, bool): void                            msg_void_b;
    fn(void*, void*, i32): void                             msg_void_I;
    fn(void*, void*, i64): void                             msg_void_q;

    fn(void*, void*): void*                                                              msg_id_v;
    fn(void*, void*, void*): void*                                                       msg_id_i;
    fn(void*, void*, void*, void*): void*                                                msg_id_ii;
    fn(void*, void*, void*, void*, void*): void*                                         msg_id_iii;
    fn(void*, void*, void*, void*, void*, void*): void*                                  msg_id_iiii;
    fn(void*, void*, void*, void*, void*, void*, void*): void*                           msg_id_iiiii;
    fn(void*, void*, void*, void*, void*, void*, void*, void*): void*                    msg_id_iiiiii;
    fn(void*, void*, void*, void*, void*, void*, void*, void*, void*): void*             msg_id_iiiiiii;
    fn(void*, void*, void*, void*, void*, void*, void*, void*, void*, void*): void*      msg_id_iiiiiiii;
    fn(void*, void*, void*, void*, void*, void*, void*, void*, void*, void*, void*): void* msg_id_iiiiiiiii;

    // Mixed pointer / integer dispatch — selectors that take a mix
    // of object pointers and NSUInteger / NSInteger args (common
    // throughout Metal: setVertexBuffer:offset:atIndex:, etc.).
    fn(void*, void*, u64): void*                                                         msg_id_q;
    fn(void*, void*, u64, void*): void*                                                  msg_id_qi;
    fn(void*, void*, void*, u64): void*                                                  msg_id_iq;
    fn(void*, void*, u64, u64): void*                                                    msg_id_qq;
    fn(void*, void*, void*, u64, void*): void*                                           msg_id_iqi;
    fn(void*, void*, void*, u64, u64): void*                                             msg_id_iqq;
    fn(void*, void*, u64, u64, u64): void*                                               msg_id_qqq;
    fn(void*, void*, void*, u64, void*, void*): void*                                    msg_id_iqii;
    fn(void*, void*, void*, u64, u64, void*): void*                                      msg_id_iqqi;
    fn(void*, void*, void*, u64, u64, u64): void*                                        msg_id_iqqq;
    fn(void*, void*, void*, u64, u64, u64, u64): void*                                   msg_id_iqqqq;
    fn(void*, void*, void*, u64, u64, u64, u64, u64): void*                              msg_id_iqqqqq;

    fn(void*, void*): bool                                  msg_bool_v;
    fn(void*, void*, void*): bool                           msg_bool_i;
    fn(void*, void*, u64): bool                             msg_bool_q;

    fn(void*, void*): i64                                   msg_q_v;
    fn(void*, void*, void*): i64                            msg_q_i;

    fn(void*, void*): f64                                   msg_d_v;
}

ObjcMsgTable objc;

// --- Type-encoding constants -----------------------------------------------

u8* OBJC_ENC_v_v     = "v@:";       // -(void)method;
u8* OBJC_ENC_v_i     = "v@:@";      // -(void)method:(id)arg;
u8* OBJC_ENC_v_ii    = "v@:@@";     // -(void)method:(id)a tag:(id)b;
u8* OBJC_ENC_b_v     = "c@:";       // -(BOOL)method;
u8* OBJC_ENC_b_i     = "c@:@";      // -(BOOL)method:(id)arg;
u8* OBJC_ENC_i_v     = "@@:";       // -(id)method;
u8* OBJC_ENC_i_i     = "@@:@";      // -(id)method:(id)arg;
u8* OBJC_ENC_q_v     = "q@:";       // -(NSInteger)method;
u8* OBJC_ENC_d_v     = "d@:";       // -(double)method;

// --- Initialisation ---------------------------------------------------------
//
// Call once at startup before any objc.msg_* field is used.
// Subsequent calls are no-ops.

bool _objc_runtime_inited = false;

void objc_runtime_init() {
    if _objc_runtime_inited { return; }
    // Linked objc_msgSend — take its address instead of dlopen+dlsym.
    void* a = cast(void*, objc_msgSend);

    objc.raw = a;
    objc.raw_super = cast(void*, objc_msgSendSuper);

    objc.msg_void_v   = cast(fn(void*, void*): void, a);
    objc.msg_void_i   = cast(fn(void*, void*, void*): void, a);
    objc.msg_void_ii  = cast(fn(void*, void*, void*, void*): void, a);
    objc.msg_void_iii = cast(fn(void*, void*, void*, void*, void*): void, a);
    objc.msg_void_b   = cast(fn(void*, void*, bool): void, a);
    objc.msg_void_I   = cast(fn(void*, void*, i32): void, a);
    objc.msg_void_q   = cast(fn(void*, void*, i64): void, a);

    objc.msg_id_v       = cast(fn(void*, void*): void*, a);
    objc.msg_id_i       = cast(fn(void*, void*, void*): void*, a);
    objc.msg_id_ii      = cast(fn(void*, void*, void*, void*): void*, a);
    objc.msg_id_iii     = cast(fn(void*, void*, void*, void*, void*): void*, a);
    objc.msg_id_iiii    = cast(fn(void*, void*, void*, void*, void*, void*): void*, a);
    objc.msg_id_iiiii   = cast(fn(void*, void*, void*, void*, void*, void*, void*): void*, a);
    objc.msg_id_iiiiii  = cast(fn(void*, void*, void*, void*, void*, void*, void*, void*): void*, a);
    objc.msg_id_iiiiiii = cast(fn(void*, void*, void*, void*, void*, void*, void*, void*, void*): void*, a);
    objc.msg_id_iiiiiiii= cast(fn(void*, void*, void*, void*, void*, void*, void*, void*, void*, void*): void*, a);
    objc.msg_id_iiiiiiiii = cast(fn(void*, void*, void*, void*, void*, void*, void*, void*, void*, void*, void*): void*, a);

    objc.msg_id_q       = cast(fn(void*, void*, u64): void*, a);
    objc.msg_id_qi      = cast(fn(void*, void*, u64, void*): void*, a);
    objc.msg_id_iq      = cast(fn(void*, void*, void*, u64): void*, a);
    objc.msg_id_qq      = cast(fn(void*, void*, u64, u64): void*, a);
    objc.msg_id_iqi     = cast(fn(void*, void*, void*, u64, void*): void*, a);
    objc.msg_id_iqq     = cast(fn(void*, void*, void*, u64, u64): void*, a);
    objc.msg_id_qqq     = cast(fn(void*, void*, u64, u64, u64): void*, a);
    objc.msg_id_iqii    = cast(fn(void*, void*, void*, u64, void*, void*): void*, a);
    objc.msg_id_iqqi    = cast(fn(void*, void*, void*, u64, u64, void*): void*, a);
    objc.msg_id_iqqq    = cast(fn(void*, void*, void*, u64, u64, u64): void*, a);
    objc.msg_id_iqqqq   = cast(fn(void*, void*, void*, u64, u64, u64, u64): void*, a);
    objc.msg_id_iqqqqq  = cast(fn(void*, void*, void*, u64, u64, u64, u64, u64): void*, a);

    objc.msg_bool_v   = cast(fn(void*, void*): bool, a);
    objc.msg_bool_i   = cast(fn(void*, void*, void*): bool, a);
    objc.msg_bool_q   = cast(fn(void*, void*, u64): bool, a);

    objc.msg_q_v      = cast(fn(void*, void*): i64, a);
    objc.msg_q_i      = cast(fn(void*, void*, void*): i64, a);

    objc.msg_d_v      = cast(fn(void*, void*): f64, a);

    _objc_runtime_inited = true;
}

}  // when os(macos) || os(ios)
