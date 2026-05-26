#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$ExcludedItemAncestors = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
@("Fabricate", "Deconstruct", "Inventory", "ItemSet", "npcsets", "Jobs", "Missions") |
    ForEach-Object { [void]$ExcludedItemAncestors.Add($_) }

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string[]]$Lines
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $encoding)
}

function Get-Paths {
    $repoDir = Split-Path -Parent $PSCommandPath
    $modRootDir = [System.IO.Path]::GetFullPath((Join-Path $repoDir ".."))
    $vanillaContentDir = [System.IO.Path]::GetFullPath((Join-Path $modRootDir "..\..\..\Barotrauma\Content"))
    $outputFilePath = Join-Path $modRootDir "Items_NeedUpdate.md"

    return @{
        Repo = $repoDir
        ModRoot = $modRootDir
        VanillaContent = $vanillaContentDir
        OutputFile = $outputFilePath
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string[]]$Args,
        [Parameter(Mandatory)][string]$Cwd,
        [switch]$AllowFailure
    )

    $result = & git @Args 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and !$AllowFailure) {
        throw "git $($Args -join ' ') failed in '$Cwd': $($result -join [Environment]::NewLine)"
    }

    return @{
        ExitCode = $exitCode
        Output = @($result)
    }
}

function Get-ChangedXmlFiles {
    param([Parameter(Mandatory)][string]$VanillaContentPath)

    Push-Location $VanillaContentPath
    try {
        $gitResult = Invoke-Git -Args @("diff-tree", "--no-commit-id", "--name-status", "-r", "HEAD") -Cwd $VanillaContentPath
    }
    finally {
        Pop-Location
    }

    $changed = New-Object System.Collections.Generic.List[object]
    foreach ($line in $gitResult.Output) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = $line -split "`t"
        $status = $parts[0]
        if (($status.StartsWith("R") -or $status.StartsWith("C")) -and $parts.Count -ge 3) {
            $oldPath = $parts[1]
            $newPath = $parts[2]
        }
        elseif ($parts.Count -ge 2) {
            $oldPath = $parts[1]
            $newPath = $parts[1]
        }
        else {
            continue
        }

        if ($oldPath.EndsWith(".xml", [System.StringComparison]::OrdinalIgnoreCase) -or $newPath.EndsWith(".xml", [System.StringComparison]::OrdinalIgnoreCase)) {
            $changed.Add([pscustomobject]@{
                Status = $status
                OldPath = $oldPath
                NewPath = $newPath
            })
        }
    }

    return $changed
}

function Read-GitFile {
    param(
        [Parameter(Mandatory)][string]$VanillaContentPath,
        [Parameter(Mandatory)][string]$Revision,
        [Parameter(Mandatory)][string]$RelativePath
    )

    Push-Location $VanillaContentPath
    try {
        $result = Invoke-Git -Args @("show", "$Revision`:$RelativePath") -Cwd $VanillaContentPath -AllowFailure
    }
    finally {
        Pop-Location
    }

    if ($result.ExitCode -ne 0) {
        return $null
    }

    return ($result.Output -join "`n")
}

function Get-LocalTagName {
    param([Parameter(Mandatory)][System.Xml.XmlNode]$Node)
    if ($Node.LocalName) {
        return $Node.LocalName
    }
    return $Node.Name
}

function Normalize-XmlElement {
    param([Parameter(Mandatory)][System.Xml.XmlElement]$Element)

    $doc = $Element.OwnerDocument
    $clone = $doc.CreateElement($Element.Prefix, $Element.LocalName, $Element.NamespaceURI)

    $attributes = @($Element.Attributes) | Sort-Object Name
    foreach ($attribute in $attributes) {
        [void]$clone.SetAttribute($attribute.Name, $attribute.Value)
    }

    foreach ($child in $Element.ChildNodes) {
        if ($child.NodeType -eq [System.Xml.XmlNodeType]::Comment) {
            continue
        }

        if ($child.NodeType -eq [System.Xml.XmlNodeType]::Text -or $child.NodeType -eq [System.Xml.XmlNodeType]::Whitespace -or $child.NodeType -eq [System.Xml.XmlNodeType]::SignificantWhitespace) {
            if (![string]::IsNullOrWhiteSpace($child.Value)) {
                [void]$clone.AppendChild($doc.CreateTextNode($child.Value.Trim()))
            }
            continue
        }

        if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            [void]$clone.AppendChild((Normalize-XmlElement -Element ([System.Xml.XmlElement]$child)))
        }
    }

    return $clone
}

