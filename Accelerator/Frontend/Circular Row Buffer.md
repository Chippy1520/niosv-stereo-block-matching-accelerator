# Circular Row Buffer
#implemented

[[Home]] · [[Module Blocks.canvas|System blocks]] · [[Accelerator Blocks.canvas|Accelerator blocks]] · [[Stereo Frontend Blocks.canvas|Frontend drill-down]] · [[Image Line Buffers]] · [[Single SAD Engine]] · [[Testbench Guide]]

Source: [rtl/circular_row_buffer.sv](../../rtl/circular_row_buffer.sv). Bench: [tb_circular_row_buffer.sv](../../tests/rtl/tb_circular_row_buffer.sv).

## First, the story — no RTL yet

Imagine a filing cabinet with eleven full-row drawers and a clerk walking across an image one pixel at a time. The clerk drops each new pixel into the drawer assigned to the current image row. At a given horizontal position, the cabinet still holds pixels from earlier rows at that same position. Once enough rows have arrived, the clerk reads the ten older pixels and adds the just-arrived pixel as the newest: that bundle is one **vertical column**. At the end of the image row, the clerk returns to the left edge and rotates to the next drawer. Eventually the drawers circle back and old rows are overwritten. An input pause leaves the clerk standing in place; an abort returns the clerk to the start and requires enough fresh rows before any bundle can be trusted again.

This cabinet works for **one grayscale image only**. It neither pairs two images nor calculates differences or the SAD score. An end-of-output-row sign tells a future controller when to drain the downstream engine; the cabinet itself does not wait.

```text
One image's pixel stream -> x position, rotating row slot
                        -> old pixels from other slots at the same x
New pixel ---------------------------------------------> newest tap
Old taps + newest tap -> registered vertical column (after warmup)
```

**Map for reading code:** drawer → `row_mem`; clerk position → `x`/`slot`; fresh-row count → `rows_filled`; newest bypass → `pixel_i`; resulting bundle → `column_o`; end-of-row sign → `row_last_o`. Below, every important statement is traced back to this picture.

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

## Code walkthrough — the row ring, with RTL beside each explanation

Line numbers below refer to [rtl/circular_row_buffer.sv](../../rtl/circular_row_buffer.sv). This **one-image** pixel-row ring is distinct from the engine's circular *column-cost* history.

### 1. Interface: what the clerk receives and emits (lines 1–25)

```systemverilog
`timescale 1ns/1ps
`default_nettype none
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
```

- **Lines 1–2:** Simulation timing and implicit-net typo protection; neither is a row store.
- **Lines 4–11 (comments in full source):** Define raster order, oldest-to-newest packing, one-edge registration, and the fact that *some future controller* must drain a downstream engine after a complete output row. They do not implement a drain.
- **Lines 12–16:** `K` is the number of image rows represented in one vertical column; `PIXEL_W` is bits per pixel; `IMG_W` is accepted pixels per row. These are fixed at elaboration, not CPU-controlled at runtime.
- **Lines 17–21:** Clock, synchronous reset/clear, acceptance stamp, and a single grayscale input pixel. With `valid_i=0` the clerk must not move.
- **Lines 22–25:** Output-valid, last-x-of-complete-window-row marker, and packed vertical column. Row zero occupies the low slice; current `pixel_i` occupies row K−1. The flag marks an output column, not every incoming warmup-row boundary.

### 2. State and warmup (lines 26–36)

```systemverilog
localparam integer X_W = (IMG_W <= 1) ? 1 : $clog2(IMG_W);
localparam integer SLOT_W = (K <= 1) ? 1 : $clog2(K);
localparam integer COUNT_W = $clog2(K + 1);
logic [PIXEL_W-1:0] row_mem [0:K-1][0:IMG_W-1];
logic [X_W-1:0] x;
logic [SLOT_W-1:0] slot;
logic [COUNT_W-1:0] rows_filled;
wire window_ready = (rows_filled >= COUNT_W'(K - 1));
```

- **Line 26:** Counter width for the pixel position; the one-pixel-row case still has a legal one-bit counter.
- **Line 27:** Counter width for the rotating row slot; K=1 still has a legal bit of storage.
- **Line 28:** Enough bits to count through K completed rows before saturation.
- **Lines 30–32:** Defines K rows of IMG_W pixel positions. The comment explicitly calls this a **functional** combinational-read model; it does not promise M9K inference at full image width.
- **Lines 33–34:** `x` is the position within one raster row; `slot` is the current drawer to overwrite when accepting pixels.
- **Lines 35–36:** `rows_filled` counts *completed rows*; after K−1 rows, the incoming pixel at the current x can finish the first K-row vertical window. Old memory bits are not trusted before this condition.

