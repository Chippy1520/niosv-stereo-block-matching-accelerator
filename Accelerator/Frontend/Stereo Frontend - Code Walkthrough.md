# Stereo Frontend — Code Walkthrough

[[Stereo Frontend]] · [[Circular Row Buffer]] · [[Right Column Shift Register]] · [[Verification]] · [[Testbench Guide]]

Source of truth: `rtl/stereo_frontend.sv`. Interface and scheduling authority: `docs/packed-frontend-contract.md`. This is the packed-load **datapath**, not a raster controller, FIFO, ownership manager, SDRAM interface or SAD/disparity backend.

**Caller protocol:** start each row at x=0, accept consecutive x values with no skips/duplicates, hold y/oldest bank fixed within that row, and clear horizontal history between rows. Left/right loads have separate enables/data but shared bank/word addresses. The datapath does not validate ownership, this coordinate protocol or overridden tag widths. Normal row clear follows the final store handoff; asserting clear with a pending handoff aborts it. These are explicit integration obligations, not evidence that a controller exists.

## Exact full RTL

The first SystemVerilog block is the complete source, including defaults, public widths, comments and simulation-only parameter check.

```systemverilog
`timescale 1ns/1ps
`default_nettype none

// Datapath only: the caller owns loading, bank lifetime and read scheduling.
// Read at t -> stored columns after t -> paired columns/tags after t+1.
// A downstream clocked consumer samples that pair at t+2.
module stereo_frontend #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer IMG_W = 640,
    parameter integer IMG_H = 480,
    parameter integer TAPS = 32,
    parameter integer SPARE_ROWS = 1,
    parameter integer X_W = (IMG_W <= 1) ? 1 : $clog2(IMG_W),
    parameter integer Y_W = (IMG_H <= 1) ? 1 : $clog2(IMG_H),
    parameter integer BANK_W = (K+SPARE_ROWS <= 1) ? 1 : $clog2(K+SPARE_ROWS),
    parameter integer WORD_AW = ((IMG_W+3)/4 <= 1) ? 1 : $clog2((IMG_W+3)/4)
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          frame_clear_i,
    input  wire                          row_clear_i,
    input  wire                          left_write_valid_i,
    input  wire                          right_write_valid_i,
    input  wire [BANK_W-1:0]             write_bank_i,
    input  wire [WORD_AW-1:0]            write_word_i,
    input  wire [4*PIXEL_W-1:0]          left_write_data_i,
    input  wire [4*PIXEL_W-1:0]          right_write_data_i,
    input  wire                          read_valid_i,
    input  wire [X_W-1:0]                read_x_i,
    input  wire [Y_W-1:0]                read_y_i,
    input  wire [BANK_W-1:0]             read_oldest_i,
    output wire                          left_valid_o,
    output wire [K*PIXEL_W-1:0]          left_column_o,
    output wire [TAPS-1:0]               right_valid_o,
    output wire [TAPS*K*PIXEL_W-1:0]     right_columns_o,
    output logic [X_W-1:0]              x_o,
    output logic [Y_W-1:0]              y_o,
    output logic                         row_last_o
);
    localparam integer COL_W = K * PIXEL_W;
    wire history_clear = frame_clear_i || row_clear_i;
    wire read_enable = read_valid_i && !history_clear;
    wire left_column_valid, right_column_valid;
    wire [COL_W-1:0] left_stored_column, right_stored_column;
    logic [X_W-1:0] pending_x;
    logic [Y_W-1:0] pending_y;

    // Row clear leaves RAM and the independent load path untouched.
    // Frame clear/reset have priority inside both stores, including over writes.
    packed_circular_row_buffer #(
        .K(K), .PIXEL_W(PIXEL_W), .IMG_W(IMG_W), .SPARE_ROWS(SPARE_ROWS),
        .X_W(X_W), .BANK_W(BANK_W), .WORD_AW(WORD_AW)
    ) left_rows (
        .clk(clk), .rst_n(rst_n), .clear_i(frame_clear_i),
        .write_valid_i(left_write_valid_i), .write_bank_i(write_bank_i),
        .write_word_i(write_word_i), .write_data_i(left_write_data_i),
        .read_valid_i(read_enable), .read_x_i(read_x_i),
        .read_oldest_i(read_oldest_i), .column_valid_o(left_column_valid),
        .column_o(left_stored_column)
    );
    packed_circular_row_buffer #(
        .K(K), .PIXEL_W(PIXEL_W), .IMG_W(IMG_W), .SPARE_ROWS(SPARE_ROWS),
        .X_W(X_W), .BANK_W(BANK_W), .WORD_AW(WORD_AW)
    ) right_rows (
        .clk(clk), .rst_n(rst_n), .clear_i(frame_clear_i),
        .write_valid_i(right_write_valid_i), .write_bank_i(write_bank_i),
        .write_word_i(write_word_i), .write_data_i(right_write_data_i),
        .read_valid_i(read_enable), .read_x_i(read_x_i),
        .read_oldest_i(read_oldest_i), .column_valid_o(right_column_valid),
        .column_o(right_stored_column)
    );

    left_column_delay #(.K(K), .PIXEL_W(PIXEL_W)) left_align (
        .clk(clk), .rst_n(rst_n), .clear_i(history_clear),
        .valid_i(left_column_valid), .column_i(left_stored_column),
        .valid_o(left_valid_o), .column_o(left_column_o)
    );
    right_column_shift #(.K(K), .PIXEL_W(PIXEL_W), .TAPS(TAPS)) right_cache (
        .clk(clk), .rst_n(rst_n), .clear_i(history_clear),
        .valid_i(right_column_valid), .column_i(right_stored_column),
        .tap_valid_o(right_valid_o), .columns_o(right_columns_o)
    );

    // pending_* follows the RAM read edge. The second register follows the
    // existing delay/cache edge, using the OLD store valid and OLD pending tag.
    // Bubbles hold coordinates/payload but never repeat a valid row-end pulse.
    always_ff @(posedge clk) begin
        if (!rst_n || history_clear) begin
            pending_x <= '0;
            pending_y <= '0;
            x_o <= '0;
            y_o <= '0;
            row_last_o <= 1'b0;
        end else begin
            if (read_enable) begin
                pending_x <= read_x_i;
                pending_y <= read_y_i;
            end
            if (left_column_valid) begin
                x_o <= pending_x;
                y_o <= pending_y;
            end
            row_last_o <= left_column_valid && (pending_x == X_W'(IMG_W-1));
        end
    end

    // synthesis translate_off
    initial begin
        if (K < 1 || PIXEL_W < 1 || IMG_W < 1 || IMG_H < 1 || TAPS < 1 || SPARE_ROWS < 1)
            $fatal(1, "FRONTEND K=%0d parameters must be positive", K);
    end
    // synthesis translate_on
endmodule
`default_nettype wire
```

## 1. Dimensions and public bus widths

```systemverilog
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer IMG_W = 640,
    parameter integer IMG_H = 480,
    parameter integer TAPS = 32,
    parameter integer SPARE_ROWS = 1,
