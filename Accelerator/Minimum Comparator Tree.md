# Minimum Comparator Tree
#planned
Future pipelined pairwise minimum reduction over (SAD, disparity) tuples from [[Disparity Bank]]. Carry both fields through every stage. Define deterministic ties, proposed smaller disparity wins. Invalid lanes must lose against valid lanes. If all lanes are invalid, no valid result.

Output is disparity, not metric depth. Depth requires focal length, baseline and calibrated rectification; zero disparity must be handled explicitly. See [[Timing and Pipelining]].
