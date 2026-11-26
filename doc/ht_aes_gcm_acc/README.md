# AES-GCM Accelerator Specification

## English

Draft design specification (version 0.1) of an APB/AXI4/DMA accelerator that adds AES-GCM and GMAC to the `ht_aes128_256` core, with the build parameter `PARA_AES_GCM_EN` to enable or disable GCM. The RTL is in [`rtl/ht_aes_gcm_acc`](../../rtl/ht_aes_gcm_acc/README.md); the original specification before the RTL is the git tag `aes-gcm-hds-v0.1`.

| File | Content |
|---|---|
| `VLSIT_AES_GCM_ACCELERATOR_HDS.md` | Authoritative specification (22 sections) |
| `aesgcm_CSR.xlsx`, `aesgcm_regs.json` | Register workbook and its JSON source (prefix `aesgcm`, validated by `vlsit_csr_tool.py`) |
| `figures/` | Block diagram, FSM diagrams and 21 waveforms with their draw.io, JSON and WaveJSON sources |
| `research/vlsit_reference_ip_log.md` | Reference IP research log |

The GCM statements cite NIST SP 800-38D (November 2007), converted to Markdown in the specification skill (`vlsit_nist_sp800_38d_gcm_gmac.md`). Open items are in section 20 of the specification.

## Tiếng Việt

Bản nháp đặc tả (phiên bản 0.1) của bộ tăng tốc APB/AXI4/DMA bổ sung AES-GCM và GMAC cho core `ht_aes128_256`, có tham số build `PARA_AES_GCM_EN` để bật hoặc tắt GCM. RTL nằm ở [`rtl/ht_aes_gcm_acc`](../../rtl/ht_aes_gcm_acc/README.md); bản đặc tả gốc trước RTL là git tag `aes-gcm-hds-v0.1`.

| Tệp | Nội dung |
|---|---|
| `VLSIT_AES_GCM_ACCELERATOR_HDS.md` | Đặc tả chính (22 mục) |
| `aesgcm_CSR.xlsx`, `aesgcm_regs.json` | Workbook thanh ghi và JSON nguồn (prefix `aesgcm`, đã qua `vlsit_csr_tool.py validate`) |
| `figures/` | Block diagram, sơ đồ FSM và 21 waveform cùng nguồn draw.io, JSON, WaveJSON |
| `research/vlsit_reference_ip_log.md` | Nhật ký nghiên cứu IP tham chiếu |

Các phát biểu về GCM trích dẫn NIST SP 800-38D (11/2007), đã chuyển sang Markdown trong skill đặc tả. Các mục còn mở nằm ở mục 20 của đặc tả.
