[CmdletBinding()]
param(
    [string]$CurrentPath = (Join-Path $PSScriptRoot "current.json")
)

$ErrorActionPreference = "Stop"
$validator = Join-Path $PSScriptRoot "src\validate-knowledge.mjs"
& node $validator $PSScriptRoot $CurrentPath
if ($LASTEXITCODE -ne 0) { throw "Knowledge-base validation failed" }
