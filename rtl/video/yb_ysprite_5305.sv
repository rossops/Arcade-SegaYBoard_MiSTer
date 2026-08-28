//============================================================================
//  Sega 315-5305 Y Board sprite generator, rendering the linked sprite list
//  into one of two 512x512x16 framebuffers held in DDR3 through yb_fb_if,
//  latching the rotation parameters that travel with each buffer to the
//  315-5306 scan-out (yb_rotate_5306).
//  Algorithm: MAME sega16sp.cpp sega_yboard_sprite_device::draw:
//    w0: e------- -------- end of list; -h-h---- hide; -----iii iiiiiiii
//        indirection table address (/16 words) in sprite RAM
//    w1: bbbb---- -------- bank 7:4 (only bit 4 used); ----xxxx xxxxxxxx x
//    w2: bbbb---- -------- bank 3:0; ----yyyy yyyyyyyy y (0x600 = fb 0)
//    w3: ROM offset within the bank (64-bit words)
//    w4: height
//    w5: -y------ top-to-bottom, --f----- flip (inverted), ---x---- left-to-
//        right, -----zzz zzzzzzzz zoom (0x200 = 1:1)
//    w6: -ccc---- colour, ----rrrr priority, -------- pppppppp pitch
//    w7: ----nnnn nnnnnnnn next entry (a visited entry ends the walk)
//  Framebuffer pixel: {colour[2:0], priority[3:0], indirected pen[8:0]};
//  0xFFFF = empty. Rows are clipped to the per-line-pair extents in the
//  rotation RAM buffer (word 2n = min x, 2n+1 = max x, bit 15/14 = above/
//  below the screen); everything is in the 0x600-based coordinate space.
//
//  Sequence: every frame the renderer erases the back buffer, walks the list
//  from sprite RAM as it is, and the buffers swap at the next vblank (MAME
//  renders the list at screen update). The rotation parameters (words
//  3F0-3FB of the rotation buffer) are latched with the render and travel
//  with the buffer to the display.
//
//  Sprite ROM: SDRAM port p2, 128-bit bursts = two consecutive 64-bit words,
//  each stored as four 16-bit words with the first pen in the top nibble of
//  the first word (tools/pack_roms.py x64).
//============================================================================
import yb_pkg::*;

module yb_ysprite_5305 (
    input             clk,            // clk_ram (100 MHz)
    input             reset,
    input       [7:0] num_banks,      // 512 KB banks in the ROM set (gforce2: 8)

    // timing (clk_ram domain pulses)
    input             start_req,      // one-clk pulse: render the list now
    input             vbl_start,      // one-clk pulse at start of line 223
    input             line_start,     // one-clk pulse at hcnt == 0
    input       [8:0] vcnt,

    // sprite RAM read port (64 KB, sub X's), 1-clk registered output
    output reg [14:0] sram_addr,
    input      [15:0] sram_q,
    // rotation RAM buffer read port (the bank the CPU is not writing), 1-clk
    output reg  [9:0] rot_addr,
    input      [15:0] rot_q,

    // sprite ROM (SDRAM p2 contract: one burst per rising edge of rom_req)
    output reg        rom_req,
    output reg [24:4] rom_addr,
    input     [127:0] rom_dout,
    input             rom_ack,

    // framebuffer (yb_fb_if)
    output reg        fb_wr_start,
    output reg  [1:0] fb_wr_buf,
    output reg  [9:0] fb_wr_x,
    output reg  [3:0] fb_wr_lanes,
    output reg  [8:0] fb_wr_y,
    output reg        fb_wr_valid,
    output reg [15:0] fb_wr_pix,
    output reg        fb_wr_end,
    output reg        fb_wr_dup,
    output reg  [8:0] fb_wr_dup_y,
    input             fb_wr_busy,
    output reg        fb_er_req,
    output reg  [1:0] fb_er_buf,
    output reg  [8:0] fb_er_y,
    input             fb_er_ack,
    output reg        fb_rd_req,
    output reg  [1:0] fb_rd_buf,
    output reg  [8:0] fb_rd_y,
    input             fb_rd_ack,

    output reg        disp_buf,       // buffer currently displayed
    output reg [191:0] disp_rot,      // its rotation parameters: {currx, curry, dyy, dxx, dxy, dyx}, 32 bits each
    output reg        rendering
);

