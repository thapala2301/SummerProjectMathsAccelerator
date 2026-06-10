'''
Generates map of exponential values for fog in BRAM of PYNQ
we use exp(-dist * fog density), and for different values of dist we compute
that value in FP27
Python generates numbers, pasted into Verilog as BRAM init values
Python computes 256 fog factors. Copied into fog_lut array in palette.sv
initial begin: hw reads fog_lut[dist[25:18]] at runtime

'''
import numpy as np
fog_density = 0.02  #ADAPTIVE TO MUSIC? BC CELL SIZE CHANGES W MUSIC
lut = [0] * 256
for i in range(256):

    dist = 2 ** (i-127)  # distance = 2^true exp
    lut[i] = int(np.clip(np.exp(-fog_density * dist), 0, 1) * 255)
    #np.clip : clamps x to the range [0,1]. if x = 1.00001 due to FP errors clip returns 1
    # if x = -0.00001 clip returns 0 
    #exp(-kd) is always in [0,1] mathematically but clamp for safety

with open("fog_lut.mem", "w") as f:
    for v in lut:
        f.write(f"{v:02X}\n")
