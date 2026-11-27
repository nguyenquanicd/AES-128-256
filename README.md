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

### AES-GCM accelerator top level

The accelerator has two top modules in `rtl/ht_aes_gcm_acc/`. Both are structural, take the same parameters and differ only in the data window.

| Top | Interfaces | Use |
|---|---|---|
| `m_aesgcm_acc_apb_top` | APB4 completer (CSR and 32-bit programmed-I/O data port), DMA request/acknowledge handshake (input and output), one interrupt, key side-load, secure-only pin, DFT pins | Small MCU: all data goes through the APB port or the external DMA |
| `m_aesgcm_acc_axi_top` | Everything above plus an AXI4 subordinate data window (32, 64 or 128-bit data) | SoC subsystem: bulk data through AXI4 bursts |

Two clock domains: BUS (`i_clk_bus`, APB, AXI, DMA handshake, CSR) and CORE (`i_clk_core`, AES core and GCM datapath). `PARA_CLK_ASYNC` = 1 builds asynchronous crossings (Gray-code FIFOs, four-phase handshakes, reset synchronizers); 0 builds the cheaper related-clock crossings. Each domain has its own reset input.

```text
APB4 / AXI4 / DMA / IRQ / key side-load                    (BUS clock)
        |
  generated CSR (25 registers)  --  m_aesgcm_bus_dom: bus control, PIO path, 2 DMA channels, AXI window
        |
  m_aesgcm_xing: 5 bundle crossings (configuration, command, status, word request, word response)
                 + input and output data FIFOs                (clock-domain crossing)
        |
  m_aesgcm_core_dom                                           (CORE clock)
        sequencer, key select, input/output formatters, GHASH (+ H powers), tag unit,
        context slots / export  --  wraps the unchanged m_aes128_256_batch_top
```

| Parameter | Values (default) | Meaning |
|---|---|---|
| `PARA_AES_GCM_EN` | 0 or 1 (1) | 1 builds the GCM logic (GHASH, tag, J0, policies); 0 leaves a plain ECB/CBC/CFB/OFB/CTR accelerator |
| `PARA_AES_LANE_NUM` | 1 to 4 (1) | 128-bit AES block lanes processed in parallel |
| `PARA_GCM_REL_POLICY` | 0, 1 or 2 (0) | Plaintext release policy: 0 = A (verify the tag first in pass 1, release plaintext in pass 2), 1 = C (release as produced, tag checked at the end), 2 = both, selected per message |
| `PARA_GHASH_ARCH`, `PARA_GHASH_DIGIT_W`, `PARA_GHASH_PIPE` | 0 to 2 (1), 4 to 64 (16), 0 or 1 (0) | GHASH multiplier area/speed trade-off: digit-serial, single parallel or aggregated, digit width, feed-forward pipeline stage |
| `PARA_GCM_CTX_MODE`, `PARA_GCM_CTX_NUM` | 0 or 1 (0), 0 to 4 (2) | Suspend/resume context storage: internal slots, or export and import through the CSR |
| `PARA_KEY_SIDE_EN` | 0 or 1 (0) | Builds the key side-load port that lets an external key manager supply the key |
| `PARA_CLK_ASYNC` | 0 or 1 (1) | Asynchronous or related BUS and CORE clocks |
| `PARA_FIFO_DEPTH` | 8 to 256 (16) | Entries of each data FIFO |
| `PARA_AXI_DATA_W`, `PARA_AXI_ID_W`, `PARA_AXI_ADDR_W` | 32/64/128 (32), 1 to 8 (4), 12 to 32 (16) | AXI window widths (AXI top only) |

AES-128 or AES-256 is selected at run time through the registers. GCM supports 96-bit IVs and tags of 96 to 128 bits; the IV is supplied by software and the other authenticated modes (CCM, XTS, CMAC) are outside the scope. Illegal parameter values are reported by the verification-only checker `verification/ht_aes_gcm_acc/m_aesgcm_param_check.sv`. Details: the [specification](doc/ht_aes_gcm_acc/VLSIT_AES_GCM_ACCELERATOR_HDS.md) and the [RTL notes](rtl/ht_aes_gcm_acc/README.md).

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

### Top level của bộ tăng tốc AES-GCM

Bộ tăng tốc có hai module top trong `rtl/ht_aes_gcm_acc/`. Cả hai đều là module cấu trúc, cùng tham số và chỉ khác nhau ở cửa sổ dữ liệu.

