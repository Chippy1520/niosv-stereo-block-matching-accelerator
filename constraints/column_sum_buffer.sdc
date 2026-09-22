# Provisional component clock target: 50 MHz, not a measured Fmax.
create_clock -name clk -period 20.000 [get_ports {clk}]
derive_clock_uncertainty
# External I/O delays require the eventual system interface specification.
# No false paths applied to synchronous reset or data ports.
