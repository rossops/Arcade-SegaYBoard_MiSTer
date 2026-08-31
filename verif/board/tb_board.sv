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
    .p1_buttons({9'd0, p1_start, 6'd0} | hold_now), .p2_buttons(16'd0),
    .stick_x(8'sd0), .stick_y(8'sd0), .stick2_x(8'sd0), .stick2_y(8'sd0), .throttle(8'h80),
    .stick_mode(2'd0), .ana_curve(2'd0), .ana_range(2'd0),
    .gun_mode(1'b0), .speed1(4'd0), .speed2(4'd0), .xhair_en(1'b0), .stick_hold(1'b0), .shifter_en(shifter_sw),
    .dsw_a(dsw_a), .dsw_b(dsw_b), .service(1'b0), .test(test_sw), .coin1(coin1), .coin2(1'b0),
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
`CPU_TRACE(mt, core.main_cpu.cpu, fmp)
`CPU_TRACE(xt, core.subx_cpu.cpu, fxp)
`CPU_TRACE(yt, core.suby_cpu.cpu, fyp)
always @(posedge clk_sys) begin
    if (!reset) begin
        if (tm_start && tm_fc[1]) $fwrite(fm, "%06x\n", {tm_addr, 1'b0});
        if (tx_start && tx_fc[1]) $fwrite(fx, "%06x\n", {tx_addr, 1'b0});
        if (ty_start && ty_fc[1]) $fwrite(fy, "%06x\n", {ty_addr, 1'b0});
    end
end

// ---- port E (display enable, resets, watchdog kick; the ADC mux bits are left out) and watchdog resets
reg [7:0] pe_d;
always @(posedge clk_sys) begin
    pe_d <= core.pe_out;
    if (core.pe_out[7:2] != pe_d[7:2]) $display("PORTE f=%0d line=%0d %02x (/KILL=%0d /WDCL=%0d /SRES=%0d XRES=%0d YRES=%0d)", frame, core.vcnt, core.pe_out,
        core.pe_out[7], core.pe_out[5], core.pe_out[4], core.pe_out[3], core.pe_out[2]);
    if (core.wd_reset) $display("WATCHDOG reset f=%0d", frame);
end

// ---- +trace_vid: when sub Y swaps the rotation RAM and where sub X writes the
// sprite list (first/last line with writes per frame), to place the render
reg trace_vid; initial trace_vid = $test$plusargs("trace_vid");
integer ys_first = -1, ys_last = -1, ys_n = 0, bs_first = -1, bs_last = -1, bs_n = 0;
reg vb_tv_d, rend_d;
always @(posedge clk_sys) begin
    vb_tv_d <= vb;
    if (trace_vid && core.y_cs && core.y_rd && core.y_sel_rotc) $display("ROTSWAP f=%0d line=%0d", frame, core.vcnt);
    rend_d <= core.sprites.rendering;
    if (trace_vid && core.sprites.rendering != rend_d) $display("RENDER %s f=%0d line=%0d", core.sprites.rendering ? "start" : "end", frame, core.vcnt);
    if (trace_vid && core.y_start && core.y_wr && core.y_sel_bspr) begin
        if (bs_first < 0) bs_first = core.vcnt; bs_last = core.vcnt; bs_n = bs_n + 1;
        if (bs_n < 3) $display("BSPRW f=%0d line=%0d a=%04x d=%04x", frame, core.vcnt, {core.ya[11:1], 1'b0}, core.y_dout);
    end
    if (trace_vid && core.x_start && core.x_wr && core.x_sel_yspr) begin
        if (ys_first < 0) ys_first = core.vcnt; ys_last = core.vcnt; ys_n = ys_n + 1;
        if (ys_n < 4 || core.vcnt == 9'd223) $display("YSPRW f=%0d line=%0d a=%05x d=%04x", frame, core.vcnt, {core.xa[15:1], 1'b0}, core.x_dout);
    end
    if (trace_vid && vb && !vb_tv_d) begin
        $display("YSPR-WRITES f=%0d n=%0d first_line=%0d last_line=%0d", frame, ys_n, ys_first, ys_last);
        $display("BSPR-WRITES f=%0d n=%0d first_line=%0d last_line=%0d", frame, bs_n, bs_first, bs_last);
        ys_first = -1; ys_last = -1; ys_n = 0; bs_first = -1; bs_last = -1; bs_n = 0;
    end
end

// ---- 315-5306 scan-out statistics: worst DDR3 misses and clocks per line in
// each frame, and lines that were not ready at their deadline (cumulative)
integer rot_miss_max = 0, rot_clk_max = 0, bs_clk_max = 0;
reg vb_rot_d;
always @(posedge clk_ram) begin
    if (core.rotate.st == 5 || (core.rotate.st == 0 && !core.rotate.building)) begin
        if (core.rotate.miss_count > rot_miss_max) rot_miss_max = core.rotate.miss_count;
        if (core.rotate.line_clocks > rot_clk_max) rot_clk_max = core.rotate.line_clocks;
    end
    if (!core.bsprites.building && core.bsprites.line_clocks > bs_clk_max) bs_clk_max = core.bsprites.line_clocks;
end
always @(posedge clk_sys) begin
    if (vb && !vb_rot_d && frame != 0 && (frame % 20 == 0 || frame == dumpframe + 1))
        $display("SCANOUT f=%0d worst misses/line=%0d worst clocks/line=%0d late lines so far=%0d; 16B worst clocks/line=%0d late=%0d", frame, rot_miss_max, rot_clk_max, core.rotate.late_count, bs_clk_max, core.bsprites.late_count);
    if (vb && !vb_rot_d) begin rot_miss_max = 0; rot_clk_max = 0; bs_clk_max = 0; end
    vb_rot_d <= vb;
end

// ---- +dumpframe=N: what frame N was made from. The Y render is kicked at
// line 226 of frame N-1, erases the back buffer, walks the live list from
// about line 234 (after sub X's Scene Select list writes at 227) and the
// buffers swap at line 223, so frame N shows it: the Y list and the
// rotation buffer (clip and scan-out parameters) are dumped the moment
// that walk starts. The 16B copy is taken at line 226 of frame N itself
// and drives its lines, so the 16B list is dumped there; the palette when
// frame N's last visible line has been scanned, as MAME's frame-end draw
// sees it. tools/board_check.py renders the model from these and compares
// frame N.
integer dumpframe = -1;
initial begin if (!$value$plusargs("dumpframe=%d", dumpframe)) dumpframe = -1; end
task automatic dump_ram(input string name, input integer words, input integer which);
    integer fd, k;
    fd = $fopen(name, "wb");
    for (k = 0; k < words; k = k + 1) begin
        case (which)
            0: $fwrite(fd, "%c%c", core.yspriteram.mem[k][7:0], core.yspriteram.mem[k][15:8]);
            1: $fwrite(fd, "%c%c", core.rotateram.mem[{~core.rot_bank, k[9:0]}][7:0], core.rotateram.mem[{~core.rot_bank, k[9:0]}][15:8]);
            3: $fwrite(fd, "%c%c", core.bspriteram.mem[k][7:0], core.bspriteram.mem[k][15:8]);
            default: $fwrite(fd, "%c%c", core.palette.mem[k][7:0], core.palette.mem[k][15:8]);
        endcase
    end
    $fclose(fd);
endtask
reg rend_dump_d;
always @(posedge clk_sys) begin
    rend_dump_d <= core.sprites.rendering;
    if (dumpframe >= 1 && frame == dumpframe - 1 && core.sprites.rendering && !rend_dump_d) begin
        dump_ram("rtl_yspriteram.bin", 32768, 0);
        dump_ram("rtl_rotbuf.bin", 1024, 1);
        $display("dumped the Y sprite list and the rotation buffer at frame %0d line %0d, the render start", frame, core.vcnt);
    end
    if (dumpframe >= 0 && frame == dumpframe && core.line_start && core.vcnt == 9'd226) begin
        dump_ram("rtl_bspriteram.bin", 2048, 3);
        $display("dumped the 16B list at frame %0d line 226, its copy", frame);
    end
end

// ---- +watch_a=/+watch_b=<hex>: log every shared-RAM access to those word
// addresses (0C0000-based, low 16 bits): writes always, reads when the
// value differs from the last one logged. For chasing CPU handshakes.
integer watch_a = -1, watch_b = -1;
initial begin
    if (!$value$plusargs("watch_a=%h", watch_a)) watch_a = -1;
    if (!$value$plusargs("watch_b=%h", watch_b)) watch_b = -1;
end
reg        w_hit; reg [1:0] w_cpu; reg w_we; reg [1:0] w_be; reg [15:0] w_din, w_addr, w_last_a, w_last_b;
reg        w_seen_a, w_seen_b;
initial begin w_seen_a = 1'b0; w_seen_b = 1'b0; end
always @(posedge clk_sys) begin
    w_hit <= 1'b0;
    if (core.shr_pick_m || core.shr_pick_x || core.shr_pick_y) begin
        if ({16'd0, core.shr_addr, 1'b0} == watch_a || {16'd0, core.shr_addr, 1'b0} == watch_b) begin
            w_hit <= 1'b1; w_cpu <= core.shr_pick_m ? 2'd0 : core.shr_pick_x ? 2'd1 : 2'd2;
            w_we <= core.shr_we; w_be <= core.shr_be; w_din <= core.shr_din; w_addr <= {core.shr_addr, 1'b0};
        end
    end
    if (w_hit) begin
        if (w_we || (w_addr == watch_a[15:0] ? (!w_seen_a || core.shr_q != w_last_a) : (!w_seen_b || core.shr_q != w_last_b))) begin
            $display("SHR f=%0d line=%0d %s %s 0C%04x be=%b din=%04x q=%04x", frame, core.vcnt,
                     w_cpu == 2'd0 ? "main" : w_cpu == 2'd1 ? "subx" : "suby", w_we ? "wr" : "rd", w_addr, w_be, w_din, core.shr_q);
            if (w_addr == watch_a[15:0]) begin w_seen_a <= !w_we; w_last_a <= core.shr_q; end
            else begin w_seen_b <= !w_we; w_last_b <= core.shr_q; end
        end
    end
end

// ---- +watch_x=<hex>: log sub X's accesses to one word of its backup RAM
// (byte address 1FC000-1FFFFF), same shape as the shared-RAM watch
integer watch_x = -1;
initial begin if (!$value$plusargs("watch_x=%h", watch_x)) watch_x = -1; end
reg xb_hit, xb_we; reg [1:0] xb_be; reg [15:0] xb_din;
always @(posedge clk_sys) begin
    xb_hit <= 1'b0;
    if (watch_x >= 0 && core.x_valid && core.x_start && core.x_sel_bkup && {11'd0, core.xa[20:1], 1'b0} == watch_x) begin
        xb_hit <= 1'b1; xb_we <= core.x_wr; xb_be <= core.x_be; xb_din <= core.x_dout;
    end
    if (xb_hit) $display("XBK f=%0d line=%0d subx %s %06x be=%b din=%04x q=%04x", frame, core.vcnt, xb_we ? "wr" : "rd", watch_x[23:0], xb_be, xb_din, core.bkup_q);
end

// ---- +irqlog=F: sub X's program fetches with the IPL it sees, lines 222-225
// of frame F and F+5 (chasing a missed IRQ4)
integer irqlog = -1;
initial begin if (!$value$plusargs("irqlog=%d", irqlog)) irqlog = -1; end
always @(posedge clk_sys) begin
    if (irqlog >= 0 && (frame == irqlog || frame == irqlog + 5) && core.vcnt >= 9'd222 && core.vcnt <= 9'd225 && tx_start && tx_fc[1])
        $display("XF f=%0d line=%0d h=%0d pc=%06x ipl=%0d asn=%b", frame, core.vcnt, core.hcnt, {tx_addr, 1'b0}, core.ipl, core.subx_cpu.bus_as_n);
end

// ---- +hold=<hex mask> +hold_from=N: hold P1 buttons from frame N, in the
// core's layout (0 right 1 left 2 down 3 up 4 A 5 B ... 11 gas 12 brake 13 C)
integer hold_mask = 0, hold_from = -1;
initial begin
    if (!$value$plusargs("hold=%h", hold_mask)) hold_mask = 0;
    if (!$value$plusargs("hold_from=%d", hold_from)) hold_from = -1;
end
wire [15:0] hold_now = (hold_from >= 0 && frame >= hold_from) ? hold_mask[15:0] : 16'd0;

// ---- writes into ROM space: acknowledged and dropped by the core; logged
// (first 8) because a game doing this is worth knowing about
integer romwr_n = 0;
always @(posedge clk_sys) begin
    if (core.m_start && core.m_wr && core.m_sel_rom && romwr_n < 8) begin romwr_n = romwr_n + 1; $display("ROMWR f=%0d line=%0d main %06x", frame, core.vcnt, {core.ma, 1'b0}); end
    if (core.x_start && core.x_wr && core.x_sel_rom && romwr_n < 8) begin romwr_n = romwr_n + 1; $display("ROMWR f=%0d line=%0d subx %06x", frame, core.vcnt, {core.xa, 1'b0}); end
    if (core.y_start && core.y_wr && core.y_sel_rom && romwr_n < 8) begin romwr_n = romwr_n + 1; $display("ROMWR f=%0d line=%0d suby %06x", frame, core.vcnt, {core.ya, 1'b0}); end
end

// ---- +shifter: enable the gear indicator overlay (off for the gates: the
// MAME captures use the native view, which has no artwork)
reg shifter_sw; initial shifter_sw = $test$plusargs("shifter");

// ---- +test_from=N: hold the test switch (service mode) from frame N on
integer test_from = -1;
initial begin if (!$value$plusargs("test_from=%d", test_from)) test_from = -1; end
wire test_sw = (test_from >= 0) && (frame >= test_from);
// ---- +coin=N: press Coin 1 for four frames from frame N (matches tools/mame_coin.lua)
integer coin_frame = -1;
initial begin if (!$value$plusargs("coin=%d", coin_frame)) coin_frame = -1; end
wire coin1 = (coin_frame >= 0) && (frame >= coin_frame) && (frame < coin_frame + 4);
// ---- +start=N: press P1 Start for four frames from frame N
integer start_frame = -1;
initial begin if (!$value$plusargs("start=%d", start_frame)) start_frame = -1; end
// +start2..+start5=N: further four-frame Start presses
integer start2_frame = -1, start3_frame = -1, start4_frame = -1, start5_frame = -1;
initial begin
    if (!$value$plusargs("start2=%d", start2_frame)) start2_frame = -1;
    if (!$value$plusargs("start3=%d", start3_frame)) start3_frame = -1;
    if (!$value$plusargs("start4=%d", start4_frame)) start4_frame = -1;
    if (!$value$plusargs("start5=%d", start5_frame)) start5_frame = -1;
end
function automatic pressed(input integer at);
    pressed = (at >= 0) && (frame >= at) && (frame < at + 4);
endfunction
wire p1_start = pressed(start_frame) || pressed(start2_frame) || pressed(start3_frame) || pressed(start4_frame) || pressed(start5_frame);

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
        if (dumpframe >= 0 && frame == dumpframe) begin       // the last visible line of frame N just ended
            dump_ram("rtl_paletteram.bin", 8192, 2);
            $display("dumped the palette at the end of frame %0d", frame);
        end
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