// ---------------------------------------------------------------- buffers
reg        render_pending;
reg        did_render;
reg        er_need;
reg  [8:0] er_line;
reg [11:0] vis_clr;          // visited-set clear counter (runs during the erase)
reg        vis_clearing;
reg [191:0] rot_r;           // rotation parameters latched with the render (words 3F0-3FB)
reg   [3:0] rcnt;

typedef enum logic [4:0] {
    R_IDLE, R_ERASE, R_ERASEW, R_ROT,
    R_FETCH, R_FETCHW, R_DECODE, R_IND, R_INDW, R_ROW, R_BANK, R_CLIP, R_CLIPA, R_CLIPB, R_CLIPC,
    R_ROWWAIT, R_ROMREQ, R_ROMWAIT, R_PIX, R_ROWEND, R_ROWSKIP, R_NEXT
} rs_t;
rs_t rs;
wire erasing = (rs == R_ERASE) || (rs == R_ERASEW);

// ---------------------------------------------------------------- visited set
// 4096 x 1, cleared while the back buffer is erased, set as entries are walked
reg        vis_mem [0:4095];
reg        vis_q;
reg        vis_we;
reg [11:0] vis_waddr;
reg        vis_wdata;
reg [11:0] idx, next_idx;
always @(posedge clk) begin
    if (vis_we) vis_mem[vis_waddr] <= vis_wdata;
    vis_q <= vis_mem[idx];
end

// ---------------------------------------------------------------- list entry
reg  [3:0] wcnt;
reg [15:0] w [0:7];
reg        hide;
reg  [4:0] bank;
reg [11:0] xpos, top;
reg [15:0] addr;             // row base (MAME addr), advanced by pitch
reg [15:0] height;
reg        ydown, flip, xright;
reg [10:0] zoom;
reg [15:0] colpri;
reg signed [7:0] pitch;
reg  [8:0] ind9 [0:15];      // indirection table: pen value
reg        indok [0:15];     //   and "draws" (< 0x1FE)
reg  [4:0] icnt;

// row state
reg [12:0] y;                // 0x600-based, may run past the buffer
reg [15:0] rows_left;
reg  [8:0] yacc;
reg [15:0] rowaddr;
reg signed [14:0] x;         // 0x600-based, may leave the clip window either side
reg [11:0] xacc;
reg  [3:0] nib;
reg [63:0] pixels;
reg        last_data;
reg [15:0] minx;             // this row's min extent (raw from rotation RAM, with flags)
reg [13:0] minx_c, maxx_c;   // clamped to the buffer (0x600 .. 0x7FF)
reg        have_run;
reg [15:0] run_rowaddr;
reg [13:0] run_minx, run_maxx;

