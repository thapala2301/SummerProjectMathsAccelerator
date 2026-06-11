import sounddevice as sd
import numpy as np

# step 1: list all audio devices, find your USB adapter
print(sd.query_devices())
DEVICE_INDEX = 0    # replace with whatever index the USB adapter shows as
SAMPLE_RATE  = 44100
BLOCK_SIZE   = 1024

# record one block and print FFT
data = sd.rec(BLOCK_SIZE, samplerate=SAMPLE_RATE, channels=1, 
              dtype='float32', device=DEVICE_INDEX, blocking=True)

fft = np.abs(np.fft.rfft(data[:, 0]))
print("FFT shape:", fft.shape)       # should be (513,)
print("Bass energy:",   np.mean(fft[1:5]))
print("Mid energy:",    np.mean(fft[5:47]))
print("Treble energy:", np.mean(fft[47:187]))
