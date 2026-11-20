# SAD Search Backend

Parent: [[Stereo SAD Datapath]] · Frontend: [[Stereo Frontend]]
Children: [[Single SAD Engine]] · [[Minimum Comparator Tree]]
Verification: [[Verification]] · [[Verification Map]] · [[Testbench Guide]]

Source: [rtl/sad_search_backend.sv](../rtl/sad_search_backend.sv). Contract: [accelerator datapath specification](../docs/accelerator-datapath-spec.md). Standalone bench: [tb_sad_search_backend.sv](../tests/rtl/tb_sad_search_backend.sv).

## Purpose — turn aligned columns into one full-search answer

The frontend supplies one left vertical column and a bank of right vertical columns for the **same left-image coordinate**. Lane `d` receives the right column at `x-d`. This backend gives each disparity its own [[Single SAD Engine]], waits until every lane has a complete square window for that coordinate, and sends those costs to the [[Minimum Comparator Tree]]. It returns the winning unsigned SAD, its disparity, and the matching coordinate/end-of-row tags. Ties select the lower disparity through the comparator's existing rule.

**Why this module is needed:** one engine can measure only one fixed alignment; the comparator alone cannot build windows, identify the common image interior, or align coordinate tags. This boundary combines those responsibilities without adding a scheduler, replay buffer, FIFO, or forwarding-only wrapper. `LANES` is the entire compile-time search range, disparities `0..LANES-1`; a smaller build searches fewer disparities, not the same search by time multiplexing.

```text
Stereo Frontend: left column + lane-d right column R[x-d] + tags
    -> parallel Single SAD Engines (each owns its horizontal history)
    -> common-interior AND every-engine-valid qualification
    -> Minimum Comparator Tree
    -> winning SAD/disparity + edge-delayed x/y/row_last
```

## Complete source

The first SystemVerilog block below is the full, unannotated source snapshot. Source line numbers in the subsequent table refer to the RTL file, not this note.

