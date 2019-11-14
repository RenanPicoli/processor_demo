# processor_demo
Setup for testing microprocessor repo (https://github.com/RenanPicoli/microprocessor) in Altera DE2-115 board

* microprocessor runs a program simulating a IIR filter, reading inputs and previous outputs from mini_ram, then writing the new output to mini_ram.
* The clock signal is provided by the onboard 50MHz oscillator, which is prescaled by a factor 50.000.000 to reduce frequency to 1Hz.
* The most recent output is read from data_memory_output (an output of microprocessor) when instruction_address reaches a predefined value (0x28, when the program loads the recently calculated output).
* Then this value is displayed as an hexadecimal value on the 7 segments displays.
* While other instructions are being executed, its address is displayed.
