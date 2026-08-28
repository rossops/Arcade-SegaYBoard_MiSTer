//============================================================================
//  Sega 315-5306 scan-out: the affine walk over the Y sprite framebuffer.
//  MAME segaic16.cpp rotate_draw: per frame currx += dxx * 27 (the 27 is
//  MAME's calibration, open question 5), then per screen pixel
//  tx += dxx, ty += dyx and per line currx += dxy, curry += dyy; the source
//  pixel is ((ty >> 14) & 0x1FF, (tx >> 14) & 0x1FF). A written pixel becomes
//  palette index {1, colour[1:0], colour[2], pen[8:0]} with priority
//  {pixel[15:9], 1}; an empty one (FFFF) the source line number with priority
//  FF (the scanline colour).
//
//  The framebuffer is in DDR3, so each screen line is built one line ahead
//  into a line buffer: the address stream goes through a direct-mapped cache
//  of 128 64-bit words (four pixels) indexed by sx[8:2] ^ sy[6:0], which
//  keeps a whole source row resident when consecutive lines read the same
//  row and spreads vertical walks; misses are single-word reads through
//  yb_fb_if. The cache is emptied when the displayed buffer changes.
//  Line v+1 is computed while line v is displayed; at each line start the
//  banks swap (the display side in clk_sys, the fill side in clk_ram), and a
//  line not finished by then is counted (late_count) and shown anyway. verif/models/rotate5306.py is the golden model.
//============================================================================
module yb_rotate_5306 (
    input             clk,            // clk_ram
    input             reset,

    input             line_start,     // one-clk pulse (clk_ram) at hcnt == 0
    input       [8:0] vcnt,           // line being displayed
    input             disp_buf,       // framebuffer on display
    input     [191:0] disp_rot,       // {currx, curry, dyy, dxx, dxy, dyx}

    // single-word framebuffer reads (yb_fb_if rq port)
    output reg        rq_req,
    output reg  [1:0] rq_buf,
    output reg  [8:0] rq_y,
    output reg  [6:0] rq_xw,
    input             rq_ack,
    input      [63:0] rq_data,

    // display side (rd_clk = clk_sys): the line buffer entry for screen x of
    // the current line, registered one rd_clk after rd_x. rd_line_start is
    // the clk_sys line start of every displayed line (0..223); the builder
    // toggles its bank on lines 261 and 0..222, so the two selects stay in
    // step from reset (fill 1, display 0) and line v is read from the bank
    // it was built in
    input             rd_clk,
    input             rd_line_start,
    input       [8:0] rd_x,
    output     [12:0] rd_idx,
    output      [7:0] rd_pri,

    // bench statistics, per line
    output reg  [8:0] miss_count,     // DDR3 words fetched for the last completed line
    output reg [12:0] line_clocks,    // clocks from line start to completion
    output reg [15:0] late_count      // lines still being built at their deadline
);

wire signed [31:0] p_currx = disp_rot[191:160];
wire signed [31:0] p_curry = disp_rot[159:128];
wire signed [31:0] p_dyy   = disp_rot[127:96];
wire signed [31:0] p_dxx   = disp_rot[95:64];
wire signed [31:0] p_dxy   = disp_rot[63:32];
wire signed [31:0] p_dyx   = disp_rot[31:0];

// ---------------------------------------------------------------- line buffer
// two banks of 320 x {idx, pri}: written in clk (fill_bank), read in rd_clk
// (disp_bank); both toggle once per line, from opposite reset values
reg [20:0] lb [0:1023];
reg        fill_bank;
reg        disp_bank;
reg [20:0] lb_q;
reg        lb_we;
reg  [8:0] lb_waddr;
reg [20:0] lb_wdata;
always @(posedge clk) if (lb_we) lb[{fill_bank, lb_waddr}] <= lb_wdata;
always @(posedge rd_clk) begin
    if (reset) disp_bank <= 1'b0;
    else if (rd_line_start) disp_bank <= ~disp_bank;
    lb_q <= lb[{disp_bank, rd_x}];
end
assign rd_idx = lb_q[20:8];
assign rd_pri = lb_q[7:0];

// ---------------------------------------------------------------- cache
wire [8:0] sx_c, sy_c;
wire [6:0] cidx = sx_c[8:2] ^ sy_c[6:0];
reg  [63:0] c_data [0:127];
reg   [8:0] c_tag  [0:127];      // source line (sx[8:2] follows from the index)
reg [127:0] c_valid;
reg   [6:0] c_idx;
reg  [63:0] c_data_q;
reg   [8:0] c_tag_q;
reg         c_we;
reg   [6:0] c_waddr;
reg  [63:0] c_wdata;
reg   [8:0] c_wtag;
// the read address is the pixel's index as computed (cidx): S_LOOK registers
// c_idx for the write side and the RAM answers in S_MISS for the same pixel
always @(posedge clk) begin
    if (c_we) begin c_data[c_waddr] <= c_wdata; c_tag[c_waddr] <= c_wtag; end
    c_data_q <= c_data[cidx];
    c_tag_q  <= c_tag[cidx];
end

