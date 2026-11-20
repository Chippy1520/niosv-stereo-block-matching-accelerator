# Circular Row Buffer
#implemented

[[Home]] · [[Module Blocks.canvas|System blocks]] · [[Accelerator Blocks.canvas|Accelerator blocks]] · [[Stereo Frontend Blocks.canvas|Frontend drill-down]] · [[Stereo Frontend]] · [[Single SAD Engine]] · [[Testbench Guide]]

Source: [rtl/circular_row_buffer.sv](../../rtl/circular_row_buffer.sv). Bench: [tb_circular_row_buffer.sv](../../tests/rtl/tb_circular_row_buffer.sv). Internal memory primitive: [[Row RAM Bank]].

## First, the story — no RTL yet

Imagine a filing cabinet with eleven full-row drawers and a clerk walking across an image one pixel at a time. Each new pixel goes into the drawer assigned to the current image row. At that horizontal position, other drawers hold pixels from earlier rows. Once enough rows have arrived, the clerk reads the ten older pixels and adds the just-arrived pixel as the newest: that bundle is one **vertical column**. At row end, the clerk returns to the left edge and rotates to the next drawer. Old rows are eventually overwritten. A pause leaves the clerk standing in place; an abort returns the clerk to the start and requires fresh rows before another bundle can be trusted.

This cabinet serves **one grayscale image only**. It neither pairs images nor calculates SAD. Its end-of-output-row sign tells a future controller when to drain the downstream engine; the cabinet itself does not wait.

```text
Pixel stream -> horizontal cursor x + rotating write slot
            -> K clocked row RAM banks -> registered older pixels
New pixel -----------------------------> registered newest pixel
Captured write-slot tag + registered pixels -> ordered vertical column
```

**Map for reading code:** drawer → [[Row RAM Bank]]'s `memory`; clerk position → `x`/`slot`; fresh-row count → `rows_filled`; bank results → `bank_columns`; newest bypass → `newest_pixel`; captured drawer identity → `read_slot`; bundle → `column_o`; end-of-row sign → `row_last_o`.

## What this abstraction is

One raster-ordered grayscale stream. The module keeps **K row slots in a ring** and emits a vertical K-pixel column at each accepted x once enough fresh rows overlap.

It does **not** pair images, shift disparity, pad borders, compute SAD or stall the producer. Use two instances later. A future controller must drain [[Single SAD Engine]] after `row_last_o` before the next window-row. **That controller comes last, after datapath review.**

## Review contract — this block only

This replaces the asynchronous pixel-read network with independent synchronous RAM banks. The small bank-module boundary is an internal implementation dependency, **not another accelerator stage**. The existing ports and accepted-pixel/output edge are preserved.

| Item | Contract |
|---|---|
| Dimensions | Compile-time `K`, `PIXEL_W`, `IMG_W`; defaults 11, 8, 640. |
| Input | One P-bit pixel; accepted only with `rst_n && !clear_i && valid_i`. No ready port. |
| Output | K×P bits, oldest row in the low slice. `valid_o` and `row_last_o` describe that column. |
| Read latency | At edge E, bank read registers, newest-pixel register and row-selection tag update together. Their column is available after E; a downstream register samples it at E+1. No additional pipeline edge. |
| Read/write collision | All banks read x on an accepted pixel. The written bank's collision result is **never selected**: newest is a registered bypass. No old/new collision value is assumed. |
| Bubbles | Cursor, bank reads and payload hold. Valid/last go low after the bubble edge. |
| Reset/clear | Synchronous; discard simultaneous valid input. Reset cursor/tags/visibility, **not RAM**. Fresh-row warmup masks stale contents. |
| Out of scope | Second image, disparity alignment, SAD, automatic drain, controller, memory transport, fitted timing and board proof. |

## Complete source

The first SystemVerilog block exactly matches the RTL; `scripts/check_walkthrough.py` checks it. Read [[Row RAM Bank]] for the bank's full source and independent testbench.

