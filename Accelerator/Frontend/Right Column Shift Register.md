# Right Column Shift Register
#implemented

[[Home]] → [[Accelerator Architecture]] → [[Stereo Frontend]] → this module.
[[Disparity Bank]] · [[Circular Row Buffer]] · [[Testbench Guide]]

Source: [right_column_shift.sv](../../rtl/right_column_shift.sv). Independent bench: [tb_right_column_shift.sv](../../tests/rtl/tb_right_column_shift.sv).

## Story first

The right row buffer hands us a **whole vertical column** at horizontal position x. Put that column on the first shelf, move the previous column to the second shelf, and continue. Shelf d therefore holds R[x−d]. All shelves move together on one accepted input. When the source pauses, nobody moves: the next column is still the next horizontal position, not an extra disparity gap.

An occupancy marker remembers which shelves contain columns from this row. A separate beat marker says whether a new input arrived this clock. Both must be true before a shelf may feed an engine. A physically zero-filled shelf is not a valid border sample. Clear empties the shelves and their markers; do that between output rows so the preceding row cannot leak into the next.

```text
right row buffer → R[x] + valid → Q[0] → Q[1] → ... → Q[TAPS−1]
                                R[x]   R[x−1]       R[x−(TAPS−1)]
                                │       │             │
                                └──── direct disparity taps ────┘
left row buffer → matching one-register left alignment (NEXT, not implemented)
                                → pair L[x] with Q[d] → engine d (planned)
```

## Pre-RTL contract and boundaries

| Item | Contract |
|---|---|
| Parameters | K=11, PIXEL_W=8, TAPS=32 by default; synthesis-time, positive integers |
| column_i | K*PIXEL_W bits; internal row order unchanged from circular_row_buffer |
| columns_o | TAPS*K*PIXEL_W bits; tap d at `[d*COL_W +: COL_W]` |
| tap_valid_o | TAPS bits; bit d corresponds to the same packed tap d |
| Sampling | Input accepted at rising edge t; registered Q and valid mask visible after that edge |
| Pauses | valid_i=0: hold every column, output all valid bits zero; no horizontal advancement |
| Warmup | First column: only tap 0 valid. Tap d becomes valid on accepted column d+1 |
| Reset/clear | Synchronous active-low rst_n / active-high clear_i; either discards simultaneous input |
| Row boundary | Caller must clear between complete output rows; no automatic row_last input |
| Meaning of x | Consecutive accepted columns of one row; dropped positions cannot be represented as pauses |
| Exclusions | Left delay, coordinate tags, row controller, engine bank and their wiring |

Defaults give **88-bit columns** and a **2816-bit packed tap bus**. This is an internal parallel bus, not board I/O. Reading the tap from an engine at a later edge adds the normal register handoff. A matching left register and delayed metadata are mandatory before integration.

## Complete source — exact snapshot

```systemverilog
`timescale 1ns/1ps
`default_nettype none

// Shift whole K-pixel columns, not pixels or SAD costs. Tap d is R[x-d].
// Accepted at edge t -> registered taps after that edge; no backpressure.
// valid_i=0 holds history and suppresses every output-valid bit for that beat.
// x advances ONLY on accepted columns. Clear between rows; clear discards input.
// A separate one-register left alignment is required before engine pairing.
module right_column_shift #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer TAPS = 32
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clear_i,
    input  wire                         valid_i,
    input  wire [K*PIXEL_W-1:0]          column_i,
    output wire [TAPS-1:0]              tap_valid_o,
    output wire [TAPS*K*PIXEL_W-1:0]     columns_o
);
    localparam integer COL_W = K * PIXEL_W;
    logic [COL_W-1:0] columns [0:TAPS-1];
    logic [TAPS-1:0] occupied;
    logic beat_valid;
    integer d;

    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            occupied <= '0;
            beat_valid <= 1'b0;
            for (d = 0; d < TAPS; d = d + 1) columns[d] <= '0;
        end else begin
            beat_valid <= valid_i;
            if (valid_i) begin
                columns[0] <= column_i;
                occupied[0] <= 1'b1;
                for (d = 1; d < TAPS; d = d + 1) begin
                    columns[d] <= columns[d-1];
                    occupied[d] <= occupied[d-1];
                end
            end
        end
    end

    assign tap_valid_o = occupied & {TAPS{beat_valid}};
    genvar tap;
    generate
        for (tap = 0; tap < TAPS; tap = tap + 1) begin : g_output
            assign columns_o[tap*COL_W +: COL_W] = columns[tap];
        end
    endgenerate

    // synthesis translate_off
    initial begin
        if (K < 1 || PIXEL_W < 1 || TAPS < 1)
            $fatal(1, "K, PIXEL_W and TAPS must be positive");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
```

