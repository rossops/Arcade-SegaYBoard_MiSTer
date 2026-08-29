//============================================================================
//  OKI MSM6253 4-channel 8-bit ADC behind the 315-5296's /FMCS window
//  (100040-100047, low byte). A write to register n (address bits 2:1)
//  loads the shift register with channel n; each read returns the MSB on
//  D7 and shifts left with zero fill (the games read eight times). Channel
//  3 comes through the 74HC4052 selected by port E bits 1:0, so MAME's
//  seven analog ports are ch0-2 and mux0-3; the descriptor's reverse mask
//  is per MAME channel like PORT_REVERSE (0x100 - value on a 1..FF range). Conversion is instant, as in
//  MAME (the real chip's CKOT-clocked conversion time is open question 8).
//  Reference MAME msm6253.cpp; verif/models/msm6253.py is the golden model.
//============================================================================
module yb_msm6253 (
    input             clk,
    input             reset,
    input             cs,           // one clk pulse per bus access
    input             we,
    input       [1:0] addr,         // channel (address bits 2:1)
    output            d7,           // the bit shifted out by the read in progress

    input       [1:0] mux_sel,      // port E bits 1:0
    input       [6:0] adc_reverse,  // descriptor bit n: MAME channel n reads 255 - value
    input       [7:0] ch0, ch1, ch2,
    input       [7:0] mux0, mux1, mux2, mux3
);

reg [7:0] shift;

wire [7:0] mux_v  = (mux_sel == 2'd0) ? mux0 : (mux_sel == 2'd1) ? mux1 : (mux_sel == 2'd2) ? mux2 : mux3;
wire [2:0] mame_ch = (addr == 2'd3) ? (3'd3 + {1'b0, mux_sel}) : {1'b0, addr};
wire [7:0] raw    = (addr == 2'd0) ? ch0 : (addr == 2'd1) ? ch1 : (addr == 2'd2) ? ch2 : mux_v;
// PORT_REVERSE on MAME's 0x01..0xFF ranges is (max + min) - value = 0x100 - value,
// so a centred stick stays 0x80; the core's axes reach 0, which maps to 0xFF
wire [7:0] rev    = (raw == 8'd0) ? 8'hFF : (8'd0 - raw);
wire [7:0] sample = adc_reverse[mame_ch] ? rev : raw;

// The bus strobe is one clock at the start of the cycle and the 68000 latches
// the data several clocks later, after DTACK, so the bit a read returns is
// latched on the strobe before the register shifts. Returning shift[7]
// directly handed the CPU the next bit: it assembled (value << 1) and read a
// centred stick as 0.
reg d7_q;
assign d7 = d7_q;

always @(posedge clk) begin
    if (reset) begin shift <= 8'd0; d7_q <= 1'b0; end
    else if (cs) begin
        if (we) shift <= sample;
        else begin d7_q <= shift[7]; shift <= {shift[6:0], 1'b0}; end
    end
end
endmodule
