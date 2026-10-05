`timescale 1ns/1ps
`default_nettype none

// Independent fixed-size lesson experiments, NOT a frontend/bank/top wrapper.
// Explicit expected values never come from DUT internal state.
module tb_datapath_examples;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0;
    logic row_en = 0, pair_en = 0, col_en = 0, buf_en = 0, eng_en = 0;
    logic [7:0] pixel = 0;
    logic [23:0] pair_l = 0, pair_r = 0, col_l = 0, col_r = 0, eng_l = 0, eng_r = 0;
    logic [9:0] cost_in = 0;
    logic [2:0] mask_in = 0;
    logic [35:0] costs_in = 0;
    logic [5:0] ids_in = 0;
    wire row_v, row_last, left_v, col_v, buf_v, eng_v, winner_v;
    wire [23:0] row_column, left_column;
    wire [2:0] tap_v;
    wire [71:0] taps;
    wire [9:0] col_cost;
    wire [11:0] buf_sad, eng_sad, winner_sad;
    wire [1:0] winner_d;

    circular_row_buffer #(.K(3), .PIXEL_W(8), .IMG_W(4)) row_dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(row_en),
        .pixel_i(pixel), .valid_o(row_v), .row_last_o(row_last), .column_o(row_column));
    left_column_delay #(.K(3), .PIXEL_W(8)) left_dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(pair_en),
        .column_i(pair_l), .valid_o(left_v), .column_o(left_column));
    right_column_shift #(.K(3), .PIXEL_W(8), .TAPS(3)) shift_dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(pair_en),
        .column_i(pair_r), .tap_valid_o(tap_v), .columns_o(taps));
    column_sad #(.K(3), .PIXEL_W(8)) column_dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(col_en),
        .left_column_i(col_l), .right_column_i(col_r), .valid_o(col_v), .column_sum_o(col_cost));
    column_sum_buffer #(.K(3), .PIXEL_W(8)) buffer_dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(buf_en),
        .column_sum_i(cost_in), .valid_o(buf_v), .sad_o(buf_sad));
    sad_engine #(.K(3), .PIXEL_W(8)) engine_dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(eng_en),
        .left_column_i(eng_l), .right_column_i(eng_r), .valid_o(eng_v), .sad_o(eng_sad));
    comparator_tree #(.LANES(3), .SAD_W(12), .D_W(2)) comparator_dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .lane_valid_i(mask_in),
        .sad_i(costs_in), .disparity_i(ids_in), .valid_o(winner_v),
        .sad_o(winner_sad), .disparity_o(winner_d));

    integer i, j, checked = 0;
    integer samples [0:4];
    integer want_sad [0:4];
    integer want_column [0:6];
    logic [23:0] expected_column;
    task automatic observe();
        @(posedge clk); #1;
    endtask
    task automatic reset_all();
        begin
            @(negedge clk);
            clear_i = 1;
            row_en = 0; pair_en = 0; col_en = 0; buf_en = 0; eng_en = 0; mask_in = 0;
            observe();
            if (row_v !== 0 || row_last !== 0 || row_column !== 0 ||
                left_v !== 0 || left_column !== 0 || tap_v !== 0 || taps !== 0 ||
                col_v !== 0 || col_cost !== 0 || buf_v !== 0 || buf_sad !== 0 ||
                eng_v !== 0 || eng_sad !== 0 || winner_v !== 0 || winner_sad !== 0 || winner_d !== 0)
                $fatal(1, "EXAMPLES reset/clear mismatch");
            @(negedge clk); rst_n = 1; clear_i = 0;
        end
    endtask
    task automatic pair_beat(input bit en, input logic [23:0] l, r,
                             input logic [23:0] want_l,
                             input logic [2:0] want_mask, input logic [71:0] want_taps);
        begin
            @(negedge clk); pair_en = en; pair_l = l; pair_r = r;
            observe();
            if (left_v !== en || left_column !== want_l || tap_v !== want_mask || taps !== want_taps)
                $fatal(1, "EXAMPLES pair got L=%h mask=%b taps=%h", left_column, tap_v, taps);
            $display("PAIR left=%h valid=%b taps=%h mask=%b", left_column, left_v, taps, tap_v);
            checked = checked + 1;
        end
    endtask
    initial begin
        if ($test$plusargs("VCD")) begin
            $dumpfile("waveform.vcd"); $dumpvars(0, tb_datapath_examples);
        end
        reset_all();
        // Three raster rows: the least-significant byte is the oldest row.
        for (i = 0; i < 12; i = i + 1) begin
            @(negedge clk); row_en = 1; pixel = 8'(i + 1);
            observe();
            if (i < 8) begin
                if (row_v !== 0 || row_last !== 0 || row_column !== 0)
                    $fatal(1, "EXAMPLES premature row column");
            end else begin
                expected_column = {8'(i + 1), 8'(i - 3), 8'(i - 7)};
                if (row_v !== 1 || row_last !== (i == 11) || row_column !== expected_column)
                    $fatal(1, "EXAMPLES row position=%0d got=%h expected=%h", i, row_column, expected_column);
                $display("ROW x=%0d column=%h last=%b", i-8, row_column, row_last);
            end
            checked = checked + 1;
        end
        @(negedge clk); row_en = 0; pixel = '1;
        observe();
        if (row_v !== 0 || row_last !== 0 || row_column !== 24'h0c0804)
            $fatal(1, "EXAMPLES row pause");
        checked = checked + 1;

        reset_all();
        pair_beat(1, 24'h131211, 24'h090501, 24'h131211, 3'b001, 72'h000000_000000_090501);
        pair_beat(1, 24'h232221, 24'h0a0602, 24'h232221, 3'b011, 72'h000000_090501_0a0602);
        pair_beat(0, '1, '1, 24'h232221, 3'b000, 72'h000000_090501_0a0602);
        pair_beat(1, 24'h333231, 24'h0b0703, 24'h333231, 3'b111, 72'h090501_0a0602_0b0703);
        pair_beat(0, '0, '0, 24'h333231, 3'b000, 72'h090501_0a0602_0b0703);
        reset_all();
        pair_beat(1, 24'h434241, 24'h0c0804, 24'h434241, 3'b001, 72'h000000_000000_0c0804);

        reset_all();
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk); col_en = (i == 0);
            col_l = {8'd200, 8'd50, 8'd10}; col_r = {8'd100, 8'd30, 8'd20};
            observe();
            if (col_v !== (i == 2) || col_cost !== ((i >= 2) ? 10'd130 : 10'd0))
                $fatal(1, "EXAMPLES column timing edge=%0d got=%b/%0d", i, col_v, col_cost);
            $display("COLUMN edge=%0d valid=%b cost=%0d", i, col_v, col_cost);
            checked = checked + 1;
        end

        reset_all();
        samples[0]=6; samples[1]=15; samples[2]=24; samples[3]=33; samples[4]=0;
        want_sad[0]=0; want_sad[1]=0; want_sad[2]=45; want_sad[3]=72; want_sad[4]=57;
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge clk); buf_en = 1; cost_in = 10'(samples[i]);
            observe();
            if (buf_v !== (i >= 2) || buf_sad !== 12'(want_sad[i]))
                $fatal(1, "EXAMPLES window edge=%0d got=%b/%0d", i, buf_v, buf_sad);
            $display("BUFFER input=%0d valid=%b sad=%0d", samples[i], buf_v, buf_sad);
            checked = checked + 1;
        end
        @(negedge clk); buf_en = 0; cost_in = 10'd765;
        observe();
        if (buf_v !== 0 || buf_sad !== 12'd57) $fatal(1, "EXAMPLES buffer pause");
        checked = checked + 1;

        reset_all();
        want_column[0]=0; want_column[1]=0; want_column[2]=6; want_column[3]=15;
        want_column[4]=24; want_column[5]=33; want_column[6]=33;
        for (i = 0; i < 7; i = i + 1) begin
            @(negedge clk); eng_en = (i < 4); eng_r = 0;
            for (j = 0; j < 3; j = j + 1) eng_l[j*8 +: 8] = 8'(3*i + j + 1);
            observe();
            // Internal signals are checked/printed against explicit expectations,
            // never used to compute the expected full-window SAD.
            if (engine_dut.column_valid !== (i >= 2 && i <= 5) ||
                engine_dut.column_sum !== 10'(want_column[i]) ||
                eng_v !== (i >= 5) || eng_sad !== ((i == 5) ? 12'd45 : ((i == 6) ? 12'd72 : 12'd0)))
                $fatal(1, "EXAMPLES engine edge=%0d got=%b/%0d", i, eng_v, eng_sad);
            $display("ENGINE edge=%0d column_valid=%b column=%0d window_valid=%b sad=%0d",
                     i, engine_dut.column_valid, engine_dut.column_sum, eng_v, eng_sad);
            checked = checked + 1;
        end

        reset_all();
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            mask_in = (i == 0) ? 3'b111 : ((i == 1) ? 3'b110 : 3'b000);
            costs_in = {12'd5, 12'd5, ((i == 0) ? 12'd30 : 12'd0)};
            ids_in = {2'd0, 2'd1, 2'd2};
            observe();
            if (winner_v !== (i == 1 || i == 2) ||
                winner_sad !== ((i == 1 || i == 2) ? 12'd5 : 12'd0) || winner_d !== 0)
                $fatal(1, "EXAMPLES comparator edge=%0d got=%b/%0d/%0d", i, winner_v, winner_sad, winner_d);
            $display("COMPARATOR edge=%0d valid=%b cost=%0d disparity=%0d", i, winner_v, winner_sad, winner_d);
            checked = checked + 1;
        end
        $display("PASS datapath examples: seven modules, %0d checked stimulus edges", checked);
        $finish;
    end
    initial begin #10000; $fatal(1, "EXAMPLES timeout"); end
endmodule
`default_nettype wire
