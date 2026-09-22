`timescale 1ns/1ps
`default_nettype none

// Standalone self-checking circular history test. Reference shifts K entries and
// resums the ENTIRE window; it does not reproduce the DUT pointer/rolling recurrence.
module tb_column_sum_buffer;
    parameter integer K = 11;
    parameter integer P = 8;
    localparam integer CW = P + $clog2(K);
    localparam integer SW = P + $clog2(K*K);
    localparam longint unsigned MAX_COLUMN = K*((64'd1 << P)-1);
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0, valid_i = 0;
    logic [CW-1:0] column_sum_i = '0;
    wire valid_o;
    wire [SW-1:0] sad_o;
    column_sum_buffer #(.K(K), .PIXEL_W(P)) dut(.*);

    longint unsigned reference_columns [0:K-1];
    longint unsigned held_output = 0;
    bit expected_valid;
    integer filled = 0, cycles = 0, outputs = 0, random_cycles = 2000;
    logic [31:0] rng = 32'h2468ace1;
    integer i, phase, ignored;
    longint unsigned sample_value;

    function automatic logic [31:0] next_random();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    task automatic tick(input bit rn, cl, vi, input longint unsigned sample_data);
        integer n;
        begin
            @(negedge clk);
            rst_n = rn; clear_i = cl; valid_i = vi;
            column_sum_i = CW'(sample_data);
            expected_valid = 0;
            if (!rn || cl) begin
                filled = 0; held_output = 0;
                for (n = 0; n < K; n = n + 1) reference_columns[n] = 0;
            end else if (vi) begin
                for (n = K-1; n > 0; n = n - 1)
                    reference_columns[n] = reference_columns[n-1];
                reference_columns[0] = sample_data;
                if (filled < K) filled = filled + 1;
                if (filled == K) begin
                    expected_valid = 1;
                    held_output = 0;
                    for (n = 0; n < K; n = n + 1)
                        held_output = held_output + reference_columns[n];
                end
            end
            @(posedge clk); #1;
            if (valid_o !== expected_valid || sad_o !== SW'(held_output))
                $fatal(1, "BUFFER K=%0d P=%0d cycle=%0d got=(%b,%0d) expected=(%b,%0d)",
                    K, P, cycles, valid_o, sad_o, expected_valid, held_output);
            cycles = cycles + 1;
            if (valid_o) outputs = outputs + 1;
        end
    endtask

    initial begin
        ignored = $value$plusargs("RANDOM_CYCLES=%d", random_cycles);
        ignored = $value$plusargs("SEED=%d", rng);
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_column_sum_buffer);
        end
        tick(0, 0, 0, 0);
        tick(0, 1, 1, MAX_COLUMN);
        for (i = 0; i < 5*K+7; i = i + 1) tick(1, 0, 1, MAX_COLUMN);
        for (i = 0; i < K+3; i = i + 1) tick(1, 0, 0, 0);
        for (i = 0; i < 4*K+5; i = i + 1) tick(1, 0, 1, 0);
        for (i = 0; i < 5*K+7; i = i + 1) begin
            tick(1, 0, 1, i % (MAX_COLUMN+1));
            if (i%3 == 0) tick(1, 0, 0, MAX_COLUMN);
        end
        // Exercise clears at all warmup counts and after multiple wraps.
        for (phase = 0; phase <= K+2; phase = phase + 1) begin
            tick(1, 1, 0, 0);
            for (i = 0; i < phase; i = i + 1) tick(1, 0, 1, MAX_COLUMN);
            tick(1, 1, 1, MAX_COLUMN); // clear must discard this input
            for (i = 0; i < K+1; i = i + 1) tick(1, 0, 1, 0);
            tick(0, 0, 1, MAX_COLUMN);
        end
        for (i = 0; i < random_cycles; i = i + 1) begin
            sample_value = next_random() % (MAX_COLUMN+1);
            tick((next_random()%101 != 0), (next_random()%61 == 0),
                 (next_random()%4 != 0), sample_value);
        end
        tick(1, 0, 0, 0);
        if (outputs == 0) $fatal(1, "No valid outputs checked");
        $display("PASS buffer K=%0d P=%0d cycles=%0d outputs=%0d", K, P, cycles, outputs);
        $finish;
    end
    initial begin #100000000; $fatal(1, "buffer test timeout"); end
endmodule
`default_nettype wire
