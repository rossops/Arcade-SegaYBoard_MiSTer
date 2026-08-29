//============================================================================
//  Sega Y Board — board top
//  M1: the three 68000s (main, sub X, sub Y; fx68k) with ROM caches, every
//  CPU-visible RAM, a 315-5248/5249 pair per CPU, the 315-5296 I/O chip with
//  the MSM6253 behind its /FMCS window, the scanline interrupts, the MB3773
//  watchdog and the sound latch. The three CPUs share one 64 KB RAM through
//  a one-access-per-clock arbiter. Video chips arrive in M2-M4: the display
//  is the Y layer (315-5305 into DDR3, 315-5306 scan-out) under the 16B
//  layer (315-5196) through the 315-5312 mixer and the palette, and the
//  Z80 sound board with the YM2151 and the 315-5218 (M5).
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
    input      [15:0] p1_buttons,   // 0 right 1 left 2 down 3 up 4 A 5 B 6 start 7 coin 8 test 9 service 10 pause 11 gas/speed up 12 brake/slow down 13 C (After Burner, Gear Shift)
    input      [15:0] p2_buttons,   // second controller, same layout (Rail Chase)
    input signed [7:0] stick_x, stick_y,    // MiSTer analog axes, -128..127
    input signed [7:0] stick2_x, stick2_y,  // second controller's stick (Rail Chase P2 gun)
    input       [7:0] throttle,             // 0..255
    input       [1:0] stick_mode,           // 0 analog, 1 d-pad, 2 both
    input       [1:0] ana_curve,            // OSD analog response: 0 linear, 1 soft, 2 softer
    input       [1:0] ana_range,            // OSD analog range: 0 100%, 1 75%, 2 50%
    input             gun_mode,             // Rail Chase: 0 lightgun (absolute stick), 1 gamepad cursor
    input       [3:0] speed1, speed2,       // cursor speeds (OSD values 0..9)
    input             xhair_en,             // draw crosshairs in gamepad mode
    input             stick_hold,           // flight games (modes 1 and 4): the pad moves a held position instead of a spring-return stick
    input       [7:0] dsw_a, dsw_b,         // SW A (port G, coinage), SW B (port F)
    input             service, test,
    input             coin1, coin2,

    // video (320x224 inside the 400x262 grid)
    output      [7:0] r, g, b,
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

