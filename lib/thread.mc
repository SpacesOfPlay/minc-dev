// thread.mc — threading primitives (compiler builtins)
//
// All functions below are compiler builtins; the prototypes are
// reference-only (commented out). Include this file to get the type
// definitions used by the builtins.

struct Thread {
    i64 handle;   // Windows HANDLE / Linux tid / macOS pthread_t
}

struct Mutex {
    u8[64] opaque;
}

struct Semaphore {
    i64 handle;       // Windows HANDLE / macOS dispatch_semaphore_t
    i32 count;        // Linux: count, guarded by `guard`
    i32 _pad;
    u8[64] guard;     // Linux: Mutex backing. Unused on other platforms.
}

// --- Threads --------------------------------------------------------
//
// void thread_create(Thread* t, fn(void*): void entry, void* arg);
// void thread_join(Thread* t);
// void thread_sleep(i32 ms);
//  i32 cpu_count();
//
// --- Mutex ----------------------------------------------------------
//
// void mutex_init(Mutex* m);
// void mutex_lock(Mutex* m);
// void mutex_unlock(Mutex* m);
// void mutex_destroy(Mutex* m);
//
// --- Semaphore ------------------------------------------------------
//
// void sem_init(Semaphore* s, i32 initial);
// void sem_signal(Semaphore* s);
// void sem_wait(Semaphore* s);
// void sem_destroy(Semaphore* s);