```systemverilog
`timescale 1ns/1ps
`default_nettype none

// Fixed full-search backend: lane d receives R[x-d]. No scheduling/backpressure.
// Prefix lane warmup is legal; missing spatial columns within a row are not.
// Input edge t -> winner after t+$clog2(K)+1+max(1,$clog2(LANES)).
module sad_search_backend #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer LANES = 32,
    parameter integer IMG_W = 640,
    parameter integer IMG_H = 480,
    parameter integer SAD_W = PIXEL_W + $clog2(K*K),
    parameter integer D_W = (LANES <= 1) ? 1 : $clog2(LANES),
    parameter integer X_W = (IMG_W <= 1) ? 1 : $clog2(IMG_W),
    parameter integer Y_W = (IMG_H <= 1) ? 1 : $clog2(IMG_H)
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          clear_i,
    input  wire                          valid_i,
    input  wire [K*PIXEL_W-1:0]          left_column_i,
    input  wire [LANES*K*PIXEL_W-1:0]    right_columns_i,
    input  wire [LANES-1:0]             right_valid_i,
    input  wire [X_W-1:0]               x_i,
    input  wire [Y_W-1:0]               y_i,
    input  wire                          row_last_i,
    output wire                          valid_o,
    output wire [SAD_W-1:0]             sad_o,
    output wire [D_W-1:0]               disparity_o,
    output wire [X_W-1:0]               x_o,
    output wire [Y_W-1:0]               y_o,
    output wire                          row_last_o
);
    localparam integer ENGINE_DELAY = $clog2(K)+1;
    localparam integer REDUCE_STAGES = (LANES <= 1) ? 1 : $clog2(LANES);
    localparam integer DELAY = ENGINE_DELAY + REDUCE_STAGES;
    localparam integer COL_BITS = K * PIXEL_W;
    wire [LANES-1:0] lane_valid;
    wire [LANES*SAD_W-1:0] lane_sad;
    wire [LANES*D_W-1:0] lane_disparity;
    logic common_valid [0:DELAY];
    logic [X_W-1:0] tag_x [0:DELAY];
    logic [Y_W-1:0] tag_y [0:DELAY];
    logic tag_last [0:DELAY];
    integer i;

    // Engines receive early columns; masking before warmup would lose history.
    genvar d;
    generate
        for (d = 0; d < LANES; d = d + 1) begin : g_lane
            sad_engine #(.K(K), .PIXEL_W(PIXEL_W), .SAD_W(SAD_W)) engine (
                .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
                .valid_i(valid_i && right_valid_i[d]),
                .left_column_i(left_column_i),
                .right_column_i(right_columns_i[d*COL_BITS +: COL_BITS]),
                .valid_o(lane_valid[d]), .sad_o(lane_sad[d*SAD_W +: SAD_W])
            );
            assign lane_disparity[d*D_W +: D_W] = D_W'(d);
        end
    endgenerate

    // Index zero captures this edge; every later index shifts even on bubbles.
    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            for (i = 0; i <= DELAY; i = i + 1) begin
                common_valid[i] <= 1'b0;
                tag_x[i] <= '0;
                tag_y[i] <= '0;
                tag_last[i] <= 1'b0;
            end
        end else begin
            // Do not narrow the thresholds: an impossible interior must stay empty.
            common_valid[0] <= valid_i && x_i >= K+LANES-2 && y_i >= K-1 &&
                               x_i < IMG_W && y_i < IMG_H;
            tag_x[0] <= x_i;
            tag_y[0] <= y_i;
            tag_last[0] <= row_last_i;
            for (i = 1; i <= DELAY; i = i + 1) begin
                common_valid[i] <= common_valid[i-1];
                tag_x[i] <= tag_x[i-1];
                tag_y[i] <= tag_y[i-1];
                tag_last[i] <= tag_last[i-1];
            end
        end
    end

    // All-or-none qualification forbids an accidental partial-search winner.
    wire full_search = common_valid[ENGINE_DELAY] && (&lane_valid);
    comparator_tree #(.LANES(LANES), .SAD_W(SAD_W), .D_W(D_W)) minimum (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .lane_valid_i({LANES{full_search}}), .sad_i(lane_sad),
        .disparity_i(lane_disparity), .valid_o(valid_o),
        .sad_o(sad_o), .disparity_o(disparity_o)
    );
    assign x_o = valid_o ? tag_x[DELAY] : '0;
    assign y_o = valid_o ? tag_y[DELAY] : '0;
    assign row_last_o = valid_o && tag_last[DELAY];

    // Protocol assertions are verification only, not extra datapath control.
    // synthesis translate_off
    integer lane;
    integer next_x, active_y;
    initial begin
        next_x = 0;
        active_y = 0;
        if (K < 1 || PIXEL_W < 1 || LANES < 1 || IMG_W < 1 || IMG_H < 1 ||
            SAD_W < PIXEL_W+$clog2(K*K) || D_W < ((LANES<=1)?1:$clog2(LANES)) ||
            X_W < ((IMG_W<=1)?1:$clog2(IMG_W)) || Y_W < ((IMG_H<=1)?1:$clog2(IMG_H)))
            $fatal(1, "SEARCH_PROTOCOL invalid parameters or undersized widths");
    end
    always @(posedge clk) begin
        if (!rst_n || clear_i) begin
            next_x = 0;
            active_y = 0;
        end else begin
            if (valid_i) begin
                if (x_i != next_x || x_i >= IMG_W || y_i >= IMG_H ||
                    (next_x != 0 && y_i != active_y) || row_last_i !== (x_i == IMG_W-1))
                    $fatal(1, "SEARCH_PROTOCOL rows require consecutive x, fixed y and matching last");
                for (lane = 0; lane < LANES; lane = lane + 1)
                    if (right_valid_i[lane] !== (x_i >= lane))
                        $fatal(1, "SEARCH_PROTOCOL missing lane column at x=%0d lane=%0d", x_i, lane);
                next_x = next_x + 1;
                active_y = y_i;
            end
            if (common_valid[ENGINE_DELAY] && !(&lane_valid))
                $fatal(1, "SEARCH_PROTOCOL common interior requires every engine result");
        end
    end
    // synthesis translate_on
endmodule
`default_nettype wire
```

## Line-by-line walkthrough

Every nonblank source line has its own row. Indentation inside code spans is retained; Markdown pipe escapes represent the literal RTL pipe characters.

| RTL line | Exact source line | Explanation |
|---:|---|---|
| 1 | `` `timescale 1ns/1ps `` | Sets simulation time units and precision; it does not specify a hardware clock frequency. |
| 2 | `` `default_nettype none `` | Requires explicit net declarations so misspelled wiring cannot silently create a net. |
| 4 | `// Fixed full-search backend: lane d receives R[x-d]. No scheduling/backpressure.` | States the fixed disparity mapping and that the caller must supply/consume beats without ready handshakes. |
| 5 | `// Prefix lane warmup is legal; missing spatial columns within a row are not.` | Distinguishes the allowed leading unavailable columns from forbidden holes in a lane's spatial history. |
| 6 | `// Input edge t -> winner after t+$clog2(K)+1+max(1,$clog2(LANES)).` | Gives the accepted-column-to-winner edge offset, assuming the beat completes eligible windows. |
| 7 | `module sad_search_backend #(` | Opens the cohesive lane-bank, qualification, reduction and metadata module with elaboration-time parameters. |
| 8 | `    parameter integer K = 11,` | Sets both the vertical column height and horizontal window length for every engine. |
| 9 | `    parameter integer PIXEL_W = 8,` | Sets the bit width of each unsigned image sample. |
| 10 | `    parameter integer LANES = 32,` | Allocates one physical engine per searched disparity; this is not a runtime lane count. |
| 11 | `    parameter integer IMG_W = 640,` | Defines the exclusive horizontal coordinate bound and the expected final column. |
| 12 | `    parameter integer IMG_H = 480,` | Defines the exclusive vertical coordinate bound used to reject out-of-image results. |
| 13 | `    parameter integer SAD_W = PIXEL_W + $clog2(K*K),` | Derives a sufficient width for the unsigned sum of all K-by-K absolute differences. |
| 14 | `    parameter integer D_W = (LANES <= 1) ? 1 : $clog2(LANES),` | Sizes the disparity identifier and keeps a legal one-bit port for a one-lane build. |
| 15 | `    parameter integer X_W = (IMG_W <= 1) ? 1 : $clog2(IMG_W),` | Sizes the x coordinate without creating a zero-width vector for a unit-width image. |
| 16 | `    parameter integer Y_W = (IMG_H <= 1) ? 1 : $clog2(IMG_H)` | Applies the same minimum-one-bit rule to the y coordinate. |
| 17 | `) (` | Ends parameter declarations and begins the external signal interface. |
| 18 | `    input  wire                          clk,` | Supplies the rising-edge clock shared by engines, reduction stages and metadata registers. |
| 19 | `    input  wire                          rst_n,` | Requests synchronous active-low reset; a low value takes effect on a rising edge. |
| 20 | `    input  wire                          clear_i,` | Synchronously aborts pending work and clears horizontal history and tags across the backend. |
| 21 | `    input  wire                          valid_i,` | Marks a real spatial input column; a low value inserts a clock bubble rather than advancing lane history. |
| 22 | `    input  wire [K*PIXEL_W-1:0]          left_column_i,` | Supplies the packed K-pixel left column shared by all disparity engines. |
| 23 | `    input  wire [LANES*K*PIXEL_W-1:0]    right_columns_i,` | Supplies packed lane columns, with one K-pixel slice for each disparity. |
| 24 | `    input  wire [LANES-1:0]             right_valid_i,` | Identifies which right columns exist during leading disparity warmup; it is not an arbitrary lane stall mask. |
| 25 | `    input  wire [X_W-1:0]               x_i,` | Tags the trailing/bottom-right x of the left window, not its center or the right-image x. |
| 26 | `    input  wire [Y_W-1:0]               y_i,` | Tags the bottom row of the left window; vertical border qualification uses this value. |
| 27 | `    input  wire                          row_last_i,` | Marks the accepted final column of this input row and travels alongside its coordinates. |
| 28 | `    output wire                          valid_o,` | Marks the comparator's complete-search winner; downstream must consume each asserted result. |
| 29 | `    output wire [SAD_W-1:0]             sad_o,` | Exposes the minimum full-window cost selected by the comparator. |
| 30 | `    output wire [D_W-1:0]               disparity_o,` | Exposes the winning lane's fixed disparity identifier. |
| 31 | `    output wire [X_W-1:0]               x_o,` | Returns the delayed left-window x belonging to that winner, zero when invalid. |
| 32 | `    output wire [Y_W-1:0]               y_o,` | Returns the corresponding delayed bottom-row y, zero when invalid. |
| 33 | `    output wire                          row_last_o` | Reports a valid result belonging to the input row's final column, not a general row-complete pulse. |
| 34 | `);` | Closes the module interface; internal datapath wiring follows. |
| 35 | `    localparam integer ENGINE_DELAY = $clog2(K)+1;` | Names E, the edge offset from an accepted column to its eligible engine output. |
| 36 | `    localparam integer REDUCE_STAGES = (LANES <= 1) ? 1 : $clog2(LANES);` | Names R, the comparator's registered reduction depth, including a registered one-lane path. |
| 37 | `    localparam integer DELAY = ENGINE_DELAY + REDUCE_STAGES;` | Names D=E+R, the complete backend output edge offset used to align metadata. |
| 38 | `    localparam integer COL_BITS = K * PIXEL_W;` | Defines the packed bit stride between successive right-column lanes. |
| 39 | `    wire [LANES-1:0] lane_valid;` | Collects each engine's complete-window stamp before common qualification. |
| 40 | `    wire [LANES*SAD_W-1:0] lane_sad;` | Collects all full-window costs in lane-indexed packed slices. |
| 41 | `    wire [LANES*D_W-1:0] lane_disparity;` | Carries constant disparity labels in the same packed order as the costs. |
| 42 | `    logic common_valid [0:DELAY];` | Allocates D+1 eligibility registers; index zero captures the input edge rather than being a wire. |
| 43 | `    logic [X_W-1:0] tag_x [0:DELAY];` | Allocates the matching D+1 registered x positions. |
| 44 | `    logic [Y_W-1:0] tag_y [0:DELAY];` | Allocates the matching D+1 registered y positions. |
| 45 | `    logic tag_last [0:DELAY];` | Gives the row-end tag the same physical edge progression as x and y. |
| 46 | `    integer i;` | Declares the procedural loop index used to reset and shift the metadata arrays. |
| 48 | `    // Engines receive early columns; masking before warmup would lose history.` | Explains why common-interior gating happens after engines, not at their column inputs. |
| 49 | `    genvar d;` | Declares the separate elaboration index for constructing fixed-disparity hardware instances. |
| 50 | `    generate` | Begins elaboration-time replication, not a sequential runtime search. |
| 51 | `        for (d = 0; d < LANES; d = d + 1) begin : g_lane` | Creates named lane scopes for all disparities from zero through LANES-1. |
| 52 | `            sad_engine #(.K(K), .PIXEL_W(PIXEL_W), .SAD_W(SAD_W)) engine (` | Instantiates an existing complete-window engine with common dimensions and result width. |
| 53 | `                .clk(clk), .rst_n(rst_n), .clear_i(clear_i),` | Makes every lane share the same clock and synchronous flush boundary. |
| 54 | `                .valid_i(valid_i && right_valid_i[d]),` | Accepts a column only when the global beat and this lane's right column are real; leading absent columns do not enter history. |
| 55 | `                .left_column_i(left_column_i),` | Fans the same left column out to every fixed-disparity engine. |
| 56 | `                .right_column_i(right_columns_i[d*COL_BITS +: COL_BITS]),` | Selects exactly lane d's K-pixel right column using an indexed part-select. |
| 57 | `                .valid_o(lane_valid[d]), .sad_o(lane_sad[d*SAD_W +: SAD_W])` | Places the engine's window-valid stamp and cost into corresponding lane slices. |
| 58 | `            );` | Completes the engine instance without adding a wrapper arithmetic register. |
| 59 | `            assign lane_disparity[d*D_W +: D_W] = D_W'(d);` | Drives this lane's constant disparity with an explicit D_W-bit cast. |
| 60 | `        end` | Closes one generated lane scope; all such lanes exist concurrently. |
| 61 | `    endgenerate` | Ends lane replication before the shared metadata pipeline. |
| 63 | `    // Index zero captures this edge; every later index shifts even on bubbles.` | Documents the register-count convention and wall-clock, rather than accepted-beat, delay. |
| 64 | `    always_ff @(posedge clk) begin` | Registers eligibility and tags on every rising edge. |
| 65 | `        if (!rst_n \|\| clear_i) begin` | Gives synchronous reset or clear priority over incoming valid data. |
| 66 | `            for (i = 0; i <= DELAY; i = i + 1) begin` | Visits every metadata register, including both endpoint indices. |
| 67 | `                common_valid[i] <= 1'b0;` | Invalidates all delayed interior stamps so aborted work cannot qualify a later reduction. |
| 68 | `                tag_x[i] <= '0;` | Removes stale x tags throughout the pipeline on reset/clear. |
| 69 | `                tag_y[i] <= '0;` | Removes stale y tags at the same flush edge. |
| 70 | `                tag_last[i] <= 1'b0;` | Clears pending row-end tags so an aborted row cannot advertise a final result. |
| 71 | `            end` | Finishes clearing all D+1 metadata positions. |
| 72 | `        end else begin` | Selects normal input capture and edge-by-edge shifting when no flush is active. |
| 73 | `            // Do not narrow the thresholds: an impossible interior must stay empty.` | Warns against truncating border constants into coordinate widths and accidentally admitting impossible windows. |
| 74 | `            common_valid[0] <= valid_i && x_i >= K+LANES-2 && y_i >= K-1 &&` | Captures eligibility only after the most delayed lane has K columns and all K vertical rows exist. |
| 75 | `                               x_i < IMG_W && y_i < IMG_H;` | Completes qualification with exclusive image bounds; dimensions too small for the interior produce no eligible beat. |
| 76 | `            tag_x[0] <= x_i;` | Captures this edge's x even on a bubble; validity, not conditional tag movement, decides whether it matters. |
| 77 | `            tag_y[0] <= y_i;` | Captures this edge's y into the first registered tag position. |
| 78 | `            tag_last[0] <= row_last_i;` | Captures the row-end flag with the same input edge as the coordinates. |
| 79 | `            for (i = 1; i <= DELAY; i = i + 1) begin` | Advances each later register by one clock edge, regardless of input validity. |
| 80 | `                common_valid[i] <= common_valid[i-1];` | Moves the old preceding eligibility stamp forward; nonblocking assignments prevent same-edge cascading. |
| 81 | `                tag_x[i] <= tag_x[i-1];` | Delays x by the identical register-to-register progression. |
| 82 | `                tag_y[i] <= tag_y[i-1];` | Keeps y aligned with x and eligibility through bubbles. |
| 83 | `                tag_last[i] <= tag_last[i-1];` | Keeps the row-end tag aligned with the eventual winning result. |
| 84 | `            end` | Ends the unconditional shift loop for positions one through D. |
| 85 | `        end` | Closes normal operation; reset/clear and shift cannot both execute on an edge. |
| 86 | `    end` | Ends the shared metadata sequential block. |
| 88 | `    // All-or-none qualification forbids an accidental partial-search winner.` | States that a winner is legal only for the entire configured disparity range. |
| 89 | `    wire full_search = common_valid[ENGINE_DELAY] && (&lane_valid);` | Combines the engine-aligned interior stamp with reduction-AND of all lane valids; one absent result suppresses the whole search beat. |
| 90 | `    comparator_tree #(.LANES(LANES), .SAD_W(SAD_W), .D_W(D_W)) minimum (` | Reuses the registered minimum reducer with matching cost and disparity packing widths. |
| 91 | `        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),` | Flushes the comparator on the same reset/clear edge as engines and tags. |
| 92 | `        .lane_valid_i({LANES{full_search}}), .sad_i(lane_sad),` | Replicates one common qualification bit to every candidate: all real lanes compete together or none do. |
| 93 | `        .disparity_i(lane_disparity), .valid_o(valid_o),` | Supplies fixed lane labels and directly exposes the reducer's result validity. |
| 94 | `        .sad_o(sad_o), .disparity_o(disparity_o)` | Routes the chosen cost and disparity directly to backend outputs. |
| 95 | `    );` | Ends the comparator instance; its own registers provide R reduction stages. |
| 96 | `    assign x_o = valid_o ? tag_x[DELAY] : '0;` | Selects the t+D coordinate only for a valid winner, otherwise explicitly outputs zero. |
| 97 | `    assign y_o = valid_o ? tag_y[DELAY] : '0;` | Applies the same valid-qualified behavior to the output bottom-row coordinate. |
| 98 | `    assign row_last_o = valid_o && tag_last[DELAY];` | Allows row_last only on a visible valid result; an empty interior does not generate completion. |
| 100 | `    // Protocol assertions are verification only, not extra datapath control.` | Separates diagnostic checks from synthesizable scheduling or recovery mechanisms. |
| 101 | `    // synthesis translate_off` | Begins a synthesis-excluded simulation-check region. |
| 102 | `    integer lane;` | Declares the simulation loop index used to check every lane's availability bit. |
| 103 | `    integer next_x, active_y;` | Tracks the expected next accepted column and the current row's y for protocol diagnostics. |
| 104 | `    initial begin` | Performs simulation initialization and parameter checking once at startup. |
| 105 | `        next_x = 0;` | Expects the first accepted column after startup to be x=0. |
| 106 | `        active_y = 0;` | Initializes the row tracker; the first accepted x=0 may establish a different legal y. |
| 107 | `        if (K < 1 \|\| PIXEL_W < 1 \|\| LANES < 1 \|\| IMG_W < 1 \|\| IMG_H < 1 \|\|` | Rejects nonpositive window, pixel, lane or image dimensions. |
| 108 | `            SAD_W < PIXEL_W+$clog2(K*K) \|\| D_W < ((LANES<=1)?1:$clog2(LANES)) \|\|` | Also rejects insufficient full-window cost width or insufficient disparity identifier width. |
| 109 | `            X_W < ((IMG_W<=1)?1:$clog2(IMG_W)) \|\| Y_W < ((IMG_H<=1)?1:$clog2(IMG_H)))` | Completes the parameter check by requiring enough bits for both image coordinates. |
| 110 | `            $fatal(1, "SEARCH_PROTOCOL invalid parameters or undersized widths");` | Stops simulation on an invalid parameter contract rather than silently accepting truncation. |
| 111 | `    end` | Ends the one-time setup; accepted-traffic checks run separately on clock edges. |
| 112 | `    always @(posedge clk) begin` | Observes protocol state on the same rising edges that accept input beats. |
| 113 | `        if (!rst_n \|\| clear_i) begin` | Restarts diagnostic row tracking when the actual backend state is reset or cleared. |
| 114 | `            next_x = 0;` | Requires a new spatial row to restart from its first column after flush. |
| 115 | `            active_y = 0;` | Discards the old row's diagnostic y state. |
| 116 | `        end else begin` | Checks traffic only when reset/clear is inactive. |
| 117 | `            if (valid_i) begin` | Ignores input coordinates and lane availability on global bubbles. |
| 118 | `                if (x_i != next_x \|\| x_i >= IMG_W \|\| y_i >= IMG_H \|\|` | Detects skipped/repeated accepted x values and coordinates outside the configured image. |
| 119 | `                    (next_x != 0 && y_i != active_y) \|\| row_last_i !== (x_i == IMG_W-1))` | Requires fixed y after the row's first beat and exact end-of-row marking; case inequality also catches an unknown last flag. |
| 120 | `                    $fatal(1, "SEARCH_PROTOCOL rows require consecutive x, fixed y and matching last");` | Terminates simulation when the global row-order/tag contract is violated. |
| 121 | `                for (lane = 0; lane < LANES; lane = lane + 1)` | Checks each configured disparity separately on every accepted column. |
| 122 | `                    if (right_valid_i[lane] !== (x_i >= lane))` | Allows exactly the disparity-prefix pattern, rejecting absent available columns, premature columns and unknown valid bits. |
| 123 | `                        $fatal(1, "SEARCH_PROTOCOL missing lane column at x=%0d lane=%0d", x_i, lane);` | Reports the offending coordinate/lane and stops instead of pretending a broken lane history can recover automatically. |
| 124 | `                next_x = next_x + 1;` | Advances expected spatial position only on a valid beat; it does not wrap at row_last. |
| 125 | `                active_y = y_i;` | Records the accepted row identifier for the next fixed-y comparison. |
| 126 | `            end` | Ends accepted-input checks without preventing independent checks of already pipelined work. |
| 127 | `            if (common_valid[ENGINE_DELAY] && !(&lane_valid))` | Detects a qualified interior beat whose engines are not all ready, even while current input is a bubble. |
| 128 | `                $fatal(1, "SEARCH_PROTOCOL common interior requires every engine result");` | Stops on missing interior engine results; all-or-none gating is not a substitute for satisfying the protocol. |
| 129 | `        end` | Closes active diagnostic checking for this edge. |
| 130 | `    end` | Ends the edge-based verification process, which adds no hardware control. |
| 131 | `    // synthesis translate_on` | Restores normal synthesis interpretation after the diagnostic-only region. |
| 132 | `endmodule` | Ends the backend definition; storage/frontend and transport remain outside this boundary. |
| 133 | `` `default_nettype wire `` | Restores the normal implicit-net default for subsequently compiled source. |

## Spatial history: prefix warmup is not permission to drop a column

An engine's horizontal buffer advances on **accepted columns**, not on x coordinates. If lane d silently misses a real column in the middle of a row, its next K accepted columns can bridge that missing spatial position. The resulting sum is not a contiguous K-by-K window, even if the engine later asserts valid. The backend does not store enough coordinate history to detect or repair that numerically.

Therefore the caller contract is strict:

- Start each row at x=0; increment accepted x by exactly one and keep y fixed until row end. Global bubbles are legal because neither spatial position nor lane history advances on them.
- On every accepted beat, require `right_valid_i[d] == (x_i >= d)`. Lane d begins at x=d, then accepts every subsequent real column of the row. Unavailable leading columns are the only lane-specific gap allowed.
- Feed these early lane columns into the engines even before the common output interior. Masking inputs until every window is ready would discard the history needed to create those windows.
- With initialized vertical columns, lane d first has K horizontal columns at x=d+K-1. The last disparity is d=LANES-1, giving the shared horizontal threshold `x >= K+LANES-2`. The vertical threshold is `y >= K-1`. Image bounds are checked too; a window/search range that cannot fit emits nothing, rather than wrapping a narrowed threshold.

The simulation assertions enforce this protocol but are synthesis-excluded. They are not synthesized hole detection, a scheduler, or proof that arbitrary upstream traffic is safe.

## Why qualification is all-or-none

`common_valid[ENGINE_DELAY]` identifies the coordinate now at the engine outputs. `&lane_valid` demands a complete-window stamp from **every** engine. Their conjunction, `full_search`, is replicated across all comparator candidate-valid bits.

The comparator is capable of reducing a subset of valid candidates, but that is intentionally not the meaning of this backend. An interior answer must search the entire configured range; feeding independent lane-valid bits directly into it could return a plausible minimum over only the lanes that happened to be ready. The combined gate suppresses that accidental partial-search answer. The accompanying assertion reports the underlying protocol failure. Neither mechanism rebuilds a lane's damaged history; contiguous accepted input columns remain mandatory.

## Timing: t+E+R is an edge offset; D+1 is a register count

Define `E = $clog2(K)+1`, `R = max(1,$clog2(LANES))`, and `D = E+R`.

| Event for an eligible input beat | Edge / register interpretation |
|---|---|
| Backend accepts the column and tags | At edge t, tag index 0 captures x/y/last and common validity. |
| Engines expose their complete-window costs | Just after edge t+E; the common stamp is at index E. |
| Comparator samples that engine beat | At edge t+E+1; it sees the preceding edge's registered engine outputs. |
| Last of R registered reductions exposes the winner | Just after edge t+E+R, with tags at index D. |
| Downstream synchronous consumer samples that winner | At the following rising edge, provided clear has not suppressed the result before it is observable. |

There are **D+1 tag registers**, indices `0..D`, because index zero is a real capture register at t. This does not mean the input-to-output offset is D+1 edges. After D further edges, the input tag has moved from index zero to index D. Every tag/stamp position shifts on every clock, including bubbles, to match the arithmetic pipeline's wall-clock travel. Shifting only on valid input would misassociate later coordinates with older arithmetic results.

Even `LANES=1` retains a registered reduction stage. For `K=1`, the engine still has its documented registered path; neither corner case removes the tag-alignment requirement. The frontend's additional latency belongs to [[Stereo SAD Datapath]], not this backend's input-edge definition.

## Coordinates, row_last, and draining

Coordinates describe the **bottom-right/trailing pixel of the left window**. The left window spans x-K+1 through x and y-K+1 through y. Disparity d uses right-image horizontal positions x-d-K+1 through x-d at those same rows. The backend forwards the original left coordinate, not a disparity-shifted right coordinate or a window-center coordinate. Actual vertical-column assembly and disparity alignment are frontend duties.

`row_last_i` must match `x_i == IMG_W-1` on an accepted beat. It is delayed by the same D-edge path, then qualified with winner valid. Thus `row_last_o` means **this valid result corresponds to the final input column**, not “the row finished regardless of whether results exist.” A vertically invalid row or image too narrow for the complete search can produce no row_last output at all.

Normal row end is caller-controlled: stop valid input after the final column, allow the engine/reducer/tag pipeline to drain through t+D, let the consumer sample the final result, and only then clear on a separate edge. The single-engine drain interval alone is not enough for this composed backend. There is no automatic drain timer, row counter reset on row_last, or row-overlap protocol here. The diagnostic `next_x` tracker does not wrap itself; clear/reset establishes the next row's x=0 start. An abort may assert clear immediately and deliberately discard pending results. Reset/clear reaches engines, comparator and tags together.

## Verification links and limits

- [Standalone backend bench](../tests/rtl/tb_sad_search_backend.sv): instantiates the actual backend and exposes engine costs/valids to the checker.
- [Shared raw-image checks](../tests/rtl/stereo_raw_checks.svh): test-only reference/checking infrastructure, separate from synthesizable RTL. The contract calls for recomputing complete raw-pixel windows rather than copying the DUT's rolling-history algorithm.
- [Regression runner](../scripts/run_tests.py), [walkthrough checker](../scripts/check_walkthrough.py), and [fault-sensitivity checker](../scripts/check_test_sensitivity.py): entry points for executable evidence, exact snapshots and mutation checks.
- [[Verification]], [[Verification Map]], and [[Testbench Guide]] organize evidence; the [datapath specification](../docs/accelerator-datapath-spec.md) states required cases and integration timing.

Subsequent parent-run evidence is recorded in [the complete compute verification report](../docs/verification/compute-datapath.md): all 130 default cases, 33 targeted faults and 13 exact-source mappings pass, together with real integrated 1/3/32-lane A&S. Tests compare raw-pixel lane/winner costs and precise tags, including K=1, odd lanes, ties, borders, bubbles and abort/drain edges. This is not device fitting, fitted timing, achieved throughput, board success or completed Nios V/controller/transport integration. No commit or push is part of this increment.
