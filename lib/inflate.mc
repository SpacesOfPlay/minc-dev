// inflate.mc - DEFLATE decompressor (port of puff.c by Mark Adler)
// Reference: RFC 1951 (DEFLATE Compressed Data Format)

// Error codes
// 0  = success
// -1 = input exhausted
// -2 = invalid stored block length
// -3 = too many length/distance codes
// -4 = code lengths don't form valid table
// -5 = invalid fixed code set (should not happen)
// -6 = invalid literal/length or distance code
// -7 = distance too far back
// -8 = invalid block type
// -9 = output buffer too small
// -10 = invalid Huffman code during decode

private struct BitState {
    u8* src;
    i32 srclen;
    i32 srcpos;
    i32 bitbuf;
    i32 bitcnt;
    u8* dst;
    i32 dstlen;
    i32 dstpos;
}

// Huffman table: count[0..MAXBITS] and symbol[0..nsymbols]
private i32 MAXBITS = 15;

private struct Huffman {
    i32* count;   // number of codes of each length (0..MAXBITS)
    i32* symbol;  // canonical symbol order
}

// Read `need` bits from input, LSB first. Returns -1 on exhaustion.
private i32 inf_bits(BitState* s, i32 need) {
    i32 val = s.bitbuf;
    i32 have = s.bitcnt;
    while have < need {
        if s.srcpos >= s.srclen { return 0 - 1; }
        val = val | (cast(i32, *(s.src + s.srcpos)) << have);
        s.srcpos = s.srcpos + 1;
        have = have + 8;
    }
    s.bitbuf = val >> need;
    s.bitcnt = have - need;
    return val & ((1 << need) - 1);
}

// Build a Huffman table from code lengths.
// Returns 0 on success, negative on error.
private i32 huffman_construct(Huffman* h, i32* lengths, i32 n) {
    // Count codes per length
    for i32 i = 0; i <= MAXBITS; i = i + 1 {
        *(h.count + i) = 0;
    }
    for i32 i = 0; i < n; i = i + 1 {
        *(h.count + *(lengths + i)) = *(h.count + *(lengths + i)) + 1;
    }
    if *(h.count + 0) == n { return 0; } // no codes — complete but decode will fail

    // Check for over-subscribed or incomplete set
    i32 left = 1;
    for i32 len = 1; len <= MAXBITS; len = len + 1 {
        left = left << 1;
        left = left - *(h.count + len);
        if left < 0 { return 0 - 4; } // over-subscribed
    }

    // Generate offsets into symbol table for each length
    i32[16] offs;
    offs[0] = 0;
    offs[1] = 0;
    for i32 len = 1; len < MAXBITS; len = len + 1 {
        offs[len + 1] = offs[len] + *(h.count + len);
    }

    // Fill symbol table
    for i32 i = 0; i < n; i = i + 1 {
        i32 clen = *(lengths + i);
        if clen != 0 {
            *(h.symbol + offs[clen]) = i;
            offs[clen] = offs[clen] + 1;
        }
    }

    return left;
}

// Decode one symbol using Huffman table. Returns symbol or -10 on error.
private i32 huffman_decode(BitState* s, Huffman* h) {
    i32 code = 0;
    i32 first = 0;
    i32 idx = 0;
    for i32 len = 1; len <= MAXBITS; len = len + 1 {
        i32 bit = inf_bits(s, 1);
        if bit < 0 { return 0 - 10; }
        code = code | bit;
        i32 cnt = *(h.count + len);
        if code - cnt < first {
            return *(h.symbol + idx + (code - first));
        }
        idx = idx + cnt;
        first = (first + cnt) << 1;
        code = code << 1;
    }
    return 0 - 10; // ran out of bits
}

// Decompress a stored (uncompressed) block
private i32 inflate_stored(BitState* s) {
    // Discard remaining bits in current byte
    s.bitbuf = 0;
    s.bitcnt = 0;

    // Read length and complement
    if s.srcpos + 4 > s.srclen { return 0 - 1; }
    i32 len = cast(i32, *(s.src + s.srcpos));
    len = len | (cast(i32, *(s.src + s.srcpos + 1)) << 8);
    i32 nlen = cast(i32, *(s.src + s.srcpos + 2));
    nlen = nlen | (cast(i32, *(s.src + s.srcpos + 3)) << 8);
    s.srcpos = s.srcpos + 4;

    if (len ^ nlen) != 65535 { return 0 - 2; } // complement mismatch

    if s.srcpos + len > s.srclen { return 0 - 1; }

    // Copy bytes to output
    for i32 i = 0; i < len; i = i + 1 {
        if s.dstpos >= s.dstlen { return 0 - 9; }
        *(s.dst + s.dstpos) = *(s.src + s.srcpos);
        s.dstpos = s.dstpos + 1;
        s.srcpos = s.srcpos + 1;
    }
    return 0;
}

