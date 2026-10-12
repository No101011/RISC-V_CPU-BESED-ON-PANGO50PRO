<# Select both PDS memory images from a checked official-run package. #>
param(
    [ValidateSet('Performance','Validation')][string]$RunMode = 'Performance',
    [string]$PackageDir = ''
)
$ErrorActionPreference = 'Stop'
$modeName = $RunMode.ToLowerInvariant()
$defaultPackageName = if ($RunMode -eq 'Performance') { 'performance_long' } else { 'validation' }
$package = Join-Path $PSScriptRoot "coremark_b2\$defaultPackageName"
if ($PackageDir) { $package = (Resolve-Path -LiteralPath $PackageDir).Path }
$manifestPath = Join-Path $package 'build_manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.run_mode -ne $modeName) { throw 'Package run mode mismatch' }
$files = @('imem_coremark.dat','dmem_coremark.dat')
# Check both files before updating either active image.
foreach ($name in $files) {
    $source = Join-Path $package $name
    $actual = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $manifest.sha256.$name) { throw "Package hash mismatch: $name" }
}
$backup = Join-Path $PSScriptRoot ('_backup_coremark_selection_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $backup | Out-Null
foreach ($name in $files) {
    $active = Join-Path $PSScriptRoot $name
    if (Test-Path -LiteralPath $active) {
        Copy-Item -LiteralPath $active -Destination (Join-Path $backup $name)
    }
}
foreach ($name in $files) {
    Copy-Item -LiteralPath (Join-Path $package $name) -Destination (Join-Path $PSScriptRoot $name)
}
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $PSScriptRoot 'selected_coremark_image.json')
Write-Host "Selected: $modeName; iterations=$($manifest.iterations); CPU_HZ=$($manifest.cpu_hz)"
Write-Host "Previous active images: $backup"
Write-Host 'Next: regenerate BOTH irom_bram and bram_dram, rebuild PDS, then download the bitstream.'
Write-Host 'A successful build does not replace the required board validation run.'
