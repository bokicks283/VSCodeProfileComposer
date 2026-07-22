# Architecture

## Components and profiles

A component is a focused reusable unit with portable `settings.jsonc`, an extension list, and ownership documentation. Every focused component can participate in a standalone profile when combined with `default`.

A profile is an explicit YAML recipe. Profiles do not inherit other profiles. The composer parses the narrow current recipe schema and rejects unsupported YAML structures.

## Layers

```text
Global settings owned by VS Code's built-in Default profile
→ recipe components in declared order
→ optional portable profile override
→ platform settings
→ machine-local settings
```

The global layer is generated separately under `build/global/`; it is not merged into named profiles. The composer materializes the remaining profile layers exactly in order. Workspace settings stay separate and are never appended to a personal profile. Manual VS Code profile import and, when deliberately enabled, Settings Sync remain the runtime delivery mechanisms.

## Global settings

`global/settings.jsonc` owns settings intentionally configured through `workbench.settings.applyToAllProfiles`. VS Code stores their effective values in its built-in Default profile and ignores duplicate values in named profile settings. Repository validation requires each global value to appear exactly once in the apply-to-all list and rejects those settings from components, profile overrides, and platform overlays.

`build/global/settings.json` is a reviewable manual-merge artifact. The composer does not write the live Application Settings file.

## Default shared base

Default is the shared daily-driver foundation for common repository formats, source browsing, general terminal behavior, routine shell-language work, and the user's expected cross-profile tools.

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

Ignored `machine/local/<machine-id>.jsonc` files contain absolute executable paths, SDK roots, compiler paths, credentials, database connections, module paths, remoting endpoints, and device tuning. `-Machine <machine-id>` makes the target explicit; `-ListMachines` shows locally available IDs.

## Workspace settings

Repositories own generated-folder exclusions, include paths, compile commands, team formatter policy, PSScriptAnalyzer/Pester rules, module paths, database schema/migration policy, and project-specific extension behavior.

## Generated artifacts

`scripts/Compose-Profile.ps1` materializes reviewable artifacts under ignored `build/global/` and `build/profiles/`. When explicitly requested with `-ExportCodeProfile`, it also creates a manual-import `.code-profile` containing composed settings, extension identifiers, and keybindings. `-UiStateFromProfile` may pass through one opaque `globalState` snapshot from a manually exported private profile; the composer never reads live VS Code state, interprets or merges that payload, or maintains UI inheritance. It does not import profiles, install extensions, or control Settings Sync. Source components, global settings, and recipes remain canonical.
