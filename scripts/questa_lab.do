# Run in the Questa/ModelSim Transcript from the repository root:
#   set part lab
#   do scripts/questa_lab.do
# Change part to delay, shift, row, column, buffer, engine, comparator or pairing.
# Optional student_bench overrides the lab file (keep module tb_delay_lab).
# Optional student_rtl overrides the lab DUT (keep module left_column_delay).
if {![info exists root]} {set root [file normalize [pwd]]}
if {![file isfile [file join $root rtl left_column_delay.sv]]} {
    error "Set root to the repository directory before running this macro"
}
if {![info exists part]} {set part lab}
set sources [dict create \
    lab {left_column_delay} \
    delay {left_column_delay} \
    shift {right_column_shift} \
    row {circular_row_buffer} \
    column {column_sad} \
    buffer {column_sum_buffer} \
    engine {column_sad column_sum_buffer sad_engine} \
    comparator {comparator_tree} \
    pairing {left_column_delay right_column_shift}]
set tops [dict create lab tb_delay_lab delay tb_left_column_delay \
    shift tb_right_column_shift row tb_circular_row_buffer column tb_column_sad \
    buffer tb_column_sum_buffer engine tb_sad_engine comparator tb_comparator_tree \
    pairing tb_column_pairing]
if {![dict exists $tops $part]} {error "Unknown part: $part"}
set top [dict get $tops $part]
set out [file join $root build questa_lab $part]
file mkdir $out
cd $out
catch {quit -sim}
vlib work
if {![file exists modelsim.ini]} {vmap -c}
vmap work work
foreach name [dict get $sources $part] {
    set rtl [file join $root rtl ${name}.sv]
    if {$part eq "lab" && [info exists student_rtl]} {set rtl [file normalize $student_rtl]}
    vlog -sv $rtl
}
if {$part eq "lab"} {
    set bench [file join $root tests lab tb_delay_lab.sv]
    if {[info exists student_bench]} {set bench [file normalize $student_bench]}
} else {set bench [file join $root tests rtl ${top}.sv]}
vlog -sv $bench
set generics {}
if {$part ne "lab"} {
    if {$part eq "comparator"} {set generics {-gN=3 -gP=8}} else {set generics {-gK=3 -gP=8}}
    if {$part eq "row"} {lappend generics -gW=4}
    if {$part eq "shift" || $part eq "pairing"} {lappend generics -gT=3}
}
vsim -onfinish stop -voptargs=+acc {*}$generics work.$top +RANDOM_CYCLES=0
add wave -r sim:/$top/*
run -all
wave zoom full
# Leave simulation/waves open for inspection. A PASS line, not the waveform alone,
# is the acceptance criterion. This GUI convenience script is not a CI runner.
