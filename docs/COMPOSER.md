# Automated profile composer

## Overview

`scripts/ProfileComposer.ps1` is the unified supported entry point. It validates and composes repository-owned artifacts, lists definitions, synchronizes reviewed profile exports, captures explicitly supplied UI state, performs safe repository renames/default-ownership changes, and provides guarded live-profile discovery/guidance. All new workflows should use its subcommands; `Compose-Profile.ps1` and `Save-ProfileUiState.ps1` remain compatible wrappers for existing automation. Runtime composition requires PowerShell 7 and built-in .NET APIs; YAML support is intentionally limited to the current recipe schema, so no YAML module is required.

For a task-oriented walkthrough rather than this technical reference, see [Complete usage guide](USAGE.md).

## Commands

```powershell
pwsh ./scripts/ProfileComposer.ps1 help
pwsh ./scripts/ProfileComposer.ps1 validate
pwsh ./scripts/ProfileComposer.ps1 compose-global
pwsh ./scripts/ProfileComposer.ps1 list-profiles
pwsh ./scripts/ProfileComposer.ps1 list-machines
pwsh ./scripts/ProfileComposer.ps1 compose main
pwsh ./scripts/ProfileComposer.ps1 compose unreal -Platform windows -Machine windows
pwsh ./scripts/ProfileComposer.ps1 compose-all -Platform windows -ExportCodeProfile
pwsh ./scripts/ProfileComposer.ps1 capture-ui-state main "C:\private\Adjusted Main.code-profile"
pwsh ./scripts/ProfileComposer.ps1 sync "C:\private\Adjusted Python.code-profile" -Platform windows -Machine main-windows -DryRun
pwsh ./scripts/ProfileComposer.ps1 vscode list
pwsh ./scripts/ProfileComposer.ps1 vscode import python-database -Platform windows -DryRun
pwsh ./scripts/ProfileComposer.ps1 vscode replace python-database -LiveProfile "Old Python Setup" -DryRun
pwsh ./scripts/ProfileComposer.ps1 rename-profile old new -DryRun
pwsh ./scripts/ProfileComposer.ps1 rename-component old new -DryRun
pwsh ./scripts/ProfileComposer.ps1 default show
pwsh ./scripts/ProfileComposer.ps1 default set main -DryRun
```

Use `-Strict` when warnings, including duplicate extension declarations, should fail the command. Ordinary composition fails only on errors.

## Inputs and order

Global settings are owned separately by `global/settings.jsonc` and generated to `build/global/settings.json`. For each named-profile recipe, the composer reads composable files in this order:

1. Component `settings.jsonc`, `extensions.txt`, and `keybindings.jsonc` files in declared recipe order.
2. Optional `profiles/<profile-id>.settings.remove.jsonc` top-level setting removals.
3. Optional recursive `profiles/<profile-id>.settings.jsonc` overrides.
4. Optional exact-value `profiles/<profile-id>.settings.replace.jsonc` replacements.
5. Optional `profiles/<profile-id>.extensions.jsonc` and `.keybindings.jsonc` recipe operations.
6. Optional `platform/<platform>.jsonc`.

An optional named machine or explicit machine file is composed separately into the built-in Default/application artifact, not as a fourth named-profile layer.

Missing component input files are valid. Missing explicitly requested platform or machine overlays are errors. README files and workspace examples are never composed.

## Global settings

`global/settings.jsonc` contains `workbench.settings.applyToAllProfiles` and exactly one value for every listed setting. Repository validation rejects duplicates, missing values, unlisted values, and declarations of globally owned settings in components, profile overrides, or platform overlays.

`ProfileComposer.ps1 fix global [-DryRun]` repairs the mechanically unambiguous subset of those errors. It creates a missing ownership array, removes repeated IDs while retaining the first occurrence, and appends unlisted value keys in existing file order. It refuses invalid entries, listed keys with no value, and cross-layer ownership conflicts. The repair runs against an isolated staging repository and uses the rollback-safe source transaction. A changed file is normalized to JSON because parser comments cannot be reconstructed.

`pwsh ./scripts/ProfileComposer.ps1 compose-global` safely generates:

```text
build/global/
├─ settings.json
├─ overrides.json
└─ manifest.json
```

