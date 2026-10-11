#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
coe2dat.py —— 把 Vivado 的 .coe / 简单 .hex 文件转换成 PDS(紫光同创) IP 需要的 .dat

为什么需要转换：
    Vivado 的 Block Memory Generator 用 .coe（memory_initialization_radix /
    memory_initialization_vector 格式）；
    PDS 的 DRM Based ROM / RAM 的 "Init File" 只接受 *.dat，内容为
    “一行一个数据，二进制或十六进制”，十六进制时每行宽度 = DATA_WIDTH/4。

用法：
    python coe2dat.py irom.coe -o irom.dat --width 32 --depth 4096 --format hex
    python coe2dat.py dram.coe -o dram.dat --width 32 --depth 65536 --format hex
    python coe2dat.py tests/coremark/build/imem.hex -o imem.dat --width 32 --depth 4096

参数：
    --width   数据位宽（bit），默认 32
    --depth   存储器深度（字数）；给 0 表示不补齐（文件到哪算哪）
    --format  hex（默认）或 bin
    --radix   当输入是纯 hex 文件（无 memory_initialization_radix）时的进制，
              默认 16，可给 2
"""

import argparse
import re
import sys


def _strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return text


def read_words(path: str, default_radix: int):
    """读取 .coe 或纯文本 hex/bin 文件，返回 (radix, [int, ...])"""
    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
        raw = fh.read()

    text = _strip_comments(raw)

    m = re.search(r"memory_initialization_radix\s*=\s*(\d+)", text, re.I)
    radix = int(m.group(1)) if m else default_radix

    if re.search(r"memory_initialization_vector", text, re.I):
        body = re.split(r"memory_initialization_vector\s*=", text, flags=re.I)[1]
    else:
        body = text

    tokens = [t for t in re.split(r"[\s,;]+", body) if t]
    words = []
    for tok in tokens:
        tok = tok.strip().replace("_", "")
        if not tok:
            continue
        try:
            words.append(int(tok, radix))
        except ValueError:
            # 允许 8'hAB / 32'b1010 这类带位宽的写法
            m2 = re.match(r"^\d*'([bdhoBDHO])([0-9a-fA-FxXzZ_]+)$", tok)
            if not m2:
                continue
            base = {"b": 2, "o": 8, "d": 10, "h": 16}[m2.group(1).lower()]
            digits = m2.group(2).replace("_", "")
            if re.search(r"[xXzZ]", digits):
                digits = re.sub(r"[xXzZ]", "0", digits)
            words.append(int(digits, base))
    return radix, words


def main() -> int:
    ap = argparse.ArgumentParser(description="coe/hex -> PDS .dat")
    ap.add_argument("src", help="输入 .coe 或 .hex/.dat 文件")
    ap.add_argument("-o", "--out", help="输出 .dat（默认与输入同名）")
    ap.add_argument("--width", type=int, default=32, help="数据位宽 bit，默认 32")
    ap.add_argument("--depth", type=int, default=0, help="补齐到多少个字，0=不补齐")
    ap.add_argument("--format", choices=["hex", "bin"], default="hex")
    ap.add_argument("--radix", type=int, default=16, help="纯 hex/bin 输入时的进制，默认 16")
    args = ap.parse_args()

    radix, words = read_words(args.src, args.radix)
    if not words:
        print(f"[ERR] 没有从 {args.src} 里解析到任何数据", file=sys.stderr)
        return 2

    if args.depth and len(words) > args.depth:
        print(f"[WARN] 输入 {len(words)} 个字 > 深度 {args.depth}，已截断", file=sys.stderr)
        words = words[: args.depth]
    if args.depth:
        words += [0] * (args.depth - len(words))

    out = args.out or (args.src.rsplit(".", 1)[0] + ".dat")

    if args.format == "hex":
        nib = (args.width + 3) // 4
        mask = (1 << args.width) - 1
        lines = [format(w & mask, "0{}X".format(nib)) for w in words]
    else:
        lines = [format(w & ((1 << args.width) - 1), "0{}b".format(args.width)) for w in words]

    with open(out, "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")

    print(f"[OK] {args.src} (radix={radix}, {len(words)} words) -> {out} "
          f"[{args.format}, width={args.width}, depth={len(words)}]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
