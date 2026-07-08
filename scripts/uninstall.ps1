#Requires -Version 5.1
param(
    [switch]$User,
    [string]$Prefix = "",
    [switch]$RemoveUserData
)

$ErrorActionPreference = "Stop"

function Write-Log([string]$Message) { Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[!] $Message" -ForegroundColor Yellow }

if ($User -or $Prefix) {
    if ($Prefix) {
        $Target = Join-Path $Prefix "bin\claude.exe"
        $TargetDir = Join-Path $Prefix "bin"
    } else {
        $TargetDir = Join-Path $env:LOCALAPPDATA "Programs\claude-code\bin"
        $Target = Join-Path $TargetDir "claude.exe"
    }
    $PathScope = "User"
} else {
    $TargetDir = Join-Path $env:ProgramFiles "Claude Code\bin"
    $Target = Join-Path $TargetDir "claude.exe"
    $PathScope = "Machine"
}

if (Test-Path -LiteralPath $Target) {
    Remove-Item -LiteralPath $Target -Force
    Write-Log "Removed: $Target"
} else {
    Write-Warn "Not found: $Target"
}

$CurrentPath = [Environment]::GetEnvironmentVariable("Path", $PathScope)
if ($CurrentPath) {
    $Parts = $CurrentPath -split ";" | Where-Object { $_ -and ($_ -ne $TargetDir) }
    [Environment]::SetEnvironmentVariable("Path", ($Parts -join ";"), $PathScope)
}

if ($RemoveUserData) {
    $ClaudeDir = Join-Path $env:USERPROFILE ".claude"
    $ClaudeJson = Join-Path $env:USERPROFILE ".claude.json"
    if (Test-Path -LiteralPath $ClaudeDir) { Remove-Item -LiteralPath $ClaudeDir -Recurse -Force }
    if (Test-Path -LiteralPath $ClaudeJson) { Remove-Item -LiteralPath $ClaudeJson -Force }
    Write-Log "Removed user data: $ClaudeDir $ClaudeJson"
} else {
    Write-Warn "User data not removed. Use -RemoveUserData to delete ~/.claude"
}
