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
Import-Module (Join-Path $PSScriptRoot 'ProfileComposer.psm1') -Force -DisableNameChecking

function Write-GeneralHelp {
    @'
VS Code Profile Composer

Usage:
  pwsh ./scripts/ProfileComposer.ps1 <command> [arguments] [options]

Commands:
  help [command]                    Show general or command-specific help.
  validate                          Validate repository sources and ownership.
  fix global                       Repair mechanically safe global ownership issues.
  compose <profile>                 Compose one named profile and application settings.
  compose-all                       Compose every profile and application settings.
  compose-global                    Compose built-in Default/application settings only.
  list-profiles                     List recipe IDs, names, and ordered components.
  list-machines                     List ignored named machine overlays.
  capture-ui-state [profile] <file> Store only an opaque globalState seed locally.
  sync [profile] <export>           Route a reviewed export back to authoritative owners.
  route <action>                    Explain, audit, and manage ownership routes.
  migrate legacy-sync              Audit or archive old profile-sidecar output.
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
        'fix' {
            @'
fix global [-DryRun]
  Repairs mechanically safe ownership-list issues in global/settings.jsonc:
  creates a missing workbench.settings.applyToAllProfiles array, removes duplicate
  entries while preserving the first occurrence, and appends unlisted setting keys
  in their existing file order.

  The repair is staged and repository-validated before it is committed. Listed
  settings with no value, invalid entries, and cross-layer ownership conflicts are
  not guessed; the command fails with an actionable error instead.

Examples:
  ProfileComposer.ps1 fix global -DryRun
  ProfileComposer.ps1 fix global
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
  ProfileComposer.ps1 capture-ui-state main C:\Private\Main.code-profile -DryRun
  ProfileComposer.ps1 capture-ui-state C:\Private\Python.code-profile -DryRun
'@ | Write-Host
        }
        'sync' {
            @'
sync [<profile>] <private-export> [-Platform <id>] [-Machine <id>]
     [-RoutingFile <path>] [-RoutingMode Supplement|Override|Isolated]
     [-NonInteractive] [-WriteUnresolved <path>] [-SkipGlobal] [-SkipUiState]
     [-PersistDryRunDecisions] [-DryRun]
  Imports a manually exported .code-profile, discovers exact repository owners,
  applies managed/custom routes, classifies values, resolves unknown ownership,
  validates one complete mutation plan, and updates authoritative sources.
  When <profile> is omitted, the export name must match exactly one recipe ID
  or display name. Application settings explicitly listed by
  workbench.settings.applyToAllProfiles are synced from the selected VS Code
  User directory; Sync-ignored machine values are excluded.

  Existing exact ownership wins over broad rules. Security classification forces
  exclusion; machine-local path classification forces machine ownership.
  Unknown items are grouped for terminal resolution. -NonInteractive never
  prompts and exits nonzero without repository writes if anything is unresolved.
  -WriteUnresolved writes a reusable provisional router file for review.

  RoutingMode defaults to Supplement. Override suppresses managed matches when a
  custom route matches. Isolated disables the managed router, while exact existing
  ownership and classification remain active. Dry-run performs no repository
  mutation; interactive dry-run decisions persist only with
  -PersistDryRunDecisions.

  Exit 0: complete routed plan validated and applied, or valid dry-run.
  Exit 1: invalid input/router, conflict, unresolved item, or validation failure.

Examples:
  vscomp sync .\Main.code-profile -Platform windows -Machine main-windows
  vscomp sync .\Main.code-profile -Platform windows -Machine main-windows -DryRun
  vscomp sync .\Main.code-profile -Platform windows -Machine main-windows -NonInteractive -WriteUnresolved .\unresolved-routing.yaml
  vscomp sync .\Main.code-profile -Platform windows -Machine main-windows -RoutingFile .\temporary-routes.yaml -RoutingMode Supplement
'@ | Write-Host
        }
        'route' {
            @'
route <action>
  Manages config/ownership-router.jsonc through staged, validated CLI updates.

Actions:
  list
  show <route-id-or-item>
  explain <item> [-Kind setting|extension] [-Platform <id>]
                 [-RoutingFile <path>] [-RoutingMode Supplement|Override|Isolated]
  audit [-RoutingFile <path>] [-Platform <id>]
  add-setting <key> <typed destination> [-Id <id>] [-Reason <text>]
  add-extension <id> <typed destination> [-Id <route-id>] [-Reason <text>]
  add-prefix <prefix> <typed destination> -ConfirmBroadRule [-Kind setting|extension]
  add-publisher <publisher> <typed destination> -ConfirmBroadRule
  remove <route-id> [-DryRun]
  enable <route-id> [-DryRun]
  disable <route-id> [-DryRun]
  import <custom-router> [-DryRun]

Typed destinations:
  -Component <name> | -Platform <name> | -Machine | -Profile <name> |
  -Exclude | -Unresolved

Route metadata defaults:
  -Source user-confirmed
  -Status approved
  -Reason "Added through vscomp route."

Approved routes apply automatically. Provisional routes are suggestions only.
Disabled routes do not participate. Prefix and publisher rules require the
explicit -ConfirmBroadRule switch. Custom files are never imported implicitly.

Examples:
  vscomp route list
  vscomp route explain "python.analysis.typeCheckingMode" -Platform windows
  vscomp route add-setting "editor.formatOnSave" -Component main -Reason "Shared editor baseline"
  vscomp route add-prefix "eslint." -Component web -ConfirmBroadRule
  vscomp route audit
'@ | Write-Host
        }
        'route explain' {
            Write-Host 'route explain <item> [-Kind setting|extension] [-Platform <id>] [-RoutingFile <path>] [-RoutingMode Supplement|Override|Isolated]: prints every candidate, precedence, winner, destination file, classification override, and final validation. Example: vscomp route explain "eslint.useFlatConfig" -Platform windows'
        }
        'route audit' {
            Write-Host 'route audit [-RoutingFile <path>] [-Platform <id>]: validates schema, IDs, references, duplicates, conflicts, pattern overlap, approval state, owner disagreement, and unsafe destinations. Errors exit 1; warnings are reported. Example: vscomp route audit'
        }
        'route add-setting' {
            Write-Host 'route add-setting <key> <typed destination> [-Id <id>] [-Reason <text>] [-Source <value>] [-Status approved|provisional|disabled] [-DryRun]. Example: vscomp route add-setting "some.path" -Machine -Reason "Local executable path"'
        }
        'route add-extension' {
            Write-Host 'route add-extension <publisher.id> <typed destination> [-Id <id>] [-Reason <text>] [-DryRun]. Example: vscomp route add-extension "ms-python.python" -Component python'
        }
        'route add-prefix' {
            Write-Host 'route add-prefix <prefix> <typed destination> -ConfirmBroadRule [-Kind setting|extension] [-DryRun]. Shows intent through an explicit confirmation flag; audit reports overlaps. Example: vscomp route add-prefix "eslint." -Component web -ConfirmBroadRule'
        }
        'route add-publisher' {
            Write-Host 'route add-publisher <publisher> <typed destination> -ConfirmBroadRule [-DryRun]. Example: vscomp route add-publisher "ms-python" -Component python -ConfirmBroadRule'
        }
        'route list' { Write-Host 'route list: lists every managed route with match, destination, status, provenance, and reason. Example: vscomp route list' }
        'route show' { Write-Host 'route show <route-id-or-item>: shows exact matching route metadata without mutation. Example: vscomp route show python-settings' }
        'route remove' { Write-Host 'route remove <route-id> [-DryRun]: removes one exact managed route through a staged transaction. Example: vscomp route remove old-rule -DryRun' }
        'route enable' { Write-Host 'route enable <route-id> [-DryRun]: changes one route status to approved. Example: vscomp route enable python-settings' }
        'route disable' { Write-Host 'route disable <route-id> [-DryRun]: changes one route status to disabled. Example: vscomp route disable stale-rule' }
        'route import' { Write-Host 'route import <custom-router> [-DryRun]: explicitly imports validated non-conflicting routes and marks provenance custom-file. Sync -RoutingFile never mutates the managed router. Example: vscomp route import .\reviewed-routes.yaml -DryRun' }
        'migrate' {
            @'
migrate legacy-sync [-ConfirmArchive] [-BackupName <id>] [-DryRun]
  Audits profile JSONC sidecars produced by the pre-router sync workflow.
  Without -ConfirmArchive it lists candidates and makes no changes.

  -ConfirmArchive copies every candidate into
  migration-backups/<BackupName>/ before removing it from profiles/. The
  default BackupName is legacy-sync-manual. The staged repository must validate
  before replacement, and a post-write failure rolls back profiles and backups.
  Existing non-identical backups cause a safe failure.

  Archiving changes profile behavior. Review the candidate list and Git diff,
  then route each retained item explicitly. This command is terminal-only.

Examples:
  vscomp migrate legacy-sync
  vscomp migrate legacy-sync -ConfirmArchive -BackupName legacy-sync-review -DryRun
  vscomp migrate legacy-sync -ConfirmArchive -BackupName legacy-sync-review
'@ | Write-Host
        }
        'rename-profile' {
            Write-Host 'rename-profile <old-id> <new-id> [-DryRun]: transactionally renames the recipe, optional profile override, and stored local UI-state seed. It never touches live VS Code profiles. Example: ProfileComposer.ps1 rename-profile old-id new-id -DryRun'
        }
        'rename-component' {
            Write-Host 'rename-component <old-id> <new-id> [-DryRun]: transactionally renames the component, updates ordered recipe references, and updates composer.jsonc when needed. Example: ProfileComposer.ps1 rename-component old new -DryRun'
        }
        'default' {
            Write-Host 'default show | default set <component> [-DryRun]: reads or transactionally changes shared-default ownership. Setting it places the component first in every recipe without duplicates. Example: ProfileComposer.ps1 default set main -DryRun'
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

function Get-RouteDestinationFromOptions {
    param([Parameter(Mandatory)][hashtable]$Options)

    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @(
        @{ Key = 'component'; Type = 'component'; Value = $true },
        @{ Key = 'platform'; Type = 'platform'; Value = $true },
        @{ Key = 'profile'; Type = 'profile'; Value = $true },
        @{ Key = 'machine'; Type = 'machine'; Value = $false },
        @{ Key = 'exclude'; Type = 'exclude'; Value = $false },
        @{ Key = 'unresolved'; Type = 'unresolved'; Value = $false }
    )) {
        if (($entry.Value -and $Options.ContainsKey($entry.Key)) -or (-not $entry.Value -and [bool]$Options[$entry.Key])) {
            $selected.Add($entry)
        }
    }
    if ($selected.Count -ne 1) {
        throw 'Choose exactly one destination: -Component, -Platform, -Machine, -Profile, -Exclude, or -Unresolved.'
    }
    $choice = $selected[0]
    $name = if ($choice.Value) { [string]$Options[$choice.Key] } else { $null }
    return New-OwnershipDestination $choice.Type $name
}

function Invoke-RouteCommand {
    param([string[]]$Arguments)

    if ($Arguments.Count -eq 0) { Write-CommandHelp route; return }
    $action = $Arguments[0].ToLowerInvariant()
    $remaining = @($Arguments | Select-Object -Skip 1)
    if ($action -in @('help', '-help', '--help', '-h')) {
        if ($remaining.Count -gt 0) { Write-CommandHelp "route $($remaining[0])" } else { Write-CommandHelp route }
        return
    }
    switch ($action) {
        'list' {
            $parsed = Read-CommandOptions $remaining @() @('RepositoryRoot')
            if ($parsed.Options.Help) { Write-CommandHelp 'route list'; return }
            if ($parsed.Positionals.Count -ne 0) { throw 'route list does not accept positional arguments.' }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $router = Get-ManagedOwnershipRouter $root
            Write-Host "Managed ownership routes ($($router.routes.Count)):"
            foreach ($route in $router.routes | Sort-Object id) {
                Write-Host "  $($route.id): $($route.kind) $($route.match.type) '$($route.match.value)' -> $(Get-OwnershipDestinationLabel $route.destination) [$($route.status); $($route.source)]"
                Write-Host "    $($route.reason)"
            }
        }
        'show' {
            $parsed = Read-CommandOptions $remaining @() @('RepositoryRoot')
            if ($parsed.Options.Help) { Write-CommandHelp 'route show'; return }
            if ($parsed.Positionals.Count -ne 1) { throw 'route show requires one route ID or routed item.' }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $value = $parsed.Positionals[0]
            $matches = @((Get-ManagedOwnershipRouter $root).routes | Where-Object {
                $_.id -ieq $value -or ($_.match.type -eq 'exact' -and $_.match.value -ieq $value)
            })
            if ($matches.Count -eq 0) { throw "No route matches '$value'." }
            $matches | ConvertTo-Json -Depth 20 | Write-Host
        }
        'explain' {
            $parsed = Read-CommandOptions $remaining @() @('RepositoryRoot', 'Kind', 'Platform', 'RoutingFile', 'RoutingMode')
            if ($parsed.Options.Help) { Write-CommandHelp 'route explain'; return }
            if ($parsed.Positionals.Count -ne 1) { throw 'route explain requires one setting key or extension ID.' }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $parameters = @{ RepositoryRoot = $root; Item = $parsed.Positionals[0] }
            foreach ($key in @('kind', 'platform', 'routingfile', 'routingmode')) {
                if ($parsed.Options.ContainsKey($key)) { $parameters[$key] = $parsed.Options[$key] }
            }
            $report = Explain-OwnershipRoute @parameters
            Write-Host "$($report.kind): $($report.item)"
            Write-Host 'Resolution candidates:'
            if ($report.candidates.Count -eq 0) { Write-Host '  No matching candidates.' }
            foreach ($candidate in $report.candidates | Sort-Object precedence) {
                Write-Host "  $($candidate.precedence). $($candidate.id) [$($candidate.source); $($candidate.status)] -> $(Get-OwnershipDestinationLabel $candidate.destination)"
                Write-Host "     $($candidate.reason)"
            }
            Write-Host "Destination: $($report.destination)"
            if ($report.destinationFile) { Write-Host "Destination file: $($report.destinationFile)" }
            Write-Host "Classification: $($report.classification)"
            Write-Host "Validation: $($report.validation)"
        }
        'audit' {
            $parsed = Read-CommandOptions $remaining @() @('RepositoryRoot', 'RoutingFile', 'Platform')
            if ($parsed.Options.Help) { Write-CommandHelp 'route audit'; return }
            if ($parsed.Positionals.Count -ne 0) { throw 'route audit does not accept positional arguments.' }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $parameters = @{ RepositoryRoot = $root }
            foreach ($key in @('routingfile', 'platform')) { if ($parsed.Options.ContainsKey($key)) { $parameters[$key] = $parsed.Options[$key] } }
            $result = Invoke-OwnershipRouterAudit @parameters
            Write-ValidationSummary $result
            if ($result.errors.Count -gt 0) { exit 1 }
        }
        { $_ -in @('add-setting', 'add-extension', 'add-prefix', 'add-publisher') } {
            $parsed = Read-CommandOptions $remaining @('Machine', 'Exclude', 'Unresolved', 'ConfirmBroadRule', 'DryRun') @(
                'Component', 'Platform', 'Profile', 'RepositoryRoot', 'Id', 'Reason', 'Source', 'Status', 'Kind'
            )
            if ($parsed.Options.Help) { Write-CommandHelp "route $action"; return }
            if ($parsed.Positionals.Count -ne 1) { throw "route $action requires one key, extension ID, prefix, or publisher." }
            if ($action -in @('add-prefix', 'add-publisher') -and -not $parsed.Options.confirmbroadrule) {
                throw "route $action requires -ConfirmBroadRule after reviewing the proposed match."
            }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $destination = Get-RouteDestinationFromOptions $parsed.Options
            $kind = switch ($action) {
                'add-setting' { 'setting' }
                'add-extension' { 'extension' }
                'add-publisher' { 'extension' }
                default { if ($parsed.Options.ContainsKey('kind')) { [string]$parsed.Options.kind } else { 'setting' } }
            }
            if ($kind -notin @('setting', 'extension')) { throw "-Kind must be setting or extension." }
            $matchType = if ($action -in @('add-setting', 'add-extension')) { 'exact' } elseif ($action -eq 'add-publisher') { 'publisher' } else { 'prefix' }
            $matchValue = $parsed.Positionals[0]
            $safe = $matchValue.ToLowerInvariant() -replace '[^a-z0-9._-]', '-'
            $routeId = if ($parsed.Options.ContainsKey('id')) { [string]$parsed.Options.id } else { "$kind-$matchType-$safe" }
            $reason = if ($parsed.Options.ContainsKey('reason')) { [string]$parsed.Options.reason } else { 'Added through vscomp route.' }
            $source = if ($parsed.Options.ContainsKey('source')) { [string]$parsed.Options.source } else { 'user-confirmed' }
            $status = if ($parsed.Options.ContainsKey('status')) { [string]$parsed.Options.status } else { 'approved' }
            $route = New-OwnershipRoute $routeId $kind $matchType $matchValue $destination $source $status $reason
            $result = Add-ManagedOwnershipRoute $root $route -DryRun:$parsed.Options.dryrun
            Write-ChangePlan $result
        }
        { $_ -in @('remove', 'enable', 'disable') } {
            $parsed = Read-CommandOptions $remaining @('DryRun') @('RepositoryRoot')
            if ($parsed.Options.Help) { Write-CommandHelp "route $action"; return }
            if ($parsed.Positionals.Count -ne 1) { throw "route $action requires one route ID." }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            if ($action -eq 'remove') {
                $result = Remove-ManagedOwnershipRoute $root $parsed.Positionals[0] -DryRun:$parsed.Options.dryrun
            }
            else {
                $status = if ($action -eq 'enable') { 'approved' } else { 'disabled' }
                $result = Set-ManagedOwnershipRouteStatus $root $parsed.Positionals[0] $status -DryRun:$parsed.Options.dryrun
            }
            Write-ChangePlan $result
        }
        'import' {
            $parsed = Read-CommandOptions $remaining @('DryRun') @('RepositoryRoot')
            if ($parsed.Options.Help) { Write-CommandHelp 'route import'; return }
            if ($parsed.Positionals.Count -ne 1) { throw 'route import requires one custom router path.' }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $result = Import-ManagedOwnershipRoutes $root $parsed.Positionals[0] -DryRun:$parsed.Options.dryrun
            Write-ChangePlan $result
        }
        default { throw "Unknown route action '$action'. Use 'vscomp help route'." }
    }
}

function Invoke-Compose {
    param([bool]$AllProfiles, [string[]]$Arguments)
    $parsed = Read-CommandOptions $Arguments @('DryRun', 'Strict', 'ExportCodeProfile') @('Platform', 'Machine', 'MachineFile', 'UiStateFromProfile', 'UiStateProfile', 'RepositoryRoot')
    if ($parsed.Options.Help) { Write-CommandHelp $(if ($AllProfiles) { 'compose-all' } else { 'compose' }); return }
    if ($AllProfiles -and $parsed.Positionals.Count -ne 0) { throw 'compose-all does not accept a profile ID.' }
    if (-not $AllProfiles -and $parsed.Positionals.Count -ne 1) { throw 'compose requires exactly one profile ID. Example: ProfileComposer.ps1 compose main -Platform windows' }
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
            elseif ($CommandArguments.Count -le 2) { Write-CommandHelp ($CommandArguments -join ' ') }
            else { throw 'help accepts a command and optional subcommand name.' }
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
        'fix' {
            $parsed = Read-CommandOptions $CommandArguments @('DryRun') @('RepositoryRoot')
            if ($parsed.Options.Help -or $parsed.Positionals.Count -eq 0) { Write-CommandHelp fix; break }
            if ($parsed.Positionals.Count -ne 1 -or $parsed.Positionals[0].ToLowerInvariant() -ne 'global') {
                throw "fix currently requires the target 'global'."
            }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $result = Repair-ComposerGlobalOwnership $root -DryRun:$parsed.Options.dryrun
            Write-ChangePlan $result
            if ($result.ownershipListCreated) {
                Write-Host '  Created workbench.settings.applyToAllProfiles.'
            }
            if ($result.addedSettings.Count -gt 0) {
                Write-Host "  Added missing ownership: $($result.addedSettings -join ', ')"
            }
            if ($result.removedDuplicates.Count -gt 0) {
                Write-Host "  Removed duplicate entries: $($result.removedDuplicates -join ', ')"
            }
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
                else {
                    Write-Host 'Named machine overlays:'
                    foreach ($item in $machines) {
                        $platform = if ($item.Platform) { $item.Platform } else { 'platform unspecified' }
                        $schema = if ($item.Legacy) { 'legacy settings map' } else { "schema $($item.SchemaVersion)" }
                        Write-Host "  $($item.Id): $($item.Name) [$platform; $schema] machine/local/$($item.Id).jsonc"
                    }
                }
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
            $parsed = Read-CommandOptions $CommandArguments @('DryRun', 'SkipGlobal', 'SkipUiState', 'NonInteractive', 'PersistDryRunDecisions') @(
                'Platform', 'Machine', 'MachineFile', 'RepositoryRoot', 'VSCodeUserDataPath',
                'RoutingFile', 'RoutingMode', 'WriteUnresolved'
            )
            if ($parsed.Options.Help) { Write-CommandHelp sync; break }
            if ($parsed.Positionals.Count -lt 1 -or $parsed.Positionals.Count -gt 2) {
                throw 'sync requires <profile-export> for automatic matching or <profile> <profile-export> explicitly.'
            }
            if ($parsed.Options.ContainsKey('machine') -and $parsed.Options.ContainsKey('machinefile')) {
                throw '-Machine and -MachineFile cannot be used together.'
            }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $parameters = @{
                RepositoryRoot = $root
                SourceProfileExport = $parsed.Positionals[-1]
                DryRun = [bool]$parsed.Options.dryrun
                SkipGlobal = [bool]$parsed.Options.skipglobal
                SkipUiState = [bool]$parsed.Options.skipuistate
                NonInteractive = [bool]$parsed.Options.noninteractive
                PersistDryRunDecisions = [bool]$parsed.Options.persistdryrundecisions
            }
            if ($parsed.Positionals.Count -eq 2) { $parameters.Profile = $parsed.Positionals[0] }
            foreach ($key in @('platform', 'machine', 'machinefile', 'vscodeuserdatapath', 'routingfile', 'routingmode', 'writeunresolved')) {
                if ($parsed.Options.ContainsKey($key)) { $parameters[$key] = $parsed.Options[$key] }
            }
            $result = Sync-ComposerProfileFromExport @parameters
            Write-Host "$(if ($result.dryRun) { 'DRY RUN: planned sync' } else { 'Synced' }) export '$($result.exportName)' to recipe '$($result.profileId)'."
            Write-ChangePlan $result
            Write-Host "  Settings routed: $($result.counts.settingsRouted); extensions routed: $($result.counts.extensionsRouted); excluded: $($result.counts.excluded)"
            Write-Host "  Conservative removal policy: no shared setting or extension was removed because it was absent from this export."
            Write-Host "  Keybindings: $($result.counts.keybindingAdditions) addition(s), exact-order replacement=$($result.counts.keybindingsReplacedForOrder)"
            Write-Host "  Global: $($result.counts.globalSettings) tracked setting(s); $($result.counts.machineOwnedGlobalSettingsSkipped) Sync-ignored machine value(s) skipped"
            Write-Host "  Ownership filters: $($result.counts.exportGlobalSettingsIgnored) global/machine setting(s) and $($result.counts.platformSettingsIgnored) platform setting(s) excluded from recipe deltas"
            Write-Host "  Machine routing: $($result.counts.machineSettingsAdded) addition(s), $($result.counts.machineSettingsUpdated) update(s), $($result.counts.machineSettingsRetained) retained"
            if ($result.machine) {
                Write-Host "  Selected machine: $($result.machine.id) [$($result.machine.selection)] -> $($result.machine.path)"
            }
            $displayRoutes = @($result.routes | Where-Object { $_.changed -or $_.ruleId -ne 'existing-repository-owner' -or $_.classification -notin @('portable', 'extension') })
            foreach ($route in $displayRoutes) {
                Write-Host "    $($route.kind.ToUpperInvariant()) $($route.item) -> $($route.destination) [$($route.ruleId); precedence $($route.precedence); $($route.classification)]"
            }
            Write-Host "  UI state updated: $($result.uiStateUpdated)"
        }
        'route' { Invoke-RouteCommand $CommandArguments }
        'migrate' {
            $parsed = Read-CommandOptions $CommandArguments @('ConfirmArchive', 'DryRun') @('RepositoryRoot', 'BackupName')
            if ($parsed.Options.Help -or $parsed.Positionals.Count -eq 0) { Write-CommandHelp migrate; break }
            if ($parsed.Positionals.Count -ne 1 -or $parsed.Positionals[0] -ine 'legacy-sync') {
                throw "migrate currently requires the target 'legacy-sync'."
            }
            $root = Get-RepositoryRootFromOptions $parsed.Options
            $parameters = @{
                RepositoryRoot = $root
                ConfirmArchive = [bool]$parsed.Options.confirmarchive
                DryRun = [bool]$parsed.Options.dryrun
            }
            if ($parsed.Options.ContainsKey('backupname')) { $parameters.BackupName = $parsed.Options.backupname }
            $result = Archive-LegacySyncSidecars @parameters
            Write-ChangePlan $result
            if ($result.confirmationRequired) { Write-Host '  Re-run with -ConfirmArchive only after reviewing every candidate.' }
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
