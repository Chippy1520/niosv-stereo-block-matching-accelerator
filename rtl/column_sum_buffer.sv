`timescale 1ns/1ps
`default_nettype none

// One disparity lane. Input: sum of K vertical absolute pixel differences.
// Output: sum of K consecutive input columns. One input per clock, no backpressure.
// clear_i discards all history and takes priority over valid_i; assert between rows.
module column_sum_buffer #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer COL_W = PIXEL_W + $clog2(K),
    parameter integer SAD_W = PIXEL_W + $clog2(K*K)
) (
    input  wire                 clk,
    input  wire                 rst_n,       // synchronous active-low reset
    input  wire                 clear_i,
    input  wire                 valid_i,
    input  wire [COL_W-1:0]     column_sum_i,
    output logic                valid_o,
    output logic [SAD_W-1:0]    sad_o
);
    // Parameters are elaboration-time constants, not CPU registers.
    // Legal input range: 0 .. K * (2**PIXEL_W - 1).
    generate
        if (K == 1) begin : g_single
            always_ff @(posedge clk) begin
                if (!rst_n || clear_i) begin
                    valid_o <= 1'b0;
                    sad_o <= '0;
                end else begin
                    valid_o <= valid_i;
                    if (valid_i) sad_o <= column_sum_i;
                end
            end
        end else begin : g_history
            localparam integer DEPTH = K - 1;
            localparam integer PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
            localparam integer COUNT_W = $clog2(DEPTH + 1);
            logic [COL_W-1:0] history [0:DEPTH-1];
            logic [PTR_W-1:0] wr_ptr;
            logic [COUNT_W-1:0] fill_count;
            logic [SAD_W-1:0] history_sum;
            wire full = (fill_count == DEPTH);
            wire [SAD_W-1:0] new_column = {{(SAD_W-COL_W){1'b0}}, column_sum_i};
            // Uninitialized memory is never used until every slot has been written.
            wire [SAD_W-1:0] old_column = full
                ? {{(SAD_W-COL_W){1'b0}}, history[wr_ptr]} : {SAD_W{1'b0}};

            always_ff @(posedge clk) begin
                if (!rst_n || clear_i) begin
                    wr_ptr <= '0;
                    fill_count <= '0;
                    history_sum <= '0;
                    valid_o <= 1'b0;
                    sad_o <= '0;
                end else begin
                    valid_o <= 1'b0;
                    if (valid_i) begin
                        // Before this edge history_sum contains the previous K-1 columns.
                        if (full) begin
                            sad_o <= history_sum + new_column;
                            valid_o <= 1'b1;
                        end
                        // Evict oldest, insert newest: prepare history for the NEXT input.
                        history_sum <= (history_sum - old_column) + new_column;
                        history[wr_ptr] <= column_sum_i;
                        if (wr_ptr == DEPTH-1) wr_ptr <= '0;
                        else wr_ptr <= wr_ptr + 1'b1;
                        if (!full) fill_count <= fill_count + 1'b1;
                    end
                end
            end
        end
    endgenerate

    // synthesis translate_off
    initial begin
        if (K < 1 || PIXEL_W < 1) $fatal(1, "K and PIXEL_W must be positive");
        if (COL_W < PIXEL_W + $clog2(K)) $fatal(1, "COL_W too small");
        if (SAD_W < PIXEL_W + $clog2(K*K) || SAD_W < COL_W)
            $fatal(1, "SAD_W too small");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
