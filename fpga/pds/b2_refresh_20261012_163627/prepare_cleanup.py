"""Inventory only obsolete CoreMark DATs; leave ISA tests and board demos alone."""
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
KEEP_DIRS = {'performance_long','validation','sim_performance','sim_validation'}
KEEP = {REPO/'fpga/pds'/name for name in ['imem_coremark.dat','dmem_coremark.dat']}
for directory in KEEP_DIRS:
    KEEP.update(REPO/'fpga/pds/coremark_b2'/directory/name for name in ['imem_coremark.dat','dmem_coremark.dat'])


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    # Confirm the selected packages before issuing any deletion plan.
    for directory in KEEP_DIRS:
        base = REPO/'fpga/pds/coremark_b2'/directory
        m = json.loads((base/'build_manifest.json').read_text())
        assert '-O3' in m['compiler_flags'] and '-flto' not in m['compiler_flags']
        assert '-flto' not in m['linker_flags']
        for name in ['imem_coremark.dat','dmem_coremark.dat']:
            assert sha(base/name) == m['sha256'][name]
    files = []
    for root in [REPO/'fpga/pds',REPO/'tests/coremark',REPO/'tests/coremark_official_reclone_20261011']:
        for path in root.rglob('*.dat'):
            if path in KEEP:
                continue
            if path.name not in {'imem_coremark.dat','dmem_coremark.dat'} and path.parent != REPO/'fpga/pds/ip_init_audit_20261012':
                continue
            assert path.resolve().is_relative_to(REPO.resolve())
            files.append(dict(path=str(path.resolve()),relative=str(path.relative_to(REPO)),sha256=sha(path),bytes=path.stat().st_size))
    archives = []
    for path in (REPO/'fpga/pds').glob('coremark_*.zip'):
        with ZipFile(path) as z:
            entries = [n for n in z.namelist() if n.lower().endswith('.dat')]
        if entries:
            archives.append(dict(path=str(path.resolve()),sha256=sha(path),remove_entries=entries))
    plan = dict(keep=[str(p) for p in sorted(KEEP)],delete_files=files,archives=archives,
                scope='Only obsolete/duplicate CoreMark images, obsolete 2200-iteration B2 DAT, and B4 decoded audit DAT; ISA fixtures/demos untouched')
    (HERE/'cleanup_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(delete_files=len(files),archive_dat_entries=sum(len(x['remove_entries']) for x in archives),
                         by_directory=sorted({str(Path(x['relative']).parent) for x in files})),ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
