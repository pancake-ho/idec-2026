param(
    [ValidateSet("v20", "ab", "cycle_ab", "repo_baseline", "cycle_repo_baseline")]
    [string]$TestName = "ab",
    [string]$VivadoBin = ""
)

$ErrorActionPreference = "Stop"
$PackageRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RepoRoot = (& git -C $PackageRoot rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) { throw "Git repository root was not found." }
$DataRoot = if ($env:PFDW_DATA_DIR) { $env:PFDW_DATA_DIR } else { Join-Path $RepoRoot "data" }

if (-not $VivadoBin) {
    foreach ($Candidate in @("C:\Xilinx\Vivado\2024.1\bin", "C:\AMD\Vivado\2024.1\bin")) {
        if (Test-Path $Candidate) { $VivadoBin = $Candidate; break }
    }
}
if (-not (Test-Path $VivadoBin)) { throw "Vivado 2024.1 bin directory was not found." }
$env:Path = "$VivadoBin;$env:Path"

& python (Join-Path $PackageRoot "scripts\generate_rtl.py")
if ($LASTEXITCODE -ne 0) { throw "V20 RTL generation failed." }

$V20 = @(
    (Join-Path $PackageRoot "rtl\pfdw_pipe49_booth_engine_v20_w5.sv"),
    (Join-Path $PackageRoot "rtl\chip_pfdw_fc_v20_pow2.sv")
)
$V18 = @(
    (Join-Path $RepoRoot "far_pfdw_v19\reference_v18a\pfdw_pipe49_booth_engine_v18a.sv"),
    (Join-Path $RepoRoot "far_pfdw_v19\reference_v18a\chip_pfdw_fc_v18a.sv")
)
$Baseline = @(
    "conv1.v", "conv2.v", "maxpool_relu.v", "fc.v", "comparator.v", "chip.v"
) | ForEach-Object { Join-Path $RepoRoot "verilog\$_" }

switch ($TestName) {
    "v20" {
        $Top = "top_tb_v20_1000"
        $Sources = $V20 + @(Join-Path $PackageRoot "tb\top_tb_v20_1000.sv")
    }
    "ab" {
        $Top = "top_tb_v20_vs_v18a_1000"
        $Sources = $V18 + $V20 + @(Join-Path $PackageRoot "tb\top_tb_v20_vs_v18a_1000.sv")
    }
    "cycle_ab" {
        $Top = "top_tb_cycle_v20_vs_v18a"
        $Sources = $V18 + $V20 + @(Join-Path $PackageRoot "tb\top_tb_cycle_v20_vs_v18a.sv")
    }
    "repo_baseline" {
        $Top = "top_tb_v20_vs_baseline_1000"
        $Sources = $Baseline + $V20 + @(Join-Path $PackageRoot "tb\top_tb_v20_vs_baseline_1000.sv")
    }
    "cycle_repo_baseline" {
        $Top = "top_tb_cycle_v20_vs_baseline"
        $Sources = $Baseline + $V20 + @(Join-Path $PackageRoot "tb\top_tb_cycle_v20_vs_baseline.sv")
    }
}

foreach ($Source in $Sources) {
    if (-not (Test-Path $Source)) { throw "Source file not found: $Source" }
}
if (-not (Test-Path (Join-Path $DataRoot "input_1000.txt"))) { throw "input_1000.txt not found." }

$Work = Join-Path $PackageRoot "build\vivado\$TestName"
$WorkData = Join-Path $Work "data"
New-Item -ItemType Directory -Force -Path $Work, $WorkData | Out-Null
Copy-Item -Path (Join-Path $DataRoot "*") -Destination $WorkData -Recurse -Force

function Invoke-Logged {
    param([string]$Exe, [string[]]$ArgumentList, [string]$ConsoleLog)
    if (Test-Path $ConsoleLog) { Remove-Item -Force $ConsoleLog }
    & $Exe @ArgumentList 2>&1 | Tee-Object -FilePath $ConsoleLog
    $Code = $LASTEXITCODE
    if ($Code -ne 0) { throw "$Exe failed with exit code $Code. Log: $ConsoleLog" }
}

$Xvlog = (Get-Command xvlog.bat -ErrorAction Stop).Source
$Xelab = (Get-Command xelab.bat -ErrorAction Stop).Source
$Xsim = (Get-Command xsim.bat -ErrorAction Stop).Source
$Snapshot = "${Top}_snapshot"

Push-Location $Work
try {
    Invoke-Logged $Xvlog (@("-sv") + $Sources) (Join-Path $Work "xvlog_console.log")
    Invoke-Logged $Xelab @($Top, "-s", $Snapshot, "--debug", "typical", "--timescale", "1ps/1ps") (Join-Path $Work "xelab_console.log")
    Invoke-Logged $Xsim @($Snapshot, "-runall") (Join-Path $Work "xsim_console.log")
    Copy-Item (Join-Path $Work "xsim_console.log") (Join-Path $Work "xsim.log") -Force
}
finally {
    Pop-Location
}

Write-Host "Completed: $TestName"
Write-Host "Result log: $(Join-Path $Work 'xsim.log')"
