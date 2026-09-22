# Timing and Pipelining
#design
The first [[Column Sum Buffer]] has registered output and a one-clock feedback update. It is **not** an arbitrarily retimed multi-stage accumulator. The history update contains subtraction and addition; actual achievable frequency requires fitted Quartus timing analysis.

Pipelining the [[Column SAD Engines]] feedforward adder tree and [[Minimum Comparator Tree]] is straightforward if valid, disparity, coordinates and flush controls receive matching delays.

Adding pipeline stages into history_sum feedback naively breaks consecutive-column accumulation. Any such change needs a proven look-ahead/interleaving architecture or a different rolling-sum organization.

Current verification establishes function, not resource use, Fmax, board operation, or whole-accelerator pixel rate.
