import socket
import struct
import threading
import numpy as np
import sounddevice as sd
from pynq import Overlay, MMIO

DEFINE_TCP = True

#mmio
AXI_BASE_ADDR = 0x43C00000
AXI_SPAN = 0x1000

#audio
SAMPLE_RATE = 44100
BLOCK_SIZE = 1024 # samples per FFT, 23 ms per block

#FFT bin range (at 44100Hz, 1024 samples-> 43 Hz per bin)
BASS_BINS = (1, 5)
MID_BINS = (5, 47)
TREBLE_BINS = (47, 187)

#base secne values + how much each band can push them
BASE_CELL_SZ = 10.0; CELL_SZ_SCALE= 4.0
BASE_B_FP = 4.5; B_FP_SCALE = 1.5
BASE_E_FP = 0.15; E_FP_SCALE = 0.1

#smoothing: 0=no smoothing, 1=never changes
#smoothed = 0.3 × new + 0.7 × old for eg
ALPHA = 0.3

def fp32_to_fp27(value):
    # struct.pack(">f", value) converts the float to 4 big-endian bytes
    # struct.unpack(">I", ...) converts those bytes to an unsigned 32-bit int
    # struct.unpack returns a tuple, so use [0]
    bits = struct.unpack(">I", struct.pack(">f", float(value)))[0]
    sign = (bits >> 31) & 0x1
    exponent = (bits >> 23) & 0xFF
    fraction23 = bits & 0x7FFFFF

    # exponent == 0 is a special case
    # It represents zero or a subnormal number, which we simplify to signed zero
    # Only the sign bit in position 26
    if exponent == 0:
        return sign << 26

    # exponent == 0xFF is also a special case
    # It represents infinity if fraction23 == 0 and NaN if fraction23 != 0
    # We keep the sign bit in position 26, keep exp = 255 and have one bit in the fraction which is 1 if it's NaN
    if exponent == 0xFF:
        return (sign << 26) | (exponent << 18) | (1 if fraction23 else 0)

    fraction18 = (fraction23 + 0x10) >> 5
    if fraction18 >= (1 << 18):
        fraction18 = 0
        exponent = min(exponent + 1, 0xFF)

    return (sign << 26) | ((exponent & 0xFF) << 18) | fraction18

'''
writes regs 0-11 once at startup
'''
def write_default_camera(mmio):
    #identity lookat mtx: right = [1,0,0], up = [0,1,0], forward = [0,0,-1]
    defaults = [
        1.0, 0.0, 0.0,  #right vect (x)
        0.0, 1.0, 0.0, #up vec (y)
        0.0, 0.0, -1.0, #forward vec (z)
        0.0, 0.15, 4.5 # cam origin xyz
    ]
    for i,v in enumerate (defaults): #enumerate gives pair (index, value). i is posn, v is float at that psn
        mmio.write(i*4, fp32_to_fp27(v)) #

#smoothed val, shared between callback and main
smoothed_bass = 0.0
smoothed_mid = 0.0
smoothed_treble = 0.0

def audio_callback(indata, frames, time, status):
    global smoothed_bass, smoothed_mid, smoothed_treble
    ##FFT on mono audio?
    mono = indata[:, 0]
    fft = np.abs(np.fft.rfft(mono))
    
    #extract band energies
    bass = np.mean(fft[BASS_BINS[0]: BASS_BINS[1]])
    mid =  np.mean(fft[MID_BINS[0]: MID_BINS[1]])
    treble = np.mean(fft[TREBLE_BINS[0]: TREBLE_BINS[1]])
    
    #smooth
    smoothed_bass = ALPHA*bass + (1-ALPHA) * smoothed_bass
    smoothed_mid = ALPHA*mid + (1-ALPHA) * smoothed_mid
    smoothed_treble = ALPHA*treble + (1-ALPHA) * smoothed_treble