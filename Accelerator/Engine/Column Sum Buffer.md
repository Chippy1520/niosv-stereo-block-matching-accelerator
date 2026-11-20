# Column Sum Buffer

Detailed study note: [[Column Sum Buffer - Code Walkthrough]].
#implemented
Source: [RTL](../../rtl/column_sum_buffer.sv)

One lane; defaults K=11, PIXEL_W=8. A ten-entry ring retains previous column sums. A running total retains their sum. Before each accepted sample, wr_ptr identifies the oldest entry once full.

| Quantity | Default |
|---|---:|
| Maximum column sum | 2805 |
| COL_W | 12 bits |
| Maximum 11x11 SAD | 30855 |
| SAD_W | 15 bits |
| History storage per lane | 120 bits |
| History storage for 32 lanes | 3840 bits |

Storage figures exclude accumulators, output registers, pointers, counters, and image storage. The short asynchronous-read history array may map to registers/muxes rather than block RAM; verify in Quartus.

Memory is not reset. fill_count prevents stale entries from being read before every slot has been overwritten. Explicit wrap supports non-power-of-two depth ten. K=1 has a direct registered-output implementation.

Connections: [[Rolling SAD Math]] → [[Column Sum Buffer#Interface contract|buffer interface contract]] → [[Verification]]. Replicate in [[Project Plan#Disparity bank|disparity-bank plan]]. Timing caveats: [[Timing and Pipelining]].

## Interface contract

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

Image dimensions, disparity indices and coordinate metadata are outside this module. Future frontend/controller ownership is defined in [[Project Plan]].
