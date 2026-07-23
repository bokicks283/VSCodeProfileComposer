# Complete usage guide

This guide is the practical, start-to-finish workflow for using and maintaining VS Code Profile Composer with repository-safe composition and guarded VS Code profile guidance.

## What the composer does

The composer validates portable repository sources, generates built-in Default settings under `build/global/`, and generates complete named-profile artifacts under `build/profiles/`. With `-ExportCodeProfile`, it also creates a `.code-profile` file that VS Code can import through its Profiles editor. An explicitly supplied private export may seed a one-time starting UI layout.

Ordinary validation and composition never read or change live VS Code data. The opt-in `vscode`, `sync`, and automatic UI-state recipe-selection workflows have narrower permissions:

- `vscode list` reads profile names and opaque location IDs only;
- automatic `capture-ui-state` selection reads `code --status` only;
- `vscode open` invokes the supported `code --profile` option for a verified existing profile;
- `vscode import`, `replace`, and `delete` prepare or verify a reviewed operation but do not perform the final live mutation.
- `sync` reads a manually exported private profile and, unless skipped, the built-in Default/application `settings.json`; it writes only repository sources and ignored local UI seed data.

The CLI never:

- writes VS Code's private profile registry or settings;
- automatically imports or deletes a profile;
- installs or removes extensions;
- enables, disables, resets, or otherwise changes Settings Sync;
- copies workspace settings into a personal profile;
- silently reads machine-specific values.

The repository is the source of truth for composed settings, extension identifiers, and reviewed keybindings. VS Code remains the runtime source of truth for live UI placement and profile state. A reviewed `sync` operation can snapshot that state back into recipe-specific sources and an ignored opaque UI seed; it does not create continuing inheritance.

## Requirements

- PowerShell 7.0 or newer, invoked as `pwsh`
- Git, optional at runtime but recommended so manifests include a commit SHA
- Pester 5.5 or newer, only when running tests
- Stable VS Code for importing generated `.code-profile` files and using the optional `vscode` command group

Check the required tools from the repository root:

```powershell
pwsh --version
git --version
```

The composer uses built-in PowerShell and .NET functionality. It does not require a YAML or JSONC module.

## Know the available profiles

| Profile ID | Display name | Components |
| --- | --- | --- |
| `main` | Main | Main |
| `cpp` | C++ | Main + C++ |
| `unreal` | Unreal Engine | Main + C++ + Unreal |
| `web` | Web | Main + Web |
| `python` | Python | Main + Python |
| `powershell` | PowerShell Development | Main + PowerShell |
| `database` | Database | Main + Database |
| `web-database` | Web + Database | Main + Web + Database |
| `python-database` | Python + Database | Main + Python + Database |
| `sql-server` | SQL Server | Main + Database + SQL Server |
| `mongodb` | MongoDB | Main + Database + MongoDB |

Main is the general daily profile and the shared base for every focused profile. Its 34 extensions are therefore present in all current compositions. PowerShell Development is for advanced module, testing, analysis, debugging, publishing, or administration work. Database profiles are opt-in so database clients and connection explorers do not become part of Main.

You can also list the recipe IDs directly:

```powershell
pwsh ./scripts/ProfileComposer.ps1 list-profiles
```

## First run

Run all commands from the repository root.

1. Validate the repository without generating anything:

   ```powershell
   pwsh ./scripts/ProfileComposer.ps1 validate
   ```

2. Generate the settings owned by VS Code's built-in Default profile for this computer:

   ```powershell
   pwsh ./scripts/ProfileComposer.ps1 compose-global -Machine main-windows
   ```

   Substitute your local machine ID, or omit `-Machine` if the computer has no private overlay. Review `build/global/settings.json`. In VS Code, run **Preferences: Open Application Settings (JSON)** and merge these values into that file. Do not replace unrelated existing settings.

3. Preview the named Main build for Windows:

   ```powershell
   pwsh ./scripts/ProfileComposer.ps1 compose main -Platform windows -DryRun
   ```

