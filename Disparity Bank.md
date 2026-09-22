# Disparity Bank
#planned
Future wrapper: 32 lanes, provisionally disparities 0 through 31. Each lane owns [[Column SAD Engines]] and [[Column Sum Buffer]] state. Shared clocks and synchronized accepted-column advancement are required for meaningful comparisons.

Align output windows to the same left-image coordinate. Invalid right-image borders must be masked, not scored as zeros. A common valid-only interior or per-lane mask must be selected before integration.

Send aligned scores and disparity indices to [[Minimum Comparator Tree]]. Runtime search range can potentially mask lanes in a maximum-size bank; that control is not implemented yet.
