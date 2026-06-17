'''
SCRIPT FOR PYNQ BOARD: OVERLAY + IMU TO DETERMINE LOOKAT MATRIX
Gets IMU values, computes lookat from this
Also gets audio data from computer via TCP

HOW TO RUN (this script runs ON the PYNQ Z1, audio_sender.py runs on the PC):

1. Copy this file to the board (from the PC, adjust IP to your board's):
       scp board.py xilinx@192.168.137.49:/home/xilinx/

2a. SOFTWARE-ONLY TEST (no bitstream needed, safe — use this to verify the
    audio pipeline; received register writes are printed once per second):
       ssh xilinx@192.168.137.49        (password: xilinx)
       cd /home/xilinx
       python3 board.py --no-hw

2b. REAL HARDWARE RUN — requires Bitstream_Handoff/scaffold.bit, a bitstream
    containing an AXI register file at 0x43C00000 (PS7 + axi_camera_regs,
    20 registers). WARNING: do NOT run this with a bitstream that lacks the
    AXI slave (e.g. the standalone top.bit builds) — the first MMIO write
    will deadlock the ARM core and the board must be power cycled.
       sudo -i
       source /etc/profile.d/pynq_venv.sh
       cd /home/xilinx
       python3 board.py

3. Once "waiting for audio connection..." appears, start audio_sender.py on
   the PC. Reconnections are handled automatically; Enter stops the script.
'''
import socket
import struct
import sys
import threading
import time
import numpy as np

NO_HW = "--no-hw" in sys.argv

if not NO_HW:
    from pynq import Bitstream, MMIO

class DummyMMIO:
    '''Prints register writes instead of touching the AXI bus (sound test without bitstream).
       Snapshots once per second so the terminal stays readable.'''
    def __init__(self):
        self._regs = {}
        self._last_print = 0.0
    def write(self, offset, value):
        self._regs[offset // 4] = value
        now = time.time()
        if now - self._last_print >= 1.0:
            self._last_print = now
            print("  ".join(f"r{k}={v:07X}" for k, v in sorted(self._regs.items())))

AXI_BASE_ADDR = 0x43C00000
AXI_SPAN      = 0x1000

def fp32_to_fp27(value):
    bits       = struct.unpack(">I", struct.pack(">f", float(value)))[0]
    sign       = (bits >> 31) & 0x1
    exponent   = (bits >> 23) & 0xFF
    fraction23 = bits & 0x7FFFFF
    if exponent == 0:
        return sign << 26
    if exponent == 0xFF:
        return (sign << 26) | (exponent << 18) | (1 if fraction23 else 0)
    fraction18 = (fraction23 + 0x10) >> 5
    if fraction18 >= (1 << 18):
        fraction18 = 0
        exponent   = min(exponent + 1, 0xFF)
    return (sign << 26) | ((exponent & 0xFF) << 18) | fraction18

def write_default_camera(mmio):
    defaults = [
        1.0, 0.0,  0.0,   # right
        0.0, 1.0,  0.0,   # up
        0.0, 0.0, -1.0,   # forward
        0.0, 0.15, 4.5    # origin
    ]
    for i, v in enumerate(defaults):
        mmio.write(i * 4, fp32_to_fp27(v))

def tcp_thread(mmio):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", 9998))
    server.listen(1)
    while True:
        print("waiting for audio connection...")
        conn, addr = server.accept()
        print("tcp connected:", addr)
        while True:
            try:
                data = conn.recv(44, socket.MSG_WAITALL)
                if len(data) != 44:   # empty/short read = peer closed
                    break
                values = struct.unpack("11f", data)
                for i, v in enumerate(values):
                    mmio.write((9 + i) * 4, fp32_to_fp27(v))
            except (ConnectionResetError, BrokenPipeError):
                break
        print("audio connection lost")
        conn.close()

def imu_thread(mmio):
    # placeholder — Jai handles IMU GPIO
    defaults = [1.0, 0.0,  0.0,
                0.0, 1.0,  0.0,
                0.0, 0.0, -1.0]
    for i, v in enumerate(defaults):
        mmio.write(i * 4, fp32_to_fp27(v))

stop_event = threading.Event()

def run(music_on=True):
    mmio = DummyMMIO() if NO_HW else MMIO(AXI_BASE_ADDR, AXI_SPAN)
    write_default_camera(mmio)
    if music_on:
        t = threading.Thread(target=tcp_thread, args=(mmio,), daemon=True)
        t.start()
    imu_thread(mmio)
    input("Press Enter to stop...")
    stop_event.set()
    stop_event.clear()

if __name__ == "__main__":
    if not NO_HW:
        bs = Bitstream("Bitstream_Handoff/scaffold.bit")
        bs.download()
    run(music_on=True)
