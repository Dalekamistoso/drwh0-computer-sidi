#set_global_assignment -name CYCLONEII_OPTIMIZATION_TECHNIQUE AREA
#set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE AREA"
#
#set_global_assignment -name VHDL_FILE ${boardpath}/deca/audio/audio_i2s.vhd
#set_global_assignment -name VERILOG_FILE ${boardpath}/deca/ulpi/ULPI_PS2.v
#set_global_assignment -name QIP_FILE     ${boardpath}/deca/ulpi/PLL_PHASE90.qip
#
# Audio output DETO1 = SIGMA_L, DETO2 = SIGMA_R
#set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to DETO1_PMOD2_6
#set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to DETO2_PMOD2_7
#
#set_global_assignment -name VERILOG_MACRO "USE_CLOCK_50=1"
#set_global_assignment -name VERILOG_MACRO "VGA_8BIT=1"
#set_global_assignment -name VERILOG_MACRO "USE_HDMI=1"
set_global_assignment -name VERILOG_MACRO "NO_DIRECT_UPLOAD=1"
set_global_assignment -name VERILOG_MACRO "I2S_AUDIO=1"
set_global_assignment -name VERILOG_MACRO "USE_AUDIO_IN=1"
#set_global_assignment -name VERILOG_MACRO "USE_QSPI=1"
#set_global_assignment -name VERILOG_MACRO "BIG_OSD=1"





