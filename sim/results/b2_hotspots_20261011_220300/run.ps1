$ErrorActionPreference = 'Stop'
$repository = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$env:PATH = 'D:/realsoftwares/modelsim/win64;' + $env:PATH
if (-not $env:LM_LICENSE_FILE) { $env:LM_LICENSE_FILE = 'D:/realsoftwares/modelsim/LICENSE.TXT' }
$env:COREMARK_PYTHON = 'C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$env:COREMARK_MAX_CYCLES = '20000000'
$env:COREMARK_PERF_ENABLE = '1'
$env:COREMARK_IMEM_HEX = '../../fpga/pds/coremark_b2/sim_performance/imem.hex'
$env:COREMARK_DMEM_HEX = '../../fpga/pds/coremark_b2/sim_performance/dmem.hex'
$env:COREMARK_WORK_LIB = 'b2_hotspots_20261011_220300'
$env:COREMARK_REPORT_CSV = '../results/b2_hotspots_20261011_220300/performance.csv'
$env:COREMARK_HOTSPOT_CSV = '../results/b2_hotspots_20261011_220300/hotspots.csv'
Remove-Item Env:COREMARK_PERF_ELF -ErrorAction SilentlyContinue
$previous = Get-Location
try {
    Set-Location -LiteralPath (Join-Path $repository 'sim/programs')
    & 'D:/realsoftwares/modelsim/win64/vsim.exe' -c -l ('../results/b2_hotspots_20261011_220300/performance.log') -do 'onerror {quit -code 1}; do coremark.do'
    if ($LASTEXITCODE -ne 0) { throw "ModelSim failed: exit=$LASTEXITCODE" }
} finally {
    Set-Location -LiteralPath $previous
}
