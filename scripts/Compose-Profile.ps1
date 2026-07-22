[CmdletBinding(DefaultParameterSetName = 'One')]
param(
    [Parameter(Mandatory, ParameterSetName = 'One')]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Profile,

    [Parameter(Mandatory, ParameterSetName = 'All')]
    [switch]$All,

    [Parameter(Mandatory, ParameterSetName = 'Validate')]
    [switch]$Validate,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [Parameter(ParameterSetName = 'Validate')]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Platform,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [Parameter(ParameterSetName = 'Validate')]
    [string]$MachineFile,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [switch]$DryRun,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [switch]$ExportCodeProfile,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [string]$UiStateFromProfile,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [Parameter(ParameterSetName = 'Validate')]
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $PSScriptRoot 'ProfileComposer.psm1') -Force

function Write-ValidationSummary {
    param([Parameter(Mandatory)]$Result)
    Write-Host "Validation: $($Result.errors.Count) error(s), $($Result.warnings.Count) warning(s), $($Result.information.Count) informational notice(s)."
    foreach ($level in @('errors', 'warnings', 'information')) {
        foreach ($item in $Result.$level) {
            $source = if ($item.PSObject.Properties.Name -contains 'source') { " [$($item.source)]" } else { '' }
            $path = if ($item.PSObject.Properties.Name -contains 'path') { " $($item.path)" } else { '' }
            Write-Host "  $($level.ToUpperInvariant()): $($item.code)$source$path - $($item.message)"
        }
    }
}

try {
    if ($UiStateFromProfile -and -not $ExportCodeProfile) {
        throw '-UiStateFromProfile requires -ExportCodeProfile.'
    }

    if ($Validate) {
        $result = Test-ComposerRepository -RepositoryRoot $repositoryRoot -Platform $Platform -MachineFile $MachineFile
        Write-ValidationSummary $result
        if ($result.errors.Count -gt 0 -or ($Strict -and $result.warnings.Count -gt 0)) { exit 1 }
        exit 0
    }

    $profiles = if ($All) {
        @(Get-ProfileDefinitions -RepositoryRoot $repositoryRoot | ForEach-Object Id)
    }
    else { @($Profile) }

    foreach ($profileId in $profiles) {
        $parameters = @{
            RepositoryRoot = $repositoryRoot
            Profile = $profileId
            DryRun = $DryRun
            Strict = $Strict
            ExportCodeProfile = $ExportCodeProfile
        }
        if ($Platform) { $parameters.Platform = $Platform }
        if ($MachineFile) { $parameters.MachineFile = $MachineFile }
        if ($UiStateFromProfile) { $parameters.UiStateFromProfile = $UiStateFromProfile }
        $result = Invoke-ProfileComposition @parameters
        if ($DryRun) {
            Write-Host "DRY RUN: $($result.profileId) ($($result.displayName))"
            Write-Host "  Planned output: $($result.outputDirectory)"
            if ($result.codeProfileExportPath) { Write-Host "  Planned .code-profile: $($result.codeProfileExportPath)" }
            if ($result.uiStateSeeded) { Write-Host '  UI state seed: copied from the explicitly supplied profile export' }
            Write-Host "  Inputs:"
            foreach ($input in $result.inputFiles) { Write-Host "    $($input.type): $($input.path)" }
            Write-Host "  Counts: $($result.counts.settings) settings, $($result.counts.extensions) extensions, $($result.counts.keybindings) keybindings, $($result.counts.overrides) overrides, $($result.counts.warnings) warnings"
        }
        else {
            Write-Host "Composed '$($result.profileId)' at $($result.outputDirectory): $($result.counts.settings) settings, $($result.counts.extensions) extensions, $($result.counts.keybindings) keybindings, $($result.counts.overrides) overrides."
            if ($result.codeProfileExportPath) { Write-Host "VS Code profile export: $($result.codeProfileExportPath)" }
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
