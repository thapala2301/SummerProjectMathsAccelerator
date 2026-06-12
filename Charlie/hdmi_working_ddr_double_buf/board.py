import socket
import struct
import time
from pynq import MMIO

CAMERA_REG_BASE = 0x43C00000
VDMA_BASE = 0x43000000
GPIO_BASE = 0x41200000
SPAN = 0x10000

CAMERA_PACKET_BYTES = 48
VDMA_PARK_PTR = 0x28
GPIO_DATA = 0x00
GPIO2_DATA = 0x08

camera_regs = MMIO(CAMERA_REG_BASE, SPAN)
vdma = MMIO(VDMA_BASE, SPAN)
gpio = MMIO(GPIO_BASE, SPAN)

frame_ack_active = False
frame_ack_count = 0
frame_ack_last_status = 0


def set_display_bank(bank):
    bank &= 1
    vdma.write(VDMA_PARK_PTR, bank | (bank << 8))


def service_frame_ready():
    global frame_ack_active, frame_ack_count, frame_ack_last_status

    status = gpio.read(GPIO_DATA)
    frame_ack_last_status = status
    ready_bank = status & 1
    ready_valid = (status >> 1) & 1

    if frame_ack_active:
        if not ready_valid:
            gpio.write(GPIO2_DATA, 0)
            frame_ack_active = False
        return

    if ready_valid:
        set_display_bank(ready_bank)
        gpio.write(GPIO2_DATA, 1)
        frame_ack_active = True
        frame_ack_count += 1

def fp32_to_fp27(value):
    # struct.pack(">f", value) converts the float to 4 big-endian bytes
    # struct.unpack(">I", ...) converts those bytes to an unsigned 32-bit int
    # struct.unpack returns a tuple, so use [0]
    bits = struct.unpack(">I", struct.pack(">f", float(value)))[0]
    sign = (bits >> 31) & 0x1
    exponent = (bits >> 23) & 0xFF
    fraction23 = bits & 0x7FFFFF

    # exponent == 0 is a special case
    # It represents zero or a subnormal number, which we simplify to signed zero
    # Only the sign bit in position 26
    if exponent == 0:
        return sign << 26

    # exponent == 0xFF is also a special case
    # It represents infinity if fraction23 == 0 and NaN if fraction23 != 0
    # We keep the sign bit in position 26, keep exp = 255 and have one bit in the fraction which is 1 if it's NaN
    if exponent == 0xFF:
        return (sign << 26) | (exponent << 18) | (1 if fraction23 else 0)

    fraction18 = (fraction23 + 0x10) >> 5
    if fraction18 >= (1 << 18):
        fraction18 = 0
        exponent = min(exponent + 1, 0xFF)

    return (sign << 26) | ((exponent & 0xFF) << 18) | fraction18

def write_camera_packet(data):
    values = struct.unpack("<12f", data)

    for index, value in enumerate(values):
        camera_regs.write(index * 4, fp32_to_fp27(value))

# AF_INET = IPv4, SOCK_STREAM = TCP
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.setblocking(False)

server.bind(("0.0.0.0", 9999))
server.listen(1)

conn = None
rx_buffer = bytearray()
print("waiting for connection...")

while True:
    service_frame_ready()

    if conn is None:
        try:
            conn, addr = server.accept()
            conn.setblocking(False)
            rx_buffer.clear()
            print("Connected at:", addr)
        except BlockingIOError:
            pass
    else:
        try:
            chunk = conn.recv(4096)
            if not chunk:
                print("client disconnected")
                conn.close()
                conn = None
            else:
                rx_buffer.extend(chunk)
                packet_count = len(rx_buffer) // CAMERA_PACKET_BYTES

                if packet_count:
                    packet_start = (packet_count - 1) * CAMERA_PACKET_BYTES
                    packet = bytes(rx_buffer[packet_start:packet_start + CAMERA_PACKET_BYTES])
                    rx_buffer.clear()
                    write_camera_packet(packet)
        except BlockingIOError:
            pass
        except ConnectionResetError:
            print("client disconnected")
            conn.close()
            conn = None

    service_frame_ready()
    time.sleep(0.0005)

if conn is not None:
    try:
        conn.close()
    except OSError:
        pass
