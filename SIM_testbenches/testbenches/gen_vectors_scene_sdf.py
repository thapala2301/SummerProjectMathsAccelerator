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
    with open("test_vectors_scene_sdf.hex", "w") as f:
        b_fp = 1.0
        e_fp = float27_to_float32(0x01F0CCCD)
        
        for i in range(250):
            # Normal
            if i < 200:
                px = random.uniform(-5.0, 5.0)
                py = random.uniform(-5.0, 5.0)
                pz = random.uniform(-5.0, 5.0)
            # Edges
            elif i < 210:
                px = random.uniform(1e3, 1e4)
                py = random.uniform(1e3, 1e4)
                pz = random.uniform(1e3, 1e4)
            elif i < 230:
                px = b_fp
                py = 0.0
                pz = 0.0
            else:
                px = b_fp + 1e-4
                py = random.uniform(-b_fp, b_fp)
                pz = random.uniform(-b_fp, b_fp)
            
            val_x = float32_to_float27(px)
            val_y = float32_to_float27(py)
            val_z = float32_to_float27(pz)
            
            px_f = float27_to_float32(val_x)
            py_f = float27_to_float32(val_y)
            pz_f = float27_to_float32(val_z)
            
            # Stage A
            px_intermed = abs(px_f) - b_fp
            py_intermed = abs(py_f) - b_fp
            pz_intermed = abs(pz_f) - b_fp
            
            # Stage B
            px_intermed2 = px_intermed + e_fp
            py_intermed2 = py_intermed + e_fp
            pz_intermed2 = pz_intermed + e_fp
            
            qx = abs(px_intermed2) - e_fp
            qy = abs(py_intermed2) - e_fp
            qz = abs(pz_intermed2) - e_fp
            
            def sdf_term(v0, v1, v2):
                cx = max(v0, 0.0)
                cy = max(v1, 0.0)
                cz = max(v2, 0.0)
                length = math.sqrt(cx*cx + cy*cy + cz*cz)
                clamped = min(max(v0, max(v1, v2)), 0.0)
                return length + clamped
            
            term1 = sdf_term(px_intermed, qy, qz)
            term2 = sdf_term(qx, py_intermed, qz)
            term3 = sdf_term(qx, qy, pz_intermed)
            
            res = min(min(term1, term2), term3)
            val_res = float32_to_float27(res)
            
            f.write(f"{val_x:07X}_{val_y:07X}_{val_z:07X}_{val_res:07X}\n")

if __name__ == "__main__":
    generate_vectors()
