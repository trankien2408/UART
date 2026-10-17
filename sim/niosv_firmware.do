onerror {quit -code 1 -force}
onbreak {quit -code 1 -force}
catch {fconfigure stdout -buffering line}
set root $env(UART_PROJECT_ROOT)
set QSYS_SIMDIR "$root/fpga/build/uart_soc/simulation"
source "$QSYS_SIMDIR/mentor/msim_setup.tcl"
puts "UART_SIM: compiling device libraries and generated SoC"
dev_com
com
puts "UART_SIM: compiling board top and firmware testbench"
vlog -sv -work work "$root/fpga/de2_115_uart_top.v" "$root/tb/tb_niosv_firmware.v"
if {[info exists env(UART_SOC_COMPILE_ONLY)] && $env(UART_SOC_COMPILE_ONLY) eq "1"} {
    puts "PASS Nios V simulation compile only (no CPU execution)"
    quit -code 0 -force
}
# Generated script copies the default initialization image. Replace it only in
# this temporary simulation working directory with the actual firmware image.
file copy -force "$root/firmware/build/app/build/ram.hex" uart_soc_ram.hex
set TOP_LEVEL_NAME tb_niosv_firmware
set USER_DEFINED_ELAB_OPTIONS {-voptargs=+acc}
puts "UART_SIM: elaborating Nios V model and loading firmware RAM"
elab
puts "UART_SIM: running CPU; waiting for firmware READY (boot deadline 5 ms simulated)"
run -all
quit -code 0 -force
