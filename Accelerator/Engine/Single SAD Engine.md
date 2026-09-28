# Single SAD Engine
#implemented

[[Home]] · [[Pipelined Column SAD Calculator]] · [[Column Sum Buffer]] · [[Testbench Guide]] · [[Disparity Bank]]

Source: [rtl/sad_engine.sv](../../rtl/sad_engine.sv). Standalone bench: [tb_sad_engine.sv](../../tests/rtl/tb_sad_engine.sv).

## First, the story — no RTL yet

Picture a conveyor bringing **already paired** left/right vertical columns for one chosen disparity. The first station measures the difference at every row and combines those differences into one column cost. The second station keeps the costs of the preceding columns in a circular ledger. Once that ledger has enough history, it adds the new cost to the preceding costs to produce one complete square-window SAD. Each station stamps its output with “valid,” so a skipped input does not accidentally become a real window. The second station is one registered step behind the first. At the end of a scanline, let all submitted columns leave both stations before wiping their state for the next scanline.

The conveyor is **one fixed-disparity lane**. It does not fetch either image, choose the disparity, or decide which of 32 candidates wins. Its second station already includes the final window addition—there is no third arithmetic station in this wrapper.

```text
Already aligned left/right columns (one fixed disparity)
    -> station 1: registered pixel differences and column subtotal tree
    -> stamped intermediate column cost
    -> station 2: circular previous-column costs and final SAD register
    -> complete window cost + validity
Reset/clear reaches both stations at the same rising edge.
```

**Map for reading code:** station 1 → `u_column_sad`; the handoff stamp and cost → `column_valid`/`column_sum`; station 2 → `u_column_sum_buffer`; the final product → `valid_o`/`sad_o`. The source and detailed mapping follow.

## Complete source

```systemverilog
`timescale 1ns/1ps
`default_nettype none

// One fixed-alignment disparity lane. Upstream supplies already-aligned K-pixel
// columns; image storage, disparity shifting and coordinate tags are NOT inside.
// Accepts one column per edge with valid_i; no input/output backpressure.
// Accepted input at edge t -> window output at t+$clog2(K)+1 (once K columns exist).
// clear_i flushes both the column pipeline and horizontal history immediately.
// Normal row end: drive valid_i=0 for $clog2(K)+1 edges, then clear on its own edge.
module sad_engine #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer COL_W = PIXEL_W + $clog2(K),
    parameter integer SAD_W = PIXEL_W + $clog2(K*K)
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       clear_i,
    input  wire                       valid_i,
    input  wire [K*PIXEL_W-1:0]       left_column_i,
    input  wire [K*PIXEL_W-1:0]       right_column_i,
    output wire                       valid_o,
    output wire [SAD_W-1:0]           sad_o
);
    wire column_valid;
    wire [COL_W-1:0] column_sum;

    column_sad #(.K(K), .PIXEL_W(PIXEL_W), .COL_W(COL_W)) u_column_sad (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(valid_i),
        .left_column_i(left_column_i), .right_column_i(right_column_i),
        .valid_o(column_valid), .column_sum_o(column_sum)
    );

    // The existing buffer ALREADY includes the final H + new_column SAD adder.
    column_sum_buffer #(.K(K), .PIXEL_W(PIXEL_W), .COL_W(COL_W), .SAD_W(SAD_W))
    u_column_sum_buffer (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .valid_i(column_valid), .column_sum_i(column_sum),
        .valid_o(valid_o), .sad_o(sad_o)
    );
endmodule
`default_nettype wire
```

## Code walkthrough — source excerpts with line-by-line mapping

Source-file line numbers refer to [rtl/sad_engine.sv](../../rtl/sad_engine.sv), not this Markdown page. This wrapper **instantiates** the calculator and history buffer; it has no separate arithmetic register of its own.

### 1. Contract, dimensions and ports (lines 1–24)

```systemverilog
`timescale 1ns/1ps
`default_nettype none
module sad_engine #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer COL_W = PIXEL_W + $clog2(K),
    parameter integer SAD_W = PIXEL_W + $clog2(K*K)
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       clear_i,
    input  wire                       valid_i,
    input  wire [K*PIXEL_W-1:0]       left_column_i,
    input  wire [K*PIXEL_W-1:0]       right_column_i,
    output wire                       valid_o,
    output wire [SAD_W-1:0]           sad_o
);
```

- **Lines 1–2:** Simulation time unit and implicit-net typo protection. Neither introduces a pipeline stage.
- **Lines 4–9 (comments in the full source):** Upstream must supply aligned, fixed-disparity columns. One column can arrive per edge, but gaps are allowed. Row-end draining and clear are *controller* duties, not an automatic feature of this wrapper.
- **Line 10:** Declares one reusable lane. The `#(...)` values configure hardware at elaboration; no Nios V runtime control is implemented here.
- **Lines 11–12:** `K` chooses both the number of rows per column and columns per square window; `PIXEL_W` sets each unsigned pixel's width.
- **Line 13:** `COL_W` holds one vertical column cost (12 bits by default), not a full window cost.
- **Line 14:** `SAD_W` holds up to K×K pixel differences (15 bits by default for K=11, 8-bit pixels).
- **Lines 16–19:** One clock and synchronous reset/clear feed both stations. `valid_i` is the receipt stamp for a real incoming pair; there is no ready/backpressure signal.
- **Lines 20–21:** Both buses are packed K-row vertical columns. Pair row `j` in the left bus with row `j` in the right bus; disparity alignment and image storage happen elsewhere.
- **Lines 22–24:** The wrapper exposes the complete window SAD and its validity, not intermediate pixel differences. Ignore `sad_o` if `valid_o=0`.

