# Run in the Questa/ModelSim Transcript from the repository root:
#   set part lab
#   do scripts/questa_lab.do
# Change part to examples, delay, shift, row-bank, row, word-bank, packed-row,
# frontend, search, datapath, control, column, buffer, engine, comparator or pairing.
# Optional student_bench overrides the lab file (keep module tb_delay_lab).
# Optional student_rtl overrides the lab DUT (keep module left_column_delay).
if {![info exists root]} {set root [file normalize [pwd]]}
if {![file isfile [file join $root rtl left_column_delay.sv]]} {
    error "Set root to the repository directory before running this macro"
}
if {![info exists part]} {set part lab}
set sources [dict create \
    lab {left_column_delay} \
    examples {row_ram_bank circular_row_buffer left_column_delay right_column_shift column_sad column_sum_buffer sad_engine comparator_tree} \
    delay {left_column_delay} \
    shift {right_column_shift} \
    row-bank {row_ram_bank} \
    row {row_ram_bank circular_row_buffer} \
    word-bank {row_word_bank} \
    packed-row {row_word_bank packed_circular_row_buffer} \
    frontend {row_word_bank packed_circular_row_buffer left_column_delay right_column_shift stereo_frontend} \
    search {column_sad column_sum_buffer sad_engine comparator_tree sad_search_backend} \
    datapath {row_word_bank packed_circular_row_buffer left_column_delay right_column_shift stereo_frontend column_sad column_sum_buffer sad_engine comparator_tree sad_search_backend stereo_sad_datapath} \
    control {row_word_bank packed_circular_row_buffer left_column_delay right_column_shift stereo_frontend column_sad column_sum_buffer sad_engine comparator_tree sad_search_backend stereo_sad_datapath} \
    column {column_sad} \
    buffer {column_sum_buffer} \
    engine {column_sad column_sum_buffer sad_engine} \
    comparator {comparator_tree} \
    pairing {left_column_delay right_column_shift}]
set tops [dict create lab tb_delay_lab examples tb_datapath_examples delay tb_left_column_delay \
    shift tb_right_column_shift row-bank tb_row_ram_bank row tb_circular_row_buffer column tb_column_sad \
    buffer tb_column_sum_buffer engine tb_sad_engine comparator tb_comparator_tree \
    pairing tb_column_pairing word-bank tb_row_word_bank \
    packed-row tb_packed_circular_row_buffer frontend tb_stereo_frontend \
    search tb_sad_search_backend datapath tb_stereo_sad_datapath control tb_stereo_control]
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
} elseif {$part eq "examples"} {
    set bench [file join $root tests lab tb_datapath_examples.sv]
} else {set bench [file join $root tests rtl ${top}.sv]}
vlog -sv "+incdir+[file join $root tests rtl]" $bench
set generics {}
if {$part ne "lab" && $part ne "examples"} {
    if {$part eq "word-bank"} {
        set generics {-gN=7 -gP=32}
    } elseif {$part eq "comparator" || $part eq "row-bank"} {
        set generics {-gN=3 -gP=8}
    } else {set generics {-gK=3 -gP=8}}
    if {$part eq "row"} {lappend generics -gW=4}
    if {$part eq "packed-row"} {lappend generics -gW=7}
    if {$part eq "frontend"} {lappend generics -gW=9 -gT=5}
    if {$part eq "search" || $part eq "datapath"} {lappend generics -gW=13 -gT=3}
    if {$part eq "control"} {lappend generics -gW=9 -gT=3 -gS=2}
    if {$part eq "shift" || $part eq "pairing"} {lappend generics -gT=3}
}
vsim -onfinish stop -voptargs=+acc {*}$generics work.$top +RANDOM_CYCLES=0
add wave -r sim:/$top/*
run -all
wave zoom full
# Leave simulation/waves open for inspection. A PASS line, not the waveform alone,
# is the acceptance criterion. This GUI convenience script is not a CI runner.
