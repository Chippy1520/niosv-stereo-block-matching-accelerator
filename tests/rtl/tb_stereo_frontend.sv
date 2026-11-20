`timescale 1ns/1ps
`default_nettype none

// Raw-image oracle: no modeled ring banks, lane selector or shifting tap cache.
module tb_stereo_frontend;
    parameter integer K = 11;
    parameter integer P = 8;
    parameter integer W = 8;
    parameter integer T = 32;
    parameter integer S = 1;
    localparam integer BANKS = K + S;
    // Keep full-width simulations bounded while exercising several bank wraps.
    // IMG_H is a bench choice; the production RTL default remains 480.
    localparam integer H = (3*BANKS+5 < 480) ? 3*BANKS+5 : 480;
    localparam integer C = K*P;
    localparam integer WORDS = (W+3)/4;
    localparam integer XW = (W <= 1) ? 1 : $clog2(W);
    localparam integer YW = (H <= 1) ? 1 : $clog2(H);
    localparam integer BW = (BANKS <= 1) ? 1 : $clog2(BANKS);
    localparam integer AW = (WORDS <= 1) ? 1 : $clog2(WORDS);

    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, frame_clear_i = 0, row_clear_i = 0;
    logic left_write_valid_i = 0, right_write_valid_i = 0, read_valid_i = 0;
    logic [BW-1:0] write_bank_i = '0, read_oldest_i = '0;
    logic [AW-1:0] write_word_i = '0;
    logic [4*P-1:0] left_write_data_i = '0, right_write_data_i = '0;
    logic [XW-1:0] read_x_i = '0;
    logic [YW-1:0] read_y_i = '0;
    wire left_valid_o, row_last_o;
    wire [C-1:0] left_column_o;
    wire [T-1:0] right_valid_o;
    wire [T*C-1:0] right_columns_o;
    wire [XW-1:0] x_o;
    wire [YW-1:0] y_o;
    stereo_frontend #(.K(K), .PIXEL_W(P), .IMG_W(W), .IMG_H(H), .TAPS(T), .SPARE_ROWS(S)) dut (
        .clk(clk), .rst_n(rst_n), .frame_clear_i(frame_clear_i), .row_clear_i(row_clear_i),
        .left_write_valid_i(left_write_valid_i), .right_write_valid_i(right_write_valid_i),
        .write_bank_i(write_bank_i), .write_word_i(write_word_i),
        .left_write_data_i(left_write_data_i), .right_write_data_i(right_write_data_i),
        .read_valid_i(read_valid_i), .read_x_i(read_x_i), .read_y_i(read_y_i),
        .read_oldest_i(read_oldest_i), .left_valid_o(left_valid_o),
        .left_column_o(left_column_o), .right_valid_o(right_valid_o),
        .right_columns_o(right_columns_o), .x_o(x_o), .y_o(y_o), .row_last_o(row_last_o)
    );

    logic [P-1:0] left_image [0:H*W-1];
    logic [P-1:0] right_image [0:H*W-1];
    bit left_loaded [0:H*W-1];
    bit right_loaded [0:H*W-1];
    logic [31:0] rng = 32'h6d52a391;
    integer random_cycles = 2000, ignored;
    integer cycles = 0, accepted = 0, consumed = 0, outputs = 0;
    integer left_only = 0, right_only = 0, overlaps = 0, clear_loads = 0;
    integer same_word_overlaps = 0;
    integer i, x, last_y, reload_rows;

    // Exactly one outstanding read expectation. Its complete payload is computed
    // directly from image coordinates at acceptance, not from DUT internal state.
    bit pending_valid = 0, expected_valid = 0, expected_last = 0;
    logic [C-1:0] pending_left = '0, expected_left = '0;
    logic [T*C-1:0] pending_right = '0, expected_right = '0;
    logic [T-1:0] pending_mask = '0, expected_mask = '0;
    integer pending_x = 0, pending_y = 0, expected_x = 0, expected_y = 0;

    function automatic logic [31:0] next_random();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    task automatic new_images;
        integer p;
        begin
            for (p = 0; p < H*W; p = p + 1) begin
                left_image[p] = P'(next_random());
                right_image[p] = P'(next_random());
                left_loaded[p] = 0;
                right_loaded[p] = 0;
            end
        end
    endtask

    task automatic check_outputs(input bit consumer);
        begin
            if (left_valid_o !== expected_valid || right_valid_o !== expected_mask ||
                left_column_o !== expected_left || right_columns_o !== expected_right ||
                x_o !== XW'(expected_x) || y_o !== YW'(expected_y) ||
                row_last_o !== expected_last)
                $fatal(1, "FRONTEND K=%0d P=%0d W=%0d T=%0d consumer=%0d cycle=%0d got v=%b mask=%h xy=%0d,%0d last=%b L=%h R=%h expected v=%b mask=%h xy=%0d,%0d last=%b L=%h R=%h",
                    K, P, W, T, consumer, cycles, left_valid_o, right_valid_o,
                    x_o, y_o, row_last_o, left_column_o, right_columns_o,
                    expected_valid, expected_mask, expected_x, expected_y,
                    expected_last, expected_left, expected_right);
        end
    endtask

    // Inputs are driven away from the active edge. wy is a test-scheduler image
    // row, converted to a physical bank ONLY for stimulus, never for the oracle.
    task automatic tick(input bit rn, fc, rc, rd,
                        input integer rx, ry,
                        input bit wl, wr, input integer wy, ww,
                        input bit poison);
        integer lane, px, j, d, iy, idx;
        begin
            @(negedge clk);
            rst_n = rn; frame_clear_i = fc; row_clear_i = rc;
            read_valid_i = rd; read_x_i = XW'(rx); read_y_i = YW'(ry);
            read_oldest_i = BW'((ry-K+1+BANKS*H)%BANKS);
            left_write_valid_i = wl; right_write_valid_i = wr;
            write_bank_i = BW'(wy%BANKS); write_word_i = AW'(ww);
            for (lane = 0; lane < 4; lane = lane + 1) begin
                px = ww*4+lane;
                if (px < W) begin
                    left_write_data_i[lane*P +: P] = left_image[wy*W+px];
                    right_write_data_i[lane*P +: P] = right_image[wy*W+px];
                end else begin
                    // Deliberately nonzero padding: it must never become a pixel.
                    left_write_data_i[lane*P +: P] = P'('1);
                    right_write_data_i[lane*P +: P] = P'('1);
                end
            end
            if (poison) begin
                left_write_data_i = ~left_write_data_i;
                right_write_data_i = ~right_write_data_i;
            end
            #1;
            if (cycles > 0) check_outputs(0); // No combinational tag/payload leaks.
            @(posedge clk);
            if (cycles > 0) begin
                check_outputs(1); // Values sampled by a clocked downstream consumer.
                // A normal row clear follows the handoff bubble: the final
                // aligned pair is still sampled here BEFORE clear's NBA update.
                if (rn && !fc && expected_valid) consumed = consumed + 1;
            end
            if (!rn || fc || rc) begin
                expected_valid = 0; expected_mask = '0; expected_last = 0;
                expected_left = '0; expected_right = '0;
                expected_x = 0; expected_y = 0;
                pending_valid = 0;
            end else begin
                // Consume the PREVIOUS read before replacing the pending record.
                expected_valid = pending_valid;
                expected_mask = pending_valid ? pending_mask : '0;
                expected_last = pending_valid && (pending_x == W-1);
                if (pending_valid) begin
                    expected_left = pending_left; expected_right = pending_right;
                    expected_x = pending_x; expected_y = pending_y;
                end
                pending_valid = rd;
                if (rd) begin
                    if (rx < 0 || rx >= W || ry < K-1 || ry >= H)
                        $fatal(1, "FRONTEND K=%0d illegal scheduler read x=%0d y=%0d", K, rx, ry);
                    if ((wl || wr) && (wy-ry+K-1+BANKS*H)%BANKS < K)
                        $fatal(1, "FRONTEND K=%0d scheduler active-bank overwrite", K);
                    pending_left = '0; pending_right = '0; pending_mask = '0;
                    pending_x = rx; pending_y = ry;
                    for (j = 0; j < K; j = j + 1) begin
                        iy = ry-K+1+j;
                        idx = iy*W+rx;
                        if (!left_loaded[idx] || !right_loaded[idx])
                            $fatal(1, "FRONTEND K=%0d uninitialized scheduler read row=%0d x=%0d", K, iy, rx);
                        pending_left[j*P +: P] = left_image[idx];
                        for (d = 0; d < T; d = d + 1) begin
                            if (rx >= d) begin
                                pending_mask[d] = 1;
                                pending_right[d*C+j*P +: P] = right_image[iy*W+rx-d];
                            end
                        end
                    end
                    accepted = accepted + 1;
                end
            end
            if (rn && !fc && (wl || wr)) begin
                if (poison) $fatal(1, "FRONTEND K=%0d accepted poison stimulus", K);
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    px = ww*4+lane;
                    if (px < W) begin
                        if (wl) left_loaded[wy*W+px] = 1;
                        if (wr) right_loaded[wy*W+px] = 1;
                    end
                end
                if (wl && !wr) left_only = left_only + 1;
                if (wr && !wl) right_only = right_only + 1;
                if (rd && !rc) begin
                    overlaps = overlaps + 1;
                    if (ww == rx/4) same_word_overlaps = same_word_overlaps + 1;
                end
                if (rc) clear_loads = clear_loads + 1;
            end
            #1;
            check_outputs(0); // Registered pair after the NBA updates.
            if (left_valid_o) outputs = outputs + 1;
            cycles = cycles + 1;
        end
    endtask

    task automatic idle;
        tick(1, 0, 0, 0, 0, K-1, 0, 0, 0, 0, 0);
    endtask

    task automatic load_word(input integer y, w, input bit l, r);
        tick(1, 0, 0, 0, 0, K-1, l, r, y, w, 0);
    endtask

    // Randomize word order and independent L/R arrival order. Already preloaded
    // words already prefetched into a spare bank are skipped. A delayed image
    // finishes here before any read can promote its partially loaded row.
    task automatic load_row(input integer y);
        integer order [0:WORDS-1];
        integer a, b, tmp, w;
        bit need_l, need_r;
        begin
            for (a = 0; a < WORDS; a = a + 1) order[a] = a;
            for (a = WORDS-1; a > 0; a = a - 1) begin
                b = next_random()%(a+1);
                tmp = order[a]; order[a] = order[b]; order[b] = tmp;
            end
            for (a = 0; a < WORDS; a = a + 1) begin
                w = order[a];
                need_l = !left_loaded[y*W+4*w];
                need_r = !right_loaded[y*W+4*w];
                if (next_random()%5 == 0) idle();
                if (need_l && need_r && next_random()%3 != 0) begin
                    if (next_random()%2 == 0) begin
                        load_word(y, w, 1, 0);
                        if (next_random()%2 == 0) idle();
                        load_word(y, w, 0, 1);
                    end else begin
                        load_word(y, w, 0, 1);
                        if (next_random()%2 == 0) idle();
                        load_word(y, w, 1, 0);
                    end
                end else if (need_l || need_r) load_word(y, w, need_l, need_r);
            end
        end
    endtask

    // Prefetch y+1 into a spare bank starting at x=0, while all K active rows
    // remain unchanged. Exercise identical word addresses in different banks.
    // Independent L/R arrivals may finish at different times; no partial promotion.
    task automatic read_row(input integer y, limit, input bit overlap);
        integer xx, old_word;
        bit wl, wr;
        begin
            for (xx = 0; xx < W; xx = xx + 1) begin
                if (next_random()%4 == 0) idle();
                wl = 0; wr = 0; old_word = 0;
                if (overlap && y+1 < limit) begin
                    old_word = xx/4;
                    wl = (xx%4 == 0);
                    wr = (xx%4 == 1 || W == 1);
                end
                tick(1, 0, 0, 1, xx, y, wl, wr,
                     (y+1 < limit) ? y+1 : 0, old_word, 0);
            end
            idle(); // At this edge the FINAL store column reaches alignment.
            // Separate clear: metadata/history only; a new-row load is allowed.
            tick(1, 0, 1, 1, 0, y, y+1 < limit, 0,
                 (y+1 < limit) ? y+1 : 0, WORDS-1, 0);
        end
    endtask

    task automatic run_frame(input integer rows);
        integer y;
        begin
            for (y = 0; y < rows; y = y + 1) begin
                load_row(y);
                // Vertical warmup is EXTERNAL: never ask RAM for missing rows.
                if (y >= K-1) read_row(y, rows, 1);
            end
        end
    endtask

    initial begin
        ignored = $value$plusargs("RANDOM_CYCLES=%d", random_cycles);
        ignored = $value$plusargs("SEED=%d", rng);
        if (rng == 0) rng = 32'h1;
        if (K < 1 || K > H || P < 1 || W < 1 || T < 1 || S < 1 || random_cycles < 0)
            $fatal(1, "FRONTEND K=%0d unsupported bench parameters", K);
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_stereo_frontend);
        end
        new_images();
        tick(0, 0, 0, 1, 0, K-1, 1, 1, 0, 0, 1);
        idle();
        run_frame(H); // Every row and every packed word; several physical wraps.
        last_y = H-1;

        // Last window remains live. Replay it after row clear without RAM reload.
        // Also prove row_clear accepts independent writes and suppresses reads.
        tick(1, 0, 1, 1, 0, last_y, 1, 0, last_y-K, 0, 0);
        read_row(last_y, H, 0);

        // Abort an in-flight column and simultaneous valid read/poison load.
        // The current pending column must never reappear after frame clear.
        tick(1, 0, 0, 1, 0, last_y, 0, 0, 0, 0, 0);
        tick(1, 1, 1, 1, W-1, last_y, 1, 1, last_y, 0, 1);
        idle(); idle();
        new_images(); // Explicitly reload fresh ownership; no stale-frame reads.
        reload_rows = (K+2 < H) ? K+2 : H;
        run_frame(reload_rows);
        last_y = reload_rows-1;

        // A bounded random stress budget: independent input bubbles and complete
        // ordered row replays, including W=1 and T>W (no mature SAD interior).
        x = 0;
        for (i = 0; i < random_cycles; i = i + 1) begin
            if (next_random()%3 == 0) idle();
            else begin
                tick(1, 0, 0, 1, x, last_y, 0, 0, 0, 0, 0);
                x = x + 1;
                if (x == W) begin
                    idle();
                    tick(1, 0, 1, 1, 0, last_y, 0, 0, 0, 0, 0);
                    x = 0;
                end
            end
        end
        idle();
        tick(0, 0, 0, 1, 0, last_y, 1, 1, last_y, 0, 1);
        idle(); idle();
        if (accepted == 0 || consumed == 0 || outputs == 0 ||
            left_only == 0 || right_only == 0 || clear_loads == 0 ||
            overlaps == 0 || same_word_overlaps == 0)
            $fatal(1, "FRONTEND K=%0d missing coverage accepted=%0d consumed=%0d outputs=%0d Lonly=%0d Ronly=%0d overlap=%0d clearloads=%0d",
                K, accepted, consumed, outputs, left_only, right_only, overlaps, clear_loads);
        $display("PASS frontend K=%0d P=%0d W=%0d T=%0d S=%0d H=%0d cycles=%0d reads=%0d outputs=%0d consumed=%0d Lonly=%0d Ronly=%0d overlap=%0d sameword=%0d clearloads=%0d",
            K, P, W, T, S, H, cycles, accepted, outputs, consumed,
            left_only, right_only, overlaps, same_word_overlaps, clear_loads);
        $finish;
    end
    initial begin #1000000000; $fatal(1, "FRONTEND K=%0d timeout", K); end
endmodule
`default_nettype wire
