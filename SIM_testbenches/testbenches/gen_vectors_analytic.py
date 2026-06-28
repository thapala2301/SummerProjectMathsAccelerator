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
    raw_mantissa = i & 0x7FFFFF
    mantissa = raw_mantissa >> 5
    if (raw_mantissa & 0x10) != 0:
        mantissa += 1
    if exp == 0xFF and (i & 0x7FFFFF) != 0 and mantissa == 0:
        mantissa = 1
    return (sign << 26) | (exp << 18) | mantissa

def float27_to_float32(val27):
    sign = (val27 >> 26) & 0x1
    exp = (val27 >> 18) & 0xFF
    mantissa = val27 & 0x3FFFF
    i32 = (sign << 31) | (exp << 23) | (mantissa << 5)
    return int32_to_float(i32)




def sdf_sphere(px, py, pz):
    radius = 1.0
    return math.sqrt(px*px + py*py + pz*pz) - radius

def sdf_box(px, py, pz):
    bx, by, bz = 1.0, 0.5, 1.0
    qx = abs(px) - bx
    qy = abs(py) - by
    qz = abs(pz) - bz
    length = math.sqrt(max(qx, 0.0)**2 + max(qy, 0.0)**2 + max(qz, 0.0)**2)
    clamped = min(max(qx, max(qy, qz)), 0.0)
    return length + clamped

def sdf_term(v0, v1, v2):
    cx = max(v0, 0.0)
    cy = max(v1, 0.0)
    cz = max(v2, 0.0)
    length = math.sqrt(cx*cx + cy*cy + cz*cz)
    clamped = min(max(v0, max(v1, v2)), 0.0)
    return length + clamped

def repeat_cell(p):
    abs_p = abs(p)
    if abs_p < 5.0: off = 0.0
    elif abs_p < 15.0: off = 10.0
    elif abs_p < 25.0: off = 20.0
    elif abs_p < 35.0: off = 30.0
    elif abs_p < 45.0: off = 40.0
    elif abs_p < 55.0: off = 50.0
    elif abs_p < 65.0: off = 60.0
    elif abs_p < 75.0: off = 70.0
    elif abs_p < 85.0: off = 80.0
    elif abs_p < 95.0: off = 90.0
    elif abs_p < 105.0: off = 100.0
    else: off = 10.0 * round(abs_p / 10.0)
    return p + off if p < 0 else p - off

def scene_sdf(px, py, pz):
    px = repeat_cell(px)
    py = repeat_cell(py)
    pz = repeat_cell(pz)
    
    b_fp = 1.0
    e_fp = float27_to_float32(0x01F0CCCD)
    px_intermed2 = (abs(px) - b_fp) + e_fp
    py_intermed2 = (abs(py) - b_fp) + e_fp
    pz_intermed2 = (abs(pz) - b_fp) + e_fp
    
    qx = abs(px_intermed2) - e_fp
    qy = abs(py_intermed2) - e_fp
    qz = abs(pz_intermed2) - e_fp
    
    term1 = sdf_term(abs(px) - b_fp, qy, qz)
    term2 = sdf_term(qx, abs(py) - b_fp, qz)
    term3 = sdf_term(qx, qy, abs(pz) - b_fp)
    
    return min(min(term1, term2), term3)


def sdf_capped_torus(px, py, pz):
    sc_x = 0.5
    sc_y = math.sqrt(3) / 2
    ra = 1.0
    rb = 0.3
    abs_px = abs(px)
    dot_pxy = abs_px * sc_x + py * sc_y
    len_pxy = math.sqrt(abs_px**2 + py**2)
    cond = abs_px * sc_y - py * sc_x
    k = len_pxy if cond < 0 else dot_pxy
    dot_pp = px**2 + py**2 + pz**2
    radicand = dot_pp + ra**2 - 2 * ra * k
    return math.sqrt(max(0.0, radicand)) - rb

def sdf_capsule(px, py, pz):
    h = 1.0
    r = 0.3
    len_xz = math.sqrt(px**2 + pz**2)
    qy_raw = abs(py) - h
    qy_clamped = max(qy_raw, 0.0)
    len_q = math.sqrt(len_xz**2 + qy_clamped**2)
    return len_q - r

def sdf_chain_link(px, py, pz):
    chain_r = 2.0
    tube_r = 0.5
    half_h = 0.5
    len_xz = math.sqrt(px**2 + pz**2)
    qx = len_xz - chain_r
    py_top = min(py, half_h)
    qy = max(py_top, -half_h)
    len_q = math.sqrt(qx**2 + qy**2)
    return len_q - tube_r

