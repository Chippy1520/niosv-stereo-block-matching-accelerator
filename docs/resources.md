# Curated support material

All links below were checked for existence when this list was assembled. External examples target different boards or tool versions; use them to understand architecture and protocol behavior, not as drop-in DE2-115 code.

## Start here: official Nios V and Platform Designer videos

1. **Getting Started with Nios V/m Processor (Part 1/3) — Altera**  
   https://www.youtube.com/watch?v=3Fwgsfbbcm4  
   Hardware/software flow overview and the closest official starting point to the team's completed Hello World milestone.

2. **Setting Up Open-Source Tools for Nios V/m (Part 2/3) — Altera**  
   https://www.youtube.com/watch?v=ExOHGZ0ggWk

3. **Software Development on Nios V/m Processor (Part 3/3) — Altera**  
   https://www.youtube.com/watch?v=nGUI78Q-evY

4. **Nios V Processors Hardware Integration — Altera**  
   https://www.youtube.com/watch?v=vVEmKEgD8-E  
   Particularly relevant when expanding the current processor system with external memory and custom IP.

5. **Introduction to Platform Designer — Altera**  
   https://www.youtube.com/watch?v=FpN587eIWtE

6. **Creating a System Design with Platform Designer: Getting Started — Altera**  
   https://www.youtube.com/watch?v=WnmzO08v9jI

7. **Platform Designer Standard Interfaces — Altera**  
   https://www.youtube.com/watch?v=auxFLON7mJo  
   Useful before defining the custom control-slave and memory-master interfaces.

## Avalon-MM and custom-IP material

1. **CSCE 491 Lecture 8: Avalon IP Design — Jason D. Bakos**  
   https://www.youtube.com/watch?v=Ziv2SN653Os  
   University lecture focused on Avalon IP design. Check signal behavior against the current official specification.

2. **Nios Custom Peripheral, Part 1 — tscevers**  
   https://www.youtube.com/watch?v=FDdjmhgEBYc

3. **Nios Custom Peripheral, Part 2 — tscevers**  
   https://www.youtube.com/watch?v=1oBuAFo665o

4. **Avalon Interface Specifications — official documentation**  
   https://docs.altera.com/r/docs/683091/current  
   Treat this as authoritative for `waitrequest`, `readdatavalid`, burst, and transfer acceptance behavior.

5. **Platform Designer User Guide — official documentation**  
   https://docs.altera.com/r/docs/683609/current

## Stereo block matching and FPGA examples

1. **Stereo Camera System: SAD and Census disparity algorithms in VHDL/FPGA — eigenpi**  
   https://www.youtube.com/watch?v=AvXN3mPzjkE  
   Useful visual evidence of the expected disparity pipeline and output; not a DE2-115 integration tutorial.

2. **3D dense stereo on FPGA: rectification, matching, subpixel, filtering — Computer Vision and Embedded Systems**  
   https://www.youtube.com/watch?v=KXFWIvrcAYo  
   Shows the broader pipeline; rectification and subpixel processing should remain stretch goals here.

3. **FPGA/GPU block-matching performance project — Abhishek Khule**  
   https://www.youtube.com/watch?v=V4KY466UOeo  
   Useful for thinking about benchmark presentation, but independently verify technical details.

4. **FPGA Stereo Depth Map — jamesrivas**  
   https://github.com/jamesrivas/FPGA_Stereo_Depth_Map  
   Readable description of a 5×5-window multi-pipeline design with line buffers and a result aggregator. Different platform and I/O architecture.

5. **Real-time binocular stereo vision FPGA system — yangjl-cs**  
   https://github.com/yangjl-cs/stereo-vision-fpga  
   Larger Xilinx/HLS camera system. Useful for architectural ideas and bibliography, not directly reusable RTL.

## Nios V and Avalon example repositories

1. **Nios V examples on Cyclone IV DE0-Nano — monkstein88**  
   https://github.com/monkstein88/niosv-example-projects  
   Particularly relevant because it targets another Cyclone IV Terasic board and discusses the SDRAM controller IP search path. Do not copy pin assignments to the DE2-115.

2. **Nios V example designs shipped with Quartus — nabeel-at-intel**  
   https://github.com/nabeel-at-intel/NiosVExamples

3. **Avalon-MM master templates — frobino**  
   https://github.com/frobino/avalon_mm_master_templates  
   Older Qsys-oriented reference. Its README notes incomplete/outdated simulation scripts, so use it for protocol structure rather than direct integration.

## Official Nios V documentation

1. **Nios V Processor Reference Manual**  
   https://docs.altera.com/r/docs/683632/current

2. **Nios V Processor Quick Start Guide**  
   https://cdrdv2-public.intel.com/679987/ug20345-683590-679987.pdf

3. **Nios V Developer Center**  
   https://www.altera.com/design/guidance/nios-v-developer

## Stereo datasets

1. **Middlebury Stereo Datasets**  
   https://vision.middlebury.edu/stereo/data/  
   Recommended primary evaluation source. It includes multiple stereo datasets with ground-truth disparities and clear citations.

2. **Scene Flow: FlyingThings3D, Driving, and Monkaa**  
   https://lmb.informatik.uni-freiburg.de/resources/datasets/SceneFlowDatasets.en.html  
   Synthetic sequences with left/right images, disparity, optical flow, segmentation, and camera data. Use the small sample pack rather than the full collection initially.

3. **KITTI Stereo Evaluation**  
   https://www.cvlibs.net/datasets/kitti/eval_stereo.php  
   Realistic driving scenes. Use as a stretch test after Middlebury and synthetic vectors.

## Suggested learning order

1. Official Nios V hardware-integration material.
2. Official Platform Designer and standard-interface videos.
3. Avalon Interface Specifications, especially stalls and read-valid timing.
4. Build and test the shared-SDRAM copy/transform engine.
5. Study the `jamesrivas` stereo architecture for line-buffer and pipeline concepts.
6. Implement the software SAD model and tiny synthetic tests.
7. Add one verified disparity lane before replication.

## Important cautions

- Nios V may expose AXI4 instruction/data managers; Platform Designer performs adaptation to Avalon-MM peripherals where required.
- Do not infer DE2-115 SDRAM pin/clock settings from a DE0-Nano or Xilinx project.
- Never assume CPU cache coherence with a custom memory master.
- A repository with no explicit license should be treated as reference-only; do not copy its code into a public submission without permission.
- Preserve dataset citations and terms of use in the final report.
