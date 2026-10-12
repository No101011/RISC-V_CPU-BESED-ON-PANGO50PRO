<#
  build.ps1 —— CoreMark 构建（Windows / PowerShell 版，功能等同 Makefile）
  为什么需要它：GNU make 在 Windows 上要用 sh.exe 跑 recipe（mkdir -p / rm -rf / test），
  没装 MSYS/Git-Bash 的 usr\bin 时会直接失败。这个脚本把同样的步骤用 PowerShell 走一遍。

  用法（仓库根目录或本目录均可）：
      powershell -ExecutionPolicy Bypass -File tests\coremark\build.ps1
  可选参数：
      -Toolchain D:\realsoftwares\xpack-riscv-none-elf-gcc-15.2.0-1\bin   # 不填则从 PATH 找
      -Iters 10        # -DITERATIONS
      -CpuHz 100000000 # -DCPU_HZ：仿真台 100 MHz；50Pro 上板 83333333
      -Libc newlib_nano | picolibc | newlib
      -Isa rv32im_zicsr | rv32im_zba_zicsr
      -Optimization O2 | O3  # B1=Zba+O2, B2=Zba+O3
      -Lto                   # B3=Zba+O2+LTO, B4=Zba+O3+LTO

  RunMode=Performance / Validation 使用官方两组种子；BuildDir 可分开保存产物。
  两种常用组合（默认产物落在 build\，会互相覆盖，跑完请对号入座）：
    ① 仿真（配合 sim\programs\coremark.do）：
         powershell -File tests\coremark\build.ps1 -Toolchain <bin>
       ITERS=10 @100MHz 约 400 万周期跑完，能验 CRC；但按 CoreMark 规则跑不满
       10 秒，报表会写 "ERROR! Must execute for at least 10 secs"（这是规则要求，
       不是算错）。三个 CRC 应命中 performance run 的官方值
       0xe714 / 0x1fd7 / 0x8e3a（seedcrc 0xe9f5）。
    ② 上板（PDS ROM 镜像）：
         powershell -File tests\coremark\build.ps1 -Toolchain <bin> -Iters 2200 -CpuHz 83333333
         powershell -File fpga\pds\mk_imem_dat.ps1
       ITERS=2200 @83.333MHz 约 10.49 秒，才会打印 "Correct operation validated"
       和 "CoreMark 1.0 : ... / ... / STATIC" 成绩行；之后必须在 PDS 里重新
       生成 irom_bram 这个 IP，ROM 才会换上新的内容。
#>
param(
    [string]$Toolchain = '',
    [int]$Iters   = 10,
    [string]$CpuHz = '100000000',
    [ValidateSet('newlib_nano','picolibc','newlib')][string]$Libc = 'newlib_nano',
    [ValidateSet('Performance','Validation')][string]$RunMode = 'Performance',
    [string]$BuildDir = 'build/b2/sim_performance',
    [ValidateSet('rv32im_zicsr','rv32im_zba_zicsr')][string]$Isa = 'rv32im_zba_zicsr',
    [string]$Python = 'python',
    [ValidateSet('O2','O3')][string]$Optimization = 'O3',
    [switch]$Lto
)
# 故意用 Continue：gcc 会把 warning 写到 stderr，PowerShell 5.1 会把它当成“错误记录”，
# 若设成 Stop 就会在第一条 warning 处中断构建。这里改成靠 $LASTEXITCODE 判断成败。
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent | Split-Path -Parent      # tests/coremark -> 仓库根
Set-Location (Join-Path $root 'tests\coremark')

if ($Toolchain) { $env:Path = $Toolchain + ';' + $env:Path }
$CC   = 'riscv-none-elf-gcc'
$OC   = 'riscv-none-elf-objcopy'
$GCCV = & $CC --version 2>&1 | Select-Object -First 1
if (-not $GCCV) { throw "找不到 $CC，请用 -Toolchain 指定 bin 目录" }
Write-Host "toolchain : $GCCV"

