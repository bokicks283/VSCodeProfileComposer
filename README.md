# VS Code Profile Composer

This repository contains reusable VS Code settings and extension components plus a safe PowerShell 7 composer. `scripts/ProfileComposer.ps1` is the unified CLI for validation, composition, discovery, UI-state capture, and transactional source maintenance without changing the user's VS Code installation.

For a complete first-run walkthrough, profile-selection guide, import procedure, Settings Sync precautions, maintenance workflow, and troubleshooting reference, start with [Complete usage guide](docs/USAGE.md).

## Quick start

Requirements:

- PowerShell 7.0 or newer (`pwsh`)
- Git, optional, for recording the current commit in manifests
- Pester 5.5 or newer, only for running the test suite

The composer has no external runtime dependencies and never installs modules automatically.

```powershell
# Discover commands and detailed command-specific help.
pwsh ./scripts/ProfileComposer.ps1 help
pwsh ./scripts/ProfileComposer.ps1 help compose

# Validate every component and recipe.
pwsh ./scripts/ProfileComposer.ps1 validate

# Compose one profile.
pwsh ./scripts/ProfileComposer.ps1 compose default -Platform windows

# List and select private machine-local overlays by ID.
pwsh ./scripts/ProfileComposer.ps1 list-machines
pwsh ./scripts/ProfileComposer.ps1 compose unreal -Platform windows -Machine windows

# Generate only the settings owned by VS Code's built-in Default profile.
pwsh ./scripts/ProfileComposer.ps1 compose-global

# Compose every valid recipe.
pwsh ./scripts/ProfileComposer.ps1 compose-all -Platform windows

# Compose and create a file for manual import through VS Code Profiles.
pwsh ./scripts/ProfileComposer.ps1 compose default -Platform windows -ExportCodeProfile

# Inspect inputs and planned output without writing build files.
pwsh ./scripts/ProfileComposer.ps1 compose default -Platform windows -ExportCodeProfile -DryRun
```

After arranging a profile in VS Code and exporting it manually, store only its UI state under ignored local project data:

```powershell
pwsh ./scripts/ProfileComposer.ps1 capture-ui-state default "C:\private\Adjusted Default.code-profile"
```

Reuse that stored layout for the same profile or as the starting layout for another profile:

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose python-database -Platform windows -Machine excalibur117-w -ExportCodeProfile -UiStateProfile default
```

Warnings are informational by default. Add `-Strict` to make warnings fail validation or composition.

## Repository model

```text
Named profile: Default shared base
→ additional recipe components in declared order
→ optional profiles/<id>.settings.jsonc override
→ platform/<platform>.jsonc

