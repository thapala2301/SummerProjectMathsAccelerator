'''Records 2 seconds from every input device and prints the peak level.
Run while music is playing into the adapter to find the live endpoint.'''
import numpy as np
import sounddevice as sd

for i, d in enumerate(sd.query_devices()):
    if d['max_input_channels'] < 1:
        continue
    fs = int(d['default_samplerate'])
    try:
        rec = sd.rec(2 * fs, samplerate=fs, channels=1, dtype='float32', device=i)
        sd.wait()
        peak = float(np.abs(rec).max())
        bar = '#' * int(min(peak, 1.0) * 30)
        print(f"{i:3d} {d['name'][:48]:48s} peak={peak:.4f} {bar}")
    except Exception as e:
        print(f"{i:3d} {d['name'][:48]:48s} ERROR: {str(e)[:50]}")