This artifact targets VS Code's built-in Default profile. It is not included in `.code-profile` exports because those create named profiles, where VS Code ignores these values. Apply it manually by merging it into **Preferences: Open Application Settings (JSON)**. `build/global/overrides.json` records any machine value that replaced a portable global default, using the same sensitive-value redaction as profile reports.

Named machine overlays use `machine/local/<id>.jsonc`. Schema 1 stores `machine.id`, display name, platform, optional hostnames, and a `settings` object; legacy plain setting maps remain readable. `ProfileComposer.ps1 list-machines` discovers available IDs and `-Machine <id>` selects one for a validating, composing, or syncing subcommand. Each selected machine key is merged into `build/global/settings.json`, appended to `workbench.settings.applyToAllProfiles`, and appended to `settingsSync.ignoredSettings`; a conflicting `-setting.name` force-sync entry is removed. The same key is omitted from named-profile output and exports. The manifests record the ID, selection mode, delivery target, and count without recording machine values. `-MachineFile` remains supported for an explicit path.

The recipe parser accepts the repository's narrow schema:

```yaml
name: Unreal Engine
components:
  - main
  - cpp
  - unreal
```

Unsupported YAML structures fail clearly instead of being interpreted approximately.

## Merge rules

- JSONC input supports line comments, block comments, and trailing commas. Sources remain unchanged.
- Objects merge recursively.
- Later scalar, array, and null values replace earlier values.
- Arrays in settings are never unioned.
- Extensions ignore blank lines and `#` comment lines, validate Marketplace-style IDs, deduplicate case-insensitively, and preserve first appearance.
- Keybinding arrays concatenate in layer order. Identical objects remain present and generate warnings.

Override paths use JSON Pointer notation. Each changed value records its old and new sources and values. Paths containing terms such as password, token, secret, credential, connection string, API key, or private key have both report values replaced with `[REDACTED]`. Redaction does not alter generated settings.

## Generated package

Each `build/profiles/<id>/` directory contains:

- `settings.json` — merged standard JSON object
- `extensions.txt` — one deterministic extension ID per line
- `keybindings.json` — concatenated standard JSON array
- `manifest.json` — provenance, Git SHA, counts, validation summary, and SHA-256 hashes
- `overrides.json` — informational replacements and keybinding duplicate warnings
- `validation.json` — errors, warnings, and informational notices
- `<Display-Name>.code-profile` — optional manual-import artifact when `-ExportCodeProfile` is requested

The manifest hashes all other generated files. It does not hash itself, because a self-hash cannot be embedded stably.

## `.code-profile` export

The optional export follows VS Code's `IUserDataProfileTemplate` JSON representation verified against stable VS Code 1.129.1 (commit `8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8`). The outer object has a display `name` plus JSON-encoded string resources:

- `settings`: `{ "settings": "<generated settings.json text>" }`
- `extensions`: an array of `{ "identifier": { "id": "publisher.extension" } }`; versions and local installation state are not embedded
- `keybindings`: `{ "keybindings": "<generated keybindings.json text>", "platform": <number> }`

`components/main/keybindings.jsonc` supplies the portable shared bindings inherited by every recipe. Focused commands are kept with their owning component, such as the SQL Server binding in `components/sql-server/keybindings.jsonc`. The composer does not infer or read the user's live keybindings during composition.

The format has no identifiable schema version, so the manifest records `schemaVersion: "unversioned"` plus the VS Code version and commit used for verification. On import, VS Code reviews the resources and resolves/installs extension identifiers through its normal profile-import workflow.

The export has no `globalState` resource by default. Accidental component-level `globalState` or `ui-state` source files still fail repository validation.

