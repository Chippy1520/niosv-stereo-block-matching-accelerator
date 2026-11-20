`timescale 1ns/1ps
`default_nettype none

// Complete compute datapath, not a controller or memory-bus interface.
// Read at t -> result after t+2+$clog2(K)+1+max(1,$clog2(LANES)).
module stereo_sad_datapath #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer IMG_W = 640,
    parameter integer IMG_H = 480,
    parameter integer LANES = 32,
    parameter integer SPARE_ROWS = 1,
    parameter integer SAD_W = PIXEL_W + $clog2(K*K),
    parameter integer D_W = (LANES <= 1) ? 1 : $clog2(LANES),
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
    output wire                          valid_o,
    output wire [SAD_W-1:0]             sad_o,
    output wire [D_W-1:0]               disparity_o,
    output wire [X_W-1:0]               x_o,
    output wire [Y_W-1:0]               y_o,
    output wire                          row_last_o,
    output logic [31:0]                 result_o
);
    wire left_valid, row_last;
    wire [K*PIXEL_W-1:0] left_column;
    wire [LANES-1:0] right_valid;
    wire [LANES*K*PIXEL_W-1:0] right_columns;
    wire [X_W-1:0] x;
    wire [Y_W-1:0] y;

    stereo_frontend #(
        .K(K), .PIXEL_W(PIXEL_W), .IMG_W(IMG_W), .IMG_H(IMG_H), .TAPS(LANES),
        .SPARE_ROWS(SPARE_ROWS),
        .X_W(X_W), .Y_W(Y_W), .BANK_W(BANK_W), .WORD_AW(WORD_AW)
    ) frontend (
        .clk(clk), .rst_n(rst_n), .frame_clear_i(frame_clear_i), .row_clear_i(row_clear_i),
        .left_write_valid_i(left_write_valid_i), .right_write_valid_i(right_write_valid_i),
        .write_bank_i(write_bank_i), .write_word_i(write_word_i),
        .left_write_data_i(left_write_data_i), .right_write_data_i(right_write_data_i),
        .read_valid_i(read_valid_i), .read_x_i(read_x_i), .read_y_i(read_y_i),
        .read_oldest_i(read_oldest_i), .left_valid_o(left_valid), .left_column_o(left_column),
        .right_valid_o(right_valid), .right_columns_o(right_columns),
        .x_o(x), .y_o(y), .row_last_o(row_last)
    );
    sad_search_backend #(
        .K(K), .PIXEL_W(PIXEL_W), .LANES(LANES), .IMG_W(IMG_W), .IMG_H(IMG_H),
        .SAD_W(SAD_W), .D_W(D_W), .X_W(X_W), .Y_W(Y_W)
    ) backend (
        .clk(clk), .rst_n(rst_n), .clear_i(frame_clear_i || row_clear_i),
        .valid_i(left_valid), .left_column_i(left_column),
        .right_columns_i(right_columns), .right_valid_i(right_valid),
        .x_i(x), .y_i(y), .row_last_i(row_last),
        .valid_o(valid_o), .sad_o(sad_o), .disparity_o(disparity_o),
        .x_o(x_o), .y_o(y_o), .row_last_o(row_last_o)
    );

    // A combinational record adds no latency; invalid cycles are exactly zero.
    // Part-selects avoid a negative replication count for rejected parameters.
    always_comb begin
        result_o = '0;
        if (valid_o) begin
            result_o[0 +: SAD_W] = sad_o;
            result_o[SAD_W +: D_W] = disparity_o;
            result_o[31] = 1'b1;
        end
    end

    // synthesis translate_off
    initial begin
        if (SAD_W+D_W > 31)
            $fatal(1, "DATAPATH record requires SAD_W+D_W<=31");
        if (SPARE_ROWS < 1)
            $fatal(1, "DATAPATH SPARE_ROWS must be at least one");
        if (BANK_W < ((K+SPARE_ROWS<=1)?1:$clog2(K+SPARE_ROWS)) ||
            WORD_AW < (((IMG_W+3)/4<=1)?1:$clog2((IMG_W+3)/4)))
            $fatal(1, "DATAPATH undersized bank/word address");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
