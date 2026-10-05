`timescale 1ns/1ps
`default_nettype none

// Integration bench only: no functional wrapper, row buffers, or SAD engines.
module tb_column_pairing;
    parameter integer K = 11;
    parameter integer P = 8;
    parameter integer T = 32;
    localparam integer C = K * P;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0, valid_i = 0;
    logic [C-1:0] left_i = '0, right_i = '0;
    wire left_valid;
    wire [C-1:0] left_o;
    wire [T-1:0] tap_valid;
    wire [T*C-1:0] right_o;
    left_column_delay #(.K(K), .PIXEL_W(P)) left_dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(valid_i),
        .column_i(left_i), .valid_o(left_valid), .column_o(left_o)
    );
    right_column_shift #(.K(K), .PIXEL_W(P), .TAPS(T)) right_dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(valid_i),
        .column_i(right_i), .tap_valid_o(tap_valid), .columns_o(right_o)
    );
    logic [C-1:0] right_history[];
    logic [C-1:0] expected_left = '0, lv, rv;
    logic [T*C-1:0] expected_right = '0;
    logic [T-1:0] expected_mask = '0;
    bit expected_left_valid = 0;
    integer count = 0, cycles = 0, consumed = 0, random_cycles = 2000;
    integer i, row, ignored;
    logic [31:0] rng = 32'h31415926;
    function automatic logic [31:0] next_random();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction
    function automatic logic [C-1:0] patterned(input integer x, bias);
        integer r;
        for (r = 0; r < K; r = r + 1) patterned[r*P +: P] = P'(bias + x*(K+1) + r);
    endfunction
    task automatic tick(input bit rn, cl, en, input logic [C-1:0] l, r);
        integer d;
        begin
            @(negedge clk);
            rst_n = rn; clear_i = cl; valid_i = en; left_i = l; right_i = r;
            @(posedge clk);
            // Check the pre-NBA values that a synchronous consumer actually samples.
            if (rn && !cl) begin
                if (left_valid !== expected_left_valid || tap_valid !== expected_mask ||
                    left_o !== expected_left || right_o !== expected_right)
                    $fatal(1, "PAIRING K=%0d P=%0d T=%0d consumer mismatch cycle=%0d", K, P, T, cycles);
                for (d = 0; d < T; d = d + 1)
                    if (left_valid && tap_valid[d]) consumed = consumed + 1;
            end
            expected_mask = '0;
            expected_left_valid = rn && !cl && en;
            if (!rn || cl) begin
                count = 0; expected_left = '0; expected_right = '0;
            end else if (en) begin
                if (count >= right_history.size()) $fatal(1, "pair history capacity");
                right_history[count] = r; count = count + 1;
                expected_left = l;
                for (d = 0; d < T; d = d + 1) begin
                    if (d < count) begin
                        expected_mask[d] = 1;
                        expected_right[d*C +: C] = right_history[count-1-d];
                    end else expected_right[d*C +: C] = '0;
                end
            end
            #1;
            if (left_valid !== expected_left_valid || tap_valid !== expected_mask ||
                left_o !== expected_left || right_o !== expected_right)
                $fatal(1, "PAIRING K=%0d P=%0d T=%0d registered mismatch cycle=%0d", K, P, T, cycles);
            cycles = cycles + 1;
        end
    endtask
    initial begin
        ignored = $value$plusargs("RANDOM_CYCLES=%d", random_cycles);
        ignored = $value$plusargs("SEED=%d", rng);
        right_history = new[random_cycles + 4*T + 128];
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_column_pairing);
        end
        tick(0, 0, 1, '1, '1);
        for (i = 0; i < 2*T+3; i = i + 1) begin
            tick(1, 0, 1, patterned(i, 71), patterned(i, 0));
            if (i%3 == 0) tick(1, 0, 0, '1, '1);
        end
        tick(1, 0, 0, '1, '0); // Hand off the final accepted pair before clear.
        tick(1, 1, 1, '1, '1);
        for (i = 0; i < T+2; i = i + 1) tick(1, 0, 1, patterned(i, 19), patterned(i, 93));
        for (i = 0; i < random_cycles; i = i + 1) begin
            for (row = 0; row < K; row = row + 1) begin
                lv[row*P +: P] = P'(next_random());
                rv[row*P +: P] = P'(next_random());
            end
            tick(next_random()%101 != 0, next_random()%61 == 0, next_random()%4 != 0, lv, rv);
        end
        tick(1, 0, 0, '1, '1);
        tick(1, 1, 1, '1, '1);
        if (consumed == 0) $fatal(1, "No pairs checked at consumer edges");
        $display("PASS pairing K=%0d P=%0d T=%0d cycles=%0d consumed=%0d", K, P, T, cycles, consumed);
        $finish;
    end
    initial begin #100000000; $fatal(1, "pair test timeout"); end
endmodule
`default_nettype wire
