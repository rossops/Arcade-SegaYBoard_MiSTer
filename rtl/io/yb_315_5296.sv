//============================================================================
//  Sega 315-5296 I/O chip (low byte of each word at 100000-10007F)
//  64 byte registers: 0-7 ports A-H, 8-B read 'S','E','G','A', C/E the CNT
//  register, D/F the direction register (bit n = port n is an output).
//  Reading an output port returns its latch, an input port the pin; a write
//  always lands in the latch and drives the pin only while the port is an
//  output (MAME refreshes an input port's callback with 0). Everything else
//  reads FF. Registers 20-3F assert /FMCS, the MSM6253's chip select here.
//  CNT0-2 and CKOT are not modelled (MAME leaves them too). Reference MAME
//  315_5296.cpp; verif/models/io5296.py is the golden model.
//============================================================================
module yb_315_5296 (
    input             clk,
    input             reset,
    input             cs,           // one clk pulse per bus access
    input             we,
    input       [5:0] addr,         // byte register (address bits 6:1)
    input       [7:0] din,
    output reg  [7:0] dout,
    output            fmcs,         // combinational: cs window 20-3F

    input       [7:0] in_a, in_b, in_c, in_d, in_e, in_f, in_g, in_h,
    output      [7:0] out_a, out_b, out_c, out_d, out_e, out_f, out_g, out_h
);

reg [7:0] latch [0:7];
reg [7:0] dir;
reg [7:0] cnt;
integer i;

assign fmcs = addr[5];

assign out_a = dir[0] ? latch[0] : 8'd0;
assign out_b = dir[1] ? latch[1] : 8'd0;
assign out_c = dir[2] ? latch[2] : 8'd0;
assign out_d = dir[3] ? latch[3] : 8'd0;
assign out_e = dir[4] ? latch[4] : 8'd0;
assign out_f = dir[5] ? latch[5] : 8'd0;
assign out_g = dir[6] ? latch[6] : 8'd0;
assign out_h = dir[7] ? latch[7] : 8'd0;

always @(posedge clk) begin
    if (reset) begin
        for (i = 0; i < 8; i = i + 1) latch[i] <= 8'd0;
        dir <= 8'd0;
        cnt <= 8'd0;
    end
    else if (cs && we) begin
        if (!addr[5] && !addr[4] && !addr[3]) latch[addr[2:0]] <= din;   // 00-07
        else if (addr == 6'h0E) cnt <= din;
        else if (addr == 6'h0F) dir <= din;
    end
end

wire [7:0] pin [0:7];
assign pin[0] = in_a; assign pin[1] = in_b; assign pin[2] = in_c; assign pin[3] = in_d;
assign pin[4] = in_e; assign pin[5] = in_f; assign pin[6] = in_g; assign pin[7] = in_h;

always @* begin
    if (!addr[5] && !addr[4] && !addr[3]) dout = dir[addr[2:0]] ? latch[addr[2:0]] : pin[addr[2:0]];
    else begin
        case (addr)
            6'h08: dout = 8'h53;   // 'S'
            6'h09: dout = 8'h45;   // 'E'
            6'h0A: dout = 8'h47;   // 'G'
            6'h0B: dout = 8'h41;   // 'A'
            6'h0C, 6'h0E: dout = cnt;
            6'h0D, 6'h0F: dout = dir;
            default: dout = 8'hFF;
        endcase
    end
end
endmodule
