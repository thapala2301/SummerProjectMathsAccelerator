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


PYNQ_IP = "192.168.137.243"
PYNQ_PORT = 9998
SAMPLE_RATE = 44100
BLOCK_SIZE = 1024

BASS_HZ = (43, 215)
MID_HZ = (215, 2000)
TREBLE_HZ = (2000, 8000)
MAX_BRIGHTNESS_HZ = 8000.0

CELL_SZ_DEFAULT = 10.0
CELL_SZ_EXPAND_SPAN = 10.0
HALF_CELL_DEFAULT = 0.5 * CELL_SZ_DEFAULT

SHAPE_SIZE_MIN = 3.6
SHAPE_SIZE_MAX = 4.95
SHAPE_EXTRA_MIN = 0.12
SHAPE_EXTRA_MAX = 0.34
GENERIC_SHAPE_SIZE_MIN = 3.8
GENERIC_SHAPE_SIZE_SPAN = 1.2
GENERIC_SHAPE_EXTRA_MIN = 0.10
GENERIC_SHAPE_EXTRA_SPAN = 0.22

MIN_MOTION_HZ = 0.05
MAX_MOTION_HZ = 1.20
MIN_BEAT_INTERVAL_S = 0.22
MIN_BPM = 60.0
MAX_BPM = 180.0
TEMPO_ATTACK = 0.25
TEMPO_RELEASE = 0.08
TEMPO_IDLE_DECAY = 0.02
SILENCE_GATE = 0.3
ENERGY_HISTORY = 20
BEAT_THRESHOLD = 1.5
BEAT_DECAY_SLOW = 0.992
BEAT_DECAY_FAST = 0.94
MIN_BEAT_LEVEL = 0.12
MOOD_ATTACK = 0.08
MOOD_RELEASE = 0.02
COLOR_PHASE_MIN_HZ = 0.015
COLOR_PHASE_MAX_HZ = 0.16

CELL_PULSE_BEAT_DIVIDER = 2
CELL_PULSE_MIN_INTERVAL_S = 0.55
CELL_PULSE_MIN_STRENGTH = 0.42
CELL_PULSE_STRONG_STRENGTH = 0.72
CELL_PULSE_ATTACK_MIN = 0.06
CELL_PULSE_ATTACK_MAX = 0.24
CELL_PULSE_DECAY_WEAK = 0.965
CELL_PULSE_DECAY_STRONG = 0.985
CELL_PULSE_IDLE_DAMP = 0.92

INPUT_FLOOR_ATTACK = 0.35
INPUT_FLOOR_RELEASE = 0.003
INPUT_PEAK_ATTACK = 0.60
INPUT_PEAK_RELEASE = 0.01
INPUT_FLOOR_BOOTSTRAP = 0.35
INPUT_PEAK_BOOTSTRAP = 1.25
MIN_SIGNAL_RANGE = 0.0015
MIN_SIGNAL_LEVEL = 0.0002
SIGNAL_PRESENT_FRACTION = 0.08

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
BG_MYSTIC = (28.0, 20.0, 46.0)
BG_WARM = (54.0, 24.0, 12.0)
BG_HELL = (84.0, 20.0, 8.0)
FLASH_COOL = (64.0, 180.0, 255.0)
FLASH_MYSTIC = (156.0, 118.0, 255.0)
FLASH_WARM = (255.0, 156.0, 48.0)
FLASH_HELL = (255.0, 72.0, 16.0)
SHAPE_COOL = (90.0, 220.0, 255.0)
SHAPE_MYSTIC = (176.0, 132.0, 255.0)
SHAPE_WARM = (255.0, 190.0, 88.0)
SHAPE_HELL = (255.0, 92.0, 36.0)
SHAPE_COOL_HI = (170.0, 255.0, 255.0)
SHAPE_MYSTIC_HI = (224.0, 202.0, 255.0)
SHAPE_WARM_HI = (255.0, 228.0, 132.0)
SHAPE_HELL_HI = (255.0, 168.0, 72.0)


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
    mood_energy: float = 0.0
    mood_brightness: float = 0.0
    mood_noise: float = 0.0
    motion_phase: float = 0.0
    color_phase: float = 0.0
    cell_expand: float = 0.0
    cell_drive: float = 0.0
    cell_attack: float = CELL_PULSE_ATTACK_MIN
    cell_decay: float = CELL_PULSE_DECAY_WEAK
    cell_beat_count: int = 0
    cell_pulse_cooldown: float = 0.0


