'''
SCRIPT FOR PYNQ BOARD: VDMA + FRAME ACK + CAMERA TCP + AUDIO TCP (OPTIONAL)
Called by ui_base_selector.py via run(stop_event, music_on).
- music_on=True:  starts audio TCP server on port 9998
- music_on=False: audio server not started
- Camera TCP port 9999: keyboard/mouse controller on PC
- BTN1 (0x41210000 bit 0): returns to UI if present in bitstream
'''
import socket
import struct
import threading
import time

import numpy as np
from pynq import MMIO, allocate

CAMERA_REG_BASE = 0x43C00000
VDMA_BASE       = 0x43000000
GPIO_BASE       = 0x41200000
BTN_BASE_ADDR   = 0x41210000
SPAN            = 0x10000
BTN_SPAN        = 0x1000

WIDTH           = 1024
HEIGHT          = 600
STRIDE          = WIDTH * 4
HSIZE           = WIDTH * 4

CAMERA_PACKET_FORMAT = "<12f"
CAMERA_PACKET_BYTES  = struct.calcsize(CAMERA_PACKET_FORMAT)
CAMERA_TCP_PORT      = 9999

SCENE_PACKET_FORMAT = "<4f2I4f"
SCENE_PACKET_BYTES  = struct.calcsize(SCENE_PACKET_FORMAT)
AUDIO_TCP_PORT      = 9998

FRAME_BASE0_REG       = 12 * 4
FRAME_BASE1_REG       = 13 * 4
SCENE_CELL_SZ_REG     = 14 * 4
SCENE_HALF_CELL_REG   = 15 * 4
SCENE_SHAPE_SIZE_REG  = 16 * 4
SCENE_SHAPE_EXTRA_REG = 17 * 4
SCENE_BG_RGB_REG      = 18 * 4
SCENE_SHAPE_RGB_REG   = 19 * 4
SCENE_BEAT_PULSE_REG  = 20 * 4
SCENE_LEVEL_REG       = 21 * 4
SCENE_SPECTRAL_REG    = 22 * 4
SCENE_NOISE_REG       = 23 * 4

SCENE_FLOAT_REGS = (
    SCENE_CELL_SZ_REG, SCENE_HALF_CELL_REG,
    SCENE_SHAPE_SIZE_REG, SCENE_SHAPE_EXTRA_REG,
    SCENE_BEAT_PULSE_REG, SCENE_LEVEL_REG,
    SCENE_SPECTRAL_REG, SCENE_NOISE_REG,
)

MM2S_DMACR        = 0x00
MM2S_DMASR        = 0x04
MM2S_FRMSTORE     = 0x18
VDMA_PARK_PTR     = 0x28
MM2S_VSIZE        = 0x50
MM2S_HSIZE        = 0x54
MM2S_STRIDE       = 0x58
MM2S_START_ADDR_1 = 0x5C
MM2S_START_ADDR_2 = 0x60

GPIO_DATA  = 0x00
GPIO_TRI   = 0x04
GPIO2_DATA = 0x08
GPIO2_TRI  = 0x0C

DMACR_RUN_PARK    = 0x00000001
DMACR_RESET       = 0x00000004
FRAME_ACK_PULSE_S = 0.001

DEFAULT_CAMERA = [
    1.0, 0.0,  0.0,
    0.0, 1.0,  0.0,
    0.0, 0.0, -1.0,
    0.0, 0.15, 4.5,
]


def phys_addr(buffer):
    if hasattr(buffer, "physical_address"):
        return int(buffer.physical_address)
    return int(buffer.device_address)


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
        exponent = min(exponent + 1, 0xFF)
    return (sign << 26) | ((exponent & 0xFF) << 18) | fraction18


def write_camera_values(camera_regs, values):
    for i, v in enumerate(values):
        camera_regs.write(i * 4, fp32_to_fp27(v))


def write_scene_values(camera_regs, values):
    (cell_sz, half_cell, shape_size, shape_extra,
     bg_rgb, shape_rgb, beat_pulse, level, spectral, noise) = values
    for offset, value in zip(SCENE_FLOAT_REGS,
                             (cell_sz, half_cell, shape_size, shape_extra,
                              beat_pulse, level, spectral, noise)):
        camera_regs.write(offset, fp32_to_fp27(value))
    camera_regs.write(SCENE_BG_RGB_REG,    int(bg_rgb)    & 0x00FFFFFF)
    camera_regs.write(SCENE_SHAPE_RGB_REG, int(shape_rgb) & 0x00FFFFFF)


def reset_vdma(vdma):
    vdma.write(MM2S_DMACR, 0)
    time.sleep(0.01)
    vdma.write(MM2S_DMACR, DMACR_RESET)
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        if (vdma.read(MM2S_DMACR) & DMACR_RESET) == 0:
            return
        time.sleep(0.001)
    raise RuntimeError("VDMA reset timed out")


def set_display_bank(vdma, bank):
    bank &= 1
    vdma.write(VDMA_PARK_PTR, bank | (bank << 8))


