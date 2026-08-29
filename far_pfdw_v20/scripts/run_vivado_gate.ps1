param(
    [string]$Netlist = "",
    [string]$StdcellDir = "",
    [string]$VivadoBin = ""
)

$ErrorActionPreference = "Stop"
$PackageRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RepoRoot = (& git -C $PackageRoot rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) { throw "Git repository root was not found." }
$BundleRoot = Join-Path $PackageRoot "build\orfs\gate_bundle"
if (-not $Netlist) { $Netlist = Join-Path $BundleRoot "chip_v20_pow2_final.v" }
if (-not $StdcellDir) { $StdcellDir = Join-Path $BundleRoot "stdcell" }
$DataRoot = if ($env:PFDW_DATA_DIR) { $env:PFDW_DATA_DIR } else { Join-Path $RepoRoot "data" }

if (-not (Test-Path -PathType Leaf $Netlist)) {
    throw "Post-route netlist not found: $Netlist. Run the Seraph full flow or pass -Netlist."
}
if (-not (Test-Path -PathType Container $StdcellDir)) {
    throw "ASAP7 Verilog model directory not found: $StdcellDir"
}
if (-not (Test-Path (Join-Path $DataRoot "input_1000.txt"))) {
    throw "input_1000.txt not found under $DataRoot"
}

if (-not $VivadoBin) {
    foreach ($Candidate in @("C:\Xilinx\Vivado\2024.1\bin", "C:\AMD\Vivado\2024.1\bin")) {
        if (Test-Path $Candidate) { $VivadoBin = $Candidate; break }
    }
}
if (-not (Test-Path $VivadoBin)) { throw "Vivado 2024.1 bin directory was not found." }
$env:Path = "$VivadoBin;$env:Path"

$StdcellSources = @(
    Get-ChildItem -Path $StdcellDir -Recurse -File |
        Where-Object { ($_.Extension -in @(".v", ".sv")) -and ($_.Name -ne "dff.v") } |
        Sort-Object FullName |
        ForEach-Object { $_.FullName }
)
if ($StdcellSources.Count -eq 0) { throw "No Verilog cell models found under $StdcellDir" }

$Work = Join-Path $PackageRoot "build\vivado\gate_v20"
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

$Top = "top_tb_gate_v20_1000"
$Snapshot = "${Top}_snapshot"
$Sources = $StdcellSources + @(
    (Resolve-Path $Netlist).Path,
    (Join-Path $PackageRoot "tb\top_tb_gate_v20_1000.sv")
)
$Xvlog = (Get-Command xvlog.bat -ErrorAction Stop).Source
$Xelab = (Get-Command xelab.bat -ErrorAction Stop).Source
$Xsim = (Get-Command xsim.bat -ErrorAction Stop).Source

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

Get-Content (Join-Path $Work "xsim.log") |
    Select-String "Correct|Fail|Accuracy|RESULT|TIMEOUT|FATAL|ERROR"
Write-Host "Gate-level result: $(Join-Path $Work 'xsim.log')"
