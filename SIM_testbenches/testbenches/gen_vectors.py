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
        for _ in range(300):
            a = random.uniform(-1000.0, 1000.0)
            b = random.uniform(-1000.0, 1000.0)
            c = random.uniform(-1000.0, 1000.0)
            
            # Edges
            if random.random() < 0.1: a = float('inf')
            if random.random() < 0.1: b = float('inf')
            if random.random() < 0.1: a = float('-inf')
            if random.random() < 0.1: b = float('-inf')
            if random.random() < 0.1: a = float('nan')
            if random.random() < 0.1: b = float('nan')
            if random.random() < 0.1: a = 0.0
            if random.random() < 0.1: b = 0.0
            if random.random() < 0.05: a = -0.0
            if random.random() < 0.05: b = -0.0
            if random.random() < 0.05: a = 1e-38
            if random.random() < 0.05: b = 1e-38

            # Precision
            val_a_27 = float32_to_float27(a)
            val_b_27 = float32_to_float27(b)
            val_c_27 = float32_to_float27(c)
            
            a_f = float27_to_float32(val_a_27)
            b_f = float27_to_float32(val_b_27)
            c_f = float27_to_float32(val_c_27)

            for op in range(10):
                val_a_hex = val_a_27
                if op == 0: res = a_f + b_f
                elif op == 1: res = a_f - b_f
                elif op == 2: res = a_f * b_f
                elif op == 3: res = abs(a_f)
                elif op == 4: res = -a_f
                elif op == 5: res = min(a_f, b_f)
                elif op == 6: res = max(a_f, b_f)
                elif op == 7:
                    res = 1.0 / math.sqrt(a_f) if a_f > 0 else float('nan')
                elif op == 8:
                    res = math.sqrt(a_f*a_f + b_f*b_f + c_f*c_f)
                elif op == 9:
                    int_val = random.randint(-0x80000000, 0x7FFFFFFF)
                    res = int_val / float(1 << 29)
                    val_a_hex = int_val & 0xFFFFFFFF
                
                try:
                    val_res_27 = float32_to_float27(res)
                except:
                    val_res_27 = 0x3FFFFFF
                
                f.write(f"{op:02X}_{val_a_hex:08X}_{val_b_27:08X}_{val_c_27:08X}_{val_res_27:08X}\n")

if __name__ == "__main__":
    generate_vectors()