// Length and distance tables (RFC 1951 §3.2.5)
// Initialized by init_len_dist_tables()
i32[29] inf_lens;   // base length for each length code 257..285
i32[29] inf_lext;   // extra bits for each length code
i32[30] inf_dists;  // base distance for each distance code 0..29
i32[30] inf_dext;   // extra bits for each distance code

private bool inf_tables_inited = false;

void init_len_dist_tables() {
    if inf_tables_inited { return; }
    inf_tables_inited = true;

    // Length codes 257-285
    // lengths: 3,4,5,6,7,8,9,10, 11,13,15,17, 19,23,27,31, 35,43,51,59,
    //          67,83,99,115, 131,163,195,227, 258
    // extra:   0,0,0,0,0,0,0,0,  1,1,1,1,  2,2,2,2,  3,3,3,3,  4,4,4,4,  5,5,5,5, 0

    i32 idx = 0;
    i32 length = 3;
    for i32 bits = 0; bits < 6; bits = bits + 1 {
        i32 n_codes = 4;
        if bits == 0 { n_codes = 8; } // first group has 8 codes, rest have 4
        for i32 j = 0; j < n_codes; j = j + 1 {
            if idx < 29 {
                inf_lens[idx] = length;
                inf_lext[idx] = bits;
                if bits == 0 { inf_lext[idx] = 0; }
                length = length + (1 << bits);
                if bits == 0 { length = length - 1 + 1; } // step of 1 for first 8
                idx = idx + 1;
            }
        }
    }
    // Fix: code 285 is length 258, 0 extra bits
    inf_lens[28] = 258;
    inf_lext[28] = 0;

    // Actually, let me just directly assign the tables from the spec
    inf_lens[0] = 3;   inf_lext[0] = 0;
    inf_lens[1] = 4;   inf_lext[1] = 0;
    inf_lens[2] = 5;   inf_lext[2] = 0;
    inf_lens[3] = 6;   inf_lext[3] = 0;
    inf_lens[4] = 7;   inf_lext[4] = 0;
    inf_lens[5] = 8;   inf_lext[5] = 0;
    inf_lens[6] = 9;   inf_lext[6] = 0;
    inf_lens[7] = 10;  inf_lext[7] = 0;
    inf_lens[8] = 11;  inf_lext[8] = 1;
    inf_lens[9] = 13;  inf_lext[9] = 1;
    inf_lens[10] = 15; inf_lext[10] = 1;
    inf_lens[11] = 17; inf_lext[11] = 1;
    inf_lens[12] = 19; inf_lext[12] = 2;
    inf_lens[13] = 23; inf_lext[13] = 2;
    inf_lens[14] = 27; inf_lext[14] = 2;
    inf_lens[15] = 31; inf_lext[15] = 2;
    inf_lens[16] = 35; inf_lext[16] = 3;
    inf_lens[17] = 43; inf_lext[17] = 3;
    inf_lens[18] = 51; inf_lext[18] = 3;
    inf_lens[19] = 59; inf_lext[19] = 3;
    inf_lens[20] = 67; inf_lext[20] = 4;
    inf_lens[21] = 83; inf_lext[21] = 4;
    inf_lens[22] = 99; inf_lext[22] = 4;
    inf_lens[23] = 115; inf_lext[23] = 4;
    inf_lens[24] = 131; inf_lext[24] = 5;
    inf_lens[25] = 163; inf_lext[25] = 5;
    inf_lens[26] = 195; inf_lext[26] = 5;
    inf_lens[27] = 227; inf_lext[27] = 5;
    inf_lens[28] = 258; inf_lext[28] = 0;

    // Distance codes 0-29
    inf_dists[0] = 1;     inf_dext[0] = 0;
    inf_dists[1] = 2;     inf_dext[1] = 0;
    inf_dists[2] = 3;     inf_dext[2] = 0;
    inf_dists[3] = 4;     inf_dext[3] = 0;
    inf_dists[4] = 5;     inf_dext[4] = 1;
    inf_dists[5] = 7;     inf_dext[5] = 1;
    inf_dists[6] = 9;     inf_dext[6] = 2;
    inf_dists[7] = 13;    inf_dext[7] = 2;
    inf_dists[8] = 17;    inf_dext[8] = 3;
    inf_dists[9] = 25;    inf_dext[9] = 3;
    inf_dists[10] = 33;   inf_dext[10] = 4;
    inf_dists[11] = 49;   inf_dext[11] = 4;
    inf_dists[12] = 65;   inf_dext[12] = 5;
    inf_dists[13] = 97;   inf_dext[13] = 5;
    inf_dists[14] = 129;  inf_dext[14] = 6;
    inf_dists[15] = 193;  inf_dext[15] = 6;
    inf_dists[16] = 257;  inf_dext[16] = 7;
    inf_dists[17] = 385;  inf_dext[17] = 7;
    inf_dists[18] = 513;  inf_dext[18] = 8;
    inf_dists[19] = 769;  inf_dext[19] = 8;
    inf_dists[20] = 1025; inf_dext[20] = 9;
    inf_dists[21] = 1537; inf_dext[21] = 9;
    inf_dists[22] = 2049; inf_dext[22] = 10;
    inf_dists[23] = 3073; inf_dext[23] = 10;
    inf_dists[24] = 4097; inf_dext[24] = 11;
    inf_dists[25] = 6145; inf_dext[25] = 11;
    inf_dists[26] = 8193; inf_dext[26] = 12;
    inf_dists[27] = 12289; inf_dext[27] = 12;
    inf_dists[28] = 16385; inf_dext[28] = 13;
    inf_dists[29] = 24577; inf_dext[29] = 13;
    return;
}

