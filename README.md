# VS Code Profile Composer

This repository contains reusable VS Code settings and extension components plus a safe PowerShell 7 composer. `scripts/ProfileComposer.ps1` is the unified CLI for validation, composition, discovery, reviewed export synchronization, UI-state capture, transactional source maintenance, and guarded VS Code profile guidance. Ordinary composition remains repository-only.

For a complete first-run walkthrough, profile-selection guide, import procedure, Settings Sync precautions, maintenance workflow, and troubleshooting reference, start with [Complete usage guide](docs/USAGE.md). For every command, subcommand, option, destination, output, exit behavior, and safety boundary, use the [Complete composer CLI guide](docs/CLI-GUIDE.md).

## Quick start

Requirements:

- PowerShell 7.0 or newer (`pwsh`)
- Git, optional, for normal source-control workflows
- Pester 5.5 or newer, only for running the test suite

The composer has no external runtime dependencies and never installs modules automatically.

```powershell
# Discover commands and detailed command-specific help.
pwsh ./scripts/ProfileComposer.ps1 help
pwsh ./scripts/ProfileComposer.ps1 compose help
pwsh ./scripts/ProfileComposer.ps1 compose -Help

# Validate every component and recipe.
pwsh ./scripts/ProfileComposer.ps1 validate

# Preview mechanically safe repairs to global ownership.
pwsh ./scripts/ProfileComposer.ps1 fix global -DryRun

# Compose one profile.
pwsh ./scripts/ProfileComposer.ps1 compose main -Platform windows

# Compose the two current project profiles.
pwsh ./scripts/ProfileComposer.ps1 compose react -Platform windows
pwsh ./scripts/ProfileComposer.ps1 compose project-zomboid-mod -Platform windows

# List and select private machine-local overlays by ID.
pwsh ./scripts/ProfileComposer.ps1 list-machines
pwsh ./scripts/ProfileComposer.ps1 compose unreal -Platform windows -Machine windows

# Generate only the settings owned by VS Code's built-in Default profile.
pwsh ./scripts/ProfileComposer.ps1 compose-global

# Compose every valid recipe.
pwsh ./scripts/ProfileComposer.ps1 compose-all -Platform windows

# Compose and create a file for manual import through VS Code Profiles.
pwsh ./scripts/ProfileComposer.ps1 compose main -Platform windows

# Inspect inputs and planned output without writing build files.
pwsh ./scripts/ProfileComposer.ps1 compose main -Platform windows -DryRun

# Explain and audit ownership routing.
pwsh ./scripts/ProfileComposer.ps1 route explain "python.analysis.typeCheckingMode" -Platform windows
pwsh ./scripts/ProfileComposer.ps1 route audit -Platform windows
```

After arranging a profile in VS Code and exporting it manually, store only its UI state under ignored local project data:

```powershell
# Explicit recipe ID.
pwsh ./scripts/ProfileComposer.ps1 capture-ui-state main "C:\private\Adjusted Main.code-profile"

# Or omit the recipe when exactly one active VS Code profile name matches a recipe.
pwsh ./scripts/ProfileComposer.ps1 capture-ui-state "C:\private\Adjusted Python.code-profile"
```

If active VS Code windows match zero or multiple recipe IDs/display names, automatic selection fails and requires the explicit form.

After changing a test profile, export it through the Profiles editor and preview a complete repository sync:

```powershell
# The export name matches the Python recipe automatically.
pwsh ./scripts/ProfileComposer.ps1 sync "C:\private\Adjusted Python.code-profile" -Platform windows -Machine main-windows -DryRun

# Apply only after reviewing the plan; inspect the Git diff afterward.
pwsh ./scripts/ProfileComposer.ps1 sync "C:\private\Adjusted Python.code-profile" -Platform windows -Machine main-windows
```

`sync` is an ownership-aware repository synchronization command. Existing
component, platform, machine, and explicit profile-local owners are updated
directly. New items use the managed registry at
`config/ownership-router.jsonc`, an optional custom JSONC/YAML router, or a
grouped terminal decision. Unknown items never fall back to profile JSON.
Classification runs before portability validation: sensitive/private values
are excluded and machine paths route to the selected ignored machine file. It
also reads the built-in Default/application `settings.json`, automatically
derives `workbench.settings.applyToAllProfiles` from every top-level setting,
updates portable values in `global/settings.jsonc`, and routes ignored or
machine-classified values to the selected private machine overlay. Add
`-NonInteractive -WriteUnresolved <path>` for deterministic automation.

After `sync` or `capture-ui-state` updates Main's stored layout, ordinary
composition uses it automatically:

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose-all -Platform windows -Machine excalibur117-w
```

Warnings are informational by default. Add `-Strict` to make warnings fail validation or composition.

## Repository model

```text
Named profile: Main shared base
→ additional recipe components in declared order
→ optional recipe-specific settings removals, recursive overrides, and exact replacements
→ optional recipe-specific extension/keybinding operations
→ platform/<platform>.jsonc
→ selected schema 2 machine component settings
→ selected schema 2 machine profile settings
→ workspace settings owned by the active repository

