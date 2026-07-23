# Architecture

## Components and profiles

A component is a focused reusable unit with portable `settings.jsonc`, an extension list, and ownership documentation. `composer.jsonc` names the shared default component; it currently points to `default`.

A profile is an explicit YAML recipe. Profiles do not inherit other profiles. The composer parses the narrow current recipe schema and rejects unsupported YAML structures.

## Layers

```text
Named profile: recipe components in declared order
→ optional recipe settings removals and recursive/exact overrides
→ optional recipe extension and keybinding operations
→ platform settings

Built-in Default/application settings: global settings
→ explicitly selected machine-local settings
```

The global and selected machine layers are generated separately under `build/global/`; they are not merged into named profiles. Every selected machine key is added to both `workbench.settings.applyToAllProfiles` and `settingsSync.ignoredSettings`. The composer removes those keys from named-profile output so VS Code has one unambiguous owner: the selected computer's built-in Default profile. Workspace settings stay separate and are never appended to a personal profile. Manual VS Code profile import and Settings Sync remain the runtime delivery mechanisms.

## Global settings

`global/settings.jsonc` owns settings intentionally configured through `workbench.settings.applyToAllProfiles`. VS Code stores their effective values in its built-in Default profile and ignores duplicate values in named profile settings. Repository validation requires each global value to appear exactly once in the apply-to-all list and rejects those settings from components, profile overrides, and platform overlays.

`build/global/settings.json` is a reviewable manual-merge artifact. The composer does not write the live Application Settings file.

## Default shared base

The component named by `composer.jsonc` is required exactly once and first in every recipe. Validation enforces this invariant. `ProfileComposer.ps1 default set` changes the configuration and recipe order together through a staged, rollback-safe transaction; this deliberately remains one shared-default rule rather than a general component dependency graph.

Default is the current shared daily-driver foundation for common repository formats, source browsing, general terminal behavior, routine shell-language work, and the user's expected cross-profile tools.

It owns:

- basic PowerShell support through the Microsoft PowerShell extension
- PowerShell, Bash/Zsh shell-script, and Windows batch file associations
- terminal behavior that is portable and not operating-system-specific
- common navigation and formatting commands

Default therefore supports everyday `.ps1`, `.psm1`, `.psd1`, `.sh`, `.bash`, `.zsh`, `.bat`, and `.cmd` work without composing the PowerShell component.

The Microsoft PowerShell placement is provisional: available evidence shows PowerShell language/debug/command activation and prior cross-profile ownership, but no reliable activation-time measurement. Revisit it if later Default measurements show a meaningful cost.

Default deliberately excludes database clients, database language servers, connection explorers, and vendor-specific database extensions.

## Focused components

- `default` is the shared portable and daily-driver base used by every recipe.
- `cpp` owns general C/C++.
- `unreal` owns only Unreal-specific concerns and reuses `cpp`.
- `web` and `python` own their language/workflow behavior without database tooling.
- `powershell` owns only advanced PowerShell development concerns such as Command Explorer, module authoring, dedicated testing/analysis, advanced debugging, and administration tooling.
- `database` owns vendor-neutral SQL tooling.
- `sql-server` owns the official SQL Server extension and reviewed `mssql.*` behavior.
- `mongodb` owns MongoDB-specific language-server and explorer behavior.

## Database composition

```text
Database          = Default + Database
Web + Database    = Default + Web + Database
Python + Database = Default + Python + Database
SQL Server        = Default + Database + SQL Server
MongoDB           = Default + Database + MongoDB
```

Generic and vendor-specific concerns remain separate. PostgreSQL, MySQL/MariaDB, and SQLite are planned only; no empty components are created without reviewed content.

Database tooling is opt-in because extensions may add background services, language servers, connection explorers, extra UI, or retained authentication state. This is an architectural isolation decision, not a claim that every database extension has a measured startup penalty.

## Platform overlays

Committed Windows and Linux files contain reusable OS preferences. Windows prefers PowerShell 7; Linux defaults to Bash and keeps PowerShell optional. Platform defaults are not duplicated in components.

## Machine-local overlays

Ignored `machine/local/<machine-id>.jsonc` files contain absolute executable paths, SDK roots, compiler paths, credentials, database connections, module paths, remoting endpoints, and device tuning. `ProfileComposer.ps1 list-machines` shows locally available IDs; `-Machine <machine-id>` selects one for `validate`, `compose-global`, `compose`, or `compose-all`. Machine settings are composed into `build/global/settings.json`, automatically applied to all profiles, and automatically excluded from Settings Sync. They never enter a named profile or `.code-profile` export.

## Workspace settings

Repositories own generated-folder exclusions, include paths, compile commands, team formatter policy, PSScriptAnalyzer/Pester rules, module paths, database schema/migration policy, and project-specific extension behavior.

## Generated artifacts

`scripts/ProfileComposer.ps1` is the unified command surface. It materializes reviewable artifacts under ignored `build/global/` and `build/profiles/`, lists repository definitions, captures an opaque UI-state seed, synchronizes reviewed exports into recipe deltas, performs safe source-ID/default-ownership transactions, and exposes guarded `vscode` guidance. All documented workflows use its subcommands. `Compose-Profile.ps1` and `Save-ProfileUiState.ps1` remain compatibility wrappers for existing automation only.

When explicitly requested with `-ExportCodeProfile`, composition creates a manual-import `.code-profile` containing composed settings, extension identifiers, and keybindings. UI-state capture may retain one opaque `globalState` snapshot per recipe under ignored `machine/local/ui-state/`; `-UiStateProfile` reuses a stored snapshot and `-UiStateFromProfile` supports a one-off source. When the capture recipe is omitted, only `code --status` is read to resolve one exact recipe match. `sync` instead consumes a manually exported private profile, writes flattened differences only to recipe-specific sidecars, and optionally reconciles application-owned values from the built-in Default `settings.json`. It never assigns a live difference to a shared component because exports contain no source provenance. Sync-ignored machine values are excluded, and the entire repository update is staged, validated, and rollback-safe.

Separately, `vscode list` reads names and opaque profile location IDs from VS Code's version-sensitive profile metadata, and `vscode open` invokes the supported launcher. Ordinary composition still reads no live state. No command interprets UI payloads, maintains UI inheritance, writes the private profile registry, imports/exports/deletes profiles automatically, installs extensions, or controls Settings Sync. Source components, global settings, configuration, recipes, and reviewed recipe sidecars remain canonical.

Sync, rename, and shared-default mutations are prepared and validated in an isolated staging copy. Only the affected source roots are swapped into place; a second validation runs before rollback backups are removed. A collision, I/O failure, or validation failure restores every swapped path.
