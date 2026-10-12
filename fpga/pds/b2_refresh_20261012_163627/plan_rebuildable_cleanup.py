"""Safer cleanup after automatic review: preserve history, archives and backups."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2].resolve()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    roots = [REPO/'fpga/pds'/n for n in ['coremark_b1','coremark_b3','coremark_b4','coremark_official','coremark_fresh_20261011']]
    roots += [p for p in (REPO/'tests/coremark/build').iterdir() if p.is_dir() and p.name != 'b2']
    roots += [REPO/'fpga/pds/coremark_b2/performance',REPO/'tests/coremark/build/b2/performance']
    extensions = {'.elf','.hex','.bin','.o','.map','.dis','.a','.d'}
    generated = set()
    for root in roots:
        if root.exists():
            generated.update(p.resolve() for p in root.rglob('*') if p.is_file() and
                             (p.suffix.lower() in extensions or p.name == 'coremark_build_info.h'))
    generated.update(p.resolve() for p in (REPO/'tests/coremark/build').iterdir() if p.is_file() and
                     (p.suffix.lower() in extensions or p.name == 'coremark_build_info.h'))
    libraries = [p for p in (REPO/'sim/programs').iterdir() if p.is_dir() and
                 (p.name.startswith('coremark_official') or
                  (p.name.startswith('btb_') and any(s in p.name for s in ['new_perf','new_val','old_perf','ratio_probe'])))]
    for root in libraries:
        generated.update(p.resolve() for p in root.rglob('*') if p.is_file())
    # Explicit non-adopted build entry points; historical logs/JSON/ZIP untouched.
    generated.update((REPO/'fpga/pds'/name).resolve() for name in ['build_coremark_b1.ps1','build_coremark_lto.ps1'])
    targets = []
    for p in sorted(generated):
        assert p.is_relative_to(REPO) and p.is_file()
        assert not any(part in p.parts for part in ['_backup_pre_build_report_20261010','coremark_official_reclone_20261011','ip_init_audit_20261012'])
        assert not p.is_relative_to(REPO/'fpga/pds/coremark_b2') or p.parent.name == 'performance'
        assert not p.is_relative_to(REPO/'tests/coremark/build/b2') or 'performance' in p.relative_to(REPO/'tests/coremark/build/b2').parts
        targets.append(dict(path=str(p),relative=str(p.relative_to(REPO)),sha256=sha(p),bytes=p.stat().st_size))
    protected = list((REPO/'tests/coremark/src').iterdir())
    protected += [p for p in (REPO/'tests/unofficial_test_data').iterdir() if p.is_file()]
    protected += [REPO/'rtl/soc/myCPU.sv',REPO/'rtl/core/l0_cache.v',REPO/'rtl/include/defines.vh']
    for mode in ['performance_long','validation','sim_performance','sim_validation']:
        protected += [p for p in (REPO/'fpga/pds/coremark_b2'/mode).iterdir() if p.is_file()]
    protected += [REPO/'fpga/pds'/n for n in ['imem_coremark.dat','dmem_coremark.dat']]
    plan = dict(scope='Only reproducible non-B2 generated binaries and compiled libraries and non-B2 build scripts; all history, backups, audit data and ZIP archives preserved',
                delete_files=targets,protected=[dict(path=str(p.resolve()),sha256=sha(p)) for p in protected if p.is_file()])
    (HERE/'rebuildable_cleanup_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Rebuildable files planned:',len(targets),'bytes:',sum(x['bytes'] for x in targets))


if __name__ == '__main__':
    main()
