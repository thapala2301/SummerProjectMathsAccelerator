'''
THIS SCRIPT IS ONLY FOR AUDIO: AUDIO DETERMINES CAMERA POSITION AND SDF_PARAMS
Captures audio from mic/USB adapter
Computes FFT + all features: 8 sdf_params
Applies scaling to get final scene values
Sends 11 floats to PYNQ via TCP port 9998
'''
import socket
import struct
import numpy as np
import sounddevice as sd
import threading
import math

PYNQ_IP     = "192.168.2.99"
PYNQ_PORT   = 9998
SAMPLE_RATE = 44100
BLOCK_SIZE  = 1024

BASS_BINS   = (1,  5)
MID_BINS    = (5,  47)
TREBLE_BINS = (47, 187)

BASE_CELL_SZ = 10.0; CELL_SZ_SCALE = 4.0
BASE_B_FP    = 4.5;  B_FP_SCALE    = 1.5
BASE_E_FP    = 0.15; E_FP_SCALE    = 0.1
ALPHA = 0.3

sock           = None
energy_history = []
smoothed_bass   = 0.0
smoothed_mid    = 0.0
smoothed_treble = 0.0
t = 0.0

def audio_callback(indata, frames, time, status):
    global smoothed_bass, smoothed_mid, smoothed_treble, t

    mono = indata[:, 0]
    fft  = np.abs(np.fft.rfft(mono))

    bass   = np.mean(fft[BASS_BINS[0]:BASS_BINS[1]])
    mid    = np.mean(fft[MID_BINS[0]:MID_BINS[1]])
    treble = np.mean(fft[TREBLE_BINS[0]:TREBLE_BINS[1]])

    smoothed_bass   = min(ALPHA * bass   + (1 - ALPHA) * smoothed_bass,   1.0)
    smoothed_mid    = min(ALPHA * mid    + (1 - ALPHA) * smoothed_mid,    1.0)
    smoothed_treble = min(ALPHA * treble + (1 - ALPHA) * smoothed_treble, 1.0)

    rms = min(float(np.sqrt(np.mean(mono ** 2))), 1.0)

    freqs    = np.fft.rfftfreq(BLOCK_SIZE, d=1.0 / SAMPLE_RATE)
    centroid = float(np.sum(freqs * fft) / (np.sum(fft) + 1e-6))
    centroid_norm = min(centroid / 8000.0, 1.0)

    frame_energy = float(np.mean(fft ** 2))
    energy_history.append(frame_energy)
    if len(energy_history) > 20:
        energy_history.pop(0)
    beat = 1.0 if frame_energy > 1.5 * np.mean(energy_history) else 0.0

    zcr = min(float(np.mean(np.abs(np.diff(np.sign(mono)))) / 2.0), 1.0)

    cell_sz = BASE_CELL_SZ + smoothed_bass   * CELL_SZ_SCALE
    b_fp    = BASE_B_FP    + smoothed_mid    * B_FP_SCALE
    e_fp    = BASE_E_FP    + smoothed_treble * E_FP_SCALE

    dt   = frames / SAMPLE_RATE
    t   += (smoothed_bass * 0.5 + 0.05) * dt
    R    = 8.0 - rms * 3.0
    pos_x = R * math.sin(t)
    pos_y = 0.15 + centroid_norm
    pos_z = R * math.cos(t)

    values = [pos_x, pos_y, pos_z, cell_sz, b_fp, e_fp, rms, centroid_norm, beat, zcr, 0.0]

    try:
        if sock:
            sock.sendall(struct.pack("11f", *values))
    except (BrokenPipeError, ConnectionResetError):
        print("PYNQ connection lost")

if __name__ == "__main__":
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((PYNQ_IP, PYNQ_PORT))
    print("connected to PYNQ")
    with sd.InputStream(samplerate=SAMPLE_RATE, blocksize=BLOCK_SIZE,
                        channels=1, dtype='float32',
                        callback=audio_callback):
        print("streaming audio, ctrl+c to stop")
        threading.Event().wait()
