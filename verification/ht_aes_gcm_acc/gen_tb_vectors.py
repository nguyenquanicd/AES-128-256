#!/usr/bin/env python3
"""Vector generator of the AES-GCM accelerator testbench (rule R-023: expected values come from
the independent models gcm_ref.py and aes128_256_ref.py, never from the DUT).

Usage:
  python gen_tb_vectors.py [--out vectors] [--seed 1]

Writes one file vectors/<ID>.hex per testcase and per WF scenario, read by the testbench with
$readmemh. Format (one 32-bit hexadecimal word per line):

  word 0          number of records N
  then N records, each:
    w0  magic 0xA5C30001
    w1  record length in words (header of 32 words + data words)
    w2  mode code (spec 9.3: 0 ECB, 1 CBC, 2 CFB, 3 OFB, 4 CTR, 5 GCM)
    w3  decipher (0 encrypt, 1 decrypt)
    w4  key size (0 AES-128, 1 AES-256)
    w5  tag length code (0 = 128 ... 4 = 96)
    w6  CFB segment code (0 = 1 bit ... 7 = 128 bit)
    w7  AAD length in bytes
    w8  payload length in bytes (aesgcm_datalen)
    w9  expected tag comparison result (decryption): 1 match, 0 mismatch
    w10 message kind (informative, see KIND below)
    w11 action code (see ACTION below)
    w12..w19  key words in CSR format (aesgcm_key_k: bytes 4k..4k+3, byte 4k at bits [7:0])
    w20..w23  IV words in CSR format (aesgcm_iv_k); word 3 is random for GCM (ignored, REQ-FUNC-008)
    w24..w27  tag to program in aesgcm_tagin_k (decryption) - may be forged
    w28..w31  full 128-bit tag T computed by the model over (A, C) in CSR format (tag byte 0 =
              leftmost byte of T, spec 9.1); the expected aesgcm_tagout_k value
    then ceil(aad/4) AAD words, ceil(len/4) input stream words, ceil(len/4) expected output
    words; bytes packed little-endian in a word (first stream byte at bits [7:0], spec 9.1).

The record set of each ID is fixed: the testbench refers to records by index (see the testcase
headers in tb_aesgcm_tests.svh and tb_aesgcm_wf.svh).
"""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "ht_aes128_256"))
import gcm_ref  # noqa: E402
import aes128_256_ref as aes  # noqa: E402

MAGIC = 0xA5C30001
HDR = 32
MODE = {"ECB": 0, "CBC": 1, "CFB": 2, "OFB": 3, "CTR": 4, "GCM": 5}
SEG_BITS = (1, 2, 4, 8, 16, 32, 64, 128)
# Action codes interpreted by the testbench (task run_record).
ACTION = {
    "none": 0,
    "len_err": 1,        # program as given, expect LEN_ERR (ERR-002)
    "mode6": 2,          # override aesgcm_cfg.mode = 6, expect CFG_ERR (ERR-001)
    "aad_legacy": 3,     # override aesgcm_aadlen = 16 in a legacy mode, expect CFG_ERR (ERR-001)
    "seg9": 4,           # override aesgcm_cfg.cfb_seg = 9, expect CFG_ERR (ERR-001)
    "tag5": 5,           # override aesgcm_cfg.tag_len = 5, expect CFG_ERR (ERR-001)
    "pass3": 6,          # override aesgcm_cfg.gcm_pass = 3, expect CFG_ERR (ERR-001)
}
KIND = {"enc": 0, "dec_ok": 1, "dec_forged_tag": 2, "dec_ct_mod": 3, "legacy": 4, "kat": 5,
        "dec_tag_out_of_t": 6, "dec_tag_in_t": 7}


def words_le(data: bytes) -> list[int]:
    pad = data + bytes((-len(data)) % 4)
    return [int.from_bytes(pad[i:i + 4], "little") for i in range(0, len(pad), 4)]


