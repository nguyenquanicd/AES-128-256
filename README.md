# AES RTL Project

## English

This repository contains four AES RTL implementations. Each implementation has its own RTL, specification or design notes, and verification assets. The high-throughput designs use independent golden models and keep testbench code outside the RTL filelists.

| Design | RTL | Description | Specification / notes | Verification |
|---|---|---|---|---|
| Single-block AES-128 | `rtl/single_aes128/` | Iterative AES-128 core with ECB, CBC, CFB, OFB and CTR | [Design notes](doc/single_aes128/README.md) | [Single AES-128 verification](verification/single_aes128/README.md) |
| High-throughput AES-128 | `rtl/ht_aes128/` | Pipelined, parameterized batch core for AES-128 | [AES-128 specification](doc/ht_aes128/AES128_ECB_CBC_CFB_OFB_CTR_Design_Specification.md) | [HT AES-128 verification](verification/ht_aes128/README.md) |
| High-throughput AES-128/AES-256 | `rtl/ht_aes128_256/` | Pipelined batch core with run-time AES-128/AES-256 selection | [AES-128/AES-256 specification](doc/ht_aes128_256/AES128_AES256_ECB_CBC_CFB_OFB_CTR_Design_Specification.md) | [Dual-key verification](verification/ht_aes128_256/README.md) |
| AES-GCM accelerator | `rtl/ht_aes_gcm_acc/` | APB4 / AXI4 / DMA accelerator that wraps the dual-key core and adds AES-GCM and GMAC, enabled by `PARA_AES_GCM_EN` (all six legacy modes stay available) | [AES-GCM specification](doc/ht_aes_gcm_acc/VLSIT_AES_GCM_ACCELERATOR_HDS.md), [RTL notes](rtl/ht_aes_gcm_acc/README.md) | [AES-GCM verification](verification/ht_aes_gcm_acc/README.md) |

The AES-GCM accelerator is on the branch `feature/aes-gcm-acc`. Its status: specification check PASS; RTL rule check and Verilator lint PASS, scratch simulations against an independent GCM model PASS; the specification-based testbench (107 assertions, plan, fault plan) is written but **has not been built or run yet**, so there are no regression, coverage, CDC or synthesis results for it.

## Repository layout

```text
doc/
  single_aes128/       Single-block AES-128 design notes and legacy documents
  ht_aes128/           AES-128 batch specification, figures, waveforms, research
  ht_aes128_256/       Dual-key specification, figures, waveforms, research
  ht_aes_gcm_acc/      AES-GCM accelerator specification, CSR workbook, FSM figures, waveforms
  shared/references/   Local NIST FIPS 197 and SP 800-38A copies
rtl/
  single_aes128/       Iterative AES-128 RTL
  ht_aes128/           High-throughput AES-128 RTL
  ht_aes128_256/       High-throughput AES-128/AES-256 RTL
  ht_aes_gcm_acc/      AES-GCM accelerator RTL (27 modules, generated CSR, filelist)
verification/
  single_aes128/       Legacy core tests, formal harnesses and simulation scripts
  ht_aes128/           Batch testbench, vectors, logs and waveform evidence
  ht_aes128_256/       Dual-key testbench, vectors, logs, waveforms and synthesis
  ht_aes_gcm_acc/      AES-GCM testbench, vectors, test and fault plans (not run yet)
  shared/              Independent AES reference model used by the flows
  legacy_uart_apb/     Preserved UART/APB files unrelated to the AES designs
Makefile              Main entry point for the AES-128 flows
```

## Commands

Run commands from the repository root. GNU Make and the listed tools must be available.

```sh
make quick                    # Single-block AES-128 simulation suite
make regress                  # Single-block AES-128 full regression
make formal                   # Single-block AES-128 formal checks
make vlsit-verification       # High-throughput AES-128 simulation and waveform checks
make aes128-256-regression    # Dual-key simulation, 1 and 4 lanes
make aes128-256-synth         # Dual-key generic synthesis, 1 and 4 lanes
make aes128-256-verification  # Dual-key regression, waveforms and synthesis
```

The root `Makefile` is the entry point for the three AES core designs. The AES-GCM accelerator has no Make target yet: its Verilator build and run commands are in [`verification/ht_aes_gcm_acc/README.md`](verification/ht_aes_gcm_acc/README.md). Generic synthesis statistics are not ASIC area, timing or power results; a target library, corner and timing constraints are required for those measurements.

## Tiếng Việt

Repository này có bốn cách cài đặt AES RTL. Mỗi design có RTL, đặc tả hoặc tài liệu mô tả và tài nguyên verification riêng. Các design throughput cao dùng mô hình tham chiếu độc lập; testbench không nằm trong filelist RTL.