**Conveyor mapping:** the aligned pixel buses arrive at station 1; `COL_W` sizes its receipt, while `SAD_W` sizes the final product at station 2.

### 2. Wires between stations (lines 25–26)

```systemverilog
wire column_valid;
wire [COL_W-1:0] column_sum;
```

- **Line 25:** `column_valid` is the first station's stamp, sampled by the second station on the following edge.
- **Line 26:** `column_sum` is its vertical-only cost, sized to fit K differences. These are **wires**, not extra registers or an extra clock stage.

### 3. Station 1 — pipelined vertical calculation (lines 28–32)

```systemverilog
column_sad #(.K(K), .PIXEL_W(PIXEL_W), .COL_W(COL_W)) u_column_sad (
    .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(valid_i),
    .left_column_i(left_column_i), .right_column_i(right_column_i),
    .valid_o(column_valid), .column_sum_o(column_sum)
);
```

- **Line 28:** Creates one *physical instance* of the calculator, with the exact same K, pixel width, and intermediate width. This is not a function called later by the CPU.
- **Line 29:** Carries clock and synchronous abort into the calculator. When a real input is present, `valid_i` labels that column's difference leaves.
- **Line 30:** Gives the first station both aligned pixel columns, unchanged by this wrapper.
- **Line 31:** Connects its *registered* sum and stamp to the two internal wires above.
- **Line 32:** Ends this instance; there is no wrapper register between stations. The calculator internally registers each absolute difference and each pairwise addition level.

**Where is one value now?** If column A is accepted at edge `t`, its difference leaves are captured at `t`; for K=11, its column cost is on `column_sum` and its stamp on `column_valid` after edge `t+4`. See the indexed node diagram in [[Pipelined Column SAD Calculator]].

### 4. Station 2 — circular history and the *only* full-window adder (lines 34–40)

```systemverilog
// The existing buffer ALREADY includes the final H + new_column SAD adder.
column_sum_buffer #(.K(K), .PIXEL_W(PIXEL_W), .COL_W(COL_W), .SAD_W(SAD_W))
u_column_sum_buffer (
    .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
    .valid_i(column_valid), .column_sum_i(column_sum),
    .valid_o(valid_o), .sad_o(sad_o)
);
```

- **Line 34:** Warns not to add another `history_sum + column_sum` here: the instantiated buffer *already* computes and registers that sum.
- **Line 35:** Gives the second station the same K, pixel and column widths, plus the wider full-window output width.
- **Line 36:** Names the actual circular-history instance.
- **Line 37:** Both stations see the same synchronous reset/clear edge. Clear takes priority over valid in each: pending first-stage data and old second-stage history are both discarded.
- **Line 38:** The second station accepts `column_sum` *only* when `column_valid` is high. A bubble can carry held numerical data but must not advance the circular pointer or running total.
- **Line 39:** Directly connects the buffer's registered full-window result and validity to the wrapper output. There is no extra output register.
- **Line 40:** Ends the instance. Within the buffer, the old total of K−1 previous costs plus the incoming cost yields one K-column SAD; the history is simultaneously updated for the *next* column.
- **Lines 41–42:** End the wrapper and restore normal nettype. No third arithmetic station appears here.

**Story mapping:** station 1 hands over a stamped column-cost card; station 2's rotating tray holds K−1 earlier cards, and the new card completes the score.

### 5. Diagram — register boundary, warmup and row end

