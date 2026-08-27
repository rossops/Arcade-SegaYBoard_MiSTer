//============================================================================
//  Sega Y Board — board top
//  M0: the port list only. The framework side (Arcade-SegaYBoard.sv) and the
//  board bench (verif/board/tb_board.sv) are wired to this interface; the
//  milestones fill the body in: M1 the three 68000s, RAMs, 315-5296, ADC and
//  interrupts, M2/M3 the 315-5305 Y sprites and 315-5306 rotation, M4 the 16B
//  sprites and mixer, M5 the sound board. Until then the output is a colour
//  gradient on the real video timing so a build can be checked on the bench.
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

    // SDRAM read ports (sdram.sv p0..p7; the CPU caches, Z80, PCM and the two
    // sprite fetchers are assigned in M1..M4)
    output            p0_req, output [24:3] p0_addr, input  [63:0] p0_dout, input p0_ack,
    output            p1_req, output [24:3] p1_addr, input  [63:0] p1_dout, input p1_ack,
    output            p2_req, output [24:4] p2_addr, input [127:0] p2_dout, input p2_ack,
    output            p3_req, output [24:3] p3_addr, input  [63:0] p3_dout, input p3_ack, output p3_urgent,
    output            p4_req, output [24:4] p4_addr, input [127:0] p4_dout, input p4_ack, output p4_urgent,
    output            p5_req, output [24:3] p5_addr, input  [63:0] p5_dout, input p5_ack,
    output            p6_req, output [24:1] p6_addr, input  [15:0] p6_dout, input p6_ack,
    output            p7_req, output [24:4] p7_addr, input [127:0] p7_dout, input p7_ack,

    // backup RAM (16 KB on sub X) as ioctl index 3
    input             nv_download,
    input             nv_upload,
    input             nv_wr,
    input             nv_rd,
    input      [12:0] nv_addr,        // word address 0..0x1FFF
    input      [15:0] nv_din,
    output     [15:0] nv_dout,
    output            nv_modified,

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

// M0 placeholder picture: x gradient in red, y gradient in green, blue on the
// right-hand 64 columns. Black outside the 320x224 window.
always @(posedge clk_sys) begin
    if (ce_out) begin
        if (ohblank || vblank) begin
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

assign p0_req = 1'b0; assign p0_addr = '0;
assign p1_req = 1'b0; assign p1_addr = '0;
assign p2_req = 1'b0; assign p2_addr = '0;
assign p3_req = 1'b0; assign p3_addr = '0; assign p3_urgent = 1'b0;
assign p4_req = 1'b0; assign p4_addr = '0; assign p4_urgent = 1'b0;
assign p5_req = 1'b0; assign p5_addr = '0;
assign p6_req = 1'b0; assign p6_addr = '0;
assign p7_req = 1'b0; assign p7_addr = '0;

assign nv_dout     = 16'd0;
assign nv_modified = 1'b0;

assign audio_l = 16'sd0;
assign audio_r = 16'sd0;

assign trace_main_addr = '0; assign trace_main_start = 1'b0; assign trace_main_fc = 3'd0;
assign trace_subx_addr = '0; assign trace_subx_start = 1'b0; assign trace_subx_fc = 3'd0;
assign trace_suby_addr = '0; assign trace_suby_start = 1'b0; assign trace_suby_fc = 3'd0;

endmodule
