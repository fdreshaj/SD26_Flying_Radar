# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "clk_divider" -parent ${Page_0}
  ipgui::add_param $IPINST -name "cpha" -parent ${Page_0}
  ipgui::add_param $IPINST -name "cpol" -parent ${Page_0}


}

proc update_PARAM_VALUE.clk_divider { PARAM_VALUE.clk_divider } {
	# Procedure called to update clk_divider when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.clk_divider { PARAM_VALUE.clk_divider } {
	# Procedure called to validate clk_divider
	return true
}

proc update_PARAM_VALUE.cpha { PARAM_VALUE.cpha } {
	# Procedure called to update cpha when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.cpha { PARAM_VALUE.cpha } {
	# Procedure called to validate cpha
	return true
}

proc update_PARAM_VALUE.cpol { PARAM_VALUE.cpol } {
	# Procedure called to update cpol when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.cpol { PARAM_VALUE.cpol } {
	# Procedure called to validate cpol
	return true
}


proc update_MODELPARAM_VALUE.cpol { MODELPARAM_VALUE.cpol PARAM_VALUE.cpol } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.cpol}] ${MODELPARAM_VALUE.cpol}
}

proc update_MODELPARAM_VALUE.cpha { MODELPARAM_VALUE.cpha PARAM_VALUE.cpha } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.cpha}] ${MODELPARAM_VALUE.cpha}
}

proc update_MODELPARAM_VALUE.clk_divider { MODELPARAM_VALUE.clk_divider PARAM_VALUE.clk_divider } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.clk_divider}] ${MODELPARAM_VALUE.clk_divider}
}

