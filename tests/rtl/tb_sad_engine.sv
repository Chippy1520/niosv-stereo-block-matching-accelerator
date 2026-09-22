`timescale 1ns/1ps
`default_nettype none

// End-to-end one-lane test. Reference stores RAW pixel columns and recomputes
// K*K absolute differences per window. No DUT column sums or internal state read.
module tb_sad_engine;
    parameter integer K = 11;
    parameter integer P = 8;
    localparam integer SW = P + $clog2(K*K);
    localparam integer DELAY = $clog2(K) + 1;
    localparam integer BUS_W = K*P;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0, valid_i = 0;
    logic [BUS_W-1:0] left_column_i = '0, right_column_i = '0;
    wire valid_o;
    wire [SW-1:0] sad_o;
    sad_engine #(.K(K), .PIXEL_W(P)) dut(.*);

    // Independent full-window reference in input-coordinate order.
    logic [BUS_W-1:0] left_history [0:K-1], right_history [0:K-1];
    bit expected_valid [0:DELAY];
    longint unsigned expected_sad [0:DELAY];
    longint unsigned held_output = 0;
    integer filled = 0, cycles = 0, outputs = 0, random_cycles = 2000;
    logic [31:0] rng = 32'hcafef00d;
    logic [BUS_W-1:0] a, b;
    integer i, j, row, phase, ignored, before_outputs, expected_row_outputs;

    function automatic logic [31:0] next_random();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    task automatic tick(input bit rn, cl, vi,
        input logic [BUS_W-1:0] left_pixels, right_pixels);
        integer n, vertical;
        longint unsigned total, l, r;
        begin
            @(negedge clk);
            rst_n = rn; clear_i = cl; valid_i = vi;
            left_column_i = left_pixels; right_column_i = right_pixels;
            if (!rn || cl) begin
                filled = 0; held_output = 0;
                for (n = 0; n < K; n = n + 1) begin
                    left_history[n] = '0; right_history[n] = '0;
                end
                for (n = 0; n <= DELAY; n = n + 1) begin
                    expected_valid[n] = 0; expected_sad[n] = 0;
                end
            end else begin
                // Delay only expected *results*, not a model of either DUT module.
                for (n = DELAY; n > 0; n = n - 1) begin
                    expected_valid[n] = expected_valid[n-1];
                    expected_sad[n] = expected_sad[n-1];
                end
                expected_valid[0] = 0;
                expected_sad[0] = 0;
                if (vi) begin
                    for (n = K-1; n > 0; n = n - 1) begin
                        left_history[n] = left_history[n-1];
                        right_history[n] = right_history[n-1];
                    end
                    left_history[0] = left_pixels;
                    right_history[0] = right_pixels;
                    if (filled < K) filled = filled + 1;
                    if (filled == K) begin
                        total = 0;
                        for (n = 0; n < K; n = n + 1)
                            for (vertical = 0; vertical < K; vertical = vertical + 1) begin
                                l = left_history[n][vertical*P +: P];
                                r = right_history[n][vertical*P +: P];
                                if (l >= r) total = total + l - r;
                                else total = total + r - l;
                            end
                        expected_valid[0] = 1;
                        expected_sad[0] = total;
                    end
                end
                if (expected_valid[DELAY]) held_output = expected_sad[DELAY];
            end
            @(posedge clk); #1;
            if (valid_o !== expected_valid[DELAY] || sad_o !== SW'(held_output))
                $fatal(1, "ENGINE K=%0d P=%0d cycle=%0d got=(%b,%0d) expected=(%b,%0d)",
                    K, P, cycles, valid_o, sad_o, expected_valid[DELAY], held_output);
            cycles = cycles + 1;
            if (valid_o) outputs = outputs + 1;
        end
    endtask

    task automatic drain();
        integer n;
        begin
            for (n = 0; n < DELAY; n = n + 1) tick(1, 0, 0, '0, '0);
        end
    endtask

    initial begin
        ignored = $value$plusargs("RANDOM_CYCLES=%d", random_cycles);
        ignored = $value$plusargs("SEED=%d", rng);
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_sad_engine);
        end
        tick(0, 0, 0, '0, '0);
        tick(0, 1, 1, '1, '0);
        // Distinct rows including zero cost, max cost, and nonuniform pixels.
        // Exact drain interval then clear: detects loss of final row windows.
        for (row = 0; row < 4; row = row + 1) begin
            tick(1, 1, 0, '0, '0);
            before_outputs = outputs;
            for (i = 0; i < 3*K+7; i = i + 1) begin
                for (j = 0; j < K; j = j + 1) begin
                    a[j*P +: P] = P'(i*13 + j*7 + row);
                    b[j*P +: P] = P'(i*3 + j*17 + row*11);
                end
                if (row == 0) b = a;
                if (row == 1) begin a = '1; b = '0; end
                if (row == 2) begin a = '0; b = '1; end
                tick(1, 0, 1, a, b);
                if (row == 3 && i%3 == 0) tick(1, 0, 0, '1, '0);
            end
            drain();
            expected_row_outputs = (3*K+7)-K+1;
            if (outputs-before_outputs != expected_row_outputs)
                $fatal(1, "Lost/extra row outputs: got %0d expected %0d",
                    outputs-before_outputs, expected_row_outputs);
        end
        // Short rows cannot produce a window.
        tick(1, 1, 0, '0, '0);
        for (i = 0; i < K-1; i = i + 1) tick(1, 0, 1, '1, '0);
        drain();
        tick(1, 1, 1, '1, '0);
        // Abort at each pipeline offset, both before and after history warmup.
        for (phase = 0; phase <= DELAY+1; phase = phase + 1) begin
            tick(1, 1, 0, '0, '0);
            for (i = 0; i < K+phase; i = i + 1) tick(1, 0, 1, '1, '0);
            tick(1, 1, 1, '1, '0);
            drain();
            for (i = 0; i < K+DELAY+2; i = i + 1) tick(1, 0, 1, '0, '0);
            tick(0, 0, 1, '1, '0);
            drain();
        end
        for (i = 0; i < random_cycles; i = i + 1) begin
            for (j = 0; j < K; j = j + 1) begin
                a[j*P +: P] = P'(next_random());
                b[j*P +: P] = P'(next_random());
            end
            tick((next_random()%101 != 0), (next_random()%61 == 0),
                 (next_random()%4 != 0), a, b);
        end
        drain();
        tick(1, 0, 0, '0, '0);
        if (outputs == 0) $fatal(1, "No valid outputs checked");
        $display("PASS engine K=%0d P=%0d cycles=%0d outputs=%0d", K, P, cycles, outputs);
        $finish;
    end
    initial begin #100000000; $fatal(1, "engine test timeout"); end
endmodule
`default_nettype wire
