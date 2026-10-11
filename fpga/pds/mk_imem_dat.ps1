<#
  mk_imem_dat.ps1 —— 把 CoreMark 的 imem.hex 转成 PDS ROM IP 能吃的 .dat

  背景：
    PDS 的 "DRM Based ROM" IP 的 INIT_FILE 要的是「一行一个 32 位十六进制字、
    行数 == ROM 深度」的 .dat。CoreMark 构建出来的 build/imem.hex 只有实际用到的
    行数（约 5000 行），直接喂给 ROM IP 会短；而 ROM 深度是 8192（ADDR_WIDTH=13）。

    这个脚本把 imem.hex 原样搬过来，后面补 NOP 到 8192 行。

  为什么要单独跑：
    imem.hex 每次重编都会变（修了链接脚本、改了程序……），
    但 PDS 工程里那份 imem_coremark.dat 不会自动跟着变 ——
    2026-09-29 那次就是漏了这一步，工程里一直是链接脚本修好之前的旧镜像
    （首字 80101197，正确的是 00101197）。

  用法：
      powershell -ExecutionPolicy Bypass -File fpga\pds\mk_imem_dat.ps1
      powershell -ExecutionPolicy Bypass -File fpga\pds\mk_imem_dat.ps1 -Src <hex> -Dst <dat> -Depth 8192

  跑完还要在 PDS 里做一步：双击 irom_bram 这个 IP -> 重新生成（Regenerate），
  这样 rtl/irom_bram_init_param.v 才会换上新的 ROM 内容。
#>
param(
    [string]$Src   = '',
    [string]$Dst   = '',
    [int]   $Depth = 8192
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot                                   # fpga/pds
$root = Split-Path (Split-Path $here -Parent) -Parent    # 仓库根
if (-not $Src) { $Src = Join-Path $root 'tests\coremark\build\imem.hex' }
if (-not $Dst) { $Dst = Join-Path $here 'imem_coremark.dat' }

if (-not (Test-Path $Src)) { throw ("找不到 {0}（先构建 CoreMark：tests\coremark\build.ps1）" -f $Src) }

# 只取形如 8 位十六进制的行，去掉空行/注释
$words = @(Get-Content $Src |
           ForEach-Object { $_.Trim() } |
           Where-Object { $_ -match '^[0-9a-fA-F]{1,8}$' } |
           ForEach-Object { $_.PadLeft(8, '0') })

if ($words.Count -eq 0) { throw ("{0} 里没解析出任何指令字" -f $Src) }
if ($words.Count -gt $Depth) {
    throw ("程序 {0} 字 > ROM 深度 {1} 字 —— 装不下，先精简程序或加大 ROM" -f $words.Count, $Depth)
}

# 补齐到 ROM 深度，填空 NOP（00000013）：万一 PC 跑飞进未初始化区，
# 执行的是 NOP 而不是全 0 的非法指令，便于定位。
$pad  = $Depth - $words.Count
$tail = New-Object string[] $pad
for ($i = 0; $i -lt $pad; $i++) { $tail[$i] = '00000013' }
$all  = $words + $tail

# 必须是「无 BOM + 纯 LF」！PDS 的 ROM IP 解析器遇到 BOM 会直接报
#   E: IPCompiler 0055: DRM Based ROM (1.6): Failed to load the initial
#      memory data from file <xxx>.dat
# （2026-09-30 踩过：带 BOM 的 .dat 是 81923 字节，加载失败；
#   能用的那份正好 8192 x 9 = 73728 字节 = 每行 8 个 hex + 一个 LF。）
$enc = New-Object System.Text.UTF8Encoding($false)   # $false = 不写 BOM
[System.IO.File]::WriteAllText($Dst, (($all -join "`n") + "`n"), $enc)

Write-Host ("源      : {0}" -f $Src)
Write-Host ("目标    : {0}" -f $Dst)
Write-Host ("指令数  : {0} 字 ({1:N1} KB)" -f $words.Count, ($words.Count * 4 / 1KB))
Write-Host ("补齐到  : {0} 字（末尾 {1} 行 NOP 00000013）" -f $Depth, $pad)
Write-Host ("首 4 字 : {0}" -f (($words | Select-Object -First 4) -join ' '))
Write-Host  "          期望首字 00101197（auipc gp,0x101）；若是 80101197 说明链接脚本还链在 0"
Write-Host ""
Write-Host "下一步：PDS 里重新生成 irom_bram 这个 IP，让 ROM 换上这份内容。"
