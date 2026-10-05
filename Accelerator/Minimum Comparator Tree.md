# Minimum Comparator Tree
#implemented
Standalone [[Minimum Comparator Tree - Code Walkthrough|pipelined comparator RTL]] reduces the valid `(SAD, disparity)` tuples from a future [[Disparity Bank]]. Smaller SAD wins; on ties, smaller disparity wins. Invalid lanes (including padded leaves) cannot win, and an all-invalid beat has `valid_o=0`. For 32 lanes, five registered pairwise levels accept one aligned candidate set per clock. The caller still owes coordinate alignment, border masking, row-drain control and any cross-group merge. No multi-lane bank is connected yet.

Output is disparity, not metric depth. Depth requires focal length, baseline and calibrated rectification; zero disparity must be handled explicitly. See [[Timing and Pipelining]] and [[Verification Map]].
