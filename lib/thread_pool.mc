// thread_pool.mc — persistent worker pool with parallel_for
//
// Built on the thread and atomic builtins. The workers start once and
// live until tp_destroy. A dispatch is one atomic generation bump.
// Work is handed out by an atomic cursor, so uneven per-item cost
// balances itself, and the caller runs chunks too. The barrier is an
// atomic done count the caller spins on.
//
// Idle workers spin for a while, then block on a semaphore. The spin
// keeps dispatch latency low when calls come back to back, as in an
// inference loop. The block keeps the cores free when the pool sits
// idle between frames, as in a renderer. Both are tuned per pool
// through ThreadPoolDesc.
//
//
// --- API --------------------------------------------------------------
//
// void tp_init(ThreadPool* p, i32 threads);
//   Start a pool with `threads` participants, the caller included.
//   0 means cpu_count(). Every other setting takes its default.
//
// void tp_init_desc(ThreadPool* p, ThreadPoolDesc* desc);
//   Start a pool with explicit settings. A zero field means default.
//
// void parallel_for(ThreadPool* p, i64 n, fn(void*, i64, i64): void body, void* ctx);
//   Run body(ctx, start, end) over disjoint sub-ranges of [0, n) and
//   return when every index has been processed. Chunk size follows
//   desc.chunks_per_thread.
//
// void parallel_for_chunk(ThreadPool* p, i64 n, i64 chunk, fn(void*, i64, i64): void body, void* ctx);
//   Same, with an explicit chunk size. For tiles and rows, where one
//   item is already a good unit of work.
//
// void tp_destroy(ThreadPool* p);
//   Stop and join the workers, free the pool's memory.
//
// Not supported: calling parallel_for from inside a body (nested
// dispatch), and dispatching from two threads at once. Bodies may
// run on any participant, the caller included.
//
//
// --- Example ----------------------------------------------------------
//
//   struct Job { f32* out; }
//
//   void fill(void* ctx, i64 start, i64 end) {
//       Job* j = cast(Job*, ctx);
//       for i64 i = start; i < end; i++ { j.out[i] = cast(f32, i); }
//   }
//
//   i32 main() {
//       Job j = Job{ alloc<f32>(1000) };
//       ThreadPool p;
//       tp_init(&p, 0);
//       parallel_for(&p, 1000, fill, cast(void*, &j));
//       tp_destroy(&p);
//       return 0;
//   }

#include "thread.mc"
#include "atomic.mc"

// desc.spin value: workers poll forever and never block. For pools
// that dispatch back to back and own the machine.
const i32 TP_SPIN_ONLY = -1;

const i32 TP_DEFAULT_SPIN = 100000;   // polls before a worker blocks, ~0.1-0.3 ms
const i32 TP_DEFAULT_CHUNKS_PER_THREAD = 8;

struct ThreadPoolDesc {
    i32 threads;             // participants, caller included. 0 = cpu_count()
    i32 spin;                // idle polls before a worker blocks. 0 = default, TP_SPIN_ONLY = never block
    i32 chunks_per_thread;   // parallel_for chunk count per participant. 0 = 8
    bool main_idle;          // true: the caller only waits, workers do all the work
}

// One per worker thread. Padded to its own cache lines so a worker's
// sleep flag does not share a line with its neighbour's.
struct TpWorker {
    Thread thread;
    Semaphore sem;
    ThreadPool* pool;
    i32 sleeping;            // 1 while the worker may be blocked on sem
    u8[28] _pad;
}

// The fields a dispatch writes and the counters the workers hammer sit
// on separate 64-byte lines, counted from the struct start.
struct ThreadPool {
    TpWorker* workers;
    i32 nthreads;            // participants, caller included
    i32 nworkers;            // nthreads - 1
    i32 spin;
    i32 chunks_per_thread;
    bool main_idle;
    u8[7] _pad0;
    fn(void*, i64, i64): void body;
    void* ctx;
    i64 n;
    i64 chunk;

    i64 gen;                 // bumped to dispatch, workers wait on it
    u8[56] _pad1;
    i64 next;                // work cursor
    u8[56] _pad2;
    i32 done;                // workers finished with this generation
    i32 shutdown;
    u8[56] _pad3;
}

// Take chunks off the cursor until the range is used up.
void tp_run_chunks(ThreadPool* p) {
    while true {
        i64 start = atomic_add(&p.next, p.chunk, RELAXED);
        if start >= p.n { break; }
        i64 end = start + p.chunk;
        if end > p.n { end = p.n; }
        p.body(p.ctx, start, end);
    }
}

