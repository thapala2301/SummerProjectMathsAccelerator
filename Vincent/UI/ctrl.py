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
SHIFT_PX = 0   # set to match selector.py SHIFT_PX — shifts framebuffer origin to correct monitor's right-shift

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


def read_debug_state(gpio):
    value = gpio.read(GPIO_DATA)
    state = (value >> 4) & 0xF
    top_flags = {
        "frame_ready_valid": bool((value >> 1) & 1),
        "frame_ready_bank": bool(value & 1),
        "dispatch_enable": bool((value >> 2) & 1),
        "frame_drain_wait": bool((value >> 3) & 1),
    }
    dispatch_hi = (value >> 8) & 0xFF
    done_hi = (value >> 16) & 0xFF
    frame_counter = (value >> 24) & 0xFF
    return value, state, DEBUG_STATES.get(state, "unknown"), top_flags, dispatch_hi, done_hi, frame_counter


def format_debug_status(gpio):
    value, state, state_name, top_flags, dispatch_hi, done_hi, frame_counter = read_debug_state(gpio)
    active_top = [name for name, enabled in top_flags.items() if enabled]
    return (
        f"debug=0x{value:08x}; state={state}:{state_name}; "
        f"frame={frame_counter}; dispatch_hi=0x{dispatch_hi:02x}; done_hi=0x{done_hi:02x}; "
        f"top={','.join(active_top) if active_top else '-'}; "
    )


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

    print(f"FRAME0 phys = 0x{frame0_addr:08x}")
    print(f"FRAME1 phys = 0x{frame1_addr:08x}")
    print(format_debug_status(gpio))
    print(f"Waiting for camera controller on TCP port {TCP_PORT}")

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", TCP_PORT))
    server.listen(1)
    server.settimeout(0.5)

    try:
        while True:
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


def run(stop_event=None):
    camera_regs = MMIO(CAMERA_REG_BASE, SPAN)
    vdma        = MMIO(VDMA_BASE, SPAN)
    gpio        = MMIO(GPIO_BASE, SPAN)

    frame0 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    frame1 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    frame0[:] = 0x00FFFFFF  # white — confirms display is working
    frame1[:] = 0x00FFFFFF
    frame0_addr = phys_addr(frame0) + SHIFT_PX * 4
    frame1_addr = phys_addr(frame1) + SHIFT_PX * 4

    # Write frame bases first — ray marcher starts on bitstream load and will
    # deadlock if it tries to write to address 0 (register reset value).
    camera_regs.write(FRAME_BASE0_REG, frame0_addr)
    camera_regs.write(FRAME_BASE1_REG, frame1_addr)

    ack_state = {"active": False, "release_at": 0.0}
    gpio.write(GPIO_TRI,   0xFFFFFFFF)
    gpio.write(GPIO2_TRI,  0x00000000)
    gpio.write(GPIO2_DATA, 1)   # pulse ack to clear any stuck feedback state
    time.sleep(0.01)
    gpio.write(GPIO2_DATA, 0)

    write_camera_values(camera_regs, DEFAULT_CAMERA)
    init_vdma(vdma, frame0_addr, frame1_addr)
    vdma_sr = vdma.read(MM2S_DMASR)
    print(f"FRAME0=0x{frame0_addr:08x} FRAME1=0x{frame1_addr:08x}")
    print(f"VDMA SR=0x{vdma_sr:08x} ({'HALTED' if vdma_sr & 1 else 'RUNNING'})")
    print(format_debug_status(gpio))

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    server.bind(("0.0.0.0", TCP_PORT))
    server.listen(1)
    server.settimeout(0.5)

    def _should_stop():
        return stop_event is not None and stop_event.is_set()

    try:
        while not _should_stop():
            try:
                conn, addr = server.accept()
            except socket.timeout:
                service_frame_ready(gpio, vdma, ack_state)
                continue
            conn.settimeout(0.5)
            with conn:
                while not _should_stop():
                    packet = recv_exact(conn, CAMERA_PACKET_BYTES,
                                        lambda: service_frame_ready(gpio, vdma, ack_state))
                    if packet is None:
                        service_frame_ready(gpio, vdma, ack_state)
                        break
                    write_camera_values(camera_regs, struct.unpack("<12f", packet))
                    service_frame_ready(gpio, vdma, ack_state)
    finally:
        server.close()
        frame0.freebuffer()
        frame1.freebuffer()

if __name__ == "__main__":
    main()