function Get-ElementSnapshot {
    param([Parameter(Mandatory)][System.Xml.XmlElement]$Element)

    $doc = [System.Xml.XmlDocument]::new()
    $normalized = Normalize-XmlElement -Element $Element
    [void]$doc.AppendChild($doc.ImportNode($normalized, $true))

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.OmitXmlDeclaration = $true
    $settings.Encoding = [System.Text.Encoding]::UTF8
    $settings.Indent = $false
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::None

    $builder = [System.Text.StringBuilder]::new()
    $writer = [System.Xml.XmlWriter]::Create($builder, $settings)
    $doc.WriteTo($writer)
    $writer.Close()
    return $builder.ToString()
}

function Find-ItemNodes {
    param(
        [Parameter(Mandatory)][System.Xml.XmlNode]$Node,
        [bool]$HasExcludedAncestor = $false,
        [Parameter(Mandatory)]$Items
    )

    if ($Node.NodeType -ne [System.Xml.XmlNodeType]::Element) {
        return
    }

    $tag = Get-LocalTagName -Node $Node
    if ($tag -eq "Item" -and $Node.Attributes["identifier"] -and !$HasExcludedAncestor) {
        $Items.Add([System.Xml.XmlElement]$Node)
    }

    $childHasExcludedAncestor = $HasExcludedAncestor -or $ExcludedItemAncestors.Contains($tag)
    foreach ($child in $Node.ChildNodes) {
        Find-ItemNodes -Node $child -HasExcludedAncestor $childHasExcludedAncestor -Items $Items
    }
}

function Get-ItemSnapshots {
    param([string]$XmlContent)

    $snapshots = @{}
    if ([string]::IsNullOrWhiteSpace($XmlContent)) {
        return $snapshots
    }

    try {
        $doc = [System.Xml.XmlDocument]::new()
        $doc.PreserveWhitespace = $false
        $doc.LoadXml($XmlContent)

        $items = New-Object System.Collections.ArrayList
        Find-ItemNodes -Node $doc.DocumentElement -Items $items

        foreach ($item in $items) {
            $itemId = $item.GetAttribute("identifier")
            if (!$itemId) {
                continue
            }

            if (!$snapshots.ContainsKey($itemId)) {
                $snapshots[$itemId] = New-Object System.Collections.Generic.List[string]
            }
            $snapshots[$itemId].Add((Get-ElementSnapshot -Element $item))
        }
    }
    catch {
        Write-Warning "XML snapshot extraction failed: $($_.Exception.Message)"
    }

    $combined = @{}
    foreach ($key in $snapshots.Keys) {
        $combined[$key] = (($snapshots[$key] | Sort-Object) -join "`n")
    }
    return $combined
}

function Get-ChangedItemIds {
    param(
        [Parameter(Mandatory)][hashtable]$OldItems,
        [Parameter(Mandatory)][hashtable]$NewItems
    )

    $allIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $OldItems.Keys) { [void]$allIds.Add($key) }
    foreach ($key in $NewItems.Keys) { [void]$allIds.Add($key) }

    $changed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($itemId in $allIds) {
        if ($OldItems[$itemId] -ne $NewItems[$itemId]) {
            [void]$changed.Add($itemId)
        }
    }
    return $changed
}

