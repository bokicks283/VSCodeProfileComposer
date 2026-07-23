# Architecture

## Components and profiles

A component is a focused reusable unit with portable `settings.jsonc`, an extension list, and ownership documentation. `composer.jsonc` names the shared default component; it currently points to `main`.

A profile is an explicit YAML recipe. Profiles do not inherit other profiles. The composer parses the narrow current recipe schema and rejects unsupported YAML structures.

## Layers

```text
Named profile: recipe components in declared order
→ optional recipe settings removals and recursive/exact overrides
→ optional recipe extension and keybinding operations
→ platform settings
→ machine-local application settings
→ workspace settings

Built-in Default/application settings: global settings
→ explicitly selected machine-local settings
```

The global and selected machine layers are generated separately under `build/global/`; they are not merged into named profiles. Every selected machine key is added to both `workbench.settings.applyToAllProfiles` and `settingsSync.ignoredSettings`. The composer removes those keys from named-profile output so VS Code has one unambiguous owner: the selected computer's built-in Default profile. Workspace settings stay separate and are never appended to a personal profile. Manual VS Code profile import and Settings Sync remain the runtime delivery mechanisms.

## Global settings

`global/settings.jsonc` owns settings intentionally configured through `workbench.settings.applyToAllProfiles`. VS Code stores their effective values in its built-in Default profile and ignores duplicate values in named profile settings. Repository validation requires each global value to appear exactly once in the apply-to-all list and rejects those settings from components, profile overrides, and platform overlays.

`ProfileComposer.ps1 fix global` provides a deliberately narrow repair for mechanically safe list problems: create the missing list, retain the first copy of duplicate IDs, and append unlisted values. Missing values and cross-layer conflicts remain human decisions. Repairs use the same staged validation and rollback-safe commit as other source transformations.

`build/global/settings.json` is a reviewable manual-merge artifact. The composer does not write the live Application Settings file.

## Main shared base

The component named by `composer.jsonc` is required exactly once and first in every recipe. Validation enforces this invariant. `ProfileComposer.ps1 default set` changes the configuration and recipe order together through a staged, rollback-safe transaction; this deliberately remains one shared-default rule rather than a general component dependency graph.

Main is the current shared daily-driver foundation for common repository formats, source browsing, general terminal behavior, routine shell-language work, and the user's expected cross-profile tools.

It owns:

- basic PowerShell support through the Microsoft PowerShell extension
- PowerShell, Bash/Zsh shell-script, and Windows batch file associations
- terminal behavior that is portable and not operating-system-specific
- common navigation and formatting commands

Main therefore supports everyday `.ps1`, `.psm1`, `.psd1`, `.sh`, `.bash`, `.zsh`, `.bat`, and `.cmd` work without composing the PowerShell component.

The Microsoft PowerShell placement is provisional: available evidence shows PowerShell language/debug/command activation and prior cross-profile ownership, but no reliable activation-time measurement. Revisit it if later Main measurements show a meaningful cost.

Main deliberately excludes database clients, database language servers, connection explorers, and vendor-specific database extensions.

## Focused components

- `main` is the shared portable and daily-driver base used by every recipe.
- `cpp` owns general C/C++.
- `unreal` owns only Unreal-specific concerns and reuses `cpp`.
- `web` and `python` own their language/workflow behavior without database tooling.
- `powershell` owns only advanced PowerShell development concerns such as Command Explorer, module authoring, dedicated testing/analysis, advanced debugging, and administration tooling.
- `database` owns vendor-neutral SQL tooling.
- `sql-server` owns the official SQL Server extension and reviewed `mssql.*` behavior.
- `mongodb` owns MongoDB-specific language-server and explorer behavior.

## Database composition

```text
Database          = Main + Database
Web + Database    = Main + Web + Database
Python + Database = Main + Python + Database
SQL Server        = Main + Database + SQL Server
MongoDB           = Main + Database + MongoDB
```

