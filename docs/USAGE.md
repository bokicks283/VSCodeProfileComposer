# Complete usage guide

This guide is the practical, start-to-finish workflow for using and maintaining VS Code Profile Composer without relying on automation outside this repository.

## What the composer does

The composer validates portable repository sources and generates complete profile artifacts under `build/profiles/`. With `-ExportCodeProfile`, it also creates a `.code-profile` file that VS Code can import through its Profiles editor.

The composer never:

- reads or changes live VS Code settings, profiles, extensions, UI state, or Settings Sync;
- imports a profile into VS Code;
- installs or removes extensions;
- copies workspace settings into a personal profile;
- silently reads machine-specific values.

The repository is the source of truth for composed settings, extension identifiers, and reviewed keybindings. VS Code remains the source of truth for live UI placement and other live profile state.

## Requirements

- PowerShell 7.0 or newer, invoked as `pwsh`
- Git, optional at runtime but recommended so manifests include a commit SHA
- Pester 5.5 or newer, only when running tests
- Stable VS Code for manually importing generated `.code-profile` files

Check the required tools from the repository root:

```powershell
pwsh --version
git --version
```

The composer uses built-in PowerShell and .NET functionality. It does not require a YAML or JSONC module.

## Know the available profiles

| Profile ID | Display name | Components |
| --- | --- | --- |
| `default` | Default | Suggested Baseline + Default |
| `cpp` | C++ | Suggested Baseline + C++ |
| `unreal` | Unreal Engine | Suggested Baseline + C++ + Unreal |
| `web` | Web | Suggested Baseline + Web |
| `python` | Python | Suggested Baseline + Python |
| `powershell` | PowerShell Development | Suggested Baseline + PowerShell |
| `database` | Database | Suggested Baseline + Database |
| `web-database` | Web + Database | Suggested Baseline + Web + Database |
| `python-database` | Python + Database | Suggested Baseline + Python + Database |
| `sql-server` | SQL Server | Suggested Baseline + Database + SQL Server |
| `mongodb` | MongoDB | Suggested Baseline + Database + MongoDB |

Default is the general daily profile. PowerShell Development is for advanced module, testing, analysis, debugging, publishing, or administration work. Database profiles are opt-in so database clients and connection explorers do not become part of Default.

You can also list the recipe IDs directly:

```powershell
Get-ChildItem ./profiles/*.yaml | Select-Object -ExpandProperty BaseName
```

## First run

Run all commands from the repository root.

1. Validate the repository without generating anything:

   ```powershell
   pwsh ./scripts/Compose-Profile.ps1 -Validate
   ```

2. Preview the Default build for Windows:

   ```powershell
   pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows -DryRun
   ```

3. Compose Default:

   ```powershell
   pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows
   ```

4. Inspect `build/profiles/default/`. This step does not affect VS Code.

5. When you want a manually importable file, compose again with export enabled:

   ```powershell
   pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows -ExportCodeProfile
   ```

6. Import `build/profiles/default/Default.code-profile` into a new, clearly named VS Code profile. Review the import form before selecting **Create**.

## Command reference

### Validate all repository sources

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Validate
```

Validation checks all known components and recipes. It produces no profile output. Errors return a nonzero exit code; warnings do not fail unless `-Strict` is supplied.

Validate an explicitly selected overlay as well:

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Validate -Platform windows
pwsh ./scripts/Compose-Profile.ps1 -Validate -Platform windows -MachineFile ./machine/local/windows.jsonc
```

### Compose one profile

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows
```

Omit `-Platform` only when no platform overlay is wanted. For normal Windows or Linux use, select the matching committed overlay explicitly.

### Preview without writing

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -ExportCodeProfile -DryRun
```

Dry run reports the recipe, ordered inputs, planned directory, planned export path, and result counts. It does not create or replace generated files.

### Compose every recipe

```powershell
pwsh ./scripts/Compose-Profile.ps1 -All -Platform windows
```

Generate a `.code-profile` for every recipe:

```powershell
pwsh ./scripts/Compose-Profile.ps1 -All -Platform windows -ExportCodeProfile
```

### Treat warnings as failures

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Validate -Strict
pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows -Strict
```

Strict mode is useful before committing source changes. Ordinary composition still reports warnings but fails only on errors.

## Portable versus machine-specific builds

A portable build uses components, an optional profile override, and an optional platform overlay. It does not contain a private machine overlay:

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -ExportCodeProfile
```

Use this form when the export should work on multiple compatible Windows machines.

A machine-specific build explicitly adds a private overlay last:

```powershell
Copy-Item ./machine/windows.example.jsonc ./machine/local/windows.jsonc
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -MachineFile ./machine/local/windows.jsonc -ExportCodeProfile
```

