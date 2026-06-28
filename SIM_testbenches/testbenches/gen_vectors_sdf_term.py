import struct
import math
import random

def float_to_int32(f):
    return struct.unpack('>I', struct.pack('>f', f))[0]

def int32_to_float(i):
    return struct.unpack('>f', struct.pack('>I', i))[0]

def float32_to_float27(f):
    i = float_to_int32(f)
    sign = (i >> 31) & 0x1
    exp = (i >> 23) & 0xFF
    mantissa = (i & 0x7FFFFF) >> 5
    if exp == 0xFF and (i & 0x7FFFFF) != 0 and mantissa == 0:
        mantissa = 1
    return (sign << 26) | (exp << 18) | mantissa

def float27_to_float32(val27):
    sign = (val27 >> 26) & 0x1
    exp = (val27 >> 18) & 0xFF
    mantissa = val27 & 0x3FFFF
    i32 = (sign << 31) | (exp << 23) | (mantissa << 5)
    return int32_to_float(i32)

def generate_vectors():
    with open("test_vectors_sdf_term.hex", "w") as f:
        for _ in range(200):
            vx = random.uniform(-10.0, 10.0)
            vy = random.uniform(-10.0, 10.0)
            vz = random.uniform(-10.0, 10.0)
            
            val_x = float32_to_float27(vx)
            val_y = float32_to_float27(vy)
            val_z = float32_to_float27(vz)
            
            vx_f = float27_to_float32(val_x)
            vy_f = float27_to_float32(val_y)
            vz_f = float27_to_float32(val_z)
            
            cx = max(vx_f, 0.0)
            cy = max(vy_f, 0.0)
            cz = max(vz_f, 0.0)
            
            length = math.sqrt(cx*cx + cy*cy + cz*cz)
            clamped = min(max(vx_f, max(vy_f, vz_f)), 0.0)
            
            res = length + clamped
            
            val_res = float32_to_float27(res)
            
            f.write(f"{val_x:07X}_{val_y:07X}_{val_z:07X}_{val_res:07X}\n")

if __name__ == "__main__":
    generate_vectors()