4. Compose Main:

   ```powershell
   pwsh ./scripts/ProfileComposer.ps1 compose main -Platform windows
   ```

5. Inspect `build/profiles/main/`. This step does not affect VS Code.

6. When you want a manually importable file, compose again with export enabled:

   ```powershell
   pwsh ./scripts/ProfileComposer.ps1 compose main -Platform windows -ExportCodeProfile
   ```

7. Import `build/profiles/main/Main.code-profile` into a new, clearly named VS Code profile. Review the import form before selecting **Create**. The guided equivalent is:

   ```powershell
   pwsh ./scripts/ProfileComposer.ps1 vscode import main -Platform windows
   ```

## Command reference

Start with built-in help. Every command returns nonzero on invalid arguments,
validation failures, collisions, or unsafe paths.

```powershell
pwsh ./scripts/ProfileComposer.ps1 help
pwsh ./scripts/ProfileComposer.ps1 help rename-component
```

### Validate all repository sources

```powershell
pwsh ./scripts/ProfileComposer.ps1 validate
```

Validation checks all known components and recipes. It produces no profile output. Errors return a nonzero exit code; warnings do not fail unless `-Strict` is supplied.

Validate an explicitly selected overlay as well:

```powershell
pwsh ./scripts/ProfileComposer.ps1 validate -Platform windows
pwsh ./scripts/ProfileComposer.ps1 validate -Platform windows -Machine windows
```

### Repair global ownership metadata

Preview mechanically safe repairs reported by global ownership validation:

```powershell
pwsh ./scripts/ProfileComposer.ps1 fix global -DryRun
```

Apply the staged repair after reviewing the plan:

```powershell
pwsh ./scripts/ProfileComposer.ps1 fix global
```

The command creates a missing `workbench.settings.applyToAllProfiles` array, removes duplicate IDs while preserving their first occurrence, and appends settings that have values in `global/settings.jsonc` but are absent from the array. Added settings preserve their existing file order. The repaired repository must validate before the source file is replaced, and a failed post-write validation rolls it back.

The command deliberately does not invent values for listed settings that have none, remove settings from components or overlays, or decide whether a conflicting value should be global. Those cases fail with an actionable error. Because the JSONC parser does not retain comments, a repair that changes the file rewrites it as normalized JSON; use `-DryRun` and inspect `git diff` before committing.

### Generate built-in Default settings

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose-global
```

This writes `build/global/settings.json`, `overrides.json`, and `manifest.json`. The source is `global/settings.jsonc`. These settings are excluded from named profiles because VS Code applies the built-in Default profile's value everywhere and ignores duplicates.

To change a gray “applied in all profiles” setting, edit `global/settings.jsonc`, regenerate, then merge the changed value into **Preferences: Open Application Settings (JSON)**. You can also change it directly through VS Code's **Apply Setting to all Profiles** action; bring the final value back into the repository source afterward.

This follows VS Code's documented [Apply a setting to all profiles](https://code.visualstudio.com/docs/configure/profiles#_apply-a-setting-to-all-profiles) behavior. **Open User Settings (JSON)** opens the active named profile; **Open Application Settings (JSON)** opens the built-in Default profile that owns these values.

Profiles imported before this split can still contain ignored copies. Re-import a newly generated profile, or open that profile's **User Settings (JSON)** and remove the keys listed in `global/settings.jsonc`. The composer does not edit an existing live profile automatically.

Preview without writing:

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose-global -DryRun
```

Generate the artifact for one computer without composing a named profile:

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose-global -Machine main-windows
```

The composer adds every selected machine key to both `workbench.settings.applyToAllProfiles` and `settingsSync.ignoredSettings`. The value therefore comes from this computer's built-in Default profile, applies in every named profile, and does not travel through Settings Sync. Machine overlays may not edit either ownership list directly.

### Compose one profile

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose unreal -Platform windows
```

Omit `-Platform` only when no platform overlay is wanted. For normal Windows or Linux use, select the matching committed overlay explicitly.

