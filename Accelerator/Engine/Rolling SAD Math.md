# Rolling SAD Math
#design
For rectified stereo, define disparity convention R(x-d,y) against L(x,y). The frontend must reject out-of-range coordinates.

For a fixed vertical window ending at y:

$$C_d(x,y)=\sum_{j=0}^{K-1}|L(x,y-j)-R(x-d,y-j)|$$
$$S_d(x,y)=\sum_{i=0}^{K-1}C_d(x-i,y)$$

Before accepting a new column, H holds the sum of the preceding K-1 columns.

1. Output S = H + C_new, only once K-1 previous columns exist.
2. Update H = H - C_oldest + C_new; oldest is zero during warmup.
3. Replace the oldest circular-buffer entry and advance the pointer.

These are **column sums**, not row sums. [[Pipelined Column SAD Calculator]] computes K absolute differences and reduces them per lane. [[Column Sum Buffer]] reuses horizontal overlap only. [[Circular Row Buffer|Circular Row Buffer]] provides vertical pixels; its storage is separate.

After draining in-flight engine work, clear horizontal cost history on a separate edge before accepting the next output scanline. Keep vertical row-buffer history; old row column sums cannot be reused for a new row without a separate vertical-update design. See [[Timing and Pipelining]] and [[Project Plan]].
