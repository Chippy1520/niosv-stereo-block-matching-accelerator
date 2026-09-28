# Pipelined Column SAD Calculator
#implemented

[[Home]] · [[Single SAD Engine]] · [[Column Sum Buffer]] · [[Testbench Guide]]

Source: [rtl/column_sad.sv](../../rtl/column_sad.sv). Standalone bench: [tb_column_sad.sv](../../tests/rtl/tb_column_sad.sv).

## First, the story — no RTL yet

Imagine eleven pairs of students standing in a vertical line, one student holding a left-image gray value and the other holding the matching right-image gray value. Each pair measures **how different** its two numbers are, without caring which one is larger. All eleven pairs work simultaneously. They hand their differences to a set of collection desks: neighboring results are combined, then neighboring subtotals, until one desk holds the cost of this **one vertical column**. There are register checkpoints between desks, so several different columns can be in flight at once. A small companion marker follows each column through the same checkpoints; if no column arrives on a clock, that marker says “empty,” rather than stopping everyone already in the pipeline.

This is **not** a whole 11×11 SAD result. Another module gathers costs from neighboring columns. Reset or clear empties all checkpoints, intentionally discarding unfinished work. The picture is the physical process the RTL below implements:

```text
11 matched left/right pixel pairs
    -> 11 parallel absolute differences, registered at edge t
    -> 16-position adder bracket (five positions are constant zero)
    -> neighboring sums, registered at each reduction level
    -> one vertical-column cost and its validity stamp after edge t+4
```

**Map for reading code:** “pair” → a generated leaf `j`; “difference desk” → comparison and subtraction; “checkpoint” → `difference_reg` or `sum_reg`; “collection desks” → `tree`; “marker” → `valid_pipe`; “empty the desks” → `rst_n`/`clear_i`. The exact behavior and line-by-line mapping follow the source snapshot.

## Complete source

```systemverilog
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
```

## Code walkthrough — actual RTL, explained beside the lines

The complete [source snapshot](../../rtl/column_sad.sv) above is checked against `rtl/column_sad.sv`. The numbers below are **source-file line numbers**, not Markdown line numbers. Every `generate` loop expands to parallel hardware at elaboration; it does not run once per clock.

### 1. File setup and the module contract (lines 1–22)

```systemverilog
`timescale 1ns/1ps
`default_nettype none
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
```

- **Lines 1–2:** Simulation time unit/precision and implicit-net protection. Neither creates a clock or hardware delay; the final directive restores normal nettype outside this file.
- **Lines 4–8 (comments in the full source):** Declare one vertical cost, a registered leaf plus registered reduction levels, moving invalid bubbles, and synchronous reset/clear. These are the desk's operating rules, not separate hardware.
- **Line 9:** Defines the reusable calculator. `#(...)` chooses hardware dimensions *before synthesis*, not by writing a CPU register.
- **Lines 10–12:** `K` is the number of paired rows, `PIXEL_W` is bits per unsigned grayscale sample, and `COL_W` is the column-score width. At the defaults, the largest cost is 11×255 = 2805, so 12 bits suffice. `K=1` has zero reduction levels but still has its leaf register.
- **Lines 14–17:** `clk` clocks all checkpoints; active-low `rst_n` and active-high `clear_i` are sampled *at* the edge. `valid_i` says whether the presented pair of columns is real; there is no ready/backpressure.
- **Lines 18–19:** Each input bus contains K pixels. Row `j` is the slice beginning at bit `j*PIXEL_W` in **both** buses; the producer must already have selected the right disparity.
- **Lines 20–22:** The result is one vertical-column cost and its stamp. `column_sum_o` can hold stale data if `valid_o=0`; this is not a full square-window SAD.

**Story mapping:** K student pairs enter; `valid_i` is the delivery stamp, and `column_sum_o` is the final desk's column-only receipt.

### 2. How many desks and wires? (lines 23–27)

```systemverilog
localparam integer LEVELS = $clog2(K);
localparam integer LEAVES = 2**LEVELS;
logic [LEVELS:0] valid_pipe;
wire [COL_W-1:0] tree [0:LEVELS][0:LEAVES-1];
```