sock = None
energy_history = deque(maxlen=ENERGY_HISTORY)
audio_state = AudioState()
last_beat_time = None
last_callback_time = None
input_floor = 0.0
input_peak = 0.0


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


def generic_shape_size(shape_size):
    return clamp01((shape_size - GENERIC_SHAPE_SIZE_MIN) / GENERIC_SHAPE_SIZE_SPAN)


def generic_shape_extra(shape_extra):
    return clamp01((shape_extra - GENERIC_SHAPE_EXTRA_MIN) / GENERIC_SHAPE_EXTRA_SPAN)


def normalize_loudness(raw_loudness):
    global input_floor, input_peak

    if input_floor == 0.0:
        input_floor = raw_loudness * INPUT_FLOOR_BOOTSTRAP
    else:
        alpha = INPUT_FLOOR_ATTACK if raw_loudness < input_floor else INPUT_FLOOR_RELEASE
        input_floor += alpha * (raw_loudness - input_floor)

    if input_peak == 0.0:
        input_peak = max(raw_loudness, input_floor * INPUT_PEAK_BOOTSTRAP)
    else:
        alpha = INPUT_PEAK_ATTACK if raw_loudness > input_peak else INPUT_PEAK_RELEASE
        input_peak += alpha * (raw_loudness - input_peak)
        input_peak = max(input_peak, input_floor + MIN_SIGNAL_RANGE)

    signal_range = max(input_peak - input_floor, MIN_SIGNAL_RANGE)
    normalized_level = clamp01((raw_loudness - input_floor) / signal_range)
    signal_present = raw_loudness > max(
        MIN_SIGNAL_LEVEL,
        input_floor + SIGNAL_PRESENT_FRACTION * signal_range,
    )

    return normalized_level, signal_present


def extract_audio_features(audio_samples):
    fft_mag = np.abs(np.fft.rfft(audio_samples))
    total = float(np.sum(fft_mag))
    raw_loudness = float(np.sqrt(np.mean(audio_samples ** 2)))
    loudness, signal_present = normalize_loudness(raw_loudness)

    if total < 1e-6 or not signal_present:
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
    beat_trigger = 1.0 if loudness >= MIN_BEAT_LEVEL and frame_energy > BEAT_THRESHOLD * average_energy else 0.0
    energy_history.append(frame_energy)

    return features, beat_trigger


def beat_strength(features):
    return clamp01(
        0.38 * features.loudness +
        0.28 * features.bass +
        0.20 * audio_state.tempo +
        0.14 * features.brightness
    )