Generic and vendor-specific concerns remain separate. PostgreSQL, MySQL/MariaDB, and SQLite are planned only; no empty components are created without reviewed content.

Database tooling is opt-in because extensions may add background services, language servers, connection explorers, extra UI, or retained authentication state. This is an architectural isolation decision, not a claim that every database extension has a measured startup penalty.

## Platform overlays

Committed Windows and Linux files contain reusable OS preferences. Windows prefers PowerShell 7; Linux defaults to Bash and keeps PowerShell optional. Platform defaults are not duplicated in components.

## Machine-local overlays

Ignored `machine/local/<machine-id>.jsonc` files contain absolute executable paths, SDK roots, compiler paths, module paths, and device tuning. Credential-bearing, saved-connection, private-host, certificate, account, and authentication resources are excluded rather than treated as ordinary machine settings. New files use a versioned envelope with stable ID, display name, platform, and optional hostname metadata; legacy plain settings maps remain compatible. `ProfileComposer.ps1 list-machines` shows locally available IDs; `-Machine <machine-id>` selects one for validating, composing, or syncing commands. Machine settings are composed into `build/global/settings.json`, automatically applied to all profiles, and automatically excluded from Settings Sync. They never enter a named profile or `.code-profile` export.

## Workspace settings

Repositories own generated-folder exclusions, include paths, compile commands, team formatter policy, PSScriptAnalyzer/Pester rules, module paths, database schema/migration policy, and project-specific extension behavior.

## Generated artifacts

`scripts/ProfileComposer.ps1` is the unified command surface. It materializes reviewable artifacts under ignored `build/global/` and `build/profiles/`, lists repository definitions, captures an opaque UI-state seed, synchronizes reviewed exports into recipe deltas, performs safe source-ID/default-ownership transactions, and exposes guarded `vscode` guidance. All documented workflows use its subcommands. `Compose-Profile.ps1` and `Save-ProfileUiState.ps1` remain compatibility wrappers for existing automation only.

When explicitly requested with `-ExportCodeProfile`, composition creates a manual-import `.code-profile` containing composed settings, extension identifiers, and keybindings. UI-state capture may retain one opaque `globalState` snapshot per recipe under ignored `machine/local/ui-state/`; `-UiStateProfile` reuses a stored snapshot and `-UiStateFromProfile` supports a one-off source. When the capture recipe is omitted, only `code --status` is read to resolve one exact recipe match.

`sync` consumes a manually exported private profile and uses an explicit
ownership model. It indexes component, selected platform, selected machine, and
explicit profile-local sources; applies the managed router at
`config/ownership-router.jsonc` plus any custom router; classifies nested
values; and groups unresolved items for a terminal decision. Existing exact
ownership wins over managed patterns. Unknown portable items never fall back
to profile JSON. Security classification forces exclusion and machine paths
force the resolved machine owner before strict portability validation. Every
owner/router/UI/global change is staged, validated, committed, and validated
again as one rollback-safe plan.

Separately, `vscode list` reads names and opaque profile location IDs from VS Code's version-sensitive profile metadata, and `vscode open` invokes the supported launcher. Ordinary composition still reads no live state. No command interprets UI payloads, maintains UI inheritance, writes the private profile registry, imports/exports/deletes profiles automatically, installs extensions, or controls Settings Sync. Source components, global settings, configuration, recipes, and reviewed recipe sidecars remain canonical.

Sync, router management, legacy-sidecar migration, global ownership repair,
rename, and shared-default mutations are prepared and validated in an isolated
staging copy. Only the affected source roots are swapped into place; a second
validation runs before rollback backups are removed. A collision, I/O failure,
or validation failure restores every swapped path.

See [Ownership router and repository synchronization](OWNERSHIP-ROUTER.md) for
the schema, precedence, CLI, custom modes, classification overrides, removal
policy, and exit codes.
