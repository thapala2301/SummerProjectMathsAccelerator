from pynq import Overlay


BITFILE = "/home/xilinx/jupyter_notebooks/ctrl/ctrl.bit"


print(f"Loading overlay: {BITFILE}")
ol = Overlay(BITFILE)
print("Overlay loaded")