def sdf_cone(px, py, pz):
    sin_30 = 0.5
    cos_30 = math.sqrt(3) / 2
    neg_py = -py
    len_xz = math.sqrt(px**2 + pz**2)
    dot_qc = len_xz * sin_30 + neg_py * cos_30
    dot_pos = max(dot_qc, 0.0)
    cp_x = dot_pos * sin_30
    cp_y = dot_pos * cos_30
    d_x = len_xz - cp_x
    d_y = neg_py - cp_y
    d_len = math.sqrt(d_x**2 + d_y**2)
    cross = len_xz * cos_30 - neg_py * sin_30
    return -d_len if cross < 0 else d_len

def sdf_cylinder(px, py, pz):
    r = 1.0
    h = 0.5
    len_xz = math.sqrt(px**2 + pz**2)
    dx = len_xz - r
    abs_py = abs(py)
    dy = abs_py - h
    mx = max(dx, 0.0)
    my = max(dy, 0.0)
    inner_max = max(dx, dy)
    inner = min(inner_max, 0.0)
    len_outer = math.sqrt(mx**2 + my**2)
    return len_outer + inner

def sdf_death_star(px, py, pz):
    r_big = 1.5
    r_small = 0.7
    offset = 1.5
    len_big = math.sqrt(px**2 + py**2 + pz**2)
    sdf_big = len_big - r_big
    px_off = px - offset
    len_small = math.sqrt(px_off**2 + py**2 + pz**2)
    sdf_small = len_small - r_small
    return max(sdf_big, -sdf_small)


def sdf_ellipsoid(px, py, pz):
    INV_A = 2.0 / 3.0
    INV_B = 1.0
    INV_C = 4.0 / 3.0
    sx = px * INV_A
    sy = py * INV_B
    sz = pz * INV_C
    length = math.sqrt(sx**2 + sy**2 + sz**2)
    return length - 1.0

def sdf_gyroid(px, py, pz):
    def approx_sin(v):
        return v - (v**3) / 6.0
    def approx_cos(v):
        return 1.0 - (v**2) / 2.0
    sin_px = approx_sin(px)
    cos_py = approx_cos(py)
    sin_py = approx_sin(py)
    cos_pz = approx_cos(pz)
    sin_pz = approx_sin(pz)
    cos_px = approx_cos(px)
    alpha = sin_px * cos_py
    beta = sin_py * cos_pz
    gamma = sin_pz * cos_px
    return (alpha + beta + gamma) * 0.25

def sdf_hyperboloid(px, py, pz):
    INV_A = 1.0
    INV_B = 0.5
    INV_C = 1.0
    sx = px * INV_A
    sz = pz * INV_C
    r_xz = math.sqrt(sx**2 + sz**2)
    sy = py * INV_B
    sy2 = sy**2
    sy2_1 = sy2 + 1.0
    return r_xz - math.sqrt(sy2_1)

def sdf_mandelbulb(px, py, pz):
    r_final = math.sqrt(px**2 + py**2 + pz**2)
    return (r_final - 1.0) * 0.5

def sdf_octahedron(px, py, pz):
    S = 2.0
    recip_sqrt3 = 1.0 / math.sqrt(3.0)
    sum_abs = abs(px) + abs(py) + abs(pz)
    diff = sum_abs - S
    return diff * recip_sqrt3

def sdf_pyramid(px, py, pz):
    M2 = 1.25
    INV_1P5 = 2.0 / 3.0
    INV_SQRT_M2 = 1.0 / math.sqrt(1.25)
    mx = max(abs(px), abs(pz))
    mz = min(abs(px), abs(pz))
    px2 = mx - 0.5
    pz2 = mz - 0.5
    qy = py - 0.5 * px2
    qx_pos = max(pz2, 0.0)
    t_num = qy - 0.5 * pz2
    t_raw = t_num * INV_1P5
    t = max(0.0, min(t_raw, 1.0))
    a = M2 * (qx_pos**2) + (qy**2)
    b_ix = pz2 + 0.5 * t
    b1 = M2 * (b_ix**2)
    b_iy = qy - M2 * t
    b = b1 + (b_iy**2)
    min_ab = min(a, b)
    sqrt_ab = math.sqrt(min_ab) if min_ab > 0 else 0.0
    sdf_mag = sqrt_ab * INV_SQRT_M2
    sign_test = min(pz2, -qy)
    if sign_test < 0:
        return -sdf_mag
    else:
        return sdf_mag


def sdf_round_box(px, py, pz):
    BX = 0.5
    BY = 0.25
    BZ = 0.5
    R = 0.125
    qx = abs(px) - BX
    qy = abs(py) - BY
    qz = abs(pz) - BZ
    box_sdf = sdf_term(qx, qy, qz)
    return box_sdf - R

