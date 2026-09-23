// mem_heap.mc: the heap behind alloc, new, realloc and free.
//
// The compiler compiles this module into every wasm, Linux and Android
// program. On Windows and macOS `import mem_heap;` uses it in place of
// the C runtime allocator.
//
// A program supplies its own heap instead by defining all three:
//
//   void* __minc_alloc(i64 n)             // 16-aligned, uninitialized; null on failure
//   void  __minc_free(void* p)            // p from __minc_alloc, or null
//   void* __minc_realloc(void* p, i64 n)  // C semantics; null on failure, p intact
//
// Algorithm: two-level segregated fit (TLSF, Masmano, Ripoll, Crespo
// and Real, 2004), with quick lists for blocks up to 512 bytes in the
// style of dlmalloc's fastbins. Alloc and free run in constant time.
// Freed blocks merge with their neighbours and serve later requests of
// any size; small blocks are reused directly. Memory comes from the
// environment through __heap_grow.
//
// __minc_heap_bytes() reports the bytes obtained so far and
// __minc_heap_check() verifies the heap. Both are for tests.

const u64 MHEAP_FREE = 1;
const u64 MHEAP_PREV_FREE = 2;
const u64 MHEAP_MIN_CHUNK = 262_144;
const u64 MHEAP_MAX_SIZE = 549_755_813_888;   // 2^39; larger requests fail
const u64 MHEAP_QUICK_MAX = 512;
const i32 MHEAP_QUICK_CAP = 32;

u64 mheap_fl_bitmap;
u64[32] mheap_sl_bitmap;
u64[1024] mheap_blocks;        // [fl * 32 + sl] -> head payload address, 0 = empty
u64 mheap_pool_end;            // one past the last region, for contiguity
u64 mheap_total;               // bytes obtained from __heap_grow
u64[256] mheap_pools;          // base, length pairs for __minc_heap_check
i32 mheap_npools;
u32 mheap_lock;
u64 mheap_map_fl;              // outputs of mheap_map_insert / mheap_map_search
u64 mheap_map_sl;
u64 mheap_map_size;            // the rounded size mheap_map_search searched for
u64[32] mheap_quick;           // [size / 16 - 1] -> head, linked through the payload
i32[32] mheap_quick_n;

// --- headers -----------------------------------------------------------

private u64 mheap_hdr(u64 p) { return *cast(u64*, p - 8); }
private void mheap_set_hdr(u64 p, u64 v) { *cast(u64*, p - 8) = v; }
private u64 mheap_size(u64 p) { return mheap_hdr(p) & ~cast(u64, 15); }
private void mheap_set_size(u64 p, u64 s) { mheap_set_hdr(p, s | (mheap_hdr(p) & 3)); }
private bool mheap_is_free(u64 p) { return (mheap_hdr(p) & MHEAP_FREE) != 0; }
private bool mheap_is_prev_free(u64 p) { return (mheap_hdr(p) & MHEAP_PREV_FREE) != 0; }
private u64 mheap_prev_phys(u64 p) { return *cast(u64*, p - 16); }
private u64 mheap_next_phys(u64 p) { return p + mheap_size(p) + 16; }
private u64 mheap_next_free(u64 p) { return *cast(u64*, p); }
private u64 mheap_prev_free(u64 p) { return *cast(u64*, p + 8); }

// Record p as its successor's previous block; returns the successor.
private u64 mheap_link_next(u64 p) {
    u64 n = mheap_next_phys(p);
    *cast(u64*, n - 16) = p;
    return n;
}

private void mheap_mark_free(u64 p) {
    u64 n = mheap_link_next(p);
    mheap_set_hdr(n, mheap_hdr(n) | MHEAP_PREV_FREE);
    mheap_set_hdr(p, mheap_hdr(p) | MHEAP_FREE);
}

private void mheap_mark_used(u64 p) {
    u64 n = mheap_next_phys(p);
    mheap_set_hdr(n, mheap_hdr(n) & ~MHEAP_PREV_FREE);
    mheap_set_hdr(p, mheap_hdr(p) & ~MHEAP_FREE);
}

// --- bins ----------------------------------------------------------------

// Index of the highest set bit; x != 0.
private u64 mheap_fls(u64 x) {
    u64 hi = x >> 32;
    if hi != 0 { return 63 - cast(u64, clz(cast(i32, hi))); }
    return 31 - cast(u64, clz(cast(i32, x)));
}

