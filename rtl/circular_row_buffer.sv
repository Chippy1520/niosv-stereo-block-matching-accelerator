`timescale 1ns/1ps
`default_nettype none

// One image, raster order. A ring of K row slots emits one vertical column
// per accepted pixel once K rows overlap at that x.
// Window row 0 is the oldest and occupies [0 +: PIXEL_W]; row K-1 is pixel_i.
// Accepted at edge t -> registered column after that edge. No backpressure.
// clear_i drops the cursor and output, not RAM. Warmup masks stale storage.
// This is not disparity alignment, pairing, or the SAD engine. Instantiate twice.
// row_last_o marks the last x of a complete window-row. A later controller must
// drain the engine before the next row; this module does not insert that gap.
module circular_row_buffer #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer IMG_W = 640
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       clear_i,
    input  wire                       valid_i,
    input  wire [PIXEL_W-1:0]         pixel_i,
    output logic                      valid_o,
    output logic                      row_last_o,
    output logic [K*PIXEL_W-1:0]      column_o
);
    localparam integer X_W = (IMG_W <= 1) ? 1 : $clog2(IMG_W);
    localparam integer SLOT_W = (K <= 1) ? 1 : $clog2(K);
    localparam integer COUNT_W = $clog2(K + 1);

    logic [X_W-1:0] x;
    logic [SLOT_W-1:0] slot;
    logic [COUNT_W-1:0] rows_filled;
    wire window_ready = (rows_filled >= COUNT_W'(K - 1));
    wire accept_pixel = rst_n && !clear_i && valid_i;
    wire capture_column = accept_pixel && window_ready;

    // These tags/bypass update with the RAM read registers, not a cycle later.
    logic [SLOT_W-1:0] read_slot;
    logic [PIXEL_W-1:0] newest_pixel;
    logic column_present;
    wire [K*PIXEL_W-1:0] bank_columns;

    genvar b, j;
    generate
        if (K > 1) begin : g_rows
            for (b = 0; b < K; b = b + 1) begin : g_bank
                // Keep the recognized RAM template inside its own module boundary.
                row_ram_bank #(.PIXEL_W(PIXEL_W), .DEPTH(IMG_W)) bank (
                    .clk(clk), .enable_i(accept_pixel),
                    .write_i(slot == SLOT_W'(b)), .address_i(x),
                    .pixel_i(pixel_i),
                    .pixel_o(bank_columns[b*PIXEL_W +: PIXEL_W])
                );
            end
        end else begin : g_no_rows
            // K=1 needs only the registered newest pixel, not image RAM.
            assign bank_columns = '0;
        end

        for (j = 0; j < K; j = j + 1) begin : g_tap
            if (j == K - 1) begin : g_newest
                assign column_o[j*PIXEL_W +: PIXEL_W] =
                    column_present ? newest_pixel : '0;
            end else begin : g_older
                // Rotate registered bank reads using the slot from their edge.
                // The live slot may already have advanced at row end.
                wire [SLOT_W:0] tap_sum = {1'b0, read_slot} + (SLOT_W + 1)'(j + 1);
                wire [SLOT_W:0] tap_slot = (tap_sum >= (SLOT_W + 1)'(K))
                    ? tap_sum - (SLOT_W + 1)'(K) : tap_sum;
                assign column_o[j*PIXEL_W +: PIXEL_W] = column_present
                    ? bank_columns[tap_slot[SLOT_W-1:0]*PIXEL_W +: PIXEL_W] : '0;
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            x <= '0;
            slot <= '0;
            rows_filled <= '0;
            valid_o <= 1'b0;
            row_last_o <= 1'b0;
            read_slot <= '0;
            newest_pixel <= '0;
            column_present <= 1'b0;
        end else begin
            valid_o <= capture_column;
            row_last_o <= capture_column && (x == IMG_W - 1);
            if (capture_column) begin
                read_slot <= slot;
                newest_pixel <= pixel_i;
                column_present <= 1'b1;
            end
            if (accept_pixel) begin
                if (x == IMG_W - 1) begin
                    x <= '0;
                    if (K == 1) slot <= '0;
                    else if (slot == K - 1) slot <= '0;
                    else slot <= slot + 1'b1;
                    if (rows_filled < K) rows_filled <= rows_filled + 1'b1;
                end else begin
                    x <= x + 1'b1;
                end
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (K < 1 || PIXEL_W < 1 || IMG_W < 1)
            $fatal(1, "K, PIXEL_W and IMG_W must be positive");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