function Get-UpdatedVanillaItems {
    param([Parameter(Mandatory)][string]$VanillaContentPath)

    Write-Host ""
    Write-Host "1. 正在检查 '$VanillaContentPath' 的 git 历史记录..."
    if (!(Test-Path -LiteralPath (Join-Path $VanillaContentPath ".git"))) {
        throw "'$VanillaContentPath' 不是一个 git 仓库. 无法检测更新."
    }

    $xmlFiles = @(Get-ChangedXmlFiles -VanillaContentPath $VanillaContentPath)
    $updatedItemIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $itemPathMap = @{}

    if ($xmlFiles.Count -eq 0) {
        Write-Host "在上一次 git commit 中没有找到被修改的 .xml 文件."
        return @{
            Ids = $updatedItemIds
            PathMap = $itemPathMap
        }
    }

    Write-Host "发现在上一次 commit 中有 $($xmlFiles.Count) 个 .xml 文件被修改:"
    foreach ($file in $xmlFiles) {
        $displayPath = if ($file.Status.StartsWith("D")) { $file.OldPath } else { $file.NewPath }
        if ($displayPath.Replace("\", "/").StartsWith("Items/Assemblies/")) {
            continue
        }

        Write-Host "  - $displayPath"
        $oldXml = if ($file.Status.StartsWith("A")) { $null } else { Read-GitFile -VanillaContentPath $VanillaContentPath -Revision "HEAD^" -RelativePath $file.OldPath }
        $newPath = Join-Path $VanillaContentPath $file.NewPath
        $newXml = if ($file.Status.StartsWith("D") -or !(Test-Path -LiteralPath $newPath)) { $null } else { Get-Content -LiteralPath $newPath -Raw -Encoding UTF8 }

        $oldItems = Get-ItemSnapshots -XmlContent $oldXml
        $newItems = Get-ItemSnapshots -XmlContent $newXml
        $identifiers = Get-ChangedItemIds -OldItems $oldItems -NewItems $newItems

        foreach ($itemId in $identifiers) {
            [void]$updatedItemIds.Add($itemId)
            $reportPath = if ($file.Status.StartsWith("D")) { $file.OldPath } else { $file.NewPath }
            $itemPathMap[$itemId] = $reportPath.Replace("\", "/")
        }
    }

    Write-Host "从更新的香草文件中提取了 $($updatedItemIds.Count) 个真正变更的唯一 item ID."
    return @{
        Ids = $updatedItemIds
        PathMap = $itemPathMap
    }
}

function Get-ModOverriddenItems {
    param(
        [Parameter(Mandatory)][string]$ModRootPath,
        [Parameter(Mandatory)][string]$RepoDir
    )

    Write-Host ""
    Write-Host "2. 正在解析模组覆盖的物品列表..."
    $itemListPath = Join-Path $ModRootPath "About\itemlist.md"

    if (!(Test-Path -LiteralPath $itemListPath)) {
        Write-Warning "'$itemListPath' 未找到. 将首先尝试生成该文件..."
        $generator = Join-Path $RepoDir "item_list_generator.ps1"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $generator
        if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $itemListPath)) {
            throw "自动生成 'itemlist.md' 失败. 请手动运行 item_list_generator.ps1 后再试."
        }
        Write-Host "'itemlist.md' 已成功生成."
    }

    $overriddenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $inOverriddenSection = $false
    foreach ($line in (Get-Content -LiteralPath $itemListPath -Encoding UTF8)) {
        if ($line -like "*## Items Overridden by This Mod*") {
            $inOverriddenSection = $true
            continue
        }
        if ($line -like "*## Items Added by This Mod*") {
            break
        }

        if ($inOverriddenSection) {
            $match = [regex]::Match($line, '^\|\s*([^|]+?)\s*\|')
            if ($match.Success) {
                $itemId = $match.Groups[1].Value.Trim()
                if ($itemId -and $itemId -ne "ID" -and $itemId -ne ":---") {
                    [void]$overriddenIds.Add($itemId)
                }
            }
        }
    }

    Write-Host "从 'itemlist.md' 中找到 $($overriddenIds.Count) 个被模组覆盖的 item ID."
    return $overriddenIds
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
        [xml]$doc = Get-Content -LiteralPath $XmlFilePath -Raw -Encoding UTF8
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

    $translationSources = @(
        @{ File = Join-Path $ModRootDir "Content\Texts\SimplifiedChinese.xml"; Lang = "Simplified Chinese"; Target = $chinese },
        @{ File = Join-Path $ModRootDir "Content\Texts\English.xml"; Lang = "English"; Target = $english },
        @{ File = Join-Path $VanillaContentDir "Texts\SimplifiedChinese.xml"; Lang = "Simplified Chinese"; Target = $chinese },
        @{ File = Join-Path $VanillaContentDir "Texts\SimplifiedChinese\SimplifiedChineseVanilla.xml"; Lang = "Simplified Chinese"; Target = $chinese },
        @{ File = Join-Path $VanillaContentDir "Texts\SimplifiedChinese\SimplifiedChineseVanillaFactions.xml"; Lang = "Simplified Chinese"; Target = $chinese },
        @{ File = Join-Path $VanillaContentDir "Texts\English.xml"; Lang = "English"; Target = $english },
        @{ File = Join-Path $VanillaContentDir "Texts\English\EnglishVanilla.xml"; Lang = "English"; Target = $english },
        @{ File = Join-Path $VanillaContentDir "Texts\English\EnglishVanillaFactions.xml"; Lang = "English"; Target = $english }
    )

    foreach ($source in $translationSources) {
        foreach ($entry in (Get-TranslationsFromXml -XmlFilePath $source.File -LanguageFilter $source.Lang).GetEnumerator()) {
            $source.Target[$entry.Key] = $entry.Value
        }
    }

    return @{
        Chinese = $chinese
        English = $english
    }
}

