# Datapath Study Guide

[[Home]] → [[System Architecture]] → [[Accelerator Architecture]] → **this guide** → [[Stereo Frontend]] / [[SAD Engine Architecture]] → individual modules.

> **Read this as a course, not a test command list.** For every module: understand its job, draw its state, predict its clock trace, write a small independent bench, inspect waves, then compare with the production bench. The linked module notes contain the exact full RTL and code-adjacent explanations; this guide connects their implementation, mathematics, timing and verification into one datapath story.
>
> **Scope:** seven implemented functional modules, the tested single-engine connection and the local left/right pairing. The complete frontend, parallel engine bank, metadata/controller and accelerator top are still planned. The runnable lesson experiments below do not implement that missing wrapper or prove board operation.

## Contents and study order

1. [The calculation and the intended datapath](#1-the-calculation-and-the-intended-datapath)
2. [Widths, packing and SystemVerilog essentials](#2-widths-packing-and-systemverilog-essentials)
3. [Clock edges, warmup, bubbles and clear](#3-clock-edges-warmup-bubbles-and-clear)
4. [Circular image-row buffer](#4-circular-image-row-buffer)
5. [Right-column disparity shift cache](#5-right-column-disparity-shift-cache)
6. [Left-column sampling delay](#6-left-column-sampling-delay)
7. [Pipelined column-SAD calculator](#7-pipelined-column-sad-calculator)
8. [Circular column-cost history buffer](#8-circular-column-cost-history-buffer)
9. [Single SAD engine](#9-single-sad-engine)
10. [Minimum comparator tree](#10-minimum-comparator-tree)
11. [How the pieces must connect](#11-how-the-pieces-must-connect)
12. [Run the worked examples and write your own benches](#12-run-the-worked-examples-and-write-your-own-benches)
13. [Verification checklist and completion gate](#13-verification-checklist-and-completion-gate)

For the first bench-writing session, use [[Hands-on Testbench Lab]]. Return here for each module's specific contract and test design. Read [[Testbench Guide]] for the larger regression matrices. Use [[Accelerator Blocks.canvas]] and [[SAD Engine Blocks.canvas]] as architectural maps, not evidence that every planned connection exists.

## 1. The calculation and the intended datapath

### 1.1 What stereo block matching computes

For teaching, anchor a window at its **bottom-right** left-image pixel `(x,y)`. Pixels are unsigned grayscale values. For disparity `d`, the right-image window is displaced horizontally by `d`:

$$
S_d(x,y)=\sum_{h=0}^{K-1}\sum_{v=0}^{K-1}
\left|L(y-v,x-h)-R(y-v,x-h-d)\right|.
$$

Smaller SAD means a closer photometric match, not a guarantee of correct depth. Equal costs are resolved by choosing the smaller disparity. This anchor explains the mathematical indexing; hardware coordinate tags and final output-map placement have not yet been implemented.

Split the work into a vertical cost and a horizontal accumulation:

$$
C_d(x,y)=\sum_{v=0}^{K-1}|L(y-v,x)-R(y-v,x-d)|,
\qquad S_d(x,y)=\sum_{h=0}^{K-1}C_d(x-h,y).
$$

That decomposition is why the design does **not** recompute every pixel difference of every overlapping square from scratch. A lane computes a new vertical cost, retains previous column costs and forms the full-window total. Our engine **testbench**, however, deliberately recomputes the full raw-pixel square to provide an independent check.

### 1.2 Three different kinds of data

| Data | Meaning | Example at K=11, 8-bit pixels |
|---|---|---|
| Packed pixel column | K grayscale samples at one x | 88-bit vector; not a number to add as a whole |
| Column cost | Sum of K absolute differences | 12-bit scalar, legal maximum 2805 |
| Window SAD | Sum of K column costs | 15-bit scalar, legal maximum 30855 |

An image-row buffer stores **pixels**. The right shift cache stores **whole pixel columns**. The per-engine history buffer stores **column costs**. Mixing up these three stores creates the wrong architecture even if every signal happens to be called a column.

### 1.3 Intended flow, and current implementation boundary

```text
L pixel → circular_row_buffer → left_column_delay ──broadcast──┐
                                                             │
R pixel → circular_row_buffer → right_column_shift → tap d ───┤
                                                             ▼
                   one sad_engine for each disparity d:
                   column_sad → column_sum_buffer → (SAD_d, valid_d)
                                                             │
                        aligned lane candidates ─────────────┘
                                      ↓
                            comparator_tree
                                      ↓
                          best (SAD, disparity)
```

The boxes exist individually. `sad_engine` already connects its two child blocks. The pairing bench connects only the left delay and right cache. The arrows from row buffers through a lane bank to the comparator are the **intended integration**, not an existing complete accelerator. The control/metadata path is omitted from the drawing for readability, not because it is unnecessary.

### 1.4 Module/source/solution map

| Study chapter | Authoritative RTL | Exact-code note | Production bench |
|---|---|---|---|
| Image row ring | `rtl/circular_row_buffer.sv` | [[Circular Row Buffer]] | `tests/rtl/tb_circular_row_buffer.sv` |
| Right disparity cache | `rtl/right_column_shift.sv` | [[Right Column Shift Register]] | `tests/rtl/tb_right_column_shift.sv` |
| Left register | `rtl/left_column_delay.sv` | [[Left Column Delay]] | `tests/rtl/tb_left_column_delay.sv` |
| Vertical arithmetic | `rtl/column_sad.sv` | [[Pipelined Column SAD Calculator]] | `tests/rtl/tb_column_sad.sv` |
| Horizontal arithmetic/history | `rtl/column_sum_buffer.sv` | [[Column Sum Buffer - Code Walkthrough]] | `tests/rtl/tb_column_sum_buffer.sv` |
| One complete lane | `rtl/sad_engine.sv` | [[Single SAD Engine]] | `tests/rtl/tb_sad_engine.sv` |
| Winner selection | `rtl/comparator_tree.sv` | [[Minimum Comparator Tree - Code Walkthrough]] | `tests/rtl/tb_comparator_tree.sv` |
| Local pairing, not another functional module | — | [[Column Pairing Verification]] | `tests/rtl/tb_column_pairing.sv` |

`rtl/circular_row_buffer_synth.sv` is a synthesis-smoke wrapper with a smaller fixed row width, not another datapath algorithm. It does not establish a full-size fitted row-memory implementation.

## 2. Widths, packing and SystemVerilog essentials

### 2.1 Parameters are hardware choices

`K`, `PIXEL_W`, `IMG_W`, `TAPS`, `LANES`, `COL_W`, `SAD_W` and `D_W` are **elaboration-time parameters**. They determine how much hardware is generated. They are not CPU-controlled configuration registers. Runtime kernel/disparity configuration requires a separate design that is not present here.

Use `P=PIXEL_W`, `B=K*P` for the packed pixel-column width, and `CW` for the column-cost width in your notes:

$$
C_{max}=K(2^P-1),\qquad S_{max}=K^2(2^P-1).
$$

The implemented conservative defaults are `CW=P+$clog2(K)` and `SW=P+$clog2(K*K)`. Minimum mathematical widths can instead be derived as `ceil(log2(maximum+1))`; do not narrow the actual ports without changing their contract and re-verifying the design.

| Quantity | Formula | Current default |
|---|---|---|
| Pixel column B | K×P | 88 bits |
| Column scalar CW | P+ceil(log2 K) | 12 bits |
| Window scalar SW | P+ceil(log2 K²) | 15 bits |
| Right tap payload bus | TAPS×B | 2816 bits for 32 taps |
| Right validity mask | TAPS | 32 bits |
| Comparator cost bus | LANES×SAD_W | 480 bits for 32×15 |
| Comparator ID width | max(1,ceil(log2 LANES)) by default | 5 bits |
| Comparator ID bus | LANES×D_W | 160 bits for 32×5 |

**Naming trap:** the local `COL_W` in `right_column_shift.sv` is `K*PIXEL_W`, the width of a **pixel vector**. The parameter `COL_W` in `column_sad.sv` is the width of a **scalar cost**. Equal names in separate module scopes do not mean equal representations.

### 2.2 Packing: learn this before testing arithmetic

Row `j` occupies `[j*P +: P]`; `+:` selects P bits upwards from the starting bit. Row zero, the oldest image row, is in the least-significant slice. With K=3 and oldest-to-newest samples `[1,5,9]`:

```systemverilog
// Packing example, not a separate RTL module:
// {newest_row, middle_row, oldest_row}
// {8'd9, 8'd5, 8'd1} == 24'h090501
```

A right tap contains that same row ordering. Tap `d` starts at `[d*B +: B]`. Its row `j` starts at `[d*B+j*P +: P]`. Tap zero is the least-significant **column** slice; it is not the oldest disparity history.

Comparator lane `n` similarly occupies `[n*SAD_W +: SAD_W]` and `[n*D_W +: D_W]`. Keep cost, ID and validity of a lane together. A correctly sized flattened bus with the wrong slice stride still compiles and silently computes the wrong result.

### 2.3 Syntax that describes hardware

| Construct | Meaning in this project | What to watch |
|---|---|---|
| `wire` / continuous `assign` | A driven connection or combinational expression | No storage is created just by declaring a wire |
| `logic` / `reg` updated on a rising edge | Registered state | Storage comes from its use in the clocked block |
| `always_ff @(posedge clk)` | Synchronous state update | Reset here is synchronous even though named `rst_n` |
| Nonblocking `<=` | Compute from old state, commit after sampling | Essential for simultaneous shifting and pipeline stages |
| `generate` / `genvar` | Build repeated hardware at elaboration | Not a software loop executed once per image sample |
| A `for` loop inside a clocked block | Repeated register assignments at the same edge | It does not spend one extra clock per loop iteration |
| `$clog2` | Constant ceiling-log width/stage calculation | K=1 requires special care where a zero-width vector would result |
| `W'(expression)` | Size cast to W bits | Narrow casts truncate; they do not saturate |
| Concatenation / zero extension | Preserve unsigned value in a wider adder | Signed extension would change grayscale values above the sign boundary |
| `synthesis translate_off` guards | Simulation-only parameter checks | They are not physical datapath validation logic |
| `default_nettype none` | Reject accidental implicit nets | Helps catch misspelled signals instead of creating a hidden one-bit wire |

Quartus Lite 22.1 needs separately declared genvars for these sources. Preserve the existing syntax rather than changing to inline `for (genvar ...)` declarations that failed in this environment.

## 3. Clock edges, warmup, bubbles and clear

### 3.1 Use one timing convention

Let `t` be the rising edge at which an input is sampled. “Output after edge t” means after nonblocking assignments settle. A downstream register on the **same clock** samples the old upstream register at t, then sees the new output at **t+1**.

A sampling stage followed by L registered additions contains L+1 register stages, but its output edge is `t+L` relative to its input sampling edge. Do not confuse register-stage count with this edge offset.

| Block | Input sampled at t → output available after | Warmup counted in accepted samples |
|---|---|---|
| `circular_row_buffer` | t | Previous K−1 complete image rows must exist at that x |
| `right_column_shift` | t | Tap d needs d+1 accepted columns since clear |
| `left_column_delay` | t | None |
| `column_sad` | t+ceil(log2 K) | None; pipeline latency only |
| `column_sum_buffer` | t | First valid window on the Kth accepted cost |
| `sad_engine` | t+ceil(log2 K)+1 | First valid window corresponds to the Kth accepted input column |
| `comparator_tree` | t+M−1, M=max(1,ceil(log2 LANES)) | No history warmup; M registered reduction levels |

The K=1 calculator outputs after its sampling edge. The K=1 engine still has the downstream history/pass-through register and therefore outputs at t+1. The one-lane comparator still uses one registered reduction level and outputs after t.

### 3.2 A bubble is not a global pipeline stall

A source beat with `valid_i=0` is not accepted. Row cursors and accepted-column histories do not advance. But calculator/comparator pipeline validity still advances with the clock, and older accepted beats can emerge during that bubble.

- Delay: hold payload, output valid becomes zero after this edge.
- Right cache: hold payload **and occupancy**, suppress all tap-valid bits for this beat.
- Row ring: hold cursor/storage/output payload, suppress `valid_o` and `row_last_o`.
- Cost-history buffer: hold its history/total/output payload, suppress its immediate output valid.
- Calculator and engine: older work can still produce output. Do not assert “input invalid implies output invalid at this same edge”.
- Comparator: older candidate sets can still produce output; invalid final results explicitly drive zero cost and zero ID.

Invalid payload is not interchangeable with a valid zero cost. Zero is often the **best** possible match, so validity must be checked separately.

### 3.3 Reset, clear and normal row completion

All seven modules have `clk`, synchronous active-low `rst_n`, and synchronous active-high `clear_i`. At a sampling edge, `!rst_n || clear_i` wins over new valid input. A simultaneous valid beat is discarded. Changing reset/clear between edges must not immediately change these registered outputs.

There are two different actions:

1. **Abort:** clear calculator/engine state immediately and intentionally discard pending work.
2. **Normal row end:** stop new engine input, allow `ceil(log2 K)+1` drain edges, then clear the engine on a **separate** edge. Otherwise the last valid windows are lost.

This is an **engine-local** drain rule. It is not proof that a downstream comparator/output FIFO has drained. A future controller must account for all remaining consumers before clearing them.

**Clear scope matters:** the row ring preserves vertical history across normal image rows. The right disparity cache and horizontal cost history must not mix one output row with the next. Do not connect one indiscriminate “row clear” to every block and erase the vertical history you still need.

## 4. Circular image-row buffer

**Source:** `rtl/circular_row_buffer.sv`. **Full code:** [[Circular Row Buffer]]. **Questa part:** `row`.

### Purpose, ports and stored state

It converts one accepted raster pixel stream into K-pixel vertical columns. Instantiate one per image; it does not pair left/right, shift disparities or compute SAD.

| Port/parameter | Contract |
|---|---|
| `K`, `PIXEL_W`, `IMG_W` | Positive compile-time row depth, pixel width and raster width |
| `valid_i`, `pixel_i[P-1:0]` | One accepted pixel when valid, at the current cursor |
| `valid_o`, `column_o[B-1:0]` | A complete registered vertical column after sufficient rows exist |
| `row_last_o` | True only with a complete column at x=IMG_W−1; not a warmup-row end signal |

State: `row_mem[K][IMG_W]`, horizontal cursor `x`, write `slot`, and saturated `rows_filled`. The logical payload store is K×IMG_W×P bits: 56320 bits per image at defaults. This is declared storage, **not** a fitted resource count.

### How the ring actually works

1. Accepted input writes `row_mem[slot][x]`.
2. Older rows are read from `(slot+j+1)` wrapped into the K slots. The sum is wide enough to avoid truncation before comparison.
3. Since the largest sum needs at most one wrap, the RTL uses compare/subtract rather than a general `% K` divider.
4. The newest row is **pixel_i itself**, bypassing the memory write. This avoids needing the just-written memory value to appear immediately.
5. At the final x, the cursor wraps, slot advances modulo K and the completed-row count increases. A bubble changes none of these.
6. Output becomes valid when `rows_filled >= K−1`. It reads the previous K−1 rows at that x plus the arriving pixel.

For K=3: write rows into slots 0,1,2; the third row's slot 2 reads older slots 0 and 1. On the fourth row, slot 0 reads older slots 1 and 2. The physical slot order changes; the output's oldest-to-newest row order does not.

Reset/clear does not bulk-erase the memories. It resets cursors/readiness and zeros registered outputs. Old memory must remain unreachable until the new stream rewrites enough complete rows. This is why warmup tests must also follow a clear after nonzero image data.

**Implementation limit:** these sources use combinational row-memory reads and registered output. Mapping to synchronous FPGA block RAM is a later fitting/timing pass, not merely a naming change. A RAM read register would alter the interface latency unless explicitly accommodated.

### Predict, then test

For K=3/W=4, feed rows `[1,2,3,4]`, `[5,6,7,8]`, `[9,10,11,12]`. The first eight accepted pixels produce no complete column. The next four produce:

| x | Oldest → newest | Packed value | valid | row_last |
|---|---|---|---|---|
| 0 | 1,5,9 | `090501` | 1 | 0 |
| 1 | 2,6,10 | `0a0602` | 1 | 0 |
| 2 | 3,7,11 | `0b0703` | 1 | 0 |
| 3 | 4,8,12 | `0c0804` | 1 | 1 |

| Test you must write | What it catches |
|---|---|
| Distinct x and y pixel patterns, not a constant image | Wrong row slot, x address or row packing |
| Insert a pause before the final pixel of a row | Cursor accidentally advances on invalid cycles |
| Continue through more than two complete ring rotations | Incorrect wrap or stale row selection |
| Clear in the middle of a populated image; feed fewer than K rows | Old image data incorrectly appears as valid |
| Clear/reset with valid input and nonzero pixel | Control priority and discarded input |
| K=1, IMG_W=1, non-power-of-two K and IMG_W | Width-zero corner cases and improper binary wrap |

**Write the reference:** keep a flat array of original accepted pixels. Derive `x=n%W`, `y=n/W`; when y≥K−1, index `(y−K+1+j)*W+x`. Do **not** duplicate the DUT slot arithmetic. Compare all row slices, valid and row_last after the edge.

**Observe:** x, slot, rows_filled, pixel_i, column_o, valid_o, row_last_o. Internal signals are for explaining a failure; the expected column comes from your input image.

**Exercise:** draw the slot contents through the fourth row. Explain why the arriving pixel is bypassed and why normal row end must not clear this block.

## 5. Right-column disparity shift cache

**Source:** `rtl/right_column_shift.sv`. **Full code:** [[Right Column Shift Register]]. **Questa part:** `shift`.

### Purpose, ports and state

Input `column_i[B-1:0]` is one whole right-image vertical column. Output `columns_o[TAPS*B-1:0]` holds columns `R[x]`, `R[x−1]`, …; `tap_valid_o[TAPS-1:0]` says which taps are usable for the current beat. `TAPS` is positive and defaults to 32.

State is `columns[0:TAPS-1]`, `occupied[TAPS-1:0]` and `beat_valid`. Default payload storage is 2816 bits, excluding validity state and synthesis overhead.

### How it is implemented

On an accepted edge, tap zero captures the incoming vector and tap d captures the **old** tap d−1. Nonblocking assignments make these simultaneous moves, not a repeated software shift that overwrites its own source.

Occupancy shifts in the same way, with tap zero occupied after each accepted input. `beat_valid` records this edge's input valid. The output mask is `occupied & {TAPS{beat_valid}}`.

This separates two facts: “a history entry exists” and “there is a new valid beat to pair with the left column”. A bubble keeps occupancy and data but removes all outward validity for that beat. Tap displacement counts accepted columns, not elapsed clocks.

### Predict, then test

Use three distinct whole columns A/B/C. With TAPS=3:

| Input beat | tap 0 / tap 1 / tap 2 | mask, bit 0 on the right |
|---|---|---|
| A accepted | A / zero / zero | `001` |
| B accepted | B / A / zero | `011` |
| Pause with different input pins | B / A / zero, held | `000` |
| C accepted | C / B / A | `111` |
| Clear with valid D | zero / zero / zero; D discarded | `000` |
| D accepted after clear | D / zero / zero | `001` |

Write tests for every tap's first valid beat, repeated pauses, more accepted columns than tap depth, one tap, 32 taps, distinct values in **every packed row**, and clear followed by different row data. A test using the same byte in every row cannot expose swapped row slices.

**Write the reference:** append only accepted input vectors to a log. Tap d is `log[count−1−d]` when d<count; on a bubble expect the payload to hold but the mask to be zero. On clear reset the logical log length. This reference does not reproduce a shift-register chain.

**Observe:** columns, occupied, beat_valid and the flattened outputs. Verify pre-edge hold for synchronous control and compare after-edge values. Later pairing tests must also check the next consumer edge.

**Exercise:** explain why tap d is R[x−d], not R[x−d clock cycles], and why occupancy alone is an unsafe engine-enable signal.

## 6. Left-column sampling delay

**Source:** `rtl/left_column_delay.sv`. **Full code:** [[Left Column Delay]]. **Questa part:** `delay`; start with the simpler `lab`.

### Purpose, ports and implementation

The left path needs **one sampling register**, matching the right cache's output registration. It does not need TAPS registers: the right cache stores different spatial disparities, while every lane needs the same current L[x].

`column_i[B-1:0]` → registered `column_o[B-1:0]`; `valid_i` → registered `valid_o`. State is only those output registers. On reset/clear, both zero. Otherwise valid follows the sampled input and payload updates only when that input is valid.

At edge t, the delay and right cache capture L[x] and R[x]. After t the pair is available. At t+1 a clocked engine can consume L[x] with R[x−d]. Omitting this left register would pair a changing direct left input with an older registered right beat.

### Predict, then test

Start with K=1/P=8: accept `12`, accept `a5`, pause with input `ff`, clear with valid `ff`, accept `3c`. Expected `(valid,payload)` is `(1,12)`, `(1,a5)`, `(0,a5)`, `(0,00)`, `(1,3c)` after each sampled edge.

1. Build a clock, instantiate the DUT with explicit named ports and hold reset through a rising edge.
2. Drive at the falling edge. Before the next rising edge verify that changed input/reset/clear has not changed the output early.
3. Compare after NBA settlement. A bubble checks **both** valid=0 and held payload.
4. Test back-to-back accepted vectors, long pauses, reset-only, clear-only, simultaneous reset/clear/valid, K=1 and multi-row vectors.
5. Change one packed row at a time to find a wrong payload width or slice.

**Write the reference:** an expected valid bit and expected vector, updated from stimulus only. Inspect [[Hands-on Testbench Lab]] for the line-explained tick task and safe scratch-copy fault injection.

**Exercise:** deliberately break a scratch copy so payload updates during a bubble. Your bench must compile successfully, then reject the held-payload violation. A compile error is not a successful sensitivity test.

## 7. Pipelined column-SAD calculator

**Source:** `rtl/column_sad.sv`. **Full code:** [[Pipelined Column SAD Calculator]]. **Questa part:** `column`.

### Purpose and ports

It accepts already-aligned `left_column_i[B-1:0]` and `right_column_i[B-1:0]` with `valid_i`, and returns `column_sum_o[CW-1:0]` with delayed `valid_o`. It has no disparity search, image addressing, horizontal history or coordinates inside.

### Arithmetic and register structure

1. Extract each unsigned pixel pair from the same packed row slice.
2. Compare before subtracting: `left>=right ? left-right : right-left`. That keeps the difference nonnegative in P bits, including 255 versus zero.
3. Zero-extend each difference to CW and register it when valid input arrives.
4. Let L=ceil(log2 K), LEAVES=2^L. Pad unused leaves with **zero**, the neutral element for addition.
5. Add neighboring nodes through L registered tree levels, all CW bits wide.
6. Advance a valid pipeline in parallel. Each adder updates on its previous stage's valid, not on this edge's raw input valid.

All row differences are parallel hardware. The balanced pipelined tree shortens the combinational add path compared with one long serial combinational sum. It adds register stages and does not establish fitted frequency by itself.

For K=11: 11 real differences, a 16-leaf padded structure, four registered addition levels plus the difference registers. Input sampled at t gives output after t+4. For K=3 it is after t+2. Sustained accepted inputs can produce a cost each clock after fill; this is a component capability, not measured integrated 32-lane throughput.

### Predict, then test

For K=3, L=`[10,50,200]`, R=`[20,30,100]`: differences are 10,20,100 and the cost is **130**. An isolated input at local edge 0 yields valid=0 at edges 0 and 1, valid=1/cost=130 at edge 2, then valid=0 with held cost at edge 3.

| Test | Expected / failure targeted |
|---|---|
| Identical vectors | Zero, delayed by the exact pipeline offset |
| All maximum pixels versus zero, both directions | K×(2^P−1), no signedness or overflow error |
| One nonzero difference walked through every row | Every real leaf contributes; no row omission |
| K=3/11 and power-of-two K | Correct zero padding and reduction depth |
| Distinct sums on consecutive accepted edges | No swapped/duplicated pipeline outputs |
| Bubble between two accepted inputs | A timed gap, not stalled old work |
| Clear at every pipeline occupancy offset | No old valid cost emerges after abort |
| K=1 | Difference-stage-only timing, not an extra addition stage |

**Write the reference:** serially sum unsigned absolute differences using a wider testbench integer. Schedule that mathematical result for `accepted_edge+L`. Advance the due-edge model on every clock, including bubbles. Clear all pending expectations on reset/clear. Compare valid every edge and the documented held payload when invalid.

Do not use the DUT tree structure or its internal column output to compute expected sums. The production bench's `direct_column` function is the worked solution to read after writing your own.

**Observe:** valid_pipe, real difference registers, successive tree nodes, valid_o and column_sum_o. Distinguish debug visibility from reference-model input.

**Exercise:** draw the K=3 four-leaf tree and track two different inputs separated by a bubble. Explain why the final output can remain valid while this edge's input is invalid.

## 8. Circular column-cost history buffer

**Source:** `rtl/column_sum_buffer.sv`. **Full code:** [[Column Sum Buffer - Code Walkthrough]]. **Math:** [[Rolling SAD Math]]. **Questa part:** `buffer`.

### Purpose, ports and state

Input `column_sum_i[CW-1:0]` is a **scalar vertical cost**, legal range 0 through K×(2^P−1). Output `sad_o[SW-1:0]` is the sum of K successive accepted costs after warmup. The module does not check that runtime inputs obey the physical pixel-cost limit; that is a caller/reference-model contract, not a saturation feature.

For K>1, state is K−1 cost entries, write pointer, fill count, running `history_sum`, and output registers. Default history payload is 10×12=120 bits, excluding counters, totals and outputs. It is not a K×K pixel store.

### The two sums that must not be confused

Before an accepted edge, H=`history_sum` contains the previous K−1 costs. Let C be the new cost and O the oldest stored cost:

$$
S_{new}=H+C,\qquad H_{next}=H-O+C.
$$

The current output is **H+C**, not the newly updated history sum. The RTL already contains this final output adder; adding another adder outside would double-count or misalign the result.

During warmup, `old_column` is forced to zero rather than reading an unwritten entry. The pointer wraps at DEPTH−1, not at the natural binary overflow of its vector. `fill_count` saturates at DEPTH=K−1. On the Kth accepted cost, the **old** full flag is true and the first complete output is registered.

The K=1 generate branch has no history memory. It is a registered pass-through cost/valid block. Reset/clear zeros the logical history state and outputs; the history array itself is not bulk-erased.

### Predict, then test

K=3, accepted costs 6,15,24,33,0:

| C | H before edge | O removed | valid/output SAD | H after edge |
|---|---|---|---|---|
| 6 | 0 | 0 | 0 / 0 | 6 |
| 15 | 6 | 0 | 0 / 0 | 21 |
| 24 | 21 | 6 | 1 / 45 | 39 |
| 33 | 39 | 15 | 1 / 72 | 57 |
| 0 | 57 | 24 | 1 / 57 | 33 |

A pause before 24 leaves H=21 and does not consume a pointer slot. A pause after the final input gives valid=0 while the registered SAD remains 57.

Tests: exactly K−1 inputs must not yield a window; the Kth must. Use long increasing sequences to force repeated wraps, all-maximum costs to test width, maximum-to-zero transitions to test eviction, pauses at every fill count, clear after full history, and clear/reset with simultaneous valid. Cover K=1, K=2 (depth one) and non-power-of-two history depths.

**Write the reference:** retain K accepted costs in a simple list/deque and re-sum the **entire list** once it is full. Do not use H−O+C in the scoreboard. That would reproduce the DUT bug you are trying to detect. Compare warmup, exact sums and held output across invalid edges.

**Observe:** wr_ptr, fill_count, full, history_sum, old_column, column_sum_i, valid_o and sad_o. The expected sum must never be derived from those DUT internal values.

**Exercise:** explain which column each pointer slot contains after 33, and why reading unwritten memory is avoided without resetting every stored entry.

## 9. Single SAD engine

**Source:** `rtl/sad_engine.sv`. **Full code:** [[Single SAD Engine]]. **Architecture:** [[SAD Engine Architecture]]. **Questa part:** `engine`.

### What exists inside, and what does not

This implemented module connects `column_sad` to `column_sum_buffer`. It broadcasts clock/reset/clear to both, connects calculator `column_valid` to the history buffer's input valid, and passes the calculator cost into the buffer. It accepts one fixed-alignment left/right pair per valid edge.

The engine's interfaces are `left_column_i[B-1:0]`, `right_column_i[B-1:0]`, `valid_i`, and `sad_o[SW-1:0]` / `valid_o`, with the shared synchronous controls. K/P/CW/SW pass to the children.

It does **not** choose disparity, store image rows, shift right columns, carry coordinates, generate row-clear timing or implement backpressure. It is one lane, not the disparity bank or accelerator top. There is no separate missing “final window adder” inside this lane; the history buffer already implements it.

### Why the engine adds one more edge

The calculator's output is registered. The downstream history buffer samples it on the next clock edge. Therefore the engine offset is L+1, not L. For K=3, feed left columns `[1,2,3]`, `[4,5,6]`, `[7,8,9]`, `[10,11,12]` against zeros at local edges 0–3, then stop input:

| Local edge | Engine input accepted? | Calculator valid/cost after edge | Engine valid/SAD after edge |
|---|---|---|---|
| 0 | yes, first column | 0 / 0 | 0 / 0 |
| 1 | yes, second | 0 / 0 | 0 / 0 |
| 2 | yes, third | 1 / 6 | 0 / 0 |
| 3 | yes, fourth | 1 / 15 | 0 / 0 |
| 4 | no, drain | 1 / 24 | 0 / 0 |
| 5 | no, drain | 1 / 33 | 1 / 45 |
| 6 | no, drain | 0 / 33, held | 1 / 72 |

At edge 5 the buffer samples the calculator's **old** cost 24, not its newly registered 33. The last input at edge 3 requires drain edges 4,5,6; engine clear may occur at edge 7 separately. A connected downstream reducer may still need additional drain time.

### Test the lane independently of its own decomposition

Keep original raw left/right columns, retain K of each, and recompute all K×K unsigned absolute differences for every full window. Delay only the independently calculated result/valid by L+1 edges. Never use the calculator's output as the golden expected window.

Required tests:

- Identical raw windows → zero; maximum mismatch in both directions → K²×(2^P−1).
- Nonuniform row/column patterns → catch a calculator connection, order or width error.
- N accepted columns in a row, N≥K → exactly N−K+1 windows **after drain**.
- Short row N<K → zero windows, even after drain.
- Bubbles without advancing raw-column history, while still advancing due-edge time.
- Normal row drain followed by clear and a contrasting next row → no last-window loss or cross-row contamination.
- Abort while work occupies every pipeline offset, including after warmup → no stale results.
- K=1 and other parameter cases → consistent combined timing.

**Observe:** input pairs, `column_valid`, `column_sum`, child history fill, final valid and SAD. The worked examples print the child signals against explicit known expectations to explain the timing; the production engine scoreboard computes full-window expectations from raw inputs.

**Exercise:** explain why checking the calculator and history buffer separately does not prove that their valid wires were connected correctly. Then predict the missing final window if you clear at edge 5 of the table.

## 10. Minimum comparator tree

**Source:** `rtl/comparator_tree.sv`. **Full code:** [[Minimum Comparator Tree - Code Walkthrough]]. **Questa part:** `comparator`.

### Purpose, ports and candidate definition

It selects the minimum **valid** `(SAD, disparity ID)` from an aligned candidate set. Inputs are `lane_valid_i[LANES-1:0]`, `sad_i[LANES*SAD_W-1:0]`, and `disparity_i[LANES*D_W-1:0]`. Outputs are one registered-tree result with valid, scalar cost and ID. Unlike other blocks, there is no single input `valid_i`; validity is per lane.

A lane index is a physical position in the packed input. Its disparity ID is explicit data. They need not be equal. If using a small lane group with larger global disparity IDs, explicitly choose D_W wide enough and size the bench/connecting buses accordingly. Three lanes default to two ID bits, so IDs 7 and 9 would be truncated rather than tested as 7 and 9.

### Reduction and tie rule

M=max(1,ceil(log2 LANES)); PADDED=2^M. Real leaves unpack their fields and validity. Padded leaves have active=0. **Zero-cost padding cannot be treated as valid**, because it would beat genuine nonzero matches.

Each registered pair chooses right only when right is active and left is inactive, right cost is smaller, or equal cost has smaller right ID. Its validity is the OR of child validity. Cost, ID and valid are registered together at every reduction level.

At the root, valid=0 explicitly forces outward cost and ID to zero. Otherwise it exposes the winning fields. LANES=1 still has one registered pair with an inactive padded neighbor.

For LANES=32, M=5 and input sampled at t gives the root after t+4. This is five register levels, not an edge offset of five. Candidate sets must already refer to the same `(x,y)`; the tree neither stores nor checks tags.

### Predict, then test

For three lanes with SAD_W=12/D_W=2, physical lanes 0/1/2 carry costs `[30,5,5]`, IDs `[2,1,0]`, mask `111`. Winner is `(5,0)`, because ID 0 wins the equal-cost tie. With two registered levels it appears after edge t+1.

Now change lane zero's cost to zero but use mask `110`: that invalid zero must not win. An all-invalid candidate set eventually produces valid=0, cost=0 and ID=0, not a valid zero match.

| Test | Why it matters |
|---|---|
| Unique minimum walked through every physical lane | Every leaf and pair participates |
| Only one valid lane, including highest lane | Valid beats invalid regardless of invalid cost |
| All costs equal, IDs opposite lane order | Tie follows explicit disparity ID, not physical position |
| Equal cost and equal ID | Either identical candidate value is equivalent; no artificial lane preference required |
| All invalid; valid mask changes every edge | Validity propagates with the matching fields |
| Maximum representable costs and zero | Unsigned comparisons and exact field widths |
| One lane, odd lane count, 32 lanes | Registered special case and invalid padding |
| Clear/reset at every occupied reduction offset | No old winner escapes the flush |

**Write the reference:** serially scan valid candidates in a testbench loop and minimize `(cost, ID)` lexicographically. Schedule the result at input_edge+M−1. Do not build a second comparator tree in the reference. Clear pending candidate results on reset/clear.

**Observe:** input slices, active flags, winning_cost / winning_disparity / winning_valid at each level, and final outputs.

**Exercise:** explain why masking invalid candidates with a numerical “large cost” alone is less explicit than propagating valid, and why default small-group ID width is not enough for arbitrary global IDs.

## 11. How the pieces must connect

### 11.1 Alignment and enables

For future lane d, the intended sampled input is common L[x] and right tap R[x−d], enabled by `left_valid && tap_valid[d]`. Both streams must share the same accepted-coordinate progression. A single common valid is a contract, not a synchronizer for independently arriving images; independent transport streams need appropriate buffering/pairing first.

Every lane's history accumulates its own valid aligned columns. Tap warmup is not a complete K-column window: tap d first appears at x=d, but its first full horizontal lane window requires x≥d+K−1. Vertical windows additionally require y≥K−1.

Under the bottom-right convention, all disparities 0…TAPS−1 are geometrically available only for x≥(TAPS−1)+(K−1). At defaults that threshold is x=41. This is a mathematical border rule, **not an implemented output mask or coordinate counter**.

A future system must decide whether border pixels use a subset of disparities, are marked invalid, or are omitted. It must also decide output anchoring/placement. Do not silently turn missing candidates into valid zero SAD.

### 11.2 Spatial history is not an output delay

All equal-K/P engines have the same clock pipeline offset. A lane with larger d starts its accepted-column warmup later, but once valid it still describes the current left x. Do not add another d-cycle delay to engine outputs: that would combine costs for different left coordinates in the comparator.

Metadata `(x,y)` must follow the actual registered timing and valid/bubble flow. Gating the metadata pipeline only when **new input** is valid would stall old tags while old numeric work continues. The correct controller/tag design must be specified and tested before the wrapper.

### 11.3 Proposed continuous-case edge budget, not a measured integrated result

If eligible pixel inputs are sampled by row buffers at edge 0, and all intended connections use the same clock without extra registers:

| Event | Predicted edge at default K=11 / 32 comparator lanes |
|---|---|
| Row column registered | 0 |
| Delay/cache sample that registered column | 1 |
| Lane engine samples the pair | 2 |
| Engine registers the full-window SAD | 7 |
| Comparator samples engine candidate outputs | 8 |
| Comparator root registers winner | 12 |

This is derived from the component sampling contracts, assuming warmup is already satisfied. There is no complete top-level RTL/metadata bench proving this end-to-end budget yet. Added RAM stages, FIFOs, transport or controller choices can change it.

### 11.4 What is missing and must be tested later

- Row-buffer-to-pair-to-engine hookup with a raw stereo-image reference.
- Parallel bank fan-out/fan-in and aligned valid masks/IDs/tags.
- Row-last tag delay, ingress pause control, lane drains, reducer drain and correctly scoped clears.
- Output buffering and a policy for downstream stalls. None of these modules has a ready/backpressure interface.
- Runtime control/status and memory-mapped interfaces, address generation, memory transport and board integration.
- Resource fitting, RAM mapping, fully constrained timing and actual board acceptance.

[[Disparity Bank]], [[Timing and Pipelining]], [[Interface Contract]] and [[Hardware Integration]] are planning references, not substitutes for those verification gates.

## 12. Run the worked examples and write your own benches

### 12.1 Runnable small datapath lessons

`tests/lab/tb_datapath_examples.sv` uses K=3/P=8, row width 4, three right taps and a three-lane/12-bit-cost/2-bit-ID comparator. It exercises all seven modules with explicit known values. They are independent experiments; outputs are not connected into a new frontend/bank/top wrapper.

The bench checks 40 stimulus edges: row warmup/packing/pause; left/right accepted/pause/restart behavior; cost 130 and its timing; history windows 45/72/57; the seven-edge engine trace; and comparator tie/invalid-zero/no-valid timing. It also checks cleared outputs between experiments. The smaller original beginner bench and production benches remain separate.

**Questa/ModelSim, from its Transcript:**

```tcl
cd {C:/path/to/Stereo-SAD-FPGA}
set root [pwd]
set part examples
do scripts/questa_lab.do
```

Replace the path. The macro leaves simulation and recursive waves open at finish. Look for **`PASS datapath examples: seven modules, 40 checked stimulus edges`**, not merely a stopped simulation. Zoom into one phase, label the local edges and compare with this guide. The engine trace is at local edges 0…6, not at absolute simulation start time.

The macro changes to a build directory. For later module runs use the saved root:

```tcl
set part column
do "$root/scripts/questa_lab.do"
```

Use `row`, `shift`, `delay`, `column`, `buffer`, `engine`, `comparator` or `pairing` to run their **standalone golden benches** with small directed parameters. Those benches are more extensive than the fixed lesson trace. See [[Hands-on Testbench Lab]] for student bench/RTL overrides and safe scratch copies.

**Portable Icarus route, from a normal shell at the repository root:**

```sh
python scripts/run_testbench_lab.py --check-faults --examples
```

Requirements: Python, `iverilog` and `vvp`. The helper preserves `build/lab/reference.vcd` for the beginner lab, `build/lab/datapath_examples.vcd` for these lessons, and `build/lab/datapath_examples.log` for the printed trace. All generated artifacts remain ignored; no production RTL is mutated.

### 12.2 Each module's directed production command

```sh
python scripts/run_tests.py --suite row --case 3:8:4 --random-cycles 0 --vcd
python scripts/run_tests.py --suite shift --case 3:8:3 --random-cycles 0 --vcd
python scripts/run_tests.py --suite delay --case 3:8 --random-cycles 0 --vcd
python scripts/run_tests.py --suite column --case 3:8 --random-cycles 0 --vcd
python scripts/run_tests.py --suite buffer --case 3:8 --random-cycles 0 --vcd
python scripts/run_tests.py --suite engine --case 3:8 --random-cycles 0 --vcd
python scripts/run_tests.py --suite comparator --case 3:12 --random-cycles 0 --vcd
python scripts/run_tests.py --suite pairing --case 3:8:3 --random-cycles 0 --vcd
```

For `comparator`, case is `LANES:SAD_W`; the second number is **not pixel width**. For `row`, case is `K:PIXEL_W:IMG_W`; for `shift`/`pairing`, it is `K:PIXEL_W:TAPS`. The golden comparator bench's ID width is derived from its lane count. The Questa standalone comparator preset uses SAD_W=8 to keep waves small; the fixed worked-example bench uses SAD_W=12 to match a K=3 full-window cost width.

After a directed case passes, use a reproducible nonzero seed such as `--seed 12345 --random-cycles 10000`. The same simulator/seed/parameters reproduce traffic. Cross-simulator random function argument evaluation can differ, so compare each simulator to its own reference rather than requiring identical random output counts.

### 12.3 Write your bench rather than copy the solution

For **each** module, follow this sequence:

1. **Contract page:** list parameters, widths, valid/data relationships, reset/clear priority, warmup threshold, edge offset and invalid-payload behavior. Predict three useful traces before opening waves.
2. **Skeleton:** clock, held initial reset, explicit DUT ports, a timeout and test counters. Start with small legal parameters.
3. **Directed tick:** drive on a falling edge, allow the next rising edge to sample, inspect after NBA settlement. A testbench `#1` after posedge is an observation aid, not a clock-cycle delay or a synthesizable register.
4. **Assertions:** use four-state comparisons (`!==`) so an unknown valid/value cannot silently pass. Include case, edge, stimulus, expected and actual fields in the first failure.
5. **Independent model:** use the model prescribed in the chapter. Schedule expected results by clock edge; increment histories only on accepted input. Check that at least one valid result was actually compared.
6. **Consumer check:** for pairing, also check pre-NBA values at the next positive edge—the values another synchronous module consumes.
7. **Stress:** warmup boundaries, consecutive accepts, invalid beats with changing inputs, wrap, control priority, extreme arithmetic and deterministic random cases.
8. **Sensitivity:** break a scratch copy of the DUT. Require a successful compile and a numerical/control assertion failure. Keep production RTL untouched. Read [[Hands-on Testbench Lab]] for overrides.
9. **Read the solution:** compare with the matching `tests/rtl/tb_*.sv`, then explain why its reference is independent of the hardware implementation.
10. **Explain the result:** annotate a waveform and connect each failed/successful edge to the RTL assignment that creates it. “It printed PASS” is not enough understanding.

Changing a scratch bench requires recompilation. Restarting a simulation image without rebuilding it does not test your new source. Preserve the first failing seed/trace before experimenting with fixes.

## 13. Verification checklist and completion gate

### 13.1 Quick diagnosis map

| Symptom | First things to inspect |
|---|---|
| Correct numbers one edge early/late | Input sampling edge, NBA observation, child register boundary, due-edge queue |
| Failure only with pauses | Accepted-count versus clock-count distinction; history enable versus valid pipeline |
| Failure after warmup/wrap | Old full flag, pointer modulus, row-slot ordering, stale memory exposure |
| Only large pixel values fail | Signedness, zero extension, cost widths, truncating casts |
| Only odd K/lane counts fail | Padding and non-power-of-two wrap |
| Invalid zero wins | Missing valid propagation or active padding |
| Equal costs pick the wrong disparity | Explicit ID width/packing and tie rule, not lane order |
| Last row windows vanish | Clear too early, missing engine drain, downstream clear scope |
| A new image contains old data | Readiness/count reset, old memory accessed before rewrite, wrong clear scope |
| Always passes, even when broken | Expected model copies DUT internals, no outputs checked, assertions not reached |

### 13.2 What passing simulations do and do not establish

The production regression contains 70 simulation cases, with separate deliberate-fault checks. The teaching trace is a separate fixed-size experiment, **not 40 extra parameter cases** and not a complete disparity-map test. Source snapshots are checked against RTL by `scripts/check_walkthrough.py`.

[This guide's actual simulation evidence](../docs/verification/datapath-study-guide.md) records the Icarus/Questa worked traces, production regression and individual-command checks. Preparing and running these examples does not mean you have already completed the bench-writing exercises yourself.

Use the recorded [[Verification]] and `docs/verification/` reports for actual component synthesis results. Simulation demonstrates functional contracts for tested conditions. Analysis & Synthesis is not fitting or timing closure. Resource estimates for a small smoke top cannot be claimed for the full 640-wide row buffer. This study-guide milestone changes no synthesizable datapath RTL and requires no claim of new hardware synthesis.

**Recorded area evidence, not new synthesis from this guide:**

| Component / actual synthesized configuration | Recorded Analysis & Synthesis | Limits / evidence |
|---|---|---|
| Row-ring smoke top, K=11/P=8/IMG_W=16 | 3156 logic elements; 0 errors/warnings; 0 inferred memory bits | [Row report](../docs/verification/row-buffer-synthesis.md). Full IMG_W=640 did not finish the documented time-limited attempts; no full-width area/timing result. |
| Single engine, K=11/P=8 | 770 logic elements, 368 registers; 0 errors/warnings; 0 inferred memory bits | [Engine report](../docs/verification/single-engine-synthesis.md). Includes calculator + cost history; not a fitted lane bank. |
| Right cache, K=11/P=8/TAPS=32 | 2883 logic cells; 0 errors/warnings | [Shift report](../docs/verification/right-shift-synthesis.md). Wide tap bus is internal wiring, not assignable board pins. |
| Left register, K=11/P=8 | 90 logic cells; 0 errors/warnings | [Delay report](../docs/verification/left-delay-synthesis.md). Component only. |
| Comparator, LANES=32/SAD_W=15/D_W=5 | 1622 logic cells; 0 errors; 1 processor-count-setting warning | [Comparator report](../docs/verification/comparator-synthesis.md). Not integrated bank timing. |

The guide does not provide a separately measured calculator/history area split or an integrated accelerator total. Multiplying one lane's area by 32 is an estimate, not a measured bank result. None of these reports establishes fitted Fmax or power. A provisional clock constraint is a target, not achieved timing.

**Design trade-offs to discuss after the functional labs:** registered reduction trees exchange register count/latency for shorter combinational paths; explicit valid state keeps bubbles from corrupting history; rings exchange large shifting stores for indexed writes/reads and control; register-based right taps provide simultaneous column access but cost wide storage/wiring. The actual asynchronous row/history reads did not infer block RAM in the cited runs. Changing to synchronous RAM may improve mapping but changes timing and must be treated as a new verified implementation step, not a guaranteed optimization.

### 13.3 Before moving to the new wrapper

- [ ] I can name the representation and width on every arrow in the intended flow.
- [ ] I can explain why image-row memory, right-column cache and column-cost history are different.
- [ ] I can pack/unpack rows, taps and lane IDs without reversing their order.
- [ ] I can draw each block's state and locate its update enable in the exact source note.
- [ ] I can calculate legal maxima and explain unsigned arithmetic/zero extension.
- [ ] I can distinguish accepted-sample warmup from clock-edge pipeline latency.
- [ ] I wrote an independent self-checking bench for each component, including invalid/control behavior.
- [ ] My benches reject compiled deliberate faults rather than only compile errors.
- [ ] I can explain the K=3 engine trace and preserve its last outputs using drain then separate clear.
- [ ] I can explain left/right consumer-edge pairing and lane-specific warmup without adding disparity-dependent output delays.
- [ ] We have agreed coordinate anchoring, border policy, tag timing, clear scope and downstream buffering **before** implementing the wrapper.

**Suggested learning order:** left register → right cache → image-row ring → vertical calculator → cost history → single engine → comparator → local pairing → integration contract. The chapter order follows dataflow; the learning order starts with the easiest bench. Keep questions and your annotated traces beside this one guide and its linked exact-code notes. No slides or additional Obsidian plugins are required.
