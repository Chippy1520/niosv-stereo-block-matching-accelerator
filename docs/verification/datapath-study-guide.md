# Datapath study-guide verification

This is a teaching/documentation milestone, not a new synthesizable datapath or top-level wrapper. No `rtl/*.sv` source or Quartus project was changed.

## Actually exercised

- `python scripts/check_walkthrough.py`: all seven functional source/walkthrough/standalone-bench registrations passed.
- `python scripts/run_tests.py`: 70 simulation cases passed.
- `python scripts/check_test_sensitivity.py`: all 12 compiled faulty designs were detected; production RTL unchanged.
- `python scripts/run_testbench_lab.py --check-faults --examples`: beginner baseline passed seven directed beats, both compiled beginner faults were detected, and the new examples passed 40 checked stimulus edges.
- Questa Intel Starter Edition 2021.2: actually compiled and ran `scripts/questa_lab.do` with `part=examples`; zero reported compile errors/warnings and the same 40-edge PASS marker. This was batch execution of the macro, not visual GUI acceptance. Batch mode cannot zoom a GUI waveform; the macro still ran its numerical assertions.
- All eight individual commands listed in [[Datapath Study Guide]] passed with directed traffic and VCD enabled, including the three-lane/12-bit-cost comparator case.
- Guide contents anchors and Obsidian wiki targets were checked against actual headers and existing vault files.

## Worked results seen in both simulators

- Row columns: `090501`, `0a0602`, `0b0703`, `0c0804`; last flag only on the fourth.
- Right tap masks across accepted/paused beats: `001`, `011`, `000`, `111`; clear/restart returns to `001` without old data.
- Isolated column cost: 130 at local edge 2; held payload with invalid output at edge 3.
- Cost-history windows: 45, 72, 57 after two accepted warmup costs.
- Single-engine windows: 45 at local edge 5, 72 at edge 6, during the three-edge drain after the last input at edge 3.
- Comparator: equal-cost tie gives cost 5 / explicit disparity ID 0; an invalid zero-cost lane is ignored; all-invalid output is zero with valid clear after pipeline delay.

The 40 edges are fixed lesson stimuli, not 40 additional parameter configurations. The lesson instantiates components for independent experiments; it does not connect row buffers through an engine bank to the comparator. Existing synthesis evidence remains in the component reports; no fresh synthesis, integrated Fmax, memory transport, Nios V or board result is claimed.

Generated local evidence stays ignored: `build/lab/datapath_examples.log`, `build/lab/datapath_examples.vcd`, and `build/questa_lab/examples-validation.log`. CI reruns the portable teaching command and uploads its logs/wave alongside the regression artifacts.