### Preview without writing

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose unreal -Platform windows -ExportCodeProfile -DryRun
```

Dry run reports the recipe, ordered inputs, planned directory, planned export path, and result counts. It does not create or replace generated files.

### Compose every recipe

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose-all -Platform windows
```

Generate a `.code-profile` for every recipe:

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose-all -Platform windows -ExportCodeProfile
```

Seed every generated export from a layout you already arranged and manually exported from VS Code:

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose-all -Platform windows -ExportCodeProfile -UiStateFromProfile "C:\private\Composer Main Layout.code-profile"
```

`-UiStateFromProfile` requires `-ExportCodeProfile`. It never exports from or modifies the running VS Code instance.

Store a manually exported layout for later reuse:

```powershell
pwsh ./scripts/ProfileComposer.ps1 capture-ui-state main "C:\private\Adjusted Main.code-profile"
```

When exactly one active VS Code window has a profile name matching a repository recipe ID or display name, omit the recipe ID:

```powershell
pwsh ./scripts/ProfileComposer.ps1 capture-ui-state "C:\private\Adjusted Python.code-profile"
```

The command reads only `code --status` for this selection. It deduplicates the ID/name match for one recipe, but refuses zero matches, duplicate recipe display names, or different matching recipes across active windows. Supply the explicit recipe ID in those cases. The named Main profile normally matches automatically; use explicit `main` when status discovery is unavailable or ambiguous.

The stored seed is `machine/local/ui-state/main/seed.code-profile`, which is ignored by Git. It contains only the export's opaque `globalState` resource and a generic local name. Preview capture without replacing a prior seed by adding `-DryRun`.

Use the stored Main layout to create the urgent Python + Database profile:

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose python-database -Platform windows -Machine excalibur117-w -ExportCodeProfile -UiStateProfile main
```

`-UiStateProfile` can name any recipe with a stored seed and can seed a different target recipe. To update a layout, arrange that live profile, export it manually again, rerun `capture-ui-state` for its recipe ID, and rebuild. `-UiStateProfile` and `-UiStateFromProfile` are mutually exclusive.

### Treat warnings as failures

```powershell
pwsh ./scripts/ProfileComposer.ps1 validate -Strict
pwsh ./scripts/ProfileComposer.ps1 compose main -Platform windows -Strict
```

Strict mode is useful before committing source changes. Ordinary composition still reports warnings but fails only on errors.

### Shared default ownership

`composer.jsonc` declares the shared default component. Show or change it with:

```powershell
pwsh ./scripts/ProfileComposer.ps1 default show
pwsh ./scripts/ProfileComposer.ps1 default set main -DryRun
```

Setting a new shared default requires an existing component. The command places
it first in every recipe, removes duplicate occurrences, and preserves the
remaining declared order. Validation rejects a missing configured component or
any recipe that omits it, duplicates it, or places it later.

### Rename repository IDs safely

Always inspect the exact plan first:

```powershell
pwsh ./scripts/ProfileComposer.ps1 rename-profile python python-work -DryRun
pwsh ./scripts/ProfileComposer.ps1 rename-component cpp native-cpp -DryRun
```

Profile rename moves the recipe, optional profile settings override, and
ignored stored UI-state seed. Component rename moves the component directory,
updates every ordered recipe reference, and updates `composer.jsonc` when the
component is the shared default. Both operations reject invalid IDs, missing
sources, collisions, and path escapes. They validate a staged repository before
applying a rollback-safe transaction and validate again afterward. They do not
rename or otherwise modify live VS Code profiles.

`Compose-Profile.ps1` and `Save-ProfileUiState.ps1` remain compatible wrappers
for existing automation. New workflows should use `ProfileComposer.ps1`.

### Inspect and guide live VS Code profile management

`<recipe>` is a repository recipe ID such as `python-database`. A live profile name is separate and is supplied with `-LiveProfile` where required.

```powershell
# Read names and opaque location IDs only.
pwsh ./scripts/ProfileComposer.ps1 vscode list

