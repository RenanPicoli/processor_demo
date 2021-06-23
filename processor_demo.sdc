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

## DATE    "Sat Jun 05 19:00:37 2021"

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

create_generated_clock -name {clk_12M} -source [get_pins {clk_12MHz|altpll_component|auto_generated|pll1|inclk[0]}] -multiply_by 12 -divide_by 50 -master_clock {clk_in} [get_pins {clk_12MHz|altpll_component|auto_generated|pll1|clk[0]}] 
create_generated_clock -name {uproc_clk} -source [get_pins {clk_dbg|altpll_component|auto_generated|pll1|inclk[0]}] -multiply_by 2 -divide_by 25 -master_clock {clk_in} [get_pins {clk_dbg|altpll_component|auto_generated|pll1|clk[1]}] 

# clk_dbg: 64MHz
create_generated_clock -name {clk_dbg} -source [get_pins {clk_dbg|altpll_component|auto_generated|pll1|inclk[0]}] -multiply_by 64 -divide_by 50 -phase 0 -master_clock {clk_in} [get_pins {clk_dbg|altpll_component|auto_generated|pll1|clk[0]}] 

create_generated_clock -name {i2s_WS} -source [get_pins {i2s|i2s|ws_gen|count[0]|clk}] -divide_by 64 -master_clock {i2s_128fs} [get_pins {i2s|i2s|WS|combout}] 
create_generated_clock -name {i2s_128fs} -source [get_pins {clk_fs_128fs|altpll_component|auto_generated|pll1|inclk[0]}] -multiply_by 4 -divide_by 17 -master_clock {clk_12M} [get_pins { clk_fs_128fs|altpll_component|auto_generated|pll1|clk[1] }] 
create_generated_clock -name {i2c_aux} -source [get_pins {i2c|i2c|CLK_aux_clk|count[0]|clk}] -divide_by 50 -master_clock {uproc_clk} [get_pins {i2c|i2c|CLK_aux_clk|CLK|q}] 
create_generated_clock -name {i2c_scl_clk} -source [get_pins {i2c|i2c|scl_clk|count[0]|clk}] -divide_by 2 -master_clock {uproc_clk} [get_pins {i2c|i2c|scl_clk|CLK|q}]  
create_generated_clock -name {i2c_scl} -source [get_pins {i2c|i2c|scl_clk|CLK|q}] -master_clock {i2c_scl_clk} [get_pins {i2c|i2c|SCL~0|combout}] 


#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************



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


#**************************************************************
# Set False Path
#**************************************************************

set_false_path  -from  [get_clocks *]  -to  [get_clocks {clk_dbg}]

# following intel guidelines, asynchronous reset is excluded from timing analysis:
set_false_path  -from  [get_ports {RST}] -to [all_registers]


#**************************************************************
# Set Multicycle Path
#**************************************************************

set_multicycle_path -setup -end -from [get_pins {i2s|i2s|WS|combout}] -to [get_cells {i2s|l_fifo|OVF i2s|r_fifo|OVF}] 2
#set_multicycle_path -setup -from [all_registers] -to [get_registers *processor|register_file*] 1
#set_multicycle_path -hold -from [all_registers] -to [get_registers *processor|register_file*] 0


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
