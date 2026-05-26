#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

function Get-ReleasePaths {
    $repoDir = Split-Path -Parent $PSCommandPath
    $modRootDir = [System.IO.Path]::GetFullPath((Join-Path $repoDir ".."))
    $releaseOutputDir = (Get-Location).Path

    return @{
        Repo = $repoDir
        ModRoot = $modRootDir
        ReleaseOutput = $releaseOutputDir
    }
}

function Get-CurrentModVersion {
    param([Parameter(Mandatory)][string]$ModRootDir)

    $changelogPath = Join-Path $ModRootDir "About\changelog.txt"
    if (!(Test-Path -LiteralPath $changelogPath)) {
        Write-Warning "changelog.txt not found at $changelogPath"
        return "1.0.0"
    }

    try {
        $lines = Get-Content -LiteralPath $changelogPath -Encoding UTF8
        if ($lines.Count -ge 5) {
            $version = $lines[4].Trim()
            if ($version -match '^\d+\.\d+\.\d+$') {
                return $version
            }

            Write-Warning "Invalid version format in changelog.txt line 5: $version"
            return "1.0.0"
        }

        Write-Warning "changelog.txt has fewer than 5 lines"
        return "1.0.0"
    }
    catch {
        Write-Warning "Error reading changelog.txt: $($_.Exception.Message)"
        return "1.0.0"
    }
}

function Read-NewVersion {
    param([Parameter(Mandatory)][string]$CurrentVersion)

    Write-Host ""
    Write-Host "Current modversion: $CurrentVersion"
    while ($true) {
        $newVersion = (Read-Host "Enter new modversion ([Main Version].[Sub Version].[Update Count]) or press Enter to keep current").Trim()
        if (!$newVersion) {
            Write-Host "Using current version: $CurrentVersion"
            return $CurrentVersion
        }

        if ($newVersion -match '^\d+\.\d+\.\d+$') {
            return $newVersion
        }

        Write-Host "Invalid version format. Please use format: x.y.z (e.g., 2.0.2)" -ForegroundColor Yellow
    }
}

