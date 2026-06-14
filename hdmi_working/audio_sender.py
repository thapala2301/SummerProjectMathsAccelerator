import socket
import struct
import sys
import time

import numpy as np
import sounddevice as sd

DEBUG = "--debug" in sys.argv
NO_BOARD = "--no-board" in sys.argv
SCENE_PACKET_FORMAT = "<4f2I4f"
DEBUG_EVERY = 5

def arg_value(flag):
    if flag in sys.argv:
        index = sys.argv.index(flag)
        if index + 1 < len(sys.argv):
            return sys.argv[index + 1]
    return None

PYNQ_IP = "192.168.2.99"
PYNQ_PORT = 9998
SAMPLE_RATE = 44100
BLOCK_SIZE = 1024

BASS_HZ = (43, 215)
MID_HZ = (215, 2000)
TREBLE_HZ = (2000, 8000)

BASE_CELL_SZ = 10.0
CELL_SZ_SCALE = 4.0
BASE_FRAME_EXTENT = 5.0
FRAME_EXTENT_SCALE = 1.5
BASE_FRAME_THICKNESS = 0.15
FRAME_THICKNESS_SCALE = 0.1
ALPHA = 0.3
SILENCE_GATE = 0.3

sock = None
energy_history = []
smoothed_bass = 0.0
smoothed_mid = 0.0
smoothed_treble = 0.0
smoothed_loudness = 0.0
smoothed_brightness = 0.0

def set_rate(sample_rate_hz):
    global SAMPLE_RATE, BASS_BINS, MID_BINS, TREBLE_BINS
    SAMPLE_RATE = int(sample_rate_hz)

    def bins(lo_hi):
        lo = max(1, round(lo_hi[0] * BLOCK_SIZE / sample_rate_hz))
        hi = max(lo + 1, round(lo_hi[1] * BLOCK_SIZE / sample_rate_hz))
        return (lo, hi)

    BASS_BINS = bins(BASS_HZ)
    MID_BINS = bins(MID_HZ)
    TREBLE_BINS = bins(TREBLE_HZ)

def clamp_byte(value):
    return max(0, min(int(value), 255))

def rgb_u32(red, green, blue):
    return (clamp_byte(red) << 16) | (clamp_byte(green) << 8) | clamp_byte(blue)

def smooth(previous, value):
    return min(ALPHA * value + (1 - ALPHA) * previous, 1.0)

def band_ratio(fft, bins, total):
    return float(np.sum(fft[bins[0]:bins[1]])) / total

def debug_bar(value, width=12):
    return ("#" * int(min(max(value, 0.0), 1.0) * width)).ljust(width)

def build_scene_values(bass, mid, treble, loudness, brightness, beat, roughness):
    cell_sz = BASE_CELL_SZ + bass * CELL_SZ_SCALE
    half_cell = 0.5 * cell_sz
    frame_extent = BASE_FRAME_EXTENT + mid * FRAME_EXTENT_SCALE
    frame_thickness = BASE_FRAME_THICKNESS + treble * FRAME_THICKNESS_SCALE

    bg_rgb = rgb_u32(
        64 * loudness,
        96 * brightness,
        160 * brightness,
    )
    bar_rgb = rgb_u32(
        96 + 159 * treble + 32 * beat,
        96 + 159 * mid + 32 * beat,
        96 + 159 * bass + 32 * beat,
    )

    return (
        cell_sz,
        half_cell,
        frame_extent,
        frame_thickness,
        bg_rgb,
        bar_rgb,
        beat,
        loudness,
        brightness,
        roughness,
    )

set_rate(SAMPLE_RATE)