// Index of the lowest set bit; x != 0.
private u64 mheap_ffs(u64 x) {
    u64 lo = x & 0xFFFFFFFF;
    if lo != 0 { return cast(u64, ctz(cast(i32, lo))); }
    return 32 + cast(u64, ctz(cast(i32, x >> 32)));
}

// Bin of a block of `size` bytes.
private void mheap_map_insert(u64 size) {
    if size < 512 {
        mheap_map_fl = 0;
        mheap_map_sl = size >> 4;
        return;
    }
    u64 f = mheap_fls(size);
    mheap_map_sl = (size >> (f - 5)) - 32;
    mheap_map_fl = f - 8;
}

// Bin to search for `size` bytes, rounded up so any block found fits.
private void mheap_map_search(u64 size) {
    u64 s = size;
    if s >= 512 {
        u64 round = (cast(u64, 1) << (mheap_fls(s) - 5)) - 1;
        s = s + round;
    }
    mheap_map_size = s;
    mheap_map_insert(s);
}

// Head block of the first non-empty bin at or above (fl, sl), or 0.
private u64 mheap_find(u64 fl, u64 sl) {
    u64 all = ~cast(u64, 0);
    u64 slmap = mheap_sl_bitmap[fl] & (all << sl);
    if slmap == 0 {
        u64 flmap = mheap_fl_bitmap & (all << (fl + 1));
        if flmap == 0 { return 0; }
        fl = mheap_ffs(flmap);
        slmap = mheap_sl_bitmap[fl];
    }
    sl = mheap_ffs(slmap);
    mheap_map_fl = fl;
    mheap_map_sl = sl;
    return mheap_blocks[fl * 32 + sl];
}

private void mheap_remove(u64 p, u64 fl, u64 sl) {
    u64 prev = mheap_prev_free(p);
    u64 next = mheap_next_free(p);
    if next != 0 { *cast(u64*, next + 8) = prev; }
    if prev != 0 { *cast(u64*, prev) = next; }
    u64 idx = fl * 32 + sl;
    if mheap_blocks[idx] == p {
        mheap_blocks[idx] = next;
        if next == 0 {
            mheap_sl_bitmap[fl] = mheap_sl_bitmap[fl] & ~(cast(u64, 1) << sl);
            if mheap_sl_bitmap[fl] == 0 {
                mheap_fl_bitmap = mheap_fl_bitmap & ~(cast(u64, 1) << fl);
            }
        }
    }
}

private void mheap_insert(u64 p, u64 fl, u64 sl) {
    u64 idx = fl * 32 + sl;
    u64 head = mheap_blocks[idx];
    *cast(u64*, p) = head;
    *cast(u64*, p + 8) = 0;
    if head != 0 { *cast(u64*, head + 8) = p; }
    mheap_blocks[idx] = p;
    mheap_fl_bitmap = mheap_fl_bitmap | (cast(u64, 1) << fl);
    mheap_sl_bitmap[fl] = mheap_sl_bitmap[fl] | (cast(u64, 1) << sl);
}

private void mheap_block_insert(u64 p) {
    mheap_map_insert(mheap_size(p));
    mheap_insert(p, mheap_map_fl, mheap_map_sl);
}

private void mheap_block_remove(u64 p) {
    mheap_map_insert(mheap_size(p));
    mheap_remove(p, mheap_map_fl, mheap_map_sl);
}

// --- split and merge -----------------------------------------------------

private bool mheap_can_split(u64 p, u64 size) { return mheap_size(p) >= size + 32; }

// Cut p down to `size`; the remainder becomes a free block, returned.
private u64 mheap_split(u64 p, u64 size) {
    u64 rem = p + size + 16;
    mheap_set_hdr(rem, mheap_size(p) - size - 16);
    mheap_set_size(p, size);
    mheap_mark_free(rem);
    return rem;
}

private u64 mheap_merge_next(u64 p) {
    u64 n = mheap_next_phys(p);
    if mheap_is_free(n) {
        mheap_block_remove(n);
        mheap_set_size(p, mheap_size(p) + mheap_size(n) + 16);
        mheap_link_next(p);
    }
    return p;
}

private u64 mheap_merge_prev(u64 p) {
    if mheap_is_prev_free(p) {
        u64 prev = mheap_prev_phys(p);
        mheap_block_remove(prev);
        mheap_set_size(prev, mheap_size(prev) + mheap_size(p) + 16);
        mheap_link_next(prev);
        return prev;
    }
    return p;
}

