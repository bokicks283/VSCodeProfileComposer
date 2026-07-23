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
  capture-ui-state [profile] <file> Store only an opaque globalState seed locally.
  sync [profile] <export>           Sync a reviewed live export back into recipe sources.
  rename-profile <old> <new>        Safely rename a recipe and related repository sources.
  rename-component <old> <new>      Safely rename a component and recipe references.
  default show                      Show the configured shared default component.
  default set <component>           Set it and normalize every recipe.
  vscode <action>                   Inspect or guide management of live VS Code profiles.

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
            @'
capture-ui-state [<profile>] <private-export> [-CodeCommand <command>] [-DryRun]
  Validates an export and stores only its opaque globalState under ignored
  machine/local/ui-state/. When <profile> is omitted, the command reads
  `code --status` and accepts exactly one active VS Code profile whose name
  matches a repository recipe ID or display name. Zero or multiple matches fail.

Examples:
  ProfileComposer.ps1 capture-ui-state default C:\Private\Main.code-profile -DryRun
  ProfileComposer.ps1 capture-ui-state C:\Private\Python.code-profile -DryRun
'@ | Write-Host
        }
        'sync' {
            @'
sync [<profile>] <private-export> [-Platform <id>] [-VSCodeUserDataPath <path>]
     [-SkipGlobal] [-SkipUiState] [-DryRun]
  Transactionally syncs settings, extensions, keybindings, and opaque UI layout
  from a manually exported .code-profile into recipe-specific source deltas.
  When <profile> is omitted, the export name must match exactly one recipe ID
  or display name. Application settings explicitly listed by
  workbench.settings.applyToAllProfiles are synced from the selected VS Code
  User directory; Sync-ignored machine values are excluded.

  Flattened live resources are never guessed back into shared components.
  Review -DryRun output and the Git diff before committing.

Examples:
  ProfileComposer.ps1 sync C:\Private\Python.code-profile -Platform windows -DryRun
  ProfileComposer.ps1 sync python-database C:\Private\Adjusted.code-profile -Platform windows
  ProfileComposer.ps1 sync python C:\Private\Python.code-profile -SkipGlobal -SkipUiState -DryRun
'@ | Write-Host
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
        'vscode' {
            @'
vscode <action>
  Read-only discovery and supported/guided VS Code profile management.

Actions:
  list
      List live profile names and opaque location IDs without reading settings.
  open <live-profile> [workspace] [-CodeCommand <command>] [-DryRun]
      Open an existing profile through the supported `code --profile` option.
  import <recipe> [composition options]
      Compose a validated .code-profile and print the reviewed import steps.
  replace <recipe> -LiveProfile <name> [composition options]
      Verify the live target, compose its replacement, and print backup/import/delete steps.
  delete <live-profile> [-DryRun]
      Verify the target and print the supported Profiles: Delete Profile step.

Import/replace options:
  -Platform, -Machine, -MachineFile, -UiStateFromProfile, -UiStateProfile,
  -Strict, -DryRun, -RepositoryRoot, -VSCodeUserDataPath

The import, replace, and delete actions never edit VS Code's private profile
registry. Final creation/deletion remains a reviewed action in the Profiles editor.
'@ | Write-Host
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
        elseif ($change.PSObject.Properties.Name -contains 'path') { Write-Host "  $($change.action.ToUpperInvariant()) $($change.path)" }
        else { Write-Host "  UPDATE $($change.target)" }
    }
}

function Resolve-LiveVSCodeProfile {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$VSCodeUserDataPath
    )

    $profiles = @(Get-LiveVSCodeProfileDefinitions -VSCodeUserDataPath $VSCodeUserDataPath)
    $matches = @($profiles | Where-Object { $_.Name -ieq $Name })
    if ($matches.Count -eq 0) {
        throw "Live VS Code profile '$Name' was not found. Run 'ProfileComposer.ps1 vscode list'."
    }
    if ($matches.Count -gt 1) {
        throw "Live VS Code profile name '$Name' is ambiguous. Rename the duplicates in VS Code before continuing."
    }
    return $matches[0]
}

