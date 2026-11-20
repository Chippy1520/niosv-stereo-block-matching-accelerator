# Packed Circular Row Buffer

[[Stereo Frontend]] · [[Testbench Guide]] · [Datapath contract](../../docs/packed-frontend-contract.md)

## Exact RTL

```systemverilog
`timescale 1ns/1ps
`default_nettype none

// Four-pixel word loads and independent vertical-column reads; no scheduler.
// K active rows plus spare prefetch rows; low output slice is oldest.
// Caller owns complete-row readiness, bank lifetime and boundary rotation.
module packed_circular_row_buffer #(
    parameter integer K = 11,
    parameter integer PIXEL_W = 8,
    parameter integer IMG_W = 640,
    parameter integer SPARE_ROWS = 1,
    parameter integer X_W = (IMG_W <= 1) ? 1 : $clog2(IMG_W),
    parameter integer BANK_W = (K+SPARE_ROWS <= 1) ? 1 : $clog2(K+SPARE_ROWS),
    parameter integer WORD_AW = ((IMG_W + 3)/4 <= 1) ? 1 : $clog2((IMG_W + 3)/4)
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clear_i,
    input  wire                         write_valid_i,
    input  wire [BANK_W-1:0]            write_bank_i,
    input  wire [WORD_AW-1:0]           write_word_i,
    input  wire [4*PIXEL_W-1:0]         write_data_i,
    input  wire                         read_valid_i,
    input  wire [X_W-1:0]               read_x_i,
    input  wire [BANK_W-1:0]            read_oldest_i,
    output logic                        column_valid_o,
    output wire [K*PIXEL_W-1:0]         column_o
);
    localparam integer WORD_W = 4 * PIXEL_W;
    localparam integer WORDS = (IMG_W + 3) / 4;
    localparam integer ROW_BANKS = K + SPARE_ROWS;
    wire load_word = rst_n && !clear_i && write_valid_i;
    wire read_column = rst_n && !clear_i && read_valid_i;
    wire [WORD_AW-1:0] read_word = WORD_AW'(read_x_i >> 2);
    wire [ROW_BANKS*WORD_W-1:0] bank_words;
    logic [BANK_W-1:0] oldest;
    logic [1:0] lane;
    logic column_present;
    wire [ROW_BANKS*PIXEL_W-1:0] bank_pixels;

    genvar b, j;
    generate
        for (b = 0; b < ROW_BANKS; b = b + 1) begin : g_bank
            // Circular distance from oldest identifies the K live row banks.
            wire [BANK_W:0] bank_distance = (BANK_W'(b) >= read_oldest_i)
                ? (BANK_W+1)'(b) - {1'b0, read_oldest_i}
                : (BANK_W+1)'(b+ROW_BANKS) - {1'b0, read_oldest_i};
            wire bank_active = bank_distance < (BANK_W+1)'(K);
            row_word_bank #(.WORD_W(WORD_W), .DEPTH(WORDS), .ADDR_W(WORD_AW)) bank (
                .clk(clk), .write_i(load_word && write_bank_i == BANK_W'(b)),
                .write_address_i(write_word_i), .write_data_i(write_data_i),
                .read_i(read_column && bank_active), .read_address_i(read_word),
                .read_data_o(bank_words[b*WORD_W +: WORD_W])
            );
            // Narrow each bank to one pixel before the cross-bank rotation.
            assign bank_pixels[b*PIXEL_W +: PIXEL_W] =
                bank_words[b*WORD_W + lane*PIXEL_W +: PIXEL_W];
        end
        for (j = 0; j < K; j = j + 1) begin : g_tap
            wire [BANK_W:0] bank_sum = {1'b0, oldest} + (BANK_W + 1)'(j);
            wire [BANK_W:0] bank_index = (bank_sum >= (BANK_W + 1)'(ROW_BANKS))
                ? bank_sum - (BANK_W + 1)'(ROW_BANKS) : bank_sum;
            assign column_o[j*PIXEL_W +: PIXEL_W] = column_present
                ? bank_pixels[bank_index[BANK_W-1:0]*PIXEL_W +: PIXEL_W] : '0;
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n || clear_i) begin
            oldest <= '0;
            lane <= '0;
            column_present <= 1'b0;
            column_valid_o <= 1'b0;
        end else begin
            column_valid_o <= read_column;
            if (read_column) begin
                oldest <= read_oldest_i;
                lane <= 2'(read_x_i);
                column_present <= 1'b1;
            end
        end
    end

    // synthesis translate_off
    wire [BANK_W:0] write_distance = (write_bank_i >= read_oldest_i)
        ? {1'b0, write_bank_i} - {1'b0, read_oldest_i}
        : {1'b0, write_bank_i} + (BANK_W+1)'(ROW_BANKS) - {1'b0, read_oldest_i};
    initial begin
        if (SPARE_ROWS < 1)
            $fatal(1, "PACKED_ROW SPARE_ROWS must be at least one");
        if (K < 1 || PIXEL_W < 1 || IMG_W < 1 ||
            X_W < ((IMG_W <= 1) ? 1 : $clog2(IMG_W)) ||
            BANK_W < ((ROW_BANKS <= 1) ? 1 : $clog2(ROW_BANKS)) ||
            WORD_AW < ((WORDS <= 1) ? 1 : $clog2(WORDS)))
            $fatal(1, "Positive dimensions and sufficient address widths are required");
    end
    always @(posedge clk) begin
        if (load_word && (write_bank_i >= ROW_BANKS || write_word_i >= WORDS))
            $fatal(1, "PACKED_ROW invalid write address");
        if (read_column && (read_x_i >= IMG_W || read_oldest_i >= ROW_BANKS))
            $fatal(1, "PACKED_ROW invalid column address");
        // Whole active rows stay intact, even when the write word differs.
        // During bubbles/row-clear, ownership remains a caller obligation.
        if (load_word && read_column && write_distance < (BANK_W+1)'(K))
            $fatal(1, "PACKED_ROW cannot overwrite an active row bank");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
```

