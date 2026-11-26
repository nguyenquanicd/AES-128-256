// -------------------------------------------------------------------------------------------------
// Project      : AES-GCM Accelerator - acceptance simulation testbench
// File         : tb_aesgcm_regs.svh (included inside module tb_aesgcm_top)
// Description  : Register offsets and field positions taken from the register workbook description
//                doc/ht_aes_gcm_acc/aesgcm_regs.json (REF-005, the only register authority, spec
//                section 11.1). No value here is taken from RTL.
// -------------------------------------------------------------------------------------------------

localparam logic [15:0] A_VERSION   = 16'h0000;
localparam logic [15:0] A_CAP       = 16'h0004;
localparam logic [15:0] A_CTRL      = 16'h0008;
localparam logic [15:0] A_CFG       = 16'h000C;
localparam logic [15:0] A_AADLEN    = 16'h0010;
localparam logic [15:0] A_DATALEN   = 16'h0014;
localparam logic [15:0] A_KEYWAIT   = 16'h0018;
localparam logic [15:0] A_KEY       = 16'h0020;   // 8 words, stride 4, wo
localparam logic [15:0] A_IV        = 16'h0040;   // 4 words
localparam logic [15:0] A_TAGIN     = 16'h0050;   // 4 words
localparam logic [15:0] A_TAGOUT    = 16'h0060;   // 4 words, ro
localparam logic [15:0] A_STS       = 16'h0070;
localparam logic [15:0] A_FIFOSTS   = 16'h0074;
localparam logic [15:0] A_IRQ_RAW   = 16'h0080;   // w1c
localparam logic [15:0] A_IRQ_EN    = 16'h0084;
localparam logic [15:0] A_IRQ_INJ   = 16'h0088;
localparam logic [15:0] A_IRQ_STS   = 16'h008C;
localparam logic [15:0] A_ERR_CODE  = 16'h0090;
localparam logic [15:0] A_FAILCNT   = 16'h0094;
localparam logic [15:0] A_DMACFG    = 16'h0098;
localparam logic [15:0] A_PIO_DIN   = 16'h009C;
localparam logic [15:0] A_PIO_DOUT  = 16'h00A0;
localparam logic [15:0] A_CONS_A    = 16'h00A4;
localparam logic [15:0] A_CONS_D    = 16'h00A8;
localparam logic [15:0] A_CTXX      = 16'h0100;   // 24 words, rwi

// aesgcm_ctrl fields
localparam logic [31:0] CTRL_START   = 32'h0000_0001;
localparam logic [31:0] CTRL_ABORT   = 32'h0000_0002;
localparam logic [31:0] CTRL_ZEROIZE = 32'h0000_0004;
localparam logic [31:0] CTRL_SUSPEND = 32'h0000_0008;
localparam logic [31:0] CTRL_RESUME  = 32'h0000_0010;
localparam logic [31:0] CTRL_KEY_NEW = 32'h0000_0020;
localparam logic [31:0] CTRL_FREE    = 32'h0000_0040;
localparam logic [31:0] CTRL_EN      = 32'h0000_0100;

// aesgcm_sts fields
localparam int STS_BUSY = 0, STS_TAG_OK = 1, STS_VER_OK = 2, STS_ZEROIZED = 3, STS_SEC_ONLY = 4;
localparam int STS_KEY_LD = 5;            // phase [11:8], ctx_vld [19:16]

// aesgcm_fifosts fields
localparam int FIFO_IN_FULL = 9, FIFO_OUT_EMPTY = 26;

// Event bits of aesgcm_irq_raw / _en / _inj / _sts (spec 6.4, 9.3, 11.3: bit 0 DONE ... bit 9 PROTO_ERR)
localparam int EV_DONE = 0, EV_TAGF = 1, EV_CERR = 2, EV_LERR = 3, EV_CEXH = 4;
localparam int EV_DINR = 5, EV_DOUR = 6, EV_CSWD = 7, EV_KERR = 8, EV_PERR = 9;
localparam logic [9:0] EV_ALL = 10'h3FF;
localparam logic [9:0] EV_END = 10'b11_0001_1111 & ~10'b00_0110_0000; // done|tagf|cerr|lerr|cexh|kerr|perr
localparam logic [9:0] EV_ERRS = (1 << EV_TAGF) | (1 << EV_CERR) | (1 << EV_LERR) |
                                 (1 << EV_CEXH) | (1 << EV_KERR) | (1 << EV_PERR);

