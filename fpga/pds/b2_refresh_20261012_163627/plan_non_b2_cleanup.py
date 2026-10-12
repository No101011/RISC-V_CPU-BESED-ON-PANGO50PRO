"""Plan explicit non-B2 CoreMark deletion; never delete shared source or ISA cases."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2].resolve()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    relative_dirs = [
        'fpga/pds/coremark_b1','fpga/pds/coremark_b3','fpga/pds/coremark_b4',
        'fpga/pds/coremark_official','fpga/pds/coremark_fresh_20261011',
        'tests/coremark_official_reclone_20261011','tests/coremark/_backup_pre_build_report_20261010',
        'fpga/pds/ip_init_audit_20261012','fpga/pds/coremark_b2/performance',
        'tests/coremark/build/b2/performance',
        'fpga/pds/b2_refresh_20261012_163627/ip_stage',
    ]
    relative_dirs += [str(p.relative_to(REPO)) for p in (REPO/'fpga/pds').glob('_backup_coremark_selection_*') if p.is_dir()]
    relative_dirs += [str(p.relative_to(REPO)) for p in (REPO/'tests/coremark/build').iterdir() if p.is_dir() and p.name != 'b2']
    relative_dirs += [str(p.relative_to(REPO)) for p in (REPO/'sim/programs').iterdir()
                     if p.is_dir() and (p.name.startswith('coremark_official') or
                         (p.name.startswith('btb_') and any(s in p.name for s in ['performance','validation','new_perf','new_val','old_perf','ratio_probe'])))]
    relative_files = [
        'fpga/pds/build_coremark_b1.ps1','fpga/pds/build_coremark_lto.ps1',
        'fpga/pds/coremark_b1_2026-10-11.zip','fpga/pds/coremark_b3_b4_lto_20261011.zip',
        'fpga/pds/coremark_fresh_20261011.zip','fpga/pds/coremark_lto_compare.md',
        'fpga/pds/coremark_lto_static_summary.json','fpga/pds/coremark_board_2026-10-10.log',
        'fpga/pds/coremark_board_2026-10-10_full_params.log','fpga/pds/coremark_build_parameters_2026-10-10.txt',
    ]
    relative_files += [str(p.relative_to(REPO)) for p in (REPO/'tests/coremark/build').iterdir() if p.is_file()]
    for name in ['ip_generated_before.zip','ram_reference_check.v','refresh_ram_init.py',
                 'prepare_cleanup.py','clean_archives.py','finalize.py','ip_rom_stdout.log','ip_rom_stderr.log']:
        relative_files.append(str((HERE/name).relative_to(REPO)))
    isa_keep = {'baseline_divu.do','baseline_divu.log','riscv_tests_isolated.do','riscv_tests.log'}
    old_results = REPO/'sim/results/btb_2bit_tag_20261011_194410'
    relative_files += [str(p.relative_to(REPO)) for p in old_results.iterdir() if p.is_file() and p.name not in isa_keep]
    protected = [REPO/'rtl/soc/myCPU.sv',REPO/'rtl/core/l0_cache.v',REPO/'rtl/include/defines.vh']
    protected += list((REPO/'tests/coremark/src').iterdir())
    protected += [p for p in (REPO/'tests/unofficial_test_data').glob('*') if p.is_file()]
    for mode in ['performance_long','validation','sim_performance','sim_validation']:
        base = REPO/'fpga/pds/coremark_b2'/mode
        protected += [base/n for n in ['imem_coremark.dat','dmem_coremark.dat','coremark.elf']]
    protected += [REPO/'fpga/pds'/n for n in ['imem_coremark.dat','dmem_coremark.dat']]
    protected = [p.resolve() for p in protected if p.is_file()]
    targets = []
    for relative,is_dir in [(x,True) for x in relative_dirs]+[(x,False) for x in relative_files]:
        path = (REPO/relative).resolve()
        if not path.exists():
            continue
        assert path.is_relative_to(REPO) and path != REPO
        assert not any(p==path or p.is_relative_to(path) for p in protected)
        assert path.is_dir() == is_dir
        members = [p for p in path.rglob('*') if p.is_file()] if is_dir else [path]
        assert not any('.git' in p.relative_to(REPO).parts for p in members)
        targets.append(dict(path=str(path),relative=str(path.relative_to(REPO)),directory=is_dir,
                            file_count=len(members),bytes=sum(p.stat().st_size for p in members)))
    plan = dict(root=str(REPO),targets=targets,
        protected=[dict(path=str(p),sha256=sha(p)) for p in protected],
        scope='Delete non-adopted CoreMark variants, duplicates and old B1 CoreMark runs; retain B2 and shared source/BSP and ISA records')
    (HERE/'non_b2_cleanup_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(targets=len(targets),files=sum(x['file_count'] for x in targets),
                         bytes=sum(x['bytes'] for x in targets),paths=[x['relative'] for x in targets]),ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
