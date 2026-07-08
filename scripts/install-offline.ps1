#Requires -Version 5.1
param(
    [switch]$User,
    [string]$Prefix = "",
    [string]$Package = "",
    [switch]$Force,
    [switch]$NoVerify
)

$ErrorActionPreference = "Stop"

function Write-Log([string]$Message) { Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host "[x] $Message" -ForegroundColor Red; exit 1 }

if (-not $Package) {
    $Package = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$Package = (Resolve-Path $Package).Path

$Binary = Join-Path $Package "bin\claude.exe"
if (-not (Test-Path -LiteralPath $Binary)) {
    Write-Err "Binary not found: $Binary"
}

if (-not $NoVerify) {
    $VerifyScript = Join-Path $Package "verify-package.ps1"
    if (Test-Path -LiteralPath $VerifyScript) {
        & $VerifyScript -Package $Package
    }
}

if ($User -or $Prefix) {
    if ($Prefix) {
        $TargetDir = Join-Path $Prefix "bin"
    } else {
        $TargetDir = Join-Path $env:LOCALAPPDATA "Programs\claude-code\bin"
    }
} else {
    $TargetDir = Join-Path $env:ProgramFiles "Claude Code\bin"
}

$Target = Join-Path $TargetDir "claude.exe"

if ((Test-Path -LiteralPath $Target) -and -not $Force) {
    Write-Warn "Target already exists: $Target"
    Write-Warn "Use -Force to overwrite, or run uninstall.ps1 first."
    exit 1
}

Write-Log "Installing Claude Code to: $Target"
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
Copy-Item -LiteralPath $Binary -Destination $Target -Force

$PathEntries = @($TargetDir)
if ($User -or $Prefix) {
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $Parts = @()
    if ($UserPath) { $Parts = $UserPath -split ";" | Where-Object { $_ } }
    if ($Parts -notcontains $TargetDir) {
        $NewPath = ($Parts + $PathEntries) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        $env:Path = $TargetDir + ";" + $env:Path
        Write-Log "Added to user PATH: $TargetDir"
    }
} else {
    $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $Parts = @()
    if ($MachinePath) { $Parts = $MachinePath -split ";" | Where-Object { $_ } }
    if ($Parts -notcontains $TargetDir) {
        $NewPath = ($Parts + $PathEntries) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")
        Write-Log "Added to system PATH: $TargetDir (open a new terminal to use it)"
    }
}

Write-Log "Installation complete."
try {
    & $Target --version
} catch {
    Write-Warn "claude --version failed; check system compatibility."
}
