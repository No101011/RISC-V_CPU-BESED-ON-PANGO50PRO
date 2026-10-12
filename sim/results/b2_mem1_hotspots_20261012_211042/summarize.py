"""Check B2's timed counters, attribute PC hotspots and preserve run evidence."""
import csv
import hashlib
import json
import math
import re
import struct
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
IMAGE = REPO / "fpga/pds/coremark_b2/sim_performance"


def read_functions(elf):
    data = elf.read_bytes()
    header = struct.unpack_from("<16sHHIIIIIHHHHHH", data)
    assert data[:7] == b"\x7fELF\x01\x01\x01" and header[2] == 243
    sections = [struct.unpack_from("<10I", data, header[6] + i * header[11])
                for i in range(header[12])]
    functions = []
    for section in sections:
        if section[1] != 2:
            continue
        assert section[9] == 16
        st = sections[section[6]]
        strings = data[st[4]:st[4]+st[5]]
        for offset in range(section[4], section[4]+section[5], 16):
            name, address, size, info, _, index = struct.unpack_from("<IIIBBH", data, offset)
            if name and index and info & 15 == 2 and size:
                end = strings.index(b"\0", name)
                functions.append((address, size, strings[name:end].decode("ascii")))
    return functions


def main():
    input_records = json.loads((HERE / "inputs_before.json").read_text(encoding="utf-8"))
    for record in input_records:
        assert hashlib.sha256(Path(record["Path"]).read_bytes()).hexdigest() == record["SHA256"], record["Path"]
    log = (HERE / "performance.log").read_text(encoding="utf-8", errors="replace")
    scopes = {}
    with (HERE / "performance.csv").open(newline="") as f:
        for row in csv.DictReader(f):
            value = row["value"]
            if re.fullmatch(r"[0-9]+", value):
                value = int(value)
            elif re.fullmatch(r"[0-9]+\.[0-9]+", value):
                value = float(value)
            scopes.setdefault(row["scope"], {})[row["metric"]] = value
    meta, timed = scopes["METADATA"], scopes["COREMARK_TIMED"]
    assert meta["exit_reason"] == "EXIT" and meta["boundary_errors"] == 0
    assert meta["uart_ticks_match"] == 1 and meta["run_mode"] == "performance"
    assert timed["iterations"] == 10 and meta["tb_cpu_hz"] == 100000000
    crc = {}
    for name, value in zip(("seedcrc", "crclist", "crcmatrix", "crcstate"),
                           ("e9f5", "e714", "1fd7", "8e3a")):
        match = re.search(r"\b" + name + r"\s*:\s*0x([0-9a-fA-F]+)", log)
        assert match and int(match[1], 16) == int(value, 16), name
        crc[name] = value
    final_crc = re.search(r"\bcrcfinal\s*:\s*0x([0-9a-fA-F]+)", log)
    assert final_crc and int(final_crc[1], 16) == 0xfcaf
    crc["crcfinal"] = "fcaf"
    assert "ERROR! Must execute for at least 10 secs" in log
    assert "** Error:" not in log and "** Fatal:" not in log
    assert log.count("Errors: 0, Warnings: 0") >= 2
    assert timed["retired_arch_instructions"] == timed["retired_units"] + timed["retired_fused_pairs"]
    assert timed["dependency_stall_cycles"] == (
        timed["load_dependency_cycles"] + timed["mul_dependency_cycles"] -
        timed["load_and_mul_dependency_cycles"])
    for name in ("WHOLE_PROGRAM", "COREMARK_TIMED"):
        s = scopes[name]
        expected_cpi = s["cycles"] / s["retired_arch_instructions"]
        assert math.isclose(s["cpi_arch"], expected_cpi, abs_tol=1e-8), (name, s["cpi_arch"], expected_cpi)
        assert math.isclose(s["cycles_per_retired_unit"], s["cycles"]/s["retired_units"], abs_tol=1e-8)
        s["branch_accuracy_percent"] = 100 * (1-s["branch_mispredictions"]/s["resolved_branches"])
        s["jump_accuracy_percent"] = 100 * (1-s["jump_mispredictions"]/s["resolved_jumps"])
    assert math.isclose(timed["throughput_per_mhz_estimate"],
                        1e6 * timed["iterations"] / timed["cycles"], abs_tol=1e-8)
    functions = read_functions(IMAGE / "coremark.elf")
    instruction = {}
    for line in (IMAGE / "coremark.dis").read_text().splitlines():
        match = re.match(r"\s*([0-9a-f]+):\s+[0-9a-f]+\s+(.+)", line)
        if match:
            instruction[int(match[1], 16)] = match[2].strip()
    hotspots = {}
    with (HERE / "hotspots.csv").open(newline="") as f:
        for row in csv.DictReader(f):
            assert row["scope"] == "COREMARK_TIMED"
            pc, count = int(row["pc"], 16), int(row["value"])
            matches = [item for item in functions if item[0] <= pc < item[0]+item[1]]
            assert matches and pc in instruction, hex(pc)
            base, _, fn = min(matches, key=lambda item: item[1])
            hotspots.setdefault(row["metric"], []).append({
                "pc": f"{pc:08x}", "function": fn, "function_offset": pc-base,
                "instruction": instruction[pc], "count": count})
    aliases = {
        "load_dependency_consumer_cycles": "load_dependency_cycles",
        "mul_dependency_consumer_cycles": "mul_dependency_cycles",
        "e1_load_producer_cycles": "ex1_load_dependency_cycles",
        "e2_load_producer_cycles": "ex2_load_dependency_cycles",
        "m1_load_producer_cycles": "mem1_load_dependency_cycles",
        "e1_mul_producer_cycles": "ex1_mul_dependency_cycles",
        "e2_mul_producer_cycles": "ex2_mul_dependency_cycles",
        "d1_store_buffer_selected": "d1_storebuffer_selected"}
    totals = {key: sum(row["count"] for row in rows) for key, rows in hotspots.items()}
    for key in ("resolved_branches", "branch_mispredictions", "branch_direction_errors",
                "branch_target_errors", "d1_eligible_probes", "d1_fastpath_hits",
                "d1_l0_selected", "d1_fastpath_misses"):
        aliases[key] = key
    for key, aggregate in aliases.items():
        assert totals.get(key, 0) == timed[aggregate], (key, totals.get(key, 0), timed[aggregate])
    assert sum(totals.get(k, 0) for k in ("resolved_jal", "resolved_returns", "resolved_other_jumps")) == timed["resolved_jumps"]
    assert sum(totals.get(k, 0) for k in ("jal_mispredictions", "return_mispredictions", "other_jump_mispredictions")) == timed["jump_mispredictions"]
    by_function = {}
    for key, rows in hotspots.items():
        rows.sort(key=lambda row: (-row["count"], row["pc"]))
        counter = Counter()
        for row in rows:
            counter[row["function"]] += row["count"]
            row["share_of_bucket_percent"] = 100*row["count"]/totals[key]
        by_function[key] = [{"function": fn, "count": value,
                             "share_of_bucket_percent": 100*value/totals[key]}
                            for fn, value in counter.most_common()]
    with (HERE / "hotspots_annotated.csv").open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["metric", "pc", "function", "offset", "instruction", "count", "bucket_percent"])
        for key, rows in hotspots.items():
            for row in rows:
                writer.writerow([key, row["pc"], row["function"], row["function_offset"],
                                 row["instruction"], row["count"], row["share_of_bucket_percent"]])
    manifest = json.loads((IMAGE / "build_manifest.json").read_text())
    for filename in ("coremark.elf", "imem_coremark.dat", "dmem_coremark.dat"):
        assert hashlib.sha256((IMAGE / filename).read_bytes()).hexdigest() == manifest["sha256"][filename]
    assert hashlib.sha256((REPO / "rtl/soc/myCPU.sv").read_bytes()).hexdigest() == "825a7158b3eaf00e546f86ff4b22491ade322cb8a56d624ff9ca3000c797783e"
    sha256 = {}
    for path in sorted((REPO / "rtl/core").glob("*.v")) + sorted((REPO / "rtl/include").glob("*.vh")) + [
            REPO / "rtl/soc/myCPU.sv", REPO / "sim/tb/tb_myCPU/tb_myCPU.sv",
            REPO / "sim/programs/coremark.do", IMAGE / "coremark.elf",
            IMAGE / "imem.hex", IMAGE / "dmem.hex"]:
        sha256[path.relative_to(REPO).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    summary = {"simulator": "ModelSim SE-64 2020.4", "configuration": "B2 Zba+O3, no LTO, BTB plus EX2 L0 and MEM1 ordinary-load live forwarding",
               "feature_switches": {"FUSE_EN": True, "FUSE_F2": True,
                                    "SUBWORD_FAST": True, "SUBWORD_SPEC": False},
               "crc": crc, "scopes": scopes, "hotspot_totals": totals,
               "inputs_unchanged_after_simulation": True,
               "duration_check": "Expected failure: 10 iterations take less than 10 seconds; this is a hotspot simulation, not a formal score.",
               "hotspots": hotspots, "function_hotspots": by_function, "input_sha256": sha256,
               "checks": "CRC, EXIT, UART ticks, timer window, histogram sums, ELF mapping and printed CPI checked; one complete simulation run",
               "limitations": "10 iterations at TB 100 MHz; not an official 10-second score; cause/stage counters can overlap."}
    (HERE / "summary.json").write_text(json.dumps(summary, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"timed": timed, "hotspot_totals": totals,
                      "top_functions": {k: v[:3] for k, v in by_function.items()}}, indent=2))


if __name__ == "__main__":
    main()
