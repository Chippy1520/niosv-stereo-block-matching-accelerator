# Interface Contract
#design
This note describes the buffer-only interface. For packed pixel input and pipeline drain/flush behavior, see [[Single SAD Engine]] and [[Pipelined Column SAD Calculator]].

[[Column Sum Buffer]] ports:

| Port | Meaning |
|---|---|
| clk | Rising-edge clock |
| rst_n | Synchronous active-low reset; hold low across a rising edge |
| clear_i | Synchronous flush at a scanline/frame boundary |
| valid_i | Accept column_sum_i on this edge |
| column_sum_i | Unsigned sum of K absolute pixel differences |
| valid_o | Registered indication that sad_o is a complete K-column SAD |
| sad_o | Registered full-window SAD |

Reset/clear takes priority over valid_i. A simultaneous clear and valid **discards that input**. Clear must therefore occupy a separate boundary cycle. No ready signal or output backpressure exists: the downstream stage must always accept valid outputs.

Stalls do not advance pointer/history; valid_o becomes zero and sad_o holds its previous value. Invalid output data must be ignored. The Kth accepted sample produces the first output just after its sampling edge; subsequent valid inputs produce one result each. This is one registered stage, not K clocks of fixed latency; warmup counts accepted samples, not clock cycles.

For K=3, after reset: accept 10 → invalid; accept 20 → invalid; bubble → invalid; accept 30 → valid 60; accept 40 → valid 90; clear → invalid and rewarm.

Only legal column sums (0 through K*(2^PIXEL_W-1)) may be supplied; spare binary encodings are not legal data. K and widths are compile-time parameters, not runtime CPU configuration.

Image width/height and disparity indices are deliberately outside this module. The future frontend/controller must align coordinate metadata and clear signals with the pipelined column inputs. See [[Nios V Interface]], [[Disparity Bank]].
