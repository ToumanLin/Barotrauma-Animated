#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null
$ErrorActionPreference = "Stop"

$RepoRoot = "C:\Program Files (x86)\Steam\steamapps\common\Barotrauma\LocalMods\Barotrauma-Animated"
$ReferenceRoot = Join-Path $RepoRoot "ReferenceMod"

$mods = @(
  @{
    Name   = "Waifu in the deep"
    Source = "C:\Program Files (x86)\Steam\steamapps\workshop\content\602960\2655395672"
    Target = Join-Path $ReferenceRoot "Waifu in the deep"
  },
  @{
    Name   = "Anime Waifu"
    Source = "C:\Program Files (x86)\Steam\steamapps\workshop\content\602960\3100128373"
    Target = Join-Path $ReferenceRoot "Anime Waifu"
  },
  @{
    Name   = "ProjectEndfield"
    Source = "C:\Program Files (x86)\Steam\steamapps\workshop\content\602960\3126336445"
    Target = Join-Path $ReferenceRoot "ProjectEndfield"
  },
  @{
    Name   = "EuropaMoeProject with male"
    Source = "C:\Program Files (x86)\Steam\steamapps\workshop\content\602960\3127901589"
    Target = Join-Path $ReferenceRoot "EuropaMoeProject with male"
  },
  @{
    Name   = "S.A.F.S"
    Source = "C:\Program Files (x86)\Steam\steamapps\workshop\content\602960\3341377109"
    Target = Join-Path $ReferenceRoot "S.A.F.S"
  },
  @{
    Name   = "Blue Archive Extra Content"
    Source = "C:\Program Files (x86)\Steam\steamapps\workshop\content\602960\3568170618"
    Target = Join-Path $ReferenceRoot "Blue Archive Extra Content"
  },
  @{
    Name   = "OTFX"
    Source = "C:\Program Files (x86)\Steam\steamapps\workshop\content\602960\2986787106"
    Target = Join-Path $ReferenceRoot "OTFX"
  }
)

Set-Location $RepoRoot

foreach ($mod in $mods) {
  Write-Host "Syncing $($mod.Name)..." -ForegroundColor Cyan

  if (!(Test-Path $mod.Source)) {
    Write-Warning "Source not found: $($mod.Source)"
    continue
  }

  if (!(Test-Path $mod.Target)) {
    New-Item -ItemType Directory -Path $mod.Target | Out-Null
  }

  robocopy `
    $mod.Source `
    $mod.Target `
    /MIR `
    /XD ".git" ".svn" `
    /XF "Thumbs.db" "desktop.ini" `
    /R:2 `
    /W:1 `
    /NFL `
    /NDL `
    /NJH `
    /NJS `
    /NP

  # Robocopy exit codes 0-7 are normal/success states.
  if ($LASTEXITCODE -gt 7) {
    throw "Robocopy failed for $($mod.Name) with exit code $LASTEXITCODE"
  }

  git add -- "ReferenceMod/$($mod.Name)"
}

git status

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
git commit -m "Update reference mods snapshot $timestamp"