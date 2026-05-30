import asyncio
import websockets
import json
import numpy as np
from pynq import Overlay, allocate

print("1. Wiping and Initializing FPGA...")
overlay = Overlay("audio_fft.bit", download=True)
dma = overlay.axi_dma_0

N = 1024 
input_buffer = allocate(shape=(N,), dtype=np.int32)
output_buffer = allocate(shape=(N * 2,), dtype=np.int32) 

async def process_audio(websocket):
    print("\n[SUCCESS] Webpage Connected! Streaming hardware FFT...")
    try:
        async for message in websocket:
            # 1. Receive raw audio chunk from the browser
            audio_data = np.frombuffer(message, dtype=np.float32)
            
            # 2. Pack it for the hardware (Zeroing out Imaginary channel)
            raw_audio = (audio_data * 32767.0).astype(np.int32)
            packed_audio = raw_audio & 0x0000FFFF
            np.copyto(input_buffer, packed_audio)

            # 3. Fire the Silicon Pipeline!
            dma.sendchannel.transfer(input_buffer)
            dma.recvchannel.transfer(output_buffer)
            dma.sendchannel.wait()
            dma.recvchannel.wait()

            # 4. Extract Magnitude and scale it
            magnitude_data = output_buffer[0::2][:512]
            scaled_for_web = (np.abs(magnitude_data) / 100000.0).tolist()
            
            # 5. Send back to the browser
            await websocket.send(json.dumps(scaled_for_web))
            
            # Print a dot so we know data is flowing!
            print(".", end="", flush=True)
            
    except websockets.exceptions.ConnectionClosed:
        print("\n[INFO] Webpage disconnected.")

# --- MODERNIZED ASYNCIO STARTUP ---
async def main():
    print("2. Starting Server on port 8765...")
    async with websockets.serve(process_audio, "0.0.0.0", 8765):
        await asyncio.Future()  # Run forever

if __name__ == "__main__":
    asyncio.run(main())