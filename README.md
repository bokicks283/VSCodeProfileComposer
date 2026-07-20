# VS Code Profile Composer

A concise, human-readable design and backup repository for portable, composable Visual Studio Code profiles.

This MVP intentionally does **not** contain a profile composer application, deployment scripts, generators, a test harness, or GitHub Actions. VS Code Settings Sync and manual profile management remain the runtime workflow until the core profiles are stable.

## Immediate MVP

The core manual-validation priorities are:

- Default
- C++
- Unreal Engine
- Web
- Python

An additional **PowerShell Development** profile remains available for module authoring, Pester, PSScriptAnalyzer, advanced debugging, administration tooling, and other specialized PowerShell work. It is not required for ordinary scripts.

Each component owns the smallest reusable settings and extension set that explains why it exists. Profiles are explicit recipes; there is no inheritance.

```text
Default                = Suggested Baseline + Default
C++                    = Suggested Baseline + C++
Unreal                 = Suggested Baseline + C++ + Unreal
Web                    = Suggested Baseline + Web
Python                 = Suggested Baseline + Python
PowerShell Development = Suggested Baseline + PowerShell
```

## Everyday shell support

Suggested Baseline supports routine work with PowerShell, Bash/Zsh shell scripts, and Windows batch files. Default therefore handles normal editing, navigation, formatting commands, terminal use, and occasional PowerShell debugging without a profile switch.

Recognized everyday shell files include:

```text
.ps1  .psm1  .psd1
.sh   .bash  .zsh
.bat  .cmd
```

The Microsoft PowerShell extension is currently baseline-owned because PowerShell is used frequently, the source audit treated it as cross-profile, and its recorded activation events are PowerShell language/debug/command triggers rather than eager startup activation. This is a provisional MVP placement, not a measured performance conclusion; revisit it if later Default measurements show a meaningful cost.

## Repository model

```text
Portable components
→ profile recipe
→ platform settings
→ machine-local settings
→ workspace settings
```

Later layers conceptually override earlier layers. No merger is implemented yet.

- `components/` — portable, focused settings and extension ownership
- `profiles/` — explicit YAML recipes
- `platform/` — committed OS-specific preferences without personal paths
- `machine/` — placeholder examples plus ignored local overrides
- `workspace-examples/` — project-specific settings examples
- `exports/` — private `.code-profile` backup guidance
- `docs/` — architecture, portability, migration, and deferred plans

## Current deployment workflow

For personal machines:

```text
Install VS Code
→ sign in
→ enable Settings Sync and profile synchronization
→ select the required profile
→ apply the short platform/machine checklist
```

Settings Sync is currently the practical deployment mechanism. This repository is the reviewed design and backup source; manual VS Code profiles remain the runtime source of truth.

Stable profiles should eventually be exported as private `.code-profile` files. Do not commit exports containing credentials, tokens, account state, private connection details, or personal machine paths.

## Important retained decisions

- The `trunk.io` VS Code extension is retired because it measured roughly 15 seconds to activate in the Unreal workspace.
- Trunk CLI, CI use, and repository `.trunk` configuration remain supported.
- `trunk.trunkPath` and `trunk.addToolsToPath` are not required shared settings.
- General terminal behavior and basic shell-language support belong in Suggested Baseline.
- PowerShell 7 is preferred on Windows.
- Bash remains the default terminal on Linux; PowerShell is optional there.
- User settings are the normal focus. Workspace settings are reserved for genuine project or team policy.
- The bundled `renderMermaidDiagram` contribution error is deferred and is not addressed here.
- Automation remains deferred until the core manual profiles are stable.

See [Architecture](docs/ARCHITECTURE.md), [Portability](docs/PORTABILITY.md), and [Migration](docs/MIGRATION.md).
