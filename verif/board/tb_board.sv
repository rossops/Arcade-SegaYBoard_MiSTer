//============================================================================
//  Board simulation top (Verilator). Clocks come from the C++ driver.
//  Writes one PPM per frame, 48 kHz audio, and (from M1) the executed-PC
//  traces of the three 68000s.
//============================================================================
`timescale 1ns/1ps
import yb_pkg::*;

module tb_board (
    input clk_sys,
    input clk_ram,
    input reset,
    input [31:0] max_frames,
    output reg [31:0] frame
);

board_desc_t desc;
integer pa;
reg [7:0] dsw_a, dsw_b;
initial begin dsw_a = 8'hFF; dsw_b = 8'h7E; if ($value$plusargs("dswa=%h", pa)) dsw_a = pa[7:0]; if ($value$plusargs("dswb=%h", pa)) dsw_b = pa[7:0]; end
// descriptor: gforce2 unless plusargs say otherwise (tools/romsets.py has the values)
initial begin
    desc = '0;
    desc.game_id = 8'd0; desc.yspr_banks = 8'd8; desc.bspr_banks = 8'd4;
    desc.adc_reverse = 8'h02; desc.pcm_bankmask = 8'hF8; desc.ana_mode = 3'd0; desc.irq2_line = 8'd170;
    if ($value$plusargs("game_id=%d", pa))     desc.game_id = pa[7:0];
    if ($value$plusargs("deluxe=%d", pa))      desc.deluxe = pa[0];
    if ($value$plusargs("link=%d", pa))        desc.link = pa[0];
    if ($value$plusargs("r360=%d", pa))        desc.r360 = pa[0];
    if ($value$plusargs("yspr_banks=%d", pa))  desc.yspr_banks = pa[7:0];
    if ($value$plusargs("bspr_banks=%d", pa))  desc.bspr_banks = pa[7:0];
    if ($value$plusargs("adc_reverse=%h", pa)) desc.adc_reverse = pa[7:0];
    if ($value$plusargs("ana_mode=%d", pa))    desc.ana_mode = pa[2:0];
    if ($value$plusargs("irq2=%d", pa))        desc.irq2_line = pa[7:0];
end

wire p0_req, p1_req, p2_req, p3_req, p4_req, p5_req, p6_req, p7_req, p3_urgent, p4_urgent;
wire p0_ack, p1_ack, p2_ack, p3_ack, p4_ack, p5_ack, p6_ack, p7_ack, wr_ack, sdr_ready;
wire [24:3] p0_addr, p1_addr, p3_addr, p5_addr;
wire [24:4] p2_addr, p4_addr, p7_addr;
wire [24:1] p6_addr;
wire [63:0] p0_dout, p1_dout, p3_dout, p5_dout;
wire [127:0] p2_dout, p4_dout, p7_dout;
wire [15:0] p6_dout;

sdram_model sdram (
    .clk(clk_ram), .init(reset), .ready(sdr_ready),
    .wr_req(1'b0), .wr_addr(24'd0), .wr_din(16'd0), .wr_be(2'd0), .wr_ack(wr_ack),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(p3_req), .p3_addr(p3_addr), .p3_dout(p3_dout), .p3_ack(p3_ack), .p3_urgent(p3_urgent),
    .p4_req(p4_req), .p4_addr(p4_addr), .p4_dout(p4_dout), .p4_ack(p4_ack), .p4_urgent(p4_urgent),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack),
    .p6_req(p6_req), .p6_addr(p6_addr), .p6_dout(p6_dout), .p6_ack(p6_ack),
    .p7_req(p7_req), .p7_addr(p7_addr), .p7_dout(p7_dout), .p7_ack(p7_ack)
);

wire [7:0] r, g, b;
wire ce_pix, hs, vs, hb, vb;
wire signed [15:0] al, ar;
wire [23:1] tm_addr, tx_addr, ty_addr; wire tm_start, tx_start, ty_start; wire [2:0] tm_fc, tx_fc, ty_fc;

wire        DDRAM_BUSY, DDRAM_DOUT_READY, DDRAM_RD, DDRAM_WE;
wire  [7:0] DDRAM_BURSTCNT, DDRAM_BE;
wire [28:0] DDRAM_ADDR;
wire [63:0] DDRAM_DOUT, DDRAM_DIN;
ddram_model ddram (
    .clk(clk_ram), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE)
);

yb_core core (
    .clk_sys(clk_sys), .clk_ram(clk_ram), .reset(reset), .pause(1'b0), .board_desc(desc),
    .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(p3_req), .p3_addr(p3_addr), .p3_dout(p3_dout), .p3_ack(p3_ack), .p3_urgent(p3_urgent),
    .p4_req(p4_req), .p4_addr(p4_addr), .p4_dout(p4_dout), .p4_ack(p4_ack), .p4_urgent(p4_urgent),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack),
    .p6_req(p6_req), .p6_addr(p6_addr), .p6_dout(p6_dout), .p6_ack(p6_ack),
    .p7_req(p7_req), .p7_addr(p7_addr), .p7_dout(p7_dout), .p7_ack(p7_ack),
    .nv_download(1'b0), .nv_upload(1'b0), .nv_wr(1'b0), .nv_rd(1'b0), .nv_addr(13'd0), .nv_din(16'd0), .nv_dout(), .nv_modified(),
    .p1_buttons({9'd0, p1_start, 6'd0}), .p2_buttons(16'd0),
    .stick_x(8'sd0), .stick_y(8'sd0), .stick2_x(8'sd0), .stick2_y(8'sd0), .throttle(8'h80),
    .stick_mode(2'd0), .ana_curve(2'd0), .ana_range(2'd0),
    .dsw_a(dsw_a), .dsw_b(dsw_b), .service(1'b0), .test(1'b0), .coin1(coin1), .coin2(1'b0),
    .r(r), .g(g), .b(b), .ce_vid(ce_pix), .hs(hs), .vs(vs), .hb(hb), .vb(vb),
    .audio_l(al), .audio_r(ar),
    .trace_main_addr(tm_addr), .trace_main_start(tm_start), .trace_main_fc(tm_fc),
    .trace_subx_addr(tx_addr), .trace_subx_start(tx_start), .trace_subx_fc(tx_fc),
    .trace_suby_addr(ty_addr), .trace_suby_start(ty_start), .trace_suby_fc(ty_fc)
);

// ---- traces
//  trace_*_rtl.txt : program-space word fetches (FC = 2 user / 6 supervisor)
//  trace_*_pc.txt  : executed instructions: the PC when fx68k moves IR to
//                    IRD (instruction start). fx68k's PC register then holds
//                    instruction address + 4 (two prefetched words).
integer fm, fx, fy, fmp, fxp, fyp, fppm;
initial begin
    fm  = $fopen("trace_main_rtl.txt", "w");
    fx  = $fopen("trace_subx_rtl.txt", "w");
    fy  = $fopen("trace_suby_rtl.txt", "w");
    fmp = $fopen("trace_main_pc.txt", "w");
    fxp = $fopen("trace_subx_pc.txt", "w");
    fyp = $fopen("trace_suby_pc.txt", "w");
    frame = 0;
end
// Instruction addresses follow fx68k's prefetch queue: the word captured
// into Irc (xToIrc & enPhi2) comes from address eab; Ir <= Irc and
// Ird <= Ir shift the matching address along, so at Ird load the queued
// address is exactly the executing instruction's address.
// M1 instantiates this once per CPU: `CPU_TRACE(mt, core.main_cpu.cpu, fmp) etc.
`define CPU_TRACE(pfx, cpu, fh) \
reg [23:1] pfx``_a_irc, pfx``_a_ir, pfx``_a_ird; \
reg [23:1] pfx``_last; \
always @(posedge clk_sys) begin \
    if (reset) begin pfx``_a_irc <= 0; pfx``_a_ir <= 0; pfx``_a_ird <= 0; pfx``_last <= 23'h7fffff; end \
    else begin \
        if (cpu.excUnit.dataIo.xToIrc && cpu.enPhi2) pfx``_a_irc <= cpu.eab; \
        if (cpu.enT1) begin \
            if (cpu.Nanod.Ir2Ird) begin \
                pfx``_a_ird <= pfx``_a_ir; \
                if (pfx``_a_ir != pfx``_last) begin $fwrite(fh, "%06x\n", {pfx``_a_ir, 1'b0}); pfx``_last <= pfx``_a_ir; end \
            end \
            else if (cpu.microLatch[0]) pfx``_a_ir <= pfx``_a_irc; \
        end \
    end \
end
always @(posedge clk_sys) begin
    if (!reset) begin
        if (tm_start && tm_fc[1]) $fwrite(fm, "%06x\n", {tm_addr, 1'b0});
        if (tx_start && tx_fc[1]) $fwrite(fx, "%06x\n", {tx_addr, 1'b0});
        if (ty_start && ty_fc[1]) $fwrite(fy, "%06x\n", {ty_addr, 1'b0});
    end
end

// ---- +dumpframe=N: RAM dumps at the start of that frame's vblank (M2 adds the RAMs)
integer dumpframe = -1;
initial begin if (!$value$plusargs("dumpframe=%d", dumpframe)) dumpframe = -1; end

// ---- +coin=N: press Coin 1 for four frames from frame N (matches tools/mame_coin.lua)
integer coin_frame = -1;
initial begin if (!$value$plusargs("coin=%d", coin_frame)) coin_frame = -1; end
wire coin1 = (coin_frame >= 0) && (frame >= coin_frame) && (frame < coin_frame + 4);
// ---- +start=N: press P1 Start for four frames from frame N
integer start_frame = -1;
initial begin if (!$value$plusargs("start=%d", start_frame)) start_frame = -1; end
wire p1_start = (start_frame >= 0) && (frame >= start_frame) && (frame < start_frame + 4);

// ---- audio: 48 kHz stereo, raw little-endian 16-bit (audio.raw)
integer faud;
reg [15:0] aud_acc;      // 48000/50e6 = 0.00096 -> add 63 per clock (16-bit phase acc: 65536*0.00096=62.9)
reg aud_ovf;
initial faud = $fopen("audio.raw", "wb");
always @(posedge clk_sys) begin
    if (!reset) begin
        {aud_ovf, aud_acc} <= aud_acc + 16'd63;
        if (aud_ovf) $fwrite(faud, "%c%c%c%c", al[7:0], al[15:8], ar[7:0], ar[15:8]);
    end
end

// ---- frame dump: one PPM per frame (320x224)
reg vb_d;
reg ppm_open;
string fname;
always @(posedge clk_sys) begin
    vb_d <= vb;
    if (vb && !vb_d) begin
        if (ppm_open) begin $fclose(fppm); ppm_open <= 0; end
        frame <= frame + 1;
        if (frame + 1 == max_frames) $finish;
    end
    if (!vb && vb_d) begin
        $sformat(fname, "frame_%04d.ppm", frame);
        fppm = $fopen(fname, "wb");
        $fwrite(fppm, "P6\n320 224\n255\n");
        ppm_open <= 1;
    end
    if (ce_pix && !hb && !vb && ppm_open) $fwrite(fppm, "%c%c%c", r, g, b);
end
endmodule
