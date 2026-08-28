`timescale 1ns/1ps
// Standalone 315-5196 test: the sprite RAM (bspriteram.hex, 2048 words) is
// snapshotted, then lines 0..223 are built one after another with the real
// sprite ROM (bsprite.hex, SDRAM 16-bit word image) through the p4 burst
// port; each finished line is dumped from the line buffer as lines.txt.
module tb_bsprite;
reg clk = 0; always #5 clk = ~clk;
reg reset = 1;

reg [15:0] sram [0:2047];
wire [10:0] sram_addr; reg [15:0] sram_q;
always @(posedge clk) sram_q <= sram[sram_addr];

reg [15:0] rom [0:1048575];   // 2 MB slot / 2
wire        rom_req; wire [24:4] rom_addr; reg [127:0] rom_dout; reg rom_ack;
reg  [3:0] rom_lat; reg rom_pend; reg [24:4] rom_a; reg req_d;
localparam [24:4] BBASE = 21'h31000;   // SDR_BSPR_BASE >> 4
always @(posedge clk) begin
    req_d <= rom_req; rom_ack <= 0;
    if (rom_req && !req_d) begin rom_pend <= 1; rom_a <= rom_addr; rom_lat <= 4'd9; end
    else if (rom_pend) begin
        if (rom_lat != 0) rom_lat <= rom_lat - 1;
        else begin
            rom_dout <= {rom[{rom_a - BBASE, 3'd7}], rom[{rom_a - BBASE, 3'd6}], rom[{rom_a - BBASE, 3'd5}], rom[{rom_a - BBASE, 3'd4}],
                         rom[{rom_a - BBASE, 3'd3}], rom[{rom_a - BBASE, 3'd2}], rom[{rom_a - BBASE, 3'd1}], rom[{rom_a - BBASE, 3'd0}]};
            rom_ack <= 1; rom_pend <= 0;
        end
    end
end

reg snap = 0, line_start = 0; reg [8:0] vcnt = 9'd261;
wire [15:0] rd_pix; wire [12:0] line_clocks; wire [15:0] late_count;
yb_bsprite_5196 dut (
    .clk(clk), .reset(reset), .num_banks(8'd4),
    .snap(snap), .line_start(line_start), .vcnt(vcnt),
    .sram_addr(sram_addr), .sram_q(sram_q),
    .rom_req(rom_req), .rom_addr(rom_addr), .rom_dout(rom_dout), .rom_ack(rom_ack),
    .rd_clk(clk), .rd_line_start(line_start), .rd_x(9'd0), .rd_pix(rd_pix),
    .line_clocks(line_clocks), .late_count(late_count));

integer fd, fs, x, y, cyc, worst_clk = 0;
initial begin
    $readmemh("bspriteram.hex", sram);
    $readmemh("bsprite.hex", rom);
    repeat (8) @(posedge clk); reset = 0;
    repeat (4) @(posedge clk);
    snap <= 1; @(posedge clk); snap <= 0;
    @(posedge clk);   // let the DUT's nonblocking updates land before polling
    while (dut.snapping) @(posedge clk);
    repeat (4) @(posedge clk);
    fd = $fopen("lines.txt", "w"); fs = $fopen("stats.txt", "w");
    for (y = -1; y < 223; y = y + 1) begin
        vcnt <= (y < 0) ? 9'd261 : y[8:0];
        line_start <= 1; @(posedge clk); line_start <= 0;
        @(posedge clk);
        cyc = 0;
        while (dut.building) begin @(posedge clk); cyc = cyc + 1; if (cyc > 60000) begin $display("TIMEOUT line %0d st=%0d ent=%0d", y + 1, dut.st, dut.ent); $finish; end end
        repeat (2) @(posedge clk);
        for (x = 0; x < 320; x = x + 1) $fwrite(fd, "%04x\n", dut.lb[{dut.fill_bank, x[8:0]}]);
        $fwrite(fs, "%0d %0d\n", y + 1, dut.line_clocks);
        if (dut.line_clocks > worst_clk) worst_clk = dut.line_clocks;
    end
    $fclose(fd); $fclose(fs);
    $display("16B done: worst clocks/line %0d (budget 6400)", worst_clk);
    $finish;
end
endmodule
