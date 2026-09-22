`timescale 1ns/1ps
`default_nettype none

// Standalone, self-checking column calculator testbench. No DUT internals used.
module tb_column_sad;
    parameter integer K = 11;
    parameter integer P = 8;
    localparam integer CW = P + $clog2(K);
    localparam integer DELAY = $clog2(K);
    localparam integer BUS_W = K*P;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0, valid_i = 0;
    logic [BUS_W-1:0] left_column_i = '0, right_column_i = '0;
    wire valid_o;
    wire [CW-1:0] column_sum_o;
    column_sad #(.K(K), .PIXEL_W(P)) dut(.*);

    bit expected_valid [0:DELAY];
    longint unsigned expected_sum [0:DELAY];
    longint unsigned held_output = 0;
    integer cycles = 0, outputs = 0, random_cycles = 2000;
    logic [31:0] rng = 32'h13579bdf;
    logic [BUS_W-1:0] a, b;
    integer i, j, phase, ignored;

    function automatic logic [31:0] next_random();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    // Deliberately serial mathematical reference, independent of the tree.
    function automatic longint unsigned direct_column(
        input logic [BUS_W-1:0] left_pixels, right_pixels
    );
        longint unsigned total, l, r;
        integer row;
        begin
            total = 0;
            for (row = 0; row < K; row = row + 1) begin
                l = left_pixels[row*P +: P];
                r = right_pixels[row*P +: P];
                if (l >= r) total = total + l - r;
                else total = total + r - l;
            end
            return total;
        end
    endfunction

    task automatic tick(input bit rn, cl, vi,
        input logic [BUS_W-1:0] left_pixels, right_pixels);
        integer n;
        begin
            @(negedge clk);
            rst_n = rn; clear_i = cl; valid_i = vi;
            left_column_i = left_pixels; right_column_i = right_pixels;
            if (!rn || cl) begin
                for (n = 0; n <= DELAY; n = n + 1) begin
                    expected_valid[n] = 0;
                    expected_sum[n] = 0;
                end
                held_output = 0;
            end else begin
                for (n = DELAY; n > 0; n = n - 1) begin
                    expected_valid[n] = expected_valid[n-1];
                    expected_sum[n] = expected_sum[n-1];
                end
                expected_valid[0] = vi;
                expected_sum[0] = direct_column(left_pixels, right_pixels);
                if (expected_valid[DELAY]) held_output = expected_sum[DELAY];
            end
            @(posedge clk); #1;
            if (valid_o !== expected_valid[DELAY] || column_sum_o !== CW'(held_output))
                $fatal(1, "COLUMN K=%0d P=%0d cycle=%0d got=(%b,%0d) expected=(%b,%0d)",
                    K, P, cycles, valid_o, column_sum_o, expected_valid[DELAY], held_output);
            cycles = cycles + 1;
            if (valid_o) outputs = outputs + 1;
        end
    endtask

    initial begin
        ignored = $value$plusargs("RANDOM_CYCLES=%d", random_cycles);
        ignored = $value$plusargs("SEED=%d", rng);
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_column_sad);
        end
        tick(0, 0, 0, '0, '0);
        tick(0, 1, 1, '1, '0); // reset/clear beat valid
        for (i = 0; i < K+DELAY+5; i = i + 1) tick(1, 0, 1, '0, '0);
        for (i = 0; i < K+DELAY+5; i = i + 1) tick(1, 0, 1, '1, '0);
        for (i = 0; i < K+DELAY+5; i = i + 1) tick(1, 0, 1, '0, '1);
        // Walk an extreme difference across every packed row: catches omissions/padding.
        for (j = 0; j < K; j = j + 1) begin
            a = '0; b = '0; a[j*P +: P] = '1;
            tick(1, 0, 1, a, b);
            tick(1, 0, 0, '1, '1);
            tick(1, 0, 1, b, a);
        end
        // Flush at every pipeline occupancy offset; no stale valid may escape.
        for (phase = 0; phase <= DELAY+1; phase = phase + 1) begin
            tick(1, 1, 0, '0, '0);
            for (i = 0; i <= phase; i = i + 1) tick(1, 0, 1, '1, '0);
            tick(1, 1, 1, '1, '0);
            for (i = 0; i < DELAY+2; i = i + 1) tick(1, 0, 0, '0, '0);
            tick(1, 0, 1, '0, '1);
            tick(0, 0, 1, '1, '0);
        end
        for (i = 0; i < random_cycles; i = i + 1) begin
            for (j = 0; j < K; j = j + 1) begin
                a[j*P +: P] = P'(next_random());
                b[j*P +: P] = P'(next_random());
            end
            tick((next_random()%101 != 0), (next_random()%61 == 0),
                 (next_random()%4 != 0), a, b);
        end
        for (i = 0; i < DELAY+2; i = i + 1) tick(1, 0, 0, '0, '0);
        if (outputs == 0) $fatal(1, "No valid outputs checked");
        $display("PASS column K=%0d P=%0d cycles=%0d outputs=%0d", K, P, cycles, outputs);
        $finish;
    end
    initial begin #100000000; $fatal(1, "column test timeout"); end
endmodule
`default_nettype wire