Built-in Default/application settings: global/settings.jsonc
→ optional explicitly selected machine-local settings file
```

Later layers win. Settings objects merge recursively, while scalar values, arrays, and null values replace earlier values. Extension IDs are validated and deduplicated case-insensitively in first-appearance order. Keybinding arrays are concatenated unchanged; identical objects produce warnings but remain in the output.

Workspace settings are not materialized into personal profiles. `workspace-examples/` remains project guidance only.

`composer.jsonc` declares the shared default component. It starts as `default`, which remains first in every recipe, so its portable settings and extensions are present in every generated profile. Use `default show` or `default set <component> -DryRun`; setting ownership normalizes every recipe without duplicates while preserving the remaining order.

Repository IDs can be maintained without hand-editing references:

```powershell
pwsh ./scripts/ProfileComposer.ps1 rename-profile old-id new-id -DryRun
pwsh ./scripts/ProfileComposer.ps1 rename-component old-id new-id -DryRun
```

Rename and shared-default changes are validated in an isolated staged copy, then applied as a rollback-safe source transaction. They never rename live VS Code profiles. The older `Compose-Profile.ps1` and `Save-ProfileUiState.ps1` commands remain compatible wrappers.

## Output and safety

Composition writes global settings to `build/global/` and named profiles to `build/profiles/<id>/`:

```text
settings.json
extensions.txt
keybindings.json
manifest.json
overrides.json
validation.json
# Optional when -ExportCodeProfile is supplied:
<Display-Name>.code-profile
```

Generated JSON is standard JSON. Each build is first written and validated in a temporary directory. The prior target is replaced only after the new package is complete; a failed composition preserves the previous valid output. Build output is ignored and is never canonical source.

Settings listed in `global/settings.jsonc` are deliberately absent from named-profile output. VS Code ignores copies of those settings and uses the built-in Default profile's value instead. Edit the repository global source, generate `build/global/settings.json`, and manually merge it into **Preferences: Open Application Settings (JSON)**.

`overrides.json` records replaced setting paths, values, and source layers. Values whose paths look sensitive are redacted in reports. Explicitly selected machine-local values remain intact only in `build/global/settings.json`; they are never written to named-profile settings or exports.

Repository validation checks recipes, JSONC/YAML structure, extension IDs and duplicates, portable personal paths and likely secrets, requested overlays, ignored machine-local boundaries, profile IDs, and output containment.

## VS Code profile export

Add `-ExportCodeProfile` to one-profile or `-All` composition. For example, Default writes `build/profiles/default/Default.code-profile`; Unreal writes `build/profiles/unreal/Unreal-Engine.code-profile`. The export contains the fully composed settings, recipe-owned extension identifiers, and generated keybindings. VS Code handles extension acquisition during its normal import workflow—composition never installs extensions.

Machine overlays are deliberately excluded from named-profile settings and `.code-profile` exports. Selecting `-Machine` or `-MachineFile` instead adds those keys to `build/global/settings.json`, `workbench.settings.applyToAllProfiles`, and `settingsSync.ignoredSettings`. This makes the values effective on the selected computer without sending its paths through Settings Sync. Exports remain portable unless `-UiStateFromProfile` adds a private UI snapshot.

`Save-ProfileUiState.ps1` validates a manually exported `.code-profile` and stores only its opaque `globalState` resource at `machine/local/ui-state/<profile>/seed.code-profile`. The source settings, extensions, keybindings, name, and path are not copied. `-UiStateProfile <id>` reuses a stored seed; `-UiStateFromProfile <path>` remains available for a one-off build. This is copy-on-create, not inheritance: VS Code owns each profile's UI after import, later layout changes do not propagate, and views introduced by other extensions use their defaults. Stored and generated UI-seeded files are private because `globalState` can include extension or account-related state.

Import manually:

```text
File → Preferences → Profiles
→ New Profile dropdown
→ Import Profile...
→ Select the generated .code-profile
→ Review contents
→ Create Profile
```

By default, UI placement is not included. When an explicit UI seed is supplied, the composer passes the snapshot through without interpreting or merging it. After import, VS Code owns and syncs the resulting live UI state. Review every import preview: re-importing may create a profile or replace selected profile resources according to VS Code's current import workflow.

`components/default/keybindings.jsonc` is currently absent, so current exports correctly carry an empty custom-keybinding array. Add repository-owned bindings there when they are ready; the composer never reads live user keybindings.

## Machine-local setup

Create one ignored file per computer. Its filename is the machine ID:

```powershell
Copy-Item ./machine/windows.example.jsonc ./machine/local/main-windows.jsonc
pwsh ./scripts/ProfileComposer.ps1 list-machines
pwsh ./scripts/ProfileComposer.ps1 compose default -Platform windows -Machine main-windows
```

Replace placeholders locally, then select the filename without `.jsonc` using `-Machine`. `-MachineFile` remains available for an exceptional explicit path. The same command generates the portable named profile and the selected computer's `build/global/settings.json`; manually merge the latter into **Preferences: Open Application Settings (JSON)**. In particular, Todo Tree's confirmed working Windows ripgrep path is machine-specific; no portable `"rg"` override is present in Default.

## Tests

Install Pester only if needed:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
```

Run the isolated suite:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed -CI"
```

## Installer status

Direct installation into VS Code is intentionally deferred. `.code-profile` generation is an export only and never invokes import. The composer never edits VS Code user data, profile storage, extensions, Settings Sync, or operating-system configuration. Settings Sync remains the primary cross-machine delivery mechanism for imported active profiles.

See [Complete usage guide](docs/USAGE.md), [Composer details](docs/COMPOSER.md), [Architecture](docs/ARCHITECTURE.md), [Main-profile ownership audit](docs/audits/2026-07-22-main-profile-ownership.md), [Portability](docs/PORTABILITY.md), [Migration](docs/MIGRATION.md), and the sanitized [historical extension reference](reference/extensions/README.md).
