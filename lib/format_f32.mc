// Shortest round-trip f32 formatter (Ryu).
//
//   import format_f32;
//   string s = format_f32(0.1f);    // "0.1"
//   i32 n = f32_to_str(v, buf);     // into a caller buffer (>= 20 bytes)
//
// Returns the shortest decimal that reads back as the same f32. Special 
// values give "nan", "inf", "-inf"; zero gives "0.0". Magnitudes in 
// [1e-4, 1e21) print as plain decimal, the rest in scientific notation.
//
// Importing this alongside format_f64 is safe; the two share no names.
//
// Reference: Adams 2018, "Ryu: Fast Float-to-String Conversion."

private {

// f32 5^q tables for Ryu. Each entry is 64 bits.
//
// POW5: q in [0, 46], normalized to 61 bits.
// INV : q in [0, 30], 5^-q approximation.

const i32 RYU32_POW5_BITCOUNT       = 61;
const i32 RYU32_POW5_INV_BITCOUNT   = 59;
const i32 RYU32_POW5_TABLE_SIZE     = 47;
const i32 RYU32_POW5_INV_TABLE_SIZE = 31;

const i64[47] ryu32_pow5_split = {
    0x1000000000000000,   // 5^0
    0x1400000000000000,   // 5^1
    0x1900000000000000,   // 5^2
    0x1F40000000000000,   // 5^3
    0x1388000000000000,   // 5^4
    0x186A000000000000,   // 5^5
    0x1E84800000000000,   // 5^6
    0x1312D00000000000,   // 5^7
    0x17D7840000000000,   // 5^8
    0x1DCD650000000000,   // 5^9
    0x12A05F2000000000,   // 5^10
    0x174876E800000000,   // 5^11
    0x1D1A94A200000000,   // 5^12
    0x12309CE540000000,   // 5^13
    0x16BCC41E90000000,   // 5^14
    0x1C6BF52634000000,   // 5^15
    0x11C37937E0800000,   // 5^16
    0x16345785D8A00000,   // 5^17
    0x1BC16D674EC80000,   // 5^18
    0x1158E460913D0000,   // 5^19
    0x15AF1D78B58C4000,   // 5^20
    0x1B1AE4D6E2EF5000,   // 5^21
    0x10F0CF064DD59200,   // 5^22
    0x152D02C7E14AF680,   // 5^23
    0x1A784379D99DB420,   // 5^24
    0x108B2A2C28029094,   // 5^25
    0x14ADF4B7320334B9,   // 5^26
    0x19D971E4FE8401E7,   // 5^27
    0x1027E72F1F128130,   // 5^28
    0x1431E0FAE6D7217C,   // 5^29
    0x193E5939A08CE9DB,   // 5^30
    0x1F8DEF8808B02452,   // 5^31
    0x13B8B5B5056E16B3,   // 5^32
    0x18A6E32246C99C60,   // 5^33
    0x1ED09BEAD87C0378,   // 5^34
    0x13426172C74D822B,   // 5^35
    0x1812F9CF7920E2B6,   // 5^36
    0x1E17B84357691B64,   // 5^37
    0x12CED32A16A1B11E,   // 5^38
    0x178287F49C4A1D66,   // 5^39
    0x1D6329F1C35CA4BF,   // 5^40
    0x125DFA371A19E6F7,   // 5^41
    0x16F578C4E0A060B5,   // 5^42
    0x1CB2D6F618C878E3,   // 5^43
    0x11EFC659CF7D4B8D,   // 5^44
    0x166BB7F0435C9E71,   // 5^45
    0x1C06A5EC5433C60D,   // 5^46
};

const i64[31] ryu32_pow5_inv_split = {
    0x0800000000000000,   // 1/5^0
    0x0666666666666667,   // 1/5^1
    0x051EB851EB851EB9,   // 1/5^2
    0x04189374BC6A7EFA,   // 1/5^3
    0x068DB8BAC710CB2A,   // 1/5^4
    0x053E2D6238DA3C22,   // 1/5^5
    0x0431BDE82D7B634E,   // 1/5^6
    0x06B5FCA6AF2BD216,   // 1/5^7
    0x055E63B88C230E78,   // 1/5^8
    0x044B82FA09B5A52D,   // 1/5^9
    0x06DF37F675EF6EAE,   // 1/5^10
    0x057F5FF85E592558,   // 1/5^11
    0x0465E6604B7A8447,   // 1/5^12
    0x0709709A125DA071,   // 1/5^13
    0x05A126E1A84AE6C1,   // 1/5^14
    0x0480EBE7B9D58567,   // 1/5^15
    0x0734ACA5F6226F0B,   // 1/5^16
    0x05C3BD5191B525A3,   // 1/5^17
    0x049C97747490EAE9,   // 1/5^18
    0x0760F253EDB4AB0E,   // 1/5^19
    0x05E72843249088D8,   // 1/5^20
    0x04B8ED0283A6D3E0,   // 1/5^21
    0x078E480405D7B966,   // 1/5^22
    0x060B6CD004AC9452,   // 1/5^23
    0x04D5F0A66A23A9DB,   // 1/5^24
    0x07BCB43D769F762B,   // 1/5^25
    0x063090312BB2C4EF,   // 1/5^26
    0x04F3A68DBC8F03F3,   // 1/5^27
    0x07EC3DAF94180651,   // 1/5^28
    0x065697BFA9ACD1DA,   // 1/5^29
    0x051212FFBAF0A7E2,   // 1/5^30
};


// ------ low-level arithmetic helpers ----------------------------------

// floor(m * factor / 2^shift). For f32, m fits in ~26 bits and factor
// is a 64-bit table entry, so every partial product stays in a
// positive i64 and no 128-bit step is needed. shift is in [33, 62], so
// shift-32 is a valid 1..30 shift. The low-32 mask truncates to u32.
i64 ryu32_mul_shift(i64 m, i64 factor, i32 shift) {
    i64 mask32 = 0xFFFFFFFF;
    i64 factor_lo = factor & mask32;
    i64 factor_hi = (factor >> 32) & mask32;
    i64 bits0 = m * factor_lo;
    i64 bits1 = m * factor_hi;
    i64 sum = ((bits0 >> 32) & mask32) + bits1;
    return (sum >> (shift - 32)) & mask32;
}

i64 ryu32_mul_pow5_inv_div_pow2(i64 m, i32 q, i32 j) {
    return ryu32_mul_shift(m, ryu32_pow5_inv_split[q], j);
}

i64 ryu32_mul_pow5_div_pow2(i64 m, i32 i, i32 j) {
    return ryu32_mul_shift(m, ryu32_pow5_split[i], j);
}

// Count factors of 5 in value (value > 0).
i32 ryu32_pow5_factor(i64 value) {
    i32 count = 0;
    while value != 0 {
        i64 q = value / 5;
        if q * 5 != value { return count; }
        value = q;
        count = count + 1;
    }
    return count;
}

bool ryu32_multiple_of_power_of_5(i64 value, i32 p) {
    return ryu32_pow5_factor(value) >= p;
}

bool ryu32_multiple_of_power_of_2(i64 value, i32 p) {
    if p >= 64 { return value == 0; }
    i64 mask = (cast(i64, 1) << p) - 1;
    return (value & mask) == 0;
}

// floor(e * log10(2)), e >= 0 in the range Ryu uses.
i32 ryu32_log10_pow2(i32 e) {
    return (e * 78913) >> 18;
}

// floor(e * log10(5)), e >= 0.
i32 ryu32_log10_pow5(i32 e) {
    return (e * 732923) >> 20;
}

// ceil(e * log2(5)), e >= 0.
i32 ryu32_pow5_bits(i32 e) {
    return ((e * 1217359) >> 19) + 1;
}

// Write decimal of n (n > 0, no sign). Returns bytes written.
i32 ryu32_write_uint(i64 n, u8* buf) {
    u8[24] tmp;
    i32 len = 0;
    while n > 0 {
        i64 d = n % 10;
        tmp[len] = cast(u8, '0' + cast(i32, d));
        n = n / 10;
        len = len + 1;
    }
    for i32 i = 0; i < len; i = i + 1 {
        *(buf + i) = tmp[len - 1 - i];
    }
    return len;
}

i32 ryu32_decimal_length(i64 n) {
    i32 d = 0;
    while n > 0 { n = n / 10; d = d + 1; }
    return d;
}

// ------ the Ryu32 core ------------------------------------------------

struct RyuDecimal32 {
    i64 mantissa;
    i32 exponent;
    bool sign;
}

// Decompose a non-special f32 into its shortest decimal. The caller
// has already handled nan, inf, and zero.
RyuDecimal32 ryu32_f2d(i32 bits) {
    i32 ieee_exp = (bits >> 23) & 0xFF;
    i32 ieee_mant = bits & 0x7FFFFF;
    bool sign = bits < 0;

    i32 e2;
    i64 m2;
    if ieee_exp == 0 {
        e2 = 1 - 127 - 23 - 2;
        m2 = cast(i64, ieee_mant);
    } else {
        e2 = ieee_exp - 127 - 23 - 2;
        m2 = cast(i64, ieee_mant) | (cast(i64, 1) << 23);
    }

    bool even = (m2 & 1) == 0;
    bool accept_bounds = even;

    i64 mv = 4 * m2;
    i64 mp = 4 * m2 + 2;
    i32 mm_shift = 1;
    if ieee_mant == 0 && ieee_exp > 1 {
        mm_shift = 0;
    }
    i64 mm = 4 * m2 - 1 - mm_shift;

    i64 vr; i64 vp; i64 vm;
    i32 e10;
    bool vm_is_trailing_zeros = false;
    bool vr_is_trailing_zeros = false;
    i32 last_removed = 0;

    if e2 >= 0 {
        i32 q = ryu32_log10_pow2(e2);
        e10 = q;
        i32 k = RYU32_POW5_INV_BITCOUNT + ryu32_pow5_bits(q) - 1;
        i32 i = (0 - e2) + q + k;
        vr = ryu32_mul_pow5_inv_div_pow2(mv, q, i);
        vp = ryu32_mul_pow5_inv_div_pow2(mp, q, i);
        vm = ryu32_mul_pow5_inv_div_pow2(mm, q, i);
        if q != 0 && (vp - 1) / 10 <= vm / 10 {
            i32 l = RYU32_POW5_INV_BITCOUNT + ryu32_pow5_bits(q - 1) - 1;
            i64 lr = ryu32_mul_pow5_inv_div_pow2(mv, q - 1, (0 - e2) + q - 1 + l);
            last_removed = cast(i32, lr % 10);
        }
        if q <= 9 {
            if mv % 5 == 0 {
                vr_is_trailing_zeros = ryu32_multiple_of_power_of_5(mv, q);
            } else if accept_bounds {
                vm_is_trailing_zeros = ryu32_multiple_of_power_of_5(mm, q);
            } else {
                if ryu32_multiple_of_power_of_5(mp, q) { vp = vp - 1; }
            }
        }
    } else {
        i32 q = ryu32_log10_pow5(0 - e2);
        e10 = q + e2;
        i32 i = (0 - e2) - q;
        i32 k = ryu32_pow5_bits(i) - RYU32_POW5_BITCOUNT;
        i32 j = q - k;
        vr = ryu32_mul_pow5_div_pow2(mv, i, j);
        vp = ryu32_mul_pow5_div_pow2(mp, i, j);
        vm = ryu32_mul_pow5_div_pow2(mm, i, j);
        if q != 0 && (vp - 1) / 10 <= vm / 10 {
            i32 jj = q - 1 - (ryu32_pow5_bits(i + 1) - RYU32_POW5_BITCOUNT);
            i64 lr = ryu32_mul_pow5_div_pow2(mv, i + 1, jj);
            last_removed = cast(i32, lr % 10);
        }
        if q <= 1 {
            vr_is_trailing_zeros = true;
            if accept_bounds {
                vm_is_trailing_zeros = mm_shift == 1;
            } else {
                vp = vp - 1;
            }
        } else if q < 31 {
            vr_is_trailing_zeros = ryu32_multiple_of_power_of_2(mv, q - 1);
        }
    }

    // Shorten: remove trailing digits while keeping vm < vp.
    i32 removed = 0;
    i64 output;
    if vm_is_trailing_zeros || vr_is_trailing_zeros {
        while vp / 10 > vm / 10 {
            vm_is_trailing_zeros = vm_is_trailing_zeros && (vm % 10 == 0);
            vr_is_trailing_zeros = vr_is_trailing_zeros && (last_removed == 0);
            last_removed = cast(i32, vr % 10);
            vr = vr / 10;
            vp = vp / 10;
            vm = vm / 10;
            removed = removed + 1;
        }
        if vm_is_trailing_zeros {
            while vm % 10 == 0 {
                vr_is_trailing_zeros = vr_is_trailing_zeros && (last_removed == 0);
                last_removed = cast(i32, vr % 10);
                vr = vr / 10;
                vp = vp / 10;
                vm = vm / 10;
                removed = removed + 1;
            }
        }
        if vr_is_trailing_zeros && last_removed == 5 && vr % 2 == 0 {
            last_removed = 4;
        }
        bool inc = (vr == vm && (!accept_bounds || !vm_is_trailing_zeros)) || last_removed >= 5;
        if inc { output = vr + 1; } else { output = vr; }
    } else {
        while vp / 10 > vm / 10 {
            last_removed = cast(i32, vr % 10);
            vr = vr / 10;
            vp = vp / 10;
            vm = vm / 10;
            removed = removed + 1;
        }
        bool inc = vr == vm || last_removed >= 5;
        if inc { output = vr + 1; } else { output = vr; }
    }

    RyuDecimal32 r;
    r.mantissa = output;
    r.exponent = e10 + removed;
    r.sign = sign;
    return r;
}

// Format the (sign, mantissa, exponent) decimal triple into buf.
// Decimal vs scientific by magnitude (identical rules to format_f64).
i32 ryu32_format_d2d(RyuDecimal32 d, u8* buf) {
    i32 idx = 0;
    if d.sign && d.mantissa != 0 {
        *(buf + idx) = '-';
        idx = idx + 1;
    }
    i32 olen = ryu32_decimal_length(d.mantissa);
    // The decimal value is d.mantissa * 10^d.exponent.
    // Equivalently, the displayed value has olen significant digits
    // and a leftmost-decimal exponent of (d.exponent + olen - 1).
    i32 sci_exp = d.exponent + olen - 1;

    // Auto-switch: decimal for 1e-4 <= |x| < 1e21, scientific outside.
    // sci_exp is the exponent for scientific notation (i.e. log10 of the
    // leading-digit value). |x| in [1e-4, 1e21) <=> sci_exp in [-4, 21).
    bool use_sci = sci_exp < (0 - 4) || sci_exp >= 21;

    if use_sci {
        // Output: <digit>.<rest>e<exp>   (rest may be empty if olen==1)
        u8[24] digits;
        i64 m = d.mantissa;
        i32 i = 0;
        while m > 0 {
            digits[i] = cast(u8, '0' + cast(i32, m % 10));
            m = m / 10;
            i = i + 1;
        }
        // Now digits[0..olen-1] holds least-significant-digit-first; reverse.
        // Emit digit[olen-1] '.' digit[olen-2] ... digit[0]
        *(buf + idx) = digits[olen - 1];
        idx = idx + 1;
        if olen > 1 {
            *(buf + idx) = '.';
            idx = idx + 1;
            for i32 k = olen - 2; k >= 0; k = k - 1 {
                *(buf + idx) = digits[k];
                idx = idx + 1;
            }
        } else {
            // Single digit: still emit ".0" so float-ness is visible.
            *(buf + idx) = '.';
            idx = idx + 1;
            *(buf + idx) = '0';
            idx = idx + 1;
        }
        *(buf + idx) = 'e';
        idx = idx + 1;
        i32 e = sci_exp;
        if e < 0 {
            *(buf + idx) = '-';
            idx = idx + 1;
            e = 0 - e;
        }
        // Write exponent (no padding, no '+').
        u8[6] etmp;
        i32 ei = 0;
        if e == 0 {
            etmp[0] = '0';
            ei = 1;
        } else {
            while e > 0 {
                etmp[ei] = cast(u8, '0' + (e % 10));
                e = e / 10;
                ei = ei + 1;
            }
        }
        for i32 k = ei - 1; k >= 0; k = k - 1 {
            *(buf + idx) = etmp[k];
            idx = idx + 1;
        }
        return idx;
    }

    // Decimal path.
    if d.exponent >= 0 {
        // Integer-and-zero-padding case: mantissa followed by `exponent`
        // zeros, then ".0" so float-ness is visible.
        idx = idx + ryu32_write_uint(d.mantissa, buf + idx);
        for i32 k = 0; k < d.exponent; k = k + 1 {
            *(buf + idx) = '0';
            idx = idx + 1;
        }
        *(buf + idx) = '.';
        idx = idx + 1;
        *(buf + idx) = '0';
        idx = idx + 1;
        return idx;
    } else {
        // Fractional case: -d.exponent < olen means dot is inside the
        // digits; -d.exponent >= olen means leading "0.0...0" before
        // the digits.
        i32 dot_pos = olen + d.exponent;   // exponent is negative
        // Get digit string into a temp buffer.
        u8[24] digits;
        i64 m = d.mantissa;
        for i32 k = olen - 1; k >= 0; k = k - 1 {
            digits[k] = cast(u8, '0' + cast(i32, m % 10));
            m = m / 10;
        }
        if dot_pos > 0 {
            // Emit dot_pos digits, '.', then the rest.
            for i32 k = 0; k < dot_pos; k = k + 1 {
                *(buf + idx) = digits[k];
                idx = idx + 1;
            }
            *(buf + idx) = '.';
            idx = idx + 1;
            for i32 k = dot_pos; k < olen; k = k + 1 {
                *(buf + idx) = digits[k];
                idx = idx + 1;
            }
            return idx;
        } else {
            // Leading "0." then (-dot_pos) zeros, then all digits.
            *(buf + idx) = '0';
            idx = idx + 1;
            *(buf + idx) = '.';
            idx = idx + 1;
            for i32 k = 0; k < (0 - dot_pos); k = k + 1 {
                *(buf + idx) = '0';
                idx = idx + 1;
            }
            for i32 k = 0; k < olen; k = k + 1 {
                *(buf + idx) = digits[k];
                idx = idx + 1;
            }
            return idx;
        }
    }
}

}  // end private

