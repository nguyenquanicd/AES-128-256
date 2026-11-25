# Reference IP research log: AES-GCM accelerator

Date: 2026-11-25. Rules: R-010 (evidence filter), R-011 (Chinese sources), R-012 (no copying), R-009 (no download without approval).

## Queries and sources

| Source | Query | Result |
|---|---|---|
| GitHub (`vlsit_ip_search.py`) | `aes gcm verilog`, `aes-gcm ghash hardware accelerator rtl`, `ghash multiplier verilog GF(2^128)` | Failed: GitHub API returned HTTP 403 (unauthenticated rate limit); no candidates from the script |
| Gitee (`vlsit_ip_search.py`) | `AES-GCM verilog` | 0 candidates |
| Web search (standard) | OpenTitan AES GCM; open-source AES-GCM Verilog core with testbench; commercial AES-GCM IP datasheets | See table below |
| Chinese-language sources | Gitee search above | None found; no Chinese page was read (confidence: not applicable) |

## Candidates

| Candidate | Direction | Evidence | Licence | Decision |
|---|---|---|---|---|
| OpenTitan AES unit (`opentitan.org/book/hw/ip/aes`) | Build parameter enables GCM in hardware; GHASH module runs in parallel with the cipher core; phases ECB (hash subkey), CTR (payload), GHASH-only (AAD); 96-bit IV and 128-bit tag; context save and restore; first-order masking option | Public documentation; open verification environment and FPGA use are documented by the project; silicon evidence for the hardware-GCM version was not confirmed in this run (the Earl Grey 1.0.0 documentation still describes software GHASH) | Apache-2.0 (project statement, not re-verified in this run) | USED for ideas only: parameter-selected GCM, GHASH parallel to the cipher, setup/payload/AAD phases, context save/restore. Evidence level: medium |
| BLu85/AES-GCM-128-192-256-bits | Configurable AES-GCM IP, 128 to 12.8 bit/clk size options, optional key expansion, cocotb testbench with a software golden model | `vlsit_ip_search.py evaluate`: QUALIFIED, score 3 (FPGA and verification evidence); README read | Apache-2.0 (LICENSE file read) | USED for ideas only: size/throughput configurations, pre-expanded key option, software-model testbench. Evidence level: medium |
| secworks/aes | AES core only (no GCM) | Testbench via FuseSoC | BSD-2-Clause (mirror listing) | EXCLUDED: no GCM function |
| CAST, Rambus (AES-IP-61), Synopsys, Xiphera, Helion cores | Commercial AES-GCM with separate CTR and GHASH pipelines, up to hundreds of Gb/s | Vendor datasheets and product pages only | Commercial | EXCLUDED as design reference (not open, figures are vendor claims); used only to confirm that the CTR and GHASH pipelines are separated in high-rate products |

## Findings that shaped the specification

1. A parameter that removes GHASH and mode 5 entirely (OpenTitan style) keeps the area of non-GCM builds unchanged: `PARA_AES_GCM_EN`.
2. GHASH is independent of the cipher after the hash subkey exists, so it can run in parallel with the CTR stage: used in the sequencer (section 5.3).
3. The standard permits the aggregated form $X_1 H^m \oplus \cdots \oplus X_m H$ (SP 800-38D 6.4), which allows a GHASH rate equal to the lane count.
4. SP 800-38D 7.2 allows verification before plaintext computation; this is the basis of policy A.
5. Context export through registers conflicts with SP 800-38D 5.3 (intermediate values secret); the specification blocks it with `i_gcm_secure_only` and keeps internal slots as the default.

No text or code of any candidate is copied (rule R-012). Nothing was downloaded from GitHub or Gitee. The SP 800-38D PDF was downloaded with the user's approval (271,960 bytes, SHA-256 `d99f3921ccebca049e7522426553aba071dae14ec3d5b6041e8c111a6cb57bba`).
