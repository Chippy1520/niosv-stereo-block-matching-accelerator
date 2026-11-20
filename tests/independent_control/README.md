# Independent stereo SAD contract replay

## Provenance: blind v1, deliberately strengthened v2

The original v1 was clean-room **test authoring**, not a DUT review. Its author
used only the supplied functional contract, `rtl/stereo_sad_datapath.sv` lines
1–41 (public declarations), and RTL filenames. No RTL body or existing
test/script was read, and no RTL compilation or simulation was run during v1
authoring. Those three source files were frozen before parent-run validation;
the byte-for-byte v1 sources and original evidence remain preserved under
`build/independent-control-validation/frozen-v1-sources/tests/independent_control/`.

**V2 is not a newly blind experiment.** This follow-up author knows the reported
surviving challenge: tying the right write enable to the left passed v1 because
both data buses always carried the correct packed word, even when invalid.
V2 deliberately strengthens both sides symmetrically: on every load an invalid
side carries the full-word bitwise complement of its intended packed word,
masked to `4*P` bits; valid data and idle-cycle zero data are unchanged. No new
randomness is consumed. Scheduling, images, SAD oracle, expected results, and
the SV public-port bench are unchanged. V2 author checks are Python-only;
**the parent/user must freeze v2 before compiling or simulating RTL.**

## Files

- `run_independent.py`: stdlib-only full-image integer SAD oracle, legal caller
  schedule generator, Icarus subprocess runner. Does not import project scripts.
- `tb_independent_replay.sv`: parameterized public-port replay and synchronous
  consumer checks; no hierarchy probes, DUT helper reuse, or rolling-SAD model.
- This README.

## Commands (run from repository root)

```sh
# Python-only validation and generation: NEVER invokes an RTL tool.
python tests/independent_control/run_independent.py --self-check --generate-only --out-dir build/independent_control_author_check

# First actual RTL compile/simulation: parent/user must run after freezing sources.
python tests/independent_control/run_independent.py --self-check --rtl-dir rtl --out-dir build/independent_control_run

# Disposable RTL directory, same frozen test source and deterministic vectors.
python tests/independent_control/run_independent.py --rtl-dir build/disposable_rtl --out-dir build/independent_control_disposable

# One named case, or extra parameters K,P,W,H,LANES,SPARE.
python tests/independent_control/run_independent.py --case odd_k_lane_bank --out-dir build/independent_control_one
python tests/independent_control/run_independent.py --params 5,6,21,11,5,2 --out-dir build/independent_control_extra
```

`--rtl-dir PATH` is the directory directly containing the eleven supplied RTL
filenames. `--out-dir PATH` accepts absolute or relative paths but must resolve
inside this repository's `build/`. Absolute source/output paths with spaces are
passed as individual Python subprocess arguments, not shell commands. Default
executables are `tools/mingw64/bin/iverilog.exe` and `vvp.exe`; override with
`--iverilog PATH --vvp PATH` if needed. No Git operations are used.

Generated files stay in `build/`: `vectors.hex`, `manifest.json` (raw L/R images,
parameters, coverage, per-edge labels), `commands.json` (exact compiler/runner
argument arrays), and `summary.json`. Actual runs additionally create `sim.vvp`,
`compile.log`, `simulation.log`, and `observed.csv`. The runner stops on the first
compiler/simulator failure; simulator exit zero alone is insufficient without
`INDEPENDENT_PASS`. `GENERATED_NOT_SIMULATED` is not a DUT pass.

## Bounded default matrix

| Name | K | P | W | H | LANES | SPARE | Physical banks |
|---|---:|---:|---:|---:|---:|---:|---:|
| one_lane_k1 | 1 | 5 | 9 | 5 | 1 | 2 | 3 |
| odd_k_lane_bank | 3 | 8 | 17 | 9 | 3 | 2 | 5 |
| power_lane_reuse | 2 | 4 | 13 | 7 | 4 | 1 | 3 |

Every case uses three raw-image fixtures: deterministic shifted random texture
(target disparity `LANES-1`, including nonzero winners when LANES>1), maximum
absolute-difference constant images (all disparities tie at maximum cost, so
lowest disparity must win), and independently randomized L/R images. All widths
have partial final words with poisoned non-image padding. Images extend beyond a
physical-bank cycle, forcing bank reuse.

Schedules exercise:

- Left-only, right-only, and joint writes; gaps while one side is not ready.
  Reads begin only after all words of all K rows are initialized on both sides.
