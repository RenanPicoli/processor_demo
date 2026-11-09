# processor_demo

Single chip computer based on my own RISC microprocessor (https://github.com/RenanPicoli/microprocessor). Built and tested on Altera DE2-115 board.

<img width="1800" height="1320" alt="processor_demo_blocks_en" src="https://github.com/user-attachments/assets/d6aa52ad-33a7-4597-baf8-b71c8f500250" />

It consists of 2 clock domains:
* domain 0: CPU and most of the peripherals running at 4 MHz
* domain 1: DMA, SDRAM and VGA running at 75MHz

* The clock signals are provided by the onboard 50MHz oscillator, which is passes through a firts PLL to produce 4MHz, whose output is fed to a second PLL to generate 220500 Hz sampling clock, after this we use a factor 10 prescaler to produce sampling frequency (22050 Hz).
Due to the CPU complexity (single precision FPU inside datapath, 2 stages pipeline, etc) the cpu frequency is currently less than the SDRAM frequency, unlike most of the computers.

For each domain, arbiters select between one of the 2 masters (CPU and DMA), if a master requests access to a peripheral at the other domain, its bus goes through a CDC bridge (based on dual-clock fifos) before passing through the arbiter

The wiki describes a task to test the system: running an adaptative filter algorithm (for IIR filter identification). Refer to : https://github.com/RenanPicoli/processor_demo/wiki#objective

## DSP peripherals
* It was added hardware for: inner product, address decoding, multiplication of vector by scalar and vector addition (VMAC).
* Inner product and VMAC operate on vectors of 8 single precision floats.
* A parallel vector transfer bus (vector_bus) was used to allow one full vector of 8 floats to be transferred between these peripherals in one ram clock cycle. Of course, this makes the timing constraints harder to achieve.

## IIR Filter
* The filter has only one input (single precision current sample) and only one output (single precision current output), previous samples are stored inside the filter.
* Filter coefficients will be updated every sampling edge, as long as a WREN signal is held high on the previous sampling edge.
