import numpy as np

# 1. Simulate receiving the 32-bit DMA buffer (1024 samples)
# In reality, this comes from: dma_buffer = dma.recvchannel.transfer(...)
dma_buffer = np.array([...], dtype=np.uint32) 

# 2. Unpack Real and Imaginary parts using bitwise masks
# We cast to int16 so Python correctly handles the signed negative numbers
real_parts = np.int16(dma_buffer & 0x0000FFFF)
imag_parts = np.int16((dma_buffer & 0xFFFF0000) >> 16)

# 3. Calculate Magnitude
# Using float32 for the math to prevent overflow
magnitudes = np.sqrt(np.square(real_parts, dtype=np.float32) + np.square(imag_parts, dtype=np.float32))

# 4. Discard the second half (Nyquist symmetry) and the DC offset (Bin 0)
useful_mags = magnitudes[1:512] 

# 5. Average the bins into 3 Ray Marcher Parameters
# Assuming ~43Hz per bin:
bass_band = np.mean(useful_mags[0:5])     # Bins 1-5 (approx 43Hz - 250Hz)
mids_band = np.mean(useful_mags[5:46])    # Bins 6-46 (approx 250Hz - 2000Hz)
highs_band = np.mean(useful_mags[46:256]) # Bins 47-256 (approx 2000Hz - 11000Hz)

print(f"Bass Energy: {bass_band}")
print(f"Mids Energy: {mids_band}")
print(f"Highs Energy: {highs_band}")