# Left Column Delay
#implemented #verified

[[Stereo Frontend]] → [[Right Column Shift Register]] / [[Left Column Delay]] → [[Column Pairing Verification]] → [[Single SAD Engine]] (engine hookup remains planned).

## Pre-RTL contract

| Item | Contract |
|---|---|
| Purpose | Give L[x] the same sampling register as right tap Q[0]; broadcast this L[x] to all future disparity lanes |
| Parameters | K=11, PIXEL_W=8; both positive compile-time integers |
| Input | clk, synchronous active-low rst_n, clear_i, valid_i, column_i[K*PIXEL_W−1:0] |
| Output | valid_o, column_o of the same whole-column width |
| Accepted beat | rst_n=1, clear_i=0, valid_i=1 at the rising edge |
| Pause | Payload holds; output valid becomes zero; no ready/backpressure |
| Reset/clear | At the edge, zero output and valid; discard simultaneous input |
| Latency | One sampling register: sampled at t, visible after t, synchronous consumer samples at t+1 |
| Packing | Row j is [j*PIXEL_W +: PIXEL_W]; no row reordering |

This is **not** a delay of d clocks for disparity d and is not a 32-stage delay. Spatial disparities already live in the right cache. Both sides must receive the same accepted column beat. Independently dropped columns, coordinate tags and row-end control are not handled here.

## Exact source

First SystemVerilog block is the complete source of `rtl/left_column_delay.sv`; the snapshot checker enforces exact equality.

```systemverilog
`timescale 1ns/1ps
`default_nettype none

// Match the right-column cache's single sampling register, not its tap depth.
// Accepted at edge t -> output after edge t; a consumer samples at edge t+1.
// Bubbles hold payload but suppress valid. Reset/clear discards simultaneous input.
module left_column_delay #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    valid_i,
    input  wire [K*PIXEL_W-1:0]     column_i,
    output logic                   valid_o,
    output logic [K*PIXEL_W-1:0]    column_o
);
    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            valid_o <= 1'b0;
            column_o <= '0;
        end else begin
            valid_o <= valid_i;
            if (valid_i) column_o <= column_i;
        end
    end

    // synthesis translate_off
    initial begin
        if (K < 1 || PIXEL_W < 1)
            $fatal(1, "K and PIXEL_W must be positive");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
```

## 1. Interface and width

```systemverilog
module left_column_delay #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    valid_i,
    input  wire [K*PIXEL_W-1:0]     column_i,
    output logic                   valid_o,
    output logic [K*PIXEL_W-1:0]    column_o
);
```

| Code | Why it exists |
|---|---|
| `parameter integer K`, `PIXEL_W` | Elaboration-time column shape, not runtime CSRs |
| `[K*PIXEL_W-1:0]` | A whole vertical column; default 88 bits, never a SAD cost |
| `input wire` | Input connection driven by another module/testbench |
| `output logic` | Outputs assigned procedurally in the sequential block |
| `clk`, `rst_n`, `clear_i` | Shared edge and reset/row-clear contract with the right cache |
| `valid_i`, `valid_o` | Distinguish a meaningful column from a held invalid payload |

`timescale` sets simulation units/precision. `default_nettype none` catches accidental undeclared nets; restore `wire` after the module so unrelated files are unaffected. `#1` belongs in the bench, not this RTL.

## 2. One register and control priority

```systemverilog
    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            valid_o <= 1'b0;
            column_o <= '0;
        end else begin
            valid_o <= valid_i;
            if (valid_i) column_o <= column_i;
        end
    end
```

| Statement | Line reason |
|---|---|
| `always_ff @(posedge clk)` | Storage changes only on a rising edge |
| `if (!rst_n || clear_i)` | Synchronous reset and clear take priority over valid |
| `valid_o <= 1'b0` | Reset/clear cannot accidentally create a usable beat |
| `column_o <= '0` | A deterministic empty payload for testing and row restart |
| `valid_o <= valid_i` | Bubble becomes an invalid output beat even though payload holds |
| `if (valid_i) column_o <= column_i` | Whole-column enable; no payload updates during pauses |
| Nonblocking `<=` | All downstream registers at this edge see the old output; new values become visible afterward |
| Omitted payload assignment on a pause | In a clocked block this means hold a register, not infer a latch |

Do not gate valid by combinational input valid: the status belongs to the registered beat. Do not enable the left path using deep right-tap validity: that would lose L[x] while the right cache warms up.

## 3. Parameter guard

The simulation-only initial guard rejects non-positive widths. `synthesis translate_off/on` excludes the diagnostic from synthesized hardware. The generated bit widths still need legal parameters at elaboration; this guard is not a runtime recovery mechanism.

## Read the timing before the waveform

| Event sampled | Payload after edge | valid after edge |
|---|---|---|
| Reset with valid ff | 00 | 0 |
| Accept 12 | 12 | 1 |
| Accept a5 | a5 | 1 |
| Pause, input changes to ff | a5 | 0 |
| Clear with valid ff | 00 | 0 |
| Accept 3c in a new row | 3c | 1 |

The learning bench deliberately uses K=1/P=8 so you can read these bytes first. The standalone regression checks larger packed columns and every pixel slice.

## Verification

- `tests/rtl/tb_left_column_delay.sv` checks output stability before the rising edge, then payload/valid after NBA updates; directed/reset/pause cases and randomized traffic.
- `tests/rtl/tb_column_pairing.sv` independently indexes accepted right-column history and checks L[x]/R[x−d] both after registration and at the next consumer edge. See [[Column Pairing Verification]].
- `tests/lab/tb_delay_lab.sv` is the small teaching baseline, not a substitute for the production bench. Start [[Hands-on Testbench Lab]].

```sh
python scripts/run_tests.py --suite delay --case 3:8 --vcd
python scripts/run_tests.py --suite pairing --case 3:8:3 --vcd
python scripts/run_testbench_lab.py --check-faults
```

Component synthesis project: `Stereo_SAD_LeftDelay.qpf`; [observed synthesis](../../docs/verification/left-delay-synthesis.md). No fitter, fully constrained Fmax, row-buffer assembly, full disparity map or board test is claimed.

## Next gate, not hidden work

[[Hands-on Testbench Lab]] prepares the existing modules for individual study. After that: agree border/coordinate policy and drain/clear control, then assemble and verify the frontend/bank/top-level wrapper. Coordinate and row-last metadata need matching registered alignment; this payload-only module does not manufacture tags. Keep vertical row-buffer history when clearing horizontal state.
