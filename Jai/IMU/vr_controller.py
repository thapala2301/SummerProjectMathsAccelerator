import math
import select
import signal
import struct
import sys
import threading
import time

import numpy as np
from pynq import Overlay, MMIO, allocate

# --- config ---
BIT_FILE        = sys.argv[1] if len(sys.argv) > 1 else "/home/xilinx/jupyter_notebooks/IMU/top_ps.bit"
IIC_BASE        = 0x41600000
AXI_CAM_BASE    = 0x43C00000
VDMA_BASE       = 0x43000000
GPIO_BASE       = 0x41200000
SPAN            = 0x10000
WIDTH           = 1024
HEIGHT          = 600
STRIDE          = WIDTH * 4
HSIZE           = WIDTH * 4
FRAME_BASE0_REG = 15 * 4
FRAME_BASE1_REG = 16 * 4
IMU_ADDR        = 0x68
TARGET_HZ       = 100
CALIB_SAMPLES   = 200
ACCEL_GAIN      = 0.02
ACCEL_MIN_G     = 0.75
ACCEL_MAX_G     = 1.25
GYRO_DEADBAND   = 0.05
MAX_FAILS       = 15
MOVE_STEP       = 0.05
INIT_POS        = np.array([0.0, 0.15, 4.5], dtype=np.float64)

# sensor axis -> scene axis mapping: (source_index, sign)
AXIS_MAP = [(0, +1), (1, +1), (2, -1)]

VALID_WHO_AM_I = {0x71: "MPU-9250", 0x70: "MPU-6500", 0x68: "MPU-6050", 0x73: "MPU-9255"}

# --- VDMA register offsets ---
MM2S_DMACR       = 0x00
MM2S_DMASR       = 0x04
MM2S_FRMSTORE    = 0x18
VDMA_PARK_PTR    = 0x28
MM2S_VSIZE       = 0x50
MM2S_HSIZE       = 0x54
MM2S_STRIDE      = 0x58
MM2S_START_ADDR1 = 0x5C
MM2S_START_ADDR2 = 0x60
GPIO_TRI         = 0x04
GPIO2_DATA       = 0x08
GPIO2_TRI        = 0x0C

# --- AXI IIC MMIO driver ---
_iic             = None
_iic_needs_reset = True

def _iic_softr():
    global _iic_needs_reset
    _iic.write(0x040, 0x0A)  # soft reset
    time.sleep(0.010)
    _iic.write(0x100, 0x02)  # clear CR
    time.sleep(0.005)
    _iic.write(0x100, 0x01)  # EN only
    _iic_needs_reset = False

def _iic_clear():
    _iic.write(0x020, 0xFF)  # clear ISR
    _iic.write(0x100, 0x01)  # EN only

def _iic_prep():
    if _iic_needs_reset:
        _iic_softr()
    else:
        _iic_clear()

def iic_write_reg(addr, reg, val):
    _iic_prep()
    _iic.write(0x108, addr << 1)
    _iic.write(0x108, reg)
    _iic.write(0x108, val)
    _iic.write(0x100, 0x07)  # START + TX + MSMS -> send + STOP
    time.sleep(0.001)

def iic_read_byte(addr, reg):
    global _iic_needs_reset
    _iic_prep()
    _iic.write(0x108, addr << 1)
    _iic.write(0x108, reg)
    _iic.write(0x100, 0x07)  # write phase
    time.sleep(0.001)
    if _iic.read(0x020) & 0x10:  # NACK
        _iic_needs_reset = True
        return None
    _iic_clear()
    _iic.write(0x108, (addr << 1) | 1)
    _iic.write(0x100, 0x1D)  # read phase: RSTA + TXAK + MSMS
    time.sleep(0.001)
    if _iic.read(0x104) & 0x40:  # RX FIFO empty
        _iic_needs_reset = True
        return None
    return _iic.read(0x10C) & 0xFF

