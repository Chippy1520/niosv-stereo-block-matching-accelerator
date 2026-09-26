---
tags:
  - implemented
  - walkthrough
aliases:
  - Circular Buffer Code Walkthrough
---

# Column Sum Buffer — Code Walkthrough

[[Home]] · [[Column Sum Buffer]] · [[Rolling SAD Math]] · [[Interface Contract]] · [[Verification]]

This note contains the complete `rtl/column_sum_buffer.sv` source, its line-by-line explanation, a worked example, and a comparison against the proposed stereo SAD architecture.

> [!important] Main comparison
> **Your proposal:** retain ten previous column sums and combine them with the new column sum.
> **Implemented:** retain those same ten column sums **and their running total**, so we do not need to add all ten stored sums again.
>
> This module starts **after** the eleven absolute differences for a new column have already been added. It does not accept raw image pixels.

The embedded code is a source snapshot. If the RTL changes later, refresh this note before relying on its line numbers. The source of truth is [column_sum_buffer.sv](rtl/column_sum_buffer.sv).

## Complete SystemVerilog source

```systemverilog
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
```

## 1. What enters and leaves this module

For one disparity engine:

```text
11 left-image pixels     11 shifted right-image pixels
          │                         │
          └──── Absolute differences
                           │
                  Sum of 11 differences
                           │
                      column_sum_i
                           │
                ┌─────────────────────┐
                │ column_sum_buffer   │ ← current module
                │                     │
                │ Ten previous sums   │
                │ + their total       │
                └─────────────────────┘
                           │
                         sad_o
                   Full 11×11 SAD
```

Each of the 32 disparity engines needs its **own independent history**. The multi-engine wrapper is a later stage: [[Disparity Bank]].

## 2. File setup — lines 1–6

```systemverilog
`timescale 1ns/1ps
`default_nettype none
```

### Line 1 — simulation timescale

`1ns` is the unit for simulation delays; `1ps` is the simulation precision. This does **not** set the FPGA clock frequency. Hardware provides the clock, and the `.sdc` file describes its expected timing to Quartus.

### Line 2 — disable implicit nets

Prevents undeclared names from silently becoming wires. For example, a typo such as `history_smu` instead of `history_sum` should produce an error rather than unintended hardware.

### Lines 4–6 — interface comments

```systemverilog
// One disparity lane. Input: sum of K vertical absolute pixel differences.
// Output: sum of K consecutive input columns. One input per clock, no backpressure.
// clear_i discards all history and takes priority over valid_i; assert between rows.
```

One instance handles one disparity. Input is a column sum, not an individual pixel difference. Output combines `K` consecutive accepted columns. There is no `ready` signal. Clearing discards the history.

“One input per clock” describes the maximum acceptance rate; `valid_i` can introduce gaps.

## 3. Module parameters — lines 7–12

```systemverilog
module column_sum_buffer #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer COL_W = PIXEL_W + $clog2(K),
    parameter integer SAD_W = PIXEL_W + $clog2(K*K)
) (
```

### Line 7 — module declaration

Defines the reusable hardware block. The `#(...)` section contains parameters used when elaborating the design.

### Line 8 — kernel size

`K = 11` assumes a square `K × K` window. Here, `K` determines how many consecutive column sums form a full SAD.

**Difference from runtime configuration:** `K` is fixed when synthesizing the design. Nios V cannot change it by writing a register.

### Line 9 — pixel width

`PIXEL_W = 8` assumes unsigned 8-bit grayscale pixels. The upstream absolute-difference circuit must use the same interpretation.

### Line 10 — column-sum width

`$clog2(...)` is the ceiling of the base-two logarithm. `COL_W` reserves enough bits to sum `K` pixel differences.

For the defaults, the maximum legal column sum is **2,805**, and `COL_W` is **12 bits**.

### Line 11 — full-window width

`SAD_W` reserves enough bits for all differences in the square window. For the defaults, the maximum legal SAD is **30,855**, and `SAD_W` is **15 bits**.

