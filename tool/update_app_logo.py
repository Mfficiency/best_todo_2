#!/usr/bin/env python3
"""Resize existing PNG icons for all platforms."""
# run this script from the root of the project:
# python tool/update_app_logo.py
import os
from PIL import Image

# Source icons
SOURCE_ICON = "web/icons/Icon-512.png"
SOURCE_MASKABLE_ICON = "web/icons/Icon-maskable-512.png"

def resize_and_save(src, dest, size):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    img = Image.open(src).convert("RGBA")
    img = img.resize((size, size), Image.LANCZOS)
    img.save(dest, format="PNG")
    print(f"Saved {dest} ({size}x{size})")

def save_watch_icon(src, dest, size):
    """Watch launcher icon: the logo on a white disc, shrunk to stay inside
    the circle the watch's app list crops icons to."""
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    img = Image.open(src).convert("RGBA")
    # Centre on the dark glyph, not on the canvas (the logo sits off-centre).
    glyph = img.convert("L").point(lambda v: 255 if v < 200 else 0).getbbox()
    logo = img.crop(glyph)
    scale = size * 0.74 / max(logo.size)
    logo = logo.resize((max(1, round(logo.width * scale)),
                        max(1, round(logo.height * scale))), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    out.alpha_composite(logo, ((size - logo.width) // 2,
                               (size - logo.height) // 2))
    out.save(dest, format="PNG")
    print(f"Saved {dest} ({size}x{size})")

def watch_icons():
    # Wear OS companion (wear/): same logo, so the watch shows BestToDo's.
    wear = 'wear/app/src/main/res'
    for size, folder in [
        (48, 'mipmap-mdpi'),
        (72, 'mipmap-hdpi'),
        (96, 'mipmap-xhdpi'),
        (144, 'mipmap-xxhdpi'),
        (192, 'mipmap-xxxhdpi'),
    ]:
        save_watch_icon(SOURCE_ICON, f'{wear}/{folder}/ic_launcher.png', size)

def save_notification_icon(src, dest, size):
    """Status-bar icon: Android draws only its alpha, so the logo becomes a
    white glyph on transparent (the launcher PNG would be a white square)."""
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    img = Image.open(src).convert("RGBA")
    dark = img.convert("L").point(lambda v: 255 - v)
    glyph = dark.point(lambda v: 255 if v > 55 else 0).getbbox()
    alpha = dark.crop(glyph)
    scale = size * 0.92 / max(alpha.size)
    alpha = alpha.resize((max(1, round(alpha.width * scale)),
                          max(1, round(alpha.height * scale))), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    white = Image.new("RGBA", alpha.size, (255, 255, 255, 255))
    white.putalpha(alpha)
    out.alpha_composite(white, ((size - alpha.width) // 2,
                                (size - alpha.height) // 2))
    out.save(dest, format="PNG")
    print(f"Saved {dest} ({size}x{size})")

def notification_icons():
    android = 'android/app/src/main/res'
    for size, folder in [
        (24, 'drawable-mdpi'),
        (36, 'drawable-hdpi'),
        (48, 'drawable-xhdpi'),
        (72, 'drawable-xxhdpi'),
        (96, 'drawable-xxxhdpi'),
    ]:
        save_notification_icon(SOURCE_ICON, f'{android}/{folder}/ic_stat_notification.png', size)

def main():
    # Web icons
    resize_and_save(SOURCE_ICON, "web/icons/Icon-512.png", 512)
    resize_and_save(SOURCE_ICON, "web/icons/Icon-192.png", 192)
    resize_and_save(SOURCE_MASKABLE_ICON, "web/icons/Icon-maskable-512.png", 512)
    resize_and_save(SOURCE_MASKABLE_ICON, "web/icons/Icon-maskable-192.png", 192)
    resize_and_save(SOURCE_ICON, "web/favicon.png", 16)

    # Android icons
    android = 'android/app/src/main/res'
    for size, folder in [
        (48, 'mipmap-mdpi'),
        (72, 'mipmap-hdpi'),
        (96, 'mipmap-xhdpi'),
        (144, 'mipmap-xxhdpi'),
        (192, 'mipmap-xxxhdpi'),
    ]:
        resize_and_save(SOURCE_ICON, f'{android}/{folder}/ic_launcher.png', size)

    # iOS icons
    ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    ios_sizes = {
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
        'Icon-App-1024x1024@1x.png': 1024,
    }
    for name, size in ios_sizes.items():
        resize_and_save(SOURCE_ICON, f'{ios}/{name}', size)

    # macOS icons
    mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    mac_sizes = {
        'app_icon_16.png': 16,
        'app_icon_32.png': 32,
        'app_icon_64.png': 64,
        'app_icon_128.png': 128,
        'app_icon_256.png': 256,
        'app_icon_512.png': 512,
        'app_icon_1024.png': 1024,
    }
    for name, size in mac_sizes.items():
        resize_and_save(SOURCE_ICON, f'{mac}/{name}', size)

    # Windows icon (multi-size .ico used for the exe / taskbar)
    ico = 'windows/runner/resources/app_icon.ico'
    os.makedirs(os.path.dirname(ico), exist_ok=True)
    Image.open(SOURCE_ICON).convert("RGBA").save(
        ico,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(f"Saved {ico} (16-256px)")

    notification_icons()
    watch_icons()

    print("All icons generated from existing PNGs.")

if __name__ == "__main__":
    main()