# Open an existing live profile through code --profile.
pwsh ./scripts/ProfileComposer.ps1 vscode open "Python + Database" .

# Compose an importable recipe and print the reviewed import steps.
pwsh ./scripts/ProfileComposer.ps1 vscode import python-database -Platform windows -DryRun
pwsh ./scripts/ProfileComposer.ps1 vscode import python-database -Platform windows

# Verify a live target and prepare its replacement package.
pwsh ./scripts/ProfileComposer.ps1 vscode replace python-database -LiveProfile "Old Python Setup" -Platform windows -DryRun

# Verify a deletion target and print the supported Profiles-editor action.
pwsh ./scripts/ProfileComposer.ps1 vscode delete "Old Python Setup" -DryRun
```

`vscode import` and `replace` imply `-ExportCodeProfile` and accept the normal platform, machine, UI-state, strict, and dry-run composition options. Replace refuses the built-in Default profile and requires an exact, unambiguous live display name. Delete also refuses Default. Neither command edits live storage: export the old profile privately, import and test the generated package, then use **Profiles: Delete Profile** only after verification.

Use `-VSCodeUserDataPath` for a nonstandard stable/Insiders User directory and `-CodeCommand code-insiders` when applicable. These options also make tests fully isolated from real VS Code data.

## Portable profiles and machine-specific application settings

A named-profile build uses components, optional recipe resource operations, and an optional platform overlay. Its `.code-profile` is portable because private machine values are never embedded:

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose unreal -Platform windows -ExportCodeProfile
```

Use this form when the export should work on multiple compatible Windows machines.

To target a computer, explicitly select its private overlay. Create one file per computer; the filename without `.jsonc` is its ID:

```powershell
Copy-Item ./machine/windows.example.jsonc ./machine/local/main-windows.jsonc
Copy-Item ./machine/windows.example.jsonc ./machine/local/gaming-server.jsonc
pwsh ./scripts/ProfileComposer.ps1 list-machines
pwsh ./scripts/ProfileComposer.ps1 compose unreal -Platform windows -Machine main-windows -ExportCodeProfile
```

Edit the copied file locally and replace placeholders. Confirm Git ignores it:

```powershell
git check-ignore ./machine/local/main-windows.jsonc
```

The command produces two ownership-correct artifacts: a portable named profile under `build/profiles/` and machine-specific application settings under `build/global/`. Machine values appear only in `build/global/settings.json`. They are excluded from the named profile and `.code-profile`, even when the same key exists in a component or platform layer.

The profile manifest records the machine ID and routes it to `build/global/settings.json`; `machineOverlayIncluded` remains false and the export remains `portable`. The global manifest records the machine ID and setting count, never its values. Never commit the local overlay or generated output.

`-MachineFile` remains available for backward compatibility and exceptional paths. Do not combine it with `-Machine`.

Machine files are deliberately not synchronized by Git. Their generated setting keys are automatically added to `settingsSync.ignoredSettings`. Recreate the files from committed examples on each computer or store them in a separate secure private backup. You can build for another computer only if its local overlay is present on the current computer.

`global/settings.jsonc` keeps the Todo Tree key ignored even before a machine is selected, and the composer dynamically protects every additional selected machine key. The composer does not otherwise control Sync.

## Composition and merge order

Global and profile settings have separate ownership. Named profiles apply sources in this order:

```text
recipe components in declared order
→ optional profiles/<profile-id>.settings.remove.jsonc
→ optional recursive profiles/<profile-id>.settings.jsonc
→ optional exact profiles/<profile-id>.settings.replace.jsonc
→ optional profiles/<profile-id>.extensions.jsonc and .keybindings.jsonc operations
→ optional platform/<platform>.jsonc
```

Separately, `global/settings.jsonc` is merged with the explicitly selected machine file to generate `build/global/settings.json`. Machine-owned keys are removed from named-profile output so VS Code does not display ignored gray duplicates. Later layers win within each of these two streams.