These formulas are safe width bounds for legal pixel-derived inputs, not necessarily the smallest possible widths for every parameter combination.

### Line 12 — begin ports

Ends the parameter list and begins the port list.

## 4. Ports — lines 13–20

```systemverilog
input  wire                 clk,
input  wire                 rst_n,
input  wire                 clear_i,
input  wire                 valid_i,
input  wire [COL_W-1:0]     column_sum_i,
output logic                valid_o,
output logic [SAD_W-1:0]    sad_o
);
```

### Line 13 — `clk`

State updates on rising clock edges.

### Line 14 — `rst_n`

Active-low reset: zero means reset; one means normal operation. It is **synchronous** and takes effect only on a rising edge. The `_n` suffix indicates polarity, not synchronous/asynchronous behavior.

### Line 15 — `clear_i`

Clears this buffer without a whole-system reset. Intended uses include starting a scanline, starting a frame, or aborting and restarting processing.

### Line 16 — `valid_i`

Indicates that `column_sum_i` contains a new column to accept at the next rising edge. When low, history does not advance.

### Line 17 — `column_sum_i`

Unsigned sum of `K` vertically aligned absolute pixel differences. This is one scalar for one disparity lane.

### Line 18 — `valid_o`

High when registered `sad_o` is a complete window result. Downstream logic must ignore output data when this signal is low.

### Line 19 — `sad_o`

Registered full-window SAD.

### Line 20 — close ports

Closes the port declaration.

**Why `wire` inputs and `logic` outputs?** Inputs are driven externally. Outputs are assigned inside sequential procedural blocks, for which `logic` is appropriate.

## 5. Input assumptions — lines 21–22

```systemverilog
// Parameters are elaboration-time constants, not CPU registers.
// Legal input range: 0 .. K * (2**PIXEL_W - 1).
```

These comments do not enforce the input range. A 12-bit input can represent values outside the legal column-sum range, but upstream logic must not supply those values. Output width is sized for actual pixel-derived column sums, not arbitrary use of every input encoding.

## 6. Generate block and K = 1 — lines 23–34

### Lines 23–24 — select hardware at elaboration

```systemverilog
generate
    if (K == 1) begin : g_single
```

This is an elaboration-time choice, not a runtime multiplexer. Quartus builds either the `K = 1` implementation or the history-buffer implementation—not both.

### Line 25 — sequential logic

```systemverilog
always_ff @(posedge clk) begin
```

Defines rising-edge-triggered sequential logic.

### Lines 26–28 — reset or clear

```systemverilog
if (!rst_n || clear_i) begin
    valid_o <= 1'b0;
    sad_o <= '0;
```

Invalidates output and sets data to zero. `'0` fills the destination with zero bits.

### Lines 29–31 — direct registered output

```systemverilog
end else begin
    valid_o <= valid_i;
    if (valid_i) sad_o <= column_sum_i;
```

For `K = 1`, no preceding columns are required. A valid input becomes a valid registered output. On an invalid input, output data holds while validity becomes low.

### Lines 32–34 — start the history implementation

Close the preceding blocks and select:

```systemverilog
end else begin : g_history
```

For `K = 11`, this is the branch Quartus implements.

## 7. Internal dimensions — lines 35–37

```systemverilog
localparam integer DEPTH = K - 1;
localparam integer PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
localparam integer COUNT_W = $clog2(DEPTH + 1);
```

### Line 35 — `DEPTH`

Number of previous column sums to remember: ten for this design. Eleven stored entries are unnecessary because the incoming column is available at the input.

### Line 36 — `PTR_W`

Pointer width. The conditional avoids a zero-width pointer for a one-entry history.

### Line 37 — `COUNT_W`

Counter width. It must represent zero through `DEPTH`, inclusive.

`localparam` marks an internally derived constant, rather than a parameter intended for external override.

## 8. Stored state — lines 38–41

```systemverilog
logic [COL_W-1:0] history [0:DEPTH-1];
logic [PTR_W-1:0] wr_ptr;
logic [COUNT_W-1:0] fill_count;
logic [SAD_W-1:0] history_sum;
```