Built-in Default/application settings: global/settings.jsonc
→ optional explicitly selected machine-local settings file
```

Later layers win. Settings objects merge recursively, while scalar values, arrays, and null values replace earlier values. Extension IDs are validated and deduplicated case-insensitively in first-appearance order. Keybinding arrays are concatenated unchanged; identical objects produce warnings but remain in the output.

Workspace settings are not materialized into personal profiles. `workspace-examples/` remains project guidance only.

`composer.jsonc` declares both the shared default component and the default
UI-state seed profile. Both currently use `main`. The shared component remains
first in every recipe, while the UI setting copies Main's ignored local seed
into each new export when that seed exists. Use `default show` or
`default set <component> -DryRun`; setting ownership normalizes every recipe
without duplicates while preserving the remaining order.

Repository IDs can be maintained without hand-editing references:

```powershell
pwsh ./scripts/ProfileComposer.ps1 rename-profile old-id new-id -DryRun
pwsh ./scripts/ProfileComposer.ps1 rename-component old-id new-id -DryRun
```

Sync, global ownership repair, rename, and shared-default changes are validated in an isolated staged copy, then applied as a rollback-safe source transaction. `fix global` creates a missing apply-to-all array, removes duplicate IDs while preserving first occurrence, and appends unlisted global value keys; it refuses missing values and cross-layer conflicts rather than guessing. These commands never rename or rewrite live VS Code profiles. Use `ProfileComposer.ps1` for all new workflows; the older `Compose-Profile.ps1` and `Save-ProfileUiState.ps1` scripts remain compatible wrappers for existing automation.

## Output and safety

Composition produces only the two end-user deliverables:

```text
build/global/settings.json
build/profiles/<id>/<Display-Name>.code-profile
```

The `.code-profile` is the finished importable named profile. The separate
application settings file is necessary because VS Code stores apply-to-all and
machine-local values in the built-in Default profile instead of a named-profile
import. Intermediate settings, extension, keybinding, validation, and override
data is kept in memory and is not emitted.

Generated JSON is standard JSON. Each build is first written and validated in a temporary directory. The prior target is replaced only after the new package is complete; a failed composition preserves the previous valid output. Build output is ignored and is never canonical source.

Settings listed in `global/settings.jsonc` are deliberately absent from named-profile output. VS Code ignores copies of those settings and uses the built-in Default profile's value instead. Edit the repository global source, generate `build/global/settings.json`, and manually merge it into **Preferences: Open Application Settings (JSON)**.

`workbench.settings.applyToAllProfiles` is derived ownership metadata. Every
other top-level key in generated application settings is included exactly once.
During `sync`, the same normalization runs before ownership routing, so a value
cannot become orphaned merely because its array entry was missing.

Machine application values remain only in `build/global/settings.json`.
Schema 2 component/profile values are written only to matching named profiles;
those exports are explicitly reported as machine-specific.

Repository validation checks recipes, JSONC/YAML structure, extension IDs and duplicates, portable personal paths and likely secrets, requested overlays, ignored machine-local boundaries, profile IDs, and output containment.

## VS Code profile export

`compose <profile-id>` and `compose-all` always create finished importable
profiles. For example, Main writes `build/profiles/main/Main.code-profile`;
Unreal writes `build/profiles/unreal/Unreal-Engine.code-profile`. The export
contains the fully composed settings, recipe-owned extension identifiers, and
generated keybindings. VS Code handles extension acquisition during its normal
import workflow—composition never installs extensions.

Schema 2 machine application values are excluded from named-profile settings
and added to `build/global/settings.json`, `applyToAllProfiles`, and
`settingsSync.ignoredSettings`. Component/profile values are added only to
matching profile exports and their keys are Sync-ignored. Such exports are
machine-specific; omit `-Machine` for a portable artifact.

`ProfileComposer.ps1 capture-ui-state [<profile-id>] <export-path>` validates a manually exported `.code-profile` and stores only its opaque `globalState` resource at `machine/local/ui-state/<profile>/seed.code-profile`. When the recipe ID is omitted, the CLI reads `code --status` and accepts exactly one active profile name matching a recipe ID or display name. Zero or multiple matches fail safely. The source settings, extensions, keybindings, name, and path are not copied. Normal composition automatically uses the target profile's stored seed when present, then falls back to the seed named by `composer.jsonc.defaultUiStateProfile`; `-UiStateProfile <id>` is an advanced per-run override, `-UiStateFromProfile <path>` is a one-off compatibility source, and `-NoUiState` explicitly omits UI state. This is copy-on-compose, not live inheritance: capturing or syncing a seed does not regenerate a built artifact or change an imported profile. Run `compose` (or `compose-all`) and then complete a reviewed import or replacement to deliver it. Views introduced by other extensions use their defaults. Stored and generated UI-seeded files are private because `globalState` can include extension or account-related state.

`ProfileComposer.ps1 sync [<profile-id>] <export-path>` is the reviewed reverse
path. It consumes settings, extensions, keybindings, and optional
`globalState`; resolves exact ownership before managed/custom patterns; groups
unresolved items for terminal decisions; validates the complete plan; and
updates authoritative files atomically. Missing imported resources do not
delete shared ownership. Explicit profile routes may use the existing profile
sidecar formats, and a reviewed keybinding order remains profile-local. The
private UI resource remains ignored under `machine/local/ui-state/`. Storing it
does not regenerate `build/` or modify a live VS Code profile; `sync` reports
those delivery boundaries and points to the required compose/import steps.

## Guided VS Code profile management

The `vscode` command group automates safe preparation and read-only discovery while leaving profile creation and deletion in VS Code's supported Profiles editor:

```powershell
pwsh ./scripts/ProfileComposer.ps1 vscode list
pwsh ./scripts/ProfileComposer.ps1 vscode open "Python + Database" .
pwsh ./scripts/ProfileComposer.ps1 vscode import python-database -Platform windows -DryRun
pwsh ./scripts/ProfileComposer.ps1 vscode replace python-database -LiveProfile "Old Python Setup" -Platform windows -DryRun
pwsh ./scripts/ProfileComposer.ps1 vscode delete "Old Python Setup" -DryRun
```

Here `<recipe>` is the filename under `profiles/` without `.yaml`; `-LiveProfile` is the exact existing VS Code display name. `vscode import` and `vscode replace` imply `.code-profile` export and print the reviewed Profiles-editor steps. `vscode list` reads only profile names and opaque location IDs. `vscode open` uses the supported `code --profile` option after verifying the target exists. Replace and delete never edit VS Code's private profile registry or Settings Sync data.

Import manually:

```text
File → Preferences → Profiles
→ New Profile dropdown
→ Import Profile...
→ Select the generated .code-profile
→ Review contents
→ Create Profile
```

When a target-profile seed or configured fallback seed exists, UI placement is
included automatically. The composer passes one opaque snapshot through without
interpreting or merging it. After import, VS Code owns and syncs the resulting
live UI state. Review every import preview: re-importing may create a profile or
replace selected profile resources according to VS Code's current import
workflow.

Portable custom keybindings are canonical component inputs. `components/main/keybindings.jsonc` supplies the editor, notebook, panel, Markdown, and spelling shortcuts inherited by every recipe, including `Ctrl+Shift+S` for cSpell suggestions; focused extension commands such as SQL Server's IntelliSense-cache rebuild shortcut stay in their owning component. A reviewed sync can add, remove, or exactly order recipe-specific bindings without changing those shared sources.

## Machine-local setup

Create one ignored file per computer. Its filename is the machine ID:

```powershell
Copy-Item ./machine/windows.example.jsonc ./machine/local/main-windows.jsonc
pwsh ./scripts/ProfileComposer.ps1 list-machines
pwsh ./scripts/ProfileComposer.ps1 compose main -Platform windows -Machine main-windows
```

Replace placeholders locally, then select the filename without `.jsonc` using `-Machine`. `-MachineFile` remains available for an exceptional explicit path. The same command generates the portable named profile and the selected computer's `build/global/settings.json`; manually merge the latter into **Preferences: Open Application Settings (JSON)**. In particular, Todo Tree's confirmed working Windows ripgrep path is machine-specific; no portable `"rg"` override is present in Main.

New machine files use the versioned identity envelope documented in [Schema and ownership contract](docs/SCHEMA.md). Legacy plain settings maps remain compatible. For sync-only automatic selection, store one ignored ID in `machine/local/.default-machine`; otherwise sync accepts exactly one platform-compatible local machine and fails rather than guessing among multiple targets.

## Tests

Install Pester only if needed:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
```