// ------ public entry points ------------------------------------------

// Write the formatted value into buf (at least 20 bytes) and return its
// length. Specials are read from the bit pattern.
i32 f32_to_str(f32 v, u8* buf) {
    i32 bits = *cast(i32*, &v);
    i32 abs_bits = bits & 0x7FFFFFFF;
    i32 exp_field = (abs_bits >> 23) & 0xFF;
    bool sign = bits < 0;
    if exp_field == 0xFF {
        if (abs_bits & 0x7FFFFF) != 0 {
            *(buf + 0) = 'n'; *(buf + 1) = 'a'; *(buf + 2) = 'n';
            return 3;
        }
        if sign {
            *(buf + 0) = '-'; *(buf + 1) = 'i'; *(buf + 2) = 'n'; *(buf + 3) = 'f';
            return 4;
        }
        *(buf + 0) = 'i'; *(buf + 1) = 'n'; *(buf + 2) = 'f';
        return 3;
    }
    if abs_bits == 0 {
        *(buf + 0) = '0'; *(buf + 1) = '.'; *(buf + 2) = '0';
        return 3;
    }
    RyuDecimal32 d = ryu32_f2d(bits);
    return ryu32_format_d2d(d, buf);
}

// Format v as a newly allocated string. The caller owns it.
string format_f32(f32 v) {
    u8* buf = alloc<u8>(20);
    i32 n = f32_to_str(v, buf);
    string s;
    s.data = buf;
    s.len = n;
    return s;
}
