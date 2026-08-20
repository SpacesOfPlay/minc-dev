// mem.mc - Memory allocators: arena (bump) and pool (fixed-size)
//

// --- Arena (bump allocator with reset) ---

struct Arena {
    u8* buf;
    i32 pos;
    i32 cap;
}

void arena_create(Arena* a, i32 size) {
    a.buf = alloc<u8>(size);
    a.pos = 0;
    a.cap = size;
    return;
}

// returns zero-filled data
void* arena_alloc_mem(Arena* a, i32 size) {
    // 8-byte alignment
    i32 aligned = (a.pos + 7) & (0 - 8);
    if aligned + size > a.cap { return null; }
    u8* ptr = a.buf + aligned;
    memset(ptr, 0, cast(i64, size));
    a.pos = aligned + size;
    return cast(void*, ptr);
}

void arena_reset(Arena* a) {
    a.pos = 0;
    return;
}

void arena_destroy(Arena* a) {
    free(a.buf);
    a.buf = null;
    a.pos = 0;
    a.cap = 0;
    return;
}


// --- Pool (fixed-size block allocator) ---

struct Pool {
    u8* buf;
    void* free_list;
    i32 block_size;
    i32 cap;
}

void pool_create(Pool* p, i32 block_size, i32 count) {
    // Minimum block size is 8 (to hold free-list pointer)
    if block_size < 8 { block_size = 8; }
    // Align block size to 8
    block_size = (block_size + 7) & (0 - 8);
    p.block_size = block_size;
    p.cap = count;
    i32 total = block_size * count;
    p.buf = alloc<u8>(total);
    memset(p.buf, 0, total);

    // Build free list (linked through first 8 bytes of each block)
    p.free_list = null;
    for i32 i = count - 1; i >= 0; i = i - 1 {
        void** block = cast(void**, p.buf + i * block_size);
        *block = p.free_list;
        p.free_list = cast(void*, block);
    }
    return;
}

void* pool_alloc(Pool* p) {
    if p.free_list == null { return null; }
    void* block = p.free_list;
    p.free_list = *cast(void**, block);
    // Zero the block
    memset(block, 0, cast(i64, p.block_size));
    return block;
}

void pool_free(Pool* p, void* ptr) {
    if ptr == null { return; }
    void** block = cast(void**, ptr);
    *block = p.free_list;
    p.free_list = cast(void*, block);
    return;
}

void pool_destroy(Pool* p) {
    free(p.buf);
    p.buf = null;
    p.free_list = null;
    p.block_size = 0;
    p.cap = 0;
    return;
}
