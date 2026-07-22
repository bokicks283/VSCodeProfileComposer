[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$CommandArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:DefaultRepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $PSScriptRoot 'ProfileComposer.psm1') -Force

function Write-GeneralHelp {
    @'
VS Code Profile Composer

Usage:
  pwsh ./scripts/ProfileComposer.ps1 <command> [arguments] [options]

Commands:
  help [command]                    Show general or command-specific help.
  validate                          Validate repository sources and ownership.
  compose <profile>                 Compose one named profile and application settings.
  compose-all                       Compose every profile and application settings.
  compose-global                    Compose built-in Default/application settings only.
  list-profiles                     List recipe IDs, names, and ordered components.
  list-machines                     List ignored named machine overlays.
  capture-ui-state <profile> <file> Store only an opaque globalState seed locally.
  rename-profile <old> <new>        Safely rename a recipe and related repository sources.
  rename-component <old> <new>      Safely rename a component and recipe references.
  default show                      Show the configured shared default component.
  default set <component>           Set it and normalize every recipe.

Aliases:
  list profiles | list machines
  rename profile <old> <new> | rename component <old> <new>

Use "help <command>" or "<command> -Help" for options and examples.
'@ | Write-Host
}

function Write-CommandHelp {
    param([Parameter(Mandatory)][string]$Name)
    switch ($Name.ToLowerInvariant()) {
        'validate' {
            @'
validate
  Validates configuration, shared-default ownership, recipes, components,
  global/application settings, platform overlays, and optional machine selection.

Usage:
  ProfileComposer.ps1 validate [-Platform <id>] [-Machine <id> | -MachineFile <path>] [-Strict]

Example:
  pwsh ./scripts/ProfileComposer.ps1 validate -Platform windows -Strict
'@ | Write-Host
        }
        'compose' {
            @'
compose <profile>
  Generates built-in Default/application settings and one portable named profile.

Options:
  -Platform <id>              Apply a committed platform overlay.
  -Machine <id>               Apply ignored machine/local/<id>.jsonc to application settings.
  -MachineFile <path>         Backward-compatible explicit machine overlay path.
  -ExportCodeProfile          Also create an importable .code-profile artifact.
  -UiStateProfile <id>        Reuse a stored local opaque UI-state seed.
  -UiStateFromProfile <path>  Copy globalState from an explicit private export.
  -DryRun                     Validate and print planned output without writing build/.
  -Strict                     Treat warnings as errors.

Example:
  pwsh ./scripts/ProfileComposer.ps1 compose python-database -Platform windows -ExportCodeProfile -DryRun
'@ | Write-Host
        }
        'compose-all' {
            Write-Host 'compose-all: same options as compose, but generates every recipe. Example: ProfileComposer.ps1 compose-all -Platform windows -ExportCodeProfile -DryRun'
        }
        'compose-global' {
            Write-Host 'compose-global: generates only build/global. Options: -Machine, -MachineFile, -DryRun, -Strict. Example: ProfileComposer.ps1 compose-global -DryRun'
        }
        'list-profiles' { Write-Host 'list-profiles: lists profile recipe IDs, display names, and ordered components. Example: ProfileComposer.ps1 list-profiles' }
        'list-machines' { Write-Host 'list-machines: lists ignored machine/local/*.jsonc definitions without reading values. Example: ProfileComposer.ps1 list-machines' }
        'capture-ui-state' {
            Write-Host 'capture-ui-state <profile> <private-export> [-DryRun]: validates an export and stores only its opaque globalState under ignored machine/local/ui-state/. Example: ProfileComposer.ps1 capture-ui-state default C:\Private\Main.code-profile -DryRun'
        }
        'rename-profile' {
            Write-Host 'rename-profile <old-id> <new-id> [-DryRun]: transactionally renames the recipe, optional profile override, and stored local UI-state seed. It never touches live VS Code profiles. Example: ProfileComposer.ps1 rename-profile old-id new-id -DryRun'
        }
        'rename-component' {
            Write-Host 'rename-component <old-id> <new-id> [-DryRun]: transactionally renames the component, updates ordered recipe references, and updates composer.jsonc when needed. Example: ProfileComposer.ps1 rename-component old new -DryRun'
        }
        'default' {
            Write-Host 'default show | default set <component> [-DryRun]: reads or transactionally changes shared-default ownership. Setting it places the component first in every recipe without duplicates. Example: ProfileComposer.ps1 default set default -DryRun'
        }
        default { throw "Unknown help topic '$Name'. Run 'ProfileComposer.ps1 help' to list commands." }
    }
}

