"""
CPU ray-march of the 3-level Menger sponge SDF → menger.ppm
Mirrors the RTL menger_sdf.sv algorithm exactly.
Run: python3 tools/menger_ppm.py
"""

import numpy as np

W, H = 320, 240
MAX_ITER = 64
HIT_THRESH = 0.002
MAX_DIST = 40.0

# Menger sponge cross helper: min(max(rx,ry), max(ry,rz), max(rz,rx))
def cross_min(r):
    rx, ry, rz = r[..., 0], r[..., 1], r[..., 2]
    return np.minimum(np.maximum(rx, ry),
           np.minimum(np.maximum(ry, rz),
                      np.maximum(rz, rx)))

def menger_sdf(p, b=1.0):
    # Box SDF (L-inf)
    box_d = np.max(np.abs(p) - b, axis=-1)

    # Level 1 (s=1): fold space, compute cross, no rescale
    a1  = np.mod(p,       2.0) - 1.0
    r1  = np.abs(1.0 - 3.0 * np.abs(a1))
    c1  = cross_min(r1) - 1.0           # divide by s=1

    # Level 2 (s=3)
    a2  = np.mod(p * 3.0, 2.0) - 1.0
    r2  = np.abs(1.0 - 3.0 * np.abs(a2))
    c2  = (cross_min(r2) - 1.0) / 3.0

    # Level 3 (s=9)
    a3  = np.mod(p * 9.0, 2.0) - 1.0
    r3  = np.abs(1.0 - 3.0 * np.abs(a3))
    c3  = (cross_min(r3) - 1.0) / 9.0

    # CSG: box minus three levels of cross tunnels
    return np.maximum(box_d, np.maximum(-c1, np.maximum(-c2, -c3)))

def render():
    # Camera: orbit slightly above and in front
    cam_pos = np.array([1.8, 1.4, -4.0])
    target  = np.array([0.0, 0.0,  0.0])
    up      = np.array([0.0, 1.0,  0.0])

    fwd = target - cam_pos;  fwd /= np.linalg.norm(fwd)
    rgt = np.cross(fwd, up); rgt /= np.linalg.norm(rgt)
    up2 = np.cross(rgt, fwd)

    fov_y = np.radians(60.0)
    half_h = np.tan(fov_y * 0.5)
    half_w = half_h * W / H

    # Build pixel grid of ray directions
    xs = (np.arange(W) + 0.5) / W * 2 - 1   # [-1, 1]
    ys = (np.arange(H) + 0.5) / H * 2 - 1
    xs, ys = np.meshgrid(xs, ys)              # shape (H, W)
    dirs = (fwd[None,None,:]
            + xs[...,None] * half_w * rgt[None,None,:]
            - ys[...,None] * half_h * up2[None,None,:])
    dirs /= np.linalg.norm(dirs, axis=-1, keepdims=True)

    # Ray march — vectorised but step serially
    pos    = np.broadcast_to(cam_pos, (H, W, 3)).copy()
    dist   = np.zeros((H, W))
    iters  = np.zeros((H, W), dtype=np.int32)
    active = np.ones((H, W), dtype=bool)

    for i in range(MAX_ITER):
        if not active.any():
            break
        d = menger_sdf(pos)
        dist  += d * active
        hit    = active & (np.abs(d) < HIT_THRESH)
        miss   = active & (dist > MAX_DIST)
        done   = hit | miss
        active &= ~done
        iters += active.astype(np.int32)   # count steps taken while still going
        pos   += dirs * d[..., None] * active[..., None]

    # Colour: iteration count → grayscale (same as FPGA palette mapping)
    brightness = (iters.astype(float) / MAX_ITER)
    r = (brightness * 255).astype(np.uint8)
    g = ((1.0 - brightness) * 180).astype(np.uint8)
    b = ((brightness * 0.5 + 0.3) * 200).astype(np.uint8)

    rgb = np.stack([r, g, b], axis=-1)

    path = "menger.ppm"
    with open(path, "wb") as f:
        f.write(f"P6\n{W} {H}\n255\n".encode())
        f.write(rgb.tobytes())
    print(f"Saved {path}  ({W}x{H})")

if __name__ == "__main__":
    render()