```systemverilog
`timescale 1ns/1ps
`default_nettype none

// One image, raster order. A ring of K row slots emits one vertical column
// per accepted pixel once K rows overlap at that x.
// Window row 0 is the oldest and occupies [0 +: PIXEL_W]; row K-1 is pixel_i.
// Accepted at edge t -> registered column after that edge. No backpressure.
// clear_i drops the cursor and output, not RAM. Warmup masks stale storage.
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

    logic [X_W-1:0] x;
    logic [SLOT_W-1:0] slot;
    logic [COUNT_W-1:0] rows_filled;
    wire window_ready = (rows_filled >= COUNT_W'(K - 1));
    wire accept_pixel = rst_n && !clear_i && valid_i;
    wire capture_column = accept_pixel && window_ready;

    // These tags/bypass update with the RAM read registers, not a cycle later.
    logic [SLOT_W-1:0] read_slot;
    logic [PIXEL_W-1:0] newest_pixel;
    logic column_present;
    wire [K*PIXEL_W-1:0] bank_columns;

    genvar b, j;
    generate
        if (K > 1) begin : g_rows
            for (b = 0; b < K; b = b + 1) begin : g_bank
                // Keep the recognized RAM template inside its own module boundary.
                row_ram_bank #(.PIXEL_W(PIXEL_W), .DEPTH(IMG_W)) bank (
                    .clk(clk), .enable_i(accept_pixel),
                    .write_i(slot == SLOT_W'(b)), .address_i(x),
                    .pixel_i(pixel_i),
                    .pixel_o(bank_columns[b*PIXEL_W +: PIXEL_W])
                );
            end
        end else begin : g_no_rows
            // K=1 needs only the registered newest pixel, not image RAM.
            assign bank_columns = '0;
        end

        for (j = 0; j < K; j = j + 1) begin : g_tap
            if (j == K - 1) begin : g_newest
                assign column_o[j*PIXEL_W +: PIXEL_W] =
                    column_present ? newest_pixel : '0;
            end else begin : g_older
                // Rotate registered bank reads using the slot from their edge.
                // The live slot may already have advanced at row end.
                wire [SLOT_W:0] tap_sum = {1'b0, read_slot} + (SLOT_W + 1)'(j + 1);
                wire [SLOT_W:0] tap_slot = (tap_sum >= (SLOT_W + 1)'(K))
                    ? tap_sum - (SLOT_W + 1)'(K) : tap_sum;
                assign column_o[j*PIXEL_W +: PIXEL_W] = column_present
                    ? bank_columns[tap_slot[SLOT_W-1:0]*PIXEL_W +: PIXEL_W] : '0;
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
            read_slot <= '0;
            newest_pixel <= '0;
            column_present <= 1'b0;
        end else begin
            valid_o <= capture_column;
            row_last_o <= capture_column && (x == IMG_W - 1);
            if (capture_column) begin
                read_slot <= slot;
                newest_pixel <= pixel_i;
                column_present <= 1'b1;
            end
            if (accept_pixel) begin
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

## Code walkthrough — read one section, then ask questions

Line numbers refer to the RTL file, not this note. This stores **image rows**, not the engine's column-cost history.

### 1. Interface and cursor — lines 1–35

| RTL line / statement | Why it exists |
|---|---|
| 1–11: timescale, nettype, comments | Simulation units, typo protection, raster order and the absence of automatic row drain. |
| 12–16: `K`, `PIXEL_W`, `IMG_W` | Elaboration-time dimensions, not CPU registers. |
| 17–21: clock/reset/clear/valid/pixel inputs | One stream. Reset and clear take priority over valid. |
| 22–25: `valid_o`, `row_last_o`, `column_o` | K packed pixels and their matching flags. Warmup row ends do not produce row_last. |
| 26–28: `X_W`, `SLOT_W`, `COUNT_W` | Counter widths. Clamp depth-one x/slot to one bit; allow a completed-row count through K. |
| 30: `x` | Horizontal position of the next accepted pixel. |
| 31: `slot` | Physical bank overwritten by the current image row. |
| 32: `rows_filled` | Completed fresh rows since clear, saturating at K. |
| 33: `window_ready` | K−1 complete older rows plus the current pixel make a vertical window. |
| 34: `accept_pixel` | Common cursor/write/read enable; reset and clear cannot write a pixel. |
| 35: `capture_column` | Mature accepted pixel: output tag and bypass may become visible. Earlier reads stay masked. |

### 2. Clocked banks — lines 37–58

| RTL line / statement | Why it exists |
|---|---|
| 37–41: `read_slot`, `newest_pixel`, `column_present`, `bank_columns` | Hold the selector tag, newest bypass and visibility bit alongside the bank results. The packed bus is wiring, not another image store. |
| 43–46: separately declared `genvar b, j`, bank loop | Elaborate K simultaneous bank instances; not K sequential clocks. This syntax also satisfies local Quartus parsing. |
| 47–48: `row_ram_bank #(…) bank` | Keep the measured working RAM inference template inside its own module boundary. Generated local-array candidates did not infer RAM in the tested local configuration. See [[Row RAM Bank]]. |
| 49: `.enable_i(accept_pixel)` | Advance all bank read outputs only on accepted pixels; hold through bubbles and reset/clear. |
| 50: `.write_i(slot == SLOT_W'(b)), .address_i(x)` | Only the bank matching slot writes; every bank addresses the same horizontal x. Cast b to the slot comparison width. |
| 51–53: pixel input and fixed bank slice | Route incoming pixel and each clocked bank result. The write bank's read result is unspecified, but the parent never selects it. |
| 54–58: K=1 branch | No older rows exist; omit all RAM and use the newest-pixel register only. |

**Why no RAM reset?** Resetting every word can prevent embedded-memory mapping. Instead, reset visibility and require enough fresh rows before exposing another column.

### 3. Physical banks to ordered rows — lines 60–74

