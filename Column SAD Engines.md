# Column SAD Engines
#planned
Future RTL, not implemented.
Each disparity lane computes K unsigned absolute pixel differences and a pipelined reduction tree producing one column sum. Align the left image column against the corresponding shifted right-image column. Avoid unsigned-subtraction underflow by compare-then-subtract.

[[Image Line Buffers]] → column differences and adder tree → [[Column Sum Buffer]].
Carry valid and coordinate metadata through every stage. See [[Timing and Pipelining]].
