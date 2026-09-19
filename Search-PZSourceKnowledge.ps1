[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Query,
    [ValidateSet("all", "game")][string]$Scope = "all",
    [ValidateRange(1, 100)][int]$Limit = 20
)

$ErrorActionPreference = "Stop"
$search = Join-Path $PSScriptRoot "src\search-knowledge.mjs"
& node $search $PSScriptRoot $Query $Scope $Limit
if ($LASTEXITCODE -ne 0) { throw "Knowledge-base search failed" }
