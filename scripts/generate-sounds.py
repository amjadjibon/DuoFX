#!/usr/bin/env python3
"""Generate DuoFX's original, short filtered-noise whooshes (no external assets)."""
import math
from pathlib import Path
import random
import struct
import wave

destination = Path(__file__).resolve().parent.parent / "DuoFX/Resources/Sounds"
destination.mkdir(parents=True, exist_ok=True)
rate = 44100
count = int(rate * 0.45)
for name, opening in [("Open", True), ("Close", False)]:
    noise = random.Random(42)
    low = 0.0
    samples = []
    for i in range(count):
        t = i / (count - 1)
        sweep = t if opening else 1 - t
        cutoff = 650 + 2300 * sweep
        alpha = 1 - math.exp(-2 * math.pi * cutoff / rate)
        low += alpha * (noise.uniform(-1, 1) - low)
        envelope = math.sin(math.pi * t) ** 1.8
        samples.append(low * envelope)
    peak = max(abs(sample) for sample in samples)
    pcm = b"".join(struct.pack("<h", round(sample / peak * 0.55 * 32767)) for sample in samples)
    with wave.open(str(destination / f"{name}.wav"), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(rate)
        audio.writeframes(pcm)
