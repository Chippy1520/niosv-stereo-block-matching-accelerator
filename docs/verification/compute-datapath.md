# Complete compute datapath — observed verification

> Historical K-only compute checkpoint. Its 130-case results, source hashes and utilization below remain unchanged. [Current spare-row verification](spare-row-prefetch.md) records the new 142-case run, updated area and native-license limit.

Scope: `sad_search_backend` and `stereo_sad_datapath`, built only after the independent advocate/skeptic/evidence reviews were reconciled in [the frozen specification](../accelerator-datapath-spec.md). The top connects real packed row stores, alignment/cache, parallel SAD engines, common-interior qualification, minimum reduction and result tags. It is **not** a controller, Nios V/Avalon integration or board result. Nothing in this increment is committed or pushed before the user's simplification review.

## Functional checks

- Each new functional module has a registered standalone bench and an exact-full-source, line-explained Obsidian walkthrough: [[SAD Search Backend]] and [[Stereo SAD Datapath]]. `python scripts/check_walkthrough.py` passed for all 13 functional modules.
- The backend bench supplies deterministic raw-image columns. The complete-path bench performs real packed loads into both row stores. Both independently recompute every candidate's complete raw K×K pixel SAD, then serially minimize `(cost,d)`; they do not build expectations from DUT history. Internal candidate cost/valid outputs are observed only for comparison.
- Every clock checks due output, valid, SAD, disparity, x/y and row-last after NBA updates and again at the next consumer edge. Complete-path checks also compare the exact 32-bit result, including zero on every invalid beat. Normal rows use the minimum complete-path drain then a **separate** clear edge.
- Fixtures include zero/ties, maximum unsigned contrast, independent hashed images, a known nonzero image shift, bubbles, odd/padded lane counts, narrow/no-interior images, bank rotation, resets and frame-clear aborts with qualified results in flight. The backend separately tests y below the common vertical interior. The top keeps vertical RAM across horizontal row clear.
- `python scripts/check_test_sensitivity.py` passed: **33 compiled targeted production-RTL faults rejected**, up from 26. New faults reverse disparity wiring, skip lane warmup, skew tags by one edge, leak partial-search winners, corrupt packed disparity/invalid zeros and ignore backend row clear. Production RTL hashes remain unchanged by the mutations.
- `python scripts/run_testbench_lab.py --check-faults --examples` passed: beginner reference, two teaching-fault rejections and the original seven-module/40-edge lesson. These are not additional production parameter cases.

**Default whole-regression status: PASS — all 130 cases.** The final `python scripts/run_tests.py` exited zero and ended with `PASS: 130 simulation cases completed; suite=all.` The retained report is `build/compute-regression-results.txt`, including all ten backend and ten complete-path cases. Full-width K=11/32-lane cases cover 640 columns and 38 rows, not a 640×480 complete frame; they compare 22,143 backend and 22,139 packed-path outputs across directed/stress/abort exercises. Odd 641-wide cases use seven lanes.

An initial run hit the 600-second process cap while repeatedly hashing raw fixture pixels; it did not report a numerical mismatch. The final bench caches **only immutable raw-image pixels**, still summing each independent complete K×K candidate window. No DUT recurrence, expected-cost cache, row reduction or coverage reduction was introduced. The workflow allows 45 minutes for the complete CPU-heavy regression, not a hardware timing budget.

**Fresh final-source guard:** a temporary harness removed itself before executing checks. All 13 source/walkthrough mappings and 33 fault rejections pass; 12 additional actual-DUT simulations using cached and original uncached raw-window references produce identical pass summaries for K=1, odd lanes and 10-bit pixels. An actual oversized-record instance is rejected at time zero. The guard checks the complete 130-case report and confirms that current RTL hashes match all three integrated A&S runs and native-compilation evidence. `build/compute-final-check/evidence.json` records commands, real return codes and source hashes; no functional source changed during verification.

### Additional independent-seed/boundary checks

`build/verify_compute_extra.py` actually executed nine additional parameter cases with seed 987654321 and zero randomized tail cycles. `build/compute-extra/evidence.json` contains commands, return codes, source hashes and logs:

- Three lanes at K=3/P=8/W=13/H=14, backend then complete path.
- Exactly one common-interior column: K=3/P=8/W=5/H=3/LANES=3, backend then complete path.
- Empty vertical interior: K=3/H=2, backend then complete path.
- K=1/P=8/W=1/H=1/LANES=1, backend then complete path.
- **All 480 rows including y=479:** K=3/P=8/W=64/LANES=5 complete path passed, checking 27,998 outputs across directed frames and abort exercises. This is high-y/full-height evidence, not default-width/default-K full-frame coverage.
- A separate intentional mid-row right-lane hole was rejected with `SEARCH_PROTOCOL missing lane column`. Prefix warmup is permitted; arbitrary per-lane gaps are **not** supported or silently repaired.
- An additional K=3/P=10/W=13/H=14/five-lane packed-path case passed with seed 987654321 and 200 randomized tail cycles (`build/compute-extra/wide-pixel.log`).

### Native Questa

Both new benches and actual complete-path dependencies compiled natively with Questa Intel Starter FPGA Edition 2021.2: zero errors. Fresh runtime attempts for **both** benches failed at design loading because the user's existing Questa instance holds the one-session uncounted node-locked license. Logs: `build/compute-extra/native-compile.log` and `native-runtime-{search,datapath}.log`. The existing instance was not closed or killed. Functional pass evidence above is Icarus, not a fabricated new native simulation pass.

## Exact timing and 32-bit encoding

Let `E=ceil(log2(K))+1`, `R=max(1,ceil(log2(LANES)))`. Input sampled by the backend at t produces a winner **after edge t+E+R**. The frontend adds two edges from its sampled read request. At K=11/LANES=32 the result is available after read edge r+12; the earliest normal clear is r+13, also the edge at which a synchronous consumer can capture that last result. K=1/LANES=1 uses backend +2, complete path +4. Packing is combinational.

Coordinates are bottom-right anchors. Output requires `x>=K+LANES-2`, `y>=K-1`, in image bounds, and all real lane results valid for that coordinate. No partial-search winner is emitted. Tags shift on every clock, including bubbles.

Default 32-bit record: `[14:0]=SAD`, `[19:15]=disparity`, `[30:20]=0`, `[31]=valid`. Invalid records are entirely zero. Generic positions derive from `SAD_W`/`D_W`; a synthesis-excluded time-zero simulation guard rejects `SAD_W+D_W>31`, which remains a caller parameter obligation in synthesis. Coordinates and row-last remain sidebands; no undocumented frame bit is invented.

## Actual integrated Analysis & Synthesis

Quartus Prime Lite 22.1, Cyclone IV E `EP4CE115F29C7`, **real `stereo_sad_datapath`**, K=11/P=8/IMG_W=640/IMG_H=480. The existing inference helper now supports `--top datapath` and generates isolated projects, recording hashes of every dependency. These are not reduced-width smoke tops.

| Fixed search lanes | Logic elements | Registers | Logical memory bits | M9K RAM nodes | Errors / warnings |
|---|---:|---:|---:|---:|---|
| 1 | 2,715 | 755 | 112,640 | 22 | 0 / 2 |
| 3 | 4,525 | 1,724 | 112,640 | 22 | 0 / 2 |
| 32 | 30,537 | 15,519 | 112,640 | 22 | 0 / 2 |

Observed isolated evidence directories:

- `build/datapath-synthesis/k11_p8_w640_t1_r8q222af/evidence.json` — 67.34 seconds.
- `build/datapath-synthesis/k11_p8_w640_t3_6syeh8m7/evidence.json` — 82.16 seconds.
- `build/datapath-synthesis/k11_p8_w640_t32_a4ij6y9i/evidence.json` — 343.55 seconds.

Warnings on every build: processor-count setting (one processor requested) and constant output pins. The final guard inspected the actual default 32-lane `13410` child messages: they name exactly `result_o[20]` through `[30]`, the deliberately zero reserved field. There are zero embedded multipliers and zero PLLs in these A&S summaries.

Reproduce, for N=1,3,32:

```sh
python scripts/check_row_buffer_synthesis.py --top datapath --taps N --quartus-map /path/to/quartus_map
```

**Limits:** these configurations search different fixed ranges. They are not equivalent-search performance builds: no replay/group scheduler or cross-group merge exists. This is measured synthesis area/RAM inference only, **not fitting, TimeQuest closure, 32-lane achieved throughput, power, bus/SDRAM transport, Nios V integration or board success**. Output acceptance and safe RAM-bank reuse remain caller obligations.

## Interactive review gate

Review components one at a time, starting with packed row storage, then alignment, one engine, the backend and composition. Distinguish necessary state/registered timing from optional readability changes. Make no speculative extra wrappers/FIFOs. No commit, push or CI run is claimed for this uncommitted increment.
