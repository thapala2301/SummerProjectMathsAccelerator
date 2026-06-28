# SCRIPTS

Python scripts for running the ray marcher on the PYNQ-Z1 board and controlling it from a PC.

---

## `PYNQ/` — runs on the board

### `ctrl.py` — main runtime controller

The main script for running the ray marcher. Does everything:

1. **VDMA setup**: allocates two contiguous DDR3 frame buffers using `pynq.allocate`, writes their physical addresses to the `FRAME_BASE0_REG` and `FRAME_BASE1_REG` AXI registers. The PL won't dispatch any pixels until both addresses are set and non-zero.
2. **VDMA config**: programs the Xilinx VDMA IP (at `0x43000000`) with frame dimensions, stride, and start addresses. Starts the MM2S (memory-to-stream) channel in park mode.
3. **Camera TCP server** (port 9999): listens for 12-float packets from `Computer/camera_mmio_controller.py`. Each packet is a 3×3 lookat matrix + 3D origin. On receipt, writes all 12 values to the AXI camera registers.
4. **Audio TCP server** (port 9998, optional): listens for scene parameter packets from the PC. Parameters include cell size, shape size, colours, and audio energy values. Set `music_on=True` when calling `run()` to enable.
5. **Frame ACK loop**: pulses the `frame_ack` GPIO at regular intervals (~1ms) to tell the PL that the VDMA has consumed the last frame and the render bank can be swapped.

Called by `ui_base_selector.py` in a thread: `ctrl.run(stop_event, music_on=False)`.

**Register map** (AXI base `0x43C00000`):

```python
FRAME_BASE0_REG    = 12 * 4   # DDR3 base address for frame buffer 0
FRAME_BASE1_REG    = 13 * 4   # DDR3 base address for frame buffer 1
SCENE_CELL_SZ_REG  = 14 * 4   # FP27, domain repeat cell size
# ... see ctrl.py for full list
```

### `ui_base_selector.py`

Simple web UI (served via the PYNQ web interface) that displays a button to switch between the base Vivado design and the ray marcher bitstream. Loads the appropriate `.bit` and `.hwh` files and starts `ctrl.py` as a background thread.

### `Charlie_notebook.ipynb`

Jupyter notebook for interactive camera and scene control. Useful for debugging and demo.

---

## `Computer/` — runs on a laptop

### `camera_mmio_controller.py`

Keyboard/mouse camera controller. Reads keyboard input (WASD + mouse), computes the camera lookat matrix and origin, packs them as 12 floats, and sends over TCP to the board on port 9999.

The camera model is a standard look-at with yaw/pitch controlled by mouse delta.

### `relay_imu_data.py`

Reads IMU data (e.g. from a phone or headset) and relays it to the board for head-tracking camera control.

### `audio_sender.py`

Reads the laptop microphone, computes an FFT, extracts bass/mid/treble energy, and sends scene parameter packets to the board on port 9998.

---

## `Vivado_bd/` — Vivado TCL scripts

### `create_project.tcl`

Recreates the Vivado block design from scratch. Run this if you don't have the `.xpr` file or want to start from a clean state:

```tcl
vivado -mode batch -source create_project.tcl
```

### `control_bd.tcl`

TCL for the control block design specifically (AXI interconnect, axi_camera_regs IP, VDMA).

---

## Typical workflow

1. Copy `SCRIPTS/PYNQ/` to the PYNQ-Z1 (e.g. via `scp` or the PYNQ file manager).
2. Open the PYNQ web interface, navigate to `ui_base_selector.py` or `Charlie_notebook.ipynb`.
3. Load the ray marcher bitstream.
4. On the laptop, run `python3 Computer/camera_mmio_controller.py --host <board-ip>`.
5. Use WASD + mouse to fly the camera.
