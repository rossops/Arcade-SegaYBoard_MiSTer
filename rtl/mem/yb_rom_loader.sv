//============================================================================
//  Sega Y Board — ioctl ROM loader
//  Index-0 stream (see yb_pkg OFF_*): [64-byte descriptor][main][subx][suby]
//  [z80][pcm][bsprite][ysprite], every region padded to its slot except the
//  last, and the slots laid out in SDRAM at the same offsets, so a stream
//  byte lands at SDRAM address (stream address - OFF_MAIN). Words arrive
//  little-endian (WIDE=1) and are written straight to SDRAM; tools/pack_roms.py
//  builds the stream so that each 16-bit SDRAM word already holds the byte
//  order the consumer expects.
//  Index 3 = backup RAM (NVRAM) upload/download, handled in yb_core.
//  rom_loaded releases the game reset only after the last SDRAM write of an
//  index-0 transfer has been acknowledged.
//============================================================================
import yb_pkg::*;

module yb_rom_loader (
    input             clk,
    input             rst,
    input             mem_ready,

    input             ioctl_download,
    input       [7:0] ioctl_index,
    input             ioctl_wr,
    input      [26:0] ioctl_addr,
    input      [15:0] ioctl_dout,
    output            ioctl_wait,

    output board_desc_t board_desc,

    output reg        sdr_wr_req,
    output reg [24:1] sdr_wr_addr,
    output reg [15:0] sdr_wr_din,
    output reg  [1:0] sdr_wr_be,
    input             sdr_wr_ack,

    output reg        rom_loaded
);

reg [7:0] desc_bytes [0:7];
reg       busy;
reg       index0_seen;
integer   i;

assign ioctl_wait = busy | ~mem_ready;

board_desc_t desc_r;
assign board_desc = desc_r;

always @(posedge clk) begin
    if (rst) begin
        sdr_wr_req <= 1'b0; sdr_wr_addr <= '0; sdr_wr_din <= '0; sdr_wr_be <= '0;
        rom_loaded <= 1'b0; busy <= 1'b0; index0_seen <= 1'b0;
        desc_r <= '0;
        for (i = 0; i < 8; i = i + 1) desc_bytes[i] <= 8'd0;
    end
    else begin
        if (sdr_wr_ack) begin
            sdr_wr_req <= 1'b0;
            busy       <= 1'b0;
        end

        if (mem_ready && ioctl_download && ioctl_wr && !busy && ioctl_index == 8'd0) begin
            if (ioctl_addr < OFF_MAIN) begin
                if (ioctl_addr[26:3] == 0) begin
                    desc_bytes[ioctl_addr[2:0]]        <= ioctl_dout[7:0];
                    desc_bytes[ioctl_addr[2:0] + 1'b1] <= ioctl_dout[15:8];
                end
                if (ioctl_addr == OFF_MAIN - 27'd2) begin
                    desc_r.game_id      <= desc_bytes[0];
                    desc_r.deluxe       <= desc_bytes[1][0];
                    desc_r.link         <= desc_bytes[1][1];
                    desc_r.r360         <= desc_bytes[1][2];
                    desc_r.yspr_banks   <= desc_bytes[2];
                    desc_r.bspr_banks   <= desc_bytes[3];
                    desc_r.adc_reverse  <= desc_bytes[4];
                    desc_r.pcm_bankmask <= desc_bytes[5];
                    desc_r.ana_mode     <= desc_bytes[6][2:0];
                    desc_r.irq2_line    <= desc_bytes[7];
                end
            end
            else if (ioctl_addr < OFF_END) begin
                logic [26:0] ma;
                ma = ioctl_addr - OFF_MAIN;
                sdr_wr_req  <= 1'b1;
                busy        <= 1'b1;
                sdr_wr_addr <= ma[24:1];
                sdr_wr_din  <= ioctl_dout;
                sdr_wr_be   <= 2'b11;
            end
        end

        if (mem_ready && ioctl_download && ioctl_wr && ioctl_index == 8'd0 && ioctl_addr == 0) begin
            rom_loaded  <= 1'b0;
            index0_seen <= 1'b1;
        end
        if (mem_ready && !ioctl_download && index0_seen && !busy && !sdr_wr_req) begin
            rom_loaded  <= 1'b1;
            index0_seen <= 1'b0;
        end
    end
end
endmodule
