`timescale 1ns/1ps
`default_nettype none
// Expected-failure companion bench; scripts/check_test_sensitivity.py checks
// specific contract messages, not compilation failures or an unrelated timeout.
module tb_packed_row_guards;
    parameter integer FAULT = 0;
    localparam integer K = 4;
    localparam integer S = (FAULT == 0) ? 0 : 2;
    localparam integer BW = (FAULT == 1) ? 2 : 3;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0, write_valid_i = 0, read_valid_i = 0;
    logic [BW-1:0] write_bank_i = 0, read_oldest_i = 0;
    logic [1:0] write_word_i = 0;
    logic [3:0] read_x_i = 0;
    wire column_valid_o;
    wire [K*8-1:0] column_o;
    packed_circular_row_buffer #(.K(K), .PIXEL_W(8), .IMG_W(9),
        .SPARE_ROWS(S), .BANK_W(BW)) dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .write_valid_i(write_valid_i), .write_bank_i(write_bank_i),
        .write_word_i(write_word_i), .write_data_i(32'h12345678),
        .read_valid_i(read_valid_i), .read_x_i(read_x_i), .read_oldest_i(read_oldest_i),
        .column_valid_o(column_valid_o), .column_o(column_o)
    );
    initial begin
        @(negedge clk); rst_n = 1;
        case (FAULT)
            2: begin write_valid_i = 1; write_bank_i = K+S; end
            3: begin read_valid_i = 1; read_oldest_i = K+S; end
            4: begin write_valid_i = 1; write_word_i = 3; end
            5: begin read_valid_i = 1; read_x_i = 9; end
            6: begin read_valid_i = 1; write_valid_i = 1; end
            7: begin read_valid_i = 1; write_valid_i = 1; write_word_i = 1; end
            8: begin
                read_valid_i = 1; write_valid_i = 1;
                read_oldest_i = K+S-1; write_bank_i = 0; write_word_i = 1;
            end
            default: begin end
        endcase
        @(posedge clk); #1;
        $fatal(1, "GUARD_TEST missing expected rejection FAULT=%0d", FAULT);
    end
endmodule
`default_nettype wire
