"""Remove obsolete DAT members from old CoreMark archives, retaining other files."""
import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2].resolve()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    plan = json.loads((HERE/'cleanup_plan.json').read_text(encoding='utf-8'))
    result = []
    for entry in plan['archives']:
        path = Path(entry['path']).resolve()
        assert path.is_relative_to(REPO) and path.parent == REPO/'fpga/pds'
        assert path.suffix == '.zip' and path.name.startswith('coremark_')
        assert sha(path) == entry['sha256']
        temporary = path.with_suffix('.zip.cleaning')
        assert temporary.resolve().is_relative_to(REPO) and not temporary.exists()
        with ZipFile(path) as source, ZipFile(temporary,'w',compression=ZIP_DEFLATED) as destination:
            assert [n for n in source.namelist() if n.lower().endswith('.dat')] == entry['remove_entries']
            for info in source.infolist():
                if info.filename not in entry['remove_entries']:
                    destination.writestr(info,source.read(info.filename))
        with ZipFile(temporary) as check:
            assert check.testzip() is None
            assert not any(n.lower().endswith('.dat') for n in check.namelist())
        temporary.replace(path)
        result.append(dict(path=str(path),removed_dat_entries=len(entry['remove_entries']),
                           old_sha256=entry['sha256'],new_sha256=sha(path)))
    (HERE/'archive_cleanup.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Removed archive DAT entries:',sum(x['removed_dat_entries'] for x in result))


if __name__ == '__main__':
    main()
