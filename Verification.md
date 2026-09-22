# Verification
#verified
Real simulator: Icarus Verilog 13.0, local portable MSYS2 package in tools/mingw64. Quartus Prime Lite 22.1 Analysis & Synthesis also passed for `Stereo_SAD.qpf`: zero errors, one warning about unspecified parallel processor count. Report: `output_files/Stereo_SAD.map.rpt`. The history array maps to logic rather than block RAM due to asynchronous reads. No fitted timing or hardware test has been performed.

Run from the project root:
```sh
python scripts/run_tests.py
```

The Python runner generates stimulus and independently computes expected output using a length-K deque and full Python sums. Icarus compiles the actual SystemVerilog and vvp compares valid and output data every cycle, including held output on invalid cycles. Any mismatch exits nonzero.

Configurations tested: (K, pixel bits) = (1,8), (2,8), (3,8), (11,8), (16,8), (11,10).
Directed checks: maximum/zero windows, warmup, pointer wrap, valid bubbles, clear with simultaneous valid, reset during traffic. Each configuration also receives 5000 deterministic randomized cycles.

Local generated simulator report: [results.txt](sim/results.txt). Committed milestone evidence: [column-buffer-simulation.txt](docs/verification/column-buffer-simulation.txt). Generated testbenches/vectors: build/. GitHub Actions uploads fresh results for each run.

[[Column Sum Buffer]] · [[Interface Contract]] · [[Timing and Pipelining]]