Edit the copied file locally and replace placeholders. Confirm Git ignores it:

```powershell
git check-ignore ./machine/local/windows.jsonc
```

The machine overlay may contain explicitly requested values such as executable or SDK paths. Those values appear in generated settings and in the `.code-profile` settings payload, but sensitive-looking values are redacted from reports and are not copied into export metadata.

An export generated with `-MachineFile` is classified as `machine-overlay-included`. Use it only on the same machine or a compatible machine. Never commit the local overlay or generated export.

## Composition and merge order

The composer applies sources in this order:

```text
recipe components in declared order
→ optional profiles/<profile-id>.settings.jsonc
→ optional platform/<platform>.jsonc
→ optional explicitly supplied machine file
```

Later layers win.

- Settings objects merge recursively.
- Later scalar values, arrays, and null values replace earlier values.
- Settings arrays are not unioned.
- Extension IDs are deduplicated case-insensitively in first-appearance order.
- Keybinding arrays are concatenated in layer order.
- Identical keybinding objects remain in the output and generate warnings.
- Workspace examples are never composed into personal profiles.

Every meaningful settings replacement is recorded in `overrides.json` with its old and new sources. Sensitive-looking values are redacted in reports without changing the generated settings.

## Generated output

For Default with export enabled, the generated directory is:

```text
build/profiles/default/
├─ settings.json
├─ extensions.txt
├─ keybindings.json
├─ manifest.json
├─ overrides.json
├─ validation.json
└─ Default.code-profile
```

The six core files are always generated. The `.code-profile` file is present only when `-ExportCodeProfile` is requested.

- `settings.json` is the merged standard JSON settings object.
- `extensions.txt` contains one deterministic extension ID per line.
- `keybindings.json` is the concatenated standard JSON array.
- `manifest.json` records provenance, counts, validation, hashes, and export metadata.
- `overrides.json` explains setting replacements and duplicate-keybinding warnings.
- `validation.json` records errors, warnings, and informational notices for that build.

Inspect a result without opening VS Code:

```powershell
Get-Content ./build/profiles/default/manifest.json -Raw
Get-Content ./build/profiles/default/validation.json -Raw
Get-Content ./build/profiles/default/overrides.json -Raw
```

Generated output is ignored and disposable. Never edit it as source; make changes in `components/`, `profiles/`, `platform/`, or an ignored machine overlay and recompose.

## Import into VS Code safely

The generated `.code-profile` contains composed settings, extension identifiers, and keybindings. It intentionally omits `globalState`, so it does not compose Activity Bar order, moved or hidden views, side bar placement, panel placement, or similar UI state.

Use VS Code's supported Profiles editor:

1. Open **File > Preferences > Profiles** or use the Manage gear and open **Profiles**.
2. Open the dropdown beside **New Profile** and select **Import Profile...**.
3. Select the generated `.code-profile` file from `build/profiles/<id>/`.
4. Review every preselected resource in the profile creation form.
5. Give the profile a new, recognizable name during testing.
6. Select **Create** only when the preview is correct.
7. Open a representative workspace and verify its terminal, languages, extensions, and keybindings.
8. Customize UI placement normally. VS Code owns that live UI state after import.

Do not silently replace the active Default profile. Start with a new profile so returning to the previous configuration remains easy.

VS Code handles extension acquisition during import. The composer records only recipe-owned identifiers; it does not query locally installed versions or install anything itself.

The export structure was verified against stable VS Code 1.129.1. VS Code does not publish a version field for this template format, so always inspect the import preview after upgrading VS Code.

Official references:

- [Profiles in Visual Studio Code](https://code.visualstudio.com/docs/configure/profiles)
- [Settings Sync](https://code.visualstudio.com/docs/configure/settings-sync)

## Current keybinding behavior

`components/suggested-baseline/keybindings.jsonc` is currently absent, so current exports contain a valid encoded empty keybinding array.

The composer deliberately does not copy live user keybindings. Before adding global bindings, review each one and place only portable, intentional bindings in a component `keybindings.jsonc`. Unresolved or machine-specific bindings should remain live and outside the repository.

## Historical extension reference

The sanitized [Extension Library Staging inventory](../reference/extensions/README.md) preserves 150 extension IDs from the pre-optimization live profile. It is project memory only and is never composed or installed. All currently owned extensions appear in the snapshot; the remaining historical candidates can be reviewed individually after the new profiles have been tested.

Do not copy the historical list wholesale into a component. It includes deliberately retired and deferred tools. When a missing capability is identified, select the smallest correct component and add only the extension that solves the current need.

## Settings Sync and multiple machines

Settings Sync can synchronize settings, keyboard shortcuts, snippets, tasks, UI state, extensions, and profiles. Importing a generated profile and enabling Sync are separate actions.

Use this conservative sequence on a new machine:

1. Compose a portable `.code-profile` without `-MachineFile`.
2. Import it into a new named profile and validate it locally.
3. Customize the live profile's UI.
4. Review the resources enabled in **Settings Sync: Configure** before signing another machine into the same account.
5. Enable Sync only after deciding which live resources should travel between the machines.
6. Recreate machine-only paths locally instead of syncing them as portable settings.

If signing in on another machine produces unexpected changes, do not immediately reset cloud data or overwrite files. Pause further synchronization, identify whether settings, keybindings, extensions, profiles, or UI state changed, inspect **Settings Sync: Show Synced Data**, and take backups before restoring anything.

The composer never reads, writes, pauses, enables, disables, or resets Settings Sync.

## Maintain the repository

### Change an existing profile

1. Find the owning component using `docs/COMPONENT-GUIDELINES.md`.
2. Edit its `settings.jsonc`, `extensions.txt`, or `keybindings.jsonc`.
3. Put a portable one-profile exception in `profiles/<profile-id>.settings.jsonc` only when component ownership would be misleading.
4. Put reusable OS behavior in `platform/windows.jsonc` or `platform/linux.jsonc`.
5. Put private absolute paths and device values in an ignored machine overlay.
6. Validate, dry-run, compose, inspect overrides, and run tests.

### Add an extension

Add one Marketplace-style `publisher.extension` ID per line to the smallest correct component's `extensions.txt`. Blank lines and lines beginning with `#` are ignored. Do not include versions.

### Add keybindings

Create or edit a component `keybindings.jsonc` whose root is an array:

```jsonc
[
  {
    "key": "ctrl+alt+t",
    "command": "workbench.action.terminal.toggleTerminal"
  }
]
```

Files concatenate in composition order. The composer does not attempt semantic deduplication because VS Code keybinding precedence depends on ordered entries and `when` clauses.

### Add a profile recipe

Create `profiles/<id>.yaml` using the supported narrow schema:

```yaml
name: Example Profile
components:
  - suggested-baseline
  - web
```

The filename is the profile ID. Use only letters, numbers, periods, underscores, and hyphens, beginning with a letter or number. Every referenced component directory must exist.

### Keep these items out of portable sources

- credentials, tokens, private keys, connection strings, and saved connections;
- usernames and personal home paths;
- absolute compiler, SDK, engine, database, or executable paths;
- employer-specific resources or account state;
- workspace-owned formatter, linter, build, schema, or generated-folder policy;
- VS Code `globalState` or composed UI layout.

## Testing changes

Install Pester only when it is not already available:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
```

Run validation and the isolated test suite:

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Validate -Strict
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
```

Tests use temporary repositories and do not import profiles or modify VS Code user data.

Before committing, also confirm that generated and machine-local data are ignored:

```powershell
git status --short
```

Do not force-add `build/`, `machine/local/`, or unreviewed `.code-profile` backups.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| `pwsh` is not recognized | Install PowerShell 7 and reopen the terminal. Windows PowerShell 5.1 is not supported. |
| `invalid-yaml` | Keep the recipe to a top-level `name` and indented `components` list. |
| `invalid-jsonc` | Fix the named file. Comments and trailing commas are allowed; malformed strings and delimiters are not. |
| `missing-component` | Correct the recipe ID or add the missing component directory. |
| `missing-platform-overlay` | Use `windows` or `linux`, or add the explicitly requested committed overlay. |
| `missing-machine-overlay` | Check the path. Relative machine paths resolve from the repository root. |
| `portable-absolute-path` | Move the value into `machine/local/` and supply it explicitly. |
| Secret warning | Remove the value from portable sources. Do not rely on report redaction as permission to commit it. |
| Strict mode fails on warnings | Inspect the reported source, resolve it, or rerun without `-Strict` for an informational local build. |
| Import preview looks wrong | Cancel import, inspect generated files and `overrides.json`, fix canonical sources, then recompose. |
| Unexpected changes after Sync | Pause further sync, identify the affected resource, inspect synced-data history, and back up before restoring. |

Composition is temporary-directory-first. If parsing, validation, export creation, or generated-content verification fails, the previous valid target directory is preserved.

## Routine independent workflow

For ordinary maintenance, use this repeatable sequence:

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Validate -Strict
pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows -ExportCodeProfile -DryRun
pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows -ExportCodeProfile
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
git status --short
```

Then inspect the manifest, validation, overrides, and VS Code import preview. Commit only canonical repository sources and documentation—not generated output or private machine data.
