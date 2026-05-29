import asyncio
import websockets
import numpy as np
from pynq import Overlay, allocate

print("Loading FPGA Overlay...")
# 1. Load your specific Vivado Bitstream
overlay = Overlay("audio_fft.bit")
dma = overlay.axi_dma_0
fft_config_gpio = overlay.axi_gpio_0

print("Allocating DMA Memory...")
# 2. Allocate contiguous memory for DMA transfers (1024 points, 32-bit float)
input_buffer = allocate(shape=(1024,), dtype=np.float32)
output_buffer = allocate(shape=(1024,), dtype=np.int32)

print("Configuring FFT IP...")
# 3. Configure the FFT IP via GPIO
# Writing 0x01 configures it for a Forward FFT. 
fft_config_gpio.channel1.write(val=0x01, mask=0xFFFFFFFF) 

async def process_audio(websocket, path):
    async for message in websocket:
        audio_data = np.frombuffer(message, dtype=np.float32)
        
        if len(audio_data) == 1024:
            np.copyto(input_buffer, audio_data)
            
            dma.sendchannel.transfer(input_buffer)
            dma.recvchannel.transfer(output_buffer)
            dma.sendchannel.wait()
            dma.recvchannel.wait()
            
            # Take the absolute value of the integer data
            fft_mag = np.abs(output_buffer).astype(np.float32)
            
            # Send the cleaned data back
            await websocket.send(fft_mag.tobytes())
        
        # INCREASE THIS DELAY Slightly (e.g., 10ms)
        # This acts as a brake pedal so your browser doesn't freeze!
        await asyncio.sleep(0.01)

print("Hardware Server Started! Listening for browser connection on port 8765...")
# Start WebSocket server
start_server = websockets.serve(process_audio, "0.0.0.0", 8765)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()