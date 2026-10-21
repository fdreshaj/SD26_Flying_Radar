#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -f -- "$work/work-obj08.cf" "$work/tb_spi_master" "$work/tb_spi_to_axis" "$work/tb_spi_master_to_axis" "$work/"*.o; rmdir -- "$work"' EXIT
cd -- "$work"
rtl="$root/sd_fpga_controller.srcs/sources_1/new"
ghdl -a --std=08 "$rtl/spi_master.vhd" "$rtl/spi_slave.vhd" \
  "$rtl/spi_async_fifo.vhd" "$rtl/spi_to_axis.vhd" \
  "$rtl/spi_slave_to_axis.vhd" "$rtl/spi_master_to_axis.vhd" \
  "$root/tests/tb_spi_master.vhd" "$root/tests/tb_spi_to_axis.vhd" \
  "$root/tests/tb_spi_master_to_axis.vhd"
ghdl -e --std=08 tb_spi_master
ghdl -e --std=08 tb_spi_to_axis
ghdl -e --std=08 tb_spi_master_to_axis
for width in 8 16; do
  for divider in 1 3; do
    ghdl -r --std=08 tb_spi_master -gwidth="$width" -gdivider="$divider" --assert-level=error
  done
done
for mode in 0 1 2 3; do
  for divider in 1 3; do
    ghdl -r --std=08 tb_spi_master_to_axis -gmode="$mode" \
      -gdivider="$divider" --assert-level=error
  done
  for half_period in 10 15; do
    ghdl -r --std=08 tb_spi_to_axis -gmode="$mode" \
      -ghalf_period_ns="$half_period" --assert-level=error
  done
  ghdl --synth --std=08 -gcpol="'$((mode / 2))'" -gcpha="'$((mode % 2))'" \
    spi_slave_to_axis > /dev/null
  ghdl --synth --std=08 -gcpol="'$((mode / 2))'" -gcpha="'$((mode % 2))'" \
    spi_master_to_axis > /dev/null
done
ghdl --synth --std=08 spi_master > /dev/null