| Top | Giao diện | Dùng cho |
|---|---|---|
| `m_aesgcm_acc_apb_top` | APB4 completer (CSR và cổng dữ liệu PIO 32 bit), handshake yêu cầu/xác nhận DMA (vào và ra), một ngắt, nạp key side-load, chân secure-only, chân DFT | MCU nhỏ: mọi dữ liệu đi qua cổng APB hoặc DMA ngoài |
| `m_aesgcm_acc_axi_top` | Toàn bộ phần trên cộng cửa sổ dữ liệu AXI4 subordinate (dữ liệu 32, 64 hoặc 128 bit) | Subsystem SoC: dữ liệu khối lớn qua burst AXI4 |

Hai miền clock: BUS (`i_clk_bus`, APB, AXI, handshake DMA, CSR) và CORE (`i_clk_core`, core AES và datapath GCM). `PARA_CLK_ASYNC` = 1 dựng các đường qua miền bất đồng bộ (FIFO mã Gray, handshake bốn pha, bộ đồng bộ reset); 0 dựng đường qua miền clock liên quan, rẻ hơn. Mỗi miền có chân reset riêng.

```text
APB4 / AXI4 / DMA / IRQ / key side-load                    (clock BUS)
        |
  CSR sinh tự động (25 thanh ghi)  --  m_aesgcm_bus_dom: điều khiển bus, đường PIO, 2 kênh DMA, cửa sổ AXI
        |
  m_aesgcm_xing: 5 đường qua miền (cấu hình, lệnh, trạng thái, yêu cầu word, đáp ứng word)
                 + FIFO dữ liệu vào và ra                     (qua miền clock)
        |
  m_aesgcm_core_dom                                           (clock CORE)
        sequencer, chọn key, bộ định dạng vào/ra, GHASH (+ lũy thừa H), khối tag,
        slot context / export  --  bao m_aes128_256_batch_top không sửa
```

| Tham số | Giá trị (mặc định) | Ý nghĩa |
|---|---|---|
| `PARA_AES_GCM_EN` | 0 hoặc 1 (1) | 1 dựng logic GCM (GHASH, tag, J0, policy); 0 chỉ còn bộ tăng tốc ECB/CBC/CFB/OFB/CTR |
| `PARA_AES_LANE_NUM` | 1 đến 4 (1) | Số lane AES 128 bit xử lý song song |
| `PARA_GCM_REL_POLICY` | 0, 1 hoặc 2 (0) | Chính sách nhả plaintext: 0 = A (pass 1 kiểm tag trước, pass 2 mới nhả plaintext), 1 = C (nhả ngay khi tạo ra, kiểm tag ở cuối), 2 = cả hai, chọn theo từng message |
| `PARA_GHASH_ARCH`, `PARA_GHASH_DIGIT_W`, `PARA_GHASH_PIPE` | 0 đến 2 (1), 4 đến 64 (16), 0 hoặc 1 (0) | Đánh đổi diện tích/tốc độ của bộ nhân GHASH: digit-serial, một bộ nhân song song hoặc gộp, độ rộng digit, tầng pipeline feed-forward |
| `PARA_GCM_CTX_MODE`, `PARA_GCM_CTX_NUM` | 0 hoặc 1 (0), 0 đến 4 (2) | Lưu context cho suspend/resume: slot nội bộ, hoặc export và import qua CSR |
| `PARA_KEY_SIDE_EN` | 0 hoặc 1 (0) | Dựng cổng key side-load để bộ quản lý key bên ngoài cấp key |
| `PARA_CLK_ASYNC` | 0 hoặc 1 (1) | Clock BUS và CORE bất đồng bộ hoặc liên quan |
| `PARA_FIFO_DEPTH` | 8 đến 256 (16) | Số entry của mỗi FIFO dữ liệu |
| `PARA_AXI_DATA_W`, `PARA_AXI_ID_W`, `PARA_AXI_ADDR_W` | 32/64/128 (32), 1 đến 8 (4), 12 đến 32 (16) | Độ rộng cửa sổ AXI (chỉ top AXI) |

AES-128 hoặc AES-256 được chọn khi chạy qua thanh ghi. GCM hỗ trợ IV 96 bit và tag 96 đến 128 bit; IV do phần mềm cấp, các chế độ xác thực khác (CCM, XTS, CMAC) nằm ngoài phạm vi. Giá trị tham số sai được báo bởi checker chỉ dùng cho verification `verification/ht_aes_gcm_acc/m_aesgcm_param_check.sv`. Chi tiết: [đặc tả](doc/ht_aes_gcm_acc/VLSIT_AES_GCM_ACCELERATOR_HDS.md) và [ghi chú RTL](rtl/ht_aes_gcm_acc/README.md).

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
