[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Profile,

    [Parameter(Mandatory)]
    [string]$SourceProfileExport,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $PSScriptRoot 'ProfileComposer.psm1') -Force

try {
    $result = Save-ProfileUiStateSeed -RepositoryRoot $repositoryRoot -Profile $Profile -SourceProfileExport $SourceProfileExport -DryRun:$DryRun
    $prefix = if ($DryRun) { 'DRY RUN: would store' } else { 'Stored' }
    Write-Host "$prefix UI state for profile '$($result.profileId)' at $($result.outputPath)."
    Write-Host 'Only the opaque globalState resource was retained; settings, extensions, keybindings, profile name, and source path were not copied.'
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