wire [8:0] fy      = y[8:0];                          // framebuffer line
wire       y_in_fb = (y[12:9] == 4'b0011);            // 0x600 .. 0x7FF
wire signed [14:0] minx_s = $signed({1'b0, minx_c});
wire signed [14:0] maxx_s = $signed({1'b0, maxx_c});
wire       x_in    = (x >= minx_s) && (x <= maxx_s);


// ROM burst: two 64-bit words; keep the burst and pick the half
reg [127:0] burst;
reg  [14:0] burst_tag;
reg   [4:0] burst_bank;
reg         burst_valid;
wire        burst_hit = burst_valid && burst_tag == rowaddr[15:1] && burst_bank == bank;
// a 64-bit word as MAME sees it: pens from bit 63 down; the stream holds it
// as four 16-bit words, first word first
wire [63:0] word_lo = {burst[15:0],  burst[31:16],  burst[47:32],   burst[63:48]};
wire [63:0] word_hi = {burst[79:64], burst[95:80], burst[111:96], burst[127:112]};
wire [63:0] word_sel = rowaddr[0] ? word_hi : word_lo;
// draw order into the low nibble: non-flipped draws bits 63:60 first
function automatic [63:0] rev16(input [63:0] p);
    integer k;
    for (k = 0; k < 16; k = k + 1) rev16[k*4 +: 4] = p[(15-k)*4 +: 4];
endfunction

wire [3:0] pen  = pixels[3:0];
wire [8:0] ind  = ind9[pen];
wire       indv = indok[pen];

// the whole-line read port is unused: the 315-5306 fetches single words
always @(posedge clk) begin fb_rd_req <= 1'b0; fb_rd_buf <= 2'd0; fb_rd_y <= 9'd0; end

// yacc += zoom; addr += pitch * (yacc >> 9); yacc &= 0x1ff, sum registered a
// clock ahead (every use is at least two clocks after the last yacc write)
reg [11:0] row_sum;
always @(posedge clk) row_sum <= {3'd0, yacc} + {1'b0, zoom};
function automatic [24:0] next_row(input [15:0] ra);
    logic signed [15:0] step;
    step = $signed(pitch) * $signed({1'b0, row_sum[11:9]});
    next_row = {row_sum[8:0], ra + step};
endfunction

// ---------------------------------------------------------------- renderer
always @(posedge clk) begin
    fb_wr_start <= 1'b0;
    fb_wr_valid <= 1'b0;
    fb_wr_end   <= 1'b0;
    fb_wr_dup   <= 1'b0;
    rom_req     <= 1'b0;
    vis_we      <= 1'b0;
    if (reset) begin
        rs <= R_IDLE; disp_buf <= 1'b0; render_pending <= 1'b0; rendering <= 1'b0;
        burst_valid <= 1'b0; idx <= 12'd0; next_idx <= 12'd0; wcnt <= 4'd0; icnt <= 5'd0;
        fb_er_req <= 1'b0; did_render <= 1'b0; er_need <= 1'b1; er_line <= 9'd0;
        vis_clr <= 12'd0; vis_clearing <= 1'b0;
        disp_rot <= 192'd0; rot_r <= 192'd0; rcnt <= 4'd0;
        have_run <= 1'b0;
    end
    else begin
        if (start_req) render_pending <= 1'b1;

        // visited-set clear runs alongside the erase
        if (vis_clearing) begin
            vis_we <= 1'b1; vis_waddr <= vis_clr; vis_wdata <= 1'b0;
            vis_clr <= vis_clr + 12'd1;
            if (vis_clr == 12'd4095) vis_clearing <= 1'b0;
        end

        // vblank: swap if a render ran since the last swap, abort a running one
        if (vbl_start && !erasing) begin
            if (rendering || did_render) begin
                disp_buf <= ~disp_buf; er_need <= 1'b1;
                disp_rot <= rot_r;
            end
            did_render <= 1'b0;
            rendering <= 1'b0;
            if (rs != R_IDLE && rs != R_ROWWAIT) fb_wr_end <= 1'b1;   // close an open run
            fb_er_req <= 1'b0;
            rs <= R_IDLE;
        end
        else case (rs)
        R_IDLE: begin
            if (er_need) begin
                er_line <= 9'd0; rs <= R_ERASE;
                vis_clr <= 12'd0; vis_clearing <= 1'b1;
            end
            else if (render_pending && !fb_wr_busy && !vis_clearing) begin
                render_pending <= 1'b0;
                rendering <= 1'b1;
                did_render <= 1'b1;
                idx <= 12'd0;
                burst_valid <= 1'b0;
                rot_addr <= 10'h3F0; rcnt <= 4'd0;
                rs <= R_ROT;
            end
        end
        // erase the back buffer, all 512 lines, as soon as it becomes the back buffer
        R_ERASE: begin
            fb_er_req <= 1'b1;
            fb_er_buf <= {1'b0, ~disp_buf};
            fb_er_y   <= er_line;
            rs <= R_ERASEW;
        end
        R_ERASEW: begin
            if (fb_er_ack) begin
                fb_er_req <= 1'b0;
                if (er_line == 9'd511) begin er_need <= 1'b0; rs <= R_IDLE; end
                else begin er_line <= er_line + 9'd1; rs <= R_ERASE; end
            end
        end
        // rotation parameters, words 3F0-3FB (big-endian 32-bit pairs) into
        // rot_r, most significant first. The address for word 0 went out in
        // R_IDLE and the RAM answers two clocks later, in the rcnt == 1 cycle;
        // word k is captured at rcnt == k + 1
        R_ROT: begin
            rot_addr <= 10'h3F0 + {6'd0, rcnt + 4'd1};
            if (rcnt >= 4'd1) rot_r <= {rot_r[175:0], rot_q};
            rcnt <= rcnt + 4'd1;
            if (rcnt == 4'd12) rs <= R_FETCH;
        end
        // read the 8 words of the entry (sram is 1-clk registered) and the visited bit
        R_FETCH: begin sram_addr <= {idx, 3'd0}; wcnt <= 4'd0; rs <= R_FETCHW; end
        R_FETCHW: begin
            sram_addr <= {idx, 3'd0} + {11'd0, wcnt + 4'd1};
            if (wcnt != 4'd0) begin logic [3:0] wi; wi = wcnt - 4'd1; w[wi[2:0]] <= sram_q; end
            wcnt <= wcnt + 4'd1;
            if (wcnt == 4'd8) rs <= R_DECODE;
        end
        R_DECODE: begin
            if (w[0][15] || vis_q) begin rs <= R_IDLE; rendering <= 1'b0; end   // end of list / loop
            else begin
                vis_we <= 1'b1; vis_waddr <= idx; vis_wdata <= 1'b1;
                next_idx <= w[7][11:0];
                hide   <= |(w[0] & 16'h5000);
                bank   <= {w[1][12], w[2][15:12]};
                xpos   <= w[1][11:0];
                top    <= w[2][11:0];
                addr   <= w[3];
                height <= w[4];
                ydown  <= w[5][14];
                flip   <= ~w[5][13];
                xright <= w[5][12];
                zoom   <= (w[5][10:0] == 11'd0) ? 11'd1 : w[5][10:0];
                colpri <= {w[6][14:8], 9'd0};
                pitch  <= w[6][7:0];
                sram_addr <= {w[0][10:0], 4'd0};
                icnt <= 5'd0;
                if ((|(w[0] & 16'h5000)) || w[4] == 16'd0) rs <= R_NEXT;
                else rs <= R_INDW;
            end
        end
        // fetch the 16-entry indirection table
        R_INDW: begin
            sram_addr <= {w[0][10:0], 4'd0} + {11'd0, icnt[3:0] + 4'd1};
            if (icnt != 5'd0) begin
                logic [4:0] ii; ii = icnt - 5'd1;
                ind9[ii[3:0]]  <= sram_q[8:0];
                indok[ii[3:0]] <= (sram_q < 16'h01FE);
            end
            icnt <= icnt + 5'd1;
            if (icnt == 5'd16) rs <= R_ROW;
        end
        R_ROW: begin
            y <= {1'b0, top}; rows_left <= height; yacc <= 9'd0; have_run <= 1'b0;
            rs <= R_BANK;
        end
        // bank wraps to the ROM size (MAME bank %= numbanks): one subtraction
        // per clock, at most three (32 bank values, 8 banks or more)
        R_BANK: begin
            if (num_banks != 8'd0 && {3'd0, bank} >= num_banks) bank <= bank - num_banks[4:0];
            else rs <= R_CLIP;
        end
        // per row: extents from the rotation RAM (two reads), then clip/skip/end
        R_CLIP: begin
            if (rows_left == 16'd0) rs <= R_NEXT;
            else if (!y_in_fb) rs <= R_ROWSKIP;
            else begin rot_addr <= {1'b0, fy[8:1], 1'b0}; rs <= R_CLIPA; end
        end
        R_CLIPA: begin rot_addr <= {1'b0, fy[8:1], 1'b1}; rs <= R_CLIPB; end
        R_CLIPB: begin minx <= rot_q; rs <= R_CLIPC; end
        R_CLIPC: begin
            if (minx[15] && !ydown) rs <= R_NEXT;          // above the top, drawing upwards: done
            else if (minx[14] && ydown) rs <= R_NEXT;      // below the bottom, drawing downwards
            else if (minx[15] || minx[14]) rs <= R_ROWSKIP;
            else begin
                // MAME clamps min up to the buffer's left edge and max down to
                // its right edge; a min beyond the right edge simply draws nothing
                minx_c <= (minx[13:0] < 14'h600) ? 14'h600 : minx[13:0];
                maxx_c <= (rot_q > 16'h07FF) ? 14'h7FF : rot_q[13:0];
                rs <= R_ROWWAIT;
            end
        end
        // open a run, or re-flush the held one when the row is the same source
        // row with the same extents (the zoom accumulator did not advance)
        R_ROWWAIT: begin
            if (!fb_wr_busy && have_run && addr == run_rowaddr && minx_c == run_minx && maxx_c == run_maxx) begin
                fb_wr_dup   <= 1'b1;
                fb_wr_dup_y <= fy;
                rs <= R_ROWSKIP;
            end
            else if (!fb_wr_busy) begin
                have_run    <= 1'b1;
                run_rowaddr <= addr; run_minx <= minx_c; run_maxx <= maxx_c;
                fb_wr_start <= 1'b1;
                fb_wr_buf   <= {1'b0, ~disp_buf};
                fb_wr_y     <= fy;
                rowaddr <= addr;
                x <= $signed({3'b000, xpos}); xacc <= 12'd0; nib <= 4'd0;
                rs <= R_ROMREQ;
            end
        end
        R_ROMREQ: begin
            if (!((xright && x <= maxx_s) || (!xright && x >= minx_s))) begin
                fb_wr_end <= 1'b1; rs <= R_ROWEND;      // ran past the extents: end of row
            end
            else if (burst_hit) begin
                pixels    <= flip ? word_sel : rev16(word_sel);
                last_data <= flip ? (word_sel[63:60] == 4'hF) : (word_sel[3:0] == 4'hF);
                rowaddr   <= flip ? rowaddr - 16'd1 : rowaddr + 16'd1;
                nib <= 4'd0;
                rs <= R_PIX;
            end
            else begin
                rom_req  <= 1'b1;
                rom_addr <= SDR_YSPR_BASE[24:4] + {1'b0, bank, rowaddr[15:1]};
                rs <= R_ROMWAIT;
            end
        end
        R_ROMWAIT: begin
            if (rom_ack) begin
                burst <= rom_dout; burst_tag <= rowaddr[15:1]; burst_bank <= bank; burst_valid <= 1'b1;
                rs <= R_ROMREQ;
            end
        end
        // one framebuffer pixel per clock while xacc < 0x200; the step to the
        // next pen happens in the clock that exhausts the accumulator
        R_PIX: begin
            logic [11:0] xacc1; logic adv;
            xacc1 = xacc + {1'b0, zoom};
            if (xacc < 12'h200) begin
                fb_wr_valid <= x_in && indv;
                fb_wr_lanes <= 4'b0001 << x[1:0];
                fb_wr_pix   <= colpri | {7'd0, ind};
                fb_wr_x     <= {1'b0, x[8:0]};
                x    <= xright ? x + 15'sd1 : x - 15'sd1;
                adv  = (xacc1 >= 12'h200);
                xacc <= adv ? xacc1 - 12'h200 : xacc1;
            end
            else begin
                adv  = 1'b1;
                xacc <= xacc - 12'h200;
            end
            if (adv) begin
                pixels <= pixels >> 4;
                if (nib == 4'd15) begin
                    if (last_data) begin fb_wr_end <= 1'b1; rs <= R_ROWEND; end
                    else rs <= R_ROMREQ;
                end
                nib <= nib + 4'd1;
            end
        end
        R_ROWEND: begin
            {yacc, addr} <= next_row(addr);
            y <= ydown ? y + 13'd1 : y - 13'd1;
            rows_left <= rows_left - 16'd1;
            rs <= R_CLIP;
        end
        R_ROWSKIP: begin
            {yacc, addr} <= next_row(addr);
            y <= ydown ? y + 13'd1 : y - 13'd1;
            rows_left <= rows_left - 16'd1;
            rs <= R_CLIP;
        end
        R_NEXT: begin idx <= next_idx; rs <= R_FETCH; end
        default: rs <= R_IDLE;
        endcase
    end
end
endmodule
