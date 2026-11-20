`timescale 1ns/1ps
`default_nettype none
module tb_sad_search_backend;
    parameter integer K=3, P=8, W=13, T=5, H=3*K+5;
    localparam integer S=1;
    localparam bit PACKED=0;
    `include "stereo_raw_checks.svh"
    wire clear_i=frame_clear_i || row_clear_i;
    wire row_last_i=read_valid_i && read_x_i==W-1;
    initial if(K<1 || P<1 || W<1 || H<1 || T<1)
        $fatal(1,"DATAPATH K=%0d test dimensions must be positive",K);
    sad_search_backend #(.K(K), .PIXEL_W(P), .LANES(T), .IMG_W(W), .IMG_H(H)) dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(read_valid_i),
        .left_column_i(left_column_i), .right_columns_i(right_columns_i),
        .right_valid_i(right_valid_i), .x_i(read_x_i), .y_i(read_y_i), .row_last_i(row_last_i),
        .valid_o(valid_o), .sad_o(sad_o), .disparity_o(disparity_o),
        .x_o(x_o), .y_o(y_o), .row_last_o(row_last_o)
    );
    assign result_o='0;
    assign observed_costs=dut.lane_sad;
    assign observed_valid=dut.lane_valid;
endmodule
`default_nettype wire
