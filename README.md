# VS Code Profile Composer

A concise, human-readable design and backup repository for portable, composable Visual Studio Code profiles.

This MVP intentionally does **not** contain a profile composer application, deployment scripts, generators, a test harness, or GitHub Actions. VS Code Settings Sync and manual profile management remain the runtime workflow until the core profiles are stable.

## Immediate MVP

The repository contains real configuration for:

- Suggested Baseline
- Default
- C++
- Unreal Engine
- PowerShell
- Web
- Python

Each component owns the smallest reusable settings and extension set that explains why it exists. Profiles are explicit recipes; there is no inheritance.

```text
Default     = Suggested Baseline + Default
C++         = Suggested Baseline + C++
Unreal      = Suggested Baseline + C++ + Unreal
PowerShell  = Suggested Baseline + PowerShell
Web         = Suggested Baseline + Web
Python      = Suggested Baseline + Python
```

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
- PowerShell 7 is preferred on Windows.
- Bash remains the default terminal on Linux; PowerShell is optional there.
- User settings are the normal focus. Workspace settings are reserved for genuine project or team policy.
- The bundled `renderMermaidDiagram` contribution error is deferred and is not addressed here.
- Automation remains deferred until the manual Default, C++, Unreal, PowerShell, Web, and Python profiles are stable.

See [Architecture](docs/ARCHITECTURE.md), [Portability](docs/PORTABILITY.md), and [Migration](docs/MIGRATION.md).
