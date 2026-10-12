"""Record the refreshed B2 packages and verify current PDS initialization."""
import hashlib
import importlib.util
import json
import re
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PDS = Path('E:/FPGA/github/ZiGuang/RISCV_BASEDON_PANGU')
MODES = ['performance_long','validation','sim_performance','sim_validation']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    inputs = json.loads((HERE/'rtl_inputs_before.json').read_text())
    assert all(sha(Path(x['path'])) == x['sha256'] for x in inputs), 'CPU RTL changed during this task'
    log = (HERE/'build_all.log').read_text(encoding='utf-8-sig',errors='replace')
    assert not re.search(r'\b(?:warning|error):',log,re.I)
    packages = []
    for mode in MODES:
        base = REPO/'fpga/pds/coremark_b2'/mode
        path = base/'build_manifest.json'
        manifest = json.loads(path.read_text())
        oldpath = HERE/'fpga/pds/coremark_b2'/mode/'build_manifest.json'
        old = json.loads(oldpath.read_text())
        assert '-O3' in manifest['compiler_flags'] and '-flto' not in manifest['compiler_flags']
        assert '-flto' not in manifest['linker_flags']
        for name,depth in [('imem_coremark.dat',8192),('dmem_coremark.dat',32768)]:
            raw = (base/name).read_bytes()
            assert len(raw.splitlines()) == depth and b'\r' not in raw and not raw.startswith(b'\xef\xbb\xbf')
            assert all(re.fullmatch(rb'[0-9a-fA-F]{8}',line) for line in raw.splitlines())
            assert sha(base/name) == manifest['sha256'][name]
        manifest.update(variant='B2',optimization='O3',lto=False,rebuilt_date='2026-10-12',
            build_exit_code=0,text_bytes=21836,
            rtl_mycpu_sha256_at_rebuild=sha(REPO/'rtl/soc/myCPU.sv'),
            runtime_status='Recompiled and statically checked; no new RTL simulation or board run in this task',
            previous_manifest_snapshot=str(oldpath.relative_to(REPO)),
            image_bytes_match_previous_package={name:manifest['sha256'][name]==old['sha256'][name]
                for name in ['imem_coremark.dat','dmem_coremark.dat']})
        manifest['historical_board_evidence'] = {key:value for key,value in old.items()
            if key.startswith('board_run_evidence')}
        for item in base.iterdir():
            if item.is_file() and item.name != 'build_manifest.json':
                manifest['sha256'][item.name] = sha(item)
        path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        packages.append(dict(package=mode,run_mode=manifest['run_mode'],iterations=manifest['iterations'],
            cpu_hz=manifest['cpu_hz'],text_bytes=21836,imem_sha256=manifest['sha256']['imem_coremark.dat'],
            dmem_sha256=manifest['sha256']['dmem_coremark.dat'],
            image_bytes_match_previous_package=manifest['image_bytes_match_previous_package']))
    for name in ['imem_coremark.dat','dmem_coremark.dat']:
        assert sha(REPO/'fpga/pds'/name) == sha(REPO/'fpga/pds/coremark_b2/performance_long'/name)
    spec = importlib.util.spec_from_file_location('audit',REPO/'fpga/pds/ip_init_audit_20261012/audit.py')
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    ip_result = {}
    for ip,kind,width,depth in [('irom_bram','imem',4,8192),('bram_dram','dmem',16,32768)]:
        directory = PDS/'ipcore'/ip
        dat = REPO/'fpga/pds/coremark_b2/performance_long'/f'{kind}_coremark.dat'
        decoded = audit.decode(directory/'rtl'/f'{ip}_init_param.v',width,depth)
        assert decoded == [int(x,16) for x in dat.read_text().splitlines()]
        assert dat.as_posix() in (directory/f'{ip}.idf').read_text()
        assert dat.as_posix() in (directory/f'{ip}.v').read_text()
        ip_result[ip] = dict(all_words_match=True,words=depth,
            init_sha256=sha(directory/'rtl'/f'{ip}_init_param.v'),
            wrapper_sha256=sha(directory/f'{ip}.v'))
    plan = json.loads((HERE/'cleanup_plan.json').read_text(encoding='utf-8'))
    assert all(not Path(x['path']).exists() for x in plan['delete_files'])
    for root in [REPO/'fpga/pds',REPO/'tests/coremark',REPO/'tests/coremark_official_reclone_20261011']:
        for path in root.rglob('*.dat'):
            if path.name in ['imem_coremark.dat','dmem_coremark.dat']:
                assert str(path) in plan['keep'], str(path)
    historical_summary = json.loads((HERE/'fpga/pds/coremark_b2/build_summary.json').read_text())
    summary = dict(variant='B2',isa='rv32im_zba_zicsr',optimization='O3',lto=False,rebuilt_date='2026-10-12',
        packages=packages,ip_initialization=ip_result,
        cleanup=dict(deleted_dat_files=len(plan['delete_files']),
                     removed_archive_dat_entries=sum(len(x['remove_entries']) for x in plan['archives'])),
        historical_board_pair=historical_summary.get('board_pair_after_btb'),
        status='B2 refreshed, active DAT selected, generated IP initialization matches; PDS implementation/bitstream/download pending',
        rtl_unchanged=True,new_runtime_tests=False)
    (HERE/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (REPO/'fpga/pds/coremark_b2/build_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    adoptedpath = REPO/'fpga/pds/adopted_coremark_config.json'
    adopted = json.loads(adoptedpath.read_text())
    adopted.update(rebuilt_date='2026-10-12',generated_ip_initialization_matches=True,
        cleanup_report=str((HERE/'cleanup_plan.json').relative_to(REPO)),status=summary['status'])
    adoptedpath.write_text(json.dumps(adopted,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    # Keep old manifest checksums as historical evidence, but mark missing DATs.
    retired = set(Path(x['path']).parent for x in plan['delete_files'])
    for directory in retired:
        manifestpath = directory/'build_manifest.json'
        if manifestpath.exists():
            manifest = json.loads(manifestpath.read_text())
            manifest['dat_distribution_status'] = 'Removed at user request on 2026-10-12; original hashes and board logs are historical evidence'
            manifestpath.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for package in ['coremark_b1','coremark_b3','coremark_b4','coremark_official','coremark_fresh_20261011']:
        readme = REPO/'fpga/pds'/package/'README.md'
        if readme.exists():
            text = readme.read_text(encoding='utf-8-sig')
            note = '> 2026-10-12：用户决定仅采用B2，本目录DAT已删除；源码、ELF、历史日志及参数记录保留。当前镜像见 ../coremark_b2/。\n\n'
            if not text.startswith(note):
                readme.write_text(note+text,encoding='utf-8')
    # Selected manifest follows the fresh package metadata, not a retired variant.
    (REPO/'fpga/pds/selected_coremark_image.json').write_bytes((REPO/'fpga/pds/coremark_b2/performance_long/build_manifest.json').read_bytes())
    archive = REPO/'fpga/pds/coremark_b2_2026-10-12.zip'
    with ZipFile(archive,'w',compression=ZIP_DEFLATED) as z:
        for mode in MODES:
            for path in (REPO/'fpga/pds/coremark_b2'/mode).rglob('*'):
                if path.is_file():
                    z.write(path,str(path.relative_to(REPO/'fpga/pds')))
        for name in ['README.md','build_summary.json']:
            path = REPO/'fpga/pds/coremark_b2'/name
            z.write(path,str(path.relative_to(REPO/'fpga/pds')))
    with ZipFile(archive) as z:
        assert z.testzip() is None
        assert len([n for n in z.namelist() if n.endswith('.dat')]) == 8
    print(json.dumps(summary,ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
