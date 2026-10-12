# ============================================================================
# Questa / ModelSim run script for CoreMark on the RV32IM CPU.
#
# Run from this directory (sim/programs), with vsim reachable:
#     vsim -c -do coremark.do
# On Windows the license env may need setting in this shell first:
#     set LM_LICENSE_FILE=D:\realsoftwares\modelsim\LICENSE.TXT
#
# How the program talks to the testbench (see tests/coremark/port/syscalls.c,
# decoded in sim/tb/tb_myCPU/tb_myCPU.sv):
#   write 0xF000_0000 -> the TB prints the low 8 bits as a character (printf)
#   write 0xF000_0004 -> the TB dumps perf counters and finishes   (EXIT)
# Both addresses are decoded by tb_myCPU only; the FPGA SoC has no such
# decoder, so on-board output needs extra logic in perip_bridge.sv.
# ============================================================================

set WLIB work
if {[info exists env(COREMARK_WORK_LIB)]} { set WLIB $env(COREMARK_WORK_LIB) }
if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $WLIB]} { error "Invalid COREMARK_WORK_LIB" }
catch { vdel -lib $WLIB -all }
vlib $WLIB

set INC ../../rtl/include

# Collect rtl/core/*.v by glob (skip the legacy imem.v / dmem.v).
# Do NOT hardcode the file list: the old one referenced branch_predictor.v,
# mem1_mem2_reg.v and mem2_wb_reg.v, none of which exist any more.
set CORE_SRCS {}
foreach f [lsort [glob ../../rtl/core/*.v]] {
    if {[string match "*imem.v" $f] || [string match "*dmem.v" $f]} { continue }
    lappend CORE_SRCS $f
}
eval vlog -sv -work $WLIB "+incdir+$INC" $CORE_SRCS \
    ../../rtl/soc/myCPU.sv.bak_prebtb_2bit_tag_20261011_193355_808 \
    ../../sim/tb/tb_myCPU/tb_myCPU.sv

set IHEX ../../tests/coremark/build/imem.hex
set DHEX ../../tests/coremark/build/dmem.hex
if {[info exists env(COREMARK_IMEM_HEX)]} { set IHEX $env(COREMARK_IMEM_HEX) }
if {[info exists env(COREMARK_DMEM_HEX)]} { set DHEX $env(COREMARK_DMEM_HEX) }

# Match the selected HEX files against their ELF before enabling timed reports.
# The observer samples the actual timer CSR reads in EX1; function-entry PCs
# would include a different boundary overhead. PERF_ENABLE=0 gives whole-run
# reports for images without an ELF or without preserved timer symbols.
set PERF_ENABLE 1
if {[info exists env(COREMARK_PERF_ENABLE)]} { set PERF_ENABLE $env(COREMARK_PERF_ENABLE) }
if {$PERF_ENABLE ni {0 1}} { error "COREMARK_PERF_ENABLE must be 0 or 1" }
set PERF_ARGS [list +PERF_ENABLE=$PERF_ENABLE]
if {$PERF_ENABLE} {
    set PERF_PYTHON python
    if {[info exists env(COREMARK_PYTHON)]} { set PERF_PYTHON $env(COREMARK_PYTHON) }
    set META_CMD [list $PERF_PYTHON coremark_perf_metadata.py --imem $IHEX --dmem $DHEX]
    if {[info exists env(COREMARK_PERF_ELF)]} { lappend META_CMD --elf $env(COREMARK_PERF_ELF) }
    if {[catch {exec {*}$META_CMD 2>@1} PERF_META_OUTPUT]} {
        error "Cannot enable CoreMark timed report: $PERF_META_OUTPUT\nSet COREMARK_PYTHON / COREMARK_PERF_ELF as needed, or COREMARK_PERF_ENABLE=0 for whole-run reports."
    }
    # Some Windows Python launchers write startup diagnostics to stderr even
    # on success. Accept only the helper's strictly numeric metadata line.
    set PERF_META ""
    foreach line [split $PERF_META_OUTPUT "\n"] {
        set line [string trim $line]
        if {[regexp {^start_pc [0-9a-f]{8} stop_pc [0-9a-f]{8} iterations [0-9]+ text_bytes [0-9]+$} $line]} {
            set PERF_META $line
        } elseif {$line ne ""} { echo "Python: $line" }
    }
    if {$PERF_META eq ""} { error "No valid CoreMark metadata returned: $PERF_META_OUTPUT" }
    lappend PERF_ARGS +PERF_START_PC=[dict get $PERF_META start_pc] \
                     +PERF_STOP_PC=[dict get $PERF_META stop_pc] \
                     +PERF_ITERATIONS=[dict get $PERF_META iterations]
    echo "CoreMark ELF/HEX matched; .text bytes=[dict get $PERF_META text_bytes]"
}
set PERF_CSV coremark_perf.csv
if {[info exists env(COREMARK_REPORT_CSV)]} { set PERF_CSV $env(COREMARK_REPORT_CSV) }
if {$PERF_CSV ne ""} { lappend PERF_ARGS +PERF_REPORT_CSV=$PERF_CSV }

# Cycle cap, default 200M (= 2 s at 100 MHz, plenty for CoreMark).
# For a quick smoke run:  set COREMARK_MAX_CYCLES=2000000
set MC 200000000
if {[info exists env(COREMARK_MAX_CYCLES)]} { set MC $env(COREMARK_MAX_CYCLES) }

vsim -onfinish stop \
     -voptargs=+acc \
     -gIROM_HEX=$IHEX \
     -gDRAM_HEX=$DHEX \
     -gMAX_CYCLES=$MC \
     {*}$PERF_ARGS \
     ${WLIB}.tb_myCPU

run -all

# The TB already prints both scopes and writes the CSV. Legacy u_perf counters
# have a different instruction definition and must not be mixed into this report.

quit -f
