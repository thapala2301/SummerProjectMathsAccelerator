import threading
import time

import numpy as np
from pynq import MMIO, allocate


CAMERA_REG_BASE = 0x43C00000
VDMA_BASE = 0x43000000
GPIO_BASE = 0x41200000
SPAN = 0x10000

WIDTH = 1024
HEIGHT = 600
BYTES_PER_PIXEL = 4
STRIDE = WIDTH * BYTES_PER_PIXEL
HSIZE = WIDTH * BYTES_PER_PIXEL

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

DMACR_RUN_PARK = 0x1
DMACR_RESET = 0x4

camera_regs = MMIO(CAMERA_REG_BASE, SPAN)
vdma = MMIO(VDMA_BASE, SPAN)
gpio = MMIO(GPIO_BASE, SPAN)


def phys_addr(buffer):
    if hasattr(buffer, "physical_address"):
        return int(buffer.physical_address)
    return int(buffer.device_address)


def reset_vdma():
    vdma.write(MM2S_DMACR, DMACR_RESET)
    for _ in range(10000):
        if (vdma.read(MM2S_DMACR) & DMACR_RESET) == 0:
            return
        time.sleep(0.0001)
    raise RuntimeError("VDMA reset timed out")


def set_display_bank(bank):
    bank &= 1
    vdma.write(VDMA_PARK_PTR, bank | (bank << 8))


def init_vdma(frame0_addr, frame1_addr):
    reset_vdma()
    vdma.write(MM2S_FRMSTORE, 2)
    vdma.write(MM2S_DMACR, DMACR_RUN_PARK)
    vdma.write(MM2S_START_ADDR_1, frame0_addr)
    vdma.write(MM2S_START_ADDR_2, frame1_addr)
    vdma.write(MM2S_STRIDE, STRIDE)
    vdma.write(MM2S_HSIZE, HSIZE)
    set_display_bank(0)
    vdma.write(MM2S_VSIZE, HEIGHT)


def pulse_frame_ack():
    gpio.write(GPIO2_DATA, 1)
    time.sleep(0.000001)
    gpio.write(GPIO2_DATA, 0)


def frame_ack_loop():
    while True:
        status = gpio.read(GPIO_DATA)
        ready_bank = status & 1
        ready_valid = (status >> 1) & 1

        if ready_valid:
            set_display_bank(ready_bank)
            pulse_frame_ack()

            while (gpio.read(GPIO_DATA) >> 1) & 1:
                time.sleep(0.0005)

        time.sleep(0.0005)


renderer_frame0 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
renderer_frame1 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
renderer_frame0[:] = 0
renderer_frame1[:] = 0

frame0_addr = phys_addr(renderer_frame0)
frame1_addr = phys_addr(renderer_frame1)

gpio.write(GPIO_TRI, 0xFFFFFFFF)
gpio.write(GPIO2_TRI, 0x00000000)
gpio.write(GPIO2_DATA, 0)

init_vdma(frame0_addr, frame1_addr)

if "frame_ack_thread" not in globals() or not frame_ack_thread.is_alive():
    frame_ack_thread = threading.Thread(target=frame_ack_loop, daemon=True)
    frame_ack_thread.start()

camera_regs.write(FRAME_BASE0_REG, frame0_addr)
camera_regs.write(FRAME_BASE1_REG, frame1_addr)

print(f"FRAME0 phys = 0x{frame0_addr:08x}")
print(f"FRAME1 phys = 0x{frame1_addr:08x}")
print(f"VDMA DMACR  = 0x{vdma.read(MM2S_DMACR):08x}")
print(f"VDMA DMASR  = 0x{vdma.read(MM2S_DMASR):08x}")
print(f"FRMSTORE    = 0x{vdma.read(MM2S_FRMSTORE):08x}")
print(f"PARK_PTR    = 0x{vdma.read(VDMA_PARK_PTR):08x}")
print(f"VSIZE       = 0x{vdma.read(MM2S_VSIZE):08x}")
print(f"HSIZE       = 0x{vdma.read(MM2S_HSIZE):08x}")
print(f"STRIDE      = 0x{vdma.read(MM2S_STRIDE):08x}")
print(f"ADDR1       = 0x{vdma.read(MM2S_START_ADDR_1):08x}")
print(f"ADDR2       = 0x{vdma.read(MM2S_START_ADDR_2):08x}")
print(f"FRAME_BASE0 = 0x{camera_regs.read(FRAME_BASE0_REG):08x}")
print(f"FRAME_BASE1 = 0x{camera_regs.read(FRAME_BASE1_REG):08x}")
print(f"GPIO        = 0x{gpio.read(GPIO_DATA):08x}")