$ARCH = @(('-march=' + $Isa),'-mabi=ilp32','-mcmodel=medlow')
$OPT  = @(('-' + $Optimization))
$LINKOPT = @()
if ($Lto) {
    $OPT += '-flto'
    # Match the compile optimization level when GCC executes LTO at link time.
    $LINKOPT = @(('-' + $Optimization), '-flto')
}
$WARN = @('-Wall','-Wno-unused-variable','-Wno-unused-but-set-variable','-Wno-implicit-function-declaration','-Wno-unused-function')
$buildPath = $BuildDir.Replace('\', '/').TrimEnd('/')
if (-not $buildPath) { throw 'BuildDir 不能为空' }
$INC  = @('-Isrc','-Iport',('-I' + $buildPath))
# 从实际参数生成 C 字符串头文件，避免 PowerShell 5.1 的 -D 字符串引号转义。
$modeDefine = if ($RunMode -eq 'Validation') { '-DVALIDATION_RUN=1' } else { '-DPERFORMANCE_RUN=1' }
$DEFS = @("-DITERATIONS=$Iters","-DCPU_HZ=$CpuHz",'-DTOTAL_DATA_SIZE=2000',$modeDefine)
if ($Lto) { $DEFS += '-DCOREMARK_LTO=1' }
# 也不用 -u _printf_float：端口自带 port\ee_printf.c（core_portme.h 里 HAS_PRINTF=0），
# 几百字节就支持 %f。newlib-nano 的浮点 printf 会把 .text 撑到 40680 字节，
# 超出 32KB IROM，链接必然失败。
switch ($Libc) {
    'picolibc'    { $SPEC = @('--specs=picolibc.specs'); $LIBS = @('-lc'); $FLOAT = @() }
    'newlib_nano' { $SPEC = @('--specs=nano.specs');      $LIBS = @('-lc','-lgcc','-lnosys'); $FLOAT = @() }
    default       { $SPEC = @();                          $LIBS = @('-lc','-lgcc','-lnosys'); $FLOAT = @() }
}
$CFLAGS = $ARCH + $OPT + $WARN + $INC + $DEFS + @('-ffunction-sections','-fdata-sections','-fno-builtin-printf') + $SPEC
$LDFLAGS = $ARCH + $LINKOPT + @('-nostartfiles','-T','port/link.ld','-Wl,--gc-sections',("-Wl,-Map=$buildPath/coremark.map")) + $FLOAT + $SPEC

New-Item -ItemType Directory -Force -Path "$buildPath/src", "$buildPath/port" | Out-Null
$buildInfoArgs = @('--output', "$buildPath/coremark_build_info.h",
                   ('--cflags=' + ($CFLAGS -join ' ')),
                   ('--ldflags=' + ($LDFLAGS -join ' ')),
                   ('--libs=' + ($LIBS -join ' ')), ('--libc=' + $Libc))
& $Python scripts\gen_build_info.py @buildInfoArgs
if ($LASTEXITCODE -ne 0) { throw '生成 CoreMark 报表参数失败' }

$objs = @()
foreach ($c in @('src\core_main.c','src\core_list_join.c','src\core_matrix.c','src\core_state.c','src\core_util.c',
                 'port\core_portme.c','port\syscalls.c','port\ee_printf.c')) {
    $o = "$buildPath/$([IO.Path]::ChangeExtension($c,'o'))"
    Write-Host "  CC   $c"
    & $CC @CFLAGS -c $c -o $o
    if ($LASTEXITCODE -ne 0) { throw "编译失败: $c" }
    $objs += $o
}
Write-Host "  AS   port\crt0.S"
& $CC @CFLAGS -c port\crt0.S -o "$buildPath/port/crt0.o"
if ($LASTEXITCODE -ne 0) { throw "编译失败: port\crt0.S" }
$objs = @("$buildPath/port/crt0.o") + $objs

Write-Host "  LINK $buildPath/coremark.elf ($RunMode)"
# 链接：不再需要 -u _printf_float（%f 由 port\ee_printf.c 提供）
& $CC @LDFLAGS @objs @LIBS -o "$buildPath/coremark.elf"
if ($LASTEXITCODE -ne 0) { throw "链接失败（若报 region overflow，说明程序超过 32KB IROM）" }

& $OC -O binary --only-section=.text "$buildPath/coremark.elf" "$buildPath/coremark.text.bin"
if ($LASTEXITCODE -ne 0) { throw '提取指令镜像失败' }
& $OC -O binary --only-section=.rodata --only-section=.data "$buildPath/coremark.elf" "$buildPath/coremark.data.bin"
if ($LASTEXITCODE -ne 0) { throw '提取数据镜像失败' }
& $Python scripts\bin2hex.py "$buildPath/coremark.text.bin" "$buildPath/imem.hex"
if ($LASTEXITCODE -ne 0) { throw '转换指令镜像失败' }
& $Python scripts\bin2hex.py "$buildPath/coremark.data.bin" "$buildPath/dmem.hex"
if ($LASTEXITCODE -ne 0) { throw '转换数据镜像失败' }

& riscv-none-elf-size "$buildPath/coremark.elf"
$words = (Get-Content "$buildPath/imem.hex" | Measure-Object -Line).Lines
Write-Host ""
Write-Host ("imem.hex : {0} 字 = {1:N1} KB (IROM 上限 8192 字=32KB)" -f $words, ($words*4/1KB))
Write-Host ("第 1 条指令 : " + (Get-Content "$buildPath/imem.hex" -TotalCount 1))
Write-Host  "             期望 00100197 左右（auipc gp 的小立即数）；若是 80101197 说明 .text 还链在 0"
Write-Host ("dmem.hex : {0} 字" -f (Get-Content "$buildPath/dmem.hex" | Measure-Object -Line).Lines)
