#!/usr/bin/env python3
"""
Debug script for multicore ray marcher.
Checks: MMIO accessibility, VDMA startup, camera reg write/readback,
        frame_ready_valid toggling (proves render pipeline works).
Run this on the PYNQ board INSTEAD of the normal board.py.
"""

import socket
import struct
import time

import numpy as np
from pynq import MMIO, allocate

# ── addresses (must match your BD address map) ──────────────────────────────
CAMERA_REG_BASE = 0x43C00000
VDMA_BASE       = 0x43000000
GPIO_BASE       = 0x41200000
SPAN            = 0x10000

# ── display ──────────────────────────────────────────────────────────────────
WIDTH           = 1024
HEIGHT          = 600
BYTES_PER_PIXEL = 4
STRIDE          = WIDTH * BYTES_PER_PIXEL
HSIZE           = WIDTH * BYTES_PER_PIXEL

# ── camera regs ──────────────────────────────────────────────────────────────
FRAME_BASE0_REG  = 12 * 4
FRAME_BASE1_REG  = 13 * 4
CAMERA_COMMIT_REG = 14 * 4

# ── VDMA reg offsets ─────────────────────────────────────────────────────────
MM2S_DMACR       = 0x00
MM2S_DMASR       = 0x04
MM2S_FRMSTORE    = 0x18
VDMA_PARK_PTR    = 0x28
MM2S_VSIZE       = 0x50
MM2S_HSIZE       = 0x54
MM2S_STRIDE      = 0x58
MM2S_START_ADDR_1 = 0x5C
MM2S_START_ADDR_2 = 0x60

DMACR_RUN_PARK  = 0x00000001
DMACR_RESET     = 0x00000004

# ── GPIO reg offsets ─────────────────────────────────────────────────────────
# Channel 1 (inputs): bit0 = frame_ready_bank, bit1 = frame_ready_valid
# Channel 2 (output): bit0 = frame_ack
GPIO_DATA  = 0x00   # channel 1 read
GPIO_TRI   = 0x04   # channel 1 direction (all 1 = input)
GPIO2_DATA = 0x08   # channel 2 write
GPIO2_TRI  = 0x0C   # channel 2 direction (all 0 = output)

# ── TCP ──────────────────────────────────────────────────────────────────────
TCP_PORT            = 9999
CAMERA_PACKET_BYTES = 48
FRAME_ACK_PULSE_S   = 0.001

# ── default camera ───────────────────────────────────────────────────────────
DEFAULT_CAMERA = [
    1.0, 0.0, 0.0,
    0.0, 1.0, 0.0,
    0.0, 0.0, -1.0,
    0.0, 0.15, 4.5,
]

# ─────────────────────────────────────────────────────────────────────────────

def phys_addr(buf):
    return int(getattr(buf, "physical_address", buf.device_address))


def fp32_to_fp27(value):
    bits = struct.unpack(">I", struct.pack(">f", float(value)))[0]
    sign      = (bits >> 31) & 0x1
    exponent  = (bits >> 23) & 0xFF
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
    camera_regs.write(CAMERA_COMMIT_REG, 1)


# ── VDMA ─────────────────────────────────────────────────────────────────────

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


def decode_vdma_status(vdma):
    sr = vdma.read(MM2S_DMASR)
    cr = vdma.read(MM2S_DMACR)
    halted    = bool(sr & 0x01)
    idle      = bool(sr & 0x02)
    int_err   = bool(sr & 0x10)
    slv_err   = bool(sr & 0x20)
    dec_err   = bool(sr & 0x40)
    any_err   = int_err or slv_err or dec_err
    err_str   = f"INT={int_err} SLV={slv_err} DEC={dec_err}" if any_err else "OK"
    return (
        f"VDMA DMACR=0x{cr:08x} DMASR=0x{sr:08x} | "
        f"halted={halted} idle={idle} errors={err_str}"
    ), any_err


# ── GPIO ─────────────────────────────────────────────────────────────────────

def read_gpio(gpio):
    """Returns (raw, frame_ready_valid, frame_ready_bank)."""
    raw = gpio.read(GPIO_DATA)
    return raw, bool((raw >> 1) & 1), bool(raw & 1)


# ── startup selftest ─────────────────────────────────────────────────────────

