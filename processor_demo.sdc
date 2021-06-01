## Generated SDC file "processor_demo.sdc"

## Copyright (C) 2018  Intel Corporation. All rights reserved.
## Your use of Intel Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Intel Program License 
## Subscription Agreement, the Intel Quartus Prime License Agreement,
## the Intel FPGA IP License Agreement, or other applicable license
## agreement, including, without limitation, that your use is for
## the sole purpose of programming logic devices manufactured by
## Intel and sold by Intel or its authorized distributors.  Please
## refer to the applicable agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus Prime"
## VERSION "Version 18.1.0 Build 625 09/12/2018 SJ Lite Edition"

## DATE    "Sun May 30 17:22:48 2021"

##
## DEVICE  "EP4CE115F29C7"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {altera_reserved_tck} -period 100.000 -waveform { 0.000 50.000 } [get_ports {altera_reserved_tck}]
create_clock -name {clk_in} -period 20.000 -waveform { 0.000 10.000 } [get_ports {CLK_IN}]


#**************************************************************
# Create Generated Clock
#**************************************************************

create_generated_clock -name {uproc_clk} -source [get_ports {CLK_IN}] -divide_by 50 -master_clock {clk_in} [get_nets {processor|CLK}] 
create_generated_clock -name {clk_12M} -source [get_ports {CLK_IN}] -multiply_by 12 -divide_by 50 -master_clock {clk_in} [get_nets {clk_12MHz|altpll_component|auto_generated|wire_pll1_clk[0]}] 
create_generated_clock -name {clk_256fs} -source [get_nets {clk_12MHz|altpll_component|auto_generated|wire_pll1_clk[0]}] -multiply_by 8 -divide_by 17 -master_clock {clk_12M} [get_nets {clk_fs_256fs|altpll_component|auto_generated|wire_pll1_clk[1]}] 
create_generated_clock -name {scl} -source [get_pins {i2c|i2c|scl_clk|count[0]|clk}] -divide_by 100 -master_clock {clk_dbg|altpll_component|auto_generated|pll1|clk[1]} [get_ports {I2C_SCLK}] 


#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

set_clock_uncertainty -rise_from [get_clocks {altera_reserved_tck}] -rise_to [get_clocks {altera_reserved_tck}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {altera_reserved_tck}] -fall_to [get_clocks {altera_reserved_tck}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {altera_reserved_tck}] -rise_to [get_clocks {altera_reserved_tck}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {altera_reserved_tck}] -fall_to [get_clocks {altera_reserved_tck}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {uproc_clk}] -rise_to [get_clocks {uproc_clk}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {uproc_clk}] -fall_to [get_clocks {uproc_clk}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {uproc_clk}] -rise_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {uproc_clk}] -fall_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {uproc_clk}] -rise_to [get_clocks {uproc_clk}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {uproc_clk}] -fall_to [get_clocks {uproc_clk}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {uproc_clk}] -rise_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {uproc_clk}] -fall_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {clk_256fs}] -rise_to [get_clocks {clk_256fs}]  0.030  
set_clock_uncertainty -rise_from [get_clocks {clk_256fs}] -fall_to [get_clocks {clk_256fs}]  0.030  
set_clock_uncertainty -rise_from [get_clocks {clk_256fs}] -rise_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {clk_256fs}] -rise_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -hold 0.180  
set_clock_uncertainty -rise_from [get_clocks {clk_256fs}] -fall_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {clk_256fs}] -fall_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -hold 0.180  
set_clock_uncertainty -fall_from [get_clocks {clk_256fs}] -rise_to [get_clocks {clk_256fs}]  0.030  
set_clock_uncertainty -fall_from [get_clocks {clk_256fs}] -fall_to [get_clocks {clk_256fs}]  0.030  
set_clock_uncertainty -fall_from [get_clocks {clk_256fs}] -rise_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {clk_256fs}] -rise_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -hold 0.180  
set_clock_uncertainty -fall_from [get_clocks {clk_256fs}] -fall_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {clk_256fs}] -fall_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -hold 0.180  
set_clock_uncertainty -rise_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {uproc_clk}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {uproc_clk}]  0.020  
set_clock_uncertainty -rise_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {clk_256fs}] -setup 0.180  
set_clock_uncertainty -rise_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {clk_256fs}] -hold 0.200  
set_clock_uncertainty -rise_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {clk_256fs}] -setup 0.180  
set_clock_uncertainty -rise_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {clk_256fs}] -hold 0.200  
set_clock_uncertainty -rise_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}]  0.030  
set_clock_uncertainty -rise_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}]  0.030  
set_clock_uncertainty -fall_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {uproc_clk}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {uproc_clk}]  0.020  
set_clock_uncertainty -fall_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {clk_256fs}] -setup 0.180  
set_clock_uncertainty -fall_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {clk_256fs}] -hold 0.200  
set_clock_uncertainty -fall_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {clk_256fs}] -setup 0.180  
set_clock_uncertainty -fall_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {clk_256fs}] -hold 0.200  
set_clock_uncertainty -fall_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -rise_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}]  0.030  
set_clock_uncertainty -fall_from [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] -fall_to [get_clocks {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}]  0.030  


#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************

set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 


#**************************************************************
# Set False Path
#**************************************************************



#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************



#**************************************************************
# Set Net Delay
#**************************************************************

set_net_delay -max 10.000 -from [get_pins {processor|register_file|\registers:0:regx|Q[0]|q}] -to [get_pins {processor|register_file|\registers:0:regx|Q[0]|q}]
