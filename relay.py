"""
relay.py - Run this on your Windows laptop
Reads IMU data from ESP32 (USB) and forwards to PYNQ via UDP
Double-click or run: python relay.py
"""

import serial
import serial.tools.list_ports
import socket
import time

PYNQ_IP   = '192.168.137.68'
PYNQ_PORT = 5005

# --- Auto-find ESP32 COM port ---
print("Looking for ESP32...")
esp_port = None
for port in serial.tools.list_ports.comports():
    if 'CH340' in port.description or 'USB-SERIAL' in port.description.upper() or 'CP210' in port.description:
        esp_port = port.device
        print(f"Found ESP32 on {esp_port}: {port.description}")
        break

if not esp_port:
    print("ESP32 not found automatically. Available ports:")
    for port in serial.tools.list_ports.comports():
        print(f"  {port.device}: {port.description}")
    esp_port = input("Enter COM port (e.g. COM4): ").strip()

# --- Open serial ---
ser = serial.Serial(esp_port, 115200, timeout=1)
time.sleep(2)
ser.reset_input_buffer()
print(f"Serial open. Sending to {PYNQ_IP}:{PYNQ_PORT}")
print("Press Ctrl+C to stop\n")

# --- UDP socket ---
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

count = 0
while True:
    try:
        line = ser.readline()
        if line and b',' in line:
            sock.sendto(line, (PYNQ_IP, PYNQ_PORT))
            count += 1
            if count % 100 == 0:
                print(f"[{count}] {line.decode().strip()}")
    except KeyboardInterrupt:
        print("Stopped")
        break
    except Exception as e:
        print(f"Error: {e}")

ser.close()
sock.close()

