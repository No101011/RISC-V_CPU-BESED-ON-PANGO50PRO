<# Build B3 (O2 + LTO) and B4 (O3 + LTO) as independent PDS packages. #>
param(
    [string]$Toolchain = 'D:/realsoftwares/xpack-riscv-none-elf-gcc-15.2.0-1/bin',
    [string]$Python = 'python',
    [ValidateSet('Both','B3','B4')][string]$Variant = 'Both'
)
$ErrorActionPreference = 'Stop'
$repositoryPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$previousLocation = Get-Location
$variants = @(
    @{ Name='b3'; Optimization='O2' },
    @{ Name='b4'; Optimization='O3' }
)
$jobs = @(
    @{ Name='performance_long'; Mode='Performance'; Iters=4000; Hz=83333333 },
    @{ Name='validation';       Mode='Validation';  Iters=4000; Hz=83333333 },
    @{ Name='sim_performance';  Mode='Performance'; Iters=10;   Hz=100000000 },
    @{ Name='sim_validation';   Mode='Validation';  Iters=10;   Hz=100000000 }
)
try {
    Set-Location -LiteralPath $repositoryPath
    foreach ($candidate in $variants) {
        if ($Variant -ne 'Both' -and $candidate.Name -ne $Variant.ToLowerInvariant()) { continue }
        $packageRoot = Join-Path $PSScriptRoot ('coremark_' + $candidate.Name)
        $summaries = @()
        foreach ($job in $jobs) {
            $buildDirectory = 'build/' + $candidate.Name + '/' + $job.Name
            $packageDirectory = Join-Path $packageRoot $job.Name
            $buildAbsolute = Join-Path $repositoryPath ('tests/coremark/' + $buildDirectory)
            New-Item -ItemType Directory -Force -Path $packageDirectory | Out-Null
            $buildArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',
                (Join-Path $repositoryPath 'tests/coremark/build.ps1'),
                '-Toolchain',$Toolchain,'-Isa','rv32im_zba_zicsr',
                '-Optimization',$candidate.Optimization,'-Lto','-Python',$Python,
                '-RunMode',$job.Mode,'-Iters',$job.Iters,'-CpuHz',$job.Hz,'-BuildDir',$buildDirectory)
            $ErrorActionPreference = 'Continue'
            & powershell @buildArguments 2>&1 | Tee-Object -FilePath (Join-Path $packageDirectory 'build_log.txt')
            $buildExitCode = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($buildExitCode -ne 0) { throw "Build failed: $($candidate.Name)/$($job.Name)" }
            & (Join-Path $Toolchain 'riscv-none-elf-objdump.exe') -d (Join-Path $buildAbsolute 'coremark.elf') |
                Out-File -LiteralPath (Join-Path $buildAbsolute 'coremark.dis') -Encoding ascii
            if ($LASTEXITCODE -ne 0) { throw "Disassembly failed: $($job.Name)" }
            & $Python (Join-Path $repositoryPath 'tests/coremark/scripts/export_pds_image.py') `
                --build-dir $buildAbsolute --output-dir $packageDirectory
            if ($LASTEXITCODE -ne 0) { throw "Packaging failed: $($job.Name)" }
            foreach ($name in @('imem.hex','dmem.hex','coremark.map','coremark.dis',
                                'coremark.text.bin','coremark.data.bin')) {
                Copy-Item -LiteralPath (Join-Path $buildAbsolute $name) -Destination (Join-Path $packageDirectory $name)
            }
            $zbaLines = @(Select-String -LiteralPath (Join-Path $packageDirectory 'coremark.dis') -Pattern '\bsh[123]add\b')
            $zbaLines | ForEach-Object { $_.Line } |
                Out-File -LiteralPath (Join-Path $packageDirectory 'zba_instructions.txt') -Encoding ascii
            & $Python (Join-Path $repositoryPath 'sim/programs/coremark_perf_metadata.py') `
                --imem (Join-Path $packageDirectory 'imem.hex') --dmem (Join-Path $packageDirectory 'dmem.hex')
            if ($LASTEXITCODE -ne 0) { throw "ELF/HEX or timer metadata mismatch: $($job.Name)" }
            $manifestPath = Join-Path $packageDirectory 'build_manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $textBytes = (Get-Item -LiteralPath (Join-Path $packageDirectory 'coremark.text.bin')).Length
            $dataBytes = (Get-Item -LiteralPath (Join-Path $packageDirectory 'coremark.data.bin')).Length
            $additional = [ordered]@{
                variant=$candidate.Name.ToUpperInvariant(); optimization=$candidate.Optimization; lto=$true
                text_bytes=$textBytes; initial_data_bytes=$dataBytes; static_zba_sites=$zbaLines.Count
                timer_policy='start_time/stop_time: noipa; mcycle asm: volatile + memory clobber'
                build_exit_code=$buildExitCode
                rtl_mycpu_sha256=(Get-FileHash -LiteralPath (Join-Path $repositoryPath 'rtl/soc/myCPU.sv') -Algorithm SHA256).Hash.ToLowerInvariant()
                port_core_portme_sha256=(Get-FileHash -LiteralPath (Join-Path $repositoryPath 'tests/coremark/port/core_portme.c') -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            foreach ($key in $additional.Keys) {
                $manifest | Add-Member -NotePropertyName $key -NotePropertyValue $additional[$key] -Force
            }
            foreach ($name in @('imem.hex','dmem.hex','coremark.map','coremark.dis',
                                'coremark.text.bin','coremark.data.bin','coremark_build_info.h','build_log.txt')) {
                $manifest.sha256 | Add-Member -NotePropertyName $name -NotePropertyValue `
                    (Get-FileHash -LiteralPath (Join-Path $packageDirectory $name) -Algorithm SHA256).Hash.ToLowerInvariant() -Force
            }
            $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding ascii
            $summaries += [ordered]@{
                package=$job.Name; mode=$manifest.run_mode; iterations=$job.Iters; cpu_hz=$job.Hz
                text_bytes=$textBytes; initial_data_bytes=$dataBytes; static_zba_sites=$zbaLines.Count
                build_exit_code=$buildExitCode; sha256=$manifest.sha256
            }
            Write-Host "Ready: $($candidate.Name)/$($job.Name), .text=$textBytes bytes"
        }
        [ordered]@{
            variant=$candidate.Name.ToUpperInvariant(); optimization=$candidate.Optimization; lto=$true
            generated_at=(Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'); packages=$summaries
            execution_status='compiled and packaged; RTL simulation, PDS and board runs pending'
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $packageRoot 'build_summary.json') -Encoding ascii
    }
} finally {
    Set-Location -LiteralPath $previousLocation
}
