#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$BarotraumaContentPath = "C:\Program Files (x86)\Steam\steamapps\common\Barotrauma\Content"
$OutputFilename = "itemlist.md"
$ChineseLangCode = "Simplified Chinese"
$EnglishLangCode = "English"

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string[]]$Lines
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $encoding)
}

function Sort-Ordinal {
    param([Parameter(Mandatory)]$Values)

    $array = @($Values)
    [array]::Sort($array, [System.StringComparer]::Ordinal)
    return $array
}

function Get-XmlFiles {
    param([Parameter(Mandatory)][string]$Directory)

    if (!(Test-Path -LiteralPath $Directory)) {
        return @()
    }

    Get-ChildItem -LiteralPath $Directory -Recurse -File -Filter "*.xml" |
        Where-Object { $_.Name -ne "Reference.xml" } |
        ForEach-Object { $_.FullName }
}

function Remove-UnwantedSections {
    param([Parameter(Mandatory)][string]$Content)

    $patterns = @(
        "<Fabricate[^>]*?/>", "<Fabricate.*?</Fabricate>",
        "<Deconstruct[^>]*?/>", "<Deconstruct.*?</Deconstruct>",
        "<Inventory[^>]*?/>", "<Inventory.*?</Inventory>",
        "<ItemSet[^>]*?/>", "<ItemSet.*?</ItemSet>",
        "<npcsets[^>]*?/>", "<npcsets.*?</npcsets>",
        "<Jobs[^>]*?/>", "<Jobs.*?</Jobs>",
        "<Missions[^>]*?/>", "<Missions.*?</Missions>"
    )

    $result = $Content
    foreach ($pattern in $patterns) {
        $result = [regex]::Replace($result, $pattern, "", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    }
    return $result
}

function Get-IdentifiersFromXmlContent {
    param([Parameter(Mandatory)][string]$Content)

    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($match in [regex]::Matches($Content, '<Item[^>]*?identifier="([^"]+)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        [void]$ids.Add($match.Groups[1].Value)
    }
    return $ids
}

function Get-XmlFilesFromFilelist {
    param(
        [Parameter(Mandatory)][string]$FilelistPath,
        [Parameter(Mandatory)][string]$ModRootDir
    )

    $paths = New-Object System.Collections.Generic.List[string]
    if (!(Test-Path -LiteralPath $FilelistPath)) {
        Write-Warning "filelist.xml not found at $FilelistPath. This will prevent reading mod content via filelist."
        return $paths
    }

    try {
        [xml]$filelist = Get-Content -LiteralPath $FilelistPath -Raw -Encoding UTF8
        $relevantTags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        @("Item", "Jobs", "NPCSets", "Character", "Afflictions", "Sounds", "Text", "Particles", "UIStyle", "RandomEvents", "Missions", "Factions", "Corpses", "EnemySubmarine") |
            ForEach-Object { [void]$relevantTags.Add($_) }

        foreach ($element in $filelist.DocumentElement.ChildNodes) {
            if ($element.NodeType -ne [System.Xml.XmlNodeType]::Element) {
                continue
            }

            if ($relevantTags.Contains($element.Name)) {
                $rawPath = $element.GetAttribute("file")
                if ($rawPath) {
                    $paths.Add($rawPath.Replace("%ModDir%", $ModRootDir))
                }
            }
        }
    }
    catch {
        Write-Warning "Error parsing filelist.xml at $FilelistPath`: $($_.Exception.Message). This will prevent reading mod content via filelist."
    }

    return $paths
}

function Get-ItemIdentifiersFromMod {
    param([Parameter(Mandatory)][string]$ModRootDir)

    $filelistPath = Join-Path $ModRootDir "filelist.xml"
    $xmlFiles = @(Get-XmlFilesFromFilelist -FilelistPath $filelistPath -ModRootDir $ModRootDir)

    if ($xmlFiles.Count -gt 0) {
        Write-Host "Identified $($xmlFiles.Count) XML files from filelist.xml for mod: $ModRootDir"
    }
    else {
        Write-Host "Could not use filelist.xml at $filelistPath. Scanning directory for mod content..."
        $xmlFiles = @(Get-XmlFiles -Directory $ModRootDir)
        Write-Host "Identified $($xmlFiles.Count) XML files by scanning directory for mod: $ModRootDir"
    }

    $allIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($xmlFile in $xmlFiles) {
        if (!(Test-Path -LiteralPath $xmlFile)) {
            Write-Warning "Referenced file not found (might be deleted or incorrect path): $xmlFile"
            continue
        }

        try {
            $content = Get-Content -LiteralPath $xmlFile -Raw -Encoding UTF8
            $cleaned = Remove-UnwantedSections -Content $content
            foreach ($id in (Get-IdentifiersFromXmlContent -Content $cleaned)) {
                [void]$allIds.Add($id)
            }
        }
        catch {
            Write-Warning "Error processing $xmlFile`: $($_.Exception.Message)"
        }
    }

    return $allIds
}

function Get-ItemIdentifiersFromVanilla {
    param([Parameter(Mandatory)][string]$VanillaContentDir)

    Write-Host "Scanning directory for vanilla content: $VanillaContentDir"
    $xmlFiles = @(Get-XmlFiles -Directory $VanillaContentDir)
    $allIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($xmlFile in $xmlFiles) {
        try {
            $content = Get-Content -LiteralPath $xmlFile -Raw -Encoding UTF8
            $cleaned = Remove-UnwantedSections -Content $content
            foreach ($id in (Get-IdentifiersFromXmlContent -Content $cleaned)) {
                [void]$allIds.Add($id)
            }
        }
        catch {
            Write-Warning "Error processing vanilla file $xmlFile`: $($_.Exception.Message)"
        }
    }

    Write-Host "Vanilla unique item identifiers found: $($allIds.Count)."
    return $allIds
}

function Get-TranslationsFromXml {
    param(
        [Parameter(Mandatory)][string]$XmlFilePath,
        [string]$LanguageFilter
    )

    $translations = @{}
    if (!(Test-Path -LiteralPath $XmlFilePath)) {
        return $translations
    }

    try {
        $settings = [System.Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
        $reader = [System.Xml.XmlReader]::Create($XmlFilePath, $settings)
        $doc = [System.Xml.XmlDocument]::new()
        $doc.Load($reader)
        $reader.Close()

        if ($LanguageFilter -and $doc.DocumentElement.GetAttribute("language") -ne $LanguageFilter) {
            return $translations
        }

        foreach ($node in $doc.SelectNodes("//*[starts-with(name(), 'entityname.')]")) {
            $identifier = $node.Name.Substring("entityname.".Length)
            $translations[$identifier] = if ($null -ne $node.InnerText) { $node.InnerText.Trim() } else { "" }
        }
    }
    catch {
        Write-Warning "Error parsing translation file $XmlFilePath`: $($_.Exception.Message)"
    }

    return $translations
}

function Get-AllTranslations {
    param(
        [Parameter(Mandatory)][string]$ModRootDir,
        [Parameter(Mandatory)][string]$VanillaContentDir
    )

    $chinese = @{}
    $english = @{}

    Write-Host "Collecting mod translations..."
    $modTextDir = Join-Path $ModRootDir "Content\Texts"
    foreach ($entry in (Get-TranslationsFromXml -XmlFilePath (Join-Path $modTextDir "SimplifiedChinese.xml") -LanguageFilter $ChineseLangCode).GetEnumerator()) {
        $chinese[$entry.Key] = $entry.Value
    }
    foreach ($entry in (Get-TranslationsFromXml -XmlFilePath (Join-Path $modTextDir "English.xml") -LanguageFilter $EnglishLangCode).GetEnumerator()) {
        $english[$entry.Key] = $entry.Value
    }
    Write-Host "Mod CN translations found: $($chinese.Count), EN translations found: $($english.Count)"

    Write-Host "Collecting vanilla translations..."
    $vanillaTextDir = Join-Path $VanillaContentDir "Texts"
    $cnFiles = @(
        (Join-Path $vanillaTextDir "SimplifiedChinese.xml"),
        (Join-Path $vanillaTextDir "SimplifiedChinese\SimplifiedChineseVanilla.xml"),
        (Join-Path $vanillaTextDir "SimplifiedChinese\SimplifiedChineseVanillaFactions.xml")
    )
    $enFiles = @(
        (Join-Path $vanillaTextDir "English.xml"),
        (Join-Path $vanillaTextDir "English\EnglishVanilla.xml"),
        (Join-Path $vanillaTextDir "English\EnglishVanillaFactions.xml")
    )

    foreach ($file in $cnFiles) {
        foreach ($entry in (Get-TranslationsFromXml -XmlFilePath $file -LanguageFilter $ChineseLangCode).GetEnumerator()) {
            $chinese[$entry.Key] = $entry.Value
        }
    }
    foreach ($file in $enFiles) {
        foreach ($entry in (Get-TranslationsFromXml -XmlFilePath $file -LanguageFilter $EnglishLangCode).GetEnumerator()) {
            $english[$entry.Key] = $entry.Value
        }
    }

    Write-Host "Total CN translations found: $($chinese.Count), Total EN translations found: $($english.Count)"
    return @{
        Chinese = $chinese
        English = $english
    }
}

function Write-ItemComparisonMarkdown {
    param(
        [Parameter(Mandatory)]$Override,
        [Parameter(Mandatory)]$Addon,
        [Parameter(Mandatory)][hashtable]$ChineseTranslations,
        [Parameter(Mandatory)][hashtable]$EnglishTranslations,
        [Parameter(Mandatory)][string]$OutputFilePath
    )

    Write-Host "Writing comparison results to: $OutputFilePath"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("## Items Overridden by This Mod 以下物品被本模组覆盖")
    $lines.Add("")
    $lines.Add("| ID | English | Chinese |")
    $lines.Add("|:---|:---|:---|")

    if ($Override.Count -gt 0) {
        foreach ($itemId in (Sort-Ordinal -Values $Override)) {
            $en = if ($EnglishTranslations.ContainsKey($itemId)) { $EnglishTranslations[$itemId] } else { '<span style="color:red">UKN</span>' }
            $cn = if ($ChineseTranslations.ContainsKey($itemId)) { $ChineseTranslations[$itemId] } else { '<span style="color:red">UKN</span>' }
            $lines.Add("| $itemId | $en | $cn |")
        }
    }
    else {
        $lines.Add("| (No items overridden) | | |")
    }

    $lines.Add("")
    $lines.Add("## Items Added by This Mod 以下物品被本模组添加")
    $lines.Add("")
    $lines.Add("| ID | English | Chinese |")
    $lines.Add("|:---|:---|:---|")

    if ($Addon.Count -gt 0) {
        foreach ($itemId in (Sort-Ordinal -Values $Addon)) {
            $en = if ($EnglishTranslations.ContainsKey($itemId)) { $EnglishTranslations[$itemId] } else { '<span style="color:red">UKN</span>' }
            $cn = if ($ChineseTranslations.ContainsKey($itemId)) { $ChineseTranslations[$itemId] } else { '<span style="color:red">UKN</span>' }
            $lines.Add("| $itemId | $en | $cn |")
        }
    }
    else {
        $lines.Add("| (No new items added) | | |")
    }

    Write-Utf8NoBom -Path $OutputFilePath -Lines $lines
    Write-Host "Comparison results written successfully in Markdown format."
}

Write-Host "Starting item list generation process..."
$repoDir = Split-Path -Parent $PSCommandPath
$modRootDir = [System.IO.Path]::GetFullPath((Join-Path $repoDir ".."))
Write-Host "Determined mod root directory: $modRootDir"

Write-Host "Processing mod items..."
$modIds = Get-ItemIdentifiersFromMod -ModRootDir $modRootDir
Write-Host "Mod unique item identifiers found: $($modIds.Count)"

Write-Host "Processing vanilla items from: $BarotraumaContentPath"
$vanillaIds = Get-ItemIdentifiersFromVanilla -VanillaContentDir $BarotraumaContentPath

Write-Host "Collecting all relevant translations..."
$translations = Get-AllTranslations -ModRootDir $modRootDir -VanillaContentDir $BarotraumaContentPath
Write-Host "Collected $($translations.Chinese.Count) Chinese and $($translations.English.Count) English translations."

Write-Host "Comparing mod and vanilla item lists..."
$overrideItems = @($modIds | Where-Object { $vanillaIds.Contains($_) })
$addonItems = @($modIds | Where-Object { -not $vanillaIds.Contains($_) })

$outputAboutDir = Join-Path $modRootDir "About"
New-Item -ItemType Directory -Path $outputAboutDir -Force | Out-Null
$outputFilePath = Join-Path $outputAboutDir $OutputFilename

Write-ItemComparisonMarkdown `
    -Override $overrideItems `
    -Addon $addonItems `
    -ChineseTranslations $translations.Chinese `
    -EnglishTranslations $translations.English `
    -OutputFilePath $outputFilePath

Write-Host ""
Write-Host "Item list generation complete."
