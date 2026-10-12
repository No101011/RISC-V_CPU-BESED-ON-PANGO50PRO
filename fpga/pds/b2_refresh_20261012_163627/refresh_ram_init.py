"""Regenerate only the RAM initialization using PDS's unmodified Tcl generator."""
import hashlib
import importlib.util
import json
import re
import shutil
import tkinter
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PDS = Path('E:/FPGA/github/ZiGuang/RISCV_BASEDON_PANGU')
VENDOR = Path('D:/realsoftwares/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_ram/ipm2l_flex_ram_eval/ipm2l_sdpram')
STAGE = HERE/'ip_stage/bram_dram'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def constants(path):
    return {(int(b,16),int(a),int(d)):int(v,16) for b,a,d,v in re.findall(
        r'localparam\s+INIT_([0-9A-F]+)_(\d+)_(\d+)\s*=\s*288\x27h([0-9a-fA-F]+)',path.read_text())}


def main():
    tree = ET.parse(STAGE/'bram_dram.idf').getroot()
    assert tree.findtext('header/family') == 'Logos2'
    params = {p.findtext('name'):{'true':'1','false':'0'}.get(p.findtext('value'),p.findtext('value'))
              for p in tree.findall('param_list/param')}
    params.setdefault('CAS_MODE_SEL',{'18K':'DRM18K','36K':'DRM36K','64K':'DRM64K'}[params['CAS_MODE']])
    assert params['WR_ADDR_WIDTH'] == params['RD_ADDR_WIDTH'] == '15'
    assert params['WR_DATA_WIDTH'] == params['RD_DATA_WIDTH'] == '32'
    t = tkinter.Tcl()
    t.eval('namespace eval ui {}')
    t.createcommand('ui::getValue',lambda option,name:params[name])
    errors = []
    t.createcommand('ui::print',lambda *args:errors.append(args))
    for filename in ['createCasParam.tcl','createInitFile.tcl']:
        t.call('source',(VENDOR/filename).as_posix())
    # Verify the adapter against the currently generated old RAM constants.
    reference = HERE/'ram_reference_check.v'
    t.call('createInitParamFile',(REPO/'fpga/pds/coremark_b4/validation/dmem_coremark.dat').as_posix(),reference.as_posix(),'HEX')
    assert not errors, errors
    old_init = STAGE/'rtl/bram_dram_init_param.v'
    assert constants(reference) == constants(old_init), 'Vendor adapter did not reproduce the existing B4 constants'
    generated = HERE/'bram_dram_init_param_b2.v'
    dat = REPO/'fpga/pds/coremark_b2/performance_long/dmem_coremark.dat'
    assert Path(params['INIT_FILE']).resolve() == dat.resolve()
    t.call('createInitParamFile',dat.as_posix(),generated.as_posix(),'HEX')
    assert not errors, errors
    spec = importlib.util.spec_from_file_location('audit',REPO/'fpga/pds/ip_init_audit_20261012/audit.py')
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    assert audit.decode(generated,16,32768) == [int(x,16) for x in dat.read_text().splitlines()]
    original_wrapper = STAGE/'bram_dram.v'
    wrapper_bytes = original_wrapper.read_bytes()
    replacement,count = re.subn(rb'(localparam INIT_FILE\s*=\s*")[^"]*(")',
        lambda m:m[1]+dat.as_posix().encode('ascii')+m[2],wrapper_bytes)
    assert count == 1
    new_wrapper = HERE/'bram_dram_b2.v'
    new_wrapper.write_bytes(replacement)
    live = PDS/'ipcore/bram_dram'
    assert sha(live/'bram_dram.v') == sha(original_wrapper), 'Live wrapper changed during regeneration'
    assert sha(live/'rtl/bram_dram_init_param.v') == sha(old_init), 'Live constants changed during regeneration'
    shutil.copyfile(generated,live/'rtl/bram_dram_init_param.v')
    shutil.copyfile(new_wrapper,live/'bram_dram.v')
    summary = dict(method='PDS original createCasParam.tcl + createInitFile.tcl called via Tcl; architecture and interfaces unchanged',
        old_B4_constants_reproduced=True,new_B2_all_32768_words_match=True,
        input_dat_sha256=sha(dat),generated_init_sha256=sha(generated),wrapper_sha256=sha(new_wrapper),
        generator_scripts={name:sha(VENDOR/name) for name in ['createCasParam.tcl','createInitFile.tcl']},
        bitstream_regenerated=False)
    (HERE/'ram_regeneration.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))


if __name__ == '__main__':
    main()
