"""Read-only decoding of the currently generated Logos2 DRM initialization."""
import hashlib
import json
import re
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PDS = Path('E:/FPGA/github/ZiGuang/RISCV_BASEDON_PANGU')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode(path, width, depth):
    text = path.read_text(encoding='utf-8-sig')
    values = {(int(block,16),int(a),int(d)):int(value,16)
              for block,a,d,value in re.findall(
                  r'localparam\s+INIT_([0-9A-Fa-f]+)_(\d+)_(\d+)\s*=\s*288\s*\x27h([0-9A-Fa-f]+)',text)}
    data = []
    per_block = 64 if width == 4 else 16
    per_bank = per_block*128
    for address in range(depth):
        addr_bank, local = divmod(address,per_bank)
        block, word = divmod(local,per_block)
        value = 0
        for d in range(32//width):
            packed = values[block,addr_bank,d]
            if width == 4:
                shift = (word//2)*9+(word%2)*4
                part = (packed>>shift)&15
            else:
                shift = word*18
                part = ((packed>>shift)&255) | (((packed>>(shift+9))&255)<<8)
            value |= part<<(d*width)
        data.append(value)
    return data


def main():
    result = dict(evidence='Current on-disk generated IP; no bitstream/device readback', ip={}, candidates={})
    decoded = {}
    for ip,kind,width,depth in [('irom_bram','imem',4,8192),('bram_dram','dmem',16,32768)]:
        ipdir = PDS/'ipcore'/ip
        init = ipdir/'rtl'/f'{ip}_init_param.v'
        decoded[kind] = decode(init,width,depth)
        metadata = {}
        for path in [ipdir/f'{ip}.idf',ipdir/f'{ip}.v',init]:
            snapshot = HERE/path.name
            snapshot.write_bytes(path.read_bytes())
            metadata[path.name] = dict(path=str(path),sha256=sha(path),mtime=path.stat().st_mtime)
        idf = (ipdir/f'{ip}.idf').read_text()
        wrapper = (ipdir/f'{ip}.v').read_text()
        metadata['idf_init_file'] = re.search(r'<name>INIT_FILE</name>\s*<value>(.*?)</value>',idf,re.S)[1]
        metadata['wrapper_init_file'] = re.search(r'localparam INIT_FILE\s*=\s*"(.*?)"',wrapper)[1]
        result['ip'][ip] = metadata
        (HERE/f'{kind}_decoded.dat').write_text(''.join(f'{word:08x}\n' for word in decoded[kind]))
    for package in ['coremark_b2/performance_long','coremark_b2/validation','coremark_b4/validation']:
        directory = REPO/'fpga/pds'/package
        manifest = json.loads((directory/'build_manifest.json').read_text())
        info = {}
        for kind in ['imem','dmem']:
            path = directory/f'{kind}_coremark.dat'
            words = [int(line,16) for line in path.read_text().splitlines() if line.strip()]
            differences = [i for i,(a,b) in enumerate(zip(words,decoded[kind])) if a!=b]
            assert len(words) == len(decoded[kind])
            info[kind] = dict(sha256=sha(path),manifest_hash_matches=sha(path)==manifest['sha256'][path.name],
                              generated_ip_words_match=not differences,different_words=len(differences),
                              first_difference=differences[0] if differences else None)
        result['candidates'][package] = info
    result['generated_ip_matches'] = [name for name,info in result['candidates'].items()
                                      if all(v['generated_ip_words_match'] for v in info.values())]
    assert len(result['generated_ip_matches']) == 1
    raw = b''.join(struct.pack('<I',word) for word in decoded['dmem'])
    flags = re.findall(rb'-march=[^\x00]+',raw)
    result['embedded_flags'] = [value.decode('ascii') for value in flags]
    (HERE/'audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
