`timescale 1ns/1ps
// Standalone 315-5306 test: the DDRAM model's buffer 0 holds a framebuffer
// (fb.hex, 512 lines of 128 64-bit words), the rotation parameters come from
// rot.hex (12 words, 3F0-3FB), and the scan-out builds lines 0..223 one
// after another; each finished line is dumped from the line buffer as
// lines.txt (idx pri per pixel) with the misses and clocks it took.
module tb_rotate;
reg clk = 0; always #5 clk = ~clk;
reg reset = 1;

wire        DDRAM_BUSY, DDRAM_DOUT_READY, DDRAM_RD, DDRAM_WE;
wire  [7:0] DDRAM_BURSTCNT, DDRAM_BE;
wire [28:0] DDRAM_ADDR;
wire [63:0] DDRAM_DOUT, DDRAM_DIN;
ddram_model ddram (.clk(clk), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE));

wire rq_req, rq_ack; wire [1:0] rq_buf; wire [8:0] rq_y; wire [6:0] rq_xw; wire [63:0] rq_data;
wire [15:0] fbr_pix; wire fbe_ack, fbr_ack, fbw_busy;
yb_fb_if #(.FB_BASE(32'h3000_0000)) fb (
    .clk(clk), .rst(reset), .hires(1'b0),
    .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .wr_start(1'b0), .wr_buf(2'd0), .wr_x(10'd0), .wr_lanes(4'd0), .wr_y(9'd0),
    .wr_valid(1'b0), .wr_pix(16'd0), .wr_end(1'b0), .wr_dup(1'b0), .wr_dup_y(9'd0), .wr_shadow(1'b0), .wr_busy(fbw_busy),
    .er_req(1'b0), .er_buf(2'd0), .er_y(9'd0), .er_ack(fbe_ack),
    .rq_req(rq_req), .rq_buf(rq_buf), .rq_y(rq_y), .rq_xw(rq_xw), .rq_ack(rq_ack), .rq_data(rq_data),
    .rd_req(1'b0), .rd_buf(2'd0), .rd_y(9'd0), .rd_ack(fbr_ack),
    .rd_x(10'd0), .rd_pix(fbr_pix), .rd_pub_ok(1'b1));

reg [15:0] rotw [0:11];
reg [191:0] disp_rot;
reg line_start = 0; reg [8:0] vcnt = 9'd261;
wire [12:0] rd_idx; wire [7:0] rd_pri; wire [8:0] miss_count; wire [12:0] line_clocks; wire [15:0] late_count;
yb_rotate_5306 dut (
    .clk(clk), .reset(reset), .line_start(line_start), .vcnt(vcnt), .disp_buf(1'b0), .disp_rot(disp_rot),
    .rq_req(rq_req), .rq_buf(rq_buf), .rq_y(rq_y), .rq_xw(rq_xw), .rq_ack(rq_ack), .rq_data(rq_data),
    .rd_clk(clk), .rd_line_start(line_start), .rd_x(9'd0), .rd_idx(rd_idx), .rd_pri(rd_pri),
    .miss_count(miss_count), .line_clocks(line_clocks), .late_count(late_count));

integer fd, fs, x, y, k, cyc, worst_miss = 0, worst_clk = 0;
initial begin
    $readmemh("fb.hex", ddram.mem);
    $readmemh("rot.hex", rotw);
    for (k = 0; k < 12; k = k + 1) disp_rot[191 - k*16 -: 16] = rotw[k];
    repeat (8) @(posedge clk); reset = 0;
    repeat (4) @(posedge clk);
    fd = $fopen("lines.txt", "w"); fs = $fopen("stats.txt", "w");
    // line 261 starts line 0's build; line v starts line v+1's
    for (y = -1; y < 223; y = y + 1) begin
        // nonblocking stimulus: the DUT samples at the same edges the loop waits on
        vcnt <= (y < 0) ? 9'd261 : y[8:0];
        line_start <= 1; @(posedge clk); line_start <= 0;
        @(posedge clk);
        cyc = 0;
        while (dut.building) begin @(posedge clk); cyc = cyc + 1; if (cyc > 20000) begin $display("TIMEOUT line %0d", y + 1); $finish; end end
        repeat (2) @(posedge clk);
        // the line just built is in the fill bank
        for (x = 0; x < 320; x = x + 1) $fwrite(fd, "%0d %0d\n", dut.lb[{dut.fill_bank, x[8:0]}][20:8], dut.lb[{dut.fill_bank, x[8:0]}][7:0]);
        $fwrite(fs, "%0d %0d %0d\n", y + 1, dut.miss_count, dut.line_clocks);
        if (dut.miss_count > worst_miss) worst_miss = dut.miss_count;
        if (dut.line_clocks > worst_clk) worst_clk = dut.line_clocks;
    end
    $fclose(fd); $fclose(fs);
    $display("scan-out done: worst misses/line %0d, worst clocks/line %0d (budget 6400)", worst_miss, worst_clk);
    $finish;
end
endmodule
