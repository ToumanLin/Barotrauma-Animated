#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$releaseDir = Split-Path -Parent $PSCommandPath
$localModsDir = [System.IO.Path]::GetFullPath((Join-Path $releaseDir ".."))
$modRootDir = Join-Path $localModsDir "Barotrauma-Animated"
$repoDir = Join-Path $modRootDir "Repo"
$releaseScript = Join-Path $repoDir "release.ps1"

if (!(Test-Path -LiteralPath $releaseScript)) {
    Write-Host "ERROR: release.ps1 not found at '$releaseScript'" -ForegroundColor Red
    Write-Host "Please ensure the file structure is correct."
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "Launching Barotrauma Mod Release Process..."
Write-Host "Release Output Directory: '$releaseDir'"
Write-Host "Mod Source Directory: '$modRootDir'"
Write-Host ""

Push-Location $releaseDir
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $releaseScript
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "Release process finished."
Read-Host "Press Enter to exit"