def update_cell_spacing(dt, beat_onset, strength):
    audio_state.cell_pulse_cooldown = max(0.0, audio_state.cell_pulse_cooldown - dt)

    if beat_onset:
        audio_state.cell_beat_count += 1

        should_expand = (
            audio_state.cell_pulse_cooldown <= 0.0 and
            (
                strength >= CELL_PULSE_STRONG_STRENGTH or
                (
                    audio_state.cell_beat_count >= CELL_PULSE_BEAT_DIVIDER and
                    strength >= CELL_PULSE_MIN_STRENGTH
                )
            )
        )

        if should_expand:
            audio_state.cell_beat_count = 0
            audio_state.cell_drive = max(
                audio_state.cell_drive,
                0.10 + 0.90 * strength
            )
            audio_state.cell_attack = (
                CELL_PULSE_ATTACK_MIN +
                (CELL_PULSE_ATTACK_MAX - CELL_PULSE_ATTACK_MIN) * strength
            )
            audio_state.cell_decay = (
                CELL_PULSE_DECAY_WEAK +
                (CELL_PULSE_DECAY_STRONG - CELL_PULSE_DECAY_WEAK) * strength
            )
            audio_state.cell_pulse_cooldown = CELL_PULSE_MIN_INTERVAL_S * (1.0 - 0.35 * strength)

    audio_state.cell_expand += audio_state.cell_attack * (audio_state.cell_drive - audio_state.cell_expand)
    audio_state.cell_drive *= audio_state.cell_decay

    if audio_state.level < 0.05:
        audio_state.cell_drive *= CELL_PULSE_IDLE_DAMP


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
    trigger_strength = 0.0
    if beat_trigger:
        if last_beat_time is None or (now - last_beat_time) >= MIN_BEAT_INTERVAL_S:
            beat_onset = True
            trigger_strength = beat_strength(features)
            if last_beat_time is not None:
                bpm = clamp01((60.0 / (now - last_beat_time) - MIN_BPM) / (MAX_BPM - MIN_BPM))
                audio_state.tempo = smooth_follow(audio_state.tempo, bpm, TEMPO_ATTACK, TEMPO_RELEASE)
            last_beat_time = now

    if beat_onset:
        audio_state.beat_pulse = 1.0
    else:
        pulse_speed = clamp01(
            0.65 * audio_state.tempo +
            0.20 * audio_state.treble +
            0.15 * audio_state.level
        )
        beat_decay = BEAT_DECAY_SLOW - (BEAT_DECAY_SLOW - BEAT_DECAY_FAST) * pulse_speed
        audio_state.beat_pulse *= beat_decay

    if audio_state.level < 0.05:
        audio_state.beat_pulse *= 0.75

    if last_beat_time is None or (now - last_beat_time) > 1.5:
        audio_state.tempo = max(0.0, audio_state.tempo - TEMPO_IDLE_DECAY * dt)

    instant_energy = clamp01(
        0.40 * audio_state.level +
        0.25 * audio_state.bass +
        0.20 * audio_state.tempo +
        0.15 * audio_state.beat_pulse
    )
    instant_brightness = clamp01(
        0.60 * audio_state.spectral +
        0.40 * audio_state.treble
    )
    instant_noise = clamp01(
        0.60 * audio_state.noise +
        0.20 * audio_state.bass +
        0.20 * audio_state.tempo
    )

    audio_state.mood_energy = smooth_follow(
        audio_state.mood_energy, instant_energy, MOOD_ATTACK, MOOD_RELEASE
    )
    audio_state.mood_brightness = smooth_follow(
        audio_state.mood_brightness, instant_brightness, MOOD_ATTACK, MOOD_RELEASE
    )
    audio_state.mood_noise = smooth_follow(
        audio_state.mood_noise, instant_noise, MOOD_ATTACK, MOOD_RELEASE
    )

    motion_drive = clamp01(
        0.70 * audio_state.tempo +
        0.20 * audio_state.treble +
        0.10 * audio_state.level
    )
    motion_hz = MIN_MOTION_HZ + (MAX_MOTION_HZ - MIN_MOTION_HZ) * motion_drive
    audio_state.motion_phase = (audio_state.motion_phase + (2.0 * math.pi * motion_hz * dt)) % (2.0 * math.pi)

    color_drive = clamp01(
        0.45 * audio_state.tempo +
        0.30 * audio_state.mood_brightness +
        0.25 * (1.0 - audio_state.mood_noise)
    )
    color_hz = COLOR_PHASE_MIN_HZ + (COLOR_PHASE_MAX_HZ - COLOR_PHASE_MIN_HZ) * color_drive
    audio_state.color_phase = (audio_state.color_phase + (2.0 * math.pi * color_hz * dt)) % (2.0 * math.pi)

    update_cell_spacing(dt, beat_onset, trigger_strength)


