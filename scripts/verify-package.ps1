#Requires -Version 5.1
param(
    [string]$Package = "",
    [switch]$NoGpg
)

$ErrorActionPreference = "Stop"
$ExpectedGpgFpr = "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

function Write-Log([string]$Message) { Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host "[x] $Message" -ForegroundColor Red; exit 1 }

if (-not $Package) {
    $Package = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$Package = (Resolve-Path $Package).Path

$ChecksumsFile = Join-Path $Package "meta\checksums.txt"
$Binary = Join-Path $Package "bin\claude.exe"
if (-not (Test-Path -LiteralPath $ChecksumsFile)) { Write-Err "Missing: $ChecksumsFile" }
if (-not (Test-Path -LiteralPath $Binary)) { Write-Err "Missing: $Binary" }

$Lines = Get-Content -LiteralPath $ChecksumsFile
foreach ($Line in $Lines) {
    if ($Line -match '^\s*$' -or $Line -match '^\s*#') { continue }
    $Parts = $Line -split '\s+', 2
    if ($Parts.Count -lt 2) { continue }
    $Expected = $Parts[0].ToLower()
    $RelPath = $Parts[1].Trim() -replace '/', '\'
    $File = Join-Path $Package $RelPath
    if (-not (Test-Path -LiteralPath $File)) { Write-Err "Missing file: $RelPath" }
    $Actual = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLower()
    if ($Actual -ne $Expected) {
        Write-Err "SHA256 mismatch: $RelPath expected=$Expected actual=$Actual"
    }
}
Write-Log "SHA256 verification passed."

if ($NoGpg) {
    Write-Warn "Skipped GPG signature verification."
    exit 0
}

$Manifest = Join-Path $Package "meta\manifest.json"
$Sig = Join-Path $Package "meta\manifest.json.sig"
$Key = Join-Path $Package "meta\claude-code.asc"
if (-not (Test-Path -LiteralPath $Manifest) -or -not (Test-Path -LiteralPath $Sig) -or -not (Test-Path -LiteralPath $Key)) {
    Write-Warn "Missing manifest/signature/key; skipped GPG verification."
    exit 0
}

$Gpg = Get-Command gpg -ErrorAction SilentlyContinue
if (-not $Gpg) {
    Write-Warn "gpg not found; skipped GPG verification."
    exit 0
}

$Work = Join-Path $env:TEMP ("claude-offline-gpg-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $Work | Out-Null
try {
    $Env:GNUPGHOME = $Work
    & gpg --batch --import $Key 2>&1 | Out-Null
    $FpLine = & gpg --batch --with-colons --fingerprint security@anthropic.com 2>$null | Where-Object { $_ -match '^fpr:' } | Select-Object -First 1
    if (-not $FpLine) { Write-Err "Failed to read GPG fingerprint." }
    $Fp = ($FpLine -split ':')[9].ToUpper()
    if ($Fp -ne $ExpectedGpgFpr) { Write-Err "GPG fingerprint mismatch: $Fp" }
    & gpg --batch --verify $Sig $Manifest 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Err "manifest signature verification failed" }
    Write-Log "manifest GPG signature verification passed."
} finally {
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:GNUPGHOME -ErrorAction SilentlyContinue
}
