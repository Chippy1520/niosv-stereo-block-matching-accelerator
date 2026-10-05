# Comparator-tree component synthesis

Quartus Prime Lite 22.1std.0 Build 915, `quartus_map comparator_tree` using disposable `build/comparator-synth/comparator_tree.qpf`/`.qsf`, device **EP4CE115F29C7** and default `LANES=32`, `SAD_W=15`, `D_W=5`.

Result: **Analysis & Synthesis successful; 0 errors, 1 warning** (processor count unspecified in disposable QSF). Report: **1,622 logic cells** and 2,318 total device resources after synthesis; these are **before fitting** and may change. The EDA netlist writer emitted informational multidimensional-array bus-regrouping messages. No fitter, fully constrained timing/Fmax, pinout, board programming, power, 32-engine integration or SDRAM transfer was exercised.

Local simulation evidence: `python scripts/run_tests.py` (46 cases including eight comparator widths) and `python scripts/check_test_sensitivity.py` (seven faults, including two comparator faults). The generated log stays under ignored `build/comparator-synth/` and can be reproduced with the same Quartus top/source settings.
