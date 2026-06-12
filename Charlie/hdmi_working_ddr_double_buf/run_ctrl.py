#!/usr/bin/env python3

import builtins
import argparse
import socket
import struct
import time
from pathlib import Path

import numpy as np
from pynq import MMIO, Overlay, allocate


BITFILE = "/home/xilinx/jupyter_notebooks/ctrl/ctrl.bit"

CAMERA_REG_BASE = 0x43C00000
VDMA_BASE = 0x43000000
GPIO_BASE = 0x41200000
SPAN = 0x10000

WIDTH = 1024
HEIGHT = 600
BYTES_PER_PIXEL = 4
STRIDE = WIDTH * BYTES_PER_PIXEL
HSIZE = WIDTH * BYTES_PER_PIXEL

CAMERA_PACKET_BYTES = 48
TCP_PORT = 9999

FRAME_BASE0_REG = 12 * 4
FRAME_BASE1_REG = 13 * 4

MM2S_DMACR = 0x00
MM2S_DMASR = 0x04
MM2S_FRMSTORE = 0x18
VDMA_PARK_PTR = 0x28
MM2S_VSIZE = 0x50
MM2S_HSIZE = 0x54
MM2S_STRIDE = 0x58
MM2S_START_ADDR_1 = 0x5C
MM2S_START_ADDR_2 = 0x60

GPIO_DATA = 0x00
GPIO_TRI = 0x04
GPIO2_DATA = 0x08
GPIO2_TRI = 0x0C

DMACR_RUN_PARK = 0x00000001
DMACR_RESET = 0x00000004

STATE_NAME = "_ctrl_runtime_state"

DEFAULT_CAMERA = [
    1.0, 0.0, 0.0,
    0.0, 1.0, 0.0,
    0.0, 0.0, -1.0,
    0.0, 0.15, 4.5,
]


def free_buffer(buffer):
    if buffer is None:
        return
    if hasattr(buffer, "freebuffer"):
        buffer.freebuffer()
    elif hasattr(buffer, "close"):
        buffer.close()


def cleanup_previous_state():
    state = getattr(builtins, STATE_NAME, None)
    if state is None:
        return

    state["active"] = False
    runtime = state.get("runtime")
    if runtime is not None:
        runtime.close()

    for key in ("conn", "server"):
        obj = state.get(key)
        if obj is not None:
            try:
                obj.close()
            except OSError:
                pass

    free_buffer(state.get("frame0"))
    free_buffer(state.get("frame1"))
    setattr(builtins, STATE_NAME, None)


def phys_addr(buffer):
    if hasattr(buffer, "physical_address"):
        return int(buffer.physical_address)
    return int(buffer.device_address)


def fp32_to_fp27(value):
    bits = struct.unpack(">I", struct.pack(">f", float(value)))[0]
    sign = (bits >> 31) & 0x1
    exponent = (bits >> 23) & 0xFF
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
    for index, value in enumerate(values):
        camera_regs.write(index * 4, fp32_to_fp27(value))


def stop_hardware(camera_regs, vdma, gpio):
    camera_regs.write(FRAME_BASE0_REG, 0)
    camera_regs.write(FRAME_BASE1_REG, 0)
    gpio.write(GPIO2_DATA, 0)
    time.sleep(0.05)
    vdma.write(MM2S_DMACR, 0)


def set_display_bank(vdma, bank):
    bank &= 1
    vdma.write(VDMA_PARK_PTR, bank | (bank << 8))


def reset_vdma(vdma):
    vdma.write(MM2S_DMACR, 0)
    time.sleep(0.01)

    vdma.write(MM2S_DMACR, DMACR_RESET)
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        if (vdma.read(MM2S_DMACR) & DMACR_RESET) == 0:
            return
        time.sleep(0.001)

    dmacr = vdma.read(MM2S_DMACR)
    dmasr = vdma.read(MM2S_DMASR)
    raise RuntimeError(
        f"VDMA reset timed out: DMACR=0x{dmacr:08x}, DMASR=0x{dmasr:08x}. "
        "If this repeats, reboot or power-cycle the board before reloading the bitstream."
    )


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


