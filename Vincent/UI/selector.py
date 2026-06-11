import sys
import time
import numpy as np
from PIL import Image, ImageDraw
from pynq import Overlay, allocate, GPIO
from pynq.lib.video import VideoMode
sys.path.append("../Software")
import board

# EMIO GPIO: Zynq PS GPIO base (906 on PYNQ-Z1) + 54 MIO offset + EMIO index
# BTN1=EMIO[0], BTN2=EMIO[1], BTN3=EMIO[2]
# Check base: ls /sys/class/gpio/ → gpiochipNNN → NNN is the base
_EMIO_BASE = 906 + 54
_btn_down  = GPIO(_EMIO_BASE + 0, 'in')  # BTN1 — scroll down
_btn_up    = GPIO(_EMIO_BASE + 1, 'in')  # BTN2 — scroll up
_btn_music = GPIO(_EMIO_BASE + 2, 'in')  # BTN3 — toggle music

def _wait_btn(btn):
    while btn.read(): pass        # wait for release if held
    while not btn.read(): pass    # wait for press
    time.sleep(0.05)              # debounce


UI_IMAGE = "FPGA Accelerated Ray Marching.png"

#10 sdf options
#music reactive is 3rd field
OPTIONS = [
    ("Scaffold", "Bitstream_Handoff/scaffold.bit", True),
    ("Sphere", "Bitstream_Handoff/sphere.bit", True),
    ("Twisted Torus", "Bitstream_Handoff/Twisted_Torus.bit", True),
    ("Gyroid", "Bitstream_Handoff/Gyroid.bit", True),
    ("Hyperboloid", "Bitstream_Handoff/Hyperboloid.bit", True),
    ("Octahedron", "Bitstream_Handoff/Octahedron.bit", True),
    ("Star", "Bitstream_Handoff/Star.bit", True),
    ("Torus", "Bitstream_Handoff/Torus.bit", True),
    ("Mandelbox", "Bitstream_Handoff/Mandelbox.bit", False),
    ("Neural", "Bitstream_Handoff/Neural.bit", False)
]
BASE_PX_Y=200
OFFSET_Y=100


OPTION_Y = [BASE_PX_Y, BASE_PX_Y+OFFSET_Y, BASE_PX_Y+2*OFFSET_Y, BASE_PX_Y+3*OFFSET_Y, 
            BASE_PX_Y+OFFSET_Y*4, BASE_PX_Y+OFFSET_Y*5, BASE_PX_Y+OFFSET_Y*6, 
            BASE_PX_Y+OFFSET_Y*7, BASE_PX_Y+OFFSET_Y*8, BASE_PX_Y+OFFSET_Y*9]
HIGHLIGHT_X = (55, 290) #from X55 to X 290
HIGHLIGHT_H = 36
MUSIC_REACTIVE_BOX = (390, 85, 760, 165)  # x0,y0,x1,y1 — tune to match PNG

def render_frame (base, selected, framebuf):
    copy = base.copy()
    img = Image.fromarray(copy)
    draw = ImageDraw.Draw(img)
    y = OPTION_Y[selected]
    draw.rectangle([HIGHLIGHT_X[0], y - HIGHLIGHT_H, HIGHLIGHT_X[1], y + HIGHLIGHT_H],
               outline=(255, 220, 0), width=3)
    if OPTIONS[selected][2]:   # music reactive supported
        draw.rectangle(MUSIC_REACTIVE_BOX, outline=(255, 220, 0), width=3)
    framebuf[:] = np.array(img)
    framebuf.flush()


def run_selector(framebuf):
    img = Image.open(UI_IMAGE).convert("RGB").resize((1024, 600))
    base = np.array(img)
    selected = 0
    render_frame(base, selected, framebuf)

    while True:
        if _btn_down.read():
            selected = (selected + 1) % len(OPTIONS)
            render_frame(base, selected, framebuf)
            _wait_btn(_btn_down)
        elif _btn_up.read():
            selected = (selected - 1) % len(OPTIONS)
            render_frame(base, selected, framebuf)
            _wait_btn(_btn_up)
        elif _btn_music.read():   # BTN3 = confirm selection
            _wait_btn(_btn_music)
            break
        time.sleep(0.02)

    if OPTIONS[selected][2]:
        m = input("Music reactive? (y/n): ").strip().lower()
        music_on = (m == "y")
    else:
        music_on = False

    return OPTIONS[selected][0], OPTIONS[selected][1], music_on

def start_ui_vdma(framebuf):
    ol = Overlay("ui.bit")
    vdma = ol.axi_vdma_0
    vdma.readchannel.mode = VideoMode(1024, 600, 24)
    vdma.readchannel.transfer(framebuf)
    vdma.readchannel.start()
    return ol


    
#unclear?
if __name__ == "__main__":
    framebuf = allocate(shape=(600, 1024, 3), dtype=np.uint8)
    '''allocate(shape=(720,1280,3), dtype=np.uint8) : reserves a chunk of physically 
    contiguous DDR memory that the VDMA DMA engine can read directly. 
    shape=(720,1280,3) = height x width x RGB channels'''
    
    ol = start_ui_vdma(framebuf)

    while True:
        name, bitfile, music_reactive = run_selector(framebuf)
        ol = Overlay(bitfile)
        print(f"Loaded {name}, music reactive: {music_reactive}")
        board.run(music_reactive)  # blocks until stop_event is set
        ol = start_ui_vdma(framebuf)
  
