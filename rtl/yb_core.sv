//============================================================================
//  Sega Y Board — board top
//  M1: the three 68000s (main, sub X, sub Y; fx68k) with ROM caches, every
//  CPU-visible RAM, a 315-5248/5249 pair per CPU, the 315-5296 I/O chip with
//  the MSM6253 behind its /FMCS window, the scanline interrupts, the MB3773
//  watchdog and the sound latch. The three CPUs share one 64 KB RAM through
//  a one-access-per-clock arbiter. Video chips arrive in M2-M4: the display
//  is a gradient gated by /KILL, and the video RAMs only exist on the CPU
//  side. The Z80 sound board is wired in M5.
//============================================================================
import yb_pkg::*;

module yb_core (
    input             clk_sys,      // 50 MHz
    input             clk_ram,      // 100 MHz
    input             reset,
    input             pause,
    input board_desc_t board_desc,

    // DDR3 (the two Y sprite framebuffers)
    input             DDRAM_BUSY,
    output      [7:0] DDRAM_BURSTCNT,
    output     [28:0] DDRAM_ADDR,
    input      [63:0] DDRAM_DOUT,
    input             DDRAM_DOUT_READY,
    output            DDRAM_RD,
    output     [63:0] DDRAM_DIN,
    output      [7:0] DDRAM_BE,
    output            DDRAM_WE,

    // SDRAM read ports (sdram.sv p0..p7): p0 main ROM, p1 sub X ROM, p3 sub Y
    // ROM; p5 Z80 and p6 PCM in M5, p2 Y sprites in M2, p4 16B sprites in M4
    output            p0_req, output [24:3] p0_addr, input  [63:0] p0_dout, input p0_ack,
    output            p1_req, output [24:3] p1_addr, input  [63:0] p1_dout, input p1_ack,
    output            p2_req, output [24:4] p2_addr, input [127:0] p2_dout, input p2_ack,
    output            p3_req, output [24:3] p3_addr, input  [63:0] p3_dout, input p3_ack, output p3_urgent,
    output            p4_req, output [24:4] p4_addr, input [127:0] p4_dout, input p4_ack, output p4_urgent,
    output            p5_req, output [24:3] p5_addr, input  [63:0] p5_dout, input p5_ack,
    output            p6_req, output [24:1] p6_addr, input  [15:0] p6_dout, input p6_ack,
    output            p7_req, output [24:4] p7_addr, input [127:0] p7_dout, input p7_ack,

    // backup RAM (16 KB on sub X) as ioctl index 3; the CPUs are in reset
    // during a download, so the host borrows the CPU port
    input             nv_download,
    input             nv_upload,
    input             nv_wr,
    input             nv_rd,
    input      [12:0] nv_addr,        // word address 0..0x1FFF
    input      [15:0] nv_din,
    output reg [15:0] nv_dout,
    output reg        nv_modified,

    // inputs (active high)
    input      [15:0] p1_buttons,   // 0 right 1 left 2 down 3 up 4 A 5 B 6 start 7 coin 8 test 9 service 10 pause 11 gas/speed up 12 brake/slow down
    input      [15:0] p2_buttons,   // second controller, same layout (Rail Chase)
    input signed [7:0] stick_x, stick_y,    // MiSTer analog axes, -128..127
    input signed [7:0] stick2_x, stick2_y,  // second controller's stick (Rail Chase P2 gun)
    input       [7:0] throttle,             // 0..255
    input       [1:0] stick_mode,           // 0 analog, 1 d-pad, 2 both
    input       [1:0] ana_curve,            // OSD analog response: 0 linear, 1 soft, 2 softer
    input       [1:0] ana_range,            // OSD analog range: 0 100%, 1 75%, 2 50%
    input       [7:0] dsw_a, dsw_b,         // SW A (port G, coinage), SW B (port F)
    input             service, test,
    input             coin1, coin2,

    // video (320x224 inside the 400x262 grid)
    output reg  [7:0] r, g, b,
    output            ce_vid, hs, vs, hb, vb,

    output signed [15:0] audio_l, audio_r,

    // executed-instruction traces for the board bench (one per 68000)
    output     [23:1] trace_main_addr, output trace_main_start, output [2:0] trace_main_fc,
    output     [23:1] trace_subx_addr, output trace_subx_start, output [2:0] trace_subx_fc,
    output     [23:1] trace_suby_addr, output trace_suby_start, output [2:0] trace_suby_fc
);

