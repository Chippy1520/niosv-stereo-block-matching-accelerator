# Circular Row Buffer
#implemented

[[Home]] · [[Module Blocks.canvas|Module blocks]] · [[Image Line Buffers]] · [[Single SAD Engine]] · [[Testbench Guide]]

Source: [rtl/circular_row_buffer.sv](rtl/circular_row_buffer.sv). Bench: [tb_circular_row_buffer.sv](tests/rtl/tb_circular_row_buffer.sv).

## What this abstraction is

One grayscale stream. Pixels arrive left to right, then the next row. The module keeps **K row slots in a ring** and, once those rows overlap, emits the vertical column at the current x.

It does **not** pair left and right images, shift a disparity, pad borders, or compute SAD. Use two instances later. A future controller must drain [[Single SAD Engine]] after `row_last_o` before the next window-row; this module does not insert that gap.

## Complete source

```systemverilog
`timescale 1ns/1ps
`default_nettype none

// One image, raster order. A ring of K row slots emits one vertical column
// per accepted pixel once K rows overlap at that x.
// Window row 0 is the oldest and occupies [0 +: PIXEL_W]; row K-1 is pixel_i.
// Accepted at edge t -> registered column after that edge. No backpressure.
// clear_i drops the cursor and the output. Slots are never read until rewritten.
// This is not disparity alignment, pairing, or the SAD engine. Instantiate twice.
// row_last_o marks the last x of a complete window-row. A later controller must
// drain the engine before the next row; this module does not insert that gap.
module circular_row_buffer #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer IMG_W = 640
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       clear_i,
    input  wire                       valid_i,
    input  wire [PIXEL_W-1:0]         pixel_i,
    output logic                      valid_o,
    output logic                      row_last_o,
    output logic [K*PIXEL_W-1:0]      column_o
);
    localparam integer X_W = (IMG_W <= 1) ? 1 : $clog2(IMG_W);
    localparam integer SLOT_W = (K <= 1) ? 1 : $clog2(K);
    localparam integer COUNT_W = $clog2(K + 1);

    // Functional row store. Combinational column readout is the abstraction;
    // mapping each row to synchronous RAM is a later fitting pass.
    logic [PIXEL_W-1:0] row_mem [0:K-1][0:IMG_W-1];
    logic [X_W-1:0] x;
    logic [SLOT_W-1:0] slot;
    logic [COUNT_W-1:0] rows_filled;
    wire window_ready = (rows_filled >= COUNT_W'(K - 1));

    wire [K*PIXEL_W-1:0] column_next;
    genvar j;
    generate
        for (j = 0; j < K; j = j + 1) begin : g_tap
            if (j == K - 1) begin : g_newest
                assign column_next[j*PIXEL_W +: PIXEL_W] = pixel_i;
            end else begin : g_older
                // slot is 0..K-1 and this offset is 1..K-1, so one subtract wraps it.
                // A wide % would make Quartus infer a divider.
                wire [SLOT_W:0] tap_sum = {1'b0, slot} + (SLOT_W + 1)'(j + 1);
                wire [SLOT_W:0] tap_slot = (tap_sum >= (SLOT_W + 1)'(K))
                    ? tap_sum - (SLOT_W + 1)'(K) : tap_sum;
                assign column_next[j*PIXEL_W +: PIXEL_W] =
                    row_mem[tap_slot[SLOT_W-1:0]][x];
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            x <= '0;
            slot <= '0;
            rows_filled <= '0;
            valid_o <= 1'b0;
            row_last_o <= 1'b0;
            column_o <= '0;
        end else begin
            valid_o <= 1'b0;
            row_last_o <= 1'b0;
            if (valid_i) begin
                row_mem[slot][x] <= pixel_i;
                if (window_ready) begin
                    valid_o <= 1'b1;
                    row_last_o <= (x == IMG_W - 1);
                    column_o <= column_next;
                end
                if (x == IMG_W - 1) begin
                    x <= '0;
                    if (K == 1) slot <= '0;
                    else if (slot == K - 1) slot <= '0;
                    else slot <= slot + 1'b1;
                    if (rows_filled < K) rows_filled <= rows_filled + 1'b1;
                end else begin
                    x <= x + 1'b1;
                end
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (K < 1 || PIXEL_W < 1 || IMG_W < 1)
            $fatal(1, "K, PIXEL_W and IMG_W must be positive");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
```

## Ports

| Port | Kind | Meaning |
|---|---|---|
| clk | control | Rising-edge clock |
| rst_n | control | Synchronous active-low reset |
| clear_i | control | Drop the cursor and the registered output. Wins over valid_i |
| valid_i | input | Accept pixel_i. Bubbles do not advance x |
| pixel_i | input | One grayscale pixel |
| valid_o | output | column_o is a complete K-pixel window |
| row_last_o | output | That column is the last x of a window-row. Zero when invalid |
| column_o | output | Oldest window row in the low slice. Held while invalid, except reset/clear zeros it |

Window row `j` occupies `[j*PIXEL_W +: PIXEL_W]`. Row 0 is the oldest image row in the window. Row `K-1` is the pixel just accepted.

## Timing

An accepted pixel at rising edge `t` produces its registered column after that same edge. There is no adder-tree delay here. Warmup counts **completed rows**, not clocks: the first column is the first pixel of image row `K-1`.

`row_last_o` is only asserted with `valid_o`. Ends of the warmup rows do not pulse it.

## Storage

`row_mem[slot][x]` is the functional store. The newest tap is `pixel_i`, because the slot being written still holds the pixel from K rows ago until the write lands. Older taps read the other slots at the same x. After clear, those slots are not read until this frame rewrites them.

Combinational readout of the column is intentional for this first abstraction. Quartus may map it to logic rather than M9K. A later pass can give each row a synchronous RAM without changing this port list.

The functional default is `IMG_W=640`. Analysis & Synthesis of that default did not finish within 300 seconds. `Stereo_SAD_RowBuffer.qpf` therefore synthesizes `circular_row_buffer_synth`, the same module with `IMG_W=16`. That run passed with 0 errors and 0 warnings and reported 3156 logic cells before fitting. That count is not the 640-wide design, and it is not an Fmax.

## Run

```sh
python scripts/run_tests.py --suite row
python scripts/run_tests.py --suite row --case 11:8:8 --vcd
```

The scoreboard stores a flat image and rebuilds each column from original pixels. It does not copy the ring pointer. Open **Stereo_SAD_RowBuffer.qpf** for component synthesis. See [[Module Blocks.canvas]] for the port-level interconnect.
