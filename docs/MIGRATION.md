# Migration report

## Source

Reviewed from private `bokicks283/VSCodeOptimizationAudit`, primarily:

- `config/settings/application.jsonc`
- `config/settings/shared-editor.jsonc`
- `config/settings/default.jsonc`
- `config/settings/current-user-settings-fixed.jsonc`
- `config/settings/profiles/unreal.jsonc`
- `config/settings/profiles/powershell.jsonc`
- `config/settings/profiles/web.jsonc`
- `config/settings/profiles/python.jsonc`
- `config/settings/profiles/sql-server.jsonc`
- `config/settings/machine/*.example.jsonc`
- `config/settings/workspaces/american-cartel.example.jsonc`
- `config/profile-components/all-profiles-baseline.txt`
- `config/profile-components/default-global-optional.txt`
- `config/profile-components/cpp-core.txt`
- `config/profile-components/unreal.txt`
- `config/profile-components/sql-server.txt`
- `config/profile-definitions.json`
- `docs/FINAL-EXTENSION-PLACEMENT-PLAN.md`
- `docs/BASE-EXTENSION-STABILITY.md`
- `docs/SETTINGS-AND-KEYBINDINGS-CLEANUP.md`
- related profile design and portability planning

The source repository was reference-only and was not modified.

## Migrated

- reviewed application/editor behavior → the shared Default base
- selected daily-driver preferences and optional tools → the shared Default base
- general `C_Cpp.*` and language blocks → C++
- Unreal extension overlay and planning boundary → Unreal
- initial PowerShell extension behavior → PowerShell
- reviewed Web settings → Web
- reviewed Python/Pylance/environment settings → Python
- PowerShell 7 preference → Windows platform
- Bash default and optional PowerShell → Linux platform
- Unreal and `.trunk` exclusions → Unreal workspace example
- machine path classes → placeholder examples

## Post-migration shell ownership refinement

After the initial migration, shell-language ownership was refined without redoing the repository:

- `ms-vscode.powershell` moved from `components/powershell/extensions.txt` to the then-named Suggested Baseline, which has since been consolidated into Default.
- PowerShell file recognition expanded from `.ps1` to `.ps1`, `.psm1`, and `.psd1`.
- Built-in shell-script associations were added for `.sh`, `.bash`, and `.zsh`.
- Built-in Windows batch associations were added for `.bat` and `.cmd`.
- `terminal.explorerKind`, persistent-session scrollback, and shell-integration environment reporting were classified as portable cross-profile terminal behavior and now live in Default.
- Command Explorer remained in the PowerShell component as an advanced development preference.
- The PowerShell recipe display name changed to `PowerShell Development`; every recipe now begins with the shared Default component.

The Microsoft PowerShell extension placement is provisional. Available audit evidence showed prior cross-profile ownership and activation on PowerShell language/debug/commands rather than eager startup, but no reliable timing measurement. No item was left in the advanced component because of a proven performance cost.

## Post-migration database ownership refinement

Database ownership was refined without redoing the migration:

- Confirmed the shared Default base contains no database settings, clients, language servers, or connection explorers.
- Confirmed Web and Python were already database-independent.
- Moved the previously reviewed generic SQLTools extension into a new opt-in `database` component.
- Preserved the five reviewed `mssql.*` behavior settings in a focused `sql-server` component.
- Added the official `ms-mssql.mssql` extension to the SQL Server component.
- Preserved `mongodbLanguageServer.maxNumberOfProblems` in a focused `mongodb` component.
- Added `mongodb.mongodb-vscode` to the MongoDB component.
- Added explicit Database, Web + Database, Python + Database, SQL Server, and MongoDB recipes.
- Default remains database-free; database tooling is added only through explicit focused components.

The old source settings contained live connection-profile metadata. No connection object, connection group, host, database name, username, password, token, certificate, account ID, private cloud resource, or authentication cache was copied or reproduced.

`mdb.mcp.server` remains deferred because its desired ownership and cross-machine behavior are unclear. SQLTools vendor drivers, MySQL autocomplete, Azure Functions SQL bindings, and SQL database-project tooling also remain deferred or project-specific to avoid overlapping clients and speculative components.

## Transformed

- Generated-file headers were removed because destination files are manually curated.
- Personal spell-check dictionaries were excluded.
- The source global extension set was reduced to a reviewed shared Default set.
- Measurement-pending and known-bug extensions were documented rather than forced into shared Default.
- The unreliable portable Todo Tree `"rg"` override was removed. The confirmed Windows path shape remains a placeholder example, while real values belong only in ignored machine-local overlays.
- C++ memory and workspace-symbol tuning were classified as machine/performance decisions.
- Web framework settings were kept together for MVP only where useful.
- Unreal settings remain minimal because the current reviewed fragment is only a planning stub.
- Database settings were separated into generic, SQL Server, and MongoDB ownership without carrying connection data into the public repository.

## Default base consolidation

The former `suggested-baseline` component was merged into `default` after the user confirmed that both extension groups should be available in every profile. Every recipe now begins with `default`, and the standalone Default recipe contains only that component.

The merge preserved the former Baseline-then-Default order inside the consolidated settings and extension files. Focused components still apply afterward, so their later settings retain precedence. The redundant `components/suggested-baseline/` directory and recipe references were removed.

## Intentionally retired

- `trunk.io` VS Code extension
- Trunk editor formatter/settings ownership
- obsolete extension-pack wrappers
- old `vscode-ripgrep`
- duplicate or built-in-replaced import, Markdown, image, XML, theme, and debugger helpers identified by the source review

Trunk CLI, CI, and repository `.trunk` files remain valid external tooling.

## Deferred

- Project Manager and CODEOWNERS pending repair
- All Autocomplete, Shift That, and Path Intellisense pending measurement
- containers and Kubernetes
- PostgreSQL, MySQL/MariaDB, and SQLite component selection
- SQLTools vendor-driver ownership
- `mdb.mcp.server` ownership
- Flask, PHP, Java, C#, Unity, game/minecraft modding
- CMake/Make, CodeLLDB, Jupyter/data science
- framework-specific Web splits
- Python formatter/linter ownership
- advanced PowerShell/Pester/PSScriptAnalyzer/module-publishing/administration configuration
- automatic VS Code installation and deployment (artifact composition is implemented)

## Excluded for privacy or sensitivity

- usernames and personal home paths
- exact compiler, SDK, Unreal Engine, Kubernetes, database, and PowerShell executable paths
- credentials, tokens, connection profiles, connection groups, database hosts, private database names, remoting endpoints, and account state
- certificates, account IDs, authentication caches, and employer-specific cloud resources
- provider-specific AI account/model selections
- raw configuration dumps and historical audit captures

## Generated infrastructure omitted

No generated profile packages, rollout/apply scripts, fragment builders, performance harnesses, temporary workflows, or artifact trees were migrated during the ownership refinements. The later unified CLI adds a reviewed `sync` transaction for manually exported profiles; it creates recipe-specific deltas and does not retroactively treat flattened historical exports as component sources.