- **Line 23:** `LEVELS` is the number of pairwise addition rounds, four for K=11.
- **Line 24:** `LEAVES` reserves a power-of-two bracket: 16 leaf positions for 11 real pairs. Padding is constant zero, not five extra pixels or a clock stage.
- **Line 25:** `valid_pipe[0]` marks the registered difference leaves. Indices 1 through `LEVELS` mark each registered subtotal level. These stamp bits advance on *every* clock, including bubbles.
- **Lines 26–27:** The two-dimensional `tree[level][node]` carries one subtotal per active node. It is wiring to the registered leaves and sums, **not** an image memory. Unused positions in higher levels are never read and synthesize away.

**Story mapping:** `level` is a collection-desk round, `node` is one numbered desk within it, and `valid_pipe` is the companion stamp travelling beside the costs.

### 3. Stamp the arriving column (lines 29–32)

```systemverilog
always_ff @(posedge clk) begin
    if (!rst_n || clear_i) valid_pipe[0] <= 1'b0;
    else valid_pipe[0] <= valid_i;
end
```

- **Line 29:** A rising edge is the acceptance/checkpoint boundary.
- **Line 30:** Reset or clear wins over a simultaneously offered input, marking the leaf data invalid.
- **Line 31:** Otherwise record whether the new column is real. Zero creates a bubble; it does **not** freeze older columns in later desks.
- **Line 32:** Ends this leaf-stamp register. Nonblocking `<=` means downstream registers on this edge still see its *previous* value.

### 4. Create and register each pixel-pair difference (lines 34–53)

```systemverilog
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
```

- **Lines 34–37:** `genvar` names and `for` replicate leaf circuits at synthesis. Separate declarations are required by the installed Quartus parser. `j` is a hardware position, not a pixel-processing time step.
- **Lines 38–40:** Only `j<K` gets an actual pixel pair. `+: PIXEL_W` selects exactly one row from each packed bus; using the same `j` prevents accidentally comparing different rows.
- **Lines 41–42:** Choose the larger-minus-smaller subtraction. Each difference is unsigned and fits in `PIXEL_W` bits; all comparisons happen in parallel.
- **Lines 43–47:** Declare/register the difference at an edge. Clear zeros it. When `valid_i=1`, zero-extend the smaller difference to `COL_W` before feeding the adder tree. When `valid_i=0`, its *data* holds but line 31 has marked this leaf delivery invalid.
- **Line 49:** `tree[0][j]` names the registered leaf so the first subtotal level can read it on a later edge.
- **Lines 50–53:** `j>=K` connects a constant-zero leaf. For K=11, nodes 11–15 add no cost and need no pixel or difference register.

**Story mapping:** Each student pair hands its nonnegative difference to a registered desk; five empty desks are physically wired to zero. At edge `t`, the valid leaf registers for column A capture A—not any earlier column.

### 5. The registered pairwise tree (lines 54–69)

```systemverilog
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
```

- **Line 54:** Elaborates levels 1 through `LEVELS`; this builds simultaneous pipeline stages rather than iterating levels at runtime.
- **Lines 55–58:** The stamp for this level takes the *old* previous-level stamp every edge. Clear zeroes all stamps at the same edge, so an unfinished column cannot reappear later.
- **Line 59:** There are half as many active nodes each round (`LEAVES >> level`); at level 1 of a 16-leaf tree there are eight.
- **Lines 60–65:** Every node owns a register. Clear zeros it; otherwise the register captures a sum **only** when the preceding level's stamp is valid. On a bubble, the data stays put but the stamp propagates as zero.
- **Line 64 specifically:** `2*node` and `2*node+1` select adjacent nodes in the *preceding* registered level. A node sums two subtotals from the same column, because all registers read old values on an edge; no node mixes A with B.
- **Lines 66–69:** Connect the new register to the next level and close the generated structures. This registered checkpoint breaks a long adder chain into shorter clock-to-clock paths; fitted timing is still unverified.

**Indexed diagram for K=11; the arrows represent wiring, not extra cycles:**

```text
At edge t       LEVEL 0:  registered absolute differences
                 d0 d1 d2 d3 d4 d5 d6 d7 d8 d9 d10  0  0  0  0  0
                    \ /   \ /   \ /   \ /   \ /    \ / \ / \ /
At edge t+1     LEVEL 1: n0    n1    n2    n3    n4    n5 n6 n7
                        d0+d1 d2+d3 d4+d5 d6+d7 d8+d9 d10+0 0 0
                         \___/       \___/       \___/     \_/
At edge t+2     LEVEL 2:  n0          n1          n2        n3
                          d0..d3      d4..d7      d8..d10   0
                             \_________/             \_______/
At edge t+3     LEVEL 3:       n0                    n1
                                d0..d7                d8..d10
                                   \_____________________/
At edge t+4     LEVEL 4:                n0 = sum(d0..d10)
```

