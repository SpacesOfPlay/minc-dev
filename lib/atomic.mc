// atomic.mc — atomic operations
//
// All atomic_* functions below are compiler builtins. The prototypes
// are reference-only (commented out); include this file to get the
// MemOrder enum used by the power-form variants. The default (seq_cst)
// forms are recognised even without including this file.

enum MemOrder {
    RELAXED,    // atomicity only, no ordering
    ACQUIRE,    // pairs with RELEASE on subsequent loads
    RELEASE,    // pairs with ACQUIRE on prior stores
    ACQ_REL,    // both — for RMW ops
    SEQ_CST,    // single global order across threads (default)
}

// --- Default form (SEQ_CST) -----------------------------------------
//
// i32  atomic_load (i32*  p);
// u32  atomic_load (u32*  p);
// i64  atomic_load (i64*  p);     
// u64  atomic_load (u64*  p);
// T*   atomic_load (T**   p);
//
// void atomic_store(i32*  p, i32  v);
// void atomic_store(u32*  p, u32  v);
// void atomic_store(i64*  p, i64  v);
// void atomic_store(u64*  p, u64  v);
// void atomic_store(T**   p, T*   v);
//
// i32  atomic_add  (i32*  p, i32  d);  
// u32  atomic_add  (u32*  p, u32  d);
// i64  atomic_add  (i64*  p, i64  d);
// u64  atomic_add  (u64*  p, u64  d);
//
// i32  atomic_sub  (i32*  p, i32  d);  ...
//
// i32  atomic_xchg (i32*  p, i32  v);  ...
//
// bool atomic_cas  (i32*  p, i32  expected, i32  new_val);
// bool atomic_cas  (u32*  p, u32  expected, u32  new_val);
// bool atomic_cas  (i64*  p, i64  expected, i64  new_val);
// bool atomic_cas  (u64*  p, u64  expected, u64  new_val);
// bool atomic_cas  (T**   p, T*   expected, T*   new_val);
//
//
// --- Explicit ordering  ---------------------------------------------
//
// i32  atomic_load (i32*  p, MemOrder ord); ...
//
// void atomic_store(i32*  p, i32  v, MemOrder ord);  ...
//
// i32  atomic_add  (i32*  p, i32  d, MemOrder ord);  ...
//
// i32  atomic_sub  (i32*  p, i32  d, MemOrder ord);  ...
//
// i32  atomic_xchg (i32*  p, i32  v, MemOrder ord);  ...
//
// bool atomic_cas     (i32* p, i32 expected, i32 new_val,
//                      MemOrder success, MemOrder failure);  ...
//
// bool atomic_cas_weak(i32* p, i32 expected, i32 new_val,
//                      MemOrder success, MemOrder failure);  ...
//
//
// --- Fence ----------------------------------------------------------
//
// void atomic_fence(MemOrder ord);
//
//
// --- Ordering constraints -------------------------------------------
//
//   atomic_load                — RELAXED, ACQUIRE, SEQ_CST
//   atomic_store               — RELAXED, RELEASE, SEQ_CST
//   atomic_{add,sub,xchg,cas}  — all five
//   atomic_cas failure ord     — RELAXED, ACQUIRE, SEQ_CST
//   atomic_fence               — ACQUIRE, RELEASE, ACQ_REL, SEQ_CST
//
// Invalid combinations are rejected at compile time.
//