For an explicit one-time starting layout, pass a private VS Code export:

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose-all -Platform windows -ExportCodeProfile -UiStateFromProfile "C:\private\Composer Main Layout.code-profile"
```

The composer validates the source wrapper and passes only its opaque `globalState` string through unchanged. It does not copy source settings, extensions, keybindings, name, or path, and it does not interpret or merge the UI payload. The manifest records the payload hash and `seed-on-import-then-managed-by-vscode`. Generated profiles receive the same starting snapshot, after which VS Code owns each live layout independently.

For repeatable local use, capture the opaque resource under an ignored profile ID and reuse it:

```powershell
pwsh ./scripts/ProfileComposer.ps1 capture-ui-state main "C:\private\Adjusted Main.code-profile"
pwsh ./scripts/ProfileComposer.ps1 compose python-database -Platform windows -ExportCodeProfile -UiStateProfile main
```

The stored file contains only a generic name and `globalState`; its original path and other export resources are discarded. `-UiStateProfile` may seed the same recipe or a different target recipe. Stored UI data is local and private, not canonical component input.

The recipe ID may be omitted from `capture-ui-state` when exactly one active VS Code profile name in `code --status` matches a recipe ID or display name. Matching is case-insensitive and deduplicated by recipe ID. Zero or multiple recipe matches fail and require the explicit form. Status text is used only for selection and is never stored or printed.

## Synchronizing a tested profile

VS Code has no supported complete profile-export CLI, so synchronization starts with **Profiles: Export Profile...** and a private local `.code-profile` file:

```powershell
pwsh ./scripts/ProfileComposer.ps1 sync "C:\private\Adjusted Python.code-profile" -Platform windows -Machine main-windows -DryRun
pwsh ./scripts/ProfileComposer.ps1 sync "C:\private\Adjusted Python.code-profile" -Platform windows -Machine main-windows
```

The export name automatically selects one exact recipe ID or display name. The
explicit form is `sync <recipe> <export>`. The command indexes existing owners,
applies the managed/custom router, and recursively classifies every value
before constructing changes. Safe absolute and home-derived paths force the
machine owner; secret, connection, account, certificate, private-host, and
authentication resources force exclusion with redacted reporting. It then
validates the final routed plan and synchronizes:

- existing component/platform/machine/profile settings directly;
- new settings and extensions through approved routes or grouped decisions;
- explicit profile-only settings through profile sidecars;
- additive/reordered keybindings without inferring shared removals;
- the opaque `globalState` resource under ignored `machine/local/ui-state/<recipe>/`;
- built-in Default/application values named by the live `workbench.settings.applyToAllProfiles` list.

For routed settings, machine resolution is explicit `-Machine`/`-MachineFile`, then ignored `machine/local/.default-machine`, then one unique platform-compatible definition. Multiple matches never resolve by hostname or path text. A sync `-MachineFile` must resolve under `machine/local/` so it can join the rollback transaction. The route report records add, update, or retain by setting key, destination file, selection mode, and any earlier portable/platform owner without printing the value.

Application settings are read from the selected VS Code User directory. Keys also present in `settingsSync.ignoredSettings` are treated as machine-owned and their values are not copied into tracked settings. A leading `-` means VS Code force-syncs that key and is not treated as machine ownership. `-SkipGlobal` disables application reconciliation; `-SkipUiState` permits an export without UI state.

Global reconciliation rewrites `global/settings.jsonc` as normalized JSON because live application settings carry no repository comments. Preview and review this diff before committing.

Keys already owned by the selected `-Platform` overlay are excluded from recipe deltas. Change reusable OS behavior in `platform/<id>.jsonc`; the sync summary reports how many platform-owned settings were filtered.

Exports are flattened, so unowned items require an explicit route or decision.
They are not assumed to be profile-local. Existing exact repository ownership
is concrete provenance and is updated directly. The selected owners, managed
router persistence, global settings, and ignored UI seed share one staging
repository; only changed roots are swapped. A validation or commit failure
rolls every path back. Repeating the same sync reports no changes. Absence from
one export never deletes shared settings or extensions.

See [Ownership router and repository synchronization](OWNERSHIP-ROUTER.md) for
custom modes, non-interactive unresolved export, route commands, audit/explain,
and detailed exit behavior.

Portable export:

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose unreal -Platform windows -ExportCodeProfile
```

Generate a portable profile plus application settings for one named machine:

```powershell
pwsh ./scripts/ProfileComposer.ps1 compose unreal -Platform windows -Machine windows -ExportCodeProfile
```

Machine values are written only to `build/global/settings.json`; the `.code-profile` remains portable and its manifest records `machineSettingsDelivery: built-in-default-application-settings`. The export manifest also records the filename and SHA-256 hash, UI-state policy, and `manual-vscode-profile-import` import method. Only a UI-seeded artifact is classified `ui-state-seed-included`.

Import through VS Code's Profiles editor:

```text
File → Preferences → Profiles
→ New Profile dropdown
→ Import Profile...
→ Select the generated .code-profile
→ Review contents
→ Create Profile
```

Review the import preview. Re-import behavior can create or replace profile resources depending on the selected VS Code workflow; the composer does not automate that choice.

