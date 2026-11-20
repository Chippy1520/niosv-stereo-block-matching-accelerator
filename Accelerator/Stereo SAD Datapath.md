# Stereo SAD Datapath — Code Walkthrough

Parent: [[Accelerator Architecture]]

Children: [[Stereo Frontend]] · [[SAD Search Backend]]

Verification: [[Verification]] · [[Verification Map]] · [[Testbench Guide]]

Source of truth: `rtl/stereo_sad_datapath.sv`. Interface, caller obligations and timing authority: [compute-datapath specification](../docs/accelerator-datapath-spec.md).

## Purpose, need and connections

This is the complete **compute datapath**, joining packed image storage to the winning SAD/disparity result. [[Stereo Frontend]] owns the two packed row stores, left-column alignment and right-column history. [[SAD Search Backend]] owns the parallel window-cost engines, common-interior qualification, minimum selection and result-tag delay. This top connects those meaningful boundaries and packs the result; it does not duplicate their storage or arithmetic.

It is needed so a caller can load real left/right image rows, request columns and receive tagged full-search winners through one interface. It is **not** a raster controller, oldest-bank ownership manager, input/output FIFO, SDRAM bus interface or autonomous drain timer. There are no synthesized coordinate counters in this top: x, y and the oldest bank are caller inputs. Backend simulation-only protocol bookkeeping is not a hardware controller.

## Exact full RTL

The first SystemVerilog block is the complete, unannotated source. The table immediately after it explains every nonblank source line beside its exact code.

```systemverilog
`timescale 1ns/1ps
`default_nettype none

// Complete compute datapath, not a controller or memory-bus interface.
// Read at t -> result after t+2+$clog2(K)+1+max(1,$clog2(LANES)).
module stereo_sad_datapath #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer IMG_W = 640,
    parameter integer IMG_H = 480,
    parameter integer LANES = 32,
    parameter integer SPARE_ROWS = 1,
    parameter integer SAD_W = PIXEL_W + $clog2(K*K),
    parameter integer D_W = (LANES <= 1) ? 1 : $clog2(LANES),
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
    output wire                          valid_o,
    output wire [SAD_W-1:0]             sad_o,
    output wire [D_W-1:0]               disparity_o,
    output wire [X_W-1:0]               x_o,
    output wire [Y_W-1:0]               y_o,
    output wire                          row_last_o,
    output logic [31:0]                 result_o
);
    wire left_valid, row_last;
    wire [K*PIXEL_W-1:0] left_column;
    wire [LANES-1:0] right_valid;
    wire [LANES*K*PIXEL_W-1:0] right_columns;
    wire [X_W-1:0] x;
    wire [Y_W-1:0] y;

    stereo_frontend #(
        .K(K), .PIXEL_W(PIXEL_W), .IMG_W(IMG_W), .IMG_H(IMG_H), .TAPS(LANES),
        .SPARE_ROWS(SPARE_ROWS),
        .X_W(X_W), .Y_W(Y_W), .BANK_W(BANK_W), .WORD_AW(WORD_AW)
    ) frontend (
        .clk(clk), .rst_n(rst_n), .frame_clear_i(frame_clear_i), .row_clear_i(row_clear_i),
        .left_write_valid_i(left_write_valid_i), .right_write_valid_i(right_write_valid_i),
        .write_bank_i(write_bank_i), .write_word_i(write_word_i),
        .left_write_data_i(left_write_data_i), .right_write_data_i(right_write_data_i),
        .read_valid_i(read_valid_i), .read_x_i(read_x_i), .read_y_i(read_y_i),
        .read_oldest_i(read_oldest_i), .left_valid_o(left_valid), .left_column_o(left_column),
        .right_valid_o(right_valid), .right_columns_o(right_columns),
        .x_o(x), .y_o(y), .row_last_o(row_last)
    );
    sad_search_backend #(
        .K(K), .PIXEL_W(PIXEL_W), .LANES(LANES), .IMG_W(IMG_W), .IMG_H(IMG_H),
        .SAD_W(SAD_W), .D_W(D_W), .X_W(X_W), .Y_W(Y_W)
    ) backend (
        .clk(clk), .rst_n(rst_n), .clear_i(frame_clear_i || row_clear_i),
        .valid_i(left_valid), .left_column_i(left_column),
        .right_columns_i(right_columns), .right_valid_i(right_valid),
        .x_i(x), .y_i(y), .row_last_i(row_last),
        .valid_o(valid_o), .sad_o(sad_o), .disparity_o(disparity_o),
        .x_o(x_o), .y_o(y_o), .row_last_o(row_last_o)
    );

    // A combinational record adds no latency; invalid cycles are exactly zero.
    // Part-selects avoid a negative replication count for rejected parameters.
    always_comb begin
        result_o = '0;
        if (valid_o) begin
            result_o[0 +: SAD_W] = sad_o;
            result_o[SAD_W +: D_W] = disparity_o;
            result_o[31] = 1'b1;
        end
    end

    // synthesis translate_off
    initial begin
        if (SAD_W+D_W > 31)
            $fatal(1, "DATAPATH record requires SAD_W+D_W<=31");
        if (SPARE_ROWS < 1)
            $fatal(1, "DATAPATH SPARE_ROWS must be at least one");
        if (BANK_W < ((K+SPARE_ROWS<=1)?1:$clog2(K+SPARE_ROWS)) ||
            WORD_AW < (((IMG_W+3)/4<=1)?1:$clog2((IMG_W+3)/4)))
            $fatal(1, "DATAPATH undersized bank/word address");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
```

