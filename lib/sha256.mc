// sha256.mc — SHA-256 hash (FIPS 180-4).
//
// Extracted and transpiled from cifra. cifra is public-domain (CC0),
// Joseph Birr-Pixton, https://github.com/ctz/cifra.
//
// Public API:
//   void sha256_init(Sha256Ctx* ctx);
//   void sha256_update(Sha256Ctx* ctx, void* data, u64 nbytes);
//   void sha256_final(Sha256Ctx* ctx, u8* out_32);   // writes 32 bytes
//   void sha256_oneshot(void* data, u64 nbytes, u8* out_32);
//
// Self-contained. Verified against the FIPS 180-4 test vectors.
//

struct Sha256Ctx {
    u32[8] H;
    u8[64] partial;
    u32 blocks;
    u64 npartial;
}

// ---------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------

private {

type sha256_block_fn = fn(void*, u8*): void;

u32 sha256_rotr32(u32 x, u32 n) {
    return (x >> n) | (x << (32 - n));
}

u32 sha256_read32_be(u8* buf) {
    return (cast(u32, buf[0]) << 24)
         | (cast(u32, buf[1]) << 16)
         | (cast(u32, buf[2]) << 8)
         |  cast(u32, buf[3]);
}

// cast(u8, x) truncates to the low byte, so no & 0xff is needed.
void sha256_write32_be(u32 v, u8* buf) {
    buf[0] = cast(u8, v >> 24);
    buf[1] = cast(u8, v >> 16);
    buf[2] = cast(u8, v >> 8);
    buf[3] = cast(u8, v);
}

void sha256_write64_be(u64 v, u8* buf) {
    buf[0] = cast(u8, v >> 56);
    buf[1] = cast(u8, v >> 48);
    buf[2] = cast(u8, v >> 40);
    buf[3] = cast(u8, v >> 32);
    buf[4] = cast(u8, v >> 24);
    buf[5] = cast(u8, v >> 16);
    buf[6] = cast(u8, v >> 8);
    buf[7] = cast(u8, v);
}

// SHA-256 round constants (FIPS 180-4 §4.2.2 — first 32 bits of the
// fractional parts of the cube roots of the first 64 primes).
const u32[64] sha256__K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

// SHA-256 compression function — process one 64-byte block.
void sha256_update_block(void* vctx, u8* inp) {
    Sha256Ctx* ctx = vctx;
    u32[16] W;
    u32 a = ctx.H[0];
    u32 b = ctx.H[1];
    u32 c = ctx.H[2];
    u32 d = ctx.H[3];
    u32 e = ctx.H[4];
    u32 f = ctx.H[5];
    u32 g = ctx.H[6];
    u32 h = ctx.H[7];
    u32 Wt = 0;
    u8* p = inp;
    for u64 t = 0; t < 64; t++ {
        if t < 16 {
            Wt = sha256_read32_be(p);
            W[t] = Wt;
            p = p + 4;
        } else {
            u32 w2  = W[(t - 2) % 16];
            u32 w7  = W[(t - 7) % 16];
            u32 w15 = W[(t - 15) % 16];
            u32 w16 = W[(t - 16) % 16];
            u32 s1 = sha256_rotr32(w2, 17) ^ sha256_rotr32(w2, 19) ^ (w2 >> 10);
            u32 s0 = sha256_rotr32(w15, 7) ^ sha256_rotr32(w15, 18) ^ (w15 >> 3);
            Wt = s1 + w7 + s0 + w16;
            W[t % 16] = Wt;
        }
        u32 S1 = sha256_rotr32(e, 6) ^ sha256_rotr32(e, 11) ^ sha256_rotr32(e, 25);
        u32 ch = (e & f) ^ ((~e) & g);
        u32 T1 = h + S1 + ch + sha256__K[t] + Wt;
        u32 S0 = sha256_rotr32(a, 2) ^ sha256_rotr32(a, 13) ^ sha256_rotr32(a, 22);
        u32 mj = (a & b) ^ (a & c) ^ (b & c);
        u32 T2 = S0 + mj;
        h = g;
        g = f;
        f = e;
        e = d + T1;
        d = c;
        c = b;
        b = a;
        a = T1 + T2;
    }
    ctx.H[0] = ctx.H[0] + a;
    ctx.H[1] = ctx.H[1] + b;
    ctx.H[2] = ctx.H[2] + c;
    ctx.H[3] = ctx.H[3] + d;
    ctx.H[4] = ctx.H[4] + e;
    ctx.H[5] = ctx.H[5] + f;
    ctx.H[6] = ctx.H[6] + g;
    ctx.H[7] = ctx.H[7] + h;
    ctx.blocks = ctx.blocks + 1;
}

// Generic blockwise accumulator (cifra). Buffers partial input in
// `partial[0..*npartial)`; flushes via `process(ctx, block)` for each
// full 64-byte block.
void sha256_blockwise_accumulate(u8* partial, u64* npartial, u64 nblock,
                                  void* inp, u64 nbytes,
                                  sha256_block_fn process, void* ctx) {
    u8* bufin = inp;
    if (*npartial != 0) && (nbytes != 0) {
        u64 space = nblock - *npartial;
        u64 taken = space < nbytes ? space : nbytes;
        memcpy(partial + *npartial, bufin, taken);
        bufin = bufin + taken;
        nbytes = nbytes - taken;
        *npartial = *npartial + taken;
        if *npartial == nblock {
            process(ctx, partial);
            *npartial = 0;
        }
    }
    while nbytes >= nblock {
        process(ctx, bufin);
        bufin = bufin + nblock;
        nbytes = nbytes - nblock;
    }
    while nbytes != 0 {
        u64 space = nblock - *npartial;
        u64 taken = space < nbytes ? space : nbytes;
        memcpy(partial + *npartial, bufin, taken);
        bufin = bufin + taken;
        nbytes = nbytes - taken;
        *npartial = *npartial + taken;
    }
}

// Run `process` over `nbytes` of literal byte values: first `fbyte`,
// then `nbytes-2` middle bytes, then `lbyte`. Used in final() to emit
// the standard SHA pad sequence (0x80, then zeros, then big-endian
// length).
void sha256_blockwise_acc_byte(u8* partial, u64* npartial, u64 nblock,
                                u8 byte, u64 nbytes,
                                sha256_block_fn process, void* ctx) {
    while nbytes != 0 {
        u64 start = *npartial;
        u64 left = nblock - start;
        u64 count = nbytes < left ? nbytes : left;
        memset(partial + start, byte, count);
        if start + count == nblock {
            process(ctx, partial);
            *npartial = 0;
        } else {
            *npartial = *npartial + count;
        }
        nbytes = nbytes - count;
    }
}

void sha256_blockwise_acc_pad(u8* partial, u64* npartial, u64 nblock,
                               u8 fbyte, u8 mbyte, u8 lbyte, u64 nbytes,
                               sha256_block_fn process, void* ctx) {
    if nbytes == 0 { return; }
    if nbytes == 1 {
        u8 bb = fbyte ^ lbyte;
        sha256_blockwise_accumulate(partial, npartial, nblock, &bb, 1,
                                    process, ctx);
        return;
    }
    if nbytes == 2 {
        sha256_blockwise_accumulate(partial, npartial, nblock, &fbyte, 1,
                                    process, ctx);
        sha256_blockwise_accumulate(partial, npartial, nblock, &lbyte, 1,
                                    process, ctx);
        return;
    }
    sha256_blockwise_accumulate(partial, npartial, nblock, &fbyte, 1,
                                process, ctx);
    if lbyte != mbyte {
        sha256_blockwise_acc_byte(partial, npartial, nblock,
                                  mbyte, nbytes - 2, process, ctx);
        sha256_blockwise_accumulate(partial, npartial, nblock, &lbyte, 1,
                                    process, ctx);
    } else {
        sha256_blockwise_acc_byte(partial, npartial, nblock,
                                  mbyte, nbytes - 1, process, ctx);
    }
}

} // end private