- Settings objects merge recursively.
- Later scalar values, arrays, and null values replace earlier values.
- Settings arrays are not unioned.
- Extension IDs are deduplicated case-insensitively in first-appearance order.
- Component keybinding arrays are concatenated in layer order; recipe operations can remove/add exact objects or replace the recipe array to preserve a reviewed live order.
- Identical keybinding objects remain in the output and generate warnings.
- Workspace examples are never composed into personal profiles.

Every meaningful settings replacement is recorded in `overrides.json` with its old and new sources. Sensitive-looking values are redacted in reports without changing the generated settings.

## Generated output

For Main with export enabled, the generated directory is:

```text
build/profiles/main/
├─ settings.json
├─ extensions.txt
├─ keybindings.json
├─ manifest.json
├─ overrides.json
├─ validation.json
└─ Main.code-profile
```

The six core files are always generated. The `.code-profile` file is present only when `-ExportCodeProfile` is requested.

Global output is separate:

```text
build/global/
├─ settings.json
├─ overrides.json
└─ manifest.json
```

- `settings.json` is the merged standard JSON settings object.
- `extensions.txt` contains one deterministic extension ID per line.
- `keybindings.json` is the concatenated standard JSON array.
- `manifest.json` records provenance, counts, validation, hashes, and export metadata.
- `overrides.json` explains setting replacements and duplicate-keybinding warnings.
- `validation.json` records errors, warnings, and informational notices for that build.

Inspect a result without opening VS Code:

```powershell
Get-Content ./build/profiles/main/manifest.json -Raw
Get-Content ./build/profiles/main/validation.json -Raw
Get-Content ./build/profiles/main/overrides.json -Raw
```

Generated output is ignored and disposable. Never edit it as source; make changes in `components/`, `profiles/`, `platform/`, or an ignored machine overlay and recompose.

## Import into VS Code safely

The generated `.code-profile` contains composed settings, extension identifiers, and keybindings. It omits `globalState` by default.

When `-UiStateFromProfile` or `-UiStateProfile` is supplied, the composer validates and copies only the source export's opaque `globalState` string. It ignores source settings, extensions, keybindings, display name, and every other resource. It does not inspect individual UI entries, merge layouts, read the running VS Code profile, or record the private source path in the manifest.

The result is copy-on-create behavior: all generated profiles begin with the same captured layout, then diverge normally. Later changes to the source layout do not update existing profiles, and UI contributed by extensions that were not present in the seed uses VS Code's defaults.

Treat both the source and seeded exports as private. `globalState` can contain profile-scoped extension or account-related state. The composer preserves it as supplied and does not attempt unsafe partial redaction. Keep the source outside Git or under an ignored private location, inspect the import preview, and delete generated seeded exports when they are no longer needed.

### Sync tested changes back into the repository

VS Code exports the final flattened profile but does not record which component originally owned each value. The `sync` command therefore writes only recipe-specific deltas and never guesses that a change belongs in Main, Python, Database, or another shared component:

```powershell
# In VS Code first: Profiles → profile overflow menu → Export Profile...

# Preview every repository path that would change.
pwsh ./scripts/ProfileComposer.ps1 sync "C:\private\Adjusted Python.code-profile" -Platform windows -DryRun

# Apply the staged, validated transaction.
pwsh ./scripts/ProfileComposer.ps1 sync "C:\private\Adjusted Python.code-profile" -Platform windows

# If the export name does not match exactly one recipe:
pwsh ./scripts/ProfileComposer.ps1 sync python-database "C:\private\Adjusted DB Profile.code-profile" -Platform windows
```

The command synchronizes settings, extensions, keyboard shortcuts, and the export's opaque UI layout. Settings that differ from component values become exact recipe replacements; missing component settings become recipe removals. Extension and keybinding changes become add/remove operations, while reordered keybindings use an exact recipe array. The UI resource is stored only under ignored `machine/local/ui-state/<recipe>/`.

