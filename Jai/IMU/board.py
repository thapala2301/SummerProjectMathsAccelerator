import socket
import struct
from pynq import MMIO

AXI_BASE_ADDR = 0x43C00000
AXI_SPAN = 0x1000

mmio = MMIO(AXI_BASE_ADDR, AXI_SPAN)

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

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

server.bind(("0.0.0.0", 9999))
server.listen(1)

print("waiting for connection...")

conn, addr = server.accept()

print("Connected at:", addr)

while True:
    data = conn.recv(48)

    if len(data) != 48:
        print("Invalid data received")
        continue

    values = struct.unpack("12f", data)

    for index, value in enumerate(values):
        mmio.write(index * 4, fp32_to_fp27(value))