// ---------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------

void sha256_init(Sha256Ctx* ctx) {
    memset(ctx, 0, sizeof(Sha256Ctx));
    // FIPS 180-4 §5.3.3 — first 32 bits of the fractional parts of
    // the square roots of the first 8 primes.
    ctx.H[0] = 0x6a09e667;
    ctx.H[1] = 0xbb67ae85;
    ctx.H[2] = 0x3c6ef372;
    ctx.H[3] = 0xa54ff53a;
    ctx.H[4] = 0x510e527f;
    ctx.H[5] = 0x9b05688c;
    ctx.H[6] = 0x1f83d9ab;
    ctx.H[7] = 0x5be0cd19;
}

void sha256_update(Sha256Ctx* ctx, void* data, u64 nbytes) {
    sha256_blockwise_accumulate(&ctx.partial[0], &ctx.npartial, 64,
                                data, nbytes,
                                sha256_update_block, ctx);
}

void sha256_final(Sha256Ctx* ctx, u8* out_32) {
    u64 digested_bytes = ctx.blocks;
    digested_bytes = digested_bytes * 64 + ctx.npartial;
    u64 digested_bits = digested_bytes * 8;
    u64 padbytes = 64 - (digested_bytes + 8) % 64;
    sha256_blockwise_acc_pad(&ctx.partial[0], &ctx.npartial, 64,
                             0x80, 0, 0, padbytes,
                             sha256_update_block, ctx);
    u8[8] buf;
    sha256_write64_be(digested_bits, &buf[0]);
    sha256_update(ctx, &buf[0], 8);
    sha256_write32_be(ctx.H[0], out_32 + 0);
    sha256_write32_be(ctx.H[1], out_32 + 4);
    sha256_write32_be(ctx.H[2], out_32 + 8);
    sha256_write32_be(ctx.H[3], out_32 + 12);
    sha256_write32_be(ctx.H[4], out_32 + 16);
    sha256_write32_be(ctx.H[5], out_32 + 20);
    sha256_write32_be(ctx.H[6], out_32 + 24);
    sha256_write32_be(ctx.H[7], out_32 + 28);
    memset(ctx, 0, sizeof(Sha256Ctx));
}

// One-shot helper: hash `nbytes` of `data`, write 32-byte digest into
// `out_32`. Convenience wrapper around init/update/final.
void sha256_oneshot(void* data, u64 nbytes, u8* out_32) {
    Sha256Ctx ctx;
    sha256_init(&ctx);
    sha256_update(&ctx, data, nbytes);
    sha256_final(&ctx, out_32);
}
