'''
THIS SCRIPT IS ONLY FOR AUDIO: AUDIO DETERMINES CAMERA POSITION AND SDF_PARAMS
Captures audio from mic/USB adapter
Computes FFT + all features: 8 sdf_params
Applies scaling to get final scene values
Sends 11 floats to PYNQ via TCP port 9998

HOW TO RUN (this script runs on the PC, board.py runs on the PYNQ Z1):

1. Set PYNQ_IP below to your board's IP address.

2. Install dependencies (Windows: use `py` if `python`/`pip` aren't on PATH):
       py -m pip install sounddevice numpy

3. Start board.py on the PYNQ first (see its header), wait for
   "waiting for audio connection...", then run:
       py audio_sender.py --debug

   --debug shows a live bar meter of all features (bass/mid/treb/rms/
   cent/zcr/beat) — use it to tune the constants below. The bars show the
   exact values being sent. Omit the flag for a quiet run.

4. Make noise / play music near the mic and watch the values move.
   Connection drops are reconnected automatically. Ctrl+C to stop.

AUDIO INPUT SELECTION:

RECOMMENDED — LOOPBACK (play music on this PC, capture it digitally):
   1. Plug the audience headphones/speakers into the laptop's own 3.5mm
      jack (the Realtek output) and make it the default output device.
      Unplug any USB audio adapter so it can't steal the default.
   2. Play songs with any player on this PC.
   3. Run:  py audio_sender.py --device "Stereo Mix"
   "Stereo Mix" is the Realtek loopback: it records exactly what the PC
   plays — no adapter, no cables, no analog noise. Note its level scales
   with the Windows output volume.

ALTERNATIVE — external source via mic/line input:
   py audio_sender.py --list-devices        <- find the input's index
   py audio_sender.py --device 5 ...        <- use it (index or name substring)
   Beware: mono "Microphone" endpoints of cheap USB adapters often read the
   wrong contact of a stereo plug and deliver silence (this cost us an
   afternoon). Verify with probe_inputs.py — it records 2s from every
   endpoint and prints peak levels.

NOTE: bass/mid/treble/rms scale with absolute mic volume (close speech
saturates them; quiet room music barely moves them), while cent is
volume-independent. Tune ALPHA / the divisors below to your setup.
'''
import http.server
import json
import os
import socket
import struct
import sys
import time
import numpy as np
import sounddevice as sd
import threading
import math

DEBUG    = "--debug" in sys.argv
NO_BOARD = "--no-board" in sys.argv   # tune with the visualizer only, no PYNQ needed
VIS_PORT = 8000

def arg_value(flag):
    if flag in sys.argv:
        i = sys.argv.index(flag)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return None

latest = {}   # most recent features + scene values, served to the visualizer

PYNQ_IP     = "192.168.2.99"
PYNQ_PORT   = 9998
SAMPLE_RATE = 44100   # replaced by the input device's native rate at startup
BLOCK_SIZE  = 1024

# Band edges in Hz (converted to FFT bins once the device rate is known)
BASS_HZ   = (43,   215)
MID_HZ    = (215,  2000)
TREBLE_HZ = (2000, 8000)

def set_rate(fs):
    global SAMPLE_RATE, BASS_BINS, MID_BINS, TREBLE_BINS
    SAMPLE_RATE = int(fs)
    def bins(lo_hi):
        lo = max(1, round(lo_hi[0] * BLOCK_SIZE / fs))
        hi = max(lo + 1, round(lo_hi[1] * BLOCK_SIZE / fs))
        return (lo, hi)
    BASS_BINS, MID_BINS, TREBLE_BINS = bins(BASS_HZ), bins(MID_HZ), bins(TREBLE_HZ)

set_rate(SAMPLE_RATE)

BASE_CELL_SZ = 10.0; CELL_SZ_SCALE = 4.0
BASE_B_FP    = 4.5;  B_FP_SCALE    = 1.5
BASE_E_FP    = 0.15; E_FP_SCALE    = 0.1
ALPHA = 0.3
SILENCE_GATE = 0.3   # total |FFT| below this counts as silence (all ratio
                     # features -> 0). Raise if room noise keeps bars alive;
                     # lower if quiet music gets gated out. If rms barely
                     # moves while music plays, also raise the mic input
                     # level in Windows sound settings.

sock           = None
energy_history = []
smoothed_bass   = 0.0
smoothed_mid    = 0.0
smoothed_treble = 0.0
t = 0.0

