[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [switch]$Sync,
    [string]$CfrJar = $env:PZ_CFR_JAR
)

$ErrorActionPreference = "Stop"

function Assert-Directory([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label directory is missing: $Path"
    }
    return [IO.Path]::GetFullPath($Path)
}

function Get-TreeDigest([string[]]$Roots) {
    $records = [Collections.Generic.List[string]]::new()
    foreach ($rootPath in $Roots) {
        $resolved = Assert-Directory $rootPath "Digest source"
        $label = Split-Path -Leaf $resolved
        foreach ($file in Get-ChildItem -LiteralPath $resolved -Recurse -File | Sort-Object FullName) {
            $relative = $file.FullName.Substring($resolved.Length).TrimStart('\').Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $records.Add("$label/$relative|$($file.Length)|$hash")
        }
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($records -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash($bytes))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-MediaMetadataFiles([string]$MediaPath) {
    $extensions = @('.xml', '.txt', '.json', '.csv', '.ini', '.properties', '.md', '.html', '.css', '.info', '.animstates', '.tbx')
    $luaPrefix = (Join-Path $MediaPath 'lua').TrimEnd('\') + '\'
    $scriptsPrefix = (Join-Path $MediaPath 'scripts').TrimEnd('\') + '\'
    return @(Get-ChildItem -LiteralPath $MediaPath -Recurse -File | Where-Object {
        $_.Extension.ToLowerInvariant() -in $extensions -and
        -not $_.FullName.StartsWith($luaPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        -not $_.FullName.StartsWith($scriptsPrefix, [StringComparison]::OrdinalIgnoreCase)
    })
}

function Get-FileSetDigest([string]$BasePath, [IO.FileInfo[]]$Files) {
    $records = [Collections.Generic.List[string]]::new()
    foreach ($file in $Files | Sort-Object FullName) {
        $relative = $file.FullName.Substring($BasePath.Length).TrimStart('\').Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $records.Add("$relative|$($file.Length)|$hash")
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($records -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash($bytes))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$currentPath = Join-Path $PSScriptRoot "current.json"
if (-not (Test-Path -LiteralPath $currentPath -PathType Leaf)) {
    throw "Knowledge base has not been built: $currentPath"
}
$manifestPath = Join-Path $SourceRoot "steamapps\appmanifest_380870.acf"
$jarPath = Join-Path $SourceRoot "java\projectzomboid.jar"
$mediaRoot = Join-Path $SourceRoot "media"
$luaRoot = Join-Path $mediaRoot "lua"
$scriptsRoot = Join-Path $mediaRoot "scripts"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $jarPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $luaRoot -PathType Container) -or
        -not (Test-Path -LiteralPath $scriptsRoot -PathType Container)) {
    throw "Candidate server installation is incomplete: $SourceRoot"
}
$current = Get-Content -LiteralPath $currentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
$match = [regex]::Match($manifest, '"buildid"\s+"(\d+)"')
if (-not $match.Success) { throw "Candidate Build ID is missing" }
$candidateBuild = $match.Groups[1].Value
$candidateJar = (Get-FileHash -LiteralPath $jarPath -Algorithm SHA256).Hash.ToLowerInvariant()
$candidateTree = Get-TreeDigest -Roots @($luaRoot, $scriptsRoot)
$candidateMetadata = Get-FileSetDigest $mediaRoot @(Get-MediaMetadataFiles $mediaRoot)
$snapshotPath = if ([IO.Path]::IsPathRooted([string]$current.gameSnapshot)) {
    [IO.Path]::GetFullPath([string]$current.gameSnapshot)
} else {
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ([string]$current.gameSnapshot)))
}
$provenancePath = Join-Path $snapshotPath "provenance.json"
if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) {
    throw "Current snapshot provenance is missing: $provenancePath"
}
$provenance = Get-Content -LiteralPath $provenancePath -Raw -Encoding UTF8 | ConvertFrom-Json
$changed = $candidateBuild -ne [string]$current.gameBuildId -or
    $candidateJar -ne [string]$current.jarSha256 -or
    $candidateTree -ne [string]$provenance.vanillaTreeSha256 -or
    $candidateMetadata -ne [string]$provenance.mediaMetadataSha256
$result = [ordered]@{
    checkedAt = [DateTime]::UtcNow.ToString('o')
    sourceRoot = [IO.Path]::GetFullPath($SourceRoot)
    currentBuildId = [string]$current.gameBuildId
    candidateBuildId = $candidateBuild
    currentJarSha256 = [string]$current.jarSha256
    candidateJarSha256 = $candidateJar
    currentVanillaTreeSha256 = [string]$provenance.vanillaTreeSha256
    candidateVanillaTreeSha256 = $candidateTree
    currentMediaMetadataSha256 = [string]$provenance.mediaMetadataSha256
    candidateMediaMetadataSha256 = $candidateMetadata
    gameUpdateDetected = $changed
}
$result | ConvertTo-Json
if ($Sync) {
    $arguments = @("-SourceRoot", $SourceRoot)
    if (-not [string]::IsNullOrWhiteSpace($CfrJar)) { $arguments += @("-CfrJar", $CfrJar) }
    & (Join-Path $PSScriptRoot "Build-PZSourceKnowledge.ps1") @arguments
    if ($LASTEXITCODE -ne 0) { throw "Knowledge-base synchronization failed" }
}
