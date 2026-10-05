# Timing and Pipelining
#design
The first [[Column Sum Buffer]] has registered output and a one-clock feedback update. It is **not** an arbitrarily retimed multi-stage accumulator. The history update contains subtraction and addition; actual achievable frequency requires fitted Quartus timing analysis.

[[Pipelined Column SAD Calculator]] implements registered absolute differences and a registered balanced reduction tree, with matching valid delays. [[Single SAD Engine]] adds the existing registered horizontal SAD output. The standalone [[Minimum Comparator Tree]] adds `max(1, ceil(log2(P_LANES)))` registered pairwise levels after aligned engine outputs (five for 32 lanes); the **bank-to-tree hookup** remains planned. Future coordinate metadata must receive matching delays.

Adding pipeline stages into history_sum feedback naively breaks consecutive-column accumulation. Any such change needs a proven look-ahead/interleaving architecture or a different rolling-sum organization.

For L=ceil(log2(K)), input sampled at edge t reaches the column output after t+L and engine output after t+L+1, once horizontal warmup is complete. Normal row end drains L+1 edges before a separate clear edge. Clear itself aborts in-flight work.

Current verification establishes functional cycle behavior and component synthesis resource estimates, not fitted Fmax, board operation, or whole-accelerator pixel rate. For K=11 the engine has six register stages including the sampling stage, giving an edge offset of five.

[[Right Column Shift Register]] accepts a complete right column at edge t and exposes registered taps after that edge. Pauses hold its horizontal history but suppress output validity. Matching left-column/valid and coordinate delays are required before pairing; those are not implemented. Engine-only drain counts above begin at engine inputs. A future controller draining from the row-buffer side must account for the extra frontend register handoff, then clear horizontal histories separately while keeping vertical row-buffer history.