See the official [VS Code Profiles documentation](https://code.visualstudio.com/docs/configure/profiles) for the current UI workflow. The export schema was verified against the installed stable version named above; because the format has no version field, preview every import after a VS Code upgrade.

## Validation and security

Repository validation detects malformed global ownership, machine attempts to replace composer-owned ownership lists, globally owned settings in profile sources, missing or duplicate recipe components, invalid/unsupported YAML, invalid JSONC roots, invalid and duplicate extension IDs, missing requested overlays, tracked `machine/local/` data, common personal home paths in portable settings, likely portable secrets, duplicate or unsafe profile IDs, unsafe export filenames, unsupported UI-state sources, and output paths outside `build/`.

Machine example placeholders are parsed but are excluded from portable-component path violations. Real values belong only in ignored `machine/local/` files. Reports use repository-relative paths where possible and do not expose values from sensitive-looking setting paths.

## Safe replacement and recovery

The composer writes global and profile artifacts into unique temporary directories under `build/`, reparses generated JSON (including nested export resources), hashes completed artifacts, and only then swaps each target directory. If validation or generation fails, the previous target remains unchanged. If replacement itself fails after moving the old target aside, the composer attempts to restore it before surfacing the error.

Recomposition affects only the selected generated profile directory. `-DryRun` creates no build directory or files.

## Testing

Tests require Pester 5.5 or newer and use isolated temporary repositories:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
```

The suite covers recipe and JSONC parsing, validation, global ownership repair, every merge mode, redaction, overlay order, safe replacement, failure preservation, dry run behavior, output structure, current core recipes, export schema/resources, portability metadata, hashes, filename containment, CLI dispatch and errors, compatibility wrappers, transactional source changes and rollback, guarded live-profile guidance, reviewed reverse synchronization, and safe local UI-state capture/reuse and automatic recipe selection.

## Troubleshooting

- `invalid-jsonc`: fix the named source; comments and trailing commas are supported, malformed strings and delimiters are not.
- `invalid-yaml`: keep the recipe to `name` plus an indented `components` list.
- `missing-platform-overlay` or `missing-machine-overlay`: check the explicit argument; run `pwsh ./scripts/ProfileComposer.ps1 list-machines` for named local overlays.
- `global-setting-in-profile-source`: remove the setting from the component, profile override, or platform file and edit it in `global/settings.jsonc`.
- `portable-absolute-path`: portable source still contains a machine path. For a live export, rerun `sync ... -Machine <id>` so classification can route it before validation; for a hand-edited tracked source, move it into `machine/local/`.
- `sync-machine-local-path`: review the redacted route and select a machine explicitly when local default or unique platform metadata cannot resolve one.
- `sync-sensitive-setting`: remove the credential/private resource from the export or manage it with the owning extension or a dedicated secret store; ordinary machine JSONC is not an approved secret store.
- `invalid-export-filename`: keep the profile display name free of path separators, traversal sequences, and reserved Windows names.
- `unsupported-ui-state-source`: remove the component-level file; starting UI state is accepted only through `-UiStateFromProfile` or a locally stored `-UiStateProfile` seed.
- missing or invalid UI seed: manually export the arranged source profile again and confirm it contains a non-empty `globalState` resource.
- sync reports a missing UI resource: export **UI State** with the profile, or intentionally add `-SkipUiState`.
- sync rejects application settings: use `-VSCodeUserDataPath` for the intended stable/Insiders User directory, or `-SkipGlobal` for a recipe-only reconciliation.
- strict-mode warning failure: rerun without `-Strict` to inspect an otherwise valid build, or resolve the warning at its source.

## Installer and rollback status

No unattended installer or exporter is included. Ordinary export generation never discovers or writes live VS Code storage and never imports automatically. `vscode list` reads only names and opaque location IDs; `vscode open` uses `code --profile` after verifying the name; and import/replace/delete print reviewed Profiles-editor steps without writing live storage. `sync` consumes a manual private export and optionally reads application settings, but writes only validated repository sources and ignored UI seed data. Delete ignored `build/` output to discard generated artifacts, or simply recompose from canonical sources.

The locally installed VS Code 1.130 `code --help` exposes `--profile <profileName>` but no supported command for importing, replacing, listing, or deleting complete profiles. The command group therefore verifies existing names before opening, composes import packages, and keeps final create/delete confirmations in the supported Profiles editor rather than editing undocumented profile databases.
