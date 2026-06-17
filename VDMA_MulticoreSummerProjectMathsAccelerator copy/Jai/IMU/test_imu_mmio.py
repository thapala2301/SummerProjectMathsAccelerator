import sys
import struct
import time

BIT_FILE  = sys.argv[1] if len(sys.argv) > 1 else "/home/xilinx/jupyter_notebooks/FInal/top_ps.bit"
IIC_BASE  = 0x41600000
MMIO_BASE = 0x43C00000
IMU_ADDR  = 0x68

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"
INFO = "\033[94mINFO\033[0m"

def section(title):
    print(f"\n{'='*60}\n  {title}\n{'='*60}")

section("1 / 4  Load bitstream overlay")
try:
    from pynq import Overlay, MMIO
    ol = Overlay(BIT_FILE)
    print(f"[{PASS}] Overlay loaded")
    print(f"[{INFO}] IPs: {list(ol.ip_dict.keys())}")
except Exception as e:
    print(f"[{FAIL}] {e}")
    sys.exit(1)

time.sleep(0.5)

m = MMIO(IIC_BASE, 0x1000)

def iic_reset():
    m.write(0x040, 0x0A)
    time.sleep(0.1)
    m.write(0x100, 0x02)
    time.sleep(0.05)
    m.write(0x100, 0x01)

def iic_write(addr, reg, val):
    iic_reset()
    m.write(0x020, 0xFF)
    m.write(0x108, addr << 1)
    m.write(0x108, reg)
    m.write(0x108, val)
    m.write(0x100, 0x07)
    time.sleep(0.003)

def iic_read_byte(addr, reg):
    iic_reset()
    m.write(0x020, 0xFF)
    m.write(0x108, addr << 1)
    m.write(0x108, reg)
    m.write(0x100, 0x07)
    time.sleep(0.003)
    if m.read(0x020) & 0x10:
        return None
    m.write(0x020, 0xFF)
    m.write(0x108, (addr << 1) | 1)
    m.write(0x100, 0x1D)
    time.sleep(0.003)
    if m.read(0x104) & 0x40:
        return None
    return m.read(0x10C) & 0xFF

def iic_read(addr, reg, n):
    result = []
    for i in range(n):
        b = iic_read_byte(addr, reg + i)
        if b is None:
            return None
        result.append(b)
    return result

section("2 / 4  MPU WHO_AM_I check")

VALID = {0x71: "MPU-9250", 0x70: "MPU-6500", 0x68: "MPU-6050", 0x73: "MPU-9255"}

who = iic_read(IMU_ADDR, 0x75, 1)
if who is None:
    print(f"[{FAIL}] NACK - device not found at 0x68")
    print(f"        Check: VCC->3.3V, GND->GND, SDA->A4, SCL->A5, AD0->GND")
    sys.exit(1)

name = VALID.get(who[0], "Unknown")
if who[0] in VALID:
    print(f"[{PASS}] WHO_AM_I = 0x{who[0]:02X} -> {name}")
else:
    print(f"[{FAIL}] WHO_AM_I = 0x{who[0]:02X} (unrecognised)")
    sys.exit(1)

section("3 / 4  Live accel + gyro data (10 samples)")

for reg, val in [(0x6B,0x80),(0x6B,0x01),(0x6C,0x00),
                 (0x1A,0x03),(0x19,9),(0x1B,0x00),(0x1C,0x00)]:
    iic_write(IMU_ADDR, reg, val)
time.sleep(0.2)

print(f"  {'ax(g)':>8} {'ay(g)':>8} {'az(g)':>8}   |a|")
bad = 0
for _ in range(10):
    d = iic_read(IMU_ADDR, 0x3B, 6)
    if d is None:
        print(f"  [read failed]")
        bad += 1
        continue
    ax, ay, az = [v/16384.0 for v in struct.unpack('>hhh', bytes(d))]
    mag = (ax**2 + ay**2 + az**2)**0.5
    if not (0.5 < mag < 2.0):
        bad += 1
    print(f"  {ax:+8.4f} {ay:+8.4f} {az:+8.4f}   {mag:.4f}g")
    time.sleep(0.1)

if bad == 0:
    print(f"\n[{PASS}] All 10 samples sane (|a| near 1g)")
else:
    print(f"\n[{FAIL}] {bad}/10 samples bad - check power/wiring")

section("4 / 4  AXI camera register write/readback")

try:
    cam = MMIO(MMIO_BASE, 0x1000)
    cam.write(0, 0x12345678)
    rb = cam.read(0)
    if rb == 0x12345678:
        print(f"[{PASS}] MMIO write/readback OK")
    else:
        print(f"[{FAIL}] Wrote 0x12345678, got 0x{rb:08X}")
except Exception as e:
    print(f"[{FAIL}] {e}")

section("Done")
