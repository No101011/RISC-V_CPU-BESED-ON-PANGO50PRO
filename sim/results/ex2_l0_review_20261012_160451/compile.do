onerror {quit -code 1}
set WLIB ex2_l0_review_20261012_160451_work
vlib $WLIB
set CORE_SRCS {}
foreach f [lsort [glob ../../rtl/core/*.v]] {
    if {[string match "*imem.v" $f] || [string match "*dmem.v" $f]} { continue }
    lappend CORE_SRCS $f
}
eval vlog -sv -work $WLIB +incdir+../../rtl/include +incdir+../tb/tb_myCPU $CORE_SRCS ../../rtl/soc/myCPU.sv ../../sim/tb/tb_myCPU/tb_myCPU.sv
vopt -work $WLIB +acc ${WLIB}.tb_myCPU -o tb_review_opt
quit -code 0