function ConvertTo-NormalizedOptionName {
    param([Parameter(Mandatory)][string]$Value)
    return $Value.TrimStart('-').Replace('-', '').ToLowerInvariant()
}

function Read-CommandOptions {
    param(
        [string[]]$Arguments,
        [string[]]$SwitchNames = @(),
        [string[]]$ValueNames = @()
    )
    $switchSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $valueSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $SwitchNames) { $switchSet.Add((ConvertTo-NormalizedOptionName $name)) | Out-Null }
    foreach ($name in $ValueNames) { $valueSet.Add((ConvertTo-NormalizedOptionName $name)) | Out-Null }
    $options = @{ Help = $false }
    foreach ($name in $SwitchNames) { $options[(ConvertTo-NormalizedOptionName $name)] = $false }
    $positionals = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]
        if (-not $argument.StartsWith('-')) {
            $positionals.Add($argument)
            continue
        }
        $name = ConvertTo-NormalizedOptionName $argument
        if ($name -eq 'help' -or $name -eq 'h') { $options.Help = $true; continue }
        if ($switchSet.Contains($name)) { $options[$name] = $true; continue }
        if ($valueSet.Contains($name)) {
            if ($index + 1 -ge $Arguments.Count -or $Arguments[$index + 1].StartsWith('-')) {
                throw "Option '$argument' requires a value."
            }
            $index++
            $options[$name] = $Arguments[$index]
            continue
        }
        throw "Unknown option '$argument'. Use '$Command -Help' for supported options."
    }
    return [pscustomobject]@{ Options = $options; Positionals = [string[]]$positionals.ToArray() }
}

function Get-RepositoryRootFromOptions {
    param([hashtable]$Options)
    if ($Options.ContainsKey('repositoryroot')) { return [System.IO.Path]::GetFullPath([string]$Options.repositoryroot) }
    return $script:DefaultRepositoryRoot
}

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

function Write-ChangePlan {
    param([Parameter(Mandatory)]$Result)
    $prefix = if ($Result.dryRun) { 'DRY RUN: planned changes' } else { 'Applied changes' }
    Write-Host "$prefix ($($Result.changes.Count)):"
    if ($Result.changes.Count -eq 0) { Write-Host '  No source changes required.'; return }
    foreach ($change in $Result.changes) {
        if ($change.action -eq 'move') { Write-Host "  MOVE $($change.source) -> $($change.target)" }
        else { Write-Host "  UPDATE $($change.target)" }
    }
}

function Invoke-Compose {
    param([bool]$AllProfiles, [string[]]$Arguments)
    $parsed = Read-CommandOptions $Arguments @('DryRun', 'Strict', 'ExportCodeProfile') @('Platform', 'Machine', 'MachineFile', 'UiStateFromProfile', 'UiStateProfile', 'RepositoryRoot')
    if ($parsed.Options.Help) { Write-CommandHelp $(if ($AllProfiles) { 'compose-all' } else { 'compose' }); return }
    if ($AllProfiles -and $parsed.Positionals.Count -ne 0) { throw 'compose-all does not accept a profile ID.' }
    if (-not $AllProfiles -and $parsed.Positionals.Count -ne 1) { throw 'compose requires exactly one profile ID. Example: ProfileComposer.ps1 compose default -Platform windows' }
    $root = Get-RepositoryRootFromOptions $parsed.Options
    if ($parsed.Options.ContainsKey('machine') -and $parsed.Options.ContainsKey('machinefile')) { throw '-Machine and -MachineFile cannot be used together.' }
    if (($parsed.Options.ContainsKey('uistatefromprofile') -or $parsed.Options.ContainsKey('uistateprofile')) -and -not $parsed.Options.exportcodeprofile) { throw 'UI-state seeding requires -ExportCodeProfile.' }
    if ($parsed.Options.ContainsKey('uistatefromprofile') -and $parsed.Options.ContainsKey('uistateprofile')) { throw '-UiStateFromProfile and -UiStateProfile cannot be used together.' }
    $validationParameters = @{ RepositoryRoot = $root }
    foreach ($key in @('platform', 'machine', 'machinefile')) { if ($parsed.Options.ContainsKey($key)) { $validationParameters[$key] = $parsed.Options[$key] } }
    $validation = Test-ComposerRepository @validationParameters
    if ($validation.errors.Count -gt 0 -or ($parsed.Options.strict -and $validation.warnings.Count -gt 0)) {
        Write-ValidationSummary $validation
        throw 'Composition stopped because repository preflight validation failed.'
    }
    $globalParameters = @{ RepositoryRoot = $root; DryRun = [bool]$parsed.Options.dryrun; Strict = [bool]$parsed.Options.strict }
    foreach ($key in @('machine', 'machinefile')) { if ($parsed.Options.ContainsKey($key)) { $globalParameters[$key] = $parsed.Options[$key] } }
    $globalResult = Invoke-GlobalSettingsComposition @globalParameters
    $globalVerb = if ($parsed.Options.dryrun) { 'DRY RUN: planned' } else { 'Generated' }
    Write-Host "$globalVerb built-in Default settings at $($globalResult.outputDirectory)."
    $profileIds = if ($AllProfiles) { @(Get-ProfileDefinitions $root | ForEach-Object Id) } else { @($parsed.Positionals[0]) }
    foreach ($profileId in $profileIds) {
        $parameters = @{
            RepositoryRoot = $root
            Profile = $profileId
            DryRun = [bool]$parsed.Options.dryrun
            Strict = [bool]$parsed.Options.strict
            ExportCodeProfile = [bool]$parsed.Options.exportcodeprofile
        }
        foreach ($key in @('platform', 'machine', 'machinefile', 'uistatefromprofile', 'uistateprofile')) {
            if ($parsed.Options.ContainsKey($key)) { $parameters[$key] = $parsed.Options[$key] }
        }
        $result = Invoke-ProfileComposition @parameters
        $verb = if ($result.dryRun) { 'DRY RUN: planned' } else { 'Composed' }
        Write-Host "$verb '$($result.profileId)' at $($result.outputDirectory): $($result.counts.settings) settings, $($result.counts.extensions) extensions, $($result.counts.keybindings) keybindings."
        if ($result.codeProfileExportPath) { Write-Host "  VS Code profile export: $($result.codeProfileExportPath)" }
    }
}

