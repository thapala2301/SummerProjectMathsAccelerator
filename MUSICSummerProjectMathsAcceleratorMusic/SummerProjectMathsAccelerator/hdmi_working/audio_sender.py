import socket
import struct
import sys
import time
import math
from collections import deque
from dataclasses import dataclass

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
MAX_BRIGHTNESS_HZ = 8000.0

CELL_SZ = 10.0
HALF_CELL = 5.0

SHAPE_SIZE_BASE = 0.28
SHAPE_SIZE_LEVEL_GAIN = 0.16
SHAPE_SIZE_BASS_GAIN = 0.16
SHAPE_SIZE_PULSE_GAIN = 0.18
SHAPE_SIZE_LFO_GAIN = 0.12

SHAPE_EXTRA_BASE = 0.20
SHAPE_EXTRA_TREBLE_GAIN = 0.12
SHAPE_EXTRA_NOISE_GAIN = 0.10
SHAPE_EXTRA_PULSE_GAIN = 0.12
SHAPE_EXTRA_LFO_GAIN = 0.08

MIN_MOTION_HZ = 0.10
MAX_MOTION_HZ = 1.20
MIN_BEAT_INTERVAL_S = 0.22
MIN_BPM = 60.0
MAX_BPM = 180.0
TEMPO_ATTACK = 0.25
TEMPO_RELEASE = 0.08

SILENCE_GATE = 0.3
ENERGY_HISTORY = 20
BEAT_THRESHOLD = 1.5
BEAT_DECAY = 0.90

BAND_ATTACK = 0.35
BAND_RELEASE = 0.18
LOUDNESS_ATTACK = 0.30
LOUDNESS_RELEASE = 0.12
BRIGHTNESS_ATTACK = 0.25
BRIGHTNESS_RELEASE = 0.10
ROUGHNESS_ATTACK = 0.25
ROUGHNESS_RELEASE = 0.12

BG_GLOOM = (8.0, 12.0, 18.0)
BG_COOL = (18.0, 42.0, 76.0)
BG_WARM = (54.0, 24.0, 12.0)
FLASH_COOL = (64.0, 180.0, 255.0)
FLASH_WARM = (255.0, 156.0, 48.0)
SHAPE_COOL = (90.0, 220.0, 255.0)
SHAPE_WARM = (255.0, 190.0, 88.0)
SHAPE_COOL_HI = (170.0, 255.0, 255.0)
SHAPE_WARM_HI = (255.0, 228.0, 132.0)


@dataclass
class AudioFeatures:
    bass: float = 0.0
    mid: float = 0.0
    treble: float = 0.0
    loudness: float = 0.0
    brightness: float = 0.0
    roughness: float = 0.0


@dataclass
class AudioState:
    bass: float = 0.0
    mid: float = 0.0
    treble: float = 0.0
    level: float = 0.0
    spectral: float = 0.0
    noise: float = 0.0
    beat_pulse: float = 0.0
    tempo: float = 0.0
    motion_phase: float = 0.0


sock = None
energy_history = deque(maxlen=ENERGY_HISTORY)
audio_state = AudioState()
last_beat_time = None
last_callback_time = None


def set_rate(sample_rate_hz):
    global SAMPLE_RATE, BASS_BINS, MID_BINS, TREBLE_BINS, FFT_FREQS
    SAMPLE_RATE = int(sample_rate_hz)

    def bins(lo_hi):
        lo = max(1, round(lo_hi[0] * BLOCK_SIZE / sample_rate_hz))
        hi = max(lo + 1, round(lo_hi[1] * BLOCK_SIZE / sample_rate_hz))
        return (lo, hi)

    BASS_BINS = bins(BASS_HZ)
    MID_BINS = bins(MID_HZ)
    TREBLE_BINS = bins(TREBLE_HZ)
    FFT_FREQS = np.fft.rfftfreq(BLOCK_SIZE, d=1.0 / sample_rate_hz)


def clamp01(value):
    return max(0.0, min(float(value), 1.0))


def clamp_byte(value):
    return max(0, min(int(value), 255))


def rgb_u32(red, green, blue):
    return (clamp_byte(red) << 16) | (clamp_byte(green) << 8) | clamp_byte(blue)