```text
One K=11 column A, accepted at rising edge t (assuming prior 10 columns already filled the history):

edge              t        t+1      t+2      t+3      t+4      t+5
calculator A      abs      add1     add2     add3     add4     held/next
column_valid(A)   0        0        0        0        1        0/next
buffer A          —        —        —        —        —        register H + A
valid_o(A)        0        0        0        0        0        1

History of valid column costs (not raw pixels):
receive C0..C9     -> buffer has ten earlier cards; no full window yet
receive C10        -> sad_o = C0 + ... + C10, then rotate out C0
receive C11        -> sad_o = C1 + ... + C11, then rotate out C1
last raw column    -> wait L+1 empty input edges, consuming any outputs
separate clear edge-> invalidate both stations before next scanline
```

At `t+4` both instances are clocked, so the buffer sees the calculator's *old* outputs; it can accept A only at `t+5`. In this diagram `column_valid(A)` describes whether that wire marks A; a continuous stream could have other valid outputs on neighboring edges. The buffer's first valid full-window output requires K accepted column *costs*, regardless of bubbles. `clear_i` on the final-result edge would suppress that result, so the controller must drain and then clear on a different edge. The wrapper does not perform this control automatically.

## Scope and connections

```text
Aligned K-pixel left/right columns
    → column_sad: abs differences + pipelined column reduction
    → column_sum_buffer: circular history + running total + final SAD adder
    → valid_o, sad_o
```

This is one **fixed-alignment disparity lane**, not the full disparity search. The frontend supplies correctly aligned vertical columns in horizontal sequence. No raw-image line buffer, disparity selection, coordinate tagging, backpressure, Nios V interface or memory master is implemented here.

The existing buffer already contains the final `history_sum + new_column` adder. Adding another arithmetic stage after `sad_o` would double-count rather than fill a missing function. The engine wrapper only connects the two proven modules.

## Ports and defaults

| Port | Contract |
|---|---|
| clk | Rising-edge clock |
| rst_n | Synchronous active-low reset of both components |
| clear_i | Immediate flush of both components; overrides valid_i |
| valid_i | Accept one aligned column pair |
| left_column_i, right_column_i | Packed K×PIXEL_W bits; row j in slice j*PIXEL_W +: PIXEL_W |
| valid_o | Complete K×K window SAD available |
| sad_o | Unsigned window SAD; held when invalid except reset/clear sets zero |

Defaults: K=11 and PIXEL_W=8. Column sums use 12 bits; window sums use 15 bits. Parameters are compile-time constants. The receiver must always consume valid outputs because no ready signal exists.

## Timing and warmup

Let L=ceil(log2(K)). A column accepted at rising edge t reaches:
1. The calculator output just after **t+L**.
2. The buffer output just after **t+L+1**, if it completes a window.

The buffer samples the previous calculator output on an edge; it cannot see that edge's new nonblocking register value until the next edge.

For K=11, accepted input at edge t produces its completed-window result after **t+5**, once ten prior accepted columns exist. This is six register stages including the absolute-difference sampling stage. Thereafter, consecutive valid inputs can produce consecutive outputs, subject to actual fitted timing.

With first accepted input at edge 0 and no gaps: eleventh column is accepted at edge 10, its column sum appears after edge 14, and the first full window appears after edge 15. Warmup counts accepted columns; pipeline travel counts clock edges.

## Row boundary protocol: drain, clear, restart

Normal completion (preserve all pending results):
1. Accept the final input column at edge t.
2. Drive valid_i=0 for **L+1 rising edges**. During this drain, still consume any valid outputs.
3. Assert clear_i on the following separate rising edge (valid_i=0).
4. Deassert clear_i and start the next row on the next edge.

For K=11, drain five rising edges before the clear edge. Do **not** clear on the final-result edge: clear has priority and would discard it.

Abort (discard pending work): assert clear_i immediately. All pipeline entries and horizontal history are invalidated; the next row can begin on the following edge and warms up normally.

No metadata-driven overlap between rows is implemented. A future high-throughput frontend may carry row-boundary markers, but that requires a separately verified protocol.

## Independent engine test

The scoreboard stores raw left and right pixels for the latest K accepted columns and recomputes **all K×K absolute differences** for every eligible window. It does not read the DUT's column sum, buffer history, pointer, or running total. Only the final expected result is delayed to its specified output edge.

Tests include identical/maximal/nonuniform rows, exact per-row output counts after draining, short rows, warmup, bursts/bubbles, early aborts, resets, simultaneous clear/valid and random traffic.

```sh
python scripts/run_tests.py --suite engine
python scripts/run_tests.py --suite engine --case 11:8 --seed 12345 --random-cycles 5000 --vcd
```

Open **Stereo_SAD_Engine.qpf** for component synthesis. The original **Stereo_SAD.qpf** remains the buffer-only project. See [[Hardware Integration]] for synthesis results and limitations.
