"""One-shot XXH32, XXH64, and XXH3-64 kernels exposed through a C ABI."""

from std.sys import inlined_assembly
from std.sys.info import simd_width_of as simdwidthof

comptime BPtr = UnsafePointer[UInt8, AnyOrigin[mut=True]]

comptime P32_1: UInt32 = 0x9E3779B1
comptime P32_2: UInt32 = 0x85EBCA77
comptime P32_3: UInt32 = 0xC2B2AE3D
comptime P32_4: UInt32 = 0x27D4EB2F
comptime P32_5: UInt32 = 0x165667B1

comptime P64_1: UInt64 = 0x9E3779B185EBCA87
comptime P64_2: UInt64 = 0xC2B2AE3D27D4EB4F
comptime P64_3: UInt64 = 0x165667B19E3779F9
comptime P64_4: UInt64 = 0x85EBCA77C2B2AE63
comptime P64_5: UInt64 = 0x27D4EB2F165667C5
comptime MX1: UInt64 = 0x165667919E3779F9
comptime MX2: UInt64 = 0x9FB21C651E98DF25


def read32(p: BPtr, offset: Int) -> UInt32:
    return (p + offset).bitcast[UInt32]().load[alignment=1]()


def read64(p: BPtr, offset: Int) -> UInt64:
    return (p + offset).bitcast[UInt64]().load[alignment=1]()


def rotl32(v: UInt32, n: UInt32) -> UInt32:
    return (v << n) | (v >> (UInt32(32) - n))


def rotl64(v: UInt64, n: UInt64) -> UInt64:
    return (v << n) | (v >> (UInt64(64) - n))


def swap32(v: UInt32) -> UInt32:
    return (
        (v << 24)
        | ((v << 8) & 0x00FF0000)
        | ((v >> 8) & 0x0000FF00)
        | (v >> 24)
    )


def swap64(v: UInt64) -> UInt64:
    return (
        (v << 56)
        | ((v << 40) & 0x00FF000000000000)
        | ((v << 24) & 0x0000FF0000000000)
        | ((v << 8) & 0x000000FF00000000)
        | ((v >> 8) & 0x00000000FF000000)
        | ((v >> 24) & 0x0000000000FF0000)
        | ((v >> 40) & 0x000000000000FF00)
        | (v >> 56)
    )


def xxh32_round(acc: UInt32, lane: UInt32) -> UInt32:
    return inlined_assembly[
        "imull $$0x85ebca77, $0; addl $1, $0; roll $$13, $0; imull $$0x9e3779b1, $0",
        UInt32,
        constraints="=r,r,0",
        has_side_effect=False,
    ](acc, lane)


def xxh32_impl(p: BPtr, n: Int, seed: UInt32) -> UInt32:
    var i = 0
    var h: UInt32
    if n >= 16:
        var v1 = seed + P32_1 + P32_2
        var v2 = seed + P32_2
        var v3 = seed
        var v4 = seed - P32_1
        while i <= n - 16:
            v1 = xxh32_round(v1, read32(p, i))
            v2 = xxh32_round(v2, read32(p, i + 4))
            v3 = xxh32_round(v3, read32(p, i + 8))
            v4 = xxh32_round(v4, read32(p, i + 12))
            i += 16
        h = (
            rotl32(v1, 1)
            + rotl32(v2, 7)
            + rotl32(v3, 12)
            + rotl32(v4, 18)
        )
    else:
        h = seed + P32_5
    h += UInt32(n)
    while i <= n - 4:
        h += read32(p, i) * P32_3
        h = rotl32(h, 17) * P32_4
        i += 4
    while i < n:
        h += UInt32(p[i]) * P32_5
        h = rotl32(h, 11) * P32_1
        i += 1
    h ^= h >> 15
    h *= P32_2
    h ^= h >> 13
    h *= P32_3
    h ^= h >> 16
    return h


def xxh64_round(acc: UInt64, lane: UInt64) -> UInt64:
    return rotl64(acc + lane * P64_2, 31) * P64_1


def xxh64_merge(acc: UInt64, lane: UInt64) -> UInt64:
    return (acc ^ xxh64_round(0, lane)) * P64_1 + P64_4


def avalanche64(h_in: UInt64) -> UInt64:
    var h = h_in
    h ^= h >> 33
    h *= P64_2
    h ^= h >> 29
    h *= P64_3
    h ^= h >> 32
    return h


