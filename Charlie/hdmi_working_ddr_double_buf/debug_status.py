from pynq import MMIO


GPIO_BASE = 0x41200000
SPAN = 0x10000

DEBUG_STATES = {
    0: "idle/no frame",
    1: "dispatching",
    2: "waiting for march completions",
    3: "feedback-loop stall",
    4: "dispatch blocked",
    5: "DDR writer backpressure/drain",
    6: "frame ready / waiting for ack",
}

gpio = MMIO(GPIO_BASE, SPAN)
debug = gpio.read(0)
frame_counter = (debug >> 24) & 0xFF
done_hi = (debug >> 16) & 0xFF
dispatch_hi = (debug >> 8) & 0xFF
state = (debug >> 4) & 0xF
frame_drain_wait = bool((debug >> 3) & 1)
dispatch_enable = bool((debug >> 2) & 1)
frame_ready_valid = bool((debug >> 1) & 1)
frame_ready_bank = debug & 1

print(f"debug=0x{debug:08x}")
print(f"state={state}: {DEBUG_STATES.get(state, 'unknown')}")
print(f"frame={frame_counter}")
print(f"dispatch_hi=0x{dispatch_hi:02x}")
print(f"done_hi=0x{done_hi:02x}")
print(f"dispatch_enable={int(dispatch_enable)}")
print(f"frame_drain_wait={int(frame_drain_wait)}")
print(f"frame_ready_valid={int(frame_ready_valid)}")
print(f"frame_ready_bank={frame_ready_bank}")
