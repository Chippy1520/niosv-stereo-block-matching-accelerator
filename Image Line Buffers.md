# Image Line Buffers
#planned
Future module, not implemented.
Provide K vertically aligned pixels per image column. Requires previous image rows, appropriate read bandwidth, window warmup and border handling. Raw images cannot be connected directly to [[Column Sum Buffer]].

Flow: [[Nios V Interface]] → image ingress/line storage → [[Column SAD Engines]].
For now assume rectified images; calibration/rectification is upstream. Define padding versus valid-only windows before building this stage.
