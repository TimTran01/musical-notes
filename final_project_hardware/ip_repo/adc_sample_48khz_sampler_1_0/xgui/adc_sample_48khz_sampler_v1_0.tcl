# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "CLK_FREQ_HZ" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MEM_FILE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SAMPLE_RATE_HZ" -parent ${Page_0}


}

proc update_PARAM_VALUE.CLK_FREQ_HZ { PARAM_VALUE.CLK_FREQ_HZ } {
	# Procedure called to update CLK_FREQ_HZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CLK_FREQ_HZ { PARAM_VALUE.CLK_FREQ_HZ } {
	# Procedure called to validate CLK_FREQ_HZ
	return true
}

proc update_PARAM_VALUE.MEM_FILE { PARAM_VALUE.MEM_FILE } {
	# Procedure called to update MEM_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MEM_FILE { PARAM_VALUE.MEM_FILE } {
	# Procedure called to validate MEM_FILE
	return true
}

proc update_PARAM_VALUE.SAMPLE_RATE_HZ { PARAM_VALUE.SAMPLE_RATE_HZ } {
	# Procedure called to update SAMPLE_RATE_HZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SAMPLE_RATE_HZ { PARAM_VALUE.SAMPLE_RATE_HZ } {
	# Procedure called to validate SAMPLE_RATE_HZ
	return true
}


proc update_MODELPARAM_VALUE.CLK_FREQ_HZ { MODELPARAM_VALUE.CLK_FREQ_HZ PARAM_VALUE.CLK_FREQ_HZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CLK_FREQ_HZ}] ${MODELPARAM_VALUE.CLK_FREQ_HZ}
}

proc update_MODELPARAM_VALUE.SAMPLE_RATE_HZ { MODELPARAM_VALUE.SAMPLE_RATE_HZ PARAM_VALUE.SAMPLE_RATE_HZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SAMPLE_RATE_HZ}] ${MODELPARAM_VALUE.SAMPLE_RATE_HZ}
}

proc update_MODELPARAM_VALUE.MEM_FILE { MODELPARAM_VALUE.MEM_FILE PARAM_VALUE.MEM_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MEM_FILE}] ${MODELPARAM_VALUE.MEM_FILE}
}