| RTL line / statement | Why it exists |
|---|---|
| 60–63: `g_tap`, `g_newest`, `newest_pixel` | One slice per window row. The newest slice uses a registered pixel, never live `pixel_i`. |
| 64–67: `g_older`, `tap_sum` using `read_slot` | Select with the slot captured on the read edge. The live slot may already have rotated at the final x. Extra carry width prevents overflow. |
| 68–69: conditional subtraction | Wrap a bounded slot+j+1 sum by subtracting K once; no general modulo divider. |
| 70–71: `column_present ? bank_columns[…] : '0` | Select among K clocked P-bit results, not IMG_W asynchronous words. Force zeros while storage is untrusted. Oldest row occupies the low slice. |
| 72–74: block endings | This output is a combinational mux of registered values; there is no extra output pipeline register. |

At fixed x with K=3:

| Incoming image row | Captured write slot | Oldest | Middle | Newest |
|---|---:|---|---|---|
| 0, 1 | 0, 1 | Invalid warmup | Invalid warmup | Invalid warmup |
| 2 | 2 | bank 0 output | bank 1 output | registered current pixel |
| 3 | 0 | bank 1 output | bank 2 output | registered current pixel |
| 4 | 1 | bank 2 output | bank 0 output | registered current pixel |

### 4. Reset, visibility and row advance — lines 76–106

| RTL line / statement | Why it exists |
|---|---|
| 76–85: clocked reset/clear branch | Reset cursor, warmup count, flags, tag and bypass; clear `column_present`. Neither RAM contents nor bank read registers are reset. |
| 86–88: `valid_o <= capture_column`, `row_last_o <= …` | Qualify this edge's output. A bubble clears both flags after the edge. |
| 89–93: capture `read_slot`, `newest_pixel`, `column_present` | Capture the pre-edge slot and pixel with the bank read. Leave visibility set through bubbles so payload holds. |
| 94–96: accepted final x wraps | Move only for accepted pixels; wrap x to zero at row end, including width one. |
| 97–99: slot increment/wrap | K=1 stays at zero; otherwise wrap at K−1, not binary overflow. Non-power-of-two K works. |
| 100: saturating `rows_filled` | Count complete fresh rows. The first valid column is x=0 of image row K−1. |
| 101–106: nonfinal x increment and block endings | Advance x for nonfinal accepted pixels. Unassigned cursor/payload state holds on bubbles. |

Before edge E, a consumer sees the preceding output. After E, bank values, captured tag, newest pixel and valid settle to the current output. A downstream register consumes it at E+1. Clear discards a simultaneous pixel; it is not a normal row-drain operation.

### 5. Guards — lines 108–115

`translate_off/on` surrounds a simulation-only parameter check; zero/negative dimensions cause `$fatal`, not reset hardware. The module ends and restores the default nettype. No controller or SAD calculation follows.

## Ports

`clk` is rising-edge. `rst_n` is synchronous active-low reset. `clear_i` resets stream progress and visibility and wins over `valid_i`. `pixel_i` is one grayscale pixel. `valid_o` means the K-pixel column is complete. `row_last_o` only accompanies the final x of a valid window-row. `column_o[j*PIXEL_W +: PIXEL_W]` holds window row j, oldest first; payload holds during bubbles and becomes zero on reset/clear.

## Timing

An accepted pixel at edge t produces its column after that same edge once warmup is complete. Warmup counts **completed rows, not clocks**. Ends of warmup rows do not pulse `row_last_o`. RAM read latency is matched by the bypass and captured selector; it does not add another edge to the module interface.

## Storage

For K>1, bank b's words are `g_rows.g_bank[b].bank.memory[x]`. Every accepted pixel clocks all bank reads and writes only its selected bank. The other K−1 banks supply older taps; newest comes from `newest_pixel`. Keeping K banks preserves the existing rotating-row organization rather than introducing a new K−1-bank overwrite algorithm in this review.

The production K=11, width=640 implementation passes Analysis & Synthesis with **11 M9K RAM nodes, 56,320 logical memory bits, 697 logic elements and 33 registers**. See [row-buffer synthesis evidence](../../docs/verification/row-buffer-synthesis.md). RAM attributes alone did not prove inference. This is not fitted timing or board proof; the earlier width-16 smoke and full-width failures remain historical baselines.

## Run

```sh
python scripts/run_tests.py --suite row-bank
python scripts/run_tests.py --suite row
python scripts/run_tests.py --suite row --case 11:8:640
```

Eight bank cases are checked independently before the ten parent cases. The parent suite includes 640×480 and 641×480 raster streams with bubbles, clear/warmup/restart and random traffic. Its scoreboard rebuilds columns from a flat source image, not the DUT's ring. It also checks output stability before/after rising edges; pseudorandom source pixels avoid aliases hidden by wrapping 8-bit ramps.

The Questa GUI macro supports `part=row-bank` and `part=row`; see [[Testbench Guide]]. The fresh automated native run was blocked by an already-open Questa process consuming the node-locked license. That user process was not closed. The passing current simulations are Icarus, not a claimed fresh native Questa simulation pass.

This serial reference has been reviewed. The current [[Stereo Frontend]] instead uses [[Packed Circular Row Buffer|independently packed-loaded stores]]; do not instantiate both storage paths. See the existing [[Accelerator Blocks.canvas]] and [[Stereo Frontend Blocks.canvas]] for their roles. Interactive review of the complete compute datapath precedes publishing; the autonomous controller remains future work in [[Project Plan]].
