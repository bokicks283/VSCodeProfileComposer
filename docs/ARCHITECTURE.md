# Architecture

## Components and profiles

A component is a focused reusable unit with portable `settings.jsonc`, an extension list, and ownership documentation. Every focused component can participate in a standalone profile when combined with `default`.

A profile is an explicit YAML recipe. Profiles do not inherit other profiles. The composer parses the narrow current recipe schema and rejects unsupported YAML structures.

## Layers

```text
Recipe components in declared order
→ optional portable profile override
→ platform settings
→ machine-local settings
```

The composer materializes exactly this order. Workspace settings stay separate and are never appended to a personal profile. Manual VS Code profile import and, when deliberately enabled, Settings Sync remain the runtime delivery mechanisms.

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

Ignored local files contain absolute executable paths, SDK roots, compiler paths, credentials, database connections, module paths, remoting endpoints, and device tuning.

## Workspace settings

Repositories own generated-folder exclusions, include paths, compile commands, team formatter policy, PSScriptAnalyzer/Pester rules, module paths, database schema/migration policy, and project-specific extension behavior.

## Generated artifacts

`scripts/Compose-Profile.ps1` materializes reviewable artifacts under ignored `build/profiles/`. When explicitly requested with `-ExportCodeProfile`, it also creates a manual-import `.code-profile` containing composed settings, extension identifiers, and keybindings. It does not import profiles, install extensions, control Settings Sync, compose UI state, or read live VS Code state. Source components and recipes remain canonical.