// aesgcm_err_code.code values (spec 9.3)
localparam int ERRC_NONE = 0, ERRC_CFG = 1, ERRC_LEN = 2, ERRC_CTR = 3, ERRC_KEY = 4;
localparam int ERRC_PROTO = 5, ERRC_TAG = 6, ERRC_CORE = 7;

// Mode codes (spec 9.3)
localparam int M_ECB = 0, M_CBC = 1, M_CFB = 2, M_OFB = 3, M_CTR = 4, M_GCM = 5;

// AXI window decode (spec 6.2/6.3.2: only address bit 11 is decoded)
localparam logic [15:0] AXI_WR_WIN = 16'h0000;   // bit 11 = 0: write window
localparam logic [15:0] AXI_RD_WIN = 16'h0800;   // bit 11 = 1: read window

// aesgcm_cfg word builder (field positions of the workbook)
function automatic logic [31:0] cfg_word(input int mode, input int dec, input int ksz,
                                         input int ksrc, input int dsrc, input int gpass,
                                         input int seg, input int tlc, input int ctx);
  logic [31:0] w;
  w = '0;
  w[2:0]   = mode[2:0];
  w[3]     = dec[0];
  w[4]     = ksz[0];
  w[5]     = ksrc[0];
  w[6]     = dsrc[0];
  w[8:7]   = gpass[1:0];
  w[12:9]  = seg[3:0];
  w[15:13] = tlc[2:0];
  w[17:16] = ctx[1:0];
  return w;
endfunction

// Expected aesgcm_cap value from the build parameters (field descriptions of the workbook).
function automatic logic [31:0] cap_expected();
  logic [31:0] w;
  w = '0;
  w[0]     = (C_GCM_EN == 1);
  w[1]     = (C_AXI == 1);
  w[2]     = (C_KEY_SIDE == 1);
  w[3]     = (C_ASYNC == 1);
  w[5:4]   = C_POLICY[1:0];
  w[6]     = (C_CTX_MODE == 1);
  w[10:8]  = C_CTX_NUM[2:0];
  w[14:12] = C_LANES[2:0];
  w[17:16] = C_ARCH[1:0];
  w[21:20] = C_DW_CODE[1:0];
  return w;
endfunction

// Fields of aesgcm_cap that are compared (open question Q-07: GCM-disabled and APB-wrapper values).
function automatic logic [31:0] cap_compare_mask();
  logic [31:0] m;
  m = 32'h0000_700F;                          // gcm_en, axi_en, key_side, async, lanes
  if (C_GCM_EN == 1) m = m | 32'h0003_0770;   // policy, ctx_exp, ctx_num, ghash
  if (C_AXI == 1)    m = m | 32'h0030_0000;   // axi_dw only on the AXI wrapper
  return m;
endfunction

// Reserved bits (read as 0, spec 11.4) of registers whose fields do not fill 32 bits.
function automatic logic [31:0] rsv_mask(input logic [15:0] a);
  case (a)
    A_CAP:      rsv_mask = 32'hFFCC_8880;
    A_CTRL:     rsv_mask = 32'hFFFF_FE80;
    A_CFG:      rsv_mask = 32'hFFFC_0000;
    A_KEYWAIT:  rsv_mask = 32'hFFFF_0000;
    A_STS:      rsv_mask = 32'hFFF0_F0C0;
    A_FIFOSTS:  rsv_mask = ~32'h0400_0200;
    A_IRQ_RAW, A_IRQ_EN, A_IRQ_INJ, A_IRQ_STS: rsv_mask = 32'hFFFF_FC00;
    A_ERR_CODE: rsv_mask = 32'hFFFF_FF00;
    A_DMACFG:   rsv_mask = 32'hFFFF_FF00;
    default:    rsv_mask = 32'h0000_0000;
  endcase
endfunction

// Address map of the workbook (aligned addresses only).
function automatic bit addr_mapped(input logic [15:0] a);
  if (a[1:0] != 2'b00) return 1'b0;
  if (a <= 16'h0018) return 1'b1;
  if ((a >= 16'h0020) && (a <= 16'h0074)) return 1'b1;
  if ((a >= 16'h0080) && (a <= 16'h00A8)) return 1'b1;
  if ((a >= 16'h0100) && (a <= 16'h015C)) return 1'b1;
  return 1'b0;
endfunction