- Next-row spare prefetch during reads and bubbles, including equal write/read
  word addresses in different banks. A separate logical-owner/readiness tracker
  asserts the generated caller never writes an active bank, even during bubbles.
- One-/two-edge bubbles with arbitrary ignored x payload, fixed row y/oldest,
  accepted x advancing exactly one from zero. Edge-time, not beat-time, tags.
- Repeat of the first window after a drained separate row clear without any RAM
  reload: horizontal restart, same coordinates, retained pixel storage.
- Row-clear/read coincidence (read must be suppressed), frame-clear/read/load
  coincidence, and both reset and frame-clear aborts striking pending work at
  three phase offsets: 0, LAT//2, LAT-1 after the final accepted beat.
- Quiet post-abort observation followed by reinitialized fresh-pixel restart.
  Normal row ends wait LAT+2 idle edges, including final winner consumption,
  before a **separate** row-clear edge.

The expected mature result is a literal full K-by-K raw-image sum for each d,
with `(cost,d)` minimization. The Python self-check includes hand calculations,
maximum/tie checks, shifted images, and a separately ordered whole-window sum.
The SV bench checks post-edge visibility and then checks the same registered
winner at the following posedge as a clocked sink would see it. Aborts may
explicitly discard the pre-edge consumer sample.

## Assumptions and deliberate non-overconstraints

- LAT is `2+ceil(log2(K))+1+max(1,ceil(log2(LANES)))`. Accepted read at event t
  requires its mature result **after** event t+LAT; sink consumption is t+LAT+1.
- `x>=K+LANES-2`, `y>=K-1` defines the guaranteed common interior. Earlier
  accepted x positions are deliberately **not required either valid or invalid**.
  If valid, their tags, disparity range, row_last, and record packing must still
  be consistent. Their SAD/disparity contents are not compared with a border
  oracle. Outside every scheduled accepted-read slot, valid must be zero.
- A valid result echoes accepted x/y; row_last means accepted x==W-1. Bit31 is
  valid, low SAD_W bits cost, next D_W bits disparity; every unused bit is zero.
  On invalid cycles only valid/result/row_last are constrained; sad/disparity/x/y
  payloads are otherwise ignored.
- Reset/frame-clear/row-clear invalidate pending visibility immediately after
  their synchronous edge. Row-clear is only used after draining, not as an
  additional busy-abort contract. Frame clear has priority over simultaneous
  read/write. Simultaneous row-clear/write acceptance is ambiguous (`may permit
  loads`), so this suite deliberately does not rely on it.
- Frame clear invalidates caller ownership. The suite rewrites complete L/R
  windows before reading after frame clear or reset. It therefore does **not**
  claim to prove frame clear preserves RAM, or that coincident suppressed loads
  did not physically touch RAM: observing those effects would require a defined
  ownership-reacquisition/no-rewrite protocol not supplied here. Row-clear RAM
  preservation is directly exercised.
- The scoreboard tests legal callers, not DUT enforcement of active-bank write
  protection, incomplete-row rejection, or out-of-range inputs. Those illegal
  stimuli have no specified response and are excluded.
- Parameters are positive, SPARE>=1, H>=K, W>K+LANES-2, SAD_W+D_W<=31. Custom
  parameters allow tiny edge cases; the default coverage assertions guarantee
  nonzero-disparity wins only for the selected multi-lane defaults.

## Original v1 author-side checks (historical)

Python oracle self-check and generation completed for all three defaults:
692 / 1762 / 1195 replay edges, respectively; 222 / 394 / 249 visible mature
expectations. Python-only generation also completed for custom
`5,6,21,11,5,2` and minimal `1,1,1,1,1,1`.

An initial Python schedule-coverage assertion exposed a bookkeeping issue:
concurrent-spare counting omitted the first accepted read's newly active window.
It was corrected in the generator before successful generation. No DUT output
was consulted during v1 authoring. At that freeze, SV syntax, compilation, and
DUT behavior had not yet been verified by the parent/user.

## V2 author-side checks

Python-only self-checks passed for all four `(Lvalid,Rvalid)` combinations at
`P=1` and `P=5`, on full and partial words, including unchanged idle payloads
and RNG state. In-memory replay comparison against frozen v1 passed for all
three defaults, custom `5,6,21,11,5,2`, and minimal `1,1,1,1,1,1`: only inactive
L/R data fields changed; all other event fields, images, coverage, labels, and
RNG state matched. The SV bench remained byte-identical to frozen v1. No RTL
compilation or simulation was performed for this v2 patch; no v2 DUT pass or
challenge rejection is claimed.
