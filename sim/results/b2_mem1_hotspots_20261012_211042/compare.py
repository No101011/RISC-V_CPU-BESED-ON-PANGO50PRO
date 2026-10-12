"""Compare current timed PC counters with the preserved pre-load-optimization B2 run."""
import json
from pathlib import Path

here = Path(__file__).resolve().parent
current = json.loads((here / 'summary.json').read_text())
baseline = json.loads((here.parent / 'b2_hotspots_20261011_220300/summary.json').read_text())
now = current['scopes']['COREMARK_TIMED']
old = baseline['scopes']['COREMARK_TIMED']
metrics = ['cycles', 'retired_arch_instructions', 'retired_units', 'retired_fused_pairs',
           'load_dependency_cycles', 'mul_dependency_cycles', 'dependency_stall_cycles',
           'load_and_mul_dependency_cycles', 'ex1_load_dependency_cycles',
           'ex2_load_dependency_cycles', 'mem1_load_dependency_cycles',
           'ex1_mul_dependency_cycles', 'ex2_mul_dependency_cycles',
           'dram_stall_cycles', 'mdu_stall_cycles', 'csr_stall_cycles',
           'resolved_branches', 'branch_mispredictions', 'resolved_jumps',
           'jump_mispredictions', 'prediction_redirects', 'frontend_empty_opportunity_cycles']
comparison = {key: {'previous': old[key], 'current': now[key],
                    'delta': now[key] - old[key]}
              for key in metrics if key in old and key in now}
cycle_reduction = old['cycles'] - now['cycles']
pc_changes = {}
for metric in ['load_dependency_consumer_cycles', 'mul_dependency_consumer_cycles',
               'e1_load_producer_cycles', 'e2_load_producer_cycles',
               'e1_mul_producer_cycles', 'e2_mul_producer_cycles', 'branch_mispredictions']:
    previous = {row['pc']: row for row in baseline['hotspots'].get(metric, [])}
    present = {row['pc']: row for row in current['hotspots'].get(metric, [])}
    rows = []
    for pc in previous.keys() | present.keys():
        old_count = previous.get(pc, {}).get('count', 0)
        new_count = present.get(pc, {}).get('count', 0)
        annotation = present.get(pc, previous.get(pc))
        rows.append({'pc': pc, 'function': annotation['function'],
                     'instruction': annotation['instruction'], 'previous': old_count,
                     'current': new_count, 'cycles_or_events_saved': old_count-new_count})
    pc_changes[metric] = sorted(rows, key=lambda row: (-row['current'], row['pc']))

result = {
    'baseline_scope': 'B2 BTB, before both EX2 L0 and ordinary-load MEM1 forwarding',
    'current_scope': 'B2 BTB plus EX2 L0 and ordinary-load MEM1 forwarding',
    'warning': 'This comparison combines two RTL optimizations; no intermediate EX2-only timed run is available.',
    'metrics': comparison, 'cycles_saved': cycle_reduction,
    'cycle_reduction_percent': 100*cycle_reduction/old['cycles'],
    'throughput_gain_percent': 100*(old['cycles']/now['cycles']-1),
    'load_wait_reduction_percent': 100*(old['load_dependency_cycles']-now['load_dependency_cycles'])/old['load_dependency_cycles'],
    'load_share_of_current_cycles_percent': 100*now['load_dependency_cycles']/now['cycles'],
    'mul_share_of_current_cycles_percent': 100*now['mul_dependency_cycles']/now['cycles'],
    'pc_changes': pc_changes,
    'ideal_remove_one_ex2_mul_wait_cycle': {
        'candidate_cycles': now['ex2_mul_dependency_cycles'],
        'scope': 'Opportunity estimate only; assumes all these cycles disappear and other behavior is unchanged.',
        'throughput_gain_percent': 100*(now['cycles']/(now['cycles']-now['ex2_mul_dependency_cycles'])-1)
    }
}
(here / 'comparison.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps({key:value for key,value in result.items() if key != 'pc_changes'}, indent=2))