def tag_words(t: int) -> list[int]:
    return words_le(t.to_bytes(16, "big"))


class Rec:
    def __init__(self, **kw):
        self.mode = kw["mode"]
        self.dec = kw.get("dec", 0)
        self.ksz = kw.get("ksz", 0)
        self.tlc = kw.get("tlc", 0)
        self.seg = kw.get("seg", 7)
        self.key = kw["key"]
        self.iv = kw["iv"]               # 16 bytes as written to aesgcm_iv_0..3
        self.aad = kw.get("aad", b"")
        self.inp = kw.get("inp", b"")
        self.exp = kw.get("exp", b"")
        self.tagin = kw.get("tagin", 0)
        self.tagexp = kw.get("tagexp", 0)
        self.expok = kw.get("expok", 1)
        self.kind = kw.get("kind", 0)
        self.action = kw.get("action", 0)

    def encode(self) -> list[int]:
        keyb = self.key + bytes(32 - len(self.key))
        body = words_le(self.aad) + words_le(self.inp) + words_le(self.exp)
        hdr = [MAGIC, HDR + len(body), self.mode, self.dec, self.ksz, self.tlc, self.seg,
               len(self.aad), len(self.inp), self.expok, self.kind, self.action]
        hdr += words_le(keyb) + words_le(self.iv) + tag_words(self.tagin) + tag_words(self.tagexp)
        assert len(hdr) == HDR
        return hdr + body