function Write-Report {
    param(
        [Parameter(Mandatory)]$ItemsToUpdate,
        [Parameter(Mandatory)][hashtable]$Translations,
        [Parameter(Mandatory)][hashtable]$ItemPathMap,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$VanillaContentDir
    )

    Write-Host ""
    Write-Host "4. 正在生成更新报告..."

    $reportData = @()
    foreach ($itemId in $ItemsToUpdate) {
        $path = if ($ItemPathMap.ContainsKey($itemId)) { $ItemPathMap[$itemId] } else { "Unknown Path" }
        $reportData += [pscustomobject]@{ Path = $path; ItemId = $itemId }
    }

    $reportData = $reportData | Sort-Object Path, ItemId
    $reportDir = Split-Path -Parent $OutputPath
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Potentially Outdated Items Report")
    $lines.Add("")
    $lines.Add("此报告列出了最近香草更新中被修改, **并且**也同时被本模组覆盖的物品.")
    $lines.Add("这些物品可能需要检查和更新以兼容最新版本.")
    $lines.Add("")
    $lines.Add("| ID | English | Chinese | Vanilla File Path |")
    $lines.Add("|:---|:---|:---|:---|")

    if (!$reportData -or $reportData.Count -eq 0) {
        $lines.Add("| (没有找到需要更新的重叠物品) | | | |")
    }
    else {
        foreach ($row in $reportData) {
            $itemId = $row.ItemId
            $en = if ($Translations.English.ContainsKey($itemId)) { $Translations.English[$itemId] } else { "N/A" }
            $cn = if ($Translations.Chinese.ContainsKey($itemId)) { $Translations.Chinese[$itemId] } else { "N/A" }

            if ($row.Path -eq "Unknown Path") {
                $pathLink = "Unknown Path"
            }
            else {
                $targetAbs = Join-Path $VanillaContentDir $row.Path
                $baseUri = [System.Uri]::new(([System.IO.Path]::GetFullPath($reportDir).TrimEnd("\") + "\"))
                $targetUri = [System.Uri]::new([System.IO.Path]::GetFullPath($targetAbs))
                $relativePath = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString())
                $fileName = Split-Path -Leaf $row.Path
                $pathLink = "[$fileName]($relativePath)"
            }

            $lines.Add("| $itemId | $en | $cn | $pathLink |")
        }
    }

    Write-Utf8NoBom -Path $OutputPath -Lines $lines
    Write-Host "报告已成功写入到: $OutputPath"
}

function Clear-PyCache {
    param([Parameter(Mandatory)][string]$RepoDir)

    Write-Host ""
    Write-Host "正在清理 $RepoDir 中的 __pycache__ 目录..."
    $pycacheDirs = @(Get-ChildItem -LiteralPath $RepoDir -Recurse -Directory -Filter "__pycache__")
    foreach ($dir in $pycacheDirs) {
        Remove-Item -LiteralPath $dir.FullName -Recurse -Force
        Write-Host "已删除: $($dir.FullName)"
    }

    if ($pycacheDirs.Count -gt 0) {
        Write-Host "清理完成，共删除了 $($pycacheDirs.Count) 个 __pycache__ 目录"
    }
    else {
        Write-Host "未找到需要清理的 __pycache__ 目录"
    }
}

try {
    Write-Host "--- 开始检查模组与香草更新的重叠项 ---"
    $paths = Get-Paths

    Write-Host "Mod 根目录: $($paths.ModRoot)"
    Write-Host "香草 Content 目录: $($paths.VanillaContent)"
    Write-Host "输出文件: $($paths.OutputFile)"

    $updated = Get-UpdatedVanillaItems -VanillaContentPath $paths.VanillaContent
    if ($updated.Ids.Count -eq 0) {
        Write-Host ""
        Write-Host "没有从香草更新中找到任何物品, 进程结束."
        Write-Report -ItemsToUpdate @() -Translations @{ Chinese = @{}; English = @{} } -ItemPathMap @{} -OutputPath $paths.OutputFile -VanillaContentDir $paths.VanillaContent
        return
    }

    $modOverriddenIds = Get-ModOverriddenItems -ModRootPath $paths.ModRoot -RepoDir $paths.Repo
    $itemsThatNeedUpdate = @($updated.Ids | Where-Object { $modOverriddenIds.Contains($_) })
    Write-Host ""
    Write-Host "3. 比较完成: 发现 $($itemsThatNeedUpdate.Count) 个物品需要检查."

    Write-Host "正在收集翻译..."
    $translations = Get-AllTranslations -ModRootDir $paths.ModRoot -VanillaContentDir $paths.VanillaContent
    Write-Host "收集了 $($translations.Chinese.Count) 条中文翻译和 $($translations.English.Count) 条英文翻译."

    Write-Report -ItemsToUpdate $itemsThatNeedUpdate -Translations $translations -ItemPathMap $updated.PathMap -OutputPath $paths.OutputFile -VanillaContentDir $paths.VanillaContent
    Write-Host ""
    Write-Host "--- 检查完成 ---"
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    Clear-PyCache -RepoDir (Split-Path -Parent $PSCommandPath)
}
