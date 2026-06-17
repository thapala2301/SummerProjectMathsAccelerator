import socket
import struct
from pynq import MMIO

AXI_BASE_ADDR = 0x43C00000
AXI_SPAN = 0x1000

mmio = MMIO(AXI_BASE_ADDR, AXI_SPAN)

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

# AF_INET = IPv4, SOCK_STREAM = TCP
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

server.bind(("0.0.0.0", 9999))
server.listen(1)

print("waiting for connection...")

conn, addr = server.accept()

print("Connected at:", addr)

while True:
    # 12 x 4 bytes = 48 bytes
    data = conn.recv(48)

    if len(data) != 48:
        print("Invalid data received")
        continue

    values = struct.unpack("12f", data)

    for index, value in enumerate(values):
        mmio.write(index * 4, fp32_to_fp27(value))
