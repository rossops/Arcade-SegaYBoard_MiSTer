//============================================================================
//  Hiscore glue: JimmyStones' hiscore.v behind the framework's 16-bit ioctl,
//  with the score table carried inside the backup RAM's NVRAM file.
//
//  MiSTer allows one <nvram> per MRA and the Y Board games keep records and
//  settings in the sub X battery RAM, so the saved file is that RAM (16 KB)
//  followed by a 512-byte window holding hiscore.v's table. Inside the index
//  NV_INDEX transfer, addresses with bit 14 set are the window; the module
//  sees them as its own dump index (4). A window that arrives all zero (an
//  old 16 KB file, zero-filled by Main) is treated as no table at all, so
//  nothing is restored from it.
//
//  hps_io runs WIDE (one 16-bit word per ioctl_wr, addresses step by 2) and
//  hiscore.v parses bytes: each word is replayed as two byte writes (low
//  byte = even address), and on upload the two bytes of the requested word
//  are fetched in turn. The game-RAM side is byte wide; bits 23:21 of the
//  address select the CPU space (0 sub Y, 1 sub X), decoded in yb_core.
//============================================================================
module yb_hiscore #(
    parameter CONFIG_INDEX = 5,   // MRA <rom index="5">: header + hiscore.dat entries
    parameter NV_INDEX     = 3    // MRA <nvram index="3">: backup RAM, then the table
) (
    input         clk,
    input         reset,
    input         paused,           // the core really is paused (from the pause module)
    input         autosave,
    input         OSD_STATUS,
    input         ioctl_download,
    input         ioctl_upload,
    input         ioctl_wr,
    input  [26:0] ioctl_addr,
    input   [7:0] ioctl_index,
    input  [15:0] ioctl_dout,
    output [15:0] ioctl_din,        // valid for the window during an index NV_INDEX upload
    output        upload_req,
    output        configured,       // the MRA carried a hiscore table
    // game RAM, byte wide; read data one clock after the address
    output [23:0] ram_addr,
    output  [7:0] ram_din,          // to game RAM
    input   [7:0] ram_dout,         // from game RAM
    output        ram_write,        // write strobe (with ram_wr)
    output        ram_rd,           // hiscore wants the read port
    output        ram_wr,           // hiscore wants the write port
    output        pause_req
);

localparam DUMP_INDEX = 8'd4;     // what hiscore.v is told during the window

wire in_window = (ioctl_index == NV_INDEX[7:0]) && ioctl_addr[14];
wire is_config = (ioctl_index == CONFIG_INDEX[7:0]);

// ---- download: one 16-bit word becomes two byte writes on consecutive clocks
reg        b_wr, pend;
reg [24:0] b_addr, pend_addr;
reg  [7:0] b_data, pend_data;
reg        dl_d;
reg        dump_nonzero;           // a nonzero byte arrived in the window
reg  [2:0] wr_recent;              // clocks since a window word, saturating
always @(posedge clk) begin
    dl_d <= ioctl_download;
    b_wr <= 1'b0;
    if (wr_recent != 3'd7) wr_recent <= wr_recent + 3'd1;
    if (ioctl_download && !dl_d) begin
        b_addr       <= 25'd0;      // a fresh stream starts at its header
        pend         <= 1'b0;
        dump_nonzero <= 1'b0;
    end
    if (ioctl_download && ioctl_wr && (is_config || in_window)) begin
        b_wr      <= 1'b1;
        b_addr    <= ioctl_addr[24:0];
        b_data    <= ioctl_dout[7:0];
        pend      <= 1'b1;
        pend_addr <= ioctl_addr[24:0] + 25'd1;
        pend_data <= ioctl_dout[15:8];
        if (in_window) begin
            wr_recent <= 3'd0;
            if (ioctl_dout != 16'd0) dump_nonzero <= 1'b1;
        end
    end
    else if (pend) begin
        b_wr   <= 1'b1;
        b_addr <= pend_addr;
        b_data <= pend_data;
        pend   <= 1'b0;
    end
end

// The index hiscore.v sees: its dump index for the window, but only while a
// word is being replayed or once real data has shown up, so a blank window
// ends the download under another index and never counts as a loaded dump.
wire window_live = dump_nonzero || (wr_recent != 3'd7);
wire [7:0] hs_ioctl_index = is_config ? CONFIG_INDEX[7:0] :
                            (in_window && (ioctl_upload || window_live)) ? DUMP_INDEX : 8'd0;

// ---- upload: alternate the two byte addresses of the word the host asked
// for; hiscore.v returns a byte two clocks after it sees the address
// (address register, then the buffer RAM), so the phase is delayed to match.
wire        uploading = ioctl_upload && in_window;
wire  [7:0] data_to_hps;
reg         phase, ph_d1, ph_d2;
reg  [15:0] din;
always @(posedge clk) begin
    phase <= ~phase;
    ph_d1 <= phase;
    ph_d2 <= ph_d1;
    if (ph_d2) din[15:8] <= data_to_hps;
    else       din[7:0]  <= data_to_hps;
end
assign ioctl_din = din;

wire [24:0] hs_ioctl_addr = uploading ? {ioctl_addr[24:1], phase} : b_addr;

hiscore #(
    .HS_ADDRESSWIDTH(24),
    .HS_SCOREWIDTH(9),            // 512-byte window: Power Drift needs 399, G-LOC 239
    .HS_CONFIGINDEX(CONFIG_INDEX),
    .HS_DUMPINDEX(DUMP_INDEX),
    .CFG_ADDRESSWIDTH(3),         // up to 8 hiscore.dat lines
    .CFG_LENGTHWIDTH(2)           // two-byte entry lengths (Power Drift's is 0x18F)
) hs (
    .clk(clk),
    .paused(paused),
    .reset(reset),
    .autosave(autosave),
    .ioctl_upload(ioctl_upload),
    .ioctl_upload_req(upload_req),
    .ioctl_download(ioctl_download),
    .ioctl_wr(b_wr),
    .ioctl_addr(hs_ioctl_addr),
    .ioctl_index(hs_ioctl_index),
    .OSD_STATUS(OSD_STATUS),
    .data_from_hps(b_data),
    .data_from_ram(ram_dout),
    .ram_address(ram_addr),
    .data_to_hps(data_to_hps),
    .data_to_ram(ram_din),
    .ram_write(ram_write),
    .ram_intent_read(ram_rd),
    .ram_intent_write(ram_wr),
    .pause_cpu(pause_req),
    .configured(configured)
);

endmodule
