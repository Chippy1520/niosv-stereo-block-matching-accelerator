`timescale 1ns/1ps
`default_nettype none

// Datapath only: the caller owns loading, bank lifetime and read scheduling.
// Read at t -> stored columns after t -> paired columns/tags after t+1.
// A downstream clocked consumer samples that pair at t+2.
module stereo_frontend #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer IMG_W = 640,
    parameter integer IMG_H = 480,
    parameter integer TAPS = 32,
    parameter integer SPARE_ROWS = 1,
    parameter integer X_W = (IMG_W <= 1) ? 1 : $clog2(IMG_W),
    parameter integer Y_W = (IMG_H <= 1) ? 1 : $clog2(IMG_H),
    parameter integer BANK_W = (K+SPARE_ROWS <= 1) ? 1 : $clog2(K+SPARE_ROWS),
    parameter integer WORD_AW = ((IMG_W+3)/4 <= 1) ? 1 : $clog2((IMG_W+3)/4)
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          frame_clear_i,
    input  wire                          row_clear_i,
    input  wire                          left_write_valid_i,
    input  wire                          right_write_valid_i,
    input  wire [BANK_W-1:0]             write_bank_i,
    input  wire [WORD_AW-1:0]            write_word_i,
    input  wire [4*PIXEL_W-1:0]          left_write_data_i,
    input  wire [4*PIXEL_W-1:0]          right_write_data_i,
    input  wire                          read_valid_i,
    input  wire [X_W-1:0]                read_x_i,
    input  wire [Y_W-1:0]                read_y_i,
    input  wire [BANK_W-1:0]             read_oldest_i,
    output wire                          left_valid_o,
    output wire [K*PIXEL_W-1:0]          left_column_o,
    output wire [TAPS-1:0]               right_valid_o,
    output wire [TAPS*K*PIXEL_W-1:0]     right_columns_o,
    output logic [X_W-1:0]              x_o,
    output logic [Y_W-1:0]              y_o,
    output logic                         row_last_o
);
    localparam integer COL_W = K * PIXEL_W;
    wire history_clear = frame_clear_i || row_clear_i;
    wire read_enable = read_valid_i && !history_clear;
    wire left_column_valid, right_column_valid;
    wire [COL_W-1:0] left_stored_column, right_stored_column;
    logic [X_W-1:0] pending_x;
    logic [Y_W-1:0] pending_y;

    // Row clear leaves RAM and the independent load path untouched.
    // Frame clear/reset have priority inside both stores, including over writes.
    packed_circular_row_buffer #(
        .K(K), .PIXEL_W(PIXEL_W), .IMG_W(IMG_W), .SPARE_ROWS(SPARE_ROWS),
        .X_W(X_W), .BANK_W(BANK_W), .WORD_AW(WORD_AW)
    ) left_rows (
        .clk(clk), .rst_n(rst_n), .clear_i(frame_clear_i),
        .write_valid_i(left_write_valid_i), .write_bank_i(write_bank_i),
        .write_word_i(write_word_i), .write_data_i(left_write_data_i),
        .read_valid_i(read_enable), .read_x_i(read_x_i),
        .read_oldest_i(read_oldest_i), .column_valid_o(left_column_valid),
        .column_o(left_stored_column)
    );
    packed_circular_row_buffer #(
        .K(K), .PIXEL_W(PIXEL_W), .IMG_W(IMG_W), .SPARE_ROWS(SPARE_ROWS),
        .X_W(X_W), .BANK_W(BANK_W), .WORD_AW(WORD_AW)
    ) right_rows (
        .clk(clk), .rst_n(rst_n), .clear_i(frame_clear_i),
        .write_valid_i(right_write_valid_i), .write_bank_i(write_bank_i),
        .write_word_i(write_word_i), .write_data_i(right_write_data_i),
        .read_valid_i(read_enable), .read_x_i(read_x_i),
        .read_oldest_i(read_oldest_i), .column_valid_o(right_column_valid),
        .column_o(right_stored_column)
    );

    left_column_delay #(.K(K), .PIXEL_W(PIXEL_W)) left_align (
        .clk(clk), .rst_n(rst_n), .clear_i(history_clear),
        .valid_i(left_column_valid), .column_i(left_stored_column),
        .valid_o(left_valid_o), .column_o(left_column_o)
    );
    right_column_shift #(.K(K), .PIXEL_W(PIXEL_W), .TAPS(TAPS)) right_cache (
        .clk(clk), .rst_n(rst_n), .clear_i(history_clear),
        .valid_i(right_column_valid), .column_i(right_stored_column),
        .tap_valid_o(right_valid_o), .columns_o(right_columns_o)
    );

    // pending_* follows the RAM read edge. The second register follows the
    // existing delay/cache edge, using the OLD store valid and OLD pending tag.
    // Bubbles hold coordinates/payload but never repeat a valid row-end pulse.
    always_ff @(posedge clk) begin
        if (!rst_n || history_clear) begin
            pending_x <= '0;
            pending_y <= '0;
            x_o <= '0;
            y_o <= '0;
            row_last_o <= 1'b0;
        end else begin
            if (read_enable) begin
                pending_x <= read_x_i;
                pending_y <= read_y_i;
            end
            if (left_column_valid) begin
                x_o <= pending_x;
                y_o <= pending_y;
            end
            row_last_o <= left_column_valid && (pending_x == X_W'(IMG_W-1));
        end
    end

    // synthesis translate_off
    initial begin
        if (K < 1 || PIXEL_W < 1 || IMG_W < 1 || IMG_H < 1 || TAPS < 1 || SPARE_ROWS < 1)
            $fatal(1, "FRONTEND K=%0d parameters must be positive", K);
    end
    // synthesis translate_on
endmodule
`default_nettype wire
