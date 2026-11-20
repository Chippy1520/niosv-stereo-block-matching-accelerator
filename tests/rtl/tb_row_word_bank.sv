`timescale 1ns/1ps
`default_nettype none
module tb_row_word_bank;
    // N counts whole words; P is the complete word width, not a pixel width.
    parameter integer N = 160, P = 32;
    localparam integer A = (N <= 1) ? 1 : $clog2(N);
    logic clk = 0, write_i = 0, read_i = 0;
    logic [A-1:0] write_address_i = '0, read_address_i = '0;
    logic [P-1:0] write_data_i = '0;
    wire [P-1:0] read_data_o;
    logic [P-1:0] image [0:N-1];
    logic [P-1:0] consumer;
    logic [31:0] rng = 32'h692f831d;
    integer random_cycles = 2000, cycles = 0, reads = 0, overlaps = 0;
    integer i, wa, ra;
    bit wr, rd;
    logic [P-1:0] data_word;
    string vcd_path;

    always #5 clk = ~clk;
    // A real registered consumer must see the previous read result at this edge.
    always @(posedge clk) consumer <= read_data_o;
    row_word_bank #(.WORD_W(P), .DEPTH(N), .ADDR_W(A)) dut (.*);

    function automatic logic [31:0] next_random(input logic [31:0] value);
        logic [31:0] v;
        begin
            v = value ^ (value << 13);
            v = v ^ (v >> 17);
            next_random = v ^ (v << 5);
        end
    endfunction

    task automatic make_word(output logic [P-1:0] value);
        integer b;
        begin
            for (b = 0; b < P; b = b + 1) begin
                if (b % 32 == 0) rng = next_random(rng);
                value[b] = rng[b % 32];
            end
        end
    endtask

    task automatic tick(input bit writing, input integer write_addr,
                        input logic [P-1:0] value,
                        input bit reading, input integer read_addr);
        logic [P-1:0] held, expected;
        begin
            if ((writing && (write_addr < 0 || write_addr >= N)) ||
                (reading && (read_addr < 0 || read_addr >= N)))
                $fatal(1, "WORD_RAM test scheduled an illegal address");
            if (writing && reading && write_addr == read_addr)
                $fatal(1, "WORD_RAM test scheduled a same-word collision");
            @(negedge clk);
            held = read_data_o;
            expected = reading ? image[read_addr] : held;
            write_i = writing;
            write_address_i = A'(write_addr);
            write_data_i = value;
            read_i = reading;
            read_address_i = A'(read_addr);
            #1;
            if (read_data_o !== held)
                $fatal(1, "WORD_RAM N=%0d P=%0d asynchronous change cycle=%0d", N, P, cycles);
            @(posedge clk);
            // This comparison is deliberately before NBA, not merely a #1 check.
            if (read_data_o !== held)
                $fatal(1, "WORD_RAM N=%0d P=%0d pre-NBA stability cycle=%0d", N, P, cycles);
            #1;
            if (consumer !== held)
                $fatal(1, "WORD_RAM N=%0d P=%0d consumer-edge mismatch cycle=%0d", N, P, cycles);
            if (read_data_o !== expected)
                $fatal(1, "WORD_RAM N=%0d P=%0d rd=%b ra=%0d wa=%0d got=%h expected=%h cycle=%0d",
                       N, P, reading, read_addr, write_addr, read_data_o, expected, cycles);
            // The independent reference array changes only on accepted writes.
            if (writing) image[write_addr] = value;
            if (reading) reads = reads + 1;
            if (writing && reading) overlaps = overlaps + 1;
            cycles = cycles + 1;
        end
    endtask

    initial begin
        if (N < 1 || P < 1) $fatal(1, "WORD_RAM needs positive N and P");
        if ($value$plusargs("RANDOM_CYCLES=%d", random_cycles)) begin end
        if (random_cycles < 0) $fatal(1, "RANDOM_CYCLES must be nonnegative");
        if ($value$plusargs("SEED=%d", rng)) begin end
        if (rng == 0) rng = 32'h692f831d;
        if ($test$plusargs("VCD")) begin
            if (!$value$plusargs("VCD=%s", vcd_path)) vcd_path = "tb_row_word_bank.vcd";
            $dumpfile(vcd_path); $dumpvars(0, tb_row_word_bank);
        end
        // No reset exists: initialize every location through the write port.
        // A disabled, initially unknown read register must hold even here.
        for (i = N - 1; i >= 0; i = i - 1) begin
            make_word(data_word);
            tick(1, i, data_word, 0, (i + 1) % N);
        end
        for (i = 0; i < N; i = i + 1) tick(0, (i + 1) % N, '1, 1, i);
        for (i = N - 1; i >= 0; i = i - 1) begin
            tick(0, i, ~image[i], 0, i); // disabled read: address/data may change
            tick(0, (i + 1) % N, '0, 1, i);
        end
        // Directed independent-address concurrency covers every write address.
        // A depth-one bank cannot legally overlap, but still tests write/hold/read.
        for (i = 0; i < N; i = i + 1) begin
            make_word(data_word);
            tick(1, i, data_word, N > 1, (i + 1) % N);
            tick(0, (i + 1) % N, ~data_word, 1, i);
        end
        for (i = 0; i < random_cycles; i = i + 1) begin
            rng = next_random(rng); wr = rng[0]; rd = rng[3];
            rng = next_random(rng); wa = integer'(rng % N);
            rng = next_random(rng); ra = integer'(rng % N);
            if (wr && rd && wa == ra) begin
                if (N > 1) ra = (ra + 1) % N;
                else wr = 0;
            end
            make_word(data_word);
            tick(wr, wa, data_word, rd, ra);
        end
        for (i = N - 1; i >= 0; i = i - 1) tick(0, (i + 1) % N, '1, 1, i);
        tick(0, 0, '0, 0, N - 1);
        if (N > 1 && overlaps < N) $fatal(1, "WORD_RAM overlap coverage missing");
        $display("PASS WORD_RAM N=%0d P=%0d cycles=%0d reads=%0d overlaps=%0d", N, P, cycles, reads, overlaps);
        $finish;
    end
endmodule
`default_nettype wire