### Line 38 — `history`

Array holding previous column sums: `history[0]` through `history[9]`, each 12 bits wide for the defaults.

**Actual Quartus result:** the array was not inferred as block RAM because of its asynchronous read. The current design uses logic/register resources for this storage.

### Line 39 — `wr_ptr`

Identifies the next entry to overwrite. Once full, that entry contains the oldest retained column sum.

### Line 40 — `fill_count`

Tracks valid history entries. It increases until history is full, then saturates.

### Line 41 — `history_sum`

Stores the sum of all currently valid retained entries. This is the additional optimization.

Both representations are needed:
- `history_sum` supplies the retained total quickly.
- `history[]` tells us which oldest value to subtract.

## 9. Combinational signals — lines 42–46

### Line 42 — history full

```systemverilog
wire full = (fill_count == DEPTH);
```

High once `K−1` previous columns exist. A valid output additionally requires a new valid input.

### Line 43 — extend the incoming value

```systemverilog
wire [SAD_W-1:0] new_column =
    {{(SAD_W-COL_W){1'b0}}, column_sum_i};
```

Zero-extends the input to accumulator width. Replication creates leading zeros; concatenation joins them to the column value. The numerical value is unchanged, and arithmetic widths are explicit.

### Lines 44–46 — select the oldest value safely

```systemverilog
// Uninitialized memory is never used until every slot has been written.
wire [SAD_W-1:0] old_column = full
    ? {{(SAD_W-COL_W){1'b0}}, history[wr_ptr]}
    : {SAD_W{1'b0}};
```

When full, select the oldest retained sum and zero-extend it. During warmup, select zero instead. Unwritten or stale memory cannot influence the arithmetic during warmup.

These `wire ... = ...` declarations are continuous combinational connections, **not one-time initialization statements**.

## 10. Sequential update and reset — lines 48–55

```systemverilog
always_ff @(posedge clk) begin
    if (!rst_n || clear_i) begin
        wr_ptr <= '0;
        fill_count <= '0;
        history_sum <= '0;
        valid_o <= 1'b0;
        sad_o <= '0;
    end else begin
```

- **Line 48:** state changes on rising edges.
- **Line 49:** reset and clear take priority over processing.
- **Line 50:** restart pointer at the first entry.
- **Line 51:** logically invalidate all retained entries.
- **Line 52:** reset retained-history total.
- **Lines 53–54:** invalidate and clear output.
- **Line 55:** begin normal operation.

> [!warning] Clear/input collision
> `clear_i = 1` and `valid_i = 1` on the same edge **discard the incoming column**. The current interface requires a separate boundary-clear cycle before the first column of the new row.

### Why not clear the memory array?

`fill_count` prevents stale entries from being used. New columns overwrite every entry before the history is declared full. Clearing the array is therefore unnecessary and would add reset wiring.

## 11. Default validity and input acceptance — lines 56–57

```systemverilog
valid_o <= 1'b0;
if (valid_i) begin
```

**Line 56:** default output validity to zero. If a complete window is accepted below, the later assignment sets it to one.

**Line 57:** accept a column only when valid is high.

When `valid_i = 0`:
- Pointer holds.
- Counter holds.
- Memory holds.
- History total holds.
- Output data holds.
- Output validity becomes zero.

> [!important] Stalls versus missing coordinates
> An invalid cycle must mean “no new column transferred,” not “skip a spatial column and join the columns around it.” The module has no coordinates and cannot detect spatial gaps.

## 12. Producing the full SAD — lines 58–62

```systemverilog
// Before this edge history_sum contains the previous K-1 columns.
if (full) begin
    sad_o <= history_sum + new_column;
    valid_o <= 1'b1;
end
```

- **Line 58:** documents the invariant: before an input, history contains the retained preceding columns.
- **Line 59:** produce output only when enough history exists.
- **Line 60:** add the new column to that retained total, obtaining a full window.
- **Line 61:** mark the output valid.
- **Line 62:** close the condition.

### Critical concept: nonblocking assignments