def audio_callback(indata, frames, time, status):
    global smoothed_bass, smoothed_mid, smoothed_treble, t

    mono = indata.mean(axis=1)   # downmix stereo line-in; no-op for mono devices
    if np.abs(mono).max() > 2.0:   # some WDM-KS drivers deliver int16-scale floats
        mono = mono / 32768.0
    fft  = np.abs(np.fft.rfft(mono))

    # Bands as fractions of total spectrum energy: volume-independent,
    # naturally 0..1. All ratio features are gated to zero in near-silence —
    # the spectrum of mic noise is broadband, so ungated ratios (especially
    # the centroid) pin to garbage values when no music is playing.
    total  = float(np.sum(fft))
    silent = total < SILENCE_GATE
    if silent:
        bass = mid = treble = 0.0
    else:
        bass   = float(np.sum(fft[BASS_BINS[0]:BASS_BINS[1]]))     / total
        mid    = float(np.sum(fft[MID_BINS[0]:MID_BINS[1]]))       / total
        treble = float(np.sum(fft[TREBLE_BINS[0]:TREBLE_BINS[1]])) / total

    smoothed_bass   = min(ALPHA * bass   + (1 - ALPHA) * smoothed_bass,   1.0)
    smoothed_mid    = min(ALPHA * mid    + (1 - ALPHA) * smoothed_mid,    1.0)
    smoothed_treble = min(ALPHA * treble + (1 - ALPHA) * smoothed_treble, 1.0)

    rms = min(float(np.sqrt(np.mean(mono ** 2))), 1.0)

    if silent:
        centroid_norm = 0.0
        beat = 0.0
        zcr  = 0.0
    else:
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

    latest.update(bass=smoothed_bass, mid=smoothed_mid, treble=smoothed_treble,
                  rms=rms, cent=centroid_norm, beat=beat, zcr=zcr, values=values)

    if DEBUG and not hasattr(audio_callback, "_n"):
        audio_callback._n = 0
    if DEBUG:
        audio_callback._n += 1
        if audio_callback._n % 5 == 0:   # ~8 updates/sec
            def bar(x, w=12):
                return ("#" * int(min(max(x, 0.0), 1.0) * w)).ljust(w)
            print(f"\rbass[{bar(smoothed_bass)}] mid[{bar(smoothed_mid)}] "
                  f"treb[{bar(smoothed_treble)}] rms[{bar(rms)}] "
                  f"cent[{bar(centroid_norm)}] zcr[{bar(zcr)}] "
                  f"beat:{'X' if beat else '.'}  ", end="", flush=True)

    try:
        if sock:
            sock.sendall(struct.pack("11f", *values))
    except (BrokenPipeError, ConnectionResetError, OSError):
        globals()["sock"] = None   # main loop reconnects

def connect():
    while True:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect((PYNQ_IP, PYNQ_PORT))
            print("\nconnected to PYNQ")
            return s
        except OSError:
            print("\rconnecting to PYNQ...", end="", flush=True)
            time.sleep(1)

class VisHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/values":
            body, ctype = json.dumps(latest).encode(), "application/json"
        else:
            page = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "visualizer.html")
            with open(page, "rb") as f:
                body, ctype = f.read(), "text/html"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass   # keep the terminal free for the --debug meter

def start_visualizer():
    try:
        server = http.server.ThreadingHTTPServer(("127.0.0.1", VIS_PORT), VisHandler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        print(f"visualizer: http://localhost:{VIS_PORT}")
    except OSError:
        print(f"visualizer port {VIS_PORT} busy, skipping (close other senders)")

if __name__ == "__main__":
    if "--list-devices" in sys.argv:
        print(sd.query_devices())
        sys.exit(0)

    device = arg_value("--device")
    if device is not None and device.isdigit():
        device = int(device)
    info = sd.query_devices(device if device is not None else None, 'input')
    channels = 2 if info['max_input_channels'] >= 2 else 1
    set_rate(info['default_samplerate'])
    print(f"audio input: {info['name']} ({channels} ch @ {SAMPLE_RATE} Hz, "
          f"bins bass{BASS_BINS} mid{MID_BINS} treble{TREBLE_BINS})")

    start_visualizer()
    sock = None if NO_BOARD else connect()
    with sd.InputStream(device=device, samplerate=SAMPLE_RATE,
                        blocksize=BLOCK_SIZE,
                        channels=channels, dtype='float32',
                        callback=audio_callback):
        print("streaming audio, ctrl+c to stop")
        while True:
            if not NO_BOARD and sock is None:
                print("\nPYNQ connection lost, reconnecting...")
                sock = connect()
            time.sleep(0.5)
