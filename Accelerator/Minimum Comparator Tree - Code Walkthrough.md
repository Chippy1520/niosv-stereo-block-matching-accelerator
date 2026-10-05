# Minimum comparator tree — code walkthrough
#implemented

[[Accelerator Architecture]] · [[Minimum Comparator Tree]] · [[Disparity Bank]] · [[Verification Map]]
Source: [comparator_tree.sv](../rtl/comparator_tree.sv) · Bench: [tb_comparator_tree.sv](../tests/rtl/tb_comparator_tree.sv)

## First, the story
At one image coordinate, imagine each disparity lane handing over a card: `(valid, SAD, disparity)`. A knockout tournament pairs cards at every station. An invalid card never beats a valid one. Of two valid cards, the lower SAD wins; equal costs go to the lower disparity. When both cards have the same cost and disparity, the left card stays, so the result is deterministic. Registers between tournament rounds admit a new, aligned set of cards every clock. A whole round of invalid cards becomes an invalid, zero-valued output; the tree neither stores a past winner nor merges different disparity groups.

```text
LANES valid/cost/disparity cards at one (x,y)
  → [pair + register] → [pair + register] → ... → one best card
Padding cards for odd LANES are permanently invalid.
```

The *caller*, not this module, must align engine outputs for the same `(x,y)`, mask right-image borders, carry coordinate tags through the same pipeline, and drain pending results before a row-end clear. No image fetch, shift cache, backpressure, cross-pass merge, or metric-depth conversion is implemented here.

## Complete RTL — exact source snapshot
```systemverilog
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
```

## Code-adjacent reading map

### Parameters, buses and receipt timing
- `LANES` counts physical contenders; `SAD_W` sizes each cost; `D_W` sizes the explicit disparity *ID*. The default is 32 lanes, 15-bit cost and 5-bit ID. These are compile-time widths, not a CPU runtime range.
- Packed lane `i` occupies `sad_i[i*SAD_W +: SAD_W]` and `disparity_i[i*D_W +: D_W]`; `lane_valid_i[i]` says whether it exists at this coordinate. Explicit IDs allow a non-contiguous or offset group (with a wide enough `D_W`), rather than assuming lane index equals disparity.
- One set may arrive each edge. `LEVELS = max(1, ceil(log2(LANES)))` is the number of registered reductions: a set accepted at edge `t` appears just after edge `t + LEVELS - 1`, when no reset/clear intervenes. For 32 lanes that means **five registered levels**, not five extra cycles beyond the accepting edge. There is no ready signal.

### Leaf cards and odd counts
```systemverilog
if (lane < LANES) begin : real_lane
    assign cost[0][lane] = sad_i[lane*SAD_W +: SAD_W];
    assign disparity[0][lane] = disparity_i[lane*D_W +: D_W];
    assign active[0][lane] = lane_valid_i[lane];
end else begin : padding
    assign cost[0][lane] = '0;
    assign disparity[0][lane] = '0;
    assign active[0][lane] = 1'b0;
end
```
- `PADDED` rounds up to the next power of two (and to two for one lane); only the first `LANES` leaves read inputs. Every padded leaf is invalid—even though its numeric cost is zero—so it cannot steal a win from a real maximum-cost card.

### Pair comparison, ID and valid travel together
```systemverilog
assign choose_right = active[level-1][2*node+1] &&
    (!active[level-1][2*node] ||
     cost[level-1][2*node+1] < cost[level-1][2*node] ||
     (cost[level-1][2*node+1] == cost[level-1][2*node] &&
      disparity[level-1][2*node+1] < disparity[level-1][2*node]));
```
- Check right validity *before* its cost; if left is invalid, any valid right wins. With two valid inputs, compare unsigned SADs first and explicit IDs second. The strict `<` leaves the left entry on an exact duplicate.
- The three `winning_*` registers advance together at every clock. Synchronous `!rst_n || clear_i` invalidates **all** stages and discards any simultaneous input. Otherwise `winning_valid` is the OR of both child validity bits, while cost and ID are copied from the chosen child. Invalid beats do not pause the pipeline.
- The final `valid_o` comes from the root; `sad_o` and `disparity_o` are gated to zero whenever no candidate is valid. Downstream logic must still respect `valid_o`; zero is also a legitimate valid cost or disparity.

### Exercise it
`python scripts/run_tests.py --suite comparator` covers N=1, 2, 3, 5, 11, 16, 31 and 32; `--case 32:15 --seed 123 --random-cycles 5000 --vcd` makes a repeatable waveform. The bench computes a serial minimum from the original packed inputs, delays that reference by `LEVELS` registered beats and checks every edge. It walks the zero-cost winner through each physical lane, masks that zero, reverses tied IDs, exercises clear/reset at every stage occupancy, inserts bubbles, and drives randomized duplicate costs/IDs. `scripts/check_test_sensitivity.py` confirms the bench rejects reversed tie order and invalid-lane wins. This remains standalone comparator verification, **not** an integrated 32-lane disparity bank or board result.