def xxh64_impl(p: BPtr, n: Int, seed: UInt64) -> UInt64:
    var i = 0
    var h: UInt64
    if n >= 32:
        var v1 = seed + P64_1 + P64_2
        var v2 = seed + P64_2
        var v3 = seed
        var v4 = seed - P64_1
        while i <= n - 32:
            v1 = xxh64_round(v1, read64(p, i))
            v2 = xxh64_round(v2, read64(p, i + 8))
            v3 = xxh64_round(v3, read64(p, i + 16))
            v4 = xxh64_round(v4, read64(p, i + 24))
            i += 32
        h = rotl64(v1, 1) + rotl64(v2, 7) + rotl64(v3, 12) + rotl64(v4, 18)
        h = xxh64_merge(h, v1)
        h = xxh64_merge(h, v2)
        h = xxh64_merge(h, v3)
        h = xxh64_merge(h, v4)
    else:
        h = seed + P64_5
    h += UInt64(n)
    while i <= n - 8:
        h ^= xxh64_round(0, read64(p, i))
        h = rotl64(h, 27) * P64_1 + P64_4
        i += 8
    if i <= n - 4:
        h ^= UInt64(read32(p, i)) * P64_1
        h = rotl64(h, 23) * P64_2 + P64_3
        i += 4
    while i < n:
        h ^= UInt64(p[i]) * P64_5
        h = rotl64(h, 11) * P64_1
        i += 1
    return avalanche64(h)


def secret_word(i: Int, seed: UInt64) -> UInt64:
    var v: UInt64
    if i == 0: v = 0xBE4BA423396CFEB8
    elif i == 1: v = 0x1CAD21F72C81017C
    elif i == 2: v = 0xDB979083E96DD4DE
    elif i == 3: v = 0x1F67B3B7A4A44072
    elif i == 4: v = 0x78E5C0CC4EE679CB
    elif i == 5: v = 0x2172FFCC7DD05A82
    elif i == 6: v = 0x8E2443F7744608B8
    elif i == 7: v = 0x4C263A81E69035E0
    elif i == 8: v = 0xCB00C391BB52283C
    elif i == 9: v = 0xA32E531B8B65D088
    elif i == 10: v = 0x4EF90DA297486471
    elif i == 11: v = 0xD8ACDEA946EF1938
    elif i == 12: v = 0x3F349CE33F76FAA8
    elif i == 13: v = 0x1D4F0BC7C7BBDCF9
    elif i == 14: v = 0x3159B4CD4BE0518A
    elif i == 15: v = 0x647378D9C97E9FC8
    elif i == 16: v = 0xC3EBD33483ACC5EA
    elif i == 17: v = 0xEB6313FAFFA081C5
    elif i == 18: v = 0x49DAF0B751DD0D17
    elif i == 19: v = 0x9E68D429265516D3
    elif i == 20: v = 0xFCA1477D58BE162B
    elif i == 21: v = 0xCE31D07AD1B8F88F
    elif i == 22: v = 0x280416958F3ACB45
    else: v = 0x7E404BBBCAFBD7AF
    if seed != 0:
        if i % 2 == 0:
            v += seed
        else:
            v -= seed
    return v


def secret64(offset: Int, seed: UInt64) -> UInt64:
    var word = offset // 8
    var shift = offset % 8
    if shift == 0:
        return secret_word(word, seed)
    var bits = UInt64(shift * 8)
    return (secret_word(word, seed) >> bits) | (
        secret_word(word + 1, seed) << (UInt64(64) - bits)
    )


def secret64_from(words: UnsafePointer[UInt64, _], offset: Int) -> UInt64:
    var word = offset // 8
    var shift = offset % 8
    if shift == 0:
        return words[word]
    var bits = UInt64(shift * 8)
    return (words[word] >> bits) | (words[word + 1] << (UInt64(64) - bits))


def mul_fold(a: UInt64, b: UInt64) -> UInt64:
    var lo_lo = UInt64(UInt32(a)) * UInt64(UInt32(b))
    var hi_lo = UInt64(UInt32(a >> 32)) * UInt64(UInt32(b))
    var lo_hi = UInt64(UInt32(a)) * UInt64(UInt32(b >> 32))
    var hi_hi = UInt64(UInt32(a >> 32)) * UInt64(UInt32(b >> 32))
    var cross = (lo_lo >> 32) + (hi_lo & 0xFFFFFFFF) + lo_hi
    var high = (hi_lo >> 32) + (cross >> 32) + hi_hi
    var low = (cross << 32) | (lo_lo & 0xFFFFFFFF)
    return low ^ high


