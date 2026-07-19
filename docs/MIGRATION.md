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
- `config/settings/machine/*.example.jsonc`
- `config/settings/workspaces/american-cartel.example.jsonc`
- `config/profile-components/all-profiles-baseline.txt`
- `config/profile-components/default-global-optional.txt`
- `config/profile-components/cpp-core.txt`
- `config/profile-components/unreal.txt`
- `config/profile-definitions.json`
- `docs/FINAL-EXTENSION-PLACEMENT-PLAN.md`
- `docs/BASE-EXTENSION-STABILITY.md`
- `docs/SETTINGS-AND-KEYBINDINGS-CLEANUP.md`
- related profile design and portability planning

The source repository was reference-only and was not modified.

## Migrated

- reviewed application/editor behavior → Suggested Baseline
- selected Default-only preferences and optional tools → Default
- general `C_Cpp.*` and language blocks → C++
- Unreal extension overlay and planning boundary → Unreal
- PowerShell extension behavior → PowerShell
- reviewed Web settings → Web
- reviewed Python/Pylance/environment settings → Python
- PowerShell 7 preference → Windows platform
- Bash default and optional PowerShell → Linux platform
- Unreal and `.trunk` exclusions → Unreal workspace example
- machine path classes → placeholder examples

## Transformed

- Generated-file headers were removed because destination files are manually curated.
- Personal spell-check dictionaries were excluded.
- The source global extension set was reduced to a lighter Suggested Baseline.
- Measurement-pending and known-bug extensions were documented rather than forced into the baseline.
- Todo Tree uses portable `rg`; the confirmed personal Windows path became a private placeholder example.
- C++ memory and workspace-symbol tuning were classified as machine/performance decisions.
- Web framework settings were kept together for MVP only where useful.
- Unreal settings remain minimal because the current reviewed fragment is only a planning stub.

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
- containers, Kubernetes, databases, SQL Server, MongoDB
- Flask, PHP, Java, C#, Unity, game/minecraft modding
- CMake/Make, CodeLLDB, Jupyter/data science
- framework-specific Web splits
- Python formatter/linter ownership
- automated composition and deployment

## Excluded for privacy or sensitivity

- usernames and personal home paths
- exact compiler, SDK, Unreal Engine, Kubernetes, and database executable paths
- credentials, tokens, connection profiles, private hosts, and account state
- provider-specific AI account/model selections
- raw configuration dumps and historical audit captures

## Generated infrastructure omitted

No generated profile packages, rollout/apply scripts, fragment builders, synchronization scripts, reconciliation systems, performance harnesses, temporary workflows, or artifact trees were migrated.