// Decode literal/length/distance codes until end-of-block
private i32 inflate_codes(BitState* s, Huffman* lencode, Huffman* distcode) {
    init_len_dist_tables();

    while true {
        i32 sym = huffman_decode(s, lencode);
        if sym < 0 { return 0 - 6; }
        if sym < 256 {
            // Literal byte
            if s.dstpos >= s.dstlen { return 0 - 9; }
            *(s.dst + s.dstpos) = cast(u8, sym);
            s.dstpos = s.dstpos + 1;
        } else if sym == 256 {
            // End of block
            return 0;
        } else {
            // Length/distance pair
            sym = sym - 257;
            if sym >= 29 { return 0 - 6; }
            i32 length = inf_lens[sym];
            i32 extra = inf_lext[sym];
            if extra > 0 {
                i32 eb = inf_bits(s, extra);
                if eb < 0 { return 0 - 1; }
                length = length + eb;
            }

            // Decode distance
            i32 dsym = huffman_decode(s, distcode);
            if dsym < 0 || dsym >= 30 { return 0 - 6; }
            i32 dist = inf_dists[dsym];
            extra = inf_dext[dsym];
            if extra > 0 {
                i32 eb = inf_bits(s, extra);
                if eb < 0 { return 0 - 1; }
                dist = dist + eb;
            }

            // Check distance
            if dist > s.dstpos { return 0 - 7; }

            // Copy from output buffer (allows overlapping)
            for i32 i = 0; i < length; i = i + 1 {
                if s.dstpos >= s.dstlen { return 0 - 9; }
                *(s.dst + s.dstpos) = *(s.dst + s.dstpos - dist);
                s.dstpos = s.dstpos + 1;
            }
        }
    }
    return 0;
}

// Decompress a fixed Huffman block (RFC 1951 §3.2.6)
private i32 inflate_fixed(BitState* s) {
    // Build fixed literal/length code: 0-143=8, 144-255=9, 256-279=7, 280-287=8
    i32[288] lengths;
    for i32 i = 0; i < 144; i = i + 1 { lengths[i] = 8; }
    for i32 i = 144; i < 256; i = i + 1 { lengths[i] = 9; }
    for i32 i = 256; i < 280; i = i + 1 { lengths[i] = 7; }
    for i32 i = 280; i < 288; i = i + 1 { lengths[i] = 8; }

    i32[16] lcount;
    i32[288] lsymbol;
    Huffman lencode;
    lencode.count = &lcount[0];
    lencode.symbol = &lsymbol[0];
    i32 err = huffman_construct(&lencode, &lengths[0], 288);
    if err < 0 { return 0 - 5; }

    // Build fixed distance code: all 5-bit codes
    // Note: 30 codes of length 5 is incomplete (2 unused), which is OK
    i32[30] dlengths;
    for i32 i = 0; i < 30; i = i + 1 { dlengths[i] = 5; }

    i32[16] dcount;
    i32[30] dsymbol;
    Huffman distcode;
    distcode.count = &dcount[0];
    distcode.symbol = &dsymbol[0];
    err = huffman_construct(&distcode, &dlengths[0], 30);
    if err < 0 { return 0 - 5; }

    return inflate_codes(s, &lencode, &distcode);
}

