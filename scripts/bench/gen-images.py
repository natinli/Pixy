#!/usr/bin/env python3
"""性能基线脚本（scripts/bench/run.sh）的测试图片生成器，只用标准库。

  gen-images.py seed <目录> [数量]            生成 数量（默认 300）张带编号、宽高比有变化的 PNG：img_00001.png ...
  gen-images.py fan  <种子目录> <目标目录> <N>  用硬链接循环复用种子，得到 N 个 img_%05d.png（目标目录须已存在）

生成是确定性的（不用随机数、不看时钟）：同一台机器上每次得到的文件集合完全相同，基线才可比。
硬链接的副本共享同一个 inode，所以大小、日期、内容完全一致；真实目录比这更杂，这点在
docs/dev/performance-baseline.md 里有说明。
"""
import os
import struct
import sys
import zlib

# 宽高比（宽:高）循环使用，让瀑布流 / 对齐布局都有事可做
RATIOS = [(4, 3), (3, 2), (16, 9), (1, 1), (3, 4), (2, 3), (9, 16), (5, 4)]
LONG_EDGE = 1200  # 长边像素：足够让缩略图解码有真实开销，又不至于生成太慢


def chunk(tag: bytes, data: bytes) -> bytes:
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def png_bytes(index: int) -> bytes:
    ratio_w, ratio_h = RATIOS[index % len(RATIOS)]
    scale = LONG_EDGE / max(ratio_w, ratio_h)
    width, height = int(ratio_w * scale), int(ratio_h * scale)

    # 一行渐变，颜色相位由编号决定；之后每一行是上一行平移一个像素（3 字节），得到斜向渐变，
    # 用字节切片拼接而不是逐像素循环，300 张也只要几秒
    row = bytearray()
    for x in range(width):
        row += bytes(((x * 255 // width + index * 7) % 256,
                      (x * 127 // width + index * 13) % 256,
                      (255 - x * 255 // width + index * 29) % 256))
    row = bytes(row)
    raw = bytearray()
    for y in range(height):
        shift = (y * 3) % len(row)
        raw += b"\x00" + row[shift:] + row[:shift]
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8 位 RGB
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 1)) + chunk(b"IEND", b""))


def cmd_seed(directory: str, count: int) -> None:
    os.makedirs(directory, exist_ok=True)
    for i in range(1, count + 1):
        with open(os.path.join(directory, "img_%05d.png" % i), "wb") as f:
            f.write(png_bytes(i))


def cmd_fan(seed_dir: str, dest_dir: str, total: int) -> None:
    seeds = sorted(n for n in os.listdir(seed_dir) if n.endswith(".png"))
    if not seeds:
        sys.exit("种子目录里没有 PNG：%s" % seed_dir)
    for i in range(1, total + 1):
        os.link(os.path.join(seed_dir, seeds[(i - 1) % len(seeds)]),
                os.path.join(dest_dir, "img_%05d.png" % i))


def main(argv: list) -> None:
    if len(argv) >= 3 and argv[1] == "seed":
        cmd_seed(argv[2], int(argv[3]) if len(argv) > 3 else 300)
    elif len(argv) == 5 and argv[1] == "fan":
        cmd_fan(argv[2], argv[3], int(argv[4]))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
