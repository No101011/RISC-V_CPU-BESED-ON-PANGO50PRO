"""Check unchanged B2 execution and summarize read-only EX2 shadow queries."""
import csv
import hashlib
import json
import re
import struct
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
BASELINE = REPO / 'sim/results/b2_hotspots_20261011_220300'
IMAGE = REPO / 'fpga/pds/coremark_b2/sim_performance'


def scopes(path):
    result = defaultdict(dict)
    for row in csv.DictReader(path.open(newline='')):
        value = row['value']
        result[row['scope']][row['metric']] = int(value) if value.isdigit() else value
    return result


def functions(path):
    data = path.read_bytes()
    h = struct.unpack_from('<16sHHIIIIIHHHHHH', data)
    assert data[:7] == b'\x7fELF\x01\x01\x01' and h[2] == 243
    sections = [struct.unpack_from('<10I', data, h[6] + i*h[11]) for i in range(h[12])]
    result = []
    for section in sections:
        if section[1] != 2:
            continue
        strings_section = sections[section[6]]
        strings = data[strings_section[4]:strings_section[4]+strings_section[5]]
        for off in range(section[4], section[4]+section[5], section[9]):
            name, address, size, info, _, index = struct.unpack_from('<IIIBBH', data, off)
            if name and index and info & 15 == 2 and size:
                result.append((address, size, strings[name:strings.index(b'\0', name)].decode()))
    return result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    current, old = scopes(HERE/'performance.csv'), scopes(BASELINE/'performance.csv')
    meta, timed = current['METADATA'], current['COREMARK_TIMED']
    assert meta['exit_reason'] == 'EXIT' and meta['boundary_errors'] == 0
    assert meta['uart_ticks_match'] == 1 and timed['iterations'] == 10
    # Observer must not change a single pre-existing raw counter or PC bucket.
    for scope in ('WHOLE_PROGRAM', 'COREMARK_TIMED'):
        for key, value in old[scope].items():
            assert current[scope][key] == value, (scope, key, value, current[scope][key])
    assert sha(HERE/'hotspots.csv') == sha(BASELINE/'hotspots.csv')
    log = (HERE/'performance.log').read_text(encoding='utf-8', errors='replace')
    for name, expected in [('seedcrc','e9f5'),('crclist','e714'),('crcmatrix','1fd7'),('crcstate','8e3a'),('crcfinal','fcaf')]:
        assert re.search(r'\b'+name+r'\s*:\s*0x'+expected+r'\b', log), name
    assert 'Errors: 0, Warnings: 0' in log
    assert not re.search(r'^# \*\* (?:Error|Fatal):', log, re.M)
    before = json.loads((HERE/'dut_inputs_before.json').read_text(encoding='utf-8-sig'))
    for item in before:
        assert sha(Path(item['path'])) == item['sha256'], item['path']
    fn = functions(IMAGE/'coremark.elf')
    dis = {}
    for line in (IMAGE/'coremark.dis').read_text().splitlines():
        m = re.match(r'\s*([0-9a-f]+):\s+[0-9a-f]+\s+(.+)', line)
        if m:
            dis[int(m[1],16)] = m[2].strip()
    totals, per_metric, annotated = Counter(), defaultdict(list), []
    for row in csv.DictReader((HERE/'ex2_shadow.csv').open(newline='')):
        assert row['scope'] == 'COREMARK_TIMED'
        pc, count = int(row['pc'],16), int(row['value'])
        matches = [f for f in fn if f[0] <= pc < f[0]+f[1]]
        assert matches and pc in dis, hex(pc)
        base, _, name = min(matches, key=lambda f:f[1])
        entry = dict(metric=row['metric'], pc=f'{pc:08x}', function=name,
                     offset=pc-base, instruction=dis[pc], count=count)
        annotated.append(entry)
        totals[row['metric']] += count
        per_metric[row['metric']].append(entry)
    for metric, value in re.findall(r'\[EX2_SHADOW\] ([a-z0-9_]+)=([0-9]+)', log):
        assert totals[metric] == int(value), ('CSV/log mismatch', metric)
        totals[metric] = int(value)
    t = totals
    assert t['ex2_dram_aligned_probes'] == sum(t[f'ex2_{w}_probes'] for w in ('word','half','byte'))
    assert t['ex2_dram_aligned_probes'] == t['l0_raw_hits']+t['l0_invalid_misses']+t['l0_tag_misses']
    assert t['l0_safe_validated_hits'] == t['l0_guarded_hits']-t['l0_guarded_data_mismatches']
    assert t['ex2_load_dependency_cycles'] == timed['ex2_load_dependency_cycles']
    assert t['l0_safe_hits_with_ex2_dependency'] == t['l0_releasable_cycles']+t['l0_safe_dependency_other_block_cycles']
    assert t['l0_releasable_cycles'] == sum(t[f'l0_releasable_{w}_cycles'] for w in ('word','half','byte'))
    assert t['l0_releasable_cycles'] == t['l0_releasable_consumer_cycles']
    assert t['l0_or_store_buffer_releasable_cycles'] == t['l0_releasable_cycles']+t['store_buffer_only_releasable_cycles']
    # All hardware-guarded hits must match the addressed architectural data.
    # Equality is an observer assertion, not a realizable hardware hit condition.
    assert t['l0_guarded_data_mismatches'] == 0, 'Guard policy is insufficient; do not implement as proposed'
    with (HERE/'ex2_shadow_annotated.csv').open('w',newline='',encoding='utf-8') as f:
        writer = csv.DictWriter(f,fieldnames=['metric','pc','function','offset','instruction','count'])
        writer.writeheader()
        writer.writerows(sorted(annotated,key=lambda x:(x['metric'],-x['count'],x['pc'])))
    ranked = {key:sorted(rows,key=lambda x:-x['count']) for key,rows in per_metric.items()}
    by_function = {}
    for key in ('l0_releasable_cycles','l0_releasable_consumer_cycles','store_buffer_only_releasable_cycles'):
        count = Counter()
        for item in per_metric[key]:
            count[item['function']] += item['count']
        by_function[key] = dict(count.most_common())
    candidates = t['l0_releasable_cycles']
    summary = dict(
        configuration='B2 Zba+O3, no LTO; performance 10 iterations; TB 100 MHz',
        baseline_execution_unchanged=True, dut_and_image_hashes_unchanged=True,
        cycles=timed['cycles'], load_dependency_cycles=timed['load_dependency_cycles'],
        shadow_totals=dict(t), by_function=by_function, ranked=ranked,
        static_estimate=dict(
            saved_cycle_candidates=candidates,
            percent_of_total_cycles=100*candidates/timed['cycles'],
            percent_of_load_waits=100*candidates/timed['load_dependency_cycles'],
            percent_of_ex2_load_waits=100*candidates/t['ex2_load_dependency_cycles'],
            ideal_throughput_gain_percent=100*candidates/(timed['cycles']-candidates),
            word_only_candidates=t['l0_releasable_word_cycles'],
            word_only_share_percent=100*t['l0_releasable_word_cycles']/candidates,
            word_only_ideal_gain_percent=100*t['l0_releasable_word_cycles']/(timed['cycles']-t['l0_releasable_word_cycles'])),
        limitations=[
            'Read-only baseline trace; does not simulate the modified pipeline or changed cache evolution.',
            'L0 capacity, fill and invalidation policy unchanged; no incoming same-edge fill bypass.',
            'MEM1 and WB same-word stores conservatively block L0 even for disjoint byte lanes.',
            'No same-word store blocking cases occurred on raw L0 hits in this run; coherence corner cases are not tested.',
            'Existing EX2 readiness and any other stall/redirect are excluded from releasable counts.',
            'Store-buffer-only benefit is a separate subword-forwarding option, not a new L0-port benefit.',
            'Timing, resource cost and board performance of the proposed RTL remain unmeasured.'],
        inputs=before,
        observer_hashes={name:sha(REPO/name) for name in (
            'sim/tb/tb_myCPU/tb_myCPU.sv','sim/tb/tb_myCPU/ex2_l0_shadow.svh','sim/programs/coremark.do')})
    (HERE/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:summary[k] for k in ('cycles','shadow_totals','by_function','static_estimate')},ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