// Wait until gen moves past `last`: poll first, then block.
//
// The sleep flag and the generation form a store-then-load pair on
// both sides. With SEQ_CST on all four accesses, either the worker
// sees the new generation or the dispatcher sees the flag and signals.
// A worker that sees both leaves one signal in its semaphore, which
// the next wait consumes and loops past.
void tp_wait_gen(ThreadPool* p, TpWorker* w, i64 last) {
    while true {
        i32 polls = p.spin;
        while polls != 0 {
            if atomic_load(&p.gen, ACQUIRE) != last { return; }
            if polls > 0 { polls--; }
        }
        atomic_store(&w.sleeping, 1, SEQ_CST);
        if atomic_load(&p.gen, SEQ_CST) != last {
            atomic_store(&w.sleeping, 0, SEQ_CST);
            return;
        }
        sem_wait(&w.sem);
        atomic_store(&w.sleeping, 0, SEQ_CST);
    }
}

// Worker entry: wait for a generation, run its share, report, repeat.
void tp_worker(void* arg) {
    TpWorker* w = cast(TpWorker*, arg);
    ThreadPool* p = w.pool;
    i64 last = 0;
    while true {
        tp_wait_gen(p, w, last);
        if atomic_load(&p.shutdown, ACQUIRE) != 0 { return; }
        last = atomic_load(&p.gen, ACQUIRE);
        tp_run_chunks(p);
        atomic_add(&p.done, 1, RELEASE);
    }
}

// Signal every worker that went to sleep since the last dispatch.
void tp_wake(ThreadPool* p) {
    for i32 i = 0; i < p.nworkers; i++ {
        TpWorker* w = p.workers + i;
        if atomic_xchg(&w.sleeping, 0, SEQ_CST) != 0 { sem_signal(&w.sem); }
    }
}

void tp_init_desc(ThreadPool* p, ThreadPoolDesc* desc) {
    i32 threads = desc.threads;
    if threads <= 0 { threads = cpu_count(); }
    if threads < 1 { threads = 1; }
    p.nthreads = threads;
    p.nworkers = threads - 1;
    p.spin = desc.spin;
    if p.spin == 0 { p.spin = TP_DEFAULT_SPIN; }
    p.chunks_per_thread = desc.chunks_per_thread;
    if p.chunks_per_thread <= 0 { p.chunks_per_thread = TP_DEFAULT_CHUNKS_PER_THREAD; }
    p.main_idle = desc.main_idle;
    p.body = null;
    p.ctx = null;
    p.n = 0;
    p.chunk = 0;
    p.gen = 0;
    p.next = 0;
    p.done = 0;
    p.shutdown = 0;
    p.workers = null;
    if p.nworkers > 0 {
        p.workers = alloc<TpWorker>(p.nworkers);
        for i32 i = 0; i < p.nworkers; i++ {
            TpWorker* w = p.workers + i;
            w.pool = p;
            w.sleeping = 0;
            sem_init(&w.sem, 0);
            thread_create(&w.thread, tp_worker, cast(void*, w));
        }
    }
}

void tp_init(ThreadPool* p, i32 threads) {
    ThreadPoolDesc d;
    d.threads = threads;
    tp_init_desc(p, &d);
}

void parallel_for_chunk(ThreadPool* p, i64 n, i64 chunk, fn(void*, i64, i64): void body, void* ctx) {
    if n <= 0 { return; }
    if p.nworkers <= 0 {
        body(ctx, 0, n);
        return;
    }
    if chunk < 1 { chunk = 1; }
    p.body = body;
    p.ctx = ctx;
    p.n = n;
    p.chunk = chunk;
    atomic_store(&p.next, 0, RELAXED);
    atomic_store(&p.done, 0, RELAXED);
    atomic_add(&p.gen, 1, SEQ_CST);          // publish the job
    tp_wake(p);
    if !p.main_idle { tp_run_chunks(p); }
    while atomic_load(&p.done, ACQUIRE) < p.nworkers { }
}

void parallel_for(ThreadPool* p, i64 n, fn(void*, i64, i64): void body, void* ctx) {
    // Several chunks per participant, so uneven chunks balance without
    // the cursor becoming the bottleneck.
    i64 nchunks = cast(i64, p.nthreads) * cast(i64, p.chunks_per_thread);
    i64 chunk = (n + nchunks - 1) / nchunks;
    parallel_for_chunk(p, n, chunk, body, ctx);
}

void tp_destroy(ThreadPool* p) {
    if p.nworkers <= 0 { return; }
    atomic_store(&p.shutdown, 1, RELEASE);
    atomic_add(&p.gen, 1, SEQ_CST);          // a worker checks shutdown after every wake
    tp_wake(p);
    for i32 i = 0; i < p.nworkers; i++ {
        TpWorker* w = p.workers + i;
        thread_join(&w.thread);
        sem_destroy(&w.sem);
    }
    free(p.workers);
    p.workers = null;
    p.nworkers = 0;
}
