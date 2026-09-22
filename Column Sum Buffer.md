# Column Sum Buffer

Detailed study note: [[Column Sum Buffer - Code Walkthrough]].
#implemented
Source: [RTL](rtl/column_sum_buffer.sv)

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

Connections: [[Rolling SAD Math]] → [[Interface Contract]] → [[Verification]]. Replicate in [[Disparity Bank]]. Timing caveats: [[Timing and Pipelining]].
