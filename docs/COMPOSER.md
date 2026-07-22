# Automated profile composer

## Overview

`scripts/Compose-Profile.ps1` is the single supported entry point. It validates and composes repository-owned artifacts only. Runtime composition requires PowerShell 7 and built-in .NET APIs; YAML support is intentionally limited to the current recipe schema, so no YAML module is required.

For a task-oriented walkthrough rather than this technical reference, see [Complete usage guide](USAGE.md).

## Commands

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Validate
pwsh ./scripts/Compose-Profile.ps1 -Global
pwsh ./scripts/Compose-Profile.ps1 -ListMachines
pwsh ./scripts/Compose-Profile.ps1 -Profile default
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -Machine windows
pwsh ./scripts/Compose-Profile.ps1 -All -Platform windows
pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows -DryRun
pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows -ExportCodeProfile
pwsh ./scripts/Compose-Profile.ps1 -All -Platform windows -ExportCodeProfile
```

Use `-Strict` when warnings, including duplicate extension declarations, should fail the command. Ordinary composition fails only on errors.

## Inputs and order

Global settings are owned separately by `global/settings.jsonc` and generated to `build/global/settings.json`. For each named-profile recipe, the composer reads composable files in this order:

1. Component `settings.jsonc`, `extensions.txt`, and `keybindings.jsonc` files in declared recipe order.
2. Optional portable `profiles/<profile-id>.settings.jsonc`.
3. Optional `platform/<platform>.jsonc`.

An optional named machine or explicit machine file is composed separately into the built-in Default/application artifact, not as a fourth named-profile layer.

Missing component input files are valid. Missing explicitly requested platform or machine overlays are errors. README files and workspace examples are never composed.

## Global settings

`global/settings.jsonc` contains `workbench.settings.applyToAllProfiles` and exactly one value for every listed setting. Repository validation rejects duplicates, missing values, unlisted values, and declarations of globally owned settings in components, profile overrides, or platform overlays.

`pwsh ./scripts/Compose-Profile.ps1 -Global` safely generates:

```text
build/global/
├─ settings.json
├─ overrides.json
└─ manifest.json
```

This artifact targets VS Code's built-in Default profile. It is not included in `.code-profile` exports because those create named profiles, where VS Code ignores these values. Apply it manually by merging it into **Preferences: Open Application Settings (JSON)**. `build/global/overrides.json` records any machine value that replaced a portable global default, using the same sensitive-value redaction as profile reports.

Named machine overlays use `machine/local/<id>.jsonc`. `-ListMachines` discovers available IDs and `-Machine <id>` selects one. Each selected machine key is merged into `build/global/settings.json`, appended to `workbench.settings.applyToAllProfiles`, and appended to `settingsSync.ignoredSettings`; a conflicting `-setting.name` force-sync entry is removed. The same key is omitted from named-profile output and exports. The manifests record the ID, selection mode, delivery target, and count without recording machine values. `-MachineFile` remains supported for an explicit path.

The recipe parser accepts the repository's narrow schema:

```yaml
name: Unreal Engine
components:
  - default
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

`components/default/keybindings.jsonc` supplies the portable shared bindings inherited by every recipe. Focused commands are kept with their owning component, such as the SQL Server binding in `components/sql-server/keybindings.jsonc`. The composer does not infer or read the user's live keybindings during composition.

The format has no identifiable schema version, so the manifest records `schemaVersion: "unversioned"` plus the VS Code version and commit used for verification. On import, VS Code reviews the resources and resolves/installs extension identifiers through its normal profile-import workflow.

The export has no `globalState` resource by default. Accidental component-level `globalState` or `ui-state` source files still fail repository validation.

For an explicit one-time starting layout, pass a private VS Code export:

```powershell
pwsh ./scripts/Compose-Profile.ps1 -All -Platform windows -ExportCodeProfile -UiStateFromProfile "C:\private\Composer Default Layout.code-profile"
```

The composer validates the source wrapper and passes only its opaque `globalState` string through unchanged. It does not copy source settings, extensions, keybindings, name, or path, and it does not interpret or merge the UI payload. The manifest records the payload hash and `seed-on-import-then-managed-by-vscode`. Generated profiles receive the same starting snapshot, after which VS Code owns each live layout independently.

For repeatable local use, capture the opaque resource under an ignored profile ID and reuse it:

```powershell
pwsh ./scripts/Save-ProfileUiState.ps1 -Profile default -SourceProfileExport "C:\private\Adjusted Default.code-profile"
pwsh ./scripts/Compose-Profile.ps1 -Profile python-database -Platform windows -ExportCodeProfile -UiStateProfile default
```

The stored file contains only a generic name and `globalState`; its original path and other export resources are discarded. `-UiStateProfile` may seed the same recipe or a different target recipe. Stored UI data is local and private, not canonical component input.

Portable export:

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -ExportCodeProfile
```

Generate a portable profile plus application settings for one named machine:

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -Machine windows -ExportCodeProfile
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

The suite covers recipe and JSONC parsing, validation, every merge mode, redaction, overlay order, safe replacement, failure preservation, dry run behavior, output structure, current core recipes, export schema/resources, portability metadata, hashes, filename containment, and safe local UI-state capture/reuse.

## Troubleshooting

- `invalid-jsonc`: fix the named source; comments and trailing commas are supported, malformed strings and delimiters are not.
- `invalid-yaml`: keep the recipe to `name` plus an indented `components` list.
- `missing-platform-overlay` or `missing-machine-overlay`: check the explicit argument; use `-ListMachines` for named local overlays.
- `global-setting-in-profile-source`: remove the setting from the component, profile override, or platform file and edit it in `global/settings.jsonc`.
- `portable-absolute-path`: move the setting into `machine/local/` and pass it explicitly.
- `invalid-export-filename`: keep the profile display name free of path separators, traversal sequences, and reserved Windows names.
- `unsupported-ui-state-source`: remove the component-level file; starting UI state is accepted only through `-UiStateFromProfile` or a locally stored `-UiStateProfile` seed.
- missing or invalid UI seed: manually export the arranged source profile again and confirm it contains a non-empty `globalState` resource.
- strict-mode warning failure: rerun without `-Strict` to inspect an otherwise valid build, or resolve the warning at its source.

## Installer and rollback status

No installer is included. Export generation never discovers or writes live VS Code storage and never imports automatically, so no VS Code rollback is needed. Delete ignored `build/` output to discard generated artifacts, or simply recompose from canonical sources.

The locally installed `code --help` exposes `--profile <profileName>` for opening or creating a named profile, but exposes no supported command for importing composed settings, keybindings, or a complete profile package. Direct apply therefore remains deferred rather than editing undocumented profile databases. The next step is to re-evaluate official CLI support for profile import; any implementation must be explicit, backup-first, reversible, and separate from ordinary composition.
