#!/usr/bin/env python3
"""
generate_app_icon.py
Generates Apple macOS standard AppIcon.icns from an uploaded icon image.
Cleans background corner artifacts, applies squircle mask with anti-aliasing,
applies subtle macOS drop shadow, builds .iconset and compiles to AppIcon.icns.
"""

import sys
import os
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFilter

def generate_icns(source_path: str, output_icns_path: str):
    if not os.path.exists(source_path):
        print(f"Error: Source image not found: {source_path}", file=sys.stderr)
        sys.exit(1)

    print(f"==> Processing source image: {source_path}")
    src = Image.open(source_path).convert('RGBA')

    # 1. Precise crop of squircle bounds to eliminate outside wallpaper/screenshot edges
    # Left: 1, Top: 1, Right: 417, Bottom: 425
    crop = src.crop((1, 1, 417, 425))
    cw, ch = crop.size

    # 2. 4x supersampling mask for ultra-smooth anti-aliased squircle edges
    scale = 4
    mask_hi = Image.new('L', (cw * scale, ch * scale), 0)
    draw_hi = ImageDraw.Draw(mask_hi)
    radius_hi = int(82 * scale)
    draw_hi.rounded_rectangle([(0, 0), (cw * scale - 1, ch * scale - 1)], radius=radius_hi, fill=255)
    mask = mask_hi.resize((cw, ch), Image.Resampling.LANCZOS)

    # 3. Apply mask to isolate squircle with transparent corners
    icon_isolated = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
    icon_isolated.paste(crop, (0, 0), mask=mask)

    # 4. Fit into standard macOS HIG 1024x1024 icon grid (~834x834 squircle)
    squircle_size = 834
    icon_scaled = icon_isolated.resize((squircle_size, squircle_size), Image.Resampling.LANCZOS)

    master_1024 = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    
    # 5. Add native macOS subtle drop shadow
    shadow_mask = Image.new('L', (squircle_size, squircle_size), 0)
    draw_shadow = ImageDraw.Draw(shadow_mask)
    draw_shadow.rounded_rectangle(
        [(0, 0), (squircle_size - 1, squircle_size - 1)],
        radius=int(squircle_size * 0.22),
        fill=255
    )

    shadow_canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    shadow_layer = Image.new('RGBA', (squircle_size, squircle_size), (0, 0, 0, 95))
    shadow_layer.putalpha(shadow_mask)

    x_pos = (1024 - squircle_size) // 2
    y_pos = (1024 - squircle_size) // 2 - 8  # slight upward optical center for bottom shadow
    shadow_canvas.paste(shadow_layer, (x_pos, y_pos + 16))
    shadow_canvas = shadow_canvas.filter(ImageFilter.GaussianBlur(radius=18))

    master_1024 = Image.alpha_composite(master_1024, shadow_canvas)
    master_1024.paste(icon_scaled, (x_pos, y_pos), mask=icon_scaled)

    # 6. Build macOS standard .iconset
    temp_iconset = os.path.join(os.path.dirname(output_icns_path), "AppIcon.iconset")
    if os.path.exists(temp_iconset):
        shutil.rmtree(temp_iconset)
    os.makedirs(temp_iconset, exist_ok=True)

    sizes = [
        ('icon_16x16.png', 16),
        ('icon_16x16@2x.png', 32),
        ('icon_32x32.png', 32),
        ('icon_32x32@2x.png', 64),
        ('icon_128x128.png', 128),
        ('icon_128x128@2x.png', 256),
        ('icon_256x256.png', 256),
        ('icon_256x256@2x.png', 512),
        ('icon_512x512.png', 512),
        ('icon_512x512@2x.png', 1024),
    ]

    print("==> Generating multi-resolution PNGs...")
    for filename, sz in sizes:
        resized = master_1024.resize((sz, sz), Image.Resampling.LANCZOS)
        resized.save(os.path.join(temp_iconset, filename), 'PNG')

    # 7. Convert .iconset to .icns using macOS iconutil
    os.makedirs(os.path.dirname(output_icns_path), exist_ok=True)
    print(f"==> Compiling .icns via iconutil to: {output_icns_path}")
    cmd = ["iconutil", "-c", "icns", temp_iconset, "-o", output_icns_path]
    subprocess.run(cmd, check=True)

    # Clean up iconset
    shutil.rmtree(temp_iconset)
    print(f"🎉 Successfully created macOS icon: {output_icns_path}")

if __name__ == "__main__":
    default_src = "/Users/cnoxc/.gemini/antigravity/brain/76d803d8-4d19-47a4-a458-a9c7bc4da196/.user_uploaded/media_1789894338305.png"
    default_dest = os.path.abspath(os.path.join(os.path.dirname(__file__), "../Sources/EPUBRepackerApp/Resources/AppIcon.icns"))

    src = sys.argv[1] if len(sys.argv) > 1 else default_src
    dest = sys.argv[2] if len(sys.argv) > 2 else default_dest

    generate_icns(src, dest)
