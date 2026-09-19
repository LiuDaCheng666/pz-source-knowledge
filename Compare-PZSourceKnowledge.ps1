[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PreviousGameSnapshot
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$current = Get-Content -LiteralPath (Join-Path $root "current.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$reports = Join-Path $root "generated\reports"
New-Item -ItemType Directory -Path $reports -Force | Out-Null

function Resolve-KnowledgePath([string]$Value) {
    if ([IO.Path]::IsPathRooted($Value)) { return [IO.Path]::GetFullPath($Value) }
    return [IO.Path]::GetFullPath((Join-Path $root $Value))
}

function Read-FileIndex([string]$Base) {
    $map = @{}
    $path = Join-Path (Resolve-KnowledgePath $Base) "indexes\files.jsonl"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $map }
    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $row = $line | ConvertFrom-Json
        $map["$($row.kind):$($row.path)"] = $row
    }
    return $map
}

function Compare-Index([string]$OldPath, [string]$NewPath) {
    $old = Read-FileIndex $OldPath
    $new = Read-FileIndex $NewPath
    $added = @($new.Keys | Where-Object { -not $old.ContainsKey($_) } | Sort-Object)
    $removed = @($old.Keys | Where-Object { -not $new.ContainsKey($_) } | Sort-Object)
    $changed = @($new.Keys | Where-Object { $old.ContainsKey($_) -and $new[$_].sha256 -ne $old[$_].sha256 } | Sort-Object)
    return [ordered]@{ added = $added; removed = $removed; changed = $changed }
}

function Read-SymbolMap([string]$Base, [string]$FileName, [string]$Kind) {
    $map = @{}
    $path = Join-Path (Resolve-KnowledgePath $Base) "indexes\$FileName"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $map }
    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $row = $line | ConvertFrom-Json
        $key = switch ($Kind) {
            "java" { "$($row.className)|$($row.kind)|$($row.name)|$($row.descriptor)" }
            "lua" { "$($row.path)|$($row.kind)|$($row.name)|$($row.signature)" }
            "event" { "$($row.path)|$($row.line)|$($row.event)|$($row.callback)" }
            "protocol" { "$($row.path)|$($row.direction)|$($row.command)|$($row.key)" }
            default { throw "Unsupported symbol-map kind: $Kind" }
        }
        $map[$key] = $row
    }
    return $map
}

function Compare-Map($Old, $New) {
    return [ordered]@{
        added = @($New.Keys | Where-Object { -not $Old.ContainsKey($_) } | Sort-Object)
        removed = @($Old.Keys | Where-Object { -not $New.ContainsKey($_) } | Sort-Object)
    }
}

$game = Compare-Index $PreviousGameSnapshot ([string]$current.gameSnapshot)
$oldJava = Read-SymbolMap $PreviousGameSnapshot "java-symbols.jsonl" "java"
$newJava = Read-SymbolMap ([string]$current.gameSnapshot) "java-symbols.jsonl" "java"
$oldLua = Read-SymbolMap $PreviousGameSnapshot "lua-symbols.jsonl" "lua"
$newLua = Read-SymbolMap ([string]$current.gameSnapshot) "lua-symbols.jsonl" "lua"
$oldEvents = Read-SymbolMap $PreviousGameSnapshot "events.jsonl" "event"
$newEvents = Read-SymbolMap ([string]$current.gameSnapshot) "events.jsonl" "event"
$oldProtocol = Read-SymbolMap $PreviousGameSnapshot "protocol.jsonl" "protocol"
$newProtocol = Read-SymbolMap ([string]$current.gameSnapshot) "protocol.jsonl" "protocol"
$javaDiff = Compare-Map $oldJava $newJava
$luaDiff = Compare-Map $oldLua $newLua
$eventDiff = Compare-Map $oldEvents $newEvents
$protocolDiff = Compare-Map $oldProtocol $newProtocol

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$jsonPath = Join-Path $reports "knowledge-diff-$stamp.json"
$mdPath = Join-Path $reports "knowledge-diff-$stamp.md"
$report = [ordered]@{
    generatedAt = [DateTime]::UtcNow.ToString('o')
    previousGameSnapshot = $PreviousGameSnapshot
    currentGameSnapshot = $current.gameSnapshot
    game = $game
    symbols = [ordered]@{
        java = $javaDiff
        lua = $luaDiff
        events = $eventDiff
        protocol = $protocolDiff
    }
}
[IO.File]::WriteAllText($jsonPath, (ConvertTo-Json $report -Depth 8), [Text.UTF8Encoding]::new($false))
$lines = @(
    "# 知识库版本差异",
    "",
    "- 生成时间：$($report.generatedAt)",
    "- 原版：``$PreviousGameSnapshot`` -> ``$($current.gameSnapshot)``",
    "",
    "| 范围 | 新增 | 删除 | 修改 |",
    "|---|---:|---:|---:|",
    "| 原版 | $($game.added.Count) | $($game.removed.Count) | $($game.changed.Count) |",
    "",
    "## 符号变化",
    "",
    "| 索引 | 新增 | 删除 |",
    "|---|---:|---:|",
    "| Java 字节码 API | $($javaDiff.added.Count) | $($javaDiff.removed.Count) |",
    "| 原版 Lua 函数 | $($luaDiff.added.Count) | $($luaDiff.removed.Count) |",
    "| 原版事件注册 | $($eventDiff.added.Count) | $($eventDiff.removed.Count) |",
    "| 原版协议引用 | $($protocolDiff.added.Count) | $($protocolDiff.removed.Count) |"
)
[IO.File]::WriteAllLines($mdPath, $lines, [Text.UTF8Encoding]::new($false))
Write-Host "Knowledge diff: $mdPath"
