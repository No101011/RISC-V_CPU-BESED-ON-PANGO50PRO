"""Build the official DIVU fixture; --install backs up and replaces local files.

Compiles and checks machine-code constants; does not run RTL simulation.
"""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess

base = Path(__file__).resolve().parent
repository = base.parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--toolchain', default='D:/realsoftwares/xpack-riscv-none-elf-gcc-15.2.0-1/bin')
parser.add_argument('--install', action='store_true')
args = parser.parse_args()
build = base / 'build'
build.mkdir(exist_ok=True)
log_lines = []


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(argv):
    log_lines.append('ARGV: ' + json.dumps([str(a) for a in argv]))
    result = subprocess.run([str(a) for a in argv], cwd=base, capture_output=True, text=True)
    log_lines.append(result.stdout)
    log_lines.append(result.stderr)
    (build / 'build.log').write_text('\n'.join(log_lines), encoding='utf-8')
    if result.returncode:
        raise RuntimeError('Command failed with exit code ' + str(result.returncode))
    return result.stdout


provenance = json.loads((base / 'upstream_provenance.json').read_text())
for name, expected in provenance['files_sha256'].items():
    if sha(base / 'upstream' / name) != expected:
        raise RuntimeError('Upstream file changed: ' + name)
toolchain = Path(args.toolchain)
prefix = toolchain / 'riscv-none-elf-'
gcc = Path(str(prefix) + 'gcc.exe')
objcopy = Path(str(prefix) + 'objcopy.exe')
objdump = Path(str(prefix) + 'objdump.exe')
version = run([gcc, '--version']).splitlines()[0]
elf = build / 'rv32um-p-divu.elf'
binary = build / 'rv32um-p-divu.bin'
flags = ['-march=rv32im', '-mabi=ilp32', '-nostdlib', '-nostartfiles', '-static',
         '-Wl,--build-id=none', '-Wl,--no-relax', '-T', 'env/link.ld',
         '-Ienv', '-Iupstream/isa/macros/scalar']
source = 'upstream/isa/rv32um/divu.S'
run([gcc, *flags, source, '-o', elf])
preprocessed = run([gcc, '-march=rv32im', '-mabi=ilp32', '-Ienv',
                    '-Iupstream/isa/macros/scalar', '-E', '-P', source])
(build / 'divu_preprocessed.S').write_text(preprocessed, encoding='utf-8')
dump = run([objdump, '-d', '-M', 'numeric,no-aliases', elf])
(build / 'rv32um-p-divu.dump').write_text(dump, encoding='utf-8')
run([objcopy, '-O', 'binary', '--only-section=.text', elf, binary])
code = binary.read_bytes()
if not code or len(code) % 4 or len(code) > 32768:
    raise RuntimeError('Invalid instruction image size')

# Decode only constant-loading instructions to check the official test inputs
# and expected values in every compiled test block, without executing DIVU.
expected_cases = {
    2: (20, 6, 3), 3: (0xffffffec, 6, 715827879),
    4: (20, 0xfffffffa, 0), 5: (0xffffffec, 0xfffffffa, 0),
    6: (0x80000000, 1, 0x80000000), 7: (0x80000000, 0xffffffff, 0),
    8: (0x80000000, 0, 0xffffffff), 9: (1, 0, 0xffffffff),
    10: (0, 0, 0xffffffff),
}
labels = {int(n): int(address, 16) for address, n in
          re.findall(r'^([0-9a-f]+) <test_(\d+)>:', dump, re.M)}
if set(labels) != set(expected_cases):
    raise RuntimeError('Missing or unexpected official test labels')
checked_cases = {}
for number, values in expected_cases.items():
    offset = labels[number] - 0x80000000
    registers = {0: 0}
    saw_divu = False
    checked = False
    while offset < len(code):
        word = struct.unpack_from('<I', code, offset)[0]
        opcode, rd, rs1 = word & 127, (word >> 7) & 31, (word >> 15) & 31
        if opcode == 0x37:
            registers[rd] = word & 0xfffff000
        elif opcode == 0x13 and ((word >> 12) & 7) == 0:
            imm = word >> 20
            if imm & 0x800:
                imm -= 4096
            registers[rd] = (registers[rs1] + imm) & 0xffffffff
        elif opcode == 0x33:
            if ((word >> 25), (word >> 12) & 7, rd, rs1, (word >> 20) & 31) != (1, 5, 14, 11, 12):
                raise RuntimeError('Unexpected arithmetic instruction')
            if (registers[11], registers[12]) != values[:2]:
                raise RuntimeError('Wrong compiled input for test ' + str(number))
            saw_divu = True
        elif opcode == 0x63:
            if not saw_divu or registers.get(3) != number or registers.get(7) != values[2]:
                raise RuntimeError('Wrong compiled expected constant for test ' + str(number))
            if ((word >> 12) & 7, rs1, (word >> 20) & 31) != (1, 14, 7):
                raise RuntimeError('Unexpected result comparison')
            checked = True
            break
        else:
            raise RuntimeError('Unexpected instruction in constant inspection')
        offset += 4
    if not checked:
        raise RuntimeError('Result comparison missing')
    checked_cases[str(number)] = {'dividend': hex(values[0]), 'divisor': hex(values[1]),
                                  'expected': hex(values[2]), 'constant_check': 'passed'}

destination = repository / 'tests/unofficial_test_data'
old_dat = destination / 'rv32um-p-divu.dat'
depth = max(len(old_dat.read_text().splitlines()), len(code) // 4)
words = [f'{w[0]:08x}' for w in struct.iter_unpack('<I', code)]
image = ('\n'.join(words + ['00000000'] * (depth - len(words))) + '\n').encode('ascii')
for suffix in ['dat', 'txt']:
    (build / ('rv32um-p-divu.' + suffix)).write_bytes(image)
manifest = {'upstream_commit': provenance['commit'], 'compiler': version,
            'compiler_flags': flags, 'official_source_modified': False,
            'official_macros_modified': False, 'environment': 'project x26/x27/x3 testbench adapter',
            'instruction_bytes': len(code), 'image_words': depth,
            'compiled_cases': checked_cases, 'rtl_simulation_run': False,
            'sha256': {p.name: sha(p) for p in build.glob('rv32um-p-divu.*')}}

if args.install:
    backup = destination / ('_backup_pre_official_divu_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    backup.mkdir()
    replacements = {('rv32um-p-divu.' + s): build / ('rv32um-p-divu.' + s)
                    for s in ['dat', 'txt', 'dump']}
    replacements['rv32um-p-divu.S'] = base / 'upstream/isa/rv32um/divu.S'
    old_hashes = {}
    for name in replacements:
        target = destination / name
        if target.exists():
            shutil.copy2(target, backup / name)
            old_hashes[name] = sha(target)
            if sha(backup / name) != old_hashes[name]:
                raise RuntimeError('Backup hash mismatch')
    (backup / 'backup_manifest.json').write_text(json.dumps(old_hashes, indent=2) + '\n', encoding='utf-8')
    for name, replacement in replacements.items():
        shutil.copyfile(replacement, destination / name)
        if sha(destination / name) != sha(replacement):
            raise RuntimeError('Installed hash mismatch')
    manifest['installed'] = True
    manifest['backup_directory'] = str(backup)
    manifest['installed_sha256'] = {name: sha(destination / name) for name in replacements}
else:
    manifest['installed'] = False
(base / 'build_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(json.dumps(manifest, indent=2))