def iic_read_bytes(addr, reg, n):
    result = []
    for i in range(n):
        b = iic_read_byte(addr, reg + i)
        if b is None:
            return None
        result.append(b)
    return result

# --- IMU driver (MPU-6050 / MPU-9250 via MMIO I2C) ---
class MPU:
    def __init__(self, addr=IMU_ADDR):
        self._addr = addr
        self._init()

    def _init(self):
        global _iic_needs_reset
        _iic_needs_reset = True
        _iic_softr()
        iic_write_reg(self._addr, 0x6B, 0x80)  # device reset
        time.sleep(0.15)
        iic_write_reg(self._addr, 0x6B, 0x01)  # wake up
        time.sleep(0.05)
        who = iic_read_byte(self._addr, 0x75)
        if who is None or who not in VALID_WHO_AM_I:
            raise RuntimeError(
                f"IMU not found at 0x{self._addr:02X} (WHO_AM_I={'None' if who is None else hex(who)}). "
                f"Check: VCC->3.3V GND->GND SDA->A4 SCL->A5 AD0->GND"
            )
        iic_write_reg(self._addr, 0x6C, 0x00)  # enable all axes
        iic_write_reg(self._addr, 0x1A, 0x03)  # DLPF 44 Hz
        iic_write_reg(self._addr, 0x19, 0x09)  # 100 Hz sample rate
        iic_write_reg(self._addr, 0x1B, 0x00)  # gyro +-250 dps
        iic_write_reg(self._addr, 0x1C, 0x00)  # accel +-2g
        time.sleep(0.1)
        print(f"[IMU] {VALID_WHO_AM_I[who]} ready (WHO_AM_I=0x{who:02X})")

    def read_raw(self):
        d = iic_read_bytes(self._addr, 0x3B, 14)
        if d is None:
            raise RuntimeError("I2C read failed")
        ax = struct.unpack('>h', bytes(d[0:2]))[0] / 16384.0
        ay = struct.unpack('>h', bytes(d[2:4]))[0] / 16384.0
        az = struct.unpack('>h', bytes(d[4:6]))[0] / 16384.0
        gx = struct.unpack('>h', bytes(d[8:10]))[0] / 131.0
        gy = struct.unpack('>h', bytes(d[10:12]))[0] / 131.0
        gz = struct.unpack('>h', bytes(d[12:14]))[0] / 131.0
        return ax, ay, az, gx, gy, gz

    def reinit(self):
        for attempt in range(1, 6):
            try:
                self._init()
                return True
            except Exception as e:
                print(f"[IMU] Reinit {attempt}/5: {e}")
                time.sleep(0.5 * attempt)
        return False

# --- VDMA + frame buffer init ---
_frame0 = None
_frame1 = None

def _phys(buf):
    return int(buf.physical_address if hasattr(buf, 'physical_address') else buf.device_address)

def init_vdma(vdma, gpio):
    global _frame0, _frame1
    _frame0 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    _frame1 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    _frame0[:] = 0
    _frame1[:] = 0
    f0 = _phys(_frame0)
    f1 = _phys(_frame1)
    vdma.write(MM2S_DMACR, 0x4)  # reset
    for _ in range(10000):
        if (vdma.read(MM2S_DMACR) & 0x4) == 0:
            break
        time.sleep(0.0001)
    else:
        raise RuntimeError("VDMA reset timed out")
    vdma.write(MM2S_FRMSTORE,    2)
    vdma.write(MM2S_DMACR,       0x1)
    vdma.write(MM2S_START_ADDR1, f0)
    vdma.write(MM2S_START_ADDR2, f1)
    vdma.write(MM2S_STRIDE,      STRIDE)
    vdma.write(MM2S_HSIZE,       HSIZE)
    vdma.write(VDMA_PARK_PTR,    0)
    vdma.write(MM2S_VSIZE,       HEIGHT)
    cam = MMIO(AXI_CAM_BASE, SPAN)
    cam.write(FRAME_BASE0_REG, f0)
    cam.write(FRAME_BASE1_REG, f1)
    gpio.write(GPIO_TRI,   0xFFFFFFFF)
    gpio.write(GPIO2_TRI,  0x00000000)
    gpio.write(GPIO2_DATA, 0)
    print(f"[VDMA] FRAME0=0x{f0:08x}  FRAME1=0x{f1:08x}")
    print(f"[VDMA] DMACR=0x{vdma.read(MM2S_DMACR):08x}  VSIZE=0x{vdma.read(MM2S_VSIZE):08x}")

