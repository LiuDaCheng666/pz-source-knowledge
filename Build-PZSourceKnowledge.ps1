[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [string]$CfrJar = $env:PZ_CFR_JAR,
    [ValidateRange(4, 48)][int]$CfrMaxHeapGB = 16,
    [switch]$ForceGameRebuild,
    [switch]$RebuildIndexes
)

$ErrorActionPreference = "Stop"
$knowledgeRoot = $PSScriptRoot
$generatedRoot = Join-Path $knowledgeRoot "generated"
$snapshotsRoot = Join-Path $generatedRoot "snapshots"
$reportsRoot = Join-Path $generatedRoot "reports"
$nodeIndexer = Join-Path $knowledgeRoot "src\build-indexes.mjs"
$validator = Join-Path $knowledgeRoot "Validate-PZSourceKnowledge.ps1"
$nodeExe = (Get-Command node -ErrorAction Stop).Source
$javaExe = (Get-Command java -ErrorAction Stop).Source
$javapExe = (Get-Command javap -ErrorAction Stop).Source

if ([string]::IsNullOrWhiteSpace($CfrJar)) {
    $CfrJar = Join-Path $knowledgeRoot ".tools\cfr\cfr-0.152.jar"
}

function Assert-Directory([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label directory is missing: $Path"
    }
    return [IO.Path]::GetFullPath($Path)
}

function Assert-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label file is missing: $Path"
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