```

- `K` is the vertical column height, not a locally generated warmup count. Each image has K active row banks plus `SPARE_ROWS` additional prefetch banks.
- `PIXEL_W` sets the sample width. Four adjacent samples occupy each load beat; production `PIXEL_W=8` therefore has separate 32-bit left/right load buses.
- `IMG_W` bounds the x coordinate and determines the number of four-pixel words per row, rounded up.
- `IMG_H` supplies the y-tag width. No height-dependent raster traversal is implemented.
- `TAPS` controls the existing right-column history depth. It is independent of K and of the left alignment latency.
- `SPARE_ROWS` is an elaboration-time capacity parameter, default/minimum one. Both packed stores receive it; no readiness tracker, row copy or extra pipeline edge is introduced.

```systemverilog
    parameter integer X_W = (IMG_W <= 1) ? 1 : $clog2(IMG_W),
    parameter integer Y_W = (IMG_H <= 1) ? 1 : $clog2(IMG_H),
    parameter integer BANK_W = (K+SPARE_ROWS <= 1) ? 1 : $clog2(K+SPARE_ROWS),
    parameter integer WORD_AW = ((IMG_W+3)/4 <= 1) ? 1 : $clog2((IMG_W+3)/4)
```

Each address width has a one-bit minimum. `BANK_W` reaches the full active-plus-spare ring, including bank-count power-of-two crossings; `WORD_AW` addresses words, not pixels. A non-multiple-of-four row has padding lanes in its final word; the caller never reads x beyond `IMG_W-1`.

```systemverilog
    input  wire                          left_write_valid_i,
    input  wire                          right_write_valid_i,
    input  wire [BANK_W-1:0]             write_bank_i,
    input  wire [WORD_AW-1:0]            write_word_i,
    input  wire [4*PIXEL_W-1:0]          left_write_data_i,
    input  wire [4*PIXEL_W-1:0]          right_write_data_i,