def frame_ack_loop(vdma, gpio):
    while True:
        status = gpio.read(0x00)
        if (status >> 1) & 1:
            bank = status & 1
            vdma.write(VDMA_PARK_PTR, bank | (bank << 8))
            gpio.write(GPIO2_DATA, 1)
            time.sleep(0.000001)
            gpio.write(GPIO2_DATA, 0)
            while (gpio.read(0x00) >> 1) & 1:
                time.sleep(0.0005)
        time.sleep(0.0005)

# --- gyro bias calibration ---
def calibrate_gyro(imu):
    print(f"[CAL] Keep still — calibrating gyro ({CALIB_SAMPLES} samples)...")
    gs = np.zeros(3)
    n = 0
    for _ in range(CALIB_SAMPLES):
        try:
            _, _, _, gx, gy, gz = imu.read_raw()
            gs += [gx, gy, gz]
            n += 1
        except RuntimeError:
            pass
        time.sleep(0.01)
    if n == 0:
        print("[CAL] No samples — bias zero")
        return np.zeros(3)
    bias = gs / n
    print(f"[CAL] Gyro bias: [{bias[0]:+.4f}, {bias[1]:+.4f}, {bias[2]:+.4f}] deg/s")
    return bias

# --- sensor axis remapping ---
def remap(ax, ay, az, gx, gy, gz):
    ra = (ax, ay, az)
    rg = (gx, gy, gz)
    return (
        ra[AXIS_MAP[0][0]] * AXIS_MAP[0][1],
        ra[AXIS_MAP[1][0]] * AXIS_MAP[1][1],
        ra[AXIS_MAP[2][0]] * AXIS_MAP[2][1],
        rg[AXIS_MAP[0][0]] * AXIS_MAP[0][1],
        rg[AXIS_MAP[1][0]] * AXIS_MAP[1][1],
        rg[AXIS_MAP[2][0]] * AXIS_MAP[2][1],
    )

# --- complementary orientation filter ---
class OrientationFilter:
    def __init__(self):
        self.reset()

    def reset(self):
        self.R = np.array([[1., 0., 0.], [0., 1., 0.], [0., 0., -1.]], dtype=np.float64)

    def update(self, gx, gy, gz, ax, ay, az, dt, gyro_bias):
        if dt <= 0.0 or dt > 0.5:
            return
        # gyro integration
        wx = math.radians(gx - gyro_bias[0])
        wy = math.radians(gy - gyro_bias[1])
        wz = math.radians(gz - gyro_bias[2])
        if abs(wx) < math.radians(GYRO_DEADBAND): wx = 0.0
        if abs(wy) < math.radians(GYRO_DEADBAND): wy = 0.0
        if abs(wz) < math.radians(GYRO_DEADBAND): wz = 0.0
        dx, dy, dz = wx * dt, wy * dt, wz * dt
        dR = np.array([[1., -dz, dy], [dz, 1., -dx], [-dy, dx, 1.]], dtype=np.float64)
        Rg = dR @ self.R
        # accel tilt correction
        a_mag = math.sqrt(ax*ax + ay*ay + az*az)
        if ACCEL_MIN_G < a_mag < ACCEL_MAX_G:
            a_norm = np.array([ax, ay, az]) / a_mag
            g_meas = Rg @ a_norm
            err = np.cross(g_meas, np.array([0., 1., 0.]))
            err_mag = float(np.linalg.norm(err))
            if err_mag > 1e-8:
                e = err * (ACCEL_GAIN / err_mag) * min(err_mag, 1.0)
                Rc = np.array([[1., -e[2], e[1]], [e[2], 1., -e[0]], [-e[1], e[0], 1.]], dtype=np.float64)
                Rg = Rc @ Rg
        # Gram-Schmidt re-orthogonalisation
        right = Rg[0] / (np.linalg.norm(Rg[0]) + 1e-15)
        fwd   = Rg[2] - np.dot(Rg[2], right) * right
        fwd   = fwd / (np.linalg.norm(fwd) + 1e-15)
        up    = np.cross(right, fwd)
        up    = up / (np.linalg.norm(up) + 1e-15)
        self.R = np.array([right, up, fwd], dtype=np.float64)