def startup_selftest(camera_regs, vdma, gpio, frame0_addr, frame1_addr):
    print()
    print("=" * 60)
    print("HARDWARE SELFTEST")
    print("=" * 60)

    # GPIO
    raw, frv, frb = read_gpio(gpio)
    gpio_tri  = gpio.read(GPIO_TRI)
    gpio2_tri = gpio.read(GPIO2_TRI)
    gpio2_dat = gpio.read(GPIO2_DATA)
    print(f"  GPIO  DATA =0x{raw:08x}  frame_ready_valid={frv}  frame_ready_bank={frb}")
    print(f"  GPIO  TRI  =0x{gpio_tri:08x}  (should be 0xFFFFFFFF for all-input)")
    print(f"  GPIO2 DATA =0x{gpio2_dat:08x}")
    print(f"  GPIO2 TRI  =0x{gpio2_tri:08x}  (should be 0x00000000 for all-output)")
    if gpio_tri != 0xFFFFFFFF:
        print("  [WARN] GPIO TRI wrong — direction register not set correctly")
    if gpio2_tri != 0x00000000:
        print("  [WARN] GPIO2 TRI wrong — frame_ack may not drive output")

    # VDMA
    vdma_status, vdma_err = decode_vdma_status(vdma)
    print(f"  {vdma_status}")
    addr1 = vdma.read(MM2S_START_ADDR_1)
    addr2 = vdma.read(MM2S_START_ADDR_2)
    stride = vdma.read(MM2S_STRIDE)
    hsize  = vdma.read(MM2S_HSIZE)
    frmstore = vdma.read(MM2S_FRMSTORE)
    print(f"  VDMA ADDR1=0x{addr1:08x} (expect 0x{frame0_addr:08x})  match={addr1==frame0_addr}")
    print(f"  VDMA ADDR2=0x{addr2:08x} (expect 0x{frame1_addr:08x})  match={addr2==frame1_addr}")
    print(f"  VDMA STRIDE=0x{stride:08x} HSIZE=0x{hsize:08x} FRMSTORE={frmstore}")
    if vdma_err:
        print("  [ERROR] VDMA has error bits set — DMA may not run")
    if addr1 != frame0_addr or addr2 != frame1_addr:
        print("  [ERROR] VDMA start addresses wrong — frame buffer mismatch")

    # Camera regs: write test pattern then read back
    print("  Camera reg write/readback:")
    test_val = fp32_to_fp27(1.0)
    camera_regs.write(0, test_val)
    readback = camera_regs.read(0)
    if readback == test_val:
        print(f"    reg[0] write=0x{test_val:07x} readback=0x{readback:07x}  MATCH")
    else:
        print(f"    reg[0] write=0x{test_val:07x} readback=0x{readback:07x}  MISMATCH")
        print("    [WARN] Camera reg readback failed — IP may be write-only (OK if AXI-lite slave)")

    # Camera frame base regs
    fb0 = camera_regs.read(FRAME_BASE0_REG)
    fb1 = camera_regs.read(FRAME_BASE1_REG)
    print(f"  Camera FRAME_BASE0=0x{fb0:08x} (expect 0x{frame0_addr:08x})  match={fb0==frame0_addr}")
    print(f"  Camera FRAME_BASE1=0x{fb1:08x} (expect 0x{frame1_addr:08x})  match={fb1==frame1_addr}")
    if fb0 != frame0_addr or fb1 != frame1_addr:
        print("  [ERROR] Frame base regs wrong — PL won't write to correct buffers")

    print("=" * 60)
    print()


# ── frame ack ────────────────────────────────────────────────────────────────

def service_frame_ready(gpio, vdma, ack_state, frame_stats):
    now = time.monotonic()
    raw, frv, frb = read_gpio(gpio)

    if ack_state["active"]:
        if now >= ack_state["release_at"]:
            gpio.write(GPIO2_DATA, 0)
            ack_state["active"] = False
        return

    if frv:
        set_display_bank(vdma, int(frb))
        gpio.write(GPIO2_DATA, 1)
        ack_state["active"] = True
        ack_state["release_at"] = now + FRAME_ACK_PULSE_S

        # frame stats
        frame_stats["count"] += 1
        if frame_stats["first_frame_time"] is None:
            frame_stats["first_frame_time"] = now
            elapsed = now - frame_stats["start_time"]
            print(f"[FRAME] First frame received after {elapsed:.2f}s  bank={frb}")
        elif (frame_stats["count"] % 30) == 0:
            elapsed = now - frame_stats["first_frame_time"]
            fps = frame_stats["count"] / elapsed if elapsed > 0 else 0
            print(f"[FRAME] count={frame_stats['count']}  avg_fps={fps:.2f}  bank={frb}")


# ── TCP helpers ──────────────────────────────────────────────────────────────

