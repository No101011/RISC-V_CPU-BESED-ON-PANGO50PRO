onerror {quit -code 1}
vlib report_ratio_work
vlog -sv -work report_ratio_work report_ratio_check.sv
vsim report_ratio_work.report_ratio_check
run -all
quit -f
