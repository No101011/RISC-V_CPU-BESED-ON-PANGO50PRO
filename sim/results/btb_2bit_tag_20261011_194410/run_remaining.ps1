$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath 'E:\FPGA\github\RISCV\RISCV_CPU_BaseOn_Pangu\sim\programs'
$env:PATH = 'D:\realsoftwares\modelsim\win64;' + $env:PATH
$env:COREMARK_PYTHON = 'C:\Users\ASUS\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$env:COREMARK_MAX_CYCLES = '20000000'
$env:COREMARK_PERF_ENABLE = '1'
Remove-Item Env:COREMARK_PERF_ELF -ErrorAction SilentlyContinue
$btbReportRoot = '../results/btb_2bit_tag_20261011_194410'
$btbRunCases = @(
    @{ Name='baseline_performance'; Mode='sim_performance'; Lib='btb_old_perf_20261011_194410'; DoFile="$btbReportRoot/baseline_coremark.do" },
    @{ Name='new_validation'; Mode='sim_validation'; Lib='btb_new_val_20261011_194410'; DoFile='coremark.do' }
)
foreach ($btbRunCase in $btbRunCases) {
    $env:COREMARK_IMEM_HEX = '../../fpga/pds/coremark_b1/' + $btbRunCase.Mode + '/imem.hex'
    $env:COREMARK_DMEM_HEX = '../../fpga/pds/coremark_b1/' + $btbRunCase.Mode + '/dmem.hex'
    $env:COREMARK_WORK_LIB = $btbRunCase.Lib
    $env:COREMARK_REPORT_CSV = $btbReportRoot + '/' + $btbRunCase.Name + '.csv'
    & 'D:\realsoftwares\modelsim\win64\vsim.exe' -c -l ($btbReportRoot + '/' + $btbRunCase.Name + '.log') -do ('do ' + $btbRunCase.DoFile)
    if ($LASTEXITCODE -ne 0) { throw ('ModelSim failed: ' + $btbRunCase.Name + ', exit=' + $LASTEXITCODE) }
}