def recv_exact(conn, n, on_timeout=None):
    data = bytearray()
    while len(data) < n:
        try:
            chunk = conn.recv(n - len(data))
        except socket.timeout:
            if on_timeout:
                on_timeout()
            continue
        if not chunk:
            return None
        data.extend(chunk)
    return bytes(data)


# ── main ─────────────────────────────────────────────────────────────────────

def main():
    print("Initialising MMIO...")
    camera_regs = MMIO(CAMERA_REG_BASE, SPAN)
    vdma        = MMIO(VDMA_BASE,       SPAN)
    gpio        = MMIO(GPIO_BASE,       SPAN)

    print("Allocating frame buffers...")
    frame0 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    frame1 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    frame0[:] = 0
    frame1[:] = 0
    f0_addr = phys_addr(frame0)
    f1_addr = phys_addr(frame1)
    print(f"  frame0 phys=0x{f0_addr:08x}")
    print(f"  frame1 phys=0x{f1_addr:08x}")

    # GPIO direction
    gpio.write(GPIO_TRI,  0xFFFFFFFF)   # channel 1 all input
    gpio.write(GPIO2_TRI, 0x00000000)   # channel 2 all output
    gpio.write(GPIO2_DATA, 0)

    # Camera regs + VDMA
    write_camera_values(camera_regs, DEFAULT_CAMERA)
    camera_regs.write(FRAME_BASE0_REG, f0_addr)
    camera_regs.write(FRAME_BASE1_REG, f1_addr)
    print("Initialising VDMA...")
    init_vdma(vdma, f0_addr, f1_addr)
    time.sleep(0.1)   # let VDMA settle

    # Self-test dumps all registers so you can see what's wrong
    startup_selftest(camera_regs, vdma, gpio, f0_addr, f1_addr)

    ack_state  = {"active": False, "release_at": 0.0}
    frame_stats = {
        "count": 0,
        "first_frame_time": None,
        "start_time": time.monotonic(),
    }
    no_frame_warn_at = time.monotonic() + 15.0
    no_frame_warned  = False

    print(f"Waiting for TCP camera controller on port {TCP_PORT}...")
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", TCP_PORT))
    server.listen(1)
    server.settimeout(0.5)

    try:
        while True:
            # Warn if no frame has appeared in 15 s (likely pipeline stuck)
            if not no_frame_warned and frame_stats["first_frame_time"] is None:
                if time.monotonic() >= no_frame_warn_at:
                    no_frame_warned = True
                    raw, frv, frb = read_gpio(gpio)
                    vdma_s, _ = decode_vdma_status(vdma)
                    print()
                    print("[WARN] No frame_ready_valid after 15 s — render pipeline may be stuck")
                    print(f"  GPIO raw=0x{raw:08x}  frame_ready_valid={frv}")
                    print(f"  {vdma_s}")
                    print("  Possible causes:")
                    print("    - Wrong bitstream loaded (check .bit file)")
                    print("    - HWH address mismatch (check CAMERA_REG_BASE / GPIO_BASE / VDMA_BASE)")
                    print("    - frame_base_valid never went high (frame0/1 addr still 0 in PL)")
                    print("    - dispatch_enable never set (check frame_base registers above)")
                    print()

            try:
                conn, addr = server.accept()
            except socket.timeout:
                service_frame_ready(gpio, vdma, ack_state, frame_stats)
                continue

            print(f"Camera controller connected from {addr}")
            conn.settimeout(0.5)
            packet_count = 0
            last_status_t = [time.monotonic()]

            def on_timeout():
                service_frame_ready(gpio, vdma, ack_state, frame_stats)
                now = time.monotonic()
                if now - last_status_t[0] >= 2.0:
                    last_status_t[0] = now
                    raw, frv, frb = read_gpio(gpio)
                    vs, _ = decode_vdma_status(vdma)
                    print(f"  [idle] GPIO=0x{raw:08x} frv={frv} frb={frb}  {vs}")

            with conn:
                while True:
                    packet = recv_exact(conn, CAMERA_PACKET_BYTES, on_timeout)
                    if packet is None:
                        print("Camera controller disconnected")
                        service_frame_ready(gpio, vdma, ack_state, frame_stats)
                        break
                    write_camera_values(camera_regs, struct.unpack("<12f", packet))
                    service_frame_ready(gpio, vdma, ack_state, frame_stats)
                    packet_count += 1

    finally:
        server.close()
        frame0.freebuffer()
        frame1.freebuffer()


if __name__ == "__main__":
    main()
