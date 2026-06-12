import time

from pynq import MMIO


CAMERA_REG_BASE = 0x43C00000
VDMA_BASE = 0x43000000
GPIO_BASE = 0x41200000
SPAN = 0x10000

FRAME_BASE0_REG = 12 * 4
FRAME_BASE1_REG = 13 * 4
MM2S_DMACR = 0x00
GPIO2_DATA = 0x08


camera_regs = MMIO(CAMERA_REG_BASE, SPAN)
vdma = MMIO(VDMA_BASE, SPAN)
gpio = MMIO(GPIO_BASE, SPAN)

camera_regs.write(FRAME_BASE0_REG, 0)
camera_regs.write(FRAME_BASE1_REG, 0)
gpio.write(GPIO2_DATA, 0)
time.sleep(0.05)
vdma.write(MM2S_DMACR, 0)

print("Stopped PL framebuffer writes and VDMA reads")
