# processor_demo
Setup for testing microprocessor repo (https://github.com/RenanPicoli/microprocessor) and IIR system identification in Altera DE2-115 board

![processor_demo_diagram](https://user-images.githubusercontent.com/19754679/198846484-a853597a-c4ff-4d01-ac0f-c87a9736f753.svg)

![processor_demo_timing](https://user-images.githubusercontent.com/19754679/198850892-ba2ec52a-6975-4611-bc4e-1ac79194e33d.svg)


* This branch is intended to create a fifo with different clocks for reading and writing
* For writing, new data should be pushed through a shift register
* For reading, only a pointer should be updated.
* All data should be multiplexed on output port, that pointer will be the selection input
* DON'T PUSH to I2S/master, until it is stable enough to be merged with processor_demo/master.
* PUSH to I2S/smart_fifo_refactoring instead.

* Tries to adapt filters of up to 8 weights (direct form I, feed-forward + feddback).
* Implements all elements, from registers to multipliers, multiply-accumulate, fpu, except PLL. The number of FPGA logical elements might be a restriction.
* A filtered audio signal is fed to the system, which performs a Full gradient IIR LMS algorithm to identify the filter used (guess its coeffients).
* reads inputs and previous outputs from a file, applies a IIR filter, then writes the new output to data_out output.
* Processor reads this output, compares it with the desired response, performs calculations and updates filter coefficients.
* Processor executes 1 instruction per cycle, its clock runs at 4 MHz.
* My intention was to run at 50 MHz, but this was postponed because I need learn about timing considerations (I learned this when trying to run at 50MHz: one of the ALU operands was arriving after the clock edge and messing everything)
* It will be added hardware for: inner product, address decoding, possibly multiplication of vector by scalar and vector addition.
* Since the file was generated by downsampling (2x) an audio sample recorded at 44100 Hz, the filter sampling frequency is 22050 Hz.
* In order to have real time processing, processor must process each new sample with 453 instructions, at most.
* The clock signal is provided by the onboard 50MHz oscillator, which is passes through a firts PLL to produce 5MHz, whose output is fed to a second PLL to generate 220500 Hz sampling clock, after this we use a factor 10 prescaler to produce sampling frequency (22050 Hz).
* The filter has only one input (single precision current sample) and only one output (single precision current output), previous samples are stored inside the filter.
* Filter coefficients will be updated every sampling edge, as long as a WREN signal is held high on the previous sampling edge.