# --- keyboard controller ---
class KeyboardController:
    def __init__(self):
        self.pos      = INIT_POS.copy()
        self._lock    = threading.Lock()
        self._cmds    = []
        self._stop    = False
        self._reset   = False
        self._old_tty = None
        try:
            import tty, termios
            self._old_tty = termios.tcgetattr(sys.stdin)
            tty.setcbreak(sys.stdin.fileno())
        except Exception:
            pass
        threading.Thread(target=self._listen, daemon=True).start()

    def _listen(self):
        while not self._stop:
            try:
                if select.select([sys.stdin], [], [], 0.05)[0]:
                    ch = sys.stdin.read(1).lower()
                    with self._lock:
                        self._cmds.append(ch)
            except Exception:
                break

    def tick(self, R):
        with self._lock:
            cmds = self._cmds[:]
            self._cmds.clear()
        for ch in cmds:
            if   ch == 'w': self.pos += R[2] * -MOVE_STEP
            elif ch == 's': self.pos -= R[2] * -MOVE_STEP
            elif ch == 'd': self.pos += R[0] *  MOVE_STEP
            elif ch == 'a': self.pos -= R[0] *  MOVE_STEP
            elif ch == ' ': self.pos += R[1] *  MOVE_STEP
            elif ch == 'c': self.pos -= R[1] *  MOVE_STEP
            elif ch == 'r':
                self.pos = INIT_POS.copy()
                with self._lock:
                    self._reset = True
        return self.pos.copy()

    def consume_reset(self):
        with self._lock:
            v = self._reset
            self._reset = False
        return v

    def stop(self):
        self._stop = True
        if self._old_tty is not None:
            try:
                import termios
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, self._old_tty)
            except Exception:
                pass

# --- FP27 float conversion (1 sign | 8 exp | 18 frac) ---
def fp32_to_fp27(value):
    bits     = struct.unpack(">I", struct.pack(">f", float(value)))[0]
    sign     = (bits >> 31) & 0x1
    exponent = (bits >> 23) & 0xFF
    frac23   = bits & 0x7FFFFF
    if exponent == 0:
        return sign << 26
    if exponent == 0xFF:
        return (sign << 26) | (exponent << 18) | (1 if frac23 else 0)
    frac18 = (frac23 + 0x10) >> 5
    if frac18 >= (1 << 18):
        frac18 = 0
        exponent = min(exponent + 1, 0xFF)
    return (sign << 26) | ((exponent & 0xFF) << 18) | frac18

# --- AXI camera register writer ---
class AXICameraRegs:
    def __init__(self):
        self._m = MMIO(AXI_CAM_BASE, SPAN)
        print(f"[AXI] Camera regs at 0x{AXI_CAM_BASE:08X}")

    def write(self, R, pos):
        for i, v in enumerate(R.flatten()):  # regs 0-8: rotation matrix
            self._m.write(i * 4, fp32_to_fp27(float(v)) & 0xFFFFFFFF)
        for i, v in enumerate(pos):          # regs 9-11: camera position
            self._m.write(0x24 + i * 4, fp32_to_fp27(float(v)) & 0xFFFFFFFF)

    def write_identity(self):
        self.write(np.array([[1., 0., 0.], [0., 1., 0.], [0., 0., -1.]], dtype=np.float64), INIT_POS)

