`timescale 1ns/1ps
`default_nettype none

// Append-only accepted-column log: reference indexes history, never shifts it.
module tb_right_column_shift;
    parameter integer K = 11;
    parameter integer P = 8;
    parameter integer T = 32;
    localparam integer C = K * P;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0, valid_i = 0;
    logic [C-1:0] column_i = '0;
    wire [T-1:0] tap_valid_o;
    wire [T*C-1:0] columns_o;
    right_column_shift #(.K(K), .PIXEL_W(P), .TAPS(T)) dut (.*);

    logic [C-1:0] accepted[];
    logic [T*C-1:0] expected_columns = '0;
    logic [T-1:0] expected_valid;
    logic [C-1:0] values;
    integer count = 0, cycles = 0, outputs = 0, random_cycles = 2000;
    integer i, j, depth, ignored;
    logic [31:0] rng = 32'h13579bdf;

    function automatic logic [31:0] next_random();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    function automatic logic [C-1:0] patterned(input integer x);
        integer row;
        for (row = 0; row < K; row = row + 1)
            patterned[row*P +: P] = P'(x*(K+1) + row + (x >> 1));
    endfunction

    task automatic tick(input bit rn, cl, en, input logic [C-1:0] value);
        integer tap;
        begin
            @(negedge clk);
            rst_n = rn; clear_i = cl; valid_i = en; column_i = value;
            expected_valid = '0;
            if (!rn || cl) begin
                count = 0;
                expected_columns = '0;
            end else if (en) begin
                if (count >= accepted.size()) $fatal(1, "reference history capacity");
                accepted[count] = value;
                count = count + 1;
                for (tap = 0; tap < T; tap = tap + 1) begin
                    if (tap < count) begin
                        expected_valid[tap] = 1;
                        expected_columns[tap*C +: C] = accepted[count-1-tap];
                    end else expected_columns[tap*C +: C] = '0;
                end
            end // A bubble preserves the previous column bus, but not its valid mask.
            @(posedge clk); #1;
            if (tap_valid_o !== expected_valid || columns_o !== expected_columns)
                $fatal(1, "SHIFT K=%0d P=%0d T=%0d cycle=%0d valid=%h expected=%h columns=%h expected=%h",
                       K, P, T, cycles, tap_valid_o, expected_valid, columns_o, expected_columns);
            cycles = cycles + 1;
            if (tap_valid_o[0]) outputs = outputs + 1;
        end
    endtask

    initial begin
        ignored = $value$plusargs("RANDOM_CYCLES=%d", random_cycles);
        ignored = $value$plusargs("SEED=%d", rng);
        accepted = new[random_cycles + 4*T + 128];
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_right_column_shift);
        end
        tick(0, 0, 1, '1);
        tick(1, 0, 0, '1);
        // Warmup, sustained full history, and pauses with changing input data.
        for (i = 0; i < T+3; i = i + 1) tick(1, 0, 1, patterned(i));
        for (i = 0; i < 3; i = i + 1) tick(1, 0, 0, patterned(100+i));
        for (i = 0; i < T+3; i = i + 1) tick(1, 0, 1, patterned(200+i));
        // Clear at every warmup depth, including full history; valid cannot win clear.
        for (depth = 0; depth <= T; depth = depth + 1) begin
            tick(1, 1, 1, '1);
            for (i = 0; i < depth; i = i + 1) tick(1, 0, 1, patterned(i));
            tick(1, 1, 1, '1);
            tick(1, 0, 0, '1);
            tick(1, 0, 1, patterned(500));
        end
        tick(0, 1, 1, '1);
        tick(1, 0, 1, '0);
        for (i = 0; i < T+1; i = i + 1) tick(1, 0, 1, '1);
        for (i = 0; i < random_cycles; i = i + 1) begin
            for (j = 0; j < K; j = j + 1) values[j*P +: P] = P'(next_random());
            tick(next_random()%101 != 0, next_random()%61 == 0,
                 next_random()%4 != 0, values);
        end
        tick(1, 0, 0, '1);
        tick(1, 1, 1, '1);
        if (outputs == 0) $fatal(1, "No accepted outputs checked");
        $display("PASS shift K=%0d P=%0d T=%0d cycles=%0d outputs=%0d", K, P, T, cycles, outputs);
        $finish;
    end
    initial begin #100000000; $fatal(1, "shift test timeout"); end
endmodule
`default_nettype wire
