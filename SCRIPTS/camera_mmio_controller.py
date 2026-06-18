#!/usr/bin/env python3

import math
import socket
import struct
import time

import pygame


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
SERVER_ADDR = ("192.168.137.17", 9999)
CONNECT_RETRY_SECONDS = 0.5
SOCKET_TIMEOUT_SECONDS = 0.2


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

    return [
        right[0], up[0], forward[0],
        right[1], up[1], forward[1],
        right[2], up[2], forward[2],
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
    payload = struct.pack("<12f", *(matrix + state["position"]))
    sock.sendall(payload)


def connect_camera_socket():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(SOCKET_TIMEOUT_SECONDS)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    sock.connect(SERVER_ADDR)
    return sock


def main():
    camera = create_camera_state()
    sock = None
    next_connect_attempt = 0.0
    connected = False

    pygame.init()
    screen = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
    pygame.display.set_caption(WINDOW_TITLE)
    pygame.event.set_grab(True)
    pygame.mouse.set_visible(False)

    clock = pygame.time.Clock()
    running = True

    try:
        while running:
            dt = min(clock.tick(120) / 1000.0, 0.05)

            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                    running = False
                elif event.type == pygame.KEYDOWN and event.key == pygame.K_r:
                    reset_camera_state(camera)
                elif event.type == pygame.MOUSEMOTION:
                    camera["yaw"] += event.rel[0] * LOOK_SENSITIVITY
                    camera["pitch"] = clamp(
                        camera["pitch"] - event.rel[1] * LOOK_SENSITIVITY,
                        PITCH_MIN,
                        PITCH_MAX,
                    )
                elif event.type == pygame.MOUSEWHEEL:
                    factor = math.exp(event.y * 0.12)
                    camera["speed"] = clamp(camera["speed"] * factor, MIN_CAMERA_SPEED, MAX_CAMERA_SPEED)

            advance_camera_state(camera, pygame.key.get_pressed(), dt)

            if sock is None and time.monotonic() >= next_connect_attempt:
                try:
                    sock = connect_camera_socket()
                    connected = True
                except OSError:
                    sock = None
                    connected = False
                    next_connect_attempt = time.monotonic() + CONNECT_RETRY_SECONDS

            if sock is not None:
                try:
                    send_camera(sock, camera)
                except OSError:
                    sock.close()
                    sock = None
                    connected = False
                    next_connect_attempt = time.monotonic() + CONNECT_RETRY_SECONDS

            screen.fill((0, 0, 0))
            pygame.display.set_caption(
                f"{WINDOW_TITLE}  "
                f"pos=({camera['position'][0]:.2f}, {camera['position'][1]:.2f}, {camera['position'][2]:.2f})  "
                f"speed={camera['speed']:.2f}  "
                f"{'connected' if connected else 'connecting'}"
            )
            pygame.display.flip()
    finally:
        pygame.mouse.set_visible(True)
        pygame.event.set_grab(False)
        pygame.quit()
        if sock is not None:
            sock.close()


if __name__ == "__main__":
    main()