function Format-CommandArgument {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-VSCodeOpen {
    param([string[]]$Arguments)

    $parsed = Read-CommandOptions $Arguments @('DryRun') @('CodeCommand', 'VSCodeUserDataPath')
    if ($parsed.Options.Help) { Write-CommandHelp vscode; return }
    if ($parsed.Positionals.Count -lt 1 -or $parsed.Positionals.Count -gt 2) {
        throw 'vscode open requires <live-profile> and accepts one optional workspace path.'
    }
    $userDataPath = if ($parsed.Options.ContainsKey('vscodeuserdatapath')) { [string]$parsed.Options.vscodeuserdatapath } else { $null }
    $profile = Resolve-LiveVSCodeProfile -Name $parsed.Positionals[0] -VSCodeUserDataPath $userDataPath
    $codeCommand = if ($parsed.Options.ContainsKey('codecommand')) { [string]$parsed.Options.codecommand } else { 'code' }
    $workspace = $null
    if ($parsed.Positionals.Count -eq 2) {
        $workspace = [System.IO.Path]::GetFullPath($parsed.Positionals[1])
        if (-not (Test-Path -LiteralPath $workspace)) {
            throw "Workspace path '$workspace' does not exist."
        }
    }
    $commandArguments = @('--new-window', '--profile', $profile.Name)
    if ($workspace) { $commandArguments += $workspace }
    $displayCommand = (@($codeCommand) + $commandArguments | ForEach-Object { Format-CommandArgument ([string]$_) }) -join ' '
    if ($parsed.Options.dryrun) {
        Write-Host "DRY RUN: would open existing live profile '$($profile.Name)'."
        Write-Host "  $displayCommand"
        return
    }
    try {
        & $codeCommand @commandArguments
        $exitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    }
    catch {
        throw "Could not open VS Code through '$codeCommand': $($_.Exception.Message)"
    }
    if ($null -ne $exitCode -and $exitCode -ne 0) {
        throw "VS Code open command failed with exit code $exitCode."
    }
    Write-Host "Opened live VS Code profile '$($profile.Name)'."
}

function Invoke-VSCodeCompositionPreparation {
    param(
        [Parameter(Mandatory)][ValidateSet('import', 'replace')][string]$Action,
        [string[]]$Arguments
    )

    $parsed = Read-CommandOptions $Arguments @('DryRun', 'Strict') @(
        'Platform', 'Machine', 'MachineFile', 'UiStateFromProfile', 'UiStateProfile',
        'RepositoryRoot', 'LiveProfile', 'VSCodeUserDataPath'
    )
    if ($parsed.Options.Help) { Write-CommandHelp vscode; return }
    if ($parsed.Positionals.Count -ne 1) { throw "vscode $Action requires exactly one repository recipe ID." }
    if ($parsed.Options.ContainsKey('machine') -and $parsed.Options.ContainsKey('machinefile')) {
        throw '-Machine and -MachineFile cannot be used together.'
    }
    if ($parsed.Options.ContainsKey('uistatefromprofile') -and $parsed.Options.ContainsKey('uistateprofile')) {
        throw '-UiStateFromProfile and -UiStateProfile cannot be used together.'
    }
    if ($Action -eq 'import' -and $parsed.Options.ContainsKey('liveprofile')) {
        throw '-LiveProfile is valid only with vscode replace.'
    }
    if ($Action -eq 'replace' -and -not $parsed.Options.ContainsKey('liveprofile')) {
        throw 'vscode replace requires -LiveProfile <existing-name>.'
    }

    $root = Get-RepositoryRootFromOptions $parsed.Options
    $recipeId = $parsed.Positionals[0]
    $targetProfile = $null
    if ($Action -eq 'replace') {
        $userDataPath = if ($parsed.Options.ContainsKey('vscodeuserdatapath')) { [string]$parsed.Options.vscodeuserdatapath } else { $null }
        $targetProfile = Resolve-LiveVSCodeProfile -Name ([string]$parsed.Options.liveprofile) -VSCodeUserDataPath $userDataPath
        if ($targetProfile.IsDefault) {
            throw 'The built-in Default profile cannot be replaced. Compose application settings with compose-global instead.'
        }
    }

    $globalParameters = @{
        RepositoryRoot = $root
        DryRun = [bool]$parsed.Options.dryrun
        Strict = [bool]$parsed.Options.strict
    }
    $profileParameters = @{
        RepositoryRoot = $root
        Profile = $recipeId
        ExportCodeProfile = $true
        DryRun = [bool]$parsed.Options.dryrun
        Strict = [bool]$parsed.Options.strict
    }
    foreach ($key in @('machine', 'machinefile')) {
        if ($parsed.Options.ContainsKey($key)) {
            $globalParameters[$key] = $parsed.Options[$key]
            $profileParameters[$key] = $parsed.Options[$key]
        }
    }
    foreach ($key in @('platform', 'uistatefromprofile', 'uistateprofile')) {
        if ($parsed.Options.ContainsKey($key)) { $profileParameters[$key] = $parsed.Options[$key] }
    }

    Invoke-GlobalSettingsComposition @globalParameters | Out-Null
    $result = Invoke-ProfileComposition @profileParameters
    $exportPath = [System.IO.Path]::GetFullPath((Join-Path $root $result.codeProfileExportPath))
    if (-not $parsed.Options.dryrun) { Test-CodeProfileTemplate $exportPath | Out-Null }

    $verb = if ($parsed.Options.dryrun) { 'DRY RUN: would prepare' } else { 'Prepared' }
    Write-Host "$verb '$($result.displayName)' from recipe '$($result.profileId)' for VS Code $Action."
    Write-Host "  Export: $exportPath"
    if ($Action -eq 'import') {
        Write-Host '  Review required in VS Code:'
        Write-Host '    1. Run Profiles: Import Profile...'
        Write-Host "    2. Select the export above and review every resource."
        Write-Host '    3. Select Create to finish the import.'
    }
    else {
        Write-Host "  Live target: $($targetProfile.Name)"
        Write-Host '  Review required in VS Code:'
        Write-Host '    1. Export the existing live target as a private backup.'
        Write-Host '    2. Import the generated export and verify it in representative workspaces.'
        Write-Host '    3. Delete the old target with Profiles: Delete Profile only after verification.'
    }
    Write-Host '  No live VS Code profile or Settings Sync data was modified by this command.'
}

function Invoke-VSCodeCommand {
    param([string[]]$Arguments)

    if ($Arguments.Count -eq 0) { Write-CommandHelp vscode; return }
    $action = $Arguments[0].ToLowerInvariant()
    $remaining = @($Arguments | Select-Object -Skip 1)
    switch ($action) {
        { $_ -in @('-help', '--help', '-h', 'help') } { Write-CommandHelp vscode }
        'list' {
            $parsed = Read-CommandOptions $remaining @() @('VSCodeUserDataPath')
            if ($parsed.Options.Help) { Write-CommandHelp vscode; break }
            if ($parsed.Positionals.Count -gt 0) { throw 'vscode list does not accept positional arguments.' }
            $userDataPath = if ($parsed.Options.ContainsKey('vscodeuserdatapath')) { [string]$parsed.Options.vscodeuserdatapath } else { $null }
            Write-Host 'Live VS Code profiles (read-only metadata):'
            foreach ($profile in (Get-LiveVSCodeProfileDefinitions -VSCodeUserDataPath $userDataPath)) {
                $kind = if ($profile.IsDefault) { 'built-in' } else { "location $($profile.Id)" }
                Write-Host "  $($profile.Name) [$kind]"
            }
        }
        'open' { Invoke-VSCodeOpen $remaining }
        'import' { Invoke-VSCodeCompositionPreparation -Action import -Arguments $remaining }
        'replace' { Invoke-VSCodeCompositionPreparation -Action replace -Arguments $remaining }
        'delete' {
            $parsed = Read-CommandOptions $remaining @('DryRun') @('VSCodeUserDataPath')
            if ($parsed.Options.Help) { Write-CommandHelp vscode; break }
            if ($parsed.Positionals.Count -ne 1) { throw 'vscode delete requires exactly one live profile name.' }
            $userDataPath = if ($parsed.Options.ContainsKey('vscodeuserdatapath')) { [string]$parsed.Options.vscodeuserdatapath } else { $null }
            $profile = Resolve-LiveVSCodeProfile -Name $parsed.Positionals[0] -VSCodeUserDataPath $userDataPath
            if ($profile.IsDefault) { throw 'The built-in Default profile cannot be deleted.' }
            $prefix = if ($parsed.Options.dryrun) { 'DRY RUN: reviewed deletion target' } else { 'Reviewed deletion target' }
            Write-Host "$prefix '$($profile.Name)' [location $($profile.Id)]."
            Write-Host '  Export a private backup, then run Profiles: Delete Profile in VS Code and select this exact name.'
            Write-Host '  No live VS Code profile or Settings Sync data was modified by this command.'
        }
        default { throw "Unknown vscode action '$action'. Use 'ProfileComposer.ps1 help vscode'." }
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
            $parsed = Read-CommandOptions $CommandArguments @('DryRun') @('RepositoryRoot', 'CodeCommand')
            if ($parsed.Options.Help) { Write-CommandHelp capture-ui-state; break }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            if ($parsed.Positionals.Count -eq 2) {
                $profileId = $parsed.Positionals[0]
                $sourceProfileExport = $parsed.Positionals[1]
            }
            elseif ($parsed.Positionals.Count -eq 1) {
                $codeCommand = if ($parsed.Options.ContainsKey('codecommand')) { [string]$parsed.Options.codecommand } else { 'code' }
                $status = Get-VSCodeStatusText -CodeCommand $codeCommand
                $match = Resolve-ComposerProfileFromVSCodeStatus -RepositoryRoot $root -StatusText $status
                $profileId = $match.ProfileId
                $sourceProfileExport = $parsed.Positionals[0]
                Write-Host "Matched active VS Code profile '$($match.DisplayName)' to repository recipe '$profileId'."
            }
            else {
                throw 'capture-ui-state requires <source-profile-export> for automatic matching or <profile> <source-profile-export> explicitly.'
            }
            $result = Save-ProfileUiStateSeed $root $profileId $sourceProfileExport -DryRun:$parsed.Options.dryrun
            $verb = if ($result.dryRun) { 'DRY RUN: would store' } else { 'Stored' }
            Write-Host "$verb UI state for '$($result.profileId)' at $($result.outputPath). Only opaque globalState is retained."
        }
        'sync' {
            $parsed = Read-CommandOptions $CommandArguments @('DryRun', 'SkipGlobal', 'SkipUiState') @('Platform', 'RepositoryRoot', 'VSCodeUserDataPath')
            if ($parsed.Options.Help) { Write-CommandHelp sync; break }
            if ($parsed.Positionals.Count -lt 1 -or $parsed.Positionals.Count -gt 2) {
                throw 'sync requires <profile-export> for automatic matching or <profile> <profile-export> explicitly.'
            }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $parameters = @{
                RepositoryRoot = $root
                SourceProfileExport = $parsed.Positionals[-1]
                DryRun = [bool]$parsed.Options.dryrun
                SkipGlobal = [bool]$parsed.Options.skipglobal
                SkipUiState = [bool]$parsed.Options.skipuistate
            }
            if ($parsed.Positionals.Count -eq 2) { $parameters.Profile = $parsed.Positionals[0] }
            foreach ($key in @('platform', 'vscodeuserdatapath')) {
                if ($parsed.Options.ContainsKey($key)) { $parameters[$key] = $parsed.Options[$key] }
            }
            $result = Sync-ComposerProfileFromExport @parameters
            Write-Host "$(if ($result.dryRun) { 'DRY RUN: planned sync' } else { 'Synced' }) export '$($result.exportName)' to recipe '$($result.profileId)'."
            Write-ChangePlan $result
            Write-Host "  Settings: $($result.counts.settingReplacements) replacement(s), $($result.counts.settingRemovals) removal(s)"
            Write-Host "  Extensions: $($result.counts.extensionAdditions) addition(s), $($result.counts.extensionRemovals) removal(s)"
            Write-Host "  Keybindings: $($result.counts.keybindingAdditions) addition(s), $($result.counts.keybindingRemovals) removal(s), exact-order replacement=$($result.counts.keybindingsReplacedForOrder)"
            Write-Host "  Global: $($result.counts.globalSettings) tracked setting(s); $($result.counts.machineOwnedGlobalSettingsSkipped) Sync-ignored machine value(s) skipped"
            Write-Host "  Ownership filters: $($result.counts.exportGlobalSettingsIgnored) global/machine setting(s) and $($result.counts.platformSettingsIgnored) platform setting(s) excluded from recipe deltas"
            Write-Host "  UI state updated: $($result.uiStateUpdated)"
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
        'vscode' { Invoke-VSCodeCommand $CommandArguments }
        default { throw "Unknown command '$Command'. Run 'pwsh ./scripts/ProfileComposer.ps1 help' to list commands." }
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine("Profile Composer error: $($_.Exception.Message)")
    [Console]::Error.WriteLine("Run 'pwsh ./scripts/ProfileComposer.ps1 help $Command' for usage.")
    exit 1
}
