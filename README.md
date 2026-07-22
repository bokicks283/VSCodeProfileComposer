# VS Code Profile Composer

This repository contains reusable VS Code settings and extension components plus a safe PowerShell 7 composer. One command validates the source model and materializes a complete profile without reading or changing the user's VS Code installation.

For a complete first-run walkthrough, profile-selection guide, import procedure, Settings Sync precautions, maintenance workflow, and troubleshooting reference, start with [Complete usage guide](docs/USAGE.md).

## Quick start

Requirements:

- PowerShell 7.0 or newer (`pwsh`)
- Git, optional, for recording the current commit in manifests
- Pester 5.5 or newer, only for running the test suite

The composer has no external runtime dependencies and never installs modules automatically.

```powershell
# Validate every component and recipe.
pwsh ./scripts/Compose-Profile.ps1 -Validate

# Compose one profile.
pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows

# Compose with a private machine-local overlay.
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -MachineFile ./machine/local/windows.jsonc

# Compose every valid recipe.
pwsh ./scripts/Compose-Profile.ps1 -All -Platform windows

# Compose and create a file for manual import through VS Code Profiles.
pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows -ExportCodeProfile

# Inspect inputs and planned output without writing build files.
pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows -ExportCodeProfile -DryRun
```

Warnings are informational by default. Add `-Strict` to make warnings fail validation or composition.

## Repository model

```text
Suggested Baseline
→ recipe components in declared order
→ optional profiles/<id>.settings.jsonc override
→ platform/<platform>.jsonc
→ optional machine-local settings file
```

Later layers win. Settings objects merge recursively, while scalar values, arrays, and null values replace earlier values. Extension IDs are validated and deduplicated case-insensitively in first-appearance order. Keybinding arrays are concatenated unchanged; identical objects produce warnings but remain in the output.

Workspace settings are not materialized into personal profiles. `workspace-examples/` remains project guidance only.

## Output and safety

Composition writes to `build/profiles/<id>/`:

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

`overrides.json` records replaced setting paths, values, and source layers. Values whose paths look sensitive are redacted in reports, while explicitly supplied machine-local values remain intact in the generated `settings.json`.

Repository validation checks recipes, JSONC/YAML structure, extension IDs and duplicates, portable personal paths and likely secrets, requested overlays, ignored machine-local boundaries, profile IDs, and output containment.

## VS Code profile export

Add `-ExportCodeProfile` to one-profile or `-All` composition. For example, Default writes `build/profiles/default/Default.code-profile`; Unreal writes `build/profiles/unreal/Unreal-Engine.code-profile`. The export contains the fully composed settings, recipe-owned extension identifiers, and generated keybindings. VS Code handles extension acquisition during its normal import workflow—composition never installs extensions.

For a portable export, omit `-MachineFile`. Supplying a machine overlay includes those explicitly requested settings and classifies the export as `machine-overlay-included`, so it is intended for the same or a compatible machine.

Import manually:

```text
File → Preferences → Profiles
→ New Profile dropdown
→ Import Profile...
→ Select the generated .code-profile
→ Review contents
→ Create Profile
```

UI placement is not composed. After import, customize the profile UI in VS Code. VS Code owns and syncs the resulting live UI state. Review every import preview: re-importing may create a profile or replace selected profile resources according to VS Code's current import workflow.

`components/suggested-baseline/keybindings.jsonc` is currently absent, so current exports correctly carry an empty custom-keybinding array. Add repository-owned bindings there when they are ready; the composer never reads live user keybindings.

## Machine-local setup

Copy the appropriate example and keep the result ignored:

```powershell
Copy-Item ./machine/windows.example.jsonc ./machine/local/windows.jsonc
```

Replace placeholders locally, then pass the file with `-MachineFile`. In particular, Todo Tree's confirmed working Windows ripgrep path is machine-specific; no portable `"rg"` override is present in Suggested Baseline.

## Tests

Install Pester only if needed:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
```

Run the isolated suite:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
```

## Installer status

Direct installation into VS Code is intentionally deferred. `.code-profile` generation is an export only and never invokes import. The composer never edits VS Code user data, profile storage, extensions, Settings Sync, or operating-system configuration. Settings Sync remains the primary cross-machine delivery mechanism for imported active profiles.

See [Complete usage guide](docs/USAGE.md), [Composer details](docs/COMPOSER.md), [Architecture](docs/ARCHITECTURE.md), [Portability](docs/PORTABILITY.md), [Migration](docs/MIGRATION.md), and the sanitized [historical extension reference](reference/extensions/README.md).
