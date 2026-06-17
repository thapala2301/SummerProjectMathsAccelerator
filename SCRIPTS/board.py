import socket
import struct
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

CAMERA_PACKET_BYTES = 48
TCP_PORT = 9999

FRAME_BASE0_REG = 12 * 4
FRAME_BASE1_REG = 13 * 4
CAMERA_COMMIT_REG = 14 * 4

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
FRAME_ACK_PULSE_S = 0.001

DEBUG_STATES = {
    0: "idle/no frame",
    1: "dispatching",
    2: "waiting for march completions",
    3: "feedback-loop stall",
    4: "dispatch blocked",
    5: "DDR writer backpressure/drain",
    6: "frame ready / waiting for ack",
}

DEFAULT_CAMERA = [
    1.0, 0.0, 0.0,
    0.0, 1.0, 0.0,
    0.0, 0.0, -1.0,
    0.0, 0.15, 4.5,
]


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
    camera_regs.write(CAMERA_COMMIT_REG, 1)


def reset_vdma(vdma):
    vdma.write(MM2S_DMACR, 0)
    time.sleep(0.01)
    vdma.write(MM2S_DMACR, DMACR_RESET)

    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        if (vdma.read(MM2S_DMACR) & DMACR_RESET) == 0:
            return
        time.sleep(0.001)

    raise RuntimeError("VDMA reset timed out; power-cycle the board")


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
    halted   = bool(sr & 0x01)
    idle     = bool(sr & 0x02)
    int_err  = bool(sr & 0x10)
    slv_err  = bool(sr & 0x20)
    dec_err  = bool(sr & 0x40)
    err_str  = f"INT={int_err} SLV={slv_err} DEC={dec_err}" if (int_err or slv_err or dec_err) else "OK"
    return f"VDMA DMACR=0x{cr:08x} DMASR=0x{sr:08x} halted={halted} idle={idle} errors={err_str}"


def startup_selftest(camera_regs, vdma, gpio, frame0_addr, frame1_addr):
    print()
    print("=" * 60)
    print("HARDWARE SELFTEST")
    print("=" * 60)

    raw = gpio.read(GPIO_DATA)
    frv = bool((raw >> 1) & 1)
    frb = bool(raw & 1)
    tri  = gpio.read(GPIO_TRI)
    tri2 = gpio.read(GPIO2_TRI)
    print(f"  GPIO DATA=0x{raw:08x}  frame_ready_valid={frv}  frame_ready_bank={frb}")
    print(f"  GPIO TRI =0x{tri:08x}  (want 0xFFFFFFFF)")
    print(f"  GPIO2 TRI=0x{tri2:08x}  (want 0x00000000)")
    if tri != 0xFFFFFFFF:
        print("  [WARN] GPIO TRI wrong — reads will be garbage")
    if tri2 != 0x00000000:
        print("  [WARN] GPIO2 TRI wrong — frame_ack not driving output")

    print(f"  {decode_vdma_status(vdma)}")
    a1 = vdma.read(MM2S_START_ADDR_1)
    a2 = vdma.read(MM2S_START_ADDR_2)
    print(f"  VDMA ADDR1=0x{a1:08x} expect=0x{frame0_addr:08x} match={a1==frame0_addr}")
    print(f"  VDMA ADDR2=0x{a2:08x} expect=0x{frame1_addr:08x} match={a2==frame1_addr}")
    if a1 != frame0_addr or a2 != frame1_addr:
        print("  [ERROR] VDMA frame addresses wrong")

    fb0 = camera_regs.read(FRAME_BASE0_REG)
    fb1 = camera_regs.read(FRAME_BASE1_REG)
    print(f"  CAM FRAME_BASE0=0x{fb0:08x} expect=0x{frame0_addr:08x} match={fb0==frame0_addr}")
    print(f"  CAM FRAME_BASE1=0x{fb1:08x} expect=0x{frame1_addr:08x} match={fb1==frame1_addr}")
    if fb0 != frame0_addr or fb1 != frame1_addr:
        print("  [ERROR] Camera frame base regs wrong — PL writes to wrong memory, dispatch never starts")

    print("=" * 60)
    print()


_frame_stats = {"count": 0, "first_t": None, "start_t": time.monotonic()}