def audio_callback(indata, frames, time_info, status):
    global smoothed_bass, smoothed_mid, smoothed_treble
    global smoothed_loudness, smoothed_brightness

    mono = indata.mean(axis=1)
    if np.abs(mono).max() > 2.0:
        mono = mono / 32768.0

    fft = np.abs(np.fft.rfft(mono))
    total = float(np.sum(fft))
    silent = total < SILENCE_GATE

    if silent:
        bass = 0.0
        mid = 0.0
        treble = 0.0
    else:
        bass = band_ratio(fft, BASS_BINS, total)
        mid = band_ratio(fft, MID_BINS, total)
        treble = band_ratio(fft, TREBLE_BINS, total)

    smoothed_bass = smooth(smoothed_bass, bass)
    smoothed_mid = smooth(smoothed_mid, mid)
    smoothed_treble = smooth(smoothed_treble, treble)

    loudness = min(float(np.sqrt(np.mean(mono ** 2))), 1.0)

    if silent:
        loudness = 0.0
        brightness = 0.0
        beat = 0.0
        roughness = 0.0
        smoothed_loudness = 0.0
        smoothed_brightness = 0.0
    else:
        freqs = np.fft.rfftfreq(BLOCK_SIZE, d=1.0 / SAMPLE_RATE)
        centroid = float(np.sum(freqs * fft) / (np.sum(fft) + 1e-6))
        brightness = min(centroid / 8000.0, 1.0)

        frame_energy = float(np.mean(fft ** 2))
        energy_history.append(frame_energy)
        if len(energy_history) > 20:
            energy_history.pop(0)
        beat = 1.0 if frame_energy > 1.5 * np.mean(energy_history) else 0.0

        roughness = min(float(np.mean(np.abs(np.diff(np.sign(mono)))) / 2.0), 1.0)

        smoothed_loudness = smooth(smoothed_loudness, loudness)
        smoothed_brightness = smooth(smoothed_brightness, brightness)

    scene_values = build_scene_values(
        smoothed_bass,
        smoothed_mid,
        smoothed_treble,
        smoothed_loudness,
        smoothed_brightness,
        beat,
        roughness,
    )

    if DEBUG and not hasattr(audio_callback, "_n"):
        audio_callback._n = 0
    if DEBUG:
        audio_callback._n += 1
        if audio_callback._n % DEBUG_EVERY == 0:
            print(
                f"\rbass[{debug_bar(smoothed_bass)}] mid[{debug_bar(smoothed_mid)}] "
                f"treb[{debug_bar(smoothed_treble)}] loud[{debug_bar(smoothed_loudness)}] "
                f"bright[{debug_bar(smoothed_brightness)}] rough[{debug_bar(roughness)}] "
                f"beat:{'X' if beat else '.'}  ",
                end="",
                flush=True,
            )

    try:
        if sock:
            sock.sendall(struct.pack(SCENE_PACKET_FORMAT, *scene_values))
    except (BrokenPipeError, ConnectionResetError, OSError):
        globals()["sock"] = None

def connect():
    while True:
        try:
            connection = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            connection.connect((PYNQ_IP, PYNQ_PORT))
            print("\nconnected to PYNQ")
            return connection
        except OSError:
            print("\rconnecting to PYNQ...", end="", flush=True)
            time.sleep(1)

if __name__ == "__main__":
    if "--list-devices" in sys.argv:
        print(sd.query_devices())
        sys.exit(0)

    device = arg_value("--device")
    if device is not None and device.isdigit():
        device = int(device)

    info = sd.query_devices(device if device is not None else None, "input")
    channels = 2 if info["max_input_channels"] >= 2 else 1
    set_rate(info["default_samplerate"])
    print(
        f"audio input: {info['name']} ({channels} ch @ {SAMPLE_RATE} Hz, "
        f"bins bass{BASS_BINS} mid{MID_BINS} treble{TREBLE_BINS})"
    )

    sock = None if NO_BOARD else connect()

    with sd.InputStream(
        device=device,
        samplerate=SAMPLE_RATE,
        blocksize=BLOCK_SIZE,
        channels=channels,
        dtype="float32",
        callback=audio_callback,
    ):
        print("streaming audio, ctrl+c to stop")
        while True:
            if not NO_BOARD and sock is None:
                print("\nPYNQ connection lost, reconnecting...")
                sock = connect()
            time.sleep(0.5)