// ---------------------------------------------------------------- clocks
reg [1:0] phase;             // 12.5 MHz = clk_sys/4
always @(posedge clk_sys) begin
    if (reset) phase <= 2'd0;
    else phase <= phase + 2'd1;
end
wire ce_cpu = ~pause;

// ---------------------------------------------------------------- timing
wire       ce_pix, hblank, vblank, hsync, vsync, v0, line_start, vbl_irq, latch_pulse;
wire [8:0] hcnt, vcnt;
wire       ce_out, oline, ohblank, ohsync;
wire [9:0] ohcnt;

yb_video_timing timing (
    .clk(clk_sys), .reset(reset),
    .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
    .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync),
    .v0(v0), .line_start(line_start), .vbl_irq(vbl_irq), .latch_pulse(latch_pulse),
    .hires(1'b0), .ce_out(ce_out), .ohcnt(ohcnt), .oline(oline), .ohblank(ohblank), .ohsync(ohsync)
);
assign ce_vid = ce_out;
assign hs = ohsync;
assign vs = vsync;
assign hb = ohblank;
assign vb = vblank;

// ---------------------------------------------------------------- interrupts
// No 315-5250 here. IPL2 is the 315-5306's "timer" line, one scanline wide
// at the descriptor's line (MAME 170); IPL4 is vblank, one line wide at 223;
// IPL6 when both are up. No acknowledge on any of them. All three CPUs see
// the same lines (MAME update_irqs).
wire       irq2 = (vcnt == {1'b0, board_desc.irq2_line});
wire [2:0] ipl  = (irq2 && vbl_irq) ? 3'd6 : vbl_irq ? 3'd4 : irq2 ? 3'd2 : 3'd0;

// ---------------------------------------------------------------- watchdog
// MB3773: its 5 s timer restarts on every falling edge of /WDCL (port E bit
// 5, MAME write_line_ck) and issues a reset when it runs out. 300 frames.
wire [7:0] pe_out;
reg  [8:0] wd_frames;
reg        wd_reset, wdcl_d;
always @(posedge clk_sys) begin
    wdcl_d <= pe_out[5];
    if (reset) begin wd_frames <= 9'd0; wd_reset <= 1'b0; end
    else begin
        wd_reset <= 1'b0;
        if (!pe_out[5] && wdcl_d) wd_frames <= 9'd0;
        else if (line_start && vcnt == 9'd0) begin
            if (wd_frames == 9'd300) begin wd_reset <= 1'b1; wd_frames <= 9'd0; end
            else wd_frames <= wd_frames + 9'd1;
        end
    end
end
wire cpu_reset = reset | wd_reset;

// ================================================================ MAIN CPU
wire [23:1] m_addr;
wire        m_valid, m_start, m_rd, m_wr;
wire  [1:0] m_be;
wire [15:0] m_dout;
reg  [15:0] m_din;
reg         m_ack;
wire  [2:0] m_fc;
wire        m_reset_out;     // main 68000 RESET instruction -> sub CPUs reset (MAME m68k_reset_callback)

yb_m68k_bus main_cpu (
    .clk(clk_sys), .reset(cpu_reset), .ce_phase(ce_cpu), .phase(phase),
    .ipl(ipl), .halt_n(1'b1),
    .bus_addr(m_addr), .bus_valid(m_valid), .bus_start(m_start),
    .bus_rd(m_rd), .bus_wr(m_wr), .bus_be(m_be),
    .bus_dout(m_dout), .bus_din(m_din), .bus_ack(m_ack), .reset_out(m_reset_out), .fc(m_fc), .bus_as_n()
);
assign trace_main_addr = m_addr; assign trace_main_start = m_start; assign trace_main_fc = m_fc;

// main decode (global mask 0x1FFFFF -> bits 20:1; unmapped reads FFFF)
wire [20:1] ma = m_addr[20:1];
wire m_sel_rom  = (ma[20:19] == 2'd0);          // 000000-07FFFF
wire m_sel_mult = (ma[20:13] == 8'h40);         // 080000-081FFF (mirror 1FF8)
wire m_sel_snd  = (ma[20:13] == 8'h41);         // 082001, sound latch
wire m_sel_div  = (ma[20:13] == 8'h42);         // 084000-085FFF (mirror 1FE0)
wire m_sel_shr  = (ma[20:16] == 5'h0C);         // 0C0000-0CFFFF shared RAM
wire m_sel_io   = (ma[20:7]  == 14'h2000);      // 100000-10007F 315-5296 (and the ADC behind /FMCS)
wire m_sel_lram = (ma[20:16] == 5'h1F);         // 1F0000-1FFFFF local RAM

// one-clock strobes for the chips, and a 1-clk-later ack for BRAM targets
reg m_ram_rdy;
always @(posedge clk_sys) m_ram_rdy <= m_valid && !m_start && !m_ack ? 1'b1 : (m_valid ? m_ram_rdy : 1'b0);
wire m_cs = m_start;

// ---- main ROM cache
wire [15:0] m_rom_data; wire m_rom_ack;
wire        m_rom_req; wire [19:3] m_rom_addr;
yb_rom_cache #(.AW(19), .LINES(512)) main_cache (
    .clk(clk_sys), .reset(reset), .invalidate(reset),
    .cpu_req(m_valid && m_rd && m_sel_rom), .cpu_addr(ma[19:1]),
    .cpu_data(m_rom_data), .cpu_ack(m_rom_ack),
    .rom_req(m_rom_req), .rom_addr(m_rom_addr), .rom_data(p0_dout), .rom_ack(p0_ack)
);
assign p0_req  = m_rom_req;
assign p0_addr = SDR_MAIN_BASE[24:3] + {5'd0, m_rom_addr};

// ---- main local RAM (64 KB)
wire [15:0] m_lram_q;
yb_dpram #(.AW(15)) main_ram (.clk(clk_sys), .a_addr(ma[15:1]), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_lram && m_start), .a_dout(m_lram_q),
    .b_clk(clk_sys), .b_addr(15'd0), .b_dout());

// ---- main math chips
wire [15:0] m_mult_q, m_div_q;
wire        m_div_rdy;
yb_math_5248 main_mult (.clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_mult), .we(m_wr),
    .addr(ma[2:1]), .din(m_dout), .be(m_be), .dout(m_mult_q));
yb_math_5249 main_div (.clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_div), .we(m_wr),
    .addr(ma[4:1]), .din(m_dout), .be(m_be), .dout(m_div_q), .rdy(m_div_rdy));

// ---- sound latch (082001, odd byte): a write raises the Z80's NMI (M5)
reg [7:0] snd_latch;
reg       snd_nmi;
always @(posedge clk_sys) begin
    if (cpu_reset) begin snd_latch <= 8'd0; snd_nmi <= 1'b0; end
    else if (m_cs && m_wr && m_sel_snd && m_be[0]) begin snd_latch <= m_dout[7:0]; snd_nmi <= 1'b1; end
end

// ---- 315-5296 and the MSM6253 (low byte lane)
// Port A: P1 (unused on the parents); port B: bit 0 unused, 1 test, 2
// service, 3 start, 4 button 1, 5 button 2, 6 coin 1, 7 coin 2 (active low);
// port C: limit switches, inactive; ports D/E/H are outputs; F = SW B, G = SW A.
wire [7:0] io_q, ph_out;
wire       io_fmcs;
wire       adc_d7;
wire [7:0] in_b = ~{coin2, coin1 | p1_buttons[7], p1_buttons[5], p1_buttons[4],
                    p1_buttons[6], service | p1_buttons[9], test | p1_buttons[8], 1'b0};
yb_315_5296 io (
    .clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_io && m_be[0]), .we(m_wr),
    .addr(ma[6:1]), .din(m_dout[7:0]), .dout(io_q), .fmcs(io_fmcs),
    .in_a(8'hFF), .in_b(in_b), .in_c(8'hFF), .in_d(8'hFF), .in_e(8'hFF), .in_f(dsw_b), .in_g(dsw_a), .in_h(8'hFF),
    .out_a(), .out_b(), .out_c(), .out_d(), .out_e(pe_out), .out_f(), .out_g(), .out_h(ph_out)
);
// port E: 7 /KILL (display enable), 6 CONT, 5 /WDCL, 4 /SRES, 3 XRES, 2 YRES, 1:0 ADC mux
wire display_enable = pe_out[7];
wire snd_reset_n    = pe_out[4];
wire xres           = pe_out[3];
wire yres           = pe_out[2];
wire mute_n         = ph_out[7];
yb_msm6253 adc (
    .clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_io && m_be[0] && io_fmcs), .we(m_wr),
    .addr(ma[2:1]), .d7(adc_d7),
    .mux_sel(pe_out[1:0]), .adc_reverse(board_desc.adc_reverse[6:0]),
    .ch0(adc_ch0), .ch1(adc_ch1), .ch2(adc_ch2),
    .mux0(adc_mux0), .mux1(adc_mux1), .mux2(adc_mux2), .mux3(adc_mux3)
);

// ---- analog inputs to the ADC channels, per the descriptor's analog mode.
// Mode 0 (Galaxy Force II): stick X on channel 0 and Y on channel 1, both
// full range 0x01..0xFF with 0x80 centred (the Y reversal is the
// descriptor's adc_reverse bit, MAME's PORT_REVERSE), throttle on channel 2.
// The other modes (flight, driving, guns, R360) arrive with their games in M7.
wire signed [7:0] sx_s, sy_s, thr_s;
yb_ana_shape shape_x (.clk(clk_sys), .axis(stick_x), .curve(ana_curve), .range(ana_range), .out(sx_s));
yb_ana_shape shape_y (.clk(clk_sys), .axis(stick_y), .curve(ana_curve), .range(ana_range), .out(sy_s));
yb_ana_shape shape_t (.clk(clk_sys), .axis(throttle ^ 8'h80), .curve(ana_curve), .range(ana_range), .out(thr_s));
wire [7:0] throttle_s = thr_s ^ 8'h80;
// Speed Up / Slow Down hold the throttle at its ends (the X Board's After
// Burner mapping: high reads as fast)
wire [7:0] thr_fl = p1_buttons[11] ? 8'hFF : p1_buttons[12] ? 8'h00 : throttle_s;
wire use_analog  = (stick_mode != 2'd1);
wire use_dpad    = (stick_mode != 2'd0);
wire dpad_active = |p1_buttons[3:0];
wire [7:0] fr_x  = {~sx_s[7], sx_s[6:0]};   // 0x80 + x
wire [7:0] fr_y  = {~sy_s[7], sy_s[6:0]};   // up (negative) -> low
wire [7:0] fr_dx = p1_buttons[0] ? 8'hFF : p1_buttons[1] ? 8'h01 : 8'h80;
wire [7:0] fr_dy = p1_buttons[3] ? 8'h01 : p1_buttons[2] ? 8'hFF : 8'h80;
wire [7:0] adc_ch0 = (use_dpad && dpad_active) ? fr_dx : use_analog ? fr_x : 8'h80;
wire [7:0] adc_ch1 = (use_dpad && dpad_active) ? fr_dy : use_analog ? fr_y : 8'h80;
wire [7:0] adc_ch2 = thr_fl;
wire [7:0] adc_mux0 = 8'h80, adc_mux1 = 8'h80, adc_mux2 = 8'h80, adc_mux3 = 8'h80;

// ================================================================ SUB X
wire [23:1] x_addr;
wire        x_valid, x_start, x_rd, x_wr;
wire  [1:0] x_be;
wire [15:0] x_dout;
reg  [15:0] x_din;
reg         x_ack;
wire  [2:0] x_fc;

yb_m68k_bus subx_cpu (
    .clk(clk_sys), .reset(cpu_reset | m_reset_out | xres), .ce_phase(ce_cpu), .phase(phase),
    .ipl(ipl), .halt_n(1'b1),
    .bus_addr(x_addr), .bus_valid(x_valid), .bus_start(x_start),
    .bus_rd(x_rd), .bus_wr(x_wr), .bus_be(x_be),
    .bus_dout(x_dout), .bus_din(x_din), .bus_ack(x_ack), .reset_out(), .fc(x_fc), .bus_as_n()
);
assign trace_subx_addr = x_addr; assign trace_subx_start = x_start; assign trace_subx_fc = x_fc;

wire [20:1] xa = x_addr[20:1];
wire x_sel_rom  = (xa[20:18] == 3'd0);          // 000000-03FFFF
wire x_sel_mult = (xa[20:13] == 8'h40);
wire x_sel_div  = (xa[20:13] == 8'h42);
wire x_sel_shr  = (xa[20:16] == 5'h0C);
wire x_sel_yspr = (xa[20:16] == 5'h18);         // 180000-18FFFF Y sprite RAM
wire x_sel_lram = (xa[20:14] == 7'h7E);         // 1F8000-1FBFFF
wire x_sel_bkup = (xa[20:14] == 7'h7F);         // 1FC000-1FFFFF backup RAM

reg x_ram_rdy;
always @(posedge clk_sys) x_ram_rdy <= x_valid && !x_start && !x_ack ? 1'b1 : (x_valid ? x_ram_rdy : 1'b0);
wire x_cs = x_start;

wire [15:0] x_rom_data; wire x_rom_ack;
wire        x_rom_req; wire [18:3] x_rom_addr;
yb_rom_cache #(.AW(18), .LINES(512)) subx_cache (
    .clk(clk_sys), .reset(reset), .invalidate(reset),
    .cpu_req(x_valid && x_rd && x_sel_rom), .cpu_addr(xa[18:1]),
    .cpu_data(x_rom_data), .cpu_ack(x_rom_ack),
    .rom_req(x_rom_req), .rom_addr(x_rom_addr), .rom_data(p1_dout), .rom_ack(p1_ack)
);
assign p1_req  = x_rom_req;
assign p1_addr = SDR_SUBX_BASE[24:3] + {6'd0, x_rom_addr};

wire [15:0] x_lram_q, yspr_q, bkup_q, bkup_hq;
yb_dpram #(.AW(13)) subx_ram (.clk(clk_sys), .a_addr(xa[13:1]), .a_din(x_dout), .a_be(x_be),
    .a_we(x_valid && x_wr && x_sel_lram && x_start), .a_dout(x_lram_q),
    .b_clk(clk_sys), .b_addr(13'd0), .b_dout());
// Y sprite RAM (64 KB): port B is the 315-5305's (M2)
yb_dpram #(.AW(15)) yspriteram (.clk(clk_sys), .a_addr(xa[15:1]), .a_din(x_dout), .a_be(x_be),
    .a_we(x_valid && x_wr && x_sel_yspr && x_start), .a_dout(yspr_q),
    .b_clk(clk_ram), .b_addr(15'd0), .b_dout());
// backup RAM (16 KB, battery backed): the host borrows the CPU port for the
// NVRAM download and reads port B for the upload
wire        bk_we = x_valid && x_wr && x_sel_bkup && x_start;
wire [12:0] bk_a  = nv_download ? nv_addr : xa[13:1];
wire [15:0] bk_d  = nv_download ? nv_din : x_dout;
wire  [1:0] bk_be = nv_download ? 2'b11 : x_be;
yb_dpram #(.AW(13)) backup (.clk(clk_sys), .a_addr(bk_a), .a_din(bk_d), .a_be(bk_be),
    .a_we(nv_download ? nv_wr : bk_we), .a_dout(bkup_q),
    .b_clk(clk_sys), .b_addr(nv_addr), .b_dout(bkup_hq));
always @(posedge clk_sys) nv_dout <= bkup_hq;
// modified flag: set on a CPU write, cleared when an upload starts; held off
// for ~2 s after each request so the host is not flooded with saves
reg [7:0] nv_hold;
reg       vb_d;
always @(posedge clk_sys) begin
    vb_d <= vblank;
    if (reset) begin nv_modified <= 1'b0; nv_hold <= 8'd0; end
    else begin
        if (nv_upload) nv_modified <= 1'b0;
        else if (bk_we && nv_hold == 8'd0) begin nv_modified <= 1'b1; nv_hold <= 8'd120; end
        if (vblank && !vb_d && nv_hold != 8'd0) nv_hold <= nv_hold - 8'd1;
    end
end

wire [15:0] x_mult_q, x_div_q;
wire        x_div_rdy;
yb_math_5248 subx_mult (.clk(clk_sys), .reset(cpu_reset), .cs(x_cs && x_sel_mult), .we(x_wr),
    .addr(xa[2:1]), .din(x_dout), .be(x_be), .dout(x_mult_q));
yb_math_5249 subx_div (.clk(clk_sys), .reset(cpu_reset), .cs(x_cs && x_sel_div), .we(x_wr),
    .addr(xa[4:1]), .din(x_dout), .be(x_be), .dout(x_div_q), .rdy(x_div_rdy));

// ================================================================ SUB Y
wire [23:1] y_addr;
wire        y_valid, y_start, y_rd, y_wr;
wire  [1:0] y_be;
wire [15:0] y_dout;
reg  [15:0] y_din;
reg         y_ack;
wire  [2:0] y_fc;

yb_m68k_bus suby_cpu (
    .clk(clk_sys), .reset(cpu_reset | m_reset_out | yres), .ce_phase(ce_cpu), .phase(phase),
    .ipl(ipl), .halt_n(1'b1),
    .bus_addr(y_addr), .bus_valid(y_valid), .bus_start(y_start),
    .bus_rd(y_rd), .bus_wr(y_wr), .bus_be(y_be),
    .bus_dout(y_dout), .bus_din(y_din), .bus_ack(y_ack), .reset_out(), .fc(y_fc), .bus_as_n()
);
assign trace_suby_addr = y_addr; assign trace_suby_start = y_start; assign trace_suby_fc = y_fc;

wire [20:1] ya = y_addr[20:1];
wire y_sel_rom  = (ya[20:18] == 3'd0);          // 000000-03FFFF
wire y_sel_mult = (ya[20:13] == 8'h40);
wire y_sel_div  = (ya[20:13] == 8'h42);
wire y_sel_shr  = (ya[20:16] == 5'h0C);
wire y_sel_rot  = (ya[20:15] == 6'h30);         // 180000-187FFF rotation RAM (2 KB, mirror 7800)
wire y_sel_bspr = (ya[20:15] == 6'h31);         // 188000-18FFFF 16B sprite RAM (4 KB, mirror 7000)
wire y_sel_pal  = (ya[20:15] == 6'h32);         // 190000-197FFF palette (16 KB, mirror 4000)
wire y_sel_rotc = (ya[20:15] == 6'h33);         // 198000-19FFFF rotation control (read swaps)
wire y_sel_lram = (ya[20:16] == 5'h1F);         // 1F0000-1FFFFF

reg y_ram_rdy;
always @(posedge clk_sys) y_ram_rdy <= y_valid && !y_start && !y_ack ? 1'b1 : (y_valid ? y_ram_rdy : 1'b0);
wire y_cs = y_start;

wire [15:0] y_rom_data; wire y_rom_ack;
wire        y_rom_req; wire [18:3] y_rom_addr;
yb_rom_cache #(.AW(18), .LINES(512)) suby_cache (
    .clk(clk_sys), .reset(reset), .invalidate(reset),
    .cpu_req(y_valid && y_rd && y_sel_rom), .cpu_addr(ya[18:1]),
    .cpu_data(y_rom_data), .cpu_ack(y_rom_ack),
    .rom_req(y_rom_req), .rom_addr(y_rom_addr), .rom_data(p3_dout), .rom_ack(p3_ack)
);
assign p3_req    = y_rom_req;
assign p3_addr   = SDR_SUBY_BASE[24:3] + {6'd0, y_rom_addr};
assign p3_urgent = 1'b0;

wire [15:0] y_lram_q, rot_q, bspr_q, pal_q;
yb_dpram #(.AW(15)) suby_ram (.clk(clk_sys), .a_addr(ya[15:1]), .a_din(y_dout), .a_be(y_be),
    .a_we(y_valid && y_wr && y_sel_lram && y_start), .a_dout(y_lram_q),
    .b_clk(clk_sys), .b_addr(15'd0), .b_dout());
// rotation RAM: two 2 KB banks. The CPU writes one while the 315-5306 scans
// the other; a read of 198000 swaps them (MAME rotate_control_r exchanges
// the RAM with its buffer) and returns FFFF.
reg rot_bank;
always @(posedge clk_sys) begin
    if (cpu_reset) rot_bank <= 1'b0;
    else if (y_cs && y_rd && y_sel_rotc) rot_bank <= ~rot_bank;
end
yb_dpram #(.AW(11)) rotateram (.clk(clk_sys), .a_addr({rot_bank, ya[10:1]}), .a_din(y_dout), .a_be(y_be),
    .a_we(y_valid && y_wr && y_sel_rot && y_start), .a_dout(rot_q),
    .b_clk(clk_ram), .b_addr({~rot_bank, 10'd0}), .b_dout());
yb_dpram #(.AW(11)) bspriteram (.clk(clk_sys), .a_addr(ya[11:1]), .a_din(y_dout), .a_be(y_be),
    .a_we(y_valid && y_wr && y_sel_bspr && y_start), .a_dout(bspr_q),
    .b_clk(clk_sys), .b_addr(11'd0), .b_dout());
wire [7:0] pal_r, pal_g, pal_b;
yb_palette_5242 palette (.clk(clk_sys), .a_addr(ya[13:1]), .a_din(y_dout), .a_be(y_be),
    .a_we(y_valid && y_wr && y_sel_pal && y_start), .a_dout(pal_q),
    .b_addr(13'd0), .b_effects(1'b0), .r(pal_r), .g(pal_g), .b(pal_b));

wire [15:0] y_mult_q, y_div_q;
wire        y_div_rdy;
yb_math_5248 suby_mult (.clk(clk_sys), .reset(cpu_reset), .cs(y_cs && y_sel_mult), .we(y_wr),
    .addr(ya[2:1]), .din(y_dout), .be(y_be), .dout(y_mult_q));
yb_math_5249 suby_div (.clk(clk_sys), .reset(cpu_reset), .cs(y_cs && y_sel_div), .we(y_wr),
    .addr(ya[4:1]), .din(y_dout), .be(y_be), .dout(y_div_q), .rdy(y_div_rdy));

// ================================================================ SHARED RAM
// 64 KB seen by all three CPUs at 0C0000. One BRAM, one access per clock:
// each CPU's start pulse queues a request, the arbiter serves one queued
// request per clock (main first, then sub X, then sub Y) and the requester's
// data is captured and acknowledged two clocks later. A 68000 bus cycle is
// at least 16 clocks, so the queue never holds more than one request per
// CPU and DTACK is never late. What the 315-5314..5318 PALs do on the real
// board is open question 6.
reg         m_shr_pend, x_shr_pend, y_shr_pend;
reg         m_shr_got, x_shr_got, y_shr_got;
reg         m_shr_ack, x_shr_ack, y_shr_ack;
reg  [15:0] m_shr_q, x_shr_q, y_shr_q;
wire        shr_pick_m = m_shr_pend;
wire        shr_pick_x = !m_shr_pend && x_shr_pend;
wire        shr_pick_y = !m_shr_pend && !x_shr_pend && y_shr_pend;
wire [14:0] shr_addr = shr_pick_m ? ma[15:1] : shr_pick_x ? xa[15:1] : ya[15:1];
wire [15:0] shr_din  = shr_pick_m ? m_dout   : shr_pick_x ? x_dout   : y_dout;
wire  [1:0] shr_be   = shr_pick_m ? m_be     : shr_pick_x ? x_be     : y_be;
wire        shr_we   = shr_pick_m ? m_wr     : shr_pick_x ? x_wr     : (shr_pick_y & y_wr);
wire [15:0] shr_q;
yb_dpram #(.AW(15)) sharedram (.clk(clk_sys), .a_addr(shr_addr), .a_din(shr_din), .a_be(shr_be),
    .a_we(shr_we), .a_dout(shr_q),
    .b_clk(clk_sys), .b_addr(15'd0), .b_dout());
always @(posedge clk_sys) begin
    if (reset) begin
        m_shr_pend <= 1'b0; x_shr_pend <= 1'b0; y_shr_pend <= 1'b0;
        m_shr_got <= 1'b0; x_shr_got <= 1'b0; y_shr_got <= 1'b0;
        m_shr_ack <= 1'b0; x_shr_ack <= 1'b0; y_shr_ack <= 1'b0;
    end
    else begin
        if (m_start && m_sel_shr) m_shr_pend <= 1'b1; else if (shr_pick_m) m_shr_pend <= 1'b0;
        if (x_start && x_sel_shr) x_shr_pend <= 1'b1; else if (shr_pick_x) x_shr_pend <= 1'b0;
        if (y_start && y_sel_shr) y_shr_pend <= 1'b1; else if (shr_pick_y) y_shr_pend <= 1'b0;
        m_shr_got <= shr_pick_m; x_shr_got <= shr_pick_x; y_shr_got <= shr_pick_y;
        if (!m_valid) m_shr_ack <= 1'b0; else if (m_shr_got) begin m_shr_q <= shr_q; m_shr_ack <= 1'b1; end
        if (!x_valid) x_shr_ack <= 1'b0; else if (x_shr_got) begin x_shr_q <= shr_q; x_shr_ack <= 1'b1; end
        if (!y_valid) y_shr_ack <= 1'b0; else if (y_shr_got) begin y_shr_q <= shr_q; y_shr_ack <= 1'b1; end
    end
end

// ================================================================ read muxes
always @* begin
    m_din = 16'hFFFF;
    m_ack = 1'b0;
    if (m_sel_rom)       begin m_din = m_rom_data; m_ack = m_rom_ack; end
    else if (m_sel_shr)  begin m_din = m_shr_q;    m_ack = m_shr_ack; end
    else if (m_sel_lram) begin m_din = m_lram_q;   m_ack = m_ram_rdy; end
    else if (m_sel_mult) begin m_din = m_mult_q;   m_ack = m_ram_rdy; end
    else if (m_sel_div)  begin m_din = m_div_q;    m_ack = m_ram_rdy && m_div_rdy; end
    else if (m_sel_io)   begin m_din = io_fmcs ? {8'hFF, adc_d7, 7'h7F} : {8'hFF, io_q}; m_ack = m_ram_rdy; end
    else                 begin m_din = 16'hFFFF;   m_ack = m_ram_rdy; end   // sound latch, unmapped
end

always @* begin
    x_din = 16'hFFFF;
    x_ack = 1'b0;
    if (x_sel_rom)       begin x_din = x_rom_data; x_ack = x_rom_ack; end
    else if (x_sel_shr)  begin x_din = x_shr_q;    x_ack = x_shr_ack; end
    else if (x_sel_yspr) begin x_din = yspr_q;     x_ack = x_ram_rdy; end
    else if (x_sel_lram) begin x_din = x_lram_q;   x_ack = x_ram_rdy; end
    else if (x_sel_bkup) begin x_din = bkup_q;     x_ack = x_ram_rdy; end
    else if (x_sel_mult) begin x_din = x_mult_q;   x_ack = x_ram_rdy; end
    else if (x_sel_div)  begin x_din = x_div_q;    x_ack = x_ram_rdy && x_div_rdy; end
    else                 begin x_din = 16'hFFFF;   x_ack = x_ram_rdy; end
end

always @* begin
    y_din = 16'hFFFF;
    y_ack = 1'b0;
    if (y_sel_rom)       begin y_din = y_rom_data; y_ack = y_rom_ack; end
    else if (y_sel_shr)  begin y_din = y_shr_q;    y_ack = y_shr_ack; end
    else if (y_sel_lram) begin y_din = y_lram_q;   y_ack = y_ram_rdy; end
    else if (y_sel_rot)  begin y_din = rot_q;      y_ack = y_ram_rdy; end
    else if (y_sel_bspr) begin y_din = bspr_q;     y_ack = y_ram_rdy; end
    else if (y_sel_pal)  begin y_din = pal_q;      y_ack = y_ram_rdy; end
    else if (y_sel_mult) begin y_din = y_mult_q;   y_ack = y_ram_rdy; end
    else if (y_sel_div)  begin y_din = y_div_q;    y_ack = y_ram_rdy && y_div_rdy; end
    else                 begin y_din = 16'hFFFF;   y_ack = y_ram_rdy; end   // rotation control, unmapped
end

// ================================================================ video (M1)
// Placeholder picture behind /KILL: x gradient in red, y gradient in green,
// blue on the right-hand 64 columns; black while the game holds the display
// off. M2 replaces this with the Y layer.
always @(posedge clk_sys) begin
    if (ce_out) begin
        if (ohblank || vblank || !display_enable) begin
            r <= 8'd0; g <= 8'd0; b <= 8'd0;
        end
        else begin
            r <= ohcnt[7:0];
            g <= vcnt[7:0];
            b <= ohcnt[8] ? 8'hFF : 8'h00;
        end
    end
end

// ---------------------------------------------------------------- tie-offs
assign DDRAM_BURSTCNT = 8'd0;
assign DDRAM_ADDR     = 29'd0;
assign DDRAM_RD       = 1'b0;
assign DDRAM_DIN      = 64'd0;
assign DDRAM_BE       = 8'd0;
assign DDRAM_WE       = 1'b0;

assign p2_req = 1'b0; assign p2_addr = '0;
assign p4_req = 1'b0; assign p4_addr = '0; assign p4_urgent = 1'b0;
assign p5_req = 1'b0; assign p5_addr = '0;
assign p6_req = 1'b0; assign p6_addr = '0;
assign p7_req = 1'b0; assign p7_addr = '0;

assign audio_l = 16'sd0;
assign audio_r = 16'sd0;

endmodule
