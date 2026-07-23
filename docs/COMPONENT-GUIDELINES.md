# Component guidelines

## DRY ownership

A setting or extension belongs in the smallest reusable component that fully explains why it exists. Larger profiles reference that component rather than copying it.

Live `.code-profile` exports are flattened and contain no component provenance. The `sync` command therefore records tested differences as recipe-specific sidecars. Promote a synchronized setting, extension, or keybinding into a shared component only after deciding that every recipe using that component should inherit it; then remove the redundant recipe operation and validate all affected recipes.

## Standalone usability

Every focused component must work in a recipe with `main`.

## Settings ownership

- General editor and portable terminal behavior → Main
- Basic PowerShell, Bash/Zsh shell-script, and Windows batch support → Main
- Cross-profile daily-driver behavior and extensions → Main
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

Basic language support must not be duplicated in an advanced component. The PowerShell component may assume the Microsoft PowerShell extension is already available from Main.

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

Do not duplicate database extension IDs across Database, SQL Server, MongoDB, Web, Python, and Main without a documented reason.

A frequently used extension may belong in Main when the user expects it across profiles and available evidence does not show a material cost. Record provisional placement and revisit it after representative measurements rather than claiming unmeasured performance.

## Keybinding ownership

Portable editor and commands supplied by shared Main extensions belong in `components/main/keybindings.jsonc`. Commands supplied by focused extensions belong in the same focused component as the extension. Preserve explicit `-command.id` entries created when replacing a default binding, and keep `when` clauses so overlapping keys remain deterministic.

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