// p is free and off the lists: keep `size`, bin the rest.
private void mheap_trim_free(u64 p, u64 size) {
    if mheap_can_split(p, size) {
        u64 rem = mheap_split(p, size);
        mheap_link_next(p);
        mheap_set_hdr(rem, mheap_hdr(rem) | MHEAP_PREV_FREE);
        mheap_block_insert(rem);
    }
}

// p is in use: give back its tail beyond `size`.
private void mheap_trim_used(u64 p, u64 size) {
    if mheap_can_split(p, size) {
        u64 rem = mheap_split(p, size);
        rem = mheap_merge_next(rem);
        mheap_block_insert(rem);
    }
}

// --- regions -------------------------------------------------------------

// Fetch a region big enough for a block of `need` bytes and bin it.
private bool mheap_grow(u64 need) {
    u64 chunk = need + 48;
    u64 min = MHEAP_MIN_CHUNK;
    if mheap_total >> 2 > min { min = mheap_total >> 2; }
    if chunk < min { chunk = min; }
    chunk = (chunk + 65535) & ~cast(u64, 65535);
    u64 base = cast(u64, __heap_grow(cast(i64, chunk)));
    if base == 0 { return false; }
    mheap_total = mheap_total + chunk;
    u64 p;
    bool recorded = mheap_npools > 0 && mheap_npools <= 128
        && mheap_pools[(mheap_npools - 1) * 2] + mheap_pools[(mheap_npools - 1) * 2 + 1] == mheap_pool_end;
    if base == mheap_pool_end && mheap_npools > 0 {
        // Contiguous with the last region: the two merge.
        p = base;
        mheap_set_hdr(p, (chunk - 16) | (mheap_hdr(p) & MHEAP_PREV_FREE));
        if recorded { mheap_pools[(mheap_npools - 1) * 2 + 1] = mheap_pools[(mheap_npools - 1) * 2 + 1] + chunk; }
    } else {
        p = base + 16;
        mheap_set_hdr(p, chunk - 32);
        if mheap_npools < 128 {
            mheap_pools[mheap_npools * 2] = base;
            mheap_pools[mheap_npools * 2 + 1] = chunk;
        }
        mheap_npools = mheap_npools + 1;
    }
    // Sentinel: a zero-size used block in the region's last 16 bytes.
    mheap_set_hdr(base + chunk, 0);
    mheap_mark_free(p);
    p = mheap_merge_prev(p);
    mheap_block_insert(p);
    mheap_pool_end = base + chunk;
    return true;
}

// --- the allocator -------------------------------------------------------

private void mheap_acquire() {
    while atomic_xchg(&mheap_lock, 1) != 0 { cpu_pause(); }
}

private void mheap_release() {
    atomic_store(&mheap_lock, 0);
}

// Payload size for a request of n bytes; 0 when the request is invalid.
private u64 mheap_adjust(i64 n) {
    if n < 0 { return 0; }
    u64 s = cast(u64, n);
    if s < 16 { return 16; }
    s = (s + 15) & ~cast(u64, 15);
    if s >= MHEAP_MAX_SIZE { return 0; }
    return s;
}

private void mheap_free_locked(u64 p) {
    mheap_mark_free(p);
    p = mheap_merge_prev(p);
    p = mheap_merge_next(p);
    mheap_block_insert(p);
}

// Return every quick-listed block to the bins, where it can merge.
private void mheap_quick_flush() {
    for i32 qi = 0; qi < 32; qi++ {
        u64 q = mheap_quick[qi];
        while q != 0 {
            u64 nx = *cast(u64*, q);
            mheap_free_locked(q);
            q = nx;
        }
        mheap_quick[qi] = 0;
        mheap_quick_n[qi] = 0;
    }
}

private u64 mheap_alloc_locked(u64 size) {
    mheap_map_search(size);
    u64 p = mheap_find(mheap_map_fl, mheap_map_sl);
    if p == 0 {
        mheap_quick_flush();
        mheap_map_search(size);
        p = mheap_find(mheap_map_fl, mheap_map_sl);
    }
    if p == 0 {
        if !mheap_grow(mheap_map_size) { return 0; }
        mheap_map_search(size);
        p = mheap_find(mheap_map_fl, mheap_map_sl);
        if p == 0 { return 0; }
    }
    mheap_remove(p, mheap_map_fl, mheap_map_sl);
    mheap_trim_free(p, size);
    mheap_mark_used(p);
    return p;
}