### 3. The parallel tap wiring (lines 38–54)

```systemverilog
wire [K*PIXEL_W-1:0] column_next;
genvar j;
generate
    for (j = 0; j < K; j = j + 1) begin : g_tap
        if (j == K - 1) begin : g_newest
            assign column_next[j*PIXEL_W +: PIXEL_W] = pixel_i;
        end else begin : g_older
            wire [SLOT_W:0] tap_sum = {1'b0, slot} + (SLOT_W + 1)'(j + 1);
            wire [SLOT_W:0] tap_slot = (tap_sum >= (SLOT_W + 1)'(K))
                ? tap_sum - (SLOT_W + 1)'(K) : tap_sum;
            assign column_next[j*PIXEL_W +: PIXEL_W] =
                row_mem[tap_slot[SLOT_W-1:0]][x];
        end
    end
endgenerate
```

- **Lines 38–41:** Define one packed candidate column and *K simultaneous taps*. The generate loop constructs hardware connections; it does not take K clock cycles.
- **Lines 42–43:** The newest tap directly uses the incoming `pixel_i`, because `row_mem[slot][x]` still contains the row K steps old until this edge's write is registered. With K=1, this is the **only** tap.
- **Lines 44–47:** For an older output row `j`, calculate `slot+j+1` with one extra bit so arithmetic cannot truncate. The oldest output row (`j=0`) lives in the drawer *after* the one being overwritten.
- **Lines 48–49:** If that index reaches K, subtract K **once**. The possible sum is below 2K, so one subtract suffices; a wide `% K` would infer an expensive divider.
- **Lines 50–51:** Read that selected row at the *same x* as every other tap. This assembles a vertical column rather than neighboring pixels in one row.
- **Lines 52–54:** End conditional and generated hardware. The ordered packed slices place oldest row at index zero and newest at index K−1.

**K=3 drawer map at a fixed x (the arrows are tap selection, not clock cycles):**

```text
incoming image row      write slot     row 0 output      row 1 output      row 2 output
row 0                   0              —                 —                 —
row 1                   1              —                 —                 —
row 2                   2              row_mem[0][x]     row_mem[1][x]     pixel_i
row 3                   0              row_mem[1][x]     row_mem[2][x]     pixel_i
row 4                   1              row_mem[2][x]     row_mem[0][x]     pixel_i
```

The output remains invalid for warmup rows 0 and 1. Each drawer rotates only after *IMG_W accepted pixels*, not after a bubble.

### 4. Reset, accept, output and row rotation (lines 56–85)

```systemverilog
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
```

- **Lines 56–64:** At an edge, reset or clear first zeros the cursor, warmup count, and registered outputs. It *does not clear all pixel storage*, saving a bulk erase; warmup prevents stale rows from becoming valid.
- **Lines 65–67:** Every non-clear edge defaults output flags low. If `valid_i=0`, no write or cursor movement follows; `column_o` retains its old bits, but is invalid this edge.
- **Line 68:** Write the just-accepted pixel into the current drawer/position. Other row slots retain their previous pixels.
- **Lines 69–73:** Once warmed up, capture `column_next`, assert valid, and mark the final accepted x. Nonblocking assignments read the *old* row-memory values here while the newest tap bypasses that memory with `pixel_i`.
- **Lines 74–79:** At the final accepted x, return to x=0, rotate/wrap `slot` (or keep it zero for K=1), and saturate completed-row count at K.
- **Lines 80–85:** Otherwise advance x by one, and close the sequential blocks. A bubble executes neither path inside `valid_i`.

### 5. Simulation guards and what this module cannot do (lines 87–94)

```systemverilog
// synthesis translate_off
initial begin
    if (K < 1 || PIXEL_W < 1 || IMG_W < 1)
        $fatal(1, "K, PIXEL_W and IMG_W must be positive");
end
// synthesis translate_on
endmodule
`default_nettype wire
```

- **Lines 87–92:** Reject dimensions that could not describe a real row/window in simulation; excluded from the synthesized datapath.
- **Lines 93–94:** Close module and restore nettype. No second image, disparity alignment, or SAD arithmetic is hidden here.

**Edge handoff:** the row buffer registers a valid column *after* its accepted pixel edge; a downstream registered column calculator samples that registered column on the **following** edge. `row_last_o` alone does not stall the next raster row or drain the SAD engine. That scheduling still needs a controller.

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

The scoreboard stores a flat image and rebuilds each column from original pixels. It does not copy the ring pointer. Open **Stereo_SAD_RowBuffer.qpf** for component synthesis. See [[Accelerator Blocks.canvas]] for its place in the proposed datapath and [[Stereo Frontend Blocks.canvas]] for the row-buffer/tap interconnect.