## Code walkthrough — code and reasons side by side

Source line numbers below refer to the complete RTL above. Structural `end`/`endgenerate` lines close their shown scopes and do not introduce extra clocks.

### 1. Interface and state (lines 1–26)

```systemverilog
module right_column_shift #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer TAPS = 32
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clear_i,
    input  wire                         valid_i,
    input  wire [K*PIXEL_W-1:0]          column_i,
    output wire [TAPS-1:0]              tap_valid_o,
    output wire [TAPS*K*PIXEL_W-1:0]     columns_o
);
    localparam integer COL_W = K * PIXEL_W;
    logic [COL_W-1:0] columns [0:TAPS-1];
    logic [TAPS-1:0] occupied;
    logic beat_valid;
    integer d;
```

| Lines | Why they are written this way |
|---|---|
| 1–2, 61 | Simulation units and implicit-net protection; final directive restores the surrounding compilation default |
| 4–8 | State the whole-column, accepted-position, one-register and separate-left-alignment contract |
| 9–13 | Elaboration parameters select spatial hardware dimensions, not runtime software registers |
| 14–17 | Clock, synchronous reset/clear and accepted-column qualifier; no ready/backpressure |
| 18 | One entire vertical column; no slicing into individual pixels during the shift |
| 19–21 | One valid bit per disparity and a flattened parallel column bus |
| 22 | COL_W names the width of a single shelf |
| 23 | TAPS payload registers, not image-row memory or SAD-cost history |
| 24 | occupied remembers valid history across source pauses |
| 25 | beat_valid tracks the current registered output beat, not cumulative occupancy |
| 26 | Integer loop index elaborates/controls fixed register assignments; it is not a runtime disparity counter |

### 2. Reset and pause behavior (lines 28–35)

```systemverilog
    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            occupied <= '0;
            beat_valid <= 1'b0;
            for (d = 0; d < TAPS; d = d + 1) columns[d] <= '0;
        end else begin
            beat_valid <= valid_i;
            if (valid_i) begin
```

| Lines | Explanation |
|---|---|
| 28 | All state changes on rising edges |
| 29 | Reset or clear has priority over valid_i; reset is synchronous despite the `_n` suffix |
| 30–31 | Invalidate history and the current beat so stale output cannot be consumed |
| 32 | Explicitly zero payload registers too; this favors simple deterministic behavior over a reset-free RAM implementation |
| 33–34 | Normal clocks always sample valid_i into the beat marker, including zero on a pause |
| 35 | Only accepted columns may change payload or occupancy; old columns do not drift during pauses |

### 3. Shift one whole column per accepted beat (lines 36–44)

```systemverilog
                columns[0] <= column_i;
                occupied[0] <= 1'b1;
                for (d = 1; d < TAPS; d = d + 1) begin
                    columns[d] <= columns[d-1];
                    occupied[d] <= occupied[d-1];
                end
            end
        end
    end
```