// Decompress a dynamic Huffman block (RFC 1951 §3.2.7)
private i32 inflate_dynamic(BitState* s) {
    // Read table sizes
    i32 nlen = inf_bits(s, 5);
    if nlen < 0 { return 0 - 1; }
    nlen = nlen + 257;
    i32 ndist = inf_bits(s, 5);
    if ndist < 0 { return 0 - 1; }
    ndist = ndist + 1;
    i32 ncode = inf_bits(s, 4);
    if ncode < 0 { return 0 - 1; }
    ncode = ncode + 4;

    if nlen > 286 || ndist > 30 { return 0 - 3; }

    // Code length code order (RFC 1951 §3.2.7)
    i32[19] order = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};

    // Read code length code lengths
    i32[19] clengths;
    for i32 i = 0; i < 19; i = i + 1 { clengths[i] = 0; }
    for i32 i = 0; i < ncode; i = i + 1 {
        i32 v = inf_bits(s, 3);
        if v < 0 { return 0 - 1; }
        clengths[order[i]] = v;
    }

    // Build code length Huffman table
    i32[16] ccount;
    i32[19] csymbol;
    Huffman clcode;
    clcode.count = &ccount[0];
    clcode.symbol = &csymbol[0];
    i32 err = huffman_construct(&clcode, &clengths[0], 19);
    if err < 0 { return 0 - 4; }

    // Decode literal/length + distance code lengths
    i32 total = nlen + ndist;
    i32[316] lengths; // max 286 + 30
    i32 idx = 0;
    while idx < total {
        i32 sym = huffman_decode(s, &clcode);
        if sym < 0 { return 0 - 4; }

        if sym < 16 {
            // Literal code length
            lengths[idx] = sym;
            idx = idx + 1;
        } else if sym == 16 {
            // Copy previous 3-6 times
            if idx == 0 { return 0 - 4; }
            i32 rep = inf_bits(s, 2);
            if rep < 0 { return 0 - 1; }
            rep = rep + 3;
            i32 prev = lengths[idx - 1];
            for i32 j = 0; j < rep; j = j + 1 {
                if idx >= total { return 0 - 3; }
                lengths[idx] = prev;
                idx = idx + 1;
            }
        } else if sym == 17 {
            // Repeat 0 for 3-10 times
            i32 rep = inf_bits(s, 3);
            if rep < 0 { return 0 - 1; }
            rep = rep + 3;
            for i32 j = 0; j < rep; j = j + 1 {
                if idx >= total { return 0 - 3; }
                lengths[idx] = 0;
                idx = idx + 1;
            }
        } else if sym == 18 {
            // Repeat 0 for 11-138 times
            i32 rep = inf_bits(s, 7);
            if rep < 0 { return 0 - 1; }
            rep = rep + 11;
            for i32 j = 0; j < rep; j = j + 1 {
                if idx >= total { return 0 - 3; }
                lengths[idx] = 0;
                idx = idx + 1;
            }
        } else {
            return 0 - 4;
        }
    }

    // Build literal/length Huffman table
    i32[16] lcount;
    i32[288] lsymbol;
    Huffman lencode;
    lencode.count = &lcount[0];
    lencode.symbol = &lsymbol[0];
    err = huffman_construct(&lencode, &lengths[0], nlen);
    if err < 0 { return 0 - 4; }

    // Build distance Huffman table
    i32[16] dcount;
    i32[30] dsymbol;
    Huffman distcode;
    distcode.count = &dcount[0];
    distcode.symbol = &dsymbol[0];
    err = huffman_construct(&distcode, &lengths[nlen], ndist);
    if err < 0 { return 0 - 4; }

    return inflate_codes(s, &lencode, &distcode);
}

// Main inflate function: decompress raw DEFLATE data
// Returns 0 on success, negative on error
i32 inflate(u8* src, i32 srclen, u8* dst, i32 dstlen, i32* out_srcused, i32* out_dstused) {
    BitState state;
    state.src = src;
    state.srclen = srclen;
    state.srcpos = 0;
    state.bitbuf = 0;
    state.bitcnt = 0;
    state.dst = dst;
    state.dstlen = dstlen;
    state.dstpos = 0;

    i32 last = 0;
    while last == 0 {
        last = inf_bits(&state, 1);
        if last < 0 { return 0 - 1; }
        i32 btype = inf_bits(&state, 2);
        if btype < 0 { return 0 - 1; }

        i32 err = 0;
        if btype == 0 {
            err = inflate_stored(&state);
        } else if btype == 1 {
            err = inflate_fixed(&state);
        } else if btype == 2 {
            err = inflate_dynamic(&state);
        } else {
            return 0 - 8; // reserved block type
        }

        if err != 0 { return err; }
    }

    if out_srcused != cast(i32*, 0) { *out_srcused = state.srcpos; }
    if out_dstused != cast(i32*, 0) { *out_dstused = state.dstpos; }
    return 0;
}