// sound clocks: 4 MHz = 2 pulses per 25 clk_sys (12/13 spacing), 8 MHz = 4
// pulses per 25 (for the simulation Z80 clock), jt51 cen_p1 = 2 MHz,
// PCM tick = 4 MHz / 128. Open question 3: the PCB notes' 16 MHz / 4.
reg [4:0] snd_div;
reg       ce_z80, ce_z80x2, ce_fm_p1, pcm_tick;
reg [6:0] pcm_div;
always @(posedge clk_sys) begin
    if (reset) begin snd_div <= 5'd0; ce_z80 <= 1'b0; ce_z80x2 <= 1'b0; ce_fm_p1 <= 1'b0; pcm_div <= 7'd0; pcm_tick <= 1'b0; end
    else begin
        // pause freezes the sound section with the CPUs (no hanging notes)
        snd_div  <= (snd_div == 5'd24) ? 5'd0 : snd_div + 5'd1;
        ce_z80   <= !pause && ((snd_div == 5'd0) || (snd_div == 5'd12));
        ce_z80x2 <= !pause && ((snd_div == 5'd0) || (snd_div == 5'd6) || (snd_div == 5'd12) || (snd_div == 5'd18));
        ce_fm_p1 <= !pause && (snd_div == 5'd0);
        pcm_tick <= 1'b0;
        if (!pause && (snd_div == 5'd0 || snd_div == 5'd12)) begin
            if (pcm_div == 7'd127) begin pcm_div <= 7'd0; pcm_tick <= 1'b1; end
            else pcm_div <= pcm_div + 7'd1;
        end
    end
end

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
wire        m_as_n, x_as_n, y_as_n;
wire        m_reset_out;     // main 68000 RESET instruction -> sub CPUs reset (MAME m68k_reset_callback)

yb_m68k_bus main_cpu (
    .clk(clk_sys), .reset(cpu_reset), .ce_phase(ce_cpu), .phase(phase),
    .ipl(ipl), .halt_n(1'b1),
    .bus_addr(m_addr), .bus_valid(m_valid), .bus_start(m_start),
    .bus_rd(m_rd), .bus_wr(m_wr), .bus_be(m_be),
    .bus_dout(m_dout), .bus_din(m_din), .bus_ack(m_ack), .reset_out(m_reset_out), .fc(m_fc), .bus_as_n(m_as_n)
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

// ---- sound latch (082001, odd byte): MAME's generic latch with its
// data-pending line on the Z80's NMI: a write raises it, the Z80's read
// of port 40 clears it
reg [7:0] snd_latch;
reg       snd_nmi;
wire      snd_read;
always @(posedge clk_sys) begin
    if (cpu_reset) begin snd_latch <= 8'd0; snd_nmi <= 1'b0; end
    else if (m_cs && m_wr && m_sel_snd && m_be[0]) begin snd_latch <= m_dout[7:0]; snd_nmi <= 1'b1; end
    else if (snd_read) snd_nmi <= 1'b0;
end

// ---- 315-5296 and the MSM6253 (low byte lane)
// Port A: P1 (unused); port B (MAME's GENERAL, active low): bit 0 After
// Burner (G-LOC, Strike Fighter), 1 test, 2 service, 3 start, 4 button 1,
// 5 button 2 or Power Drift's gear shift (active high, a toggle like MAME's
// PORT_TOGGLE: press to change gear), 6 coin 1, 7 coin 2. Rail Chase wires
// it differently: 0 P2 trigger, 1 P1 trigger, 2 and 3 service, 4 coin 1,
// 5 coin 2, 6 P2 start, 7 P1 start (no test bit; the test input goes to
// bit 2 so the OSD switch still reaches the game). Port C: limit switches
// and sensors, inactive (high, except Power Drift's four active-high ones);
// ports D/E/H are outputs; F = SW B, G = SW A.
wire [7:0] io_q, ph_out;
wire       io_fmcs;
wire       adc_d7;
wire is_pdrift = (board_desc.game_id == 8'd1);
wire is_rchase = (board_desc.game_id == 8'd3);
reg  gear_hi, btn_c_d;
always @(posedge clk_sys) begin
    btn_c_d <= p1_buttons[13];
    if (cpu_reset) gear_hi <= 1'b0;
    else if (p1_buttons[13] && !btn_c_d) gear_hi <= ~gear_hi;
end
wire [7:0] in_b_gen = ~{coin2, coin1 | p1_buttons[7], is_pdrift ? ~gear_hi : p1_buttons[5], p1_buttons[4],
                        p1_buttons[6], service | p1_buttons[9], test | p1_buttons[8], p1_buttons[13] && !is_pdrift};
wire [7:0] in_b_rc  = ~{p1_buttons[6], p2_buttons[6], coin2 | p2_buttons[7], coin1 | p1_buttons[7],
                        service | p1_buttons[9], test | service | p1_buttons[8] | p1_buttons[9], p1_buttons[4], p2_buttons[4]};
wire [7:0] in_b = is_rchase ? in_b_rc : in_b_gen;
wire [7:0] in_c = is_pdrift ? 8'hE4 : 8'hFF;   // Power Drift: sensors and limit switches (bits 0, 1, 3, 4) active high, the rest unused and low-active
yb_315_5296 io (
    .clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_io && m_be[0]), .we(m_wr),
    .addr(ma[6:1]), .din(m_dout[7:0]), .dout(io_q), .fmcs(io_fmcs),
    .in_a(8'hFF), .in_b(in_b), .in_c(in_c), .in_d(8'hFF), .in_e(8'hFF), .in_f(dsw_b), .in_g(dsw_a), .in_h(8'hFF),
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

// ---- analog inputs to the ADC channels, per the descriptor's analog mode
// (docs/DESIGN.md, Controls). The seven MAME channels are ADC 0-2 and the
// 74HC4052 inputs 0-3 on channel 3. Ranges follow MAME's PORT_MINMAX; the
// Y reversals come from the descriptor's adc_reverse (PORT_REVERSE).
//   0 Galaxy Force II: stick X on 0, Y on 1, throttle on 2, all 0x01..0xFF
//   1 G-LOC, Strike Fighter: stick Y on mux 0 (0x40..0xC0), throttle on
//     mux 1, stick X on mux 2 (0x20..0xE0)
//   2 Power Drift: brake on mux 0, gas on mux 1 (0x00 released), steering
//     on mux 2 (0x20..0xE0)
//   3 Rail Chase: P1 gun X, Y on 0, 1; P2 gun X on 2, Y on mux 0
//   4 G-LOC R360: mode 1 with the cabinet's pitch on 0 and roll on 2,
//     centred (the motor stub, open question 9)
// Unread channels read 0x80.
wire [2:0] am = board_desc.ana_mode;
wire flight_mode = (am == 3'd1) || (am == 3'd4);
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
function automatic [3:0] speed_idx(input [3:0] v);   // 1..10
    speed_idx = (v < 4'd6) ? (v + 4'd5) : (v - 4'd5);
endfunction
function automatic signed [7:0] dpad_axis(input neg, input pos, input signed [7:0] stick);
    dpad_axis = pos ? 8'sd100 : neg ? -8'sd100 : stick;
endfunction
function automatic [11:0] cursor_step(input [11:0] c, input signed [7:0] axis, input [3:0] idx);
    reg signed [13:0] d; reg signed [13:0] n;
    begin
        d = ($signed({{6{axis[7]}}, axis}) * $signed({10'd0, idx})) >>> 3;
        n = $signed({2'b00, c}) + d;
        cursor_step = (n < 14'sd0) ? 12'd0 : (n > 14'sd4095) ? 12'd4095 : n[11:0];
    end
endfunction
// the stick as a signed deflection: the d-pad is full lock, up and left negative
wire signed [7:0] in_x = (use_dpad && dpad_active) ? (p1_buttons[0] ? 8'sd127 : p1_buttons[1] ? -8'sd127 : 8'sd0) : use_analog ? sx_s : 8'sd0;
wire signed [7:0] in_y = (use_dpad && dpad_active) ? (p1_buttons[2] ? 8'sd127 : p1_buttons[3] ? -8'sd127 : 8'sd0) : use_analog ? sy_s : 8'sd0;
// "hold position" (OSD, flight games only): the pad moves a virtual stick
// that stays where it is left, full deflection crossing the range in about
// half a second, so a gamepad can fly G-LOC the way a self-centring stick
// held off centre does
wire       hold_on = stick_hold && flight_mode;
reg [11:0] vst_x, vst_y;
reg        vbl_vs_d;
always @(posedge clk_sys) begin
    vbl_vs_d <= vbl_irq;
    if (cpu_reset || !hold_on) begin vst_x <= 12'd2048; vst_y <= 12'd2048; end
    else if (vbl_irq && !vbl_vs_d) begin
        vst_x <= cursor_step(vst_x, in_x, 4'd8);
        vst_y <= cursor_step(vst_y, in_y, 4'd8);
    end
end
wire signed [7:0] dx_s = hold_on ? $signed(vst_x[11:4] ^ 8'h80) : in_x;
wire signed [7:0] dy_s = hold_on ? $signed(vst_y[11:4] ^ 8'h80) : in_y;
// full range (mode 0): 0x80 + deflection, so 0x01..0xFF with the d-pad
wire [7:0] fr_x = {~dx_s[7], dx_s[6:0]};
wire [7:0] fr_y = {~dy_s[7], dy_s[6:0]};
// flight (modes 1 and 4): Y within 0x40..0xC0 (half), X within 0x20..0xE0 (three quarters)
wire signed [7:0] dy_h = dy_s >>> 1;
wire signed [7:0] dx_q = dx_s - (dx_s >>> 2);
wire [7:0] fl_y = {~dy_h[7], dy_h[6:0]};
wire [7:0] fl_x = {~dx_q[7], dx_q[6:0]};
// driving (mode 2): the d-pad ramps the wheel, 8 per frame to full lock and
// 16 per frame back to centre, so it steers like a wheel and not a switch;
// the pedals are the buttons or the throttle axis either side of centre
reg signed [7:0] wheel;
reg        vbl_w_d;
always @(posedge clk_sys) begin
    vbl_w_d <= vbl_irq;
    if (cpu_reset) wheel <= 8'sd0;
    else if (vbl_irq && !vbl_w_d) begin
        if (use_dpad && p1_buttons[0])      wheel <= (wheel > 8'sd119) ? 8'sd127 : wheel + 8'sd8;
        else if (use_dpad && p1_buttons[1]) wheel <= (wheel < -8'sd119) ? -8'sd127 : wheel - 8'sd8;
        else                                wheel <= (wheel > 8'sd16) ? wheel - 8'sd16 : (wheel < -8'sd16) ? wheel + 8'sd16 : 8'sd0;
    end
end
wire signed [7:0] st_s = (use_dpad && (p1_buttons[0] || p1_buttons[1] || wheel != 8'sd0)) ? wheel : use_analog ? sx_s : 8'sd0;
wire signed [7:0] st_q = st_s - (st_s >>> 2);
wire [7:0] steer = {~st_q[7], st_q[6:0]};
wire [7:0] gas   = p1_buttons[11] ? 8'hFF : (throttle_s > 8'h80) ? {throttle_s[6:0], 1'b0} : 8'h00;
wire [7:0] brake = p1_buttons[12] ? 8'hFF : (throttle_s < 8'h80) ? {7'h7F - throttle_s[6:0], 1'b0} : 8'h00;
// guns (mode 3), one per player, as the X Board's Line of Fire. Lightgun
// mode: the stick is an absolute position (MiSTer's USB gun support
// delivers coordinates that way). Gamepad mode: a persistent cursor moved
// by the stick or D-pad at the OSD speed (values 0..9 stand for 50,60,..100,
// 10,20,30,40 percent), in 1/16 pixel units, advanced once per frame.
reg [11:0] cur1_x, cur1_y, cur2_x, cur2_y;
reg        vbl_gun_d;
always @(posedge clk_sys) begin
    vbl_gun_d <= vbl_irq;
    if (cpu_reset) begin cur1_x <= 12'd2048; cur1_y <= 12'd2048; cur2_x <= 12'd2048; cur2_y <= 12'd2048; end
    else if (vbl_irq && !vbl_gun_d) begin
        cur1_x <= cursor_step(cur1_x, dpad_axis(p1_buttons[1], p1_buttons[0], stick_x),  speed_idx(speed1));
        cur1_y <= cursor_step(cur1_y, dpad_axis(p1_buttons[3], p1_buttons[2], stick_y),  speed_idx(speed1));
        cur2_x <= cursor_step(cur2_x, dpad_axis(p2_buttons[1], p2_buttons[0], stick2_x), speed_idx(speed2));
        cur2_y <= cursor_step(cur2_y, dpad_axis(p2_buttons[3], p2_buttons[2], stick2_y), speed_idx(speed2));
    end
end
wire [7:0] gun1_x = gun_mode ? cur1_x[11:4] : {~stick_x[7],  stick_x[6:0]};
wire [7:0] gun1_y = gun_mode ? cur1_y[11:4] : {~stick_y[7],  stick_y[6:0]};
wire [7:0] gun2_x = gun_mode ? cur2_x[11:4] : {~stick2_x[7], stick2_x[6:0]};
wire [7:0] gun2_y = gun_mode ? cur2_y[11:4] : {~stick2_y[7], stick2_y[6:0]};
wire [7:0] adc_ch0  = (am == 3'd3) ? gun1_x : (am == 3'd0) ? fr_x   : 8'h80;
wire [7:0] adc_ch1  = (am == 3'd3) ? gun1_y : (am == 3'd0) ? fr_y   : 8'h80;
wire [7:0] adc_ch2  = (am == 3'd3) ? gun2_x : (am == 3'd0) ? thr_fl : 8'h80;
wire [7:0] adc_mux0 = (am == 3'd3) ? gun2_y : flight_mode ? fl_y   : (am == 3'd2) ? brake : 8'h80;
wire [7:0] adc_mux1 = flight_mode ? thr_fl : (am == 3'd2) ? gas   : 8'h80;
wire [7:0] adc_mux2 = flight_mode ? fl_x   : (am == 3'd2) ? steer : 8'h80;
wire [7:0] adc_mux3 = 8'h80;

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
    .bus_dout(x_dout), .bus_din(x_din), .bus_ack(x_ack), .reset_out(), .fc(x_fc), .bus_as_n(x_as_n)
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
// Y sprite RAM (64 KB): port B is the 315-5305's
yb_dpram #(.AW(15)) yspriteram (.clk(clk_sys), .a_addr(xa[15:1]), .a_din(x_dout), .a_be(x_be),
    .a_we(x_valid && x_wr && x_sel_yspr && x_start), .a_dout(yspr_q),
    .b_clk(clk_ram), .b_addr(yspr_rd_addr), .b_dout(yspr_rd_q));
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
    .bus_dout(y_dout), .bus_din(y_din), .bus_ack(y_ack), .reset_out(), .fc(y_fc), .bus_as_n(y_as_n)
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
    .b_clk(clk_ram), .b_addr({~rot_bank, rot_rd_addr}), .b_dout(rot_rd_q));
wire [10:0] bspr_rd_addr; wire [15:0] bspr_rd_q;
yb_dpram #(.AW(11)) bspriteram (.clk(clk_sys), .a_addr(ya[11:1]), .a_din(y_dout), .a_be(y_be),
    .a_we(y_valid && y_wr && y_sel_bspr && y_start), .a_dout(bspr_q),
    .b_clk(clk_ram), .b_addr(bspr_rd_addr), .b_dout(bspr_rd_q));
// the palette (315-5242) is instantiated with the video pipeline below

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
// A CPU that has just read keeps the RAM until its next bus cycle starts:
// if that cycle is the write half of a read-modify-write (tas, whose AS
// stays low throughout, or bclr/bset/addq on memory, which are two plain
// cycles a few clocks apart) it is served first, and an instruction fetch
// releases the hold. Without it Power Drift's lock byte at 0CEB43 was set
// back by sub Y's stale tas write right after main had released it, and
// later the acknowledge sub Y wrote into 0CFF12 landed between the read
// and the write of main's bclr and was overwritten, so the race never
// started. MAME's instructions are atomic; the board's PALs must span the
// gap as well. A holder that stalls (reset, halted) is released by a
// timeout so nobody starves.
reg   [1:0] shr_hold;   // 0 free, 1 main, 2 sub X, 3 sub Y
reg   [7:0] shr_hold_t; // clocks since the hold was taken
wire        hold_free  = (shr_hold == 2'd0);
wire        shr_pick_m = m_shr_pend && (hold_free || shr_hold == 2'd1);
wire        shr_pick_x = x_shr_pend && !shr_pick_m && (hold_free || shr_hold == 2'd2);
wire        shr_pick_y = y_shr_pend && !shr_pick_m && !shr_pick_x && (hold_free || shr_hold == 2'd3);
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
        shr_hold <= 2'd0; shr_hold_t <= 8'd0;
    end
    else begin
        shr_hold_t <= (shr_hold == 2'd0) ? 8'd0 : shr_hold_t + 8'd1;
        if (shr_pick_m && m_rd)      begin shr_hold <= 2'd1; shr_hold_t <= 8'd0; end
        else if (shr_pick_x && x_rd) begin shr_hold <= 2'd2; shr_hold_t <= 8'd0; end
        else if (shr_pick_y && y_rd) begin shr_hold <= 2'd3; shr_hold_t <= 8'd0; end
        else if ((shr_hold == 2'd1 && ((m_start && !m_sel_shr) || (shr_pick_m && m_wr) || cpu_reset)) ||
                 (shr_hold == 2'd2 && ((x_start && !x_sel_shr) || (shr_pick_x && x_wr) || cpu_reset || m_reset_out || xres)) ||
                 (shr_hold == 2'd3 && ((y_start && !y_sel_shr) || (shr_pick_y && y_wr) || cpu_reset || m_reset_out || yres)) ||
                 (shr_hold != 2'd0 && shr_hold_t == 8'd255)) shr_hold <= 2'd0;
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
    // a write into ROM space is acknowledged and dropped: the board's DTACK
    // logic does not look at R/W and MAME ignores it; G-LOC R360 clears 64 KB
    // at 040000 on the way into a fight and stalled here until the watchdog
    if (m_sel_rom)       begin m_din = m_rom_data; m_ack = m_wr ? m_ram_rdy : m_rom_ack; end
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
    if (x_sel_rom)       begin x_din = x_rom_data; x_ack = x_wr ? x_ram_rdy : x_rom_ack; end
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
    if (y_sel_rom)       begin y_din = y_rom_data; y_ack = y_wr ? y_ram_rdy : y_rom_ack; end
    else if (y_sel_shr)  begin y_din = y_shr_q;    y_ack = y_shr_ack; end
    else if (y_sel_lram) begin y_din = y_lram_q;   y_ack = y_ram_rdy; end
    else if (y_sel_rot)  begin y_din = rot_q;      y_ack = y_ram_rdy; end
    else if (y_sel_bspr) begin y_din = bspr_q;     y_ack = y_ram_rdy; end
    else if (y_sel_pal)  begin y_din = pal_q;      y_ack = y_ram_rdy; end
    else if (y_sel_mult) begin y_din = y_mult_q;   y_ack = y_ram_rdy; end
    else if (y_sel_div)  begin y_din = y_div_q;    y_ack = y_ram_rdy && y_div_rdy; end
    else                 begin y_din = 16'hFFFF;   y_ack = y_ram_rdy; end   // rotation control, unmapped
end

// ================================================================ Y sprites (M2)
// The 315-5305 renders into the DDR3 framebuffers in clk_ram; the timing
// pulses cross from clk_sys through 2-flop synchronisers on levels that are
// high for a whole line (clean edges). The render starts at line 226: the
// IRQ4 handler (line 223) has by then flipped the list head in sprite RAM
// and swapped the rotation RAM, so the renderer reads a consistent list
// (verif/board +trace_vid showed the head write and the swap at line 223,
// the list bodies written during the frame into lists not linked in).
wire       go_lvl = (vcnt == 9'd226);
reg  [1:0] r_vbl_s, r_go_s, r_line_s;
reg        r_vbl_d, r_go_d, r_line_d;
reg  [8:0] r_vcnt_a, r_vcnt_b;
reg  [7:0] r_banks_a, r_banks_b;   // descriptor bank counts, quasi-static, into clk_ram
reg  [7:0] r_bbanks_a, r_bbanks_b;
reg        line_start_lvl;
always @(posedge clk_sys) if (line_start) line_start_lvl <= 1'b1; else if (ce_pix && hcnt == 9'd200) line_start_lvl <= 1'b0;
always @(posedge clk_ram) begin
    r_vbl_s  <= {r_vbl_s[0],  vbl_irq};
    r_go_s   <= {r_go_s[0],   go_lvl};
    r_line_s <= {r_line_s[0], line_start_lvl};
    r_vcnt_a <= vcnt; r_vcnt_b <= r_vcnt_a;
    r_banks_a <= board_desc.yspr_banks; r_banks_b <= r_banks_a;
    r_bbanks_a <= board_desc.bspr_banks; r_bbanks_b <= r_bbanks_a;
    r_vbl_d <= r_vbl_s[1]; r_go_d <= r_go_s[1]; r_line_d <= r_line_s[1];
end
wire r_vbl_start  = r_vbl_s[1] & ~r_vbl_d;
wire r_go         = r_go_s[1] & ~r_go_d;
wire r_line_start = r_line_s[1] & ~r_line_d;

wire        fbw_start, fbw_valid, fbw_end, fbw_busy, fbw_dup;
wire        fbe_req, fbe_ack, fbr_req, fbr_ack;
wire  [1:0] fbw_buf, fbe_buf, fbr_buf;
wire  [9:0] fbw_x;
wire  [3:0] fbw_lanes;
wire  [8:0] fbw_y, fbw_dup_y, fbe_y, fbr_y;
wire [15:0] fbw_pix, fbr_pix;
wire        spr_disp_buf, spr_rendering;
wire [191:0] disp_rot;
wire        rq_req, rq_ack; wire [1:0] rq_buf; wire [8:0] rq_y; wire [6:0] rq_xw; wire [63:0] rq_data;
wire [14:0] yspr_rd_addr; wire [15:0] yspr_rd_q;
wire  [9:0] rot_rd_addr;  wire [15:0] rot_rd_q;
yb_ysprite_5305 sprites (
    .clk(clk_ram), .reset(reset), .num_banks(r_banks_b),
    .start_req(r_go), .vbl_start(r_vbl_start), .line_start(r_line_start), .vcnt(r_vcnt_b),
    .sram_addr(yspr_rd_addr), .sram_q(yspr_rd_q),
    .rot_addr(rot_rd_addr), .rot_q(rot_rd_q),
    .rom_req(p2_req), .rom_addr(p2_addr), .rom_dout(p2_dout), .rom_ack(p2_ack),
    .fb_wr_start(fbw_start), .fb_wr_buf(fbw_buf), .fb_wr_x(fbw_x), .fb_wr_lanes(fbw_lanes), .fb_wr_y(fbw_y),
    .fb_wr_valid(fbw_valid), .fb_wr_pix(fbw_pix), .fb_wr_end(fbw_end), .fb_wr_dup(fbw_dup), .fb_wr_dup_y(fbw_dup_y), .fb_wr_busy(fbw_busy),
    .fb_er_req(fbe_req), .fb_er_buf(fbe_buf), .fb_er_y(fbe_y), .fb_er_ack(fbe_ack),
    .fb_rd_req(fbr_req), .fb_rd_buf(fbr_buf), .fb_rd_y(fbr_y), .fb_rd_ack(fbr_ack),
    .disp_buf(spr_disp_buf), .disp_rot(disp_rot), .rendering(spr_rendering)
);
// 315-5306 scan-out: builds each screen line one line ahead from the
// displayed buffer through its word cache (clk_ram); the display reads its
// line buffer at hcnt
wire [12:0] rot_idx; wire [7:0] rot_pri;
wire  [8:0] rot_miss; wire [12:0] rot_clocks; wire [15:0] rot_late;
yb_rotate_5306 rotate (
    .clk(clk_ram), .reset(reset),
    .line_start(r_line_start), .vcnt(r_vcnt_b), .disp_buf(spr_disp_buf), .disp_rot(disp_rot),
    .rq_req(rq_req), .rq_buf(rq_buf), .rq_y(rq_y), .rq_xw(rq_xw), .rq_ack(rq_ack), .rq_data(rq_data),
    .rd_clk(clk_sys), .rd_line_start(line_start && vcnt <= 9'd223), .rd_x(hcnt), .rd_idx(rot_idx), .rd_pri(rot_pri),
    .miss_count(rot_miss), .line_clocks(rot_clocks), .late_count(rot_late)
);
// 315-5196 16B sprites: the list is snapshotted at line 226 (sub Y rewrites
// it from the IRQ2 handler, lines 170-182) and each line is built one line
// ahead into its own line buffer
wire [15:0] bspr_pix;
wire [12:0] bspr_clocks; wire [15:0] bspr_late;
yb_bsprite_5196 bsprites (
    .clk(clk_ram), .reset(reset), .num_banks(r_bbanks_b),
    .snap(r_go), .line_start(r_line_start), .vcnt(r_vcnt_b),
    .sram_addr(bspr_rd_addr), .sram_q(bspr_rd_q),
    .rom_req(p4_req), .rom_addr(p4_addr), .rom_dout(p4_dout), .rom_ack(p4_ack),
    .rd_clk(clk_sys), .rd_line_start(line_start && vcnt <= 9'd223), .rd_x(hcnt), .rd_pix(bspr_pix),
    .line_clocks(bspr_clocks), .late_count(bspr_late)
);
assign p4_urgent = 1'b0;
yb_fb_if #(.FB_BASE(32'h3000_0000)) fb (
    .clk(clk_ram), .rst(reset), .hires(1'b0),
    .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .wr_start(fbw_start), .wr_buf(fbw_buf), .wr_x(fbw_x), .wr_lanes(fbw_lanes), .wr_y(fbw_y), .wr_dup(fbw_dup), .wr_dup_y(fbw_dup_y),
    .wr_valid(fbw_valid), .wr_pix(fbw_pix), .wr_end(fbw_end), .wr_shadow(1'b0), .wr_busy(fbw_busy),
    .er_req(fbe_req), .er_buf(fbe_buf), .er_y(fbe_y), .er_ack(fbe_ack),
    .rq_req(rq_req), .rq_buf(rq_buf), .rq_y(rq_y), .rq_xw(rq_xw), .rq_ack(rq_ack), .rq_data(rq_data),
    .rd_req(fbr_req), .rd_buf(fbr_buf), .rd_y(fbr_y), .rd_ack(fbr_ack),
    .rd_x(10'd0), .rd_pix(fbr_pix), .rd_pub_ok(1'b1)
);

// ================================================================ video (M4)
// 315-5312 mixer (MAME segaybd_v.cpp screen_update): the rotated Y layer is
// the base (palette index, priority); a 16B pixel wins when its priority
// nibble, shifted, is below the Y priority's low five bits, and then either
// shadows the Y pixel (pen E: the palette's effects copy) or replaces it
// with 0x800 | pixel[10:0]. Both line buffers are read at hcnt (two clocks
// after ce_out), then the palette (2 clocks): the RGB of pixel hcnt is ready
// before the next pixel enable, when the framework samples it with the
// blanking of the same pixel, so blanking and sync are not delayed.
reg        ce_pix_d1, ce_pix_d2;
reg [12:0] pal_idx;
reg        pal_eff;
wire       b_win    = (bspr_pix != 16'hFFFF) && ({bspr_pix[15:12], 1'b0} < rot_pri[4:0]);
wire       b_shadow = b_win && (bspr_pix[3:0] == 4'hE);
always @(posedge clk_sys) begin
    ce_pix_d1 <= ce_out; ce_pix_d2 <= ce_pix_d1;
    if (ce_pix_d2) begin
        pal_idx <= (b_win && !b_shadow) ? {2'b01, bspr_pix[10:0]} : rot_idx;
        pal_eff <= b_shadow;
    end
end
wire [7:0] pal_r, pal_g, pal_b;
yb_palette_5242 palette (.clk(clk_sys), .a_addr(ya[13:1]), .a_din(y_dout), .a_be(y_be),
    .a_we(y_valid && y_wr && y_sel_pal && y_start), .a_dout(pal_q),
    .b_addr(pal_idx), .b_effects(pal_eff), .r(pal_r), .g(pal_g), .b(pal_b));
assign hb = ohblank; assign vb = vblank; assign hs = ohsync; assign vs = vsync;
// crosshair overlay for the gamepad gun mode (P1 white, P2 yellow): the
// 0..255 positions map to the 320x224 screen as MAME's crosshairs do
wire        xh_on = xhair_en && gun_mode && (am == 3'd3);
wire [11:0] xh1_xm = {4'b0000, gun1_x} * 12'd5, xh1_ym = {4'b0000, gun1_y} * 12'd7;
wire [11:0] xh2_xm = {4'b0000, gun2_x} * 12'd5, xh2_ym = {4'b0000, gun2_y} * 12'd7;
wire  [9:0] xh1_x = xh1_xm[11:2], xh1_y = {1'b0, xh1_ym[11:3]};   // *1.25 -> 0..318, *0.875 -> 0..223
wire  [9:0] xh2_x = xh2_xm[11:2], xh2_y = {1'b0, xh2_ym[11:3]};
function automatic cross_hit(input [8:0] hc, input [8:0] vc, input [9:0] cx, input [9:0] cy);
    reg [9:0] dx, dy;
    begin
        dx = ({1'b0, hc} > cx) ? ({1'b0, hc} - cx) : (cx - {1'b0, hc});
        dy = ({1'b0, vc} > cy) ? ({1'b0, vc} - cy) : (cy - {1'b0, vc});
        cross_hit = (dx == 10'd0 && dy <= 10'd3) || (dy == 10'd0 && dx <= 10'd3);
    end
endfunction
wire xh1 = xh_on && cross_hit(hcnt, vcnt, xh1_x, xh1_y);
wire xh2 = xh_on && cross_hit(hcnt, vcnt, xh2_x, xh2_y);
assign r = (ohblank | vblank | !display_enable) ? 8'd0 : (xh1 | xh2) ? 8'hFF : pal_r;
assign g = (ohblank | vblank | !display_enable) ? 8'd0 : (xh1 | xh2) ? 8'hFF : pal_g;
assign b = (ohblank | vblank | !display_enable) ? 8'd0 : xh1 ? 8'hFF : xh2 ? 8'h00 : pal_b;

// ---------------------------------------------------------------- tie-offs
assign p7_req = 1'b0; assign p7_addr = '0;

// ---------------------------------------------------------------- sound
// Z80, YM2151 and 315-5218 as on the X Board; /SRES from port E bit 4,
// /MUTE from port H bit 7. ROM through SDRAM p5, samples through p6.
yb_soundsys sound (
    .clk(clk_sys), .reset(reset), .z80_reset_n(snd_reset_n),
    .ce_z80(ce_z80), .ce_z80x2(ce_z80x2), .ce_fm(ce_z80), .ce_fm_p1(ce_fm_p1), .pcm_tick(pcm_tick),
    .mute_n(mute_n), .pcm_bankmask(board_desc.pcm_bankmask),
    .snd_latch(snd_latch), .snd_nmi(snd_nmi), .snd_read(snd_read),
    .zrom_req(p5_req), .zrom_addr(p5_addr), .zrom_dout(p5_dout), .zrom_ack(p5_ack),
    .pcm_req(p6_req), .pcm_addr(p6_addr), .pcm_dout(p6_dout), .pcm_ack(p6_ack),
    .audio_l(audio_l), .audio_r(audio_r)
);

endmodule
