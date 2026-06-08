from pynq import Overlay, MMIO

# ── Load bitstream ────────────────────────────────────────────────────────────
ol = Overlay('/home/xilinx/jupyter_notebooks/VincentRayMarcher/design_1_wrapper.xsa')
print("Overlay loaded")

# ── IP base addresses (from Vivado BD address editor) ────────────────────────
VDMA_BASE = 0x43000000
VTC_BASE  = 0x43C00000

vdma = MMIO(VDMA_BASE, 0x10000)
vtc  = MMIO(VTC_BASE,  0x10000)

# ── Frame buffer (must match axi_fb_writer.sv) ───────────────────────────────
FRAME_BASE = 0x1E000000   # frame_base_0
WIDTH      = 1280
HEIGHT     = 720
STRIDE     = WIDTH * 4    # 5120 bytes, 32-bit pixels

# ── Video Timing Controller: 1280x720 @ 60 Hz ────────────────────────────────
# H: active=1280, fp=110, sync=40, bp=220, total=1650
# V: active=720,  fp=5,   sync=5,  bp=20,  total=750
vtc.write(0x000, 0x00000000)                  # disable
vtc.write(0x068, (HEIGHT << 16) | WIDTH)      # active size
vtc.write(0x070, 1650)                         # H total
vtc.write(0x074, 750)                          # V total
vtc.write(0x078, (1430 << 16) | 1390)         # H sync: end=1430, start=1390
vtc.write(0x07C, (730  << 16) | 725)          # V sync: end=730,  start=725
vtc.write(0x080, (1650 << 16) | 1280)         # H blank: end=1650, start=1280
vtc.write(0x084, (750  << 16) | 720)          # V blank: end=750,  start=720
vtc.write(0x000, 0x0002000D)                  # enable generator, +ve sync polarity
print("VTC configured")

# ── VDMA MM2S: reset ─────────────────────────────────────────────────────────
vdma.write(0x00, 0x4)
for _ in range(10000):
    if not (vdma.read(0x00) & 0x4):
        break
print("VDMA reset done")

# ── VDMA MM2S: start (write VSIZE last — that triggers the DMA) ──────────────
vdma.write(0x00, 0x1)             # run
vdma.write(0x50, FRAME_BASE)      # frame buffer address
vdma.write(0x30, STRIDE)          # stride in bytes
vdma.write(0x2C, WIDTH * 4)       # H size in bytes (bytes per line)
vdma.write(0x28, HEIGHT)          # V size in lines — starts DMA

# ── Status ───────────────────────────────────────────────────────────────────
dmasr = vdma.read(0x04)
print(f"VDMA status: {hex(dmasr)}")
if dmasr & 0x1:
    print("  VDMA halted — check frame buffer address and VDMA config")
else:
    print("  VDMA running — check HDMI cable")