## Every nonblank line, beside its code

Line numbers refer to `rtl/stereo_sad_datapath.sv`, including blank lines. Backslash-escaped pipes below represent literal RTL pipes, not extra source characters. Double-backtick code spans preserve the source's preprocessor backticks.

| RTL line | Exact code | Explanation |
| ---: | --- | --- |
| 1 | <code>&#96;timescale 1ns/1ps</code> | Sets the simulation time unit and precision; it does not generate a clock or impose a physical frequency. |
| 2 | <code>&#96;default_nettype none</code> | Rejects accidental implicit nets, making misspelled composition signals visible to the tools. |
| 4 | <code>// Complete compute datapath, not a controller or memory-bus interface.</code> | Complete compute datapath, not a controller or memory-bus interface. |
| 5 | <code>// Read at t -&gt; result after t+2+$clog2(K)+1+max(1,$clog2(LANES)).</code> | Read at t -> result after t+2+$clog2(K)+1+max(1,$clog2(LANES)). |
| 6 | <code>module stereo_sad_datapath #(</code> | Opens the parameterized top-level compute module. |
| 7 | <code>    parameter integer K = 11,</code> | Sets active vertical rows and SAD window size; spare storage is configured separately. |
| 8 | <code>    parameter integer PIXEL_W = 8,</code> | Sets each unsigned pixel width; load beats always contain four such pixels. |
| 9 | <code>    parameter integer IMG_W = 640,</code> | Sets the row extent, packed word-address sizing and common-interior bounds. |
| 10 | <code>    parameter integer IMG_H = 480,</code> | Sets the frame height used for y-tag sizing and backend bounds, not a traversal counter. |
| 11 | <code>    parameter integer LANES = 32,</code> | Sets the entire fixed disparity search range, from zero through LANES minus one; there is no lane replay. |
| 12 | <code>    parameter integer SPARE_ROWS = 1,</code> | Adds one spare prefetch row by default; this elaboration-time count may increase but must remain at least one. |
| 13 | <code>    parameter integer SAD_W = PIXEL_W + $clog2(K*K),</code> | Derives a sufficient unsigned width for a sum of K-by-K pixel differences. |
| 14 | <code>    parameter integer D_W = (LANES &lt;= 1) ? 1 : $clog2(LANES),</code> | Sizes the winning disparity index with a one-bit minimum for a one-lane build. |
| 15 | <code>    parameter integer X_W = (IMG_W &lt;= 1) ? 1 : $clog2(IMG_W),</code> | Sizes an explicit x coordinate without creating a zero-width port for a one-pixel row. |
| 16 | <code>    parameter integer Y_W = (IMG_H &lt;= 1) ? 1 : $clog2(IMG_H),</code> | Sizes the y sideband, retaining a legal one-bit interface at height one. |
| 17 | <code>    parameter integer BANK_W = (K+SPARE_ROWS &lt;= 1) ? 1 : $clog2(K+SPARE_ROWS),</code> | Sizes physical bank indices for all active and spare banks, retaining a one-bit minimum. |
| 18 | <code>    parameter integer WORD_AW = ((IMG_W+3)/4 &lt;= 1) ? 1 : $clog2((IMG_W+3)/4)</code> | Addresses the rounded-up number of four-pixel words per row, with a one-bit minimum. |
| 19 | <code>) (</code> | Ends the parameter list and begins the external ports. |
| 20 | <code>    input  wire                          clk,</code> | Supplies the common rising-edge clock to both child pipelines. |
| 21 | <code>    input  wire                          rst_n,</code> | Passes synchronous active-low reset to the children; it resets visibility/history rather than initializing image RAM. |
| 22 | <code>    input  wire                          frame_clear_i,</code> | Aborts frame visibility and histories, blocks frontend reads and suppresses store writes on the clear edge without erasing RAM. |
| 23 | <code>    input  wire                          row_clear_i,</code> | Resets horizontal histories and pending tags between rows while preserving row RAM and the independent load path. |
| 24 | <code>    input  wire                          left_write_valid_i,</code> | Enables a left-store write independently of the right-store enable. |
| 25 | <code>    input  wire                          right_write_valid_i,</code> | Enables a right-store write independently; either image or both may be loaded at the shared address. |
| 26 | <code>    input  wire [BANK_W-1:0]             write_bank_i,</code> | Supplies the common physical destination bank for whichever image write enables are asserted. |
| 27 | <code>    input  wire [WORD_AW-1:0]            write_word_i,</code> | Supplies the common destination word index, not a pixel x coordinate. |
| 28 | <code>    input  wire [4*PIXEL_W-1:0]          left_write_data_i,</code> | Carries four left pixels, low-slice first; it is a 32-bit load bus only when PIXEL_W is eight. |
| 29 | <code>    input  wire [4*PIXEL_W-1:0]          right_write_data_i,</code> | Carries a separate four-pixel right payload; left and right data need not match or arrive together. |
| 30 | <code>    input  wire                          read_valid_i,</code> | Requests a column read when reset/clear permits; there is no ready handshake or input queue. |
| 31 | <code>    input  wire [X_W-1:0]                read_x_i,</code> | Supplies the trailing left-window x; the caller must begin at zero and advance consecutively on accepted reads. |
| 32 | <code>    input  wire [Y_W-1:0]                read_y_i,</code> | Supplies the bottom row of the left window, held fixed during a row's accepted reads. |
| 33 | <code>    input  wire [BANK_W-1:0]             read_oldest_i,</code> | Identifies the physical bank containing the oldest/top window row; ownership and rotation remain caller responsibilities. |
| 34 | <code>    output wire                          valid_o,</code> | Qualifies a completed full-search winner that the consumer must accept; no output backpressure exists. |
| 35 | <code>    output wire [SAD_W-1:0]             sad_o,</code> | Exposes the winning unsigned cost from the backend, meaningful as a result when valid_o is asserted. |
| 36 | <code>    output wire [D_W-1:0]               disparity_o,</code> | Exposes the winning fixed lane index; equal costs select the lower disparity in the backend. |
| 37 | <code>    output wire [X_W-1:0]               x_o,</code> | Carries the winner's delayed bottom-right x tag, not a newly generated coordinate. |
| 38 | <code>    output wire [Y_W-1:0]               y_o,</code> | Carries the matching bottom-right y tag alongside the same result. |
| 39 | <code>    output wire                          row_last_o,</code> | Qualifies the final-column winner only when result valid is true; it is not an unconditional row-completion pulse. |
| 40 | <code>    output logic [31:0]                 result_o</code> | Exposes the combinational 32-bit record in parallel with the explicit cost, disparity and coordinate sidebands. |
| 41 | <code>);</code> | Completes backend composition; no extra FIFO or scheduling stage is inserted. |
| 42 | <code>    wire left_valid, row_last;</code> | Connects the frontend's paired-column validity and trailing-column marker to the backend. |
| 43 | <code>    wire [K*PIXEL_W-1:0] left_column;</code> | Holds one full vertical left column, shared by every disparity engine downstream. |
| 44 | <code>    wire [LANES-1:0] right_valid;</code> | Holds one validity bit per right tap; legal prefix warmup tells each engine when its real columns begin. |
| 45 | <code>    wire [LANES*K*PIXEL_W-1:0] right_columns;</code> | Bundles the disparity-aligned K-pixel right columns, one column per search lane. |
| 46 | <code>    wire [X_W-1:0] x;</code> | Carries the frontend-aligned x tag with the columns. |
| 47 | <code>    wire [Y_W-1:0] y;</code> | Carries the matching frontend-aligned y tag. |
| 49 | <code>    stereo_frontend #(</code> | Instantiates the child responsible for packed storage and column alignment rather than duplicating it. |
| 50 | <code>        .K(K), .PIXEL_W(PIXEL_W), .IMG_W(IMG_W), .IMG_H(IMG_H), .TAPS(LANES),</code> | Shares image/window geometry and makes the right-tap count match the complete disparity search. |
| 51 | <code>        .SPARE_ROWS(SPARE_ROWS),</code> | Passes spare capacity into the existing frontend without adding a module, copy, queue or pipeline edge. |
| 52 | <code>        .X_W(X_W), .Y_W(Y_W), .BANK_W(BANK_W), .WORD_AW(WORD_AW)</code> | Keeps child tag and address ports consistent with this top's public widths. |
| 53 | <code>    ) frontend (</code> | Names the configured frontend instance and opens its signal connections. |
| 54 | <code>        .clk(clk), .rst_n(rst_n), .frame_clear_i(frame_clear_i), .row_clear_i(row_clear_i),</code> | Preserves distinct frame/row clear semantics inside the frontend while sharing clock and reset. |
| 55 | <code>        .left_write_valid_i(left_write_valid_i), .right_write_valid_i(right_write_valid_i),</code> | Forwards independent image write enables without coupling them into a single paired-load requirement. |
| 56 | <code>        .write_bank_i(write_bank_i), .write_word_i(write_word_i),</code> | Forwards the shared destination address; this top does not calculate bank ownership or word progression. |
| 57 | <code>        .left_write_data_i(left_write_data_i), .right_write_data_i(right_write_data_i),</code> | Connects the two independent packed payloads to their respective stores. |
| 58 | <code>        .read_valid_i(read_valid_i), .read_x_i(read_x_i), .read_y_i(read_y_i),</code> | Passes caller-issued reads and tags into the registered frontend path. |
| 59 | <code>        .read_oldest_i(read_oldest_i), .left_valid_o(left_valid), .left_column_o(left_column),</code> | Supplies caller-owned row ordering and receives the aligned left column plus its validity. |
| 60 | <code>        .right_valid_o(right_valid), .right_columns_o(right_columns),</code> | Receives right-history taps and their per-lane warmup validity for the same left coordinate. |
| 61 | <code>        .x_o(x), .y_o(y), .row_last_o(row_last)</code> | Receives metadata delayed to match the paired column payloads. |
| 62 | <code>    );</code> | Completes backend composition; no extra FIFO or scheduling stage is inserted. |
| 63 | <code>    sad_search_backend #(</code> | Instantiates the arithmetic/search child consuming the aligned frontend stream. |
| 64 | <code>        .K(K), .PIXEL_W(PIXEL_W), .LANES(LANES), .IMG_W(IMG_W), .IMG_H(IMG_H),</code> | Shares the same window, pixel, search-range and image geometry with the arithmetic path. |
| 65 | <code>        .SAD_W(SAD_W), .D_W(D_W), .X_W(X_W), .Y_W(Y_W)</code> | Makes winner payload widths and delayed coordinate widths match this top. |
| 66 | <code>    ) backend (</code> | Names the configured backend instance and starts its stream connections. |
| 67 | <code>        .clk(clk), .rst_n(rst_n), .clear_i(frame_clear_i &#124;&#124; row_clear_i),</code> | Either clear aborts engine, reducer and tag state together; unlike the frontend stores, the backend needs no distinction between clear types. |
| 68 | <code>        .valid_i(left_valid), .left_column_i(left_column),</code> | Presents the aligned left beat to the backend; early real columns must reach the engines to warm horizontal windows. |
| 69 | <code>        .right_columns_i(right_columns), .right_valid_i(right_valid),</code> | Presents every disparity's right column and prefix validity; the backend forbids arbitrary mid-row lane holes. |
| 70 | <code>        .x_i(x), .y_i(y), .row_last_i(row_last),</code> | Passes matching column metadata into the backend's wall-clock tag pipeline, including across bubbles. |
| 71 | <code>        .valid_o(valid_o), .sad_o(sad_o), .disparity_o(disparity_o),</code> | Exposes the common-interior, all-lanes-qualified minimum directly without another output register. |
| 72 | <code>        .x_o(x_o), .y_o(y_o), .row_last_o(row_last_o)</code> | Exposes backend-aligned winner coordinates and valid-qualified row-end marking. |
| 73 | <code>    );</code> | Completes backend composition; no extra FIFO or scheduling stage is inserted. |
| 75 | <code>    // A combinational record adds no latency; invalid cycles are exactly zero.</code> | A combinational record adds no latency; invalid cycles are exactly zero. |
| 76 | <code>    // Part-selects avoid a negative replication count for rejected parameters.</code> | Part-selects avoid a negative replication count for rejected parameters. |
| 77 | <code>    always_comb begin</code> | Starts a purely combinational formatter, not a clocked pipeline stage. |
| 78 | <code>        result_o = &#x27;0;</code> | Defaults every record bit to zero on every evaluation, preventing latches and clearing unused and invalid bits. |
| 79 | <code>        if (valid_o) begin</code> | Populates the payload only for a completed winner; otherwise the all-zero default remains. |
| 80 | <code>            result_o[0 +: SAD_W] = sad_o;</code> | Places the cost in the lowest SAD_W bits using an upward indexed part-select. |
| 81 | <code>            result_o[SAD_W +: D_W] = disparity_o;</code> | Places disparity immediately above the cost; coordinate tags are deliberately not packed here. |
| 82 | <code>            result_o[31] = 1&#x27;b1;</code> | Sets the record's top valid bit, leaving any intervening padding bits zero. |
| 83 | <code>        end</code> | Ends startup diagnostics; child modules provide their own geometry and payload-width checks. |
| 84 | <code>    end</code> | Ends startup diagnostics; child modules provide their own geometry and payload-width checks. |
| 86 | <code>    // synthesis translate_off</code> | synthesis translate_off |
| 87 | <code>    initial begin</code> | Runs static parameter diagnostics at simulation startup. |
| 88 | <code>        if (SAD_W+D_W &gt; 31)</code> | Rejects payload widths that would overlap the reserved valid bit or exceed the record. |
| 89 | <code>            $fatal(1, &quot;DATAPATH record requires SAD_W+D_W&lt;=31&quot;);</code> | Stops simulation on an unrepresentable record contract instead of promising silent truncation is supported. |
| 90 | <code>        if (SPARE_ROWS &lt; 1)</code> | Rejects zero/negative spare capacity in simulation; synthesis still requires legal parameter values. |
| 91 | <code>            $fatal(1, &quot;DATAPATH SPARE_ROWS must be at least one&quot;);</code> | Stops simulation with a specific invalid-spare-count diagnostic rather than accepting K-only storage. |
| 92 | <code>        if (BANK_W &lt; ((K+SPARE_ROWS&lt;=1)?1:$clog2(K+SPARE_ROWS)) &#124;&#124;</code> | Checks top-level bank-port width against the complete active-plus-spare ring. |
| 93 | <code>            WORD_AW &lt; (((IMG_W+3)/4&lt;=1)?1:$clog2((IMG_W+3)/4)))</code> | Also requires enough word-address bits for the rounded-up packed row depth. |
| 94 | <code>            $fatal(1, &quot;DATAPATH undersized bank/word address&quot;);</code> | Stops simulation if either public address width is insufficient; it does not create runtime address repair. |
| 95 | <code>    end</code> | Ends startup diagnostics; child modules provide their own geometry and payload-width checks. |
| 96 | <code>    // synthesis translate_on</code> | synthesis translate_on |
| 97 | <code>endmodule</code> | Closes the complete composed compute datapath. |
| 98 | <code>&#96;default_nettype wire</code> | Restores the conventional default net type for subsequently compiled source. |

## Caller protocol: loads, ownership and coordinates

- **Independent loads, shared address:** each image has its own enable and `4*PIXEL_W`-bit payload. Assert either enable or both at the common `write_bank_i`/`write_word_i`. Payload slice zero holds the lowest-x pixel of the word; subsequent slices hold successive pixels. Padding in the final partial word is never a real read pixel.
- **Ownership stays outside:** `SPARE_ROWS=1` (minimum one) provides K+SPARE_ROWS banks per image; bank ports address that full ring. The caller initializes both complete K-row windows, holds `read_oldest_i`/y fixed within a row, and prefetches into spares while preserving every active row. Same-word-address reads/writes in different banks are legal. Promote only after both images' complete next rows are ready, draining/clearing first; advance oldest modulo the total bank count. The retired oldest becomes spare without copying. No synthesized ownership/readiness tracker is added.
- **Spatial continuity:** accepted reads begin at x=0 and then advance by exactly one. Bubbles do not advance horizontal histories. Right tap d represents R[x-d]; only prefix warmup is permitted, not arbitrary missing lane columns. Backend protocol assertions diagnose violations in simulation; they are not a synthesized scheduler.
- **Coordinate meaning:** `x_o`/`y_o` mark the **bottom-right/trailing pixel of the left K-by-K window**, not its center or top-left. Disparity d pairs that left window with the right window trailing at x-d. The backend emits only the complete common search interior: x at least K+LANES-2 and y at least K-1, within image bounds. Every lane must have a valid engine result; equal minimum costs prefer lower disparity. An image with no common interior emits no winners.
- **No backpressure:** there are no `ready` ports, input/output FIFOs or consumer-stall handling. The caller schedules reads; the consumer must sample every asserted `valid_o`. `row_last_o` is a valid-qualified final-column result, not a row-complete signal for rows that emit nothing.

## Frame clear versus row clear

Both clears are synchronous and abort pending arithmetic results/tags. Reset is synchronous active-low. None of these operations fills the row RAM with zero pixels: retained RAM contents are not proof of initialized window ownership.

**Frame clear** reaches both row stores as their clear input, suppresses loads and reads on that edge, resets visibility and clears alignment/search histories. **Row clear** preserves stored pixels, blocks new reads while asserted and clears horizontal alignment, search history and metadata; with reset/frame clear inactive, independent writes may still proceed. Reusing retained rows after a normal row boundary therefore does not require reloading every bank.

Clear is not a drain request. An early clear is an intentional abort and can discard pending work. No controller waits for results or generates a completion pulse on the caller's behalf.

## Timing: drain first, clear on a separate edge

The [frozen timing contract](../docs/accelerator-datapath-spec.md#frozen-timingfeasibility-contract) defines E = ceil(log2(K))+1 engine edges and R = max(1, ceil(log2(LANES))) reduction stages. A packed read sampled at edge t reaches the backend at t+2 and produces the final result **after t+2+E+R**. Metadata advances on wall-clock edges, including bubbles. The combinational record formatter adds no register or extra edge.

For the default K=11 and LANES=32, E=5 and R=5: a read at t yields its winner after **t+12**, if that read belongs to the valid common interior. A clocked downstream consumer samples that stable result at **t+13**. Stop issuing reads and keep clears deasserted while the final frontend handoff, engines and reducer drain. Then clear on a **separate edge after the final result can be sampled**; a conservative schedule samples at t+13 and asserts row clear at t+14. Do not clear at t+12 and expect the pending winner to survive. This is a scheduling obligation, not evidence of an implemented drain timer or measured sustained throughput.

## The 32-bit result record

`result_o` is an internal result interface, not a physical board pinout or an SDRAM protocol. The contract requires SAD_W+D_W no greater than 31. On valid cycles:

| Field | General layout | Default layout |
| --- | --- | --- |
| SAD | Lowest SAD_W bits | [14:0] |
| Disparity | Next D_W bits, immediately above SAD | [19:15] |
| Reserved | Remaining bits below bit 31, if any | [30:20], all zero |
| Valid | Bit 31 | [31], one |

On **every invalid cycle, all 32 bits of `result_o` are zero**, regardless of unqualified sideband payloads. Coordinates and `row_last_o` remain explicit sidebands and are not silently squeezed into this record. The top's startup checks diagnose excessive record widths and insufficient bank/word widths in simulation; they are not synthesis-time proof or runtime protection. Child checks also reject unsupported geometry or undersized result/tag widths.

## Verification connections and honest status

- [Standalone packed-top bench](../tests/rtl/tb_stereo_sad_datapath.sv) instantiates this module and observes the actual backend lane results.
- [[Control Emulation]] adds [a test-only frame scheduler](../tests/rtl/tb_stereo_control.sv) around this same real top, with independently delayed L/R loading, accepted-port ownership/readiness monitoring, raw-image output comparison and a clocked framebuffer sink. It exercises the earliest safe consumer/row-clear edge after the complete-path drain; it is not controller RTL.
- [Shared test-only raw-image checks](../tests/rtl/stereo_raw_checks.svh) supply independent complete-window reference costs rather than duplicating the DUT's rolling sum/cache algorithm.
- [Backend standalone bench](../tests/rtl/tb_sad_search_backend.sv) isolates arithmetic, winner and tag behavior before packed-store integration.
- [Frontend standalone bench](../tests/rtl/tb_stereo_frontend.sv) isolates packed storage, alignment and retained-row behavior; see [[Stereo Frontend - Code Walkthrough]].
- [[Verification]], [[Verification Map]] and [[Testbench Guide]] provide the surrounding evidence and test workflow. [Required verification cases](../docs/accelerator-datapath-spec.md#required-verification-cases) define the wider acceptance target.

The [earlier K-only compute report](../docs/verification/compute-datapath.md) records the historical 130 cases/33 faults and 22-M9K implementation. It is not current spare-row evidence. [Spare-row decision and current verification](../docs/verification/spare-row-prefetch.md) covers S=1/2/3, no-between-row-reload full-path prefetch, unchanged exact timing, parameter/ownership faults and fresh synthesis. Default-width compute benches now choose 41 rows with S=1, not a full 480-row frame. No fitted timing, achieved throughput, board or Nios V claim; no commit or push in this increment.
