"""Locate CoreMark timer CSR reads in the ELF that produced the loaded HEX.

Only Python's standard library is needed. Output is a numeric Tcl dictionary;
failure is deliberate when symbols or images do not match (never guess a PC).
"""

import argparse
import struct
import sys
from pathlib import Path


def read_hex(path):
    words = []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.split("//", 1)[0].strip()
        if not line:
            continue
        if len(line) != 8:
            raise ValueError(f"{path}: expected one 32-bit word per line")
        words.append(struct.pack("<I", int(line, 16)))
    return b"".join(words)


def metadata(elf_path, imem_path, dmem_path):
    data = elf_path.read_bytes()
    if data[:7] != b"\x7fELF\x01\x01\x01":
        raise ValueError("Expected a little-endian ELF32 file")
    header = struct.unpack_from("<16sHHIIIIIHHHHHH", data)
    if header[2] != 243:
        raise ValueError("Expected RISC-V ELF")
    if header[7] & 1:
        raise ValueError("Compressed-instruction ELF is unsupported by this RV32IM timer locator")
    shoff, shsize, shnum, shstrndx = header[6], header[11], header[12], header[13]
    if shsize != 40 or not shnum or shstrndx >= shnum:
        raise ValueError("Unsupported ELF section table")
    sections = [struct.unpack_from("<10I", data, shoff + i * shsize)
                for i in range(shnum)]

    def payload(section):
        return data[section[4]:section[4] + section[5]]

    def name(table, offset):
        end = table.index(b"\0", offset)
        return table[offset:end].decode("ascii")

    names = payload(sections[shstrndx])
    by_name = {name(names, s[0]): s for s in sections}
    text = by_name[".text"]
    imem, dmem = read_hex(imem_path), read_hex(dmem_path)
    if text[3] != 0x80000000 or payload(text) != imem[:text[5]]:
        raise ValueError("ELF .text and IROM HEX differ")
    # Compare every initialized allocatable section in the data address range.
    for section in sections:
        if (section[2] & 2) and section[1] != 8 and section[5]:
            address = section[3]
            if 0x80100000 <= address < 0x80120000:
                offset = address - 0x80100000
                if payload(section) != dmem[offset:offset + section[5]]:
                    raise ValueError("ELF initialized data and DRAM HEX differ")

    symbols = {}
    for section in sections:
        if section[1] != 2:  # SHT_SYMTAB
            continue
        if section[9] != 16:
            raise ValueError("Unsupported ELF symbol table")
        strings = payload(sections[section[6]])
        for offset in range(section[4], section[4] + section[5], 16):
            st_name, value, size, info, _, index = struct.unpack_from("<IIIBBH", data, offset)
            if st_name and index and index < shnum:
                symbols[name(strings, st_name)] = (value, size, info, index)

    def timer_pc(function):
        matches = [v for n, v in symbols.items()
                   if n == function or n.startswith(function + ".")]
        pcs = []
        for address, size, info, index in matches:
            if info & 15 != 2:  # STT_FUNC
                continue
            section = sections[index]
            code = data[section[4] + address - section[3]:
                        section[4] + address - section[3] + size]
            for offset in range(0, len(code) - 3, 4):
                instruction = struct.unpack_from("<I", code, offset)[0]
                # csrrs rd,mcycle,x0 (csrr pseudoinstruction), rd != x0.
                if instruction & 0xFFFFF07F == 0xB0002073 and instruction & 0xF80:
                    pcs.append(address + offset)
        if len(pcs) != 1:
            raise ValueError(f"Need exactly one mcycle read in {function}; found {len(pcs)}. "
                             "Inlined/LTO timers require preserved timer function symbols.")
        return pcs[0]

    seed = symbols["seed4_volatile"][0]
    offset = seed - 0x80100000
    if offset < 0 or offset + 4 > len(dmem):
        raise ValueError("seed4_volatile is outside initialized DRAM HEX")
    iterations = struct.unpack_from("<I", dmem, offset)[0]
    start, stop = timer_pc("start_time"), timer_pc("stop_time")
    if start == stop:
        raise ValueError("Timer boundaries must have different PCs")
    return start, stop, iterations, text[5]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--imem", type=Path, required=True)
    parser.add_argument("--dmem", type=Path, required=True)
    parser.add_argument("--elf", type=Path)
    args = parser.parse_args()
    elf = args.elf or args.imem.with_name("coremark.elf")
    try:
        start, stop, iterations, text_bytes = metadata(elf, args.imem, args.dmem)
    except (OSError, ValueError, KeyError, IndexError, struct.error) as exc:
        print(f"CoreMark performance metadata: {exc}", file=sys.stderr)
        return 1
    print(f"start_pc {start:08x} stop_pc {stop:08x} iterations {iterations} text_bytes {text_bytes}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