def service_frame_ready(gpio, vdma, ack_state):
    now = time.monotonic()
    status = gpio.read(GPIO_DATA)
    ready_bank = status & 1
    ready_valid = (status >> 1) & 1

    if ack_state["active"]:
        if now >= ack_state["release_at"]:
            gpio.write(GPIO2_DATA, 0)
            ack_state["active"] = False
        return

    if ready_valid:
        set_display_bank(vdma, ready_bank)
        gpio.write(GPIO2_DATA, 1)
        ack_state["active"] = True
        ack_state["release_at"] = now + FRAME_ACK_PULSE_S

        _frame_stats["count"] += 1
        if _frame_stats["first_t"] is None:
            _frame_stats["first_t"] = now
            print(f"[FRAME] First frame after {now - _frame_stats['start_t']:.2f}s  bank={ready_bank}")
        elif (_frame_stats["count"] % 30) == 0:
            fps = _frame_stats["count"] / (now - _frame_stats["first_t"])
            print(f"[FRAME] count={_frame_stats['count']}  fps={fps:.2f}  bank={ready_bank}")


def read_debug_state(gpio):
    value = gpio.read(GPIO_DATA)
    # NOTE: only bits 0-1 are wired in the BD (bank, valid). Bits 2+ are 0.
    frv = bool((value >> 1) & 1)
    frb = bool(value & 1)
    return value, frv, frb


def format_debug_status(gpio):
    value, frv, frb = read_debug_state(gpio)
    frames = _frame_stats["count"]
    return f"GPIO=0x{value:08x} frame_ready_valid={frv} frame_ready_bank={frb} frames_rendered={frames}"


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


def main():
    camera_regs = MMIO(CAMERA_REG_BASE, SPAN)
    vdma = MMIO(VDMA_BASE, SPAN)
    gpio = MMIO(GPIO_BASE, SPAN)

    frame0 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    frame1 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    frame0[:] = 0
    frame1[:] = 0
    frame0_addr = phys_addr(frame0)
    frame1_addr = phys_addr(frame1)

    ack_state = {"active": False, "release_at": 0.0}
    gpio.write(GPIO_TRI, 0xFFFFFFFF)
    gpio.write(GPIO2_TRI, 0x00000000)
    gpio.write(GPIO2_DATA, 0)

    write_camera_values(camera_regs, DEFAULT_CAMERA)
    camera_regs.write(FRAME_BASE0_REG, frame0_addr)
    camera_regs.write(FRAME_BASE1_REG, frame1_addr)
    init_vdma(vdma, frame0_addr, frame1_addr)
    time.sleep(0.1)

    print(f"FRAME0 phys = 0x{frame0_addr:08x}")
    print(f"FRAME1 phys = 0x{frame1_addr:08x}")
    startup_selftest(camera_regs, vdma, gpio, frame0_addr, frame1_addr)
    print(format_debug_status(gpio))
    print(f"Waiting for camera controller on TCP port {TCP_PORT}")
    _frame_stats["start_t"] = time.monotonic()
    no_frame_warn_at = time.monotonic() + 15.0
    no_frame_warned = False

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", TCP_PORT))
    server.listen(1)
    server.settimeout(0.5)

    try:
        while True:
            if not no_frame_warned and _frame_stats["first_t"] is None and time.monotonic() >= no_frame_warn_at:
                no_frame_warned = True
                raw = gpio.read(GPIO_DATA)
                print()
                print("[WARN] No frame after 15s — render pipeline stuck")
                print(f"  GPIO raw=0x{raw:08x}  frame_ready_valid={bool((raw>>1)&1)}")
                print(f"  {decode_vdma_status(vdma)}")
                print("  Likely: wrong bitstream, wrong address map, or frame_base regs 0 in PL")
                print()

            try:
                conn, addr = server.accept()
            except socket.timeout:
                service_frame_ready(gpio, vdma, ack_state)
                continue

            print("Connected at:", addr)
            conn.settimeout(0.5)

            with conn:
                packet_count = 0
                last_idle_status = [time.monotonic()]

                def handle_timeout():
                    service_frame_ready(gpio, vdma, ack_state)
                    now = time.monotonic()
                    if now - last_idle_status[0] >= 1.0:
                        print(f"Waiting for camera packet; {format_debug_status(gpio)}")
                        last_idle_status[0] = now

                while True:
                    packet = recv_exact(conn, CAMERA_PACKET_BYTES, handle_timeout)
                    if packet is None:
                        service_frame_ready(gpio, vdma, ack_state)
                        print(format_debug_status(gpio))
                        print("Camera controller disconnected")
                        break

                    write_camera_values(camera_regs, struct.unpack("<12f", packet))
                    service_frame_ready(gpio, vdma, ack_state)
                    packet_count += 1
                    if packet_count == 1 or (packet_count % 30) == 0:
                        print(f"Camera packets: {packet_count}; {format_debug_status(gpio)}")
    finally:
        server.close()
        frame0.freebuffer()
        frame1.freebuffer()


if __name__ == "__main__":
    main()