def avalanche3(h_in: UInt64) -> UInt64:
    var h = h_in
    h ^= h >> 37
    h *= MX1
    h ^= h >> 32
    return h


def rrmxmx(h_in: UInt64, n: Int) -> UInt64:
    var h = h_in
    h ^= rotl64(h, 49) ^ rotl64(h, 24)
    h *= MX2
    h ^= (h >> 35) + UInt64(n)
    h *= MX2
    return h ^ (h >> 28)


def mix16(p: BPtr, input_offset: Int, secret_offset: Int, seed: UInt64) -> UInt64:
    return mul_fold(
        read64(p, input_offset) ^ (secret64(secret_offset, 0) + seed),
        read64(p, input_offset + 8) ^ (secret64(secret_offset + 8, 0) - seed),
    )


def xxh3_short(p: BPtr, n: Int, seed: UInt64) -> UInt64:
    if n == 0:
        return avalanche64(seed ^ (secret64(56, 0) ^ secret64(64, 0)))
    if n <= 3:
        var c1 = UInt32(p[0])
        var c2 = UInt32(p[n >> 1])
        var c3 = UInt32(p[n - 1])
        var combined = (c1 << 16) | (c2 << 24) | c3 | (UInt32(n) << 8)
        var bitflip = UInt64(UInt32(secret64(0, 0)) ^ UInt32(secret64(4, 0))) + seed
        return avalanche64(UInt64(combined) ^ bitflip)
    if n <= 8:
        var mixed_seed = seed ^ (UInt64(swap32(UInt32(seed))) << 32)
        var input64 = UInt64(read32(p, n - 4)) + (UInt64(read32(p, 0)) << 32)
        var bitflip = (secret64(8, 0) ^ secret64(16, 0)) - mixed_seed
        return rrmxmx(input64 ^ bitflip, n)
    var input_lo = read64(p, 0) ^ ((secret64(24, 0) ^ secret64(32, 0)) + seed)
    var input_hi = read64(p, n - 8) ^ ((secret64(40, 0) ^ secret64(48, 0)) - seed)
    return avalanche3(UInt64(n) + swap64(input_lo) + input_hi + mul_fold(input_lo, input_hi))


