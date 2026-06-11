'''
SCRIPT FOR PYNQ BOARD: OVERLAY + IMU TO DETERMINE LOOKAT MATRIX
Gets IMU values, like Arduino: computes lookat from this, ie the orbit of the camera
Also gets audio data from computer via TCP
'''


import socket
import struct
import threading
import numpy as np
# import sounddevice as sd
from pynq import Overlay, MMIO


#mmio
AXI_BASE_ADDR = 0x43C00000
AXI_SPAN = 0x1000

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

'''
writes regs 0-11 once at startup
'''
def write_default_camera(mmio):
    #identity lookat mtx: right = [1,0,0], up = [0,1,0], forward = [0,0,-1]
    defaults = [
        1.0, 0.0, 0.0,  #right vect (x)
        0.0, 1.0, 0.0, #up vec (y)
        0.0, 0.0, -1.0, #forward vec (z)
        0.0, 0.15, 4.5 # cam origin xyz
    ]
    for i,v in enumerate (defaults): #enumerate gives pair (index, value). i is posn, v is float at that psn
        mmio.write(i*4, fp32_to_fp27(v)) #


#registers 0-11 = camera. Sdf_params start at register 12. each reg is 4 bytes. So byte offset = reg_index*4
            
def tcp_thread(mmio):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(("0.0.0.0", 9998))
    server.listen(1)
    print("waiting for sdf_params + camera pos (from audio) conn...")
    conn, addr = server.accept()
    print("tcp connected: " , addr)
    while True:
        data=conn.recv(44) # expecting 11 floats, the params + mov of camera
        if len(data) != 44: # 11 params
            continue
        values = struct.unpack("11f", data) #interpret these bytes as 11 floats. Deserializes TCP back to python floats
        for i,v in enumerate (values):
            mmio.write((9+i)*4, fp32_to_fp27(v))  

#this thread is not TCP, it's pure GPIO
'''
imu controls lookat matrix: get 9 values for the 3*3 lookat matrix
'''
def imu_thread (mmio):
    #placeholder for IMU GPIO readings code. 
    
    defaults = [1.0, 0.0, 0.0,
                0.0, 1.0, 0.0,
                0.0, 0.0, -1.0]
    for i,v in enumerate (defaults):
        mmio.write(i*4, fp32_to_fp27(v))
        
#.?
stop_event = threading.Event()

#unclear
def run(music_on):
    mmio = MMIO(AXI_BASE_ADDR, AXI_SPAN)
    if music_on:
        t = threading.Thread(target=tcp_thread, args=(mmio,), daemon=True)
        t.start()
    write_default_camera(mmio)
    imu_thread(mmio)
    input("Press Enter to return to menu...")
    stop_event.set()
    stop_event.clear()

#unclear
if __name__ == "__main__":
    ol = Overlay("Bitstream_Handoff/scaffold.bit")
    run(music_on=True)
        


