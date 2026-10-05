`timescale 1ns/1ps
`default_nettype none

module tb_left_column_delay;
    parameter integer K = 11;
    parameter integer P = 8;
    localparam integer C = K * P;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0, valid_i = 0;
    logic [C-1:0] column_i = '0;
    wire valid_o;
    wire [C-1:0] column_o;
    left_column_delay #(.K(K), .PIXEL_W(P)) dut (.*);

    logic expected_valid = 0;
    logic [C-1:0] expected_column = '0, values;
    integer cycles = 0, outputs = 0, random_cycles = 2000;
    integer i, row, ignored;
    logic [31:0] rng = 32'h2468ace1;
    function automatic logic [31:0] next_random();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    task automatic tick(input bit rn, cl, en, input logic [C-1:0] value);
        begin
            @(negedge clk);
            rst_n = rn; clear_i = cl; valid_i = en; column_i = value;
            #1;
            // Inputs must not pass through before the sampling edge.
            if (valid_o !== expected_valid || column_o !== expected_column)
                $fatal(1, "DELAY K=%0d P=%0d changed before edge, cycle=%0d", K, P, cycles);
            if (!rn || cl) begin
                expected_valid = 0;
                expected_column = '0;
            end else begin
                expected_valid = en;
                if (en) expected_column = value;
            end
            @(posedge clk); #1;
            if (valid_o !== expected_valid || column_o !== expected_column)
                $fatal(1, "DELAY K=%0d P=%0d cycle=%0d valid=%b expected=%b column=%h expected=%h",
                       K, P, cycles, valid_o, expected_valid, column_o, expected_column);
            cycles = cycles + 1;
            if (valid_o) outputs = outputs + 1;
        end
    endtask

    initial begin
        ignored = $value$plusargs("RANDOM_CYCLES=%d", random_cycles);
        ignored = $value$plusargs("SEED=%d", rng);
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_left_column_delay);
        end
        tick(0, 0, 1, '1);
        tick(1, 0, 0, '1);
        tick(1, 0, 1, '0);
        tick(1, 0, 1, '1);
        for (row = 0; row < K; row = row + 1) begin
            values = '0;
            values[row*P +: P] = '1;
            tick(1, 0, 1, values);
        end
        repeat (3) tick(1, 0, 0, '0);
        tick(1, 0, 1, '1);
        tick(1, 1, 1, '1);
        tick(1, 0, 0, '1);
        tick(1, 0, 1, '0);
        tick(0, 1, 1, '1);
        tick(1, 0, 1, '1);
        for (i = 0; i < random_cycles; i = i + 1) begin
            for (row = 0; row < K; row = row + 1) values[row*P +: P] = P'(next_random());
            tick(next_random()%101 != 0, next_random()%61 == 0,
                 next_random()%4 != 0, values);
        end
        tick(1, 0, 0, '0);
        tick(1, 1, 1, '1);
        if (outputs == 0) $fatal(1, "No valid delay outputs checked");
        $display("PASS delay K=%0d P=%0d cycles=%0d outputs=%0d", K, P, cycles, outputs);
        $finish;
    end
    initial begin #100000000; $fatal(1, "delay test timeout"); end
endmodule
`default_nettype wire
