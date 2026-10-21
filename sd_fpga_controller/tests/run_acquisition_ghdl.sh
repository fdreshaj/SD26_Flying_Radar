#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -f -- "$work/work-obj08.cf" "$work/unisim-obj08.cf" "$work/tb_ad9284_capture" "$work/tb_ad9284_to_axis" "$work/tb_axis_byte_packetizer" "$work/tb_spi_master_to_axis_fifo" "$work/"*.o; rmdir -- "$work"' EXIT
cd -- "$work"
rtl="$root/sd_fpga_controller.srcs/sources_1/new"
ghdl -a --std=08 --work=unisim "$root/tests/models/unisim_capture_models.vhd"
ghdl -a --std=08 "$rtl/spi_master.vhd" "$rtl/spi_master_to_axis.vhd" \
  "$rtl/axis_byte_packetizer.vhd" "$rtl/spi_master_to_axis_fifo.vhd" \
  "$rtl/ad9284_capture.vhd" "$rtl/ad9284_lvds_rx.vhd" "$rtl/ad9284_to_axis.vhd" \
  "$root/tests/tb_ad9284_capture.vhd" "$root/tests/tb_ad9284_to_axis.vhd" \
  "$root/tests/tb_axis_byte_packetizer.vhd" "$root/tests/tb_spi_master_to_axis_fifo.vhd"
for half_period in 4 5 7; do
  ghdl -r --std=08 tb_ad9284_capture -gsample_half_ns="$half_period" --assert-level=error
done
for mapping in true false; do
  for previous_falling in true false; do
    ghdl -r --std=08 tb_ad9284_to_axis -grising_is_a="$mapping" \
      -gpair_previous_falling="$previous_falling" --assert-level=error
  done
done
for bytes in 4 256; do
  ghdl -r --std=08 tb_axis_byte_packetizer -gpacket_bytes="$bytes" --assert-level=error
done
for mode in 0 1 2 3; do
  ghdl -r --std=08 tb_spi_master_to_axis_fifo -gmode="$mode" --assert-level=error
  ghdl --synth --std=08 -gcpol="'$((mode / 2))'" -gcpha="'$((mode % 2))'" \
    spi_master_to_axis_fifo > /dev/null
done
ghdl --synth --std=08 ad9284_capture > /dev/null
ghdl --synth --std=08 axis_byte_packetizer > /dev/null
