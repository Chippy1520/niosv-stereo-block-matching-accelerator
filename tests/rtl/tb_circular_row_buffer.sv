`timescale 1ns/1ps
`default_nettype none

// Flat-image reference. It does not reproduce the ring slot or row memories.
module tb_circular_row_buffer;
    parameter integer K = 11;
    parameter integer P = 8;
    parameter integer W = 8;
    localparam integer MAX_PIX = (1 << 20) - 1;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0, valid_i = 0;
    logic [P-1:0] pixel_i = '0;
    wire valid_o, row_last_o;
    wire [K*P-1:0] column_o;

    circular_row_buffer #(.K(K), .PIXEL_W(P), .IMG_W(W)) dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(valid_i),
        .pixel_i(pixel_i), .valid_o(valid_o), .row_last_o(row_last_o),
        .column_o(column_o)
    );

    logic [P-1:0] image [0:MAX_PIX];
    integer accepted = 0, cycles = 0, outputs = 0, random_cycles = 2000;
    logic [31:0] rng = 32'h13579bdf;
    logic [K*P-1:0] held = '0;
    bit expected_valid, expected_last;
    integer i, ignored, x_ref, y_ref, j, index;

    function automatic logic [31:0] next_random();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    task automatic tick(input bit rn, cl, vi, input logic [P-1:0] pixel);
        begin
            @(negedge clk);
            rst_n = rn; clear_i = cl; valid_i = vi; pixel_i = pixel;
            expected_valid = 0;
            expected_last = 0;
            if (!rn || cl) begin
                accepted = 0;
                held = '0;
            end else if (vi) begin
                if (accepted > MAX_PIX) $fatal(1, "reference image full");
                x_ref = accepted % W;
                y_ref = accepted / W;
                image[accepted] = pixel;
                if (y_ref >= K - 1) begin
                    expected_valid = 1;
                    expected_last = (x_ref == W - 1);
                    held = '0;
                    for (j = 0; j < K; j = j + 1) begin
                        index = (y_ref - (K - 1) + j) * W + x_ref;
                        held[j*P +: P] = image[index];
                    end
                end
                accepted = accepted + 1;
            end
            @(posedge clk); #1;
            if (valid_o !== expected_valid || row_last_o !== expected_last
                    || column_o !== held)
                $fatal(1, "ROW K=%0d P=%0d W=%0d cycle=%0d got=(%b,%b,%h) expected=(%b,%b,%h)",
                    K, P, W, cycles, valid_o, row_last_o, column_o,
                    expected_valid, expected_last, held);
            cycles = cycles + 1;
            if (valid_o) outputs = outputs + 1;
        end
    endtask

    initial begin
        ignored = $value$plusargs("RANDOM_CYCLES=%d", random_cycles);
        ignored = $value$plusargs("SEED=%d", rng);
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_circular_row_buffer);
        end
        tick(0, 0, 0, '0);
        tick(0, 1, 1, {P{1'b1}});
        // More than two windows, with bubbles, so the ring must drop old rows.
        for (i = 0; i < (2*K + 3)*W; i = i + 1) begin
            tick(1, 0, 1, P'(i + 1));
            if (i % 5 == 0) tick(1, 0, 0, {P{1'b1}});
        end
        tick(1, 1, 1, {P{1'b1}}); // clear discards this pixel and restarts warmup
        for (i = 0; i < (K - 1)*W; i = i + 1) tick(1, 0, 1, P'(i + 3));
        tick(1, 0, 0, '0);
        for (i = 0; i < W + 2; i = i + 1) tick(1, 0, 1, {P{1'b1}});
        tick(0, 0, 1, {P{1'b1}});
        for (i = 0; i < random_cycles; i = i + 1)
            tick((next_random() % 101 != 0), (next_random() % 61 == 0),
                 (next_random() % 4 != 0), P'(next_random()));
        tick(1, 0, 0, '0);
        if (outputs == 0) $fatal(1, "No valid row-buffer outputs checked");
        $display("PASS row K=%0d P=%0d W=%0d cycles=%0d outputs=%0d",
            K, P, W, cycles, outputs);
        $finish;
    end
    initial begin #100000000; $fatal(1, "row buffer test timeout"); end
endmodule
`default_nettype wire
