<# Build independent B1 (Zba + O2, no LTO) packages; active DATs are not selected. #>
param(
    [string]$Toolchain = 'D:/realsoftwares/xpack-riscv-none-elf-gcc-15.2.0-1/bin',
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$repositoryPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$previousLocation = Get-Location
$jobs = @(
    @{ Name='performance';      Mode='Performance'; Iters=2200; Hz=83333333 },
    @{ Name='performance_long'; Mode='Performance'; Iters=4000; Hz=83333333 },
    @{ Name='validation';       Mode='Validation';  Iters=4000; Hz=83333333 },
    @{ Name='sim_performance';  Mode='Performance'; Iters=10;   Hz=100000000 },
    @{ Name='sim_validation';   Mode='Validation';  Iters=10;   Hz=100000000 }
)
try {
    Set-Location -LiteralPath $repositoryPath
    foreach ($job in $jobs) {
        $buildDirectory = 'build/b1/' + $job.Name
        $packageDirectory = Join-Path $PSScriptRoot ('coremark_b1/' + $job.Name)
        $buildAbsolute = Join-Path $repositoryPath ('tests/coremark/' + $buildDirectory)
        New-Item -ItemType Directory -Force -Path $packageDirectory | Out-Null
        $buildArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',
            (Join-Path $repositoryPath 'tests/coremark/build.ps1'),
            '-Toolchain',$Toolchain,'-Isa','rv32im_zba_zicsr','-Python',$Python,
            '-RunMode',$job.Mode,'-Iters',$job.Iters,'-CpuHz',$job.Hz,'-BuildDir',$buildDirectory)
        # Windows PowerShell turns native compiler warnings into error records.
        # Keep them in the log and decide success using the child exit code.
        $ErrorActionPreference = 'Continue'
        & powershell @buildArguments 2>&1 | Tee-Object -FilePath (Join-Path $packageDirectory 'build_log.txt')
        $buildExitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($buildExitCode -ne 0) { throw "B1 build failed: $($job.Name)" }
        & (Join-Path $Toolchain 'riscv-none-elf-objdump.exe') -d (Join-Path $buildAbsolute 'coremark.elf') |
            Out-File -LiteralPath (Join-Path $buildAbsolute 'coremark.dis') -Encoding ascii
        if ($LASTEXITCODE -ne 0) { throw "Disassembly failed: $($job.Name)" }
        $exportArguments = @((Join-Path $repositoryPath 'tests/coremark/scripts/export_pds_image.py'),
            '--build-dir',$buildAbsolute,'--output-dir',$packageDirectory)
        & $Python @exportArguments
        if ($LASTEXITCODE -ne 0) { throw "B1 packaging failed: $($job.Name)" }
        foreach ($name in @('imem.hex','dmem.hex','coremark.map','coremark.dis')) {
            Copy-Item -LiteralPath (Join-Path $buildAbsolute $name) -Destination (Join-Path $packageDirectory $name)
        }
        $zbaLines = @(Select-String -LiteralPath (Join-Path $packageDirectory 'coremark.dis') -Pattern '\bsh[123]add\b')
        $zbaLines | ForEach-Object { $_.Line } |
            Out-File -LiteralPath (Join-Path $packageDirectory 'zba_instructions.txt') -Encoding ascii
        if ($zbaLines.Count -eq 0) { throw "No native Zba instructions found: $($job.Name)" }
        $metadataArguments = @((Join-Path $repositoryPath 'sim/programs/coremark_perf_metadata.py'),
            '--imem',(Join-Path $packageDirectory 'imem.hex'),
            '--dmem',(Join-Path $packageDirectory 'dmem.hex'))
        & $Python @metadataArguments
        if ($LASTEXITCODE -ne 0) { throw "ELF/HEX mismatch: $($job.Name)" }
        Write-Host "B1 ready: $($job.Name), static Zba instruction sites=$($zbaLines.Count)"
    }
} finally {
    Set-Location -LiteralPath $previousLocation
}
