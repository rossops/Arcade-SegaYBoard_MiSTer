//============================================================================
//  Sega 315-5196 System 16B sprite generator as the Y Board uses it: line
//  based, one screen line built ahead of the display into a double-banked
//  line buffer. Algorithm: MAME sega16sp.cpp sega_sys16b_sprite_device::draw
//  with the Y Board's origin (x 184 = screen 0), no screen flip, identity
//  bank table:
//    w0: bottom - 1 (15:8), top - 1 (7:0)        w1: ----iiii -xxxxxxxx x (9 bits), iiii Y Board priority
//    w2: e------- end, -h------ hide, -------f flip, pitch (signed, 7:0)
//    w3: ROM offset (16-bit words)               w4: ----bbbb bank, pp------ priority, --cccccc colour
//    w5: ------vv vvvhhhhh vertical / horizontal zoom (0 = 1:1, 0x10 = half)
//    w7: scratch (the row address)
//  The chip keeps its per-sprite state in the list itself: word 5 bits 15:10
//  accumulate the vertical zoom, word 7 holds the row address. This module
//  takes a copy of the 4 KB list at `snap` (one clk per word) and works on
//  the copy, so the CPU's RAM is never written and the picture is the list
//  as it was at the snapshot (MAME renders at screen update). At each line
//  it walks the 256 entries: an entry whose rows cover the line has its
//  state stepped (addr += pitch, acc += vzoom << 10, an extra pitch on the
//  carry) and its row drawn: xacc starts at 4 * hzoom and a pen is placed
//  when (xacc & 0x3F) + hzoom < 0x40; pens 0 and F are transparent, the row
//  ends when the last pen of a word is F, and at most 511 pens are placed.
//  Line buffer pixel: {ybd priority[3:0], priority[1:0], colour[5:0], pen};
//  0xFFFF = empty. Sprite ROM: SDRAM port p4, 128-bit bursts = 8 words.
//  verif/models/bsprite5196.py is the golden model.
//============================================================================
import yb_pkg::*;

module yb_bsprite_5196 (
    input             clk,            // clk_ram
    input             reset,
    input       [7:0] num_banks,      // 128 KB banks in the ROM set (gforce2: 4)

    input             snap,           // one-clk pulse: copy the list
    input             line_start,     // one-clk pulse (clk_ram) at hcnt == 0
    input       [8:0] vcnt,           // line being displayed

    // sprite RAM read port (2048 words), 1-clk registered output
    output reg [10:0] sram_addr,
    input      [15:0] sram_q,

    // sprite ROM (SDRAM p4 contract)
    output reg        rom_req,
    output reg [24:4] rom_addr,
    input     [127:0] rom_dout,
    input             rom_ack,

    // display side (rd_clk = clk_sys), as yb_rotate_5306
    input             rd_clk,
    input             rd_line_start,
    input       [8:0] rd_x,
    output     [15:0] rd_pix,

    // bench statistics
    output reg [12:0] line_clocks,
    output reg [15:0] late_count
);

// ---------------------------------------------------------------- list copy
reg [15:0] cp [0:2047];
reg [10:0] cp_addr;
reg [15:0] cp_q;
reg        cp_we;
reg [10:0] cp_waddr;
reg [15:0] cp_wdata;
always @(posedge clk) begin
    if (cp_we) cp[cp_waddr] <= cp_wdata;
    cp_q <= cp[cp_addr];
end

// ---------------------------------------------------------------- line buffer
reg [15:0] lb [0:1023];
reg        fill_bank, disp_bank;
reg [15:0] lb_q;
reg        lb_we;
reg  [8:0] lb_waddr;
reg [15:0] lb_wdata;
always @(posedge clk) if (lb_we) lb[{fill_bank, lb_waddr}] <= lb_wdata;
always @(posedge rd_clk) begin
    if (reset) disp_bank <= 1'b0;
    else if (rd_line_start) disp_bank <= ~disp_bank;
    lb_q <= lb[{disp_bank, rd_x}];
end
assign rd_pix = lb_q;

