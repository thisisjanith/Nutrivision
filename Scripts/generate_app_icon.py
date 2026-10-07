#!/usr/bin/env python3
"""Draws the NutriVision app icon (light, dark and tinted variants) into the AppIcon set."""
from PIL import Image, ImageDraw, ImageFilter
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "NutriVision", "Assets.xcassets", "AppIcon.appiconset")
S = 4096  # supersampled, downscaled to 1024


def gradient(c1, c2):
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            t = (x + y) / (2 * S)
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return img


def glyph(fg, accent):
    """Viewfinder corners around a plate with fork and knife."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, arm, m = 190, 780, 760
    for cx, cy, dx, dy in [(m, m, 1, 1), (S - m, m, -1, 1), (m, S - m, 1, -1), (S - m, S - m, -1, -1)]:
        d.line([(cx + dx * arm, cy), (cx, cy), (cx, cy + dy * arm)], fill=fg, width=w, joint="curve")
        d.ellipse([cx - w // 2, cy - w // 2, cx + w // 2, cy + w // 2], fill=fg)
        d.ellipse([cx + dx * arm - w // 2, cy - w // 2, cx + dx * arm + w // 2, cy + w // 2], fill=fg)
        d.ellipse([cx - w // 2, cy + dy * arm - w // 2, cx + w // 2, cy + dy * arm + w // 2], fill=fg)
    c, r = S // 2, 900
    d.ellipse([c - r, c - r, c + r, c + r], fill=fg)
    d.ellipse([c - r + 140, c - r + 140, c + r - 140, c + r - 140], fill=accent)
    # fork (left): three tines joined by a rounded base, then a handle
    fx = c - 260
    for dx in (-110, 0, 110):
        d.rounded_rectangle([fx + dx - 30, c - 480, fx + dx + 30, c - 120], radius=30, fill=fg)
    d.rounded_rectangle([fx - 140, c - 250, fx + 140, c - 60], radius=95, fill=fg)
    d.rounded_rectangle([fx - 38, c - 120, fx + 38, c + 480], radius=38, fill=fg)
    # knife (right): blade with a rounded back, then a handle
    kx = c + 270
    d.rounded_rectangle([kx - 75, c - 480, kx + 75, c + 40], radius=75, fill=fg)
    d.rectangle([kx - 75, c - 300, kx - 20, c + 40], fill=fg)
    d.rounded_rectangle([kx - 38, c - 20, kx + 38, c + 480], radius=38, fill=fg)
    return layer


def save(name, bg, fg, accent):
    img = bg.convert("RGBA")
    img.alpha_composite(glyph(fg, accent))
    img.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, name))


teal = gradient((0x2E, 0x9E, 0x8A), (0x0F, 0xB5, 0x9B))
save("AppIcon.png", teal, (255, 255, 255, 255), (0x1A, 0xA3, 0x84, 255))
save("AppIcon-dark.png", Image.new("RGB", (S, S), (0x0B, 0x0F, 0x0E)), (0x1F, 0xC9, 0xA4, 255), (0x0B, 0x0F, 0x0E, 255))
save("AppIcon-tinted.png", Image.new("RGB", (S, S), (0, 0, 0)), (255, 255, 255, 255), (0, 0, 0, 255))