def blend_rgb(low, high, mix):
    mix = clamp01(mix)
    return tuple((1.0 - mix) * lo + mix * hi for lo, hi in zip(low, high))


def scale_rgb(rgb, scale):
    return tuple(scale * channel for channel in rgb)


def add_rgb(*rgbs):
    out = [0.0, 0.0, 0.0]
    for rgb in rgbs:
        for index, channel in enumerate(rgb):
            out[index] += channel
    return tuple(out)


def smooth_follow(previous, value, attack, release):
    alpha = attack if value > previous else release
    return clamp01(previous + alpha * (value - previous))


def band_ratio(fft_mag, bins, total):
    return float(np.sum(fft_mag[bins[0]:bins[1]])) / total


def debug_bar(value, width=12):
    return ("#" * int(clamp01(value) * width)).ljust(width)


def mix_audio_samples(indata):
    audio_samples = indata.mean(axis=1)
    if np.abs(audio_samples).max() > 2.0:
        audio_samples = audio_samples / 32768.0
    return audio_samples


def extract_audio_features(audio_samples):
    fft_mag = np.abs(np.fft.rfft(audio_samples))
    total = float(np.sum(fft_mag))
    loudness = clamp01(np.sqrt(np.mean(audio_samples ** 2)))

    if total < SILENCE_GATE:
        energy_history.clear()
        return AudioFeatures(), 0.0

    features = AudioFeatures(
        bass=band_ratio(fft_mag, BASS_BINS, total),
        mid=band_ratio(fft_mag, MID_BINS, total),
        treble=band_ratio(fft_mag, TREBLE_BINS, total),
        loudness=loudness,
        brightness=clamp01(np.sum(FFT_FREQS * fft_mag) / ((np.sum(fft_mag) + 1e-6) * MAX_BRIGHTNESS_HZ)),
        roughness=clamp01(np.mean(np.abs(np.diff(np.sign(audio_samples)))) / 2.0),
    )

    frame_energy = float(np.mean(fft_mag ** 2))
    average_energy = frame_energy if not energy_history else float(np.mean(energy_history))
    beat_trigger = 1.0 if frame_energy > BEAT_THRESHOLD * average_energy else 0.0
    energy_history.append(frame_energy)

    return features, beat_trigger


def update_audio_state(features, beat_trigger):
    global last_beat_time, last_callback_time

    now = time.monotonic()
    default_dt = BLOCK_SIZE / SAMPLE_RATE
    dt = default_dt if last_callback_time is None else max(now - last_callback_time, 1e-3)
    last_callback_time = now

    audio_state.bass = smooth_follow(audio_state.bass, features.bass, BAND_ATTACK, BAND_RELEASE)
    audio_state.mid = smooth_follow(audio_state.mid, features.mid, BAND_ATTACK, BAND_RELEASE)
    audio_state.treble = smooth_follow(audio_state.treble, features.treble, BAND_ATTACK, BAND_RELEASE)
    audio_state.level = smooth_follow(
        audio_state.level, features.loudness, LOUDNESS_ATTACK, LOUDNESS_RELEASE
    )
    audio_state.spectral = smooth_follow(
        audio_state.spectral, features.brightness, BRIGHTNESS_ATTACK, BRIGHTNESS_RELEASE
    )
    audio_state.noise = smooth_follow(
        audio_state.noise, features.roughness, ROUGHNESS_ATTACK, ROUGHNESS_RELEASE
    )

    beat_onset = False
    if beat_trigger:
        if last_beat_time is None or (now - last_beat_time) >= MIN_BEAT_INTERVAL_S:
            beat_onset = True
            if last_beat_time is not None:
                bpm = clamp01((60.0 / (now - last_beat_time) - MIN_BPM) / (MAX_BPM - MIN_BPM))
                audio_state.tempo = smooth_follow(audio_state.tempo, bpm, TEMPO_ATTACK, TEMPO_RELEASE)
            last_beat_time = now

    if beat_onset:
        audio_state.beat_pulse = 1.0
    else:
        audio_state.beat_pulse *= BEAT_DECAY

    motion_hz = MIN_MOTION_HZ + (MAX_MOTION_HZ - MIN_MOTION_HZ) * (
        0.75 * audio_state.tempo + 0.25 * audio_state.level
    )
    audio_state.motion_phase = (audio_state.motion_phase + (2.0 * math.pi * motion_hz * dt)) % (2.0 * math.pi)


