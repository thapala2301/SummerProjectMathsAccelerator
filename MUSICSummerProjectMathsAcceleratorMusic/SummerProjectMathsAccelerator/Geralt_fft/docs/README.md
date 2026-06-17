## Audio-Sync Ray Marcher: FFT Processing Block

This directory contains the Fast Fourier Transform (FFT) hardware-software pipeline for the Audio-Sync Ray Marcher project. This block is responsible for taking incoming digital audio, converting it into the frequency domain using the Programmable Logic (PL), and passing the binned frequency magnitudes to the Processing System (PS) to drive the visual ray marcher.

### 1. System Architecture
The audio processing pipeline utilizes hardware-software co-design on the PYNQ-Z1:
* **Hardware (PL):** A Xilinx FFT IP block configured for a 1024-point transform processes the incoming audio stream via AXI4-Stream.
* **Transport:** An AXI Direct Memory Access (DMA) block moves the raw FFT output from the PL directly into the CPU's DDR memory.
* **Software (PS):** Python (NumPy) running on the ARM core unpacks the DMA buffer, calculates magnitudes, and averages the frequencies into distinct bands (Bass, Mids, Highs) for the rendering engine.

### 2. Output Data Format (Hardware to Software)
The Xilinx FFT IP outputs complex numbers. Because we are using 16-bit input data, the FFT packs the output into a single 32-bit word over the AXI-Stream interface:
* **Bits [15:0]:** Real component ($R$), represented as a 16-bit two's complement signed integer.
* **Bits [31:16]:** Imaginary component ($I$), represented as a 16-bit two's complement signed integer.

### 3. Mathematical Calculations

#### A. Magnitude Calculation
The ray marcher requires the amplitude (volume) of the frequencies, not phase. The CPU extracts the Real and Imaginary components and calculates the magnitude using the following formula:

$$Magnitude = \sqrt{R^2 + I^2}$$

#### B. Frequency Resolution (Bin Width)
The FFT takes a time-domain signal and divides it into $N$ frequency bins. The frequency width of each bin is determined by the audio sample rate ($F_s$) and the FFT size ($N$).

Given our system parameters:
* $F_s = 44100 	ext{ Hz}$ (Standard Audio Sample Rate)
* $N = 1024$ (FFT Size)

The resolution is calculated as:

$$	ext{Bin Width} = rac{F_s}{N} = rac{44100}{1024}  pprox 43.07 	ext{ Hz per bin}$$

#### C. Nyquist Theorem and Usable Bins
According to the Nyquist-Shannon sampling theorem, an FFT can only accurately represent frequencies up to half the sample rate (the Nyquist frequency). 
* **Nyquist Frequency:** $rac{44100}{2} = 22050 	ext{ Hz}$
* Therefore, only the first **512 bins** (0 to 511) contain useful audio data. The second half of the 1024 output array is a complex conjugate mirror and is discarded in software.
* **Bin 0** represents the DC offset (0 Hz) and is also discarded to prevent visual glitches.

### 4. Frequency Binning Strategy (Feature Extraction)
To provide the ray marcher with stable, manageable parameters, the 511 usable bins are averaged into three distinct frequency bands. Based on our 43.07 Hz bin width, the mapping is as follows:

| Ray Marcher Parameter | Target Frequency Range | Corresponding FFT Bins | Calculation Method |
| :--- | :--- | :--- | :--- |
| **Bass** | ~43 Hz to 250 Hz | Bins 1 to 5 | Arithmetic Mean |
| **Mids** | ~250 Hz to 2000 Hz | Bins 6 to 46 | Arithmetic Mean |
| **Highs** | ~2000 Hz to 11000 Hz | Bins 47 to 256 | Arithmetic Mean |

*(Note: Frequencies above ~11000 Hz are ignored, as they contain negligible physical energy in most music and introduce unnecessary noise to the visualizer).*

### 5. Design Considerations: Linear FFT vs. Logarithmic Hearing

While the binning strategy outlined in Section 4 is fully functional and standard for real-time visualizers, it exhibits a numerical imbalance:

* Bass (43 Hz - 250 Hz): Represented by only 5 bins.
* Highs (2000 Hz - 11000 Hz): Represented by over 200 bins.

This occurs because the Fast Fourier Transform (FFT) divides the frequency spectrum linearly (each bin in our system is exactly ~43 Hz wide), whereas human hearing and musical pitches scale logarithmically (by octaves). Deep bass frequencies occupy a very narrow absolute frequency range (e.g., the octave from 50 Hz to 100 Hz is only 50 Hz wide), while high-frequency octaves span thousands of Hertz.

#### Functional Impact

Despite this numerical disparity, the current 5-bin strategy for the bass band is highly effective. Low-frequency audio features (like kick drums and 808s) contain immense physical energy. When these elements occur, the magnitude within those 5 specific bins spikes dramatically, providing a highly reactive, high-contrast parameter (bass_val) for the ray marcher's geometric deformations.

#### Future Scalability

If future iterations of the visualizer require finer control over the low-frequency spectrum (e.g., separating sub-bass from a higher kick drum), the system architecture can be easily scaled to provide higher resolution:

* **Hardware Adjustment (PL):** Increase the FFT Size (`N`) in the Xilinx FFT IP block. For example, moving from `N = 1024` to `N = 4096` reduces the bin width to ~10.7 Hz per bin.
* **Software Adjustment (PS):** Update the Python processing script. At `N = 4096`, the 43 Hz - 250 Hz bass range would span ~20 bins, allowing it to be split into multiple distinct, granular parameters for the graphics pipeline.

Currently, `N = 1024` is utilized as the optimal baseline to balance PL resource utilization, CPU processing time, and visual reactivity.