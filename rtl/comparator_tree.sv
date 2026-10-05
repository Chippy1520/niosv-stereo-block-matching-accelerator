`timescale 1ns/1ps
`default_nettype none

// Select the smallest valid (SAD, disparity) from aligned lanes.
// One candidate beat per clock, no backpressure. Result after LEVELS registered
// reductions (edge t -> edge t+LEVELS-1). The caller aligns coordinates and
// masks image borders; this module does not store or compare coordinate tags.
module comparator_tree #(
    parameter integer LANES = 32,
    parameter integer SAD_W = 15,
    parameter integer D_W = (LANES > 1) ? $clog2(LANES) : 1
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear_i,
    input  wire [LANES-1:0]         lane_valid_i,
    input  wire [LANES*SAD_W-1:0]   sad_i,
    input  wire [LANES*D_W-1:0]     disparity_i,
    output wire                     valid_o,
    output wire [SAD_W-1:0]         sad_o,
    output wire [D_W-1:0]           disparity_o
);
    localparam integer LEVELS = (LANES > 1) ? $clog2(LANES) : 1;
    localparam integer PADDED = 1 << LEVELS;

    wire [SAD_W-1:0] cost [0:LEVELS][0:PADDED-1];
    wire [D_W-1:0] disparity [0:LEVELS][0:PADDED-1];
    wire active [0:LEVELS][0:PADDED-1];

    genvar lane, level, node;
    generate
        for (lane = 0; lane < PADDED; lane = lane + 1) begin : leaf
            if (lane < LANES) begin : real_lane
                assign cost[0][lane] = sad_i[lane*SAD_W +: SAD_W];
                assign disparity[0][lane] = disparity_i[lane*D_W +: D_W];
                assign active[0][lane] = lane_valid_i[lane];
            end else begin : padding
                assign cost[0][lane] = '0;
                assign disparity[0][lane] = '0;
                assign active[0][lane] = 1'b0;
            end
        end
        for (level = 1; level <= LEVELS; level = level + 1) begin : stage
            for (node = 0; node < (PADDED >> level); node = node + 1) begin : pair
                reg [SAD_W-1:0] winning_cost;
                reg [D_W-1:0] winning_disparity;
                reg winning_valid;
                wire choose_right;

                assign choose_right = active[level-1][2*node+1] &&
                    (!active[level-1][2*node] ||
                     cost[level-1][2*node+1] < cost[level-1][2*node] ||
                     (cost[level-1][2*node+1] == cost[level-1][2*node] &&
                      disparity[level-1][2*node+1] < disparity[level-1][2*node]));

                always @(posedge clk) begin
                    if (!rst_n || clear_i) begin
                        winning_cost <= '0;
                        winning_disparity <= '0;
                        winning_valid <= 1'b0;
                    end else begin
                        winning_valid <= active[level-1][2*node] |
                                         active[level-1][2*node+1];
                        winning_cost <= choose_right ? cost[level-1][2*node+1] :
                                                       cost[level-1][2*node];
                        winning_disparity <= choose_right ? disparity[level-1][2*node+1] :
                                                               disparity[level-1][2*node];
                    end
                end
                assign cost[level][node] = winning_cost;
                assign disparity[level][node] = winning_disparity;
                assign active[level][node] = winning_valid;
            end
        end
    endgenerate

    assign valid_o = active[LEVELS][0];
    assign sad_o = valid_o ? cost[LEVELS][0] : '0;
    assign disparity_o = valid_o ? disparity[LEVELS][0] : '0;
endmodule
`default_nettype wire
