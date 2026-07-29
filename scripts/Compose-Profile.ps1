[CmdletBinding(DefaultParameterSetName = 'One')]
param(
    [Parameter(Mandatory, ParameterSetName = 'One')]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Profile,

    [Parameter(Mandatory, ParameterSetName = 'All')]
    [switch]$All,

    [Parameter(Mandatory, ParameterSetName = 'Validate')]
    [switch]$Validate,

    [Parameter(Mandatory, ParameterSetName = 'Global')]
    [switch]$Global,

    [Parameter(Mandatory, ParameterSetName = 'ListMachines')]
    [switch]$ListMachines,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [Parameter(ParameterSetName = 'Validate')]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Platform,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [Parameter(ParameterSetName = 'Validate')]
    [Parameter(ParameterSetName = 'Global')]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Machine,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [Parameter(ParameterSetName = 'Validate')]
    [Parameter(ParameterSetName = 'Global')]
    [string]$MachineFile,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [Parameter(ParameterSetName = 'Global')]
    [switch]$DryRun,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [string]$UiStateFromProfile,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$UiStateProfile,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [switch]$NoUiState,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [Parameter(ParameterSetName = 'Validate')]
    [Parameter(ParameterSetName = 'Global')]
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
    if ($UiStateFromProfile -and $UiStateProfile) { throw '-UiStateFromProfile and -UiStateProfile cannot be used together.' }
    if ($NoUiState -and ($UiStateFromProfile -or $UiStateProfile)) { throw '-NoUiState cannot be combined with an explicit UI-state source.' }
    if ($Machine -and $MachineFile) { throw '-Machine and -MachineFile cannot be used together.' }

    if ($ListMachines) {
        $machines = @(Get-MachineDefinitions -RepositoryRoot $repositoryRoot)
        if ($machines.Count -eq 0) {
            Write-Host 'No named machine overlays found under machine/local/.'
        }
        else {
            Write-Host 'Named machine overlays:'
            foreach ($item in $machines) {
                Write-Host "  $($item.Id): machine/local/$($item.Id).jsonc"
            }
        }
        exit 0
    }

    if ($Validate) {
        $result = Test-ComposerRepository -RepositoryRoot $repositoryRoot -Platform $Platform -Machine $Machine -MachineFile $MachineFile
        Write-ValidationSummary $result
        if ($result.errors.Count -gt 0 -or ($Strict -and $result.warnings.Count -gt 0)) { exit 1 }
        exit 0
    }

    if ($Global) {
        $globalParameters = @{ RepositoryRoot = $repositoryRoot; DryRun = $DryRun; Strict = $Strict }
        if ($Machine) { $globalParameters.Machine = $Machine }
        if ($MachineFile) { $globalParameters.MachineFile = $MachineFile }
        $globalResult = Invoke-GlobalSettingsComposition @globalParameters
        $prefix = if ($DryRun) { 'DRY RUN: planned' } else { 'Generated' }
        Write-Host "$prefix application settings: $($globalResult.settingsPath)"
        if ($globalResult.machineId) { Write-Host "  Machine '$($globalResult.machineId)': $($globalResult.machineSettingCount) local setting(s), ignored by Settings Sync." }
        exit 0
    }

    $preflight = Test-ComposerRepository -RepositoryRoot $repositoryRoot -Platform $Platform -Machine $Machine -MachineFile $MachineFile
    if ($preflight.errors.Count -gt 0 -or ($Strict -and $preflight.warnings.Count -gt 0)) {
        Write-ValidationSummary $preflight
        throw 'Composition stopped because repository preflight validation failed.'
    }
    $globalParameters = @{ RepositoryRoot = $repositoryRoot; DryRun = $DryRun; Strict = $Strict }
    if ($Machine) { $globalParameters.Machine = $Machine }
    if ($MachineFile) { $globalParameters.MachineFile = $MachineFile }
    $globalResult = Invoke-GlobalSettingsComposition @globalParameters
    $globalPrefix = if ($DryRun) { 'DRY RUN: planned' } else { 'Generated' }
    Write-Host "$globalPrefix application settings: $($globalResult.settingsPath)"
    if ($globalResult.machineId) { Write-Host "  Machine '$($globalResult.machineId)': $($globalResult.machineSettingCount) local setting(s), ignored by Settings Sync." }

    $profiles = if ($All) {
        @(Get-ProfileDefinitions -RepositoryRoot $repositoryRoot | ForEach-Object Id)
    }
    else { @($Profile) }

    foreach ($profileId in $profiles) {
        $parameters = @{
            RepositoryRoot = $repositoryRoot
            Profile = $profileId
            DryRun = $DryRun
            NoUiState = $NoUiState
            Strict = $Strict
        }
        if ($Platform) { $parameters.Platform = $Platform }
        if ($Machine) { $parameters.Machine = $Machine }
        if ($MachineFile) { $parameters.MachineFile = $MachineFile }
        if ($UiStateFromProfile) { $parameters.UiStateFromProfile = $UiStateFromProfile }
        if ($UiStateProfile) { $parameters.UiStateProfile = $UiStateProfile }
        $result = Invoke-ProfileComposition @parameters
        if ($DryRun) {
            Write-Host "DRY RUN '$($result.profileId)': $($result.codeProfileExportPath)"
            if ($result.uiStateSeeded) {
                Write-Host "  UI state seed: $($result.uiStateSource)"
            }
            if ($result.machineId) { Write-Host "  Machine: $($result.machineId) (delivered through built-in Default settings, not this named profile)" }
        }
        else {
            $uiLabel = if ($result.uiStateSeeded) { " [UI: $($result.uiStateSource)]" }
                elseif ($result.uiStateSource -like 'configured-default-missing:*') { " [UI seed unavailable: $($result.uiStateSource.Split(':', 2)[1])]" }
                else { '' }
            Write-Host "Composed '$($result.profileId)': $($result.codeProfileExportPath)$uiLabel"
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