```

The shared address selects the bank/word for this beat. Left and right enables are independent: a left-only beat must not overwrite right RAM, and vice versa. This wrapper neither queues nor combines beats. Lane n of each beat stores image x=`4*write_word_i+n` in slice `[n*PIXEL_W +: PIXEL_W]`; lane extraction belongs inside the packed row stores.

```systemverilog
    input  wire                          read_valid_i,
    input  wire [X_W-1:0]                read_x_i,
    input  wire [Y_W-1:0]                read_y_i,
    input  wire [BANK_W-1:0]             read_oldest_i,
```

These are caller-scheduled **paired** reads. `read_y_i` is the window's bottom image row. The caller provides initialized, still-live K-row windows and increasing x beginning at zero for each horizontal history epoch. The oldest bank is supplied externally; this frontend does not infer it from y or maintain an ownership cursor.

## 2. Clear domains are deliberately different

```systemverilog
    localparam integer COL_W = K * PIXEL_W;
    wire history_clear = frame_clear_i || row_clear_i;
    wire read_enable = read_valid_i && !history_clear;
```

`COL_W` is one whole vertical column. `history_clear` affects both horizontal consumers and metadata. Masking `read_enable` suppresses a simultaneous new read on either clear, preventing a discarded row-clear input from reappearing one edge later.

| Active edge condition | Row-store loads | New column reads | Horizontal history and tags |
|---|---|---|---|
| `rst_n=0` | Suppressed inside row stores | Suppressed inside row stores | Synchronously reset to zero |
| `frame_clear_i=1` | Suppressed inside row stores | Suppressed | Synchronously cleared to zero |
| `row_clear_i=1` only | Still permitted independently | Suppressed | Synchronously cleared to zero |
| Neither clear/reset | Independent left/right enables | Shared paired read enable | Advance only for the prior accepted read |

All resets/clears are synchronous. Neither kind erases RAM. A frame clear invalidates the caller's notion of fresh frame ownership; retaining physical bits does not make them a newly loaded frame. A row clear intentionally allows a new-row load while flushing horizontal state.

## 3. Two packed row stores, no streaming bypass

```systemverilog
    ) left_rows (
        .clk(clk), .rst_n(rst_n), .clear_i(frame_clear_i),
        .write_valid_i(left_write_valid_i), .write_bank_i(write_bank_i),
        .write_word_i(write_word_i), .write_data_i(left_write_data_i),
```

The left store receives **frame clear only**, not `history_clear`. Its RAM write address and data are independent of the read x address. The right instance mirrors this connection with the right enable/data. Both receive `.SPARE_ROWS(SPARE_ROWS)` and the public X/BANK/WORD widths, keeping capacity and named-port widths consistent with the wrapper.

```systemverilog
        .read_valid_i(read_enable), .read_x_i(read_x_i),
        .read_oldest_i(read_oldest_i), .column_valid_o(left_column_valid),
        .column_o(left_stored_column)
```

Both stores use identical read control; consequently their column-valid registers advance together. Each store captures the lane/oldest selector with its synchronous RAM read. Low column slice is the oldest row; high slice is the newest. **The newest row also comes from RAM**—there is no input-stream bypass, including when K=1.

The caller must avoid reading any uninitialized/overwritten window. **Only the K active banks read a column**; spare banks may accept writes at the same word address. Preserve every active row, including during bubbles, and promote a prefetched row only after all its left AND right words are loaded. Advance oldest modulo K+SPARE_ROWS at a drained/cleared row boundary, making the retired oldest bank spare without copying. The local accepted-read assertion is not a synthesized ownership/readiness manager.

## 4. Existing horizontal blocks provide the second register boundary

```systemverilog
    left_column_delay #(.K(K), .PIXEL_W(PIXEL_W)) left_align (
        .clk(clk), .rst_n(rst_n), .clear_i(history_clear),
        .valid_i(left_column_valid), .column_i(left_stored_column),
        .valid_o(left_valid_o), .column_o(left_column_o)
    );
