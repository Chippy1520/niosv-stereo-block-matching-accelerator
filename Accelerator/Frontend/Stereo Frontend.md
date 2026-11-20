# Stereo frontend

[[Accelerator Architecture]] → [[Stereo Frontend Blocks.canvas|frontend schematic]]. The datapath connects two packed-word row stores to the existing left delay and right disparity cache, with aligned `(x,y,row_last)` tags. Testbenches supply load addresses, safe bank reuse, reads and scoped clears; there is no autonomous controller. Parent [[Stereo SAD Datapath]] now connects this frontend to [[SAD Search Backend]].

- [[Stereo Frontend - Code Walkthrough]] — complete frontend RTL, tag timing and raw-image interconnection bench.
- [[Packed Circular Row Buffer]] — K active rows plus parameterized spare prefetch rows (default/minimum one), direct four-pixel loads and independent K-pixel reads; no-copy bank rotation.
- [[Row Word Bank]] — internal independently addressed clocked RAM primitive; not another accelerator stage or FIFO.
- [[Right Column Shift Register]] — implemented right taps and per-tap validity.
- [[Left Column Delay]] — matching registered left payload/valid.
- [[Circular Row Buffer]] / [[Row RAM Bank]] — retained serial-input reference and existing lessons, not extra storage in the packed path.
- [[Hands-on Testbench Lab]] — write a standalone bench before studying its integrated counterpart.
- [Packed frontend contract](../../docs/packed-frontend-contract.md) — four-pixel lane order, independent ports, caller obligations and register handoffs.
- [Spare-row decision and verification](../../docs/verification/spare-row-prefetch.md) — active-window preservation, same-word-address spare writes and integrated shift/SAD tests.
- [[SAD Search Backend]] — downstream engine fan-out and bank/reducer, implemented separately from this frontend.