def sdf_star(px, py, pz):
    FP_HALF = 0.5
    FP_866 = math.sqrt(3) / 2
    FP_TWO = 2.0
    HEIGHT = 0.5
    RADIUS = 1.0
    abs_px = abs(px)
    abs_pz = abs(pz)
    dot_x = abs_px * FP_HALF
    dot_z = abs_pz * FP_866
    dot = dot_x + dot_z
    min_dot = min(dot, 0.0)
    two_dot = min_dot * FP_TWO
    fold_x_sub = two_dot * FP_HALF
    fold_z_sub = two_dot * FP_866
    fx = abs_px - fold_x_sub
    fz = abs_pz - fold_z_sub
    qx = fx - RADIUS
    qz = fz - 0.0
    abs_py = abs(py)
    qy = abs_py - HEIGHT
    return sdf_term(qx, qy, qz)

def sdf_torus(px, py, pz):
    radius_major = 1.0
    radius_minor = 0.35
    len_xz = math.sqrt(px**2 + pz**2)
    qx = len_xz - radius_major
    len_q = math.sqrt(qx**2 + py**2)
    return len_q - radius_minor

def sdf_triangular_prism(px, py, pz):
    H_Z = 1.0
    H_XY = 1.0
    HALF_HXY = 0.5
    abs_pz = abs(pz)
    term1 = abs_pz - H_Z
    abs_px = abs(px)
    side_a = abs_px * (math.sqrt(3) / 2)
    side_b = py * 0.5
    face_dot = side_a + side_b
    neg_py = -py
    inner = max(face_dot, neg_py)
    term2 = inner - HALF_HXY
    return max(term1, term2)

def sdf_twisted_torus(px, py, pz):
    BIG_R = 1.0
    SMALL_R = 0.35
    TWIST = 1.0
    angle = py * TWIST
    angle2 = angle * angle
    angle2_2 = angle2 * 0.5
    cos_a = 1.0 - angle2_2
    angle3 = angle2 * angle
    angle3_6 = angle3 * (1.0 / 6.0)
    sin_a = angle - angle3_6
    px_cos = px * cos_a
    pz_sin = pz * sin_a
    px_sin = px * sin_a
    pz_cos = pz * cos_a
    rx = px_cos - pz_sin
    rz = px_sin + pz_cos
    len_xz = math.sqrt(rx**2 + rz**2)
    qx = len_xz - BIG_R
    len_q = math.sqrt(qx**2 + py**2)
    return len_q - SMALL_R

def sdf_vesica(px, py, pz):
    R = 1.0
    D = 0.5
    px_plus_D = px + D
    px_minus_D = px - D
    len_A = math.sqrt(px_plus_D**2 + py**2 + pz**2)
    len_B = math.sqrt(px_minus_D**2 + py**2 + pz**2)
    sdf_A = len_A - R
    sdf_B = len_B - R
    return max(sdf_A, sdf_B)



SHAPES = {
    "sdf_sphere": sdf_sphere,
    "sdf_box": sdf_box,
    "scene_sdf": scene_sdf,
    "sdf_capped_torus": sdf_capped_torus,
    "sdf_capsule": sdf_capsule,
    "sdf_chain_link": sdf_chain_link,
    "sdf_cone": sdf_cone,
    "sdf_cylinder": sdf_cylinder,
    "sdf_death_star": sdf_death_star,
    "sdf_ellipsoid": sdf_ellipsoid,
    "sdf_gyroid": sdf_gyroid,
    "sdf_hyperboloid": sdf_hyperboloid,
    "sdf_mandelbulb": sdf_mandelbulb,
    "sdf_octahedron": sdf_octahedron,
    "sdf_pyramid": sdf_pyramid,
    "sdf_round_box": sdf_round_box,
    "sdf_star": sdf_star,
    "sdf_torus": sdf_torus,
    "sdf_triangular_prism": sdf_triangular_prism,
    "sdf_twisted_torus": sdf_twisted_torus,
    "sdf_vesica": sdf_vesica
}

def generate_vectors():
    for shape_name, sdf_func in SHAPES.items():
        filename = f"test_vectors_{shape_name}.hex"
        with open(filename, "w") as f:
            for i in range(200):

                if i < 150:
                    px = random.uniform(-5.0, 5.0)
                    py = random.uniform(-5.0, 5.0)
                    pz = random.uniform(-5.0, 5.0)

                elif i < 180:
                    px = random.uniform(1e3, 1e4)
                    py = random.uniform(1e3, 1e4)
                    pz = random.uniform(1e3, 1e4)
                else:
                    px = 1.0
                    py = 0.0
                    pz = 0.0
                

                val_x = float32_to_float27(px)
                val_y = float32_to_float27(py)
                val_z = float32_to_float27(pz)
                
                px_f = float27_to_float32(val_x)
                py_f = float27_to_float32(val_y)
                pz_f = float27_to_float32(val_z)
                

                try:
                    res = sdf_func(px_f, py_f, pz_f)
                except ValueError:
                    res = 0.0
                val_res = float32_to_float27(res)
                
                f.write(f"{val_x:07X}_{val_y:07X}_{val_z:07X}_{val_res:07X}\n")
        print(f"Generated {filename}")

if __name__ == "__main__":
    generate_vectors()
