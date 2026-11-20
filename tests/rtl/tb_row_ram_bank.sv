`timescale 1ns/1ps
`default_nettype none
module tb_row_ram_bank;
    parameter integer N = 640, P = 8;
    localparam integer A = (N <= 1) ? 1 : $clog2(N);
    logic clk = 0, enable_i = 0, write_i = 0;
    logic [A-1:0] address_i = '0;
    logic [P-1:0] pixel_i = '0;
    wire [P-1:0] pixel_o;
    logic [P-1:0] image [0:N-1];
    logic [31:0] rng = 32'h13579bdf;
    integer cycles = 0, reads = 0, random_cycles = 2000;
    integer i, address;
    bit en, wr;
    always #5 clk = ~clk;
    row_ram_bank #(.PIXEL_W(P), .DEPTH(N)) dut (.*);

    task automatic tick(input bit enabled, input bit writing, input integer addr,
                        input logic [P-1:0] value);
        logic [P-1:0] held;
        begin
            @(negedge clk);
            held = pixel_o;
            enable_i = enabled;
            write_i = writing;
            address_i = A'(addr);
            pixel_i = value;
            #1;
            if (pixel_o !== held)
                $fatal(1, "RAM N=%0d P=%0d asynchronous output at cycle=%0d", N, P, cycles);
            @(posedge clk); #1;
            if (!enabled && pixel_o !== held)
                $fatal(1, "RAM N=%0d P=%0d bubble changed output cycle=%0d", N, P, cycles);
            if (enabled && !writing) begin
                if (pixel_o !== image[addr])
                    $fatal(1, "RAM N=%0d P=%0d read addr=%0d got=%h expected=%h cycle=%0d",
                           N, P, addr, pixel_o, image[addr], cycles);
                reads = reads + 1;
            end
            // A write-edge read value is outside the bank contract; do not assume old/new data.
            if (enabled && writing) image[addr] = value;
            cycles = cycles + 1;
        end
    endtask

    function automatic logic [31:0] next_random(input logic [31:0] value);
        logic [31:0] v;
        begin
            v = value ^ (value << 13);
            v = v ^ (v >> 17);
            next_random = v ^ (v << 5);
        end
    endfunction

    initial begin
        if ($value$plusargs("RANDOM_CYCLES=%d", random_cycles)) begin end
        if ($value$plusargs("SEED=%d", rng)) begin end
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_row_ram_bank);
        end
        // Initialize through the public write port, not hierarchical memory access.
        for (i = 0; i < N; i = i + 1) begin
            rng = next_random(rng);
            tick(1, 1, i, P'(rng));
        end
        for (i = 0; i < N; i = i + 1) tick(1, 0, i, ~image[i]);
        for (i = N - 1; i >= 0; i = i - 1) begin
            tick(0, 1, i, ~image[i]);
            tick(1, 0, i, '0);
        end
        for (i = 0; i < random_cycles; i = i + 1) begin
            rng = next_random(rng); en = (rng % 5 != 0);
            rng = next_random(rng); wr = rng[0];
            rng = next_random(rng); address = integer'(rng % N);
            rng = next_random(rng);
            tick(en, wr, address, P'(rng));
        end
        for (i = 0; i < N; i = i + 1) tick(1, 0, i, '0);
        $display("PASS RAM N=%0d P=%0d cycles=%0d reads=%0d", N, P, cycles, reads);
        $finish;
    end
endmodule
`default_nettype wire