# --- signal handler ---
_running = True

def _on_signal(sig, frame):
    global _running
    _running = False

signal.signal(signal.SIGINT,  _on_signal)
signal.signal(signal.SIGTERM, _on_signal)

# --- main ---
def main():
    global _iic, _running

    print("=" * 64)
    print("  VR Controller  |  PYNQ-Z1  |  MPU-6050/9250")
    print(f"  Bitfile: {BIT_FILE}")
    print("=" * 64)

    print("[INIT] Loading overlay...")
    Overlay(BIT_FILE)
    time.sleep(0.5)
    print("[INIT] Overlay loaded")

    _iic = MMIO(IIC_BASE,  SPAN)
    vdma = MMIO(VDMA_BASE, SPAN)
    gpio = MMIO(GPIO_BASE, SPAN)

    print("[INIT] Initialising VDMA...")
    init_vdma(vdma, gpio)
    threading.Thread(target=frame_ack_loop, args=(vdma, gpio), daemon=True).start()

    print("[INIT] Connecting to IMU...")
    try:
        imu = MPU(IMU_ADDR)
    except RuntimeError as e:
        print(f"[FATAL] {e}")
        sys.exit(1)

    regs      = AXICameraRegs()
    gyro_bias = calibrate_gyro(imu)
    ori       = OrientationFilter()
    kb        = KeyboardController()

    print("\nControls: W/S=fwd/back  A/D=left/right  Space/C=up/down  R=reset  Ctrl+C=quit\n")

    prev_t      = time.monotonic()
    target_dt   = 1.0 / TARGET_HZ
    frame       = 0
    fail_streak = 0

    while _running:
        now = time.monotonic()
        dt  = now - prev_t
        rem = target_dt - dt
        if rem > 0:
            time.sleep(rem)
            now = time.monotonic()
            dt  = now - prev_t
        prev_t = now

        if kb.consume_reset():
            ori.reset()
            print("[INFO] Orientation and position reset")

        try:
            ax, ay, az, gx, gy, gz = imu.read_raw()
            fail_streak = 0
        except RuntimeError:
            fail_streak += 1
            if fail_streak == MAX_FAILS:
                print(f"[ERR] {MAX_FAILS} consecutive I2C failures — reinitialising IMU...")
                if imu.reinit():
                    gyro_bias = calibrate_gyro(imu)
                    fail_streak = 0
                    print("[INFO] IMU recovered")
                else:
                    print("[FATAL] IMU reinit failed — exiting")
                    _running = False
            continue

        ax, ay, az, gx, gy, gz = remap(ax, ay, az, gx, gy, gz)
        ori.update(gx, gy, gz, ax, ay, az, dt, gyro_bias)
        pos = kb.tick(ori.R)

        try:
            regs.write(ori.R, pos)
        except Exception as e:
            print(f"[WARN] MMIO write: {e}")

        frame += 1
        if frame % (TARGET_HZ * 2) == 0:
            yaw   = math.degrees(math.atan2( ori.R[2, 0],  ori.R[2, 2]))
            pitch = math.degrees(math.asin(max(-1., min(1., -ori.R[2, 1]))))
            roll  = math.degrees(math.atan2(-ori.R[1, 0],  ori.R[1, 1]))
            a_mag = math.sqrt(ax*ax + ay*ay + az*az)
            print(
                f"[{frame:6d}] yaw={yaw:+6.1f}  pitch={pitch:+5.1f}  roll={roll:+5.1f} deg  "
                f"pos=[{pos[0]:.2f},{pos[1]:.2f},{pos[2]:.2f}]  |a|={a_mag:.3f}g"
            )

    kb.stop()
    try:
        regs.write_identity()
        print("[INFO] FPGA reset to identity orientation")
    except Exception:
        pass
    print("[INFO] Done")


if __name__ == "__main__":
    main()