def init_vdma(vdma, frame0_addr, frame1_addr):
    reset_vdma(vdma)
    vdma.write(MM2S_DMASR, 0xFFFFFFFF)
    vdma.write(MM2S_FRMSTORE, 2)
    vdma.write(MM2S_START_ADDR_1, frame0_addr)
    vdma.write(MM2S_START_ADDR_2, frame1_addr)
    vdma.write(MM2S_STRIDE, STRIDE)
    vdma.write(MM2S_HSIZE, HSIZE)
    set_display_bank(vdma, 0)
    vdma.write(MM2S_DMACR, DMACR_RUN_PARK)
    vdma.write(MM2S_VSIZE, HEIGHT)


def service_frame_ready(gpio, vdma, ack_state):
    now         = time.monotonic()
    status      = gpio.read(GPIO_DATA)
    ready_bank  = status & 1
    ready_valid = (status >> 1) & 1
    if ack_state["active"]:
        if now >= ack_state["release_at"]:
            gpio.write(GPIO2_DATA, 0)
            ack_state["active"] = False
        return
    if ready_valid:
        set_display_bank(vdma, ready_bank)
        gpio.write(GPIO2_DATA, 1)
        ack_state["active"]     = True
        ack_state["release_at"] = now + FRAME_ACK_PULSE_S


def recv_exact(conn, byte_count, on_timeout=None):
    data = bytearray()
    while len(data) < byte_count:
        try:
            chunk = conn.recv(byte_count - len(data))
        except socket.timeout:
            if on_timeout is not None:
                on_timeout()
            continue
        if not chunk:
            return None
        data.extend(chunk)
    return bytes(data)


def open_server(port, timeout=None):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", port))
    server.listen(1)
    if timeout is not None:
        server.settimeout(timeout)
    return server


def serve_audio(camera_regs, stop_event):
    server = open_server(AUDIO_TCP_PORT)
    server.settimeout(0.5)
    print(f"waiting for audio on port {AUDIO_TCP_PORT}", flush=True)
    while not stop_event.is_set():
        try:
            conn, addr = server.accept()
        except socket.timeout:
            continue
        print("audio connected:", addr, flush=True)
        with conn:
            while not stop_event.is_set():
                packet = recv_exact(conn, SCENE_PACKET_BYTES)
                if packet is None:
                    print("audio disconnected", flush=True)
                    break
                write_scene_values(camera_regs, struct.unpack(SCENE_PACKET_FORMAT, packet))
    server.close()


def btn_thread_fn(stop_event):
    # MMIO on a non-existent address causes SIGBUS — must check ip_dict first
    print("No button GPIO in SDF bitstream — Ctrl+C to return to UI", flush=True)
    stop_event.wait()


def run(stop_event=None, music_on=True, frame0=None, frame1=None):
    if stop_event is None:
        stop_event = threading.Event()

    camera_regs = MMIO(CAMERA_REG_BASE, SPAN)
    vdma        = MMIO(VDMA_BASE, SPAN)
    gpio        = MMIO(GPIO_BASE, SPAN)

    # use passed-in buffers if provided (avoids allocate() which fails on SDF overlays)
    owned = frame0 is None
    if owned:
        frame0 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
        frame1 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
        frame0[:] = 0
        frame1[:] = 0
    frame0_addr = phys_addr(frame0)
    frame1_addr = phys_addr(frame1)

    gpio.write(GPIO_TRI,   0xFFFFFFFF)
    gpio.write(GPIO2_TRI,  0x00000000)
    gpio.write(GPIO2_DATA, 0)

    write_camera_values(camera_regs, DEFAULT_CAMERA)
    camera_regs.write(FRAME_BASE0_REG, frame0_addr)
    camera_regs.write(FRAME_BASE1_REG, frame1_addr)
    init_vdma(vdma, frame0_addr, frame1_addr)

    threading.Thread(target=btn_thread_fn, args=(stop_event,), daemon=True).start()

    if music_on:
        print("music reactive: ON", flush=True)
        threading.Thread(target=serve_audio, args=(camera_regs, stop_event), daemon=True).start()
    else:
        print("music reactive: OFF", flush=True)

    ack_state = {"active": False, "release_at": 0.0}
    server = open_server(CAMERA_TCP_PORT, timeout=0.5)
    print(f"waiting for camera on port {CAMERA_TCP_PORT}", flush=True)

    try:
        while not stop_event.is_set():
            try:
                conn, addr = server.accept()
            except socket.timeout:
                service_frame_ready(gpio, vdma, ack_state)
                continue
            print("camera connected:", addr, flush=True)
            conn.settimeout(0.5)
            with conn:
                while not stop_event.is_set():
                    packet = recv_exact(
                        conn, CAMERA_PACKET_BYTES,
                        lambda: service_frame_ready(gpio, vdma, ack_state),
                    )
                    if packet is None:
                        print("camera disconnected", flush=True)
                        break
                    write_camera_values(camera_regs, struct.unpack(CAMERA_PACKET_FORMAT, packet))
                    service_frame_ready(gpio, vdma, ack_state)
    finally:
        server.close()
        if owned:
            frame0.freebuffer()
            frame1.freebuffer()


if __name__ == "__main__":
    run(music_on=True)