#!/usr/bin/env python3
"""Package a CoreMark build for PDS, checking the unmodified official sources."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


OFFICIAL_COMMIT = '1f483d5b8316753a742cbf5590caf5bd0a4e4777'
# Normalized official source bytes at the pinned commit (CRLF -> LF).
OFFICIAL_MD5 = {
    'core_main.c': '4a9e6dadce1ac3866381021fbe843fc9',
    'core_list_join.c': '9007fe7861b60ee6f210d156b62974c8',
    'core_matrix.c': '5fa21a0f7c3964167c9691db531ca652',
    'core_state.c': 'fb49e7605c125306575a83f14f5798ac',
    'core_util.c': '45540ba2145adea1ec7ea2c72a1fbbcb',
    'coremark.h': 'b0ec69b6c8e75853d06accb3b1bcf534',
}


def make_dat(path, depth, padding):
    words = path.read_text(encoding='ascii').splitlines()
    if not words or len(words) > depth:
        raise ValueError('Invalid image length: {}'.format(path))
    if any(not re.fullmatch(r'[0-9a-fA-F]{8}', word) for word in words):
        raise ValueError('Invalid 32-bit hex word: {}'.format(path))
    return len(words), ('\n'.join(words + [padding] * (depth - len(words))) + '\n').encode('ascii')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', required=True)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    build = Path(args.build_dir).resolve()
    output = Path(args.output_dir).resolve()
    source = Path(__file__).resolve().parents[1] / 'src'
    source_hashes = {}
    for name, expected in OFFICIAL_MD5.items():
        digest = hashlib.md5((source / name).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
        if digest != expected:
            raise ValueError('Official source has changed: {}'.format(name))
        source_hashes[name] = digest

    header = (build / 'coremark_build_info.h').read_text(encoding='ascii')
    info = {name: json.loads(value) for name, value in
            re.findall(r'^#define (\w+) (".*")$', header, re.MULTILINE)}
    flags = info['FLAGS_STR']
    definitions = dict(re.findall(r'(?:^|\s)-D(\w+)=(\d+)(?=\s|$)', flags))
    perf = definitions.get('PERFORMANCE_RUN') == '1'
    valid = definitions.get('VALIDATION_RUN') == '1'
    if perf == valid or definitions.get('TOTAL_DATA_SIZE') != '2000':
        raise ValueError('Build must select exactly one official 2K run mode')
    mode = 'performance' if perf else 'validation'
    ticks_hz = int(definitions['CPU_HZ'])
    iterations = int(definitions['ITERATIONS'])
    if ticks_hz <= 0 or iterations <= 0:
        raise ValueError('Board packages require a positive clock and fixed iteration count')

    # Validate both images before creating or replacing any package file.
    instruction_words, instruction_data = make_dat(build / 'imem.hex', 8192, '00000013')
    data_words, data_data = make_dat(build / 'dmem.hex', 32768, '00000000')
    manifest = {
        'run_mode': mode,
        'iterations': iterations,
        'cpu_hz': ticks_hz,
        'total_data_size': 2000,
        'instruction_words': instruction_words,
        'initial_data_words': data_words,
        'official_commit': OFFICIAL_COMMIT,
        'official_source_md5_lf': source_hashes,
        'compiler_flags': flags,
        'linker_flags': info['LINKER_FLAGS_STR'],
        'libraries': info['LINK_LIBS_STR'],
        'libc': info['LIBC_NAME_STR'],
        'board_validation': 'pending; compilation is not a board run',
        'sha256': {
            'imem_coremark.dat': hashlib.sha256(instruction_data).hexdigest(),
            'dmem_coremark.dat': hashlib.sha256(data_data).hexdigest(),
            'coremark.elf': hashlib.sha256((build / 'coremark.elf').read_bytes()).hexdigest(),
        },
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / 'imem_coremark.dat').write_bytes(instruction_data)
    (output / 'dmem_coremark.dat').write_bytes(data_data)
    shutil.copyfile(build / 'coremark.elf', output / 'coremark.elf')
    shutil.copyfile(build / 'coremark_build_info.h', output / 'coremark_build_info.h')
    (output / 'build_manifest.json').write_bytes((json.dumps(manifest, indent=2) + '\n').encode('ascii'))
    print('Packaged {}: {} instruction words, {} data words; official sources unchanged'.format(
        mode, instruction_words, data_words))


if __name__ == '__main__':
    main()