// ---------------------------------------------------------------- walker
typedef enum logic [3:0] {
    S_IDLE, S_SNAP, S_CLEAR, S_HDR, S_HDRW, S_WORDS, S_ROW, S_BANK, S_WB, S_ROMREQ, S_ROMWAIT, S_PIX, S_NEXT
} st_t;
st_t st;
reg        building, snapping;
reg [11:0] snap_cnt;
reg  [8:0] clr_x;
reg  [8:0] y;                // screen line being built
reg  [7:0] ent;              // entry 0..255
reg  [3:0] wcnt;
reg [15:0] w [0:7];
reg [12:0] cnt_clk;
// decoded entry
reg  [7:0] top, bottom;
reg  [8:0] xpos;
reg        flip;
reg signed [7:0] pitch;
reg  [3:0] bank;
reg [15:0] colpri;
reg  [4:0] vzoom, hzoom;
reg [15:0] addr;             // row address (word 7 state)
reg [15:0] acc;              // vertical zoom accumulator (word 5 state)
// row
reg  [9:0] x;
reg  [6:0] xacc;
reg  [1:0] nib;
reg [15:0] pixels;
reg        last_f;
reg [15:0] rowaddr;
wire [8:0] xd = xpos - x[8:0];                       // (xpos - x) & 0x1ff
wire       row_more = (xd != 9'd1);
wire [9:0] sxw = x - 10'd184;
wire       x_on = (x >= 10'd184) && (x <= 10'd503);
wire [3:0] pen = pixels[3:0];
// ROM burst: 8 words; keep it and pick the word
reg [127:0] burst;
reg  [12:0] burst_tag;
reg   [3:0] burst_bank;
reg         burst_valid;
wire        burst_hit = burst_valid && burst_tag == rowaddr[15:3] && burst_bank == bank;
wire [15:0] word_sel = burst[rowaddr[2:0]*16 +: 16];
function automatic [15:0] rev4(input [15:0] p);
    rev4 = {p[3:0], p[7:4], p[11:8], p[15:12]};
endfunction

always @(posedge clk) begin
    lb_we <= 1'b0;
    cp_we <= 1'b0;
    rom_req <= 1'b0;
    if (reset) begin
        st <= S_IDLE; building <= 1'b0; snapping <= 1'b0; fill_bank <= 1'b1;
        burst_valid <= 1'b0; line_clocks <= 13'd0; late_count <= 16'd0; cnt_clk <= 13'd0;
        snap_cnt <= 12'd0; y <= 9'd0; ent <= 8'd0; wcnt <= 4'd0;
    end
    else begin
        if (building) cnt_clk <= cnt_clk + 13'd1;

        // copy the list: address k out at clock k, data back two clocks later
        if (snap) begin snapping <= 1'b1; snap_cnt <= 12'd0; end
        if (snapping) begin
            sram_addr <= snap_cnt[10:0];
            if (snap_cnt >= 12'd2) begin cp_we <= 1'b1; cp_waddr <= snap_cnt[10:0] - 11'd2; cp_wdata <= sram_q; end
            snap_cnt <= snap_cnt + 12'd1;
            if (snap_cnt == 12'd2049) snapping <= 1'b0;
        end

        // line start: the line just built goes on display, build the next
        if (line_start && (vcnt < 9'd223 || vcnt == 9'd261)) begin
            if (building) late_count <= late_count + 16'd1;
            fill_bank <= ~fill_bank;
            y <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
            building <= 1'b1; cnt_clk <= 13'd0;
            clr_x <= 9'd0; burst_valid <= 1'b0;
            st <= S_CLEAR;
        end
        else case (st)
        S_IDLE: ;
        // empty the fill bank (0xFFFF)
        S_CLEAR: begin
            lb_we <= 1'b1; lb_waddr <= clr_x; lb_wdata <= 16'hFFFF;
            if (clr_x == 9'd319) begin ent <= 8'd0; cp_addr <= 11'd0; st <= S_HDR; end
            else clr_x <= clr_x + 9'd1;
        end
        // words 0 and 2 first: does the entry cover this line at all?
        S_HDR: begin cp_addr <= {ent, 3'd2}; st <= S_HDRW; end
        S_HDRW: begin
            // cp_q = word 0 now, word 2 next clock
            w[0] <= cp_q;
            cp_addr <= {ent, 3'd1}; wcnt <= 4'd0;
            st <= S_WORDS;
        end
        // word 2 arrives first, then 1, 3, 4, 5, 7
        S_WORDS: begin
            case (wcnt)
                4'd0: begin w[2] <= cp_q; cp_addr <= {ent, 3'd3}; end
                4'd1: begin w[1] <= cp_q; cp_addr <= {ent, 3'd4}; end
                4'd2: begin w[3] <= cp_q; cp_addr <= {ent, 3'd5}; end
                4'd3: begin w[4] <= cp_q; cp_addr <= {ent, 3'd7}; end
                4'd4: begin w[5] <= cp_q; end
                default: begin w[7] <= cp_q; end
            endcase
            wcnt <= wcnt + 4'd1;
            if (wcnt == 4'd0 && cp_q[15]) begin      // end of list
                building <= 1'b0; line_clocks <= cnt_clk; st <= S_IDLE;
            end
            else if (wcnt == 4'd0 && (cp_q[14] || w[0][7:0] >= w[0][15:8] || y[7:0] < w[0][7:0] || y[7:0] >= w[0][15:8] || y[8])) begin
                st <= S_NEXT;                         // hidden, empty, or not on this line
            end
            else if (wcnt == 4'd5) st <= S_ROW;
        end
        // step the row state (init at the top row) and decode
        S_ROW: begin
            logic [15:0] a0, ac;
            a0 = (y[7:0] == w[0][7:0]) ? w[3] : w[7];
            ac = (y[7:0] == w[0][7:0]) ? (w[5] & 16'h03FF) : w[5];
            ac = ac + {w[5][9:5], 10'd0};
            addr <= a0 + {{8{w[2][7]}}, w[2][7:0]} + (ac[15] ? {{8{w[2][7]}}, w[2][7:0]} : 16'd0);
            acc  <= ac & 16'h7FFF;
            top <= w[0][7:0]; bottom <= w[0][15:8];
            xpos <= w[1][8:0]; flip <= w[2][8]; pitch <= w[2][7:0];
            bank <= w[4][11:8];
            colpri <= {w[1][12:9], w[4][7:0], 4'd0};
            vzoom <= w[5][9:5]; hzoom <= w[5][4:0];
            st <= S_BANK;
        end
        S_BANK: begin
            if (num_banks != 8'd0 && {4'd0, bank} >= num_banks) bank <= bank - num_banks[3:0];
            else st <= S_WB;
        end
        // write the state back (word 5 then word 7) and open the row
        S_WB: begin
            cp_we <= 1'b1; cp_waddr <= {ent, 3'd5}; cp_wdata <= acc;
            wcnt <= 4'd0;
            rowaddr <= addr;
            x <= {1'b0, xpos}; xacc <= {hzoom, 2'b00}; nib <= 2'd0;
            st <= S_ROMREQ;
        end
        S_ROMREQ: begin
            if (wcnt == 4'd0) begin cp_we <= 1'b1; cp_waddr <= {ent, 3'd7}; cp_wdata <= addr; wcnt <= 4'd1; end
            if (!row_more) st <= S_NEXT;
            else if (burst_hit) begin
                pixels <= flip ? word_sel : rev4(word_sel);
                last_f <= flip ? (word_sel[15:12] == 4'hF) : (word_sel[3:0] == 4'hF);
                rowaddr <= flip ? rowaddr - 16'd1 : rowaddr + 16'd1;
                nib <= 2'd0;
                st <= S_PIX;
            end
            else begin
                rom_req  <= 1'b1;
                rom_addr <= SDR_BSPR_BASE[24:4] + {4'd0, bank, rowaddr[15:3]};
                st <= S_ROMWAIT;
            end
        end
        S_ROMWAIT: begin
            if (rom_ack) begin
                burst <= rom_dout; burst_tag <= rowaddr[15:3]; burst_bank <= bank; burst_valid <= 1'b1;
                st <= S_ROMREQ;
            end
        end
        // one pen per clock
        S_PIX: begin
            logic [6:0] xa;
            xa = {1'b0, xacc[5:0]} + {2'b00, hzoom};
            xacc <= xa;
            if (xa < 7'd64) begin
                lb_we <= x_on && (pen != 4'd0) && (pen != 4'hF);
                lb_waddr <= sxw[8:0]; lb_wdata <= colpri | {12'd0, pen};
                x <= x + 10'd1;
            end
            pixels <= pixels >> 4;
            if (nib == 2'd3) begin if (last_f) st <= S_NEXT; else st <= S_ROMREQ; end
            nib <= nib + 2'd1;
        end
        S_NEXT: begin
            if (ent == 8'd255) begin building <= 1'b0; line_clocks <= cnt_clk; st <= S_IDLE; end
            else begin ent <= ent + 8'd1; cp_addr <= {ent + 8'd1, 3'd0}; st <= S_HDR; end   // word 0 of the next entry
        end
        default: st <= S_IDLE;
        endcase
    end
end
endmodule
