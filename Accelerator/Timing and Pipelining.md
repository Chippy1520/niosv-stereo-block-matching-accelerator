# Timing and Pipelining
#design
The first [[Column Sum Buffer]] has registered output and a one-clock feedback update. It is **not** an arbitrarily retimed multi-stage accumulator. The history update contains subtraction and addition; actual achievable frequency requires fitted Quartus timing analysis.

[[Pipelined Column SAD Calculator]] implements registered absolute differences and a registered balanced reduction tree, with matching valid delays. [[Single SAD Engine]] adds the registered horizontal SAD output. [[SAD Search Backend]] connects the engine bank to [[Minimum Comparator Tree]], with `max(1, ceil(log2(P_LANES)))` registered pairwise levels (five for 32 lanes), common-interior qualification and matching wall-clock coordinate tags. The hookup is implemented; autonomous scheduling is not.

Adding pipeline stages into history_sum feedback naively breaks consecutive-column accumulation. Any such change needs a proven look-ahead/interleaving architecture or a different rolling-sum organization.

For L=ceil(log2(K)), input sampled at edge t reaches the column output after t+L and engine output after t+L+1, once horizontal warmup is complete. Normal row end drains L+1 edges before a separate clear edge. Clear itself aborts in-flight work.

Current verification establishes functional cycle behavior and component/integrated Analysis & Synthesis resource estimates, not fitted Fmax, board operation or whole-accelerator pixel rate. For K=11 the engine has six register stages including sampling, giving an edge offset of five.

[[Right Column Shift Register]] and [[Left Column Delay]] sample paired columns at edge t and expose registered payload/valid after that edge; downstream registers sample them at t+1. Pauses hold payload history but suppress output validity. [[Column Pairing Verification]] checks those local observation points. [[Stereo Frontend]] adds actual packed-store handoff and aligned tags; [[Stereo SAD Datapath]] verifies the connected path through the winner. Engine-only drain counts above begin at engine inputs, not raw storage reads. The complete path must drain through the reducer and let the final consumer sample before a **separate** horizontal-clear edge; preserve the active vertical rows. The exact full-path edge budget is in [[Stereo SAD Datapath]] and [[Datapath Study Guide#11.3 Implemented continuous-case edge budget|the study trace]].
