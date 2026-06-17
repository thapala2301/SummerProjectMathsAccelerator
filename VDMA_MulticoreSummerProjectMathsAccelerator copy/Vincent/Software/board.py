'''
SCRIPT FOR PYNQ BOARD: OVERLAY + IMU TO DETERMINE LOOKAT MATRIX
Gets IMU values, computes lookat from this
Also gets audio data from computer via TCP
BTN1 (AXI GPIO 0x41210000 bit 0) returns to UI selector
'''
import socket
import struct
import threading
import time
import numpy as np
from pynq import Overlay, MMIO

AXI_BASE_ADDR = 0x43C00000
AXI_SPAN      = 0x1000

BTN_BASE_ADDR = 0x41210000
BTN_SPAN      = 0x1000

def _has_btn_gpio(overlay, addr):
    for ip in overlay.ip_dict.values():
        if ip.get('phys_addr') == addr:
            return True
    return False

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
    print("waiting for audio connection...")
    conn, addr = server.accept()
    print("tcp connected:", addr)
    while True:
        try:
            data = conn.recv(44)
            if len(data) != 44:
                continue
            values = struct.unpack("11f", data)
            for i, v in enumerate(values):
                mmio.write((9 + i) * 4, fp32_to_fp27(v))
        except (ConnectionResetError, BrokenPipeError):
            print("audio connection lost")
            break

def imu_thread(mmio):
    # placeholder — Jai handles IMU GPIO
    defaults = [1.0, 0.0,  0.0,
                0.0, 1.0,  0.0,
                0.0, 0.0, -1.0]
    for i, v in enumerate(defaults):
        mmio.write(i * 4, fp32_to_fp27(v))

stop_event = threading.Event()

def btn_thread(btn_mmio):
    while not stop_event.is_set():
        if btn_mmio.read(0x0) & 0x1:   # BTN1 — back to UI
            stop_event.set()
            return
        time.sleep(0.05)

def run(music_on=True, overlay=None):
    mmio = MMIO(AXI_BASE_ADDR, AXI_SPAN)
    write_default_camera(mmio)
    if overlay is not None and _has_btn_gpio(overlay, BTN_BASE_ADDR):
        btn_mmio = MMIO(BTN_BASE_ADDR, BTN_SPAN)
        tb = threading.Thread(target=btn_thread, args=(btn_mmio,), daemon=True)
        tb.start()
    else:
        print("No button GPIO in this bitstream — press Ctrl+C to return to UI")
    if music_on:
        t = threading.Thread(target=tcp_thread, args=(mmio,), daemon=True)
        t.start()
    imu_thread(mmio)
    stop_event.wait()       # blocks until BTN1 pressed (btn_thread sets it)
    stop_event.clear()

if __name__ == "__main__":
    ol = Overlay("Bitstream_Handoff/scaffold.bit")
    run(music_on=True)
