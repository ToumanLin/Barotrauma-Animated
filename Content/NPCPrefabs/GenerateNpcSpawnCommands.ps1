#Requires -Version 5.1

param(
    [string]$InputFile = "SpecialNpcs.xml",
    [string]$OutputFile = "npc_spawn_commands.txt"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

function Get-NpcSpawnCommands {
    param([Parameter(Mandatory)][string]$InputPath)

    $commands = New-Object System.Collections.Generic.List[string]
    if (!(Test-Path -LiteralPath $InputPath)) {
        Write-Host "错误：输入文件 '$InputPath' 不存在。" -ForegroundColor Red
        return $commands
    }

    try {
        Write-Host "正在读取文件: $InputPath"
        [xml]$xml = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8

        Write-Host "正在查找 './/npcset'..."
        $npcsets = $xml.SelectNodes("//npcset")
        Write-Host "找到 $($npcsets.Count) 个 <npcset> 元素。"

        foreach ($npcset in $npcsets) {
            $npcsetId = $npcset.GetAttribute("identifier")
            if (!$npcsetId) {
                Write-Warning "找到一个没有 'identifier' 的 <npcset> 标签，已跳过。"
                continue
            }

            foreach ($npc in $npcset.SelectNodes("npc")) {
                $npcId = $npc.GetAttribute("identifier")
                if (!$npcId) {
                    Write-Warning "在 npcset '$npcsetId' 中找到一个没有 'identifier' 的 <npc> 标签，已跳过。"
                    continue
                }

                $commands.Add("spawnnpc $npcsetId $npcId")
            }
        }

        Write-Host "文件处理完成，共找到 $($commands.Count) 条有效指令。"
    }
    catch {
        Write-Host "处理文件 '$InputPath' 时发生错误: $($_.Exception.Message)" -ForegroundColor Red
    }

    return $commands
}

$scriptDir = Split-Path -Parent $PSCommandPath
$inputPath = if ([System.IO.Path]::IsPathRooted($InputFile)) { $InputFile } else { Join-Path $scriptDir $InputFile }
$outputPath = if ([string]::IsNullOrWhiteSpace($OutputFile)) { $null } elseif ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path $scriptDir $OutputFile }

$commands = Get-NpcSpawnCommands -InputPath $inputPath
if ($commands.Count -eq 0) {
    Write-Host "未能生成任何指令。请检查 XML 文件结构和脚本逻辑。"
    exit 0
}

if ($outputPath) {
    $commands | ForEach-Object { "$_ cursor" } | Set-Content -LiteralPath $outputPath -Encoding UTF8
    Write-Host "指令已成功保存到文件: '$outputPath'"
}
else {
    Write-Host ""
    Write-Host "--- 生成的 Spawn 指令 ---"
    $commands | ForEach-Object { Write-Host $_ }
}
