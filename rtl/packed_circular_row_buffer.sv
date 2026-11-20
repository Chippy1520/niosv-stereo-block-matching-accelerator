`timescale 1ns/1ps
`default_nettype none

// Four-pixel word loads and independent vertical-column reads; no scheduler.
// K active rows plus spare prefetch rows; low output slice is oldest.
// Caller owns complete-row readiness, bank lifetime and boundary rotation.
module packed_circular_row_buffer #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer IMG_W = 640,
    parameter integer SPARE_ROWS = 1,
    parameter integer X_W = (IMG_W <= 1) ? 1 : $clog2(IMG_W),
    parameter integer BANK_W = (K+SPARE_ROWS <= 1) ? 1 : $clog2(K+SPARE_ROWS),
    parameter integer WORD_AW = ((IMG_W + 3)/4 <= 1) ? 1 : $clog2((IMG_W + 3)/4)
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clear_i,
    input  wire                         write_valid_i,
    input  wire [BANK_W-1:0]            write_bank_i,
    input  wire [WORD_AW-1:0]           write_word_i,
    input  wire [4*PIXEL_W-1:0]         write_data_i,
    input  wire                         read_valid_i,
    input  wire [X_W-1:0]               read_x_i,
    input  wire [BANK_W-1:0]            read_oldest_i,
    output logic                        column_valid_o,
    output wire [K*PIXEL_W-1:0]         column_o
);
    localparam integer WORD_W = 4 * PIXEL_W;
    localparam integer WORDS = (IMG_W + 3) / 4;
    localparam integer ROW_BANKS = K + SPARE_ROWS;
    wire load_word = rst_n && !clear_i && write_valid_i;
    wire read_column = rst_n && !clear_i && read_valid_i;
    wire [WORD_AW-1:0] read_word = WORD_AW'(read_x_i >> 2);
    wire [ROW_BANKS*WORD_W-1:0] bank_words;
    logic [BANK_W-1:0] oldest;
    logic [1:0] lane;
    logic column_present;
    wire [ROW_BANKS*PIXEL_W-1:0] bank_pixels;

    genvar b, j;
    generate
        for (b = 0; b < ROW_BANKS; b = b + 1) begin : g_bank
            // Circular distance from oldest identifies the K live row banks.
            wire [BANK_W:0] bank_distance = (BANK_W'(b) >= read_oldest_i)
                ? (BANK_W+1)'(b) - {1'b0, read_oldest_i}
                : (BANK_W+1)'(b+ROW_BANKS) - {1'b0, read_oldest_i};
            wire bank_active = bank_distance < (BANK_W+1)'(K);
            row_word_bank #(.WORD_W(WORD_W), .DEPTH(WORDS), .ADDR_W(WORD_AW)) bank (
                .clk(clk), .write_i(load_word && write_bank_i == BANK_W'(b)),
                .write_address_i(write_word_i), .write_data_i(write_data_i),
                .read_i(read_column && bank_active), .read_address_i(read_word),
                .read_data_o(bank_words[b*WORD_W +: WORD_W])
            );
            // Narrow each bank to one pixel before the cross-bank rotation.
            assign bank_pixels[b*PIXEL_W +: PIXEL_W] =
                bank_words[b*WORD_W + lane*PIXEL_W +: PIXEL_W];
        end
        for (j = 0; j < K; j = j + 1) begin : g_tap
            wire [BANK_W:0] bank_sum = {1'b0, oldest} + (BANK_W + 1)'(j);
            wire [BANK_W:0] bank_index = (bank_sum >= (BANK_W + 1)'(ROW_BANKS))
                ? bank_sum - (BANK_W + 1)'(ROW_BANKS) : bank_sum;
            assign column_o[j*PIXEL_W +: PIXEL_W] = column_present
                ? bank_pixels[bank_index[BANK_W-1:0]*PIXEL_W +: PIXEL_W] : '0;
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            oldest <= '0;
            lane <= '0;
            column_present <= 1'b0;
            column_valid_o <= 1'b0;
        end else begin
            column_valid_o <= read_column;
            if (read_column) begin
                oldest <= read_oldest_i;
                lane <= 2'(read_x_i);
                column_present <= 1'b1;
            end
        end
    end

    // synthesis translate_off
    wire [BANK_W:0] write_distance = (write_bank_i >= read_oldest_i)
        ? {1'b0, write_bank_i} - {1'b0, read_oldest_i}
        : {1'b0, write_bank_i} + (BANK_W+1)'(ROW_BANKS) - {1'b0, read_oldest_i};
    initial begin
        if (SPARE_ROWS < 1)
            $fatal(1, "PACKED_ROW SPARE_ROWS must be at least one");
        if (K < 1 || PIXEL_W < 1 || IMG_W < 1 ||
            X_W < ((IMG_W <= 1) ? 1 : $clog2(IMG_W)) ||
            BANK_W < ((ROW_BANKS <= 1) ? 1 : $clog2(ROW_BANKS)) ||
            WORD_AW < ((WORDS <= 1) ? 1 : $clog2(WORDS)))
            $fatal(1, "Positive dimensions and sufficient address widths are required");
    end
    always @(posedge clk) begin
        if (load_word && (write_bank_i >= ROW_BANKS || write_word_i >= WORDS))
            $fatal(1, "PACKED_ROW invalid write address");
        if (read_column && (read_x_i >= IMG_W || read_oldest_i >= ROW_BANKS))
            $fatal(1, "PACKED_ROW invalid column address");
        // Whole active rows stay intact, even when the write word differs.
        // During bubbles/row-clear, ownership remains a caller obligation.
        if (load_word && read_column && write_distance < (BANK_W+1)'(K))
            $fatal(1, "PACKED_ROW cannot overwrite an active row bank");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