For each level, `tree[level][node]` is that exact numbered subtotal. For example, `tree[1][2]=d4+d5`; `tree[2][1]=d4+d5+d6+d7`; `tree[3][1]=d8+d9+d10`; `tree[4][0]` is the full column cost. The visually unused level-1/2 upper positions are constant-zero branches; the RTL may simplify them without changing valid latency.

### 6. Root output and parameter guards (lines 71–81)

```systemverilog
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
```

- **Lines 71–72:** Present the final stamp and root subtotal together. When invalid, the root data can be held; consumers must ignore it.
- **Lines 74–79:** Simulations reject illegal dimensions or a too-narrow output. `translate_off/on` prevents these checks from becoming runtime datapath hardware.
- **Lines 80–81:** Close the module and restore ordinary implicit-net handling for later compilation units.

**Follow column A through the registers:** if accepted at edge `t`, differences are registered at `t`; `tree[1][*]` at `t+1`; `tree[2][*]` at `t+2`; `tree[3][*]` at `t+3`; `tree[4][0]` and `valid_o` at `t+4`. The five registered stages have an edge offset of four because the first stage samples at `t`. A bubble accepted at `t+1` produces an invalid output at `t+5` without delaying A or any later valid column.

## Job of this module

For one supplied disparity alignment, accept K left pixels and K right pixels from a vertical column. Calculate the sum of their unsigned absolute differences. This is a **column** cost, not the complete K×K window cost. [[Column Sum Buffer]] provides horizontal reuse and the final window adder.

## Packed pixel convention

Row j occupies `[j*PIXEL_W +: PIXEL_W]` in both buses. Row zero is the least-significant slice. The producer must pair the correct corresponding left/right pixels. No image memory, rectification, disparity shifting, or coordinate generation lives here.

## Hardware stages

1. Compare each pixel pair and subtract smaller from larger. Register each absolute difference, zero-extended to COL_W.
2. Pad the conceptual leaf count to the next power of two with constant zeros. All real K pixels remain included.
3. At each tree level, add neighboring nodes and register the result. Padded constant branches may simplify during synthesis, but valid latency stays fixed.
4. Output the root and its associated validity bit.

For K=11 there are four registered reduction levels after the absolute-difference registers. This is **five register stages** from input sampling through column output. K=1 naturally bypasses reduction levels and uses only the registered absolute difference.

Full COL_W width is used throughout to make addition widths unambiguous; constant high bits can be optimized by synthesis.

## Precise latency convention

Let **t** be the rising edge that accepts an input. With L=ceil(log2(K)):
- Absolute differences are available just after edge t.
- Column output is available just after edge **t+L**.
- For K=11: column output after **t+4**.

“Five register stages” and “edge offset four” are not contradictory: the first register samples at t itself. No need to guess whether a count includes the sampling edge.

## Valid, bubbles, reset and clear

The pipeline advances every clock. Each valid bit follows its corresponding data. `valid_i=0` inserts a bubble; it does not freeze older in-flight work. Data registers only update when their incoming stage is valid, so output data holds during output-invalid cycles.

Synchronous active-low `rst_n` or active-high `clear_i` clears every pipeline validity bit and data register. Clear wins over simultaneous input validity. It is an **abort/flush**, not a delayed row marker: pending column results are discarded.

## Standalone verification

The testbench computes the expected column by a serial software-style sum, then schedules it at the documented output edge. It checks data and validity every cycle, including held data on bubbles and zero data on flush.

Directed tests cover zero differences, maximum differences in both subtraction directions, each pixel position independently, odd/non-power-of-two K, and flushes at different pipeline offsets. Deterministic random columns mix bubbles, resets and clears.

```sh
python scripts/run_tests.py --suite column
python scripts/run_tests.py --suite column --case 11:8 --vcd
```

See [[Timing and Pipelining]] for integration timing and [[Verification]] for actual run evidence. Quartus Lite 22.1 requires the separately declared `genvar` style used here; inline `for (genvar ...)` was rejected by the installed parser.
