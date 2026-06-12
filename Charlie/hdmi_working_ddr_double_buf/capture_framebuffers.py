import binascii
import struct
import zlib

import numpy as np


WIDTH = 1024
HEIGHT = 600
INTERNAL_WIDTH = 512
INTERNAL_HEIGHT = 300


def _require_global(name):
    if name not in globals():
        raise RuntimeError(
            f"{name} is not defined. Run this with `%run -i capture_framebuffers.py` "
            "after running config.py in the same notebook kernel."
        )
    return globals()[name]


def _png_chunk(kind, data):
    payload = kind + data
    return struct.pack(">I", len(data)) + payload + struct.pack(">I", binascii.crc32(payload) & 0xFFFFFFFF)


def write_png(path, rgb):
    height, width, channels = rgb.shape
    if channels != 3:
        raise ValueError("Expected an RGB image with shape (height, width, 3)")

    raw_rows = []
    for row in rgb.astype(np.uint8):
        raw_rows.append(b"\x00" + row.tobytes())

    png = [
        b"\x89PNG\r\n\x1a\n",
        _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)),
        _png_chunk(b"IDAT", zlib.compress(b"".join(raw_rows), level=6)),
        _png_chunk(b"IEND", b""),
    ]

    with open(path, "wb") as f:
        f.write(b"".join(png))


def words_to_rgb(words):
    words = np.asarray(words, dtype=np.uint32)
    rgb = np.empty(words.shape + (3,), dtype=np.uint8)
    rgb[..., 0] = (words >> 16) & 0xFF
    rgb[..., 1] = (words >> 8) & 0xFF
    rgb[..., 2] = words & 0xFF
    return rgb


def internal_from_screen(screen_words):
    return screen_words[0 : INTERNAL_HEIGHT * 2 : 2, 0 : INTERNAL_WIDTH * 2 : 2]


def save_bank(name, buffer):
    words = np.array(buffer, dtype=np.uint32, copy=True).reshape((HEIGHT, WIDTH))
    screen_rgb = words_to_rgb(words)
    frame_rgb = words_to_rgb(internal_from_screen(words))

    write_png(f"screen_{name}.png", screen_rgb)
    write_png(f"screen_{name}_rotcw.png", np.rot90(screen_rgb, k=3))
    write_png(f"frame_{name}.png", frame_rgb)


renderer_frame0 = _require_global("renderer_frame0")
renderer_frame1 = _require_global("renderer_frame1")

save_bank("bank0", renderer_frame0)
save_bank("bank1", renderer_frame1)

if "vdma" in globals() and "VDMA_PARK_PTR" in globals():
    park = vdma.read(VDMA_PARK_PTR)
    display_bank = park & 1
    save_bank("displayed", renderer_frame1 if display_bank else renderer_frame0)
    print(f"PARK_PTR = 0x{park:08x}, displayed bank guess = {display_bank}")

if "gpio" in globals() and "GPIO_DATA" in globals():
    print(f"GPIO = 0x{gpio.read(GPIO_DATA):08x}")

print("Wrote screen_bank0.png, screen_bank1.png, frame_bank0.png, frame_bank1.png")
print("If available, also wrote screen_displayed.png and frame_displayed.png")
