set spi_root [file dirname [file normalize [info script]]]
if {[current_project -quiet] eq ""} {
    open_project [file join $spi_root sd_fpga_controller.xpr]
}
if {[file normalize [get_property DIRECTORY [current_project]]] ne $spi_root} {
    error "Open the sd_fpga_controller project before importing SPI sources."
}
foreach name {
    spi_master spi_slave spi_async_fifo spi_to_axis spi_slave_to_axis spi_master_to_axis
    axis_byte_packetizer spi_master_to_axis_fifo ad9284_capture ad9284_lvds_rx ad9284_to_axis
} {
    set path [file join $spi_root sd_fpga_controller.srcs sources_1 new ${name}.vhd]
    if {[llength [get_files -quiet $path]] == 0} {
        add_files -fileset sources_1 -norecurse $path
    }
}
foreach name {
    tb_spi_master tb_spi_to_axis tb_spi_master_to_axis_fifo tb_spi_master_to_axis
    tb_axis_byte_packetizer tb_ad9284_capture tb_ad9284_to_axis
} {
    set path [file join $spi_root tests ${name}.vhd]
    if {[llength [get_files -quiet $path]] == 0} {
        add_files -fileset sim_1 -norecurse $path
    }
    set_property FILE_TYPE {VHDL 2008} [get_files $path]
}
set_property top spi_to_axis [get_filesets sources_1]
set_property top tb_spi_to_axis [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
