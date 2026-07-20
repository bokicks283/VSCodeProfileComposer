# Automated profile composer

## Overview

`scripts/Compose-Profile.ps1` is the single supported entry point. It validates and composes repository-owned artifacts only. Runtime composition requires PowerShell 7 and built-in .NET APIs; YAML support is intentionally limited to the current recipe schema, so no YAML module is required.

## Commands

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Validate
pwsh ./scripts/Compose-Profile.ps1 -Profile default
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -MachineFile ./machine/local/windows.jsonc
pwsh ./scripts/Compose-Profile.ps1 -All -Platform windows
pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows -DryRun
pwsh ./scripts/Compose-Profile.ps1 -Profile default -Platform windows -ExportCodeProfile
pwsh ./scripts/Compose-Profile.ps1 -All -Platform windows -ExportCodeProfile
```

Use `-Strict` when warnings, including duplicate extension declarations, should fail the command. Ordinary composition fails only on errors.

## Inputs and order

For each recipe, the composer reads composable files in this order:

1. Component `settings.jsonc`, `extensions.txt`, and `keybindings.jsonc` files in declared recipe order.
2. Optional portable `profiles/<profile-id>.settings.jsonc`.
3. Optional `platform/<platform>.jsonc`.
4. Optional explicitly supplied machine settings file.

Missing component input files are valid. Missing explicitly requested platform or machine overlays are errors. README files and workspace examples are never composed.

The recipe parser accepts the repository's narrow schema:

```yaml
name: Unreal Engine
components:
  - suggested-baseline
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

`components/suggested-baseline/keybindings.jsonc` is currently absent, so present exports use VS Code's encoded empty-array representation. The composer does not infer or read the user's live keybindings.

The format has no identifiable schema version, so the manifest records `schemaVersion: "unversioned"` plus the VS Code version and commit used for verification. On import, VS Code reviews the resources and resolves/installs extension identifiers through its normal profile-import workflow.

The export deliberately has no `globalState` resource. UI placement is not composed. After import, customize the profile UI in VS Code. VS Code owns and syncs the resulting live UI state. Accidental `globalState` or `ui-state` source files fail repository validation.

Portable export:

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -ExportCodeProfile
```

Same-machine or compatible-machine export with explicit local settings:

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -MachineFile ./machine/local/windows.jsonc -ExportCodeProfile
```

Machine values are included in the settings payload, but never copied into export metadata. The manifest records `portable` or `machine-overlay-included`, the export filename and SHA-256 hash, `managed-by-vscode` UI policy, and `manual-vscode-profile-import` import method.

Import through VS Code:

```text
Open Profiles
→ Import Profile
→ Select the generated .code-profile
→ Review contents
→ Create Profile
```

Review the import preview. Re-import behavior can create or replace profile resources depending on the selected VS Code workflow; the composer does not automate that choice.

## Validation and security

Repository validation detects missing or duplicate recipe components, invalid/unsupported YAML, invalid JSONC roots, invalid and duplicate extension IDs, missing requested overlays, tracked `machine/local/` data, common personal home paths in portable settings, likely portable secrets, duplicate or unsafe profile IDs, unsafe export filenames, unsupported UI-state sources, and output paths outside `build/profiles/`.

Machine example placeholders are parsed but are excluded from portable-component path violations. Real values belong only in ignored `machine/local/` files. Reports use repository-relative paths where possible and do not expose values from sensitive-looking setting paths.

## Safe replacement and recovery

The composer writes the six core files and any requested export into a unique temporary directory under `build/profiles/`, reparses generated JSON (including nested export resources), hashes the completed artifacts, and only then swaps the target profile directory. If validation or generation fails, the previous target and export remain unchanged. If replacement itself fails after moving the old target aside, the composer attempts to restore it before surfacing the error.

Recomposition affects only the selected generated profile directory. `-DryRun` creates no build directory or files.

## Testing

Tests require Pester 5.5 or newer and use isolated temporary repositories:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed"
```

The suite covers recipe and JSONC parsing, validation, every merge mode, redaction, overlay order, safe replacement, failure preservation, dry run behavior, output structure, current core recipes, export schema/resources, portability metadata, hashes, filename containment, and the no-UI-state policy.

## Troubleshooting

- `invalid-jsonc`: fix the named source; comments and trailing commas are supported, malformed strings and delimiters are not.
- `invalid-yaml`: keep the recipe to `name` plus an indented `components` list.
- `missing-platform-overlay` or `missing-machine-overlay`: check the explicit argument. Relative machine paths resolve from the repository root.
- `portable-absolute-path`: move the setting into `machine/local/` and pass it explicitly.
- `invalid-export-filename`: keep the profile display name free of path separators, traversal sequences, and reserved Windows names.
- `unsupported-ui-state-source`: remove the file; UI state belongs to the imported live VS Code profile.
- strict-mode warning failure: rerun without `-Strict` to inspect an otherwise valid build, or resolve the warning at its source.

## Installer and rollback status

No installer is included. Export generation never discovers or writes live VS Code storage and never imports automatically, so no VS Code rollback is needed. Delete ignored `build/` output to discard generated artifacts, or simply recompose from canonical sources.

The locally installed `code --help` exposes `--profile <profileName>` for opening or creating a named profile, but exposes no supported command for importing composed settings, keybindings, or a complete profile package. Direct apply therefore remains deferred rather than editing undocumented profile databases. The next step is to re-evaluate official CLI support for profile import; any implementation must be explicit, backup-first, reversible, and separate from ordinary composition.