def xxh3_mid(p: BPtr, n: Int, seed: UInt64) -> UInt64:
    var acc = UInt64(n) * P64_1
    if n <= 128:
        if n > 32:
            if n > 64:
                if n > 96:
                    acc += mix16(p, 48, 96, seed)
                    acc += mix16(p, n - 64, 112, seed)
                acc += mix16(p, 32, 64, seed)
                acc += mix16(p, n - 48, 80, seed)
            acc += mix16(p, 16, 32, seed)
            acc += mix16(p, n - 32, 48, seed)
        acc += mix16(p, 0, 0, seed)
        acc += mix16(p, n - 16, 16, seed)
        return avalanche3(acc)
    for i in range(8):
        acc += mix16(p, 16 * i, 16 * i, seed)
    var acc_end = mix16(p, n - 16, 136 - 17, seed)
    acc = avalanche3(acc)
    for i in range(8, n // 16):
        acc_end += mix16(p, 16 * i, 16 * (i - 8) + 3, seed)
    return avalanche3(acc + acc_end)


def accumulate[acc_origin: MutOrigin, secret_origin: MutOrigin](
    acc: UnsafePointer[UInt64, acc_origin],
    p: BPtr,
    input_offset: Int,
    secret_offset: Int,
    secret: UnsafePointer[UInt64, secret_origin],
):
    comptime W = simdwidthof[DType.float64]()
    var lane = 0
    while lane <= 8 - W:
        var data = (p + input_offset + lane * 8).bitcast[UInt64]().load[
            width=W, alignment=1
        ]()
        var secret_data = (
            secret.bitcast[UInt8]() + secret_offset + lane * 8
        ).bitcast[UInt64]().load[width=W, alignment=1]()
        var keyed = data ^ secret_data
        var values = acc.load[width=W](lane)
        values += data.shuffle[1, 0, 3, 2]() + (
            keyed & UInt64(0xFFFFFFFF)
        ) * (keyed >> 32)
        acc.store(lane, values)
        lane += W
    while lane < 8:
        var data = read64(p, input_offset + lane * 8)
        var keyed = data ^ secret64_from(
            secret, secret_offset + lane * 8
        )
        acc[lane ^ 1] += data
        acc[lane] += UInt64(UInt32(keyed)) * UInt64(UInt32(keyed >> 32))
        lane += 1


def scramble[acc_origin: MutOrigin, secret_origin: MutOrigin](
    acc: UnsafePointer[UInt64, acc_origin],
    secret: UnsafePointer[UInt64, secret_origin],
):
    comptime W = simdwidthof[DType.float64]()
    var lane = 0
    while lane <= 8 - W:
        var values = acc.load[width=W](lane)
        var secrets = (secret + 16 + lane).load[width=W]()
        values ^= values >> 47
        acc.store(lane, (values ^ secrets) * UInt64(P32_1))
        lane += W
    while lane < 8:
        var value = acc[lane]
        value ^= value >> 47
        value ^= secret[16 + lane]
        acc[lane] = value * UInt64(P32_1)
        lane += 1


def xxh3_long(p: BPtr, n: Int, seed: UInt64) -> UInt64:
    var secret: Array[UInt64, 24] = [
        0xBE4BA423396CFEB8, 0x1CAD21F72C81017C,
        0xDB979083E96DD4DE, 0x1F67B3B7A4A44072,
        0x78E5C0CC4EE679CB, 0x2172FFCC7DD05A82,
        0x8E2443F7744608B8, 0x4C263A81E69035E0,
        0xCB00C391BB52283C, 0xA32E531B8B65D088,
        0x4EF90DA297486471, 0xD8ACDEA946EF1938,
        0x3F349CE33F76FAA8, 0x1D4F0BC7C7BBDCF9,
        0x3159B4CD4BE0518A, 0x647378D9C97E9FC8,
        0xC3EBD33483ACC5EA, 0xEB6313FAFFA081C5,
        0x49DAF0B751DD0D17, 0x9E68D429265516D3,
        0xFCA1477D58BE162B, 0xCE31D07AD1B8F88F,
        0x280416958F3ACB45, 0x7E404BBBCAFBD7AF,
    ]
    if seed != 0:
        for i in range(24):
            if i % 2 == 0:
                secret[i] += seed
            else:
                secret[i] -= seed

    var secret_ptr = UnsafePointer(to=secret[0])
    var acc = Array[UInt64, 8](fill=0)
    acc[0] = UInt64(P32_3)
    acc[1] = P64_1
    acc[2] = P64_2
    acc[3] = P64_3
    acc[4] = P64_4
    acc[5] = UInt64(P32_2)
    acc[6] = P64_5
    acc[7] = UInt64(P32_1)
    var acc_ptr = UnsafePointer(to=acc[0])

    var block_len = 1024
    var blocks = (n - 1) // block_len
    for block in range(blocks):
        for stripe in range(16):
            accumulate(acc_ptr, p, block * block_len + stripe * 64, stripe * 8, secret_ptr)
        scramble(acc_ptr, secret_ptr)
    var stripes = ((n - 1) - block_len * blocks) // 64
    for stripe in range(stripes):
        accumulate(acc_ptr, p, blocks * block_len + stripe * 64, stripe * 8, secret_ptr)
    accumulate(acc_ptr, p, n - 64, 192 - 64 - 7, secret_ptr)

    var result = UInt64(n) * P64_1
    for i in range(4):
        result += mul_fold(
            acc[2 * i] ^ secret64_from(secret_ptr, 11 + 16 * i),
            acc[2 * i + 1] ^ secret64_from(secret_ptr, 19 + 16 * i),
        )
    return avalanche3(result)


def xxh3_impl(p: BPtr, n: Int, seed: UInt64) -> UInt64:
    if n <= 16:
        return xxh3_short(p, n, seed)
    if n <= 240:
        return xxh3_mid(p, n, seed)
    return xxh3_long(p, n, seed)


@export("mojo_xxh32")
def mojo_xxh32(addr: Int, n: Int, seed: UInt32) abi("C") -> UInt32:
    return xxh32_impl(BPtr(unsafe_from_address=addr), n, seed)


@export("mojo_xxh64")
def mojo_xxh64(addr: Int, n: Int, seed: UInt64) abi("C") -> UInt64:
    return xxh64_impl(BPtr(unsafe_from_address=addr), n, seed)


@export("mojo_xxh3_64")
def mojo_xxh3_64(addr: Int, n: Int, seed: UInt64) abi("C") -> UInt64:
    return xxh3_impl(BPtr(unsafe_from_address=addr), n, seed)
