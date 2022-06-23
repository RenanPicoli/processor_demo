#set_max_skew -from * -to [get_registers {*Q[0]*}] \
#		-get_skew_value_from_clock_period src_clock_period -skew_value_multiplier 0.8
#
#set_net_delay -from * -to [get_registers {*Q[0]*}] \
#     -get_value_from_clock_period dst_clock_period -value_multiplier 0.8 -max
	  
#set_max_skew -from [get_pins -compatibility_mode {data_in[*]}] -to [get_registers {*Q[0]*}] \
#		-get_skew_value_from_clock_period src_clock_period -skew_value_multiplier 0.8
#
#set_net_delay -from [get_pins -compatibility_mode {data_in[*]}] -to [get_registers {*Q[0]*}] \
#     -get_value_from_clock_period dst_clock_period -value_multiplier 0.8 -max
	  
#set_max_skew -from [get_ports {*sync_chain:*|data_in*}] -to [get_registers {*sync_chain:*|Q[0]*}] \
#		-get_skew_value_from_clock_period src_clock_period -skew_value_multiplier 0.8
#
#set_net_delay -from [get_ports {*sync_chain:*|data_in*}] -to [get_registers {*sync_chain:*|Q[0]*}] \
#     -get_value_from_clock_period dst_clock_period -value_multiplier 0.8 -max
	  
set_max_skew -from * -to [get_registers {*sync_chain:*|Q[0]*}] \
		-get_skew_value_from_clock_period src_clock_period -skew_value_multiplier 0.8

set_net_delay -from * -to [get_registers {*sync_chain:*|Q[0]*}] \
     -get_value_from_clock_period dst_clock_period -value_multiplier 0.8 -max