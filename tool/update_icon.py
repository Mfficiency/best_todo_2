#!/usr/bin/env python3
"""Generate green circle icons for all platforms."""
import math, struct, zlib, os

def circle_png_bytes(size: int) -> bytes:
    radius = size / 2.0
    lines = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            dx = x + 0.5 - radius
            dy = y + 0.5 - radius
            if dx * dx + dy * dy <= radius * radius:
                row += bytes((0, 255, 0, 255))  # opaque green
            else:
                row += bytes((0, 0, 0, 0))      # transparent
        lines.append(b'\x00' + bytes(row))
    raw = b''.join(lines)
    compressor = zlib.compress(raw)
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
        + chunk(b'IDAT', compressor)
        + chunk(b'IEND', b'')
    )
    return png

def write_png(path: str, size: int) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(circle_png_bytes(size))

def write_ico(path: str, sizes):
    images = [circle_png_bytes(s) for s in sizes]
    header = struct.pack('<HHH', 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries = []
    for size, img in zip(sizes, images):
        w = h = size if size < 256 else 0
        entries.append(struct.pack('<BBBBHHII', w, h, 0, 0, 1, 32, len(img), offset))
        offset += len(img)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(header)
        for entry in entries:
            f.write(entry)
        for img in images:
            f.write(img)

def main():
    # Web icons
    write_png('web/icons/Icon-512.png', 512)
    write_png('web/icons/Icon-192.png', 192)
    write_png('web/icons/Icon-maskable-512.png', 512)
    write_png('web/icons/Icon-maskable-192.png', 192)
    write_png('web/favicon.png', 16)

    # Android icons
    android = 'android/app/src/main/res'
    for size, folder in [
        (48, 'mipmap-mdpi'),
        (72, 'mipmap-hdpi'),
        (96, 'mipmap-xhdpi'),
        (144, 'mipmap-xxhdpi'),
        (192, 'mipmap-xxxhdpi'),
    ]:
        write_png(f'{android}/{folder}/ic_launcher.png', size)

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
        write_png(f'{ios}/{name}', size)

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
        write_png(f'{mac}/{name}', size)

    # Windows icon
    write_ico('windows/runner/resources/app_icon.ico', [16, 32, 48, 256])

    print('Green circle icons generated.')

if __name__ == '__main__':
    main()