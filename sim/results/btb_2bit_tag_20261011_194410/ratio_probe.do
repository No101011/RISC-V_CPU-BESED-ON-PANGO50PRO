onerror {quit -code 1}
vlib btb_ratio_probe2_20261011_194410
vlog -sv -work btb_ratio_probe2_20261011_194410 ../results/btb_2bit_tag_20261011_194410/ratio_probe.sv
vsim -onfinish stop -voptargs=+acc btb_ratio_probe2_20261011_194410.ratio_probe
run -all
quit -f
