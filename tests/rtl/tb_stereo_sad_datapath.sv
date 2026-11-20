`timescale 1ns/1ps
`default_nettype none
module tb_stereo_sad_datapath;
    parameter integer K=3, P=8, W=13, T=5, S=1, H=3*(K+S)+5;
    localparam bit PACKED=1;
    `include "stereo_raw_checks.svh"
    initial if(K<1 || P<1 || W<1 || H<1 || T<1 || SW+DW>31)
        $fatal(1,"DATAPATH K=%0d positive dimensions and a fitting 32-bit record required",K);
    stereo_sad_datapath #(.K(K), .PIXEL_W(P), .IMG_W(W), .IMG_H(H), .LANES(T), .SPARE_ROWS(S)) dut (
        .clk(clk), .rst_n(rst_n), .frame_clear_i(frame_clear_i), .row_clear_i(row_clear_i),
        .left_write_valid_i(left_write_valid_i), .right_write_valid_i(right_write_valid_i),
        .write_bank_i(write_bank_i), .write_word_i(write_word_i),
        .left_write_data_i(left_write_data_i), .right_write_data_i(right_write_data_i),
        .read_valid_i(read_valid_i), .read_x_i(read_x_i), .read_y_i(read_y_i), .read_oldest_i(read_oldest_i),
        .valid_o(valid_o), .sad_o(sad_o), .disparity_o(disparity_o),
        .x_o(x_o), .y_o(y_o), .row_last_o(row_last_o), .result_o(result_o)
    );
    assign observed_costs=dut.backend.lane_sad;
    assign observed_valid=dut.backend.lane_valid;
endmodule
`default_nettype wire