class Gen:
    def __init__(self, seed: int):
        self.rng = random.Random(seed)

    def rb(self, n: int) -> bytes:
        return bytes(self.rng.getrandbits(8) for _ in range(n))

    def key(self, ksz: int) -> bytes:
        return self.rb(32 if ksz else 16)

    # ---------------------------------------------------------------- GCM records
    def gcm(self, dec: int, ksz: int, tlc: int, aad_len: int, dlen: int, key: bytes | None = None,
            iv: bytes | None = None, forge: str | None = None, action: int = 0) -> Rec:
        key = key if key is not None else self.key(ksz)
        iv12 = iv if iv is not None else self.rb(12)
        iv16 = iv12 + self.rb(4)            # aesgcm_iv_3 random: ignored in GCM (REQ-FUNC-008)
        aad = self.rb(aad_len)
        ptext = self.rb(dlen)
        ctext, t = gcm_ref.gcm_encrypt(key, iv12, ptext, aad)
        t_bits = gcm_ref.TAG_BITS.get(tlc, 128)
        if not dec:
            return Rec(mode=5, dec=0, ksz=ksz, tlc=tlc, key=key, iv=iv16, aad=aad, inp=ptext,
                       exp=ctext, tagin=0, tagexp=t, expok=1, kind=KIND["enc"], action=action)
        cin = ctext
        tagin = t
        kind = KIND["dec_ok"]
        if forge == "tag_in":               # flip the leftmost tag bit (inside MSB_t)
            tagin = t ^ (1 << 127)
            kind = KIND["dec_forged_tag"]
        elif forge == "tag_last_in":        # flip the last bit inside MSB_t
            tagin = t ^ (1 << (128 - t_bits))
            kind = KIND["dec_tag_in_t"]
        elif forge == "tag_out":            # flip the first bit outside MSB_t (ignored)
            if t_bits < 128:
                tagin = t ^ (1 << (127 - t_bits))
            kind = KIND["dec_tag_out_of_t"]
        elif forge == "ct" and dlen > 0:    # ciphertext modified (e.g. between policy A passes)
            b = bytearray(ctext)
            b[dlen // 2] ^= 0x01
            cin = bytes(b)
            kind = KIND["dec_ct_mod"]
        ptext_out, ok, t_calc = gcm_ref.gcm_decrypt(key, iv12, cin, aad, tagin, t_bits)
        return Rec(mode=5, dec=1, ksz=ksz, tlc=tlc, key=key, iv=iv16, aad=aad, inp=cin,
                   exp=ptext_out, tagin=tagin, tagexp=t_calc, expok=int(ok), kind=kind,
                   action=action)

    def kat(self, name: str) -> Rec:
        for nm, k, iv, p, a, c, t in gcm_ref.KNOWN_ANSWERS:
            if nm == name:
                key = bytes.fromhex(k)
                return Rec(mode=5, dec=0, ksz=int(len(key) == 32), tlc=0, key=key,
                           iv=bytes.fromhex(iv) + bytes(4), aad=bytes.fromhex(a),
                           inp=bytes.fromhex(p), exp=bytes.fromhex(c), tagexp=int(t, 16),
                           kind=KIND["kat"])
        raise KeyError(name)

    # ---------------------------------------------------------------- legacy records
    def legacy(self, mode: str, dec: int, ksz: int, dlen: int, seg: int = 7,
               key: bytes | None = None, action: int = 0) -> Rec:
        key = key if key is not None else self.key(ksz)
        iv = self.rb(16)
        iv_int = int.from_bytes(iv, "big")
        data = self.rb(dlen)
        out = bytearray()
        if mode in ("ECB", "CBC"):
            nfull = dlen // 16
            blocks = [int.from_bytes(data[16 * i:16 * i + 16], "big") for i in range(nfull)]
            recs = aes.run_stream(mode, dec, key, iv_int, blocks) if blocks else []
            for _, o, _ in recs:
                out += o.to_bytes(16, "big")
            out += bytes(dlen - len(out))   # LEN_ERR records only: tail not produced
        elif mode == "CFB":
            bits = SEG_BITS[seg]
            if bits < 8:
                # DEC-021: one stream byte per segment, left-justified in bits [7:8-s]
                vals = [b << 120 for b in data]
                recs = aes.run_stream("CFB", dec, key, iv_int, vals, seg=seg)
                for _, o, _ in recs:
                    out.append((o >> 120) & 0xFF)
            else:
                nb = bits // 8
                assert dlen % nb == 0, "CFB records use whole segments (open question Q-12)"
                vals = [int.from_bytes(data[i:i + nb], "big") << (128 - bits)
                        for i in range(0, dlen, nb)]
                recs = aes.run_stream("CFB", dec, key, iv_int, vals, seg=seg)
                for _, o, _ in recs:
                    out += (o >> (128 - bits)).to_bytes(nb, "big")
        else:  # OFB, CTR: partial last block is truncated keystream XOR
            blocks = []
            for i in range(0, dlen, 16):
                chunk = data[i:i + 16]
                blocks.append(int.from_bytes(chunk + bytes(16 - len(chunk)), "big"))
            recs = aes.run_stream(mode, dec, key, iv_int, blocks, ctr_width=32) if blocks else []
            for _, o, _ in recs:
                out += o.to_bytes(16, "big")
            out = out[:dlen]
        return Rec(mode=MODE[mode], dec=dec, ksz=ksz, tlc=0, seg=seg, key=key, iv=iv,
                   inp=data, exp=bytes(out), kind=KIND["legacy"], action=action)


def build_sets(g: Gen) -> dict[str, list[Rec]]:
    s: dict[str, list[Rec]] = {}
    # ---------------------------------------------------------------- integrated testcases
    r0 = g.gcm(1, 1, 0, 32, 512)
    r1 = Rec(**vars(r0))
    b = bytearray(r0.inp)
    b[256] ^= 0x01
    r1.inp = bytes(b)
    p1, ok1, t1 = gcm_ref.gcm_decrypt(r0.key, r0.iv[:12], r1.inp, r0.aad, r0.tagin, 128)
    r1.exp, r1.expok, r1.tagexp, r1.kind = p1, int(ok1), t1, KIND["dec_ct_mod"]
    s["TC-01"] = [r0, r1]
    k = g.key(0)
    s["TC-02"] = [g.gcm(1, 0, 0, 16, 280, key=k, forge="tag_in"), g.gcm(1, 0, 0, 16, 280, key=k)]
    s["TC-03"] = [g.gcm(1, 0, 0, 8, 64)]
    keys = [g.key(0) for _ in range(5)]
    tc4 = [g.gcm(0, 0, c, 20, 33, key=keys[c]) for c in range(5)]
    tc4 += [g.gcm(1, 0, c, 20, 33, key=keys[c], forge="tag_out") for c in range(5)]
    tc4 += [g.gcm(1, 0, c, 20, 33, key=keys[c], forge="tag_last_in") for c in range(5)]
    s["TC-04"] = tc4
    tc5 = [g.kat(n) for n in ("TC1", "TC2", "TC3", "TC4", "TC13", "TC14", "TC15", "TC16")]
    i = 0
    for alen in (0, 1, 15, 16, 17, 33):
        for dlen in (0, 1, 15, 16, 17, 31, 32, 33):
            tc5.append(g.gcm(0, i % 2, i % 5, alen, dlen))
            i += 1
    s["TC-05"] = tc5
    s["TC-06"] = [g.gcm(0, 0, 0, 32, 96), g.gcm(0, 1, 0, 8, 40)]
    s["TC-07"] = [g.gcm(0, 0, 0, 64, 48), g.gcm(1, 0, 0, 16, 128), g.gcm(0, 0, 0, 0, 16)]
    k8 = g.key(0)
    s["TC-08"] = [g.gcm(0, 0, 0, 16, 2048, key=k8), g.gcm(0, 0, 0, 16, 64, key=k8),
                  g.gcm(0, 1, 0, 0, 32)]
    s["TC-09"] = [g.gcm(0, 1, 0, 40, 2048)]
    s["TC-10"] = [g.gcm(0, 0, 0, 24, 200), g.legacy("CBC", 0, 1, 256), g.gcm(1, 0, 0, 0, 100),
                  g.legacy("CTR", 0, 0, 77)]
    tc11 = []
    for ksz in (0, 1):
        for dec in (0, 1):
            tc11.append(g.legacy("ECB", dec, ksz, 64))
            tc11.append(g.legacy("CBC", dec, ksz, 80))
            tc11.append(g.legacy("OFB", dec, ksz, 37))
            tc11.append(g.legacy("CTR", dec, ksz, 45))
    for seg in range(8):
        tc11.append(g.legacy("CFB", 0, seg % 2, 32, seg=seg))
        tc11.append(g.legacy("CFB", 1, (seg + 1) % 2, 32, seg=seg))
    tc11.append(g.legacy("ECB", 0, 0, 20, action=ACTION["len_err"]))
    tc11.append(g.legacy("CTR", 0, 0, 0, action=ACTION["len_err"]))
    tc11.append(g.legacy("CBC", 0, 0, 32, action=ACTION["mode6"]))
    tc11.append(g.legacy("CTR", 0, 0, 32, action=ACTION["aad_legacy"]))
    tc11.append(g.legacy("CFB", 0, 0, 32, seg=3, action=ACTION["seg9"]))
    tc11.append(g.legacy("CBC", 1, 1, 48))   # recovery record after the errors
    s["TC-11"] = tc11
    s["TC-12"] = [g.legacy("ECB", 0, 0, 16)]
    s["TC-13"] = [g.gcm(0, 0, 0, 16, 1024), g.gcm(0, 0, 0, 16, 64)]
    s["TC-14"] = [g.gcm(0, 0, 0, 20, 70), g.gcm(1, 1, 0, 13, 129), g.legacy("CTR", 0, 0, 48)]
    s["TC-15"] = [g.gcm(0, 1, 0, 16, 280), g.gcm(0, 0, 0, 0, 1024)]
    # ---------------------------------------------------------------- focused testcases
    s["FT-012"] = [g.gcm(0, 0, 0, 64, 256), g.gcm(0, 0, 0, 16, 32)]
    s["FT-028"] = [g.gcm(0, 0, 0, 64, 256), g.gcm(0, 0, 0, 16, 32)]
    s["FT-013"] = [g.legacy("ECB", 0, 0, 32)]
    s["FT-014"] = [g.gcm(0, 1, 0, 16, 32), g.gcm(0, 0, 0, 16, 32)]
    s["FT-015"] = [g.gcm(i % 2, (i // 2) % 2, i % 5, 7 * i, 23 * i + 1) for i in range(10)]
    s["FT-016"] = []
    s["FT-018"] = [g.gcm(0, 0, 0, 0, 4096)]
    s["FT-026"] = [g.gcm(1, 0, 0, 16, 32), g.gcm(0, 0, 0, 0, 1024),
                   g.gcm(0, 0, 0, 0, 16, action=ACTION["tag5"]),
                   g.gcm(1, 0, 0, 0, 16, action=ACTION["pass3"])]
    kf = g.key(0)
    s["FT-029"] = [g.gcm(1, 0, 0, 8, 48, key=kf, forge="tag_in") for _ in range(4)]
    s["FT-030"] = [g.gcm(0, 0, 0, 0, 160)]
    s["FT-031"] = [g.gcm(0, 0, 0, 20, 70)]
    s["FT-033"] = [g.legacy("CTR", 0, 0, 20)]
    # ---------------------------------------------------------------- waveform scenarios
    s["WF-001"] = [g.gcm(0, 0, 0, 16, 32)]
    s["WF-002"] = [g.gcm(0, 0, 0, 16, 32)]
    s["WF-003"] = [g.gcm(1, 0, 0, 16, 32, forge="tag_in")]
    s["WF-004"] = [g.gcm(1, 0, 0, 16, 32)]
    s["WF-005"] = [g.gcm(1, 0, 0, 16, 32)]
    s["WF-006"] = [g.gcm(0, 0, 0, 0, 8192)]
    s["WF-007"] = [g.gcm(0, 0, 0, 0, 32)]
    s["WF-008"] = [g.gcm(0, 0, 0, 0, 32)]
    s["WF-009"] = [g.gcm(0, 0, 0, 0, 128)]
    s["WF-010"] = [g.gcm(0, 0, 0, 0, 4096)]
    s["WF-011"] = [g.gcm(0, 1, 0, 0, 16), g.gcm(0, 1, 0, 0, 16)]
    s["WF-012"] = [g.gcm(0, 0, 0, 16, 96)]
    s["WF-013"] = [g.gcm(0, 0, 0, 0, 1024)]
    s["WF-014"] = [g.gcm(0, 0, 0, 0, 1024)]
    s["WF-015"] = [g.legacy("ECB", 0, 0, 16)]
    s["WF-016"] = [g.gcm(0, 0, 0, 0, 16)]
    s["WF-017"] = [g.gcm(0, 0, 0, 0, 112)]
    s["WF-018"] = [g.gcm(0, 0, 0, 0, 1024)]
    s["WF-019"] = [g.legacy("CTR", 0, 0, 16)]
    s["WF-020"] = [g.gcm(0, 0, 0, 16, 0)]
    s["WF-021"] = [g.gcm(0, 0, 0, 16, 96)]
    s["WF-022"] = [g.gcm(0, 0, 0, 0, 160)]
    s["WF-023"] = [g.gcm(0, 0, 0, 0, 1024)]
    return s


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=str(HERE / "vectors"))
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    gcm_ref.self_test(verbose=False)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    sets = build_sets(Gen(args.seed))
    for name, recs in sets.items():
        words = [len(recs)]
        for r in recs:
            words += r.encode()
        assert len(words) <= 65536, f"{name}: vector memory overflow"
        (out / f"{name}.hex").write_text("".join(f"{w:08x}\n" for w in words))
    print(f"wrote {len(sets)} vector files to {out} (seed {args.seed})")


if __name__ == "__main__":
    main()
