// fiber.mc — cooperative fibers (coroutines)
//
// All fiber_* functions below are compiler builtins. The prototypes
// are reference-only (commented out); include this file to get the
// `Fiber` struct used as the handle type.
//
// Fibers are cooperative — control passes only when a fiber calls 
// fiber_yield or returns.
//
//
// --- API --------------------------------------------------------------
//
// Fiber* fiber_create(fn(void*): void entry, void* arg);
//
//   Allocate a new fiber. `entry(arg)` runs the next time the fiber is
//   switched to. Fiber keeps running until it calls fiber_yield (which
//   returns control to the switcher) or returns (which marks the fiber
//   done).
//
// void fiber_switch(Fiber* f);
//   Resume f. Runs until f yields or completes. No-op if f is done.
//
// void fiber_yield();
//   Yield from inside a fiber back to its switcher.
//
// bool fiber_done(Fiber* f);
//   True once f's entry function has returned.
//
// void fiber_destroy(Fiber* f);
//   Free the fiber's stack and context.
//
//
// --- Example ----------------------------------------------------------
//
//   void worker(void* arg) {
//       for i32 i = 0; i < 3; i++ {
//           print("tick\n");
//           fiber_yield();
//       }
//   }
//
//   i32 main() {
//       Fiber* f = fiber_create(worker, null);
//       while !fiber_done(f) { fiber_switch(f); }
//       fiber_destroy(f);
//       return 0;
//   }

struct Fiber {
    void* ctx;
    void* stack;
    bool done;
    fn(void*): void entry;
    void* arg;
}