void* __minc_alloc(i64 n) {
    u64 size = mheap_adjust(n);
    if size == 0 { return null; }
    mheap_acquire();
    if size <= MHEAP_QUICK_MAX {
        i32 qi = cast(i32, size >> 4) - 1;
        u64 q = mheap_quick[qi];
        if q != 0 {
            mheap_quick[qi] = *cast(u64*, q);
            mheap_quick_n[qi] = mheap_quick_n[qi] - 1;
            mheap_release();
            return cast(void*, q);
        }
    }
    u64 p = mheap_alloc_locked(size);
    mheap_release();
    return cast(void*, p);
}

void __minc_free(void* ptr) {
    if ptr == null { return; }
    u64 p = cast(u64, ptr);
    mheap_acquire();
    u64 size = mheap_size(p);
    if size <= MHEAP_QUICK_MAX {
        i32 qi = cast(i32, size >> 4) - 1;
        if mheap_quick_n[qi] < MHEAP_QUICK_CAP {
            *cast(u64*, p) = mheap_quick[qi];
            mheap_quick[qi] = p;
            mheap_quick_n[qi] = mheap_quick_n[qi] + 1;
            mheap_release();
            return;
        }
    }
    mheap_free_locked(p);
    mheap_release();
}

void* __minc_realloc(void* ptr, i64 n) {
    if ptr == null { return __minc_alloc(n); }
    if n == 0 {
        __minc_free(ptr);
        return null;
    }
    u64 size = mheap_adjust(n);
    if size == 0 { return null; }
    u64 p = cast(u64, ptr);
    mheap_acquire();
    u64 cur = mheap_size(p);
    if size <= cur {
        mheap_trim_used(p, size);
        mheap_release();
        return ptr;
    }
    u64 next = mheap_next_phys(p);
    if mheap_is_free(next) && cur + mheap_size(next) + 16 >= size {
        mheap_merge_next(p);
        mheap_mark_used(p);
        mheap_trim_used(p, size);
        mheap_release();
        return ptr;
    }
    mheap_release();
    void* q = __minc_alloc(n);
    if q == null { return null; }
    memcpy(q, ptr, cast(i64, cur));
    __minc_free(ptr);
    return q;
}

// --- introspection -------------------------------------------------------

// Bytes obtained from the environment so far.
i64 __minc_heap_bytes() { return cast(i64, mheap_total); }

// 0 when the heap is consistent, otherwise a code for the first violation.
i32 __minc_heap_check() {
    mheap_acquire();
    i32 rc = 0;
    u64 free_walk = 0;
    i32 npools = mheap_npools;
    if npools > 128 { npools = 128; }
    for i32 i = 0; i < npools && rc == 0; i++ {
        u64 base = mheap_pools[i * 2];
        u64 end = base + mheap_pools[i * 2 + 1];
        u64 p = base + 16;
        bool prev_free = false;
        u64 prev = 0;
        while rc == 0 {
            u64 size = mheap_size(p);
            if (mheap_hdr(p) & 12) != 0 { rc = 1; break; }
            if mheap_is_prev_free(p) != prev_free { rc = 2; break; }
            if prev_free && mheap_prev_phys(p) != prev { rc = 3; break; }
            if size == 0 {
                if p != end { rc = 4; }
                break;
            }
            if (size & 15) != 0 || size < 16 { rc = 5; break; }
            if p + size + 16 > end { rc = 6; break; }
            if mheap_is_free(p) {
                if prev_free { rc = 7; break; }
                free_walk = free_walk + 1;
            }
            prev_free = mheap_is_free(p);
            prev = p;
            p = p + size + 16;
        }
    }
    u64 free_listed = 0;
    if rc == 0 {
        for i32 b = 0; b < 1024 && rc == 0; b++ {
            u64 q = mheap_blocks[b];
            while q != 0 {
                if !mheap_is_free(q) { rc = 8; break; }
                mheap_map_insert(mheap_size(q));
                if mheap_map_fl * 32 + mheap_map_sl != cast(u64, b) { rc = 9; break; }
                free_listed = free_listed + 1;
                q = mheap_next_free(q);
            }
        }
    }
    if rc == 0 && mheap_npools <= 128 && free_listed != free_walk { rc = 10; }
    mheap_release();
    return rc;
}