try {
    $normalizedCommand = $Command.ToLowerInvariant()
    if ($normalizedCommand -in @('-help', '--help', '-h')) { $normalizedCommand = 'help' }
    switch ($normalizedCommand) {
        'help' {
            if ($CommandArguments.Count -eq 0) { Write-GeneralHelp }
            elseif ($CommandArguments.Count -eq 1) { Write-CommandHelp $CommandArguments[0] }
            else { throw 'help accepts at most one command name.' }
        }
        'validate' {
            $parsed = Read-CommandOptions $CommandArguments @('Strict') @('Platform', 'Machine', 'MachineFile', 'RepositoryRoot')
            if ($parsed.Options.Help) { Write-CommandHelp validate; break }
            if ($parsed.Positionals.Count -gt 0) { throw 'validate does not accept positional arguments.' }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $parameters = @{ RepositoryRoot = $root }
            foreach ($key in @('platform', 'machine', 'machinefile')) { if ($parsed.Options.ContainsKey($key)) { $parameters[$key] = $parsed.Options[$key] } }
            $result = Test-ComposerRepository @parameters
            Write-ValidationSummary $result
            if ($result.errors.Count -gt 0 -or ($parsed.Options.strict -and $result.warnings.Count -gt 0)) { exit 1 }
        }
        'compose' { Invoke-Compose $false $CommandArguments }
        'compose-all' { Invoke-Compose $true $CommandArguments }
        'compose-global' {
            $parsed = Read-CommandOptions $CommandArguments @('DryRun', 'Strict') @('Machine', 'MachineFile', 'RepositoryRoot')
            if ($parsed.Options.Help) { Write-CommandHelp compose-global; break }
            if ($parsed.Positionals.Count -gt 0) { throw 'compose-global does not accept positional arguments.' }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $parameters = @{ RepositoryRoot = $root; DryRun = [bool]$parsed.Options.dryrun; Strict = [bool]$parsed.Options.strict }
            foreach ($key in @('machine', 'machinefile')) { if ($parsed.Options.ContainsKey($key)) { $parameters[$key] = $parsed.Options[$key] } }
            $result = Invoke-GlobalSettingsComposition @parameters
            $verb = if ($result.dryRun) { 'DRY RUN: planned' } else { 'Generated' }
            Write-Host "$verb built-in Default settings at $($result.outputDirectory): $($result.settingCount) settings."
        }
        { $_ -in @('list-profiles', 'list-machines', 'list') } {
            $kind = if ($normalizedCommand -eq 'list') {
                if ($CommandArguments.Count -lt 1) { throw "list requires 'profiles' or 'machines'." }
                $first = $CommandArguments[0].ToLowerInvariant()
                $CommandArguments = @($CommandArguments | Select-Object -Skip 1)
                $first
            } elseif ($normalizedCommand -eq 'list-profiles') { 'profiles' } else { 'machines' }
            $parsed = Read-CommandOptions $CommandArguments @() @('RepositoryRoot')
            if ($parsed.Options.Help) { Write-CommandHelp "list-$kind"; break }
            if ($parsed.Positionals.Count -gt 0) { throw "list $kind does not accept positional arguments." }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            if ($kind -eq 'profiles') {
                Write-Host 'Profiles:'
                foreach ($definition in Get-ProfileDefinitions $root) {
                    $recipe = Read-ProfileRecipe $definition.Path
                    Write-Host "  $($definition.Id): $($recipe.Name) [$($recipe.Components -join ', ')]"
                }
            } elseif ($kind -eq 'machines') {
                $machines = @(Get-MachineDefinitions $root)
                if ($machines.Count -eq 0) { Write-Host 'No named machine overlays found under machine/local/.' }
                else { Write-Host 'Named machine overlays:'; foreach ($item in $machines) { Write-Host "  $($item.Id): machine/local/$($item.Id).jsonc" } }
            } else { throw "Unknown list target '$kind'. Use 'profiles' or 'machines'." }
        }
        'capture-ui-state' {
            $parsed = Read-CommandOptions $CommandArguments @('DryRun') @('RepositoryRoot')
            if ($parsed.Options.Help) { Write-CommandHelp capture-ui-state; break }
            if ($parsed.Positionals.Count -ne 2) { throw 'capture-ui-state requires <profile> <source-profile-export>.' }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $result = Save-ProfileUiStateSeed $root $parsed.Positionals[0] $parsed.Positionals[1] -DryRun:$parsed.Options.dryrun
            $verb = if ($result.dryRun) { 'DRY RUN: would store' } else { 'Stored' }
            Write-Host "$verb UI state for '$($result.profileId)' at $($result.outputPath). Only opaque globalState is retained."
        }
        { $_ -in @('rename-profile', 'rename-component', 'rename') } {
            if ($normalizedCommand -eq 'rename') {
                if ($CommandArguments.Count -lt 1) { throw "rename requires 'profile' or 'component'." }
                $kind = $CommandArguments[0].ToLowerInvariant()
                $CommandArguments = @($CommandArguments | Select-Object -Skip 1)
            } else { $kind = $normalizedCommand.Substring('rename-'.Length) }
            $parsed = Read-CommandOptions $CommandArguments @('DryRun') @('RepositoryRoot')
            if ($parsed.Options.Help) { Write-CommandHelp "rename-$kind"; break }
            if ($parsed.Positionals.Count -ne 2) { throw "rename-$kind requires <old-id> <new-id>." }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            if ($kind -eq 'profile') { $result = Rename-ComposerProfile $root $parsed.Positionals[0] $parsed.Positionals[1] -DryRun:$parsed.Options.dryrun }
            elseif ($kind -eq 'component') { $result = Rename-ComposerComponent $root $parsed.Positionals[0] $parsed.Positionals[1] -DryRun:$parsed.Options.dryrun }
            else { throw "Unknown rename target '$kind'. Use 'profile' or 'component'." }
            Write-ChangePlan $result
        }
        'default' {
            $parsed = Read-CommandOptions $CommandArguments @('DryRun') @('RepositoryRoot')
            if ($parsed.Options.Help -or $parsed.Positionals.Count -eq 0) { Write-CommandHelp default; break }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $verb = $parsed.Positionals[0].ToLowerInvariant()
            if ($verb -eq 'show' -and $parsed.Positionals.Count -eq 1) { Write-Host "Shared default component: $(Get-SharedDefaultComponent $root)" }
            elseif ($verb -eq 'set' -and $parsed.Positionals.Count -eq 2) {
                $result = Set-SharedDefaultComponent $root $parsed.Positionals[1] -DryRun:$parsed.Options.dryrun
                Write-ChangePlan $result
            }
            else { throw "default requires 'show' or 'set <component>'." }
        }
        default { throw "Unknown command '$Command'. Run 'pwsh ./scripts/ProfileComposer.ps1 help' to list commands." }
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine("Profile Composer error: $($_.Exception.Message)")
    [Console]::Error.WriteLine("Run 'pwsh ./scripts/ProfileComposer.ps1 help $Command' for usage.")
    exit 1
}
