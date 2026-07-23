<#
.SYNOPSIS
Validates CLI help and repository Markdown without opening external tools.

.DESCRIPTION
Checks internal Markdown links, required command/help coverage, sync parameter
documentation, router schema validity, current command names, and prohibited
legacy sync claims. The command is deterministic, terminal-only, and exits
nonzero on drift.

.EXAMPLE
pwsh -NoProfile -NonInteractive -File ./scripts/Test-Documentation.ps1
#>

[CmdletBinding()]
param(
    [string]$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RepositoryRoot)
$cli = Join-Path $root 'scripts/ProfileComposer.ps1'
$errors = [System.Collections.Generic.List[string]]::new()

function Add-DocError {
    param([Parameter(Mandatory)][string]$Message)
    $script:errors.Add($Message)
}

$markdownFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.md' |
    Where-Object { $_.FullName -notmatch '[\\/](build|migration-backups)[\\/]' })

foreach ($file in $markdownFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    foreach ($match in [regex]::Matches($content, '\[[^\]]+\]\(([^)]+)\)')) {
        $target = $match.Groups[1].Value
        if ($target -match '^(?i:https?://|mailto:|#)') { continue }
        $targetPath = ($target -split '#', 2)[0]
        if ([string]::IsNullOrWhiteSpace($targetPath)) { continue }
        $decoded = [uri]::UnescapeDataString($targetPath)
        $resolved = [System.IO.Path]::GetFullPath((Join-Path $file.DirectoryName $decoded))
        if (-not (Test-Path -LiteralPath $resolved)) {
            Add-DocError "Broken link in $($file.FullName): $target"
        }
    }
}

$helpTopics = @(
    'sync',
    'route',
    'route list',
    'route show',
    'route explain',
    'route audit',
    'route add-setting',
    'route add-extension',
    'route add-prefix',
    'route add-publisher',
    'route remove',
    'route enable',
    'route disable',
    'route import',
    'migrate'
)
foreach ($topic in $helpTopics) {
    $arguments = @('help') + ($topic -split ' ')
    $output = @(& pwsh -NoProfile -NonInteractive -File $cli @arguments 2>&1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output -join "`n"))) {
        Add-DocError "Help topic '$topic' is missing or failed."
    }
}

$syncHelp = @(& pwsh -NoProfile -NonInteractive -File $cli help sync 2>&1) -join "`n"
$routerDoc = [System.IO.File]::ReadAllText((Join-Path $root 'docs/OWNERSHIP-ROUTER.md'))
foreach ($parameter in @(
    '-Platform', '-Machine', '-RoutingFile', '-RoutingMode', '-NonInteractive',
    '-WriteUnresolved', '-SkipGlobal', '-SkipUiState', '-PersistDryRunDecisions',
    '-DryRun'
)) {
    if ($syncHelp -notmatch [regex]::Escape($parameter)) { Add-DocError "sync help omits $parameter." }
    if ($routerDoc -notmatch [regex]::Escape($parameter)) { Add-DocError "ownership router documentation omits $parameter." }
}
foreach ($mode in @('Supplement', 'Override', 'Isolated')) {
    if ($syncHelp -notmatch $mode -or $routerDoc -notmatch $mode) {
        Add-DocError "Routing mode '$mode' is not synchronized between help and docs."
    }
}
foreach ($command in @(
    'route list', 'route show', 'route explain', 'route audit', 'route add-setting',
    'route add-extension', 'route add-prefix', 'route add-publisher', 'route remove',
    'route enable', 'route disable', 'route import', 'migrate legacy-sync'
)) {
    if ($routerDoc -notmatch [regex]::Escape($command)) { Add-DocError "Command reference omits '$command'." }
}

$allCurrentDocs = @($markdownFiles | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
foreach ($obsolete in @(
    'writes only recipe-specific deltas',
    'remaining flattened settings continue to become recipe-specific deltas',
    'Portable differences become exact recipe replacements'
)) {
    if ($allCurrentDocs -match [regex]::Escape($obsolete)) {
        Add-DocError "Current documentation retains obsolete sync claim: $obsolete"
    }
}

Import-Module (Join-Path $root 'scripts/ProfileComposer.psm1') -Force -DisableNameChecking
$audit = Invoke-OwnershipRouterAudit -RepositoryRoot $root -Platform windows
if ($audit.errors.Count -gt 0) {
    foreach ($item in $audit.errors) { Add-DocError "Router schema example/configuration error: $($item.message)" }
}

if ($errors.Count -gt 0) {
    foreach ($item in $errors) { [Console]::Error.WriteLine("DOC ERROR: $item") }
    [Console]::Error.WriteLine("Documentation validation failed with $($errors.Count) error(s).")
    exit 1
}

Write-Host "Documentation validation passed: $($markdownFiles.Count) Markdown file(s), $($helpTopics.Count) help topic(s), router schema, links, commands, parameters, and modes."
exit 0
