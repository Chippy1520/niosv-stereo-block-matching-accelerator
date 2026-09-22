`timescale 1ns/1ps
`default_nettype none

// One fixed-alignment disparity lane. Upstream supplies already-aligned K-pixel
// columns; image storage, disparity shifting and coordinate tags are NOT inside.
// Accepts one column per edge with valid_i; no input/output backpressure.
// Accepted input at edge t -> window output at t+$clog2(K)+1 (once K columns exist).
// clear_i flushes both the column pipeline and horizontal history immediately.
// Normal row end: drive valid_i=0 for $clog2(K)+1 edges, then clear on its own edge.
module sad_engine #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer COL_W = PIXEL_W + $clog2(K),
    parameter integer SAD_W = PIXEL_W + $clog2(K*K)
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       clear_i,
    input  wire                       valid_i,
    input  wire [K*PIXEL_W-1:0]       left_column_i,
    input  wire [K*PIXEL_W-1:0]       right_column_i,
    output wire                       valid_o,
    output wire [SAD_W-1:0]           sad_o
);
    wire column_valid;
    wire [COL_W-1:0] column_sum;

    column_sad #(.K(K), .PIXEL_W(PIXEL_W), .COL_W(COL_W)) u_column_sad (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(valid_i),
        .left_column_i(left_column_i), .right_column_i(right_column_i),
        .valid_o(column_valid), .column_sum_o(column_sum)
    );

    // The existing buffer ALREADY includes the final H + new_column SAD adder.
    column_sum_buffer #(.K(K), .PIXEL_W(PIXEL_W), .COL_W(COL_W), .SAD_W(SAD_W))
    u_column_sum_buffer (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .valid_i(column_valid), .column_sum_i(column_sum),
        .valid_o(valid_o), .sad_o(sad_o)
    );
endmodule
`default_nettype wire
