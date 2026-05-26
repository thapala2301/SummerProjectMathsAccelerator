# Xilinx Fast Fourier Transform IP

## What it does
The FFT IP computes the Discrete Fourier Transform (DFT) or the Inverse Discrete Fourier Transform (IDFT). It acts as a mathematical translation engine used heavily in Digital Signal Processing (DSP) to convert time-domain signals (like raw audio or radio waves) into frequency-domain data (showing the spectrum of frequencies present), and vice-versa.

## Key Interfaces
* **`S_AXIS_DATA` (Input):** The [[AXI4-Stream]] interface where raw time-domain (or frequency-domain) samples enter the math engine.
* **`M_AXIS_DATA` (Output):** The stream output that pushes out the calculated complex numbers (interleaved real and imaginary components).
* **`S_AXIS_CONFIG` (Control):** A crucial stream input that configures the FFT dynamically at runtime. It accepts packets that define the transform direction (Forward vs. Inverse) and scaling schedules to prevent math overflows.

## Key Parameter Adjustments (Vivado)
* **Transform Length (N):** The number of data points in a single FFT frame (e.g., 256, 1024, 4096). Larger lengths provide higher frequency resolution but take longer to compute and use more block RAM.
* **Architecture Choice:**
  * *Pipelined, Streaming I/O:* Uses the most FPGA logic but can process continuous streams of data without dropping samples. Essential for real-time processing.
  * *Radix-4 / Radix-2 Burst I/O:* Uses significantly fewer FPGA resources but pauses to calculate. It cannot accept new data while crunching the current frame.
* **Implementation Data Format:**
  * *Fixed Point:* Standard integer math. Uses less logic and is generally faster, but requires careful "scaling schedules" to prevent numbers from clipping.
  * *Floating Point:* Automatically handles extreme ranges of numbers without clipping, but consumes massive amounts of DSP slices and logic.