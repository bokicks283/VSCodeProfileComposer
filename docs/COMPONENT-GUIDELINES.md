# Component guidelines

## DRY ownership

A setting or extension belongs in the smallest reusable component that fully explains why it exists. Larger profiles reference that component rather than copying it.

## Standalone usability

Every focused component must work in a recipe with `suggested-baseline`.

## Settings ownership

- General editor and portable terminal behavior → Suggested Baseline
- Basic PowerShell, Bash/Zsh shell-script, and Windows batch support → Suggested Baseline
- Personal cross-stack optional behavior → Default
- General C/C++ → C++
- Unreal-only → Unreal
- Advanced PowerShell development → PowerShell
- Browser/Web → Web
- General Python → Python
- Generic SQL and vendor-neutral database behavior → Database
- `mssql.*` and SQL Server behavior → SQL Server
- `mongodbLanguageServer.*` and MongoDB behavior → MongoDB
- OS default shell and reusable OS preference → Platform
- Personal executable, module, SDK, or database client path → Machine
- Repository policy, Pester/PSScriptAnalyzer rules, database schema/migration policy, and team formatting → Workspace

Basic language support must not be duplicated in an advanced component. The PowerShell component may assume the Microsoft PowerShell extension is already available from Suggested Baseline.

Web and Python must not absorb database tooling. Database-enabled variants compose `database` and any required vendor component explicitly.

## Extension ownership

Avoid extension-pack wrappers and duplicate tools. Keep framework-specific and heavy extensions out of broad components unless the MVP explicitly needs them.

Use this database placement rule:

```text
Generic and vendor-neutral → Database
SQL Server-specific        → SQL Server
MongoDB-specific           → MongoDB
Machine- or employer-owned → Exclude from portable components
```

Do not duplicate database extension IDs across Database, SQL Server, MongoDB, Web, Python, Suggested Baseline, and Default without a documented reason.

A frequently used extension may belong in Suggested Baseline when available evidence does not show a material Default-profile cost. Record provisional placement and revisit it after representative measurements rather than claiming unmeasured performance.

## Dependencies

Document conceptual dependencies in profile recipes. Do not implement inheritance or hidden dependencies.

Vendor-specific database recipes explicitly include both `database` and the vendor component.

## Platform and machine boundaries

Executable names may be portable when `PATH` lookup is supported. Absolute paths are machine-local. Windows/Linux default terminal selection is platform-owned and must not be copied into components.

Database hosts, saved connection objects, account IDs, authentication caches, certificates, and employer resources are never portable component values.

## Workspace boundaries

Formatters, linters, generated-folder exclusions, toolchains, include paths, framework enablement, Pester configuration, PSScriptAnalyzer policy, schema projects, migrations, and team database connection policy become workspace settings when the repository owns the decision.

## Conflict avoidance

Do not assign multiple default formatters to one language. Do not enable overlapping linters or competing database clients by default. Record unresolved ownership rather than inventing a replacement.

## Performance

Any extension with wildcard activation, eager startup, deep scanning, language servers, project discovery, background indexing, connection explorers, or retained authentication state must justify its component and be measured in representative workspaces.

Language-triggered activation is useful placement evidence but is not equivalent to a measured activation-time result.