```

The existing left delay samples the **previous edge's** registered row-store output. Its one register matches the right cache's input sampling register, not the number of disparity taps. A disabled beat holds the payload but deasserts valid.

```systemverilog
    right_column_shift #(.K(K), .PIXEL_W(PIXEL_W), .TAPS(TAPS)) right_cache (
        .clk(clk), .rst_n(rst_n), .clear_i(history_clear),
        .valid_i(right_column_valid), .column_i(right_stored_column),
        .tap_valid_o(right_valid_o), .columns_o(right_columns_o)
    );
```

Tap d is the entire K-pixel right column at x-d for the same bottom y. Bubbles do not shift the cache or fill new taps. On an accepted output column x, tap-valid d is true exactly when x>=d, assuming the required zero-based, contiguous accepted x sequence. Invalid taps after clear contain zero; all payloads hold on bubbles even though all valid bits become zero.

This frontend does **not** wait for K horizontal columns or TAPS mature taps before emitting data. Early columns must remain visible for later engines to apply their own SAD-window readiness. W<K or W<TAPS is legal even when a later full SAD interior would be empty.

## 5. Tags follow the data, including bubbles

```systemverilog
            if (read_enable) begin
                pending_x <= read_x_i;
                pending_y <= read_y_i;
            end
```

The pending tag is the first metadata register. It changes on the same accepted edge as the RAM lane and bank selectors, not on every clock and not on load beats.

```systemverilog
            if (left_column_valid) begin
                x_o <= pending_x;
                y_o <= pending_y;
            end
            row_last_o <= left_column_valid && (pending_x == X_W'(IMG_W-1));
```

Nonblocking assignments are essential: this block sees the **old** store valid and **old** pending tag, just as the delay/cache see the old stored columns. Using `read_x_i` here would attach the next input's x to the previous read's data; arbitrary input bubbles make that error observable. Coordinates hold when no column hands off. `row_last_o` is a valid-beat pulse, not a level held while a final-column coordinate remains on the bus.

On reset/clear, the earlier branch zeros both pending and output tags and row-end. The horizontal blocks independently clear their payload/valid state at that same edge, so an abort cannot leave valid old data with new zero tags.

### Edge-by-edge timing

| Edge | State sampled before NBA | State visible after NBA |
|---|---|---|
| t | Caller presents an enabled read with x/y/oldest | Row stores expose column; pending tag captures x/y |
| t+1 | Alignment/cache and tag output registers sample that stored column/tag | Aligned left column, right taps and output x/y are visible |
| t+2 | A synchronous downstream consumer samples the aligned pair and tags | Next pair, bubble or clear becomes visible |

Consecutive reads occupy both stages. A bubble at the input does not erase the previous read waiting to hand off. After the last read of a normal row, use **one bubble edge** to move that last stored column into alignment, then assert row clear on a **separate edge**. Clear simultaneous with the handoff is an abort, not a drain. A later SAD engine has its own additional documented drain requirement; this wrapper does not implement that backend timing.

## 6. Standalone verification: raw image, not a second implementation

Bench: `tests/rtl/tb_stereo_frontend.sv`, parameters `K`, `P`, `W`, `T`, `S`. Its chosen IMG_H is `min(3*(K+S)+5,480)`, including full-width cases: enough for several whole-ring wraps without turning every raw-image/tap sweep into a 480-row simulation. Production IMG_H remains 480. Runner `--spare-rows N` overrides S. Runtime controls remain `+RANDOM_CYCLES=<n>`, `+SEED=<n>` and optional `+VCD`.

The oracle owns independent flat left/right pixel images. At an accepted x/y read it constructs:

- left slice j directly from `left_image[(y-K+1+j)*W+x]`;
- right tap d/slice j directly from `right_image[(y-K+1+j)*W+x-d]` when x>=d;
- right validity from x>=d, without shifting a modeled cache;
- x/y and row-end from the supplied image coordinates.

A single pending **expected output record** accounts for the required store-to-alignment edge. This is a latency record, not a modeled ring, lane selector, bank RAM, tap shift register or DUT-internal probe. The same expectation is compared before NBA at the consumer edge and after NBA at the registered-output observation point. An extra between-edge comparison rejects combinational metadata/payload leaks. Payload holds, zero reset visibility and invalid-beat row-end suppression are checked as well as valid data.

The stimulus scheduler—not the oracle—maps row y to bank y modulo K+S. It loads every required packed word, shuffles preload word order, randomizes load gaps/LR arrival order, and waits for both images' required rows before reading. Separate per-pixel load flags reject uninitialized reads. Padding lanes are deliberately nonzero. Historical image arrays are not permission to reread overwritten banks.

During a scan, prefetch begins at x=0 into a **spare** bank while every active row stays intact. Same-word-address read/write overlaps are deliberate, with independent left/right arrivals. If a partial final word leaves the right side late, its missing pixels are loaded before the next row is read. Row advancement reuses banks without copying. This is testbench scheduling, not implemented autonomous ownership control.

Directed checks include:

1. Synchronous reset asserted with read/write valid and poison input data.
2. External vertical warmup followed by immediate x=0 visibility; shallow widths and long tap counts still produce valid early columns.
3. Final-column handoff on one bubble, then row clear separately; a simultaneous row-clear read is suppressed while a left-only load remains legal.
4. Final live-window replay after row clear **without RAM reload**, proving horizontal clear preserves stored images.
5. Frame clear with an outstanding read, a simultaneous valid read, and poison write data; both clears asserted together exercise priority. Subsequent bubbles must not resurrect the aborted pair.
6. Fresh independent images and explicit row-word reload after frame clear, followed by bounded randomized bubbles and complete row replays.
7. K=1, IMG_W=1 with K>1, partial final words, non-power-of-two K/widths, alternate pixel widths, TAPS=1 and full-width 640/641-row addressing through parameter sweeps.

Every literal bench fatal begins with `FRONTEND K=` so the mutation runner can distinguish scoreboard failures. Counters require accepted reads, consumer observations, independent L-only/R-only writes, row-clear loads and same-word-address spare prefetch, including narrow rows. Additional S=2/3 cases exercise non-power-of-two total bank counts. [Current spare-row verification](../../docs/verification/spare-row-prefetch.md).

## Verification boundary

The standalone bench is intended for Icarus simulation with `row_word_bank.sv`, `packed_circular_row_buffer.sv`, `left_column_delay.sv`, `right_column_shift.sv`, and `stereo_frontend.sv` as dependencies. Shared runner registration and project-wide integration are maintained separately. Simulation checks functional pairing and clock/tag timing; this note makes no RAM-mapping, synthesis, fitted timing, SDRAM, full SAD-bank or board-success claim.