function Copy-MediaMetadata([string]$MediaPath, [IO.FileInfo[]]$Files, [string]$DestinationMedia) {
    foreach ($file in $Files) {
        $relative = $file.FullName.Substring($MediaPath.Length).TrimStart('\')
        $target = Join-Path $DestinationMedia $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
}

function Write-JsonNoBom([string]$Path, $Value, [int]$Depth = 12) {
    $json = ConvertTo-Json -InputObject $Value -Depth $Depth
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Copy-SourceTree([string]$Source, [string]$Destination) {
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Write-ClassInventory([string]$JarPath, [string]$OutputPath) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($JarPath)
    $writer = [IO.StreamWriter]::new($OutputPath, $false, [Text.UTF8Encoding]::new($false))
    $classes = [Collections.Generic.List[string]]::new()
    try {
        foreach ($entry in $zip.Entries | Where-Object { $_.FullName.EndsWith('.class') } | Sort-Object FullName) {
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() }
            finally { $sha.Dispose(); $stream.Dispose() }
            $className = $entry.FullName.Substring(0, $entry.FullName.Length - 6).Replace('/', '.')
            $gameOwned = $className.StartsWith('zombie.')
            $row = [ordered]@{
                name = $className
                path = $entry.FullName
                bytes = $entry.Length
                compressedBytes = $entry.CompressedLength
                sha256 = $hash
                gameOwned = $gameOwned
            }
            $writer.WriteLine((ConvertTo-Json -InputObject $row -Compress))
            if ($gameOwned) { $classes.Add($className) }
        }
    }
    finally { $writer.Dispose(); $zip.Dispose() }
    return $classes.ToArray()
}

function Write-JavaApi([string[]]$Classes, [string]$ClassPath, [string]$OutputPath) {
    $writer = [IO.StreamWriter]::new($OutputPath, $false, [Text.UTF8Encoding]::new($false))
    try {
        for ($offset = 0; $offset -lt $Classes.Count; $offset += 40) {
            $batch = @($Classes | Select-Object -Skip $offset -First 40)
            $output = & $javapExe -classpath $ClassPath -p -s @batch 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "javap failed at class batch offset $offset`: $($output -join [Environment]::NewLine)"
            }
            foreach ($line in $output) { $writer.WriteLine([string]$line) }
        }
    }
    finally { $writer.Dispose() }
}

$SourceRoot = Assert-Directory $SourceRoot "Project Zomboid server"
$CfrJar = Assert-File $CfrJar "CFR"
$mediaRoot = Assert-Directory (Join-Path $SourceRoot "media") "Vanilla media"
$luaRoot = Assert-Directory (Join-Path $SourceRoot "media\lua") "Vanilla Lua"
$scriptsRoot = Assert-Directory (Join-Path $SourceRoot "media\scripts") "Vanilla scripts"
$jarPath = Assert-File (Join-Path $SourceRoot "java\projectzomboid.jar") "Project Zomboid JAR"
$appManifestPath = Assert-File (Join-Path $SourceRoot "steamapps\appmanifest_380870.acf") "Steam app manifest"
$appManifestText = [IO.File]::ReadAllText($appManifestPath, [Text.Encoding]::UTF8)
$buildMatch = [regex]::Match($appManifestText, '"buildid"\s+"(\d+)"')
if (-not $buildMatch.Success) { throw "Steam Build ID is missing from $appManifestPath" }
$buildId = $buildMatch.Groups[1].Value
$depotMatches = [regex]::Matches($appManifestText, '(?s)"(\d+)"\s*\{\s*"manifest"\s+"(\d+)"')
$depots = [ordered]@{}
foreach ($match in $depotMatches) { $depots[$match.Groups[1].Value] = $match.Groups[2].Value }
$jarSha = (Get-FileHash -LiteralPath $jarPath -Algorithm SHA256).Hash.ToLowerInvariant()
$vanillaTreeSha = Get-TreeDigest -Roots @($luaRoot, $scriptsRoot)
$mediaMetadataFiles = @(Get-MediaMetadataFiles $mediaRoot)
$mediaMetadataSha = Get-FileSetDigest $mediaRoot $mediaMetadataFiles
$snapshotId = "build-$buildId-$($jarSha.Substring(0, 12))-$($vanillaTreeSha.Substring(0, 12))"
$snapshotPath = Join-Path $snapshotsRoot $snapshotId
$previousCurrent = $null
$currentPath = Join-Path $knowledgeRoot "current.json"
if (Test-Path -LiteralPath $currentPath -PathType Leaf) {
    $previousCurrent = Get-Content -LiteralPath $currentPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

New-Item -ItemType Directory -Path $snapshotsRoot, $reportsRoot -Force | Out-Null

if ($ForceGameRebuild -and (Test-Path -LiteralPath $snapshotPath)) {
    throw "Immutable snapshot already exists. Refusing destructive rebuild: $snapshotPath"
}

if (-not (Test-Path -LiteralPath $snapshotPath -PathType Container)) {
    $snapshotTemp = $null
    foreach ($candidate in Get-ChildItem -LiteralPath $generatedRoot -Directory -Filter '.staging-game-*' |
            Sort-Object LastWriteTime -Descending) {
        $candidateJar = Join-Path $candidate.FullName "raw\java\projectzomboid.jar"
        $candidateLua = Join-Path $candidate.FullName "raw\media\lua"
        $candidateScripts = Join-Path $candidate.FullName "raw\media\scripts"
        $candidateApi = Join-Path $candidate.FullName "bytecode\java-api.txt"
        $candidateClasses = Join-Path $candidate.FullName "bytecode\java-classes.jsonl"
        if (-not (Test-Path -LiteralPath $candidateJar -PathType Leaf) -or
                -not (Test-Path -LiteralPath $candidateApi -PathType Leaf) -or
                -not (Test-Path -LiteralPath $candidateClasses -PathType Leaf) -or
                -not (Test-Path -LiteralPath $candidateLua -PathType Container) -or
                -not (Test-Path -LiteralPath $candidateScripts -PathType Container)) { continue }
        $candidateJarSha = (Get-FileHash -LiteralPath $candidateJar -Algorithm SHA256).Hash.ToLowerInvariant()
        $candidateTreeSha = Get-TreeDigest -Roots @($candidateLua, $candidateScripts)
        if ($candidateJarSha -eq $jarSha -and $candidateTreeSha -eq $vanillaTreeSha) {
            $snapshotTemp = $candidate.FullName
            Write-Host "Resuming verified game staging directory $snapshotTemp"
            break
        }
    }

    if (-not $snapshotTemp) {
        $snapshotTemp = Join-Path $generatedRoot (".staging-game-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $snapshotTemp -Force | Out-Null
        Write-Host "Creating game snapshot $snapshotId"
        Copy-SourceTree $luaRoot (Join-Path $snapshotTemp "raw\media\lua")
        Copy-SourceTree $scriptsRoot (Join-Path $snapshotTemp "raw\media\scripts")
        Copy-MediaMetadata $mediaRoot $mediaMetadataFiles (Join-Path $snapshotTemp "raw\media")
        New-Item -ItemType Directory -Path (Join-Path $snapshotTemp "raw\java"), (Join-Path $snapshotTemp "bytecode") -Force | Out-Null
        Copy-Item -LiteralPath $jarPath -Destination (Join-Path $snapshotTemp "raw\java\projectzomboid.jar") -Force
        Copy-Item -LiteralPath $appManifestPath -Destination (Join-Path $snapshotTemp "raw\appmanifest_380870.acf") -Force

        $snapshotJar = Join-Path $snapshotTemp "raw\java\projectzomboid.jar"
        $classInventoryPath = Join-Path $snapshotTemp "bytecode\java-classes.jsonl"
        $gameClasses = @(Write-ClassInventory $snapshotJar $classInventoryPath)
        if ($gameClasses.Count -lt 1000) { throw "Unexpectedly low game-owned class count: $($gameClasses.Count)" }
        Write-Host "Indexing bytecode API for $($gameClasses.Count) game classes"
        Write-JavaApi $gameClasses (Join-Path $SourceRoot "java\*") (Join-Path $snapshotTemp "bytecode\java-api.txt")
    } else {
        $snapshotJar = Join-Path $snapshotTemp "raw\java\projectzomboid.jar"
        $classInventoryPath = Join-Path $snapshotTemp "bytecode\java-classes.jsonl"
        $gameClasses = @(Get-Content -LiteralPath $classInventoryPath -Encoding UTF8 | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { return }
            $row = $_ | ConvertFrom-Json
            if ($row.gameOwned -eq $true) { [string]$row.name }
        })
    }

    $decompileRoot = Join-Path $snapshotTemp "java-decompiled"
    New-Item -ItemType Directory -Path $decompileRoot -Force | Out-Null
    Write-Host "Decompiling projectzomboid.jar with CFR 0.152 (heap ${CfrMaxHeapGB}GB)"
    $heapArgument = "-Xmx$($CfrMaxHeapGB)g"
    $cfrLog = & $javaExe $heapArgument -jar $CfrJar $snapshotJar --outputdir $decompileRoot `
        --silent true --showversion false --caseinsensitivefs true --clobber true 2>&1
    [IO.File]::WriteAllLines((Join-Path $snapshotTemp "cfr.log"), @($cfrLog), [Text.UTF8Encoding]::new($false))
    if ($LASTEXITCODE -ne 0) { throw "CFR failed with exit code $LASTEXITCODE" }
    $javaSourceCount = @(Get-ChildItem -LiteralPath $decompileRoot -Recurse -File -Filter '*.java').Count
    if ($javaSourceCount -lt 1000) { throw "CFR coverage too low: $javaSourceCount Java files" }

    $provenance = [ordered]@{
        schemaVersion = 1
        snapshotId = $snapshotId
        generatedAt = [DateTime]::UtcNow.ToString('o')
        sourceRoot = $SourceRoot
        appId = "380870"
        buildId = $buildId
        depotManifests = $depots
        jarSha256 = $jarSha
        vanillaTreeSha256 = $vanillaTreeSha
        mediaMetadataSha256 = $mediaMetadataSha
        mediaMetadataFileCount = $mediaMetadataFiles.Count
        cfrVersion = "0.152"
        javaClassCount = $gameClasses.Count
        javaSourceCount = $javaSourceCount
        evidencePolicy = "Bytecode signatures are authoritative; CFR output is reconstructed source for reading."
    }
    Write-JsonNoBom (Join-Path $snapshotTemp "provenance.json") $provenance
    & $nodeExe $nodeIndexer game $snapshotTemp
    if ($LASTEXITCODE -ne 0) { throw "Game index builder failed" }
    Move-Item -LiteralPath $snapshotTemp -Destination $snapshotPath
} else {
    Write-Host "Reusing immutable game snapshot $snapshotId"
    $snapshotProvenancePath = Join-Path $snapshotPath "provenance.json"
    $snapshotProvenance = Get-Content -LiteralPath $snapshotProvenancePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $metadataEnriched = $false
    if (-not $snapshotProvenance.PSObject.Properties['mediaMetadataSha256']) {
        Write-Host "Enriching initial snapshot with versioned text metadata"
        Copy-MediaMetadata $mediaRoot $mediaMetadataFiles (Join-Path $snapshotPath "raw\media")
        $snapshotProvenance | Add-Member -NotePropertyName mediaMetadataSha256 -NotePropertyValue $mediaMetadataSha
        $snapshotProvenance | Add-Member -NotePropertyName mediaMetadataFileCount -NotePropertyValue $mediaMetadataFiles.Count
        Write-JsonNoBom $snapshotProvenancePath $snapshotProvenance
        $metadataEnriched = $true
    } elseif ([string]$snapshotProvenance.mediaMetadataSha256 -ne $mediaMetadataSha) {
        throw "Immutable snapshot metadata differs inside the same Build. Use a clean candidate installation."
    }
    if ($RebuildIndexes -or $metadataEnriched) {
        Write-Host "Rebuilding derived game indexes"
        & $nodeExe $nodeIndexer game $snapshotPath
        if ($LASTEXITCODE -ne 0) { throw "Game index rebuild failed" }
    }
}

$current = [ordered]@{
    schemaVersion = 1
    updatedAt = [DateTime]::UtcNow.ToString('o')
    gameBuildId = $buildId
    gameSnapshotId = $snapshotId
    gameSnapshot = "generated/snapshots/$snapshotId"
    jarSha256 = $jarSha
}
$currentTemp = Join-Path $knowledgeRoot ("current-" + [guid]::NewGuid().ToString('N') + ".json")
Write-JsonNoBom $currentTemp $current
& $validator -CurrentPath $currentTemp
if ($LASTEXITCODE -ne 0) { throw "Knowledge-base validation failed" }
Move-Item -LiteralPath $currentTemp -Destination $currentPath -Force

if ($previousCurrent -and [string]$previousCurrent.gameSnapshotId -ne $snapshotId) {
    $compare = Join-Path $knowledgeRoot "Compare-PZSourceKnowledge.ps1"
    & $compare -PreviousGameSnapshot ([string]$previousCurrent.gameSnapshot)
    if ($LASTEXITCODE -ne 0) { throw "Knowledge-base comparison failed" }
}

Write-Host "Knowledge base ready"
Write-Host "Game snapshot: $snapshotId"
Write-Host "Current pointer: $currentPath"
