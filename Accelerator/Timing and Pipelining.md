# Timing and Pipelining
#design
The first [[Column Sum Buffer]] has registered output and a one-clock feedback update. It is **not** an arbitrarily retimed multi-stage accumulator. The history update contains subtraction and addition; actual achievable frequency requires fitted Quartus timing analysis.

[[Pipelined Column SAD Calculator]] now implements registered absolute differences and a registered balanced reduction tree, with matching valid delays. [[Single SAD Engine]] adds the existing registered horizontal SAD output. The [[Minimum Comparator Tree]] is still planned. Future coordinate/disparity metadata must receive matching delays.

Adding pipeline stages into history_sum feedback naively breaks consecutive-column accumulation. Any such change needs a proven look-ahead/interleaving architecture or a different rolling-sum organization.

For L=ceil(log2(K)), input sampled at edge t reaches the column output after t+L and engine output after t+L+1, once horizontal warmup is complete. Normal row end drains L+1 edges before a separate clear edge. Clear itself aborts in-flight work.

Current verification establishes functional cycle behavior and component synthesis resource estimates, not fitted Fmax, board operation, or whole-accelerator pixel rate. For K=11 the engine has six register stages including the sampling stage, giving an edge offset of five.