function Invoke-SafetyChecks {
    param(
        [Parameter(Mandatory)][string]$ModRootDir,
        [Parameter(Mandatory)][string]$ReleaseOutputDir
    )

    Write-Host "Performing safety checks..."
    $system32 = Join-Path $env:WINDIR "System32"

    if ([string]::Equals($ReleaseOutputDir, $system32, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Running in System32 is forbidden! Aborting."
    }

    if ([string]::Equals($ReleaseOutputDir, $ModRootDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "This script should NOT be run directly from the mod's source directory. Run it from the intended release output directory."
    }

    Write-Host "Safety checks passed."
}

function Clear-ReleaseDirectory {
    param(
        [Parameter(Mandatory)][string]$DirectoryPath,
        [string]$ExcludeFile
    )

    Write-Host "Cleaning directory: $DirectoryPath..."
    $excludeFullPath = if ($ExcludeFile) { [System.IO.Path]::GetFullPath($ExcludeFile) } else { $null }

    Get-ChildItem -LiteralPath $DirectoryPath -Force | ForEach-Object {
        $itemFullPath = [System.IO.Path]::GetFullPath($_.FullName)
        if ($excludeFullPath -and [string]::Equals($itemFullPath, $excludeFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }

        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }

    Write-Host "Directory cleaned successfully."
}

function Copy-ReleaseContent {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$DestinationRoot
    )

    $foldersToCopy = @("About", "Content", "Subs", "要中文人名就用这里面的文件替换names xml")
    $filesToCopy = @("filelist.xml")

    Write-Host ""
    Write-Host "Copying folders..."
    foreach ($folder in $foldersToCopy) {
        $src = Join-Path $SourceRoot $folder
        $dest = Join-Path $DestinationRoot $folder

        if (Test-Path -LiteralPath $src) {
            if (Test-Path -LiteralPath $dest) {
                Remove-Item -LiteralPath $dest -Recurse -Force
            }
            Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
            Write-Host "Copied folder: '$folder'"
        }
        else {
            Write-Warning "Source folder '$src' not found. Skipping."
        }
    }

    Write-Host ""
    Write-Host "Copying files..."
    foreach ($fileName in $filesToCopy) {
        $src = Join-Path $SourceRoot $fileName
        $dest = Join-Path $DestinationRoot $fileName

        if (!(Test-Path -LiteralPath $src)) {
            throw "Source file '$src' not found. Aborting."
        }

        Copy-Item -LiteralPath $src -Destination $dest -Force
        Write-Host "Copied file: '$fileName'"
    }
}

function Invoke-ItemListGeneration {
    param([Parameter(Mandatory)][string]$RepoDir)

    Write-Host ""
    Write-Host "Generating item list..."
    $scriptPath = Join-Path $RepoDir "item_list_generator.ps1"
    if (!(Test-Path -LiteralPath $scriptPath)) {
        throw "item_list_generator.ps1 not found at $scriptPath. Aborting."
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Item list generation failed with exit code $LASTEXITCODE."
    }

    Write-Host "Item list generation successful."
}

function Update-ReleaseFilelist {
    param(
        [Parameter(Mandatory)][string]$FilelistPath,
        [Parameter(Mandatory)][string]$NewVersion
    )

    Write-Host ""
    Write-Host "Modifying filelist.xml at: $FilelistPath..."
    if (!(Test-Path -LiteralPath $FilelistPath)) {
        throw "filelist.xml not found at $FilelistPath"
    }

    $content = Get-Content -LiteralPath $FilelistPath -Raw -Encoding UTF8
    $lines = $content -split "`n" | Where-Object { $_ -notmatch "ArchiveAndReference" }
    $content = $lines -join "`n"
    $content = $content.Replace('name="[EA-HI]木卫二萌化计划-DEV"', 'name="[EA-HI]木卫二萌化计划" steamworkshopid="2809175631"')
    $content = [regex]::Replace($content, 'modversion="[^"]*"', "modversion=`"$NewVersion`"")
    Set-Content -LiteralPath $FilelistPath -Value $content -Encoding UTF8 -NoNewline
    Write-Host "Filelist.xml modified successfully. Updated version to: $NewVersion"
}

function Copy-ReleaseLauncher {
    param(
        [Parameter(Mandatory)][string]$SourceRepoDir,
        [Parameter(Mandatory)][string]$DestinationReleaseDir
    )

    Write-Host ""
    Write-Host "Copying ZZ_Release.ps1 to output directory..."
    $src = Join-Path $SourceRepoDir "ZZ_Release.ps1"
    $dest = Join-Path $DestinationReleaseDir "ZZ_Release.ps1"

    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $dest -Force
        Write-Host "Copied 'ZZ_Release.ps1' to '$dest'"
    }
    else {
        Write-Warning "'ZZ_Release.ps1' not found in Repo directory at '$src'. Skipping copy."
    }
}

try {
    Write-Host "--- Starting Mod Release Preparation ---"
    $paths = Get-ReleasePaths

    Write-Host "Mod Source Directory: $($paths.ModRoot)"
    Write-Host "Release Output Directory: $($paths.ReleaseOutput)"
    Read-Host "Press Enter to continue or Ctrl+C to abort"

    Invoke-SafetyChecks -ModRootDir $paths.ModRoot -ReleaseOutputDir $paths.ReleaseOutput
    Clear-ReleaseDirectory -DirectoryPath $paths.ReleaseOutput -ExcludeFile (Join-Path $paths.ReleaseOutput "ZZ_Release.ps1")
    Invoke-ItemListGeneration -RepoDir $paths.Repo
    Copy-ReleaseContent -SourceRoot $paths.ModRoot -DestinationRoot $paths.ReleaseOutput

    $currentVersion = Get-CurrentModVersion -ModRootDir $paths.ModRoot
    $newVersion = Read-NewVersion -CurrentVersion $currentVersion
    Update-ReleaseFilelist -FilelistPath (Join-Path $paths.ReleaseOutput "filelist.xml") -NewVersion $newVersion
    Copy-ReleaseLauncher -SourceRepoDir $paths.Repo -DestinationReleaseDir $paths.ReleaseOutput

    Write-Host ""
    Write-Host "--- Mod Release Preparation Done. ---"
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    Read-Host "Press Enter to exit"
}
