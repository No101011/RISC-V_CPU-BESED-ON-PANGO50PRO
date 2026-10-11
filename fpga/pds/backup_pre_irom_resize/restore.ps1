# restore.ps1 —— 把 backup_pre_irom_resize 里的文件复制回工程（IROM/DARM 改动前的状态）
$bk   = $PSScriptRoot
$root = Resolve-Path (Join-Path $bk '..\..\..')
$files = @(
 'rtl\perip\perip_bridge.sv',
 'rtl\perip\dram_driver.sv',
 'rtl\perip\student_top.sv',
 'rtl\soc\myCPU.sv',
 'sim\tb\tb_student\tb_student.v',
 'sim\tb\tb_myCPU\tb_myCPU.sv',
 'tests\coremark\port\link.ld'
)
foreach ($f in $files) {
  Copy-Item (Join-Path $bk $f) (Join-Path $root $f) -Force
  Write-Host "restored: $f"
}
Write-Host "done. 记得同步回退 PDS 里的 IP 配置（bram_dram Address Width 16、irom_bram Address Width 12）。"
