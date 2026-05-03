# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "BANK1_COEFF_FILE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "BANK2_COEFF_FILE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "BANK3_COEFF_FILE" -parent ${Page_0}


}

proc update_PARAM_VALUE.BANK1_COEFF_FILE { PARAM_VALUE.BANK1_COEFF_FILE } {
	# Procedure called to update BANK1_COEFF_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BANK1_COEFF_FILE { PARAM_VALUE.BANK1_COEFF_FILE } {
	# Procedure called to validate BANK1_COEFF_FILE
	return true
}

proc update_PARAM_VALUE.BANK2_COEFF_FILE { PARAM_VALUE.BANK2_COEFF_FILE } {
	# Procedure called to update BANK2_COEFF_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BANK2_COEFF_FILE { PARAM_VALUE.BANK2_COEFF_FILE } {
	# Procedure called to validate BANK2_COEFF_FILE
	return true
}

proc update_PARAM_VALUE.BANK3_COEFF_FILE { PARAM_VALUE.BANK3_COEFF_FILE } {
	# Procedure called to update BANK3_COEFF_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BANK3_COEFF_FILE { PARAM_VALUE.BANK3_COEFF_FILE } {
	# Procedure called to validate BANK3_COEFF_FILE
	return true
}


proc update_MODELPARAM_VALUE.BANK1_COEFF_FILE { MODELPARAM_VALUE.BANK1_COEFF_FILE PARAM_VALUE.BANK1_COEFF_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BANK1_COEFF_FILE}] ${MODELPARAM_VALUE.BANK1_COEFF_FILE}
}

proc update_MODELPARAM_VALUE.BANK2_COEFF_FILE { MODELPARAM_VALUE.BANK2_COEFF_FILE PARAM_VALUE.BANK2_COEFF_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BANK2_COEFF_FILE}] ${MODELPARAM_VALUE.BANK2_COEFF_FILE}
}

proc update_MODELPARAM_VALUE.BANK3_COEFF_FILE { MODELPARAM_VALUE.BANK3_COEFF_FILE PARAM_VALUE.BANK3_COEFF_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BANK3_COEFF_FILE}] ${MODELPARAM_VALUE.BANK3_COEFF_FILE}
}
