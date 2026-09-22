# Hardware Integration
#design
Target: DE2-115, Cyclone IV. A Quartus component project now exists: `Stereo_SAD.qpf` with companion `Stereo_SAD.qsf`, targeting EP4CE115F29C7 and top-level `column_sum_buffer`. A provisional 50 MHz clock constraint is supplied in `constraints/column_sum_buffer.sdc`. Quartus Prime Lite 22.1 Analysis & Synthesis passed with zero errors and one processor-count warning. This is **not a board-programmable top-level**: no pin map, board wrapper, external I/O delay specification or .sof exists yet. Do not connect component inputs directly to arbitrary board pins.

Altera's current Nios V Developer Center explicitly lists Cyclone IV under its Quartus Prime Standard processor support table. Confirm installed software version/edition and selected Nios V IP before integration; do not assume legacy board examples use the same CPU.

Source: https://www.altera.com/design/guidance/nios-v-developer
Board manual: https://www.terasic.com.tw/attachment/archive/502/DE2_115_User_manual.pdf

Future: add rtl/column_sum_buffer.sv as SystemVerilog to the existing Platform Designer/Quartus project and instantiate inside the accelerator. Board synthesis, timing constraints, CDC, CPU integration and programming are later milestones.

[[Nios V Interface]] · [[Timing and Pipelining]] · [[Home]]