def build_scene_values():
    cell_sz = CELL_SZ_DEFAULT + CELL_SZ_EXPAND_SPAN * clamp01(audio_state.cell_expand)
    half_cell = 0.5 * cell_sz

    shape_size_mix = clamp01(
        0.32 +
        0.22 * audio_state.level +
        0.18 * audio_state.bass +
        0.20 * audio_state.beat_pulse +
        0.18 * audio_state.tempo * (0.5 + 0.5 * math.sin(audio_state.motion_phase))
    )
    shape_extra_mix = clamp01(
        0.18 +
        0.22 * audio_state.treble +
        0.18 * audio_state.noise +
        0.16 * audio_state.beat_pulse +
        0.12 * (0.5 + 0.5 * math.sin(audio_state.motion_phase + 1.7))
    )

    shape_size = SHAPE_SIZE_MIN + (SHAPE_SIZE_MAX - SHAPE_SIZE_MIN) * shape_size_mix
    shape_extra = SHAPE_EXTRA_MIN + (SHAPE_EXTRA_MAX - SHAPE_EXTRA_MIN) * shape_extra_mix

    instant_energy = clamp01(
        0.40 * audio_state.level +
        0.25 * audio_state.bass +
        0.20 * audio_state.tempo +
        0.15 * audio_state.beat_pulse
    )
    section_lift = clamp01(
        0.5 +
        1.6 * (instant_energy - audio_state.mood_energy) +
        0.8 * (audio_state.spectral - audio_state.mood_brightness)
    )
    music_energy = clamp01(
        0.72 * audio_state.mood_energy +
        0.18 * audio_state.beat_pulse +
        0.10 * audio_state.tempo
    )
    music_liveliness = clamp01(
        0.55 * audio_state.tempo +
        0.20 * audio_state.treble +
        0.15 * audio_state.beat_pulse +
        0.10 * section_lift
    )
    cool_bias = clamp01(
        (1.0 - music_energy) * (0.45 + 0.55 * audio_state.mood_brightness)
    )
    mystic_bias = clamp01(
        (1.0 - music_energy) * (0.15 + 0.85 * audio_state.mood_brightness)
    )
    warm_bias = clamp01(
        music_energy * (0.35 + 0.65 * audio_state.bass)
    )
    aggression = clamp01(
        music_energy * (
            0.30 * audio_state.mood_noise +
            0.35 * audio_state.bass +
            0.35 * audio_state.tempo
        )
    )
    palette_mix = clamp01(
        0.55 * music_energy +
        0.30 * section_lift +
        0.15 * audio_state.beat_pulse
    )
    palette_brightness = clamp01(
        0.12 +
        0.28 * audio_state.mood_energy +
        0.20 * audio_state.mood_brightness +
        0.28 * audio_state.beat_pulse +
        0.12 * section_lift
    )
    shade_wave = 0.5 + 0.5 * math.sin(audio_state.color_phase)
    shade_wave_offset = 0.5 + 0.5 * math.sin(audio_state.color_phase + 2.1)

    bg_cool = blend_rgb(BG_COOL, BG_MYSTIC, clamp01(0.25 + 0.75 * mystic_bias * shade_wave))
    bg_cool = blend_rgb(BG_GLOOM, bg_cool, 0.18 + 0.30 * cool_bias + 0.10 * shade_wave_offset)
    bg_warm = blend_rgb(BG_WARM, BG_HELL, clamp01(0.20 + 0.80 * aggression * shade_wave_offset))
    bg_base = blend_rgb(bg_cool, bg_warm, palette_mix)
    bg_ambient = blend_rgb(BG_GLOOM, bg_base, 0.18 + 0.36 * palette_brightness)

    bg_flash = blend_rgb(FLASH_COOL, FLASH_MYSTIC, clamp01(0.25 + 0.75 * mystic_bias * shade_wave_offset))
    bg_flash = blend_rgb(bg_flash, FLASH_WARM, warm_bias)
    bg_flash = blend_rgb(bg_flash, FLASH_HELL, aggression)
    bg_rgb = rgb_u32(
        *add_rgb(
            scale_rgb(bg_ambient, 1.0),
            scale_rgb(bg_flash, 0.08 + 0.42 * section_lift + 0.55 * audio_state.beat_pulse),
        )
    )

    shape_cool = blend_rgb(SHAPE_COOL, SHAPE_MYSTIC, clamp01(0.25 + 0.75 * mystic_bias * shade_wave))
    shape_warm = blend_rgb(SHAPE_WARM, SHAPE_HELL, clamp01(0.25 + 0.75 * aggression * shade_wave_offset))
    shape_base = blend_rgb(shape_cool, shape_warm, palette_mix)
    shape_highlight = blend_rgb(SHAPE_COOL_HI, SHAPE_MYSTIC_HI, clamp01(0.30 + 0.70 * mystic_bias * shade_wave_offset))
    shape_highlight = blend_rgb(shape_highlight, SHAPE_WARM_HI, warm_bias)
    shape_highlight = blend_rgb(shape_highlight, SHAPE_HELL_HI, aggression)
    shape_rgb = rgb_u32(
        *add_rgb(
            scale_rgb(shape_base, 0.24 + 0.32 * palette_brightness + 0.12 * shade_wave),
            scale_rgb(shape_highlight, 0.16 + 0.52 * audio_state.beat_pulse + 0.22 * music_liveliness + 0.14 * section_lift),
        )
    )

    return (
        cell_sz,
        half_cell,
        generic_shape_size(shape_size),
        generic_shape_extra(shape_extra),
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
                f"cell[{debug_bar(audio_state.cell_expand)}] "
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