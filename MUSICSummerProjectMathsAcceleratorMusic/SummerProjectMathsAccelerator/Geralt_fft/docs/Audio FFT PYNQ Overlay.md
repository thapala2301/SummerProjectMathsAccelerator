## Overview
This hardware design offloads audio frequency analysis from the ARM processor to the FPGA fabric on a PYNQ board. It takes a time-domain audio signal, calculates the [[Fast Fourier Transform (Xilinx IP)]], and returns the frequency-domain magnitudes.
## System Architecture
The data and control flow relies on several interconnected blocks:
1. **The Brain:** [[Zynq-7000 Processing System]] manages the Python environment and orchestrates the hardware.
2. **The Data Mover:** The [[AXI Direct Memory Access (DMA)]] streams audio from RAM to the math block without bothering the CPU.
3. **The Math Engine:** The [[Fast Fourier Transform (Xilinx IP)]] crunches the numbers in real-time.
4. **The Configurator:** An [[AXI GPIO]] block is used as a lightweight way for the CPU to tell the FFT how to behave (e.g., Forward vs. Inverse FFT).
## Communication Protocols
* [[AXI4-Lite]]: Used by the Zynq to send slow control signals to the DMA and GPIO.
* [[AXI4-Stream]]: Used as a high-speed data highway to push raw audio bytes through the DMA and FFT.
## Top Level Design/Pin Assignment
![[FFT_TOP.png]]
