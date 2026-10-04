"""Generate the Bonbon app icon with only the Python standard library."""
from pathlib import Path
import struct
import zlib

SIZE = 1024
OUT = Path(__file__).resolve().parents[1] / "ios/Bonbon/Assets.xcassets/AppIcon.appiconset/icon.png"


def rounded_box(x, y, left, top, right, bottom, radius):
    cx = min(max(x, left + radius), right - radius)
    cy = min(max(y, top + radius), bottom - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


rows = []
for y in range(SIZE):
    row = bytearray([0])
    for x in range(SIZE):
        color = (246, 243, 224)
        if rounded_box(x, y, 117, 117, 907, 907, 192):
            color = (16, 41, 36)
        if rounded_box(x, y, 262, 251, 762, 357, 47):
            color = (246, 232, 121)
        if rounded_box(x, y, 262, 444, 654, 550, 47):
            color = (246, 232, 121)
        if rounded_box(x, y, 262, 637, 762, 743, 47):
            color = (246, 232, 121)
        row.extend(color)
    rows.append(bytes(row))


def chunk(name, data):
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data) & 0xffffffff)


OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
    + chunk(b"IEND", b"")
)
print(OUT)
