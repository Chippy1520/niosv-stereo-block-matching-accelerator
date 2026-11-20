`timescale 1ns/1ps
`default_nettype none
module tb_packed_circular_row_buffer;
    parameter integer K = 11, P = 8, W = 640, S = 1;
    localparam integer BANKS = K + S;
    localparam integer XW = (W <= 1) ? 1 : $clog2(W);
    localparam integer BW = (BANKS <= 1) ? 1 : $clog2(BANKS);
    localparam integer WORDS = (W + 3) / 4;
    localparam integer AW = (WORDS <= 1) ? 1 : $clog2(WORDS);
    // Wide configurations exercise an entire 480-row image. Small ones still
    // advance through more than four complete bank rotations, including K=1.
    localparam integer FRAME_ROWS = (W >= 640 && 480 > 5*BANKS + 9) ? 480 : 5*BANKS + 9;
    localparam logic [3:0] REQUIRED_LANES = (W >= 4) ? 4'b1111 :
                                          (W == 3) ? 4'b0111 :
                                          (W == 2) ? 4'b0011 : 4'b0001;
    logic clk = 0, rst_n = 0, clear_i = 0;
    logic write_valid_i = 0, read_valid_i = 0;
    logic [BW-1:0] write_bank_i = '0, read_oldest_i = '0;
    logic [AW-1:0] write_word_i = '0;
    logic [4*P-1:0] write_data_i = '0;
    logic [XW-1:0] read_x_i = '0;
    wire column_valid_o;
    wire [K*P-1:0] column_o;
    logic consumer_valid;
    logic [K*P-1:0] consumer_column;

    // Flat, logical image data only. No DUT memory peeks, physical bank array,
    // mirrored lane-select network, or FIFO-of-DUT-results serves as an oracle.
    logic [P-1:0] RAW [0:FRAME_ROWS*W-1];
    logic [31:0] rng = 32'h4857ab91;
    logic [K*P-1:0] expected_column = '0;
    bit expected_valid = 0, expectation_known = 0;
    integer first_row = 0;
    // Physical ownership is bookkeeping solely for driving the public inputs.
    // Expected tap j always comes directly from RAW[(first_row+j)*W+x].
    integer oldest_bank = 0;
    integer random_cycles = 1500, cycles = 0, reads = 0, overlaps = 0;
    integer completed_windows = 0, wraps = 0, priority_checks = 0;
    integer adjacent_rotations = 0;
    integer same_word_overlaps = 0, prefetched_rows = 0, loaded_until;
    logic [3:0] lanes_seen = '0;
    integer i, b, x, row_number, next_word, random_x;
    bit do_overlap, random_read;
    logic [P-1:0] pixel_value;
    logic [4*P-1:0] load_value;
    string vcd_path;

    always #5 clk = ~clk;
    always @(posedge clk) begin
        consumer_valid <= column_valid_o;
        consumer_column <= column_o;
    end
    packed_circular_row_buffer #(.K(K), .PIXEL_W(P), .IMG_W(W), .SPARE_ROWS(S),
        .X_W(XW), .BANK_W(BW), .WORD_AW(AW)) dut (.*);

    function automatic logic [31:0] next_random(input logic [31:0] value);
        logic [31:0] v;
        begin
            v = value ^ (value << 13);
            v = v ^ (v >> 17);
            next_random = v ^ (v << 5);
        end
    endfunction

    task automatic make_pixel(output logic [P-1:0] value);
        integer bit_index;
        begin
            for (bit_index = 0; bit_index < P; bit_index = bit_index + 1) begin
                if (bit_index % 32 == 0) rng = next_random(rng);
                value[bit_index] = rng[bit_index % 32];
            end
        end
    endtask

    // Packing is used only to drive writes; the read oracle never unpacks this.
    function automatic logic [4*P-1:0] packed_word(input integer logical_row,
                                                 input integer word_index);
        integer lane, image_x;
        begin
            packed_word = '0;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                image_x = 4*word_index + lane;
                if (image_x < W)
                    packed_word[lane*P +: P] = RAW[logical_row*W + image_x];
                else
                    // Nonzero poison padding must never escape as an image pixel.
                    packed_word[lane*P +: P] = '1;
            end
        end
    endfunction

    task automatic tick(input bit reset_n, input bit clearing,
                        input bit writing, input integer bank_index,
                        input integer word_index, input logic [4*P-1:0] value,
                        input bit reading, input integer image_x,
                        input integer oldest_index);
        logic [K*P-1:0] held_column, next_column;
        logic held_valid;
        bit next_valid;
        integer tap;
        begin
            if (reset_n && !clearing) begin
                if (writing && (bank_index < 0 || bank_index >= BANKS || word_index < 0 || word_index >= WORDS))
                    $fatal(1, "PACKED_ROW test scheduled an invalid write");
                if (reading && (image_x < 0 || image_x >= W || oldest_index < 0 || oldest_index >= BANKS))
                    $fatal(1, "PACKED_ROW test scheduled an invalid read");
                if (writing && reading && (bank_index + BANKS - oldest_index) % BANKS < K)
                    $fatal(1, "PACKED_ROW test scheduled an active-bank overwrite");
            end
            @(negedge clk);
            if (expectation_known && (column_o !== expected_column || column_valid_o !== expected_valid))
                $fatal(1, "PACKED_ROW K=%0d P=%0d W=%0d between-edge mismatch cycle=%0d", K, P, W, cycles);
            held_column = column_o;
            held_valid = column_valid_o;
            rst_n = reset_n; clear_i = clearing;
            write_valid_i = writing;
            write_bank_i = BW'(bank_index); write_word_i = AW'(word_index);
            write_data_i = value;
            read_valid_i = reading;
            read_x_i = XW'(image_x); read_oldest_i = BW'(oldest_index);
            next_column = expected_column;
            next_valid = 0;
            if (!reset_n || clearing) next_column = '0;
            else if (reading) begin
                next_valid = 1;
                for (tap = 0; tap < K; tap = tap + 1)
                    next_column[tap*P +: P] = RAW[(first_row + tap)*W + image_x];
            end
            #1;
            if (column_o !== held_column || column_valid_o !== held_valid)
                $fatal(1, "PACKED_ROW K=%0d P=%0d W=%0d asynchronous output/mask cycle=%0d", K, P, W, cycles);
            @(posedge clk);
            // Pre-NBA stability is the downstream consumer's actual contract.
            if (column_o !== held_column || column_valid_o !== held_valid)
                $fatal(1, "PACKED_ROW K=%0d P=%0d W=%0d pre-NBA mismatch cycle=%0d", K, P, W, cycles);
            #1;
            if (consumer_column !== held_column || consumer_valid !== held_valid)
                $fatal(1, "PACKED_ROW K=%0d P=%0d W=%0d consumer mismatch cycle=%0d", K, P, W, cycles);
            if (column_valid_o !== next_valid || column_o !== next_column)
                $fatal(1, "PACKED_ROW K=%0d P=%0d W=%0d row=%0d x=%0d oldest=%0d rd=%b reset_n=%b clear=%b got_valid=%b expected_valid=%b got=%h expected=%h cycle=%0d",
                       K, P, W, first_row, image_x, oldest_index, reading, reset_n, clearing,
                       column_valid_o, next_valid, column_o, next_column, cycles);
            expected_column = next_column;
            expected_valid = next_valid;
            expectation_known = 1;
            if (reset_n && !clearing && reading) begin
                reads = reads + 1;
                lanes_seen[image_x % 4] = 1;
                if (writing) begin
                    overlaps = overlaps + 1;
                    if (word_index == image_x/4) same_word_overlaps = same_word_overlaps + 1;
                end
            end
            cycles = cycles + 1;
        end
    endtask

    task automatic gap;
        integer idle_x, idle_bank, idle_word;
        begin
            rng = next_random(rng); idle_x = integer'(rng % W);
            rng = next_random(rng); idle_bank = integer'(rng % BANKS);
            rng = next_random(rng); idle_word = integer'(rng % WORDS);
            // Change lane/oldest/data while disabled; payload must hold and valid
            // must fall. No live write-data bypass is permitted even for K=1.
            tick(1, 0, 0, idle_bank, idle_word, '1, 0, idle_x, idle_bank);
        end
    endtask

    task automatic load_initial_window(input bit shuffled);
        integer row_order [0:K-1];
        integer word_order [0:WORDS-1];
        integer r, w, swap_at, temp, logical_offset, physical;
        begin
            // The second preload uses independent Fisher-Yates row/word orders;
            // neither expected reads nor image initialization follows these orders.
            for (r = 0; r < K; r = r + 1) row_order[r] = K - 1 - r;
            if (shuffled) begin
                for (r = K - 1; r > 0; r = r - 1) begin
                    rng = next_random(rng); swap_at = integer'(rng % (r + 1));
                    temp = row_order[r]; row_order[r] = row_order[swap_at]; row_order[swap_at] = temp;
                end
            end
            for (r = 0; r < K; r = r + 1) begin
                logical_offset = row_order[r];
                physical = (oldest_bank + logical_offset) % BANKS;
                for (w = 0; w < WORDS; w = w + 1) word_order[w] = WORDS - 1 - w;
                if (shuffled) begin
                    for (w = WORDS - 1; w > 0; w = w - 1) begin
                        rng = next_random(rng); swap_at = integer'(rng % (w + 1));
                        temp = word_order[w]; word_order[w] = word_order[swap_at]; word_order[swap_at] = temp;
                    end
                end
                for (w = 0; w < WORDS; w = w + 1) begin
                    rng = next_random(rng);
                    if (rng % 7 == 0) gap();
                    tick(1, 0, 1, physical, word_order[w],
                         packed_word(first_row + logical_offset, word_order[w]),
                         0, W - 1, (oldest_bank + 1) % BANKS);
                end
            end
            // Caller now owns K fully loaded rows. No partial-preload read exists.
        end
    endtask

    task automatic scan_retained_window;
        integer scan_x;
        begin
            for (scan_x = W - 1; scan_x >= 0; scan_x = scan_x - 1)
                tick(1, 0, 0, (oldest_bank + 1) % BANKS, 0, '1, 1, scan_x, oldest_bank);
            gap(); gap();
        end
    endtask

    // Store-port timing only: the frontend still drains/clears between rows.
    // Preload all spares, then change oldest on consecutive accepted edges,
    // crossing the physical ring in both directions with no intervening bubble.
    task automatic check_adjacent_rotations;
        integer r, w, step, physical;
        begin
            for (r = K; r < BANKS; r = r + 1) begin
                physical = (oldest_bank + r) % BANKS;
                for (w = 0; w < WORDS; w = w + 1)
                    tick(1, 0, 1, physical, w, packed_word(r, w), 0, 0, oldest_bank);
            end
            for (step = 0; step <= 2*S; step = step + 1) begin
                first_row = (step <= S) ? step : 2*S-step;
                oldest_bank = (BANKS-1 + first_row) % BANKS;
                tick(1, 0, 0, 0, 0, '0, 1, (step%2 == 0) ? 0 : W-1, oldest_bank);
                if (step > 0) begin
                    if (consumer_valid !== 1'b1)
                        $fatal(1, "PACKED_ROW bank rotation was not back-to-back");
                    adjacent_rotations = adjacent_rotations + 1;
                end
            end
            gap();
        end
    endtask

    task automatic check_priority(input bit use_reset, input bit also_clear);
        integer target_word;
        logic [4*P-1:0] poison;
        begin
            target_word = WORDS - 1;
            poison = ~packed_word(first_row, target_word);
            // First make visibility nonzero/valid, then abort a simultaneous read
            // and poisoned load. Same-word commands are safe because BOTH must
            // be suppressed by synchronous reset/clear priority.
            tick(1, 0, 0, oldest_bank, 0, '1, 1, W - 1, oldest_bank);
            tick(!use_reset, !use_reset || also_clear, 1, oldest_bank,
                 target_word, poison, 1, W - 1, oldest_bank);
            gap(); gap();
            // Explicit caller revalidation: every old location remains known and
            // no accepted write occurred, so reclaim the same logical window.
            // This tests retention, NOT autonomous DUT ownership after a clear.
            scan_retained_window();
            priority_checks = priority_checks + 1;
        end
    endtask

    initial begin
        if (K < 1 || P < 1 || W < 1 || S < 1) $fatal(1, "PACKED_ROW needs positive K, P, W, S");
        if ($value$plusargs("RANDOM_CYCLES=%d", random_cycles)) begin end
        if (random_cycles < 0) $fatal(1, "RANDOM_CYCLES must be nonnegative");
        if ($value$plusargs("SEED=%d", rng)) begin end
        if (rng == 0) rng = 32'h4857ab91;
        if ($test$plusargs("VCD")) begin
            if (!$value$plusargs("VCD=%s", vcd_path)) vcd_path = "tb_packed_circular_row_buffer.vcd";
            $dumpfile(vcd_path); $dumpvars(0, tb_packed_circular_row_buffer);
        end
        for (i = 0; i < FRAME_ROWS*W; i = i + 1) begin
            make_pixel(pixel_value);
            RAW[i] = pixel_value;
        end
        tick(0, 0, 1, 0, 0, '1, 1, 0, 0);
        gap();
        first_row = 0; oldest_bank = BANKS - 1;
        load_initial_window(0);
        // Exhaust every x including 0, 3/4 crossings and the partial final word.
        for (x = 0; x < W; x = x + 1)
            tick(1, 0, 0, 0, 0, '1, 1, x, oldest_bank);
        scan_retained_window();
        check_priority(0, 0); // clear alone suppresses read AND poisoned write
        check_priority(1, 0); // synchronous active-low reset alone
        check_priority(1, 1); // reset and clear together, with both commands
        check_adjacent_rotations();

        // New caller ownership epoch, different physical permutation/preload order.
        tick(1, 1, 0, 0, 0, '0, 0, 0, 0);
        first_row = 0; oldest_bank = BANKS / 2;
        load_initial_window(1);
        for (i = 0; i < random_cycles; i = i + 1) begin
            rng = next_random(rng); random_x = integer'(rng % W);
            rng = next_random(rng); random_read = (rng % 5 != 0);
            tick(1, 0, 0, integer'(rng % BANKS), integer'(rng % WORDS),
                 (4*P)'(rng), random_read, random_x, oldest_bank);
        end

        // Fill every available spare with complete future rows, never modify any
        // active row. Same-word-address reads/writes in DIFFERENT banks are legal.
        // Re-read the entire current window after loading to prove it is intact.
        loaded_until = K - 1;
        for (row_number = K - 1; row_number < FRAME_ROWS; row_number = row_number + 1) begin
            next_word = 0;
            for (x = 0; x < W; x = x + 1) begin
                rng = next_random(rng);
                if (rng % 11 == 0) gap();
                do_overlap = (loaded_until + 1 < FRAME_ROWS && loaded_until + 1 < first_row + BANKS);
                if (do_overlap) load_value = packed_word(loaded_until + 1, next_word);
                else load_value = '1;
                b = (oldest_bank + loaded_until + 1 - first_row) % BANKS;
                tick(1, 0, do_overlap, b, next_word,
                     load_value, 1, x, oldest_bank);
                if (do_overlap) begin
                    next_word = next_word + 1;
                    if (next_word == WORDS) begin
                        loaded_until = loaded_until + 1;
                        prefetched_rows = prefetched_rows + 1;
                        next_word = 0;
                    end
                end
            end
            completed_windows = completed_windows + 1;
            gap();
            scan_retained_window();
            // Narrow images/multiple spares can exhaust scan cycles before every
            // spare is full. Finish loading while paused; never expose partial rows.
            while (loaded_until + 1 < FRAME_ROWS && loaded_until + 1 < first_row + BANKS) begin
                b = (oldest_bank + loaded_until + 1 - first_row) % BANKS;
                tick(1, 0, 1, b, next_word, packed_word(loaded_until + 1, next_word),
                     0, 0, oldest_bank);
                next_word = next_word + 1;
                if (next_word == WORDS) begin
                    loaded_until = loaded_until + 1;
                    prefetched_rows = prefetched_rows + 1;
                    next_word = 0;
                end
            end
            if (row_number + 1 < FRAME_ROWS) begin
                if (loaded_until < row_number + 1) $fatal(1, "PACKED_ROW premature bank swap");
                first_row = first_row + 1;
                if (oldest_bank == BANKS - 1) wraps = wraps + 1;
                oldest_bank = (oldest_bank + 1) % BANKS;
            end
        end
        // Revisit boundaries/random x after every future row is completely loaded.
        scan_retained_window();
        check_priority(0, 0);
        tick(1, 0, 0, 0, 0, '0, 1, 0, oldest_bank);
        tick(1, 0, 0, 0, 0, '1, 1, W - 1, oldest_bank);
        gap(); gap();
        if (lanes_seen !== REQUIRED_LANES || wraps < 4 || priority_checks != 4)
            $fatal(1, "PACKED_ROW insufficient coverage lanes=%b wraps=%0d priority=%0d", lanes_seen, wraps, priority_checks);
        if (overlaps == 0 || same_word_overlaps == 0 || prefetched_rows != FRAME_ROWS-K)
            $fatal(1, "PACKED_ROW missing spare prefetch coverage overlap=%0d sameword=%0d rows=%0d",
                   overlaps, same_word_overlaps, prefetched_rows);
        if (completed_windows != FRAME_ROWS - K + 1) $fatal(1, "PACKED_ROW missing image windows");
        if (adjacent_rotations != 2*S) $fatal(1, "PACKED_ROW missing adjacent bank rotations");
        $display("PASS PACKED_ROW K=%0d P=%0d W=%0d S=%0d cycles=%0d reads=%0d overlaps=%0d sameword=%0d prefetched=%0d wraps=%0d frame_rows=%0d windows=%0d lanes=%b priority=%0d adjacent_rotations=%0d",
                 K, P, W, S, cycles, reads, overlaps, same_word_overlaps, prefetched_rows, wraps,
                 FRAME_ROWS, completed_windows, lanes_seen, priority_checks, adjacent_rotations);
        $finish;
    end
endmodule
`default_nettype wire