## Code-adjacent explanation

| RTL line | Exact code | Explanation |
| ---: | --- | --- |
| 1 | <code>&#96;timescale 1ns/1ps</code> | Compilation directive; no additional storage or pipeline edge. |
| 2 | <code>&#96;default_nettype none</code> | Compilation directive; no additional storage or pipeline edge. |
| 4 | <code>// Four-pixel word loads and independent vertical-column reads; no scheduler.</code> | Four-pixel word loads and independent vertical-column reads; no scheduler. |
| 5 | <code>// K active rows plus spare prefetch rows; low output slice is oldest.</code> | K active rows plus spare prefetch rows; low output slice is oldest. |
| 6 | <code>// Caller owns complete-row readiness, bank lifetime and boundary rotation.</code> | Caller owns complete-row readiness, bank lifetime and boundary rotation. |
| 7 | <code>module packed_circular_row_buffer #(</code> | Cohesive row-store datapath; loading and processing positions are separate inputs. |
| 8 | <code>    parameter integer K = 11,</code> | Sets active vertical rows and SAD window size; spare storage is configured separately. |
| 9 | <code>    parameter integer PIXEL_W = 8,</code> | Pixel width; four 8-bit production pixels form one 32-bit load. |
| 10 | <code>    parameter integer IMG_W = 640,</code> | Image pixels per row; the final word may contain padding. |
| 11 | <code>    parameter integer SPARE_ROWS = 1,</code> | Adds one spare prefetch row by default; this elaboration-time count may increase but must remain at least one. |
| 12 | <code>    parameter integer X_W = (IMG_W &lt;= 1) ? 1 : $clog2(IMG_W),</code> | Minimum horizontal pixel-coordinate width, clamped to one. |
| 13 | <code>    parameter integer BANK_W = (K+SPARE_ROWS &lt;= 1) ? 1 : $clog2(K+SPARE_ROWS),</code> | Sizes physical bank indices for all active and spare banks, retaining a one-bit minimum. |
| 14 | <code>    parameter integer WORD_AW = ((IMG_W + 3)/4 &lt;= 1) ? 1 : $clog2((IMG_W + 3)/4)</code> | Word-address width for ceil(IMG_W/4), clamped to one. |
| 15 | <code>) (</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 16 | <code>    input  wire                         clk,</code> | Common clock for the two independent synchronous ports. |
| 17 | <code>    input  wire                         rst_n,</code> | Synchronous active-low reset; no RAM erasure. |
| 18 | <code>    input  wire                         clear_i,</code> | Abort current accesses and mask output visibility, preserving stored image rows. |
| 19 | <code>    input  wire                         write_valid_i,</code> | Accept the complete supplied word at the supplied bank/word address. |
| 20 | <code>    input  wire [BANK_W-1:0]            write_bank_i,</code> | Caller-selected physical destination row; no automatic ownership scheduler. |
| 21 | <code>    input  wire [WORD_AW-1:0]           write_word_i,</code> | Destination word index, independent of the processing pixel position. |
| 22 | <code>    input  wire [4*PIXEL_W-1:0]         write_data_i,</code> | Four consecutive pixels; earliest pixel occupies the lowest slice. |
| 23 | <code>    input  wire                         read_valid_i,</code> | Accept one caller-scheduled, fully initialized vertical-column read. |
| 24 | <code>    input  wire [X_W-1:0]               read_x_i,</code> | Processing pixel x, independent of the load cursor. |
| 25 | <code>    input  wire [BANK_W-1:0]            read_oldest_i,</code> | Physical bank holding the oldest row of this complete K-row window. |
| 26 | <code>    output logic                        column_valid_o,</code> | Registered valid for accepted reads only, including bubbles and clears. |
| 27 | <code>    output wire [K*PIXEL_W-1:0]         column_o</code> | K pixels packed oldest-to-newest in low-to-high slices. |
| 28 | <code>);</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 29 | <code>    localparam integer WORD_W = 4 * PIXEL_W;</code> | Four pixel lanes per RAM word; 32 bits in production. |
| 30 | <code>    localparam integer WORDS = (IMG_W + 3) / 4;</code> | Round image width upward to whole four-pixel words. |
| 31 | <code>    localparam integer ROW_BANKS = K + SPARE_ROWS;</code> | Counts all physical RAM banks; output columns still contain only K active pixels. |
| 32 | <code>    wire load_word = rst_n &amp;&amp; !clear_i &amp;&amp; write_valid_i;</code> | Reset/clear suppress even a simultaneous valid write. |
| 33 | <code>    wire read_column = rst_n &amp;&amp; !clear_i &amp;&amp; read_valid_i;</code> | Reset/clear suppress reads and their tag captures. |
| 34 | <code>    wire [WORD_AW-1:0] read_word = WORD_AW&#x27;(read_x_i &gt;&gt; 2);</code> | Drop two low x bits to obtain the shared RAM word address. |
| 35 | <code>    wire [ROW_BANKS*WORD_W-1:0] bank_words;</code> | Bundles all physical bank outputs, including spares; pixel selection stays ahead of active-row rotation. |
| 36 | <code>    logic [BANK_W-1:0] oldest;</code> | Captured bank selector, aligned to the RAM read result. |
| 37 | <code>    logic [1:0] lane;</code> | Captured low two x bits, selecting one of four pixels. |
| 38 | <code>    logic column_present;</code> | Resettable visibility flag avoids resetting the memory array. |
| 39 | <code>    wire [ROW_BANKS*PIXEL_W-1:0] bank_pixels;</code> | Bundles all physical bank outputs, including spares; pixel selection stays ahead of active-row rotation. |
| 41 | <code>    genvar b, j;</code> | Separate genvar declarations required by Quartus Lite 22.1. |
| 42 | <code>    generate</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 43 | <code>        for (b = 0; b &lt; ROW_BANKS; b = b + 1) begin : g_bank</code> | Elaborates one real word RAM per active or spare row, not a row-copy mechanism. |
| 44 | <code>            // Circular distance from oldest identifies the K live row banks.</code> | Circular distance from oldest identifies the K live row banks. |
| 45 | <code>            wire [BANK_W:0] bank_distance = (BANK_W&#x27;(b) &gt;= read_oldest_i)</code> | Begins an extra-bit unsigned circular distance from requested oldest to this constant bank; selects direct or wrapped subtraction. |
| 46 | <code>                ? (BANK_W+1)&#x27;(b) - {1&#x27;b0, read_oldest_i}</code> | Computes direct forward distance for a bank at or above oldest, using zero-extended arithmetic. |
| 47 | <code>                : (BANK_W+1)&#x27;(b+ROW_BANKS) - {1&#x27;b0, read_oldest_i};</code> | Adds the full ring size before subtracting oldest for a bank below oldest, covering a wrapped active window. |
| 48 | <code>            wire bank_active = bank_distance &lt; (BANK_W+1)&#x27;(K);</code> | Only distances zero through K minus one are active; the other banks are spare and must not read. |
| 49 | <code>            row_word_bank #(.WORD_W(WORD_W), .DEPTH(WORDS), .ADDR_W(WORD_AW)) bank (</code> | Instantiates the existing embedded-RAM primitive with matching word depth and public address width. |
| 50 | <code>                .clk(clk), .write_i(load_word &amp;&amp; write_bank_i == BANK_W&#x27;(b)),</code> | Only the selected physical bank receives the write enable. |
| 51 | <code>                .write_address_i(write_word_i), .write_data_i(write_data_i),</code> | Independent full-word write address and payload. |
| 52 | <code>                .read_i(read_column &amp;&amp; bank_active), .read_address_i(read_word),</code> | Reads only active banks, allowing same-word-address writes into spares without a same-bank RAM collision. |
| 53 | <code>                .read_data_o(bank_words[b*WORD_W +: WORD_W])</code> | Place this bank’s registered word in its own output slice. |
| 54 | <code>            );</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 55 | <code>            // Narrow each bank to one pixel before the cross-bank rotation.</code> | Narrow each bank to one pixel before the cross-bank rotation. |
| 56 | <code>            assign bank_pixels[b*PIXEL_W +: PIXEL_W] =</code> | First choose one pixel from each bank; do not rotate whole words. |
| 57 | <code>                bank_words[b*WORD_W + lane*PIXEL_W +: PIXEL_W];</code> | The registered lane tag selects the proper slice of this bank’s word. |
| 58 | <code>        end</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 59 | <code>        for (j = 0; j &lt; K; j = j + 1) begin : g_tap</code> | Produce one logical output-row tap for every row in the window. |
| 60 | <code>            wire [BANK_W:0] bank_sum = {1&#x27;b0, oldest} + (BANK_W + 1)&#x27;(j);</code> | Add the captured oldest bank and logical row offset with one extra bit. |
| 61 | <code>            wire [BANK_W:0] bank_index = (bank_sum &gt;= (BANK_W + 1)&#x27;(ROW_BANKS))</code> | Tests a captured tap sum against the complete active-plus-spare ring, not K. |
| 62 | <code>                ? bank_sum - (BANK_W + 1)&#x27;(ROW_BANKS) : bank_sum;</code> | Wraps once by subtracting the total physical bank count; oldest plus tap index is less than twice that count. |
| 63 | <code>            assign column_o[j*PIXEL_W +: PIXEL_W] = column_present</code> | Map each logical row tap into its packed output slice. |
| 64 | <code>                ? bank_pixels[bank_index[BANK_W-1:0]*PIXEL_W +: PIXEL_W] : &#x27;0;</code> | Rotate only PIXEL_W-bit pixels; mask unknown RAM contents until a valid read. |
| 65 | <code>        end</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 66 | <code>    endgenerate</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 68 | <code>    always_ff @(posedge clk) begin</code> | Clock data-valid and lane/bank selectors at the same edge as RAM reads. |
| 69 | <code>        if (!rst_n &#124;&#124; clear_i) begin</code> | Reset/clear has priority; no access or stale visibility survives it. |
| 70 | <code>            oldest &lt;= &#x27;0;</code> | Clear the visible bank tag without clearing pixel memory. |
| 71 | <code>            lane &lt;= &#x27;0;</code> | Clear the visible pixel-lane tag. |
| 72 | <code>            column_present &lt;= 1&#x27;b0;</code> | Mask RAM outputs after reset/clear; initialization remains the caller’s job. |
| 73 | <code>            column_valid_o &lt;= 1&#x27;b0;</code> | Do not advertise a read during reset or clear. |
| 74 | <code>        end else begin</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 75 | <code>            column_valid_o &lt;= read_column;</code> | A bubble produces invalid, not an additional column. |
| 76 | <code>            if (read_column) begin</code> | Only accepted reads advance the output selectors. |
| 77 | <code>                oldest &lt;= read_oldest_i;</code> | Capture the oldest physical bank for this exact RAM access. |
| 78 | <code>                lane &lt;= 2&#x27;(read_x_i);</code> | Capture x modulo four for this exact RAM access. |
| 79 | <code>                column_present &lt;= 1&#x27;b1;</code> | Allow initialized RAM data to become visible after the first accepted read. |
| 80 | <code>            end</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 81 | <code>        end</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 82 | <code>    end</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 84 | <code>    // synthesis translate_off</code> | synthesis translate_off |
| 85 | <code>    wire [BANK_W:0] write_distance = (write_bank_i &gt;= read_oldest_i)</code> | Begins a simulation-only circular membership check, not synthesized ownership tracking. |
| 86 | <code>        ? {1&#x27;b0, write_bank_i} - {1&#x27;b0, read_oldest_i}</code> | Computes direct write-bank distance from oldest with zero-extended indices. |
| 87 | <code>        : {1&#x27;b0, write_bank_i} + (BANK_W+1)&#x27;(ROW_BANKS) - {1&#x27;b0, read_oldest_i};</code> | Computes wrapped write-bank distance; a numerically smaller bank can still be active. |
| 88 | <code>    initial begin</code> | Simulation-only parameter validation; no controller hardware. |
| 89 | <code>        if (SPARE_ROWS &lt; 1)</code> | Rejects zero/negative spare capacity in simulation; synthesis still requires legal parameter values. |
| 90 | <code>            $fatal(1, &quot;PACKED_ROW SPARE_ROWS must be at least one&quot;);</code> | Stops simulation with a specific invalid-spare-count diagnostic rather than accepting K-only storage. |
| 91 | <code>        if (K &lt; 1 &#124;&#124; PIXEL_W &lt; 1 &#124;&#124; IMG_W &lt; 1 &#124;&#124;</code> | Require positive dimensions and enough bits in all address ports. |
| 92 | <code>            X_W &lt; ((IMG_W &lt;= 1) ? 1 : $clog2(IMG_W)) &#124;&#124;</code> | Reject an undersized x address port. |
| 93 | <code>            BANK_W &lt; ((ROW_BANKS &lt;= 1) ? 1 : $clog2(ROW_BANKS)) &#124;&#124;</code> | Requires enough bank-address bits to reach all active and spare physical banks. |
| 94 | <code>            WORD_AW &lt; ((WORDS &lt;= 1) ? 1 : $clog2(WORDS)))</code> | Reject an undersized word-address port. |
| 95 | <code>            $fatal(1, &quot;Positive dimensions and sufficient address widths are required&quot;);</code> | Stop simulation on a violated caller/parameter contract; not synthesized. |
| 96 | <code>    end</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 97 | <code>    always @(posedge clk) begin</code> | Simulation-only checks of enabled access contracts. |
| 98 | <code>        if (load_word &amp;&amp; (write_bank_i &gt;= ROW_BANKS &#124;&#124; write_word_i &gt;= WORDS))</code> | Rejects an enabled bank or word address beyond physical storage. |
| 99 | <code>            $fatal(1, &quot;PACKED_ROW invalid write address&quot;);</code> | Stop simulation on a violated caller/parameter contract; not synthesized. |
| 100 | <code>        if (read_column &amp;&amp; (read_x_i &gt;= IMG_W &#124;&#124; read_oldest_i &gt;= ROW_BANKS))</code> | Rejects an enabled out-of-image x or an oldest index beyond the complete bank ring. |
| 101 | <code>            $fatal(1, &quot;PACKED_ROW invalid column address&quot;);</code> | Stop simulation on a violated caller/parameter contract; not synthesized. |
| 102 | <code>        // Whole active rows stay intact, even when the write word differs.</code> | Whole active rows stay intact, even when the write word differs. |
| 103 | <code>        // During bubbles/row-clear, ownership remains a caller obligation.</code> | During bubbles/row-clear, ownership remains a caller obligation. |
| 104 | <code>        if (load_word &amp;&amp; read_column &amp;&amp; write_distance &lt; (BANK_W+1)&#x27;(K))</code> | Rejects any active-bank overwrite during an accepted read, even at a different word; ownership during bubbles remains external. |
| 105 | <code>            $fatal(1, &quot;PACKED_ROW cannot overwrite an active row bank&quot;);</code> | Makes active-window corruption a visible contract failure rather than relying on RAM collision behavior. |
| 106 | <code>    end</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 107 | <code>    // synthesis translate_on</code> | synthesis translate_on |
| 108 | <code>endmodule</code> | Continuation or closing boundary of the enclosing declaration/process; no extra hardware. |
| 109 | <code>&#96;default_nettype wire</code> | Compilation directive; no additional storage or pipeline edge. |

## Timing and ownership

This is a datapath, not a memory reader or row scheduler. **`SPARE_ROWS=1` (minimum one)** adds physical prefetch rows separately from the K active rows. The ring has K+SPARE_ROWS banks; output tap j selects `(oldest+j) modulo (K+SPARE_ROWS)`. Only the K active banks read. A spare can therefore receive a packed write at the **same word address** as the current active-bank read without a RAM collision.

Keep all K active rows intact throughout the scan, including bubbles. Simulation rejects concurrent active-bank writes on accepted-read edges even when the word address differs; there is no ownership tracking during read bubbles/row clear. The caller tracks initialization and complete-row readiness in both images, waits for a late prefetch, drains/clears horizontal history separately, then advances oldest around the full ring. The retired oldest bank becomes spare **without copying a row**. Reset masks visibility without resetting RAM. An accepted read still produces its result after that edge; synchronous consumers sample it on the next edge. Prefetch does not add latency or advance the disparity cache.

Selecting the lane **before** rotating the row-bank pixels narrows the costly mux from 32-bit words to 8-bit pixels in production. It adds no state, module or latency; see [council review](../../docs/verification/packed-frontend-council.md).

Standalone: `tests/rtl/tb_packed_circular_row_buffer.sv`; runner `--suite packed-row`, optional `--spare-rows N`. Its flat-image reference checks packing, partial words, full-ring rotation, same-word-address spare prefetch, complete active-window replay after loading, multiple spares, holds, clear and consumer edges. [Decision and evidence](../../docs/verification/spare-row-prefetch.md). [[Stereo Frontend - Code Walkthrough]] integrates two stores. [[Circular Row Buffer]] is the retained serial reference, not another buffer in this path.
