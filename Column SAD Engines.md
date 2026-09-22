# Column SAD Engines
#implemented

The single-lane column calculator is now implemented as [[Pipelined Column SAD Calculator]] (`rtl/column_sad.sv`). It feeds [[Column Sum Buffer]] inside [[Single SAD Engine]] (`rtl/sad_engine.sv`).

Each accepted input contains K already-aligned left/right pixel pairs. The calculator uses parallel unsigned absolute differences and a pipelined balanced reduction tree. This is not the image line-buffer frontend or the 32-lane disparity bank.

See [[Testbench Guide]] for separate calculator, buffer and engine tests; [[Timing and Pipelining]] for exact pipeline edges; [[Disparity Bank]] for future replication.
