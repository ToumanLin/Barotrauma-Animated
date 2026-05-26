#Requires -Version 5.1

$ErrorActionPreference = "Stop"

Write-Host "Converting all .wav files to .ogg..."
Write-Host ""

$scriptDir = Split-Path -Parent $PSCommandPath
$wavFiles = @(Get-ChildItem -LiteralPath $scriptDir -File -Filter "*.wav")

foreach ($file in $wavFiles) {
    Write-Host "Found file: $($file.Name)"
    $outputPath = Join-Path $scriptDir ($file.BaseName + ".ogg")
    & ffmpeg -y -i $file.FullName $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed for '$($file.FullName)' with exit code $LASTEXITCODE"
    }

    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $file.FullName -Force
    }
}

Write-Host ""
Write-Host "All files processed."
Read-Host "Press Enter to exit"
