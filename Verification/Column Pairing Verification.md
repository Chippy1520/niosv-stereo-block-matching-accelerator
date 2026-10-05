# Column Pairing Verification
#verified

[[Stereo Frontend]] → [[Left Column Delay]] + [[Right Column Shift Register]] → this **integration test**, not a new functional wrapper. Continue with [[Hands-on Testbench Lab]].

## What is actually connected

`tests/rtl/tb_column_pairing.sv` instantiates only the left delay and right cache with a common clock, reset, clear and accepted-beat valid. It supplies complete synthetic vertical columns directly. It does not instantiate image row buffers, SAD engines, a comparator or a controller.

```text
accepted L[x] ── left sampling register ── L[x] ───────────┐
accepted R[x] ── right-column cache ────── R[x−d] ────────┤ future engine d
                              mask[d] AND left_valid ───┘
```

The reference appends right columns to a software-style log and indexes `history[count−1−d]`. It never reads DUT state or duplicates the DUT shift chain. Expected left is the same accepted beat's L[x]. Packed pixels remain in their original row order.

## Two observation points

1. **At the rising edge before NBA updates:** compare the old registered outputs, exactly as a synchronous consumer would sample them. Current reset/clear aborts consumer work, so those edges do not count as consumption.
2. **After the edge (`#1` in the bench):** compare the newly registered outputs and per-tap validity against the accepted input history.

On a pause, a consumer may still take the final prior beat at that edge; afterward both output-valid paths are zero. This is why checking only a post-edge waveform can hide a one-cycle alignment mistake.

## Small K=3 / TAPS=3 example

| Current accepted x | Delayed left | Right tap 0 / 1 / 2 | Tap mask [2:0] |
|---|---|---|---|
| 0 | L0 | R0 / empty / empty | 001 |
| 1 | L1 | R1 / R0 / empty | 011 |
| pause | held L1 | held R1 / R0 / empty | 000 |
| 2 | L2 | R2 / R1 / R0 | 111 |
| clear | zero | all zero | 000 |
| next row x=0 | new L0 | new R0 / empty / empty | 001 |

A valid right tap is not a valid full SAD window. Lane d would need K accepted pairs; its first complete horizontal window ends at x=d+K−1. The bank's global border policy is still a later design gate.

## Reproduce

```sh
python scripts/run_tests.py --suite delay
python scripts/run_tests.py --suite shift
python scripts/run_tests.py --suite pairing
python scripts/run_tests.py --suite pairing --case 3:8:3 --seed 12345 --random-cycles 10000 --vcd
```

Open `build/pairing/k3_p8_t3/waveform.vcd`. In Questa, use `set part pairing` and the tested macro described in [[Hands-on Testbench Lab]]. Eight pairing cases share the right-shift matrix, including single taps, odd depths and the default 32 taps. The consumer counter is lane-pair observations, not pixels/second or throughput.

## What remains before the top-level wrapper

- Both row-buffer outputs must refer to the same (x,y), and paired input stalls must be shared.
- Coordinates/row-last need alignment matching the payload register.
- Choose common-interior versus per-lane border masks before scoring.
- Drain from the correct boundary: the engine-only drain remains ceil(log2(K))+1 edges after its final accepted input, followed by a separate clear. Draining from upstream must include frontend handoff edges.
- Keep row-buffer vertical history while clearing the right cache and engine horizontal histories.
- Feed and verify actual engines, winner reduction, controller and transport under a separate wrapper milestone.

This bench verifies local left/right column pairing, not those later integration items.