// ---------------------------------------------------------------- walker
typedef enum logic [2:0] { S_IDLE, S_STEP, S_LOOK, S_MISS, S_MISSW, S_FILL } st_t;
st_t st;
reg signed [31:0] lx, ly;        // start of the line being built
reg signed [31:0] tx, ty;        // current pixel
reg  [8:0] x;                    // screen x being built
reg  [8:0] sx, sy;               // source pixel of x
reg  [8:0] cnt_miss;
reg [12:0] cnt_clk;
reg        building;
reg        disp_buf_d;
reg  [8:0] next_line;
assign sx_c = tx[22:14];
assign sy_c = ty[22:14];
wire [15:0] pix = (sx[1:0] == 2'd0) ? c_data_q[15:0] : (sx[1:0] == 2'd1) ? c_data_q[31:16] :
                  (sx[1:0] == 2'd2) ? c_data_q[47:32] : c_data_q[63:48];
wire [15:0] mpix = (sx[1:0] == 2'd0) ? rq_data[15:0] : (sx[1:0] == 2'd1) ? rq_data[31:16] :
                   (sx[1:0] == 2'd2) ? rq_data[47:32] : rq_data[63:48];
function automatic [20:0] entry(input [15:0] p, input [8:0] line);
    entry = (p != 16'hFFFF) ? {1'b1, p[14:13], p[15], p[8:0], p[15:9], 1'b1} : {4'd0, line, 8'hFF};
endfunction

always @(posedge clk) begin
    lb_we <= 1'b0;
    c_we  <= 1'b0;
    if (reset) begin
        st <= S_IDLE; fill_bank <= 1'b1; building <= 1'b0; rq_req <= 1'b0;
        c_valid <= 128'd0; disp_buf_d <= 1'b0;
        miss_count <= 9'd0; line_clocks <= 13'd0; late_count <= 16'd0;
        lx <= 32'd0; ly <= 32'd0; tx <= 32'd0; ty <= 32'd0; x <= 9'd0; cnt_miss <= 9'd0; cnt_clk <= 13'd0;
        next_line <= 9'd0;
    end
    else begin
        disp_buf_d <= disp_buf;
        if (disp_buf != disp_buf_d) c_valid <= 128'd0;   // new picture on display
        if (building) cnt_clk <= cnt_clk + 13'd1;

        // line start: publish the line just built, start the next one
        if (line_start && (vcnt < 9'd223 || vcnt == 9'd261)) begin
            if (building) late_count <= late_count + 16'd1;
            fill_bank <= ~fill_bank;
            next_line <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
            // line 0 starts at (currx + 27 dxx, curry + 27 dyx); each later line adds (dxy, dyy)
            if (vcnt == 9'd261) begin
                lx <= p_currx + (p_dxx <<< 4) + (p_dxx <<< 3) + (p_dxx <<< 1) + p_dxx;
                ly <= p_curry + (p_dyx <<< 4) + (p_dyx <<< 3) + (p_dyx <<< 1) + p_dyx;
            end
            else begin
                lx <= lx + p_dxy;
                ly <= ly + p_dyy;
            end
            building <= 1'b1; cnt_miss <= 9'd0; cnt_clk <= 13'd0;
            st <= S_STEP;
            x <= 9'd0;
        end
        else case (st)
        S_IDLE: ;
        // first pixel of the line: load the accumulators
        S_STEP: begin
            tx <= lx; ty <= ly;
            st <= S_LOOK;
        end
        // present the cache index for the pixel at (tx, ty); the RAM answers next clock
        S_LOOK: begin
            c_idx <= cidx; sx <= sx_c; sy <= sy_c;
            st <= S_MISS;
        end
        // hit: emit; miss: fetch the word
        S_MISS: begin
            if (c_valid[c_idx] && c_tag_q == sy) begin
                lb_we <= 1'b1; lb_waddr <= x; lb_wdata <= entry(pix, sy);
                if (x == 9'd319) begin building <= 1'b0; miss_count <= cnt_miss; line_clocks <= cnt_clk; st <= S_IDLE; end
                else begin x <= x + 9'd1; tx <= tx + p_dxx; ty <= ty + p_dyx; st <= S_LOOK; end
            end
            else begin
                rq_req <= 1'b1; rq_buf <= {1'b0, disp_buf}; rq_y <= sy; rq_xw <= sx[8:2];
                cnt_miss <= cnt_miss + 9'd1;
                st <= S_MISSW;
            end
        end
        S_MISSW: begin
            if (rq_ack) begin
                rq_req <= 1'b0;
                c_we <= 1'b1; c_waddr <= c_idx; c_wdata <= rq_data; c_wtag <= sy;
                c_valid[c_idx] <= 1'b1;
                lb_we <= 1'b1; lb_waddr <= x; lb_wdata <= entry(mpix, sy);
                if (x == 9'd319) begin building <= 1'b0; miss_count <= cnt_miss; line_clocks <= cnt_clk; st <= S_IDLE; end
                else begin x <= x + 9'd1; tx <= tx + p_dxx; ty <= ty + p_dyx; st <= S_FILL; end
            end
        end
        // the fill lands in the cache RAM this clock; a lookup in the same
        // clock would read the old tag and miss the same word again
        S_FILL: st <= S_LOOK;
        default: st <= S_IDLE;
        endcase
    end
end
endmodule
