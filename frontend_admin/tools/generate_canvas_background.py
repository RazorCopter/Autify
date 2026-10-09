"""Genera assets/images/10_canvas_abstract.jpg, lo sfondo del canvas della
Dashboard 4.0.

Uso, dalla cartella frontend_admin (serve numpy e pillow):

    python tools/generate_canvas_background.py assets/images/10_canvas_abstract.jpg

Compone lo sfondo astratto del canvas della Dashboard 4.0.

Lastre traslucide sovrapposte: bande larghe deformate da un campo
sinusoidale, con bordo netto e una lumeggiatura sul contorno, cosi' si
leggono come piani di vetro satinato e non come sfocature. Il centro resta
piu' chiaro perche' e' dove stanno le card. Chiude una grana fine.
"""

import sys

import numpy as np
from PIL import Image

W, H = 2560, 1600
ASPECT = W / H

BASE = (244, 247, 252)

# (angolo gradi, offset, semilarghezza, ampiezza onda, frequenza, fase,
#  colore, intensita')
SLABS = [
    (24.0, 0.16, 0.150, 0.075, 1.7, 0.0, (74, 123, 255), 0.26),
    (31.0, 0.46, 0.085, 0.060, 2.4, 1.3, (124, 140, 255), 0.22),
    (18.0, 0.78, 0.125, 0.090, 1.4, 2.6, (150, 120, 214), 0.22),
    (-26.0, 0.52, 0.105, 0.070, 1.9, 0.8, (126, 213, 232), 0.17),
    (-34.0, 0.92, 0.075, 0.055, 2.9, 3.4, (99, 91, 255), 0.16),
    (52.0, 0.34, 0.060, 0.045, 3.6, 1.9, (255, 255, 255), 0.34),
]

CORNERS = [
    (-0.12, -0.16, 0.66, (74, 123, 255), 0.28),
    (1.12, 1.14, 0.64, (150, 120, 214), 0.26),
    (1.08, -0.12, 0.44, (99, 91, 255), 0.16),
]

EDGE_LIGHT = 0.55
CENTER_LIFT = 0.26
GRAIN = 2.0
VIGNETTE = 0.09


def smoothstep(edge: np.ndarray) -> np.ndarray:
    t = np.clip(edge, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def main(out_path: str) -> None:
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    x = xs / (W - 1)
    y = (ys / (H - 1)) / ASPECT
    del xs, ys

    img = np.empty((H, W, 3), dtype=np.float32)
    for channel, value in enumerate(BASE):
        img[:, :, channel] = value

    for angle, offset, half, amp, freq, phase, color, strength in SLABS:
        rad = np.deg2rad(angle)
        axis = x * np.cos(rad) + y * np.sin(rad)
        along = -x * np.sin(rad) + y * np.cos(rad)
        wave = amp * np.sin(freq * np.pi * along + phase)
        wave += 0.35 * amp * np.sin(2.3 * freq * np.pi * along + phase * 1.7)
        dist = np.abs(axis + wave - offset)

        # Bordo netto: la sfumatura occupa solo l'ultimo 18% della lastra.
        feather = half * 0.18
        core = 1.0 - smoothstep((dist - (half - feather)) / feather)
        # Variazione lungo la lastra, cosi' non e' una banda uniforme.
        core = core * (0.6 + 0.4 * np.sin(1.3 * np.pi * along + phase) ** 2)
        core = core * strength

        for channel in range(3):
            img[:, :, channel] += (color[channel] - img[:, :, channel]) * core

        # Lumeggiatura sul contorno: e' cio' che fa leggere il piano.
        rim = np.exp(-(((dist - half) / (half * 0.09)) ** 2)) * EDGE_LIGHT
        img += (253.0 - img) * rim[:, :, None]

        del axis, along, wave, dist, core, rim

    for cx, cy, radius, color, strength in CORNERS:
        dist = np.sqrt((x - cx) ** 2 + (y - cy / ASPECT) ** 2) / radius
        weight = smoothstep(1.0 - dist) * strength
        for channel in range(3):
            img[:, :, channel] += (color[channel] - img[:, :, channel]) * weight
        del dist, weight

    center = np.sqrt((x - 0.5) ** 2 + (y - 0.46 / ASPECT) ** 2) / 0.52
    lift = smoothstep(1.0 - center) * CENTER_LIFT
    img += (252.0 - img) * lift[:, :, None]
    del center, lift

    radial = np.sqrt((x - 0.5) ** 2 + (y - 0.5 / ASPECT) ** 2) / 0.62
    img *= (1.0 - VIGNETTE * np.clip(radial - 0.55, 0.0, 1.0))[:, :, None]
    del radial, x, y

    rng = np.random.default_rng(20261009)
    img += rng.normal(0.0, GRAIN, size=(H, W, 1)).astype(np.float32)

    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), mode="RGB")
    out.save(out_path, quality=92, subsampling=0, optimize=True)
    print("scritto", out_path, out.size)


if __name__ == "__main__":
    main(sys.argv[1])