Unless `-SkipGlobal` is supplied, `sync` also reads the selected VS Code User directory's `settings.json`. It treats `workbench.settings.applyToAllProfiles` as the explicit global ownership list and rewrites `global/settings.jsonc` from those values. Values whose keys are ignored by Settings Sync are considered machine-owned and are skipped; their values are never printed. Use `-VSCodeUserDataPath` for Insiders or a nonstandard User directory.

Because the live file contains no repository comments, a global reconciliation normalizes `global/settings.jsonc` to formatted JSON and cannot preserve its prior comments. The values and ownership order remain reviewable; use `-DryRun` first and inspect the resulting Git diff before committing.

Settings owned by the selected `-Platform` overlay are also excluded from recipe deltas. Update the platform source deliberately when an OS-wide choice changes; the sync summary reports the filtered count.

The source export must include UI State. Use `-SkipUiState` only when intentionally syncing the other resources. Snippet and task resources are rejected because the current composer schema does not own them. Keep the export private: it can contain account or extension state. After a real sync, inspect `git diff`, validate, and compose before committing.

Shared components still require human intent. Once a recipe-specific change proves broadly useful, move it from the generated recipe sidecar into the smallest correct component and remove the redundant sidecar entry.

Use VS Code's supported Profiles editor:

1. Open **File > Preferences > Profiles** or use the Manage gear and open **Profiles**.
2. Open the dropdown beside **New Profile** and select **Import Profile...**.
3. Select the generated `.code-profile` file from `build/profiles/<id>/`.
4. Review every preselected resource in the profile creation form.
5. Give the profile a new, recognizable name during testing.
6. Select **Create** only when the preview is correct.
7. Open a representative workspace and verify its terminal, languages, extensions, and keybindings.
8. Customize UI placement normally. Seeded or not, VS Code owns that live UI state after import.

Do not silently replace the active Default profile. Start with a new profile so returning to the previous configuration remains easy.

### Rebuild, re-import, or delete a test profile

Running the same compose command twice safely replaces only that profile's ignored `build/profiles/<id>/` directory and the generated `build/global/` artifact. The previous generated build is not retained after a successful replacement; canonical inputs and Git history are the recovery path. A failed build preserves the previous valid generated directory.

Rebuilding does not change an already imported live VS Code profile. To test new artifacts, use `vscode import <recipe>` or import the rebuilt `.code-profile` manually and review whether VS Code is creating a new profile or updating selected resources. Keeping a temporary name during debugging makes rollback simple.

To remove a test profile, first run `vscode delete "<name>" -DryRun` to verify the exact metadata target. Then open the VS Code Profiles editor, open that profile's overflow actions, and choose **Delete Profile**. The Command Palette also provides **Profiles: Delete Profile...**. Deleting a live profile does not delete repository sources or generated artifacts. If a workspace keeps selecting a removed or unwanted profile, switch it back to Default; **Developer: Reset Workspace Profiles Associations** clears all saved workspace/profile associations without deleting profiles.

VS Code handles extension acquisition during import. The composer records only recipe-owned identifiers; it does not query locally installed versions or install anything itself.

The export structure was verified against stable VS Code 1.129.1. VS Code does not publish a version field for this template format, so always inspect the import preview after upgrading VS Code.

Official references:

- [Profiles in Visual Studio Code](https://code.visualstudio.com/docs/configure/profiles)
- [Settings Sync](https://code.visualstudio.com/docs/configure/settings-sync)

## Current keybinding behavior

`components/main/keybindings.jsonc` is the canonical shared set inherited by every recipe. It contains portable editor, notebook, panel, Markdown, and cSpell bindings; the current cSpell suggestion shortcut is `Ctrl+Shift+S`. Commands that require a focused extension remain in that extension's owning component; for example, `mssql.rebuildIntelliSenseCache` is in `components/sql-server/keybindings.jsonc`.

The composer does not read live user keybindings during validation or composition. To retain a new customization, review it and add it to the smallest appropriate component. Preserve VS Code's explicit `-command.id` removal entries when they accompany a remapping, because removing them can restore an old default shortcut and create a conflict.

## Historical extension reference

The sanitized [Extension Library Staging inventory](../reference/extensions/README.md) preserves 150 extension IDs from the pre-optimization live profile. It is project memory only and is never composed or installed. All currently owned extensions appear in the snapshot; the remaining historical candidates can be reviewed individually after the new profiles have been tested.

Do not copy the historical list wholesale into a component. It includes deliberately retired and deferred tools. When a missing capability is identified, select the smallest correct component and add only the extension that solves the current need.

For the exact list in one generated profile, open `build/profiles/<id>/extensions.txt`. For the maintainable source list, read the `extensions.txt` files named by that recipe under `components/`; Main is inherited by every recipe. The 150-ID historical snapshot is the fallback comparison list if a capability from the pre-optimization setup appears to be missing. Add one reviewed ID to the smallest owning component, validate, and rebuild—there is no migration or schema change required.

## Settings Sync and multiple machines

Settings Sync can synchronize settings, keyboard shortcuts, snippets, tasks, UI state, extensions, and profiles. Importing a generated profile and enabling Sync are separate actions.

Settings Sync may remain enabled. Use this sequence on each machine:

1. Create that computer's ignored `machine/local/<id>.jsonc`.
2. Compose with `-Machine <id>` so `build/global/settings.json` contains its local values and protects their keys from Sync.
3. Merge `build/global/settings.json` into **Preferences: Open Application Settings (JSON)**.
4. Import the portable `.code-profile` into a named profile and validate it locally.
5. Customize the live profile's UI; VS Code and Settings Sync continue to own that live UI state.
6. Repeat the machine-overlay and application-settings merge on every additional computer.

If signing in on another machine produces unexpected changes, do not immediately reset cloud data or overwrite files. Identify whether settings, keybindings, extensions, profiles, or UI state changed, inspect **Settings Sync: Show Synced Data**, and take backups before restoring anything. The ownership design above does not require turning Sync off.

The composer never writes, pauses, enables, disables, or resets Settings Sync. A deliberate `sync` command may read `settingsSync.ignoredSettings` from application settings only to exclude machine-owned values from tracked sources.

## Collect VS Code diagnostics

For an issue that appears only in a live imported profile:

1. Note the active profile name and reproduce the issue once.
2. Run **Developer: Open Logs Folder** from the Command Palette.
3. Copy the newest timestamped session directory and zip the copy. Include the whole session so renderer, extension-host, Settings Sync, and extension logs remain correlated.
4. For a channel that is visible only in the Output panel, run **Output: Show Output Channels**, select the affected extension, and save or copy that channel separately if its text is absent from the session folder.
5. For intermittent problems, use **Developer: Set Log Level...** for only the affected feature, reproduce briefly, then return the log level to its prior value to avoid oversized logs.

Logs can contain usernames, local paths, repository names, remote hosts, and extension account details. Review the archive before sharing it publicly. The composer does not collect or upload diagnostics.

## Maintain the repository

### Change an existing profile

1. If the setting should use one value in every profile, edit `global/settings.jsonc` and keep it in `workbench.settings.applyToAllProfiles`.
2. Otherwise, find the owning component using `docs/COMPONENT-GUIDELINES.md`.
3. Edit its `settings.jsonc`, `extensions.txt`, or `keybindings.jsonc`.
4. Put a portable one-profile exception in `profiles/<profile-id>.settings.jsonc` only when component ownership would be misleading.
5. Alternatively, export a tested live profile and run `sync ... -DryRun`; review its recipe-specific `.settings.replace`, `.settings.remove`, `.extensions`, and `.keybindings` sidecars before applying.
6. Put reusable OS behavior in `platform/windows.jsonc` or `platform/linux.jsonc`.
7. Put private absolute paths and device values in an ignored named machine overlay.
8. Validate, dry-run, compose, inspect overrides, and run tests.

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

Bindings from `main` appear in every generated profile because every recipe begins with that component. Put extension-specific commands in the component that owns the extension so profiles without that extension do not receive dead shortcuts.

### Add a profile recipe

Create `profiles/<id>.yaml` using the supported narrow schema:

```yaml
name: Example Profile
components:
  - main
  - web
```

The filename is the profile ID. Use only letters, numbers, periods, underscores, and hyphens, beginning with a letter or number. Every referenced component directory must exist.

### Keep these items out of portable sources

- credentials, tokens, private keys, connection strings, and saved connections;
- usernames and personal home paths;
- absolute compiler, SDK, engine, database, or executable paths;
- employer-specific resources or account state;
- workspace-owned formatter, linter, build, schema, or generated-folder policy;
- committed component-level VS Code `globalState` or composed UI layout declarations; use only a private `-UiStateFromProfile` source or ignored `-UiStateProfile` seed when a starting snapshot is wanted.

## Testing changes

Install Pester only when it is not already available:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
```

Run validation and the isolated test suite:

```powershell
pwsh ./scripts/ProfileComposer.ps1 validate -Strict
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
| `missing-machine-overlay` | Run `pwsh ./scripts/ProfileComposer.ps1 list-machines`; confirm `machine/local/<id>.jsonc` exists, or check the explicit `-MachineFile` path. |
| Setting is gray and says it applies to all profiles | Change it in `global/settings.jsonc`, regenerate with `pwsh ./scripts/ProfileComposer.ps1 compose-global`, then merge into **Preferences: Open Application Settings (JSON)**. Do not add it to a component. |
| Machine setting missing from named-profile settings | This is intentional. Run a composing command with `-Machine <id>`, then merge `build/global/settings.json` into **Preferences: Open Application Settings (JSON)**. The value applies to all profiles and is ignored by Settings Sync. |
| Setting is gray and says it cannot be applied while a non-default profile is active | The built-in Default/application scope owns it. It is not being ignored: use **Preferences: Open Application Settings (JSON)** (or briefly activate Default) to change the effective value, then update the repository source. |
| `portable-absolute-path` | Move the value into `machine/local/` and supply it explicitly. |
| Secret warning | Remove the value from portable sources. Do not rely on report redaction as permission to commit it. |
| Sync cannot match the export | Supply the recipe explicitly: `sync <recipe> <export>`. |
| Sync says UI layout is missing | Re-export with **UI State** selected, or intentionally add `-SkipUiState`. |
| Sync cannot find application settings | Pass the intended VS Code User directory with `-VSCodeUserDataPath`, or add `-SkipGlobal`. |
| Strict mode fails on warnings | Inspect the reported source, resolve it, or rerun without `-Strict` for an informational local build. |
| Import preview looks wrong | Cancel import, inspect generated files and `overrides.json`, fix canonical sources, then recompose. |
| Unexpected changes after Sync | Identify the affected resource, inspect **Settings Sync: Show Synced Data**, and back up before restoring or resetting anything. Machine paths should be corrected through the local overlay and Application Settings artifact. |

Composition is temporary-directory-first. If parsing, validation, export creation, or generated-content verification fails, the previous valid target directory is preserved.

## Routine independent workflow

For ordinary maintenance, use this repeatable sequence:

```powershell
pwsh ./scripts/ProfileComposer.ps1 validate -Strict
pwsh ./scripts/ProfileComposer.ps1 compose main -Platform windows -ExportCodeProfile -DryRun
pwsh ./scripts/ProfileComposer.ps1 compose main -Platform windows -ExportCodeProfile
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
git status --short
```

Then inspect the manifest, validation, overrides, and VS Code import preview. Commit only canonical repository sources and documentation—not generated output or private machine data.

When the maintenance started in a live test profile, insert these steps before validation:

```powershell
pwsh ./scripts/ProfileComposer.ps1 sync "C:\private\Adjusted Profile.code-profile" -Platform windows -DryRun
pwsh ./scripts/ProfileComposer.ps1 sync "C:\private\Adjusted Profile.code-profile" -Platform windows
git diff
```
