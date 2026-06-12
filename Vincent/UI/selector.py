import sys
import time
import numpy as np
from PIL import Image, ImageDraw
from pynq import Overlay, allocate, MMIO, Clocks
import threading
import ctrl


WIDTH  = 1024
HEIGHT = 600
STRIDE = WIDTH * 4   # uint32 = 4 bytes per pixel

# Buttons via AXI GPIO at 0x41210000
# btns[0]=BTN1 scroll down, btns[1]=BTN2 scroll up, btns[2]=BTN3 confirm/music
_btn_mmio = MMIO(0x41210000, 0x1000)

def _read_btns():
    return _btn_mmio.read(0x0) & 0x7

def _wait_release(mask):
    while _read_btns() & mask: pass
    time.sleep(0.05)

UI_IMAGE = "base_ui.png"

OPTIONS = [
    ("Scaffold",      "Bitstream_Handoff/scaffold.bit",      True),
    ("Sphere",        "Bitstream_Handoff/sphere.bit",        True),
    ("Twisted Torus", "Bitstream_Handoff/Twisted_Torus.bit", True),
    ("Gyroid",        "Bitstream_Handoff/Gyroid.bit",        True),
    ("Hyperboloid",   "Bitstream_Handoff/Hyperboloid.bit",   True),
    ("Octahedron",    "Bitstream_Handoff/Octahedron.bit",    True),
    ("Star",          "Bitstream_Handoff/Star.bit",          True),
    ("Torus",         "Bitstream_Handoff/Torus.bit",         True),
    ("Mandelbox",     "Bitstream_Handoff/Mandelbox.bit",     False),
    ("Neural",        "Bitstream_Handoff/Neural.bit",        False)
]

BASE_PX_Y    = 145
OFFSET_Y     = 40
OPTION_Y     = [BASE_PX_Y + OFFSET_Y * i for i in range(len(OPTIONS))]
HIGHLIGHT_X  = (55, 290)
HIGHLIGHT_H  = 20
MUSIC_BOX    = (330, 85, 770, 150)
LONG_PRESS_S = 0.5


def _to_uint32(img_array):
    arr = img_array.astype(np.uint32)
    return (arr[:,:,0] << 16) | (arr[:,:,1] << 8) | arr[:,:,2]


def render_frame(base, selected, music_on, framebuf):
    img  = Image.fromarray(base.copy())
    draw = ImageDraw.Draw(img)
    y    = OPTION_Y[selected]
    draw.rectangle(
        [HIGHLIGHT_X[0], y - HIGHLIGHT_H, HIGHLIGHT_X[1], y + HIGHLIGHT_H],
        outline=(255, 50, 200), width=3 # R, B, G displays
    )
    if OPTIONS[selected][2]:
        color = (255, 50, 200) if music_on else (180, 60, 60)
        draw.rectangle(MUSIC_BOX, outline=color, width=3)
    framebuf[:] = _to_uint32(np.array(img))


def run_selector(framebuf):
    img      = Image.open(UI_IMAGE).convert("RGB").resize((WIDTH, HEIGHT))
    base     = np.array(img)
    selected = 0
    music_on = OPTIONS[0][2]
    render_frame(base, selected, music_on, framebuf)

    while True:
        btns = _read_btns()

        if btns & 0x1:
            selected = (selected + 1) % len(OPTIONS)
            music_on = OPTIONS[selected][2]
            render_frame(base, selected, music_on, framebuf)
            _wait_release(0x1)

        elif btns & 0x2:
            selected = (selected - 1) % len(OPTIONS)
            music_on = OPTIONS[selected][2]
            render_frame(base, selected, music_on, framebuf)
            _wait_release(0x2)

        elif btns & 0x4:
            t_press = time.time()
            _wait_release(0x4)
            if time.time() - t_press >= LONG_PRESS_S:
                break
            if OPTIONS[selected][2]:
                music_on = not music_on
                render_frame(base, selected, music_on, framebuf)

        time.sleep(0.02)

    return OPTIONS[selected][0], OPTIONS[selected][1], music_on


def _init_vdma(frame0, frame1):
    vdma = MMIO(0x43000000, 0x10000)
    vdma.write(0x00, 0x4)
    for _ in range(10000):
        if (vdma.read(0x00) & 0x4) == 0: break
        time.sleep(0.0001)
    vdma.write(0x04, 0xFFFFFFFF)
    vdma.write(0x18, 2)
    vdma.write(0x00, 0x1)
    vdma.write(0x5C, int(frame0.physical_address))
    vdma.write(0x60, int(frame1.physical_address))
    vdma.write(0x28, 0)
    vdma.write(0x58, STRIDE)
    vdma.write(0x54, STRIDE)
    vdma.write(0x50, HEIGHT)


def start_ui_vdma():
    ol     = Overlay("ui.bit")
    frame0 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    frame1 = allocate(shape=(HEIGHT, WIDTH), dtype=np.uint32, cacheable=False)
    _init_vdma(frame0, frame1)
    return ol, frame0   # frame0 is the live display buffer


if __name__ == "__main__":
    import signal, sys

    _in_raymarcher = False

    def _sigint(sig, frame):
        if _in_raymarcher:
            raise KeyboardInterrupt   # return to UI
        sys.exit(0)                   # in menu: quit entirely

    signal.signal(signal.SIGINT, _sigint)

    ol, framebuf = start_ui_vdma()

    while True:
        name, bitfile, music_on = run_selector(framebuf)
        ol = Overlay(bitfile)
        Clocks.fclk0_mhz = 50.0   # ui.bit leaves FCLK0 at wrong freq; scaffold expects 50 MHz
        print(f"Loaded {name}, music: {music_on}")
        stop = threading.Event()
        _in_raymarcher = True
        try:
            ctrl.run(stop_event=stop)
        except KeyboardInterrupt:
            pass
        finally:
            _in_raymarcher = False

        ol, framebuf = start_ui_vdma()