class Runtime:
    def __init__(self, camera_regs, vdma, gpio, frame0, frame1, server):
        self.camera_regs = camera_regs
        self.vdma = vdma
        self.gpio = gpio
        self.frame0 = frame0
        self.frame1 = frame1
        self.server = server
        self.conn = None
        self.rx_buffer = bytearray()
        self.frame_ack_active = False
        self.frame_ack_count = 0
        self.frame_ack_last_status = 0
        self.camera_packet_count = 0
        self.active = True

    def close(self):
        self.active = False
        try:
            stop_hardware(self.camera_regs, self.vdma, self.gpio)
        except Exception as error:
            print(f"PL shutdown warning: {error}")

        if self.conn is not None:
            try:
                self.conn.close()
            except OSError:
                pass
            self.conn = None
        try:
            self.server.close()
        except OSError:
            pass

    def dump_status(self):
        print(f"VDMA DMACR      = 0x{self.vdma.read(MM2S_DMACR):08x}")
        print(f"VDMA DMASR      = 0x{self.vdma.read(MM2S_DMASR):08x}")
        print(f"VDMA PARK_PTR   = 0x{self.vdma.read(VDMA_PARK_PTR):08x}")
        print(f"VDMA VSIZE      = 0x{self.vdma.read(MM2S_VSIZE):08x}")
        print(f"VDMA HSIZE      = 0x{self.vdma.read(MM2S_HSIZE):08x}")
        print(f"VDMA STRIDE     = 0x{self.vdma.read(MM2S_STRIDE):08x}")
        print(f"VDMA ADDR1      = 0x{self.vdma.read(MM2S_START_ADDR_1):08x}")
        print(f"VDMA ADDR2      = 0x{self.vdma.read(MM2S_START_ADDR_2):08x}")
        print(f"FRAME_BASE0     = 0x{self.camera_regs.read(FRAME_BASE0_REG):08x}")
        print(f"FRAME_BASE1     = 0x{self.camera_regs.read(FRAME_BASE1_REG):08x}")
        print(f"GPIO            = 0x{self.gpio.read(GPIO_DATA):08x}")
        print(f"GPIO2           = 0x{self.gpio.read(GPIO2_DATA):08x}")
        print(f"ACK active      = {self.frame_ack_active}")
        print(f"ACK count       = {self.frame_ack_count}")
        print(f"ACK last GPIO   = 0x{self.frame_ack_last_status:08x}")
        print(f"Camera packets  = {self.camera_packet_count}")

    def service_frame_ready(self):
        status = self.gpio.read(GPIO_DATA)
        self.frame_ack_last_status = status
        ready_bank = status & 1
        ready_valid = (status >> 1) & 1

        if self.frame_ack_active:
            if not ready_valid:
                self.gpio.write(GPIO2_DATA, 0)
                self.frame_ack_active = False
            return

        if ready_valid:
            set_display_bank(self.vdma, ready_bank)
            self.gpio.write(GPIO2_DATA, 1)
            self.frame_ack_active = True
            self.frame_ack_count += 1

    def accept_connection(self):
        try:
            self.conn, addr = self.server.accept()
            self.conn.setblocking(False)
            self.rx_buffer.clear()
            print(f"Camera controller connected from {addr}")
        except BlockingIOError:
            pass

    def close_connection(self):
        if self.conn is None:
            return
        try:
            self.conn.close()
        except OSError:
            pass
        self.conn = None
        self.rx_buffer.clear()
        print("Camera controller disconnected")

    def handle_camera_socket(self):
        if self.conn is None:
            self.accept_connection()
            return

        try:
            chunk = self.conn.recv(4096)
        except BlockingIOError:
            return
        except ConnectionResetError:
            self.close_connection()
            return

        if not chunk:
            self.close_connection()
            return

        self.rx_buffer.extend(chunk)
        packet_count = len(self.rx_buffer) // CAMERA_PACKET_BYTES
        if not packet_count:
            return

        packet_start = (packet_count - 1) * CAMERA_PACKET_BYTES
        packet = bytes(self.rx_buffer[packet_start:packet_start + CAMERA_PACKET_BYTES])
        self.rx_buffer.clear()
        values = struct.unpack("<12f", packet)
        write_camera_values(self.camera_regs, values)
        self.camera_packet_count += 1

    def run(self):
        print(f"Waiting for camera controller on TCP port {TCP_PORT}")
        while self.active:
            self.service_frame_ready()
            self.handle_camera_socket()
            self.service_frame_ready()
            time.sleep(0.0005)


