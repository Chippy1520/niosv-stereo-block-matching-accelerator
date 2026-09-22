`timescale 1ns/1ps
`default_nettype none

// One disparity's vertical column cost. Row j occupies [j*PIXEL_W +: PIXEL_W].
// One abs-difference register stage, then ceil(log2(K)) registered add levels.
// Input sampled at edge t -> output valid after edge t+$clog2(K).
// No backpressure: bubbles move through the pipeline, not a global stall.
// rst_n is synchronous active-low; clear_i discards ALL in-flight columns.
module column_sad #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer COL_W = PIXEL_W + $clog2(K)
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       clear_i,
    input  wire                       valid_i,
    input  wire [K*PIXEL_W-1:0]       left_column_i,
    input  wire [K*PIXEL_W-1:0]       right_column_i,
    output wire                       valid_o,
    output wire [COL_W-1:0]           column_sum_o
);
    localparam integer LEVELS = $clog2(K);
    localparam integer LEAVES = 2**LEVELS;
    logic [LEVELS:0] valid_pipe;
    // Only active nodes in each level are driven/read; unused entries synthesize away.
    wire [COL_W-1:0] tree [0:LEVELS][0:LEAVES-1];

    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) valid_pipe[0] <= 1'b0;
        else valid_pipe[0] <= valid_i;
    end

    // Separate declarations support the Quartus Prime Lite 22.1 parser.
    genvar j, level, node;
    generate
        for (j = 0; j < LEAVES; j = j + 1) begin : g_leaf
            if (j < K) begin : g_pixel
                wire [PIXEL_W-1:0] left_pixel = left_column_i[j*PIXEL_W +: PIXEL_W];
                wire [PIXEL_W-1:0] right_pixel = right_column_i[j*PIXEL_W +: PIXEL_W];
                wire [PIXEL_W-1:0] difference = (left_pixel >= right_pixel)
                    ? left_pixel - right_pixel : right_pixel - left_pixel;
                logic [COL_W-1:0] difference_reg;
                always_ff @(posedge clk) begin
                    if (!rst_n || clear_i) difference_reg <= '0;
                    else if (valid_i)
                        difference_reg <= {{(COL_W-PIXEL_W){1'b0}}, difference};
                end
                assign tree[0][j] = difference_reg;
            end else begin : g_padding
                assign tree[0][j] = '0;
            end
        end
        for (level = 1; level <= LEVELS; level = level + 1) begin : g_level
            always_ff @(posedge clk) begin
                if (!rst_n || clear_i) valid_pipe[level] <= 1'b0;
                else valid_pipe[level] <= valid_pipe[level-1];
            end
            for (node = 0; node < (LEAVES >> level); node = node + 1) begin : g_add
                logic [COL_W-1:0] sum_reg;
                always_ff @(posedge clk) begin
                    if (!rst_n || clear_i) sum_reg <= '0;
                    else if (valid_pipe[level-1])
                        sum_reg <= tree[level-1][2*node] + tree[level-1][2*node+1];
                end
                assign tree[level][node] = sum_reg;
            end
        end
    endgenerate

    assign valid_o = valid_pipe[LEVELS];
    assign column_sum_o = tree[LEVELS][0];

    // synthesis translate_off
    initial begin
        if (K < 1 || PIXEL_W < 1) $fatal(1, "K and PIXEL_W must be positive");
        if (COL_W < PIXEL_W + $clog2(K)) $fatal(1, "COL_W too small");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
