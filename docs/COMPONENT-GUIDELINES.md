# Component guidelines

## DRY ownership

A setting or extension belongs in the smallest reusable component that fully explains why it exists. Larger profiles reference that component rather than copying it.

Live `.code-profile` exports are flattened, but known repository values already
have exact owners. `sync` updates those owners directly. New items require an
approved route or grouped decision; choose the smallest reusable component
only when every recipe using it should inherit the item. Profile-local
sidecars are an explicit rare destination, never the fallback.

## Standalone usability

Every focused component must work in a recipe with `main`.

## Settings ownership

- General editor and portable terminal behavior → Main
- Basic PowerShell, Bash/Zsh shell-script, and Windows batch support → Main
- Cross-profile daily-driver behavior and extensions → Main
- General C/C++ → C++
- General C# language support → C#
- CMake workflow → CMake
- Makefile workflow → Makefile
- Unreal-only → Unreal
- Advanced PowerShell development → PowerShell
- Browser/Web → Web
- React-specific authoring aids → React
- General PHP language and debugging support → PHP
- Apache and NGINX configuration-language support → Apache and NGINX
- General Lua language and formatting support → Lua
- Project Zomboid-only authoring and build tooling → Project Zomboid
- General Python → Python
- Generic SQL and vendor-neutral database behavior → Database
- MySQL/MariaDB SQLTools driver behavior → MySQL and MariaDB
- `mssql.*` and SQL Server behavior → SQL Server
- `mongodbLanguageServer.*` and MongoDB behavior → MongoDB
- OS default shell and reusable OS preference → Platform
- Personal executable, module, SDK, or database client path → Machine
- A personal path shared by every recipe using one component → Machine component scope
- A personal path used by only one named profile → Machine profile scope
- Repository policy, Pester/PSScriptAnalyzer rules, database schema/migration policy, and team formatting → Workspace

Basic language support must not be duplicated in an advanced component. The PowerShell component may assume the Microsoft PowerShell extension is already available from Main.

Web, React, Lua, and Python must not absorb database tooling. Database-enabled
variants compose `database` and any required vendor component explicitly.

React recipes explicitly compose both `web` and `react`. Project Zomboid
recipes explicitly compose `lua` and `project-zomboid`, plus `web` only when
the project actually includes browser-facing files.

## Extension ownership

Avoid extension-pack wrappers and duplicate tools. Keep framework-specific and heavy extensions out of broad components unless the MVP explicitly needs them.

Use this database placement rule:

```text
Generic and vendor-neutral → Database
SQL Server-specific        → SQL Server
MongoDB-specific           → MongoDB
MySQL/MariaDB-specific     → MySQL and MariaDB
Machine- or employer-owned → Exclude from portable components
```

Do not duplicate database extension IDs across Database, SQL Server, MongoDB, Web, Python, and Main without a documented reason.

A frequently used extension may belong in Main when the user expects it across profiles and available evidence does not show a material cost. Record provisional placement and revisit it after representative measurements rather than claiming unmeasured performance.

When one profile needs a capability that another consumer of the same base
component does not, create a focused sibling component and list it only in the
recipes that need it. Use profile-local extension removal only for a genuine
exception to otherwise-correct shared ownership; do not use subtraction to
compensate for an overly broad component.

## Keybinding ownership

Portable editor and commands supplied by shared Main extensions belong in `components/main/keybindings.jsonc`. Commands supplied by focused extensions belong in the same focused component as the extension. Preserve explicit `-command.id` entries created when replacing a default binding, and keep `when` clauses so overlapping keys remain deterministic.

## Dependencies

Document conceptual dependencies in profile recipes. Do not implement
inheritance or hidden dependencies. For example, C++ explicitly adds the CMake
and Makefile components, while Unreal explicitly adds C# and omits both native
build-system components.

Vendor-specific database recipes explicitly include both `database` and the vendor component.

The LAMP + LEMP recipe explicitly composes `web`, `php`, `database`,
`mysql-mariadb`, and `apache-nginx`. Runtime installation, service selection,
ports, sockets, document roots, and database connections remain outside the
portable profile.

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
