# processor_demo
Setup for testing microprocessor repo (https://github.com/RenanPicoli/microprocessor) in Altera DE2-115 board

microprocessor runs a program simulating a IIR filter, reading inputs and previous outputs from mini_ram, then writing the new output to mini_ram.
The clock is manually provided by a sliding switch.
The most recent output is read from data_memory_output (an output of microprocessor) when instruction_address reaches a predefined value (0xA, when the program loads the recently calculated output).
Then this value is converted from single precision IEEE754 encoding to scientific notation before being sent to 7 segments displays.