def make_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.setblocking(False)
    server.bind(("0.0.0.0", TCP_PORT))
    server.listen(1)
    return server


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bitfile", default=BITFILE)
    parser.add_argument("--load-overlay", action="store_true")
    parser.add_argument("--no-overlay", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--no-vdma-reset", action="store_true")
    parser.add_argument("--stop", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    cleanup_previous_state()

    bitfile = args.bitfile
    if not Path(bitfile).exists() and Path("ctrl.bit").exists():
        bitfile = "ctrl.bit"

    if args.load_overlay and not args.no_overlay:
        print(f"Loading overlay: {bitfile}")
        Overlay(bitfile)
    else:
        print("Skipping overlay load. Use --load-overlay after power-cycling or copying a new bitstream.")

    camera_regs = MMIO(CAMERA_REG_BASE, SPAN)
    vdma = MMIO(VDMA_BASE, SPAN)
    gpio = MMIO(GPIO_BASE, SPAN)

    if args.stop:
        stop_hardware(camera_regs, vdma, gpio)
        print("Stopped PL framebuffer writes and VDMA reads")
        return

    frame0 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    frame1 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    frame0[:] = 0
    frame1[:] = 0

    frame0_addr = phys_addr(frame0)
    frame1_addr = phys_addr(frame1)

    gpio.write(GPIO_TRI, 0xFFFFFFFF)
    gpio.write(GPIO2_TRI, 0x00000000)
    gpio.write(GPIO2_DATA, 0)

    write_camera_values(camera_regs, DEFAULT_CAMERA)
    camera_regs.write(FRAME_BASE0_REG, frame0_addr)
    camera_regs.write(FRAME_BASE1_REG, frame1_addr)
    if args.no_vdma_reset:
        vdma.write(MM2S_DMASR, 0xFFFFFFFF)
        vdma.write(MM2S_FRMSTORE, 2)
        vdma.write(MM2S_START_ADDR_1, frame0_addr)
        vdma.write(MM2S_START_ADDR_2, frame1_addr)
        vdma.write(MM2S_STRIDE, STRIDE)
        vdma.write(MM2S_HSIZE, HSIZE)
        set_display_bank(vdma, 0)
        vdma.write(MM2S_DMACR, DMACR_RUN_PARK)
        vdma.write(MM2S_VSIZE, HEIGHT)
    else:
        init_vdma(vdma, frame0_addr, frame1_addr)

    server = make_server()
    runtime = Runtime(camera_regs, vdma, gpio, frame0, frame1, server)
    setattr(builtins, STATE_NAME, {
        "active": True,
        "frame0": frame0,
        "frame1": frame1,
        "server": server,
        "conn": None,
        "runtime": runtime,
    })
    builtins.ctrl_runtime = runtime
    builtins.dump_status = runtime.dump_status

    print(f"FRAME0 phys = 0x{frame0_addr:08x}")
    print(f"FRAME1 phys = 0x{frame1_addr:08x}")
    runtime.dump_status()

    try:
        runtime.run()
    except KeyboardInterrupt:
        print("Stopped")
    finally:
        runtime.close()
        free_buffer(frame0)
        free_buffer(frame1)
        setattr(builtins, STATE_NAME, None)


if __name__ == "__main__":
    main()
