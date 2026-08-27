//============================================================================
//  Sega Y Board for MiSTer — shared package
//  Board constants, SDRAM/DDR3 map, ioctl stream layout and the per-game
//  descriptor that the MRA prepends to the ROM stream. docs/DESIGN.md ("ROM
//  stream and descriptor") is the reference; tools/romsets.py holds the same
//  slots and tools/pack_roms.py the same descriptor bytes.
//============================================================================
package yb_pkg;

    // ---- board clocks (Hz) -------------------------------------------------
    localparam int PCB_MASTER_HZ = 50_000_000;   // 68000 x3 = /4, 315-5296 = /8, pixel = /8
    localparam int PCB_SOUND_HZ  = 16_000_000;   // Z80 / YM2151 / 315-5218 = /4 (open question 3)
    localparam int CLK_SYS_HZ    = 50_000_000;   // == PCB_MASTER_HZ (exact)
    localparam int CLK_RAM_HZ    = 100_000_000;

    // ---- video timing: 400 x 262 at clk_sys/8, 320 x 224 visible ----------
    // MAME's 342 columns are a set_size placeholder (open question 1).
    localparam int H_TOTAL   = 400;
    localparam int H_ACTIVE  = 320;
    localparam int V_TOTAL   = 262;
    localparam int V_ACTIVE  = 224;
    localparam int VBLANK_LINE = 223;   // IRQ4 asserted during this line
    localparam int LATCH_LINE  = 261;   // yb_video_timing's end-of-frame pulse
    localparam int IRQ2_LINE_DEFAULT = 170;   // 315-5306 timer IRQ, descriptor byte 7

    // ---- SDRAM byte map (25-bit byte address, 32 MB), contiguous slots ----
    localparam [24:0] SDR_MAIN_BASE = 25'h000_0000;  // 512 KB slot, main 68000
    localparam [24:0] SDR_SUBX_BASE = 25'h008_0000;  // 256 KB, sub X 68000
    localparam [24:0] SDR_SUBY_BASE = 25'h00C_0000;  // 256 KB, sub Y 68000
    localparam [24:0] SDR_Z80_BASE  = 25'h010_0000;  //  64 KB
    localparam [24:0] SDR_PCM_BASE  = 25'h011_0000;  //   2 MB, 315-5218 samples
    localparam [24:0] SDR_BSPR_BASE = 25'h031_0000;  //   2 MB, 16B sprite ROM (16-bit words)
    localparam [24:0] SDR_YSPR_BASE = 25'h051_0000;  //  16 MB, Y sprite ROM (64-bit words as four 16-bit halves)
    localparam [24:0] SDR_END       = 25'h151_0000;

    // ---- ioctl index-0 stream layout (byte offsets) -----------------------
    // Every region is padded to its slot except the last one (Y sprites), so
    // stream offset = SDRAM offset + OFF_MAIN and the loader is a plain copy.
    localparam [26:0] OFF_DESC = 27'h000_0000;   // 64-byte descriptor
    localparam [26:0] OFF_MAIN = 27'h000_0040;
    localparam [26:0] OFF_SUBX = OFF_MAIN + 27'h08_0000;
    localparam [26:0] OFF_SUBY = OFF_SUBX + 27'h04_0000;
    localparam [26:0] OFF_Z80  = OFF_SUBY + 27'h04_0000;
    localparam [26:0] OFF_PCM  = OFF_Z80  + 27'h01_0000;
    localparam [26:0] OFF_BSPR = OFF_PCM  + 27'h20_0000;
    localparam [26:0] OFF_YSPR = OFF_BSPR + 27'h20_0000;
    localparam [26:0] OFF_END  = OFF_YSPR + 27'h100_0000;

    // ---- DDR3: two 512x512x16 Y sprite framebuffers, 512 KB each ----------
    localparam [28:0] DDR_FB0_BASE = 29'h0600_0000;  // 0x3000_0000 >> 3, in 64-bit units
    localparam [28:0] DDR_FB1_BASE = 29'h0601_0000;  // 0x3008_0000 >> 3

    // ---- per-game descriptor (first 64 bytes of the stream) ----------------
    //  byte 0: game id (0 gforce2, 1 pdrift, 2 gloc, 3 rchase, 4 strkfgtr,
    //          5 glocr360, 6 pdriftl)
    //  byte 1: flags: bit0 deluxe cabinet (motor board stub on port C / ADC)
    //                 bit1 link board present (pdriftl)
    //                 bit2 R360 (cabinet pitch and roll on ADC 0 and 2)
    //  byte 2: Y sprite ROM bank count, 512 KB banks (bank % count wrap)
    //  byte 3: 16B sprite ROM bank count, 128 KB banks
    //  byte 4: ADC reverse mask (bit n: MAME channel n reads 255 - value)
    //  byte 5: 315-5218 bank mask (0xF8 on every set)
    //  byte 6: bits 2:0 analog mode (0 gforce2, 1 flight gloc/strkfgtr,
    //          2 driving pdrift, 3 guns rchase, 4 R360)
    //  byte 7: IRQ2 scanline (170 unless tuned)
    //  bytes 8..63: reserved (0)
    typedef struct packed {
        logic [7:0] game_id;
        logic       deluxe;
        logic       link;
        logic       r360;
        logic [7:0] yspr_banks;
        logic [7:0] bspr_banks;
        logic [7:0] adc_reverse;
        logic [7:0] pcm_bankmask;
        logic [2:0] ana_mode;
        logic [7:0] irq2_line;
    } board_desc_t;

endpackage