def build_scene_values():
    mood_warm = clamp01(
        0.55 * audio_state.bass +
        0.35 * audio_state.level +
        0.30 * audio_state.noise +
        0.20 * audio_state.tempo -
        0.20 * audio_state.spectral
    )
    mood_cool = clamp01(
        0.55 * audio_state.spectral +
        0.25 * audio_state.mid +
        0.20 * (1.0 - audio_state.noise) +
        0.20 * (1.0 - audio_state.tempo)
    )
    mood_mix = clamp01(0.5 + 0.5 * (mood_warm - mood_cool))

    shape_lfo = 0.5 + 0.5 * math.sin(audio_state.motion_phase)
    extra_lfo = 0.5 + 0.5 * math.sin(audio_state.motion_phase + 1.7)

    shape_size = clamp01(
        SHAPE_SIZE_BASE +
        SHAPE_SIZE_LEVEL_GAIN * audio_state.level +
        SHAPE_SIZE_BASS_GAIN * audio_state.bass +
        SHAPE_SIZE_PULSE_GAIN * audio_state.beat_pulse +
        SHAPE_SIZE_LFO_GAIN * audio_state.tempo * shape_lfo
    )
    shape_extra = clamp01(
        SHAPE_EXTRA_BASE +
        SHAPE_EXTRA_TREBLE_GAIN * audio_state.treble +
        SHAPE_EXTRA_NOISE_GAIN * audio_state.noise +
        SHAPE_EXTRA_PULSE_GAIN * audio_state.beat_pulse +
        SHAPE_EXTRA_LFO_GAIN * extra_lfo
    )

    bg_base = blend_rgb(BG_COOL, BG_WARM, mood_mix)
    bg_base = blend_rgb(BG_GLOOM, bg_base, 0.25 + 0.45 * audio_state.spectral + 0.20 * audio_state.level)
    bg_flash = blend_rgb(FLASH_COOL, FLASH_WARM, mood_mix)
    bg_rgb = rgb_u32(
        *add_rgb(
            scale_rgb(bg_base, 1.0),
            scale_rgb(bg_flash, 0.70 * audio_state.beat_pulse),
        )
    )

    shape_base = blend_rgb(SHAPE_COOL, SHAPE_WARM, mood_mix)
    shape_highlight = blend_rgb(SHAPE_COOL_HI, SHAPE_WARM_HI, mood_mix)
    shape_rgb = rgb_u32(
        *add_rgb(
            scale_rgb(shape_base, 0.45 + 0.45 * audio_state.level + 0.15 * audio_state.spectral),
            scale_rgb(shape_highlight, 0.20 + 0.60 * audio_state.beat_pulse),
        )
    )

    return (
        CELL_SZ,
        HALF_CELL,
        shape_size,
        shape_extra,
        bg_rgb,
        shape_rgb,
        audio_state.beat_pulse,
        audio_state.level,
        audio_state.spectral,
        audio_state.noise,
    )


set_rate(SAMPLE_RATE)


def audio_callback(indata, frames, time_info, status):
    audio_samples = mix_audio_samples(indata)
    features, beat_trigger = extract_audio_features(audio_samples)
    update_audio_state(features, beat_trigger)
    scene_values = build_scene_values()

    if DEBUG and not hasattr(audio_callback, "_n"):
        audio_callback._n = 0
    if DEBUG:
        audio_callback._n += 1
        if audio_callback._n % DEBUG_EVERY == 0:
            print(
                f"\rbass[{debug_bar(audio_state.bass)}] mid[{debug_bar(audio_state.mid)}] "
                f"treb[{debug_bar(audio_state.treble)}] lvl[{debug_bar(audio_state.level)}] "
                f"spec[{debug_bar(audio_state.spectral)}] noise[{debug_bar(audio_state.noise)}] "
                f"tempo[{debug_bar(audio_state.tempo)}] pulse[{debug_bar(audio_state.beat_pulse)}] "
                f"trig:{'X' if beat_trigger else '.'}  ",
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
