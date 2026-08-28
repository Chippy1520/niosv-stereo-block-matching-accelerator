# Verification workspace

Keep small deterministic vectors under version control rather than full external datasets.

Recommended tests:

- Single changed/matched pixel.
- Constant-disparity textured plane.
- Two regions with different disparities.
- Border and maximum-disparity cases.
- Equal-cost tie case.
- FIFO and randomized Avalon wait-state tests.
- Complete FPGA-versus-integer-reference map comparison.

Large Middlebury, Scene Flow, and KITTI files should be downloaded separately and remain outside Git.
