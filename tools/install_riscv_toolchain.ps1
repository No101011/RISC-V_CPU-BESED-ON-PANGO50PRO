<#
  install_riscv_toolchain.ps1
  一键安装 xpack RISC-V GCC（给本仓库的 CoreMark / riscv-tests 用）

  用法（在你自己的 PowerShell 里跑；不要在受限沙箱里跑）：
      powershell -ExecutionPolicy Bypass -File tools\install_riscv_toolchain.ps1

  常用参数：
      -Dest    D:\realsoftwares       # 安装根目录（默认，约需 1.6 GB 空间）
      -Version 15.2.0-1               # xpack 版本
      -Mirror  https://ghproxy.net/   # GitHub 下载慢时加加速前缀（第三方代理，见文末说明）
      -NoSha                          # 跳过 SHA256 校验（不推荐）

  装完后 Makefile 默认的 RISCV_PREFIX=riscv-none-elf- 就能直接用：
      cd tests\coremark
      make LIBC=newlib_nano
#>
param(
    [string]$Version = '15.2.0-1',
    [string]$Dest    = 'D:\realsoftwares',
    [string]$Mirror  = '',
    [switch]$NoSha
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$asset = "xpack-riscv-none-elf-gcc-$Version-win32-x64.zip"
$url   = "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$Version/$asset"
if ($Mirror) { $url = $Mirror.TrimEnd('/') + '/' + $url }

# 该版本的官方 SHA256（来自 GitHub Release 的 .sha 附件）
$sha = '85ef714dacd273b1dadf4af4892774520ac01915bfa6da816a56e7e41591e09e'

# ---- 代理：环境变量优先，其次 IE 设置（Clash Verge 默认写的就是这两处）----
$proxyUrl = $env:HTTPS_PROXY
if (-not $proxyUrl) { $proxyUrl = $env:HTTP_PROXY }
if (-not $proxyUrl) {
    $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($ie.ProxyEnable -eq 1 -and $ie.ProxyServer) { $proxyUrl = 'http://' + $ie.ProxyServer }
}

$zip = Join-Path $env:TEMP $asset
Write-Host "[1/4] 下载 $url"
if ($proxyUrl) { Write-Host "      走代理 $proxyUrl" } else { Write-Host "      直连（没检测到代理）" }
if (Test-Path $zip) { Remove-Item $zip -Force }
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $wc = New-Object System.Net.WebClient
    if ($proxyUrl) { $wc.Proxy = New-Object System.Net.WebProxy($proxyUrl) }
    $wc.DownloadFile($url, $zip)
} catch {
    Write-Host ""
    Write-Host "下载失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  1) 国内的 GitHub 直连常常被重置，加加速前缀再试："
    Write-Host "     -Mirror https://ghproxy.net/      （第三方代理，会看到你的下载流量）"
    Write-Host "     -Mirror https://gh-proxy.com/     （同上）"
    Write-Host "  2) 或改用 MounRiver Studio 自带的工具链（国内下载快），然后："
    Write-Host "     make RISCV_PREFIX=riscv-none-embed-"
    exit 1
}
$sw.Stop()
Write-Host ("      完成：{0:N1} MB，用时 {1:N0} 秒" -f ((Get-Item $zip).Length/1MB), $sw.Elapsed.TotalSeconds)

if (-not $NoSha) {
    Write-Host "[2/4] 校验 SHA256"
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $sha.ToLower()) {
        Write-Host "      校验失败！期望 $sha" -ForegroundColor Red
        Write-Host "      实际       $actual" -ForegroundColor Red
        Write-Host "      文件可能被镜像篡改或下载不完整，已中止。" -ForegroundColor Red
        exit 1
    }
    Write-Host "      通过 ✓"
} else {
    Write-Host "[2/4] 跳过 SHA256 校验"
}

Write-Host "[3/4] 解压到 $Dest"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
& tar.exe -xf $zip -C $Dest
if ($LASTEXITCODE -ne 0) { Expand-Archive -Path $zip -DestinationPath $Dest -Force }
Remove-Item $zip -Force

$bin = Join-Path $Dest "xpack-riscv-none-elf-gcc-$Version\bin"
if (-not (Test-Path $bin)) { throw "解压后找不到 $bin，请检查 -Dest / -Version" }

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$bin*") {
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $bin), 'User')
    Write-Host "      已把 $bin 写入用户 PATH（新开的终端生效）"
} else {
    Write-Host "      $bin 已在用户 PATH 中"
}
$env:Path = $env:Path + ';' + $bin

Write-Host "[4/4] 验证"
& (Join-Path $bin 'riscv-none-elf-gcc.exe') --version | Select-Object -First 1

Write-Host ""
Write-Host "装好了。下一步（本仓库根目录）：" -ForegroundColor Green
Write-Host "  cd tests\coremark"
Write-Host "  make LIBC=newlib_nano"
Write-Host "  # 然后核对 build\imem.hex 第 1 条应该是 00100197（小立即数），不是 80101197"
Write-Host "  cd ..\..\sim\programs"
Write-Host "  vsim -c -do coremark.do"