Run the isolated suite:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed -CI"
```

Run the terminal-only documentation/help/schema/link drift check:

```powershell
pwsh -NoProfile -NonInteractive -File ./scripts/Test-Documentation.ps1
```

## Installer status

Unattended installation, replacement, deletion, and export remain deferred because VS Code 1.130 exposes no supported complete profile-management CLI. The guided commands may read profile names/location IDs and `code --status`, and `vscode open` may launch an existing profile; they never write profile storage, invoke import/export automatically, install extensions, or alter Settings Sync. `sync` requires a manually exported private `.code-profile` and reads application settings only for explicit global ownership reconciliation. Settings Sync remains the primary cross-machine delivery mechanism for imported active profiles.

See [Complete composer CLI guide](docs/CLI-GUIDE.md), [Complete usage guide](docs/USAGE.md), [C++ and Unreal performance settings](docs/CPP-UNREAL-PERFORMANCE.md), [Ownership router and sync](docs/OWNERSHIP-ROUTER.md), [Composer details](docs/COMPOSER.md), [Architecture](docs/ARCHITECTURE.md), [Schema and ownership contract](docs/SCHEMA.md), [Main profile health check](docs/audits/2026-07-29-main-profile-health.md), [Sync routing and schema-model audit](docs/audits/2026-07-23-sync-schema-model.md), [Main-profile ownership audit](docs/audits/2026-07-22-main-profile-ownership.md), [Portability](docs/PORTABILITY.md), [Migration](docs/MIGRATION.md), and the sanitized [historical extension reference](reference/extensions/README.md).