| Lines | Explanation |
|---|---|
| 36–37 | Shelf 0 receives the new column and is now occupied |
| 38 | Higher shelves update in parallel; TAPS=1 makes this loop empty without illegal part-selects |
| 39 | Nonblocking `<=` reads each previous shelf's **pre-edge** value, so one column advances exactly one shelf, not through the entire chain |
| 40 | Occupancy moves alongside the same column; unfilled deep shelves stay invalid |
| 41–44 | Close shift, accepted-input, normal-clock and sequential scopes |

### 4. Qualify and flatten outputs (lines 46–52)

```systemverilog
    assign tap_valid_o = occupied & {TAPS{beat_valid}};
    genvar tap;
    generate
        for (tap = 0; tap < TAPS; tap = tap + 1) begin : g_output
            assign columns_o[tap*COL_W +: COL_W] = columns[tap];
        end
    endgenerate
```

| Lines | Explanation |
|---|---|
| 46 | `{TAPS{beat_valid}}` replicates one bit; bitwise AND with occupied qualifies each tap independently |
| 47–49 | Separately declared genvar supports Quartus Lite 22.1; generate creates parallel output wiring |
| 50 | Indexed part-select flattens shelf tap without another register, mux or latency |
| 51–52 | End the generated wiring; nothing shifts here |

### 5. Simulation parameter guard (lines 54–59)

```systemverilog
    // synthesis translate_off
    initial begin
        if (K < 1 || PIXEL_W < 1 || TAPS < 1)
            $fatal(1, "K, PIXEL_W and TAPS must be positive");
    end
    // synthesis translate_on
```

`translate_off/on` excludes the initial guard from synthesized hardware. It fails fast if any dimension is nonpositive. The surrounding `endmodule` closes this component.

## What happens to three taps?

Values below are **after** each sampling edge; bit order is `[2:0]`.

| Input | Q[0], Q[1], Q[2] | valid[2:0] |
|---|---|---|
| Reset | 0, 0, 0 | 000 |
| Accept A | A, 0, 0 | 001 |
| Accept B | B, A, 0 | 011 |
| Pause (input may change) | B, A, 0 | 000 |
| Accept C | C, B, A | 111 |
| Clear with valid D | 0, 0, 0 | 000; D discarded |
| Accept E, new row | E, 0, 0 | 001 |

A tap-valid bit means the **right column** exists, not that a full K-column SAD window is ready. Lane d's horizontal history still needs K accepted column pairs. Do not use zero padding as a valid stereo border.

## Verification and scope

The standalone bench stores an append-only log of accepted columns and indexes `history[count−1−d]`; it does not duplicate the RTL shift chain or inspect DUT internals. It checks the complete payload bus and validity mask after every edge, including held invalid data. Directed tests cover single tap, odd tap counts, every clear/warmup depth, long/full history, bubbles, zero/maximum data, and reset/clear with simultaneous valid. Random traffic supplies changing data, pauses, reset and clear.

```sh
python scripts/run_tests.py --suite shift
python scripts/run_tests.py --suite shift --case 11:8:32 --seed 12345 --random-cycles 10000 --vcd
python scripts/check_walkthrough.py
python scripts/check_test_sensitivity.py
```

`--case K:P:T` overrides tap count; a shift-only `K:P` case defaults to 32 taps. Fault checks deliberately shift during pauses, ignore occupancy, and ignore clear; the real RTL is not mutated.

Open `Stereo_SAD_RightShift.qpf` for component Analysis & Synthesis. [Synthesis evidence](../../docs/verification/right-shift-synthesis.md) describes observed resources and limits. No fitted timing, left alignment, frontend integration, bank throughput or board success is claimed. Existing frontend canvases still describe the planned assembly; their local layouts are not changed by this standalone milestone.

## Next integration gate

Implement the matching left-column/valid alignment separately. Then verify paired coordinates and border masks before feeding engines. The row controller must account for the new frontend register handoff when draining from the row-buffer side; the existing engine-only drain contract is measured at the engine inputs, not upstream of this cache. Keep vertical row-buffer history while clearing horizontal cache/engine history between output rows.