The `<=` assignments evaluate their right-hand sides using the old state and update registers together. Therefore:

```systemverilog
sad_o <= history_sum + new_column;
```

uses the history total **before** the update below. It does not use the newly updated total.

## 13. Updating history — lines 63–65

```systemverilog
// Evict oldest, insert newest: prepare history for the NEXT input.
history_sum <= (history_sum - old_column) + new_column;
history[wr_ptr] <= column_sum_i;
```

**Line 63:** output and history have distinct meanings:
- Output includes all `K` window columns.
- Updated history retains only the latest `K−1` columns for the next input.

**Line 64:** remove the oldest retained column and add the new one. During warmup, the removed value is zero, so this accumulates incoming values.

**Line 65:** overwrite the oldest array entry with the incoming column sum.

Nonblocking semantics ensure `old_column` is taken from the memory entry **before** it is overwritten.

## 14. Circular pointer — lines 66–67

```systemverilog
if (wr_ptr == DEPTH-1) wr_ptr <= '0;
else wr_ptr <= wr_ptr + 1'b1;
```

**Line 66:** wrap to zero at the final valid entry.

**Line 67:** otherwise advance to the next entry.

Explicit wrapping supports a depth that is not a power of two. Natural binary pointer overflow would not implement the desired ten-entry cycle.

The data does **not physically shift through the array**. Only one entry is replaced on each accepted input.

## 15. Warmup count — line 68

```systemverilog
if (!full) fill_count <= fill_count + 1'b1;
```

Increment until full, then saturate.

For `K = 11`:
- The first ten accepted inputs populate history.
- The eleventh produces the first complete SAD.

On the tenth accepted input, `full` is still false before the edge, so output is correctly suppressed. The counter reaches full as a result of that edge.

## 16. Closing hardware blocks — lines 69–73

The closing `end` statements and `endgenerate` close, in order:

1. Valid-input condition.
2. Normal-operation branch.
3. Sequential block.
4. History implementation.
5. Generate construct.

They introduce no additional hardware behavior. Blank lines throughout the file likewise only separate sections for readability.

## 17. Parameter checks — lines 75–82

```systemverilog
// synthesis translate_off
initial begin
    if (K < 1 || PIXEL_W < 1) $fatal(1, "K and PIXEL_W must be positive");
    if (COL_W < PIXEL_W + $clog2(K)) $fatal(1, "COL_W too small");
    if (SAD_W < PIXEL_W + $clog2(K*K) || SAD_W < COL_W)
        $fatal(1, "SAD_W too small");
end
// synthesis translate_on
```

- **Lines 75 and 82:** synthesis directives exclude these checks from hardware.
- **Line 76:** run the initial block once at simulation startup.
- **Line 77:** reject nonpositive kernel/pixel width.
- **Line 78:** reject insufficient column width.
- **Lines 79–80:** reject insufficient SAD width or SAD width smaller than column width.
- **Line 81:** close the check block.

These are simulation safeguards, not runtime checks. Some invalid parameter combinations may fail during elaboration before these checks can run.

## 18. End of file — lines 83–84

```systemverilog
endmodule
`default_nettype wire
```

**Line 83:** end the module.

**Line 84:** restore the usual implicit-net setting so this file's stricter setting does not unintentionally affect subsequent code.

## 19. Worked example — K = 3

Use a smaller kernel to make the ring behavior clear. `K = 3` requires two history entries. The following trace was computed for input columns `10, 20, 30, 40, 50`:

| New column | Pointer before | History total before | Oldest removed | Output SAD | History total after | Memory after |
|---:|---:|---:|---:|---:|---:|---|
| 10 | 0 | 0 | 0 | Invalid | 10 | `[10, unwritten]` |
| 20 | 1 | 10 | 0 | Invalid | 30 | `[10, 20]` |
| 30 | 0 | 30 | 10 | 60 | 50 | `[30, 20]` |
| 40 | 1 | 50 | 20 | 90 | 70 | `[30, 40]` |
| 50 | 0 | 70 | 30 | 120 | 90 | `[50, 40]` |

Array order is not chronological after wrapping. **The pointer identifies the oldest entry.**

The output total includes the oldest column, but the updated retained-history total excludes it. This distinction is the core of the implementation.

### Same example with a stall and clear

```text
After reset:
accept 10  → invalid
accept 20  → invalid
bubble     → invalid; history unchanged
accept 30  → valid SAD 60
accept 40  → valid SAD 90
clear      → invalid; history logically empty
```

After clear, warmup starts again. If clear and valid coincide, that input is discarded.

## 20. Instantiation for the 11×11 design

```systemverilog
logic        column_valid;
logic [11:0] column_sum;
logic        window_valid;
logic [14:0] window_sad;

