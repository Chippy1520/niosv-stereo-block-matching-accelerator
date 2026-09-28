# Nios V Interface
#planned
Processor/CPU is Nios V; OS or bare-metal HAL remains to be specified.
Future control/data interface may use Avalon memory-mapped registers plus a stream or DMA, subject to the actual Platform Designer system.

Open decisions: Quartus version/edition; Nios V variant; OS; image transport; runtime kernel/range requirements; border convention; frame/line signaling; clock and reset domains.

Current K is a synthesis-time constant. If the CPU must change K at runtime, define K_MAX, programmable history depth, valid-count rules and flush-on-change before extending the module. Do not treat a SystemVerilog parameter as a software register.

See [[Hardware Integration]], [[Interface Contract]], [[Image Line Buffers]].
