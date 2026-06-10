import time

import numpy as np
from pynq import MMIO, allocate

VDMA_BASE = 0x43000000
SPAN = 0x10000

WIDTH = 1024
HEIGHT = 600
BYTES_PER_PIXEL = 4
STRIDE = WIDTH * BYTES_PER_PIXEL
HSIZE = WIDTH * BYTES_PER_PIXEL

MM2S_DMACR = 0x00
MM2S_DMASR = 0x04
MM2S_VSIZE = 0x50
MM2S_HSIZE = 0x54
MM2S_STRIDE = 0x58
MM2S_START_ADDR_1 = 0x5C
MM2S_START_ADDR_2 = 0x60

DMACR_RUN_CIRCULAR = 0x3
DMACR_RESET = 0x4


def make_frame():
    try:
        return allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    except TypeError:
        return allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32)


def fill_frame(frame):
    colors = np.array(
        [
            0x00FF0000,
            0x0000FF00,
            0x000000FF,
            0x00FFFFFF,
            0x00FFFF00,
            0x0000FFFF,
        ],
        dtype=np.uint32,
    )

    for y in range(HEIGHT):
        frame[y, :] = colors[(y // 100) % len(colors)]

    if hasattr(frame, "flush"):
        frame.flush()


def reset_vdma(vdma):
    vdma.write(MM2S_DMACR, DMACR_RESET)
    for _ in range(10000):
        if (vdma.read(MM2S_DMACR) & DMACR_RESET) == 0:
            return
        time.sleep(0.0001)
    raise RuntimeError("VDMA reset timed out")


def phys_addr(frame):
    return getattr(frame, "physical_address", frame.device_address)


frame0 = make_frame()
frame1 = make_frame()
fill_frame(frame0)
fill_frame(frame1)

vdma = MMIO(VDMA_BASE, SPAN)
reset_vdma(vdma)
vdma.write(MM2S_DMACR, DMACR_RUN_CIRCULAR)
vdma.write(MM2S_START_ADDR_1, phys_addr(frame0))
vdma.write(MM2S_START_ADDR_2, phys_addr(frame1))
vdma.write(MM2S_STRIDE, STRIDE)
vdma.write(MM2S_HSIZE, HSIZE)
vdma.write(MM2S_VSIZE, HEIGHT)

globals()["_ddr_test_frame0"] = frame0
globals()["_ddr_test_frame1"] = frame1

print(f"FRAME0 phys = 0x{phys_addr(frame0):08x}")
print(f"FRAME1 phys = 0x{phys_addr(frame1):08x}")
print(f"VDMA DMACR  = 0x{vdma.read(MM2S_DMACR):08x}")
print(f"VDMA DMASR  = 0x{vdma.read(MM2S_DMASR):08x}")
print("Filled allocated DDR framebuffers with test bars")