| Design | RTL | Mô tả | Đặc tả / tài liệu | Verification |
|---|---|---|---|---|
| AES-128 một block | `rtl/single_aes128/` | Core AES-128 tuần tự, hỗ trợ ECB, CBC, CFB, OFB và CTR | [Tài liệu design](doc/single_aes128/README.md) | [Verification AES-128 đơn](verification/single_aes128/README.md) |
| AES-128 throughput cao | `rtl/ht_aes128/` | Batch core AES-128 có pipeline và số lane cấu hình được | [Đặc tả AES-128](doc/ht_aes128/AES128_ECB_CBC_CFB_OFB_CTR_Design_Specification.md) | [Verification HT AES-128](verification/ht_aes128/README.md) |
| AES-128/AES-256 throughput cao | `rtl/ht_aes128_256/` | Batch core pipeline, chọn AES-128 hoặc AES-256 khi chạy | [Đặc tả AES-128/AES-256](doc/ht_aes128_256/AES128_AES256_ECB_CBC_CFB_OFB_CTR_Design_Specification.md) | [Verification hai kích thước khóa](verification/ht_aes128_256/README.md) |
| Bộ tăng tốc AES-GCM | `rtl/ht_aes_gcm_acc/` | Bộ tăng tốc APB4 / AXI4 / DMA bao core hai key size, thêm AES-GCM và GMAC, bật bằng `PARA_AES_GCM_EN` (sáu mode cũ vẫn dùng được) | [Đặc tả AES-GCM](doc/ht_aes_gcm_acc/VLSIT_AES_GCM_ACCELERATOR_HDS.md), [Ghi chú RTL](rtl/ht_aes_gcm_acc/README.md) | [Verification AES-GCM](verification/ht_aes_gcm_acc/README.md) |

Bộ tăng tốc AES-GCM nằm trên nhánh `feature/aes-gcm-acc`. Trạng thái: kiểm tra đặc tả PASS; rule check RTL và lint Verilator PASS, mô phỏng scratch với mô hình GCM độc lập PASS; testbench theo đặc tả (107 assertion, kế hoạch test và fault) đã viết nhưng **chưa build và chưa chạy**, nên chưa có kết quả regression, coverage, CDC hay synthesis.

## Cấu trúc repository

```text
doc/
  single_aes128/       Tài liệu AES-128 một block và tài liệu cũ
  ht_aes128/           Đặc tả, hình, waveform và nghiên cứu cho batch AES-128
  ht_aes128_256/       Đặc tả, hình, waveform và nghiên cứu cho batch AES-128/AES-256
  ht_aes_gcm_acc/      Đặc tả bộ tăng tốc AES-GCM, workbook CSR, hình FSM, waveform
  shared/references/   Bản NIST FIPS 197 và SP 800-38A lưu trong dự án
rtl/
  single_aes128/       RTL AES-128 tuần tự
  ht_aes128/           RTL AES-128 throughput cao
  ht_aes128_256/       RTL AES-128/AES-256 throughput cao
  ht_aes_gcm_acc/      RTL bộ tăng tốc AES-GCM (27 module, CSR sinh tự động, filelist)
verification/
  single_aes128/       Test, formal harness và script mô phỏng core cũ
  ht_aes128/           Testbench batch, vector, log và waveform
  ht_aes128_256/       Testbench hai key size, vector, log, waveform và synthesis
  ht_aes_gcm_acc/      Testbench AES-GCM, vector, kế hoạch test và fault (chưa chạy)
  shared/              Mô hình AES tham chiếu độc lập dùng chung
  legacy_uart_apb/     Tệp UART/APB cũ, không thuộc các AES design
Makefile              Điểm chạy chính cho các flow AES-128
```

## Lệnh chạy

Chạy lệnh từ thư mục gốc repository. Cần GNU Make và các tool tương ứng.

```sh
make quick                    # Bộ simulation AES-128 tuần tự
make regress                  # Regression đầy đủ AES-128 tuần tự
make formal                   # Formal check AES-128 tuần tự
make vlsit-verification       # Simulation và waveform check AES-128 throughput cao
make aes128-256-regression    # Simulation dual-key, 1 và 4 lane
make aes128-256-synth         # Yosys generic synthesis, 1 và 4 lane
make aes128-256-verification  # Regression, waveform và synthesis dual-key
```

Root `Makefile` là điểm chạy lệnh cho ba design lõi AES. Bộ tăng tốc AES-GCM chưa có target Make: lệnh build và chạy Verilator nằm trong [`verification/ht_aes_gcm_acc/README.md`](verification/ht_aes_gcm_acc/README.md). Số liệu synthesis generic không phải diện tích, timing hay công suất ASIC; cần thư viện cell, corner và ràng buộc timing cho các phép đo đó.
