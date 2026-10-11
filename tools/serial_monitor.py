#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""串口监视器 —— 盘古50Pro / PG2L50H CoreMark 调试用

为什么不用普通串口助手：
  * 自动认出板载 CP2102 的 COM 口（不用猜 COM 号）
  * 每行打时间戳，自动存盘（原始字节 + 文本）
  * 自动高亮 CoreMark 关键行（seedcrc / crc*/CoreMark 1.0 / Correct operation validated）
  * 断线自动重连（板子复位/重下 bit 流时不用重启工具）
  * 收到成绩行时自动解析并打印一行摘要

用法：
    python tools/serial_monitor.py                 # 自动找 CP2102，9600-8-N-1
    python tools/serial_monitor.py -p COM7         # 指定串口
    python tools/serial_monitor.py --seconds 15    # 只收 15 秒后退出（跑一次 CoreMark 用）
    python tools/serial_monitor.py --hex           # 十六进制显示
    python tools/serial_monitor.py --list          # 只列串口

依赖：pyserial（pip install pyserial）
"""

import argparse
import datetime as dt
import os
import re
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("缺少 pyserial：请先执行  pip install pyserial")

# CP2102（盘古50Pro 板载 USB-UART）
CP2102_IDS = {(0x10C4, 0xEA60), (0x10C4, 0xEA70)}

KEY = re.compile(
    r"CoreMark|seedcrc|crclist|crcmatrix|crcstate|crcfinal|"
    r"Correct operation validated|ERROR|Total ticks|Total time|Iterations|"
    r"Compiler version|Memory location",
    re.I,
)
SCORE = re.compile(r"CoreMark\s+1\.0\s*:\s*([0-9.]+)", re.I)
ITER_SEC = re.compile(r"Iterations/Sec\s*:\s*([0-9.]+)", re.I)
TICKS = re.compile(r"Total ticks\s*:\s*(\d+)", re.I)
SECS = re.compile(r"Total time \(secs\)\s*:\s*([0-9.]+)", re.I)


def list_ports_verbose():
    ports = list(list_ports.comports())
    if not ports:
        print("没有发现任何串口。检查 USB 线 / 驱动（板载串口是 CP2102，VID:PID = 10C4:EA60）")
        return ports
    print("可用串口：")
    for p in ports:
        tag = "  <== CP2102（板载 USB-UART）" if (p.vid, p.pid) in CP2102_IDS else ""
        print("   %-8s %-38s [%04X:%04X]%s" % (p.device, (p.description or "")[:38], p.vid or 0, p.pid or 0, tag))
    return ports


def pick_port(requested):
    ports = list(list_ports.comports())
    if requested:
        for p in ports:
            if p.device.lower() == requested.lower():
                return p.device
        return requested
    for p in ports:
        if (p.vid, p.pid) in CP2102_IDS:
            return p.device
    if len(ports) == 1:
        return ports[0].device
    if not ports:
        sys.exit("没有可用串口。板载 USB-UART 是 CP2102，请确认插的是板上标 USB-UART / UART 的那个 Type-C 口")
    print("检测到多个串口，且没有 CP2102，请用 -p 指定：")
    list_ports_verbose()
    sys.exit(2)


def main():
    ap = argparse.ArgumentParser(description="盘古50Pro 串口监视器（CoreMark 调试）")
    ap.add_argument("-p", "--port", help="串口号，如 COM7；不填则自动找 CP2102")
    ap.add_argument("-b", "--baud", type=int, default=9600, help="波特率（默认 9600）")
    ap.add_argument("-o", "--out", help="日志文件路径（默认 tools/../logs/serial_YYYYmmdd_HHMMSS.log）")
    ap.add_argument("--hex", action="store_true", help="十六进制显示（默认按文本显示）")
    ap.add_argument("--seconds", type=float, default=0, help="收满 N 秒后自动退出（0=一直收）")
    ap.add_argument("--list", action="store_true", help="只列出串口后退出")
    ap.add_argument("--no-reconnect", action="store_true", help="断线不重连")
    args = ap.parse_args()

    if args.list:
        list_ports_verbose()
        return

    port = pick_port(args.port)
    if args.out:
        log_path = args.out
    else:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        d = os.path.join(root, "logs")
        os.makedirs(d, exist_ok=True)
        log_path = os.path.join(d, "serial_%s.log" % dt.datetime.now().strftime("%Y%m%d_%H%M%S"))

    print("串口 %s @ %d-8-N-1   日志: %s" % (port, args.baud, log_path))
    print("（Ctrl-C 退出；下面每行前是接收时间）\n")

    found = {}
    t_end = time.time() + args.seconds if args.seconds > 0 else None
    global txt_f
    raw_f = open(log_path, "wb")
    txt_f = open(log_path + ".txt", "w", encoding="utf-8", errors="replace")

    try:
        while True:
            try:
                ser = serial.Serial(port, args.baud, timeout=0.2)
            except Exception as e:
                if args.no_reconnect:
                    sys.exit("打开串口失败：%s" % e)
                print("[%s] 打开 %s 失败（%s），2 秒后重试…" % (dt.datetime.now().strftime("%H:%M:%S"), port, e))
                time.sleep(2)
                continue

            buf = b""
            try:
                while True:
                    chunk = ser.read(4096)
                    if chunk:
                        raw_f.write(chunk)
                        raw_f.flush()
                        buf += chunk
                        while b"\n" in buf:
                            line, buf = buf.split(b"\n", 1)
                            show(line)
                    if t_end and time.time() >= t_end:
                        raise KeyboardInterrupt
            except (serial.SerialException, OSError) as e:
                print("[%s] 串口断开（%s）" % (dt.datetime.now().strftime("%H:%M:%S"), e))
                if args.no_reconnect:
                    sys.exit(1)
                time.sleep(1)
                continue
            finally:
                try:
                    ser.close()
                except Exception:
                    pass
    except KeyboardInterrupt:
        pass
    finally:
        raw_f.close()
        txt_f.close()

    print("\n日志已保存：")
    print("   原始字节 : %s" % log_path)
    print("   文本行   : %s.txt" % log_path)
    if found:
        print("\n本次收到的关键数据：")
        for k, v in found.items():
            print("   %-22s %s" % (k, v))


def show(raw_line):
    """打印一行（带时间戳 + 关键行高亮），并做成绩解析。"""
    global found
    line = raw_line.rstrip(b"\r")
    ts = dt.datetime.now().strftime("%H:%M:%S.%f")[:-3]
    if HEX_MODE:
        text = " ".join("%02X" % b for b in line)
    else:
        text = line.decode("utf-8", errors="replace")
    mark = "★ " if KEY.search(text) else "  "
    print("%s%s %s" % (mark, ts, text))
    try:
        txt_f.write(text + "\n")
        txt_f.flush()
    except Exception:
        pass
    for pat, name in ((SCORE, "CoreMark 分数"), (ITER_SEC, "迭代/秒"),
                      (TICKS, "Total ticks"), (SECS, "总秒数")):
        m = pat.search(text)
        if m:
            found[name] = m.group(1)


HEX_MODE = False
found = {}
txt_f = None
if __name__ == "__main__":
    HEX_MODE = "--hex" in sys.argv
    main()
