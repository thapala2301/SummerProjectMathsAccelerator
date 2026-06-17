#!/usr/bin/env python3

import math
import struct

import pygame
import socket

LOOK_SENSITIVITY = 0.0019
PITCH_MIN = -1.52
PITCH_MAX = 1.52

DEFAULT_CAMERA_POSITION = [0.0, 0.15, 4.5]
DEFAULT_CAMERA_SPEED = 4.5
MIN_CAMERA_SPEED = 0.15
MAX_CAMERA_SPEED = 35.0

WINDOW_WIDTH = 1024
WINDOW_HEIGHT = 600
WINDOW_TITLE = "ctrls"

def clamp(value, minimum, maximum):
    return max(minimum, min(maximum, value))

def create_camera_state():
    return {
        "position": DEFAULT_CAMERA_POSITION.copy(),
        "yaw": 0.0,
        "pitch": 0.0,
        "speed": DEFAULT_CAMERA_SPEED,
    }

def reset_camera_state(state):
    state["position"] = DEFAULT_CAMERA_POSITION.copy()
    state["yaw"] = 0.0
    state["pitch"] = 0.0

def get_camera_matrix(yaw, pitch):
    cy = math.cos(yaw)
    sy = math.sin(yaw)
    cp = math.cos(pitch)
    sp = math.sin(pitch)

    forward = [sy * cp, sp, -cy * cp]
    right = [cy, 0.0, sy]
    up = [
        right[1] * forward[2] - right[2] * forward[1],
        right[2] * forward[0] - right[0] * forward[2],
        right[0] * forward[1] - right[1] * forward[0],
    ]

    # The FPGA ray generator expects the third row to be the world-space
    # forward vector directly. With the reset basis this is [0, 0, -1], which
    # makes the centre ray point down -Z into the scene.
    return [
        right[0], right[1], right[2],
        up[0], up[1], up[2],
        forward[0], forward[1], forward[2],
    ]

def advance_camera_state(state, keys, dt):
    cy = math.cos(state["yaw"])
    sy = math.sin(state["yaw"])

    forward = [sy, 0.0, -cy]
    right = [cy, 0.0, sy]
    up = [0.0, 1.0, 0.0]
    move = [0.0, 0.0, 0.0]

    def add_scaled(vector, scale):
        move[0] += vector[0] * scale
        move[1] += vector[1] * scale
        move[2] += vector[2] * scale

    if keys[pygame.K_w]:
        add_scaled(forward, 1.0)
    if keys[pygame.K_s]:
        add_scaled(forward, -1.0)
    if keys[pygame.K_d]:
        add_scaled(right, 1.0)
    if keys[pygame.K_a]:
        add_scaled(right, -1.0)
    if keys[pygame.K_SPACE]:
        add_scaled(up, 1.0)
    if keys[pygame.K_LSHIFT] or keys[pygame.K_RSHIFT]:
        add_scaled(up, -1.0)

    length = math.hypot(move[0], move[1], move[2])
    if length < 0.0001:
        return

    state["position"][0] += (move[0] / length) * state["speed"] * dt
    state["position"][1] += (move[1] / length) * state["speed"] * dt
    state["position"][2] += (move[2] / length) * state["speed"] * dt

def send_camera(sock, state):
    matrix = get_camera_matrix(state["yaw"], state["pitch"])
    values = matrix + state["position"]

    payload = struct.pack("12f", *values)
    sock.sendall(payload)

def main():
    # AF_INET = IPv4, SOCK_STREAM = TCP
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect(("192.168.137.238", 9999))
    camera = create_camera_state()

    pygame.init()
    screen = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
    pygame.display.set_caption(WINDOW_TITLE)
    # We grab mouse input into the window
    pygame.event.set_grab(True)
    pygame.mouse.set_visible(False)

    clock = pygame.time.Clock()
    running = True

    while running:

        # clock.tick(120) limits the loop to run at most 120 times per second
        # and returns the time since last call in milliseconds
        dt = min(clock.tick(120) / 1000.0, 0.05)

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                running = False
            elif event.type == pygame.KEYDOWN and event.key == pygame.K_r:
                reset_camera_state(camera)
            elif event.type == pygame.MOUSEMOTION:
                # event.rel[0] is relative x movement
                camera["yaw"] += event.rel[0] * LOOK_SENSITIVITY
                camera["pitch"] = clamp(
                    camera["pitch"] - event.rel[1] * LOOK_SENSITIVITY,
                    PITCH_MIN,
                    PITCH_MAX,
                )
            elif event.type == pygame.MOUSEWHEEL:
                # In software version, event.y is positive when scrolling down and negative when scrolling up
                # pygame is opposite so sign is different
                # Also event.y in pygame is smaller than event.deltaY so we use 0.12 instead of 0.0015
                factor = math.exp(event.y * 0.12)
                camera["speed"] = clamp(camera["speed"] * factor, MIN_CAMERA_SPEED, MAX_CAMERA_SPEED)

        keys = pygame.key.get_pressed()
        advance_camera_state(camera, keys, dt)
        send_camera(sock, camera)

        screen.fill((0, 0, 0))
        pygame.display.set_caption(
            f"{WINDOW_TITLE}  "
            f"pos=({camera['position'][0]:.2f}, {camera['position'][1]:.2f}, {camera['position'][2]:.2f})  "
            f"speed={camera['speed']:.2f}"
        )
        # We don't actually render anything
        # but we still need to flip the display to process events and update the window title
        pygame.display.flip()

    pygame.mouse.set_visible(True)
    pygame.event.set_grab(False)
    pygame.quit()

if __name__ == "__main__":
    main()
