# Single SAD Engine
#implemented

[[Home]] · [[Pipelined Column SAD Calculator]] · [[Column Sum Buffer]] · [[Testbench Guide]] · [[Disparity Bank]]

Source: [rtl/sad_engine.sv](rtl/sad_engine.sv). Standalone bench: [tb_sad_engine.sv](tests/rtl/tb_sad_engine.sv).

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