column_sum_buffer #(
    .K       (11),
    .PIXEL_W (8)
) u_column_sum_buffer (
    .clk          (clk),
    .rst_n        (rst_n),
    .clear_i      (clear_history),
    .valid_i      (column_valid),
    .column_sum_i (column_sum),
    .valid_o      (window_valid),
    .sad_o        (window_sad)
);
```

The enclosing module must supply `clk`, `rst_n`, and `clear_history`, and connect the column producer and result consumer. This is an integration example, not a complete board top-level.

## 21. Comparison against the original plan

| Intended feature | Current implementation |
|---|---|
| Retain previous ten column sums | **Yes** |
| Combine new column with previous ten | **Yes**, using their stored running total |
| Compute eleven absolute differences for the new column | **Not in this module**; upstream stage |
| Run 32 disparity calculations in parallel | **Not yet**; one lane's history |
| Pipeline column adder trees | **Now implemented** in [[Pipelined Column SAD Calculator]], outside this buffer |
| Comparator tree carrying score and disparity index | **Not yet** |
| Pipeline comparator tree | **Not yet** |
| Accept image width and height | **Not here**; frontend/controller responsibility |
| Configure kernel through Nios V | **Not yet**; current `K` is compile-time |
| Clear between scanlines | **Yes**, with explicit clear input |
| Handle borders and invalid disparities | **Not here**; frontend/masking responsibility |

### Design point 1 — running-total feedback timing

```systemverilog
history_sum <= (history_sum - old_column) + new_column;
```

The history update contains subtraction followed by addition. This avoids repeatedly summing all stored columns but creates a feedback timing path.

The output is registered; that does **not** mean the arithmetic is internally pipelined. Simply inserting extra registers in the feedback path would break consecutive-column processing at one input per clock. A redesigned recurrence or scheduling scheme would be necessary.

See [[Timing and Pipelining]]. Quartus Analysis & Synthesis has passed, but fitted timing has not been verified.

### Design point 2 — runtime kernel configuration

If kernel size is selected before synthesis, this implementation matches that requirement.

If Nios V must change it while the FPGA runs, the design needs:
- Maximum supported size.
- Runtime depth control.
- Width sizing for the supported maximum.
- Clear/restart behavior when configuration changes.

See [[Nios V Interface]].

## Conclusion

The module implements horizontal column reuse for a fixed-size, single-disparity lane, with an additional running-total optimization.

The column calculator, one integrated lane and the [[Circular Row Buffer]] abstraction are now implemented. See [[Pipelined Column SAD Calculator]], [[Single SAD Engine]], [[Module Blocks.canvas]] and [[Testbench Guide]]. Remaining stages include disparity alignment, the parallel engine bank, and comparator integration.

## Related notes

- [[Column Sum Buffer]] — implementation overview and bit widths.
- [[Rolling SAD Math]] — stereo indexing and recurrence.
- [[Interface Contract]] — reset, clear, validity and acceptance rules.
- [[Column SAD Engines]] — upstream absolute differences and adder tree.
- [[Image Line Buffers]] — vertical image storage, separate from this ring.
- [[Disparity Bank]] — independent state per disparity.
- [[Minimum Comparator Tree]] — future best-match selection.
- [[Timing and Pipelining]] — feedback and pipeline caveats.
- [[Verification]] — simulation and synthesis evidence.
