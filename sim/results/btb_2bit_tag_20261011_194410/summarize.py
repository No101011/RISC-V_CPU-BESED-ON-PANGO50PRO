"""Check this run's logs/CSV and save the measured BTB comparison."""
import csv
import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent
results = {}
for name, mode, expected in (
    ("new_performance", "performance", ("e9f5", "e714", "1fd7", "8e3a")),
    ("baseline_performance", "performance", ("e9f5", "e714", "1fd7", "8e3a")),
    ("new_validation", "validation", ("18f2", "e3c1", "0747", "8d84")),
):
    log = (root / f"{name}.log").read_text(encoding="utf-8", errors="replace")
    scopes = {}
    with (root / f"{name}.csv").open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream):
            scopes.setdefault(row["scope"], {})[row["metric"]] = row["value"]
    meta, timed = scopes["METADATA"], scopes["COREMARK_TIMED"]
    assert meta["exit_reason"] == "EXIT", (name, meta)
    assert meta["uart_ticks_match"] == "1", (name, meta)
    assert meta["boundary_errors"] == "0", (name, meta)
    assert meta["run_mode"] == mode, (name, meta)
    assert timed["iterations"] == "10", (name, timed)
    checks = {}
    for metric, value in zip(("seedcrc", "crclist", "crcmatrix", "crcstate"), expected):
        match = re.search(r"\b" + metric + r"\s*:\s*0x([0-9a-fA-F]+)", log)
        assert match and int(match[1], 16) == int(value, 16), (name, metric, match)
        checks[metric] = value
    assert int(timed["retired_arch_instructions"]) == int(timed["retired_units"]) + int(timed["retired_fused_pairs"])
    assert int(timed["dependency_stall_cycles"]) == int(timed["load_dependency_cycles"]) + int(timed["mul_dependency_cycles"]) - int(timed["load_and_mul_dependency_cycles"])
    for scope in scopes.values():
        for key, value in list(scope.items()):
            if re.fullmatch(r"[0-9]+", value):
                scope[key] = int(value)
            elif re.fullmatch(r"[0-9]+\.[0-9]+", value):
                scope[key] = float(value)
    reported_derived = {}
    for scope_name in ("WHOLE_PROGRAM", "COREMARK_TIMED"):
        scope = scopes[scope_name]
        reported_derived[scope_name] = {key: scope[key] for key in ("cpi_arch", "cycles_per_retired_unit")}
        scope["cpi_arch"] = scope["cycles"] / scope["retired_arch_instructions"]
        scope["cycles_per_retired_unit"] = scope["cycles"] / scope["retired_units"]
        scope["branch_accuracy_percent"] = (1 - scope["branch_mispredictions"] / scope["resolved_branches"]) * 100
        scope["jump_accuracy_percent"] = (1 - scope["jump_mispredictions"] / scope["resolved_jumps"]) * 100
    results[name] = {"crc": checks, "scopes": scopes, "reported_derived_metrics": reported_derived}

isa_log = (root / "riscv_tests.log").read_text(encoding="utf-8", errors="replace")
isa_match = re.search(r"SUMMARY: (\d+) PASS, (\d+) FAIL, (\d+) HANG", isa_log)
assert isa_match, "ISA regression incomplete"
isa = dict(zip(("pass", "fail", "hang"), map(int, isa_match.groups())))
assert isa == {"pass": 46, "fail": 1, "hang": 0}, isa
assert "rv32um-p-divu/testnum=8" in isa_log
old_divu_log = (root / "baseline_divu.log").read_text(encoding="utf-8", errors="replace")
assert "SUMMARY: 0 PASS, 1 FAIL, 0 HANG" in old_divu_log
assert "rv32um-p-divu/testnum=8" in old_divu_log
isa["known_failure"] = "DIVU testnum=8; reproduced with the pre-BTB myCPU backup"

hashes = json.loads((root / "input_sha256.json").read_text(encoding="utf-8-sig"))
for entry in hashes:
    assert hashlib.sha256(Path(entry["Path"]).read_bytes()).hexdigest().upper() == entry["Hash"], entry["Path"]

old = results["baseline_performance"]["scopes"]["COREMARK_TIMED"]
new = results["new_performance"]["scopes"]["COREMARK_TIMED"]
comparison = {
    "cycles_saved": old["cycles"] - new["cycles"],
    "cycle_reduction_percent": (1 - new["cycles"] / old["cycles"]) * 100,
    "throughput_gain_percent": (old["cycles"] / new["cycles"] - 1) * 100,
    "old_branch_accuracy_percent": (1 - old["branch_mispredictions"] / old["resolved_branches"]) * 100,
    "new_branch_accuracy_percent": (1 - new["branch_mispredictions"] / new["resolved_branches"]) * 100,
    "direction_errors_saved": old["branch_direction_errors"] - new["branch_direction_errors"],
}
summary = {"simulator": "ModelSim SE-64 2020.4", "tb_hz": 100000000,
           "iterations": 10, "isa": isa, "comparison": comparison, "runs": results,
           "derived_metrics_note": "TB printed incorrect zero ratios for several metrics. Summary CPI and prediction accuracy are recalculated from raw counts; original logs/CSV are preserved.",
           "limitations": "Short RTL simulation; not an official 10-second score or PDS timing validation."}
(root / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"isa": isa, "comparison": comparison}, indent=2))
