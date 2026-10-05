`timescale 1ns/1ps
`default_nettype none

// Independent serial minimum reference; no DUT internals are inspected.
module tb_comparator_tree;
    parameter integer N = 32;
    parameter integer P = 15;
    localparam integer D = (N > 1) ? $clog2(N) : 1;
    localparam integer LEVELS = (N > 1) ? $clog2(N) : 1;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0;
    logic [N-1:0] lane_valid_i = '0;
    logic [N*P-1:0] sad_i = '0;
    logic [N*D-1:0] disparity_i = '0;
    wire valid_o;
    wire [P-1:0] sad_o;
    wire [D-1:0] disparity_o;
    comparator_tree #(.LANES(N), .SAD_W(P), .D_W(D)) dut (.*);

    bit expected_valid [0:LEVELS-1];
    logic [P-1:0] expected_cost [0:LEVELS-1];
    logic [D-1:0] expected_disparity [0:LEVELS-1];
    integer cycles = 0, outputs = 0, random_cycles = 2000;
    logic [31:0] rng = 32'h13579bdf;
    logic [N-1:0] mask;
    logic [N*P-1:0] costs;
    logic [N*D-1:0] ids;
    integer i, j, phase, ignored;

    function automatic logic [31:0] next_random();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    task automatic tick(input bit rn, cl, input logic [N-1:0] valid_mask,
                        input logic [N*P-1:0] values,
                        input logic [N*D-1:0] disparities);
        bit best_valid;
        logic [P-1:0] best_cost, candidate_cost;
        logic [D-1:0] best_d, candidate_d;
        integer n;
        begin
            @(negedge clk);
            rst_n = rn; clear_i = cl; lane_valid_i = valid_mask;
            sad_i = values; disparity_i = disparities;
            if (!rn || cl) begin
                for (n = 0; n < LEVELS; n = n + 1) begin
                    expected_valid[n] = 0;
                    expected_cost[n] = '0;
                    expected_disparity[n] = '0;
                end
            end else begin
                for (n = LEVELS-1; n > 0; n = n - 1) begin
                    expected_valid[n] = expected_valid[n-1];
                    expected_cost[n] = expected_cost[n-1];
                    expected_disparity[n] = expected_disparity[n-1];
                end
                best_valid = 0; best_cost = '0; best_d = '0;
                for (n = 0; n < N; n = n + 1) begin
                    candidate_cost = values[n*P +: P];
                    candidate_d = disparities[n*D +: D];
                    if (valid_mask[n] && (!best_valid || candidate_cost < best_cost ||
                        (candidate_cost == best_cost && candidate_d < best_d))) begin
                        best_valid = 1;
                        best_cost = candidate_cost;
                        best_d = candidate_d;
                    end
                end
                expected_valid[0] = best_valid;
                expected_cost[0] = best_valid ? best_cost : '0;
                expected_disparity[0] = best_valid ? best_d : '0;
            end
            @(posedge clk); #1;
            if (valid_o !== expected_valid[LEVELS-1] ||
                sad_o !== expected_cost[LEVELS-1] ||
                disparity_o !== expected_disparity[LEVELS-1])
                $fatal(1, "COMPARATOR N=%0d P=%0d cycle=%0d got=(%b,%0d,%0d) expected=(%b,%0d,%0d)",
                       N, P, cycles, valid_o, sad_o, disparity_o,
                       expected_valid[LEVELS-1], expected_cost[LEVELS-1],
                       expected_disparity[LEVELS-1]);
            cycles = cycles + 1;
            if (valid_o) outputs = outputs + 1;
        end
    endtask

    initial begin
        ignored = $value$plusargs("RANDOM_CYCLES=%d", random_cycles);
        ignored = $value$plusargs("SEED=%d", rng);
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_comparator_tree);
        end
        costs = '0; ids = '0;
        tick(0, 0, '1, costs, ids);
        tick(0, 1, '1, costs, ids);
        tick(1, 0, '0, costs, ids); // all invalid: zeroed outputs
        // Walk a unique zero-cost winner through every physical lane.
        for (j = 0; j < N; j = j + 1) begin
            costs = '1; ids = '0; mask = '1;
            for (i = 0; i < N; i = i + 1) ids[i*D +: D] = D'(N-1-i);
            costs[j*P +: P] = '0;
            tick(1, 0, mask, costs, ids);
            mask[j] = 0; // invalid zero must lose against valid maximum cost
            tick(1, 0, mask, costs, ids);
        end
        // All costs equal, IDs run opposite physical order; smaller disparity wins.
        costs = '0; ids = '0;
        for (i = 0; i < N; i = i + 1) ids[i*D +: D] = D'(N-1-i);
        tick(1, 0, '1, costs, ids);
        for (j = 0; j < N; j = j + 1) begin
            mask = '0; mask[j] = 1;
            tick(1, 0, mask, costs, ids);
        end
        // Clear at every occupancy: no stale valid result may emerge afterward.
        for (phase = 0; phase <= LEVELS; phase = phase + 1) begin
            tick(1, 1, '1, costs, ids);
            for (i = 0; i < phase; i = i + 1) tick(1, 0, '1, costs, ids);
            tick(1, 1, '1, costs, ids);
            for (i = 0; i < LEVELS+1; i = i + 1) tick(1, 0, '0, costs, ids);
            tick(1, 0, '1, costs, ids);
            tick(0, 0, '1, costs, ids);
        end
        for (j = 0; j < random_cycles; j = j + 1) begin
            for (i = 0; i < N; i = i + 1) begin
                costs[i*P +: P] = P'(next_random() % 17); // frequent ties
                ids[i*D +: D] = D'(next_random());
                mask[i] = (next_random() % 4 != 0);
            end
            if (j % 13 == 0) mask = '0;
            tick((next_random()%101 != 0), (next_random()%61 == 0), mask, costs, ids);
        end
        for (i = 0; i < LEVELS+1; i = i + 1) tick(1, 0, '0, '0, '0);
        if (outputs == 0) $fatal(1, "No valid outputs checked");
        $display("PASS comparator N=%0d P=%0d cycles=%0d outputs=%0d", N, P, cycles, outputs);
        $finish;
    end
    initial begin #100000000; $fatal(1, "comparator test timeout"); end
endmodule
`default_nettype wire
