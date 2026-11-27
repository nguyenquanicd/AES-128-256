#!/usr/bin/env python3
"""Independent AES-GCM / GMAC reference model for the AES-GCM accelerator testbench.

Written from NIST SP 800-38D (November 2007) only:
  * Algorithm 1 (block multiplication, 6.3), R = 11100001 || 0^120
  * Algorithm 2 (GHASH, 6.4)
  * Algorithm 3 (GCTR, 6.5) with inc32 (6.2)
  * Algorithm 4 (authenticated encryption, 7.1) with J0 = IV || 0^31 || 1 for a 96-bit IV
  * Algorithm 5 (authenticated decryption, 7.2), tag truncation MSB_t
The block cipher is the independent FIPS-197 model aes128_256_ref.enc_block (verification/
ht_aes128_256), which does not inspect RTL. Nothing in this file is derived from the RTL of the
accelerator (rule R-023).

Bit and byte conventions (spec section 9.1): a block is 16 bytes, byte 0 is the leftmost byte, bit
x0 of SP 800-38D is bit 7 of byte 0. Internally a block is a Python int with byte 0 in the most
significant position (int.from_bytes(block, "big")).

Self-test: python gcm_ref.py
  Test cases 1 to 4 (AES-128) and 13 to 16 (AES-256) of the GCM specification of McGrew and Viega
  (SP 800-38D reference [6]). NOTE: these vectors were written from the author's knowledge and
  were not copied from a downloaded file (DEP-003 needs the user's approval to download); a
  failing self-test means either the model or a transcribed vector is wrong and must be checked
  against the published document before the model is used.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "ht_aes128_256"))
import aes128_256_ref as aes  # noqa: E402  (independent FIPS-197 model)

MASK128 = (1 << 128) - 1
R_POLY = 0xE1 << 120          # R = 11100001 || 0^120 (SP 800-38D 6.3)
TAG_BITS = {0: 128, 1: 120, 2: 112, 3: 104, 4: 96}   # aesgcm_cfg.tag_len codes (spec 9.3)


def gf_mult(x: int, y: int) -> int:
    """SP 800-38D Algorithm 1: X . Y on 128-bit blocks (x0 is the MSB of the int)."""
    z = 0
    v = y
    for i in range(128):
        if (x >> (127 - i)) & 1:
            z ^= v
        if v & 1:
            v = (v >> 1) ^ R_POLY
        else:
            v >>= 1
    return z


def ghash(h: int, blocks: list[int], y0: int = 0) -> int:
    """SP 800-38D Algorithm 2 (optionally continued from a saved state y0)."""
    y = y0
    for x in blocks:
        y = gf_mult(y ^ x, h)
    return y


def inc32(cb: int) -> int:
    """SP 800-38D 6.2 inc_32: increment the rightmost 32 bits modulo 2^32."""
    return (cb & ~0xFFFFFFFF & MASK128) | ((cb + 1) & 0xFFFFFFFF)


def enc_int(key: bytes, block: int) -> int:
    return int.from_bytes(aes.enc_block(block.to_bytes(16, "big"), key), "big")


def gctr(key: bytes, icb: int, data: bytes) -> bytes:
    """SP 800-38D Algorithm 3: GCTR_K(ICB, X) for any byte length (partial last block)."""
    out = bytearray()
    cb = icb
    for off in range(0, len(data), 16):
        chunk = data[off:off + 16]
        ks = enc_int(key, cb).to_bytes(16, "big")
        out += bytes(a ^ b for a, b in zip(chunk, ks))
        cb = inc32(cb)
    return bytes(out)


def blocks_of(data: bytes) -> list[int]:
    """Split into 128-bit blocks, zero-padding the last one (SP 800-38D 7.1 step 4, u and v)."""
    res = []
    for off in range(0, len(data), 16):
        chunk = data[off:off + 16]
        res.append(int.from_bytes(chunk + bytes(16 - len(chunk)), "big"))
    return res


def length_block(aad_len: int, c_len: int) -> int:
    """[len(A)]64 || [len(C)]64 with bit lengths (spec 9.1 length block)."""
    return ((8 * aad_len) << 64) | (8 * c_len)


def j0_of(iv: bytes) -> int:
    if len(iv) != 12:
        raise ValueError("this model and the accelerator support only a 96-bit IV (REQ-FUNC-008)")
    return (int.from_bytes(iv, "big") << 32) | 1


def gcm_core(key: bytes, iv: bytes, aad: bytes, ctext: bytes) -> dict:
    """Common part: H, J0, E(K,J0), S and the full 128-bit tag over (A, C)."""
    h = enc_int(key, 0)
    j0 = j0_of(iv)
    ekj0 = enc_int(key, j0)
    y_aad = ghash(h, blocks_of(aad))
    s = ghash(h, blocks_of(ctext) + [length_block(len(aad), len(ctext))], y_aad)
    return {"H": h, "J0": j0, "EKJ0": ekj0, "Y_AAD": y_aad, "S": s, "T": ekj0 ^ s}


def gcm_encrypt(key: bytes, iv: bytes, ptext: bytes, aad: bytes) -> tuple[bytes, int]:
    """SP 800-38D Algorithm 4. Returns (C, full 128-bit T as int)."""
    j0 = j0_of(iv)
    ctext = gctr(key, inc32(j0), ptext)
    return ctext, gcm_core(key, iv, aad, ctext)["T"]


def gcm_decrypt(key: bytes, iv: bytes, ctext: bytes, aad: bytes, tag: int,
                t_bits: int = 128) -> tuple[bytes, bool, int]:
    """SP 800-38D Algorithm 5. Returns (P, tag match on MSB_t, full computed T).

    The plaintext is returned even when the tag fails, because the accelerator in policy C
    releases it before the comparison (REQ-FUNC-005); the caller decides what is expected."""
    j0 = j0_of(iv)
    ptext = gctr(key, inc32(j0), ctext)
    t_full = gcm_core(key, iv, aad, ctext)["T"]
    return ptext, msb(t_full, t_bits) == msb(tag, t_bits), t_full


def msb(t: int, t_bits: int) -> int:
    """MSB_t of a 128-bit tag."""
    return t >> (128 - t_bits)


def _hx(s: str) -> bytes:
    return bytes.fromhex(s.replace(" ", ""))


# McGrew-Viega GCM test cases (written from knowledge, see module docstring).
_P3 = ("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
       "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255")
_P4 = _P3[:120]
_A4 = "feedfacedeadbeeffeedfacedeadbeefabaddad2"
_K3 = "feffe9928665731c6d6a8f9467308308"
_IV3 = "cafebabefacedbaddecaf888"
KNOWN_ANSWERS = [
    # name, key, iv, plaintext, aad, ciphertext, tag
    ("TC1", "00" * 16, "00" * 12, "", "", "", "58e2fccefa7e3061367f1d57a4e7455a"),
    ("TC2", "00" * 16, "00" * 12, "00" * 16, "", "0388dace60b6a392f328c2b971b2fe78",
     "ab6e47d42cec13bdf53a67b21257bddf"),
    ("TC3", _K3, _IV3, _P3, "",
     "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e"
     "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985",
     "4d5c2af327cd64a62cf35abd2ba6fab4"),
    ("TC4", _K3, _IV3, _P4, _A4,
     "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e"
     "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091",
     "5bc94fbc3221a5db94fae95ae7121a47"),
    ("TC13", "00" * 32, "00" * 12, "", "", "", "530f8afbc74536b9a963b4f1c4cb738b"),
    ("TC14", "00" * 32, "00" * 12, "00" * 16, "", "cea7403d4d606b6e074ec5d3baf39d18",
     "d0d1c8a799996bf0265b98b5d48ab919"),
    ("TC15", _K3 * 2, _IV3, _P3, "",
     "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa"
     "8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad",
     "b094dac5d93471bdec1a502270e3cc6c"),
    ("TC16", _K3 * 2, _IV3, _P4, _A4,
     "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa"
     "8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662",
     "76fc6ece0f4e1768cddf8853bb2d551b"),
]


def self_test(verbose: bool = True) -> None:
    aes.self_test()
    # Algorithm 1 sanity: X . 1 (the block with x0 = 1, "one" of the field) equals X.
    one = 1 << 127
    assert gf_mult(0x0123456789ABCDEF0011223344556677, one) == 0x0123456789ABCDEF0011223344556677
    # Aggregated / feed-forward GHASH equivalence (spec 13.1, DEC-017) on 10 blocks, N = 4.
    h = 0x66E94BD4EF8A2C3B884CFA59CA342B2E
    xs = [(0x1111 * (i + 1)) << 100 | i for i in range(10)]
    ref = ghash(h, xs)
    h2 = gf_mult(h, h)
    h3 = gf_mult(h2, h)
    h4 = gf_mult(h3, h)
    hp = {1: h, 2: h2, 3: h3, 4: h4}
    y = 0
    for k0 in (0, 4, 8):
        batch = xs[k0:k0 + 4]
        k = len(batch)
        acc = 0
        for j, x in enumerate(batch):
            acc ^= gf_mult((y ^ x) if j == 0 else x, hp[k - j])
        y = acc
    assert y == ref, "aggregated GHASH differs from Algorithm 2"
    for name, k, iv, p, a, c, t in KNOWN_ANSWERS:
        key, ivb, pb, ab, cb, tb = _hx(k), _hx(iv), _hx(p), _hx(a), _hx(c), int(t, 16)
        c_out, t_out = gcm_encrypt(key, ivb, pb, ab)
        assert c_out == cb, f"{name}: ciphertext mismatch {c_out.hex()}"
        assert t_out == tb, f"{name}: tag mismatch {t_out:032x}"
        p_out, ok, _ = gcm_decrypt(key, ivb, cb, ab, tb)
        assert ok and p_out == pb, f"{name}: decryption failed"
        for t_bits in TAG_BITS.values():
            _, ok_t, _ = gcm_decrypt(key, ivb, cb, ab, tb ^ (1 << (128 - t_bits)), t_bits)
            assert not ok_t, f"{name}: flipped bit inside MSB_{t_bits} not detected"
            if t_bits < 128:
                _, ok_o, _ = gcm_decrypt(key, ivb, cb, ab, tb ^ (1 << (127 - t_bits)), t_bits)
                assert ok_o, f"{name}: bit outside MSB_{t_bits} must be ignored"
        if verbose:
            print(f"  {name}: PASS")


if __name__ == "__main__":
    self_test()
    print("GCM reference PASS: SP 800-38D Algorithms 1 to 5, test cases 1-4 and 13-16")
