`timescale 1ns/1ps
// Standalone 315-5305 test: render one sprite list (yspriteram.hex) with the
// rotation buffer (rotateram.hex) and the real sprite ROM (ysprite.hex, the
// SDRAM 16-bit word image) through yb_fb_if and the DDRAM model, then dump
// the render target (buffer 1 after reset) as fb.txt: 512 lines of 512 hex
// words.
module tb_ysprite;
reg clk = 0; always #5 clk = ~clk;
reg reset = 1;

// sprite RAM, rotation buffer: yb_dpram port B is one output register
reg [15:0] sram [0:32767];
wire [14:0] sram_addr; reg [15:0] sram_q;
always @(posedge clk) sram_q <= sram[sram_addr];
reg [15:0] rot [0:1023];
wire [9:0] rot_addr; reg [15:0] rot_q;
always @(posedge clk) rot_q <= rot[rot_addr];

// sprite ROM served through the p2 burst port (8 x 16-bit words per burst)
reg [15:0] rom [0:8388607];   // 16 MB slot / 2
wire        rom_req; wire [24:4] rom_addr; reg [127:0] rom_dout; reg rom_ack;
reg  [3:0] rom_lat; reg rom_pend; reg [24:4] rom_a; reg req_d;
localparam [24:4] YBASE = 21'h51000;   // SDR_YSPR_BASE >> 4
always @(posedge clk) begin
    req_d <= rom_req; rom_ack <= 0;
    if (rom_req && !req_d) begin rom_pend <= 1; rom_a <= rom_addr; rom_lat <= 4'd9; end
    else if (rom_pend) begin
        if (rom_lat != 0) rom_lat <= rom_lat - 1;
        else begin
            rom_dout <= {rom[{rom_a - YBASE, 3'd7}], rom[{rom_a - YBASE, 3'd6}], rom[{rom_a - YBASE, 3'd5}], rom[{rom_a - YBASE, 3'd4}],
                         rom[{rom_a - YBASE, 3'd3}], rom[{rom_a - YBASE, 3'd2}], rom[{rom_a - YBASE, 3'd1}], rom[{rom_a - YBASE, 3'd0}]};
            rom_ack <= 1; rom_pend <= 0;
        end
    end
end

wire        DDRAM_BUSY, DDRAM_DOUT_READY, DDRAM_RD, DDRAM_WE;
wire  [7:0] DDRAM_BURSTCNT, DDRAM_BE;
wire [28:0] DDRAM_ADDR;
wire [63:0] DDRAM_DOUT, DDRAM_DIN;
ddram_model ddram (.clk(clk), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE));

wire fbw_start, fbw_valid, fbw_end, fbw_busy, fbe_ack, fbr_ack, fbw_dup, fbe_req, fbr_req;
wire [8:0] fbw_dup_y, fbw_y, fbe_y, fbr_y; wire [1:0] fbw_buf, fbe_buf, fbr_buf;
wire [9:0] fbw_x; wire [3:0] fbw_lanes; wire [15:0] fbw_pix, fbr_pix;
yb_fb_if #(.FB_BASE(32'h3000_0000)) fb (
    .clk(clk), .rst(reset), .hires(1'b0),
    .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .wr_start(fbw_start), .wr_buf(fbw_buf), .wr_x(fbw_x), .wr_lanes(fbw_lanes), .wr_y(fbw_y),
    .wr_valid(fbw_valid), .wr_pix(fbw_pix), .wr_end(fbw_end), .wr_dup(fbw_dup), .wr_dup_y(fbw_dup_y), .wr_shadow(1'b0), .wr_busy(fbw_busy),
    .er_req(fbe_req), .er_buf(fbe_buf), .er_y(fbe_y), .er_ack(fbe_ack),
    .rd_req(fbr_req), .rd_buf(fbr_buf), .rd_y(fbr_y), .rd_ack(fbr_ack),
    .rd_x(10'd0), .rd_pix(fbr_pix), .rd_pub_ok(1'b1));

reg start_req = 0;
wire disp_buf, rendering; wire [8:0] disp_ox, disp_oy;
yb_ysprite_5305 dut (
    .clk(clk), .reset(reset), .num_banks(8'd8),
    .start_req(start_req), .vbl_start(1'b0), .line_start(1'b0), .vcnt(9'd0),
    .sram_addr(sram_addr), .sram_q(sram_q), .rot_addr(rot_addr), .rot_q(rot_q),
    .rom_req(rom_req), .rom_addr(rom_addr), .rom_dout(rom_dout), .rom_ack(rom_ack),
    .fb_wr_start(fbw_start), .fb_wr_buf(fbw_buf), .fb_wr_x(fbw_x), .fb_wr_lanes(fbw_lanes), .fb_wr_y(fbw_y),
    .fb_wr_valid(fbw_valid), .fb_wr_pix(fbw_pix), .fb_wr_end(fbw_end), .fb_wr_dup(fbw_dup), .fb_wr_dup_y(fbw_dup_y), .fb_wr_busy(fbw_busy),
    .fb_er_req(fbe_req), .fb_er_buf(fbe_buf), .fb_er_y(fbe_y), .fb_er_ack(fbe_ack),
    .fb_rd_req(fbr_req), .fb_rd_buf(fbr_buf), .fb_rd_y(fbr_y), .fb_rd_ack(fbr_ack),
    .disp_buf(disp_buf), .disp_ox(disp_ox), .disp_oy(disp_oy), .rendering(rendering));

integer fd, x, y, cyc, nspr = 0, npix = 0;
reg started = 0;
initial begin
    $readmemh("yspriteram.hex", sram);
    $readmemh("rotateram.hex", rot);
    $readmemh("ysprite.hex", rom);
    repeat (8) @(posedge clk); reset = 0;
    // the renderer erases the back buffer itself (er_need after reset)
    @(posedge clk);
    start_req = 1; @(posedge clk); start_req = 0;
    cyc = 0;
    forever begin
        @(posedge clk); cyc = cyc + 1;
        if (dut.rs == 10) nspr = nspr + 1;          // R_DECODE
        if (fbw_valid) npix = npix + 1;
        if (rendering) started = 1;
        if (started && !rendering && !fbw_busy && dut.rs == 0) begin
            fd = $fopen("fb.txt", "w");
            for (y = 0; y < 512; y = y + 1)
                for (x = 0; x < 512; x = x + 4) begin
                    reg [63:0] q;
                    q = ddram.mem[(32'h3008_0000 >> 3) - (32'h3000_0000 >> 3) + y*128 + x/4];
                    $fwrite(fd, "%04x %04x %04x %04x\n", q[15:0], q[31:16], q[47:32], q[63:48]);
                end
            $fclose(fd);
            $display("render done in %0d cycles: %0d entries, %0d pixel writes, ox=%0d oy=%0d", cyc, nspr, npix, dut.ox_r, dut.oy_r);
            $finish;
        end
        if (cyc > 6000000) begin
            $display("TIMEOUT rs=%0d idx=%0d rows_left=%0d y=%0d x=%0d busy=%0d", dut.rs, dut.idx, dut.rows_left, dut.y, dut.x, fbw_busy);
            $finish;
        end
    end
end
endmodule
