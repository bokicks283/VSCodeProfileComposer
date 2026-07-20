# Architecture

## Components and profiles

A component is a focused reusable unit with portable `settings.jsonc`, an extension list, and ownership documentation. Every component can participate in a standalone profile when combined with `suggested-baseline`.

A profile is an explicit YAML recipe. Profiles do not inherit other profiles. The composer parses the narrow current recipe schema and rejects unsupported YAML structures.

## Layers

```text
Portable component settings
→ explicit profile recipe
→ platform settings
→ machine-local settings
→ workspace settings
```

The composer materializes this order through the machine-local layer. Workspace settings stay separate. Manual VS Code profiles and Settings Sync remain the runtime delivery mechanism.

## Suggested Baseline

The baseline is the lightweight daily driver for common repository formats, source browsing, general terminal behavior, and routine shell-language work across mixed repositories and machines.

It owns:

- basic PowerShell support through the Microsoft PowerShell extension
- PowerShell, Bash/Zsh shell-script, and Windows batch file associations
- terminal behavior that is portable and not operating-system-specific
- common navigation and formatting commands

Default therefore supports everyday `.ps1`, `.psm1`, `.psd1`, `.sh`, `.bash`, `.zsh`, `.bat`, and `.cmd` work without composing the PowerShell component.

The Microsoft PowerShell placement is provisional: available evidence shows PowerShell language/debug/command activation and prior cross-profile ownership, but no reliable activation-time measurement. Revisit it if later Default measurements show a meaningful cost.

Suggested Baseline and Default deliberately exclude database clients, database language servers, connection explorers, and vendor-specific database extensions.

## Focused components

- `default` adds optional cross-stack daily tools.
- `cpp` owns general C/C++.
- `unreal` owns only Unreal-specific concerns and reuses `cpp`.
- `web` and `python` own their language/workflow behavior without database tooling.
- `powershell` owns only advanced PowerShell development concerns such as Command Explorer, module authoring, dedicated testing/analysis, advanced debugging, and administration tooling.
- `database` owns vendor-neutral SQL tooling.
- `sql-server` owns the official SQL Server extension and reviewed `mssql.*` behavior.
- `mongodb` owns MongoDB-specific language-server and explorer behavior.

## Database composition

```text
Database          = Suggested Baseline + Database
Web + Database    = Suggested Baseline + Web + Database
Python + Database = Suggested Baseline + Python + Database
SQL Server        = Suggested Baseline + Database + SQL Server
MongoDB           = Suggested Baseline + Database + MongoDB
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

`scripts/Compose-Profile.ps1` materializes reviewable artifacts under ignored `build/profiles/`. It does not install them, create exports, control Settings Sync, or read live VS Code state. Source components and recipes remain canonical.
